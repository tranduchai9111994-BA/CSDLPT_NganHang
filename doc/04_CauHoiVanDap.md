# Bộ Câu Hỏi Vấn Đáp — Ôn Thi CSDL Phân Tán (Đề Ngân Hàng)

> **Cách dùng:** Đọc câu hỏi → che phần trả lời → tự trả lời → so sánh.
> **Mẹo:** Giảng viên thường hỏi theo chuỗi. VD: hỏi phân mảnh → hỏi tiếp Linked Server → hỏi tiếp Distributed Transaction. Nên ôn theo cụm, không ôn lẻ.

**Cấu trúc tài liệu:**
- Cụm 1–8: Bộ câu hỏi lý thuyết + tình huống theo chủ đề.
- Cụm 9: Phân tích chi tiết 6 kịch bản demo hay bị hỏi trực tiếp.

---

## CỤM 1: PHÂN MẢNH DỮ LIỆU

### 1.1. Hệ thống dùng kiểu phân mảnh gì? Tại sao?

**Trả lời:** Phân mảnh ngang (**Horizontal Fragmentation**), dựa trên cột `MACN` (mã chi nhánh). Mỗi dòng dữ liệu nằm ở chi nhánh nào tùy vào giá trị `MACN` của nó. Ví dụ dòng có `MACN = 'BENTHANH'` nằm ở SQL1, `MACN = 'TANDINH'` nằm ở SQL2.

Chọn phân mảnh ngang vì nghiệp vụ ngân hàng phân chia theo chi nhánh — mỗi chi nhánh xử lý giao dịch của riêng mình, ít khi cần truy cập dữ liệu chi nhánh khác.

### 1.2. Bảng nào phân mảnh, bảng nào không?

**Trả lời:**
- **Phân mảnh ngang** (theo `MACN`): `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`.
- **Nhân bản toàn vẹn** (Full Replication) giữa 2 chi nhánh: `ChiNhanh` (danh mục tham chiếu) và `TaiKhoan` (để mỗi site có thể tra cứu TK toàn hệ thống ngay tại local, không cần Linked Server để SELECT).
- **Nhân bản 1 chiều xuống TRACUU**: `KhachHang` được replicate full sang SQL3 để phục vụ tra cứu toàn cục.

### 1.3. Tại sao `TaiKhoan` nhân bản toàn vẹn thay vì phân mảnh?

**Trả lời:** Nhân bản toàn vẹn `TaiKhoan` mang lại 2 lợi ích:

1. **Kiểm tra nhanh khi chuyển tiền**: `sp_ChuyenTien` cần xác minh TK nhận có tồn tại. Nhờ replicate full, mọi TK có bản copy local → SELECT kiểm tra không qua LINK → nhanh.
2. **Tra cứu linh hoạt**: Nhân viên có thể xem thông tin bất kỳ TK nào từ site local.

**Quy tắc ĐỌC/GHI với bảng nhân bản:**
- **Đọc**: local (nhanh, không tốn mạng).
- **Ghi**: chỉ ghi tại **site sở hữu** (nơi có `MACN` trùng với `MACN` của TK). Nếu TK thuộc chi nhánh khác → GHI qua `[LINK1]`, Replication đồng bộ ngược lại.

**SP phải phân biệt bằng MACN, không bằng EXISTS**: Vì TK luôn tồn tại local (do replicate), `sp_ChuyenTien` so sánh `MACN` của TK nhận với `MACN` chi nhánh hiện tại để quyết định ghi local hay qua LINK1.

### 1.4. `GD_GOIRUT` và `GD_CHUYENTIEN` không có cột MACN, vậy phân mảnh theo gì?

**Trả lời:** Hai bảng giao dịch này cố tình không có `MACN`. Giao dịch thuộc chi nhánh nào được xác định gián tiếp:
1. Qua cột `MANV` — NV nào thực hiện thì GD thuộc chi nhánh của NV đó.
2. Qua mảnh phân tán — GD được INSERT vào mảnh nào thì thuộc chi nhánh đó.

Thêm `MACN` vào bảng GD là **sai thiết kế** vì tạo dư thừa dữ liệu.

### 1.5. Trạm TRACUU chứa gì? Tại sao chỉ chứa `KhachHang`?

**Trả lời:** TRACUU chỉ replicate full bảng `KhachHang` của cả 2 chi nhánh. Không chứa bảng giao dịch, không chứa `NhanVien`, không chứa `TaiKhoan`.

Lý do: TRACUU phục vụ nhóm NganHang (Ban Giám Đốc) tra cứu nhanh khách hàng mà không ảnh hưởng hiệu năng server đang xử lý giao dịch. Khi cần xem GD/TK/NV, TRACUU dùng Linked Server (LINK1/LINK2) gọi sang SQL1/SQL2 → dữ liệu realtime + TRACUU nhẹ.

### 1.6. Phân mảnh ngang khác phân mảnh dọc ở điểm nào?

**Trả lời:**
- **Phân mảnh ngang**: chia theo **hàng**. Mỗi mảnh chứa một tập con các dòng. Cấu trúc cột giống nhau. → Hệ thống này dùng.
- **Phân mảnh dọc**: chia theo **cột**. Mỗi mảnh chứa một tập con các cột. Cần có khóa chính chung để ghép lại.

Đề bài này phù hợp phân mảnh ngang vì tất cả chi nhánh cần cùng cấu trúc bảng, chỉ khác tập dữ liệu.

### 1.7. 3 tính chất của phân mảnh (Completeness / Reconstruction / Disjointness) đạt ở mức nào?

**Trả lời:**
- **Completeness (Đầy đủ)**: Mọi dòng của bảng "logic" đều nằm trong ít nhất 1 mảnh. Đạt — mọi KH/NV/GD đều có `MACN` xác định → nằm trong đúng 1 mảnh.
- **Reconstruction (Tái hợp)**: Có thể ghép các mảnh lại được bảng gốc bằng `UNION ALL`. Đạt — cấu trúc cột giống nhau, `UNION ALL` từ tất cả mảnh cho ra bảng gốc.
- **Disjointness (Tách biệt)**: Các mảnh không giao nhau. **Đạt cho các bảng phân mảnh ngang**; **có ý vi phạm với bảng full replication** (`TaiKhoan`, `ChiNhanh`, `KhachHang` trên TRACUU). Vi phạm này **có chủ đích và có kiểm soát**: đánh đổi tính tách biệt lấy tốc độ đọc — phù hợp yêu cầu tra cứu toàn cục.

### 1.8. Làm sao đảm bảo tính toàn vẹn khi dữ liệu nằm ở nhiều server?

**Trả lời:** Qua 3 cơ chế:
1. **Replication** đồng bộ dữ liệu giữa NGUON và các mảnh (nhất quán).
2. **Distributed Transaction + MSDTC** cho các thao tác liên chi nhánh (ACID).
3. **Ràng buộc CHECK tại mỗi mảnh** (VD: `SODU >= 0` trên `TaiKhoan`).

### 1.9. Nếu thêm chi nhánh thứ 3 thì cần làm gì?

**Trả lời:**
1. Tạo SQL Server instance mới (VD SQL4).
2. Thêm dòng mới vào bảng `ChiNhanh` (VD `MACN = 'CHOLON'`).
3. Cấu hình Replication mới với filter `MACN = 'CHOLON'`.
4. Tạo Linked Server từ SQL4 đến các mảnh khác + ngược lại.
5. Cập nhật SP TRACUU (`sp_DanhSachNhanVien`, `sp_SaoKeToanBo`...) để UNION ALL thêm `[LINK3]`.

Ưu điểm phân mảnh ngang: mở rộng dễ dàng, chỉ cần thêm mảnh mới.

---

## CỤM 2: LINKED SERVER

### 2.1. Linked Server là gì? Tại sao cần dùng?

**Trả lời:** Linked Server là cơ chế của SQL Server cho phép 1 server truy vấn dữ liệu trên server khác như thể đang truy vấn local. Cú pháp **4 phần**: `[TenLink].TenDB.dbo.TenBang`.

