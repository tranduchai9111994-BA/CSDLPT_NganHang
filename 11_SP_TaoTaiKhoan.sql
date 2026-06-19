USE NGANHANG;
GO

CREATE OR ALTER PROCEDURE SP_TaoTaiKhoan
    @LGNAME VARCHAR(50),
    @PASS VARCHAR(50),
    @USERNAME VARCHAR(50),
    @ROLE VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RET INT;

    -- 1. Kiểm tra xem Login đã tồn tại chưa
    IF EXISTS (SELECT name FROM sys.server_principals WHERE name = @LGNAME)
    BEGIN
        RETURN 1; -- Trạng thái 1: Login name bị trùng (đã tồn tại)
    END
    
    -- 2. Kiểm tra xem User đã tồn tại chưa
    IF EXISTS (SELECT name FROM sys.database_principals WHERE name = @USERNAME)
    BEGIN
        RETURN 2; -- Trạng thái 2: User name bị trùng (đã tồn tại trong Database hiện tại)
    END

    BEGIN TRY
        -- 3. Tạo Login ở cấp Server
        DECLARE @SqlStr NVARCHAR(MAX);
        SET @SqlStr = 'CREATE LOGIN [' + @LGNAME + '] WITH PASSWORD = ''' + @PASS + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
        EXEC(@SqlStr);
        
        -- 4. Tạo User ở cấp Database, ánh xạ tới Login vừa tạo
        SET @SqlStr = 'CREATE USER [' + @USERNAME + '] FOR LOGIN [' + @LGNAME + '];';
        EXEC(@SqlStr);
        
        -- 5. Gán Role cho User để cấp quyền phân tán
        EXEC sp_addrolemember @ROLE, @USERNAME;

        RETURN 0; -- Trạng thái 0: Thành công
    END TRY
    BEGIN CATCH
        -- Bắt lỗi nếu có lỗi xảy ra trong quá trình tạo tài khoản
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN 3; -- Trạng thái 3: Lỗi hệ thống trong quá trình thực thi lệnh CREATE
    END CATCH
END
GO
