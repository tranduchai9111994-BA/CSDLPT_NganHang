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
--
-- Rẽ nhánh transaction (fix #6):
--   TK cùng CN + không dùng LINK1 → BEGIN TRANSACTION (local, không cần MSDTC)
--   TK khác CN + dùng LINK1       → BEGIN DISTRIBUTED TRANSACTION (2-phase commit)
--
-- Chặn self-transfer (fix #9): @SOTK_CHUYEN phải khác @SOTK_NHAN.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),
    @SOTK_NHAN   nchar(9),
    @SOTIEN      money,
    @MANV        nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA CƠ BẢN
    -- ==========================================================================
    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);
        RETURN;
    END

    -- Fix #9: chặn TH tài khoản chuyển và nhận trùng nhau
    IF RTRIM(@SOTK_CHUYEN) = RTRIM(@SOTK_NHAN)
    BEGIN
        RAISERROR(N'Tài khoản chuyển và tài khoản nhận phải khác nhau.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA TÀI KHOẢN CHUYỂN TỒN TẠI
    -- ==========================================================================
    DECLARE @MACN_CHUYEN nchar(10);
    SELECT @MACN_CHUYEN = RTRIM(MACN)
    FROM TaiKhoan
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);

    IF @MACN_CHUYEN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 3: KIỂM TRA TÀI KHOẢN NHẬN TỒN TẠI
    -- ==========================================================================
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN)
    FROM TaiKhoan
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);

    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 4: XÁC ĐỊNH LOCAL / DISTRIBUTED
    -- ==========================================================================
    DECLARE @IsNhanLocal bit = 0;
    IF @MACN_NHAN = @MACN_CHUYEN
        SET @IsNhanLocal = 1;

    -- ==========================================================================
    -- BƯỚC 5: THỰC HIỆN GIAO DỊCH
    -- Nhánh 5.1: Cùng CN — BEGIN TRANSACTION (local, không MSDTC)
    -- Nhánh 5.2: Khác CN — BEGIN DISTRIBUTED TRANSACTION (2-phase commit)
    -- ==========================================================================
    BEGIN TRY
        IF @IsNhanLocal = 1
        BEGIN
            -- === Nhánh 5.1: LOCAL TRANSACTION ===
            BEGIN TRANSACTION;

            UPDATE TaiKhoan
            SET SODU = SODU - @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN)
              AND SODU >= @SOTIEN;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
                RETURN;
            END

            UPDATE TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);

            INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
            VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

            COMMIT TRANSACTION;
        END
        ELSE
        BEGIN
            -- === Nhánh 5.2: DISTRIBUTED TRANSACTION (dùng LINK1) ===
            BEGIN DISTRIBUTED TRANSACTION;

            UPDATE TaiKhoan
            SET SODU = SODU - @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN)
              AND SODU >= @SOTIEN;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
                RETURN;
            END

            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);

            INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
            VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
