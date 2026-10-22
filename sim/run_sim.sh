#!/bin/sh
# Smoke test with Icarus Verilog : ./sim/run_sim.sh   ( from repo root )
set -e
cd "$(dirname "$0")/.."
M=third_party/MesaBusProtocol/verilog
S=third_party/sump3/verilog
mkdir -p sim/build
iverilog -g2005 -DSIMULATION -o sim/build/tb_la_top.vvp -s tb_la_top \
  sim/tb_la_top.v rtl/la_top.v rtl/la_clk_gen.v rtl/la_sump3.v rtl/la_test_pattern.v \
  $S/sump3_core.v $S/sump3_rle_hub.v $S/sump3_rle_pod.v $S/time_stamp.v \
  $M/ft232_xface.v $M/mesa_uart_phy.v $M/mesa_uart.v $M/mesa_tx_uart.v \
  $M/mesa_byte2ascii.v $M/mesa_ascii2nibble.v $M/mesa_decode.v $M/mesa2lb.v \
  $M/mesa_id.v $M/mesa2ctrl.v
vvp -n sim/build/tb_la_top.vvp
