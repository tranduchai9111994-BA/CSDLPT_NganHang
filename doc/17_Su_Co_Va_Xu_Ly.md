# Sự Cố Cốt Lõi & Cách Xử Lý (Troubleshooting)

Tài liệu tổng hợp **10 sự cố kinh điển** trong mô hình 4 SQL Server instance của hệ thống ngân hàng phân tán, cùng nguyên nhân gốc rễ và cách xử lý. Đây là những case rất hay bị hỏi xoáy trong vấn đáp về CSDL phân tán. 5 sự cố đầu là các case kỹ thuật hạ tầng; 5 sự cố sau (6–10) là bài học nghiệp vụ + defense-in-depth phát hiện trong đợt refactor tháng 07/2026.

---

## Sự cố 1 — DDL bị chặn trên Subscriber (Replication Article)

**Triệu chứng:**
```
Msg 21531: The data definition language (DDL) command cannot be executed at the Subscriber.
Msg 21530: The schema change failed during execution of an internal replication procedure.
Msg 3609: The transaction ended in the trigger. The batch has been aborted.
```
Xảy ra khi chạy `CREATE OR ALTER PROCEDURE sp_Login_App` hoặc `SP_TaoTaiKhoan` trực tiếp trên Subscriber (SQL3 — TRACUU).

**Nguyên nhân gốc rễ:**
Cả hai SP này là **Article** trong Publication `PUB_TRACUU`. Merge Replication khoá cứng mọi DDL (`CREATE / ALTER / DROP`) trên đối tượng đã đăng ký Article, ở tất cả Subscriber — cơ chế bảo vệ để cấu trúc Publisher/Subscriber không bị lệch pha. Trigger `MSmerge_tr_alterschemaonly` chính là "cửa gác" thực hiện việc chặn này.

**Cách xử lý:**
Không bao giờ ALTER SP trên Subscriber. Muốn sửa nội dung SP thuộc Article:
1. Deploy sửa trên **NGUON (Publisher)**.
2. `sp_startpublication_snapshot @publication = 'PUB_TRACUU'` → tạo snapshot mới.
3. `sp_reinitmergesubscription` để Subscriber đánh dấu reinit.
4. View Synchronization Status → Start → SQL3 nhận SP mới qua replication.

**Bài học (quan trọng cho vấn đáp):**
> SP nào đã là Article trong Publication thì **chỉ được sửa tại Publisher**. Muốn sửa `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_MoTaiKhoan`, `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien`... thì làm ở NGUON rồi để Replication tự đẩy xuống.
>
> **Hệ quả kiến trúc:** SP nào phải chạy trên nhiều site có schema khác nhau (ví dụ: `sp_Login_App` chạy cả trên SQL1/SQL2 có bảng `NhanVien` và trên TRACUU/SQL3 không có bảng đó) cần dùng `OBJECT_ID('dbo.NhanVien','U') IS NOT NULL` guard để tự thích nghi — một bản code duy nhất chạy được trên tất cả site.

---

## Sự cố 2 — `Login failed` khi gọi Linked Server (Login là đối tượng cấp Server)

**Triệu chứng:**
```
Msg 18456, Level 14, State 1
Login failed for user 'HTKN'.
```
Xảy ra khi chạy `SELECT TOP 1 * FROM [LINK1].NGANHANG.dbo.TaiKhoan` trên SQL3 — dù `HTKN` **tồn tại và đang bật** trên chính SQL3.

**Nguyên nhân gốc rễ:**
`HTKN` là **SQL Login cấp Server (instance-level)**. Login **KHÔNG nằm trong phạm vi đồng bộ của Replication** — Replication chỉ đồng bộ đối tượng cấp Database (bảng, SP, dữ liệu, view). Khi SQL3 gọi sang `[LINK1]` (trỏ tới SQL1), nó xác thực bằng Login ở **phía SQL1**, không phải SQL3. Nếu `HTKN` chưa được tạo trên SQL1, hoặc mật khẩu trong `sp_addlinkedsrvlogin` sai → `Login failed`.

**Cách xử lý:**
Với mỗi cặp Linked Server, phải làm 3 việc riêng biệt:
1. Kiểm tra Login tồn tại + đang bật ở server **đích** (nơi LINKx trỏ tới):
   ```sql
   SELECT name, is_disabled FROM sys.server_principals WHERE name = 'HTKN';
   ```
