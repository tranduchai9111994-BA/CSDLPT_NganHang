# Hướng dẫn kiểm tra 6 câu — Phân tích kỹ thuật phân tán chi tiết

> Mục tiêu: Không chỉ biết bấm nút, mà hiểu **tại sao** code chạy như vậy, **đoạn nào** thể hiện phân tán, và **trả lời phản biện** của giảng viên được.

---

## Kiến trúc nhanh — đọc trước khi làm

```
NGUON (ES-HAITD16)          ← Publisher + Distributor
  ├── SQL1 (BENTHANH)        ← Subscriber, xử lý chi nhánh Bến Thành
  ├── SQL2 (TANDINH)         ← Subscriber, xử lý chi nhánh Tân Định
  └── SQL3 (TRACUU)          ← Subscriber, tra cứu toàn hệ thống

Linked Server tại SQL1:  LINK0→NGUON,  LINK1→SQL2
Linked Server tại SQL2:  LINK0→NGUON,  LINK1→SQL1
Linked Server tại SQL3:  LINK0→NGUON,  LINK1→SQL1,  LINK2→SQL2
```

### Bảng nào nằm đâu? (quan trọng nhất khi phản biện)

| Bảng | SQL1 (BT) | SQL2 (TD) | SQL3 (TRACUU) | Loại phân tán |
|------|-----------|-----------|---------------|---------------|
| ChiNhanh | ✅ Full | ✅ Full | ❌ | Nhân bản toàn vẹn |
| KhachHang | ✅ MACN=BT | ✅ MACN=TD | ✅ Full (cả 2) | Phân mảnh ngang + Nhân bản |
| NhanVien | ✅ MACN=BT | ✅ MACN=TD | ❌ | Phân mảnh ngang |
| **TaiKhoan** | ✅ **Full** | ✅ **Full** | ❌ (đọc qua LINK1) | **Nhân bản toàn vẹn** |
| GD_GOIRUT | ✅ GD tại BT | ✅ GD tại TD | ❌ | Phân mảnh ngang |
| GD_CHUYENTIEN | ✅ CT tại BT | ✅ CT tại TD | ❌ | Phân mảnh ngang |

**Điểm hay bị hỏi:** TaiKhoan nhân bản full → mọi NV ở SQL1 đều thấy cả TK của SQL2. Nhưng chỉ được **GHI** vào TK thuộc chi nhánh mình (theo MACN). Nếu TK nhận thuộc chi nhánh khác → GHI qua LINK1.

---

## Câu 1: Chuyển tiền

**SP thực thi:** `sp_ChuyenTien`
**Server chạy SP:** SQL1 (nếu đăng nhập BT001) hoặc SQL2 (nếu đăng nhập TD001)

### Luồng phân tán — từng bước trong SP

```sql
-- BƯỚC 1: Đọc MACN của TK chuyển (local, luôn là của mình)
SELECT @MACN_CHUYEN = RTRIM(MACN)
FROM TaiKhoan
WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
```
> **Tại sao đọc local được?** TaiKhoan được nhân bản toàn vẹn → SQL1 có sẵn bản copy của tất cả TK cả 2 chi nhánh. Không cần Linked Server.

```sql
-- BƯỚC 2: Đọc MACN của TK nhận (cũng đọc local, cùng lý do)
SELECT @MACN_NHAN = RTRIM(MACN)
FROM TaiKhoan
WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);

IF @MACN_NHAN IS NULL
    RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.', 16, 1);
```
> **Tại sao không cần LINK1 để kiểm tra TK nhận?** Vì nhân bản full — TK của TANDINH cũng có copy trên SQL1. Nếu `@MACN_NHAN IS NULL` thì TK đó không tồn tại ở bất kỳ đâu trong hệ thống.

```sql
-- BƯỚC 3: ĐÂY LÀ ĐOẠN PHÂN TÁN QUAN TRỌNG NHẤT
-- So sánh MACN để quyết định ghi ở đâu
DECLARE @IsNhanLocal bit = 0;
IF @MACN_NHAN = @MACN_CHUYEN      -- cùng chi nhánh?
    SET @IsNhanLocal = 1;          -- ghi local
-- khác chi nhánh → IsNhanLocal = 0 → ghi qua LINK1
```
> **Giảng viên hay hỏi:** "Tại sao không dùng EXISTS để check TK nhận ở local hay không?"  
> **Trả lời:** Vì TaiKhoan nhân bản full nên EXISTS luôn = TRUE, không phân biệt được TK đó thuộc chi nhánh nào. Phải so sánh MACN — đó là cách duy nhất đúng khi nhân bản toàn vẹn.

