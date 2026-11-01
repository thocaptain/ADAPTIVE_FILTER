`timescale 1ns/1ps

// AXI4-Lite registers for the actual runtime interface of top.sv.
// This register ABI replaces the older parallel-symbol / BER64 interface.
module adaptive_eq_axi_regs #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 8
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

    , output logic o_cfg_awgn_en
    , output logic o_cfg_lms_en
    , output logic o_cfg_mon_en
    , output logic o_cfg_ffe_en
    , output logic o_cfg_dfe_en
    , output logic o_cfg_tx_en
    , output logic o_cfg_isi_en
    , output logic [15:0] o_cfg_snr_db
    , output logic signed [15:0] o_cfg_ffe_w0
    , output logic signed [15:0] o_cfg_ffe_w1
    , output logic signed [15:0] o_cfg_ffe_w2
    , output logic signed [15:0] o_cfg_dfe_b0
    , output logic signed [15:0] o_cfg_isi_coeff
    , output logic signed [15:0] o_cfg_learning_rate
    , output logic o_cfg_snapshot_trig
    , input logic [31:0] i_stat_total_words
    , input logic [31:0] i_stat_err_bits
);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CONTROL = 'h00;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_COMMAND = 'h04;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_NOISE_GAIN = 'h08;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_FFE_W0 = 'h0c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_FFE_W1 = 'h10;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_FFE_W2 = 'h14;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_DFE_B0 = 'h18;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_ISI_COEFF = 'h1c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_LEARNING_RATE = 'h24;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_ERROR_BITS = 'h20;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_TOTAL_WORDS = 'h28;
    localparam logic [1:0] AXI_OKAY = 2'b00, AXI_SLVERR = 2'b10;
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    logic [31:0] axi_wdata, write_mask, reg_data_out, control_q;
    logic [3:0] axi_wstrb;
    logic axi_aw_pending, axi_w_pending, slv_reg_wren;
    logic [1:0] reg_read_resp, reg_write_resp;

    // Enable bits match top directly; FFE/DFE are enables, not bypass bits.
    assign o_cfg_awgn_en = control_q[0];
    assign o_cfg_lms_en = control_q[1];
    assign o_cfg_mon_en = control_q[2];
    assign o_cfg_ffe_en = control_q[3];
    assign o_cfg_dfe_en = control_q[4];
    assign o_cfg_tx_en = control_q[5];
    assign o_cfg_isi_en = control_q[6];

    // One outstanding write; address and data may arrive in either order.
    assign S_AXI_AWREADY = S_AXI_ARESETN && !axi_aw_pending && !S_AXI_BVALID;
    assign S_AXI_WREADY  = S_AXI_ARESETN && !axi_w_pending  && !S_AXI_BVALID;
    assign slv_reg_wren  = axi_aw_pending && axi_w_pending && !S_AXI_BVALID;
    assign write_mask    = {{8{axi_wstrb[3]}}, {8{axi_wstrb[2]}},
                            {8{axi_wstrb[1]}}, {8{axi_wstrb[0]}}};

    always_comb begin
        reg_write_resp = AXI_OKAY;
        case (axi_awaddr)
            REG_CONTROL, REG_COMMAND, REG_NOISE_GAIN, REG_CFG_FFE_W0, REG_CFG_FFE_W1, REG_CFG_FFE_W2, REG_CFG_DFE_B0, REG_ISI_COEFF, REG_LEARNING_RATE: ;
            default: reg_write_resp = AXI_SLVERR;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awaddr     <= '0;
            axi_wdata      <= '0;
            axi_wstrb      <= '0;
            axi_aw_pending <= 1'b0;
            axi_w_pending  <= 1'b0;
            S_AXI_BVALID   <= 1'b0;
            S_AXI_BRESP    <= AXI_OKAY;
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                axi_awaddr     <= S_AXI_AWADDR;
                axi_aw_pending <= 1'b1;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                axi_wdata     <= S_AXI_WDATA;
                axi_wstrb     <= S_AXI_WSTRB;
                axi_w_pending <= 1'b1;
            end
            if (slv_reg_wren) begin
                axi_aw_pending <= 1'b0;
                axi_w_pending  <= 1'b0;
                S_AXI_BVALID   <= 1'b1;
                S_AXI_BRESP    <= reg_write_resp;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end


    // Configuration is live. The sole command pulse supported by top is snapshot.
    // With LMS disabled, current RX RTL reloads configured weights each clock.
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            control_q <= '0;
            o_cfg_snr_db <= 16'd0;
            o_cfg_ffe_w0 <= 16'd4096;
            o_cfg_ffe_w1 <= 16'd0;
            o_cfg_ffe_w2 <= 16'd0;
            o_cfg_dfe_b0 <= 16'd0;
            o_cfg_isi_coeff <= 16'd2048;
            o_cfg_learning_rate <= 16'd33;
            o_cfg_snapshot_trig <= 1'b0;
        end else begin
            o_cfg_snapshot_trig <= 1'b0;
            if (slv_reg_wren && reg_write_resp == AXI_OKAY) begin
                case (axi_awaddr)
                    REG_CONTROL: control_q <= ((control_q & ~write_mask)
                                              | (axi_wdata & write_mask)) & 32'h7f;
                    REG_COMMAND: if (axi_wstrb[0]) o_cfg_snapshot_trig <= axi_wdata[0];
                    REG_NOISE_GAIN: begin
                        if (axi_wstrb[0]) o_cfg_snr_db[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_snr_db[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_FFE_W0: begin
                        if (axi_wstrb[0]) o_cfg_ffe_w0[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_ffe_w0[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_FFE_W1: begin
                        if (axi_wstrb[0]) o_cfg_ffe_w1[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_ffe_w1[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_FFE_W2: begin
                        if (axi_wstrb[0]) o_cfg_ffe_w2[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_ffe_w2[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_DFE_B0: begin
                        if (axi_wstrb[0]) o_cfg_dfe_b0[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_dfe_b0[15:8] <= axi_wdata[15:8];
                    end
                    REG_ISI_COEFF: begin
                        if (axi_wstrb[0]) o_cfg_isi_coeff[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_isi_coeff[15:8] <= axi_wdata[15:8];
                    end
                    REG_LEARNING_RATE: begin
                        if (axi_wstrb[0]) o_cfg_learning_rate[7:0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) o_cfg_learning_rate[15:8] <= axi_wdata[15:8];
                    end
                    default: ;
                endcase
            end
        end
    end

    // top's two counters are already a coherent snapshot, not live counters.
    assign S_AXI_ARREADY = S_AXI_ARESETN && !S_AXI_RVALID;
    always_comb begin
        reg_data_out = '0;
        reg_read_resp = AXI_OKAY;
        case (S_AXI_ARADDR)
            REG_CONTROL: reg_data_out = control_q;
            REG_COMMAND: reg_data_out = '0;
            REG_NOISE_GAIN: reg_data_out = {16'd0, o_cfg_snr_db};
            REG_CFG_FFE_W0: reg_data_out = {16'd0, o_cfg_ffe_w0};
            REG_CFG_FFE_W1: reg_data_out = {16'd0, o_cfg_ffe_w1};
            REG_CFG_FFE_W2: reg_data_out = {16'd0, o_cfg_ffe_w2};
            REG_CFG_DFE_B0: reg_data_out = {16'd0, o_cfg_dfe_b0};
            REG_ISI_COEFF: reg_data_out = {16'd0, o_cfg_isi_coeff};
            REG_LEARNING_RATE: reg_data_out = {16'd0, o_cfg_learning_rate};
            REG_ERROR_BITS: reg_data_out = i_stat_err_bits;
            REG_TOTAL_WORDS: reg_data_out = i_stat_total_words;
            default: reg_read_resp = AXI_SLVERR;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= '0;
            S_AXI_RRESP  <= AXI_OKAY;
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RDATA  <= reg_data_out;
                S_AXI_RRESP  <= reg_read_resp;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end


    // AXPROT is accepted but unused; this peripheral has no privilege filtering.
    initial begin
        if (C_S_AXI_DATA_WIDTH != 32 || C_S_AXI_ADDR_WIDTH < 6)
            $fatal(1, "AXI registers require 32-bit data and at least 6 address bits");
    end
endmodule
