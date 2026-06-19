# 🔄 Cơ Chế Phân Tán & Nhân Bản Dữ Liệu (Replication)

Tài liệu này trình bày chi tiết về kiến trúc phân tán cơ sở dữ liệu (Distributed Database Architecture) được áp dụng trong hệ thống thông qua công nghệ **SQL Server Replication**.

## 1. Mô Hình Tổng Quan (Publisher - Subscriber)

Hệ thống tuân theo mô hình Xuất bản - Đăng ký (Publisher - Subscriber) với 1 Server Gốc và 3 Server phân mảnh:

- **Publisher (Máy chủ xuất bản):** `ES-HAITD16` (thường gọi là mảnh NGUON). Đây là nơi chứa toàn bộ cơ sở dữ liệu gốc (nguyên thủy chưa phân mảnh), đồng thời có thể đóng vai trò là **Distributor** (Máy chủ phân phối) để quản lý và điều phối dữ liệu đồng bộ giữa các mảnh.
- **Subscribers (Các máy chủ đăng ký / Phân mảnh):**
  - `ES-HAITD16\SQL1` (Chi nhánh Bến Thành - Phân mảnh 1)
  - `ES-HAITD16\SQL2` (Chi nhánh Tân Định - Phân mảnh 2)
  - `ES-HAITD16\SQL3` (Phân mảnh Tra cứu - Phân mảnh 3)

## 2. Tiêu Chí Phân Mảnh (Fragmentation Rules)

Cơ sở dữ liệu được áp dụng kỹ thuật **Phân mảnh ngang (Horizontal Fragmentation)** đối với hầu hết các bảng nghiệp vụ, dựa trên thuộc tính `MACN` (Mã chi nhánh).

### 2.1. Phân mảnh 1: Chi nhánh Bến Thành (SQL1)
- **Điều kiện Lọc (Filter):** `MACN = 'BENTHANH'`
- Dữ liệu ở các bảng `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN` chỉ chứa các dòng có mã chi nhánh là Bến Thành.
- Đối với bảng danh mục như `ChiNhanh`, và bảng `TaiKhoan` **[Cập nhật 19/06/2026]**, dữ liệu được nhân bản toàn vẹn (Replicated entirely) để chi nhánh nào cũng truy xuất được ngay tại local.

### 2.2. Phân mảnh 2: Chi nhánh Tân Định (SQL2)
- **Điều kiện Lọc (Filter):** `MACN = 'TANDINH'`
- Tương tự SQL1, phân mảnh này chỉ chứa các dòng dữ liệu mà trường MACN là 'TANDINH'.

### 2.3. Phân mảnh 3: Trạm Tra Cứu (SQL3)
- **Chức năng:** Phục vụ nhóm quyền `NganHang` để xem báo cáo toàn hệ thống hoặc tra cứu khách hàng nhanh mà không làm ảnh hưởng đến hiệu năng (Performance) của các máy chủ đang xử lý giao dịch.
- **Cấu hình:** Phân mảnh này KHÔNG phải là Full Copy của Publisher. Nó **chỉ Replicate Full bảng `KhachHang`** của toàn hệ thống để tối ưu hóa việc tra cứu. Các bảng giao dịch không cần replicate sang đây vì nhóm Ngân Hàng có thể dùng Linked Server gọi ngược lên `NGUON` hoặc chéo sang các mảnh để xem báo cáo.

**[Cập nhật 19/06/2026] Quy tắc đọc/ghi dữ liệu cho bảng nhân bản toàn vẹn (`TaiKhoan`, `ChiNhanh`):**
- **Đọc (SELECT):** Đọc trực tiếp tại local (Subscriber) để tăng tốc độ truy vấn, không cần qua Linked Server.
- **Ghi (INSERT/UPDATE/DELETE):** Chỉ thao tác trên local nếu dữ liệu đó thuộc về chi nhánh hiện tại. Nếu dữ liệu thuộc chi nhánh đối tác (ví dụ: cộng tiền vào tài khoản mở tại chi nhánh khác), **BẮT BUỘC** phải ghi qua Linked Server (`[LINK1]`) để trỏ về bản gốc (Publisher) hoặc site sở hữu dữ liệu đó. TUYỆT ĐỐI không ghi trực tiếp lên bản nhân bản tại Subscriber vì sẽ bị khoá ghi hoặc bị Replication ghi đè (override) ở chu kỳ đồng bộ kế tiếp.

## 3. Cấu hình Publication & Subscriptions

Sau khi chuẩn bị xong, tiến hành cấu hình Merge Replication theo mô hình Publisher - Subscriber.

