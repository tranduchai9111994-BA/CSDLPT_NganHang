# 📚 Toàn Bộ Stored Procedures — Source Code & Giải Thích Cơ Chế Phân Tán

> **Đây là nguồn sự thật (source of truth)** cho toàn bộ SP đang chạy trong hệ thống. Mỗi SP đi kèm giải thích **chạy ở đâu**, **dùng Linked Server nào**, và **cơ chế phân tán liên quan**.
>
> File gốc SQL: [`sql/stored_procedures/`](../sql/stored_procedures/). Bản inline dùng để deploy tự động: `APP_NGANHANG/setup_db.js`. Bản đặc thù TRACUU: [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql).

**Danh sách:**
- [1. `sp_Login_App`](#1-sp_login_app---xác-thực-đăng-nhập)
- [2. `SP_TaoTaiKhoan`](#2-sp_taotaikhoan---tạo-loginuserrole)
- [3. `SP_ResetMatKhau`](#3-sp_resetmatkhau---đổi-mật-khẩu)
- [4. `sp_ThemKhachHang`](#4-sp_themkhachhang)
- [5. `sp_LietKeKhachHang`](#5-sp_lietkekhachhang)
- [6. `SP_SaoKeTaiKhoan`](#6-sp_saoketaikhoan---bản-chi-nhánh)
- [7. `sp_ChuyenTien` ⭐](#7-sp_chuyentien---chuyển-tiền-liên-chi-nhánh)
- [8. `sp_GuiTien` / `sp_RutTien`](#8-sp_guitien-sp_ruttien---gửi-rút-tiền)
- [9. `sp_MoTaiKhoan`](#9-sp_motaikhoan---mở-tài-khoản)
- [10. `sp_ChuyenNhanVien` ⭐](#10-sp_chuyennhanvien---chuyển-nhân-viên-liên-chi-nhánh)
- [11. `sp_PhucHoiNhanVien`](#11-sp_phuchoinhanvien---phục-hồi-nv-đã-chuyển)
- [12. `sp_TaiKhoanKhachHang`](#12-sp_taikhoankhachhang---kh-xem-tk-của-mình)
- [12b. `SP_DongTaiKhoan` ⭐ mới](#12b-sp_dongtaikhoan---đóng-tài-khoản-defense-in-depth)
- [13. SP đặc thù TRACUU](#13-sp-đặc-thù-tracuu-sql3)

---

## 1. `sp_Login_App` — Xác thực đăng nhập

**Deploy:** Article của cả 3 Publication → có trên NGUON/SQL1/SQL2/SQL3 (chỉ ALTER trên NGUON).
**Gọi bởi:** `routes/auth.js:POST /login`.
**Cơ chế:**
- Resolve `@DBUserName` từ `sys.database_principals` join `sys.server_principals` bằng SID (xử lý trường hợp login name khác DB user name).
- Xác định Role qua `sys.database_role_members`.
- Dùng `OBJECT_ID('dbo.NhanVien', 'U')` **guard** để chạy được trên TRACUU (schema khác các chi nhánh — không có bảng `NhanVien`/`ChiNhanh`).

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_Login_App]
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);
    DECLARE @DBUserName nvarchar(128);

    -- Resolve DB user name từ login name qua SID
    SELECT @DBUserName = dp.name
    FROM sys.database_principals dp
    JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE sp.name = @LoginName;

    IF @DBUserName IS NULL SET @DBUserName = @LoginName;

    -- Tìm Role (NganHang / ChiNhanh / KhachHang)
    SELECT @NHOM = rp.name
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id  = rp.principal_id
    WHERE dp.name = @DBUserName
      AND rp.name IN ('NganHang','ChiNhanh','KhachHang');

    IF @NHOM IS NULL
    BEGIN
        RAISERROR(N'Tai khoan SQL chua duoc phan quyen Role.', 16, 1); RETURN;
    END

    IF @NHOM != 'KhachHang'
    BEGIN
        IF OBJECT_ID('dbo.NhanVien', 'U') IS NOT NULL         -- Guard: TRACUU không có NhanVien
        BEGIN
            SELECT @MANV = MANV,
                   @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN),
                   @MACN = MACN
            FROM NhanVien
            WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;
        END

        -- NganHang trên TRACUU: không có bản ghi NV → dùng username làm MANV, MACN='TRACUU'
        IF @MANV IS NULL AND @NHOM = 'NganHang'
        BEGIN
            SET @MANV = @DBUserName;
            SET @HOTEN = N'Quan Tri Vien (Ban Giam Doc)';
            IF OBJECT_ID('dbo.ChiNhanh', 'U') IS NOT NULL
                SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh);
            ELSE
                SET @MACN = N'TRACUU';
        END
    END
    ELSE
    BEGIN
        SELECT @MANV = CMND,
               @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN),
               @MACN = MACN
        FROM KhachHang
        WHERE RTRIM(CMND) = @DBUserName;
    END

    IF @MANV IS NULL RETURN;

    SELECT @LoginName AS USERNAME, @MANV AS MANV, @HOTEN AS HOTEN, @NHOM AS NHOM, @MACN AS MACN;
END
GO
GRANT EXECUTE ON dbo.sp_Login_App TO NganHang;
GRANT EXECUTE ON dbo.sp_Login_App TO ChiNhanh;
GRANT EXECUTE ON dbo.sp_Login_App TO KhachHang;  -- bắt buộc — KH cũng cần đăng nhập
```

---

## 2. `SP_TaoTaiKhoan` — Tạo Login+User+Role

**Deploy:** Article của cả 3 Publication.
**Gọi bởi:** `routes/quantri.js` — chỉ dùng ở tầng ứng dụng để tạo login cho user mới. **Route tự fan‑out gọi trên cả 4 instance** (Login không được Replication đồng bộ).
**Cơ chế bảo mật:** `QUOTENAME` bọc tên + `REPLACE` escape ký tự `'` trong password để chống SQL injection. Idempotent — chạy lại không lỗi (`IF NOT EXISTS` trước mỗi bước).

```sql
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

        -- 1) CREATE LOGIN
        IF NOT EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
        BEGIN
            SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME)
                       + ' WITH PASSWORD = ''' + @PassEscaped + ''''
                       + ', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
            EXEC(@SqlStr);
        END

        -- 2) CREATE USER
        IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
        BEGIN
            SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME)
                       + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
            EXEC(@SqlStr);
        END

        -- 3) ADD ROLE
        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE,'''','''''')
                    + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

        -- 4) Log vào QuanTriLogin
        IF NOT EXISTS(SELECT 1 FROM dbo.QuanTriLogin WHERE LoginName = @LGNAME)
        BEGIN
            INSERT INTO dbo.QuanTriLogin(LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
            VALUES(@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());
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
```

---

## 3. `SP_ResetMatKhau` — Đổi mật khẩu

**Deploy:** thủ công qua `setup_db.js` trên cả 4 instance.
**Gọi bởi:** `routes/quantri.js` — chỉ role `NganHang` được phép qua middleware.
**Điểm đặc biệt — `WITH EXECUTE AS OWNER`:** SP chạy dưới ngữ cảnh của owner (thường là `dbo`) → có quyền `ALTER LOGIN` mà không cần cấp `securityadmin` cho user gọi.

```sql
CREATE OR ALTER PROCEDURE [dbo].[SP_ResetMatKhau]
    @LoginName   VARCHAR(50),
    @MATKHAU_MOI VARCHAR(50) = '123456'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LoginName)
    BEGIN
        RAISERROR(N'Tài khoản đăng nhập không tồn tại.', 16, 1); RETURN 1;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@MATKHAU_MOI, '''', '''''');
        SET @SqlStr = 'ALTER LOGIN ' + QUOTENAME(@LoginName)
                   + ' WITH PASSWORD = ''' + @PassEscaped + ''';';
        EXEC(@SqlStr);

        UPDATE dbo.QuanTriLogin
        SET MatKhauHienTai = @MATKHAU_MOI, NgayCapNhatMK = GETDATE()
        WHERE LoginName = @LoginName;

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1); RETURN 2;
    END CATCH
END
GO
```

---

## 4. `sp_ThemKhachHang`

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH (không có ở TRACUU).
**Gọi bởi:** `routes/khachhang.js:POST /them` — chỉ chạy trên site chi nhánh của NV thực hiện. `KhachHang` phân mảnh theo `MACN` → INSERT tại local là đúng site chủ sở hữu.

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_ThemKhachHang]
    @CMND    nchar(10),
    @HO      nvarchar(40),
    @TEN     nvarchar(10),
    @DIACHI  nvarchar(100),
    @PHAI    nvarchar(3),
    @NGAYCAP date,
    @SODT    nvarchar(15),
    @MACN    nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng đã tồn tại.', 16, 1); RETURN;
    END
    BEGIN TRY
        INSERT INTO KhachHang(CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT, MACN)
        VALUES(@CMND, @HO, @TEN, @DIACHI, @PHAI, @NGAYCAP, @SODT, @MACN);
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
```

Sau khi SP thành công, route tự fan‑out **CREATE LOGIN + CREATE USER + ADD ROLE 'KhachHang'** trên cả 4 instance (Login không được Replication đồng bộ).

---

## 5. `sp_LietKeKhachHang`

**Deploy:** Article của cả 3 Publication → có trên mọi site (kể cả TRACUU vì KhachHang cũng replicate full sang TRACUU).
**Gọi bởi:** `routes/baocao.js` — dùng cho báo cáo B3.
**Cơ chế:** Chỉ đọc bảng `KhachHang` local. `WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))` — NULL = lấy tất cả. `ORDER BY MACN, HO, TEN` đúng yêu cầu đề bài.

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeKhachHang]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT HO, TEN, CMND, MACN, SODT
    FROM KhachHang
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
GO
```

---

## 6. `SP_SaoKeTaiKhoan` — bản chi nhánh

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH (có bản riêng cho TRACUU — xem §13).
**Gọi bởi:** `routes/baocao.js:POST /saoke` — cho ChiNhanh, KhachHang. **NganHang cũng gọi bản này** nhưng route tạm mượn `spServer='BENTHANH'` (vì TRACUU không có `TaiKhoan` local).
**Kỹ thuật tối ưu:**
1. **Tính lùi số dư đầu kỳ:** `SODU_DAUKY = SODU_HIENTAI - SUM(biến động sau @TUNGAY)`. Không cần kéo toàn bộ lịch sử qua Linked Server.
2. **Window Function tính lũy kế:** `SUM(...) OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` — 1 lần scan.
3. **Defense in depth cho role `KhachHang`** *(fix #8)*: dùng `IS_ROLEMEMBER('KhachHang')` + `SUSER_SNAME()` để **chặn KH truy vấn SOTK không thuộc CMND của mình**, kể cả khi KH đăng nhập SSMS chạy trực tiếp SP (không đi qua route Node). Route `baocao.js` cũng có pre‑check nhưng lớp SQL là lớp cuối cùng chống bypass ứng dụng.

```sql
CREATE OR ALTER PROCEDURE SP_SaoKeTaiKhoan
    @SOTK    NVARCHAR(50),
    @TUNGAY  DATETIME,
    @DENNGAY DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    -- Số dư hiện tại (đọc local — TaiKhoan nhân bản full)
    DECLARE @SODU_HIENTAI MONEY;
    DECLARE @CMND_TK nchar(10);
    SELECT @SODU_HIENTAI = SODU, @CMND_TK = CMND FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK);
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1); RETURN;
    END

    -- Defense in depth: KH chỉ được sao kê TK thuộc chính mình (fix #8)
    -- SUSER_SNAME() = SQL login name; với role KhachHang, login = CMND
    IF IS_ROLEMEMBER('KhachHang') = 1
    BEGIN
        IF RTRIM(@CMND_TK) <> RTRIM(SUSER_SNAME())
        BEGIN
            RAISERROR(N'Bạn không có quyền xem sao kê tài khoản này.', 16, 1); RETURN;
        END
    END

    -- Tính lùi số dư đầu kỳ: trừ ngược tổng biến động sau @TUNGAY (Local + LINK1)
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;
    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE
            WHEN LOAIGD IN ('GT','NT') THEN SOTIEN
            WHEN LOAIGD IN ('RT','CT') THEN -SOTIEN ELSE 0
        END), 0)
    FROM (
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' FROM GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' FROM GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- Chi tiết GD trong kỳ + số dư lũy kế qua Window Function
    ;WITH TransactionsInPeriod AS (
        SELECT NGAYGD, SOTIEN, LOAIGD FROM GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' FROM GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' FROM GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    RunningBalance AS (
        SELECT NGAYGD, LOAIGD, SOTIEN,
               SODU_LUYKE = @SODU_DAUKY + SUM(
                   CASE
                       WHEN LOAIGD IN ('GT','NT') THEN SOTIEN
                       WHEN LOAIGD IN ('RT','CT') THEN -SOTIEN ELSE 0
                   END) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    SELECT * FROM RunningBalance ORDER BY NGAYGD ASC;
END
GO
GRANT EXECUTE ON SP_SaoKeTaiKhoan TO KhachHang;
```

**Ví dụ số:** `SODU_HIENTAI=10tr`, biến động sau `@TUNGAY = 2tr` (net +2tr) → `SODU_DAUKY = 8tr`. Với 5 dòng GD trong kỳ, Window Function tự cộng dồn để ra `SODU_LUYKE` từng dòng — hình dung như phép cộng bậc thang.

---

## 7. `sp_ChuyenTien` — Chuyển tiền liên chi nhánh ⭐

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH.
**Gọi bởi:** `routes/giaodich.js:POST /chuyentien` **qua `execSPAdmin`** (sqlcmd) vì có thể dùng DTC.
**Điểm cốt lõi (rất hay hỏi vấn đáp):**
- **Đọc local** để kiểm tra TK và lấy `MACN` (TaiKhoan nhân bản full → không cần LINK1).
- **So sánh MACN** (không dùng EXISTS trên LINK1) để quyết định UPDATE local hay qua LINK1.
- **Atomic check số dư:** `UPDATE ... WHERE SODU >= @SOTIEN` + kiểm tra `@@ROWCOUNT` — không race condition.
- **GD_CHUYENTIEN ghi tại local** (đúng mảnh — theo NV thực hiện).
- **Chặn tự chuyển cho chính mình** *(fix #9)*: `IF RTRIM(@SOTK_CHUYEN) = RTRIM(@SOTK_NHAN)` → RAISERROR trước khi bắt đầu transaction.
- **Rẽ nhánh transaction theo scope** *(fix #6)*: TK nhận **cùng chi nhánh** với TK chuyển → dùng `BEGIN TRANSACTION` (local, không MSDTC); TK nhận **khác chi nhánh** → mới dùng `BEGIN DISTRIBUTED TRANSACTION`. Giảm chi phí MSDTC cho các giao dịch cùng chi nhánh (chiếm >70% workload thực tế).

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),
    @SOTK_NHAN   nchar(9),
    @SOTIEN      money,
    @MANV        nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;              -- Bắt buộc cho DTC

    IF @SOTIEN <= 0
    BEGIN RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1); RETURN; END

    -- Chặn tự chuyển cho chính mình (fix #9)
    IF RTRIM(@SOTK_CHUYEN) = RTRIM(@SOTK_NHAN)
    BEGIN RAISERROR(N'Không thể chuyển tiền cho chính tài khoản này.',16,1); RETURN; END

    -- Lấy MACN của TK chuyển (đọc local — nhân bản full)
    DECLARE @MACN_CHUYEN nchar(10);
    SELECT @MACN_CHUYEN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
    IF @MACN_CHUYEN IS NULL
    BEGIN RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1); RETURN; END

    -- Lấy MACN của TK nhận (đọc local — nhân bản full)
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
    IF @MACN_NHAN IS NULL
    BEGIN RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1); RETURN; END

    DECLARE @IsNhanLocal bit = 0;
    IF @MACN_NHAN = @MACN_CHUYEN SET @IsNhanLocal = 1;

    BEGIN TRY
        -- Fix #6: local tran nếu cùng CN (không cần MSDTC), DTC nếu khác CN
        IF @IsNhanLocal = 1
            BEGIN TRANSACTION;
        ELSE
            BEGIN DISTRIBUTED TRANSACTION;

        -- Trừ tiền TK chuyển (local — site sở hữu)
        UPDATE TaiKhoan
        SET SODU = SODU - @SOTIEN
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN)
          AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1); RETURN;
        END

        -- Cộng tiền TK nhận: local hoặc qua LINK1 (site đối tác)
        IF @IsNhanLocal = 1
            UPDATE TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        ELSE
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan
            SET SODU = SODU + @SOTIEN
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);

        -- Log GD tại local (đúng mảnh theo NV)
        INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
```

**Flow khi NV BT001 chuyển 500k từ TK BT sang TK TD:**
```
1. SP chạy trên SQL1 (BENTHANH)
2. Đọc MACN_CHUYEN='BENTHANH' (local, TaiKhoan replicate full)
3. Đọc MACN_NHAN  ='TANDINH'  (local, TaiKhoan replicate full)
4. @IsNhanLocal = 0 (khác CN)
5. BEGIN DISTRIBUTED TRAN
6.   UPDATE local: TK BT trừ 500k (WHERE SODU >= 500k → atomic)
7.   UPDATE qua [LINK1] (LINK1 SQL1 = SQL2): TK TD cộng 500k
8.   INSERT log vào GD_CHUYENTIEN local (SQL1)
9. COMMIT → MSDTC 2PC ký kết cả 2 site
```

---

## 8. `sp_GuiTien` / `sp_RutTien` — Gửi / Rút tiền

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH.
**Gọi bởi:** `routes/giaodich.js:POST /goitien` và `/ruttien` **qua `execSPAdmin`** (có thể dùng DTC).
**Điểm chung:**
- Đọc MACN TK và MACN NV để xác định `@IsLocal` (TK và NV cùng CN?).
- **Rẽ nhánh transaction** *(fix #6)*: `@IsLocal = 1` → `BEGIN TRANSACTION` (local); `@IsLocal = 0` → `BEGIN DISTRIBUTED TRANSACTION` (UPDATE qua LINK1). Chỉ dùng MSDTC khi thực sự cần.
- GD_GOIRUT luôn ghi local (phân mảnh theo NV thực hiện).
- Kiểm tra `SOTIEN >= 100_000` (yêu cầu đề bài A4).

**`sp_RutTien` có thêm** kiểm tra số dư atomic: `WHERE SODU >= @SOTIEN` + `@@ROWCOUNT = 0` → ROLLBACK.

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_GuiTien]
    @SOTK nchar(9), @SOTIEN money, @MANV nchar(10)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @SOTIEN < 100000
    BEGIN RAISERROR(N'Số tiền gửi tối thiểu là 100,000 VND.', 16, 1); RETURN; END

    DECLARE @MACN_TK nchar(10);
    SELECT @MACN_TK = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK);
    IF @MACN_TK IS NULL
    BEGIN RAISERROR(N'Tài khoản không tồn tại.', 16, 1); RETURN; END

    DECLARE @MACN_NV nchar(10);
    SELECT @MACN_NV = RTRIM(MACN) FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);

    DECLARE @IsLocal bit = 0;
    IF @MACN_TK = @MACN_NV SET @IsLocal = 1;

    BEGIN TRY
        IF @IsLocal = 1
        BEGIN
            -- Fix #6: nhánh cùng CN — local tran, không MSDTC
            BEGIN TRANSACTION;
            UPDATE TaiKhoan SET SODU = SODU + @SOTIEN
             WHERE RTRIM(SOTK) = RTRIM(@SOTK);
        END
        ELSE
        BEGIN
            -- Nhánh khác CN — DTC 2PC (UPDATE qua LINK1)
            BEGIN DISTRIBUTED TRANSACTION;
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU = SODU + @SOTIEN
             WHERE RTRIM(SOTK) = RTRIM(@SOTK);
        END

        INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
        VALUES(@SOTK, 'GT', GETDATE(), @SOTIEN, @MANV);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_RutTien]
    @SOTK nchar(9), @SOTIEN money, @MANV nchar(10)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @SOTIEN < 100000
    BEGIN RAISERROR(N'Số tiền rút tối thiểu là 100,000 VND.', 16, 1); RETURN; END

    DECLARE @MACN_TK nchar(10);
    SELECT @MACN_TK = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK);
    IF @MACN_TK IS NULL
    BEGIN RAISERROR(N'Tài khoản không tồn tại.', 16, 1); RETURN; END

    DECLARE @MACN_NV nchar(10);
    SELECT @MACN_NV = RTRIM(MACN) FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);

    DECLARE @IsLocal bit = 0;
    IF @MACN_TK = @MACN_NV SET @IsLocal = 1;

    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;
        IF @IsLocal = 1
            UPDATE TaiKhoan SET SODU = SODU - @SOTIEN
             WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND SODU >= @SOTIEN;
        ELSE
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU = SODU - @SOTIEN
             WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Số dư không đủ để rút.', 16, 1); RETURN;
        END

        INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
        VALUES(@SOTK, 'RT', GETDATE(), @SOTIEN, @MANV);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

---

## 9. `sp_MoTaiKhoan` — Mở tài khoản

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH.
**Gọi bởi:** `routes/taikhoan.js:POST /mo` **luôn qua `execSPAdmin`** (dùng DTC).

**Đặc biệt 1 — Tách LINK1 query khỏi DTC scope:**
> Bảng `TaiKhoan` có Merge Replication trigger `MSmerge_ins_*`. Nếu trong cùng scope có cả `SELECT [LINK1]...` và `INSERT TaiKhoan`, SQL Server tạo **implicit distributed transaction**. Merge trigger cố enlist vào implicit DT này → conflict → session bị kill với lỗi *"session is in the kill state"*.
>
> **Giải pháp:** Check KH (local + LINK1) TRƯỚC, lưu vào biến `@KHFound`. INSERT nằm trong `BEGIN DISTRIBUTED TRANSACTION` riêng — scope chỉ chứa INSERT, không có LINK1 query. Pattern này nhất quán với `sp_GuiTien`/`sp_RutTien`/`sp_ChuyenTien`.

**Đặc biệt 2 — Sinh SOTK atomic trong SP** *(fix #3)*:
> **Vấn đề cũ:** SOTK sinh ở tầng app (`sinhSOTK()` trong `routes/taikhoan.js`) bằng `MAX(SOTK) + 1` → race condition khi 2 nhân viên cùng lúc mở TK. Cả 2 đọc cùng `MAX = 8`, cùng gán `SOTK = BT0000009`, cùng INSERT → 1 người thành công, 1 người dính PK violation.
>
> **Giải pháp:** Move logic sinh SOTK vào SP. SP dùng vòng WHILE retry tối đa 5 lần: mỗi lần đọc `MAX(SOTK) + 1 + @Attempt` rồi INSERT trong DTC; nếu error `2627/2601` (PK duplicate) → ROLLBACK, tăng `@Attempt`, thử SOTK mới. Prefix `BT`/`TD` lấy theo `@MACN` (chi nhánh sở hữu TK), không phụ thuộc server chạy SP → cross-branch scenario cũng đúng.

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_MoTaiKhoan]
    @CMND nchar(10), @SODU money, @MACN nchar(10)   -- BỎ @SOTK (SP tự sinh)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    -- BƯỚC 1: Check KH TRƯỚC distributed tran (tách khỏi INSERT scope)
    DECLARE @KHFound bit = 0;
    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
        SET @KHFound = 1;
    ELSE IF EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
        SET @KHFound = 1;
    IF @KHFound = 0
    BEGIN RAISERROR(N'Khach hang khong ton tai tren he thong.',16,1); RETURN; END

    -- BƯỚC 2: Prefix theo @MACN của TK, không theo server chạy SP
    DECLARE @Prefix nchar(2);
    SET @Prefix = CASE RTRIM(@MACN) WHEN 'BENTHANH' THEN 'BT' WHEN 'TANDINH' THEN 'TD' ELSE NULL END;
    IF @Prefix IS NULL
    BEGIN RAISERROR(N'MACN khong hop le.', 16, 1); RETURN; END

    -- BƯỚC 3: Vòng retry sinh SOTK atomic (fix #3)
    DECLARE @Attempt int = 0, @MaxAttempt int = 5;
    DECLARE @SOTK nchar(9), @Max nchar(9), @Num int;

    WHILE @Attempt < @MaxAttempt
    BEGIN
        SET @Max = NULL;
        SELECT TOP 1 @Max = SOTK FROM TaiKhoan
         WHERE SOTK LIKE @Prefix + '%' ORDER BY SOTK DESC;

        SET @Num = ISNULL(CAST(SUBSTRING(RTRIM(@Max), 3, 7) AS INT), 0) + 1 + @Attempt;
        SET @SOTK = @Prefix + RIGHT('0000000' + CAST(@Num AS VARCHAR(7)), 7);

        BEGIN TRY
            BEGIN DISTRIBUTED TRANSACTION;
            INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK)
            VALUES(@SOTK, @CMND, @SODU, @MACN, GETDATE());
            COMMIT TRANSACTION;

            SELECT @SOTK AS SOTK;   -- Trả SOTK mới về app để hiển thị
            RETURN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            IF ERROR_NUMBER() IN (2627, 2601)
                SET @Attempt = @Attempt + 1;    -- PK dup → thử SOTK khác
            ELSE
            BEGIN
                DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
                RAISERROR(@ErrMsg, 16, 1); RETURN;
            END
        END CATCH
    END

    RAISERROR(N'He thong ban, thu lai sau.', 16, 1);
END
GO
```

**Route parse SOTK trả về:** `execSPAdmin` chạy SP qua sqlcmd → output text. Route dùng regex `/\b(?:BT|TD)\d{7}\b/` bắt SOTK trong stdout.

**Cross‑branch scenario:** NV BENTHANH mở TK cho KH TANDINH → route chạy SP trên SQL2 (server có KH TANDINH local) với `@MACN='TANDINH'` → SOTK sinh ra có prefix `TD` (đúng chi nhánh sở hữu, không phụ thuộc server chạy SP).

---

## 10. `sp_ChuyenNhanVien` — Chuyển nhân viên liên chi nhánh ⭐

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH.
**Gọi bởi:** `routes/nhanvien.js:POST /chuyen` **qua `execSPAdmin`** (dùng DTC).
**Điểm cốt lõi:**
- **Sinh MANV mới** với prefix chi nhánh đích (`BT###` hoặc `TD###`) — query MANV lớn nhất qua LINK1, +1.
- **Race condition check:** vòng `WHILE EXISTS` tăng số thứ tự nếu MANV mới bị trùng.
- **Distributed Transaction:** UPDATE `TrangThaiXoa=1` local + INSERT qua LINK1 với MANV mới + MACN mới + TrangThaiXoa=0.
- **Resurrect logic** *(fix RF‑A)*: `UQ_NhanVien_CMND` không phân biệt `TrangThaiXoa` → nếu chi nhánh đích đã có bản ghi cùng CMND đang **soft-delete** (do đã chuyển đi trước đó) thì INSERT sẽ vi phạm UNIQUE. Giải pháp: query LINK1 tìm bản ghi cùng CMND — nếu có + `TrangThaiXoa=1` → **UPDATE ngược** (`TrangThaiXoa=0`, giữ nguyên MANV cũ, giữ nguyên thông tin cũ), giữ liên tục lịch sử GD. Nếu có + `TrangThaiXoa=0` → RAISERROR (dữ liệu sai — không được active ở 2 chi nhánh đồng thời). Nếu không có bản nào → sinh MANV mới + INSERT như cũ. SP trả cột `IsResurrect bit` để app biết kịch bản nào đã xảy ra.

```sql
CREATE OR ALTER PROCEDURE SP_ChuyenNhanVien
    @MANV NVARCHAR(10), @MACN_MOI NVARCHAR(10)
AS
BEGIN
    SET XACT_ABORT ON; SET NOCOUNT ON;

    -- 1) Check NV tồn tại và đang làm việc
    DECLARE @MACN_HIENTAI NVARCHAR(10), @TRANGTHAIXOA BIT;
    SELECT @MACN_HIENTAI = RTRIM(MACN), @TRANGTHAIXOA = TrangThaiXoa
    FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);
    IF @MACN_HIENTAI IS NULL
    BEGIN RAISERROR(N'Nhân viên không tồn tại ở chi nhánh này.', 16, 1); RETURN; END
    IF @TRANGTHAIXOA = 1
    BEGIN RAISERROR(N'Nhân viên này đã bị xóa hoặc đã chuyển công tác trước đó.', 16, 1); RETURN; END
    IF @MACN_HIENTAI = @MACN_MOI
    BEGIN RAISERROR(N'Chi nhánh mới phải khác chi nhánh hiện tại.', 16, 1); RETURN; END

    -- 2) Lấy CMND để check tại đích qua LINK1 (RF-A)
    DECLARE @CMND NCHAR(10);
    SELECT @CMND = CMND FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);

    DECLARE @EXIST_MANV NVARCHAR(10) = NULL, @EXIST_TRANGTHAI BIT = NULL;
    SELECT @EXIST_MANV = RTRIM(MANV), @EXIST_TRANGTHAI = TrangThaiXoa
    FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(CMND) = RTRIM(@CMND);

    IF @EXIST_MANV IS NOT NULL AND @EXIST_TRANGTHAI = 0
    BEGIN RAISERROR(N'NV cùng CMND đang làm việc tại chi nhánh đích.', 16, 1); RETURN; END

    -- 3) Xác định nhánh RESURRECT hay INSERT_NEW
    DECLARE @IsResurrect BIT = 0, @MANV_MOI NVARCHAR(10);
    IF @EXIST_MANV IS NOT NULL AND @EXIST_TRANGTHAI = 1
    BEGIN
        SET @IsResurrect = 1;
        SET @MANV_MOI    = @EXIST_MANV;   -- Giữ MANV cũ
    END
    ELSE
    BEGIN
        DECLARE @PREFIX NVARCHAR(2), @LAST_MANV NVARCHAR(10), @NEXT_NUM INT;
        SET @PREFIX = CASE @MACN_MOI WHEN 'BENTHANH' THEN 'BT' ELSE 'TD' END;

        SELECT TOP 1 @LAST_MANV = RTRIM(MANV)
        FROM [LINK1].NGANHANG.dbo.NhanVien
        WHERE RTRIM(MANV) LIKE @PREFIX + '%'
        ORDER BY MANV DESC;

        SET @NEXT_NUM = ISNULL(CAST(SUBSTRING(@LAST_MANV, LEN(@PREFIX)+1, 10) AS INT), 0) + 1;
        SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);

        WHILE EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(MANV) = @MANV_MOI)
        BEGIN
            SET @NEXT_NUM = @NEXT_NUM + 1;
            SET @MANV_MOI = @PREFIX + RIGHT('000' + CAST(@NEXT_NUM AS NVARCHAR(5)), 3);
        END
    END

    -- 4) Distributed Transaction: soft-delete source + resurrect/insert target
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;
        UPDATE NhanVien SET TrangThaiXoa = 1 WHERE RTRIM(MANV) = RTRIM(@MANV);

        IF @IsResurrect = 1
            UPDATE [LINK1].NGANHANG.dbo.NhanVien
            SET TrangThaiXoa = 0
            WHERE RTRIM(MANV) = @MANV_MOI;
        ELSE
            INSERT INTO [LINK1].NGANHANG.dbo.NhanVien
                   (MANV, CMND, HO, TEN, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
            SELECT @MANV_MOI, CMND, HO, TEN, DIACHI, PHAI, SODT, @MACN_MOI, 0
            FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);

        COMMIT TRAN;

        SELECT @MANV_MOI AS MANV_MOI, @MACN_MOI AS MACN_MOI, @IsResurrect AS IsResurrect;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, ERROR_SEVERITY(), ERROR_STATE());
    END CATCH
END
GO
```

---

## 11. `sp_PhucHoiNhanVien` — Phục hồi NV đã chuyển

**Deploy:** Article của PUB_BENTHANH + PUB_TANDINH.
**Gọi bởi:** `routes/nhanvien.js:POST /phuchoi` **qua `execSPAdmin`** (dùng DTC).
**Cơ chế:** Khi NV được chuyển BT→TD, bản BT có `TrangThaiXoa=1`, bản TD (MANV mới) active. Nếu muốn phục hồi bản cũ → phải deactivate bản đang active bên kia (cùng CMND). Nếu không → 2 bản ghi cùng người đều active = inconsistency.

```sql
CREATE OR ALTER PROCEDURE SP_PhucHoiNhanVien
    @MANV NVARCHAR(10)
AS
BEGIN
    SET XACT_ABORT ON; SET NOCOUNT ON;

    -- 1) Check NV local tồn tại và đang ở trạng thái xóa
    DECLARE @CMND NVARCHAR(20), @TRANGTHAIXOA BIT;
    SELECT @CMND = RTRIM(CMND), @TRANGTHAIXOA = TrangThaiXoa
    FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);
    IF @CMND IS NULL
    BEGIN RAISERROR(N'Nhân viên không tồn tại ở chi nhánh này.', 16, 1); RETURN; END
    IF @TRANGTHAIXOA = 0
    BEGIN RAISERROR(N'Nhân viên này đang hoạt động, không cần phục hồi.', 16, 1); RETURN; END

    -- 2) Tìm bản active cùng CMND bên kia (qua LINK1)
    DECLARE @MANV_BEN_KIA NVARCHAR(10);
    SELECT TOP 1 @MANV_BEN_KIA = RTRIM(MANV)
    FROM [LINK1].NGANHANG.dbo.NhanVien
    WHERE RTRIM(CMND) = @CMND AND TrangThaiXoa = 0;

    -- 3) Distributed Transaction
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;
        UPDATE NhanVien SET TrangThaiXoa = 0 WHERE RTRIM(MANV) = RTRIM(@MANV);
        IF @MANV_BEN_KIA IS NOT NULL
            UPDATE [LINK1].NGANHANG.dbo.NhanVien SET TrangThaiXoa = 1
             WHERE RTRIM(MANV) = @MANV_BEN_KIA;
        COMMIT TRAN;

        SELECT @MANV AS MANV_PHUCHOI, @MANV_BEN_KIA AS MANV_DEACTIVATED;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, ERROR_SEVERITY(), ERROR_STATE());
    END CATCH
END
GO
```

---

## 12. `sp_TaiKhoanKhachHang` — KH xem TK của mình

**Deploy:** Deploy thủ công qua `setup_db.js` trên cả 4 instance.
**Gọi bởi:** `routes/taikhoan.js` (GET `/`) và `routes/baocao.js` (POST `/saoke`) khi user là KhachHang.
**Vai trò bảo mật:** Là **cửa ngõ duy nhất** cho role `KhachHang` — role này không có `SELECT` trực tiếp trên bảng nào. SP tự lọc theo `@CMND` → KH không thể xem TK của người khác kể cả khi kết nối trực tiếp SSMS.

```sql
CREATE OR ALTER PROCEDURE sp_TaiKhoanKhachHang
    @CMND nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK,
           RTRIM(tk.CMND) AS CMND,
           tk.SODU,
           RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM TaiKhoan tk
    WHERE RTRIM(tk.CMND) = RTRIM(@CMND)
    ORDER BY tk.NGAYMOTK DESC;
END
GO
GRANT EXECUTE ON sp_TaiKhoanKhachHang TO KhachHang;
```

---

## 12b. `SP_DongTaiKhoan` — Đóng tài khoản (defense in depth)

**Deploy:** thủ công trên SQL1 + SQL2 qua `sql/stored_procedures/23_SP_DongTaiKhoan.sql` (đã thêm vào `run_all.bat`).
**Gọi bởi:** `routes/taikhoan.js:POST /dong` **qua `execSPAdmin`** (SP query LINK1).

**Lý do sinh ra** *(fix RF‑B)*: Trước đây tầng route Node.js đảm nhận check số dư + kiểm giao dịch rồi mới `DELETE FROM TaiKhoan`. Nếu ai đó bypass ứng dụng (SSMS trực tiếp, SP khác), guard biến mất → xóa TK bừa bãi → mất consistency. Chuyển logic guard xuống SP để **defense in depth** — dù truy cập từ đâu, quy tắc nghiệp vụ vẫn được ép ở tầng SQL.

**Guard 5 lớp trong SP:**
1. **G1** — TK tồn tại (đọc local, TaiKhoan replicate full).
2. **G2** — `SODU = 0`.
3. **G3** — TK cùng CN với NV (`MACN_TK = MACN_NV`) — **chỉ cho đóng cùng CN**, không cross-branch. Cross-branch closing dễ gây nhầm lẫn, không có nhu cầu nghiệp vụ.
4. **G4** — Không có GD_GOIRUT (đếm cả LOCAL + LINK1, vì GD_GOIRUT phân mảnh theo NV, có thể tồn tại ở CN khác).
5. **G5** — Không có GD_CHUYENTIEN (LOCAL + LINK1).

Sau khi 5 guard đều pass → `DELETE FROM TaiKhoan` trong `BEGIN TRANSACTION` local. Không cần DTC — Merge Replication sẽ propagate DELETE sang site kia.

```sql
CREATE OR ALTER PROCEDURE [dbo].[SP_DongTaiKhoan]
    @SOTK NCHAR(9), @MANV NCHAR(10)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    -- G1 + G2: TK tồn tại + SODU=0
    DECLARE @MACN_TK NCHAR(10), @SODU MONEY;
    SELECT @MACN_TK = RTRIM(MACN), @SODU = SODU FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK);
    IF @MACN_TK IS NULL
    BEGIN RAISERROR(N'Tài khoản không tồn tại.', 16, 1); RETURN; END
    IF @SODU <> 0
    BEGIN RAISERROR(N'Không thể đóng tài khoản có số dư khác 0.', 16, 1); RETURN; END

    -- G3: cùng CN với NV
    DECLARE @MACN_NV NCHAR(10);
    SELECT @MACN_NV = RTRIM(MACN) FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);
    IF @MACN_NV IS NULL
    BEGIN RAISERROR(N'Nhân viên không tồn tại tại chi nhánh này.', 16, 1); RETURN; END
    IF @MACN_TK <> @MACN_NV
    BEGIN RAISERROR(N'Chỉ nhân viên tại chi nhánh sở hữu tài khoản mới có quyền đóng.', 16, 1); RETURN; END

    -- G4: không có GD_GOIRUT (local + LINK1)
    DECLARE @GD_LOCAL INT, @GD_REMOTE INT;
    SELECT @GD_LOCAL  = COUNT(*) FROM GD_GOIRUT WHERE RTRIM(SOTK) = RTRIM(@SOTK);
    SELECT @GD_REMOTE = COUNT(*) FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE RTRIM(SOTK) = RTRIM(@SOTK);
    IF (@GD_LOCAL + @GD_REMOTE) > 0
    BEGIN RAISERROR(N'Không thể đóng tài khoản đã có giao dịch gửi/rút.', 16, 1); RETURN; END

    -- G5: không có GD_CHUYENTIEN (local + LINK1)
    DECLARE @CT_LOCAL INT, @CT_REMOTE INT;
    SELECT @CT_LOCAL = COUNT(*) FROM GD_CHUYENTIEN
     WHERE RTRIM(SOTK_CHUYEN) = RTRIM(@SOTK) OR RTRIM(SOTK_NHAN) = RTRIM(@SOTK);
    SELECT @CT_REMOTE = COUNT(*) FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
     WHERE RTRIM(SOTK_CHUYEN) = RTRIM(@SOTK) OR RTRIM(SOTK_NHAN) = RTRIM(@SOTK);
    IF (@CT_LOCAL + @CT_REMOTE) > 0
    BEGIN RAISERROR(N'Không thể đóng tài khoản đã có giao dịch chuyển tiền.', 16, 1); RETURN; END

    -- DELETE local tran (merge replication tự sync)
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK);
        COMMIT TRANSACTION;
        SELECT @SOTK AS SOTK_DA_DONG;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
GRANT EXECUTE ON [dbo].[SP_DongTaiKhoan] TO NganHang;
```

**Route** giờ chỉ còn 4 dòng:
```js
router.post('/dong', async (req, res) => {
  const { SOTK } = req.body;
  try {
    await execSPAdmin(server, 'SP_DongTaiKhoan', { SOTK, MANV: user.MANV });
    res.redirect('/taikhoan?success=Đã đóng tài khoản ' + SOTK);
  } catch (err) {
    res.redirect('/taikhoan?error=' + encodeURIComponent(err.message));
  }
});
```

---

## 13. SP đặc thù TRACUU (SQL3)

TRACUU chỉ replicate `KhachHang`. Không có local: `NhanVien`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN`, `ChiNhanh`. Các SP dưới đây đọc qua Linked Server.

**Deploy:** thủ công qua [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql). **Không đưa vào Article** — nếu đưa vào Article Replication sẽ đẩy xuống SQL1/SQL2, gây xung đột (SP tham chiếu [LINK1]/[LINK2] không tồn tại ở đó).

### 13.1. `sp_DanhSachTaiKhoan`
> **Đọc chỉ LINK1 (không UNION ALL LINK1+LINK2)** — vì `TaiKhoan` nhân bản toàn vẹn, LINK1 (BENTHANH) đã có đủ TK cả 2 chi nhánh; UNION thêm LINK2 sẽ ra x2. JOIN `KhachHang` local bằng `OUTER APPLY TOP 1` tránh nhân bản khi 1 CMND có nhiều KH.

```sql
CREATE OR ALTER PROCEDURE sp_DanhSachTaiKhoan
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK,
           RTRIM(tk.CMND) AS CMND,
           tk.SODU,
           RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (
        SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND) = RTRIM(tk.CMND)
    ) kh
    ORDER BY tk.NGAYMOTK DESC;
END
GO
GRANT EXECUTE ON sp_DanhSachTaiKhoan TO NganHang;
GRANT EXECUTE ON sp_DanhSachTaiKhoan TO ChiNhanh;
```

### 13.2. `sp_LietKeTaiKhoanTheoNgay` — bản TRACUU

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL, @TUNGAY date = NULL, @DENNGAY date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (
        SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND) = RTRIM(tk.CMND)
    ) kh
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
GO
GRANT EXECUTE ON sp_LietKeTaiKhoanTheoNgay TO NganHang;
GRANT EXECUTE ON sp_LietKeTaiKhoanTheoNgay TO ChiNhanh;
```

### 13.3. `sp_DanhSachNhanVien` — bản TRACUU
> `NhanVien` phân mảnh ngang → **BẮT BUỘC** UNION ALL LINK1 + LINK2 để tái tạo quan hệ toàn cục (đúng tính chất Reconstruction).

```sql
CREATE OR ALTER PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(MANV) AS MANV, RTRIM(HO) AS HO, RTRIM(TEN) AS TEN,
           RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
           RTRIM(CMND) AS CMND, RTRIM(MACN) AS MACN, SODT, DIACHI, TrangThaiXoa
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
GO
```

### 13.4. `sp_SaoKeToanBo` — bản TRACUU (báo cáo tổng hợp toàn hệ thống)

```sql
CREATE OR ALTER PROCEDURE sp_SaoKeToanBo
    @TUNGAY datetime, @DENNGAY datetime
AS
BEGIN
    SET NOCOUNT ON;
    -- Gộp GD gửi/rút từ cả 2 CN
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY

    -- Gộp GD chuyển tiền — mỗi GD chia 2 dòng (CT bên chuyển, NT bên nhận)
    UNION ALL
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ORDER BY NGAYGD;
END
GO
```

### 13.5. `SP_DanhSachTrangThaiLogin` — bản TRACUU

```sql
CREATE OR ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- NhanVien: gộp LINK1+LINK2
    SELECT 'NhanVien' AS LoaiTK, nv.MANV AS MaThamChieu,
           RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
           RTRIM(nv.MACN) AS MACN,
           CASE
               WHEN ql.LoginName IS NULL THEN 0
               WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
               ELSE 2
           END AS DaCapTaiKhoan,
           ql.LoginName, ql.NhomQuyen, ql.NgayTao, ql.NgayCapNhatMK
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS nv
    LEFT JOIN dbo.QuanTriLogin ql
        ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV)
       AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

    UNION ALL

    -- KhachHang: local (replicate full trên TRACUU)
    SELECT 'KhachHang' AS LoaiTK, kh.CMND AS MaThamChieu,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           RTRIM(kh.MACN) AS MACN,
           CASE
               WHEN ql.LoginName IS NULL THEN 0
               WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
               ELSE 2
           END AS DaCapTaiKhoan,
           ql.LoginName, ql.NhomQuyen, ql.NgayTao, ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql
        ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND)
       AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
GO
```

`DaCapTaiKhoan` diễn giải:
- `0` = chưa có record trong `QuanTriLogin` (NV/KH chưa được cấp Login)
- `1` = có record, và Login vẫn active (`sys.server_principals`)
- `2` = có record nhưng Login đã bị xóa/disable trên server (lỗi đồng bộ)

### 13.6. `SP_SaoKeTaiKhoan` — bản TRACUU
Cùng thuật toán "tính lùi số dư đầu kỳ" + Window Function, nhưng đọc `GD_GOIRUT`/`GD_CHUYENTIEN` từ LINK1 + LINK2. Số dư hiện tại lấy từ LINK1, fallback LINK2. **Chỉ được gọi khi báo cáo tổng hợp không chọn SOTK cụ thể** — vì route `baocao.js` khi NganHang chọn SOTK cụ thể sẽ mượn `spServer='BENTHANH'` để gọi bản chi nhánh (đơn giản và đủ dữ liệu — TaiKhoan replicate full, GD Local+LINK1 gộp đủ).

```sql
CREATE OR ALTER PROCEDURE [dbo].[SP_SaoKeTaiKhoan]
    @SOTK NVARCHAR(50), @TUNGAY DATETIME, @DENNGAY DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SODU_HIENTAI MONEY;
    SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    IF @SODU_HIENTAI IS NULL
        SELECT @SODU_HIENTAI = SODU FROM [LINK2].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    IF @SODU_HIENTAI IS NULL
    BEGIN RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1); RETURN; END

    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;
    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE WHEN LOAIGD IN ('GT','NT') THEN SOTIEN
             WHEN LOAIGD IN ('RT','CT') THEN -SOTIEN ELSE 0 END), 0)
    FROM (
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL SELECT SOTIEN, 'CT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL SELECT SOTIEN, 'NT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL SELECT SOTIEN, LOAIGD FROM [LINK2].NGANHANG.dbo.GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL SELECT SOTIEN, 'CT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL SELECT SOTIEN, 'NT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    ;WITH TransactionsInPeriod AS (
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL SELECT NGAYGD, SOTIEN, 'CT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL SELECT NGAYGD, SOTIEN, 'NT' FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK2].NGANHANG.dbo.GD_GOIRUT
         WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL SELECT NGAYGD, SOTIEN, 'CT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL SELECT NGAYGD, SOTIEN, 'NT' FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN
         WHERE SOTK_NHAN   = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    RunningBalance AS (
        SELECT NGAYGD, LOAIGD, SOTIEN,
               SODU_LUYKE = @SODU_DAUKY + SUM(
                   CASE WHEN LOAIGD IN ('GT','NT') THEN SOTIEN
                        WHEN LOAIGD IN ('RT','CT') THEN -SOTIEN ELSE 0 END)
                   OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    SELECT * FROM RunningBalance ORDER BY NGAYGD ASC;
END
GO
GRANT EXECUTE ON dbo.SP_SaoKeTaiKhoan TO NganHang;
GRANT EXECUTE ON dbo.SP_SaoKeTaiKhoan TO ChiNhanh;
GRANT EXECUTE ON dbo.SP_SaoKeTaiKhoan TO KhachHang;
```

---

## 📌 Ghi chú deploy

- **SP là Article** (`sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang`, `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_PhucHoiNhanVien`, `sp_ThemKhachHang`, `SP_SaoKeTaiKhoan` bản chi nhánh): chỉ ALTER trên NGUON theo quy trình 6 bước tại [`08_Database_Replication.md`](08_Database_Replication.md) §5.
- **SP không phải Article** (`SP_ResetMatKhau`, `sp_TaiKhoanKhachHang`, **`SP_DongTaiKhoan`**): deploy thủ công trên từng site qua `setup_db.js` hoặc `run_all.bat` (đã thêm `sqlcmd -i sql\stored_procedures\23_SP_DongTaiKhoan.sql` vào batch script).
- **SP đặc thù TRACUU** (`sp_DanhSachTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay` bản TRACUU, `sp_DanhSachNhanVien`, `sp_SaoKeToanBo`, `SP_DanhSachTrangThaiLogin`, `SP_SaoKeTaiKhoan` bản TRACUU): deploy thủ công qua [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql).

## 📝 Lịch sử refactor gần đây

| Fix | SP | Nội dung |
|-----|----|----|
| **#3** | `sp_MoTaiKhoan` | Sinh SOTK atomic trong SP (retry PK conflict), prefix theo `@MACN` chi nhánh sở hữu TK. Bỏ tham số `@SOTK`, SP trả SOTK mới qua `SELECT`. |
| **#6** | `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien` | Rẽ nhánh `BEGIN TRANSACTION` (cùng CN) vs `BEGIN DISTRIBUTED TRANSACTION` (khác CN) — giảm chi phí MSDTC cho tác vụ local. |
| **#8** | `SP_SaoKeTaiKhoan` (bản CN + bản TRACUU) | Defense-in-depth: `IS_ROLEMEMBER('KhachHang')` + `SUSER_SNAME()` chặn KH xem sao kê TK người khác kể cả khi bypass ứng dụng. |
| **#9** | `sp_ChuyenTien` | Chặn `@SOTK_CHUYEN = @SOTK_NHAN` (self-transfer). |
| **RF-A** | `sp_ChuyenNhanVien` | Resurrect NV soft-delete tại chi nhánh đích (giữ MANV cũ + info cũ) thay vì INSERT mới → tránh UQ_NhanVien_CMND violation trong kịch bản "chuyển đi rồi chuyển về". |
| **RF-B** | **`SP_DongTaiKhoan`** (mới) | Đẩy 5 lớp guard từ route Node xuống SP: SODU=0, không GD, same-branch. Route chỉ còn forward call. |

**Kiểm chứng:** Tất cả các fix đã PASS 12+ test case qua `sqlcmd` (SQL layer) và 4 test case qua Playwright (browser E2E). Xem [`test/e2e_http.js`](../test/e2e_http.js) và [`test/e2e_pw.spec.js`](../test/e2e_pw.spec.js).
