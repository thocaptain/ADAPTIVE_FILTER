# Channel

Source: [BLOCK_DIAGRAM_DESIGN_FLOW.txt](../../99_doc/BLOCK_DIAGRAM_DESIGN_FLOW.txt), draft 1.1.

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
| i_noise_en | Input | 1 | Logic | {0,1} | 0: ISI only; 1: add AWGN at the loaded SNR. Sampled each symbol clock. |
| i_cfg_snr_db[7:0] | Input | 8 | Unsigned integer dB | 0..255 dB encoding | SNR configuration; 20 means 20 dB. Latched on i_cfg_noise_load. |
| i_cfg_noise_load | Input | 1 | Synchronous load | {0,1} | Pulse for one clock to load i_cfg_snr_db independently of RX coefficient loading. |
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

- The sample interface is i_sym[3:0] -> o_r[7:0], with common clock/reset and separate runtime noise/SNR controls.
- No per-symbol valid input or output is used. Every clock during steady operation represents one new symbol index n.
- Advance Channel symbol-history memory and noise generation once per symbol clock after reset.
- Keep a fixed pipeline latency L_CH, with no stalls. Exact latency is still to be specified.
- After pipeline fill, produce one o_r sample per clock in the same order as the input symbols.
- RX receives signed Q4.4 o_r[7:0] and must support one sample per clock in this continuous-flow design.
- Recommended RX coefficient/internal formats are specified in section 3; the external input remains signed8 Q4.4.
- Count startup cycles at the top level to begin measurement/training after pipeline fill; do not interpret reset/fill values as transmitted PAM-4 symbols.
- Align measurement/training references with the fixed Channel and RX latencies and the equalizer's symbol delay. Specify these separately when RX is defined.
- Runtime noise/SNR ports are specified below; Channel coefficient and internal gain conversion details remain to be defined.

## 2.4 RUNTIME NOISE / SNR CONFIGURATION

- `i_noise_en` is a runtime enable: 0 bypasses noise addition, 1 adds AWGN. The ISI path remains active in both cases.
- `i_cfg_snr_db[7:0]` is an unsigned integer dB value, not Q4.4 or Q4.12. Its encoding range is 0..255; the supported SNR range/LUT entries must be frozen with the Channel implementation. Initial target presets are 15, 20 and 25 dB.
- `i_cfg_noise_load` is a separate Channel configuration strobe. Hold the dB bus stable and pulse it for one rising clock edge. Changes to the bus without a load leave the active SNR unchanged.
- `DEFAULT_SNR_DB`, default 8'd20, selects the reset SNR. Reset takes priority over loading. The new SNR applies to subsequent sample processing after the configuration edge; exact gain-conversion latency remains to be specified.
- Reset/configuration loading does not use the RX `i_cfg_load` pin. Loading SNR does not reset input history or reseed noise generation, and can occur while noise addition is disabled.
- Advance ISI history and the noise RNG every active clock after reset, including while `i_noise_en=0`. The enable bypasses only the final noise contribution and does not pause the stream or RNG.
- SNR-to-gain conversion belongs inside Channel: `sigma = sqrt(P_ref / 10^(snr_db/10))`. The reference-power convention, LUT coverage and gain precision remain implementation decisions. The original MATLAB model uses measured frame clean-signal power; this streaming interface does not imply that measurement has already been implemented.
- The fixed-sigma 0.25 bounds in section 2.2 describe the saved 20 dB model profile. Other SNR/gain settings need their own bounds; final output saturation still limits Q4.4 to [-8,+7.9375].
- The old fixed `SIGMA_Q12`/`NOISE_ENABLE` parameters are replaced by these runtime controls and `DEFAULT_SNR_DB`. `H1_Q12` and `NOISE_SEED` remain parameters.
- The Channel bench holds reset for 10 clocks, loads SNR_DB (default 20 dB) on one configuration clock with noise disabled, then applies NOISE_EN (default 1). Run `make run MODULE=channel NOISE_EN=1 SNR_DB=25` from `10_sim`. This is stimulus scaffolding, not a functional Channel test result.

## Sources / decisions

- Current Python model: retained without modification; its random-symbol stream is separate from this implementation proposal.
- User-selected Channel output interface: signed 8-bit Q4.4 (8 total bits, 4 fractional bits).
- User-selected timing: continuous TX and one-symbol-per-clock Channel; remove per-symbol valid ports and use fixed pipeline timing.

This README contains the corresponding design section from the source document.
