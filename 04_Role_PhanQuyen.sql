USE NGANHANG;
GO

-- ==============================================================================
-- 1. XÓA ROLE NẾU ĐÃ TỒN TẠI ĐỂ CHẠY LẠI SCRIPT KHÔNG BỊ LỖI
-- ==============================================================================
IF DATABASE_PRINCIPAL_ID('NganHang') IS NOT NULL DROP ROLE NganHang;
IF DATABASE_PRINCIPAL_ID('ChiNhanh') IS NOT NULL DROP ROLE ChiNhanh;
IF DATABASE_PRINCIPAL_ID('KhachHang') IS NOT NULL DROP ROLE KhachHang;
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
GRANT SELECT ON NhanVien TO ChiNhanh;
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
GRANT EXECUTE ON SP_SaoKeTaiKhoan TO KhachHang;
GO
