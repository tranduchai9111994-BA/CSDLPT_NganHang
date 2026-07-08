# 🏦 Đồ Án Quản Lý Ngân Hàng - CSDL Phân Tán

Hệ thống Quản lý Ngân Hàng mô phỏng hoạt động thực tế với kiến trúc **Cơ sở dữ liệu phân tán (Distributed Database)** trên SQL Server và nền tảng Web Application xây dựng bằng Node.js. 

Hệ thống đảm bảo tính toàn vẹn dữ liệu (ACID) tuyệt đối trong môi trường phân tán (thông qua MSDTC), áp dụng các kỹ thuật tối ưu hóa truy vấn nâng cao (Window Functions) và quản trị bảo mật sát với thực tế bằng SQL Authentication.

---

## 🏗️ Kiến Trúc Hệ Thống

Dự án được phân mảnh thành 4 Site chính (Instance) trên SQL Server:
1. **`NGUON` (Publisher)**: Lưu trữ dữ liệu gốc, phát hành Replication. Không trực tiếp phục vụ giao dịch.
2. **`BENTHANH` (SQL1 - Phân mảnh 1)**: Xử lý giao dịch cho Chi nhánh Bến Thành.
3. **`TANDINH` (SQL2 - Phân mảnh 2)**: Xử lý giao dịch cho Chi nhánh Tân Định.
4. **`TRACUU` (SQL3 - Server Báo Cáo)**: Chứa bản hợp nhất của bảng Khách Hàng, phục vụ nhóm Ngân Hàng tra cứu toàn cục. 

Giao tiếp liên chi nhánh (chuyển tiền, sao kê) được thực hiện thông qua mạng lưới **Linked Server** an toàn.

---

## 🚀 Các Tính Năng Nổi Bật

### 1. Phân Quyền Bảo Mật Sâu (SQL Authentication)
- Thay vì dùng 1 tài khoản hệ thống (App Authentication), ứng dụng tạo kết nối CSDL bằng chính **SQL Login** của từng Nhân viên / Khách hàng.
- Stored Procedure `sp_Login_App` map trực tiếp Login với người dùng thông qua `sys.database_principals` và `sys.database_role_members`.
- 3 cấp độ Role:
  - **NganHang**: Chỉ tra cứu, báo cáo. Không được thêm/xóa/sửa.
  - **ChiNhanh**: Toàn quyền nghiệp vụ tại chi nhánh của mình.
  - **KhachHang**: Chỉ xem được sao kê tài khoản của chính mình.

### 2. Giao Dịch Chuyển Tiền Phân Tán (Distributed Transaction)
- Giao dịch liên chi nhánh được bọc trong lệnh `BEGIN DISTRIBUTED TRAN` và `SET XACT_ABORT ON`.
- Kích hoạt **MSDTC (Microsoft Distributed Transaction Coordinator)**, đảm bảo nguyên tắc Two-Phase Commit: Nếu đứt kết nối mạng giữa 2 chi nhánh, toàn bộ giao dịch tại 2 đầu tự động Rollback, không gây sai lệch dữ liệu.

### 3. Tối Ưu Báo Cáo Sao Kê (Window Functions)
- Giải quyết bài toán tính Số dư lũy kế mà không dùng vòng lặp (Cursor) hay JavaScript.
- Kéo dữ liệu qua Linked Server kết hợp với **Window Functions (`SUM() OVER`)** của SQL Server để tự động tính lùi số dư đầu kỳ và số dư từng dòng giao dịch cực kỳ tối ưu.

### 4. Giao Diện Chuẩn Master-Detail & Flexbox
- Thiết kế **Master-Detail (SubForm)** trong nghiệp vụ Mở Tài Khoản.
- Form Tạo Tài Khoản (Login) phân chia 2 cột an toàn tuyệt đối với mọi trình duyệt nhờ Pure CSS Flexbox.

---

## 💻 Cài Đặt Và Vận Hành

### Yêu Cầu Môi Trường
- **Node.js** (Phiên bản 14+ trở lên)
- **SQL Server** (Đã cài đặt Replication và cấu hình đủ 4 Instances, bật MSDTC)

### Các Bước Chạy Ứng Dụng
1. Clone dự án về máy.
2. Di chuyển vào thư mục `APP_NGANHANG`:
   ```bash
   cd APP_NGANHANG
   ```
3. Cài đặt các gói thư viện cần thiết:
   ```bash
   npm install
   ```
4. Đảm bảo file cấu hình `db.js` có đúng tên Server (`ES-HAITD16`, `ES-HAITD16\SQL1`, v.v..) khớp với máy thực tế.
5. Khởi động Web Server:
   ```bash
   npm start
   ```
6. Truy cập ứng dụng tại: `http://localhost:3001`

---

## 📚 Hệ Thống Tài Liệu Kỹ Thuật

Bộ tài liệu chi tiết được đính kèm trong thư mục `/doc/` để giải thích ngọn ngành kiến trúc, quy trình xử lý sự cố và báo cáo bảo vệ:
- `architecture.md`: Tổng quan kiến trúc MVC và cấu trúc file.
- `database_diagram.md`: Sơ đồ ERD bằng Mermaid.
- `database_schema.md`: Đặc tả các bảng và cấu trúc Stored Procedures.
- `database_replication.md`: Thông số cấu hình Transactional Replication.
- `database_connection.md` & `linked_servers.md`: Sơ đồ mạng lưới Linked Server và cách lấy Connection.
- `security_authorization.md` & `Account.md`: Phân quyền chặt chẽ bằng SQL Authentication.
- `modules_routing.md`: Đặc tả các module nghiệp vụ Node.js.
- `Reports_Checklist.md`: Tiến độ thực hiện các chức năng báo cáo, sao kê.
- `SP_Sync_Status.md`: Báo cáo giám sát hiện trạng đồng bộ SP.
- `Su_Co_Va_Xu_Ly.md`: Các kịch bản và cách rà soát lỗi Database phức tạp.
- `18_DanhGia_CoChePhanTan.md`: **Đánh giá cơ chế phân tán** — rà soát toàn bộ logic source code & DB (Linked Server, Replication, Stored Procedure, Phân quyền), chỉ ra các điểm đang xử lý bằng code thay vì theo cơ chế phân tán và đưa ra khuyến nghị xử lý (ưu tiên theo mức độ).
