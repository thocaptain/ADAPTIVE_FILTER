# Python model from the MATLAB v26 reference

Source: `reference/full_demo_v26_clt_awgn_fixed_paper.m`.
Executable: `01_bench/full_demo_v26_clt_awgn_fixed_paper.py`.

This is the first numerical port for main_task 1, step B. It runs independently
of MATLAB and its VS Code extensions. The original MATLAB source is unchanged.
There is no MATLAB/Python runtime comparison yet, so bit-for-bit equivalence
across the two runtimes has **not** been established.

## Run

Run from the repository root in WSL/Linux:

```bash
python3 01_bench/full_demo_v26_clt_awgn_fixed_paper.py
```

Default experiment:

- One million noise samples, twelve Taus88/CLT lanes, source seed `0x0A5B`.
- 200,000 symbols per case; 3,000 training samples; decision delay D=1.
- No-noise case and Gaussian channel-output SNR 15/20/25 dB.
- All five source EQ variants at 20 dB: plain, sm_sign, robust, proj, robust_proj.
- Gaussian-mixture impulse noise at 20 dB for plain, sm_sign, robust_proj.
- An additional frozen-tap case: use the final 20 dB robust_proj taps on a new
  symbol frame and a new Taus88 seed, with adaptation disabled.
- Numeric outputs and a plot in `10_sim/python_v26/`.

The installed dependencies are NumPy, SciPy and Matplotlib. If needed in another
environment, install `01_bench/requirements-python-model.txt`.

For a smaller smoke run:

```bash
python3 01_bench/full_demo_v26_clt_awgn_fixed_paper.py \
  --symbols 6000 --stat-samples 10000 --debug-samples 128 \
  --output 10_sim/python_v26_smoke --skip-mixed
```

For numerical contract checks:

```bash
python3 -m unittest discover -s 02_test -p test_v26_python_model.py -v
```

## Translation scope

| MATLAB reference | Python implementation |
| --- | --- |
| Taus88 stepping, lane seeding, bit mixing/windows | `taus88_step`, `seed_mix32`, `stage1_offsets` |
| CLT summation, discrete centering, gain tuning | `generate_clt`, `clt_parameters` |
| Q4.12 conversion, arithmetic shifts, saturation | `q_from_real`, `q_mul`, `q_sat` |
| Channel `s[n] + ISI*s[n-1]`, noise scaling/impulses | `run_case` |
| Five DFE-LMS variants, Q20/40-bit accumulators | `dfe_core` |
| Training, decision-directed gating, clipping/projection | `dfe_core` |
| Polyak coefficient averages and learning traces | `dfe_core` |
| Gray BER/SER | `error_counts`, `run_case` |
| Noise histogram, moments, tails, ACF, bit-true CLT PMF | `noise_statistics`, `bittrue_reference` |
| Per-sample Excel debug data | CSV/hex/NPZ exports |

The initial port does not include the original large Monte Carlo sweeps,
projected ODE, Lyapunov, decreasing-step validation suites, or reconstructed-eye
height/width/jitter metrics. It retains the decreasing-step update option in the
core. The new plot shows symbol decision distributions, not an analog eye.

## Numerical conventions

- Signed Q4.12 signals and visible coefficients saturate to [-32768, 32767].
- Each product is shifted right by 12 and saturated **before** summation,
  following the MATLAB filtering core; it is not a single full-precision MAC.
