/* ****************************************************************************
-- Source file: la_top_s9_la16.v
-- Description: Antminer S9 control board top level, la16 protocol variant
--              ( docs/PROTOCOL_LA16.md, own libsigrok driver "la16" ).
--              Probes are sampled on both clock edges ( IDDR ) = 200 MS/s.
--              Same pins and clock as la_top_s9.v ( see that file and
--              constraints/antminer_s9.xdc ):
--                J1 pin 11/12 = UART TX/RX, J5..J8 = D0..D15,
--                J9 pin 5 = test pattern jumper, LEDs D5..D8 active low.
--              UART baud ( jumper to GND, pull-ups inside ):
--                none = 921600, J9 pin 11 = 460800, J9 pin 12 = 230400,
--                both = 115200. Set the same baud rate in PulseView.
--              LEDs: D5 heartbeat, D6 armed ( prefill / waiting for
--                    trigger ), D7 test pattern, D8 UART RX activity.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_top_s9_la16
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
  input  wire [1:0]   baud_sel_n,     // J9 pin 11 / pin 12, jumper to GND
  input  wire         bd_rx,
  output wire         bd_tx,
  output wire [3:0]   led_n
);// module la_top_s9_la16

  wire          fclk0;
  wire          fclk0_reset_n;
  wire [3:0]    led;
  wire [15:0]   probe_lo;
  wire [15:0]   probe_hi;


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
// Probes: IDDR, Q1 = rising edge sample ( earlier ), Q2 = falling edge
// sample of the same clock period, both presented on the rising edge.
//-----------------------------------------------------------------------------
genvar i;
generate
  for ( i = 0; i < 16; i = i + 1 ) begin : g_iddr
    IDDR #( .DDR_CLK_EDGE ( "SAME_EDGE_PIPELINED" ), .SRTYPE ( "SYNC" ) ) u_iddr
    (
      .C  ( fclk0       ),
      .CE ( 1'b1        ),
      .D  ( probe[i]    ),
      .R  ( 1'b0        ),
      .S  ( 1'b0        ),
      .Q1 ( probe_lo[i] ),
      .Q2 ( probe_hi[i] )
    );
  end
endgenerate


//-----------------------------------------------------------------------------
// la16 logic analyzer. Test pattern via J9 jumper.
//-----------------------------------------------------------------------------
la16_core u_la16_core
(
  .clk_100m     ( fclk0                ),
  .probe_lo     ( probe_lo             ),
  .probe_hi     ( probe_hi             ),
  .tp_sel       ( ~tp_sel_n            ),
  .baud_sel     ( ~baud_sel_n          ),
  .uart_rx      ( bd_rx                ),
  .uart_tx      ( bd_tx                ),
  .led          ( led[3:0]             ),
  .m_awready ( 1'b0 ), .m_wready ( 1'b0 ), .m_bresp ( 2'b00 ), .m_bid ( 6'd0 ),
  .m_bvalid  ( 1'b0 ), .m_arready ( 1'b0 ), .m_rdata ( 64'd0 ), .m_rresp ( 2'b00 ),
  .m_rid     ( 6'd0 ), .m_rlast ( 1'b0 ), .m_rvalid ( 1'b0 )
);// u_la16_core

  assign led_n = ~led;


endmodule // la_top_s9_la16.v
`default_nettype wire
