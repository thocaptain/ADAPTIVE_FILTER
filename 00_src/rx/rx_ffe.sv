// =============================================================================
// Module Name:   rx_ffe
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 3 (Van Phuc)
// Description:   3-Tap Adaptive Feed-Forward Equalizer (FFE) Module.
//                Contains:
//                1. 3-Tap Input Delay Line: x[n], x[n-1], x[n-2]
//                2. Pipelined FIR Filtering Datapath:
//                   y_ffe[n] = w0*x[n] + w1*x[n-1] + w2*x[n-2]
//                3. Embedded LMS Adaptive Tap Units (ATUs):
//                   w_k[n+1] = w_k[n] + mu * e[n] * x[n-k]
//                4. Programmable Initial Weights & Bypass Control
// =============================================================================

`timescale 1ns / 1ps

module rx_ffe #(
    parameter int TAG_FFE    = 3,
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC  = 12
)(
    // Clock & Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // Input Sample from Channel
    input  logic                          i_valid,
    input  logic signed [DATA_WIDTH-1:0]  i_r_in,             // Q4.12 received sample

    // Configuration & Initial Weights
    input  logic                          i_cfg_ffe_en,       // 1: Enable FFE filtering, 0: Bypass
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w0,       // Initial tap weight w0 (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w1,       // Initial tap weight w1 (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w2,       // Initial tap weight w2 (Q4.12)

    // LMS Adaptation Signals (from rx_top)
    input  logic                          i_cfg_lms_en,       // 1: Adapt weights via LMS, 0: Hold weights
    input  logic signed [DATA_WIDTH-1:0]  i_error,            // Error e[n] from rx_top (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_learning_rate,    // Step-size mu (Q0.16)

    // Outputs
    output logic                          o_valid,            // Aligned valid signal
    output logic signed [DATA_WIDTH-1:0]  o_ffe_data,         // y_ffe[n] filtered output (Q4.12)
    output logic signed [DATA_WIDTH-1:0]  o_curr_w0,          // Current adapted w0 (for debug)
    output logic signed [DATA_WIDTH-1:0]  o_curr_w1,          // Current adapted w1 (for debug)
    output logic signed [DATA_WIDTH-1:0]  o_curr_w2           // Current adapted w2 (for debug)
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
    // 1. 3-Tap Input Delay Line: x[n], x[n-1], x[n-2]
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] x_reg [0:TAG_FFE-1];
    logic                         valid_r;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            for (int k = 0; k < TAG_FFE; k++) begin
                x_reg[k] <= '0;
            end
            valid_r <= 1'b0;
        end else if (i_valid) begin
            x_reg[0] <= i_r_in;
            x_reg[1] <= x_reg[0];
            x_reg[2] <= x_reg[1];
            valid_r  <= 1'b1;
        end else begin
            valid_r  <= 1'b0;
        end
    end

    // =========================================================================
    // 2. Tap Weight Registers (w0, w1, w2)
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] w_reg [0:TAG_FFE-1];

    // =========================================================================
    // 3. Embedded LMS Weight Adaptation Logic
    //    w_k[n+1] = w_k[n] + mu * e[n] * x[n-k]
    //    (Multipliers and saturation logic mapped cleanly for FPGA DSP slices)
    // delta = (mu * e * x)
    // Member 3 can fine-tune bit-true fixed-point scaling here
    logic signed [31:0] prod_err_x;
    logic signed [47:0] prod_mu;
    logic signed [31:0] delta;
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            w_reg[0] <= i_cfg_ffe_w0;
            w_reg[1] <= i_cfg_ffe_w1;
            w_reg[2] <= i_cfg_ffe_w2;
        end else if (i_cfg_lms_en && valid_r) begin
            for (int k = 0; k < TAG_FFE; k++) begin

                prod_err_x = $signed(i_error) * $signed(x_reg[k]);
                prod_mu    = $signed(i_learning_rate) * $signed(prod_err_x >>> DATA_FRAC);
                delta      = prod_mu >>> 16; // mu is Q0.16

                w_reg[k]   <= sat16($signed({{16{w_reg[k][15]}}, w_reg[k]}) + delta);
            end
        end else if (!i_cfg_lms_en) begin
            // Hold or reload initial weights when adaptation is disabled
            w_reg[0] <= i_cfg_ffe_w0;
            w_reg[1] <= i_cfg_ffe_w1;
            w_reg[2] <= i_cfg_ffe_w2;
        end
    end

    // =========================================================================
    // 4. FIR Filter Datapath: sum(w_k * x_k)
    // =========================================================================
    logic signed [31:0] mul_prod [0:TAG_FFE-1];
    logic signed [31:0] sum_ffe_32;
    logic signed [DATA_WIDTH-1:0] y_ffe;

    always_comb begin
        sum_ffe_32 = '0;
        for (int k = 0; k < TAG_FFE; k++) begin
            mul_prod[k] = $signed(x_reg[k]) * $signed(w_reg[k]);
            sum_ffe_32  = sum_ffe_32 + (mul_prod[k] >>> DATA_FRAC);
        end

        if (i_cfg_ffe_en) begin
            y_ffe = sat16(sum_ffe_32);
        end else begin
            y_ffe = x_reg[0]; // Bypass FFE
        end
    end

    // =========================================================================
    // Outputs
    // =========================================================================
    assign o_valid    = valid_r;
    assign o_ffe_data = y_ffe;
    assign o_curr_w0  = w_reg[0];
    assign o_curr_w1  = w_reg[1];
    assign o_curr_w2  = w_reg[2];

endmodule: rx_ffe
