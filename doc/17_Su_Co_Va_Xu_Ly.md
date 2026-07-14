# 🛠️ Nhật Ký Sự Cố & Cách Xử Lý (Troubleshooting Log)

Tài liệu này ghi lại các sự cố thực tế gặp phải trong quá trình triển khai và chuẩn hoá Stored Procedure trên mô hình 4 SQL Server instance, cùng nguyên nhân gốc rễ và cách xử lý. Dùng để ôn tập vấn đáp vì đây là những câu hỏi rất hay bị hỏi xoáy.

---

## Sự cố 1: Không `DROP` được Stored Procedure cũ tại Subscriber

**Triệu chứng:**
```
Msg 3724, Level 16, State 2
Cannot drop the procedure 'dbo.SP_DangNhap' because it is being used for replication.
```
Xảy ra khi chạy `DROP PROCEDURE dbo.SP_DangNhap` tại server **TANDINH (SQL2)**.

**Nguyên nhân gốc rễ:**
Thường là do SP đã được đăng ký làm một **Article** trong Publication tại site NGUON (Publisher). SQL Server Replication khoá quyền `DROP`/`ALTER` trực tiếp lên đối tượng này tại các Subscriber, để tránh làm lệch pha cấu trúc giữa Publisher và Subscriber.

**Cách xử lý đã chọn:**
**[Cập nhật 19/06/2026]**: Trước khi kết luận bị khoá do Replication, đã kiểm tra lại bằng lệnh `sp_helparticle` trên cả 3 Publication (PUB_BENTHANH, PUB_TANDINH, PUB_TRACUU). Kết quả xác nhận `SP_DangNhap` KHÔNG nằm trong Article của bất kỳ Publication nào. Nó chỉ là SP rác còn sót lại. Do đó, đã xoá được trực tiếp bằng lệnh `DROP PROCEDURE IF EXISTS SP_DangNhap;` mà không gặp lỗi khoá DDL, không cần qua bước `sp_droparticle`.

**Cách xử lý (nếu thực sự là Article):**
Phải gỡ Article ra khỏi Publication tại NGUON trước:
```sql
-- Chạy tại NGUON (Publisher)
EXEC sp_dropsubscription
    @publication = N'TenPublication',
    @article = N'SP_DangNhap',
    @subscriber = N'ALL';
GO
EXEC sp_droparticle
    @publication = N'TenPublication',
    @article = N'SP_DangNhap';
GO
EXEC sp_startpublication_snapshot @publication = N'TenPublication';
```

---

## Sự cố 2: Không `CREATE OR ALTER` được SP tại Subscriber (lỗi DDL)

**Triệu chứng:**
```
Msg 21531, Level 16, State 1
The data definition language (DDL) command cannot be executed at the Subscriber.
In a republishing hierarchy, DDL commands can only be executed at the root Publisher,
not at any of the republishing Subscribers.

Msg 21530, Level 16, State 1
The schema change failed during execution of an internal replication procedure.

Msg 3609, Level 16, State 2
The transaction ended in the trigger. The batch has been aborted.
```
Xảy ra khi chạy `CREATE OR ALTER PROCEDURE dbo.sp_Login_App` và `dbo.SP_TaoTaiKhoan` tại server **TRACUU (SQL3)**.

**Nguyên nhân gốc rễ:**
Cùng bản chất với Sự cố 1, nhưng lần này là lệnh `ALTER` (không phải `DROP`). Cả 2 SP này đã thuộc Publication. Replication chặn **mọi lệnh DDL** (`CREATE`, `ALTER`, `DROP`) lên các đối tượng đã đăng ký Article, tại bất kỳ Subscriber nào — kể cả trong mô hình republishing nhiều tầng.

**Cách xử lý đã chọn:**
Không `ALTER` lại 2 SP này tại TRACUU — giữ nguyên bản đã được Replicate sẵn từ NGUON. Việc chuẩn hoá tại TRACUU chỉ tập trung vào các SP đọc/báo cáo **chưa từng được đưa vào Publication** (`SP_SaoKeTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay`, `sp_LietKeKhachHang`) — các SP này tạo mới hoàn toàn nên không bị khoá.

