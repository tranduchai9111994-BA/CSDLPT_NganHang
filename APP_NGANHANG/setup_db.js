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

// sp_Login_App: chỉ deploy trên NGUON (Publisher ES-HAITD16).
// Merge Replication (article PUB_TRACUU) tự đồng bộ xuống SQL1/SQL2/SQL3
// (Subscriber) — không ALTER trực tiếp trên Subscriber vì DDL trigger
// MSmerge_tr_alterschemasonly sẽ chặn.
const alterSpLoginApp = `
ALTER PROCEDURE [dbo].[sp_Login_App]
    @LoginName nvarchar(128)  -- Tham số: Tên login của người dùng đăng nhập
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);  -- Biến lưu kết quả
    DECLARE @DBUserName nvarchar(128);  -- Biến lưu tên user trong database (có thể khác login name)

    -- BƯỚC 1: Resolve tên user trong database từ login name
    -- Login name và DB user name có thể khác nhau, dùng JOIN sys views để tìm user tương ứng
    SELECT @DBUserName = dp.name
    FROM sys.database_principals dp
    JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE sp.name = @LoginName;

    -- Fallback: nếu không tìm thấy mapping → dùng login name làm user name
    IF @DBUserName IS NULL SET @DBUserName = @LoginName;

    -- BƯỚC 2: Xác định nhóm quyền (role) của user — NganHang/ChiNhanh/KhachHang
    SELECT @NHOM = rp.name
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE dp.name = @DBUserName
      AND rp.name IN ('NganHang','ChiNhanh','KhachHang');

    IF @NHOM IS NULL  -- User không thuộc bất kỳ role nào → chưa phân quyền
    BEGIN
        RAISERROR(N'Tai khoan SQL chua duoc phan quyen Role (NganHang, ChiNhanh, KhachHang).', 16, 1);
        RETURN;
    END

    -- BƯỚC 3: Lấy thông tin chi tiết theo loại tài khoản
    IF @NHOM != 'KhachHang'  -- Không phải khách hàng → nhân viên hoặc admin
    BEGIN
        -- SQL3/TRACUU không có bảng NhanVien → bỏ qua bước này (OBJECT_ID trả NULL)
        IF OBJECT_ID('dbo.NhanVien', 'U') IS NOT NULL
        BEGIN
            SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
            FROM NhanVien
            WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;
        END

        -- Không tìm thấy NV nhưng role là NganHang → đây là admin (Ban Giám Đốc)
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
    ELSE  -- Role = KhachHang → tìm theo CMND trong bảng KhachHang
    BEGIN
        SELECT @MANV = CMND, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM KhachHang
        WHERE RTRIM(CMND) = @DBUserName;
    END

    -- BƯỚC 4: Trả về kết quả cho ứng dụng
    IF @MANV IS NULL RETURN;  -- Không tìm thấy → kết thúc, không trả gì

    SELECT
        @LoginName AS USERNAME,  -- Tên đăng nhập gốc
        @MANV AS MANV,           -- Mã nhân viên hoặc CMND khách hàng
        @HOTEN AS HOTEN,         -- Họ tên đầy đủ
        @NHOM AS NHOM,           -- Nhóm quyền (NganHang/ChiNhanh/KhachHang)
        @MACN AS MACN;           -- Mã chi nhánh
END
`;

const alterSpLoginAppPermissions = `
GRANT EXECUTE ON dbo.sp_Login_App TO NganHang;
GRANT EXECUTE ON dbo.sp_Login_App TO ChiNhanh;
GRANT EXECUTE ON dbo.sp_Login_App TO KhachHang;
`;

// SP_ResetMatKhau: chỉ deploy trên NGUON, cùng lý do với sp_Login_App
// (WITH EXECUTE AS OWNER để user thường có thể gọi ALTER LOGIN gián tiếp
// mà không cần cấp quyền securityadmin trực tiếp).
const alterSpResetMatKhau = `
ALTER PROCEDURE [dbo].[SP_ResetMatKhau]
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

// SP_XoaLoiDongBo: deploy trên cả 4 site. Dọn dẹp trường hợp "lỗi đồng bộ"
// — record còn trong QuanTriLogin / DB user còn tồn tại nhưng login server
// đã bị xóa (thường do phục hồi nhân viên phân tán không đồng bộ hết).
const alterSpXoaLoiDongBo = `
ALTER PROCEDURE [dbo].[SP_XoaLoiDongBo]
    @LoginName  VARCHAR(50),         -- Tham số: tên login bị lỗi đồng bộ
    @UserName   VARCHAR(50) = NULL   -- Tham số: tên DB user tương ứng, NULL = dùng luôn LoginName
