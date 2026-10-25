# RX

Source: [BLOCK_DIAGRAM_DESIGN_FLOW.txt](../../99_doc/BLOCK_DIAGRAM_DESIGN_FLOW.txt), draft 1.3.

[TX](../tx/README.md) | [Channel](../channel/README.md) | [RX](../rx/README.md) | [Top.sv](../Top.sv)

## Block interface

`rx_top` must expose `parameter integer NUMBER_SYMBOL=1`. Use `[NUMBER_SYMBOL-1:0][7:0]` for `i_r`, `[NUMBER_SYMBOL-1:0][3:0]` for `i_tx_ref`/`o_sym`, `[NUMBER_SYMBOL-1:0][1:0]` for `o_bits`, and `[NUMBER_SYMBOL-1:0][15:0]` for `o_y`. Coefficient/configuration ports remain shared scalars. The tables below describe one lane (`NUMBER_SYMBOL=1` baseline).

Lane `[0]` is earliest and lane `[NUMBER_SYMBOL-1]` latest in a continuous symbol stream. `TRAIN_LEN` remains a number of symbols, so training may end within a block. Clock latency and algorithmic symbol delay are separate units. The child implementation must preserve the agreed Channel/FFE/DFE/LMS state schedule across lanes and block boundaries. Top now forwards NUMBER_SYMBOL and its BER monitor supports complete blocks plus per-lane startup/training qualification; the parallel DSP child RTL is still supplied separately by the team. See [TOP_BER.md](../../99_doc/TOP_BER.md).

## Overview

Input: signed8 Q4.4, one Channel sample every clock after pipeline fill.
Main output: one recovered signed4 PAM-4 symbol and its two Gray bits per clock after RX fill.
These are recommended internal formats, not yet an RTL implementation or a verified Q4.4 performance result.
Notation: signedW Ff means W TOTAL bits including sign, with f fractional bits; Q4.12 here is signed16 F12.

## 3.1 RX BLOCK FLOW / CONNECTIONS

Default FFE+DFE path is shown below; independent bypass mux behavior and mode-dependent D are specified in 3.10.

```text
  Channel o_r[7:0]
        |
        v
  [Input scaling + 2 sample delays] -- x[n] --> [FFE: 3 taps] -- f[n] --> [DFE subtraction] -- y[n] --> [PAM-4 slicer] -- d_hat[n] --> [Gray decoder]
                 |                                ^                         ^                   |                     |                    |
                 |                                | w[n]                    | b0[n]*d_prev[n]    |                     |                    +--> rx_bits[1:0]
                 |                          [FFE coefficient z^-1]     [DFE feedback multiply]  |                     +--> rx_sym[3:0]
                 |                                ^                         ^                   |                     |
                 |                                |                         |                   |                     v
                 +--> [LMS_FFE: 3 updates] --------+                         +---------- d_prev[n] <-- [Decision z^-1]
                            ^                                                                  |          |
                            | shared psi[n],g[n]                                                |          +--> [LMS_DFE: 1 update]
                            |                                                                  |                         |
                      [Error clip + DD gate] <--- e[n] --- [C1: d_des[n] - y[n]] <---------------+                         v
                            |                                   ^                                            [DFE coefficient z^-1]
                            +--> same psi[n],g[n] --> LMS_DFE     |                                                        |
                                                        [Training / DD selector]                               b0[n] --> feedback multiply
                                                          ^                 ^
                                                          |                 +--- current d_hat[n] (DD mode)
  TX symbol reference --> [Reference alignment: path latency + mode-selected D] (training mode)
```

- FFE and DFE LMS are separate update blocks, outside the forward FFE -> DFE -> slicer path.
- The shared error comparator takes y BEFORE the slicer; the DD desired value is the CURRENT slicer decision.
- Decision z^-1 stores the PREVIOUS decision. Both the DFE cancellation and LMS_DFE use that same delayed decision.
- Coefficient z^-1 stores each updated coefficient state for the next symbol; it is not an extra error delay.
- The two FFE history delays provide r[n-1] and r[n-2] to both the FFE and LMS_FFE.
- Four signed16 F12 configuration pins + i_cfg_load feed the FFE/DFE coefficient state registers (RX11), not the sample input.
- i_adapt_en permits LMS writes only for non-bypassed branches; all modes keep one-sample-per-clock data flow.
- Add an FFE output mux (filtered f versus current r) and a DFE feedback mux (b0*d_prev versus zero); see the four-mode table in 3.10.
- Training and BER reference paths are on-chip testbench side paths, separate from the Channel data input.

