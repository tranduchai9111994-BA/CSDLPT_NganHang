# 🎯 Bộ Câu Hỏi Vấn Đáp — Ôn Thi CSDL Phân Tán (Đề Ngân Hàng)

> **Cách dùng:** Đọc câu hỏi → che phần trả lời → tự trả lời → so sánh.  
> **Mẹo:** Giảng viên thường hỏi theo chuỗi. VD: hỏi phân mảnh → hỏi tiếp linked server → hỏi tiếp distributed transaction. Nên ôn theo cụm, không ôn lẻ.

---

## CỤM 1: PHÂN MẢNH DỮ LIỆU (7 câu)

### 1.1. Hệ thống của em dùng kiểu phân mảnh gì? Tại sao?

**Trả lời:** Phân mảnh ngang (Horizontal Fragmentation), dựa trên cột `MACN` (mã chi nhánh). Tức là mỗi dòng dữ liệu sẽ nằm ở chi nhánh nào tùy thuộc vào giá trị MACN của nó. Ví dụ dòng nào có MACN = 'BENTHANH' thì nằm ở SQL1, MACN = 'TANDINH' thì nằm ở SQL2.

Chọn phân mảnh ngang vì nghiệp vụ ngân hàng phân chia theo chi nhánh — mỗi chi nhánh xử lý giao dịch của riêng mình, ít khi cần truy cập dữ liệu chi nhánh khác.

### 1.2. Bảng nào được phân mảnh, bảng nào không?

**Trả lời:** 
- **Phân mảnh ngang:** KhachHang, NhanVien, GD_GOIRUT, GD_CHUYENTIEN — đều theo MACN.
- **Nhân bản toàn vẹn (Replicate Full):** `ChiNhanh` (danh mục tham chiếu) và `TaiKhoan` (để mỗi site có thể kiểm tra sự tồn tại TK đích ngay local khi chuyển tiền, không cần gọi Linked Server để SELECT).
- **Trường hợp đặc biệt:** KhachHang được replicate full sang TRACUU (SQL3) để phục vụ tra cứu toàn cục.

### 1.3. Tại sao TaiKhoan lại nhân bản toàn vẹn thay vì phân mảnh như KhachHang/NhanVien?

**Trả lời:** Nhân bản toàn vẹn `TaiKhoan` mang lại 2 lợi ích:

1. **Kiểm tra nhanh khi chuyển tiền:** SP `sp_ChuyenTien` cần xác minh TK nhận có tồn tại hay không. Nếu TaiKhoan được replicate full, mọi TK đều có bản copy local → SELECT kiểm tra không cần qua Linked Server → nhanh.
2. **Tra cứu linh hoạt:** Nhân viên có thể xem thông tin bất kỳ TK nào trong hệ thống từ site local.

**Quy tắc ĐỌC/GHI cho bảng nhân bản:**
- **Đọc:** Đọc local (nhanh, không tốn mạng).
- **Ghi:** Chỉ ghi tại **site sở hữu** (site có MACN trùng với MACN của TK đó). Nếu TK thuộc chi nhánh khác → GHI qua `[LINK1]` (Linked Server) để cập nhật vào site chủ sở hữu, Replication sẽ đồng bộ ngược lại.

**SP phải phân biệt bằng MACN, không bằng EXISTS:** Vì TK luôn tồn tại local (do replicate), SP `sp_ChuyenTien` kiểm tra `MACN` của TK nhận so với MACN chi nhánh hiện tại để quyết định ghi local hay qua LINK1.

### 1.4. Bảng GD_GOIRUT và GD_CHUYENTIEN không có cột MACN, vậy phân mảnh theo gì?

**Trả lời:** Hai bảng giao dịch này cố tình không có MACN. Giao dịch thuộc chi nhánh nào được xác định gián tiếp qua 2 cách:
1. Qua cột `MANV` — nhân viên nào thực hiện thì giao dịch thuộc chi nhánh của nhân viên đó.
2. Qua mảnh phân tán — giao dịch được INSERT vào mảnh nào thì thuộc chi nhánh đó.

Việc thêm MACN vào bảng giao dịch là **sai thiết kế** vì tạo dư thừa dữ liệu (data redundancy).

### 1.5. Trạm TRACUU chứa những gì? Tại sao chỉ chứa bảng KhachHang?

