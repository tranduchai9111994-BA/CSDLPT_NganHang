USE NGANHANG;
GO

CREATE OR ALTER PROCEDURE sp_Login_App
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);
    
    SELECT @NHOM = rp.name
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE dp.name = @LoginName
      AND rp.name IN ('NganHang','ChiNhanh','KhachHang');

    IF @NHOM IS NULL
    BEGIN
        SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM NhanVien
        WHERE RTRIM(MANV) = @LoginName AND TrangThaiXoa = 0;
        
        IF @MANV IS NOT NULL
        BEGIN
            SET @NHOM = 'ChiNhanh';
        END
    END
    ELSE
    BEGIN
        IF @NHOM != 'KhachHang'
        BEGIN
            SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
            FROM NhanVien
            WHERE RTRIM(MANV) = @LoginName AND TrangThaiXoa = 0;
            
            -- FALLBACK CHO ADMIN (Nhóm NganHang nhưng không có tên trong bảng Nhân Viên)
            IF @MANV IS NULL AND @NHOM = 'NganHang'
            BEGIN
                SET @MANV = @LoginName;
                SET @HOTEN = N'Quản Trị Viên (Ban Giám Đốc)';
                SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh); -- Lấy đại 1 MACN vì NganHang xem toàn hệ thống
            END
        END
        ELSE
        BEGIN
            SELECT @MANV = CMND, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
            FROM KhachHang
            WHERE RTRIM(CMND) = @LoginName;
        END
    END
    
    IF @MANV IS NULL
    BEGIN
        RETURN;
    END

    SELECT 
        @LoginName AS USERNAME,
        @MANV AS MANV,
        @HOTEN AS HOTEN,
        @NHOM AS NHOM,
        @MACN AS MACN;
END
GO
