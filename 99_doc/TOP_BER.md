# Top-level block BER monitoring

The BER monitor is implemented inline in [Top.sv](../00_src/Top.sv). It compares recovered RX Gray labels with the delayed TX Gray reference. [Top_wrapper.sv](../00_src/Top_wrapper.sv) exposes configuration and coherent counter snapshots through AXI4-Lite.

## Block ordering and interfaces

`NUMBER_SYMBOL=N` is the number of consecutive symbols processed per clock. Packed buses use `[N-1:0][width-1:0]`: TX/RX amplitudes have 4 bits per lane, Gray labels 2, Channel samples 8 and pre-slicer samples 16. Lane `[0]` is the earliest symbol in a block; lane `[N-1]` is latest. The next clock continues that same stream. Coefficients and configuration remain shared scalar ports. Cast `$signed(bus[k])` when using one packed amplitude lane in signed arithmetic.

Top forwards NUMBER_SYMBOL to `tx_top`, `channel_top` and `rx_top`. Each child must implement those packed interfaces and its state progression across lanes/block boundaries. Changing the bus width alone does not implement parallel DSP. There are no stream valid/ready ports: steady operation carries one complete N-symbol block every clock, without padded or idle lanes.

## Measurement controls and outputs

| Port | Width | Meaning |
|---|---|---|
| `i_ber_en` | 1 | Count eligible lanes when 1; pause when 0 |
| `i_ber_clear` | 1 | Synchronously clear counters without resetting the stream/history/training age |
| `o_ber_error_bits` | `BER_COUNTER_WIDTH` | Number of differing bits across all counted lanes |
| `o_ber_total_bits` | `BER_COUNTER_WIDTH` | Number of compared bits across all counted lanes |
| `o_ber_ready` | 1 | At least one lane is eligible and configuration settling has completed |
| `o_ber_latency` | 32 | Maximum TX history age needed by the selected mode, in clocks |

For each eligible lane k, count the set bits in `RX_bits[k] XOR aligned_TX_bits[k]` (0, 1 or 2 errors). Sum across the eligible lanes and add `2*eligible_lane_count` to the total. A complete steady-state block adds `2*N` total bits and 0..`2*N` error bits. BER is `error_bits/total_bits`, calculated on the CPU only when total is nonzero. It is a bit-error ratio, not a ratio of erroneous blocks.

Example: N=4, three eligible symbols with error counts 0/1/2 add 3 errors and 6 compared bits. A complete error-free N=4 block adds 0 errors and 8 bits. The per-block increment width is `$clog2(2*N+1)`, so the all-bits-wrong block cannot overflow the increment.

Counters default to 64 bits, supported range 2..64. They must be wide enough to represent a complete `2*N`-bit increment. If the next eligible block would overflow the total counter, both counters retain their values; no block is partially counted to fill the remaining capacity. The largest reachable total depends on block size and any initial partial block, is even, and is at most `2^BER_COUNTER_WIDTH-2`.

## Clock latency and symbol alignment

The latency parameters describe implemented child pipelines; they do not insert registers into those children or acquire alignment automatically.

| Parameter | Unit | Default |
|---|---|---|
| `TX_LATENCY` | Startup clocks until first actual TX block/reference | 1 |
| `CHANNEL_LATENCY` | Clocks | 1 |
| `FFE_LATENCY` | Clocks, including RX input pipeline | 0 |
| `DFE_LATENCY` | Clocks | 0 |
| `SLICER_LATENCY` | Clocks, including Gray output registers | 1 |
| `FFE_SYMBOL_DELAY` | Algorithmic target delay in symbols, when FFE is active | 1 |
| `TRAIN_LEN` | RX symbols, not blocks/clocks | 3000 |
| `BER_SKIP_TRAINING` | 1 excludes the initial training symbols | 1 |

```text
RX_PIPELINE = FFE_LATENCY + DFE_LATENCY + SLICER_LATENCY
P = CHANNEL_LATENCY + RX_PIPELINE                 // physical block clocks
D = latched_ffe_bypass ? 0 : FFE_SYMBOL_DELAY     // algorithmic symbols
Q = D / N
R = D % N
reference_age(k) = P + Q + (k < R ? 1 : 0)
reference_lane(k) = (k + N - R) % N
```

