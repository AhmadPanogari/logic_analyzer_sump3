@echo off
REM JTAG only bring-up of the Antminer S9.
REM Uses xsct ( Vitis / SDK ) if found, else xsdb ( ships with Vivado: <Vivado>\bin\xsdb.bat ).
where xsct >nul 2>nul
if %errorlevel%==0 (
  call xsct "%~dp0s9_jtag_load.tcl" %*
) else (
  call xsdb "%~dp0s9_jtag_load.tcl" %*
)
