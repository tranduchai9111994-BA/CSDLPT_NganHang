USE NGANHANG;
GO

-- Đồng bộ với bản deployed trong setup_db.js (alterSpLoginApp).
-- Thay đổi so với phiên bản cũ:
--   - Thêm bước resolve @DBUserName từ @LoginName qua sys.database_principals / sys.server_principals
--     để xử lý đúng trường hợp login name khác với DB user name.
--   - Bỏ nhánh "NHOM IS NULL → tự suy luận thành ChiNhanh" vì không đáng tin cậy.
CREATE OR ALTER PROCEDURE [dbo].[sp_Login_App]
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);
    DECLARE @DBUserName nvarchar(128);

    -- ==========================================================================
    -- BƯỚC 1: RESOLVE TÊN USER TRONG DATABASE TỪ LOGIN NAME
    -- Mục đích: Login name và DB user name có thể khác nhau
    -- Dùng JOIN sys views để tìm DB user tương ứng với Login đang đăng nhập
    -- Fallback: nếu không tìm thấy mapping → dùng login name làm user name
    -- ==========================================================================
    SELECT @DBUserName = dp.name
    FROM sys.database_principals dp
    JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE sp.name = @LoginName;

    IF @DBUserName IS NULL SET @DBUserName = @LoginName;

    -- ==========================================================================
    -- BƯỚC 2: XÁC ĐỊNH NHÓM QUYỀN (ROLE) CỦA USER
    -- Mục đích: Tìm user thuộc role nào (NganHang, ChiNhanh, KhachHang)
    -- Nếu không thuộc role nào → tài khoản chưa được phân quyền → báo lỗi
    -- ==========================================================================
    SELECT @NHOM = rp.name
    FROM sys.database_role_members rm
    JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
    JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
    WHERE dp.name = @DBUserName
      AND rp.name IN ('NganHang','ChiNhanh','KhachHang');

    IF @NHOM IS NULL
    BEGIN
        RAISERROR(N'Tai khoan SQL chua duoc phan quyen Role (NganHang, ChiNhanh, KhachHang).', 16, 1);
        RETURN;
    END

    -- ==========================================================================
    -- BƯỚC 3: LẤY THÔNG TIN CHI TIẾT THEO LOẠI TÀI KHOẢN
    -- Mục đích: Tùy theo role, lấy thông tin từ bảng khác nhau
    --   - NganHang/ChiNhanh → tìm trong bảng NhanVien (theo MANV)
    --   - KhachHang → tìm trong bảng KhachHang (theo CMND)
    -- ==========================================================================
    IF @NHOM != 'KhachHang'
    BEGIN
        -- Bước 3a: Tìm nhân viên đang làm việc (TrangThaiXoa = 0) có MANV khớp
        SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM NhanVien
        WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;

        -- Bước 3b: Nếu không tìm thấy NV nhưng role là NganHang → đây là admin (Ban Giám Đốc)
        IF @MANV IS NULL AND @NHOM = 'NganHang'
        BEGIN
            SET @MANV = @DBUserName;
            SET @HOTEN = N'Quan Tri Vien (Ban Giam Doc)';
            SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh);
        END
    END
    ELSE
    BEGIN
        -- Bước 3c: Khách hàng → tìm theo CMND trong bảng KhachHang
        SELECT @MANV = CMND, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM KhachHang
        WHERE RTRIM(CMND) = @DBUserName;
    END

    -- ==========================================================================
    -- BƯỚC 4: TRẢ VỀ KẾT QUẢ CHO ỨNG DỤNG
    -- Mục đích: Trả về thông tin đăng nhập (username, mã NV/KH, họ tên, role, chi nhánh)
    -- Nếu @MANV vẫn NULL → không tìm thấy thông tin → không trả kết quả
    -- ==========================================================================
    IF @MANV IS NULL RETURN;

    SELECT
        @LoginName AS USERNAME,
        @MANV      AS MANV,
        @HOTEN     AS HOTEN,
        @NHOM      AS NHOM,
        @MACN      AS MACN;
END
GO

GRANT EXECUTE ON dbo.sp_Login_App TO NganHang;
GRANT EXECUTE ON dbo.sp_Login_App TO ChiNhanh;
GRANT EXECUTE ON dbo.sp_Login_App TO KhachHang;
GO
