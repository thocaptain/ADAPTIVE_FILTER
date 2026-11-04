# Test FFE / DFE

Hướng dẫn chính, lệnh chạy và sơ đồ model C++/SV nằm trong
[eq_independent/README.md](eq_independent/README.md).

```bash
cd ~/adaptive_eq/02_test/eq_independent
make MODE=DFE_ONLY TEST=FIXED
make MODE=FFE_ONLY TEST=LMS N=4096
make MODE=FFE_DFE TEST=LMS N=10000 OPENWAVE=1
make clean
```

Có thể chạy từ repo root bằng `make -C 02_test MODE=... TEST=...`.
Log và waveform luôn nằm ngay trong `02_test/eq_independent`.
Bộ test dùng C++17 và Verilator, không cần Python/MATLAB.