## 3.2 RX DATAPATH SUBMODULES

| ID | Submodule | Function | Inputs / value range | Outputs / value range | Recommended representation |
| --- | --- | --- | --- | --- | --- |
| RX01 | rx_input_history | Convert Channel samples to the internal scale. Keep two sample delays for the 3-tap FFE and its LMS branch. | i_r[7:0]: signed Q4.4, representable [-8,7.9375]; current-profile bound [-6,+6]. clk, rst_n. | x[n]={r[n],r[n-1],r[n-2]}; same real range as input, with zero history on reset. | Input: signed8 F4. Each internal sample: signed16 F12. Sign-extend to 16 bits, then <<8. Conversion is exact. |
| RX02 | ffe_mac_3tap | Compute f[n]=sum(w_k*x_k). Output mux selects f[n] normally or current r[n] when FFE is bypassed. Keep x[n] available to LMS_FFE. | 3 samples x_k: signed16 F12. 3 coefficients w_k: signed16 F12 in [-1.25,+1.25]. Latched ffe_bypass: 1 bit. | f_sel[n]: signed18 F12; normal FFE profile bound [-22.5,+22.5], bypass bound [-6,+6]. Bypass passes r[n], not r[n-1]. | Each raw product: signed32 F24. Arithmetic >>12 then saturate each term to signed16 F12; sum in signed18 F12. |
| RX03 | dfe_cancel_1tap | Compute v=b0*d_prev. Use v_sel=0 when DFE is bypassed, otherwise v_sel=v. Output y=sat16(f_sel-v_sel). | f_sel[n]: signed18 F12. b0: signed16 F12 in [-0.75,+0.75]. d_prev: {-3,-1,+1,+3}, startup 0. Latched dfe_bypass: 1 bit. | v_sel: [-2.25,+2.25], or exactly 0 in bypass. y: signed16 F12, range [-8,7.999755859375]; feeds slicer and comparator. | Lift d_prev to signed16 F12. Product signed32 F24 -> signed16 F12. Subtract in signed19 F12, then saturate y to signed16 F12. |
| RX04 | pam4_slicer | Compare y to -2, 0, +2. Match the current model: exact threshold ties choose the lower level. | y[n]: signed16 F12, representable [-8,7.999755859375]. | d_hat[n]: signed integer {-3,-1,+1,+3}. Feeds recovered-symbol output, Gray decoder, DD selector and decision memory. | Output signed4 integer Q4.0. Threshold stored integers: -8192, 0, +8192 in F12. |
| RX05 | decision_delay_z1 | Store exactly one previous slicer decision. Provide d_hat[n-1] to DFE feedback and LMS_DFE. | d_hat[n]: signed4 integer {-3,-1,+1,+3}; clk, rst_n. | d_prev[n]=d_hat[n-1]: {-3,-1,+1,+3}; 0 only for reset/startup history. | One signed4 register. Convert to signed16 F12 by sign extension then <<12 wherever fractional multiplication is needed. |
| RX06 | pam4_gray_decoder | Recover the transmitted Gray label from the decided amplitude. Keep output bits and symbol aligned. | d_hat[n]: signed4 integer {-3,-1,+1,+3}. | rx_bits[1:0]: -3->00, -1->01, +1->11, +3->10. rx_sym[3:0]=d_hat[n]. | Recovered bits: unsigned2 logic vector. Recovered symbol: signed4 Q4.0. No fractional rounding. |

## 3.3 RX TRAINING / ERROR / LMS SUBMODULES

