#!/usr/bin/env python3
"""Draw the current Python PAM-4 model from its config and measured vectors."""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Circle
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("v26_diagram_model", ROOT / "01_bench/full_demo_v26_clt_awgn_fixed_paper.py")
MODEL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODEL
SPEC.loader.exec_module(MODEL)


def value_range(values, scale=1):
    return [float(np.min(values) / scale), float(np.max(values) / scale)]


def read_model_data(run):
    report = json.loads((run / "results.json").read_text())
    taps = json.loads((run / "adaptive_taps_summary.json").read_text())
    cfg = MODEL.Config(**report["config"])
    case = next(case for case in report["cases"] if case["mode"] == "adaptive" and case["variant"] == "robust_proj"
                and case["noise_model"] == "gaussian" and case["use_noise"] and case["snr_db"] == 20)
    arrays = np.load(run / "gaussian_20db_vectors.npz")
    scale = 1 << cfg.frac_bits
    initial = [0] * cfg.nf + [0] * cfg.nb
    initial[min(cfg.nf - 1, cfg.delay)] = int(MODEL.q_from_real(cfg.init_main_tap))
    if cfg.nb:
        initial[cfg.nf] = int(MODEL.q_from_real(cfg.init_feedback_tap))
    before = np.vstack([initial, arrays["tap_after_fx"][:-1]])
    ffe = np.zeros(len(arrays["rx_fx"]), dtype=np.int64)
    for k in range(cfg.nf):
        delayed = arrays["rx_fx"] if not k else np.r_[np.zeros(k, dtype=np.int64), arrays["rx_fx"][:-k]]
        ffe += MODEL.q_mul(before[:, k], delayed, cfg.frac_bits, cfg.total_bits)
    feedback_symbols = np.r_[0, arrays["decisions"][:-1]] * scale
    feedback = MODEL.q_mul(before[:, cfg.nf], feedback_symbols, cfg.frac_bits, cfg.total_bits)
    np.testing.assert_array_equal(MODEL.q_sat(ffe - feedback, cfg.total_bits), arrays["y_fx"])
    center, gain = MODEL.clt_parameters(cfg)
    z_limits = MODEL.q_mul(np.array([-center, center]), gain, cfg.frac_bits, cfg.total_bits)
    noise_limits = MODEL.q_mul(z_limits, case["metrics"]["noise_sigma_fx"], cfg.frac_bits, cfg.total_bits)
    clean_limit_fx = int(MODEL.q_from_real(3 * (1 + abs(cfg.isi))))
    rx_limits = MODEL.q_sat(np.array([-clean_limit_fx, clean_limit_fx]) + noise_limits, cfg.total_bits)
    ranges = dict(
        representation=dict(bits=cfg.total_bits, fractional_bits=cfg.frac_bits,
                            integer_range=[-(1 << (cfg.total_bits - 1)), (1 << (cfg.total_bits - 1)) - 1],
                            real_range=[-8.0, 32767 / scale], lsb=1 / scale),
        configured=dict(ffe_taps=[cfg.w_min, cfg.w_max], dfe_tap=[cfg.b_min, cfg.b_max],
                        error_clip=[-cfg.error_clip, cfg.error_clip], dd_update_error=[-cfg.dd_gate_error, cfg.dd_gate_error],
                        mu=cfg.mu, mu_acc_q20=int(MODEL.q_from_real(cfg.mu, cfg.adapt_frac_bits, cfg.adapt_total_bits)),
                        adaptation_bits=cfg.adapt_total_bits, adaptation_fractional_bits=cfg.adapt_frac_bits),
        theoretical=dict(tx_levels=MODEL.LEVELS.tolist(), clean=[-4.5, 4.5],
                         lane_uniform=[0, (1 << cfg.u_bits) - 1], uniform_sum=[0, 2 * center], centered_sum=[-center, center],
                         unit_clt=value_range(z_limits, scale), scaled_noise=value_range(noise_limits, scale),
                         rx=value_range(rx_limits, scale), dfe_feedback=[-3 * abs(cfg.b_max), 3 * abs(cfg.b_max)]),
        measured=dict(clean=value_range(arrays["clean_fx"], scale), noise=value_range(arrays["noise_fx"], scale),
                      rx=value_range(arrays["rx_fx"], scale), ffe_wide_sum=value_range(ffe, scale),
                      dfe_feedback=value_range(feedback, scale), y=value_range(arrays["y_fx"], scale)),
        sigma_float=case["metrics"]["noise_sigma_float"], sigma_fx=case["metrics"]["noise_sigma_fx"],
        frame_symbols=report["symbols_per_case"], train_samples=cfg.train_len, delay=cfg.delay,
        metrics=case["metrics"]["eq"], final_taps=taps["taps"],
        ffe_feedback_replay_verified=True,
        range_scope="Bounds apply to the Gaussian/CLT 20 dB case; gaussmix is not drawn. Measured ranges use the entire 200000-sample frame.")
    return cfg, ranges


