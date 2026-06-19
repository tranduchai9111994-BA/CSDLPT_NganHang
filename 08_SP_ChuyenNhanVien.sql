USE NGANHANG;
GO

CREATE OR ALTER PROCEDURE SP_ChuyenNhanVien
    @MANV NVARCHAR(10),
    @MACN_MOI NVARCHAR(10)
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    -- =========================================================================================
    -- BƯỚC 1: KIỂM TRA ĐIỀU KIỆN 
    -- =========================================================================================
    DECLARE @MACN_HIENTAI NVARCHAR(10);
    DECLARE @TRANGTHAIXOA BIT;

    -- Lấy thông tin chi nhánh hiện tại của nhân viên
    SELECT @MACN_HIENTAI = MACN, @TRANGTHAIXOA = TrangThaiXoa 
    FROM NhanVien 
    WHERE MANV = @MANV;

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

    -- =========================================================================================
    -- BƯỚC 2: THỰC THI GIAO DỊCH PHÂN TÁN
    -- Nhân viên được cập nhật trạng thái xóa ở Local, và được INSERT nguyên vẹn sang Remote
    -- Dùng BEGIN DISTRIBUTED TRAN để bảo đảm an toàn dữ liệu.
    -- =========================================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        -- 1. Cập nhật trạng thái "Đã chuyển/Đã xóa" tại Local
        UPDATE NhanVien 
        SET TrangThaiXoa = 1 
        WHERE MANV = @MANV;

        -- 2. Đẩy dữ liệu nhân viên sang chi nhánh mới (thông qua Linked Server)
        -- 2. Thêm nhân viên mới vào mảnh của Chi nhánh chuyển đến
        -- Dùng Linked Server (LINK1 đã được cấu hình trỏ về Site đối tác)
        INSERT INTO [LINK1].NGANHANG.dbo.NhanVien (MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        SELECT MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, @MACN_MOI, 0
        FROM NhanVien WHERE MANV = @MANV;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END
GO
