/* ****************************************************************************
-- Source file: la_core.v
-- Description: Board independent part of the XC7Z010 Logic Analyzer.
--
--   PC (sump3.py) <-TCP-> bd_server.py <-USB-UART-> MesaBus (ft232_xface)
--                                                      |
--                                                 32bit LocalBus
--                                                      |
--                                    sump3_core + sump3_rle_hub + RLE Pods
--
--   SUMP3 captures, sump3.py downloads + exports VCD, host/sump3_vcd2sr.py
--   converts VCD to a sigrok session (*.sr) and PulseView displays it.
--
--   Board tops ( la_top.v, la_top_s9.v ) only provide the 100 MHz clock
--   and map pins.
--
--   Ports:
--     clk_100m     : 100 MHz. Must match ck_freq_mhz in la_sump3.v
--     probe[15:0]  : external logic analyzer inputs (LVCMOS33)
--     bd_rx        : UART RX from external 3.3V USB-UART (FT232/CP2102)
--     bd_tx        : UART TX to   external 3.3V USB-UART
--     btn[3:0]     : btn[0] = reset demo counter, btn[1] = pause it
--     sw[1:0]      : sw[0]=1 replaces probe[15:0] with internal test pattern
--     led[3:0]     : active high
--
-- Language:    Verilog-2001
-- License:     SUMP3 and MesaBus IP are (C) Kevin Hubbard / BlackMesaLabs,
--              CERN OHL v1.2. See third_party/ for the original sources.
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_core
(
  input  wire         clk_100m,     // LocalBus + SUMP3 capture clock
  input  wire         clk_locked,   // Low holds the design in reset
  input  wire [3:0]   btn,
  input  wire [1:0]   sw,
  input  wire [15:0]  probe,
  input  wire         bd_rx,
  output wire         bd_tx,
  output reg  [3:0]   led
);// module la_core

  reg  [3:0]    reset_sr = 4'hF;
  wire          reset_loc;

  wire          lb_wr;
  wire          lb_rd;
  wire [31:0]   lb_addr;
  wire [31:0]   lb_wr_d;
  wire [31:0]   lb_rd_d;
  wire          lb_rd_rdy;
  wire          sump3_lb_cs_ctrl;
  wire          sump3_lb_cs_data;

  // 2-FF synchronizers. First probe stage is packed into the IOB so every
  // channel sees the same input delay.
  (* IOB = "TRUE", ASYNC_REG = "TRUE" *) reg  [15:0]   probe_meta;
  (* ASYNC_REG = "TRUE" *)               reg  [15:0]   probe_sync;
  (* ASYNC_REG = "TRUE" *)               reg  [1:0]    sw_meta;
  (* ASYNC_REG = "TRUE" *)               reg  [1:0]    sw_sync;
  (* ASYNC_REG = "TRUE" *)               reg  [3:0]    btn_meta;
  (* ASYNC_REG = "TRUE" *)               reg  [3:0]    btn_sync;
  (* ASYNC_REG = "TRUE" *)               reg           bd_rx_meta;
  (* ASYNC_REG = "TRUE" *)               reg           bd_rx_sync;

  wire [15:0]   test_pattern;
  wire [15:0]   pod0_events;
  wire [31:0]   pod1_events;
  reg  [31:0]   demo_cnt;
  reg  [26:0]   heartbeat_cnt;


//-----------------------------------------------------------------------------
// Reset : held until the clock source is stable
//-----------------------------------------------------------------------------
always @ ( posedge clk_100m or negedge clk_locked ) begin : proc_reset
  if ( clk_locked == 0 ) begin
    reset_sr <= 4'hF;
  end else begin
    reset_sr <= { reset_sr[2:0], 1'b0 };
  end
end // proc_reset
  assign reset_loc = reset_sr[3];


//-----------------------------------------------------------------------------
// Input synchronizers. Probes are asynchronous to clk_100m.
//-----------------------------------------------------------------------------
always @ ( posedge clk_100m ) begin : proc_sync
  probe_meta <= probe[15:0];
  probe_sync <= probe_meta[15:0];
  sw_meta    <= sw[1:0];
  sw_sync    <= sw_meta[1:0];
  btn_meta   <= btn[3:0];
  btn_sync   <= btn_meta[3:0];
  bd_rx_meta <= bd_rx;
  bd_rx_sync <= bd_rx_meta;
end // proc_sync


//-----------------------------------------------------------------------------
// Internal test pattern ( UART, SPI, I2C-like and clock dividers ) so the
// whole flow can be verified in PulseView without any external wiring.
//-----------------------------------------------------------------------------
la_test_pattern u_la_test_pattern
(
  .clk          ( clk_100m            ),
  .reset        ( reset_loc           ),
  .pattern      ( test_pattern[15:0]  )
);// u_la_test_pattern

  assign pod0_events[15:0] = ( sw_sync[0] == 1 ) ? test_pattern[15:0] :
                                                   probe_sync[15:0];


//-----------------------------------------------------------------------------
// Demo counter + internal debug signals for the 2nd RLE Pod
//-----------------------------------------------------------------------------
always @ ( posedge clk_100m ) begin : proc_demo
  heartbeat_cnt <= heartbeat_cnt + 1;
  if ( btn_sync[1] == 0 ) begin
    demo_cnt <= demo_cnt + 1;// btn[1] pauses the counter
  end
  if ( btn_sync[0] == 1 || reset_loc == 1 ) begin
    demo_cnt      <= 32'd0;
    heartbeat_cnt <= 27'd0;
  end
end // proc_demo

  assign pod1_events[23:0]  = demo_cnt[23:0];
  assign pod1_events[24]    = bd_rx_sync;  // MesaBus UART RX ( from PC )
  assign pod1_events[25]    = bd_tx;       // MesaBus UART TX ( to PC )
  assign pod1_events[26]    = lb_wr;
  assign pod1_events[27]    = lb_rd;
  assign pod1_events[31:28] = btn_sync[3:0];

always @ ( posedge clk_100m ) begin : proc_led
  led[0] <= heartbeat_cnt[26];  // Alive
  led[1] <= clk_locked;
  led[2] <= sw_sync[0];         // Test pattern selected
  led[3] <= ~bd_rx_sync;        // UART activity ( idle high )
end // proc_led


//-----------------------------------------------------------------------------
// MesaBus interface to LocalBus : 2-wire UART to 32bit PCIe like localbus
// Files from https://github.com/blackmesalabs/MesaBusProtocol
// The UART autobauds on the first "\n" sent by bd_server.py.
//-----------------------------------------------------------------------------
ft232_xface u_ft232_xface
(
  .reset       ( reset_loc       ),
  .clk_lb      ( clk_100m        ),
  .ftdi_wi     ( bd_rx_sync      ),
  .ftdi_ro     ( bd_tx           ),
  .lb_wr       ( lb_wr           ),
  .lb_rd       ( lb_rd           ),
  .lb_addr     ( lb_addr[31:0]   ),
  .lb_wr_d     ( lb_wr_d[31:0]   ),
  .lb_rd_d     ( lb_rd_d[31:0]   ),
  .lb_rd_rdy   ( lb_rd_rdy       )
);// u_ft232_xface


//-----------------------------------------------------------------------------
// SUMP3 Logic Analyzer : core + hub + 2 RLE pods
// Control reg at 0x98, Data reg at 0x9C ( sump_uut_addr = 00000098 )
//-----------------------------------------------------------------------------
la_sump3 u_la_sump3
(
  .reset        ( reset_loc            ),
  .clk_lb       ( clk_100m             ),
  .clk_cap      ( clk_100m             ),
  .lb_cs_ctrl   ( sump3_lb_cs_ctrl     ),// Must be -4 from lb_cs_data
  .lb_cs_data   ( sump3_lb_cs_data     ),// Must be +4 from lb_cs_ctrl
  .lb_wr        ( lb_wr                ),
  .lb_rd        ( lb_rd                ),
  .lb_wr_d      ( lb_wr_d[31:0]        ),
  .lb_rd_d      ( lb_rd_d[31:0]        ),
  .lb_rd_rdy    ( lb_rd_rdy            ),
  .pod0_events  ( pod0_events[15:0]    ),
  .pod1_events  ( pod1_events[31:0]    )
);// u_la_sump3
  assign sump3_lb_cs_ctrl = ( lb_addr[7:0] == 8'h98 ) ? 1 : 0;
  assign sump3_lb_cs_data = ( lb_addr[7:0] == 8'h9c ) ? 1 : 0;


endmodule // la_core.v
`default_nettype wire // enable Verilog default for any 3rd party IP needing it
