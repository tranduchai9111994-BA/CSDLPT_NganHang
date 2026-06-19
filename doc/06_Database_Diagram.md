# 📊 Sơ Đồ Thực Thể Liên Kết (ERD) - Database NGANHANG

Tài liệu này cung cấp cái nhìn tổng quan về kiến trúc Database dưới dạng sơ đồ thực thể liên kết (ER Diagram). Sơ đồ này mô tả chi tiết các bảng, các trường dữ liệu quan trọng, khóa chính (PK), khóa ngoại (FK), các ràng buộc (UK - Unique, NOT NULL, CHECK), và mối quan hệ giữa chúng.

```mermaid
erDiagram
    ChiNhanh {
        nchar(10) MACN PK
        nvarchar(100) TENCN UK "UNIQUE"
        nvarchar(100) DIACHI
        nvarchar(15) SoDT
    }

    NhanVien {
        nchar(10) MANV PK
        nvarchar(50) HO
        nvarchar(10) TEN
        nchar(10) CMND UK "UNIQUE"
        nvarchar(100) DIACHI
        nvarchar(3) PHAI
        nvarchar(15) SODT
        nchar(10) MACN FK
        int TrangThaiXoa "0: Đang làm, 1: Đã xóa"
    }

    KhachHang {
        nchar(10) CMND PK
        nvarchar(50) HO
        nvarchar(10) TEN
        nvarchar(100) DIACHI
        nvarchar(3) PHAI
        date NGAYCAP
        nvarchar(15) SODT
        nchar(10) MACN "Được tạo ở Chi Nhánh nào"
    }

    TaiKhoan {
        nchar(9) SOTK PK
        nchar(10) CMND FK "NOT NULL"
        money SODU "CHECK (SODU >= 0)"
        nchar(10) MACN "Mở tại Chi Nhánh nào"
        datetime NGAYMOTK
    }

    GD_GOIRUT {
        int MAGD PK "Tự tăng"
        nchar(9) SOTK FK
        nchar(2) LOAIGD "GT: Gửi, RT: Rút"
        datetime NGAYGD
        money SOTIEN
        nchar(10) MANV FK "Giao dịch viên"
    }

    GD_CHUYENTIEN {
        int MAGD PK "Tự tăng"
        nchar(9) SOTK_CHUYEN FK "TK Gửi"
        nchar(9) SOTK_NHAN FK "TK Nhận"
        money SOTIEN
        datetime NGAYGD
        nchar(10) MANV FK "Giao dịch viên"
    }

    %% Các mối quan hệ (Relationships)
    ChiNhanh ||--o{ NhanVien : "Quản lý"
    KhachHang ||--o{ TaiKhoan : "Sở hữu"
    NhanVien ||--o{ GD_GOIRUT : "Thực hiện"
    NhanVien ||--o{ GD_CHUYENTIEN : "Thực hiện"
    TaiKhoan ||--o{ GD_GOIRUT : "Phát sinh"
    TaiKhoan ||--o{ GD_CHUYENTIEN : "Chuyển đi"
    TaiKhoan ||--o{ GD_CHUYENTIEN : "Nhận về"
```

## 📝 Chú thích các chuẩn thiết kế

*   **Bảng `ChiNhanh` và `NhanVien`**: Được liên kết qua `MACN`. Tại một phân mảnh cụ thể, bảng `NhanVien` chỉ chứa nhân viên làm việc tại `MACN` đó. Các trường `TENCN` và `CMND` có ràng buộc duy nhất (UNIQUE).
*   **Bảng `KhachHang` và `TaiKhoan`**: Một khách hàng (PK: `CMND`) có thể có nhiều Tài khoản. Tài khoản bắt buộc phải có chủ sở hữu (`CMND` là NOT NULL) và số dư luôn luôn phải không âm (`CHECK (SODU >= 0)`).
*   **Các bảng Giao Dịch (`GD_GOIRUT`, `GD_CHUYENTIEN`)**: Không có cột `MACN`. Nguyên tắc thiết kế CSDL Phân Tán yêu cầu dữ liệu giao dịch phải "đi theo" nhân viên hoặc tài khoản phát sinh ra nó thay vì bị cố định dư thừa. Mối quan hệ được truy vết hoàn toàn qua `SOTK` và `MANV`.
*   **Tính ACID trong Chuyển Tiền**: Khi thực hiện `GD_CHUYENTIEN` giữa hai tài khoản thuộc hai chi nhánh khác nhau, `SOTK_CHUYEN` (của chi nhánh gốc) và `SOTK_NHAN` (của chi nhánh đích) sẽ được bọc trong một Distributed Transaction (MSDTC) thay vì được liên kết cứng vật lý (Foreign Key constraints liên chi nhánh), nhằm bảo toàn khả năng vận hành độc lập của các Site.