```sql
-- BƯỚC 4: Thực hiện giao dịch phân tán
BEGIN DISTRIBUTED TRANSACTION;

-- Trừ tiền TK chuyển (luôn local — TK chuyển là của mình)
UPDATE TaiKhoan
SET SODU = SODU - @SOTIEN
WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN)
  AND SODU >= @SOTIEN;     -- ← Kiểm tra số dư ATOMIC trong cùng UPDATE

IF @@ROWCOUNT = 0          -- UPDATE không ảnh hưởng dòng nào = số dư không đủ
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR(N'Số dư không đủ.', 16, 1);
    RETURN;
END
```
> **Điểm hay hỏi:** "Tại sao kiểm tra số dư trong WHERE thay vì IF trước?"  
> **Trả lời:** Đây là kỹ thuật **atomic check-and-update**. Nếu dùng IF riêng thì giữa lúc check và lúc UPDATE, có thể thread khác cũng rút tiền làm số dư thay đổi (race condition). Nhét điều kiện vào WHERE + check @@ROWCOUNT là cách chuẩn để tránh race condition, không cần lock thêm.

```sql
-- BƯỚC 5: Cộng tiền TK nhận — ĐÂY LÀ ĐIỂM PHÂN TÁN THỰC SỰ
IF @IsNhanLocal = 1
BEGIN
    -- Cùng chi nhánh: UPDATE local
    UPDATE TaiKhoan
    SET SODU = SODU + @SOTIEN
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
END
ELSE
BEGIN
    -- Khác chi nhánh: UPDATE qua Linked Server sang site đối tác
    UPDATE [LINK1].NGANHANG.dbo.TaiKhoan
    SET SODU = SODU + @SOTIEN
    WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
END

-- Ghi log (luôn ghi local — giao dịch xảy ra tại chi nhánh mình)
INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

COMMIT TRANSACTION;
```

### Tại sao BEGIN DISTRIBUTED TRANSACTION (không phải BEGIN TRANSACTION thường)?

`DISTRIBUTED TRANSACTION` kích hoạt **MSDTC (Microsoft Distributed Transaction Coordinator)**. MSDTC thực hiện **2-Phase Commit (2PC)**:

```
Phase 1 - PREPARE:
  MSDTC hỏi SQL1: "Mày sẵn sàng commit chưa?" → SQL1: "Sẵn sàng"
  MSDTC hỏi SQL2: "Mày sẵn sàng commit chưa?" → SQL2: "Sẵn sàng"

Phase 2 - COMMIT:
  Tất cả đồng ý → MSDTC ra lệnh COMMIT cả 2
  
Nếu SQL2 sập ở Phase 1:
  SQL2 không trả lời → MSDTC timeout → ra lệnh ROLLBACK cả SQL1 lẫn SQL2
  → Tiền không mất
```

### Tại sao Node.js dùng sqlcmd thay vì thư viện mssql thông thường?

Thư viện `mssql` (dùng driver tedious) không hỗ trợ `BEGIN DISTRIBUTED TRANSACTION`. Khi SP chạy lệnh này, tedious bị lỗi "distributed transaction not supported". Giải pháp: dùng `sqlcmd` (SQL Server Native Client) qua `child_process.execFile` trong Node.js — `sqlcmd` hỗ trợ MSDTC đầy đủ.

### Cách kiểm tra khi demo

```sql
-- Trước khi chuyển (chạy trên SQL1):
SELECT SOTK, SODU, MACN FROM TaiKhoan WHERE SOTK IN ('BT0000001','TD0000001');

-- Thực hiện chuyển tiền trên app

-- Sau khi chuyển (chạy trên SQL1):
SELECT SOTK, SODU, MACN FROM TaiKhoan WHERE SOTK IN ('BT0000001','TD0000001');
-- Cả 2 TK đều thấy được do nhân bản full → chứng minh nhân bản hoạt động

-- Xem log giao dịch (SQL1):
SELECT TOP 3 * FROM GD_CHUYENTIEN ORDER BY NGAYGD DESC;

-- Xác nhận SQL2 cũng cập nhật đúng (chạy trên SQL2):
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'TD0000001';
```