### 3.1. Article cấu hình cho từng Publication [Cập nhật 19/06/2026]
Kiểu Replicate đã chọn cho Stored Procedures: **"Replicate stored procedure definitions"** (đồng bộ cấu trúc/code), KHÔNG dùng "Replicate as execution".
- **PUB_BENTHANH và PUB_TANDINH:** Đều add đủ 11 SP nghiệp vụ và quản trị (gồm: `sp_ChuyenNhanVien`, `sp_ChuyenTien`, `sp_GuiTien`, `sp_LietKeKhachHang`, `sp_LietKeTaiKhoanTheoNgay`, `sp_Login_App`, `sp_MoTaiKhoan`, `sp_RutTien`, `SP_SaoKeTaiKhoan`, `SP_TaoTaiKhoan`, `sp_ThemKhachHang`).
- **PUB_TRACUU:** Chỉ add 2 SP quản trị là `sp_Login_App` và `SP_TaoTaiKhoan`. (Vì TRACUU không có dữ liệu giao dịch local, các SP đọc/báo cáo đặc thù của TRACUU dùng `[LINK1]` + `[LINK2]` được viết tay riêng trên site này, không đưa vào Article).

## 4. Tự Động Hóa Quá Trình Đồng Bộ Lên Server 3 (TRACUU)

Hệ thống sử dụng **Transactional Replication** hoặc **Merge Replication** với cơ chế sau:
1. **Khởi tạo:** Các chi nhánh (SQL1, SQL2, SQL3) nhận bản Snapshot ban đầu từ NGUON.
2. **Đồng bộ 2 chiều (Sync):** Khi nhân viên tại Bến Thành thêm 1 Khách hàng mới, dữ liệu lập tức được chèn vào mảnh Bến Thành (SQL1). Thông qua Log Reader Agent / Merge Agent, dữ liệu này được đồng bộ ngược về máy chủ Gốc (`ES-HAITD16`) và từ đó truyền xuống máy chủ Tra cứu (`SQL3`).
3. Dữ liệu của Bến Thành sẽ KHÔNG bao giờ bị đồng bộ nhầm sang Tân Định (`SQL2`) nhờ vào lớp Filter Constraints (Điều kiện lọc) đã thiết lập trong quá trình định nghĩa **Publication**.

## 5. Phân Tán Giao Dịch Phức Tạp (Distributed Transactions)

Đối với các nghiệp vụ xảy ra **xuyên chi nhánh** (Ví dụ: Chuyển tiền từ Bến Thành sang Tân Định), hệ thống không thể chỉ dựa vào Replication vì độ trễ (Latency). Thay vào đó, nó kết hợp dùng **Linked Server** và dịch vụ **MSDTC (Microsoft Distributed Transaction Coordinator)**.

- Khi gọi Stored Procedure `sp_ChuyenTien` tại SQL1, câu lệnh sẽ Update trừ tiền ở `SQL1` (Local) và đồng thời gọi qua `[LINK1]` để Update cộng tiền ở `SQL2` (Remote).
- MSDTC đảm bảo tuân thủ giao thức **2-Phase Commit** (Chuẩn bị và Ghi nhận). Nếu `SQL2` đột ngột sập nguồn hoặc mất mạng kết nối ngay lúc chuyển tiền, toàn bộ giao dịch tại cả 2 bên sẽ tự động bị Rollback, đảm bảo tiền không bị "mất tích" vào hư không.

## 6. Quản Lý Khóa Chính Phân Tán (Identity Range Management)

Trong môi trường phân tán (đặc biệt khi dùng Merge Replication hoặc Updateable Transactional Replication), nếu 2 chi nhánh cùng insert dữ liệu vào một bảng có cột `IDENTITY` (như bảng chứa `MAGD` tự tăng), sẽ xảy ra lỗi trùng khóa chính khi đồng bộ về Gốc.

**Giải pháp:** SQL Server cung cấp cơ chế **Identity Range Management** (tự động phân bổ dải ID).
- **Cơ chế:** Mỗi Subscriber sẽ được cấp một dải số độc lập (`@identity_range`). Ví dụ: Chi nhánh Bến Thành được cấp ID từ `1,000` đến `1,999`. Chi nhánh Tân Định được cấp ID từ `2,000` đến `2,999`. 
- Khi Bến Thành thêm giao dịch, hệ thống tự động sinh ra số 1001. Khi đồng bộ về Gốc, số 1001 này tuyệt đối không bao giờ bị đụng độ (conflict) với bất kỳ số nào sinh ra tại Tân Định. Khi chi nhánh dùng hết dải số, hệ thống sẽ tự cấp phát dải mới.
