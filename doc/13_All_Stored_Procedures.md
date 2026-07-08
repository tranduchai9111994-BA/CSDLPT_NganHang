# Toàn bộ Stored Procedures hiện tại trong CSDL

Tài liệu này tổng hợp code mới nhất của tất cả các Stored Procedures đang chạy trong hệ thống (đã bao gồm các bản vá lỗi gần nhất).

**[Cập nhật 19/06/2026] Thông tin đưa vào Article (Replication):**
- **PUB_BENTHANH & PUB_TANDINH:** Đã add toàn bộ 11 SP nghiệp vụ bên dưới vào Article (chế độ Replicate stored procedure definitions).
- **PUB_TRACUU:** Article gồm: `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang`, `sp_LietKeTaiKhoanTheoNgay`, `sp_DanhSachTaiKhoan` (tổng 5 SP).
- **[Cập nhật 05/07/2026] SP riêng của TRACUU** (không qua Replication, cài bằng `setup_db.js` hoặc [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql)):
  - `sp_SaoKeToanBo` — gộp GD_GOIRUT + GD_CHUYENTIEN từ LINK1+LINK2
  - `sp_DanhSachNhanVien` — gộp NhanVien từ LINK1+LINK2 (TRACUU không có NhanVien local)
  - `SP_DanhSachTrangThaiLogin` — phiên bản TRACUU, đọc NhanVien qua LINK, KhachHang+QuanTriLogin local
- **[Cập nhật 05/07/2026] Lưu ý quan trọng về TaiKhoan:** TaiKhoan replicate full (giống ChiNhanh) → mỗi site đã có đủ TK cả 2 chi nhánh. SP trên TRACUU chỉ đọc từ **LINK1** (không UNION ALL LINK1+LINK2, vì sẽ bị duplicate). JOIN KhachHang local dùng **OUTER APPLY TOP 1** để tránh nhân bản kết quả.
- **Lưu ý:** Đã xoá bỏ `SP_DangNhap` (không phải là Article, xoá thành công bằng `DROP PROCEDURE IF EXISTS`).

---

## sp_Login_App

**Chạy trên:** BENTHANH / TANDINH / TRACUU (replicated qua PUB_TRACUU)  
**Gọi bởi:** `auth.js` – POST `/login`

```sql
CREATE   PROCEDURE [dbo].[sp_Login_App]
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
```

> **Flow:**
> 1. **Nhận input:** `@LoginName` = tên đăng nhập SQL (ví dụ: `NV001`, `1234567890`).
> 2. **Resolve DB username:** JOIN `sys.database_principals` ↔ `sys.server_principals` theo SID để lấy DB user tương ứng với login. Nếu không tìm thấy → fallback về chính `@LoginName`.
> 3. **Kiểm tra Role:** Truy vấn `sys.database_role_members` để xác định user thuộc nhóm nào trong `{NganHang, ChiNhanh, KhachHang}`. Nếu không có role → RAISERROR.
> 4. **Lấy thông tin theo nhóm:**
>    - `ChiNhanh` / `NganHang`: đọc `NhanVien` (TrangThaiXoa=0), lấy MANV + HoTen + MACN.
>    - `NganHang` không tìm thấy trong NhanVien → dùng fallback "Quan Tri Vien" + MACN đầu tiên trong ChiNhanh.
>    - `KhachHang`: đọc `KhachHang` theo CMND = DBUserName.
> 5. **Trả về:** 1 row gồm USERNAME, MANV, HOTEN, NHOM, MACN → app lưu vào session.

---

## sp_LietKeKhachHang

**Chạy trên:** BENTHANH / TANDINH / TRACUU  
**Gọi bởi:** `khachhang.js` – GET `/khachhang`

```sql
-- KhachHang replicate full trên mọi site → chỉ cần đọc local, không cần Linked Server.
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeKhachHang]
    @MACN nchar(10) = NULL  -- NULL = tất cả; có giá trị = lọc theo chi nhánh
AS
BEGIN
    SET NOCOUNT ON;

    SELECT HO, TEN, CMND, MACN, SODT
    FROM KhachHang
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
```

> **Flow:**
> 1. **Nhận input:** `@MACN` – lọc theo chi nhánh (NULL = tất cả).
> 2. **Đọc local:** Bảng `KhachHang` được replicate full trên mọi site → không cần Linked Server.
> 3. **Lọc:** Nếu `@MACN` có giá trị → `WHERE MACN = @MACN` (lọc theo chi nhánh của NV/NganHang).
> 4. **Trả về:** Danh sách khách hàng sắp xếp theo MACN → HO → TEN.
>
> **Lưu ý phân tán:** NganHang luôn kết nối TRACUU → đọc KhachHang replicated từ cả 2 chi nhánh, hiển thị toàn bộ. ChiNhanh đọc local của chi nhánh mình.

---

## sp_ThemKhachHang

**Chạy trên:** BENTHANH / TANDINH  
**Gọi bởi:** `khachhang.js` – POST `/khachhang/them`

