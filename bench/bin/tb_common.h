// tb_common.h - shared Verilator harness
#ifndef TB_COMMON_H
#define TB_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <verilated.h>
#include <verilated_fst_c.h>
#include "Vtop.h"

static vluint64_t sim_unit = 0;
static vluint64_t sim_time = 0;

static void print_passed(const char *msg) {
  printf("::\033[1;32mPASSED\033[0m:: %s\n", msg);
}

static void print_failed(const char *msg) {
  printf("::\033[1;31mFAILED\033[0m:: %s\n", msg);
}

static Vtop *dut_init(int argc, char **argv, VerilatedFstC **vtrace) {
  Verilated::commandArgs(argc, argv);
  Vtop *dut = new Vtop;

  Verilated::traceEverOn(true);
  *vtrace = new VerilatedFstC;
  dut->trace(*vtrace, 2);
  (*vtrace)->open("wave.fst");

  dut->i_clk   = 1;
  dut->i_rst_n = 0;
  dut->eval();
  (*vtrace)->dump(0);
  return dut;
}

static void finish(Vtop *dut, VerilatedFstC *vtrace, bool pass) {
  printf("\nCycles: %llu\n", static_cast<unsigned long long>(sim_unit));
  printf("\n-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.- END OF FILE -.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-\n\n");
  vtrace->close();
  delete vtrace;
  delete dut;
  exit(pass ? EXIT_SUCCESS : EXIT_FAILURE);
}

// One clock cycle; reset is held low for the first 2 cycles
static void dut_clock(Vtop *dut, VerilatedFstC *vtrace) {
  dut->i_rst_n = (sim_unit < 2) ? 0 : 1;

  sim_time = sim_unit * 10 + 1;
  vtrace->dump(sim_time);

  sim_time += 4;
  dut->i_clk = 0;
  dut->eval();
  vtrace->dump(sim_time);

  sim_time += 5;
  dut->i_clk = 1;
  dut->eval();
  vtrace->dump(sim_time);

  sim_unit++;
}

#endif
