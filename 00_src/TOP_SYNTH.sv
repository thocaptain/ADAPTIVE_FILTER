//------------------------------------------------------------------------------
// TOP_SYNTH.sv - Arty A7-35T : Adaptive FFE-DFE Equalizer + Channel + BERT
//------------------------------------------------------------------------------
// - 100 MHz clock; reset (ck_rst, active-low) is synchronized
// - Buttons are synchronized and debounced, switches are 2-FF synchronized
//
//   sw[0]    : severe ISI/noise in channel model
//   sw[1]    : LMS adaptation enable
//   sw[3:2]  : reserved
//   btn[0]   : clear BERT counters
//   btn[3:1] : reserved
//
//   led[0]   : BERT lock
//   led[1]   : error detected (err_cnt != 0)
//   led[2]   : severe mode
//   led[3]   : adapt mode
//   RGB LD0  : green = locked & no error, red = locked & error, blue = no lock
//   RGB LD1..3, UART, Pmod JA..JD : reserved
//------------------------------------------------------------------------------
/* verilator lint_off UNUSEDSIGNAL */
module TOP_SYNTH
  import eq_pkg::*;
(
  // Clock & reset
  input  logic        CLK100MHZ,
  input  logic        ck_rst,        // RESET button (active-low)

  // Switches / buttons
  input  logic [3:0]  sw,
  input  logic [3:0]  btn,

  // LEDs
  output logic [3:0]  led,           // Standard LEDs LD4..LD7
  output logic [3:0]  led_r,         // RGB LEDs 0..3 - red channel
  output logic [3:0]  led_g,         // RGB LEDs 0..3 - green channel
  output logic [3:0]  led_b,         // RGB LEDs 0..3 - blue channel

  // UART (through FTDI, FPGA side)
  input  logic        uart_txd_in,   // PC -> FPGA
  output logic        uart_rxd_out,  // FPGA -> PC

  // Pmod
  inout  wire  [7:0]  ja,
  inout  wire  [7:0]  jb,
  inout  wire  [7:0]  jc,
  inout  wire  [7:0]  jd
);

  //--------------------------------------------------------------------------
  // Parameters
  //--------------------------------------------------------------------------
  localparam int CLK_FREQ_HZ  = 100_000_000;
  localparam int DEBOUNCE_MS  = 10;
  localparam int DEBOUNCE_CNT = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
  localparam int DB_W         = $clog2(DEBOUNCE_CNT + 1);

  //--------------------------------------------------------------------------
  // Reset: synchronized, active-high internally
  //--------------------------------------------------------------------------
  logic [2:0] rst_sync;
  logic       rst;

  always_ff @(posedge CLK100MHZ or negedge ck_rst) begin
    if (!ck_rst) rst_sync <= 3'b111;
    else         rst_sync <= {rst_sync[1:0], 1'b0};
  end
  assign rst = rst_sync[2];

  //--------------------------------------------------------------------------
  // Switches: 2-FF synchronizer
  //--------------------------------------------------------------------------
  logic [3:0] sw_meta, sw_sync;

  always_ff @(posedge CLK100MHZ) begin
    sw_meta <= sw;
    sw_sync <= sw_meta;
  end

  //--------------------------------------------------------------------------
  // Buttons: synchronizer + debounce
  //--------------------------------------------------------------------------
  logic [3:0]      btn_meta, btn_sync, btn_clean;
  logic [DB_W-1:0] db_cnt [4];

  always_ff @(posedge CLK100MHZ) begin
    btn_meta <= btn;
    btn_sync <= btn_meta;
  end

  for (genvar i = 0; i < 4; i++) begin : g_debounce
    always_ff @(posedge CLK100MHZ) begin
      if (rst) begin
        db_cnt[i]    <= '0;
        btn_clean[i] <= 1'b0;
      end else if (btn_sync[i] == btn_clean[i]) begin
        db_cnt[i] <= '0;
      end else if (db_cnt[i] == DB_W'(DEBOUNCE_CNT)) begin
        db_cnt[i]    <= '0;
        btn_clean[i] <= btn_sync[i];
      end else begin
        db_cnt[i] <= db_cnt[i] + DB_W'(1);
      end
    end
  end

  //--------------------------------------------------------------------------
  // Equalizer system
  //--------------------------------------------------------------------------
  logic             lock;
  logic [CNT_W-1:0] bit_cnt;
  logic [CNT_W-1:0] err_cnt;
  logic             has_err;

  eq_top u_eq_top (
    .i_clk     (CLK100MHZ   ),
    .i_rst_n   (~rst        ),
    .i_en      (1'b1        ),
    .i_severe  (sw_sync[0]  ),
    .i_adapt   (sw_sync[1]  ),
    .i_clr     (btn_clean[0]),
    .o_lock    (lock        ),
    .o_bit_cnt (bit_cnt     ),
    .o_err_cnt (err_cnt     )
  );

  assign has_err = |err_cnt;

  //--------------------------------------------------------------------------
  // LEDs
  //--------------------------------------------------------------------------
  assign led[0] = lock;
  assign led[1] = has_err;
  assign led[2] = sw_sync[0];
  assign led[3] = sw_sync[1];

  assign led_r = {3'b000, lock &  has_err};
  assign led_g = {3'b000, lock & ~has_err};
  assign led_b = {3'b000, ~lock};

  //--------------------------------------------------------------------------
  // UART (reserved for BER report) - idle high
  //--------------------------------------------------------------------------
  assign uart_rxd_out = 1'b1;

  //--------------------------------------------------------------------------
  // Pmod (reserved) - high-Z
  //--------------------------------------------------------------------------
  assign ja = 'z;
  assign jb = 'z;
  assign jc = 'z;
  assign jd = 'z;

endmodule
