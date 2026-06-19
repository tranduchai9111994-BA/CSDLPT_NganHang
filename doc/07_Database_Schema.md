# 🗄️ Phân Tích Cấu Trúc Cơ Sở Dữ Liệu (NGANHANG)

Tài liệu này mô tả chi tiết về cấu trúc các bảng dữ liệu (Tables) và các thủ tục lưu trữ (Stored Procedures) cốt lõi đang được sử dụng trong CSDL Phân Tán của đồ án.

## 1. Cấu Trúc Bảng Dữ Liệu (Tables)

### 1.1. Bảng `ChiNhanh` (Chi Nhánh)
Lưu thông tin về các chi nhánh của ngân hàng. Bảng này thường được nhân bản (Replication) hoặc lưu trữ toàn cục.
- `MACN` (nchar 10): Mã chi nhánh (VD: BENTHANH, TANDINH) - **Khóa chính**
- `TENCN` (nvarchar 100): Tên chi nhánh - **Ràng buộc UNIQUE**
- `DIACHI` (nvarchar 100): Địa chỉ chi nhánh
- `SoDT` (nvarchar 15): Số điện thoại

### 1.2. Bảng `NhanVien` (Nhân Viên)
Thông tin các nhân viên làm việc tại ngân hàng. Mỗi chi nhánh chỉ chứa nhân viên của chi nhánh đó (phân mảnh ngang).
- `MANV` (nchar 10): Mã nhân viên - **Khóa chính**
- `HO` (nvarchar 50), `TEN` (nvarchar 10): Họ tên nhân viên
- `CMND` (nchar 10): Số CMND - **Ràng buộc UNIQUE**
- `DIACHI` (nvarchar 100): Địa chỉ
- `PHAI` (nvarchar 3): Giới tính (Nam/Nữ)
- `SODT` (nvarchar 15): Số điện thoại
- `MACN` (nchar 10): Mã chi nhánh (Khóa ngoại)
- `TrangThaiXoa` (int): Cờ đánh dấu đã xóa/nghỉ việc (0: Đang làm, 1: Đã xóa) - **Ràng buộc DEFAULT 0**

### 1.3. Bảng `KhachHang` (Khách Hàng)
Thông tin khách hàng giao dịch.
- `CMND` (nchar 10): Số CMND / CCCD - **Khóa chính**
- `HO` (nvarchar 50), `TEN` (nvarchar 10): Họ tên
- `DIACHI` (nvarchar 100): Địa chỉ
- `PHAI` (nvarchar 3): Giới tính
- `NGAYCAP` (date): Ngày cấp CMND
- `SODT` (nvarchar 15): Số điện thoại
- `MACN` (nchar 10): Khách hàng thuộc chi nhánh nào tạo.

### 1.4. Bảng `TaiKhoan` (Tài Khoản)
**[Cập nhật 19/06/2026]:** Bảng này được **nhân bản toàn vẹn** (Replicate Full) xuống tất cả các phân mảnh thay vì phân mảnh ngang theo MACN.
- **Lý do:** Cho phép các SP kiểm tra sự tồn tại của tài khoản đích (khi chuyển tiền khác chi nhánh) ngay tại local mà không cần gọi Linked Server để SELECT, giúp giảm tải mạng đáng kể.
- **Quy tắc ghi:** Chỉ UPDATE/INSERT local nếu TK thuộc đúng site đó; nếu TK thuộc site khác, phải UPDATE qua `[LINK1]` vào bản gốc. TUYỆT ĐỐI không UPDATE trực tiếp lên bản nhân bản tại Subscriber.

Một khách hàng có thể có nhiều tài khoản.
- `SOTK` (nchar 9): Số tài khoản - **Khóa chính**
- `CMND` (nchar 10): Chủ tài khoản (Khóa ngoại) - **NOT NULL**
- `SODU` (money): Số dư hiện tại - **Ràng buộc CHECK (SODU >= 0)**
- `MACN` (nchar 10): Mở tại chi nhánh nào
- `NGAYMOTK` (datetime): Ngày mở tài khoản

### 1.5. Bảng `GD_GOIRUT` (Giao dịch Gửi/Rút)
- `MAGD` (int): Mã giao dịch (Tự tăng) - **Khóa chính** (Lưu ý: Cần cấu hình Identity Range Management khi Replication để tránh đụng độ khóa giữa các Site)
- `SOTK` (nchar 9): Số tài khoản thực hiện giao dịch
- `LOAIGD` (nchar 2): Loại giao dịch (`GT` = Gửi tiền, `RT` = Rút tiền)
- `NGAYGD` (datetime): Thời điểm giao dịch
- `SOTIEN` (money): Số tiền giao dịch
- `MANV` (nchar 10): Nhân viên thực hiện giao dịch
> **Lưu ý Kiến trúc (Điểm Nghẽn):** Bảng này CỐ TÌNH KHÔNG CÓ cột `MACN`. Giao dịch thuộc chi nhánh nào sẽ được nội suy từ `MANV` (người lập) hoặc mảnh phân tán nơi nó được chèn vào. Việc thêm `MACN` là sai thiết kế schema gốc.

