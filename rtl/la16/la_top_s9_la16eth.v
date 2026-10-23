/* ****************************************************************************
-- Source file: la_top_s9_la16eth.v
-- Description: Antminer S9 control board top level, la16 protocol variant
--              ( docs/PROTOCOL_LA16.md, own libsigrok driver "la16" ).
--              Probes are sampled on both clock edges ( IDDR ) = 200 MS/s.
--              Ethernet build: the ARM program ( sw/la16_eth ) serves the
--              la16 protocol over TCP ( GEM0, PHY on MIO ), controls the
--              capture through M_AXI_GP0 registers ( 0x43C0_0000 ) and reads
--              the DDR ring ( 251M samples at 0x0200_0000, written through
--              S_AXI_HP0 ). No UART protocol; bd_rx / bd_tx unused.
--              LEDs: D5 heartbeat, D6 armed, D7 test pattern,
--                    D8 set by software ( Ethernet client connected ).
--              Same pins and clock as la_top_s9.v ( see that file and
--              constraints/antminer_s9.xdc ):
--                J1 pin 11/12 = UART TX/RX, J5..J8 = D0..D15,
--                J9 pin 5 = test pattern jumper, LEDs D5..D8 active low.
--              UART baud ( jumper to GND, pull-ups inside ):
--                none = 921600, J9 pin 11 = 460800, J9 pin 12 = 230400,
--                both = 115200. Set the same baud rate in PulseView.
--              LEDs: D5 heartbeat, D6 armed ( prefill / waiting for
--                    trigger ), D7 test pattern, D8 UART RX activity.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_top_s9_la16eth
(
  // PS7 dedicated pins ( DDR and MIO ), required by processing_system7
  inout  wire [14:0]  DDR_addr,
  inout  wire [2:0]   DDR_ba,
  inout  wire         DDR_cas_n,
  inout  wire         DDR_ck_n,
  inout  wire         DDR_ck_p,
  inout  wire         DDR_cke,
  inout  wire         DDR_cs_n,
  inout  wire [3:0]   DDR_dm,
  inout  wire [31:0]  DDR_dq,
  inout  wire [3:0]   DDR_dqs_n,
  inout  wire [3:0]   DDR_dqs_p,
  inout  wire         DDR_odt,
  inout  wire         DDR_ras_n,
  inout  wire         DDR_reset_n,
  inout  wire         DDR_we_n,
  inout  wire         FIXED_IO_ddr_vrn,
  inout  wire         FIXED_IO_ddr_vrp,
  inout  wire [53:0]  FIXED_IO_mio,
  inout  wire         FIXED_IO_ps_clk,
  inout  wire         FIXED_IO_ps_porb,
  inout  wire         FIXED_IO_ps_srstb,

  // PL pins
  input  wire [15:0]  probe,
  input  wire         tp_sel_n,
  input  wire [1:0]   baud_sel_n,     // J9 pin 11 / pin 12, jumper to GND
  input  wire         bd_rx,
  output wire         bd_tx,
  output wire [3:0]   led_n
);// module la_top_s9_la16eth

  wire          fclk0;
  wire          fclk0_reset_n;
  wire [3:0]    led;
  wire [15:0]   probe_lo;
  wire [15:0]   probe_hi;
  wire [31:0]   hp_awaddr, hp_araddr;
  wire [3:0]    hp_awlen, hp_arlen, hp_awcache, hp_arcache, hp_awqos, hp_arqos;
  wire [2:0]    hp_awsize, hp_arsize, hp_awprot, hp_arprot;
  wire [1:0]    hp_awburst, hp_arburst, hp_awlock, hp_arlock, hp_bresp, hp_rresp;
  wire [5:0]    hp_awid, hp_arid, hp_wid, hp_bid, hp_rid;
  wire          hp_awvalid, hp_awready, hp_wvalid, hp_wready, hp_wlast;
  wire          hp_bvalid, hp_bready, hp_arvalid, hp_arready;
  wire          hp_rvalid, hp_rready, hp_rlast;
  wire [63:0]   hp_wdata, hp_rdata;
  wire [7:0]    hp_wstrb;
  wire [31:0]   gp_awaddr, gp_araddr, gp_wdata, gp_rdata;
  wire [11:0]   gp_awid, gp_arid, gp_wid, gp_bid, gp_rid;
  wire [3:0]    gp_awlen, gp_arlen, gp_awcache, gp_arcache, gp_awqos, gp_arqos, gp_wstrb;
  wire [2:0]    gp_awsize, gp_arsize, gp_awprot, gp_arprot;
  wire [1:0]    gp_awburst, gp_arburst, gp_awlock, gp_arlock, gp_bresp, gp_rresp;
  wire          gp_awvalid, gp_awready, gp_wvalid, gp_wready, gp_wlast;
  wire          gp_bvalid, gp_bready, gp_arvalid, gp_arready;
  wire          gp_rvalid, gp_rready, gp_rlast;


//-----------------------------------------------------------------------------
// Zynq PS : only used as the PL clock source
//-----------------------------------------------------------------------------
la_ps_wrapper u_la_ps
(
  .DDR_addr          ( DDR_addr          ),
  .DDR_ba            ( DDR_ba            ),
  .DDR_cas_n         ( DDR_cas_n         ),
  .DDR_ck_n          ( DDR_ck_n          ),
  .DDR_ck_p          ( DDR_ck_p          ),
  .DDR_cke           ( DDR_cke           ),
  .DDR_cs_n          ( DDR_cs_n          ),
  .DDR_dm            ( DDR_dm            ),
  .DDR_dq            ( DDR_dq            ),
  .DDR_dqs_n         ( DDR_dqs_n         ),
  .DDR_dqs_p         ( DDR_dqs_p         ),
  .DDR_odt           ( DDR_odt           ),
  .DDR_ras_n         ( DDR_ras_n         ),
  .DDR_reset_n       ( DDR_reset_n       ),
  .DDR_we_n          ( DDR_we_n          ),
  .FIXED_IO_ddr_vrn  ( FIXED_IO_ddr_vrn  ),
  .FIXED_IO_ddr_vrp  ( FIXED_IO_ddr_vrp  ),
  .FIXED_IO_mio      ( FIXED_IO_mio      ),
  .FIXED_IO_ps_clk   ( FIXED_IO_ps_clk   ),
  .FIXED_IO_ps_porb  ( FIXED_IO_ps_porb  ),
  .FIXED_IO_ps_srstb ( FIXED_IO_ps_srstb ),
  .FCLK_CLK0         ( fclk0             ),
  .FCLK_RESET0_N     ( fclk0_reset_n     ),
  .S_AXI_HP0_araddr  ( hp_araddr         ),
  .S_AXI_HP0_arburst ( hp_arburst        ),
  .S_AXI_HP0_arcache ( hp_arcache        ),
  .S_AXI_HP0_arid    ( hp_arid           ),
  .S_AXI_HP0_arlen   ( hp_arlen          ),
  .S_AXI_HP0_arlock  ( hp_arlock         ),
  .S_AXI_HP0_arprot  ( hp_arprot         ),
  .S_AXI_HP0_arqos   ( hp_arqos          ),
  .S_AXI_HP0_arready ( hp_arready        ),
  .S_AXI_HP0_arsize  ( hp_arsize         ),
  .S_AXI_HP0_arvalid ( hp_arvalid        ),
  .S_AXI_HP0_awaddr  ( hp_awaddr         ),
  .S_AXI_HP0_awburst ( hp_awburst        ),
  .S_AXI_HP0_awcache ( hp_awcache        ),
  .S_AXI_HP0_awid    ( hp_awid           ),
  .S_AXI_HP0_awlen   ( hp_awlen          ),
  .S_AXI_HP0_awlock  ( hp_awlock         ),
  .S_AXI_HP0_awprot  ( hp_awprot         ),
  .S_AXI_HP0_awqos   ( hp_awqos          ),
  .S_AXI_HP0_awready ( hp_awready        ),
  .S_AXI_HP0_awsize  ( hp_awsize         ),
  .S_AXI_HP0_awvalid ( hp_awvalid        ),
  .S_AXI_HP0_bid     ( hp_bid            ),
  .S_AXI_HP0_bready  ( hp_bready         ),
  .S_AXI_HP0_bresp   ( hp_bresp          ),
  .S_AXI_HP0_bvalid  ( hp_bvalid         ),
  .S_AXI_HP0_rdata   ( hp_rdata          ),
  .S_AXI_HP0_rid     ( hp_rid            ),
  .S_AXI_HP0_rlast   ( hp_rlast          ),
  .S_AXI_HP0_rready  ( hp_rready         ),
  .S_AXI_HP0_rresp   ( hp_rresp          ),
  .S_AXI_HP0_rvalid  ( hp_rvalid         ),
  .S_AXI_HP0_wdata   ( hp_wdata          ),
  .S_AXI_HP0_wid     ( hp_wid            ),
  .S_AXI_HP0_wlast   ( hp_wlast          ),
  .S_AXI_HP0_wready  ( hp_wready         ),
  .S_AXI_HP0_wstrb   ( hp_wstrb          ),
  .S_AXI_HP0_wvalid  ( hp_wvalid         ),
  .M_AXI_GP0_araddr  ( gp_araddr         ),
  .M_AXI_GP0_arburst ( gp_arburst        ),
  .M_AXI_GP0_arcache ( gp_arcache        ),
  .M_AXI_GP0_arid    ( gp_arid           ),
  .M_AXI_GP0_arlen   ( gp_arlen          ),
  .M_AXI_GP0_arlock  ( gp_arlock         ),
  .M_AXI_GP0_arprot  ( gp_arprot         ),
  .M_AXI_GP0_arqos   ( gp_arqos          ),
  .M_AXI_GP0_arready ( gp_arready        ),
  .M_AXI_GP0_arsize  ( gp_arsize         ),
  .M_AXI_GP0_arvalid ( gp_arvalid        ),
  .M_AXI_GP0_awaddr  ( gp_awaddr         ),
  .M_AXI_GP0_awburst ( gp_awburst        ),
  .M_AXI_GP0_awcache ( gp_awcache        ),
  .M_AXI_GP0_awid    ( gp_awid           ),
  .M_AXI_GP0_awlen   ( gp_awlen          ),
  .M_AXI_GP0_awlock  ( gp_awlock         ),
  .M_AXI_GP0_awprot  ( gp_awprot         ),
  .M_AXI_GP0_awqos   ( gp_awqos          ),
  .M_AXI_GP0_awready ( gp_awready        ),
  .M_AXI_GP0_awsize  ( gp_awsize         ),
  .M_AXI_GP0_awvalid ( gp_awvalid        ),
  .M_AXI_GP0_bid     ( gp_bid            ),
  .M_AXI_GP0_bready  ( gp_bready         ),
  .M_AXI_GP0_bresp   ( gp_bresp          ),
  .M_AXI_GP0_bvalid  ( gp_bvalid         ),
  .M_AXI_GP0_rdata   ( gp_rdata          ),
  .M_AXI_GP0_rid     ( gp_rid            ),
  .M_AXI_GP0_rlast   ( gp_rlast          ),
  .M_AXI_GP0_rready  ( gp_rready         ),
  .M_AXI_GP0_rresp   ( gp_rresp          ),
  .M_AXI_GP0_rvalid  ( gp_rvalid         ),
  .M_AXI_GP0_wdata   ( gp_wdata          ),
  .M_AXI_GP0_wid     ( gp_wid            ),
  .M_AXI_GP0_wlast   ( gp_wlast          ),
  .M_AXI_GP0_wready  ( gp_wready         ),
  .M_AXI_GP0_wstrb   ( gp_wstrb          ),
  .M_AXI_GP0_wvalid  ( gp_wvalid         )
);// u_la_ps


//-----------------------------------------------------------------------------
// Probes: IDDR, Q1 = rising edge sample ( earlier ), Q2 = falling edge
// sample of the same clock period, both presented on the rising edge.
//-----------------------------------------------------------------------------
genvar i;
generate
  for ( i = 0; i < 16; i = i + 1 ) begin : g_iddr
    IDDR #( .DDR_CLK_EDGE ( "SAME_EDGE_PIPELINED" ), .SRTYPE ( "SYNC" ) ) u_iddr
    (
      .C  ( fclk0       ),
      .CE ( 1'b1        ),
      .D  ( probe[i]    ),
      .R  ( 1'b0        ),
      .S  ( 1'b0        ),
      .Q1 ( probe_lo[i] ),
      .Q2 ( probe_hi[i] )
    );
  end
endgenerate


//-----------------------------------------------------------------------------
// la16 logic analyzer, controlled by the ARM over GP0. Test pattern via the
// J9 jumper or the CFG register.
//-----------------------------------------------------------------------------
la16_eth_core u_la16_eth_core
(
  .clk_100m  ( fclk0       ),
  .probe_lo  ( probe_lo    ),
  .probe_hi  ( probe_hi    ),
  .tp_sel    ( ~tp_sel_n   ),
  .led       ( led[3:0]    ),
  .s_awaddr  ( gp_awaddr   ), .s_awid    ( gp_awid    ), .s_awvalid ( gp_awvalid ),
  .s_awready ( gp_awready  ), .s_wdata   ( gp_wdata   ), .s_wstrb   ( gp_wstrb   ),
  .s_wvalid  ( gp_wvalid   ), .s_wready  ( gp_wready  ), .s_bid     ( gp_bid     ),
  .s_bresp   ( gp_bresp    ), .s_bvalid  ( gp_bvalid  ), .s_bready  ( gp_bready  ),
  .s_araddr  ( gp_araddr   ), .s_arid    ( gp_arid    ), .s_arvalid ( gp_arvalid ),
  .s_arready ( gp_arready  ), .s_rid     ( gp_rid     ), .s_rdata   ( gp_rdata   ),
  .s_rresp   ( gp_rresp    ), .s_rlast   ( gp_rlast   ), .s_rvalid  ( gp_rvalid  ),
  .s_rready  ( gp_rready   ),
  .m_awaddr  ( hp_awaddr  ), .m_awlen   ( hp_awlen   ), .m_awsize  ( hp_awsize  ),
  .m_awburst ( hp_awburst ), .m_awlock  ( hp_awlock  ), .m_awcache ( hp_awcache ),
  .m_awprot  ( hp_awprot  ), .m_awqos   ( hp_awqos   ), .m_awid    ( hp_awid    ),
  .m_awvalid ( hp_awvalid ), .m_awready ( hp_awready ), .m_wdata   ( hp_wdata   ),
  .m_wstrb   ( hp_wstrb   ), .m_wlast   ( hp_wlast   ), .m_wid     ( hp_wid     ),
  .m_wvalid  ( hp_wvalid  ), .m_wready  ( hp_wready  ), .m_bresp   ( hp_bresp   ),
  .m_bid     ( hp_bid     ), .m_bvalid  ( hp_bvalid  ), .m_bready  ( hp_bready  ),
  .m_araddr  ( hp_araddr  ), .m_arlen   ( hp_arlen   ), .m_arsize  ( hp_arsize  ),
  .m_arburst ( hp_arburst ), .m_arlock  ( hp_arlock  ), .m_arcache ( hp_arcache ),
  .m_arprot  ( hp_arprot  ), .m_arqos   ( hp_arqos   ), .m_arid    ( hp_arid    ),
  .m_arvalid ( hp_arvalid ), .m_arready ( hp_arready ), .m_rdata   ( hp_rdata   ),
  .m_rresp   ( hp_rresp   ), .m_rid     ( hp_rid     ), .m_rlast   ( hp_rlast   ),
  .m_rvalid  ( hp_rvalid  ), .m_rready  ( hp_rready  )
);// u_la16_eth_core

  assign led_n = ~led;
  assign bd_tx = 1'b1;                       // UART unused in this build


endmodule // la_top_s9_la16eth.v
`default_nettype wire
