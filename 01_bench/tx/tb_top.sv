`timescale 1ns/1ps

module tb_top
#(
    parameter integer     NUMBER_SYMBOL = 1,
    parameter logic [6:0] PRBS_SEED     = 7'h7f
)
(
      input  logic               i_clk
    , input  logic               i_rst_n

    , output logic signed [NUMBER_SYMBOL-1:0][3:0] o_sym      // Q4.0 {-3, -1, +1, +3}
    , output logic [NUMBER_SYMBOL-1:0][1:0]        o_bits_ref // U2 {00, 01, 11, 10}
);

    tx_top #(
        .NUMBER_SYMBOL (NUMBER_SYMBOL),
        .PRBS_SEED     (PRBS_SEED    )
    ) dut (
        .i_clk      (i_clk     ),
        .i_rst_n    (i_rst_n   ),
        .o_sym      (o_sym     ),
        .o_bits_ref (o_bits_ref)
    );

endmodule
