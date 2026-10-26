# Project Specification: FPGA-Based PAM-4 Communication System with Emulated ISI Channel, CLT AWGN Generator, and Adaptive FFE-DFE Equalizer with Cyclic Pattern BER Monitor

**Course:** EE5427 – Digital System Design on FPGA  
**Target Platform:** Digilent Arty A7 (Xilinx Artix-7 XC7A35T / XC7A100T)  
**EDA Tool:** AMD Xilinx Vivado Design Suite  
**HDL Standard:** SystemVerilog  
**Team Size:** 5 Members  
**Reference Design:** Senior Thesis by Nguyen Hung Minh (HCMUT, May 2026)  

---

## 1. Executive Summary & Objective

In modern high-speed serial links (such as **PCIe 5.0/6.0, 400GE/800GE Ethernet, and USB4**), **PAM-4 (Pulse Amplitude Modulation 4-Level)** is widely adopted to double transmission throughput compared to conventional binary Non-Return-to-Zero (NRZ) signaling at the same baud rate. However, packing 4 voltage levels into the same physical dynamic range reduces the signal-to-noise ratio (SNR) margin by approximately $9.54\text{ dB}$, making PAM-4 signals highly vulnerable to high-frequency channel attenuation, dispersion, and **Inter-Symbol Interference (ISI)**.

This project implements an **autonomous, on-chip PAM-4 digital baseband evaluation system** on the **Digilent Arty A7 FPGA**. The system emulates a complete end-to-end communications transceiver chain:
1. **Transmitter (TX):** A deterministic 2-bit cyclic Gray code generator ($0 \to 1 \to 2 \to 3$) and PAM-4 amplitude mapper.
2. **Channel Impairment Engine:** A first-postcursor ISI channel filter with configurable postcursor loss coefficient (`i_cfg_isi_coeff`) and a 12-lane Central Limit Theorem (CLT) Additive White Gaussian Noise (AWGN) generator with configurable SNR scaling (`i_cfg_snr_db`).
3. **Adaptive Equalizer Core:** A 3-tap Feed-Forward Equalizer (FFE) and a 1-tap Decision Feedback Equalizer (DFE) with embedded Least Mean Square (LMS) coefficient adaptation operating in pure **Decision-Directed (DD-LMS)** mode.
4. **On-Chip BER Monitor:** A hardware Bit Error Rate (BER) measurement unit with snapshot holding registers for non-disruptive observability.

```
+-----------------------------------------------------------------------------------------------------------------+
|                                             FPGA On-Chip Testbench                                              |
|                                                                                                                 |
|  +------------+     +------------+     +---------------+     +---------------+                                  |
|  | Gray Gen   | --> | PAM-4 TX   | --> | Lossy Channel | --> |  Noise Adder  | ---------------------+           |
|  | (Cycle     |     | Gray Map   |     | Model (ISI)   |     | (r_clean+AWGN)|                      |           |
|  |  0,1,2,3)  |     +------------+     +---------------+     +---------------+                      |           |
|  +------------+                                                      ^                              v           |
|        |                                                             |     +---------------------------------+  |
|        |                                                     +---------------+   Adaptive 3-Tap FFE +        |  |
|        |                                                     | CLT AWGN Gen  |   1-Tap DFE Equalizer         |  |
|        |                                                     | (12 Taus88 L) |                               |  |
|        |                                                     +---------------+     +------------------+      |  |
|        |                                                                     |     |  Adaptive 3-FFE  |      |  |
|        |                                                                     |     |  (Precursor ISI  |      |  |
|        |                                           +-----------------------------> |  + LMS Adaptation|      |  |
|        |                                           |                         |     +------------------+      |  |
|        |                                           |                         |               |               |  |
|        |                                           |                         |               v (+)           |  |
|        |                                           |                         |             (Summer) <-- y[n] |  |
|        |                                           |                         |               ^ (-)    (pre-  |  |
|        |                                           |                         |               |        slicer)|  |
|        |                                           |                         |     +------------------+  |   |  |
|        |                                           |                         |  +- |  Adaptive 1-DFE  |  |   |  |
|        |                                           |   +-------------------------> |  (Postcursor ISI |  |   |  |
|        |                                           |   |                     |  |  |  + LMS Adaptation|  |   |  |
|        |                                           |   |                     |  |  +------------------+  |   |  |
|        |                                           |   |                     |  |            ^           |   |  |
|        |                                           |   |                     |  | d_hat[n-1] |           |   |  |
|        |                                           |   |                     |  |  +------------------+  |   |  |
|        |                                           |   |                     |  +->|   PAM-4 Slicer   | -+   |  |
|        |                                           |   |                     |     | (Symbol Decision)|  |   |  |
|        |                                           |   |                     |     +------------------+  |   |  |
|        |                                           |   |                     |               |           |   |  |
|        |                                           |   |                     |               v d_hat[n]  |   |  |
|        |                                           |   |     +-------------+ |     +------------------+  |   |  |
|        |                                           +---+---- | Error Logic | <-----+ d_hat (Decision- |  |   |  |
|        |                                               |     | e = d_hat-y |       | Directed DD-LMS) |  |   |  |
|        |                                                     +-------------+       +------------------+  |   |  |
|        |                                                                     +---------------------------|---+  |
|        |                                                                                                 |      |
|        |               +---------------------------------------------------------------------------------+      |
|        |               | Recovered Bits [1:0]                                                                   |
|        v               v                                                                                        |
|  +---------------------------+                                                                                  |
|  | Gray-Code BER Monitor     |                                                                                  |
|  |                           |                                                                                  |
|  +---------------------------+                                                                                  |
+-----------------------------------------------------------------------------------------------------------------+
```

