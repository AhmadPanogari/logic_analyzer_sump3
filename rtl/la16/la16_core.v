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
--     m_*             : AXI3 master to the PS DDR ( USE_DDR = 1, S_AXI_HP0 )
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_core
#(
  parameter        USE_DDR     = 0,
  parameter        W           = USE_DDR ? 28 : 16,
  // DDR ring 0x0200_0000 .. 0x1FFF_FFFF ( 480 MB ), the first 32 MB are
  // left for PS software ( Ethernet stage )
  parameter        MAX_SAMPLES = USE_DDR ? 251_658_240 : 65536,
  parameter [31:0] DDR_BASE    = 32'h0200_0000
)
(
  input  wire         clk_100m,
  input  wire [15:0]  probe_lo,
  input  wire [15:0]  probe_hi,
  input  wire         tp_sel,
  input  wire [1:0]   baud_sel,
  input  wire         uart_rx,
  output wire         uart_tx,
  output reg  [3:0]   led,

  output wire [31:0]  m_awaddr,
  output wire [3:0]   m_awlen,
  output wire [2:0]   m_awsize,
  output wire [1:0]   m_awburst,
  output wire [1:0]   m_awlock,
  output wire [3:0]   m_awcache,
  output wire [2:0]   m_awprot,
  output wire [3:0]   m_awqos,
  output wire [5:0]   m_awid,
  output wire         m_awvalid,
  input  wire         m_awready,
  output wire [63:0]  m_wdata,
  output wire [7:0]   m_wstrb,
  output wire         m_wlast,
  output wire [5:0]   m_wid,
  output wire         m_wvalid,
  input  wire         m_wready,
  input  wire [1:0]   m_bresp,
  input  wire [5:0]   m_bid,
  input  wire         m_bvalid,
  output wire         m_bready,
  output wire [31:0]  m_araddr,
  output wire [3:0]   m_arlen,
  output wire [2:0]   m_arsize,
  output wire [1:0]   m_arburst,
  output wire [1:0]   m_arlock,
  output wire [3:0]   m_arcache,
  output wire [2:0]   m_arprot,
  output wire [3:0]   m_arqos,
  output wire [5:0]   m_arid,
  output wire         m_arvalid,
  input  wire         m_arready,
  input  wire [63:0]  m_rdata,
  input  wire [1:0]   m_rresp,
  input  wire [5:0]   m_rid,
  input  wire         m_rlast,
  input  wire         m_rvalid,
  output wire         m_rready
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

la16_engine #( .W ( W ), .MAX_SAMPLES ( MAX_SAMPLES ), .USE_DDR ( USE_DDR ),
               .DDR_BASE ( DDR_BASE ), .CLK_HZ ( 100_000_000 ),
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
  .busy         ( busy            ),
  .m_awaddr  ( m_awaddr  ), .m_awlen   ( m_awlen   ), .m_awsize  ( m_awsize  ),
  .m_awburst ( m_awburst ), .m_awlock  ( m_awlock  ), .m_awcache ( m_awcache ),
  .m_awprot  ( m_awprot  ), .m_awqos   ( m_awqos   ), .m_awid    ( m_awid    ),
  .m_awvalid ( m_awvalid ), .m_awready ( m_awready ), .m_wdata   ( m_wdata   ),
  .m_wstrb   ( m_wstrb   ), .m_wlast   ( m_wlast   ), .m_wid     ( m_wid     ),
  .m_wvalid  ( m_wvalid  ), .m_wready  ( m_wready  ), .m_bresp   ( m_bresp   ),
  .m_bid     ( m_bid     ), .m_bvalid  ( m_bvalid  ), .m_bready  ( m_bready  ),
  .m_araddr  ( m_araddr  ), .m_arlen   ( m_arlen   ), .m_arsize  ( m_arsize  ),
  .m_arburst ( m_arburst ), .m_arlock  ( m_arlock  ), .m_arcache ( m_arcache ),
  .m_arprot  ( m_arprot  ), .m_arqos   ( m_arqos   ), .m_arid    ( m_arid    ),
  .m_arvalid ( m_arvalid ), .m_arready ( m_arready ), .m_rdata   ( m_rdata   ),
  .m_rresp   ( m_rresp   ), .m_rid     ( m_rid     ), .m_rlast   ( m_rlast   ),
  .m_rvalid  ( m_rvalid  ), .m_rready  ( m_rready  )
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
