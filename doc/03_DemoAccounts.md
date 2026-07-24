# Tài Khoản Demo — Hệ Thống Ngân Hàng

Tất cả tài khoản dưới đây dùng để đăng nhập vào web app tại `http://localhost:3001`.
Xác thực bằng **SQL Server Authentication** — LoginName chính là tên SQL Login thực tế trên các instance.

---

## Tổng quan Roles

| Role | Mô tả quyền hạn |
|------|-----------------|
| `NganHang` | Ban Giám Đốc / Quản trị — `SELECT` toàn schema, `EXECUTE` SP báo cáo. `DENY INSERT/UPDATE/DELETE` cấp DB. Được tạo TK cùng nhóm + đổi role. |
| `ChiNhanh` | Nhân viên chi nhánh — CRUD trên `KhachHang`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN`, `NhanVien`. `SELECT` `ChiNhanh`. `EXECUTE` toàn bộ SP nghiệp vụ. |
| `KhachHang` | Khách hàng — KHÔNG có `SELECT` trực tiếp trên bất kỳ bảng nào. Chỉ được `EXECUTE` 3 SP: `sp_TaiKhoanKhachHang`, `SP_SaoKeTaiKhoan`, `sp_Login_App`. |

Xem chi tiết phân quyền tại [`11_Security_Authorization.md`](11_Security_Authorization.md).

---

## 1. Tài khoản Admin (Ban Giám Đốc)

| Trường | Giá trị |
|---|---|
| SQL Login | `admin` |
| Mật khẩu | `1` |
| Role | `NganHang` |
| Server Role | `securityadmin` (để tạo/reset login qua UI) |
| Server thực tế khi login | `ES-HAITD16\SQL3` (TRACUU) — tự gán bởi `auth.js` bất kể chi nhánh chọn trên form |
| Khi login | `sp_Login_App` trả về `MANV='admin'`, `HOTEN='Quan Tri Vien (Ban Giam Doc)'`, `MACN='TRACUU'` |

**Script tạo/đảm bảo:** [`sql/setup/09_TaoTaiKhoanAdmin.sql`](../sql/setup/09_TaoTaiKhoanAdmin.sql) — chạy trên cả 4 SQL instance (login là đối tượng cấp Server, không có trong Replication).

---

## 2. Tài khoản Nhân viên Chi nhánh (demo)

Nhân viên đăng nhập bằng **MANV** làm SQL Login. Mật khẩu demo: **`1`**. Role: `ChiNhanh`.

### Chi nhánh Bến Thành — server `ES-HAITD16\SQL1`

| SQL Login | Password | Ghi chú |
|---|---|---|
| `BT001` | `1` | Nhân viên BT #1 |
| `BT002` | `1` | Nhân viên BT #2 |
| `BT003` | `1` | Nhân viên BT #3 |

### Chi nhánh Tân Định — server `ES-HAITD16\SQL2`

| SQL Login | Password | Ghi chú |
|---|---|---|
| `TD001` | `1` | Nhân viên TD #1 |
| `TD002` | `1` | Nhân viên TD #2 |
| `TD003` | `1` | Nhân viên TD #3 |
| `TD004` | `1` | Nhân viên TD #4 |

**Yêu cầu ràng buộc:**
- LoginName phải trùng `MANV` trong bảng `NhanVien` để `sp_Login_App` tìm được thông tin nhân viên.
- Nhân viên phải có `TrangThaiXoa = 0` (đang làm việc).
- Prefix `BT`/`TD` được đảm bảo bởi `sinhMANV()` trong `routes/nhanvien.js` — tránh trùng MANV khi chuyển NV giữa 2 chi nhánh.

**Script tạo:** [`sql/setup/10_TaoTaiKhoanNhanVien_Demo.sql`](../sql/setup/10_TaoTaiKhoanNhanVien_Demo.sql) — chạy trên **cả 4 instance** (cần login tồn tại ở mọi site để Linked Server + fan‑out hoạt động).

**Quyền cấp DB** cho role `ChiNhanh` (theo [`sql/setup/04_Role_PhanQuyen.sql`](../sql/setup/04_Role_PhanQuyen.sql)):
- `SELECT, INSERT, UPDATE, DELETE` trên: `GD_CHUYENTIEN`, `GD_GOIRUT`, `KhachHang`, `TaiKhoan`, `NhanVien`
- `SELECT` trên: `ChiNhanh`
- `EXECUTE` toàn bộ schema `dbo`

---

## 3. Tài khoản Khách hàng (demo)

Khách hàng đăng nhập bằng **CMND** làm SQL Login. Mật khẩu demo: **`123456`**. Role: `KhachHang`.

> ⚠️ **Lưu ý về mật khẩu:** Với KH được tạo qua form (`POST /khachhang/them`), route dùng `MACPIN` do người dùng nhập; nếu để trống → password = CMND. Với các tài khoản demo được tạo qua script `11_TaoTaiKhoanKhachHang_Demo.sql`, password được cứng = `123456`.

### Khách hàng Bến Thành (`MACN = 'BENTHANH'`)

| SQL Login (CMND) | Password | Họ tên |
|---|---|---|
| `1111111111` | `123456` | Nguyễn Văn An |
| `0011223344` | `123456` | Trần Đức Hải |

### Khách hàng Tân Định (`MACN = 'TANDINH'`)

| SQL Login (CMND) | Password | Họ tên |
|---|---|---|
| `2222222222` | `123456` | Lê Thị Bình |
| `0099887766` | `123456` | Lê Thảo Trang |
| `3333333333` | `123456` | Nguyễn Văn Hoàng |
| `4444444444` | `123456` | Hoàng Văn Thái |

**Script tạo:** [`sql/setup/11_TaoTaiKhoanKhachHang_Demo.sql`](../sql/setup/11_TaoTaiKhoanKhachHang_Demo.sql) — chạy trên **cả 4 instance** (để KH login được từ bất kỳ site nào; đặc biệt là TRACUU nếu cần).

**Quyền cấp DB** cho role `KhachHang`:
- **KHÔNG** có `SELECT` trực tiếp trên bất kỳ bảng nào.
- `EXECUTE` **chỉ 3 SP**:
  - `sp_Login_App` — bắt buộc để đăng nhập
  - `sp_TaiKhoanKhachHang` — xem danh sách TK của mình (SP tự lọc theo `@CMND`)
  - `SP_SaoKeTaiKhoan` — xem sao kê 1 TK (route pre‑check ownership qua `sp_TaiKhoanKhachHang`)

---

## 4. Tài khoản hệ thống — `HTKN`

**Không phục vụ đăng nhập UI**. Được dùng bởi:
- Backend `db.js:getAdminPool()` cho các thao tác DDL cấp Server (CREATE LOGIN, ALTER LOGIN…)
- Backend `db.js:execSPAdmin()` cho các SP có `BEGIN DISTRIBUTED TRANSACTION` (chạy qua `sqlcmd`)
- **Security Mapping** của tất cả Linked Server (LINK0/LINK1/LINK2) — xem [`10_Linked_Servers.md`](10_Linked_Servers.md) mục 4

| Trường | Giá trị |
|---|---|
| SQL Login | `HTKN` |
| Mật khẩu | `123` (đồng nhất trên mọi instance) |
| Server Role | `sysadmin` (hoặc `securityadmin`) |
| Yêu cầu | Phải tồn tại + đúng mật khẩu trên **cả 4 instance** — vì Login là đối tượng cấp Server, KHÔNG có trong Replication |

---

## 5. Khởi tạo lại toàn bộ tài khoản demo

Chạy tuần tự các script (thay `TEN_SERVER` bằng tên instance thực tế):

```bat
:: Bước 1 — Roles + phân quyền (chạy trên CẢ 4 instance)
sqlcmd -S ES-HAITD16       -E -d NGANHANG -i sql\setup\04_Role_PhanQuyen.sql
sqlcmd -S ES-HAITD16\SQL1  -E -d NGANHANG -i sql\setup\04_Role_PhanQuyen.sql
sqlcmd -S ES-HAITD16\SQL2  -E -d NGANHANG -i sql\setup\04_Role_PhanQuyen.sql
sqlcmd -S ES-HAITD16\SQL3  -E -d NGANHANG -i sql\setup\04_Role_PhanQuyen.sql

