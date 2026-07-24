# Testcase Kiểm Thử & Giải Thích Hệ Thống Ngân Hàng Phân Tán
> Mục đích: Dùng để thực hành kiểm thử, hiểu luồng xử lý từ Node.js → SQL Server, và cơ chế phân tán khi bảo vệ đồ án.

---

## Tài khoản Demo (dùng cho toàn bộ testcase)

> Xem danh sách đầy đủ tại [`03_DemoAccounts.md`](03_DemoAccounts.md).

| Nhóm | SQL Login | Password | Chi nhánh chọn | Role |
|------|-----------|----------|----------------|------|
| ChiNhanh (BT) | `BT001` | `1` | `BENTHANH` | ChiNhanh |
| ChiNhanh (TD) | `TD001` | `1` | `TANDINH` | ChiNhanh |
| NganHang | `admin` | `1` | `BENTHANH` hoặc `TANDINH` (hệ thống tự dùng TRACUU) | NganHang |
| KhachHang | `1111111111` | `123456` | `BENTHANH` hoặc `TANDINH` | KhachHang |

> **Lưu ý login page:** Dropdown chỉ còn BENTHANH và TANDINH. Admin/KhachHang chọn site nào cũng được — hệ thống tự điều phối. NganHang luôn được gán `effectiveServer = TRACUU` sau khi đăng nhập (xem `auth.js`). TRACUU bị ẩn khỏi dropdown vì chọn vào thì dữ liệu y chang BENTHANH — không có giá trị phân biệt với người dùng.

---

## Kiến trúc tổng quan

```
[Trình duyệt]
     │
     ▼
[Node.js App - app.js]
     │   routes/auth.js, taikhoan.js, giaodich.js, ...
     │
     ├──► SQL1 (ES-HAITD16\SQL1)  ← Chi nhánh BENTHANH  ← Mảnh ngang: TK prefix "BT"
     ├──► SQL2 (ES-HAITD16\SQL2)  ← Chi nhánh TANDINH   ← Mảnh ngang: TK prefix "TD"
     └──► SQL3 (ES-HAITD16\SQL3)  ← Server TRACUU       ← Chỉ replicate KhachHang + đọc qua LINK1/LINK2
```

**Mô hình dữ liệu:**
- **Phân mảnh ngang:** KhachHang, NhanVien, GD_GOIRUT, GD_CHUYENTIEN — theo `MACN`
- **Nhân bản toàn vẹn:** `TaiKhoan` — mỗi site có đầy đủ TK của cả 2 chi nhánh (đọc local nhanh, GHI qua LINK1 nếu TK thuộc CN khác)
- **Nhân bản toàn vẹn:** `ChiNhanh` — danh mục tham chiếu (trên SQL1/SQL2, SQL3 đã DROP)
- **TRACUU (SQL3):** Chỉ có 2 bảng local: `KhachHang` (replicate full) + `QuanTriLogin` (local). 
NhanVien/TaiKhoan/GD đọc qua LINK1+LINK2 bằng SP đặc thù (`sp_DanhSachNhanVien`, `sp_LietKeTaiKhoanTheoNgay`, `SP_DanhSachTrangThaiLogin`)
- Linked Server: SQL1 có `LINK1` trỏ tới SQL2 (và ngược lại); SQL3 có `LINK1`→SQL1, `LINK2`→SQL2

---

## TC-01: Đăng nhập — Xác thực qua SQL Server

### Mục tiêu
Kiểm tra cơ chế đăng nhập dùng chính SQL Login (không dùng bảng user riêng).

### Tình huống test

| ID | Input | Kết quả kỳ vọng |
|----|-------|-----------------|
| 01a | username=`BT001`, password=`1`, chi nhánh=`BENTHANH` | Đăng nhập thành công, NHOM=ChiNhanh, MACN=BENTHANH |
| 01b | username=`BT001`, password=`saimat`, chi nhánh=`BENTHANH` | Lỗi: "Sai tài khoản hoặc mật khẩu" |
| 01c | username=`TD001`, password=`1`, chi nhánh=`BENTHANH` | Lỗi: "Sai tài khoản hoặc mật khẩu" *(xem giải thích bên dưới)* |
| 01d | username=`admin`, password=`1`, chi nhánh=`BENTHANH` | Thành công, NHOM=NganHang, MACN=TRACUU *(xem giải thích bên dưới)* |
| 01e | username=`1111111111`, password=`123456`, chi nhánh=`BENTHANH` | Thành công, NHOM=KhachHang |

### Hệ thống xử lý chi tiết

**Bước 1 — Kết nối SQL bằng chính user/password người dùng nhập**
- Code: [`routes/auth.js:22–42`](../APP_NGANHANG/routes/auth.js)
- `new sql.ConnectionPool({ user: username, password: password })` → nếu SQL Server từ chối → lỗi "Sai tài khoản hoặc mật khẩu"
- Đây là **Impersonation thật** — mỗi user kết nối bằng quyền SQL Login của mình, không dùng tài khoản hệ thống trung gian

**Bước 2 — Gọi SP `sp_Login_App` để lấy thông tin phân quyền**
- Code: [`routes/auth.js:48–53`](../APP_NGANHANG/routes/auth.js), SP: [`sql/stored_procedures/sp_Login_App.sql`](../sql/stored_procedures/sp_Login_App.sql)
- SP tra `sys.database_role_members` + `sys.database_principals` → xác định user thuộc role nào (`NganHang`, `ChiNhanh`, `KhachHang`)
- Nếu `NHOM = ChiNhanh` hoặc `NganHang` → query bảng `NhanVien` lấy `MANV`, `HOTEN`, `MACN`
- Nếu `NHOM = KhachHang` → query bảng `KhachHang` theo `CMND` = LoginName
- Nếu `admin` (NganHang) không có trong NhanVien → SP fallback gán `HOTEN = 'Quan Tri Vien'`

**Bước 3 — Kiểm tra MACN vs chi nhánh đã chọn**
- Code: [`routes/auth.js:67–69`](../APP_NGANHANG/routes/auth.js)
- Chỉ áp dụng cho `NHOM = ChiNhanh`: nếu `MACN` từ DB ≠ chi nhánh user chọn → lỗi "không có quyền đăng nhập vào chi nhánh này"
- `admin` (NganHang) và KhachHang không bị kiểm tra này

**Bước 4 — Lưu session**
- Code: [`routes/auth.js:71–79`](../APP_NGANHANG/routes/auth.js)
- Lưu: `{ USERNAME, PASSWORD, MANV, HOTEN, NHOM, MACN, SERVER }` → dùng cho mọi request sau

**Cách kiểm tra trong DB:**
```sql
-- Xem SQL Login tồn tại trên server nào:
SELECT name, is_disabled FROM sys.server_principals WHERE name = 'BT001';

-- Xem user thuộc role nào:
SELECT dp.name AS UserName, rp.name AS RoleName
FROM sys.database_role_members rm
JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
WHERE dp.name = 'BT001';
```

**Logic vấn đáp:** Hệ thống dùng SQL Authentication thật — login name = MANV hoặc CMND, 
mỗi SQL Server instance có riêng danh sách Login. `BT001` chỉ tồn tại trên SQL1, không tồn tại trên SQL2, nên không thể đăng nhập vào TANDINH. Đây là cách phân quyền tự nhiên nhất trong CSDL phân tán — quyền gắn liền với server chứa dữ liệu.

**Giải thích 01d — admin đăng nhập TRACUU:**  
`sp_Login_App` ban đầu query `FROM NhanVien` và `FROM ChiNhanh` — 2 bảng không tồn tại trên SQL3 → SP crash. Đã fix bằng cách thêm `OBJECT_ID` guard: khi chạy trên SQL3, bỏ qua query NhanVien và gán `MACN = 'TRACUU'` thay vì query ChiNhanh.  
**Cách deploy:** Sửa SP trên Publisher (`ES-HAITD16`) → `sp_startpublication_snapshot` → `sp_reinitmergesubscription` → Merge Agent sync → SQL3 nhận SP mới qua replication (không DDL trực tiếp trên Subscriber).  
**Điều kiện tiên quyết:** phải chạy [`09_TaoTaiKhoanAdmin.sql`](../sql/setup/09_TaoTaiKhoanAdmin.sql) trên **SQL3** (không chỉ SQL1/SQL2).

**Giải thích 01e — KhachHang đăng nhập:**  
KH login không được tạo tự động qua setup script. Phải chạy [`11_TaoTaiKhoanKhachHang_Demo.sql`](../sql/setup/11_TaoTaiKhoanKhachHang_Demo.sql) trên **SQL1** (cho KH BENTHANH) và **SQL2** (cho KH TANDINH) trước khi test.  
Sau khi chạy: username = CMND (`1111111111`), password = `123456`, chi nhánh = `BENTHANH`.

**Giải thích 01c — tại sao không ra "không có quyền đăng nhập vào chi nhánh này":**  
`TD001` chỉ tồn tại trên SQL2 (TANDINH). Khi chọn chi nhánh `BENTHANH`, hệ thống kết nối tới SQL1 bằng credentials `TD001`/`1` → SQL1 từ chối ngay (không có login này) → lỗi dừng ở **Bước 1**, chưa đến Bước 2 hay Bước 3.  
Thông báo "Bạn không có quyền đăng nhập vào chi nhánh này!" chỉ xuất hiện khi user *tồn tại* trên server được chọn nhưng `MACN` trong DB lại khác chi nhánh đó — tình huống này không xảy ra trong thiết kế phân tán (mỗi nhân viên chỉ có SQL Login đúng server chi nhánh của mình).

