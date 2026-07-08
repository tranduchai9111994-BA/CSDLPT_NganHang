# 🧩 Chi Tiết Các Module Nghiệp Vụ (Routes)

Tất cả các chức năng nghiệp vụ được tách ra thành từng file riêng trong thư mục `routes/` để dễ bảo trì.

> 📌 **Liên quan phân tán:** Một số module (`taikhoan.js` tổng hợp TK cho NganHang, `baocao.js` sao kê không chọn TK, fan-out cấp Login trong `quantri.js`/`khachhang.js`) đang xử lý **tổng hợp/điều phối xuyên mảnh tại tầng Node** thay vì bằng SP + Linked Server. Đánh giá chi tiết và khuyến nghị: [`18_DanhGia_CoChePhanTan.md`](18_DanhGia_CoChePhanTan.md) mục #4.

## 1. `auth.js` (Xác thực)
- Xử lý đăng nhập. Xác định user thuộc nhóm nào bằng cách truy vấn View hệ thống (`sys.database_role_members`) hoặc kiểm tra tài khoản NV/KH.
- Gọi SP `sp_Login_App`.
- Gán thông tin (MANV, HOTEN, NHOM, MACN, SERVER) vào `req.session.user`.

## 2. `khachhang.js` (Quản lý Khách Hàng)
- **NganHang**: Chỉ xem danh sách toàn hệ thống (query `TRACUU`). **Không** thêm/sửa/xóa.
- **ChiNhanh**: Toàn quyền CRUD — xem/thêm/sửa/xóa khách hàng trong chi nhánh mình (query server cục bộ).
- Các route ghi (`GET/POST /them`, `GET/POST /sua`, `POST /xoa`) được bảo vệ bởi middleware `requireChiNhanh` — NganHang bị chặn HTTP 403 ngay tại route, không chỉ ở tầng UI.
- Gọi SP `sp_ThemKhachHang` để thêm mới.
- **Form thêm mới (views/khachhang/form.ejs):** Thứ tự trường được tối ưu — Họ/Tên → Địa chỉ → Giới tính/Ngày cấp → SĐT → CMND/Mã PIN (ở dưới cùng). CMND để trống không có placeholder tránh browser autocomplete nhầm. Ô Mã PIN có nút mắt 👁 để hiện/ẩn ký tự. Toàn form dùng `autocomplete="off"`.

## 3. `nhanvien.js` (Quản lý Nhân Viên)
- **NganHang**: Chỉ xem danh sách toàn hệ thống — gọi `querySP(req, 'TRACUU', 'sp_DanhSachNhanVien', {})` — SP chạy trên TRACUU đọc NhanVien qua LINK1+LINK2 (TRACUU không có NhanVien local). **Không** thêm/sửa/xóa/chuyển CN/phục hồi.
- **ChiNhanh**: Toàn quyền — thêm/sửa/xóa/chuyển chi nhánh/phục hồi nhân viên trong chi nhánh mình.
- Tất cả route ghi (`/them`, `/sua`, `/xoa`, `/chuyen`, `/phuchoi`) được bảo vệ bởi middleware `requireChiNhanh`.
- **Tính năng Thêm Mới:** Tự động sinh Mã Nhân Viên (`MANV`) theo định dạng chi nhánh — prefix `BT` cho BENTHANH (`BT001`, `BT002`...), prefix `TD` cho TANDINH (`TD001`, `TD002`...). Đảm bảo không trùng khi chuyển nhân viên qua lại giữa 2 chi nhánh. Hàm `sinhMANV()` query `TOP 1 MANV LIKE prefix%` rồi tăng số thứ tự.
- Có thêm tính năng **Chuyển Chi Nhánh**: gọi SP `sp_ChuyenNhanVien(@MANV, @MACN_MOI)` để chuyển dữ liệu nhân viên từ phân mảnh này sang phân mảnh khác qua Linked Server (sử dụng `sqlcmd` qua hàm `execSPAdmin` do hạn chế của driver Node.js với Distributed Transaction).
- Có thêm tính năng **Phục hồi**: Cho phép khôi phục lại nhân viên đã xóa/nghỉ việc (`TrangThaiXoa = 0`).

