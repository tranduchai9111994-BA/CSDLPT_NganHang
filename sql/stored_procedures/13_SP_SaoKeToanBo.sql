USE NGANHANG;
GO

-- ==========================================================================
-- SP SAO KÊ TOÀN BỘ (phiên bản TRACUU — chạy trên SQL3)
-- Tổng hợp toàn bộ giao dịch từ CẢ 2 chi nhánh trong 1 khoảng thời gian.
-- Không lọc theo SOTK cụ thể → dùng cho admin xem báo cáo tổng hợp.
--
-- TRACUU không có bảng GD_GOIRUT, GD_CHUYENTIEN local
-- → Phải đọc qua LINK1 (BENTHANH) + LINK2 (TANDINH).
-- ==========================================================================
CREATE OR ALTER PROCEDURE sp_SaoKeToanBo
    @TUNGAY datetime,   -- Ngày bắt đầu khoảng sao kê
    @DENNGAY datetime   -- Ngày kết thúc khoảng sao kê
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo "xx rows affected"

    -- ==========================================================================
    -- BƯỚC 1: GỘP GD GỬI/RÚT (GD_GOIRUT) TỪ CẢ 2 CHI NHÁNH
    -- LOAIGD = 'GT' (gửi tiền) hoặc 'RT' (rút tiền)
    -- ==========================================================================

    -- GD gửi/rút tại BENTHANH (LINK1)
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    -- GD gửi/rút tại TANDINH (LINK2)
    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- ==========================================================================
    -- BƯỚC 2: GỘP GD CHUYỂN TIỀN (GD_CHUYENTIEN) TỪ BENTHANH (LINK1)
    -- Mỗi GD chuyển tiền tạo 2 dòng kết quả:
    --   - SOTK_CHUYEN → loại 'CT' (chuyển tiền đi — trừ tiền)
    --   - SOTK_NHAN   → loại 'NT' (nhận tiền — cộng tiền)
    -- ==========================================================================
    UNION ALL

    -- Dòng chuyển đi (CT) từ BENTHANH
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    -- Dòng nhận (NT) từ BENTHANH
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- ==========================================================================
    -- BƯỚC 3: GỘP GD CHUYỂN TIỀN TỪ TANDINH (LINK2)
    -- Tương tự bước 2 nhưng đọc từ chi nhánh TANDINH
    -- ==========================================================================
    UNION ALL

    -- Dòng chuyển đi (CT) từ TANDINH
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    -- Dòng nhận (NT) từ TANDINH
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- Sắp xếp toàn bộ kết quả theo thời gian tăng dần
    ORDER BY NGAYGD;
END
GO
