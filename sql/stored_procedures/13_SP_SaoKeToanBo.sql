USE NGANHANG;
GO

-- SP chạy trên TRACUU: tổng hợp toàn bộ giao dịch (GD_GOIRUT + GD_CHUYENTIEN)
-- từ cả 2 chi nhánh trong một khoảng thời gian, không lọc theo SOTK cụ thể.
-- Thay thế 3 query rời + merge ở tầng Node.js cho NganHang xem sao kê tổng.
CREATE OR ALTER PROCEDURE sp_SaoKeToanBo
    @TUNGAY datetime,
    @DENNGAY datetime
AS
BEGIN
    SET NOCOUNT ON;

    -- ==========================================================================
    -- BƯỚC 1: GỘP TOÀN BỘ GIAO DỊCH GỬI/RÚT TỪ CẢ 2 CHI NHÁNH
    -- Mục đích: Lấy GD_GOIRUT (gửi tiền GT, rút tiền RT) từ LINK1 và LINK2
    -- trong khoảng [@TUNGAY, @DENNGAY]
    -- ==========================================================================
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- ==========================================================================
    -- BƯỚC 2: GỘP GIAO DỊCH CHUYỂN TIỀN TỪ CHI NHÁNH BENTHANH (LINK1)
    -- Mục đích: Mỗi GD chuyển tiền tạo 2 bản ghi:
    --   - SOTK_CHUYEN với loại 'CT' (chuyển tiền đi, trừ tiền)
    --   - SOTK_NHAN với loại 'NT' (nhận tiền, cộng tiền)
    -- ==========================================================================
    UNION ALL

    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- ==========================================================================
    -- BƯỚC 3: GỘP GIAO DỊCH CHUYỂN TIỀN TỪ CHI NHÁNH TANDINH (LINK2)
    -- Mục đích: Tương tự bước 2 nhưng cho chi nhánh TANDINH
    -- ==========================================================================
    UNION ALL

    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- ==========================================================================
    -- BƯỚC 4: SẮP XẾP KẾT QUẢ THEO THỜI GIAN
    -- Mục đích: Hiển thị giao dịch theo thứ tự thời gian tăng dần
    -- ==========================================================================
    ORDER BY NGAYGD;
END
GO