## 4. `taikhoan.js` (Mở Tài Khoản)
- **NganHang**: Chỉ xem danh sách toàn hệ thống (gộp qua SP `sp_DanhSachTaiKhoan` trên TRACUU). **Không** mở hoặc xóa tài khoản.
- **ChiNhanh**: Xem **tất cả TK** (TaiKhoan nhân bản toàn vẹn, không filter theo MACN) + mở TK mới + xóa TK (khi SODU=0 và không có GD). KhachHang phân mảnh ngang → dùng `getAdminPool()` + LINK1 để hiển thị tên KH cả 2 chi nhánh.
- Route `GET/POST /mo` (mở TK) và `POST /dong` (xóa TK) được bảo vệ bởi `requireChiNhanh` — NganHang bị chặn HTTP 403.
- **Mở TK cross-branch:** Form hiển thị KH từ cả 2 chi nhánh (nhóm theo optgroup). Khi KH thuộc chi nhánh khác → `MACN = chi nhánh KH`, `SOTK` prefix theo **chi nhánh NV** (để phân biệt TK mở cross-branch), INSERT chạy trên server có KH (via `execSPAdmin`) để thỏa FK_TaiKhoan_KhachHang + FK_TaiKhoan_ChiNhanh. TK replicate full sang server đối tác.
- Tự động sinh `SOTK` theo prefix chi nhánh (BT/TD) + số tự tăng 7 chữ số.
- Gọi SP `sp_MoTaiKhoan`.

## 5. `giaodich.js` (Gửi / Rút / Chuyển tiền)
- Cung cấp form giao dịch. Giao diện Gửi/Rút tiền được nâng cấp thiết kế **Tabs đa năng** (Chuyển đổi giữa Gửi và Rút trên cùng 1 trang), tự động hiển thị số dư trực quan với màu sắc tương ứng.
- Dropdown hiển thị **tất cả TK** (TaiKhoan nhân bản toàn vẹn, không filter theo MACN) kèm `[MACN]` để phân biệt chi nhánh. NV có thể thực hiện giao dịch cho TK thuộc chi nhánh khác.
- **SP luôn chạy trên server NV** (local) — đảm bảo GD_GOIRUT/GD_CHUYENTIEN ghi đúng mảnh (phân mảnh theo NV). Nếu TK thuộc chi nhánh khác, SP tự UPDATE TK qua LINK1 (Distributed Transaction).
- Gọi SP `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` — cả 3 đều có logic kiểm tra MACN TK vs MACN NV và dùng LINK1 khi cần.

## 6. `baocao.js` (Thống kê, Sao kê)
- **Cập nhật Logic Sao Kê Tài Khoản:** Trình bày dữ liệu trả về trực tiếp từ SP_SaoKeTaiKhoan. Toàn bộ logic tính số dư lũy kế đã được đẩy xuống tầng SQL Server xử lý.
- **Liệt kê:**
  - `GET /baocao/lietke?loai=tk`: Query lấy danh sách tài khoản, kết nối `KhachHang`. **ORDER BY tk.NGAYMOTK DESC**.
  - `GET /baocao/lietke?loai=kh`: Trả về danh sách khách hàng. **ORDER BY MACN, TEN, HO**.
  - Không cần SP vì thao tác lấy danh sách trực tiếp khá nhẹ và ít cần xử lý giao dịch ACID.
- **Tìm kiếm (search):** Form liệt kê KH hỗ trợ tham số `?search=` — lọc theo tên hoặc CMND với `LIKE %keyword%` trên cả 2 cột `HO+TEN` và `CMND`. Áp dụng cho cả nhóm `NganHang` và `ChiNhanh`.

## 7. `quantri.js` (Tạo Tài Khoản / Phân Quyền)
- **Chức năng Tạo Tài Khoản (Login):** Giao diện đã được nâng cấp thành thiết kế 2 cột song song (Grid Layout / Flexbox) chuyên nghiệp, hiển thị trực quan cả 2 bảng.
- Hỗ trợ công cụ tìm kiếm "search-as-you-type" để chọn trực tiếp Nhân viên hoặc Khách hàng khi có quá nhiều dữ liệu, thay cho Select dropdown thông thường. Trường "Nhóm quyền" (Role) được khóa cứng để hệ thống tự động gán chống sai sót phân quyền.
- **Bảng Theo Dõi Trạng Thái Login:** Dưới form tạo tài khoản là bảng danh sách (Route `GET /quantri/login-management/list`). Bảng hiển thị thông tin những ai đã được cấp tài khoản, ai chưa. Có bộ lọc theo Loại, Trạng thái và tìm kiếm text.
- **Xem / Đặt Lại Mật Khẩu (Chỉ dành cho NganHang):**
  - Route `GET /quantri/login-management/password/:loginName`: trả về mật khẩu plain-text từ bảng `QuanTriLogin`.
  - Route `POST /quantri/login-management/reset-password`: đặt lại mật khẩu về mặc định (`123456`) trên tất cả 3 server đồng thời.
  - Route `POST /quantri/login-management/cleanup-sync-error`: dọn dẹp các tài khoản bị lỗi đồng bộ (có trên bảng phụ trợ nhưng Login thật đã mất).
