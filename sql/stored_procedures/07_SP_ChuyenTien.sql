USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP CHUYỂN TIỀN GIỮA 2 TÀI KHOẢN (có thể cùng hoặc khác chi nhánh)
-- Chạy trên chi nhánh (SQL1/SQL2) — nơi nhân viên thực hiện giao dịch.
--
-- Nguyên tắc phân tán:
--   TaiKhoan được NHÂN BẢN TOÀN VẸN → mọi TK đều tồn tại local → ĐỌC local.
--   Nhưng GHI chỉ tại site sở hữu (MACN khớp):
--     MACN TK nhận = MACN TK chuyển → cùng chi nhánh → UPDATE local
--     MACN TK nhận ≠ MACN TK chuyển → khác chi nhánh → UPDATE qua LINK1
--   GD_CHUYENTIEN KHÔNG nhân bản → log ghi tại chi nhánh thực hiện GD.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),   -- Tham số: Số tài khoản chuyển tiền đi
    @SOTK_NHAN   nchar(9),   -- Tham số: Số tài khoản nhận tiền
    @SOTIEN      money,      -- Tham số: Số tiền cần chuyển
    @MANV        nchar(10)   -- Tham số: Mã nhân viên thực hiện giao dịch
AS
BEGIN
    SET NOCOUNT ON;     -- Tắt thông báo "xx rows affected" để tăng hiệu suất
    SET XACT_ABORT ON;  -- Bắt buộc khi dùng DISTRIBUTED TRANSACTION — lỗi runtime tự ROLLBACK

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA SỐ TIỀN HỢP LỆ
    -- ==========================================================================
    IF @SOTIEN <= 0  -- Số tiền phải dương
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);  -- Ném lỗi severity 16
        RETURN;  -- Kết thúc SP
    END

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA TÀI KHOẢN CHUYỂN TỒN TẠI
    -- Đọc local (TaiKhoan nhân bản full) để lấy MACN của TK chuyển
    -- ==========================================================================
    DECLARE @MACN_CHUYEN nchar(10);  -- Biến lưu mã chi nhánh của TK chuyển
    SELECT @MACN_CHUYEN = RTRIM(MACN)  -- Lấy MACN, RTRIM bỏ khoảng trắng thừa (nchar)
    FROM TaiKhoan                       -- Đọc từ bảng TaiKhoan local (nhân bản full)
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);  -- So sánh sau khi trim (tránh lỗi nchar padding)

    IF @MACN_CHUYEN IS NULL  -- Không tìm thấy → TK chuyển không tồn tại
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 3: KIỂM TRA TÀI KHOẢN NHẬN TỒN TẠI
    -- Cũng đọc local (nhân bản full, không cần LINK1) để lấy MACN của TK nhận
    -- ==========================================================================
    DECLARE @MACN_NHAN nchar(10);  -- Biến lưu mã chi nhánh của TK nhận
    SELECT @MACN_NHAN = RTRIM(MACN)  -- Lấy MACN của TK nhận
    FROM TaiKhoan                     -- Đọc từ bảng TaiKhoan local
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);  -- So sánh SOTK sau khi trim

    IF @MACN_NHAN IS NULL  -- Không tìm thấy → TK nhận không tồn tại
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 4: XÁC ĐỊNH TK NHẬN LÀ CÙNG HAY KHÁC CHI NHÁNH
    -- Cùng MACN → UPDATE local; khác MACN → UPDATE qua LINK1 (giao dịch phân tán)
    -- ==========================================================================
    DECLARE @IsNhanLocal bit = 0;  -- Biến cờ: 0 = khác chi nhánh, 1 = cùng chi nhánh
    IF @MACN_NHAN = @MACN_CHUYEN   -- Nếu 2 TK cùng chi nhánh
        SET @IsNhanLocal = 1;       -- Đánh dấu TK nhận là local

    -- ==========================================================================
    -- BƯỚC 5: THỰC HIỆN GIAO DỊCH PHÂN TÁN
    -- DISTRIBUTED TRANSACTION đảm bảo atomicity khi thao tác trên 2 server
    -- Thứ tự: Trừ tiền TK chuyển → Cộng tiền TK nhận → Ghi log
    -- Nếu bất kỳ bước nào lỗi → XACT_ABORT tự ROLLBACK toàn bộ
    -- ==========================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;  -- Bắt đầu giao dịch phân tán (2-phase commit)

        -- BƯỚC 5a: TRỪ TIỀN TÀI KHOẢN CHUYỂN (tại local — site sở hữu TK chuyển)
        UPDATE TaiKhoan                 -- Cập nhật bảng TaiKhoan local
        SET SODU = SODU - @SOTIEN       -- Trừ số tiền chuyển khỏi số dư
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN)  -- Điều kiện: đúng TK chuyển
          AND SODU >= @SOTIEN;          -- Điều kiện: đủ số dư (tránh âm)

        IF @@ROWCOUNT = 0  -- Không có dòng nào được update → không đủ tiền hoặc TK không tồn tại
        BEGIN
            ROLLBACK TRANSACTION;  -- Hủy toàn bộ giao dịch
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
            RETURN;
        END

        -- BƯỚC 5b: CỘNG TIỀN TÀI KHOẢN NHẬN
        IF @IsNhanLocal = 1  -- Nếu TK nhận cùng chi nhánh
        BEGIN
            UPDATE TaiKhoan              -- Cập nhật bảng TaiKhoan local
            SET SODU = SODU + @SOTIEN    -- Cộng số tiền vào số dư TK nhận
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);  -- Điều kiện: đúng TK nhận
        END
        ELSE  -- TK nhận khác chi nhánh
        BEGIN
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan  -- Cập nhật qua Linked Server
            SET SODU = SODU + @SOTIEN              -- Cộng số tiền vào số dư TK nhận
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN); -- Điều kiện: đúng TK nhận
        END

        -- BƯỚC 5c: GHI LOG GIAO DỊCH VÀO BẢNG GD_CHUYENTIEN (local)
        -- Log ghi tại chi nhánh thực hiện GD (nơi nhân viên đang đăng nhập)
        -- GD_CHUYENTIEN không nhân bản → chỉ tồn tại tại site ghi
        INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)  -- Chèn log GD
        VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);  -- GETDATE() = thời điểm hiện tại

        COMMIT TRANSACTION;  -- Xác nhận giao dịch thành công (2-phase commit hoàn tất)

    -- ==========================================================================
    -- BƯỚC 6: XỬ LÝ LỖI — bắt exception, rollback nếu transaction còn mở
    -- ==========================================================================
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;  -- Rollback nếu transaction chưa kết thúc
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();  -- Lấy thông báo lỗi gốc
        RAISERROR(@ErrMsg, 16, 1);  -- Ném lỗi lên tầng ứng dụng để hiển thị cho user
    END CATCH
END
GO
