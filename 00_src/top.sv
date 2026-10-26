// =============================================================================
// Module Name:   top
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 5 (Quy Hau)
// Description:   Full System Top-Level Module.
//                Cascades:
//                [ tx_top ] ---> [ channel_top ] ---> [ rx_top ]
//                Exposes all board-level clocks, resets, configurations,
//                and 32-bit status registers.
// =============================================================================

`timescale 1ns / 1ps

module top #(
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC  = 12
)(
    // Primary Clock & Active-Low Asynchronous Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // TX Configurations
    input  logic                          i_cfg_tx_en,         // Enable 2-bit cyclic Gray code generation

    // Channel Impairment Configurations
    input  logic                          i_cfg_isi_en,        // 1: Enable ISI filter, 0: Bypass ISI
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_isi_coeff,     // Post-cursor ISI coefficient (h1): voltage leak from s[n-1] to s[n] (default: 16'sh0800 = 0.50, h0 fixed = 1.0)
    input  logic                          i_cfg_awgn_en,       // 1: Enable AWGN noise injection, 0: Clean signal
    input  logic [15:0]                   i_cfg_snr_db,        // Noise scale sigma_noise / SNR config (Q4.12)

    // Equalizer Core Configurations
    input  logic                          i_cfg_ffe_en,        // 1: Enable FFE filtering, 0: Bypass FFE
    input  logic                          i_cfg_dfe_en,        // 1: Enable DFE feedback, 0: Bypass DFE
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w0,        // FFE tap 0 weight (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w1,        // FFE tap 1 weight (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_ffe_w2,        // FFE tap 2 weight (Q4.12)
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_dfe_b0,        // DFE tap 0 feedback weight (Q4.12)

    // LMS Adaptation Configurations (Decision-Directed Mode)
    input  logic                          i_cfg_lms_en,        // 1: Enable LMS weight update, 0: Hold
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_learning_rate, // Step size mu (Q0.16)

    // Receiver Monitor Configurations
    input  logic                          i_cfg_mon_en,        // 1: Enable cyclic pattern BER monitor
    input  logic                          i_cfg_snapshot_trig, // Pulse to capture current BER metrics into status regs

    // 32-Bit Read Status Registers
    output logic [31:0]                   o_stat_total_words,  // Total evaluated symbols
    output logic [31:0]                   o_stat_err_bits      // Total bit errors captured
);

    // =========================================================================
    // Inter-Block Interconnect Wires
    // =========================================================================
    logic                         tx_valid;
    logic signed [DATA_WIDTH-1:0] tx_data;

    logic                         chan_valid;
    logic signed [DATA_WIDTH-1:0] chan_data;

    // =========================================================================
    // 1. Transmitter Block (tx_top) - Member 1 (Dac Huy)
    // =========================================================================
    tx_top #(
        .SYMB_BITS  (2),
        .DATA_WIDTH (DATA_WIDTH),
        .DATA_FRAC  (DATA_FRAC)
    ) u_tx_top (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_cfg_tx_en    (i_cfg_tx_en),
        .o_valid        (tx_valid),
        .o_tx_sym_raw   (),
        .o_tx_gray_bits (),
        .o_tx_data      (tx_data)
    );

    // =========================================================================
    // 2. Channel Impairment Block (channel_top) - Member 2 (Nhat Huy)
    // =========================================================================
    channel_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .DATA_FRAC  (DATA_FRAC)
    ) u_channel_top (
        .i_clk            (i_clk),
        .i_rstn           (i_rstn),
        .i_valid          (tx_valid),
        .i_tx_data        (tx_data),
        .i_cfg_isi_en     (i_cfg_isi_en),
        .i_cfg_isi_coeff  (i_cfg_isi_coeff),
        .i_cfg_awgn_en    (i_cfg_awgn_en),
        .i_cfg_snr_db     (i_cfg_snr_db),
        .o_valid          (chan_valid),
        .o_channel_data   (chan_data),
        .o_clean_isi_data (),
        .o_awgn_noise     ()
    );

    // =========================================================================
    // 3. Receiver Block (rx_top) - Integrated by Member 5 (Quy Hau)
    // =========================================================================
    rx_top #(
        .TAG_FFE    (3),
        .TAG_DFE    (1),
        .DATA_WIDTH (DATA_WIDTH),
        .DATA_FRAC  (DATA_FRAC)
    ) u_rx_top (
        .i_clk                (i_clk),
        .i_rstn               (i_rstn),
        .i_valid              (chan_valid),
        .i_r_in               (chan_data),
        .i_cfg_ffe_en         (i_cfg_ffe_en),
        .i_cfg_dfe_en         (i_cfg_dfe_en),
        .i_cfg_ffe_w0         (i_cfg_ffe_w0),
        .i_cfg_ffe_w1         (i_cfg_ffe_w1),
        .i_cfg_ffe_w2         (i_cfg_ffe_w2),
        .i_cfg_dfe_b0         (i_cfg_dfe_b0),
        .i_cfg_lms_en         (i_cfg_lms_en),
        .i_cfg_learning_rate  (i_cfg_learning_rate),
        .i_cfg_mon_en         (i_cfg_mon_en),
        .i_cfg_snapshot_trig  (i_cfg_snapshot_trig),
        .o_valid              (),
        .o_data_before_slicer (),
        .o_sliced_symbol      (),
        .o_recovered_bits     (),
        .o_error              (),
        .o_stat_total_words   (o_stat_total_words),
        .o_stat_err_bits      (o_stat_err_bits),
        .o_curr_ffe_w0        (),
        .o_curr_ffe_w1        (),
        .o_curr_ffe_w2        (),
        .o_curr_dfe_b0        ()
    );

endmodule: top
