`timescale 1ns/1ps

module Top
#(
    parameter logic          [6:0]  PRBS_SEED           = 7'h7f,           // U7 [1, 127]
    parameter logic   signed [15:0] CHANNEL_H1_Q12      = 16'sd2048,       // Q4.12 [-8, 8-2^-12]
    parameter logic   signed [15:0] NOISE_SIGMA_Q12     = 16'sd1024,       // Q4.12 [-8, 8-2^-12]
    parameter logic          [31:0] NOISE_SEED          = 32'h00000a5b,    // U32 [0, 2^32-1]
    parameter bit                   NOISE_ENABLE        = 1'b1,            // {0, 1}
    parameter integer               TRAIN_LEN           = 3000,            // Integer [0, 2^31-1]
    parameter logic   signed [39:0] MU_F20              = 40'sd524,        // Q20.20 [-2^19, 2^19-2^-20]
    parameter integer               RX_STARTUP_CYCLES   = 2,               // Integer [0, 2^31-1]
    parameter integer               TX_REF_DELAY_CYCLES = 1                // Integer [0, 2^31-1]
)
(
      input  logic               i_clk           // {0, 1}
    , input  logic               i_rst_n         // {0, 1}

    , input  logic signed [15:0] i_cfg_ffe0      // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0] i_cfg_ffe1      // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0] i_cfg_ffe2      // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0] i_cfg_dfe0      // Q4.12 [-8, 8-2^-12]
    , input  logic               i_cfg_load      // {0, 1}
    , input  logic               i_adapt_en      // {0, 1}
    , input  logic               i_ffe_bypass    // {0, 1}
    , input  logic               i_dfe_bypass    // {0, 1}

    , output logic signed [3:0]  o_tx_sym        // Q4.0 {-3, -1, +1, +3}
    , output logic        [1:0]  o_tx_bits       // U2 {00, 01, 11, 10}
    , output logic signed [7:0]  o_channel_r     // Q4.4 [-8, 7.9375]

    , output logic signed [3:0]  o_rx_sym        // Q4.0 {-3, -1, +1, +3}
    , output logic        [1:0]  o_rx_bits       // U2 {00, 01, 11, 10}
    , output logic signed [15:0] o_rx_y          // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_ffe0          // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_ffe1          // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_ffe2          // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_dfe0          // Q4.12 [-8, 8-2^-12]
);

    logic signed [3:0]  TX_sym;      // Q4.0 {-3, -1, +1, +3}
    logic        [1:0]  TX_bits_ref; // U2 {00, 01, 11, 10}

    logic signed [7:0]  CH_r;        // Q4.4 [-8, 7.9375]

    logic signed [3:0]  RX_sym;      // Q4.0 {-3, -1, +1, +3}
    logic        [1:0]  RX_bits;     // U2 {00, 01, 11, 10}
    logic signed [15:0] RX_y;        // Q4.12 [-8, 8-2^-12]

    logic signed [15:0] RX_ffe0;     // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] RX_ffe1;     // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] RX_ffe2;     // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] RX_dfe0;     // Q4.12 [-8, 8-2^-12]

    tx_top #(
        .PRBS_SEED (PRBS_SEED)
    ) tx_top (
        .i_clk      (i_clk      ),
        .i_rst_n    (i_rst_n    ),
        .o_sym      (TX_sym     ),
        .o_bits_ref (TX_bits_ref)
    );

    assign o_tx_sym    = TX_sym;
    assign o_tx_bits   = TX_bits_ref;

    channel_top #(
        .H1_Q12       (CHANNEL_H1_Q12 ),
        .SIGMA_Q12    (NOISE_SIGMA_Q12),
        .NOISE_SEED   (NOISE_SEED     ),
        .NOISE_ENABLE (NOISE_ENABLE   )
    ) channel_top (
        .i_clk   (i_clk  ),
        .i_rst_n (i_rst_n),
        .i_sym   (TX_sym ),
        .o_r     (CH_r   )
    );

    assign o_channel_r = CH_r;

    rx_top #(
        .TRAIN_LEN        (TRAIN_LEN          ),
        .STARTUP_CYCLES   (RX_STARTUP_CYCLES  ),
        .REF_DELAY_CYCLES (TX_REF_DELAY_CYCLES),
        .MU_F20           (MU_F20             )
    ) rx_top (
        .i_clk        (i_clk       ),
        .i_rst_n      (i_rst_n     ),
        .i_r          (CH_r        ),
        .i_tx_ref     (TX_sym      ),

        .i_cfg_ffe0   (i_cfg_ffe0  ),
        .i_cfg_ffe1   (i_cfg_ffe1  ),
        .i_cfg_ffe2   (i_cfg_ffe2  ),
        .i_cfg_dfe0   (i_cfg_dfe0  ),
        .i_cfg_load   (i_cfg_load  ),
        .i_adapt_en   (i_adapt_en  ),
        .i_ffe_bypass (i_ffe_bypass),
        .i_dfe_bypass (i_dfe_bypass),

        .o_sym        (RX_sym      ),
        .o_bits       (RX_bits     ),
        .o_y          (RX_y        ),
        .o_ffe0       (RX_ffe0     ),
        .o_ffe1       (RX_ffe1     ),
        .o_ffe2       (RX_ffe2     ),
        .o_dfe0       (RX_dfe0     )
    );

    assign o_rx_sym    = RX_sym;
    assign o_rx_bits   = RX_bits;
    assign o_rx_y      = RX_y;

    assign o_ffe0      = RX_ffe0;
    assign o_ffe1      = RX_ffe1;
    assign o_ffe2      = RX_ffe2;
    assign o_dfe0      = RX_dfe0;

endmodule
