/* ****************************************************************************
-- Source file: la_sump3.v
-- Description: SUMP3 instance for the XC7Z010 Logic Analyzer.
--              Based on sump3_top.v example by khubbard ( BlackMesaLabs ).
--
--   Hub  "ck100_hub"  : one clock domain, 100 MHz
--   Pod  "probe_pod"  : 16 external probes D0..D15, 4096 RLE samples x 48 bits
--                       ( 2 code + 16 data + 30 timestamp, 2^30*10ns=10.7 s )
--   Pod  "debug_pod"  : 32 internal signals, 2048 RLE samples x 64 bits
--
--   Signal names in the View ROM are what sump3.py displays, what it writes
--   to the VCD file and therefore what PulseView shows as channel names.
--
--   To make captures deeper, raise rle_ram_depth_len / rle_ram_depth_bits
--   ( must be 2^N ). XC7Z010 has 60 BRAM36. 8192 x 48 uses ~11 BRAM36.
--
-- Language:    Verilog-2001
-- License:     CERN OHL v1.2 ( derived from blackmesalabs/sump3 )
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la_sump3
(
  input  wire          reset,
  input  wire          clk_lb,
  input  wire          clk_cap,
  input  wire          lb_cs_ctrl,
  input  wire          lb_cs_data,
  input  wire          lb_wr,
  input  wire          lb_rd,
  input  wire [31:0]   lb_wr_d,
  output wire [31:0]   lb_rd_d,
  output wire          lb_rd_rdy,
  input  wire [15:0]   pod0_events,
  input  wire [31:0]   pod1_events
);// module la_sump3

  wire [0:0]   core_miso;
  wire [0:0]   core_mosi;
  wire [0:0]   trigger_mosi;
  wire [0:0]   trigger_miso;

  wire [1:0]   hub0_pod_mosi;
  wire [1:0]   hub0_pod_miso;

  // Pods do not use a View ROM ( names live in the core ROM ). The pod
  // still copies view_rom_txt into its ROM array every clock, which is free
  // in hardware ( optimized away ) but makes RTL simulation crawl, so keep it
  // tiny for simulation.
`ifdef SIMULATION
  localparam POD_VIEW_ROM_SIZE = 32;
`else
  localparam POD_VIEW_ROM_SIZE = 1024;
`endif


// ----------------------------------------------------------------------------
// Pod 0 : External probes
// ----------------------------------------------------------------------------
sump3_rle_pod
#
(
  .pod_name           ( "probe_pod   "    ),// 12 chars exactly
  .rle_ram_depth_len  (  4096             ),
  .rle_ram_depth_bits (  12               ),
  .rle_ram_width      (  48               ),// Must equal timestamp+data+code
  .rle_timestamp_bits (  30               ),// 2^^30 * 10ns = 10.7 Seconds
  .rle_data_bits      (  16               ),
  .rle_code_bits      (  2                ),// Must be 2
  .view_rom_size      (  POD_VIEW_ROM_SIZE )
)
u0_sump3_rle_pod
(
  .clk_cap            ( clk_cap           ),
  .events             ( pod0_events[15:0] ),
  .pod_mosi           ( hub0_pod_mosi[0]  ),
  .pod_miso           ( hub0_pod_miso[0]  ),
  .pod_user_ctrl      (                   ),
  .pod_user_trig      (                   ),
  .pod_user_mask      (                   ),
  .pod_user_pretrig   (                   ),
  .pod_is_armed       (                   )
);// sump3_rle_pod


// ----------------------------------------------------------------------------
// Pod 1 : Internal debug signals
// ----------------------------------------------------------------------------
sump3_rle_pod
#
(
  .pod_name           ( "debug_pod   "    ),// 12 chars exactly
  .rle_ram_depth_len  (  2048             ),
  .rle_ram_depth_bits (  11               ),
  .rle_ram_width      (  64               ),// Must equal timestamp+data+code
  .rle_timestamp_bits (  30               ),// 2^^30 * 10ns = 10.7 Seconds
  .rle_data_bits      (  32               ),
  .rle_code_bits      (  2                ),// Must be 2
  .view_rom_size      (  POD_VIEW_ROM_SIZE )
)
u1_sump3_rle_pod
(
  .clk_cap            ( clk_cap           ),
  .events             ( pod1_events[31:0] ),
  .pod_mosi           ( hub0_pod_mosi[1]  ),
  .pod_miso           ( hub0_pod_miso[1]  ),
  .pod_user_ctrl      (                   ),
  .pod_user_trig      (                   ),
  .pod_user_mask      (                   ),
  .pod_user_pretrig   (                   ),
  .pod_is_armed       (                   )
);// sump3_rle_pod


// -----------------------------------------------------------------------------
// SUMP3 RLE Hub - One per clock domain. Each hub may have 1-256 pods
// -----------------------------------------------------------------------------
sump3_rle_hub
#
(
  .hub_name          ( "ck100_hub   "          ),// 12 chars exactly
  .ck_freq_mhz       ( 12'd100                 ),
  .ck_freq_fracts    ( 20'h00000               ),
  .rle_pod_num       ( 2                       ) // How many Pods downstream
)
u0_sump3_rle_hub
(
  .clk_lb            ( clk_lb                  ),
  .clk_cap           ( clk_cap                 ),
  .core_mosi         ( core_mosi[0]            ),
  .core_miso         ( core_miso[0]            ),
  .trigger_mosi      ( trigger_mosi[0]         ),
  .trigger_miso      ( trigger_miso[0]         ),
  .sump_is_armed     (                         ),
  .user_bus_wr       (                         ),
  .user_bus_rd       (                         ),
  .user_bus_addr     (                         ),
  .user_bus_wr_d     (                         ),
  .user_bus_rd_d     ( 32'd0                   ),
  .pod_mosi          ( hub0_pod_mosi[1:0]      ),
  .pod_miso          ( hub0_pod_miso[1:0]      )
);// sump3_rle_hub


// ----------------------------------------------------------------------------
// Sump3 Core. Top level.
// View ROM coding ( see third_party/sump3/verilog/sump3_top.v ):
//  F0 ROM Start, F1 View Name, F4 Signal Source "hub.pod", F5 Group Name,
//  F6 Bit ( 16b bit position, name ), F7 Vector ( 16b msb, 16b lsb, name ),
//  E5 Group End, E1 View End, E0 ROM End
// Single bit (F6) signals become one PulseView channel each. Vectors (F7)
// are split into one channel per bit by host/sump3_vcd2sr.py.
// ----------------------------------------------------------------------------
sump3_core
#
(
  .ck_freq_mhz        (  12'd100   ),
  .ck_freq_fracts     (  20'h00000 ),
  .rle_hub_num        (  1         ),// Number of RLE Hubs connected to core
  .view_rom_en        (  1         ),
  .view_rom_size      (  16384     ),// View ROM size in bits
  .view_rom_txt       (
    {
     64'd0,                                         // Reqd 2-DWORD postamble
     8'hF0,                                         // ROM Start
       8'hF1, "probes",                             // Name for this view
         8'hF4, "ck100_hub.probe_pod",              // Signal source
         8'hF5, "probes",                           // Top level group
           8'hF6, 16'd0,          "D0",
           8'hF6, 16'd1,          "D1",
           8'hF6, 16'd2,          "D2",
           8'hF6, 16'd3,          "D3",
           8'hF6, 16'd4,          "D4",
           8'hF6, 16'd5,          "D5",
           8'hF6, 16'd6,          "D6",
           8'hF6, 16'd7,          "D7",
           8'hF6, 16'd8,          "D8",
           8'hF6, 16'd9,          "D9",
           8'hF6, 16'd10,         "D10",
           8'hF6, 16'd11,         "D11",
           8'hF6, 16'd12,         "D12",
           8'hF6, 16'd13,         "D13",
           8'hF6, 16'd14,         "D14",
           8'hF6, 16'd15,         "D15",
         8'hE5,                                     // End Group
       8'hE1,                                       // End View
       8'hF1, "debug",                              // Name for this view
         8'hF4, "ck100_hub.debug_pod",              // Signal source
         8'hF5, "debug",                            // Top level group
           8'hF7, 16'd23, 16'd0,  "demo_cnt[23:0]", // Vector
           8'hF6, 16'd24,         "mesa_rx",
           8'hF6, 16'd25,         "mesa_tx",
           8'hF6, 16'd26,         "lb_wr",
           8'hF6, 16'd27,         "lb_rd",
           8'hF6, 16'd28,         "btn0",
           8'hF6, 16'd29,         "btn1",
           8'hF6, 16'd30,         "btn2",
           8'hF6, 16'd31,         "btn3",
         8'hE5,                                     // End Group
       8'hE1,                                       // End View
     8'hE0                                          // End ROM
    })
)
u_sump3_core
(
  .clk_cap           ( clk_cap                 ), // SUMP Capture Clock
  .clk_lb            ( clk_lb                  ), // LocalBus Clock
  .ck_tick           ( 1'b0                    ), // Slow LS clock (strobe)
  .lb_cs_ctrl        ( lb_cs_ctrl              ), // SUMP Control Reg Strobe
  .lb_cs_data        ( lb_cs_data              ), // SUMP Data Reg Strobe
  .lb_wr             ( lb_wr                   ), // LocalBus Write Strobe
  .lb_rd             ( lb_rd                   ), // LocalBus Read Strobe
  .lb_wr_d           ( lb_wr_d[31:0]           ), // LocalBus Write Data
  .lb_rd_d           ( lb_rd_d[31:0]           ), // LocalBus Read Data
  .lb_rd_rdy         ( lb_rd_rdy               ), // LocalBus Read Data Ready

  .trigger_adc_ch    (                         ),
  .trigger_adc_level (                         ),
  .trigger_adc_more  ( 1'b0                    ),
  .trigger_adc_less  ( 1'b0                    ),
  .rec_cfg_select    (                         ),
  .rec_cfg_profile   ( 32'd0                   ),
  .rec_wr_en         ( 1'b0                    ),
  .rec_wr_addr       ( 8'd0                    ),
  .rec_wr_data       ( 32'd0                   ),
  .rec_timestamp     (                         ),
  .rec_sample_start  (                         ),

  .core_mosi         ( core_mosi[0:0]          ),
  .core_miso         ( core_miso[0:0]          ),
  .trigger_mosi      ( trigger_mosi[0:0]       ),
  .trigger_miso      ( trigger_miso[0:0]       ),

  .trigger_in        ( 1'b0                    ),
  .trigger_out       (                         ),
  .sump_is_armed     (                         ),
  .sump_is_awake     (                         ),
  .core_user_ctrl    (                         ),
  .dig_triggers      ( 32'd0                   )
);// sump3_core


endmodule // la_sump3.v
`default_nettype wire // enable Verilog default for any 3rd party IP needing it
