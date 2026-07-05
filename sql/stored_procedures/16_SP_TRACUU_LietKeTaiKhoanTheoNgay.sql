USE NGANHANG;
GO

-- ==========================================================================
-- SP LIỆT KÊ TÀI KHOẢN THEO NGÀY (phiên bản TRACUU — chạy trên SQL3)
-- TaiKhoan replicate full (không filter MACN) → mỗi site đã có đủ data.
-- Chỉ cần đọc từ LINK1, không cần UNION ALL (sẽ bị trùng).
-- JOIN KhachHang local (replicate full) để lấy họ tên.
-- Hỗ trợ lọc tùy chọn theo chi nhánh và khoảng ngày mở TK.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,   -- NULL = tất cả chi nhánh; có giá trị = lọc theo CN
    @TUNGAY date = NULL,      -- NULL = không giới hạn ngày bắt đầu
    @DENNGAY date = NULL      -- NULL = không giới hạn ngày kết thúc
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK) AS SOTK,
           RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU,
           RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
GO
