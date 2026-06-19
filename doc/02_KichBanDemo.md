# 🎬 Kịch Bản Demo — Đồ Án CSDL Phân Tán Ngân Hàng

> **Thời lượng dự kiến:** 8–12 phút  
> **Mục tiêu:** Show đủ các chức năng chính, nhấn mạnh phần phân tán + phân quyền.  
> **Nguyên tắc:** Demo ĐÚNG THỨ TỰ, không nhảy lung tung. Mỗi bước ghi rõ dữ liệu test.

---

## CHUẨN BỊ TRƯỚC KHI DEMO

### Checklist khởi động
- [ ] 4 SQL Server instance đang chạy (NGUON, SQL1, SQL2, SQL3)
- [ ] MSDTC đang chạy (services.msc → Distributed Transaction Coordinator → Running)
- [ ] Đã chạy `npm start` trong thư mục APP_NGANHANG
- [ ] Browser mở sẵn `http://localhost:3000`
- [ ] Mở sẵn SSMS kết nối 4 instance (để show dữ liệu nếu giảng viên hỏi)
- [ ] Ghi chú tài khoản test trên giấy (bên dưới)

### Tài khoản test (ghi ra giấy để không quên)

| Mục đích | Login | Password | Server | Ghi chú |
|---|---|---|---|---|
| Demo nhóm ChiNhanh (BT) | NV01 | 123456 | BENTHANH | Giao dịch viên Bến Thành |
| Demo nhóm ChiNhanh (TD) | NV03 | 123456 | TANDINH | Giao dịch viên Tân Định |
| Demo nhóm NganHang | admin | admin | TRACUU | Ban Giám Đốc |
| Demo nhóm KhachHang | (CMND KH mẫu) | 123456 | BENTHANH/TANDINH | Khách hàng |

> ⚠️ **CẬP NHẬT:** Trước khi demo, mở SSMS kiểm tra SOTK và CMND mẫu thực tế trong DB.  
> Ghi lại vào bảng này: SOTK_BT = _______, SOTK_TD = _______, CMND_KH = _______

---

## KỊCH BẢN DEMO (theo thứ tự)

### Phần 0: Giới thiệu kiến trúc (1 phút)

**Nói:** "Hệ thống gồm 4 SQL Server instance: NGUON là server gốc chứa data toàn cục, SQL1 là chi nhánh Bến Thành, SQL2 là Tân Định, SQL3 là server tra cứu. Dữ liệu được phân mảnh ngang theo mã chi nhánh. Giao tiếp giữa các mảnh qua Linked Server."

**Show (nếu cần):** Mở SSMS, show 4 instance trong Object Explorer.

---

### Phần 1: Login nhóm ChiNhanh — BENTHANH (1 phút)

**Thao tác:**
1. Mở `http://localhost:3000/login`
2. Nhập: Username = `NV01`, Password = `123456`, Chi nhánh = `BENTHANH`
3. Bấm Đăng nhập

**Nói:** "Đăng nhập bằng SQL Authentication thật — hệ thống tạo connection pool trực tiếp bằng login/password của nhân viên, không dùng tài khoản hệ thống trung gian."

**Kỳ vọng:** Vào trang chủ, menu trái hiển thị đủ: Khách hàng, Nhân viên, Tài khoản, Giao dịch, Báo cáo, Quản trị.

---

### Phần 2: Thêm khách hàng mới (1 phút)

**Thao tác:**
1. Vào menu **Khách hàng** → bấm **Thêm**
2. Nhập dữ liệu mẫu:
   - CMND: `9999900001`
   - Họ: `Nguyễn Văn`
   - Tên: `Demo`
   - Địa chỉ: `123 Lê Lợi, Q1`
   - Phái: `Nam`
   - Ngày cấp: `01/01/2020`
   - SĐT: `0901234567`
3. Bấm **Ghi**

