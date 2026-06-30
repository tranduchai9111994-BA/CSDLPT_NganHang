-- =========================================================================================
-- SCRIPT: DỮ LIỆU MẪU (SEED DATA)
-- Tự động phát hiện chi nhánh và chèn đúng dữ liệu.
--
-- CÁCH CHẠY:
--   SQL1 (BENTHANH): sqlcmd -S "...\SQL1" -E -i seed_data.sql
--   SQL2 (TANDINH) : sqlcmd -S "...\SQL2" -E -i seed_data.sql
--   SQL3 (TRACUU)  : sqlcmd -S "...\SQL3" -E -i seed_data.sql  (chèn cả 2 bên)
--
-- Dùng IF NOT EXISTS → an toàn khi chạy lại, không ghi đè dữ liệu đã có.
-- =========================================================================================

USE NGANHANG;
GO

-- ==============================================================
-- BƯỚC 1: Đảm bảo bảng ChiNhanh có đủ 2 chi nhánh
-- (SQL3/TRACUU cần cả 2; SQL1 chỉ cần BENTHANH; SQL2 chỉ cần TANDINH)
-- ==============================================================

-- Chèn chi nhánh tương ứng với server này (dựa vào cái đang có)
-- BENTHANH
IF NOT EXISTS (SELECT 1 FROM ChiNhanh WHERE RTRIM(MACN) = 'BENTHANH')
   AND (NOT EXISTS (SELECT 1 FROM ChiNhanh) OR EXISTS (SELECT 1 FROM ChiNhanh WHERE RTRIM(MACN) = 'BENTHANH'))
    INSERT INTO ChiNhanh (MACN, TENCN, DIACHI, SoDT)
    VALUES (N'BENTHANH', N'Chi nhánh Bến Thành', N'211 Lê Lợi, Quận 1, TPHCM', N'02838220099');

-- TANDINH (chỉ chèn vào SQL2 hoặc SQL3)
IF NOT EXISTS (SELECT 1 FROM ChiNhanh WHERE RTRIM(MACN) = 'TANDINH')
   AND (NOT EXISTS (SELECT 1 FROM ChiNhanh) OR EXISTS (SELECT 1 FROM ChiNhanh WHERE RTRIM(MACN) = 'TANDINH'))
    INSERT INTO ChiNhanh (MACN, TENCN, DIACHI, SoDT)
    VALUES (N'TANDINH', N'Chi nhánh Tân Định', N'234 Hai Bà Trưng, phường Đakao, Quận 1, TPHCM', N'02838290066');

PRINT N'Bước 1: ChiNhanh OK';
GO

