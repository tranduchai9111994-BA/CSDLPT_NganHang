USE NGANHANG;
GO

-- ==============================================================================
-- 1. TẠO ROLE NẾU CHƯA CÓ (không DROP/CREATE lại — giữ nguyên member hiện có)
-- ==============================================================================
IF DATABASE_PRINCIPAL_ID('NganHang') IS NULL CREATE ROLE NganHang;
IF DATABASE_PRINCIPAL_ID('ChiNhanh') IS NULL CREATE ROLE ChiNhanh;
IF DATABASE_PRINCIPAL_ID('KhachHang') IS NULL CREATE ROLE KhachHang;
GO

-- ==============================================================================
-- 2. THU HỒI TOÀN BỘ GRANT/DENY HIỆN CÓ CỦA 3 ROLE (reset quyền, KHÔNG đụng member)
-- Tránh tình trạng "trôi quyền" (quyền cũ/thừa còn sót lại từ lần chạy trước)
-- ==============================================================================
DECLARE @revokeSql NVARCHAR(MAX) = '';
SELECT @revokeSql += 'REVOKE ' + pe.permission_name + ' ON ' +
    CASE pe.class_desc
        WHEN 'SCHEMA' THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
        WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id)
        WHEN 'DATABASE' THEN ''
        ELSE NULL
    END + ' FROM ' + QUOTENAME(pr.name) + ';' + CHAR(10)
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
WHERE pr.name IN ('NganHang', 'ChiNhanh', 'KhachHang')
  AND pe.class_desc IN ('SCHEMA', 'OBJECT_OR_COLUMN');  -- Bỏ qua permission hệ thống (MSmerge_* do replication tự cấp)

IF @revokeSql <> '' EXEC sp_executesql @revokeSql;
GO

-- ==============================================================================
-- 3. PHÂN QUYỀN CHO ROLE ChiNhanh
-- Dùng IF OBJECT_ID guard: một số server (VD TRACUU) không có local các bảng này
-- ==============================================================================
IF OBJECT_ID('GD_CHUYENTIEN') IS NOT NULL GRANT SELECT, INSERT, UPDATE, DELETE ON GD_CHUYENTIEN TO ChiNhanh;
IF OBJECT_ID('GD_GOIRUT')     IS NOT NULL GRANT SELECT, INSERT, UPDATE, DELETE ON GD_GOIRUT TO ChiNhanh;
IF OBJECT_ID('KhachHang')     IS NOT NULL GRANT SELECT, INSERT, UPDATE, DELETE ON KhachHang TO ChiNhanh;
IF OBJECT_ID('TaiKhoan')      IS NOT NULL GRANT SELECT, INSERT, UPDATE, DELETE ON TaiKhoan TO ChiNhanh;
IF OBJECT_ID('NhanVien')      IS NOT NULL GRANT SELECT, INSERT, UPDATE, DELETE ON NhanVien TO ChiNhanh;
IF OBJECT_ID('ChiNhanh')      IS NOT NULL GRANT SELECT ON ChiNhanh TO ChiNhanh;
GRANT EXECUTE ON SCHEMA::dbo TO ChiNhanh;
GO

-- ==============================================================================
-- 4. PHÂN QUYỀN CHO ROLE NganHang
-- ==============================================================================
GRANT SELECT ON SCHEMA::dbo TO NganHang;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO NganHang;
GRANT EXECUTE ON SCHEMA::dbo TO NganHang;
GO

-- ==============================================================================
-- 5. PHÂN QUYỀN CHO ROLE KhachHang
-- ==============================================================================
-- Chỉ cấp EXECUTE trên SP — KhachHang không có SELECT trực tiếp trên bất kỳ bảng nào.
-- SP kiểm soát điều kiện lọc (WHERE CMND = @CMND), đảm bảo KhachHang chỉ thấy dữ liệu của mình.
GRANT EXECUTE ON sp_TaiKhoanKhachHang TO KhachHang;  -- danh sách TK của tôi
GRANT EXECUTE ON SP_SaoKeTaiKhoan TO KhachHang;       -- sao kê chi tiết 1 TK
GRANT EXECUTE ON sp_Login_App TO KhachHang;           -- bắt buộc để đăng nhập (auth.js gọi SP này cho MỌI role)
GO
