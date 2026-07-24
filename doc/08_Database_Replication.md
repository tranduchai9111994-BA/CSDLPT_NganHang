# 🔄 Cơ Chế Phân Tán & Nhân Bản Dữ Liệu (Replication)

Tài liệu này đặc tả **kiến trúc phân tán CSDL** — Replication (Publisher/Subscriber), phân mảnh ngang theo `MACN`, ma trận Publication–Article, Distributed Transaction và Identity Range Management.

Đây là tài liệu **cốt lõi cho vấn đáp phần CSDL Phân Tán**. Đọc kèm [`10_Linked_Servers.md`](10_Linked_Servers.md) và [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md).

---

## 1. Mô Hình Publisher–Subscriber

| Vai trò | Instance | Chức năng |
|---|---|---|
| **Publisher + Distributor** | `ES-HAITD16` (NGUON) | Chứa CSDL gốc, phát hành 3 Publication, quản lý Distribution Agent |
| Subscriber 1 | `ES-HAITD16\SQL1` (BENTHANH) | Chi nhánh Bến Thành — phân mảnh `MACN='BENTHANH'` |
| Subscriber 2 | `ES-HAITD16\SQL2` (TANDINH) | Chi nhánh Tân Định — phân mảnh `MACN='TANDINH'` |
| Subscriber 3 | `ES-HAITD16\SQL3` (TRACUU) | Trạm tra cứu — replicate full `KhachHang` |

**Kiểu Replication:** Merge Replication (2 chiều — cho phép Subscriber cập nhật ngược về Publisher).

**Kiểu article cho Stored Procedure:** "**Replicate stored procedure definitions**" (đồng bộ **định nghĩa/code**), KHÔNG dùng "Replicate as execution". → Muốn sửa SP thì ALTER trên NGUON, snapshot mới sẽ đẩy code xuống Subscriber.

---

## 2. Ba Tính Chất Phân Mảnh (Completeness · Reconstruction · Disjointness)

Đây là 3 tính chất **bắt buộc** của một chiến lược phân mảnh đúng đắn. Chúng thường được hỏi trong vấn đáp — cần đối chiếu với từng bảng thực tế trong hệ thống.

### 2.1. Tính đầy đủ (Completeness)
> "Mọi bản ghi của quan hệ gốc phải thuộc về ít nhất một mảnh — không có bản ghi nào bị mất."

Đối chiếu:
- `KhachHang` — mọi KH có `MACN` ∈ {`BENTHANH`, `TANDINH`} → đều nằm ở SQL1 hoặc SQL2. **Đạt.**
- `NhanVien` — tương tự. **Đạt.**
- `GD_GOIRUT`, `GD_CHUYENTIEN` — mỗi GD được INSERT tại đúng site NV thực hiện → không GD nào bị thất thoát. **Đạt.**
- `TaiKhoan`, `ChiNhanh` — nhân bản toàn vẹn (không phân mảnh) → **hiển nhiên đầy đủ**.

### 2.2. Tính tái tạo (Reconstruction)
> "Có thể ghép lại quan hệ gốc từ các mảnh bằng phép hợp/kết (union/join)."

Đối chiếu:
- Với các bảng phân mảnh ngang theo `MACN`: `<Bảng gốc> = <mảnh BENTHANH> UNION ALL <mảnh TANDINH>`.
- Ứng dụng thực tế: các SP TRACUU (`sp_DanhSachNhanVien`, `sp_SaoKeToanBo`) đúng là dùng `UNION ALL [LINK1] ∪ [LINK2]` để tái tạo quan hệ toàn cục cho `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`.
- **Đạt.**

### 2.3. Tính rời nhau (Disjointness)
> "Với phân mảnh ngang, các mảnh phải rời nhau — không có bản ghi nào xuất hiện trong 2 mảnh cùng lúc."

