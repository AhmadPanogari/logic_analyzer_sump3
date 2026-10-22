## Digilent Arty Z7-10  ( XC7Z010-1CLG400C )
## Pins from Digilent Arty-Z7-10-Master.xdc. Verify against your board revision.
##
##  probe[7:0]  -> Pmod JA   ( JA1..JA4 = probe0..3, JA7..JA10 = probe4..7 )
##  probe[15:8] -> Pmod JB   ( JB1..JB4 = probe8..11, JB7..JB10 = probe12..15 )
##  UART        -> Arduino header IO0 = bd_rx <- adapter TXD
##                                IO1 = bd_tx -> adapter RXD,  GND = GND
##
## Note: the on-board USB-UART of the Arty Z7 is wired to PS MIO pins and can
## not be used by this PL-only design. Use a 3.3V USB-UART cable.

## 125 MHz clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports sys_clk]

## Switches
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]

## Buttons
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN L20 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]

## LEDs
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## Pmod JA -> probe[7:0]
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[0]}]
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[1]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[2]}]
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[3]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[4]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[5]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[6]}]
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[7]}]

## Pmod JB -> probe[15:8]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[8]}]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[9]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[10]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[11]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[12]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[13]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[14]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports {probe[15]}]

## Arduino / ChipKit header -> MesaBus UART
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports bd_rx]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports bd_tx]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Timing
## 125 MHz PL oscillator. The MMCM output clock (100 MHz) is derived automatically.
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]
set_input_jitter sys_clk 0.200

## All other I/O is asynchronous and goes through 2-FF synchronizers in la_core.v
set_false_path -from [get_ports {probe[*] btn[*] sw[*] bd_rx}]
set_false_path -to   [get_ports {bd_tx led[*]}]
