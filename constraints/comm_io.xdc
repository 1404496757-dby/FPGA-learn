# An explicit 0 ns external budget bounds transmitter-to-pin paths.
create_clock -name board_clk_50m -period 20.000 [get_ports clk]
# UART is asynchronous: this is not a claim of an external synchronous receiver.
set_output_delay -clock [get_clocks board_clk_50m] 0.000 [get_ports uart_tx]
set_output_delay -clock [get_clocks board_clk_50m] 0.000 [get_ports {led[*]}]
