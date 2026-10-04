# vivado -mode batch -source build_vivado.tcl -tclargs comm|image
# Builds a bitstream, never connects/programs hardware.
set root [file normalize [file join [file dirname [info script]] ..]]
set mode comm
if {[info exists argv] && [llength $argv]} {set mode [lindex $argv 0]}
if {$mode ni {comm image}} {error "Choose comm or image"}
set output [file join $root builds "${mode}_[clock milliseconds]"]
create_project jianli_$mode $output -part xc7a35tfgg484-2
set_property target_language Verilog [current_project]
add_files [glob [file join $root rtl common *.v]]
add_files [glob [file join $root vendor uart *.v]]
if {$mode eq "comm"} {
    add_files [glob [file join $root rtl comm *.v]]
    add_files [file join $root vendor spi SPI_Master.v]
    set top comm_acx750_top
} else {
    add_files [glob [file join $root rtl image *.v]]
    add_files [file join $root vendor jls jls_encoder.v]
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
    set_property -dict [list CONFIG.PRIM_IN_FREQ {50.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
        CONFIG.RESET_TYPE {ACTIVE_HIGH} CONFIG.USE_LOCKED {true}] [get_ips clk_wiz_0]
    generate_target all [get_ips clk_wiz_0]
    set top image_acx750_top
}
add_files -fileset constrs_1 [file join $root constraints acx750.xdc]
add_files -fileset constrs_1 [file join $root constraints ${mode}_io.xdc]
if {$mode eq "image"} {
    # Output clock is resolved after the OOC Clocking Wizard is linked.
    set_property USED_IN_SYNTHESIS false [get_files image_io.xdc]
}
set_property top $top [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation/bitstream failed"}
open_run impl_1
if {[llength [get_pins -hier -filter {NAME =~ *rx_meta_reg/D}]] != 1} {error "Missing UART input synchronizer constraint target"}
report_utilization -file [file join $output utilization.rpt]
report_timing_summary -file [file join $output timing.rpt]
set check_fp [open [file join $output timing.rpt] r]
set timing_text [read $check_fp]
close $check_fp
if {![regexp {There are ([0-9]+) ports with no output delay specified} $timing_text -> missing_outputs] || $missing_outputs != 0} {
    error "Missing output-delay constraints; do not accept this build"
}
report_cdc -file [file join $output cdc.rpt]
report_drc -file [file join $output drc.rpt]
foreach violation [get_drc_violations -quiet] {
    set rule_name [get_property NAME $violation]
    set severity [get_property SEVERITY $violation]
    if {[regexp {REQP-1839|REQP-1840} $rule_name] || $severity in {Error {Critical Warning}}} {
        error "Unresolved implementation DRC: $rule_name ($severity)"
    }
}
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {![llength $setup_paths] || ![llength $hold_paths]} {error "Missing timing paths"}
set wns [get_property SLACK $setup_paths]
set whs [get_property SLACK $hold_paths]
set fp [open [file join $output build_status.txt] w]
puts $fp "top=$top\npart=xc7a35tfgg484-2\nwns_ns=$wns\nwhs_ns=$whs\nboard_tested=false"
close $fp
if {$wns < 0 || $whs < 0} {error "Timing failed: WNS=$wns WHS=$whs"}
puts "PASS_BUILD: $top WNS=$wns WHS=$whs output=$output"
