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

    -- ==========================================================================
    -- BƯỚC 1: KIỂM TRA LOGIN NAME CHƯA TỒN TẠI TRÊN SERVER
    -- Mục đích: Tránh tạo trùng Login ở cấp SQL Server instance
    -- ==========================================================================
    IF EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
    BEGIN
        RAISERROR('Login name is already in use', 16, 1);
        RETURN 1;
    END

    -- ==========================================================================
    -- BƯỚC 2: KIỂM TRA USER NAME CHƯA TỒN TẠI TRONG DATABASE
    -- Mục đích: Tránh tạo trùng User ở cấp database NGANHANG
    -- ==========================================================================
    IF EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
    BEGIN
        RAISERROR('User name is already in use in the current database', 16, 1);
        RETURN 2;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');

        -- ==========================================================================
        -- BƯỚC 3: TẠO LOGIN CẤP SERVER
        -- Mục đích: Tạo SQL Login để người dùng có thể đăng nhập vào SQL Server
        -- Dùng QUOTENAME để tránh SQL injection qua tên login
        -- ==========================================================================
        SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
        EXEC(@SqlStr);

        -- ==========================================================================
        -- BƯỚC 4: TẠO USER CẤP DATABASE VÀ MAP VỚI LOGIN
        -- Mục đích: Tạo Database User liên kết với Login vừa tạo ở bước 3
        -- ==========================================================================
        SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME) + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
        EXEC(@SqlStr);

        -- ==========================================================================
        -- BƯỚC 5: GÁN ROLE (PHÂN QUYỀN)
        -- Mục đích: Thêm User vào role tương ứng (NganHang, ChiNhanh, KhachHang)
        -- Role quyết định user được phép làm gì trong hệ thống
        -- ==========================================================================
        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE, '''', '''''') + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

        -- ==========================================================================
        -- BƯỚC 6: GHI THÔNG TIN VÀO BẢNG QUẢN TRỊ LOGIN
        -- Mục đích: Lưu metadata (login, loại TK, mã tham chiếu, nhóm quyền)
        -- để quản lý và tra cứu trạng thái tài khoản từ giao diện ứng dụng
        -- ==========================================================================
        INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
        VALUES (@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());

        RETURN 0;

    -- ==========================================================================
    -- BƯỚC 7: XỬ LÝ LỖI
    -- Mục đích: Nếu bất kỳ bước nào lỗi → ném lại lỗi cho app xử lý
    -- Lưu ý: Các bước CREATE LOGIN/USER không nằm trong transaction tường minh
    -- nên nếu lỗi giữa chừng có thể cần cleanup thủ công
    -- ==========================================================================
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
