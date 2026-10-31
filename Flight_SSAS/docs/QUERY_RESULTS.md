# Kết quả 15 truy vấn FlightCube

Kết quả thực thi thật trên `localhost / Flight_SSAS / FlightCube`, dữ liệu năm 2024. Tất cả 15 truy vấn đã được đối chiếu độc lập với CSV 18 cột bằng pandas; xem [verification.json](../results/verification.json).

Các tỷ lệ dưới đây là số đã định dạng `%`; số phút là phút, cự ly là dặm. Các giá trị âm của trung bình đến thể hiện đến sớm. Tất cả kết luận chỉ áp dụng cho mẫu 50.142 bản ghi.

| Câu | Số dòng kết quả | Kiểm chứng |
|---:|---:|---|
| 1 | 1 | PASS |
| 2 | 16 | PASS |
| 3 | 5 | PASS |
| 4 | 3 | PASS |
| 5 | 3 | PASS |
| 6 | 15 | PASS |
| 7 | 592 | PASS |
| 8 | 7 | PASS |
| 9 | 2 | PASS |
| 10 | 2 | PASS |
| 11 | 142 | PASS |
| 12 | 14 | PASS |
| 13 | 5 | PASS |
| 14 | 5 | PASS |
| 15 | 8 | PASS |

## Câu 1: Tổng chuyến, chuyến không hủy, chuyến hủy và phút trễ cất cánh của AA năm 2024.

[MDX](../queries/01_AA_2024.mdx) · [Toàn bộ kết quả CSV](../results/01_AA_2024.csv) · [Số gốc JSON](../results/01_AA_2024.json)

| Chiều 1 | Total Flights | Operated Flights | Cancelled Flights | Departure Delay Minutes |
| --- | --- | --- | --- | --- |
| AA | 6,840 | 6,726 | 114 | 148,696.00 |

**Nhận xét:** Hiển thị cả tổng chuyến có lịch và chuyến không hủy để tránh hiểu nhầm mẫu số. Phút trễ là phần dương và loại chuyến hủy khỏi chỉ số trễ chuyến thực hiện.

## Câu 2: Số chuyến không hủy và trễ hạ cánh trung bình theo quý/tháng năm 2024.

[MDX](../queries/02_Quarter_Month.mdx) · [Toàn bộ kết quả CSV](../results/02_Quarter_Month.csv) · [Số gốc JSON](../results/02_Quarter_Month.json)

| Chiều 1 | Operated Flights | Average Arrival Delay |
| --- | --- | --- |
| Q1/2024 | 12,198 | 6.46 |
| 01/2024 | 4,065 | 11.98 |
| 02/2024 | 3,934 | 0.43 |
| 03/2024 | 4,199 | 6.78 |
| Q2/2024 | 12,282 | 9.87 |
| 04/2024 | 4,057 | 5.43 |
| 05/2024 | 4,177 | 13.38 |
| 06/2024 | 4,048 | 10.69 |
| Q3/2024 | 12,342 | 9.55 |
| 07/2024 | 4,119 | 18.64 |
| 08/2024 | 4,155 | 9.84 |
| 09/2024 | 4,068 | 0.05 |
| Q4/2024 | 12,452 | 1.38 |
| 10/2024 | 4,180 | -1.15 |
| 11/2024 | 4,069 | -0.65 |
| 12/2024 | 4,203 | 5.84 |

**Nhận xét:** 16 dòng gồm 4 quý và 12 tháng. Trung bình tại quý được tính từ tổng phút / tổng lượt quan sát của quý, không lấy trung bình giản đơn của ba số trung bình tháng.

## Câu 3: Top 5 sân bay xuất phát theo số chuyến không hủy năm 2024.

[MDX](../queries/03_Top5_Origin_Airports.mdx) · [Toàn bộ kết quả CSV](../results/03_Top5_Origin_Airports.csv) · [Số gốc JSON](../results/03_Top5_Origin_Airports.json)

| Chiều 1 | Operated Flights |
| --- | --- |
| ATL | 2,319 |
| DEN | 2,212 |
| DFW | 2,129 |
| ORD | 1,909 |
| CLT | 1,527 |

**Nhận xét:** Xếp hạng theo chuyến không hủy. Đây là mức độ khai thác trong mẫu 50k, không phải bảng xếp hạng đầy đủ của thị trường hàng không.

## Câu 4: Hãng có ít nhất 100 chuyến hủy năm 2024.

