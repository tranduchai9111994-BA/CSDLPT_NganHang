USE NGANHANG;
GO

-- Cập nhật kiểu dữ liệu cột HO
ALTER TABLE NhanVien ALTER COLUMN HO nvarchar(50);

-- Thêm UNIQUE cho CMND
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_NhanVien_CMND')
BEGIN
    ALTER TABLE NhanVien ADD CONSTRAINT UQ_NhanVien_CMND UNIQUE (CMND);
END

-- Thêm CHECK >= 0 cho SODU
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TaiKhoan_SODU')
BEGIN
    ALTER TABLE TaiKhoan ADD CONSTRAINT CK_TaiKhoan_SODU CHECK (SODU >= 0);
END

-- Thêm UNIQUE cho TENCN
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_ChiNhanh_TENCN')
BEGIN
    ALTER TABLE ChiNhanh ADD CONSTRAINT UQ_ChiNhanh_TENCN UNIQUE (TENCN);
END

-- Thêm DEFAULT 0 cho TrangThaiXoa của NhanVien
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_NhanVien_TrangThaiXoa')
BEGIN
    ALTER TABLE NhanVien ADD CONSTRAINT DF_NhanVien_TrangThaiXoa DEFAULT 0 FOR TrangThaiXoa;
END
GO
