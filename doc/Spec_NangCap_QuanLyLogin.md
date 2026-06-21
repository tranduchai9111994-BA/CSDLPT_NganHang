# Spec nâng cấp: Form "Tạo Tài Khoản (Login)" — Quản lý & Theo dõi Login

## 0. Bối cảnh & Mục tiêu

Form hiện tại (`/taikhoan-login` hay route tương đương) chỉ có 2 panel:
- Cấp tài khoản Nhân Viên (tạo Login cho NhanVien)
- Cấp mã PIN Khách Hàng (tạo Login cho KhachHang)

**Yêu cầu nâng cấp — thêm 3 tính năng:**
1. **Bảng danh sách trạng thái cấp tài khoản** bên dưới form: biết NV/KH nào đã có Login, ai chưa.
2. **Xem/ẩn mật khẩu** (toggle con mắt) ngay trên bảng để kiểm tra login nhanh.
3. **Reset mật khẩu về mặc định** (`123456`) cho 1 tài khoản bất kỳ trong bảng, bằng 1 nút bấm.

## 1. Cảnh báo bảo mật bắt buộc đọc trước khi code

SQL Server **không lưu** mật khẩu Login dạng đọc lại được — `CREATE LOGIN ... WITH PASSWORD` chỉ lưu hash 1 chiều. Không có cách nào, kể cả bằng quyền `sa`, để "lấy lại" mật khẩu gốc từ SQL Server.

**Quyết định đã chốt với người dùng:** chấp nhận lưu thêm 1 bản sao mật khẩu dạng plain-text trong **1 bảng quản trị riêng**, KHÔNG phải bảng nghiệp vụ, để phục vụ tính năng "xem mật khẩu". Đây là đánh đổi có chủ đích cho mục đích demo/debug đồ án — **không phải chuẩn bảo mật production**. Cần ghi rõ comment trong code và trong báo cáo đồ án để không bị hiểu nhầm là sơ suất.

Tầng bảo vệ bắt buộc phải có:
- Bảng quản trị mới chỉ Role `NganHang` (hoặc 1 role admin riêng) được `SELECT`. `ChiNhanh` và `KhachHang` tuyệt đối `DENY`.
- Route API trả password chỉ cho phép gọi bởi user có `NHOM = 'NganHang'` (check ở Middleware Node.js, giống cách `requireRole` đang làm).
- Không bao giờ trả mật khẩu plain-text qua API nếu người gọi không phải admin — kể cả qua DevTools/Network tab.

## 2. Thiết kế Database

### 2.1. Bảng quản trị mới: `QuanTriLogin`

```sql
USE NGANHANG;
GO

CREATE TABLE dbo.QuanTriLogin (
    LoginName       VARCHAR(50)  NOT NULL PRIMARY KEY,  -- trùng với Login Name thật trên SQL Server
    MatKhauHienTai  VARCHAR(50)  NOT NULL,                -- plain-text, CHỈ phục vụ mục đích xem/debug
    LoaiTaiKhoan    VARCHAR(20)  NOT NULL,                -- 'NhanVien' hoặc 'KhachHang'
    MaThamChieu     VARCHAR(50)  NOT NULL,                -- MANV hoặc CMND tương ứng
    NhomQuyen       VARCHAR(20)  NOT NULL,                -- 'NganHang' / 'ChiNhanh' / 'KhachHang'
    NgayTao         DATETIME     NOT NULL DEFAULT GETDATE(),
    NgayCapNhatMK   DATETIME     NULL                      -- lần reset mật khẩu gần nhất (NULL nếu chưa reset lần nào)
);
GO

-- Chỉ NganHang được xem bảng này
GRANT SELECT ON dbo.QuanTriLogin TO NganHang;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.QuanTriLogin TO ChiNhanh;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.QuanTriLogin TO KhachHang;
GO
```