### Câu hỏi phản biện thường gặp

| Câu hỏi | Trả lời ngắn |
|---------|--------------|
| TaiKhoan nhân bản full thì dữ liệu ở SQL1 và SQL2 có giống nhau không? | Có — nhưng phải chờ Replication sync (vài giây). Trong thời gian đó có thể thấy lệch. |
| Nếu LINK1 đứt thì chuyển tiền khác chi nhánh sẽ thế nào? | SP lỗi ở dòng UPDATE [LINK1]... → CATCH bắt → ROLLBACK → tiền không bị trừ. |
| Sao không ghi GD_CHUYENTIEN ở SQL2 luôn? | Giao dịch xảy ra tại SQL1 (BT001 thực hiện), nên log ghi tại SQL1. SQL2 biết thông qua Replication hoặc LINK1 nếu cần báo cáo tổng hợp. |
| SET XACT_ABORT ON để làm gì? | Bắt mọi lỗi runtime → tự động ROLLBACK ngay, không để transaction treo. Bắt buộc khi dùng DISTRIBUTED TRANSACTION. |

---

## Câu 2: Liệt kê khách hàng

**SP thực thi:** `sp_LietKeKhachHang`
- Khi đăng nhập là **ChiNhanh** (BT001 trên SQL1): truyền `@MACN = 'BENTHANH'` → chỉ SELECT KhachHang local có MACN khớp
- Khi đăng nhập là **NganHang** (admin trên SQL3 — TRACUU): truyền `@MACN = NULL` → SELECT trực tiếp từ bảng KhachHang local trên TRACUU (đã có full dữ liệu cả 2 chi nhánh nhờ nhân bản toàn vẹn)

### Tại sao TRACUU có full KhachHang?

Publication `PUB_TRACUU` replicate bảng `KhachHang` **không có filter** → toàn bộ KH từ NGUON được đẩy xuống SQL3. Khi chi nhánh thêm KH mới → Merge Agent sync lên NGUON → NGUON đẩy xuống SQL3.

### SP hoạt động thế nào?

Trên **TRACUU (SQL3)**: KhachHang đã có local (nhân bản full) → chỉ cần `SELECT ... FROM KhachHang WHERE ...` — không cần UNION qua Linked Server.

Trên **chi nhánh (SQL1/SQL2)**: KhachHang là phân mảnh ngang → `WHERE MACN = @MACN` chỉ thấy KH của mình.

> **So sánh với NhanVien/TaiKhoan:** Các bảng đó KHÔNG được replicate xuống TRACUU → SP trên TRACUU phải dùng `UNION ALL LINK1 + LINK2`. KhachHang thì đã có sẵn → đọc trực tiếp, hiệu quả hơn.

### Luồng phân tán

SP được tạo trên **NGUON**, Replication tự đẩy xuống SQL1, SQL2, SQL3. Cùng 1 SP nhưng kết quả khác nhau tùy dữ liệu local của mỗi site:

```
ChiNhanh (BT001 trên SQL1):
  EXEC sp_LietKeKhachHang @MACN = 'BENTHANH'
  → SELECT ... FROM KhachHang WHERE MACN = 'BENTHANH'
  → Đọc local (phân mảnh ngang), chỉ thấy KH của mình

NganHang (admin trên SQL3 — TRACUU):
  EXEC sp_LietKeKhachHang @MACN = NULL
  → SELECT ... FROM KhachHang (không WHERE MACN)
  → Đọc local trên TRACUU, thấy KH CẢ 2 chi nhánh ← nhân bản toàn vẹn đang hoạt động
```

### Cách kiểm tra khi demo

```sql
-- Trên SQL1 (đăng nhập BT001 — chi nhánh):
EXEC sp_LietKeKhachHang @MACN = 'BENTHANH';  -- chỉ thấy KH chi nhánh mình

-- Trên SQL3 (đăng nhập admin — ngân hàng):
EXEC sp_LietKeKhachHang @MACN = NULL;  -- thấy cả BENTHANH và TANDINH
SELECT COUNT(*), MACN FROM KhachHang GROUP BY MACN;  -- xác nhận có đủ 2 CN
```