**Bài học rút ra (quan trọng cho vấn đáp):**
> Bất kỳ SP nào đã là Article trong Publication thì **chỉ được sửa tại Publisher (NGUON)**. Muốn sửa nội dung `sp_Login_App` hay `SP_TaoTaiKhoan`, phải làm tại NGUON rồi để Replication tự đẩy xuống toàn bộ Subscriber.

---

## Sự cố 3: `Login failed for user 'HTKN'` khi gọi Linked Server

**Triệu chứng:**
```
Msg 18456, Level 14, State 1
Login failed for user 'HTKN'.
```
Xảy ra khi chạy `SELECT TOP 1 * FROM [LINK1].NGANHANG.dbo.TaiKhoan;` hoặc `[LINK2]...` tại server **TRACUU (SQL3)**, dù đã xác nhận Login `HTKN` **tồn tại và đang bật (`is_disabled = 0`)** ngay trên chính SQL3.

**Nguyên nhân gốc rễ (điểm dễ nhầm lẫn nhất):**
`HTKN` là Login cấp **Server (instance-level)** — đây chính là tài khoản SQL mà ứng dụng Node.js dùng để kết nối CSDL (xem `database_connection.md`, mật khẩu mặc định `123`).

Login là đối tượng cấp Server, **KHÔNG nằm trong phạm vi đồng bộ của Replication** (Replication chỉ đồng bộ đối tượng cấp Database: bảng, SP, dữ liệu). Vì vậy:
- `HTKN` tồn tại trên SQL3 không có nghĩa là nó cũng tồn tại trên SQL1, SQL2.
- Khi SQL3 gọi sang `[LINK1]` (trỏ tới BENTHANH/SQL1), nó cần xác thực **HTKN ở phía SQL1**, không phải ở SQL3.
- Nếu `HTKN` chưa tồn tại / bị khoá / sai mật khẩu ở đầu SQL1 (hoặc sai mật khẩu trong cấu hình Security Mapping của chính Linked Server `LINK1` tại SQL3) → lỗi `Login failed`, dù SQL3 hoàn toàn không có vấn đề gì.

**Quy trình chẩn đoán đã áp dụng:**
1. Kiểm tra Login `HTKN` trên server **đích** (nơi Linked Server trỏ tới), không phải server đang đứng:
   ```sql
   SELECT name, type_desc, is_disabled
   FROM sys.server_principals
   WHERE name = 'HTKN';
   ```
2. Kiểm tra cấu hình mapping của Linked Server:
   ```sql
   SELECT
       s.name AS LinkedServerName,
       l.loginname AS LocalLogin,
       l.remote_name AS RemoteLoginDuocDung,
       l.uses_self_credential,
       s.is_remote_login_enabled
   FROM sys.servers s
   LEFT JOIN sys.linked_logins l ON s.server_id = l.server_id
   WHERE s.is_linked = 1;
   ```
3. Test trực tiếp bằng `SELECT TOP 1 * FROM [LINKx]...` để xác nhận lỗi nằm ở tầng Linked Server, không phải ở nội dung Stored Procedure.

**Cách xử lý đã áp dụng (cho LINK1 → BENTHANH):**
Xác nhận `HTKN` đã tồn tại sẵn trên SQL1 → vấn đề chỉ là cấu hình mapping → sửa lại bằng:
```sql
-- Chạy tại SQL3 (nơi khai báo LINK1)
EXEC sp_addlinkedsrvlogin
    @rmtsrvname  = N'LINK1',
    @useself     = N'False',
    @locallogin  = NULL,
    @rmtuser     = N'HTKN',
    @rmtpassword = N'<mật khẩu đúng của HTKN trên SQL1>';
```
→ **Kết quả: LINK1 chạy OK.**

**Cách xử lý cho LINK2 → TANDINH:**
Lặp lại đúng quy trình 3 bước ở trên, áp dụng cho SQL2 và `LINK2`. Vì Login là đối tượng cấp Server độc lập theo từng instance, bước kiểm tra/tạo Login phải lặp lại cho TỪNG cặp Linked Server, không thể suy ra từ kết quả của LINK1.

