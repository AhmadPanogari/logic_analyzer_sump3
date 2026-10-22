# -----------------------------------------------------------------------------
# JTAG only bring-up for the Antminer S9 control board ( no SD card, no Linux ).
#
#   xsct vivado/s9_jtag_load.tcl            ( Vitis / SDK, or: xsdb ... )
#   xsct vivado/s9_jtag_load.tcl <build_dir>
#
# Board: boot jumpers JP1..JP4 all at 0 ( "Cascade JTAG" ), Xilinx/Digilent
# JTAG cable on J10, 12 V on. Close the Vivado Hardware Manager first ( only
# one program can own the cable ).
#
# The S9 PL has no oscillator. Its 100 MHz clock is FCLK_CLK0 from the PS, and
# in JTAG boot mode nobody starts the PS clocks. This script:
#   1) resets the system and loads la_top.bit into the PL
#   2) runs only the PLL and clock parts of ps7_init.tcl ( from build.tcl ).
#      DDR and MIO init are skipped: the logic analyzer does not use them, and
#      the block design's DDR settings are not tuned for this board.
#   3) runs ps7_post_config: enables the PS<->PL level shifters ( FCLK only
#      reaches the PL after this ) and releases the FPGA resets
#   4) reads the clock registers back and prints the FCLK0 frequency
#
# Everything is volatile. After a power cycle, run this script again.
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set build_dir  [expr { [llength $argv] > 0 ? [file normalize [lindex $argv 0]] \
                                           : "$script_dir/build_antminer_s9" }]
set bit        "$build_dir/la_top.bit"
set init       "$build_dir/ps7_init.tcl"
set ps_clk_mhz 33.333333   ;# Y1 oscillator on PS_CLK

foreach f [list $bit $init] {
  if { ![file exists $f] } {
    puts "ERROR: $f not found. Build first: vivado -mode batch -source build.tcl -tclargs antminer_s9"
    exit 1
  }
}

connect
puts "JTAG targets:"
puts [targets]

# 1) System reset, then configure the PL
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000
puts "Programming $bit"
fpga -file $bit

# 2) PLL + clock init only, on CPU #0
targets -set -nocase -filter {name =~ "*A9*#0"}
catch { stop }
source $init

configparams force-mem-accesses 1
set si_ver [expr { [llength [info procs ps_version]] ? [ps_version] : "3.0" }]
switch -- $si_ver {
  "1.0"   { set sfx 1_0 }
  "2.0"   { set sfx 2_0 }
  default { set sfx 3_0 }
}
puts "Zynq silicon $si_ver : ps7_pll_init_data_$sfx + ps7_clock_init_data_$sfx"
ps7_pll_init_data_$sfx
ps7_clock_init_data_$sfx
configparams force-mem-accesses 0

# 3) Level shifters on, FPGA resets released
ps7_post_config

# 4) Verify FCLK0
proc bits { v hi lo } { return [expr { ($v >> $lo) & ((1 << ($hi - $lo + 1)) - 1) }] }

set pll_status [mrd -force -value 0xF800010C]
set fclk0_ctrl [mrd -force -value 0xF8000170]
set lvl_shftr  [mrd -force -value 0xF8000900]
set src  [bits $fclk0_ctrl 5 4]
set div0 [bits $fclk0_ctrl 13 8]
set div1 [bits $fclk0_ctrl 25 20]
switch -- $src {
  2       { set pll_reg 0xF8000100; set pll_name ARM; set lock_bit 0 }
  3       { set pll_reg 0xF8000104; set pll_name DDR; set lock_bit 1 }
  default { set pll_reg 0xF8000108; set pll_name IO;  set lock_bit 2 }
}
set fdiv   [bits [mrd -force -value $pll_reg] 18 12]
set locked [bits $pll_status $lock_bit $lock_bit]
set fclk0  [expr { $ps_clk_mhz * $fdiv / double( max( 1, $div0 * $div1 ) ) }]

puts "======================================================================"
puts [format " %s PLL      : %.3f MHz ( FDIV %d, locked %d )" \
       $pll_name [expr { $ps_clk_mhz * $fdiv }] $fdiv $locked]
puts [format " FCLK0       : %.3f MHz ( DIV0 %d, DIV1 %d )" $fclk0 $div0 $div1]
puts [format " LVL_SHFTR_EN: 0x%X ( expect 0xF )" $lvl_shftr]
puts "======================================================================"
if { !$locked || abs( $fclk0 - 100.0 ) > 0.5 || ( $lvl_shftr & 0xF ) != 0xF } {
  puts "WARNING: FCLK0 is not 100 MHz / not enabled. SUMP3 time base will be wrong."
} else {
  puts "OK: LED D5 should now blink ( ~0.75 Hz ) and D6 be on."
  puts "    Next: python host/la.py server --port <COM>  and  python host/la.py gui"
}

# The CPU stays halted in JTAG mode, which is fine: the PL only needs FCLK0.
disconnect
exit
