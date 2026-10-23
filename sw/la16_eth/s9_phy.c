/*
 * PHY of the Antminer S9 control board: Broadcom BCM54612E ( ID 0362/5E6x )
 * at MDIO address 1, RGMII to GEM0. U-Boot's S9 device tree uses phy-mode
 * "rgmii-id": the PHY delays both RX and TX clocks ( its power-on default ).
 *
 * lwIP 2.2's xemacpsif only knows Marvell, TI, Realtek and ADI PHYs. With a
 * fixed link speed it writes Marvell page registers, advertises that one
 * speed only, and its 1 s link check ( eth_link_detect() ) calls
 * phy_setup_emacps() again on every link-up, which resets the PHY: the link
 * goes down again right away and never stays up.
 *
 * s9_phy_init() takes the PHY over after xemac_add(): it switches lwIP's link
 * check off, resets the PHY, keeps the RGMII delays on and advertises
 * 10/100/1000. s9_phy_poll() then follows the link and sets the GEM speed,
 * the GEM0 reference clock and the lwIP netif link flag.
 */

#include "xil_io.h"
#include "xil_printf.h"
#ifdef SDT
#include "xiltimer.h"
#else
#include "xtime_l.h"
#endif
#include "lwip/netif.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "s9_phy.h"

extern struct netif *echo_netif;	/* main.c of the template */

#define PHY_ADDR		1
#define PHY_ID1_BROADCOM	0x0362

/* IEEE registers */
#define PHY_BMCR		0x00
#define PHY_BMSR		0x01
#define PHY_ID1			0x02
#define PHY_ID2			0x03
#define PHY_ANAR		0x04
#define PHY_GBCR		0x09
#define BMCR_RESET		0x8000
#define BMCR_ANENABLE		0x1000
#define BMCR_ANRESTART		0x0200
#define BMSR_LINK		0x0004
#define BMSR_ANDONE		0x0020
#define ANAR_ALL		0x0DE1	/* pause + asym. pause, 100/10 FD/HD, IEEE 802.3 */
#define GBCR_1000		0x0300	/* 1000BASE-T FD/HD */

/* Broadcom registers */
#define PHY_AUXCTL		0x18
#define PHY_AUXSTAT		0x19
#define PHY_SHADOW		0x1C
#define AUXCTL_MISC_READ	0x7007	/* select shadow 7 ( misc control ) for reading */
#define AUXCTL_MISC		0x0007
#define AUXCTL_WREN		0x8000
#define AUXCTL_RGMII_SKEW	0x0100	/* RXC delayed against RXD */
#define SHD_CLK_ALIGN		0x03	/* shadow 0x1C / 00011: clock alignment */
#define SHD_WRITE		0x8000
#define SHD_GTXCLK_DELAY	0x0200	/* GTXCLK delayed against TXD */
#define AUXSTAT_HCD(v)		(((v) >> 8) & 7)

/* GEM0 reference clock: IO PLL ( 1000 MHz ) / DIV0 ( 8, ps7_init ) / DIV1 */
#define SLCR_LOCK		0xF8000004u
#define SLCR_UNLOCK		0xF8000008u
#define SLCR_GEM0_CLK_CTRL	0xF8000140u
#define GEM0_BASEADDR		0xE000B000u

static XEmacPs *emac;
static int link_up;
static XTime t_poll;

static u16 phy_rd(u32 reg)
{
	u16 v = 0xFFFF;

	XEmacPs_PhyRead(emac, PHY_ADDR, reg, &v);
	return v;
}

static void phy_wr(u32 reg, u16 v)
{
	XEmacPs_PhyWrite(emac, PHY_ADDR, reg, v);
}

/* At least ms since t. s9_phy_poll() runs every main loop pass: no 64 bit division */
static int elapsed(XTime t, u32 ms)
{
	XTime now;

	XTime_GetTime(&now);
	return now - t >= (XTime)ms * (COUNTS_PER_SECOND / 1000);
}

