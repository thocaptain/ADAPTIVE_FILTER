`timescale 1ns/1ps

module adaptive_eq_axi_regs
#(
    parameter integer     C_S_AXI_DATA_WIDTH = 32,
    parameter integer     C_S_AXI_ADDR_WIDTH = 8,
    parameter integer     NUMBER_SYMBOL      = 1,
    parameter integer     BER_COUNTER_WIDTH  = 64,
    parameter logic [7:0] DEFAULT_SNR_DB     = 8'd20
)
(
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

    , output logic               o_noise_en
    , output logic               o_adapt_en
    , output logic               o_ber_en
    , output logic               o_ffe_bypass
    , output logic               o_dfe_bypass
    , output logic        [7:0]  o_cfg_snr_db       // U8 [0, 255] dB
    , output logic signed [15:0] o_cfg_ffe0         // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_cfg_ffe1         // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_cfg_ffe2         // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_cfg_dfe0         // Q4.12 [-8, 8-2^-12]
    , output logic               o_cfg_load
    , output logic               o_cfg_noise_load
    , output logic               o_ber_clear
    , output logic               o_core_reset

    , input  logic               i_ber_ready
    , input  logic        [31:0] i_ber_latency
    , input  logic [BER_COUNTER_WIDTH-1:0] i_ber_error_bits
    , input  logic [BER_COUNTER_WIDTH-1:0] i_ber_total_bits
    , input  logic signed [15:0] i_ffe0
    , input  logic signed [15:0] i_ffe1
    , input  logic signed [15:0] i_ffe2
    , input  logic signed [15:0] i_dfe0
    , input  logic signed [NUMBER_SYMBOL-1:0][3:0]  i_tx_sym
    , input  logic        [NUMBER_SYMBOL-1:0][1:0]  i_tx_bits
    , input  logic signed [NUMBER_SYMBOL-1:0][7:0]  i_channel_r
    , input  logic signed [NUMBER_SYMBOL-1:0][3:0]  i_rx_sym
    , input  logic        [NUMBER_SYMBOL-1:0][1:0]  i_rx_bits
    , input  logic signed [NUMBER_SYMBOL-1:0][15:0] i_rx_y
);

    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CONTROL      = C_S_AXI_ADDR_WIDTH'('h00);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_COMMAND      = C_S_AXI_ADDR_WIDTH'('h04);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_SNR_DB       = C_S_AXI_ADDR_WIDTH'('h08);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_FFE0     = C_S_AXI_ADDR_WIDTH'('h0c);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_FFE1     = C_S_AXI_ADDR_WIDTH'('h10);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_FFE2     = C_S_AXI_ADDR_WIDTH'('h14);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CFG_DFE0     = C_S_AXI_ADDR_WIDTH'('h18);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_STATUS       = C_S_AXI_ADDR_WIDTH'('h1c);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_ERROR_LO     = C_S_AXI_ADDR_WIDTH'('h20);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_ERROR_HI     = C_S_AXI_ADDR_WIDTH'('h24);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_TOTAL_LO     = C_S_AXI_ADDR_WIDTH'('h28);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_TOTAL_HI     = C_S_AXI_ADDR_WIDTH'('h2c);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_SNAP_LATENCY = C_S_AXI_ADDR_WIDTH'('h30);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_FFE0         = C_S_AXI_ADDR_WIDTH'('h34);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_FFE1         = C_S_AXI_ADDR_WIDTH'('h38);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_FFE2         = C_S_AXI_ADDR_WIDTH'('h3c);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_DFE0         = C_S_AXI_ADDR_WIDTH'('h40);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_TX_SYM       = C_S_AXI_ADDR_WIDTH'('h44);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_TX_BITS      = C_S_AXI_ADDR_WIDTH'('h48);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_CHANNEL_R    = C_S_AXI_ADDR_WIDTH'('h4c);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_RX_SYM       = C_S_AXI_ADDR_WIDTH'('h50);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_RX_BITS      = C_S_AXI_ADDR_WIDTH'('h54);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_RX_Y         = C_S_AXI_ADDR_WIDTH'('h58);
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] REG_LIVE_LATENCY = C_S_AXI_ADDR_WIDTH'('h5c);
    localparam logic [1:0]                    AXI_OKAY         = 2'b00;
    localparam logic [1:0]                    AXI_SLVERR       = 2'b10;

    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    logic [31:0] axi_wdata;
    logic [3:0]  axi_wstrb;
    logic        axi_aw_pending;
    logic        axi_w_pending;
    logic        slv_reg_wren;
    logic [31:0] write_mask;
    logic [31:0] reg_data_out;
    logic [1:0]  reg_read_resp;
    logic [1:0]  reg_write_resp;

    logic [31:0] control_q;
    logic [7:0]  snr_db_q;
    logic signed [15:0] cfg_ffe0_q;
    logic signed [15:0] cfg_ffe1_q;
    logic signed [15:0] cfg_ffe2_q;
    logic signed [15:0] cfg_dfe0_q;
    logic [63:0] snapshot_errors;
    logic [63:0] snapshot_total;
    logic [31:0] snapshot_latency;
    logic        snapshot_valid;

    assign o_noise_en   = control_q[0];
    assign o_adapt_en   = control_q[1];
    assign o_ber_en     = control_q[2];
    assign o_ffe_bypass = control_q[3];
    assign o_dfe_bypass = control_q[4];
    assign o_cfg_snr_db = snr_db_q;
    assign o_cfg_ffe0   = cfg_ffe0_q;
    assign o_cfg_ffe1   = cfg_ffe1_q;
    assign o_cfg_ffe2   = cfg_ffe2_q;
    assign o_cfg_dfe0   = cfg_dfe0_q;

    // One outstanding write; address and data may arrive in either order.
    assign S_AXI_AWREADY = S_AXI_ARESETN && !axi_aw_pending && !S_AXI_BVALID;
    assign S_AXI_WREADY  = S_AXI_ARESETN && !axi_w_pending  && !S_AXI_BVALID;
    assign slv_reg_wren  = axi_aw_pending && axi_w_pending && !S_AXI_BVALID;
    assign write_mask    = {{8{axi_wstrb[3]}}, {8{axi_wstrb[2]}},
                            {8{axi_wstrb[1]}}, {8{axi_wstrb[0]}}};

    always_comb begin
        reg_write_resp = AXI_OKAY;
        case (axi_awaddr)
            REG_CONTROL, REG_COMMAND, REG_SNR_DB,
            REG_CFG_FFE0, REG_CFG_FFE1, REG_CFG_FFE2, REG_CFG_DFE0: ;
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

    // Shadow registers and write-one command pulses.
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            control_q        <= '0;
            snr_db_q         <= DEFAULT_SNR_DB;
            cfg_ffe0_q       <= 16'sd0;
            cfg_ffe1_q       <= 16'sd3072;
            cfg_ffe2_q       <= 16'sd0;
            cfg_dfe0_q       <= 16'sd0;
            o_cfg_load       <= 1'b0;
            o_cfg_noise_load <= 1'b0;
            o_ber_clear      <= 1'b0;
            o_core_reset     <= 1'b0;
            snapshot_errors  <= '0;
            snapshot_total   <= '0;
            snapshot_latency <= '0;
            snapshot_valid   <= 1'b0;
        end else begin
            o_cfg_load       <= 1'b0;
            o_cfg_noise_load <= 1'b0;
            o_ber_clear      <= 1'b0;
            o_core_reset     <= 1'b0;
            if (slv_reg_wren && reg_write_resp == AXI_OKAY) begin
                case (axi_awaddr)
                    REG_CONTROL: control_q <= ((control_q & ~write_mask)
                                            | (axi_wdata & write_mask)) & 32'h0000001f;
                    REG_COMMAND: if (axi_wstrb[0]) begin
                        o_cfg_load       <= axi_wdata[0];
                        o_cfg_noise_load <= axi_wdata[1];
                        o_ber_clear      <= axi_wdata[2];
                        o_core_reset     <= axi_wdata[4];
                        if (axi_wdata[4]) begin
                            snapshot_valid <= 1'b0;
                        end else if (axi_wdata[3]) begin
                            snapshot_errors  <= 64'(i_ber_error_bits);
                            snapshot_total   <= 64'(i_ber_total_bits);
                            snapshot_latency <= i_ber_latency;
                            snapshot_valid   <= 1'b1;
                        end
                    end
                    REG_SNR_DB: if (axi_wstrb[0]) snr_db_q <= axi_wdata[7:0];
                    REG_CFG_FFE0: begin
                        if (axi_wstrb[0]) cfg_ffe0_q[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) cfg_ffe0_q[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_FFE1: begin
                        if (axi_wstrb[0]) cfg_ffe1_q[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) cfg_ffe1_q[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_FFE2: begin
                        if (axi_wstrb[0]) cfg_ffe2_q[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) cfg_ffe2_q[15:8] <= axi_wdata[15:8];
                    end
                    REG_CFG_DFE0: begin
                        if (axi_wstrb[0]) cfg_dfe0_q[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) cfg_dfe0_q[15:8] <= axi_wdata[15:8];
                    end
                    default: ;
                endcase
            end
        end
    end

    // Read response/data remain stable until the CPU accepts them.
    assign S_AXI_ARREADY = S_AXI_ARESETN && !S_AXI_RVALID;

    always_comb begin
        reg_data_out = '0;
        reg_read_resp = AXI_OKAY;
        case (S_AXI_ARADDR)
            REG_CONTROL:      reg_data_out = control_q;
            REG_COMMAND:      reg_data_out = '0;
            REG_SNR_DB:       reg_data_out = {24'd0, snr_db_q};
            REG_CFG_FFE0:     reg_data_out = {16'd0, cfg_ffe0_q};
            REG_CFG_FFE1:     reg_data_out = {16'd0, cfg_ffe1_q};
            REG_CFG_FFE2:     reg_data_out = {16'd0, cfg_ffe2_q};
            REG_CFG_DFE0:     reg_data_out = {16'd0, cfg_dfe0_q};
            REG_STATUS:       reg_data_out = {30'd0, snapshot_valid, i_ber_ready};
            REG_ERROR_LO:     reg_data_out = snapshot_errors[31:0];
            REG_ERROR_HI:     reg_data_out = snapshot_errors[63:32];
            REG_TOTAL_LO:     reg_data_out = snapshot_total[31:0];
            REG_TOTAL_HI:     reg_data_out = snapshot_total[63:32];
            REG_SNAP_LATENCY: reg_data_out = snapshot_latency;
            REG_FFE0:         reg_data_out = {{16{i_ffe0[15]}}, i_ffe0};
            REG_FFE1:         reg_data_out = {{16{i_ffe1[15]}}, i_ffe1};
            REG_FFE2:         reg_data_out = {{16{i_ffe2[15]}}, i_ffe2};
            REG_DFE0:         reg_data_out = {{16{i_dfe0[15]}}, i_dfe0};
            REG_TX_SYM:       reg_data_out = {{28{i_tx_sym[0][3]}}, i_tx_sym[0]};
            REG_TX_BITS:      reg_data_out = {30'd0, i_tx_bits[0]};
            REG_CHANNEL_R:    reg_data_out = {{24{i_channel_r[0][7]}}, i_channel_r[0]};
            REG_RX_SYM:       reg_data_out = {{28{i_rx_sym[0][3]}}, i_rx_sym[0]};
            REG_RX_BITS:      reg_data_out = {30'd0, i_rx_bits[0]};
            REG_RX_Y:         reg_data_out = {{16{i_rx_y[0][15]}}, i_rx_y[0]};
            REG_LIVE_LATENCY: reg_data_out = i_ber_latency;
            default:         reg_read_resp = AXI_SLVERR;
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

    initial begin
        if (C_S_AXI_DATA_WIDTH != 32 || C_S_AXI_ADDR_WIDTH < 7)
            $fatal(1, "AXI registers require 32-bit data and at least 7 address bits");
        if (NUMBER_SYMBOL != 1 || BER_COUNTER_WIDTH < 2 || BER_COUNTER_WIDTH > 64)
            $fatal(1, "AXI registers require one symbol/clock and BER width 2..64");
    end

endmodule
