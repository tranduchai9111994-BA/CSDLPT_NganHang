# 🗄️ Cấu Trúc Cơ Sở Dữ Liệu `NGANHANG`

Tài liệu này đặc tả toàn bộ **bảng dữ liệu** và **danh mục Stored Procedures** đang triển khai. Chi tiết cơ chế nhân bản/phân mảnh: xem [`08_Database_Replication.md`](08_Database_Replication.md). Source code SP: xem [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md).

---

## 1. Cấu Trúc Bảng

### 1.1. `ChiNhanh` — Danh mục chi nhánh
Nhân bản toàn vẹn về mọi Subscriber (không filter theo `MACN`).

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `MACN` | `nchar(10)` | **PK** — VD `BENTHANH`, `TANDINH` |
| `TENCN` | `nvarchar(100)` | `UNIQUE` |
| `DIACHI` | `nvarchar(100)` | |
| `SoDT` | `nvarchar(15)` | |

### 1.2. `NhanVien` — Nhân viên (phân mảnh ngang theo `MACN`)

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `MANV` | `nchar(10)` | **PK** — format prefix `BT###`/`TD###` |
| `HO` | `nvarchar(50)` | |
| `TEN` | `nvarchar(10)` | |
| `CMND` | `nchar(10)` | `UNIQUE` |
| `DIACHI` | `nvarchar(100)` | |
| `PHAI` | `nvarchar(3)` | |
| `SODT` | `nvarchar(15)` | |
| `MACN` | `nchar(10)` | **FK** → `ChiNhanh(MACN)` |
| `TrangThaiXoa` | `bit` | `DEFAULT 0` — 0: đang làm, 1: đã xóa mềm / đã chuyển đi |

**Phân mảnh:** Filter `WHERE MACN = 'BENTHANH'` cho SQL1 · `WHERE MACN = 'TANDINH'` cho SQL2. **KHÔNG replicate sang TRACUU** — TRACUU đọc qua LINK1+LINK2 khi cần.

### 1.3. `KhachHang` — Khách hàng (phân mảnh ngang theo `MACN`, + replicate full sang TRACUU)

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `CMND` | `nchar(10)` | **PK** — cũng dùng làm LoginName cho SQL Auth |
| `HO` | `nvarchar(50)` | |
| `TEN` | `nvarchar(10)` | |
| `DIACHI` | `nvarchar(100)` | |
| `PHAI` | `nvarchar(3)` | |
| `NGAYCAP` | `date` | Ngày cấp CMND |
| `SODT` | `nvarchar(15)` | |
| `MACN` | `nchar(10)` | **FK** → `ChiNhanh(MACN)` |

**Phân mảnh:** SQL1 chỉ chứa `MACN='BENTHANH'`, SQL2 chỉ chứa `MACN='TANDINH'`. **TRACUU replicate full** (không filter) để NganHang tra cứu toàn cục.

### 1.4. `TaiKhoan` — Tài khoản (**nhân bản toàn vẹn**)

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `SOTK` | `nchar(9)` | **PK** — format prefix `BT#######`/`TD#######` |
| `CMND` | `nchar(10)` | **FK** → `KhachHang(CMND)`, `NOT NULL` |
| `SODU` | `money` | `CHECK (SODU >= 0)` |
| `MACN` | `nchar(10)` | **FK** → `ChiNhanh(MACN)` — chi nhánh chủ sở hữu TK |
| `NGAYMOTK` | `datetime` | |

**Nhân bản toàn vẹn** trên SQL1 + SQL2 (giống `ChiNhanh`). Mỗi site có bản copy đầy đủ TK của cả 2 chi nhánh. **KHÔNG replicate sang TRACUU**.

**Quy tắc đọc/ghi (quan trọng):**
- **Đọc (SELECT):** Đọc local trực tiếp — nhanh, không cần Linked Server.
- **Ghi (UPDATE/INSERT/DELETE):** Chỉ ghi tại **site sở hữu** (site có `MACN` khớp). Nếu TK thuộc chi nhánh đối tác → ghi qua `[LINK1]` trong `BEGIN DISTRIBUTED TRANSACTION`. Replication sẽ đồng bộ bản copy ngược lại.

### 1.5. `GD_GOIRUT` — Giao dịch gửi/rút tiền (phân mảnh ngang theo NV thực hiện)

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `MAGD` | `int` | **PK IDENTITY** — cần **Identity Range Management** trong Replication để tránh trùng khóa |
| `SOTK` | `nchar(9)` | TK thực hiện GD |
| `LOAIGD` | `nchar(2)` | `'GT'` = Gửi tiền, `'RT'` = Rút tiền |
| `NGAYGD` | `datetime` | |
| `SOTIEN` | `money` | |
| `MANV` | `nchar(10)` | Nhân viên thực hiện |

