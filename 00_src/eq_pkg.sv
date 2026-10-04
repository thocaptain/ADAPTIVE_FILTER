package eq_pkg;

  localparam int DW         = 12;  // sample width (signed fixed-point)
  localparam int CW         = 12;  // coefficient width (signed fixed-point)
  localparam int PRBS_ORDER = 7;   // PRBS7 / PRBS15 / PRBS31
  localparam int CH_TAPS    = 5;   // channel FIR taps
  localparam int FFE_TAPS   = 5;   // FFE taps (precursor)
  localparam int DFE_TAPS   = 3;   // DFE taps (postcursor)
  localparam int CNT_W      = 48;  // BERT counter width

endpackage
