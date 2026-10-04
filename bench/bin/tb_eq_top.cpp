#include "tb_common.h"

static const vluint64_t MAX_CYCLES = 100000;

int main(int argc, char **argv) {
  VerilatedFstC *vtrace;
  Vtop *dut = dut_init(argc, argv, &vtrace);

  dut->i_en     = 1;
  dut->i_severe = 0;
  dut->i_adapt  = 1;
  dut->i_clr    = 0;

  printf("\nRunning tb_eq_top (%llu cycles)\n", static_cast<unsigned long long>(MAX_CYCLES));

  while (sim_unit < MAX_CYCLES)
    dut_clock(dut, vtrace);

  unsigned long long bits = dut->o_bit_cnt;
  unsigned long long errs = dut->o_err_cnt;
  printf("  lock = %d, bits = %llu, errors = %llu\n", dut->o_lock, bits, errs);

  // TODO: define pass criteria (e.g. lock && BER below target)
  bool pass = dut->o_lock && (errs == 0);
  if (pass) print_passed("tb_eq_top");
  else      print_failed("tb_eq_top");

  finish(dut, vtrace, pass);
  return 0;
}
