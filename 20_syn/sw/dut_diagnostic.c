/* MicroBlaze standalone AXI diagnostic for the revised top_wrapper register ABI.
 * Add this file as the ONLY main() in a Vitis Empty Application (C).
 * BSP stdout must be axi_uartlite_0. Use the actual UARTLite baud rate.
 * Stops measurement, tests RW registers, restores scalar configuration, leaves
 * CONTROL=0, DUT held in software reset and snapshot counters cleared.
 * Requires IP 1.3 or later, with DUT_RESET_N at offset 0x2c.
 */
#include <stdint.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"

#ifndef DUT_BASEADDR
#if defined(XPAR_DUT_0_S_AXI_BASEADDR)
#define DUT_BASEADDR XPAR_DUT_0_S_AXI_BASEADDR
#elif defined(XPAR_DUT_0_BASEADDR)
#define DUT_BASEADDR XPAR_DUT_0_BASEADDR
#else
#define DUT_BASEADDR 0x44A00000U
#define DIAG_FALLBACK_BASE 1
#endif
#endif

#ifndef DIAG_WAIT_LOOPS
#define DIAG_WAIT_LOOPS 10000U
#endif

enum {
    REG_CONTROL = 0x00, REG_COMMAND = 0x04, REG_NOISE_GAIN = 0x08,
    REG_FFE_W0 = 0x0c, REG_FFE_W1 = 0x10, REG_FFE_W2 = 0x14,
    REG_DFE_B0 = 0x18, REG_ISI_COEFF = 0x1c, REG_ERROR_BITS = 0x20,
    REG_LEARNING_RATE = 0x24, REG_TOTAL_WORDS = 0x28, REG_DUT_RESET_N = 0x2c,
    CTRL_MON = 1U << 2, CTRL_FFE = 1U << 3, CTRL_TX = 1U << 5
};

struct config_register {
    const char *name;
    unsigned offset;
};
static const struct config_register config[] = {
    {"NOISE_GAIN", REG_NOISE_GAIN}, {"FFE_W0", REG_FFE_W0},
    {"FFE_W1", REG_FFE_W1}, {"FFE_W2", REG_FFE_W2},
    {"DFE_B0", REG_DFE_B0}, {"ISI_COEFF", REG_ISI_COEFF},
    {"LEARNING_RATE", REG_LEARNING_RATE}
};
#define CONFIG_COUNT (sizeof(config) / sizeof(config[0]))
static unsigned checks, failures;

static UINTPTR addr(unsigned offset)
{
    return (UINTPTR)DUT_BASEADDR + offset;
}

static uint32_t rd(unsigned offset)
{
    uint32_t value = Xil_In32(addr(offset));
    DATA_SYNC;
    return value;
}

static void wr(unsigned offset, uint32_t value)
{
    Xil_Out32(addr(offset), value);
    DATA_SYNC;
}

static void delay(void)
{
    /* A bounded software wait, not a calibrated measurement interval. */
    for (volatile unsigned i = 0; i < DIAG_WAIT_LOOPS; ++i) {}
}

static void expect(unsigned offset, uint32_t expected, const char *label)
{
    uint32_t actual = rd(offset);
    ++checks;
    if (actual != expected) {
        ++failures;
        xil_printf("[FAIL] %s offset=0x%02x expected=0x%08x read=0x%08x\r\n",
                   label, offset, (unsigned)expected, (unsigned)actual);
    }
}

static void check(int success, const char *label)
{
    ++checks;
    if (!success) {
        ++failures;
        xil_printf("[FAIL] %s\r\n", label);
    }
}

static void phase_result(const char *label, unsigned failures_before)
{
    xil_printf("[%s] %s\r\n", failures == failures_before ? "PASS" : "FAIL", label);
}

static void snapshot(uint32_t *errors, uint32_t *words)
{
    wr(REG_COMMAND, 1);
    /* Ordered readback also lets the one-cycle pulse reach the monitor before
     * reading its snapshot registers. COMMAND always reads zero. */
    (void)rd(REG_COMMAND);
    *errors = rd(REG_ERROR_BITS);
    *words = rd(REG_TOTAL_WORDS);
}

