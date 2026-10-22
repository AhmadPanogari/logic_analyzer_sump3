#!/bin/sh
# Smoke test with Icarus Verilog, from the repo root:
#   ./sim/run_sim.sh          Digilent top ( la_top, MMCM bypassed )
#   ./sim/run_sim.sh s9       Antminer S9 top ( la_top_s9, PS7 stub clock )
set -e
cd "$(dirname "$0")/.."
M=third_party/MesaBusProtocol/verilog
S=third_party/sump3/verilog
if [ "$1" = "s9" ]; then
  TOP="-DS9 rtl/la_top_s9.v sim/la_ps_wrapper_stub.v"
else
  TOP="rtl/la_top.v rtl/la_clk_gen.v"
fi
mkdir -p sim/build
iverilog -g2005 -DSIMULATION -o sim/build/tb_la_top.vvp -s tb_la_top \
  sim/tb_la_top.v $TOP rtl/la_core.v rtl/la_sump3.v rtl/la_test_pattern.v \
  $S/sump3_core.v $S/sump3_rle_hub.v $S/sump3_rle_pod.v $S/time_stamp.v \
  $M/ft232_xface.v $M/mesa_uart_phy.v $M/mesa_uart.v $M/mesa_tx_uart.v \
  $M/mesa_byte2ascii.v $M/mesa_ascii2nibble.v $M/mesa_decode.v $M/mesa2lb.v \
  $M/mesa_id.v $M/mesa2ctrl.v
vvp -n sim/build/tb_la_top.vvp
