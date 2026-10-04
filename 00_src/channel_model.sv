// Channel Model: FIR loss + AWGN
//   i_severe = 1 -> switch to severe ISI / noise profile
/* verilator lint_off UNUSEDSIGNAL */
module channel_model
  import eq_pkg::*;
(
  input  logic                 i_clk,
  input  logic                 i_rst_n,
  input  logic                 i_en,
  input  logic                 i_severe,
  input  logic signed [DW-1:0] i_sym,   // s[n]
  output logic signed [DW-1:0] o_r      // r[n]
);

  logic signed [DW-1:0] noise;

  // TODO: CH_TAPS FIR with 2 coefficient sets (mild / severe)

  awgn_gen u_awgn (
    .i_clk   (i_clk                    ),
    .i_rst_n (i_rst_n                  ),
    .i_en    (i_en                     ),
    .i_level (i_severe ? 2'd2 : 2'd1   ),
    .o_noise (noise                    )
  );

  assign o_r = '0;

endmodule