### 1.6. Bảng `GD_CHUYENTIEN` (Giao dịch Chuyển tiền)
- `MAGD` (int): Mã giao dịch (Tự tăng) - **Khóa chính** (Lưu ý: Cần cấu hình Identity Range Management khi Replication để tránh đụng độ khóa giữa các Site)
- `SOTK_CHUYEN` (nchar 9): Số tài khoản gửi đi
- `SOTK_NHAN` (nchar 9): Số tài khoản nhận tiền
- `SOTIEN` (money): Số tiền chuyển
- `NGAYGD` (datetime): Thời điểm chuyển
- `MANV` (nchar 10): Nhân viên thực hiện giao dịch
> **Lưu ý Kiến trúc (Điểm Nghẽn):** Tương tự, bảng này KHÔNG CÓ `MACN`. Các SP nghiệp vụ (`SP_SaoKeTaiKhoan`, `SP_ChuyenTien`) tuyệt đối không tham chiếu hoặc truyền `MACN` cho các bảng giao dịch này.

---

## 2. Các Thủ Tục Lưu Trữ (Stored Procedures) Quan Trọng

Toàn bộ các logic thay đổi số dư, kiểm tra ràng buộc phân tán đều được đẩy xuống SQL Server thông qua SP để đảm bảo tính toàn vẹn dữ liệu (ACID) trên môi trường Distributed. Dưới đây là các SP đã được tối ưu hóa tối đa:

- `SP_MoTaiKhoan` (@SOTK, @CMND, @SODU, @MACN, @MANV)
  - Mở tài khoản mới cho khách hàng, khởi tạo số dư.
  
- `SP_ThemKhachHang` (@CMND, @HO, @TEN, @DIACHI, @PHAI, @NGAYCAP, @SODT, @MACN)
  - Thêm mới một khách hàng vào chi nhánh cục bộ.
  
- `SP_GuiTien` (@SOTK, @SOTIEN, @MANV) / `SP_RutTien` (@SOTK, @SOTIEN, @MANV)
  - Tăng/Giảm số dư trong bảng `TaiKhoan` và ghi log vào `GD_GOIRUT`.
  - **Tối ưu:** Đều có `TRY...CATCH` và kiểm tra logic số dư kỹ lưỡng trước khi ghi.
  
- `SP_ChuyenTien` (@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, @MANV)
  - Nghiệp vụ liên chi nhánh phức tạp nhất. Trừ tiền ở tài khoản chuyển (Local) và cộng tiền ở tài khoản nhận (Local hoặc qua Linked Server).
  - **Tối ưu cực hạn:** Bắt buộc áp dụng `SET XACT_ABORT ON` và lệnh `BEGIN DISTRIBUTED TRAN` kết hợp `TRY...CATCH`. Cấu trúc này kích hoạt MSDTC (Two-Phase Commit), đảm bảo nếu đứt cáp mạng giữa 2 site lúc đang chuyển tiền, toàn bộ giao dịch ở cả 2 đầu sẽ tự động Rollback không sai một cắc.
  
- `SP_ChuyenNhanVien` (@MANV, @MACN_MOI)
  - Chuyển một nhân viên sang chi nhánh mới.
  - **Tối ưu cực hạn:** Tương tự `SP_ChuyenTien`, giao dịch này bọc trong `BEGIN DISTRIBUTED TRAN`. Ở Local, set `TrangThaiXoa = 1`, và dùng lệnh `INSERT INTO [LINK1]...` để bắn dữ liệu qua mảnh mới an toàn 100%.

- `sp_Login_App` (@LoginName) (Thay thế cho phiên bản sp_Login cũ)
  - SP trái tim của hệ thống phân quyền. Không còn query thủ công dễ dãi, nó kết nối qua `sys.database_principals` và `sys.database_role_members` để map chính xác SQL Login với người dùng. Trả về `USERNAME`, `MANV`, `HOTEN`, `NHOM` (Role của database) và `MACN`.

- `SP_SaoKeTaiKhoan` (@SOTK, @TUNGAY, @DENNGAY) (Thay thế cho sp_SaoKe)
  - Trả về lịch sử giao dịch. Gom toàn bộ bảng `GD_GOIRUT` và `GD_CHUYENTIEN` từ Local và Linked Server.
  - **Tối ưu cực hạn (Tránh nghẽn mạng):** Kỹ thuật "Tính lùi số dư đầu kỳ". Lấy số dư hiện tại trong bảng TaiKhoan trừ đi tổng biến động (SUM) sau ngày yêu cầu. Sau khi có số dư gốc, mới kéo dữ liệu chi tiết của 1 tháng qua Linked Server và dùng Window Functions (`SUM() OVER`) để tính toán cộng dồn. Tốc độ cao hơn gấp nhiều lần so với việc kéo toàn bộ 10 năm giao dịch qua mạng để tính.

---
**Ghi chú:** Các logic nghiệp vụ chính của ứng dụng ở tầng NodeJS phần lớn đóng vai trò trung chuyển, xác thực và gọi đúng SP thay vì tự viết các câu lệnh `UPDATE`, `INSERT` rời rạc để bảo đảm tuyệt đối an toàn dữ liệu trên môi trường phân tán.
