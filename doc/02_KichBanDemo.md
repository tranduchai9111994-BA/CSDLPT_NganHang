# 🎬 Kịch Bản Demo — Đồ Án CSDL Phân Tán Ngân Hàng

> **Thời lượng dự kiến:** 8–12 phút
> **Mục tiêu:** Show đủ các chức năng chính, nhấn mạnh phần **phân tán** (Distributed Transaction, Linked Server, Replication) + **phân quyền 3 role** (SQL Authentication).
> **Nguyên tắc:** Demo đúng thứ tự, ghi rõ dữ liệu test trên giấy trước khi vào phòng.

---

## CHUẨN BỊ TRƯỚC KHI DEMO

### Checklist khởi động
- [ ] 4 SQL Server instance đang chạy (`ES-HAITD16`, `SQL1`, `SQL2`, `SQL3`)
- [ ] Dịch vụ **MSDTC** đang `Running` (services.msc → Distributed Transaction Coordinator)
- [ ] Đã chạy `npm start` trong thư mục `APP_NGANHANG` (port `3001`)
- [ ] Browser mở sẵn `http://localhost:3001`
- [ ] Mở SSMS kết nối 4 instance (dùng khi giảng viên yêu cầu show dữ liệu thô)
- [ ] Ghi tài khoản test ra giấy (xem dưới)

### Tài khoản test

| Mục đích | Login | Password | Chi nhánh chọn | Server thực tế |
|---|---|---|---|---|
| Demo `ChiNhanh` — BENTHANH | `BT001` | `1` | BENTHANH | `ES-HAITD16\SQL1` |
| Demo `ChiNhanh` — TANDINH | `TD001` | `1` | TANDINH | `ES-HAITD16\SQL2` |
| Demo `NganHang` (Ban GĐ) | `admin` | `1` | (chọn CN nào cũng được) | `ES-HAITD16\SQL3` (auto‑fixed) |
| Demo `KhachHang` | `1111111111` | `123456` | BENTHANH | `ES-HAITD16\SQL1` |

> **Lưu ý ràng buộc:** LoginName của nhân viên = MANV (`BT001`/`TD001`...). LoginName của KhachHang = CMND (`1111111111`, `2222222222`...). Xem toàn bộ tài khoản demo tại [`03_DemoAccounts.md`](03_DemoAccounts.md).

### Dữ liệu mẫu cần ghi lại trước

Chạy trong SSMS trước khi demo:
```sql
-- Trên SQL1 (BENTHANH)
SELECT TOP 5 SOTK, SODU, MACN FROM NGANHANG.dbo.TaiKhoan WHERE MACN='BENTHANH';
-- Trên SQL2 (TANDINH)
SELECT TOP 5 SOTK, SODU, MACN FROM NGANHANG.dbo.TaiKhoan WHERE MACN='TANDINH';
```
Ghi lại:
- `SOTK_BT` (VD `BT0000001`) = _______
- `SOTK_TD` (VD `TD0000001`) = _______
- `CMND_BT` (VD `1111111111`) = _______

---

## KỊCH BẢN DEMO (theo thứ tự)

### Phần 0: Giới thiệu kiến trúc (1 phút)

> "Hệ thống gồm **4 SQL Server instance** trên cùng máy `ES-HAITD16`:
> - `NGUON` là Publisher/Distributor chứa CSDL gốc.
> - `SQL1` là chi nhánh **Bến Thành** (Subscriber).
> - `SQL2` là chi nhánh **Tân Định** (Subscriber).
> - `SQL3` là trạm **Tra cứu** dành cho Ban Giám Đốc.
>
> Dữ liệu được **phân mảnh ngang theo `MACN`** cho các bảng `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`. Riêng `TaiKhoan` và `ChiNhanh` được **nhân bản toàn vẹn** trên cả 2 site chi nhánh. Giao tiếp giữa các mảnh dùng **Linked Server** — trong đó `LINK1` luôn trỏ đến chi nhánh đối tác."

