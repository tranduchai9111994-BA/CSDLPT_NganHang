USE NGANHANG;  -- Chọn database NGANHANG
GO

-- =========================================================================================
-- SP SAO KÊ TÀI KHOẢN (xem lịch sử giao dịch của 1 tài khoản cụ thể)
-- Chạy trên chi nhánh (SQL1/SQL2).
-- Bảng GD_GOIRUT, GD_CHUYENTIEN KHÔNG nhân bản → giao dịch nằm rải ở 2 site.
-- → Phải đọc cả Local + LINK1 để có đầy đủ giao dịch liên quan đến SOTK.
-- =========================================================================================
CREATE OR ALTER PROCEDURE SP_SaoKeTaiKhoan
    @SOTK NVARCHAR(50),    -- Tham số: Số tài khoản cần sao kê
    @TUNGAY DATETIME,      -- Tham số: Ngày bắt đầu khoảng sao kê
    @DENNGAY DATETIME      -- Tham số: Ngày kết thúc khoảng sao kê
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo "xx rows affected" để tăng hiệu suất

    -- =========================================================================================
    -- BƯỚC 0: DEFENSE IN DEPTH — KH chỉ được xem sao kê TK của chính mình
    -- Nếu caller thuộc role KhachHang → verify SOTK phải thuộc về SUSER_SNAME() (=CMND của KH).
    -- SUSER_SNAME() trả về tên SQL login đang gọi SP (KH dùng CMND làm login name).
    -- Chặn kịch bản KH gọi trực tiếp qua SSMS với SOTK người khác. Tầng app đã có
    -- lớp bảo vệ tương tự, nhưng SP tự bảo vệ để không phụ thuộc duy nhất tầng app.
    -- =========================================================================================
    IF IS_ROLEMEMBER('KhachHang') = 1
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM TaiKhoan
            WHERE RTRIM(SOTK) = RTRIM(@SOTK)
              AND RTRIM(CMND) = RTRIM(SUSER_SNAME())
        )
        BEGIN
            RAISERROR(N'Bạn không có quyền xem sao kê tài khoản này.', 16, 1);
            RETURN;
        END
    END

    -- =========================================================================================
    -- BƯỚC 1: KIỂM TRA TÀI KHOẢN TỒN TẠI VÀ LẤY SỐ DƯ HIỆN TẠI
    -- TaiKhoan được nhân bản full → luôn tồn tại local ở mọi site, chỉ cần đọc local.
    -- =========================================================================================
    DECLARE @SODU_HIENTAI MONEY;  -- Biến lưu số dư hiện tại của tài khoản

    -- Bước 1a: Tìm số dư ở Local trước (nhanh hơn, không tốn băng thông mạng)
    SELECT @SODU_HIENTAI = SODU   -- Gán số dư vào biến
    FROM TaiKhoan                  -- Đọc từ bảng TaiKhoan local
    WHERE SOTK = @SOTK;           -- Điều kiện: khớp số tài khoản

    -- Bước 1b: Không tìm thấy → tài khoản không tồn tại → báo lỗi
    -- (TaiKhoan được nhân bản full nên chỉ cần đọc Local, không cần LINK1)
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1);  -- Ném lỗi severity 16
        RETURN;  -- Kết thúc SP, không chạy tiếp
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
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;  -- Biến tổng biến động, khởi tạo = 0

    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(  -- Tính tổng biến động, ISNULL chuyển NULL→0
        CASE
            WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN    -- Gửi/Nhận → đã cộng vào số dư
            WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN   -- Rút/Chuyển → đã trừ khỏi số dư
            ELSE 0                                      -- Loại khác (nếu có) → bỏ qua
        END
    ), 0)  -- ISNULL: nếu không có GD nào → tổng biến động = 0
    FROM (
        -- === GD tại Local (chi nhánh đang chạy SP) ===
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT              -- GD gửi/rút tiền mặt tại local
        WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY           -- Lọc theo TK và từ ngày bắt đầu
        UNION ALL                                           -- Gộp thêm kết quả (giữ trùng)
        SELECT SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN  -- GD chuyển tiền đi (TK này chuyển)
        WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY   -- Lọc TK chuyển khớp
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN  -- GD nhận tiền (TK này nhận)
        WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY     -- Lọc TK nhận khớp

        UNION ALL  -- Gộp thêm GD từ chi nhánh đối tác

        -- === GD tại Linked Server (chi nhánh đối tác) ===
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT          -- GD gửi/rút ở LINK1
        WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN  -- GD chuyển đi ở LINK1
        WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN  -- GD nhận ở LINK1
        WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;  -- Alias cho subquery chứa tất cả biến động

    -- Công thức tính ngược: Số dư đầu kỳ = Số dư hiện tại − tổng biến động sau ngày bắt đầu
    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- =========================================================================================
    -- BƯỚC 3: TRÍCH XUẤT CHI TIẾT GIAO DỊCH TRONG KỲ VÀ TÍNH SỐ DƯ LŨY KẾ
    -- CTE TransactionsInPeriod: gom tất cả GD từ Local + LINK1 trong [@TUNGAY, @DENNGAY]
    -- CTE RunningBalance: dùng Window Function SUM() OVER() để tính số dư lũy kế
    --   sau mỗi giao dịch, bắt đầu từ @SODU_DAUKY
    -- =========================================================================================
    ;WITH TransactionsInPeriod AS (  -- CTE: tập hợp tất cả giao dịch trong kỳ sao kê
        -- === GD tại Local ===
        SELECT NGAYGD, SOTIEN, LOAIGD FROM GD_GOIRUT         -- GD gửi/rút local
        WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY  -- Lọc trong khoảng thời gian
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN    -- GD chuyển đi local
        WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN    -- GD nhận local
        WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY

        UNION ALL  -- Gộp thêm GD từ Linked Server

        -- === GD tại Linked Server ===
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT         -- GD gửi/rút LINK1
        WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN  -- GD chuyển LINK1
        WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN  -- GD nhận LINK1
        WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    -- =========================================================================================
    -- GIẢI THÍCH WINDOW FUNCTION — tính tổng lũy kế (Running Balance)
    --
    -- Cú pháp:
    --   SUM( CASE WHEN ... THEN SOTIEN ... )
    --   OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
    --
    -- Diễn giải:
    --   ORDER BY NGAYGD ASC         = sắp xếp theo ngày tăng dần
    --   ROWS UNBOUNDED PRECEDING    = tính từ dòng đầu tiên đến dòng hiện tại
    --
    -- Ví dụ: Giả sử SODU_DAUKY = 10,000,000
    --   Dòng 1 (01/07): Gửi +5tr  → SUM = 5,000,000  → SODU = 10tr + 5tr  = 15,000,000
    --   Dòng 2 (05/07): Rút -2tr  → SUM = 5-2 = 3tr  → SODU = 10tr + 3tr  = 13,000,000
    --   Dòng 3 (10/07): Rút -1tr  → SUM = 5-2-1 = 2tr → SODU = 10tr + 2tr = 12,000,000
    --   Dòng 4 (15/07): Gửi +3tr  → SUM = 5-2-1+3 = 5tr → SODU = 10tr+5tr = 15,000,000
    --
    -- SQL Server tự tính trong 1 lần scan, không cần vòng lặp hay cursor.
    -- =========================================================================================
    RunningBalance AS (  -- CTE: tính số dư lũy kế cho từng giao dịch
        SELECT
            NGAYGD,   -- Ngày giao dịch
            LOAIGD,   -- Loại giao dịch (GT/RT/CT/NT)
            SOTIEN,   -- Số tiền giao dịch
            -- Tính số dư lũy kế: bắt đầu từ số dư đầu kỳ, cộng/trừ theo từng GD
            SODU_LUYKE = @SODU_DAUKY + SUM(  -- Số dư đầu kỳ + tổng tích lũy
                CASE
                    WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN    -- Gửi/Nhận → cộng vào số dư
                    WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN   -- Rút/Chuyển → trừ khỏi số dư
                    ELSE 0                                      -- Loại khác → không ảnh hưởng
                END
            ) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)  -- Window: tính từ đầu đến dòng hiện tại
        FROM TransactionsInPeriod  -- Đọc từ CTE chứa tất cả GD trong kỳ
    )
    -- Trả về kết quả cuối cùng, sắp xếp theo thời gian tăng dần
    SELECT *              -- Lấy tất cả cột (NGAYGD, LOAIGD, SOTIEN, SODU_LUYKE)
    FROM RunningBalance   -- Đọc từ CTE đã tính số dư lũy kế
    ORDER BY NGAYGD ASC;  -- Sắp xếp theo ngày giao dịch tăng dần

END
GO
