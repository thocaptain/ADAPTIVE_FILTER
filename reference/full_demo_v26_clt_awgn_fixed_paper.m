function full_demo_v8_clt_awgn_fixed_paper()
%% ============================================================
% PAM4 + ISI + AWGN(CLT + Taus88) + DFE-LMS / Robust-Projected LMS
%
% FPGA-oriented version:
%   - LMS only (NO NLMS normalization / NO division)
%   - optional robust error clipping psi(e)
%   - optional box projection on taps
%   - optional decision-directed gating
%   - Monte-Carlo DFE validation (BER/SER + learning oscillation)
%   - projected ODE validation
%   - Polyak averaging validation
%   - decreasing-step validation
%
% Notes:
% - AWGN datapath is fixed-point.
% - Plotting/statistics remain floating-point.
% - LUT/FF/BRAM/DSP/Fmax must come from FPGA synthesis.
%% ============================================================

%% ---------------- Configuration ----------------
cfg.M           = 4;
cfg.A           = (-(cfg.M-1):2:(cfg.M-1));   % [-3 -1 1 3]
cfg.k           = log2(cfg.M);

cfg.ISI         = 0.5;
cfg.SNRdB       = 20;

cfg.sps_eye     = 16;
cfg.alpha_eye   = 0.5;
cfg.spanUI_eye  = 8;

cfg.eye_open_quantile_pct = 5;
cfg.eye_max_traces_plot   = 800;

% DFE
cfg.Nf          = 3;
cfg.Nb          = 1;
cfg.D           = 1;
cfg.trainLen    = 3000;
cfg.mu          = 5e-4;

% Fixed-point / RNG
cfg.total_bits  = 16;      % signed Q4.12
cfg.frac_bits   = 12;
cfg.u_bits      = 12;
cfg.seed0       = uint32(hex2dec('0A5B'));

% Stage-1 proposal
cfg.stage1_mix_enable = true;
cfg.stage1_r1         = 7;
cfg.stage1_r2         = 11;

% m configuration
cfg.m_list       = [12 24 48 96];
cfg.m_clt        = 12;
cfg.m_clt_sys    = 12;

% ------------------------------------------------------------
% Lane debug export mode
% ------------------------------------------------------------
cfg.run_lane_debug          = true;
cfg.lane_debug_m_list       = [12];
cfg.lane_debug_N            = 50000;
cfg.lane_debug_preview_N    = 12;
cfg.lane_debug_file_prefix  = 'lane_debug';

% ------------------------------------------------------------
% Statistical validation mode
% ------------------------------------------------------------
cfg.run_stat_validation = true;
cfg.run_multi_m_stat    = true;
cfg.Nsym_stat           = 10000000;

% ------------------------------------------------------------
% System evaluation mode
% ------------------------------------------------------------
cfg.run_system_eval     = true;
cfg.run_multi_m_sys     = false;
cfg.Nsym_sys            = 200000;
cfg.enable_eye_analysis = true;
cfg.max_eye_symbols     = 20000;
cfg.store_dfe_history   = false;
cfg.do_per_m_snr_sweep  = false;
cfg.snr_list            = 10:2:24;

% ------------------------------------------------------------
% Robust / projected LMS (NO division, FPGA-friendly)
% ------------------------------------------------------------
cfg.eq_variant          = 'robust_proj';   % plain / sm_sign / robust / proj / robust_proj

% bounded observation transform psi(e)
cfg.use_error_clip      = true;
cfg.err_clip            = 2.5;             % symbol-scale clipping

% projected iterate box H = [l_i, u_i]
cfg.use_proj            = true;
cfg.w_min               = -2.0 * ones(cfg.Nf,1);
cfg.w_max               =  2.0 * ones(cfg.Nf,1);
cfg.b_min               = -2.0 * ones(cfg.Nb,1);
cfg.b_max               =  2.0 * ones(cfg.Nb,1);

% decision-directed gating
cfg.use_dd_gate         = true;
cfg.dd_gate_err         = 1.50;            % update only if |e| <= threshold in DD mode

% LMS-SM-sign baseline: set-membership data censoring + signed-error LMS update
% update condition: |e| > sm_sign_err_bound; update direction: sign(e) * x
cfg.sm_sign_err_bound  = 0.75;            % bounded-error set-membership threshold
cfg.sm_sign_update_amp = 1.00;            % signed-error amplitude used in the LMS update

% step-size mode
cfg.mu_mode             = 'constant';      % constant / decreasing
cfg.mu0                 = cfg.mu;
cfg.mu_n0               = 200;
cfg.mu_gamma            = 0.70;            % only used when mu_mode='decreasing'

% ------------------------------------------------------------
% Internal adaptation precision (KEEP external datapath Q4.12)
% ------------------------------------------------------------
cfg.adapt_frac_bits      = 20;   % internal only
cfg.adapt_total_bits     = 40;   % internal only

% less-degenerate initialization
cfg.init_main_tap        = 0.75;
cfg.init_fb_tap          = 0.00;

% tighter projection box so projection can actually appear
cfg.w_min               = -1.25 * ones(cfg.Nf,1);
cfg.w_max               =  1.25 * ones(cfg.Nf,1);
cfg.b_min               = -0.75 * ones(cfg.Nb,1);
cfg.b_max               =  0.75 * ones(cfg.Nb,1);

% iterate averaging (validation only, not RTL datapath)
cfg.use_polyak_avg      = true;
cfg.polyak_start_frac   = 0.60;

% trace collection for MC / validation
cfg.collect_learning_trace = true;
cfg.trace_decim            = 50;

% verbosity
cfg.verbose_case           = true;
% ------------------------------------------------------------
% Equalizer sample-by-sample debug export
% ------------------------------------------------------------
cfg.run_eq_debug_export   = true;
cfg.eq_debug_N            = 12800;                 % export số sample đầu
cfg.eq_debug_seed         = 12345;
cfg.eq_debug_use_awgn     = true;
cfg.eq_debug_variant      = 'robust_proj';
cfg.eq_debug_file_prefix  = 'eq_debug_trace';
% ------------------------------------------------------------
% Validation / experiments
% ------------------------------------------------------------
cfg.do_zscore_reference   = false;
cfg.enable_rng_debug      = false;
cfg.enable_excel_log      = false;
cfg.tail_thresholds       = [3 4 5];
cfg.maxLag_whiteness      = 40;
cfg.max_exact_irwinhall_m = 24;
cfg.max_bittrue_exact_m   = 24;
cfg.chi2_num_bins         = 24;

cfg.validation_mode        = 'bittrue_fixedpoint';
cfg.gain_search_radius_fx  = 8;
cfg.use_discrete_center    = true;
cfg.use_gain_fx_tuning     = true;

cfg.do_lane_correlation_subset = false;
cfg.lane_corr_subset_N         = 100000;

cfg.enable_finite_m_exact = true;
cfg.max_finite_m_exact    = 24;

cfg.enable_chen_style_validation = true;
cfg.chen_alpha                   = 0.05;
cfg.chen_target_sigma            = 1.0;
cfg.chen_t_sigma                 = 8;
cfg.chen_min_expected_per_bin    = 5;
cfg.chen_report_pmf_error        = true;

% ------------------------------------------------------------
% Noise-model experiments for robustness
% ------------------------------------------------------------
cfg.noise_model          = 'gaussian';     % gaussian / gaussmix
cfg.impulse_p            = 0.01;           % for gaussmix
cfg.impulse_kappa        = 8.0;            % burst scale

% ------------------------------------------------------------
% Monte-Carlo DFE evaluation
% ------------------------------------------------------------
cfg.run_mc_eval          = true;
cfg.Nmc                  = 24;
cfg.mc_variant_list      = {'plain','sm_sign','robust','proj','robust_proj'};
cfg.mc_noise_models      = {'gaussian','gaussmix'};
cfg.mc_seed_base         = 10000;
cfg.div_tap_norm_thresh  = 6.0;

% ------------------------------------------------------------
% Monte-Carlo SNR sweep for thesis DFE validation
% ------------------------------------------------------------
cfg.run_mc_snr_dfe_validation = true;
cfg.mc_snr_list               = 15:1:30;
cfg.mc_snr_variant_list       = {'plain','sm_sign','robust_proj'};  % LMS / LMS-SM-sign / proposed
cfg.mc_snr_noise_model        = 'gaussian';
cfg.mc_snr_Nmc                = 12;
cfg.mc_snr_Nsym               = 120000;
cfg.mc_snr_trace_decim        = 100;
cfg.mc_snr_trace_snr          = 20;
cfg.fec_threshold_ber         = 1e-3;

% ------------------------------------------------------------
% Projected ODE validation
% ------------------------------------------------------------
cfg.run_projected_ode_validation = true;
cfg.ode_avg_N            = 12000;
cfg.ode_grid_N           = 15;
cfg.ode_mu               = 2e-4;
cfg.ode_idx_pair         = [cfg.D+1, cfg.Nf+1]; % main FFE tap + first FBE tap

% ------------------------------------------------------------
% Polyak / decreasing-mu validation
% ------------------------------------------------------------
cfg.run_polyak_validation         = true;
cfg.run_decreasing_mu_validation  = true;
cfg.dec_mu_validation_noise       = 'gaussmix';
cfg.dec_mu_validation_variants    = {'plain','robust_proj'};
cfg.dec_mu_Nsym                   = 8000;
cfg.dec_mu_Nmc                    = 12;
cfg.dec_mu_trace_decim            = 20;

% ------------------------------------------------------------
% Additional validation suites for thesis completeness
% ------------------------------------------------------------

% clipping-threshold sweep
cfg.run_clip_sweep_validation = true;
cfg.clip_sweep_noise          = 'gaussmix';
cfg.clip_sweep_variant        = 'robust_proj';
cfg.clip_sweep_baseline_variants = {'plain'};   % legacy/testbench mode: keep old plain baseline
cfg.clip_list                 = [0.75 1.0 1.5 2.0 2.5 3.0 4.0];
cfg.clip_sweep_Nmc            = 12;
cfg.clip_sweep_Nsym           = 120000;
cfg.clip_sweep_snr_list       = 15:1:30;
cfg.clip_sweep_use_snr_sweep = true;   % SNR sweep enabled; seed remains legacy/testbench-compatible
cfg.clip_sweep_export_csv    = true;
cfg.clip_sweep_seed_mode     = 'v24'; % v24-compatible: keep cfg_i.seed0 unchanged; plain rng(810000+imc), clips rng(820000+100*ic+imc)

% empirical Lyapunov validation (simulation support, not formal proof)
cfg.run_lyapunov_validation   = true;
cfg.lyap_noise_model          = 'gaussmix';
cfg.lyap_variants             = {'plain','robust_proj'};
cfg.lyap_Nmc                  = 12;
cfg.lyap_Nsym                 = 12000;
cfg.lyap_trace_decim          = 20;
cfg.lyap_movavg_len           = 9;

% tightness / boundedness validation
cfg.run_tightness_validation  = true;
cfg.tight_noise_model         = 'gaussmix';
cfg.tight_variants            = {'plain','robust','proj','robust_proj'};
cfg.tight_Nmc                 = 24;
cfg.tight_Nsym                = 120000;

% tap trajectory visualization
cfg.run_tap_trajectory_validation = true;
cfg.taptraj_noise_model          = 'gaussmix';
cfg.taptraj_variants             = {'plain','robust_proj'};
cfg.taptraj_Nsym                 = 12000;
cfg.taptraj_trace_decim          = 10;
cfg.taptraj_idx                  = [cfg.D+1, cfg.Nf+1];  % main FFE tap, first FBE tap

if cfg.frac_bits ~= cfg.u_bits
    error('This script assumes frac_bits == u_bits == 12 for a clean CLT datapath.');
end

%% ---------------- Main ----------------
if cfg.run_lane_debug
    run_lane_debug_export(cfg);
end

if cfg.run_stat_validation
    run_statistical_validation(cfg);
end

if cfg.run_system_eval
    run_system_level_evaluation(cfg);
end

if cfg.run_mc_eval
    run_mc_dfe_suite(cfg);
end

if cfg.run_mc_snr_dfe_validation
    run_mc_snr_dfe_validation_suite(cfg);
end

if cfg.run_projected_ode_validation
    run_projected_ode_suite(cfg);
end

if cfg.run_polyak_validation
    run_polyak_validation_suite(cfg);
end

if cfg.run_decreasing_mu_validation
    run_decreasing_mu_validation_suite(cfg);
end

if cfg.run_clip_sweep_validation
    run_clip_sweep_suite(cfg);
end

if cfg.run_lyapunov_validation
    run_empirical_lyapunov_suite(cfg);
end

if cfg.run_tightness_validation
    run_tightness_boundedness_suite(cfg);
end

if cfg.run_tap_trajectory_validation
    run_tap_trajectory_suite(cfg);
end

if cfg.run_eq_debug_export
    run_eq_debug_export(cfg);
end
end

%% ============================================================
function run_lane_debug_export(cfg)
% Export debug data for multiple m values:
%   - initial states per lane
%   - raw lane word W32
%   - mixed lane word V32
%   - extracted lane word R before summation
%   - sumR / center_fx / z_clt_fx

    m_list = cfg.lane_debug_m_list(:).';

    fprintf('\n==================================================\n');
    fprintf('LANE DEBUG EXPORT MODE\n');
    fprintf('m list:'); fprintf(' %d', m_list); fprintf('\n');
    fprintf('N export per m = %d\n', cfg.lane_debug_N);
    fprintf('Preview rows per m = %d\n', cfg.lane_debug_preview_N);
    fprintf('==================================================\n');

    for im = 1:numel(m_list)
        mval = m_list(im);

        cfg_i = prepare_cfg_for_m(cfg, mval);
        cfg_i.enable_rng_debug = true;

        Ndbg    = cfg_i.lane_debug_N;
        Nshow   = min(cfg_i.lane_debug_preview_N, Ndbg);
        outFile = sprintf('%s_m%d.xlsx', cfg_i.lane_debug_file_prefix, mval);

        fprintf('\n--------------------------------------------------\n');
        fprintf('Lane debug export for m = %d\n', mval);
        fprintf('Output file: %s\n', outFile);
        fprintf('--------------------------------------------------\n');

        [z_fx, dbg] = my_randn_clt_taus88_fx(Ndbg, cfg_i);

        fprintf('\nInitial states for m = %d\n', mval);
        fprintf('%6s %10s %12s %12s %12s\n', 'lane', 'bit_offset', 'init_s1', 'init_s2', 'init_s3');
        for j = 1:cfg_i.m_clt
            fprintf('%6d %10d %12u %12u %12u\n', ...
                j, dbg.bit_offsets(j), dbg.init_s1(j), dbg.init_s2(j), dbg.init_s3(j));
        end

        fprintf('\nFirst %d samples for m = %d\n', Nshow, mval);
        for n = 1:Nshow
            fprintf('sample %d: sumR=%d, center_fx=%d, z_clt_fx=%d, z_clt=%.6f\n', ...
                n, dbg.sumR(n), dbg.center_fx(n), z_fx(n), q_to_real_scalar(z_fx(n), cfg_i.frac_bits));

            for j = 1:cfg_i.m_clt
                fprintf('   lane %2d: W32=%10u, V32=%10u, R=%5u\n', ...
                    j, dbg.W32(n,j), dbg.V32(n,j), dbg.R(n,j));
            end
        end

        lane_idx = (1:cfg_i.m_clt).';
        initTbl = table( ...
            lane_idx, ...
            dbg.bit_offsets(:), ...
            double(dbg.init_s1(:)), ...
            binvec_unsigned(dbg.init_s1(:), 32), ...
            double(dbg.init_s2(:)), ...
            binvec_unsigned(dbg.init_s2(:), 32), ...
            double(dbg.init_s3(:)), ...
            binvec_unsigned(dbg.init_s3(:), 32), ...
            'VariableNames', { ...
                'lane', ...
                'bit_offset', ...
                'init_s1_dec', 'init_s1_bin', ...
                'init_s2_dec', 'init_s2_bin', ...
                'init_s3_dec', 'init_s3_bin'});

        writetable(initTbl, outFile, 'Sheet', 'InitSeeds');

        meta_name = { ...
            'm_clt'; ...
            'u_bits'; ...
            'frac_bits'; ...
            'total_bits'; ...
            'stage1_mix_enable'; ...
            'stage1_r1'; ...
            'stage1_r2'; ...
            'center_const'; ...
            'clt_gain_fx'; ...
            'clt_gain_float'; ...
            'N_export'};

        meta_value = [ ...
            double(cfg_i.m_clt); ...
            double(cfg_i.u_bits); ...
            double(cfg_i.frac_bits); ...
            double(cfg_i.total_bits); ...
            double(cfg_i.stage1_mix_enable); ...
            double(cfg_i.stage1_r1); ...
            double(cfg_i.stage1_r2); ...
            double(dbg.center_const); ...
            double(dbg.clt_gain_fx); ...
            double(dbg.clt_gain_float); ...
            double(Ndbg)];

        metaTbl = table(meta_name, meta_value, ...
            'VariableNames', {'name','value'});

        writetable(metaTbl, outFile, 'Sheet', 'Meta');

        sampleTbl = table( ...
            (1:Ndbg).', ...
            double(dbg.sumR(:)), ...
            double(dbg.center_fx(:)), ...
            double(z_fx(:)), ...
            q_to_real(z_fx, cfg_i.frac_bits), ...
            'VariableNames', { ...
                'sample', ...
                'sumR_dec', ...
                'center_fx_dec', ...
                'z_clt_fx_dec', ...
                'z_clt_float'});

        sumR_bits = cfg_i.u_bits + ceil(log2(cfg_i.m_clt));
        sampleTbl.sumR_bin      = binvec_unsigned(uint32(dbg.sumR(:)), sumR_bits);
        sampleTbl.center_fx_bin = binvec_signed_tc(dbg.center_fx(:), cfg_i.total_bits);
        sampleTbl.z_clt_fx_bin  = binvec_signed_tc(z_fx(:), cfg_i.total_bits);

        for j = 1:cfg_i.m_clt
            sampleTbl.(sprintf('W32_lane%d_dec', j)) = double(dbg.W32(:,j));
            sampleTbl.(sprintf('W32_lane%d_bin', j)) = binvec_unsigned(dbg.W32(:,j), 32);

            sampleTbl.(sprintf('V32_lane%d_dec', j)) = double(dbg.V32(:,j));
            sampleTbl.(sprintf('V32_lane%d_bin', j)) = binvec_unsigned(dbg.V32(:,j), 32);

            sampleTbl.(sprintf('R_lane%d_dec', j)) = double(dbg.R(:,j));
            sampleTbl.(sprintf('R_lane%d_bin', j)) = binvec_unsigned(dbg.R(:,j), cfg_i.u_bits);
        end

        writetable(sampleTbl, outFile, 'Sheet', 'LaneData');

        fprintf('Lane debug Excel export done: %s\n', outFile);
    end
end

%% ============================================================
function run_statistical_validation(cfg)

    if cfg.run_multi_m_stat
        m_list = cfg.m_list(:).';
    else
        m_list = cfg.m_clt;
    end

    nM = numel(m_list);
    summary = struct([]);

    fprintf('\n==================================================\n');
    fprintf('STATISTICAL VALIDATION MODE\n');
    fprintf('Nsym_stat = %d\n', cfg.Nsym_stat);
    fprintf('m values:'); fprintf(' %d', m_list); fprintf('\n');
    fprintf('==================================================\n');

    for im = 1:nM
        cfg_i = prepare_cfg_for_m(cfg, m_list(im));

        fprintf('\n##################################################\n');
        fprintf('Statistical validation for m = %d\n', cfg_i.m_clt);
        fprintf('Stage-1 bit offsets:'); fprintf(' %d', cfg_i.stage1_bit_offsets); fprintf('\n');
        fprintf('##################################################\n');

        [z_fx, dbg] = my_randn_clt_taus88_fx(cfg_i.Nsym_stat, cfg_i);
        z = q_to_real(z_fx, cfg_i.frac_bits);

        ref = validate_awgn_suite_bittrue(z_fx, cfg_i, dbg.clt_gain_fx);
        validate_whiteness(z, cfg_i.maxLag_whiteness);
        validate_tail_counts_bittrue(z_fx, cfg_i, dbg.clt_gain_fx, ref);

        if cfg_i.enable_chen_style_validation
            validate_awgn_suite_chen_style(z_fx, cfg_i);
        end

        if cfg_i.do_lane_correlation_subset
            cfg_dbg = cfg_i;
            cfg_dbg.enable_rng_debug = true;
            [~, dbg_sub] = my_randn_clt_taus88_fx(cfg_i.lane_corr_subset_N, cfg_dbg);
            if isfield(dbg_sub, 'U') && ~isempty(dbg_sub.U)
                validate_lane_correlation(dbg_sub.U);
            end
        end

        stats = compute_awgn_basic_stats(z, cfg_i.m_clt);

        summary(im).m                  = cfg_i.m_clt;
        summary(im).mean_z             = stats.mu;
        summary(im).std_z              = stats.sig;
        summary(im).skew_z             = stats.sk;
        summary(im).kurt_z             = stats.kt;
        summary(im).kurt_theory        = stats.kt_th;
        summary(im).clt_gain_fx        = double(dbg.clt_gain_fx);
        summary(im).clt_gain_real      = double(dbg.clt_gain_fx) / 2^cfg_i.frac_bits;
    end

    fprintf('\n================ MULTI-m STAT SUMMARY ================\n');
    fprintf('%8s %12s %12s %12s %12s %12s\n', ...
        'm', 'mean(z)', 'std(z)', 'skew(z)', 'kurt(z)', 'gain');
    for im = 1:nM
        fprintf('%8d %12.6f %12.6f %12.6f %12.6f %12.6f\n', ...
            summary(im).m, ...
            summary(im).mean_z, ...
            summary(im).std_z, ...
            summary(im).skew_z, ...
            summary(im).kurt_z, ...
            summary(im).clt_gain_real);
    end

    plot_multi_m_stat_summary(summary);
end

%% ============================================================
function run_system_level_evaluation(cfg)

    if cfg.run_multi_m_sys
        m_list = cfg.m_list(:).';
    else
        m_list = cfg.m_clt_sys;
    end

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    fprintf('\n==================================================\n');
    fprintf('SYSTEM EVALUATION MODE\n');
    fprintf('Nsym_sys = %d\n', cfg.Nsym_sys);
    fprintf('m values:'); fprintf(' %d', m_list); fprintf('\n');
    fprintf('default EQ variant = %s\n', cfg.eq_variant);
    fprintf('==================================================\n');

    summary = struct([]);

    for im = 1:numel(m_list)
        cfg_i = prepare_cfg_for_m(cfg, m_list(im));

        rng(1);
        sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
        d       = cfg_i.A(sym_idx);
        d       = d(:);

        fprintf('\n##################################################\n');
        fprintf('System evaluation for m = %d\n', cfg_i.m_clt);
        fprintf('##################################################\n');

        res0 = run_case_system(d, cfg_i, g_rc, false, cfg_i.eq_variant);
        res1 = run_case_system(d, cfg_i, g_rc, true,  cfg_i.eq_variant);

        print_summary_table(res0, res1, cfg_i);

        summary(im).m                  = cfg_i.m_clt;
        summary(im).SER_dfe            = res1.SER_dfe;
        summary(im).BER_dfe            = res1.BER_dfe;
        summary(im).MSE_ss             = res1.MSE_ss;
        summary(im).eye_height_post    = res1.app_metrics_post.worst_eye_height;
        summary(im).eye_width_post     = res1.app_metrics_post.worst_eye_width_ui;
        summary(im).cross_rms_post     = res1.app_metrics_post.worst_crossing_rms_ui;
        summary(im).slicer_snr_post_db = res1.app_metrics_post.slicer_snr_db;

        if cfg_i.do_per_m_snr_sweep
            sweep_ser_ber_vs_snr(cfg_i, g_rc, cfg_i.snr_list);
        end

        print_analytic_arch_summary(cfg_i);
    end

    if numel(summary) > 1
        plot_multi_m_system_summary(summary);
    end