### Điểm phân tán cần biết
- Mỗi chi nhánh (SQL1, SQL2) có **SQL Login riêng** cho nhân viên của mình.
- `BT001` tồn tại trên `SQL1`, không tồn tại trên `SQL2` → không đăng nhập được vào TANDINH.
- `db.js:getPool()` dùng **username/password trong session** để tạo kết nối tới đúng server → **Impersonation đúng nghĩa**.

---

## TC-02: Xem danh sách tài khoản — Phân quyền theo Role

### Mục tiêu
Kiểm tra dữ liệu trả về khác nhau theo NHOM (NganHang / ChiNhanh / KhachHang).

### Tình huống test

| ID | Đăng nhập bằng | Kết quả kỳ vọng |
|----|----------------|-----------------|
| 02a | `admin` (NganHang) | Thấy TK của **cả 2 chi nhánh** (gộp từ SQL1+SQL2) |
| 02b | `BT001` (ChiNhanh-BENTHANH) | Thấy TK của **cả 2 chi nhánh** (TaiKhoan nhân bản toàn vẹn, không filter theo MACN) |
| 02c | *(CMND KH)* (KhachHang) | Chỉ thấy TK của chính mình (theo CMND) |

### Hệ thống xử lý chi tiết

**Nhánh NganHang (admin):**
- Code: [`routes/taikhoan.js:31–34`](../APP_NGANHANG/routes/taikhoan.js)
- Gọi `querySP(req, 'TRACUU', 'sp_DanhSachTaiKhoan', {})` → SP chạy trên SQL3
- SP [`sql/stored_procedures/12_SP_DanhSachTaiKhoan.sql`](../sql/stored_procedures/12_SP_DanhSachTaiKhoan.sql): đọc `TaiKhoan` qua `LINK1` (SQL1) + `LINK2` (SQL2), JOIN `KhachHang` local (TRACUU replicate full KhachHang)
- Kết quả: danh sách toàn bộ TK hệ thống

**Nhánh ChiNhanh (BT001):**
- Code: [`routes/taikhoan.js:50–71`](../APP_NGANHANG/routes/taikhoan.js)
- TaiKhoan nhân bản toàn vẹn → hiển thị **tất cả TK**, không filter theo MACN
- KhachHang phân mảnh ngang → dùng `queryAdminSQL()` (tài khoản HTKN, có retry tự động) + `OUTER APPLY (UNION ALL local + LINK1)` để lấy tên KH cả 2 chi nhánh
- User ChiNhanh không có quyền query LINK1 → bắt buộc dùng admin pool

**Nhánh KhachHang (CMND):**
- Code: [`routes/taikhoan.js:48–50`](../APP_NGANHANG/routes/taikhoan.js)
- Gọi `querySP(req, server, 'sp_TaiKhoanKhachHang', { CMND: user.MANV })`
- SP [`sql/stored_procedures/14_SP_TaiKhoanKhachHang.sql`](../sql/stored_procedures/14_SP_TaiKhoanKhachHang.sql): lọc theo CMND → KH chỉ thấy TK của mình
- KhachHang **KHÔNG có GRANT SELECT** trên bảng TaiKhoan (xem `04_Role_PhanQuyen.sql`) → chỉ truy cập qua SP

**Cách kiểm tra trong DB:**
```sql
-- Trên SQL3 (TRACUU), kiểm tra SP đọc qua Linked Server:
EXEC sp_DanhSachTaiKhoan;  -- Gộp từ LINK1 + LINK2

-- Trên SQL1 (BENTHANH), xem TK local:
SELECT * FROM TaiKhoan WHERE RTRIM(MACN) = 'BENTHANH';
```

**Logic vấn đáp:** 3 nhóm user → 3 luồng query khác nhau. 
NganHang query trên TRACUU (SQL3) dùng SP gộp qua LINK1+LINK2 — đây là **tái cấu trúc (reconstruction)** trong CSDL phân tán. 
ChiNhanh query TaiKhoan local (nhân bản full → có đủ TK cả 2 CN), JOIN KhachHang qua admin pool + LINK1 (KhachHang phân mảnh ngang). 
KhachHang dùng SP bắt buộc (không có quyền SELECT trực tiếp) — đảm bảo chỉ thấy TK của mình.

---

## TC-03: Mở tài khoản — Sinh SOTK tự động theo chi nhánh

### Mục tiêu
Kiểm tra sinh số tài khoản không trùng theo prefix chi nhánh.

### Tình huống test

| ID | Thao tác | Kết quả kỳ vọng |
|----|----------|-----------------|
| 03a | NV BenThanh mở TK đầu tiên | SOTK = `BT0000001` |
| 03b | NV BenThanh mở TK thứ 2 | SOTK = `BT0000002` |
| 03c | NV TanDinh mở TK đầu tiên | SOTK = `TD0000001` |
| 03d | NV BenThanh mở TK cho KH **TanDinh** | SOTK = `TD000000X`, MACN = TANDINH, INSERT chạy trên SQL2 (thỏa FK) → TK replicate sang SQL1 |
| 03e | NV TanDinh mở TK cho KH **BenThanh** | SOTK = `BT000000X`, MACN = BENTHANH, INSERT chạy trên SQL1 (thỏa FK) → TK replicate sang SQL2 |
| 03f | Mở TK với SODU âm | Lỗi từ SP (constraint check) |
| 03g | KhachHang cố mở TK | HTTP 403 — Không có quyền |
| 03h | NganHang (admin) cố mở TK | HTTP 403 — Không có quyền (chỉ ChiNhanh được mở TK) |

### Hệ thống xử lý chi tiết

**Bước 1 — Sinh SOTK (khi mở form)**
- Code: [`routes/taikhoan.js:12–21`](../APP_NGANHANG/routes/taikhoan.js) (hàm `sinhSOTK`)
- Logic: `SELECT TOP 1 SOTK FROM TaiKhoan WHERE SOTK LIKE 'BT%' ORDER BY SOTK DESC` → parse số cuối + 1 → pad 7 chữ số → `BT0000001`
- Prefix: `BENTHANH` → `BT`, `TANDINH` → `TD` (map tại dòng 9: `MACN_PREFIX`)

**Bước 2 — Kiểm tra quyền**
- Code: [`routes/taikhoan.js`](../APP_NGANHANG/routes/taikhoan.js) — middleware `requireChiNhanh`
- `if (user.NHOM !== 'ChiNhanh')` → HTTP 403
- Cả `KhachHang` lẫn `NganHang` đều bị chặn tại đây, không đến được SQL

**Bước 3 — Xác định chi nhánh đích (cross-branch logic)**
- Code: [`routes/taikhoan.js:100–128`](../APP_NGANHANG/routes/taikhoan.js)
- Form gửi `KH_MACN` (chi nhánh của KH được chọn, lấy từ `data-macn` trên `<option>`)
- So sánh `KH_MACN` vs `user.MACN`:
  - **Cùng chi nhánh:** `MACN = user.MACN`, SOTK prefix theo user.MACN → gọi `execSPAdmin(userMacn, ...)` local
  - **Khác chi nhánh (cross-branch):** `MACN = KH_MACN`, SOTK prefix theo chi nhánh NV → gọi `execSPAdmin(khMacn, ...)` trên server có KH
  - **Cả 2 case đều dùng `execSPAdmin` (sqlcmd)** vì SP dùng `BEGIN DISTRIBUTED TRANSACTION` → tedious không hỗ trợ MSDTC

**Bước 4 — Gọi SP mở TK**
- SP `sp_MoTaiKhoan`: kiểm tra SOTK chưa tồn tại, kiểm tra CMND tồn tại (check local trước → không có thì check `[LINK1]` đối tác — **TRƯỚC** `BEGIN DISTRIBUTED TRANSACTION` để tránh conflict với merge trigger), INSERT trong `BEGIN DISTRIBUTED TRANSACTION` riêng
- Cross-branch: INSERT chạy trên server có KH → thỏa cả **FK_TaiKhoan_KhachHang** (CMND) lẫn **FK_TaiKhoan_ChiNhanh** (MACN)
- TaiKhoan nhân bản toàn vẹn → Merge Replication tự đồng bộ sang server đối tác
- Constraint `CHECK (SODU >= 0)` trong DB chặn số dư âm

**Cách kiểm tra trong DB:**
```sql
-- Xem SOTK cuối cùng tại BENTHANH:
SELECT TOP 1 SOTK FROM TaiKhoan WHERE SOTK LIKE 'BT%' ORDER BY SOTK DESC;

-- Kiểm tra constraint:
SELECT name, definition FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('TaiKhoan');
```

**Logic vấn đáp:** Prefix BT/TD đảm bảo **không bao giờ trùng SOTK** khi 2 site đồng thời INSERT (vì TaiKhoan nhân bản toàn vẹn). 
TK mới được INSERT tại site sở hữu (MACN khớp), Replication tự đồng bộ sang site đối tác. 
Đây là giải pháp tránh xung đột khóa chính trong CSDL phân tán.

**Cross-branch (03d, 03e):** KH đăng ký ở chi nhánh A, NV chi nhánh B mở TK cho KH đó → hệ thống tự route INSERT sang server A (nơi có KH) để thỏa FK. MACN và SOTK prefix theo chi nhánh KH (không phải chi nhánh NV). Dùng `execSPAdmin` (tài khoản HTKN) vì cần chạy SP trên server khác. Dropdown KH trong form hiển thị cả 2 chi nhánh (nhóm theo optgroup) với `data-macn` attribute để truyền chi nhánh KH về server.

---

## TC-04: Chuyển tiền nội bộ (cùng chi nhánh)

### Mục tiêu
Chuyển tiền khi cả 2 tài khoản đều nằm trên cùng 1 SQL Server.

### Tình huống test

