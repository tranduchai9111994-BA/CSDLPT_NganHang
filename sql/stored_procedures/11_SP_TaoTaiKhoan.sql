USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP TẠO TÀI KHOẢN ĐĂNG NHẬP (Login + User + Role + Log)
-- Đồng bộ với bản deployed trong setup_db.js (alterSpTaoTaiKhoanNguon).
-- Yêu cầu: Caller phải có Server Role [securityadmin] để CREATE LOGIN.
-- Dùng QUOTENAME + REPLACE thay vì nối chuỗi trực tiếp (giảm rủi ro injection).
-- SP là idempotent: chạy lại trên cùng server không lỗi (IF NOT EXISTS trước mỗi bước).
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME      VARCHAR(50),   -- Tham số: Tên login (dùng để đăng nhập SQL Server)
    @PASS        VARCHAR(50),   -- Tham số: Mật khẩu cho login
    @USERNAME    VARCHAR(50),   -- Tham số: Tên user trong database (có thể khác login name)
    @ROLE        VARCHAR(50),   -- Tham số: Role cần gán (NganHang/ChiNhanh/KhachHang)
    @LOAITK      VARCHAR(20),   -- Tham số: Loại tài khoản (NhanVien/KhachHang)
    @MATHAMCHIEU VARCHAR(50)    -- Tham số: Mã tham chiếu (MANV hoặc CMND)
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);  -- Biến lưu câu SQL động (dynamic SQL)
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');  -- Escape ký tự ' trong password

        -- ==========================================================================
        -- BƯỚC 1: TẠO LOGIN NẾU CHƯA TỒN TẠI
        -- Login là đối tượng server-level, dùng để xác thực kết nối
        -- Idempotent: chạy trên nhiều server, login có thể đã có → skip
        -- ==========================================================================
        IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)  -- Kiểm tra login đã tồn tại chưa
        BEGIN
            -- Tạo login với password, tắt kiểm tra hết hạn và chính sách password phức tạp
            SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME)                    -- QUOTENAME bọc [] chống injection
                        + ' WITH PASSWORD = ''' + @PassEscaped + ''''             -- Password đã được escape
                        + ', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';        -- Tắt chính sách password Windows
            EXEC(@SqlStr);  -- Thực thi câu SQL động
        END

        -- ==========================================================================
        -- BƯỚC 2: TẠO USER NẾU CHƯA TỒN TẠI VÀ MAP VỚI LOGIN
        -- User là đối tượng database-level, map với login để truy cập DB
        -- ==========================================================================
        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)  -- Kiểm tra user đã tồn tại chưa
        BEGIN
            SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME)          -- Tạo user với tên được bọc []
                        + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';     -- Map user với login tương ứng
            EXEC(@SqlStr);  -- Thực thi câu SQL động
        END

        -- ==========================================================================
        -- BƯỚC 3: GÁN ROLE (PHÂN QUYỀN)
        -- sp_addrolemember gán user vào role (NganHang/ChiNhanh/KhachHang)
        -- sp_addrolemember tự bỏ qua nếu user đã thuộc role → an toàn gọi lại
        -- ==========================================================================
        SET @SqlStr = 'EXEC sp_addrolemember '''                         -- Gọi SP hệ thống gán role
                    + REPLACE(@ROLE, '''', '''''') + ''', '              -- Tên role (escape ký tự ')
                    + QUOTENAME(@USERNAME) + ';';                        -- Tên user (bọc [])
        EXEC(@SqlStr);  -- Thực thi câu SQL động

        -- ==========================================================================
        -- BƯỚC 4: GHI THÔNG TIN VÀO BẢNG QUẢN TRỊ LOGIN (NẾU CHƯA CÓ)
        -- Lưu log tạo tài khoản vào bảng QuanTriLogin để quản lý và tra cứu
        -- ==========================================================================
        IF NOT EXISTS(SELECT 1 FROM dbo.QuanTriLogin WHERE LoginName = @LGNAME)  -- Kiểm tra đã có log chưa
        BEGIN
            INSERT INTO dbo.QuanTriLogin                                          -- Chèn bản ghi mới
                   (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
            VALUES (@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());    -- GETDATE() = thời điểm tạo
        END

        RETURN 0;  -- Trả mã thành công = 0

    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();  -- Lấy thông báo lỗi
        RAISERROR(@ErrMsg, 16, 1);  -- Ném lỗi lên tầng ứng dụng
        RETURN 3;  -- Trả mã lỗi = 3
    END CATCH
END
GO

GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO NganHang;   -- Cấp quyền thực thi cho role NganHang (admin)
GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO ChiNhanh;   -- Cấp quyền thực thi cho role ChiNhanh (nhân viên CN)
DENY  EXECUTE ON dbo.SP_TaoTaiKhoan TO KhachHang;  -- Từ chối quyền cho KhachHang (không được tạo TK)
GO
