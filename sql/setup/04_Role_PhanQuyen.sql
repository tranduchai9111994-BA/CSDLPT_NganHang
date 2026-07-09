USE NGANHANG;
GO

-- ==============================================================================
-- 1. XÓA ROLE NẾU ĐÃ TỒN TẠI ĐỂ CHẠY LẠI SCRIPT KHÔNG BỊ LỖI
-- Phải xóa members trước khi DROP ROLE (SQL Server không cho DROP role còn members)
-- ==============================================================================
IF DATABASE_PRINCIPAL_ID('NganHang') IS NOT NULL
BEGIN
    DECLARE @sql1 NVARCHAR(MAX) = '';
    SELECT @sql1 += 'EXEC sp_droprolemember ''NganHang'', ''' + dp.name + ''';'
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE rp.name = 'NganHang';
    IF @sql1 <> '' EXEC sp_executesql @sql1;
    DROP ROLE NganHang;
END
IF DATABASE_PRINCIPAL_ID('ChiNhanh') IS NOT NULL
BEGIN
    DECLARE @sql2 NVARCHAR(MAX) = '';
    SELECT @sql2 += 'EXEC sp_droprolemember ''ChiNhanh'', ''' + dp.name + ''';'
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE rp.name = 'ChiNhanh';
    IF @sql2 <> '' EXEC sp_executesql @sql2;
    DROP ROLE ChiNhanh;
END
IF DATABASE_PRINCIPAL_ID('KhachHang') IS NOT NULL
BEGIN
    DECLARE @sql3 NVARCHAR(MAX) = '';
    SELECT @sql3 += 'EXEC sp_droprolemember ''KhachHang'', ''' + dp.name + ''';'
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE rp.name = 'KhachHang';
    IF @sql3 <> '' EXEC sp_executesql @sql3;
    DROP ROLE KhachHang;
END
GO

-- ==============================================================================
-- 2. TẠO 3 ROLE THEO YÊU CẦU
-- ==============================================================================
CREATE ROLE NganHang;
CREATE ROLE ChiNhanh;
CREATE ROLE KhachHang;
GO

-- ==============================================================================
-- 3. PHÂN QUYỀN CHO ROLE ChiNhanh
-- ==============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON GD_CHUYENTIEN TO ChiNhanh;
GRANT SELECT, INSERT, UPDATE, DELETE ON GD_GOIRUT TO ChiNhanh;
GRANT SELECT, INSERT, UPDATE, DELETE ON KhachHang TO ChiNhanh;
GRANT SELECT, INSERT, UPDATE, DELETE ON TaiKhoan TO ChiNhanh;
GRANT SELECT, INSERT, UPDATE, DELETE ON NhanVien TO ChiNhanh;
GRANT SELECT ON ChiNhanh TO ChiNhanh;
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
GO
