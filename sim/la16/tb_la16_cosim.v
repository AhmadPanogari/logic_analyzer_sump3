/* ****************************************************************************
-- Source file: tb_la16_cosim.v
-- Description: Byte level co-simulation top for la16_engine. cocotb
--              ( test_la16_cosim.py ) bridges rx/tx bytes to a TCP socket so
--              the libsigrok la16 driver ( sigrok-cli with
--              conn=tcp-raw/127.0.0.1/<port> ) talks to the RTL.
--   Probes  : 16 bit counter at the 200 MS/s base rate ( s_lo = n, s_hi = n+1 )
--   USE_DDR : 1 = ring buffer in axi3_mem_model, 262144 samples
--   CLK_HZ  : 100 kHz for the ms timers only, so STATUS frames ( every 50 ms )
--             come often in wall clock time; the sample rate is unaffected
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_la16_cosim;
  parameter USE_DDR = 0;
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

  wire [31:0]  awaddr, araddr;
  wire [3:0]   awlen, arlen;
  wire         awvalid, awready, wvalid, wready, wlast, bvalid, bready;
  wire         arvalid, arready, rvalid, rready, rlast;
  wire [63:0]  wdata, rdata;
  wire [7:0]   wstrb;
  wire [1:0]   bresp, rresp;
  wire [5:0]   bid, rid;

  axi3_mem_model #( .WORD_BITS( 16 ), .BASE( 32'h0200_0000 ) ) u_mem
  (
    .clk ( clk ), .reset ( reset ),
    .awaddr ( awaddr ), .awlen ( awlen ), .awvalid ( awvalid ), .awready ( awready ),
    .wdata ( wdata ), .wstrb ( wstrb ), .wlast ( wlast ), .wvalid ( wvalid ), .wready ( wready ),
    .bresp ( bresp ), .bid ( bid ), .bvalid ( bvalid ), .bready ( bready ),
    .araddr ( araddr ), .arlen ( arlen ), .arvalid ( arvalid ), .arready ( arready ),
    .rdata ( rdata ), .rresp ( rresp ), .rid ( rid ), .rlast ( rlast ), .rvalid ( rvalid ),
    .rready ( rready )
  );

  la16_engine #( .W( USE_DDR ? 19 : 16 ), .MAX_SAMPLES( USE_DDR ? 262144 : 65536 ),
                 .USE_DDR( USE_DDR ), .CLK_HZ( 100_000 ) ) u_dut
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
    .busy     ( busy        ),
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