**Nói:** "Khách hàng được thêm vào phân mảnh BENTHANH (SQL1). Sau khi Replication chạy, dữ liệu sẽ tự đồng bộ sang server TRACUU (SQL3) để nhóm Ngân Hàng tra cứu."

**Kỳ vọng:** Thêm thành công, KH xuất hiện trong danh sách.

---

### Phần 3: Mở tài khoản cho KH vừa thêm (1 phút)

**Thao tác:**
1. Vào menu **Tài khoản**
2. Chọn khách hàng vừa thêm (CMND: `9999900001`)
3. Grid bên dưới hiển thị danh sách TK (ban đầu trống)
4. Bấm **Thêm** → Số TK tự sinh, nhập số dư ban đầu: `1000000` (1 triệu)
5. Bấm **Ghi**

**Nói:** "Đây là giao diện Master-Detail theo yêu cầu đề bài. Master là thông tin KH, Detail là grid TK. Số TK được tự sinh bằng cách lấy MAX(SOTK) + 1."

**Ghi lại:** SOTK vừa tạo = _______ (cần để demo gửi/rút/chuyển tiền)

---

### Phần 4: Gửi tiền (30 giây)

**Thao tác:**
1. Vào menu **Giao dịch** → **Gửi/Rút tiền**
2. Chọn TK vừa mở, Loại GD = **Gửi tiền**, Số tiền = `500000`
3. Bấm thực hiện

**Nói:** "Số tiền gửi tối thiểu 100.000đ theo đề bài. SP sp_GuiTien kiểm tra điều kiện này."

**Kỳ vọng:** Thành công. Số dư tăng từ 1.000.000 lên 1.500.000.

---

### Phần 5: Rút tiền — test lỗi (30 giây)

**Thao tác:**
1. Rút tiền `50000` (dưới 100.000) → **Phải báo lỗi**
2. Rút tiền `200000` → **Thành công**

**Nói:** "SP kiểm tra 2 điều kiện: số tiền >= 100.000 và số dư đủ. Nếu vi phạm sẽ ROLLBACK."

---

### Phần 6: Chuyển tiền liên chi nhánh ⭐ (2 phút — PHẦN QUAN TRỌNG NHẤT)

**Đây là phần giảng viên quan tâm nhất vì thể hiện rõ CSDL Phân Tán.**

**Thao tác:**
1. Vào **Giao dịch** → **Chuyển tiền**
2. TK chuyển: TK vừa mở ở BENTHANH (ghi ở bước 3)
3. TK nhận: Một SOTK ở chi nhánh TANDINH (kiểm tra trước trong SSMS)
4. Số tiền: `300000`
5. Bấm thực hiện

**Nói:** "Đây là giao dịch phân tán. SP sp_ChuyenTien kiểm tra TK nhận có nằm ở local không, nếu không thì tìm qua LINK1 (Linked Server trỏ sang Tân Định). Giao dịch bọc trong BEGIN DISTRIBUTED TRANSACTION với SET XACT_ABORT ON. MSDTC đảm bảo Two-Phase Commit — nếu mất kết nối giữa chừng, cả 2 bên tự động Rollback."

**Xác nhận (nếu giảng viên yêu cầu):** Mở SSMS → SQL2 (TANDINH) → query `SELECT SODU FROM TaiKhoan WHERE SOTK = 'xxx'` → số dư đã tăng.

---

### Phần 7: Đăng xuất → Login nhóm NganHang (1 phút)

**Thao tác:**
1. Đăng xuất
2. Login: `admin` / `admin` / Chi nhánh: `TRACUU`

**Nói:** "Nhóm NganHang đăng nhập vào server TRACUU. Họ có thể chọn bất kỳ chi nhánh nào để xem báo cáo nhưng không được thêm/sửa/xóa dữ liệu."

**Kỳ vọng:** Menu chỉ có Báo cáo, Quản trị. Không có Giao dịch (hoặc nếu có thì bị khóa).

---

### Phần 8: Xem sao kê tài khoản (1 phút)

