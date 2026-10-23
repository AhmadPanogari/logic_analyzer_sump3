# -----------------------------------------------------------------------------
# Vivado batch build for the XC7Z010 SUMP3 Logic Analyzer.
#
#   cd vivado
#   vivado -mode batch -source build.tcl -tclargs antminer_s9
#   vivado -mode batch -source build.tcl -tclargs antminer_s9_ols
#   vivado -mode batch -source build.tcl -tclargs zybo_z7_10
#   vivado -mode batch -source build.tcl -tclargs arty_z7_10
#
# Output in vivado/build_<board>/ :
#   la_top.bit      JTAG ( Vivado Hardware Manager )
#   la_top.bit.bin  Linux FPGA manager ( byte swapped, like bootgen -process_bitstream )
#   la_top.xsa      Hardware platform ( antminer_s9 only, for an FSBL )
#   ps7_init.tcl    PS clock setup for JTAG only boot ( antminer_s9, s9_jtag_load.tcl )
#   *.rpt           Timing, utilization and I/O reports
#
# Board selects ../constraints/<board>.xdc and the top level:
#   antminer_s9           -> la_top_s9 ( clock = PS FCLK_CLK0, needs a PS7 block design )
#   antminer_s9_ols       -> la_top_s9_ols ( same board, OLS/SUMP protocol for PulseView,
#                            no SUMP3/MesaBus, uses constraints/antminer_s9.xdc )
#   zybo_z7_10/arty_z7_10 -> la_top    ( clock = 125 MHz PL oscillator, PL only )
# -----------------------------------------------------------------------------
set board  [expr { [llength $argv] > 0 ? [lindex $argv 0] : "antminer_s9" }]
set part   xc7z010clg400-1

set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/.."]
set out_dir    "$script_dir/build_$board"
# Variant "<board>_ols" uses the base board pins with the OLS engine
set ols_variant [string match "*_ols" $board]
set pin_board   [expr { $ols_variant ? [string range $board 0 end-4] : $board }]
set board_xdc  "$root/constraints/$pin_board.xdc"

if { ![file exists $board_xdc] } {
  puts "ERROR: no constraints for board '$board' ( $board_xdc )"
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
  puts "ERROR: the OLS variant currently exists for antminer_s9 only"
  exit 1
}
if { $ols_variant } {
  set top la_top_s9_ols
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

  create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
  create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO
  create_bd_port -dir O -type clk FCLK_CLK0
  create_bd_port -dir O -type rst FCLK_RESET0_N
  connect_bd_intf_net [get_bd_intf_ports DDR]      [get_bd_intf_pins ps7/DDR]
  connect_bd_intf_net [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]
  connect_bd_net      [get_bd_ports FCLK_CLK0]     [get_bd_pins ps7/FCLK_CLK0]
  connect_bd_net      [get_bd_ports FCLK_RESET0_N] [get_bd_pins ps7/FCLK_RESET0_N]

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
if { $ols_variant } {
  # OLS / SUMP engine for PulseView ( own RTL, no third party HDL )
  read_verilog "$root/rtl/ols/ols_uart.v"
  read_verilog "$root/rtl/ols/ols_engine.v"
  read_verilog "$root/rtl/ols/la_ols_core.v"
  read_verilog "$root/rtl/ols/la_top_s9_ols.v"
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
  if { [catch { write_hw_platform -fixed -force -file "$out_dir/la_top.xsa" } err] } {
    puts "NOTE: write_hw_platform skipped ( $err )"
  }
}

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "======================================================================"
puts " Board      : $board ( $part ), top = $top"
puts " Bitstream  : $out_dir/la_top.bit"
puts " Linux      : $out_dir/la_top.bit.bin"
puts " Setup WNS  : $wns ns"
puts "======================================================================"
if { $wns < 0 } {
  puts "WARNING: timing not met, see $out_dir/post_route_timing_summary.rpt"
}
