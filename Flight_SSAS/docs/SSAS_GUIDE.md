# Flight SSAS: triển khai và kiểm tra 15 truy vấn

Project Multidimensional `Flight_SSAS` phân tích **50.142 chuyến trong mẫu**, không phải toàn bộ mạng bay thực tế của Hoa Kỳ. CSV vẫn có 18 cột; không sửa CSV, không sinh chuyến bay hoặc ngày bay. Nguồn quan hệ là `Flight_DW`; Cube là `FlightCube`.

## 1. Đối chiếu quy trình đồ án mẫu

Tham khảo chương 3 của đồ án **Xây dựng kho dữ liệu FULL TMDB MOVIES (1M MOVIES)**, nhóm Lê Nguyễn Thúy An – Phạm Nhật Khoa, IS217.Q11, 2025. Bản Flight có cùng các phần thiết kế SSAS, nhưng dùng mô hình quan hệ phù hợp với chuyến bay.

| Phần trong mẫu | Phần đã thực hiện cho Flight |
|---|---|
| 3.1 Project SSAS | `Flight_SSAS.dwproj` trong solution `SSIS.slnx` |
| 3.2 Data Source | `Flight_DW.ds`, Windows Authentication, provider `MSOLEDBSQL` |
| 3.3 Data Source View | `Flight_DW.dsv`, 8 Named Query và 8 quan hệ khóa |
| 3.4 Dimension | 7 Dimension dùng chung; sân bay có hai vai trò trong Cube |
| 3.5 Cube và Measures | `FlightCube.cube`, 1 Measure Group, 16 measure gốc, 5 measure tính toán |
| 3.6 Bridge của dữ liệu phim | Flight không có quan hệ nhiều-nhiều tương ứng; không tạo bridge không cần thiết |
| 3.7 Dimension Usage | 8 quan hệ `Regular` từ Measure Group đến các chiều |
| 3.8 Phân cấp và Attribute Relationships | Calendar, Geography, Daily Schedule, Airlines; khóa quý/tháng chứa năm |
| 3.9 Deploy và Process | Script triển khai tương thích SQL Server 2025, đã Process Full thực tế |
| 3.10 Cube Browser, Excel Pivot, MDX | 15 file MDX, kết quả CSV/JSON, hướng dẫn bố trí các trường bên dưới |

## 2. Quy ước nghiệp vụ

- **Total Flights:** số dòng chuyến bay trong mẫu, gồm chuyến hủy. Đây là tổng dùng ở các câu đếm tổng và mẫu số tỷ lệ hủy.
- **Operated Flights:** `CANCELLED = 0`. Các câu gọi “chuyến cất cánh” dùng quy ước chuyến không hủy. Bộ 18 cột không có `WHEELS_OFF`, nên không dùng chỉ số này để khẳng định đã kiểm chứng thời điểm rời đường băng.
- **Cancelled Flights:** tổng cờ `CANCELLED`.
- **Departure Delay Minutes:** tổng phần dương của `DEP_DELAY`, chỉ với chuyến không hủy; chuyến sớm không bù trừ phút trễ của chuyến khác.
- **Average Arrival Delay:** tổng `ARR_DELAY` của chuyến không hủy / số chuyến không hủy có `ARR_DELAY`. Giữ số âm của chuyến đến sớm. Đây là độ lệch đến trung bình so với lịch, không phải trung bình riêng nhóm chuyến trễ.
- **Departure Delay Rate:** số chuyến không hủy có `DEP_DELAY >= 15` / số chuyến không hủy có `DEP_DELAY`. Ngưỡng 15 phút đã được người dùng xác nhận.
- **Cancellation Rate:** `Cancelled Flights / Total Flights`. Các tỷ lệ trả `NULL` khi mẫu số bằng 0, lưu dạng 0–1 và hiển thị theo `%`.
- **Route Distance Miles:** tổng khoảng cách / tổng số chuyến trong ngữ cảnh. Mỗi cặp sân bay trong nguồn hiện có một cự ly cố định; script Build kiểm tra điều này trước khi tạo mô hình. Khoảng cách không được cộng rồi dùng như cự ly của một tuyến.
- Các nguyên nhân `Carrier/Weather/NAS/Security/Late Aircraft Delay` là các phút nguyên nhân trễ từ nguồn; không cộng thêm chúng vào `ARR_DELAY` để tránh tính hai lần.

