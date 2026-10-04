# From local ACX750_CB_PIN.xdc and UART examples, not a Basys3 pin map.
set_property PACKAGE_PIN W19 [get_ports clk]
set_property PACKAGE_PIN D21 [get_ports reset_n]
set_property PACKAGE_PIN L21 [get_ports uart_rx]
set_property PACKAGE_PIN M21 [get_ports uart_tx]
set_property PACKAGE_PIN U22 [get_ports {led[0]}]
set_property PACKAGE_PIN V22 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk reset_n uart_rx uart_tx led[*]}]
# Primary clock is defined by comm_io.xdc or by the image Clocking Wizard.
# RX is asynchronous. Except only the first synchronizer D, never downstream
# synchronous logic. The two stages remain timed normally against each other.
set_false_path -from [get_ports uart_rx] -to [get_pins -hier -filter {NAME =~ *rx_meta_reg/D}]
# Mode-specific output delay is in comm_io.xdc or image_io.xdc.
# Board reset is asynchronous by design; release is synchronized per domain.
set_false_path -from [get_ports reset_n]
# ACX750-CORE.pdf page 4: CFGBVS and bank-0 VCCO connect to VCC3P3.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
