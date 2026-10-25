# TX / RX / Channel Simulation

Run the commands in WSL from the `10_sim` directory:

```bash
cd /home/lqhau/adaptive_eq/10_sim
make help
```

## Select a module

```bash
make sim MODULE=tx       # Build TX
make run MODULE=tx       # Build and run TX
make run MODULE=rx       # Build and run RX
make run MODULE=channel  # Build and run Channel
```

Equivalent shortcuts:

```bash
make tx
make rx
make channel
```

Each build uses one `tb_top` and its corresponding `tp_top.cpp` driver.

## Directory structure

```text
10_sim/
|-- makefile
|-- conf.vlt
|-- flist                # Default TX file list
|-- tx/flist
|-- rx/flist
|-- channel/flist
`-- build/               # Generated during build/run
    |-- tx/
    |-- rx/
    `-- channel/
```

| Module | RTL wrapper | Testbench | Driver |
|---|---|---|---|
| tx | `00_src/tx/tx_top.sv` | `01_bench/tx/tb_top.sv` | `01_bench/tx/tp_top.cpp` |
| rx | `00_src/rx/rx_top.sv` | `01_bench/rx/tb_top.sv` | `01_bench/rx/tp_top.cpp` |
| channel | `00_src/channel/channel_top.sv` | `01_bench/channel/tb_top.sv` | `01_bench/channel/tp_top.cpp` |

Paths in this table are relative to the project root. Paths inside each `flist` are relative to `10_sim`, where the Makefile runs Verilator. Add RTL packages and dependencies to `tx/flist`, `rx/flist`, or `channel/flist` before the corresponding wrapper.

The Makefile runs `verilator --cc --exe`, then builds the generated code with `make`. Clock and reset are driven by C++. Waveforms use VCD to match the current drivers.

## Channel noise configuration

```bash
make run MODULE=channel NOISE_EN=1 SNR_DB=25
make run MODULE=channel NOISE_EN=0 SNR_DB=20
# Shortcut
make channel NOISE_EN=1 SNR_DB=15
```

| Option | Default | Driver pin / meaning |
|---|---|---|
| `NOISE_EN` | `1` | `i_noise_en`: 0 disables noise addition, 1 enables it |
| `SNR_DB` | `20` | `i_cfg_snr_db[7:0]`: unsigned integer dB, encoding 0..255 |

These options are passed to the Channel executable as `+noise_en` and `+snr_db`. The driver keeps noise disabled during the 10 reset clocks, pulses `i_cfg_noise_load` for one clock after reset, then applies `NOISE_EN`. They do not change TX/RX simulation arguments or the Channel reset parameter `DEFAULT_SNR_DB`.

The Makefile and driver validate the encoding range; supported SNR values and dB-to-gain conversion still belong to the Channel RTL implementation. These inputs currently configure the bench stimulus, without a functional noise checker.

## Lint, waveforms, and cleanup

```bash
make lint MODULE=tx
make list MODULE=rx
make wave MODULE=channel
make clean MODULE=rx
```

`make wave` opens an existing waveform in GTKWave. For example, after running Channel, its waveform is `build/channel/channel_clock_reset.vcd`. The executable is `build/<module>/obj_dir/Vtb_top`.

`make clean MODULE=rx` removes only `build/rx`.

You can also run commands from the project root:

```bash
make -C 10_sim run MODULE=tx
```

`JOBS` defaults to 2. `SEED` controls Verilator's runtime seed, independently of PRBS/noise seeds in the RTL parameters:

```bash
make run MODULE=tx JOBS=4 SEED=1
```

The three RTL directories currently contain design documentation. Until `tx_top.sv`, `rx_top.sv`, and `channel_top.sv` are implemented, the `check` target reports the missing source file. Module selection has been verified with dry runs for all three modules; RTL simulation has not been run.