end

%% ============================================================
function cfg_i = prepare_cfg_for_m(cfg, m)

    cfg_i = cfg;
    cfg_i.m_clt = m;
    cfg_i.stage1_bit_offsets = make_stage1_bit_offsets(cfg_i.m_clt, cfg_i.u_bits);
    validate_stage1_offsets(cfg_i.stage1_bit_offsets, cfg_i.m_clt, cfg_i.u_bits);

end

%% ============================================================
function res = run_case_system(d, cfg, g_rc, use_awgn, eq_variant)

    if nargin < 5 || isempty(eq_variant)
        eq_variant = cfg.eq_variant;
    end

    cfg_i = cfg;
    cfg_i.eq_variant = eq_variant;

    % --------------------------------------------------------
    % Ensure m-dependent fields exist
    % --------------------------------------------------------
    if ~isfield(cfg_i, 'm_clt') || isempty(cfg_i.m_clt)
        if isfield(cfg_i, 'm_clt_sys') && ~isempty(cfg_i.m_clt_sys)
            cfg_i.m_clt = cfg_i.m_clt_sys;
        else
            error('cfg.m_clt is missing.');
        end
    end

    if ~isfield(cfg_i, 'stage1_bit_offsets') || isempty(cfg_i.stage1_bit_offsets)
        cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);
    end

    Q    = cfg_i.frac_bits;
    TB   = cfg_i.total_bits;
    Nsym = numel(d);

    % Symbol-rate ISI channel
    r_clean    = d + cfg_i.ISI * [0; d(1:end-1)];
    r_clean_fx = q_from_real(r_clean, Q, TB);

    if ~use_awgn
        r_fx          = r_clean_fx;
        z_clt_fx      = int32(zeros(Nsym,1));
        z_clt_float   = [];
        sqrt_sigma_fx = int32(0);
        sigma2        = 0;
        rng_dbg       = struct('U', []);
        noise_fx      = int32(zeros(Nsym,1));
        noise_dbg     = struct();
        noise_dbg.impulse_count = 0;
    else
        Pr            = mean(r_clean.^2);
        sigma2        = Pr / (10^(cfg_i.SNRdB/10));
        sqrt_sigma_fx = q_from_real_scalar(sqrt(sigma2), Q, TB);

        [noise_fx, z_clt_fx, z_clt_float, rng_dbg, noise_dbg] = ...
            generate_channel_noise_fx(Nsym, sqrt_sigma_fx, cfg_i);

        r_fx = q_add_vec(r_clean_fx, noise_fx, TB);
    end

    % Decisions before EQ
    r_float = q_to_real(r_fx, Q);
    d_noeq  = pam_slice_vec(r_float, cfg_i.A);

    % Fixed-point DFE-LMS / Robust-Projected LMS
    d_fx = q_from_real(d, Q, TB);
    [y_fx, d_hat, e_fx, W_hist, B_hist, w_final, b_final, aux] = ...
        dfe_lms_pam_fp_core(r_fx, d_fx, cfg_i);

    y_float = q_to_real(y_fx, Q);
    e_float = q_to_real(e_fx, Q);

    % Eye analysis
    if cfg_i.enable_eye_analysis
        Neye = min(numel(r_float), cfg_i.max_eye_symbols);
        y_b_os = conv(upsample_zero(r_float(1:Neye), cfg_i.sps_eye), g_rc);
        y_a_os = conv(upsample_zero(y_float(1:Neye), cfg_i.sps_eye), g_rc);

        eye_metrics_pre  = analyze_reconstructed_eye(y_b_os, cfg_i.sps_eye, cfg_i.A, cfg_i.eye_open_quantile_pct);
        eye_metrics_post = analyze_reconstructed_eye(y_a_os, cfg_i.sps_eye, cfg_i.A, cfg_i.eye_open_quantile_pct);
    else
        y_b_os = [];
        y_a_os = [];
        eye_metrics_pre  = empty_eye_metrics(cfg_i.A);
        eye_metrics_post = empty_eye_metrics(cfg_i.A);
    end

    slicer_metrics_pre  = analyze_slicer_clusters(r_float, d, 0,      cfg_i.A);
    slicer_metrics_post = analyze_slicer_clusters(y_float, d, cfg_i.D, cfg_i.A);

    app_metrics_pre  = summarize_app_metrics(eye_metrics_pre,  slicer_metrics_pre);
    app_metrics_post = summarize_app_metrics(eye_metrics_post, slicer_metrics_post);

    [SER_noeq, SER_dfe, BER_noeq, BER_dfe] = ...
        ser_ber_from_decisions(d, d_noeq, d_hat, cfg_i.D, cfg_i.A, cfg_i.k);

    mse_curve = e_float.^2;
    tailL     = max(1, round(0.9*length(mse_curve)));
    MSE_ss    = mean(mse_curve(tailL:end));

    if cfg_i.verbose_case
        if use_awgn
            tag = sprintf('%s | %s | SNR=%.1f dB | m=%d', ...
                upper(eq_variant), upper(cfg_i.noise_model), cfg_i.SNRdB, cfg_i.m_clt);
        else
            tag = sprintf('%s | NO-AWGN | m=%d', upper(eq_variant), cfg_i.m_clt);
        end

        fprintf('=== %s ===\n', tag);
        fprintf('SER  No-EQ: %.6g | SER DFE: %.6g\n', SER_noeq, SER_dfe);
        fprintf('BER  No-EQ: %.6g | BER DFE: %.6g\n', BER_noeq, BER_dfe);
        fprintf('MSE_ss (tail 10%%): %.6g\n', MSE_ss);
        fprintf('Projection count: %d | DD-gate skips: %d\n', ...
            aux.proj_count_total, aux.dd_gate_skip_count);

        if use_awgn
            fprintf('sqrt(sigma2) fixed = %.6f\n', q_to_real_scalar(sqrt_sigma_fx, Q));
            fprintf('z_clt mean/std     = %.6f / %.6f\n', mean(z_clt_float), std(z_clt_float,1));
            if isfield(noise_dbg,'impulse_count')
                fprintf('impulses           = %d\n', noise_dbg.impulse_count);
            end
        end

        print_pre_post_app_metrics(app_metrics_pre, app_metrics_post, tag);
        fprintf('\n');
        print_final_taps(w_final, b_final, cfg_i.D, Q, tag);
    end

    res = struct();
    res.d                   = d;
    res.d_fx                = d_fx;
    res.d_hat               = d_hat;

    res.r_clean             = r_clean;
    res.r_clean_fx          = r_clean_fx;

    res.noise_fx            = noise_fx;
    res.noise_float         = q_to_real(noise_fx, Q);

    res.r_fx                = r_fx;
    res.y_fx                = y_fx;

    res.y_b_os              = y_b_os;
    res.y_a_os              = y_a_os;
    res.y_float             = y_float;
    res.e_float             = e_float;

    res.SER_noeq            = SER_noeq;
    res.SER_dfe             = SER_dfe;
    res.BER_noeq            = BER_noeq;
    res.BER_dfe             = BER_dfe;
    res.MSE_ss              = MSE_ss;

    res.W                   = W_hist;
    res.B                   = B_hist;
    res.w_final             = w_final;
    res.b_final             = b_final;

    res.z_clt_fx            = z_clt_fx;
    res.z_clt_float         = z_clt_float;
    res.sigma2              = sigma2;
    res.rng_dbg             = rng_dbg;
    res.noise_dbg           = noise_dbg;

    res.eye_metrics_pre     = eye_metrics_pre;
    res.eye_metrics_post    = eye_metrics_post;
    res.slicer_metrics_pre  = slicer_metrics_pre;
    res.slicer_metrics_post = slicer_metrics_post;

    res.app_metrics_pre     = app_metrics_pre;
    res.app_metrics_post    = app_metrics_post;
    res.aux                 = aux;
end

%% ============================================================
function [noise_fx, z_clt_fx, z_clt_float, rng_dbg, noise_dbg] = generate_channel_noise_fx(Nsym, sqrt_sigma_fx, cfg)

    % --------------------------------------------------------
    % Ensure m-dependent fields exist
    % --------------------------------------------------------
    if ~isfield(cfg, 'm_clt') || isempty(cfg.m_clt)
        if isfield(cfg, 'm_clt_sys') && ~isempty(cfg.m_clt_sys)
            cfg.m_clt = cfg.m_clt_sys;
        else
            error('cfg.m_clt is missing.');
        end
    end

    if ~isfield(cfg, 'stage1_bit_offsets') || isempty(cfg.stage1_bit_offsets)
        cfg = prepare_cfg_for_m(cfg, cfg.m_clt);
    end

    Q  = cfg.frac_bits;
    TB = cfg.total_bits;

    [z_clt_fx, rng_dbg] = my_randn_clt_taus88_fx(Nsym, cfg);
    z_clt_float         = q_to_real(z_clt_fx, Q);

    noise_base_fx = q_mul_vec(sqrt_sigma_fx, z_clt_fx, Q, TB);
    noise_fx      = noise_base_fx;

    noise_dbg = struct();
    noise_dbg.impulse_count = 0;

    switch lower(cfg.noise_model)
        case 'gaussian'
            % keep base noise

        case 'gaussmix'
            rng(double(cfg.seed0) + 777);
            burst = rand(Nsym,1) < cfg.impulse_p;
            kappa_fx = q_from_real_scalar(cfg.impulse_kappa, Q, TB);

            if any(burst)
                noise_fx(burst) = q_mul_vec(kappa_fx, noise_fx(burst), Q, TB);
            end
            noise_dbg.impulse_count = sum(burst);

        otherwise
            error('Unsupported noise_model: %s', cfg.noise_model);
    end
end

%% ============================================================
function [z_fx, dbg] = my_randn_clt_taus88_fx(Nsym, cfg)
% Fixed-point CLT Gaussianization from m independent Taus88 lanes.

    % --------------------------------------------------------
    % Ensure m-dependent fields exist
    % --------------------------------------------------------
    if ~isfield(cfg, 'm_clt') || isempty(cfg.m_clt)
        if isfield(cfg, 'm_clt_sys') && ~isempty(cfg.m_clt_sys)
            cfg.m_clt = cfg.m_clt_sys;
        else
            error('cfg.m_clt is missing.');
        end
    end

    if ~isfield(cfg, 'stage1_bit_offsets') || isempty(cfg.stage1_bit_offsets)
        cfg = prepare_cfg_for_m(cfg, cfg.m_clt);
    end

    m      = cfg.m_clt;
    u_bits = cfg.u_bits;
    Q      = cfg.frac_bits;
    TB     = cfg.total_bits;
    seed0  = cfg.seed0;
    r1     = cfg.stage1_r1;
    r2     = cfg.stage1_r2;
    bit_offsets = cfg.stage1_bit_offsets(:);

    if mod(m,2) ~= 0
        error('m must be even in this implementation.');
    end

    if numel(bit_offsets) ~= m
        error('bit_offsets must have length m.');
    end

    if any(bit_offsets < 0) || any(bit_offsets + u_bits > 32)
        error('Invalid bit_offsets: each b_i must satisfy 0 <= b_i and b_i + u_bits <= 32.');
    end

    s1 = zeros(m,1,'uint32');
    s2 = zeros(m,1,'uint32');
    s3 = zeros(m,1,'uint32');

    for j = 1:m
        s1(j) = fix_taus_seed(seed_mix32(seed0 + uint32(101*j + 1)), uint32(2));
        s2(j) = fix_taus_seed(seed_mix32(seed0 + uint32(211*j + 3)), uint32(8));
        s3(j) = fix_taus_seed(seed_mix32(seed0 + uint32(307*j + 7)), uint32(16));
    end

    init_s1 = s1;
    init_s2 = s2;
    init_s3 = s3;

    sumR   = zeros(Nsym,1,'int32');
    mask_u = uint32(2^u_bits - 1);

    if cfg.enable_rng_debug
        U   = zeros(Nsym, m);
        R   = zeros(Nsym, m, 'uint16');
        W32 = zeros(Nsym, m, 'uint32');
        V32 = zeros(Nsym, m, 'uint32');
    else
        U   = [];
        R   = [];
        W32 = [];
        V32 = [];
    end

    for n = 1:Nsym
        [u32_vec, s1, s2, s3] = taus88_step_word_vec(s1, s2, s3);

        if cfg.stage1_mix_enable
            v32_vec = bitxor(bitxor(u32_vec, bitshift(u32_vec, -r1)), rotl32(u32_vec, r2));
        else
            v32_vec = u32_vec;
        end

        acc = int32(0);

        for j = 1:m
            bj   = double(bit_offsets(j));
            Rj_u = uint16(bitand(bitshift(v32_vec(j), -bj), mask_u));
            acc  = acc + int32(Rj_u);

            if cfg.enable_rng_debug
                W32(n,j)  = u32_vec(j);
                V32(n,j)  = v32_vec(j);
                R(n,j)    = Rj_u;
                U(n,j)    = double(Rj_u) / 2^u_bits;
            end
        end

        sumR(n) = acc;
    end

    Nlev = 2^u_bits;

    if cfg.use_discrete_center
        center_const = int32((m/2) * (Nlev - 1));
    else
        center_const = int32((m/2) * 2^Q);
    end

    center_fx = sumR - center_const;

    clt_gain_ideal = sqrt(12 / (m * (1 - 1/(Nlev^2))));

    if cfg.use_gain_fx_tuning
        clt_gain_fx = choose_best_gain_fx( ...
            clt_gain_ideal, m, u_bits, Q, TB, cfg.gain_search_radius_fx);
    else
        clt_gain_fx = q_from_real_scalar(clt_gain_ideal, Q, TB);
    end

    clt_gain = double(clt_gain_fx) / 2^Q;
    z_fx = q_mul_vec(center_fx, clt_gain_fx, Q, TB);

    if cfg.do_zscore_reference
        zf   = q_to_real(z_fx, Q);
        zf   = (zf - mean(zf)) ./ std(zf,1);
        z_fx = q_from_real(zf, Q, TB);
    end

    dbg = struct();
    dbg.init_s1           = init_s1;
    dbg.init_s2           = init_s2;
    dbg.init_s3           = init_s3;
    dbg.sumR              = sumR;
    dbg.center_fx         = center_fx;
    dbg.center_const      = center_const;
    dbg.U                 = U;
    dbg.R                 = R;
    dbg.W32               = W32;
    dbg.V32               = V32;
    dbg.bit_offsets       = bit_offsets(:);
    dbg.stage1_mix_enable = cfg.stage1_mix_enable;
    dbg.stage1_r1         = r1;
    dbg.stage1_r2         = r2;
    dbg.clt_gain_float    = clt_gain;
    dbg.clt_gain_ideal    = clt_gain_ideal;
    dbg.clt_gain_fx       = clt_gain_fx;
end

%% ============================================================
function [u32, s1, s2, s3] = taus88_step_word_vec(s1, s2, s3)

    b  = bitshift(bitxor(bitshift(s1, 13), s1), -19);
    s1 = bitxor(bitshift(bitand(s1, uint32(4294967294)), 12), b);

    b  = bitshift(bitxor(bitshift(s2, 2), s2), -25);
    s2 = bitxor(bitshift(bitand(s2, uint32(4294967288)), 4), b);

    b  = bitshift(bitxor(bitshift(s3, 3), s3), -11);
    s3 = bitxor(bitshift(bitand(s3, uint32(4294967280)), 17), b);

    u32 = bitxor(bitxor(s1, s2), s3);
end

function y = rotl32(x, k)
    x = uint32(x);
    k = mod(k, 32);
    if k == 0
        y = x;
    else
        y = bitor(bitshift(x, k, 'uint32'), bitshift(x, k - 32, 'uint32'));
    end
    y = uint32(y);
end

function y = seed_mix32(x)
    y = uint32(x);
    y = bitxor(y, bitshift(y, 13));
    y = bitxor(y, bitshift(y, -17));
    y = bitxor(y, bitshift(y, 5));
end

function s = fix_taus_seed(s, minval)
    s = uint32(s);
    if s < minval
        s = s + minval;
    end
    if s == 0
        s = minval;
    end
end

%% ============================================================
function gain_fx = choose_best_gain_fx(gain_ideal, m, u_bits, Q, TB, radius_fx)

    Nlev = 2^u_bits;
    var_center = m * (Nlev^2 - 1) / 12;

    g0_fx = q_from_real_scalar(gain_ideal, Q, TB);
    cand = int32((double(g0_fx)-radius_fx):(double(g0_fx)+radius_fx));

    best_cost = inf;
    gain_fx   = g0_fx;

    for k = 1:numel(cand)
        g = double(cand(k)) / 2^Q;
        var_z = (g^2) * var_center / (2^(2*u_bits));
        cost  = abs(var_z - 1);

        if cost < best_cost
            best_cost = cost;
            gain_fx   = cand(k);
        end
    end
end

