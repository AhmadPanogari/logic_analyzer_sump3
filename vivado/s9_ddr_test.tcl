# -----------------------------------------------------------------------------
# DDR bring-up test for the Antminer S9 control board over JTAG.
#
#   xsdb vivado/s9_ddr_test.tcl                      ( or xsct )
#   xsdb vivado/s9_ddr_test.tcl <build_dir>
#
# Same setup as s9_jtag_load.tcl ( boot jumpers JP1..JP4 = 0, JTAG on J10,
# 12 V on, Vivado Hardware Manager closed ). Needs ps7_init.tcl from a build
# made after the DDR settings were added to build.tcl ( any antminer_s9* board ).
#
# Board DDR: 2x Samsung K4B2G1646F-BYMA ( DDR3L 2 Gbit x16 ) = 32 bit, 512 MB,
# CPU address 0x00000000 .. 0x1FFFFFFF ( the first 1 MB is skipped: OCM ).
#
# Steps: system reset, MIO + PLL + clock + DDR init from ps7_init.tcl ( the
# order of ps7_init; the MIO part also sets up the DDR I/O buffers ( DDRIOB )
# and runs the DCI calibration, without it DDR accesses hang ), then
#   1) DDR controller status
#   2) data bus walking ones ( 32 bit )
#   3) address bus ( aliasing between all power of two offsets, finds missing
#      or swapped address lines and a wrong size )
#   4) pseudo random blocks at 8 places across the 512 MB
# Nothing is loaded into the PL. Run s9_jtag_load.tcl afterwards as usual.
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set build_dir  [expr { [llength $argv] > 0 ? [file normalize [lindex $argv 0]] \
                                           : "$script_dir/build_antminer_s9_ols" }]
set init       "$build_dir/ps7_init.tcl"
if { ![file exists $init] } {
  set init "$script_dir/build_antminer_s9/ps7_init.tcl"
}
if { ![file exists $init] } {
  puts "ERROR: ps7_init.tcl not found. Build first: vivado -mode batch -source build.tcl -tclargs antminer_s9_ols"
  exit 1
}

set ddr_base 0x00100000
set ddr_end  0x20000000          ;# 512 MB
set block_words 4096             ;# 16 KB per random block

connect
if { [info exists ::env(S9_JTAG_HZ)] } {
  catch { jtag targets -set -filter {level == 0}; jtag frequency $::env(S9_JTAG_HZ) }
}
if { [llength [targets -filter {name =~ "APU*"}]] == 0 } {
  puts "ERROR: no Zynq APU target ( see s9_jtag_load.tcl for the checklist )"
  exit 1
}

targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000
targets -set -nocase -filter {name =~ "*A9*#0"}
catch { stop }
puts "Using $init"
source $init

configparams force-mem-accesses 1
set si_ver [expr { [llength [info procs ps_version]] ? [ps_version] : "3.0" }]
switch -- $si_ver {
  "1.0"   { set sfx 1_0 }
  "2.0"   { set sfx 2_0 }
  default { set sfx 3_0 }
}
if { [llength [info procs ps7_ddr_init_data_$sfx]] == 0 } {
  puts "ERROR: ps7_ddr_init_data_$sfx missing in $init ( DDR disabled in the PS7 block? )"
  exit 1
}
puts "Zynq silicon $si_ver : MIO ( incl. DDR I/O + DCI ), PLL, clock and DDR init"
if { [catch { ps7_mio_init_data_$sfx } err] } {
  puts "ERROR: MIO / DDR I/O init failed: $err"
  exit 1
}
ps7_pll_init_data_$sfx
ps7_clock_init_data_$sfx
if { [catch { ps7_ddr_init_data_$sfx } err] } {
  puts "ERROR: DDR init failed: $err"
  exit 1
}

set fails 0
proc check { name ok detail } {
  global fails
  if { $ok } {
    puts [format "  PASS  %s" $name]
  } else {
    incr fails
    puts [format "  FAIL  %s : %s" $name $detail]
  }
}
# A DDR access that never completes stalls the CPU and xsdb reports a timeout.
# Turn that into a clear FAIL and stop instead of a Tcl traceback.
proc bus_error { what a err } {
  global fails
  incr fails
  puts [format "  FAIL  %s at 0x%08X does not complete ( bus hang )" $what $a]
  puts "        $err"
  puts "======================================================================"
  puts " DDR FAILED: accesses hang. Send this output."
  puts "======================================================================"
  catch { disconnect }
  exit 1
}
proc rd  { a } {
  if { [catch { mrd -force -value $a } r] } { bus_error "read" $a $r }
  return $r
}
proc wr  { a v } {
  if { [catch { mwr -force $a $v } r] } { bus_error "write" $a $r }
}

