#!/bin/sh
# JTAG only bring-up of the Antminer S9 ( needs xsct from Vitis/SDK on PATH )
exec xsct "$(dirname "$0")/s9_jtag_load.tcl" "$@"
