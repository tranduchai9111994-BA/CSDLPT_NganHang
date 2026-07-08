USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP DANH SÁCH TRẠNG THÁI LOGIN (phiên bản TRACUU — chạy trên SQL3)
-- Gộp NhanVien + KhachHang, hiển thị trạng thái cấp tài khoản đăng nhập.
-- TRACUU không có NhanVien local → đọc qua LINK1+LINK2.
-- KhachHang, QuanTriLogin, sys.server_principals đều local trên TRACUU.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL  -- Tham số: mã chi nhánh, NULL = tất cả
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng

    -- ==========================================================================
    -- BƯỚC 1: DANH SÁCH NHÂN VIÊN + TRẠNG THÁI TÀI KHOẢN LOGIN
    -- Gộp NV từ 2 chi nhánh (LINK1 + LINK2) vì TRACUU không có NV local
    -- LEFT JOIN QuanTriLogin để biết NV đã được cấp TK đăng nhập chưa
    -- ==========================================================================
    SELECT
        'NhanVien' AS LoaiTK,          -- Cột phân loại: đây là dòng nhân viên
        nv.MANV AS MaThamChieu,        -- Mã nhân viên (dùng làm mã tham chiếu)
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,  -- Ghép họ + tên đầy đủ
        RTRIM(nv.MACN) AS MACN,        -- Mã chi nhánh của NV
        -- Xác định trạng thái cấp tài khoản:
        CASE
            WHEN ql.LoginName IS NULL THEN 0  -- 0 = chưa cấp (không có record trong QuanTriLogin)
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1  -- 1 = đã cấp, login đang active
            ELSE 2  -- 2 = đã cấp nhưng login bị xóa/disable trên server
        END AS DaCapTaiKhoan,
        ql.LoginName,     -- Tên login (NULL nếu chưa cấp)
        ql.NhomQuyen,     -- Role được gán (NganHang/ChiNhanh)
        ql.NgayTao,       -- Ngày tạo tài khoản
        ql.NgayCapNhatMK  -- Ngày cập nhật mật khẩu gần nhất
    FROM (
        -- Gộp NV từ BENTHANH (LINK1)
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien  -- Đọc NV từ chi nhánh BENTHANH

        UNION ALL  -- Gộp thêm (giữ bản ghi trùng)

        -- Gộp NV từ TANDINH (LINK2)
        SELECT MANV, HO, TEN, CMND, MACN, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien  -- Đọc NV từ chi nhánh TANDINH
    ) AS nv  -- Alias cho subquery gộp 2 chi nhánh
    -- LEFT JOIN: giữ tất cả NV, kể cả NV chưa có TK đăng nhập (LoginName = NULL)
    LEFT JOIN dbo.QuanTriLogin ql
        ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV)  -- Khớp theo mã nhân viên
       AND ql.LoaiTaiKhoan = 'NhanVien'             -- Chỉ khớp loại NhanVien
    WHERE nv.TrangThaiXoa = 0  -- Chỉ lấy NV đang làm việc (chưa bị xóa/chuyển)
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)

    -- ==========================================================================
    -- BƯỚC 2: GỘP THÊM DANH SÁCH KHÁCH HÀNG + TRẠNG THÁI LOGIN
    -- KhachHang được replicate full trên TRACUU → đọc local
    -- Cùng logic LEFT JOIN và kiểm tra sys.server_principals
    -- ==========================================================================
    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK,        -- Cột phân loại: đây là dòng khách hàng
        kh.CMND AS MaThamChieu,        -- Số CMND (dùng làm mã tham chiếu cho KH)
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,  -- Ghép họ + tên KH
        RTRIM(kh.MACN) AS MACN,        -- Mã chi nhánh của KH
        CASE
            WHEN ql.LoginName IS NULL THEN 0  -- 0 = chưa cấp TK đăng nhập
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1  -- 1 = đã cấp, active
            ELSE 2  -- 2 = đã cấp nhưng login bị xóa/disable
        END AS DaCapTaiKhoan,
        ql.LoginName,     -- Tên login
        ql.NhomQuyen,     -- Role được gán (KhachHang)
        ql.NgayTao,       -- Ngày tạo TK
        ql.NgayCapNhatMK  -- Ngày cập nhật mật khẩu
    FROM KhachHang kh  -- Đọc bảng KhachHang local (replicate full trên TRACUU)
    LEFT JOIN dbo.QuanTriLogin ql
        ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND)  -- Khớp theo số CMND
       AND ql.LoaiTaiKhoan = 'KhachHang'            -- Chỉ khớp loại KhachHang
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))  -- Lọc theo chi nhánh (tùy chọn)

    -- ==========================================================================
    -- BƯỚC 3: SẮP XẾP KẾT QUẢ
    -- Nhóm theo loại TK, ưu tiên chưa cấp TK lên trước, rồi theo họ tên
    -- ==========================================================================
    ORDER BY LoaiTK,           -- Nhóm NhanVien trước, KhachHang sau
             DaCapTaiKhoan ASC,  -- Ưu tiên chưa cấp TK (0) lên trước
             HoTen;             -- Sắp theo họ tên để dễ tìm kiếm
END
GO
