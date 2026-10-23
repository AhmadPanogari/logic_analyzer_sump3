#!/bin/sh
# DDR test of the Antminer S9 over JTAG.
# Uses xsct ( Vitis / SDK ) if found, else xsdb ( ships with Vivado: <Vivado>/bin/xsdb ).
TCL="$(dirname "$0")/s9_ddr_test.tcl"
if command -v xsct >/dev/null 2>&1; then exec xsct "$TCL" "$@"; fi
exec xsdb "$TCL" "$@"