---

## 2. Key Architectural Decisions & Reference Simplifications

To adapt the reference graduation thesis into a focused, modular **course assignment** for EE5427, the following key design decisions were made to reduce peripheral complexity while maximizing digital design learning outcomes:

| Feature | Reference Thesis Architecture | Proposed Assignment Architecture | Technical Motivation |
| :--- | :--- | :--- | :--- |
| **Test Pattern Generator & Monitor** | High-order PRBS-7/15 LFSRs with cross-correlation synchronization state machines. | **2-Bit Cyclic Gray-Code Generator & Synchronized BER Monitor** (repeating cycle: $0 \to 1 \to 2 \to 3 \to 0 \dots$). | Drastically simplifies pattern generation and synchronization logic while guaranteeing balanced, uniform transitions across all 4 PAM-4 signal levels for bit error measurement. |
| **Adaptation Mode** | Dual-mode operation: training mode using reference symbols followed by decision-directed tracking. | Pure **Decision-Directed LMS (DD-LMS)**: $e[n] = \hat{d}[n] - y[n]$. | Eliminates the need to distribute delayed transmitter reference symbols across the chip, reflecting realistic receiver operation and simplifying the interface. |
| **Equalizer Tap Adaptation** | Top-level adaptive equalizer with centralized adaptation engine. | **Modular Embedded Adaptive Tap Units (ATUs)** directly integrated inside the FFE and DFE sub-modules. | Preserves LMS coefficient adaptation, preset weight initialization, and step size $\mu$ control, distributed cleanly into modular blocks assigned to individual team members. |
| **Monitoring & Visualization** | External **ESP32-S3 microcontroller** over UART, transmitting HTTP packets via Wi-Fi to a PC web browser for eye-diagram plots. | **On-Chip Cyclic BER Monitor** directly following the PAM-4 Slicer. | Eliminates external microcontroller boards, Wi-Fi dependencies, and web development. The FPGA becomes **100% self-contained**, providing deterministic, quantitative BER measurements via 32-bit status registers. |
| **ISI Channel Filter** | Full multi-tap channel filter with floating/configurable main cursor gain. | **First-postcursor ISI filter with normalized main cursor $h_0 = 1.0$** and configurable postcursor factor `i_cfg_isi_coeff`. | Eliminates a hardware multiplier on the critical main cursor path while maintaining accurate modeling of high-frequency transmission line dispersion. |

---

## 3. Detailed Subsystem Architecture

### 3.1. Transmitter (TX): Cyclic 2-Bit Gray-Code Generator & PAM-4 Mapper

- **Cyclic 2-Bit Pattern Generator**:
  - Implements a deterministic 2-bit counter cycling through states:
    $$\text{Cycle: } 0 \to 1 \to 2 \to 3 \to 0 \to 1 \to 2 \to 3 \dots$$
  - Provides a repeatable, continuous test stream that visits all four PAM-4 constellation points uniformly.
  - Controlled via `i_cfg_tx_en`. When disabled, freezes the counter state.

