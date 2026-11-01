-- One-time local setup for the default SSAS service account.
-- Run as a SQL Server administrator. If SSAS uses another account, substitute it.
-- Read access to the six source tables only; no db_owner/sysadmin role is added.
-- Re-run this script after an SSIS full refresh, which drops/recreates the tables.
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name=N'NT SERVICE\MSSQLServerOLAPService')
    CREATE LOGIN [NT SERVICE\MSSQLServerOLAPService] FROM WINDOWS;
GO
USE Flight_DW;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name=N'NT SERVICE\MSSQLServerOLAPService')
    CREATE USER [NT SERVICE\MSSQLServerOLAPService] FOR LOGIN [NT SERVICE\MSSQLServerOLAPService];
GRANT SELECT ON OBJECT::dbo.FACT_FLIGHT TO [NT SERVICE\MSSQLServerOLAPService];
GRANT SELECT ON OBJECT::dbo.DIM_DATE TO [NT SERVICE\MSSQLServerOLAPService];
GRANT SELECT ON OBJECT::dbo.DIM_TIME TO [NT SERVICE\MSSQLServerOLAPService];
GRANT SELECT ON OBJECT::dbo.DIM_CARRIER TO [NT SERVICE\MSSQLServerOLAPService];
GRANT SELECT ON OBJECT::dbo.DIM_AIRPORT TO [NT SERVICE\MSSQLServerOLAPService];
GRANT SELECT ON OBJECT::dbo.DIM_CANCELLATION TO [NT SERVICE\MSSQLServerOLAPService];
GO
