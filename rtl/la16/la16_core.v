/* ****************************************************************************
-- Source file: la16_core.v
-- Description: Board independent la16 logic analyzer ( docs/PROTOCOL_LA16.md ).
--
--   Host <-- USB-UART ( 921600 8N1 by default ) --> la16_engine --> 16 probes
--
--   Ports:
--     clk_100m        : 100 MHz
--     probe_lo/hi     : probes sampled on the rising / falling edge of
--                       clk_100m ( IDDR outputs at the board top level, both
--                       already registered on the rising edge ), so the base
--                       sample rate is 200 MS/s
--     tp_sel          : 1 = internal test pattern ( each value twice )
--     baud_sel        : 00 = 921600  01 = 460800  10 = 230400  11 = 115200
--     uart_rx/tx      : to the USB-UART, 8N1
--     led[3:0]        : active high. 0 heartbeat, 1 armed ( prefill or
--                       waiting for trigger ), 2 test pattern, 3 UART RX
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_core
#(
  parameter DEPTH_BITS = 16                  // 64K samples in BRAM
)
(
  input  wire         clk_100m,
  input  wire [15:0]  probe_lo,
  input  wire [15:0]  probe_hi,
  input  wire         tp_sel,
  input  wire [1:0]   baud_sel,
  input  wire         uart_rx,
  output wire         uart_tx,
  output reg  [3:0]   led
);

  reg  [3:0]    reset_sr = 4'hF;
  wire          reset_loc;

  (* ASYNC_REG = "TRUE" *) reg  [31:0]   probe_sync;
  (* ASYNC_REG = "TRUE" *) reg  [1:0]    tp_sel_sr;
  (* ASYNC_REG = "TRUE" *) reg  [1:0]    baud_meta;
  (* ASYNC_REG = "TRUE" *) reg  [1:0]    baud_sync;
  (* ASYNC_REG = "TRUE" *) reg  [1:0]    rx_sr;
  reg  [15:0]   clks_per_bit = 16'd108;
  reg  [31:0]   samples;

  wire [15:0]   test_pattern;
  wire [7:0]    rx_byte;
  wire          rx_valid;
  wire [7:0]    tx_byte;
  wire          tx_valid;
  wire          tx_ready;
  wire          armed;
  wire          busy;
  reg  [26:0]   heartbeat_cnt;
  reg  [22:0]   rx_led_cnt;


//-----------------------------------------------------------------------------
// Power-on reset and synchronizers. probe_lo/hi come from IDDR flops, this
// is the second stage.
//-----------------------------------------------------------------------------
always @ ( posedge clk_100m ) begin : proc_reset_sync
  reset_sr   <= { reset_sr[2:0], 1'b0 };
  probe_sync <= { probe_hi, probe_lo };
  tp_sel_sr  <= { tp_sel_sr[0], tp_sel };
  baud_meta  <= baud_sel;
  baud_sync  <= baud_meta;
  case ( baud_sync )
    2'b00   : clks_per_bit <= 16'd108;   // 921600 ( +0.5 % )
    2'b01   : clks_per_bit <= 16'd217;   // 460800
    2'b10   : clks_per_bit <= 16'd434;   // 230400
    default : clks_per_bit <= 16'd868;   // 115200
  endcase
  rx_sr      <= { rx_sr[0], uart_rx };
  samples    <= tp_sel_sr[1] ? { test_pattern, test_pattern } : probe_sync;
end // proc_reset_sync
  assign reset_loc = reset_sr[3];


la_test_pattern u_la_test_pattern
(
  .clk          ( clk_100m            ),
  .reset        ( reset_loc           ),
  .pattern      ( test_pattern[15:0]  )
);// u_la_test_pattern


//-----------------------------------------------------------------------------
// UART + la16 engine
//-----------------------------------------------------------------------------
ols_uart_rx u_uart_rx
(
  .clk          ( clk_100m        ),
  .reset        ( reset_loc       ),
  .clks_per_bit ( clks_per_bit    ),
  .rx           ( rx_sr[1]        ),
  .rx_byte      ( rx_byte         ),
  .rx_valid     ( rx_valid        )
);

ols_uart_tx u_uart_tx
(
  .clk          ( clk_100m        ),
  .reset        ( reset_loc       ),
  .clks_per_bit ( clks_per_bit    ),
  .tx_byte      ( tx_byte         ),
  .tx_valid     ( tx_valid        ),
  .tx_ready     ( tx_ready        ),
  .tx           ( uart_tx         )
);

la16_engine #( .DEPTH_BITS ( DEPTH_BITS ), .CLK_HZ ( 100_000_000 ),
               .BASE_HZ ( 200_000_000 ) ) u_la16_engine
(
  .clk          ( clk_100m        ),
  .reset        ( reset_loc       ),
  .s_lo         ( samples[15:0]   ),
  .s_hi         ( samples[31:16]  ),
  .rx_byte      ( rx_byte         ),
  .rx_valid     ( rx_valid        ),
  .tx_byte      ( tx_byte         ),
  .tx_valid     ( tx_valid        ),
  .tx_ready     ( tx_ready        ),
  .armed        ( armed           ),
  .busy         ( busy            )
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
  led[2] <= tp_sel_sr[1];
  led[3] <= ( rx_led_cnt != 0 );
  if ( reset_loc == 1 ) begin
    heartbeat_cnt <= 27'd0;
    rx_led_cnt    <= 23'd0;
  end
end // proc_led

endmodule // la16_core.v
`default_nettype wire
