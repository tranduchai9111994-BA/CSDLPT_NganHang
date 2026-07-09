USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP RESET MẬT KHẨU LOGIN
-- Đồng bộ với bản deployed trong setup_db.js (alterSpResetMatKhau).
-- Chạy trên: NGUON (nguồn chính), và cũng được nhân bản trên BENTHANH/TANDINH
-- để chi nhánh có thể tự reset mật khẩu nhân viên/khách hàng cục bộ.
-- WITH EXECUTE AS OWNER: cho phép user thường gọi ALTER LOGIN gián tiếp
-- mà không cần cấp quyền securityadmin trực tiếp.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[SP_ResetMatKhau]
    @LoginName   VARCHAR(50),               -- Tham số: tên login cần đổi mật khẩu
    @MATKHAU_MOI VARCHAR(50) = '123456'     -- Tham số: mật khẩu mới, mặc định '123456'
WITH EXECUTE AS OWNER  -- Chạy với quyền của owner SP (securityadmin) để được phép ALTER LOGIN
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- Kiểm tra login có tồn tại trên server không, tránh đổi mật khẩu cho login ảo
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LoginName)
    BEGIN
        RAISERROR(N'Tài khoản đăng nhập không tồn tại.', 16, 1);
        RETURN 1;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);  -- Biến lưu câu SQL động
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@MATKHAU_MOI, '''', '''''');  -- Escape ký tự ' trong password

        -- Đổi mật khẩu login ở cấp server
        SET @SqlStr = 'ALTER LOGIN ' + QUOTENAME(@LoginName) + ' WITH PASSWORD = ''' + @PassEscaped + ''';';
        EXEC(@SqlStr);

        -- Đồng bộ mật khẩu mới + thời điểm đổi vào bảng quản trị
        UPDATE dbo.QuanTriLogin
        SET MatKhauHienTai = @MATKHAU_MOI,
            NgayCapNhatMK  = GETDATE()
        WHERE LoginName = @LoginName;

        RETURN 0;  -- Thành công
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 2;  -- Lỗi khi đổi mật khẩu
    END CATCH
END
GO
