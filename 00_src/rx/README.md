# Module Specification: Receiver Subsystem (RX Part)

**Top Module Name:** `rx_top.sv`  
**Sub-Modules:**  
- `rx_ffe.sv` — **Member 3 (Van Phuc)**  
- `rx_dfe.sv` — **Member 4 (Ngoc Cuong)**  
- `rx_monitor.sv` — **Member 1 (Dac Huy)**  
- `rx_top.sv` (Integration & Error Logic) — **Member 5 (Quy Hau)**  

**Target Platform:** Digilent Arty A7 (Xilinx Artix-7)  
**Language:** SystemVerilog  

---

## 1. Short Functional Description

The **Receiver Subsystem (`rx_top`)** equalizes the distorted PAM-4 channel signal, recovers the transmitted 2-bit binary symbols, and continuously measures the Bit Error Rate (BER).

The architecture is partitioned into three cooperating sub-modules:

```
                            +-------------------------------------------------+
                            |                     rx_top                      |
                            |                                                 |
  i_r_in [15:0] ------------+--> [ rx_ffe ] ------------------> (+)           |
  (Noisy Sample)            |    (3 Taps: w0, w1, w2)            |            |
                            |    (Embedded LMS Tap Update)       v            |
                            |                                (Summer)         |
                            |                                    ^ (-)        |
                            |                                    |            |
                            |    +-------------------------------+            |
                            |    | Pre-slicer y[n]                            |
                            |    v                                            |
                            | [ PAM-4 Slicer ] ----------------+              |
                            | (Decision d_hat: -3,-1,+1,+3)    |              |
                            |    |                             |              |
                            |    v                             v              |
                            | [ rx_monitor ]             [ rx_dfe ]           |
                            | (Demap + BER Counter)      (1 Tap: b0)          |
                            |                            (Embedded LMS Update)|
                            +-------------------------------------------------+
```

### 1.1. Adaptive 3-Tap FFE (`rx_ffe.sv` - Member 3: Van Phuc)
- **FIR Filtering Datapath**: Implements a 3-tap delay line $[x_0, x_1, x_2]$:
  $$y_{ffe}[n] = w_0 \cdot x[n] + w_1 \cdot x[n-1] + w_2 \cdot x[n-2]$$
- **Embedded LMS Adaptation**: Each tap contains its own coefficient register and updates dynamically:
  $$w_k[n+1] = w_k[n] + \mu \cdot e[n] \cdot x[n-k]$$
- **Configurability**: Accepts initial tap weights (`i_cfg_ffe_w0, w1, w2`) and supports runtime bypass (`i_cfg_ffe_en = 0`).

### 1.2. Adaptive 1-Tap DFE (`rx_dfe.sv` - Member 4: Ngoc Cuong)
- **Feedback Cancellation Datapath**: Reconstructs the first-postcursor ISI tail from the previous sliced decision $\hat{d}[n-1]$:
  $$y_{dfe}[n] = b_0 \cdot \hat{d}[n-1]$$
- **Embedded LMS Adaptation**: Updates the feedback coefficient:
  $$b_0[n+1] = b_0[n] - \mu \cdot e[n] \cdot \hat{d}[n-1]$$
- **Configurability**: Accepts initial feedback weight `i_cfg_dfe_b0` and supports runtime bypass (`i_cfg_dfe_en = 0`).
- **Timing Architecture**: Prepared for Direct-Form feedback and Speculative (Look-Ahead) loop unrolling.

### 1.3. Equalizer Summer & PAM-4 Slicer (in `rx_top.sv` - Member 5: Quy Hau)
- **Equalizer Summer**: Computes the pre-slicer equalized waveform:
  $$y[n] = y_{ffe}[n] - y_{dfe}[n]$$
- **PAM-4 Slicer (Comparator)**:
  - $y[n] < -2.0 \implies \hat{d}[n] = -3$ (`16'shD000`)
  - $-2.0 \le y[n] < 0.0 \implies \hat{d}[n] = -1$ (`16'shF000`)
  - $0.0 \le y[n] < +2.0 \implies \hat{d}[n] = +1$ (`16'sh1000`)
  - $y[n] \ge +2.0 \implies \hat{d}[n] = +3$ (`16'sh3000`)
