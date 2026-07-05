USE NGANHANG;
GO

-- ==========================================================================
-- SP CHUYỂN TIỀN GIỮA 2 TÀI KHOẢN (có thể cùng hoặc khác chi nhánh)
-- Chạy trên chi nhánh (SQL1/SQL2) — nơi nhân viên thực hiện giao dịch.
--
-- Nguyên tắc phân tán:
--   TaiKhoan được NHÂN BẢN TOÀN VẸN → mọi TK đều tồn tại local → ĐỌC local.
--   Nhưng GHI chỉ tại site sở hữu (MACN khớp):
--     MACN TK nhận = MACN TK chuyển → cùng chi nhánh → UPDATE local
--     MACN TK nhận ≠ MACN TK chuyển → khác chi nhánh → UPDATE qua LINK1
--   GD_CHUYENTIEN KHÔNG nhân bản → log ghi tại chi nhánh thực hiện GD.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),   -- Số tài khoản chuyển tiền đi
    @SOTK_NHAN   nchar(9),   -- Số tài khoản nhận tiền
    @SOTIEN      money,      -- Số tiền cần chuyển
    @MANV        nchar(10)   -- Mã nhân viên thực hiện giao dịch
AS
BEGIN
    SET NOCOUNT ON;     -- Tắt thông báo "xx rows affected"
    SET XACT_ABORT ON;  -- Bắt buộc khi dùng DISTRIBUTED TRANSACTION — lỗi runtime tự ROLLBACK

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA SỐ TIỀN HỢP LỆ
    -- ==========================================================================
    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA TÀI KHOẢN CHUYỂN TỒN TẠI
    -- Đọc local (TaiKhoan nhân bản full) để lấy MACN của TK chuyển
    -- ==========================================================================
    DECLARE @MACN_CHUYEN nchar(10);
    SELECT @MACN_CHUYEN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
    IF @MACN_CHUYEN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 3: KIỂM TRA TÀI KHOẢN NHẬN TỒN TẠI
    -- Cũng đọc local (nhân bản full, không cần LINK1) để lấy MACN của TK nhận
    -- ==========================================================================
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 4: XÁC ĐỊNH TK NHẬN LÀ CÙNG HAY KHÁC CHI NHÁNH
    -- Cùng MACN → UPDATE local; khác MACN → UPDATE qua LINK1 (giao dịch phân tán)
    -- ==========================================================================
    DECLARE @IsNhanLocal bit = 0;  -- 0 = khác chi nhánh, 1 = cùng chi nhánh
    IF @MACN_NHAN = @MACN_CHUYEN
        SET @IsNhanLocal = 1;

    -- ==========================================================================
    -- BƯỚC 5: THỰC HIỆN GIAO DỊCH PHÂN TÁN
    -- DISTRIBUTED TRANSACTION đảm bảo atomicity khi thao tác trên 2 server
    -- Thứ tự: Trừ tiền TK chuyển → Cộng tiền TK nhận → Ghi log
    -- Nếu bất kỳ bước nào lỗi → XACT_ABORT tự ROLLBACK toàn bộ
    -- ==========================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;

        -- BƯỚC 5a: TRỪ TIỀN TÀI KHOẢN CHUYỂN (tại local — site sở hữu TK chuyển)
        -- Điều kiện SODU >= @SOTIEN kiểm tra đủ tiền ngay trong câu UPDATE
        -- Nếu @@ROWCOUNT = 0 → không đủ số dư → rollback
        UPDATE TaiKhoan
        SET SODU = SODU - @SOTIEN
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN) AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0  -- Không có dòng nào được update → không đủ tiền
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
            RETURN;
        END

        -- BƯỚC 5b: CỘNG TIỀN TÀI KHOẢN NHẬN
        IF @IsNhanLocal = 1
        BEGIN
            -- Cùng chi nhánh → UPDATE bảng TaiKhoan local
            UPDATE TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END
        ELSE
        BEGIN
            -- Khác chi nhánh → UPDATE qua Linked Server (site sở hữu TK nhận)
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END

        -- BƯỚC 5c: GHI LOG GIAO DỊCH VÀO BẢNG GD_CHUYENTIEN (local)
        -- Log ghi tại chi nhánh thực hiện GD (nơi nhân viên đang đăng nhập)
        -- GD_CHUYENTIEN không nhân bản → chỉ tồn tại tại site ghi
        INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

        COMMIT TRANSACTION;

    -- ==========================================================================
    -- BƯỚC 6: XỬ LÝ LỖI — bắt exception, rollback nếu transaction còn mở
    -- ==========================================================================
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;  -- Rollback nếu transaction chưa kết thúc
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);  -- Ném lỗi lên tầng ứng dụng
    END CATCH
END
GO