| ID | Input | Kết quả kỳ vọng |
|----|-------|-----------------|
| 04a | Chuyển BT0000001 → BT0000002, số tiền hợp lệ | Thành công, cả 2 SODU cập nhật |
| 04b | Chuyển BT0000001 → BT0000002, SOTIEN=0 | **Không thể nhập** — form tự xóa ô khi nhập `0`, nút Submit bị block bởi JS trước khi gửi request. SP không được gọi. |
| 04c | Chuyển BT0000001 → BT0000002, SOTIEN > SODU | Lỗi: "Số dư không đủ" |
| 04d | Chuyển BT0000001 → BT9999999 (không tồn tại) | Lỗi: "Tài khoản nhận không tồn tại" |

### Hệ thống xử lý chi tiết

**Bước 1 — Node.js nhận request**
- Code: [`routes/giaodich.js:85–101`](../APP_NGANHANG/routes/giaodich.js)
- `execSP(req, server, 'sp_ChuyenTien', { SOTK_CHUYEN, SOTK_NHAN, SOTIEN, MANV })`
- `db.js` dùng `sqlcmd` (không dùng tedious) vì MSDTC distributed transaction — tedious không hỗ trợ `BEGIN DISTRIBUTED TRANSACTION`

**Bước 2 — SP validate đầu vào**
- SP: [`sql/stored_procedures/07_SP_ChuyenTien.sql:19–41`](../sql/stored_procedures/07_SP_ChuyenTien.sql)
- Kiểm tra `@SOTIEN > 0` → nếu không → RAISERROR
- Đọc `MACN` của TK chuyển và TK nhận từ bảng `TaiKhoan` **local** (vì TaiKhoan nhân bản full, không cần LINK1)
- Nếu TK không tồn tại → `@MACN IS NULL` → RAISERROR

**Bước 3 — Xác định nội bộ hay liên chi nhánh**
- SP: [`07_SP_ChuyenTien.sql:44–46`](../sql/stored_procedures/07_SP_ChuyenTien.sql)
- So sánh `@MACN_CHUYEN` vs `@MACN_NHAN`:
  - Cùng nhau (ví dụ cả 2 đều `BENTHANH`) → `@IsNhanLocal = 1` → UPDATE local
  - Khác nhau → `@IsNhanLocal = 0` → UPDATE qua LINK1

**Bước 4 — Thực hiện giao dịch**
- SP: [`07_SP_ChuyenTien.sql:49–77`](../sql/stored_procedures/07_SP_ChuyenTien.sql)
- `BEGIN DISTRIBUTED TRANSACTION` (luôn dùng distributed dù nội bộ — do `SET XACT_ABORT ON`)
- Trừ tiền: `UPDATE TaiKhoan SET SODU -= @SOTIEN WHERE SOTK = @SOTK_CHUYEN AND SODU >= @SOTIEN`
- Nếu `@@ROWCOUNT = 0` → ROLLBACK + RAISERROR "số dư không đủ"
- Cộng tiền: `@IsNhanLocal = 1` → UPDATE local; `= 0` → UPDATE qua `[LINK1]`
- Ghi log: `INSERT INTO GD_CHUYENTIEN`
- `COMMIT TRANSACTION`

**Cách kiểm tra trong DB:**
```sql
-- Trước giao dịch:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK IN ('BT0000001', 'BT0000002');

-- Sau giao dịch, kiểm tra lịch sử:
SELECT * FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = 'BT0000001' ORDER BY NGAYGD DESC;
```

**Logic vấn đáp:** SP dùng `SET XACT_ABORT ON` + `BEGIN DISTRIBUTED TRANSACTION` 
→ nếu BẤT KỲ lệnh nào fail → tự động ROLLBACK toàn bộ. Điều kiện `SODU >= @SOTIEN` 
trong WHERE của UPDATE đảm bảo atomic — không bao giờ số dư âm, ngay cả khi 2 giao dịch chạy đồng thời (row-level lock).

---

## TC-05: Chuyển tiền liên chi nhánh (khác SQL Server) 

### Mục tiêu
Chuyển tiền khi TK nguồn và TK đích nằm trên 2 SQL Server khác nhau → phải qua MSDTC.

### Tình huống test

| ID | Input | Kết quả kỳ vọng |
|----|-------|-----------------|
| 05a | Chuyển BT0000001 → TD0000001, số tiền hợp lệ | Thành công, SQL1.SODU giảm, SQL2.SODU tăng |
| 05b | Chuyển BT0000001 → TD9999999 (không tồn tại cả 2 nơi) | Lỗi: "Tài khoản nhận không tồn tại trên toàn hệ thống" |
| 05c | Tắt SQL2, thực hiện chuyển BT→TD | Lỗi MSDTC (linked server unreachable), ROLLBACK toàn bộ |

### Hệ thống xử lý chi tiết

**Bước 1–2:** Giống TC-04 (validate đầu vào, đọc MACN local)

**Bước 3 — Phát hiện liên chi nhánh**
- SP: [`07_SP_ChuyenTien.sql:44–46`](../sql/stored_procedures/07_SP_ChuyenTien.sql)
- `MACN_CHUYEN = 'BENTHANH'`, `MACN_NHAN = 'TANDINH'` → khác nhau → `@IsNhanLocal = 0`

**Bước 4 — Distributed Transaction qua MSDTC**
- SP: [`07_SP_ChuyenTien.sql:49–77`](../sql/stored_procedures/07_SP_ChuyenTien.sql)
- `BEGIN DISTRIBUTED TRANSACTION` → MSDTC điều phối 2-phase commit:
  - **Phase 1 (PREPARE):** SQL1 + SQL2 đều xác nhận sẵn sàng commit
  - **Phase 2 (COMMIT):** Nếu cả 2 OK → commit cả 2; nếu 1 bên fail → rollback cả 2
- Trừ tiền: `UPDATE TaiKhoan SET SODU -= @SOTIEN` (trên SQL1 — local)
- Cộng tiền: `UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU += @SOTIEN` (ghi sang SQL2 qua Linked Server)
- `INSERT INTO GD_CHUYENTIEN` (ghi trên SQL1)
- `COMMIT TRANSACTION` → MSDTC commit 2-phase

**Cách kiểm tra trong DB:**
```sql
-- Trên SQL1 (BENTHANH):
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'BT0000001';
SELECT * FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = 'BT0000001' ORDER BY NGAYGD DESC;

-- Trên SQL2 (TANDINH) — xác nhận SODU đã tăng:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'TD0000001';
```

**Logic vấn đáp:**
- **MSDTC là gì?** → Microsoft Distributed Transaction Coordinator, quản lý giao dịch 2-phase commit (2PC) trên nhiều SQL Server.
- **2-Phase Commit:** Phase 1 (PREPARE) — tất cả bên đồng ý commit; Phase 2 (COMMIT) — coordinator ra lệnh commit/rollback. 
Đảm bảo ACID dù giao dịch trải rộng nhiều node.
- **Nếu SQL2 sập giữa chừng?** → MSDTC detect timeout ở PREPARE phase → gửi ROLLBACK → SQL1 hoàn trả lại.
- **Tại sao dùng sqlcmd thay tedious?** → Driver tedious (Node.js) không hỗ trợ `BEGIN DISTRIBUTED TRANSACTION`; `sqlcmd` dùng SQL Server Native Client nên hỗ trợ MSDTC. Xem `db.js` hàm `execSP`.

---

## TC-06: Gửi / Rút tiền

### Tình huống test

| ID | Input | Kết quả kỳ vọng |
|----|-------|-----------------|
| 06a | Gửi BT0000001 số tiền 1,000,000 | SODU tăng, GD_GOIRUT có bản ghi LOAIGD='GT' |
| 06b | Rút BT0000001 số tiền hợp lệ | SODU giảm, GD_GOIRUT có bản ghi LOAIGD='RT' |
| 06c | Rút số tiền > SODU | SP RAISERROR, ROLLBACK |
| 06d | Rút số tiền = 0 | **Không thể nhập** — form tự xóa ô khi nhập `0`, nút Submit bị block bởi JS (`submitMoney` alert "Số tiền tối thiểu là 100.000 VNĐ"). SP không được gọi. |

### Hệ thống xử lý chi tiết

**Gửi tiền:**
- Code: [`routes/giaodich.js:31–44`](../APP_NGANHANG/routes/giaodich.js)
- Gọi `execSP(req, server, 'sp_GuiTien', { SOTK, SOTIEN, MANV })`
- SP `sp_GuiTien`:
  1. Validate `@SOTIEN > 0`
  2. `UPDATE TaiKhoan SET SODU = SODU + @SOTIEN WHERE SOTK = @SOTK`
  3. `INSERT INTO GD_GOIRUT(SOTK, SOTIEN, LOAIGD, NGAYGD, MANV) VALUES(@SOTK, @SOTIEN, 'GT', GETDATE(), @MANV)`

**Rút tiền:**
- Code: [`routes/giaodich.js:47–62`](../APP_NGANHANG/routes/giaodich.js)
- Gọi `execSP(req, server, 'sp_RutTien', { SOTK, SOTIEN, MANV })`
- SP `sp_RutTien`:
  1. Validate `@SOTIEN > 0`
  2. `UPDATE TaiKhoan SET SODU = SODU - @SOTIEN WHERE SOTK = @SOTK AND SODU >= @SOTIEN`
  3. `@@ROWCOUNT = 0` → RAISERROR "Số dư không đủ"
  4. `INSERT INTO GD_GOIRUT(SOTK, SOTIEN, LOAIGD, NGAYGD, MANV) VALUES(@SOTK, @SOTIEN, 'RT', GETDATE(), @MANV)`