**Giải thích các cột quan trọng:**
- `LoginName`: khớp 1-1 với Login thật trên SQL Server (NV01, NV02, hoặc CMND khách hàng).
- `MaThamChieu`: để JOIN ngược về bảng `NhanVien`/`KhachHang` khi hiển thị bảng danh sách (lấy Họ Tên, Chi nhánh...).
- `NgayCapNhatMK`: hiển thị trên UI để biết "mật khẩu này có phải mặc định ban đầu hay đã từng đổi".

### 2.2. Vì sao không lưu thẳng cột này vào bảng `NhanVien`/`KhachHang`

Vì đó là bảng nghiệp vụ nằm trong phạm vi phân mảnh/replication của đề bài — không nên trộn dữ liệu bảo mật vào đó. Tách riêng `QuanTriLogin` giúp:
- Không phá cấu trúc bảng đã được chấm điểm theo đúng đề bài gốc (`00_DE3_NGAN_HANG_PhanTan.md`).
- Dễ dàng giải thích khi vấn đáp: "Đây là bảng quản trị phụ trợ, không phải bảng nghiệp vụ, không tham gia phân mảnh."
- Nếu giảng viên yêu cầu bỏ tính năng này để đúng chuẩn, chỉ cần DROP 1 bảng, không ảnh hưởng gì đến phần lõi.

### 2.3. Bảng này có cần tạo ở cả SQL1, SQL2, SQL3 không?

**Có** — tạo giống nhau ở cả 3 server (NGUON/SQL1/SQL2/SQL3, tùy mô hình bạn đang chạy), vì mỗi server có Login/User riêng (Login là cấp Server, không tự đồng bộ — xem `10_Linked_Servers.md` đã có trong tài liệu đồ án). KHÔNG đưa bảng này vào Replication Publication (không cần đồng bộ dữ liệu quản trị xuyên site).

## 3. Sửa Stored Procedure `SP_TaoTaiKhoan` — ghi đồng thời vào `QuanTriLogin`

```sql
ALTER PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME   VARCHAR(50), 
    @PASS     VARCHAR(50), 
    @USERNAME VARCHAR(50), 
    @ROLE     VARCHAR(50),
    @LOAITK   VARCHAR(20),   -- 'NhanVien' hoặc 'KhachHang' — tham số mới
    @MATHAMCHIEU VARCHAR(50) -- MANV hoặc CMND — tham số mới
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

**Lưu ý quan trọng về Replication:** Theo `13_All_Stored_Procedures.md`, `SP_TaoTaiKhoan` đã nằm trong `PUB_TRACUU` Article. Lệnh `ALTER PROCEDURE` này **chỉ được chạy tại server NGUON (Publisher)** — chạy trực tiếp tại Subscriber sẽ bị chặn với lỗi "The batch has been aborted" (xem `17_Su_Co_Va_Xu_Ly.md`, Sự cố 2 đã từng gặp). Sau khi ALTER tại NGUON, đợi Replication tự đẩy xuống các Subscriber.

## 4. Stored Procedure mới: `SP_ResetMatKhau`

```sql
CREATE PROCEDURE [dbo].[SP_ResetMatKhau]
    @LGNAME      VARCHAR(50),
    @MATKHAU_MOI VARCHAR(50) = '123456'   -- mặc định 123456 nếu không truyền
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
GO

