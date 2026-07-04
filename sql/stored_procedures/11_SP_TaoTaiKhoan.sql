USE NGANHANG;
GO

-- Đồng bộ với bản deployed trong setup_db.js (alterSpTaoTaiKhoanNguon).
-- Yêu cầu: Caller phải có Server Role [securityadmin] để CREATE LOGIN.
-- Dùng QUOTENAME + REPLACE thay vì nối chuỗi trực tiếp (giảm rủi ro injection).
-- SP là idempotent: chạy lại trên cùng server không lỗi (IF NOT EXISTS trước mỗi bước).
CREATE OR ALTER PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME      VARCHAR(50),
    @PASS        VARCHAR(50),
    @USERNAME    VARCHAR(50),
    @ROLE        VARCHAR(50),
    @LOAITK      VARCHAR(20),
    @MATHAMCHIEU VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');

        -- ==========================================================================
        -- BƯỚC 1: TẠO LOGIN NẾU CHƯA TỒN TẠI
        -- Idempotent: chạy trên nhiều server, login có thể đã có → skip
        -- ==========================================================================
        IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
        BEGIN
            SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
            EXEC(@SqlStr);
        END

        -- ==========================================================================
        -- BƯỚC 2: TẠO USER NẾU CHƯA TỒN TẠI VÀ MAP VỚI LOGIN
        -- ==========================================================================
        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
        BEGIN
            SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME) + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
            EXEC(@SqlStr);
        END

        -- ==========================================================================
        -- BƯỚC 3: GÁN ROLE (PHÂN QUYỀN)
        -- sp_addrolemember tự bỏ qua nếu user đã thuộc role → an toàn gọi lại
        -- ==========================================================================
        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE, '''', '''''') + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

        -- ==========================================================================
        -- BƯỚC 4: GHI THÔNG TIN VÀO BẢNG QUẢN TRỊ LOGIN (NẾU CHƯA CÓ)
        -- ==========================================================================
        IF NOT EXISTS(SELECT 1 FROM dbo.QuanTriLogin WHERE LoginName = @LGNAME)
        BEGIN
            INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
            VALUES (@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());
        END

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