Selected adaptation baseline: robust_proj, constant mu=0.0005, matching the current model's principal demonstrated case.
Other model variants and Polyak averaging are separate options; their hardware is not included in this initial RX proposal.

| ID | Submodule | Function | Inputs / value range | Outputs / value range | Recommended representation |
| --- | --- | --- | --- | --- | --- |
| RX07 | training_ref_control | Align TX reference to the current EQ output. Choose known reference during training and current slicer decision afterwards. | TX symbol reference: signed4, {-3,-1,+1,+3}. d_hat[n]: same set. Startup count, fixed latency, mode-dependent D, N_train=3000. | d_des[n]: reference s[n-D] during training, d_hat[n] in decision-directed mode, 0 during initial algorithmic startup. train_mode, adapt_step: internal control bits. | Reference alignment registers: signed4. d_des at comparator: signed16 F12. Training count: unsigned12 for 0..3000, then saturate. |
| RX08 | error_clip_gate | Shared comparator C1: e=sat16(d_des-y). For robust_proj, clip the error and gate adaptation using the original e. | d_des, y: signed16 F12. Clip=2.5; DD gate=1.5. Internal training/startup control. | e_raw: signed16 F12. psi=clip(e_raw,-2.5,+2.5). g: update allowed; during DD require abs(e_raw)<=1.5. Same psi,g go to BOTH LMS blocks. | Subtract in signed17 F12 before sat16. psi: signed16 F12. Clip integer=10240; gate integer=6144. Magnitude/absolute operation must handle -32768. |
| RX09 | lms_ffe_3tap | For each tap compute delta_w=mu*psi*x_k, then A_w_next=project(A_w+delta_w). No independent slicer/error inside this block. | x[n]: 3 x signed16 F12, same vector used by FFE for y[n]. psi: signed16 F12, +/-2.5. g: 1 bit. A_w: 3 x signed40 F20. mu: F20. | 3 next accumulator states, each in [-1.25,+1.25]. Hold states unless i_adapt_en && g && !ffe_bypass. Config load has write priority. | Keep coefficient accumulators signed40 F20. Full mu*psi*x product: signed72 F44; round/shift by 24 to F20. Add in signed41 F20 before saturation/projection. |
| RX10 | lms_dfe_1tap | Compute delta_b=mu*psi*d_prev, then A_b_next=project(A_b-delta_b). The MINUS sign follows y=f-b*d_prev. | d_prev: signed16 F12, {-3,-1,+1,+3} plus startup 0; psi and g shared with LMS_FFE. A_b: signed40 F20. mu: F20. | Next accumulator state in [-0.75,+0.75]. Hold state unless i_adapt_en && g && !dfe_bypass. Config load has write priority. | Accumulator signed40 F20. Full update product signed72 F44 -> rounded signed40 F20. Subtract in signed41 F20 before saturation/projection. |
| RX11 | coefficient_state_z1 | Store coefficient states and two bypass mode bits. Atomically load config on i_cfg_load. Permit LMS writes only for enabled, non-bypassed branches. | Four signed16 F12 config taps; i_ffe_bypass, i_dfe_bypass; i_cfg_load, i_adapt_en; LMS next states, clk, rst_n. | w: 3 x signed16 F12; b0: signed16 F12. ffe_bypass,dfe_bypass: latched 1-bit flags. Reset w=[0,0.75,0], b0=0, both flags=0. | State: 4 x signed40 F20. Config: clamp F12, sign-extend to 40 bits, then <<8. Visible taps: round F20 -> F12 by 8 bits, ties away from zero; sat16. |

## 3.4 RECOMMENDED RX TOP-LEVEL INTERFACE

No per-symbol handshake ports. All sample processing is synchronous with the common clock.
Coefficient config pins and both bypass config pins are sampled only on i_cfg_load; this control does not qualify or pause sample data.

