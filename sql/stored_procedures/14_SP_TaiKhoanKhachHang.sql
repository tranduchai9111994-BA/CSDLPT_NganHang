USE NGANHANG;
GO

-- SP tra cứu danh sách tài khoản thuộc về một khách hàng (theo CMND).
-- KhachHang chỉ có GRANT EXECUTE trên SP này, không có SELECT trực tiếp trên TaiKhoan.
-- Điều này đảm bảo KhachHang không thể đọc TK của người khác dù kết nối thẳng vào DB.
CREATE OR ALTER PROCEDURE sp_TaiKhoanKhachHang
    @CMND nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK)  AS SOTK,
           RTRIM(tk.CMND)  AS CMND,
           tk.SODU,
           RTRIM(tk.MACN)  AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM TaiKhoan tk
    WHERE RTRIM(tk.CMND) = RTRIM(@CMND)
    ORDER BY tk.NGAYMOTK DESC;
END
GO
