# -----------------------------------------------------------------------------
# Vivado batch build for the XC7Z010 SUMP3 Logic Analyzer.
#
#   cd vivado
#   vivado -mode batch -source build.tcl -tclargs antminer_s9
#   vivado -mode batch -source build.tcl -tclargs antminer_s9_ols
#   vivado -mode batch -source build.tcl -tclargs antminer_s9_la16
#   vivado -mode batch -source build.tcl -tclargs antminer_s9_la16ddr
#   vivado -mode batch -source build.tcl -tclargs antminer_s9_la16eth
#   vivado -mode batch -source build.tcl -tclargs zybo_z7_10
#   vivado -mode batch -source build.tcl -tclargs arty_z7_10
#
# Output in vivado/build_<board>/ :
#   la_top.bit      JTAG ( Vivado Hardware Manager )
#   la_top.bit.bin  Linux FPGA manager ( byte swapped, like bootgen -process_bitstream )
#   la_top.xsa      Hardware platform ( antminer_s9 only, for an FSBL )
#   ps7_init.tcl    PS clock setup for JTAG only boot ( antminer_s9, s9_jtag_load.tcl )
#                   and DDR init ( s9_ddr_test.tcl )
#   *.rpt           Timing, utilization and I/O reports
#
# Board selects ../constraints/<board>.xdc and the top level:
#   antminer_s9           -> la_top_s9 ( clock = PS FCLK_CLK0, needs a PS7 block design )
#   antminer_s9_ols       -> la_top_s9_ols ( same board, OLS/SUMP protocol for PulseView,
#                            no SUMP3/MesaBus, uses constraints/antminer_s9.xdc )
#   antminer_s9_la16      -> la_top_s9_la16 ( same board, own la16 protocol and
#                            libsigrok driver, 200 MS/s, docs/PROTOCOL_LA16.md )
#   antminer_s9_la16ddr   -> la_top_s9_la16ddr ( la16 with the ring buffer in the
#                            PS DDR through S_AXI_HP0, 251M samples )
#   antminer_s9_la16eth   -> la_top_s9_la16eth ( DDR ring + Ethernet: the ARM
#                            program sw/la16_eth serves la16 over TCP, capture
#                            registers on M_AXI_GP0 )
#   zybo_z7_10/arty_z7_10 -> la_top    ( clock = 125 MHz PL oscillator, PL only )
# -----------------------------------------------------------------------------
# Named "target", not "board": write_hw_platform picks up a global Tcl "board"
# as the XSA board name, and Vitis sdtgen then fails looking for
# <name>.dtsi ( "board file is not present in DTG" ).
set target [expr { [llength $argv] > 0 ? [lindex $argv 0] : "antminer_s9" }]
set part   xc7z010clg400-1

set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/.."]
set out_dir    "$script_dir/build_$target"
# Variants "<board>_ols" / "<board>_la16" use the base board pins with the
# OLS or la16 engine instead of SUMP3
set variant ""
foreach v { ols la16 la16ddr la16eth } {
  if { [string match "*_$v" $target] } { set variant $v }
}
set ols_variant [expr { $variant ne "" }]
set pin_board   [expr { $ols_variant ? [string range $target 0 end-[expr { [string length $variant] + 1 }]] : $target }]
set board_xdc  "$root/constraints/$pin_board.xdc"

if { ![file exists $board_xdc] } {
  puts "ERROR: no constraints for board '$target' ( $board_xdc )"
  exit 1
}
if { !$ols_variant && ![file exists "$root/third_party/sump3/verilog/sump3_core.v"] } {
  puts "ERROR: third_party/ is empty ( SUMP3 + MesaBus sources are git submodules,"
  puts "       a GitHub \"Download ZIP\" does not include them ). From the repo root run:"
  puts "         python fetch_third_party.py"
  puts "       or, in a git clone: git submodule update --init --recursive"
  exit 1
}
proc find_file { dir name } {
  foreach f [glob -nocomplain -directory $dir -types f $name] { return $f }
  foreach d [glob -nocomplain -directory $dir -types d *] {
    set f [find_file $d $name]
    if { $f ne "" } { return $f }
  }
  return ""
}

