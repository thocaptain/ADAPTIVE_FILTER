// PRBS Generator (TX Core): outputs bit and NRZ symbol s[n]
/* verilator lint_off UNUSEDSIGNAL */
module prbs_gen
  import eq_pkg::*;
(
  input  logic                 i_clk,
  input  logic                 i_rst_n,
  input  logic                 i_en,
  output logic                 o_bit,   // TX bit (reference for BERT)
  output logic signed [DW-1:0] o_sym    // s[n]
);

  // TODO: LFSR PRBS-N, map bit -> +A / -A

  assign o_bit = 1'b0;
  assign o_sym = '0;

endmodule
