#!/usr/bin/env python3
"""English model diagram: typed interfaces, separate LMS branches and state delays."""
import argparse
import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyArrowPatch, FancyBboxPatch
import numpy as np

from draw_current_model import MODEL, ROOT, read_model_data


def interval(x, digits=6):
    return "[%.*f, %.*f]" % (digits, x[0], digits, x[1])


def audit_interfaces(run, cfg, data):
    with np.load(run / "gaussian_20db_vectors.npz") as archive:
        arrays = {name: archive[name] for name in archive.files}
    scale, acc_scale = 1 << cfg.frac_bits, 1 << cfg.adapt_frac_bits
    n = len(arrays["tx_fx"])
    sample = np.arange(1, n + 1)
    reference = np.r_[np.zeros(cfg.delay, dtype=np.int64), arrays["tx_fx"][:-cfg.delay]]
    desired = np.where(sample <= cfg.train_len, reference, arrays["decisions"] * scale)
    desired[sample <= cfg.delay] = 0
    error = MODEL.q_sat(desired - arrays["y_fx"], cfg.total_bits)
    psi = np.clip(error, -int(cfg.error_clip * scale), int(cfg.error_clip * scale))
    gate = (sample <= cfg.train_len) | (np.abs(error) <= int(cfg.dd_gate_error * scale))
    x = np.column_stack([arrays["rx_fx"], np.r_[0, arrays["rx_fx"][:-1]], np.r_[0, 0, arrays["rx_fx"][:-2]]])
    previous = np.r_[0, arrays["decisions"][:-1]] * scale
    mu_acc = int(MODEL.q_from_real(cfg.mu, cfg.adapt_frac_bits, cfg.adapt_total_bits))
    aw = [0, int(cfg.init_main_tap * acc_scale), 0]
    ab = int(cfg.init_feedback_tap * acc_scale)
    acc_shift = 1 << (cfg.adapt_frac_bits - cfg.frac_bits)
    expected_before = np.vstack([[0, int(cfg.init_main_tap * scale), 0, 0], arrays["tap_after_fx"][:-1]])

    # Replay the two update equations as independent state machines sharing
    # psi/gate. Read OLD coefficient state for sample n; commit NEXT state for n+1.
    for i in range(n):
        visible_before = [MODEL.round_scalar(v / acc_shift) for v in aw + [ab]]
        if visible_before != expected_before[i].tolist():
            raise AssertionError("Coefficient memory timing differs at sample %d" % (i + 1))
        if gate[i]:
            aw_next = []
            for k in range(3):
                delta = MODEL.sat_scalar(MODEL.round_scalar(float(mu_acc) * int(psi[i]) * int(x[i, k]) / (1 << 24)), 40)
                value = MODEL.sat_scalar(aw[k] + delta, 40)
                aw_next.append(min(max(value, int(cfg.w_min * acc_scale)), int(cfg.w_max * acc_scale)))
            delta_b = MODEL.sat_scalar(MODEL.round_scalar(float(mu_acc) * int(psi[i]) * int(previous[i]) / (1 << 24)), 40)
            ab_next = min(max(MODEL.sat_scalar(ab - delta_b, 40), int(cfg.b_min * acc_scale)), int(cfg.b_max * acc_scale))
        else:
            aw_next, ab_next = aw[:], ab
        visible_next = [MODEL.round_scalar(v / acc_shift) for v in aw_next + [ab_next]]
        if visible_next != arrays["tap_after_fx"][i].tolist():
            raise AssertionError("Separate LMS updates differ at sample %d" % (i + 1))
        aw, ab = aw_next, ab_next

    # Conservative FFE bounds: three individually quantized products, wide sum.
    r_fx_bounds = np.array(MODEL.q_from_real(data["theoretical"]["rx"]), dtype=np.int64)
    w_fx_bounds = np.array(MODEL.q_from_real([cfg.w_min, cfg.w_max]), dtype=np.int64)
    products = MODEL.q_mul(w_fx_bounds[:, None], r_fx_bounds[None, :])
    ffe_bounds = [float(3 * products.min() / scale), float(3 * products.max() / scale)]
    data["theoretical"]["ffe_wide_sum"] = ffe_bounds
    data["measured"]["error_raw"] = [float(error.min() / scale), float(error.max() / scale)]
    data["measured"]["psi"] = [float(psi.min() / scale), float(psi.max() / scale)]
    data["split_lms_state_replay_verified"] = True
    data["lms_replayed_samples"] = n
    data["lms_final_accumulator_fx"] = dict(ffe=aw, dfe=ab)

    ports = []

    def port(pid, source, target, signal, dtype, bound, measured="", note=""):
        ports.append(dict(id=pid, source=source, target=target, signal=signal,
                          format=dtype, bound=bound, measured=measured, note=note))

    port("P01", "TX", "ISI / TX alignment / raw monitor", "s[n]", "signed16 F12", "S4={-3,-1,+1,+3}", note="Random PAM-4 symbols, not a PRBS stream.")
    port("P02", "ISI FIR", "Noise adder", "r_clean[n]", "signed16 F12", "[-4.5,+4.5]", interval(data["measured"]["clean"]))
    port("P03", "12 Taus88 + mix/extract", "CLT", "R_j[n], j=1..12", "12 x unsigned12", "Each integer in [0,4095]")
    port("P04", "CLT sum/center/normalize", "Noise scale", "z_unit[n]", "signed16 F12", interval(data["theoretical"]["unit_clt"], 12))
    port("P05", "Noise scale", "Noise adder", "eta[n]", "signed16 F12", interval(data["theoretical"]["scaled_noise"], 12), interval(data["measured"]["noise"]))
    port("P06", "Noise adder", "FFE / raw monitor", "r[n]", "signed16 F12", interval(data["theoretical"]["rx"], 12), interval(data["measured"]["rx"]))
    port("P07", "FFE", "DFE", "f[n]", "wide signed sum, F12 (18 bits suffice for bound)", interval(ffe_bounds, 12), interval(data["measured"]["ffe_wide_sum"]), "No intermediate FFE-sum saturation before the DFE subtraction.")
    port("P08", "DFE subtraction", "Slicer / LMS error comparator C1", "y[n]", "signed16 F12", "Q=[-8,7.999755859375]", interval(data["measured"]["y"]), "LMS compares the current pre-slicer output.")
    port("P09", "Slicer", "Gray labels / decision memory / desired selector", "d_hat[n]", "signed16 F12", "S4")
    port("P10", "Gray labels", "Post-EQ comparator C2", "(d_hat[n], b_hat[n])", "symbol + 2 Gray bits", "S4 x {00,01,11,10}", note="Gray conversion is measurement postprocessing in the Python model.")
    port("P11", "DFE decision z^-1", "DFE feedback / DFE LMS", "d_prev[n]=d_hat[n-1]", "signed16 F12", "S0=S4 union {0}", note="Initialized to zero; used both by the DFE and its LMS branch.")
    port("P12", "TX alignment z^-D", "Training selector / C2", "d_ref[n]=s[n-D]", "signed16 F12", "S0", note="D=1. Startup reference is zero.")
    port("P13", "Training / DD selector", "LMS error comparator C1", "d_des[n]", "signed16 F12", "S0", note="d_ref for n<=3000, d_hat afterwards; zero during startup n<=D.")
    port("P14", "C1", "Clip / gate", "e_raw[n]=satQ(d_des-y)", "signed16 F12", "Q", interval(data["measured"]["error_raw"]))
    port("P15", "Clip / gate", "FFE LMS + DFE LMS", "(psi[n], g[n])", "signed16 F12 + Boolean", "psi in [-2.5,+2.5]; g in {0,1}", interval(data["measured"]["psi"]), "Both update branches use the same current error and gate.")
    port("P16", "FFE sample buffer", "FFE LMS", "x[n]=(r[n],r[n-1],r[n-2])", "3 x signed16 F12", "Each in R", note="Two internal sample delays in the FFE; initial history is zero.")
    port("P17", "FFE LMS update", "FFE coefficient memory", "A_w_next[n]", "3 x signed40 F20", "Each in W=[-1.25,+1.25]", note="Projected next accumulator state.")
    port("P18", "FFE coefficient z^-1", "FFE LMS state input", "A_w[n]=A_w_next[n-1]", "3 x signed40 F20", "Each in W", note="Initial state [0,0.75,0]; not an added error delay.")
    port("P19", "FFE coefficient memory + quantizer", "FFE", "w[n]=Q12(A_w[n])", "3 x signed16 F12", "Each in W")
    port("P20", "DFE LMS update", "DFE coefficient memory", "A_b_next[n]", "signed40 F20", "B=[-0.75,+0.75]")
    port("P21", "DFE coefficient z^-1", "DFE LMS state input", "A_b[n]=A_b_next[n-1]", "signed40 F20", "B", note="Initial state zero; not an added error delay.")
    port("P22", "DFE coefficient memory + quantizer", "DFE", "b0[n]=Q12(A_b[n])", "signed16 F12", "B")
    port("P23", "Post-EQ comparison C2", "Results", "BER / SER / error counts", "ratios + integer counters", "BER,SER in [0,1]; bit errors 0..394000; symbol errors 0..197000", "BER=6/394000; SER=6/197000")
    port("P24", "Raw comparison C0", "Results", "BER_raw / SER_raw", "ratios + integer counters", "BER,SER in [0,1]", "BER_raw=73983/394000", "Compare slice(r[k]) with s[k], D=0, using the same retained TX indices as C2.")
    return data, ports


