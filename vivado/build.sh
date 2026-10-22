#!/bin/sh
# Usage: ./build.sh [zybo_z7_10|arty_z7_10]
cd "$(dirname "$0")"
vivado -mode batch -nojournal -log build_${1:-zybo_z7_10}.log -source build.tcl -tclargs "${1:-zybo_z7_10}"
