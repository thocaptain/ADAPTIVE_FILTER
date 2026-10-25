#!/usr/bin/env python3
"""Executable Python port of the numerical core of reference/full_demo_v26*.m.

Ported: Taus88/CLT, Q4.12 channel/noise, all five adaptive EQ variants,
Q20 adaptation accumulators, Polyak averaging, learning traces, BER/SER.
The original ODE/Lyapunov/threshold Monte Carlo suites and Excel/eye metrics
are outside this initial port. MATLAB cross-runtime equivalence is unverified.
Legacy BER is retained for diagnosis; reported primary BER is delay-aligned
and excludes training. A separately labelled frozen-tap experiment supports
the static-coefficient scope in README.md.
"""

import argparse
import csv
import hashlib
import json
import math
import time
from dataclasses import asdict, dataclass, replace
from pathlib import Path

import numpy as np
from scipy.special import ndtr
from scipy.stats import beta, chi2


ROOT = Path(__file__).resolve().parents[1]
LEVELS = np.array([-3, -1, 1, 3], dtype=np.int64)
GRAY = np.array([0, 1, 3, 2], dtype=np.int64)
POPCOUNT_2 = np.array([0, 1, 1, 2], dtype=np.int64)
MASK32 = (1 << 32) - 1
VARIANTS = ("plain", "sm_sign", "robust", "proj", "robust_proj")


@dataclass(frozen=True)
class Config:
    isi: float = 0.5
    snr_db: float = 20.0
    nf: int = 3
    nb: int = 1
    delay: int = 1
    train_len: int = 3000
    mu: float = 5e-4
    frac_bits: int = 12
    total_bits: int = 16
    u_bits: int = 12
    seed: int = 0x0A5B
    lanes: int = 12
    mix_enable: bool = True
    mix_r1: int = 7
    mix_r2: int = 11
    use_discrete_center: bool = True
    tune_gain: bool = True
    gain_search_radius: int = 8
    error_clip: float = 2.5
    use_error_clip: bool = True
    use_dd_gate: bool = True
    dd_gate_error: float = 1.50
    sm_sign_error_bound: float = 0.75
    sm_sign_update_amp: float = 1.0
    w_min: float = -1.25
    w_max: float = 1.25
    b_min: float = -0.75
    b_max: float = 0.75
    adapt_frac_bits: int = 20
    adapt_total_bits: int = 40
    init_main_tap: float = 0.75
    init_feedback_tap: float = 0.0
    mu_mode: str = "constant"
    mu_n0: int = 200
    mu_gamma: float = 0.70
    use_polyak: bool = True
    polyak_start_frac: float = 0.60
    trace_decimation: int = 50
    impulse_p: float = 0.01
    impulse_kappa: float = 8.0
    slicer_ties: str = "lower"
    adapt: bool = True


def round_away(x):
    """MATLAB round(): halves away from zero, unlike numpy.round()."""
    a = np.asarray(x, dtype=np.float64)
    out = np.copysign(np.floor(np.abs(a) + 0.5), a)
    return float(out) if out.ndim == 0 else out


def q_sat(x, bits=16):
    return np.clip(x, -(1 << (bits - 1)), (1 << (bits - 1)) - 1).astype(np.int64)


def q_from_real(x, q=12, bits=16):
    return q_sat(round_away(np.asarray(x) * (1 << q)), bits)


def q_mul(a, b, q=12, bits=16):
    return q_sat((np.asarray(a, dtype=np.int64) * np.asarray(b, dtype=np.int64)) >> q, bits)


def sat_scalar(x, bits=16):
    return min(max(int(x), -(1 << (bits - 1))), (1 << (bits - 1)) - 1)


def round_scalar(x):
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def seed_mix32(x):
    x = int(x) & MASK32
    x ^= (x << 13) & MASK32
    x ^= x >> 17
    x ^= (x << 5) & MASK32
    return x & MASK32


def taus88_step(s1, s2, s3):
    """Unsigned shifts discard overflow, matching MATLAB uint32 bitshift."""
    b = (((s1 << 13) & MASK32) ^ s1) >> 19
    s1 = (((s1 & 4294967294) << 12) & MASK32) ^ b
    b = (((s2 << 2) & MASK32) ^ s2) >> 25
    s2 = (((s2 & 4294967288) << 4) & MASK32) ^ b
    b = (((s3 << 3) & MASK32) ^ s3) >> 11
    s3 = (((s3 & 4294967280) << 17) & MASK32) ^ b
    return s1 ^ s2 ^ s3, s1, s2, s3


def stage1_offsets(lanes, u_bits):
    nbase = 33 - u_bits
    stride = next(c for c in [4, 5, 3, 2, 1] if math.gcd(c, nbase) == 1)
    return [(j % nbase) * stride % nbase for j in range(lanes)]


def clt_parameters(cfg):
    if cfg.lanes < 2 or cfg.lanes % 2 or cfg.frac_bits != cfg.u_bits:
        raise ValueError("Require even lanes >= 2 and frac_bits == u_bits.")
    if not 0 < cfg.u_bits <= 32:
        raise ValueError("u_bits must be in 1..32")
    nlev = 1 << cfg.u_bits
    center = cfg.lanes // 2 * (nlev - 1 if cfg.use_discrete_center else 1 << cfg.frac_bits)
    ideal = math.sqrt(12 / (cfg.lanes * (1 - 1 / nlev**2)))
    gain0 = int(q_from_real(ideal, cfg.frac_bits, cfg.total_bits))
    candidates = range(gain0 - cfg.gain_search_radius, gain0 + cfg.gain_search_radius + 1)
    var_center = cfg.lanes * (nlev**2 - 1) / 12
    gain = min(candidates, key=lambda g: abs((g / (1 << cfg.frac_bits))**2 * var_center / nlev**2 - 1)) if cfg.tune_gain else gain0
    return center, gain