**Trả lời:** TRACUU chỉ replicate full bảng KhachHang của cả 2 chi nhánh. Không chứa bảng giao dịch.

Lý do: TRACUU phục vụ nhóm NganHang (Ban Giám Đốc) để tra cứu nhanh khách hàng mà không làm ảnh hưởng hiệu năng của server đang xử lý giao dịch. Khi NganHang cần xem giao dịch, sẽ dùng Linked Server gọi sang SQL1/SQL2 thay vì lưu copy giao dịch ở TRACUU.

### 1.6. Phân mảnh ngang khác phân mảnh dọc ở điểm nào?

**Trả lời:** 
- **Phân mảnh ngang:** Chia theo hàng (dòng). Mỗi mảnh chứa một tập con các dòng. Cấu trúc cột giống nhau. → Hệ thống em dùng kiểu này.
- **Phân mảnh dọc:** Chia theo cột. Mỗi mảnh chứa một tập con các cột. Cần có khóa chính chung để ghép lại.

Đề bài này phù hợp phân mảnh ngang vì tất cả chi nhánh cần cùng cấu trúc bảng, chỉ khác tập dữ liệu.

### 1.7. Làm sao đảm bảo tính toàn vẹn khi dữ liệu nằm ở nhiều server?

**Trả lời:** Qua 3 cơ chế:
1. **Replication** đồng bộ dữ liệu giữa NGUON và các mảnh (đảm bảo dữ liệu nhất quán).
2. **Distributed Transaction + MSDTC** cho các thao tác liên chi nhánh (đảm bảo ACID).
3. **Ràng buộc CHECK tại mỗi mảnh** (ví dụ: `SODU >= 0` trên bảng TaiKhoan).

### 1.8. Nếu thêm chi nhánh thứ 3 thì cần làm gì?

**Trả lời:** Cần:
1. Tạo thêm SQL Server instance mới (ví dụ SQL4).
2. Thêm dòng mới vào bảng ChiNhanh (ví dụ MACN = 'CHOLON').
3. Cấu hình Replication mới với filter `MACN = 'CHOLON'`.
4. Tạo Linked Server từ SQL4 đến các mảnh khác.
5. Cập nhật SP `sp_ChuyenTien` để check thêm TK ở mảnh mới.

Đây là ưu điểm của phân mảnh ngang: mở rộng dễ dàng, chỉ cần thêm mảnh mới.

---

## CỤM 2: LINKED SERVER (6 câu)

### 2.1. Linked Server là gì? Tại sao cần dùng?

**Trả lời:** Linked Server là cơ chế của SQL Server cho phép 1 server truy vấn dữ liệu trên server khác như thể đang truy vấn local. Cú pháp 4 phần: `[TenLink].TenDB.dbo.TenBang`.

Cần dùng vì dữ liệu nằm phân tán ở nhiều server. Khi chi nhánh BENTHANH cần kiểm tra tài khoản nhận ở TANDINH, phải truy vấn qua Linked Server.

### 2.2. LINK0, LINK1, LINK2 trỏ đến đâu?

**Trả lời:**
- Tại SQL1 (BENTHANH): `LINK0` → NGUON (server gốc), `LINK1` → SQL2 (TANDINH — chi nhánh đối tác).
- Tại SQL2 (TANDINH): `LINK0` → NGUON, `LINK1` → SQL1 (BENTHANH — chi nhánh đối tác).
- Tại SQL3 (TRACUU): `LINK0` → NGUON, `LINK1` → SQL1 (BENTHANH), `LINK2` → SQL2 (TANDINH).

**Quy tắc:** LINK1 luôn là chi nhánh đối tác. Tuyệt đối không cấu hình loopback (trỏ về chính mình).

### 2.3. Tại sao LINK1 luôn là chi nhánh đối tác mà không dùng tên cụ thể?

**Trả lời:** Để SP có thể viết chung cho cả 2 chi nhánh. Ví dụ `sp_ChuyenTien` ở SQL1 gọi `[LINK1].NGANHANG.dbo.TaiKhoan` — đó là TANDINH. Cùng SP đó chạy ở SQL2, `[LINK1]` sẽ trỏ đến BENTHANH. Một SP dùng chung, không cần viết 2 bản khác nhau.