set use_ps [expr { $pin_board eq "antminer_s9" }]
if { $ols_variant && !$use_ps } {
  puts "ERROR: the $variant variant currently exists for antminer_s9 only"
  exit 1
}
if { $ols_variant } {
  set top la_top_s9_$variant
} else {
  set top [expr { $use_ps ? "la_top_s9" : "la_top" }]
}

file delete -force $out_dir
file mkdir $out_dir

# An in-memory project is needed for the PS7 block design ( IP generation )
create_project -in_memory -part $part
set_property target_language Verilog [current_project]

# MesaBus mesa_id reports a 32bit UNIX build timestamp from module time_stamp
set ts [clock seconds]
set fh [open "$out_dir/time_stamp.v" w]
puts $fh "module time_stamp ( output wire \[31:0\] time_dout );"
puts $fh "  assign time_dout = 32'h[format %08x $ts];"
puts $fh "// [clock format $ts]"
puts $fh "endmodule"
close $fh

# -----------------------------------------------------------------------------
# PS7 block design: only FCLK_CLK0 = 100 MHz is used by the PL.
# -----------------------------------------------------------------------------
if { $use_ps } {
  create_bd_design -dir $out_dir la_ps
  set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
  set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0             {0}   \
    CONFIG.PCW_EN_CLK0_PORT              {1}   \
    CONFIG.PCW_EN_RST0_PORT              {1}   \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  {100} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE   {1}   \
    CONFIG.PCW_UART1_UART1_IO            {MIO 48 .. 49} \
  ] $ps7
  # S9 DDR: 2x Samsung K4B2G1646F-BYMA ( DDR3L, 2 Gbit x16 each ) = 32 bit, 512 MB.
  # Same geometry as Vivado's MT41K128M16 JT-125 ( 8 banks, 14 rows, 10 cols ).
  # 533 MHz is the -1 speed grade limit; the chips are DDR3L-1866 parts.
  # NOTE: on the board these presets give corrupted data. The DDR is set up
  # with U-Boot's S9 register values instead ( s9_ddr_init.tcl ); these
  # settings only keep the PS7 block consistent.
  set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE      {DDR 3 (Low Voltage)} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO           {MT41K128M16 JT-125} \
  ] $ps7
  # Part presets can override the bus width and clock, so set those after it
  set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH        {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ         {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE  {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE   {1} \
  ] $ps7
  set uses_hp0 [expr { $variant eq "la16ddr" || $variant eq "la16eth" }]
  if { $variant eq "la16eth" } {
    # Ethernet as on the S9 ( U-Boot board files ): GEM0 RGMII on MIO 16..27,
    # MDIO on MIO 52..53, PHY at address 1. MIO bank 1 ( MIO 16..53 ) is
    # 1.8 V on this board, bank 0 3.3 V. Capture registers on M_AXI_GP0.
    # TTC0 ( no pins ): the lwIP tick of the Vitis app comes from xiltimer's
    # interval timer, which needs a TTC ( the SCU timer does not count ).
    set_property -dict [list \
      CONFIG.PCW_TTC0_PERIPHERAL_ENABLE   {1} \
      CONFIG.PCW_TTC0_TTC0_IO             {EMIO} \
      CONFIG.PCW_PRESET_BANK0_VOLTAGE     {LVCMOS 3.3V} \
      CONFIG.PCW_PRESET_BANK1_VOLTAGE     {LVCMOS 1.8V} \
      CONFIG.PCW_ENET0_PERIPHERAL_ENABLE  {1} \
      CONFIG.PCW_ENET0_ENET0_IO           {MIO 16 .. 27} \
      CONFIG.PCW_ENET0_GRP_MDIO_ENABLE    {1} \
      CONFIG.PCW_ENET0_GRP_MDIO_IO        {MIO 52 .. 53} \
      CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
      CONFIG.PCW_ENET0_RESET_ENABLE       {0} \
      CONFIG.PCW_USE_M_AXI_GP0            {1} \
    ] $ps7
  }
  if { $uses_hp0 } {
    # Capture ring buffer in DDR: 64 bit AXI3 HP0 slave, clocked by FCLK_CLK0
    set_property -dict [list \
      CONFIG.PCW_USE_S_AXI_HP0       {1}  \
      CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
    ] $ps7
  }
  puts "PS7 DDR: [get_property CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE $ps7],\
 [get_property CONFIG.PCW_UIPARAM_DDR_PARTNO $ps7],\
 [get_property CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH $ps7],\
 [get_property CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ $ps7] MHz"

  create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
  create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO
  create_bd_port -dir O -type clk FCLK_CLK0
  create_bd_port -dir O -type rst FCLK_RESET0_N
  connect_bd_intf_net [get_bd_intf_ports DDR]      [get_bd_intf_pins ps7/DDR]
  connect_bd_intf_net [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]
  connect_bd_net      [get_bd_ports FCLK_CLK0]     [get_bd_pins ps7/FCLK_CLK0]
  connect_bd_net      [get_bd_ports FCLK_RESET0_N] [get_bd_pins ps7/FCLK_RESET0_N]
  if { $uses_hp0 } {
    create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_HP0
    set hp [get_bd_intf_ports S_AXI_HP0]
    foreach { k v } {
      PROTOCOL AXI3  DATA_WIDTH 64  ADDR_WIDTH 32  ID_WIDTH 6  FREQ_HZ 100000000
      HAS_REGION 0  HAS_QOS 1  HAS_LOCK 1  HAS_CACHE 1  HAS_PROT 1  HAS_BURST 1
      HAS_WSTRB 1  HAS_BRESP 1  HAS_RRESP 1  MAX_BURST_LENGTH 16
    } {
      if { [catch { set_property CONFIG.$k $v $hp } err] } {
        puts "NOTE: S_AXI_HP0 $k not set ( $err )"
      }
    }
    connect_bd_intf_net [get_bd_intf_ports S_AXI_HP0] [get_bd_intf_pins ps7/S_AXI_HP0]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/S_AXI_HP0_ACLK]
    set_property CONFIG.ASSOCIATED_BUSIF {S_AXI_HP0} [get_bd_ports FCLK_CLK0]
    assign_bd_address -target_address_space [get_bd_addr_spaces S_AXI_HP0] \
      [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
    puts "HP0 address map:"
    foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces S_AXI_HP0]] {
      puts "  $seg offset [get_property OFFSET $seg] range [get_property RANGE $seg]"
    }
  }
  if { $variant eq "la16eth" } {
    # la16_regs: 4 KB at 0x43C0_0000 in the GP0 range
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI_GP0
    set gp [get_bd_intf_ports M_AXI_GP0]
    foreach { k v } {
      PROTOCOL AXI3  DATA_WIDTH 32  ADDR_WIDTH 32  FREQ_HZ 100000000
    } {
      if { [catch { set_property CONFIG.$k $v $gp } err] } {
        puts "NOTE: M_AXI_GP0 $k not set ( $err )"
      }
    }
    connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] $gp
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
    set_property CONFIG.ASSOCIATED_BUSIF {S_AXI_HP0:M_AXI_GP0} [get_bd_ports FCLK_CLK0]
    assign_bd_address -offset 0x43C00000 -range 4K \
      -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs M_AXI_GP0/Reg] -force
    puts "GP0 address map:"
    foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps7/Data]] {
      puts "  $seg offset [get_property OFFSET $seg] range [get_property RANGE $seg]"
    }
  }

  validate_bd_design
  save_bd_design
  set bd_file [get_files la_ps.bd]
  set_property synth_checkpoint_mode None $bd_file
  generate_target all $bd_file
  make_wrapper -files $bd_file -top

  # ps7_init.tcl is used by s9_jtag_load.tcl to start the PS clocks over JTAG
  set ps7_init [find_file $out_dir ps7_init.tcl]
  if { $ps7_init ne "" } {
    file copy -force $ps7_init "$out_dir/ps7_init.tcl"
  } else {
    puts "WARNING: ps7_init.tcl not found, JTAG only boot will not work"
  }
  set wrapper [find_file $out_dir la_ps_wrapper.v]
  if { $wrapper eq "" } {
    puts "ERROR: la_ps_wrapper.v was not generated"
    exit 1
  }
  read_verilog $wrapper
}

