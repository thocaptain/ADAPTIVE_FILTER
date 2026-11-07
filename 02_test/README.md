# FFE / DFE Tests

The main guide, run commands, and C++/SV model diagrams are available in
[eq_independent/README.md](eq_independent/README.md).

```bash
cd ~/adaptive_eq/02_test/eq_independent
make MODE=DFE_ONLY TEST=FIXED
make MODE=FFE_ONLY TEST=LMS N=4096
make MODE=FFE_DFE TEST=LMS N=10000 OPENWAVE=1
make clean
```

You can also run from the repository root with `make -C 02_test MODE=... TEST=...`.
Logs and waveforms are always saved directly in `02_test/eq_independent`.
The suite uses C++17 and Verilator; Python and MATLAB are not required.

For a specific pipeline setting, pass `PIPELINE=0` or `PIPELINE=1` (no spaces
around `=`). If omitted, the selected SystemVerilog top module's default is used:

```bash
make -C 02_test MODE=DFE_ONLY TEST=FIXED PIPELINE=1
make -C 02_test MODE=DFE_ONLY TEST=FIXED PIPELINE=0
```

## Full regression

The test Makefile currently provides 16 regression cases:

- 6 FFE/DFE comparisons: three modes (`FFE_ONLY`, `DFE_ONLY`, `FFE_DFE`) with
  both `FIXED` and `LMS` profiles.
- 10 block-BER configurations in `ber/`.

Run all cases from the repository root:

```bash
make -C 02_test regression
```

The regression continues after individual failures, prints a final passed/failed
case count, and saves detailed output to `02_test/regression.log`. The command
returns a nonzero status if any case fails.

To run every FFE/DFE regression case with the same pipeline setting, pass it to
the regression target:

```bash
make -C 02_test regression PIPELINE=1
make -C 02_test regression PIPELINE=0
```

Omitting `PIPELINE` uses each selected top module's default.
