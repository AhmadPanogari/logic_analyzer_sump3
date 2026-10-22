#!/bin/sh
# Run ON the Antminer S9 board ( Linux booted from microSD ) as root:
#   sh s9_load_bitstream.sh la_top.bit.bin
#
# Loads the logic analyzer into the PL through the Linux FPGA manager.
# The boot loader already runs FCLK0 at 100 MHz, which is the PL clock.
# Stop any service that accesses the previous PL design over AXI first:
# with this design loaded those addresses are empty and an access hangs
# the bus ( the watchdog then resets the board ).
set -e
BIN=${1:-la_top.bit.bin}
MGR=/sys/class/fpga_manager/fpga0
[ -e "$MGR/firmware" ] || { echo "ERROR: $MGR not found ( no FPGA manager in this kernel )"; exit 1; }
mkdir -p /lib/firmware
cp "$BIN" /lib/firmware/la_top.bit.bin
echo 0 > "$MGR/flags"                       # full bitstream
echo la_top.bit.bin > "$MGR/firmware"
echo "FPGA manager state: $(cat $MGR/state)"
if [ -r /sys/devices/soc0/amba/f8007000.devcfg/fclk/fclk0/set_rate ]; then
  echo "FCLK0: $(cat /sys/devices/soc0/amba/f8007000.devcfg/fclk/fclk0/set_rate) Hz"
fi
for f in /sys/kernel/debug/clk/fclk0/clk_rate; do
  [ -r "$f" ] && echo "FCLK0: $(cat $f) Hz"
done
exit 0
