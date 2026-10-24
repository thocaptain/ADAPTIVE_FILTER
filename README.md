# FPGA-Based PAM-4 Communication System with Emulated ISI Channel, CLT AWGN Generator, and Configurable FFE-DFE Equalizer with On-Chip BER Tester

**Course:** EE5427 – Digital System Design on FPGA  
**Target Platform:** Digilent Arty A7 (Xilinx Artix-7 XC7A35T / XC7A100T)  
**EDA Tool:** AMD Xilinx Vivado Design Suite  
**HDL Standard:** SystemVerilog  
**Team Size:** 5 Members  

---

## 1. Executive Summary & Objective

In modern high-speed serial links (such as **PCIe 5.0/6.0, 400GE/800GE Ethernet, and USB4**), **PAM-4 (Pulse Amplitude Modulation 4-Level)** is widely adopted to double transmission throughput over conventional binary NRZ. However, packing 4 voltage levels into the same physical dynamic range degrades the SNR margin by $\approx 9.5\text{ dB}$, making PAM-4 signals highly vulnerable to high-frequency channel loss, dispersion, and **Inter-Symbol Interference (ISI)**.

This project implements an **autonomous, on-chip PAM-4 digital baseband evaluation system** on the **Digilent Arty A7 FPGA**. The system emulates a complete communications transceiver chain—including a pseudo-random transmitter, a lossy physical channel model with additive Gaussian noise, a configurable **Feed-Forward Equalizer (FFE)**, a **Decision Feedback Equalizer (DFE)**, and an on-chip **Bit Error Rate Tester (BERT)**.

```
+-----------------------------------------------------------------------------------------------------------------+
|                                             FPGA On-Chip Testbench                                              |
|                                                                                                                 |
|  +------------+     +------------+     +---------------+     +---------------+                                  |
|  | PRBS Gen   | --> | PAM-4 TX   | --> | Lossy Channel | --> |  Noise Adder  | ---------------------+           |
|  | (PRBS-7/15)|     | Gray Map   |     | Model (ISI)   |     | (r_clean+AWGN)|                      |           |
|  +------------+     +------------+     +---------------+     +---------------+                      |           |
|        |                                                             ^                              v           |
|        |                                                             |     +---------------------------------+  |
|        |                                                     +---------------+   Configurable 3-Tap FFE +    |  |
|        |                                                     | CLT AWGN Gen  |   1-Tap DFE Equalizer         |  |
|        |                                                     | (12 Taus88 L) |                               |  |
|        |                                                     +---------------+     +------------------+      |  |
|        |                                                                     |     |    3-Tap FFE     |      |  |
|        |                                                                     |     |  (Precursor ISI) |      |  |
|        |                                                                     |     +------------------+      |  |
|        |                                                                     |               |               |  |
|        |                                                                     |               v (+)           |  |
|        |                                                                     |             (Summer) <-- y[n] |  |
|        |                                                                     |               ^ (-)    (pre-  |  |
|        |                                                                     |               |        slicer)|  |
|        |                                                                     |     +------------------+      |  |
|        |                                                                     |  +- |    1-Tap DFE     |      |  |
|        |                                                                     |  |  |  (Postcursor ISI)|      |  |
|        |                                                                     |  |  +------------------+      |  |
|        |                                                                     |  |            ^               |  |
|        |                                                                     |  | d_hat[n-1] |               |  |
|        |                                                                     |  |  +------------------+      |  |
|        |                                                                     |  +->|   PAM-4 Slicer   | ----+ |  |
|        |                                                                     |     | (Symbol Decision)|     | |  |
|        |                                                                     |     +------------------+     | |  |
|        |                                                                     +------------------------------|-+  |
|        |                                                                                                    |   |
|        |               +------------------------------------------------------------------------------------+   |
|        |               | Recovered Bits [1:0]                                                                   |
|        v               v                                                                                        |
|  +---------------------------+                                                                                  |
|  | PRBS Monitor              |                                                                                  |
|  | (BER)                     |                                                                                  |
|  +---------------------------+                                                                                  |
+-----------------------------------------------------------------------------------------------------------------+
```

---

## 2. Key Simplifications from Reference Thesis

To adapt the reference graduation thesis into a well-scoped, highly reliable **course assignment** for EE5427 without sacrificing academic rigor, two major simplifications are introduced:

