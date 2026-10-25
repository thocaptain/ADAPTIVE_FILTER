`timescale 1ns/1ps

// Transport fixtures only; compile separately from the real child RTL.
module tx_top #(
    parameter integer NUMBER_SYMBOL = 1,
    parameter logic [6:0] PRBS_SEED = 7'h7f
)(
    input logic i_clk, i_rst_n,
    output logic signed [NUMBER_SYMBOL-1:0][3:0] o_sym,
    output logic        [NUMBER_SYMBOL-1:0][1:0] o_bits_ref
);
    logic [31:0] symbol_base;
    logic [NUMBER_SYMBOL-1:0][1:0] source_bits;
    function automatic [1:0] test_gray(input logic [31:0] index);
        logic [31:0] hash;
        begin
            hash = (index + 32'(PRBS_SEED)) * 32'h9e3779b9;
            hash = (hash ^ (hash >> 16)) * 32'h85ebca6b;
            hash = hash ^ (hash >> 13);
            test_gray = hash[1:0];
        end
    endfunction
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) symbol_base <= '0;
        else symbol_base <= symbol_base + NUMBER_SYMBOL;
    end
    for (genvar lane = 0; lane < NUMBER_SYMBOL; lane = lane + 1) begin : g_source
        assign source_bits[lane] = test_gray(symbol_base + lane);
        always_comb begin
            case (o_bits_ref[lane])
                2'b00: o_sym[lane] = -4'sd3;
                2'b01: o_sym[lane] = -4'sd1;
                2'b11: o_sym[lane] =  4'sd1;
                default: o_sym[lane] = 4'sd3;
            endcase
        end
    end
    if (`TEST_TX == 0) begin : g_no_pipe
        assign o_bits_ref = source_bits;
    end else begin : g_pipe
        logic [NUMBER_SYMBOL-1:0][1:0] pipe [0:`TEST_TX-1];
        always_ff @(posedge i_clk or negedge i_rst_n) begin
            if (!i_rst_n) begin
                for (integer k = 0; k < `TEST_TX; k = k + 1) pipe[k] <= '0;
            end else begin
                pipe[0] <= source_bits;
                for (integer k = 1; k < `TEST_TX; k = k + 1) pipe[k] <= pipe[k-1];
            end
        end
        assign o_bits_ref = pipe[`TEST_TX-1];
    end
endmodule

