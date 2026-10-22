# -----------------------------------------------------------------------------
# Load the bitstream into the PL over JTAG ( volatile, lost on power off ).
#   vivado -mode batch -source program.tcl -tclargs antminer_s9
# -----------------------------------------------------------------------------
set board  [expr { [llength $argv] > 0 ? [lindex $argv 0] : "antminer_s9" }]
set bit    [file normalize "[file dirname [info script]]/build_$board/la_top.bit"]

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z010*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "Programmed $bit"
close_hw_manager
