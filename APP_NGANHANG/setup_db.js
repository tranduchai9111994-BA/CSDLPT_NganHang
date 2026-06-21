const { configs } = require('./db');
const sql = require('mssql');

const createTablesAndLocalSPs = `
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[QuanTriLogin]') AND type in (N'U'))
BEGIN
    CREATE TABLE dbo.QuanTriLogin (
        LoginName       VARCHAR(50)  NOT NULL PRIMARY KEY,
        MatKhauHienTai  VARCHAR(50)  NOT NULL,
        LoaiTaiKhoan    VARCHAR(20)  NOT NULL,
        MaThamChieu     VARCHAR(50)  NOT NULL,
        NhomQuyen       VARCHAR(20)  NOT NULL,
        NgayTao         DATETIME     NOT NULL DEFAULT GETDATE(),
        NgayCapNhatMK   DATETIME     NULL
    );

    GRANT SELECT ON dbo.QuanTriLogin TO NganHang;
    DENY SELECT, INSERT, UPDATE, DELETE ON dbo.QuanTriLogin TO ChiNhanh;
    DENY SELECT, INSERT, UPDATE, DELETE ON dbo.QuanTriLogin TO KhachHang;
END

IF OBJECT_ID('dbo.SP_ResetMatKhau', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.SP_ResetMatKhau AS SELECT 1;');
`;

const alterSpLoginApp = `
ALTER PROCEDURE [dbo].[sp_Login_App]
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
        @MANV AS MANV,
        @HOTEN AS HOTEN,
        @NHOM AS NHOM,
        @MACN AS MACN;
END
`;

const alterSpLoginAppPermissions = `
GRANT EXECUTE ON dbo.sp_Login_App TO NganHang;
GRANT EXECUTE ON dbo.sp_Login_App TO ChiNhanh;
GRANT EXECUTE ON dbo.sp_Login_App TO KhachHang;
`;

const alterSpResetMatKhau = `
ALTER PROCEDURE [dbo].[SP_ResetMatKhau]
    @LoginName   VARCHAR(50),
    @MATKHAU_MOI VARCHAR(50) = '123456'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LoginName)
    BEGIN
        RAISERROR(N'Tài khoản đăng nhập không tồn tại.', 16, 1);
        RETURN 1;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@MATKHAU_MOI, '''', '''''');

        SET @SqlStr = 'ALTER LOGIN ' + QUOTENAME(@LoginName) + ' WITH PASSWORD = ''' + @PassEscaped + ''';';
        EXEC(@SqlStr);

        UPDATE dbo.QuanTriLogin
        SET MatKhauHienTai = @MATKHAU_MOI,
            NgayCapNhatMK  = GETDATE()
        WHERE LoginName = @LoginName;

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 2;
    END CATCH
END
`;

const alterSpResetMatKhauPermissions = `
GRANT EXECUTE ON dbo.SP_ResetMatKhau TO NganHang;
DENY EXECUTE ON dbo.SP_ResetMatKhau TO ChiNhanh;
DENY EXECUTE ON dbo.SP_ResetMatKhau TO KhachHang;
`;

const createSpDanhSachTrangThaiLogin = `
IF OBJECT_ID('dbo.SP_DanhSachTrangThaiLogin', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.SP_DanhSachTrangThaiLogin AS SELECT 1;');
`;

const createSpXoaLoiDongBo = `
IF OBJECT_ID('dbo.SP_XoaLoiDongBo', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.SP_XoaLoiDongBo AS SELECT 1;');
`;

const alterSpXoaLoiDongBo = `
ALTER PROCEDURE [dbo].[SP_XoaLoiDongBo]
    @LoginName  VARCHAR(50),
    @UserName   VARCHAR(50) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    -- Xóa record trong QuanTriLogin
    DELETE FROM dbo.QuanTriLogin WHERE LoginName = @LoginName;

    -- DROP DB user nếu còn tồn tại
    DECLARE @TargetUser VARCHAR(50) = ISNULL(@UserName, @LoginName);
    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @TargetUser)
    BEGIN
        DECLARE @Sql NVARCHAR(200) = N'DROP USER ' + QUOTENAME(@TargetUser);
        EXEC sp_executesql @Sql;
    END

    RETURN 0;
END
`;

