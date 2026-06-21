# 🧩 Chi Tiết Các Module Nghiệp Vụ (Routes)

Tất cả các chức năng nghiệp vụ được tách ra thành từng file riêng trong thư mục `routes/` để dễ bảo trì.

## 1. `auth.js` (Xác thực)
- Xử lý đăng nhập. Xác định user thuộc nhóm nào bằng cách truy vấn View hệ thống (`sys.database_role_members`) hoặc kiểm tra tài khoản NV/KH.
- Gọi SP `sp_Login_App`.
- Gán thông tin (MANV, HOTEN, NHOM, MACN, SERVER) vào `req.session.user`.

## 2. `khachhang.js` (Quản lý Khách Hàng)
- CRUD (Create, Read, Update, Delete). Giao diện tuân thủ đầy đủ các nút chức năng: Thêm, Xóa, Phục hồi (Reset Form / Hủy trạng thái xóa), Ghi, Thoát.
- Nếu nhóm là `NganHang`, kết nối tới Server `TRACUU` để lấy toàn bộ. Nếu là `ChiNhanh`, kết nối Server cục bộ để lấy dữ liệu chi nhánh mình.
- Gọi SP `sp_ThemKhachHang` để thêm mới.

## 3. `nhanvien.js` (Quản lý Nhân Viên)
- Hoạt động tương tự `khachhang.js`. Giao diện tuân thủ đầy đủ các nút chức năng: Thêm, Xóa, Phục hồi (Reset Form / Hủy trạng thái xóa), Ghi, Thoát.
- Có thêm tính năng **Chuyển Chi Nhánh**: gọi SP `sp_ChuyenNhanVien(@MANV, @MACN_MOI)` để chuyển dữ liệu nhân viên từ phân mảnh này sang phân mảnh khác qua Linked Server.
- Có thêm tính năng **Phục hồi**: Cho phép khôi phục lại nhân viên đã xóa/nghỉ việc (`TrangThaiXoa = 0`).

## 4. `taikhoan.js` (Mở Tài Khoản)
- Giao diện được thiết kế chuẩn Master-Detail (SubForm): Chọn khách hàng ở Master, Form mở tài khoản (Detail) hiển thị ngay bên dưới.
- Giao diện tuân thủ đầy đủ các nút chức năng: Thêm, Xóa, Phục hồi (Reset Form / Hủy trạng thái xóa), Ghi, Thoát.
- Tự động sinh `SOTK` bằng cách lấy số TK lớn nhất trong DB cộng thêm 1.
- Gọi SP `sp_MoTaiKhoan`.

## 5. `giaodich.js` (Gửi / Rút / Chuyển tiền)
- Cung cấp form giao dịch. 
- Gửi các lệnh tương ứng vào DB thông qua các SP `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien`. Trong đó `sp_ChuyenTien` có logic phân tán phức tạp nhất (kiểm tra tài khoản nhận có nằm ở chi nhánh khác không và xử lý Distributed Transaction).

## 6. `baocao.js` (Thống kê, Sao kê)
- **Cập nhật Logic Sao Kê Tài Khoản:** Trình bày dữ liệu trả về trực tiếp từ SP_SaoKeTaiKhoan. Toàn bộ logic tính số dư lũy kế đã được đẩy xuống tầng SQL Server xử lý.
- **Liệt kê:** 
  - `GET /baocao/lietke?loai=tk`: Query lấy danh sách tài khoản, kết nối `KhachHang`. **ORDER BY tk.NGAYMOTK DESC**.
  - `GET /baocao/lietke?loai=kh`: Trả về danh sách khách hàng. **ORDER BY MACN, TEN, HO**.
  - Không cần SP vì thao tác lấy danh sách trực tiếp khá nhẹ và ít cần xử lý giao dịch ACID.

## 7. `quantri.js` (Tạo Tài Khoản / Phân Quyền)
- **Chức năng Tạo Tài Khoản (Login):** Giao diện đã được nâng cấp thành thiết kế 2 cột song song (Grid Layout / Flexbox) chuyên nghiệp, hiển thị trực quan cả 2 bảng.
- Dùng Dropdown để chọn trực tiếp Nhân viên hoặc Khách hàng. Trường "Nhóm quyền" (Role) được khóa cứng để hệ thống tự động gán chống sai sót phân quyền.
- **Bảng Theo Dõi Trạng Thái Login:** Dưới form tạo tài khoản là bảng danh sách (Route `GET /quantri/login-management/list`). Bảng hiển thị thông tin những ai đã được cấp tài khoản, ai chưa.
- **Xem / Đặt Lại Mật Khẩu (Chỉ dành cho NganHang):**
  - Route `GET /quantri/login-management/password/:loginName`: trả về mật khẩu plain-text từ bảng `QuanTriLogin`.
  - Route `POST /quantri/login-management/reset-password`: đặt lại mật khẩu về mặc định (`123456`).
  - Route `POST /quantri/login-management/cleanup-sync-error`: dọn dẹp các tài khoản bị lỗi đồng bộ (có trên bảng phụ trợ nhưng Login thật đã mất).
