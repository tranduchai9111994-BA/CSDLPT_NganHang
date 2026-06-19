# 🔗 Mô Tả Mạng Lưới Linked Servers (CSDL Phân Tán)

Trong đề tài CSDL Phân Tán, các Server (hay còn gọi là các mảnh - Fragments) giao tiếp với nhau thông qua cơ chế **Linked Server** của SQL Server. Dưới đây là sơ đồ cấu hình các Linked Server đã được tạo tại từng Site.

## 1. Cấu Hình Tên Máy Chủ (Instance)
Hệ thống gồm 4 máy chủ (Instances) đặt trên cùng một máy thật (hoặc máy ảo) có tên là `ES-HAITD16`:
- **Máy Chủ Gốc (Publisher/Distributor):** `ES-HAITD16` (thường gọi là mảnh NGUON)
- **Mảnh 1 (Subscriber 1):** `ES-HAITD16\SQL1` (Chi nhánh Bến Thành)
- **Mảnh 2 (Subscriber 2):** `ES-HAITD16\SQL2` (Chi nhánh Tân Định)
- **Mảnh 3 (Subscriber 3):** `ES-HAITD16\SQL3` (Phân mảnh Tra Cứu)

## 2. Chi Tiết Linked Server Từng Site

Quy tắc bất di bất dịch trong bài CSDLPT: **`LINK1` luôn luôn là "Chi nhánh đối tác"**. Tuyệt đối không dùng cấu hình loopback (trỏ về chính nó) vì nó làm sai lệch logic query phân tán và là điểm trừ nặng khi vấn đáp.

### 2.1. Tại Site Gốc (`NGUON` - `ES-HAITD16`)
Chứa dữ liệu toàn cục. Không dành cho người dùng nghiệp vụ đăng nhập, nhưng vẫn thiết lập Linked Server xuống cả 3 Site:
- `LINK1` ➔ Trỏ đến `ES-HAITD16\SQL1` (Bến Thành)
- `LINK2` ➔ Trỏ đến `ES-HAITD16\SQL2` (Tân Định)
- `LINK3` ➔ Trỏ đến `ES-HAITD16\SQL3` (Tra cứu)
**Lý do NGUON có Linked Server:** Dù nhân viên không login vào NGUON, nhưng DBA (Quản trị viên) hoặc Developer cần đứng tại NGUON để chạy các query kiểm tra trạng thái đồng bộ, đối chiếu dữ liệu giữa Gốc và các Mảnh (Ví dụ: `SELECT * FROM KhachHang EXCEPT SELECT * FROM [LINK1]...`) hoặc để bảo trì hệ thống tập trung.

### 2.2. Tại Mảnh 1 (`SQL1` - Chi Nhánh Bến Thành)
Thực hiện nghiệp vụ tại Bến Thành. Để thực hiện giao dịch liên chi nhánh (chuyển tiền sang Tân Định hoặc tra cứu khách hàng bên đó), sử dụng:
- `LINK0` ➔ Trỏ về máy chủ gốc (`ES-HAITD16`)
- **`LINK1`** ➔ Trỏ thẳng đến **Mảnh Tân Định (`ES-HAITD16\SQL2`)** (Chi nhánh đối tác).

### 2.3. Tại Mảnh 2 (`SQL2` - Chi Nhánh Tân Định)
Thực hiện nghiệp vụ tại Tân Định. Tương tự như SQL1, nhưng đối tác bị đảo ngược:
- `LINK0` ➔ Trỏ về máy chủ gốc (`ES-HAITD16`)
- **`LINK1`** ➔ Trỏ thẳng đến **Mảnh Bến Thành (`ES-HAITD16\SQL1`)** (Chi nhánh đối tác).

### 2.4. Tại Mảnh 3 (`SQL3` - Phân Mảnh Tra Cứu)
Dùng riêng cho nhóm `NganHang` (Ban Giám Đốc) để query dữ liệu tổng hợp. 
- `LINK0` ➔ Trỏ về máy chủ gốc (`ES-HAITD16`)
- `LINK1` ➔ Trỏ đến mảnh Bến Thành (`ES-HAITD16\SQL1`)
- `LINK2` ➔ Trỏ đến mảnh Tân Định (`ES-HAITD16\SQL2`)

---

## 3. Ứng Dụng Trong Mã Nguồn

