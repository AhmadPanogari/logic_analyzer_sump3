#!/bin/sh
# Pin level smoke test of la_top_s9_ols ( UART 921600 baud ) with Icarus.
set -e
cd "$(dirname "$0")/../.."
mkdir -p sim/build
iverilog -g2005 -DSIMULATION -o sim/build/tb_ols_uart.vvp -s tb_ols_uart \
  sim/ols/tb_ols_uart.v rtl/ols/la_top_s9_ols.v rtl/ols/la_ols_core.v \
  rtl/ols/ols_engine.v rtl/ols/ols_uart.v rtl/la_test_pattern.v \
  sim/la_ps_wrapper_stub.v
vvp -n sim/build/tb_ols_uart.vvp
