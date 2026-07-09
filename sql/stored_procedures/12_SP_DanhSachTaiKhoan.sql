USE NGANHANG;  -- Chọn database NGANHANG
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
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    SELECT RTRIM(tk.SOTK)  AS SOTK,    -- Số tài khoản, RTRIM bỏ khoảng trắng (nchar)
           RTRIM(tk.CMND)  AS CMND,    -- Số CMND chủ tài khoản
           tk.SODU,                     -- Số dư hiện tại
           RTRIM(tk.MACN)  AS MACN,    -- Mã chi nhánh quản lý TK
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,  -- Ngày mở TK, format dd/mm/yyyy
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen     -- Ghép họ + tên khách hàng
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk  -- Đọc TaiKhoan từ LINK1 (nhân bản full, chỉ cần 1 nguồn)
    OUTER APPLY (                          -- OUTER APPLY: JOIN linh hoạt, trả NULL nếu không khớp
        SELECT TOP 1 HO, TEN              -- Lấy 1 bản ghi KH khớp CMND
        FROM KhachHang                     -- Đọc bảng KhachHang local (replicate full trên TRACUU)
        WHERE RTRIM(CMND)=RTRIM(tk.CMND)  -- Điều kiện: CMND khớp
    ) kh                                   -- Alias cho subquery
    ORDER BY tk.NGAYMOTK DESC;             -- Sắp xếp theo ngày mở TK mới nhất lên trước
END
GO