2. Kiểm tra mapping của Linked Server:
   ```sql
   SELECT s.name, l.remote_name, l.uses_self_credential
   FROM sys.servers s LEFT JOIN sys.linked_logins l ON s.server_id = l.server_id
   WHERE s.is_linked = 1;
   ```
3. Cập nhật mapping với đúng mật khẩu:
   ```sql
   EXEC sp_addlinkedsrvlogin
       @rmtsrvname  = N'LINK1',
       @useself     = N'False',
       @locallogin  = NULL,
       @rmtuser     = N'HTKN',
       @rmtpassword = N'<mật khẩu HTKN trên server đích>';
   ```

**Bài học (rất hay bị hỏi vấn đáp):**
> Trong mô hình nhiều instance, có **3 loại đối tượng đồng bộ theo 3 cách khác nhau**:
>
> | Đối tượng | Cấp độ | Cơ chế đồng bộ |
> |---|---|---|
> | Dữ liệu (rows) | Database | Replication (tự động) |
> | Stored Procedure | Database | Replication nếu là Article, hoặc chạy tay từng site |
> | **Login / SID** | **Server (instance)** | **KHÔNG có cơ chế tự động** — luôn phải tạo tay ở từng instance |
>
> Vì vậy: khi tạo user KH mới trong ứng dụng, hệ thống phải **fan-out `CREATE LOGIN` sang cả BENTHANH + TANDINH + TRACUU** để KH có thể tra cứu từ mọi site.

---

## Sự cố 3 — `tedious` không hỗ trợ MSDTC → phải bung `sqlcmd`

**Triệu chứng:**
Gọi `sp_ChuyenNhanVien`, `sp_ChuyenTien`, `sp_MoTaiKhoan` (đều dùng `BEGIN DISTRIBUTED TRANSACTION`) từ Node.js qua `mssql`/`tedious` bị treo hoặc báo lỗi `MSDTC on server is unavailable`, dù chạy trên SSMS thì OK.

**Nguyên nhân gốc rễ:**
Driver `tedious` (backend của thư viện `mssql`) **không hỗ trợ đầy đủ Two-Phase Commit** qua MSDTC. Khi SP mở distributed tran, driver dễ mất kết nối, không rollback được, hoặc treo. Đây là hạn chế cố hữu của tedious — không phải bug của app.

**Cách xử lý:**
Bọc SP bằng **`sqlcmd` CLI** qua `child_process.execFile`. `sqlcmd` dùng Native Client / ODBC — hỗ trợ MSDTC nguyên vẹn:

```javascript
// db.js — execSPAdmin (rút gọn)
execFile('sqlcmd', [
  '-S', serverAddr,
  '-d', 'NGANHANG',
  '-U', 'HTKN', '-P', '123',
  ...vArgs,                    // -v KEY=VALUE cho từng param (chống injection)
  '-Q', `EXEC ${spName} @A=N'$(A)', @B=N'$(B)'`,
  '-b',                        // exit với error code nếu SQL lỗi
  '-o', tmpFile, '-f', '65001' // ép output ra file UTF-8 (giữ dấu tiếng Việt)
], ...);
```

**3 điểm quan trọng trong implementation:**
1. **Chống shell injection**: SQL template `-Q` chỉ chứa `$(VarName)` — giá trị đi qua `-v` (channel riêng). Vẫn escape `'` → `''` để không vỡ SQL string literal.
2. **Encoding tiếng Việt**: `sqlcmd` khi xuất qua stdout/pipe dùng OEM codepage → mất dấu tiếng Việt (`?`). Phải ghi ra file `-o file -f 65001` (UTF-8) rồi Node đọc lại → mới giữ đúng thông báo `RAISERROR`.
3. **Lọc header kỹ thuật**: `sqlcmd` tự thêm dòng `Msg ###, Level ##, State ##, Server ..., Procedure ..., Line ##` trước nội dung `RAISERROR`. Regex bỏ dòng này để hiển thị message sạch cho user.

