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

## 2. Bảng điểm — Đối chiếu 7 hạng mục phân tán

| # | Hạng mục | Cơ chế phân tán kỳ vọng | Hiện trạng | Đánh giá |
|---|---|---|---|---|
| 1 | Phân mảnh ngang theo `MACN` | Publication filter + Merge Replication | Áp dụng cho `KhachHang`, `NhanVien`, `GD_GOIRUT`, `GD_CHUYENTIEN` | ✅ Đạt (3 tính chất Completeness/Reconstruction/Disjointness — xem [`08_Database_Replication.md`](08_Database_Replication.md) §2) |
| 2 | Nhân bản toàn vẹn `TaiKhoan`, `ChiNhanh` | Article không filter | Có bản đầy đủ trên SQL1 + SQL2. `TaiKhoan` áp dụng quy tắc "đọc local, ghi tại site sở hữu MACN" | ✅ Đạt |
| 3 | Trạm TRACUU chuyên tra cứu | Chỉ replicate KhachHang, đọc phần còn lại qua Linked Server | PUB_TRACUU có 1 article `KhachHang` + 3 SP article. Các bảng khác đọc qua LINK1/LINK2 | ✅ Đạt |
| 4 | Distributed Transaction (MSDTC 2PC) | `BEGIN DISTRIBUTED TRAN` + `SET XACT_ABORT ON` + LINK1 | 6 SP dùng DTC: `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_PhucHoiNhanVien` | ✅ Đạt |
| 5 | Sao kê tại tầng DB (không kéo data thô về app) | Local + LINK1 + Window Function | `SP_SaoKeTaiKhoan`: tính lùi số dư đầu kỳ + `SUM() OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` | ✅ Đạt (tối ưu chuẩn) |
| 6 | Phân quyền 3 tầng | DB Role + Middleware + UI | `NganHang/ChiNhanh/KhachHang`; `KhachHang` không có `SELECT` trực tiếp, chỉ EXECUTE 3 SP | ✅ Đạt |
| 7 | Sinh khóa phân tán không đụng độ | Identity Range (IDENTITY) + prefix (MANV/SOTK) | `MAGD`: Identity Range Management; `MANV`: prefix `BT/TD`; `SOTK`: prefix `BT/TD` + số 7 chữ số | ✅ Đạt |

**Kết luận tổng:** ✅ Hệ thống đáp ứng đầy đủ các nguyên lý CSDL phân tán yêu cầu bởi đề bài.

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

**6 SP chạy trong `BEGIN DISTRIBUTED TRANSACTION`:**

| SP | Thao tác phân tán | Điểm đặc biệt |
|---|---|---|
| `sp_ChuyenTien` | UPDATE TK chuyển local + UPDATE TK nhận qua LINK1 (nếu khác CN) + INSERT log local | Atomic `WHERE SODU >= @SOTIEN` |
| `sp_GuiTien`, `sp_RutTien` | UPDATE TK (local hoặc LINK1 theo MACN) + INSERT log local | Check `@SOTIEN ≥ 100k`, atomic số dư (rút) |
| `sp_MoTaiKhoan` | INSERT `TaiKhoan` (kích hoạt Merge trigger) | Check KH TRƯỚC scope DTC — tách LINK1 query ra ngoài |
| `sp_ChuyenNhanVien` | UPDATE `TrangThaiXoa=1` local + INSERT bản mới qua LINK1 | Sinh MANV mới với prefix chi nhánh đích |
| `sp_PhucHoiNhanVien` | Local phục hồi + LINK1 deactivate bản active bên kia | Đảm bảo không có 2 bản cùng CMND cùng active |

**Đảm bảo ACID:**
- `SET XACT_ABORT ON` — mọi lỗi runtime tự ROLLBACK.
- MSDTC thực hiện 2‑Phase Commit: Prepare → Commit đồng thời.
- Đứt mạng giữa chừng → cả 2 site tự ROLLBACK.

### 3.5. Sao kê tại tầng DB

Không kéo dữ liệu thô về Node.js để tính. Toàn bộ logic thực hiện trong SP:
- **Tính lùi số dư đầu kỳ:** `SODU_DAUKY = SODU_HIENTAI - SUM(biến động sau @TUNGAY)` — chỉ scan các GD trong khoảng thời gian yêu cầu, không phải toàn bộ lịch sử.
- **Window Function tính lũy kế:** `SUM(...) OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` — 1 lần scan, không cursor.
- **Gộp dữ liệu phân tán:** `UNION ALL Local + [LINK1]` (bản chi nhánh) hoặc `[LINK1] + [LINK2]` (bản TRACUU) để có đầy đủ GD của cả 2 CN.

### 3.6. Phân quyền 3 tầng

| Tầng | Cơ chế | Xử lý khi vi phạm |
|---|---|---|
| **Database** | `GRANT/DENY` trên bảng + `EXECUTE` trên SP. `DENY INSERT/UPDATE/DELETE` cho `NganHang`. KhachHang không có `SELECT` trực tiếp — chỉ EXECUTE 3 SP. | SQL Server từ chối lệnh (kể cả khi vào thẳng SSMS). |
| **Backend** | Middleware `requireLogin` → `requireRole(...)` → (route ghi) `requireChiNhanh`/`requireNganHang`. | HTTP 403 trước khi tới route handler. |
| **UI** | `<% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>` trong EJS. | Ẩn menu — UX tốt hơn, nhưng không phải rào chắn an ninh (đã có 2 tầng trên). |

**SQL Authentication theo từng người dùng:** `db.js:getPool()` mở connection pool riêng theo `(serverKey, username)` → `LOGIN_NAME()` trong SQL Server ghi đúng người thực hiện thao tác (audit trail).

### 3.7. Sinh khóa phân tán không đụng độ

| Khóa | Kỹ thuật | File nguồn |
|---|---|---|
| `MAGD` (INT IDENTITY) | **Identity Range Management** — mỗi Subscriber được cấp dải ID riêng, không giao | Cấu hình Publication (`@identityrangemanagementoption='auto'`) |
| `MANV` (nchar 10) | **Prefix chi nhánh** `BT###` / `TD###` — `sinhMANV()` query `MAX(MANV) LIKE prefix%` + 1 | `routes/nhanvien.js` |
| `SOTK` (nchar 9) | **Prefix chi nhánh** `BT#######` / `TD#######` (7 chữ số) — `sinhSOTK()` tương tự | `routes/taikhoan.js` |
| `CMND` (nchar 10) | Do người dùng nhập; duy nhất toàn cục theo nghiệp vụ | — |

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
4. **Distributed Transaction** — MSDTC 2‑Phase Commit qua LINK1 cho mọi thao tác xuyên site.
5. **Báo cáo tối ưu** — tính toán tại tầng DB, giảm IO mạng.
6. **Phân quyền 3 tầng** — DB Role + Middleware + UI, SQL Authentication cho audit đúng người.
7. **Khóa phân tán** — Identity Range + prefix chi nhánh, không đụng độ khi sync.