:: Bước 2 — Tài khoản admin + HTKN (chạy trên CẢ 4 instance)
sqlcmd -S ES-HAITD16       -E -i sql\setup\09_TaoTaiKhoanAdmin.sql
sqlcmd -S ES-HAITD16\SQL1  -E -i sql\setup\09_TaoTaiKhoanAdmin.sql
sqlcmd -S ES-HAITD16\SQL2  -E -i sql\setup\09_TaoTaiKhoanAdmin.sql
sqlcmd -S ES-HAITD16\SQL3  -E -i sql\setup\09_TaoTaiKhoanAdmin.sql

:: Bước 3 — Tài khoản nhân viên demo (chạy trên CẢ 4 instance)
sqlcmd -S ES-HAITD16       -E -i sql\setup\10_TaoTaiKhoanNhanVien_Demo.sql
sqlcmd -S ES-HAITD16\SQL1  -E -i sql\setup\10_TaoTaiKhoanNhanVien_Demo.sql
sqlcmd -S ES-HAITD16\SQL2  -E -i sql\setup\10_TaoTaiKhoanNhanVien_Demo.sql
sqlcmd -S ES-HAITD16\SQL3  -E -i sql\setup\10_TaoTaiKhoanNhanVien_Demo.sql

:: Bước 4 — Tài khoản khách hàng demo (chạy trên CẢ 4 instance)
sqlcmd -S ES-HAITD16       -E -i sql\setup\11_TaoTaiKhoanKhachHang_Demo.sql
sqlcmd -S ES-HAITD16\SQL1  -E -i sql\setup\11_TaoTaiKhoanKhachHang_Demo.sql
sqlcmd -S ES-HAITD16\SQL2  -E -i sql\setup\11_TaoTaiKhoanKhachHang_Demo.sql
sqlcmd -S ES-HAITD16\SQL3  -E -i sql\setup\11_TaoTaiKhoanKhachHang_Demo.sql
```

> **Tại sao phải chạy trên cả 4 instance?** Vì Login là **object cấp Server**, KHÔNG được Replication đồng bộ (Replication chỉ đồng bộ object cấp Database). Tạo login trên NGUON không tự tạo được ở SQL1/SQL2/SQL3.