### Câu hỏi phản biện

| Câu hỏi | Trả lời ngắn |
|---------|--------------|
| Sao KhachHang đọc local trên TRACUU mà NhanVien lại phải UNION qua LINK? | Vì KhachHang được replicate full xuống TRACUU (PUB_TRACUU có article KhachHang). NhanVien và TaiKhoan KHÔNG có trong publication → TRACUU không có local → phải đọc qua LINK1+LINK2. |
| Nếu thêm KH mới ở BENTHANH, bao lâu thì TRACUU thấy? | Phụ thuộc Merge Agent sync interval, thường 1–5 phút. Nếu cần ngay, trigger sync thủ công trên SSMS. |
| Phân mảnh ngang KhachHang vi phạm tính tách biệt (Disjointness) không? | Có vi phạm có kiểm soát: KH được lưu ở mảnh riêng (SQL1 hoặc SQL2), nhưng đồng thời nhân bản lên TRACUU. Đây là đánh đổi giữa tính nhất quán và hiệu năng tra cứu — chấp nhận được theo yêu cầu đề bài. |

---

## Câu 3: Chuyển nhân viên

**SP thực thi:** `sp_ChuyenNhanVien`
**Server chạy SP:** SQL1 (BT001 đang quản lý NV cần chuyển)

### Luồng phân tán

```sql
-- BƯỚC 1: Kiểm tra NV có tồn tại và đang làm việc không (local)
IF NOT EXISTS (
    SELECT 1 FROM NhanVien
    WHERE RTRIM(MANV) = RTRIM(@MANV) AND TrangThaiXoa = 0
)
    RAISERROR('NV không tồn tại hoặc đã nghỉ việc', 16, 1);
```
> NhanVien phân mảnh ngang → SQL1 chỉ có NV của BENTHANH. Nếu check NV ở chi nhánh khác → không thấy → lỗi. Đây là hành vi đúng: NV của TANDINH phải do TD001 quản lý.

```sql
-- BƯỚC 2: Tạo MANV mới với prefix chi nhánh đích
-- Ví dụ chuyển sang TANDINH → prefix = 'TD'
-- MAX(MANV) LIKE 'TD%' trên SQL2 (qua LINK1) → sinh TD004, TD005...
DECLARE @MANV_MOI nchar(10);
-- Logic sinh MANV mới (trong app, trước khi gọi SP)
```
> **Điểm hay hỏi:** Tại sao phải đổi MANV? Vì nếu giữ nguyên BT001 ở TANDINH → khi sync Replication về NGUON sẽ trùng khóa chính với NV khác. Prefix BT/TD đảm bảo tính duy nhất toàn cục.

```sql
-- BƯỚC 3: DISTRIBUTED TRANSACTION — xóa mềm NV ở local, insert sang đối tác
BEGIN DISTRIBUTED TRANSACTION;

-- Xóa mềm ở chi nhánh cũ (local)
UPDATE NhanVien
SET TrangThaiXoa = 1
WHERE RTRIM(MANV) = RTRIM(@MANV);

-- Insert sang chi nhánh mới (qua Linked Server)
INSERT INTO [LINK1].NGANHANG.dbo.NhanVien
    (MANV, HO, TEN, CMND, SODT, MACN, TrangThaiXoa)
VALUES
    (@MANV_MOI, @HO, @TEN, @CMND, @SODT, @MACN_MOI, 0);

COMMIT TRANSACTION;
```

### Câu hỏi phản biện

| Câu hỏi | Trả lời ngắn |
|---------|--------------|
| Tại sao xóa mềm (TrangThaiXoa=1) thay vì DELETE? | DELETE sẽ bị Replication đồng bộ xóa ở tất cả site. Xóa mềm giữ lại lịch sử, Replication vẫn hoạt động bình thường. |
| MANV mới ở TANDINH có xung đột không? | Không — sinh MANV mới với prefix TD, lấy MAX(MANV) LIKE 'TD%' tại SQL2 qua LINK1. Luôn duy nhất trong không gian TANDINH. |
| Nếu LINK1 đứt thì sao? | INSERT [LINK1]... lỗi → CATCH bắt → ROLLBACK → TrangThaiXoa được hoàn về 0 → NV vẫn ở chi nhánh cũ, không mất. |

