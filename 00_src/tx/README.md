# TX

Source: [BLOCK_DIAGRAM_DESIGN_FLOW.txt](../../99_doc/BLOCK_DIAGRAM_DESIGN_FLOW.txt), draft 1.3.

[TX](../tx/README.md) | [Channel](../channel/README.md) | [RX](../rx/README.md) | [Top.sv](../Top.sv)

## Block interface

`tx_top` must expose `parameter integer NUMBER_SYMBOL=1`. Ports `o_sym` and `o_bits_ref` use `[NUMBER_SYMBOL-1:0][3:0]` and `[NUMBER_SYMBOL-1:0][1:0]`. The tables below describe one lane (`NUMBER_SYMBOL=1` baseline). Each active clock carries one full block: lane `[0]` is earliest and lane `[NUMBER_SYMBOL-1]` latest in the same continuous symbol stream. Advance the single TX sequence NUMBER_SYMBOL symbol steps per clock; lanes are consecutive symbols, not independent PRBS channels.

## Selected TX concept (NUMBER_SYMBOL=1 baseline)

- Use ONE PRBS/LFSR source to control the selection of one Gray code per clock after reset.
- The PRBS output used here is sel[1:0], a pseudo-random MUX select value in 0..3.
- A 4:1 MUX selects one of four constant Gray words: 00, 01, 11, 10.
- The PAM-4 mapper maps that selected Gray word to one signed 4-bit integer amplitude: -3, -1, +1, +3.
- Each clock in continuous operation produces ONE new symbol. A 2-bit select code is one control word for that symbol.
- There is no serial-bit pair collector in this proposal. There is no runtime MUX between two PRBS cores.
- Draft PRBS order N=7 is a starting parameter, not a second source. Exact taps/shift direction will be frozen later.
- Selected throughput: one new symbol every clock after reset and pipeline fill, without per-symbol handshake signals.
- PRBS selection is deterministic pseudo-random; seed and the agreed LFSR convention determine the sequence.
- Current Python TX still uses its existing random-symbol source. This document does not replace that source.

## Processing submodules

tx_top: common clock/reset; initialize the PRBS seed at reset, then run continuously

```text
  One PRBS/LFSR ---- sel[1:0] ----> 4:1 Gray-code MUX ---- gray_code[1:0] ----> PAM-4 mapper ---- tx_sym[3:0] (signed) ----> CHANNEL
                                          ^                                     |
                                          |                                     +--> tx_bits_ref[1:0]
                                 C0=00, C1=01, C2=11, C3=10
```

Control and output registers may be implemented inside tx_top/mapper; they do not require extra processing blocks here.
The MUX output is the actual Gray label carried by the symbol. The PRBS select value is a control signal.

| ID | Submodule | Function | Inputs / value range | Outputs / value range | Recommended representation |
| --- | --- | --- | --- | --- | --- |
| TX01 | prbs_selector | One PRBS/LFSR generates a pseudo-random 2-bit MUX select code. Use the current state and advance once every active clock. | clk, rst_n: logic {0,1}. Reset seed: nonzero unsigned 1..(2^N-1). Draft N=7: seed 1..127, default 7'h7F. Seed is a reset-time configuration. | sel[1:0]: unsigned 0..3 (00/01/10/11). Proposed sel=state[1:0]. Internal state: N-bit nonzero unsigned. | State: unsigned N bits, draft 7 bits. Select: unsigned 2 bits. Clock/reset: 1 bit. No fractional bits. |
| TX02 | gray_code_mux | A combinational 4:1 MUX selects ONE fixed Gray code from the current select value. All four data inputs are constants. | sel[1:0]: unsigned 0..3. Constant inputs: C0=2'b00, C1=2'b01, C2=2'b11, C3=2'b10. | gray_code[1:0]: one of 00/01/11/10. sel=00->00, 01->01, 10->11, 11->10. | Select and Gray data: 2-bit logic vectors. No fractional bits. |
| TX03 | pam4_gray_mapper | Map one selected Gray code to one PAM-4 amplitude. Register the symbol and selected Gray reference together every active clock. | clk, rst_n: {0,1}. gray_code[1:0]: 00/01/11/10. | tx_sym[3:0]: signed integer {-3,-1,+1,+3}, encoded 1101/1111/0001/0011. tx_bits_ref[1:0]=selected Gray code for the same symbol. | Amplitude: signed 4-bit integer (Q4.0, zero fractional bits). Gray reference: 2 bits. All four amplitudes are exact. |

## 1.1 SELECT -> GRAY -> PAM-4 TRUTH TABLE

```text
  sel[1:0]   Selected Gray   Signed amplitude   tx_sym[3:0] bits   4-bit hex
  00         00              -3                 1101               D
  01         01              -1                 1111               F
  10         11              +1                 0001               1
  11         10              +3                 0011               3
```

