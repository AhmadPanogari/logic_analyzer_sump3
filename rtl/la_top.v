/* ****************************************************************************
-- Source file: la_top.v
-- Description: Top level Logic Analyzer for Xilinx Zynq-7000 XC7Z010 (PL only).
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
--   The design uses the PL only. No PS7 / FSBL is required, the bitstream
--   can be loaded over JTAG with the Vivado Hardware Manager.
--
--   Inputs:
--     sys_clk      : 125 MHz PL oscillator (Zybo Z7-10 / Arty Z7-10)
--     probe[15:0]  : external logic analyzer inputs on 2x Pmod (LVCMOS33)
--     bd_rx        : UART RX from external 3.3V USB-UART (FT232/CP2102)
--     bd_tx        : UART TX to   external 3.3V USB-UART
--     btn[3:0]     : push buttons (btn[0] = reset demo counter)
--     sw[1:0]      : sw[0]=1 replaces probe[15:0] with internal test pattern
--
-- Language:    Verilog-2001
-- License:     SUMP3 and MesaBus IP are (C) Kevin Hubbard / BlackMesaLabs,
--              CERN OHL v1.2. See third_party/ for the original sources.
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_top
(
  input  wire         sys_clk,
  input  wire [3:0]   btn,
  input  wire [1:0]   sw,
  input  wire [15:0]  probe,
  input  wire         bd_rx,
  output wire         bd_tx,
  output reg  [3:0]   led
);// module la_top

  wire          clk_100m;
  wire          clk_locked;
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
// Clocking : 125 MHz PL oscillator -> 100 MHz for LocalBus + SUMP3 capture
//-----------------------------------------------------------------------------
la_clk_gen u_la_clk_gen
(
  .clk_in       ( sys_clk         ),
  .clk_out      ( clk_100m        ),
  .locked       ( clk_locked      )
);// u_la_clk_gen


//-----------------------------------------------------------------------------
// Reset : held until the MMCM has locked
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


endmodule // la_top.v
`default_nettype wire // enable Verilog default for any 3rd party IP needing it
