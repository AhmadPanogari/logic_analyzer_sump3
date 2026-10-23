/* ****************************************************************************
-- Source file: la16_capture.v
-- Description: la16 capture ( docs/PROTOCOL_LA16.md ):
--              la16_front ( divider, trigger conditions, 1 pipeline stage )
--              -> la16_seq ( prefill / wait / post, ring index )
--              -> la16_store_bram ( USE_DDR = 0, ring = 2^W samples )
--              or la16_store_ddr  ( USE_DDR = 1, ring = total rounded up to
--                                   64 samples, in PS DDR via AXI3 HP )
--
--   Input   : two 16 bit samples per clock, s_lo earlier than s_hi.
--   done    : capture complete and stored ( DDR: all bursts written ).
--   ready   : a new capture may be armed ( DDR: earlier writes drained ).
--   Readback: rd_idx = sample number 0 .. total-1 of the result, oldest
--             first. rd_ready = rd_data belongs to rd_idx ( BRAM: always,
--             3 clocks after rd_idx; DDR: after a burst fetch ).
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_capture
#(
  parameter        W       = 16,              // Ring index bits
  parameter        USE_DDR = 0,
  parameter [31:0] DDR_BASE = 32'h0200_0000
)
(
  input  wire          clk,
  input  wire          reset,
  input  wire [15:0]   s_lo,
  input  wire [15:0]   s_hi,

  input  wire [31:0]   divider,
  input  wire [W:0]    total,
  input  wire [W:0]    pre,
  input  wire [15:0]   tl_mask,
  input  wire [15:0]   tl_value,
  input  wire [15:0]   tr_mask,
  input  wire [15:0]   tf_mask,

  input  wire          arm,
  input  wire          abort,

  output wire [2:0]    state,
  output wire [W:0]    captured,
  output wire          done,
  output wire          ready,
  output wire          overflow,

  input  wire          rd_en,
  input  wire [W-1:0]  rd_idx,
  output wire [15:0]   rd_data,
  output wire          rd_ready,

  // AXI3 master ( USE_DDR = 1 only )
  output wire [31:0]   m_awaddr,
  output wire [3:0]    m_awlen,
  output wire [2:0]    m_awsize,
  output wire [1:0]    m_awburst,
  output wire [1:0]    m_awlock,
  output wire [3:0]    m_awcache,
  output wire [2:0]    m_awprot,
  output wire [3:0]    m_awqos,
  output wire [5:0]    m_awid,
  output wire          m_awvalid,
  input  wire          m_awready,
  output wire [63:0]   m_wdata,
  output wire [7:0]    m_wstrb,
  output wire          m_wlast,
  output wire [5:0]    m_wid,
  output wire          m_wvalid,
  input  wire          m_wready,
  input  wire [1:0]    m_bresp,
  input  wire [5:0]    m_bid,
  input  wire          m_bvalid,
  output wire          m_bready,
  output wire [31:0]   m_araddr,
  output wire [3:0]    m_arlen,
  output wire [2:0]    m_arsize,
  output wire [1:0]    m_arburst,
  output wire [1:0]    m_arlock,
  output wire [3:0]    m_arcache,
  output wire [2:0]    m_arprot,
  output wire [3:0]    m_arqos,
  output wire [5:0]    m_arid,
  output wire          m_arvalid,
  input  wire          m_arready,
  input  wire [63:0]   m_rdata,
  input  wire [1:0]    m_rresp,
  input  wire [5:0]    m_rid,
  input  wire          m_rlast,
  input  wire          m_rvalid,
  output wire          m_rready
);

  wire [15:0]   v0, v1, sv0, sv1;
  wire          t0, t1, h0, h1;
  wire          we0, we1;
  wire [W-1:0]  wi0, wi1;
  wire [W-1:0]  start;
  wire          seq_done;

  // DDR: ring = total rounded up to whole 16 beat bursts ( 64 samples )
  wire [W:0]    ring = USE_DDR ? ( ( total + 7'd63 ) & ~( { {(W-5){1'b0}}, 6'd63 } ) )
                               : ( { 1'b1, {W{1'b0}} } );

  la16_front u_front
  (
    .clk      ( clk      ),
    .s_lo     ( s_lo     ),
    .s_hi     ( s_hi     ),
    .divider  ( divider  ),
    .tl_mask  ( tl_mask  ),
    .tl_value ( tl_value ),
    .tr_mask  ( tr_mask  ),
    .tf_mask  ( tf_mask  ),
    .arm      ( arm      ),
    .v0       ( v0       ),
    .v1       ( v1       ),
    .t0       ( t0       ),
    .t1       ( t1       ),
    .h0       ( h0       ),
    .h1       ( h1       )
  );

  la16_seq #( .W ( W ) ) u_seq
  (
    .clk      ( clk      ),
    .reset    ( reset    ),
    .v0       ( v0       ),
    .v1       ( v1       ),
    .t0       ( t0       ),
    .t1       ( t1       ),
    .h0       ( h0       ),
    .h1       ( h1       ),
    .total    ( total    ),
    .pre      ( pre      ),
    .ring     ( ring     ),
    .arm      ( arm      ),
    .abort    ( abort    ),
    .state    ( state    ),
    .captured ( captured ),
    .done     ( seq_done ),
    .start    ( start    ),
    .we0      ( we0      ),
    .we1      ( we1      ),
    .wi0      ( wi0      ),
    .wi1      ( wi1      ),
    .sv0      ( sv0      ),
    .sv1      ( sv1      )
  );

  // Ring index of result sample rd_idx
  reg  [W-1:0]  rj;
  wire [W:0]    rsum = start + rd_idx;
  always @ ( posedge clk ) begin : proc_rj
    rj <= ( rsum >= ring ) ? rsum - ring : rsum;
  end // proc_rj

  generate
    if ( USE_DDR ) begin : g_ddr
      wire drained;
      wire flushed;

      la16_store_ddr #( .W ( W ), .BASE ( DDR_BASE ) ) u_store
      (
        .clk        ( clk          ),
        .reset      ( reset        ),
        .arm        ( arm          ),
        .abort      ( abort        ),
        .flush      ( seq_done     ),
        .we0        ( we0          ),
        .we1        ( we1          ),
        .sv0        ( sv0          ),
        .sv1        ( sv1          ),
        .ring_words ( ring[W-1:2]  ),     // DDR: ring < 2^W ( MAX_SAMPLES < 2^W )
        .drained    ( drained      ),
        .flushed    ( flushed      ),
        .overflow   ( overflow     ),
        .rd_en      ( rd_en        ),
        .rj         ( rj           ),
        .rd_data    ( rd_data      ),
        .rd_ready   ( rd_ready     ),
        .m_awaddr   ( m_awaddr     ),
        .m_awlen    ( m_awlen      ),
        .m_awsize   ( m_awsize     ),
        .m_awburst  ( m_awburst    ),
        .m_awlock   ( m_awlock     ),
        .m_awcache  ( m_awcache    ),
        .m_awprot   ( m_awprot     ),
        .m_awqos    ( m_awqos      ),
        .m_awid     ( m_awid       ),
        .m_awvalid  ( m_awvalid    ),
        .m_awready  ( m_awready    ),
        .m_wdata    ( m_wdata      ),
        .m_wstrb    ( m_wstrb      ),
        .m_wlast    ( m_wlast      ),
        .m_wid      ( m_wid        ),
        .m_wvalid   ( m_wvalid     ),
        .m_wready   ( m_wready     ),
        .m_bresp    ( m_bresp      ),
        .m_bid      ( m_bid        ),
        .m_bvalid   ( m_bvalid     ),
        .m_bready   ( m_bready     ),
        .m_araddr   ( m_araddr     ),
        .m_arlen    ( m_arlen      ),
        .m_arsize   ( m_arsize     ),
        .m_arburst  ( m_arburst    ),
        .m_arlock   ( m_arlock     ),
        .m_arcache  ( m_arcache    ),
        .m_arprot   ( m_arprot     ),
        .m_arqos    ( m_arqos      ),
        .m_arid     ( m_arid       ),
        .m_arvalid  ( m_arvalid    ),
        .m_arready  ( m_arready    ),
        .m_rdata    ( m_rdata      ),
        .m_rresp    ( m_rresp      ),
        .m_rid      ( m_rid        ),
        .m_rlast    ( m_rlast      ),
        .m_rvalid   ( m_rvalid     ),
        .m_rready   ( m_rready     )
      );

      assign done  = seq_done && flushed && drained;
      assign ready = drained;
    end else begin : g_bram
      la16_store_bram #( .W ( W ) ) u_store
      (
        .clk     ( clk     ),
        .we0     ( we0     ),
        .we1     ( we1     ),
        .wi0     ( wi0     ),
        .wi1     ( wi1     ),
        .sv0     ( sv0     ),
        .sv1     ( sv1     ),
        .rj      ( rj      ),
        .rd_data ( rd_data )
      );

      assign done      = seq_done;
      assign ready     = 1'b1;
      assign overflow  = 1'b0;
      assign rd_ready  = 1'b1;
      assign m_awaddr  = 32'd0;  assign m_awlen   = 4'd0;  assign m_awsize  = 3'd0;
      assign m_awburst = 2'd0;   assign m_awlock  = 2'd0;  assign m_awcache = 4'd0;
      assign m_awprot  = 3'd0;   assign m_awqos   = 4'd0;  assign m_awid    = 6'd0;
      assign m_awvalid = 1'b0;   assign m_wdata   = 64'd0; assign m_wstrb   = 8'd0;
      assign m_wlast   = 1'b0;   assign m_wid     = 6'd0;  assign m_wvalid  = 1'b0;
      assign m_bready  = 1'b1;   assign m_araddr  = 32'd0; assign m_arlen   = 4'd0;
      assign m_arsize  = 3'd0;   assign m_arburst = 2'd0;  assign m_arlock  = 2'd0;
      assign m_arcache = 4'd0;   assign m_arprot  = 3'd0;  assign m_arqos   = 4'd0;
      assign m_arid    = 6'd0;   assign m_arvalid = 1'b0;  assign m_rready  = 1'b1;
    end
  endgenerate

endmodule // la16_capture
`default_nettype wire
