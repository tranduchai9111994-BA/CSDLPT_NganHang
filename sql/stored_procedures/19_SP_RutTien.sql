USE NGANHANG;
GO

-- ==========================================================================
-- SP RÚT TIỀN TỪ TÀI KHOẢN (có thể cùng hoặc khác chi nhánh)
-- Chạy trên chi nhánh (SQL1/SQL2) — nơi nhân viên thực hiện giao dịch.
--
-- Nguyên tắc phân tán:
--   TaiKhoan được NHÂN BẢN TOÀN VẸN → mọi TK đều tồn tại local → ĐỌC local.
--   GHI chỉ tại site sở hữu (MACN khớp):
--     MACN TK = MACN NV → cùng chi nhánh → UPDATE local
--     MACN TK ≠ MACN NV → khác chi nhánh → UPDATE qua LINK1
--   GD_GOIRUT phân mảnh ngang theo NV → log ghi tại chi nhánh thực hiện GD.
--
-- Rẽ nhánh transaction (fix #6):
--   TK cùng CN với NV → BEGIN TRANSACTION (local, không cần MSDTC).
--   TK khác CN với NV → BEGIN DISTRIBUTED TRANSACTION (dùng LINK1 → 2-phase commit).
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_RutTien]
    @SOTK   nchar(9),
    @SOTIEN money,
    @MANV   nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Kiểm tra số tiền hợp lệ
    IF @SOTIEN < 100000
    BEGIN
        RAISERROR(N'Số tiền rút tối thiểu là 100,000 VND.', 16, 1);
        RETURN;
    END

    -- Kiểm tra tài khoản tồn tại + lấy MACN (đọc local — TaiKhoan nhân bản full)
    DECLARE @MACN_TK nchar(10);
    SELECT @MACN_TK = RTRIM(MACN)
    FROM TaiKhoan
    WHERE RTRIM(SOTK) = RTRIM(@SOTK);

    IF @MACN_TK IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại.', 16, 1);
        RETURN;
    END

    -- Lấy MACN của NV
    DECLARE @MACN_NV nchar(10);
    SELECT @MACN_NV = RTRIM(MACN)
    FROM NhanVien
    WHERE RTRIM(MANV) = RTRIM(@MANV);

    -- Xác định TK cùng hay khác chi nhánh với NV
    DECLARE @IsLocal bit = 0;
    IF @MACN_TK = @MACN_NV
        SET @IsLocal = 1;

    BEGIN TRY
        IF @IsLocal = 1
        BEGIN
            -- === Nhánh LOCAL: không cần DTC ===
            BEGIN TRANSACTION;

            UPDATE TaiKhoan
            SET SODU = SODU - @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND SODU >= @SOTIEN;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR(N'Số dư không đủ để rút.', 16, 1);
                RETURN;
            END

            INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
            VALUES(@SOTK, 'RT', GETDATE(), @SOTIEN, @MANV);

            COMMIT TRANSACTION;
        END
        ELSE
        BEGIN
            -- === Nhánh DISTRIBUTED: UPDATE TK qua LINK1, INSERT log local ===
            BEGIN DISTRIBUTED TRANSACTION;

            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan
            SET SODU = SODU - @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND SODU >= @SOTIEN;

            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR(N'Số dư không đủ để rút.', 16, 1);
                RETURN;
            END

            INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
            VALUES(@SOTK, 'RT', GETDATE(), @SOTIEN, @MANV);

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
