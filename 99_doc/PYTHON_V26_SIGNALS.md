# Chạy lại: tín hiệu TX/RX và tap adaptive

Đầu ra: `10_sim/python_v26_signals/`.
Lệnh chạy từ repository root:

```bash
python3 01_bench/full_demo_v26_clt_awgn_fixed_paper.py --output 10_sim/python_v26_signals
```

Đã chạy lại đủ 12 case, 200000 symbol/case, 1000000 mẫu thống kê CLT.
Các số liệu BER, tap cuối và bảy mảng số đã lưu từ lần trước đều được tái lập
giống hệt. Có 14 numerical contract tests đạt, gồm kiểm tra căn tín hiệu và
thời điểm cập nhật tap. Chi tiết kiểm tra nằm trong `rerun_validation.json`.

## Hình tín hiệu truyền và nhận

![TX và RX](../10_sim/python_v26_signals/tx_rx_signals.png)

Case hiển thị: robust_proj, SNR=20 dB, h0=1, h1=0.5, D=1.
Hình phóng 64 symbol TX từ n=4001 đến n=4064, gồm bốn hàng:

1. Symbol phát s[n].
2. Tín hiệu nhận r[n] sau kênh ISI và nhiễu CLT, trước equalizer.
3. Đầu ra trước slicer y[n+D], đã dịch đúng D=1 để so với cùng s[n].
4. Symbol quyết định d_hat[n+D] so với s[n].

Trong đoạn này, slicer trực tiếp từ r[n] sai 22/64 symbol, sau EQ sai 0/64.
Trên toàn cửa sổ đo sau training, case này có 6 bit lỗi/394000 bit.
Đoạn minh họa nằm sau training trong lúc hệ số vẫn tiếp tục thích nghi.
Giá trị tap cuối bên dưới thuộc thời điểm sample 200000.

Các hình là mẫu tín hiệu ở tốc độ symbol, chưa có mô phỏng DAC/ADC hoặc dạng
sóng analog. Giá trị từng điểm nằm trong `tx_rx_signals.csv`. Có thêm bản PDF.

## Tap adaptive thực tế

![Tap adaptive](../10_sim/python_v26_signals/adaptive_taps.png)

Cột trái của hình cho thấy 20000 sample đầu; cột phải phóng 20000 sample cuối.
Đường gạch là tham chiếu không nhiễu. Đường ngang đen là trung bình các tap
Q4.12 của toàn bộ 20000 sample cuối, vùng tô là mean +/- một standard deviation.
Chấm đen cuối đồ thị là tap đúng tại sample 200000.

Giá trị **sau lần cập nhật cuối**, SNR=20 dB:

| Tap | Số thực chính xác | Integer Q4.12 | Hex 16 bit |
| --- | ---: | ---: | --- |
| w0 | 0.0078125 | 32 | 0020 |
| w1 | 0.986083984375 | 4039 | 0FC7 |
| w2 | -0.00537109375 | -22 | FFEA |
| b0 | 0.49267578125 | 2018 | 07E2 |

Đầu ra y[200000] được tính trước lần cập nhật cuối, với bộ tap integer
`[35, 4041, -23, 2019]`. Sau khi lấy error của sample đó để cập nhật, bộ tap
trở thành `[32, 4039, -22, 2018]` như bảng trên. Hai thời điểm đều được xuất rõ
trong `adaptive_taps_summary.json`/`.csv`.

Thống kê trên 20000 sample cuối, dùng đủ lịch sử từng sample:

| Tap | Mean | Standard deviation | Min | Max |
| --- | ---: | ---: | ---: | ---: |
| w0 | 0.005284741211 | 0.004250115928 | -0.00830078125 | 0.017333984375 |
| w1 | 0.984708374023 | 0.004369243580 | 0.9716796875 | 0.99658203125 |
| w2 | 0.000291442871 | 0.003797367950 | -0.009765625 | 0.009765625 |
| b0 | 0.493788354492 | 0.003811722001 | 0.47998046875 | 0.505615234375 |

Với nhiễu và mu cố định, tap tiếp tục dao động quanh vùng hội tụ. Vì vậy cần
ghi rõ đang dùng snapshot cuối, trung bình một cửa sổ, hay Polyak average.
Thống kê mean ở bảng này là trung bình tap nhìn thấy ở Q4.12; nó khác cách
Polyak average của accumulator nội bộ trong reference.

## Đối chiếu không nhiễu

Cùng lượt chạy, case không nhiễu cho FFE=[0,1,0], b0=0.5. Với D=1:

```text
r[n-1] = s[n-1] + 0.5*s[n-2]
y[n]   = r[n-1] - 0.5*d_hat[n-1]
```

Khi quyết định trước đúng, d_hat[n-1]=s[n-2], nên y[n]=s[n-1]. Vì vậy tap chính
nằm tại w1 theo quy ước độ trễ của model. Bộ này là tham chiếu zero-forcing
không nhiễu; bộ tap noisy ở 20 dB được ghi riêng ở trên.

## Dữ liệu bàn giao

- `tx_rx_signals.png` / `.pdf` và `tx_rx_signals.csv`.
- `adaptive_taps.png` / `.pdf`.
- `adaptive_taps_summary.json` / `.csv`: snapshot cuối và thống kê chính xác.
- `adaptive_taps_trace.csv`: mỗi 50 sample và thêm đúng sample cuối.
- `gaussian_20db_vectors.npz`, field `tap_after_fx`: đủ 200000 x 4 tap integer.
- `results.json`, `summary.csv`, `run.log`: số liệu đầy đủ của lượt chạy lại.
- `rerun_validation.json`: tái lập số liệu, kiểm tra lịch sử tap và căn điểm vẽ.