**KHÔNG có cột `MACN`.** Giao dịch thuộc chi nhánh nào được nội suy qua (a) `MANV` (mảnh chứa NV) hoặc (b) mảnh mà bản ghi được INSERT vào. Ghi thẳng cột `MACN` vào đây = **dư thừa dữ liệu**, không hợp lý về mặt thiết kế.

### 1.6. `GD_CHUYENTIEN` — Giao dịch chuyển tiền

| Cột | Kiểu | Ràng buộc |
|---|---|---|
| `MAGD` | `int` | **PK IDENTITY** — cần Identity Range Management |
| `SOTK_CHUYEN` | `nchar(9)` | TK gửi đi |
| `SOTK_NHAN` | `nchar(9)` | TK nhận |
| `SOTIEN` | `money` | |
| `NGAYGD` | `datetime` | |
| `MANV` | `nchar(10)` | Nhân viên thực hiện |

**KHÔNG có `MACN`.** Log được ghi tại site NV thực hiện GD (đúng mảnh).

### 1.7. `QuanTriLogin` — Bảng phụ trợ quản lý login (local, KHÔNG replicate)

| Cột | Kiểu | Ghi chú |
|---|---|---|
| `LoginName` | `varchar(50)` | Tên SQL Login (khớp `MANV` hoặc `CMND`) |
| `MatKhauHienTai` | `varchar(50)` | Lưu **plain‑text** để phục vụ tra cứu / demo (không dùng cho production) |
| `LoaiTaiKhoan` | `varchar(20)` | `'NhanVien'` hoặc `'KhachHang'` |
| `MaThamChieu` | `varchar(50)` | MANV / CMND |
| `NhomQuyen` | `varchar(50)` | `NganHang` / `ChiNhanh` / `KhachHang` |
| `NgayTao` | `datetime` | |
| `NgayCapNhatMK` | `datetime` | |

Tồn tại giống nhau trên mọi instance nhưng **được quản lý độc lập** — vì Login là object cấp Server, mỗi instance có bản copy riêng. `DENY SELECT` cho ChiNhanh + KhachHang; chỉ NganHang xem qua API có middleware `requireNganHang`.

---

## 2. Danh Mục Stored Procedures

Toàn bộ SP nằm trong thư mục [`sql/stored_procedures/`](../sql/stored_procedures/). Source code đầy đủ + giải thích: xem [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md).

### 2.1. SP nghiệp vụ trên **chi nhánh** (SQL1 + SQL2)

| SP | Chức năng | Distributed Tran? |
|---|---|---|
| `sp_ChuyenTien(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, @MANV)` | Chuyển tiền cùng CN hoặc liên CN (dùng MACN check) | ✅ (dùng LINK1 nếu khác CN) |
| `sp_GuiTien(@SOTK, @SOTIEN, @MANV)` | Gửi tiền — hỗ trợ TK cross‑branch | ✅ |
| `sp_RutTien(@SOTK, @SOTIEN, @MANV)` | Rút tiền — hỗ trợ TK cross‑branch, atomic check `SODU >= @SOTIEN` | ✅ |
| `sp_MoTaiKhoan(@SOTK, @CMND, @SODU, @MACN)` | Mở TK mới — check KH local + LINK1 trước, INSERT trong DTC scope riêng | ✅ |
| `sp_ChuyenNhanVien(@MANV, @MACN_MOI)` | Chuyển NV sang CN khác — sinh MANV mới với prefix đích | ✅ |
| `sp_PhucHoiNhanVien(@MANV)` | Phục hồi NV: local `TrangThaiXoa=0` + deactivate bản active ở CN kia (nếu có) | ✅ |
| `SP_SaoKeTaiKhoan(@SOTK, @TUNGAY, @DENNGAY)` | Sao kê 1 TK — tính lùi số dư đầu kỳ, Window Function tính lũy kế | ❌ (chỉ đọc) |
| `sp_LietKeKhachHang(@MACN)` | Liệt kê KH theo CN, sort `MACN, HO, TEN` | ❌ |
| `sp_ThemKhachHang(...)` | Thêm KH mới local | ❌ |

### 2.2. SP đặc thù trên **TRACUU** (SQL3) — deploy thủ công qua [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql)

TRACUU chỉ có `KhachHang` local (replicate full). Các bảng khác đọc qua LINK1/LINK2.