| Signal | Direction | Bits | Representation | Value range | Meaning |
| --- | --- | --- | --- | --- | --- |
| i_clk | Input | 1 | Clock | {0,1}; common TX/Channel/RX clock. | One sample per clock during steady operation. |
| i_rst_n | Input | 1 | Active-low reset | {0,1} | Initialize sample history, decision memory, coefficient states and startup/training counters. |
| i_r[7:0] | Input | 8 | Signed Q4.4 | Representable [-8,+7.9375]; selected-profile bound [-6,+6]. | Direct connection from Channel o_r[7:0]. |
| i_tx_ref[3:0] | Input | 4 | Signed integer Q4.0 | {-3,-1,+1,+3} | Known TX symbol side path for initial training; align internally. Not additional Channel data. Unused as desired data after training. |
| i_cfg_ffe0[15:0] | Input | 16 | Signed Q4.12 | Allowed real [-1.25,+1.25]; F12 integers [-5120,+5120]; step 1/4096. | Load w0 multiplying r[n]. Sample with the other taps on i_cfg_load. |
| i_cfg_ffe1[15:0] | Input | 16 | Signed Q4.12 | Allowed real [-1.25,+1.25]; F12 integers [-5120,+5120]; step 1/4096. | Load w1 multiplying r[n-1]. |
| i_cfg_ffe2[15:0] | Input | 16 | Signed Q4.12 | Allowed real [-1.25,+1.25]; F12 integers [-5120,+5120]; step 1/4096. | Load w2 multiplying r[n-2]. |
| i_cfg_dfe0[15:0] | Input | 16 | Signed Q4.12 | Allowed real [-0.75,+0.75]; F12 integers [-3072,+3072]; step 1/4096. | Load b0 multiplying d_hat[n-1]; y=f-b0*d_prev. |
| i_ffe_bypass | Input | 1 | Synchronous mode config | 0: use 3-tap FFE; 1: pass current r[n]. | Latched on i_cfg_load. Bypassing FFE also freezes its LMS state writes, while preserving coefficients. |
| i_dfe_bypass | Input | 1 | Synchronous mode config | 0: subtract DFE feedback; 1: feedback contribution is zero. | Latched on i_cfg_load. Bypassing DFE freezes its LMS state writes; slicer/decision history keep advancing. |
| i_cfg_load | Input | 1 | Synchronous load control | {0,1}; pulse high for one clock to load. | Atomically latch all four coefficient inputs and both bypass flags; overrides LMS writes. Does not pause the data stream. |
| i_adapt_en | Input | 1 | Adaptation control | 0: fixed coefficients; 1: LMS enabled, subject to startup and error gate. | 0 holds coefficients; 1 enables LMS only for active branches, subject to startup/error gate. Data keeps flowing. |
| o_sym[3:0] | Output | 4 | Signed integer Q4.0 | {-3,-1,+1,+3} | Recovered symbol, one per clock after fill. |
| o_bits[1:0] | Output | 2 | Gray label | 00,01,11,10 | Recovered Gray word aligned with o_sym; route to BERT. |

## 3.5 VALUE RANGES / FIXED-POINT RATIONALE

