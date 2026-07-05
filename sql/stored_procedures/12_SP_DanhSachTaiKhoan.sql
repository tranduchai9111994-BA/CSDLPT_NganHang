USE NGANHANG;
GO

-- ==========================================================================
-- SP DANH SÁCH TÀI KHOẢN (phiên bản TRACUU — chạy trên SQL3)
-- TaiKhoan replicate full (không filter MACN) → mỗi site đã có đủ data.
-- Chỉ cần đọc từ LINK1, không cần UNION ALL LINK1+LINK2 (sẽ bị trùng).
-- KhachHang có local trên TRACUU (replicate full) → JOIN local cho nhanh.
-- ==========================================================================
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
    OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
    ORDER BY tk.NGAYMOTK DESC;
END
GO