Đối chiếu:
- `KhachHang`, `NhanVien` — `MACN` là điều kiện lọc chặt (`MACN='BENTHANH'` XOR `MACN='TANDINH'`) → không giao. **Đạt.**
- `GD_GOIRUT`, `GD_CHUYENTIEN` — mỗi GD chỉ INSERT tại 1 site (site NV thực hiện). **Đạt.**
- **Ngoại lệ có chủ đích:** `TaiKhoan` và `ChiNhanh` **KHÔNG rời nhau** — cố tình nhân bản đầy đủ trên cả 2 CN. Đây là **replication toàn vẹn** (khác với phân mảnh) — nhằm cho phép mọi site tra cứu TK nhanh mà không cần Linked Server, đổi lại phải có quy tắc "ghi tại site sở hữu (MACN)" để không xung đột.

> 💡 Lưu ý ôn vấn đáp: khi giảng viên hỏi "đảm bảo tính rời nhau", trả lời **theo từng bảng** — không nói chung "hệ thống em rời nhau" vì `TaiKhoan` không rời nhau theo đúng nghĩa (nó replicate).

---

## 3. Tiêu Chí Phân Mảnh Cụ Thể

### 3.1. SQL1 — Chi nhánh Bến Thành
- **Filter Replication:** `MACN = 'BENTHANH'` cho `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`.
- **Không filter** (nhân bản toàn vẹn): `TaiKhoan`, `ChiNhanh`.

### 3.2. SQL2 — Chi nhánh Tân Định
- **Filter Replication:** `MACN = 'TANDINH'` cho `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`.
- **Không filter** (nhân bản toàn vẹn): `TaiKhoan`, `ChiNhanh`.

### 3.3. SQL3 — Trạm Tra Cứu
- **Chỉ có 1 bảng article:** `KhachHang` (replicate full — không filter).
- **Không có local:** `NhanVien`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN`, `ChiNhanh` → khi cần đọc, SP TRACUU dùng `[LINK1]` (BENTHANH) + `[LINK2]` (TANDINH).

### 3.4. Bảng phụ trợ `QuanTriLogin`
- **KHÔNG replicate.** Mỗi instance có bản độc lập.
- Lý do: `LoginName` là object cấp Server, sinh Login trên instance nào thì `QuanTriLogin` trên instance đó ghi. Nếu replicate sẽ tạo ảo giác "cùng 1 Login trên nhiều server" nhưng SID vẫn khác nhau → orphaned user.

### 3.5. Quy tắc đọc/ghi cho bảng nhân bản toàn vẹn

Với `ChiNhanh` (danh mục chỉ đọc):
- **Đọc:** local.
- **Ghi:** Chỉ ghi tại NGUON (qua `LINK0`). TUYỆT ĐỐI không ghi tại Subscriber (sẽ bị Replication ghi đè).

Với `TaiKhoan` (có UPDATE thường xuyên):
- **Đọc:** local.
- **Ghi:** Chỉ ghi tại **site sở hữu** (site có `MACN` khớp với `TaiKhoan.MACN`). SP `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien` so sánh MACN để quyết định UPDATE local hay qua `[LINK1]` trong `BEGIN DISTRIBUTED TRANSACTION`.

---

## 4. Ma Trận Publication ↔ Article ↔ Subscriber

| Publication | Publisher | Subscriber | Article: Bảng | Article: Stored Procedure |
|---|---|---|---|---|
| **PUB_BENTHANH** | NGUON | SQL1 (filter `MACN='BENTHANH'` cho các bảng phân mảnh) | `ChiNhanh`, `KhachHang`, `NhanVien`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN` | `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang`, `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_PhucHoiNhanVien`, `sp_ThemKhachHang`, `SP_SaoKeTaiKhoan` |
| **PUB_TANDINH** | NGUON | SQL2 (filter `MACN='TANDINH'` cho các bảng phân mảnh) | Giống PUB_BENTHANH | Giống PUB_BENTHANH |
| **PUB_TRACUU** | NGUON | SQL3 (không filter cho `KhachHang`) | **Chỉ** `KhachHang` | `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang` |