SP dùng `execSPAdmin`: `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `SP_PhucHoiNhanVien`.

**Bài học:**
> Khi thiết kế hệ thống CSDL Phân Tán mà đã lỡ dùng `BEGIN DISTRIBUTED TRANSACTION` trong SP, cần đảm bảo Driver phía app hỗ trợ MSDTC. Với Node.js: bọc `sqlcmd`. Với .NET/Java: dùng ADO.NET/JDBC XA driver.

---

## Sự cố 4 — Duplicate data trên TRACUU (Full Replication vs Horizontal Fragmentation)

**Triệu chứng:**
Trang "Liệt kê tài khoản" và dropdown "Sao kê" trên TRACUU hiển thị mỗi tài khoản **2 lần**. Form liệt kê TK ra 14 dòng thay vì 7.

**Nguyên nhân gốc rễ:**
Nhầm lẫn về **kiểu replicate** của các bảng:

| Bảng | Kiểu | Trên SQL1 | Trên SQL2 | UNION ALL LINK1+LINK2 |
|---|---|---|---|---|
| `TaiKhoan` | **Full replication** | Có TK của cả 2 chi nhánh | Có TK của cả 2 chi nhánh | ❌ Duplicate x2 |
| `ChiNhanh` | **Full replication** | Có cả 2 chi nhánh | Có cả 2 chi nhánh | ❌ Duplicate x2 |
| `NhanVien` | **Phân mảnh ngang** theo MACN | Chỉ NV chi nhánh BENTHANH | Chỉ NV chi nhánh TANDINH | ✅ Đúng |
| `GD_GOIRUT`, `GD_CHUYENTIEN` | **Phân mảnh ngang** theo chi nhánh | Chỉ GD của chi nhánh này | Chỉ GD của chi nhánh này | ✅ Đúng |

SP TRACUU dùng `UNION ALL [LINK1]...TaiKhoan + [LINK2]...TaiKhoan` → mỗi TK ra 2 lần vì cả 2 site đều đã có đủ.

**Cách xử lý:**
1. Với bảng **full replication** (`TaiKhoan`, `ChiNhanh`): **chỉ đọc từ 1 LINK**. Ví dụ:
   ```sql
   SELECT * FROM [LINK1].NGANHANG.dbo.TaiKhoan
   ```
2. Với bảng **phân mảnh ngang** (`NhanVien`, `GD_*`): mới dùng `UNION ALL LINK1 + LINK2`.
3. Với JOIN có thể trả nhiều row cùng key (VD `KhachHang` có nhiều row cùng CMND), thay `LEFT JOIN` bằng `OUTER APPLY (SELECT TOP 1 ...)` để tránh nhân bản.

**Bài học (rất core cho vấn đáp CSDL phân tán):**
> Trước khi UNION ALL qua Linked Server, phải xác nhận bảng **có thực sự phân mảnh ngang** hay đã **replicate toàn phần**. Bảng replicate toàn phần chỉ cần đọc từ 1 LINK; UNION ALL sẽ gây duplicate = số lượng bản sao. Trong hệ thống này:
> - Phân mảnh ngang: `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN` (fragmentation predicate = `MACN`).
> - Full replication: `TaiKhoan`, `ChiNhanh` (để mọi site có bức tranh toàn cục).
> - Full replication vào TRACUU (subset): `KhachHang` (chỉ replicate xuôi 1 chiều vào SQL3).

---

## Sự cố 5 — `session is in the kill state` khi mở tài khoản (Merge Trigger + Implicit Distributed Tran)

**Triệu chứng:**
```
Cannot continue the execution because the session is in the kill state.
```
Xảy ra khi ChiNhanh mở tài khoản mới, gọi `sp_MoTaiKhoan`.

**Nguyên nhân gốc rễ (tinh vi — hay bị hỏi vấn đáp):**
SP bản cũ có pattern nguy hiểm:
```sql
-- ❌ Query LINK1 và INSERT vào bảng có Merge Replication trong CÙNG scope
IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE CMND=@CMND)
   AND NOT EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE CMND=@CMND)
INSERT INTO TaiKhoan (...) VALUES (...);   -- TaiKhoan có Merge Replication trigger
```

Bảng `TaiKhoan` có Merge Replication → INSERT kích hoạt trigger `MSmerge_ins_*`. Trigger cố enlist vào transaction hiện tại. Nhưng scope này đã có query `[LINK1]...` → SQL Server tự tạo **implicit distributed transaction** để cover cả LINK1 query. Kết quả: merge trigger enlist vào implicit distributed tran mà nó không biết → conflict → SQL Server kill session.

Các SP `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` **không bị lỗi** này vì chúng đọc local/LINK1 **trước**, rồi mới `BEGIN DISTRIBUTED TRANSACTION` tường minh chỉ chứa write — merge trigger hoạt động bình thường trong distributed tran tường minh.

**Cách xử lý (pattern chuẩn):**
```sql
-- ✅ Tách 2 phase rõ ràng
DECLARE @KHFound bit = 0;

