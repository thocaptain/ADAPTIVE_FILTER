# AXI4-Lite wrapper

[Top_wrapper.sv](../Top_wrapper.sv) contains [adaptive_eq_axi_regs.sv](adaptive_eq_axi_regs.sv) and the existing [Top.sv](../Top.sv):

```text
CPU AXI4-Lite master -> AXI register bridge -> Top (TX -> Channel -> RX + BER)
                              ^                         |
                              +---- status/snapshot ----+
```

The AXI signal names and parameter convention follow the supplied `myip_hamming_v1_0_S00_AXI.sv` example. This implementation independently captures write address and data, supports byte strobes, and holds read/write responses under backpressure. One read and one write may be outstanding independently. No CPU, AXI interconnect, clock-domain crossing, board wrapper or Vivado IP packaging is included.

## Integration

- Use `Top_wrapper` as the peripheral RTL top; connect the CPU/interconnect AXI4-Lite master to `S_AXI_*`.
- AXI data is 32 bits (`C_S_AXI_DATA_WIDTH=32` only); local byte address width defaults to 8 and must be at least 7. The peripheral base address is assigned by the enclosing system.
- `S_AXI_ACLK` clocks both the bridge and Top. Supply an active-low reset with release synchronized to that clock on `S_AXI_ARESETN`.
- Stream connections use `[NUMBER_SYMBOL-1:0][width-1:0]` packed arrays; diagnostic registers read lane `[0]`.
- All Top parameters, including latency and counter width, are forwarded. `NUMBER_SYMBOL=1` is the only implemented throughput, matching Top's current guard.
- Compile `Top_wrapper.sv`, `axi/adaptive_eq_axi_regs.sv`, `Top.sv`, and the team-provided `tx_top`, `channel_top`, `rx_top` sources. The child RTL is not implemented here.
- CPU AXI accesses configure/monitor the continuously running datapath; they do not carry the symbol stream. `AWPROT` and `ARPROT` are accepted but unused; this peripheral performs no privilege filtering.

## Register map

Offsets are bytes relative to the peripheral base. Access words at aligned 4-byte addresses. Unmapped/unaligned accesses and writes to read-only registers return `SLVERR` (`2'b10`); invalid reads return zero. Successful accesses return `OKAY` (`2'b00`). Writes honor `WSTRB`; zero strobes have no register or command effects.

| Offset | Name | Access | Meaning / reset |
|---|---|---|---|
| `0x00` | CONTROL | RW | Bits 0 noise enable, 1 adaptation enable, 2 BER enable, 3 FFE bypass shadow, 4 DFE bypass shadow. Reset 0; reserved bits read 0. |
| `0x04` | COMMAND | W1P / R0 | Bit 0 RX config load, 1 Channel SNR load, 2 BER clear, 3 snapshot, 4 core-only reset. Each written 1 triggers once; only byte strobe 0 applies. |
| `0x08` | SNR_DB | RW | Bits [7:0], unsigned integer dB. Reset `DEFAULT_SNR_DB` (20). Applies on Channel SNR load. |
| `0x0C` | CFG_FFE0 | RW | Bits [15:0], signed Q4.12 shadow. Reset 0. |
| `0x10` | CFG_FFE1 | RW | Bits [15:0], signed Q4.12 shadow. Reset 3072 (0.75). |
| `0x14` | CFG_FFE2 | RW | Bits [15:0], signed Q4.12 shadow. Reset 0. |
| `0x18` | CFG_DFE0 | RW | Bits [15:0], signed Q4.12 shadow. Reset 0. |
| `0x1C` | STATUS | RO | Bit 0 live BER ready; bit 1 snapshot valid. Other bits 0. |
| `0x20` | ERROR_LO | RO | Snapshot error count [31:0]. Reset 0. |
| `0x24` | ERROR_HI | RO | Snapshot error count [63:32]. Reset 0. |
| `0x28` | TOTAL_LO | RO | Snapshot compared-bit count [31:0]. Reset 0. |
| `0x2C` | TOTAL_HI | RO | Snapshot compared-bit count [63:32]. Reset 0. |
| `0x30` | SNAP_LATENCY | RO | TX-reference alignment delay captured with the counters. Reset 0. |
| `0x34` | FFE0 | RO | Live active signed Q4.12 coefficient, sign-extended to 32 bits. |
| `0x38` | FFE1 | RO | Live active signed Q4.12 coefficient, sign-extended to 32 bits. |
| `0x3C` | FFE2 | RO | Live active signed Q4.12 coefficient, sign-extended to 32 bits. |
| `0x40` | DFE0 | RO | Live active signed Q4.12 coefficient, sign-extended to 32 bits. |
| `0x44` | TX_SYM | RO | Live signed Q4.0 symbol, sign-extended to 32 bits. |
| `0x48` | TX_BITS | RO | Live 2-bit Gray reference, zero-extended. |
| `0x4C` | CHANNEL_R | RO | Live signed Q4.4 Channel sample, sign-extended to 32 bits. |
| `0x50` | RX_SYM | RO | Live signed Q4.0 recovered symbol, sign-extended to 32 bits. |
| `0x54` | RX_BITS | RO | Live 2-bit recovered Gray word, zero-extended. |
| `0x58` | RX_Y | RO | Live signed Q4.12 pre-slicer sample, sign-extended to 32 bits. |
| `0x5C` | LIVE_LATENCY | RO | Current TX-reference alignment delay in clocks. |

