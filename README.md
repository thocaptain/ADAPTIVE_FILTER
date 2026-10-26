# Project Specification: FPGA-Based PAM-4 Communication System with Emulated ISI Channel, CLT AWGN Generator, and Adaptive FFE-DFE Equalizer with Cyclic Pattern BER Monitor

**Course:** EE5427 – Digital System Design on FPGA  
**Target Platform:** Digilent Arty A7 (Xilinx Artix-7 XC7A35T / XC7A100T)  
**EDA Tool:** AMD Xilinx Vivado Design Suite  
**HDL Standard:** SystemVerilog  
**Team Size:** 5 Members  
**Reference Design:** Senior Thesis by Nguyen Hung Minh (HCMUT, May 2026)  

---

## 1. Executive Summary & Objective

In modern high-speed serial links (such as **PCIe 5.0/6.0, 400GE/800GE Ethernet, and USB4**), **PAM-4 (Pulse Amplitude Modulation 4-Level)** is widely adopted to double transmission throughput over conventional binary NRZ. However, packing 4 voltage levels into the same physical dynamic range degrades the SNR margin by $\approx 9.5\text{ dB}$, making PAM-4 signals highly vulnerable to high-frequency channel loss, dispersion, and **Inter-Symbol Interference (ISI)**.

This project implements an **autonomous, on-chip PAM-4 digital baseband evaluation system** on the **Digilent Arty A7 FPGA**. The system emulates a complete communications transceiver chain—including a cyclic Gray-coded transmitter, a lossy physical channel model with additive Gaussian noise, an **Adaptive Feed-Forward Equalizer (FFE)**, an **Adaptive Decision Feedback Equalizer (DFE)**, and an on-chip **Cyclic Pattern Bit Error Rate (BER) Monitor**.

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

## 2. Key Architecture Decisions & Reference Features

To adapt the reference graduation thesis into a high-scoring, modular **course assignment** for EE5427, the following key architectural choices are established:

| Feature | Reference Thesis Architecture | Proposed Assignment Architecture | Technical Motivation |
| :--- | :--- | :--- | :--- |
| **Test Pattern Generator & Monitor** | Standard high-order PRBS-7/15 LFSRs with cross-correlation lock state machines. | **2-Bit Cyclic Gray-Code Generator & Synchronized BER Monitor** (continuous cycle: `0 -> 1 -> 2 -> 3 -> 0...`). | Drastically simplifies pattern generation and reference synchronization while fully exercising all 4 PAM-4 signal levels and transitions for bit error measurement. |
| **Equalizer Tap Adaptation** | Top-level adaptive equalizer with centralized adaptation engine. | **Modular Embedded Adaptive Tap Units** implemented directly inside each **FFE** and **DFE** module. | Preserves the thesis's **LMS coefficient adaptation**, `init_alpha` preset loading, and step-size $\mu$ control, distributed cleanly into modular FFE and DFE blocks. |
| **Monitoring & Visualization** | External **ESP32-S3 microcontroller** over UART, transmitting HTTP packets via Wi-Fi to a PC web browser for eye-diagram plots. | **On-Chip Cyclic BER Monitor** directly following the PAM-4 Slicer. | Eliminates external microcontrollers, Wi-Fi dependencies, and web development. The FPGA becomes **100% self-contained**, giving deterministic, quantitative BER measurements. |

---

## 3. Detailed Subsystem Architecture

### 3.1. Transmitter (TX): Cyclic 2-Bit Gray-Code Generator & PAM-4 Mapper
- **Cyclic 2-Bit Pattern Generator**:
  - Implements a simple, deterministic 2-bit counter cycling through states:
    $$\text{Cycle: } 0 \rightarrow 1 \rightarrow 2 \rightarrow 3 \rightarrow 0 \rightarrow 1 \rightarrow 2 \rightarrow 3 \dots$$
  - Provides a repeatable, continuous test stream that visits all four PAM-4 constellation points uniformly.
- **PAM-4 Gray Mapper**:
  - Maps 2-bit binary symbols $(b_1, b_0)$ into symmetrical signed 16-bit fixed-point amplitudes (**Q4.12**: 1 sign bit, 3 integer bits, 12 fractional bits):
    - State `0` (`2'b00`) $\rightarrow -3$ (`16'shD000`)
    - State `1` (`2'b01`) $\rightarrow -1$ (`16'shF000`)
    - State `2` (`2'b10`) $\rightarrow +1$ (`16'sh1000`)
    - State `3` (`2'b11`) $\rightarrow +3$ (`16'sh3000`)

---

### 3.2. Channel Model: First-Postcursor ISI & Hardware AWGN Generator

#### A. ISI Channel Model
Emulates high-frequency attenuation and dispersion characteristic of lossy backplanes:
$$r_{clean}[n] = s[n] + \text{ISI\_coeff} \cdot s[n-1]$$
- Main cursor gain $h_0$ được chuẩn hóa cố định bằng $1.0$ (không cần bộ nhân phần cứng cho $h_0$).
- `i_cfg_isi_coeff` ($h_1$): First-postcursor distortion factor — hệ số quy định mức độ điện áp của symbol trước $s[n-1]$ ảnh hưởng đến điện áp sau $s[n]$ (e.g., $0.35$ đến $0.50$, cấu hình qua port `i_cfg_isi_coeff`).