module channel_top #(
    parameter integer NUMBER_SYMBOL = 1,
    parameter logic signed [15:0] H1_Q12 = 16'sd2048,
    parameter logic [31:0] NOISE_SEED = 32'h00000a5b,
    parameter logic [7:0] DEFAULT_SNR_DB = 8'd20
)(
    input logic i_clk, i_rst_n,
    input logic signed [NUMBER_SYMBOL-1:0][3:0] i_sym,
    input logic i_noise_en, i_cfg_noise_load,
    input logic [7:0] i_cfg_snr_db,
    output logic signed [NUMBER_SYMBOL-1:0][7:0] o_r
);
    logic [NUMBER_SYMBOL-1:0][7:0] scaled;
    for (genvar lane = 0; lane < NUMBER_SYMBOL; lane = lane + 1) begin : g_scale
        assign scaled[lane] = {i_sym[lane], 4'b0};
    end
    if (`TEST_CH == 0) begin : g_no_pipe
        assign o_r = scaled;
    end else begin : g_pipe
        logic [NUMBER_SYMBOL-1:0][7:0] pipe [0:`TEST_CH-1];
        always_ff @(posedge i_clk or negedge i_rst_n) begin
            if (!i_rst_n) begin
                for (integer k = 0; k < `TEST_CH; k = k + 1) pipe[k] <= '0;
            end else begin
                pipe[0] <= scaled;
                for (integer k = 1; k < `TEST_CH; k = k + 1) pipe[k] <= pipe[k-1];
            end
        end
        assign o_r = pipe[`TEST_CH-1];
    end
endmodule

module rx_top #(
    parameter integer NUMBER_SYMBOL = 1,
    parameter integer TRAIN_LEN = 3000,
    parameter integer STARTUP_CYCLES = 2,
    parameter integer REF_DELAY_CYCLES = 1,
    parameter logic signed [39:0] MU_F20 = 40'sd524
)(
    input logic i_clk, i_rst_n,
    input logic signed [NUMBER_SYMBOL-1:0][7:0] i_r,
    input logic signed [NUMBER_SYMBOL-1:0][3:0] i_tx_ref,
    input logic signed [15:0] i_cfg_ffe0, i_cfg_ffe1, i_cfg_ffe2, i_cfg_dfe0,
    input logic i_cfg_load, i_adapt_en, i_ffe_bypass, i_dfe_bypass,
    output logic signed [NUMBER_SYMBOL-1:0][3:0] o_sym,
    output logic        [NUMBER_SYMBOL-1:0][1:0] o_bits,
    output logic signed [NUMBER_SYMBOL-1:0][15:0] o_y,
    output logic signed [15:0] o_ffe0, o_ffe1, o_ffe2, o_dfe0
);
    localparam integer PIPE = `TEST_FF + `TEST_DF + `TEST_SL;
    localparam integer HISTORY = (`TEST_D > 0) ? `TEST_D : 1;
    logic [NUMBER_SYMBOL-1:0][1:0] decoded, delayed, selected, recovered;
    logic [1:0] past [0:HISTORY-1];
    logic ffe_bypass_q;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            ffe_bypass_q <= 1'b0;
            o_ffe0 <= '0; o_ffe1 <= 16'sd3072; o_ffe2 <= '0; o_dfe0 <= '0;
        end else if (i_cfg_load) begin
            ffe_bypass_q <= i_ffe_bypass;
            o_ffe0 <= i_cfg_ffe0; o_ffe1 <= i_cfg_ffe1;
            o_ffe2 <= i_cfg_ffe2; o_dfe0 <= i_cfg_dfe0;
        end
    end
    // A symbol FIFO models target delay independently of the Top's block addressing.
    for (genvar k = 0; k < HISTORY; k = k + 1) begin : g_history
        if (k < NUMBER_SYMBOL) begin : g_input
            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) past[k] <= '0;
                else past[k] <= decoded[NUMBER_SYMBOL-1-k];
            end
        end else begin : g_past
            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) past[k] <= '0;
                else past[k] <= past[k-NUMBER_SYMBOL];
            end
        end
    end
    for (genvar lane = 0; lane < NUMBER_SYMBOL; lane = lane + 1) begin : g_lane
        always_comb begin
            case (i_r[lane])
                -8'sd48: decoded[lane] = 2'b00;
                -8'sd16: decoded[lane] = 2'b01;
                 8'sd16: decoded[lane] = 2'b11;
                 8'sd48: decoded[lane] = 2'b10;
                default: decoded[lane] = 2'b00;
            endcase
        end
        if (lane >= `TEST_D) begin : g_same_block
            assign delayed[lane] = decoded[lane-`TEST_D];
        end else begin : g_previous_block
            assign delayed[lane] = past[`TEST_D-1-lane];
        end
        assign o_sym[lane] = '0;
        assign o_y[lane] = '0;
    end
    assign selected = ffe_bypass_q ? decoded : delayed;
    if (PIPE == 0) begin : g_no_pipe
        assign recovered = selected;
    end else begin : g_pipe
        logic [NUMBER_SYMBOL-1:0][1:0] pipe [0:PIPE-1];
        always_ff @(posedge i_clk or negedge i_rst_n) begin
            if (!i_rst_n) begin
                for (integer k = 0; k < PIPE; k = k + 1) pipe[k] <= '0;
            end else begin
                pipe[0] <= selected;
                for (integer k = 1; k < PIPE; k = k + 1) pipe[k] <= pipe[k-1];
            end
        end
        assign recovered = pipe[PIPE-1];
    end
    assign o_bits = recovered ^ ber_block_test.error_mask;
endmodule

module ber_block_test(
    input logic i_clk, i_rst_n,
    input logic enabled, clear, cfg_load, noise_load, noise_en, adapt_en, bp_f, bp_d,
    input logic [`TEST_N-1:0][1:0] error_mask,
    output logic [`TEST_CW-1:0] errors, total,
    output logic ready,
    output logic [31:0] latency,
    output logic [`TEST_N-1:0][1:0] tx_bits, rx_bits
);
    Top #(
        .NUMBER_SYMBOL (`TEST_N),
        .TX_LATENCY (`TEST_TX), .CHANNEL_LATENCY (`TEST_CH),
        .FFE_LATENCY (`TEST_FF), .DFE_LATENCY (`TEST_DF), .SLICER_LATENCY (`TEST_SL),
        .FFE_SYMBOL_DELAY (`TEST_D), .TRAIN_LEN (`TEST_TRAIN),
        .BER_COUNTER_WIDTH (`TEST_CW), .BER_SKIP_TRAINING (`TEST_SKIP)
    ) dut (
        .i_clk (i_clk), .i_rst_n (i_rst_n),
        .i_noise_en (noise_en), .i_cfg_snr_db (8'd20), .i_cfg_noise_load (noise_load),
        .i_cfg_ffe0 (16'sd0), .i_cfg_ffe1 (16'sd3072),
        .i_cfg_ffe2 (16'sd0), .i_cfg_dfe0 (16'sd0),
        .i_cfg_load (cfg_load), .i_adapt_en (adapt_en),
        .i_ffe_bypass (bp_f), .i_dfe_bypass (bp_d),
        .i_ber_en (enabled), .i_ber_clear (clear),
        .o_tx_sym (), .o_tx_bits (tx_bits), .o_channel_r (),
        .o_rx_sym (), .o_rx_bits (rx_bits), .o_rx_y (),
        .o_ffe0 (), .o_ffe1 (), .o_ffe2 (), .o_dfe0 (),
        .o_ber_error_bits (errors), .o_ber_total_bits (total),
        .o_ber_ready (ready), .o_ber_latency (latency)
    );
endmodule
