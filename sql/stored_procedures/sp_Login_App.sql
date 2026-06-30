USE NGANHANG;
GO

-- Đồng bộ với bản deployed trong setup_db.js (alterSpLoginApp).
-- Thay đổi so với phiên bản cũ:
--   - Thêm bước resolve @DBUserName từ @LoginName qua sys.database_principals / sys.server_principals
--     để xử lý đúng trường hợp login name khác với DB user name.
--   - Bỏ nhánh "NHOM IS NULL → tự suy luận thành ChiNhanh" vì không đáng tin cậy.
CREATE OR ALTER PROCEDURE [dbo].[sp_Login_App]
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);
    DECLARE @DBUserName nvarchar(128);

    -- Resolve DB user name từ login name (hỗ trợ login name khác user name)
    SELECT @DBUserName = dp.name
    FROM sys.database_principals dp
    JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE sp.name = @LoginName;

    -- Fallback: nếu login name = user name
    IF @DBUserName IS NULL SET @DBUserName = @LoginName;

    SELECT @NHOM = rp.name
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE dp.name = @DBUserName
      AND rp.name IN ('NganHang','ChiNhanh','KhachHang');

    IF @NHOM IS NULL
    BEGIN
        RAISERROR(N'Tai khoan SQL chua duoc phan quyen Role (NganHang, ChiNhanh, KhachHang).', 16, 1);
        RETURN;
    END

    IF @NHOM != 'KhachHang'
    BEGIN
        SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM NhanVien
        WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;

        IF @MANV IS NULL AND @NHOM = 'NganHang'
        BEGIN
            SET @MANV = @DBUserName;
            SET @HOTEN = N'Quan Tri Vien (Ban Giam Doc)';
            SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh);
        END
    END
    ELSE
    BEGIN
        SELECT @MANV = CMND, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM KhachHang
        WHERE RTRIM(CMND) = @DBUserName;
    END

    IF @MANV IS NULL RETURN;

    SELECT
        @LoginName AS USERNAME,
        @MANV      AS MANV,
        @HOTEN     AS HOTEN,
        @NHOM      AS NHOM,
        @MACN      AS MACN;
END
GO

GRANT EXECUTE ON dbo.sp_Login_App TO NganHang;
GRANT EXECUTE ON dbo.sp_Login_App TO ChiNhanh;
GRANT EXECUTE ON dbo.sp_Login_App TO KhachHang;
GO
