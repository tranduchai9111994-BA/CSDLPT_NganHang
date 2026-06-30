# 🔐 Phân Quyền & Bảo Mật (`app.js` & `SQL Server`)

Hệ thống có 3 nhóm quyền chính: `NganHang`, `ChiNhanh`, `KhachHang`.
Bảo mật được thiết lập nhiều lớp từ Frontend, Backend tới tận Database.

> ⚠️ **[Đánh giá 26/06/2026]** Phát hiện lỗ hổng nhất quán: nhóm `KhachHang` có route đọc `TaiKhoan` bằng raw SELECT nhưng role DB **không** được `GRANT SELECT` trên `TaiKhoan` → truy vấn sẽ bị từ chối quyền. Xem khuyến nghị (bọc SP hoặc GRANT + view lọc) tại [`18_DanhGia_CoChePhanTan.md`](18_DanhGia_CoChePhanTan.md) mục #5.

## 1. Mức Cơ Sở Dữ Liệu (Database Level)
Đây là chốt chặn quan trọng nhất để tránh các thao tác nguy hiểm (ví dụ: dùng SQL Injection hoặc kết nối thẳng vào SSMS).
- **Role `NganHang`**: Chỉ có quyền đọc (`GRANT SELECT`) và thực thi SP báo cáo. TUYỆT ĐỐI KHÔNG có quyền Thêm/Xóa/Sửa (`DENY INSERT, UPDATE, DELETE`).
- **Role `ChiNhanh`**: Chỉ được cấp quyền Thêm/Xóa/Sửa trên các bảng Giao dịch (như `GD_CHUYENTIEN`, `KhachHang`, `TaiKhoan`...) và quyền thực thi SP nghiệp vụ.
- Stored Procedure lõi `sp_Login_App` đóng vai trò mapping chính xác giữa **Login (SQL Server)** và **User (CSDL)** thông qua `sys.database_principals` và `sys.database_role_members` để tự động trả về `MANV`, `HOTEN`, `NHOM` (nhóm quyền chuẩn) và `MACN` cực kỳ bảo mật.

## 2. Mức Backend (Application Level - `auth.js`)
Quá trình đăng nhập được thống nhất 100% bằng **SQL Authentication** cho mọi cấp bậc (Khẳng định nhóm `KhachHang` hiện tại cũng được cấp SQL Login thật trên hệ thống và được map vào role `KhachHang`, xóa bỏ hoàn toàn cơ chế "App Authentication" qua tài khoản `HTKN`):
- Hệ thống lấy `username` (hoặc `CMND` đối với Khách Hàng) và `password` (hoặc `Mã PIN` đối với Khách Hàng) mà người dùng nhập trên Web để trực tiếp tạo kết nối vào SQL Server (`new sql.ConnectionPool()`).
- Nếu DB từ chối (sai pass, tài khoản khóa), Backend lập tức báo lỗi.
- Nếu kết nối thành công, hệ thống tiếp tục gọi `sp_Login_App` để truy xuất Role và Map tương ứng.
- Điều này bảo đảm **mọi thao tác** lưu vết xuống cơ sở dữ liệu đều được định danh chính xác đến từng con người cụ thể (Audit) mà không cần đi qua bất kỳ tài khoản hệ thống trung gian nào. Tránh hoàn toàn việc thất thoát bảo mật.

Bên cạnh đó, các Middleware trong NodeJS (như `requireRole`) vẫn được áp dụng chặt chẽ trên mọi Routing để chặn truy cập trái phép qua URL:
```javascript
app.use('/khachhang', requireLogin, requireRole('NganHang', 'ChiNhanh'), khachHangRoutes);
app.use('/giaodich', requireLogin, requireRole('NganHang', 'ChiNhanh'), giaoDichRoutes);
```
Nếu nhóm `KhachHang` cố tình truy cập các link trên, họ sẽ nhận mã lỗi HTTP 403 (Forbidden).

## 3. Quản Lý & Cấp Phát Login (Tính năng đặc biệt)
Tính năng tạo và cấp phát Login (Form "Tạo Tài Khoản") đòi hỏi thao tác cấp Server (`CREATE LOGIN`, `ALTER LOGIN`). Quyền thao tác này không được giao cho các tài khoản NV thông thường. Thay vào đó:
- Hệ thống sử dụng một **Admin Pool** (kết nối ngầm bằng tài khoản SA hoặc tài khoản có quyền `securityadmin`) chỉ riêng cho chức năng cấp phát tài khoản và đặt lại mật khẩu. **Mọi chức năng nghiệp vụ khác** vẫn tuân thủ 100% bằng Pool của chính người dùng (SQL Authentication).
- **Lưu mật khẩu phụ trợ (`QuanTriLogin`)**: SQL Server lưu mật khẩu dưới dạng Hash 1 chiều, không thể đọc lại. Để phục vụ mục đích kiểm thử và quản lý đồ án (ví dụ như quên mật khẩu test), hệ thống chủ động lưu thêm một bản sao mật khẩu dạng plain-text tại bảng độc lập `QuanTriLogin`. Bảng này bị khóa bằng lệnh `DENY SELECT` đối với `ChiNhanh` và `KhachHang`, chỉ `NganHang` (Admin) mới có quyền truy cập thông qua một API được kiểm duyệt chặt chẽ bởi middleware Backend.
  - **Quy ước `LoginName`:** Trường `LoginName` trong `QuanTriLogin` phải trùng khớp với `MANV` trong bảng `NhanVien` và tên SQL Login thực tế. Format: prefix `BT` cho BENTHANH (`BT001`, `BT002`...), prefix `TD` cho TANDINH (`TD001`, `TD002`...). Nếu có lệch pha (do tạo tài khoản trước khi migration), chạy script `sql/setup/migrate_quantrilogin.sql` để đồng bộ lại toàn bộ 3 server.
  - **Reset mật khẩu qua app** đặt về `123456` (hardcode trong route `/quantri/login-management/reset-password`). Reset thủ công qua script đặt về `1` (xem `sql/setup/reset_password_demo.sql`).

### Phân quyền cấp Database (GRANT/DENY) trên các Stored Procedures Quản Trị:
Để đảm bảo an toàn tuyệt đối, bên cạnh việc kiểm tra Middleware ở Node.js, CSDL cũng khóa cứng quyền chạy các SP bằng lệnh `GRANT/DENY`:
- **`sp_Login_App`**: `GRANT EXECUTE` cho cả `NganHang`, `ChiNhanh`, `KhachHang`.
- **`SP_TaoTaiKhoan`**: `GRANT` cho `NganHang`, `ChiNhanh` (Chỉ NV mới được tạo TK). `DENY` cho `KhachHang`.
- **`SP_DanhSachTrangThaiLogin`** & **`SP_XoaLoiDongBo`**: `GRANT` cho `NganHang`, `ChiNhanh`. `DENY` cho `KhachHang`.
- **`SP_ResetMatKhau`**: CHỈ `GRANT` cho `NganHang` (Ban Giám Đốc). `DENY` cho `ChiNhanh` và `KhachHang` để tránh nhân viên lạm quyền đổi pass của người khác.

## 4. Mức Giao Diện (UI - View)
Trong các file `.ejs`, sử dụng thẻ `if` để ẩn/hiện menu dựa trên nhóm quyền, nhằm mang lại trải nghiệm người dùng tốt (không thấy các chức năng không được phép sử dụng):
```ejs
<% if (['ChiNhanh', 'NganHang'].includes(user.NHOM)) { %>
  <a href="/khachhang">Quản lý Khách Hàng</a>
<% } %>
```
