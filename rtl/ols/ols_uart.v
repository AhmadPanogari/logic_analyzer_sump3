/* ****************************************************************************
-- Source file: ols_uart.v
-- Description: Small 8N1 UART receiver and transmitter for the OLS engine.
--              CLKS_PER_BIT = clk frequency / baud rate
--              ( 100 MHz / 921600 = 108, error 0.5 % ).
--              The RX input must already be synchronized to clk.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module ols_uart_rx
#(
  parameter CLKS_PER_BIT = 108
)
(
  input  wire        clk,
  input  wire        reset,
  input  wire        rx,
  output reg  [7:0]  rx_byte,
  output reg         rx_valid
);

  localparam CW = 16;

  reg  [CW-1:0]  clk_cnt;
  reg  [3:0]     bit_cnt;
  reg  [7:0]     shift;
  reg            busy;

  always @ ( posedge clk ) begin : proc_rx
    rx_valid <= 0;
    if ( busy == 0 ) begin
      if ( rx == 0 ) begin
        busy    <= 1;
        clk_cnt <= CLKS_PER_BIT / 2;   // Sample in the middle of each bit
        bit_cnt <= 4'd0;
      end
    end else begin
      if ( clk_cnt == 0 ) begin
        clk_cnt <= CLKS_PER_BIT - 1;
        bit_cnt <= bit_cnt + 1;
        if ( bit_cnt == 4'd0 ) begin
          if ( rx == 1 ) begin
            busy <= 0;                 // Glitch, not a start bit
          end
        end else if ( bit_cnt <= 4'd8 ) begin
          shift <= { rx, shift[7:1] }; // LSB first
        end else begin
          busy <= 0;                   // Stop bit
          if ( rx == 1 ) begin
            rx_byte  <= shift;
            rx_valid <= 1;
          end
        end
      end else begin
        clk_cnt <= clk_cnt - 1;
      end
    end
    if ( reset == 1 ) begin
      busy     <= 0;
      rx_valid <= 0;
    end
  end // proc_rx

endmodule // ols_uart_rx


module ols_uart_tx
#(
  parameter CLKS_PER_BIT = 108
)
(
  input  wire        clk,
  input  wire        reset,
  input  wire [7:0]  tx_byte,
  input  wire        tx_valid,   // Byte accepted when tx_valid & tx_ready
  output wire        tx_ready,
  output reg         tx
);

  localparam CW = 16;

  reg  [CW-1:0]  clk_cnt;
  reg  [3:0]     bit_cnt;
  reg  [9:0]     shift;
  reg            busy;

  assign tx_ready = ~busy;

  always @ ( posedge clk ) begin : proc_tx
    if ( busy == 0 ) begin
      tx <= 1;
      if ( tx_valid == 1 ) begin
        busy    <= 1;
        shift   <= { 1'b1, tx_byte, 1'b0 };// Stop, data, start
        bit_cnt <= 4'd0;
        clk_cnt <= CLKS_PER_BIT - 1;
        tx      <= 0;
      end
    end else begin
      if ( clk_cnt == 0 ) begin
        clk_cnt <= CLKS_PER_BIT - 1;
        bit_cnt <= bit_cnt + 1;
        shift   <= { 1'b1, shift[9:1] };
        tx      <= shift[1];
        if ( bit_cnt == 4'd9 ) begin
          busy <= 0;
          tx   <= 1;
        end
      end else begin
        clk_cnt <= clk_cnt - 1;
      end
    end
    if ( reset == 1 ) begin
      busy <= 0;
      tx   <= 1;
    end
  end // proc_tx

endmodule // ols_uart_tx
`default_nettype wire
