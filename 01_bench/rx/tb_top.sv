`timescale 1ns/1ps

module tb_top
#(
    parameter integer             TRAIN_LEN        = 3000,
    parameter integer             STARTUP_CYCLES   = 0,
    parameter integer             REF_DELAY_CYCLES = 0,
    parameter logic signed [39:0] MU_F20           = 40'sd524
)
(
      input  logic               i_clk
    , input  logic               i_rst_n

    , input  logic signed [7:0]   i_r                   // Q4.4 [-8, 7.9375]
    , input  logic signed [3:0]   i_tx_ref              // Q4.0 {-3, -1, +1, +3}
    , input  logic signed [15:0]  i_cfg_ffe0            // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0]  i_cfg_ffe1            // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0]  i_cfg_ffe2            // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0]  i_cfg_dfe0            // Q4.12 [-8, 8-2^-12]
    , input  logic                i_cfg_load            // {0, 1}
    , input  logic                i_adapt_en            // {0, 1}
    , input  logic                i_ffe_bypass          // {0, 1}
    , input  logic                i_dfe_bypass          // {0, 1}
    , output logic signed [3:0]   o_sym                 // Q4.0 {-3, -1, +1, +3}
    , output logic [1:0]          o_bits                // U2 {00, 01, 11, 10}
    , output logic signed [15:0]  o_y                   // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0]  o_ffe0                // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0]  o_ffe1                // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0]  o_ffe2                // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0]  o_dfe0                // Q4.12 [-8, 8-2^-12]
);

    rx_top #(
        .TRAIN_LEN        (TRAIN_LEN       ),
        .STARTUP_CYCLES   (STARTUP_CYCLES  ),
        .REF_DELAY_CYCLES (REF_DELAY_CYCLES),
        .MU_F20           (MU_F20          )
    ) dut (
        .i_clk        (i_clk       ),
        .i_rst_n      (i_rst_n     ),
        .i_r          (i_r         ),
        .i_tx_ref     (i_tx_ref    ),
        .i_cfg_ffe0   (i_cfg_ffe0  ),
        .i_cfg_ffe1   (i_cfg_ffe1  ),
        .i_cfg_ffe2   (i_cfg_ffe2  ),
        .i_cfg_dfe0   (i_cfg_dfe0  ),
        .i_cfg_load   (i_cfg_load  ),
        .i_adapt_en   (i_adapt_en  ),
        .i_ffe_bypass (i_ffe_bypass),
        .i_dfe_bypass (i_dfe_bypass),
        .o_sym        (o_sym       ),
        .o_bits       (o_bits      ),
        .o_y          (o_y         ),
        .o_ffe0       (o_ffe0      ),
        .o_ffe1       (o_ffe1      ),
        .o_ffe2       (o_ffe2      ),
        .o_dfe0       (o_dfe0      )
    );

endmodule
