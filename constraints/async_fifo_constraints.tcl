# Optional study helper for an instantiated async_fifo in a real dual-clock top.
# Do NOT combine this with a broad asynchronous clock group: it would override
# the Gray-bus maximum-delay bound. Adjust paths after inspecting synthesized cells.
proc constrain_gray_fifo {instance wr_period_ns rd_period_ns} {
    foreach {src dst period} [list wgray rgray_w1 $wr_period_ns rgray wgray_r1 $rd_period_ns] {
        set from_cells [get_cells -hier -filter "NAME =~ ${instance}/${src}_reg*"]
        set to_cells [get_cells -hier -filter "NAME =~ ${instance}/${dst}_reg*"]
        if {![llength $from_cells] || ![llength $to_cells]} {error "Gray registers not found for $instance"}
        set_max_delay -datapath_only $period -from $from_cells -to $to_cells
        set_bus_skew $period -from $from_cells -to $to_cells
    }
}
