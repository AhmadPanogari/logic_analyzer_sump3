## Timing constraints common to all XC7Z010 boards
## 125 MHz PL oscillator. The MMCM output clock (100 MHz) is derived automatically.
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]
set_input_jitter sys_clk 0.200

## All other I/O is asynchronous and goes through 2-FF synchronizers in la_top.v
set_false_path -from [get_ports {probe[*]}]
set_false_path -from [get_ports {btn[*]}]
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports bd_rx]
set_false_path -to   [get_ports bd_tx]
set_false_path -to   [get_ports {led[*]}]