WITH EXECUTE AS OWNER  -- Cần quyền cao hơn để DROP USER
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- Xóa record trong QuanTriLogin (không còn login server tương ứng)
    DELETE FROM dbo.QuanTriLogin WHERE LoginName = @LoginName;

    -- DROP DB user nếu còn tồn tại (mồ côi vì login server đã bị xóa)
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

// SP_DanhSachTrangThaiLogin (bản chung — NGUON/BENTHANH/TANDINH, có bảng NhanVien local).
// Bản riêng cho TRACUU (đọc NhanVien qua LINK1+LINK2) nằm ở
// alterSpDanhSachTrangThaiLogin_TRACUU phía dưới.
const alterSpDanhSachTrangThaiLogin = `
ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL  -- Tham số: mã chi nhánh, NULL = tất cả
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- TrangThaiTK: 0 = Chưa cấp, 1 = Đã cấp và login tồn tại, 2 = Lỗi đồng bộ (còn trong QuanTriLogin nhưng login đã bị xóa)
    SELECT
        'NhanVien' AS LoaiTK,          -- Cột phân loại: dòng nhân viên
        nv.MANV AS MaThamChieu,        -- Mã nhân viên
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,  -- Ghép họ + tên
        RTRIM(nv.MACN) AS MACN,        -- Mã chi nhánh của NV
        CASE
            WHEN ql.LoginName IS NULL THEN 0  -- Chưa cấp tài khoản
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1  -- Đã cấp, login active
            ELSE 2  -- Đã cấp nhưng login bị xóa/disable → lỗi đồng bộ
        END AS DaCapTaiKhoan,
        ql.LoginName,     -- Tên login (NULL nếu chưa cấp)
        ql.NhomQuyen,     -- Role được gán
        ql.NgayTao,       -- Ngày tạo tài khoản
        ql.NgayCapNhatMK  -- Ngày cập nhật mật khẩu gần nhất
    FROM NhanVien nv
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0  -- Chỉ lấy NV đang làm việc
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)

    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK,        -- Cột phân loại: dòng khách hàng
        kh.CMND AS MaThamChieu,        -- Số CMND (mã tham chiếu cho KH)
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,  -- Ghép họ + tên KH
        RTRIM(kh.MACN) AS MACN,        -- Mã chi nhánh của KH
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
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;  -- Nhóm theo loại TK, ưu tiên chưa cấp lên trước
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

// SP_TaoTaiKhoan: deploy trên NGUON/BENTHANH/TANDINH (skip TRACUU vì SP này
// là article được Merge Replication tự đồng bộ xuống Subscriber).
// Idempotent: chạy lại trên cùng server không lỗi (IF NOT EXISTS trước mỗi bước).
const alterSpTaoTaiKhoanNguon = `
ALTER PROCEDURE [dbo].[SP_TaoTaiKhoan]
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
        DECLARE @SqlStr VARCHAR(MAX);  -- Biến lưu câu SQL động
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');  -- Escape ký tự ' trong password

        -- BƯỚC 1: Tạo login nếu chưa tồn tại (đối tượng server-level)
        IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
        BEGIN
            SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
            EXEC(@SqlStr);
        END

        -- BƯỚC 2: Tạo user nếu chưa tồn tại và map với login (đối tượng database-level)
        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
        BEGIN
            SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME) + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
            EXEC(@SqlStr);
        END

        -- BƯỚC 3: Gán role (phân quyền) — sp_addrolemember tự bỏ qua nếu đã thuộc role
        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE, '''', '''''') + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

        -- BƯỚC 4: Ghi log tạo tài khoản vào bảng quản trị (nếu chưa có)
        IF NOT EXISTS(SELECT 1 FROM dbo.QuanTriLogin WHERE LoginName = @LGNAME)
        BEGIN
            INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
            VALUES (@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());
        END

        RETURN 0;  -- Thành công
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 3;  -- Lỗi khi tạo tài khoản
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

// sp_TaiKhoanKhachHang: KhachHang chỉ có GRANT EXECUTE trên SP này, không có
// SELECT trực tiếp trên TaiKhoan → đảm bảo KH không đọc được TK của người khác.
const alterSpTaiKhoanKhachHang = `
ALTER PROCEDURE [dbo].[sp_TaiKhoanKhachHang]
    @CMND nchar(10)  -- Tham số: Số CMND của khách hàng đang đăng nhập
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    -- Đọc từ bảng TaiKhoan local, lọc theo CMND để KH chỉ thấy TK của mình
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

// sp_DanhSachTaiKhoan: TaiKhoan replicate full (không filter MACN) → mỗi site
// đã có đủ data, chỉ cần đọc từ LINK1 (không UNION ALL LINK1+LINK2 để tránh trùng).
const alterSpDanhSachTaiKhoan = `
ALTER PROCEDURE [dbo].[sp_DanhSachTaiKhoan]
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen  -- Ghép họ + tên khách hàng
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk  -- Đọc TaiKhoan qua LINK1 (nhân bản full, 1 nguồn đủ)
    OUTER APPLY (  -- Lấy 1 bản ghi KH khớp CMND, trả NULL nếu không khớp
        SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND) = RTRIM(tk.CMND)
    ) kh
    ORDER BY tk.NGAYMOTK DESC;
END
`;

const createSpSaoKeToanBo = `
IF OBJECT_ID('dbo.sp_SaoKeToanBo', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_SaoKeToanBo AS SELECT 1;');
`;

// sp_SaoKeToanBo: tổng hợp toàn bộ giao dịch từ cả 2 chi nhánh trong 1 khoảng
// thời gian, dùng cho admin xem báo cáo tổng hợp. TRACUU/NGUON không có bảng
// GD_GOIRUT/GD_CHUYENTIEN local → phải đọc qua LINK1 (BENTHANH) + LINK2 (TANDINH).
const alterSpSaoKeToanBo = `
ALTER PROCEDURE [dbo].[sp_SaoKeToanBo]
    @TUNGAY datetime,   -- Tham số: Ngày bắt đầu khoảng sao kê
    @DENNGAY datetime   -- Tham số: Ngày kết thúc khoảng sao kê
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    -- Gộp GD gửi/rút (LOAIGD = 'GT'/'RT') từ BENTHANH (LINK1) + TANDINH (LINK2)
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    -- Gộp GD chuyển tiền từ BENTHANH: mỗi GD tạo 2 dòng — 'CT' (chuyển đi, trừ tiền) và 'NT' (nhận, cộng tiền)
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    -- Gộp GD chuyển tiền từ TANDINH (tương tự BENTHANH nhưng qua LINK2)
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ORDER BY NGAYGD;  -- Sắp toàn bộ kết quả theo ngày giao dịch tăng dần
END
`;

// sp_DanhSachNhanVien: chỉ deploy trên TRACUU (đọc NhanVien qua LINK1+LINK2)
const createSpDanhSachNhanVien = `
IF OBJECT_ID('dbo.sp_DanhSachNhanVien', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_DanhSachNhanVien AS SELECT 1;');
`;

const alterSpDanhSachNhanVien = `
ALTER PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL  -- Tham số: mã chi nhánh, NULL = lấy tất cả
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    SELECT RTRIM(MANV) AS MANV,
           RTRIM(HO) AS HO, RTRIM(TEN) AS TEN,
           RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
           RTRIM(CMND) AS CMND,
           RTRIM(MACN) AS MACN,
           SODT, DIACHI, TrangThaiXoa
    FROM (
        -- TRACUU không có bảng NhanVien local → gộp NV từ 2 chi nhánh qua LINK1 + LINK2
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS AllNV
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)
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
    @MACN nchar(10) = NULL,   -- Tham số: mã chi nhánh, NULL = tất cả
    @TUNGAY date = NULL,      -- Tham số: ngày bắt đầu, NULL = không giới hạn
    @DENNGAY date = NULL      -- Tham số: ngày kết thúc, NULL = không giới hạn
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    -- TaiKhoan replicate full → chỉ cần đọc từ LINK1 (không UNION ALL để tránh trùng)
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (  -- JOIN KhachHang local (replicate full trên TRACUU) để lấy họ tên
        SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND) = RTRIM(tk.CMND)
    ) kh
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))              -- Lọc theo chi nhánh (tùy chọn)
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)     -- Lọc từ ngày (tùy chọn)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)   -- Lọc đến ngày (tùy chọn)
    ORDER BY tk.NGAYMOTK DESC;
END
`;

// SP_SaoKeTaiKhoan phiên bản TRACUU: TRACUU không có bảng GD_GOIRUT/GD_CHUYENTIEN
// local → đọc giao dịch qua LINK1 (BENTHANH) + LINK2 (TANDINH).
const createSpSaoKeTaiKhoan_TRACUU = `
IF OBJECT_ID('dbo.SP_SaoKeTaiKhoan', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.SP_SaoKeTaiKhoan AS SELECT 1;');
`;

const alterSpSaoKeTaiKhoan_TRACUU = `
ALTER PROCEDURE [dbo].[SP_SaoKeTaiKhoan]
    @SOTK NVARCHAR(50),    -- Tham số: số tài khoản cần sao kê
    @TUNGAY DATETIME,      -- Tham số: ngày bắt đầu khoảng sao kê
    @DENNGAY DATETIME      -- Tham số: ngày kết thúc khoảng sao kê
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- BƯỚC 0: Defense in depth — KhachHang chỉ được xem TK của chính mình
    -- Trên TRACUU không có TaiKhoan local → verify qua LINK1/LINK2
    -- SUSER_SNAME() trả về tên SQL login đang gọi SP (KH dùng CMND làm login name)
    IF IS_ROLEMEMBER('KhachHang') = 1
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM [LINK1].NGANHANG.dbo.TaiKhoan
            WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND RTRIM(CMND) = RTRIM(SUSER_SNAME())
        )
        AND NOT EXISTS (
            SELECT 1 FROM [LINK2].NGANHANG.dbo.TaiKhoan
            WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND RTRIM(CMND) = RTRIM(SUSER_SNAME())
        )
        BEGIN
            RAISERROR(N'Bạn không có quyền xem sao kê tài khoản này.', 16, 1);
            RETURN;
        END
    END

    -- BƯỚC 1: Lấy số dư hiện tại của TK — thử LINK1 (BENTHANH) trước, không có thì thử LINK2 (TANDINH)
    DECLARE @SODU_HIENTAI MONEY;
    SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    IF @SODU_HIENTAI IS NULL
        SELECT @SODU_HIENTAI = SODU FROM [LINK2].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1);
        RETURN;
    END

    -- BƯỚC 2: Tính biến động sau @TUNGAY để suy ngược ra số dư đầu kỳ
    -- (số dư hiện tại đã bao gồm mọi GD, nên số dư đầu kỳ = hiện tại - biến động sau mốc TUNGAY)
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;
    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE WHEN LOAIGD IN ('GT','NT') THEN SOTIEN WHEN LOAIGD IN ('RT','CT') THEN -SOTIEN ELSE 0 END
    ), 0)
    FROM (
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, LOAIGD FROM [LINK2].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- BƯỚC 3: Gộp giao dịch trong khoảng [@TUNGAY, @DENNGAY] từ cả 2 chi nhánh,
    -- rồi tính số dư lũy kế theo từng dòng (running balance) bắt đầu từ @SODU_DAUKY
    ;WITH TransactionsInPeriod AS (
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK2].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    RunningBalance AS (
        SELECT NGAYGD, LOAIGD, SOTIEN,
            SODU_LUYKE = @SODU_DAUKY + SUM(
                CASE WHEN LOAIGD IN ('GT','NT') THEN SOTIEN WHEN LOAIGD IN ('RT','CT') THEN -SOTIEN ELSE 0 END
            ) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    SELECT * FROM RunningBalance ORDER BY NGAYGD ASC;  -- Sắp theo ngày giao dịch tăng dần
END
`;

// SP_DanhSachTrangThaiLogin phiên bản TRACUU: TRACUU không có NhanVien local
// → đọc qua LINK1+LINK2; KhachHang, QuanTriLogin, sys.server_principals đều local.
const alterSpDanhSachTrangThaiLogin_TRACUU = `
ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL  -- Tham số: mã chi nhánh, NULL = tất cả
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- BƯỚC 1: Danh sách nhân viên + trạng thái tài khoản login
    -- Gộp NV từ 2 chi nhánh (LINK1+LINK2) vì TRACUU không có NV local
    SELECT
        'NhanVien' AS LoaiTK,
        nv.MANV AS MaThamChieu,
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
        RTRIM(nv.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0  -- Chưa cấp tài khoản
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1  -- Đã cấp, active
            ELSE 2  -- Đã cấp nhưng login bị xóa/disable
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
    WHERE nv.TrangThaiXoa = 0  -- Chỉ lấy NV đang làm việc
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)

    -- BƯỚC 2: Gộp thêm danh sách khách hàng + trạng thái login (KhachHang replicate full trên TRACUU)
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
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)

    -- BƯỚC 3: Nhóm theo loại TK, ưu tiên chưa cấp TK lên trước, rồi theo họ tên
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
            // Bản chung dùng bảng NhanVien local — TRACUU không có bảng này, sẽ bị
            // ghi đè bằng bản TRACUU-specific (đọc qua LINK1+LINK2) ở khối "SP đặc thù TRACUU" bên dưới.
            if (key !== 'TRACUU') {
                await pool.request().batch(alterSpDanhSachTrangThaiLogin);
            }
            await pool.request().batch(alterSpDanhSachTrangThaiLoginPermissions);

            // SP_TaoTaiKhoan: skip TRACUU vì đã là article trong PUB_TRACUU (replication tự đồng bộ)
            if (key !== 'TRACUU') {
                console.log(`[${key}] Đang thực thi ALTER SP_TaoTaiKhoan...`);
                await pool.request().batch(createSpTaoTaiKhoan);
                await pool.request().batch(alterSpTaoTaiKhoanNguon);
                await pool.request().batch(grantSpTaoTaiKhoan);
            }

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
                await pool.request().batch(createSpSaoKeTaiKhoan_TRACUU);
                await pool.request().batch(alterSpSaoKeTaiKhoan_TRACUU);
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