**Bài học rút ra (rất hay bị hỏi vấn đáp):**
> Trong mô hình nhiều SQL Server instance, có **3 thứ cần đồng bộ riêng biệt, theo 3 cơ chế khác nhau**:
> | Loại đối tượng | Cấp độ | Cơ chế đồng bộ |
> |---|---|---|
> | Dữ liệu (data rows) | Database | Replication (tự động) |
> | Stored Procedure (cấu trúc) | Database | Replication nếu được đưa vào Article (tự động), hoặc chạy tay |
> | Login | **Server (instance)** | **KHÔNG có cơ chế tự động** — luôn phải tạo tay ở từng instance |

---

## Tổng kết quy trình chẩn đoán lỗi Linked Server (dùng lại cho lần sau)

Khi gặp `Login failed` hoặc bất kỳ lỗi liên quan `[LINKx]`, làm theo đúng thứ tự:

1. Test trực tiếp `SELECT TOP 1 * FROM [LINKx].NGANHANG.dbo.<TenBang>;` để cô lập lỗi — xác nhận lỗi nằm ở Linked Server, không phải ở SP gọi nó.
2. Kiểm tra Login tồn tại + đang bật ở **server đích** mà Linked Server đó trỏ tới (không phải server đang đứng).
3. Kiểm tra cấu hình mapping (`sys.servers` + `sys.linked_logins`) xem đang dùng login nào, chế độ `uses_self_credential` hay mapping cụ thể.
4. Cập nhật lại bằng `sp_addlinkedsrvlogin` với đúng mật khẩu hiện tại.
5. Lặp lại cho từng Linked Server riêng biệt (LINK1, LINK2...) — không suy luận lỗi đã hết chỉ vì 1 cái đã chạy được.

---

## Sự cố 4: Lỗi `MSDTC on server is unavailable` hoặc lệnh bị treo khi chạy `SP_ChuyenNhanVien` qua Node.js

**Triệu chứng:**
Gọi thủ tục `SP_ChuyenNhanVien` bằng Node.js (thư viện `mssql` dùng `tedious`) bị lỗi, dù gọi trên SSMS thì chạy tốt. Thường báo lỗi không hỗ trợ Distributed Transaction.

**Nguyên nhân gốc rễ:**
Thư viện `tedious` (driver phổ biến nhất cho Node.js kết nối SQL Server) **không hỗ trợ** các giao dịch phân tán (Distributed Transactions) qua MSDTC (Microsoft Distributed Transaction Coordinator). Do `SP_ChuyenNhanVien` sử dụng lệnh `BEGIN DISTRIBUTED TRANSACTION`, nó đòi hỏi client driver cũng phải hỗ trợ cơ chế two-phase commit này.

**Cách xử lý đã áp dụng:**
Thay vì dùng thư viện `mssql` thông thường, hệ thống đã dùng một giải pháp Workaround: **Gọi công cụ dòng lệnh `sqlcmd` của Windows (Native Client)** bằng hàm `execFile` trong `child_process` của Node.js.
`sqlcmd` dùng Native Client hoặc ODBC driver, hỗ trợ đầy đủ MSDTC.

```javascript
// db.js (Hàm execSPAdmin)
execFile('sqlcmd', [
  '-S', serverAddr,
  '-d', 'NGANHANG',
  '-U', 'HTKN',
  '-P', '123',
  '-Q', query,
  '-b'   // exit với error code nếu SQL lỗi
], ...)
```

**Bài học rút ra:**
> Khi thiết kế hệ thống CSDL Phân Tán, nếu bắt buộc phải dùng `BEGIN DISTRIBUTED TRANSACTION` trong Stored Procedure, cần đảm bảo Driver của ngôn ngữ lập trình phía Backend (Node.js, Java, .NET) hỗ trợ MSDTC. Nếu không, phải dùng cách bọc tiến trình hoặc gọi Native driver.

---

## Sự cố 5: MANV trùng giữa 2 chi nhánh khi chuyển nhân viên

