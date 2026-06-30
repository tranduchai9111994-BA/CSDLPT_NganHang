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

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA SỐ TIỀN HỢP LỆ
    -- Mục đích: Đảm bảo số tiền chuyển phải dương, tránh giao dịch vô nghĩa
    -- ==========================================================================
    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA TÀI KHOẢN CHUYỂN TỒN TẠI
    -- Mục đích: Đọc local (nhân bản full) để lấy MACN của TK chuyển
    -- Nếu không tìm thấy → TK không tồn tại → báo lỗi
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
    -- Mục đích: Đọc local (nhân bản full, không cần LINK1) để lấy MACN của TK nhận
    -- Nếu không tìm thấy → TK nhận không có trên toàn hệ thống → báo lỗi
    -- ==========================================================================
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 4: XÁC ĐỊNH TK NHẬN LÀ LOCAL HAY REMOTE
    -- Mục đích: So sánh MACN để quyết định ghi vào bảng local hay qua Linked Server
    -- Cùng MACN → cùng chi nhánh → UPDATE local; khác MACN → UPDATE qua LINK1
    -- ==========================================================================
    DECLARE @IsNhanLocal bit = 0;
    IF @MACN_NHAN = @MACN_CHUYEN
        SET @IsNhanLocal = 1;

    -- ==========================================================================
    -- BƯỚC 5: THỰC HIỆN GIAO DỊCH PHÂN TÁN
    -- Mục đích: Đảm bảo tính toàn vẹn khi thao tác trên 2 server (hoặc cùng server)
    -- Thứ tự: Trừ tiền TK chuyển → Cộng tiền TK nhận → Ghi log giao dịch
    -- ==========================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;

        -- BƯỚC 5a: TRỪ TIỀN TÀI KHOẢN CHUYỂN
        -- Kiểm tra đồng thời: SOTK phải khớp VÀ SODU >= @SOTIEN (đủ tiền)
        -- Nếu @@ROWCOUNT = 0 → TK không tồn tại hoặc không đủ số dư → rollback
        UPDATE TaiKhoan
        SET SODU = SODU - @SOTIEN
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN) AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
            RETURN;
        END

        -- BƯỚC 5b: CỘNG TIỀN TÀI KHOẢN NHẬN
        -- Nếu cùng chi nhánh → UPDATE local; khác chi nhánh → UPDATE qua LINK1
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

        -- BƯỚC 5c: GHI LOG GIAO DỊCH CHUYỂN TIỀN
        -- Lưu lại thông tin giao dịch vào bảng GD_CHUYENTIEN để sao kê sau này
        INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

        COMMIT TRANSACTION;

    -- ==========================================================================
    -- BƯỚC 6: XỬ LÝ LỖI
    -- Mục đích: Nếu bất kỳ bước nào trong transaction bị lỗi → rollback toàn bộ
    -- ==========================================================================
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
