// First-postcursor ISI + 12-lane Taus88/CLT approximate AWGN.
// See README.md for the interface, arithmetic, block diagram and timing contract.
`timescale 1ns/1ps
module channel_top #(
    parameter int DATA_WIDTH = 16,
    parameter int DATA_FRAC = 12,
    parameter logic [31:0] NOISE_SEED = 32'h00000a5b
)(
    input logic i_clk, i_rstn, i_valid,
    input logic signed [DATA_WIDTH-1:0] i_tx_data,
    input logic i_cfg_isi_en,
    input logic signed [DATA_WIDTH-1:0] i_cfg_isi_coeff,
    input logic i_cfg_awgn_en,
    // Unsigned integer SNR in dB (0..40), committed by i_cfg_snr_load.
    input logic [15:0] i_cfg_snr_db,
    input logic i_cfg_snr_load,
    output logic [15:0] o_cfg_snr_db,
    output logic signed [15:0] o_cfg_sigma_q12,
    output logic [39:0] o_cfg_signal_power_q24,
    output logic o_valid,
    output logic signed [DATA_WIDTH-1:0] o_channel_data,
    output logic signed [DATA_WIDTH-1:0] o_clean_isi_data,
    output logic signed [DATA_WIDTH-1:0] o_awgn_noise
);
    initial begin
        if (DATA_WIDTH != 16 || DATA_FRAC != 12)
            $fatal(1, "channel_top supports only signed 16-bit Q4.12");
    end
    function automatic logic signed [15:0] sat16(input logic signed [31:0] x);
        if (x > 32767) sat16 = 16'sh7fff;
        else if (x < -32768) sat16 = 16'sh8000;
        else sat16 = x[15:0];
    endfunction
    // SNR conversion: no real arithmetic, logarithm or divider in runtime RTL.
    // LUT is round(2^24 * 10^(-SNR_dB/20)), integer dB 0..40.
    function automatic logic [24:0] attenuation_q24(input logic [15:0] db);
        case (db)
            16'd0: attenuation_q24 = 25'd16777216;
            16'd1: attenuation_q24 = 25'd14952709;
            16'd2: attenuation_q24 = 25'd13326616;
            16'd3: attenuation_q24 = 25'd11877359;
            16'd4: attenuation_q24 = 25'd10585708;
            16'd5: attenuation_q24 = 25'd9434522;
            16'd6: attenuation_q24 = 25'd8408526;
            16'd7: attenuation_q24 = 25'd7494107;
            16'd8: attenuation_q24 = 25'd6679130;
            16'd9: attenuation_q24 = 25'd5952781;
            16'd10: attenuation_q24 = 25'd5305422;
            16'd11: attenuation_q24 = 25'd4728462;
            16'd12: attenuation_q24 = 25'd4214246;
            16'd13: attenuation_q24 = 25'd3755951;
            16'd14: attenuation_q24 = 25'd3347495;
            16'd15: attenuation_q24 = 25'd2983458;
            16'd16: attenuation_q24 = 25'd2659010;
            16'd17: attenuation_q24 = 25'd2369845;
            16'd18: attenuation_q24 = 25'd2112126;
            16'd19: attenuation_q24 = 25'd1882435;
            16'd20: attenuation_q24 = 25'd1677722;
            16'd21: attenuation_q24 = 25'd1495271;
            16'd22: attenuation_q24 = 25'd1332662;
            16'd23: attenuation_q24 = 25'd1187736;
            16'd24: attenuation_q24 = 25'd1058571;
            16'd25: attenuation_q24 = 25'd943452;
            16'd26: attenuation_q24 = 25'd840853;
            16'd27: attenuation_q24 = 25'd749411;
            16'd28: attenuation_q24 = 25'd667913;
            16'd29: attenuation_q24 = 25'd595278;
            16'd30: attenuation_q24 = 25'd530542;
            16'd31: attenuation_q24 = 25'd472846;
            16'd32: attenuation_q24 = 25'd421425;
            16'd33: attenuation_q24 = 25'd375595;
            16'd34: attenuation_q24 = 25'd334749;
            16'd35: attenuation_q24 = 25'd298346;
            16'd36: attenuation_q24 = 25'd265901;
            16'd37: attenuation_q24 = 25'd236984;
            16'd38: attenuation_q24 = 25'd211213;
            16'd39: attenuation_q24 = 25'd188243;
            16'd40: attenuation_q24 = 25'd167772;
            default: attenuation_q24 = 25'd167772;
        endcase
    endfunction
    function automatic logic [19:0] isqrt40(input logic [39:0] value);
        logic [41:0] remainder, trial;
        logic [19:0] root;
        remainder = '0;
        root = '0;
        for (int k=19; k>=0; k--) begin
            remainder = (remainder << 2) | {40'b0, value[2*k +: 2]};
            root = root << 1;
            trial = {21'b0, root, 1'b1};
            if (remainder >= trial) begin
                remainder = remainder - trial;
                root = root + 20'd1;
            end
        end
        return root;
    endfunction
    logic [15:0] snr_db_r;
    logic signed [15:0] sigma_q12_r;
    logic [39:0] signal_power_q24_r;
    logic signed [31:0] cfg_h1_square;
    logic [39:0] cfg_power_q24;
    logic [19:0] cfg_rms_q12;
    logic [44:0] cfg_sigma_product, cfg_sigma_rounded;
    logic [15:0] cfg_snr_clamped;
    always_comb begin
        cfg_snr_clamped = (i_cfg_snr_db > 16'd40) ? 16'd40 : i_cfg_snr_db;
        cfg_h1_square = i_cfg_isi_coeff * i_cfg_isi_coeff;
        cfg_power_q24 = 40'd5 * (40'd16777216 +
                        (i_cfg_isi_en ? {8'b0, cfg_h1_square} : 40'd0));
        cfg_rms_q12 = isqrt40(cfg_power_q24);
        cfg_sigma_product = cfg_rms_q12 * attenuation_q24(cfg_snr_clamped);
        cfg_sigma_rounded = (cfg_sigma_product + 45'd8388608) >> 24;
    end
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            snr_db_r <= 16'd20;
            sigma_q12_r <= 16'sd916;
            signal_power_q24_r <= 40'd83886080; // nominal PAM4 power = 5
        end else if (i_cfg_snr_load) begin
            snr_db_r <= cfg_snr_clamped;
            sigma_q12_r <= (cfg_sigma_rounded > 45'd32767)
                         ? 16'sh7fff : $signed(cfg_sigma_rounded[15:0]);
            signal_power_q24_r <= cfg_power_q24;
        end
    end
    assign o_cfg_snr_db = snr_db_r;
    assign o_cfg_sigma_q12 = sigma_q12_r;
    assign o_cfg_signal_power_q24 = signal_power_q24_r;
    function automatic logic [31:0] seed_mix(input logic [31:0] x);
        logic [31:0] t;
        t = x ^ (x << 13);
        t = t ^ (t >> 17);
        return t ^ (t << 5);
    endfunction
    function automatic logic [31:0] lane_seed(input int lane, component);
        logic [31:0] x, minimum;
        // Seed expansion from the local Python/MATLAB model (normal seed range).
        case (component)
            0: begin x = NOISE_SEED + 101 * (lane+1) + 1; minimum = 2; end
            1: begin x = NOISE_SEED + 211 * (lane+1) + 3; minimum = 8; end
            default: begin x = NOISE_SEED + 307 * (lane+1) + 7; minimum = 16; end
        endcase
        x = seed_mix(x);
        if (x < minimum) x = x + minimum;
        return x;
    endfunction
    logic [31:0] s1 [12], s2 [12], s3 [12];
    logic [11:0] uniform_r [12];
    for (genvar j = 0; j < 12; j++) begin : g_lane
        localparam int OFFSET = (4*j) % 21;
        logic [31:0] n1, n2, n3, word_u;
        assign n1 = ((s1[j] & 32'hfffffffe) << 12) ^ (((s1[j] << 13) ^ s1[j]) >> 19);
        assign n2 = ((s2[j] & 32'hfffffff8) << 4) ^ (((s2[j] << 2) ^ s2[j]) >> 25);
        assign n3 = ((s3[j] & 32'hfffffff0) << 17) ^ (((s3[j] << 3) ^ s3[j]) >> 11);
        assign word_u = n1 ^ n2 ^ n3;
        always_ff @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) begin
                s1[j] <= lane_seed(j, 0);
                s2[j] <= lane_seed(j, 1);
                s3[j] <= lane_seed(j, 2);
                uniform_r[j] <= '0;
            end else if (i_valid) begin
                s1[j] <= n1;
                s2[j] <= n2;
                s3[j] <= n3;
                uniform_r[j] <= 12'((word_u ^ (word_u >> 7)
                                  ^ {word_u[20:0], word_u[31:21]}) >> OFFSET);
            end
        end
    end
    // Five register stages: uniform/ISI -> pairs -> groups -> total -> output.
    // Input captured at edge t produces output just after edge t+4.
    // RNG/history advance only for valid input; pipeline advances every clock.
    logic signed [15:0] previous_r;
    logic signed [31:0] isi_product, isi_sum;
    logic signed [15:0] clean_pipe [4], sigma_pipe [4];
    logic [3:0] valid_pipe, enable_pipe;
    logic [12:0] pair_r [6];
    logic [13:0] group_r [3];
    logic [15:0] total_r;
    logic signed [31:0] centered, noise_product;
    logic signed [15:0] noise_sat;
    logic signed [31:0] noisy_sum;
    always_comb begin
        isi_product = previous_r * i_cfg_isi_coeff;
        isi_sum = {{16{i_tx_data[15]}}, i_tx_data};
        if (i_cfg_isi_en) isi_sum = isi_sum + (isi_product >>> 12);
        // U in [0,4095]: E[sum]=24570, Var(sum)=4096^2-1.
        // Interpreting centered as Q12 gives variance 1-2^-24.
        // Unit gain is the nearest Q12 normalization constant (4096).
        centered = $signed({16'b0, total_r}) - 32'sd24570;
        noise_product = centered * $signed(sigma_pipe[3]);
        noise_sat = enable_pipe[3] ? sat16(noise_product >>> 12) : 16'sd0;
        noisy_sum = $signed({{16{clean_pipe[3][15]}}, clean_pipe[3]})
                  + $signed({{16{noise_sat[15]}}, noise_sat});
    end
    always_ff @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            previous_r <= '0;
            valid_pipe <= '0;
            enable_pipe <= '0;
            total_r <= '0;
            o_valid <= 1'b0;
            o_channel_data <= '0;
            o_clean_isi_data <= '0;
            o_awgn_noise <= '0;
            for (int k=0; k<4; k++) begin
                clean_pipe[k] <= '0;
                sigma_pipe[k] <= '0;
            end
            for (int k=0; k<6; k++) pair_r[k] <= '0;
            for (int k=0; k<3; k++) group_r[k] <= '0;
        end else begin
            valid_pipe <= {valid_pipe[2:0], i_valid};
            enable_pipe <= {enable_pipe[2:0], i_cfg_awgn_en};
            if (i_valid) previous_r <= i_tx_data;
            clean_pipe[0] <= sat16(isi_sum);
            sigma_pipe[0] <= sigma_q12_r;
            for (int k=1; k<4; k++) begin
                clean_pipe[k] <= clean_pipe[k-1];
                sigma_pipe[k] <= sigma_pipe[k-1];
            end
            for (int k=0; k<6; k++)
                pair_r[k] <= {1'b0, uniform_r[2*k]} + {1'b0, uniform_r[2*k+1]};
            for (int k=0; k<3; k++)
                group_r[k] <= {1'b0, pair_r[2*k]} + {1'b0, pair_r[2*k+1]};
            total_r <= {2'b0, group_r[0]} + {2'b0, group_r[1]} + {2'b0, group_r[2]};
            o_valid <= valid_pipe[3];
            o_clean_isi_data <= clean_pipe[3];
            o_awgn_noise <= noise_sat;
            o_channel_data <= sat16(noisy_sum);
        end
    end
endmodule
