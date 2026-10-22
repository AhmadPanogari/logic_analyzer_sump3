# -----------------------------------------------------------------------------
# Non-project Vivado build for the XC7Z010 SUMP3 Logic Analyzer.
#
#   cd vivado
#   vivado -mode batch -source build.tcl -tclargs zybo_z7_10
#   vivado -mode batch -source build.tcl -tclargs arty_z7_10
#
# Output: vivado/build_<board>/la_top.bit  + reports
# The board name selects ../constraints/<board>.xdc
# -----------------------------------------------------------------------------
set board  [expr { [llength $argv] > 0 ? [lindex $argv 0] : "zybo_z7_10" }]
set part   xc7z010clg400-1
set top    la_top

set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/.."]
set out_dir    "$script_dir/build_$board"
set board_xdc  "$root/constraints/$board.xdc"

if { ![file exists $board_xdc] } {
  puts "ERROR: no constraints for board '$board' ( $board_xdc )"
  exit 1
}
if { ![file exists "$root/third_party/sump3/verilog/sump3_core.v"] } {
  puts "ERROR: third_party submodules missing. Run: git submodule update --init"
  exit 1
}
file mkdir $out_dir

# MesaBus mesa_id reports a 32bit UNIX build timestamp from module time_stamp
set ts [clock seconds]
set fh [open "$out_dir/time_stamp.v" w]
puts $fh "module time_stamp ( output wire \[31:0\] time_dout );"
puts $fh "  assign time_dout = 32'h[format %08x $ts];"
puts $fh "// [clock format $ts]"
puts $fh "endmodule"
close $fh

set_part $part

# Project RTL
read_verilog "$root/rtl/la_top.v"
read_verilog "$root/rtl/la_clk_gen.v"
read_verilog "$root/rtl/la_sump3.v"
read_verilog "$root/rtl/la_test_pattern.v"
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

read_xdc "$root/constraints/timing.xdc"
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

write_bitstream -force "$out_dir/$top.bit"

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "======================================================================"
puts " Board      : $board ( $part )"
puts " Bitstream  : $out_dir/$top.bit"
puts " Setup WNS  : $wns ns"
puts "======================================================================"
if { $wns < 0 } {
  puts "WARNING: timing not met, see $out_dir/post_route_timing_summary.rpt"
}
