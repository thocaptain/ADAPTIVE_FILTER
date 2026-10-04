// PRBS -> Channel -> FFE -> DFE -> BERT
module eq_top
  import eq_pkg::*;
(
  input  logic             i_clk,
  input  logic             i_rst_n,
  input  logic             i_en,
  input  logic             i_severe,  // switch: add severe ISI/noise
  input  logic             i_adapt,   // switch: enable LMS adaptation
  input  logic             i_clr,     // clear BERT counters
  output logic             o_lock,
  output logic [CNT_W-1:0] o_bit_cnt,
  output logic [CNT_W-1:0] o_err_cnt
);

  logic                 tx_bit;
  logic signed [DW-1:0] s_n;
  logic signed [DW-1:0] r_n;
  logic signed [DW-1:0] y_n;
  logic                 d_n;
  logic signed [DW-1:0] err;

  prbs_gen u_prbs (
    .i_clk   (i_clk  ),
    .i_rst_n (i_rst_n),
    .i_en    (i_en   ),
    .o_bit   (tx_bit ),
    .o_sym   (s_n    )
  );

  channel_model u_channel (
    .i_clk    (i_clk   ),
    .i_rst_n  (i_rst_n ),
    .i_en     (i_en    ),
    .i_severe (i_severe),
    .i_sym    (s_n     ),
    .o_r      (r_n     )
  );

  ffe u_ffe (
    .i_clk   (i_clk  ),
    .i_rst_n (i_rst_n),
    .i_en    (i_en   ),
    .i_adapt (i_adapt),
    .i_r     (r_n    ),
    .i_err   (err    ),
    .o_y     (y_n    )
  );

  dfe u_dfe (
    .i_clk   (i_clk  ),
    .i_rst_n (i_rst_n),
    .i_en    (i_en   ),
    .i_adapt (i_adapt),
    .i_y     (y_n    ),
    .o_d     (d_n    ),
    .o_err   (err    )
  );

  bert_checker u_bert (
    .i_clk     (i_clk    ),
    .i_rst_n   (i_rst_n  ),
    .i_en      (i_en     ),
    .i_clr     (i_clr    ),
    .i_ref_bit (tx_bit   ),
    .i_rx_bit  (d_n      ),
    .o_lock    (o_lock   ),
    .o_bit_cnt (o_bit_cnt),
    .o_err_cnt (o_err_cnt)
  );

endmodule
