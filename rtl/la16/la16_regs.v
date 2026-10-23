/* ****************************************************************************
-- Source file: la16_regs.v
-- Description: la16 control registers for the PS ( Zynq M_AXI_GP0, AXI3,
--              32 bit, single beat accesses ). Used by the Ethernet build:
--              the ARM program speaks the la16 protocol over TCP and drives
--              the capture through these registers; it reads the result
--              straight from the DDR ring.
--
--   0x00 R   ID          0x4C413136 ( "LA16" )
--   0x04 W   CTRL        bit0 ARM, bit1 ABORT ( pulses )
--   0x08 RW  DIVIDER     sample every DIVIDER + 1 base samples
--   0x0C RW  TOTAL       samples
--   0x10 RW  PRE         pre-trigger samples ( < TOTAL )
--   0x14 RW  TRIG_LEVEL  [15:0] mask, [31:16] value
--   0x18 RW  TRIG_EDGE   [15:0] rising mask, [31:16] falling mask
--   0x1C R   STATUS      [2:0] capture state ( 0 idle, 1 prefill, 2 wait,
--                        3 post, 5 done ), [3] done ( stored in DDR ),
--                        [4] ready ( DDR writes drained ), [5] overflow
--   0x20 R   CAPTURED    samples captured so far
--   0x24 R   START       ring index of result sample 0
--   0x28 R   RING        ring size in samples
--   0x2C R   DDR_BASE    byte address of ring index 0
--   0x30 R   MAX_SAMPLES
--   0x34 RW  CFG         bit0 internal test pattern, bit8 LED D8 ( software )
--   0x38 R   BASE_HZ     200000000
--   Other addresses read 0. Responses are always OKAY.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_regs
#(
  parameter        W           = 28,
  parameter [31:0] MAX_SAMPLES = 32'd251_658_240,
  parameter [31:0] DDR_BASE    = 32'h0200_0000,
  parameter [31:0] BASE_HZ     = 32'd200_000_000
)
(
  input  wire         clk,
  input  wire         reset,

  // AXI3 slave ( from M_AXI_GP0 )
  input  wire [31:0]  s_awaddr,
  input  wire [11:0]  s_awid,
  input  wire         s_awvalid,
  output wire         s_awready,
  input  wire [31:0]  s_wdata,
  input  wire [3:0]   s_wstrb,
  input  wire         s_wvalid,
  output wire         s_wready,
  output reg  [11:0]  s_bid,
  output wire [1:0]   s_bresp,
  output reg          s_bvalid,
  input  wire         s_bready,
  input  wire [31:0]  s_araddr,
  input  wire [11:0]  s_arid,
  input  wire         s_arvalid,
  output wire         s_arready,
  output reg  [11:0]  s_rid,
  output reg  [31:0]  s_rdata,
  output wire [1:0]   s_rresp,
  output wire         s_rlast,
  output reg          s_rvalid,
  input  wire         s_rready,

  // Capture control and status
  output reg          arm,
  output reg          abort,
  output reg  [31:0]  divider,
  output reg  [W:0]   total,
  output reg  [W:0]   pre,
  output reg  [15:0]  tl_mask,
  output reg  [15:0]  tl_value,
  output reg  [15:0]  tr_mask,
  output reg  [15:0]  tf_mask,
  output reg  [31:0]  cfg,
  input  wire [2:0]   state,
  input  wire         done,
  input  wire         ready,
  input  wire         overflow,
  input  wire [W:0]   captured,
  input  wire [W-1:0] start,
  input  wire [W:0]   ring
);

  assign s_bresp = 2'b00;
  assign s_rresp = 2'b00;
  assign s_rlast = 1'b1;

  // Write: take address and data ( any order ), then answer B
  reg          aw_have, w_have;
  reg  [7:0]   aw_off;
  reg  [31:0]  w_data;
  reg  [3:0]   w_strb;

  assign s_awready = !aw_have && !s_bvalid;
  assign s_wready  = !w_have  && !s_bvalid;

  function [31:0] merge;
    input [31:0] old;
    input [31:0] d;
    input [3:0]  be;
    integer      i;
    begin
      merge = old;
      for ( i = 0; i < 4; i = i + 1 )
        if ( be[i] ) merge[ 8*i +: 8 ] = d[ 8*i +: 8 ];
    end
  endfunction

  always @ ( posedge clk ) begin : proc_write
    arm   <= 1'b0;
    abort <= 1'b0;
    if ( s_awvalid && s_awready ) begin
      aw_have <= 1'b1;
      aw_off  <= s_awaddr[7:0];
      s_bid   <= s_awid;
    end
    if ( s_wvalid && s_wready ) begin
      w_have <= 1'b1;
      w_data <= s_wdata;
      w_strb <= s_wstrb;
    end
    if ( aw_have && w_have ) begin
      aw_have  <= 1'b0;
      w_have   <= 1'b0;
      s_bvalid <= 1'b1;
      case ( aw_off )
        8'h04 : begin
          arm   <= w_strb[0] & w_data[0];
          abort <= w_strb[0] & w_data[1];
        end
        8'h08 : divider <= merge( divider, w_data, w_strb );
        8'h0C : total   <= merge( { {(31-W){1'b0}}, total }, w_data, w_strb );
        8'h10 : pre     <= merge( { {(31-W){1'b0}}, pre   }, w_data, w_strb );
        8'h14 : { tl_value, tl_mask } <= merge( { tl_value, tl_mask }, w_data, w_strb );
        8'h18 : { tf_mask,  tr_mask } <= merge( { tf_mask,  tr_mask }, w_data, w_strb );
        8'h34 : cfg     <= merge( cfg, w_data, w_strb );
        default : ;
      endcase
    end
    if ( s_bvalid && s_bready ) s_bvalid <= 1'b0;
    if ( reset ) begin
      aw_have  <= 1'b0;
      w_have   <= 1'b0;
      s_bvalid <= 1'b0;
      divider  <= 32'd0;
      total    <= { {W{1'b0}}, 1'b1 };
      pre      <= {(W+1){1'b0}};
      tl_mask  <= 16'd0;
      tl_value <= 16'd0;
      tr_mask  <= 16'd0;
      tf_mask  <= 16'd0;
      cfg      <= 32'd0;
    end
  end // proc_write

  // Read: one beat per AR
  assign s_arready = !s_rvalid;

  always @ ( posedge clk ) begin : proc_read
    if ( s_arvalid && s_arready ) begin
      s_rvalid <= 1'b1;
      s_rid    <= s_arid;
      case ( s_araddr[7:0] )
        8'h00 : s_rdata <= 32'h4C41_3136;
        8'h08 : s_rdata <= divider;
        8'h0C : s_rdata <= total;
        8'h10 : s_rdata <= pre;
        8'h14 : s_rdata <= { tl_value, tl_mask };
        8'h18 : s_rdata <= { tf_mask, tr_mask };
        8'h1C : s_rdata <= { 26'd0, overflow, ready, done, state };
        8'h20 : s_rdata <= captured;
        8'h24 : s_rdata <= start;
        8'h28 : s_rdata <= ring;
        8'h2C : s_rdata <= DDR_BASE;
        8'h30 : s_rdata <= MAX_SAMPLES;
        8'h34 : s_rdata <= cfg;
        8'h38 : s_rdata <= BASE_HZ;
        default : s_rdata <= 32'd0;
      endcase
    end else if ( s_rvalid && s_rready ) begin
      s_rvalid <= 1'b0;
    end
    if ( reset ) s_rvalid <= 1'b0;
  end // proc_read

endmodule // la16_regs
`default_nettype wire