```sql
CREATE   PROCEDURE [dbo].[sp_ThemKhachHang]
    @CMND nchar(10),
    @HO nvarchar(40),
    @TEN nvarchar(10),
    @DIACHI nvarchar(100),
    @PHAI nvarchar(3),
    @NGAYCAP date,
    @SODT nvarchar(15),
    @MACN nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng đã tồn tại.', 16, 1);
        RETURN;
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
```

> **Flow:**
> 1. **Nhận input:** Đầy đủ thông tin khách hàng (CMND, HO, TEN, ..., MACN).
> 2. **Kiểm tra trùng CMND:** Nếu CMND đã tồn tại trong `KhachHang` → RAISERROR.
> 3. **INSERT:** Ghi bản ghi mới vào `KhachHang` tại chi nhánh (MACN = chi nhánh đang thao tác).
> 4. **Replication:** Sau khi INSERT, Merge Replication tự đồng bộ sang các site khác (BENTHANH↔TANDINH↔TRACUU).

---

## sp_MoTaiKhoan

**Ghi chú:** SP cũ, dùng `LINK0` (Publisher NGUON). Phiên bản hiện tại dùng `SP_TaoTaiKhoan`.

```sql
CREATE   PROCEDURE [dbo].[sp_MoTaiKhoan]
    @SOTK nchar(9),
    @CMND nchar(10),
    @SODU money,
    @MACN nchar(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK))
    BEGIN
        RAISERROR(N'Số tài khoản đã tồn tại.',16,1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM LINK0.NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng không tồn tại trên hệ thống.',16,1);
        RETURN;
    END

    INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK)
    VALUES(@SOTK, @CMND, @SODU, @MACN, GETDATE());
END
```

> **Flow:**
> 1. Kiểm tra SOTK chưa tồn tại trong `TaiKhoan` local.
> 2. Kiểm tra CMND tồn tại qua `LINK0` (Publisher NGUON) — đây là cách cũ trước khi KhachHang được replicate full.
> 3. INSERT vào `TaiKhoan` local → replicate sang các site khác.

---

## sp_GuiTien

**Chạy trên:** BENTHANH / TANDINH  
**Gọi bởi:** `giaodich.js` – POST `/giaodich/goirut` (LOAIGD = 'GT')

```sql
CREATE  PROCEDURE sp_GuiTien
    @SOTK   nchar(9),
    @SOTIEN money,
    @MANV   nchar(10)
AS
BEGIN
    SET NOCOUNT ON

    -- Kiểm tra số tiền hợp lệ
    IF @SOTIEN < 100000
    BEGIN
        RAISERROR(N'Số tiền gửi tối thiểu là 100,000 VNĐ.', 16, 1)
        RETURN
    END

    -- Kiểm tra tài khoản tồn tại
    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE SOTK = @SOTK)
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại.', 16, 1)
        RETURN
    END

    BEGIN TRY
        BEGIN TRANSACTION

        -- Cập nhật số dư
        UPDATE TaiKhoan
        SET SODU = SODU + @SOTIEN
        WHERE SOTK = @SOTK

        -- Ghi giao dịch gửi tiền
        INSERT INTO GD_GOIRUT (SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
        VALUES (@SOTK, 'GT', GETDATE(), @SOTIEN, @MANV)

        COMMIT TRANSACTION

        PRINT N'Gửi tiền thành công.'
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        DECLARE @msg NVARCHAR(4000)
        SET @msg = ERROR_MESSAGE()

        RAISERROR(@msg, 16, 1)
    END CATCH
END
```

> **Flow:**
> 1. **Validate:** `@SOTIEN >= 100,000` VNĐ (tối thiểu theo quy định).
> 2. **Kiểm tra TK:** Tài khoản phải tồn tại trong `TaiKhoan` local (TK replicated full → luôn có local).
> 3. **Transaction:**
>    - `UPDATE TaiKhoan SET SODU += @SOTIEN` — cộng số dư.
>    - `INSERT GD_GOIRUT (LOAIGD='GT')` — ghi log gửi tiền.
> 4. **Replication:** GD_GOIRUT được replicate về TRACUU để NganHang tra cứu.
>
> **Giao dịch này là local** (không dùng DISTRIBUTED TRANSACTION) vì TK và GD_GOIRUT đều nằm cùng server.

---

## sp_RutTien

**Chạy trên:** BENTHANH / TANDINH  
**Gọi bởi:** `giaodich.js` – POST `/giaodich/goirut` (LOAIGD = 'RT')

