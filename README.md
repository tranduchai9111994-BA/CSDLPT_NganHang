# 🏦 Đồ Án Quản Lý Ngân Hàng — CSDL Phân Tán

Hệ thống Quản lý Ngân Hàng mô phỏng hoạt động thực tế với kiến trúc **Cơ sở dữ liệu phân tán (Distributed Database)** trên SQL Server, kết hợp Web Application xây dựng bằng Node.js + Express.

Hệ thống đảm bảo tính toàn vẹn dữ liệu (ACID) tuyệt đối trong môi trường phân tán thông qua **MSDTC (Two‑Phase Commit)**, áp dụng kỹ thuật tối ưu hóa truy vấn nâng cao (**Window Functions**) và quản trị bảo mật sát thực tế bằng **SQL Authentication** trực tiếp cho từng người dùng.

---

## 🏗️ Kiến Trúc Hệ Thống

Dự án phân mảnh thành **4 SQL Server instance** trên cùng máy `ES-HAITD16`:

| Instance | Vai trò | Mô tả |
|---|---|---|
| `ES-HAITD16` (NGUON) | **Publisher / Distributor** | Chứa CSDL gốc, phát hành 3 Publication. Không phục vụ nghiệp vụ trực tiếp. |
| `ES-HAITD16\SQL1` (BENTHANH) | **Subscriber — Chi nhánh 1** | Chứa dữ liệu phân mảnh `MACN='BENTHANH'`. Xử lý giao dịch Bến Thành. |
| `ES-HAITD16\SQL2` (TANDINH) | **Subscriber — Chi nhánh 2** | Chứa dữ liệu phân mảnh `MACN='TANDINH'`. Xử lý giao dịch Tân Định. |
| `ES-HAITD16\SQL3` (TRACUU) | **Subscriber — Trạm tra cứu** | Chỉ replicate bảng `KhachHang`. Phục vụ role `NganHang` tra cứu toàn cục. |

Giao tiếp liên site được thực hiện qua mạng lưới **Linked Server** (LINK0/LINK1/LINK2) — xem [`doc/10_Linked_Servers.md`](doc/10_Linked_Servers.md).

---

## 🚀 Các Tính Năng Nổi Bật

### 1. Phân quyền bảo mật sâu — SQL Authentication theo từng người dùng
- Ứng dụng KHÔNG dùng 1 tài khoản service chung. Mỗi người dùng đăng nhập bằng **SQL Login của chính họ** (ví dụ `BT001`, `TD001`, `1111111111`). `db.js` mở connection pool riêng theo `(serverKey, username)`.
- 3 role cấp Database: **`NganHang`** (chỉ đọc + báo cáo toàn hệ thống), **`ChiNhanh`** (CRUD trên chi nhánh mình), **`KhachHang`** (chỉ EXECUTE 3 SP).
- SP lõi `sp_Login_App` map Login → Role qua `sys.database_role_members` + `sys.database_principals`.

### 2. Giao dịch phân tán chuẩn 2‑Phase Commit
- Các SP `sp_GuiTien`, `sp_RutTien`, `sp_ChuyenTien`, `sp_MoTaiKhoan`, `sp_ChuyenNhanVien`, `sp_PhucHoiNhanVien` đều dùng `BEGIN DISTRIBUTED TRANSACTION` + `SET XACT_ABORT ON` + `TRY/CATCH`.
- MSDTC bảo đảm cộng/trừ ở 2 site cùng commit hoặc cùng rollback — không có "tiền mất tích".
- Do driver `tedious` của Node.js không hỗ trợ MSDTC, các SP này được gọi qua **`sqlcmd`** (hàm `execSPAdmin` trong `db.js`).

### 3. Tối ưu báo cáo Sao Kê bằng Window Functions
- Kỹ thuật "**tính lùi số dư đầu kỳ**": lấy số dư hiện tại trừ đi tổng biến động sau `@TUNGAY`, tránh phải kéo toàn bộ lịch sử qua Linked Server.
- Dùng `SUM(...) OVER (ORDER BY NGAYGD ROWS UNBOUNDED PRECEDING)` để tính số dư lũy kế trên 1 lần scan, không cần cursor.

### 4. Bảo mật 3 tầng
DB Role (`GRANT/DENY`) — Backend Middleware (`requireRole`) — UI (`if user.NHOM`). Kể cả khi user vượt qua UI hoặc middleware, DB Role vẫn chặn cứng ở tầng cuối.

---

## 💻 Cài Đặt Và Vận Hành

