## Extra pins of the antminer_s9_la16 variant ( read after antminer_s9.xdc ), same as _ols.
## UART baud select jumpers on J9 ( pull-ups inside, jumper to GND = 1 ):
##   J9 pin 11 ( T17 ) -> bridge to J9 pin 9  ( GND )
##   J9 pin 12 ( R18 ) -> bridge to J9 pin 10 ( GND )
##   none = 921600, pin 11 = 460800, pin 12 = 230400, both = 115200
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {baud_sel_n[0]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {baud_sel_n[1]}]
set_false_path -from [get_ports {baud_sel_n[*]}]
