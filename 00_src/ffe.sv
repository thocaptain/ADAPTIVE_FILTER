// FFE (Feed-Forward Equalizer) - cancels precursor ISI, LMS adaptive
/* verilator lint_off UNUSEDSIGNAL */
module ffe
  import eq_pkg::*;
(
  input  logic                 i_clk,
  input  logic                 i_rst_n,
  input  logic                 i_en,
  input  logic                 i_adapt,  // enable LMS update
  input  logic signed [DW-1:0] i_r,      // r[n]
  input  logic signed [DW-1:0] i_err,    // error from DFE slicer
  output logic signed [DW-1:0] o_y       // y[n]
);

  // TODO: FFE_TAPS delay line, MAC, LMS coefficient update

  assign o_y = '0;

endmodule