```sql
CREATE PROCEDURE [dbo].[sp_RutTien]
    @SOTK nchar(9),
    @SOTIEN money,
    @MANV nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- ✅ BẢN VÁ: Thêm kiểm tra số tiền tối thiểu (đúng đề bài)
    IF @SOTIEN < 100000
    BEGIN
        RAISERROR(N'Số tiền rút tối thiểu là 100,000 VNĐ.', 16, 1);
        RETURN;
    END

    -- Kiểm tra tài khoản tồn tại
    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK))
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Trừ tiền + kiểm tra số dư đủ trong cùng 1 câu lệnh (atomic)
        UPDATE TaiKhoan 
        SET SODU = SODU - @SOTIEN 
        WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND SODU >= @SOTIEN;
        -- Nếu SODU < @SOTIEN thì WHERE không match → @@ROWCOUNT = 0

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Số dư không đủ để rút.', 16, 1);
            RETURN;
        END

        -- Ghi log giao dịch rút tiền
        INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
        VALUES(@SOTK, 'RT', GETDATE(), @SOTIEN, @MANV);
        -- LOAIGD = 'RT' nghĩa là Rút Tiền

        COMMIT TRANSACTION;
        PRINT N'Rút tiền thành công.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

> **Flow:**
> 1. **Validate:** `@SOTIEN >= 100,000` VNĐ.
> 2. **Kiểm tra TK tồn tại:** Tài khoản phải có trong `TaiKhoan` local.
> 3. **Transaction — kiểm tra số dư atomic:**
>    - `UPDATE TaiKhoan SET SODU -= @SOTIEN WHERE SODU >= @SOTIEN` — vừa trừ vừa kiểm tra số dư trong 1 câu lệnh. Nếu không đủ tiền → `@@ROWCOUNT = 0` → ROLLBACK + RAISERROR.
>    - `INSERT GD_GOIRUT (LOAIGD='RT')` — ghi log rút tiền.
> 4. **Kỹ thuật đặc biệt:** Điều kiện `SODU >= @SOTIEN` trong WHERE tránh race condition (so với cách đọc SODU ra rồi so sánh riêng — có thể xảy ra concurrent access).

---

## sp_ChuyenTien

**Chạy trên:** BENTHANH / TANDINH  
**Gọi bởi:** `giaodich.js` – POST `/giaodich/chuyentien`

```sql
-- TaiKhoan được NHÂN BẢN TOÀN VẸN → mọi TK đều tồn tại local.
-- Dùng MACN để phân biệt: cùng CN → ghi local, khác CN → ghi qua LINK1.
CREATE   PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),
    @SOTK_NHAN   nchar(9),
    @SOTIEN      money,
    @MANV        nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);
        RETURN;
    END

    -- Kiểm tra TK chuyển + lấy MACN (đọc local — nhân bản full)
    DECLARE @MACN_CHUYEN nchar(10);
    SELECT @MACN_CHUYEN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
    IF @MACN_CHUYEN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1);
        RETURN;
    END

    -- Kiểm tra TK nhận + lấy MACN (đọc local — nhân bản full, không cần LINK1)
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- So sánh MACN: cùng CN → ghi local, khác CN → ghi qua LINK1
    DECLARE @IsNhanLocal bit = 0;
    IF @MACN_NHAN = @MACN_CHUYEN
        SET @IsNhanLocal = 1;

    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;

        UPDATE TaiKhoan 
        SET SODU = SODU - @SOTIEN 
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN) AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
            RETURN;
        END

        IF @IsNhanLocal = 1
        BEGIN
            UPDATE TaiKhoan 
            SET SODU = SODU + @SOTIEN 
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END
        ELSE
        BEGIN
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan 
            SET SODU = SODU + @SOTIEN 
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END

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
```

> **Flow:**
> 1. **Validate:** `@SOTIEN > 0`.
> 2. **Đọc MACN của 2 TK từ local** (TaiKhoan replicated full → cả 2 chi nhánh đều có đủ TK). Nếu TK không tồn tại → RAISERROR.
> 3. **Phân biệt nội/liên chi nhánh:** So sánh `MACN_CHUYEN` vs `MACN_NHAN`:
>    - Giống nhau (`@IsNhanLocal=1`) → giao dịch **cùng chi nhánh**, cộng tiền local.
>    - Khác nhau → giao dịch **liên chi nhánh**, cộng tiền qua `[LINK1].NGANHANG.dbo.TaiKhoan`.
> 4. **DISTRIBUTED TRANSACTION (MSDTC):**
>    - Trừ SODU của TK chuyển (kèm kiểm tra đủ số dư atomic).
>    - Cộng SODU của TK nhận (local hoặc qua LINK1).
>    - INSERT `GD_CHUYENTIEN` ghi log tại chi nhánh chuyển.
> 5. **XACT_ABORT ON:** Mọi lỗi → tự động ROLLBACK toàn bộ distributed transaction.
>
> **Lưu ý:** GD_CHUYENTIEN chỉ ghi tại chi nhánh **chuyển** (không ghi tại chi nhánh nhận). Khi sao kê TK nhận, SP_SaoKeTaiKhoan sẽ JOIN `SOTK_NHAN` để tính số dư.

---

## SP_SaoKeTaiKhoan

**Chạy trên:** BENTHANH / TANDINH  
**Gọi bởi:** `baocao.js` – GET `/baocao/saoke` (ChiNhanh và KhachHang)

```sql
CREATE   PROCEDURE SP_SaoKeTaiKhoan
    @SOTK NVARCHAR(50),
    @TUNGAY DATETIME,
    @DENNGAY DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    -- BƯỚC 1: KIỂM TRA TÀI KHOẢN VÀ LẤY SỐ DƯ HIỆN TẠI
    DECLARE @SODU_HIENTAI MONEY;
    
    SELECT @SODU_HIENTAI = SODU FROM TaiKhoan WHERE SOTK = @SOTK;
    
    IF @SODU_HIENTAI IS NULL
    BEGIN
        SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    END

    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại trên hệ thống.', 16, 1);
        RETURN;
    END

    -- BƯỚC 2: TÍNH SỐ DƯ ĐẦU KỲ BẰNG CÁCH "TRỪ NGƯỢC" TỪ HIỆN TẠI
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;

    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE 
            WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN
            WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN
            ELSE 0
        END
    ), 0)
    FROM (
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- BƯỚC 3: TRÍCH XUẤT CHI TIẾT GIAO DỊCH VÀ TÍNH SỐ DƯ LŨY KẾ
    WITH TransactionsInPeriod AS (
        SELECT NGAYGD, SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    RunningBalance AS (
        SELECT 
            NGAYGD,
            LOAIGD,
            SOTIEN,
            SODU_LUYKE = @SODU_DAUKY + SUM(
                CASE 
                    WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN
                    WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN
                    ELSE 0
                END
            ) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    SELECT * 
    FROM RunningBalance 
    ORDER BY NGAYGD ASC;

END
```

> **Flow:**
> 1. **Nhận input:** `@SOTK`, `@TUNGAY`, `@DENNGAY`.
> 2. **Bước 1 — Lấy số dư hiện tại:**
>    - Tìm trong `TaiKhoan` local trước.
>    - Nếu không có → tìm qua `[LINK1]` (TK của chi nhánh đối tác).
>    - Không tìm thấy → RAISERROR.
> 3. **Bước 2 — Tính số dư đầu kỳ (thuật toán "trừ ngược"):**
>    - Lấy tất cả biến động từ `@TUNGAY` đến nay (local + LINK1): GT/NT cộng (+), RT/CT trừ (-).
>    - `SODU_DAUKY = SODU_HIENTAI − BIENDONG_SAU_TUNGAY`
>    - Lý do: thay vì load toàn bộ lịch sử từ đầu (tốn I/O), chỉ cần biết biến động từ @TUNGAY đến nay.
> 4. **Bước 3 — Trích xuất chi tiết trong kỳ [@TUNGAY, @DENNGAY]:**
>    - CTE `TransactionsInPeriod`: UNION ALL 6 nguồn (GD_GOIRUT local, GD_CHUYENTIEN local × 2, + LINK1 × 3).
>    - CTE `RunningBalance`: Window Function `SUM(...) OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` tính số dư lũy kế sau mỗi GD.
> 5. **Trả về:** Danh sách GD kèm SODU_LUYKE sau từng giao dịch, sắp xếp theo ngày tăng dần.
>
> **Lý do đọc cả LINK1:** GD của TK này có thể phát sinh ở chi nhánh đối tác (ví dụ TK ở BENTHANH nhưng nộp tiền tại TANDINH → GD_GOIRUT ghi tại TANDINH).

---

## sp_TaiKhoanKhachHang *(chạy trên BENTHANH/TANDINH — GRANT EXECUTE cho KhachHang)*

**Gọi bởi:** `baocao.js` – GET `/baocao/saoke` (KhachHang chọn TK của mình)

```sql
-- Trả danh sách TK thuộc về 1 CMND. KhachHang có EXECUTE nhưng không có SELECT trực tiếp
-- trên TaiKhoan → SP là cửa ngõ duy nhất, đảm bảo KhachHang chỉ thấy TK của mình.
CREATE OR ALTER PROCEDURE sp_TaiKhoanKhachHang
    @CMND nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM TaiKhoan tk
    WHERE RTRIM(tk.CMND) = RTRIM(@CMND)
    ORDER BY tk.NGAYMOTK DESC;
END
```

> **Flow:**
> 1. **Nhận input:** `@CMND` — CMND của khách hàng đang đăng nhập (lấy từ session).
> 2. **Bảo mật theo tầng:** KhachHang role không có SELECT trực tiếp trên `TaiKhoan` → phải gọi SP này. SP chỉ trả TK của đúng CMND đó.
> 3. **Đọc local:** TaiKhoan replicated full → cả 2 chi nhánh đều có. SP trả tất cả TK của KH, kể cả TK mở ở chi nhánh khác.
> 4. **Trả về:** Danh sách SOTK, CMND, SODU, MACN, NGAYMOTK sắp xếp theo ngày mở mới nhất.

---

## sp_ChuyenNhanVien

**Chạy trên:** Chi nhánh **cũ** (nơi NV đang làm việc)  
**Gọi bởi:** `nhanvien.js` – POST `/nhanvien/chuyen` (qua `execSPAdmin`)

```sql
CREATE PROCEDURE [dbo].[sp_ChuyenNhanVien]
    @MANV nchar(10),
    @MACN_MOI nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Kiểm tra nhân viên có tồn tại và đang làm việc không
    IF NOT EXISTS (
        SELECT 1 FROM NhanVien 
        WHERE RTRIM(MANV) = RTRIM(@MANV) AND TrangThaiXoa = 0
    )
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại hoặc đã nghỉ việc tại chi nhánh này.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        -- Bắt đầu giao dịch phân tán (vì sẽ thao tác trên 2 server khác nhau)
        BEGIN DISTRIBUTED TRANSACTION;
        
        -- Đọc thông tin nhân viên trước khi chuyển
        DECLARE @HO nvarchar(50), @TEN nvarchar(10), @CMND nchar(10);
        DECLARE @DIACHI nvarchar(100), @PHAI nvarchar(3), @SODT nvarchar(15);
        
        SELECT @HO = HO, @TEN = TEN, @CMND = CMND, 
               @DIACHI = DIACHI, @PHAI = PHAI, @SODT = SODT
        FROM NhanVien 
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        -- ✅ ĐÚNG ĐỀ BÀI: Đánh dấu đã chuyển ở chi nhánh cũ (KHÔNG xóa hẳn)
        UPDATE NhanVien 
        SET TrangThaiXoa = 1 
        WHERE RTRIM(MANV) = RTRIM(@MANV);
        
        -- Chèn bản ghi mới vào chi nhánh đối tác qua Linked Server
        -- LINK1 luôn trỏ đến chi nhánh đối tác (quy tắc cố định)
        INSERT INTO [LINK1].NGANHANG.dbo.NhanVien 
            (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES 
            (@MANV, @HO, @TEN, @CMND, @DIACHI, @PHAI, @SODT, @MACN_MOI, 0);
        -- TrangThaiXoa = 0 ở chi nhánh mới: nhân viên đang hoạt động

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

> **Flow:**
> 1. **Nhận input:** `@MANV` (mã NV cần chuyển), `@MACN_MOI` (chi nhánh đích).
> 2. **Validate:** NV phải tồn tại trong `NhanVien` local với `TrangThaiXoa=0` (đang hoạt động).
> 3. **Đọc thông tin NV** để copy sang chi nhánh mới.
> 4. **DISTRIBUTED TRANSACTION (MSDTC):**
>    - `UPDATE NhanVien SET TrangThaiXoa=1` — đánh dấu **không xóa** ở chi nhánh cũ (soft-delete, lưu lịch sử).
>    - `INSERT [LINK1].NGANHANG.dbo.NhanVien` — tạo bản ghi mới với `TrangThaiXoa=0` tại chi nhánh mới qua LINK1.
> 5. **Kết quả:** NV có 2 bản ghi: chi nhánh cũ (TrangThaiXoa=1), chi nhánh mới (TrangThaiXoa=0).
> 6. **App layer:** `nhanvien.js` xác định `serverHienTai` = server ngược với `@MACN_MOI` để gọi SP trên đúng server.

---

## SP_PhuHoiNhanVien

**Chạy trên:** Chi nhánh đang phục hồi NV (chi nhánh cũ)  
**Gọi bởi:** `nhanvien.js` – POST `/nhanvien/phuchoi` (qua `execSPAdmin`)

```sql
CREATE OR ALTER PROCEDURE SP_PhuHoiNhanVien
    @MANV NVARCHAR(10)   -- Mã NV cần phục hồi (VD: BT001)
AS
BEGIN
    SET XACT_ABORT ON;
    SET NOCOUNT ON;

    -- Bước 1: Kiểm tra NV tồn tại và đang ở trạng thái xóa
    DECLARE @CMND         NVARCHAR(20);
    DECLARE @TRANGTHAIXOA BIT;

    SELECT @CMND = RTRIM(CMND), @TRANGTHAIXOA = TrangThaiXoa
    FROM NhanVien
    WHERE RTRIM(MANV) = RTRIM(@MANV);

    IF @CMND IS NULL
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại ở chi nhánh này.', 16, 1);
        RETURN;
    END

    IF @TRANGTHAIXOA = 0
    BEGIN
        RAISERROR(N'Nhân viên này đang hoạt động, không cần phục hồi.', 16, 1);
        RETURN;
    END

    -- Bước 2: Tìm bản ghi đang active cùng CMND ở chi nhánh kia (qua LINK1)
    DECLARE @MANV_BEN_KIA NVARCHAR(10);

    SELECT TOP 1 @MANV_BEN_KIA = RTRIM(MANV)
    FROM [LINK1].NGANHANG.dbo.NhanVien
    WHERE RTRIM(CMND) = @CMND
      AND TrangThaiXoa = 0;

    -- Bước 3: Distributed transaction - phục hồi local + deactivate bên kia
    BEGIN TRY
        BEGIN DISTRIBUTED TRAN;

        UPDATE NhanVien
        SET TrangThaiXoa = 0
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        IF @MANV_BEN_KIA IS NOT NULL
        BEGIN
            UPDATE [LINK1].NGANHANG.dbo.NhanVien
            SET TrangThaiXoa = 1
            WHERE RTRIM(MANV) = @MANV_BEN_KIA;
        END

        COMMIT TRAN;

        SELECT @MANV        AS MANV_PHUCHOI,
               @MANV_BEN_KIA AS MANV_DEACTIVATED;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg      NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT            = ERROR_SEVERITY();
        DECLARE @ErrState    INT            = ERROR_STATE();
        RAISERROR(@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END
```

> **Flow:**
> 1. **Nhận input:** `@MANV` — mã NV cần phục hồi (ví dụ BT001).
> 2. **Validate bước 1:**
>    - NV phải tồn tại trong `NhanVien` local → lấy CMND và TrangThaiXoa.
>    - Nếu không tìm thấy → RAISERROR "không tồn tại".
>    - Nếu `TrangThaiXoa=0` → đang hoạt động, không cần phục hồi → RAISERROR.
> 3. **Validate bước 2:** Tìm qua `[LINK1]` xem có bản ghi cùng CMND đang `TrangThaiXoa=0` ở chi nhánh kia không (bản ghi được tạo khi chuyển chi nhánh).
> 4. **DISTRIBUTED TRANSACTION (MSDTC):**
>    - `UPDATE NhanVien SET TrangThaiXoa=0` — phục hồi NV ở chi nhánh hiện tại.
>    - Nếu tìm thấy `@MANV_BEN_KIA` → `UPDATE [LINK1]... SET TrangThaiXoa=1` — tự động deactivate bản ghi chi nhánh kia.
> 5. **Trả về:** `MANV_PHUCHOI` + `MANV_DEACTIVATED` (NULL nếu không có bản ghi bên kia).
> 6. **App layer:** Hiển thị thông báo thành công, nếu có `MANV_DEACTIVATED` → thêm thông tin "tự động vô hiệu hóa [MANV] ở chi nhánh kia".
>
> **Tính nhất quán:** Đảm bảo tại mọi thời điểm 1 người (CMND) chỉ có tối đa 1 bản ghi active trong toàn hệ thống.

---

## SP_TaoTaiKhoan

**Chạy trên:** BENTHANH / TANDINH / TRACUU  
**Gọi bởi:** `quantri.js` – POST `/quantri/taotaikhoan`

```sql
CREATE PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME VARCHAR(50), 
    @PASS VARCHAR(50), 
    @USERNAME VARCHAR(50), 
    @ROLE VARCHAR(50),
    @LOAITK VARCHAR(20),   -- 'NhanVien' hoặc 'KhachHang'
    @MATHAMCHIEU VARCHAR(50) -- MANV hoặc CMND
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

        -- Ghi vào bảng quản trị để phục vụ tính năng theo dõi + xem mật khẩu
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
```

> **Flow:**
> 1. **Nhận input:** LoginName, Password, UserName, Role (ChiNhanh/KhachHang/NganHang), LoaiTK, MaThamChieu (MANV hoặc CMND).
> 2. **Kiểm tra trùng:** Login name chưa có trong `sys.server_principals`; DB user chưa có trong `sys.database_principals`.
> 3. **Tạo login SQL:** `CREATE LOGIN` với password, tắt kiểm tra chính sách mật khẩu.
> 4. **Tạo DB user:** `CREATE USER ... FOR LOGIN ...` liên kết login với user trong database NGANHANG.
> 5. **Gán role:** `sp_addrolemember` thêm user vào role tương ứng (ChiNhanh/KhachHang/NganHang).
> 6. **Ghi log:** INSERT vào `QuanTriLogin` để admin có thể xem/reset mật khẩu và theo dõi trạng thái.
> 7. **WITH EXECUTE AS OWNER:** SP cần quyền sysadmin để tạo login → chạy với quyền của owner (dbo/sa).
>
> **Lưu ý:** SP tạo login ở **server hiện tại** (BENTHANH hoặc TANDINH). NganHang dùng server TRACUU → tạo login trên TRACUU, không thể đăng nhập vào BENTHANH/TANDINH. Cần tạo login riêng trên từng server nếu cần đăng nhập trực tiếp.

---

## SP_ResetMatKhau

**Chạy trên:** BENTHANH / TANDINH / TRACUU  
**Gọi bởi:** `quantri.js` – POST `/quantri/reset-password`

```sql
CREATE PROCEDURE [dbo].[SP_ResetMatKhau]
    @LGNAME      VARCHAR(50),
    @MATKHAU_MOI VARCHAR(50) = '123456'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
    BEGIN
        RAISERROR(N'Login không tồn tại trên server này.', 16, 1);
        RETURN 1;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@MATKHAU_MOI, '''', '''''');

        SET @SqlStr = 'ALTER LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''';';
        EXEC(@SqlStr);

        UPDATE dbo.QuanTriLogin
        SET MatKhauHienTai = @MATKHAU_MOI,
            NgayCapNhatMK  = GETDATE()
        WHERE LoginName = @LGNAME;

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 2;
    END CATCH
END
```

> **Flow:**
> 1. **Nhận input:** `@LGNAME`, `@MATKHAU_MOI` (default = '123456').
> 2. **Validate:** Login phải tồn tại trong `sys.server_principals` trên server đang chạy SP.
> 3. **Đổi mật khẩu:** `ALTER LOGIN ... WITH PASSWORD = ...` (dynamic SQL qua `EXEC`).
> 4. **Cập nhật log:** `UPDATE QuanTriLogin SET MatKhauHienTai + NgayCapNhatMK` để admin xem mật khẩu hiện tại.

---

## SP_DanhSachTrangThaiLogin *(ChiNhanh — đọc NhanVien local)*

**Chạy trên:** BENTHANH / TANDINH  
**Gọi bởi:** `quantri.js` – GET `/quantri/login-management/list` (ChiNhanh)

```sql
CREATE PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
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
```

> **Flow:**
> 1. **Nhận input:** `@MACN` (NULL = tất cả, có giá trị = lọc theo chi nhánh).
> 2. **Phần NhanVien:** LEFT JOIN `NhanVien` (local, TrangThaiXoa=0) với `QuanTriLogin`. Tính `DaCapTaiKhoan`:
>    - `0` = chưa có bản ghi trong QuanTriLogin (chưa cấp tài khoản).
>    - `1` = có trong QuanTriLogin và login còn tồn tại trong `sys.server_principals`.
>    - `2` = có trong QuanTriLogin nhưng login đã bị xóa khỏi server (lỗi đồng bộ).
> 3. **Phần KhachHang:** Tương tự, JOIN `KhachHang` (replicated local) với `QuanTriLogin`.
> 4. **UNION ALL:** Gộp 2 danh sách, sắp xếp theo LoaiTK → DaCapTaiKhoan → HoTen.

---

## SP_XoaLoiDongBo

**Chạy trên:** BENTHANH / TANDINH / TRACUU  
**Gọi bởi:** `quantri.js` – POST `/quantri/xoa-loi-dongbo`

```sql
CREATE PROCEDURE [dbo].[SP_XoaLoiDongBo]
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
```

> **Flow:**
> 1. **Nhận input:** `@LoginName`, `@UserName` (NULL = trùng với LoginName).
> 2. **Xóa khỏi QuanTriLogin:** Dọn bản ghi tracking không còn hợp lệ.
> 3. **DROP DB User (nếu còn):** Kiểm tra `sys.database_principals` → nếu DB user còn tồn tại → DROP.
> 4. **Dùng khi:** Login bị xóa thủ công qua SSMS nhưng QuanTriLogin chưa được cập nhật → trạng thái `DaCapTaiKhoan=2` (lỗi đồng bộ). SP này dọn dẹp trạng thái đó.

---

## sp_DanhSachTaiKhoan *(TRACUU — đọc TaiKhoan qua LINK1)*

**Chạy trên:** TRACUU  
**Gọi bởi:** `taikhoan.js` – GET `/taikhoan` (NganHang)

```sql
-- TaiKhoan replicate full → LINK1 đã có đủ data cả 2 CN. Không UNION ALL (sẽ duplicate).
-- JOIN KhachHang local dùng OUTER APPLY TOP 1 để tránh nhân bản kết quả.
CREATE OR ALTER PROCEDURE sp_DanhSachTaiKhoan
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK)  AS SOTK,
           RTRIM(tk.CMND)  AS CMND,
           tk.SODU,
           RTRIM(tk.MACN)  AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
    ORDER BY tk.NGAYMOTK DESC;
END
```

> **Flow:**
> 1. **Đọc TaiKhoan qua LINK1** (BENTHANH): TaiKhoan replicated full → LINK1 đã có đủ TK cả 2 chi nhánh, không cần UNION ALL LINK1+LINK2 (sẽ duplicate).
> 2. **JOIN KhachHang local** (TRACUU): Dùng `OUTER APPLY TOP 1` để lấy tên KH theo CMND. `OUTER APPLY` thay vì LEFT JOIN để tránh nhân bản nếu có nhiều KH cùng CMND.
> 3. **Trả về:** Danh sách toàn bộ TK của hệ thống kèm HoTen, sắp xếp theo ngày mở mới nhất.

---

## sp_LietKeTaiKhoanTheoNgay *(TRACUU — đọc TaiKhoan qua LINK1)*

**Chạy trên:** TRACUU  
**Gọi bởi:** `baocao.js` – GET `/baocao/lietke?loai=tk` (NganHang)

```sql
-- TaiKhoan replicate full → LINK1 đã có đủ data cả 2 CN. Không UNION ALL (sẽ duplicate).
-- JOIN KhachHang local dùng OUTER APPLY TOP 1 để tránh nhân bản kết quả.
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,
    @TUNGAY date = NULL,
    @DENNGAY date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK) AS SOTK,
           RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU,
           RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
```

> **Flow:**
> 1. **Nhận input:** `@MACN`, `@TUNGAY`, `@DENNGAY` (tất cả nullable — NULL = không lọc).
> 2. **Đọc TaiKhoan qua LINK1** (tương tự `sp_DanhSachTaiKhoan` nhưng có thêm filter).
> 3. **Lọc:** Theo MACN (chi nhánh) và khoảng ngày mở tài khoản.
> 4. **Phiên bản ChiNhanh** (chạy trên BENTHANH/TANDINH): đọc `TaiKhoan` local thay vì LINK1.

---

## sp_SaoKeToanBo *(TRACUU only — dùng LINK1+LINK2)*

**Chạy trên:** TRACUU  
**Gọi bởi:** `baocao.js` – GET `/baocao/saoke` (NganHang)

```sql
-- Chạy trên TRACUU. Tổng hợp GD_GOIRUT + GD_CHUYENTIEN từ cả 2 chi nhánh
-- trong khoảng thời gian @TUNGAY–@DENNGAY, không lọc theo SOTK cụ thể.
CREATE OR ALTER PROCEDURE sp_SaoKeToanBo
    @TUNGAY datetime,
    @DENNGAY datetime
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
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
```

> **Flow:**
> 1. **Nhận input:** `@TUNGAY`, `@DENNGAY` — khoảng thời gian cần báo cáo.
> 2. **UNION ALL 6 nguồn:**
>    - `GD_GOIRUT` từ LINK1 (BENTHANH) — gửi/rút tại BT.
>    - `GD_GOIRUT` từ LINK2 (TANDINH) — gửi/rút tại TD.
>    - `GD_CHUYENTIEN.SOTK_CHUYEN` từ LINK1 — TK chuyển tại BT (LOAIGD='CT').
>    - `GD_CHUYENTIEN.SOTK_NHAN` từ LINK1 — TK nhận tại BT (LOAIGD='NT').
>    - `GD_CHUYENTIEN.SOTK_CHUYEN` từ LINK2 — TK chuyển tại TD (LOAIGD='CT').
>    - `GD_CHUYENTIEN.SOTK_NHAN` từ LINK2 — TK nhận tại TD (LOAIGD='NT').
> 3. **Lý do LINK1+LINK2 (không phải chỉ LINK1):** GD_GOIRUT và GD_CHUYENTIEN **không replicate** (partitioned by MACN) → mỗi chi nhánh chỉ có GD của mình. TRACUU phải đọc từ cả 2.
> 4. **Trả về:** Toàn bộ GD toàn hệ thống trong kỳ, sắp xếp theo ngày.

---

## sp_DanhSachNhanVien *(TRACUU only — dùng LINK1+LINK2)*

**Chạy trên:** TRACUU  
**Gọi bởi:** `nhanvien.js` – GET `/nhanvien` (NganHang); `quantri.js` – getNhanVienList

```sql
-- TRACUU không có NhanVien local (PUB_TRACUU chỉ replicate KhachHang).
-- SP đọc NhanVien từ BENTHANH (LINK1) + TANDINH (LINK2).
-- Dùng bởi: nhanvien.js (NganHang GET /), quantri.js (getNhanVienList)
CREATE PROCEDURE [dbo].[sp_DanhSachNhanVien]
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
```

> **Flow:**
> 1. **Nhận input:** `@MACN` (NULL = tất cả chi nhánh).
> 2. **UNION ALL LINK1+LINK2:** NhanVien được phân mảnh ngang theo MACN — BENTHANH có NV của mình, TANDINH có NV của mình → cần UNION để có danh sách đầy đủ.
> 3. **Lý do UNION ALL (không phải chỉ LINK1):** NhanVien **không replicate full** (khác TaiKhoan). Mỗi server chỉ có NV của chi nhánh mình.
> 4. **Lọc:** `@MACN` → lọc theo chi nhánh (NganHang dùng @MACN=NULL để thấy tất cả).
> 5. **Trả về:** Toàn bộ NV (kể cả TrangThaiXoa=1) để admin thấy lịch sử chuyển chi nhánh.

---

## SP_DanhSachTrangThaiLogin *(TRACUU — NhanVien qua LINK)*

**Chạy trên:** TRACUU  
**Gọi bởi:** `quantri.js` – GET `/quantri/login-management/list` (NganHang)

```sql
-- Phiên bản chạy trên TRACUU. Bản gốc (SQL1/SQL2) đọc NhanVien local.
-- TRACUU không có NhanVien → đọc qua LINK1+LINK2. KhachHang + QuanTriLogin vẫn local.
-- Dùng bởi: quantri.js (GET /login-management/list khi NganHang)
CREATE PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        'NhanVien' AS LoaiTK, nv.MANV AS MaThamChieu,
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
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK, kh.CMND AS MaThamChieu,
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
        RTRIM(kh.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName, ql.NhomQuyen, ql.NgayTao, ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND) AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
```

> **Flow:**
> 1. **Giống ChiNhanh version** nhưng NhanVien được lấy từ `UNION ALL LINK1+LINK2` thay vì local (TRACUU không có NhanVien).
> 2. **KhachHang:** Đọc local (replicated) + JOIN `QuanTriLogin` local (replicated).
> 3. **sys.server_principals:** Kiểm tra trên TRACUU — login được tạo trên TRACUU (khi NganHang tạo tài khoản) nên kiểm tra local là đúng.
> 4. **DaCapTaiKhoan:** 0 = chưa cấp, 1 = đang active, 2 = lỗi đồng bộ (QuanTriLogin có nhưng login đã mất).
