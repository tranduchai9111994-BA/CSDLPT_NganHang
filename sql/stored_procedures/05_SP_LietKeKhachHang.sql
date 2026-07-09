USE NGANHANG;  -- Chọn database NGANHANG để tạo SP
GO

-- SP LIỆT KÊ KHÁCH HÀNG
-- Tạo trên NGUON → Replication đẩy xuống chi nhánh + TRACUU.
-- Chỉ đọc bảng KhachHang local (nhân bản toàn vẹn, không cần Linked Server).
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeKhachHang]
    @MACN nchar(10) = NULL  -- Tham số đầu vào: mã chi nhánh, mặc định NULL = lấy tất cả
AS
BEGIN
    SET NOCOUNT ON;  -- Tắt thông báo đếm số dòng ảnh hưởng, tăng hiệu suất

    SELECT HO, TEN, CMND, MACN, SODT  -- Lấy họ, tên, CMND, mã chi nhánh, số điện thoại
    FROM KhachHang                     -- Đọc từ bảng KhachHang local (được nhân bản toàn vẹn)
    -- Nếu @MACN có giá trị → chỉ lấy KH thuộc chi nhánh đó
    -- Nếu @MACN = NULL → điều kiện bị bỏ qua → lấy tất cả KH (dùng cho admin)
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;  -- Sắp xếp theo chi nhánh, rồi theo họ tên
END
GO