Show SSMS: 4 instance trong Object Explorer.

---

### Phần 1: Đăng nhập nhóm `ChiNhanh` — BENTHANH (1 phút)

**Thao tác:**
1. Mở `http://localhost:3001/login`
2. Username = `BT001`, Password = `1`, Chi nhánh = `BENTHANH`
3. Bấm Đăng nhập

> "Đăng nhập bằng **SQL Authentication thật**. `db.js` tạo connection pool trực tiếp bằng username/password của nhân viên — không dùng tài khoản service trung gian. Điều này đảm bảo SQL Server ghi nhận đúng `LOGIN_NAME()` cho mọi thao tác (audit trail)."

Kỳ vọng: Vào trang chủ, menu trái hiển thị đủ Khách hàng / Nhân viên / Tài khoản / Giao dịch / Báo cáo.

---

### Phần 2: Thêm khách hàng mới (1 phút)

**Thao tác:**
1. Menu **Khách hàng** → **Thêm**
2. Điền form:
   - Họ: `Nguyễn Văn`, Tên: `Demo`
   - Địa chỉ: `123 Lê Lợi, Q1`
   - Phái: `Nam`, Ngày cấp: `01/01/2020`
   - SĐT: `0901234567`
   - CMND: `9999900001` (để trống Mã PIN → mặc định = CMND)
3. **Ghi**

> "KH được thêm vào phân mảnh BENTHANH (SQL1). Ngoài INSERT bảng `KhachHang`, route còn **fan‑out CREATE LOGIN + CREATE USER + Add Role trên cả 4 SQL instance** để KH có thể đăng nhập từ bất kỳ site nào (Login là đối tượng cấp Server, không có trong Replication). Sau đó Merge Replication tự đẩy record `KhachHang` sang TRACUU."

---

### Phần 3: Mở tài khoản cho KH vừa thêm (1 phút)

**Thao tác:**
1. Menu **Tài khoản** → chọn KH `9999900001`
2. Grid TK ban đầu trống → **Thêm TK**
3. Số dư ban đầu: `1000000`. Bấm **Ghi**

> "Đây là giao diện **Master‑Detail** theo yêu cầu đề bài. Số TK được tự sinh với prefix chi nhánh: `BT` cho BENTHANH → format `BT0000001`. SP `sp_MoTaiKhoan` chạy trong `BEGIN DISTRIBUTED TRANSACTION` vì bảng `TaiKhoan` có Merge Replication trigger — nếu commit thành công, Replication sẽ tự đồng bộ TK sang site đối tác."

Ghi lại: SOTK vừa tạo = _______

---

### Phần 4: Gửi tiền (30 giây)

**Thao tác:**
1. **Giao dịch** → **Gửi/Rút tiền** → Tab **Gửi tiền**
2. Chọn TK vừa mở, Số tiền = `500000` → thực hiện

Kỳ vọng: Thành công. Số dư 1.000.000 → 1.500.000.

> "SP `sp_GuiTien` kiểm tra số tiền ≥ 100.000, đọc MACN của TK và MACN của NV để quyết định UPDATE local hay qua `[LINK1]`. Log `GD_GOIRUT` luôn ghi tại site NV thực hiện (phân mảnh theo NV)."

---

### Phần 5: Rút tiền — test lỗi (30 giây)

**Thao tác:**
1. Tab **Rút tiền**
2. Rút `50000` → **báo lỗi** (< 100.000)
3. Rút `200000` → **thành công**

> "SP `sp_RutTien` kiểm tra 2 điều kiện atomic trong 1 UPDATE: `WHERE SOTK=@SOTK AND SODU >= @SOTIEN`. Nếu `@@ROWCOUNT = 0` thì ROLLBACK."

---

### Phần 6: Chuyển tiền liên chi nhánh ⭐ (2 phút — QUAN TRỌNG NHẤT)

Đây là phần thể hiện rõ nhất CSDL Phân Tán.

