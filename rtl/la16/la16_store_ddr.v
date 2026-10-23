/* ****************************************************************************
-- Source file: la16_store_ddr.v
-- Description: la16 ring buffer in the Zynq PS DDR through an AXI3 HP port
--              ( 64 bit, clocked by clk ).
--
--   Write   : up to two samples per clock are packed 4 per 64 bit word,
--             queued in a FIFO of 2^FB words and written in 16 beat bursts
--             ( 128 byte, aligned ) to BASE + 8 * word. Several bursts may
--             be outstanding, so 400 MB/s ( 200 MS/s ) fits the 800 MB/s of
--             the port. The ring is ring_words words ( multiple of 16 ).
--             flush ( capture done ) writes the last partial word with byte
--             strobes so older ring contents stay intact, then the rest.
--             abort writes what is queued and drops the partial word.
--             overflow : the FIFO was full and samples were lost.
--   Read    : rj = ring sample index ( registered by the caller ). A 16 beat
--             burst holding it is fetched into a small cache; rd_data /
--             rd_ready follow 1 clock after a hit. Fetches only when rd_en.
--   drained : nothing queued or in flight on the write side.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_store_ddr
#(
  parameter        W    = 28,                // Ring index bits ( samples )
  parameter [31:0] BASE = 32'h0200_0000,
  parameter        FB   = 10                 // FIFO depth 2^FB words
)
(
  input  wire          clk,
  input  wire          reset,
  input  wire          arm,
  input  wire          abort,
  input  wire          flush,
  input  wire          we0,
  input  wire          we1,
  input  wire [15:0]   sv0,
  input  wire [15:0]   sv1,
  input  wire [W-3:0]  ring_words,
  output wire          drained,
  output reg           flushed,
  output reg           overflow,

  input  wire          rd_en,
  input  wire [W-1:0]  rj,
  output reg  [15:0]   rd_data,
  output reg           rd_ready,

  // AXI3 master ( Zynq S_AXI_HP0 )
  output reg  [31:0]   m_awaddr,
  output reg  [3:0]    m_awlen,
  output wire [2:0]    m_awsize,
  output wire [1:0]    m_awburst,
  output wire [1:0]    m_awlock,
  output wire [3:0]    m_awcache,
  output wire [2:0]    m_awprot,
  output wire [3:0]    m_awqos,
  output wire [5:0]    m_awid,
  output reg           m_awvalid,
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
  output reg  [31:0]   m_araddr,
  output wire [3:0]    m_arlen,
  output wire [2:0]    m_arsize,
  output wire [1:0]    m_arburst,
  output wire [1:0]    m_arlock,
  output wire [3:0]    m_arcache,
  output wire [2:0]    m_arprot,
  output wire [3:0]    m_arqos,
  output wire [5:0]    m_arid,
  output reg           m_arvalid,
  input  wire          m_arready,
  input  wire [63:0]   m_rdata,
  input  wire [1:0]    m_rresp,
  input  wire [5:0]    m_rid,
  input  wire          m_rlast,
  input  wire          m_rvalid,
  output wire          m_rready
);

  localparam SIZE = ( 1 << FB );

  assign m_awsize  = 3'b011;                 // 8 byte beats
  assign m_awburst = 2'b01;                  // INCR
  assign m_awlock  = 2'b00;
  assign m_awcache = 4'b0011;
  assign m_awprot  = 3'b000;
  assign m_awqos   = 4'd0;
  assign m_awid    = 6'd0;
  assign m_wid     = 6'd0;
  assign m_bready  = 1'b1;
  assign m_arlen   = 4'd15;
  assign m_arsize  = 3'b011;
  assign m_arburst = 2'b01;
  assign m_arlock  = 2'b00;
  assign m_arcache = 4'b0011;
  assign m_arprot  = 3'b000;
  assign m_arqos   = 4'd0;
  assign m_arid    = 6'd0;
  assign m_rready  = 1'b1;

  // ---------------------------------------------------------------------
  // Packer: 4 samples per word, lane 0 first
  // ---------------------------------------------------------------------
  reg  [63:0]  pk;
  reg  [1:0]   pc;                           // Samples held in pk
  reg          flush_d;
  wire [1:0]   n = we0 + we1;
  wire [15:0]  a = we0 ? sv0 : sv1;
  reg  [79:0]  tmp;
  reg  [2:0]   tot;

  always @ ( * ) begin : proc_pack
    tmp = { 16'd0, pk };
    if ( n != 2'd0 ) tmp[ pc * 16 +: 16 ] = a;
    if ( n == 2'd2 ) tmp[ ( pc + 1 ) * 16 +: 16 ] = sv1;
    tot = pc + n;
  end // proc_pack

  wire         flush_now = flush_d && !flushed;
  wire         push_full = ( tot >= 3'd4 );
  wire         push_part = flush_now && ( pc != 2'd0 );
  wire         push      = push_full || push_part;
  wire [71:0]  push_word = push_part ?
                           { ( pc == 2'd1 ) ? 8'h03 : ( pc == 2'd2 ) ? 8'h0F : 8'h3F, pk }
                         : { 8'hFF, tmp[63:0] };

  // ---------------------------------------------------------------------
  // FIFO with a first word fall-through head register
  // ---------------------------------------------------------------------
  reg  [71:0]  mem [0:SIZE-1];
  reg  [FB-1:0] wptr, rptr;
  reg  [FB:0]  mcount;
  reg  [71:0]  head;
  reg          head_v;
  wire         full = ( mcount == SIZE );
  wire         pop;
  wire         load = ( mcount != 0 ) && ( !head_v || pop );
  wire         do_push = push && !full;

  // ---------------------------------------------------------------------
  // Burst assignment ( AW ), W beats, B responses
  // ---------------------------------------------------------------------
  reg  [FB:0]  unassigned;                   // Words not yet in a burst
  reg          last_req;                        // No more full bursts coming
  reg  [W-3:0] waw;                          // Word address of next burst
  reg  [4:0]   lq [0:7];                     // Burst lengths for W
  reg  [2:0]   lq_wr, lq_rd;
  reg  [3:0]   lq_cnt;
  reg          w_act;
  reg  [4:0]   w_len;
  reg  [4:0]   w_beat;
  reg  [5:0]   osd;                          // Bursts without B response

  // Never past the end of the aligned 128 byte block ( so never across 4 KB ):
  // only the last bursts after flush / abort can start mid block
  wire [4:0]   aw_room = 5'd16 - waw[3:0];
  wire [4:0]   aw_len  = ( unassigned >= aw_room ) ? aw_room : unassigned[4:0];
  wire         aw_go = !m_awvalid && ( lq_cnt < 4'd8 ) &&
                       ( unassigned >= aw_room || ( last_req && unassigned != 0 ) );
  wire [W-2:0] waw_sum = waw + aw_len;
  wire         aw_hs = m_awvalid && m_awready;
  wire         w_start = !w_act && ( lq_cnt != 0 );

  assign m_wvalid = w_act && head_v;
  assign m_wdata  = head[63:0];
  assign m_wstrb  = head[71:64];
  assign m_wlast  = ( w_beat == w_len - 1'b1 );
  assign pop      = m_wvalid && m_wready;

  always @ ( posedge clk ) begin : proc_write
    flush_d <= flush;

    // Packer
    if ( push_part ) begin
      pc <= 2'd0;
    end else if ( push_full ) begin
      pk <= { 48'd0, tmp[79:64] };
      pc <= tot - 3'd4;
    end else begin
      pk <= tmp[63:0];
      pc <= tot[1:0];
    end
    if ( flush_now ) flushed <= 1'b1;
    if ( push && full ) overflow <= 1'b1;

    // FIFO
    if ( do_push ) begin
      mem[ wptr ] <= push_word;
      wptr <= wptr + 1'b1;
    end
    if ( load ) begin
      head   <= mem[ rptr ];
      rptr   <= rptr + 1'b1;
      head_v <= 1'b1;
    end else if ( pop ) begin
      head_v <= 1'b0;
    end
    mcount <= mcount + do_push - load;

    // AW
    unassigned <= unassigned + do_push - ( aw_go ? aw_len : 5'd0 );
    if ( aw_go ) begin
      m_awaddr  <= BASE + { waw, 3'b000 };
      m_awlen   <= aw_len - 1'b1;
      m_awvalid <= 1'b1;
      lq[ lq_wr ] <= aw_len;
      lq_wr     <= lq_wr + 1'b1;
      waw       <= ( waw_sum >= ring_words ) ? waw_sum - ring_words : waw_sum;
    end else if ( aw_hs ) begin
      m_awvalid <= 1'b0;
    end
    lq_cnt <= lq_cnt + aw_go - w_start;
    osd    <= osd + aw_hs - m_bvalid;

    // W
    if ( w_start ) begin
      w_act  <= 1'b1;
      w_len  <= lq[ lq_rd ];
      w_beat <= 5'd0;
      lq_rd  <= lq_rd + 1'b1;
    end else if ( pop ) begin
      w_beat <= w_beat + 1'b1;
      if ( m_wlast ) w_act <= 1'b0;
    end

    if ( abort ) last_req <= 1'b1;
    if ( flush_now ) last_req <= 1'b1;

    if ( arm ) begin
      flush_d  <= 1'b0;                       // done of the previous capture
      pk       <= 64'd0;
      pc       <= 2'd0;
      waw      <= {(W-2){1'b0}};
      last_req    <= 1'b0;
      flushed  <= 1'b0;
      overflow <= 1'b0;
    end
    if ( reset ) begin
      pc         <= 2'd0;
      wptr       <= {FB{1'b0}};
      rptr       <= {FB{1'b0}};
      mcount     <= {(FB+1){1'b0}};
      head_v     <= 1'b0;
      unassigned <= {(FB+1){1'b0}};
      last_req      <= 1'b0;
      flushed    <= 1'b0;
      overflow   <= 1'b0;
      waw        <= {(W-2){1'b0}};
      m_awvalid  <= 1'b0;
      lq_wr      <= 3'd0;
      lq_rd      <= 3'd0;
      lq_cnt     <= 4'd0;
      w_act      <= 1'b0;
      osd        <= 6'd0;
    end
  end // proc_write

  assign drained = ( mcount == 0 ) && !head_v && ( unassigned == 0 ) &&
                   !m_awvalid && ( lq_cnt == 0 ) && !w_act && ( osd == 0 );

  // ---------------------------------------------------------------------
  // Read cache: one 16 beat burst = 64 samples
  // ---------------------------------------------------------------------
  reg  [63:0]  rbuf [0:15];
  reg          rbuf_v;
  reg  [W-7:0] rtag, rtag_pend;
  reg          r_busy;
  reg  [3:0]   r_cnt;
  wire [W-7:0] tag = rj[W-1:6];
  wire [63:0]  rword = rbuf[ rj[5:2] ];

  always @ ( posedge clk ) begin : proc_read
    rd_ready <= 1'b0;
    if ( rbuf_v && rtag == tag ) begin
      rd_data  <= rword >> ( 16 * rj[1:0] );
      rd_ready <= 1'b1;
    end else if ( rd_en && !r_busy ) begin
      m_araddr  <= BASE + { tag, 7'b0000000 };
      m_arvalid <= 1'b1;
      r_busy    <= 1'b1;
      rtag_pend <= tag;
      rbuf_v    <= 1'b0;
      r_cnt     <= 4'd0;
    end
    if ( m_arvalid && m_arready ) m_arvalid <= 1'b0;
    if ( m_rvalid ) begin
      rbuf[ r_cnt ] <= m_rdata;
      r_cnt <= r_cnt + 1'b1;
      if ( m_rlast ) begin
        rbuf_v <= 1'b1;
        rtag   <= rtag_pend;
        r_busy <= 1'b0;
      end
    end
    if ( arm || reset ) begin
      rbuf_v    <= 1'b0;
    end
    if ( reset ) begin
      m_arvalid <= 1'b0;
      r_busy    <= 1'b0;
    end
  end // proc_read

endmodule // la16_store_ddr
`default_nettype wire
