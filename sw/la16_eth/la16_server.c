/*
 * la16 protocol server over TCP ( docs/PROTOCOL_LA16.md ), Antminer S9 build
 * antminer_s9_la16eth.
 *
 * Replaces echo.c of the Vitis "lwIP Echo Server" template: the template's
 * main.c ( lwIP init, DHCP with fallback 192.168.1.10, main loop ) and
 * platform files stay as generated and call print_app_header(),
 * start_application() and transfer_data() of this file.
 *
 * PulseView: driver "la16", conn = tcp-raw/<board IP>/5555.
 *
 * The capture runs in the PL ( la16_regs at 0x43C0_0000 on M_AXI_GP0 ); the
 * result is read from the DDR ring the PL wrote through S_AXI_HP0 and sent
 * as DATA frames. Frames and their meaning are the same as over the UART.
 */

#include <string.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#ifdef SDT
#include "xiltimer.h"	/* XTime, COUNTS_PER_SECOND in the SDT ( unified Vitis ) BSP */
#else
#include "xtime_l.h"
#endif
#include "lwip/err.h"
#include "lwip/tcp.h"
#ifdef __arm__
#include "s9_phy.h"
#else				/* host test ( test/ ): no PHY */
static void s9_phy_init(void) {}
static void s9_phy_poll(void) {}
#endif

#define LA16_TCP_PORT		5555

/* la16_regs */
#define REG_BASE		0x43C00000u
#define R_ID			0x00
#define R_CTRL			0x04
#define R_DIVIDER		0x08
#define R_TOTAL			0x0C
#define R_PRE			0x10
#define R_TRIG_LEVEL		0x14
#define R_TRIG_EDGE		0x18
#define R_STATUS		0x1C
#define R_CAPTURED		0x20
#define R_START			0x24
#define R_RING			0x28
#define R_DDR_BASE		0x2C
#define R_MAX_SAMPLES		0x30
#define R_CFG			0x34
#define R_BASE_HZ		0x38
#define REG_ID_VALUE		0x4C413136u
#define CTRL_ARM		0x1
#define CTRL_ABORT		0x2
#define ST_DONE			(1u << 3)
#define ST_READY		(1u << 4)
#define ST_OVERFLOW		(1u << 5)
#define CFG_LED			(1u << 8)

/* Frames */
#define SYNC			0xA5
#define MAX_PAYLOAD		1024
#define T_IDENT			0x01
#define T_CONFIG		0x02
#define T_ARM			0x03
#define T_ABORT			0x04
#define T_STATUS		0x05
#define R_IDENT			0x81
#define R_ACK			0x82
#define R_STATUS_F		0x83
#define R_DATA			0x84
#define R_TRIGGER		0x85
#define R_END			0x86
#define R_ERROR			0x8F
#define E_CRC			1
#define E_TYPE			2
#define E_CONFIG		3
#define E_BUSY			4
#define END_OVERFLOW		0x01
#define END_ABORTED		0x02
#define END_TIMEOUT		0x04
#define DATA_SAMPLES		510		/* ( 1024 - 4 ) / 2 */
#define STATUS_PERIOD_MS	50

enum state { S_IDLE, S_CAPTURE, S_TRIGGER, S_DATA, S_END };

static struct tcp_pcb *client;
static u8 rx[4096];
static u32 rx_len;

/* Control frames wait here until lwIP has room; DATA is made on demand */
#define TXQ_SIZE 8192
static u8 txq[TXQ_SIZE];
static u32 txq_len;

static enum state st = S_IDLE;
static int configured;
static u32 cfg_div, cfg_total, cfg_pre, cfg_tlm, cfg_tlv, cfg_trm, cfg_tfm, cfg_tmo;
static u32 up_sent, up_start, up_ring, ddr_base, max_samples;
static u8 end_flags, last_code = 0xFF, idle_code;
static XTime t_arm, t_status;

static inline u32 reg_rd(u32 off) { return Xil_In32(REG_BASE + off); }
static inline void reg_wr(u32 off, u32 v) { Xil_Out32(REG_BASE + off, v); }