### 2.4. Security Mapping của Linked Server là gì?

**Trả lời:** Khi server A gọi sang server B qua Linked Server, nó cần xác thực bằng login ở phía server B. Security Mapping cấu hình login nào được dùng khi gọi qua. Hệ thống dùng login `HTKN` (password: `123`) làm credential chung cho tất cả Linked Server.

**Điểm dễ sai:** Login `HTKN` phải được tạo **thủ công trên từng server instance** vì Login là đối tượng cấp Server, không được Replication đồng bộ.

### 2.5. Gặp lỗi "Login failed for user 'HTKN'" khi gọi Linked Server thì xử lý thế nào?

**Trả lời:** Kiểm tra login HTKN ở **server đích** (nơi Linked Server trỏ tới), không phải server đang đứng. Cụ thể:
1. Kiểm tra HTKN có tồn tại và đang bật (`is_disabled = 0`) trên server đích.
2. Kiểm tra mật khẩu HTKN trên server đích có khớp với cấu hình Security Mapping không.
3. Test thử: `SELECT TOP 1 * FROM [LINK1].NGANHANG.dbo.TaiKhoan`.

### 2.6. Cú pháp 4 phần là gì? Cho ví dụ.

**Trả lời:** `[TenLinkedServer].[TenDatabase].[Schema].[TenBang]`

Ví dụ: `[LINK1].NGANHANG.dbo.TaiKhoan` — truy vấn bảng TaiKhoan trong database NGANHANG, schema dbo, trên server mà LINK1 trỏ tới.

---

## CỤM 3: DISTRIBUTED TRANSACTION & MSDTC (6 câu)

### 3.1. Distributed Transaction là gì? Khi nào cần dùng?

**Trả lời:** Là giao dịch mà các thao tác diễn ra trên 2 hay nhiều server khác nhau. Cần dùng khi thao tác phải đảm bảo ACID trên nhiều mảnh, ví dụ: chuyển tiền từ TK ở BENTHANH sang TK ở TANDINH — phải trừ tiền ở SQL1 VÀ cộng tiền ở SQL2, cả 2 phải thành công hoặc cả 2 đều rollback.

### 3.2. MSDTC là gì? Vai trò trong hệ thống?

**Trả lời:** MSDTC = Microsoft Distributed Transaction Coordinator. Là dịch vụ Windows quản lý giao dịch phân tán. Nó thực hiện giao thức **Two-Phase Commit (2PC)**:
- **Phase 1 (Prepare):** Hỏi tất cả server "sẵn sàng commit chưa?"
- **Phase 2 (Commit/Rollback):** Nếu tất cả OK → commit. Nếu bất kỳ ai fail → rollback hết.

### 3.3. Giải thích câu lệnh SET XACT_ABORT ON.

**Trả lời:** Khi bật `SET XACT_ABORT ON`, nếu bất kỳ lỗi runtime nào xảy ra (ví dụ: mất kết nối mạng, vi phạm constraint), SQL Server sẽ **tự động ROLLBACK toàn bộ transaction** thay vì để transaction treo. Đây là yêu cầu bắt buộc khi dùng `BEGIN DISTRIBUTED TRANSACTION`.

### 3.4. Nếu đang chuyển tiền mà đứt mạng giữa 2 server thì sao?

**Trả lời:** Nhờ MSDTC + `SET XACT_ABORT ON`, toàn bộ giao dịch ở cả 2 đầu sẽ tự động ROLLBACK. Tiền không bị mất, không bị sai. Cụ thể: server chuyển tiền sẽ ROLLBACK (hoàn lại số dư), server nhận tiền cũng ROLLBACK (không cộng tiền). Sau khi mạng phục hồi, nhân viên thực hiện lại giao dịch.

### 3.5. Tại sao sp_ChuyenTien luôn dùng BEGIN DISTRIBUTED TRANSACTION ngay cả khi chuyển cùng chi nhánh?

**Trả lời:** Trong code hiện tại, SP luôn dùng `BEGIN DISTRIBUTED TRAN` bất kể chuyển cùng hay khác chi nhánh. Về mặt kỹ thuật, nếu chuyển cùng chi nhánh (cả 2 TK đều local) thì chỉ cần `BEGIN TRAN` thường là đủ. Tuy nhiên dùng DISTRIBUTED TRAN không gây hại — SQL Server đủ thông minh để nhận ra khi không có thao tác remote thì nó hoạt động như local transaction.

