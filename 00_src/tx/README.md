# Module Specification: Transmitter (TX Part)

**Module Name:** `tx_top.sv`  
**Responsible Member:** Member 1 (Dac Huy)  
**Target Platform:** Digilent Arty A7 (Xilinx Artix-7)  
**Language:** SystemVerilog  

---

## 1. Short Functional Description

The **Transmitter Top-Level Module (`tx_top`)** generates the test pattern and maps it into standard 4-level Pulse Amplitude Modulation (PAM-4) fixed-point waveforms. It performs two core functions:

1. **2-Bit Cyclic Pattern Generation**:
   - Rather than complex PRBS polynomials, it implements a deterministic 2-bit counter that cycles continuously through decimal states:
     $$\text{Pattern: } 0 \rightarrow 1 \rightarrow 2 \rightarrow 3 \rightarrow 0 \rightarrow 1 \rightarrow 2 \rightarrow 3 \dots$$
   - Each state transition is controlled by `i_cfg_tx_en`. When enabled, it outputs one new symbol on every active clock edge.
2. **Gray Code Encoding & PAM-4 Amplitude Mapping**:
   - Converts the 2-bit binary count into 2-bit Gray code:
     $$\text{Gray}[1:0] = \text{Binary}[1:0] \oplus (\text{Binary}[1:0] \gg 1)$$
   - Maps the 2-bit Gray code into a **signed 16-bit fixed-point Q4.12** format (1 sign bit, 3 integer bits, 12 fractional bits, $1.0 = \text{16'sh1000}$):
     - `2'b00` $\longrightarrow -3.0$ (`16'shD000`)
     - `2'b01` $\longrightarrow -1.0$ (`16'shF000`)
     - `2'b11` $\longrightarrow +1.0$ (`16'sh1000`)
     - `2'b10` $\longrightarrow +3.0$ (`16'sh3000`)

---

## 2. Interface Input / Output Specifications

| Signal Name | Direction | Data Width | Format / Range | Description |
| :--- | :---: | :---: | :---: | :--- |
| `i_clk` | Input | `1` bit | Clock | Primary system clock (e.g., 50 MHz or 100 MHz). |
| `i_rstn` | Input | `1` bit | Active-Low Reset | Asynchronous/Synchronous system reset. Resets symbol counter to 0 and deasserts `o_valid`. |
| `i_cfg_tx_en` | Input | `1` bit | Control Flag | **TX Enable**: When `1`, advances the 2-bit cyclic counter every clock cycle. When `0`, freezes counter state and deasserts `o_valid`. |
| `o_valid` | Output | `1` bit | Status Flag | **Data Valid**: Asserted high when `o_tx_data` contains a valid active PAM-4 symbol. |
| `o_tx_sym_raw` | Output | `2` bits | Unsigned Binary | Raw 2-bit counter state (`2'b00`, `2'b01`, `2'b10`, `2'b11`). Useful for simulation and reference training alignment. |
| `o_tx_gray_bits`| Output | `2` bits | Gray Code | Transmitted 2-bit Gray-coded symbol (`2'b00`, `2'b01`, `2'b11`, `2'b10`). |
| `o_tx_data` | Output | `16` bits | Signed Q4.12 | Transmitted PAM-4 fixed-point voltage level ($\{-3.0, -1.0, +1.0, +3.0\}$). Connects to `channel_top`. |

---

## 3. Implementation Guidelines for Member 1

1. **Synchronous Behavior:** Ensure that `o_valid` and the counter output update synchronously on the rising clock edge.
2. **Stand-Alone Testbench:** Verify that when reset is released and `i_cfg_tx_en` is high, `o_tx_data` produces the repeating sequence:
   `16'shD000` (-3) $\rightarrow$ `16'shF000` (-1) $\rightarrow$ `16'sh3000` (+3) $\rightarrow$ `16'sh1000` (+1).
