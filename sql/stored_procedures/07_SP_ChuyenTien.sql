USE NGANHANG;
GO

-- TaiKhoan được NHÂN BẢN TOÀN VẸN (Replicate Full) → mọi TK đều tồn tại local.
-- Do đó KHÔNG dùng EXISTS để phân biệt local/remote, mà dùng MACN:
--   MACN TK nhận = MACN TK chuyển → cùng chi nhánh → UPDATE local
--   MACN TK nhận ≠ MACN TK chuyển → khác chi nhánh → UPDATE qua LINK1
-- Quy tắc nhân bản: ĐỌC local, GHI chỉ tại site sở hữu (MACN khớp).
CREATE OR ALTER PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),
    @SOTK_NHAN   nchar(9),
    @SOTIEN      money,
    @MANV        nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);
        RETURN;
    END

    -- Kiểm tra TK chuyển tồn tại (đọc local — nhân bản full)
    DECLARE @MACN_CHUYEN nchar(10);
    SELECT @MACN_CHUYEN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
    IF @MACN_CHUYEN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1);
        RETURN;
    END

    -- Kiểm tra TK nhận tồn tại (đọc local — nhân bản full, không cần LINK1)
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- So sánh MACN để quyết định ghi local hay qua Linked Server
    DECLARE @IsNhanLocal bit = 0;
    IF @MACN_NHAN = @MACN_CHUYEN
        SET @IsNhanLocal = 1;

    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;

        UPDATE TaiKhoan
        SET SODU = SODU - @SOTIEN
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN) AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
            RETURN;
        END

        IF @IsNhanLocal = 1
        BEGIN
            UPDATE TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END
        ELSE
        BEGIN
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END

        INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