RX lane k uses `TX_history[reference_age(k)][reference_lane(k)]`. This is the chronological TX symbol at `(t-P)*N+k-D` for RX block t. In particular, D=1 with N>1 is not an extra whole-block clock delay for every lane.

For N=4 and D=1:

| RX lane in block t | Matching TX reference |
|---|---|
| 0 | block `t-P-1`, lane 3 |
| 1 | block `t-P`, lane 0 |
| 2 | block `t-P`, lane 1 |
| 3 | block `t-P`, lane 2 |

The same quotient/remainder mapping handles D>=N and exact multiples of N. FFE bypass sets D=0 and compares every lane with the same lane P clocks earlier. Physical bypass paths must have the same clock latency as their processing paths.

`o_ber_latency = P + ceil(D/N)` reports the maximum required history age. Some lanes can use a newer history block. It is not a claim that every lane has that many whole-clock delays. TX_LATENCY is used only for startup qualification because the stored reference checkpoint is already the TX output. With N=1/defaults, the reported value remains 3 clocks for FFE active and 2 for FFE bypass.

The RX defaults remain `RX_STARTUP_CYCLES=TX_LATENCY+CHANNEL_LATENCY` and `TX_REF_DELAY_CYCLES=CHANNEL_LATENCY+FFE_LATENCY+DFE_LATENCY`. The latter remains a clock count; the RX must apply algorithmic symbol alignment separately. Override these only to match the actual module schedule.

## Startup and training boundaries

Let a be completed clocks since reset and `B=RX_STARTUP_CYCLES+RX_PIPELINE`. RX processed-symbol index for lane k is `(a-B)*N+k`. The monitor excludes a lane until that index is at least `TRAIN_LEN` (or 0 when BER_SKIP_TRAINING=0). Independently, the lane's TX reference is valid only when `a >= TX_LATENCY+reference_age(k)`.

These guards are per lane, including when training or initial reference fill ends inside a block. For N=4/TRAIN_LEN=5, training covers the first full block plus lane 0 of the next block; the remaining three lanes can add 6 bits if their TX references are valid. `o_ber_ready` can therefore assert for a partial block; the reported total always reflects the exact number of compared bits.

The TX history shifts every clock while BER is paused or cleared. The comparator observes the pre-edge RX output and matching pre-edge TX history; counters update on that edge. Age saturates after all lanes can be eligible.

## Measurement point and configuration

| Latched FFE bypass | Latched DFE bypass | Selected measurement |
|---|---|---|
| 0 | 0 | After FFE + DFE |
| 0 | 1 | FFE only |
| 1 | 0 | DFE only |
| 1 | 1 | Raw Channel |

One monitor follows the selected post-slicer/Gray RX output. Bypass flags apply only on `i_cfg_load`; changing an unloaded flag does not change alignment.

Global reset, RX config load, Channel SNR load, and changes to noise/adaptation enable clear both counters. Config changes also suppress measurement until the worst-case history interval has settled. A loaded mode never mixes old/new pipeline blocks into a counted block. Explicit BER clear does not repeat that settling interval or restart training. RX config loads do not restart training age; starting a fresh training run requires chain reset.

The existing AXI register map and snapshot mechanism are unchanged. Both aggregate counters and latency are captured on the same edge; the CPU reads stable 32-bit low/high halves. Diagnostic sample registers still read lane 0 only, independently from block BER accumulation. See [AXI README](../00_src/axi/README.md).

## Reproducible verification

Run `make -C 02_test/ber test` from the repository root. The permanent [C++/Verilator regression](../02_test/ber/README.md) checks the actual Top against chronological TX symbol history, using isolated behavioral transport/error-injection fixtures. It checks exact error/bit totals on every clock, upper-lane-only errors, all lanes wrong, cross-block alignment, partial training/startup blocks, pause/clear, saturation, all modes, config settling and global reset.

The ten cases cover N=1/2/3/4/8; symbol delays 0/1/3/5/6, including greater-than-block and exact-block delays; zero/nonzero pipelines; TX startup 0/1/2; training enabled/disabled; and 4/8/64-bit counters. The N=1 case includes default 3000-symbol training and 64-bit counters. Fixtures do not implement DSP, AWGN or LMS; full chain numerical BER still depends on the team-provided child RTL and its agreed lane/state/latency contract. No Python reference co-simulation is used.
