USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP CHUYỂN NHÂN VIÊN SANG CHI NHÁNH KHÁC
-- Chạy trên chi nhánh nguồn (SQL1/SQL2) — nơi NV đang làm việc.
-- Dùng DISTRIBUTED TRANSACTION vì thao tác trên 2 server:
--   Local: đánh dấu xóa mềm NV cũ
--   LINK1: chèn NV mới với MANV mới (prefix chi nhánh đích)
-- ==========================================================================
CREATE OR ALTER PROCEDURE SP_ChuyenNhanVien
    @MANV     NVARCHAR(10),  -- Tham số: Mã nhân viên cần chuyển
    @MACN_MOI NVARCHAR(10)   -- Tham số: Mã chi nhánh đích
AS
BEGIN
    SET XACT_ABORT ON;  -- Lỗi runtime → tự ROLLBACK (bắt buộc cho distributed tran)
    SET NOCOUNT ON;     -- Tắt thông báo đếm dòng ảnh hưởng

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA NHÂN VIÊN TỒN TẠI VÀ ĐANG LÀM VIỆC
    -- ==========================================================================
    DECLARE @MACN_HIENTAI NVARCHAR(10);  -- Biến lưu mã chi nhánh hiện tại của NV
    DECLARE @TRANGTHAIXOA BIT;           -- Biến lưu trạng thái xóa (0=đang làm, 1=đã xóa/chuyển)

    SELECT @MACN_HIENTAI = RTRIM(MACN),    -- Lấy MACN hiện tại, trim khoảng trắng
           @TRANGTHAIXOA = TrangThaiXoa     -- Lấy trạng thái xóa
    FROM NhanVien                           -- Đọc từ bảng NhanVien local
    WHERE RTRIM(MANV) = RTRIM(@MANV);       -- So sánh MANV sau khi trim

    IF @MACN_HIENTAI IS NULL  -- Không tìm thấy NV trong bảng
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại ở chi nhánh này.', 16, 1);
        RETURN;
    END

    IF @TRANGTHAIXOA = 1  -- NV đã bị đánh dấu xóa (đã chuyển trước đó)
    BEGIN
        RAISERROR(N'Nhân viên này đã bị xóa hoặc đã chuyển công tác trước đó.', 16, 1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA CHI NHÁNH MỚI KHÁC CHI NHÁNH HIỆN TẠI
    -- ==========================================================================
    IF @MACN_HIENTAI = @MACN_MOI  -- Chi nhánh đích trùng chi nhánh hiện tại
    BEGIN
        RAISERROR(N'Chi nhánh mới phải khác chi nhánh hiện tại.', 16, 1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 3: SINH MÃ NHÂN VIÊN MỚI VỚI PREFIX CỦA CHI NHÁNH ĐÍCH
    -- Mỗi chi nhánh có prefix riêng: BENTHANH → 'BT', TANDINH → 'TD'
    -- Tìm MANV lớn nhất ở chi nhánh đích qua LINK1, +1 để có mã mới
    -- ==========================================================================
    DECLARE @PREFIX     NVARCHAR(2);    -- Biến prefix của chi nhánh đích
    DECLARE @LAST_MANV  NVARCHAR(10);   -- Biến lưu MANV lớn nhất hiện có
    DECLARE @NEXT_NUM   INT;            -- Biến số thứ tự tiếp theo
    DECLARE @MANV_MOI   NVARCHAR(10);   -- Biến lưu MANV mới được sinh ra

    -- Xác định prefix dựa trên mã chi nhánh đích
    SET @PREFIX = CASE @MACN_MOI WHEN 'BENTHANH' THEN 'BT' ELSE 'TD' END;

    -- Tìm MANV lớn nhất có cùng prefix ở chi nhánh đích (qua LINK1)
    SELECT TOP 1 @LAST_MANV = RTRIM(MANV)         -- Lấy MANV lớn nhất
    FROM [LINK1].NGANHANG.dbo.NhanVien             -- Đọc bảng NhanVien tại chi nhánh đích
    WHERE RTRIM(MANV) LIKE @PREFIX + '%'           -- Lọc theo prefix (VD: 'BT%')
    ORDER BY MANV DESC;                             -- Sắp giảm dần để lấy lớn nhất

    IF @LAST_MANV IS NULL          -- Nếu chưa có NV nào với prefix này
        SET @NEXT_NUM = 1;          -- Bắt đầu từ số 1
    ELSE
        -- Cắt phần số sau prefix, chuyển sang INT, +1
        SET @NEXT_NUM = CAST(SUBSTRING(@LAST_MANV, LEN(@PREFIX) + 1, 10) AS INT) + 1;

    -- Ghép prefix + số (padding 3 chữ số): VD: 'BT' + '001' = 'BT001'
    SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);

    -- ==========================================================================
    -- BƯỚC 4: KIỂM TRA TRÙNG MÃ (RACE CONDITION)
    -- Trong trường hợp nhiều người cùng chuyển NV đồng thời,
    -- vòng lặp đảm bảo mã mới không bị trùng
    -- ==========================================================================
    WHILE EXISTS (  -- Kiểm tra MANV mới đã tồn tại chưa
        SELECT 1 FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(MANV) = @MANV_MOI
    )
    BEGIN
        SET @NEXT_NUM = @NEXT_NUM + 1;  -- Tăng số thứ tự lên 1
        SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);  -- Tạo mã mới
    END

    -- ==========================================================================
    -- BƯỚC 5: THỰC HIỆN GIAO DỊCH PHÂN TÁN
    -- Đảm bảo atomicity khi thao tác trên 2 server khác nhau
    -- ==========================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;  -- Bắt đầu giao dịch phân tán (2-phase commit)

        -- BƯỚC 5a: ĐÁNH DẤU XÓA MỀM TẠI CHI NHÁNH HIỆN TẠI
        UPDATE NhanVien            -- Cập nhật bảng NhanVien local
        SET TrangThaiXoa = 1       -- Đánh dấu xóa mềm (không xóa hẳng, giữ lịch sử)
        WHERE RTRIM(MANV) = RTRIM(@MANV);  -- Điều kiện: đúng mã NV cần chuyển

        -- BƯỚC 5b: CHÈN BẢN GHI MỚI VÀO CHI NHÁNH ĐÍCH QUA LINKED SERVER
        INSERT INTO [LINK1].NGANHANG.dbo.NhanVien                           -- Chèn vào bảng NV chi nhánh đích
               (MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)  -- Danh sách cột
        SELECT @MANV_MOI, CMND, HO, TEN, DIACHI, PHAI, SODT, @MACN_MOI, 0  -- Sao chép thông tin cũ, gán MANV mới + MACN mới + TrangThaiXoa=0
        FROM NhanVien                                                        -- Đọc thông tin NV từ local
        WHERE RTRIM(MANV) = RTRIM(@MANV);                                   -- Điều kiện: đúng NV cần chuyển

        COMMIT TRAN;  -- Xác nhận giao dịch thành công

        -- BƯỚC 5c: TRẢ VỀ KẾT QUẢ CHO APP
        SELECT @MANV_MOI AS MANV_MOI,  -- Trả mã NV mới để app hiển thị thông báo
               @MACN_MOI AS MACN_MOI;  -- Trả mã chi nhánh mới

    -- ==========================================================================
    -- BƯỚC 6: XỬ LÝ LỖI — rollback toàn bộ nếu có exception
    -- ==========================================================================
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;  -- Rollback nếu transaction chưa kết thúc
        DECLARE @ErrMsg      NVARCHAR(4000) = ERROR_MESSAGE();   -- Lấy thông báo lỗi
        DECLARE @ErrSeverity INT           = ERROR_SEVERITY();   -- Lấy mức độ nghiêm trọng
        DECLARE @ErrState    INT           = ERROR_STATE();      -- Lấy trạng thái lỗi
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);  -- Ném lỗi lên tầng ứng dụng
    END CATCH
END
GO
