USE NGANHANG;
GO

-- SP chạy RIÊNG trên TRACUU (SQL3).
-- TRACUU không có bảng TaiKhoan local (chỉ replicate KhachHang).
-- → Đọc TaiKhoan từ 2 chi nhánh qua LINK1 + LINK2, JOIN KhachHang local.
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
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