#### B. CLT-Based AWGN Generator
- **Uniform Backbone**: $m=12$ parallel **Taus88** combined Tausworthe pseudo-random number generators. Each lane combines 3 LFSRs (degrees 31, 29, 28) using shifts, masks, and XOR gates (aggregate period $\approx 2^{88}$).
- **Bit-Mixing**: Lightweight bit permutation and XOR decorrelator extracting a 12-bit unsigned uniform word per lane.
- **Pipelined Adder Tree**: Multi-stage binary adder tree summing the twelve 12-bit words ($S = \sum_{i=1}^{12} \text{lane}_i$), followed by subtraction of the theoretical mean ($12 \times 2048 = 24576$).
- **Normalized Scaling**: Multiplies the centered sum by pre-calculated constant integer gain $G_{CLT}$ and bit-shifts to obtain unit-variance noise ($\sigma = 1.0$, Q4.12).
- **Noise Injection**:
  $$r_{noisy}[n] = r_{clean}[n] + \sigma_{noise} \cdot \text{AWGN}[n]$$
  $\sigma_{noise}$ is selectable via board switches to simulate different SNR levels ($15\text{ dB}, 20\text{ dB}, 25\text{ dB}, \infty\text{ dB / No Noise}$).

---

### 3.3. Equalizer Core: Adaptive 3-Tap FFE & Adaptive 1-Tap DFE

In this design, **each equalizer module (FFE and DFE) embeds its own LMS coefficient adaptation logic**, preserving the Adaptive Tap Unit (ATU) architecture from the reference thesis:

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
               | w_k <= w_k + mu * e * x_k        | <--- i_init_alpha_FFE   |
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
|                 |    | Tap 0 (b0)                  | <--- i_init_alpha_DFE|
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
- **Filtering Datapath**: 3-tap FIR filter operating on incoming samples $x[n], x[n-1], x[n-2]$:
  $$y_{ffe}[n] = \sum_{k=0}^{2} w_k[n] \cdot x[n-k]$$
- **Embedded Tap Adaptation**:
  - Each tap contains its own internal coefficient register initialized via `i_init_alpha_FFE[k]`.
  - Continuously updates weights using the error signal $e[n]$:
    $$w_k[n+1] = w_k[n] + \mu \cdot e[n] \cdot x[n-k]$$
- **DSP Mapping & Pipelining**: Tap multiplications and adder tree are mapped to Xilinx **DSP48E1** slices with internal pipeline registers.

#### B. Adaptive 1-Tap Decision Feedback Equalizer (DFE) Module
- **Filtering Datapath**: Reconstructs the first-postcursor ISI tail from the previous sliced decision $\hat{d}[n-1]$:
  $$y_{dfe}[n] = b_0[n] \cdot \hat{d}[n-1]$$
- **Equalizer Subtraction**:
  $$y[n] = y_{ffe}[n] - y_{dfe}[n]$$
- **Embedded Tap Adaptation**:
  - Contains its own internal feedback coefficient register initialized via `i_init_alpha_DFE`.
  - Continuously updates the feedback weight:
    $$b_0[n+1] = b_0[n] - \mu \cdot e[n] \cdot \hat{d}[n-1]$$

#### C. Error Generation & Slicer
- **PAM-4 Slicer**: Compares $y[n]$ against thresholds ($-2.0, 0.0, +2.0$) to produce the hard decision $\hat{d}[n] \in \{-3, -1, +1, +3\}$.
- **Decision-Directed Error Generation**:
  $$e[n] = \hat{d}[n] - y[n]$$
  Operates purely in **Decision-Directed LMS (DD-LMS)** mode, computing the difference between the hard-decision sliced symbol $\hat{d}[n]$ and the equalizer pre-slicer sample $y[n]$.
- Error $e[n]$ is broadcast back to both the FFE and DFE modules to drive their respective Adaptive Tap Units.

---

### 3.4. On-Chip Cyclic Pattern BER Monitor
- **Deterministic Delay Match**: Because the transmitter pattern is a known cyclic sequence ($0 \rightarrow 1 \rightarrow 2 \rightarrow 3$), the expected symbol/bits at the receiver are generated locally via a matched 2-bit counter synchronized with the total datapath latency ($D_{total}$).
- **Bit & Symbol Comparator**: Compares recovered bits with expected bits on each clock cycle:
  $$\text{Bit Error} = (\text{recovered\_bits} \neq \text{expected\_bits})$$
- **Accumulation Counters**:
  - **Total Bit Counter**: 48-bit register accumulating evaluated bits.
  - **Bit Error Counter**: 32-bit register counting mismatched bits.
  - Computes and outputs real-time Bit Error Rate (BER).

---

## 4. Hardware Pipelining Strategy & L.O.3 Compliance

The course syllabus highlights **L.O.3: Pipeline design and latency vs. throughput trade-off analysis**. This project provides an ideal architecture for this analysis:

### 4.1. FFE Feed-Forward Pipelining
- Because the FFE is an open-loop FIR filter, registers can be inserted between the multiplication stage and the adder-tree reduction stage without recursion constraints.
- Multipliers and adders are mapped to Xilinx **DSP48E1** slices (`ug479`), utilizing dedicated internal pipeline registers (`AREG=1, BREG=1, MREG=1, PREG=1`) to achieve clock speeds $>200\text{ MHz}$ on Artix-7.

### 4.2. DFE Feedback Loop: Direct-Form vs. Speculative (Look-Ahead) DFE
The DFE contains a **recursive feedback loop** that represents a classic hardware critical path:
1. **Direct-Form DFE Constraint**:
   - The feedback decision $\hat{d}[n-1]$ must be multiplied by $b_0$, subtracted from FFE output $y_{ffe}[n]$, and sliced by the comparator **in a single clock cycle**:
     $$T_{clk} \ge T_{mult} + T_{sub} + T_{slicer} + T_{setup}$$
   - This single-cycle feedback bottleneck limits the maximum clock frequency of the entire system.
2. **Speculative / Look-Ahead DFE (Loop Unrolling)**:
   - For PAM-4, past decision $\hat{d}[n-1]$ can only take 4 possible values: $\{-3, -1, +1, +3\}$.
   - In parallel, pre-calculate 4 candidate sums:
     $$y^{(k)}[n] = y_{ffe}[n] - b_0 \cdot S_k, \quad k \in \{0, 1, 2, 3\}$$
   - Slice all 4 candidates in parallel.
   - Use a fast 4:1 multiplexer controlled by the previous registered decision to select the valid symbol.
   - **Evaluation Metric for Course:** Group will implement both versions (or analyze the critical path breakdown) to demonstrate how pipelining/loop unrolling overcomes the feedback delay bottleneck.

---

## 5. Work Breakdown for 5 Team Members

| Member | Assigned Subsystem | Key Technical Responsibilities |
| :--- | :--- | :--- |
| **Dac Huy** | **Cyclic Pattern Gen/Mon & PAM-4 TX/RX** | - RTL design of 2-bit cyclic Gray-code generator (cycling $0 \rightarrow 1 \rightarrow 2 \rightarrow 3$).<br>- PAM-4 Gray TX mapper (binary to signed 16-bit Q4.12).<br>- PAM-4 Slicer (3 decision thresholds) and Gray Demapper.<br>- On-chip cyclic pattern BER Monitor (delay matching, bit error counter, total bit counter). |
| **Nhat Huy** | **Channel Impairment Engine (ISI & CLT AWGN)** | - RTL design of first-postcursor ISI channel filter ($s[n] + \text{ISI\_coeff} \cdot s[n-1]$ với $h_0 = 1.0$) with configurable postcursor loss profile.<br>- RTL design of CLT-based AWGN generator (12 parallel Taus88 LFSR lanes, bit-mixing decorrelation, pipelined adder tree, mean-centering, and calibrated variance scaling).<br>- Noise scaling and injection adder ($r_{clean} + \sigma_{noise} \cdot \text{AWGN}$) with selectable SNR modes.<br>- Fixed-point Q4.12 saturation and boundary overflow protection. |
| **Van Phuc** | **Adaptive 3-Tap FFE Module** | - RTL design of 3-Tap FFE datapath with embedded **Adaptive Tap Units (ATU)** for $w_0, w_1, w_2$.<br>- Implements FIR filtering and internal LMS weight adaptation ($w_k \leftarrow w_k + \mu \cdot e \cdot x_k$) with initial weight configuration (`init_alpha_FFE`).<br>- Pipelined multiplier datapath mapped to Xilinx `DSP48E1` slices.<br>- Runtime bypass control logic. |
| **Ngoc Cuong** | **Adaptive 1-Tap DFE Module** | - RTL design of 1-Tap DFE feedback datapath with embedded **Adaptive Tap Unit (ATU)** for $b_0$.<br>- Implements feedback subtraction ($y_{ffe} - b_0 \hat{d}$) and internal LMS weight adaptation ($b_0 \leftarrow b_0 - \mu \cdot e \cdot \hat{d}$) with initial weight configuration (`init_alpha_DFE`).<br>- Direct-Form DFE vs. Speculative (Look-Ahead) DFE architecture implementation.<br>- Critical-path timing analysis of the recursive DFE feedback loop. |
| **Quy Hau** | **System Integration, Error Logic, Co-Sim & Synthesis (STA)** | - RTL design of the Decision-Directed Error Computation block ($e[n] = \hat{d}[n] - y[n]$).<br>- **Top-Level Integration:** Connect all sub-modules into `pam4_transceiver_top.sv`.<br>- **MATLAB Golden Model & Co-Simulation:** Build simulation model and SystemVerilog testbench scoreboard for bit-true validation.<br>- **FPGA Synthesis & Timing (STA):** Run Vivado synthesis, Place & Route, static timing analysis (STA - $F_{max}$, setup/hold slacks), Arty A7 pin planning (`.xdc`), and board-level validation. |