-- PHASE 1: Đọc local + LINK1, lưu vào biến (KHÔNG có write ở đây)
IF EXISTS (SELECT 1 FROM KhachHang WHERE CMND=@CMND) SET @KHFound = 1;
ELSE IF EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE CMND=@CMND) SET @KHFound = 1;

IF @KHFound = 0
BEGIN
    RAISERROR(N'Không tìm thấy khách hàng.', 16, 1); RETURN;
END

-- PHASE 2: Distributed tran TƯỜNG MINH — scope chỉ chứa write, không có LINK1 query
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN DISTRIBUTED TRANSACTION;
    INSERT INTO TaiKhoan(...) VALUES(...);
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
```

Đi kèm ở tầng app:
- Route `taikhoan.js` gọi qua `execSPAdmin` (sqlcmd) thay vì `execSP` (tedious).
- `db.js` bổ sung `isPoolDead()` + `isSessionKilled()` + retry 1 lần để hồi phục pool khi replication làm bay session.

**Bài học (rất hay bị hỏi vấn đáp về CSDL phân tán):**
> Khi bảng có **Merge Replication trigger** (`MSmerge_ins/upd/del_*`), **không được** query Linked Server **cùng scope** với INSERT/UPDATE/DELETE lên bảng đó — trừ khi đã bọc bằng `BEGIN DISTRIBUTED TRANSACTION` tường minh. Query Linked Server tạo **implicit distributed tran** ngầm định → conflict với merge trigger → session bị kill.
>
> **Nguyên tắc thiết kế SP phân tán trong hệ thống này:**
> 1. Đọc dữ liệu qua LINK trước, lưu vào biến.
> 2. Mở `BEGIN DISTRIBUTED TRANSACTION` tường minh.
> 3. Trong distributed tran chỉ chứa **write** (INSERT/UPDATE/DELETE), không đọc LINK.
> 4. `COMMIT` sớm nhất có thể.

---

## Sự cố 6 — Race condition khi 2 NV cùng lúc mở tài khoản (SOTK trùng)

**Triệu chứng:**
```
Msg 2627, Level 14, State 1
Violation of PRIMARY KEY constraint 'PK_TaiKhoan'. Cannot insert duplicate key
in object 'dbo.TaiKhoan'. The duplicate key value is (BT0000009).
```
Xảy ra khi 2 nhân viên (VD: BT001 và BT002) cùng lúc click "Mở tài khoản" trong khoảng vài ms.

**Nguyên nhân gốc rễ:**
Trước fix, SOTK được sinh ở **tầng app** (`sinhSOTK()` trong `routes/taikhoan.js`):
```javascript
// ❌ Race condition
const maxRow = await queryAdminSQL(server, "SELECT MAX(SOTK) FROM TaiKhoan WHERE SOTK LIKE 'BT%'");
const newSOTK = 'BT' + String(Number(maxRow[0].max.slice(2)) + 1).padStart(7, '0');
await execSPAdmin(server, 'sp_MoTaiKhoan', { SOTK: newSOTK, ... });
```
2 NV đọc cùng `MAX = BT0000008` → cùng gán `BT0000009` → cùng INSERT → 1 thành công, 1 dính PK violation. Đây là **check-then-act race** kinh điển — logic sinh SOTK và INSERT không nằm trong 1 atomic operation.

**Cách xử lý** *(fix #3)*:
Move logic sinh SOTK vào SP. SP dùng vòng WHILE retry tối đa 5 lần: mỗi lần đọc `MAX(SOTK)` + `@Attempt` rồi INSERT trong distributed tran; PK duplicate → ROLLBACK, tăng `@Attempt`, thử SOTK khác. Prefix `BT`/`TD` lấy theo `@MACN` (chi nhánh sở hữu TK), không phụ thuộc server chạy SP.

```sql
WHILE @Attempt < @MaxAttempt
BEGIN
    SELECT TOP 1 @Max = SOTK FROM TaiKhoan WHERE SOTK LIKE @Prefix + '%' ORDER BY SOTK DESC;
    SET @Num  = ISNULL(CAST(SUBSTRING(RTRIM(@Max), 3, 7) AS INT), 0) + 1 + @Attempt;
    SET @SOTK = @Prefix + RIGHT('0000000' + CAST(@Num AS VARCHAR(7)), 7);

    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;
        INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK) VALUES(@SOTK, ...);
        COMMIT TRANSACTION;
        SELECT @SOTK AS SOTK; RETURN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2627, 2601) SET @Attempt = @Attempt + 1;
        ELSE BEGIN RAISERROR(ERROR_MESSAGE(), 16, 1); RETURN; END
    END CATCH
