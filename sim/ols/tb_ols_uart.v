/* ****************************************************************************
-- Source file: tb_ols_uart.v
-- Description: la_top_s9_ols at the pin level: the testbench talks OLS over
--              the UART at 921600 baud ( PS7 replaced by sim/la_ps_wrapper_stub.v )
--   1) 5x reset + ID       -> expect "1ALS"
--   2) metadata            -> expect device name token "AntMiner S9 LA"
--   3) capture 16 samples of the test pattern ( J9 jumper closed )
--   Run with sim/ols/run_uart_sim.sh
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_ols_uart;
  localparam real BIT_NS = 1.0e9 / 921600.0;

  reg          bd_rx = 1;
  wire         bd_tx;
  wire [3:0]   led_n;
  reg  [15:0]  probe = 16'h0000;
  reg  [7:0]   rx_buf [0:255];
  integer      rx_cnt = 0;
  integer      errors = 0;
  integer      i;

  la_top_s9_ols u_dut
  (
    .probe    ( probe     ),
    .tp_sel_n ( 1'b0      ),    // Jumper closed: test pattern
    .bd_rx    ( bd_rx     ),
    .bd_tx    ( bd_tx     ),
    .led_n    ( led_n     )
  );

  task send_byte ( input [7:0] b );
    integer k;
    begin
      bd_rx = 0; #( BIT_NS );
      for ( k = 0; k < 8; k = k + 1 ) begin
        bd_rx = b[k]; #( BIT_NS );
      end
      bd_rx = 1; #( BIT_NS );
    end
  endtask

  task send_long ( input [7:0] op, input [31:0] d );
    begin
      send_byte( op );
      send_byte( d[7:0] );  send_byte( d[15:8] );
      send_byte( d[23:16] ); send_byte( d[31:24] );
    end
  endtask

  always begin : proc_rx
    integer k;
    reg [7:0] b;
    @( negedge bd_tx );
    #( BIT_NS * 1.5 );
    for ( k = 0; k < 8; k = k + 1 ) begin
      b[k] = bd_tx; #( BIT_NS );
    end
    rx_buf[ rx_cnt % 256 ] = b;
    rx_cnt = rx_cnt + 1;
  end

  initial begin
    #2000;
    for ( i = 0; i < 5; i = i + 1 ) send_byte( 8'h00 );
    send_byte( 8'h02 );
    #( BIT_NS * 60 );
    $display( "ID : %s%s%s%s", rx_buf[0], rx_buf[1], rx_buf[2], rx_buf[3] );
    if ( { rx_buf[0], rx_buf[1], rx_buf[2], rx_buf[3] } != "1ALS" ) begin
      $display( "ERROR: bad ID" ); errors = errors + 1;
    end

    rx_cnt = 0;
    send_byte( 8'h04 );
    #( BIT_NS * 10 * 50 );
    $display( "metadata bytes : %0d", rx_cnt );
    if ( rx_cnt != 42 || rx_buf[0] != 8'h01 || rx_buf[1] != "A" ) begin
      $display( "ERROR: bad metadata" ); errors = errors + 1;
    end

    // 16 samples at 100 MHz, no trigger ( stage 0 mask 0 = fire at once )
    rx_cnt = 0;
    send_long( 8'hC0, 32'd0 );
    send_long( 8'hC1, 32'd0 );
    send_long( 8'hC2, 32'h0800_0000 );   // Level 0, start
    send_long( 8'h80, 32'd0 );           // Divider 0 = 100 MHz
    send_long( 8'h81, { 16'd3, 16'd3 } );// Read 16, delay 16
    send_long( 8'h82, 32'h0000_0030 );   // Groups 3,4 disabled -> 2 bytes/sample
    send_byte( 8'h01 );                  // Arm
    #( BIT_NS * 10 * 40 );
    $display( "sample bytes : %0d ( expect 32 )", rx_cnt );
    if ( rx_cnt != 32 ) begin
      $display( "ERROR: bad sample count" ); errors = errors + 1;
    end
    $display( "LEDs ( active low ) : %b", led_n );

    if ( errors == 0 ) $display( "PASS" );
    else               $display( "FAIL ( %0d errors )", errors );
    $finish;
  end

  initial begin
    #( 10_000_000 );
    $display( "FAIL : timeout" );
    $finish;
  end
endmodule
`default_nettype wire