static void test_control(void)
{
    unsigned before = failures;
    xil_printf("[TEST] CONTROL enable bits and reserved-bit mask\r\n");
    for (unsigned bit = 0; bit < 32; ++bit) {
        uint32_t value = (uint32_t)1U << bit;
        wr(REG_CONTROL, value);
        expect(REG_CONTROL, value & 0x7fU, "CONTROL walking bit");
        wr(REG_CONTROL, 0);
    }
    wr(REG_CONTROL, 0xffffffffU);
    expect(REG_CONTROL, 0x7fU, "CONTROL all bits");
    wr(REG_CONTROL, 0);
    phase_result("CONTROL", before);
}

static void test_config(void)
{
    static const uint32_t patterns[] = {
        0x00000000U, 0xffffffffU, 0x0000aaaaU, 0x00005555U,
        0x00008000U, 0x00007fffU, 0x00001234U, 0xdeadbeefU
    };
    xil_printf("[TEST] 32-bit stores, 16-bit fields, upper bits and signed encodings\r\n");
    for (unsigned i = 0; i < CONFIG_COUNT; ++i) {
        unsigned before = failures;
        for (unsigned p = 0; p < sizeof(patterns) / sizeof(patterns[0]); ++p) {
            wr(config[i].offset, patterns[p]);
            expect(config[i].offset, patterns[p] & 0xffffU, config[i].name);
        }
        phase_result(config[i].name, before);
    }
}

static void test_byte_lanes(void)
{
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    unsigned before = failures;
    xil_printf("[TEST] Byte/halfword CPU stores -> AXI write strobes\r\n");
    wr(REG_NOISE_GAIN, 0x1122U);
    Xil_Out8(addr(REG_NOISE_GAIN), 0xaaU);
    DATA_SYNC;
    expect(REG_NOISE_GAIN, 0x11aaU, "low byte");
    Xil_Out8(addr(REG_NOISE_GAIN + 1), 0xbbU);
    DATA_SYNC;
    expect(REG_NOISE_GAIN, 0xbbaaU, "high byte");
    /* Seed each reserved-lane check independently so a failed high-byte store
     * does not create two additional failures with the same underlying cause. */
    wr(REG_NOISE_GAIN, 0xbbaaU);
    Xil_Out8(addr(REG_NOISE_GAIN + 2), 0xccU);
    DATA_SYNC;
    expect(REG_NOISE_GAIN, 0xbbaaU, "reserved byte 2 ignored");
    wr(REG_NOISE_GAIN, 0xbbaaU);
    Xil_Out8(addr(REG_NOISE_GAIN + 3), 0xddU);
    DATA_SYNC;
    expect(REG_NOISE_GAIN, 0xbbaaU, "reserved byte 3 ignored");
    Xil_Out16(addr(REG_NOISE_GAIN), 0x8001U);
    DATA_SYNC;
    expect(REG_NOISE_GAIN, 0x8001U, "low halfword");
    check(Xil_In8(addr(REG_NOISE_GAIN)) == 0x01U, "CPU low-byte load");
    check(Xil_In8(addr(REG_NOISE_GAIN + 1)) == 0x80U, "CPU high-byte load");
    check(Xil_In16(addr(REG_NOISE_GAIN)) == 0x8001U, "CPU halfword load");
    phase_result("AXI byte lanes", before);
#else
    xil_printf("[SKIP] Byte lane test requires the little-endian MicroBlaze configuration\r\n");
#endif
}