[MDX](../queries/04_Cancelled_100.mdx) · [Toàn bộ kết quả CSV](../results/04_Cancelled_100.csv) · [Số gốc JSON](../results/04_Cancelled_100.json)

| Chiều 1 | Total Flights | Cancelled Flights |
| --- | --- | --- |
| UA | 5,516 | 129 |
| AA | 6,840 | 114 |
| WN | 10,079 | 111 |

**Nhận xét:** Giữ nguyên điều kiện ít nhất 100 chuyến hủy; không hạ ngưỡng để tăng số hãng xuất hiện.

## Câu 5: Top 3 hãng theo tổng phút trễ cất cánh trong quý 2/2024.

[MDX](../queries/05_Top3_Departure_Q2.mdx) · [Toàn bộ kết quả CSV](../results/05_Top3_Departure_Q2.csv) · [Số gốc JSON](../results/05_Top3_Departure_Q2.json)

| Chiều 1 | Operated Flights | Departure Delay Minutes |
| --- | --- | --- |
| AA | 1,633 | 45,809.00 |
| WN | 2,495 | 42,459.00 |
| DL | 1,760 | 26,742.00 |

**Nhận xét:** Bộ lọc quý dùng khóa 20242, nên không trộn quý 2 của các năm khác nếu nguồn được mở rộng.

## Câu 6: Tỷ lệ hủy của từng hãng, giảm dần; mẫu số là toàn bộ chuyến trong mẫu.

[MDX](../queries/06_Cancellation_Rate.mdx) · [Toàn bộ kết quả CSV](../results/06_Cancellation_Rate.csv) · [Số gốc JSON](../results/06_Cancellation_Rate.json)

| Chiều 1 | Total Flights | Cancelled Flights | Cancellation Rate |
| --- | --- | --- | --- |
| HA | 572 | 19 | 3.32% |
| F9 | 1,470 | 47 | 3.20% |
| AS | 1,821 | 55 | 3.02% |
| G4 | 838 | 22 | 2.63% |
| NK | 1,862 | 45 | 2.42% |
| UA | 5,516 | 129 | 2.34% |
| MQ | 1,909 | 41 | 2.15% |
| 9E | 1,393 | 28 | 2.01% |
| YX | 2,177 | 41 | 1.88% |
| B6 | 1,784 | 33 | 1.85% |
| OO | 5,298 | 98 | 1.85% |
| AA | 6,840 | 114 | 1.67% |
| OH | 1,607 | 26 | 1.62% |
| WN | 10,079 | 111 | 1.10% |
| DL | 6,976 | 59 | 0.85% |

**Nhận xét:** Tỷ lệ là số chuyến hủy chia tất cả chuyến của hãng trong mẫu; giá trị gốc JSON là số 0–1, cột hiển thị đã định dạng phần trăm.

## Câu 7: Chuyến không hủy theo bang/vùng lãnh thổ và tháng, trừ CA/TX.

[MDX](../queries/07_States_Except_CA_TX.mdx) · [Toàn bộ kết quả CSV](../results/07_States_Except_CA_TX.csv) · [Số gốc JSON](../results/07_States_Except_CA_TX.json)

| Chiều 1 | Chiều 2 | Operated Flights |
| --- | --- | --- |
| AK | 01/2024 | 19 |
| AK | 02/2024 | 16 |
| AK | 03/2024 | 16 |
| AK | 04/2024 | 24 |
| AK | 05/2024 | 22 |
| AK | 06/2024 | 27 |
| AK | 07/2024 | 28 |
| AK | 08/2024 | 26 |
| AK | 09/2024 | 20 |
| AK | 10/2024 | 19 |
| AK | 11/2024 | 22 |
| AK | 12/2024 | 20 |
| AL | 01/2024 | 27 |
| AL | 02/2024 | 13 |
| AL | 03/2024 | 13 |
| AL | 04/2024 | 22 |
| AL | 05/2024 | 21 |
| AL | 06/2024 | 27 |

Bảng trên hiển thị 18/592 dòng; CSV đi kèm chứa đầy đủ kết quả.

**Nhận xét:** Mã bang lấy từ trường tên bang trong dataset gốc. DCA và IAD được gán VA. Các bang/vùng lãnh thổ không có dữ liệu cho một tháng không được sinh thêm bản ghi.

## Câu 8: Tuyến dài 1.000–2.000 dặm, có ít nhất 50 chuyến trong mẫu năm 2024.

