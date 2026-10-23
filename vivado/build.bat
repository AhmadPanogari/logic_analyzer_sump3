@echo off
REM Usage: build.bat [antminer_s9|antminer_s9_ols|antminer_s9_la16|antminer_s9_la16ddr|antminer_s9_la16eth|zybo_z7_10|arty_z7_10]
REM Runs "vivado" from PATH ( "Vivado Tcl Shell" ), or the one in %VIVADO%, e.g.
REM   set VIVADO=D:\Xilinx\Vivado\2024.2\bin\vivado.bat
REM antminer_s9_la16eth: use the same Vivado version as Vitis ( see sw\la16_eth\README.md ).
REM setlocal and the name TARGET: a variable BOARD ( = board, Windows names
REM ignore case ) left in this cmd window makes the Vitis device tree
REM generator look for a board file "<BOARD>.dtsi" and fail.
setlocal
set TARGET=%1
if "%TARGET%"=="" set TARGET=antminer_s9
if "%VIVADO%"=="" set VIVADO=vivado
cd /d %~dp0
call "%VIVADO%" -mode batch -nojournal -log build_%TARGET%.log -source build.tcl -tclargs %TARGET%
endlocal
