// Simulation stand-in for the Vivado generated PS7 block design wrapper.
`timescale 1 ns/ 1 ps
module la_ps_wrapper
(
  inout  wire [14:0] DDR_addr, inout wire [2:0] DDR_ba, inout wire DDR_cas_n,
  inout  wire DDR_ck_n, inout wire DDR_ck_p, inout wire DDR_cke, inout wire DDR_cs_n,
  inout  wire [3:0] DDR_dm, inout wire [31:0] DDR_dq, inout wire [3:0] DDR_dqs_n,
  inout  wire [3:0] DDR_dqs_p, inout wire DDR_odt, inout wire DDR_ras_n,
  inout  wire DDR_reset_n, inout wire DDR_we_n,
  inout  wire FIXED_IO_ddr_vrn, inout wire FIXED_IO_ddr_vrp, inout wire [53:0] FIXED_IO_mio,
  inout  wire FIXED_IO_ps_clk, inout wire FIXED_IO_ps_porb, inout wire FIXED_IO_ps_srstb,
  output reg  FCLK_CLK0 = 0,
  output wire FCLK_RESET0_N
);
  always #5 FCLK_CLK0 = ~FCLK_CLK0;   // 100 MHz
  assign FCLK_RESET0_N = 1'b1;
endmodule