static u32 ms_since(XTime t)
{
	XTime now;

	XTime_GetTime(&now);
	return (u32)((now - t) / (COUNTS_PER_SECOND / 1000));
}

static u8 crc8(u8 c, const u8 *d, u32 n)
{
	u32 i;
	int b;

	for (i = 0; i < n; i++) {
		c ^= d[i];
		for (b = 0; b < 8; b++)
			c = (c & 0x80) ? (u8)((c << 1) ^ 0x07) : (u8)(c << 1);
	}
	return c;
}

static void wl32(u8 *p, u32 v)
{
	p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24;
}

static u32 rl32(const u8 *p)
{
	return p[0] | (p[1] << 8) | (p[2] << 16) | ((u32)p[3] << 24);
}

/* Build a frame into buf, return its length */
static u32 frame(u8 *buf, u8 type, const u8 *payload, u32 len)
{
	buf[0] = SYNC;
	buf[1] = type;
	buf[2] = len;
	buf[3] = len >> 8;
	if (len)
		memcpy(&buf[4], payload, len);
	buf[4 + len] = crc8(0, &buf[1], 3 + len);
	return len + 5;
}

static void queue(u8 type, const u8 *payload, u32 len)
{
	if (txq_len + len + 5 > TXQ_SIZE)
		return;			/* Host stopped reading; drop */
	txq_len += frame(&txq[txq_len], type, payload, len);
}

static void send_ack(u8 t) { queue(R_ACK, &t, 1); }
static void send_error(u8 e) { queue(R_ERROR, &e, 1); }

static u8 status_code(void)
{
	u32 s = reg_rd(R_STATUS);

	switch (st) {
	case S_CAPTURE: return (s & 7) == 5 ? 4 : (s & 7);
	case S_TRIGGER:
	case S_DATA:
	case S_END: return 4;
	default: return idle_code;	/* 0 idle, 5 done */
	}
}

static void send_status(void)
{
	u8 p[9];

	p[0] = status_code();
	wl32(&p[1], (st == S_CAPTURE) ? reg_rd(R_CAPTURED) :
		(st == S_IDLE) ? 0 : cfg_total);
	wl32(&p[5], cfg_total);
	queue(R_STATUS_F, p, sizeof(p));
	last_code = p[0];
	XTime_GetTime(&t_status);
}

static void send_end(u8 flags)
{
	u8 p[5];

	wl32(p, up_sent);
	p[4] = flags;
	queue(R_END, p, sizeof(p));
	st = S_IDLE;
	idle_code = 5;
	send_status();
}

static void send_ident(void)
{
	static const char strings[] = "la16\0AntMiner S9 Ethernet\0" "0.2";
	u8 p[12 + sizeof(strings)];

	p[0] = 1;			/* protocol version */
	p[1] = 16;			/* channels */
	wl32(&p[2], reg_rd(R_BASE_HZ));
	wl32(&p[6], max_samples);
	p[10] = 0x01;			/* features: edge triggers */
	p[11] = 0x00;
	memcpy(&p[12], strings, sizeof(strings));
	queue(R_IDENT, p, sizeof(p));
}

