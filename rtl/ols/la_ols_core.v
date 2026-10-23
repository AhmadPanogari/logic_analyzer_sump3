/* ****************************************************************************
-- Source file: la_ols_core.v
-- Description: Board independent OLS / SUMP logic analyzer for PulseView.
--
--   PulseView ( driver "Openbench Logic Sniffer & SUMP compatibles" )
--     <-- USB-UART ( 921600 8N1 by default ) --> ols_engine --> 16 probes
--
--   Ports:
--     clk_100m    : 100 MHz. The OLS host assumes a 100 MHz reference clock.
--     probe[15:0] : asynchronous probe inputs
--     tp_sel      : 1 = internal test pattern on all 16 channels
--     baud_sel    : UART baud rate ( 1 = jumper closed )
--                     00 = 921600   01 = 460800   10 = 230400   11 = 115200
--                   The libsigrok 0.5.2 OLS driver ( PulseView 0.4.2 ) reads
--                   one byte per poll and loses bytes on long captures at
--                   921600 on Windows; 230400 or 115200 keeps up.
--                   ( PulseView "Pattern mode = Internal" does the same )
--     uart_rx/tx  : to the USB-UART, 8N1
--     led[3:0]    : active high. 0 heartbeat, 1 armed ( waiting for
--                   trigger ), 2 test pattern, 3 UART RX activity
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_ols_core
#(
  parameter DEPTH_BITS   = 16            // 64K samples
)
(
  input  wire         clk_100m,
  input  wire [15:0]  probe,
  input  wire         tp_sel,
  input  wire [1:0]   baud_sel,
  input  wire         uart_rx,
  output wire         uart_tx,
  output reg  [3:0]   led
);

  reg  [3:0]    reset_sr = 4'hF;
  wire          reset_loc;

  (* IOB = "TRUE", ASYNC_REG = "TRUE" *) reg  [15:0]   probe_meta;
  (* ASYNC_REG = "TRUE" *)               reg  [15:0]   probe_sync;
  (* ASYNC_REG = "TRUE" *)               reg  [1:0]    tp_sel_sr;
  (* ASYNC_REG = "TRUE" *)               reg  [1:0]    baud_meta;
  (* ASYNC_REG = "TRUE" *)               reg  [1:0]    baud_sync;
  reg  [15:0]   clks_per_bit = 16'd108;   // 921600 until the jumpers are read
  (* ASYNC_REG = "TRUE" *)               reg  [1:0]    rx_sr;

  wire [15:0]   test_pattern;
  wire          host_test_mode;
  wire          use_pattern;
  wire [15:0]   samples;
  wire [7:0]    rx_byte;
  wire          rx_valid;
  wire [7:0]    tx_byte;
  wire          tx_valid;
  wire          tx_ready;
  wire          armed;
  wire          capturing;
  reg  [26:0]   heartbeat_cnt;
  reg  [22:0]   rx_led_cnt;


//-----------------------------------------------------------------------------
// Power-on reset ( FPGA init values ) and input synchronizers
//-----------------------------------------------------------------------------
always @ ( posedge clk_100m ) begin : proc_reset_sync
  reset_sr   <= { reset_sr[2:0], 1'b0 };
  probe_meta <= probe[15:0];
  probe_sync <= probe_meta[15:0];
  tp_sel_sr  <= { tp_sel_sr[0], tp_sel };
  baud_meta  <= baud_sel;
  baud_sync  <= baud_meta;
  case ( baud_sync )
    2'b00   : clks_per_bit <= 16'd108;   // 921600 ( +0.5 % )
    2'b01   : clks_per_bit <= 16'd217;   // 460800 ( +0.0 % )
    2'b10   : clks_per_bit <= 16'd434;   // 230400 ( +0.0 % )
    default : clks_per_bit <= 16'd868;   // 115200 ( +0.0 % )
  endcase
  rx_sr      <= { rx_sr[0], uart_rx };
end // proc_reset_sync
  assign reset_loc = reset_sr[3];


//-----------------------------------------------------------------------------
// Test pattern ( UART 115200, SPI 1 MHz, counter, PWM, 10 ns pulse )
//-----------------------------------------------------------------------------
la_test_pattern u_la_test_pattern
(
  .clk          ( clk_100m            ),
  .reset        ( reset_loc           ),
  .pattern      ( test_pattern[15:0]  )
);// u_la_test_pattern

  assign use_pattern = tp_sel_sr[1] | host_test_mode;
  assign samples     = use_pattern ? test_pattern : probe_sync;


//-----------------------------------------------------------------------------
// UART + OLS engine
//-----------------------------------------------------------------------------
ols_uart_rx u_ols_uart_rx
(
  .clk          ( clk_100m        ),
  .reset        ( reset_loc       ),
  .clks_per_bit ( clks_per_bit    ),
  .rx           ( rx_sr[1]        ),
  .rx_byte      ( rx_byte         ),
  .rx_valid     ( rx_valid        )
);

ols_uart_tx u_ols_uart_tx
(
  .clk          ( clk_100m        ),
  .reset        ( reset_loc       ),
  .clks_per_bit ( clks_per_bit    ),
  .tx_byte      ( tx_byte         ),
  .tx_valid     ( tx_valid        ),
  .tx_ready     ( tx_ready        ),
  .tx           ( uart_tx         )
);

ols_engine #( .DEPTH_BITS ( DEPTH_BITS ) ) u_ols_engine
(
  .clk          ( clk_100m        ),
  .reset        ( reset_loc       ),
  .samples      ( samples         ),
  .rx_byte      ( rx_byte         ),
  .rx_valid     ( rx_valid        ),
  .tx_byte      ( tx_byte         ),
  .tx_valid     ( tx_valid        ),
  .tx_ready     ( tx_ready        ),
  .test_mode    ( host_test_mode  ),
  .armed        ( armed           ),
  .capturing    ( capturing       )
);


//-----------------------------------------------------------------------------
// LEDs
//-----------------------------------------------------------------------------
always @ ( posedge clk_100m ) begin : proc_led
  heartbeat_cnt <= heartbeat_cnt + 1;
  if ( rx_sr[1] == 0 ) begin
    rx_led_cnt <= {23{1'b1}};            // ~84 ms stretch
  end else if ( rx_led_cnt != 0 ) begin
    rx_led_cnt <= rx_led_cnt - 1;
  end
  led[0] <= heartbeat_cnt[26];
  led[1] <= armed;
  led[2] <= use_pattern;
  led[3] <= ( rx_led_cnt != 0 );
  if ( reset_loc == 1 ) begin
    heartbeat_cnt <= 27'd0;
    rx_led_cnt    <= 23'd0;
  end
end // proc_led

endmodule // la_ols_core.v
`default_nettype wire