static void test_snapshots(void)
{
    unsigned before = failures;
    uint32_t errors1, words1, errors2, words2;
    xil_printf("[TEST] Real DUT snapshot, counter growth, stability and clear\r\n");
    wr(REG_CONTROL, 0);
    wr(REG_NOISE_GAIN, 0);
    wr(REG_FFE_W0, 4096);
    wr(REG_FFE_W1, 0);
    wr(REG_FFE_W2, 0);
    wr(REG_DFE_B0, 0);
    wr(REG_ISI_COEFF, 2048);
    wr(REG_LEARNING_RATE, 33);
    wr(REG_DUT_RESET_N, 1);
    snapshot(&errors1, &words1);
    expect(REG_COMMAND, 0, "COMMAND readback");
    check(errors1 == 0 && words1 == 0, "Disabled monitor must snapshot zero");

    /* Clean bypass path: TX + monitor. No ISI, AWGN, FFE, DFE or LMS. */
    wr(REG_CONTROL, CTRL_TX | CTRL_MON);
    delay();
    snapshot(&errors1, &words1);
    xil_printf("[INFO] Snapshot 1: error_bits=%u total_words=%u\r\n",
               (unsigned)errors1, (unsigned)words1);
    check(words1 != 0, "TX/monitor must produce a nonzero symbol count");
    check((uint64_t)errors1 <= (uint64_t)words1 * 2U, "Error bits cannot exceed two per symbol");

    delay();
    for (unsigned i = 0; i < 4; ++i) {
        expect(REG_ERROR_BITS, errors1, "Snapshot errors stay stable");
        expect(REG_TOTAL_WORDS, words1, "Snapshot words stay stable");
    }
    wr(REG_COMMAND, 0x1eU); // Reserved/removed command bits must not refresh.
    expect(REG_COMMAND, 0, "COMMAND reserved bits read zero");
    expect(REG_ERROR_BITS, errors1, "Reserved command preserves errors");
    expect(REG_TOTAL_WORDS, words1, "Reserved command preserves words");

    snapshot(&errors2, &words2);
    xil_printf("[INFO] Snapshot 2: error_bits=%u total_words=%u\r\n",
               (unsigned)errors2, (unsigned)words2);
    check(words2 > words1, "A new snapshot must show the running counter advancing");
    check((uint64_t)errors2 <= (uint64_t)words2 * 2U, "Second snapshot counter units");

    wr(REG_CONTROL, CTRL_TX); // Monitor disable clears LIVE counts, not snapshot.
    delay();
    expect(REG_ERROR_BITS, errors2, "Monitor disable preserves old snapshot errors");
    expect(REG_TOTAL_WORDS, words2, "Monitor disable preserves old snapshot words");
    snapshot(&errors2, &words2);
    check(errors2 == 0 && words2 == 0, "New snapshot after monitor clear must be zero");
    wr(REG_CONTROL, 0);

    /* Also check the enabled identity FFE path can supply monitor data. */
    wr(REG_CONTROL, CTRL_TX | CTRL_MON | CTRL_FFE);
    delay();
    snapshot(&errors2, &words2);
    check(words2 != 0, "Identity FFE path must supply symbols to the monitor");
    xil_printf("[INFO] Identity FFE: error_bits=%u total_words=%u\r\n",
               (unsigned)errors2, (unsigned)words2);
    wr(REG_CONTROL, 0);
    phase_result("Snapshot and monitor", before);
}

static void test_dut_reset(void)
{
    unsigned before = failures;
    uint32_t errors, words, saved_noise;
    xil_printf("[TEST] Configurable DUT reset while AXI bridge stays operational\r\n");
    wr(REG_DUT_RESET_N, 1);
    wr(REG_CONTROL, CTRL_TX | CTRL_MON);
    delay();
    snapshot(&errors, &words);
    check(words != 0, "Monitor running before DUT-only reset");
    saved_noise = rd(REG_NOISE_GAIN);
    wr(REG_DUT_RESET_N, 0);
    expect(REG_DUT_RESET_N, 0, "DUT reset asserted");
    expect(REG_CONTROL, CTRL_TX | CTRL_MON, "DUT reset preserves AXI CONTROL");
    expect(REG_NOISE_GAIN, saved_noise, "DUT reset preserves scalar config");
    expect(REG_ERROR_BITS, 0, "DUT reset clears snapshot errors");
    expect(REG_TOTAL_WORDS, 0, "DUT reset clears snapshot words");
    wr(REG_NOISE_GAIN, 0xa5U);
    expect(REG_NOISE_GAIN, 0xa5U, "AXI write/read while DUT is held reset");
    wr(REG_NOISE_GAIN, saved_noise);
    Xil_Out8(addr(REG_DUT_RESET_N + 1), 1);
    DATA_SYNC;
    expect(REG_DUT_RESET_N, 0, "Reserved byte cannot release DUT reset");
    wr(REG_DUT_RESET_N, 0xfffffffeU);
    expect(REG_DUT_RESET_N, 0, "Reserved bits cannot release DUT reset");
    wr(REG_DUT_RESET_N, 0xffffffffU);
    expect(REG_DUT_RESET_N, 1, "DUT reset released, upper bits read zero");
    delay();
    snapshot(&errors, &words);
    check(words != 0, "Monitor restarts after DUT reset release");
    wr(REG_CONTROL, 0);
    wr(REG_DUT_RESET_N, 0);
    phase_result("Independent DUT reset", before);
}

