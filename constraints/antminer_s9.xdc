## Bitmain Antminer S9 control board  ( AntMiner ControlBoard XC7010, XC7Z010-1CLG400 )
## Top level: rtl/la_top_s9.v
##
## Pins taken from the board schematic as documented by the Ardzy project
## ( https://github.com/chrysovalantischryso/ardzy , docs/03_Pins_Plan.html ).
## Banks 34 and 35 are 3.3 V. No 5 V signals on any pin!
##
## 18-pin hash-board connectors J1..J9 ( 2 x 9 ), same layout on all:
##   1,2,9,10,13,14 = GND   3/4 = I2C SDA/SCL ( 1k pull-ups, not used )
##   5 = IO0   11 = IO1   12 = IO2   15 = IO3   16 = 3.3 V out
##   6,7,8 = address straps ( do not use )   18 = ARM EN ( 2.5 V )   17 = NC
##
##   J1 : 11 = bd_tx -> adapter RXD,  12 = bd_rx <- adapter TXD,  1 = GND
##   J5 : 5,11,12,15 = D0..D3
##   J6 : 5,11,12,15 = D4..D7
##   J7 : 5,11,12,15 = D8..D11
##   J8 : 5,11,12,15 = D12..D15
##   J9 : 5 = tp_sel_n ( open = probes, bridge to pin 1 GND = test pattern )
##
## The 100 MHz clock is FCLK_CLK0 from the PS. Its create_clock comes from the
## processing_system7 IP constraints.

## MesaBus UART on J1
set_property -dict { PACKAGE_PIN T12 IOSTANDARD LVCMOS33 } [get_ports bd_tx]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports bd_rx]

## Probes J5
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[0]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[1]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[2]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[3]}]
## Probes J6
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[4]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[5]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[6]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[7]}]
## Probes J7
set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[8]}]
set_property -dict { PACKAGE_PIN V20 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[9]}]
set_property -dict { PACKAGE_PIN W20 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[10]}]
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[11]}]
## Probes J8
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[12]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[13]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[14]}]
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[15]}]

## Test pattern select jumper J9 pin 5
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports tp_sel_n]

## On-board LEDs D5..D8, active low
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports {led_n[0]}]
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports {led_n[1]}]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {led_n[2]}]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports {led_n[3]}]

## Timing : all PL I/O is asynchronous ( 2-FF synchronizers in la_core.v )
set_false_path -from [get_ports {probe[*] tp_sel_n bd_rx}]
set_false_path -to   [get_ports {bd_tx led_n[*]}]
