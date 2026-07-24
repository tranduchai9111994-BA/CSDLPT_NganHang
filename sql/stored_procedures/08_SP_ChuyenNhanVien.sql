USE NGANHANG;
GO

-- ==========================================================================
-- SP CHUYỂN NHÂN VIÊN SANG CHI NHÁNH KHÁC
-- Chạy trên chi nhánh nguồn (SQL1/SQL2) — nơi NV đang làm việc.
-- Dùng DISTRIBUTED TRANSACTION vì thao tác trên 2 server:
--   Local: đánh dấu xóa mềm NV cũ
--   LINK1: hoặc INSERT NV mới (chưa từng làm ở CN đích), hoặc "resurrect"
--          (bật TrangThaiXoa=0) nếu NV này đã từng làm và đã bị chuyển đi
--          trước đó tại CN đích (cùng CMND).
--
-- === Xử lý ca "chuyển đi rồi chuyển về" (RF-A) ===
-- Constraint UQ_NhanVien_CMND không phân biệt TrangThaiXoa → nếu chi nhánh
-- đích có NV cùng CMND (TrangThaiXoa=1) thì INSERT sẽ vi phạm UNIQUE.
-- Giải pháp: query LINK1 để phát hiện bản ghi soft-deleted → resurrect
-- (UPDATE TrangThaiXoa=0), giữ nguyên MANV cũ và toàn bộ thông tin cũ.
-- Điều này giữ lịch sử GD (GD_GOIRUT/GD_CHUYENTIEN vẫn map đúng NV qua MANV cũ).
-- Nếu tại CN đích đã có NV cùng CMND đang ACTIVE (TrangThaiXoa=0) → chặn.
-- ==========================================================================
CREATE OR ALTER PROCEDURE SP_ChuyenNhanVien
    @MANV     NVARCHAR(10),
    @MACN_MOI NVARCHAR(10)
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    -- ======================================================================
    -- BƯỚC 1: Kiểm tra NV nguồn tồn tại và đang làm việc
    -- ======================================================================
    DECLARE @MACN_HIENTAI NVARCHAR(10);
    DECLARE @TRANGTHAIXOA BIT;
    DECLARE @CMND         NCHAR(10);

    SELECT @MACN_HIENTAI = RTRIM(MACN),
           @TRANGTHAIXOA = TrangThaiXoa,
           @CMND         = CMND
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

    -- ======================================================================
    -- BƯỚC 2: Chi nhánh mới phải khác chi nhánh hiện tại
    -- ======================================================================
    IF @MACN_HIENTAI = @MACN_MOI
    BEGIN
        RAISERROR(N'Chi nhánh mới phải khác chi nhánh hiện tại.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- BƯỚC 3: Phát hiện bản ghi cùng CMND tại chi nhánh đích qua LINK1
    -- Kết quả: @EXIST_MANV, @EXIST_TRANGTHAI (NULL nếu không có).
    -- ======================================================================
    DECLARE @EXIST_MANV      NVARCHAR(10) = NULL;
    DECLARE @EXIST_TRANGTHAI BIT          = NULL;

    SELECT @EXIST_MANV      = RTRIM(MANV),
           @EXIST_TRANGTHAI = TrangThaiXoa
    FROM [LINK1].NGANHANG.dbo.NhanVien
    WHERE RTRIM(CMND) = RTRIM(@CMND);

    -- Trường hợp CMND đang ACTIVE tại đích → dữ liệu sai, chặn.
    IF @EXIST_MANV IS NOT NULL AND @EXIST_TRANGTHAI = 0
    BEGIN
        RAISERROR(N'Nhân viên có cùng CMND đang làm việc tại chi nhánh đích. Vui lòng kiểm tra dữ liệu.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- BƯỚC 4: Xác định nhánh RESURRECT hoặc INSERT_NEW
    -- Nhánh RESURRECT: có @EXIST_MANV và soft-deleted (TrangThaiXoa=1).
    --   → giữ nguyên MANV cũ, chỉ bật TrangThaiXoa=0.
    -- Nhánh INSERT_NEW: chưa có bản ghi CMND tại đích → sinh MANV mới theo prefix.
    -- ======================================================================
    DECLARE @IsResurrect BIT       = 0;
    DECLARE @MANV_MOI    NVARCHAR(10);

    IF @EXIST_MANV IS NOT NULL AND @EXIST_TRANGTHAI = 1
    BEGIN
        SET @IsResurrect = 1;
        SET @MANV_MOI    = @EXIST_MANV;
    END
    ELSE
    BEGIN
        DECLARE @PREFIX    NVARCHAR(2);
        DECLARE @LAST_MANV NVARCHAR(10);
        DECLARE @NEXT_NUM  INT;

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

        -- Guard chống trùng MANV do race condition
        WHILE EXISTS (
            SELECT 1 FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(MANV) = @MANV_MOI
        )
        BEGIN
            SET @NEXT_NUM = @NEXT_NUM + 1;
            SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);
        END
    END

    -- ======================================================================
    -- BƯỚC 5: Thực hiện giao dịch phân tán (2-phase commit)
    -- ======================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        -- 5a. Soft-delete NV tại chi nhánh nguồn
        UPDATE NhanVien
        SET TrangThaiXoa = 1
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        -- 5b. Ghi/khôi phục NV tại chi nhánh đích qua LINK1
        IF @IsResurrect = 1
        BEGIN
            -- Nhánh RESURRECT: chỉ bật TrangThaiXoa=0, giữ nguyên thông tin cũ.
            UPDATE [LINK1].NGANHANG.dbo.NhanVien
            SET TrangThaiXoa = 0
            WHERE RTRIM(MANV) = @MANV_MOI;
        END
        ELSE
        BEGIN
            -- Nhánh INSERT_NEW: chèn bản ghi mới với thông tin từ NV nguồn.
            INSERT INTO [LINK1].NGANHANG.dbo.NhanVien
                   (MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
            SELECT @MANV_MOI, CMND, HO, TEN, DIACHI, PHAI, SODT, @MACN_MOI, 0
            FROM NhanVien
            WHERE RTRIM(MANV) = RTRIM(@MANV);
        END

        COMMIT TRAN;

        -- 5c. Trả về kết quả cho app
        SELECT @MANV_MOI    AS MANV_MOI,
               @MACN_MOI    AS MACN_MOI,
               @IsResurrect AS IsResurrect;
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
