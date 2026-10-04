// DFE (Decision Feedback Equalizer) - cancels postcursor ISI + slicer, LMS adaptive
/* verilator lint_off UNUSEDSIGNAL */
module dfe
  import eq_pkg::*;
(
  input  logic                 i_clk,
  input  logic                 i_rst_n,
  input  logic                 i_en,
  input  logic                 i_adapt,  // enable LMS update
  input  logic signed [DW-1:0] i_y,      // y[n]
  output logic                 o_d,      // d[n] decision bit
  output logic signed [DW-1:0] o_err     // slicer error (to FFE/DFE LMS)
);

  // TODO: DFE_TAPS feedback, slicer, error, LMS coefficient update

  assign o_d   = 1'b0;
  assign o_err = '0;

endmodule
