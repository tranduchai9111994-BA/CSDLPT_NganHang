USE NGANHANG;
GO

-- =========================================================================================
-- SCRIPT: TẠO TÀI KHOẢN ADMIN (GIÁM ĐỐC) CẤP ĐỘ CSDL
-- Mục đích: Hỗ trợ chức năng Đăng Nhập bằng SQL Authentication không qua cửa sau (bypass).
--
-- CHẠY ĐÚNG SERVER:
--   SQL1 (BENTHANH) → chạy để admin có thể kết nối SQL1 (hỗ trợ cross-server query)
--   SQL2 (TANDINH)  → chạy để admin có thể kết nối SQL2 (hỗ trợ cross-server query)
--   SQL3 (TRACUU)   → BẮT BUỘC chạy: đây là server admin đăng nhập vào (chi nhánh TRACUU)
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

-- 4. Gán Server Role [securityadmin]
-- Quyền này cho phép tạo/xóa/sửa Login cấp Server (CREATE LOGIN, ALTER LOGIN, DROP LOGIN)
-- Cần thiết để chức năng "Tạo tài khoản" và "Reset mật khẩu" trên giao diện hoạt động
ALTER SERVER ROLE [securityadmin] ADD MEMBER [admin];
GO

-- 5. Gán Server Role [securityadmin] cho HTKN (tài khoản hệ thống dùng bởi Node.js adminPool)
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'HTKN')
    ALTER SERVER ROLE [securityadmin] ADD MEMBER [HTKN];
GO

-- 6. Đảm bảo tài khoản admin không bị gắn nhầm vào role db_owner (lỗi bảo mật phổ biến)
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

PRINT N'✅ Đã tạo/cấu hình thành công tài khoản [admin] thuộc nhóm [NganHang] + Server Role [securityadmin].';
