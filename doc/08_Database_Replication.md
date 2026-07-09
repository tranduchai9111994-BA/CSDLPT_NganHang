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
- Dữ liệu ở các bảng `KhachHang`, `NhanVien`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN` chỉ chứa các dòng có mã chi nhánh là Bến Thành — áp dụng **phân mảnh ngang (horizontal fragmentation)** nhất quán theo `MACN`.
- Bảng `ChiNhanh` được nhân bản toàn vẹn (Replicated entirely) vì là danh mục tham chiếu chỉ đọc, cần thiết cho mọi site.

### 2.2. Phân mảnh 2: Chi nhánh Tân Định (SQL2)
- **Điều kiện Lọc (Filter):** `MACN = 'TANDINH'`
- Tương tự SQL1, phân mảnh này chỉ chứa các dòng dữ liệu mà trường MACN là 'TANDINH' cho tất cả các bảng nghiệp vụ (bao gồm `TaiKhoan`).

### 2.3. Phân mảnh 3: Trạm Tra Cứu (SQL3)
- **Chức năng:** Phục vụ nhóm quyền `NganHang` để xem báo cáo toàn hệ thống hoặc tra cứu khách hàng nhanh mà không làm ảnh hưởng đến hiệu năng (Performance) của các máy chủ đang xử lý giao dịch.
- **Cấu hình:** Phân mảnh này KHÔNG phải là Full Copy của Publisher. Nó **chỉ Replicate Full bảng `KhachHang`** của toàn hệ thống để tối ưu hóa việc tra cứu. Các bảng giao dịch không cần replicate sang đây vì nhóm Ngân Hàng có thể dùng Linked Server gọi ngược lên `NGUON` hoặc chéo sang các mảnh để xem báo cáo.

> ✅ **[Hiệu chỉnh 30/06/2026]** Xác nhận chính thức: bảng `TaiKhoan` được **nhân bản toàn vẹn (Replicate Full)** — giống bảng `ChiNhanh`. Mỗi site có đầy đủ toàn bộ tài khoản của cả 2 chi nhánh, phục vụ kiểm tra nhanh khi chuyển tiền. Quy tắc: **ĐỌC local, GHI qua Linked Server nếu TK thuộc chi nhánh khác** (phân biệt bằng MACN).

**Quy tắc đọc/ghi dữ liệu cho bảng nhân bản toàn vẹn (`ChiNhanh`):**
- **Đọc (SELECT):** Đọc trực tiếp tại local (Subscriber) để tăng tốc độ truy vấn, không cần qua Linked Server.
- **Ghi (INSERT/UPDATE/DELETE):** Chỉ thao tác qua Publisher (NGUON qua `LINK0`). TUYỆT ĐỐI không ghi trực tiếp lên bản nhân bản tại Subscriber vì sẽ bị Replication ghi đè ở chu kỳ đồng bộ kế tiếp.

**Quy tắc đọc/ghi cho `TaiKhoan` (nhân bản toàn vẹn):**
- **Đọc (SELECT):** Đọc trực tiếp tại local — mọi TK đều có bản copy local, không cần Linked Server.
- **Ghi (UPDATE số dư):** Chỉ GHI trực tiếp nếu TK có `MACN` = chi nhánh hiện tại (TK "của mình"). Nếu TK thuộc chi nhánh đối tác → bắt buộc GHI qua `[LINK1]` (Linked Server) để cập nhật tại site chủ sở hữu. SP `sp_ChuyenTien` phân biệt bằng cột `MACN`, kích hoạt `BEGIN DISTRIBUTED TRANSACTION` khi cần.

**[Cập nhật Login Management] Bảng Quản Trị Hệ Thống (`QuanTriLogin`):**
- Bảng này là một ngoại lệ. Nó tồn tại giống nhau trên mọi mảnh (SQL1, SQL2, SQL3) nhưng **KHÔNG tham gia vào Replication**. 
- Dữ liệu mật khẩu lưu trên bảng này là cục bộ của từng instance, không cần và không được đồng bộ chéo giữa các site để tuân thủ nguyên tắc thiết kế phân tán của đề bài (Login/User là tài nguyên Server-level, không tự đồng bộ).

## 3. Cấu hình Publication & Subscriptions

Sau khi chuẩn bị xong, tiến hành cấu hình Merge Replication theo mô hình Publisher - Subscriber.

### 3.1. Article cấu hình cho từng Publication [Hiệu chỉnh 30/06/2026]
Kiểu Replicate đã chọn cho Stored Procedures: **"Replicate stored procedure definitions"** (đồng bộ cấu trúc/code), KHÔNG dùng "Replicate as execution".
- **PUB_BENTHANH và PUB_TANDINH:** Bảng: 6 bảng (ChiNhanh, GD_CHUYENTIEN, GD_GOIRUT, KhachHang, NhanVien, TaiKhoan). SP: 11 SP nghiệp vụ và quản trị.
- **PUB_TRACUU:** Replicate sang SQL3 (TRACUU). Articles gồm:
  - **Bảng:** `KhachHang` (replicate full toàn bộ — không filter theo MACN)
  - **SP (replicate definition):** `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang`, `sp_LietKeTaiKhoanTheoNgay`, `sp_DanhSachTaiKhoan` — tổng 5 SP article

  TRACUU không cần các bảng giao dịch hay NhanVien/TaiKhoan vì khi cần, SP dùng Linked Server (`LINK1`→SQL1, `LINK2`→SQL2) để lấy.
  
  **[Cập nhật 05/07/2026] Lưu ý TaiKhoan:** TaiKhoan replicate full (giống ChiNhanh) → mỗi site đã có đủ TK cả 2 CN. SP trên TRACUU chỉ đọc từ **LINK1** (không UNION ALL LINK1+LINK2 vì sẽ bị duplicate). JOIN KhachHang local dùng **OUTER APPLY TOP 1** để tránh nhân bản kết quả.
  
  Các SP đặc thù cài thủ công qua `setup_db.js` / [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql) (không qua Replication):
  - `sp_SaoKeToanBo` — gộp GD_GOIRUT + GD_CHUYENTIEN từ LINK1+LINK2 (sao kê toàn hệ thống)
  - `SP_SaoKeTaiKhoan` (bản TRACUU) — gộp GD_GOIRUT + GD_CHUYENTIEN từ LINK1+LINK2 (sao kê theo 1 SOTK)
  - `sp_DanhSachNhanVien` — gộp NhanVien từ LINK1+LINK2
  - `SP_DanhSachTrangThaiLogin` — phiên bản TRACUU đọc NhanVien qua LINK, KhachHang local

> ⚠️ **Hiện trạng SSMS:** Publication `PUB_TRACUU` hiện đang check tất cả 6 bảng — cần **bỏ check** các bảng ChiNhanh, GD_CHUYENTIEN, GD_GOIRUT, NhanVien, TaiKhoan, chỉ giữ lại KhachHang. Xem hướng dẫn sửa tại mục 3.2.

### 3.1.1. Quy trình deploy SP thay đổi qua Replication (PUB_TRACUU)

SP là article trong PUB_TRACUU → **không ALTER trực tiếp trên SQL3** (bị `MSmerge_tr_alterschemasonly` chặn). Quy trình đúng:

1. Trên **NGUON (ES-HAITD16)**: `DISABLE TRIGGER [MSmerge_tr_alterschemaonly] ON DATABASE`
2. `CREATE OR ALTER PROCEDURE dbo.sp_Login_App ...` (cập nhật nội dung SP)
3. `ENABLE TRIGGER [MSmerge_tr_alterschemaonly] ON DATABASE`
4. `EXEC sp_startpublication_snapshot @publication = 'PUB_TRACUU'` — tạo snapshot mới chứa SP đã sửa
5. `EXEC sp_reinitmergesubscription @publication = 'PUB_TRACUU', @subscriber = 'ES-HAITD16\SQL3', @subscriber_db = 'NGANHANG'` — đánh dấu SQL3 cần reinit
6. SSMS → Replication Monitor → SQL3 → Start Synchronization → chờ "Applied the snapshot and merged N data change(s)"

> Trigger trên NGUON là `MSmerge_tr_alterschemaonly` (không có 's' cuối), khác với trigger trên SQL3 là `MSmerge_tr_alterschemasonly`. Dùng đúng tên khi DISABLE/ENABLE.

### 3.2. Hướng dẫn sửa PUB_TRACUU trên SSMS (bỏ article thừa)

**Bước 1:** Trên NGUON (`ES-HAITD16`), mở SSMS → Replication → Local Publications → chuột phải `PUB_TRACUU` → **Properties**.

**Bước 2:** Chọn trang **Articles** (bên trái).

**Bước 3:** Bỏ check tất cả bảng **trừ `KhachHang`**:
- ❌ ChiNhanh → bỏ check
- ❌ GD_CHUYENTIEN → bỏ check
- ❌ GD_GOIRUT → bỏ check
- ✅ **KhachHang → giữ check**
- ❌ NhanVien → bỏ check
- ❌ TaiKhoan → bỏ check

**Stored Procedures** (giữ 2 SP bắt buộc, bỏ phần còn lại):
- ✅ **sp_Login_App → giữ check** (admin đăng nhập vào TRACUU cần SP này)
- ✅ **SP_TaoTaiKhoan → giữ check** (tạo tài khoản trên TRACUU cần SP này)
- ❌ Các SP còn lại → bỏ check (SP đặc thù TRACUU cài thủ công qua `setup_db.js`)

**Bước 4:** Bấm OK → SSMS sẽ cảnh báo "Removing articles..." → xác nhận.

**Bước 5:** Tạo Snapshot mới: chuột phải `PUB_TRACUU` → **Start Snapshot Agent** để đẩy snapshot chỉ có KhachHang xuống SQL3.

**Bước 6:** Kiểm tra trên SQL3 (TRACUU): chỉ còn bảng `KhachHang` có dữ liệu. Các bảng khác (nếu đã sync trước đó) có thể vẫn tồn tại nhưng không còn được Replication đồng bộ — có thể DROP thủ công nếu muốn dọn sạch.

> ⚠️ **Lưu ý:** Sau khi bỏ article, nếu SQL3 đã có dữ liệu ở các bảng bị bỏ, dữ liệu đó sẽ không tự xóa (Replication chỉ ngưng đồng bộ). Xóa thủ công bằng `DROP TABLE` nếu cần.

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