| SP | Chức năng |
|---|---|
| `sp_DanhSachTaiKhoan()` | Danh sách toàn bộ TK — đọc **chỉ LINK1** (TaiKhoan replicate full, LINK1 đã đủ) + JOIN `KhachHang` local bằng `OUTER APPLY TOP 1` |
| `sp_LietKeTaiKhoanTheoNgay(@MACN, @TUNGAY, @DENNGAY)` | Liệt kê TK mở trong khoảng thời gian — cùng chiến lược LINK1 duy nhất |
| `sp_DanhSachNhanVien(@MACN)` | Danh sách NV toàn hệ thống — UNION ALL LINK1 + LINK2 (NhanVien phân mảnh, phải gộp) |
| `sp_SaoKeToanBo(@TUNGAY, @DENNGAY)` | Sao kê tổng hợp — UNION ALL GD_GOIRUT + GD_CHUYENTIEN từ LINK1 + LINK2 |
| `SP_SaoKeTaiKhoan(@SOTK, @TUNGAY, @DENNGAY)` | **Bản TRACUU** — đọc GD từ LINK1 + LINK2, số dư từ LINK1 (fallback LINK2). ⚠️ Route `baocao.js` khi NganHang chọn 1 TK cụ thể sẽ **không gọi bản này** mà mượn tạm server `BENTHANH` để gọi bản chi nhánh, tránh crash khi TRACUU không có bảng `TaiKhoan` local. |
| `SP_DanhSachTrangThaiLogin(@MACN)` | Danh sách NV + KH kèm trạng thái Login (chưa cấp / đã cấp active / đã cấp nhưng lỗi) — NV qua LINK, KH + `QuanTriLogin` local |

### 2.3. SP xác thực & quản trị Login (deploy trên **cả 4 instance**)

| SP | Chức năng |
|---|---|
| `sp_Login_App(@LoginName)` | Xác thực đăng nhập — resolve DB user từ SID, tìm Role qua `sys.database_role_members`, join với `NhanVien`/`KhachHang`. Có `OBJECT_ID` guard để chạy được trên TRACUU (schema khác các CN). |
| `SP_TaoTaiKhoan(@LGNAME, @PASS, @USERNAME, @ROLE, @LOAITK, @MATHAMCHIEU)` | Tạo Login + User + Role + ghi `QuanTriLogin`. Idempotent (IF NOT EXISTS mỗi bước). Dùng `QUOTENAME` + REPLACE để chống SQL injection. |
| `SP_ResetMatKhau(@LoginName, @MATKHAU_MOI)` | Đổi password. `WITH EXECUTE AS OWNER` để chạy `ALTER LOGIN` mà không cần cấp `securityadmin` cho user gọi. Cập nhật `QuanTriLogin.MatKhauHienTai` + `NgayCapNhatMK`. |
| `sp_TaiKhoanKhachHang(@CMND)` | Trả về danh sách TK của KH theo CMND. Là **cửa ngõ duy nhất** để KhachHang đọc TK (role không có `SELECT` trực tiếp). |

### 2.4. Sơ đồ triển khai (deploy matrix)

| SP | NGUON | SQL1 | SQL2 | SQL3 | Cách deploy |
|---|---|---|---|---|---|
| `sp_Login_App` | ✅ | ✅ | ✅ | ✅ | Article của PUB_BENTHANH/PUB_TANDINH/PUB_TRACUU (chỉ ALTER trên NGUON) |
| `SP_TaoTaiKhoan` | ✅ | ✅ | ✅ | ✅ | Article của cả 3 Publication |
| `SP_ResetMatKhau` | ✅ | ✅ | ✅ | ✅ | Deploy thủ công qua `setup_db.js` trên từng site |
| `sp_TaiKhoanKhachHang` | ✅ | ✅ | ✅ | ✅ | Deploy thủ công qua `setup_db.js` |
| `sp_LietKeKhachHang` | ✅ | ✅ | ✅ | ✅ | Article của cả 3 Publication |
| `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_PhucHoiNhanVien`, `sp_ThemKhachHang`, `SP_SaoKeTaiKhoan` (bản chi nhánh) | ✅ | ✅ | ✅ | ❌ | Article của PUB_BENTHANH + PUB_TANDINH |
| `sp_DanhSachTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay` (bản TRACUU), `sp_DanhSachNhanVien`, `sp_SaoKeToanBo`, `SP_SaoKeTaiKhoan` (bản TRACUU), `SP_DanhSachTrangThaiLogin` | ❌ | ❌ | ❌ | ✅ | Deploy thủ công qua [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql) |

---

## 3. Ghi Chú Kiến Trúc Quan Trọng

- **Không có logic sửa đổi dữ liệu ở tầng ứng dụng Node.js.** Mọi thao tác thay đổi số dư, chuyển tiền, chuyển NV đều được đóng gói trong SP. Node.js chỉ đóng vai trò điều phối và render.
- **TaiKhoan replicate full nhưng không "ghi tự do khắp nơi".** Quy tắc "đọc local, ghi tại site sở hữu (MACN)" được SP tự lo — code app không cần biết TK ở đâu.
- **SP đăng nhập `sp_Login_App` là Article Replication** → chỉ được sửa tại NGUON (Publisher). Muốn sửa phải làm theo quy trình 6 bước với `MSmerge_tr_alterschemaonly` (xem [`08_Database_Replication.md`](08_Database_Replication.md) §3.1.1).