**Triệu chứng:**
Nhân viên `NV01` tồn tại ở cả BENTHANH (SQL1) và TANDINH (SQL2). Khi chuyển nhân viên từ chi nhánh này sang chi nhánh kia, SP_ChuyenNhanVien INSERT thẳng MANV cũ vào chi nhánh đích → lỗi `UNIQUE KEY violation` hoặc ghi đè nhân viên sai.

**Nguyên nhân gốc rễ:**
MANV ban đầu (`NV01`, `NV02`...) không mang thông tin chi nhánh. 2 chi nhánh độc lập đều sinh MANV từ 1, dẫn đến không gian MANV trùng nhau hoàn toàn.

**Cách xử lý đã áp dụng:**
Triển khai hệ thống **prefix MANV theo chi nhánh**:
- BENTHANH: `BT001`, `BT002`, `BT003`...
- TANDINH: `TD001`, `TD002`, `TD003`, `TD004`...

Migration 3 bước:
1. Chạy `sql/setup/migrate_manv_benthanh.sql` trên SQL1 → đổi NV01→BT001, NV02→BT002, NV03→BT003; đổi tên SQL Login tương ứng.
2. Chạy `sql/setup/migrate_manv_tandinh.sql` trên SQL2 → đổi NV01→TD001... NV04→TD004; đổi tên SQL Login.
3. Chạy `sql/setup/migrate_quantrilogin.sql` trên cả 3 server → xóa record `QuanTriLogin` kiểu cũ (`NV01_BT`, `NV02_TD`...), INSERT lại với `LoginName = MANV mới`.

SP_ChuyenNhanVien cũng được cập nhật: khi chuyển sang chi nhánh đích, sinh MANV mới với prefix của chi nhánh đó (không sao chép MANV cũ).

**Bài học rút ra:**
> Trong mô hình phân mảnh ngang theo chi nhánh, các khóa chính (PK) tự sinh phải mang thông tin phân mảnh (prefix/suffix) để đảm bảo tính duy nhất toàn cục. Không nên để các mảnh độc lập tự sinh PK từ 1.

---

## Sự cố 10: Dữ liệu TaiKhoan bị duplicate x2 trên TRACUU [05/07/2026]

**Triệu chứng:**
Trang "Liệt kê tài khoản" và dropdown "Sao kê giao dịch" trên TRACUU hiển thị mỗi tài khoản 2 lần. Form Liệt kê TK: 14 dòng thay vì 7. Dropdown sao kê: mỗi SOTK xuất hiện 2 lần.

**Nguyên nhân gốc rễ:**
Bảng `TaiKhoan` được **replicate full** (giống `ChiNhanh`) — mỗi site (SQL1, SQL2) đã có đầy đủ TK của cả 2 chi nhánh. SP trên TRACUU dùng `UNION ALL [LINK1]...TaiKhoan + [LINK2]...TaiKhoan` → mỗi TK xuất hiện đúng 2 lần (1 từ LINK1, 1 từ LINK2).

Đây KHÔNG phải duplicate trong database (GROUP BY HAVING COUNT>1 = 0 rows), mà là do logic UNION ALL sai.

Lưu ý: GD_GOIRUT, GD_CHUYENTIEN, NhanVien **KHÔNG** replicate full (phân mảnh ngang theo MACN) → UNION ALL LINK1+LINK2 vẫn đúng cho các bảng này.

**Cách xử lý đã áp dụng:**
1. Sửa `sp_DanhSachTaiKhoan` và `sp_LietKeTaiKhoanTheoNgay`: bỏ UNION ALL, chỉ đọc từ `[LINK1].NGANHANG.dbo.TaiKhoan` (LINK1 đã có đủ data).
2. Đổi `LEFT JOIN KhachHang` thành `OUTER APPLY (SELECT TOP 1 ...)` để tránh nhân bản do KhachHang có thể có nhiều row cùng CMND.
3. Route `baocao.js` sao kê GET/POST: thay `UNION ALL LINK1+LINK2` bằng `SELECT DISTINCT ... FROM [LINK1]...TaiKhoan` khi server=TRACUU.
4. Restart app để clear connection pool cache (pool cũ cache kết quả UNION ALL cũ).

