#pragma once
// Numerical port of the independent FFE/DFE contract in export_vectors.m,
// derived from reference/full_demo_v26_clt_awgn_fixed_paper.m:
// dfe_lms_pam_fp_core, lms_delta_qacc, q_sat, q_convert_i64_to_i32.
// Plain LMS only. Not a port of the entire communication-system demo.
#include <algorithm>
#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace reference {
using I = int64_t;
inline I sat(I x, unsigned bits) {
    const I limit = I(1) << (bits - 1);
    return std::max(-limit, std::min(limit - 1, x));
}
// MATLAB bitshift(signed_integer,-n): arithmetic shift, including negatives.
inline I floor_shift(I x, unsigned n) {
    const I scale = I(1) << n;
    return x >= 0 ? x / scale : -((-x + scale - 1) / scale);
}
// MATLAB round: halfway cases round away from zero.
inline I round_shift(I x, unsigned n) {
    if (!n) return x;
    const I half = I(1) << (n - 1), scale = I(1) << n;
    return x >= 0 ? (x + half) / scale : -((-x + half) / scale);
}
inline I visible(I accumulator) { return sat(round_shift(accumulator, 8), 16); }
inline I delta(I mu_q16, I error_q12, I input_q12) {
    // Convert exact Q16 mu into Q20; all products in this suite fit int64.
    // Same rounded Q20 delta as lms_delta_qacc(mu_acc,e,x,12,40).
    return sat(round_shift((mu_q16 * 16) * error_q12 * input_q12, 24), 40);
}
struct Row {
    int sample, input, error, lms, enable, mu, w0, w1, w2, b0;
};
struct Result {
    I y;
    std::array<I, 3> weights;
};
class Ffe {
    std::array<I, 3> x_{{0, 0, 0}}, w_, accumulator_;
public:
    explicit Ffe(const Row &r) : w_{{r.w0, r.w1, r.w2}} {
        for (unsigned k = 0; k < 3; ++k) accumulator_[k] = w_[k] * 256;
    }
    Result step(const Row &r) {
        x_ = {{r.input, x_[0], x_[1]}};
        I sum = 0;
        for (unsigned k = 0; k < 3; ++k)
            sum += sat(floor_shift(w_[k] * x_[k], 12), 16);
        const I y = r.enable ? sat(sum, 16) : x_[0];
        if (r.lms) {
            for (unsigned k = 0; k < 3; ++k) {
                accumulator_[k] = sat(accumulator_[k] + delta(r.mu, r.error, x_[k]), 40);
                w_[k] = visible(accumulator_[k]);
            }
        }
        return {y, w_};
    }
};
class Dfe {
    I b_, accumulator_;
public:
    explicit Dfe(const Row &r) : b_(r.b0), accumulator_(I(r.b0) * 256) {}
    Result step(const Row &r) {
        // Input is the already-selected previous decision d_hat[n-1].
        const I y = r.enable ? sat(floor_shift(b_ * r.input, 12), 16) : 0;
        if (r.lms) {
            accumulator_ = sat(accumulator_ - delta(r.mu, r.error, r.input), 40);
            b_ = visible(accumulator_);
        }
        return {y, {{b_, 0, 0}}};
    }
};
inline const std::vector<std::string> &cases() {
    static const std::vector<std::string> list = {
        "fixed_basic", "fixed_saturation", "adapt_small", "adapt_large", "bypass",
        "fixed_random", "adapt_random", "adapt_rounding", "adapt_acc_saturation"};
    return list;
}
inline std::vector<Row> stimulus(const std::string &name, bool ffe) {
    if (std::find(cases().begin(), cases().end(), name) == cases().end())
        throw std::runtime_error("Unknown case: " + name);
    const bool random = name.find("random") != std::string::npos;
    const bool acc_limit = name == "adapt_acc_saturation";
    const bool rounding = name == "adapt_rounding";
    const int count = acc_limit ? 100000 : (random ? 4096 : 128);
    const std::array<int, 11> inputs{{0,4096,-4096,12288,-12288,8191,-8193,1,-1,32767,-32768}};
    const std::array<int, 4> levels{{-12288,-4096,4096,12288}};
    const std::array<int, 7> errors{{1,-1,2048,-2048,8192,-8192,0}};
    uint32_t state = 0x8a5b1234u;
    const auto next = [&state]() { state = state * 1664525u + 1013904223u; return state; };
    std::vector<Row> rows;
    for (int n = 0; n < count; ++n) {
        int input = ffe ? inputs[n % inputs.size()] : levels[n % levels.size()];
        int error = errors[n % errors.size()];
        if (random) {
            const unsigned raw = next() >> 16;
            input = ffe ? (raw < 32768 ? int(raw) : int(raw)-65536) : levels[raw % 4];
            error = int(next() >> 18) - 8192;
        }
        Row row{n,input,error,int(name.find("adapt_") == 0),int(name != "bypass"),
                name == "adapt_large" ? 4096 : 32,1024,3072,-512,2048};
        if (name == "fixed_saturation") {
            row.w0 = 24576; row.w1 = -24576; row.w2 = 24576; row.b0 = 24576;
        }
        if (rounding) {
            // +/- half-visible-LSB crossings and retained sub-LSB residue.
            row.input = ffe ? (n%8 < 4 ? 256 : -256) : (n%2 ? -4096 : 4096);
            row.error = ffe ? 4096 : 1024;
            row.w0 = row.w1 = row.w2 = row.b0 = 0;
        }
        if (acc_limit) {
            // Reach the signed 40-bit accumulator bound, then reverse updates.
            row.mu = 32767; row.input = ffe ? 32767 : 12288;
            row.error = n < count/2 ? 32767 : -32768;
            row.w0 = row.w1 = row.w2 = row.b0 = 0;
        }
        rows.push_back(row);
    }
    return rows;
}
} // namespace reference
