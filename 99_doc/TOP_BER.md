# Top-level BER monitoring

The BER monitor is implemented inline in [Top.sv](../00_src/Top.sv). It uses the existing TX Gray reference and selected RX recovered bits. No separate BERT RTL module is instantiated.

## Measurement controls and outputs

| Port | Width | Meaning |
|---|---|---|
| `i_ber_en` | 1 | Enable counting after alignment/startup/training guards pass; 0 pauses counting |
| `i_ber_clear` | 1 | Synchronously clear both counters; does not reset TX/Channel/RX or reference history |
| `o_ber_error_bits` | `BER_COUNTER_WIDTH` | Number of differing bits |
| `o_ber_total_bits` | `BER_COUNTER_WIDTH` | Number of compared bits |
| `o_ber_ready` | 1 | Current reference/data alignment is ready for measurement |
| `o_ber_latency` | 32 | Current TX-reference-to-RX-bit alignment delay, in clocks |

For each eligible symbol, `TX_reference XOR RX_bits` gives two error bits. Their population count adds 0, 1 or 2 to the error counter; the total counter increments by 2. Compute BER as `error_bits / total_bits` only when `total_bits > 0`. Division is left to the host/display logic.

Default counter width is 64 bits. When the next complete two-bit symbol would overflow the total counter, both counters stop together. The largest total is `2^BER_COUNTER_WIDTH-2`; counters do not wrap. Supported widths are 2..64.

## Symbols per clock

`Top.NUMBER_SYMBOL` defaults to 1. Stream buses use two packed dimensions: `[NUMBER_SYMBOL-1:0][width-1:0]`. TX/RX symbols use `[NUMBER_SYMBOL-1:0][3:0]`, Gray buses `[NUMBER_SYMBOL-1:0][1:0]`, Channel samples `[NUMBER_SYMBOL-1:0][7:0]`, and pre-slicer RX samples `[NUMBER_SYMBOL-1:0][15:0]`. Access symbol/sample lane `k` as `bus[k]` and its bit `b` as `bus[k][b]`. Fixed-point formats apply to each lane; coefficient and configuration ports retain their current widths. Use `$signed(bus[k])` when interpreting an individual packed lane in signed arithmetic.

Only `NUMBER_SYMBOL=1` is currently implemented. Top rejects other values with `$fatal` to prevent partial processing or incorrect BER totals. Supporting `NUMBER_SYMBOL>1` requires matching child-module interfaces, chronological lane packing, cross-lane Channel/FFE/DFE/LMS state handling, training scheduling and symbol-aware BER alignment/counting. A wider packed bus alone does not implement parallel processing. Latency parameters remain in clocks and FFE_SYMBOL_DELAY remains in symbols.

## Latency contract

The parameters describe the implemented pipeline; they do not insert pipeline registers into the child modules or discover latency automatically.

| Parameter | Default | Definition |
|---|---|---|
| `TX_LATENCY` | 1 | Startup clocks until the first actual TX symbol/reference is available |
| `CHANNEL_LATENCY` | 1 | Registered Channel latency |
| `FFE_LATENCY` | 0 | RX input/FFE pipeline latency |
| `DFE_LATENCY` | 0 | RX DFE/cancellation pipeline latency |
| `SLICER_LATENCY` | 1 | Slicer/Gray output pipeline latency |
| `FFE_SYMBOL_DELAY` | 1 | Algorithmic symbol target delay when FFE is active |
| `BER_SKIP_TRAINING` | 1 | Exclude the initial `TRAIN_LEN` RX samples |

```text
RX_PIPELINE = FFE_LATENCY + DFE_LATENCY + SLICER_LATENCY
PATH_DELAY  = CHANNEL_LATENCY + RX_PIPELINE
BER_DELAY   = PATH_DELAY + (latched_ffe_bypass ? 0 : FFE_SYMBOL_DELAY)
```

`o_ber_latency` reports BER_DELAY. TX pipeline latency is excluded from this delay because the checkpoint is already the TX output `TX_bits_ref`; TX_LATENCY is used for startup qualification. With defaults, BER_DELAY is 3 clocks for FFE-active modes and 2 for FFE-bypassed modes.

Bypass and processing paths must have equal physical pipeline latency, as already specified for RX. Additional RX input registers belong in FFE_LATENCY; output/Gray registers belong in SLICER_LATENCY. If the implementation changes a recurrence or target symbol delay, update the timing contract and RX training alignment together.

The default RX startup and training-reference parameters now follow the declared stages:

```text
RX_STARTUP_CYCLES   = TX_LATENCY + CHANNEL_LATENCY
TX_REF_DELAY_CYCLES = CHANNEL_LATENCY + FFE_LATENCY + DFE_LATENCY
```

These existing RX parameters can still be explicitly overridden when the actual module schedule requires it.

## Select the measurement point

| Latched FFE bypass | Latched DFE bypass | Measurement through RX slicer/Gray output |
|---|---|---|
| 0 | 0 | After FFE + DFE |
| 0 | 1 | FFE only |
| 1 | 0 | DFE only |
| 1 | 1 | Raw Channel |

The comparator always receives `RX_bits`, after the slicer/demapper. Analog/fixed-point FFE/DFE amplitudes are not bit labels. The selected bypass configuration determines which equalizer result reaches that decision point. This is one monitor for the selected mode, rather than simultaneous independent FFE and DFE counters.

FFE bypass is latched on `i_cfg_load`, matching the RX contract. Changing a bypass input without loading does not change BER alignment.

## Startup, training and configuration changes

The TX Gray history shifts every clock, even when counting is disabled. The age guard excludes initial TX placeholders and pipeline fill. With BER_SKIP_TRAINING=1 it also waits for the first post-training RX decision to reach the comparator. The monitor observes the previously registered RX output at the active edge, and selects the matching TX history entry for that same observation.

Both counters clear automatically on:

- Global reset.
- RX coefficient/bypass load (`i_cfg_load`).
- Channel SNR load (`i_cfg_noise_load`).
- A change to runtime noise enable or adaptation enable.

Configuration changes also suppress measurement for the maximum alignment-delay settling interval. TX history continues shifting; the data stream, RNG and equalizer histories are not paused by BER logic. `i_ber_clear` clears the measurement alone and does not repeat training.

Training age is measured from global reset. As specified for RX, coefficient/config loads do not restart the RX training counter. Starting a fresh training run requires the normal chain reset sequence.

Recommended use: set the intended configuration, keep i_ber_en=0 during setup, pulse i_ber_clear if needed, wait for o_ber_ready, then assert i_ber_en for the desired measurement interval. Deassert i_ber_en before reading a stable snapshot of both counts.

## Verification scope

The actual Top.sv BER logic was compiled and simulated with the installed Verilator using temporary behavioral transport/error-injection fixtures. Eight parameter combinations covered nonzero/zero pipeline latency, algorithmic delays 0/1/2, training inclusion/exclusion and reduced counter widths for overflow checks, plus the default 64-bit/3000-training-sample configuration. The scenarios checked error-free alignment over a PRBS period, 0/1/2-bit injected errors, pause/clear, counter saturation, all four bypass modes, configuration epochs and reset.

The fixtures are not DSP implementations of TX/Channel/RX and were kept outside the repository. Real chain BER remains dependent on the eventual RTL modules and their agreed pipeline schedules. No Python reference co-simulation was used.
