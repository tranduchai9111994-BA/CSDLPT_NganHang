USE NGANHANG;
GO

-- Đồng bộ với bản deployed trong setup_db.js (alterSpTaoTaiKhoanNguon).
-- Thay đổi so với phiên bản cũ (4 params):
--   - Thêm @LOAITK, @MATHAMCHIEU để ghi vào QuanTriLogin ngay trong SP
--   - WITH EXECUTE AS OWNER để có quyền tạo Login/User cấp Server
--   - Dùng QUOTENAME + REPLACE thay vì nối chuỗi trực tiếp (giảm rủi ro injection)
CREATE OR ALTER PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME      VARCHAR(50),
    @PASS        VARCHAR(50),
    @USERNAME    VARCHAR(50),
    @ROLE        VARCHAR(50),
    @LOAITK      VARCHAR(20),
    @MATHAMCHIEU VARCHAR(50)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
    BEGIN
        RAISERROR('Login name is already in use', 16, 1);
        RETURN 1;
    END

    IF EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
    BEGIN
        RAISERROR('User name is already in use in the current database', 16, 1);
        RETURN 2;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');

        SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
        EXEC(@SqlStr);

        SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME) + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
        EXEC(@SqlStr);

        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE, '''', '''''') + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

        INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
        VALUES (@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 3;
    END CATCH
END
GO

GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO NganHang;
GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO ChiNhanh;
DENY  EXECUTE ON dbo.SP_TaoTaiKhoan TO KhachHang;
GO