**Ghi chú:**
- 3 SP article đi kèm PUB_TRACUU đủ để admin đăng nhập vào TRACUU + tạo Login từ giao diện. Các SP đặc thù đọc LINK1/LINK2 (VD `sp_DanhSachNhanVien`) được cài **thủ công** qua [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql), không đưa vào Article.
- Chi tiết deploy matrix của SP: xem [`07_Database_Schema.md`](07_Database_Schema.md) §2.4.

---

## 5. Quy Trình ALTER SP Là Article (rất hay bị hỏi)

Vì SP như `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang` là Article, **không thể ALTER trực tiếp trên Subscriber** — Replication chặn bằng trigger `MSmerge_tr_alterschemasonly` (báo lỗi `Msg 21531`). Quy trình đúng:

1. **Trên NGUON (Publisher):**
   ```sql
   DISABLE TRIGGER [MSmerge_tr_alterschemaonly] ON DATABASE;
   -- (chú ý: trên NGUON tên là 'schemaonly' — không có 's' cuối,
   --  khác với trigger trên Subscriber là 'schemasonly')
   ```

2. **Trên NGUON:** `CREATE OR ALTER PROCEDURE dbo.<TenSP> ...` — cập nhật nội dung SP.

3. **Trên NGUON:** `ENABLE TRIGGER [MSmerge_tr_alterschemaonly] ON DATABASE;`

4. **Trên NGUON:** Snapshot lại + reinit subscription:
   ```sql
   EXEC sp_startpublication_snapshot @publication = N'PUB_BENTHANH';
   EXEC sp_reinitmergesubscription
       @publication = N'PUB_BENTHANH',
       @subscriber = N'ES-HAITD16\SQL1',
       @subscriber_db = N'NGANHANG';
   ```

5. **SSMS Replication Monitor → View Synchronization Status → Start** — chờ log hiển thị "Applied the snapshot and merged N data change(s)".

6. Kiểm tra Subscriber: `EXEC sp_helptext '<TenSP>'` → thấy code mới → thành công.

> ⚠️ **KHÔNG BAO GIỜ** chạy `CREATE OR ALTER PROCEDURE` trực tiếp trên Subscriber cho SP là Article — sẽ bị chặn và làm lệch pha schema.

---

## 6. Distributed Transaction (MSDTC — Two‑Phase Commit)

Replication đảm bảo dữ liệu **hội tụ cuối cùng (eventual consistency)** — có độ trễ giây/phút. Với các thao tác **đòi hỏi ACID xuyên site tức thời** (chuyển tiền liên CN, chuyển NV), phải dùng **Distributed Transaction** qua Linked Server + MSDTC.

### 6.1. Kiến trúc 2‑Phase Commit

```
[Application]
      │  BEGIN DISTRIBUTED TRANSACTION
      ▼
[Site A — SQL1]  ←──── MSDTC Coordinator ────→  [Site B — SQL2]
      │                    │                          │
      │   UPDATE local     │  (Prepare/Commit)        │  UPDATE qua LINK1
      │   INSERT log       │                          │
      ▼                    ▼                          ▼
   Phase 1: Prepare (mỗi site: "sẵn sàng commit chưa?")
   Phase 2: Commit đồng thời (nếu tất cả OK) hoặc Rollback đồng thời (nếu 1 fail)
```

### 6.2. SP dùng Distributed Transaction

