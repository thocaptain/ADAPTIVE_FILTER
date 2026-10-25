#include "Vtb_top.h"
#include "verilated.h"

#include <cstdio>
#include <cerrno>
#include <cstdlib>
#include <cstring>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

namespace {
constexpr unsigned kResetCycles = 10;
constexpr unsigned kRunCycles = 100;
constexpr vluint64_t kHalfPeriodNs = 5;
vluint64_t sim_time_ns = 0;

struct ChannelConfig {
    unsigned noise_en = 1;
    unsigned snr_db = 20;
};

bool parse_unsigned(const char* text, unsigned maximum, unsigned& result)
{
    if (!*text) return false;
    for (const char* c = text; *c; ++c) {
        if (*c < '0' || *c > '9') return false;
    }
    errno = 0;
    char* end = nullptr;
    const auto value = std::strtoul(text, &end, 10);
    if (errno || !end || *end || value > maximum) return false;
    result = static_cast<unsigned>(value);
    return true;
}

bool parse_config(int argc, char** argv, ChannelConfig& config)
{
    for (int i = 1; i < argc; ++i) {
        if (std::strncmp(argv[i], "+noise_en=", 10) == 0) {
            if (!parse_unsigned(argv[i] + 10, 1, config.noise_en)) {
                std::fprintf(stderr, "channel: +noise_en must be 0 or 1.\n");
                return false;
            }
        } else if (std::strncmp(argv[i], "+snr_db=", 8) == 0) {
            if (!parse_unsigned(argv[i] + 8, 255, config.snr_db)) {
                std::fprintf(stderr, "channel: +snr_db must be an integer in 0..255.\n");
                return false;
            }
        }
    }
    return true;
}

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

void initialize_inputs(Vtb_top& tb, const ChannelConfig& config)
{
    tb.i_clk = 0;
    tb.i_rst_n = 0;
    tb.i_sym = 1;
    tb.i_noise_en = 0;
    tb.i_cfg_snr_db = config.snr_db;
    tb.i_cfg_noise_load = 0;
    tb.eval();
}
}  // namespace

double sc_time_stamp()
{
    return static_cast<double>(sim_time_ns);
}

int main(int argc, char** argv)
{
    ChannelConfig config;
    if (!parse_config(argc, argv, config)) return 1;
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
    trace.open("channel_clock_reset.vcd");
    waveform = &trace;
#endif
    initialize_inputs(tb, config);

    unsigned reset_cycles = 0;
    for (; reset_cycles < kResetCycles && !Verilated::gotFinish(); ++reset_cycles) {
        tick(tb);
    }

    unsigned run_cycles = 0;
    const bool reset_completed = reset_cycles == kResetCycles && !Verilated::gotFinish();
    if (reset_completed) {
        tb.i_rst_n = 1;
        tb.i_cfg_noise_load = 1;
        tick(tb);
        tb.i_cfg_noise_load = 0;
        tb.i_noise_en = config.noise_en;
        std::printf("channel: loaded SNR=%u dB, noise_en=%u.\n", config.snr_db, config.noise_en);
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
    std::printf("channel: clock/reset sequence completed; functional checker not connected.\n");
    return 0;
}