**Sự cố phụ — Login failed for TD001 trên TRACUU:**
Route ban đầu gọi `sp_LietKeTaiKhoanTheoNgay` trên TRACUU cho mọi user. Nhưng TD001 (ChiNhanh) không có login trên SQL3 → lỗi `Login failed for user 'TD001'`. Fix: chỉ NganHang (admin) gọi SP trên TRACUU; ChiNhanh query TaiKhoan local trực tiếp.

**Bài học rút ra:**
> Trước khi dùng UNION ALL qua Linked Server, phải xác nhận bảng có thực sự phân mảnh ngang hay đã replicate full. Bảng replicate full chỉ cần đọc từ 1 LINK — UNION ALL sẽ gây duplicate. Dùng `OUTER APPLY TOP 1` thay vì `LEFT JOIN` khi JOIN có thể trả nhiều row cùng key.

---

## Sự cố 7: PUB_TRACUU subscription hỏng sau khi bỏ article [30/06/2026]

**Triệu chứng:**
Sau khi sửa PUB_TRACUU (bỏ 5 article, chỉ giữ KhachHang), Merge Agent báo lỗi:
```
The publication 'PUB_TRACUU' does not exist. (Error 20026)
The subscription to publication 'PUB_TRACUU' could not be verified. (MSSQL_REPL-2147201019)
Login failed for user 'NT AUTHORITY\SYSTEM'. (Error 18456)
```

**Nguyên nhân gốc rễ:**
1. Subscription metadata trên SQL3 bị lệch với Publication mới trên NGUON sau khi thay đổi article.
2. Merge Agent chạy dưới account `NT AUTHORITY\SYSTEM` nhưng account này không có quyền truy cập database `NGANHANG` trên SQL3.
3. Các bảng cũ (NhanVien, TaiKhoan, GD_GOIRUT, GD_CHUYENTIEN, ChiNhanh) vẫn tồn tại trên SQL3 dù không còn replicate — Replication chỉ ngưng đồng bộ, không tự xóa bảng.

**Cách xử lý đã áp dụng (5 bước):**

1. **SQL3:** Dọn metadata cũ:
```sql
EXEC sp_removedbreplication @dbname = 'NGANHANG', @type = 'merge';
```

2. **SQL3:** DROP bảng thừa (FK phải xóa trước):
```sql
DROP TABLE IF EXISTS dbo.GD_CHUYENTIEN, dbo.GD_GOIRUT, dbo.NhanVien, dbo.TaiKhoan;
-- ChiNhanh bị FK_KhachHang_ChiNhanh giữ → xóa FK trước
ALTER TABLE KhachHang DROP CONSTRAINT FK_KhachHang_ChiNhanh;
DROP TABLE dbo.ChiNhanh;
```

3. **SQL3:** Cấp quyền cho Merge Agent:
```sql
CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS;
CREATE USER [NT AUTHORITY\SYSTEM] FOR LOGIN [NT AUTHORITY\SYSTEM];
ALTER ROLE db_owner ADD MEMBER [NT AUTHORITY\SYSTEM];
```

4. **NGUON:** Tạo lại subscription (Push):
```sql
EXEC sp_addmergesubscription
    @publication = 'PUB_TRACUU',
    @subscriber = 'ES-HAITD16\SQL3',
    @subscriber_db = 'NGANHANG',
    @subscription_type = 'Push';
```

5. **NGUON:** Start Snapshot Agent + Start Merge Agent Job:
```sql
EXEC msdb.dbo.sp_start_job @job_name = 'ES-HAITD16-NGANHANG-PUB_TRACUU-ES-HAITD16\SQL3-4';
```

6. **SQL3:** Deploy lại SP đặc thù TRACUU (bị xóa bởi `sp_removedbreplication`):
```sql
-- Chạy sql/deploy_tracuu.sql
```

**Kết quả:** SQL3 chỉ còn 2 bảng: `KhachHang` (replicate từ NGUON) + `QuanTriLogin` (local). Mọi dữ liệu NhanVien/TaiKhoan/GD được đọc qua Linked Server bằng SP đặc thù.

