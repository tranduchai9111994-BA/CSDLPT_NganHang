USE NGANHANG;
GO

CREATE OR ALTER PROCEDURE SP_ChuyenTien
    @SOTK_CHUYEN NVARCHAR(50),
    @SOTK_NHAN NVARCHAR(50),
    @SOTIEN MONEY,
    @MANV NVARCHAR(50)
AS
BEGIN
    -- BẮT BUỘC BẬT: Đảm bảo giao dịch phân tán tự động Rollback nếu có lỗi Runtime hoặc đứt kết nối mạng
    SET XACT_ABORT ON;
    SET NOCOUNT ON;


    -- =========================================================================================
    -- BƯỚC 1: KIỂM TRA ĐIỀU KIỆN SỚM (FAIL-FAST)
    -- =========================================================================================
    IF @SOTK_CHUYEN = @SOTK_NHAN
    BEGIN
        RAISERROR(N'Tài khoản chuyển và nhận không được trùng nhau.', 16, 1);
        RETURN;
    END

    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.', 16, 1);
        RETURN;
    END

    DECLARE @SODU_CHUYEN MONEY;
    DECLARE @MACN_NHAN NVARCHAR(10);
    DECLARE @IS_REMOTE_NHAN BIT = 0; -- Cờ đánh dấu tài khoản nhận ở site khác

    -- 1. Lấy thông tin tài khoản chuyển (Phải nằm ở Site hiện tại mới được phép chuyển đi)
    SELECT @SODU_CHUYEN = SODU FROM TaiKhoan WHERE SOTK = @SOTK_CHUYEN;
    
    IF @SODU_CHUYEN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại ở chi nhánh này.', 16, 1);
        RETURN;
    END

    IF @SODU_CHUYEN < @SOTIEN
    BEGIN
        RAISERROR(N'Số dư không đủ để thực hiện giao dịch.', 16, 1);
        RETURN;
    END

    -- 2. Lấy thông tin tài khoản nhận (Tìm Local trước, nếu không có thì tìm ở LINK1)
    SELECT @MACN_NHAN = MACN FROM TaiKhoan WHERE SOTK = @SOTK_NHAN;
    
    IF @MACN_NHAN IS NULL
    BEGIN
        -- Tìm trên chi nhánh đối tác
        SELECT @MACN_NHAN = MACN FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK_NHAN;
        SET @IS_REMOTE_NHAN = 1;
    END

    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên hệ thống.', 16, 1);
        RETURN;
    END

    -- =========================================================================================
    -- BƯỚC 2: THỰC THI GIAO DỊCH PHÂN TÁN (DISTRIBUTED TRANSACTION)
    -- Sử dụng BEGIN DISTRIBUTED TRAN để kích hoạt MSDTC (Microsoft Distributed Transaction Coordinator)
    -- Điều này bảo đảm Two-Phase Commit (2PC): Cả 2 site đều cập nhật thành công, hoặc cùng Rollback.
    -- =========================================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        -- 1. Trừ tiền tài khoản chuyển (Local)
        UPDATE TaiKhoan 
        SET SODU = SODU - @SOTIEN 
        WHERE SOTK = @SOTK_CHUYEN;

        -- 2. Cộng tiền tài khoản nhận (Local hoặc Remote)
        IF @IS_REMOTE_NHAN = 0
        BEGIN
            UPDATE TaiKhoan 
            SET SODU = SODU + @SOTIEN 
            WHERE SOTK = @SOTK_NHAN;
        END
        ELSE
        BEGIN
            -- Thực thi truy vấn cập nhật từ xa thông qua Linked Server
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan 
            SET SODU = SODU + @SOTIEN 
            WHERE SOTK = @SOTK_NHAN;
        END

        -- 3. Ghi vết lịch sử vào bảng GD_CHUYENTIEN tại site Local
        -- Tối ưu: Chỉ ghi ở site chuyển tiền, site nhận tiền có thể xem qua báo cáo Liên chi nhánh.
        INSERT INTO GD_CHUYENTIEN (SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES (@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

        COMMIT TRAN;
        -- Kết thúc an toàn
    END TRY
    BEGIN CATCH
        -- Bắt lỗi và Rollback toàn cục nếu có sự cố (ví dụ đứt cáp mạng giữa 2 chi nhánh lúc UPDATE)
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END
GO
