# 📋 Đối Chiếu Yêu Cầu Đề Bài ↔ Thực Tế Triển Khai

> **Mục đích:** Xác nhận mọi yêu cầu trong đề bài (Đề 3 — Ngân Hàng phân tán) đều đã được triển khai đúng và đầy đủ.
> **Cách dùng:** Rà checklist này trước khi demo/bảo vệ. Xem chi tiết code tại từng file được tham chiếu.

---

## A. Cập nhật (CRUD) — 5 yêu cầu

### A1. Cập nhật Nhân viên
> Đề bài: "Form cho phép cập nhật nhân viên. Khi chuyển NV từ chi nhánh này sang chi nhánh kia thì tự động chuyển dữ liệu sang chi nhánh mới (Đổi MACN) đồng thời cập nhật `TrangThaiXoa = 1` ở chi nhánh cũ." Form phải có đủ: **Thêm, Xóa, Phục hồi, Ghi, Thoát**.

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Hiển thị danh sách NV (NganHang: toàn cục / ChiNhanh: local) | ✅ | `routes/nhanvien.js` | NganHang gọi `sp_DanhSachNhanVien` trên TRACUU (LINK1+LINK2); ChiNhanh đọc local |
| Thêm nhân viên mới — tự sinh MANV prefix BT/TD | ✅ | `routes/nhanvien.js` (`sinhMANV`) | INSERT trực tiếp bảng `NhanVien` local |
| Sửa thông tin NV | ✅ | `routes/nhanvien.js` — POST `/sua` | UPDATE trực tiếp bảng `NhanVien` local |
| Xóa NV (soft delete `TrangThaiXoa=1`) | ✅ | `routes/nhanvien.js` — POST `/xoa` | Giữ bản ghi để audit |
| Phục hồi NV | ✅ | `sp_PhucHoiNhanVien` | **Distributed Transaction:** phục hồi local + deactivate bản kia (nếu tồn tại) |
| Chuyển NV sang CN khác | ✅ | `sp_ChuyenNhanVien` | **Distributed Transaction:** UPDATE `TrangThaiXoa=1` local + INSERT qua `[LINK1]`; sinh MANV mới với prefix chi nhánh đích |
| Middleware `requireChiNhanh` chặn NganHang ghi | ✅ | `routes/nhanvien.js` | HTTP 403 nếu NganHang cố gọi route ghi |

### A2. Cập nhật Khách hàng

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Hiển thị danh sách KH | ✅ | `routes/khachhang.js` | NganHang đọc TRACUU (KhachHang replicate full); ChiNhanh đọc local |
| Thêm KH mới | ✅ | `sp_ThemKhachHang` + fan‑out CREATE LOGIN 3 site | Route tự tạo SQL Login cho KH trên NGUON/SQL1/SQL2/SQL3 |
| Sửa thông tin KH | ✅ | `routes/khachhang.js` — POST `/sua` | UPDATE trực tiếp bảng `KhachHang` local |
| Xóa KH | ✅ | `routes/khachhang.js` — POST `/xoa` | DELETE bảng `KhachHang` (chỉ khi không còn TK, không còn GD) |
| Tìm kiếm (search) theo HO+TEN, CMND | ✅ | Route hỗ trợ `?search=` | `LIKE %keyword%` |

### A3. Mở tài khoản cho khách hàng
> Đề bài: "Thiết kế theo Subform. Form chính = KH, form phụ (grid) = danh sách TK đã mở. Cho phép mở thêm TK mới (tự động sinh số TK)."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Giao diện Master‑Detail | ✅ | `views/taikhoan/` | Master = KH, Detail = grid TK |
| Tự động sinh SOTK theo prefix chi nhánh | ✅ | `routes/taikhoan.js` — `sinhSOTK()` | Format: `BT0000001`, `TD0000001` |
| Mở TK cùng chi nhánh | ✅ | `sp_MoTaiKhoan` | Distributed Transaction |
| Mở TK cross‑branch (NV BT mở TK cho KH TD) | ✅ | `sp_MoTaiKhoan` chạy trên server có KH (via `execSPAdmin`) | Thỏa cả FK_TaiKhoan_KhachHang + FK_TaiKhoan_ChiNhanh |
| Xóa TK (chỉ khi SODU=0 và không có GD) | ✅ | `routes/taikhoan.js` — POST `/dong` | DELETE trực tiếp bảng `TaiKhoan` local |

