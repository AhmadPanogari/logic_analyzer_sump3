@echo off
REM Usage: build.bat [antminer_s9|antminer_s9_ols|antminer_s9_la16|antminer_s9_la16ddr|antminer_s9_la16eth|zybo_z7_10|arty_z7_10]
REM Runs "vivado" from PATH ( "Vivado Tcl Shell" ), or the one in %VIVADO%, e.g.
REM   set VIVADO=D:\Xilinx\Vivado\2024.2\bin\vivado.bat
REM antminer_s9_la16eth: use the same Vivado version as Vitis ( see sw\la16_eth\README.md ).
set BOARD=%1
if "%BOARD%"=="" set BOARD=antminer_s9
if "%VIVADO%"=="" set VIVADO=vivado
cd /d %~dp0
call "%VIVADO%" -mode batch -nojournal -log build_%BOARD%.log -source build.tcl -tclargs %BOARD%