def draw(cfg, data, output):
    plt.rcParams.update({"font.family": "DejaVu Sans", "svg.fonttype": "none", "pdf.fonttype": 42})
    fig, ax = plt.subplots(figsize=(25.8, 16.7))
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)
    ax.set(xlim=(0, 2580), ylim=(0, 1670))
    ax.axis("off")
    colors = dict(blue="#2466a3", orange="#bf761b", green="#258365", purple="#8051a2", gray="#607181")
    fills = dict(blue="#edf5fc", orange="#fff5e7", green="#edf8f2", purple="#f5effa", gray="#f3f5f7")

    def text(x, y, content, size=12, color="#243344", align="left", weight="normal", va="center"):
        return ax.text(x, y, content, fontsize=size, color=color, ha=align, va=va, fontweight=weight, linespacing=1.6)

    def box(x, y, width, height, title, lines, kind="gray", size=11):
        ax.add_patch(FancyBboxPatch((x, y), width, height, boxstyle="round,pad=0,rounding_size=12",
                                   linewidth=1.6, edgecolor=colors[kind], facecolor=fills[kind], zorder=2))
        text(x + 15, y + height - 28, title, 13, colors[kind], weight="bold")
        ax.plot([x + 15, x + width - 15], [y + height - 52] * 2, color=colors[kind], linewidth=0.6, alpha=0.4, zorder=3)
        text(x + 15, y + height - 73, "\n".join(lines), size, va="top")

    def path(points, kind="gray", dashed=False, label=None, label_at=None):
        xs, ys = zip(*points)
        ax.plot(xs, ys, color=colors[kind], linewidth=1.5, linestyle=(0, (5, 3)) if dashed else "solid", zorder=1)
        ax.add_patch(FancyArrowPatch(points[-2], points[-1], arrowstyle="-|>", mutation_scale=15,
                                     color=colors[kind], linewidth=1.5, linestyle="solid", zorder=3))
        if label and label_at:
            text(*label_at, label, 10, colors[kind], align="center")

    def limits(values, precision=4):
        return "[%.*f, %.*f]" % (precision, values[0], precision, values[1])

    text(1290, 1620, "MÔ HÌNH PAM-4 HIỆN TẠI — TX / KÊNH / RX / LMS", 24, align="center", weight="bold")
    text(1290, 1570, "Luồng RX: FFE → DFE → Slicer  |  LMS phía trên DFE, cập nhật cả FFE và DFE  |  SNR=20 dB, h0=1, h1=0.5", 14, align="center")
    text(1290, 1520, "BIÊN: theo cấu hình/định dạng  •  ĐO: min/max trên toàn khung 200.000 sample  •  Nét đứt tím: nhánh thích nghi LMS", 11, align="center", color=colors["gray"])

    box(40, 815, 290, 300, "NGUỒN PHÁT TX", [
        "Symbol ngẫu nhiên s[n]",
        "s ∈ {−3, −1, +1, +3}",
        "Gray: 00 / 01 / 11 / 10",
        "Q12 int: −12288 / −4096",
        "               +4096 / +12288",
        "Sinh trực tiếp 4 mức PAM-4",
    ], "blue")
    box(380, 815, 320, 300, "KÊNH ISI", [
        "r_clean[n] = s[n] + 0.5s[n−1]",
        "h0 = 1 ; h1 = 0.5",
        "Postcursor thứ nhất",
        "BIÊN r_clean: [−4.5, +4.5]",
        "Đầu ra: Q4.12",
    ], "orange")
    box(750, 815, 300, 300, "CỘNG NHIỄU / RX INPUT", [
        "r[n] = satQ(r_clean[n] + η[n])",
        "BIÊN r theo case 20 dB:",
        limits(data["theoretical"]["rx"], 6),
        "ĐO r: " + limits(data["measured"]["rx"]),
        "r_fx: input của equalizer",
    ], "orange", size=10.5)
    box(1100, 815, 330, 300, "FFE — 3 TAP", [
        "f[n] = Σ qmul(wk, r[n−k])",
        "k = 0, 1, 2",
        "w0, w1, w2 ∈ [−1.25, +1.25]",
        "Khởi tạo: [0, 0.75, 0]",
        "Từng tích: Q4.12; tổng giữ rộng",
        "ĐO f: " + limits(data["measured"]["ffe_wide_sum"]),
    ], "green", size=10.5)
    # The DFE block includes both the feedback product and its subtraction.
    # This makes the main signal path explicitly FFE -> DFE -> Slicer.
    box(1480, 815, 330, 300, "DFE — 1 TAP + BỘ TRỪ", [
        "y[n] = satQ(f[n] − v[n])",
        "v[n] = qmul(b0, d_hat[n−1])",
        "b0 ∈ [−0.75, +0.75]",
        "Khởi tạo: b0 = 0",
        "BIÊN v: [−2.25, +2.25]",
        "ĐO v: " + limits(data["measured"]["dfe_feedback"]),
    ], "green", size=10.5)
    box(1860, 815, 300, 300, "SLICER PAM-4", [
        "Input y[n]: Q4.12",
        "ĐO y: " + limits(data["measured"]["y"]),
        "Ngưỡng: −2 / 0 / +2",
        "Đúng ngưỡng → mức thấp hơn",
        "Ví dụ: y=0 → d_hat=−1",
        "Căn TX/RX toàn EQ: D=1",
    ], "green", size=10.5)
    box(2210, 815, 330, 300, "SYMBOL / GRAY LABELS", [
        "d_hat[n] ∈ {−3, −1, +1, +3}",
        "−3→00 ; −1→01",
        "+1→11 ; +3→10",
        "2 bit / symbol",
        "Gray bits được suy ra để đo BER",
    ], "blue", size=10.5)
    for left, right in [(330, 380), (700, 750), (1050, 1100), (1430, 1480), (1810, 1860), (2160, 2210)]:
        path([(left, 965), (right, 965)], "green" if left >= 1050 else "gray")

    box(380, 395, 320, 300, "CLT / TAUS88 — 12 LANE", [
        "Mỗi lane: Rj ∈ [0, 4095]",
        "S = ΣRj ∈ [0, 49140]",
        "Center = S − 24570",
        "Gain = 4096 Q12 = 1.0",
        "z[n] = Center / 4096",
        "BIÊN z: [−5.998535, +5.998535]",
        "Mean ≈ 0 ; std ≈ 1",
    ], "orange", size=10.5)
    box(750, 395, 300, 300, "SCALE NHIỄU", [
        "SNR = 20 dB tại đầu ra kênh",
        "σ_float = %.10f" % data["sigma_float"],
        "σ_Q = 1024 / 4096 = 0.25",
        "η[n] = qmul(σ_Q, z[n])",
        "BIÊN η: " + limits(data["theoretical"]["scaled_noise"], 6),
        "ĐO η: " + limits(data["measured"]["noise"]),
        "CLT hữu hạn, gần Gaussian",
    ], "orange", size=10)
    path([(700, 545), (750, 545)], "orange")
    path([(900, 695), (900, 815)], "orange", label="η[n]", label_at=(925, 750))

    box(1480, 1175, 330, 300, "ROBUST-PROJECTED LMS", [
        "Training: d_des = s[n−D]",
        "Sau 3000 mẫu: d_des = d_hat[n]",
        "e_raw = satQ(d_des − y[n])",
        "ψ = clip(e_raw, [−2.5, +2.5])",
        "DD: update nếu |e_raw| ≤ 1.5",
        "μ = 0.0005 ; μ_acc = 524 Q20",
        "Δw = +μψx ; Δb = −μψd_prev",
        "40 bit / frac 20 → tap Q4.12",
        "Projection cho cả FFE và DFE",
    ], "purple", size=10)
    # Feedback below the DFE/Slicer; LMS is directly above the DFE.
    box(1935, 495, 150, 120, "z⁻¹", ["d_hat[n−1]"], "green", size=10.5)
    path([(2010, 815), (2010, 615)], "green", label="d_hat[n]", label_at=(1960, 740))
    path([(1935, 555), (1645, 555), (1645, 815)], "green",
         label="d_hat[n−1] (khởi tạo feedback = 0)", label_at=(1660, 530))
    path([(1645, 1175), (1645, 1115)], "purple", dashed=True, label="b0", label_at=(1680, 1145))
    path([(1480, 1260), (1265, 1260), (1265, 1115)], "purple", dashed=True,
         label="w0, w1, w2", label_at=(1350, 1280))
    path([(1835, 965), (1835, 1145), (1760, 1145), (1760, 1175)], "purple", dashed=True,
         label="y[n] → tính e_raw", label_at=(1940, 1150))
    ax.add_patch(Circle((1835, 965), 3, color=colors["purple"], zorder=4))
    path([(2185, 965), (2185, 1340), (1810, 1340)], "purple", dashed=True,
         label="d_hat[n] cho decision-directed", label_at=(2020, 1360))
    ax.add_patch(Circle((2185, 965), 3, color=colors["purple"], zorder=4))
    path([(185, 1115), (185, 1390), (1480, 1390)], "blue", dashed=True,
         label="TX reference: s[n−D] dùng khi training", label_at=(800, 1410))

    box(2210, 395, 330, 300, "ĐO BER / SER", [
        "So với TX tham chiếu s[n−D]",
        "Bỏ n ≤ 3000 ở đầu ra EQ",
        "197.000 symbol được đo",
        "394.000 bit được đo",
        "EQ: 6 bit lỗi / 394.000 bit",
        "BER = 1.52284 × 10⁻⁵",
    ], "blue", size=11)
    path([(2375, 815), (2375, 695)], "blue")
    path([(185, 815), (185, 330), (2375, 330), (2375, 395)], "blue", dashed=True)
    text(700, 348, "TX reference: đo BER sau khi căn D=1", 11, colors["blue"], align="center")

    box(40, 35, 1010, 240, "ĐỊNH DẠNG / QUY TẮC SỐ HỌC", [
        "Q4.12 signed 16 bit: integer ∈ [−32768, +32767]",
        "Giá trị thực ∈ [−8, +7.999755859375] ; LSB = 2⁻¹² = 0.000244140625",
        "satQ: clamp về signed 16 bit. qmul: tích integer >> 12, rồi satQ.",
        "Từ số thực → Q: round half away from zero. Dịch phải signed: floor.",
        "Tổng các tích FFE giữ rộng tới sau phép trừ DFE, rồi mới satQ đầu ra y.",
        "Các biên nhiễu / RX ở trên thuộc case CLT 20 dB; gaussmix không nằm trong hình.",
    ], "gray", size=11)

    box(1100, 35, 1440, 240, "SNAPSHOT TAP — SAU UPDATE SAMPLE 200.000, SNR 20 dB", [], "purple")
    column_x = [1130, 1270, 1560, 1800, 2010]
    for x, heading in zip(column_x, ["Tap", "Giá trị thực", "Integer Q4.12", "Hex 16 bit", "Miền cấu hình"]):
        text(x, 200, heading, 12, colors["purple"], weight="bold")
    for index, row in enumerate(data["final_taps"]):
        y = 165 - index * 35
        bound = "[−1.25, +1.25]" if index < cfg.nf else "[−0.75, +0.75]"
        for x, content in zip(column_x, [row["tap"], "%+.12f" % row["final_after_update_real"],
                                       str(row["final_after_update_fx"]), row["final_after_update_hex"], bound]):
            text(x, y, content, 12)
    text(1290, 12, "DFE gồm bộ nhân feedback và bộ trừ. LMS ở trên DFE là nhánh cập nhật cả bốn tap; số liệu mô phỏng giữ nguyên.", 10, align="center", color=colors["gray"])

    output.mkdir(parents=True, exist_ok=True)
    for suffix in ["png", "svg", "pdf"]:
        fig.savefig(output / ("pam4_current_model." + suffix), dpi=160, facecolor="white")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, default=ROOT / "10_sim/python_v26_signals")
    parser.add_argument("--output", type=Path, default=ROOT / "99_doc/figures")
    args = parser.parse_args()
    cfg, data = read_model_data(args.run)
    draw(cfg, data, args.output)
    with (args.output / "pam4_current_model_ranges.json").open("w", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
    print(json.dumps(dict(measured=data["measured"], theoretical=data["theoretical"], output=str(args.output),
                         ffe_feedback_replay_verified=True), indent=2))


if __name__ == "__main__":
    main()
