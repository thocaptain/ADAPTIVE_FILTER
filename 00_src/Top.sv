`timescale 1ns/1ps

module Top
#(
    parameter integer               SYMBOLS_PER_CYCLE   = 1,               // [1, 2^31-1] symbols/clock
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
      input  logic               i_clk                  // {0, 1}
    , input  logic               i_rst_n                // {0, 1}

    , input  logic               i_noise_en             // {0, 1}
    , input  logic        [7:0]  i_cfg_snr_db           // U8 [0, 255] dB
    , input  logic               i_cfg_noise_load       // {0, 1}

    , input  logic signed [15:0] i_cfg_ffe0             // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0] i_cfg_ffe1             // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0] i_cfg_ffe2             // Q4.12 [-8, 8-2^-12]
    , input  logic signed [15:0] i_cfg_dfe0             // Q4.12 [-8, 8-2^-12]
    , input  logic               i_cfg_load             // {0, 1}
    , input  logic               i_adapt_en             // {0, 1}
    , input  logic               i_ffe_bypass           // {0, 1}
    , input  logic               i_dfe_bypass           // {0, 1}

    , input  logic               i_ber_en               // {0, 1}
    , input  logic               i_ber_clear            // {0, 1}

    , output logic signed [4*SYMBOLS_PER_CYCLE-1:0]  o_tx_sym    // Q4.0 {-3, -1, +1, +3}
    , output logic        [2*SYMBOLS_PER_CYCLE-1:0]  o_tx_bits   // U2 {00, 01, 11, 10}
    , output logic signed [8*SYMBOLS_PER_CYCLE-1:0]  o_channel_r // Q4.4 [-8, 7.9375]

    , output logic signed [4*SYMBOLS_PER_CYCLE-1:0]  o_rx_sym    // Q4.0 {-3, -1, +1, +3}
    , output logic        [2*SYMBOLS_PER_CYCLE-1:0]  o_rx_bits   // U2 {00, 01, 11, 10}
    , output logic signed [16*SYMBOLS_PER_CYCLE-1:0] o_rx_y      // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_ffe0                 // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_ffe1                 // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_ffe2                 // Q4.12 [-8, 8-2^-12]
    , output logic signed [15:0] o_dfe0                 // Q4.12 [-8, 8-2^-12]

    , output logic [BER_COUNTER_WIDTH-1:0] o_ber_error_bits // [0, 2^BER_COUNTER_WIDTH-1]
    , output logic [BER_COUNTER_WIDTH-1:0] o_ber_total_bits // [0, 2^BER_COUNTER_WIDTH-1]
    , output logic               o_ber_ready            // {0, 1}
    , output logic        [31:0] o_ber_latency          // [0, 2^32-1] clocks
);

    logic signed [4*SYMBOLS_PER_CYCLE-1:0]  TX_sym;      // Q4.0 {-3, -1, +1, +3}
    logic        [2*SYMBOLS_PER_CYCLE-1:0]  TX_bits_ref; // U2 {00, 01, 11, 10}

    logic signed [8*SYMBOLS_PER_CYCLE-1:0]  CH_r;        // Q4.4 [-8, 7.9375]

    logic signed [4*SYMBOLS_PER_CYCLE-1:0]  RX_sym;      // Q4.0 {-3, -1, +1, +3}
    logic        [2*SYMBOLS_PER_CYCLE-1:0]  RX_bits;     // U2 {00, 01, 11, 10}
    logic signed [16*SYMBOLS_PER_CYCLE-1:0] RX_y;        // Q4.12 [-8, 8-2^-12]

    logic signed [15:0] RX_ffe0;     // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] RX_ffe1;     // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] RX_ffe2;     // Q4.12 [-8, 8-2^-12]
    logic signed [15:0] RX_dfe0;     // Q4.12 [-8, 8-2^-12]

    tx_top #(
        .PRBS_SEED (PRBS_SEED)
    ) tx_top (
        .i_clk      (i_clk      ),
        .i_rst_n    (i_rst_n    ),
        .o_sym      (TX_sym     ),
        .o_bits_ref (TX_bits_ref)
    );

    assign o_tx_sym    = TX_sym;
    assign o_tx_bits   = TX_bits_ref;

    channel_top #(
        .H1_Q12         (CHANNEL_H1_Q12),
        .NOISE_SEED     (NOISE_SEED    ),
        .DEFAULT_SNR_DB (DEFAULT_SNR_DB)
    ) channel_top (
        .i_clk            (i_clk           ),
        .i_rst_n          (i_rst_n         ),
        .i_sym            (TX_sym          ),
        .i_noise_en       (i_noise_en      ),
        .i_cfg_snr_db     (i_cfg_snr_db    ),
        .i_cfg_noise_load (i_cfg_noise_load),
        .o_r              (CH_r            )
    );

    assign o_channel_r = CH_r;

    rx_top #(
        .TRAIN_LEN        (TRAIN_LEN          ),
        .STARTUP_CYCLES   (RX_STARTUP_CYCLES  ),
        .REF_DELAY_CYCLES (TX_REF_DELAY_CYCLES),
        .MU_F20           (MU_F20             )
    ) rx_top (
        .i_clk        (i_clk       ),
        .i_rst_n      (i_rst_n     ),
        .i_r          (CH_r        ),
        .i_tx_ref     (TX_sym      ),

        .i_cfg_ffe0   (i_cfg_ffe0  ),
        .i_cfg_ffe1   (i_cfg_ffe1  ),
        .i_cfg_ffe2   (i_cfg_ffe2  ),
        .i_cfg_dfe0   (i_cfg_dfe0  ),
        .i_cfg_load   (i_cfg_load  ),
        .i_adapt_en   (i_adapt_en  ),
        .i_ffe_bypass (i_ffe_bypass),
        .i_dfe_bypass (i_dfe_bypass),

        .o_sym        (RX_sym      ),
        .o_bits       (RX_bits     ),
        .o_y          (RX_y        ),
        .o_ffe0       (RX_ffe0     ),
        .o_ffe1       (RX_ffe1     ),
        .o_ffe2       (RX_ffe2     ),
        .o_dfe0       (RX_dfe0     )
    );

    assign o_rx_sym    = RX_sym;
    assign o_rx_bits   = RX_bits;
    assign o_rx_y      = RX_y;

    assign o_ffe0      = RX_ffe0;
    assign o_ffe1      = RX_ffe1;
    assign o_ffe2      = RX_ffe2;
    assign o_dfe0      = RX_dfe0;

    localparam integer                       BER_RX_LATENCY    = FFE_LATENCY + DFE_LATENCY + SLICER_LATENCY;
    localparam integer                       BER_PATH_LATENCY  = CHANNEL_LATENCY + BER_RX_LATENCY;
    localparam integer                       BER_MAX_DELAY     = BER_PATH_LATENCY + FFE_SYMBOL_DELAY;
    localparam integer                       BER_TRAIN_END     = RX_STARTUP_CYCLES + BER_RX_LATENCY
                                                                 + (BER_SKIP_TRAINING ? TRAIN_LEN : 0);
    localparam integer                       BER_TX_READY      = TX_LATENCY + BER_MAX_DELAY;
    localparam integer                       BER_AGE_MAX       = (BER_TRAIN_END > BER_TX_READY) ? BER_TRAIN_END : BER_TX_READY;
    localparam integer                       BER_AGE_WIDTH     = (BER_AGE_MAX < 1) ? 1 : $clog2(BER_AGE_MAX + 1);
    localparam integer                       BER_DELAY_WIDTH   = (BER_MAX_DELAY < 1) ? 1 : $clog2(BER_MAX_DELAY + 1);
    localparam integer                       BER_SETTLE_CYCLES = (BER_MAX_DELAY < 1) ? 1 : BER_MAX_DELAY;
    localparam integer                       BER_SETTLE_WIDTH  = $clog2(BER_SETTLE_CYCLES + 1);
    localparam logic [BER_COUNTER_WIDTH-1:0] BER_COUNTER_MAX   = {BER_COUNTER_WIDTH{1'b1}};

    logic [1:0] ber_tx_history [0:BER_MAX_DELAY];
    logic [1:0] ber_error_mask;
    logic [1:0] ber_error_increment;
    logic [BER_AGE_WIDTH-1:0] ber_age;
    logic [BER_DELAY_WIDTH-1:0] ber_delay;
    logic [BER_SETTLE_WIDTH-1:0] ber_settle;
    logic ber_ffe_bypass_q;
    logic ber_noise_en_q;
    logic ber_adapt_en_q;
    logic ber_config_change;

    assign ber_tx_history[0] = TX_bits_ref;

    genvar ber_tap;
    generate
        for (ber_tap = 1; ber_tap <= BER_MAX_DELAY; ber_tap = ber_tap + 1) begin : g_ber_tx_delay
            always_ff @(posedge i_clk or negedge i_rst_n) begin
                if (!i_rst_n) ber_tx_history[ber_tap] <= '0;
                else          ber_tx_history[ber_tap] <= ber_tx_history[ber_tap-1];
            end
        end
    endgenerate

    assign ber_delay = BER_DELAY_WIDTH'(BER_PATH_LATENCY
                     + (ber_ffe_bypass_q ? 0 : FFE_SYMBOL_DELAY));
    assign o_ber_latency = 32'(ber_delay);
    assign ber_config_change = i_cfg_load || i_cfg_noise_load
                             || (i_noise_en != ber_noise_en_q)
                             || (i_adapt_en != ber_adapt_en_q);
    assign ber_error_mask = RX_bits ^ ber_tx_history[ber_delay];
    assign ber_error_increment = {1'b0, ber_error_mask[0]} + {1'b0, ber_error_mask[1]};
    assign o_ber_ready = i_rst_n && !i_ber_clear && !ber_config_change
                       && (ber_settle == '0)
                       && (ber_age >= BER_AGE_WIDTH'(BER_TRAIN_END))
                       && (ber_age >= BER_AGE_WIDTH'(TX_LATENCY) + BER_AGE_WIDTH'(ber_delay));

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            ber_age          <= '0;
            ber_settle       <= '0;
            ber_ffe_bypass_q <= 1'b0;
            ber_noise_en_q   <= 1'b0;
            ber_adapt_en_q   <= 1'b0;
            o_ber_error_bits <= '0;
            o_ber_total_bits <= '0;
        end else begin
            if (ber_age < BER_AGE_WIDTH'(BER_AGE_MAX)) ber_age <= ber_age + 1'b1;
            if (i_cfg_load) ber_ffe_bypass_q <= i_ffe_bypass;
            ber_noise_en_q <= i_noise_en;
            ber_adapt_en_q <= i_adapt_en;

            if (ber_config_change) ber_settle <= BER_SETTLE_WIDTH'(BER_SETTLE_CYCLES);
            else if (ber_settle != '0) ber_settle <= ber_settle - 1'b1;

            if (i_ber_clear || ber_config_change) begin
                o_ber_error_bits <= '0;
                o_ber_total_bits <= '0;
            end else if (i_ber_en && o_ber_ready
                         && (o_ber_total_bits <= BER_COUNTER_MAX - BER_COUNTER_WIDTH'(2))) begin
                o_ber_error_bits <= o_ber_error_bits + BER_COUNTER_WIDTH'(ber_error_increment);
                o_ber_total_bits <= o_ber_total_bits + BER_COUNTER_WIDTH'(2);
            end
        end
    end

    initial begin
        if (SYMBOLS_PER_CYCLE != 1)
            $fatal(1, "Only SYMBOLS_PER_CYCLE=1 is implemented; parallel datapath and BER support is required");
        if (TX_LATENCY < 0 || CHANNEL_LATENCY < 0 || FFE_LATENCY < 0 || DFE_LATENCY < 0
            || SLICER_LATENCY < 0 || FFE_SYMBOL_DELAY < 0 || RX_STARTUP_CYCLES < 0
            || TRAIN_LEN < 0 || BER_COUNTER_WIDTH < 2 || BER_COUNTER_WIDTH > 64)
            $fatal(1, "Invalid BER latency, training length or counter width");
    end

endmodule
