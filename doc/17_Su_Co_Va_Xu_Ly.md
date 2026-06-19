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
