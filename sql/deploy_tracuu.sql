-- ============================================================
-- DEPLOY SP ĐẶC THÙ CHO TRACUU (SQL3)
-- Chạy trực tiếp trên ES-HAITD16\SQL3 qua SSMS hoặc sqlcmd
--
-- TRACUU chỉ có 1 article = KhachHang (replicate full).
-- Các bảng NhanVien, TaiKhoan, GD_xxx KHÔNG có local.
-- → SP phải đọc qua LINK1 (BENTHANH) + LINK2 (TANDINH).
-- ============================================================

USE NGANHANG;
GO

-- ============================================================
-- 1. sp_DanhSachNhanVien
--    Dùng bởi: nhanvien.js (NganHang GET /), quantri.js
-- ============================================================
IF OBJECT_ID('dbo.sp_DanhSachNhanVien', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DanhSachNhanVien;
GO

CREATE PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(MANV) AS MANV,
           RTRIM(HO) AS HO, RTRIM(TEN) AS TEN,
           RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
           RTRIM(CMND) AS CMND,
           RTRIM(MACN) AS MACN,
           SODT, DIACHI, TrangThaiXoa
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS AllNV
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
GO

GRANT EXECUTE ON dbo.sp_DanhSachNhanVien TO NganHang;
GRANT EXECUTE ON dbo.sp_DanhSachNhanVien TO ChiNhanh;
GO

PRINT N'✓ sp_DanhSachNhanVien đã deploy.';
GO

-- ============================================================
-- 2. sp_LietKeTaiKhoanTheoNgay (phiên bản TRACUU)
--    Dùng bởi: baocao.js (NganHang liệt kê TK)
--    GHI ĐÈ bản cũ (từ Replication) vì bản cũ đọc local
-- ============================================================
IF OBJECT_ID('dbo.sp_LietKeTaiKhoanTheoNgay', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_LietKeTaiKhoanTheoNgay;
GO

CREATE PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,
    @TUNGAY date = NULL,
    @DENNGAY date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM (
        SELECT SOTK, CMND, SODU, MACN, NGAYMOTK
        FROM [LINK1].NGANHANG.dbo.TaiKhoan
        UNION ALL
        SELECT SOTK, CMND, SODU, MACN, NGAYMOTK
        FROM [LINK2].NGANHANG.dbo.TaiKhoan
    ) AS tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
GO

GRANT EXECUTE ON dbo.sp_LietKeTaiKhoanTheoNgay TO NganHang;
GRANT EXECUTE ON dbo.sp_LietKeTaiKhoanTheoNgay TO ChiNhanh;
GO

PRINT N'✓ sp_LietKeTaiKhoanTheoNgay (TRACUU) đã deploy.';
GO

-- ============================================================
-- 3. SP_DanhSachTrangThaiLogin (phiên bản TRACUU)
--    Dùng bởi: quantri.js (NganHang xem login management)
--    NhanVien qua LINK, KhachHang + QuanTriLogin local
-- ============================================================
IF OBJECT_ID('dbo.SP_DanhSachTrangThaiLogin', 'P') IS NOT NULL
    DROP PROCEDURE dbo.SP_DanhSachTrangThaiLogin;
GO

CREATE PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        'NhanVien' AS LoaiTK,
        nv.MANV AS MaThamChieu,
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
        RTRIM(nv.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS nv
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK,
        kh.CMND AS MaThamChieu,
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
        RTRIM(kh.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND) AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
GO

GRANT EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO NganHang;
GRANT EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO ChiNhanh;
DENY EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO KhachHang;
GO

PRINT N'✓ SP_DanhSachTrangThaiLogin (TRACUU) đã deploy.';
GO

-- ============================================================
-- 4. KIỂM TRA NHANH — chạy thử từng SP
-- ============================================================
PRINT N'';
PRINT N'=== TEST sp_DanhSachNhanVien ===';
EXEC sp_DanhSachNhanVien;
GO

PRINT N'=== TEST sp_LietKeTaiKhoanTheoNgay (không filter) ===';
EXEC sp_LietKeTaiKhoanTheoNgay;
GO

PRINT N'=== TEST SP_DanhSachTrangThaiLogin ===';
EXEC SP_DanhSachTrangThaiLogin;
GO

PRINT N'';
PRINT N'✅ Tất cả SP TRACUU đã deploy và test thành công.';
GO