### 3.6. Two-Phase Commit có nhược điểm gì?

**Trả lời:** Chậm hơn local transaction do phải chờ cả 2 server xác nhận. Nếu 1 server sập giữa phase 1 và phase 2, giao dịch bị treo (in-doubt transaction) cho đến khi server đó khởi động lại. Trong hệ thống nhỏ (2 chi nhánh) thì không đáng lo, nhưng hệ thống lớn (100+ chi nhánh) cần giải pháp khác (ví dụ: message queue, eventual consistency).

---

## CỤM 4: STORED PROCEDURE (7 câu)

### 4.1. Tại sao xử lý nghiệp vụ trong SP thay vì viết SQL trực tiếp trong code ứng dụng?

**Trả lời:** 
1. **An toàn:** SP chạy dưới quyền database, tránh SQL Injection.
2. **Toàn vẹn:** Logic kiểm tra số dư, ràng buộc phân tán nằm trong SP — đảm bảo luôn được thực thi bất kể ai gọi.
3. **Hiệu năng:** SP được compile 1 lần, chạy nhiều lần nhanh hơn.
4. **Tập trung:** Sửa logic 1 chỗ (SP), không phải tìm sửa ở nhiều file code.

### 4.2. Giải thích logic SP_SaoKeTaiKhoan — "tính lùi số dư đầu kỳ" là gì?

**Trả lời:** Thay vì kéo toàn bộ lịch sử giao dịch từ khi mở TK để tính cộng dồn (rất chậm, tốn network), SP lấy số dư hiện tại rồi **trừ ngược lại** tổng các biến động từ ngày yêu cầu đến nay. Công thức:

`Số dư đầu kỳ = Số dư hiện tại - SUM(biến động từ @TUNGAY đến nay)`

Sau đó dùng Window Functions (`SUM() OVER ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING`) để tính số dư lũy kế từng dòng. Cách này chỉ cần kéo dữ liệu trong khoảng thời gian yêu cầu qua Linked Server, nhanh hơn rất nhiều.

**Ví dụ cụ thể:** SODU_HIENTAI = 10tr, BIENDONG từ 01/07 đến nay = 2tr → SODU_DAUKY = 8tr

| NGAYGD | LOAIGD | SOTIEN | SODU_LUYKE | Giải thích |
|---|---|---|---|---|
| 01/07 | GT (gửi) | 5,000,000 | 13,000,000 | 8tr + 5tr |
| 05/07 | RT (rút) | 2,000,000 | 11,000,000 | 13tr - 2tr |
| 10/07 | CT (chuyển đi) | 1,000,000 | 10,000,000 | 11tr - 1tr |
| 15/07 | NT (nhận CK) | 3,000,000 | 13,000,000 | 10tr + 3tr |
| 20/07 | GT (gửi) | 2,000,000 | 15,000,000 | 13tr + 2tr |

### 4.3. sp_Login_App hoạt động thế nào?

**Trả lời:** SP nhận `@LoginName`, truy vấn `sys.database_principals` và `sys.database_role_members` để xác định user đó thuộc Role nào (NganHang, ChiNhanh, KhachHang). Sau đó:
- Nếu nhóm ChiNhanh: tìm trong bảng NhanVien để lấy MANV, HOTEN, MACN.
- Nếu nhóm KhachHang: tìm trong bảng KhachHang bằng CMND.
- Nếu nhóm NganHang: trả về thông tin cơ bản, MACN = NULL (vì NganHang xem mọi chi nhánh).

### 4.4. Tại sao sp_ChuyenTien phải check TK nhận ở cả local VÀ LINK1?

**Trả lời:** Vì TK nhận có thể nằm ở cùng chi nhánh (local) hoặc khác chi nhánh (remote). SP check local trước (`EXISTS SELECT 1 FROM TaiKhoan`), nếu không tìm thấy thì check qua LINK1 (`EXISTS SELECT 1 FROM [LINK1]...`). Nếu cả 2 đều không có → báo lỗi "TK nhận không tồn tại".

### 4.5. SP tại NGUON có khác SP tại các mảnh không?

