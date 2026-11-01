`timescale 1ns/1ps

// Exercise the real TX/channel/RX through AXI, including independent channels,
// byte strobes, backpressure, removed registers and coherent snapshot timing.
module tb_top_wrapper;
`ifdef EQ_AXI_ADDR12
    parameter integer ADDR_WIDTH = 12;
`else
    parameter integer ADDR_WIDTH = 8;
`endif
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg [ADDR_WIDTH-1:0] awaddr = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    integer snapshots = 0;
    always @(posedge clk) if (rstn && dut.cfg_snapshot_trig) snapshots = snapshots + 1;

    top_wrapper #(.C_S_AXI_ADDR_WIDTH(ADDR_WIDTH)) dut (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );

    task automatic address(input integer addr);
        begin
            @(negedge clk); awaddr = addr; awvalid = 1;
            do @(posedge clk); while (!awready);
            @(negedge clk); awvalid = 0;
        end
    endtask
    task automatic data(input reg [31:0] value, input reg [3:0] strobes);
        begin
            @(negedge clk); wdata = value; wstrb = strobes; wvalid = 1;
            do @(posedge clk); while (!wready);
            @(negedge clk); wvalid = 0;
        end
    endtask
    task automatic write_reg(input integer addr, input reg [31:0] value,
                             input reg [3:0] strobes, input integer order,
                             input reg [1:0] response);
        begin
            if (order == 0) begin address(addr); repeat (2) @(negedge clk); data(value, strobes); end
            else if (order == 1) begin data(value, strobes); repeat (2) @(negedge clk); address(addr); end
            else fork address(addr); data(value, strobes); join
            wait (bvalid);
            repeat (3) begin
                @(negedge clk);
                if (!bvalid || bresp !== response) $fatal(1, "Write response/stability at %h", addr);
            end
            bready = 1;
            @(posedge clk); @(negedge clk); bready = 0;
        end
    endtask
    task automatic read_reg(input integer addr, input reg [1:0] response, output reg [31:0] value);
        begin
            @(negedge clk); araddr = addr; arvalid = 1;
            do @(posedge clk); while (!arready);
            @(negedge clk); arvalid = 0;
            wait (rvalid); value = rdata;
            repeat (3) begin
                @(negedge clk);
                if (!rvalid || rdata !== value || rresp !== response)
                    $fatal(1, "Read response/stability at %h", addr);
            end
            rready = 1;
            @(posedge clk); @(negedge clk); rready = 0;
        end
    endtask
    task automatic expect_reg(input integer addr, input reg [31:0] expected);
        reg [31:0] value;
        begin
            read_reg(addr, 0, value);
            if (value !== expected) $fatal(1, "Read %h: got %h expected %h", addr, value, expected);
        end
    endtask

    integer i, pulse_count;
    reg [31:0] value, saved_total, saved_errors;
    reg [15:0] expected_noise = 0;
    reg [31:0] random_value;
    reg [3:0] strobes;
    initial begin
        repeat (5) @(negedge clk); rstn = 1;
        expect_reg('h00, 0);
        expect_reg('h08, 0);
        expect_reg('h0c, 4096);
        expect_reg('h1c, 2048);
        expect_reg('h24, 33);
        expect_reg('h20, 0);
        expect_reg('h28, 0);

        // Partial writes, signed encoding and no-op WSTRB.
        write_reg('h0c, 'hdeadbeef, 4'b0001, 0, 0);
        expect_reg('h0c, 'h10ef);
        write_reg('h0c, 'h1234ff00, 4'b0010, 1, 0);
        expect_reg('h0c, 'hffef);
        if (dut.core.i_cfg_ffe_w0 !== 16'hffef) $fatal(1, "Signed coefficient wiring");
        write_reg('h0c, 0, 0, 2, 0);
        expect_reg('h0c, 'hffef);
        write_reg('h0c, 4096, 15, 2, 0);
        for (i = 0; i < 100; i = i + 1) begin
            random_value = $random; strobes = $random;
            if (strobes[0]) expected_noise[7:0] = random_value[7:0];
            if (strobes[1]) expected_noise[15:8] = random_value[15:8];
            write_reg('h08, random_value, strobes, i % 3, 0);
            expect_reg('h08, {16'b0, expected_noise});
            if (dut.core.i_cfg_snr_db !== expected_noise) $fatal(1, "Noise gain wiring");
        end
        write_reg('h00, 'hffffffff, 15, 0, 0);
        expect_reg('h00, 'h7f);
        if ({dut.core.i_cfg_isi_en, dut.core.i_cfg_tx_en, dut.core.i_cfg_dfe_en,
             dut.core.i_cfg_ffe_en, dut.core.i_cfg_mon_en, dut.core.i_cfg_lms_en,
             dut.core.i_cfg_awgn_en} !== 7'h7f) $fatal(1, "Enable wiring");
        write_reg('h1c, 'hf800, 15, 0, 0);
        write_reg('h24, 41, 15, 1, 0);
        if (dut.core.i_cfg_isi_coeff !== 16'hf800 || dut.core.i_cfg_learning_rate !== 16'd41)
            $fatal(1, "ISI / learning rate wiring");
        write_reg('h10, 17, 15, 0, 0);
        write_reg('h14, 23, 15, 1, 0);
        write_reg('h18, 31, 15, 2, 0);
        if (dut.core.i_cfg_ffe_w1 !== 16'd17 || dut.core.i_cfg_ffe_w2 !== 16'd23 ||
            dut.core.i_cfg_dfe_b0 !== 16'd31) $fatal(1, "Coefficient wiring");

        // Invalid/removed register access and counter write protection.
        read_reg('h30, 2, value);
        if (value !== 0) $fatal(1, "Removed register read must return zero");
        read_reg('h01, 2, value);
        write_reg('h20, 123, 15, 0, 2);
        write_reg('h28, 123, 15, 1, 2);
        write_reg('h34, 123, 15, 2, 2);
        if (ADDR_WIDTH >= 12) begin
            read_reg('h100, 2, value);
            write_reg('h100, 123, 15, 0, 2);
        end

        // Monitor bypass path, snapshot while running, and stable software reads.
        write_reg('h00, 'h20, 15, 0, 0); // TX only; monitor reset.
        write_reg('h00, 'h24, 15, 1, 0); // TX + monitor, FFE/DFE/ISI/noise disabled.
        repeat (200) @(negedge clk);
        write_reg('h04, 1, 1, 2, 0);
        read_reg('h28, 0, saved_total);
        read_reg('h20, 0, saved_errors);
        if (saved_total < 150) $fatal(1, "Actual DUT monitor did not count symbols: %d", saved_total);
        if (saved_errors > saved_total * 2) $fatal(1, "Counter units invalid");
        repeat (50) @(negedge clk);
        expect_reg('h28, saved_total);
        expect_reg('h20, saved_errors);
        pulse_count = snapshots;
        write_reg('h04, 1, 0, 0, 0);
        write_reg('h04, 1, 4'b0010, 1, 0);
        write_reg('h04, 'h1e, 1, 2, 0); // Removed command bits must not trigger snapshot.
        if (snapshots != pulse_count) $fatal(1, "Unsupported/no-strobe command pulse");
        expect_reg('h04, 0);
        write_reg('h04, 1, 1, 0, 0);
        if (snapshots != pulse_count + 1) $fatal(1, "Snapshot must pulse once under B backpressure");
        read_reg('h28, 0, value);
        if (value <= saved_total) $fatal(1, "Snapshot was not refreshed");
        write_reg('h00, 'h20, 15, 0, 0); // Disable monitor clears live counts.
        expect_reg('h28, value); // Existing snapshot survives monitor disable.
        write_reg('h04, 1, 1, 1, 0);
        expect_reg('h28, 0);
        expect_reg('h20, 0);

        // Reset flushes a half-completed AXI write and restores idle config.
        address('h00);
        @(negedge clk); rstn = 0;
        repeat (4) @(negedge clk); rstn = 1;
        expect_reg('h00, 0);
        expect_reg('h28, 0);
        write_reg('h08, 4096, 15, 2, 0);
        expect_reg('h08, 4096);
        $display("PASS: real top_wrapper AXI integration, address width %0d", ADDR_WIDTH);
        $finish;
    end
    initial begin #1000000; $fatal(1, "AXI test timeout"); end
endmodule
