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
        -- SQL3/TRACUU không có bảng NhanVien → bỏ qua bước này
        IF OBJECT_ID('dbo.NhanVien', 'U') IS NOT NULL
        BEGIN
            SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
            FROM NhanVien
            WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;
        END

        IF @MANV IS NULL AND @NHOM = 'NganHang'
        BEGIN
            SET @MANV = @DBUserName;
            SET @HOTEN = N'Quan Tri Vien (Ban Giam Doc)';
            -- SQL3/TRACUU không có bảng ChiNhanh → hardcode MACN = 'TRACUU'
            IF OBJECT_ID('dbo.ChiNhanh', 'U') IS NOT NULL
                SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh);
            ELSE
                SET @MACN = N'TRACUU';
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
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');

        IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
        BEGIN
            SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
            EXEC(@SqlStr);
        END

        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
        BEGIN
            SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME) + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
            EXEC(@SqlStr);
        END

        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE, '''', '''''') + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

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
`;

const grantSpTaoTaiKhoan = `
GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO NganHang;
GRANT EXECUTE ON dbo.SP_TaoTaiKhoan TO ChiNhanh;
DENY EXECUTE ON dbo.SP_TaoTaiKhoan TO KhachHang;
`;

// sp_TaiKhoanKhachHang: deploy trên tất cả server giao dịch (BENTHANH, TANDINH, và NGUON để đồng bộ)
const createSpTaiKhoanKhachHang = `
IF OBJECT_ID('dbo.sp_TaiKhoanKhachHang', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_TaiKhoanKhachHang AS SELECT 1;');
`;

const alterSpTaiKhoanKhachHang = `
ALTER PROCEDURE [dbo].[sp_TaiKhoanKhachHang]
    @CMND nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK)  AS SOTK, RTRIM(tk.CMND) AS CMND,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM TaiKhoan tk
    WHERE RTRIM(tk.CMND) = RTRIM(@CMND)
    ORDER BY tk.NGAYMOTK DESC;
END
`;

const grantSpTaiKhoanKhachHang = `
GRANT EXECUTE ON dbo.sp_TaiKhoanKhachHang TO KhachHang;
GRANT EXECUTE ON dbo.sp_TaiKhoanKhachHang TO ChiNhanh;
GRANT EXECUTE ON dbo.sp_TaiKhoanKhachHang TO NganHang;
`;

// sp_DanhSachTaiKhoan + sp_SaoKeToanBo: chỉ deploy trên TRACUU và NGUON
// (dùng LINK1+LINK2 — LINK2 chỉ định nghĩa trên TRACUU/NGUON)
const createSpDanhSachTaiKhoan = `
IF OBJECT_ID('dbo.sp_DanhSachTaiKhoan', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_DanhSachTaiKhoan AS SELECT 1;');
`;

const alterSpDanhSachTaiKhoan = `
ALTER PROCEDURE [dbo].[sp_DanhSachTaiKhoan]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)
    UNION ALL
    SELECT RTRIM(tk.SOTK), RTRIM(tk.CMND), tk.SODU, RTRIM(tk.MACN),
           CONVERT(varchar, tk.NGAYMOTK, 103),
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN)
    FROM [LINK2].NGANHANG.dbo.TaiKhoan tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)
    ORDER BY NGAYMOTK DESC;
END
`;

const createSpSaoKeToanBo = `
IF OBJECT_ID('dbo.sp_SaoKeToanBo', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_SaoKeToanBo AS SELECT 1;');
`;

const alterSpSaoKeToanBo = `
ALTER PROCEDURE [dbo].[sp_SaoKeToanBo]
    @TUNGAY datetime,
    @DENNGAY datetime
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ORDER BY NGAYGD;
END
`;

// sp_DanhSachNhanVien: chỉ deploy trên TRACUU (đọc NhanVien qua LINK1+LINK2)
const createSpDanhSachNhanVien = `
IF OBJECT_ID('dbo.sp_DanhSachNhanVien', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_DanhSachNhanVien AS SELECT 1;');
`;

const alterSpDanhSachNhanVien = `
ALTER PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(MANV) AS MANV,
           RTRIM(HO) AS HO, RTRIM(TEN) AS TEN,
           RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
           RTRIM(CMND) AS CMND,
           RTRIM(MACN) AS MACN,
           SODT, DIACHI, TrangThaiXoa
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS AllNV
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
`;

// sp_LietKeTaiKhoanTheoNgay phiên bản TRACUU: đọc TaiKhoan qua LINK1+LINK2
const createSpLietKeTKTheoNgay_TRACUU = `
IF OBJECT_ID('dbo.sp_LietKeTaiKhoanTheoNgay', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_LietKeTaiKhoanTheoNgay AS SELECT 1;');
`;

const alterSpLietKeTKTheoNgay_TRACUU = `
ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,
    @TUNGAY date = NULL,
    @DENNGAY date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM (
        SELECT SOTK, CMND, SODU, MACN, NGAYMOTK
        FROM [LINK1].NGANHANG.dbo.TaiKhoan
        UNION ALL
        SELECT SOTK, CMND, SODU, MACN, NGAYMOTK
        FROM [LINK2].NGANHANG.dbo.TaiKhoan
    ) AS tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
`;

// SP_DanhSachTrangThaiLogin phiên bản TRACUU: NhanVien qua LINK, KhachHang local
const alterSpDanhSachTrangThaiLogin_TRACUU = `
ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS nv
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
            // TRACUU là Replication Subscriber → DDL trigger của Merge Replication chặn ALTER PROCEDURE.
            // Giải pháp: tắt tạm DDL trigger trước khi deploy SP, bật lại sau.
            // (Đây là cách chính xác khi không có Publisher chuyên dụng trong hệ thống demo.)
            // sp_Login_App + sp_ResetMatKhau: chỉ deploy trên NGUON (Publisher ES-HAITD16).
            // Replication tự đồng bộ xuống SQL1/SQL2/SQL3 — không deploy trực tiếp lên Subscriber
            // vì MSmerge_tr_alterschemasonly (system trigger) chặn DDL trên Subscriber.
            if (key === 'NGUON') {
                await pool.request().batch(alterSpLoginApp);
                await pool.request().batch(alterSpLoginAppPermissions);
                await pool.request().batch(alterSpResetMatKhau);
                await pool.request().batch(alterSpResetMatKhauPermissions);
            }
            
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

            // sp_TaiKhoanKhachHang: deploy trên tất cả server
            await pool.request().batch(createSpTaiKhoanKhachHang);
            await pool.request().batch(alterSpTaiKhoanKhachHang);
            await pool.request().batch(grantSpTaiKhoanKhachHang);

            // sp_DanhSachTaiKhoan + sp_SaoKeToanBo: chỉ deploy trên TRACUU/NGUON (cần LINK2)
            if (key === 'TRACUU' || key === 'NGUON') {
                console.log(`[${key}] Đang deploy SP xuyên mảnh (LINK1+LINK2)...`);
                await pool.request().batch(createSpDanhSachTaiKhoan);
                await pool.request().batch(alterSpDanhSachTaiKhoan);
                await pool.request().batch(createSpSaoKeToanBo);
                await pool.request().batch(alterSpSaoKeToanBo);
            }

            // SP đặc thù TRACUU: đọc NhanVien/TaiKhoan qua LINK (TRACUU chỉ có KhachHang local)
            if (key === 'TRACUU') {
                console.log(`[${key}] Đang deploy SP TRACUU-specific (NhanVien/TaiKhoan qua LINK)...`);
                await pool.request().batch(createSpDanhSachNhanVien);
                await pool.request().batch(alterSpDanhSachNhanVien);
                await pool.request().batch(createSpLietKeTKTheoNgay_TRACUU);
                await pool.request().batch(alterSpLietKeTKTheoNgay_TRACUU);
                await pool.request().batch(alterSpDanhSachTrangThaiLogin_TRACUU);
            }

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