**Trả lời:** Có. NGUON chỉ chứa 3 SP cơ bản (`sp_Login_App`, `SP_TaoTaiKhoan`, `SP_DangNhap` cũ). Các SP nghiệp vụ (GuiTien, RutTien, ChuyenTien...) chỉ cần ở SQL1 và SQL2 vì giao dịch chỉ diễn ra tại chi nhánh, không diễn ra tại server gốc. NGUON là Publisher, chỉ lưu dữ liệu gốc.

### 4.6. Không DROP được SP cũ (SP_DangNhap) tại Subscriber thì xử lý sao?

**Trả lời:** Bước đầu tiên **[Cập nhật 19/06/2026]**: Kiểm tra bằng lệnh `sp_helparticle` xem SP có thực sự là Article hay không.
Nếu nó LÀ Article (đã được đăng ký trong Publication), Replication sẽ khóa quyền DDL (DROP/ALTER) trên Subscriber. Khi đó có 2 cách:
- **Đơn giản:** Để yên, không ảnh hưởng vì code không gọi SP cũ nữa.
- **Triệt để:** Gỡ Article ra khỏi Publication tại NGUON (`sp_droparticle`), sau đó mới DROP được ở Subscriber.
Nếu kiểm tra thấy KHÔNG PHẢI Article, có thể dùng `DROP PROCEDURE IF EXISTS` trực tiếp. (Ví dụ: `SP_DangNhap` thực tế đã được xóa thành công sau khi xác nhận không phải Article).

### 4.7. Tại sao một số thao tác (sửa/xóa KH, thêm NV) dùng query trực tiếp thay vì SP?

**Trả lời:** Các thao tác đơn giản (UPDATE 1 dòng, DELETE 1 dòng tại local) không cần logic phân tán phức tạp nên dùng query trực tiếp cho nhanh. SP chỉ cần thiết khi có logic đặc biệt: kiểm tra số dư, giao dịch phân tán, ghi log, tính toán lũy kế. Tuy nhiên, nếu muốn chặt chẽ hơn, có thể tạo SP cho mọi thao tác.

---

## CỤM 5: REPLICATION (5 câu)

### 5.1. Hệ thống dùng loại Replication nào?

**Trả lời:** Hệ thống dùng **Transactional Replication** hoặc **Merge Replication** theo mô hình Publisher-Subscriber. NGUON là Publisher + Distributor, SQL1/SQL2/SQL3 là Subscriber. Dữ liệu được lọc (filter) theo MACN khi đẩy xuống từng mảnh.

### 5.2. Replication khác Linked Server ở điểm nào?

**Trả lời:** 
- **Replication:** Tự động sao chép dữ liệu giữa các server theo lịch (background). Dữ liệu ở mỗi mảnh là bản copy cục bộ, truy vấn nhanh.
- **Linked Server:** Truy vấn trực tiếp dữ liệu trên server khác theo thời gian thực (real-time). Chậm hơn vì phải qua mạng mỗi lần query.

Hệ thống dùng cả 2: Replication để đồng bộ dữ liệu nền, Linked Server để xử lý giao dịch liên chi nhánh cần real-time.

### 5.3. Identity Range Management là gì? Tại sao cần?

**Trả lời:** Khi 2 chi nhánh cùng INSERT vào bảng có cột IDENTITY (ví dụ MAGD tự tăng), nếu cả 2 đều sinh ra MAGD = 1, 2, 3... thì đồng bộ về NGUON sẽ bị trùng khóa chính.

Giải pháp: SQL Server cấp cho mỗi Subscriber một dải ID riêng. Ví dụ: SQL1 dùng 1000–1999, SQL2 dùng 2000–2999. Không bao giờ đụng độ.

### 5.4. Login có được Replication đồng bộ không?

**Trả lời:** **KHÔNG.** Login là đối tượng cấp Server (instance-level), Replication chỉ đồng bộ đối tượng cấp Database (bảng, SP, dữ liệu). Do đó login `HTKN`, `admin`, `NV01`... phải được tạo **thủ công trên từng instance**.

Đây là điểm dễ bị sót nhất khi setup, và cũng là câu hỏi vấn đáp rất hay bị hỏi.

