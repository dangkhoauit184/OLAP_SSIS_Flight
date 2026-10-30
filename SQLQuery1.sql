-- ==================================================================================
-- HỌC PHẦN: KHO DỮ LIỆU VÀ OLAP (IS217) - ĐHQG-HCM, UIT
-- ĐỀ TÀI   : XÂY DỰNG KHO DỮ LIỆU FLIGHT DATA 2024 (FLIGHT ON-TIME PERFORMANCE)
-- FILE     : init_database_Flight_DW.sql
-- MÔ TẢ    : Khởi tạo Database, 5 bảng Dimension, 1 bảng Fact và ràng buộc khóa ngoại
-- ==================================================================================

-- 1. TẠO CƠ SỞ DỮ LIỆU KHO DỮ LIỆU
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'Flight_DW')
BEGIN
    CREATE DATABASE Flight_DW;
    PRINT N'-> Đã tạo mới cơ sở dữ liệu Flight_DW.';
END
GO

USE Flight_DW;
GO

-- ==================================================================================
-- 2. XÓA CÁC RÀNG BUỘC KHÓA NGOẠI VÀ BẢNG CŨ NẾU ĐÃ TỒN TẠI (RESET AN TOÀN)
-- ==================================================================================
PRINT N'-> Đang dọn dẹp cấu trúc cũ...';

-- Gỡ bỏ các ràng buộc khóa ngoại trên FACT_FLIGHT trước
IF OBJECT_ID('FK_FACT_DATE', 'F') IS NOT NULL 
    ALTER TABLE FACT_FLIGHT DROP CONSTRAINT FK_FACT_DATE;
IF OBJECT_ID('FK_FACT_CARRIER', 'F') IS NOT NULL 
    ALTER TABLE FACT_FLIGHT DROP CONSTRAINT FK_FACT_CARRIER;
IF OBJECT_ID('FK_FACT_ORIGIN', 'F') IS NOT NULL 
    ALTER TABLE FACT_FLIGHT DROP CONSTRAINT FK_FACT_ORIGIN;
IF OBJECT_ID('FK_FACT_DEST', 'F') IS NOT NULL 
    ALTER TABLE FACT_FLIGHT DROP CONSTRAINT FK_FACT_DEST;
IF OBJECT_ID('FK_FACT_CANCEL', 'F') IS NOT NULL 
    ALTER TABLE FACT_FLIGHT DROP CONSTRAINT FK_FACT_CANCEL;
IF OBJECT_ID('FK_FACT_TIME', 'F') IS NOT NULL 
    ALTER TABLE FACT_FLIGHT DROP CONSTRAINT FK_FACT_TIME;
GO

-- Xóa bảng Fact trước, các bảng Dim sau
IF OBJECT_ID('[dbo].[FACT_FLIGHT]', 'U') IS NOT NULL 
    DROP TABLE [dbo].[FACT_FLIGHT];
IF OBJECT_ID('[dbo].[DIM_CARRIER]', 'U') IS NOT NULL 
    DROP TABLE [dbo].[DIM_CARRIER];
IF OBJECT_ID('[dbo].[DIM_AIRPORT]', 'U') IS NOT NULL 
    DROP TABLE [dbo].[DIM_AIRPORT];
IF OBJECT_ID('[dbo].[DIM_CANCELLATION]', 'U') IS NOT NULL 
    DROP TABLE [dbo].[DIM_CANCELLATION];
IF OBJECT_ID('[dbo].[DIM_TIME]', 'U') IS NOT NULL 
    DROP TABLE [dbo].[DIM_TIME];
IF OBJECT_ID('[dbo].[DIM_DATE]', 'U') IS NOT NULL 
    DROP TABLE [dbo].[DIM_DATE];
GO

-- ==================================================================================
-- 3. KHỞI TẠO CÁC BẢNG DIMENSION (BẢNG CHIỀU)
-- ==================================================================================
PRINT N'-> Đang khởi tạo các bảng Dimension...';

-- 3.1. DIM_CARRIER (Hãng hàng không)
CREATE TABLE DIM_CARRIER (
    CARRIER_ID INT IDENTITY(1,1) PRIMARY KEY,
    CARRIER_CODE NVARCHAR(50) NOT NULL UNIQUE
);
GO

-- 3.2. DIM_AIRPORT (Sân bay - Role-playing Dimension cho cả Origin và Destination)
CREATE TABLE DIM_AIRPORT (
    AIRPORT_ID INT IDENTITY(1,1) PRIMARY KEY,
    AIRPORT_CODE NVARCHAR(50) NOT NULL UNIQUE,
    CITY_NAME NVARCHAR(100) NULL
);
GO

-- 3.3. DIM_CANCELLATION (Lý do hủy chuyến - Junk Dimension)
CREATE TABLE DIM_CANCELLATION (
    CANCELLATION_ID INT IDENTITY(1,1) PRIMARY KEY,
    CANCELLATION_CODE NVARCHAR(50) NOT NULL UNIQUE,
    CANCELLATION_REASON NVARCHAR(100) NULL
);
GO

