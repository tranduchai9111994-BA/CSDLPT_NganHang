# Danh sách Tài khoản Demo (CSDLPT_NganHang)

Dưới đây là danh sách các tài khoản demo đã được khởi tạo sẵn trong CSDL để phục vụ cho việc kiểm thử ứng dụng theo từng phân quyền (Role) khác nhau.

## 1. Nhóm Ngân Hàng (Ban Giám Đốc)
Nhóm này có quyền xem dữ liệu trên toàn bộ các chi nhánh nhưng không được phép thêm/xóa/sửa (chỉ có quyền `SELECT`).

- **Tên đăng nhập (Login Name):** `admin`
- **Mật khẩu (Password):** `admin`
- **Quyền (Role):** `NganHang`

## 2. Nhóm Chi Nhánh (Nhân Viên / Giao Dịch Viên)
Nhóm này có toàn quyền (Thêm, Xóa, Sửa, Xem) trên chi nhánh mà họ đang làm việc, nhưng không được xem dữ liệu của chi nhánh khác.

| Tên đăng nhập (Mã NV) | Mật khẩu | Quyền (Role) | Ghi chú |
| :--- | :--- | :--- | :--- |
| `NV01` | `123456` | `ChiNhanh` | Chi nhánh **Bến Thành** (Server SQL1) |
| `NV03` | `123456` | `ChiNhanh` | Chi nhánh **Tân Định** (Server SQL2) |

## 3. Nhóm Khách Hàng
Khách hàng đăng nhập bằng Số CMND và chỉ có quyền xem bản sao kê của chính mình. 
Tài khoản khách hàng được tạo tự động khi nhân viên thực hiện chức năng **Thêm Khách Hàng**.

| Tên đăng nhập (CMND) | Mật khẩu (Mã PIN) | Quyền (Role) | Ghi chú |
| :--- | :--- | :--- | :--- |
| `0123456789` | `123456` | `KhachHang` | Tài khoản mẫu (Bến Thành). Số TK: `111111111` |
| `9876543210` | `123456` | `KhachHang` | Tài khoản mẫu (Tân Định). Số TK: `222222222` |

---
## 4. Danh Sách Đầy Đủ Tất Cả Tài Khoản & Mật Khẩu
Hiện tại, hệ thống đã được nâng cấp tính năng **Quản lý Login**. Do số lượng tài khoản (Nhân viên và Khách hàng) trong hệ thống khá nhiều, bạn **không cần phải nhớ** danh sách trên.
Để xem đầy đủ thông tin:
1. Đăng nhập bằng tài khoản **Ngân Hàng** (`admin` / `admin`).
2. Vào menu **Quản trị**.
3. Cuộn xuống phần **Bảng theo dõi trạng thái cấp tài khoản**. Tại đây bạn có thể thấy danh sách toàn bộ NV/KH, ai đã có Login, ai chưa, kèm theo nút bấm con mắt để **hiển thị mật khẩu gốc** hoặc reset mật khẩu về `123456`.

---
**Lưu ý khi đăng nhập:**
- Trong code Node.js, mật khẩu sẽ được truyền trực tiếp vào SQL Server để kết nối thông qua **SQL Authentication** (Connection Pool).
- Nếu gặp lỗi "Login failed", hãy chắc chắn rằng bạn đã chạy các script tạo tài khoản `09_TaoTaiKhoanAdmin.sql` và `10_TaoTaiKhoanNhanVien_Demo.sql` trên cơ sở dữ liệu của mình.