END
```

Route parse SOTK mới từ output text của `sqlcmd` bằng regex `/\b(?:BT|TD)\d{7}\b/`.

**Bài học:**
> Khi sinh khoá tự tăng bên ngoài SQL, luôn có nguy cơ race. Có 3 cách chuẩn để xử lý:
> 1. **Đưa vào atomic scope** (giải pháp áp dụng ở đây): sinh key trong SP + retry PK violation.
> 2. Dùng `IDENTITY` hoặc `SEQUENCE`: đơn giản nhất, nhưng đề bài đã ràng buộc format `BT0000009` (prefix chi nhánh) nên không dùng được.
> 3. Distributed lock (`sp_getapplock`): overkill cho scenario này.

---

## Sự cố 7 — Chuyển nhân viên về chi nhánh cũ bị chặn (UQ_NhanVien_CMND soft-delete)

**Triệu chứng:**
```
Msg 2627, Level 14, State 1
Violation of UNIQUE KEY constraint 'UQ_NhanVien_CMND'.
Cannot insert duplicate key in object 'dbo.NhanVien'.
The duplicate key value is (0999999001).
Msg 1206: The Microsoft Distributed Transaction Coordinator (MS DTC) has cancelled the distributed transaction.
```
Xảy ra khi chuyển NV từ BT → TD, nhưng trước đây NV này đã từng làm ở TD (bị soft-delete `TrangThaiXoa=1`).

**Nguyên nhân gốc rễ:**
Constraint `UQ_NhanVien_CMND` **không phân biệt `TrangThaiXoa`** — 1 CMND chỉ được tồn tại 1 bản ghi trong bảng, bất kể đã soft-delete hay chưa. `sp_ChuyenNhanVien` bản cũ luôn `INSERT` bản ghi mới tại chi nhánh đích → vi phạm UQ khi CMND đã có bản soft-delete cũ. DTC bị hủy → cả 2 site rollback.

**Cách xử lý** *(fix RF‑A)*:
Bổ sung **resurrect logic**: query LINK1 tìm NV cùng CMND tại đích. 3 nhánh:
1. **Không có** bản ghi cùng CMND → sinh MANV mới + INSERT như cũ.
2. **Có** + `TrangThaiXoa=1` (soft-delete) → **UPDATE ngược** (`TrangThaiXoa=0`), giữ nguyên MANV cũ + thông tin cũ. Đảm bảo lịch sử GD (`GD_GOIRUT`, `GD_CHUYENTIEN`) tham chiếu qua MANV cũ vẫn liên tục.
3. **Có** + `TrangThaiXoa=0` (đang active) → RAISERROR ngay lập tức, vì dữ liệu sai (1 NV không được active tại 2 chi nhánh cùng lúc).

SP trả cột `IsResurrect bit` để app phân biệt kịch bản.

```sql
-- Phát hiện bản ghi tại đích
SELECT @EXIST_MANV = RTRIM(MANV), @EXIST_TRANGTHAI = TrangThaiXoa
FROM [LINK1].NGANHANG.dbo.NhanVien WHERE RTRIM(CMND) = RTRIM(@CMND);

IF @EXIST_MANV IS NOT NULL AND @EXIST_TRANGTHAI = 0
BEGIN RAISERROR(N'NV cùng CMND đang làm việc tại chi nhánh đích.', 16, 1); RETURN; END

