#!/bin/sh
# Usage: ./build.sh [antminer_s9|zybo_z7_10|arty_z7_10]
cd "$(dirname "$0")"
vivado -mode batch -nojournal -log build_${1:-antminer_s9}.log -source build.tcl -tclargs "${1:-antminer_s9}"
