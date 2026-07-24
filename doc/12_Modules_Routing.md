# Chi Tiết Các Module Nghiệp Vụ (Routes)

Toàn bộ chức năng được tách theo module trong `APP_NGANHANG/routes/`. Mỗi file phụ trách 1 lĩnh vực, mount vào `app.js` kèm middleware phân quyền tương ứng.

---

## 1. `auth.js` — Xác Thực

- **Đăng nhập bằng SQL Authentication**: nhận `LoginName + Password`, mở connection pool bằng chính SQL Login đó.
- Sau khi kết nối thành công → gọi `sp_Login_App(@LoginName)` để lấy `MANV, HOTEN, NHOM, MACN`.
- Gán vào `req.session.user` (bao gồm cả `PASSWORD` để tái tạo pool khi cần), sau đó `res.locals.user` inject vào mọi view.
- `NHOM='NganHang'` → `effectiveServer = 'TRACUU'` bất kể user chọn gì trên dropdown.

## 2. `khachhang.js` — Quản Lý Khách Hàng

- **NganHang**: chỉ xem toàn hệ thống (query trên TRACUU vì `KhachHang` replicate full ở đó). **Không** thêm/sửa/xóa.
- **ChiNhanh**: CRUD trong chi nhánh mình. Các route ghi (`GET/POST /them`, `GET/POST /sua`, `POST /xoa`) bọc `requireChiNhanh` → NganHang bị HTTP 403.
- Route `POST /them` gọi SP `sp_ThemKhachHang` để INSERT + fan-out `SP_TaoTaiKhoan` (tạo SQL Login KH mới trên cả 3 site).
- Form `views/khachhang/form.ejs` dùng `autocomplete="off"`, `::-ms-reveal { display:none }` để tắt nút "hiện mật khẩu" mặc định của Edge/Chrome khỏi field Mã PIN. Toggle 👁 riêng cho phép user chủ động hiện/ẩn.
- Danh sách hiển thị cả cột `PHAI` (Giới tính) — SELECT có `RTRIM(PHAI) AS PHAI`.

## 3. `nhanvien.js` — Quản Lý Nhân Viên

- **NganHang**: chỉ xem — gọi `querySP(req, 'TRACUU', 'sp_DanhSachNhanVien')` (SP đọc `NhanVien` qua LINK1+LINK2 vì TRACUU không có bảng này local).
- **ChiNhanh**: toàn quyền CRUD + chuyển chi nhánh + phục hồi. Tất cả route ghi bọc `requireChiNhanh`.
- **Sinh MANV mới**: prefix `BT` cho BENTHANH, `TD` cho TANDINH. Hàm `sinhMANV()` query `TOP 1 MANV LIKE 'BT%'` hoặc `LIKE 'TD%'` rồi tăng 1. Đảm bảo duy nhất toàn cục kể cả khi chuyển NV qua lại.
- **Chuyển chi nhánh** (`/chuyen`): gọi `sp_ChuyenNhanVien` qua **`execSPAdmin` (sqlcmd)** vì SP dùng `BEGIN DISTRIBUTED TRANSACTION`. SP hiện có **resurrect logic (RF-A)** — nếu chi nhánh đích đã có NV cùng CMND đang soft-delete, SP UPDATE ngược `TrangThaiXoa=0` giữ MANV cũ thay vì INSERT mới (tránh vi phạm `UQ_NhanVien_CMND`). SP trả cột `IsResurrect bit` để route hiển thị thông báo phù hợp.
- **Phục hồi** (`/phuchoi`): gọi `SP_PhucHoiNhanVien` qua `execSPAdmin` — đưa `TrangThaiXoa = 0` local + deactivate bản active bên đối tác (LINK1) trong cùng DTC.

## 4. `taikhoan.js` — Mở / Đóng Tài Khoản