GRANT EXECUTE ON dbo.SP_ResetMatKhau TO NganHang;
DENY EXECUTE ON dbo.SP_ResetMatKhau TO ChiNhanh;
DENY EXECUTE ON dbo.SP_ResetMatKhau TO KhachHang;
GO
```

**Vì sao dùng `ALTER LOGIN` thay vì `DROP` + `CREATE` lại:** `ALTER LOGIN ... WITH PASSWORD` đổi mật khẩu tại chỗ, giữ nguyên Login/User/Role mapping đã có — không cần tạo lại User hay gán lại Role, tránh phá liên kết.

## 5. Stored Procedure mới: `SP_DanhSachTrangThaiLogin` (cho bảng theo dõi)

```sql
CREATE PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL   -- NULL = xem tất cả (dành cho NganHang)
AS
BEGIN
    SET NOCOUNT ON;

    -- Danh sách Nhân viên + trạng thái Login
    SELECT 
        'NhanVien' AS LoaiTK,
        nv.MANV AS MaThamChieu,
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
        RTRIM(nv.MACN) AS MACN,
        CASE WHEN ql.LoginName IS NOT NULL THEN 1 ELSE 0 END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM NhanVien nv
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

    UNION ALL

    -- Danh sách Khách hàng + trạng thái Login
    SELECT 
        'KhachHang' AS LoaiTK,
        kh.CMND AS MaThamChieu,
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
        RTRIM(kh.MACN) AS MACN,
        CASE WHEN ql.LoginName IS NOT NULL THEN 1 ELSE 0 END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND) AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;  -- ưu tiên hiện "chưa cấp" lên trước để dễ xử lý
END
GO