Trong mẫu có 868 chuyến hủy; 33 chuyến hủy vẫn có `DEP_DELAY`. Chúng vẫn có mặt trong Fact và được đếm là hủy, nhưng không vào chỉ số trễ của chuyến không hủy. Có 387 chuyến không hủy thiếu `ARR_DELAY`; chúng không vào mẫu số trung bình đến. CSV không có cờ `DIVERTED`, nên không suy diễn nhóm này thành trạng thái chuyển hướng hay đúng giờ.

### Bang và vùng lãnh thổ

`reference/airport_states.csv` được trích từ `origin_state_nm` và `dest_state_nm` trong dataset gốc `flight_data_2024.csv`, đối chiếu trên 7.079.081 bản ghi, đủ 342 sân bay. Xem `reference/provenance.json`.

Không lấy hậu tố `CITY_NAME` làm bang sân bay: DCA/IAD có thành phố thị trường Washington, DC nhưng bang sân bay trong nguồn là **VA**. `CITY_LABEL` vẫn là thành phố thị trường gốc. Bang/vùng lãnh thổ được giữ theo nguồn, gồm PR, VI và mã TT của BTS. Không gán tất cả mã này thành một trong 50 tiểu bang.

Khi đổi mẫu sang sân bay chưa có trong bảng tra, Build sẽ báo lỗi yêu cầu cập nhật bảng tra. Không tự gán một bang mặc định.

### Bốn khung giờ của câu 15

| Key | Khung giờ | Giờ khởi hành dự kiến tại sân bay đi |
|---:|---|---|
| 1 | Sáng | 06:00–11:59 |
| 2 | Trưa | 12:00–13:59 |
| 3 | Chiều | 14:00–17:59 |
| 4 | Tối | 18:00–23:59 và 00:00–05:59, gồm ban đêm |

Phân nhóm dựa trên `CRS_DEP_TIME`, không dựa trên giờ máy bay thực tế rời sân bay. Mốc `2400`, nếu xuất hiện trong nguồn mới, được chuẩn hóa về giờ 00 để phân nhóm.

## 3. Cấu trúc mô hình

| Dimension dùng chung | Thuộc tính/phân cấp chính | Vai trò trong Cube |
|---|---|---|
| Date | `Calendar`: Year → Quarter → Month → Date; Month Of Year; Day Of Week | Date |
| Carrier | Carrier Code; Carrier Name; Airlines | Carrier |
| Airport | `Geography`: State → City → Airport Code | Origin Airport và Destination Airport |
| Departure Time | `Daily Schedule`: Time Band → Hour → Scheduled Time | Departure Time |
| Cancellation | mã và lý do hủy; NA là không hủy | Cancellation |
| Route | cặp sân bay có hướng; Origin Code, Destination Code, Distance Miles | Route |
| Flight Status | Đã hủy / Không hủy, lấy từ cờ nguồn | Flight Status |

Measure Group `Flight Facts` nối trực tiếp với cả 8 chiều theo khóa Fact. Date/Carrier/Airport/Time/Cancellation vẫn dùng các khóa thay thế do SSIS tạo. Route được bổ sung bằng Named Query từ cặp khóa đi–đến; Status lấy giá trị phân biệt của cờ hủy trong Fact.

Các Named Query nằm trong `model/*.sql`, được nhúng vào DSV. Chúng không tạo bảng hay view mới trong SQL Server và không thay đổi package SSIS. Mô hình dùng MOLAP, một partition `All Flights`. Khóa và quan hệ không hợp lệ làm Process thất bại thay vì thay bằng Unknown Member.

## 4. Mở project và xem Cube

1. Mở `SSIS.slnx` bằng Visual Studio Community 2026 có extension Analysis Services Projects 2022+.
2. Khi phát hiện file thay đổi, chọn **Reload/Reload All**. Nếu project còn incompatible sau khi cài extension, nhấp phải `Flight_SSAS` → **Reload Project**.
3. Trong `Flight_SSAS`, mở `Data Sources/Flight_DW.ds`, `Data Source Views/Flight_DW.dsv` và các file trong `Dimensions` để xem nguồn, quan hệ và phân cấp.
4. Mở `Cubes/FlightCube.cube` → các tab **Cube Structure**, **Dimension Usage**, **Calculations**, **Partitions** và **Browser**.
5. Trong Browser, kết nối `localhost`, database `Flight_SSAS`, cube `FlightCube` và dùng **Reconnect** sau lần Process mới.

## 5. Triển khai lại sau khi chạy SSIS

Chạy SSIS toàn bộ trước, xác nhận `Verify_Load` thành công. SSIS full refresh xóa/tạo lại bảng, nên cần Process Full Cube để nạp lại dữ liệu và các khóa Dimension.

