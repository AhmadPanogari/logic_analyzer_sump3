# cocotb + Icarus co-simulation of ols_engine for the libsigrok OLS driver.
# Use run_cosim.sh, which also runs sigrok-cli against it.
SIM ?= icarus
TOPLEVEL_LANG = verilog
RTL = ../../rtl
VERILOG_SOURCES = $(PWD)/tb_ols_cosim.v $(RTL)/ols/ols_engine.v $(RTL)/la_test_pattern.v
COCOTB_TOPLEVEL = tb_ols_cosim
COCOTB_TEST_MODULES = test_ols_cosim
include $(shell cocotb-config --makefiles)/Makefile.sim