Trong Stored Procedure (Ví dụ: `sp_ChuyenTien`), Linked Server được sử dụng dưới dạng cú pháp 4 thành phần:
```sql
SELECT * FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = '...'
```
Hoặc dùng để thực thi Stored Procedure từ xa qua cơ chế RPC (Remote Procedure Call):
```sql
EXEC [LINK2].NGANHANG.dbo.sp_TangSoDu @SOTK, @SOTIEN
```
Để những lệnh này hoạt động thành công, dịch vụ **MSDTC** (Microsoft Distributed Transaction Coordinator) trên môi trường Windows Server phải được cấu hình và bật trạng thái Running ở tất cả các node tham gia.

---

## 4. (MỚI) Security Mapping — Login dùng để xác thực qua Linked Server

Đây là phần cấu hình **dễ bị bỏ sót nhất** khi setup nhiều SQL Server instance, vì nó không nằm trong phạm vi Replication.

### 4.1. Nguyên tắc cốt lõi
Mỗi Linked Server, khi được gọi, cần xác thực bằng một **Login cụ thể tại server đích**. Hệ thống dùng chung tài khoản SQL Login **`HTKN`** (xem `database_connection.md`) làm credential cho ứng dụng và cho cả Linked Server.

> ⚠️ Login là đối tượng **cấp Server (instance-level)**, KHÔNG được Replication đồng bộ (Replication chỉ đồng bộ đối tượng cấp Database). Do đó **`HTKN` phải được tạo thủ công, độc lập, trên TỪNG SQL Server instance** (NGUON, SQL1, SQL2, SQL3), kể cả khi 4 instance này dùng chung 1 database `NGANHANG` được Replicate.

### 4.2. Cấu hình mapping cần kiểm tra cho từng Linked Server
Mỗi Linked Server cần được khai báo Security Mapping trỏ đúng `HTKN` ở đầu server đích:

```sql
-- Ví dụ: cấu hình LINK1 tại SQL3 (trỏ tới BENTHANH/SQL1)
EXEC sp_addlinkedsrvlogin
    @rmtsrvname  = N'LINK1',
    @useself     = N'False',
    @locallogin  = NULL,                 -- NULL = áp dụng cho mọi login cục bộ
    @rmtuser     = N'HTKN',
    @rmtpassword = N'123';               -- Mật khẩu chuẩn của HTKN trên toàn hệ thống
```

Bảng tổng hợp các Linked Server cần cấu hình Security Mapping với `HTKN`:

| Server đứng | Linked Server | Trỏ tới | Login remote cần có |
|---|---|---|---|
| NGUON | LINK1 | SQL1 (BENTHANH) | `HTKN` phải tồn tại trên SQL1 |
| NGUON | LINK2 | SQL2 (TANDINH) | `HTKN` phải tồn tại trên SQL2 |
| NGUON | LINK3 | SQL3 (TRACUU) | `HTKN` phải tồn tại trên SQL3 |
| SQL1 (BENTHANH) | LINK1 | SQL2 (TANDINH) | `HTKN` phải tồn tại trên SQL2 |
| SQL2 (TANDINH) | LINK1 | SQL1 (BENTHANH) | `HTKN` phải tồn tại trên SQL1 |
| SQL3 (TRACUU) | LINK1 | SQL1 (BENTHANH) | `HTKN` phải tồn tại trên SQL1 |
| SQL3 (TRACUU) | LINK2 | SQL2 (TANDINH) | `HTKN` phải tồn tại trên SQL2 |

### 4.3. Quy trình chẩn đoán khi gặp lỗi `Login failed for user 'HTKN'`
Chi tiết đầy đủ xem tại file `Su_Co_Va_Xu_Ly.md`. Tóm tắt 3 bước:
1. Test trực tiếp `SELECT TOP 1 * FROM [LINKx].NGANHANG.dbo.TaiKhoan;` để xác nhận lỗi nằm ở Linked Server.
2. Kiểm tra `HTKN` có tồn tại + đang bật **trên server đích** (không phải server đang đứng):
   ```sql
   SELECT name, is_disabled FROM sys.server_principals WHERE name = 'HTKN';
   ```
3. Cập nhật lại `sp_addlinkedsrvlogin` với đúng mật khẩu nếu Login đã tồn tại nhưng vẫn lỗi (khả năng cao là sai mật khẩu trong mapping).