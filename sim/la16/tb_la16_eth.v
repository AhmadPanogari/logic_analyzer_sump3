/* ****************************************************************************
-- Source file: tb_la16_eth.v
-- Description: la16_eth_core with the AXI3 DDR model. cocotb ( test_la16_eth.py )
--              plays the ARM: register writes / reads on the GP0 slave port,
--              result read straight from the model memory.
--   Probes: 16 bit counter at the 200 MS/s base rate.
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module tb_la16_eth;
  reg          clk = 0;
  reg  [15:0]  cnt = 0;
  always #5 clk = ~clk;
  always @ ( posedge clk ) cnt <= cnt + 2;

  // GP0 side ( driven by cocotb )
  reg  [31:0]  s_awaddr = 0, s_wdata = 0, s_araddr = 0;
  reg  [11:0]  s_awid = 0, s_arid = 0;
  reg  [3:0]   s_wstrb = 4'hF;
  reg          s_awvalid = 0, s_wvalid = 0, s_bready = 0, s_arvalid = 0, s_rready = 0;
  wire         s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rlast;
  wire [11:0]  s_bid, s_rid;
  wire [1:0]   s_bresp, s_rresp;
  wire [31:0]  s_rdata;

  wire [31:0]  awaddr, araddr;
  wire [3:0]   awlen, arlen;
  wire         awvalid, awready, wvalid, wready, wlast, bvalid, bready;
  wire         arvalid, arready, rvalid, rready, rlast;
  wire [63:0]  wdata, rdata;
  wire [7:0]   wstrb;
  wire [1:0]   bresp, rresp;
  wire [5:0]   bid, rid;
  wire [3:0]   led;

  axi3_mem_model #( .WORD_BITS( 14 ), .BASE( 32'h0200_0000 ) ) u_mem
  (
    .clk ( clk ), .reset ( u_dut.reset_loc ),
    .awaddr ( awaddr ), .awlen ( awlen ), .awvalid ( awvalid ), .awready ( awready ),
    .wdata ( wdata ), .wstrb ( wstrb ), .wlast ( wlast ), .wvalid ( wvalid ), .wready ( wready ),
    .bresp ( bresp ), .bid ( bid ), .bvalid ( bvalid ), .bready ( bready ),
    .araddr ( araddr ), .arlen ( arlen ), .arvalid ( arvalid ), .arready ( arready ),
    .rdata ( rdata ), .rresp ( rresp ), .rid ( rid ), .rlast ( rlast ), .rvalid ( rvalid ),
    .rready ( rready )
  );

  la16_eth_core #( .W( 17 ), .MAX_SAMPLES( 65536 ) ) u_dut
  (
    .clk_100m ( clk ), .probe_lo ( cnt ), .probe_hi ( cnt + 16'd1 ), .tp_sel ( 1'b0 ),
    .led ( led ),
    .s_awaddr ( s_awaddr ), .s_awid ( s_awid ), .s_awvalid ( s_awvalid ), .s_awready ( s_awready ),
    .s_wdata ( s_wdata ), .s_wstrb ( s_wstrb ), .s_wvalid ( s_wvalid ), .s_wready ( s_wready ),
    .s_bid ( s_bid ), .s_bresp ( s_bresp ), .s_bvalid ( s_bvalid ), .s_bready ( s_bready ),
    .s_araddr ( s_araddr ), .s_arid ( s_arid ), .s_arvalid ( s_arvalid ), .s_arready ( s_arready ),
    .s_rid ( s_rid ), .s_rdata ( s_rdata ), .s_rresp ( s_rresp ), .s_rlast ( s_rlast ),
    .s_rvalid ( s_rvalid ), .s_rready ( s_rready ),
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
