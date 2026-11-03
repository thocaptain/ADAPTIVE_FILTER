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
    input  logic                          i_error_valid,      // Error belongs to the current RX output
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
        input logic signed [63:0] val
    );
        if (val > ((64'sd1 <<< (DATA_WIDTH-1)) - 1))
            sat16 = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else if (val < -(64'sd1 <<< (DATA_WIDTH-1)))
            sat16 = {1'b1, {(DATA_WIDTH-1){1'b0}}};
        else
            sat16 = val[DATA_WIDTH-1:0];
    endfunction

    function automatic logic signed [63:0] round_shift(
        input logic signed [63:0] value, input integer shift
    );
        if (shift <= 0)
            round_shift = value <<< (-shift);
        else if (value < 0)
            round_shift = -(((-value) + (64'sd1 <<< (shift-1))) >>> shift);
        else
            round_shift = (value + (64'sd1 <<< (shift-1))) >>> shift;
    endfunction

    function automatic logic signed [39:0] sat40(input logic signed [63:0] value);
        if (value > 64'sd549755813887) sat40 = 40'sh7FFFFFFFFF;
        else if (value < -64'sd549755813888) sat40 = 40'sh8000000000;
        else sat40 = value[39:0];
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
    logic signed [39:0] b0_acc; // Q20 internal adaptation precision

    // =========================================================================
    // 3. Embedded LMS Weight Adaptation for DFE
    //    b_0[n+1] = b_0[n] - mu * e[n] * d_hat[n-1]
    //    (Note: Minus sign for negative feedback cancellation)
    // =========================================================================
    logic signed [2*DATA_WIDTH-1:0] prod_err_d;
    logic signed [3*DATA_WIDTH-1:0] prod_mu;
    logic signed [39:0] delta;
    always_comb begin
        prod_err_d = $signed(i_error) * $signed(d_prev_r);
        prod_mu = $signed(i_learning_rate) * $signed(prod_err_d);
        delta = sat40(round_shift(64'($signed(prod_mu)), 16+2*DATA_FRAC-20));
        b0_reg = sat16(round_shift(64'($signed(b0_acc)), 20-DATA_FRAC));
    end
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            b0_acc <= sat40(64'($signed(i_cfg_dfe_b0)) <<< (20-DATA_FRAC));
        end else if (i_cfg_lms_en && i_error_valid) begin
            // Feedback update: subtract delta
            b0_acc <= sat40(64'($signed(b0_acc)) - 64'($signed(delta)));
        end else if (!i_cfg_lms_en) begin
            b0_acc <= sat40(64'($signed(i_cfg_dfe_b0)) <<< (20-DATA_FRAC));
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
            y_dfe = sat16(64'($signed(mul_dfe_32)) >>> DATA_FRAC);
        end else begin
            y_dfe = 16'sh0000; // Disable feedback
        end
    end

    // =========================================================================
    // Feedback must have exactly one decision register in the loop.
    // A second output flop would use d_hat[n-2] at the RX summer.
    // Keep the multiply combinational after d_prev_r.
    // =========================================================================
    assign o_valid    = valid_r;
    assign o_dfe_data = y_dfe;
    assign o_curr_b0  = b0_reg;

endmodule: rx_dfe
