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
    -- BƯỚC 1: KIỂM TRA NHÂN VIÊN TỒN TẠI VÀ ĐANG LÀM VIỆC
    -- Mục đích: Lấy MACN hiện tại và trạng thái xóa của nhân viên
    -- Nếu không tìm thấy → NV không tồn tại; TrangThaiXoa=1 → đã chuyển/xóa rồi
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

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA CHI NHÁNH MỚI KHÁC CHI NHÁNH HIỆN TẠI
    -- Mục đích: Tránh chuyển nhân viên sang chính chi nhánh đang làm
    -- ==========================================================================
    IF @MACN_HIENTAI = @MACN_MOI
    BEGIN
        RAISERROR(N'Chi nhánh mới phải khác chi nhánh hiện tại.', 16, 1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 3: SINH MÃ NHÂN VIÊN MỚI VỚI PREFIX CỦA CHI NHÁNH ĐÍCH
    -- Mục đích: Mỗi chi nhánh có prefix riêng (BENTHANH → 'BT', TANDINH → 'TD')
    -- Tìm MANV lớn nhất ở chi nhánh đích qua LINK1, +1 để có mã mới duy nhất
    -- ==========================================================================
    DECLARE @PREFIX     NVARCHAR(2);
    DECLARE @LAST_MANV  NVARCHAR(10);
    DECLARE @NEXT_NUM   INT;
    DECLARE @MANV_MOI   NVARCHAR(10);

    SET @PREFIX = CASE @MACN_MOI WHEN 'BENTHANH' THEN 'BT' ELSE 'TD' END;

    -- Tìm MANV lớn nhất có cùng prefix ở chi nhánh đích
    SELECT TOP 1 @LAST_MANV = RTRIM(MANV)
    FROM [LINK1].NGANHANG.dbo.NhanVien
    WHERE RTRIM(MANV) LIKE @PREFIX + '%'
    ORDER BY MANV DESC;

    IF @LAST_MANV IS NULL
        SET @NEXT_NUM = 1;
    ELSE
        SET @NEXT_NUM = CAST(SUBSTRING(@LAST_MANV, LEN(@PREFIX) + 1, 10) AS INT) + 1;

    SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);

    -- ==========================================================================
    -- BƯỚC 4: KIỂM TRA TRÙNG MÃ (RACE CONDITION)
    -- Mục đích: Trong trường hợp nhiều người cùng chuyển NV đồng thời,
    -- vòng lặp đảm bảo mã mới không bị trùng với bản ghi đã tồn tại
    -- ==========================================================================
    WHILE EXISTS (
        SELECT 1 FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(MANV) = @MANV_MOI
    )
    BEGIN
        SET @NEXT_NUM = @NEXT_NUM + 1;
        SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);
    END

    -- ==========================================================================
    -- BƯỚC 5: THỰC HIỆN GIAO DỊCH PHÂN TÁN
    -- Mục đích: Đảm bảo atomicity khi thao tác trên 2 server khác nhau
    -- Thứ tự: Đánh dấu xóa mềm ở local → INSERT NV mới sang chi nhánh đích
    -- ==========================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        -- BƯỚC 5a: ĐÁNH DẤU XÓA MỀM TẠI CHI NHÁNH HIỆN TẠI
        -- Không xóa hẳn, chỉ set TrangThaiXoa = 1 để giữ lịch sử
        UPDATE NhanVien
        SET TrangThaiXoa = 1
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        -- BƯỚC 5b: CHÈN BẢN GHI MỚI VÀO CHI NHÁNH ĐÍCH QUA LINKED SERVER
        -- Sao chép thông tin NV cũ, gán MANV mới (đúng prefix) và MACN mới
        INSERT INTO [LINK1].NGANHANG.dbo.NhanVien
               (MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        SELECT @MANV_MOI, CMND, HO, TEN, DIACHI, PHAI, SODT, @MACN_MOI, 0
        FROM NhanVien
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        COMMIT TRAN;

        -- BƯỚC 5c: TRẢ VỀ KẾT QUẢ CHO APP
        -- Trả MANV mới và MACN mới để ứng dụng hiển thị thông báo
        SELECT @MANV_MOI AS MANV_MOI, @MACN_MOI AS MACN_MOI;

    -- ==========================================================================
    -- BƯỚC 6: XỬ LÝ LỖI
    -- Mục đích: Nếu bất kỳ bước nào trong transaction bị lỗi → rollback toàn bộ
    -- ==========================================================================
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
