/* ****************************************************************************
-- Source file: tb_la16_cosim.v
-- Description: Byte level co-simulation top for la16_engine. cocotb
--              ( test_la16_cosim.py ) bridges rx/tx bytes to a TCP socket so
--              the libsigrok la16 driver ( sigrok-cli with
--              conn=tcp-raw/127.0.0.1/<port> ) talks to the RTL.
--   Probes  : 16 bit counter at the 200 MS/s base rate ( s_lo = n, s_hi = n+1 )
--   CLK_HZ  : 100 kHz for the ms timers only, so STATUS frames ( every 50 ms )
--             come often in wall clock time; the sample rate is unaffected
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_la16_cosim;
  reg          clk = 0;
  reg          reset = 1;
  reg  [7:0]   rx_byte = 0;
  reg          rx_valid = 0;
  wire [7:0]   tx_byte;
  wire         tx_valid;
  reg          tx_ready = 0;
  wire         armed;
  wire         busy;
  reg  [15:0]  cnt = 0;

  always #5 clk = ~clk;
  always @ ( posedge clk ) cnt <= cnt + 2;
  initial begin
    #100 reset = 0;
  end

  la16_engine #( .DEPTH_BITS( 16 ), .CLK_HZ( 100_000 ) ) u_dut
  (
    .clk      ( clk         ),
    .reset    ( reset       ),
    .s_lo     ( cnt         ),
    .s_hi     ( cnt + 16'd1 ),
    .rx_byte  ( rx_byte     ),
    .rx_valid ( rx_valid    ),
    .tx_byte  ( tx_byte     ),
    .tx_valid ( tx_valid    ),
    .tx_ready ( tx_ready    ),
    .armed    ( armed       ),
    .busy     ( busy        )
  );
endmodule
`default_nettype wire