**Cách kiểm tra trong DB:**
```sql
-- Xem số dư sau giao dịch:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'BT0000001';

-- Xem lịch sử gửi/rút:
SELECT * FROM GD_GOIRUT WHERE SOTK = 'BT0000001' ORDER BY NGAYGD DESC;
```

**Logic vấn đáp:** Gửi/rút là giao dịch đơn giản nhất — chỉ thao tác trên 1 server (local). Điểm đáng chú ý: điều kiện `SODU >= @SOTIEN` trong WHERE của UPDATE rút tiền — đảm bảo atomic, không bao giờ số dư âm. SP dùng `TRY...CATCH` để bắt lỗi và trả thông báo rõ ràng.

---

## TC-07: Sao kê tài khoản — Thuật toán tính số dư đầu kỳ

### Mục tiêu
Xem sao kê giao dịch trong khoảng ngày, kèm số dư lũy kế. Đây là SP phức tạp nhất.

### Tình huống test

| ID | Cách thực hiện | Input | Kết quả kỳ vọng |
|----|----------------|-------|-----------------|
| 07a | Login `BT001`/`1` → chi nhánh BENTHANH → Sao kê GD | SOTK=`BT0000001`, từ đầu tháng | Danh sách GD, SODU_LUYKE đúng sau mỗi GD |
| 07b | Login `admin`/`1` → chi nhánh TRACUU → Sao kê GD | SOTK=`TD0000001` (TK thuộc SQL2, TRACUU query qua LINK2) | SP đọc qua Linked Server, vẫn trả về kết quả |
| 07c | Login `admin`/`1` → chi nhánh TRACUU → Sao kê GD | SOTK=`XX9999999` (không tồn tại) | Lỗi: "Tài khoản không tồn tại trên hệ thống" |
| 07d | Login `BT001`/`1` → chi nhánh BENTHANH → Sao kê GD | SOTK=`BT0000001`, khoảng ngày không có GD | Trả về rỗng, SODU_DAUKY = SODU_CUOIKY |

> **Lưu ý TC-07b:** `TaiKhoan` được nhân bản full → SQL1/SQL2 đều có đủ TK cả 2 chi nhánh. Tuy nhiên dropdown của BT001 (role ChiNhanh) chỉ hiển thị TK theo MACN của NV → không thấy TD accounts. Phải test 07b từ `admin`/TRACUU vì `SP_SaoKeTaiKhoan` phiên bản TRACUU đọc GD qua `LINK1`+`LINK2`, gom giao dịch từ cả 2 chi nhánh.

### Hệ thống xử lý chi tiết

**Bước 1 — Node.js gọi SP**
- Code: [`routes/baocao.js:76`](../APP_NGANHANG/routes/baocao.js)
- `querySP(req, server, 'SP_SaoKeTaiKhoan', { SOTK, TUNGAY, DENNGAY })`

**Bước 2 — SP tìm SODU hiện tại (BƯỚC 1 trong SP)**
- SP: [`sql/stored_procedures/06_SP_SaoKeTaiKhoan.sql:18–30`](../sql/stored_procedures/06_SP_SaoKeTaiKhoan.sql)
- Đọc local: `SELECT SODU FROM TaiKhoan WHERE SOTK = @SOTK` (TaiKhoan nhân bản full → luôn có ở local, không cần LINK1)
- Không thấy → RAISERROR

**Bước 3 — Tính SODU đầu kỳ bằng kỹ thuật "trừ ngược" (BƯỚC 2 trong SP)**
- SP: [`06_SP_SaoKeTaiKhoan.sql:39–66`](../sql/stored_procedures/06_SP_SaoKeTaiKhoan.sql)
- Công thức: `SODU_DAUKY = SODU_HIENTAI - Σ(biến động từ @TUNGAY đến nay)`
- Biến động = GD_GOIRUT (local + LINK1) + GD_CHUYENTIEN (local + LINK1)
- Quy ước: `LOAIGD IN ('GT','NT')` → +SOTIEN; `IN ('RT','CT')` → -SOTIEN
- **Tại sao tính ngược?** → Không cần quét toàn bộ lịch sử từ ngày mở TK, chỉ quét từ @TUNGAY đến nay → tối ưu network IO khi đọc qua Linked Server

**Bước 4 — Chi tiết GD + số dư lũy kế bằng Window Function (BƯỚC 3 trong SP)**
- SP: [`06_SP_SaoKeTaiKhoan.sql:73–104`](../sql/stored_procedures/06_SP_SaoKeTaiKhoan.sql)
- `CTE TransactionsInPeriod`: gom GD từ local + LINK1 trong khoảng [@TUNGAY, @DENNGAY]
- `CTE RunningBalance`: dùng `SUM(...) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING) + @SODU_DAUKY`
- Kết quả: mỗi dòng GD có `SODU_LUYKE` — số dư sau giao dịch đó

**Cách kiểm tra trong DB:**
```sql
-- Chạy SP trực tiếp trên SSMS (SQL1):
EXEC SP_SaoKeTaiKhoan @SOTK = 'BT0000001', @TUNGAY = '2026-01-01', @DENNGAY = '2026-12-31';

-- Kiểm tra số dư hiện tại:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'BT0000001';
```

**Ví dụ minh họa 3 bước** (giải thích trực tiếp cho thầy):
```
Bước 1: SODU_HIENTAI = 10,000,000 (đọc local, TaiKhoan nhân bản full)
Bước 2: BIENDONG_SAU_TUNGAY = 2,000,000 → SODU_DAUKY = 10tr - 2tr = 8,000,000
Bước 3: Tính SODU_LUYKE bằng Window Function:
  NGAYGD     | LOAIGD | SOTIEN    | SODU_LUYKE
  -----------|--------|-----------|------------
  2026-07-01 | GT     | 5,000,000 | 13,000,000   (8tr + 5tr)
  2026-07-05 | RT     | 2,000,000 | 11,000,000   (13tr - 2tr)
  2026-07-10 | CT     | 1,000,000 | 10,000,000   (11tr - 1tr)
  2026-07-15 | NT     | 3,000,000 | 13,000,000   (10tr + 3tr)
  2026-07-20 | GT     | 2,000,000 | 15,000,000   (13tr + 2tr)
```

**Logic vấn đáp:**
- **Tại sao không tính từ đầu?** → TK có thể có hàng nghìn GD từ ngày mở → tốn bộ nhớ + network. Tính ngược chỉ cần quét từ `@TUNGAY` → nhanh hơn nhiều, đặc biệt khi phải kéo qua Linked Server.
- **Window Function `ROWS UNBOUNDED PRECEDING`?** → Tính tổng cộng dồn từ dòng đầu tiên đến dòng hiện tại, sort theo `NGAYGD`. Đây là SQL Server tự tính trong 1 lần scan, không cần vòng lặp.
- **Tại sao query cả local + LINK1?** → Giao dịch có thể phát sinh ở chi nhánh đối tác (chuyển tiền liên chi nhánh) → phải gom từ cả 2 mảnh để không thiếu dữ liệu.

---

## TC-08: Chuyển nhân viên — Giao dịch phân tán trên dữ liệu NhanVien

### Mục tiêu
Nhân viên chuyển từ chi nhánh này sang chi nhánh khác: xóa mềm local, insert sang chi nhánh đích.

### Tình huống test

| ID | Input | Kết quả kỳ vọng |
|----|-------|-----------------|
| 08a | Chuyển NV `BT001` sang TANDINH | BT001 TrangThaiXoa=1, SQL2 có record mới `TD00X` |
| 08b | Chuyển NV không tồn tại | Lỗi: "Nhân viên không tồn tại" |
| 08c | Chuyển NV sang chính chi nhánh hiện tại | Lỗi: "Chi nhánh mới phải khác hiện tại" |
| 08d | Chuyển NV đã bị xóa trước đó | Lỗi: "Nhân viên này đã bị xóa" |
| 08e | SQL2 sập trong lúc chuyển | ROLLBACK, BT001 không thay đổi |

### Hệ thống xử lý chi tiết

**Bước 1 — Node.js gọi SP trên server chi nhánh cũ**
- Code: [`routes/nhanvien.js:148–159`](../APP_NGANHANG/routes/nhanvien.js)
- Xác định server hiện tại từ MACN_MOI (chuyển đi đâu → hiện tại ở phía ngược lại)
- Gọi `execSPAdmin(serverHienTai, 'SP_ChuyenNhanVien', { MANV, MACN_MOI })`
- Dùng `execSPAdmin` (tài khoản hệ thống HTKN) thay vì `execSP` — vì SP cần INSERT qua LINK1 (user nhân viên không có quyền)

**Bước 2 — SP validate (BƯỚC 1 trong SP)**
- SP: [`sql/stored_procedures/08_SP_ChuyenNhanVien.sql:15–38`](../sql/stored_procedures/08_SP_ChuyenNhanVien.sql)
- Kiểm tra NV tồn tại + `TrangThaiXoa = 0` + `MACN_MOI ≠ MACN_HIENTAI`

**Bước 3 — Sinh MANV mới (BƯỚC 2 trong SP)**
- SP: [`08_SP_ChuyenNhanVien.sql:45–71`](../sql/stored_procedures/08_SP_ChuyenNhanVien.sql)
- Prefix theo MACN_MOI: `BENTHANH` → `BT`, `TANDINH` → `TD`
- Query qua LINK1: `SELECT TOP 1 MANV FROM [LINK1]...NhanVien WHERE MANV LIKE 'TD%' ORDER BY MANV DESC`
- Parse số + 1 → `TD004`
- Vòng lặp `WHILE EXISTS(...)` tránh race condition