---

## Câu 4: Chuyển nhân viên khác chi nhánh → Sao kê tài khoản

> Đề bài thường hỏi: "Liệt kê sao kê GD của 1 TK trong khoảng thời gian"

**SP thực thi:** `SP_SaoKeTaiKhoan`
**Tham số:** `@SOTK`, `@TUNGAY`, `@DENNGAY`

### Thuật toán — phân tích từng bước

#### Bước 1: Lấy số dư hiện tại

```sql
SELECT @SODU_HIENTAI = SODU
FROM TaiKhoan
WHERE RTRIM(SOTK) = RTRIM(@SOTK);
```
> Đọc local. TaiKhoan nhân bản full → luôn có.

#### Bước 2: Tính số dư ĐẦUKY bằng kỹ thuật "trừ ngược"

```sql
-- Gom TẤT CẢ giao dịch từ @TUNGAY đến NAY (không phải đến @DENNGAY)
-- Lý do: phải biết tổng biến động từ @TUNGAY đến hiện tại để tính ngược

-- GD_GOIRUT từ local + SQL2 (qua LINK1)
-- GD_CHUYENTIEN từ local + SQL2 (qua LINK1)

DECLARE @SODU_DAUKY money;
SELECT @SODU_DAUKY = @SODU_HIENTAI
    - ISNULL(SUM(
        CASE LOAIGD
            WHEN 'GT' THEN SOTIEN    -- Gửi = cộng vào TK → khi trừ ngược = trừ đi
            WHEN 'RT' THEN -SOTIEN   -- Rút = trừ khỏi TK → khi trừ ngược = cộng lại
        END
    ), 0)
FROM (
    -- GD gửi/rút từ local
    SELECT LOAIGD, SOTIEN FROM GD_GOIRUT
    WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND NGAYGD >= @TUNGAY

    UNION ALL

    -- GD gửi/rút từ chi nhánh đối tác (qua LINK1)
    SELECT LOAIGD, SOTIEN FROM [LINK1].NGANHANG.dbo.GD_GOIRUT
    WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND NGAYGD >= @TUNGAY

    UNION ALL

    -- GD chuyển tiền (cộng tiền vào TK này)
    SELECT 'CT_NHAN', SOTIEN FROM GD_CHUYENTIEN
    WHERE RTRIM(SOTK_NHAN) = RTRIM(@SOTK) AND NGAYGD >= @TUNGAY

    UNION ALL
    -- ... tương tự LINK1
) AS AllGD;
```
> **Tại sao tính lùi thay vì cộng dồn từ đầu?** Nếu cộng từ ngày mở TK, phải đọc toàn bộ lịch sử — có thể hàng nghìn GD qua Linked Server. Tính lùi từ ngày yêu cầu → chỉ cần kéo dữ liệu trong khoảng thời gian ngắn → nhanh hơn, ít IO mạng hơn.

#### Bước 3: Số dư lũy kế từng dòng — Window Function

```sql
-- Trong khoảng [@TUNGAY, @DENNGAY], mỗi dòng có SODU_LUYKE = số dư sau GD đó
SELECT
    NGAYGD,
    LOAIGD,
    SOTIEN,
    SODU_LUYKE = @SODU_DAUKY + SUM(BiendDong) OVER (
        ORDER BY NGAYGD ASC
        ROWS UNBOUNDED PRECEDING    -- cộng từ dòng đầu đến dòng hiện tại
    )
FROM TransactionsInPeriod;
```
> `ROWS UNBOUNDED PRECEDING` nghĩa là: tính tổng từ dòng đầu tiên đến dòng hiện tại. SQL Server tính trong 1 lần quét, không cần vòng lặp.

### Cách kiểm tra khi demo

```sql
-- Chạy thẳng SP để xem kết quả:
EXEC SP_SaoKeTaiKhoan
    @SOTK = 'BT0000001',
    @TUNGAY = '2024-01-01',
    @DENNGAY = '2026-12-31';

-- Kiểm tra thủ công số dư đầu kỳ đúng không:
SELECT SODU FROM TaiKhoan WHERE SOTK = 'BT0000001'; -- số dư hiện tại
SELECT SUM(SOTIEN) FROM GD_GOIRUT WHERE SOTK='BT0000001' AND NGAYGD>='2024-01-01'; -- tổng gửi/rút từ @TUNGAY
```

