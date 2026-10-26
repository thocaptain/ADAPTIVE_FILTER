`timescale 1ns/1ps

module Top_wrapper
#(
    parameter integer               C_S_AXI_DATA_WIDTH  = 32,
    parameter integer               C_S_AXI_ADDR_WIDTH  = 8,
    parameter integer               NUMBER_SYMBOL       = 1,               // [1, 2^31-1] symbols/clock
    parameter logic          [6:0]  PRBS_SEED           = 7'h7f,           // U7 [1, 127]
    parameter logic   signed [15:0] CHANNEL_H1_Q12      = 16'sd2048,       // Q4.12 [-8, 8-2^-12]
    parameter logic          [31:0] NOISE_SEED          = 32'h00000a5b,    // U32 [0, 2^32-1]
    parameter logic          [7:0]  DEFAULT_SNR_DB      = 8'd20,            // U8 [0, 255] dB
    parameter integer               TRAIN_LEN           = 3000,            // Integer [0, 2^31-1]
    parameter logic   signed [39:0] MU_F20              = 40'sd524,        // Q20.20 [-2^19, 2^19-2^-20]
    parameter integer               TX_LATENCY          = 1,               // [0, 2^31-1] clocks
    parameter integer               CHANNEL_LATENCY     = 1,               // [0, 2^31-1] clocks
    parameter integer               FFE_LATENCY         = 0,               // [0, 2^31-1] clocks
    parameter integer               DFE_LATENCY         = 0,               // [0, 2^31-1] clocks
    parameter integer               SLICER_LATENCY      = 1,               // [0, 2^31-1] clocks
    parameter integer               FFE_SYMBOL_DELAY    = 1,               // [0, 2^31-1] symbols
    parameter integer               BER_COUNTER_WIDTH   = 64,              // [2, 64]
    parameter bit                   BER_SKIP_TRAINING   = 1'b1,            // {0, 1}
    parameter integer               RX_STARTUP_CYCLES   = TX_LATENCY + CHANNEL_LATENCY,
    parameter integer               TX_REF_DELAY_CYCLES = CHANNEL_LATENCY + FFE_LATENCY + DFE_LATENCY
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
);

    logic               noise_en;
    logic               adapt_en;
    logic               ber_en;
    logic               ffe_bypass;
    logic               dfe_bypass;
    logic        [7:0]  cfg_snr_db; // U8 [0, 255] dB
    logic signed [15:0] cfg_ffe0;   // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] cfg_ffe1;   // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] cfg_ffe2;   // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] cfg_dfe0;   // Q4.12 [-8, 8-2^-12]
    logic               cfg_load;
    logic               cfg_noise_load;
    logic               ber_clear;
    logic               core_reset;
    logic               core_rst_n;
    logic               ber_ready;
    logic        [31:0] ber_latency;
    logic [BER_COUNTER_WIDTH-1:0] ber_error_bits;
    logic [BER_COUNTER_WIDTH-1:0] ber_total_bits;
    logic signed [15:0] ffe0;
    logic signed [15:0] ffe1;
    logic signed [15:0] ffe2;
    logic signed [15:0] dfe0;
    logic signed [NUMBER_SYMBOL-1:0][3:0]  tx_sym;
    logic        [NUMBER_SYMBOL-1:0][1:0]  tx_bits;
    logic signed [NUMBER_SYMBOL-1:0][7:0]  channel_r;
    logic signed [NUMBER_SYMBOL-1:0][3:0]  rx_sym;
    logic        [NUMBER_SYMBOL-1:0][1:0]  rx_bits;
    logic signed [NUMBER_SYMBOL-1:0][15:0] rx_y;

    assign core_rst_n = S_AXI_ARESETN && !core_reset;

    adaptive_eq_axi_regs #(
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
        .NUMBER_SYMBOL      (NUMBER_SYMBOL     ),
        .BER_COUNTER_WIDTH  (BER_COUNTER_WIDTH ),
        .DEFAULT_SNR_DB     (DEFAULT_SNR_DB    )
    ) axi_regs (
        .S_AXI_ACLK       (S_AXI_ACLK    ),
        .S_AXI_ARESETN    (S_AXI_ARESETN ),
        .S_AXI_AWADDR     (S_AXI_AWADDR  ),
        .S_AXI_AWPROT     (S_AXI_AWPROT  ),
        .S_AXI_AWVALID    (S_AXI_AWVALID ),
        .S_AXI_AWREADY    (S_AXI_AWREADY ),
        .S_AXI_WDATA      (S_AXI_WDATA   ),
        .S_AXI_WSTRB      (S_AXI_WSTRB   ),
        .S_AXI_WVALID     (S_AXI_WVALID  ),
        .S_AXI_WREADY     (S_AXI_WREADY  ),
        .S_AXI_BRESP      (S_AXI_BRESP   ),
        .S_AXI_BVALID     (S_AXI_BVALID  ),
        .S_AXI_BREADY     (S_AXI_BREADY  ),
        .S_AXI_ARADDR     (S_AXI_ARADDR  ),
        .S_AXI_ARPROT     (S_AXI_ARPROT  ),
        .S_AXI_ARVALID    (S_AXI_ARVALID ),
        .S_AXI_ARREADY    (S_AXI_ARREADY ),
        .S_AXI_RDATA      (S_AXI_RDATA   ),
        .S_AXI_RRESP      (S_AXI_RRESP   ),
        .S_AXI_RVALID     (S_AXI_RVALID  ),
        .S_AXI_RREADY     (S_AXI_RREADY  ),
        .o_noise_en       (noise_en      ),
        .o_adapt_en       (adapt_en      ),
        .o_ber_en         (ber_en        ),
        .o_ffe_bypass     (ffe_bypass    ),
        .o_dfe_bypass     (dfe_bypass    ),
        .o_cfg_snr_db     (cfg_snr_db    ),
        .o_cfg_ffe0       (cfg_ffe0      ),
        .o_cfg_ffe1       (cfg_ffe1      ),
        .o_cfg_ffe2       (cfg_ffe2      ),
        .o_cfg_dfe0       (cfg_dfe0      ),
        .o_cfg_load       (cfg_load      ),
        .o_cfg_noise_load (cfg_noise_load),
        .o_ber_clear      (ber_clear     ),
        .o_core_reset     (core_reset    ),
        .i_ber_ready      (ber_ready     ),
        .i_ber_latency    (ber_latency   ),
        .i_ber_error_bits (ber_error_bits),
        .i_ber_total_bits (ber_total_bits),
        .i_ffe0           (ffe0          ),
        .i_ffe1           (ffe1          ),
        .i_ffe2           (ffe2          ),
        .i_dfe0           (dfe0          ),
        .i_tx_sym         (tx_sym        ),
        .i_tx_bits        (tx_bits       ),
        .i_channel_r      (channel_r     ),
        .i_rx_sym         (rx_sym        ),
        .i_rx_bits        (rx_bits       ),
        .i_rx_y           (rx_y          )
    );

    Top #(
        .NUMBER_SYMBOL       (NUMBER_SYMBOL      ),
        .PRBS_SEED           (PRBS_SEED          ),
        .CHANNEL_H1_Q12      (CHANNEL_H1_Q12     ),
        .NOISE_SEED          (NOISE_SEED         ),
        .DEFAULT_SNR_DB      (DEFAULT_SNR_DB     ),
        .TRAIN_LEN           (TRAIN_LEN          ),
        .MU_F20              (MU_F20             ),
        .TX_LATENCY          (TX_LATENCY         ),
        .CHANNEL_LATENCY     (CHANNEL_LATENCY    ),
        .FFE_LATENCY         (FFE_LATENCY        ),
        .DFE_LATENCY         (DFE_LATENCY        ),
        .SLICER_LATENCY      (SLICER_LATENCY     ),
        .FFE_SYMBOL_DELAY    (FFE_SYMBOL_DELAY   ),
        .BER_COUNTER_WIDTH   (BER_COUNTER_WIDTH  ),
        .BER_SKIP_TRAINING   (BER_SKIP_TRAINING  ),
        .RX_STARTUP_CYCLES   (RX_STARTUP_CYCLES  ),
        .TX_REF_DELAY_CYCLES (TX_REF_DELAY_CYCLES)
    ) core (
        .i_clk            (S_AXI_ACLK    ),
        .i_rst_n          (core_rst_n    ),
        .i_noise_en       (noise_en      ),
        .i_adapt_en       (adapt_en      ),
        .i_ber_en         (ber_en        ),
        .i_ffe_bypass     (ffe_bypass    ),
        .i_dfe_bypass     (dfe_bypass    ),
        .i_cfg_snr_db     (cfg_snr_db    ),
        .i_cfg_ffe0       (cfg_ffe0      ),
        .i_cfg_ffe1       (cfg_ffe1      ),
        .i_cfg_ffe2       (cfg_ffe2      ),
        .i_cfg_dfe0       (cfg_dfe0      ),
        .i_cfg_load       (cfg_load      ),
        .i_cfg_noise_load (cfg_noise_load),
        .i_ber_clear      (ber_clear     ),
        .o_ber_ready      (ber_ready     ),
        .o_ber_latency    (ber_latency   ),
        .o_ber_error_bits (ber_error_bits),
        .o_ber_total_bits (ber_total_bits),
        .o_ffe0           (ffe0          ),
        .o_ffe1           (ffe1          ),
        .o_ffe2           (ffe2          ),
        .o_dfe0           (dfe0          ),
        .o_tx_sym         (tx_sym        ),
        .o_tx_bits        (tx_bits       ),
        .o_channel_r      (channel_r     ),
        .o_rx_sym         (rx_sym        ),
        .o_rx_bits        (rx_bits       ),
        .o_rx_y           (rx_y          )
    );

endmodule