- RX input Q4.4 -> Q4.12 conversion: r_internal_int = sign_extend_16(i_r) << 8. This retains the received value exactly; it does not recover discarded Channel precision.
- Keep visible coefficients at signed16 F12 and update states at signed40 F20 so small LMS increments can accumulate.
- mu=0.0005 rounds to stored F20 integer 524, i.e. mu_eff=524/1048576=0.000499725341796875.
- A four-fractional-bit mu would round to zero. The 8-bit Channel interface does not imply 8-bit coefficients or LMS arithmetic.
- Under |r|<=6 and |w_k|<=1.25, each untruncated FFE product has |w_k*r|<=7.5; three terms conservatively sum within [-22.5,+22.5].
- For any representable Channel input, each model-style post-shift/saturated product is signed16 F12; three such terms fit signed18 F12, range [-32,31.999755859375].
- With |b0|<=0.75 and |d_prev|<=3, feedback lies within [-2.25,+2.25]. Before final saturation the current-profile combined bound is [-24.75,+24.75].
- y is deliberately saturated to signed16 F12, range [-8,7.999755859375], matching the model's output arithmetic structure. Its actual observed range is narrower, not a guaranteed design bound.
- Before error saturation, d_des-y lies within [-10.999755859375,+11]; use signed17 F12, then saturate to signed16 F12 before clip/gate.
- psi is limited to [-2.5,+2.5]. Gate g uses abs(e_raw), not abs(psi); threshold ties abs(e_raw)=1.5 allow a DD update.
- FFE update magnitude before rounding is <=mu_eff*2.5*6=0.007495880126953125 in the selected profile; DFE update magnitude <=mu_eff*2.5*3=0.0037479400634765625.
- F20 projection limits: FFE accumulator integers +/-1310720 (real +/-1.25); DFE accumulator integers +/-786432 (real +/-0.75).
- Initial visible FFE tap integers [0,3072,0] represent [0,0.75,0]; initial F20 states [0,786432,0]. DFE starts at zero.
- For raw LMS product P_int=mu_int*psi_int*x_int (or d_prev_int), delta_int=sat40(round_away(P_int/2^24)); do not prematurely reduce psi or x to F4.
- Arithmetic right shift of negative FFE/feedback products rounds toward negative infinity, as in the Python model. LMS increments and F20-to-F12 taps use round-to-nearest with ties away from zero.
- Recommended widths retain the model's internal scale, while the changed Channel boundary and PRBS source still require later numerical validation. No Python or RTL changes are made here.

## 3.6 SLICER / GRAY OUTPUT RULES

```text
  Pre-slicer y interval     Output symbol   signed4 bits   Recovered Gray
  y <= -2                  -3              1101           00
  -2 < y <= 0              -1              1111           01
   0 < y <= +2             +1              0001           11
   y > +2                  +3              0011           10
```

- The recovered symbol is a signed integer, not Q4.4. Its Gray word matches the TX mapper table exactly.
- Internal y=0 slices to -1 under the lower-tie rule. Hold off measurement during reset/fill so this startup result is not counted as a received symbol.

## 3.7 SYMBOL INDEX / ADAPTATION / FIXED TIMING CONTRACT

- Let n be the one-based RX sample index after the first actual Channel sample reaches the RX input; startup pipeline clocks are excluded from this count.
- For each n, form x[n]=[r[n],r[n-1],r[n-2]], read current w[n],b0[n], and use d_prev[n]=d_hat[n-1]. Histories before the first sample are zero.
- Compute FFE -> DFE -> y[n] -> current d_hat[n], then compute the common error and both coefficient updates for that SAME sample.
- Default full-EQ/FFE-only alignment is D=1: d_hat[n] targets s[n-1]. FFE-bypassed modes use D=0 and target s[n]. D is separate from fixed RTL pipeline latency; configured FFE taps must match the selected target delay.
- Use the mode-selected D: during n<=D use d_des=0; for D<n<=3000 use aligned known reference s[n-D]; after n>3000 use current d_hat[n].
- After reset/fill, run the model-style update during training and apply the error gate only in DD mode. Startup holdoff is a local control policy, not a stream handshake.
- Coefficient states updated from sample n become available for sample n+1, unless a config load overrides the write. Reset initializes visible w=[0,0.75,0], b0=0.
- Coefficient state write priority is reset > config load > enabled/gated LMS update for an active branch > hold. Config and adaptation controls never stall the sample stream.
- During a gate skip retain coefficient states while input history, slicer decisions and decision memory continue advancing every clock.
- Pipeline registers in the forward path require matching delays for LMS regressors, y, d_hat, training references and output Gray bits.
- The DFE decision loop must return exactly the previous SYMBOL's decision. Arbitrarily adding registers inside that loop changes the algorithm, even if output latency stays fixed.
- Likewise, extra LMS update latency changes when new taps are used. Exact model-style per-symbol updates require the update/state loop to meet the symbol period.
- Freeze a clock-by-clock schedule and timing target before RTL: one-symbol-per-clock operation is the requirement, not a timing result already achieved.
- Use top-level startup counting and fixed latency alignment. There are no idle sample clocks, backpressure or per-symbol valid ports in this baseline.

## 3.8 WHERE TO COMPARE / MEASURE

