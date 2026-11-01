# Vivado 2021.1: vivado -mode batch -source 10_sim/axi/run.tcl
# Optional -tclargs C:/fpga_build/axi_test selects the output directory.
proc eq_axi_tool {command args} {
    if {$::tcl_platform(platform) eq "windows"} { append command .bat }
    set executable [auto_execok $command]
    if {$executable eq ""} { error "Missing $command; use a Vivado command environment" }
    exec {*}$executable {*}$args >@stdout 2>@stderr
}
proc eq_axi_test {script_dir arguments} {
    if {[llength $arguments] > 1} { error "Expected at most one build-directory argument" }
    if {[llength $arguments]} {
        set build [file normalize [lindex $arguments 0]]
    } elseif {[info exists ::env(TEMP)]} {
        set build [file join $::env(TEMP) adaptive_eq_axi_tests]
    } else {
        set build /tmp/adaptive_eq_axi_tests
    }
    set root [file normalize [file join $script_dir ../..]]
    set sources {}
    foreach relative {
        top_wrapper.sv axi/adaptive_eq_axi_regs.sv top.sv tx/tx_top.sv
        channel/channel_top.sv rx/rx_top.sv rx/rx_ffe.sv rx/rx_dfe.sv rx/rx_monitor.sv
    } { lappend sources [file join $root 00_src $relative] }
    file mkdir $build
    cd $build
    eq_axi_tool xvlog -sv {*}$sources
    foreach width {8 12} {
        if {$width == 12} {
            eq_axi_tool xvlog -sv -d EQ_AXI_ADDR12 [file join $script_dir tb_top_wrapper.sv]
        } else {
            eq_axi_tool xvlog -sv [file join $script_dir tb_top_wrapper.sv]
        }
        set snapshot eq_axi_$width
        eq_axi_tool xelab work.tb_top_wrapper -s $snapshot -debug typical
        eq_axi_tool xsim $snapshot -runall -onfinish quit -log $snapshot.log
        set fd [open $snapshot.log r]
        set log [read $fd]
        close $fd
        if {[string first "PASS: real top_wrapper AXI integration, address width $width" $log] < 0} {
            error "No PASS for address width $width; inspect $build/$snapshot.log"
        }
    }
    puts "INFO: Both AXI integration tests passed. Logs: $build"
}
set eq_axi_script_dir [file dirname [file normalize [info script]]]
set eq_axi_original_cwd [pwd]
set eq_axi_result [catch {eq_axi_test $eq_axi_script_dir $::argv} eq_axi_message eq_axi_options]
cd $eq_axi_original_cwd
if {$eq_axi_result} { return -options $eq_axi_options $eq_axi_message }
