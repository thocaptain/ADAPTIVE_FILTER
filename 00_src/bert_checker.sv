// BERT Checker: align TX reference with d[n], count bits / errors
/* verilator lint_off UNUSEDSIGNAL */
module bert_checker
  import eq_pkg::*;
(
  input  logic             i_clk,
  input  logic             i_rst_n,
  input  logic             i_en,
  input  logic             i_clr,      // clear counters
  input  logic             i_ref_bit,  // TX bit from PRBS generator
  input  logic             i_rx_bit,   // d[n]
  output logic             o_lock,
  output logic [CNT_W-1:0] o_bit_cnt,
  output logic [CNT_W-1:0] o_err_cnt
);

  // TODO: latency alignment, lock detection, bit/error counters

  assign o_lock    = 1'b0;
  assign o_bit_cnt = '0;
  assign o_err_cnt = '0;

endmodule
