/* ****************************************************************************
-- Source file: la16_capture.v
-- Description: la16 capture engine ( docs/PROTOCOL_LA16.md ).
--
--   Input   : two 16 bit samples per clock, s_lo earlier than s_hi ( IDDR on
--             a 100 MHz clock = 200 MS/s base rate ).
--   Divider : one sample is taken every ( divider + 1 ) base samples.
--   Trigger : one stage, AND of level ( mask / value ) and edge conditions
--             ( rise only, fall only, both masks set = any edge ), evaluated
--             on taken samples. All masks 0 = trigger on the first sample.
--   Buffer  : ring of 2^DEPTH_BITS samples in two BRAM banks ( even / odd
--             sample index ), so two samples can be written per clock.
--             PREFILL collects `pre` samples, WAIT keeps overwriting the
--             ring until the trigger, POST collects total - pre samples
--             starting with the trigger sample.
--   Readback: rd_idx = sample number 0 .. total-1 of the result, oldest
--             first; rd_data is valid 3 clocks later.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_capture
#(
  parameter DEPTH_BITS = 16
)
(
  input  wire                   clk,
  input  wire                   reset,
  input  wire [15:0]            s_lo,
  input  wire [15:0]            s_hi,

  input  wire [31:0]            divider,
  input  wire [DEPTH_BITS:0]    total,       // 1 .. 2^DEPTH_BITS
  input  wire [DEPTH_BITS:0]    pre,         // 0 .. total-1
  input  wire [15:0]            tl_mask,
  input  wire [15:0]            tl_value,
  input  wire [15:0]            tr_mask,
  input  wire [15:0]            tf_mask,

  input  wire                   arm,
  input  wire                   abort,

  output reg  [2:0]             state,       // ST_* below
  output wire [DEPTH_BITS:0]    captured,    // For STATUS frames
  output wire                   done,

  input  wire [DEPTH_BITS-1:0]  rd_idx,
  output reg  [15:0]            rd_data
);

  localparam ST_IDLE    = 3'd0;
  localparam ST_PREFILL = 3'd1;
  localparam ST_WAIT    = 3'd2;
  localparam ST_POST    = 3'd3;
  localparam ST_DONE    = 3'd5;

  localparam DEPTH = ( 1 << DEPTH_BITS );
  localparam AW    = DEPTH_BITS - 1;         // Address bits per bank

  reg  [15:0]            bank_e [0:DEPTH/2-1];
  reg  [15:0]            bank_o [0:DEPTH/2-1];

  reg  [31:0]            phase;              // Base samples until next take
  reg  [DEPTH_BITS-1:0]  wp;                 // Ring write pointer
  reg  [DEPTH_BITS:0]    pre_left;
  reg  [DEPTH_BITS:0]    post_left;
  reg  [DEPTH_BITS-1:0]  start;              // Ring index of result sample 0
  reg  [15:0]            prev;
  reg                    prev_v;

  wire [15:0]            r_only = tr_mask & ~tf_mask;
  wire [15:0]            f_only = tf_mask & ~tr_mask;
  wire [15:0]            any_e  = tr_mask &  tf_mask;
  wire                   use_edge = ( tr_mask | tf_mask ) != 16'd0;

  // ---------------------------------------------------------------------
  // Sample selection: lane 0 ( s_lo ) then lane 1 ( s_hi )
  // ---------------------------------------------------------------------
  wire                   take0 = ( phase == 32'd0 );
  wire [31:0]            phase1 = take0 ? divider : phase - 32'd1;
  wire                   take1 = ( phase1 == 32'd0 );
  wire [31:0]            phase2 = take1 ? divider : phase1 - 32'd1;

  function hit;
    input [15:0] x;
    input [15:0] p;
    input        p_v;
    begin
      hit = ( ( ( x ^ tl_value ) & tl_mask ) == 16'd0 ) &&
            ( !use_edge || ( p_v &&
              ( ( ~p &  x & r_only ) == r_only ) &&
              ( (  p & ~x & f_only ) == f_only ) &&
              ( ( ( p ^ x ) & any_e ) == any_e  ) ) );
    end
  endfunction

  // One taken sample through the state machine
  task step;
    input  [2:0]            st_i;
    input  [DEPTH_BITS-1:0] wp_i;
    input  [DEPTH_BITS:0]   pl_i;
    input  [DEPTH_BITS:0]   pol_i;
    input  [DEPTH_BITS-1:0] start_i;
    input  [15:0]           prev_i;
    input                   pv_i;
    input                   take;
    input  [15:0]           v;
    output [2:0]            st_o;
    output [DEPTH_BITS-1:0] wp_o;
    output [DEPTH_BITS:0]   pl_o;
    output [DEPTH_BITS:0]   pol_o;
    output [DEPTH_BITS-1:0] start_o;
    output [15:0]           prev_o;
    output                  pv_o;
    output                  we;
    begin
      st_o = st_i; wp_o = wp_i; pl_o = pl_i; pol_o = pol_i;
      start_o = start_i; prev_o = prev_i; pv_o = pv_i; we = 1'b0;
      if ( take ) begin
        case ( st_i )
          ST_PREFILL : begin
            we = 1'b1; wp_o = wp_i + 1'b1; prev_o = v; pv_o = 1'b1;
            pl_o = pl_i - 1'b1;
            if ( pl_i == 1 ) st_o = ST_WAIT;
          end
          ST_WAIT : begin
            we = 1'b1; wp_o = wp_i + 1'b1; prev_o = v; pv_o = 1'b1;
            if ( hit( v, prev_i, pv_i ) ) begin
              start_o = wp_i - pre[DEPTH_BITS-1:0];
              pol_o   = pol_i - 1'b1;
              st_o    = ( pol_i == 1 ) ? ST_DONE : ST_POST;
            end
          end
          ST_POST : begin
            we = 1'b1; wp_o = wp_i + 1'b1;
            pol_o = pol_i - 1'b1;
            if ( pol_i == 1 ) st_o = ST_DONE;
          end
          default : ;
        endcase
      end
    end
  endtask

  reg  [2:0]             st_a, st_b;
  reg  [DEPTH_BITS-1:0]  wp_a, wp_b;
  reg  [DEPTH_BITS:0]    pl_a, pl_b, pol_a, pol_b;
  reg  [DEPTH_BITS-1:0]  start_a, start_b;
  reg  [15:0]            prev_a, prev_b;
  reg                    pv_a, pv_b, we_a, we_b;

  always @ ( * ) begin : proc_lanes
    step( state, wp, pre_left, post_left, start, prev, prev_v, take0, s_lo,
          st_a, wp_a, pl_a, pol_a, start_a, prev_a, pv_a, we_a );
    step( st_a, wp_a, pl_a, pol_a, start_a, prev_a, pv_a, take1, s_hi,
          st_b, wp_b, pl_b, pol_b, start_b, prev_b, pv_b, we_b );
  end // proc_lanes

  // Lane 0 writes ring index wp, lane 1 writes wp_a. Indexes differ in bit 0
  // when both write, so each bank sees at most one write per clock.
  wire                   e_we   = ( we_a & ~wp[0] ) | ( we_b & ~wp_a[0] );
  wire [AW-1:0]          e_addr = ( we_a & ~wp[0] ) ? wp[DEPTH_BITS-1:1]
                                                    : wp_a[DEPTH_BITS-1:1];
  wire [15:0]            e_din  = ( we_a & ~wp[0] ) ? s_lo : s_hi;
  wire                   o_we   = ( we_a &  wp[0] ) | ( we_b &  wp_a[0] );
  wire [AW-1:0]          o_addr = ( we_a &  wp[0] ) ? wp[DEPTH_BITS-1:1]
                                                    : wp_a[DEPTH_BITS-1:1];
  wire [15:0]            o_din  = ( we_a &  wp[0] ) ? s_lo : s_hi;

  always @ ( posedge clk ) begin : proc_ram_wr
    if ( e_we ) bank_e[ e_addr ] <= e_din;
    if ( o_we ) bank_o[ o_addr ] <= o_din;
  end // proc_ram_wr

  // ---------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------
  always @ ( posedge clk ) begin : proc_ctrl
    if ( state == ST_PREFILL || state == ST_WAIT || state == ST_POST ) begin
      phase     <= phase2;
      state     <= st_b;
      wp        <= wp_b;
      pre_left  <= pl_b;
      post_left <= pol_b;
      start     <= start_b;
      prev      <= prev_b;
      prev_v    <= pv_b;
    end
    if ( arm ) begin
      phase     <= 32'd0;
      wp        <= {DEPTH_BITS{1'b0}};
      pre_left  <= pre;
      post_left <= total - pre;
      start     <= {DEPTH_BITS{1'b0}};
      prev_v    <= 1'b0;
      state     <= ( pre == 0 ) ? ST_WAIT : ST_PREFILL;
    end
    if ( abort ) begin
      state     <= ST_IDLE;
    end
    if ( reset ) begin
      state     <= ST_IDLE;
    end
  end // proc_ctrl

  assign done     = ( state == ST_DONE );
  assign captured = ( state == ST_PREFILL ) ? pre - pre_left :
                    ( state == ST_WAIT    ) ? pre :
                    ( state == ST_POST    ) ? total - post_left :
                    ( state == ST_DONE    ) ? total : {(DEPTH_BITS+1){1'b0}};

  // ---------------------------------------------------------------------
  // Readback ( 3 clock latency )
  // ---------------------------------------------------------------------
  reg  [DEPTH_BITS-1:0]  rd_ring;
  reg  [15:0]            rd_e, rd_o;
  reg                    rd_sel;

  always @ ( posedge clk ) begin : proc_ram_rd
    rd_ring <= start + rd_idx;
    rd_e    <= bank_e[ rd_ring[DEPTH_BITS-1:1] ];
    rd_o    <= bank_o[ rd_ring[DEPTH_BITS-1:1] ];
    rd_sel  <= rd_ring[0];
    rd_data <= rd_sel ? rd_o : rd_e;
  end // proc_ram_rd

endmodule // la16_capture
`default_nettype wire
