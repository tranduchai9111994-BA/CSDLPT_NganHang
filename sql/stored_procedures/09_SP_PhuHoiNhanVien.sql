USE NGANHANG;
GO

-- ==========================================================================
-- SP PHỤC HỒI NHÂN VIÊN (sau khi đã chuyển chi nhánh)
-- Chạy trên chi nhánh đang phục hồi (chi nhánh cũ của NV).
-- Vấn đề: khi NV được chuyển BT→TD, bản ghi TD00X vẫn active trên SQL2.
-- Nếu chỉ SET TrangThaiXoa=0 cho BT001 mà không deactivate TD00X
-- → 2 bản ghi cùng 1 người đều active = inconsistency.
-- SP này giải quyết bằng DISTRIBUTED TRANSACTION:
--   Local : SET TrangThaiXoa=0 cho @MANV (phục hồi)
--   LINK1 : SET TrangThaiXoa=1 cho NV cùng CMND đang active ở chi nhánh kia
-- ==========================================================================
CREATE OR ALTER PROCEDURE SP_PhuHoiNhanVien
    @MANV NVARCHAR(10)   -- Mã NV cần phục hồi (VD: BT001)
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    -- Bước 1: Kiểm tra NV tồn tại và đang ở trạng thái xóa
    DECLARE @CMND         NVARCHAR(20);
    DECLARE @TRANGTHAIXOA BIT;

    SELECT @CMND = RTRIM(CMND), @TRANGTHAIXOA = TrangThaiXoa
    FROM NhanVien
    WHERE RTRIM(MANV) = RTRIM(@MANV);

    IF @CMND IS NULL
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại ở chi nhánh này.', 16, 1);
        RETURN;
    END

    IF @TRANGTHAIXOA = 0
    BEGIN
        RAISERROR(N'Nhân viên này đang hoạt động, không cần phục hồi.', 16, 1);
        RETURN;
    END

    -- Bước 2: Tìm bản ghi đang active cùng CMND ở chi nhánh kia (qua LINK1)
    -- Đây là bản ghi được tạo khi NV được chuyển sang chi nhánh kia
    DECLARE @MANV_BEN_KIA NVARCHAR(10);

    SELECT TOP 1 @MANV_BEN_KIA = RTRIM(MANV)
    FROM [LINK1].NGANHANG.dbo.NhanVien
    WHERE RTRIM(CMND) = @CMND
      AND TrangThaiXoa = 0;

    -- Bước 3: Distributed transaction - phục hồi local + deactivate bên kia
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        -- Phục hồi NV tại chi nhánh hiện tại
        UPDATE NhanVien
        SET TrangThaiXoa = 0
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        -- Nếu có bản ghi active ở chi nhánh kia → deactivate
        IF @MANV_BEN_KIA IS NOT NULL
        BEGIN
            UPDATE [LINK1].NGANHANG.dbo.NhanVien
            SET TrangThaiXoa = 1
            WHERE RTRIM(MANV) = @MANV_BEN_KIA;
        END

        COMMIT TRAN;

        -- Trả về kết quả để app hiển thị
        SELECT @MANV        AS MANV_PHUCHOI,
               @MANV_BEN_KIA AS MANV_DEACTIVATED;  -- NULL nếu không có bản ghi bên kia

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg      NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrState    INT            = ERROR_STATE();
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END
GO

PRINT N'SP_PhuHoiNhanVien created.';
GO