| SP | Thao tác | Điều kiện DTC | Ghi chú |
|---|---|---|---|
| `sp_ChuyenTien` | UPDATE TK chuyển (local) + UPDATE TK nhận (LINK1 nếu khác CN) + INSERT log local | Chỉ khi khác CN (fix #6) | Cùng CN → `BEGIN TRANSACTION` local. Có chặn self-transfer (fix #9). |
| `sp_GuiTien`, `sp_RutTien` | UPDATE TK (local hoặc LINK1 tùy MACN) + INSERT log local | Chỉ khi TK và NV khác CN (fix #6) | Cùng CN → local tran, không cần MSDTC. |
| `sp_MoTaiKhoan` | INSERT `TaiKhoan` (kích hoạt Merge trigger) | Luôn dùng DTC | Merge Replication trigger yêu cầu scope DTC tường minh. SOTK sinh atomic trong SP với vòng retry (fix #3). |
| `sp_ChuyenNhanVien` | UPDATE `TrangThaiXoa=1` local + UPDATE/INSERT qua LINK1 | Luôn dùng DTC | Có resurrect logic (RF-A): UPDATE ngược bản soft-delete cùng CMND thay vì INSERT khi vi phạm UQ. |
| `sp_PhucHoiNhanVien` | Local phục hồi + LINK1 deactivate bản kia (nếu tồn tại) | Luôn dùng DTC | Đảm bảo không có 2 bản ghi cùng CMND cùng active. |

**Ngoại lệ — `SP_DongTaiKhoan`** (thêm 07/2026, RF-B): SP có query `LINK1` để check `GD_GOIRUT`/`GD_CHUYENTIEN` bên đối tác, nhưng thao tác **write** chỉ là `DELETE FROM TaiKhoan` local (Merge Replication sẽ propagate xóa sang site kia). Do đó dùng `BEGIN TRANSACTION` local, không cần DTC. Xem [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md) §12b.

### 6.3. Yêu cầu bắt buộc trong SP dùng DTC

```sql
SET NOCOUNT ON;
SET XACT_ABORT ON;           -- BẮT BUỘC: mọi lỗi runtime → tự ROLLBACK
BEGIN TRY
    BEGIN DISTRIBUTED TRANSACTION;
    -- ... UPDATE/INSERT local
    -- ... UPDATE/INSERT qua [LINK1]
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
    RAISERROR(@ErrMsg, 16, 1);
END CATCH
```

### 6.4. Điều kiện môi trường

- Dịch vụ **MSDTC** phải `Running` trên **tất cả instance tham gia**.
- Cấu hình MSDTC: **Network DTC Access = Allow** (Inbound + Outbound).
- Tường lửa cho phép **port 135** (RPC endpoint mapper) + **dynamic RPC port range**.
- Kiểm tra nhanh trên SSMS: `SELECT * FROM sys.dm_tran_current_transaction;` sau `BEGIN DISTRIBUTED TRAN` — cột `is_local` phải là `0`.

### 6.5. Vì sao phải dùng `sqlcmd` thay vì driver `mssql` để gọi SP có DTC?

Driver `tedious` (dùng bởi package `mssql` trong Node.js) **không implement** giao thức MSDTC (chỉ có protocol TDS cơ bản). `sqlcmd` (Windows Native Client) hỗ trợ MSDTC đầy đủ. Vì vậy hàm `execSPAdmin` trong `db.js` gói `sqlcmd` qua `child_process.execFile` để chạy các SP có `BEGIN DISTRIBUTED TRANSACTION`. Xem chi tiết tại [`09_Database_Connection.md`](09_Database_Connection.md) §3.

---

## 7. Identity Range Management (Quản lý dải khóa phân tán)

### 7.1. Vấn đề
`GD_GOIRUT` và `GD_CHUYENTIEN` có cột `MAGD INT IDENTITY`. Nếu SQL1 và SQL2 đồng thời INSERT, cả 2 đều sinh `MAGD = 1, 2, 3...` → khi Replication đồng bộ về NGUON → **trùng khóa chính**.

### 7.2. Giải pháp
Bật **Identity Range Management** khi cấu hình Merge Replication cho các bảng có IDENTITY. SQL Server tự cấp mỗi Subscriber một dải:
- SQL1 (BENTHANH): `MAGD ∈ [1..999]` (dải sơ cấp) + `[10_001..10_999]` (dải thứ cấp, tự cấp phát khi dải sơ cấp hết)
- SQL2 (TANDINH): `MAGD ∈ [1_001..1_999]` + `[11_001..11_999]`
- NGUON: `MAGD ∈ [2_001..2_999]` (dùng cho seed dữ liệu ban đầu)

Khi dải sơ cấp còn ≤ `@threshold%` (VD 80%), SQL Server tự động cấp dải thứ cấp mới → không bao giờ chạm giới hạn.

### 7.3. Cấu hình khi tạo Article
```sql
-- Ví dụ khi thêm article GD_GOIRUT vào PUB_BENTHANH
EXEC sp_addmergearticle
    @publication = N'PUB_BENTHANH',
    @article = N'GD_GOIRUT',
    @source_object = N'GD_GOIRUT',
    @identityrangemanagementoption = N'auto',
    @pub_identity_range = 10000,
    @identity_range = 1000,
    @threshold = 80;
```

### 7.4. Ghi chú thiết kế khóa phân tán khác

- **`MANV`** — không dùng IDENTITY. App sinh với **prefix chi nhánh** (`BT001`, `TD001`) qua `sinhMANV()`. Đảm bảo toàn cục duy nhất kể cả khi chuyển NV giữa 2 CN.
- **`SOTK`** — không dùng IDENTITY. **SP tự sinh atomic** trong `sp_MoTaiKhoan` với prefix theo `@MACN` (chi nhánh sở hữu TK) và vòng WHILE retry khi PK duplicate (fix #3, 07/2026). Cross-branch: NV BT mở TK cho KH TD → SOTK có prefix `TD` (khớp `MACN=TANDINH`, không phải prefix theo NV). Route KHÔNG còn hàm `sinhSOTK()` — parse SOTK trả về từ output text của sqlcmd bằng regex.
- **`CMND`** (KhachHang PK) — không sinh tự động; do người dùng nhập, đảm bảo toàn cục duy nhất bởi nghiệp vụ (mỗi công dân có 1 CMND).

---

## 8. Cơ Chế Đồng Bộ (Sync)

1. **Khởi tạo:** Publisher tạo Snapshot ban đầu → Snapshot Agent đẩy xuống Subscriber lần đầu.
2. **Chu kỳ đồng bộ:**
   - Publisher: Log Reader Agent (với Transactional Replication) hoặc Merge Agent (với Merge Replication) theo dõi thay đổi.
   - Subscriber: Merge Agent chạy định kỳ, gọi ngược Publisher để lấy delta.
3. **Filter tại Publication:** Đảm bảo dữ liệu của BENTHANH không lọt sang TANDINH và ngược lại.
4. **Conflict resolution (Merge Replication):** Nếu 2 site cùng sửa 1 row cùng key trước khi sync → dùng **default resolver** (ưu tiên Publisher wins). Trong hệ thống này rất hiếm gặp vì `MACN` phân tách đường ghi (chỉ có site sở hữu được UPDATE).

---

## 9. Object KHÔNG được Replication đồng bộ (rất hay bị hỏi vấn đáp)

Replication chỉ đồng bộ **đối tượng cấp Database** (bảng, SP, view, function, trigger). Các đối tượng sau **KHÔNG** đồng bộ và phải tạo thủ công trên từng instance:

| Đối tượng | Cấp | Cách quản lý |
|---|---|---|
| SQL Login (`sys.server_principals`) | **Server** | Tạo tay trên mỗi instance (VD `HTKN`, `admin`, `BT001`, `1111111111`). Xem [`03_DemoAccounts.md`](03_DemoAccounts.md) §5. |
| Linked Server (`sys.servers`) | **Server** | Cấu hình tay trên mỗi instance. Xem [`10_Linked_Servers.md`](10_Linked_Servers.md). |
| Security Mapping của Linked Server (`sys.linked_logins`) | **Server** | `sp_addlinkedsrvlogin` trên mỗi instance. |
| SQL Server Agent Jobs | **Server** | Không dùng trong đồ án. |
| Server Role membership (`securityadmin`, `sysadmin`) | **Server** | Gán tay. |

> **Bài học:** Khi setup instance mới, ĐỪNG dựa vào Replication để có các object trên. Chạy các script `sql/setup/09..11_TaoTaiKhoan*.sql` trên **cả 4 instance**.
