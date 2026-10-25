`timescale 1ns/1ps

module tb_top
#(
    parameter integer             NUMBER_SYMBOL  = 1,
    parameter logic signed [15:0] H1_Q12         = 16'sd2048,
    parameter logic        [31:0] NOISE_SEED     = 32'h00000a5b,
    parameter logic        [7:0]  DEFAULT_SNR_DB = 8'd20
)
(
      input  logic               i_clk
    , input  logic               i_rst_n

    , input  logic signed [NUMBER_SYMBOL-1:0][3:0] i_sym // Q4.0 {-3, -1, +1, +3}
    , input  logic               i_noise_en         // {0, 1}
    , input  logic        [7:0]   i_cfg_snr_db       // U8 [0, 255] dB
    , input  logic               i_cfg_noise_load   // {0, 1}
    , output logic signed [NUMBER_SYMBOL-1:0][7:0] o_r   // Q4.4 [-8, 7.9375]
);

    channel_top #(
        .NUMBER_SYMBOL  (NUMBER_SYMBOL ),
        .H1_Q12         (H1_Q12        ),
        .NOISE_SEED     (NOISE_SEED    ),
        .DEFAULT_SNR_DB (DEFAULT_SNR_DB)
    ) dut (
        .i_clk            (i_clk           ),
        .i_rst_n          (i_rst_n         ),
        .i_sym            (i_sym           ),
        .i_noise_en       (i_noise_en      ),
        .i_cfg_snr_db     (i_cfg_snr_db    ),
        .i_cfg_noise_load (i_cfg_noise_load),
        .o_r              (o_r             )
    );

endmodule