**Một lần cho cấu hình nguồn, và chạy lại sau SSIS full refresh:** mở `sql/ssas_service_read_access.sql` trong SSMS trên SQL Server cục bộ và thực thi bằng tài khoản có quyền tạo login/user, cấp SELECT. Script chỉ cấp SELECT trên sáu bảng cho `NT SERVICE\MSSQLServerOLAPService`; nếu dịch vụ SSAS dùng tài khoản khác thì thay đúng tài khoản trong script.

**Từ Git Bash tại thư mục repository:**

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Flight_SSAS/scripts/Deploy-FlightSSAS.ps1
```

Hoặc từ PowerShell tại thư mục repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Flight_SSAS\scripts\Deploy-FlightSSAS.ps1
```

Script Deploy gọi `Build-FlightProject.ps1` để đọc các file hiện có trong `.dwproj`, ghép Dimension/Cube/Partitions thành `bin/Flight_SSAS.asdatabase`, rồi tạo/cập nhật **chỉ database SSAS `Flight_SSAS`** và Process Full. Nó giữ các chỉnh sửa trong file project, từ chối ghi đè database cùng tên không có dấu nhận diện của project và không xóa hay nạp lại `Flight_DW`.

`Build-FlightModel.ps1` là bộ sinh lại mô hình từ `model/*.sql`. Chỉ chạy khi chủ động muốn sinh lại toàn bộ thiết kế; thao tác này ghi lại các file `.ds/.dsv/.dim/.cube/.partitions/.dwproj` theo mã nguồn bộ sinh. Sau khi chỉnh mô hình bằng Designer, dùng Build/Deploy thông thường để giữ các chỉnh sửa đó.

Đổi máy/instance bằng tham số `-SqlServer`, `-SqlDatabase`, `-SsasServer`. Không đổi tên database SQL thành tên database SSAS: `Flight_DW` là nguồn SQL, `Flight_SSAS` là database phân tích.

### Lưu ý client của SQL Server 2025

Extension 4.0.0 đang cài đi kèm AMO 19.104.1, đã báo lỗi không hỗ trợ edition `StandardDeveloper64` khi kết nối SSAS 2025. Scripts dùng AMO/ADOMD **19.118.3** riêng trong `.packages`, không thay DLL của Visual Studio. Lần chạy đầu scripts tự tải hai gói chính thức từ NuGet; các lần sau dùng bản đã tải.

Vì vậy đường triển khai được kiểm thử là `Deploy-FlightSSAS.ps1`. Nếu nút Deploy trong Visual Studio báo lỗi edition, dùng script này. Khi Build trong Visual Studio, chọn riêng project SSAS; nút Start của solution hiện có thể đang đặt project SSIS làm startup.

## 6. Chạy 15 câu MDX

Trong SSMS: kết nối **Analysis Services**, server `localhost` → database `Flight_SSAS` → **New Query → MDX**, mở file tương ứng trong `queries/`, rồi Execute. Mọi truy vấn dùng cube `FlightCube`; các tên đối tượng trong file khớp tên đã triển khai.

