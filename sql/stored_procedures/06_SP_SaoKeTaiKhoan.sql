USE NGANHANG;
GO

-- =========================================================================================
-- SP SAO KÊ TÀI KHOẢN (xem lịch sử giao dịch của 1 tài khoản cụ thể)
-- Chạy trên chi nhánh (SQL1/SQL2).
-- Bảng GD_GOIRUT, GD_CHUYENTIEN KHÔNG nhân bản → giao dịch nằm rải ở 2 site.
-- → Phải đọc cả Local + LINK1 để có đầy đủ giao dịch liên quan đến SOTK.
-- =========================================================================================
CREATE OR ALTER PROCEDURE SP_SaoKeTaiKhoan
    @SOTK NVARCHAR(50),    -- Số tài khoản cần sao kê
    @TUNGAY DATETIME,      -- Ngày bắt đầu khoảng sao kê
    @DENNGAY DATETIME      -- Ngày kết thúc khoảng sao kê
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo "xx rows affected"

    -- =========================================================================================
    -- BƯỚC 1: KIỂM TRA TÀI KHOẢN TỒN TẠI VÀ LẤY SỐ DƯ HIỆN TẠI
    -- TaiKhoan được nhân bản full → tồn tại local ở mọi site.
    -- Tuy nhiên SP vẫn thử Local trước, fallback LINK1 để chắc chắn.
    -- =========================================================================================
    DECLARE @SODU_HIENTAI MONEY;

    -- Bước 1a: Tìm ở Local trước (nhanh, không tốn network)
    SELECT @SODU_HIENTAI = SODU FROM TaiKhoan WHERE SOTK = @SOTK;

    -- Bước 1b: Không có ở Local → tìm ở Linked Server (chi nhánh đối tác)
    IF @SODU_HIENTAI IS NULL
    BEGIN
        SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    END

    -- Bước 1c: Tìm cả 2 nơi không thấy → tài khoản không tồn tại
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1);
        RETURN;
    END

    -- =========================================================================================
    -- BƯỚC 2: TÍNH SỐ DƯ ĐẦU KỲ BẰNG CÁCH "TRỪ NGƯỢC" TỪ SỐ DƯ HIỆN TẠI
    -- Công thức: SỐ DƯ ĐẦU KỲ = SỐ DƯ HIỆN TẠI − tổng biến động từ @TUNGAY đến nay
    -- Vì hệ thống không lưu snapshot số dư theo ngày, nên phải tính ngược.
    -- Loại giao dịch:
    --   GT (gửi tiền), NT (nhận chuyển khoản) → đã cộng vào số dư → trừ đi khi tính ngược
    --   RT (rút tiền), CT (chuyển tiền đi) → đã trừ khỏi số dư → cộng lại khi tính ngược
    -- Phải đọc từ cả Local + LINK1 vì GD nằm rải ở cả 2 chi nhánh.
    -- =========================================================================================
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;  -- Tổng biến động từ @TUNGAY đến hiện tại

    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE
            WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN    -- Gửi/Nhận → cộng vào số dư
            WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN   -- Rút/Chuyển → trừ khỏi số dư
            ELSE 0
        END
    ), 0)  -- ISNULL: nếu không có GD nào → biến động = 0
    FROM (
        -- === GD tại Local (chi nhánh đang chạy SP) ===
        -- GD gửi/rút tiền mặt
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        -- GD chuyển tiền đi (TK này là TK chuyển → loại CT)
        SELECT SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        -- GD nhận tiền (TK này là TK nhận → loại NT)
        SELECT SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY

        UNION ALL

        -- === GD tại Linked Server (chi nhánh đối tác) ===
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    -- Số dư đầu kỳ = số dư hiện tại − tổng biến động sau ngày bắt đầu
    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- =========================================================================================
    -- BƯỚC 3: TRÍCH XUẤT CHI TIẾT GIAO DỊCH TRONG KỲ VÀ TÍNH SỐ DƯ LŨY KẾ
    -- CTE TransactionsInPeriod: gom tất cả GD từ Local + LINK1 trong [@TUNGAY, @DENNGAY]
    -- CTE RunningBalance: dùng Window Function SUM() OVER() để tính số dư lũy kế
    --   sau mỗi giao dịch, bắt đầu từ @SODU_DAUKY
    -- =========================================================================================
    ;WITH TransactionsInPeriod AS (
        -- === GD tại Local ===
        SELECT NGAYGD, SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY

        UNION ALL

        -- === GD tại Linked Server ===
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    RunningBalance AS (
        SELECT
            NGAYGD,
            LOAIGD,
            SOTIEN,
            -- Tính số dư lũy kế: bắt đầu từ số dư đầu kỳ, cộng/trừ theo từng GD
            -- ROWS UNBOUNDED PRECEDING: tính tổng từ đầu đến dòng hiện tại
            SODU_LUYKE = @SODU_DAUKY + SUM(
                CASE
                    WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN    -- Gửi/Nhận → cộng
                    WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN   -- Rút/Chuyển → trừ
                    ELSE 0
                END
            ) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    -- Trả về kết quả sắp xếp theo thời gian tăng dần
    SELECT *
    FROM RunningBalance
    ORDER BY NGAYGD ASC;

END
GO