**Bước 4 — Distributed Transaction (BƯỚC 3 trong SP)**
- SP: [`08_SP_ChuyenNhanVien.sql:77–95`](../sql/stored_procedures/08_SP_ChuyenNhanVien.sql)
- `BEGIN DISTRIBUTED TRAN`
- Local: `UPDATE NhanVien SET TrangThaiXoa = 1 WHERE MANV = @MANV`
- Sang chi nhánh đích: `INSERT INTO [LINK1].NGANHANG.dbo.NhanVien(...) SELECT @MANV_MOI, CMND, HO, TEN, ...`
- `COMMIT TRAN` → MSDTC 2-phase commit
- Trả về `MANV_MOI` cho Node.js hiển thị

**Cách kiểm tra trong DB:**
```sql
-- Trên SQL1 (BENTHANH) — NV cũ đã bị xóa mềm:
SELECT MANV, TrangThaiXoa FROM NhanVien WHERE MANV = 'BT001';

-- Trên SQL2 (TANDINH) — NV mới được tạo:
SELECT * FROM NhanVien WHERE MANV LIKE 'TD%' ORDER BY MANV DESC;
```

### Tình huống mở rộng — Chuyển rồi Phục hồi

| ID | Bước | Thao tác | Trạng thái SQL1 (BT) | Trạng thái SQL2 (TD) |
|----|------|----------|----------------------|----------------------|
| 08f-1 | Khởi đầu | BT001 đang làm việc | BT001: `TrangThaiXoa=0` | *(không có)* |
| 08f-2 | Chuyển | BT001 → TANDINH | BT001: `TrangThaiXoa=1` | TD00X: `TrangThaiXoa=0` |
| 08f-3 | Phục hồi | Phục hồi BT001 tại BENTHANH | BT001: `TrangThaiXoa=0` | TD00X: `TrangThaiXoa=1` ✅ |
| 08f-4 | Kiểm tra | Xem danh sách NV ở cả 2 chi nhánh | BT001 active | TD00X đã bị vô hiệu hóa |

**Kỳ vọng khi phục hồi:**
- BT001 tại BENTHANH → `TrangThaiXoa = 0` (đang làm việc)
- TD00X tại TANDINH → `TrangThaiXoa = 1` (tự động vô hiệu hóa)
- Thông báo: *"Đã phục hồi BT001 và tự động vô hiệu hóa TD00X ở chi nhánh kia"*

**Trường hợp lỗi cũ (trước khi fix):** Phục hồi chỉ SET local → BT001 + TD00X đều active → cùng 1 người có 2 mã NV đang làm việc song song = inconsistency.

**Cách fix:** SP `SP_PhucHoiNhanVien` dùng `BEGIN DISTRIBUTED TRAN` để đồng thời phục hồi local + deactivate bản ghi cùng CMND ở chi nhánh kia qua LINK1. Route phục hồi gọi `execSPAdmin` thay vì raw UPDATE.

**Cách kiểm tra trong DB:**
```sql
-- Sau khi phục hồi BT001:
SELECT MANV, TrangThaiXoa, MACN FROM NhanVien WHERE CMND = (SELECT CMND FROM NhanVien WHERE RTRIM(MANV)='BT001');
-- Trên SQL2: SELECT MANV, TrangThaiXoa FROM NhanVien WHERE CMND = '...'
```

**Logic vấn đáp:** Chuyển NV là giao dịch phân tán trên bảng phân mảnh ngang. Xóa mềm (TrangThaiXoa=1) ở site cũ — không xóa hẳng vì cần giữ lịch sử kiểm toán. INSERT với MANV mới có prefix chi nhánh đích → đảm bảo quy ước đặt tên nhất quán. MSDTC bảo đảm: nếu INSERT sang chi nhánh mới fail → xóa mềm ở chi nhánh cũ cũng ROLLBACK.

---

## TC-09: Phân quyền SQL — Role-Based Access Control

### Mục tiêu
Kiểm tra SQL Role giới hạn đúng thao tác.

### Tình huống test (thực hiện trực tiếp trên SSMS)

| ID | User | Lệnh | Kết quả kỳ vọng |
|----|------|------|-----------------|
| 09a | *(CMND KH)* (role KhachHang) | `SELECT * FROM TaiKhoan` | Permission denied |
| 09b | *(CMND KH)* | `EXEC sp_TaiKhoanKhachHang @CMND='...'` | Thành công |
| 09c | *(CMND KH)* | `EXEC SP_SaoKeTaiKhoan ...` | Thành công |
| 09d | `admin` (role NganHang) | `INSERT INTO TaiKhoan VALUES(...)` | Permission denied (DENY INSERT) |
| 09e | `BT001` (role ChiNhanh) | `SELECT * FROM TaiKhoan` | Thành công |
| 09f | `BT001` | `DROP TABLE TaiKhoan` | Permission denied |

### Hệ thống xử lý chi tiết

**Cấu hình phân quyền** — xem [`sql/setup/04_Role_PhanQuyen.sql`](../sql/setup/04_Role_PhanQuyen.sql)

```sql
-- Role ChiNhanh: Toàn quyền CRUD + EXECUTE
GRANT SELECT, INSERT, UPDATE, DELETE ON GD_CHUYENTIEN TO ChiNhanh;
GRANT SELECT, INSERT, UPDATE, DELETE ON TaiKhoan      TO ChiNhanh;
GRANT EXECUTE ON SCHEMA::dbo TO ChiNhanh;

-- Role NganHang: Chỉ đọc + EXECUTE (không sửa được dữ liệu)
GRANT  SELECT  ON SCHEMA::dbo TO NganHang;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO NganHang;   ← DENY ghi đè GRANT

-- Role KhachHang: Chỉ EXECUTE 2 SP cụ thể — không có SELECT trực tiếp
GRANT EXECUTE ON sp_TaiKhoanKhachHang TO KhachHang;
GRANT EXECUTE ON SP_SaoKeTaiKhoan     TO KhachHang;
```

**Cách kiểm tra trong DB:**
```sql
-- Xem user thuộc role nào:
EXEC sp_helpuser 'BT001';

-- Test quyền bằng cách đổi user context trên SSMS:
EXECUTE AS USER = 'BT001';
SELECT * FROM TaiKhoan;  -- Thành công (ChiNhanh có SELECT)
REVERT;

EXECUTE AS USER = 'admin';
INSERT INTO TaiKhoan VALUES('TEST', '001', 0, 'BENTHANH', GETDATE());  -- DENY!
REVERT;
```

**Logic vấn đáp:**
- **Tại sao KhachHang không có SELECT?** → Nếu có SELECT trên TaiKhoan, KH có thể đọc TK của người khác. SP kiểm soát điều kiện `WHERE CMND = @CMND` → chỉ thấy dữ liệu của mình.
- **DENY vs không GRANT khác gì nhau?** → Không GRANT = mặc định bị từ chối. DENY = tường minh chặn, ngay cả khi user thuộc nhiều role khác nhau có GRANT thì DENY vẫn thắng (DENY ưu tiên cao nhất trong SQL Server).
- **Bảo mật 3 tầng:** (1) Database Role — `DENY INSERT/UPDATE/DELETE` tại tầng DB, (2) Backend Middleware — `requireChiNhanh` chặn route ghi tại tầng Node.js (đảm bảo NganHang không thể mở/đóng TK, thêm/sửa/xóa KH/NV dù biết URL), (3) UI — ẩn nút thao tác theo `user.NHOM`.

---

## TC-10: Đóng tài khoản — Kiểm tra điều kiện

### Tình huống test

| ID | Điều kiện | Kết quả kỳ vọng |
|----|-----------|-----------------|
| 10a | SOTK hợp lệ, SODU=0, không có GD | Xóa thành công |
| 10b | SOTK có SODU > 0 | Lỗi: "Không thể đóng TK có số dư khác 0" |
| 10c | SOTK đã có GD lịch sử | Lỗi: "Không thể đóng TK đã có giao dịch" |
| 10d | SOTK không tồn tại | Lỗi: "Tài khoản không tồn tại" |

### Hệ thống xử lý chi tiết

**Bước 1 — Kiểm tra quyền (Node.js)**
- Code: [`routes/taikhoan.js`](../APP_NGANHANG/routes/taikhoan.js) — middleware `requireChiNhanh`
- Chỉ `ChiNhanh` được đóng TK — `NganHang` bị chặn HTTP 403

**Bước 2 — Kiểm tra SODU = 0**
- Code: [`routes/taikhoan.js:116–122`](../APP_NGANHANG/routes/taikhoan.js)
- `SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK) = @sotk`
- Nếu `SODU !== 0` → redirect với lỗi

**Bước 3 — Kiểm tra không có giao dịch**
- Code: [`routes/taikhoan.js:125–133`](../APP_NGANHANG/routes/taikhoan.js)
- `SELECT COUNT(*) FROM GD_GOIRUT WHERE SOTK = @sotk`
- `SELECT COUNT(*) FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @sotk OR SOTK_NHAN = @sotk`
- Nếu có bất kỳ GD nào → lỗi "Không thể đóng TK đã có giao dịch"

**Bước 4 — Xóa TK**
- Code: [`routes/taikhoan.js:136`](../APP_NGANHANG/routes/taikhoan.js)
- `DELETE FROM TaiKhoan WHERE RTRIM(SOTK) = @sotk`

**Cách kiểm tra trong DB:**
```sql
-- Kiểm tra TK có GD không:
SELECT COUNT(*) FROM GD_GOIRUT WHERE SOTK = 'BT0000001';
SELECT COUNT(*) FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = 'BT0000001' OR SOTK_NHAN = 'BT0000001';
```

