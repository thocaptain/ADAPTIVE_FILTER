# Channel simulation

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
