-- =========================================================================================
-- SCRIPT: TẠO TÀI KHOẢN NHÂN VIÊN DEMO
-- Mục đích: Tạo SQL Login + DB User + Role ChiNhanh cho nhân viên demo
--
-- CHẠY ĐÚNG SERVER:
--   SQL1 (BENTHANH) → chạy PHẦN A (BT001, BT002, BT003)
--   SQL2 (TANDINH)  → chạy PHẦN B (TD001, TD002, TD003, TD004)
--   SQL3 (TRACUU)   → chạy CẢ HAI (cần user tồn tại để query cross-server)
--
-- Mật khẩu mặc định: 1
-- MANV = LoginName (quy ước prefix: BT=Bến Thành, TD=Tân Định)
-- =========================================================================================

USE NGANHANG;
GO

-- ========================= PHẦN A: BENTHANH (BT001, BT002, BT003) =========================

-- BT001
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'BT001') DROP LOGIN [BT001];
CREATE LOGIN [BT001] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'BT001') DROP USER [BT001];
CREATE USER [BT001] FOR LOGIN [BT001];
EXEC sp_addrolemember 'ChiNhanh', 'BT001';
GO

-- BT002
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'BT002') DROP LOGIN [BT002];
CREATE LOGIN [BT002] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'BT002') DROP USER [BT002];
CREATE USER [BT002] FOR LOGIN [BT002];
EXEC sp_addrolemember 'ChiNhanh', 'BT002';
GO

-- BT003
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'BT003') DROP LOGIN [BT003];
CREATE LOGIN [BT003] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'BT003') DROP USER [BT003];
CREATE USER [BT003] FOR LOGIN [BT003];
EXEC sp_addrolemember 'ChiNhanh', 'BT003';
GO

PRINT N'[A] Đã tạo BT001, BT002, BT003 (mật khẩu: 1, role: ChiNhanh)';
GO

-- ========================= PHẦN B: TANDINH (TD001, TD002, TD003, TD004) =========================

-- TD001
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD001') DROP LOGIN [TD001];
CREATE LOGIN [TD001] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TD001') DROP USER [TD001];
CREATE USER [TD001] FOR LOGIN [TD001];
EXEC sp_addrolemember 'ChiNhanh', 'TD001';
GO

-- TD002
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD002') DROP LOGIN [TD002];
CREATE LOGIN [TD002] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TD002') DROP USER [TD002];
CREATE USER [TD002] FOR LOGIN [TD002];
EXEC sp_addrolemember 'ChiNhanh', 'TD002';
GO

-- TD003
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD003') DROP LOGIN [TD003];
CREATE LOGIN [TD003] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TD003') DROP USER [TD003];
CREATE USER [TD003] FOR LOGIN [TD003];
EXEC sp_addrolemember 'ChiNhanh', 'TD003';
GO

-- TD004
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD004') DROP LOGIN [TD004];
CREATE LOGIN [TD004] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TD004') DROP USER [TD004];
CREATE USER [TD004] FOR LOGIN [TD004];
EXEC sp_addrolemember 'ChiNhanh', 'TD004';
GO

PRINT N'[B] Đã tạo TD001, TD002, TD003, TD004 (mật khẩu: 1, role: ChiNhanh)';
GO