def generate_clt(n, cfg, debug_samples=64):
    """Same lane recurrences, seeds, bit windows, centering and gain as .m.

    Lanes run sequentially in software, but no lane shares recurrence state.
    Summation is in int64 so the wider CLT sum is never prematurely clipped.
    """
    if n <= 0:
        raise ValueError("n must be positive")
    center, gain = clt_parameters(cfg)
    offsets = stage1_offsets(cfg.lanes, cfg.u_bits)
    count = min(n, max(0, debug_samples))
    words = np.zeros((count, cfg.lanes), dtype=np.uint32)
    mixed = np.zeros_like(words)
    uniforms = np.zeros((count, cfg.lanes), dtype=np.uint16 if cfg.u_bits <= 16 else np.uint32)
    sums = np.zeros(n, dtype=np.int64)
    initial = []
    mask_u = (1 << cfg.u_bits) - 1
    for j, offset in enumerate(offsets):
        lane = j + 1  # MATLAB seed offsets use one-based lane indices.
        seeds = []
        for factor, bias, minimum in [(101, 1, 2), (211, 3, 8), (307, 7, 16)]:
            value = seed_mix32(min(cfg.seed + factor * lane + bias, MASK32))
            if value < minimum:
                value += minimum
            seeds.append(value if value else minimum)
        s1, s2, s3 = seeds
        initial.append({"lane": lane, "bit_offset": offset, "s1": s1, "s2": s2, "s3": s3})
        lane_values = np.empty(n, dtype=np.int64)
        for i in range(n):
            word, s1, s2, s3 = taus88_step(s1, s2, s3)
            if cfg.mix_enable:
                r2 = cfg.mix_r2 % 32
                rotated = (((word << r2) & MASK32) | (word >> (32 - r2))) if r2 else word
                value = word ^ (word >> cfg.mix_r1) ^ rotated
            else:
                value = word
            lane_values[i] = (value >> offset) & mask_u
            if i < count:
                words[i, j], mixed[i, j], uniforms[i, j] = word, value, lane_values[i]
        sums += lane_values
    centered = sums - center
    z_fx = q_mul(centered, gain, cfg.frac_bits, cfg.total_bits)
    debug = dict(initial=initial, words=words, mixed=mixed, uniforms=uniforms,
                 sums=sums[:count], centered=centered[:count], z_fx=z_fx[:count],
                 center=center, gain_fx=gain, offsets=offsets)
    return z_fx, debug


def pam_slice_fx(values, cfg):
    thresholds = np.array([-2, 0, 2], dtype=np.int64) << cfg.frac_bits
    return LEVELS[np.searchsorted(thresholds, values, side="left" if cfg.slicer_ties == "lower" else "right")]


