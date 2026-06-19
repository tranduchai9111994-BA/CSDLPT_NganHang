# Đánh giá tiến độ - Yêu cầu "Liệt kê - Thống kê"

Dựa trên yêu cầu của thầy giáo:
> 1. Sao kê giao dịch của 1 tài khoản trong 1 khoảng thời gian (@tungay , @denngay).
> 2. Liệt kê các tài khoản mở trong 1 khoảng thời gian của chi nhánh, của tất cả các chi nhánh.
> 3. Liệt kê các khách hàng theo từng chi nhánh, trong từng chi nhánh thì in tăng dần theo họ tên.

Sau khi rà soát toàn bộ source code NodeJS (`routes/baocao.js`) và Database (`06_SP_SaoKeTaiKhoan.sql`), đây là báo cáo tiến độ:

## 1. Sao kê giao dịch tài khoản: ĐÃ HOÀN THÀNH (100%)
- **Thực trạng code:** Hệ thống đã có file `06_SP_SaoKeTaiKhoan.sql` và route `POST /baocao/saoke`.
- **Chức năng:** Nhận tham số `@SOTK`, `@TUNGAY`, `@DENNGAY`. 
- **Độ chính xác:**
  - Kết xuất chính xác format bảng 5 cột: Số dư đầu | Ngày | Loại giao dịch | Số tiền | Số dư sau.
  - Toàn bộ việc tính số dư đầu kỳ và số dư lũy kế từng dòng (Số dư sau) được xử lý 100% dưới SQL Server thông qua Window Functions, đáp ứng tuyệt đối yêu cầu tính toán dưới CSDL. Tầng Node.js chỉ nhận dữ liệu và in ra giao diện.
  - Tự động khóa: Khách hàng chỉ được phép sao kê chính tài khoản của họ (bảo mật cấp cao).

## 2. Liệt kê tài khoản mở trong 1 khoảng thời gian: ĐÃ HOÀN THÀNH (100%)
- **Thực trạng code:** Nằm tại route `GET /baocao/lietke?loai=tk`.
- **Chức năng:** 
  - Giao diện cho phép chọn từ ngày, đến ngày.
  - **Nhóm NganHang:** Xem được tài khoản mở của *tất cả các chi nhánh* (chọn chi nhánh qua dropdown) bằng cách query vào mảnh `TRACUU`.
  - **Nhóm ChiNhanh:** Code tự động khóa chặt, chỉ cho phép lọc và xem các tài khoản mở *tại chi nhánh hiện tại*.
- **Độ chính xác:** Truy vấn kết nối bảng `TaiKhoan` và `KhachHang` để hiển thị đầy đủ SOTK, HoTen, SoDu, NgayMo, MaCN.

## 3. Liệt kê khách hàng theo từng chi nhánh: ĐÃ HOÀN THÀNH (100%)
- **Thực trạng code:** Nằm tại route `GET /baocao/lietke?loai=kh`.
- **Chức năng:**
  - **Nhóm NganHang:** Nếu không chọn chi nhánh cụ thể, code sẽ tự động query vào mảnh `TRACUU` với câu lệnh `ORDER BY MACN, HO, TEN`. (Đáp ứng chính xác yêu cầu: *Liệt kê theo từng chi nhánh, trong từng chi nhánh in tăng dần theo Họ Tên*).
  - **Nhóm ChiNhanh:** Code tự động thêm điều kiện `WHERE MACN = @macn ORDER BY HO, TEN` để chỉ hiển thị khách của chi nhánh đó, tăng dần chuẩn xác.

---

### Tổng Kết
Chúc mừng bạn! Cả **3/3 báo cáo thống kê đều ĐÃ ĐƯỢC LẬP TRÌNH HOÀN TẤT** và tích hợp thẳng vào giao diện Web với độ bảo mật (chặn quyền NganHang/ChiNhanh) rất chặt chẽ. Bạn không cần code thêm bất cứ dòng nào cho 3 tính năng này nữa, chỉ cần mở App lên và bấm vào menu **"Báo cáo"** ở thanh bên trái (Sidebar) để trải nghiệm và chụp màn hình nộp báo cáo cho thầy!