%% ============================================================
function ref = validate_awgn_suite_bittrue(z_fx, cfg, clt_gain_fx)

    if isempty(z_fx)
        ref = [];
        return;
    end

    z = q_to_real(z_fx, cfg.frac_bits);
    m = cfg.m_clt;

    stats = compute_awgn_basic_stats(z, m);

    % Gaussian reference
    [Dg, pg] = ks_against_cdf(z, @(x) normcdf_approx(x));
    chiG     = chi_square_gof_gaussian_ref(z, cfg.chi2_num_bins);

    % Bit-true exact reference
    use_bittrue_exact = (m <= cfg.max_bittrue_exact_m);
    if use_bittrue_exact
        ref  = build_bittrue_fixedpoint_reference(m, cfg.u_bits, cfg.frac_bits, cfg.total_bits, clt_gain_fx);
        [Dbt, pbt] = ks_against_bittrue_ref(z_fx, ref);
        chiBT      = chi_square_gof_bittrue_ref(z_fx, ref, cfg.chi2_num_bins);
    else
        ref   = [];
        Dbt   = nan;
        pbt   = nan;
        chiBT = struct('stat', nan, 'dof', nan, 'p', nan);
    end

    % Supplementary finite-m exact reference
    use_finite_m_exact = cfg.enable_finite_m_exact && (m <= cfg.max_finite_m_exact);
    if use_finite_m_exact
        [Df, pf] = ks_against_cdf(z, @(x) irwinhall_std_cdf(x, m));
        chiF     = chi_square_gof_finite_m_ref(z, m, cfg.chi2_num_bins);
    else
        Df   = nan;
        pf   = nan;
        chiF = struct('stat', nan, 'dof', nan, 'p', nan);
    end

    figure('Name', sprintf('AWGN validation suite bit-true + finite-m (m=%d)', m));
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    histogram(z, 60, 'Normalization','pdf'); hold on;
    xx = linspace(min(z), max(z), 1200);
    plot(xx, (1/sqrt(2*pi))*exp(-0.5*xx.^2), 'r-', 'LineWidth', 1.2);
    legend('hist','Gaussian','Location','best');
    title(sprintf('Histogram vs Gaussian (m=%d)', m));
    grid on;
    xlabel('z');
    ylabel('pdf');

    nexttile;
    zs = sort(z(:));
    n  = numel(zs);
    Fe = (1:n)'/n;
    plot(zs, Fe, 'k-', 'LineWidth',1.0); hold on;
    plot(xx, normcdf_approx(xx), 'r-.', 'LineWidth',1.2);

    legend_list = {'empirical','Gaussian'};

    if use_finite_m_exact
        plot(xx, irwinhall_std_cdf(xx, m), 'g--', 'LineWidth', 1.2);
        legend_list{end+1} = 'finite-m exact';
    end

    if use_bittrue_exact
        stairs(ref.z, ref.cdf, 'b-', 'LineWidth', 1.2);
        legend_list{end+1} = 'bit-true ideal';
    end

    legend(legend_list, 'Location','best');
    title('Empirical CDF vs references');
    grid on;
    xlabel('z');
    ylabel('CDF');

    nexttile;
    p    = ((1:n)' - 0.5) / n;
    qn   = sqrt(2) * erfinv(2*p - 1);
    plot(qn, zs, '.', 'MarkerSize', 6); hold on;
    qmin = min([qn; zs]);
    qmax = max([qn; zs]);
    plot([qmin qmax], [qmin qmax], 'r-', 'LineWidth',1.2);
    grid on;
    xlabel('Gaussian quantiles');
    ylabel('Empirical quantiles');
    title('Q-Q plot vs Gaussian');

    nexttile;
    text(0.05,0.90, sprintf('\\mu = %.8f', stats.mu), 'Units','normalized', 'FontSize',11);
    text(0.05,0.82, sprintf('\\sigma = %.8f', stats.sig), 'Units','normalized', 'FontSize',11);
    text(0.05,0.74, sprintf('skew = %.8f', stats.sk), 'Units','normalized', 'FontSize',11);
    text(0.05,0.66, sprintf('kurt = %.8f (th = %.8f)', stats.kt, stats.kt_th), 'Units','normalized', 'FontSize',11);

    text(0.05,0.54, sprintf('KS vs Gaussian: D = %.8g, p = %.8g', Dg, pg), ...
        'Units','normalized', 'FontSize',11);
    text(0.05,0.46, sprintf('Chi2 vs Gaussian: stat = %.8g, p = %.8g', chiG.stat, chiG.p), ...
        'Units','normalized', 'FontSize',11);

    if use_finite_m_exact
        text(0.05,0.32, sprintf('KS vs finite-m: D = %.8g, p = %.8g', Df, pf), ...
            'Units','normalized', 'FontSize',11);
        text(0.05,0.24, sprintf('Chi2 vs finite-m: stat = %.8g, p = %.8g', chiF.stat, chiF.p), ...
            'Units','normalized', 'FontSize',11);
    else
        text(0.05,0.28, sprintf('finite-m exact skipped for m > %d', cfg.max_finite_m_exact), ...
            'Units','normalized', 'FontSize',11);
    end

    if use_bittrue_exact
        text(0.05,0.12, sprintf('KS vs bit-true: D = %.8g, p = %.8g', Dbt, pbt), ...
            'Units','normalized', 'FontSize',11);
        text(0.05,0.04, sprintf('Chi2 vs bit-true: stat = %.8g, p = %.8g', chiBT.stat, chiBT.p), ...
            'Units','normalized', 'FontSize',11);
    else
        text(0.05,0.08, sprintf('bit-true exact skipped for m > %d', cfg.max_bittrue_exact_m), ...
            'Units','normalized', 'FontSize',11);
    end

    axis off;
    title('Summary');

    fprintf('\n========== AWGN VALIDATION (BIT-TRUE + FINITE-m EXACT) ==========\n');
    fprintf('m                      = %d\n', m);
    fprintf('mean                   = %.8f\n', stats.mu);
    fprintf('std                    = %.8f\n', stats.sig);
    fprintf('skewness               = %.8f\n', stats.sk);
    fprintf('excess kurtosis        = %.8f\n', stats.kt);
    fprintf('theory kurtosis        = %.8f\n', stats.kt_th);

    fprintf('KS vs Gaussian         = %.8f, p = %.8f\n', Dg, pg);
    fprintf('Chi2 vs Gaussian       = %.8f, dof = %d, p = %.8f\n', chiG.stat, chiG.dof, chiG.p);

    if use_finite_m_exact
        fprintf('KS vs finite-m exact   = %.8f, p = %.8f\n', Df, pf);
        fprintf('Chi2 vs finite-m exact = %.8f, dof = %d, p = %.8f\n', chiF.stat, chiF.dof, chiF.p);
    else
        fprintf('Finite-m exact skipped for m > %d\n', cfg.max_finite_m_exact);
    end

    if use_bittrue_exact
        fprintf('KS vs bit-true ideal   = %.8f, p = %.8f\n', Dbt, pbt);
        fprintf('Chi2 vs bit-true ideal = %.8f, dof = %d, p = %.8f\n', chiBT.stat, chiBT.dof, chiBT.p);
    else
        fprintf('Bit-true exact skipped for m > %d\n', cfg.max_bittrue_exact_m);
    end
end

%% ============================================================
function validate_awgn_suite_chen_style(z_fx, cfg)

    if isempty(z_fx), return; end

    Q = cfg.frac_bits;
    z = q_to_real(z_fx, Q);

    sigma_target = cfg.chen_target_sigma;
    var_target   = sigma_target^2;
    t_sigma      = cfg.chen_t_sigma;
    minExp       = cfg.chen_min_expected_per_bin;

    ref = build_discrete_gaussian_reference_fixedpoint(Q, cfg.total_bits, sigma_target, t_sigma);

    z_fx_d = double(z_fx(:));
    in_rng = (z_fx_d >= ref.x_fx(1)) & (z_fx_d <= ref.x_fx(end));
    z_fx_in = z_fx_d(in_rng);
    N_in    = numel(z_fx_in);
    N_all   = numel(z_fx_d);

    if N_in == 0
        fprintf('\n[Chen-style validation] No samples inside target range.\n');
        return;
    end

    obs = accumarray( ...
        z_fx_in - ref.x_fx(1) + 1, ...
        1, ...
        [numel(ref.x_fx), 1], ...
        @sum, 0);

    expCounts = N_in * ref.pmf_range_norm(:);
    [obs_m, exp_m] = merge_adjacent_bins_for_chi2(obs, expCounts, minExp);

    chi2_stat = sum((obs_m - exp_m).^2 ./ (exp_m + eps));
    dof       = numel(obs_m) - 1;
    pval      = gammainc(chi2_stat/2, dof/2, 'upper');

    emp_pmf = obs / N_in;
    rel_pmf_err = abs(emp_pmf - ref.pmf_range_norm(:)) ./ max(ref.pmf_range_norm(:), eps);
    max_rel_pmf_err = max(rel_pmf_err);

    var_obs = var(z, 1);
    abs_var_err = abs(var_obs - var_target);
    rel_var_err = abs_var_err / max(var_target, eps);

    figure('Name', sprintf('Chen-style discrete validation (m=%d)', cfg.m_clt));
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    histogram(z, 60, 'Normalization','pdf'); hold on;
    xx = linspace(min(z), max(z), 1200);
    plot(xx, (1/(sigma_target*sqrt(2*pi))) * exp(-0.5*(xx/sigma_target).^2), ...
        'r-', 'LineWidth', 1.2);
    legend('hist','Gaussian','Location','best');
    title(sprintf('Histogram vs Gaussian (Chen-style, m=%d)', cfg.m_clt));
    grid on;
    xlabel('z');
    ylabel('pdf');

    nexttile;
    plot(ref.x_real, emp_pmf, 'k-', 'LineWidth', 0.8); hold on;
    plot(ref.x_real, ref.pmf_range_norm, 'r-', 'LineWidth', 1.2);
    grid on;
    xlabel('z');
    ylabel('PMF in target range');
    title('Discrete PMF: observed vs target');
    legend('empirical','target discrete Gaussian','Location','best');

    nexttile;
    emp_cdf = cumsum(emp_pmf);
    plot(ref.x_real, emp_cdf, 'k-', 'LineWidth', 1.0); hold on;
    plot(ref.x_real, ref.cdf_range_norm, 'r--', 'LineWidth', 1.2);
    grid on;
    xlabel('z');
    ylabel('CDF in target range');
    title('Discrete CDF in target range');
    legend('empirical','target discrete Gaussian','Location','best');

    nexttile;
    text(0.05,0.88, sprintf('target sigma^2 = %.8f', var_target), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.78, sprintf('observed sigma^2 = %.8f', var_obs), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.68, sprintf('abs variance error = %.8g', abs_var_err), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.58, sprintf('rel variance error = %.8g', rel_var_err), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.46, sprintf('max relative PMF error = %.8g', max_rel_pmf_err), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.34, sprintf('chi2 = %.8g', chi2_stat), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.24, sprintf('dof = %d', dof), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.14, sprintf('p = %.8g', pval), 'Units','normalized', 'FontSize', 11);
    text(0.05,0.04, sprintf('N_in_range = %d / %d', N_in, N_all), 'Units','normalized', 'FontSize', 11);
    axis off;
    title('Summary');

    fprintf('\n========== CHEN-STYLE DISCRETE VALIDATION ==========\n');
    fprintf('m                       = %d\n', cfg.m_clt);
    fprintf('target range            = [%.3f, %.3f]\n', -t_sigma*sigma_target, t_sigma*sigma_target);
    fprintf('samples in range        = %d / %d\n', N_in, N_all);
    fprintf('target variance         = %.8f\n', var_target);
    fprintf('observed variance       = %.8f\n', var_obs);
    fprintf('abs variance error      = %.8g\n', abs_var_err);
    fprintf('rel variance error      = %.8g\n', rel_var_err);
    fprintf('max relative PMF error  = %.8g\n', max_rel_pmf_err);
    fprintf('chi2 stat               = %.8g\n', chi2_stat);
    fprintf('chi2 dof                = %d\n', dof);
    fprintf('chi2 p-value            = %.8g\n', pval);
    fprintf('H0 rejected @ alpha=%.3f ? %s\n', ...
        cfg.chen_alpha, ternary_str(pval < cfg.chen_alpha, 'yes', 'no'));

    if cfg.chen_report_pmf_error
        fprintf('\n----- Chen-style variance table row -----\n');
        fprintf('Expected sigma^2 : %.6f\n', var_target);
        fprintf('Observed sigma^2 : %.6f\n', var_obs);
        fprintf('Absolute error   : %.6g\n', abs_var_err);
        fprintf('Relative error   : %.6g\n', rel_var_err);
    end
end

%% ============================================================
function ref = build_discrete_gaussian_reference_fixedpoint(Q, TB, sigma_target, t_sigma)

    delta = 2^(-Q);

    fx_min_lim = -2^(TB-1);
    fx_max_lim =  2^(TB-1) - 1;

    x_min = max(ceil((-t_sigma * sigma_target) / delta), fx_min_lim);
    x_max = min(floor(( t_sigma * sigma_target) / delta), fx_max_lim);

    x_fx = (x_min:x_max).';
    x    = double(x_fx) * delta;

    pmf = normcdf_sigma(x + delta/2, sigma_target) - normcdf_sigma(x - delta/2, sigma_target);
    pmf(pmf < 0) = 0;

    pmf_sum = sum(pmf);
    if pmf_sum <= 0
        error('Reference PMF sum is non-positive.');
    end

    pmf_range_norm = pmf / pmf_sum;
    cdf_range_norm = cumsum(pmf_range_norm);

    ref = struct();
    ref.x_fx           = x_fx;
    ref.x_real         = x;
    ref.delta          = delta;
    ref.pmf_raw        = pmf;
    ref.pmf_range_norm = pmf_range_norm;
    ref.cdf_range_norm = cdf_range_norm;
end

function y = normcdf_sigma(x, sigma)
    y = 0.5 * (1 + erf(x ./ (sigma * sqrt(2))));
end

function [obs_m, exp_m] = merge_adjacent_bins_for_chi2(obs, expCounts, minExp)

    obs = obs(:);
    expCounts = expCounts(:);

    obs_m = [];
    exp_m = [];

    accO = 0;
    accE = 0;

    for k = 1:numel(obs)
        accO = accO + obs(k);
        accE = accE + expCounts(k);

        if accE >= minExp
            obs_m(end+1,1) = accO; %#ok<AGROW>
            exp_m(end+1,1) = accE; %#ok<AGROW>
            accO = 0;
            accE = 0;
        end
    end

    if accE > 0
        if isempty(exp_m)
            obs_m = accO;
            exp_m = accE;
        else
            obs_m(end) = obs_m(end) + accO;
            exp_m(end) = exp_m(end) + accE;
        end
    end
end

function s = ternary_str(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end

%% ============================================================
function ref = build_bittrue_fixedpoint_reference(m, u_bits, Q, TB, gain_fx)

    Nlev = 2^u_bits;

    p1 = ones(1, Nlev) / Nlev;

    Llin = m * (Nlev - 1) + 1;
    Lfft = 2^nextpow2(Llin);

    P1 = fft(p1, Lfft);
    pmf_sum = real(ifft(P1 .^ m));
    pmf_sum = pmf_sum(1:Llin);

    pmf_sum(pmf_sum < 0) = 0;
    pmf_sum = pmf_sum / sum(pmf_sum);

    sum_vals = int64(0:(numel(pmf_sum)-1));
    center_const = int64((m/2) * (Nlev - 1));
    center_vals  = sum_vals - center_const;

    z_fx_vals = bitshift(center_vals * int64(gain_fx), -Q);

    z_fx_vals(z_fx_vals >  2^(TB-1)-1) =  2^(TB-1)-1;
    z_fx_vals(z_fx_vals < -2^(TB-1))   = -2^(TB-1);

    [z_fx_uniq, ~, ic] = unique(z_fx_vals(:));
    pmf_z = accumarray(ic, pmf_sum(:), [], @sum);
    cdf_z = cumsum(pmf_z);

    ref = struct();
    ref.z_fx   = double(z_fx_uniq(:));
    ref.z      = ref.z_fx / 2^Q;
    ref.pmf    = pmf_z(:);
    ref.cdf    = cdf_z(:);

    if numel(ref.z) >= 2
        ref.z_step = median(diff(ref.z));
    else
        ref.z_step = 1 / 2^Q;
    end
end

%% ============================================================
function [D, p_approx] = ks_against_bittrue_ref(z_fx, ref)

    z_sorted = sort(double(z_fx(:)));
    n        = numel(z_sorted);

    xq = [ref.z_fx(1)-1; ref.z_fx(:); ref.z_fx(end)+1];
    yq = [0; ref.cdf(:); 1];

    Fth = interp1(xq, yq, z_sorted, 'previous', 'extrap');
    Fn  = (1:n)' / n;

    D1 = max(abs(Fn - Fth));
    D2 = max(abs([0; Fn(1:end-1)] - Fth));
    D  = max(D1, D2);

    p_approx = 2 * exp(-2*n*D^2);
    p_approx = min(max(p_approx,0),1);
end

%% ============================================================
function out = chi_square_gof_bittrue_ref(z_fx, ref, num_bins)

    p_edges = linspace(0,1,num_bins+1);
    edges   = zeros(1, num_bins+1);
    edges(1)   = -inf;
    edges(end) = inf;

    for k = 2:num_bins
        idx = find(ref.cdf >= p_edges(k), 1, 'first');
        if isempty(idx)
            edges(k) = edges(k-1) + 1;
        else
            edges(k) = ref.z_fx(idx) + 0.5;
        end
    end

    for k = 2:num_bins
        if edges(k) <= edges(k-1)
            edges(k) = edges(k-1) + 1e-9;
        end
    end

    obs = histcounts(double(z_fx(:)), edges);
    n   = numel(z_fx);
    expCounts = (n / num_bins) * ones(1, num_bins);

    chi2_stat = sum((obs - expCounts).^2 ./ (expCounts + eps));
    dof       = num_bins - 1;
    pval      = gammainc(chi2_stat/2, dof/2, 'upper');

    out = struct();
    out.stat = chi2_stat;
    out.dof  = dof;
    out.p    = pval;
end

%% ============================================================
function out = chi_square_gof_gaussian_ref(z, num_bins)

    z = z(:);
    n = numel(z);

    p_edges = linspace(0, 1, num_bins + 1);
    q_inner = sqrt(2) * erfinv(2*p_edges(2:end-1) - 1);
    edges   = [-inf, q_inner, inf];

    obs = histcounts(z, edges);
    expCounts = (n / num_bins) * ones(1, num_bins);

    chi2_stat = sum((obs - expCounts).^2 ./ (expCounts + eps));
    dof       = num_bins - 1;
    pval      = gammainc(chi2_stat/2, dof/2, 'upper');

    out = struct();
    out.stat             = chi2_stat;
    out.dof              = dof;
    out.p                = pval;
    out.num_bins         = num_bins;
    out.expected_per_bin = n / num_bins;
end

%% ============================================================
function validate_tail_counts_bittrue(z_fx, cfg, clt_gain_fx, ref)

    if isempty(z_fx), return; end

    z = q_to_real(z_fx, cfg.frac_bits);
    thresholds = cfg.tail_thresholds(:).';
    nT = numel(thresholds);

    p_emp = zeros(1,nT);
    p_gau = zeros(1,nT);
    p_bt  = nan(1,nT);
    p_fm  = nan(1,nT);

    use_bittrue_exact  = (cfg.m_clt <= cfg.max_bittrue_exact_m);
    use_finite_m_exact = cfg.enable_finite_m_exact && (cfg.m_clt <= cfg.max_finite_m_exact);

    if use_bittrue_exact && isempty(ref)
        ref = build_bittrue_fixedpoint_reference(cfg.m_clt, cfg.u_bits, cfg.frac_bits, cfg.total_bits, clt_gain_fx);
    end

    for i = 1:nT
        t = thresholds(i);
        p_emp(i) = mean(abs(z) > t);
        p_gau(i) = 2 * qfunc_custom(t);

        if use_bittrue_exact
            p_bt(i) = sum(ref.pmf(abs(ref.z) > t));
        end

        if use_finite_m_exact
            p_fm(i) = 1 - (irwinhall_std_cdf(t, cfg.m_clt) - irwinhall_std_cdf(-t, cfg.m_clt));
        end
    end

    fprintf('\n========== TAIL COUNTS ==========\n');

    if use_bittrue_exact && use_finite_m_exact
        fprintf('%8s %18s %18s %18s %18s\n', ...
            'thr', 'empirical', 'bit-true ideal', 'finite-m exact', 'Gaussian');
        for i = 1:nT
            fprintf('%8.2f %18.8e %18.8e %18.8e %18.8e\n', ...
                thresholds(i), p_emp(i), p_bt(i), p_fm(i), p_gau(i));
        end
    elseif use_bittrue_exact
        fprintf('%8s %18s %18s %18s\n', ...
            'thr', 'empirical', 'bit-true ideal', 'Gaussian');
        for i = 1:nT
            fprintf('%8.2f %18.8e %18.8e %18.8e\n', ...
                thresholds(i), p_emp(i), p_bt(i), p_gau(i));
        end
    elseif use_finite_m_exact
        fprintf('%8s %18s %18s %18s\n', ...
            'thr', 'empirical', 'finite-m exact', 'Gaussian');
        for i = 1:nT
            fprintf('%8.2f %18.8e %18.8e %18.8e\n', ...
                thresholds(i), p_emp(i), p_fm(i), p_gau(i));
        end
    else
        fprintf('%8s %18s %18s\n', ...
            'thr', 'empirical', 'Gaussian');
        for i = 1:nT
            fprintf('%8.2f %18.8e %18.8e\n', ...
                thresholds(i), p_emp(i), p_gau(i));
        end
    end

    figure('Name','Tail probability comparison');
    semilogy(thresholds, max(p_emp,1e-16), 'ko-','LineWidth',1.2); hold on;

    legend_list = {'empirical'};

    if use_bittrue_exact
        semilogy(thresholds, max(p_bt,1e-16), 'bs-','LineWidth',1.2);
        legend_list{end+1} = 'bit-true ideal';
    end

    if use_finite_m_exact
        semilogy(thresholds, max(p_fm,1e-16), 'gd-','LineWidth',1.2);
        legend_list{end+1} = 'finite-m exact';
    end

    semilogy(thresholds, max(p_gau,1e-16), 'r^-','LineWidth',1.2);
    legend_list{end+1} = 'Gaussian';

    grid on;
    xlabel('Threshold (|z| > t)');
    ylabel('Probability');
    title(sprintf('Tail probability comparison (m=%d)', cfg.m_clt));
    legend(legend_list, 'Location','best');
end

%% ============================================================
function validate_whiteness(z, maxLag)
    if isempty(z), return; end

    z = z(:) - mean(z);
    v = mean(z.^2) + eps;

    lags = -maxLag:maxLag;
    ac   = zeros(size(lags));

    for idx = 1:length(lags)
        lag = lags(idx);
        if lag >= 0
            a = z(1:end-lag);
            b = z(1+lag:end);
        else
            lag = -lag;
            a = z(1+lag:end);
            b = z(1:end-lag);
        end
        ac(idx) = mean(a .* b) / v;
    end

    nfft = 2^nextpow2(length(z));
    Zf   = fft(z, nfft);
    Pxx  = abs(Zf).^2;
    Pxx  = Pxx(1:nfft/2+1);
    Pxx  = Pxx / (mean(Pxx) + eps);
    f    = linspace(0, 0.5, numel(Pxx));

    figure('Name','Whiteness validation');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    stem(lags, ac, 'filled');
    grid on;
    xlabel('Lag');
    ylabel('Normalized autocorrelation');
    title('Autocorrelation');

    nexttile;
    plot(f, 10*log10(Pxx + eps), 'LineWidth',1.0);
    grid on;
    xlabel('Normalized frequency');
    ylabel('Relative PSD (dB)');
    title('PSD flatness check');
end

%% ============================================================
function validate_lane_correlation(U)
    if isempty(U), return; end

    C = corrcoef(U);

    figure('Name','Lane correlation heatmap');
    imagesc(C);
    axis image;
    colorbar;
    title('Correlation matrix across CLT lanes');
    xlabel('Lane index');
    ylabel('Lane index');

    fprintf('\n========== LANE CORRELATION ==========\n');
    disp(C);
end

%% ============================================================
function [y_fx, d_hat, e_fx, W_hist, B_hist, w_final, b_final, aux] = dfe_lms_pam_fp_core(r_fx, d_fx, cfg)

    Q   = cfg.frac_bits;          % external system format: Q4.12
    TB  = cfg.total_bits;         % external system width : 16 bits
    N   = length(r_fx);
    Nf  = cfg.Nf;
    Nb  = cfg.Nb;

    % --------------------------------------------------------
    % Internal adaptation format (ONLY for update path)
    % External datapath / visible taps remain Q4.12
    % --------------------------------------------------------
    if ~isfield(cfg,'adapt_frac_bits') || isempty(cfg.adapt_frac_bits)
        cfg.adapt_frac_bits = 20;
    end
    if ~isfield(cfg,'adapt_total_bits') || isempty(cfg.adapt_total_bits)
        cfg.adapt_total_bits = 40;
    end
    if ~isfield(cfg,'init_main_tap') || isempty(cfg.init_main_tap)
        cfg.init_main_tap = 0.75;
    end
    if ~isfield(cfg,'init_fb_tap') || isempty(cfg.init_fb_tap)
        cfg.init_fb_tap = 0.0;
    end

    QACC  = cfg.adapt_frac_bits;
    TBACC = cfg.adapt_total_bits;

    use_sm_sign = any(strcmpi(cfg.eq_variant, {'sm_sign','sm_sign_lms','lms_sm_sign'}));
    use_robust  = any(strcmpi(cfg.eq_variant, {'robust','robust_proj'}));
    use_proj    = any(strcmpi(cfg.eq_variant, {'proj','robust_proj'}));
    debug_on    = isfield(cfg,'enable_eq_debug') && cfg.enable_eq_debug;

    x_buf  = int32(zeros(Nf,1));
    fb_buf = int32(zeros(Nb,1));

    % --------------------------------------------------------
    % Visible taps used by the system datapath: STILL Q4.12
    % --------------------------------------------------------
    w = int32(zeros(Nf,1));
    w(min(Nf, cfg.D+1)) = q_from_real_scalar(cfg.init_main_tap, Q, TB);

    if Nb > 0
        b = int32(zeros(Nb,1));
        b(1) = q_from_real_scalar(cfg.init_fb_tap, Q, TB);
    else
        b = int32([]);
    end

    % --------------------------------------------------------
    % Internal accumulators used only for adaptation
    % --------------------------------------------------------
    w_acc = q_convert_i32_to_i64(w, Q, QACC, TBACC);
    if Nb > 0
        b_acc = q_convert_i32_to_i64(b, Q, QACC, TBACC);
    else
        b_acc = int64([]);
    end

    err_clip_fx = q_from_real_scalar(cfg.err_clip,    Q, TB);
    gate_fx     = q_from_real_scalar(cfg.dd_gate_err, Q, TB);

    if ~isfield(cfg,'sm_sign_err_bound') || isempty(cfg.sm_sign_err_bound)
        cfg.sm_sign_err_bound = 0.75;
    end
    if ~isfield(cfg,'sm_sign_update_amp') || isempty(cfg.sm_sign_update_amp)
        cfg.sm_sign_update_amp = 1.0;
    end
    sm_sign_bound_fx = q_from_real_scalar(cfg.sm_sign_err_bound,  Q, TB);
    sm_sign_unit_fx  = q_from_real_scalar(cfg.sm_sign_update_amp, Q, TB);

    w_min_acc = q_from_real_i64(cfg.w_min(:), QACC, TBACC);
    w_max_acc = q_from_real_i64(cfg.w_max(:), QACC, TBACC);

    if Nb > 0
        b_min_acc = q_from_real_i64(cfg.b_min(:), QACC, TBACC);
        b_max_acc = q_from_real_i64(cfg.b_max(:), QACC, TBACC);
    else
        b_min_acc = int64([]);
        b_max_acc = int64([]);
    end

    y_fx  = int32(zeros(N,1));
    e_fx  = int32(zeros(N,1));
    d_hat = zeros(N,1);

    if cfg.store_dfe_history
        W_hist = zeros(Nf, N);
        B_hist = zeros(Nb, N);
    else
        W_hist = [];
        B_hist = [];
    end

    if cfg.collect_learning_trace
        nTrace = floor((N-1)/cfg.trace_decim) + 1;
        e2_trace       = zeros(nTrace,1);
        tap_norm_trace = zeros(nTrace,1);
        theta_trace    = zeros(Nf+Nb, nTrace);
        trace_n        = zeros(nTrace,1);
        it = 0;
    else
        e2_trace       = [];
        tap_norm_trace = [];
        theta_trace    = [];
        trace_n        = [];
    end

    if debug_on
        dbg = struct();
        dbg.x_buf         = zeros(N, Nf, 'int32');
        dbg.fb_buf        = zeros(N, Nb, 'int32');

        dbg.w_before      = zeros(N, Nf, 'int32');
        dbg.w_after       = zeros(N, Nf, 'int32');
        dbg.b_before      = zeros(N, Nb, 'int32');
        dbg.b_after       = zeros(N, Nb, 'int32');

        dbg.w_acc_before  = zeros(N, Nf, 'int64');
        dbg.w_acc_after   = zeros(N, Nf, 'int64');
        dbg.b_acc_before  = zeros(N, Nb, 'int64');
        dbg.b_acc_after   = zeros(N, Nb, 'int64');

        dbg.delta_w_acc   = zeros(N, Nf, 'int64');
        dbg.delta_b_acc   = zeros(N, Nb, 'int64');

        dbg.d_des_fx      = zeros(N, 1, 'int32');
        dbg.e_raw_fx      = zeros(N, 1, 'int32');
        dbg.e_up_fx       = zeros(N, 1, 'int32');
        dbg.mu_acc        = zeros(N, 1, 'int64');

        dbg.do_update     = false(N,1);
        dbg.proj_hits     = zeros(N,1);

        dbg.ff_term_acc   = zeros(N, Nf, 'int64');   % raw int64 products before >>Q
        dbg.ff_term_fx    = zeros(N, Nf, 'int32');   % each FFE term after q_sat(bitshift(...,-Q),TB)
        dbg.fb_term_acc   = zeros(N, Nb, 'int64');   % raw int64 products before >>Q
        dbg.fb_term_fx    = zeros(N, Nb, 'int32');   % each DFE term after q_sat(bitshift(...,-Q),TB)

        dbg.sum_ff_acc    = zeros(N, 1, 'int64');    % sum of raw FFE products
        dbg.sum_fb_acc    = zeros(N, 1, 'int64');    % sum of raw DFE products
        dbg.acc_total     = zeros(N, 1, 'int64');    % raw accumulator before >>Q
        dbg.y_from_acc    = zeros(N, 1, 'int32');    % old accumulator-based y for diagnostics only

        dbg.sum_ff_fx     = zeros(N, 1, 'int32');    % sum of quantized FFE terms
        dbg.sum_fb_fx     = zeros(N, 1, 'int32');    % sum of quantized DFE terms
        dbg.i_slicer_like = zeros(N, 1, 'int32');    % RTL-like pre-slicer value used as y_fx
    else
        dbg = struct();
    end

    use_polyak       = isfield(cfg,'use_polyak_avg') && cfg.use_polyak_avg;
    polyak_start_idx = max(1, floor(cfg.polyak_start_frac * N));

    if use_polyak
        sum_w_acc = int64(zeros(Nf,1));
        sum_b_acc = int64(zeros(Nb,1));
        cnt_avg   = int64(0);
    else
        sum_w_acc = int64([]);
        sum_b_acc = int64([]);
        cnt_avg   = int64(0);
    end

    proj_count_total   = 0;
    proj_active_steps  = 0;
    update_steps       = 0;
    clip_active_count  = 0;
    dd_gate_skip_count = 0;
    sm_sign_skip_count = 0;
    sm_sign_active_count = 0;
    max_tap_norm_real  = 0;

    for n = 1:N
        x_buf = [r_fx(n); x_buf(1:end-1)];

        if n > 1
            d_prev_fx = q_from_real_scalar(d_hat(n-1), Q, TB);
        else
            d_prev_fx = int32(0);
        end

        if Nb > 0
            fb_buf = [d_prev_fx; fb_buf(1:end-1)];
        end

        if debug_on
            dbg.x_buf(n,:)        = x_buf.';
            if Nb > 0
                dbg.fb_buf(n,:)   = fb_buf.';
            end

            dbg.w_before(n,:)     = w.';
            dbg.w_acc_before(n,:) = w_acc.';

            if Nb > 0
                dbg.b_before(n,:)     = b.';
                dbg.b_acc_before(n,:) = b_acc.';
            end
        end

        % ----------------------------------------------------
        % Filtering path: use sum of already-quantized terms
        % to match RTL ordering more closely
        % ----------------------------------------------------
        ff_term_acc    = int64(zeros(Nf,1));
        ff_term_fx     = int32(zeros(Nf,1));
        sum_ff_acc_i64 = int64(0);
        sum_ff_fx_i64  = int64(0);

        for k = 1:Nf
            ff_term_acc(k) = int64(w(k)) * int64(x_buf(k));
            ff_term_fx(k)  = q_sat(bitshift(ff_term_acc(k), -Q), TB);

            sum_ff_acc_i64 = sum_ff_acc_i64 + ff_term_acc(k);
            sum_ff_fx_i64  = sum_ff_fx_i64 + int64(ff_term_fx(k));
        end

        fb_term_acc    = int64(zeros(Nb,1));
        fb_term_fx     = int32(zeros(Nb,1));
        sum_fb_acc_i64 = int64(0);
        sum_fb_fx_i64  = int64(0);

        for k = 1:Nb
            fb_term_acc(k) = int64(b(k)) * int64(fb_buf(k));
            fb_term_fx(k)  = q_sat(bitshift(fb_term_acc(k), -Q), TB);

            sum_fb_acc_i64 = sum_fb_acc_i64 + fb_term_acc(k);
            sum_fb_fx_i64  = sum_fb_fx_i64 + int64(fb_term_fx(k));
        end

        % Old accumulator-based quantity kept only for diagnostics
        acc = sum_ff_acc_i64 - sum_fb_acc_i64;
        y_from_acc_fx = q_sat(bitshift(acc, -Q), TB);

        % New main datapath quantity: sum of already-quantized terms
        sum_ff_fx = q_sat(sum_ff_fx_i64, TB);
        sum_fb_fx = q_sat(sum_fb_fx_i64, TB);
        i_slicer_like_fx = q_sat(sum_ff_fx_i64 - sum_fb_fx_i64, TB);

        y_fx(n) = i_slicer_like_fx;

        if debug_on
            dbg.ff_term_acc(n,:) = ff_term_acc.';
            dbg.ff_term_fx(n,:)  = ff_term_fx.';
            if Nb > 0
                dbg.fb_term_acc(n,:) = fb_term_acc.';
                dbg.fb_term_fx(n,:)  = fb_term_fx.';
            end

            dbg.sum_ff_acc(n)    = sum_ff_acc_i64;
            dbg.sum_fb_acc(n)    = sum_fb_acc_i64;
            dbg.acc_total(n)     = acc;
            dbg.y_from_acc(n)    = y_from_acc_fx;

            dbg.sum_ff_fx(n)     = sum_ff_fx;
            dbg.sum_fb_fx(n)     = sum_fb_fx;
            dbg.i_slicer_like(n) = i_slicer_like_fx;
        end

        y_real   = q_to_real_scalar(y_fx(n), Q);
        d_hat(n) = pam_slice_scalar(y_real, cfg.A);

        if n - cfg.D >= 1
            if n <= cfg.trainLen
                d_des_fx = d_fx(n-cfg.D);
            else
                d_des_fx = q_from_real_scalar(d_hat(n), Q, TB);
            end
        else
            d_des_fx = int32(0);
        end

        e_raw_fx = q_sub(d_des_fx, y_fx(n), TB);
        e_fx(n)  = e_raw_fx;

        if use_sm_sign
            e_up_fx = sign_i32_q(e_raw_fx, sm_sign_unit_fx);
        elseif use_robust && cfg.use_error_clip
            e_up_fx = clip_sym_i32(e_raw_fx, err_clip_fx);
            if e_up_fx ~= e_raw_fx
                clip_active_count = clip_active_count + 1;
            end
        else
            e_up_fx = e_raw_fx;
        end

        if debug_on
            dbg.d_des_fx(n) = d_des_fx;
            dbg.e_raw_fx(n) = e_raw_fx;
            dbg.e_up_fx(n)  = e_up_fx;
        end

        do_update    = true;
        delta_w_acc  = int64(zeros(Nf,1));
        delta_b_acc  = int64(zeros(Nb,1));
        mu_n_acc_dbg = int64(0);
        proj_hits    = 0;

        if n > cfg.trainLen && cfg.use_dd_gate
            do_update = abs_i32(e_raw_fx) <= gate_fx;
            if ~do_update
                dd_gate_skip_count = dd_gate_skip_count + 1;
            end
        end

        if use_sm_sign
            sm_sign_update = abs_i32(e_raw_fx) > sm_sign_bound_fx;
            if do_update && sm_sign_update
                sm_sign_active_count = sm_sign_active_count + 1;
            elseif do_update && ~sm_sign_update
                sm_sign_skip_count = sm_sign_skip_count + 1;
            end
            do_update = do_update && sm_sign_update;
        end

        if do_update
            update_steps = update_steps + 1;
            mu_n_acc = get_mu_schedule_acc(n, cfg, QACC, TBACC);
            mu_n_acc_dbg = mu_n_acc;

            % -----------------------------------------------
            % Update path uses higher internal precision only
            % -----------------------------------------------
            for k = 1:Nf
                delta_acc      = lms_delta_qacc(mu_n_acc, e_up_fx, x_buf(k), Q, TBACC);
                delta_w_acc(k) = delta_acc;
                w_acc(k)       = sat_i64(w_acc(k) + delta_acc, TBACC);
            end

            for k = 1:Nb
                delta_acc      = lms_delta_qacc(mu_n_acc, e_up_fx, fb_buf(k), Q, TBACC);
                delta_b_acc(k) = delta_acc;
                b_acc(k)       = sat_i64(b_acc(k) - delta_acc, TBACC);
            end

            if use_proj
                w_before_proj = w_acc;
                b_before_proj = b_acc;

                w_acc = clip_vec_i64(w_acc, w_min_acc, w_max_acc);
                if Nb > 0
                    b_acc = clip_vec_i64(b_acc, b_min_acc, b_max_acc);
                end

                proj_hits = sum(w_before_proj ~= w_acc) + sum(b_before_proj ~= b_acc);
                proj_count_total = proj_count_total + proj_hits;

                if proj_hits > 0
                    proj_active_steps = proj_active_steps + 1;
                end
            end

            % -----------------------------------------------
            % Quantize internal accumulators back to Q4.12
            % for the visible system datapath
            % -----------------------------------------------
            w = q_convert_i64_to_i32(w_acc, QACC, Q, TB);
            if Nb > 0
                b = q_convert_i64_to_i32(b_acc, QACC, Q, TB);
            end
        end

        if debug_on
            dbg.do_update(n)     = do_update;
            dbg.mu_acc(n)        = mu_n_acc_dbg;
            dbg.proj_hits(n)     = proj_hits;

            dbg.delta_w_acc(n,:) = delta_w_acc.';
            if Nb > 0
                dbg.delta_b_acc(n,:) = delta_b_acc.';
            end

            dbg.w_after(n,:)     = w.';
            dbg.w_acc_after(n,:) = w_acc.';

            if Nb > 0
                dbg.b_after(n,:)     = b.';
                dbg.b_acc_after(n,:) = b_acc.';
            end
        end

        if cfg.store_dfe_history
            for k = 1:Nf
                W_hist(k,n) = q_to_real_scalar(w(k), Q);
            end
            for k = 1:Nb
                B_hist(k,n) = q_to_real_scalar(b(k), Q);
            end
        end

        tap_norm_real = sqrt(sum((double(w)/2^Q).^2) + sum((double(b)/2^Q).^2));
        max_tap_norm_real = max(max_tap_norm_real, tap_norm_real);

        if cfg.collect_learning_trace && mod(n-1, cfg.trace_decim) == 0
            it = it + 1;
            trace_n(it)        = n;
            e2_trace(it)       = q_to_real_scalar(e_fx(n), Q)^2;
            tap_norm_trace(it) = tap_norm_real;
            theta_trace(:,it)  = [double(w(:))/2^Q; double(b(:))/2^Q];
        end

        if use_polyak && n >= polyak_start_idx
            sum_w_acc = sum_w_acc + w_acc;
            if Nb > 0
                sum_b_acc = sum_b_acc + b_acc;
            end
            cnt_avg = cnt_avg + 1;
        end
    end

    w_final = w;
    b_final = b;

    if use_polyak && cnt_avg > 0
        w_polyak_acc = int64(round(double(sum_w_acc) / double(cnt_avg)));
        if Nb > 0
            b_polyak_acc = int64(round(double(sum_b_acc) / double(cnt_avg)));
        else
            b_polyak_acc = int64([]);
        end

        w_polyak_final = q_convert_i64_to_i32(w_polyak_acc, QACC, Q, TB);
        if Nb > 0
            b_polyak_final = q_convert_i64_to_i32(b_polyak_acc, QACC, Q, TB);
        else
            b_polyak_final = int32([]);
        end
    else
        w_polyak_final = w_final;
        b_polyak_final = b_final;
    end

    aux = struct();
    aux.proj_count_total            = proj_count_total;
    aux.proj_active_steps           = proj_active_steps;
    aux.update_steps                = update_steps;
    aux.clip_active_count           = clip_active_count;
    aux.clip_active_rate            = clip_active_count / max(1, N);
    aux.clip_active_rate_on_updates = clip_active_count / max(1, update_steps);
    aux.proj_active_rate            = proj_active_steps / max(1, N);
    aux.proj_active_rate_on_updates = proj_active_steps / max(1, update_steps);
    aux.dd_gate_skip_count          = dd_gate_skip_count;
    aux.sm_sign_skip_count          = sm_sign_skip_count;
    aux.sm_sign_active_count        = sm_sign_active_count;
    aux.sm_sign_active_rate         = sm_sign_active_count / max(1, N);
    aux.sm_sign_active_rate_on_gate = sm_sign_active_count / max(1, sm_sign_active_count + sm_sign_skip_count);
    aux.e2_trace                    = e2_trace;
    aux.tap_norm_trace              = tap_norm_trace;
    aux.theta_trace                 = theta_trace;
    aux.trace_n                     = trace_n;
    aux.max_tap_norm_real           = max_tap_norm_real;
    aux.w_polyak_final              = w_polyak_final;
    aux.b_polyak_final              = b_polyak_final;

    if debug_on
        aux.sample_debug = dbg;
    else
        aux.sample_debug = [];
    end
end

%% ============================================================
function mu_fx = get_mu_schedule_fx(n, cfg, Q, TB)
    switch lower(cfg.mu_mode)
        case 'constant'
            mu_val = cfg.mu;
        case 'decreasing'
            mu_val = cfg.mu0 / ((n + cfg.mu_n0)^cfg.mu_gamma);
        otherwise
            error('Unsupported mu_mode: %s', cfg.mu_mode);
    end
    mu_fx = q_from_real_scalar(mu_val, Q, TB);
end

function y = q_clip_vec(x, lo, hi)
    y = x;
    for k = 1:numel(x)
        if y(k) < lo(k)
            y(k) = lo(k);
        elseif y(k) > hi(k)
            y(k) = hi(k);
        end
    end
end

function y = clip_sym_i32(x, lim)
    if x > lim
        y = lim;
    elseif x < -lim
        y = -lim;
    else
        y = x;
    end
end

function y = abs_i32(x)
    if x >= 0
        y = x;
    else
        y = -x;
    end
end

function y = sign_i32_q(x, unit_fx)
    if x > 0
        y = unit_fx;
    elseif x < 0
        y = -unit_fx;
    else
        y = int32(0);
    end
end

%% ============================================================
function eye_metrics = analyze_reconstructed_eye(y_os, sps, A, qpct)

    L   = 2*sps;
    seg = floor(numel(y_os)/L);

    if seg < 10
        eye_metrics = empty_eye_metrics(A);
        return;
    end

    y_os = y_os(1:seg*L);
    X    = reshape(y_os, L, seg);

    dec_idx = sps + 1;
    y_dec   = X(dec_idx, :).';

    class_idx = amp_to_index(y_dec, A);

    mu_cls  = nan(numel(A),1);
    sig_cls = nan(numel(A),1);
    q05_cls = nan(numel(A),1);
    q95_cls = nan(numel(A),1);

    for k = 1:numel(A)
        vk = y_dec(class_idx == k);
        if ~isempty(vk)
            mu_cls(k)  = mean(vk);
            sig_cls(k) = std(vk, 1);
            q05_cls(k) = prctile(vk, qpct);
            q95_cls(k) = prctile(vk, 100-qpct);
        end
    end

    eye_heights = nan(numel(A)-1,1);
    for k = 1:numel(A)-1
        if ~(isnan(q95_cls(k)) || isnan(q05_cls(k+1)))
            eye_heights(k) = q05_cls(k+1) - q95_cls(k);
        end
    end

    thr = nan(numel(A)-1,1);
    for k = 1:numel(A)-1
        if ~(isnan(mu_cls(k)) || isnan(mu_cls(k+1)))
            thr(k) = 0.5*(mu_cls(k) + mu_cls(k+1));
        end
    end

    width_ui   = nan(numel(thr),1);
    cross_stat = repmat(struct( ...
        'left_mean_ui', nan, ...
        'left_rms_ui', nan, ...
        'left_pp_ui', nan, ...
        'left_count', 0, ...
        'right_mean_ui', nan, ...
        'right_rms_ui', nan, ...
        'right_pp_ui', nan, ...
        'right_count', 0), numel(thr), 1);

    for ith = 1:numel(thr)
        if isnan(thr(ith))
            continue;
        end

        left_times  = [];
        right_times = [];

        for col = 1:seg
            x = X(:,col);

            tc_all = crossing_times_linear(x, sps, thr(ith));
            if isempty(tc_all)
                continue;
            end

            left_cand  = tc_all(tc_all < 1);
            right_cand = tc_all(tc_all > 1);

            if ~isempty(left_cand)
                left_times(end+1,1) = left_cand(end); %#ok<AGROW>
            end
            if ~isempty(right_cand)
                right_times(end+1,1) = right_cand(1); %#ok<AGROW>
            end
        end

        if numel(left_times) >= 5 && numel(right_times) >= 5
            width_ui(ith) = prctile(right_times, qpct) - prctile(left_times, 100-qpct);
        end

        cross_stat(ith) = crossing_stats_from_times(left_times, right_times);
    end

    eye_metrics = struct();
    eye_metrics.decision_ui             = 1.0;
    eye_metrics.decision_sample_index   = dec_idx;
    eye_metrics.cluster_mean            = mu_cls;
    eye_metrics.cluster_std             = sig_cls;
    eye_metrics.cluster_q_low           = q05_cls;
    eye_metrics.cluster_q_high          = q95_cls;
    eye_metrics.eye_height_each         = eye_heights;

    valid_heights = eye_heights(~isnan(eye_heights));
    if isempty(valid_heights)
        eye_metrics.eye_height_at_decision = nan;
    else
        eye_metrics.eye_height_at_decision = min(valid_heights);
    end

    eye_metrics.threshold_levels        = thr;
    eye_metrics.eye_width_ui            = width_ui;
    eye_metrics.crossing_stats          = cross_stat;
end

function out = crossing_stats_from_times(left_times, right_times)
    out = struct( ...
        'left_mean_ui', nan, ...
        'left_rms_ui', nan, ...
        'left_pp_ui', nan, ...
        'left_count', 0, ...
        'right_mean_ui', nan, ...
        'right_rms_ui', nan, ...
        'right_pp_ui', nan, ...
        'right_count', 0);

    if ~isempty(left_times)
        out.left_mean_ui = mean(left_times);
        out.left_rms_ui  = std(left_times, 1);
        out.left_pp_ui   = max(left_times) - min(left_times);
        out.left_count   = numel(left_times);
    end

    if ~isempty(right_times)
        out.right_mean_ui = mean(right_times);
        out.right_rms_ui  = std(right_times, 1);
        out.right_pp_ui   = max(right_times) - min(right_times);
        out.right_count   = numel(right_times);
    end
end

function tc = crossing_times_linear(x, sps, thr)
    x = x(:);
    tc = [];

    for n = 1:numel(x)-1
        y1 = x(n)   - thr;
        y2 = x(n+1) - thr;

        if y1 == 0
            tc(end+1,1) = (n-1)/sps; %#ok<AGROW>
        end

        if y1 * y2 < 0
            frac = y1 / (y1 - y2);
            tc(end+1,1) = ((n-1) + frac) / sps; %#ok<AGROW>
        end
    end
end

function eye_metrics = empty_eye_metrics(A)
    nEye = numel(A)-1;
    eye_metrics = struct();
    eye_metrics.decision_ui             = 1.0;
    eye_metrics.decision_sample_index   = nan;
    eye_metrics.cluster_mean            = nan(numel(A),1);
    eye_metrics.cluster_std             = nan(numel(A),1);
    eye_metrics.cluster_q_low           = nan(numel(A),1);
    eye_metrics.cluster_q_high          = nan(numel(A),1);
    eye_metrics.eye_height_each         = nan(nEye,1);
    eye_metrics.eye_height_at_decision  = nan;
    eye_metrics.threshold_levels        = nan(nEye,1);
    eye_metrics.eye_width_ui            = nan(nEye,1);
    eye_metrics.crossing_stats          = repmat(struct( ...
        'left_mean_ui', nan, ...
        'left_rms_ui', nan, ...
        'left_pp_ui', nan, ...
        'left_count', 0, ...
        'right_mean_ui', nan, ...
        'right_rms_ui', nan, ...
        'right_pp_ui', nan, ...
        'right_count', 0), nEye, 1);
end

%% ============================================================
function slicer_metrics = analyze_slicer_clusters(y_float, d, D, A)

    y_float = y_float(:);
    d       = d(:);

    if D < 0
        error('D must be nonnegative.');
    end

    if numel(y_float) <= D + 10 || numel(d) <= D + 10
        slicer_metrics = empty_slicer_metrics(A);
        return;
    end

    y_valid = y_float(D+1:end);
    d_tx    = d(1:end-D);

    cls_tx  = amp_to_index(d_tx, A);
    mu_cls  = nan(numel(A),1);
    sig_cls = nan(numel(A),1);

    for k = 1:numel(A)
        vk = y_valid(cls_tx == k);
        if ~isempty(vk)
            mu_cls(k)  = mean(vk);
            sig_cls(k) = std(vk, 1);
        end
    end

    mu_per_sample = nan(size(y_valid));
    for n = 1:numel(y_valid)
        mu_per_sample(n) = mu_cls(cls_tx(n));
    end

    noise_res = y_valid - mu_per_sample;

    signal_var = var(mu_per_sample, 1);
    noise_var  = var(noise_res, 1);

    if noise_var > 0
        snr_lin = signal_var / noise_var;
        snr_db  = 10*log10(snr_lin);
    else
        snr_lin = inf;
        snr_db  = inf;
    end

    slicer_metrics = struct();
    slicer_metrics.cluster_mean = mu_cls;
    slicer_metrics.cluster_std  = sig_cls;
    slicer_metrics.signal_var   = signal_var;
    slicer_metrics.noise_var    = noise_var;
    slicer_metrics.snr_lin      = snr_lin;
    slicer_metrics.snr_db       = snr_db;
end

function slicer_metrics = empty_slicer_metrics(A)
    slicer_metrics = struct();
    slicer_metrics.cluster_mean = nan(numel(A),1);
    slicer_metrics.cluster_std  = nan(numel(A),1);
    slicer_metrics.signal_var   = nan;
    slicer_metrics.noise_var    = nan;
    slicer_metrics.snr_lin      = nan;
    slicer_metrics.snr_db       = nan;
end

function app = summarize_app_metrics(eye_metrics, slicer_metrics)

    app = struct();

    app.worst_eye_height   = nanmin_safe(eye_metrics.eye_height_each);
    app.worst_eye_width_ui = nanmin_safe(eye_metrics.eye_width_ui);

    left_rms  = arrayfun(@(s) s.left_rms_ui,  eye_metrics.crossing_stats);
    right_rms = arrayfun(@(s) s.right_rms_ui, eye_metrics.crossing_stats);
    left_pp   = arrayfun(@(s) s.left_pp_ui,   eye_metrics.crossing_stats);
    right_pp  = arrayfun(@(s) s.right_pp_ui,  eye_metrics.crossing_stats);

    app.worst_crossing_rms_ui = nanmax_safe([left_rms(:); right_rms(:)]);
    app.worst_crossing_pp_ui  = nanmax_safe([left_pp(:);  right_pp(:)]);

    app.slicer_snr_db = slicer_metrics.snr_db;
    app.signal_var    = slicer_metrics.signal_var;
    app.noise_var     = slicer_metrics.noise_var;
end

function print_pre_post_app_metrics(pre, post, tag)
    fprintf('--- Application-level PAM4 validation (%s) ---\n', tag);

    fprintf('Pre-EQ : worst eye height = %.6f, worst eye width = %.6f UI, ', ...
        pre.worst_eye_height, pre.worst_eye_width_ui);
    fprintf('worst crossing RMS = %.6f UI, slicer SNR = %.6f dB\n', ...
        pre.worst_crossing_rms_ui, pre.slicer_snr_db);

    fprintf('Post-EQ: worst eye height = %.6f, worst eye width = %.6f UI, ', ...
        post.worst_eye_height, post.worst_eye_width_ui);
    fprintf('worst crossing RMS = %.6f UI, slicer SNR = %.6f dB\n', ...
        post.worst_crossing_rms_ui, post.slicer_snr_db);

    fprintf('Delta  : eye height = %+ .6f, eye width = %+ .6f UI, ', ...
        post.worst_eye_height - pre.worst_eye_height, ...
        post.worst_eye_width_ui - pre.worst_eye_width_ui);
    fprintf('crossing RMS = %+ .6f UI, slicer SNR = %+ .6f dB\n', ...
        post.worst_crossing_rms_ui - pre.worst_crossing_rms_ui, ...
        post.slicer_snr_db - pre.slicer_snr_db);
end

function y = nanmin_safe(x)
    x = x(~isnan(x));
    if isempty(x)
        y = nan;
    else
        y = min(x);
    end
end

function y = nanmax_safe(x)
    x = x(~isnan(x));
    if isempty(x)
        y = nan;
    else
        y = max(x);
    end
end

%% ============================================================
function [SER_noeq, SER_dfe, BER_noeq, BER_dfe] = ser_ber_from_decisions(d, d_noeq, d_hat, D, A, k)
    i0   = D + 1;
    d_tx = d(1:end-D);
    rx0  = d_noeq(i0:end);
    rx1  = d_hat(i0:end);

    SER_noeq = mean(rx0 ~= d_tx);
    SER_dfe  = mean(rx1 ~= d_tx);

    tx_idx  = amp_to_index(d_tx, A);
    rx0_idx = amp_to_index(rx0, A);
    rx1_idx = amp_to_index(rx1, A);

    tx_bits  = idxs_to_gray_bits_matrix(tx_idx,  k);
    rx0_bits = idxs_to_gray_bits_matrix(rx0_idx, k);
    rx1_bits = idxs_to_gray_bits_matrix(rx1_idx, k);

    BER_noeq = mean(rx0_bits(:) ~= tx_bits(:));
    BER_dfe  = mean(rx1_bits(:) ~= tx_bits(:));
end

function idx = amp_to_index(symvals, A)
    idx = zeros(numel(symvals),1);
    for n = 1:numel(symvals)
        [~, idx(n)] = min(abs(symvals(n) - A(:)));
    end
end

function B = idxs_to_gray_bits_matrix(idx_vec, k)
    N = numel(idx_vec);
    B = zeros(N,k);
    for n = 1:N
        B(n,:) = idx_to_gray_bits(idx_vec(n), k);
    end
end

function bits = idx_to_gray_bits(j, k)
    g = bitxor(j-1, floor((j-1)/2));
    bits = zeros(1,k);
    for b = 1:k
        bits(b) = bitget(g, k-b+1);
    end
end

%% ============================================================
function print_summary_table(res0, res1, cfg)
    fprintf('================ SUMMARY ================\n');
    fprintf('%-18s %-12s %-12s %-12s %-12s %-12s\n', ...
        'Case','SER NoEQ','SER DFE','BER NoEQ','BER DFE','MSE_ss');
    fprintf('%-18s %-12.3g %-12.3g %-12.3g %-12.3g %-12.3g\n', ...
        'NO-AWGN', res0.SER_noeq, res0.SER_dfe, res0.BER_noeq, res0.BER_dfe, res0.MSE_ss);
    fprintf('%-18s %-12.3g %-12.3g %-12.3g %-12.3g %-12.3g\n\n', ...
        'AWGN',    res1.SER_noeq, res1.SER_dfe, res1.BER_noeq, res1.BER_dfe, res1.MSE_ss);

    if ~isempty(res0.y_b_os) && ~isempty(res0.y_a_os) && ~isempty(res1.y_b_os) && ~isempty(res1.y_a_os)
        combined_eyes_2x2( ...
            res0.y_b_os, res0.y_a_os, ...
            res1.y_b_os, res1.y_a_os, ...
            cfg.sps_eye, cfg.SNRdB, cfg.eye_max_traces_plot);
    end

    fprintf('--- Compact application summary ---\n');
    fprintf('NO-AWGN  Pre/Post worst-eye-height : %.6f / %.6f\n', ...
        res0.app_metrics_pre.worst_eye_height, res0.app_metrics_post.worst_eye_height);
    fprintf('NO-AWGN  Pre/Post worst-eye-width  : %.6f / %.6f UI\n', ...
        res0.app_metrics_pre.worst_eye_width_ui, res0.app_metrics_post.worst_eye_width_ui);
    fprintf('NO-AWGN  Pre/Post slicer SNR       : %.6f / %.6f dB\n', ...
        res0.app_metrics_pre.slicer_snr_db, res0.app_metrics_post.slicer_snr_db);

    fprintf('AWGN     Pre/Post worst-eye-height : %.6f / %.6f\n', ...
        res1.app_metrics_pre.worst_eye_height, res1.app_metrics_post.worst_eye_height);
    fprintf('AWGN     Pre/Post worst-eye-width  : %.6f / %.6f UI\n', ...
        res1.app_metrics_pre.worst_eye_width_ui, res1.app_metrics_post.worst_eye_width_ui);
    fprintf('AWGN     Pre/Post slicer SNR       : %.6f / %.6f dB\n\n', ...
        res1.app_metrics_pre.slicer_snr_db, res1.app_metrics_post.slicer_snr_db);
end

function combined_eyes_2x2(y0b, y0a, y1b, y1a, sps, SNRdB, maxTraces)
    L   = 2*sps;
    y0b = y0b(1:floor(numel(y0b)/L)*L);
    y0a = y0a(1:floor(numel(y0a)/L)*L);
    y1b = y1b(1:floor(numel(y1b)/L)*L);
    y1a = y1a(1:floor(numel(y1a)/L)*L);

    Yall  = [y0b(:); y0a(:); y1b(:); y1a(:)];
    ylims = [min(Yall), max(Yall)];

    figure('Name','Eye — NO-AWGN (top) / AWGN (bottom) — BEFORE vs AFTER');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    nexttile; eye_plot_reshape_fixed(y0b, sps, ylims, maxTraces); title('Eye BEFORE (NO-AWGN)'); grid on;
    nexttile; eye_plot_reshape_fixed(y0a, sps, ylims, maxTraces); title('Eye AFTER  (NO-AWGN)'); grid on;
    nexttile; eye_plot_reshape_fixed(y1b, sps, ylims, maxTraces); title(sprintf('Eye BEFORE (AWGN, %.1f dB)', SNRdB)); grid on;
    nexttile; eye_plot_reshape_fixed(y1a, sps, ylims, maxTraces); title(sprintf('Eye AFTER  (AWGN, %.1f dB)', SNRdB));  grid on;
end

function eye_plot_reshape_fixed(x_os, sps, ylims, maxTraces)
    L   = 2*sps;
    seg = floor(numel(x_os)/L);
    x_os = x_os(1:seg*L);
    X    = reshape(x_os, L, seg);
    t    = (0:L-1)/sps;

    if nargin < 4
        maxTraces = 800;
    end

    if seg > maxTraces
        step = ceil(seg/maxTraces);
        X = X(:,1:step:end);
    end

    plot(t, X, 'LineWidth', 0.6);
    axis([0 2 ylims(1) ylims(2)]);
    xlabel('Time (UI)');
    ylabel('Amplitude');
end

function print_final_taps(w_final, b_final, D, Q, tag)
    w_end = double(w_final(:)) / 2^Q;
    fprintf('--- Final taps (%s) ---\n', tag);
    fprintf('FFE w:'); fprintf(' % .4f', w_end); fprintf('\nMain tap index ~ D+1 = %d\n', D+1);

    if ~isempty(b_final)
        b_end = double(b_final(:)) / 2^Q;
        fprintf('FBE b:'); fprintf(' % .4f', b_end); fprintf('\n\n');
    else
        fprintf('FBE b: [Nb=0]\n\n');
    end
end

%% ============================================================
function sweep_ser_ber_vs_snr(cfg, g_rc, snr_list)

    nS = numel(snr_list);

    SER0 = zeros(1,nS);
    SER1 = zeros(1,nS);
    BER0 = zeros(1,nS);
    BER1 = zeros(1,nS);
    MSE1 = zeros(1,nS);

    EH0  = zeros(1,nS);
    EH1  = zeros(1,nS);
    EW0  = zeros(1,nS);
    EW1  = zeros(1,nS);
    CR0  = zeros(1,nS);
    CR1  = zeros(1,nS);
    SS0  = zeros(1,nS);
    SS1  = zeros(1,nS);

    cfg_i = cfg;
    cfg_i.enable_rng_debug = false;
    cfg_i.enable_excel_log = false;
    cfg_i.verbose_case     = false;

    for i = 1:nS
        cfg_i.SNRdB = snr_list(i);
        cfg_i.seed0 = cfg.seed0 + uint32(1000*i);

        rng(1);
        sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
        d       = cfg_i.A(sym_idx);
        d       = d(:);

        res = run_case_system(d, cfg_i, g_rc, true, cfg_i.eq_variant);

        SER0(i) = res.SER_noeq;
        SER1(i) = res.SER_dfe;
        BER0(i) = res.BER_noeq;
        BER1(i) = res.BER_dfe;
        MSE1(i) = res.MSE_ss;

        EH0(i) = res.app_metrics_pre.worst_eye_height;
        EH1(i) = res.app_metrics_post.worst_eye_height;
        EW0(i) = res.app_metrics_pre.worst_eye_width_ui;
        EW1(i) = res.app_metrics_post.worst_eye_width_ui;
        CR0(i) = res.app_metrics_pre.worst_crossing_rms_ui;
        CR1(i) = res.app_metrics_post.worst_crossing_rms_ui;
        SS0(i) = res.app_metrics_pre.slicer_snr_db;
        SS1(i) = res.app_metrics_post.slicer_snr_db;
    end

    fprintf('\n========== SNR SWEEP ==========\n');
    fprintf('%8s %12s %12s %12s %12s %12s %12s %12s %12s\n', ...
        'SNR', 'EyeH_Pre', 'EyeH_Post', 'EyeW_Pre', 'EyeW_Post', ...
        'CrossRMS_Pre', 'CrossRMS_Post', 'SNR_Pre', 'SNR_Post');
    for i = 1:nS
        fprintf('%8.2f %12.6f %12.6f %12.6f %12.6f %12.6f %12.6f %12.6f %12.6f\n', ...
            snr_list(i), EH0(i), EH1(i), EW0(i), EW1(i), CR0(i), CR1(i), SS0(i), SS1(i));
    end

    fprintf('\n========== SNR SWEEP (SER/BER) ==========\n');
    fprintf('%8s %14s %14s %14s %14s %14s\n', ...
        'SNR', 'SER NoEQ', 'SER DFE', 'BER NoEQ', 'BER DFE', 'MSE_ss');
    for i = 1:nS
        fprintf('%8.2f %14.6e %14.6e %14.6e %14.6e %14.6e\n', ...
            snr_list(i), SER0(i), SER1(i), BER0(i), BER1(i), MSE1(i));
    end

    figure('Name','SER/BER vs SNR');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    semilogy(snr_list, SER0, 'o-','LineWidth',1.2); hold on;
    semilogy(snr_list, SER1, 's-','LineWidth',1.2);
    grid on;
    xlabel('Injected SNR (dB)');
    ylabel('SER');
    title('SER vs SNR');
    legend('No-EQ','DFE','Location','best');

    nexttile;
    semilogy(snr_list, BER0, 'o-','LineWidth',1.2); hold on;
    semilogy(snr_list, BER1, 's-','LineWidth',1.2);
    grid on;
    xlabel('Injected SNR (dB)');
    ylabel('BER');
    title('BER vs SNR');
    legend('No-EQ','DFE','Location','best');

    figure('Name','Application-level PAM4 validation vs SNR');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    plot(snr_list, EH0, 'o-','LineWidth',1.2); hold on;
    plot(snr_list, EH1, 's-','LineWidth',1.2);
    grid on;
    xlabel('Injected SNR (dB)');
    ylabel('Worst eye height');
    title('Eye height vs SNR');
    legend('Pre-EQ','Post-EQ','Location','best');

    nexttile;
    plot(snr_list, EW0, 'o-','LineWidth',1.2); hold on;
    plot(snr_list, EW1, 's-','LineWidth',1.2);
    grid on;
    xlabel('Injected SNR (dB)');
    ylabel('Worst eye width (UI)');
    title('Eye width vs SNR');
    legend('Pre-EQ','Post-EQ','Location','best');

    nexttile;
    plot(snr_list, CR0, 'o-','LineWidth',1.2); hold on;
    plot(snr_list, CR1, 's-','LineWidth',1.2);
    grid on;
    xlabel('Injected SNR (dB)');
    ylabel('Worst crossing RMS (UI)');
    title('Crossing spread vs SNR');
    legend('Pre-EQ','Post-EQ','Location','best');

    nexttile;
    plot(snr_list, SS0, 'o-','LineWidth',1.2); hold on;
    plot(snr_list, SS1, 's-','LineWidth',1.2);
    plot(snr_list, snr_list, 'k--','LineWidth',1.0);
    grid on;
    xlabel('Injected SNR (dB)');
    ylabel('Estimated slicer SNR (dB)');
    title('Slicer SNR vs injected SNR');
    legend('Pre-EQ','Post-EQ','y=x ref','Location','best');
end

%% ============================================================
function print_analytic_arch_summary(cfg)

    m   = cfg.m_clt;
    Nf  = cfg.Nf;
    Nb  = cfg.Nb;
    Wu  = cfg.u_bits;

    adders_clt = m - 1;
    depth_clt  = ceil(log2(m));

    fprintf('\n========== ANALYTIC ARCHITECTURE SUMMARY ==========\n');
    fprintf('CLT lanes                    : %d\n', m);
    fprintf('URNG word width              : %d bits\n', Wu);
    fprintf('Stage-1 mixing enabled       : %d\n', cfg.stage1_mix_enable);
    fprintf('Stage-1 shift/rotate         : r1 = %d, r2 = %d\n', cfg.stage1_r1, cfg.stage1_r2);
    fprintf('Stage-1 bit offsets          :'); fprintf(' %d', cfg.stage1_bit_offsets); fprintf('\n');
    fprintf('CLT adders                   : %d\n', adders_clt);
    fprintf('CLT adder-tree depth         : %d\n', depth_clt);

    fprintf('Equalizer variant            : %s\n', cfg.eq_variant);
    fprintf('FFE feedforward taps         : %d\n', Nf);
    fprintf('FBE feedback taps            : %d\n', Nb);
    fprintf('DFE multiplies / sample      : %d\n', Nf + Nb);
    fprintf('DFE adds / sample (approx)   : %d\n', Nf + Nb);
    fprintf('Robust psi(e)                : %d\n', cfg.use_error_clip);
    fprintf('Projection onto box H        : %d\n', cfg.use_proj);
    fprintf('DD gating                    : %d\n', cfg.use_dd_gate);
    fprintf('Normalization / division     : NONE\n');
    fprintf('Noise output / cycle         : 1 sample/cycle (architectural intent)\n');
    fprintf('Note                         : LUT/FF/BRAM/DSP/Fmax require synthesis report.\n');
end

%% ============================================================
function plot_multi_m_stat_summary(summary)

    mvals = [summary.m];
    meanz = [summary.mean_z];
    stdz  = [summary.std_z];
    skewz = [summary.skew_z];
    kurtz = [summary.kurt_z];
    kurtt = [summary.kurt_theory];
    gainr = [summary.clt_gain_real];

    figure('Name', 'Multi-m statistical summary');
    tiledlayout(2,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    plot(mvals, meanz, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('mean(z)');
    title('Mean vs m');

    nexttile;
    plot(mvals, stdz, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('std(z)');
    title('Std vs m');

    nexttile;
    plot(mvals, skewz, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('skew(z)');
    title('Skewness vs m');

    nexttile;
    plot(mvals, kurtz, 'o-','LineWidth',1.2); hold on;
    plot(mvals, kurtt, 's--','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('excess kurtosis');
    title('Kurtosis vs m');
    legend('measured','theory','Location','best');

    nexttile;
    plot(mvals, gainr, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('gain');
    title('Tuned gain vs m');
end

function plot_multi_m_system_summary(summary)

    mvals = [summary.m];
    ser   = [summary.SER_dfe];
    ber   = [summary.BER_dfe];
    mse   = [summary.MSE_ss];
    ehy   = [summary.eye_height_post];
    ewid  = [summary.eye_width_post];
    ssnr  = [summary.slicer_snr_post_db];

    figure('Name', 'Multi-m system summary');
    tiledlayout(2,3,'TileSpacing','compact','Padding','compact');

    nexttile;
    semilogy(mvals, ser, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('SER DFE');
    title('SER vs m');

    nexttile;
    semilogy(mvals, ber, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('BER DFE');
    title('BER vs m');

    nexttile;
    plot(mvals, mse, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('MSE_{ss}');
    title('MSE vs m');

    nexttile;
    plot(mvals, ehy, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('Worst eye height');
    title('Eye height vs m');

    nexttile;
    plot(mvals, ewid, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('Worst eye width');
    title('Eye width vs m');

    nexttile;
    plot(mvals, ssnr, 'o-','LineWidth',1.2);
    grid on;
    xlabel('m');
    ylabel('Slicer SNR (dB)');
    title('Slicer SNR vs m');
end

%% ============================================================
function stats = compute_awgn_basic_stats(z, m)
    z  = z(:);
    mu = mean(z);
    sig = std(z,1);
    sk = mean((z-mu).^3) / (sig^3 + eps);
    kt = mean((z-mu).^4) / (sig^4 + eps) - 3;
    kt_th = -6/(5*m);

    stats = struct('mu', mu, 'sig', sig, 'sk', sk, 'kt', kt, 'kt_th', kt_th);
end

%% ============================================================
function [D, p_approx] = ks_against_cdf(x, cdf_fun)
    z   = sort(x(:));
    n   = numel(z);
    Fn  = (1:n)'/n;
    Fth = cdf_fun(z);

    D1 = max(abs(Fn - Fth));
    D2 = max(abs([0; Fn(1:end-1)] - Fth));
    D  = max(D1, D2);

    p_approx = 2 * exp(-2*n*D^2);
    p_approx = min(max(p_approx,0),1);
end

function y = normcdf_approx(x)
    y = 0.5 * (1 + erf(x / sqrt(2)));
end

function y = qfunc_custom(x)
    y = 0.5 * erfc(x / sqrt(2));
end

%% ============================================================
function bit_offsets = make_stage1_bit_offsets(m, u_bits)

    max_offset = 32 - u_bits;
    nBase      = max_offset + 1;

    stride = choose_coprime_stride(nBase);
    base_set = mod((0:nBase-1) * stride, nBase);

    bit_offsets = zeros(1,m);
    for j = 1:m
        bit_offsets(j) = base_set(mod(j-1, nBase) + 1);
    end
end

function stride = choose_coprime_stride(nBase)
    candidates = [4 5 3 2 1];
    stride = 1;
    for c = candidates
        if gcd(c, nBase) == 1
            stride = c;
            return;
        end
    end
end

function validate_stage1_offsets(bit_offsets, m, u_bits)
    if numel(bit_offsets) ~= m
        error('Length of stage1_bit_offsets must equal m_clt.');
    end

    if any(bit_offsets < 0) || any(bit_offsets + u_bits > 32)
        error('Invalid stage1_bit_offsets: each b_i must satisfy 0 <= b_i and b_i + u_bits <= 32.');
    end
end

%% ============================================================
function g = rc_pulse(alpha, sps, spanUI)
    t = -spanUI:1/sps:spanUI;

    sincDen = pi*t;
    sincNum = sin(pi*t);
    sincOp  = sincNum ./ sincDen;
    sincOp(abs(sincDen) < 1e-12) = 1;

    cosNum  = cos(alpha*pi*t);
    cosDen  = 1 - (2*alpha*t).^2;
    cosOp   = cosNum ./ cosDen;
    cosOp(abs(cosDen) < 1e-12) = pi/4;

    g = sincOp .* cosOp;
end

function y = upsample_zero(x, sps)
    y = zeros(numel(x)*sps, 1);
    y(1:sps:end) = x(:);
end

%% ============================================================
function s = pam_slice_scalar(y, A)
    [~, idx] = min(abs(y - A));
    s = A(idx);
end

function s = pam_slice_vec(y, A)
    s = arrayfun(@(yy) pam_slice_scalar(yy, A), y);
end

%% ============================================================
% Fixed-point helper functions
%% ============================================================

function q = q_from_real(x, Q, TB)
    maxv =  2^(TB-1) - 1;
    minv = -2^(TB-1);
    xq   = round(double(x) * 2^Q);
    xq(xq > maxv) = maxv;
    xq(xq < minv) = minv;
    q = int32(xq);
end

function q = q_from_real_scalar(x, Q, TB)
    maxv =  2^(TB-1) - 1;
    minv = -2^(TB-1);
    xq   = round(double(x) * 2^Q);
    xq   = min(max(xq, minv), maxv);
    q    = int32(xq);
end

function x = q_to_real(q, Q)
    x = double(q) / 2^Q;
end

function x = q_to_real_scalar(q, Q)
    x = double(q) / 2^Q;
end

function y = q_sat(x, TB)
    maxv = int64( 2^(TB-1) - 1 );
    minv = int64(-2^(TB-1)     );

    x64 = int64(x);
    x64(x64 > maxv) = maxv;
    x64(x64 < minv) = minv;

    y = int32(x64);
end

function y = q_add(a, b, TB)
    y = q_sat(int64(a) + int64(b), TB);
end

function y = q_sub(a, b, TB)
    y = q_sat(int64(a) - int64(b), TB);
end

function y = q_add_vec(a, b, TB)
    y = q_sat(int64(a) + int64(b), TB);
end

function y = q_mul(a, b, Q, TB)
    prod = bitshift(int64(a) * int64(b), -Q);
    y    = q_sat(prod, TB);
end

function y = q_mul_vec(a, b, Q, TB)
    prod = bitshift(int64(a) .* int64(b), -Q);
    y    = q_sat(prod, TB);
end

%% ============================================================
% Internal adaptation helpers (QACC), external system still Q4.12
%% ============================================================

function q = q_from_real_i64(x, Q, TB)
    maxv =  2^(TB-1) - 1;
    minv = -2^(TB-1);
    xq   = round(double(x) * 2^Q);
    xq(xq > maxv) = maxv;
    xq(xq < minv) = minv;
    q = int64(xq);
end

function q = q_from_real_scalar_i64(x, Q, TB)
    maxv =  2^(TB-1) - 1;
    minv = -2^(TB-1);
    xq   = round(double(x) * 2^Q);
    xq   = min(max(xq, minv), maxv);
    q    = int64(xq);
end

function y = sat_i64(x, TB)
    maxv = int64( 2^(TB-1) - 1 );
    minv = int64(-2^(TB-1)     );
    y = int64(x);
    y(y > maxv) = maxv;
    y(y < minv) = minv;
end

function y = round_shift_right_i64(x, s, TB)
    if s <= 0
        y = sat_i64(bitshift(int64(x), -s), TB);
    else
        y = sat_i64(int64(round(double(x) / 2^s)), TB);
    end
end

function y = q_convert_i32_to_i64(x, Qin, Qout, TBout)
    x64 = int64(x);
    if Qout >= Qin
        y = sat_i64(bitshift(x64, Qout - Qin), TBout);
    else
        y = round_shift_right_i64(x64, Qin - Qout, TBout);
    end
end

function y = q_convert_i64_to_i32(x, Qin, Qout, TBout)
    if Qin >= Qout
        y64 = round_shift_right_i64(x, Qin - Qout, TBout);
    else
        y64 = sat_i64(bitshift(int64(x), Qout - Qin), TBout);
    end
    y = int32(y64);
end

function y = clip_vec_i64(x, lo, hi)
    y = x;
    for k = 1:numel(x)
        if y(k) < lo(k)
            y(k) = lo(k);
        elseif y(k) > hi(k)
            y(k) = hi(k);
        end
    end
end

function mu_acc = get_mu_schedule_acc(n, cfg, QACC, TBACC)
    switch lower(cfg.mu_mode)
        case 'constant'
            mu_val = cfg.mu;
        case 'decreasing'
            mu_val = cfg.mu0 / ((n + cfg.mu_n0)^cfg.mu_gamma);
        otherwise
            error('Unsupported mu_mode: %s', cfg.mu_mode);
    end
    mu_acc = q_from_real_scalar_i64(mu_val, QACC, TBACC);
end

function delta_acc = lms_delta_qacc(mu_acc, e_q12, x_q12, Qsig, TBACC)
    % mu_acc : QACC
    % e_q12  : Qsig
    % x_q12  : Qsig
    %
    % desired real update:
    %   delta = mu * e * x
    %
    % represented in QACC:
    %   delta_acc = round( mu_acc * e_q12 * x_q12 / 2^(2*Qsig) )

    val = double(mu_acc) * double(e_q12) * double(x_q12) / 2^(2*Qsig);
    delta_acc = sat_i64(int64(round(val)), TBACC);
end

%% ============================================================
% Binary helper functions
%% ============================================================

function C = binvec_unsigned(x, bits)
    x = uint64(x(:));
    C = cellstr(dec2bin(double(x), bits));
end

function C = binvec_signed_tc(x, bits)
    mod_base = bitshift(int64(1), bits);
    u = mod(int64(x(:)), mod_base);
    C = cellstr(dec2bin(double(u), bits));
end

%% ============================================================
function out = chi_square_gof_finite_m_ref(z, m, num_bins)

    z = z(:);
    n = numel(z);

    p_edges = linspace(0, 1, num_bins + 1);

    zmin = -sqrt(3*m);
    zmax =  sqrt(3*m);

    xg = linspace(zmin, zmax, 40001);
    Fg = irwinhall_std_cdf(xg, m);

    for k = 2:numel(Fg)
        if Fg(k) < Fg(k-1)
            Fg(k) = Fg(k-1);
        end
    end
    Fg(1)   = 0;
    Fg(end) = 1;

    [Fg_u, idx_u] = unique(Fg, 'stable');
    xg_u = xg(idx_u);

    q_inner = interp1(Fg_u, xg_u, p_edges(2:end-1), 'linear', 'extrap');
    edges   = [-inf, q_inner, inf];

    for k = 2:num_bins
        if edges(k) <= edges(k-1)
            edges(k) = edges(k-1) + 1e-9;
        end
    end

    obs = histcounts(z, edges);
    expCounts = (n / num_bins) * ones(1, num_bins);

    chi2_stat = sum((obs - expCounts).^2 ./ (expCounts + eps));
    dof       = num_bins - 1;
    pval      = gammainc(chi2_stat/2, dof/2, 'upper');

    out = struct();
    out.stat             = chi2_stat;
    out.dof              = dof;
    out.p                = pval;
    out.num_bins         = num_bins;
    out.expected_per_bin = n / num_bins;
end

function Fz = irwinhall_std_cdf(z, m)

    x  = z .* sqrt(m/12) + m/2;
    Fs = zeros(size(x));

    Fs(x <= 0) = 0;
    Fs(x >= m) = 1;

    valid = (x > 0) & (x < m);
    xv    = x(valid);
    Fsv   = zeros(size(xv));

    for idx = 1:numel(xv)
        xx = xv(idx);
        s  = 0;
        for k = 0:floor(xx)
            s = s + ((-1)^k) * nchoosek(m,k) * (xx-k)^m;
        end
        Fsv(idx) = s / factorial(m);
    end

    Fs(valid) = Fsv;
    Fz = Fs;
end

%% ============================================================
function run_mc_dfe_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('MONTE-CARLO DFE SUITE (PAIRED COMPARISON)\n');
    fprintf('Nmc      = %d\n', cfg.Nmc);
    fprintf('m_clt    = %d\n', cfg.m_clt_sys);
    fprintf('variants ='); fprintf(' %s', cfg.mc_variant_list{:}); fprintf('\n');
    fprintf('noise    ='); fprintf(' %s', cfg.mc_noise_models{:}); fprintf('\n');
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);
    allRes = struct();

    for inoise = 1:numel(cfg.mc_noise_models)
        noise_model = cfg.mc_noise_models{inoise};

        % ------------------------------------------------------
        % Paired experiment:
        % at fixed (inoise, imc), ALL variants share:
        %   - same symbol sequence
        %   - same noise seed
        % ------------------------------------------------------
        for iv = 1:numel(cfg.mc_variant_list)
            variant = cfg.mc_variant_list{iv};

            BER      = zeros(cfg.Nmc,1);
            SER      = zeros(cfg.Nmc,1);
            MSE      = zeros(cfg.Nmc,1);
            TapMax   = zeros(cfg.Nmc,1);
            Div      = zeros(cfg.Nmc,1);
            ClipRate = zeros(cfg.Nmc,1);
            ProjRate = zeros(cfg.Nmc,1);

            e2_mat   = [];
            tap_mat  = [];
            trace_n  = [];

            fprintf('\n[MC] noise=%s | variant=%s\n', noise_model, variant);

            for imc = 1:cfg.Nmc

                % Same seeds across variants for fair comparison
                common_seed0 = cfg.seed0 + uint32(cfg.mc_seed_base + 1000*inoise + imc);
                common_rng   = 100000 + 1000*inoise + imc;

                cfg_i = cfg;
                cfg_i.noise_model         = noise_model;
                cfg_i.eq_variant          = variant;
                if ~isempty(common_seed0)
                    cfg_i.seed0 = common_seed0;
                end
                cfg_i.verbose_case        = false;
                cfg_i.enable_eye_analysis = false;
                cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

                rng(common_rng);
                sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
                d       = cfg_i.A(sym_idx);
                d       = d(:);

                res = run_case_system(d, cfg_i, g_rc, true, variant);

                BER(imc)      = res.BER_dfe;
                SER(imc)      = res.SER_dfe;
                MSE(imc)      = res.MSE_ss;
                TapMax(imc)   = res.aux.max_tap_norm_real;
                Div(imc)      = double(res.aux.max_tap_norm_real > cfg_i.div_tap_norm_thresh);
                ClipRate(imc) = res.aux.clip_active_rate;
                ProjRate(imc) = res.aux.proj_active_rate;

                if isempty(e2_mat)
                    e2_mat  = zeros(numel(res.aux.e2_trace), cfg.Nmc);
                    tap_mat = zeros(numel(res.aux.tap_norm_trace), cfg.Nmc);
                    trace_n = res.aux.trace_n(:);
                end

                e2_mat(:,imc)  = res.aux.e2_trace(:);
                tap_mat(:,imc) = res.aux.tap_norm_trace(:);
            end

            allRes.(noise_model).(variant).BER      = BER;
            allRes.(noise_model).(variant).SER      = SER;
            allRes.(noise_model).(variant).MSE      = MSE;
            allRes.(noise_model).(variant).TapMax   = TapMax;
            allRes.(noise_model).(variant).Div      = Div;
            allRes.(noise_model).(variant).ClipRate = ClipRate;
            allRes.(noise_model).(variant).ProjRate = ProjRate;
            allRes.(noise_model).(variant).e2_mat   = e2_mat;
            allRes.(noise_model).(variant).tap_mat  = tap_mat;
            allRes.(noise_model).(variant).trace_n  = trace_n;

            fprintf(['Median BER = %.6e | Median SER = %.6e | Median MSE = %.6e | ' ...
                     'Div-rate = %.4f | Clip-rate = %.6f | Proj-rate = %.6f\n'], ...
                median(BER), median(SER), median(MSE), mean(Div), ...
                median(ClipRate), median(ProjRate));
        end

        plot_mc_summary_for_noise(allRes.(noise_model), noise_model, cfg.mc_variant_list);

        % ------------------------------------------------------
        % Paired delta report versus plain
        % ------------------------------------------------------
        if isfield(allRes.(noise_model), 'plain')
            base = allRes.(noise_model).plain;

            fprintf('\n----- PAIRED DELTA REPORT vs plain | noise=%s -----\n', upper(noise_model));
            fprintf('%-14s %-16s %-16s %-16s %-16s %-16s\n', ...
                'variant', 'median(dBER)', 'median(dSER)', 'median(dMSE)', ...
                'median(dClip)', 'median(dProj)');

            for iv = 1:numel(cfg.mc_variant_list)
                variant = cfg.mc_variant_list{iv};
                cur     = allRes.(noise_model).(variant);

                dBER  = cur.BER      - base.BER;
                dSER  = cur.SER      - base.SER;
                dMSE  = cur.MSE      - base.MSE;
                dClip = cur.ClipRate - base.ClipRate;
                dProj = cur.ProjRate - base.ProjRate;

                fprintf('%-14s %-16.6e %-16.6e %-16.6e %-16.6e %-16.6e\n', ...
                    variant, median(dBER), median(dSER), median(dMSE), ...
                    median(dClip), median(dProj));
            end
        end
    end
end

function plot_mc_summary_for_noise(resNoise, noise_model, variant_list)

    nV = numel(variant_list);
    medBER = zeros(1,nV);
    medSER = zeros(1,nV);
    medMSE = zeros(1,nV);
    divRate = zeros(1,nV);

    figure('Name', sprintf('MC summary | %s', upper(noise_model)));
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    for i = 1:nV
        v = variant_list{i};
        medBER(i) = median(resNoise.(v).BER);
        medSER(i) = median(resNoise.(v).SER);
        medMSE(i) = median(resNoise.(v).MSE);
        divRate(i) = mean(resNoise.(v).Div);
    end

    nexttile;
    semilogy(1:nV, medBER, 'o-','LineWidth',1.2);
    grid on;
    set(gca,'XTick',1:nV,'XTickLabel',variant_list);
    title(sprintf('Median BER | %s', upper(noise_model)));
    ylabel('BER');

    nexttile;
    semilogy(1:nV, medSER, 's-','LineWidth',1.2);
    grid on;
    set(gca,'XTick',1:nV,'XTickLabel',variant_list);
    title(sprintf('Median SER | %s', upper(noise_model)));
    ylabel('SER');

    nexttile;
    plot(1:nV, medMSE, 'd-','LineWidth',1.2);
    grid on;
    set(gca,'XTick',1:nV,'XTickLabel',variant_list);
    title(sprintf('Median MSE_{ss} | %s', upper(noise_model)));
    ylabel('MSE');

    nexttile;
    plot(1:nV, divRate, '^-','LineWidth',1.2);
    grid on;
    set(gca,'XTick',1:nV,'XTickLabel',variant_list);
    title(sprintf('Divergence rate | %s', upper(noise_model)));
    ylabel('Rate');

    figure('Name', sprintf('MC learning curves | %s', upper(noise_model)));
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h = gobjects(nV,1);
    for i = 1:nV
        v = variant_list{i};
        t = resNoise.(v).trace_n;
        med = median(resNoise.(v).e2_mat, 2);
        h(i) = plot(t, med, 'LineWidth', 1.2);
    end
    grid on;
    xlabel('sample index');
    ylabel('median e^2');
    title(sprintf('Learning curve | %s', upper(noise_model)));
    legend(h, variant_list, 'Location','best');

    nexttile; hold on;
    h = gobjects(nV,1);
    for i = 1:nV
        v = variant_list{i};
        t = resNoise.(v).trace_n;
        med = median(resNoise.(v).tap_mat, 2);
        h(i) = plot(t, med, 'LineWidth', 1.2);
    end
    grid on;
    xlabel('sample index');
    ylabel('median tap norm');
    title(sprintf('Tap oscillation / spread | %s', upper(noise_model)));
    legend(h, variant_list, 'Location','best');
end


%% ============================================================
function run_mc_snr_dfe_validation_suite(cfg)
% Monte-Carlo DFE validation over SNR = 15...30 dB.
% Compares:
%   plain       : LMS DFE baseline
%   sm_sign     : LMS with set-membership signed-error update
%   robust_proj : proposed robust-projected LMS DFE

    fprintf('\n==================================================\n');
    fprintf('MONTE-CARLO DFE SNR VALIDATION SUITE\n');
    fprintf('SNR list ='); fprintf(' %.1f', cfg.mc_snr_list); fprintf('\n');
    fprintf('Nmc      = %d\n', cfg.mc_snr_Nmc);
    fprintf('Nsym     = %d\n', cfg.mc_snr_Nsym);
    fprintf('variants ='); fprintf(' %s', cfg.mc_snr_variant_list{:}); fprintf('\n');
    fprintf('noise    = %s\n', cfg.mc_snr_noise_model);
    fprintf('FEC BER threshold = %.3e\n', cfg.fec_threshold_ber);
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    snr_list     = cfg.mc_snr_list(:).';
    variant_list = cfg.mc_snr_variant_list(:).';
    nS = numel(snr_list);
    nV = numel(variant_list);

    medBER = zeros(nS,nV);
    medSER = zeros(nS,nV);
    medMSE = zeros(nS,nV);
    medTap = zeros(nS,nV);
    oscE2  = zeros(nS,nV);
    oscTap = zeros(nS,nV);
    updRate = zeros(nS,nV);
    smRate  = zeros(nS,nV);

    traceStore = struct();

    rowSNR = [];
    rowVariant = {};
    rowBER = [];
    rowSER = [];
    rowMSE = [];
    rowTap = [];
    rowOscE2 = [];
    rowOscTap = [];
    rowUpdRate = [];
    rowSMRate = [];

    for is = 1:nS
        snr_db = snr_list(is);

        fprintf('\n----- MC SNR = %.1f dB -----\n', snr_db);
        fprintf('%-14s %-14s %-14s %-14s %-14s %-14s %-14s %-12s\n', ...
            'variant','medBER','medSER','medMSE','medTap','oscE2','oscTap','updRate');

        for iv = 1:nV
            variant = variant_list{iv};

            BER = zeros(cfg.mc_snr_Nmc,1);
            SER = zeros(cfg.mc_snr_Nmc,1);
            MSE = zeros(cfg.mc_snr_Nmc,1);
            TAP = zeros(cfg.mc_snr_Nmc,1);
            OE2 = zeros(cfg.mc_snr_Nmc,1);
            OTP = zeros(cfg.mc_snr_Nmc,1);
            UPR = zeros(cfg.mc_snr_Nmc,1);
            SMR = zeros(cfg.mc_snr_Nmc,1);

            e2_mat  = [];
            tap_mat = [];
            trace_n = [];

            for imc = 1:cfg.mc_snr_Nmc
                common_seed0 = cfg.seed0 + uint32(910000 + 1000*is + imc);
                common_rng   = 910000 + 1000*is + imc;

                cfg_i = cfg;
                cfg_i.SNRdB                  = snr_db;
                cfg_i.Nsym_sys               = cfg.mc_snr_Nsym;
                cfg_i.noise_model            = cfg.mc_snr_noise_model;
                cfg_i.eq_variant             = variant;
                if ~isempty(common_seed0)
                    cfg_i.seed0 = common_seed0;
                end
                cfg_i.enable_eye_analysis    = false;
                cfg_i.verbose_case           = false;
                cfg_i.collect_learning_trace = true;
                cfg_i.trace_decim            = cfg.mc_snr_trace_decim;
                cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

                rng(common_rng);
                sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
                d       = cfg_i.A(sym_idx);
                d       = d(:);

                res = run_case_system(d, cfg_i, g_rc, true, variant);

                BER(imc) = res.BER_dfe;
                SER(imc) = res.SER_dfe;
                MSE(imc) = res.MSE_ss;
                TAP(imc) = res.aux.max_tap_norm_real;
                UPR(imc) = res.aux.update_steps / max(1, cfg_i.Nsym_sys);

                if isfield(res.aux, 'sm_sign_active_rate')
                    SMR(imc) = res.aux.sm_sign_active_rate;
                else
                    SMR(imc) = 0;
                end

                if ~isempty(res.aux.e2_trace)
                    idx0 = max(1, floor(0.60*numel(res.aux.e2_trace)));
                    OE2(imc) = std(res.aux.e2_trace(idx0:end), 1);
                    OTP(imc) = std(res.aux.tap_norm_trace(idx0:end), 1);
                end

                if isempty(e2_mat)
                    e2_mat  = zeros(numel(res.aux.e2_trace), cfg.mc_snr_Nmc);
                    tap_mat = zeros(numel(res.aux.tap_norm_trace), cfg.mc_snr_Nmc);
                    trace_n = res.aux.trace_n(:);
                end

                e2_mat(:,imc)  = res.aux.e2_trace(:);
                tap_mat(:,imc) = res.aux.tap_norm_trace(:);
            end

            medBER(is,iv) = median(BER);
            medSER(is,iv) = median(SER);
            medMSE(is,iv) = median(MSE);
            medTap(is,iv) = median(TAP);
            oscE2(is,iv)  = median(OE2);
            oscTap(is,iv) = median(OTP);
            updRate(is,iv)= median(UPR);
            smRate(is,iv) = median(SMR);

            fprintf('%-14s %-14.6e %-14.6e %-14.6e %-14.6f %-14.6e %-14.6e %-12.6f\n', ...
                variant, medBER(is,iv), medSER(is,iv), medMSE(is,iv), medTap(is,iv), ...
                oscE2(is,iv), oscTap(is,iv), updRate(is,iv));

            rowSNR(end+1,1) = snr_db; %#ok<AGROW>
            rowVariant{end+1,1} = variant; %#ok<AGROW>
            rowBER(end+1,1) = medBER(is,iv); %#ok<AGROW>
            rowSER(end+1,1) = medSER(is,iv); %#ok<AGROW>
            rowMSE(end+1,1) = medMSE(is,iv); %#ok<AGROW>
            rowTap(end+1,1) = medTap(is,iv); %#ok<AGROW>
            rowOscE2(end+1,1) = oscE2(is,iv); %#ok<AGROW>
            rowOscTap(end+1,1) = oscTap(is,iv); %#ok<AGROW>
            rowUpdRate(end+1,1) = updRate(is,iv); %#ok<AGROW>
            rowSMRate(end+1,1) = smRate(is,iv); %#ok<AGROW>

            if abs(snr_db - cfg.mc_snr_trace_snr) < 1e-12
                traceStore.(variant).trace_n = trace_n;
                traceStore.(variant).e2_mat  = e2_mat;
                traceStore.(variant).tap_mat = tap_mat;
            end
        end
    end

    summaryTbl = table(rowSNR, rowVariant, rowBER, rowSER, rowMSE, rowTap, ...
        rowOscE2, rowOscTap, rowUpdRate, rowSMRate, ...
        'VariableNames', {'SNRdB','Variant','MedianBER','MedianSER','MedianMSE', ...
        'MedianMaxTapNorm','MedianE2Oscillation','MedianTapOscillation', ...
        'MedianUpdateRate','MedianSMSignActiveRate'});

    writetable(summaryTbl, 'mc_dfe_snr_validation_summary.csv');
    fprintf('\nSaved MC SNR summary: mc_dfe_snr_validation_summary.csv\n');

    figure('Name','MC DFE validation: BER/SER vs SNR');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h = gobjects(nV,1);
    for iv = 1:nV
        h(iv) = semilogy(snr_list, medBER(:,iv), 'o-', 'LineWidth', 1.2);
    end
    yline(cfg.fec_threshold_ber, '--', 'FEC = 10^{-3}');
    grid on;
    xlabel('SNR (dB)');
    ylabel('median BER');
    title('BER vs SNR');
    legend(h, variant_list, 'Location','best');

    nexttile; hold on;
    h = gobjects(nV,1);
    for iv = 1:nV
        h(iv) = semilogy(snr_list, medSER(:,iv), 's-', 'LineWidth', 1.2);
    end
    grid on;
    xlabel('SNR (dB)');
    ylabel('median SER');
    title('SER vs SNR');
    legend(h, variant_list, 'Location','best');

    figure('Name','MC DFE validation: learning oscillation vs SNR');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h = gobjects(nV,1);
    for iv = 1:nV
        h(iv) = semilogy(snr_list, oscE2(:,iv) + eps, 'o-', 'LineWidth', 1.2);
    end
    grid on;
    xlabel('SNR (dB)');
    ylabel('median tail std(e^2)');
    title('Learning-error oscillation');
    legend(h, variant_list, 'Location','best');

    nexttile; hold on;
    h = gobjects(nV,1);
    for iv = 1:nV
        h(iv) = semilogy(snr_list, oscTap(:,iv) + eps, 's-', 'LineWidth', 1.2);
    end
    grid on;
    xlabel('SNR (dB)');
    ylabel('median tail std(||\theta_n||)');
    title('Tap-norm oscillation');
    legend(h, variant_list, 'Location','best');

    if ~isempty(fieldnames(traceStore))
        figure('Name', sprintf('MC learning traces at SNR %.1f dB', cfg.mc_snr_trace_snr));
        tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

        nexttile; hold on;
        h = gobjects(nV,1);
        for iv = 1:nV
            variant = variant_list{iv};
            if isfield(traceStore, variant)
                t = traceStore.(variant).trace_n;
                med = median(traceStore.(variant).e2_mat, 2);
                h(iv) = plot(t, med, 'LineWidth', 1.2);
            end
        end
        grid on;
        xlabel('sample index');
        ylabel('median e^2');
        title(sprintf('Learning curve at %.1f dB', cfg.mc_snr_trace_snr));
        legend(h, variant_list, 'Location','best');

        nexttile; hold on;
        h = gobjects(nV,1);
        for iv = 1:nV
            variant = variant_list{iv};
            if isfield(traceStore, variant)
                t = traceStore.(variant).trace_n;
                med = median(traceStore.(variant).tap_mat, 2);
                h(iv) = plot(t, med, 'LineWidth', 1.2);
            end
        end
        grid on;
        xlabel('sample index');
        ylabel('median ||\theta_n||');
        title(sprintf('Learning oscillation at %.1f dB', cfg.mc_snr_trace_snr));
        legend(h, variant_list, 'Location','best');
    end
end


%% ============================================================
function run_projected_ode_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('PROJECTED ODE VALIDATION SUITE\n');
    fprintf('==================================================\n');

    cfg_ref = cfg;
    cfg_ref.eq_variant     = 'robust_proj';
    cfg_ref.mu_mode        = 'decreasing';
    cfg_ref.mu0            = cfg.mu;
    cfg_ref.Nsym_sys       = 6000;
    cfg_ref.trainLen       = cfg_ref.Nsym_sys;
    cfg_ref.enable_eye_analysis = false;
    cfg_ref.noise_model    = 'gaussian';
    cfg_ref.store_dfe_history = true;
    cfg_ref.collect_learning_trace = false;
    cfg_ref.verbose_case = false;
    cfg_ref = prepare_cfg_for_m(cfg_ref, cfg_ref.m_clt);
    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    rng(2026);
    sym_idx = randi([1 cfg_ref.M], cfg_ref.Nsym_sys, 1);
    d       = cfg_ref.A(sym_idx);
    d       = d(:);

    res_ref = run_case_system(d, cfg_ref, g_rc, true, 'robust_proj');
    theta_ref = [res_ref.w_final(:); res_ref.b_final(:)];

    idx_pair = cfg.ode_idx_pair(:).';
    if numel(idx_pair) ~= 2 || any(idx_pair < 1) || any(idx_pair > numel(theta_ref))
        error('Invalid cfg.ode_idx_pair.');
    end

    theta_ref_real = double(theta_ref) / 2^cfg.frac_bits;
    c1 = theta_ref_real(idx_pair(1));
    c2 = theta_ref_real(idx_pair(2));

    span = 0.8;
    g1 = linspace(c1 - span, c1 + span, cfg.ode_grid_N);
    g2 = linspace(c2 - span, c2 + span, cfg.ode_grid_N);

    [G1, G2] = meshgrid(g1, g2);
    U = zeros(size(G1));
    V = zeros(size(G2));

    ode_data = build_teacher_forced_training_data(cfg, cfg.ode_avg_N);

    for i = 1:numel(G1)
        theta_i = theta_ref_real;
        theta_i(idx_pair(1)) = G1(i);
        theta_i(idx_pair(2)) = G2(i);

        drift = estimate_mean_projected_drift(theta_i, cfg, ode_data);

        U(i) = drift(idx_pair(1));
        V(i) = drift(idx_pair(2));
    end

    path1 = [];
    path2 = [];
    if ~isempty(res_ref.W)
        main_idx = idx_pair(1);
        fb_idx   = idx_pair(2);

        for n = 1:size(res_ref.W,2)
            theta_now = [res_ref.W(:,n); res_ref.B(:,n)];
            path1(end+1,1) = theta_now(main_idx); %#ok<AGROW>
            path2(end+1,1) = theta_now(fb_idx);   %#ok<AGROW>
        end
    end

    figure('Name', 'Projected ODE mean drift validation');
    quiver(G1, G2, U, V, 'AutoScale','on'); hold on;
    plot(c1, c2, 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);

    if ~isempty(path1)
        plot(path1, path2, 'k-', 'LineWidth', 1.0);
    end

    xlabel(sprintf('\\theta(%d)', idx_pair(1)));
    ylabel(sprintf('\\theta(%d)', idx_pair(2)));
    title('Projected mean-drift field + decreasing-step trajectory');
    grid on;

    fprintf('Reference theta slice center = [%.6f, %.6f]\n', c1, c2);
end

function ode_data = build_teacher_forced_training_data(cfg, N)

    Q  = cfg.frac_bits;
    TB = cfg.total_bits;
    cfg = prepare_cfg_for_m(cfg, cfg.m_clt);
    rng(3030);
    sym_idx = randi([1 cfg.M], N, 1);
    d       = cfg.A(sym_idx);
    d       = d(:);

    r_clean    = d + cfg.ISI * [0; d(1:end-1)];
    r_clean_fx = q_from_real(r_clean, Q, TB);

    Pr            = mean(r_clean.^2);
    sigma2        = Pr / (10^(cfg.SNRdB/10));
    sqrt_sigma_fx = q_from_real_scalar(sqrt(sigma2), Q, TB);

    cfg_i = cfg;
    cfg_i.verbose_case = false;
    [noise_fx, ~, ~, ~, ~] = generate_channel_noise_fx(N, sqrt_sigma_fx, cfg_i);
    r_fx = q_add_vec(r_clean_fx, noise_fx, TB);

    ode_data = struct();
    ode_data.d    = d;
    ode_data.d_fx = q_from_real(d, Q, TB);
    ode_data.r_fx = r_fx;
end

function drift = estimate_mean_projected_drift(theta_real, cfg, ode_data)

    Q  = cfg.frac_bits;
    TB = cfg.total_bits;
    Nf = cfg.Nf;
    Nb = cfg.Nb;

    theta_fx = q_from_real(theta_real(:), Q, TB);
    w = theta_fx(1:Nf);
    b = theta_fx(Nf+1:end);

    mu_fx       = q_from_real_scalar(cfg.ode_mu, Q, TB);
    err_clip_fx = q_from_real_scalar(cfg.err_clip, Q, TB);

    w_min_fx = q_from_real(cfg.w_min(:), Q, TB);
    w_max_fx = q_from_real(cfg.w_max(:), Q, TB);
    b_min_fx = q_from_real(cfg.b_min(:), Q, TB);
    b_max_fx = q_from_real(cfg.b_max(:), Q, TB);

    x_buf  = int32(zeros(Nf,1));
    fb_buf = int32(zeros(Nb,1));

    acc_drift = zeros(Nf+Nb,1);
    N = numel(ode_data.d_fx);

    for n = 1:N
        x_buf = [ode_data.r_fx(n); x_buf(1:end-1)];

        if n > 1
            d_prev_fx = ode_data.d_fx(n-1); % teacher forcing
        else
            d_prev_fx = int32(0);
        end

        if Nb > 0
            fb_buf = [d_prev_fx; fb_buf(1:end-1)];
        end

        acc = int64(0);
        for k = 1:Nf
            acc = acc + int64(w(k)) * int64(x_buf(k));
        end
        for k = 1:Nb
            acc = acc - int64(b(k)) * int64(fb_buf(k));
        end
        y_fx = q_sat(bitshift(acc, -Q), TB);

        if n - cfg.D >= 1
            d_des_fx = ode_data.d_fx(n-cfg.D);
        else
            d_des_fx = int32(0);
        end

        e_fx = q_sub(d_des_fx, y_fx, TB);
        if cfg.use_error_clip
            e_fx = clip_sym_i32(e_fx, err_clip_fx);
        end

        dw = int32(zeros(Nf,1));
        db = int32(zeros(Nb,1));

        for k = 1:Nf
            dw(k) = q_mul(mu_fx, q_mul(e_fx, x_buf(k), Q, TB), Q, TB);
        end
        for k = 1:Nb
            db(k) = q_mul(mu_fx, q_mul(e_fx, fb_buf(k), Q, TB), Q, TB);
        end

        w_next = q_add_vec(w, dw, TB);
        if Nb > 0
            b_next = q_sub(b, db, TB);
        else
            b_next = b;
        end

        if cfg.use_proj
            w_next = q_clip_vec(w_next, w_min_fx, w_max_fx);
            if Nb > 0
                b_next = q_clip_vec(b_next, b_min_fx, b_max_fx);
            end
        end

        delta_theta = [double(w_next - w)/2^Q; double(b_next - b)/2^Q];
        acc_drift = acc_drift + delta_theta;
    end

    drift = acc_drift / N;
end

%% ============================================================
function run_polyak_validation_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('POLYAK AVERAGING VALIDATION SUITE\n');
    fprintf('==================================================\n');

    cfg_i = cfg;
    cfg_i.eq_variant          = 'robust_proj';
    cfg_i.mu_mode             = 'decreasing';
    cfg_i.mu0                 = cfg.mu;
    cfg_i.Nsym_sys            = 12000;
    cfg_i.trainLen            = cfg_i.Nsym_sys;
    cfg_i.enable_eye_analysis = false;
    cfg_i.noise_model         = 'gaussian';
    cfg_i.collect_learning_trace = false;
    cfg_i.verbose_case        = false;
    cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);
    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    rng(4040);
    sym_idx = randi([1 cfg_i.M], 50000, 1);
    dref    = cfg_i.A(sym_idx);
    dref    = dref(:);

    cfg_ref = cfg_i;
    cfg_ref.Nsym_sys = numel(dref);
    cfg_ref.trainLen = numel(dref);
    res_ref = run_case_system(dref, cfg_ref, g_rc, true, 'robust_proj');
    theta_ref = [double(res_ref.w_final)/2^cfg_i.frac_bits; double(res_ref.b_final)/2^cfg_i.frac_bits];

    err_inst = zeros(cfg.Nmc,1);
    err_avg  = zeros(cfg.Nmc,1);

    for imc = 1:cfg.Nmc
        rng(5050 + imc);
        sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
        d       = cfg_i.A(sym_idx);
        d       = d(:);

        res = run_case_system(d, cfg_i, g_rc, true, 'robust_proj');

        theta_inst = [double(res.w_final)/2^cfg_i.frac_bits; double(res.b_final)/2^cfg_i.frac_bits];
        theta_avg  = [double(res.aux.w_polyak_final)/2^cfg_i.frac_bits; double(res.aux.b_polyak_final)/2^cfg_i.frac_bits];

        err_inst(imc) = norm(theta_inst - theta_ref);
        err_avg(imc)  = norm(theta_avg  - theta_ref);
    end

    fprintf('Median ||theta_final - theta_ref||  = %.6e\n', median(err_inst));
    fprintf('Median ||theta_polyak - theta_ref|| = %.6e\n', median(err_avg));
    fprintf('Mean   ||theta_final - theta_ref||  = %.6e\n', mean(err_inst));
    fprintf('Mean   ||theta_polyak - theta_ref|| = %.6e\n', mean(err_avg));

    figure('Name', 'Polyak averaging validation');
    semilogy(sort(err_inst), 'o-','LineWidth',1.2); hold on;
    semilogy(sort(err_avg),  's-','LineWidth',1.2);
    grid on;
    xlabel('sorted MC index');
    ylabel('parameter error norm');
    title('Instantaneous final taps vs Polyak-averaged taps');
    legend('final taps','Polyak-averaged taps','Location','best');
end

%% ============================================================
function run_decreasing_mu_validation_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('DECREASING-STEP VALIDATION SUITE\n');
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    cfg_ref = cfg;
    cfg_ref.eq_variant = 'robust_proj';
    cfg_ref.mu_mode = 'decreasing';
    cfg_ref.mu0 = cfg.mu;
    cfg_ref.Nsym_sys = 40000;
    cfg_ref.trainLen = cfg_ref.Nsym_sys;
    cfg_ref.enable_eye_analysis = false;
    cfg_ref.collect_learning_trace = false;
    cfg_ref.verbose_case = false;
    cfg_ref.noise_model = cfg.dec_mu_validation_noise;

    rng(6060);
    sym_idx = randi([1 cfg_ref.M], cfg_ref.Nsym_sys, 1);
    dref = cfg_ref.A(sym_idx);
    dref = dref(:);

    res_ref = run_case_system(dref, cfg_ref, g_rc, true, 'robust_proj');
    theta_ref = [double(res_ref.w_final)/2^cfg_ref.frac_bits; double(res_ref.b_final)/2^cfg_ref.frac_bits];

    figure('Name', sprintf('Decreasing-step validation | %s', upper(cfg.dec_mu_validation_noise)));
    hold on;

    h = gobjects(numel(cfg.dec_mu_validation_variants),1);

    for iv = 1:numel(cfg.dec_mu_validation_variants)
        variant = cfg.dec_mu_validation_variants{iv};

        err_mat = [];
        trace_n = [];

        for imc = 1:cfg.dec_mu_Nmc
            cfg_i = cfg;
            cfg_i.eq_variant = variant;
            cfg_i.mu_mode = 'decreasing';
            cfg_i.mu0 = cfg.mu;
            cfg_i.Nsym_sys = cfg.dec_mu_Nsym;
            cfg_i.trainLen = cfg_i.Nsym_sys;
            cfg_i.enable_eye_analysis = false;
            cfg_i.collect_learning_trace = true;
            cfg_i.trace_decim = cfg.dec_mu_trace_decim;
            cfg_i.verbose_case = false;
            cfg_i.noise_model = cfg.dec_mu_validation_noise;
            cfg_i.seed0 = cfg.seed0 + uint32(7000 + 100*iv + imc);
            cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);
            rng(700000 + 1000*iv + imc);
            sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
            d = cfg_i.A(sym_idx);
            d = d(:);

            res = run_case_system(d, cfg_i, g_rc, true, variant);

            if isempty(err_mat)
                err_mat = zeros(size(res.aux.theta_trace,2), cfg.dec_mu_Nmc);
                trace_n = res.aux.trace_n(:);
            end

            for k = 1:size(res.aux.theta_trace,2)
                err_mat(k,imc) = norm(res.aux.theta_trace(:,k) - theta_ref);
            end
        end

        med = median(err_mat, 2);
        p10 = prctile(err_mat.', 10).';
        p90 = prctile(err_mat.', 90).';

        plot(trace_n, p10, '--', 'LineWidth', 0.8);
        h(iv) = plot(trace_n, med, 'LineWidth', 1.4);
        plot(trace_n, p90, '--', 'LineWidth', 0.8);

        fprintf('[%s] median final ||theta_n - theta_ref|| = %.6e\n', variant, median(err_mat(end,:)));
    end

    grid on;
    xlabel('sample index');
    ylabel('||\theta_n - \theta_{ref}||');
    title(sprintf('Decreasing-step validation | %s', upper(cfg.dec_mu_validation_noise)));
    legend(h, cfg.dec_mu_validation_variants, 'Location','best');
end

%% ============================================================
function run_clip_sweep_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('CLIPPING-THRESHOLD SWEEP SUITE\n');
    fprintf('noise       = %s\n', cfg.clip_sweep_noise);
    fprintf('variant     = %s\n', cfg.clip_sweep_variant);

    if isfield(cfg,'clip_sweep_use_snr_sweep') && cfg.clip_sweep_use_snr_sweep
        snr_list = cfg.clip_sweep_snr_list(:).';
    else
        snr_list = cfg.SNRdB;
    end

    seed_mode = '';
    if isfield(cfg,'clip_sweep_seed_mode')
        seed_mode = lower(cfg.clip_sweep_seed_mode);
    end
    v24_seed_mode    = strcmp(seed_mode,'v24');
    legacy_seed_mode = strcmp(seed_mode,'legacy') || strcmp(seed_mode,'legacy_810_all') || v24_seed_mode;
    legacy_all_810   = strcmp(seed_mode,'legacy_810_all');

    % legacy_clip_mode controls only the old one-SNR print/return behavior.
    % v24_seed_mode reproduces the v24 testbench RNG even when SNR sweep is enabled.
    legacy_clip_mode = legacy_seed_mode && (~isfield(cfg,'clip_sweep_use_snr_sweep') || ~cfg.clip_sweep_use_snr_sweep);

    if ~legacy_clip_mode
        fprintf('baselines   ='); fprintf(' %s', cfg.clip_sweep_baseline_variants{:}); fprintf('\n');
    end
    fprintf('clip list   ='); fprintf(' %.3f', cfg.clip_list); fprintf('\n');

    if ~legacy_clip_mode
        fprintf('SNR list    ='); fprintf(' %.1f', snr_list); fprintf('\n');
        fprintf('Nmc         = %d\n', cfg.clip_sweep_Nmc);
        fprintf('Nsym        = %d\n', cfg.clip_sweep_Nsym);
        fprintf('seed mode   = %s\n', seed_mode);
        fprintf('FEC BER threshold = %.3e\n', cfg.fec_threshold_ber);
    end
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    clip_list = cfg.clip_list(:).';
    baseline_variants = cfg.clip_sweep_baseline_variants(:).';

    nS = numel(snr_list);
    nC = numel(clip_list);
    nB = numel(baseline_variants);

    medBER = zeros(nS,nC);
    medSER = zeros(nS,nC);
    medMSE = zeros(nS,nC);
    medTap = zeros(nS,nC);

    baseBER = zeros(nS,nB);
    baseSER = zeros(nS,nB);
    baseMSE = zeros(nS,nB);
    baseTap = zeros(nS,nB);

    rowSNR = [];
    rowMethod = {};
    rowClip = [];
    rowBER = [];
    rowSER = [];
    rowMSE = [];
    rowTap = [];

    for is = 1:nS
        snr_db = snr_list(is);

        fprintf('\n----- CLIP SWEEP | SNR = %.1f dB -----\n', snr_db);

        % ------------------------------------------------------
        % Baselines: plain LMS and LMS-SM-sign
        % ------------------------------------------------------
        for ib = 1:nB
            baseline = baseline_variants{ib};

            BER = zeros(cfg.clip_sweep_Nmc,1);
            SER = zeros(cfg.clip_sweep_Nmc,1);
            MSE = zeros(cfg.clip_sweep_Nmc,1);
            TAP = zeros(cfg.clip_sweep_Nmc,1);

            for imc = 1:cfg.clip_sweep_Nmc
                if v24_seed_mode
                    common_seed0 = [];
                    common_rng   = 810000 + imc;
                elseif legacy_seed_mode
                    common_seed0 = cfg.seed0 + uint32(810000 + imc);
                    common_rng   = 810000 + imc;
                else
                    common_seed0 = cfg.seed0 + uint32(830000 + 1000*is + imc);
                    common_rng   = 830000 + 1000*is + imc;
                end

                cfg_i = cfg;
                cfg_i.SNRdB = snr_db;
                cfg_i.noise_model = cfg.clip_sweep_noise;
                cfg_i.eq_variant  = baseline;
                cfg_i.Nsym_sys    = cfg.clip_sweep_Nsym;
                if ~isempty(common_seed0)
                    cfg_i.seed0 = common_seed0;
                end
                cfg_i.enable_eye_analysis = false;
                cfg_i.verbose_case = false;
                cfg_i.collect_learning_trace = false;
                cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

                rng(common_rng);
                sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
                d = cfg_i.A(sym_idx);
                d = d(:);

                res = run_case_system(d, cfg_i, g_rc, true, baseline);

                BER(imc) = res.BER_dfe;
                SER(imc) = res.SER_dfe;
                MSE(imc) = res.MSE_ss;
                TAP(imc) = res.aux.max_tap_norm_real;
            end

            baseBER(is,ib) = median(BER);
            baseSER(is,ib) = median(SER);
            baseMSE(is,ib) = median(MSE);
            baseTap(is,ib) = median(TAP);

            if legacy_clip_mode && strcmpi(baseline,'plain')
                fprintf('Plain baseline: median BER=%.6e | SER=%.6e | MSE=%.6e | TapMax=%.6f\n', ...
                    baseBER(is,ib), baseSER(is,ib), baseMSE(is,ib), baseTap(is,ib));
            else
                fprintf('baseline=%-10s | median BER=%.6e | SER=%.6e | MSE=%.6e | TapMax=%.6f\n', ...
                    baseline, baseBER(is,ib), baseSER(is,ib), baseMSE(is,ib), baseTap(is,ib));
            end

            rowSNR(end+1,1) = snr_db; %#ok<AGROW>
            rowMethod{end+1,1} = baseline; %#ok<AGROW>
            rowClip(end+1,1) = NaN; %#ok<AGROW>
            rowBER(end+1,1) = baseBER(is,ib); %#ok<AGROW>
            rowSER(end+1,1) = baseSER(is,ib); %#ok<AGROW>
            rowMSE(end+1,1) = baseMSE(is,ib); %#ok<AGROW>
            rowTap(end+1,1) = baseTap(is,ib); %#ok<AGROW>
        end

        % ------------------------------------------------------
        % Proposed robust-projected LMS under different clipping thresholds
        % ------------------------------------------------------
        for ic = 1:nC
            cval = clip_list(ic);

            BER = zeros(cfg.clip_sweep_Nmc,1);
            SER = zeros(cfg.clip_sweep_Nmc,1);
            MSE = zeros(cfg.clip_sweep_Nmc,1);
            TAP = zeros(cfg.clip_sweep_Nmc,1);

            for imc = 1:cfg.clip_sweep_Nmc
                if v24_seed_mode
                    common_seed0 = [];
                    common_rng   = 820000 + 100*ic + imc;
                elseif legacy_seed_mode
                    if legacy_all_810
                        common_seed0 = cfg.seed0 + uint32(810000 + imc);
                        common_rng   = 810000 + imc;
                    else
                        common_seed0 = cfg.seed0 + uint32(820000 + 100*ic + imc);
                        common_rng   = 820000 + 100*ic + imc;
                    end
                else
                    common_seed0 = cfg.seed0 + uint32(830000 + 1000*is + imc);
                    common_rng   = 830000 + 1000*is + imc;
                end

                cfg_i = cfg;
                cfg_i.SNRdB = snr_db;
                cfg_i.noise_model = cfg.clip_sweep_noise;
                cfg_i.eq_variant  = cfg.clip_sweep_variant;
                cfg_i.err_clip    = cval;
                cfg_i.Nsym_sys    = cfg.clip_sweep_Nsym;
                if ~isempty(common_seed0)
                    cfg_i.seed0 = common_seed0;
                end
                cfg_i.enable_eye_analysis = false;
                cfg_i.verbose_case = false;
                cfg_i.collect_learning_trace = false;
                cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

                rng(common_rng);
                sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
                d = cfg_i.A(sym_idx);
                d = d(:);

                res = run_case_system(d, cfg_i, g_rc, true, cfg_i.eq_variant);

                BER(imc) = res.BER_dfe;
                SER(imc) = res.SER_dfe;
                MSE(imc) = res.MSE_ss;
                TAP(imc) = res.aux.max_tap_norm_real;
            end

            medBER(is,ic) = median(BER);
            medSER(is,ic) = median(SER);
            medMSE(is,ic) = median(MSE);
            medTap(is,ic) = median(TAP);

            fprintf('clip=%.3f | median BER=%.6e | SER=%.6e | MSE=%.6e | TapMax=%.6f\n', ...
                cval, medBER(is,ic), medSER(is,ic), medMSE(is,ic), medTap(is,ic));

            rowSNR(end+1,1) = snr_db; %#ok<AGROW>
            rowMethod{end+1,1} = cfg.clip_sweep_variant; %#ok<AGROW>
            rowClip(end+1,1) = cval; %#ok<AGROW>
            rowBER(end+1,1) = medBER(is,ic); %#ok<AGROW>
            rowSER(end+1,1) = medSER(is,ic); %#ok<AGROW>
            rowMSE(end+1,1) = medMSE(is,ic); %#ok<AGROW>
            rowTap(end+1,1) = medTap(is,ic); %#ok<AGROW>
        end

        [bestBER, bestIdx] = min(medBER(is,:));
        if legacy_clip_mode
            fprintf('BEST clip=%.3f | median BER=%.6e | median SER=%.6e\n', ...
                clip_list(bestIdx), bestBER, medSER(is,bestIdx));
        else
            fprintf('BEST at SNR %.1f dB: clip=%.3f | median BER=%.6e | median SER=%.6e\n', ...
                snr_db, clip_list(bestIdx), bestBER, medSER(is,bestIdx));
        end
    end

    summaryTbl = table(rowSNR, rowMethod, rowClip, rowBER, rowSER, rowMSE, rowTap, ...
        'VariableNames', {'SNRdB','Method','ClipThreshold','MedianBER','MedianSER','MedianMSE','MedianMaxTapNorm'});

    if ~isfield(cfg,'clip_sweep_export_csv') || cfg.clip_sweep_export_csv
        writetable(summaryTbl, 'clip_sweep_snr_summary.csv');
        fprintf('\nSaved clipping sweep summary: clip_sweep_snr_summary.csv\n');
    end

    if legacy_clip_mode
        return;
    end

    [bestBER_all, bestIdx_all] = min(medBER, [], 2);
    bestClip = clip_list(bestIdx_all).';
    bestSER  = zeros(nS,1);
    for is = 1:nS
        bestSER(is) = medSER(is,bestIdx_all(is));
    end

    fprintf('\n========== BEST CLIP SUMMARY ==========\n');
    fprintf('%-8s %-10s %-14s %-14s\n', 'SNRdB', 'bestClip', 'bestBER', 'bestSER');
    for is = 1:nS
        fprintf('%-8.1f %-10.3f %-14.6e %-14.6e\n', ...
            snr_list(is), bestClip(is), bestBER_all(is), bestSER(is));
    end

    figure('Name','Clipping sweep: BER/SER vs SNR');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h = gobjects(nC+nB,1);
    leg = cell(nC+nB,1);
    for ib = 1:nB
        h(ib) = semilogy(snr_list, baseBER(:,ib), '--', 'LineWidth', 1.2);
        leg{ib} = baseline_variants{ib};
    end
    for ic = 1:nC
        idx = nB + ic;
        h(idx) = semilogy(snr_list, medBER(:,ic), 'o-', 'LineWidth', 1.2);
        leg{idx} = sprintf('clip=%.2f', clip_list(ic));
    end
    yline(cfg.fec_threshold_ber, '--', 'FEC = 10^{-3}');
    grid on;
    xlabel('SNR (dB)');
    ylabel('median BER');
    title('BER vs SNR under clipping threshold sweep');
    legend(h, leg, 'Location','best');

    nexttile; hold on;
    h = gobjects(nC+nB,1);
    for ib = 1:nB
        h(ib) = semilogy(snr_list, baseSER(:,ib), '--', 'LineWidth', 1.2);
    end
    for ic = 1:nC
        idx = nB + ic;
        h(idx) = semilogy(snr_list, medSER(:,ic), 's-', 'LineWidth', 1.2);
    end
    grid on;
    xlabel('SNR (dB)');
    ylabel('median SER');
    title('SER vs SNR under clipping threshold sweep');
    legend(h, leg, 'Location','best');

    figure('Name','Clipping sweep: summary heatmap and selected threshold');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    imagesc(clip_list, snr_list, log10(medBER + realmin));
    set(gca,'YDir','normal');
    colorbar;
    xlabel('clip threshold c');
    ylabel('SNR (dB)');
    title('log_{10}(median BER)');

    nexttile;
    plot(snr_list, bestClip, 'o-', 'LineWidth', 1.2);
    grid on;
    xlabel('SNR (dB)');
    ylabel('selected clip threshold');
    title('Best clip threshold by median BER');
end

%% ============================================================
function run_empirical_lyapunov_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('EMPIRICAL LYAPUNOV VALIDATION SUITE\n');
    fprintf('noise    = %s\n', cfg.lyap_noise_model);
    fprintf('variants ='); fprintf(' %s', cfg.lyap_variants{:}); fprintf('\n');
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    % build reference point theta_ref
    cfg_ref = cfg;
    cfg_ref.eq_variant = 'robust_proj';
    cfg_ref.mu_mode = 'decreasing';
    cfg_ref.mu0 = cfg.mu;
    cfg_ref.Nsym_sys = 40000;
    cfg_ref.trainLen = cfg_ref.Nsym_sys;
    cfg_ref.enable_eye_analysis = false;
    cfg_ref.collect_learning_trace = false;
    cfg_ref.verbose_case = false;
    cfg_ref.noise_model = cfg.lyap_noise_model;
    cfg_ref = prepare_cfg_for_m(cfg_ref, cfg_ref.m_clt);

    rng(830000);
    sym_idx = randi([1 cfg_ref.M], cfg_ref.Nsym_sys, 1);
    dref = cfg_ref.A(sym_idx);
    dref = dref(:);

    res_ref = run_case_system(dref, cfg_ref, g_rc, true, 'robust_proj');
    theta_ref = [double(res_ref.w_final)/2^cfg_ref.frac_bits; double(res_ref.b_final)/2^cfg_ref.frac_bits];

    figure('Name', sprintf('Empirical Lyapunov | %s', upper(cfg.lyap_noise_model)));
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h1 = gobjects(numel(cfg.lyap_variants),1);

    nexttile; hold on;
    h2 = gobjects(numel(cfg.lyap_variants),1);

    for iv = 1:numel(cfg.lyap_variants)
        variant = cfg.lyap_variants{iv};

        Vmat = [];
        Dmat = [];
        trace_n = [];

        for imc = 1:cfg.lyap_Nmc
            cfg_i = cfg;
            cfg_i.eq_variant = variant;
            cfg_i.mu_mode = 'decreasing';
            cfg_i.mu0 = cfg.mu;
            cfg_i.Nsym_sys = cfg.lyap_Nsym;
            cfg_i.trainLen = cfg_i.Nsym_sys;
            cfg_i.enable_eye_analysis = false;
            cfg_i.collect_learning_trace = true;
            cfg_i.trace_decim = cfg.lyap_trace_decim;
            cfg_i.verbose_case = false;
            cfg_i.noise_model = cfg.lyap_noise_model;
            cfg_i.seed0 = cfg.seed0 + uint32(840000 + 100*iv + imc);
            cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

            rng(840000 + 1000*iv + imc);
            sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
            d = cfg_i.A(sym_idx);
            d = d(:);

            res = run_case_system(d, cfg_i, g_rc, true, variant);

            nT = size(res.aux.theta_trace, 2);
            V = zeros(nT,1);

            for k = 1:nT
                th = res.aux.theta_trace(:,k);
                V(k) = norm(th - theta_ref)^2;
            end

            dV = [0; diff(V)];
            dV_ma = moving_average_vec(dV, cfg.lyap_movavg_len);

            if isempty(Vmat)
                Vmat = zeros(nT, cfg.lyap_Nmc);
                Dmat = zeros(nT, cfg.lyap_Nmc);
                trace_n = res.aux.trace_n(:);
            end

            Vmat(:,imc) = V;
            Dmat(:,imc) = dV_ma;
        end

        medV = median(Vmat, 2);
        medD = median(Dmat, 2);

        neg_frac = mean(medD(round(end/4):end) < 0);

        nexttile(1);
        h1(iv) = plot(trace_n, medV, 'LineWidth', 1.3);

        nexttile(2);
        h2(iv) = plot(trace_n, medD, 'LineWidth', 1.3);

        fprintf('[%s] median final V_n = %.6e | negative-drift fraction(after burn-in) = %.4f\n', ...
            variant, median(Vmat(end,:)), neg_frac);
    end

    nexttile(1);
    grid on;
    xlabel('sample index');
    ylabel('V_n = ||\theta_n - \theta_{ref}||^2');
    title('Empirical Lyapunov trajectory');
    legend(h1, cfg.lyap_variants, 'Location','best');

    nexttile(2);
    yline(0,'k--');
    grid on;
    xlabel('sample index');
    ylabel('moving-avg \Delta V_n');
    title('Empirical Lyapunov drift');
    legend(h2, cfg.lyap_variants, 'Location','best');
end

%% ============================================================
function run_tightness_boundedness_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('TIGHTNESS / BOUNDEDNESS VALIDATION SUITE\n');
    fprintf('noise    = %s\n', cfg.tight_noise_model);
    fprintf('variants ='); fprintf(' %s', cfg.tight_variants{:}); fprintf('\n');
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    figure('Name', sprintf('Tightness / boundedness | %s', upper(cfg.tight_noise_model)));
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h1 = gobjects(numel(cfg.tight_variants),1);

    nexttile; hold on;
    h2 = gobjects(numel(cfg.tight_variants),1);

    for iv = 1:numel(cfg.tight_variants)
        variant = cfg.tight_variants{iv};

        maxNorm = zeros(cfg.tight_Nmc,1);
        projRate = zeros(cfg.tight_Nmc,1);
        boxViol = zeros(cfg.tight_Nmc,1);

        for imc = 1:cfg.tight_Nmc
            cfg_i = cfg;
            cfg_i.eq_variant = variant;
            cfg_i.noise_model = cfg.tight_noise_model;
            cfg_i.Nsym_sys = cfg.tight_Nsym;
            cfg_i.enable_eye_analysis = false;
            cfg_i.collect_learning_trace = true;
            cfg_i.trace_decim = 20;
            cfg_i.verbose_case = false;
            cfg_i.seed0 = cfg.seed0 + uint32(850000 + 100*iv + imc);
            cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

            rng(850000 + 1000*iv + imc);
            sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
            d = cfg_i.A(sym_idx);
            d = d(:);

            res = run_case_system(d, cfg_i, g_rc, true, variant);

            maxNorm(imc) = res.aux.max_tap_norm_real;
            projRate(imc) = res.aux.proj_active_rate;
            boxViol(imc) = compute_sampled_box_violation(res.aux.theta_trace, cfg_i);
        end

        [xs1, ys1] = empirical_cdf_simple(maxNorm);
        [xs2, ys2] = empirical_cdf_simple(projRate);

        nexttile(1);
        h1(iv) = plot(xs1, ys1, 'LineWidth', 1.2);

        nexttile(2);
        h2(iv) = plot(xs2, ys2, 'LineWidth', 1.2);

        fprintf('[%s] median max||theta_n|| = %.6f | max(sampled box violation)=%.6e | median proj-rate=%.6f\n', ...
            variant, median(maxNorm), max(boxViol), median(projRate));
    end

    nexttile(1);
    grid on;
    xlabel('max_n ||\theta_n||');
    ylabel('empirical CDF');
    title('Tightness proxy: max tap-norm');
    legend(h1, cfg.tight_variants, 'Location','best');

    nexttile(2);
    grid on;
    xlabel('projection active rate');
    ylabel('empirical CDF');
    title('Projection activity');
    legend(h2, cfg.tight_variants, 'Location','best');
end

%% ============================================================
function run_tap_trajectory_suite(cfg)

    fprintf('\n==================================================\n');
    fprintf('TAP TRAJECTORY VALIDATION SUITE\n');
    fprintf('noise    = %s\n', cfg.taptraj_noise_model);
    fprintf('variants ='); fprintf(' %s', cfg.taptraj_variants{:}); fprintf('\n');
    fprintf('==================================================\n');

    g_rc = rc_pulse(cfg.alpha_eye, cfg.sps_eye, cfg.spanUI_eye);

    idx_pair = cfg.taptraj_idx(:).';
    if numel(idx_pair) ~= 2
        error('cfg.taptraj_idx must have two entries.');
    end

    figure('Name', sprintf('Tap trajectories | %s', upper(cfg.taptraj_noise_model)));
    tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

    nexttile; hold on;
    h1 = gobjects(numel(cfg.taptraj_variants),1);

    nexttile; hold on;
    h2 = gobjects(numel(cfg.taptraj_variants),1);

    nexttile; hold on;
    h3 = gobjects(numel(cfg.taptraj_variants),1);

    for iv = 1:numel(cfg.taptraj_variants)
        variant = cfg.taptraj_variants{iv};

        cfg_i = cfg;
        cfg_i.eq_variant = variant;
        cfg_i.noise_model = cfg.taptraj_noise_model;
        cfg_i.Nsym_sys = cfg.taptraj_Nsym;
        cfg_i.enable_eye_analysis = false;
        cfg_i.collect_learning_trace = true;
        cfg_i.trace_decim = cfg.taptraj_trace_decim;
        cfg_i.verbose_case = false;
        cfg_i.seed0 = cfg.seed0 + uint32(860000 + 100*iv);
        cfg_i = prepare_cfg_for_m(cfg_i, cfg_i.m_clt);

        rng(860000 + 1000*iv);
        sym_idx = randi([1 cfg_i.M], cfg_i.Nsym_sys, 1);
        d = cfg_i.A(sym_idx);
        d = d(:);

        res = run_case_system(d, cfg_i, g_rc, true, variant);

        t = res.aux.trace_n(:);
        TH = res.aux.theta_trace;

        nexttile(1);
        h1(iv) = plot(t, TH(idx_pair(1),:), 'LineWidth', 1.2);

        nexttile(2);
        h2(iv) = plot(t, TH(idx_pair(2),:), 'LineWidth', 1.2);

        nexttile(3);
        h3(iv) = plot(t, res.aux.tap_norm_trace(:), 'LineWidth', 1.2);
    end

    nexttile(1);
    grid on;
    xlabel('sample index');
    ylabel(sprintf('\\theta(%d)', idx_pair(1)));
    title('Selected tap trajectory #1');
    legend(h1, cfg.taptraj_variants, 'Location','best');

    nexttile(2);
    grid on;
    xlabel('sample index');
    ylabel(sprintf('\\theta(%d)', idx_pair(2)));
    title('Selected tap trajectory #2');
    legend(h2, cfg.taptraj_variants, 'Location','best');

    nexttile(3);
    grid on;
    xlabel('sample index');
    ylabel('||\theta_n||');
    title('Tap-norm trajectory');
    legend(h3, cfg.taptraj_variants, 'Location','best');
end

%% ============================================================
function v = moving_average_vec(x, L)
    x = x(:);
    n = numel(x);
    v = zeros(n,1);
    if L <= 1
        v = x;
        return;
    end
    for i = 1:n
        i1 = max(1, i-L+1);
        v(i) = mean(x(i1:i));
    end
end

%% ============================================================
function viol = compute_sampled_box_violation(theta_trace, cfg)

    if isempty(theta_trace)
        viol = nan;
        return;
    end

    Nf = cfg.Nf;
    Nb = cfg.Nb;

    W = theta_trace(1:Nf, :);
    if Nb > 0
        B = theta_trace(Nf+1:end, :);
    else
        B = zeros(0, size(theta_trace,2));
    end

    w_lo = cfg.w_min(:);
    w_hi = cfg.w_max(:);
    b_lo = cfg.b_min(:);
    b_hi = cfg.b_max(:);

    vw1 = max(max(w_lo - W, [], 2), 0);
    vw2 = max(max(W - w_hi, [], 2), 0);

    if Nb > 0
        vb1 = max(max(b_lo - B, [], 2), 0);
        vb2 = max(max(B - b_hi, [], 2), 0);
        viol = max([vw1(:); vw2(:); vb1(:); vb2(:)]);
    else
        viol = max([vw1(:); vw2(:)]);
    end
end

function C = hexvec_signed_tc(x, bits)
    mod_base = bitshift(int64(1), bits);
    u = mod(int64(x(:)), mod_base);
    width = ceil(bits/4);
    C = cellstr(upper(dec2hex(double(u), width)));
end

%% ============================================================
function [xs, ys] = empirical_cdf_simple(x)
    xs = sort(x(:));
    n = numel(xs);
    ys = (1:n)' / n;
end

function run_eq_debug_export(cfg)

    fprintf('\n==================================================\n');
    fprintf('EQUALIZER DEBUG EXPORT MODE\n');
    fprintf('==================================================\n');

    cfg_i = prepare_cfg_for_m(cfg, cfg.m_clt_sys);
    cfg_i.enable_eq_debug        = true;
    cfg_i.verbose_case           = false;
    cfg_i.enable_eye_analysis    = false;
    cfg_i.store_dfe_history      = false;
    cfg_i.collect_learning_trace = false;

    Ndbg    = cfg_i.eq_debug_N;
    outFile = sprintf('%s_m%d.xlsx', cfg_i.eq_debug_file_prefix, cfg_i.m_clt);

    rng(cfg_i.eq_debug_seed);
    sym_idx = randi([1 cfg_i.M], Ndbg, 1);
    d       = cfg_i.A(sym_idx);
    d       = d(:);

    g_rc = rc_pulse(cfg_i.alpha_eye, cfg_i.sps_eye, cfg_i.spanUI_eye);

    res = run_case_system(d, cfg_i, g_rc, cfg_i.eq_debug_use_awgn, cfg_i.eq_debug_variant);

    dbg = res.aux.sample_debug;
    if isempty(dbg)
        error('sample_debug is empty. Check cfg_i.enable_eq_debug.');
    end

    Q  = cfg_i.frac_bits;
    TB = cfg_i.total_bits;

    d_hat_fx = q_from_real(res.d_hat, Q, TB);

    T = table( ...
        (1:Ndbg).', ...
        sym_idx(:), ...
        res.d(:), ...
        double(res.d_fx(:)), ...
        q_to_real(res.d_fx(:), Q), ...
        res.r_clean(:), ...
        double(res.r_clean_fx(:)), ...
        q_to_real(res.r_clean_fx(:), Q), ...
        res.noise_float(:), ...
        double(res.noise_fx(:)), ...
        q_to_real(res.r_fx(:), Q), ...
        double(res.r_fx(:)), ...
        q_to_real(res.y_fx(:), Q), ...
        double(res.y_fx(:)), ...
        double(dbg.d_des_fx(:)), ...
        q_to_real(dbg.d_des_fx(:), Q), ...
        double(dbg.e_raw_fx(:)), ...
        q_to_real(dbg.e_raw_fx(:), Q), ...
        double(dbg.e_up_fx(:)), ...
        q_to_real(dbg.e_up_fx(:), Q), ...
        res.d_hat(:), ...
        double(d_hat_fx(:)), ...
        dbg.do_update(:), ...
        double(dbg.mu_acc(:)), ...
        dbg.proj_hits(:), ...
        'VariableNames', { ...
            'sample', ...
            'sym_idx', ...
            'tx_sym', ...
            'tx_fx_dec', 'tx_fx_real', ...
            'after_isi_real', ...
            'after_isi_fx_dec', 'after_isi_fx_real', ...
            'noise_real', ...
            'noise_fx_dec', ...
            'before_eq_real', 'before_eq_fx_dec', ...
            'after_eq_real', 'after_eq_fx_dec', ...
            'd_des_fx_dec', 'd_des_real', ...
            'e_raw_fx_dec', 'e_raw_real', ...
            'e_clip_fx_dec', 'e_clip_real', ...
            'out_slicer_real', 'out_slicer_fx_dec', ...
            'do_update', ...
            'mu_acc_dec', ...
            'proj_hits'} );

    for k = 1:cfg_i.Nf
        T.(sprintf('xbuf%d_fx_dec', k-1))      = double(dbg.x_buf(:,k));
        T.(sprintf('xbuf%d_real', k-1))        = q_to_real(dbg.x_buf(:,k), Q);

        T.(sprintf('w%d_before_fx_dec', k-1)) = double(dbg.w_before(:,k));
        T.(sprintf('w%d_before_real', k-1))   = q_to_real(dbg.w_before(:,k), Q);

        T.(sprintf('dw%d_acc_dec', k-1))      = double(dbg.delta_w_acc(:,k));

        T.(sprintf('w%d_after_fx_dec', k-1))  = double(dbg.w_after(:,k));
        T.(sprintf('w%d_after_real', k-1))    = q_to_real(dbg.w_after(:,k), Q);

        T.(sprintf('dw%d_visible_lsb', k-1))  = double(dbg.w_after(:,k) - dbg.w_before(:,k));
    end

    for k = 1:cfg_i.Nf
        T.(sprintf('ffe%d_term_acc', k-1))    = double(dbg.ff_term_acc(:,k));
        T.(sprintf('ffe%d_term_fx_dec', k-1)) = double(dbg.ff_term_fx(:,k));
        T.(sprintf('ffe%d_term_real', k-1))   = q_to_real(dbg.ff_term_fx(:,k), Q);  
    end

    for k = 1:cfg_i.Nb
        T.(sprintf('fbuf%d_fx_dec', k-1))      = double(dbg.fb_buf(:,k));
        T.(sprintf('fbuf%d_real', k-1))        = q_to_real(dbg.fb_buf(:,k), Q);

        T.(sprintf('b%d_before_fx_dec', k-1)) = double(dbg.b_before(:,k));
        T.(sprintf('b%d_before_real', k-1))   = q_to_real(dbg.b_before(:,k), Q);

        T.(sprintf('db%d_acc_dec', k-1))      = double(dbg.delta_b_acc(:,k));

        T.(sprintf('b%d_after_fx_dec', k-1))  = double(dbg.b_after(:,k));
        T.(sprintf('b%d_after_real', k-1))    = q_to_real(dbg.b_after(:,k), Q);

        T.(sprintf('db%d_visible_lsb', k-1))  = double(dbg.b_after(:,k) - dbg.b_before(:,k));
    end

    for k = 1:cfg_i.Nb
        T.(sprintf('dfe%d_term_acc', k-1))    = double(dbg.fb_term_acc(:,k));
        T.(sprintf('dfe%d_term_fx_dec', k-1)) = double(dbg.fb_term_fx(:,k));
        T.(sprintf('dfe%d_term_real', k-1))   = q_to_real(dbg.fb_term_fx(:,k), Q);
    end

    T.sum_ff_acc_dec = double(dbg.sum_ff_acc(:));
    T.sum_fb_acc_dec = double(dbg.sum_fb_acc(:));
    T.acc_total_dec  = double(dbg.acc_total(:));
    T.y_from_acc_dec = double(dbg.y_from_acc(:));
    T.y_from_acc_real = q_to_real(dbg.y_from_acc(:), Q);

    T.sum_ff_fx_dec     = sum(double(dbg.ff_term_fx), 2);
    T.sum_fb_fx_dec     = sum(double(dbg.fb_term_fx), 2);
    T.i_slicer_like_dec = T.sum_ff_fx_dec - T.sum_fb_fx_dec;
    T.i_slicer_like_real = T.i_slicer_like_dec / 2^Q;

    H = table( ...
        (1:Ndbg).', ...
        hexvec_signed_tc(res.d_fx(:), TB), ...
        hexvec_signed_tc(res.r_clean_fx(:), TB), ...
        hexvec_signed_tc(res.noise_fx(:), TB), ...
        hexvec_signed_tc(res.r_fx(:), TB), ...
        hexvec_signed_tc(res.y_fx(:), TB), ...
        hexvec_signed_tc(dbg.d_des_fx(:), TB), ...
        hexvec_signed_tc(dbg.e_raw_fx(:), TB), ...
        hexvec_signed_tc(dbg.e_up_fx(:), TB), ...
        hexvec_signed_tc(d_hat_fx(:), TB), ...
        hexvec_signed_tc(dbg.y_from_acc(:), TB), ...
        hexvec_signed_tc(int32(T.i_slicer_like_dec), TB), ...
        'VariableNames', { ...
            'sample', ...
            'tx_fx_hex', ...
            'after_isi_fx_hex', ...
            'noise_fx_hex', ...
            'before_eq_fx_hex', ...
            'after_eq_fx_hex', ...
            'd_des_fx_hex', ...
            'e_raw_fx_hex', ...
            'e_clip_fx_hex', ...
            'out_slicer_fx_hex',...
            'y_from_acc_hex',...
            'i_slicer_like_hex'} );

    Meta = table( ...
        { ...
            'variant'; ...
            'use_awgn'; ...
            'Ndbg'; ...
            'm_clt'; ...
            'SNRdB'; ...
            'Nf'; ...
            'Nb'; ...
            'D'; ...
            'mu'; ...
            'err_clip'; ...
            'adapt_frac_bits'; ...
            'adapt_total_bits' ...
        }, ...
        { ...
            cfg_i.eq_debug_variant; ...
            num2str(cfg_i.eq_debug_use_awgn); ...
            num2str(Ndbg); ...
            num2str(cfg_i.m_clt); ...
            num2str(cfg_i.SNRdB); ...
            num2str(cfg_i.Nf); ...
            num2str(cfg_i.Nb); ...
            num2str(cfg_i.D); ...
            num2str(cfg_i.mu, '%.12g'); ...
            num2str(cfg_i.err_clip, '%.12g'); ...
            num2str(cfg_i.adapt_frac_bits); ...
            num2str(cfg_i.adapt_total_bits) ...
        }, ...
        'VariableNames', {'name','value'});

    writetable(Meta, outFile, 'Sheet', 'Meta');
    writetable(T,    outFile, 'Sheet', 'SampleTrace');
    writetable(H,    outFile, 'Sheet', 'HexTrace');

    fprintf('Equalizer debug Excel export done: %s\n', outFile);
end
