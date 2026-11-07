// =============================================================================
// Module Name:   rx_top
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 5 (Quy Hau)
// Sub-Modules:   rx_ffe (Member 3), rx_dfe (Member 4), rx_monitor (Member 1)
// Description:   Receiver Top-Level Module.
//                Integrates:
//                1. Adaptive 3-Tap Feed-Forward Equalizer (rx_ffe)
//                2. Adaptive 1-Tap Decision Feedback Equalizer (rx_dfe)
//                3. Equalizer Summer: y[n] = y_ffe[n] - y_dfe[n]
//                4. PAM-4 Slicer (Decision comparator for -3, -1, +1, +3)
//                5. Known-symbol training, then decision-directed LMS
//                6. Cyclic Pattern BER Monitor & Status Reporting (rx_monitor)
// =============================================================================

`timescale 1ns / 1ps

module rx_top #(
    parameter int TAG_FFE    = 3,
    parameter int TAG_DFE    = 1,
    parameter int PIPELINE   = 1,
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC  = 12,
    parameter int TRAIN_LEN  = 3000
)(
    // Clock & Active-Low Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // Channel Input Data
    input  logic                          i_valid,
    input  logic signed [DATA_WIDTH-1:0]  i_r_in,                  // Noisy received sample (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_train_ref,             // TX reference aligned with i_r_in

    // Equalizer Configuration & Initial Weights
    input  logic                          i_cfg_ffe_en,            // 1: Enable FFE, 0: Bypass
    input  logic                          i_cfg_dfe_en,            // 1: Enable DFE, 0: Bypass
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w0,            // Initial weight w0 (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w1,            // Initial weight w1 (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w2,            // Initial weight w2 (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_dfe_b0,            // Initial feedback weight b0 (Q4.12)

    // LMS: first TRAIN_LEN valid outputs use i_train_ref, then slicer target
    input  logic                          i_cfg_lms_en,            // 1: Enable LMS weight update, 0: Hold
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_learning_rate,     // Step size mu (Q0.16)

    // Monitor Configuration
    input  logic                          i_cfg_mon_en,            // 1: Enable BER monitoring, 0: Reset
    input  logic                          i_cfg_snapshot_trig,     // Pulse high to freeze BER counters into status regs

    // Equalizer & Demapper Outputs
    output logic                          o_valid,                 // Aligned output valid
    output logic signed [DATA_WIDTH-1:0]  o_data_before_slicer,    // Pre-slicer sample y[n] (for debug)
    output logic signed [DATA_WIDTH-1:0]  o_sliced_symbol,         // Hard symbol decision d_hat[n]
    output logic [1:0]                    o_recovered_bits,        // Recovered binary data (0, 1, 2, 3)
    output logic signed [DATA_WIDTH-1:0]  o_error,                 // Saturated LMS error e[n]
    output logic                          o_training,              // Current valid output uses known TX target

    // 32-Bit Read Status Registers
    output logic [31:0]                   o_stat_total_words,      // Total words evaluated by monitor
    output logic [31:0]                   o_stat_err_bits,         // Total bit errors captured by monitor

    // Real-Time Tap Coefficients for Monitoring
    output logic signed [DATA_WIDTH-1:0]  o_curr_ffe_w0,
    output logic signed [DATA_WIDTH-1:0]  o_curr_ffe_w1,
    output logic signed [DATA_WIDTH-1:0]  o_curr_ffe_w2,
    output logic signed [DATA_WIDTH-1:0]  o_curr_dfe_b0
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
    // Internal Interconnect Signals
    // =========================================================================
    logic                         ffe_valid;
    logic signed [DATA_WIDTH-1:0] ffe_out;

    logic                         dfe_valid;
    logic signed [DATA_WIDTH-1:0] dfe_out;

    logic signed [17:0]           y_summer_18;
    logic signed [DATA_WIDTH-1:0] y_pre_slicer;
    logic signed [DATA_WIDTH-1:0] d_hat;

    logic signed [31:0]           error_raw_32;
    logic signed [DATA_WIDTH-1:0] lms_error;
    logic signed [DATA_WIDTH-1:0] train_ref_r;
    logic signed [DATA_WIDTH-1:0] train_ref_r2;
    logic signed [DATA_WIDTH-1:0] desired;
    localparam int TRAIN_COUNT_WIDTH = (TRAIN_LEN < 1) ? 1 : $clog2(TRAIN_LEN+1);
    logic [TRAIN_COUNT_WIDTH-1:0] train_count;

    // Reference traverses the same sample register as FFE input. Count only
    // valid errors actually consumed by LMS, including the final flush.
    // Delay of FFE and DFE is 1 clock cycle, so the training reference is delayed by 1 cycle. But if PIPELINE = 1, the training reference is delayed by 2 cycles.
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            train_ref_r <= '0;
            train_count <= '0;
        end else begin
            if (i_valid) train_ref_r <= i_train_ref;
            train_ref_r2 <= train_ref_r;
            if (!i_cfg_lms_en) train_count <= '0;
            else if (ffe_valid && (32'(train_count) < TRAIN_LEN))
                train_count <= train_count + 1'b1;
        end
    end
    assign o_training = i_cfg_lms_en && ffe_valid && (32'(train_count) < TRAIN_LEN);
    generate 
        if (PIPELINE == 1) begin
            assign desired = o_training ? train_ref_r2 : d_hat;
        end 
        else begin
            assign desired = o_training ? train_ref_r : d_hat;
        end
    endgenerate

    // =========================================================================
    // 1. Adaptive 3-Tap FFE: one sample register, no extra output register
    // =========================================================================
    rx_ffe #(
        .TAG_FFE    (TAG_FFE),
        .PIPELINE   (PIPELINE),
        .DATA_WIDTH (DATA_WIDTH),
        .DATA_FRAC  (DATA_FRAC)
    ) u_rx_ffe (
        .i_clk           (i_clk),
        .i_rstn          (i_rstn),
        .i_valid         (i_valid),
        .i_r_in          (i_r_in),
        .i_cfg_ffe_en    (i_cfg_ffe_en),
        .i_cfg_ffe_w0    (i_cfg_ffe_w0),
        .i_cfg_ffe_w1    (i_cfg_ffe_w1),
        .i_cfg_ffe_w2    (i_cfg_ffe_w2),
        .i_cfg_lms_en    (i_cfg_lms_en),
        .i_error         (lms_error),
        .i_learning_rate (i_cfg_learning_rate),
        .o_valid         (ffe_valid),
        .o_ffe_data      (ffe_out),
        .o_curr_w0       (o_curr_ffe_w0),
        .o_curr_w1       (o_curr_ffe_w1),
        .o_curr_w2       (o_curr_ffe_w2)
    );

    // =========================================================================
    // 2. Adaptive 1-Tap DFE Submodule (Member 4 - Ngoc Cuong)
    // =========================================================================
    rx_dfe #(
        .PIPELINE   (PIPELINE),
        .DATA_WIDTH (DATA_WIDTH),
        .DATA_FRAC  (DATA_FRAC)
    ) u_rx_dfe (
        .i_clk           (i_clk),
        .i_rstn          (i_rstn),
        // d_hat belongs to the FFE output, not the channel input.
        // Capture only real decisions, including the final pipeline flush.
        .i_valid         (ffe_valid),
        .i_sliced_data   (d_hat),
        .i_cfg_dfe_en    (i_cfg_dfe_en),
        .i_cfg_dfe_b0    (i_cfg_dfe_b0),
        .i_cfg_lms_en    (i_cfg_lms_en),
        .i_error_valid   (ffe_valid),
        .i_error         (lms_error),
        .i_learning_rate (i_cfg_learning_rate),
        .o_valid         (dfe_valid),
        .o_dfe_data      (dfe_out),
        .o_curr_b0       (o_curr_dfe_b0)
    );

    // =========================================================================
    // 3. Equalizer Summer: y[n] = y_ffe[n] - y_dfe[n]
    // =========================================================================
    always_comb begin
        y_summer_18  = {{2{ffe_out[15]}}, ffe_out} - {{2{dfe_out[15]}}, dfe_out};
        y_pre_slicer = sat16({{14{y_summer_18[17]}}, y_summer_18});
    end

    // =========================================================================
    // 4. PAM-4 Slicer (Decision Comparator for Levels: -3, -1, +1, +3)
    //    Thresholds: -2.0 (16'shE000), 0.0 (16'sh0000), +2.0 (16'sh2000)
    // =========================================================================
    always_comb begin
        if (y_pre_slicer <= -16'sh2000) begin
            d_hat = 16'shD000; // -3 level
        end else if (y_pre_slicer <= 16'sh0000) begin
            d_hat = 16'shF000; // -1 level
        end else if (y_pre_slicer <= 16'sh2000) begin
            d_hat = 16'sh1000; // +1 level
        end else begin
            d_hat = 16'sh3000; // +3 level
        end
    end

    // =========================================================================
    // 5. Error: known TX reference during training, then slicer decision.
    // It remains aligned with the sample held in the FFE/DFE gradient state.
    // =========================================================================
    always_comb begin
        error_raw_32 = $signed({{16{desired[15]}}, desired}) -
                       $signed({{16{y_pre_slicer[15]}}, y_pre_slicer});
        lms_error    = sat16(error_raw_32);
    end

    // =========================================================================
    // 6. Cyclic Pattern BER Monitor Submodule (Member 1 - Dac Huy)
    // =========================================================================
    rx_monitor #(
        .SYMB_BITS  (2),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_rx_monitor (
        .i_clk               (i_clk),
        .i_rstn              (i_rstn),
        .i_valid             (ffe_valid),
        .i_sliced_data       (d_hat),
        .i_cfg_mon_en        (i_cfg_mon_en),
        .i_cfg_snapshot_trig (i_cfg_snapshot_trig),
        .o_recovered_gray    (),
        .o_recovered_bin     (o_recovered_bits),
        .o_bit_error_pulse   (),
        .o_stat_total_words  (o_stat_total_words),
        .o_stat_err_bits     (o_stat_err_bits),
        .o_stat_sync_locked  ()
    );

    // =========================================================================
    // Top-Level Output Assignments
    // =========================================================================
    assign o_valid              = ffe_valid;
    assign o_data_before_slicer = y_pre_slicer;
    assign o_sliced_symbol      = d_hat;
    assign o_error              = lms_error;

endmodule: rx_top