**Logic vấn đáp:** Đóng TK là thao tác DELETE thật (không xóa mềm) — chỉ được phép khi SODU = 0 VÀ không có lịch sử GD. Lý do: nếu có GD, xóa TK sẽ phá vỡ ràng buộc tham chiếu (FK) từ bảng GD_GOIRUT/GD_CHUYENTIEN. Logic kiểm tra nằm ở tầng Node.js (không dùng SP riêng) — 3 query tuần tự trước khi DELETE.

---

## TC-11: Kiểm tra Linked Server — Kết nối liên site (qua giao diện)

### Mục tiêu
Xác nhận Linked Server đang hoạt động bằng cách thực hiện các thao tác trên giao diện web — các thao tác này chỉ thành công khi LINK1/LINK2 hoạt động.

### Tình huống test

| ID | Cách thực hiện trên giao diện | Kết quả kỳ vọng | Linked Server nào được dùng |
|----|-------------------------------|-----------------|----------------------------|
| 11a | Login `BT001`/BENTHANH → Chuyển tiền `BT0000001` → `TD0000001`, số tiền hợp lệ | Thành công, SODU 2 TK cập nhật | SQL1 → `[LINK1]` → SQL2 |
| 11b | Login `admin`/TRACUU → Sao kê GD → chọn SOTK `BT0000001` | Hiển thị được lịch sử GD | SQL3 → `[LINK1]` → SQL1 |
| 11c | Login `admin`/TRACUU → Sao kê GD → chọn SOTK `TD0000001` | Hiển thị được lịch sử GD | SQL3 → `[LINK2]` → SQL2 |
| 11d | Login `admin`/TRACUU → Liệt kê Nhân viên | Hiển thị NV cả BENTHANH lẫn TANDINH | SQL3 → `[LINK1]`+`[LINK2]` |
| 11e | Tắt SQL2 → Login `BT001` → Chuyển tiền sang TD | Thông báo lỗi "Linked Server unreachable" | Chứng minh phụ thuộc Linked Server |

**Logic vấn đáp:**
- **Linked Server là gì?** → Cơ chế SQL Server cho phép query sang SQL Server khác bằng cú pháp `[SERVER_NAME].database.schema.table` — như thể truy vấn bảng local.
- **Có cần Linked Server để chuyển tiền không?** → Có, bắt buộc. `sp_ChuyenTien` dùng `[LINK1]` để UPDATE số dư TK ở chi nhánh đối tác trong cùng 1 Distributed Transaction.
- **Nếu Linked Server đứt thì sao?** → Giao dịch phân tán ROLLBACK hoàn toàn — tiền không bị mất, MSDTC đảm bảo ACID.

---

## TC-12: Kiểm tra Merge Replication — Đồng bộ dữ liệu (qua giao diện)

### Mục tiêu
Xác nhận dữ liệu KhachHang đồng bộ từ SQL1/SQL2 lên SQL3 sau khi Merge Agent chạy.

### Tình huống test

| ID | Bước 1 — Thao tác tạo dữ liệu | Bước 2 — Kiểm tra sau sync | Kết quả kỳ vọng |
|----|-------------------------------|----------------------------|-----------------|
| 12a | Login `BT001`/BENTHANH → Khách hàng → Thêm KH mới (CMND mới chưa có) | Login `admin`/TRACUU → Liệt kê KH → tìm CMND vừa thêm | KH xuất hiện trên TRACUU sau khi Merge Agent sync |
| 12b | Login `TD001`/TANDINH → Khách hàng → Thêm KH mới | Login `admin`/TRACUU → Liệt kê KH | KH của TANDINH cũng hiện trên TRACUU |
| 12c | Login `BT001` → Sửa thông tin 1 KH (HO/TEN) | Login `admin`/TRACUU → kiểm tra KH đó | Thông tin đã cập nhật trên TRACUU |
| 12d | Kiểm tra replication qua SSMS | SSMS → ES-HAITD16 → Replication Monitor → PUB_TRACUU → xem tab Synchronization History | Trạng thái "Succeeded", thời gian sync gần nhất hợp lệ |

> **Lưu ý:** Sau bước tạo dữ liệu, cần trigger Merge Agent sync thủ công (SSMS → Replication Monitor → right-click Subscription → Start Synchronizing) nếu không chạy continuous.

**Logic vấn đáp:**
- **Tại sao chỉ replicate KhachHang sang SQL3?** → SQL3 là trạm tra cứu — chỉ cần biết "khách hàng nào trong hệ thống". Giao dịch và số dư lấy real-time qua Linked Server.
- **Merge vs Transactional Replication?** → Hệ thống dùng **Merge Replication** — cho phép cả Publisher lẫn Subscriber đều có thể ghi, conflict giải quyết bởi conflict resolver (mặc định: Publisher thắng).

---

## TC-13: Kiểm tra SQL Server Agent Job — Replication tự động (qua SSMS)

### Mục tiêu
Xác nhận các Job tự động hóa Replication đang chạy đúng (thực hiện trên SSMS — không có giao diện web cho phần này).

### Tình huống test (SSMS trên ES-HAITD16 → SQL Server Agent → Jobs)

| ID | Job cần kiểm tra | Cách xem | Kết quả kỳ vọng |
|----|-----------------|----------|-----------------|
| 13a | Merge Agent job: `NGUON-PUB_TRACUU-SQL3-...` | Right-click → View History | Last run: Succeeded |
| 13b | Merge Agent job: `NGUON-PUB_BENTHANH-SQL1-...` | Right-click → View History | Last run: Succeeded |
| 13c | Merge Agent job: `NGUON-PUB_TANDINH-SQL2-...` | Right-click → View History | Last run: Succeeded |
| 13d | Chạy thủ công Merge Agent | Right-click job → Start Job at Step | Hoàn thành "no data changes" hoặc "merged N change(s)" |
| 13e | Replication Monitor tổng quan | ES-HAITD16 → Replication → Launch Replication Monitor | 3 subscription đều xanh (không đỏ) |

**Logic vấn đáp:**
- **SQL Agent Job và Replication liên quan thế nào?** → Mỗi Publication tự tạo các Job: Snapshot Agent (tạo snapshot ban đầu), Merge Agent (đồng bộ định kỳ). Job fail → replication dừng, dữ liệu lạc hậu.
- **"No data changes processed" có phải lỗi không?** → Không — nghĩa là không có thay đổi cần sync trong chu kỳ đó, replication hoạt động bình thường.

> **Lưu ý khi demo 13d — bấm Start Job báo "Error" ngay lập tức:**
> SQL Server Agent chỉ cho phép **1 instance của 1 job chạy tại 1 thời điểm**. Nếu job đang chạy (Continuous/Executing) mà bấm **Start** lần nữa → Agent từ chối ngay với lỗi "Start Job ... Error / request refused because the job is already running" (dialog "Start Jobs" báo đỏ, 0 Success) — **đây là hành vi bình thường, không phải lỗi hệ thống hay lỗi replication**.
> Cách xử lý: bấm **Stop** job trước (đưa job về trạng thái Idle) → rồi bấm **Start** lại → chạy thành công bình thường. Nếu giảng viên/hội đồng lỡ bấm Start khi job đang chạy, giải thích đúng nguyên nhân này thay vì lúng túng.

---

## TC-14: Khách hàng mở tài khoản ở nhiều chi nhánh (qua giao diện)

### Mục tiêu
Xác nhận 1 khách hàng (cùng CMND) có thể mở tài khoản ở cả 2 chi nhánh, và khi mở TK ở chi nhánh thứ 2 thì hệ thống **tự tra CMND không cần nhập lại họ tên**.

### Tình huống test

| ID | Cách thực hiện trên giao diện | Input | Kết quả kỳ vọng |
|----|-------------------------------|-------|-----------------|
| 14a | Login `BT001`/`1` → BENTHANH → Tài khoản → Mở tài khoản | CMND=`9988776655` *(chưa có trong hệ thống)*, HO=`Nguyen`, TEN=`Van X`, SoDuBanDau=500.000 | TK `BT000000X` tạo thành công |
| 14b | Login `TD001`/`1` → TANDINH → Tài khoản → Mở tài khoản | Chỉ nhập CMND=`9988776655`, SoDuBanDau=200.000 — **không nhập HO/TEN** | TK `TD000000X` tạo thành công; SP tự tra HO/TEN từ KhachHang đã có |
| 14c | Login `admin`/`1` → TRACUU → Liệt kê Khách hàng | Tìm CMND `9988776655` | Hiển thị KH với 2 TK: 1 BT + 1 TD |
| 14d | Login `admin`/`1` → TRACUU → Sao kê GD → SOTK `BT000000X` | Khoảng ngày bất kỳ | Hiển thị lịch sử GD của TK BENTHANH |
| 14e | Login KH `9988776655`/`123456` → BENTHANH → Tài khoản của tôi | — | Chỉ thấy TK `BT...` (không thấy TK TANDINH) |

> **Chuẩn bị:** Cần tạo SQL Login cho KH `9988776655` trước khi test 14e — dùng chức năng Tạo tài khoản (Login) từ tài khoản admin hoặc BT001.

### Điểm trình bày khi bảo vệ