Cần dùng vì dữ liệu nằm phân tán ở nhiều server. Ví dụ chi nhánh BENTHANH cần kiểm tra tài khoản nhận ở TANDINH → truy vấn qua LINK1.

### 2.2. LINK0, LINK1, LINK2 trỏ đến đâu?

**Trả lời:**
- Tại SQL1 (BENTHANH): `LINK0` → NGUON, `LINK1` → SQL2 (chi nhánh đối tác).
- Tại SQL2 (TANDINH): `LINK0` → NGUON, `LINK1` → SQL1 (chi nhánh đối tác).
- Tại SQL3 (TRACUU): `LINK0` → NGUON, `LINK1` → SQL1, `LINK2` → SQL2.

**Quy tắc quan trọng:** LINK1 luôn là chi nhánh đối tác. **Tuyệt đối không cấu hình loopback** (trỏ về chính mình).

### 2.3. Tại sao LINK1 luôn là "đối tác" mà không đặt tên cụ thể?

**Trả lời:** Để SP có thể viết chung cho cả 2 chi nhánh. `sp_ChuyenTien` chạy ở SQL1 gọi `[LINK1]...` — đó là TANDINH. Cùng SP đó chạy ở SQL2, `[LINK1]` sẽ trỏ đến BENTHANH. **Một SP dùng chung, không cần viết 2 bản khác nhau** → dễ bảo trì.

### 2.4. Security Mapping của Linked Server là gì?

**Trả lời:** Khi server A gọi sang server B qua Linked Server, cần xác thực bằng login ở phía server B. Security Mapping cấu hình login được dùng. Hệ thống dùng login `HTKN` làm credential chung cho tất cả Linked Server:

```sql
EXEC sp_addlinkedsrvlogin
    @rmtsrvname  = N'LINK1',
    @useself     = N'False',
    @locallogin  = NULL,
    @rmtuser     = N'HTKN',
    @rmtpassword = N'123';
```

**Điểm dễ sai:** Login `HTKN` phải được **tạo thủ công trên từng instance** vì Login là đối tượng cấp Server, không được Replication đồng bộ.

### 2.5. Gặp `Login failed for user 'HTKN'` khi gọi Linked Server thì xử lý thế nào?

**Trả lời:** Kiểm tra login `HTKN` ở **server đích** (nơi Linked Server trỏ tới), không phải server đang đứng:
1. Kiểm tra HTKN có tồn tại và đang bật (`is_disabled = 0`) trên server đích.
2. Kiểm tra mật khẩu trong `sys.linked_logins` có khớp với mật khẩu thật trên server đích.
3. Test: `SELECT TOP 1 * FROM [LINK1].NGANHANG.dbo.TaiKhoan` (nếu chạy được → OK).

### 2.6. Cú pháp 4 phần là gì?

**Trả lời:** `[TenLinkedServer].[TenDatabase].[Schema].[TenBang]`. Ví dụ: `[LINK1].NGANHANG.dbo.TaiKhoan` — truy vấn bảng `TaiKhoan` trong DB `NGANHANG`, schema `dbo`, trên server mà LINK1 trỏ tới.

---

## CỤM 3: DISTRIBUTED TRANSACTION & MSDTC

### 3.1. Distributed Transaction là gì? Khi nào cần?

**Trả lời:** Là giao dịch mà các thao tác diễn ra trên 2+ server. Cần khi thao tác phải đảm bảo ACID trên nhiều mảnh. Ví dụ: chuyển tiền từ TK ở BENTHANH sang TK ở TANDINH — phải trừ tiền ở SQL1 **VÀ** cộng tiền ở SQL2, cả 2 thành công hoặc cả 2 rollback.

### 3.2. MSDTC là gì? Vai trò trong hệ thống?

**Trả lời:** MSDTC = Microsoft Distributed Transaction Coordinator. Là dịch vụ Windows quản lý giao dịch phân tán. Thực hiện giao thức **Two-Phase Commit (2PC)**:
- **Phase 1 (Prepare)**: hỏi tất cả server "sẵn sàng commit chưa?".
- **Phase 2 (Commit/Rollback)**: nếu tất cả OK → commit; nếu bất kỳ ai fail → rollback hết.

### 3.3. `SET XACT_ABORT ON` để làm gì?

**Trả lời:** Khi bật, nếu bất kỳ lỗi runtime nào (mất mạng, vi phạm constraint, deadlock...) xảy ra, SQL Server **tự động ROLLBACK toàn bộ transaction** thay vì để transaction treo. **Bắt buộc** khi dùng `BEGIN DISTRIBUTED TRANSACTION`.

### 3.4. Nếu đang chuyển tiền mà đứt mạng giữa 2 server thì sao?

**Trả lời:** Nhờ MSDTC + `SET XACT_ABORT ON`, toàn bộ giao dịch ở cả 2 đầu tự động ROLLBACK. Tiền không mất, không sai. Cụ thể: server chuyển tiền sẽ ROLLBACK (hoàn số dư), server nhận tiền cũng ROLLBACK (không cộng tiền). Sau khi mạng phục hồi, NV thực hiện lại.

### 3.5. `sp_ChuyenTien` có luôn dùng `BEGIN DISTRIBUTED TRANSACTION` không?