const alterSpXoaLoiDongBoPermissions = `
GRANT EXECUTE ON dbo.SP_XoaLoiDongBo TO NganHang;
GRANT EXECUTE ON dbo.SP_XoaLoiDongBo TO ChiNhanh;
DENY EXECUTE ON dbo.SP_XoaLoiDongBo TO KhachHang;
`;

const alterSpDanhSachTrangThaiLogin = `
ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- TrangThaiTK: 0 = Chua cap, 1 = Da cap va login ton tai, 2 = Loi dong bo (trong QuanTriLogin nhung login bi xoa)
    SELECT
        'NhanVien' AS LoaiTK,
        nv.MANV AS MaThamChieu,
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
        RTRIM(nv.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM NhanVien nv
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK,
        kh.CMND AS MaThamChieu,
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
        RTRIM(kh.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND) AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
`;

const alterSpDanhSachTrangThaiLoginPermissions = `
GRANT EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO NganHang;
GRANT EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO ChiNhanh;
DENY EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO KhachHang;
`;

const createSpTaoTaiKhoan = `
IF OBJECT_ID('dbo.SP_TaoTaiKhoan', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.SP_TaoTaiKhoan AS SELECT 1;');
`;

const alterSpTaoTaiKhoanNguon = `
ALTER PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME   VARCHAR(50), 
    @PASS     VARCHAR(50), 
    @USERNAME VARCHAR(50), 
    @ROLE     VARCHAR(50),
    @LOAITK   VARCHAR(20),
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
`;

const grantSpTaoTaiKhoan = `
GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO NganHang;
GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO ChiNhanh;
DENY EXECUTE ON dbo.SP_TaoTaiKhoan TO KhachHang;
`;

async function executeScripts() {
    const servers = ['NGUON', 'BENTHANH', 'TANDINH', 'TRACUU'];
    for (const key of servers) {
        const conf = configs[key];
        if (!conf) continue;
        console.log(`\n================================`);
        console.log(`Đang kết nối đến ${key} (${conf.server})...`);
        try {
            const pool = await new sql.ConnectionPool({
                server: conf.server,
                database: conf.database,
                user: conf.user,
                password: conf.password,
                options: conf.options
            }).connect();

            console.log(`[${key}] Đang tạo Table và SP cơ sở...`);
            await pool.request().batch(createTablesAndLocalSPs);
            await pool.request().batch(alterSpLoginApp);
            await pool.request().batch(alterSpLoginAppPermissions);
            await pool.request().batch(alterSpResetMatKhau);
            await pool.request().batch(alterSpResetMatKhauPermissions);
            
            await pool.request().batch(createSpXoaLoiDongBo);
            await pool.request().batch(alterSpXoaLoiDongBo);
            await pool.request().batch(alterSpXoaLoiDongBoPermissions);

            await pool.request().batch(createSpDanhSachTrangThaiLogin);
            await pool.request().batch(alterSpDanhSachTrangThaiLogin);
            await pool.request().batch(alterSpDanhSachTrangThaiLoginPermissions);
            
            console.log(`[${key}] Đang thực thi ALTER SP_TaoTaiKhoan...`);
            await pool.request().batch(createSpTaoTaiKhoan);
            await pool.request().batch(alterSpTaoTaiKhoanNguon);
            await pool.request().batch(grantSpTaoTaiKhoan);

            console.log(`[${key}] Thành công!`);
            await pool.close();
        } catch (err) {
            console.error(`[${key}] LỖI: `, err.message);
        }
    }
    console.log(`\nHoàn thành thiết lập database.`);
    process.exit(0);
}

executeScripts();
