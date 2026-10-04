// AWGN generator: approximate Gaussian noise (e.g. sum of uniform LFSRs - CLT)
/* verilator lint_off UNUSEDSIGNAL */
module awgn_gen
  import eq_pkg::*;
(
  input  logic                 i_clk,
  input  logic                 i_rst_n,
  input  logic                 i_en,
  input  logic [1:0]           i_level,  // noise level select
  output logic signed [DW-1:0] o_noise
);

  // TODO: noise generation + scaling by i_level

  assign o_noise = '0;

endmodule
