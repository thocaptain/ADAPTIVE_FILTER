# Kết quả chạy RTL ↔ model C++

RTL đã sửa căn FFE/error và thêm training; 18/18 ca độc lập chạy lại PASS.
24/24 ca training vòng kín cũng PASS, xem `../eq_chain/TRAINING_RESULTS.md`.
Các nhận xét lỗi chưa sửa bên dưới thuộc lịch sử trước bản training.

Đã chạy thêm convergence vòng kín; xem `../eq_chain/CONVERGENCE_RESULTS.md`.
FFE còn lệch căn error/sample trong RX kín. PASS ở đây là số học từng khối
với error được testbench căn sẵn, không chứng minh RX kín đã đúng.

## Sau sửa số học LMS và bão hòa FFE

Đã chuyển hệ số nội bộ FFE/DFE sang signed 40 bit / 20 bit phần lẻ.
Delta tính từ toàn bộ tích mu*error*input, round halfway away from zero,
không dịch/cắt trung gian. Hệ số visible Q12 được round/saturate từ Q20.
FFE cũng saturate từng tích Q12 trước khi cộng, theo MATLAB v26.

Chạy `make all`: **18/18 ca PASS**, 9 ca mỗi khối, 108960 sample/khối:
7 ca gốc đều PASS, thêm `adapt_rounding` (128 mẫu) và
`adapt_acc_saturation` (100000 mẫu). Ca dài ép chạm biên accumulator 40 bit,
rồi đảo chiều error để kiểm tra khả năng thoát bão hòa và phần dư nội bộ.
Tất cả output/taps/valid: 0 mismatch, max absolute error=0, RMSE=0.
Model gốc và driver căn latency không thay đổi trong lần sửa số học này.

Đã chạy lại `eq_chain/make all`: 7/7 ca hệ số cố định PASS.
Chưa xác minh khả năng tự hội tụ của RX kín với LMS bật, robust_proj,
MATLAB runtime, synthesis hoặc timing. Phép so LMS ở đây cấp error biết trước.

## Lịch sử trước sửa số học LMS

Sau sửa pipeline DFE: đã chạy lại `make dfe`, chỉnh driver lấy output y
sau một decision register và taps sau update. Kết quả DFE vẫn giữ nguyên
4 ca PASS / 3 ca LMS FAIL như bảng dưới; khác biệt LMS không được sửa.
Test toàn chuỗi hiện PASS cả 7 ca, xem `../eq_chain/RESULTS.md`.
SHA bên dưới mô tả bản source trước sửa pipeline.

Chạy ngày 2026-11-02, Ubuntu-20.04 WSL, Verilator 4.028.
Lệnh: `make all`. Build cả hai khối thành công, arithmetic contracts PASS.
Lệnh tổng trả mã lỗi vì phát hiện mismatch số học, không phải build fail.

Mỗi khối 7 ca / 8832 sample. Cùng stimulus cho model và RTL; error biết trước.

| Ca | FFE | DFE |
| --- | --- | --- |
| fixed_basic | PASS | PASS |
| fixed_saturation | FAIL: y lệch 11/128 mẫu | PASS |
| adapt_small | FAIL | FAIL |
| adapt_large | FAIL | FAIL |
| bypass | PASS | PASS |
| fixed_random | PASS, 4096 mẫu | PASS, 4096 mẫu |
| adapt_random | FAIL | FAIL |

Valid khớp toàn bộ các ca. Tổng 7 ca PASS và 7 ca FAIL.

## Ví dụ lệch đầu tiên

- FFE fixed_saturation: sample 12, y model=-8192, RTL=-32768,
  delta=-24576 LSB (= -6.0). Hệ số vẫn khớp toàn bộ ca này.
- FFE adapt_small: sample 1, w0 model=1024, RTL=1023, delta=-1 LSB.
- DFE adapt_small: sample 0, b0 model=2048, RTL=2049, delta=+1 LSB.

Đối chiếu mã nguồn cho thấy hai khác biệt liên quan trực tiếp:

1. MATLAB v26/model C++ bão hòa từng tích FFE trước khi cộng; RTL chỉ dịch
   phải từng tích rồi cộng, bão hòa tổng. Điều này giải thích ca hệ số lớn.
2. RTL cập nhật trực tiếp Q12 bằng dịch phải; model giữ accumulator Q20 và
   round khi đưa hệ số về Q12. Ví dụ DFE sample 0 có feedback=-12288,
   error=1, mu_q16=32: RTL dịch delta âm về -1 LSB rồi trừ nên b0 tăng 1;
   model có delta=-2 đơn vị Q20, chưa đủ đổi hệ số Q12 nhìn thấy.

Các số này đo sự khác biệt với contract model đã port. Chưa chứng minh
bản port tương đương một lần chạy MATLAB, chưa test RX kín hoặc robust_proj.
Không thay đổi RTL để ép PASS. Chi tiết từng điểm nằm trong `results/*_diff.csv`.

## Nguồn tại thời điểm chạy (SHA256)

```text
MATLAB v26:
c2dc91ab4ff43b79b4026d91688d04220191f04843abd6157ab8c7b9c78dad35
00_src/rx/rx_ffe.sv:
4dda9133b4587cdf8559eb44a7a9c46636ea416bffd5edd14dd37fbb15bcbc38
00_src/rx/rx_dfe.sv:
9d8b2948f64370137e2eb43a26bc26f438fad757318a49d15da07734337d350c
```
