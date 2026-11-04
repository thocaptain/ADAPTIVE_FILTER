function export_vectors(out_dir)
% Independent FFE/DFE contract from the v26 MATLAB model, plain LMS only.
% Extract the numerical helpers verbatim: no Python reimplementation as oracle.
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
if nargin == 0, out_dir = fullfile(here, 'vectors'); end
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
helper_dir = tempname;
mkdir(helper_dir);
cleanup = onCleanup(@() cleanup_helpers(helper_dir)); %#ok<NASGU>
model_path = fullfile(root, 'reference', 'full_demo_v26_clt_awgn_fixed_paper.m');
source = fileread(model_path);
copyfile(model_path, fullfile(out_dir, 'model_source_snapshot.m'));
starts = regexp(source, '(?m)^function\s', 'start');
starts(end+1) = length(source)+1;
names = {'q_sat','sat_i64','round_shift_right_i64', ...
    'q_convert_i32_to_i64','q_convert_i64_to_i32','lms_delta_qacc'};
for k = 1:numel(names)
    found = false;
    for j = 1:numel(starts)-1
        block = source(starts(j):starts(j+1)-1);
        header = strtok(block, sprintf('\n'));
        if ~isempty(regexp(header, ['\<', names{k}, '\s*\('], 'once'))
            f = fopen(fullfile(helper_dir, [names{k}, '.m']), 'w');
            assert(f >= 0, 'Cannot write helper');
            fprintf(f, '%s', block); fclose(f); found = true; break;
        end
    end
    assert(found, ['Missing v26 helper: ', names{k}]);
end
addpath(helper_dir, '-begin');

cases = {'fixed_basic','fixed_saturation','adapt_small','adapt_large','bypass'};
for kind = {'ffe','dfe'}
    module = kind{1};
    for ci = 1:numel(cases)
        name = cases{ci}; N = 128;
        pattern = [0 4096 -4096 12288 -12288 8191 -8193 1 -1 32767 -32768];
        x = pattern(mod(0:N-1, numel(pattern))+1);
        if strcmp(module, 'dfe')
            levels = [-12288 -4096 4096 12288];
            x = levels(mod(0:N-1, 4)+1);
        end
        e_pattern = [1 -1 2048 -2048 8192 -8192 0];
        errors = e_pattern(mod(0:N-1, numel(e_pattern))+1);
        lms = strncmp(name, 'adapt_', 6); enabled = ~strcmp(name, 'bypass');
        mu = 32; % Exact common value: 32/65536 = 512/1048576.
        if strcmp(name, 'adapt_large'), mu = 4096; end
        w = int32([1024; 3072; -512]); b = int32(2048);
        if strcmp(name, 'fixed_saturation')
            w = int32([24576; -24576; 24576]); b = int32(24576);
        end
        initial = [double(w(:))' double(b)];
        wa = q_convert_i32_to_i64(w, 12, 20, 40);
        ba = q_convert_i32_to_i64(b, 12, 20, 40);
        buf = int32(zeros(3,1));
        stem = fullfile(out_dir, [module, '_', name]);
        sf = fopen([stem, '_stim.csv'], 'w');
        gf = fopen([stem, '_expected.csv'], 'w');
        assert(sf >= 0 && gf >= 0, 'Cannot write vectors');
        fprintf(sf, 'sample,input,error,lms,enable,mu,w0,w1,w2,b0\n');
        if strcmp(module, 'ffe')
            fprintf(gf, 'sample,valid,y,w0,w1,w2\n');
        else
            fprintf(gf, 'sample,valid,y,b0\n');
        end
        for n = 1:N
            fprintf(sf, '%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n', ...
                n-1,x(n),errors(n),lms,enabled,mu,initial);
            if strcmp(module, 'ffe')
                buf = [int32(x(n)); buf(1:2)];
                % v26 quantizes/saturates each product BEFORE summation.
                terms = q_sat(bitshift(int64(w).*int64(buf), -12), 16);
                y = q_sat(sum(double(terms)), 16);
                if ~enabled, y = buf(1); end
                if lms
                    for tap = 1:3
                        delta = lms_delta_qacc(int64(mu*16), int32(errors(n)), buf(tap), 12, 40);
                        wa(tap) = sat_i64(wa(tap)+delta, 40);
                    end
                    w = q_convert_i64_to_i32(wa, 20, 12, 16);
                end
                fprintf(gf, '%d,1,%d,%d,%d,%d\n', n-1,y,w);
            else
                % input is already d_hat[n-1], NOT the current slicer output.
                y = q_sat(bitshift(int64(b)*int64(x(n)), -12), 16);
                if ~enabled, y = int32(0); end
                if lms
                    delta = lms_delta_qacc(int64(mu*16), int32(errors(n)), int32(x(n)), 12, 40);
                    ba = sat_i64(ba-delta, 40);
                    b = q_convert_i64_to_i32(ba, 20, 12, 16);
                end
                fprintf(gf, '%d,1,%d,%d\n', n-1,y,b);
            end
        end
        fclose(sf); fclose(gf);
        fprintf('Exported %s %s (%d samples)\n', module,name,N);
    end
end
end

function cleanup_helpers(folder)
rmpath(folder);
if exist(folder, 'dir'), rmdir(folder, 's'); end
end