- C1 (inside RX): compare selected desired amplitude d_des[n] against pre-slicer y[n]. This produces LMS error, not BER.
- C2 (Top-level BER logic): compare o_bits against the corresponding delayed TX Gray reference. The Top counts differing bits and total compared bits; see [TOP_BER.md](../../99_doc/TOP_BER.md).
- Delay TX references by the implemented TX-to-decision path latency and mode-selected algorithmic D (1 for default FFE-active modes, 0 for FFE-bypassed modes); use an explicit symbol-index schedule to avoid double-counting delays.
- Begin BER/SER counting after training and pipeline fill. Keep the TX reference delay line running continuously so the first measured decision is aligned.
- Optional C0 baseline (external monitor): slice the raw Channel sample and compare against its matching TX symbol with algorithmic D=0, on the same retained TX-symbol interval as C2.
- The inline Top BER monitor has configurable counters (default 64 bits), latency parameters and measurement enable/clear. Optional raw slicer and frozen-tap/Polyak experiments remain outside the RX datapath table.

## 3.9 COEFFICIENT CONFIGURATION / LOAD CONTRACT

- Config taps are four separate signed16 Q4.12 inputs. Stored integer equals round(real_coefficient*4096); the complete format range is [-8,7.999755859375].
- Current robust_proj operational bounds still apply: clamp FFE configs to stored integers [-5120,+5120] and DFE config to [-3072,+3072] at load.
- Keep all four coefficient values and both bypass inputs stable before the active edge. Pulse i_cfg_load=1 for one clock to latch them atomically. Changing these inputs with i_cfg_load=0 has no effect.
- Configuration uses the common i_clk domain. A future asynchronous switch/UART/software interface must synchronize and stage the complete coefficient word before issuing the load pulse.
- Convert each clamped F12 config integer C to the corresponding F20 state A=sign_extend_40(C)<<8. Load the actual adaptation accumulators, so the next LMS update continues from the configured coefficients.
- On reset load default states w=[0,0.75,0], b0=0, ffe_bypass=0, dfe_bypass=0, regardless of i_cfg_load. To apply external configs, pulse i_cfg_load after reset is released, preferably before the first useful sample.
- On a config-load edge, override the normal LMS state write for all four taps; do not add a stale LMS delta to the freshly loaded values. Retire/flush any pending coefficient writes if a later implementation pipelines the LMS update.
- The loaded taps become visible after the load edge and apply at the next coefficient-read step; decisions already in flight keep their original coefficient association. Freeze the exact edge/sample mapping with the RTL pipeline schedule.
- With i_adapt_en=0, hold all coefficient accumulators while allowing config loads; this is fixed-coefficient operation.
- With i_adapt_en=1, resume LMS updates only for non-bypassed branches from current/loaded states, subject to startup and DD gate. Bypassed branch states hold; loaded active coefficients may change on subsequent samples.
- Suggested manual-load sequence: drive all config taps and both bypass values, set i_adapt_en=0, pulse i_cfg_load for one clock, then leave i_adapt_en=0 for fixed taps or set it to 1 to adapt active branches.
- Config loading does not reset sample history, decision history or training counters and does not pause TX/Channel/RX. A deliberate new training run uses the chain reset/startup procedure and then reloads the desired taps.
- i_cfg_load is a coefficient-write strobe, not a per-symbol valid flag. Data throughput stays one symbol per clock.

```text
  Example config set          FFE0       FFE1       FFE2       DFE0       Meaning
  Reset-equivalent values     16'h0000   16'h0C00   16'h0000   16'h0000   w=[0,0.75,0], b0=0
  Ideal noiseless profile     16'h0000   16'h1000   16'h0000   16'h0800   w=[0,1,0], b0=+0.5; h=[1,0.5], D=1
```

- The ideal example is the analytical cancellation target for this profile, not a claim that finite-length adaptive/noisy runs end at exactly these coefficients.

## 3.10 INDEPENDENT FFE / DFE BYPASS MODES

Each block has its own active-high bypass flag: 0=process through that block, 1=bypass it.
The two input flags are latched together with the four coefficient inputs on i_cfg_load.