| Feature | Reference Thesis Architecture | Proposed Assignment Architecture | Justification & Benefits |
| :--- | :--- | :--- | :--- |
| **Equalizer Tap Weights** | Real-time adaptive **Clipped-LMS Engine** (training state machine, gradient multipliers, step-size tuning, projection registers). | **Static / Pre-Programmed Configurable Coefficients** (selectable presets via DIP switches or AXI/register config). | Eliminates complex adaptive feedback loops, divergence risks, and $>16$ hardware multipliers. Allows clear focus on **filtering datapath pipelining, latency, and throughput**. |
| **Monitoring & Visualization** | External **ESP32-S3 microcontroller** over UART, transmitting HTTP packets via Wi-Fi to a PC web browser for eye-diagram plots. | **On-Chip PRBS Monitor / BERT (Bit Error Rate Tester)** directly following the PAM-4 Slicer. | Eliminates all external microcontrollers, Wi-Fi connectivity, and web development. The FPGA becomes **100% self-contained**, outputting deterministic, quantitative BER/SER measurements. |

---

## 3. Detailed Subsystem Architecture

### 3.1. Transmitter (TX): PRBS Generator & PAM-4 Mapper
- **PRBS Generator**: Implements configurable **PRBS-7** ($X^7 + X^6 + 1$) and **PRBS-15** ($X^{15} + X^{14} + 1$) linear-feedback shift registers (LFSR) producing continuous pseudo-random bit streams at 1 bit or 2 bits per clock cycle.
- **PAM-4 Gray Mapper**: Packs 2 consecutive binary bits $(b_1, b_0)$ into one 4-level PAM-4 symbol using standard Gray coding to ensure that adjacent level errors result in only a single bit error:
  - `00` $\rightarrow -3$ (`16'hD000` in Q4.12 fixed-point)
  - `01` $\rightarrow -1$ (`16'hF000` in Q4.12 fixed-point)
  - `11` $\rightarrow +1$ (`16'h1000` in Q4.12 fixed-point)
  - `10` $\rightarrow +3$ (`16'h3000` in Q4.12 fixed-point)
- **Output Format**: Signed 16-bit fixed-point **Q4.12** (1 sign bit, 3 integer bits, 12 fractional bits).

---

### 3.2. Channel Model: First-Postcursor ISI & Hardware AWGN Generator

#### A. ISI Channel Model
Emulates high-frequency attenuation and dispersion characteristic of lossy backplanes:
$$r_{clean}[n] = h_0 \cdot s[n] + h_1 \cdot s[n-1]$$
- $h_0$: Main cursor gain (e.g., $0.80$).
- $h_1$: First-postcursor distortion factor (e.g., $0.35$ to $0.50$, selectable via switches to simulate mild, moderate, or severe channel loss).

#### B. CLT-Based AWGN Generator
- **Uniform Backbone**: $m=12$ parallel **Taus88** combined Tausworthe pseudo-random number generators. Each lane combines 3 LFSRs (degrees 31, 29, 28) using shifts, masks, and XOR gates (aggregate period $\approx 2^{88}$).
- **Bit-Mixing**: Lightweight bit permutation and XOR decorrelator extracting a 12-bit unsigned uniform word per lane.
- **Pipelined Adder Tree**: Multi-stage binary adder tree summing the twelve 12-bit words ($S = \sum_{i=1}^{12} \text{lane}_i$), followed by subtraction of the theoretical mean ($12 \times 2048 = 24576$).
- **Normalized Scaling**: Multiplies the centered sum by pre-calculated constant integer gain $G_{CLT}$ and bit-shifts to obtain unit-variance noise ($\sigma = 1.0$, Q4.12).
- **Noise Injection**:
  $$r_{noisy}[n] = r_{clean}[n] + \sigma_{noise} \cdot \text{AWGN}[n]$$
  $\sigma_{noise}$ is selectable via board switches to simulate different SNR levels ($15\text{ dB}, 20\text{ dB}, 25\text{ dB}, \infty\text{ dB / No Noise}$).

---

### 3.3. Equalizer Core: 3-Tap FFE & 1-Tap DFE

```
                         +-----------------------------------+
                         | 3-Tap Feed-Forward Equalizer(FFE) |
                         +-----------------------------------+
                                           |
r_noisy[n] ---+----------> [ z^-1 ] ------> [ z^-1 ]
              |               |               |
              v (w0)          v (w1)          v (w2)
           (Mult 0)        (Mult 1)        (Mult 2)
              |               |               |
              +-------> ( + ) <---------------+
                          |
                          v
                      ( + / - ) <------------------------- (Mult DFE: b0)
                          |                                     ^
                          | Pre-Slicer y[n]                     |
                          v                               +------------+
                   [ PAM-4 Slicer ] --------------------> | z^-1 (Reg) |
                          |                               +------------+
                          v Sliced Symbol d_hat[n]
                   [ Gray Demapper ]
                          |
                          v Recovered Bits [1:0]
```

