# Phân Quyền & Bảo Mật (`app.js` & `SQL Server`)

Hệ thống có 3 nhóm quyền chính: **`NganHang`**, **`ChiNhanh`**, **`KhachHang`**. Bảo mật được bảo vệ **3 lớp**: Database Role → Middleware Backend → UI. Cả 3 lớp cùng phối hợp: **UI** ẩn menu (UX), **Middleware** chặn HTTP 403, **DB Role** khóa cứng dù kết nối SSMS trực tiếp.

---

## 1. Lớp 1 — Database Role (Chốt Chặn Cứng)

Đây là lớp phòng thủ cuối cùng và không thể vượt qua — kể cả khi có ai đó bỏ qua middleware bằng cách gọi trực tiếp API hay dùng SSMS đăng nhập bằng SQL Login thật.

### 1.1. Role `NganHang` (Ban Giám Đốc / Toàn Ngân hàng)

- **Chỉ đọc** — `GRANT SELECT` trên các bảng cần thiết + `GRANT EXECUTE` trên SP báo cáo.
- **`DENY INSERT, UPDATE, DELETE`** trên tất cả bảng → không thể thay đổi dữ liệu dù có quyền lên module UI.
- Có quyền EXEC toàn bộ SP quản trị (`SP_ResetMatKhau`, `SP_TaoTaiKhoan`, ...).

### 1.2. Role `ChiNhanh` (Nhân viên chi nhánh)

