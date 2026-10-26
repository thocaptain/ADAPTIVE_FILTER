// =============================================================================
// Module Name:   rx_dfe
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 4 (Ngoc Cuong)
// Description:   1-Tap Adaptive Decision Feedback Equalizer (DFE) Module.
//                Contains:
//                1. 1-Tap Feedback Register storing previous sliced symbol d_hat[n-1]
//                2. Feedback Reconstruction:
//                   y_dfe[n] = b0 * d_hat[n-1]
//                3. Embedded LMS Adaptive Tap Unit (ATU):
//                   b_0[n+1] = b_0[n] - mu * e[n] * d_hat[n-1]
//                4. Programmable Initial Weight & Bypass Control
//                5. Hook for Direct-Form vs. Speculative Look-Ahead DFE
// =============================================================================

`timescale 1ns / 1ps

module rx_dfe #(
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC  = 12
)(
    // Clock & Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // Input Sliced Decision from Slicer (d_hat[n])
    input  logic                          i_valid,
    input  logic signed [DATA_WIDTH-1:0]  i_sliced_data,      // Sliced PAM-4 symbol (-3, -1, +1, +3 in Q4.12)

    // Configuration & Initial Weight
    input  logic                          i_cfg_dfe_en,       // 1: Enable DFE feedback, 0: Disable/Bypass
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_dfe_b0,       // Initial feedback tap weight b0 (Q4.12)

    // LMS Adaptation Signals (from rx_top)
    input  logic                          i_cfg_lms_en,       // 1: Adapt feedback weight via LMS, 0: Hold
    input  logic signed [DATA_WIDTH-1:0]  i_error,            // Error e[n] from rx_top (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_learning_rate,    // Step-size mu (Q0.16)

    // Outputs
    output logic                          o_valid,            // Aligned valid signal
    output logic signed [DATA_WIDTH-1:0]  o_dfe_data,         // y_dfe[n] feedback term to be subtracted
    output logic signed [DATA_WIDTH-1:0]  o_curr_b0           // Current adapted b0 (for debug)
);

    // =========================================================================
    // Helper Saturation Function
    // =========================================================================
    function automatic logic signed [DATA_WIDTH-1:0] sat16(
        input logic signed [31:0] val
    );
        if (val > 32'sd32767)
            sat16 = 16'sh7FFF;
        else if (val < -32'sd32768)
            sat16 = 16'sh8000;
        else
            sat16 = val[15:0];
    endfunction

    // =========================================================================
    // 1. Previous Sliced Decision Register: d_hat[n-1]
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] d_prev_r;
    logic                         valid_r;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            d_prev_r <= '0;
            valid_r  <= 1'b0;
        end else if (i_valid) begin
            d_prev_r <= i_sliced_data;
            valid_r  <= 1'b1;
        end else begin
            valid_r  <= 1'b0;
        end
    end

    // =========================================================================
    // 2. Feedback Tap Weight Register (b0)
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] b0_reg;

    // =========================================================================
    // 3. Embedded LMS Weight Adaptation for DFE
    //    b_0[n+1] = b_0[n] - mu * e[n] * d_hat[n-1]
    //    (Note: Minus sign for negative feedback cancellation)
    // =========================================================================
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            b0_reg <= i_cfg_dfe_b0;
        end else if (i_cfg_lms_en && valid_r) begin
            logic signed [31:0] prod_err_d;
            logic signed [47:0] prod_mu;
            logic signed [31:0] delta;

            prod_err_d = $signed(i_error) * $signed(d_prev_r);
            prod_mu    = $signed(i_learning_rate) * $signed(prod_err_d >>> DATA_FRAC);
            delta      = prod_mu >>> 16; // mu is Q0.16

            // Feedback update: subtract delta
            b0_reg     <= sat16($signed({{16{b0_reg[15]}}, b0_reg}) - delta);
        end else if (!i_cfg_lms_en) begin
            b0_reg <= i_cfg_dfe_b0;
        end
    end

    // =========================================================================
    // 4. Feedback Reconstruction: y_dfe = b0 * d_hat[n-1]
    // =========================================================================
    logic signed [31:0] mul_dfe_32;
    logic signed [DATA_WIDTH-1:0] y_dfe;

    always_comb begin
        mul_dfe_32 = $signed(d_prev_r) * $signed(b0_reg);

        if (i_cfg_dfe_en) begin
            y_dfe = sat16(mul_dfe_32 >>> DATA_FRAC);
        end else begin
            y_dfe = 16'sh0000; // Disable feedback
        end
    end

    // =========================================================================
    // Outputs
    // =========================================================================
    assign o_valid    = valid_r;
    assign o_dfe_data = y_dfe;
    assign o_curr_b0  = b0_reg;

endmodule: rx_dfe
