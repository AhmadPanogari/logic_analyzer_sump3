# -----------------------------------------------------------------------------
# Load the bitstream into the PL over JTAG ( volatile, lost on power off ).
#   vivado -mode batch -source program.tcl -tclargs zybo_z7_10
# Antminer S9: use s9_jtag_load.tcl instead ( it also starts the PS clock FCLK0 ).
# -----------------------------------------------------------------------------
set board  [expr { [llength $argv] > 0 ? [lindex $argv 0] : "zybo_z7_10" }]
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
