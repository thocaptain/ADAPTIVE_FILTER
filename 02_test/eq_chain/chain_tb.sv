`timescale 1ns/1ps
// Probe wrapper only: all datapath and wiring are the actual source top.
module chain_tb #(parameter int TRAIN_LEN=3000) (
    input logic i_clk, i_rstn, i_tx_en, i_isi_en, i_ffe_en, i_dfe_en, i_lms_en,
    input logic signed [15:0] i_h, i_w0, i_w1, i_w2, i_b0, i_mu,
    output logic o_tx_valid, o_channel_valid, o_rx_valid,
    output logic [1:0] o_tx_raw, o_tx_gray,
    output logic signed [15:0] o_tx, o_channel, o_noise,
    output logic signed [15:0] o_ffe, o_feedback, o_y, o_decision, o_error,
    output logic signed [15:0] o_w0, o_w1, o_w2, o_b0,
    output logic o_training
);
    top #(.TRAIN_LEN(TRAIN_LEN)) dut (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_cfg_tx_en(i_tx_en),
        .i_cfg_isi_en(i_isi_en), .i_cfg_isi_coeff(i_h),
        .i_cfg_awgn_en(1'b0), .i_cfg_snr_db(16'd0),
        .i_cfg_ffe_en(i_ffe_en), .i_cfg_dfe_en(i_dfe_en),
        .i_cfg_ffe_w0(i_w0), .i_cfg_ffe_w1(i_w1), .i_cfg_ffe_w2(i_w2),
        .i_cfg_dfe_b0(i_b0), .i_cfg_lms_en(i_lms_en), .i_cfg_learning_rate(i_mu),
        .i_cfg_mon_en(1'b0), .i_cfg_snapshot_trig(1'b0),
        .o_stat_total_words(), .o_stat_err_bits()
    );
    assign o_tx_valid = dut.tx_valid;
    assign o_channel_valid = dut.chan_valid;
    assign o_rx_valid = dut.u_rx_top.o_valid;
    assign o_tx_raw = dut.u_tx_top.o_tx_sym_raw;
    assign o_tx_gray = dut.u_tx_top.o_tx_gray_bits;
    assign o_tx = dut.tx_data;
    assign o_channel = dut.chan_data;
    assign o_noise = dut.u_channel_top.o_awgn_noise;
    assign o_ffe = dut.u_rx_top.ffe_out;
    assign o_feedback = dut.u_rx_top.dfe_out;
    assign o_y = dut.u_rx_top.o_data_before_slicer;
    assign o_decision = dut.u_rx_top.o_sliced_symbol;
    assign o_error = dut.u_rx_top.o_error;
    assign o_w0 = dut.u_rx_top.o_curr_ffe_w0;
    assign o_w1 = dut.u_rx_top.o_curr_ffe_w1;
    assign o_w2 = dut.u_rx_top.o_curr_ffe_w2;
    assign o_b0 = dut.u_rx_top.o_curr_dfe_b0;
    assign o_training = dut.u_rx_top.o_training;
endmodule
