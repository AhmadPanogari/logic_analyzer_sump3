@echo off
REM JTAG only bring-up of the Antminer S9 ( needs xsct from Vitis/SDK on PATH )
call xsct "%~dp0s9_jtag_load.tcl" %*
