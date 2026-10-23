/* ****************************************************************************
-- Source file: la16_seq.v
-- Description: la16 capture sequencer. Takes the la16_front lanes and decides
--              which samples go into the ring buffer and where.
--
--   Ring    : `ring` samples ( >= total ), index wraps from ring-1 to 0.
--   PREFILL : collects `pre` samples, no trigger yet.
--   WAIT    : keeps overwriting the ring until a lane has its trigger hit.
--   POST    : collects total - pre samples, starting with the trigger sample.
--   DONE    : result = `total` samples from ring index `start` ( wrapping ).
--   we0/wi0/sv0, we1/wi1/sv1 : write enable, ring index and sample for lane 0
--             and lane 1, registered ( one clock after the lanes came in ).
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_seq
#(
  parameter W = 16                           // Ring index bits
)
(
  input  wire          clk,
  input  wire          reset,
  input  wire [15:0]   v0,
  input  wire [15:0]   v1,
  input  wire          t0,
  input  wire          t1,
  input  wire          h0,
  input  wire          h1,
  input  wire [W:0]    total,                // 1 .. ring
  input  wire [W:0]    pre,                  // 0 .. total-1
  input  wire [W:0]    ring,                 // Ring size in samples
  input  wire          arm,
  input  wire          abort,
  output reg  [2:0]    state,
  output wire [W:0]    captured,             // For STATUS frames
  output wire          done,
  output reg  [W-1:0]  start,
  output reg           we0,
  output reg           we1,
  output reg  [W-1:0]  wi0,
  output reg  [W-1:0]  wi1,
  output reg  [15:0]   sv0,
  output reg  [15:0]   sv1
);

  localparam ST_IDLE    = 3'd0;
  localparam ST_PREFILL = 3'd1;
  localparam ST_WAIT    = 3'd2;
  localparam ST_POST    = 3'd3;
  localparam ST_DONE    = 3'd5;

  reg  [W-1:0]  wp;
  reg  [W:0]    pre_left;
  reg  [W:0]    post_left;
  reg  [W-1:0]  ring_m1;

  function [W-1:0] inc;
    input [W-1:0] x;
    begin
      inc = ( x == ring_m1 ) ? {W{1'b0}} : x + 1'b1;
    end
  endfunction

  // Ring index of result sample 0 when the trigger sample sits at x
  function [W-1:0] start_of;
    input [W-1:0] x;
    begin
      start_of = ( { 1'b0, x } >= pre ) ? x - pre[W-1:0]
                                        : x + ring[W-1:0] - pre[W-1:0];
    end
  endfunction

  task step;
    input  [2:0]    st_i;
    input  [W-1:0]  wp_i;
    input  [W:0]    pl_i;
    input  [W:0]    pol_i;
    input  [W-1:0]  start_i;
    input           take;
    input           h;
    output [2:0]    st_o;
    output [W-1:0]  wp_o;
    output [W:0]    pl_o;
    output [W:0]    pol_o;
    output [W-1:0]  start_o;
    output          we;
    begin
      st_o = st_i; wp_o = wp_i; pl_o = pl_i; pol_o = pol_i;
      start_o = start_i; we = 1'b0;
      if ( take ) begin
        case ( st_i )
          ST_PREFILL : begin
            we = 1'b1; wp_o = inc( wp_i );
            pl_o = pl_i - 1'b1;
            if ( pl_i == 1 ) st_o = ST_WAIT;
          end
          ST_WAIT : begin
            we = 1'b1; wp_o = inc( wp_i );
            if ( h ) begin
              start_o = start_of( wp_i );
              pol_o   = pol_i - 1'b1;
              st_o    = ( pol_i == 1 ) ? ST_DONE : ST_POST;
            end
          end
          ST_POST : begin
            we = 1'b1; wp_o = inc( wp_i );
            pol_o = pol_i - 1'b1;
            if ( pol_i == 1 ) st_o = ST_DONE;
          end
          default : ;
        endcase
      end
    end
  endtask

  reg  [2:0]    st_a, st_b;
  reg  [W-1:0]  wp_a, wp_b;
  reg  [W:0]    pl_a, pl_b, pol_a, pol_b;
  reg  [W-1:0]  start_a, start_b;
  reg           we_a, we_b;

  always @ ( * ) begin : proc_lanes
    step( state, wp, pre_left, post_left, start, t0, h0,
          st_a, wp_a, pl_a, pol_a, start_a, we_a );
    step( st_a, wp_a, pl_a, pol_a, start_a, t1, h1,
          st_b, wp_b, pl_b, pol_b, start_b, we_b );
  end // proc_lanes

  always @ ( posedge clk ) begin : proc_seq
    we0 <= 1'b0;
    we1 <= 1'b0;
    sv0 <= v0;
    sv1 <= v1;
    if ( state == ST_PREFILL || state == ST_WAIT || state == ST_POST ) begin
      state     <= st_b;
      wp        <= wp_b;
      pre_left  <= pl_b;
      post_left <= pol_b;
      start     <= start_b;
      we0       <= we_a;
      we1       <= we_b;
      wi0       <= wp;
      wi1       <= wp_a;
    end
    if ( arm ) begin
      wp        <= {W{1'b0}};
      ring_m1   <= ring[W-1:0] - 1'b1;
      pre_left  <= pre;
      post_left <= total - pre;
      start     <= {W{1'b0}};
      state     <= ( pre == 0 ) ? ST_WAIT : ST_PREFILL;
    end
    if ( abort || reset ) begin
      state     <= ST_IDLE;
    end
  end // proc_seq

  assign done     = ( state == ST_DONE );
  assign captured = ( state == ST_PREFILL ) ? pre - pre_left :
                    ( state == ST_WAIT    ) ? pre :
                    ( state == ST_POST    ) ? total - post_left :
                    ( state == ST_DONE    ) ? total : {(W+1){1'b0}};

endmodule // la16_seq
`default_nettype wire