| FFE bypass | DFE bypass | Mode | Signal at slicer input (before final sat16) | Target delay D | LMS branches allowed if i_adapt_en=1 |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | FFE + DFE | f[n] - b0*d_hat[n-1] | 1 (default) | FFE and DFE; subject to common g |
| 0 | 1 | FFE only | f[n] | 1 (default) | FFE only; hold DFE accumulators |
| 1 | 0 | DFE only | r[n] - b0*d_hat[n-1] | 0 | DFE only; hold FFE accumulators |
| 1 | 1 | Both bypassed | r[n] | 0 | Neither; hold all accumulators |

- r[n] above is the current Channel sample converted exactly to F12. f[n] is the existing wide 3-tap FFE sum.
- Forward equations: f_sel = ffe_bypass ? widen18(r[n]) : f[n]; v_sel = dfe_bypass ? 0 : b0*d_prev; y=sat16(f_sel-v_sel).
- Keep normal model-style feedback product truncation/saturation before subtraction. The bypass muxes do not change the chosen internal formats.
- FFE bypass forwards current r[n], not the middle FFE tap r[n-1]; therefore its symbol target changes from the default D=1 to D=0.
- Balance bypass and processing paths with matching pipeline registers, so the physical RX latency is identical in all four modes. This does not remove the separate mode-dependent symbol alignment D.
- Slicer and Gray decoding remain active even when both equalizers are bypassed; recovered outputs are raw Channel decisions in that mode.
- Keep the two input-history delays and decision z^-1 running every sample in every mode. DFE re-enable uses the immediately previous decision, not a stale pre-bypass value.
- Effective LMS writes: update_ffe=i_adapt_en && g && !ffe_bypass; update_dfe=i_adapt_en && g && !dfe_bypass, excluding config-load edges and startup holdoff.
- Bypass holds the corresponding F20 accumulators without overwriting or zeroing them. A config load still deliberately replaces all four tap states, including those of bypassed branches.
- A branch that is re-enabled resumes from its retained/loaded states. Since i_cfg_load loads all taps, drive the coefficient values intended for that new configuration when changing bypass mode.
- Treat mode changes as a new measurement configuration. Select the mode before startup/training where possible; on a live change discard transition outputs, align references to the new D and restart the measurement/training epoch before comparing BER.
- Do not reset or pause the sample stream to implement bypass. Exact mode-bit propagation and transition discard length must be specified with the pipeline schedule.
- These modes extend the implementation proposal; they do not modify the Python model or establish numerical BER results for FFE-only/DFE-only modes.

## 3.11 ITEMS TO FREEZE NEXT

- Confirm this RX module split and the recommended internal formats; external Channel-to-RX input remains signed8 Q4.4.
- Freeze the RX clock target, feedback/update scheduling, exact pipeline latency and startup/reference-alignment timing together.
- Decide whether training reference alignment lives inside rx_top or the top-level testbench; this draft exposes a same-TX-beat i_tx_ref and aligns it inside RX.
- Freeze config/mode-load timing, balanced bypass pipelines, mode-dependent reference alignment and transition measurement policy alongside arithmetic rules before RTL.
- Later validate the selected Q4.4 Channel boundary and PRBS stream against an agreed numerical reference; existing model results use their original formats/source.

## Sources / decisions

- Current Python model: retained without modification; its random-symbol stream is separate from this implementation proposal.
- User-selected timing: continuous TX and one-symbol-per-clock Channel; remove per-symbol valid ports and use fixed pipeline timing.
- RX proposal source: Python Config / dfe_core and current-model interfaces; 3 FFE taps, 1 DFE tap, separate FFE/DFE LMS, shared robust_proj error control.
- User-requested RX coefficient config: three FFE and one DFE signed16 F12 inputs, atomic config load, and adaptation enable for fixed/adaptive operation.
- User-requested independent FFE/DFE bypass: two active-high config bits, latched on i_cfg_load; four modes with per-branch LMS hold and mode-aware reference alignment.

This README contains the corresponding design section from the source document.
