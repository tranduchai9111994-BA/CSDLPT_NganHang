USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP LIỆT KÊ TÀI KHOẢN THEO NGÀY (phiên bản TRACUU — chạy trên SQL3)
-- TaiKhoan replicate full → mỗi site đã có đủ data.
-- Chỉ cần đọc từ LINK1, không cần UNION ALL (sẽ bị trùng).
-- JOIN KhachHang local (replicate full) để lấy họ tên.
-- Hỗ trợ lọc tùy chọn theo chi nhánh và khoảng ngày mở TK.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,   -- Tham số: mã chi nhánh, NULL = tất cả
    @TUNGAY date = NULL,      -- Tham số: ngày bắt đầu, NULL = không giới hạn
    @DENNGAY date = NULL      -- Tham số: ngày kết thúc, NULL = không giới hạn
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    SELECT RTRIM(tk.SOTK) AS SOTK,    -- Số tài khoản, trim khoảng trắng
           RTRIM(tk.CMND) AS CMND,    -- Số CMND chủ TK
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,  -- Ghép họ + tên KH
           tk.SODU,                    -- Số dư hiện tại
           RTRIM(tk.MACN) AS MACN,    -- Mã chi nhánh quản lý TK
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK  -- Ngày mở TK, format dd/mm/yyyy
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk  -- Đọc TaiKhoan từ LINK1 (nhân bản full, 1 nguồn đủ)
    OUTER APPLY (                          -- OUTER APPLY: JOIN linh hoạt, trả NULL nếu không khớp
        SELECT TOP 1 HO, TEN              -- Lấy 1 bản ghi KH có CMND khớp
        FROM KhachHang                     -- Đọc bảng KhachHang local (replicate full)
        WHERE RTRIM(CMND)=RTRIM(tk.CMND)  -- Điều kiện: CMND khớp
    ) kh                                   -- Alias cho subquery
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))              -- Lọc theo chi nhánh (tùy chọn)
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)     -- Lọc từ ngày (tùy chọn)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)   -- Lọc đến ngày (tùy chọn)
    ORDER BY tk.NGAYMOTK DESC;  -- Sắp theo ngày mở TK mới nhất lên trước
END
GO
