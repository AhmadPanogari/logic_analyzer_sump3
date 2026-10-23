# -----------------------------------------------------------------------------
# JTAG only bring-up for the Antminer S9 control board ( no SD card, no Linux ).
#
#   xsct vivado/s9_jtag_load.tcl            ( Vitis / SDK )
#   xsdb vivado/s9_jtag_load.tcl            ( ships with Vivado 2025.x )
#   xsct vivado/s9_jtag_load.tcl <build_dir>
#
# Board: boot jumpers JP1..JP4 all at 0 ( "Cascade JTAG" ), Xilinx/Digilent
# JTAG cable ( or an FT2232H programmed with program_ftdi ) on J10, 12 V on. Close the Vivado Hardware Manager first ( only
# one program can own the cable ).
#
# The S9 PL has no oscillator. Its 100 MHz clock is FCLK_CLK0 from the PS, and
# in JTAG boot mode nobody starts the PS clocks. This script:
#   1) resets the system and loads la_top.bit into the PL
#   2) runs only the PLL and clock parts of ps7_init.tcl ( from build.tcl ).
#      DDR and MIO init are skipped, except for builds that keep the capture
#      buffer in DDR ( antminer_s9_la16ddr, marked by <build_dir>/needs_ddr ):
#      then MIO + s9_ddr_init.tcl ( U-Boot's S9 DDR values ) run as well.
#      Ethernet builds ( antminer_s9_la16eth with <build_dir>/la16_eth.elf from
#      sw/la16_eth/vitis_build.py ) also run the peripheral init ( UART ) and,
#      after step 3, download and start the ARM program.
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

# Optional: slower TCK for long jumper wires / generic FT2232H boards
#   set S9_JTAG_HZ=1000000   ( Windows )   or   S9_JTAG_HZ=1000000 xsdb ... ( Linux )
if { [info exists ::env(S9_JTAG_HZ)] } {
  if { [catch { jtag targets -set -filter {level == 0}
                jtag frequency $::env(S9_JTAG_HZ)
                puts "JTAG TCK: [jtag frequency] Hz" } err] } {
    puts "NOTE: could not set JTAG frequency ( $err )"
  }
}

puts "JTAG targets:"
puts [targets]
if { [llength [targets -filter {name =~ "APU*"}]] == 0 } {
  puts "ERROR: no Zynq APU target. Check: JTAG cable recognized by hw_server"
  puts "       ( generic FT2232H needs program_ftdi, see README ), wiring on J10,"
  puts "       12 V on, boot jumpers JP1..JP4 = 0, Vivado Hardware Manager closed."
  exit 1
}

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
if { [file exists "$build_dir/needs_ddr"] } {
  source "$script_dir/s9_ddr_init.tcl"
  puts "DDR capture buffer: MIO + DDR init ( s9_ddr_init.tcl )"
  ps7_mio_init_data_$sfx
  if { [catch { s9_ddr_init } err] } {
    puts "ERROR: DDR init failed: $err"
    exit 1
  }
  set ddr_sts [mrd -force -value 0xF8006054]
  puts [format " DDRC mode_sts_reg = 0x%08X ( bits 2..0 = 1 expected )" $ddr_sts]
  if { ( $ddr_sts & 7 ) != 1 } {
    puts "ERROR: DDR controller not in normal mode, run s9_ddr_test.tcl"
    exit 1
  }
}
set app_elf "$build_dir/la16_eth.elf"
if { [file exists $app_elf] } {
  if { [catch { ps7_peripherals_init_data_$sfx } err] } {
    puts "NOTE: peripheral init: $err"
  }
}
configparams force-mem-accesses 0

# 3) Level shifters on, FPGA resets released
ps7_post_config

# Ethernet build: start the la16 server on CPU #0
if { [file exists $app_elf] } {
  puts "Starting ARM program $app_elf"
  dow $app_elf
  con
  set ip_file "$build_dir/la16_eth_ip.txt"
  set ip [expr { [file exists $ip_file] ? [string trim [read [open $ip_file]]] : "192.168.1.10" }]
  puts "la16 server: TCP $ip port 5555 ( PulseView: driver la16, Network / Raw TCP )"
}

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

# Without an ARM program the CPU stays halted, which is fine: the PL only
# needs FCLK0.
disconnect
exit
