# Testcase Kiểm Thử & Giải Thích Hệ Thống Ngân Hàng Phân Tán
> Mục đích: Dùng để thực hành kiểm thử, hiểu luồng xử lý từ Node.js → SQL Server, và cơ chế phân tán khi bảo vệ đồ án.

---

## Tài khoản Demo (dùng cho toàn bộ testcase)

> Xem danh sách đầy đủ tại [`03_DemoAccounts.md`](03_DemoAccounts.md).

| Nhóm | SQL Login | Password | Chi nhánh chọn | Role |
|------|-----------|----------|----------------|------|
| ChiNhanh (BT) | `BT001` | `1` | `BENTHANH` | ChiNhanh |
| ChiNhanh (TD) | `TD001` | `1` | `TANDINH` | ChiNhanh |
| NganHang | `admin` | `1` | `TRACUU` | NganHang |
| KhachHang | *(CMND KH, ví dụ `9999900001`)* | *(tự đặt khi tạo SQL Login)* | `BENTHANH` hoặc `TANDINH` | KhachHang |

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
| 01d | username=`admin`, password=`1`, chi nhánh=`TRACUU` | Thành công, NHOM=NganHang, MACN=TRACUU *(xem giải thích bên dưới)* |
| 01e | username=`1111111111`, password=`1`, chi nhánh=`BENTHANH` | Thành công, NHOM=KhachHang *(xem điều kiện tiên quyết bên dưới)* |

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
Sau khi chạy: username = CMND (`1111111111`), password = `1`, chi nhánh = `BENTHANH`.

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
| 02b | `BT001` (ChiNhanh-BENTHANH) | Chỉ thấy TK có `MACN=BENTHANH` |
| 02c | *(CMND KH)* (KhachHang) | Chỉ thấy TK của chính mình (theo CMND) |

### Hệ thống xử lý chi tiết

**Nhánh NganHang (admin):**
- Code: [`routes/taikhoan.js:31–34`](../APP_NGANHANG/routes/taikhoan.js)
- Gọi `querySP(req, 'TRACUU', 'sp_DanhSachTaiKhoan', {})` → SP chạy trên SQL3
- SP [`sql/stored_procedures/12_SP_DanhSachTaiKhoan.sql`](../sql/stored_procedures/12_SP_DanhSachTaiKhoan.sql): đọc `TaiKhoan` qua `LINK1` (SQL1) + `LINK2` (SQL2), JOIN `KhachHang` local (TRACUU replicate full KhachHang)
- Kết quả: danh sách toàn bộ TK hệ thống

**Nhánh ChiNhanh (BT001):**
- Code: [`routes/taikhoan.js:36–46`](../APP_NGANHANG/routes/taikhoan.js)
- Query raw SQL: `SELECT ... FROM TaiKhoan tk LEFT JOIN KhachHang kh ... WHERE RTRIM(tk.MACN) = @macn`
- Chỉ query trên server local của chi nhánh đó → chỉ thấy TK thuộc chi nhánh mình

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
ChiNhanh chỉ query local. 
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
| 03d | Mở TK với SODU âm | Lỗi từ SP (constraint check) |
| 03e | KhachHang cố mở TK | HTTP 403 — Không có quyền |

### Hệ thống xử lý chi tiết

**Bước 1 — Sinh SOTK (khi mở form)**
- Code: [`routes/taikhoan.js:12–21`](../APP_NGANHANG/routes/taikhoan.js) (hàm `sinhSOTK`)
- Logic: `SELECT TOP 1 SOTK FROM TaiKhoan WHERE SOTK LIKE 'BT%' ORDER BY SOTK DESC` → parse số cuối + 1 → pad 7 chữ số → `BT0000001`
- Prefix: `BENTHANH` → `BT`, `TANDINH` → `TD` (map tại dòng 9: `MACN_PREFIX`)

**Bước 2 — Kiểm tra quyền**
- Code: [`routes/taikhoan.js:62–65`](../APP_NGANHANG/routes/taikhoan.js)
- `if (!['NganHang', 'ChiNhanh'].includes(user.NHOM))` → HTTP 403
- KhachHang bị chặn ở tầng Node.js (middleware), không đến được SQL

**Bước 3 — Gọi SP mở TK**
- Code: [`routes/taikhoan.js:93–94`](../APP_NGANHANG/routes/taikhoan.js)
- `execSP(req, server, 'sp_MoTaiKhoan', { SOTK, CMND, SODU, MACN })`
- SP [`sql/stored_procedures/11_SP_TaoTaiKhoan.sql`](../sql/stored_procedures/11_SP_TaoTaiKhoan.sql): kiểm tra CMND tồn tại, INSERT INTO TaiKhoan
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
| 07c | Login `admin`/`1` → chi nhánh TRACUU → Sao kê GD | SOTK=`XX9999999` (không tồn tại cả 2 nơi) | Lỗi: "Tài khoản không tồn tại trên hệ thống" |
| 07d | Login `BT001`/`1` → chi nhánh BENTHANH → Sao kê GD | SOTK=`BT0000001`, khoảng ngày không có GD | Trả về rỗng, SODU_DAUKY = SODU_CUOIKY |

> **Lưu ý TC-07b:** `TaiKhoan` trên SQL1 chỉ chứa dữ liệu BENTHANH (phân mảnh ngang) — dropdown của BT001 không thấy TD accounts. Phải test 07b từ `admin`/TRACUU vì `SP_SaoKeTaiKhoan` phiên bản TRACUU đọc TaiKhoan qua `LINK1`+`LINK2`, thấy toàn bộ tài khoản cả 2 chi nhánh.

### Hệ thống xử lý chi tiết

**Bước 1 — Node.js gọi SP**
- Code: [`routes/baocao.js:76`](../APP_NGANHANG/routes/baocao.js)
- `querySP(req, server, 'SP_SaoKeTaiKhoan', { SOTK, TUNGAY, DENNGAY })`

**Bước 2 — SP tìm SODU hiện tại (BƯỚC 1 trong SP)**
- SP: [`sql/stored_procedures/06_SP_SaoKeTaiKhoan.sql:18–30`](../sql/stored_procedures/06_SP_SaoKeTaiKhoan.sql)
- Tìm local trước: `SELECT SODU FROM TaiKhoan WHERE SOTK = @SOTK`
- Không thấy → tìm qua LINK1: `SELECT SODU FROM [LINK1]...TaiKhoan`
- Vẫn không thấy → RAISERROR

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
- **Bảo mật 3 tầng:** (1) Database Role — SQL Server chặn ở tầng DB, (2) Backend Middleware — Node.js kiểm tra `user.NHOM`, (3) UI — ẩn menu không thuộc quyền.

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
- Code: [`routes/taikhoan.js:108–112`](../APP_NGANHANG/routes/taikhoan.js)
- Chỉ `NganHang` và `ChiNhanh` được đóng TK

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

- **Tại sao KH không cần nhập lại họ tên ở chi nhánh 2?** → CMND là định danh duy nhất. `SP_TaoTaiKhoan` tra CMND trong `KhachHang` local, nếu chưa có thì tra qua `[LINK1]` sang chi nhánh kia. Tìm thấy → lấy HO/TEN từ đó, chỉ tạo thêm TK mới — không tạo lại KH.
- **Dữ liệu KH lưu ở đâu?** → Phân mảnh ngang theo `MACN`: KH đăng ký ở BENTHANH → lưu SQL1, KH đăng ký TANDINH → lưu SQL2. Cả 2 replicate lên SQL3.
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