**Thao tác:**
1. Vào **Báo cáo** → **Sao kê**
2. Nhập SOTK (dùng TK đã giao dịch ở trên)
3. Chọn khoảng thời gian → Bấm xem

**Nói:** "SP_SaoKeTaiKhoan gom dữ liệu từ cả GD_GOIRUT và GD_CHUYENTIEN, tính số dư lũy kế bằng Window Functions (SUM OVER). Kỹ thuật 'tính lùi' giúp chỉ kéo dữ liệu trong khoảng thời gian yêu cầu qua Linked Server thay vì toàn bộ lịch sử."

**Kỳ vọng:** Bảng hiển thị: Số dư đầu | Ngày | Loại GD | Số tiền | Số dư sau.

---

### Phần 9: Liệt kê KH / TK (30 giây)

**Thao tác:**
1. **Báo cáo** → **Liệt kê khách hàng** → show sắp xếp theo MACN, HO, TEN
2. **Báo cáo** → **Liệt kê tài khoản** → chọn khoảng thời gian → show

**Nói:** "Nhóm NganHang có thể chọn xem theo chi nhánh cụ thể hoặc tất cả. Dữ liệu KH lấy từ TRACUU (đã replicate full), dữ liệu TK/GD lấy qua Linked Server."

---

### Phần 10: Login nhóm KhachHang (1 phút)

**Thao tác:**
1. Đăng xuất
2. Login bằng CMND khách hàng / PIN

**Nói:** "Khách hàng chỉ thấy menu Sao kê. Nếu cố truy cập URL khác (ví dụ /khachhang) sẽ bị HTTP 403. Bảo mật 3 tầng: Database Role, Backend Middleware, UI ẩn menu."

**Kỳ vọng:** Chỉ thấy form sao kê, chỉ xem được TK của mình.

---

### Phần 11 (Bonus): Chuyển nhân viên (1 phút — nếu còn thời gian)

**Thao tác:**
1. Login lại NV01 ở BENTHANH
2. Vào **Nhân viên** → chọn 1 NV → bấm **Chuyển chi nhánh**
3. Chọn chi nhánh mới: TANDINH

**Nói:** "Distributed Transaction: UPDATE TrangThaiXoa = 1 ở chi nhánh cũ, INSERT bản ghi mới qua LINK1 sang chi nhánh mới. Bản ghi cũ được giữ lại cho mục đích kiểm toán."

---

## SAU KHI DEMO — SẴN SÀNG CHO VẤN ĐÁP

Giảng viên thường hỏi ngay sau demo. Các câu hay gặp nhất (đã có đáp án ở `07_CauHoiVanDap.md`):

1. "Chuyển tiền khác chi nhánh hoạt động thế nào?" → Cụm 7, câu 7.1
2. "Mất mạng giữa chừng thì sao?" → Cụm 3, câu 3.4
3. "LINK1 trỏ đến đâu?" → Cụm 2, câu 2.2
4. "Tại sao bảng giao dịch không có MACN?" → Cụm 1, câu 1.3
5. "Login có được Replication đồng bộ không?" → Cụm 5, câu 5.4

---

## KỊCH BẢN DỰ PHÒNG — NẾU GẶP LỖI KHI DEMO

| Lỗi | Nguyên nhân có thể | Cách xử lý nhanh |
|---|---|---|
| Login failed | MSDTC chưa bật hoặc sai password | Mở services.msc → start MSDTC |
| Chuyển tiền fail | Linked Server chưa cấu hình đúng | Show lỗi cho GV, giải thích đây là lỗi MSDTC |
| App không chạy | Node.js chưa start | `cd APP_NGANHANG && npm start` |
| Không thấy dữ liệu | Replication chưa sync | Show trên SSMS, giải thích có độ trễ |
| SP báo lỗi khi chuyển NV | NV đã bị TrangThaiXoa = 1 | Chọn NV khác đang active |