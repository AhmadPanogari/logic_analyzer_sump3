/* ****************************************************************************
-- Source file: tb_ols_cosim.v
-- Description: Byte level co-simulation top for ols_engine. cocotb
--              ( test_ols_cosim.py ) bridges rx/tx bytes to a TCP socket so
--              the real libsigrok OLS driver ( sigrok-cli / PulseView with
--              conn=tcp-raw/127.0.0.1/<port> ) talks to the RTL.
--   Probes  : 16 bit counter, +1 every clock ( checks sample order )
--   Pattern : PulseView / sigrok "pattern=Internal" selects la_test_pattern
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_ols_cosim;
  reg          clk = 0;
  reg          reset = 1;
  reg  [7:0]   rx_byte = 0;
  reg          rx_valid = 0;
  wire [7:0]   tx_byte;
  wire         tx_valid;
  reg          tx_ready = 0;
  wire         test_mode;
  wire         armed;
  wire         capturing;
  reg  [15:0]  cnt = 0;
  wire [15:0]  pattern;

  always #5 clk = ~clk;                       // 100 MHz
  always @ ( posedge clk ) cnt <= cnt + 1;
  initial begin
    #100 reset = 0;
  end

  la_test_pattern u_tp ( .clk( clk ), .reset( reset ), .pattern( pattern ) );

  ols_engine #( .DEPTH_BITS( 16 ) ) u_dut
  (
    .clk       ( clk                        ),
    .reset     ( reset                      ),
    .samples   ( test_mode ? pattern : cnt  ),
    .rx_byte   ( rx_byte                    ),
    .rx_valid  ( rx_valid                   ),
    .tx_byte   ( tx_byte                    ),
    .tx_valid  ( tx_valid                   ),
    .tx_ready  ( tx_ready                   ),
    .test_mode ( test_mode                  ),
    .armed     ( armed                      ),
    .capturing ( capturing                  )
  );
endmodule
`default_nettype wire