GRANT EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO NganHang;
GRANT EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO ChiNhanh;
DENY EXECUTE ON dbo.SP_DanhSachTrangThaiLogin TO KhachHang;
GO
```

Giải thích: `LEFT JOIN` với `QuanTriLogin` — nếu chưa có Login thì các cột `ql.*` sẽ là `NULL`, cờ `DaCapTaiKhoan = 0`. ChiNhanh gọi SP này sẽ tự động chỉ thấy NV/KH chi nhánh mình do truyền `@MACN` tương ứng (giống cách các SP khác trong hệ thống đã làm).

## 6. Route API cần thêm ở Node.js (backend)

| Method | Route | Vai trò gọi | Việc làm | SP gọi |
|---|---|---|---|---|
| GET | `/login-management/list` | NganHang, ChiNhanh | Lấy bảng danh sách trạng thái | `SP_DanhSachTrangThaiLogin` |
| GET | `/login-management/password/:loginName` | Chỉ NganHang | Trả mật khẩu plain-text 1 login để hiện khi bấm icon mắt | `SELECT MatKhauHienTai FROM QuanTriLogin WHERE LoginName = @x` |
| POST | `/login-management/reset-password` | Chỉ NganHang | Reset về mật khẩu mặc định | `SP_ResetMatKhau` |

**Middleware bắt buộc cho 2 route "Chỉ NganHang":**
```javascript
app.get('/login-management/password/:loginName', requireLogin, requireRole('NganHang'), async (req, res) => {
  // ...
});
app.post('/login-management/reset-password', requireLogin, requireRole('NganHang'), async (req, res) => {
  // ...
});
```

Route `/login-management/list` cho phép cả `ChiNhanh` xem (để biết NV/KH chi nhánh mình ai đã có tài khoản), nhưng **không trả cột mật khẩu** trong response của route này — chỉ trả `DaCapTaiKhoan` (cờ Đã/Chưa cấp). Mật khẩu chỉ trả qua route riêng `/password/:loginName`, và route đó tự kiểm tra Role.

## 7. Thiết kế UI (bảng bên dưới form hiện tại)

Thêm 1 bảng dưới 2 panel hiện có:

```
| Loại | Mã (MANV/CMND) | Họ Tên | Chi nhánh | Trạng thái      | Login Name | Mật khẩu        | Ngày cấp   | Thao tác          |
|------|-----------------|--------|-----------|------------------|------------|------------------|------------|--------------------|
| NV   | NV01            | ...    | BENTHANH  | Đã cấp           | NV01       | ****** (eye)     | 01/06/2026 | Reset mật khẩu     |
| NV   | NV04            | ...    | BENTHANH  | Chưa cấp         | —          | —                | —          | Cấp tài khoản      |
| KH   | 0123456789      | ...    | BENTHANH  | Đã cấp           | 0123456789 | ****** (eye)     | 15/05/2026 | Reset mật khẩu     |
```

**Hành vi:**
- Cột "Mật khẩu": mặc định hiện dạng che (`******`). Bấm icon mắt → gọi `GET /login-management/password/:loginName` → hiện plain-text. Bấm lại → ẩn lại (không cần gọi lại API, giữ trong state).
- Nút "Reset mật khẩu": hiện confirm dialog ("Đặt lại mật khẩu về 123456 cho NV01?") → gọi `POST /login-management/reset-password` → cập nhật lại dòng đó trong bảng (load lại password mới = 123456, set `NgayCapNhatMK` = hiện tại).
- Nút "Cấp tài khoản" (dòng chưa có Login): bấm để mở lại form phía trên, tự động fill sẵn MANV/CMND tương ứng — tái dùng form hiện có, không cần làm form mới.
- Nếu user đang login là `ChiNhanh`: ẩn hẳn cột "Mật khẩu" và nút "Reset mật khẩu" (vì backend cũng chặn rồi, nhưng ẩn ở UI để trải nghiệm sạch — đúng nguyên tắc 3 tầng bảo mật đã làm xuyên suốt hệ thống).

## 8. Việc cần làm theo thứ tự (checklist cho Antigravity)

- [x] Tạo bảng `QuanTriLogin` ở SQL1, SQL2, SQL3 (hoặc đúng các instance đang dùng) + GRANT/DENY như mục 2.1
- [x] `ALTER PROCEDURE SP_TaoTaiKhoan` tại server NGUON (Publisher) — thêm 2 tham số `@LOAITK`, `@MATHAMCHIEU` — đợi Replication đẩy xuống
- [x] Tạo mới `SP_ResetMatKhau` (tạo ở từng instance, hoặc tại NGUON nếu muốn đưa vào Replication sau)
- [x] Tạo mới `SP_DanhSachTrangThaiLogin` (tương tự)
- [x] Sửa code Node.js gọi `SP_TaoTaiKhoan` — truyền thêm `LOAITK` (`'NhanVien'`/`'KhachHang'`) và `MATHAMCHIEU` (MANV hoặc CMND đang chọn ở dropdown)
- [x] Thêm 3 route API mới (mục 6) + middleware `requireRole('NganHang')` đúng chỗ
- [x] Thêm bảng UI bên dưới form (mục 7), gồm toggle xem mật khẩu + nút reset, thêm tính năng Tìm kiếm/Filter trực tiếp trên giao diện.
- [x] Test: login NganHang → thấy đủ cột mật khẩu + nút reset. Login ChiNhanh → không thấy 2 thứ đó (cả UI và thử gọi thẳng API bằng Postman để xác nhận backend cũng chặn, không chỉ ẩn ở giao diện)

## 9. Điểm dễ bị hỏi vấn đáp (chuẩn bị trước)

**Q: Lưu mật khẩu dạng plain-text trong DB có đúng chuẩn bảo mật không?**
A: Không đúng chuẩn production. Đây là tính năng quản trị phụ trợ phục vụ demo/kiểm thử trong phạm vi đồ án, tách riêng vào 1 bảng `QuanTriLogin` không thuộc nhóm bảng nghiệp vụ của đề bài, và bị giới hạn quyền chỉ Role NganHang được xem. Hệ thống thật sẽ không bao giờ lưu mật khẩu dạng đọc được — chỉ nên dùng cơ chế "reset về mặc định" mà không có "xem lại mật khẩu cũ".

**Q: Vì sao không lấy lại được mật khẩu gốc từ chính SQL Server?**
A: SQL Server lưu mật khẩu Login dưới dạng hash một chiều (one-way hash), không thể giải mã ngược. Đây là nguyên lý bảo mật chuẩn — kể cả quản trị viên cấp cao nhất (sa) cũng không xem lại được mật khẩu cũ, chỉ có thể đặt lại (reset) bằng `ALTER LOGIN`.

**Q: Bảng QuanTriLogin có tham gia phân mảnh/replication không?**
A: Không. Đây là bảng quản trị cục bộ tại từng server, phục vụ riêng cho từng instance, không nằm trong phạm vi phân mảnh dữ liệu nghiệp vụ của đề bài và không cần đồng bộ chéo giữa các site.
