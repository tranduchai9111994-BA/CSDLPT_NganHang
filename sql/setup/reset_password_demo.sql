-- =========================================================================================
-- SCRIPT: RESET MẬT KHẨU TẤT CẢ TÀI KHOẢN DEMO VỀ '1'
-- Chạy trên TẤT CẢ server (SQL1, SQL2, SQL3, NGUON) hoặc đúng server chứa login.
-- Login chỉ tồn tại ở server nào thì ALTER chỉ có tác dụng ở server đó.
-- Dùng IF EXISTS để bỏ qua những login không có mặt.
-- =========================================================================================

USE master;
GO

-- Admin (có trên tất cả server)
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'admin')
    ALTER LOGIN [admin] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;

-- BENTHANH — SQL1 (BT prefix)
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'BT001')
    ALTER LOGIN [BT001] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'BT002')
    ALTER LOGIN [BT002] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'BT003')
    ALTER LOGIN [BT003] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;

-- TANDINH — SQL2 (TD prefix)
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD001')
    ALTER LOGIN [TD001] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD002')
    ALTER LOGIN [TD002] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD003')
    ALTER LOGIN [TD003] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'TD004')
    ALTER LOGIN [TD004] WITH PASSWORD = '1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;

-- Đồng bộ mật khẩu trong QuanTriLogin (nếu DB NGANHANG tồn tại trên server này)
IF DB_ID('NGANHANG') IS NOT NULL
BEGIN
    EXEC NGANHANG.dbo.sp_executesql
        N'UPDATE dbo.QuanTriLogin SET MatKhauHienTai = @mk WHERE LoginName IN
          (''admin'',''BT001'',''BT002'',''BT003'',''TD001'',''TD002'',''TD003'',''TD004'')',
        N'@mk VARCHAR(50)', @mk = '1';
    PRINT N'QuanTriLogin đã cập nhật mật khẩu.';
END

PRINT N'✅ Đã reset mật khẩu tất cả tài khoản demo về: 1';
GO
