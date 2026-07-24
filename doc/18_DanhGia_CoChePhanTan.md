# 🧭 Đánh Giá Hiện Trạng Cơ Chế Phân Tán

> Tài liệu này rà soát hệ thống có đáp ứng đúng **cơ chế CSDL phân tán** theo yêu cầu đề bài không, dưới dạng **bảng điểm hiện trạng chốt** — không phải nhật ký chỉnh sửa.
> Đối chiếu: [`00_DE3_NGAN_HANG_PhanTan.md`](00_DE3_NGAN_HANG_PhanTan.md) (đề bài) và [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md) (source code SP).

---

## 1. Bản đồ kiến trúc

| Site | Instance | Vai trò | Dữ liệu cục bộ | Linked Server |
|---|---|---|---|---|
| NGUON | `ES-HAITD16` | Publisher / Distributor | Bản gốc toàn cục | `LINK1`→SQL1, `LINK2`→SQL2, `LINK3`→SQL3 |
| BENTHANH | `ES-HAITD16\SQL1` | Subscriber CN 1 | Phân mảnh `MACN='BENTHANH'` (KH/NV/GD) + `TaiKhoan` & `ChiNhanh` nhân bản toàn vẹn | `LINK0`→NGUON, `LINK1`→SQL2 (đối tác) |
| TANDINH | `ES-HAITD16\SQL2` | Subscriber CN 2 | Phân mảnh `MACN='TANDINH'` (KH/NV/GD) + `TaiKhoan` & `ChiNhanh` nhân bản toàn vẹn | `LINK0`→NGUON, `LINK1`→SQL1 (đối tác) |
| TRACUU | `ES-HAITD16\SQL3` | Subscriber tra cứu | Chỉ `KhachHang` replicate full + `QuanTriLogin` local | `LINK0`→NGUON, `LINK1`→SQL1, `LINK2`→SQL2 |

**Quy ước vàng:** `LINK1` luôn là **chi nhánh đối tác**. Không dùng cấu hình loopback.

---

## 2. Bảng điểm — Đối chiếu 8 hạng mục phân tán

