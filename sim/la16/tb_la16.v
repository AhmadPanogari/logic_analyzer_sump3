/* ****************************************************************************
-- Source file: tb_la16.v
-- Description: Byte level top for la16_engine unit tests ( test_la16.py ).
--   Samples : 16 bit counter at the 200 MS/s base rate: s_lo = n, s_hi = n+1
--   UART    : tx_ready drops for TX_GAP clocks after every byte
--   Small parameters for speed: 4096 samples, CLK_HZ 1 MHz ( 1 ms = 1000 clk )
--   USE_DDR = 1: ring buffer in axi3_mem_model ( AXI3 HP port model with
--   random stalls ) instead of BRAM
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_la16;
  parameter USE_DDR = 0;
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

  wire [31:0]  awaddr, araddr;
  wire [3:0]   awlen, arlen;
  wire         awvalid, awready, wvalid, wready, wlast, bvalid, bready;
  wire         arvalid, arready, rvalid, rready, rlast;
  wire [63:0]  wdata, rdata;
  wire [7:0]   wstrb;
  wire [1:0]   bresp, rresp;
  wire [5:0]   bid, rid;

  axi3_mem_model #( .WORD_BITS( 12 ), .BASE( 32'h0200_0000 ) ) u_mem
  (
    .clk ( clk ), .reset ( reset ),
    .awaddr ( awaddr ), .awlen ( awlen ), .awvalid ( awvalid ), .awready ( awready ),
    .wdata ( wdata ), .wstrb ( wstrb ), .wlast ( wlast ), .wvalid ( wvalid ), .wready ( wready ),
    .bresp ( bresp ), .bid ( bid ), .bvalid ( bvalid ), .bready ( bready ),
    .araddr ( araddr ), .arlen ( arlen ), .arvalid ( arvalid ), .arready ( arready ),
    .rdata ( rdata ), .rresp ( rresp ), .rid ( rid ), .rlast ( rlast ), .rvalid ( rvalid ),
    .rready ( rready )
  );

  la16_engine #( .W( USE_DDR ? 13 : 12 ), .MAX_SAMPLES( 4096 ), .USE_DDR( USE_DDR ),
                 .CLK_HZ( 1_000_000 ) ) u_dut
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
    .busy     ( busy      ),
    .m_awaddr ( awaddr ), .m_awlen ( awlen ), .m_awsize (), .m_awburst (), .m_awlock (),
    .m_awcache (), .m_awprot (), .m_awqos (), .m_awid (), .m_awvalid ( awvalid ),
    .m_awready ( awready ), .m_wdata ( wdata ), .m_wstrb ( wstrb ), .m_wlast ( wlast ),
    .m_wid (), .m_wvalid ( wvalid ), .m_wready ( wready ), .m_bresp ( bresp ),
    .m_bid ( bid ), .m_bvalid ( bvalid ), .m_bready ( bready ), .m_araddr ( araddr ),
    .m_arlen ( arlen ), .m_arsize (), .m_arburst (), .m_arlock (), .m_arcache (),
    .m_arprot (), .m_arqos (), .m_arid (), .m_arvalid ( arvalid ), .m_arready ( arready ),
    .m_rdata ( rdata ), .m_rresp ( rresp ), .m_rid ( rid ), .m_rlast ( rlast ),
    .m_rvalid ( rvalid ), .m_rready ( rready )
  );
endmodule
`default_nettype wire
