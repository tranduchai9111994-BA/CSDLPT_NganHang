# 🧭 Đánh Giá Cơ Chế Phân Tán (Distributed Mechanism Review)

> Tài liệu này rà soát **toàn bộ logic source code (Node.js) và database (SQL Server)** đang chạy thực tế, đối chiếu với thiết kế phân tán đã công bố (Replication, Linked Server, Distributed Transaction, Phân quyền) và **đề bài Đề 3 – Ngân Hàng** (xem [`00_DE3_NGAN_HANG_PhanTan.md`](00_DE3_NGAN_HANG_PhanTan.md)).
>
> Mục tiêu: trả lời câu hỏi **"Hệ thống đã đáp ứng đúng cơ chế phân tán chưa? Có chỗ nào đang xử lý bằng code mà lẽ ra phải xử lý theo cơ chế phân tán của DB không?"** và **đưa ra khuyến nghị**.
>
> Ngày rà soát: 26/06/2026. Phạm vi: `APP_NGANHANG/` (app.js, db.js, setup_db.js, routes/) + các file `*.sql` + bản SP deployed trong [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md).

---

## 1. Bản Đồ Kiến Trúc (Tóm tắt để đối chiếu)

| Site | Instance | Vai trò | Dữ liệu cục bộ | Linked Server |
|---|---|---|---|---|
| NGUON | `ES-HAITD16` | Publisher / Distributor | Bản gốc toàn cục | LINK1→SQL1, LINK2→SQL2, LINK3→SQL3 |
| BENTHANH | `ES-HAITD16\SQL1` | Subscriber – Chi nhánh 1 | Mảnh `MACN='BENTHANH'` | LINK0→NGUON, LINK1→SQL2 (đối tác) |
| TANDINH | `ES-HAITD16\SQL2` | Subscriber – Chi nhánh 2 | Mảnh `MACN='TANDINH'` | LINK0→NGUON, LINK1→SQL1 (đối tác) |
| TRACUU | `ES-HAITD16\SQL3` | Subscriber – Tra cứu/Báo cáo | Replicate full `KhachHang` | LINK0→NGUON, LINK1→SQL1, LINK2→SQL2 |

**Quy ước vàng:** `LINK1` luôn là **chi nhánh đối tác**. App (`db.js`) kết nối thẳng từng instance bằng pool riêng theo `serverKey` (BENTHANH/TANDINH/TRACUU/NGUON).

---

## 2. Bảng Điểm Tổng Quan

