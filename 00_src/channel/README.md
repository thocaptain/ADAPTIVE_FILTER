# Module Specification: Channel Impairment Engine (Channel Part)

**Module Name:** `channel_top.sv`  
**Responsible Member:** Member 2 (Nhat Huy)  
**Target Platform:** Digilent Arty A7 (Xilinx Artix-7)  
**Language:** SystemVerilog  

---

## 1. Short Functional Description

The **Channel Impairment Module (`channel_top`)** emulates the physical transmission medium by injecting controlled **Inter-Symbol Interference (ISI)** and **Additive White Gaussian Noise (AWGN)** into the transmitted PAM-4 signal.

It performs three sequential operations:

1. **First-Postcursor ISI Channel Filter**:
   - Emulates high-frequency attenuation and dispersion across a bandlimited transmission line:
     $$r_{clean}[n] = s[n] + \text{ISI\_coeff} \cdot s[n-1]$$
   - $h_0$ (main cursor gain) được cố định bằng $1.0$ (`16'sh1000`), không cần bộ nhân cho cursor chính.
   - `i_cfg_isi_coeff` ($h_1$): Hệ số ISI (First Postcursor) quy định mức độ mà **điện áp của symbol trước $s[n-1]$ rò rỉ và ảnh hưởng đến điện áp của symbol sau $s[n]$** (default: $0.50$, fixed-point `16'sh0800`).
   - Controlled via `i_cfg_isi_en`. When disabled (`0`), the filter bypasses the input: $r_{clean}[n] = s[n]$.
2. **CLT-Based Hardware AWGN Generator**:
   - **Taus88 Uniform Random Backbone**: Implements $m=12$ parallel independent Tausworthe pseudo-random lanes (using component LFSRs of degrees 31, 29, 28) operating at wire speed without Block RAM.
   - **Bit-Mixing & 12-Bit Extraction**: Permutes and XORs the 32-bit output of each lane to remove cross-lane correlation, extracting a 12-bit uniform unsigned word per lane.
   - **Pipelined Binary Adder Tree**: Sums the 12 uniform 12-bit words ($S = \sum_{i=1}^{12} \text{lane}_i$) and subtracts the theoretical mean ($12 \times 2048 = 24576$) to produce a zero-mean output.
   - **Variance Normalization**: Multiplies the centered sum by a constant integer calibration factor $G_{CLT}$ and bit-shifts to produce unit-variance Gaussian noise ($\sigma = 1.0$) in signed 16-bit Q4.12 format.
3. **Noise Scaling and Injection Adder**:
   - Scales the generated unit-variance noise by `i_cfg_snr_db` ($\sigma_{noise}$ in Q4.12):
     $$\text{noise}_{scaled}[n] = \sigma_{noise} \cdot \text{AWGN}[n]$$
   - Adds the scaled noise to the ISI-distorted signal:
     $$r_{noisy}[n] = r_{clean}[n] + \text{noise}_{scaled}[n]$$
   - Applies symmetric saturation (`16'sh7FFF` to `16'sh8000`) to guarantee that fixed-point arithmetic never wraps around. Controlled via `i_cfg_awgn_en`.

---

## 2. Interface Input / Output Specifications

| Signal Name | Direction | Data Width | Format / Range | Description |
| :--- | :---: | :---: | :---: | :--- |
| `i_clk` | Input | `1` bit | Clock | Primary system clock. |
| `i_rstn` | Input | `1` bit | Active-Low Reset | Resets internal delay registers, LFSR seeds, and pipelines. |
| `i_valid` | Input | `1` bit | Control Flag | Asserted when incoming `i_tx_data` is valid. |
| `i_tx_data` | Input | `16` bits | Signed Q4.12 | PAM-4 input sample from `tx_top` ($\{-3.0, -1.0, +1.0, +3.0\}$). |
| `i_cfg_isi_en` | Input | `1` bit | Control Flag | **ISI Enable**: `1` = Enable postcursor ISI filter; `0` = Bypass ISI ($r_{clean} = s$). |
| `i_cfg_isi_coeff` | Input | `16` bits | Signed Q4.12 | **Hệ số ISI (post-cursor $h_1$)**: Hệ số quy định mức độ điện áp trước $s[n-1]$ ảnh hưởng đến điện áp sau $s[n]$ (Nominal default: `16'sh0800` $= 0.50$, $h_0$ cố định $= 1.0$). |
| `i_cfg_awgn_en`| Input | `1` bit | Control Flag | **AWGN Enable**: `1` = Add Gaussian noise; `0` = Clean signal without noise. |
| `i_cfg_snr_db` | Input | `16` bits | Signed Q4.12 | **Noise Scale / SNR Configuration**: Fixed-point noise multiplier $\sigma_{noise}$ (e.g., `16'sh0400` $= 0.25$ for moderate noise; `16'sh0000` for no noise). |
| `o_valid` | Output | `1` bit | Status Flag | Output data valid aligned with total channel processing pipeline latency. |
| `o_channel_data`| Output | `16` bits | Signed Q4.12 | **Main Output**: Composite noisy signal $r_{noisy}[n]$ sent to `rx_top`. |
| `o_clean_isi_data`| Output | `16` bits | Signed Q4.12 | **Debug Output**: Signal after ISI filter only (no AWGN). |
| `o_awgn_noise` | Output | `16` bits | Signed Q4.12 | **Debug Output**: Generated scaled Gaussian noise sample. |

---

## 3. Implementation Guidelines for Member 2

1. **Pipelining Compliance (L.O.3):** Insert register stages inside the 12-lane adder tree so that the AWGN generator achieves maximum clock frequency ($>300\text{ MHz}$).
2. **Saturation:** All summations and multiplications must use fixed-point arithmetic with saturation functions to avoid catastrophic sign inversion.