**Bài học rút ra:**
> Khi thay đổi article trong Publication (thêm/bỏ bảng), subscription có thể bị lệch metadata. Quy trình an toàn: (1) xóa subscription cũ, (2) sửa publication, (3) tạo snapshot mới, (4) tạo lại subscription. Ngoài ra, Merge Agent chạy dưới service account cần có quyền trên database của Subscriber.

---

## Sự cố 8: `sp_Login_App` crash trên TRACUU — "Invalid object name 'NhanVien'"

**Triệu chứng:**
```
Lỗi hệ thống: Invalid object name 'NhanVien'.
```
Admin (`admin`/`1`) không thể đăng nhập vào chi nhánh `TRACUU`.

**Nguyên nhân gốc rễ:**
`sp_Login_App` query `FROM NhanVien` và `FROM ChiNhanh` — 2 bảng này không tồn tại trên SQL3 (TRACUU chỉ có `KhachHang` + `QuanTriLogin`). SP crash ngay khi được gọi từ SQL3.

**Cách xử lý đã áp dụng:**
Thêm `OBJECT_ID` guard vào SP:
```sql
IF OBJECT_ID('dbo.NhanVien', 'U') IS NOT NULL
BEGIN
    SELECT @MANV = MANV, ... FROM NhanVien WHERE ...
END

IF @MANV IS NULL AND @NHOM = 'NganHang'
BEGIN
    SET @MACN = CASE WHEN OBJECT_ID('dbo.ChiNhanh','U') IS NOT NULL
                     THEN (SELECT TOP 1 MACN FROM ChiNhanh)
                     ELSE N'TRACUU' END;
END
```

Deploy qua đúng mô hình phân tán (không ALTER trực tiếp trên Subscriber):
1. Disable `MSmerge_tr_alterschemaonly` trên **NGUON (ES-HAITD16)**: `DISABLE TRIGGER [MSmerge_tr_alterschemaonly] ON DATABASE`
2. `CREATE OR ALTER PROCEDURE sp_Login_App` với OBJECT_ID guard trên NGUON
3. Re-enable trigger
4. `sp_startpublication_snapshot @publication = 'PUB_TRACUU'` → tạo snapshot mới
5. `sp_reinitmergesubscription` → đánh dấu SQL3 reinit
6. View Synchronization Status → Start → SQL3 nhận SP mới qua replication

**Bài học rút ra:**
> SP nào là Article trong Publication thì **chỉ sửa tại Publisher (NGUON)**. Replication tự đẩy xuống Subscriber — không DDL trực tiếp trên Subscriber vì `MSmerge_tr_alterschemasonly` chặn mọi DDL.
> Khi SP phải chạy trên nhiều site có schema khác nhau, dùng `OBJECT_ID` guard để SP tự thích nghi — một bản code chạy được trên tất cả site.

---

## Sự cố 9: KhachHang không đăng nhập được sau khi admin reset password

**Triệu chứng:**
Admin reset password cho KH qua giao diện quản trị → KH thử đăng nhập vẫn bị lỗi, dù credentials đúng.

**Nguyên nhân gốc rễ:**
`reset-password` trong `routes/quantri.js` dùng `DROP LOGIN + CREATE LOGIN` (thay vì `ALTER LOGIN`) để đổi mật khẩu. Khi DROP+CREATE, SQL Server sinh **SID mới** cho login. DB User trong database vẫn còn nhưng liên kết theo SID cũ → **orphaned user** — kết nối SQL thành công nhưng không thuộc role `KhachHang` nữa → mọi SP bị từ chối.

*(Lý do dùng DROP+CREATE: `ALTER LOGIN` bị replication trigger chặn trên một số server.)*

**Cách xử lý đã áp dụng:**

*Fix code `quantri.js`*: Sau DROP+CREATE login, tự động drop + recreate DB User và gán lại role từ `QuanTriLogin.MaThamChieu` / `NhomQuyen`.

