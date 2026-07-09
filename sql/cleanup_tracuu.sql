-- ============================================================
-- DỌN DẸP SQL3 (TRACUU) SAU KHI SỬA PUB_TRACUU
-- Chạy trên ES-HAITD16\SQL3 sau khi đã bỏ article trên NGUON
--
-- Thứ tự thực hiện:
--   1. Trên NGUON (SSMS): sửa PUB_TRACUU → chỉ giữ KhachHang
--   2. Start Snapshot Agent để đẩy snapshot mới
--   3. Chạy script này trên SQL3 để xóa bảng thừa
-- ============================================================

USE NGANHANG;
GO

-- Kiểm tra trước khi xóa
PRINT N'=== Trước khi dọn ===';
SELECT name FROM sys.tables ORDER BY name;
GO

-- DROP các bảng không còn replicate (TRACUU chỉ cần KhachHang)
-- Lưu ý: QuanTriLogin giữ lại (không thuộc Replication, dùng cho Login Management)

IF OBJECT_ID('dbo.GD_CHUYENTIEN', 'U') IS NOT NULL
    DROP TABLE dbo.GD_CHUYENTIEN;
GO

IF OBJECT_ID('dbo.GD_GOIRUT', 'U') IS NOT NULL
    DROP TABLE dbo.GD_GOIRUT;
GO

IF OBJECT_ID('dbo.NhanVien', 'U') IS NOT NULL
    DROP TABLE dbo.NhanVien;
GO

IF OBJECT_ID('dbo.TaiKhoan', 'U') IS NOT NULL
    DROP TABLE dbo.TaiKhoan;
GO

IF OBJECT_ID('dbo.ChiNhanh', 'U') IS NOT NULL
    DROP TABLE dbo.ChiNhanh;
GO

PRINT N'';
PRINT N'=== Sau khi dọn ===';
SELECT name FROM sys.tables ORDER BY name;
GO

PRINT N'';
PRINT N'Còn lại: KhachHang (replicate) + QuanTriLogin (local).';
PRINT N'Các SP đặc thù TRACUU đọc NhanVien/TaiKhoan qua LINK1+LINK2.';
GO
