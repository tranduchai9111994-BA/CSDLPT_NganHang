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
    -- BƯỚC 1: KIỂM TRA TÀI KHOẢN VÀ LẤY SỐ DƯ HIỆN TẠI (TẠI THỜI ĐIỂM CHẠY BÁO CÁO)
    -- =========================================================================================
    DECLARE @SODU_HIENTAI MONEY;
    
    -- Ưu tiên tìm ở mảnh Local trước
    SELECT @SODU_HIENTAI = SODU FROM TaiKhoan WHERE SOTK = @SOTK;
    
    -- Nếu không có ở Local, tìm ở Linked Server (chi nhánh đối tác)
    IF @SODU_HIENTAI IS NULL
    BEGIN
        SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    END

    -- Nếu tìm cả 2 nơi không thấy, báo lỗi và thoát
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1);
        RETURN;
    END

    -- =========================================================================================
    -- BƯỚC 2: TỐI ƯU HÓA - TÍNH SỐ DƯ ĐẦU KỲ BẰNG CÁCH "TRỪ NGƯỢC" TỪ HIỆN TẠI
    -- Thay vì lôi toàn bộ dữ liệu từ quá khứ (tốn Network IO và Memory), ta lấy Số dư hiện tại
    -- trừ đi tổng các biến động diễn ra từ @TUNGAY cho đến nay (>= @TUNGAY).
    -- Điều này bảo đảm chính xác 100% kể cả khi tài khoản có số dư khởi tạo không nằm trong bảng GD.
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
        -- Các giao dịch phát sinh TỪ @TUNGAY trở về sau tại Local
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
        
        UNION ALL
        
        -- Các giao dịch phát sinh TỪ @TUNGAY trở về sau tại Linked Server
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- =========================================================================================
    -- BƯỚC 3: TRÍCH XUẤT CHI TIẾT GIAO DỊCH TRONG KỲ VÀ TÍNH SỐ DƯ LŨY KẾ
    -- Dùng CTE giới hạn đúng trong khoảng [@TUNGAY, @DENNGAY] để giảm tải dữ liệu truyền mạng.
    -- Dùng Window Function kết hợp với @SODU_DAUKY để ra số dư lũy kế chính xác sau mỗi GD.
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
