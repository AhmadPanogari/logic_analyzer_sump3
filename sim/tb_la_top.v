/* ****************************************************************************
-- Source file: tb_la_top.v
-- Description: Smoke test for la_top ( or la_top_s9 with -DS9 ). Acts like bd_server.py over the UART:
--   1) Sends "\n" so mesa_uart autobauds ( 921600 baud )
--   2) MesaBus write  0x98 <= 0x0000000B   ( SUMP3 cmd_rd_hw_id_rev )
--   3) MesaBus read   0x9C                 ( expect 0x53 "S3" in [31:24] )
--   4) Decodes the test pattern UART on pattern[0] ( 115200 baud )
--   Run with sim/run_sim.sh
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_la_top;

  localparam real CLK_PERIOD  = 10.0;           // 100 MHz ( MMCM bypassed )
  localparam real BIT_NS      = 1.0e9 / 921600.0;
  localparam real TP_BIT_NS   = 8680.0;         // la_test_pattern 115200

  reg          sys_clk = 0;
  reg  [3:0]   btn     = 4'd0;
  reg  [1:0]   sw      = 2'b01;   // Test pattern on probe pod
  reg  [15:0]  probe   = 16'd0;
  reg          bd_rx   = 1;
  wire         bd_tx;
  wire [3:0]   led;

  reg  [8*64-1:0] rx_str;
  integer         rx_len;
  integer         errors = 0;

  always #( CLK_PERIOD / 2.0 ) sys_clk = ~sys_clk;

`ifdef S9
  // Antminer S9 top : clock from the PS stub, test pattern via J9 jumper
  wire [3:0] led_n;
  assign led = ~led_n;
  la_top_s9 u_dut
  (
    .probe    ( probe     ),
    .tp_sel_n ( ~sw[0]    ),
    .bd_rx    ( bd_rx     ),
    .bd_tx    ( bd_tx     ),
    .led_n    ( led_n     )
  );
`else
  la_top u_dut
  (
    .sys_clk ( sys_clk ),
    .btn     ( btn     ),
    .sw      ( sw      ),
    .probe   ( probe   ),
    .bd_rx   ( bd_rx   ),
    .bd_tx   ( bd_tx   ),
    .led     ( led     )
  );
`endif

  task uart_send_byte ( input [7:0] b );
    integer i;
    begin
      bd_rx = 0; #( BIT_NS );
      for ( i = 0; i < 8; i = i + 1 ) begin
        bd_rx = b[i]; #( BIT_NS );
      end
      bd_rx = 1; #( BIT_NS );
    end
  endtask

  task uart_send_str ( input [8*64-1:0] s, input integer n );
    integer i;
    begin
      for ( i = n - 1; i >= 0; i = i - 1 ) begin
        uart_send_byte( s[i*8 +: 8] );
      end
    end
  endtask

  // Capture bytes coming back from the FPGA on bd_tx
  always begin : proc_rx
    integer i;
    reg [7:0] b;
    @( negedge bd_tx );
    #( BIT_NS * 1.5 );
    for ( i = 0; i < 8; i = i + 1 ) begin
      b[i] = bd_tx; #( BIT_NS );
    end
    rx_str = { rx_str[8*63-1:0], b };
    rx_len = rx_len + 1;
  end

  // Decode the internal test pattern UART ( pattern[0] -> pod0 bit 0 )
  wire tp_uart = u_dut.u_la_core.u_la_test_pattern.pattern[0];
  reg  [8*32-1:0] tp_str = 0;
  integer         tp_len = 0;
  always begin : proc_tp_rx
    integer i;
    reg [7:0] b;
    @( negedge tp_uart );
    #( TP_BIT_NS * 1.5 );
    for ( i = 0; i < 8; i = i + 1 ) begin
      b[i] = tp_uart; #( TP_BIT_NS );
    end
    tp_str = { tp_str[8*31-1:0], b };
    tp_len = tp_len + 1;
  end

  function [7:0] hex2nib ( input [7:0] c );
    begin
      if ( c >= "a" ) hex2nib = c - "a" + 10;
      else if ( c >= "A" ) hex2nib = c - "A" + 10;
      else hex2nib = c - "0";
    end
  endfunction

  reg [31:0] rd_data;
  reg [7:0]  nib;
  integer    k;

  initial begin
    rx_str = 0; rx_len = 0;
    #( 2000 );
    // bd_server.py sends 256x "FF" then "\n" when it opens the port
    uart_send_str( "FFFF\n", 5 );
    #( BIT_NS * 20 );
    // Write : FFF0 + slot 00 + subslot 0 + cmd 0 (wr) + 08 bytes + addr + data
    uart_send_str( "FFF0000008000000980000000b\n", 27 );
    #( BIT_NS * 20 );
    rx_len = 0;
    // Read  : FFF0 + slot 00 + subslot 0 + cmd 1 (rd) + 08 bytes + addr + len
    uart_send_str( "FFF00001080000009c00000001\n", 27 );
    #( BIT_NS * 10 * 40 );

    if ( rx_str[7:0] == 8'h0A ) rx_str = rx_str >> 8;// Strip trailing "\n"
    $display( "MesaBus read reply : %s", rx_str[8*16-1:0] );
    rd_data = 0;
    for ( k = 7; k >= 0; k = k - 1 ) begin
      nib     = hex2nib( rx_str[k*8 +: 8] );
      rd_data = { rd_data[27:0], nib[3:0] };
    end
    $display( "SUMP3 hw_id_rev = 0x%08x", rd_data );
    if ( rx_str[8*16-1:8*8] != "F0FE0004" && rx_str[8*16-1:8*8] != "f0fe0004" ) begin
      $display( "ERROR: bad MesaBus reply header" ); errors = errors + 1;
    end
    if ( rd_data[31:24] != 8'h53 ) begin
      $display( "ERROR: expected hw_id 0x53 ( S3 )" ); errors = errors + 1;
    end
    if ( rd_data[15:8] != 8'd1 ) begin
      $display( "ERROR: expected 1 RLE hub" ); errors = errors + 1;
    end

    // Wait for the test pattern UART to send the first message
    wait ( tp_len >= 23 );
    $display( "Test pattern UART : %s", tp_str[8*23-1:8*2] );
    if ( tp_str[8*23-1:8*2] != "Hello SUMP3 PulseView" ) begin
      $display( "ERROR: test pattern UART mismatch" ); errors = errors + 1;
    end

    if ( errors == 0 ) $display( "PASS" );
    else               $display( "FAIL ( %0d errors )", errors );
    $finish;
  end

  initial begin
    #( 20_000_000 );
    $display( "FAIL : timeout" );
    $finish;
  end

endmodule
`default_nettype wire
