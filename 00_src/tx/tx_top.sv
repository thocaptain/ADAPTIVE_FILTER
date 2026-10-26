// =============================================================================
// Module Name:   tx_top
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 1 (Dac Huy)
// Description:   Transmitter Top-Level Module.
//                Contains:
//                1. 2-Bit Cyclic Gray-Code Pattern Generator (0 -> 1 -> 2 -> 3)
//                2. PAM-4 Gray Mapper (Converts 2-bit symbol to signed 16-bit Q4.12)
// =============================================================================

`timescale 1ns / 1ps

module tx_top #(
    parameter int SYMB_BITS = 2,
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC  = 12
)(
    // Clock and Asynchronous/Synchronous Active-Low Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // Control & Configuration
    input  logic                          i_cfg_tx_en,       // 1: Enable pattern generation, 0: Pause/Hold

    // TX Outputs
    output logic                          o_valid,           // Valid indicator for TX symbol
    output logic [SYMB_BITS-1:0]          o_tx_sym_raw,      // 2-bit raw cyclic counter value (0, 1, 2, 3)
    output logic [SYMB_BITS-1:0]          o_tx_gray_bits,    // 2-bit Gray-coded bits
    output logic signed [DATA_WIDTH-1:0]  o_tx_data          // Signed 16-bit Q4.12 PAM-4 level
);

    // =========================================================================
    // Local Parameters for Fixed-Point PAM-4 Levels (Q4.12)
    // =========================================================================
    //  Symbol Level | Gray Code | Fixed-Point Hex (Q4.12) | Real Value
    //  -------------+-----------+-------------------------+-----------
    //       -3      |    00     |       16'shD000         |   -3.0
    //       -1      |    01     |       16'shF000         |   -1.0
    //       +1      |    11     |       16'sh1000         |   +1.0
    //       +3      |    10     |       16'sh3000         |   +3.0
    // =========================================================================
    localparam logic signed [DATA_WIDTH-1:0] PAM4_LEVEL_NEG3 = 16'shD000;
    localparam logic signed [DATA_WIDTH-1:0] PAM4_LEVEL_NEG1 = 16'shF000;
    localparam logic signed [DATA_WIDTH-1:0] PAM4_LEVEL_POS1 = 16'sh1000;
    localparam logic signed [DATA_WIDTH-1:0] PAM4_LEVEL_POS3 = 16'sh3000;

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [SYMB_BITS-1:0]         sym_cnt_r;
    logic [SYMB_BITS-1:0]         gray_code;
    logic signed [DATA_WIDTH-1:0] pam4_level;
    logic                         tx_valid_r;

    // =========================================================================
    // 1. 2-Bit Cyclic Counter (0 -> 1 -> 2 -> 3 -> 0...)
    // =========================================================================
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            sym_cnt_r  <= '0;
            tx_valid_r <= 1'b0;
        end else if (i_cfg_tx_en) begin
            sym_cnt_r  <= sym_cnt_r + 1'b1;
            tx_valid_r <= 1'b1;
        end else begin
            tx_valid_r <= 1'b0;
        end
    end

    // =========================================================================
    // 2. Gray Code Conversion
    // Binary (sym_cnt_r) -> Gray code: gray = bin ^ (bin >> 1)
    // bin = 00 -> gray = 00
    // bin = 01 -> gray = 01
    // bin = 10 -> gray = 11
    // bin = 11 -> gray = 10
    // =========================================================================
    always_comb begin
        gray_code = sym_cnt_r ^ {1'b0, sym_cnt_r[SYMB_BITS-1:1]};
    end

    // =========================================================================
    // 3. PAM-4 Mapper (Gray Code -> Q4.12 Fixed-Point Level)
    // =========================================================================
    always_comb begin
        case (gray_code)
            2'b00:   pam4_level = PAM4_LEVEL_NEG3;
            2'b01:   pam4_level = PAM4_LEVEL_NEG1;
            2'b11:   pam4_level = PAM4_LEVEL_POS1;
            2'b10:   pam4_level = PAM4_LEVEL_POS3;
            default: pam4_level = 16'sh0000;
        endcase
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign o_valid        = tx_valid_r;
    assign o_tx_sym_raw   = sym_cnt_r;
    assign o_tx_gray_bits = gray_code;
    assign o_tx_data      = pam4_level;

endmodule: tx_top
