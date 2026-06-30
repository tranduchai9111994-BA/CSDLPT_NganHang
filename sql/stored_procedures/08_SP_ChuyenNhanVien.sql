USE NGANHANG;
GO

CREATE OR ALTER PROCEDURE SP_ChuyenNhanVien
    @MANV     NVARCHAR(10),
    @MACN_MOI NVARCHAR(10)
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA ĐIỀU KIỆN
    -- ==========================================================================
    DECLARE @MACN_HIENTAI NVARCHAR(10);
    DECLARE @TRANGTHAIXOA BIT;

    SELECT @MACN_HIENTAI = RTRIM(MACN), @TRANGTHAIXOA = TrangThaiXoa
    FROM NhanVien
    WHERE RTRIM(MANV) = RTRIM(@MANV);

    IF @MACN_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại ở chi nhánh này.', 16, 1);
        RETURN;
    END

    IF @TRANGTHAIXOA = 1
    BEGIN
        RAISERROR(N'Nhân viên này đã bị xóa hoặc đã chuyển công tác trước đó.', 16, 1);
        RETURN;
    END

    IF @MACN_HIENTAI = @MACN_MOI
    BEGIN
        RAISERROR(N'Chi nhánh mới phải khác chi nhánh hiện tại.', 16, 1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 2: SINH MANV MỚI VỚI PREFIX CỦA CHI NHÁNH ĐÍCH
    -- Prefix: BENTHANH → 'BT', TANDINH → 'TD'
    -- Tìm số lớn nhất đang dùng ở chi nhánh đích qua LINK1, +1 để có mã mới
    -- ==========================================================================
    DECLARE @PREFIX     NVARCHAR(2);
    DECLARE @LAST_MANV  NVARCHAR(10);
    DECLARE @NEXT_NUM   INT;
    DECLARE @MANV_MOI   NVARCHAR(10);

    SET @PREFIX = CASE @MACN_MOI WHEN 'BENTHANH' THEN 'BT' ELSE 'TD' END;

    SELECT TOP 1 @LAST_MANV = RTRIM(MANV)
    FROM [LINK1].NGANHANG.dbo.NhanVien
    WHERE RTRIM(MANV) LIKE @PREFIX + '%'
    ORDER BY MANV DESC;

    IF @LAST_MANV IS NULL
        SET @NEXT_NUM = 1;
    ELSE
        SET @NEXT_NUM = CAST(SUBSTRING(@LAST_MANV, LEN(@PREFIX) + 1, 10) AS INT) + 1;

    SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);

    -- Kiểm tra tránh trùng trong trường hợp race condition
    WHILE EXISTS (
        SELECT 1 FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(MANV) = @MANV_MOI
    )
    BEGIN
        SET @NEXT_NUM = @NEXT_NUM + 1;
        SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);
    END

    -- ==========================================================================
    -- BƯỚC 3: GIAO DỊCH PHÂN TÁN
    -- Đánh dấu xóa mềm ở Local, INSERT với MANV mới sang chi nhánh đích (LINK1)
    -- ==========================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        -- Đánh dấu đã chuyển tại chi nhánh hiện tại
        UPDATE NhanVien
        SET TrangThaiXoa = 1
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        -- Insert sang chi nhánh mới với MANV mới có đúng prefix
        INSERT INTO [LINK1].NGANHANG.dbo.NhanVien
               (MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        SELECT @MANV_MOI, CMND, HO, TEN, DIACHI, PHAI, SODT, @MACN_MOI, 0
        FROM NhanVien
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        COMMIT TRAN;

        -- Trả về MANV mới để app có thể hiển thị
        SELECT @MANV_MOI AS MANV_MOI, @MACN_MOI AS MACN_MOI;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg      NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT           = ERROR_SEVERITY();
        DECLARE @ErrState    INT           = ERROR_STATE();
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END
GO
