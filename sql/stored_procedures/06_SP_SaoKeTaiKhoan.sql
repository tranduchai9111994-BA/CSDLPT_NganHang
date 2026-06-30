USE NGANHANG;
GO

CREATE OR ALTER PROCEDURE SP_SaoKeTaiKhoan
    @SOTK NVARCHAR(50),
    @TUNGAY DATETIME,
    @DENNGAY DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    -- =========================================================================================
    -- BƯỚC 1: KIỂM TRA TÀI KHOẢN TỒN TẠI VÀ LẤY SỐ DƯ HIỆN TẠI
    -- Mục đích: Xác minh SOTK có tồn tại trên hệ thống hay không
    -- Thứ tự: Tìm ở Local trước → không có thì tìm ở Linked Server → đều không có thì báo lỗi
    -- =========================================================================================
    DECLARE @SODU_HIENTAI MONEY;

    -- Bước 1a: Tìm ở mảnh Local trước (ưu tiên vì nhanh, không tốn network)
    SELECT @SODU_HIENTAI = SODU FROM TaiKhoan WHERE SOTK = @SOTK;

    -- Bước 1b: Nếu không có ở Local, tìm ở Linked Server (chi nhánh đối tác)
    IF @SODU_HIENTAI IS NULL
    BEGIN
        SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    END

    -- Bước 1c: Nếu tìm cả 2 nơi không thấy → tài khoản không tồn tại
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1);
        RETURN;
    END

    -- =========================================================================================
    -- BƯỚC 2: TÍNH SỐ DƯ ĐẦU KỲ BẰNG CÁCH "TRỪ NGƯỢC" TỪ SỐ DƯ HIỆN TẠI
    -- Mục đích: Tìm số dư tại thời điểm @TUNGAY mà không cần lưu snapshot
    -- Cách làm: Lấy số dư hiện tại - tổng biến động từ @TUNGAY đến nay
    --   GT (gửi tiền), NT (nhận chuyển khoản) → cộng vào số dư
    --   RT (rút tiền), CT (chuyển tiền đi) → trừ khỏi số dư
    -- Đọc từ cả Local và Linked Server để có đầy đủ giao dịch
    -- =========================================================================================
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;

    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE
            WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN
            WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN
            ELSE 0
        END
    ), 0)
    FROM (
        -- Giao dịch từ @TUNGAY trở về sau tại Local
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY

        UNION ALL

        -- Giao dịch từ @TUNGAY trở về sau tại Linked Server
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- =========================================================================================
    -- BƯỚC 3: TRÍCH XUẤT CHI TIẾT GIAO DỊCH TRONG KỲ VÀ TÍNH SỐ DƯ LŨY KẾ
    -- Mục đích: Liệt kê từng giao dịch trong khoảng [@TUNGAY, @DENNGAY]
    --           kèm số dư sau mỗi giao dịch (running balance)
    -- Cách làm:
    --   - CTE TransactionsInPeriod: gom tất cả GD từ Local + Linked Server trong khoảng thời gian
    --   - CTE RunningBalance: dùng Window Function để tính lũy kế từ @SODU_DAUKY
    -- =========================================================================================
    WITH TransactionsInPeriod AS (
        SELECT NGAYGD, SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY

        UNION ALL

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
            SODU_LUYKE = @SODU_DAUKY + SUM(
                CASE
                    WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN
                    WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN
                    ELSE 0
                END
            ) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    SELECT *
    FROM RunningBalance
    ORDER BY NGAYGD ASC;

END
GO
