# cocotb + Icarus unit tests for the la16 protocol engine ( rtl/la16 ).
#   make            all tests
#   make COCOTB_TEST_FILTER=test_trigger_edges
#   make USE_DDR=1  ( ring buffer through the AXI3 model instead of BRAM;
#                     run "make clean" when switching )
SIM ?= icarus
TOPLEVEL_LANG = verilog
RTL = ../../rtl
USE_DDR ?= 0
VERILOG_SOURCES = $(PWD)/tb_la16.v $(PWD)/axi3_mem_model.v \
  $(addprefix $(RTL)/la16/, la16_engine.v la16_capture.v la16_front.v la16_seq.v \
    la16_store_bram.v la16_store_ddr.v)
COMPILE_ARGS += -Ptb_la16.USE_DDR=$(USE_DDR)
COCOTB_TOPLEVEL = tb_la16
COCOTB_TEST_MODULES = test_la16
include $(shell cocotb-config --makefiles)/Makefile.sim