### Câu hỏi phản biện

| Câu hỏi | Trả lời ngắn |
|---------|--------------|
| Tại sao cần UNION ALL với LINK1? | GD của TK BT0000001 có thể xảy ra ở cả 2 server. Ví dụ ai đó từ TANDINH chuyển tiền đến BT0000001 → GD_CHUYENTIEN ở SQL2 (LINK1). Phải gộp để không thiếu GD. |
| UNION ALL hay UNION? | UNION ALL — vì GD không trùng nhau giữa 2 server (mỗi GD chỉ ghi 1 nơi). Dùng UNION thì chậm hơn do phải loại trùng. |
| Nếu TK mở ở BT nhưng thực hiện giao dịch ở TD thì GD lưu ở đâu? | GD lưu tại nơi NV thực hiện (theo MANV). Nếu NV ở TD chuyển tiền cho TK BT → GD_CHUYENTIEN lưu ở SQL2. Sao kê của TK BT phải query qua LINK1 sang SQL2 để thấy. |

---

## Câu 5: Gửi tiền / Rút tiền

**SP thực thi:** `sp_GuiTien`, `sp_RutTien`
**Server chạy:** SQL1 hoặc SQL2 (tùy chi nhánh đăng nhập)

### Đây là nghiệp vụ ĐƠN GIẢN NHẤT về phân tán

Gửi và rút chỉ thao tác trên **1 server** (local). Không cần DISTRIBUTED TRANSACTION, không cần LINK1.

### sp_GuiTien — phân tích

```sql
-- Validate số tiền tối thiểu
IF @SOTIEN < 100000
    RAISERROR(N'Số tiền gửi tối thiểu là 100,000 VNĐ.', 16, 1);

-- Validate TK tồn tại (local — TaiKhoan nhân bản full)
IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE SOTK = @SOTK)
    RAISERROR(N'Tài khoản không tồn tại.', 16, 1);

BEGIN TRANSACTION;  -- ← Transaction thường, không cần DISTRIBUTED

UPDATE TaiKhoan SET SODU = SODU + @SOTIEN WHERE SOTK = @SOTK;

INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
VALUES (@SOTK, 'GT', GETDATE(), @SOTIEN, @MANV);

COMMIT TRANSACTION;
```

### sp_RutTien — điểm đặc biệt

```sql
-- Rút tiền: điều kiện SODU >= @SOTIEN trong WHERE — atomic check
UPDATE TaiKhoan
SET SODU = SODU - @SOTIEN
WHERE SOTK = @SOTK AND SODU >= @SOTIEN;  -- ← Không bao giờ âm số dư

IF @@ROWCOUNT = 0
    RAISERROR(N'Số dư không đủ hoặc TK không tồn tại.', 16, 1);
```

### Tại sao gửi/rút không cần DISTRIBUTED TRANSACTION?

Vì toàn bộ thao tác nằm trên 1 server. `BEGIN DISTRIBUTED TRANSACTION` chỉ cần khi có thao tác trên 2+ SQL Server khác nhau trong cùng 1 transaction. Dùng thừa DISTRIBUTED TRANSACTION không sai nhưng chậm hơn (phải kích hoạt MSDTC).

### Cách kiểm tra khi demo

```sql
-- Trước khi gửi:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'BT0000001';

-- Sau khi gửi 500,000:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'BT0000001';
-- SODU phải tăng đúng 500,000

-- Kiểm tra nhân bản: xem SQL2 có SODU đã sync chưa (sau vài giây)
-- Chạy trên SQL2:
SELECT SOTK, SODU FROM TaiKhoan WHERE SOTK = 'BT0000001';
-- Phải bằng giá trị trên SQL1 (sau khi Replication sync)

-- Xem GD:
SELECT TOP 3 * FROM GD_GOIRUT WHERE SOTK='BT0000001' ORDER BY NGAYGD DESC;
```

### Câu hỏi phản biện