#### A. 3-Tap Feed-Forward Equalizer (FFE)
- **Structure**: Finite Impulse Response (FIR) filter with 3 taps $[w_0, w_1, w_2]$ operating on incoming samples $x[n], x[n-1], x[n-2]$.
- **Role**: Cancels precursor ISI and provides high-frequency peaking to open the eye.
- **Bypass Feature**: Can be bypassed via a control signal ($w_0 = 1.0, w_1 = 0, w_2 = 0$) to evaluate baseline channel degradation.

#### B. 1-Tap Decision Feedback Equalizer (DFE)
- **Structure**: Takes the sliced decision from the immediately preceding symbol ($\hat{d}[n-1]$), multiplies it by feedback weight $b_0$, and subtracts it from the FFE output:
  $$y[n] = \sum_{k=0}^{2} w_k x[n-k] - b_0 \hat{d}[n-1]$$
- **Role**: Reconstructs and subtracts the postcursor tail without amplifying high-frequency noise.
- **Bypass Feature**: Setting $b_0 = 0$ disables DFE feedback for comparative benchmarking.

#### C. PAM-4 Slicer & Demapper
- Compares pre-slicer sample $y[n]$ against three fixed decision thresholds (nominally $-2.0, 0.0, +2.0$ in Q4.12):
  - $y[n] < -2.0 \implies \hat{d}[n] = -3$ (`00`)
  - $-2.0 \le y[n] < 0.0 \implies \hat{d}[n] = -1$ (`01`)
  - $0.0 \le y[n] < +2.0 \implies \hat{d}[n] = +1$ (`11`)
  - $y[n] \ge +2.0 \implies \hat{d}[n] = +3$ (`10`)
- Outputs the 2-bit recovered data $(r_1, r_0)$ to the PRBS monitor.

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
| **Member 1** | **PRBS Gen/Mon & PAM-4 TX/RX** | - RTL design of PRBS-7 and PRBS-15 generator.<br>- PAM-4 Gray TX mapper (binary to signed 16-bit Q4.12).<br>- PAM-4 Slicer (3 decision thresholds) and Gray Demapper.<br>- PRBS Monitor / BERT (latency-matching delay FIFO, bit/symbol error comparator, BER accumulation). |
| **Member 2** | **Channel Impairment Engine (ISI & CLT AWGN)** | - RTL design of first-postcursor ISI channel filter ($h_0 \cdot s[n] + h_1 \cdot s[n-1]$) with selectable loss profiles.<br>- RTL design of CLT-based AWGN generator (12 parallel Taus88 LFSR lanes, bit-mixing decorrelation, pipelined adder tree, mean-centering, and calibrated variance scaling).<br>- Noise scaling and injection adder ($r_{clean} + \sigma_{noise} \cdot \text{AWGN}$) with selectable SNR modes.<br>- Fixed-point Q4.12 saturation and boundary overflow protection. |
| **Member 3** | **Configurable 3-Tap FFE Core** | - RTL design of pipelined 3-tap FIR filter datapath mapped to Xilinx `DSP48E1` slices.<br>- Fixed-point coefficient register bank (takes pre-calculated weights from Member 5).<br>- Runtime bypass logic and precursor ISI cancellation datapath. |
| **Member 4** | **Configurable 1-Tap DFE Core** | - RTL design of 1-tap DFE feedback datapath and summer ($y_{ffe}[n] - b_0 \hat{d}[n-1]$) with bypass control (takes pre-calculated weight from Member 5).<br>- Direct-Form DFE vs. Speculative (Look-Ahead) DFE architecture implementation.<br>- Critical-path timing analysis of the recursive DFE feedback loop. |
| **Member 5** | **System Integration, Co-Sim, Synthesis (STA) & MATLAB Weights** | - **MATLAB Modeling:** Calculate initial / optimal FFE tap weights $[w_0, w_1, w_2]$ and DFE feedback weight $b_0$ for each channel profile (MMSE / Zero-Forcing / offline LMS) and provide quantized fixed-point coefficients for RTL.<br>- **Top-Level Integration:** Connect all sub-modules into `pam4_transceiver_top.sv`.<br>- **Co-Simulation & Verification:** Build self-checking testbench comparing RTL outputs against the MATLAB golden reference model.<br>- **FPGA Synthesis & Timing (STA):** Run Vivado synthesis, Place & Route, static timing analysis (STA - $F_{max}$, setup/hold slacks), Arty A7 pin planning (`.xdc`), and board-level validation. |