# Project RTL
read_verilog "$root/rtl/la_test_pattern.v"
if { $variant eq "ols" } {
  # OLS / SUMP engine for PulseView ( own RTL, no third party HDL )
  read_verilog "$root/rtl/ols/ols_uart.v"
  read_verilog "$root/rtl/ols/ols_engine.v"
  read_verilog "$root/rtl/ols/la_ols_core.v"
  read_verilog "$root/rtl/ols/la_top_s9_ols.v"
} elseif { $variant eq "la16" || $variant eq "la16ddr" || $variant eq "la16eth" } {
  # la16 engine ( own protocol and libsigrok driver, own RTL )
  read_verilog "$root/rtl/ols/ols_uart.v"
  foreach f { la16_front la16_seq la16_store_bram la16_store_ddr la16_capture
              la16_engine la16_core la16_regs la16_eth_core } {
    read_verilog "$root/rtl/la16/$f.v"
  }
  read_verilog "$root/rtl/la16/la_top_s9_$variant.v"
  if { $variant eq "la16ddr" || $variant eq "la16eth" } {
    # Tells s9_jtag_load.tcl to initialize the DDR ( s9_ddr_init.tcl )
    set fh [open "$out_dir/needs_ddr" w]
    puts $fh "ring buffer in PS DDR via S_AXI_HP0"
    close $fh
  }
} else {
  read_verilog "$root/rtl/la_core.v"
  read_verilog "$root/rtl/la_sump3.v"
  if { $use_ps } {
    read_verilog "$root/rtl/la_top_s9.v"
  } else {
    read_verilog "$root/rtl/la_top.v"
    read_verilog "$root/rtl/la_clk_gen.v"
  }
  read_verilog "$out_dir/time_stamp.v"

  # SUMP3 IP ( https://github.com/blackmesalabs/sump3 )
  set s3 "$root/third_party/sump3/verilog"
  read_verilog "$s3/sump3_core.v"
  read_verilog "$s3/sump3_rle_hub.v"
  read_verilog "$s3/sump3_rle_pod.v"

  # MesaBus UART ( https://github.com/blackmesalabs/MesaBusProtocol )
  set mb "$root/third_party/MesaBusProtocol/verilog"
  foreach f { ft232_xface mesa_uart_phy mesa_uart mesa_tx_uart mesa_byte2ascii
              mesa_ascii2nibble mesa_decode mesa2lb mesa_id mesa2ctrl } {
    read_verilog "$mb/$f.v"
  }
}