def error_counts(tx, rx):
    tx, rx = np.asarray(tx), np.asarray(rx)
    if tx.shape != rx.shape or not tx.size:
        raise ValueError("Nonempty, equally shaped symbol arrays required")
    tx_gray = GRAY[((tx + 3) // 2).astype(int)]
    rx_gray = GRAY[((rx + 3) // 2).astype(int)]
    bit_errors = int(POPCOUNT_2[np.bitwise_xor(tx_gray, rx_gray)].sum())
    symbol_errors = int(np.count_nonzero(tx != rx))
    bits = 2 * tx.size
    # Exact two-sided Clopper-Pearson interval, conditional on independent errors.
    lo = float(beta.ppf(0.025, bit_errors, bits - bit_errors + 1)) if bit_errors else 0.0
    hi = float(beta.ppf(0.975, bit_errors + 1, bits - bit_errors)) if bit_errors < bits else 1.0
    return dict(symbols=int(tx.size), bits=int(bits), symbol_errors=symbol_errors,
                bit_errors=bit_errors, ser=symbol_errors / tx.size, ber=bit_errors / bits,
                ber_binomial_95_interval=[lo, hi])


def dfe_core(r_fx, d_fx, cfg, variant="robust_proj", initial_w=None, initial_b=None,
             debug_samples=12800, store_tap_history=False):
    """Port of dfe_lms_pam_fp_core; zero-based arrays, one-based LMS schedule."""
    if variant not in VARIANTS or cfg.slicer_ties not in ("lower", "upper"):
        raise ValueError("Invalid EQ variant or slicer tie rule")
    if cfg.mu_mode not in ("constant", "decreasing") or cfg.nf < 1 or cfg.nb < 0:
        raise ValueError("Invalid step schedule or tap count")
    q, bits, qa, ba = cfg.frac_bits, cfg.total_bits, cfg.adapt_frac_bits, cfg.adapt_total_bits
    if qa < q:
        raise ValueError("This port requires adaptation precision >= signal precision")
    scale = 1 << q
    w = [0] * cfg.nf
    w[min(cfg.nf - 1, cfg.delay)] = int(q_from_real(cfg.init_main_tap, q, bits))
    b = [0] * cfg.nb
    if b:
        b[0] = int(q_from_real(cfg.init_feedback_tap, q, bits))
    w = list(map(int, initial_w)) if initial_w is not None else w
    b = list(map(int, initial_b)) if initial_b is not None else b
    if len(w) != cfg.nf or len(b) != cfg.nb:
        raise ValueError("Initial coefficient dimensions do not match tap counts")
    w_acc, b_acc = [v << (qa - q) for v in w], [v << (qa - q) for v in b]
    w_lo, w_hi = int(q_from_real(cfg.w_min, qa, ba)), int(q_from_real(cfg.w_max, qa, ba))
    b_lo, b_hi = int(q_from_real(cfg.b_min, qa, ba)), int(q_from_real(cfg.b_max, qa, ba))
    clip = int(q_from_real(cfg.error_clip, q, bits))
    gate = int(q_from_real(cfg.dd_gate_error, q, bits))
    sign_bound = int(q_from_real(cfg.sm_sign_error_bound, q, bits))
    sign_unit = int(q_from_real(cfg.sm_sign_update_amp, q, bits))
    use_robust, use_proj = variant in ("robust", "robust_proj"), variant in ("proj", "robust_proj")
    n = len(r_fx)
    y_fx, e_fx, d_hat = np.zeros(n, dtype=np.int64), np.zeros(n, dtype=np.int64), np.zeros(n, dtype=np.int64)
    xbuf, fbuf = [0] * cfg.nf, [0] * cfg.nb
    trace, debug = [], []
    initial_taps = np.array(w + b, dtype=np.int64)
    tap_history = np.empty((n, cfg.nf + cfg.nb), dtype=np.int64) if store_tap_history else None
    counters = dict(updates=0, projection_hits=0, projection_steps=0, clipped_errors=0,
                    dd_gate_skips=0, sm_sign_skips=0)
    sum_w, sum_b, avg_count = [0] * cfg.nf, [0] * cfg.nb, 0
    avg_start = max(1, math.floor(cfg.polyak_start_frac * n))
    mu_const = int(q_from_real(cfg.mu, qa, ba))
    convert = lambda v: sat_scalar(round_scalar(v / (1 << (qa - q))), bits)
    for i in range(n):
        ni = i + 1
        xbuf = [int(r_fx[i])] + xbuf[:-1]
        if cfg.nb:
            fbuf = [int(d_hat[i - 1]) * scale if i else 0] + fbuf[:-1]
        before_w, before_b = w[:], b[:]
        ff_raw = [wk * xk for wk, xk in zip(w, xbuf)]
        fb_raw = [bk * fk for bk, fk in zip(b, fbuf)]
        ff_terms = [sat_scalar(v >> q, bits) for v in ff_raw]
        fb_terms = [sat_scalar(v >> q, bits) for v in fb_raw]
        y = sat_scalar(sum(ff_terms) - sum(fb_terms), bits)
        y_fx[i] = y
        if cfg.slicer_ties == "lower":
            decision = -3 if y <= -2 * scale else -1 if y <= 0 else 1 if y <= 2 * scale else 3
        else:
            decision = -3 if y < -2 * scale else -1 if y < 0 else 1 if y < 2 * scale else 3
        d_hat[i] = decision
        desired = int(d_fx[i - cfg.delay]) if ni > cfg.delay and ni <= cfg.train_len else decision * scale if ni > cfg.delay else 0
        error = sat_scalar(desired - y, bits)
        e_fx[i] = error
        if variant == "sm_sign":
            update_error = sign_unit if error > 0 else -sign_unit if error < 0 else 0
        elif use_robust and cfg.use_error_clip:
            update_error = min(max(error, -clip), clip)
            counters["clipped_errors"] += int(update_error != error)
        else:
            update_error = error
        do_update = True
        if ni > cfg.train_len and cfg.use_dd_gate:
            do_update = abs(error) <= gate
            counters["dd_gate_skips"] += int(not do_update)
        if variant == "sm_sign":
            active = abs(error) > sign_bound
            counters["sm_sign_skips"] += int(do_update and not active)
            do_update = do_update and active
        do_update = do_update and cfg.adapt
        hits, mu_acc = 0, 0
        if do_update:
            counters["updates"] += 1
            mu_acc = mu_const if cfg.mu_mode == "constant" else int(q_from_real(cfg.mu / (ni + cfg.mu_n0)**cfg.mu_gamma, qa, ba))
            for k in range(cfg.nf):
                delta = sat_scalar(round_scalar(float(mu_acc) * update_error * xbuf[k] / (1 << (2 * q))), ba)
                w_acc[k] = sat_scalar(w_acc[k] + delta, ba)
            for k in range(cfg.nb):
                delta = sat_scalar(round_scalar(float(mu_acc) * update_error * fbuf[k] / (1 << (2 * q))), ba)
                b_acc[k] = sat_scalar(b_acc[k] - delta, ba)
            if use_proj:
                for values, low, high in [(w_acc, w_lo, w_hi), (b_acc, b_lo, b_hi)]:
                    for k, value in enumerate(values):
                        projected = min(max(value, low), high)
                        hits += int(projected != value)
                        values[k] = projected
                counters["projection_hits"] += hits
                counters["projection_steps"] += int(hits > 0)
            w, b = [convert(v) for v in w_acc], [convert(v) for v in b_acc]
        if store_tap_history:
            tap_history[i] = w + b  # Visible taps AFTER the update for sample i+1.
        if i % cfg.trace_decimation == 0:
            trace.append([ni, (error / scale)**2] + [v / scale for v in w + b])
        if i < debug_samples:
            debug.append([ni, int(d_fx[i]), int(r_fx[i]), y, decision * scale, desired,
                          error, update_error, int(do_update), mu_acc, hits,
                          sat_scalar((sum(ff_raw) - sum(fb_raw)) >> q, bits)]
                         + xbuf + fbuf + before_w + before_b + w + b)
        if cfg.use_polyak and ni >= avg_start:
            sum_w = [sat_scalar(s + v, 64) for s, v in zip(sum_w, w_acc)]
            sum_b = [sat_scalar(s + v, 64) for s, v in zip(sum_b, b_acc)]
            avg_count += 1
    w_avg = [convert(round_scalar(v / avg_count)) for v in sum_w] if avg_count else w
    b_avg = [convert(round_scalar(v / avg_count)) for v in sum_b] if avg_count else b
    return dict(y_fx=y_fx, e_fx=e_fx, decisions=d_hat, w_fx=w, b_fx=b,
                w_polyak_fx=w_avg, b_polyak_fx=b_avg, counters=counters,
                trace=np.asarray(trace), debug=np.asarray(debug, dtype=np.int64),
                tap_after_fx=tap_history, initial_taps_fx=initial_taps)


def make_symbols(n, seed):
    # Fixed MT19937 source. MATLAB randi sequence parity has not been verified.
    return LEVELS[np.floor(4 * np.random.RandomState(seed).random_sample(n)).astype(int)]


def run_case(symbols, z_fx, cfg, variant, noise_model="gaussian", use_noise=True,
             initial_w=None, initial_b=None, debug_samples=12800, store_tap_history=False):
    scale = 1 << cfg.frac_bits
    d_fx = q_from_real(symbols, cfg.frac_bits, cfg.total_bits)
    clean = symbols + cfg.isi * np.r_[0, symbols[:-1]]
    clean_fx = q_from_real(clean, cfg.frac_bits, cfg.total_bits)
    sigma = math.sqrt(np.mean(clean**2) / 10**(cfg.snr_db / 10)) if use_noise else 0.0
    sigma_fx = int(q_from_real(sigma, cfg.frac_bits, cfg.total_bits))
    noise_fx = q_mul(z_fx[:len(symbols)], sigma_fx, cfg.frac_bits, cfg.total_bits) if use_noise else np.zeros(len(symbols), dtype=np.int64)
    impulse_count = 0
    if noise_model == "gaussmix" and use_noise:
        burst = np.random.RandomState(cfg.seed + 777).random_sample(len(symbols)) < cfg.impulse_p
        impulse_count = int(burst.sum())
        kappa = q_from_real(cfg.impulse_kappa, cfg.frac_bits, cfg.total_bits)
        noise_fx[burst] = q_mul(noise_fx[burst], kappa, cfg.frac_bits, cfg.total_bits)
    elif noise_model != "gaussian":
        raise ValueError("Unsupported noise model")
    r_fx = q_sat(clean_fx + noise_fx, cfg.total_bits)
    core = dfe_core(r_fx, d_fx, cfg, variant, initial_w, initial_b, debug_samples, store_tap_history)
    raw_decisions = pam_slice_fx(r_fx, cfg)
    start = max(cfg.train_len, cfg.delay)
    if start >= len(symbols):
        raise ValueError("Need more symbols than training length and decision delay")
    targets = np.arange(start, len(symbols)) - cfg.delay
    tx = symbols[targets]
    metrics = dict(noeq=error_counts(tx, raw_decisions[targets]),
                   eq=error_counts(tx, core["decisions"][start:]),
                   legacy_noeq=error_counts(symbols[:len(symbols)-cfg.delay], raw_decisions[cfg.delay:]),
                   legacy_eq=error_counts(symbols[:len(symbols)-cfg.delay], core["decisions"][cfg.delay:]))
    true_error = core["y_fx"][start:] / scale - tx
    metrics.update(true_symbol_mse=float(np.mean(true_error**2)),
                   decision_error_mse_tail=float(np.mean((core["e_fx"][int(0.9 * len(symbols)):] / scale)**2)),
                   noise_sigma_float=float(sigma), noise_sigma_fx=sigma_fx,
                   actual_noise_power=float(np.mean((noise_fx / scale)**2)), impulse_count=impulse_count)
    return dict(core=core, metrics=metrics, symbols=symbols, d_fx=d_fx,
                clean_fx=clean_fx, noise_fx=noise_fx, r_fx=r_fx)


def bittrue_reference(cfg):
    center, gain = clt_parameters(cfg)
    nlev = 1 << cfg.u_bits
    length = cfg.lanes * (nlev - 1) + 1
    nfft = 1 << (length - 1).bit_length()
    pmf = np.fft.irfft(np.fft.rfft(np.ones(nlev) / nlev, nfft)**cfg.lanes, nfft)[:length]
    pmf = np.maximum(pmf, 0)
    pmf /= pmf.sum()
    support = q_mul(np.arange(length, dtype=np.int64) - center, gain, cfg.frac_bits, cfg.total_bits)
    values, inverse = np.unique(support, return_inverse=True)
    weights = np.bincount(inverse, weights=pmf)
    return values, weights


def noise_statistics(z_fx, cfg, debug):
    z = z_fx / (1 << cfg.frac_bits)
    mean, std = float(z.mean()), float(z.std())
    normalized = (z - mean) / std
    values, pmf = bittrue_reference(cfg)
    cumulative = pmf.cumsum()
    observations, counts = np.unique(z_fx, return_counts=True)
    empirical_right = counts.cumsum() / z.size
    empirical_left = empirical_right - counts / z.size
    support_indices = np.searchsorted(values, observations)
    ref_right = cumulative[support_indices]
    ref_left = ref_right - pmf[support_indices]
    # Compare both sides of discrete jumps. The MATLAB helper compares every
    # repeated observation to the right CDF, which includes artificial jump gaps.
    bittrue_distance = float(max(np.max(np.abs(empirical_right - ref_right)),
                                 np.max(np.abs(empirical_left - ref_left))))
    gaussian_cdf = ndtr(observations / (1 << cfg.frac_bits))
    gaussian_distance = float(max(np.max(np.abs(empirical_right - gaussian_cdf)),
                                  np.max(np.abs(empirical_left - gaussian_cdf))))
    edges = np.r_[-np.inf, values[np.searchsorted(cumulative, np.arange(1, 24) / 24)] + 0.5, np.inf]
    observed_bins = np.histogram(z_fx, edges)[0]
    # Use actual discrete mass of each bin, not the approximation N/24.
    expected_mass = np.histogram(values, edges, weights=pmf)[0]
    expected_bins = expected_mass * z.size
    statistic = float(np.sum((observed_bins - expected_bins)**2 / expected_bins))
    autocorrelation = [float(np.mean((z[:-lag] - mean) * (z[lag:] - mean)) / std**2) for lag in range(1, 41)]
    tails = []
    for threshold in [3, 4, 5]:
        tails.append(dict(threshold=threshold, observed_count=int(np.count_nonzero(np.abs(z) > threshold)),
                          empirical=float(np.mean(np.abs(z) > threshold)),
                          ideal_clt=float(pmf[np.abs(values / (1 << cfg.frac_bits)) > threshold].sum()),
                          gaussian=float(2 * ndtr(-threshold))))
    return dict(samples=int(z.size), lanes=cfg.lanes, seed=cfg.seed, mean=mean, std=std,
                skewness=float(np.mean(normalized**3)), excess_kurtosis=float(np.mean(normalized**4) - 3),
                theoretical_excess_kurtosis=-6 / (5 * cfg.lanes), center=debug["center"], gain_fx=debug["gain_fx"],
                min=float(z.min()), max=float(z.max()), ks_distance_to_gaussian=gaussian_distance,
                ks_distance_to_bittrue_clt=bittrue_distance,
                chi_square_bittrue=dict(statistic=statistic, dof=23, p_approx_iid=float(chi2.sf(statistic, 23))),
                autocorrelation_lags_1_to_40=autocorrelation,
                max_abs_autocorrelation=float(np.max(np.abs(autocorrelation))), tails=tails)


def write_csv(path, header, rows):
    with Path(path).open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(header)
        writer.writerows(rows)


def signal_window(result, cfg, count=64, start=None):
    """All columns refer to the same TX symbol; EQ samples occur D clocks later."""
    available = len(result["symbols"]) - cfg.delay
    if count < 1 or available < 1:
        raise ValueError("Need a nonempty signal window")
    count = min(count, available)
    first_valid = max(0, cfg.train_len - cfg.delay)
    if start is None:
        start = min(cfg.train_len + 1000, available - count)
    if start < 0 or start + count > available:
        raise ValueError("Signal window extends beyond the aligned frame")
    indices = np.arange(start, start + count)
    delayed = indices + cfg.delay
    scale = 1 << cfg.frac_bits
    return dict(tx_sample=indices + 1, eq_sample=delayed + 1,
                tx=result["symbols"][indices], clean=result["clean_fx"][indices] / scale,
                rx=result["r_fx"][indices] / scale,
                y=result["core"]["y_fx"][delayed] / scale,
                decision=result["core"]["decisions"][delayed],
                noeq_decision=pam_slice_fx(result["r_fx"][indices], cfg),
                after_training=bool(start >= first_valid))


def adaptive_tap_summary(result, cfg):
    history = result["core"]["tap_after_fx"]
    if history is None or not len(history):
        raise ValueError("Full tap history is required for exact adaptive statistics")
    final = np.array(result["core"]["w_fx"] + result["core"]["b_fx"], dtype=np.int64)
    np.testing.assert_array_equal(history[-1], final)
    names = ["w%d" % k for k in range(cfg.nf)] + ["b%d" % k for k in range(cfg.nb)]
    # A zero-forcing reference for this h0=1, one-postcursor, D=1 experiment.
    # These are NOT asserted to be optimal taps at nonzero noise power.
    ideal = [0.0, 1.0, 0.0, cfg.isi] if (cfg.nf, cfg.nb, cfg.delay) == (3, 1, 1) else [None] * len(names)
    count = max(1, len(history) // 10)
    tail = history[-count:] / (1 << cfg.frac_bits)
    last_used = history[-2] if len(history) > 1 else result["core"]["initial_taps_fx"]
    rows = []
    for k, name in enumerate(names):
        rows.append(dict(tap=name, final_after_update_fx=int(final[k]),
                         final_after_update_real=float(final[k] / (1 << cfg.frac_bits)),
                         final_after_update_hex=format(int(final[k]) & ((1 << cfg.total_bits) - 1), "04X"),
                         used_for_last_output_fx=int(last_used[k]),
                         used_for_last_output_real=float(last_used[k] / (1 << cfg.frac_bits)),
                         tail_mean=float(tail[:, k].mean()), tail_std=float(tail[:, k].std()),
                         tail_min=float(tail[:, k].min()), tail_max=float(tail[:, k].max()),
                         ideal_no_noise_reference=ideal[k]))
    return dict(sample=len(history), snr_db=cfg.snr_db, variant="robust_proj", delay=cfg.delay,
                timing="Taps shown are visible Q4.12 coefficients AFTER the final update; last-output taps are separate.",
                tail_samples=count, tail_first_sample=len(history) - count + 1, taps=rows)


def export_signal_and_tap_plots(output, cfg, result):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.ticker import MaxNLocator

    window = signal_window(result, cfg)
    summary = adaptive_tap_summary(result, cfg)
    with (output / "adaptive_taps_summary.json").open("w") as stream:
        json.dump(summary, stream, indent=2, allow_nan=False)
    write_csv(output / "adaptive_taps_summary.csv", list(summary["taps"][0]),
              [[row[key] for key in summary["taps"][0]] for row in summary["taps"]])
    history = result["core"]["tap_after_fx"]
    samples = np.unique(np.r_[np.arange(0, len(history), cfg.trace_decimation), len(history) - 1])
    names = [row["tap"] for row in summary["taps"]]
    write_csv(output / "adaptive_taps_trace.csv", ["sample_after_update"] + [name + "_fx" for name in names] + names,
              [[int(i + 1)] + history[i].tolist() + (history[i] / (1 << cfg.frac_bits)).tolist() for i in samples])
    write_csv(output / "tx_rx_signals.csv", ["tx_sample", "eq_sample", "tx", "channel_clean", "rx_before_eq", "y_after_eq", "decision", "noeq_decision"],
              zip(*(window[key] for key in ["tx_sample", "eq_sample", "tx", "clean", "rx", "y", "decision", "noeq_decision"])))

    x = window["tx_sample"]
    fig, axes = plt.subplots(4, 1, figsize=(14, 10), sharex=True, constrained_layout=True)
    fig.suptitle("PAM-4 TX/RX | 20 dB CLT noise | h0=1, h1=%.2f | adaptive FFE/DFE, D=%d" % (cfg.isi, cfg.delay), fontsize=15)
    axes[0].step(x, window["tx"], where="mid", color="#1764ab", linewidth=1.6, label="TX s[n]")
    axes[0].plot(x, window["tx"], "o", color="#1764ab", markersize=3)
    axes[0].set_title("1. Transmitted PAM-4 symbols", loc="left")
    axes[1].plot(x, window["clean"], "--", color="0.55", linewidth=1, label="ISI channel without noise")
    axes[1].plot(x, window["rx"], ".-", color="#d97a14", linewidth=1, label="RX r[n]: ISI + CLT noise")
    raw_errors = window["noeq_decision"] != window["tx"]
    axes[1].plot(x[raw_errors], window["rx"][raw_errors], "x", color="#bf2331", markersize=8, label="Wrong raw-slicer decision")
    axes[1].set_title("2. Receiver input before equalization", loc="left")
    axes[2].step(x, window["tx"], where="mid", color="0.65", linestyle="--", label="TX reference")
    axes[2].plot(x, window["y"], ".-", color="#248a53", linewidth=1, label="EQ y[n+D], aligned to s[n]")
    axes[2].set_title("3. Equalized samples before slicer (delay compensated)", loc="left")
    axes[3].step(x, window["tx"], where="mid", color="#1764ab", linewidth=1.5, label="TX reference")
    axes[3].plot(x, window["decision"], "o", markerfacecolor="none", markeredgecolor="#248a53", markersize=6, label="Recovered symbol d_hat[n+D]")
    errors = window["decision"] != window["tx"]
    axes[3].plot(x[errors], window["decision"][errors], "x", color="#bf2331", markersize=9)
    axes[3].set_title("4. Decisions | raw: %d/%d symbol errors; after EQ: %d/%d in this window" %
                      (int(raw_errors.sum()), len(x), int(errors.sum()), len(x)), loc="left")
    for k, ax in enumerate(axes):
        if k in (1, 2):
            for threshold in [-2, 0, 2]:
                ax.axhline(threshold, color="0.8", linestyle=":", linewidth=0.7)
        ax.set_ylabel("Amplitude")
        ax.set_yticks([-3, -1, 1, 3])
        ax.set_ylim((-5.7, 5.7) if k == 1 else (-3.8, 3.8))
        ax.grid(alpha=0.2)
        ax.legend(loc="upper right", fontsize=8, ncol=3)
    axes[-1].set_xlabel("Transmitted symbol index n (one-based); RX after EQ uses output sample n+D")
    axes[-1].xaxis.set_major_locator(MaxNLocator(integer=True, nbins=12))
    fig.savefig(output / "tx_rx_signals.png", dpi=160)
    fig.savefig(output / "tx_rx_signals.pdf")
    plt.close(fig)

    fig, axes = plt.subplots(len(names), 2, figsize=(14, 11), squeeze=False, constrained_layout=True)
    fig.suptitle("Adaptive taps | 20 dB | mu=0.0005 | visible Q4.12 coefficients AFTER each update", fontsize=14)
    early_end = min(len(history), 20000)
    tail_start = len(history) - summary["tail_samples"]
    colors = ["#1764ab", "#d97a14", "#248a53", "#bf2331"]
    for k, row in enumerate(summary["taps"]):
        for column, begin, end in [(0, 0, early_end), (1, tail_start, len(history))]:
            ax = axes[k, column]
            stride = max(1, (end - begin) // 3000)
            idx = np.unique(np.r_[np.arange(begin, end, stride), end - 1])
            ax.plot(idx + 1, history[idx, k] / (1 << cfg.frac_bits), color=colors[k % len(colors)], linewidth=0.8, label="Adaptive " + row["tap"])
            if row["ideal_no_noise_reference"] is not None:
                ax.axhline(row["ideal_no_noise_reference"], color="0.45", linestyle="--", linewidth=0.9, label="No-noise reference")
            if column == 0:
                if cfg.train_len <= early_end:
                    ax.axvline(cfg.train_len, color="0.6", linestyle=":", linewidth=1, label="Training end")
                ax.set_title(row["tap"] + " | initial convergence", loc="left")
                ax.legend(fontsize=7, loc="best")
            else:
                ax.axhline(row["tail_mean"], color="black", linewidth=0.8, label="Tail mean")
                ax.axhspan(row["tail_mean"] - row["tail_std"], row["tail_mean"] + row["tail_std"], color=colors[k % len(colors)], alpha=0.12)
                ax.plot(len(history), row["final_after_update_real"], "o", color="black", markersize=4)
                ax.set_title("%s final = %+.12g | Q12=%d | hex=%s" % (row["tap"], row["final_after_update_real"], row["final_after_update_fx"], row["final_after_update_hex"]), loc="left", fontsize=10)
                ax.text(0.02, 0.03, "Last %d samples: mean=%+.8f, std=%.8f" % (summary["tail_samples"], row["tail_mean"], row["tail_std"]),
                        transform=ax.transAxes, fontsize=8, bbox=dict(facecolor="white", alpha=0.85, edgecolor="none"))
            ax.set_ylabel(row["tap"])
            ax.set_xlabel("Processed sample (one-based)")
            ax.grid(alpha=0.2)
            ax.ticklabel_format(axis="x", style="plain", useOffset=False)
    fig.savefig(output / "adaptive_taps.png", dpi=160)
    fig.savefig(output / "adaptive_taps.pdf")
    plt.close(fig)
    print("Exact adaptive taps AFTER sample %d:" % summary["sample"], flush=True)
    for row in summary["taps"]:
        print("  %s=%+.12f  Q12=%d  hex=%s  tail_mean=%+.8f" %
              (row["tap"], row["final_after_update_real"], row["final_after_update_fx"], row["final_after_update_hex"], row["tail_mean"]), flush=True)


def export_debug(output, cfg, debug, result):
    with (output / "lane_initial_states.json").open("w") as stream:
        json.dump(debug["initial"], stream, indent=2)
    header = ["sample", "sumR", "centered_sum", "z_clt_fx"]
    for lane in range(cfg.lanes):
        header += ["W32_lane%d" % (lane + 1), "V32_lane%d" % (lane + 1), "R_lane%d" % (lane + 1)]
    rows = []
    for i in range(len(debug["sums"])):
        row = [i + 1, int(debug["sums"][i]), int(debug["centered"][i]), int(debug["z_fx"][i])]
        for lane in range(cfg.lanes):
            row += [int(debug[name][i, lane]) for name in ("words", "mixed", "uniforms")]
        rows.append(row)
    write_csv(output / "lane_debug.csv", header, rows)
    header = ["sample", "tx_fx", "rx_fx", "y_fx", "decision_fx", "desired_fx", "error_fx", "update_error_fx",
              "do_update", "mu_acc", "projection_hits", "raw_accumulator_y_fx"]
    for name, count in [("xbuf", cfg.nf), ("fbuf", cfg.nb), ("w_before", cfg.nf), ("b_before", cfg.nb), ("w_after", cfg.nf), ("b_after", cfg.nb)]:
        header += ["%s_%d" % (name, k) for k in range(count)]
    write_csv(output / "eq_debug_trace.csv", header, result["core"]["debug"])
    trace = result["core"]["debug"]
    write_csv(output / "eq_debug_hex.csv", header[:8],
              [[int(row[0])] + [format(int(v) & 0xFFFF, "04X") for v in row[1:8]] for row in trace])


def make_plots(output, z_fx, cfg, cases, selected):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    z = z_fx / (1 << cfg.frac_bits)
    figure, axes = plt.subplots(2, 2, figsize=(12, 8), constrained_layout=True)
    axes[0, 0].hist(z, bins=100, density=True, label="CLT / Taus88")
    xx = np.linspace(-5, 5, 800)
    axes[0, 0].plot(xx, np.exp(-xx**2 / 2) / math.sqrt(2 * math.pi), label="Gaussian N(0,1)")
    axes[0, 0].set(title="Noise distribution (12 uniform lanes)", xlabel="Noise amplitude", ylabel="Density")
    axes[0, 0].legend()
    trace = selected["core"]["trace"]
    for k in range(cfg.nf + cfg.nb):
        axes[0, 1].plot(trace[:, 0], trace[:, 2 + k], label=("w%d" % k) if k < cfg.nf else "b%d" % (k - cfg.nf))
    axes[0, 1].axvline(cfg.train_len, color="black", linestyle="--", label="Training end")
    axes[0, 1].set(title="Adaptive taps: Gaussian noise, 20 dB", xlabel="Symbol index", ylabel="Coefficient")
    axes[0, 1].legend()
    start = max(cfg.train_len, cfg.delay)
    targets = np.arange(start, len(selected["symbols"])) - cfg.delay
    transmitted = selected["symbols"][targets]
    before = selected["r_fx"][targets] / (1 << cfg.frac_bits)
    after = selected["core"]["y_fx"][start:] / (1 << cfg.frac_bits)
    for level in LEVELS:
        subset = transmitted == level
        axes[1, 0].hist(before[subset], bins=80, density=True, histtype="step", alpha=0.5)
        axes[1, 0].hist(after[subset], bins=80, density=True, histtype="step", label="TX %d, after EQ" % level)
    axes[1, 0].set(title="Decision samples by transmitted symbol", xlabel="Sample amplitude", ylabel="Conditional density")
    axes[1, 0].legend(fontsize=8)
    snr_cases = sorted([c for c in cases if c["variant"] == "robust_proj" and c["noise_model"] == "gaussian" and c["use_noise"] and c["mode"] == "adaptive"], key=lambda c: c["snr_db"])
    snr = [c["snr_db"] for c in snr_cases]
    for name, label in [("noeq", "No EQ (aligned)"), ("eq", "Adaptive FFE/DFE")]:
        ber = [c["metrics"][name]["ber"] for c in snr_cases]
        axes[1, 1].semilogy(snr, [max(v, 0.5 / c["metrics"][name]["bits"]) for v, c in zip(ber, snr_cases)], "o-", label=label)
        for x, y, case in zip(snr, ber, snr_cases):
            if y == 0:
                axes[1, 1].annotate("0 errors", (x, 0.5 / case["metrics"][name]["bits"]), xytext=(0, 7), textcoords="offset points", fontsize=8)
    axes[1, 1].set(title="Measured BER after training (zero-error points labelled)", xlabel="SNR at channel output (dB)", ylabel="BER")
    axes[1, 1].legend()
    for ax in axes.flat:
        ax.grid(alpha=0.25)
    figure.savefig(output / "overview.png", dpi=160)
    plt.close(figure)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--symbols", type=int, default=200000)
    parser.add_argument("--stat-samples", type=int, default=1000000)
    parser.add_argument("--train-len", type=int, default=3000)
    parser.add_argument("--snr-values", type=float, nargs="+", default=[15, 20, 25])
    parser.add_argument("--debug-samples", type=int, default=12800)
    parser.add_argument("--output", type=Path, default=ROOT / "10_sim" / "python_v26")
    parser.add_argument("--skip-mixed", action="store_true")
    parser.add_argument("--skip-frozen", action="store_true")
    args = parser.parse_args()
    if args.symbols <= args.train_len + 10 or args.stat_samples < 100:
        parser.error("Need symbols > train-len + 10 and stat-samples >= 100")
    cfg = Config(train_len=args.train_len)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    print("Generating CLT/Taus88: %d samples, %d lanes..." % (max(args.stat_samples, args.symbols), cfg.lanes), flush=True)
    z_fx, rng_debug = generate_clt(max(args.stat_samples, args.symbols), cfg)
    stats = noise_statistics(z_fx[:args.stat_samples], cfg, rng_debug)
    print("Noise mean=%.7f std=%.7f excess-kurtosis=%.7f" % (stats["mean"], stats["std"], stats["excess_kurtosis"]), flush=True)
    symbols = make_symbols(args.symbols, 1)
    jobs = [("robust_proj", "gaussian", False, 20.0)]
    jobs += [("robust_proj", "gaussian", True, snr) for snr in sorted(set(args.snr_values + [20.0]))]
    jobs += [(variant, "gaussian", True, 20.0) for variant in VARIANTS if variant != "robust_proj"]
    if not args.skip_mixed:
        jobs += [(variant, "gaussmix", True, 20.0) for variant in ["plain", "sm_sign", "robust_proj"]]
    cases = []
    selected = None

    def record(result, case_cfg, variant, noise_model, use_noise, mode):
        core = result["core"]
        item = dict(variant=variant, noise_model=noise_model, use_noise=use_noise, snr_db=case_cfg.snr_db if use_noise else None,
                    mode=mode, metrics=result["metrics"], w_fx=core["w_fx"], b_fx=core["b_fx"],
                    w_real=[v / (1 << case_cfg.frac_bits) for v in core["w_fx"]],
                    b_real=[v / (1 << case_cfg.frac_bits) for v in core["b_fx"]],
                    w_hex=[format(v & 0xFFFF, "04X") for v in core["w_fx"]],
                    b_hex=[format(v & 0xFFFF, "04X") for v in core["b_fx"]],
                    w_polyak_fx=core["w_polyak_fx"], b_polyak_fx=core["b_polyak_fx"], counters=core["counters"])
        cases.append(item)
        print("%-7s %-11s %-8s SNR=%-5s BER raw=%.6g -> EQ=%.6g (%d/%d bits)" %
              (mode, variant, noise_model if use_noise else "no_noise", str(item["snr_db"]), item["metrics"]["noeq"]["ber"],
               item["metrics"]["eq"]["ber"], item["metrics"]["eq"]["bit_errors"], item["metrics"]["eq"]["bits"]), flush=True)
        with (output / "partial_results.json").open("w") as stream:
            json.dump(cases, stream, indent=2, allow_nan=False)

    for variant, noise_model, use_noise, snr in jobs:
        case_cfg = replace(cfg, snr_db=snr)
        keep = variant == "robust_proj" and noise_model == "gaussian" and use_noise and snr == 20
        result = run_case(symbols, z_fx, case_cfg, variant, noise_model, use_noise,
                          debug_samples=args.debug_samples if keep else 0, store_tap_history=keep)
        record(result, case_cfg, variant, noise_model, use_noise, "adaptive")
        if keep:
            selected = result
            export_debug(output, cfg, rng_debug, result)
            np.savez_compressed(output / "gaussian_20db_vectors.npz", tx_fx=result["d_fx"], rx_fx=result["r_fx"],
                                y_fx=result["core"]["y_fx"], decisions=result["core"]["decisions"],
                                noise_fx=result["noise_fx"], clean_fx=result["clean_fx"], trace=result["core"]["trace"],
                                tap_after_fx=result["core"]["tap_after_fx"])
    if not args.skip_frozen:
        frozen_cfg = replace(cfg, adapt=False, seed=cfg.seed + 1)
        print("Frozen-tap experiment: independent symbol frame and Taus88 seed...", flush=True)
        independent_z, _ = generate_clt(args.symbols, frozen_cfg, 0)
        result = run_case(make_symbols(args.symbols, 2), independent_z, frozen_cfg, "robust_proj",
                          initial_w=selected["core"]["w_fx"], initial_b=selected["core"]["b_fx"], debug_samples=0)
        record(result, frozen_cfg, "robust_proj", "gaussian", True, "frozen")
    matlab_path = ROOT / "reference" / "full_demo_v26_clt_awgn_fixed_paper.m"
    report = dict(config=asdict(cfg), symbols_per_case=args.symbols, noise_statistics=stats, cases=cases,
                  matlab_source_sha256=hashlib.sha256(matlab_path.read_bytes()).hexdigest(),
                  matlab_runtime_crosscheck=False, python_rng_symbol_seed=1, frozen_symbol_seed=2,
                  elapsed_seconds=time.perf_counter() - started,
                  scope="Numerical core; no original large MC sweeps, ODE/Lyapunov suites, Excel exports or eye-width metrics.",
                  measurement="No-EQ delay 0, EQ delay D; same TX symbols; discard output samples through training.",
                  limitations=["No measured MATLAB/Python bit-for-bit comparison is available.",
                               "Source uses random PAM-4 symbols, not a PRBS transmitter.",
                               "Binomial BER intervals are descriptive: DFE/ISI errors can be correlated.",
                               "Monte Carlo confidence and low-BER tails require more seeds/samples."])
    with (output / "results.json").open("w") as stream:
        json.dump(report, stream, indent=2, allow_nan=False)
    columns = ["mode", "variant", "noise_model", "snr_db", "noeq_ber", "eq_ber", "eq_bit_errors", "measured_bits", "legacy_noeq_ber", "true_symbol_mse", "w0", "w1", "w2", "b0"]
    write_csv(output / "summary.csv", columns,
              [[c["mode"], c["variant"], c["noise_model"] if c["use_noise"] else "no_noise", c["snr_db"],
                c["metrics"]["noeq"]["ber"], c["metrics"]["eq"]["ber"], c["metrics"]["eq"]["bit_errors"],
                c["metrics"]["eq"]["bits"], c["metrics"]["legacy_noeq"]["ber"], c["metrics"]["true_symbol_mse"]]
               + c["w_real"] + c["b_real"] for c in cases])
    make_plots(output, z_fx[:args.stat_samples], cfg, cases, selected)
    export_signal_and_tap_plots(output, cfg, selected)
    print("Done in %.1fs. Results: %s" % (report["elapsed_seconds"], output), flush=True)


if __name__ == "__main__":
    main()