IF @EXIST_MANV IS NOT NULL AND @EXIST_TRANGTHAI = 1
BEGIN SET @IsResurrect = 1; SET @MANV_MOI = @EXIST_MANV; END   -- giữ MANV cũ
```

**Bài học:**
> Với dữ liệu soft-delete, constraint UNIQUE cần được thiết kế cẩn thận. Có 2 hướng:
> 1. **Giữ UNIQUE toàn cục** (giải pháp áp dụng ở đây) + tại tầng SP xử lý resurrect. Ưu điểm: đơn giản schema, không có 2 bản ghi cùng CMND. Nhược điểm: SP phức tạp hơn.
> 2. **UNIQUE filtered** (`UNIQUE ... WHERE TrangThaiXoa=0`): chỉ ràng buộc trên bản active. Ưu điểm: SP đơn giản (chỉ INSERT). Nhược điểm: có thể tồn tại nhiều bản soft-delete cùng CMND → phức tạp khi tra cứu lịch sử.
> Với hệ thống banking, hướng 1 an toàn hơn vì đảm bảo 1 người luôn chỉ có 1 record NV tại 1 chi nhánh.

---

## Sự cố 8 — Guard nghiệp vụ ở tầng route Node.js dễ bị bypass (defense-in-depth)

**Triệu chứng:**
Route `POST /taikhoan/dong` (bản cũ) làm 3 việc: check SODU, check GD, DELETE TK. Nếu ai đó **bypass ứng dụng**, truy cập DB trực tiếp qua SSMS/sqlcmd/SP khác và chạy `DELETE FROM TaiKhoan WHERE SOTK=...` → không có bất kỳ guard nào chặn → mất consistency (TK có GD_GOIRUT nhưng bảng TaiKhoan trống → orphan FK, breaks joins downstream).

Tương tự, `SP_SaoKeTaiKhoan` bản cũ không kiểm ownership → khách hàng `1111111111` login SSMS, gọi `EXEC SP_SaoKeTaiKhoan @SOTK='TD0000001'` → xem được sao kê của khách hàng khác (`4444444444`).

**Nguyên nhân gốc rễ:**
**Nguyên tắc "single line of defense" ở tầng app không đủ**. Trong CSDL phân tán với nhiều điểm truy cập (SSMS ở admin, LINK từ site khác, script tự động), guard **phải nằm ở tầng SQL** — càng gần dữ liệu càng an toàn.

**Cách xử lý:**

**Case A (Đóng TK — RF-B):** tạo `SP_DongTaiKhoan` với 5 guard SQL-side:
- G1: TK tồn tại
- G2: `SODU = 0`
- G3: cùng CN với NV (`MACN_TK = MACN_NV`)
- G4: không có `GD_GOIRUT` (local + LINK1)
- G5: không có `GD_CHUYENTIEN` (local + LINK1)

Route giờ chỉ còn forward call: `execSPAdmin(server, 'SP_DongTaiKhoan', { SOTK, MANV })`.

**Case B (Sao kê — fix #8):** thêm check `SUSER_SNAME()` trong SP:
```sql
IF IS_ROLEMEMBER('KhachHang') = 1
BEGIN
    IF RTRIM(@CMND_TK) <> RTRIM(SUSER_SNAME())
    BEGIN RAISERROR(N'Bạn không có quyền xem sao kê tài khoản này.', 16, 1); RETURN; END
END
```
`SUSER_SNAME()` trả về SQL login name của phiên hiện tại. Với role `KhachHang`, login name = CMND — nên đối chiếu trực tiếp với `CMND` chủ TK.

**Bài học (rất core cho vấn đáp):**
> **Defense in depth** — bảo mật nhiều lớp. Không đặt niềm tin duy nhất vào tầng app: 1 bug ở middleware, 1 kịch bản bypass, 1 SP nội bộ gọi sai → mất consistency ngay. Guard SQL-side là lớp cuối cùng, chậm hơn nhưng không thể bị vượt qua.
>
> **Áp dụng trong hệ thống:**
> - `SP_DongTaiKhoan` — guard SODU/GD/same-branch tại SQL.
> - `SP_SaoKeTaiKhoan` — check ownership qua `SUSER_SNAME()`.
> - `sp_TaiKhoanKhachHang` — tự lọc `WHERE CMND = @CMND` (@CMND lấy từ session).
> - `sp_ChuyenTien` — atomic `WHERE SODU >= @SOTIEN`.

---

## Sự cố 9 — MSDTC overhead khi thao tác nội bộ chi nhánh

**Triệu chứng:**
Latency cao khi gửi/rút/chuyển tiền **cùng chi nhánh** (TK + NV cùng MACN). Log cho thấy mỗi giao dịch phải:
1. Đăng ký giao dịch với MSDTC (2 round-trip).
2. Two-phase commit (prepare + commit).

Ngay cả khi không có thao tác remote nào (không đụng LINK1) → vẫn phát sinh MSDTC overhead.

**Nguyên nhân gốc rễ:**
`sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` bản cũ **luôn** dùng `BEGIN DISTRIBUTED TRANSACTION` bất kể TK có ở cùng CN với NV hay không. MSDTC-based 2PC là bắt buộc khi transaction phủ ≥ 2 resource manager (LINK1), nhưng khi tất cả thao tác đều local thì đây là overhead không cần thiết.

**Cách xử lý** *(fix #6)*:
Rẽ nhánh transaction theo `@IsLocal`:
```sql
DECLARE @IsLocal bit = 0;
IF @MACN_TK = @MACN_NV SET @IsLocal = 1;