# 1) Controller status: DDRC mode_sts_reg bits 2..0 = 1 is normal operation
set sts [rd 0xF8006054]
puts "======================================================================"
puts [format " DDRC mode_sts_reg 0xF8006054 = 0x%08X ( bits 2..0 = 1 expected )" $sts]
puts [format " DDRC ctrl_reg1    0xF8006000 = 0x%08X" [rd 0xF8006000]]
puts "======================================================================"
check "controller in normal mode" [expr { ($sts & 7) == 1 }] [format "mode %d" [expr { $sts & 7 }]]

# 2) Data bus: walking ones at one address
set bad {}
for { set i 0 } { $i < 32 } { incr i } {
  set v [expr { 1 << $i }]
  wr $ddr_base $v
  set r [rd $ddr_base]
  if { $r != $v } { lappend bad [format "bit %d wrote 0x%08X read 0x%08X" $i $v $r] }
}
check "data bus walking ones" [expr { [llength $bad] == 0 }] [join [lrange $bad 0 3] "; "]

# 3) Address bus: every power of two offset must be its own location
set offs {}
for { set o 4 } { $ddr_base + $o < $ddr_end } { set o [expr { $o << 1 }] } { lappend offs $o }
set pat  0xAAAAAAAA
set anti 0x55555555
foreach o $offs { wr [expr { $ddr_base + $o }] $pat }
wr $ddr_base $anti
set bad {}
foreach o $offs {
  set r [rd [expr { $ddr_base + $o }]]
  if { $r != $pat } { lappend bad [format "offset 0x%08X reads 0x%08X ( alias of base? )" $o $r] }
}
wr $ddr_base $pat
foreach t $offs {
  wr [expr { $ddr_base + $t }] $anti
  foreach o $offs {
    if { $o == $t } continue
    set r [rd [expr { $ddr_base + $o }]]
    if { $r != $pat } {
      lappend bad [format "write 0x%08X changes 0x%08X" $t $o]
      break
    }
  }
  wr [expr { $ddr_base + $t }] $pat
}
check [format "address bus ( %d lines, up to 0x%08X )" [llength $offs] [expr { $ddr_base + [lindex $offs end] }]] \
      [expr { [llength $bad] == 0 }] [join [lrange $bad 0 3] "; "]

# 4) Pseudo random blocks
set places {}
set span [expr { $ddr_end - $ddr_base - $block_words * 4 }]
for { set k 0 } { $k < 8 } { incr k } {
  lappend places [expr { ($ddr_base + $span * $k / 7) & ~0xFFF }]
}
set seed 12345
foreach a $places {
  set vals {}
  for { set i 0 } { $i < $block_words } { incr i } {
    set seed [expr { ($seed * 1103515245 + 12345) & 0xFFFFFFFF }]
    lappend vals [expr { $seed ^ ($a + $i * 4) }]
  }
  set t0 [clock milliseconds]
  if { [catch { mwr -force $a $vals $block_words } r] } { bus_error "block write" $a $r }
  if { [catch { mrd -force -value $a $block_words } got] } { bus_error "block read" $a $got }
  set ms [expr { [clock milliseconds] - $t0 }]
  set nbad 0
  set first ""
  for { set i 0 } { $i < $block_words } { incr i } {
    if { [lindex $got $i] != [lindex $vals $i] } {
      if { $nbad == 0 } {
        set first [format "0x%08X: wrote 0x%08X read 0x%08X" [expr { $a + $i * 4 }] \
                    [lindex $vals $i] [lindex $got $i]]
      }
      incr nbad
    }
  }
  check [format "random 16 KB at 0x%08X ( %d ms )" $a $ms] [expr { $nbad == 0 }] "$nbad errors, first $first"
}
configparams force-mem-accesses 0

puts "======================================================================"
if { $fails == 0 } {
  puts " DDR OK: 512 MB, 32 bit, 533 MHz. Ready for the capture buffer."
} else {
  puts " DDR FAILED: $fails test(s). Send this output."
}
puts "======================================================================"
disconnect
exit
