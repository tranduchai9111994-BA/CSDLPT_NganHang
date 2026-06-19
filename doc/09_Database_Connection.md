# 🗄️ Quản Lý Kết Nối CSDL Phân Tán (`db.js`)

Đây là trái tim của ứng dụng CSDLPT. File `db.js` định nghĩa Connection Pool tới nhiều instance SQL Server khác nhau.

## 1. Khái Niệm `serverKey`
Mỗi chi nhánh hoặc cụm server được gắn một **Key**:
- `NGUON`: Server gốc chứa toàn bộ dữ liệu.
- `BENTHANH` (SQL1): Phân mảnh chi nhánh Bến Thành.
- `TANDINH` (SQL2): Phân mảnh chi nhánh Tân Định.
- `TRACUU` (SQL3): Server dùng để nhóm Ngân Hàng tra cứu toàn bộ dữ liệu. `TRACUU` chỉ chứa bản hợp nhất của bảng `KhachHang`. Đối với các báo cáo giao dịch (Sao kê), nhóm `NganHang` phải chọn tên chi nhánh trên giao diện, sau đó Backend dùng Linked Server trỏ về phân mảnh tương ứng (BENTHANH hoặc TANDINH) để kéo dữ liệu, tuyệt đối không lấy giao dịch từ TRACUU.

## 2. Cơ Chế Lấy Connection
Thay vì hardcode một chuỗi kết nối duy nhất, ứng dụng gọi:
```javascript
const rows = await querySQL(serverKey, "SELECT * FROM KhachHang");
```
Biến `serverKey` được xác định tại thời điểm người dùng đăng nhập (`req.session.user.SERVER`) và được lưu, sử dụng xuyên suốt các phiên làm việc. Điều này cho phép:
- Nhân viên Tân Định tự động thao tác trên SQL2.
- Nhân viên Bến Thành thao tác trên SQL1.
- Nhóm Ngân Hàng có thể chọn `serverKey` linh hoạt khi xem các báo cáo.
