# Channel block simulation

## Current Q4.12 ISI + AWGN / SNR-register bench

Run from the project root in WSL/Linux:

```bash
make -C 10_sim/channel -f isi_awgn.mk lint run
make -C 10_sim/channel -f isi_awgn.mk wave
make -C 10_sim/channel -f isi_awgn.mk snr-wave
```

Block sources:

- `00_src/channel/channel_top.sv`: live RTL under test.
- `01_bench/channel/isi_awgn.cpp`: stimulus, exact arithmetic/valid scoreboard,
  register-load checks, main noise capture and SNR sweeps.
- `01_bench/channel/psd_check.h`: Welch PSD acceptance, tone calibration and
  equal-power colored-noise rejection.
- `01_bench/channel/check_awgn_model.py`: first 4096 captured samples compared
  with scalar RNG functions in the existing project Python reference.
- `01_bench/channel/check_snr_capture.py`: independent SNR measurement from
  actual captured outputs and the original RTL VCD.
- `10_sim/channel/isi_awgn.mk`: isolated build/run/wave targets.

Requirements: Verilator, make, g++, Python 3 standard library; GTKWave for viewing.
No NumPy/SciPy is needed for these checks. Results are generated under
`10_sim/build/channel_awgn/`, covered by the existing `10_sim/.gitignore`.
Waveforms, binary captures and build objects are generated locally, not source files.

The complete run checks one million samples at SNR=20 dB, h1=0, plus twelve
200,000-sample SNR configurations and directed ISI/reset/valid/configuration cases.
All 0..40 dB settings are checked at five ISI coefficients for gain/readback.

`wave` opens the original RTL VCD. `snr-wave` opens a separate monitor view
derived from actual captures; compare `expected_snr_db`, `measured_snr_db` and
`snr_error_db` only when `monitor_valid=1`. This monitor is testbench software,
not an additional FPGA SNR-estimator circuit.

Interface, calibration assumptions and four-clock sample latency are documented
in [the channel handoff specification](../../00_src/channel/README.md).

## Legacy interface harness

The original `tb_top.sv` / `tp_top.cpp` harness below targets a different
NUMBER_SYMBOL/Q4.4 interface. It is retained for reference and is not compiled
by `isi_awgn.mk`. Use the commands above with the current channel RTL.

Run from `10_sim`:

```bash
make run MODULE=channel NOISE_EN=1 SNR_DB=25
make run MODULE=channel NOISE_EN=0 SNR_DB=20
make wave MODULE=channel
```

- `NOISE_EN`: 0 or 1, default 1.
- `SNR_DB`: unsigned8 integer dB encoding, default 20.
- Reset is low for 10 clocks, followed by a one-clock `i_cfg_noise_load` pulse with noise disabled. The selected `i_noise_en` is then applied.
- Sources are listed in [flist](flist); the driver is [tp_top.cpp](../../01_bench/channel/tp_top.cpp).
- The Channel RTL contract is documented in [00_src/channel/README.md](../../00_src/channel/README.md).
- Executable/waveform outputs are isolated under `10_sim/build/channel/`.

`00_src/channel/channel_top.sv` and its dependencies must be supplied before building. No Channel arithmetic or dB-to-gain conversion is implemented by this simulation configuration.
