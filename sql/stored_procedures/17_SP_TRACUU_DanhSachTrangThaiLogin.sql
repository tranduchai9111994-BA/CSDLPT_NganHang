USE NGANHANG;
GO

-- Phiên bản TRACUU của SP_DanhSachTrangThaiLogin.
-- TRACUU không có NhanVien local → đọc qua LINK1+LINK2.
-- KhachHang, QuanTriLogin, sys.server_principals đều local trên TRACUU.
CREATE OR ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- ==========================================================================
    -- BƯỚC 1: LẤY DANH SÁCH NHÂN VIÊN + TRẠNG THÁI TÀI KHOẢN LOGIN
    -- Mục đích: Gộp NhanVien từ 2 chi nhánh (LINK1 + LINK2) vì TRACUU không có local
    -- LEFT JOIN với QuanTriLogin để biết NV đã được cấp tài khoản chưa
    -- Xác định trạng thái DaCapTaiKhoan:
    --   0 = chưa cấp (không có record trong QuanTriLogin)
    --   1 = đã cấp và login đang active (tồn tại trong sys.server_principals)
    --   2 = đã cấp nhưng login bị xóa/disable (có record nhưng không tìm thấy trong sys)
    -- Chỉ lấy NV đang làm việc (TrangThaiXoa = 0)
    -- ==========================================================================
    SELECT
        'NhanVien' AS LoaiTK,
        nv.MANV AS MaThamChieu,
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
        RTRIM(nv.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS nv
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

    -- ==========================================================================
    -- BƯỚC 2: GỘP THÊM DANH SÁCH KHÁCH HÀNG + TRẠNG THÁI LOGIN
    -- Mục đích: KhachHang được replicate full trên TRACUU → đọc local
    -- Cùng logic LEFT JOIN QuanTriLogin và kiểm tra sys.server_principals
    -- Lọc theo @MACN nếu có
    -- ==========================================================================
    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK,
        kh.CMND AS MaThamChieu,
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
        RTRIM(kh.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName,
        ql.NhomQuyen,
        ql.NgayTao,
        ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND) AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    -- ==========================================================================
    -- BƯỚC 3: SẮP XẾP KẾT QUẢ
    -- Mục đích: Nhóm theo loại TK (KhachHang/NhanVien), ưu tiên chưa cấp TK lên trước
    -- rồi sắp theo họ tên để dễ tìm kiếm
    -- ==========================================================================
    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
GO