/* 125 / 25 / 2.5 MHz for 1000 / 100 / 10 Mbit/s */
static void set_gem_clock(u32 mbps)
{
	u32 div1 = mbps == 1000 ? 1 : mbps == 100 ? 5 : 50;
	u32 v;

	if (emac->Config.BaseAddress != GEM0_BASEADDR)
		return;
	Xil_Out32(SLCR_UNLOCK, 0xDF0D);
	v = Xil_In32(SLCR_GEM0_CLK_CTRL);
	v = (v & ~(0x3Fu << 20)) | (div1 << 20);
	Xil_Out32(SLCR_GEM0_CLK_CTRL, v);
	Xil_Out32(SLCR_LOCK, 0x767B);
}

void s9_phy_init(void)
{
	struct xemac_s *xemac = (struct xemac_s *)echo_netif->state;
	xemacpsif_s *xemacps = (xemacpsif_s *)xemac->state;
	u16 id1, id2, misc, clk;
	XTime t;

	/* lwIP's link check returns early on an undefined link state */
	xemacps->eth_link_status = ETH_LINK_UNDEFINED;
	emac = &xemacps->emacps;
	netif_set_link_down(echo_netif);

	id1 = phy_rd(PHY_ID1);
	id2 = phy_rd(PHY_ID2);
	xil_printf("PHY %d: ID %04x/%04x%s\r\n", PHY_ADDR, id1, id2,
		   id1 == PHY_ID1_BROADCOM ? " ( Broadcom )" : " ( not the expected Broadcom PHY )");

	phy_wr(PHY_BMCR, BMCR_RESET);
	XTime_GetTime(&t);
	while ((phy_rd(PHY_BMCR) & BMCR_RESET) && !elapsed(t, 500))
		;

	/* RGMII delays in the PHY ( rgmii-id ): on after reset, made sure here */
	phy_wr(PHY_AUXCTL, AUXCTL_MISC_READ);
	misc = phy_rd(PHY_AUXCTL);
	phy_wr(PHY_AUXCTL, AUXCTL_WREN | AUXCTL_RGMII_SKEW | (misc & ~0x0007u) | AUXCTL_MISC);
	phy_wr(PHY_SHADOW, SHD_CLK_ALIGN << 10);
	clk = phy_rd(PHY_SHADOW) & 0x3FF;
	phy_wr(PHY_SHADOW, SHD_WRITE | (SHD_CLK_ALIGN << 10) | clk | SHD_GTXCLK_DELAY);
	xil_printf("PHY RGMII delay: RX %s, TX %s ( after reset, both on now )\r\n",
		   misc & AUXCTL_RGMII_SKEW ? "on" : "off",
		   clk & SHD_GTXCLK_DELAY ? "on" : "off");

	phy_wr(PHY_ANAR, ANAR_ALL);
	phy_wr(PHY_GBCR, GBCR_1000);
	phy_wr(PHY_BMCR, BMCR_ANENABLE | BMCR_ANRESTART);
	xil_printf("PHY autonegotiation 10/100/1000 started\r\n");
	link_up = 0;
	XTime_GetTime(&t_poll);
}

void s9_phy_poll(void)
{
	u16 bmsr, aux;
	u32 mbps;
	int up, fd;

	if (!emac || !elapsed(t_poll, 250))
		return;
	XTime_GetTime(&t_poll);

	phy_rd(PHY_BMSR);			/* link bit latches low: read twice */
	bmsr = phy_rd(PHY_BMSR);
	up = (bmsr & BMSR_LINK) && (bmsr & BMSR_ANDONE);
	if (up == link_up)
		return;
	link_up = up;
	if (!up) {
		netif_set_link_down(echo_netif);
		xil_printf("Ethernet link down\r\n");
		return;
	}
	aux = phy_rd(PHY_AUXSTAT);
	switch (AUXSTAT_HCD(aux)) {
	case 7: mbps = 1000; fd = 1; break;
	case 6: mbps = 1000; fd = 0; break;
	case 5: mbps = 100;  fd = 1; break;
	case 3: mbps = 100;  fd = 0; break;
	case 2: mbps = 10;   fd = 1; break;
	default: mbps = 10;  fd = 0; break;
	}
	set_gem_clock(mbps);
	XEmacPs_SetOperatingSpeed(emac, (u16)mbps);
	netif_set_link_up(echo_netif);
	xil_printf("Ethernet link up: %d Mbit/s %s duplex%s\r\n", mbps, fd ? "full" : "half",
		   fd ? "" : " ( GEM runs full duplex, expect errors )");
}