[MDX](../queries/08_Routes_1000_2000.mdx) · [Toàn bộ kết quả CSV](../results/08_Routes_1000_2000.csv) · [Số gốc JSON](../results/08_Routes_1000_2000.json)

| Chiều 1 | Route Distance Miles | Total Flights | Operated Flights |
| --- | --- | --- | --- |
| ANC - SEA | 1,448.00 | 58 | 56 |
| SEA - PHX | 1,107.00 | 57 | 57 |
| LGA - MIA | 1,096.00 | 55 | 55 |
| PHX - SEA | 1,107.00 | 54 | 54 |
| DFW - LGA | 1,389.00 | 51 | 49 |
| LAX - IAH | 1,379.00 | 50 | 49 |
| LGA - DFW | 1,389.00 | 50 | 48 |

**Nhận xét:** Cự ly là cự ly một tuyến, không phải tổng dặm của tất cả lượt bay. Hai cận 1.000 và 2.000 đều được tính.

## Câu 9: Hãng có tổng chuyến cao nhất và thấp nhất năm 2024.

[MDX](../queries/09_Max_Min_Carriers.mdx) · [Toàn bộ kết quả CSV](../results/09_Max_Min_Carriers.csv) · [Số gốc JSON](../results/09_Max_Min_Carriers.json)

| Chiều 1 | Total Flights |
| --- | --- |
| WN | 10,079 |
| HA | 572 |

**Nhận xét:** Hai dòng lần lượt là hãng nhiều chuyến nhất và ít chuyến nhất. Tổng tính cả chuyến hủy theo quy ước đã công bố.

## Câu 10: Sân bay có trên 200 chuyến không hủy và trễ hạ cánh trung bình trên 15 phút.

[MDX](../queries/10_Airport_Average_Delay.mdx) · [Toàn bộ kết quả CSV](../results/10_Airport_Average_Delay.csv) · [Số gốc JSON](../results/10_Airport_Average_Delay.json)

| Chiều 1 | Operated Flights | Arrival Observations | Average Arrival Delay |
| --- | --- | --- | --- |
| PBI | 203 | 203 | 17.49 |
| SJU | 275 | 271 | 15.82 |

**Nhận xét:** Mẫu số Average Arrival Delay là Arrival Observations. Không chia cho tổng chuyến gồm cả chuyến hủy hoặc chuyến thiếu ARR_DELAY.

## Câu 11: Top 3 sân bay của mỗi bang theo chuyến không hủy trong tháng 6–8/2024.

[MDX](../queries/11_Top3_Airports_Per_State_Summer.mdx) · [Toàn bộ kết quả CSV](../results/11_Top3_Airports_Per_State_Summer.csv) · [Số gốc JSON](../results/11_Top3_Airports_Per_State_Summer.json)

| Chiều 1 | Chiều 2 | Operated Flights |
| --- | --- | --- |
| AK | ANC | 44 |
| AK | FAI | 8 |
| AK | JNU | 7 |
| AL | BHM | 32 |
| AL | HSV | 14 |
| AL | MGM | 4 |
| AR | LIT | 25 |
| AR | XNA | 19 |
| AR | FSM | 2 |
| AZ | PHX | 319 |
| AZ | TUS | 23 |
| AZ | AZA | 6 |
| CA | LAX | 339 |
| CA | SFO | 244 |
| CA | SAN | 199 |
| CO | DEN | 592 |
| CO | COS | 18 |
| CO | ASE | 13 |

Bảng trên hiển thị 18/142 dòng; CSV đi kèm chứa đầy đủ kết quả.

**Nhận xét:** TOP 3 được áp dụng riêng trong từng bang trên tổng ba tháng 6–8. Bang có ít hơn ba sân bay đủ dữ liệu sẽ có ít hơn ba dòng.

## Câu 12: Hãng trừ WN, tổng chuyến từ 300, sắp theo Weather Delay giảm dần.

[MDX](../queries/12_Weather_Except_WN.mdx) · [Toàn bộ kết quả CSV](../results/12_Weather_Except_WN.csv) · [Số gốc JSON](../results/12_Weather_Except_WN.json)

| Chiều 1 | Total Flights | Weather Delay Minutes |
| --- | --- | --- |
| OO | 5,298 | 12,889.00 |
| AA | 6,840 | 8,631.00 |
| MQ | 1,909 | 5,128.00 |
| OH | 1,607 | 3,380.00 |
| UA | 5,516 | 3,201.00 |
| DL | 6,976 | 2,256.00 |
| 9E | 1,393 | 1,749.00 |
| YX | 2,177 | 1,557.00 |
| G4 | 838 | 1,368.00 |
| NK | 1,862 | 982.00 |
| AS | 1,821 | 831.00 |
| F9 | 1,470 | 542.00 |
| B6 | 1,784 | 436.00 |
| HA | 572 | 90.00 |

