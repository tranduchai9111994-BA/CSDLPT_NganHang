USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP THÊM KHÁCH HÀNG MỚI
-- Chạy trên: NGUON, BENTHANH (SQL1), TANDINH (SQL2) — SQL3/TRACUU chỉ tra cứu.
-- Gọi bởi: routes/khachhang.js — POST /khachhang/them
-- Sau khi thêm KH, route còn tạo Login SQL Server cho KH trên tất cả server
-- bằng adminPool (không nằm trong SP này).
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_ThemKhachHang]
    @CMND nchar(10),        -- Tham số: Số CMND (khóa chính của KhachHang)
    @HO nvarchar(40),       -- Tham số: Họ
    @TEN nvarchar(10),      -- Tham số: Tên
    @DIACHI nvarchar(100),  -- Tham số: Địa chỉ
    @PHAI nvarchar(3),      -- Tham số: Giới tính
    @NGAYCAP date,          -- Tham số: Ngày cấp CMND
    @SODT nvarchar(15),     -- Tham số: Số điện thoại
    @MACN nchar(10)         -- Tham số: Mã chi nhánh quản lý KH
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- Kiểm tra CMND đã tồn tại chưa (tránh trùng khóa chính)
    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng đã tồn tại.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        -- Thêm bản ghi khách hàng mới vào bảng KhachHang local (phân mảnh theo chi nhánh)
        INSERT INTO KhachHang(CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT, MACN)
        VALUES(@CMND, @HO, @TEN, @DIACHI, @PHAI, @NGAYCAP, @SODT, @MACN);
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();  -- Lấy thông báo lỗi
        RAISERROR(@ErrMsg, 16, 1);  -- Ném lỗi lên tầng ứng dụng
    END CATCH
END
GO