int main(void)
{
    uint32_t saved[CONFIG_COUNT];
    uint32_t saved_noise;
    xil_printf("\r\n=== MicroBlaze -> Adaptive EQ AXI diagnostic ===\r\n");
    xil_printf("DUT base = 0x%08x\r\n", (unsigned)(UINTPTR)DUT_BASEADDR);
#ifdef XPAR_AXI_UARTLITE_0_BAUDRATE
    xil_printf("UARTLite baud = %u\r\n", (unsigned)XPAR_AXI_UARTLITE_0_BAUDRATE);
#endif
#ifdef DIAG_FALLBACK_BASE
    xil_printf("[INFO] Using fallback base; it must match Vivado Address Editor\r\n");
#endif
    xil_printf("[INFO] Requires DUT IP 1.3; leaves CONTROL=0 and DUT_RESET_N=0\r\n");
    xil_printf("[TEST] First MMIO access; if output stops here, check address/clock/reset/BIT\r\n");
    wr(REG_CONTROL, 0);
    expect(REG_CONTROL, 0, "Initial CONTROL write/read");

    /* Safe check before accessing repurposed offsets 0x1c/0x24. The obsolete
     * wrapper only implements an 8-bit SNR field and fails this check. */
    saved_noise = rd(REG_NOISE_GAIN);
    wr(REG_NOISE_GAIN, 0xa55aU);
    expect(REG_NOISE_GAIN, 0xa55aU, "Revised 16-bit register map");
    wr(REG_NOISE_GAIN, saved_noise);
    if (failures != 0) {
        xil_printf("RESULT: FAIL - verify AXI address and revised DUT BIT/XSA before continuing\r\n");
        return 1;
    }
    wr(REG_DUT_RESET_N, 1);
    expect(REG_DUT_RESET_N, 1, "IP 1.3 reset register");
    wr(REG_DUT_RESET_N, 0);
    expect(REG_DUT_RESET_N, 0, "Hold DUT reset for configuration");
    if (failures != 0) {
        xil_printf("RESULT: FAIL - program BIT with configurable DUT reset (IP 1.3)\r\n");
        return 1;
    }
    for (unsigned i = 0; i < CONFIG_COUNT; ++i) saved[i] = rd(config[i].offset);
    test_control();
    test_config();
    test_byte_lanes();
    test_snapshots();
    test_dut_reset();

    wr(REG_CONTROL, 0);
    wr(REG_DUT_RESET_N, 0);
    for (unsigned i = 0; i < CONFIG_COUNT; ++i) wr(config[i].offset, saved[i]);
    {
        uint32_t errors, words;
        snapshot(&errors, &words);
        check(errors == 0 && words == 0, "Final monitor snapshot clear");
    }
    xil_printf("\r\nRESULT: %s | checks=%u failures=%u\r\n",
               failures == 0 ? "PASS" : "FAIL", checks, failures);
    xil_printf("Scalar config restored; CONTROL=0, DUT_RESET_N=0, monitor/snapshot cleared\r\n");
    xil_printf("Counts test AXI/config/monitor behavior; inspect DSP error_bits separately\r\n");
    return failures == 0 ? 0 : 1;
}