- `GRANT INSERT/UPDATE/DELETE` trên `KhachHang`, `TaiKhoan`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN` (đúng phạm vi chi nhánh).
- `GRANT EXECUTE` trên toàn bộ SP nghiệp vụ (`sp_ThemKhachHang`, `sp_ChuyenTien`, ...).
- **`DENY EXECUTE`** trên `SP_ResetMatKhau` để tránh lạm quyền reset mật khẩu người khác.

### 1.3. Role `KhachHang` (Khách hàng)

- **Không có `SELECT` trực tiếp** trên bất kỳ bảng nào — buộc phải đi qua SP.
- `GRANT EXECUTE` trên đúng 3 SP an toàn: `sp_Login_App`, `sp_TaiKhoanKhachHang`, `SP_SaoKeTaiKhoan`.
- Mỗi SP tự lọc theo `LOGIN_NAME()` → khách hàng chỉ thấy dữ liệu của mình.

### 1.4. `sp_Login_App` — Cầu nối Login ↔ Role

SP đọc `sys.database_principals` + `sys.database_role_members` để tự động trả về `MANV, HOTEN, NHOM, MACN` từ `LOGIN_NAME()`. `GRANT EXECUTE` cho cả 3 role (bắt buộc, vì được gọi ngay khi đăng nhập cho MỌI user).

---

## 2. Lớp 2 — Middleware Backend (`app.js`)

100% dùng **SQL Authentication cho mọi user** — không có "app authentication" trung gian.

### 2.1. Đăng nhập

- Người dùng nhập `username` (KH có thể nhập `CMND`) + `password` (KH có thể nhập `MACPIN`).
- Backend gọi thẳng `new sql.ConnectionPool({ user, password })` → SQL Server tự xác thực.
- Nếu SQL Server từ chối → backend báo sai mật khẩu.
- Kết nối OK → gọi `sp_Login_App` để lấy `NHOM/MACN/MANV/HOTEN`, đặt vào `req.session.user`.
- **Toàn bộ thao tác về sau chạy dưới danh nghĩa SQL Login của user** → `LOGIN_NAME()` trong SP là chính user đó → audit chính xác đến từng người.

### 2.2. Middleware chặn theo module

```javascript
app.use('/khachhang', requireLogin, requireRole('NganHang', 'ChiNhanh'), khachHangRoutes);
app.use('/nhanvien',  requireLogin, requireRole('NganHang', 'ChiNhanh'), nhanVienRoutes);
app.use('/taikhoan',  requireLogin, requireRole('NganHang', 'ChiNhanh', 'KhachHang'), taiKhoanRoutes);
app.use('/giaodich',  requireLogin, requireRole('NganHang', 'ChiNhanh'), giaoDichRoutes);
app.use('/baocao',    requireLogin, requireRole('NganHang', 'ChiNhanh', 'KhachHang'), baoCaoRoutes);
app.use('/quantri',   requireLogin, requireRole('NganHang'), quanTriRoutes);
```

### 2.3. Middleware chặn theo hành vi ghi

- `requireChiNhanh` bọc quanh mọi POST **thêm/sửa/xóa** trong `khachhang.js`, `nhanvien.js`, `taikhoan.js` → chặn `NganHang` (chỉ được đọc).
- `requireNganHang` bọc quanh các route quản trị nhạy cảm (đổi role, reset mật khẩu).
- Route `POST /quantri/login-management/change-role` **chặn cứng thay đổi role của tài khoản `admin`** (HTTP 403).

---

## 3. Lớp 3 — UI (View)

Trong `layout.ejs` và các trang, dùng `<% if %>` để ẩn menu / nút mà user không có quyền. Chỉ mang tính **trải nghiệm** — không phải bảo mật (kẻ tấn công vẫn có thể tự gõ URL, nhưng sẽ bị lớp 1/2 chặn).

```ejs
<% if (['ChiNhanh', 'NganHang'].includes(user.NHOM)) { %>
  <a href="/khachhang">Quản lý Khách Hàng</a>
<% } %>
```

---

## 4. Quản Lý & Cấp Phát Login

Chức năng "Tạo Tài Khoản" cần quyền server-level (`CREATE LOGIN`, `ALTER LOGIN`) — không giao cho user thường:

- Dùng **Admin Pool** kết nối bằng login `HTKN` (có `sysadmin` hoặc `securityadmin`).
- Chỉ 2 chức năng dùng Admin Pool: **cấp phát tài khoản** và **reset mật khẩu**. Mọi chức năng nghiệp vụ khác đều chạy qua pool của chính user đó (SQL Auth).

### 4.1. Bảng phụ `QuanTriLogin`

SQL Server hash 1 chiều mật khẩu → không đọc lại được. Để phục vụ demo / quản lý đồ án, hệ thống lưu thêm bản sao **plain-text** trong bảng `QuanTriLogin` (không replicate).

- **Cột `LoginName`**: trùng chính xác với SQL Login thực và `MANV` trong `NhanVien` (format: `BT001` cho BENTHANH, `TD001` cho TANDINH).
- **Bảo vệ**: `DENY SELECT` với `ChiNhanh`, `KhachHang`. Chỉ `NganHang` (admin) mới đọc được, qua API bọc bởi `requireNganHang`.
- **Reset mật khẩu qua app**: đặt về `123456` (route `/quantri/login-management/reset-password`).
- **Reset mật khẩu qua script**: đặt về `1` (`sql/setup/reset_password_demo.sql`).

### 4.2. Phân quyền chi tiết các SP quản trị

| SP | NganHang | ChiNhanh | KhachHang |
|---|---|---|---|
| `sp_Login_App` | GRANT | GRANT | GRANT (bắt buộc, dùng lúc đăng nhập) |
| `sp_TaiKhoanKhachHang` | GRANT | GRANT | GRANT (SP tự lọc theo `LOGIN_NAME()`) |
| `SP_SaoKeTaiKhoan` | GRANT | GRANT | GRANT (SP tự lọc theo `LOGIN_NAME()`) |
| `SP_TaoTaiKhoan` | GRANT | GRANT | DENY |
| `SP_DanhSachTrangThaiLogin`, `SP_XoaLoiDongBo` | GRANT | GRANT | DENY |
| `SP_ResetMatKhau` | **GRANT** | **DENY** | DENY |
| `sp_ChuyenNhanVien`, `SP_PhucHoiNhanVien` | GRANT | GRANT | DENY |

---

## 5. Script Cấp Quyền `sql/setup/04_Role_PhanQuyen.sql`

Script được viết theo hướng **an toàn khi chạy lại nhiều lần** (idempotent) — không xóa quyền đăng nhập của user hiện có:

1. **Tạo role có điều kiện**: chỉ `CREATE ROLE` khi role chưa tồn tại (`IF DATABASE_PRINCIPAL_ID(...) IS NULL`) — giữ nguyên toàn bộ member cũ.
2. **Revoke động rồi grant lại**: trước khi GRANT, đọc `sys.database_permissions` để revoke toàn bộ quyền hiện có của 3 role → GRANT lại từ đầu. Cách này không cần biết danh sách quyền cũ, luôn về đúng thiết kế.
3. **Bọc `IF OBJECT_ID(...) IS NOT NULL`** cho các GRANT theo bảng cụ thể → tránh batch abort trên TRACUU (không có local `TaiKhoan`, `NhanVien`, `GD_*`, `ChiNhanh`).

Kết quả: có thể chạy lại script này trên bất kỳ site nào, bất kỳ lúc nào, mà không làm rớt login đang hoạt động.

---

## 6. Nguyên Tắc "Permission Drift"

Trong quá trình dev, dễ có tình trạng quyền được cấp tay qua SSMS rồi quên đưa vào script nguồn → khi deploy môi trường mới sẽ lệch. Cơ chế "revoke động rồi grant lại" ở mục 5 chính là biện pháp phòng chống drift: **script nguồn luôn là sự thật duy nhất**.

Rà soát định kỳ:
- Đăng nhập bằng user thường (BT001, KH_...), thử `SELECT * FROM TaiKhoan` → phải bị denied nếu là `KhachHang`.
- Test-case TC-09a: `KhachHang` không được `SELECT * FROM TaiKhoan` (dù có thể query SP `sp_TaiKhoanKhachHang`).
