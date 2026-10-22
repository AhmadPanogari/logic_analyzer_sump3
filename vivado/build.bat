@echo off
REM Usage: build.bat [zybo_z7_10|arty_z7_10]   ( run from "Vivado Tcl Shell" or with vivado on PATH )
set BOARD=%1
if "%BOARD%"=="" set BOARD=zybo_z7_10
cd /d %~dp0
call vivado -mode batch -nojournal -log build_%BOARD%.log -source build.tcl -tclargs %BOARD%
