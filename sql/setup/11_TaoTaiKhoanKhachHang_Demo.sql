-- =========================================================================================
-- SCRIPT: TẠO TÀI KHOẢN KHÁCH HÀNG DEMO
-- Mục đích: Tạo SQL Login + DB User + Role KhachHang cho các KH có trong seed_data.sql
--           để có thể test TC-01e (KhachHang đăng nhập vào ứng dụng).
--
-- CHẠY ĐÚNG SERVER:
--   SQL1 (BENTHANH) → chạy PHẦN A (KH thuộc BENTHANH: 1111111111, 0011223344)
--   SQL2 (TANDINH)  → chạy PHẦN B (KH thuộc TANDINH:   2222222222, 0099887766, 3333333333, 4444444444)
--   SQL3 (TRACUU)   → chạy CẢ HAI (KH replicate đầy đủ trên SQL3)
--
-- Quy ước: LoginName = CMND, Password = '1' (demo)
-- LoginName phải map đúng với CMND trong bảng KhachHang để sp_Login_App tìm thấy.
-- =========================================================================================

USE NGANHANG;
GO

-- ========================= PHẦN A: KH BENTHANH =========================

-- KH: 1111111111 (Nguyễn Văn An)
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '1111111111') DROP LOGIN [1111111111];
CREATE LOGIN [1111111111] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '1111111111') DROP USER [1111111111];
CREATE USER [1111111111] FOR LOGIN [1111111111];
EXEC sp_addrolemember 'KhachHang', '1111111111';
GO

-- KH: 0011223344 (Trần Đức Hải)
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '0011223344') DROP LOGIN [0011223344];
CREATE LOGIN [0011223344] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '0011223344') DROP USER [0011223344];
CREATE USER [0011223344] FOR LOGIN [0011223344];
EXEC sp_addrolemember 'KhachHang', '0011223344';
GO

PRINT N'[A] Đã tạo KH BENTHANH: 1111111111, 0011223344 (mật khẩu: 1, role: KhachHang)';
GO

-- ========================= PHẦN B: KH TANDINH =========================

-- KH: 2222222222 (Lê Thị Bình)
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '2222222222') DROP LOGIN [2222222222];
CREATE LOGIN [2222222222] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '2222222222') DROP USER [2222222222];
CREATE USER [2222222222] FOR LOGIN [2222222222];
EXEC sp_addrolemember 'KhachHang', '2222222222';
GO

-- KH: 0099887766 (Lê Thảo Trang)
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '0099887766') DROP LOGIN [0099887766];
CREATE LOGIN [0099887766] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '0099887766') DROP USER [0099887766];
CREATE USER [0099887766] FOR LOGIN [0099887766];
EXEC sp_addrolemember 'KhachHang', '0099887766';
GO

-- KH: 3333333333 (Nguyễn Văn Hoàng)
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '3333333333') DROP LOGIN [3333333333];
CREATE LOGIN [3333333333] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '3333333333') DROP USER [3333333333];
CREATE USER [3333333333] FOR LOGIN [3333333333];
EXEC sp_addrolemember 'KhachHang', '3333333333';
GO

-- KH: 4444444444 (Hoàng Văn Thái)
USE master;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '4444444444') DROP LOGIN [4444444444];
CREATE LOGIN [4444444444] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO
USE NGANHANG;
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '4444444444') DROP USER [4444444444];
CREATE USER [4444444444] FOR LOGIN [4444444444];
EXEC sp_addrolemember 'KhachHang', '4444444444';
GO

PRINT N'[B] Đã tạo KH TANDINH: 2222222222, 0099887766, 3333333333, 4444444444 (mật khẩu: 1, role: KhachHang)';
GO
