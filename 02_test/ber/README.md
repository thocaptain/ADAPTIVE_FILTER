# Block BER regression

Run from the repository root:

```sh
make -C 02_test/ber test
```

Requires Verilator, a C++17 compiler and GNU Make. The flow supports Verilator 4.028 (generate C++, then build the generated Makefile). Build products/logs stay in ignored `build/<case>/` directories.

The regression compiles the actual `00_src/Top.sv` with isolated behavioral TX/Channel/RX transport fixtures. Compile these fixtures only for this test, separately from the real child RTL. The fixtures are not DSP or AWGN/LMS implementations. No Python reference or co-simulation is used.

The C++ checker records every observed TX symbol in chronological order and uses absolute symbol indices to calculate which RX lanes are eligible after startup/training. It independently checks the observed RX decisions, exact bit/error totals on every clock, all-lane error injection, highest-lane-only errors, counter saturation, pause/clear, all bypass modes, configuration settling and reset. The RX transport fixture uses a symbol FIFO to exercise delay across block boundaries.

Cases cover NUMBER_SYMBOL=1/2/3/4/8, target delays 0/1/3/5/6, exact/non-exact block delays, partial training blocks, initial reference placeholders, zero/nonzero physical latency, training enabled/disabled and small counters. `serial` also covers the default 64-bit/3000-symbol training setup.

An individual configuration can be run with:

```sh
make -C 02_test/ber run CASE=custom N=4 D=5 TRAIN=7 CW=16
```

The fixture/checker supports at most 16 lanes (32 injected bits). Production BER RTL is parameterized independently of that test-driver limit. Full chain numerical behavior still requires the team-provided RTL and golden model.