**Trả lời:** **Không** (đây là fix #6 mới nhất). SP hiện rẽ nhánh transaction theo cùng/khác chi nhánh:

```sql
DECLARE @IsNhanLocal bit = CASE WHEN @MACN_NHAN = @MACN_CHUYEN THEN 1 ELSE 0 END;

BEGIN TRY
    IF @IsNhanLocal = 1
        BEGIN TRANSACTION;               -- Cùng CN: local tran, không cần MSDTC
    ELSE
        BEGIN DISTRIBUTED TRANSACTION;   -- Khác CN: DTC 2PC qua LINK1
    ...
```

**Lý do:** MSDTC 2PC là công cụ mạnh nhưng đắt (2 round-trip: Prepare + Commit). Khi mọi thao tác đều trong 1 site (chuyển tiền cùng CN), dùng `BEGIN TRAN` thường đã đủ ACID, không cần overhead của DTC. Trong thực tế >70% giao dịch là cùng CN → tối ưu này quan trọng.

Nguyên tắc tương tự cũng áp dụng cho `sp_GuiTien` và `sp_RutTien`.

### 3.6. Two-Phase Commit có nhược điểm gì?

**Trả lời:** Chậm hơn local tran do phải chờ tất cả server xác nhận. Nếu 1 server sập giữa phase 1 và phase 2, giao dịch bị **treo (in-doubt transaction)** đến khi server đó khởi động lại. Hệ thống nhỏ (2 chi nhánh) không đáng lo; hệ thống lớn (100+ chi nhánh) cần giải pháp khác (message queue, eventual consistency, Saga...).

### 3.7. Tại sao Node.js dùng `sqlcmd` thay vì driver `mssql`?

**Trả lời:** Driver `tedious` (backend của package `mssql`) **không hỗ trợ đầy đủ MSDTC**. Khi SP mở distributed tran, driver dễ treo hoặc mất kết nối. `sqlcmd` dùng Native Client / ODBC → hỗ trợ MSDTC nguyên vẹn. Hệ thống dùng hàm `execSPAdmin` trong `db.js` để bung `sqlcmd` qua `child_process.execFile` cho 6 SP có `BEGIN DISTRIBUTED TRANSACTION`.

---

## CỤM 4: STORED PROCEDURE

### 4.1. Tại sao xử lý nghiệp vụ trong SP thay vì viết SQL trực tiếp trong code app?

**Trả lời:**
1. **An toàn**: SP chạy dưới quyền DB, tránh SQL Injection.
2. **Toàn vẹn**: Logic kiểm tra số dư, ràng buộc phân tán nằm trong SP — đảm bảo luôn được thực thi bất kể ai gọi.
3. **Hiệu năng**: SP được compile 1 lần, cache execution plan.
4. **Tập trung**: Sửa logic 1 chỗ (SP), không phải tìm sửa ở nhiều file code.

### 4.2. Giải thích logic `SP_SaoKeTaiKhoan` — "tính lùi số dư đầu kỳ" là gì?

**Trả lời:** Thay vì kéo toàn bộ lịch sử GD từ khi mở TK để cộng dồn (rất chậm), SP lấy số dư hiện tại rồi **trừ ngược lại** tổng biến động từ ngày yêu cầu đến nay:

`Số dư đầu kỳ = Số dư hiện tại − SUM(biến động từ @TUNGAY đến nay)`

Sau đó dùng **Window Function** (`SUM() OVER ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING`) tính số dư lũy kế từng dòng. Chỉ cần kéo dữ liệu trong khoảng thời gian yêu cầu qua Linked Server → nhanh hơn nhiều so với cộng dồn từ đầu.

**Ví dụ:** SODU_HIENTAI = 10tr, BIENDONG từ 01/07 đến nay = 2tr → SODU_DAUKY = 8tr.

| NGAYGD | LOAIGD | SOTIEN | SODU_LUYKE | Giải thích |
|---|---|---|---|---|
| 01/07 | GT (gửi) | 5,000,000 | 13,000,000 | 8tr + 5tr |
| 05/07 | RT (rút) | 2,000,000 | 11,000,000 | 13tr − 2tr |
| 10/07 | CT (chuyển đi) | 1,000,000 | 10,000,000 | 11tr − 1tr |
| 15/07 | NT (nhận CK) | 3,000,000 | 13,000,000 | 10tr + 3tr |
| 20/07 | GT | 2,000,000 | 15,000,000 | 13tr + 2tr |

### 4.3. `sp_Login_App` hoạt động thế nào?

**Trả lời:** SP nhận `@LoginName`, đọc `sys.database_principals` + `sys.database_role_members` xác định role của user (`NganHang / ChiNhanh / KhachHang`). Sau đó:
- Nếu `ChiNhanh`: tìm trong `NhanVien` lấy `MANV, HOTEN, MACN`.
- Nếu `KhachHang`: tìm trong `KhachHang` bằng CMND.
- Nếu `NganHang`: trả về thông tin cơ bản, `MACN` mặc định `TRACUU`.

Trên TRACUU (SQL3) không có bảng `NhanVien`/`ChiNhanh` → SP dùng `OBJECT_ID(...) IS NOT NULL` guard để tự thích nghi (một bản code chạy được ở mọi site).

### 4.4. `sp_ChuyenTien` có phải check TK nhận ở cả local VÀ LINK1 không?

**Trả lời:** **Không cần**. `TaiKhoan` nhân bản toàn vẹn giữa 2 chi nhánh → mọi TK có bản copy local trên cả SQL1 và SQL2. SP chỉ cần đọc local `SELECT @MACN_NHAN = MACN FROM TaiKhoan WHERE SOTK = @SOTK_NHAN`. Nếu `@MACN_NHAN IS NULL` → TK không tồn tại trên toàn hệ thống.

Sau đó **so sánh `@MACN_NHAN` với chi nhánh hiện tại** để quyết định ghi local hay ghi qua LINK1.

### 4.5. SP tại NGUON có khác SP tại các mảnh không?

**Trả lời:** Có. NGUON chỉ chứa SP cấp Publisher (là "nguồn" đẩy xuống). Các SP nghiệp vụ được deploy chủ yếu ở SQL1/SQL2 (nơi giao dịch xảy ra). TRACUU có bộ SP riêng dùng LINK1/LINK2 để tra cứu tổng hợp (`sp_DanhSachTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay`, `sp_DanhSachNhanVien`, `sp_SaoKeToanBo`, `SP_SaoKeTaiKhoan` bản TRACUU, `SP_DanhSachTrangThaiLogin`).

### 4.6. Không sửa được SP tại Subscriber thì xử lý sao?

**Trả lời:** Nếu SP là Article trong Publication, Replication **khóa DDL** trên Subscriber (trigger `MSmerge_tr_alterschemaonly`). Cách xử lý:
- Deploy SP mới trên **NGUON (Publisher)**.
- Chạy `sp_startpublication_snapshot @publication = 'PUB_TRACUU'` để tạo snapshot mới.
- Chạy `sp_reinitmergesubscription` → Subscriber đánh dấu reinit.
- Merge Agent tự đẩy SP mới xuống toàn bộ Subscriber.

Nếu SP KHÔNG phải Article → `DROP PROCEDURE IF EXISTS` + `CREATE` trực tiếp trên site đó là được. Trước khi kết luận, luôn kiểm tra bằng `sp_helparticle`.

### 4.7. Tại sao một số thao tác dùng query trực tiếp thay vì SP?

**Trả lời:** Các thao tác đơn giản (UPDATE 1 dòng local, DELETE 1 dòng local, danh sách theo `MACN`) không cần logic phân tán → dùng raw SQL cho nhẹ. SP chỉ cần thiết khi có logic đặc biệt: kiểm tra số dư, distributed tran, tính toán lũy kế, fan-out sang site khác.

---

## CỤM 5: REPLICATION

### 5.1. Hệ thống dùng loại Replication nào?

**Trả lời:** Mô hình Publisher-Subscriber:
- NGUON: Publisher + Distributor.
- SQL1, SQL2, SQL3: Subscriber.

Có 3 Publication:
- **`PUB_BENTHANH`** (Transactional, filter `MACN = 'BENTHANH'`) → đẩy dữ liệu chi nhánh BENTHANH xuống SQL1.
- **`PUB_TANDINH`** (Transactional, filter `MACN = 'TANDINH'`) → đẩy dữ liệu chi nhánh TANDINH xuống SQL2.
- **`PUB_TRACUU`** (Merge) → đẩy `KhachHang` (full, không filter) và các SP dùng chung xuống SQL3.

### 5.2. Replication khác Linked Server ở điểm nào?

**Trả lời:**
- **Replication**: Tự động sao chép dữ liệu theo lịch (background). Dữ liệu ở mỗi mảnh là **bản copy cục bộ** → truy vấn nhanh, nhưng không realtime.
- **Linked Server**: Truy vấn trực tiếp dữ liệu trên server khác theo **thời gian thực**. Chậm hơn vì phải qua mạng mỗi lần query.

Hệ thống dùng cả 2: Replication để đồng bộ dữ liệu nền, Linked Server để xử lý giao dịch liên chi nhánh cần realtime.

### 5.3. Identity Range Management là gì? Tại sao cần?

**Trả lời:** Khi 2 chi nhánh cùng INSERT vào bảng có cột IDENTITY (VD `MAGD` tự tăng), nếu cả 2 đều sinh ra `MAGD = 1, 2, 3...` thì đồng bộ về NGUON sẽ trùng khóa chính.

Giải pháp: SQL Server cấp cho mỗi Subscriber một **dải ID riêng** (VD SQL1 dùng 1000–1999, SQL2 dùng 2000–2999). Không bao giờ đụng độ.

### 5.4. Login có được Replication đồng bộ không?

**Trả lời:** **KHÔNG**. Login là đối tượng cấp Server (instance-level). Replication chỉ đồng bộ đối tượng cấp Database (bảng, SP, dữ liệu). Do đó `HTKN`, `admin`, `BT001`... phải được **tạo thủ công trên từng instance**.

Đây là điểm dễ bị sót nhất khi setup — và cũng là câu hỏi vấn đáp rất hay bị hỏi.

### 5.5. Muốn sửa SP đã là Article thì phải làm ở đâu?

**Trả lời:** Chỉ được sửa tại **Publisher (NGUON)**, rồi để Replication tự đẩy xuống Subscriber. Không được ALTER trực tiếp tại Subscriber vì trigger `MSmerge_tr_alterschemaonly` khóa mọi DDL để tránh lệch pha cấu trúc.

### 5.6. PUB_TRACUU chỉ có `KhachHang`. TRACUU lấy `NhanVien`, `TaiKhoan`, `GD_*` ở đâu?

**Trả lời:** Các bảng đó **không có trên SQL3** (đúng thiết kế). Khi cần dữ liệu, TRACUU dùng **SP đặc thù đọc qua Linked Server**:

- `sp_DanhSachNhanVien`, `SP_DanhSachTrangThaiLogin` → UNION ALL `[LINK1]` + `[LINK2]` cho `NhanVien` (phân mảnh ngang, mỗi CN chỉ có NV của mình).
- `sp_SaoKeToanBo`, `SP_SaoKeTaiKhoan` (bản TRACUU) → UNION ALL `[LINK1]` + `[LINK2]` cho `GD_GOIRUT`/`GD_CHUYENTIEN` (phân mảnh ngang).
- `sp_DanhSachTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay` → **chỉ đọc qua `[LINK1]`** (không UNION LINK2). Vì `TaiKhoan` **replicate toàn phần** giữa BENTHANH↔TANDINH nên LINK1 đã có đủ TK của cả 2 chi nhánh; UNION thêm LINK2 sẽ bị duplicate x2.

Ưu điểm mô hình này: dữ liệu **realtime** (không bị trễ Replication), TRACUU nhẹ.

### 5.7. Sau khi sửa Publication (thêm/bỏ Article), các bảng cũ trên Subscriber có tự xóa không?

**Trả lời:** **KHÔNG**. Replication chỉ ngưng đồng bộ, không tự xóa bảng/dữ liệu cũ. Phải DROP thủ công. Ngoài ra, subscription metadata cũ có thể lệch → cần `sp_removedbreplication` để dọn, rồi tạo lại subscription mới.

---

## CỤM 6: PHÂN QUYỀN

### 6.1. Hệ thống có mấy nhóm quyền? Mỗi nhóm được làm gì?

**Trả lời:** 3 nhóm:
- **NganHang** (Ban Giám Đốc): Chỉ đọc, xem báo cáo mọi chi nhánh, tạo TK (login) cùng nhóm. `DENY INSERT/UPDATE/DELETE`. Reset mật khẩu (độc quyền).
- **ChiNhanh** (Giao dịch viên): Toàn quyền CRUD trên chi nhánh đã login. Tạo TK cùng nhóm. Không reset mật khẩu.
- **KhachHang**: Chỉ xem sao kê TK của chính mình (SP tự lọc theo `LOGIN_NAME()`). Không có `SELECT` trực tiếp trên bảng.

### 6.2. Bảo mật thiết kế mấy tầng?

**Trả lời:** 3 tầng:
1. **DB Role (GRANT/DENY)**: Chốt chặn cứng — kể cả kết nối trực tiếp qua SSMS cũng không vượt được.
2. **Middleware Backend (`requireRole`, `requireChiNhanh`, `requireNganHang`)**: Chặn HTTP request trái phép → HTTP 403.
3. **UI (`<% if user.NHOM %>`)**: Ẩn/hiện menu → UX tốt hơn.

Chỉ UI thì user có thể tự gõ URL. Chỉ Backend thì kết nối SSMS trực tiếp vẫn ghi được. Cần cả 3 tầng.

### 6.3. SQL Authentication khác Windows Authentication ở chỗ nào?

**Trả lời:**
- **SQL Authentication**: Dùng username + password lưu trong SQL Server. Người dùng có thể kết nối từ bất kỳ máy nào, chỉ cần đúng credential. Hệ thống này dùng cách này.
- **Windows Authentication**: Dùng tài khoản Windows (Active Directory). An toàn hơn nhưng yêu cầu cùng domain.

Đề bài yêu cầu 3 nhóm login riêng biệt cho end-user (giao dịch viên, KH) → SQL Authentication phù hợp hơn.

### 6.4. `SP_TaoTaiKhoan` hoạt động thế nào?

**Trả lời:** SP nhận `@LoginName, @Password, @UserName, @Role`. Bên trong:
1. `CREATE LOGIN` — tạo tài khoản cấp Server.
2. `CREATE USER FOR LOGIN` — tạo user cấp Database, mapping với Login.
3. `sp_addrolemember` — gán user vào Role tương ứng.

Route Node.js gọi `SP_TaoTaiKhoan` qua **Admin Pool** (login `HTKN` có quyền `securityadmin`) — user thường không được `CREATE LOGIN`.

Khi tạo login cho khách hàng mới, backend **fan-out** gọi `SP_TaoTaiKhoan` lần lượt trên **BENTHANH + TANDINH + TRACUU** để KH đăng nhập được ở mọi site.

### 6.5. NganHang muốn xem giao dịch ở TANDINH thì query đi đường nào?

**Trả lời:** NganHang mặc định vào TRACUU (SQL3). Khi xem GD:
- TRACUU dùng `[LINK2]` gọi sang TANDINH (SQL2) lấy `GD_GOIRUT`/`GD_CHUYENTIEN`.
- Xem khách hàng thì query local `KhachHang` (đã có full nhờ Replication).

---

## CỤM 7: NGHIỆP VỤ NGÂN HÀNG

### 7.1. Mô tả luồng chuyển tiền liên chi nhánh.

**Trả lời:** BT001 tại BENTHANH chuyển 500.000đ từ TK A (BENTHANH) sang TK B (TANDINH):
1. `sp_ChuyenTien` chạy tại SQL1.
2. **Chặn self-transfer** (fix #9): `IF @SOTK_CHUYEN = @SOTK_NHAN` → RAISERROR ngay.
3. `SET XACT_ABORT ON`; đọc `MACN` của TK chuyển và TK nhận (local — nhờ TaiKhoan replicate full).
4. So sánh `@MACN_NHAN` vs `@MACN_CHUYEN` → khác chi nhánh → set `@IsNhanLocal = 0`.
5. **Rẽ nhánh transaction** (fix #6): `@IsNhanLocal = 0` → `BEGIN DISTRIBUTED TRANSACTION`. Nếu cùng CN → chỉ `BEGIN TRANSACTION` (không cần MSDTC).
6. `UPDATE TaiKhoan SET SODU = SODU - 500000 WHERE SOTK = @A AND SODU >= 500000` — atomic check-and-update tại SQL1. `@@ROWCOUNT = 0` → rollback + báo lỗi số dư.
7. `UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU = SODU + 500000 WHERE SOTK = @B` — ghi qua LINK1 sang SQL2.
8. `INSERT INTO GD_CHUYENTIEN` ghi log tại SQL1 (nơi NV thực hiện GD).
9. `COMMIT TRANSACTION` → MSDTC 2PC đảm bảo cả 2 bên commit hoặc cả 2 rollback (chỉ khi là DISTRIBUTED tran).

### 7.2. Số dư tài khoản có thể âm không?

**Trả lời:** Không. Ba lớp bảo vệ:
1. `CHECK (SODU >= 0)` trên bảng `TaiKhoan`.
2. `sp_RutTien` / `sp_ChuyenTien` dùng atomic check-and-update: `WHERE SOTK = @SOTK AND SODU >= @SOTIEN`. Nếu `@@ROWCOUNT = 0` → rollback + báo lỗi.
3. UI validate tối thiểu 100.000đ.

### 7.3. Mô tả luồng chuyển nhân viên (bao gồm resurrect logic — RF-A).

**Trả lời:** Chuyển NV `BT005` từ BENTHANH sang TANDINH:
1. `sp_ChuyenNhanVien` chạy tại SQL1.
2. Kiểm tra NV tồn tại + `TrangThaiXoa = 0` + `MACN_HIENTAI ≠ MACN_MOI`.
3. **Phát hiện bản ghi cùng CMND tại đích qua LINK1** (fix RF-A):
   - Nếu **có + đang active** (`TrangThaiXoa = 0`) → RAISERROR (dữ liệu sai).
   - Nếu **có + soft-delete** → nhánh **RESURRECT**: giữ MANV cũ (VD `TD003`), chỉ bật `TrangThaiXoa = 0` khi commit.
   - Nếu **không có** → nhánh **INSERT_NEW**: sinh MANV mới với prefix `TD` (VD `TD004`).
4. `SET XACT_ABORT ON`; `BEGIN DISTRIBUTED TRANSACTION`.
5. `UPDATE NhanVien SET TrangThaiXoa = 1 WHERE MANV = 'BT005'` — xóa mềm ở chi nhánh cũ.
6. Tùy nhánh:
   - RESURRECT: `UPDATE [LINK1].NGANHANG.dbo.NhanVien SET TrangThaiXoa = 0 WHERE MANV = 'TD003'`.
   - INSERT_NEW: `INSERT INTO [LINK1].NGANHANG.dbo.NhanVien(...) SELECT ... FROM NhanVien WHERE MANV = 'BT005'`.
7. `COMMIT`. SP trả cột `IsResurrect bit` để app phân biệt.

**Lý do dùng xóa mềm**: `DELETE` sẽ bị Replication đồng bộ xóa ở tất cả site → mất lịch sử + vi phạm FK `GD_*.MANV → NhanVien.MANV`. Xóa mềm giữ lại bản ghi, Replication vẫn OK.

**Lý do resurrect thay vì INSERT mới khi CMND đã có bản soft-delete**: `UQ_NhanVien_CMND` không phân biệt `TrangThaiXoa` → INSERT sẽ vi phạm UNIQUE. Resurrect đảm bảo NV "chuyển đi rồi chuyển về" giữ nguyên MANV cũ + tính liên tục của GD lịch sử.

### 7.4. Một khách hàng có thể có nhiều tài khoản không?

**Trả lời:** Có. Quan hệ `KhachHang` ↔ `TaiKhoan` là 1-N (một KH nhiều TK). Ràng buộc `FOREIGN KEY TaiKhoan.CMND → KhachHang.CMND`.

### 7.5. Giao dịch gửi/rút cần Distributed Transaction không?

**Trả lời:** **Tùy** (đây là fix #6). SP `sp_GuiTien`/`sp_RutTien` rẽ nhánh theo cùng/khác chi nhánh giữa TK và NV thực hiện:

| Kịch bản | Transaction | Lý do |
|---|---|---|
| TK và NV **cùng CN** (`MACN_TK = MACN_NV`) | `BEGIN TRANSACTION` (local) | Chỉ UPDATE bảng `TaiKhoan` local + INSERT `GD_GOIRUT` local, không liên quan server khác. |
| TK và NV **khác CN** (VD BT001 gửi tiền cho TK TD của khách vãng lai) | `BEGIN DISTRIBUTED TRANSACTION` | UPDATE `TaiKhoan` qua `[LINK1]` (site sở hữu TK) + INSERT `GD_GOIRUT` local. Cần MSDTC 2PC. |

Với `sp_RutTien` cả 2 nhánh đều có atomic check số dư `WHERE SODU >= @SOTIEN` + `@@ROWCOUNT = 0` để tránh rút quá số dư.

**Câu hỏi phụ:** "Sao gửi tiền cho khách vãng lai lại cần DTC?"
Trả lời: Vì TK được cập nhật qua LINK1 (site sở hữu), còn GD_GOIRUT ghi local (site NV) → 2 site, 2 write → cần đảm bảo atomicity.

---

## CỤM 8: CÂU HỎI TÌNH HUỐNG

### 8.1. Nếu 2 nhân viên ở 2 chi nhánh cùng lúc rút tiền từ cùng 1 tài khoản thì sao?

**Trả lời:** Tình huống thực tế không xảy ra vì giao diện chỉ cho NV thấy TK có `MACN` = chi nhánh mình (route filter). Nếu có xảy ra ở tầng DB: SQL Server row-level locking sẽ khóa dòng — 1 UPDATE lấy được lock trước, cái kia chờ. Sau khi cái đầu commit, cái sau chạy lại — nếu `SODU` không đủ thì `@@ROWCOUNT = 0` → `RAISERROR`. Cơ chế atomic check-and-update `WHERE SODU >= @SOTIEN` triệt tiêu race condition.

### 8.2. Tại sao không dùng 1 server tập trung cho đơn giản?

**Trả lời:**
- **Hiệu năng**: 1 server phải chịu tải toàn bộ 2 chi nhánh. Phân tán thì mỗi server chỉ xử lý CN mình.
- **Khả dụng**: 1 server sập → toàn hệ thống chết. Phân tán thì CN kia vẫn hoạt động.
- **Yêu cầu đề bài**: Đề bài là CSDL Phân Tán, bắt buộc phân tán.

### 8.3. Hệ thống có xử lý concurrent không?

**Trả lời:** Có, qua cơ chế Lock của SQL Server. Khi SP dùng `BEGIN TRANSACTION`, SQL Server tự động lock các dòng đang thao tác. 2 NV cùng rút từ 2 TK khác nhau → chạy song song. Cùng 1 TK → NV thứ 2 phải chờ NV thứ 1 xong.

### 8.4. Nếu MSDTC chưa bật thì sao?

**Trả lời:** Mọi lệnh `BEGIN DISTRIBUTED TRANSACTION` fail với `MSDTC is not available`. Chuyển tiền liên CN, chuyển NV, mở TK sẽ không hoạt động. Vào `services.msc` → tìm "Distributed Transaction Coordinator" → Start. Phải bật trên **tất cả server** tham gia giao dịch phân tán.

### 8.5. Tại sao `sp_MoTaiKhoan` phải tách query LINK1 ra trước `BEGIN DISTRIBUTED TRANSACTION`?

**Trả lời:** Bảng `TaiKhoan` có Merge Replication → INSERT kích hoạt trigger `MSmerge_ins_*`. Nếu trong cùng scope có cả query `[LINK1]` (check KH) và INSERT, SQL Server tạo **implicit distributed transaction** để cover LINK1 query. Trigger cố enlist vào implicit DT này → conflict → SQL Server kill session với `Cannot continue the execution because the session is in the kill state`.

**Giải pháp (pattern chuẩn):** Check KH (local + LINK1) **TRƯỚC**, lưu kết quả vào biến `@KHFound`. INSERT nằm trong `BEGIN DISTRIBUTED TRANSACTION` riêng — scope chỉ có write, không có LINK1 query → merge trigger hoạt động bình thường. Pattern này nhất quán với `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien`.

---

## CỤM 9: PHÂN TÍCH 6 KỊCH BẢN DEMO CHI TIẾT

> Mục tiêu cụm này: không chỉ biết bấm nút, mà hiểu **tại sao** code chạy như vậy, **đoạn nào** thể hiện phân tán, và trả lời phản biện của giảng viên được.

### Bảng "cheatsheet" — bảng nào nằm đâu

| Bảng | SQL1 (BT) | SQL2 (TD) | SQL3 (TRACUU) | Loại phân tán |
|------|-----------|-----------|---------------|---------------|
| `ChiNhanh` | ✅ Full | ✅ Full | ❌ | Nhân bản toàn vẹn |
| `KhachHang` | Phân mảnh `MACN=BT` | Phân mảnh `MACN=TD` | Full (cả 2 CN) | Phân mảnh ngang + Nhân bản 1 chiều |
| `NhanVien` | Phân mảnh `MACN=BT` | Phân mảnh `MACN=TD` | ❌ | Phân mảnh ngang |
| **`TaiKhoan`** | ✅ **Full** | ✅ **Full** | ❌ (đọc qua LINK1) | **Nhân bản toàn vẹn** |
| `GD_GOIRUT` | GD tại BT | GD tại TD | ❌ | Phân mảnh ngang |
| `GD_CHUYENTIEN` | GD tại BT | GD tại TD | ❌ | Phân mảnh ngang |

**Điểm hay bị hỏi:** `TaiKhoan` nhân bản full → mọi NV ở SQL1 đều thấy cả TK của SQL2. Nhưng chỉ được **GHI** vào TK thuộc CN mình (theo MACN). Nếu TK đích thuộc CN khác → GHI qua LINK1.

### Kịch bản 1 — Chuyển tiền

**SP:** `sp_ChuyenTien` — chạy ở SQL1 hoặc SQL2 (tùy CN của NV đăng nhập).

**Luồng phân tán từng bước:**

```sql
-- Bước 1 & 2: Đọc MACN của TK chuyển + TK nhận (LOCAL — TaiKhoan replicate full)
SELECT @MACN_CHUYEN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
SELECT @MACN_NHAN   = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
IF @MACN_NHAN IS NULL RAISERROR(N'TK nhận không tồn tại trên toàn hệ thống.', 16, 1);

-- Bước 3: SO SÁNH MACN → quyết định ghi ở đâu (KHÔNG DÙNG EXISTS)
DECLARE @IsNhanLocal bit = CASE WHEN @MACN_NHAN = @MACN_CHUYEN THEN 1 ELSE 0 END;

-- Bước 4: DISTRIBUTED TRAN
BEGIN DISTRIBUTED TRANSACTION;

-- Trừ tiền TK chuyển — atomic check-and-update
UPDATE TaiKhoan SET SODU = SODU - @SOTIEN
WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN) AND SODU >= @SOTIEN;
IF @@ROWCOUNT = 0 BEGIN ROLLBACK; RAISERROR(N'Số dư không đủ.', 16, 1); RETURN; END

-- Bước 5: Cộng tiền TK nhận — điểm phân tán thực sự
IF @IsNhanLocal = 1
    UPDATE TaiKhoan SET SODU = SODU + @SOTIEN WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
ELSE
    UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU = SODU + @SOTIEN
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);

-- Ghi log tại nơi NV thực hiện GD (local)
INSERT INTO GD_CHUYENTIEN(...) VALUES(...);
COMMIT TRANSACTION;
```

**Câu hỏi phản biện thường gặp:**

| Câu hỏi | Trả lời |
|---|---|
| Tại sao không dùng `EXISTS` mà so sánh `MACN`? | Vì `TaiKhoan` nhân bản full → `EXISTS` luôn TRUE, không phân biệt được TK thuộc CN nào. Phải so sánh `MACN` — đó là cách **duy nhất đúng** khi nhân bản toàn vẹn. |
| Tại sao kiểm tra số dư trong `WHERE` thay vì `IF` trước? | Đây là **atomic check-and-update**. Nếu dùng `IF` riêng, giữa `IF` và `UPDATE` có thể thread khác cũng rút tiền → race condition. Nhét vào `WHERE` + check `@@ROWCOUNT` là cách chuẩn. |
| Nếu LINK1 đứt giữa chừng? | `UPDATE [LINK1]...` lỗi → `SET XACT_ABORT ON` → tự rollback cả 2 đầu → tiền không mất. |
| Sao không ghi `GD_CHUYENTIEN` ở SQL2 luôn? | Log ghi tại nơi NV thực hiện GD (local). Nếu cần báo cáo tổng hợp thì `sp_SaoKeToanBo` trên TRACUU tự UNION ALL LINK1+LINK2. |

### Kịch bản 2 — Liệt kê khách hàng

**SP:** `sp_LietKeKhachHang` (là Article của `PUB_TRACUU`, có mặt trên cả SQL1/SQL2/SQL3).

Trên **ChiNhanh** (BT001 → SQL1): truyền `@MACN = 'BENTHANH'` → `SELECT ... FROM KhachHang WHERE MACN = 'BENTHANH'` (đọc local, chỉ thấy KH của mình).

Trên **NganHang** (admin → TRACUU): truyền `@MACN = NULL` → `SELECT ... FROM KhachHang` (đọc local — TRACUU có full nhờ replicate).

**So sánh với NhanVien/TaiKhoan:** Các bảng đó KHÔNG được replicate xuống TRACUU → SP TRACUU phải dùng UNION ALL LINK1+LINK2 (`sp_DanhSachNhanVien`) hoặc chỉ LINK1 (`sp_DanhSachTaiKhoan` — vì TaiKhoan replicate full giữa 2 chi nhánh).

**Câu hỏi phản biện:**

| Câu hỏi | Trả lời |
|---|---|
| Nếu thêm KH mới ở BENTHANH, bao lâu TRACUU thấy? | Phụ thuộc Merge Agent sync interval (thường 1–5 phút). Cần realtime → trigger sync tay trên SSMS. |
| Phân mảnh ngang `KhachHang` có vi phạm Disjointness? | Có, nhưng **có kiểm soát**: KH lưu ở mảnh riêng (SQL1 hoặc SQL2), đồng thời replicate lên TRACUU. Đánh đổi Disjointness lấy tốc độ tra cứu — đúng thiết kế. |

### Kịch bản 3 — Chuyển nhân viên

**SP:** `sp_ChuyenNhanVien` — gọi qua `execSPAdmin` (sqlcmd) vì có `BEGIN DISTRIBUTED TRAN`.

**Luồng:**
1. Kiểm tra NV local (`NhanVien` phân mảnh ngang) — nếu không thấy → NV thuộc CN khác → không cho chuyển.
2. Sinh MANV mới với prefix CN đích: `SELECT MAX(MANV) FROM [LINK1].NGANHANG.dbo.NhanVien WHERE MANV LIKE 'TD%'` → `TD004`.
3. `BEGIN DISTRIBUTED TRAN`:
   - `UPDATE NhanVien SET TrangThaiXoa = 1` (xóa mềm ở CN cũ — giữ lịch sử, không bị Replication xóa lan).
   - `INSERT INTO [LINK1].NGANHANG.dbo.NhanVien` (tạo bản ghi mới ở CN đích).
4. `COMMIT`.

**Câu hỏi phản biện:**

| Câu hỏi | Trả lời |
|---|---|
| Sao xóa mềm mà không `DELETE`? | `DELETE` sẽ được Replication đồng bộ xóa ở tất cả site → mất luôn lịch sử. Xóa mềm giữ được record. |
| MANV mới có xung đột không? | Không — sinh `MAX(MANV) LIKE 'TD%'` tại chính SQL2 qua LINK1. Prefix `BT`/`TD` đảm bảo duy nhất toàn cục. |
| LINK1 đứt thì sao? | `INSERT [LINK1]...` fail → `SET XACT_ABORT ON` → rollback cả `UPDATE TrangThaiXoa` → NV về trạng thái ban đầu. |

### Kịch bản 4 — Sao kê tài khoản

**SP:** `SP_SaoKeTaiKhoan` — 2 phiên bản:
- Trên **chi nhánh** (SQL1/SQL2): đọc `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN` **local + LINK1**.
- Trên **TRACUU** (SQL3): UNION ALL `[LINK1]` + `[LINK2]` cho GD (do TRACUU không có bảng GD local).

**Thuật toán "tính lùi số dư đầu kỳ":**
1. `SODU_HIENTAI = SELECT SODU FROM TaiKhoan WHERE SOTK = @SOTK` (local).
2. `BIENDONG_SAU_TUNGAY = SUM` các GD từ `@TUNGAY` đến nay (bao gồm cả local + LINK1).
3. `SODU_DAUKY = SODU_HIENTAI − BIENDONG_SAU_TUNGAY`.
4. Trong khoảng `[@TUNGAY, @DENNGAY]`, dùng Window Function:

```sql
SELECT
    NGAYGD, LOAIGD, SOTIEN,
    SODU_LUYKE = @SODU_DAUKY + SUM(BiendDong) OVER (
        ORDER BY NGAYGD, MAGD
        ROWS UNBOUNDED PRECEDING
    )
FROM TransactionsInPeriod;
```

**`ROWS UNBOUNDED PRECEDING`** = cộng dồn từ dòng đầu tiên đến dòng hiện tại — SQL Server tính trong 1 lần quét, không cần vòng lặp.

**Câu hỏi phản biện:**

| Câu hỏi | Trả lời |
|---|---|
| Tại sao cần UNION ALL với LINK1? | GD của TK BT0000001 có thể xảy ra ở cả 2 server (VD ai từ TANDINH chuyển tiền đến BT0000001 → `GD_CHUYENTIEN` ở SQL2). Phải gộp để không thiếu. |
| `UNION ALL` hay `UNION`? | `UNION ALL` — GD không trùng nhau giữa 2 server (mỗi GD chỉ ghi 1 nơi). `UNION` chậm hơn do loại trùng thừa thãi. |
| Tại sao tính lùi thay vì cộng dồn từ đầu? | Cộng dồn từ ngày mở TK phải đọc **toàn bộ** lịch sử → chậm, tốn network. Tính lùi chỉ đọc dữ liệu trong khoảng `[@TUNGAY, @DENNGAY]`. |

### Kịch bản 5 — Gửi tiền / Rút tiền

**SP:** `sp_GuiTien`, `sp_RutTien` — chạy ở SQL1 hoặc SQL2 tùy CN đăng nhập. **Không cần Distributed Transaction** vì chỉ thao tác 1 TK tại 1 CN (local).

**`sp_RutTien` — atomic check-and-update:**
```sql
UPDATE TaiKhoan SET SODU = SODU - @SOTIEN
WHERE SOTK = @SOTK AND SODU >= @SOTIEN;  -- không bao giờ âm số dư
IF @@ROWCOUNT = 0 RAISERROR(N'Số dư không đủ hoặc TK không tồn tại.', 16, 1);
```

**Câu hỏi phản biện:**

| Câu hỏi | Trả lời |
|---|---|
| Gửi tiền xong, TK đó ở SQL2 có thấy số dư mới không? | Thấy — nhưng sau khi Replication sync (vài giây → vài phút). Replication không realtime. |
| Sao không dùng Trigger để tự động cập nhật số dư? | Trigger trên bảng nhân bản Replication sẽ bị Merge Agent ghi đè ở chu kỳ sync tiếp theo. **Không dùng Trigger trên bảng tham gia Replication**. |
| 2 NV cùng rút từ 1 TK cùng lúc? | Row-level locking: 1 UPDATE lock trước, cái kia chờ. Sau khi cái đầu commit, cái sau chạy → nếu SODU không đủ thì `@@ROWCOUNT = 0` → `RAISERROR`. |

### Kịch bản 6 — Liệt kê tài khoản 2 chi nhánh

**SP:** `sp_DanhSachTaiKhoan` — chạy trên **SQL3 (TRACUU)**. Ai dùng: NganHang.

**Key insight:** `TaiKhoan` **nhân bản toàn vẹn giữa SQL1↔SQL2** → LINK1 (SQL1) đã có full data cả 2 CN → **chỉ cần đọc LINK1, KHÔNG dùng UNION ALL LINK1+LINK2** (sẽ duplicate x2).

```sql
-- sp_DanhSachTaiKhoan trên SQL3
SELECT tk.SOTK, tk.SODU, tk.MACN, tk.NGAYMOTK,
       kh.HO + ' ' + kh.TEN AS HOTEN
FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
OUTER APPLY (SELECT TOP 1 HO, TEN
             FROM KhachHang         -- KhachHang có local trên TRACUU (full)
             WHERE RTRIM(CMND) = RTRIM(tk.CMND)) kh
ORDER BY tk.NGAYMOTK DESC;
```

`OUTER APPLY TOP 1` thay `LEFT JOIN` để tránh nhân bản nếu `KhachHang` có nhiều row cùng `CMND`.

**Câu hỏi phản biện:**

| Câu hỏi | Trả lời |
|---|---|
| TRACUU không có `TaiKhoan` local, JOIN với gì? | `TaiKhoan` lấy từ LINK1 (đã có full). JOIN với `KhachHang` local (đã replicate xuống TRACUU). |
| Tại sao không UNION ALL LINK1+LINK2? | `TaiKhoan` nhân bản full → SQL1 đã có TK của cả 2 CN. UNION sẽ duplicate x2. |
| Thêm CN thứ 3 thì đọc ở đâu? | `TaiKhoan` vẫn nhân bản full → LINK1 vẫn đủ. `GD_*` phân mảnh → cần thêm LINK3 vào UNION ALL của `sp_SaoKeToanBo`. |

---

---

## CỤM 10: DEFENSE IN DEPTH & CÁC FIX GẦN ĐÂY (07/2026)

> Đợt refactor tháng 07/2026 phát hiện và xử lý 6 vấn đề trong SP: race condition sinh khoá, UQ constraint không phân biệt soft-delete, guard nghiệp vụ đặt sai tầng, và MSDTC overhead. Các câu dưới bám sát kịch bản vấn đáp có thể hỏi.

### 10.1. Trước fix #3, SOTK được sinh ở đâu? Vấn đề gì?

**Trả lời:** Sinh ở **tầng app** trong `routes/taikhoan.js`:
```javascript
const maxRow = await queryAdminSQL(server, "SELECT MAX(SOTK) FROM TaiKhoan WHERE SOTK LIKE 'BT%'");
const newSOTK = 'BT' + String(Number(maxRow[0].max.slice(2)) + 1).padStart(7, '0');
await execSPAdmin(server, 'sp_MoTaiKhoan', { SOTK: newSOTK, ... });   // ❌ race
```
**Vấn đề — check-then-act race:** 2 NV cùng lúc click "Mở tài khoản" trong vài ms → cả 2 đọc cùng `MAX = BT0000008` → cùng gán `BT0000009` → cùng INSERT → PK violation, 1 người thành công, 1 người báo lỗi. Đây là race classic khi sinh key ngoài atomic scope.

**Giải pháp:** Move logic vào SP. SP dùng WHILE retry 5 lần: mỗi lần đọc `MAX + Attempt` rồi INSERT trong DTC; PK duplicate → tăng `@Attempt`, thử SOTK khác. Prefix `BT`/`TD` lấy theo `@MACN` (chi nhánh sở hữu TK), route parse SOTK mới từ output text bằng regex.

### 10.2. Tại sao prefix SOTK phải theo `@MACN` chứ không phải server chạy SP?

**Trả lời:** Kịch bản cross-branch: NV BT001 (BENTHANH) mở TK cho khách hàng vãng lai TANDINH → route chọn chạy SP trên **SQL2** (nơi có KH TANDINH local) với `@MACN='TANDINH'`. Nếu prefix dựa vào server đang chạy (`@@SERVERNAME`) → SP đang chạy SQL2 → prefix có thể sai. Vì vậy prefix **luôn** lấy theo `@MACN` — chi nhánh sở hữu TK, không phụ thuộc server chạy.

### 10.3. Tại sao chuyển NV có thể fail với `Msg 2627 UQ_NhanVien_CMND`?

**Trả lời:** Chi nhánh đích đã có bản ghi cùng CMND đang **soft-delete** (`TrangThaiXoa=1`). UQ constraint không phân biệt trạng thái xóa → INSERT vi phạm UNIQUE. Kịch bản thực tế: NV chuyển đi rồi chuyển về, hoặc CMND bị trùng.

**Fix RF-A** — resurrect logic: SP query LINK1 tìm bản ghi cùng CMND tại đích:
- Có + `TrangThaiXoa=0` → RAISERROR (không được active 2 nơi).
- Có + `TrangThaiXoa=1` → UPDATE ngược (`TrangThaiXoa=0`), giữ MANV cũ.
- Không có → INSERT mới với MANV mới.

### 10.4. Vì sao logic đóng TK từ route Node.js được chuyển xuống `SP_DongTaiKhoan`?

**Trả lời:** Đây là fix RF-B — nguyên tắc **defense in depth**. Trước đây route Node.js check `SODU=0`, check GD, rồi `DELETE FROM TaiKhoan`. Nếu ai bypass ứng dụng (SSMS trực tiếp, script khác, SP khác gọi DELETE) → guard bị vượt qua → orphan record + FK violation downstream.

Sau fix: `SP_DongTaiKhoan` giữ 5 guard SQL-side:
1. TK tồn tại.
2. `SODU = 0`.
3. `MACN_TK = MACN_NV` (cùng CN, không cross-branch).
4. Không có `GD_GOIRUT` (local + LINK1).
5. Không có `GD_CHUYENTIEN` (local + LINK1).

Route giờ chỉ forward call qua `execSPAdmin` (dùng admin login vì SP query LINK1). Dù truy cập từ đâu, quy tắc nghiệp vụ luôn được ép ở tầng SQL.

### 10.5. `IS_ROLEMEMBER('KhachHang')` + `SUSER_SNAME()` trong `SP_SaoKeTaiKhoan` để làm gì?

**Trả lời:** Đây là fix #8 — cùng nguyên tắc defense in depth với `SP_DongTaiKhoan`. Middleware Node đã kiểm tra `req.session.user.NHOM === 'KhachHang'` → chỉ cho xem TK của mình. Nhưng nếu khách hàng đăng nhập SSMS trực tiếp (có login SQL) và chạy `EXEC SP_SaoKeTaiKhoan @SOTK='TK_cua_nguoi_khac'` → tầng app biến mất.

Guard SQL:
```sql
IF IS_ROLEMEMBER('KhachHang') = 1
BEGIN
    IF RTRIM(@CMND_TK) <> RTRIM(SUSER_SNAME())
    BEGIN RAISERROR(N'Bạn không có quyền xem sao kê tài khoản này.', 16, 1); RETURN; END
END
```
`SUSER_SNAME()` = SQL login name phiên hiện tại. Với role `KhachHang`, login = CMND → đối chiếu trực tiếp với `CMND` chủ TK. Kể cả gọi trực tiếp từ SSMS cũng không bypass được.

### 10.6. Tại sao cần chặn `@SOTK_CHUYEN = @SOTK_NHAN` trong `sp_ChuyenTien`?

**Trả lời:** Đây là fix #9. Nếu không chặn:
1. `UPDATE TaiKhoan SET SODU = SODU - @SOTIEN WHERE SOTK = @SOTK_CHUYEN`.
2. `UPDATE TaiKhoan SET SODU = SODU + @SOTIEN WHERE SOTK = @SOTK_NHAN` — cùng TK → hoàn tiền.
3. Kết quả: TK không đổi số dư, nhưng có 1 bản ghi rác trong `GD_CHUYENTIEN` với `SOTK_CHUYEN = SOTK_NHAN`.

→ Không gây thiệt hại tài chính, nhưng phá hoại tính đúng đắn của bảng `GD_CHUYENTIEN` (không có ý nghĩa nghiệp vụ). Guard đầu SP là hợp lý.

### 10.7. Merge Replication lag thấy trong test E2E — xử lý ra sao?

**Trả lời:** `TaiKhoan` replicate full qua Merge Replication → có lag (Merge Agent chạy interval mặc định 1 phút). Test E2E tạo TK ở SQL2 rồi lập tức check ở SQL1 sẽ báo `TK không tồn tại` — không phải lỗi SP, là lag replication.

Xử lý trong test (polling pattern):
```js
let synced = false;
for (let i = 0; i < 30; i++) {
    const cnt = Number((await sql('SQL1', `SELECT COUNT(*) FROM TaiKhoan WHERE SOTK='${sotk}'`))[0][0]);
    if (cnt > 0) { synced = true; break; }
    await new Promise(r => setTimeout(r, 1000));
}
```
Poll 30 giây, đủ cho Merge Agent 1 chu kỳ tối đa.

**Trong sản phẩm thực tế**: chấp nhận eventual consistency; UX không hiển thị TK vừa tạo ở chi nhánh khác trong vài giây đầu. Nếu cần strong consistency → dùng DTC (như `sp_ChuyenTien` cross-branch) hoặc read-your-own-writes pattern (đọc site sở hữu SOTK).

---

## Checklist Tự Đánh Giá Trước Bảo Vệ

### Hiểu lý thuyết
- [ ] Giải thích được **phân mảnh ngang** áp dụng cho bảng nào (`KhachHang`, `NhanVien`, `GD_*`).
- [ ] Giải thích được **nhân bản toàn vẹn** áp dụng cho bảng nào, tại sao (`TaiKhoan`, `ChiNhanh`).
- [ ] Giải thích được tại sao `TaiKhoan` nhân bản full nhưng vẫn ghi qua LINK1.
- [ ] Giải thích được **MSDTC 2PC** bằng ví dụ đơn giản (Prepare → Commit/Rollback).
- [ ] Giải thích được tại sao **so sánh MACN** (không dùng `EXISTS`) trong `sp_ChuyenTien`.
- [ ] Giải thích được kỹ thuật **tính lùi số dư đầu kỳ** + Window Function.
- [ ] Giải thích được **3 tính chất phân mảnh** (Completeness / Reconstruction / Disjointness) áp dụng vào hệ thống này.

### Thực hành được
- [ ] BT001/BENTHANH → chuyển tiền cùng CN thành công.
- [ ] BT001/BENTHANH → chuyển tiền khác CN (sang TANDINH) thành công.
- [ ] Kiểm tra SSMS: `SODU` cập nhật đúng trên cả SQL1 và SQL2.
- [ ] admin/TRACUU → xem danh sách KH cả 2 CN.
- [ ] admin/TRACUU → xem danh sách TK cả 2 CN qua SP.
- [ ] Chạy `SP_SaoKeTaiKhoan` trực tiếp trên SSMS, giải thích từng cột.
- [ ] Kiểm tra Replication: thêm KH → sync → xuất hiện trên TRACUU.

### Trả lời phản biện được
- [ ] Tại sao dùng MACN thay vì EXISTS?
- [ ] LINK1 đứt giữa chuyển tiền thì sao?
- [ ] Tại sao ghi `GD_CHUYENTIEN` ở SQL1 thay vì SQL2?
- [ ] Tại sao Node.js dùng `sqlcmd` thay vì `mssql`?
- [ ] `TaiKhoan` nhân bản full → 2 server có luôn đồng bộ không?
- [ ] Tại sao TRACUU không có `NhanVien` nhưng vẫn báo cáo được NV?
- [ ] Tại sao `sp_MoTaiKhoan` phải tách query LINK1 ra trước `BEGIN DISTRIBUTED TRAN`?

---

## Tóm Tắt Nhanh — 10 Phút Cuối Trước Bảo Vệ

| Câu | SP chính | Server chạy | Qua LINK? | Loại transaction |
|-----|----------|------------|-----------|------------------|
| Chuyển tiền | `sp_ChuyenTien` | SQL1 hoặc SQL2 | Có (nếu khác CN) | Rẽ nhánh: local nếu cùng CN, **DISTRIBUTED** nếu khác CN (fix #6) |
| Liệt kê KH | `sp_LietKeKhachHang` | SQL1/SQL2 (CN) hoặc SQL3 (admin) | Không (local) | Không có |
| Chuyển NV | `sp_ChuyenNhanVien` | SQL1 hoặc SQL2 | Có (UPDATE/INSERT sang CN mới, có resurrect RF-A) | **DISTRIBUTED** |
| Sao kê TK | `SP_SaoKeTaiKhoan` | SQL1 hoặc SQL2 | Có (LINK1 gom GD) | Không có, có defense `SUSER_SNAME()` (fix #8) |
| Gửi/Rút | `sp_GuiTien`/`sp_RutTien` | SQL1 hoặc SQL2 | Nếu NV+TK khác CN → LINK1 | Rẽ nhánh: local vs **DISTRIBUTED** (fix #6) |
| Mở TK | `sp_MoTaiKhoan` | SQL1 hoặc SQL2 | Có (check KH qua LINK1 TRƯỚC DTC) | **DISTRIBUTED**, SOTK sinh atomic + retry (fix #3) |
| Đóng TK | `SP_DongTaiKhoan` (mới) | SQL1 hoặc SQL2 | Có (check GD qua LINK1) | Local, 5 guard SQL-side (RF-B) |
| Liệt kê TK 2 CN | `sp_DanhSachTaiKhoan` | **SQL3 (TRACUU)** | **Có (chỉ LINK1)** | Không có |

**Điểm phân tán cốt lõi cần thuộc:**
1. `sp_ChuyenTien` — so sánh `MACN` quyết định ghi local hay `[LINK1]`, rẽ nhánh transaction theo scope thực tế.
2. `TaiKhoan` nhân bản full → đọc local, ghi tại site sở hữu.
3. TRACUU xem tổng hợp → gọi LINK1/LINK2, JOIN `KhachHang` local.
4. Gửi/Rút → rẽ nhánh local/DTC theo `MACN_TK vs MACN_NV`.
5. `sp_MoTaiKhoan` — tách LINK1 query khỏi DTC scope + sinh SOTK atomic trong SP + retry PK.
6. `SP_DongTaiKhoan` — 5 guard SQL-side, tránh bypass ứng dụng (defense in depth).
7. `sp_ChuyenNhanVien` — 3 nhánh (resurrect / RAISERROR / insert new) khi CMND đã tồn tại tại đích.
