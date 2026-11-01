# CPU-to-DUT AXI Diagnostic

Program: [dut_diagnostic.c](dut_diagnostic.c). It uses MicroBlaze standalone
and the new wrapper register map documented in the
[AXI README](../../00_src/axi/README.md).

## Running in Vitis 2021.1

1. Generate a bitstream containing `dut_0`, export a new XSA, and create or
   update the Vitis platform.
2. Create an **Empty Application (C)** with processor `microblaze_0` and OS
   `standalone`.
3. Add `dut_diagnostic.c` to `src`. Keep only **one `main()`**: do not add
   `dut_console.c` or `uart_bootloader.c` to the same application.
4. Set BSP `stdout` to `axi_uartlite_0`; generate a linker script with code,
   data, heap, and stack in local BRAM. The current configuration does not use
   cache.
5. The program automatically gets the base address from
   `XPAR_DUT_0_S_AXI_BASEADDR` or `XPAR_DUT_0_BASEADDR`; if neither is defined,
   it uses `0x44A00000`. Verify the address in the Address Editor. You can
   override it with the compiler define `DUT_BASEADDR=0x...`.
6. Open a UART terminal **before running** the program. Use the baud rate
   configured for AXI UARTLite (115200 if your IP is configured for 115200),
   8N1, and no flow control. Build and run the ELF over JTAG. If using the
   existing UART loader, you can load it with the application linker address
   set to `0x4000`.

The program runs once, prints each phase, and ends with output similar to:

```text
=== MicroBlaze -> Adaptive EQ AXI diagnostic ===
DUT base = 0x44a00000
...
[PASS] CONTROL
[PASS] NOISE_GAIN
...
[PASS] AXI byte lanes
[INFO] Snapshot 1: error_bits=... total_words=...
[INFO] Snapshot 2: error_bits=... total_words=...
[PASS] Snapshot and monitor
RESULT: PASS | checks=... failures=0
```

## What Is Checked

- The CPU writes and reads CONTROL, each enable bit, and the reserved-bit mask.
- Seven 16-bit configuration registers are tested with zero, all-one,
  alternating, and sign-bit patterns. The raw encoding must read back
  correctly, and the upper 16 bits must be zero.
- `Xil_Out8`/`Xil_Out16` verify byte lanes and AXI WSTRB on little-endian
  MicroBlaze. A normal CPU store cannot generate WSTRB=0; that case is covered
  by the RTL test.
- A snapshot taken while the monitor is disabled must be zero. With TX and the
  monitor enabled, the counters must advance, repeated reads of a snapshot
  must be stable, and a new snapshot must increase.
- Removed command bits must not refresh the snapshot. Disabling the monitor
  clears only the live counters; the previous snapshot remains until the next
  snapshot.
- The monitor receives data in bypass mode and with FFE identity enabled.

The test does not assume that registers are at their reset values, so it can be
run repeatedly. It saves and restores the seven scalar configuration
registers, but **clears the current measurement**: CONTROL=0 and snapshot=0
when it finishes. A PASS confirms the tested register accesses and monitor
behavior; the program reports DSP error counts but does not require BER to be
zero. AWGN in the Channel is still a zero-valued placeholder.

For project `F:/master/FPGA/project_1`, inspected during this session, the
actual BSP configures UARTLite for **9600 baud** and defines
`XPAR_DUT_0_BASEADDR=0x44A10000`. The diagnostic automatically uses this macro,
so it does not use the `0x44A00000` fallback. The old IP had both `reg0` and
`Reg` address blocks; the packager was updated so that a new package contains
only `Reg`. The diagnostic was built and linked using the project's actual BSP
and linker script (JTAG ELF in BRAM starting at address 0). It has not yet been
run on the board. The current hardware fails timing at 100 MHz; review the
routed timing report before relying on measurements from the board.

## If the Test Does Not Pass

- **No banner:** Check that the ELF is running, the CPU clock and reset, UART,
  and BSP stdout configuration.
- **Stops at `First MMIO access`:** Check the DUT base/map, AXI connections,
  DUT clock/reset, and that the FPGA was programmed with the correct BIT file.
  The CPU can wait indefinitely on AXI; the program's delay loop is **not a
  timeout for a stalled MMIO access**.
- **Fails `Revised 16-bit register map`:** Check that the BIT/IP/XSA use the
  updated wrapper. The program stops before writing offsets whose meaning
  differs from the old wrapper.
- **Readback failure with expected/read hex values:** Check the register ABI
  and AXI byte lanes.
- If word reads/writes pass but the high byte remains `0x11AA` instead of
  `0xBBAA`, see [AXI_BYTE_FIX.md](AXI_BYTE_FIX.md): the old bridge rejects
  register address + 1. Update the IP/BIT; the new C code adds byte/halfword
  loads and separates the cascading failure cases.
- **Monitor count failure:** Check TX enable and the TX/Channel/RX valid path
  and monitor.

Do not deliberately access unmapped addresses or write read-only counters:
those accesses return SLVERR and require a separate CPU exception handler.
Negative protocol tests are in `10_sim/axi/tb_top_wrapper.sv`.
