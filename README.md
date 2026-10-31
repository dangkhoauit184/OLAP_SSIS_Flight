# Flight Data Warehouse — SSIS và SSAS

Project SSIS nạp CSV chuyến bay năm 2024 vào `Flight_DW`, phục vụ xây cube SSAS. File CSV đi kèm có **50.142 bản ghi, 366 ngày, mỗi ngày 137 bản ghi và 18 cột**.

Project **`Flight_SSAS`** đã có Data Source, DSV, 7 Dimension dùng chung, 8 chiều Cube, 21 chỉ số và 15 truy vấn MDX. Xem [hướng dẫn SSAS](Flight_SSAS/docs/SSAS_GUIDE.md), [kết quả và nhận xét](Flight_SSAS/docs/QUERY_RESULTS.md), [xác minh 15 truy vấn](Flight_SSAS/results/verification.json). Database SSAS là `Flight_SSAS`, cube `FlightCube`; nguồn SQL vẫn là `Flight_DW`.

## Chạy trên máy của bạn

1. Mở `SSIS.slnx` bằng Visual Studio có extension SSIS như project hiện tại. Kết nối dùng Microsoft OLE DB Driver for SQL Server (`MSOLEDBSQL`, driver 18), đã có trên máy kiểm thử.
2. Trong SQL Server, chạy `SQLQuery1.sql` nếu chưa có database `Flight_DW`.
3. Trong Connection Managers của `Package.dtsx`:
   - Kết nối `DESKTOP-7IVUF8R.Flight_DW`: tên connection được giữ để các task tiếp tục tham chiếu đúng; server mặc định là `(local)`, database `Flight_DW`. Nếu dùng instance khác, chọn server tương ứng trên máy bạn.
   - `FlatFile_FlightData`: chọn `flight_cleaned_50k.csv`. Đường dẫn mặc định vẫn là `D:\OLAP\flight_cleaned_50k.csv`; có thể Browse tới bản CSV trong repository.
4. Chạy **toàn bộ package** từ Control Flow. Task cuối `Verify_Load` phải thành công.
5. Chạy `sql/verify_load.sql` trong SSMS để đối chiếu số liệu với CSV đi kèm.

**Cách nạp là full refresh:** `Drop_All_Tables` và `Create_DIM_FACT_Table` xóa rồi tạo lại sáu bảng Dimension/Fact của đồ án trong database đã chọn. `SQLQuery1.sql` cũng khởi tạo lại các bảng này. Chạy cả package khi kiểm thử; chạy riêng luồng Fact có thể nạp thêm vào dữ liệu đang có. Sau một lần chạy thất bại, sửa nguyên nhân rồi chạy lại toàn bộ package.

## Luồng dữ liệu

```text
Drop_All_Tables
  -> Create_DIM_FACT_Table (gồm 6 khóa ngoại)
  -> Load các Dimension
  -> Load Fact
  -> Verify_Load
```

`DFT_Load_DIM_AIRPORT` kết hợp hai vai trò:

```text
Flat File Source (origin) -> Data Conversion ------------+
                                                       +-> Union All Airports -> Sort DISTINCT -> DIM_AIRPORT
Flat File Source Destination (dest) -> Data Conversion --+
```

Việc loại trùng dùng `AIRPORT_CODE`, nên cùng một sân bay chỉ có một khóa thay thế. Cả `ORIGIN_AIRPORT_ID` và `DEST_AIRPORT_ID` tham chiếu bảng này.

Trong luồng Fact:

- `Count Source Rows` đếm bản ghi thực tế từ CSV vào biến `User::SourceRowCount`, không tính dòng header.
- Sáu Lookup dừng luồng với lỗi khi không tìm được khóa. Dòng không khớp không còn bị chuyển vào một nhánh No Match không được xử lý.
- `Lookup_Date` dùng chuỗi ngày ISO `yyyy-MM-dd` được chuyển kiểu tường minh trong truy vấn, giữ metadata nhất quán khi dùng các provider SQL Server khác nhau.
- Derived Column chuyển các giờ dự kiến và cờ hủy sang số nguyên; khoảng cách và độ trễ sang số thực. Ô trống hợp lệ được giữ thành `NULL`; độ trễ âm vẫn giữ nguyên.
- Destination bật `Keep nulls`, không ánh xạ `FLIGHT_ID` vì cột này tự tăng.
- `Verify_Load` so sánh số dòng Fact với biến đếm nguồn, kiểm tra đủ khóa Dimension và đủ sáu khóa ngoại đang bật, được SQL Server tin cậy. Bước này không cố định số dòng nguồn thành 50.142.