| Hạng mục | Cơ chế phân tán kỳ vọng | Hiện trạng | Đánh giá |
|---|---|---|---|
| Giao dịch liên chi nhánh (gửi/rút/chuyển) | `BEGIN DISTRIBUTED TRAN` + LINK1 + MSDTC (2PC) | `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` đều có DTC + LINK1 + `XACT_ABORT` | ✅ Đúng — SP chạy local (server NV), GD ghi local (đúng mảnh), UPDATE TK qua LINK1 nếu TK khác CN (xem #1 ✅) |
| Chuyển nhân viên | DTC + LINK1, cập nhật `TrangThaiXoa` site cũ + INSERT site mới | `sp_ChuyenNhanVien` chuẩn | ✅ Đạt |
| Sao kê 1 tài khoản | Tính tại SQL, gộp local + LINK1, Window Function | `SP_SaoKeTaiKhoan` | ✅ Đạt (rất tốt) |
| Liệt kê KH/TK toàn hệ thống | Đọc từ TRACUU (replica) hoặc SP dùng LINK1+LINK2 | KH: đọc TRACUU ✅ / TK NganHang: **JOIN xuyên mảnh tại tầng Node** | ⚠️ Một phần (xem #4) |
| Phân quyền | Role DB (GRANT/DENY) + middleware + UI + SQL Auth | 3 lớp đầy đủ | ✅ Đạt, **trừ** lỗ hổng KhachHang đọc `TaiKhoan` (xem #5) |
| Replication TaiKhoan | Nhân bản toàn vẹn (Replicate Full) | Đọc local, ghi qua LINK1 nếu TK thuộc CN khác | ✅ Đã hiệu chỉnh: nhân bản full + SP dùng MACN phân biệt (xem #1 ✅, #2 ✅) |
| Sinh khóa phân tán (SOTK, MAGD) | Identity Range / prefix theo site | MAGD: Identity Range (doc) / **SOTK: MAX+1 tại app** | ❌ Nguy cơ trùng khóa (xem #3) |
| Cấp phát Login đa site | Login là server-level, không replicate | App fan-out 3 server (không atomic) | ⚠️ Chấp nhận được nhưng cần kiểm soát (xem #4) |

**Kết luận nhanh:** Phần **giao dịch phân tán (DTC/MSDTC) và sao kê** làm **đúng và đẹp** theo chuẩn CSDLPT. Điểm yếu nằm ở **mâu thuẫn giữa mô hình "replicate full bảng TaiKhoan" với logic ghi/chuyển tiền**, ở **sinh khóa SOTK**, và một vài chỗ **đẩy việc tổng hợp xuyên mảnh lên tầng application** thay vì xử lý bằng SP/Linked Server.

---

## 3. Những Điểm ĐÃ ĐÚNG Cơ Chế Phân Tán ✅

1. **Distributed Transaction chuẩn 2PC.** `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` và `sp_ChuyenNhanVien` dùng `BEGIN DISTRIBUTED TRANSACTION` + `SET XACT_ABORT ON` + `TRY/CATCH` → `ROLLBACK`. Đây chính là yêu cầu bắt buộc của đề bài (mục A.5). MSDTC bảo đảm cộng/trừ ở 2 site cùng commit hoặc cùng rollback. SP **luôn chạy trên server NV** → GD_GOIRUT/GD_CHUYENTIEN ghi đúng mảnh (phân mảnh theo NV); UPDATE TK qua LINK1 nếu TK thuộc chi nhánh khác.
2. **Linked Server đúng quy ước.** Mọi truy vấn xuyên site dùng cú pháp 4 phần `[LINK1].NGANHANG.dbo.<Table>`; `LINK1` = đối tác, không loopback. `sp_MoTaiKhoan` validate khách hàng bằng check local trước → không có thì check `[LINK1]` (đối tác) — nhất quán với các SP khác và không phụ thuộc NGUON.
3. **Sao kê tính tại tầng DB.** `SP_SaoKeTaiKhoan` gộp giao dịch local + `LINK1`, tính số dư đầu kỳ bằng "trừ ngược" và số dư lũy kế bằng `SUM() OVER(...)`. Logic nặng nằm ở SQL, app chỉ render. Đây là cách làm phân tán đúng (giảm IO mạng, không kéo data thô về app).
4. **Phân mảnh ngang theo `MACN`** cho `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`; replicate full `KhachHang` về TRACUU để NganHang tra cứu toàn cục mà không đụng site giao dịch. Route `khachhang.js`/`nhanvien.js` khi NganHang → đọc TRACUU; ChiNhanh → đọc local. Đúng mô hình.
6. **Tách LINK1 query khỏi distributed tran.** `sp_MoTaiKhoan` check KH qua LINK1 **trước** `BEGIN DISTRIBUTED TRANSACTION`, lưu kết quả vào biến `@KHFound`. INSERT nằm trong distributed tran riêng — không có LINK1 query → merge trigger hoạt động bình thường. Pattern này nhất quán với `sp_GuiTien`/`sp_RutTien`/`sp_ChuyenTien` (đọc trước, write trong DTC). Xem [Sự cố 11](17_Su_Co_Va_Xu_Ly.md#sự-cố-11).
5. **Xác thực & phân quyền nhiều lớp.** SQL Authentication theo từng người (`auth.js` mở pool bằng chính username/password người dùng) → mọi thao tác được định danh để audit; `sp_Login_App` map Login→Role qua `sys.database_role_members`; role DB `GRANT/DENY`; middleware `requireRole`; ẩn/hiện UI theo `user.NHOM`.

---

## 4. Những Điểm CHƯA ĐÚNG / RỦI RO & Khuyến Nghị

### ✅ #1 — ĐÃ HIỆU CHỈNH: SP `sp_ChuyenTien` phải dùng MACN (không dùng EXISTS) để phù hợp TaiKhoan nhân bản  [Hiệu chỉnh 30/06/2026]

**Quyết định: TaiKhoan = Nhân bản toàn vẹn (Replicate Full)** — theo yêu cầu đề bài.

**Vấn đề trước đó:** SP dùng `EXISTS (SELECT 1 FROM TaiKhoan WHERE SOTK = @SOTK_NHAN)` để xác định TK nhận có ở local không. Nhưng vì TaiKhoan được replicate full, **mọi TK đều tồn tại local** → `@IsNhanLocal` luôn = 1 → SP luôn UPDATE local → **sai** cho TK thuộc chi nhánh khác (vi phạm quy tắc "chỉ GHI tại site sở hữu").

**Giải pháp đã áp dụng:** Thay EXISTS bằng **so sánh MACN**:
```sql
-- Lấy MACN của TK chuyển (local, luôn thuộc chi nhánh hiện tại)
SELECT @MACN_CHUYEN = MACN FROM TaiKhoan WHERE SOTK = @SOTK_CHUYEN;
-- Lấy MACN của TK nhận (đọc local — nhân bản full, nhanh)
SELECT @MACN_NHAN = MACN FROM TaiKhoan WHERE SOTK = @SOTK_NHAN;
-- So sánh: cùng MACN → ghi local, khác MACN → ghi qua LINK1
IF @MACN_NHAN = @MACN_CHUYEN SET @IsNhanLocal = 1;
```

**Tại sao đúng:**
- **Đọc local** để kiểm tra TK nhận → nhanh, tận dụng nhân bản (không cần Linked Server để SELECT).
- **Ghi qua LINK1** nếu TK nhận thuộc chi nhánh đối tác → đảm bảo ghi đúng site sở hữu, Replication sẽ đồng bộ ngược lại.
- Kết hợp `BEGIN DISTRIBUTED TRANSACTION` + MSDTC 2PC → ACID trên cả 2 site.

---

### ✅ #2 — ĐÃ HIỆU CHỈNH: Code app ghi trực tiếp lên `TaiKhoan` (nhân bản)  [Hiệu chỉnh 30/06/2026]

**Trạng thái:** Chấp nhận được — các thao tác ghi đều ghi tại site sở hữu.

Với TaiKhoan nhân bản toàn vẹn, quy tắc là **chỉ GHI tại site sở hữu** (site có MACN khớp):
- `DELETE FROM TaiKhoan` tại local ([`taikhoan.js`](../APP_NGANHANG/routes/taikhoan.js)) — hợp lệ vì xóa TK trên server local.
- `INSERT INTO TaiKhoan` qua `sp_MoTaiKhoan`:
  - **Cùng chi nhánh:** gọi `execSP` local — MACN = chi nhánh NV.
  - **Cross-branch:** NV chi nhánh A mở TK cho KH chi nhánh B → `MACN = chi nhánh B`, INSERT chạy trên server B (via `execSPAdmin`) để thỏa cả `FK_TaiKhoan_KhachHang` (CMND) lẫn `FK_TaiKhoan_ChiNhanh` (MACN). TK replicate full sang server A.
- `UPDATE TaiKhoan` (gửi/rút/chuyển tiền) — SP `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` đều dùng MACN check: so sánh MACN TK vs MACN NV để quyết định UPDATE local hay qua LINK1. GD_GOIRUT/GD_CHUYENTIEN INSERT local (đúng mảnh theo NV).

Replication sẽ tự đồng bộ các thay đổi sang site đối tác (bản copy).

---

### ✅ #3 — ĐÃ HIỆU CHỈNH: Sinh khóa phân tán `SOTK` theo tiền tố chi nhánh  [Hiệu chỉnh 28/06/2026]

**Trạng thái:** Đã sửa `sinhSOTK()` trong [`taikhoan.js`](../APP_NGANHANG/routes/taikhoan.js).

**Thay đổi:** `SOTK` nay có **tiền tố chi nhánh** — `BT0000001` (Bến Thành) và `TD0000001` (Tân Định). Hàm lọc `WHERE SOTK LIKE @prefix%` để chỉ tính MAX của dải mình.

> ℹ️ Mặc dù TaiKhoan được nhân bản toàn vẹn (mọi TK đều có ở local), tiền tố vẫn cần thiết để: (1) phân biệt TK thuộc chi nhánh nào qua MACN, (2) tránh trùng PK khi 2 site đồng thời INSERT, (3) nhất quán với quy ước MANV (BT/TD prefix).

---

### ✅ #4 — ĐÃ HIỆU CHỈNH: Logic tổng hợp phân tán bị "rò rỉ" lên tầng application  [Hiệu chỉnh 28/06/2026]

**Trạng thái:** Đã xử lý cả 3 điểm.

**#4.1 — JOIN xuyên mảnh (taikhoan.js NganHang GET /)**

*Trước:* đọc `TaiKhoan` từ BENTHANH, đọc `KhachHang` từ cả 2 site riêng lẻ, join bằng `khMap` trong JS.

*Sau:* gọi `querySP(req, 'TRACUU', 'sp_DanhSachTaiKhoan', {})`. SP mới ([`12_SP_DanhSachTaiKhoan.sql`](../12_SP_DanhSachTaiKhoan.sql)) chạy trên TRACUU, dùng LINK1+LINK2 để lấy `TaiKhoan` từ cả 2 chi nhánh và JOIN với `KhachHang` local (TRACUU replicate full KhachHang). Toàn bộ join phân tán được thực hiện tại tầng DB.

**#4.2 — Sao kê không chọn TK chỉ trên 1 site (baocao.js NganHang non-SOTK)**

*Trước:* 3 query rời `GD_GOIRUT`/`GD_CHUYENTIEN` trên server local của NganHang (TRACUU không có bảng GD → thực tế đang trả rỗng cho NganHang).

*Sau:* Tách nhánh `user.NHOM === 'NganHang'` gọi `querySP(req, 'TRACUU', 'sp_SaoKeToanBo', {TUNGAY, DENNGAY})`. SP mới ([`13_SP_SaoKeToanBo.sql`](../13_SP_SaoKeToanBo.sql)) gộp `GD_GOIRUT` + `GD_CHUYENTIEN` (cả bên chuyển và bên nhận) từ LINK1 và LINK2. ChiNhanh/KhachHang vẫn dùng query local (đúng phạm vi của họ).

**#4.3 — Fan-out cấp Login: luôn báo "thành công" dù có lỗi (quantri.js)**

*Trước:* `errors[]` được ghi `console.error` nhưng luôn render `success`.

*Sau:* Kiểm tra `errors.length > 0` sau vòng lặp; nếu có lỗi render `error` thông báo "cấp một phần" và hướng dẫn dùng Dọn Lỗi Đồng Bộ. Fan-out vẫn là cơ chế đúng (Login là đối tượng server-level, không nằm trong Replication — bắt buộc tạo thủ công từng instance).

> ℹ️ **[Cập nhật 30/06/2026]** SP đặc thù TRACUU (không đưa vào Article Replication, cài bằng `setup_db.js` hoặc [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql)):
> - `sp_DanhSachTaiKhoan`, `sp_SaoKeToanBo` — đã có từ 28/06
> - `sp_DanhSachNhanVien` — **MỚI**: đọc NhanVien qua LINK1+LINK2 (TRACUU không còn NhanVien local sau khi sửa PUB_TRACUU chỉ giữ KhachHang)
> - `sp_LietKeTaiKhoanTheoNgay` — **MỚI**: phiên bản TRACUU đọc TaiKhoan qua LINK
> - `SP_DanhSachTrangThaiLogin` — **MỚI**: phiên bản TRACUU đọc NhanVien qua LINK, KhachHang+QuanTriLogin local
>
> Route `nhanvien.js` và `quantri.js` (getNhanVienList) NganHang đã đổi từ raw `SELECT FROM NhanVien` sang `querySP('sp_DanhSachNhanVien')`. Xem [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md) để biết định nghĩa đầy đủ.

---

### ✅ #5 — ĐÃ HIỆU CHỈNH: Phân quyền KhachHang đọc TaiKhoan qua SP  [Hiệu chỉnh 28/06/2026]

**Trạng thái:** Đã xử lý theo hướng SP (nhất quán với `SP_SaoKeTaiKhoan`).

**Các thay đổi:**

1. **SP mới `sp_TaiKhoanKhachHang(@CMND)`** ([`14_SP_TaiKhoanKhachHang.sql`](../14_SP_TaiKhoanKhachHang.sql)): trả danh sách TK lọc theo CMND. KhachHang chỉ có `GRANT EXECUTE` trên SP này — không có `SELECT` trực tiếp trên bảng. SP là cửa ngõ duy nhất, đảm bảo KhachHang không thể đọc TK của người khác ngay cả khi kết nối thẳng vào DB.

2. **`04_Role_PhanQuyen.sql`**: Thêm `GRANT EXECUTE ON sp_TaiKhoanKhachHang TO KhachHang`. Comment rõ triết lý: chỉ EXECUTE trên SP, không SELECT trực tiếp.

3. **`taikhoan.js` GET `/`**: nhánh KhachHang thay `querySQL(SELECT TaiKhoan)` → `querySP(sp_TaiKhoanKhachHang)`.

4. **`baocao.js`**: Refactor toàn bộ POST `/saoke`:
   - Pre-fetch `myTKList` qua SP một lần duy nhất ở đầu handler — dùng lại cho ownership check, tkRows dropdown, SODU fallback.
   - Ownership check: thay raw `SELECT COUNT(*) FROM TaiKhoan` → so sánh trong `myTKList` (không có query DB thêm).
   - Non-SOTK path KhachHang: gọi `SP_SaoKeTaiKhoan` cho từng TK rồi merge — KhachHang cũng không có `SELECT` trực tiếp trên `GD_GOIRUT`/`GD_CHUYENTIEN`.
   - Tất cả `tkRows` dropdown KhachHang → từ `myTKRows` (cache, không re-query).
   - GET `/saoke` KhachHang: thay raw SELECT → `querySP(sp_TaiKhoanKhachHang)`.

5. **`app.js`**: Thêm `requireRole('NganHang', 'ChiNhanh', 'KhachHang')` tường minh cho `/taikhoan` và `/baocao`. Trước đây chỉ `requireLogin` — route và quyền DB nói cùng một ngôn ngữ.

---

### 🟡 #6 — Lưu mật khẩu plain-text (`QuanTriLogin`, session)  (THẤP – môi trường học tập)

- `QuanTriLogin.MatKhauHienTai` lưu **plain-text** (chủ đích để demo/khôi phục mật khẩu test), đã `DENY SELECT` cho ChiNhanh/KhachHang và chỉ NganHang xem qua API có middleware. Chấp nhận trong đồ án nhưng **không dùng cho production**.
- `req.session.user.PASSWORD` lưu plain để mở pool theo từng user (`db.js getPool`). Cần ý thức rủi ro nếu triển khai thật (nên dùng token/giảm vòng đời session).

---

### ✅ #7 — ĐÃ HIỆU CHỈNH: Đồng bộ "nguồn sự thật" Stored Procedures  [Hiệu chỉnh 28/06/2026]

**Trạng thái:** 3 file SQL gốc bị lệch đã được cập nhật khớp với bản deployed.

| File gốc | Thay đổi |
|---|---|
| [`07_SP_ChuyenTien.sql`](../07_SP_ChuyenTien.sql) | Đổi sang `@IsNhanLocal` + `nchar(9)` — khớp bản deployed trong doc/13 |
| [`11_SP_TaoTaiKhoan.sql`](../11_SP_TaoTaiKhoan.sql) | 4 params → 6 params, thêm `WITH EXECUTE AS OWNER`, `QuanTriLogin INSERT`, `QUOTENAME` — khớp setup_db.js |
| [`sp_Login_App.sql`](../sp_Login_App.sql) | Thêm `@DBUserName` resolve (login name ≠ DB user name), bỏ nhánh tự suy luận không đáng tin cậy — khớp setup_db.js |

**`setup_db.js`** cũng được cập nhật để deploy 3 SP mới sinh ra từ #4, #5:
- `sp_TaiKhoanKhachHang` — deploy trên tất cả 4 server.
- `sp_DanhSachTaiKhoan`, `sp_SaoKeToanBo` — deploy chỉ trên TRACUU và NGUON (dùng LINK2, không có trên BENTHANH/TANDINH).

**Nguồn sự thật** sau khi hiệu chỉnh: file `*.sql` ở thư mục gốc = định nghĩa chuẩn; `setup_db.js` chứa bản inline để deploy; `doc/13_All_Stored_Procedures.md` là tài liệu tham chiếu. Ba nguồn này nay đồng nhất.

---

### ✅ #8 — ĐÃ HIỆU CHỈNH: `execSPAdmin` dùng `-v` tách SQL template khỏi data  [Hiệu chỉnh 28/06/2026]

**Trước:** build chuỗi `-Q "EXEC SP @k=N'<value>'"` — nhúng giá trị trực tiếp vào SQL string truyền cho sqlcmd.

**Sau:** SQL template tĩnh chỉ chứa `$(VarName)` placeholder; giá trị đi qua `-v Key=Value` (channel riêng biệt):

```javascript
// Template — không có user data
const query = `EXEC ${spName} @MANV=N'$(MANV)', @MACN_MOI=N'$(MACN_MOI)'`;

// Data — qua -v args, ' vẫn escape thành ''
const vArgs = ['-v', "MANV=BT001", '-v', "MACN_MOI=TANDINH"];

execFile('sqlcmd', [..., ...vArgs, '-Q', query, '-b']);
```

**Tại sao tốt hơn:**
- Shell injection không thể xảy ra (giá trị là array element riêng, không nhúng vào shell string).
- SQL template là hằng — dễ audit, không có đường vào cho user input.
- `'` vẫn được escape `→ ''` trong giá trị để ngăn SQL string literal breakage qua `$(VarName)` substitution.

> ℹ️ `execSPAdmin` được gọi tại:
> - [`nhanvien.js`](../APP_NGANHANG/routes/nhanvien.js) — `SP_ChuyenNhanVien` (chuyển NV) và `SP_PhucHoiNhanVien` (phục hồi NV).
> - [`taikhoan.js`](../APP_NGANHANG/routes/taikhoan.js) — `sp_MoTaiKhoan` (**luôn**, không chỉ cross-branch — SP dùng `BEGIN DISTRIBUTED TRANSACTION`).
>
> Rủi ro thực tế thấp (input từ dropdown/form có kiểm soát), nhưng fix là đúng về kiến trúc.

---

## 5. Tổng Kết & Thứ Tự Ưu Tiên Xử Lý

| Ưu tiên | Vấn đề | Hành động cốt lõi |
|---|---|---|
| ~~1 🔴~~ | ~~#1 SP dùng EXISTS không phù hợp TaiKhoan nhân bản~~ | ✅ **Đã xử lý 30/06/2026** — SP đổi sang dùng MACN phân biệt local/remote |
| ~~2 🔴~~ | ~~#2 Ghi trực tiếp `TaiKhoan` trên subscriber~~ | ✅ **Đã xử lý 30/06/2026** — Ghi local hợp lệ (site sở hữu MACN); SP chuyển tiền ghi qua LINK1 nếu khác MACN |
| ~~1 🟠~~ | ~~#3 SOTK sinh ở app, dễ trùng~~ | ✅ **Đã xử lý 28/06/2026** — Tiền tố BT/TD theo MACN |
| ~~2 🟠~~ | ~~#5 KhachHang thiếu quyền đọc TaiKhoan~~ | ✅ **Đã xử lý 28/06/2026** — SP `sp_TaiKhoanKhachHang` + refactor baocao.js |
| ~~3 🟠~~ | ~~#4 Tổng hợp xuyên mảnh ở tầng app~~ | ✅ **Đã xử lý 28/06/2026** — SP TRACUU + LINK1+LINK2; fix fan-out error reporting |
| ~~4 🟡~~ | ~~#7 SP đa phiên bản~~ | ✅ **Đã xử lý 28/06/2026** — Đồng bộ 3 file gốc + setup_db.js |
| ~~5 🟡~~ | ~~#6, #8 plain-text pass, sqlcmd injection~~ | ✅ **#8 Đã xử lý 28/06/2026** — -v args; #6 plain-text pass: ghi nhận rủi ro, chấp nhận cho đồ án |

**Nhận định chung.** Hệ thống **đã thể hiện đúng tinh thần CSDL phân tán**: distributed transaction qua MSDTC, Linked Server, sao kê tính tại SQL, phân quyền nhiều lớp. Bảng `TaiKhoan` được nhân bản toàn vẹn — SP `sp_ChuyenTien` đã sửa sang dùng MACN để phân biệt ghi local/remote, đảm bảo đúng quy tắc "đọc local, ghi tại site sở hữu". Tất cả các vấn đề đã được hiệu chỉnh.
