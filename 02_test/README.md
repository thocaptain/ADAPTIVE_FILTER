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
