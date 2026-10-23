/* ****************************************************************************
-- Source file: la16_store_bram.v
-- Description: la16 ring buffer in BRAM, 2^W samples in two banks ( even /
--              odd ring index ), so two samples can be written per clock.
--              Readback: rj = ring index ( registered by the caller ),
--              rd_data valid 2 clocks later.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_store_bram
#(
  parameter W = 16
)
(
  input  wire          clk,
  input  wire          we0,
  input  wire          we1,
  input  wire [W-1:0]  wi0,
  input  wire [W-1:0]  wi1,
  input  wire [15:0]   sv0,
  input  wire [15:0]   sv1,
  input  wire [W-1:0]  rj,
  output reg  [15:0]   rd_data
);

  localparam HALF = ( 1 << ( W - 1 ) );

  reg  [15:0]  bank_e [0:HALF-1];
  reg  [15:0]  bank_o [0:HALF-1];

  // When both lanes write, their ring indexes differ in bit 0
  wire          e_we   = ( we0 & ~wi0[0] ) | ( we1 & ~wi1[0] );
  wire [W-2:0]  e_addr = ( we0 & ~wi0[0] ) ? wi0[W-1:1] : wi1[W-1:1];
  wire [15:0]   e_din  = ( we0 & ~wi0[0] ) ? sv0 : sv1;
  wire          o_we   = ( we0 &  wi0[0] ) | ( we1 &  wi1[0] );
  wire [W-2:0]  o_addr = ( we0 &  wi0[0] ) ? wi0[W-1:1] : wi1[W-1:1];
  wire [15:0]   o_din  = ( we0 &  wi0[0] ) ? sv0 : sv1;

  reg  [15:0]  rd_e, rd_o;
  reg          rd_sel;

  always @ ( posedge clk ) begin : proc_ram
    if ( e_we ) bank_e[ e_addr ] <= e_din;
    if ( o_we ) bank_o[ o_addr ] <= o_din;
    rd_e    <= bank_e[ rj[W-1:1] ];
    rd_o    <= bank_o[ rj[W-1:1] ];
    rd_sel  <= rj[0];
  end // proc_ram

  always @ ( * ) rd_data = rd_sel ? rd_o : rd_e;

endmodule // la16_store_bram
`default_nettype wire