| Câu hỏi | Trả lời ngắn |
|---------|--------------|
| Gửi tiền xong, TK đó ở SQL2 có thấy số dư mới không? | Thấy — nhưng sau khi Replication sync (vài giây đến vài phút). Replication không realtime. |
| Tại sao không dùng Trigger để tự động cập nhật? | Trigger trên bảng nhân bản Replication sẽ bị Replication ghi đè ở chu kỳ sync tiếp theo. Không nên dùng Trigger trên bảng tham gia Replication. |
| Nếu 2 NV cùng rút tiền từ TK này cùng lúc thì sao? | SQL Server dùng row-level locking. `UPDATE WHERE SODU >= @SOTIEN` → 1 trong 2 UPDATE sẽ được lock trước, cái kia chờ. Sau khi cái đầu commit, cái sau chạy lại — nếu SODU không đủ thì @@ROWCOUNT=0 → RAISERROR. |

---

## Câu 6: Liệt kê tài khoản 2 chi nhánh

**SP thực thi:** `sp_DanhSachTaiKhoan` (chạy trên SQL3 - TRACUU)
**Ai dùng:** Nhóm NganHang (admin đăng nhập TRACUU)

### Tại sao chạy trên TRACUU?

TRACUU là server tra cứu tổng hợp. NganHang cần xem TK của cả 2 chi nhánh. TaiKhoan nhân bản toàn vẹn → SQL1 đã có full data cả 2 CN → chỉ cần đọc từ LINK1, **không cần UNION ALL LINK1+LINK2** (sẽ bị duplicate).

### Luồng phân tán

```sql
-- SP sp_DanhSachTaiKhoan trên SQL3
-- TaiKhoan replicate full → SQL1 đã có đủ → chỉ cần LINK1
SELECT
    tk.SOTK, tk.SODU, tk.MACN, tk.NGAYMOTK,
    kh.HO + ' ' + kh.TEN AS HOTEN
FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
-- ↑ OUTER APPLY TOP 1: tránh duplicate nếu KhachHang có nhiều row cùng CMND
ORDER BY tk.NGAYMOTK DESC;
```

> **Điểm quan trọng:** TaiKhoan nhân bản full → SQL1 và SQL2 đều có copy của nhau. Nếu UNION ALL LINK1+LINK2 sẽ bị **duplicate đúng 2 lần**. Giải pháp: chỉ đọc từ 1 site (LINK1) là đủ.

### sp_LietKeTaiKhoanTheoNgay — phiên bản TRACUU

```sql
-- Lọc TK mở trong khoảng thời gian, chỉ đọc từ LINK1 (đã có full data)
SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
       RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
       tk.SODU, RTRIM(tk.MACN) AS MACN,
       CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
  AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
  AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
ORDER BY tk.NGAYMOTK DESC;
```

### Cách kiểm tra khi demo

```sql
-- Đăng nhập admin/TRACUU trên app

-- Kiểm tra LINK1 và LINK2 hoạt động trước:
SELECT TOP 1 * FROM [LINK1].NGANHANG.dbo.TaiKhoan;
SELECT TOP 1 * FROM [LINK2].NGANHANG.dbo.TaiKhoan;

-- Gọi SP trực tiếp:
EXEC sp_DanhSachTaiKhoan;

-- Kiểm tra liệt kê theo ngày:
EXEC sp_LietKeTaiKhoanTheoNgay @TUNGAY='2024-01-01', @DENNGAY='2026-12-31';
```

### Câu hỏi phản biện

| Câu hỏi | Trả lời ngắn |
|---------|--------------|
| Tại sao không tạo View thay vì SP? | View cũng được, nhưng SP linh hoạt hơn (có thể nhận tham số lọc). Hơn nữa SP dễ phân quyền hơn View qua GRANT EXECUTE. |
| TRACUU không có bảng TaiKhoan thì JOIN với gì? | TK đến từ LINK1 (TaiKhoan replicate full nên LINK1 đã có đủ). JOIN với KhachHang local (OUTER APPLY TOP 1). |
| Tại sao chỉ đọc LINK1 mà không UNION ALL LINK1+LINK2? | TaiKhoan nhân bản full → SQL1 đã chứa TK cả 2 CN. Nếu UNION ALL sẽ bị duplicate đúng 2 lần. Chỉ cần LINK1 là đủ. |
| Tại sao dùng OUTER APPLY TOP 1 thay vì LEFT JOIN? | KhachHang trên TRACUU có thể có nhiều row cùng CMND. OUTER APPLY TOP 1 chỉ lấy 1, tránh nhân bản kết quả. |
| Nếu thêm chi nhánh thứ 3 thì sao? | TaiKhoan vẫn replicate full nên LINK1 vẫn đủ. Nhưng GD_GOIRUT/GD_CHUYENTIEN thì cần thêm LINK3 vào UNION ALL. |

