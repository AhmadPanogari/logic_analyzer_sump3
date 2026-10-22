#!/bin/sh
# JTAG only bring-up of the Antminer S9.
# Uses xsct ( Vitis / SDK ) if found, else xsdb ( ships with Vivado: <Vivado>/bin/xsdb ).
TCL="$(dirname "$0")/s9_jtag_load.tcl"
if command -v xsct >/dev/null 2>&1; then exec xsct "$TCL" "$@"; fi
exec xsdb "$TCL" "$@"
