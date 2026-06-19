USE NGANHANG;
GO

-- =========================================================================================
-- SCRIPT: TẠO TÀI KHOẢN NHÂN VIÊN (DEMO) ĐỂ TEST CHỨC NĂNG ĐĂNG NHẬP
-- Mục đích: Đảm bảo SQL Login NV01 và NV02 tồn tại, đúng mật khẩu '123456', 
-- và được phân đúng vào Role 'ChiNhanh' để không bị lỗi "Login failed" hay "Mapping User".
-- =========================================================================================

-- 1. Tạo/Reset tài khoản NV01
IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'NV01')
    DROP LOGIN [NV01];
GO
CREATE LOGIN [NV01] WITH PASSWORD = '123456', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'NV01')
    DROP USER [NV01];
GO
CREATE USER [NV01] FOR LOGIN [NV01];
GO
EXEC sp_addrolemember 'ChiNhanh', 'NV01';
GO

-- 2. Tạo/Reset tài khoản NV02
IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'NV02')
    DROP LOGIN [NV02];
GO
CREATE LOGIN [NV02] WITH PASSWORD = '123456', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'NV02')
    DROP USER [NV02];
GO
CREATE USER [NV02] FOR LOGIN [NV02];
GO
EXEC sp_addrolemember 'ChiNhanh', 'NV02';
GO

PRINT N'✅ Đã khởi tạo thành công tài khoản NV01 và NV02 (Mật khẩu: 123456) với Role ChiNhanh.';
