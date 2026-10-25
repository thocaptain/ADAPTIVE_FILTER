# Kết quả chạy model Python v26

Ngày chạy: 24/10/2026. Phần mô phỏng mất khoảng 105 giây trên môi trường hiện tại.

Đã chuyển và chạy phần numerical core của
`reference/full_demo_v26_clt_awgn_fixed_paper.m` bằng Python trong WSL.
Chưa thực hiện đối chiếu output giữa MATLAB và Python, nên các số bên dưới là
**kết quả thực chạy của bản Python**, chưa chứng nhận tương đương từng bit với MATLAB.

Code: `01_bench/full_demo_v26_clt_awgn_fixed_paper.py`.
Hướng dẫn, phạm vi và quy tắc số học: `99_doc/PYTHON_V26_MODEL.md`.
Dữ liệu gốc: `10_sim/python_v26/results.json`, `summary.csv`, `run.log`.

## Điều kiện chạy

- Python 3.8.10; NumPy 1.24.3; SciPy 1.10.1; Matplotlib 3.7.5.
- PAM-4 Gray: -3, -1, +1, +3. Dữ liệu random theo reference, chưa phải PRBS.
- Kênh `r_clean[n] = s[n] + 0.5*s[n-1]`: h0=1, h1=0.5.
- 12 lane Taus88, 12 bit uniform, CLT centering = 24570, gain Q12 = 4096.
- Datapath Q4.12; accumulator cập nhật hệ số 40 bit, 20 bit phần lẻ.
- FFE 3 tap, DFE 1 tap, D=1, mu=0.0005, training=3000 sample.
- 200.000 symbol/case. Sau khi loại training: 197.000 symbol / 394.000 bit/case.
- Nhánh No-EQ dùng delay=0; nhánh EQ dùng delay=1, cùng bộ TX symbol để so sánh.
- Bộ kiểm tra gồm 12 numerical contract tests: rounding, overflow, Taus88,
  centering, slicer, Gray coding, căn delay, đáp án DFE biết trước, projection,
  SM-sign và phép cập nhật Q20 tính tay.

## Kết quả chính: robust_proj

| Điều kiện | BER trước EQ, đã căn đúng | BER sau EQ | Bit lỗi sau EQ / bit đo |
| --- | ---: | ---: | ---: |
| Không nhiễu | 0.18783756 | 0 | 0 / 394000 |
| CLT noise, SNR 15 dB | 0.18829949 | 0.01488832 | 5866 / 394000 |
| CLT noise, SNR 20 dB | 0.18777411 | 0.0000152284 | 6 / 394000 |
| CLT noise, SNR 25 dB | 0.18783756 | 0 | 0 / 394000 |
| Hệ số cố định, khung mới, 20 dB | 0.18757360 | 0.0000152284 | 6 / 394000 |

Các dòng BER=0 chỉ có nghĩa là chưa thấy lỗi trong số bit đã đo.
Đây là thử nghiệm một seed, chưa phải đường BER Monte Carlo nhiều seed.

Nhánh No-EQ quanh 0.1875 là phù hợp với đáp án giải tích của kênh không nhiễu:
với 16 cặp symbol liên tiếp đồng xác suất, 6 cặp vượt một ngưỡng lân cận;
BER Gray là 6/(16*2)=3/16. ISI đang chi phối nhánh này ở các SNR đã thử.

## Hệ số tìm được

| Case | w0 | w1 | w2 | b0 |
| --- | ---: | ---: | ---: | ---: |
| Không nhiễu | 0 | 1 | 0 | 0.5 |
| 20 dB, cuối khung adaptive | 0.0078125 | 0.986083984375 | -0.00537109375 | 0.49267578125 |

Bộ 20 dB dạng integer Q4.12: `[32, 4039, -22, 2018]`.
Dạng hex: `[0020, 0FC7, FFEA, 07E2]`.

Thử nghiệm frozen lấy đúng bộ 20 dB này, **tắt cập nhật hệ số**, đổi seed symbol
từ 1 sang 2 và seed Taus88 từ 2651 sang 2652. Counter cập nhật bằng 0, kết quả
6 bit lỗi/394000 bit. Đây là bước thử phù hợp hướng tính hệ số offline của project;
chưa chứng minh đây là bộ hệ số tối ưu cho mọi profile hoặc SNR.

Trường hợp không nhiễu hội tụ về FFE=[0,1,0], b0=0.5. Kết quả hợp lý với D=1:
đầu ra FFE là r[n-1], và feedback trừ 0.5 lần quyết định symbol trước.

## Chất lượng nhiễu CLT: một triệu mẫu

| Thống kê | Giá trị |
| --- | ---: |
| Mean | -0.000458640625 |
| Standard deviation | 0.999921205955 |
| Skewness | 0.002673788225 |
| Excess kurtosis | -0.10253064455 |
| Excess kurtosis lý thuyết m=12 | -0.1 |
| Max abs ACF, lag 1..40 | 0.002011506195 |
| KS distance tới Gaussian chuẩn | 0.002725317531 |
| KS distance tới PMF CLT fixed-point lý tưởng | 0.000937900447 |

