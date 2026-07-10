# 📋 Đối Chiếu Yêu Cầu Đề Bài vs Thực Tế Triển Khai

> **Mục đích:** Đảm bảo không sót yêu cầu nào từ đề bài.  
> **Cách dùng:** Trước khi nộp bài hoặc demo, rà checklist này. Phần nào chưa tick = chưa xong.

---

## A. Cập nhật (CRUD) — 5 yêu cầu

### A1. Cập nhật Nhân viên
> Đề bài: "Form cho phép cập nhật nhân viên. Khi chuyển NV từ chi nhánh này sang chi nhánh kia  
> thì tự động chuyển dữ liệu sang chi nhánh mới (Đổi MACN) đồng thời cập nhật TrangThaiXoa = 1  
> ở chi nhánh cũ."  
> Form phải có đủ: **Thêm, Xóa, Phục hồi, Ghi, Thoát**

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Hiển thị danh sách NV | ✅ | `routes/nhanvien.js` | Lọc theo MACN chi nhánh đang login |
| Thêm nhân viên mới | ⚠️ | Inline query (không có SP riêng) | Nên tạo SP hoặc chuẩn bị giải thích |
| Sửa thông tin NV | ⚠️ | Inline query | Tương tự |
| Xóa NV (đánh dấu TrangThaiXoa=1) | ⚠️ | Inline query | Tương tự |
| Phục hồi NV (TrangThaiXoa=0) | ✅ | `routes/nhanvien.js` | Có nút Phục hồi |
| Chuyển NV sang CN khác | ✅ | `sp_ChuyenNhanVien` | ⚠️ **CẦN SỬA: DELETE → UPDATE** (xem 01_BanVa_SP_Fixes.md) |
| Nút Thoát | ✅ | Frontend (redirect) | |
| Distributed Transaction khi chuyển | ✅ | `BEGIN DISTRIBUTED TRAN` | MSDTC + LINK1 |

### A2. Cập nhật Khách hàng
> Đề bài: "Cập nhật thông tin khách hàng."  
> Form phải có đủ: **Thêm, Xóa, Phục hồi, Ghi, Thoát**

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Hiển thị danh sách KH | ✅ | `routes/khachhang.js` | NganHang xem từ TRACUU, ChiNhanh xem local |
| Thêm KH mới | ✅ | `sp_ThemKhachHang` | |
| Sửa thông tin KH | ⚠️ | Inline query (không có SP riêng) | Chuẩn bị giải thích |
| Xóa KH | ⚠️ | Inline query | |
| Nút Phục hồi (Reset form) | ✅ | Frontend | |
| Nút Thoát | ✅ | Frontend | |

### A3. Mở tài khoản cho khách hàng
> Đề bài: "Thiết kế theo Subform. Form chính = KH, form phụ (grid) = danh sách TK đã mở.  
> Cho phép mở thêm TK mới (tự động sinh số TK)."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Giao diện Master-Detail (Subform) | ✅ | `views/taikhoan/` | Master = KH, Detail = grid TK |
| Tự động sinh SOTK | ✅ | `sp_MoTaiKhoan` hoặc logic Node.js | Lấy MAX(SOTK) + 1 |
| Mở thêm TK mới | ✅ | `sp_MoTaiKhoan` | |
| Nút Thêm/Xóa/Phục hồi/Ghi/Thoát | ✅ | `routes/taikhoan.js` + Frontend | |

### A4. Gửi tiền / Rút tiền
> Đề bài: "Lập phiếu giao dịch. Số tiền gửi/rút > 100.000đ.  
> Phải kiểm tra TK hợp lệ và số dư trước khi cho rút."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Form gửi tiền | ✅ | `views/giaodich/goirut.ejs` | |
| Form rút tiền | ✅ | Cùng form, chọn loại GD | |
| Check số tiền >= 100.000 (gửi) | ✅ | `sp_GuiTien` | `IF @SOTIEN < 100000` |
| Check số tiền >= 100.000 (rút) | ⚠️ | `sp_RutTien` | **CẦN SỬA** (xem 01_BanVa_SP_Fixes.md) |
| Check TK hợp lệ | ✅ | SP kiểm tra `EXISTS` | |
| Check số dư trước khi rút | ✅ | `WHERE SODU >= @SOTIEN` | Atomic trong cùng UPDATE |
| Ghi log vào GD_GOIRUT | ✅ | INSERT trong SP | LOAIGD = 'GT' hoặc 'RT' |

