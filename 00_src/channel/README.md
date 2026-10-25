# Channel

Source: [BLOCK_DIAGRAM_DESIGN_FLOW.txt](../../99_doc/BLOCK_DIAGRAM_DESIGN_FLOW.txt), draft 1.0.

[TX](../tx/README.md) | [Channel](../channel/README.md) | [RX](../rx/README.md) | [Top.sv](../Top.sv)

## External interface

Selected data interface: signed 4-bit integer input -> signed 8-bit Q4.4 output.
Internal submodules, coefficient widths and intermediate arithmetic widths are not yet frozen.

```text
  TX signed4 integer symbol -> CHANNEL (ISI + noise) -> RX signed8 Q4.4 sample
```

The eight output bits are TOTAL bits: 1 sign + 3 other integer bits + 4 fractional bits.
This selection reduces output precision relative to the unchanged Python model's 16-bit Q4.12.

| Signal | Direction | Bits | Representation | Value range | Meaning |
| --- | --- | --- | --- | --- | --- |
| i_sym[3:0] | Input | 4 | Signed integer / Q4.0 | Legal levels: {-3,-1,+1,+3}; stored integer equals amplitude. | One new TX symbol on each clock during continuous operation. |
| i_clk | Input | 1 | Clock | {0,1}; frequency not yet selected. | Common synchronous clock. |
| i_rst_n | Input | 1 | Active-low reset | {0,1} | Initialize Channel sample history and pipeline registers on reset. |
| o_r[7:0] | Output | 8 | Signed fixed-point Q4.4 | Representable real range: -8 .. +7.9375. Stored integer: -128 .. +127. LSB=0.0625. | One impaired sample r[n] each clock after pipeline fill, including ISI and noise. |

## 2.1 OUTPUT REPRESENTATION / QUANTIZATION

- Real value = signed stored integer / 16. LSB = 1/16 = 0.0625.
- Output signed integer range: -128..+127. Output real range: -8..+7.9375.
- Example: +0.5 is stored as integer +8 / hex 08; -0.5 is stored as -8 / hex F8.
- The ISI profile r_clean[n]=s[n]+0.5*s[n-1] can create half-integers; these are exactly representable in Q4.4.
- Injected noise is rounded to the selected output grid; its fine details below one LSB cannot all be retained.
- If internal arithmetic has more than four fractional bits, round to nearest with half ties away from zero, then saturate to signed 8 bits.
- For an internal integer r_int with F>=4 fractional bits: o_r_int = clip(round_away(r_int / 2^(F-4)), -128, 127).
- If an internal result is already in F=4 units, do not apply an additional fractional shift.
- Use wider intermediate products/sums to preserve the computation until the selected final rounding/saturation point.
- Proposed amplitude output declaration: output logic signed [7:0] o_r.

## 2.2 CURRENT-PROFILE VALUE BOUNDS

- TX input legal set: {-3,-1,+1,+3}.
- Clean ISI sample for h0=1,h1=0.5: [-4.5,+4.5].
- The saved higher-precision model's 12-lane CLT at fixed sigma_Q=0.25 bounds the injected noise by [-1.499755859375,+1.49951171875].
- The corresponding pre-output-quantization sample bound is [-5.999755859375,+5.99951171875].
- Rounding those samples to Q4.4 gives a conservative output bound [-6,+6], or signed output integers [-96,+96].
- These configuration bounds fit within the selected Q4.4 format [-8,+7.9375].
- Exact ranges will be revisited if the Channel internal/noise precision or profile is changed.
- The Python model and its measured BER remain at Q4.12. BER/equalization accuracy at the new Q4.4 boundary has not yet been measured; this step edits the design document only.

## 2.3 CONTINUOUS FLOW / FIXED TIMING BOUNDARY

- The Channel data interface has only i_sym[3:0] and o_r[7:0], alongside the required common clock and reset.
- No per-symbol valid input or output is used. Every clock during steady operation represents one new symbol index n.
- Advance Channel symbol-history memory and noise generation once per symbol clock after reset.
- Keep a fixed pipeline latency L_CH, with no stalls. Exact latency is still to be specified.
- After pipeline fill, produce one o_r sample per clock in the same order as the input symbols.
- RX receives signed Q4.4 o_r[7:0] and must support one sample per clock in this continuous-flow design.
- Recommended RX coefficient/internal formats are specified in section 3; the external input remains signed8 Q4.4.
- Count startup cycles at the top level to begin measurement/training after pipeline fill; do not interpret reset/fill values as transmitted PAM-4 symbols.
- Align measurement/training references with the fixed Channel and RX latencies and the equalizer's symbol delay. Specify these separately when RX is defined.
- Coefficient/noise configuration ports will be decided when the Channel submodules are defined; these do not qualify individual data samples.

## Sources / decisions

- Current Python model: retained without modification; its random-symbol stream is separate from this implementation proposal.
- User-selected Channel output interface: signed 8-bit Q4.4 (8 total bits, 4 fractional bits).
- User-selected timing: continuous TX and one-symbol-per-clock Channel; remove per-symbol valid ports and use fixed pipeline timing.

This README contains the corresponding design section from the source document.
