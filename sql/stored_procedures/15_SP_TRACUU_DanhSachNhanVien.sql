USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP DANH SÁCH NHÂN VIÊN (phiên bản TRACUU — chạy trên SQL3)
-- TRACUU chỉ replicate bảng KhachHang, KHÔNG có NhanVien local.
-- → Đọc NhanVien từ 2 chi nhánh qua LINK1 (BENTHANH) + LINK2 (TANDINH).
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL  -- Tham số: mã chi nhánh, NULL = lấy tất cả
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- ==========================================================================
    -- GỘP NV TỪ 2 CHI NHÁNH, LỌC VÀ SẮP XẾP
    -- ==========================================================================
    SELECT RTRIM(MANV) AS MANV,          -- Mã nhân viên, trim khoảng trắng
           RTRIM(HO) AS HO,              -- Họ nhân viên
           RTRIM(TEN) AS TEN,            -- Tên nhân viên
           RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,  -- Ghép họ + tên đầy đủ
           RTRIM(CMND) AS CMND,          -- Số CMND
           RTRIM(MACN) AS MACN,          -- Mã chi nhánh
           SODT,                          -- Số điện thoại
           DIACHI,                        -- Địa chỉ
           TrangThaiXoa                   -- Trạng thái (0=đang làm, 1=đã xóa/chuyển)
    FROM (
        -- Đọc NV từ BENTHANH qua LINK1
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien  -- Bảng NhanVien tại BENTHANH

        UNION ALL  -- Gộp thêm (giữ bản ghi trùng)

        -- Đọc NV từ TANDINH qua LINK2
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien  -- Bảng NhanVien tại TANDINH
    ) AS AllNV  -- Alias cho subquery gộp 2 chi nhánh
    -- Lọc theo chi nhánh nếu @MACN có giá trị; NULL = lấy tất cả
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;  -- Sắp theo chi nhánh, rồi theo họ tên
END
GO
