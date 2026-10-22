/* ****************************************************************************
-- Source file: la_top.v
-- Description: Top level for boards with a 125 MHz PL oscillator
--              ( Digilent Zybo Z7-10, Arty Z7-10 ). PL only, no PS7 / FSBL.
--              The bitstream can be loaded over JTAG with Vivado.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_top
(
  input  wire         sys_clk,      // 125 MHz
  input  wire [3:0]   btn,
  input  wire [1:0]   sw,
  input  wire [15:0]  probe,
  input  wire         bd_rx,
  output wire         bd_tx,
  output wire [3:0]   led
);// module la_top

  wire          clk_100m;
  wire          clk_locked;

la_clk_gen u_la_clk_gen
(
  .clk_in       ( sys_clk         ),
  .clk_out      ( clk_100m        ),
  .locked       ( clk_locked      )
);// u_la_clk_gen

la_core u_la_core
(
  .clk_100m     ( clk_100m        ),
  .clk_locked   ( clk_locked      ),
  .btn          ( btn[3:0]        ),
  .sw           ( sw[1:0]         ),
  .probe        ( probe[15:0]     ),
  .bd_rx        ( bd_rx           ),
  .bd_tx        ( bd_tx           ),
  .led          ( led[3:0]        )
);// u_la_core

endmodule // la_top.v
`default_nettype wire