-- 3.4. DIM_TIME (Khung giờ trong ngày)
CREATE TABLE DIM_TIME (
    TIME_ID INT IDENTITY(1,1) PRIMARY KEY,
    CRS_TIME INT NOT NULL UNIQUE,
    HOUR_NUM INT NULL,
    TIME_OF_DAY NVARCHAR(50) NULL
);
GO

-- 3.5. DIM_DATE (Ngày tháng - Phân cấp Year > Quarter > Month > Day)
CREATE TABLE DIM_DATE (
    DATE_ID INT IDENTITY(1,1) PRIMARY KEY,
    FL_DATE DATE NOT NULL UNIQUE,
    YEAR_NUM INT NULL,
    QUARTER_NUM INT NULL,
    MONTH_NUM INT NULL,
    DAY_NUM INT NULL
);
GO

-- ==================================================================================
-- 4. KHỞI TẠO BẢNG FACT (BẢNG SỰ KIỆN TRUNG TÂM)
-- ==================================================================================
PRINT N'-> Đang khởi tạo bảng Fact...';

CREATE TABLE FACT_FLIGHT (
    FLIGHT_ID INT IDENTITY(1,1) PRIMARY KEY,
    
    -- Khóa ngoại (Surrogate Foreign Keys)
    DATE_ID INT NULL,
    DEP_TIME_ID INT NULL,
    CARRIER_ID INT NULL,
    ORIGIN_AIRPORT_ID INT NULL,
    DEST_AIRPORT_ID INT NULL,
    CANCELLATION_ID INT NULL,
    
    -- Lịch trình (Degenerate Attributes)
    CRS_DEP_TIME INT NULL,
    CRS_ARR_TIME INT NULL,
    
    -- Các độ đo định lượng (Numeric Measures)
    DISTANCE FLOAT NULL,
    CANCELLED INT NULL,
    DEP_DELAY FLOAT NULL,
    ARR_DELAY FLOAT NULL,
    CARRIER_DELAY FLOAT NULL,
    WEATHER_DELAY FLOAT NULL,
    NAS_DELAY FLOAT NULL,
    SECURITY_DELAY FLOAT NULL,
    LATE_AIRCRAFT_DELAY FLOAT NULL
);
GO

-- ==================================================================================
-- 5. THIẾT LẬP RÀNG BUỘC KHÓA NGOẠI (FOREIGN KEYS) CHO STAR SCHEMA
-- ==================================================================================
PRINT N'-> Đang thiết lập các ràng buộc khóa ngoại...';

ALTER TABLE FACT_FLIGHT 
    ADD CONSTRAINT FK_FACT_DATE FOREIGN KEY (DATE_ID) REFERENCES DIM_DATE(DATE_ID);

ALTER TABLE FACT_FLIGHT 
    ADD CONSTRAINT FK_FACT_CARRIER FOREIGN KEY (CARRIER_ID) REFERENCES DIM_CARRIER(CARRIER_ID);

ALTER TABLE FACT_FLIGHT 
    ADD CONSTRAINT FK_FACT_ORIGIN FOREIGN KEY (ORIGIN_AIRPORT_ID) REFERENCES DIM_AIRPORT(AIRPORT_ID);

ALTER TABLE FACT_FLIGHT 
    ADD CONSTRAINT FK_FACT_DEST FOREIGN KEY (DEST_AIRPORT_ID) REFERENCES DIM_AIRPORT(AIRPORT_ID);

ALTER TABLE FACT_FLIGHT 
    ADD CONSTRAINT FK_FACT_CANCEL FOREIGN KEY (CANCELLATION_ID) REFERENCES DIM_CANCELLATION(CANCELLATION_ID);

ALTER TABLE FACT_FLIGHT 
    ADD CONSTRAINT FK_FACT_TIME FOREIGN KEY (DEP_TIME_ID) REFERENCES DIM_TIME(TIME_ID);
GO

PRINT N'-> KHỞI TẠO TOÀN BỘ KHO DỮ LIỆU FLIGHT_DW THÀNH CÔNG!';
GO

-- ==================================================================================
-- 6. CÁC CÂU TRUY VẤN KIỂM TRA SỐ LƯỢNG BẢN GHI (VERIFICATION CHECK)
-- ==================================================================================
/*
SELECT 'DIM_CARRIER' AS Table_Name, COUNT(*) AS Total_Rows FROM DIM_CARRIER
UNION ALL
SELECT 'DIM_AIRPORT', COUNT(*) FROM DIM_AIRPORT
UNION ALL
SELECT 'DIM_CANCELLATION', COUNT(*) FROM DIM_CANCELLATION
UNION ALL
SELECT 'DIM_TIME', COUNT(*) FROM DIM_TIME
UNION ALL
SELECT 'DIM_DATE', COUNT(*) FROM DIM_DATE
UNION ALL
SELECT 'FACT_FLIGHT', COUNT(*) FROM FACT_FLIGHT;

SELECT TOP 100 * FROM FACT_FLIGHT;
*/