Example: sel=10 chooses Gray=11, so the mapper emits signed +1 (bits 0001).
For that symbol, tx_bits_ref must be 11 (the selected Gray word), not 10 (the MUX select code).
The mapper consumes the selected Gray code directly; do not apply another binary-to-Gray conversion after the MUX.

## 1.2 REPRESENTATION / VALUE RANGES

- PRBS state and seed: unsigned N-bit vectors; the complete LFSR state must be nonzero.
- Proposed N=7: state/seed range 1..127; seed default 7'h7F.
- Proposed select extraction: sel=state[1:0]. All four sel values, including 00, are legal even though the full state cannot be zero.
- sel and gray_code: 2-bit logic vectors; no fixed-point fractional bits.
- Clock and reset: 1-bit logic. No generation-enable or per-symbol handshake ports in this continuous-flow baseline.
- tx_sym: signed 4-bit two's-complement integer; Q4.0 notation here includes the sign bit among the four integer bits. No fractional bits.
- Stored signed integer equals the PAM-4 amplitude directly. TX does not multiply by 4096.
- The complete signed 4-bit representable range is -8..+7. The legal PAM-4 output set is only {-3,-1,+1,+3}.
- LSB = 1. Negative amplitudes use two's-complement encoding.
- All four PAM-4 levels are represented exactly, without rounding. Other representable integers are not transmitted levels during normal operation.
- Proposed amplitude port declaration: output logic signed [3:0] tx_sym.
- Data sent to Channel is this 4-bit signed symbol each clock; the two-bit Gray reference is for measurement.

## 1.3 CONTINUOUS ONE-SYMBOL-PER-CLOCK CONTRACT

- TX, Channel and the RX input boundary use one common clock.
- During continuous operation, each clock carries one new symbol, including when adjacent symbols have equal amplitudes.
- Use the current PRBS select code to select one Gray word and map one PAM-4 symbol, then advance the LFSR once.
- Freeze the exact current-state/first-output convention with reference vectors later. No complete PRBS period is stored.
- The mapper registers tx_sym and its matching tx_bits_ref together each clock.
- Initialize the PRBS from a nonzero seed at reset. The default is 7'h7F for draft N=7; seed configuration stays fixed during a run.
- No runtime pause, seed reload or backpressure is part of this baseline. Restart the chain through reset when restarting the sequence.
- Channel samples one TX amplitude each clock. Measurement/training uses the corresponding Gray and symbol references.
- Reset and pipeline-fill cycles are startup transients. A top-level startup counter can delay measurement/training until real samples arrive.
- Reference alignment to RX belongs to the later measurement/training design and must follow the fixed pipeline latency.
- Clock frequency, exact TX/Channel pipeline latencies and the first usable sample cycle remain to be frozen.

Illustrative consecutive symbol clocks (these values demonstrate mapping; they are not a claimed PRBS sequence):

```text
  Clock k:   sel=00 -> Gray=00 -> tx_sym=-3
  Clock k+1: sel=11 -> Gray=10 -> tx_sym=+3
  Clock k+2: sel=10 -> Gray=11 -> tx_sym=+1
  Clock k+3: sel=01 -> Gray=01 -> tx_sym=-1
```

## 1.4 TX -> CHANNEL FORMAT BOUNDARY

- TX sends signed 4-bit integer tx_sym. The selected Channel output is signed 8-bit Q4.4.
- TX does not scale its symbol. Conversion to fractional arithmetic is inside the Channel.
- If the Channel starts with Q4.4 arithmetic, sign-extend tx_sym to at least 8 bits first, then shift left by 4.
- Q4.4 examples: -3 -> stored -48 / hex D0; -1 -> -16 / F0; +1 -> +16 / 10; +3 -> +48 / 30.
- If wider internal Q4.12 arithmetic is retained, sign-extend to that width and shift left by 12 internally, then round to Q4.4 at the output.
- Always widen/sign-extend before a shift. Sign extension alone does not add fractional scaling.
- Channel internal coefficient widths and intermediate arithmetic widths remain for the next design steps.

## 1.5 ITEMS TO FREEZE NEXT

- Confirm the order N for the single PRBS source; N=7 is the current draft choice.
- Freeze polynomial, state shift direction, feedback indexes, seed, selected state bits and first-output convention together.
- Check the resulting symbol distribution/correlation with agreed reference vectors.
- Freeze reset-time seed initialization, pipeline timing and the startup counting rule using a short clock-by-clock example.
- Existing RTL is still an NRZ/single-bit placeholder with DW=12; implementation changes are outside this TXT-only step.

## Sources / decisions

- User-selected architecture: one PRBS -> MUX selecting a fixed Gray code -> PAM-4 mapper.
- README.md: Gray mapping. User-selected TX interface: signed 4-bit integer amplitude, replacing Q4.12 at the TX boundary in this implementation proposal.
- Current Python model: retained without modification; its random-symbol stream is separate from this implementation proposal.
- User-selected timing: continuous TX and one-symbol-per-clock Channel; remove per-symbol valid ports and use fixed pipeline timing.

This README contains the corresponding design section from the source document.
