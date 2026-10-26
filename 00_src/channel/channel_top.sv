// =============================================================================
// Module Name:   channel_top
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 2 (Nhat Huy)
// Description:   Channel Impairment Emulation Top-Level Module.
//                Contains:
//                1. First-Postcursor ISI Channel Filter:
//                   r_clean[n] = s[n] + i_cfg_isi_coeff * s[n-1] (h0 = 1.0)
//                2. CLT-Based Hardware AWGN Generator (12 Taus88 URNG Lanes +
//                   Adder Tree + Fixed-Point Variance Normalization)
//                3. Configurable Noise Scaling & Adder:
//                   r_noisy[n] = r_clean[n] + sigma_noise * AWGN[n]
// =============================================================================

`timescale 1ns / 1ps

module channel_top #(
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC  = 12
)(
    // Clock & Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // Input Sample from TX
    input  logic                          i_valid,
    input  logic signed [DATA_WIDTH-1:0]  i_tx_data,          // Signed 16-bit Q4.12 from tx_top

    // Channel Impairment Configurations
    input  logic                          i_cfg_isi_en,       // 1: Enable ISI distortion, 0: Bypass ISI
    input  logic signed [DATA_WIDTH-1:0]  i_cfg_isi_coeff,    // Hệ số ISI (post-cursor h1): mức độ điện áp trước s[n-1] ảnh hưởng đến điện áp sau s[n] (default: 16'sh0800 = 0.50, h0 cố định = 1.0)
    input  logic                          i_cfg_awgn_en,      // 1: Enable AWGN noise injection, 0: Clean signal
    input  logic [15:0]                   i_cfg_snr_db,       // SNR setting (or scaling factor sigma_noise, Q4.12)

    // Channel Outputs
    output logic                          o_valid,            // Valid signal aligned with output latency
    output logic signed [DATA_WIDTH-1:0]  o_channel_data,     // r_noisy: Signal after ISI + AWGN (Q4.12)
    output logic signed [DATA_WIDTH-1:0]  o_clean_isi_data,   // r_clean: Signal with ISI only (no noise, for debug)
    output logic signed [DATA_WIDTH-1:0]  o_awgn_noise        // Generated AWGN noise sample (for debug)
);

    // =========================================================================
    // Helper Saturation Function (prevents fixed-point 16-bit wrap-around)
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
    // 1. ISI Filter Subsystem (First-Postcursor Channel Model)
    //    r_clean[n] = s[n] + i_cfg_isi_coeff * s[n-1] (h0 fixed to 1.0)
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] curr_s_r;
    logic signed [DATA_WIDTH-1:0] prev_s_r;
    logic                         isi_valid_r;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            curr_s_r    <= '0;
            prev_s_r    <= '0;
            isi_valid_r <= 1'b0;
        end else if (i_valid) begin
            curr_s_r    <= i_tx_data;
            prev_s_r    <= curr_s_r;
            isi_valid_r <= 1'b1;
        end else begin
            isi_valid_r <= 1'b0;
        end
    end

    // Postcursor ISI multiplication (Q4.12 * Q4.12 = Q8.24)
    logic signed [31:0]           mul_h1;
    logic signed [DATA_WIDTH-1:0] term_h1;
    logic signed [31:0]           sum_isi_raw;
    logic signed [DATA_WIDTH-1:0] r_clean;

    always_comb begin
        // h0 is fixed to 1.0 (main cursor), so term_h0 = curr_s_r
        mul_h1  = prev_s_r * i_cfg_isi_coeff;
        term_h1 = mul_h1 >>> DATA_FRAC;

        sum_isi_raw = $signed({{16{curr_s_r[15]}}, curr_s_r}) +
                      $signed({{16{term_h1[15]}}, term_h1});

        if (i_cfg_isi_en) begin
            r_clean = sat16(sum_isi_raw);
        end else begin
            r_clean = curr_s_r; // Bypass ISI
        end
    end

    // =========================================================================
    // 2. CLT-Based Hardware AWGN Generator
    //    - Uses 12 parallel Taus88 pseudo-random generators
    //    - Pipelined adder tree sums uniform samples
    //    - Subtracts mean (12 * 2048) and scales to unit variance Q4.12
    //    (TODO: Member 2 connects detailed 12-lane Taus88 sub-modules here)
    // =========================================================================
    logic signed [DATA_WIDTH-1:0] awgn_sample;
    logic                         awgn_valid;

    // Temporary placeholder / hook for Member 2's full CLT Taus88 block
    // Refer to 252_ĐATN/code/00_src/02_channel_noise/channel_noise_AWGN_v3.sv
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            awgn_sample <= '0;
            awgn_valid  <= 1'b0;
        end else begin
            awgn_valid  <= isi_valid_r;
            // Member 2 will connect the verified CLT adder-tree output here
            awgn_sample <= 16'sh0000;
        end
    end

    // =========================================================================
    // 3. Noise Scaling and Injection Adder
    //    r_noisy[n] = r_clean[n] + sigma_noise * AWGN[n]
    // =========================================================================
    logic signed [31:0] scaled_noise_32;
    logic signed [DATA_WIDTH-1:0] scaled_noise;
    logic signed [31:0] r_noisy_32;

    always_comb begin
        // i_cfg_snr_db is used as a fixed-point noise gain multiplier sigma_noise (Q4.12)
        scaled_noise_32 = awgn_sample * $signed(i_cfg_snr_db);
        scaled_noise    = scaled_noise_32 >>> DATA_FRAC;

        if (i_cfg_awgn_en) begin
            r_noisy_32 = $signed({{16{r_clean[15]}}, r_clean}) +
                         $signed({{16{scaled_noise[15]}}, scaled_noise});
        end else begin
            r_noisy_32 = $signed({{16{r_clean[15]}}, r_clean});
        end
    end

    // =========================================================================
    // Outputs
    // =========================================================================
    assign o_valid          = isi_valid_r;
    assign o_clean_isi_data = r_clean;
    assign o_awgn_noise     = scaled_noise;
    assign o_channel_data   = sat16(r_noisy_32);

endmodule: channel_top
