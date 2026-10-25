#include "Vtb_top.h"
#include "verilated.h"

#include <cstdio>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

namespace {
constexpr unsigned kResetCycles = 10;
constexpr unsigned kRunCycles = 100;
constexpr vluint64_t kHalfPeriodNs = 5;
vluint64_t sim_time_ns = 0;

#if VM_TRACE
VerilatedVcdC* waveform = nullptr;
#endif

void evaluate_and_dump(Vtb_top& tb)
{
    tb.eval();
#if VM_TRACE
    if (waveform) waveform->dump(sim_time_ns);
#endif
}

void tick(Vtb_top& tb)
{
    tb.i_clk = 0;
    evaluate_and_dump(tb);
    sim_time_ns += kHalfPeriodNs;

    tb.i_clk = 1;
    evaluate_and_dump(tb);
    sim_time_ns += kHalfPeriodNs;

    tb.i_clk = 0;
    tb.eval();
}

void initialize_inputs(Vtb_top& tb)
{
    tb.i_clk = 0;
    tb.i_rst_n = 0;
    tb.i_r = 16;
    tb.i_tx_ref = 1;
    tb.i_cfg_ffe0 = 0x0000;
    tb.i_cfg_ffe1 = 0x0c00;
    tb.i_cfg_ffe2 = 0x0000;
    tb.i_cfg_dfe0 = 0x0000;
    tb.i_cfg_load = 0;
    tb.i_adapt_en = 0;
    tb.i_ffe_bypass = 0;
    tb.i_dfe_bypass = 0;
    tb.eval();
}
}  // namespace

double sc_time_stamp()
{
    return static_cast<double>(sim_time_ns);
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
#if VM_TRACE
    Verilated::traceEverOn(true);
#endif
    Vtb_top tb;
#if VM_TRACE
    VerilatedVcdC trace;
    tb.trace(&trace, 99);
    trace.set_time_unit("1ns");
    trace.set_time_resolution("1ns");
    trace.open("rx_clock_reset.vcd");
    waveform = &trace;
#endif
    initialize_inputs(tb);

    unsigned reset_cycles = 0;
    for (; reset_cycles < kResetCycles && !Verilated::gotFinish(); ++reset_cycles) {
        tick(tb);
    }

    unsigned run_cycles = 0;
    const bool reset_completed = reset_cycles == kResetCycles && !Verilated::gotFinish();
    if (reset_completed) {
        tb.i_rst_n = 1;
        tb.eval();

        for (; run_cycles < kRunCycles && !Verilated::gotFinish(); ++run_cycles) {
            // Add stimulus here.
            tick(tb);
            // Add output checks here.
        }
    }

    tb.final();
#if VM_TRACE
    trace.dump(sim_time_ns);
    trace.close();
    waveform = nullptr;
#endif
    if (!reset_completed || run_cycles != kRunCycles) return 1;
    std::printf("rx: clock/reset sequence completed; functional checker not connected.\n");
    return 0;
}
