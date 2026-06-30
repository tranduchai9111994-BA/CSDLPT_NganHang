USE NGANHANG;
GO

-- SP chạy trên TRACUU: gộp TaiKhoan từ cả 2 chi nhánh qua LINK1 (BENTHANH) và LINK2 (TANDINH).
-- KhachHang được JOIN local vì TRACUU replicate full bảng KhachHang.
-- Thay thế logic fan-out thủ công ở tầng Node.js khi NganHang xem danh sách tài khoản.
CREATE OR ALTER PROCEDURE sp_DanhSachTaiKhoan
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK)  AS SOTK,
           RTRIM(tk.CMND)  AS CMND,
           tk.SODU,
           RTRIM(tk.MACN)  AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)

    UNION ALL

    SELECT RTRIM(tk.SOTK),
           RTRIM(tk.CMND),
           tk.SODU,
           RTRIM(tk.MACN),
           CONVERT(varchar, tk.NGAYMOTK, 103),
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN)
    FROM [LINK2].NGANHANG.dbo.TaiKhoan tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)

    ORDER BY NGAYMOTK DESC;
END
GO
