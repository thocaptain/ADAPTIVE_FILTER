`timescale 1ns/1ps

module tb_top
#(
    parameter logic signed [15:0] H1_Q12       = 16'sd2048,
    parameter logic signed [15:0] SIGMA_Q12    = 16'sd1024,
    parameter logic [31:0]        NOISE_SEED   = 32'h00000a5b,
    parameter bit                 NOISE_ENABLE = 1'b1
)
(
      input  logic               i_clk
    , input  logic               i_rst_n

    , input  logic signed [3:0]   i_sym                 // Q4.0 {-3, -1, +1, +3}
    , output logic signed [7:0]   o_r                   // Q4.4 [-8, 7.9375]
);

    channel_top #(
        .H1_Q12       (H1_Q12      ),
        .SIGMA_Q12    (SIGMA_Q12   ),
        .NOISE_SEED   (NOISE_SEED  ),
        .NOISE_ENABLE (NOISE_ENABLE)
    ) dut (
        .i_clk   (i_clk  ),
        .i_rst_n (i_rst_n),
        .i_sym   (i_sym  ),
        .o_r     (o_r    )
    );

endmodule
