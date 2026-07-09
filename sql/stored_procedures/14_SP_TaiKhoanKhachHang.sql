USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP TRA CỨU TÀI KHOẢN THUỘC VỀ 1 KHÁCH HÀNG (theo CMND)
-- KhachHang chỉ có GRANT EXECUTE trên SP này, không có SELECT trực tiếp trên TaiKhoan.
-- → Đảm bảo KH không thể đọc TK của người khác dù kết nối thẳng vào DB.
-- ==========================================================================
CREATE OR ALTER PROCEDURE sp_TaiKhoanKhachHang
    @CMND nchar(10)  -- Tham số: Số CMND của khách hàng đang đăng nhập
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- ==========================================================================
    -- TRUY VẤN DANH SÁCH TÀI KHOẢN CỦA KHÁCH HÀNG
    -- Đọc từ bảng TaiKhoan local (nhân bản full nên có đầy đủ dữ liệu)
    -- Bảo mật: KhachHang chỉ xem được TK của mình nhờ lọc theo @CMND
    -- ==========================================================================
    SELECT RTRIM(tk.SOTK)  AS SOTK,    -- Số tài khoản, trim khoảng trắng (nchar)
           RTRIM(tk.CMND)  AS CMND,    -- Số CMND chủ TK
           tk.SODU,                     -- Số dư hiện tại của TK
           RTRIM(tk.MACN)  AS MACN,    -- Mã chi nhánh quản lý TK
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK  -- Ngày mở TK, format dd/mm/yyyy
    FROM TaiKhoan tk                    -- Đọc từ bảng TaiKhoan local
    WHERE RTRIM(tk.CMND) = RTRIM(@CMND)  -- Lọc chỉ TK có CMND khớp KH đăng nhập
    ORDER BY tk.NGAYMOTK DESC;          -- Sắp theo ngày mở TK mới nhất lên trước
END
GO