- **PAM-4 Gray Mapper**:
  - Maps 2-bit binary symbols $(b_1, b_0)$ into symmetrical signed 16-bit fixed-point amplitudes (**Q4.12**: 1 sign bit, 3 integer bits, 12 fractional bits, where $1.0 = \text{16'sh1000}$):
    - State `0` (`2'b00`) $\to -3.0$ (`16'shD000`)
    - State `1` (`2'b01`) $\to -1.0$ (`16'shF000`)
    - State `2` (`2'b10`) $\to +1.0$ (`16'sh1000`)
    - State `3` (`2'b11`) $\to +3.0$ (`16'sh3000`)

---

### 3.2. Channel Model: First-Postcursor ISI & Hardware AWGN Generator

#### A. ISI Channel Model
Emulates high-frequency attenuation and dispersion characteristic of lossy transmission channels and backplanes:
$$r_{clean}[n] = s[n] + \text{ISI\_coeff} \cdot s[n-1]$$
- **Main Cursor Gain ($h_0$):** Normalized and fixed to $1.0$ (eliminates the hardware multiplier for $h_0$).
- **`i_cfg_isi_coeff` ($h_1$):** First-postcursor distortion coefficient—specifies the extent to which the preceding symbol's voltage $s[n-1]$ bleeds into and impairs the current symbol $s[n]$ (configurable via port `i_cfg_isi_coeff`, e.g., $0.35$ to $0.50$, default `16'sh0800` = $0.50$).
- **Bypass Control:** Controlled via `i_cfg_isi_en`. When disabled (`0`), the filter bypasses the input: $r_{clean}[n] = s[n]$.

#### B. CLT-Based AWGN Generator
- **Uniform Pseudo-Random Backbone:** $m=12$ parallel **Taus88** combined Tausworthe pseudo-random number generators. Each lane combines 3 LFSRs (degrees 31, 29, 28) using shifts, masks, and XOR operations (aggregate period $\approx 2^{88}$).
- **Bit-Mixing Decorrelator:** Lightweight bit permutation and XOR operations extract a 12-bit unsigned uniform word per lane with minimized cross-lane correlation.
- **Pipelined Adder Tree:** Multi-stage binary adder tree summing the twelve 12-bit words ($S = \sum_{i=1}^{12} \text{lane}_i$), followed by subtraction of the theoretical mean ($12 \times 2048 = 24576$).
- **Normalized Scaling:** Multiplies the centered sum by a constant integer calibration factor $G_{CLT}$ and bit-shifts to obtain unit-variance noise ($\sigma = 1.0$, Q4.12).
- **Noise Scaling & Injection:**
  $$r_{noisy}[n] = r_{clean}[n] + \sigma_{noise} \cdot \text{AWGN}[n]$$
  $\sigma_{noise}$ is configurable via `i_cfg_snr_db` (Q4.12) to simulate different SNR levels ($15\text{ dB}, 20\text{ dB}, 25\text{ dB}, \infty\text{ dB / Clean}$).
  Symmetric saturation (`16'sh7FFF` to `16'sh8000`) prevents catastrophic arithmetic wrap-around.

---

### 3.3. Equalizer Core: Adaptive 3-Tap FFE & Adaptive 1-Tap DFE

Each equalizer module (FFE and DFE) embeds its own LMS coefficient adaptation logic, preserving the Adaptive Tap Unit (ATU) architecture from the reference thesis:

```
                  +---------------------------------------------------------+
                  |               Adaptive 3-Tap FFE Module                 |
                  |                                                         |
r_noisy[n] -------+--> [ z^-1 ] ----------> [ z^-1 ]                        |
                  |       |                    |                            |
                  v       v                    v                            |
               +----------------------------------+                         |
               |      Adaptive Tap Units (ATU)    | <--- Error e[n]         |
               | Tap 0 (w0) | Tap 1 (w1) | Tap 2  | <--- Learning Rate mu   |
               | w_k <= w_k + mu * e * x_k        | <--- Preset w0, w1, w2  |
               +----------------------------------+                         |
                  |       |                    |                            |
                  +-----> ( + ) <--------------+                            |
                            |                                               |
+---------------------------|-----------------------------------------------+
|                           v FFE Output
|                         ( + )
|                           ^ (-)
|                           | DFE Output
|                 +---------------------------------------------------------+
|                 |               Adaptive 1-Tap DFE Module                 |
|                 |                                                         |
|                 |    +-----------------------------+ <--- Error e[n]      |
|                 |    |   Adaptive Tap Unit (ATU)   | <--- Learning Rate mu|
|                 |    | Tap 0 (b0)                  | <--- Preset b0       |
|                 |    | b_0 <= b_0 - mu * e * d_hat |                      |
|                 |    +-----------------------------+                      |
|                 |                   ^                                     |
|                 +-------------------|-------------------------------------+
|                                     |
|                               +------------+
|                               | z^-1 (Reg) | <--- Past Decision d_hat[n-1]
|                               +------------+
|                                     ^
|                                     |
v Pre-Slicer y[n]                     |
+------------------+ Sliced Symbol    |
|   PAM-4 Slicer   | -----------------+
+------------------+ d_hat[n]
        |
        v
+------------------+ Recovered
|  Gray Demapper   | Bits [1:0]
+------------------+ ----------> To Gray-Code BER Monitor
```

#### A. Adaptive 3-Tap Feed-Forward Equalizer (FFE) Module
- **Filtering Datapath:** 3-tap FIR filter operating on incoming samples $x[n], x[n-1], x[n-2]$:
  $$y_{ffe}[n] = \sum_{k=0}^{2} w_k[n] \cdot x[n-k]$$
- **Embedded Tap Adaptation:**
  - Each tap contains its own internal coefficient register initialized via `i_cfg_ffe_w0`, `i_cfg_ffe_w1`, `i_cfg_ffe_w2`.
  - Continuously updates weights using the error signal $e[n]$:
    $$w_k[n+1] = w_k[n] + \mu \cdot e[n] \cdot x[n-k]$$
- **DSP Mapping & Pipelining:** Tap multiplications and adder tree are mapped to Xilinx **DSP48E1** slices with internal pipeline registers.

#### B. Adaptive 1-Tap Decision Feedback Equalizer (DFE) Module
- **Filtering Datapath:** Reconstructs the first-postcursor ISI tail from the previous sliced decision $\hat{d}[n-1]$:
  $$y_{dfe}[n] = b_0[n] \cdot \hat{d}[n-1]$$
- **Equalizer Subtraction:**
  $$y[n] = y_{ffe}[n] - y_{dfe}[n]$$
- **Embedded Tap Adaptation:**
  - Contains its own internal feedback coefficient register initialized via `i_cfg_dfe_b0`.
  - Continuously updates the feedback weight:
    $$b_0[n+1] = b_0[n] - \mu \cdot e[n] \cdot \hat{d}[n-1]$$

#### C. Decision-Directed Error Generation & Slicer
- **PAM-4 Slicer:** Compares the equalized waveform $y[n]$ against thresholds ($-2.0, 0.0, +2.0$) to produce the hard decision $\hat{d}[n] \in \{-3.0, -1.0, +1.0, +3.0\}$.
- **Decision-Directed Error Generation:**
  $$e[n] = \hat{d}[n] - y[n]$$
  Operates purely in **Decision-Directed LMS (DD-LMS)** mode, computing the instantaneous difference between the quantized symbol decision $\hat{d}[n]$ and the unquantized equalized sample $y[n]$.
- Error $e[n]$ is broadcast back to both the FFE and DFE modules to drive their respective Adaptive Tap Units.

---

### 3.4. On-Chip Cyclic Pattern BER Monitor
- **Deterministic Delay Match:** Because the transmitter pattern is a known cyclic sequence ($0 \to 1 \to 2 \to 3$), the expected symbol/bits at the receiver are generated locally via a matched 2-bit counter synchronized with datapath latency.
- **Bit & Symbol Comparator:** Compares recovered bits with expected bits on each clock cycle:
  $$\text{Bit Error} = (\text{recovered\_bits} \neq \text{expected\_bits})$$
- **Accumulation & Snapshot Registers:**
  - **Total Evaluated Symbols:** 32-bit register accumulating processed symbols (`o_stat_total_words`).
  - **Bit Error Counter:** 32-bit register counting mismatched bits (`o_stat_err_bits`).
  - A snapshot trigger (`i_cfg_snapshot_trig`) latches live counters into status registers for non-disruptive readout.

---

## 4. Hardware Pipelining Strategy & L.O.3 Compliance

The course syllabus highlights **L.O.3: Pipeline design and latency vs. throughput trade-off analysis**. This project provides an ideal architecture for this analysis:

### 4.1. FFE Feed-Forward Pipelining
- Because the FFE is an open-loop FIR filter, pipeline registers can be inserted between the multiplication stage and the adder-tree reduction stage without recursive timing constraints.
- Multipliers and adders are mapped to Xilinx **DSP48E1** slices (`ug479`), utilizing dedicated internal pipeline registers (`AREG=1, BREG=1, MREG=1, PREG=1`) to achieve clock speeds $>200\text{ MHz}$ on Artix-7.

### 4.2. DFE Feedback Loop: Direct-Form vs. Speculative (Look-Ahead) DFE
The DFE contains a **recursive feedback loop** that represents a classic hardware critical path:
1. **Direct-Form DFE Constraint:**
   - The feedback decision $\hat{d}[n-1]$ must be multiplied by $b_0$, subtracted from FFE output $y_{ffe}[n]$, and sliced by the comparator **in a single clock cycle**:
     $$T_{clk} \ge T_{mult} + T_{sub} + T_{slicer} + T_{setup}$$
   - This single-cycle feedback loop forms the primary frequency bottleneck of the entire system.
2. **Speculative / Look-Ahead DFE (Loop Unrolling):**
   - For PAM-4, the past decision $\hat{d}[n-1]$ can only take 4 possible values: $\{-3.0, -1.0, +1.0, +3.0\}$.
   - In parallel, pre-calculate 4 candidate sums:
     $$y^{(k)}[n] = y_{ffe}[n] - b_0 \cdot S_k, \quad k \in \{0, 1, 2, 3\}$$
   - Slice all 4 candidates in parallel.
   - Use a fast 4:1 multiplexer controlled by the previous registered decision to select the valid symbol.
   - **Evaluation Metric for Course:** The team will analyze the timing and resource breakdown between direct-form and speculative DFE to demonstrate how loop unrolling overcomes the feedback delay bottleneck.

---

## 5. Work Breakdown for 5 Team Members

| Member | Assigned Subsystem | Key Technical Responsibilities |
| :--- | :--- | :--- |
| **Dac Huy** | **Cyclic Pattern Gen/Mon & PAM-4 TX/RX** | - RTL design of 2-bit cyclic Gray code generator (cycling $0 \to 1 \to 2 \to 3$).<br>- PAM-4 Gray TX mapper (binary to signed 16-bit Q4.12).<br>- PAM-4 Slicer (3 decision thresholds) and Gray Demapper.<br>- On-chip cyclic pattern BER Monitor (synchronization, bit error accumulation, 32-bit snapshot registers). |
| **Nhat Huy** | **Channel Impairment Engine (ISI & CLT AWGN)** | - RTL design of first-postcursor ISI channel filter ($s[n] + \text{ISI\_coeff} \cdot s[n-1]$ with normalized $h_0 = 1.0$) with configurable postcursor loss.<br>- RTL design of CLT-based AWGN generator (12 parallel Taus88 LFSR lanes, bit-mixing decorrelation, pipelined adder tree, mean-centering, and calibrated variance scaling).<br>- Noise scaling and injection adder ($r_{clean} + \sigma_{noise} \cdot \text{AWGN}$) with selectable SNR modes.<br>- Fixed-point Q4.12 saturation and boundary overflow protection. |
| **Van Phuc** | **Adaptive 3-Tap FFE Module** | - RTL design of 3-Tap FFE datapath with embedded **Adaptive Tap Units (ATUs)** for $w_0, w_1, w_2$.<br>- Implements FIR filtering and internal LMS weight adaptation ($w_k \leftarrow w_k + \mu \cdot e \cdot x_k$) with initial weight configuration (`i_cfg_ffe_w0..w2`).<br>- Pipelined multiplier datapath mapped to Xilinx `DSP48E1` slices.<br>- Runtime bypass control logic. |
| **Ngoc Cuong** | **Adaptive 1-Tap DFE Module** | - RTL design of 1-Tap DFE feedback datapath with embedded **Adaptive Tap Unit (ATU)** for $b_0$.<br>- Implements feedback subtraction ($y_{ffe} - b_0 \hat{d}$) and internal LMS weight adaptation ($b_0 \leftarrow b_0 - \mu \cdot e \cdot \hat{d}$) with initial weight configuration (`i_cfg_dfe_b0`).<br>- Direct-Form DFE vs. Speculative (Look-Ahead) DFE architecture implementation.<br>- Critical-path timing analysis of the recursive DFE feedback loop. |
| **Quy Hau** | **System Integration, Error Logic, Co-Sim & Synthesis (STA)** | - RTL design of the Decision-Directed Error Computation block ($e[n] = \hat{d}[n] - y[n]$).<br>- **Top-Level Integration:** Connect all sub-modules into `top.sv` and `rx_top.sv`.<br>- **MATLAB Golden Model & Co-Simulation:** Build simulation model and SystemVerilog testbench scoreboard for bit-true validation.<br>- **FPGA Synthesis & Timing (STA):** Run Vivado synthesis, Place & Route, static timing analysis (STA - $F_{max}$, setup/hold slacks), Arty A7 pin planning (`.xdc`), and board-level validation. |