- Signed right shift rounds toward negative infinity. See the
  [MathWorks bitshift documentation](https://www.mathworks.com/help/matlab/ref/bitshift.html).
- Conversion and coefficient updates use round-to-nearest with halves away
  from zero, matching MATLAB `round` rather than NumPy's default tie rule.
- Adaptation accumulators have 20 fractional bits and a signed 40-bit bound.
- The default slicer preserves the source's nearest-level/minimum-index rule:
  exact thresholds -2, 0, +2 select -3, -1, +1. README's inequality convention
  selects -1, +1, +3 instead. The implementation exposes both tie rules in Config.
- CLT uses the exact discrete center 12*4095/2 = **24570**, not 24576.
- The symbol stream is a seeded MT19937 random PAM-4 stream, as in the MATLAB
  reference's general approach. It is **not PRBS-7/15**, and the precise MATLAB
  `randi` sequence has not been cross-validated. Noise lane recurrences and seed
  formulas are explicitly ported, with per-lane debug exports for later checks.

## BER measurement and source diagnostics

The MATLAB `ser_ber_from_decisions` helper shifts both the raw and EQ branches
by D. The raw branch has no such decision delay, so its comparison is misaligned.
The Python output retains this as `legacy_noeq` for diagnosis.

Primary `noeq`/`eq` measurements use their own delays (0 and D), exclude training,
and compare the **same transmitted symbols**. With the default experiment that
means 197,000 symbols / 394,000 bits per case. Legacy fields include the original
training period and are labelled separately in JSON/CSV.

The tests include an ideal delayed link where aligned raw/EQ errors are zero,
while the legacy raw BER exceeds 0.4. Another independent oracle sets known
FFE=[0,1,0], DFE=[0.5], which exactly cancels the noiseless first postcursor.

Decision-directed MSE compares output to the slicer's own decision after
training; it can look small even with wrong decisions. `true_symbol_mse`
therefore also compares output to the actual aligned transmitted symbol.

## Interpretation limits

The reference still adapts taps throughout the frame, while README's course
scope is static configurable coefficients. The separate frozen case is an
offline-training/online-fixed-coefficient demonstration, not an implementation
of an adaptive RTL engine or a proof that these taps are optimal.

This run uses h0=1, h1=0.5, following the MATLAB source. README's h0=0.8 and other
channel presets still need separate modelling and coefficient evaluation.

Zero observed errors is a finite-frame result, not a proven zero BER. The
reported binomial intervals and chi-square p-values are diagnostic iid
approximations: ISI/DFE errors and deterministic PRNG outputs can be correlated.
A finite CLT sum is also not exactly Gaussian, especially in its tails.

## Output files

- `results.json`: config, source hash, statistics, counters, taps, BER/SER and scope.
- `summary.csv`: compact case comparison including legacy raw BER.
- `overview.png`: noise histogram, tap evolution, symbol clusters and measured BER.
- `lane_initial_states.json`, `lane_debug.csv`: seeds and first 64 lane samples.
- `eq_debug_trace.csv`, `eq_debug_hex.csv`: first 12,800 20 dB EQ samples.
- `gaussian_20db_vectors.npz`: full 20 dB stimulus/output arrays and tap traces.
  New runs also store `tap_after_fx`, the visible coefficients after every
  sample's update, including the exact final sample.
- `partial_results.json`: completed cases, also updated during long runs.
- `artifact_validation.json`: same-window alignment comparison and exported-vector consistency checks.
- `run.log`: console output when captured by the run command.

Additional signal/tap exports on new runs:

- `tx_rx_signals.png` / `.pdf`: 64 TX symbols, channel input to EQ, equalized
  samples and recovered symbols. EQ output sample n+D is aligned with TX n.
- `tx_rx_signals.csv`: the exact plotted sample indices and amplitudes.
- `adaptive_taps.png` / `.pdf`: initial convergence and the last 10% of the frame,
  with exact final values and the no-noise reference shown separately.
- `adaptive_taps_summary.json` / `.csv`: final post-update taps, taps used to
  compute the last output, and mean/std/min/max of the complete last 10% history.
- `adaptive_taps_trace.csv`: decimated tap history plus the exact final sample;
  the full per-sample history is in the NPZ above.

The signal/tap rerun is saved separately with:

```bash
python3 01_bench/full_demo_v26_clt_awgn_fixed_paper.py \
  --output 10_sim/python_v26_signals
```

Tap values in the new figures are **after** each update. The sample's filtered
output was computed using coefficients **before** that update. Both quantities
are reported explicitly; the final value is not inferred from a decimated trace.
The last-10% mean is an empirical average of visible Q4.12 taps, distinct from
the source's Polyak average of the higher-precision adaptation accumulators.

Measured findings from the actual run are recorded in `99_doc/PYTHON_V26_RESULTS.md`.