read_xdc $board_xdc
# Variant specific extra pins, e.g. constraints/antminer_s9_ols.xdc / _la16.xdc
if { $ols_variant && [file exists "$root/constraints/$target.xdc"] } {
  read_xdc "$root/constraints/$target.xdc"
}

synth_design -top $top -part $part
report_utilization    -file "$out_dir/post_synth_util.rpt"

opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file "$out_dir/post_route_timing_summary.rpt"
report_utilization    -file "$out_dir/post_route_util.rpt"
report_io             -file "$out_dir/post_route_io.rpt"

write_bitstream -force -bin_file "$out_dir/la_top.bit"

# Linux zynq FPGA manager wants each 32 bit word byte swapped ( *.bit.bin )
if { [file exists "$out_dir/la_top.bin"] } {
  set fi [open "$out_dir/la_top.bin" rb]
  set raw [read $fi]
  close $fi
  binary scan $raw i* words
  set fo [open "$out_dir/la_top.bit.bin" wb]
  puts -nonewline $fo [binary format I* $words]
  close $fo
}

if { $use_ps } {
  # No board part / board id: a custom board without a Vitis device tree file
  catch { set_property platform.board_id {} [current_project] }
  if { [catch { write_hw_platform -fixed -force -file "$out_dir/la_top.xsa" } err] } {
    puts "NOTE: write_hw_platform skipped ( $err )"
  }
}

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "======================================================================"
puts " Board      : $target ( $part ), top = $top"
puts " Bitstream  : $out_dir/la_top.bit"
puts " Linux      : $out_dir/la_top.bit.bin"
puts " Setup WNS  : $wns ns"
puts "======================================================================"
if { $wns < 0 } {
  puts "WARNING: timing not met, see $out_dir/post_route_timing_summary.rpt"
}