### A4. Gửi tiền / Rút tiền
> Đề bài: "Lập phiếu giao dịch. Số tiền gửi/rút > 100.000đ. Phải kiểm tra TK hợp lệ và số dư trước khi cho rút."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Form gửi/rút (giao diện Tabs) | ✅ | `views/giaodich/goirut.ejs` | 1 trang, chuyển Tab giữa Gửi ↔ Rút |
| Check số tiền ≥ 100.000 (gửi) | ✅ | `sp_GuiTien` | `IF @SOTIEN < 100000 → RAISERROR` |
| Check số tiền ≥ 100.000 (rút) | ✅ | `sp_RutTien` | Kiểm tra bằng dòng lệnh tương tự |
| Check TK hợp lệ | ✅ | Cả 2 SP đọc `MACN` từ `TaiKhoan` (nhân bản full → đọc local) | RAISERROR nếu TK không tồn tại |
| Check số dư đủ khi rút | ✅ | `UPDATE ... WHERE SODU >= @SOTIEN` | Atomic — không xảy ra race condition |
| Ghi log `GD_GOIRUT` | ✅ | INSERT trong SP | `LOAIGD='GT'` hoặc `'RT'` |
| Cho phép gửi/rút TK cross‑branch | ✅ | SP so sánh `MACN_TK` vs `MACN_NV` | UPDATE local nếu cùng CN, qua `[LINK1]` nếu khác CN |

### A5. Chuyển tiền
> Đề bài: "Lập phiếu chuyển tiền nội bộ và liên chi nhánh. Bắt buộc dùng `BEGIN DISTRIBUTED TRANSACTION`."

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Form chuyển tiền | ✅ | `views/giaodich/chuyentien.ejs` | |
| Chuyển cùng chi nhánh | ✅ | `sp_ChuyenTien` (`@IsNhanLocal=1`) | UPDATE 2 TK local |
| Chuyển liên chi nhánh | ✅ | `sp_ChuyenTien` (`@IsNhanLocal=0`) | UPDATE qua `[LINK1]` |
| `BEGIN DISTRIBUTED TRANSACTION` | ✅ | Trong SP | 2‑Phase Commit qua MSDTC |
| `SET XACT_ABORT ON` | ✅ | Trong SP | Bắt buộc cho DTC |
| Check TK chuyển/nhận tồn tại | ✅ | SP đọc MACN từ TaiKhoan (nhân bản full) | Đọc local, không cần LINK1 |
| Check số dư đủ (atomic) | ✅ | `UPDATE ... WHERE SODU >= @SOTIEN` + kiểm tra `@@ROWCOUNT` | Nếu 0 dòng bị update → ROLLBACK |
| Ghi log `GD_CHUYENTIEN` local | ✅ | INSERT trong SP | Ghi tại site NV thực hiện GD (đúng mảnh) |

---

## B. Liệt kê — Thống kê — 3 yêu cầu

### B1. Sao kê giao dịch 1 tài khoản (`@SOTK`, `@TUNGAY`, `@DENNGAY`)

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Bảng 5 cột: Số dư đầu \| Ngày \| Loại GD \| Số tiền \| Số dư sau | ✅ | `SP_SaoKeTaiKhoan` | Trả về đúng format |
| Số dư đầu kỳ (tính lùi từ số dư hiện tại) | ✅ | SP tính bằng `SODU_HIENTAI - SUM(biến động sau @TUNGAY)` | Không phải kéo toàn bộ lịch sử |
| Số dư lũy kế | ✅ | Window Function `SUM(...) OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` | 1 lần scan |
| Gộp GD Local + LINK1 (chi nhánh + đối tác) | ✅ | Bản SP chạy trên SQL1/SQL2 | UNION ALL |
| Phiên bản TRACUU dùng LINK1 + LINK2 | ✅ | `SP_SaoKeTaiKhoan` (bản TRACUU trong `deploy_tracuu.sql`) | Cho NganHang chọn TK cụ thể |
| KhachHang chỉ xem sao kê TK của mình | ✅ | Route `baocao.js` pre‑fetch `myTKList` qua `sp_TaiKhoanKhachHang`, check ownership | |

### B2. Liệt kê tài khoản mở trong 1 khoảng thời gian

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Lọc theo từ ngày, đến ngày | ✅ | `sp_LietKeTaiKhoanTheoNgay` | |
| Lọc theo 1 chi nhánh | ✅ | `WHERE MACN = @MACN` | |
| Xem tất cả chi nhánh (NganHang) | ✅ | `@MACN = NULL` | NganHang query TRACUU (SP đọc LINK1 duy nhất — TaiKhoan replicate full) |
| ChiNhanh khóa dropdown về CN mình | ✅ | Route hardcode `@MACN = session.MACN` | |