def render(cfg, data, ports, output):
    plt.rcParams.update({"font.family": "DejaVu Sans", "svg.fonttype": "none", "pdf.fonttype": 42})
    fig, ax = plt.subplots(figsize=(36.6, 25.0))
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)
    ax.set(xlim=(0, 3660), ylim=(0, 2500))
    ax.axis("off")
    ink = dict(tx="#21609b", channel="#b96c13", rx="#237d60", lms="#7547a0", err="#b3424c", monitor="#42657d", gray="#5b6876")
    fill = dict(tx="#edf5fc", channel="#fff5e7", rx="#eef8f2", lms="#f5effb", err="#fff0f1", monitor="#edf4f8", gray="#f4f6f8")

    def text(x, y, label, size=12, color="#243342", align="left", weight="normal", va="center", bg=False):
        return ax.text(x, y, label, fontsize=size, color=color, ha=align, va=va,
                       fontweight=weight, linespacing=1.5, zorder=6,
                       bbox=dict(facecolor="white", edgecolor="none", alpha=0.95, pad=2) if bg else None)

    def frame(x, y, w, h, label, kind):
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size=16", edgecolor=ink[kind],
                                   linewidth=2.0, facecolor="white", zorder=0))
        text(x + 20, y + h - 28, label, 17, ink[kind], weight="bold")

    def box(x, y, w, h, label, lines, kind="gray", size=11, title_size=13):
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0,rounding_size=10", edgecolor=ink[kind],
                                   linewidth=1.4, facecolor=fill[kind], zorder=3))
        text(x + 12, y + h - 23, label, title_size, ink[kind], weight="bold")
        ax.plot([x + 12, x + w - 12], [y + h - 43] * 2, color=ink[kind], linewidth=0.6, alpha=0.4, zorder=4)
        text(x + 12, y + h - 60, "\n".join(lines), size, va="top")

    def arrow(points, kind="rx", dashed=False, label=None, at=None, size=10.5):
        xx, yy = zip(*points)
        ax.plot(xx, yy, color=ink[kind], linewidth=1.5, linestyle=(0, (5, 3)) if dashed else "solid", zorder=1)
        ax.add_patch(FancyArrowPatch(points[-2], points[-1], arrowstyle="-|>", mutation_scale=14,
                                     linewidth=1.5, color=ink[kind], zorder=5))
        if label and at:
            return text(*at, label, size, ink[kind], align="center", bg=True)
        return None

    def dot(x, y, kind):
        ax.add_patch(Circle((x, y), 3, color=ink[kind], zorder=5))

    text(1830, 2450, "PAM-4 MODEL — CHANNEL, RECEIVER AND SEPARATE LMS UPDATE PATHS", 28, align="center", weight="bold")
    text(1830, 2400, "Current Python model | h0=1, h1=0.5 | CLT noise at 20 dB | 200,000 symbols | training=3,000 | reference alignment D=1", 15, align="center")
    text(1830, 2362, "P01–P24 identify interfaces. Output names, formats and bounds appear in blocks; complete port catalogue is exported as CSV/Markdown.", 12, align="center", color=ink["gray"])

    box(40, 1830, 650, 500, "INTERFACE TYPES / RANGE ALIASES", [
        "All amplitudes and coefficient bounds are real values.",
        "Q12 = signed 16-bit, 12 fractional bits (Q4.12).",
        "Q = [−8, +7.999755859375]; LSB=2⁻¹².",
        "S4 = {−3, −1, +1, +3}; S0 = S4 ∪ {0 at startup}.",
        "R = [−5.999755859375, +5.99951171875] (20 dB case).",
        "W = [−1.25,+1.25] for each FFE coefficient.",
        "B = [−0.75,+0.75] for the DFE coefficient.",
        "F20 = signed 40-bit state, 20 fractional bits.",
        "μ_cfg=0.0005; μ_Q=524/2²⁰≈0.000499725342.",
        "Bnd = conservative configuration bound; Obs = frame min/max.",
    ], size=13, title_size=15)
    box(740, 1830, 720, 500, "DELAY / STATE CONVENTIONS", [
        "ISI FIR: one internal previous-TX-symbol memory.",
        "FFE: two internal z⁻¹ memories form r[n−1], r[n−2].",
        "DFE decision z⁻¹: d_prev[n]=d_hat[n−1], initialized to 0.",
        "Each LMS branch has a separate coefficient-state z⁻¹.",
        "A_next[n] is computed AFTER processing symbol n.",
        "The stored state becomes A[n+1] for the next symbol.",
        "Q12(A[n]) supplies the visible filtering coefficients.",
        "TX reference z⁻ᴰ: aligns ground truth for training/C2.",
        "ψ[n], x[n], d_prev[n] use the SAME iteration n.",
        "These are model sample delays; no FPGA clock timing is implied.",
    ], size=13, title_size=15)

    frame(40, 1200, 360, 510, "TRANSMITTER (TX)", "tx")
    frame(430, 790, 1030, 920, "CHANNEL = ISI FIR + CLT NOISE + SCALE + ADDER", "channel")
    frame(1490, 760, 2070, 1580, "RECEIVER (RX) = FFE → DFE → SLICER → GRAY LABELS + ADAPTATION", "rx")
    frame(430, 80, 3130, 580, "MEASUREMENT / TX REFERENCE — C0 RAW BASELINE AND C2 POST-EQ BER/SER", "monitor")

    box(70, 1300, 300, 280, "RANDOM PAM-4 SOURCE", [
        "OUT P01: s[n] ∈ S4, Q12",
        "Uniform random symbol stream",
        "Gray labels for measurement:",
        "−3→00; −1→01; +1→11; +3→10",
        "Integer levels: ±4096, ±12288",
        "200,000 symbols / frame",
    ], "tx", size=10.8)
    box(470, 1300, 370, 280, "ISI FIR / FIRST POSTCURSOR", [
        "r_clean[n] = s[n] + 0.5s[n−1]",
        "h0=1; h1=0.5",
        "Internal z⁻¹ stores s[n−1] (startup 0).",
        "OUT P02: r_clean[n], Q12",
        "Bnd: [−4.5,+4.5]",
        "Obs: [−4.5,+4.5]",
    ], "channel")
    box(1090, 1300, 320, 280, "NOISE ADDER", [
        "Inputs: P02 r_clean, P05 η",
        "r[n] = satQ(r_clean[n] + η[n])",
        "OUT P06: r[n], Q12, range R",
        "Bnd: [−5.999756,+5.999512]",
        "Obs: " + interval(data["measured"]["rx"], 4),
    ], "channel", size=10.8)
    arrow([(370, 1440), (470, 1440)], "tx", label="P01 s[n]\nQ12 / S4", at=(420, 1488), size=10)
    arrow([(840, 1440), (1090, 1440)], "channel", label="P02 r_clean[n]\nQ12 / [−4.5,+4.5]", at=(965, 1488))
    rx_input_label = arrow([(1410, 1440), (1580, 1440)], "channel", label="P06 r[n]\nQ12 / R", at=(1495, 1488))

    box(470, 880, 280, 260, "12 × TAUS88 + BIT MIX", [
        "32-bit PRNG words per lane",
        "Mix + extract 12-bit windows",
        "OUT P03: (R1,…,R12)",
        "12 × unsigned 12-bit",
        "Each Rj ∈ [0,4095] (integer)",
    ], "channel", size=10.5)
    box(800, 880, 260, 260, "CLT / NORMALIZE", [
        "S=ΣRj ∈ [0,49140]",
        "c=S−24570",
        "OUT P04: z_unit=c/4096",
        "Q12; Bnd: ±5.99853515625",
        "Mean≈0; std≈1",
    ], "channel", size=10.5)
    box(1110, 880, 300, 260, "NOISE SCALE / 20 dB", [
        "σ_float=%.10f" % data["sigma_float"],
        "σ_Q12=1024/4096=0.25",
        "OUT P05: η=qmul(σ_Q12,z_unit)",
        "Q12; Bnd: [−1.499756,+1.499512]",
        "Obs: " + interval(data["measured"]["noise"], 4),
    ], "channel", size=10)
    arrow([(750, 1010), (800, 1010)], "channel", label="P03", at=(775, 1040))
    arrow([(1060, 1010), (1110, 1010)], "channel", label="P04", at=(1085, 1040))
    arrow([(1260, 1140), (1260, 1300)], "channel", label="P05 η[n]\nQ12 / [−1.499756,+1.499512]", at=(1280, 1218), size=9.5)

    box(1580, 1300, 340, 280, "FFE / 3 TAPS", [
        "Inputs: P06 r[n], P19 w[n]",
        "x[n]=(r[n],r[n−1],r[n−2])",
        "Two internal z⁻¹ sample memories",
        "f[n]=Σ qmul(wk,xk), k=0..2",
        "OUT P07 f[n]: wide signed F12",
        "Bnd: " + interval(data["theoretical"]["ffe_wide_sum"], 6),
        "Obs: " + interval(data["measured"]["ffe_wide_sum"], 4),
        "P16 x[n] to FFE LMS: 3 × Q12 / R",
    ], "rx", size=10.5)
    box(2180, 1300, 340, 280, "DFE / 1 TAP + SUBTRACT", [
        "Inputs: P07 f, P11 d_prev, P22 b0",
        "v[n]=qmul(b0[n],d_prev[n])",
        "Feedback v Bnd: [−2.25,+2.25]",
        "y[n]=satQ(f[n]−v[n])",
        "OUT P08 y[n]: Q12 / Q",
        "Obs: " + interval(data["measured"]["y"], 4),
    ], "rx", size=10.7)
    box(2730, 1300, 320, 280, "PAM-4 SLICER", [
        "Input P08: pre-slicer y[n]",
        "Thresholds: −2, 0, +2",
        "Exact threshold → lower level",
        "OUT P09 d_hat[n]: Q12 / S4",
        "Examples: y=0 → −1; y=2 → +1",
    ], "rx", size=10.7)
    box(3240, 1300, 280, 280, "GRAY LABELS", [
        "Symbol → Gray bits",
        "−3/−1/+1/+3 → 00/01/11/10",
        "OUT P10: (d_hat[n], b_hat[n])",
        "S4 × {00,01,11,10}",
        "Measurement postprocessing",
    ], "rx", size=10.5)
    arrow([(1920, 1440), (2180, 1440)], label="P07 f[n] / wide F12\nBnd: [−22.499268,+22.498535]", at=(2050, 1490), size=10)
    arrow([(2520, 1440), (2730, 1440)], label="P08 y[n]\nQ12 / Q", at=(2625, 1490))
    arrow([(3050, 1440), (3240, 1440)], label="P09 d_hat[n]\nQ12 / S4", at=(3145, 1490))

    box(2740, 1000, 300, 150, "z⁻¹ / DECISION MEMORY", [
        "OUT P11: d_prev[n]=d_hat[n−1]",
        "Q12 / S0; initialized to zero",
    ], "rx", size=10.5, title_size=12)
    arrow([(2890, 1300), (2890, 1150)], label="P09 / S4", at=(2960, 1220))
    arrow([(2740, 1075), (2350, 1075), (2350, 1300)], label="P11 d_prev[n]\nQ12 / S0", at=(2500, 1110))
    dot(2640, 1075, "rx")
    arrow([(2640, 1075), (2640, 2040), (2520, 2040)], label="P11 / Q12 / S0", at=(2600, 2070), size=9.5)

    box(1580, 1900, 340, 300, "FFE LMS UPDATE", [
        "Inputs: P16 x, P15 ψ/g, P18 A_w",
        "Δ_w=round_F20(μ_Q ψ x)",
        "A_w_next=P_W(A_w + Δ_w)",
        "g=0 → hold current state",
        "P_W projects each tap to W",
        "OUT P17 A_w_next[n]",
        "3 × signed40 F20 / W",
    ], "lms", size=10.8)
    box(2180, 1900, 340, 300, "DFE LMS UPDATE", [
        "Inputs: P11 d_prev, P15 ψ/g, P21 A_b",
        "Δ_b=round_F20(μ_Q ψ d_prev)",
        "A_b_next=P_B(A_b − Δ_b)",
        "g=0 → hold current state",
        "P_B projects the tap to B",
        "OUT P20 A_b_next[n]",
        "signed40 F20 / B",
    ], "lms", size=10.5)
    box(1580, 1640, 340, 160, "z⁻¹ / FFE COEFFICIENT STATE", [
        "P18 A_w[n]=A_w_next[n−1] / F20 / W",
        "P19 w[n]=Q12(A_w[n]); 3 × Q12 / W",
        "Initial state: [0,0.75,0]",
    ], "lms", size=10, title_size=12)
    box(2180, 1640, 340, 160, "z⁻¹ / DFE COEFFICIENT STATE", [
        "P21 A_b[n]=A_b_next[n−1] / F20 / B",
        "P22 b0[n]=Q12(A_b[n]); Q12 / B",
        "Initial state: 0",
    ], "lms", size=10, title_size=12)
    arrow([(1750, 1900), (1750, 1800)], "lms", dashed=True, label="P17 / F20 / W", at=(1830, 1850), size=9.5)
    arrow([(2350, 1900), (2350, 1800)], "lms", dashed=True, label="P20 / F20 / B", at=(2430, 1850), size=9.5)
    arrow([(1750, 1640), (1750, 1580)], "lms", dashed=True, label="P19 w[n] / W", at=(1830, 1610), size=9.5)
    arrow([(2350, 1640), (2350, 1580)], "lms", dashed=True, label="P22 b0[n] / B", at=(2430, 1610), size=9.5)
    arrow([(1580, 1720), (1550, 1720), (1550, 1980), (1580, 1980)], "lms", dashed=True)
    arrow([(2180, 1720), (2150, 1720), (2150, 1980), (2180, 1980)], "lms", dashed=True)
    arrow([(1580, 1500), (1515, 1500), (1515, 2110), (1580, 2110)], "rx",
          label="P16 x[n]\n3 × Q12 / R", at=(1640, 2250), size=10)
    text(2200, 2250, "TWO COEFFICIENT UPDATE BRANCHES — SAME CURRENT ERROR AND GATE", 12, ink["lms"], align="center", weight="bold")

    box(2730, 2020, 330, 180, "TRAINING / DD SELECTOR", [
        "P12 d_ref during n≤3000",
        "P09 d_hat after n>3000",
        "OUT P13 d_des[n]: Q12 / S0",
        "Startup n≤D: d_des=0",
    ], "err", size=10.5, title_size=12)
    box(3150, 2020, 370, 180, "C1 / LMS ERROR COMPARISON", [
        "e_raw[n]=satQ(d_des[n]−y[n])",
        "Inputs: P13 desired; P08 y (pre-slicer)",
        "OUT P14 e_raw: Q12 / Q",
        "This comparison drives adaptation.",
    ], "err", size=10.5, title_size=12)
    box(2850, 1760, 670, 210, "SHARED ROBUST ERROR / UPDATE CONTROL", [
        "ψ[n]=clip(e_raw[n],−2.5,+2.5); OUT P15 ψ: Q12 / [−2.5,+2.5]",
        "g[n]=1 in training; in DD g=(|e_raw[n]|≤1.5); OUT P15 g∈{0,1}",
        "Both LMS branches use this same ψ[n] and g[n].",
        "No extra error-path z⁻¹ is inserted.",
    ], "err", size=11.2, title_size=13)
    arrow([(3060, 2110), (3150, 2110)], "err", label="P13", at=(3105, 2140))
    arrow([(3335, 2020), (3335, 1970)], "err", label="P14", at=(3390, 1995))
    dot(2630, 1440, "err")
    arrow([(2630, 1440), (2630, 1690), (3540, 1690), (3540, 2100), (3520, 2100)], "err",
          label="P08 y[n] / Q12 / Q — tap BEFORE the slicer", at=(3135, 1707), size=10)
    dot(3140, 1440, "rx")
    arrow([(3140, 1440), (3140, 1990), (2895, 1990), (2895, 2020)], "rx",
          label="P09 d_hat[n] / S4", at=(3070, 2000), size=9.5)
    arrow([(2850, 1865), (2670, 1865), (2670, 2110), (2520, 2110)], "err", dashed=True,
          label="P15 ψ / g", at=(2605, 2140), size=9.5)
    dot(2670, 2110, "err")
    arrow([(2670, 2110), (2670, 2280), (1980, 2280), (1980, 2110), (1920, 2110)], "err", dashed=True,
          label="P15 ψ[n] / g[n]", at=(2080, 2290), size=10)

    box(500, 300, 380, 180, "z⁻ᴰ / TX REFERENCE ALIGNMENT", [
        "Input P01 s[n]; D=1",
        "OUT P12 d_ref[n]=s[n−D]",
        "Q12 / S0; startup reference=0",
        "Used by training selector and C2",
    ], "tx", size=11, title_size=12)
    arrow([(220, 1300), (220, 390), (500, 390)], "tx", dashed=True,
          label="P01 s[n] / Q12 / S4", at=(365, 420), size=10.5)
    dot(220, 600, "tx")
    arrow([(220, 600), (1480, 600), (1480, 395), (1580, 395)], "tx", dashed=True,
          label="P01 original s[n] — no alignment delay for C0", at=(1030, 580), size=11)
    dot(880, 390, "tx")
    arrow([(880, 390), (920, 390), (920, 190), (3050, 190), (3050, 240)], "tx", dashed=True,
          label="P12 aligned d_ref[n]=s[n−1] / Q12 / S0", at=(1920, 170), size=11)
    arrow([(880, 390), (900, 390), (900, 740), (3580, 740), (3580, 2320), (2820, 2320), (2820, 2200)], "tx", dashed=True,
          label="P12 aligned TX reference → training input", at=(3180, 2335), size=10.5)

    box(1580, 240, 600, 340, "C0 / RAW-RX BASELINE COMPARISON", [
        "Inputs: P06 r[k] and P01 original s[k]",
        "raw_decision[k]=slicer(r[k]); alignment D=0",
        "SER: raw_decision[k] versus s[k]",
        "BER: Gray(raw_decision[k]) XOR Gray(s[k])",
        "Retain the same TX indices as post-EQ C2.",
        "OUT P24: BER_raw,SER_raw ∈ [0,1]",
        "Measured: 73,983 bit errors / 394,000 bits",
        "BER_raw=0.18777411; SER_raw=0.37554822",
    ], "monitor", size=12, title_size=14)
    dot(1500, 1440, "channel")
    arrow([(1500, 1440), (1500, 700), (1870, 700), (1870, 580)], "channel",
          label="P06 r[n] — raw comparison tap", at=(1840, 715), size=11)
    box(2890, 240, 630, 340, "C2 / POST-EQ BER AND SER COMPARISON", [
        "Inputs: P10 (d_hat[n],b_hat[n]); P12 d_ref[n]",
        "SER: d_hat[n] versus d_ref[n]=s[n−D]",
        "BER: b_hat[n] XOR Gray(d_ref[n])",
        "Skip EQ output n≤3000 → 197,000 symbols / 394,000 bits",
        "OUT P23: BER,SER ∈ [0,1]; integer error counters",
        "Bit counter: 0..394,000; symbol counter: 0..197,000",
        "Measured: BER=6/394000=1.52284×10⁻⁵",
        "Measured: SER=6/197000=3.04569×10⁻⁵",
    ], "monitor", size=12, title_size=14)
    arrow([(3380, 1300), (3380, 670), (3240, 670), (3240, 580)], "monitor",
          label="P10 recovered symbol + Gray bits\nS4 × {00,01,11,10}", at=(3110, 690), size=10.5)

    before_snapshot = set(ax.get_children())
    box(1580, 820, 600, 300, "RUN SNAPSHOT / AFTER UPDATE n=200000", [], "gray", title_size=13)
    for xx, title in [(1600, "Tap"), (1690, "Real value"), (1940, "Q12 int"), (2060, "Hex")]:
        text(xx, 1040, title, 11.5, weight="bold")
    for k, row in enumerate(data["final_taps"]):
        yy = 1000 - 35 * k
        for xx, label in [(1600, row["tap"]), (1690, "%+.12f" % row["final_after_update_real"]),
                          (1940, str(row["final_after_update_fx"])), (2060, row["final_after_update_hex"])]:
            text(xx, yy, label, 11)
    text(1600, 850, "These coefficients are available for sample n=200001.", 11, color=ink["gray"])
    snapshot_artists = set(ax.get_children()) - before_snapshot
    text(1830, 45, "qmul: integer product → signed >>12 → sat16. FFE products are quantized separately, then summed wide. Colored dots are junctions; unmarked crossings are separate signals.", 12, align="center", color=ink["gray"])
    text(1830, 15, "Numerical model unchanged. Two LMS branches are an explicit decomposition of its existing update equations; coefficient memories model the next-symbol state, not a delayed-error LMS variant.", 11, align="center", color=ink["gray"])

    output.mkdir(parents=True, exist_ok=True)
    for suffix in ["png", "svg", "pdf"]:
        fig.savefig(output / ("pam4_current_model_en." + suffix), dpi=140, facecolor="white")
    # Include the DFE decision memory as well as both LMS coefficient memories.
    # Hide the nonfunctional snapshot note in this crop so it is not cut in half.
    for artist in snapshot_artists:
        artist.set_visible(False)
    rx_input_label.set_visible(False)
    text(1535, 1488, "P06 r[n]\nQ12 / R", 8.5, ink["channel"], align="center", bg=True)
    box(1580, 980, 600, 230, "DETAIL RANGE LEGEND", [
        "W=[−1.25,+1.25]; B=[−0.75,+0.75]",
        "Q12: signed16/F12; Q=[−8,+7.999755859375]",
        "R=[−5.999755859375,+5.99951171875]",
        "S4={−3,−1,+1,+3}; S0=S4 ∪ {0 at startup}",
        "F20: signed40/F20; ψ∈[−2.5,+2.5], g∈{0,1}",
    ], "gray", size=11, title_size=13)
    ax.set_xlim(1490, 3560)
    ax.set_ylim(960, 2340)
    fig.set_size_inches(20.7, 13.8)
    for suffix in ["png", "svg", "pdf"]:
        fig.savefig(output / ("pam4_lms_detail_en." + suffix), dpi=160, facecolor="white")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, default=ROOT / "10_sim/python_v26_signals")
    parser.add_argument("--output", type=Path, default=ROOT / "99_doc/figures")
    args = parser.parse_args()
    cfg, data = read_model_data(args.run)
    data, ports = audit_interfaces(args.run, cfg, data)
    render(cfg, data, ports, args.output)
    with (args.output / "pam4_model_interfaces_en.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(ports[0]))
        writer.writeheader()
        writer.writerows(ports)
    with (args.output / "pam4_model_interfaces_en.json").open("w", encoding="utf-8") as stream:
        json.dump(dict(data=data, ports=ports), stream, indent=2, ensure_ascii=False)
    with (args.output / "pam4_model_interfaces_en.md").open("w", encoding="utf-8") as stream:
        stream.write("# Current model signal interfaces\n\n")
        stream.write("Amplitudes/coefficient bounds below are real values; URNG words and counters are integers.\n\n")
        stream.write("Q12 = signed16 with 12 fractional bits; Q = [-8,7.999755859375].\n\n")
        stream.write("S4 = {-3,-1,+1,+3}; S0 = S4 plus zero during memory startup.\n\n")
        stream.write("R = [-5.999755859375,+5.99951171875]; W = [-1.25,+1.25]; B = [-0.75,+0.75].\n\n")
        stream.write("F20 = signed40 coefficient accumulator with 20 fractional bits, projected to W or B.\n\n")
        stream.write("| Port | From | To | Signal | Format | Bound | Measured | Notes |\n")
        stream.write("| --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for row in ports:
            stream.write("| " + " | ".join(str(value).replace("|", "\\|") for value in row.values()) + " |\n")
        stream.write("\nVerified: independent FFE/DFE state-update replay matches all 200000 saved per-sample coefficient states.\n")
    print("Rendered English diagram and LMS detail; %d ports; %d split-LMS state updates verified." % (len(ports), data["lms_replayed_samples"]))


if __name__ == "__main__":
    main()