BEGIN TRY
    IF @IsLocal = 1
    BEGIN
        BEGIN TRANSACTION;                 -- Local tran, KHÔNG cần MSDTC
        UPDATE TaiKhoan SET SODU = SODU + @SOTIEN WHERE ...;
    END
    ELSE
    BEGIN
        BEGIN DISTRIBUTED TRANSACTION;     -- 2PC qua MSDTC
        UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU = SODU + @SOTIEN WHERE ...;
    END

    INSERT INTO GD_GOIRUT(...) VALUES(...);
    COMMIT TRANSACTION;
END TRY
```

**Bài học:**
> Distributed Transaction là công cụ mạnh nhưng đắt. Chỉ dùng khi thực sự cần phối hợp write giữa ≥ 2 site. Trong hệ thống này, phần lớn giao dịch (>70% workload thực tế) là cùng chi nhánh — nên rẽ nhánh là tối ưu quan trọng.

---

## Sự cố 10 — Merge Replication lag khi test E2E hoặc UI vừa cập nhật

**Triệu chứng:**
Vừa tạo TK `TD0000005` trên SQL2 (chi nhánh TANDINH), lập tức chạy query `SELECT ... FROM TaiKhoan WHERE SOTK='TD0000005'` trên SQL1 → **không tìm thấy**. Vài giây / vài chục giây sau mới xuất hiện.

Trong test E2E Playwright, `SP_DongTaiKhoan @SOTK='TD0000005', @MANV='BT001'` chạy trên SQL1 báo `Tài khoản không tồn tại` (đúng logic — TK chưa được replicate về SQL1) → test flaky.

**Nguyên nhân gốc rễ:**
`TaiKhoan` được thiết lập replicate **full via merge replication**. Merge Agent chạy theo schedule (mặc định polling 1 phút), không đồng bộ tức thì như snapshot/DTC. Đây là **đặc điểm nội tại** của merge replication — không phải lỗi.

**Cách xử lý:**

**Với ứng dụng thực tế:** Chấp nhận eventual consistency. UX không hiển thị TK mới tạo ở chi nhánh khác trong vài giây đầu. Nhân viên tạo TK sẽ thấy TK ngay lập tức tại chi nhánh mình (đọc local).

**Với test E2E:** Poll đợi merge sync trước khi assert:
```js
let synced = false;
for (let i = 0; i < 30; i++) {
    const cnt = Number((await sql('SQL1', `SELECT COUNT(*) FROM TaiKhoan WHERE SOTK='${sotk}'`))[0][0]);
    if (cnt > 0) { synced = true; break; }
    await new Promise(r => setTimeout(r, 1000));
}
```

**Nếu cần lower lag:** giảm interval của Merge Agent trong SQL Server Replication Monitor (thấp nhất ~10s), hoặc trigger manually: `EXEC sp_startmergesynchronizationjob @publication='...'`. Không nên push xuống < 5s vì tăng tải CPU + network.

**Bài học:**
> Merge Replication cho **eventual consistency** — chấp nhận lag thay đổi cho tính available. Nếu cần strong consistency (đọc ngay sau write), dùng distributed transaction (như `sp_ChuyenTien` khi cross-branch) hoặc pattern read-your-own-writes (đọc local trước, sync về sau).
>
> Trong hệ thống này:
> - **Đọc TK theo SOTK** → có thể lag vài giây.
> - **Đọc số dư** → có thể lag → nên đọc từ chi nhánh sở hữu (SOTK prefix quyết định site).
> - **Chuyển tiền** → dùng DTC → strong consistency ngay lập tức tại site sở hữu, replica cập nhật sau.