- **Tại sao KH không cần nhập lại họ tên ở chi nhánh 2?** → CMND là định danh duy nhất. Form mở TK dùng dropdown hiển thị KH từ cả 2 chi nhánh (qua `getAllKhachHang()` sử dụng admin pool + LINK1). Chọn KH → tự động có CMND + chi nhánh KH.
- **Dữ liệu KH lưu ở đâu?** → Phân mảnh ngang theo `MACN`: KH đăng ký ở BENTHANH → lưu SQL1, KH đăng ký TANDINH → lưu SQL2. Cả 2 replicate lên SQL3.
- **Cross-branch INSERT thỏa FK thế nào?** → TaiKhoan có 2 FK: `FK_TaiKhoan_KhachHang` (CMND) và `FK_TaiKhoan_ChiNhanh` (MACN). KhachHang + ChiNhanh đều phân mảnh ngang → cả 2 FK chỉ thỏa trên server có KH. Giải pháp: khi NV chi nhánh A mở TK cho KH chi nhánh B → MACN = chi nhánh B, INSERT chạy trên server B (via `execSPAdmin`) → cả 2 FK thỏa → TK replicate full sang server A.
- **Có bị trùng CMND không?** → Khoá duy nhất là `CMND + MACN`. Cùng CMND, khác MACN là hợp lệ — 1 người có thể có TK ở 2 chi nhánh.

---

## Tóm tắt các điểm phân tán quan trọng để trả lời khi bảo vệ

| Câu hỏi | Trả lời ngắn | Xem code/SP |
|---------|-------------|-------------|
| Phân mảnh kiểu gì? | Phân mảnh ngang cho KH/NV/GD (theo MACN); **Nhân bản toàn vẹn** cho TaiKhoan và ChiNhanh | `07_Database_Schema.md` |
| TaiKhoan nhân bản thì chuyển tiền xử lý thế nào? | SP đọc MACN local (nhanh), so sánh MACN → cùng CN ghi local, khác CN ghi qua LINK1 | `07_SP_ChuyenTien.sql:44–46` |
| TRACUU chứa gì? | Chỉ replicate bảng KhachHang (1 article). GD/TK/NV lấy qua LINK1+LINK2 | `12_SP_DanhSachTaiKhoan.sql` |
| Tái cấu trúc (reconstruction) ở đâu? | SQL3 (TRACUU) dùng SP + LINK1+LINK2 gộp dữ liệu từ 2 chi nhánh | `sp_DanhSachTaiKhoan`, `sp_DanhSachNhanVien` |
| Giao dịch phân tán dùng gì? | MSDTC + `BEGIN DISTRIBUTED TRANSACTION` trong T-SQL | `07_SP_ChuyenTien.sql:49` |
| Tại sao dùng sqlcmd thay tedious? | Driver tedious không hỗ trợ MSDTC; sqlcmd dùng Native Client hỗ trợ 2PC | `db.js` hàm `execSP` |
| Đảm bảo không trùng SOTK? | Prefix theo chi nhánh (BT/TD) → không bao giờ giao nhau | `taikhoan.js:9` |
| KhachHang xem dữ liệu thế nào? | Qua SP với filter CMND — không có SELECT trực tiếp | `14_SP_TaiKhoanKhachHang.sql` |
| Nếu 1 node sập khi chuyển tiền? | MSDTC ROLLBACK toàn bộ (ACID đảm bảo) | `07_SP_ChuyenTien.sql:80–84` |
| Window Function trong sao kê? | `SUM() OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` = running balance | `06_SP_SaoKeTaiKhoan.sql:93–99` |

---

## TC-15: Phân quyền theo Nhóm — Yêu cầu đề bài

> Kiểm thử toàn diện 3 nhóm người dùng theo đúng yêu cầu: NganHang xem tất cả, ChiNhanh toàn quyền chi nhánh mình, KhachHang chỉ xem sao kê.

### TC-15A — Nhóm NganHang (Ban Giám Đốc)

| ID | Thao tác | Kỳ vọng | Điểm phân tán |
|----|----------|---------|---------------|
| NH-01 | Login `admin/1`, chọn **BENTHANH** | Đăng nhập thành công, nav hiện `NganHang \| BENTHANH \| TRACUU` | effectiveServer tự gán TRACUU |
| NH-02 | Login `admin/1`, chọn **TANDINH** | Đăng nhập thành công, **dữ liệu y chang NH-01** | Chứng minh site chọn không ảnh hưởng |
| NH-03 | Vào **Khách hàng** → thấy KH cả 2 chi nhánh | BT + TD đều hiển thị | KhachHang replicate toàn vẹn lên TRACUU |
| NH-04 | Vào **Nhân viên** → thấy NV cả 2 chi nhánh | BT + TD đều hiển thị | sp_DanhSachNhanVien dùng LINK1+LINK2 |
| NH-05 | Vào **Tài khoản** → thấy TK cả 2 chi nhánh | BT + TD đều hiển thị | sp_DanhSachTaiKhoan dùng LINK1+LINK2 |
| NH-06 | Kiểm tra nút thao tác trong danh sách KH/NV/TK | **Không thấy** Thêm / Sửa / Xóa / Đóng TK | UI ẩn theo `user.NHOM === 'ChiNhanh'` |
| NH-07 | Thử URL thẳng `/khachhang/them` | **HTTP 403** — Không có quyền | `requireChiNhanh` middleware |
| NH-08 | Thử URL `/nhanvien/them` | **HTTP 403** | |
| NH-09 | Vào **Tạo tài khoản (Login)** → chọn nhóm **NganHang** → tạo | Thành công | NganHang tạo được cùng nhóm |
| NH-10 | Tạo tài khoản → chọn nhóm **ChiNhanh** → tạo | Thành công | NganHang tạo được mọi nhóm |
| NH-11 | Tạo tài khoản → chọn nhóm **KhachHang** → tạo | Thành công | |
| NH-12 | Sao kê GD → chọn TK bất kỳ (BT hoặc TD) | Hiển thị lịch sử đầy đủ | SP_SaoKeTaiKhoan phiên bản TRACUU đọc LINK1+LINK2 |

### TC-15B — Nhóm ChiNhanh

| ID | Thao tác | Kỳ vọng | Điểm phân tán |
|----|----------|---------|---------------|
| CN-01 | Login `BT001/1`, chọn **BENTHANH** | Thành công, MACN=BENTHANH | |
| CN-02 | Login `BT001/1`, chọn **TANDINH** | **Lỗi:** "Bạn không có quyền đăng nhập vào chi nhánh này" | SQL Login BT001 không tồn tại trên SQL2 |
| CN-03 | Login `TD001/1`, chọn **TANDINH** | Thành công, MACN=TANDINH | |
| CN-04 | BT001 → Khách hàng → thấy **chỉ KH BENTHANH** | Không thấy KH TANDINH | Phân mảnh ngang theo MACN |
| CN-05 | BT001 → **Thêm KH mới** | Thành công, KH lưu vào SQL1 | |
| CN-06 | BT001 → **Sửa** thông tin KH | Thành công | |
| CN-07 | BT001 → **Xóa** KH chưa có TK | Thành công | |
| CN-08 | BT001 → **Mở TK** cho KH BENTHANH | Thành công, SOTK = `BT00000XX` | Prefix BT tránh trùng với TD |
| CN-09 | BT001 → **Gửi tiền** TK BENTHANH | Thành công | |
| CN-10 | BT001 → **Rút tiền** TK BENTHANH | Thành công (nếu đủ số dư) | |
| CN-11 | BT001 → **Chuyển tiền** BT → TD | Thành công, MSDTC phân tán | SQL1+SQL2, 2-phase commit |
| CN-12 | TD001 (TANDINH) → **Sao kê** TK `BT0000001` sau khi nhận chuyển tiền | Thấy GD nhận (NT) | SP đọc LINK bên TANDINH |
| CN-13 | Tạo tài khoản → nhóm **ChiNhanh** → thành công | ✅ | ChiNhanh tạo được cùng nhóm |
| CN-14 | Tạo tài khoản → nhóm **NganHang** → **bị từ chối** | Lỗi: "Quyền hạn không hợp lệ" | `quantri.js:82` chặn backend |

### TC-15C — Nhóm KhachHang

| ID | Thao tác | Kỳ vọng | Điểm phân tán |
|----|----------|---------|---------------|
| KH-01 | Login `1111111111/123456`, chọn **BENTHANH** | Thành công, sidebar **chỉ thấy "Sao kê GD"** | |
| KH-02 | Login `1111111111/123456`, chọn **TANDINH** | Thành công, **dữ liệu y chang KH-01** | TaiKhoan replicate toàn vẹn |
| KH-03 | Vào **Tài khoản của tôi** | Thấy đủ các TK của mình (kể cả TK ở chi nhánh khác) | sp_TaiKhoanKhachHang đọc local (TK replicate full) |
| KH-04 | Thử URL `/khachhang` | Redirect hoặc 403 | requireLogin → KhachHang không có menu này |
| KH-05 | Thử URL `/nhanvien` | Redirect hoặc 403 | |
| KH-06 | Thử URL `/quantri/taotaikhoan` | 403 | |
| KH-07 | Sao kê GD → chọn TK của mình → thấy lịch sử | ✅ | SP lọc theo CMND — chỉ thấy dữ liệu của mình |
| KH-08 | **Không thể thấy** TK của người khác trong sao kê | Dropdown chỉ liệt kê TK của CMND đang login | sp_TaiKhoanKhachHang: `WHERE CMND = @CMND` |
| KH-09 | KhachHang **không tạo được tài khoản** | Menu "Tạo tài khoản" không hiện trong sidebar | UI ẩn + backend không expose route cho KhachHang |

---

## TC-16: Giao dịch tài khoản xuyên chi nhánh (Gửi / Rút / Chuyển tiền)

> Kịch bản: NV chi nhánh A thực hiện giao dịch cho TK thuộc chi nhánh B.
> **Nguyên tắc:** SP luôn chạy trên server NV → GD ghi đúng mảnh (GD_GOIRUT/GD_CHUYENTIEN phân mảnh theo NV). UPDATE TK qua LINK1 nếu TK thuộc chi nhánh khác (Distributed Transaction).