Shadow coefficient readbacks are zero-extended raw 16-bit encodings. Convert to signed `int16_t` and divide by 4096 for real values. Coefficients and bypass shadows become active together on COMMAND bit 0. Noise/adaptation/BER enable bits are live, as specified by Top; changing noise/adaptation clears its BER epoch. Channel SNR becomes active only on COMMAND bit 1.

## CPU sequence

1. Write CONTROL with BER disabled. Write the desired SNR and all four coefficient shadows; set bypass bits in CONTROL.
2. Write COMMAND=`0x03` to load RX config and Channel SNR. RX/Channel load pulses are high for one core clock. They apply on the next rising edge after the AXI register write commits; wait for the write response before polling status.
3. Poll STATUS bit 0 until ready, then write COMMAND=`0x04` to clear BER. Enable CONTROL bit 2 while preserving the chosen mode/noise/adaptation bits.
4. Run the measurement. Clear CONTROL bit 2 to stop at a software-controlled interval, then write COMMAND=`0x08` to capture both counters and their latency on the same edge.
5. After the snapshot write response, check STATUS bit 1 and read ERROR_LO/HI and TOTAL_LO/HI. Reconstruct each value as `((uint64_t)HI << 32) | LO`; compute BER on the CPU only if total is nonzero.

Snapshot registers remain unchanged until the next snapshot or AXI reset. New measurements/config changes do not discard an existing snapshot. A core-only reset invalidates it (STATUS bit 1 clears); its old data must then be ignored. Counter widths below 64 are zero-extended. Live diagnostic reads are independent samples and are not a trace or a synchronized set of observations.

COMMAND bit 4 resets Top for one clock without resetting the AXI interface or shadow registers. This starts fresh RX training and clears Top's BER counters. Active RX/Channel configuration returns to its child-module reset defaults; reload shadows with COMMAND=`0x03` afterwards. Send core reset separately from load/snapshot commands; if reset and snapshot are combined, snapshot validity is cleared. Existing Top BER clear/config/settling behavior is documented in [TOP_BER.md](../../99_doc/TOP_BER.md).

There is no hardware measurement-length controller or interrupt in this initial wrapper. Software determines when to stop and reads the actual bit total. Use ordered/device MMIO accesses and wait for each AXI completion; reads concurrent with a register update can observe the previous value.

## Verification

The installed Verilator compiled and simulated the register bridge with BER counter widths 64 and 16 (address widths 8 and 7). Directed checks and 500 randomized writes per configuration covered AW-before-W, W-before-AW, simultaneous channels, byte strobes, response backpressure, command pulses, signed readback, snapshot stability, invalid accesses, concurrent read/write activity and reset with incomplete/blocked transactions.

A separate simulation instantiated the actual `Top_wrapper` and `Top` with temporary behavioral child-module fixtures. It checked coefficient shadow/load wiring, bypass-dependent latency, BER counting, snapshots and core-only reset. These fixtures exercise integration and are not TX/Channel/RX DSP implementations. Test files were kept outside the repository; simulation with the real child RTL and Vivado synthesis remain pending.

## References

- Local design-style reference supplied by the user: `F:\master\project_4\project_4.srcs\sources_1\new\myip_hamming_v1_0_S00_AXI.sv` (read only; original unchanged).
- [Arm AMBA AXI and ACE Protocol Specification](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf), AXI4-Lite and independent-channel handshake rules.