### B3. Liệt kê khách hàng theo từng chi nhánh (ORDER BY MACN, HO, TEN)

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Sắp xếp theo MACN, HO, TEN | ✅ | `sp_LietKeKhachHang` — `ORDER BY MACN, HO, TEN` | |
| NganHang xem tất cả CN | ✅ | Query TRACUU (KhachHang replicate full) | |
| ChiNhanh chỉ xem KH CN mình | ✅ | Truyền `@MACN = session.MACN` | |
| SP có trên tất cả 4 site | ✅ | Là Article của PUB_BENTHANH/PUB_TANDINH/PUB_TRACUU | Replication đẩy xuống mọi Subscriber |

---

## C. Quản trị — Phân quyền 3 nhóm

### C1. Nhóm `NganHang` (Ban Giám Đốc)

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Chọn CN bất kỳ để xem báo cáo | ✅ | Dropdown MACN trong form báo cáo | |
| Truy cập TRACUU | ✅ | `effectiveServer='TRACUU'` gán trong `auth.js` | |
| `DENY INSERT/UPDATE/DELETE` cấp DB | ✅ | `sql/setup/04_Role_PhanQuyen.sql` | |
| Tạo TK cùng nhóm hoặc ChiNhanh | ✅ | `SP_TaoTaiKhoan` + form quản trị | Dropdown Role linh hoạt |
| Đổi nhóm quyền TK (change‑role) | ✅ | `sp_droprolemember` + `sp_addrolemember` trên 3 server | Chặn cứng đổi `admin` |
| Đặt lại mật khẩu / Xem mật khẩu | ✅ | `SP_ResetMatKhau` (WITH EXECUTE AS OWNER) + đọc `QuanTriLogin` | Chỉ NganHang có quyền |

### C2. Nhóm `ChiNhanh` (Giao dịch viên)

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Toàn quyền CRUD trên CN mình | ✅ | DB Role + `requireChiNhanh` middleware | |
| Không xem CN khác | ✅ | Dropdown CN bị khóa | |
| Tạo TK cùng nhóm hoặc KhachHang | ✅ | `SP_TaoTaiKhoan` | Backend chặn nếu chọn Role NganHang |
| Không được đổi nhóm quyền | ✅ | `requireNganHang` middleware | UI hiện "Không có quyền" |

### C3. Nhóm `KhachHang`

| Yêu cầu con | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Chỉ xem sao kê TK của mình | ✅ | `sp_TaiKhoanKhachHang` + `SP_SaoKeTaiKhoan` | KhachHang không có `SELECT` trực tiếp trên bảng |
| Không thao tác khác | ✅ | DB Role + Middleware + UI (3 tầng) | |
| Không truy cập form tạo TK | ✅ | `requireRole` chặn | HTTP 403 |
| Đăng nhập bằng CMND + PIN | ✅ | SQL Authentication (LoginName = CMND) | |

---

## D. Kiến trúc phân tán — Yêu cầu ngầm

| Yêu cầu | Trạng thái | Xử lý tại | Ghi chú |
|---|---|---|---|
| Phân mảnh ngang theo `MACN` | ✅ | Replication filter | Áp dụng cho `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN` |
| Nhân bản toàn vẹn `TaiKhoan` + `ChiNhanh` | ✅ | Publication article không filter | Mỗi site có đủ TK cả 2 CN |
| 3 trạm + Publisher | ✅ | NGUON / SQL1 / SQL2 / SQL3 | |
| TRACUU chứa KH replicate full | ✅ | PUB_TRACUU — 1 article `KhachHang` | Các bảng khác đọc qua LINK1/LINK2 |
| Linked Server liên kết các mảnh | ✅ | LINK0/LINK1/LINK2 | LINK1 luôn là "đối tác" |
| Distributed Transaction (MSDTC 2PC) | ✅ | `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_PhucHoiNhanVien` | Gọi qua `sqlcmd` (`execSPAdmin`) |
| Replication từ Publisher | ✅ | NGUON là Publisher & Distributor | 3 Publication: PUB_BENTHANH, PUB_TANDINH, PUB_TRACUU |
| SQL Authentication theo từng user | ✅ | `db.js:getPool()` mở pool riêng theo `(serverKey, username)` | Audit LOGIN_NAME() chính xác |

---

## E. Giao diện — Yêu cầu form

| Yêu cầu | Trạng thái | Ghi chú |
|---|---|---|
| Mỗi form nghiệp vụ có: Thêm, Xóa, Phục hồi, Ghi, Thoát | ✅ | Đủ 5 nút |
| Form Mở TK theo kiểu Master‑Detail | ✅ | Master = KH, Detail = grid TK |
| Chọn chi nhánh (NganHang) / khóa CN (ChiNhanh) | ✅ | Dropdown / disabled tùy role |

---

## ✅ Tổng kết

Toàn bộ yêu cầu đề bài (A1–A5, B1–B3, C1–C3, D, E) **đã được triển khai đầy đủ và đúng theo cơ chế CSDL phân tán**. Xem chi tiết code từng SP tại [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md).
