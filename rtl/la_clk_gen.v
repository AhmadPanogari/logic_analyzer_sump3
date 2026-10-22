/* ****************************************************************************
-- Source file: la_clk_gen.v
-- Description: 125 MHz -> 100 MHz using a 7-Series MMCME2_BASE.
--              VCO = 125 MHz * 8 / 1 = 1000 MHz, CLKOUT0 = 1000 / 10 = 100 MHz
--              Define SIMULATION to bypass the MMCM ( clk_out = clk_in ).
--              If your board has a different PL oscillator, change
--              CLKIN1_PERIOD and CLKFBOUT_MULT_F so VCO is 600-1200 MHz,
--              and keep ck_freq_mhz in la_sump3.v equal to clk_out.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_clk_gen
(
  input  wire  clk_in,
  output wire  clk_out,
  output wire  locked
);

`ifdef SIMULATION
  assign clk_out = clk_in;
  assign locked  = 1'b1;
`else
  wire  clk_in_buf;
  wire  clk_fb;
  wire  clk_fb_buf;
  wire  clk_out_loc;

  IBUF u_ibuf ( .I( clk_in ), .O( clk_in_buf ) );

  MMCME2_BASE
  #(
    .BANDWIDTH          ( "OPTIMIZED" ),
    .CLKIN1_PERIOD      ( 8.000       ),// 125 MHz
    .DIVCLK_DIVIDE      ( 1           ),
    .CLKFBOUT_MULT_F    ( 8.000       ),// VCO 1000 MHz
    .CLKFBOUT_PHASE     ( 0.000       ),
    .CLKOUT0_DIVIDE_F   ( 10.000      ),// 100 MHz
    .CLKOUT0_DUTY_CYCLE ( 0.500       ),
    .CLKOUT0_PHASE      ( 0.000       ),
    .REF_JITTER1        ( 0.010       ),
    .STARTUP_WAIT       ( "FALSE"     )
  )
  u_mmcm
  (
    .CLKIN1    ( clk_in_buf  ),
    .CLKFBIN   ( clk_fb_buf  ),
    .CLKFBOUT  ( clk_fb      ),
    .CLKFBOUTB (             ),
    .CLKOUT0   ( clk_out_loc ),
    .CLKOUT0B  (             ),
    .CLKOUT1   (             ),
    .CLKOUT1B  (             ),
    .CLKOUT2   (             ),
    .CLKOUT2B  (             ),
    .CLKOUT3   (             ),
    .CLKOUT3B  (             ),
    .CLKOUT4   (             ),
    .CLKOUT5   (             ),
    .CLKOUT6   (             ),
    .LOCKED    ( locked      ),
    .PWRDWN    ( 1'b0        ),
    .RST       ( 1'b0        )
  );

  BUFG u_bufg_fb  ( .I( clk_fb      ), .O( clk_fb_buf ) );
  BUFG u_bufg_out ( .I( clk_out_loc ), .O( clk_out    ) );
`endif

endmodule // la_clk_gen.v
`default_nettype wire
