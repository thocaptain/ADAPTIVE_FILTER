// =============================================================================
// Module Name:   rx_monitor
// Project:       FPGA-Based PAM-4 Communication System
// Member:        Member 1 (Dac Huy)
// Description:   Receiver PAM-4 Demapper & Cyclic Pattern BER Monitor.
//                Contains:
//                1. PAM-4 Demapper: maps Q4.12 symbol to 2-bit Gray code
//                2. Gray Demapper: converts 2-bit Gray code to 2-bit binary (0,1,2,3)
//                3. Cyclic Pattern BER Monitor:
//                   - Tracks expected cyclic sequence (0 -> 1 -> 2 -> 3)
//                   - Compares recovered bits with expected bits
//                   - Accumulates Total Evaluated Words & Bit Errors
//                   - Snapshot Trigger captures stable values into 32-bit status registers
// =============================================================================

`timescale 1ns / 1ps

module rx_monitor #(
    parameter int SYMB_BITS  = 2,
    parameter int DATA_WIDTH = 16
)(
    // Clock & Reset
    input  logic                          i_clk,
    input  logic                          i_rstn,

    // Input Sliced Decision from Slicer (d_hat[n])
    input  logic                          i_valid,
    input  logic signed [DATA_WIDTH-1:0]  i_sliced_data,      // Sliced PAM-4 symbol (-3, -1, +1, +3 in Q4.12)

    // Monitor Configuration & Control
    input  logic                          i_cfg_mon_en,       // 1: Enable BER monitoring, 0: Reset/Hold counters
    input  logic                          i_cfg_snapshot_trig,// Pulse high to freeze current counters into status regs

    // Real-Time Recovered Data
    output logic [SYMB_BITS-1:0]          o_recovered_gray,   // 2-bit recovered Gray code
    output logic [SYMB_BITS-1:0]          o_recovered_bin,    // 2-bit recovered binary symbol (0, 1, 2, 3)
    output logic                          o_bit_error_pulse,  // Pulses high on any bit mismatch

    // 32-Bit Readable Status Registers
    output logic [31:0]                   o_stat_total_words, // Latched count of total evaluated symbols
    output logic [31:0]                   o_stat_err_bits,    // Latched count of total bit errors
    output logic                          o_stat_sync_locked  // 1: Monitor is synchronized with transmitter sequence
);

    // =========================================================================
    // 1. PAM-4 Demapper (Q4.12 Level -> 2-Bit Gray Code)
    // =========================================================================
    logic [SYMB_BITS-1:0] rx_gray_bits;

    always_comb begin
        case (i_sliced_data)
            16'shD000: rx_gray_bits = 2'b00; // -3 level
            16'shF000: rx_gray_bits = 2'b01; // -1 level
            16'sh1000: rx_gray_bits = 2'b11; // +1 level
            16'sh3000: rx_gray_bits = 2'b10; // +3 level
            default:   rx_gray_bits = 2'b00;
        endcase
    end

    // =========================================================================
    // 2. Gray-to-Binary Demapper
    // Gray: 00 -> 00 (0)
    // Gray: 01 -> 01 (1)
    // Gray: 11 -> 10 (2)
    // Gray: 10 -> 11 (3)
    // =========================================================================
    logic [SYMB_BITS-1:0] rx_bin_val;

    always_comb begin
        rx_bin_val[1] = rx_gray_bits[1];
        rx_bin_val[0] = rx_gray_bits[1] ^ rx_gray_bits[0];
    end

    // =========================================================================
    // 3. Cyclic Sequence Reference & Synchronization Logic
    //    Transmitter cycles: 0 -> 1 -> 2 -> 3 -> 0...
    //    Receiver synchronizes upon first valid symbol, then increments locally.
    // =========================================================================
    logic [SYMB_BITS-1:0] exp_bin_cnt_r;
    logic                 sync_locked_r;
    logic [3:0]           lock_confidence_cnt;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            exp_bin_cnt_r       <= '0;
            sync_locked_r       <= 1'b0;
            lock_confidence_cnt <= '0;
        end else if (!i_cfg_mon_en) begin
            exp_bin_cnt_r       <= '0;
            sync_locked_r       <= 1'b0;
            lock_confidence_cnt <= '0;
        end else if (i_valid) begin
            if (!sync_locked_r) begin
                // Lock initial reference to incoming symbol
                exp_bin_cnt_r       <= rx_bin_val + 1'b1;
                lock_confidence_cnt <= lock_confidence_cnt + 1'b1;
                if (lock_confidence_cnt >= 4'd8) begin
                    sync_locked_r   <= 1'b1;
                end
            end else begin
                // Advance expected cyclic counter
                exp_bin_cnt_r       <= exp_bin_cnt_r + 1'b1;
            end
        end
    end

    // =========================================================================
    // 4. Bit Error Computation
    // =========================================================================
    logic [1:0] bit_diff;
    logic [1:0] error_in_this_symb;

    always_comb begin
        if (i_valid && sync_locked_r) begin
            // Compare expected binary with received binary
            bit_diff = rx_bin_val ^ exp_bin_cnt_r;
            // Count number of differing bits (0, 1, or 2)
            error_in_this_symb = {1'b0, bit_diff[1]} + {1'b0, bit_diff[0]};
        end else begin
            bit_diff           = 2'b00;
            error_in_this_symb = 2'b00;
        end
    end

    // =========================================================================
    // 5. Accumulation Counters (Live Free-Running)
    // =========================================================================
    logic [31:0] live_word_cnt_r;
    logic [31:0] live_err_bit_cnt_r;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            live_word_cnt_r    <= '0;
            live_err_bit_cnt_r <= '0;
        end else if (!i_cfg_mon_en) begin
            live_word_cnt_r    <= '0;
            live_err_bit_cnt_r <= '0;
        end else if (i_valid && sync_locked_r) begin
            live_word_cnt_r    <= live_word_cnt_r + 1'b1;
            live_err_bit_cnt_r <= live_err_bit_cnt_r + error_in_this_symb;
        end
    end

    // =========================================================================
    // 6. Snapshot Holding Registers (Latched via i_cfg_snapshot_trig)
    // =========================================================================
    logic [31:0] snap_total_words_r;
    logic [31:0] snap_err_bits_r;

    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            snap_total_words_r <= '0;
            snap_err_bits_r    <= '0;
        end else if (i_cfg_snapshot_trig) begin
            snap_total_words_r <= live_word_cnt_r;
            snap_err_bits_r    <= live_err_bit_cnt_r;
        end
    end

    // =========================================================================
    // Outputs
    // =========================================================================
    assign o_recovered_gray   = rx_gray_bits;
    assign o_recovered_bin    = rx_bin_val;
    assign o_bit_error_pulse  = |error_in_this_symb;
    assign o_stat_sync_locked = sync_locked_r;
    assign o_stat_total_words = snap_total_words_r;
    assign o_stat_err_bits    = snap_err_bits_r;

endmodule: rx_monitor