### 5.5. Muốn sửa SP đã là Article thì phải làm ở đâu?

**Trả lời:** Chỉ được sửa tại **Publisher (NGUON)**, rồi để Replication tự đẩy xuống Subscriber. Không được ALTER trực tiếp tại Subscriber vì Replication sẽ khóa lệnh DDL để tránh lệch pha cấu trúc giữa Publisher và Subscriber.

### 5.6. PUB_TRACUU chỉ có 1 article là KhachHang. Vậy TRACUU lấy NhanVien và TaiKhoan ở đâu? [Cập nhật 30/06/2026]

**Trả lời:** TRACUU (SQL3) chỉ replicate bảng `KhachHang` để phục vụ tra cứu khách hàng toàn hệ thống. Các bảng `NhanVien`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN` **không có trên SQL3**.

Khi cần dữ liệu đó, SQL3 dùng **SP đặc thù đọc qua Linked Server**:
- `sp_DanhSachNhanVien`, `SP_DanhSachTrangThaiLogin` — UNION ALL từ `[LINK1]` + `[LINK2]` cho `NhanVien` (NhanVien **không replicate**, mỗi chi nhánh chỉ có NV của mình → phải gộp cả 2 nguồn)
- `sp_SaoKeToanBo`, `SP_SaoKeTaiKhoan` (bản TRACUU) — UNION ALL từ `[LINK1]` + `[LINK2]` cho `GD_GOIRUT`/`GD_CHUYENTIEN` (GD cũng không replicate, phân mảnh theo chi nhánh)
- `sp_DanhSachTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay` — **[Cập nhật 05/07/2026]** chỉ đọc qua `[LINK1]` (không UNION ALL LINK1+LINK2): `TaiKhoan` được replicate full giữa BENTHANH↔TANDINH nên LINK1 (trỏ BENTHANH) đã có đủ TK của cả 2 chi nhánh; UNION thêm LINK2 sẽ bị duplicate

Ưu điểm: dữ liệu **realtime** (không bị trễ Replication), TRACUU nhẹ (chỉ lưu KhachHang), phù hợp vai trò "trạm tra cứu".

### 5.7. Sau khi sửa PUB_TRACUU, các bảng cũ trên SQL3 có tự xóa không?

**Trả lời:** **KHÔNG.** Replication chỉ ngưng đồng bộ, không tự xóa bảng/dữ liệu cũ trên Subscriber. Phải DROP thủ công. Ngoài ra, subscription metadata cũ có thể bị lệch → cần `sp_removedbreplication` để dọn, rồi tạo lại subscription mới.

---

## CỤM 6: PHÂN QUYỀN (5 câu)

### 6.1. Hệ thống có mấy nhóm quyền? Mỗi nhóm được làm gì?

**Trả lời:** 3 nhóm:
- **NganHang (Ban Giám Đốc):** Chỉ đọc, xem báo cáo mọi chi nhánh, tạo TK cùng nhóm. DENY INSERT/UPDATE/DELETE.
- **ChiNhanh (Giao dịch viên):** Toàn quyền CRUD trên chi nhánh đã login. Tạo TK cùng nhóm.
- **KhachHang:** Chỉ xem sao kê TK của chính mình. Không tạo TK.

### 6.2. Bảo mật được thiết kế mấy tầng?

**Trả lời:** 3 tầng:
1. **Tầng Database:** DB Role (GRANT/DENY trên bảng + EXECUTE trên SP).
2. **Tầng Backend:** Middleware `requireRole()` chặn truy cập URL trái phép (HTTP 403).
3. **Tầng Giao diện:** Ẩn/hiện menu theo nhóm quyền bằng thẻ `if` trong EJS.

Nếu chỉ bảo mật ở UI thì người dùng có thể gõ URL trực tiếp để vượt qua. Nếu chỉ bảo mật ở Backend thì người connect trực tiếp vào SSMS có thể sửa dữ liệu. Nên cần cả 3 tầng.

### 6.3. SQL Authentication khác Windows Authentication ở chỗ nào?

**Trả lời:**
- **SQL Authentication:** Dùng username + password lưu trong SQL Server. Người dùng nào cũng có thể kết nối từ bất kỳ máy nào, chỉ cần đúng user/pass. Hệ thống em dùng cách này.
- **Windows Authentication:** Dùng tài khoản Windows (Active Directory). An toàn hơn nhưng yêu cầu cùng domain.

Đề bài yêu cầu 3 nhóm login riêng biệt nên SQL Authentication phù hợp hơn.

### 6.4. SP_TaoTaiKhoan hoạt động thế nào?

**Trả lời:** SP nhận 4 tham số: LoginName, Password, UserName, Role. Bên trong:
1. `CREATE LOGIN` — tạo tài khoản cấp Server.
2. `CREATE USER` — tạo user cấp Database, mapping với Login.
3. `sp_addrolemember` — gán user vào Role tương ứng.

SP chạy với `EXECUTE AS OWNER` để có đủ quyền tạo login (vì user thường không có quyền này).

### 6.5. NganHang muốn xem giao dịch ở TANDINH thì query đi đường nào?

**Trả lời:** NganHang login vào TRACUU (SQL3). Khi xem giao dịch:
- TRACUU dùng `[LINK2]` để gọi sang TANDINH (SQL2) lấy dữ liệu giao dịch.
- Hoặc nếu xem khách hàng, query local vì TRACUU đã có full bảng KhachHang.

---

## CỤM 7: NGHIỆP VỤ NGÂN HÀNG (5 câu)

### 7.1. Mô tả luồng chuyển tiền liên chi nhánh.

**Trả lời:** Ví dụ: NV01 tại BENTHANH chuyển 500.000đ từ TK A (BENTHANH) sang TK B (TANDINH):
1. SP `sp_ChuyenTien` được gọi tại SQL1.
2. Bật `SET XACT_ABORT ON` và `BEGIN DISTRIBUTED TRAN`.
3. Check TK A có đủ 500.000 không (local).
4. Check TK B có tồn tại không — tìm local trước, không có → tìm qua `[LINK1]` (SQL2).
5. `UPDATE TaiKhoan SET SODU = SODU - 500000` tại SQL1 (trừ tiền TK A).
6. `UPDATE [LINK1].NGANHANG.dbo.TaiKhoan SET SODU = SODU + 500000` tại SQL2 (cộng tiền TK B).
7. `INSERT INTO GD_CHUYENTIEN` ghi log tại SQL1.
8. `COMMIT TRANSACTION` — MSDTC đảm bảo cả 2 bên commit.

### 7.2. Số dư tài khoản có thể âm không?

**Trả lời:** Không. Bảng TaiKhoan có `CHECK (SODU >= 0)`. Ngoài ra SP `sp_RutTien` kiểm tra `WHERE SODU >= @SOTIEN` trước khi trừ. Nếu số dư không đủ → `@@ROWCOUNT = 0` → ROLLBACK + báo lỗi.

### 7.3. Mô tả luồng chuyển nhân viên.

**Trả lời:** Ví dụ: Chuyển NV01 từ BENTHANH sang TANDINH:
1. SP `sp_ChuyenNhanVien` được gọi tại SQL1.
2. Bật DISTRIBUTED TRAN.
3. Đọc thông tin NV01 từ bảng NhanVien (local).
4. `UPDATE TrangThaiXoa = 1` ở SQL1 (đánh dấu đã chuyển, giữ bản ghi).
5. `INSERT INTO [LINK1].NGANHANG.dbo.NhanVien` ở SQL2 (tạo bản ghi mới với MACN = TANDINH, TrangThaiXoa = 0).
6. COMMIT.

### 7.4. Một khách hàng có thể có nhiều tài khoản không?

**Trả lời:** Có. Quan hệ KhachHang-TaiKhoan là 1-N (một khách hàng nhiều tài khoản). Đó là lý do form Mở TK thiết kế theo Subform: chọn KH ở Master, grid TK ở Detail.

### 7.5. Giao dịch gửi/rút tiền cần Distributed Transaction không?

**Trả lời:** Không. Vì gửi/rút chỉ thao tác trên 1 TK tại 1 chi nhánh (local), không liên quan server khác. Chỉ cần `BEGIN TRANSACTION` thường. Distributed Transaction chỉ cần khi thao tác trên 2 server trở lên (chuyển tiền liên CN, chuyển NV).

---

## CỤM 8: CÂU HỎI THỰC TẾ / TÌNH HUỐNG (5 câu)

### 8.1. Nếu 2 nhân viên ở 2 chi nhánh cùng lúc rút tiền từ cùng 1 tài khoản thì sao?

**Trả lời:** Tình huống này không xảy ra trong thực tế vì giao diện chỉ cho NV thấy TK có `MACN` = chi nhánh mình (route filter `WHERE MACN = @macn`). Dù TaiKhoan được nhân bản toàn vẹn (NV có thể thấy TK đối tác ở tầng DB), ứng dụng chỉ hiển thị TK cùng chi nhánh cho chức năng gửi/rút. Nếu muốn thao tác TK ở chi nhánh khác, phải qua chuyển tiền (Distributed Transaction xử lý).

### 8.2. Tại sao không dùng 1 server tập trung cho đơn giản?

**Trả lời:** 
- **Hiệu năng:** 1 server phải chịu tải toàn bộ 2 chi nhánh. Phân tán thì mỗi server chỉ xử lý chi nhánh mình.
- **Khả dụng:** Nếu server tập trung sập, toàn hệ thống chết. Phân tán thì chi nhánh kia vẫn hoạt động.
- **Yêu cầu đề bài:** Đề bài là CSDL Phân Tán, nên bắt buộc phải phân tán.

### 8.3. Hệ thống có xử lý concurrent (đồng thời) không?

**Trả lời:** Có, thông qua cơ chế Lock của SQL Server. Khi SP dùng `BEGIN TRANSACTION`, SQL Server tự động lock các dòng đang thao tác. Ví dụ: 2 NV cùng rút tiền từ 2 TK khác nhau thì chạy song song. Nhưng nếu cùng 1 TK thì NV thứ 2 phải chờ NV thứ 1 xong (lock tránh race condition).

### 8.4. App dùng Node.js chứ không phải C# WinForms, có bị trừ điểm không?

**Trả lời:** Không, vì đề bài không giới hạn ngôn ngữ/platform. Node.js kết nối SQL Server qua package `mssql`, gọi SP bình thường, phân quyền bình thường. Ưu điểm: nhẹ, dễ demo trên mọi máy, chỉ cần browser.

### 8.5. Nếu MSDTC chưa bật thì sao?

**Trả lời:** Mọi lệnh `BEGIN DISTRIBUTED TRANSACTION` sẽ fail với lỗi "MSDTC is not available". Khi đó chuyển tiền liên chi nhánh, chuyển NV, và mở tài khoản sẽ không hoạt động. Cần vào Services (services.msc) → tìm "Distributed Transaction Coordinator" → Start. Phải bật trên tất cả server tham gia giao dịch phân tán.

### 8.6. Tại sao `sp_MoTaiKhoan` phải tách query LINK1 ra trước `BEGIN DISTRIBUTED TRANSACTION`?

**Trả lời:** Bảng `TaiKhoan` có Merge Replication → INSERT kích hoạt trigger `MSmerge_ins_*`. Nếu trong cùng scope có cả query `[LINK1]` (kiểm tra KH) và INSERT, SQL Server tạo **implicit distributed transaction**. Trigger cố enlist vào implicit DT này → conflict → SQL Server kill session với lỗi "Cannot continue the execution because the session is in the kill state".

**Giải pháp:** Check KH (local + LINK1) **TRƯỚC**, lưu kết quả vào biến `@KHFound`. INSERT nằm trong `BEGIN DISTRIBUTED TRANSACTION` riêng — scope chỉ có write, không có LINK1 query → merge trigger hoạt động bình thường. Pattern này nhất quán với `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien` (đọc trước, write trong DTC).

### 8.7. Tại sao `sp_MoTaiKhoan` phải gọi qua `sqlcmd` thay vì `mssql` driver?

**Trả lời:** SP dùng `BEGIN DISTRIBUTED TRANSACTION` → yêu cầu driver hỗ trợ MSDTC (two-phase commit). Driver `tedious` (dùng bởi package `mssql` trong Node.js) **không hỗ trợ** MSDTC vì chỉ implement protocol TDS cơ bản. `sqlcmd` dùng Native Client của Windows → hỗ trợ MSDTC đầy đủ. Hệ thống dùng hàm `execSPAdmin` trong `db.js` để gọi `sqlcmd` qua `child_process.execFile`.