-- ==============================================================
-- BƯỚC 2: Dữ liệu BENTHANH — chỉ chèn khi server có MACN = BENTHANH
-- ==============================================================
IF EXISTS (SELECT 1 FROM ChiNhanh WHERE RTRIM(MACN) = 'BENTHANH')
BEGIN
    -- Nhân viên
    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'BT001')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'BT001', N'Trần Minh', N'Nguyên', N'0123456789', N'Nam Định', N'Nam', N'1111111111', N'BENTHANH', 0);

    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'BT002')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'BT002', N'Phạm Minh', N'Quyền', N'0911890189', N'Hải Phòng', N'Nam', N'0981765191', N'BENTHANH', 0);

    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'BT003')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'BT003', N'Trần', N'Test Mới', N'0999999999', N'123 Đường Tân Định', N'Nam', N'0912345678', N'BENTHANH', 0);

    -- Khách hàng
    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = '1111111111')
        INSERT INTO KhachHang (CMND, HO, TEN, DIACHI, PHAI, SODT, NGAYCAP, MACN)
        VALUES (N'1111111111', N'Nguyễn Văn', N'An', N'Quận 1, TP.HCM', N'Nam', N'0901111111', '2020-01-01', N'BENTHANH');

    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = '0011223344')
        INSERT INTO KhachHang (CMND, HO, TEN, DIACHI, PHAI, SODT, NGAYCAP, MACN)
        VALUES (N'0011223344', N'Trần Đức', N'Hải', N'Quận 12, TP.HCM', N'Nam', N'0901234567', '2026-01-01', N'BENTHANH');

    -- Tài khoản (chỉ những TK thuộc BENTHANH)
    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = '100000001')
        INSERT INTO TaiKhoan (SOTK, CMND, SODU, NGAYMOTK, MACN)
        VALUES (N'100000001', N'1111111111', 5000000, '2026-01-01 08:00:00', N'BENTHANH');

    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = 'TK1000001')
        INSERT INTO TaiKhoan (SOTK, CMND, SODU, NGAYMOTK, MACN)
        VALUES (N'TK1000001', N'0011223344', 500000, '2026-06-01 08:00:00', N'BENTHANH');

    -- Giao dịch gửi/rút
    IF NOT EXISTS (SELECT 1 FROM GD_GOIRUT WHERE RTRIM(SOTK)='100000001' AND LOAIGD='GT' AND SOTIEN=1000000)
        INSERT INTO GD_GOIRUT (SOTK, LOAIGD, SOTIEN, NGAYGD, MANV)
        VALUES (N'100000001', 'GT', 1000000, '2026-06-14 10:00:00', N'BT001');

    -- Giao dịch chuyển tiền sang Tân Định
    IF NOT EXISTS (SELECT 1 FROM GD_CHUYENTIEN WHERE RTRIM(SOTK_CHUYEN)='100000001' AND RTRIM(SOTK_NHAN)='100000002')
        INSERT INTO GD_CHUYENTIEN (SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES (N'100000001', N'100000002', 500000, '2026-06-14 10:05:00', N'BT001');

    PRINT N'Bước 2: BENTHANH — NhanVien(3), KhachHang(2), TaiKhoan(2), GD OK';
END
ELSE
    PRINT N'Bước 2: Bỏ qua (server này không có BENTHANH)';
GO

-- ==============================================================
-- BƯỚC 3: Dữ liệu TANDINH — chỉ chèn khi server có MACN = TANDINH
-- ==============================================================
IF EXISTS (SELECT 1 FROM ChiNhanh WHERE RTRIM(MACN) = 'TANDINH')
BEGIN
    -- Nhân viên
    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'TD001')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'TD001', N'Trần Minh', N'Nguyên', N'0123456001', N'Nam Định', N'Nam', N'1111111111', N'TANDINH', 0);

    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'TD002')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'TD002', N'Lê Văn', N'Anh', N'1234567890', N'Quận 1, TP.HCM', N'Nam', N'2222222222', N'TANDINH', 0);

    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'TD003')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'TD003', N'Trần', N'Test Mới', N'0999999001', N'123 Đường Tân Định', N'Nam', N'0912345678', N'TANDINH', 0);

    IF NOT EXISTS (SELECT 1 FROM NhanVien WHERE RTRIM(MANV) = 'TD004')
        INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES (N'TD004', N'Nguyễn Văn', N'Quang', N'1234561277', N'TPHCM', N'Nam', N'0931111777', N'TANDINH', 0);

    -- Khách hàng
    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = '2222222222')
        INSERT INTO KhachHang (CMND, HO, TEN, DIACHI, PHAI, SODT, NGAYCAP, MACN)
        VALUES (N'2222222222', N'Lê Thị', N'Bình', N'Quận 3, TP.HCM', N'Nữ', N'0902222222', '2020-01-01', N'TANDINH');

    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = '0099887766')
        INSERT INTO KhachHang (CMND, HO, TEN, DIACHI, PHAI, SODT, NGAYCAP, MACN)
        VALUES (N'0099887766', N'Lê Thảo', N'Trang', N'Quận 12, TP.HCM', N'Nữ', N'0987654321', '2026-01-01', N'TANDINH');

    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = '3333333333')
        INSERT INTO KhachHang (CMND, HO, TEN, DIACHI, PHAI, SODT, NGAYCAP, MACN)
        VALUES (N'3333333333', N'Nguyễn Văn', N'Hoàng', N'TPHCM', N'Nam', N'0911111999', '1990-01-01', N'TANDINH');

    IF NOT EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = '4444444444')
        INSERT INTO KhachHang (CMND, HO, TEN, DIACHI, PHAI, SODT, NGAYCAP, MACN)
        VALUES (N'4444444444', N'Hoàng Văn', N'Thái', N'Hà Nội', N'Nam', N'0199999999', '1981-01-10', N'TANDINH');

    -- Tài khoản (chỉ những TK thuộc TANDINH)
    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = '100000002')
        INSERT INTO TaiKhoan (SOTK, CMND, SODU, NGAYMOTK, MACN)
        VALUES (N'100000002', N'2222222222', 5000000, '2026-01-01 08:00:00', N'TANDINH');

    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = 'TK1000000')
        INSERT INTO TaiKhoan (SOTK, CMND, SODU, NGAYMOTK, MACN)
        VALUES (N'TK1000000', N'4444444444', 50000000, '2026-06-01 08:00:00', N'TANDINH');

    -- Giao dịch gửi/rút
    IF NOT EXISTS (SELECT 1 FROM GD_GOIRUT WHERE RTRIM(SOTK)='100000002' AND LOAIGD='GT' AND SOTIEN=2000000)
        INSERT INTO GD_GOIRUT (SOTK, LOAIGD, SOTIEN, NGAYGD, MANV)
        VALUES (N'100000002', 'GT', 2000000, '2026-06-14 10:00:00', N'TD002');

    IF NOT EXISTS (SELECT 1 FROM GD_GOIRUT WHERE RTRIM(SOTK)='TK1000000' AND LOAIGD='GT' AND SOTIEN=200000)
        INSERT INTO GD_GOIRUT (SOTK, LOAIGD, SOTIEN, NGAYGD, MANV)
        VALUES (N'TK1000000', 'GT', 200000, '2026-06-21 09:00:00', N'TD002');

    IF NOT EXISTS (SELECT 1 FROM GD_GOIRUT WHERE RTRIM(SOTK)='TK1000000' AND LOAIGD='RT' AND SOTIEN=300000)
        INSERT INTO GD_GOIRUT (SOTK, LOAIGD, SOTIEN, NGAYGD, MANV)
        VALUES (N'TK1000000', 'RT', 300000, '2026-06-21 09:05:00', N'TD002');

    PRINT N'Bước 3: TANDINH — NhanVien(4), KhachHang(4), TaiKhoan(2), GD OK';
END
ELSE
    PRINT N'Bước 3: Bỏ qua (server này không có TANDINH)';
GO

PRINT N'';
PRINT N'✅ Seed data hoàn tất.';
PRINT N'Tài khoản đăng nhập demo (mật khẩu đều là: 1)';
PRINT N'   BT001 / BT002 / BT003  →  Chi nhánh BENTHANH';
PRINT N'   TD001 / TD002 / TD003 / TD004  →  Chi nhánh TANDINH';
PRINT N'   admin  →  Ban Giám Đốc (TRACUU)';
GO
