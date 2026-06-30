# Tài Khoản Demo — Hệ Thống Ngân Hàng

Tất cả tài khoản dưới đây dùng để đăng nhập vào web app tại `http://localhost:3000`.  
Xác thực qua SQL Server Authentication — login name là tên SQL Login.

---

## Tổng quan Roles

| Role | Mô tả quyền hạn |
|------|----------------|
| `NganHang` | Giám đốc / Quản trị — SELECT toàn bộ schema, EXECUTE SP, không INSERT/UPDATE/DELETE |
| `ChiNhanh` | Nhân viên chi nhánh — CRUD đầy đủ trên giao dịch, khách hàng, tài khoản |
| `KhachHang` | Khách hàng — chỉ EXECUTE 2 SP: xem TK của mình và sao kê |

---

## Tài Khoản Admin (Giám Đốc)

| Trường | Giá trị |
|--------|---------|
| **SQL Login** | `admin` |
| **Mật khẩu** | `1` |
| **Role** | `NganHang` |
| **Chức danh** | Quản Trị Viên (Ban Giám Đốc) |
| **Quyền** | Xem toàn bộ dữ liệu, thực thi SP — không thể INSERT/UPDATE/DELETE trực tiếp |

---

## Tài Khoản Nhân Viên Chi Nhánh (Demo)

| SQL Login | Mật khẩu | Role | Ghi chú |
|-----------|----------|------|---------|
| `BT001` | `1` | `ChiNhanh` | Trần Minh Nguyên — BENTHANH |
| `BT002` | `1` | `ChiNhanh` | Phạm Minh Quyền — BENTHANH |
| `BT003` | `1` | `ChiNhanh` | Trần Test Mới — BENTHANH |
| `TD001` | `1` | `ChiNhanh` | Trần Minh Nguyên — TANDINH |
| `TD002` | `1` | `ChiNhanh` | Lê Văn Anh — TANDINH |
| `TD003` | `1` | `ChiNhanh` | Trần Test Mới — TANDINH |
| `TD004` | `1` | `ChiNhanh` | Nguyễn Văn Quang — TANDINH |

**Quyền của ChiNhanh:**
- SELECT, INSERT, UPDATE, DELETE trên: `GD_CHUYENTIEN`, `GD_GOIRUT`, `KhachHang`, `TaiKhoan`
- SELECT trên: `NhanVien`, `ChiNhanh`
- EXECUTE toàn bộ Stored Procedures

> Tài khoản nhân viên phải tồn tại trong bảng `NhanVien` với `TrangThaiXoa = 0` và `MANV` khớp với SQL Login.

---

## Tài Khoản Khách Hàng

Khách hàng đăng nhập bằng **số CMND** làm SQL Login.  
Tài khoản SQL phải được tạo thủ công và gán vào role `KhachHang`.

| SQL Login | Mật khẩu | Role | Ghi chú |
|-----------|----------|------|---------|
| *(CMND khách hàng)* | *(tự đặt)* | `KhachHang` | Tạo theo từng khách |

**Quyền của KhachHang:**
- EXECUTE `sp_TaiKhoanKhachHang` — xem danh sách tài khoản của mình
- EXECUTE `SP_SaoKeTaiKhoan` — xem sao kê chi tiết 1 tài khoản

---

## Khởi Tạo Lại Tài Khoản Demo

Chạy lần lượt các script sau (từ thư mục gốc project):

```bat
-- Bước 1: Tạo Roles và phân quyền
sqlcmd -S "TEN_SERVER" -E -i "sql\setup\04_Role_PhanQuyen.sql"

-- Bước 2: Tạo tài khoản Admin
sqlcmd -S "TEN_SERVER" -E -i "sql\setup\09_TaoTaiKhoanAdmin.sql"

-- Bước 3: Tạo tài khoản Nhân viên demo
sqlcmd -S "TEN_SERVER" -E -i "sql\setup\10_TaoTaiKhoanNhanVien_Demo.sql"
```

Hoặc chạy `run_all.bat` để deploy toàn bộ lên 4 SQL Server cùng lúc.