### A5. Chuyển tiền
> Đề bài: "Lập phiếu chuyển tiền nội bộ và liên chi nhánh.  
> Bắt buộc dùng BEGIN DISTRIBUTED TRANSACTION."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Form chuyển tiền | ✅ | `views/giaodich/chuyentien.ejs` | |
| Chuyển cùng chi nhánh | ✅ | `sp_ChuyenTien` (IsNhanLocal=1) | UPDATE 2 TK local |
| Chuyển liên chi nhánh | ✅ | `sp_ChuyenTien` (IsNhanLocal=0) | UPDATE qua LINK1 |
| BEGIN DISTRIBUTED TRANSACTION | ✅ | `sp_ChuyenTien` | |
| SET XACT_ABORT ON | ✅ | `sp_ChuyenTien` | Bắt buộc cho MSDTC |
| Check TK nhận tồn tại (local + remote) | ✅ | SP check cả 2 nơi | |
| Check số dư đủ | ✅ | `WHERE SODU >= @SOTIEN` | |
| Ghi log vào GD_CHUYENTIEN | ✅ | INSERT trong SP | |

---

## B. Liệt kê — Thống kê — 3 yêu cầu

### B1. Sao kê giao dịch 1 tài khoản
> Đề bài: "Sao kê GD của 1 TK trong 1 khoảng thời gian (@tungay, @denngay).  
> Kết xuất: Số dư đầu | Ngày | Loại GD | Số tiền | Số dư sau."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Nhập SOTK, từ ngày, đến ngày | ✅ | `views/baocao/saoke.ejs` | |
| Hiển thị số dư đầu kỳ | ✅ | `SP_SaoKeTaiKhoan` | Kỹ thuật "tính lùi" từ số dư hiện tại |
| Bảng 5 cột đúng format | ✅ | SP trả về đúng format | Window Functions SUM() OVER |
| Số dư cuối kỳ | ✅ | Dòng cuối cùng | |
| Lấy dữ liệu cả local + LINK1 | ✅ | UNION ALL qua Linked Server | Gom GD_GOIRUT + GD_CHUYENTIEN |
| KhachHang chỉ xem TK của mình | ✅ | SP check quyền | |

### B2. Liệt kê tài khoản mở trong khoảng thời gian
> Đề bài: "Liệt kê các TK mở trong 1 khoảng thời gian của chi nhánh, của tất cả CN."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Lọc theo từ ngày, đến ngày | ✅ | `sp_LietKeTaiKhoanTheoNgay` | |
| Lọc theo 1 chi nhánh | ✅ | WHERE MACN = @MACN | |
| Xem tất cả chi nhánh | ✅ | @MACN = NULL | NganHang query từ TRACUU |
| NganHang chọn CN bất kỳ | ✅ | Dropdown trên giao diện | |
| ChiNhanh chỉ xem CN mình | ✅ | Khóa dropdown | |

### B3. Liệt kê khách hàng theo chi nhánh
> Đề bài: "Liệt kê KH theo từng chi nhánh, trong từng CN thì in tăng dần theo họ tên."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Liệt kê theo từng CN | ✅ | `sp_LietKeKhachHang` | |
| Sắp xếp tăng dần theo HO, TEN | ✅ | `ORDER BY MACN, HO, TEN` | |
| NganHang xem tất cả CN | ✅ | UNION ALL local + LINK1 | |
| ChiNhanh xem CN mình | ✅ | WHERE MACN = @MACN | |
| SP có ở TANDINH (SQL2) | ❌ | **THIẾU** | SP chỉ có ở SQL1, cần tạo ở SQL2 |

---

## C. Quản trị — Phân quyền 3 nhóm

