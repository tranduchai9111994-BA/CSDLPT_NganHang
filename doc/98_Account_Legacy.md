# Danh Sách Tài Khoản và Quản Trị Login

Tài liệu mô tả chi tiết quyền hạn, cơ chế đăng nhập và khả năng quản trị tài khoản của từng nhóm người dùng theo đúng đặc tả yêu cầu của hệ thống CSDL Phân Tán.

## 1. Nhóm NganHang (Ban Giám Đốc / Hội Sở)
- **Cơ chế xác thực:** **SQL Authentication** (Bắt buộc phải tạo Login thực tế trên SQL Server).
- **Quyền hạn Dữ liệu (Mức UI & DB):** 
  - Khi đăng nhập, user nhóm này có thể **chọn bất kỳ chi nhánh nào** (BENTHANH, TANDINH) trên giao diện (thông qua ComboBox) để xem các báo cáo và tìm kiếm dữ liệu. Dữ liệu sẽ được truy vấn trên phân mảnh tương ứng thông qua Linked Server hoặc tra cứu khách hàng tại mảnh TRACUU.
  - Bị chặn tuyệt đối các thao tác thay đổi dữ liệu (`DENY INSERT, UPDATE, DELETE`). Xóa bỏ mọi liên quan đến Token JWT (hệ thống dùng 100% Session).
- **Quyền Quản Trị (Tạo Tài Khoản):** 
  - **Được phép** sử dụng form Tạo Tài Khoản.
  - **Giới hạn:** Chỉ được phép tạo tài khoản mới thuộc **cùng nhóm NganHang**.

## 2. Nhóm ChiNhanh (Giao Dịch Viên)
- **Cơ chế xác thực:** **SQL Authentication** (Tạo Connection trực tiếp bằng User/Pass của nhân viên).
- **Quyền hạn Dữ liệu (Mức UI & DB):** 
  - Chỉ cho phép **toàn quyền làm việc trên chi nhánh đã đăng nhập** (Thêm/Xóa/Sửa dữ liệu giao dịch, tài khoản, khách hàng). 
  - Không được phép chọn chi nhánh khác để xem báo cáo như nhóm NganHang (ComboBox chọn chi nhánh sẽ bị khóa/ẩn trên giao diện).
- **Quyền Quản Trị (Tạo Tài Khoản):**
  - **Được phép** sử dụng form Tạo Tài Khoản.
  - **Giới hạn:** Chỉ được phép tạo tài khoản mới thuộc **cùng nhóm ChiNhanh** tại phân mảnh mà họ đang làm việc.

## 3. Nhóm KhachHang (Người Dùng Cuối)
- **Cơ chế xác thực:** **SQL Authentication** (Tự động tạo Login trên SQL Server giới hạn quyền thông qua Role KhachHang).
  - Đăng nhập bằng CMND (Login Name) và Mã PIN (Password).
  - Backend mở Connection Pool trực tiếp bằng tài khoản của Khách Hàng thay vì dùng tài khoản hệ thống (HTKN).
- **Quyền hạn Dữ liệu:** Chỉ được phép **xem Sao kê tài khoản của chính mình** (có quyền EXECUTE trên SP_SaoKeTaiKhoan). Mọi thao tác khác bị từ chối ở cấp CSDL.
- **Quyền Quản Trị (Tạo Tài Khoản):** **Không được phép** truy cập form Tạo Tài Khoản.

---
**Lưu ý Kỹ Thuật (SP_TaoTaiKhoan):**
Chương trình sẽ sử dụng một Stored Procedure dùng chung là `SP_TaoTaiKhoan` chạy dưới Database. Khi giao diện gọi SP này, nó sẽ truyền thông tin Login, Password, Tên User và Role tương ứng. SP sẽ thực thi các lệnh `CREATE LOGIN`, `CREATE USER` và `sp_addrolemember` để cấp quyền tự động dựa theo nhóm người dùng.