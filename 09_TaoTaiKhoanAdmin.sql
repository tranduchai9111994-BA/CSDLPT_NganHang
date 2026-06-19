USE NGANHANG;
GO

-- =========================================================================================
-- SCRIPT: TẠO TÀI KHOẢN ADMIN (GIÁM ĐỐC) CẤP ĐỘ CSDL
-- Mục đích: Hỗ trợ chức năng Đăng Nhập bằng SQL Authentication không qua cửa sau (bypass).
-- =========================================================================================

-- 1. Tạo Login ở mức Server (Nếu chưa tồn tại)
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'admin')
BEGIN
    CREATE LOGIN [admin] WITH PASSWORD = 'admin', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
END
GO

-- 2. Tạo User ở mức Database map với Login ở trên (Nếu chưa tồn tại)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'admin')
BEGIN
    CREATE USER [admin] FOR LOGIN [admin];
END
GO

-- 3. Gán User 'admin' vào Role 'NganHang' để thừa kế quyền
-- Role 'NganHang' đã được cấu hình GRANT SELECT và DENY INSERT/UPDATE/DELETE
EXEC sp_addrolemember 'NganHang', 'admin';
GO

-- 4. Đảm bảo tài khoản admin không bị gắn nhầm vào role db_owner (lỗi bảo mật phổ biến)
IF EXISTS (
    SELECT 1 
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
    JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
    WHERE r.name = 'db_owner' AND m.name = 'admin'
)
BEGIN
    EXEC sp_droprolemember 'db_owner', 'admin';
END
GO

PRINT N'✅ Đã tạo/cấu hình thành công tài khoản [admin] thuộc nhóm [NganHang].';