**Nhận xét:** Loại WN trước khi lọc và xếp hạng. Dùng điều kiện tổng chuyến từ 300, không dùng số chuyến trễ thời tiết làm điều kiện số lượng.

## Câu 13: Top 5 tuyến từ 1.500 dặm theo Late Aircraft Delay tháng 12/2024.

[MDX](../queries/13_Top5_Long_Routes_December.mdx) · [Toàn bộ kết quả CSV](../results/13_Top5_Long_Routes_December.csv) · [Số gốc JSON](../results/13_Top5_Long_Routes_December.json)

| Chiều 1 | Route Distance Miles | Total Flights | Operated Flights | Late Aircraft Delay Minutes | Departure Delay Minutes | Average Arrival Delay |
| --- | --- | --- | --- | --- | --- | --- |
| JFK - SJU | 1,598.00 | 6 | 6 | 103.00 | 483.00 | 75.00 |
| DAL - PDX | 1,626.00 | 1 | 1 | 99.00 | 109.00 | 104.00 |
| LAX - BOS | 2,611.00 | 6 | 6 | 87.00 | 125.00 | 11.50 |
| SFO - OGG | 2,338.00 | 2 | 2 | 66.00 | 140.00 | 36.50 |
| DTW - SAN | 1,956.00 | 3 | 3 | 60.00 | 85.00 | 10.00 |

**Nhận xét:** TOP 5 được xếp trong tập tuyến từ 1.500 dặm có dữ liệu tháng 12. Late Aircraft Delay là một nguyên nhân trễ; không cộng nó thêm vào ARR_DELAY.

## Câu 14: Hợp TOP 3 Carrier Delay và TOP 3 NAS Delay; loại AK/HI trước khi xếp hạng.

[MDX](../queries/14_Hotspots_Carrier_Or_NAS.mdx) · [Toàn bộ kết quả CSV](../results/14_Hotspots_Carrier_Or_NAS.csv) · [Số gốc JSON](../results/14_Hotspots_Carrier_Or_NAS.json)

| Chiều 1 | Carrier Delay Minutes | NAS Delay Minutes |
| --- | --- | --- |
| DEN | 14,272.00 | 4,901.00 |
| ATL | 13,154.00 | 4,802.00 |
| DFW | 11,976.00 | 4,773.00 |
| ORD | 10,883.00 | 7,986.00 |
| MCO | 4,619.00 | 5,029.00 |

**Nhận xét:** Loại AK/HI trước khi lấy TOP 3 của mỗi chỉ số. UNION bỏ trùng nên kết quả có thể ít hơn 6 sân bay; đây là OR giữa hai tập, không phải AND.

## Câu 15: Mỗi khung giờ: TOP 2 hãng có tỷ lệ trễ từ 15 phút cao nhất, ít nhất 100 chuyến không hủy.

[MDX](../queries/15_Top2_Delay_Rate_Per_Band.mdx) · [Toàn bộ kết quả CSV](../results/15_Top2_Delay_Rate_Per_Band.csv) · [Số gốc JSON](../results/15_Top2_Delay_Rate_Per_Band.json)

| Chiều 1 | Chiều 2 | Operated Flights | Departure Observations | Delayed Departures | Departure Delay Rate |
| --- | --- | --- | --- | --- | --- |
| Sáng | F9 | 450 | 450 | 85 | 18.89% |
| Sáng | NK | 590 | 590 | 101 | 17.12% |
| Trưa | B6 | 205 | 205 | 70 | 34.15% |
| Trưa | F9 | 165 | 165 | 52 | 31.52% |
| Chiều | F9 | 327 | 327 | 110 | 33.64% |
| Chiều | AA | 1,438 | 1,438 | 460 | 31.99% |
| Tối | WN | 2,405 | 2,405 | 852 | 35.43% |
| Tối | F9 | 481 | 481 | 167 | 34.72% |

**Nhận xét:** TOP 2 được tính lại trong từng khung giờ, sau điều kiện ít nhất 100 chuyến không hủy. Ngưỡng trễ là DEP_DELAY >=15; Tối gồm cả 00:00–05:59.