- **Decision-Directed Error Generation**:
  $$e[n] = \hat{d}[n] - y[n]$$
  Uses pure **Decision-Directed LMS (DD-LMS)**: calculates the difference between the quantized symbol decision $\hat{d}[n]$ (after PAM-4 slicer) and the equalized sample $y[n]$ (before slicer). Error $e[n]$ is broadcast directly to both `rx_ffe` and `rx_dfe`.

### 1.4. Cyclic Pattern BER Monitor (`rx_monitor.sv` - Member 1: Dac Huy)
- Demaps sliced PAM-4 symbols into Gray code and converts to 2-bit binary ($0, 1, 2, 3$).
- Synchronizes with the transmitter's repeating cyclic sequence ($0 \rightarrow 1 \rightarrow 2 \rightarrow 3$).
- Computes bit-level errors and accumulates:
  - **Total Evaluated Words** (32-bit register).
  - **Bit Error Count** (32-bit register).
- A snapshot trigger (`i_cfg_snapshot_trig`) latches live counters into readable status registers for non-disruptive monitoring.

---

## 2. Interface Input / Output Specifications

### 2.1. `rx_top.sv` Interface (Top-Level Receiver)

| Signal Name | Direction | Data Width | Format / Range | Description |
| :--- | :---: | :---: | :---: | :--- |
| `i_clk` | Input | `1` bit | Clock | Primary system clock. |
| `i_rstn` | Input | `1` bit | Active-Low Reset | Resets all internal pipelines, tap registers, and monitor counters. |
| `i_valid` | Input | `1` bit | Control Flag | Indicates valid incoming sample from `channel_top`. |
| `i_r_in` | Input | `16` bits | Signed Q4.12 | Noisy, distorted PAM-4 input sample from `channel_top`. |
| `i_cfg_ffe_en` | Input | `1` bit | Control Flag | **FFE Enable**: `1` = Active FFE filtering; `0` = Bypass FFE. |
| `i_cfg_dfe_en` | Input | `1` bit | Control Flag | **DFE Enable**: `1` = Active DFE feedback; `0` = Bypass DFE ($y_{dfe} = 0$). |
| `i_cfg_ffe_w0` | Input | `16` bits | Signed Q4.12 | Preset initial weight for FFE tap 0 (Default: `16'sh1000` = 1.0). |
| `i_cfg_ffe_w1` | Input | `16` bits | Signed Q4.12 | Preset initial weight for FFE tap 1 (Default: `16'sh0000` = 0.0). |
| `i_cfg_ffe_w2` | Input | `16` bits | Signed Q4.12 | Preset initial weight for FFE tap 2 (Default: `16'sh0000` = 0.0). |
| `i_cfg_dfe_b0` | Input | `16` bits | Signed Q4.12 | Preset initial weight for DFE tap 0 (Default: `16'sh0800` = 0.5). |
| `i_cfg_lms_en` | Input | `1` bit | Control Flag | **LMS Enable**: `1` = Adapt weights; `0` = Hold/freeze weights. |
| `i_cfg_learning_rate`| Input | `16` bits | Signed Q0.16 | LMS adaptation step size $\mu$ (Nominal default: `16'sh0100` $\approx 0.0039$). |
| `i_cfg_mon_en` | Input | `1` bit | Control Flag | **Monitor Enable**: `1` = Run BER accumulation; `0` = Reset/Hold. |
| `i_cfg_snapshot_trig`| Input| `1` bit | Pulse Flag | **Snapshot Trigger**: Rising pulse latches counters into readable status registers. |
| `o_valid` | Output | `1` bit | Status Flag | Output data valid. |
| `o_data_before_slicer`| Output|`16` bits | Signed Q4.12 | Pre-slicer equalized waveform $y[n]$ (for observation). |
| `o_sliced_symbol` | Output | `16` bits | Signed Q4.12 | Sliced symbol decision $\hat{d}[n] \in \{-3, -1, +1, +3\}$. |
| `o_recovered_bits`| Output | `2` bits | Binary | Final recovered 2-bit symbol ($0, 1, 2, 3$). |
| `o_error` | Output | `16` bits | Signed Q4.12 | Current LMS adaptation error $e[n]$. |
| `o_stat_total_words`| Output| `32` bits | Unsigned Int | **Read Status Reg 1**: Total evaluated words captured at snapshot trigger. |
| `o_stat_err_bits` | Output | `32` bits | Unsigned Int | **Read Status Reg 2**: Total bit errors captured at snapshot trigger. |
| `o_curr_ffe_w0..w2`| Output | `16` bits | Signed Q4.12 | Current live FFE tap weights (for debug). |
| `o_curr_dfe_b0` | Output | `16` bits | Signed Q4.12 | Current live DFE feedback tap weight (for debug). |

