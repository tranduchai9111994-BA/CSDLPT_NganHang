-- ============================================================
-- DỌN SP DƯ THỪA TRÊN TỪNG SITE
-- Chạy từng khối trên đúng server tương ứng qua SSMS
-- ============================================================

-- ============================================================
-- PHẦN 1: CHẠY TRÊN SQL1 (BENTHANH) VÀ SQL2 (TANDINH)
-- Xóa các SP TRACUU đặc thù (dùng LINK1+LINK2, chỉ chạy trên SQL3)
-- Chi nhánh không có LINK2 nên các SP này sẽ lỗi nếu gọi
-- ============================================================
USE NGANHANG;
GO

-- SP TRACUU đặc thù — chi nhánh không cần
IF OBJECT_ID('dbo.sp_DanhSachNhanVien', 'P') IS NOT NULL DROP PROCEDURE sp_DanhSachNhanVien;
IF OBJECT_ID('dbo.sp_DanhSachTaiKhoan', 'P') IS NOT NULL DROP PROCEDURE sp_DanhSachTaiKhoan;
IF OBJECT_ID('dbo.SP_DanhSachTrangThaiLogin', 'P') IS NOT NULL DROP PROCEDURE SP_DanhSachTrangThaiLogin;
IF OBJECT_ID('dbo.sp_SaoKeToanBo', 'P') IS NOT NULL DROP PROCEDURE sp_SaoKeToanBo;
IF OBJECT_ID('dbo.sp_LietKeTaiKhoanTheoNgay', 'P') IS NOT NULL DROP PROCEDURE sp_LietKeTaiKhoanTheoNgay;
GO

PRINT N'✓ Đã dọn SP TRACUU dư trên chi nhánh.';
GO

-- ============================================================
-- PHẦN 2: CHẠY TRÊN SQL3 (TRACUU)
-- Xóa các SP nghiệp vụ chi nhánh (chỉ chạy trên SQL1/SQL2)
-- TRACUU không có bảng GD_GOIRUT, GD_CHUYENTIEN, NhanVien
-- nên các SP này sẽ lỗi nếu gọi
-- ============================================================
USE NGANHANG;
GO

-- SP nghiệp vụ chi nhánh — TRACUU không cần
IF OBJECT_ID('dbo.sp_ChuyenTien', 'P') IS NOT NULL DROP PROCEDURE sp_ChuyenTien;
IF OBJECT_ID('dbo.SP_ChuyenNhanVien', 'P') IS NOT NULL DROP PROCEDURE SP_ChuyenNhanVien;
IF OBJECT_ID('dbo.sp_GuiTien', 'P') IS NOT NULL DROP PROCEDURE sp_GuiTien;
IF OBJECT_ID('dbo.sp_RutTien', 'P') IS NOT NULL DROP PROCEDURE sp_RutTien;
IF OBJECT_ID('dbo.sp_MoTaiKhoan', 'P') IS NOT NULL DROP PROCEDURE sp_MoTaiKhoan;
IF OBJECT_ID('dbo.sp_ThemKhachHang', 'P') IS NOT NULL DROP PROCEDURE sp_ThemKhachHang;
IF OBJECT_ID('dbo.SP_SaoKeTaiKhoan', 'P') IS NOT NULL DROP PROCEDURE SP_SaoKeTaiKhoan;
IF OBJECT_ID('dbo.SP_ResetMatKhau', 'P') IS NOT NULL DROP PROCEDURE SP_ResetMatKhau;
IF OBJECT_ID('dbo.SP_XoaLoiDongBo', 'P') IS NOT NULL DROP PROCEDURE SP_XoaLoiDongBo;
IF OBJECT_ID('dbo.sp_TaiKhoanKhachHang', 'P') IS NOT NULL DROP PROCEDURE sp_TaiKhoanKhachHang;
GO

PRINT N'✓ Đã dọn SP chi nhánh dư trên TRACUU.';
GO