### Testcase gửi/rút tiền cross-branch

| ID | Login | Thao tác | Kỳ vọng | Điểm phân tán |
|----|-------|----------|---------|---------------|
| GD-01a | `BT001` / BENTHANH | Gửi tiền vào `BT0000001` (TK thuộc BT), 200.000đ | Thành công — UPDATE TK **local** | Cùng CN → không cần LINK1. GD_GOIRUT ghi trên SQL1 |
| GD-01b | `BT001` / BENTHANH | Gửi tiền vào `TD0000001` (TK thuộc TD), 500.000đ | Thành công — UPDATE TK **qua LINK1** | SP chạy trên SQL1, so sánh MACN TK (TD) ≠ MACN NV (BT) → UPDATE qua LINK1. GD_GOIRUT ghi trên SQL1 (đúng mảnh NV) |
| GD-01c | `TD001` / TANDINH | Rút tiền từ `BT0000001` (TK thuộc BT), 100.000đ | Thành công — UPDATE TK **qua LINK1** | SP chạy trên SQL2, MACN TK (BT) ≠ MACN NV (TD) → UPDATE qua LINK1. GD_GOIRUT ghi trên SQL2 |
| GD-01d | `BT001` / BENTHANH | Rút tiền từ `TD0000001`, số dư không đủ | Lỗi "Số dư không đủ" | `@@ROWCOUNT = 0` sau UPDATE qua LINK1 → ROLLBACK |

### Testcase chuyển tiền cross-branch

| ID | Login | Thao tác | Kỳ vọng | Điểm phân tán |
|----|-------|----------|---------|---------------|
| GD-02a | `BT001` / BENTHANH | Chuyển `BT0000001` → `TD0000001`, 500.000đ | Thành công, MSDTC commit 2 server | SQL1 trừ TK chuyển local, cộng TK nhận qua LINK1 |
| GD-02b | `TD001` / TANDINH | Chuyển `TD0000001` → `BT0000001`, 300.000đ | Thành công | SQL2 trừ local, cộng qua LINK1. GD_CHUYENTIEN ghi SQL2 |

### Testcase sao kê (xác nhận GD ghi đúng mảnh)

| ID | Login | Thao tác | Kỳ vọng | Điểm phân tán |
|----|-------|----------|---------|---------------|
| GD-03a | `1111111111` / BENTHANH | Sao kê `BT0000001` | Thấy đủ: GD gửi/rút tại BT + GD nhận chuyển tiền từ TD | SP đọc GD_GOIRUT local + GD_CHUYENTIEN local + qua LINK1 |
| GD-03b | `1111111111` / TANDINH | Sao kê `BT0000001` | **Vẫn thấy đủ GD** như login BENTHANH | TaiKhoan replicate toàn vẹn; SP đọc LINK1 từ SQL2 |
| GD-03c | `admin` / BENTHANH | Sao kê `BT0000001` | Thấy đủ GD từ cả 2 phía | SP_SaoKeTaiKhoan phiên bản TRACUU: LINK1+LINK2 |

### Kiểm tra dữ liệu trên DB sau test

```sql
-- Trên SQL1 (BENTHANH): GD_GOIRUT có GD do NV BT001 thực hiện
SELECT * FROM GD_GOIRUT WHERE RTRIM(MANV) = 'BT001';
-- Kỳ vọng: thấy GD gửi/rút cho cả TK BT lẫn TK TD (NV BT001 thực hiện)

-- Trên SQL2 (TANDINH): GD_GOIRUT có GD do TD001 thực hiện
SELECT * FROM GD_GOIRUT WHERE RTRIM(MANV) = 'TD001';
-- Kỳ vọng: thấy GD rút cho TK BT (NV TD thực hiện, GD ghi trên SQL2)

-- Quan trọng: GD_GOIRUT trên SQL1 KHÔNG có GD của TD001, và ngược lại
-- → Chứng minh GD phân mảnh đúng theo NV
```

### Điểm giải thích với thầy

- **TK mở tại BT nhưng KH giao dịch tại TD:** Trong thực tế, KH cầm thẻ đến TD nộp tiền — nhân viên TD nhập SOTK của TK BT. Hệ thống hỗ trợ đầy đủ: dropdown hiển thị tất cả TK (TaiKhoan nhân bản toàn vẹn), NV có thể gửi/rút/chuyển tiền cho TK thuộc chi nhánh khác.
- **SP luôn chạy trên server NV:** `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` đều so sánh MACN TK vs MACN NV → quyết định UPDATE local hoặc qua LINK1. GD_GOIRUT/GD_CHUYENTIEN **luôn INSERT local** → đúng mảnh phân mảnh ngang theo NV.
- **Tại sao không route SP sang server TK?** Vì GD_GOIRUT/GD_CHUYENTIEN phân mảnh theo NV (article replication filter theo MACN NV). Nếu SP chạy trên server khác → GD ghi sai mảnh → Replication không đồng bộ đúng.
- **Sao kê thấy GD ở cả 2 nơi:** Chứng minh `SP_SaoKeTaiKhoan` gom dữ liệu từ `GD_GOIRUT` + `GD_CHUYENTIEN` tại cả 2 server qua LINK1/LINK2.

---

## TC-17: Tạo Login và Phân quyền — Chương trình quản lý tài khoản

> Kiểm thử chức năng "Tạo tài khoản (Login)" — cho phép NganHang/ChiNhanh tạo login mới gắn với nhóm quyền.

| ID | Người thực hiện | Nhóm tạo | Kỳ vọng |
|----|-----------------|----------|---------|
| TK-01 | `admin` (NganHang) | NganHang | Login mới tạo trên cả 3 server (BT/TD/TRACUU), gán role NganHang |
| TK-02 | `admin` (NganHang) | ChiNhanh | Login mới tạo trên cả 3 server, gán role ChiNhanh |
| TK-03 | `admin` (NganHang) | KhachHang | Login mới tạo trên cả 3 server, gán role KhachHang |
| TK-04 | `BT001` (ChiNhanh) | ChiNhanh | Thành công |
| TK-05 | `BT001` (ChiNhanh) | KhachHang | Thành công |
| TK-06 | `BT001` (ChiNhanh) | NganHang | **Lỗi:** "Quyền hạn không hợp lệ. Bạn chỉ có thể tạo tài khoản nhóm ChiNhanh hoặc KhachHang" |
| TK-07 | Dùng login mới (NganHang) vừa tạo để đăng nhập | — | Đăng nhập thành công, có quyền NganHang |
| TK-08 | Dùng login mới (ChiNhanh) đăng nhập vào BENTHANH | — | Thành công (nếu login mapping đúng MACN=BENTHANH) |
| TK-09 | Login ChiNhanh đăng nhập vào **sai** chi nhánh (TANDINH) | **Lỗi:** "Tài khoản SQL chưa được phân quyền" | NV chỉ có record ở CN mình |

### TC-17B — Đổi nhóm quyền (Change Role)

> Kiểm thử chức năng "Đổi nhóm" — chỉ NganHang có thể thay đổi nhóm quyền của tài khoản đã tạo. Tài khoản `admin` hệ thống được bảo vệ không cho đổi.

| ID | Thao tác | Kỳ vọng | Ghi chú |
|----|----------|---------|---------|
| CR-01 | `admin` đổi TK từ NganHang → ChiNhanh | Thành công trên cả 3 server | `sp_droprolemember` cũ + `sp_addrolemember` mới |
| CR-02 | Login TK vừa đổi vào đúng CN | Đăng nhập thành công, nhóm = ChiNhanh | Menu ChiNhanh đầy đủ (Gửi/Rút, Chuyển tiền...) |
| CR-03 | TK ChiNhanh sau đổi → xem Liệt kê KH | Chỉ thấy KH **chi nhánh mình** | Phân mảnh ngang hoạt động đúng |
| CR-04 | TK ChiNhanh sau đổi → xem Sao kê | Dropdown TK hiển thị, sao kê hoạt động | |
| CR-05 | `admin` đổi TK từ ChiNhanh → NganHang | Thành công | Chiều ngược lại cũng OK |
| CR-06 | Thử đổi nhóm quyền tài khoản `admin` | **Lỗi 403:** "Không được phép thay đổi nhóm quyền của tài khoản admin hệ thống" | Backend chặn cứng + UI ẩn nút |
| CR-07 | ChiNhanh thử gọi API đổi nhóm | **Lỗi 403** | `requireNganHang` middleware chặn |

### Hệ thống xử lý

- Code tạo TK: [`routes/quantri.js:65–129`](../APP_NGANHANG/routes/quantri.js)
- Code đổi nhóm: [`routes/quantri.js` — POST `/quantri/login-management/change-role`](../APP_NGANHANG/routes/quantri.js)
- SP `SP_TaoTaiKhoan` chạy trên **cả 3 server** (BENTHANH, TANDINH, TRACUU) — idempotent (bỏ qua nếu đã tồn tại)
- Kiểm tra phạm vi quyền tại backend: `quantri.js:79–83`
- Login được lưu vào `QuanTriLogin` (bảng quản trị riêng) để theo dõi
- Đổi nhóm: `sp_droprolemember` role cũ + `sp_addrolemember` role mới + UPDATE `QuanTriLogin` trên cả 3 server
- Bảo vệ admin: Backend chặn `loginName === 'admin'` (403), UI ẩn nút "Đổi nhóm" cho row admin
- **Tại sao tạo/đổi trên cả 3 server?** → KhachHang có thể login từ BENTHANH hoặc TANDINH (TaiKhoan replicate toàn vẹn); NganHang query TRACUU → cần login tồn tại trên TRACUU; ChiNhanh chỉ cần server mình nhưng đồng bộ để an toàn.
