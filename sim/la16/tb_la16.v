/* ****************************************************************************
-- Source file: tb_la16.v
-- Description: Byte level top for la16_engine unit tests ( test_la16.py ).
--   Samples : 16 bit counter at the 200 MS/s base rate: s_lo = n, s_hi = n+1
--   UART    : tx_ready drops for TX_GAP clocks after every byte
--   Small parameters for speed: DEPTH_BITS 12, CLK_HZ 1 MHz ( 1 ms = 1000 clk )
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_la16;
  reg          clk = 0;
  reg          reset = 1;
  reg  [7:0]   rx_byte = 0;
  reg          rx_valid = 0;
  wire [7:0]   tx_byte;
  wire         tx_valid;
  reg  [3:0]   gap = 0;
  wire         tx_ready = ( gap == 0 );
  wire         armed;
  wire         busy;
  reg  [15:0]  cnt = 0;
  reg          tx_take = 0;                  // Pulse per accepted byte ( for cocotb )
  reg  [7:0]   tx_last = 0;

  always #5 clk = ~clk;
  always @ ( posedge clk ) begin
    cnt     <= cnt + 2;
    tx_take <= tx_valid && tx_ready;
    if ( tx_valid && tx_ready ) tx_last <= tx_byte;
    if ( tx_valid && tx_ready ) gap <= 4'd3;
    else if ( gap != 0 )        gap <= gap - 1;
  end

  la16_engine #( .DEPTH_BITS( 12 ), .CLK_HZ( 1_000_000 ) ) u_dut
  (
    .clk      ( clk       ),
    .reset    ( reset     ),
    .s_lo     ( cnt       ),
    .s_hi     ( cnt + 16'd1 ),
    .rx_byte  ( rx_byte   ),
    .rx_valid ( rx_valid  ),
    .tx_byte  ( tx_byte   ),
    .tx_valid ( tx_valid  ),
    .tx_ready ( tx_ready  ),
    .armed    ( armed     ),
    .busy     ( busy      )
  );
endmodule
`default_nettype wire