**Thao tác:**
1. **Giao dịch** → **Chuyển tiền**
2. TK chuyển: TK vừa mở ở BENTHANH
3. TK nhận: `SOTK_TD` đã ghi (tài khoản TANDINH)
4. Số tiền: `300000` → thực hiện

> "SP `sp_ChuyenTien` chạy trên SQL1. Nó đọc MACN của TK chuyển (`BENTHANH`) và MACN của TK nhận (`TANDINH`) — cả 2 đều có bản copy local vì `TaiKhoan` **nhân bản toàn vẹn**, không cần Linked Server để SELECT.
>
> Vì MACN khác nhau → SP quyết định UPDATE cộng tiền qua `[LINK1]` — LINK1 tại SQL1 trỏ SQL2. Toàn bộ nằm trong `BEGIN DISTRIBUTED TRANSACTION` + `SET XACT_ABORT ON`. **MSDTC** thực hiện **Two‑Phase Commit**: nếu đứt mạng giữa 2 site, cả 2 tự động ROLLBACK — không có tiền mất tích.
>
> Log `GD_CHUYENTIEN` ghi tại SQL1 (đúng mảnh theo NV thực hiện)."

**Xác nhận SSMS:** `SELECT SODU FROM SQL2.NGANHANG.dbo.TaiKhoan WHERE SOTK='<TK_TD>'` → số dư đã tăng 300.000.

---

### Phần 7: Đăng xuất → Đăng nhập nhóm `NganHang` (1 phút)

**Thao tác:**
1. Đăng xuất
2. Login: `admin` / `1` / chi nhánh (chọn gì cũng được — `auth.js` tự gán `effectiveServer='TRACUU'`)

> "Nhóm `NganHang` luôn kết nối server **TRACUU (SQL3)**. Ở tầng DB, role `NganHang` bị `DENY INSERT/UPDATE/DELETE` — kể cả gọi query trực tiếp qua SSMS cũng không thể sửa dữ liệu."

Kỳ vọng: Menu chỉ có Báo cáo + Quản trị + xem danh sách KH/NV/TK (không có form ghi).

---

### Phần 8: Sao kê tài khoản (1 phút)

**Thao tác:**
1. **Báo cáo** → **Sao kê**
2. Chọn SOTK vừa giao dịch → khoảng thời gian → **Xem**

> "SP `SP_SaoKeTaiKhoan` (bản TRACUU) đọc `GD_GOIRUT` + `GD_CHUYENTIEN` từ cả `[LINK1]` (BENTHANH) và `[LINK2]` (TANDINH) vì TRACUU không có local các bảng GD.
>
> Kỹ thuật **'tính lùi số dư đầu kỳ'**: lấy số dư hiện tại trừ đi tổng biến động sau ngày yêu cầu → không cần kéo toàn bộ lịch sử qua Linked Server. Số dư lũy kế được tính bằng **Window Function** `SUM() OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` — chỉ 1 lần scan, không cần cursor."

Kỳ vọng: Bảng 5 cột — Số dư đầu | Ngày | Loại GD | Số tiền | Số dư sau.

---

### Phần 9: Liệt kê KH / TK (30 giây)

**Thao tác:**
1. **Báo cáo** → **Liệt kê khách hàng** → sắp xếp `MACN, HO, TEN`
2. **Báo cáo** → **Liệt kê tài khoản** → chọn khoảng thời gian

> "KH đọc trực tiếp từ TRACUU (KhachHang replicate full). TK đọc qua `[LINK1]` duy nhất — vì `TaiKhoan` nhân bản toàn vẹn nên LINK1 đã có đủ cả 2 chi nhánh, `UNION ALL` cả LINK1+LINK2 sẽ bị **duplicate x2**."

---

### Phần 10: Đăng nhập nhóm `KhachHang` (1 phút)

**Thao tác:**
1. Đăng xuất
2. Login: `1111111111` / `123456`