| # | Hạng mục | Cơ chế phân tán kỳ vọng | Hiện trạng | Đánh giá |
|---|---|---|---|---|
| 1 | Phân mảnh ngang theo `MACN` | Publication filter + Merge Replication | Áp dụng cho `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN` | ✅ Đạt (3 tính chất Completeness/Reconstruction/Disjointness — xem [`08_Database_Replication.md`](08_Database_Replication.md) §2) |
| 2 | Nhân bản toàn vẹn `TaiKhoan`, `ChiNhanh` | Article không filter | Có bản đầy đủ trên SQL1 + SQL2. `TaiKhoan` áp dụng quy tắc "đọc local, ghi tại site sở hữu MACN" | ✅ Đạt |
| 3 | Trạm TRACUU chuyên tra cứu | Chỉ replicate KhachHang, đọc phần còn lại qua Linked Server | PUB_TRACUU có 1 article `KhachHang` + 3 SP article. Các bảng khác đọc qua LINK1/LINK2 | ✅ Đạt |
| 4 | Distributed Transaction (MSDTC 2PC) | `BEGIN DISTRIBUTED TRAN` + `SET XACT_ABORT ON` + LINK1, **chỉ dùng khi thực sự cross-site** | 5 SP dùng DTC: `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien` (rẽ nhánh theo MACN — fix #6), `sp_MoTaiKhoan`, `sp_ChuyenNhanVien` (có resurrect RF-A), `sp_PhucHoiNhanVien`. `SP_DongTaiKhoan` (RF-B) dùng local tran + query LINK1 để check | ✅ Đạt (tối ưu — không dùng MSDTC khi không cần) |
| 5 | Sao kê tại tầng DB (không kéo data thô về app) | Local + LINK1 + Window Function | `SP_SaoKeTaiKhoan`: tính lùi số dư đầu kỳ + `SUM() OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` | ✅ Đạt (tối ưu chuẩn) |
| 6 | Phân quyền 3 tầng + Defense in Depth | DB Role + Middleware + UI + **guard SQL-side trong SP** | `NganHang/ChiNhanh/KhachHang`; `KhachHang` không có `SELECT` trực tiếp; **`SP_SaoKeTaiKhoan` check `SUSER_SNAME()` + `IS_ROLEMEMBER`** (fix #8); **`SP_DongTaiKhoan` giữ 5 guard SQL-side** (RF-B) | ✅ Đạt + defense-in-depth |
| 7 | Sinh khóa phân tán không đụng độ | Identity Range (IDENTITY) + prefix (MANV/SOTK) atomic | `MAGD`: Identity Range Management; `MANV`: prefix `BT/TD`; **`SOTK`: sinh atomic trong SP với retry-on-PK (fix #3)** | ✅ Đạt (không còn race condition tầng app) |
| 8 | Business rule ép ở tầng SQL (không rò rỉ qua bypass app) | SP encapsulate guard; ownership check | `SP_DongTaiKhoan` (SODU=0, no GD, same-branch); `sp_ChuyenTien` chặn self-transfer (fix #9); `SP_SaoKeTaiKhoan` chặn KH xem sao kê TK người khác (fix #8) | ✅ Đạt (mới bổ sung 07/2026) |

**Kết luận tổng:** ✅ Hệ thống đáp ứng đầy đủ các nguyên lý CSDL phân tán yêu cầu bởi đề bài. Đợt refactor 07/2026 nâng thêm 1 hạng mục (defense-in-depth SQL-side).

---

## 3. Chi tiết cơ chế cho từng hạng mục

### 3.1. Phân mảnh ngang (`KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN`)

**Chiến lược:** Filter theo `MACN` khi cấu hình Article Replication. Với các bảng giao dịch (không có cột `MACN`), phân mảnh dựa trên **site INSERT** — mỗi GD được INSERT tại đúng site NV thực hiện.

**Đối chiếu 3 tính chất phân mảnh:**
- **Completeness:** ∀ record ∃ site chứa record đó. Đạt vì `MACN` ∈ {`BENTHANH`, `TANDINH`}.
- **Reconstruction:** `<Bảng gốc> = <mảnh SQL1> ∪ <mảnh SQL2>`. Đạt — SP TRACUU thực hiện `UNION ALL [LINK1] ∪ [LINK2]` để tái tạo (`sp_DanhSachNhanVien`, `sp_SaoKeToanBo`).
- **Disjointness:** Với các bảng phân mảnh, các mảnh KHÔNG giao (filter chặt theo `MACN` là XOR).

### 3.2. Nhân bản toàn vẹn (`TaiKhoan`, `ChiNhanh`)

**Vì sao nhân bản `TaiKhoan`?**
- **Kiểm tra nhanh khi chuyển tiền:** SP `sp_ChuyenTien` cần biết TK nhận thuộc chi nhánh nào. Nếu phân mảnh → phải query LINK1 để kiểm tra tồn tại (tốn mạng). Nhân bản → đọc local, biết ngay `MACN` để quyết định ghi local hay qua LINK1.
- **Tra cứu linh hoạt:** NV bất kỳ chi nhánh nào cũng có thể xem thông tin mọi TK từ site local.

**Quy tắc chống xung đột:**
- **ĐỌC local** — nhanh, không dùng Linked Server.
- **GHI tại site sở hữu** — SP so sánh `MACN_TK` vs `MACN_NV` để quyết định UPDATE local hay qua LINK1 (trong Distributed Transaction).
- Replication sẽ tự đồng bộ bản copy sang site đối tác sau khi write.

### 3.3. Trạm TRACUU (SQL3)

- **Vai trò:** phục vụ role `NganHang` (Ban Giám Đốc) tra cứu và báo cáo toàn cục, KHÔNG chịu tải giao dịch.
- **Chỉ có 1 bảng article:** `KhachHang` (không filter — replicate full). Đủ để tra cứu KH toàn hệ thống mà không dùng Linked Server.
- **Không có local:** `NhanVien`, `TaiKhoan`, `GD_GOIRUT`, `GD_CHUYENTIEN`. Đọc qua LINK1/LINK2 khi cần — bằng SP đặc thù (`sp_DanhSachNhanVien`, `sp_DanhSachTaiKhoan`, `sp_SaoKeToanBo`…) — xem [`13_All_Stored_Procedures.md`](13_All_Stored_Procedures.md) §13.

### 3.4. Distributed Transaction (MSDTC)

**SP có thể chạy trong `BEGIN DISTRIBUTED TRANSACTION`:**

| SP | Thao tác phân tán | Điều kiện DTC | Điểm đặc biệt |
|---|---|---|---|
| `sp_ChuyenTien` | UPDATE TK chuyển local + UPDATE TK nhận qua LINK1 (nếu khác CN) + INSERT log local | Chỉ khi khác CN (fix #6) | Atomic `WHERE SODU >= @SOTIEN`; chặn self-transfer `@SOTK_CHUYEN=@SOTK_NHAN` (fix #9) |
| `sp_GuiTien`, `sp_RutTien` | UPDATE TK (local hoặc LINK1 theo MACN) + INSERT log local | Chỉ khi TK và NV khác CN (fix #6) | Check `@SOTIEN ≥ 100k`, atomic số dư (rút) |
| `sp_MoTaiKhoan` | INSERT `TaiKhoan` (kích hoạt Merge trigger) | Luôn DTC | Check KH TRƯỚC scope DTC; **sinh SOTK atomic với vòng retry PK** (fix #3) |
| `sp_ChuyenNhanVien` | UPDATE `TrangThaiXoa=1` local + UPDATE hoặc INSERT bản mới qua LINK1 | Luôn DTC | **Resurrect logic** (RF-A): UPDATE ngược bản soft-delete cùng CMND thay vì INSERT khi vi phạm UQ |
| `sp_PhucHoiNhanVien` | Local phục hồi + LINK1 deactivate bản active bên kia | Luôn DTC | Đảm bảo không có 2 bản cùng CMND cùng active |

**SP dùng local tran nhưng vẫn thao tác cross-site:**

| SP | Thao tác | Ghi chú |
|---|---|---|
| `SP_DongTaiKhoan` (RF-B) | Query `LINK1` để check GD ở CN đối tác, DELETE `TaiKhoan` local | Merge Replication tự propagate DELETE sang site kia. Không cần DTC vì chỉ có 1 write. |

**Đảm bảo ACID:**
- `SET XACT_ABORT ON` — mọi lỗi runtime tự ROLLBACK.
- MSDTC thực hiện 2‑Phase Commit: Prepare → Commit đồng thời.
- Đứt mạng giữa chừng → cả 2 site tự ROLLBACK.

**Nguyên tắc thiết kế** *(rút ra từ fix #6)*: chỉ dùng `BEGIN DISTRIBUTED TRANSACTION` khi thực sự có write cross-site. Nếu chỉ write local (dù có đọc LINK1) → dùng `BEGIN TRANSACTION` để tiết kiệm chi phí MSDTC 2PC.

### 3.5. Sao kê tại tầng DB

Không kéo dữ liệu thô về Node.js để tính. Toàn bộ logic thực hiện trong SP:
- **Tính lùi số dư đầu kỳ:** `SODU_DAUKY = SODU_HIENTAI - SUM(biến động sau @TUNGAY)` — chỉ scan các GD trong khoảng thời gian yêu cầu, không phải toàn bộ lịch sử.
- **Window Function tính lũy kế:** `SUM(...) OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` — 1 lần scan, không cursor.
- **Gộp dữ liệu phân tán:** `UNION ALL Local + [LINK1]` (bản chi nhánh) hoặc `[LINK1] + [LINK2]` (bản TRACUU) để có đầy đủ GD của cả 2 CN.

### 3.6. Phân quyền 3 tầng + Defense in Depth

| Tầng | Cơ chế | Xử lý khi vi phạm |
|---|---|---|
| **Database** | `GRANT/DENY` trên bảng + `EXECUTE` trên SP. `DENY INSERT/UPDATE/DELETE` cho `NganHang`. KhachHang không có `SELECT` trực tiếp — chỉ EXECUTE 3 SP. | SQL Server từ chối lệnh (kể cả khi vào thẳng SSMS). |
| **Backend** | Middleware `requireLogin` → `requireRole(...)` → (route ghi) `requireChiNhanh`/`requireNganHang`. | HTTP 403 trước khi tới route handler. |
| **UI** | `<% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>` trong EJS. | Ẩn menu — UX tốt hơn, nhưng không phải rào chắn an ninh (đã có 2 tầng trên). |
| **SP-side (mới, 07/2026)** | Business guard trong SP: `SP_DongTaiKhoan` giữ 5 điều kiện đóng TK; `SP_SaoKeTaiKhoan` check `SUSER_SNAME() = CMND chủ TK` khi role KhachHang; `sp_ChuyenTien` chặn self-transfer | Ép ngay tại DB → không thể bypass qua SSMS/script trực tiếp |

**SQL Authentication theo từng người dùng:** `db.js:getPool()` mở connection pool riêng theo `(serverKey, username)` → `SUSER_SNAME()` trong SQL Server ghi đúng người thực hiện thao tác (audit trail). `SUSER_SNAME()` cũng được dùng để check ownership trong `SP_SaoKeTaiKhoan` (với role KhachHang, login name = CMND).

### 3.7. Sinh khóa phân tán không đụng độ

| Khóa | Kỹ thuật | File nguồn |
|---|---|---|
| `MAGD` (INT IDENTITY) | **Identity Range Management** — mỗi Subscriber được cấp dải ID riêng, không giao | Cấu hình Publication (`@identityrangemanagementoption='auto'`) |
| `MANV` (nchar 10) | **Prefix chi nhánh** `BT###` / `TD###` — `sinhMANV()` query `MAX(MANV) LIKE prefix%` + 1 | `routes/nhanvien.js` |
| `SOTK` (nchar 9) | **Prefix chi nhánh theo `@MACN` + sinh atomic trong SP** (fix #3, 07/2026): SP `sp_MoTaiKhoan` giữ vòng WHILE retry — mỗi lần đọc `MAX(SOTK) + 1 + @Attempt` rồi INSERT trong DTC; PK duplicate → tăng `@Attempt`, thử SOTK mới. Route parse SOTK trả về từ output sqlcmd bằng regex. Loại bỏ hoàn toàn race condition tầng app. | `sql/stored_procedures/20_SP_MoTaiKhoan.sql` |
| `CMND` (nchar 10) | Do người dùng nhập; duy nhất toàn cục theo nghiệp vụ | — |

### 3.8. Business rule guards SQL-side (mới bổ sung 07/2026)

Đợt refactor tháng 07/2026 đẩy các quy tắc nghiệp vụ từ tầng route xuống tầng SP để chống bypass ứng dụng (SSMS trực tiếp, script tự động, SP khác gọi lộn xộn).

| Nghiệp vụ | Guard SP-side | Fix |
|---|---|---|
| Đóng TK | `SP_DongTaiKhoan` giữ 5 điều kiện: TK tồn tại, `SODU=0`, cùng CN với NV, không có `GD_GOIRUT` (local+LINK1), không có `GD_CHUYENTIEN` (local+LINK1) | RF-B |
| Chuyển tiền | Chặn self-transfer `@SOTK_CHUYEN = @SOTK_NHAN` | #9 |
| Sao kê | Nếu role KhachHang → check `SUSER_SNAME() = CMND chủ TK` (login KH = CMND) | #8 |
| Chuyển NV | Resurrect NV soft-delete tại đích thay vì INSERT gây UQ violation | RF-A |
| Mở TK | Sinh SOTK atomic trong SP với retry-on-PK, prefix theo `@MACN` | #3 |

**Đánh giá:** Việc chuyển guard xuống SP làm SP dài hơn nhưng tăng đáng kể tính vững chắc của cơ sở dữ liệu — quy tắc nghiệp vụ được ép ngay tại tầng lưu trữ, không phụ thuộc vào tầng ứng dụng có bị bypass hay không.

---

## 4. Điểm chú ý về bảo mật (không phải lỗ hổng của cơ chế phân tán, nhưng cần rõ)

| Vấn đề | Mức | Ghi chú |
|---|---|---|
| `QuanTriLogin.MatKhauHienTai` lưu **plain‑text** | Chấp nhận trong đồ án học tập | `DENY SELECT` cho ChiNhanh/KhachHang; NganHang xem qua API có middleware. Không dùng trong production. |
| `req.session.user.PASSWORD` lưu plain trong session | Chấp nhận trong đồ án học tập | Cần thiết để mở pool per‑user (SQL Auth). Production nên dùng token và pool ngắn hạn. |
| Password `HTKN='123'` hardcode trong `db.js` và Security Mapping | Chấp nhận trong đồ án học tập | Là tài khoản hệ thống cho `execSPAdmin` + Linked Server. Password đồng nhất giữa 4 instance. |

---

## 5. Tổng kết

Hệ thống đã triển khai đúng và đầy đủ các nguyên lý CSDL phân tán mà đề bài yêu cầu:
1. **Phân mảnh ngang** theo `MACN` — thỏa Completeness/Reconstruction/Disjointness.
2. **Nhân bản toàn vẹn** `TaiKhoan`/`ChiNhanh` — có quy tắc chống xung đột "ghi tại site sở hữu".
3. **Trạm tra cứu TRACUU** — kết hợp replicate 1 bảng + đọc phần còn lại qua Linked Server.
4. **Distributed Transaction có chọn lọc** — MSDTC 2‑Phase Commit qua LINK1 chỉ khi thực sự cross-site (rẽ nhánh local/DTC theo scope thực tế — fix #6).
5. **Báo cáo tối ưu** — tính toán tại tầng DB, giảm IO mạng.
6. **Phân quyền 3 tầng + Defense in Depth** — DB Role + Middleware + UI + guard SQL-side; SQL Authentication cho audit đúng người.
7. **Khóa phân tán atomic** — Identity Range + prefix chi nhánh theo `@MACN` + sinh SOTK trong SP với retry (fix #3).
8. **Business rule ép ở tầng SQL** — SP encapsulate guard, chống bypass ứng dụng (RF-A, RF-B, fix #8, fix #9).
