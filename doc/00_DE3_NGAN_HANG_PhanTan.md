# ĐỀ TÀI MÔN CƠ SỞ DỮ LIỆU PHÂN TÁN
## ĐỀ TÀI SỐ 3 – NGÂN HÀNG

**Nội dung:** Quản lý các tài khoản và giao dịch của khách hàng.
Cho cơ sở dữ liệu NGANHANG, trong đó có các tables sau:

### 1. Cấu trúc cơ sở dữ liệu

**a. CHINHANH:**
| Field Name | Data Type | Constraint |
| --- | --- | --- |
| MACN | nChar(10) | Primary key, mã chi nhánh |
| TENCN | nvarchar(100) | Unique, not null |
| DIACHI | nvarchar(100) | |
| SoDT | nVarchar(15) | |

**b. KHACHHANG:**
| Field Name | Data Type | Thuộc tính |
| --- | --- | --- |
| HO | nVarchar(50) | Not Null |
| TEN | nVarchar(10) | Not Null |
| DIACHI | nVarchar(100) | Not Null |
| CMND | nChar(10) | Primary key |
| NGAYCAP | Date | Not Null |
| SODT | nVarchar (15) | |
| PHAI | nVarchar(3) | ‘Nam’ hoặc ‘Nữ’ |
| MACN | nChar(10) | FK |

**c. NHANVIEN:**
| Field Name | Data Type | Thuộc tính |
| --- | --- | --- |
| MANV | nChar(10) | Primary key |
| HO | nVarchar(50) | Not Null |
| TEN | nVarchar(10) | Not Null |
| DIACHI | nVarchar(100) | Not Null |
| CMND | nChar(10) | Unique key, Not Null |
| PHAI | nVarchar(3) | ‘Nam’ hoặc ‘Nữ’ |
| SODT | nVarchar (15) | |
| MACN | nChar(10) | FK |
| TrangThaiXoa | int | 0: làm việc, 1: đã chuyển/nghỉ |

**d. TAIKHOAN:**
| Field Name | Data Type | Thuộc tính |
| --- | --- | --- |
| SOTK | nChar(9) | Primary key |
| CMND | nChar(10) | FK |
| SODU | money | |
| MACN | nChar(10) | FK |
| NGAYMOTK | datetime | |

**e. GD_CHUYENTIEN:**
| Field Name | Data Type | Thuộc tính |
| --- | --- | --- |
| MAGD | int | Primary key, IDENTITY |
| SOTK_CHUYEN | nChar(9) | FK |
| NGAYGD | datetime | Giá trị mặc định là ngày hiện tại |
| SOTIEN | money | Lớn hơn 0 |
| SOTK_NHAN | nChar(9) | FK |
| MANV | nChar(10) | FK |

**f. GD_GOIRUT:**
| Field Name | Data Type | Thuộc tính |
| --- | --- | --- |
| MAGD | int | Primary key, IDENTITY |
| SOTK | nChar(9) | FK |
| LOAIGD | nChar(2) | “GT”, hoặc “RT” |
| NGAYGD | datetime | Giá trị mặc định là ngày hiện tại |
| SOTIEN | money | Lớn hơn 0, Giá trị mặc định là 100.000 |
| MANV | nChar(10) | FK |

---

### 2. Phân tán cơ sở dữ liệu

- **Trạm 1 (Bến Thành):** Chứa các thông tin của chi nhánh Bến Thành.
- **Trạm 2 (Tân Định):** Chứa các thông tin của chi nhánh Tân Định.
- **Trạm 3 (Tra Cứu):** Chứa thông tin của các khách hàng thuộc cả 2 chi nhánh để phục vụ cho việc tra cứu.

---

### 3. Yêu cầu chức năng của chương trình

#### A. Cập nhật (Mỗi form đều có đủ các nút: Thêm, Xóa, Phục hồi, Ghi, Thoát)
1. **Nhân viên:** Form này cho phép cập nhật nhân viên. Khi chuyển một nhân viên từ chi nhánh này sang chi nhánh kia thì tự động chuyển dữ liệu của nhân viên đó sang chi nhánh mới (Đổi MACN) đồng thời cập nhật trạng thái xóa của nhân viên đó ở chi nhánh cũ là 1.
2. **Khách hàng:** Cập nhật thông tin khách hàng.
3. **Mở tài khoản cho khách hàng:** Thiết kế theo Subform, trong đó form chính là thông tin khách hàng, form phụ (grid) liệt kê các tài khoản khách hàng đó đã mở. Cho phép mở thêm tài khoản mới (tự động sinh số tài khoản).
4. **Gởi tiền / Rút tiền:** Lập phiếu giao dịch. Số tiền gửi / rút lớn hơn 100.000đ. Phải kiểm tra tài khoản hợp lệ và số dư trước khi cho rút.
5. **Chuyển tiền:** Lập phiếu chuyển tiền nội bộ và liên chi nhánh. Bắt buộc dùng `BEGIN DISTRIBUTED TRANSACTION` để đảm bảo an toàn.

#### B. Liệt kê - Thống kê
1. **Sao kê giao dịch:** Sao kê giao dịch của 1 tài khoản trong 1 khoảng thời gian (`@tungay`, `@denngay`). Kết xuất:
    - *Số dư đến ngày @tungay - 1: 10.000.000*
    - Bảng gồm: Số dư đầu | Ngày | Loại giao dịch | Số tiền | Số dư sau
    - *Số dư tới ngày @denngay: 8.000.000*
2. **Liệt kê tài khoản:** Liệt kê các tài khoản mở trong 1 khoảng thời gian của chi nhánh, của tất cả các chi nhánh.
3. **Liệt kê khách hàng:** Liệt kê các khách hàng theo từng chi nhánh, trong từng chi nhánh thì in tăng dần theo họ tên.

#### C. Quản trị
Chương trình có 3 nhóm: **NganHang, ChiNhanh, KhachHang**.
- **Nếu login thuộc nhóm NganHang:** có thể chọn bất kỳ chi nhánh nào để xem các báo cáo bằng cách chọn tên chi nhánh, và tìm dữ liệu trên phân mảnh tương ứng. Nhóm này được tạo tài khoản mới cùng nhóm.
- **Nếu login thuộc nhóm ChiNhanh:** chỉ cho phép toàn quyền làm việc trên chi nhánh đã đăng nhập. Nhóm này được tạo tài khoản mới cùng nhóm.
- **Nếu login thuộc nhóm KhachHang:** chỉ được quyền xem các sao kê giao dịch của chính tài khoản của mình. Không được quyền tạo tài khoản mới.
