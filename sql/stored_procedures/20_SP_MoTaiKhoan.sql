USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP MỞ TÀI KHOẢN (tạo bản ghi TaiKhoan mới cho khách hàng)
-- Chạy trên: NGUON, BENTHANH (SQL1), TANDINH (SQL2) — SQL3/TRACUU chỉ tra cứu.
-- Gọi bởi: routes/taikhoan.js — POST /taikhoan/mo
-- Hỗ trợ mở TK cross-branch: khi KH thuộc chi nhánh khác, route gọi SP này
-- qua execSPAdmin trên server của chi nhánh KH (không phải server đăng nhập),
-- vì FK_TaiKhoan_KhachHang chỉ thỏa khi INSERT trên server có KhachHang gốc.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_MoTaiKhoan]
    @SOTK nchar(9),    -- Tham số: Số tài khoản mới (đã được sinh sẵn ở tầng ứng dụng)
    @CMND nchar(10),   -- Tham số: Số CMND của khách hàng đứng tên TK
    @SODU money,       -- Tham số: Số dư ban đầu khi mở TK
    @MACN nchar(10)    -- Tham số: Mã chi nhánh quản lý TK (có thể khác chi nhánh của KH)
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- Kiểm tra số tài khoản đã tồn tại chưa (tránh trùng khóa chính)
    IF EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK))
    BEGIN
        RAISERROR(N'Số tài khoản đã tồn tại.',16,1);
        RETURN;
    END

    -- Kiểm tra khách hàng có tồn tại trên hệ thống không.
    -- KhachHang phân mảnh ngang theo chi nhánh (filter row) → local chỉ có KH
    -- của chi nhánh mình. Check local trước, không có thì check LINK1 (đối tác)
    -- để hỗ trợ mở TK cross-branch mà không phụ thuộc NGUON.
    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
       AND NOT EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng không tồn tại trên hệ thống.',16,1);
        RETURN;
    END

    -- Tạo tài khoản mới, ngày mở TK = thời điểm hiện tại
    INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK)
    VALUES(@SOTK, @CMND, @SODU, @MACN, GETDATE());
END
GO
