/* ****************************************************************************
-- Source file: la16_front.v
-- Description: la16 capture front end, one pipeline stage ahead of la16_seq.
--
--   Input   : two 16 bit samples per clock, s_lo earlier than s_hi.
--   Divider : one sample is taken every ( divider + 1 ) base samples.
--   Trigger : one stage, AND of level ( mask / value ) and edge conditions
--             ( rise only, fall only, both masks set = any edge ). Edges
--             compare with the previous taken sample since arm.
--   Output  : registered per lane: v = sample, t = taken, h = trigger
--             condition true for that taken sample. arm clears t0/t1 so the
--             clock after arm carries no stale samples.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_front
(
  input  wire         clk,
  input  wire [15:0]  s_lo,
  input  wire [15:0]  s_hi,
  input  wire [31:0]  divider,
  input  wire [15:0]  tl_mask,
  input  wire [15:0]  tl_value,
  input  wire [15:0]  tr_mask,
  input  wire [15:0]  tf_mask,
  input  wire         arm,
  output reg  [15:0]  v0,
  output reg  [15:0]  v1,
  output reg          t0,
  output reg          t1,
  output reg          h0,
  output reg          h1
);

  reg  [31:0]  phase;                         // Base samples until next take
  reg  [15:0]  prev;
  reg          prev_v;

  wire [15:0]  r_only   = tr_mask & ~tf_mask;
  wire [15:0]  f_only   = tf_mask & ~tr_mask;
  wire [15:0]  any_e    = tr_mask &  tf_mask;
  wire         use_edge = ( tr_mask | tf_mask ) != 16'd0;

  wire         take0  = ( phase == 32'd0 );
  wire [31:0]  phase1 = take0 ? divider : phase - 32'd1;
  wire         take1  = ( phase1 == 32'd0 );
  wire [31:0]  phase2 = take1 ? divider : phase1 - 32'd1;

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

  always @ ( posedge clk ) begin : proc_front
    phase <= phase2;
    v0    <= s_lo;
    v1    <= s_hi;
    t0    <= take0;
    t1    <= take1;
    h0    <= hit( s_lo, prev, prev_v );
    h1    <= take0 ? hit( s_hi, s_lo, 1'b1 ) : hit( s_hi, prev, prev_v );
    if ( take1 ) begin
      prev   <= s_hi;
      prev_v <= 1'b1;
    end else if ( take0 ) begin
      prev   <= s_lo;
      prev_v <= 1'b1;
    end
    if ( arm ) begin
      phase  <= 32'd0;
      prev_v <= 1'b0;
      t0     <= 1'b0;
      t1     <= 1'b0;
    end
  end // proc_front

endmodule // la16_front
`default_nettype wire