### Yêu cầu môi trường
- **Node.js** 14+
- **SQL Server** 2019+ (đã cấu hình 4 instance NGUON/SQL1/SQL2/SQL3, đã bật MSDTC, đã cấu hình Replication + Linked Server)

### Các bước chạy ứng dụng
```bash
cd APP_NGANHANG
npm install
npm start
```
Truy cập: `http://localhost:3001`

Đảm bảo `APP_NGANHANG/db.js` có đúng tên server (`ES-HAITD16`, `ES-HAITD16\SQL1`, `ES-HAITD16\SQL2`, `ES-HAITD16\SQL3`).

Tài khoản demo: xem [`doc/03_DemoAccounts.md`](doc/03_DemoAccounts.md).

---

## 📚 Hệ Thống Tài Liệu Kỹ Thuật

Bộ tài liệu trong thư mục [`doc/`](doc/) — ưu tiên đọc theo thứ tự để chuẩn bị vấn đáp:

| # | File | Nội dung |
|---|------|----------|
| 00 | [`00_DE3_NGAN_HANG_PhanTan.md`](doc/00_DE3_NGAN_HANG_PhanTan.md) | Đề bài gốc (Đề 3 — Ngân Hàng phân tán) |
| 01 | [`01_DoiChieuDeBai.md`](doc/01_DoiChieuDeBai.md) | Checklist đối chiếu yêu cầu đề bài ↔ thực tế triển khai |
| 02 | [`02_KichBanDemo.md`](doc/02_KichBanDemo.md) | Kịch bản demo trước hội đồng (8–12 phút) |
| 03 | [`03_DemoAccounts.md`](doc/03_DemoAccounts.md) | Danh sách tài khoản demo (admin / BT* / TD* / KH) |
| 04 | [`04_CauHoiVanDap.md`](doc/04_CauHoiVanDap.md) | **Bộ câu hỏi vấn đáp** (8 cụm chủ đề, ~50 câu) |
| 05 | [`05_Architecture.md`](doc/05_Architecture.md) | Kiến trúc MVC, luồng request Browser → SQL |
| 06 | [`06_Database_Diagram.md`](doc/06_Database_Diagram.md) | Sơ đồ ERD (Mermaid) + ràng buộc FK/UNIQUE |
| 07 | [`07_Database_Schema.md`](doc/07_Database_Schema.md) | Đặc tả chi tiết các bảng + danh mục SP nghiệp vụ |
| 08 | [`08_Database_Replication.md`](doc/08_Database_Replication.md) | **Replication** — Publisher/Subscriber, 3 tính chất phân mảnh, Publication–Article matrix |
| 09 | [`09_Database_Connection.md`](doc/09_Database_Connection.md) | `db.js` — connection pool, `execSP` vs `execSPAdmin` |
| 10 | [`10_Linked_Servers.md`](doc/10_Linked_Servers.md) | Cấu hình LINK0/LINK1/LINK2 + Security Mapping (`HTKN`) |
| 11 | [`11_Security_Authorization.md`](doc/11_Security_Authorization.md) | Bảo mật 3 tầng: DB Role — Middleware — UI |
| 12 | [`12_Modules_Routing.md`](doc/12_Modules_Routing.md) | Đặc tả từng route file (`auth`, `khachhang`, `nhanvien`, `taikhoan`, `giaodich`, `baocao`, `quantri`) |
| 13 | [`13_All_Stored_Procedures.md`](doc/13_All_Stored_Procedures.md) | **Toàn bộ source code SP** kèm giải thích cơ chế phân tán |
| 14 | [`14_Reports_Checklist.md`](doc/14_Reports_Checklist.md) | Checklist chức năng Liệt kê / Sao kê |
| 17 | [`17_Su_Co_Va_Xu_Ly.md`](doc/17_Su_Co_Va_Xu_Ly.md) | Nhật ký sự cố CSDL phân tán tiêu biểu (ôn phản biện vấn đáp) |
| 18 | [`18_DanhGia_CoChePhanTan.md`](doc/18_DanhGia_CoChePhanTan.md) | Đánh giá hiện trạng cơ chế phân tán — điểm đạt / chưa đạt |
| 19 | [`19_TestCase_BaoVeDoAn.md`](doc/19_TestCase_BaoVeDoAn.md) | Bộ test case cho buổi bảo vệ |

> 💡 **Ôn thi vấn đáp** — bắt đầu từ `04_CauHoiVanDap.md`, tham chiếu chéo `08_Database_Replication.md` và `13_All_Stored_Procedures.md` khi cần đi sâu.