### C1. Nhóm NganHang
> Đề bài: "Chọn bất kỳ CN nào để xem báo cáo. Được tạo tài khoản mới cùng nhóm."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Chọn CN bất kỳ xem báo cáo | ✅ | Dropdown + query qua LINK | |
| Tra cứu KH trên TRACUU | ✅ | Kết nối SQL3 | |
| DENY INSERT/UPDATE/DELETE | ✅ | DB Role | |
| Tạo TK mới cùng nhóm NganHang | ✅ | `SP_TaoTaiKhoan` | Form quản trị |
| Tạo TK nhóm ChiNhanh | ✅ | Dropdown Role (NganHang/ChiNhanh) | Ban GĐ cấp quyền linh hoạt |
| Đổi nhóm quyền TK đã tạo | ✅ | `sp_droprolemember` + `sp_addrolemember` | Chỉ NganHang, admin được bảo vệ |

### C2. Nhóm ChiNhanh
> Đề bài: "Toàn quyền làm việc trên CN đã đăng nhập. Được tạo TK mới cùng nhóm."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Toàn quyền CRUD trên CN mình | ✅ | DB Role + Middleware | |
| Không xem CN khác | ✅ | Khóa dropdown CN | |
| Tạo TK mới cùng nhóm ChiNhanh hoặc KhachHang | ✅ | `SP_TaoTaiKhoan` | Backend chặn nếu chọn NganHang |
| KHÔNG được đổi nhóm quyền | ✅ | `requireNganHang` middleware | UI hiện "Không có quyền", API trả 403 |

### C3. Nhóm KhachHang
> Đề bài: "Chỉ xem sao kê của chính TK mình. Không được tạo TK mới."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Xem sao kê TK của mình | ✅ | `SP_SaoKeTaiKhoan` | SP tự check quyền |
| Không thao tác khác | ✅ | DB Role + Middleware + UI | 3 tầng bảo mật |
| Không truy cập form tạo TK | ✅ | `requireRole` chặn | HTTP 403 |
| Đăng nhập bằng CMND + PIN | ✅ | SQL Authentication | |

---

## D. Kiến trúc phân tán — Yêu cầu ngầm

| Yêu cầu | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Phân mảnh ngang theo MACN | ✅ | Replication + Filter | **[Cập nhật 19/06/2026]** Ngoại trừ bảng `TaiKhoan` được nhân bản toàn vẹn (giống `ChiNhanh`) |
| 3 trạm: BenThanh, TanDinh, TraCuu | ✅ | SQL1, SQL2, SQL3 | |
| TraCuu chứa KH cả 2 CN | ✅ | Replicate full bảng KhachHang | |
| Linked Server liên kết các mảnh | ✅ | LINK0/LINK1/LINK2 | |
| Distributed Transaction | ✅ | MSDTC + BEGIN DISTRIBUTED TRAN | |
| Replication từ Publisher | ✅ | NGUON là Publisher | |

---

## E. Giao diện — Yêu cầu form

| Yêu cầu | Trạng thái | Ghi chú |
|---|---|---|
| Mỗi form có: Thêm, Xóa, Phục hồi, Ghi, Thoát | ✅ | Đề bài nhấn mạnh |
| Form Mở TK theo kiểu Subform (Master-Detail) | ✅ | Master = KH, Detail = grid TK |
| Chọn chi nhánh (NganHang) / Khóa CN (ChiNhanh) | ✅ | Dropdown hoặc khóa |

---

## TÓM TẮT CÁC HẠNG MỤC CẦN HÀNH ĐỘNG

| # | Hạng mục | Mức ưu tiên | File tham chiếu |
|---|---|---|---|
| 1 | Sửa sp_ChuyenNhanVien (DELETE → UPDATE) | 🔴 CAO | `01_BanVa_SP_Fixes.md` |
| 2 | Sửa sp_RutTien (thêm check >= 100.000) | 🔴 CAO | `01_BanVa_SP_Fixes.md` |
| 3 | Tạo sp_LietKeKhachHang tại TANDINH (SQL2) | 🟡 TRUNG BÌNH | Copy từ SQL1, đổi LINK1 logic |
| 4 | Xác nhận thêm/sửa/xóa NV/KH dùng inline query hay SP | 🟡 TRUNG BÌNH | Chuẩn bị câu trả lời vấn đáp |
| 5 | Xác nhận code production dùng HTKN hay SQL Auth thật | 🟡 TRUNG BÌNH | Đồng bộ doc vs code |