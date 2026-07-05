USE NGANHANG;
GO

-- SP LIỆT KÊ KHÁCH HÀNG
-- Tạo trên NGUON → Replication đẩy xuống chi nhánh + TRACUU.
-- Chỉ đọc bảng KhachHang local (nhân bản toàn vẹn, không cần Linked Server).
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeKhachHang]
    @MACN nchar(10) = NULL  -- NULL = tất cả; có giá trị = lọc theo chi nhánh
AS
BEGIN
    SET NOCOUNT ON;

    SELECT HO, TEN, CMND, MACN, SODT
    FROM KhachHang
    -- @MACN = 'BENTHANH' → chỉ lấy KH có MACN = 'BENTHANH' (đứng ở Bến Thành thì chỉ thấy KH Bến Thành)
    -- @MACN = NULL → bỏ qua điều kiện → lấy tất cả (admin trên TRACUU thấy full)
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
GO
