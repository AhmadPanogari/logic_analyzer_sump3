/* ****************************************************************************
-- Source file: la_top_s9_ols.v
-- Description: Antminer S9 control board top level, OLS / SUMP protocol
--              variant: PulseView controls the capture directly ( driver
--              "Openbench Logic Sniffer & SUMP compatibles", 921600 baud ).
--              Same pins and clock as la_top_s9.v ( see that file and
--              constraints/antminer_s9.xdc ):
--                J1 pin 11/12 = UART TX/RX, J5..J8 = D0..D15,
--                J9 pin 5 = test pattern jumper, LEDs D5..D8 active low.
--              LEDs: D5 heartbeat, D6 armed ( waiting for trigger ),
--                    D7 test pattern, D8 UART RX activity.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_top_s9_ols
(
  // PS7 dedicated pins ( DDR and MIO ), required by processing_system7
  inout  wire [14:0]  DDR_addr,
  inout  wire [2:0]   DDR_ba,
  inout  wire         DDR_cas_n,
  inout  wire         DDR_ck_n,
  inout  wire         DDR_ck_p,
  inout  wire         DDR_cke,
  inout  wire         DDR_cs_n,
  inout  wire [3:0]   DDR_dm,
  inout  wire [31:0]  DDR_dq,
  inout  wire [3:0]   DDR_dqs_n,
  inout  wire [3:0]   DDR_dqs_p,
  inout  wire         DDR_odt,
  inout  wire         DDR_ras_n,
  inout  wire         DDR_reset_n,
  inout  wire         DDR_we_n,
  inout  wire         FIXED_IO_ddr_vrn,
  inout  wire         FIXED_IO_ddr_vrp,
  inout  wire [53:0]  FIXED_IO_mio,
  inout  wire         FIXED_IO_ps_clk,
  inout  wire         FIXED_IO_ps_porb,
  inout  wire         FIXED_IO_ps_srstb,

  // PL pins
  input  wire [15:0]  probe,
  input  wire         tp_sel_n,
  input  wire         bd_rx,
  output wire         bd_tx,
  output wire [3:0]   led_n
);// module la_top_s9_ols

  wire          fclk0;
  wire          fclk0_reset_n;
  wire [3:0]    led;


//-----------------------------------------------------------------------------
// Zynq PS : only used as the PL clock source
//-----------------------------------------------------------------------------
la_ps_wrapper u_la_ps
(
  .DDR_addr          ( DDR_addr          ),
  .DDR_ba            ( DDR_ba            ),
  .DDR_cas_n         ( DDR_cas_n         ),
  .DDR_ck_n          ( DDR_ck_n          ),
  .DDR_ck_p          ( DDR_ck_p          ),
  .DDR_cke           ( DDR_cke           ),
  .DDR_cs_n          ( DDR_cs_n          ),
  .DDR_dm            ( DDR_dm            ),
  .DDR_dq            ( DDR_dq            ),
  .DDR_dqs_n         ( DDR_dqs_n         ),
  .DDR_dqs_p         ( DDR_dqs_p         ),
  .DDR_odt           ( DDR_odt           ),
  .DDR_ras_n         ( DDR_ras_n         ),
  .DDR_reset_n       ( DDR_reset_n       ),
  .DDR_we_n          ( DDR_we_n          ),
  .FIXED_IO_ddr_vrn  ( FIXED_IO_ddr_vrn  ),
  .FIXED_IO_ddr_vrp  ( FIXED_IO_ddr_vrp  ),
  .FIXED_IO_mio      ( FIXED_IO_mio      ),
  .FIXED_IO_ps_clk   ( FIXED_IO_ps_clk   ),
  .FIXED_IO_ps_porb  ( FIXED_IO_ps_porb  ),
  .FIXED_IO_ps_srstb ( FIXED_IO_ps_srstb ),
  .FCLK_CLK0         ( fclk0             ),
  .FCLK_RESET0_N     ( fclk0_reset_n     )
);// u_la_ps


//-----------------------------------------------------------------------------
// OLS / SUMP logic analyzer for PulseView. Test pattern via J9 jumper or
// PulseView "Pattern mode = Internal".
//-----------------------------------------------------------------------------
la_ols_core u_la_ols_core
(
  .clk_100m     ( fclk0                ),
  .probe        ( probe[15:0]          ),
  .tp_sel       ( ~tp_sel_n            ),
  .uart_rx      ( bd_rx                ),
  .uart_tx      ( bd_tx                ),
  .led          ( led[3:0]             )
);// u_la_ols_core

  assign led_n = ~led;


endmodule // la_top_s9_ols.v
`default_nettype wire
