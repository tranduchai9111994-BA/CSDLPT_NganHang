USE NGANHANG;  -- Chọn database NGANHANG
GO

-- ==========================================================================
-- SP ĐĂNG NHẬP ỨNG DỤNG
-- Đồng bộ với bản deployed trong setup_db.js (alterSpLoginApp).
-- Thay đổi so với phiên bản cũ:
--   - Thêm bước resolve @DBUserName từ @LoginName qua sys.database_principals / sys.server_principals
--     để xử lý đúng trường hợp login name khác với DB user name.
--   - Bỏ nhánh "NHOM IS NULL → tự suy luận thành ChiNhanh" vì không đáng tin cậy.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_Login_App]
    @LoginName nvarchar(128)  -- Tham số: Tên login của người dùng đăng nhập
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm dòng ảnh hưởng
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);  -- Biến lưu kết quả
    DECLARE @DBUserName nvarchar(128);  -- Biến lưu tên user trong database (có thể khác login name)

    -- ==========================================================================
    -- BƯỚC 1: RESOLVE TÊN USER TRONG DATABASE TỪ LOGIN NAME
    -- Login name và DB user name có thể khác nhau (VD: login 'NV001' → user 'NV001_user')
    -- Dùng JOIN sys views để tìm DB user tương ứng với Login đang đăng nhập
    -- ==========================================================================
    SELECT @DBUserName = dp.name       -- Lấy tên user trong database
    FROM sys.database_principals dp    -- Bảng hệ thống: danh sách user trong DB
    JOIN sys.server_principals sp      -- Bảng hệ thống: danh sách login trên server
        ON dp.sid = sp.sid             -- JOIN theo SID (Security Identifier) — liên kết login với user
    WHERE sp.name = @LoginName;        -- Điều kiện: login name khớp tham số đầu vào

    -- Fallback: nếu không tìm thấy mapping → dùng login name làm user name
    IF @DBUserName IS NULL SET @DBUserName = @LoginName;

    -- ==========================================================================
    -- BƯỚC 2: XÁC ĐỊNH NHÓM QUYỀN (ROLE) CỦA USER
    -- Tìm user thuộc role nào (NganHang, ChiNhanh, KhachHang)
    -- Nếu không thuộc role nào → tài khoản chưa được phân quyền → báo lỗi
    -- ==========================================================================
    SELECT @NHOM = rp.name             -- Lấy tên role mà user thuộc về
    FROM sys.database_role_members rm  -- Bảng hệ thống: quan hệ user-role
    JOIN sys.database_principals dp    -- Bảng hệ thống: thông tin user
        ON rm.member_principal_id = dp.principal_id  -- JOIN: lấy user là thành viên
    JOIN sys.database_principals rp    -- Bảng hệ thống: thông tin role
        ON rm.role_principal_id = rp.principal_id    -- JOIN: lấy role chứa user
    WHERE dp.name = @DBUserName        -- Điều kiện: đúng user đang đăng nhập
      AND rp.name IN ('NganHang','ChiNhanh','KhachHang');  -- Chỉ tìm trong 3 role ứng dụng

    IF @NHOM IS NULL  -- User không thuộc bất kỳ role nào → chưa phân quyền
    BEGIN
        RAISERROR(N'Tai khoan SQL chua duoc phan quyen Role (NganHang, ChiNhanh, KhachHang).', 16, 1);
        RETURN;  -- Kết thúc SP
    END

    -- ==========================================================================
    -- BƯỚC 3: LẤY THÔNG TIN CHI TIẾT THEO LOẠI TÀI KHOẢN
    -- Tùy theo role, lấy thông tin từ bảng khác nhau:
    --   NganHang/ChiNhanh → tìm trong bảng NhanVien (theo MANV)
    --   KhachHang → tìm trong bảng KhachHang (theo CMND)
    -- ==========================================================================
    IF @NHOM != 'KhachHang'  -- Nếu KHÔNG phải khách hàng → là nhân viên hoặc admin
    BEGIN
        -- Bước 3a: Tìm nhân viên đang làm việc (TrangThaiXoa = 0) có MANV khớp
        -- SQL3/TRACUU không có bảng NhanVien → bỏ qua bước này (OBJECT_ID trả NULL)
        IF OBJECT_ID('dbo.NhanVien', 'U') IS NOT NULL  -- Kiểm tra bảng NhanVien có tồn tại không
        BEGIN
            SELECT @MANV = MANV,                                    -- Lấy mã nhân viên
                   @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN),         -- Ghép họ + tên
                   @MACN = MACN                                     -- Lấy mã chi nhánh
            FROM NhanVien                                           -- Đọc bảng NhanVien local
            WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;  -- Khớp MANV + đang làm việc
        END

        -- Bước 3b: Nếu không tìm thấy NV nhưng role là NganHang → đây là admin (Ban Giám Đốc)
        IF @MANV IS NULL AND @NHOM = 'NganHang'
        BEGIN
            SET @MANV = @DBUserName;                        -- Dùng username làm mã NV
            SET @HOTEN = N'Quan Tri Vien (Ban Giam Doc)';   -- Tên hiển thị cho admin
            -- SQL3/TRACUU không có bảng ChiNhanh → hardcode MACN = 'TRACUU'
            IF OBJECT_ID('dbo.ChiNhanh', 'U') IS NOT NULL  -- Kiểm tra bảng ChiNhanh tồn tại
                SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh);  -- Lấy MACN đầu tiên từ bảng
            ELSE
                SET @MACN = N'TRACUU';  -- Không có bảng → gán mặc định 'TRACUU'
        END
    END
    ELSE  -- Role = KhachHang
    BEGIN
        -- Bước 3c: Khách hàng → tìm theo CMND trong bảng KhachHang
        SELECT @MANV = CMND,                                -- Dùng CMND làm mã tham chiếu
               @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN),     -- Ghép họ + tên KH
               @MACN = MACN                                 -- Lấy mã chi nhánh
        FROM KhachHang                                      -- Đọc bảng KhachHang local (nhân bản full)
        WHERE RTRIM(CMND) = @DBUserName;                    -- Khớp CMND với username
    END

    -- ==========================================================================
    -- BƯỚC 4: TRẢ VỀ KẾT QUẢ CHO ỨNG DỤNG
    -- Trả về thông tin đăng nhập (username, mã NV/KH, họ tên, role, chi nhánh)
    -- Nếu @MANV vẫn NULL → không tìm thấy thông tin → không trả kết quả
    -- ==========================================================================
    IF @MANV IS NULL RETURN;  -- Không tìm thấy → kết thúc, không trả gì

    SELECT
        @LoginName AS USERNAME,  -- Tên đăng nhập gốc
        @MANV      AS MANV,     -- Mã nhân viên hoặc CMND khách hàng
        @HOTEN     AS HOTEN,    -- Họ tên đầy đủ
        @NHOM      AS NHOM,     -- Nhóm quyền (NganHang/ChiNhanh/KhachHang)
        @MACN      AS MACN;     -- Mã chi nhánh
END
GO

GRANT EXECUTE ON dbo.sp_Login_App TO NganHang;   -- Cấp quyền thực thi cho admin
GRANT EXECUTE ON dbo.sp_Login_App TO ChiNhanh;   -- Cấp quyền thực thi cho nhân viên chi nhánh
GRANT EXECUTE ON dbo.sp_Login_App TO KhachHang;  -- Cấp quyền thực thi cho khách hàng
GO
