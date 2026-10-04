# Clock name comes from the generated Clocking Wizard constraints (Vivado 2018.3).
set_output_delay -clock [get_clocks clk_out1_clk_wiz_0] 0.000 [get_ports uart_tx]
set_output_delay -clock [get_clocks clk_out1_clk_wiz_0] 0.000 [get_ports {led[*]}]
