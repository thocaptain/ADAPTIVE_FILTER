# Package the DUT from the current RTL in 00_src, with top_wrapper as the IP top.
# Can be sourced from the Vivado Tcl Console while a project/BD is open.
# Packaging runs in a separate Vivado batch process; the open project is untouched.
set eq_gen_dir [file dirname [file normalize [info script]]]
set eq_gen_root [file normalize [file join $eq_gen_dir ..]]
set eq_gen_stamp [clock seconds]
set eq_gen_out [file join $eq_gen_dir build dut_ip_current_$eq_gen_stamp]
set eq_gen_suffix 0
while {[file exists [file join $eq_gen_out ip]] ||
       [file exists [file join $eq_gen_out package_project]] ||
       [file exists [file join $eq_gen_out package.log]]} {
    incr eq_gen_suffix
    set eq_gen_out [file join $eq_gen_dir build dut_ip_current_${eq_gen_stamp}_$eq_gen_suffix]
}
set eq_gen_defaults [list \
    -out $eq_gen_out \
    -clock_hz 20000000 \
    -version 1.6 \
    -rtl_dir [file join $eq_gen_root 00_src]]
set eq_project_open [expr {[llength [get_projects -quiet]] > 0}]
if {$eq_project_open} {
    # In the GUI, argv may contain stale options from unrelated Tcl commands.
    set eq_gen_args $eq_gen_defaults
} else {
    set eq_gen_args [concat $eq_gen_defaults $argv]
}
set eq_package_script [file join $eq_gen_dir package_dut.tcl]

if {$eq_project_open} {
    set eq_out ""
    foreach {key value} $eq_gen_args {
        if {$key eq "-out"} { set eq_out [file normalize $value] }
    }
    if {$eq_out eq ""} { error "Missing -out for DUT IP package output" }
    file mkdir $eq_out
    set eq_log [file join $eq_out package.log]
    set eq_command [concat \
        [list [info nameofexecutable] -mode batch -notrace -nojournal \
            -log $eq_log -source $eq_package_script -tclargs] \
        $eq_gen_args]
    puts "INFO: Packaging current 00_src RTL as top_wrapper."
    puts "INFO: Output: $eq_out"
    puts "INFO: Batch log: $eq_log"
    if {[catch {exec {*}$eq_command 2>@1} eq_output]} {
        set eq_message "DUT IP packaging failed. The open project and block design were not changed."
        append eq_message "\nVivado batch output:\n$eq_output"
        if {[file isfile $eq_log]} {
            append eq_message "\nFull log: $eq_log"
        }
        return -code error $eq_message
    }
    puts $eq_output
} else {
    set argv $eq_gen_args
    source $eq_package_script
}
