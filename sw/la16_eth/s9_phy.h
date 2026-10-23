/*
 * PHY of the Antminer S9 control board ( Broadcom BCM54612E ), see s9_phy.c.
 */
#ifndef S9_PHY_H
#define S9_PHY_H

void s9_phy_init(void);		/* after xemac_add(), takes the PHY over from lwIP */
void s9_phy_poll(void);		/* main loop: follows the link */

#endif