---

### 2.2. `rx_ffe.sv` Interface (Member 3: Van Phuc)

| Signal Name | Direction | Data Width | Description |
| :--- | :---: | :---: | :--- |
| `i_clk`, `i_rstn` | Input | `1` bit | Clock and active-low reset. |
| `i_valid` | Input | `1` bit | Input valid from channel. |
| `i_r_in` | Input | `16` bits | Received sample $x[n]$ (Q4.12). |
| `i_cfg_ffe_en` | Input | `1` bit | `1` = Active FIR; `0` = Bypass FFE. |
| `i_cfg_ffe_w0..w2` | Input | `16` bits | Initial/preset tap coefficients. |
| `i_cfg_lms_en` | Input | `1` bit | Enable LMS weight update. |
| `i_error` | Input | `16` bits | Error $e[n]$ from `rx_top` (Q4.12). |
| `i_learning_rate` | Input | `16` bits | Step-size $\mu$ (Q0.16). |
| `o_valid` | Output | `1` bit | Aligned valid output. |
| `o_ffe_data` | Output | `16` bits | Equalized FFE output $y_{ffe}[n]$ (Q4.12). |
| `o_curr_w0..w2` | Output | `16` bits | Real-time tap weights for observation. |

---

### 2.3. `rx_dfe.sv` Interface (Member 4: Ngoc Cuong)

| Signal Name | Direction | Data Width | Description |
| :--- | :---: | :---: | :--- |
| `i_clk`, `i_rstn` | Input | `1` bit | Clock and active-low reset. |
| `i_valid` | Input | `1` bit | Valid signal from slicer. |
| `i_sliced_data` | Input | `16` bits | Hard sliced symbol $\hat{d}[n]$ (Q4.12). |
| `i_cfg_dfe_en` | Input | `1` bit | `1` = Active feedback; `0` = Bypass ($y_{dfe} = 0$). |
| `i_cfg_dfe_b0` | Input | `16` bits | Initial/preset feedback weight $b_0$. |
| `i_cfg_lms_en` | Input | `1` bit | Enable LMS feedback weight adaptation. |
| `i_error` | Input | `16` bits | Error $e[n]$ from `rx_top` (Q4.12). |
| `i_learning_rate` | Input | `16` bits | Step-size $\mu$ (Q0.16). |
| `o_valid` | Output | `1` bit | Aligned valid output. |
| `o_dfe_data` | Output | `16` bits | Feedback term $y_{dfe}[n] = b_0 \hat{d}[n-1]$ to be subtracted. |
| `o_curr_b0` | Output | `16` bits | Real-time feedback weight for observation. |

---

### 2.4. `rx_monitor.sv` Interface (Member 1: Dac Huy)

| Signal Name | Direction | Data Width | Description |
| :--- | :---: | :---: | :--- |
| `i_clk`, `i_rstn` | Input | `1` bit | Clock and active-low reset. |
| `i_valid` | Input | `1` bit | Valid indicator from slicer. |
| `i_sliced_data` | Input | `16` bits | Sliced PAM-4 symbol $\hat{d}[n]$ (Q4.12). |
| `i_cfg_mon_en` | Input | `1` bit | Enable BER counter accumulation. |
| `i_cfg_snapshot_trig`| Input | `1` bit | Pulse to latch live counters into status registers. |
| `o_recovered_gray` | Output | `2` bits | Recovered 2-bit Gray code. |
| `o_recovered_bin` | Output | `2` bits | Recovered 2-bit binary symbol ($0, 1, 2, 3$). |
| `o_bit_error_pulse` | Output | `1` bit | High for 1 cycle when any bit mismatch occurs. |
| `o_stat_total_words`| Output | `32` bits | Latched count of total evaluated symbols. |
| `o_stat_err_bits` | Output | `32` bits | Latched count of total bit errors. |

---

## 3. Implementation Guidelines
1. **Pipelining & L.O.3:** 
   - Member 3 (`rx_ffe`): Utilize internal DSP48E1 registers for multiplication and adder tree.
   - Member 4 (`rx_dfe`): Contrast direct-form 1-cycle feedback timing vs. 4-way speculative look-ahead slicing.
   - Member 5 (`rx_top`): Manage latency alignment between FFE feedforward path, DFE feedback path, error computation, and monitor.
