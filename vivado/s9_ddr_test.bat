@echo off
REM DDR test of the Antminer S9 over JTAG.
REM Uses xsct ( Vitis / SDK ) if found, else xsdb ( ships with Vivado: <Vivado>\bin\xsdb.bat ).
where xsct >nul 2>nul
if %errorlevel%==0 (
  call xsct "%~dp0s9_ddr_test.tcl" %*
) else (
  call xsdb "%~dp0s9_ddr_test.tcl" %*
)