---

## Checklist tự đánh giá trước bảo vệ

### Hiểu lý thuyết

- [ ] Giải thích được phân mảnh ngang (Horizontal Fragmentation) là gì, áp dụng cho bảng nào
- [ ] Giải thích được nhân bản toàn vẹn (Full Replication) là gì, áp dụng cho bảng nào và tại sao
- [ ] Giải thích được tại sao TaiKhoan nhân bản full nhưng vẫn ghi qua LINK1
- [ ] Giải thích được MSDTC và 2-Phase Commit bằng ví dụ đơn giản
- [ ] Giải thích được tại sao so sánh MACN (không dùng EXISTS) trong sp_ChuyenTien
- [ ] Giải thích được kỹ thuật "tính lùi số dư đầu kỳ" trong SP_SaoKeTaiKhoan

### Thực hành được

- [ ] Đăng nhập BT001/BENTHANH → chuyển tiền cùng CN thành công
- [ ] Đăng nhập BT001/BENTHANH → chuyển tiền khác CN (sang TANDINH) thành công
- [ ] Kiểm tra SQL trực tiếp: SODU cập nhật đúng trên cả SQL1 và SQL2
- [ ] Đăng nhập admin/TRACUU → xem danh sách KH cả 2 CN
- [ ] Đăng nhập admin/TRACUU → xem danh sách TK cả 2 CN qua SP
- [ ] Chạy SP_SaoKeTaiKhoan trực tiếp trên SSMS, giải thích từng cột kết quả
- [ ] Kiểm tra Replication: thêm KH → sync → xuất hiện trên TRACUU

### Trả lời phản biện được

- [ ] Tại sao dùng MACN thay vì EXISTS để kiểm tra TK nhận?
- [ ] Nếu LINK1 đứt giữa chừng khi chuyển tiền thì sao?
- [ ] Tại sao ghi GD_CHUYENTIEN ở SQL1 thay vì SQL2?
- [ ] Tại sao Node.js dùng sqlcmd thay vì thư viện mssql?
- [ ] TaiKhoan nhân bản full → 2 server có luôn đồng bộ không?
- [ ] Tại sao TRACUU không có NhanVien nhưng vẫn báo cáo được NV?
- [ ] 3 quy tắc phân mảnh (Completeness, Reconstruction, Disjointness) — vi phạm quy tắc nào?

---

## Tóm tắt nhanh — học trong 10 phút cuối

| Câu | SP chính | Server chạy | Có qua LINK không? | Loại transaction |
|-----|----------|------------|-------------------|-----------------|
| Chuyển tiền | sp_ChuyenTien | SQL1 hoặc SQL2 | Có (nếu khác CN) | DISTRIBUTED |
| Liệt kê KH | sp_DanhSachKH | SQL1/SQL2 (CN) hoặc SQL3 (admin) | Không (local) | Không có |
| Chuyển NV | sp_ChuyenNhanVien | SQL1 hoặc SQL2 | Có (INSERT sang CN mới) | DISTRIBUTED |
| Sao kê TK | SP_SaoKeTaiKhoan | SQL1 hoặc SQL2 | Có (LINK1 để gom GD) | Không có |
| Gửi/Rút tiền | sp_GuiTien/RutTien | SQL1 hoặc SQL2 | Không (local) | Thường |
| Liệt kê TK 2 CN | sp_DanhSachTaiKhoan | **SQL3 (TRACUU)** | **Có (LINK1+LINK2)** | Không có |

**Điểm phân tán cốt lõi cần thuộc:**
1. `sp_ChuyenTien` — so sánh MACN quyết định ghi local hay [LINK1] → MSDTC 2PC
2. TaiKhoan nhân bản full → đọc local, ghi tại site sở hữu
3. TRACUU xem tổng hợp → gọi LINK1+LINK2, JOIN KhachHang local
4. Giao dịch gửi/rút → local only, không cần DISTRIBUTED TRANSACTION