*Fix hàng loạt orphaned users* (script chạy trên từng server SQL1/SQL2/SQL3):
```sql
USE NGANHANG; SET NOCOUNT ON;
DECLARE @UserName nvarchar(128), @LoginName nvarchar(128), @RoleName nvarchar(128), @sql nvarchar(1000), @count int = 0;
DECLARE cur CURSOR FOR
    SELECT dp.name, ql.LoginName, ql.NhomQuyen
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
    JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(dp.name)
    WHERE dp.type = 'S' AND dp.principal_id > 4 AND sp.name IS NULL;
OPEN cur; FETCH NEXT FROM cur INTO @UserName, @LoginName, @RoleName;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LoginName)
    BEGIN
        EXEC sp_executesql N'DROP USER [' + REPLACE(@UserName,']',']]') + N']';
        EXEC sp_executesql N'CREATE USER [' + REPLACE(@UserName,']',']]') + N'] FOR LOGIN [' + REPLACE(@LoginName,']',']]') + N']';
        EXEC sp_executesql N'EXEC sp_addrolemember ''' + REPLACE(@RoleName,'''','''''') + N''', [' + REPLACE(@UserName,']',']]') + N']';
        SET @count += 1; PRINT '✓ Fixed: ' + @UserName;
    END
    FETCH NEXT FROM cur INTO @UserName, @LoginName, @RoleName;
END
CLOSE cur; DEALLOCATE cur;
PRINT '--- Hoàn thành: ' + CAST(@count AS varchar) + ' orphaned user(s) ---';
```

**Bài học rút ra:**
> `DROP LOGIN + CREATE LOGIN` đổi SID → DB User bị orphaned. Luôn re-link DB User sau khi recreate login. Script fix hàng loạt dựa vào bảng `QuanTriLogin` — đây là lý do bảng này phải được cập nhật đầy đủ khi tạo tài khoản.

---

## Sự cố 11: Lỗi "session is in the kill state" khi mở tài khoản [14/07/2026]

**Triệu chứng:**
```
Cannot continue the execution because the session is in the kill state.
```
Xảy ra khi nhân viên ChiNhanh mở tài khoản mới (POST `/taikhoan/mo`), gọi `sp_MoTaiKhoan`.

**Nguyên nhân gốc rễ:**
SP phiên bản cũ kiểm tra KH bằng `IF NOT EXISTS (... KhachHang) AND NOT EXISTS (... [LINK1].NGANHANG.dbo.KhachHang)` rồi INSERT vào `TaiKhoan` **trong cùng scope**. Bảng `TaiKhoan` có Merge Replication → INSERT kích hoạt trigger `MSmerge_ins_*`. Trigger này cố enlist vào transaction hiện tại, nhưng scope đã có query LINK1 (linked server) → SQL Server tạo **implicit distributed transaction**. Conflict giữa implicit distributed tran và merge trigger → SQL Server kill session.

**Pattern gốc (đã thấy ở `sp_GuiTien`):** Các SP khác (`sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien`) hoạt động đúng vì chúng đọc local/LINK1 **TRƯỚC**, rồi mới `BEGIN DISTRIBUTED TRANSACTION` chỉ chứa write — merge trigger chạy bình thường trong distributed tran tường minh.

**Cách xử lý đã áp dụng (3 phần):**

**1. Sửa SP `sp_MoTaiKhoan`** ([`sql/stored_procedures/20_SP_MoTaiKhoan.sql`](../sql/stored_procedures/20_SP_MoTaiKhoan.sql)):
- Tách check KH (local + LINK1) ra trước, lưu kết quả vào biến `@KHFound`.
- INSERT nằm trong `BEGIN DISTRIBUTED TRANSACTION` riêng biệt — scope chỉ có write, không có LINK1 query.
- Thêm `SET XACT_ABORT ON` + `TRY/CATCH` chuẩn.
```sql
-- SOTK đã được sinh tự động ở tầng app (sinhSOTK) → không cần check trùng
DECLARE @KHFound bit = 0;
IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    SET @KHFound = 1;
ELSE IF EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    SET @KHFound = 1;

-- INSERT trong distributed tran riêng — không có LINK1 query
BEGIN DISTRIBUTED TRANSACTION;
INSERT INTO TaiKhoan(...) VALUES(...);
COMMIT TRANSACTION;
```
Deploy lên cả SQL1 và SQL2.

