-- Doi chieu voi flight_cleaned_50k.csv di kem repository.
-- Chi doc du lieu; khong xoa, sua hay nap lai cac bang trong kho.
USE Flight_DW;
GO
SET NOCOUNT ON;

DECLARE @Checks TABLE (
    Metric nvarchar(100) NOT NULL,
    Expected bigint NOT NULL,
    Actual bigint NOT NULL
);

INSERT INTO @Checks (Metric, Expected, Actual)
SELECT N'DIM_CARRIER', 15, COUNT_BIG(*) FROM dbo.DIM_CARRIER
UNION ALL SELECT N'DIM_AIRPORT', 342, COUNT_BIG(*) FROM dbo.DIM_AIRPORT
UNION ALL SELECT N'DIM_CANCELLATION', 4, COUNT_BIG(*) FROM dbo.DIM_CANCELLATION
UNION ALL SELECT N'DIM_TIME', 1201, COUNT_BIG(*) FROM dbo.DIM_TIME
UNION ALL SELECT N'DIM_DATE', 366, COUNT_BIG(*) FROM dbo.DIM_DATE
UNION ALL SELECT N'FACT_FLIGHT', 50142, COUNT_BIG(*) FROM dbo.FACT_FLIGHT
UNION ALL SELECT N'Cancelled flights', 868, COALESCE(SUM(CONVERT(bigint, CANCELLED)), 0) FROM dbo.FACT_FLIGHT
UNION ALL SELECT N'NULL departure delay', 835, COUNT_BIG(*) FROM dbo.FACT_FLIGHT WHERE DEP_DELAY IS NULL
UNION ALL SELECT N'NULL arrival delay', 1255, COUNT_BIG(*) FROM dbo.FACT_FLIGHT WHERE ARR_DELAY IS NULL
UNION ALL SELECT N'Enabled and trusted Fact foreign keys', 6, COUNT_BIG(*)
    FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FACT_FLIGHT')
      AND is_disabled = 0 AND is_not_trusted = 0
UNION ALL SELECT N'Fact rows with missing or invalid Dimension keys', 0, COUNT_BIG(*)
    FROM dbo.FACT_FLIGHT f
    LEFT JOIN dbo.DIM_DATE d ON d.DATE_ID = f.DATE_ID
    LEFT JOIN dbo.DIM_TIME t ON t.TIME_ID = f.DEP_TIME_ID
    LEFT JOIN dbo.DIM_CARRIER c ON c.CARRIER_ID = f.CARRIER_ID
    LEFT JOIN dbo.DIM_AIRPORT o ON o.AIRPORT_ID = f.ORIGIN_AIRPORT_ID
    LEFT JOIN dbo.DIM_AIRPORT a ON a.AIRPORT_ID = f.DEST_AIRPORT_ID
    LEFT JOIN dbo.DIM_CANCELLATION x ON x.CANCELLATION_ID = f.CANCELLATION_ID
    WHERE d.DATE_ID IS NULL OR t.TIME_ID IS NULL OR c.CARRIER_ID IS NULL
       OR o.AIRPORT_ID IS NULL OR a.AIRPORT_ID IS NULL OR x.CANCELLATION_ID IS NULL;

SELECT Metric, Expected, Actual,
       CASE WHEN Actual = Expected THEN N'PASS' ELSE N'FAIL' END AS Result
FROM @Checks;

IF EXISTS (SELECT 1 FROM @Checks WHERE Actual <> Expected)
    THROW 51010, 'Warehouse does not match the bundled CSV. Check the failed metrics.', 1;
GO