- **NganHang**: chỉ xem danh sách toàn hệ thống qua SP `sp_DanhSachTaiKhoan` trên TRACUU (SP đọc `TaiKhoan` qua LINK1 — không UNION LINK2 vì TaiKhoan replicate full).
- **ChiNhanh**: xem **tất cả TK** (do `TaiKhoan` replicate toàn vẹn giữa 2 chi nhánh) + mở TK + đóng TK. Danh sách KH để chọn ở form mở TK lấy từ 2 site bằng `queryAdminSQL` (dùng LINK1 để lấy KH bên đối tác) — có retry tự động khi pool lỗi.
- Route `GET/POST /mo` và `POST /dong` bọc `requireChiNhanh`.
- **Mở TK cross-branch**: form hiển thị KH của cả 2 chi nhánh (nhóm `<optgroup>`). Khi KH thuộc CN khác → `MACN = MACN của KH`, INSERT chạy trên **server có KH** (via `execSPAdmin`) để thỏa `FK_TaiKhoan_KhachHang`.
- **Sinh SOTK atomic trong SP** *(fix #3)*: từ tháng 07/2026, route KHÔNG còn hàm `sinhSOTK()` client-side. SP `sp_MoTaiKhoan` tự sinh SOTK trong distributed transaction với vòng WHILE retry (tối đa 5 lần) khi PK duplicate. Prefix `BT`/`TD` lấy theo `@MACN` (chi nhánh sở hữu TK) — cross-branch: NV BT mở TK cho KH TD → SOTK có prefix `TD` (không phải `BT`). Route parse SOTK trả về từ output text của sqlcmd bằng regex `/\b(?:BT|TD)\d{7}\b/`.
- SP `sp_MoTaiKhoan` **luôn gọi qua `execSPAdmin` (sqlcmd)** — SP dùng `BEGIN DISTRIBUTED TRANSACTION` sau khi đã tách check KH (LINK1) ra trước (chi tiết: [Sự cố 5 trong `17_Su_Co_Va_Xu_Ly.md`](17_Su_Co_Va_Xu_Ly.md)).
- **Đóng TK (RF‑B)** — logic guard đã chuyển từ route xuống SP `SP_DongTaiKhoan`. Route `POST /dong` chỉ còn 4 dòng: forward `SOTK + user.MANV` qua `execSPAdmin`. SP thực hiện 5 guard SQL-side: (1) TK tồn tại, (2) `SODU=0`, (3) `MACN_TK=MACN_NV` (chỉ đóng cùng CN), (4) không có `GD_GOIRUT` (local + LINK1), (5) không có `GD_CHUYENTIEN` (local + LINK1). Xem [Sự cố 8 trong `17_Su_Co_Va_Xu_Ly.md`](17_Su_Co_Va_Xu_Ly.md).

## 5. `giaodich.js` — Gửi / Rút / Chuyển Tiền

- Form Gửi/Rút thiết kế **Tabs đa năng** trên cùng 1 trang.
- Dropdown TK hiển thị **tất cả TK toàn hệ thống** kèm `[MACN]` để phân biệt chi nhánh — do TaiKhoan nhân bản toàn vẹn.
- **SP chạy trên server của NV thao tác** (local) → `GD_GOIRUT`/`GD_CHUYENTIEN` ghi đúng vào mảnh của CN đó (phân mảnh theo MANV). Nếu TK ở CN khác → SP tự UPDATE qua LINK1.
- Cả `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` đều gọi qua **`execSPAdmin` (sqlcmd)** vì có thể dùng DTC.
- **Rẽ nhánh transaction** *(fix #6)*: SP hiện không luôn dùng DTC — chọn `BEGIN TRANSACTION` khi TK và NV cùng CN (local write), `BEGIN DISTRIBUTED TRANSACTION` khi khác CN (UPDATE qua LINK1). Giảm chi phí MSDTC cho ~70% giao dịch nội bộ CN.
- **Chặn self-transfer** *(fix #9)*: `sp_ChuyenTien` RAISERROR ngay khi `@SOTK_CHUYEN = @SOTK_NHAN`.
- `sp_RutTien` / `sp_ChuyenTien` dùng atomic check-and-update `WHERE SOTK=@SOTK AND SODU>=@SOTIEN` → không cần lock rời, không có race condition.

## 6. `baocao.js` — Thống Kê & Sao Kê

- **Sao kê TK**: gọi `SP_SaoKeTaiKhoan` (chi nhánh) hoặc `sp_SaoKeToanBo` (TRACUU cho NganHang không chọn TK). Toàn bộ tính số dư đầu kỳ + số dư lũy kế xử lý dưới SQL Server bằng Window Function.
- **Defense in depth cho role `KhachHang`** *(fix #8)*: `SP_SaoKeTaiKhoan` (cả bản chi nhánh + bản TRACUU) chứa guard `IS_ROLEMEMBER('KhachHang')` + `SUSER_SNAME()` — nếu login đang là KH và `CMND` chủ TK khác login name (login KH = CMND), SP RAISERROR. Chặn được kể cả khi KH đăng nhập trực tiếp SSMS bypass middleware Node.
- **Liệt kê TK**:
  - NganHang → SP `sp_LietKeTaiKhoanTheoNgay` trên TRACUU (đọc `TaiKhoan` qua LINK1).
  - ChiNhanh → raw SELECT local + LEFT JOIN `KhachHang` local, `WHERE MACN = user.MACN`.
- **Liệt kê KH**:
  - NganHang không chọn CN → raw SELECT trên TRACUU (có full `KhachHang`), `ORDER BY MACN, HO, TEN`.
  - NganHang chọn CN cụ thể → raw SELECT trên site tương ứng.
  - ChiNhanh → force `WHERE MACN = user.MACN`.
- Tham số `?search=` lọc `CMND LIKE` hoặc `HO+' '+TEN LIKE` (áp dụng cho cả 2 nhóm).
- **KhachHang** chỉ được xem sao kê **TK của chính mình**: route pre-fetch danh sách TK qua `sp_TaiKhoanKhachHang` (không raw SELECT), rồi double-check `SOTK` request có nằm trong danh sách.

## 7. `quantri.js` — Cấp Tài Khoản & Phân Quyền

- Chỉ mở cho `NganHang` (mount kèm `requireNganHang` ở `app.js` — thực tế route level cũng kiểm tra thêm).
- **Tạo Tài Khoản** (`POST /quantri/tao-tai-khoan`): Grid 2 cột hiển thị NV + KH có sẵn để chọn. Tìm kiếm "search-as-you-type" nhanh.
  - Gọi `SP_TaoTaiKhoan(@LoginName, @Password, @UserName, @Role)` qua **Admin Pool** — user thường không có `CREATE LOGIN`.
  - Insert kèm bản ghi vào `QuanTriLogin` (lưu plain-text để reset về sau).
- **Danh sách trạng thái Login** (`GET /quantri/login-management/list`): gọi `SP_DanhSachTrangThaiLogin` trên TRACUU — SP UNION `[LINK1] + [LINK2]` cho `NhanVien` + `KhachHang`, LEFT JOIN với `sys.server_principals` để biết ai đã có Login/chưa có.
- **Xem / Reset mật khẩu**:
  - `GET /quantri/login-management/password/:loginName` — trả về plain-text từ `QuanTriLogin` (chỉ NganHang).
  - `POST /quantri/login-management/reset-password` — reset về `123456` trên cả 3 site (dùng `DROP LOGIN + CREATE LOGIN` → sau đó re-link `DB User` để tránh orphaned user).
  - `POST /quantri/login-management/cleanup-sync-error` — dọn record trong `QuanTriLogin` mà không có Login thật (do lỗi sync giữa các site).
- **Đổi nhóm quyền** (`POST /quantri/login-management/change-role`): dùng `sp_droprolemember` + `sp_addrolemember` trên cả 3 site. Login `admin` được bảo vệ cứng — luôn HTTP 403. UI cũng ẩn nút với dòng admin và với user không phải NganHang.

---

## Ghi Chú Về Xử Lý Xuyên Mảnh Ở Tầng Node

Một số route điều phối xuyên mảnh **tại tầng Node** (thay vì bọc bằng SP + Linked Server):
- `khachhang.js`, `quantri.js`: fan-out `CREATE LOGIN` sang BENTHANH + TANDINH + TRACUU khi tạo KH mới. Login là object cấp Server nên buộc phải làm tay ở từng site — Replication không đồng bộ.
- `baocao.js` (sao kê không chọn TK cho ChiNhanh): raw SELECT trên `GD_GOIRUT` + `GD_CHUYENTIEN` (không qua SP).

Đây là lựa chọn có chủ đích để giảm số SP phải maintain — chấp nhận được vì các route này chỉ dùng bởi role có quyền đầy đủ tại DB (`ChiNhanh`/`NganHang`), không phải endpoint public.

## Ghi Chú Về Defense in Depth (07/2026)

Đợt refactor tháng 07/2026 chuyển các guard nghiệp vụ từ tầng route xuống tầng SP để chống bypass ứng dụng:

| Route (cũ) | SP tương ứng (mới) | Guard đã chuyển xuống SQL |
|---|---|---|
| `POST /taikhoan/dong` | `SP_DongTaiKhoan` | 5 lớp: TK tồn tại, SODU=0, same-branch, no `GD_GOIRUT`, no `GD_CHUYENTIEN` |
| `POST /baocao/saoke` (route đã có pre-check) | `SP_SaoKeTaiKhoan` (cả 2 bản) | Ownership check `SUSER_SNAME() = CMND chủ TK` khi role KhachHang |
| `POST /taikhoan/mo` (hàm `sinhSOTK` client) | `sp_MoTaiKhoan` | Atomic SOTK generation + retry-on-PK-conflict |

Đánh giá chi tiết ở [`18_DanhGia_CoChePhanTan.md`](18_DanhGia_CoChePhanTan.md).