**2. Sửa route `taikhoan.js`:**
- POST `/taikhoan/mo` luôn gọi `execSPAdmin` (sqlcmd) thay vì `execSP` (tedious) — vì SP nay dùng `BEGIN DISTRIBUTED TRANSACTION`, tedious không hỗ trợ MSDTC.
- Dùng `queryAdminSQL` thay vì `getAdminPool` trực tiếp cho `getAllKhachHang()` và GET `/taikhoan` (ChiNhanh) — có retry tự động khi pool bị lỗi.

**3. Tăng cường connection pool resilience (`db.js`):**
- Thêm `isPoolDead()`: kiểm tra pool `connected` + `_closed` trước khi reuse.
- Thêm `isSessionKilled()`: nhận diện lỗi kill state / connection closed / socket error.
- Retry logic (1 lần) trong `execSP`, `querySQL`, `queryAdminSQL`: xóa pool chết → tạo mới → thử lại.
- Hàm mới `queryAdminSQL`: admin pool query với retry (thay cho dùng `getAdminPool` trực tiếp).

**4. `start.bat` — tự kill process cũ:**
```bat
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":3001.*LISTENING"') do (
    taskkill /F /PID %%a >nul 2>&1
)
```

**Bài học rút ra (rất hay bị hỏi vấn đáp):**
> Khi bảng có Merge Replication trigger (`MSmerge_ins_*`, `MSmerge_upd_*`, `MSmerge_del_*`), **không được** query Linked Server cùng scope với INSERT/UPDATE/DELETE lên bảng đó mà không có distributed transaction tường minh. Query LINK1 tạo implicit distributed tran → conflict với trigger → session bị kill. **Giải pháp chuẩn:** đọc LINK1 trước, lưu kết quả vào biến, rồi write trong `BEGIN DISTRIBUTED TRANSACTION` riêng (scope chỉ chứa write).

---

## Sự cố 6: Dữ liệu TRACUU (SQL3) không đồng bộ sau khi migration

**Triệu chứng:**
Sau khi chạy migration đổi MANV trên SQL1+SQL2, trang danh sách nhân viên (nhóm NganHang) vẫn hiển thị `NV01`, `NV02`... thay vì `BT001`, `TD001`. Một số nhân viên mất khỏi danh sách, một số bị trùng hoặc sai chi nhánh.

**Nguyên nhân gốc rễ:**
SQL3 là **Subscriber** của Replication. Các lệnh `UPDATE NhanVien SET MANV = ...` chạy trực tiếp trên SQL1/SQL2 (Publisher) nhưng **Replication Agent không propagate kịp** (hoặc đã tạm dừng). SQL3 còn giữ snapshot cũ.

Thêm vào đó, dữ liệu demo trên SQL1 và SQL2 dùng **CMND trùng nhau** cho các nhân viên "cùng người" xuất hiện ở cả 2 chi nhánh (ví dụ: BT001 và TD001 cùng CMND `0123456789`). Bảng `NhanVien` trên SQL3 có ràng buộc `UNIQUE KEY` trên `CMND`, nên chỉ lưu được 1 trong 2 → thiếu bản ghi.

**Cách xử lý đã áp dụng:**
1. Chạy `UPDATE NhanVien SET MANV = 'BTxxx' WHERE RTRIM(MANV) = 'NVxx' AND MACN = 'BENTHANH'` trực tiếp trên SQL3.
2. Đổi CMND của nhân viên TANDINH sang giá trị khác trên SQL2 (ví dụ `TD001.CMND = '0123456001'` thay vì `'0123456789'`), sau đó INSERT thủ công bản ghi còn thiếu vào SQL3.
3. UPDATE CMND trên SQL3 để khớp với SQL2.

**Bài học rút ra:**
> Khi chạy migration data trên Publisher, cần kiểm tra Subscriber ngay sau đó. Nếu Replication chậm hoặc có conflict, cần can thiệp thủ công trên Subscriber. Dữ liệu demo không nên dùng CMND trùng cho các nhân viên khác nhau ở các chi nhánh.
