`timescale 1ns/1ps

// AXI4-Lite adapter for the current top.sv (16-bit Q4.12 datapath).
// Exposes only top's actual runtime controls and two 32-bit snapshot counters.
module top_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 8,
    parameter integer PIPELINE = 0,
    parameter integer TRAIN_LEN = 3000
)(
      input  logic                            S_AXI_ACLK
    , input  logic                            S_AXI_ARESETN
    , input  logic [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR
    , input  logic [2:0]                      S_AXI_AWPROT
    , input  logic                            S_AXI_AWVALID
    , output logic                            S_AXI_AWREADY
    , input  logic [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA
    , input  logic [C_S_AXI_DATA_WIDTH/8-1:0] S_AXI_WSTRB
    , input  logic                            S_AXI_WVALID
    , output logic                            S_AXI_WREADY
    , output logic [1:0]                      S_AXI_BRESP
    , output logic                            S_AXI_BVALID
    , input  logic                            S_AXI_BREADY
    , input  logic [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR
    , input  logic [2:0]                      S_AXI_ARPROT
    , input  logic                            S_AXI_ARVALID
    , output logic                            S_AXI_ARREADY
    , output logic [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA
    , output logic [1:0]                      S_AXI_RRESP
    , output logic                            S_AXI_RVALID
    , input  logic                            S_AXI_RREADY

);
    logic cfg_awgn_en, cfg_lms_en, cfg_mon_en, cfg_ffe_en, cfg_dfe_en, cfg_tx_en, cfg_isi_en, cfg_snapshot_trig;
    logic cfg_dut_reset_n;
    logic [15:0] cfg_snr_db;
    logic signed [15:0] cfg_ffe_w0;
    logic signed [15:0] cfg_ffe_w1;
    logic signed [15:0] cfg_ffe_w2;
    logic signed [15:0] cfg_dfe_b0;
    logic signed [15:0] cfg_isi_coeff;
    logic signed [15:0] cfg_learning_rate;
    // cfg_snr_db is the current channel's noise gain Q4.12, despite its RTL name.
    logic [31:0] stat_total_words, stat_err_bits;

    adaptive_eq_axi_regs #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) axi_regs (
        .S_AXI_ACLK(S_AXI_ACLK),
        .S_AXI_ARESETN(S_AXI_ARESETN),
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWPROT(S_AXI_AWPROT),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARPROT(S_AXI_ARPROT),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        .o_cfg_awgn_en(cfg_awgn_en),
        .o_cfg_lms_en(cfg_lms_en),
        .o_cfg_mon_en(cfg_mon_en),
        .o_cfg_ffe_en(cfg_ffe_en),
        .o_cfg_dfe_en(cfg_dfe_en),
        .o_cfg_tx_en(cfg_tx_en),
        .o_cfg_isi_en(cfg_isi_en),
        .o_cfg_snr_db(cfg_snr_db),
        .o_cfg_ffe_w0(cfg_ffe_w0),
        .o_cfg_ffe_w1(cfg_ffe_w1),
        .o_cfg_ffe_w2(cfg_ffe_w2),
        .o_cfg_dfe_b0(cfg_dfe_b0),
        .o_cfg_isi_coeff(cfg_isi_coeff),
        .o_cfg_learning_rate(cfg_learning_rate),
        .o_cfg_snapshot_trig(cfg_snapshot_trig),
        .o_cfg_dut_reset_n(cfg_dut_reset_n),
        .i_stat_total_words(stat_total_words),
        .i_stat_err_bits(stat_err_bits)
    );

    top #(.DATA_WIDTH(16), .DATA_FRAC(12), .TRAIN_LEN(TRAIN_LEN), PIPELINE(PIPELINE)) core (
        .i_clk(S_AXI_ACLK), .i_rstn(cfg_dut_reset_n),
        .i_cfg_awgn_en(cfg_awgn_en),
        .i_cfg_lms_en(cfg_lms_en),
        .i_cfg_mon_en(cfg_mon_en),
        .i_cfg_ffe_en(cfg_ffe_en),
        .i_cfg_dfe_en(cfg_dfe_en),
        .i_cfg_tx_en(cfg_tx_en),
        .i_cfg_isi_en(cfg_isi_en),
        .i_cfg_snr_db(cfg_snr_db),
        .i_cfg_ffe_w0(cfg_ffe_w0),
        .i_cfg_ffe_w1(cfg_ffe_w1),
        .i_cfg_ffe_w2(cfg_ffe_w2),
        .i_cfg_dfe_b0(cfg_dfe_b0),
        .i_cfg_isi_coeff(cfg_isi_coeff),
        .i_cfg_learning_rate(cfg_learning_rate),
        .i_cfg_snapshot_trig(cfg_snapshot_trig),
        .o_stat_total_words(stat_total_words),
        .o_stat_err_bits(stat_err_bits)
    );
endmodule