static void handle_command(u8 type, const u8 *p, u32 len)
{
	u32 total, pre;

	switch (type) {
	case T_IDENT:
		send_ident();
		break;
	case T_STATUS:
		send_status();
		break;
	case T_CONFIG:
		if (st != S_IDLE) {
			send_error(E_BUSY);
			break;
		}
		total = rl32(&p[8]);
		pre = rl32(&p[12]);
		if (len != 32 || p[0] != 0 || (p[1] != 0 && p[1] != 2) ||
				total == 0 || total > max_samples || pre >= total) {
			send_error(E_CONFIG);
			break;
		}
		cfg_div = rl32(&p[4]);
		cfg_total = total;
		cfg_pre = pre;
		cfg_tlm = p[16] | (p[17] << 8);
		cfg_tlv = p[18] | (p[19] << 8);
		cfg_trm = p[20] | (p[21] << 8);
		cfg_tfm = p[22] | (p[23] << 8);
		cfg_tmo = rl32(&p[24]);
		configured = 1;
		send_ack(T_CONFIG);
		break;
	case T_ARM:
		if (st != S_IDLE || !(reg_rd(R_STATUS) & ST_READY)) {
			send_error(E_BUSY);
			break;
		}
		if (!configured) {
			send_error(E_CONFIG);
			break;
		}
		reg_wr(R_DIVIDER, cfg_div);
		reg_wr(R_TOTAL, cfg_total);
		reg_wr(R_PRE, cfg_pre);
		reg_wr(R_TRIG_LEVEL, (cfg_tlv << 16) | cfg_tlm);
		reg_wr(R_TRIG_EDGE, (cfg_tfm << 16) | cfg_trm);
		send_ack(T_ARM);
		reg_wr(R_CTRL, CTRL_ARM);
		st = S_CAPTURE;
		idle_code = 0;
		up_sent = 0;
		end_flags = 0;
		XTime_GetTime(&t_arm);
		break;
	case T_ABORT:
		send_ack(T_ABORT);
		if (st == S_CAPTURE)
			reg_wr(R_CTRL, CTRL_ABORT);
		if (st != S_IDLE)
			send_end(END_ABORTED);
		break;
	default:
		send_error(E_TYPE);
		break;
	}
}

/* Take complete frames out of rx[], resync on 0xA5 */
static void parse_rx(void)
{
	u32 len;

	while (rx_len >= 5) {
		if (rx[0] != SYNC) {
			memmove(rx, rx + 1, --rx_len);
			continue;
		}
		len = rx[2] | (rx[3] << 8);
		if (len > MAX_PAYLOAD) {
			memmove(rx, rx + 1, --rx_len);
			continue;
		}
		if (rx_len < len + 5)
			return;
		if (crc8(0, &rx[1], 3 + len) != rx[4 + len])
			send_error(E_CRC);
		else
			handle_command(rx[1], &rx[4], len);
		rx_len -= len + 5;
		memmove(rx, rx + len + 5, rx_len);
	}
}

/* One DATA frame from the DDR ring, oldest first */
static u32 make_data(u8 *buf)
{
	u8 p[4 + 2 * DATA_SAMPLES];
	u32 n, done, j, chunk, addr;

	n = cfg_total - up_sent;
	if (n > DATA_SAMPLES)
		n = DATA_SAMPLES;
	wl32(p, up_sent);
	for (done = 0; done < n; done += chunk) {
		j = up_start + up_sent + done;
		if (j >= up_ring)
			j -= up_ring;
		chunk = n - done;
		if (chunk > up_ring - j)
			chunk = up_ring - j;	/* stop at the ring end */
		addr = ddr_base + 2 * j;
		/* The PL wrote this through HP0, past the CPU caches */
		Xil_DCacheInvalidateRange(addr & ~31u, ((addr & 31u) + 2 * chunk + 31) & ~31u);
		memcpy(&p[4 + 2 * done], (const void *)(uintptr_t)addr, 2 * chunk);
	}
	up_sent += n;
	return frame(buf, R_DATA, p, 4 + 2 * n);
}

/* Push queued control frames, then DATA, as far as lwIP has room */
static void pump_tx(void)
{
	static u8 buf[MAX_PAYLOAD + 5];
	u32 n;

	if (!client)
		return;
	if (txq_len) {
		n = tcp_sndbuf(client);
		if (n > txq_len)
			n = txq_len;
		if (n && tcp_write(client, txq, n, TCP_WRITE_FLAG_COPY) == ERR_OK) {
			txq_len -= n;
			memmove(txq, txq + n, txq_len);
		}
	}
	while (!txq_len && (st == S_TRIGGER || st == S_DATA || st == S_END) &&
			tcp_sndbuf(client) >= sizeof(buf) &&
			tcp_sndqueuelen(client) < TCP_SND_QUEUELEN - 4) {
		if (st == S_TRIGGER) {
			u8 p[4];

			wl32(p, cfg_pre);
			n = frame(buf, R_TRIGGER, p, 4);
			st = S_DATA;
		} else if (st == S_DATA) {
			n = make_data(buf);
			if (up_sent >= cfg_total)
				st = S_END;
		} else {
			send_end(end_flags);
			break;
		}
		if (tcp_write(client, buf, n, TCP_WRITE_FLAG_COPY) != ERR_OK)
			break;		/* Should not happen: room was checked */
	}
	tcp_output(client);
}

