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
    parameter int PIPELINE   = 1,
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
    input  logic                          i_error_valid,      // Error belongs to the current RX output 
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
        input logic signed [63:0] val
    );
        if (val > ((64'sd1 <<< (DATA_WIDTH-1)) - 1))
            sat16 = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else if (val < -(64'sd1 <<< (DATA_WIDTH-1)))
            sat16 = {1'b1, {(DATA_WIDTH-1){1'b0}}};
        else
            sat16 = val[DATA_WIDTH-1:0];
    endfunction

    // MATLAB round(): halfway cases round away from zero.
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
    // 1. 3-Tap Input Delay Line: x[n], x[n-1], x[n-2]
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] x_reg [0:(TAG_FFE+2)-1];
    logic                         valid_r;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            for (int k = 0; k < TAG_FFE + 2; k++) begin
                x_reg[k] <= '0;
            end
            valid_r <= 1'b0;
        end else if (i_valid) begin
            x_reg[0] <= i_r_in;
            x_reg[1] <= x_reg[0];
            x_reg[2] <= x_reg[1];
            x_reg[3] <= x_reg[2];
            x_reg[4] <= x_reg[3];
            valid_r  <= 1'b1;
        end else begin
            valid_r  <= 1'b0;
        end
    end

    // =========================================================================
    // 2. Tap Weight Registers (w0, w1, w2)
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] w_reg [0:TAG_FFE-1];
    logic signed [39:0] w_acc [0:TAG_FFE-1]; // Q20, preserves sub-Q12-LSB updates

    // =========================================================================
    // 3. Embedded LMS Weight Adaptation Logic
    //    w_k[n+1] = w_k[n] + mu * e[n] * x[n-k]
    // No intermediate truncation: delta_Q20 = round(mu_Q16 * e * x / 2^20)
    // for the default Q12 input/error. Coefficient accumulators saturate at
    // 40 bits; visible taps round/saturate separately to the external format.
    logic signed [2*DATA_WIDTH-1:0] prod_err_x [0:TAG_FFE-1];
    logic signed [3*DATA_WIDTH-1:0] prod_mu [0:TAG_FFE-1];
    logic signed [39:0] delta [0:TAG_FFE-1];
    generate
        if (PIPELINE) begin
            always_comb begin
                for (int k = 0; k < TAG_FFE; k++) begin
                    prod_err_x[k] = $signed(i_error) * $signed(x_reg[k+2]);
                    prod_mu[k]    = $signed(i_learning_rate) * $signed(prod_err_x[k]);
                    delta[k]      = sat40(round_shift(64'($signed(prod_mu[k])), 16+2*DATA_FRAC-20));
                    w_reg[k]      = sat16(round_shift(64'($signed(w_acc[k])), 20-DATA_FRAC));
                end
            end

            always_ff @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) begin
                w_acc[0] <= sat40(64'($signed(i_cfg_ffe_w0)) <<< (20-DATA_FRAC));
                w_acc[1] <= sat40(64'($signed(i_cfg_ffe_w1)) <<< (20-DATA_FRAC));
                w_acc[2] <= sat40(64'($signed(i_cfg_ffe_w2)) <<< (20-DATA_FRAC));
            end else if (i_cfg_lms_en && i_error_valid) begin
                for (int k = 0; k < TAG_FFE; k++) begin
                    w_acc[k] <= sat40(64'($signed(w_acc[k])) + 64'($signed(delta[k])));
                end
            end else if (!i_cfg_lms_en) begin
                // Hold or reload initial weights when adaptation is disabled
                w_acc[0] <= sat40(64'($signed(i_cfg_ffe_w0)) <<< (20-DATA_FRAC));
                w_acc[1] <= sat40(64'($signed(i_cfg_ffe_w1)) <<< (20-DATA_FRAC));
                w_acc[2] <= sat40(64'($signed(i_cfg_ffe_w2)) <<< (20-DATA_FRAC));
            end
            end
        end
        else begin
            always_comb begin
                for (int k = 0; k < TAG_FFE; k++) begin
                    prod_err_x[k] = $signed(i_error) * $signed(x_reg[k]);
                    prod_mu[k]    = $signed(i_learning_rate) * $signed(prod_err_x[k]);
                    delta[k]      = sat40(round_shift(64'($signed(prod_mu[k])), 16+2*DATA_FRAC-20));
                    w_reg[k]      = sat16(round_shift(64'($signed(w_acc[k])), 20-DATA_FRAC));
                end
            end

            always_ff @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) begin
                w_acc[0] <= sat40(64'($signed(i_cfg_ffe_w0)) <<< (20-DATA_FRAC));
                w_acc[1] <= sat40(64'($signed(i_cfg_ffe_w1)) <<< (20-DATA_FRAC));
                w_acc[2] <= sat40(64'($signed(i_cfg_ffe_w2)) <<< (20-DATA_FRAC));
            end else if (i_cfg_lms_en && valid_r) begin
                for (int k = 0; k < TAG_FFE; k++) begin
                    w_acc[k] <= sat40(64'($signed(w_acc[k])) + 64'($signed(delta[k])));
                end
            end else if (!i_cfg_lms_en) begin
                // Hold or reload initial weights when adaptation is disabled
                w_acc[0] <= sat40(64'($signed(i_cfg_ffe_w0)) <<< (20-DATA_FRAC));
                w_acc[1] <= sat40(64'($signed(i_cfg_ffe_w1)) <<< (20-DATA_FRAC));
                w_acc[2] <= sat40(64'($signed(i_cfg_ffe_w2)) <<< (20-DATA_FRAC));
            end
            end

        end
    endgenerate

   

    // =========================================================================
    // 4. FIR Filter Datapath: sum(w_k * x_k)
    // =========================================================================
    logic signed [31:0] mul_prod [0:TAG_FFE-1];
    logic signed [DATA_WIDTH-1:0] term_ffe [0:TAG_FFE-1];
    logic signed [31:0] sum_ffe_32;
    logic signed [DATA_WIDTH-1:0] y_ffe;

    always_comb begin
        sum_ffe_32 = '0;
        for (int k = 0; k < TAG_FFE; k++) begin
            mul_prod[k] = $signed(x_reg[k]) * $signed(w_reg[k]);
            // Match v26: saturate each quantized product before summing.
            term_ffe[k] = sat16(64'($signed(mul_prod[k])) >>> DATA_FRAC);
            sum_ffe_32 = sum_ffe_32 + 32'($signed(term_ffe[k]));
        end

        if (i_cfg_ffe_en) begin
            y_ffe = sat16(64'($signed(sum_ffe_32)));
        end else begin
            y_ffe = x_reg[0]; // Bypass FFE
        end
    end

    // =========================================================================
    // Keep one sample register in the closed loop. With another output
    // register, i_error would belong to the previous x_reg sample.
    // =========================================================================
generate
    if (PIPELINE) begin : gen_pipeline
        always_ff @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) begin
                o_valid    <= 1'b0;
                o_ffe_data <= '0;
            end else if (valid_r) begin
                o_ffe_data <= y_ffe;
            end
            o_valid    <= valid_r;
        end
    end else begin : gen_comb
        assign o_valid    = valid_r;
        assign o_ffe_data = y_ffe;
    end
endgenerate


    assign o_curr_w0  = w_reg[0];
    assign o_curr_w1  = w_reg[1];
    assign o_curr_w2  = w_reg[2];

endmodule: rx_ffe
