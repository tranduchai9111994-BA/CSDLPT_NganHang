USE NGANHANG;
GO

-- SP chạy RIÊNG trên TRACUU (SQL3).
-- TRACUU chỉ replicate bảng KhachHang, KHÔNG có NhanVien local.
-- → Đọc NhanVien từ 2 chi nhánh qua LINK1 (BENTHANH) + LINK2 (TANDINH).
CREATE OR ALTER PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- ==========================================================================
    -- BƯỚC 1: GỘP DANH SÁCH NHÂN VIÊN TỪ CẢ 2 CHI NHÁNH
    -- Mục đích: TRACUU không có bảng NhanVien local
    -- → Đọc từ LINK1 (BENTHANH) và LINK2 (TANDINH) rồi UNION ALL
    -- ==========================================================================
    -- ==========================================================================
    -- BƯỚC 2: LỌC THEO CHI NHÁNH (NẾU CÓ) VÀ SẮP XẾP
    -- Mục đích: Nếu @MACN = NULL → lấy tất cả; có giá trị → lọc theo chi nhánh
    -- Sắp xếp theo MACN, rồi theo HO + TEN để dễ tìm kiếm
    -- ==========================================================================
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
