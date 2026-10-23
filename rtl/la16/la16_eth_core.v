/* ****************************************************************************
-- Source file: la16_eth_core.v
-- Description: la16 logic analyzer for the Ethernet build: no UART engine.
--              The ARM program ( sw/la16_eth ) serves the la16 protocol over
--              TCP, drives the capture through la16_regs ( M_AXI_GP0 ) and
--              reads the result from the DDR ring. The capture writes the
--              ring through S_AXI_HP0 ( la16_store_ddr ).
--
--   clk_100m     : 100 MHz ( FCLK_CLK0, also the AXI clock of GP0 and HP0 )
--   probe_lo/hi  : IDDR outputs ( rising / falling edge ), 200 MS/s base
--   tp_sel       : 1 = internal test pattern ( also CFG bit 0 )
--   led[3:0]     : active high. 0 heartbeat, 1 armed, 2 test pattern,
--                  3 set by software ( CFG bit 8 )
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_eth_core
#(
  parameter        W           = 28,
  parameter        MAX_SAMPLES = 251_658_240,
  parameter [31:0] DDR_BASE    = 32'h0200_0000
)
(
  input  wire         clk_100m,
  input  wire [15:0]  probe_lo,
  input  wire [15:0]  probe_hi,
  input  wire         tp_sel,
  output reg  [3:0]   led,

  // AXI3 slave: registers ( M_AXI_GP0 )
  input  wire [31:0]  s_awaddr,
  input  wire [11:0]  s_awid,
  input  wire         s_awvalid,
  output wire         s_awready,
  input  wire [31:0]  s_wdata,
  input  wire [3:0]   s_wstrb,
  input  wire         s_wvalid,
  output wire         s_wready,
  output wire [11:0]  s_bid,
  output wire [1:0]   s_bresp,
  output wire         s_bvalid,
  input  wire         s_bready,
  input  wire [31:0]  s_araddr,
  input  wire [11:0]  s_arid,
  input  wire         s_arvalid,
  output wire         s_arready,
  output wire [11:0]  s_rid,
  output wire [31:0]  s_rdata,
  output wire [1:0]   s_rresp,
  output wire         s_rlast,
  output wire         s_rvalid,
  input  wire         s_rready,

  // AXI3 master: DDR ring ( S_AXI_HP0 )
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
  wire          reset_loc = reset_sr[3];

  (* ASYNC_REG = "TRUE" *) reg  [31:0]  probe_sync;
  (* ASYNC_REG = "TRUE" *) reg  [1:0]   tp_sel_sr;
  reg  [31:0]   samples;
  wire [15:0]   test_pattern;
  reg  [26:0]   heartbeat_cnt;

  wire          arm, abort;
  wire [31:0]   divider, cfg;
  wire [W:0]    total, pre, captured, ring;
  wire [W-1:0]  start;
  wire [15:0]   tl_mask, tl_value, tr_mask, tf_mask;
  wire [2:0]    state;
  wire          done, ready, overflow;
  wire          use_pattern = tp_sel_sr[1] | cfg[0];

  always @ ( posedge clk_100m ) begin : proc_sync
    reset_sr   <= { reset_sr[2:0], 1'b0 };
    probe_sync <= { probe_hi, probe_lo };
    tp_sel_sr  <= { tp_sel_sr[0], tp_sel };
    samples    <= use_pattern ? { test_pattern, test_pattern } : probe_sync;
  end // proc_sync

  la_test_pattern u_la_test_pattern
  (
    .clk     ( clk_100m      ),
    .reset   ( reset_loc     ),
    .pattern ( test_pattern  )
  );

  la16_regs #( .W ( W ), .MAX_SAMPLES ( MAX_SAMPLES ), .DDR_BASE ( DDR_BASE ) ) u_regs
  (
    .clk       ( clk_100m  ),
    .reset     ( reset_loc ),
    .s_awaddr  ( s_awaddr  ), .s_awid  ( s_awid  ), .s_awvalid ( s_awvalid ),
    .s_awready ( s_awready ), .s_wdata ( s_wdata ), .s_wstrb   ( s_wstrb   ),
    .s_wvalid  ( s_wvalid  ), .s_wready ( s_wready ), .s_bid   ( s_bid     ),
    .s_bresp   ( s_bresp   ), .s_bvalid ( s_bvalid ), .s_bready ( s_bready ),
    .s_araddr  ( s_araddr  ), .s_arid  ( s_arid  ), .s_arvalid ( s_arvalid ),
    .s_arready ( s_arready ), .s_rid   ( s_rid   ), .s_rdata   ( s_rdata   ),
    .s_rresp   ( s_rresp   ), .s_rlast ( s_rlast ), .s_rvalid  ( s_rvalid  ),
    .s_rready  ( s_rready  ),
    .arm       ( arm       ), .abort   ( abort   ), .divider   ( divider   ),
    .total     ( total     ), .pre     ( pre     ), .tl_mask   ( tl_mask   ),
    .tl_value  ( tl_value  ), .tr_mask ( tr_mask ), .tf_mask   ( tf_mask   ),
    .cfg       ( cfg       ), .state   ( state   ), .done      ( done      ),
    .ready     ( ready     ), .overflow ( overflow ), .captured ( captured ),
    .start     ( start     ), .ring    ( ring    )
  );

  la16_capture #( .W ( W ), .USE_DDR ( 1 ), .DDR_BASE ( DDR_BASE ) ) u_capture
  (
    .clk       ( clk_100m  ),
    .reset     ( reset_loc ),
    .s_lo      ( samples[15:0]  ),
    .s_hi      ( samples[31:16] ),
    .divider   ( divider   ),
    .total     ( total     ),
    .pre       ( pre       ),
    .tl_mask   ( tl_mask   ),
    .tl_value  ( tl_value  ),
    .tr_mask   ( tr_mask   ),
    .tf_mask   ( tf_mask   ),
    .arm       ( arm       ),
    .abort     ( abort     ),
    .state     ( state     ),
    .captured  ( captured  ),
    .done      ( done      ),
    .ready     ( ready     ),
    .overflow  ( overflow  ),
    .start_idx ( start     ),
    .ring_size ( ring      ),
    .rd_en     ( 1'b0      ),
    .rd_idx    ( {W{1'b0}} ),
    .rd_data   (           ),
    .rd_ready  (           ),
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

  always @ ( posedge clk_100m ) begin : proc_led
    heartbeat_cnt <= heartbeat_cnt + 1'b1;
    led[0] <= heartbeat_cnt[26];
    led[1] <= ( state == 3'd1 || state == 3'd2 );
    led[2] <= use_pattern;
    led[3] <= cfg[8];
    if ( reset_loc ) heartbeat_cnt <= 27'd0;
  end // proc_led

endmodule // la16_eth_core.v
`default_nettype wire
