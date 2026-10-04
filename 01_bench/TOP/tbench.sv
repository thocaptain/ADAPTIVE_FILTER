`include "timescale.svh"
`include "tlib.svh"

`define RESETPERIOD 55
`define FINISH      100000

module tbench
  import eq_pkg::*;
();

// Wave dumping
  initial begin : proc_dump_wave
    $dumpfile("wave.vcd");
    $dumpvars(0, dut);
  end

  logic             i_clk;
  logic             i_rst_n;
  logic             i_en     = 1'b1;
  logic             i_severe = 1'b0;
  logic             i_adapt  = 1'b1;
  logic             i_clr    = 1'b0;
/* verilator lint_off UNUSEDSIGNAL */
  logic             o_lock;
  logic [CNT_W-1:0] o_bit_cnt;
  logic [CNT_W-1:0] o_err_cnt;
/* verilator lint_on UNUSEDSIGNAL */

  initial tsk_clock_gen(i_clk);
  initial tsk_reset(i_rst_n, `RESETPERIOD);
  initial tsk_timeout(`FINISH);

  eq_top dut (
    .*
  );

endmodule
