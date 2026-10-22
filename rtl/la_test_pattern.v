/* ****************************************************************************
-- Source file: la_test_pattern.v
-- Description: Built-in stimulus for checking the logic analyzer end to end.
--              Signals are chosen so PulseView protocol decoders can be tried:
--   pattern[0]     uart_tx   115200 8N1, sends "Hello SUMP3 PulseView\r\n"
--   pattern[1]     spi_sclk  1 MHz, SPI mode 0
--   pattern[2]     spi_mosi  incrementing byte, MSB first
--   pattern[3]     spi_miso  inverted mosi
--   pattern[4]     spi_cs_n  active low, one byte per frame
--   pattern[12:5]  cnt[7:0]  8 bit counter, increments every 10.24 us
--   pattern[13]    pwm       1 kHz, duty cycle sweeps 0-100%
--   pattern[14]    pulse     single 10 ns pulse every 1 ms
--   pattern[15]    uart_busy high while a UART character is being sent
--              Assumes clk = 100 MHz.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_test_pattern
(
  input  wire         clk,
  input  wire         reset,
  output wire [15:0]  pattern
);

  localparam UART_DIV    = 868;   // 100 MHz / 115200
  localparam SPI_HALF    = 50;    // 100 MHz / 50 / 2 = 1 MHz
  localparam MSG_LEN     = 23;

  // ---------------------------------------------------------------------
  // UART TX
  // ---------------------------------------------------------------------
  reg  [9:0]   uart_div_cnt;
  reg  [3:0]   uart_bit_cnt;
  reg  [9:0]   uart_sr;
  reg          uart_tx;
  reg          uart_busy;
  reg  [4:0]   msg_ptr;
  reg  [19:0]  uart_gap_cnt;
  reg  [7:0]   msg_char;

  always @ ( * ) begin : proc_msg
    case ( msg_ptr )
      5'd0    : msg_char = "H";
      5'd1    : msg_char = "e";
      5'd2    : msg_char = "l";
      5'd3    : msg_char = "l";
      5'd4    : msg_char = "o";
      5'd5    : msg_char = " ";
      5'd6    : msg_char = "S";
      5'd7    : msg_char = "U";
      5'd8    : msg_char = "M";
      5'd9    : msg_char = "P";
      5'd10   : msg_char = "3";
      5'd11   : msg_char = " ";
      5'd12   : msg_char = "P";
      5'd13   : msg_char = "u";
      5'd14   : msg_char = "l";
      5'd15   : msg_char = "s";
      5'd16   : msg_char = "e";
      5'd17   : msg_char = "V";
      5'd18   : msg_char = "i";
      5'd19   : msg_char = "e";
      5'd20   : msg_char = "w";
      5'd21   : msg_char = 8'h0D;
      default : msg_char = 8'h0A;
    endcase
  end // proc_msg

  always @ ( posedge clk ) begin : proc_uart
    if ( uart_busy == 0 ) begin
      uart_tx <= 1;
      if ( uart_gap_cnt != 0 ) begin
        uart_gap_cnt <= uart_gap_cnt - 1;
      end else begin
        uart_busy    <= 1;
        uart_sr      <= { 1'b1, msg_char[7:0], 1'b0 };// Stop,Data,Start
        uart_bit_cnt <= 4'd0;
        uart_div_cnt <= 10'd0;
      end
    end else begin
      uart_tx <= uart_sr[0];
      if ( uart_div_cnt == UART_DIV-1 ) begin
        uart_div_cnt <= 10'd0;
        uart_sr      <= { 1'b1, uart_sr[9:1] };
        uart_bit_cnt <= uart_bit_cnt + 1;
        if ( uart_bit_cnt == 4'd9 ) begin
          uart_busy <= 0;
          if ( msg_ptr == MSG_LEN-1 ) begin
            msg_ptr      <= 5'd0;
            uart_gap_cnt <= 20'd200000;// 2 ms between messages
          end else begin
            msg_ptr      <= msg_ptr + 1;
            uart_gap_cnt <= 20'd200;   // 2 us between characters
          end
        end
      end else begin
        uart_div_cnt <= uart_div_cnt + 1;
      end
    end
    if ( reset == 1 ) begin
      uart_busy    <= 0;
      uart_tx      <= 1;
      msg_ptr      <= 5'd0;
      uart_gap_cnt <= 20'd1000;
      uart_div_cnt <= 10'd0;
      uart_bit_cnt <= 4'd0;
      uart_sr      <= 10'h3FF;
    end
  end // proc_uart


  // ---------------------------------------------------------------------
  // SPI master, mode 0 ( CPOL=0, CPHA=0 ), MSB first
  // ---------------------------------------------------------------------
  reg  [6:0]   spi_div_cnt;
  reg  [4:0]   spi_edge_cnt;
  reg  [7:0]   spi_byte;
  reg  [7:0]   spi_sr;
  reg          spi_sclk;
  reg          spi_cs_n;
  reg  [11:0]  spi_gap_cnt;

  always @ ( posedge clk ) begin : proc_spi
    if ( spi_cs_n == 1 ) begin
      spi_sclk <= 0;
      if ( spi_gap_cnt != 0 ) begin
        spi_gap_cnt <= spi_gap_cnt - 1;
      end else begin
        spi_cs_n     <= 0;
        spi_sr       <= spi_byte[7:0];
        spi_edge_cnt <= 5'd0;
        spi_div_cnt  <= 7'd0;
      end
    end else begin
      if ( spi_div_cnt == SPI_HALF-1 ) begin
        spi_div_cnt  <= 7'd0;
        spi_edge_cnt <= spi_edge_cnt + 1;
        if ( spi_edge_cnt == 5'd16 ) begin
          spi_cs_n    <= 1;            // Done, release CS 1/2 bit later
          spi_byte    <= spi_byte + 1;
          spi_gap_cnt <= 12'd1000;     // 10 us between frames
        end else if ( spi_edge_cnt[0] == 0 ) begin
          spi_sclk <= 1;                        // Rising edge : sample
        end else begin
          spi_sclk <= 0;                        // Falling edge : shift
          spi_sr   <= { spi_sr[6:0], 1'b0 };
        end
      end else begin
        spi_div_cnt <= spi_div_cnt + 1;
      end
    end
    if ( reset == 1 ) begin
      spi_cs_n     <= 1;
      spi_sclk     <= 0;
      spi_byte     <= 8'd0;
      spi_sr       <= 8'd0;
      spi_gap_cnt  <= 12'd100;
      spi_div_cnt  <= 7'd0;
      spi_edge_cnt <= 5'd0;
    end
  end // proc_spi


  // ---------------------------------------------------------------------
  // Counter, PWM and periodic pulse
  // ---------------------------------------------------------------------
  reg  [17:0]  free_cnt;
  reg  [16:0]  pwm_cnt;   // 100000 clocks = 1 ms
  reg  [16:0]  pwm_duty;
  reg          pwm;
  reg          pulse;

  always @ ( posedge clk ) begin : proc_misc
    free_cnt <= free_cnt + 1;
    pulse    <= 0;
    if ( pwm_cnt == 17'd99999 ) begin
      pwm_cnt <= 17'd0;
      pulse   <= 1;
      if ( pwm_duty >= 17'd100000 ) begin
        pwm_duty <= 17'd0;
      end else begin
        pwm_duty <= pwm_duty + 17'd5000;// 5% steps
      end
    end else begin
      pwm_cnt <= pwm_cnt + 1;
    end
    pwm <= ( pwm_cnt < pwm_duty );
    if ( reset == 1 ) begin
      free_cnt <= 18'd0;
      pwm_cnt  <= 17'd0;
      pwm_duty <= 17'd0;
      pwm      <= 0;
      pulse    <= 0;
    end
  end // proc_misc

  assign pattern[0]    = uart_tx;
  assign pattern[1]    = spi_sclk;
  assign pattern[2]    = spi_sr[7];
  assign pattern[3]    = ~spi_sr[7];
  assign pattern[4]    = spi_cs_n;
  assign pattern[12:5] = free_cnt[17:10];
  assign pattern[13]   = pwm;
  assign pattern[14]   = pulse;
  assign pattern[15]   = uart_busy;

endmodule // la_test_pattern.v
`default_nettype wire