Các Data Flow trì hoãn validation tới lúc chạy để schema được tạo trước khi kiểm tra metadata bảng đích.

Provider cũ `SQLOLEDB.1` đã được thay bằng `MSOLEDBSQL`, vì provider cũ không kết nối được từ runtime 64-bit tới SQL Server cục bộ trong bài kiểm thử. [Tài liệu Microsoft về OLE DB Driver](https://learn.microsoft.com/en-us/sql/connect/oledb/oledb-driver-for-sql-server).

## Số liệu của CSV đi kèm

| Kiểm tra | Kết quả |
|---|---:|
| DIM_CARRIER | 15 |
| DIM_AIRPORT, hợp sân bay đi và đến | 342 |
| DIM_CANCELLATION | 4 |
| DIM_TIME, giờ khởi hành dự kiến phân biệt | 1.201 |
| DIM_DATE | 366 |
| FACT_FLIGHT | 50.142 |
| SUM(CANCELLED) | 868 |
| DEP_DELAY IS NULL | 835 |
| ARR_DELAY IS NULL | 1.255 |
| Khóa ngoại Fact, đang bật và được tin cậy | 6 |

Các số trên dành cho CSV trong repository. Nếu đổi dataset, dùng số đếm nguồn và chỉ tiêu phù hợp với dataset mới. Mã hủy `NA` nghĩa là không hủy; không tự đọc nó thành lý do hủy bị thiếu.

CSV vẫn giữ 18 cột. Nó không có cờ `diverted`, vì vậy muốn phân tích riêng trạng thái chuyển hướng trong SSAS cần bổ sung dữ liệu nguồn cho chỉ tiêu đó. Không suy ra chuyến bị hủy hoặc có độ trễ `NULL` là chuyến đúng giờ.

## Kiểm thử bản sửa

Đã chạy bằng `DTExec` 17, 64-bit trên SQL Server 2025 Standard Developer với provider `MSOLEDBSQL`, trong database kiểm thử riêng:

- Hai lần chạy toàn bộ package đều thành công, mỗi lần nạp đủ 50.142 dòng. Chạy lần hai không làm tăng số dòng.
- Nối Fact với các Dimension và đối chiếu toàn bộ 18 giá trị của từng dòng với CSV nguồn: khớp cả 50.142 bản ghi, kể cả số lần xuất hiện của bản ghi.
- Script `sql/verify_load.sql` trả về `PASS` cho cả 11 chỉ tiêu sau mỗi lần nạp.
- Cố tình loại hãng `WN` khỏi dữ liệu tham chiếu: package thất bại tại `Lookup_Carrier` vì không tìm thấy khóa, đúng với cấu hình xử lý lỗi.

Database kiểm thử đã được xóa sau khi hoàn tất; bài kiểm thử không sửa database `Flight_DW` hiện có. Phần mở giao diện Designer trong Visual Studio và xử lý cube SSAS cần kiểm tra tiếp trên máy chạy project.

## Các file chính

- `SSIS/Package.dtsx`: package để chạy và chỉnh sửa Data Flow/Control Flow.
- `SSIS/SSIS.dtproj`: cấu hình project SSIS.
- `SQLQuery1.sql`: khởi tạo database, bảng và sáu khóa ngoại.
- `sql/verify_load.sql`: kiểm tra kết quả nạp của CSV đi kèm, không sửa dữ liệu kho.
- `flight_cleaned_50k.csv`: dữ liệu đầu vào đã cắt.

CSV gốc, `.mdf` và `.ldf` không được đưa vào Git.