static void poll_capture(void)
{
	u32 s;

	if (st != S_CAPTURE)
		return;
	s = reg_rd(R_STATUS);
	if (s & ST_DONE) {
		up_start = reg_rd(R_START);
		up_ring = reg_rd(R_RING);
		up_sent = 0;
		end_flags = (s & ST_OVERFLOW) ? END_OVERFLOW : 0;
		st = (cfg_tlm | cfg_trm | cfg_tfm) ? S_TRIGGER : S_DATA;
		send_status();			/* 4: upload */
		return;
	}
	if (cfg_tmo && ((s & 7) == 1 || (s & 7) == 2) && ms_since(t_arm) >= cfg_tmo) {
		reg_wr(R_CTRL, CTRL_ABORT);
		send_end(END_TIMEOUT);
		return;
	}
	if (status_code() != last_code || ms_since(t_status) >= STATUS_PERIOD_MS)
		send_status();
}

static void drop_client(void)
{
	if (st == S_CAPTURE)
		reg_wr(R_CTRL, CTRL_ABORT);
	st = S_IDLE;
	client = NULL;
	rx_len = 0;
	txq_len = 0;
	reg_wr(R_CFG, reg_rd(R_CFG) & ~CFG_LED);
	xil_printf("la16: client gone\r\n");
}

static err_t on_recv(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err)
{
	struct pbuf *q;

	(void)arg;
	if (!p) {
		tcp_close(pcb);
		if (pcb == client)
			drop_client();
		return ERR_OK;
	}
	for (q = p; q; q = q->next) {
		u32 n = q->len;

		if (n > sizeof(rx) - rx_len)
			n = sizeof(rx) - rx_len;
		memcpy(&rx[rx_len], q->payload, n);
		rx_len += n;
	}
	tcp_recved(pcb, p->tot_len);
	pbuf_free(p);
	parse_rx();
	(void)err;
	return ERR_OK;
}

static void on_err(void *arg, err_t err)
{
	(void)arg;
	(void)err;
	drop_client();		/* pcb already freed by lwIP */
}

static err_t on_accept(void *arg, struct tcp_pcb *pcb, err_t err)
{
	(void)arg;
	(void)err;
	if (client) {		/* One host at a time: the newest wins */
		tcp_arg(client, NULL);
		tcp_recv(client, NULL);
		tcp_err(client, NULL);
		tcp_abort(client);
		drop_client();
	}
	client = pcb;
	tcp_nagle_disable(pcb);
	tcp_recv(pcb, on_recv);
	tcp_err(pcb, on_err);
	reg_wr(R_CFG, reg_rd(R_CFG) | CFG_LED);
	xil_printf("la16: client connected\r\n");
	return ERR_OK;
}

void print_app_header(void)
{
	xil_printf("\r\n-----la16 logic analyzer server, TCP port %d -----\r\n",
		   LA16_TCP_PORT);
	xil_printf("PulseView: driver la16, conn=tcp-raw/<board IP>/%d\r\n",
		   LA16_TCP_PORT);
}

int start_application(void)
{
	struct tcp_pcb *pcb;

	if (reg_rd(R_ID) != REG_ID_VALUE) {
		xil_printf("la16: registers not found at 0x%08x ( wrong bitstream? )\r\n",
			   REG_BASE);
		return -1;
	}
	ddr_base = reg_rd(R_DDR_BASE);
	max_samples = reg_rd(R_MAX_SAMPLES);
	xil_printf("la16: ring at 0x%08x, %d samples\r\n", ddr_base, max_samples);
	s9_phy_init();

	pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
	if (!pcb || tcp_bind(pcb, IP_ANY_TYPE, LA16_TCP_PORT) != ERR_OK)
		return -1;
	pcb = tcp_listen(pcb);
	tcp_accept(pcb, on_accept);
	XTime_GetTime(&t_status);
	return 0;
}

int transfer_data(void)
{
	s9_phy_poll();
	poll_capture();
	pump_tx();
	return 0;
}