> "Khách hàng chỉ thấy menu **Sao kê**. Cố truy cập URL khác (VD `/khachhang`) → HTTP 403. Ở tầng DB, `KhachHang` không có `SELECT` trực tiếp trên bất kỳ bảng nào — chỉ được `EXECUTE` 3 SP: `sp_TaiKhoanKhachHang`, `SP_SaoKeTaiKhoan`, `sp_Login_App`. SP đóng vai trò cửa ngõ duy nhất."

Kỳ vọng: Chỉ thấy form sao kê, dropdown chỉ có TK của chính KH này.

---

### Phần 11 (Bonus): Chuyển nhân viên (1 phút — nếu còn thời gian)

**Thao tác:**
1. Login lại `BT001` / `1` / BENTHANH
2. **Nhân viên** → chọn 1 NV → **Chuyển chi nhánh** → TANDINH

> "SP `sp_ChuyenNhanVien` chạy trong `BEGIN DISTRIBUTED TRAN`:
> 1. Sinh `MANV` mới với prefix chi nhánh đích (`TD00X`) — query qua `[LINK1]` để tìm MANV lớn nhất hiện có.
> 2. UPDATE `TrangThaiXoa = 1` cho NV cũ tại local (giữ để audit).
> 3. INSERT bản ghi mới qua `[LINK1]` với MANV mới + MACN mới + TrangThaiXoa = 0.
>
> MSDTC đảm bảo cả 2 bước cùng commit hoặc cùng rollback."

---

## SAU KHI DEMO — CHUẨN BỊ VẤN ĐÁP

Giảng viên thường hỏi ngay sau demo. Các câu hay gặp nhất (đáp án tại [`04_CauHoiVanDap.md`](04_CauHoiVanDap.md)):

1. "Chuyển tiền khác chi nhánh hoạt động thế nào?" → Cụm 7 câu 7.1
2. "Đứt mạng giữa 2 site trong lúc chuyển tiền → chuyện gì xảy ra?" → Cụm 3 câu 3.4
3. "LINK1 trỏ đến đâu ở từng site?" → Cụm 2 câu 2.2
4. "Tại sao bảng `GD_CHUYENTIEN`/`GD_GOIRUT` không có `MACN`?" → Cụm 1 câu 1.4
5. "Login có được Replication đồng bộ không?" → Cụm 5 câu 5.4
6. "`TaiKhoan` nhân bản toàn vẹn thay vì phân mảnh — vì sao?" → Cụm 1 câu 1.3
7. "PUB_TRACUU chỉ có 1 article (`KhachHang`) — vậy TRACUU lấy `NhanVien`/`TaiKhoan` ở đâu?" → Cụm 5 câu 5.6

---

## KỊCH BẢN DỰ PHÒNG — Nếu gặp lỗi khi demo

| Lỗi | Nguyên nhân có thể | Cách xử lý nhanh |
|---|---|---|
| `Login failed` khi đăng nhập | Sai password / Login chưa được cấp trên đúng server | Chạy lại `sql/setup/09..11_TaoTaiKhoan*.sql` |
| Chuyển tiền fail với "MSDTC is unavailable" | MSDTC chưa bật hoặc chưa cấu hình network access | `services.msc` → Start MSDTC. Tường lửa cho phép port 135 + dynamic RPC |
| App không chạy | Node process cũ đang giữ port 3001 | `start.bat` tự kill process cũ, hoặc `netstat -aon | findstr 3001` → `taskkill /F /PID <pid>` |
| SP báo `Invalid object name 'NhanVien'` khi NganHang chọn TK cụ thể | Đang cố gọi SP dành cho chi nhánh trên TRACUU | Đã fix trong `baocao.js` — mượn `BENTHANH` để gọi `SP_SaoKeTaiKhoan` |
| Không thấy dữ liệu mới sau khi thêm | Replication có độ trễ vài giây | Refresh sau 3–5s, hoặc show trực tiếp trên SSMS |
| SP báo `session is in the kill state` | Query LINK1 nằm chung scope với INSERT bảng có Merge trigger | Đã fix trong `sp_MoTaiKhoan` — tách LINK1 query khỏi DTC scope |
