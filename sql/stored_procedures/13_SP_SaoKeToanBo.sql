USE NGANHANG;  -- Chọn database NGANHANG
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
    @TUNGAY datetime,   -- Tham số: Ngày bắt đầu khoảng sao kê
    @DENNGAY datetime   -- Tham số: Ngày kết thúc khoảng sao kê
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo "xx rows affected" để tăng hiệu suất

    -- ==========================================================================
    -- BƯỚC 1: GỘP GD GỬI/RÚT (GD_GOIRUT) TỪ CẢ 2 CHI NHÁNH
    -- LOAIGD = 'GT' (gửi tiền) hoặc 'RT' (rút tiền)
    -- ==========================================================================

    -- GD gửi/rút tại chi nhánh BENTHANH (qua LINK1)
    SELECT RTRIM(g.SOTK) AS SOTK,  -- Số tài khoản, trim khoảng trắng
           g.NGAYGD,                -- Ngày giao dịch
           g.LOAIGD,                -- Loại giao dịch (GT hoặc RT)
           g.SOTIEN                 -- Số tiền giao dịch
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g  -- Đọc bảng GD_GOIRUT từ BENTHANH
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY  -- Lọc theo khoảng thời gian

    UNION ALL  -- Gộp thêm kết quả (giữ bản ghi trùng)

    -- GD gửi/rút tại chi nhánh TANDINH (qua LINK2)
    SELECT RTRIM(g.SOTK),  -- Số tài khoản
           g.NGAYGD,       -- Ngày giao dịch
           g.LOAIGD,       -- Loại giao dịch
           g.SOTIEN        -- Số tiền
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g  -- Đọc bảng GD_GOIRUT từ TANDINH
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY  -- Lọc theo khoảng thời gian

    -- ==========================================================================
    -- BƯỚC 2: GỘP GD CHUYỂN TIỀN TỪ BENTHANH (LINK1)
    -- Mỗi GD chuyển tiền tạo 2 dòng kết quả:
    --   SOTK_CHUYEN → loại 'CT' (chuyển tiền đi — trừ tiền)
    --   SOTK_NHAN   → loại 'NT' (nhận tiền — cộng tiền)
    -- ==========================================================================
    UNION ALL

    -- Dòng chuyển đi (CT) từ BENTHANH: TK chuyển bị trừ tiền
    SELECT RTRIM(c.SOTK_CHUYEN),  -- Số TK chuyển tiền đi
           c.NGAYGD,               -- Ngày giao dịch
           'CT',                   -- Loại: Chuyển Tiền (trừ tiền)
           c.SOTIEN                -- Số tiền chuyển
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c  -- Đọc bảng GD_CHUYENTIEN từ BENTHANH
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY  -- Lọc theo khoảng thời gian

    UNION ALL

    -- Dòng nhận (NT) từ BENTHANH: TK nhận được cộng tiền
    SELECT RTRIM(c.SOTK_NHAN),  -- Số TK nhận tiền
           c.NGAYGD,            -- Ngày giao dịch
           'NT',                -- Loại: Nhận Tiền (cộng tiền)
           c.SOTIEN             -- Số tiền nhận
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c  -- Đọc bảng GD_CHUYENTIEN từ BENTHANH
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- ==========================================================================
    -- BƯỚC 3: GỘP GD CHUYỂN TIỀN TỪ TANDINH (LINK2)
    -- Tương tự bước 2 nhưng đọc từ chi nhánh TANDINH
    -- ==========================================================================
    UNION ALL

    -- Dòng chuyển đi (CT) từ TANDINH
    SELECT RTRIM(c.SOTK_CHUYEN),  -- Số TK chuyển
           c.NGAYGD,               -- Ngày giao dịch
           'CT',                   -- Loại: Chuyển Tiền
           c.SOTIEN                -- Số tiền
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c  -- Đọc từ TANDINH qua LINK2
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    UNION ALL

    -- Dòng nhận (NT) từ TANDINH
    SELECT RTRIM(c.SOTK_NHAN),  -- Số TK nhận
           c.NGAYGD,            -- Ngày giao dịch
           'NT',                -- Loại: Nhận Tiền
           c.SOTIEN             -- Số tiền
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c  -- Đọc từ TANDINH qua LINK2
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    ORDER BY NGAYGD;  -- Sắp xếp toàn bộ kết quả theo ngày giao dịch tăng dần
END
GO
