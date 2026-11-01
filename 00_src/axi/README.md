# AXI4-Lite adapter for current top.sv

[top_wrapper.sv](../top_wrapper.sv) connects the register bridge to the actual
[top.sv](../top.sv) runtime interface. The datapath stays fixed at 16-bit Q4.12.
The wrapper parameters are only `C_S_AXI_DATA_WIDTH=32` and
`C_S_AXI_ADDR_WIDTH=8` (minimum 6; the MicroBlaze Tcl uses 12 for a 4 KiB aperture).

The former PRBS/parallel-symbol, training, latency, BER64, core-reset and
TX/RX/coefficient debug interfaces have been removed. Top/TX/Channel/RX RTL
is unchanged. **This is a changed register ABI: rebuild older host firmware.**

## Register map

Offsets are bytes from the enclosing system's peripheral base
(`0x44A00000` in the MicroBlaze Tcl). All accesses are aligned 32-bit words.

| Offset | Register | Access | Meaning / reset |
|---|---|---|---|
| `0x00` | CONTROL | RW | Bits 0 AWGN enable, 1 LMS enable, 2 monitor enable, 3 FFE enable, 4 DFE enable, 5 TX enable, 6 ISI enable. Reset 0, reserved bits read 0. FFE/DFE bits are **enables**, not bypass bits. |
| `0x04` | COMMAND | W1P / R0 | Bit 0 triggers `i_cfg_snapshot_trig` for one core clock. All other bits ignored; only byte strobe 0 applies. |
| `0x08` | NOISE_GAIN | RW | Low 16 bits feed top's `i_cfg_snr_db`. Current Channel interprets this as a signed Q4.12 noise multiplier, **not dB**. Reset 0. |
| `0x0C` | CFG_FFE_W0 | RW | Low 16 bits, signed Q4.12. Reset 4096 (1.0). |
| `0x10` | CFG_FFE_W1 | RW | Low 16 bits, signed Q4.12. Reset 0. |
| `0x14` | CFG_FFE_W2 | RW | Low 16 bits, signed Q4.12. Reset 0. |
| `0x18` | CFG_DFE_B0 | RW | Low 16 bits, signed Q4.12. Reset 0. |
| `0x1C` | ISI_COEFF | RW | Low 16 bits, signed Q4.12. Reset 2048 (0.5). This replaces the former STATUS register. |
| `0x20` | ERROR_BITS | RO | Top's 32-bit snapshot `o_stat_err_bits`. Reset 0. |
| `0x24` | LEARNING_RATE | RW | Low 16 bits, raw Q0.16 input to LMS; RX treats it as signed. Reset 33 (about 0.0005035). This replaces the former ERROR_HI register. |
| `0x28` | TOTAL_WORDS | RO | Top's 32-bit snapshot `o_stat_total_words`, in **symbols/words**, not bits. Reset 0. |

There is no ready/valid status, latency, counter high word, explicit coefficient
load, SNR load, BER clear pulse or core-only reset command. Addresses `0x2C`
and above are unmapped. CONTROL monitor=0 clears/holds the live monitor counts
and synchronization state, as implemented by `rx_monitor.sv`.

Readbacks of 16-bit fields are zero-extended raw encodings; cast to `int16_t`
before interpreting a signed value. Writes honor WSTRB, including independent
low/high byte writes to 16-bit fields. Upper bytes have no effect; zero strobes
are a no-op. Unmapped/unaligned accesses and writes to counters return SLVERR;
invalid reads return zero. AWPROT/ARPROT are accepted but unused.

## Configuration and snapshots

Configuration is live; there are no shadow/load commands. In current RX RTL,
LMS=0 reloads the configured FFE/DFE weights each cycle. Disable LMS before
changing initial weights and enable it afterwards. During live updates, the
datapath can observe intermediate values between separate AXI writes.

1. Write CONTROL=0 while configuring. Write noise gain, ISI coefficient, FFE/DFE
   weights and learning rate. A simple identity setup is FFE W0=4096, W1=W2=0,
   DFE B0=0, with ISI/AWGN/LMS disabled.
2. Start TX and enable the desired filters. For example CONTROL=`0x28` enables
   TX and FFE. Enabling monitor as well gives CONTROL=`0x2C`.
3. To restart measurement, write monitor=0, then monitor=1 while preserving
   other enable bits. The actual monitor locks after valid received symbols;
   there is no exported readiness flag.
4. **Snapshot while monitor is still enabled:** write COMMAND=1, wait for the
   AXI write completion, then read ERROR_BITS and TOTAL_WORDS. Both are latched
   together by the monitor. Do not issue another snapshot between the two reads.
5. The snapshot remains stable until another snapshot or global AXI reset.
   Disabling monitor clears live counts but preserves the old snapshot. A
   snapshot while monitor has been disabled captures zeros.

The command pulse reaches the monitor on the clock following register commit.
Ordered MicroBlaze MMIO accesses after the write response see the new snapshot;
an independent read concurrent with the update may see the prior snapshot.
Read/write responses remain stable under backpressure; a stalled write response
does not repeat the snapshot pulse.

For the current PAM-4 two-bit symbols, software can calculate
`BER = error_bits / (2.0 * total_words)` when total_words is nonzero and before
either 32-bit counter wraps. Prefer enabling noise/LMS/ISI before starting a new
measurement; the current monitor does not automatically clear on config changes.

Current `channel_top.sv` still drives its AWGN sample to zero as a placeholder.
The AXI gain/enable wiring is real, but noise cannot affect samples until the
Channel implementation supplies a noise source.

## Verification

- Verilator elaborates the full real wrapper/TX/Channel/RX without interface
  errors. Existing width warnings inside the DSP RTL remain.
- Vivado 2021.1 synthesizes top_wrapper out of context for Arty A7-35T.
- XSim integration test uses real child RTL, independent AW/W arrival order,
  100 randomized strobe writes, response backpressure, configuration wiring,
  removed/invalid accesses, snapshot pulse timing/stability, monitor clear and
  reset with a partially accepted AXI write, at address widths 8 and 12.

From a Vivado command environment:

```bat
vivado -mode batch -source 10_sim/axi/run.tcl
```

The test prints a PASS line for each address width. Outputs go to a local
temporary directory; pass `-tclargs C:/fpga_build/axi_test` to choose one.
Board-level validation and full system implementation are separate checks.