Chạy cả bộ và xuất kết quả:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Flight_SSAS\scripts\Run-MDXQueries.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Flight_SSAS\scripts\Test-FlightSSAS.ps1
python .\Flight_SSAS\scripts\verify_query_results.py
```

Python cần `pandas`. `verify_query_results.py` tính lại 15 đáp án từ CSV bằng các phép nhóm độc lập, đối chiếu tập thành viên, mọi giá trị số và thứ tự giảm dần của các câu có yêu cầu sắp xếp. `results/*.json` lưu cả số gốc và số hiển thị; `results/*.csv` thuận tiện xem bằng Excel. Không nhân tỷ lệ thêm 100 nếu đã áp dụng định dạng phần trăm trong Excel.

## 7. Cube Browser và Excel Pivot theo 15 câu

**Cube Browser:** kéo các Dimension/Hierarchy vào vùng hàng, Measures vào vùng dữ liệu, đặt bộ lọc năm 2024. Các điều kiện Top N, OR, xếp hạng theo từng nhóm có thể vượt quá khả năng thao tác kéo thả của Browser; dùng file MDX làm kết quả chuẩn cho các câu đó.

**Excel:** Data → Get Data → From Database → From Analysis Services (hoặc trình kết nối Analysis Services tương ứng phiên bản Excel) → server `localhost` → chọn `Flight_SSAS/FlightCube` → PivotTable. File `Flight_SSAS.odc` cũng chứa cấu hình kết nối Cube, không chứa mật khẩu. Dùng Measure đã tính trong Cube cho tỷ lệ/trung bình, không lấy Average của một tỷ lệ đã tổng hợp.

| Câu | Rows trong Browser/Pivot | Values | Bộ lọc/thao tác |
|---:|---|---|---|
| 1 | Carrier Code | Total, Operated, Cancelled, Departure Delay Minutes | AA; Year 2024 |
| 2 | Date.Calendar: Quarter, Month | Operated Flights; Average Arrival Delay | Year 2024; bật subtotal quý |
| 3 | Origin Airport.Airport Code | Operated Flights | Top 5 theo Operated |
| 4 | Carrier Code | Total Flights; Cancelled Flights | Cancelled ≥100 |
| 5 | Carrier Code | Operated; Departure Delay Minutes | Q2/2024; Top 3 theo phút trễ |
| 6 | Carrier Code | Total; Cancelled; Cancellation Rate | Sort giảm theo tỷ lệ |
| 7 | Origin Airport.State, Date.Month | Operated Flights | Bỏ CA/TX |
| 8 | Route.Route | Route Distance Miles; Total; Operated | 1.000–2.000 dặm; Total ≥50 |
| 9 | Carrier Code | Total Flights | Hợp Top 1 và Bottom 1; dùng MDX cho cùng một tập kết quả |
| 10 | Origin Airport.Airport Code | Operated; Arrival Observations; Average Arrival Delay | Operated >200 và Average >15; sort Average giảm |
| 11 | Origin Airport.State, Airport Code | Operated Flights | Tháng 6–8; Top 3 **trong từng bang**; MDX GENERATE là kết quả chuẩn |
| 12 | Carrier Code | Total; Weather Delay Minutes | Bỏ WN; Total ≥300; sort Weather giảm |
| 13 | Route.Route | Distance; Total; Operated; Late Aircraft; Departure Delay; Average Arrival | Tháng 12; Distance ≥1.500; Top 5 theo Late Aircraft |
| 14 | Origin Airport.Airport Code | Carrier Delay; NAS Delay | Bỏ AK/HI **trước** xếp hạng; hợp Top 3 của từng chỉ số, bỏ trùng |
| 15 | Departure Time.Time Band, Carrier Code | Operated; Departure Observations; Delayed Departures; Departure Delay Rate | ≥100 chuyến không hủy trong từng band; Top 2 **mỗi band** bằng MDX GENERATE |

Không dùng một Top N toàn cục thay cho Top N trong từng bang/khung giờ ở câu 11/15. Không dùng AND thay cho OR của hai tập Top 3 ở câu 14. Khi các thành viên bằng nhau tại ranh giới Top N, kết quả có thể chọn trong nhóm đồng hạng; không nên diễn giải một khác biệt rất nhỏ như khác biệt có ý nghĩa trên toàn bộ thị trường.

## 8. Cập nhật bảng tra khi thay dataset

```powershell
python .\Flight_SSAS\scripts\Extract-AirportStates.py --raw D:\OLAP\flight_data_2024.csv
```

Script chỉ đọc bốn cột mã sân bay/tên bang của nguồn lớn và xuất bảng tra nhỏ. Không đưa file CSV gốc vào Git. Khi đổi bảng tra hoặc Named Query, chạy `Build-FlightModel.ps1` để cập nhật DSV, rồi Deploy, MDX và kiểm chứng kết quả theo dataset mới. Sao lưu các chỉnh sửa Designer riêng trước khi sinh lại toàn bộ mô hình.

## 9. Tài liệu tham chiếu

- [Microsoft: tạo project Multidimensional](https://learn.microsoft.com/en-us/analysis-services/multidimensional-tutorial/lesson-1-1-creating-an-analysis-services-project)
- [Microsoft: AMO Dimension, Cube và Measure Group, gồm role-playing Dimension](https://learn.microsoft.com/en-us/analysis-services/amo/programming-amo-olap-basic-objects)
- [Microsoft: Data Source View và DataSet schema](https://learn.microsoft.com/en-us/analysis-services/amo/programming-amo-fundamental-objects)
- [Microsoft: Analysis Services client libraries](https://learn.microsoft.com/en-us/analysis-services/client-libraries)
- [BTS: định nghĩa chuyến trễ từ 15 phút](https://transtats.bts.gov/homedrillchart.asp)
- [FAA: mã và tên hãng](https://www.aspm.faa.gov/aspmhelp/index/ASQP__Carrier_Codes_and_Names.html)
- [USPS: mã bang/vùng lãnh thổ](https://pe.usps.com/text/pub28/28apb.htm)
