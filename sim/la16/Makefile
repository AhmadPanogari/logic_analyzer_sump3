# cocotb + Icarus unit tests for the la16 protocol engine ( rtl/la16 ).
#   make            all tests
#   make COCOTB_TEST_FILTER=test_trigger_edges
SIM ?= icarus
TOPLEVEL_LANG = verilog
RTL = ../../rtl
VERILOG_SOURCES = $(PWD)/tb_la16.v $(RTL)/la16/la16_engine.v $(RTL)/la16/la16_capture.v
COCOTB_TOPLEVEL = tb_la16
COCOTB_TEST_MODULES = test_la16
include $(shell cocotb-config --makefiles)/Makefile.sim
