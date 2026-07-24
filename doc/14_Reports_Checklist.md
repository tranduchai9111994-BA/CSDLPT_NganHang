# Checklist Báo Cáo — Đáp Ứng 3 Yêu Cầu Đề Bài

> **Đề bài (3 yêu cầu bắt buộc):**
> 1. **Sao kê giao dịch** của 1 tài khoản trong 1 khoảng thời gian `[@TUNGAY, @DENNGAY]`.
> 2. **Liệt kê tài khoản mở** trong 1 khoảng thời gian — của 1 chi nhánh / tất cả chi nhánh.
> 3. **Liệt kê khách hàng** theo từng chi nhánh, trong từng chi nhánh in tăng dần theo họ tên.

Cả 3 chức năng đã được implement, tích hợp menu **"Báo cáo"** trong `layout.ejs`. Chi tiết bên dưới.

---

## Yêu Cầu 1 — Sao Kê Giao Dịch Tài Khoản

**Route:** `GET/POST /baocao/saoke` (`routes/baocao.js`).
**Views:** `views/baocao/saoke.ejs`.
**SP chính:** `SP_SaoKeTaiKhoan` (bản chi nhánh, đọc local + LINK1).

**Đầu ra:** bảng 5 cột — `Số dư đầu | Ngày | Loại GD | Số tiền | Số dư sau`.

**Điểm phân tán:**
- Tính **100% dưới SQL Server** bằng Window Function `SUM() OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)`. Node.js chỉ nhận dữ liệu và render.
- Route tự thêm `23:59:59` vào `DENNGAY` để bao trọn ngày kết thúc.
- **NganHang** (server=TRACUU) mượn tạm `spServer = 'BENTHANH'` để gọi `SP_SaoKeTaiKhoan` khi có chọn số TK cụ thể — vẫn đủ dữ liệu vì TaiKhoan replicate full + GD gộp Local+LINK1.
- **NganHang không chọn TK** → gọi `sp_SaoKeToanBo` trên TRACUU (UNION ALL LINK1+LINK2 cho GD).
- **KhachHang**:
  - Pre-fetch danh sách TK của mình qua `sp_TaiKhoanKhachHang` (không raw SELECT vì KhachHang không có `GRANT SELECT` trên `TaiKhoan`).
  - Server-side check: SOTK người gửi lên phải nằm trong danh sách của KH (chặn giả mạo).
  - Nếu KH không chọn TK → gọi `SP_SaoKeTaiKhoan` cho từng TK rồi merge (thay vì raw SELECT bảng GD).

**Phân quyền:**
- `NganHang`: xem mọi TK.
- `ChiNhanh`: xem mọi TK (nhờ TaiKhoan replicate full trên chi nhánh, SP tự đọc GD Local + LINK1 nên vẫn đủ).
- `KhachHang`: chỉ xem TK của chính mình (double-check server-side).

---

## Yêu Cầu 2 — Liệt Kê Tài Khoản Mở Trong Khoảng Thời Gian

**Route:** `GET /baocao/lietke?loai=tk` (`routes/baocao.js`).
**Views:** `views/baocao/lietke.ejs`.
**SP chính:** `sp_LietKeTaiKhoanTheoNgay` (bản TRACUU — dùng cho NganHang).

**Đầu ra:** bảng — `SOTK | CMND | Họ Tên | Số Dư | Chi Nhánh | Ngày Mở TK`.

**Điểm phân tán:**
- **NganHang** (mọi chi nhánh): gọi `sp_LietKeTaiKhoanTheoNgay` trên TRACUU. SP đọc `[LINK1].NGANHANG.dbo.TaiKhoan` (chỉ LINK1, không UNION LINK2 vì TaiKhoan replicate full → tránh duplicate x2). `OUTER APPLY (SELECT TOP 1 ... FROM KhachHang WHERE CMND=tk.CMND)` để tránh nhân bản khi KH có nhiều row cùng CMND.
- **ChiNhanh**: raw SELECT trực tiếp trên `TaiKhoan` local + LEFT JOIN `KhachHang` local, `WHERE MACN = user.MACN` → chỉ TK của chi nhánh mình.
- Filter dropdown `macn` (chỉ hiện với NganHang), khoảng ngày `tungay`/`denngay`, search `CMND`/`HoTen`.

**Phân quyền:**
- `NganHang`: có dropdown chọn chi nhánh, có thể xem cả 2 CN.
- `ChiNhanh`: khóa cứng theo `user.MACN`.
- `KhachHang`: không được vào menu này (middleware chặn).

---

## Yêu Cầu 3 — Liệt Kê Khách Hàng Theo Chi Nhánh

**Route:** `GET /baocao/lietke?loai=kh` (`routes/baocao.js`).
**Views:** `views/baocao/lietke.ejs`.

**Đầu ra:** bảng — `CMND | Họ Tên | Chi Nhánh | SĐT`.

**Điểm phân tán:**
- **NganHang không chọn chi nhánh**: raw SELECT trên TRACUU (KhachHang replicate full ở đó) — `ORDER BY MACN, HO, TEN` → đúng yêu cầu "theo từng chi nhánh, trong từng chi nhánh in tăng dần theo họ tên".
- **NganHang chọn 1 chi nhánh cụ thể**: SELECT trên site tương ứng theo `WHERE MACN=@macn ORDER BY HO, TEN`.
- **ChiNhanh**: force `WHERE MACN = user.MACN ORDER BY HO, TEN` — chỉ thấy KH của mình.
- Search hỗ trợ `CMND LIKE @search OR HO+' '+TEN LIKE @search`.

**Phân quyền:**
- `NganHang`, `ChiNhanh`: xem theo phạm vi tương ứng.
- `KhachHang`: chặn qua middleware `requireRole`.

---

## Kiểm Tra Nhanh Khi Demo

| Bước | Hành động | Kết quả kỳ vọng |
|---|---|---|
| 1 | Login `admin/1` chọn TRACUU → `/baocao/lietke?loai=kh` | Thấy KH cả 2 chi nhánh, sort theo `MACN, HO, TEN` |
| 2 | Login `admin/1` chọn TRACUU → `/baocao/lietke?loai=tk&tungay=...&denngay=...` | Thấy TK của cả 2 chi nhánh (không duplicate) |
| 3 | Login `admin/1` chọn TRACUU → `/baocao/saoke` chọn TK cụ thể | Sao kê đầy đủ + Số dư đầu kỳ tính đúng bằng Window Function |
| 4 | Login `BT001/1` (ChiNhanh) → `/baocao/lietke?loai=kh` | Chỉ thấy KH của BENTHANH |
| 5 | Login `TD001/1` (ChiNhanh) → `/baocao/lietke?loai=tk` | Chỉ thấy TK của TANDINH |
| 6 | Login KH (`0123456789/MACPIN`) → `/baocao/saoke` | Chỉ thấy TK của chính KH đó, tự lọc theo `LOGIN_NAME()` trong SP |