Mean/std và kurtosis phù hợp kỳ vọng của CLT 12 lane. Chưa thấy tương quan lớn
ở các lag đã kiểm tra; điều này chưa chứng minh tính độc lập giữa các lane.

Đuôi CLT nhẹ hơn Gaussian chuẩn:

| Điều kiện | Xác suất đo | CLT fixed-point lý tưởng | Gaussian chuẩn |
| --- | ---: | ---: | ---: |
| abs(z)>3 | 0.002017 | 0.0020130674 | 0.0026997961 |
| abs(z)>4 | 0.000012 | 0.0000170397 | 0.0000633425 |
| abs(z)>5 | 0 / 1000000 mẫu | 0.00000000417 | 0.000000573303 |

Vì vậy, bộ sinh thích hợp để đánh giá ban đầu nhưng không nên coi là Gaussian
chính xác khi diễn giải BER cực thấp. Dòng abs(z)>5 có số mẫu kỳ vọng rất nhỏ,
nên quan sát 0 mẫu vượt ngưỡng không đủ để kiểm chứng đuôi này.

## So sánh các thuật toán

Ở Gaussian 20 dB, plain, robust, proj và robust_proj đều có 6 bit lỗi/394000 bit.
Counter clipping và projection đều bằng 0: các cơ chế này chưa hoạt động trong
điều kiện đó, nên kết quả không cho thấy lợi thế riêng của robust/projected LMS.
SM-sign có 41 bit lỗi, với 1189 lần update trên 200000 sample.

Với gaussmix 20 dB (xác suất impulse 0.01, hệ số nhân cấu hình 8 bị lượng tử hóa
saturate theo Q4.12 của reference):

| Variant | BER sau EQ | Bit lỗi |
| --- | ---: | ---: |
| plain | 0.0038934010 | 1534 |
| sm_sign | 0.0038350254 | 1511 |
| robust_proj | 0.0038934010 | 1534 |

Kết quả một seed chưa đủ kết luận SM-sign tốt hơn. Robust_proj có 121 sample
bị clip error nhưng không có projection hit; phép thử này vẫn chưa cho thấy
cải thiện BER steady-state so với plain. Các variant cùng dùng DD gate theo cấu
hình gốc, nên plain ở đây cũng không phải một baseline LMS hoàn toàn bỏ gating.

## Các điểm phải xử lý trước khi dùng làm golden model chính thức

1. **Căn BER nhánh No-EQ:** helper MATLAB dùng D=1 cho cả nhánh raw và EQ.
   Khi giữ nguyên cùng cửa sổ 199999 symbol ở 20 dB, cách cũ cho raw
   BER=0.43858219, trong khi căn đúng cho 0.18774594. Riêng sau training, raw BER
   là 0.18777411 như bảng chính. Bản Python giữ metric legacy để đối chiếu và
   báo cáo metric đã sửa riêng. Test đường truyền lý tưởng cũng xác nhận độc lập
   rằng sai delay tạo lỗi giả. Các kiểm tra cùng cửa sổ nằm trong
   `10_sim/python_v26/artifact_validation.json`.
2. **Tách training khỏi BER:** ở 20 dB, EQ BER theo toàn khung kiểu cũ là
   0.0002750014; sau training còn 0.0000152284. Phải thống nhất cửa sổ BERT.
3. **Slicer tại đúng ngưỡng:** source chọn mức thấp hơn tại -2,0,+2, còn README
   chọn mức cao hơn. Python mặc định giữ quy tắc source, có lựa chọn upper để
   sau này thống nhất với RTL.
4. **Adaptive so với static:** source vẫn cập nhật cả khung. Với phạm vi README,
   cần tách giai đoạn tính hệ số offline và chạy đánh giá bằng hệ số đã cố định.
5. **Profile kênh và dữ liệu:** hiện chưa dùng h0=0.8 và các preset khác, chưa có
   PRBS-7/15. Đây là việc tiếp theo của bước B trước khi chốt giao tiếp ở A.
6. **Phạm vi port:** chưa chuyển các suite ODE/Lyapunov/Monte Carlo lớn hoặc
   thông số eye height/width/jitter; chưa xác nhận tương đương runtime MATLAB.

Nhận xét: chuỗi PAM-4/ISI/CLT/FFE-DFE của bản Python chạy ổn trong phép thử này,
hệ số có ý nghĩa vật lý và có thể dùng làm nền cho bước B. Cần sửa cách đo và
thống nhất các quy tắc trên trước khi gọi đây là golden model chính thức cho RTL.

Đã kiểm tra lại 12800 sample debug bằng phép tính vector hóa độc lập từ các
buffer và hệ số đã xuất: kết quả khớp y_fx lưu trong NPZ/CSV. Phép cộng kênh và
slicer cũng khớp các vector đã lưu. Đây là kiểm tra nhất quán bản Python, không
thay thế việc đối chiếu MATLAB hoặc RTL.

![Đồ thị kết quả](../10_sim/python_v26/overview.png)
