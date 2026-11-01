/* Bare-metal MicroBlaze test for TX, ISI, and fixed-weight FFE/DFE phases.
 * Add this file as the only main() in a Vitis standalone application.
 * BSP stdout must use axi_uartlite_0.
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
#define DUT_BASE_FALLBACK 1
#endif
#endif

#ifndef SEQUENCE_WAIT_LOOPS
#define SEQUENCE_WAIT_LOOPS 2000000U
#endif

enum {
    REG_CONTROL = 0x00,
    REG_COMMAND = 0x04,
    REG_NOISE_GAIN = 0x08,
    REG_FFE_W0 = 0x0c,
    REG_FFE_W1 = 0x10,
    REG_FFE_W2 = 0x14,
    REG_DFE_B0 = 0x18,
    REG_ISI_COEFF = 0x1c,
    REG_ERROR_BITS = 0x20,
    REG_LEARNING_RATE = 0x24,
    REG_TOTAL_WORDS = 0x28,
    REG_DUT_RESET_N = 0x2c,

    CTRL_MON = 1U << 2,
    CTRL_FFE = 1U << 3,
    CTRL_DFE = 1U << 4,
    CTRL_TX = 1U << 5,
    CTRL_ISI = 1U << 6
};

struct phase_result {
    uint32_t words;
    uint32_t error_bits;
};

static UINTPTR dut_address(unsigned offset)
{
    return (UINTPTR)DUT_BASEADDR + offset;
}

static void write_reg(unsigned offset, uint32_t value)
{
    Xil_Out32(dut_address(offset), value);
    DATA_SYNC;
}

static uint32_t read_reg(unsigned offset)
{
    uint32_t value = Xil_In32(dut_address(offset));
    DATA_SYNC;
    return value;
}

static void wait_for_samples(void)
{
    for (volatile uint32_t i = 0; i < SEQUENCE_WAIT_LOOPS; ++i) {
    }
}

static void configure_fixed_weights(void)
{
    write_reg(REG_NOISE_GAIN, 0);
    write_reg(REG_FFE_W0, 4096U); /* Identity tap, Q4.12 = 1.0. */
    write_reg(REG_FFE_W1, 0);
    write_reg(REG_FFE_W2, 0);
    write_reg(REG_DFE_B0, 2048U); /* Q4.12 = 0.5. */
    write_reg(REG_ISI_COEFF, 2048U); /* Q4.12 = 0.5. */
    write_reg(REG_LEARNING_RATE, 33U);
}

static struct phase_result run_phase(uint32_t control)
{
    struct phase_result result;

    write_reg(REG_CONTROL, 0);
    write_reg(REG_DUT_RESET_N, 0);
    wait_for_samples();
    configure_fixed_weights();

    write_reg(REG_DUT_RESET_N, 1);
    write_reg(REG_CONTROL, control);
    wait_for_samples();

    write_reg(REG_COMMAND, 1);
    (void)read_reg(REG_COMMAND);
    result.error_bits = read_reg(REG_ERROR_BITS);
    result.words = read_reg(REG_TOTAL_WORDS);
    return result;
}

static void print_spaces(unsigned count)
{
    while (count-- != 0U) {
        xil_printf(" ");
    }
}

static void print_text_field(const char *text, unsigned width)
{
    unsigned length = 0;
    while (text[length] != '\0') {
        xil_printf("%c", text[length]);
        ++length;
    }
    if (length < width) {
        print_spaces(width - length);
    }
}

static void print_uint_field(uint32_t value, unsigned width)
{
    char digits[10];
    unsigned count = 0;

    do {
        digits[count++] = (char)('0' + (value % 10U));
        value /= 10U;
    } while (value != 0U && count < sizeof(digits));

    if (count < width) {
        print_spaces(width - count);
    }
    while (count != 0U) {
        xil_printf("%c", digits[--count]);
    }
}

static void print_table_border(void)
{
    xil_printf("+------------------+----------------+------------+------------+--------+\r\n");
}

static void print_table_header(void)
{
    print_table_border();
    xil_printf("| ");
    print_text_field("Phase", 16);
    xil_printf(" | ");
    print_text_field("Expected", 14);
    xil_printf(" | ");
    print_text_field("Words", 10);
    xil_printf(" | ");
    print_text_field("Error bits", 10);
    xil_printf(" | ");
    print_text_field("Status", 6);
    xil_printf(" |\r\n");
    print_table_border();
}

static void print_row(const char *name, const char *expected,
                      const struct phase_result *result, const char *status)
{
    xil_printf("| ");
    print_text_field(name, 16);
    xil_printf(" | ");
    print_text_field(expected, 14);
    xil_printf(" | ");
    print_uint_field(result->words, 10);
    xil_printf(" | ");
    print_uint_field(result->error_bits, 10);
    xil_printf(" | ");
    print_text_field(status, 6);
    xil_printf(" |\r\n");
}

int main(void)
{
    const uint32_t control_tx_monitor = CTRL_TX | CTRL_MON;
    const uint32_t control_isi_monitor = CTRL_TX | CTRL_ISI | CTRL_MON;
    const uint32_t control_isi_ffe =
        CTRL_TX | CTRL_ISI | CTRL_FFE | CTRL_MON;
    const uint32_t control_isi_dfe =
        CTRL_TX | CTRL_ISI | CTRL_DFE | CTRL_MON;
    const uint32_t control_isi_ffe_dfe =
        CTRL_TX | CTRL_ISI | CTRL_FFE | CTRL_DFE | CTRL_MON;
    struct phase_result baseline;
    struct phase_result isi;
    struct phase_result isi_ffe;
    struct phase_result isi_dfe;
    struct phase_result isi_ffe_dfe;

    xil_printf("\r\nAdaptive EQ sequence test\r\n");
    xil_printf("DUT base address: 0x%08x\r\n", (unsigned)DUT_BASEADDR);
#ifdef DUT_BASE_FALLBACK
    xil_printf("WARNING: using fallback DUT base; verify the address against the Vivado address map.\r\n");
#endif
    xil_printf("LMS=off, AWGN=off, ISI=0.5, FFE=(1,0,0), DFE=0.5 (Q4.12)\r\n");
    xil_printf("Wait loops per phase: %u\r\n\r\n", (unsigned)SEQUENCE_WAIT_LOOPS);

    baseline = run_phase(control_tx_monitor);
    isi = run_phase(control_isi_monitor);
    isi_ffe = run_phase(control_isi_ffe);
    isi_dfe = run_phase(control_isi_dfe);
    isi_ffe_dfe = run_phase(control_isi_ffe_dfe);

    print_table_header();
    print_row("TX baseline", "0 errors", &baseline, "INFO");
    print_row("TX + ISI", ">0 errors", &isi, "INFO");
    print_row("TX+ISI+FFE", "report only", &isi_ffe, "INFO");
    print_row("TX+ISI+DFE", "report only", &isi_dfe, "INFO");
    print_row("TX+ISI+FFE+DFE", "report only", &isi_ffe_dfe, "INFO");
    print_table_border();
    xil_printf("\r\nISI check: INFO (expected errors %s)\r\n",
               (isi.words != 0U && isi.error_bits != 0U) ?
               "observed" : "not observed");

    write_reg(REG_CONTROL, 0);
    write_reg(REG_DUT_RESET_N, 0);
    for (;;) {
    }
}
