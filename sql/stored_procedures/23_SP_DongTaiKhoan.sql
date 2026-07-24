USE NGANHANG;
GO

-- ==========================================================================
-- SP ĐÓNG TÀI KHOẢN (xóa TaiKhoan)
-- Chạy trên chi nhánh sở hữu TK (SQL1/SQL2).
-- Gọi bởi: routes/taikhoan.js — POST /taikhoan/dong.
--
-- === Cơ chế phân tán ===
-- TaiKhoan replicate FULL bằng merge replication.
--   → DELETE tại site sở hữu → merge trigger sync xóa sang site kia.
--   → KHÔNG cần DTC (không thao tác remote).
--
-- Guard nghiệp vụ (SQL-side, defense in depth):
--   G1. TK tồn tại.
--   G2. SODU = 0.
--   G3. TK cùng chi nhánh với NV (chỉ đóng TK cùng CN, không cross-branch).
--   G4. Không có bản ghi trong GD_GOIRUT (cả 2 site — phân mảnh ngang theo NV).
--   G5. Không có bản ghi trong GD_CHUYENTIEN (cả 2 site).
--
-- Ghi chú: GD_GOIRUT và GD_CHUYENTIEN phân mảnh ngang theo NV thực hiện GD,
-- KHÔNG theo MACN của TK. Do đó phải kiểm tra qua LINK1 để chắc chắn không
-- còn giao dịch nào tham chiếu SOTK này ở chi nhánh đối tác.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[SP_DongTaiKhoan]
    @SOTK NCHAR(9),
    @MANV NCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ======================================================================
    -- G1 + G2: TK tồn tại và SODU = 0
    -- ======================================================================
    DECLARE @MACN_TK NCHAR(10);
    DECLARE @SODU    MONEY;

    SELECT @MACN_TK = RTRIM(MACN),
           @SODU    = SODU
    FROM TaiKhoan
    WHERE RTRIM(SOTK) = RTRIM(@SOTK);

    IF @MACN_TK IS NULL
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại.', 16, 1);
        RETURN;
    END

    IF @SODU <> 0
    BEGIN
        RAISERROR(N'Không thể đóng tài khoản có số dư khác 0. Vui lòng rút hết tiền trước.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- G3: TK cùng chi nhánh với NV (chỉ đóng TK cùng CN)
    -- ======================================================================
    DECLARE @MACN_NV NCHAR(10);
    SELECT @MACN_NV = RTRIM(MACN)
    FROM NhanVien
    WHERE RTRIM(MANV) = RTRIM(@MANV);

    IF @MACN_NV IS NULL
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại tại chi nhánh này.', 16, 1);
        RETURN;
    END

    IF @MACN_TK <> @MACN_NV
    BEGIN
        RAISERROR(N'Chỉ nhân viên tại chi nhánh sở hữu tài khoản mới có quyền đóng tài khoản.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- G4: Không có bản ghi GD_GOIRUT (local + LINK1)
    -- ======================================================================
    DECLARE @GD_LOCAL INT;
    DECLARE @GD_REMOTE INT;

    SELECT @GD_LOCAL = COUNT(*)
    FROM GD_GOIRUT
    WHERE RTRIM(SOTK) = RTRIM(@SOTK);

    SELECT @GD_REMOTE = COUNT(*)
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT
    WHERE RTRIM(SOTK) = RTRIM(@SOTK);

    IF (@GD_LOCAL + @GD_REMOTE) > 0
    BEGIN
        RAISERROR(N'Không thể đóng tài khoản đã có giao dịch gửi/rút.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- G5: Không có bản ghi GD_CHUYENTIEN (local + LINK1)
    -- ======================================================================
    DECLARE @CT_LOCAL INT;
    DECLARE @CT_REMOTE INT;

    SELECT @CT_LOCAL = COUNT(*)
    FROM GD_CHUYENTIEN
    WHERE RTRIM(SOTK_CHUYEN) = RTRIM(@SOTK)
       OR RTRIM(SOTK_NHAN)   = RTRIM(@SOTK);

    SELECT @CT_REMOTE = COUNT(*)
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN
    WHERE RTRIM(SOTK_CHUYEN) = RTRIM(@SOTK)
       OR RTRIM(SOTK_NHAN)   = RTRIM(@SOTK);

    IF (@CT_LOCAL + @CT_REMOTE) > 0
    BEGIN
        RAISERROR(N'Không thể đóng tài khoản đã có giao dịch chuyển tiền.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- BƯỚC XÓA: DELETE trong local tran (merge replication tự sync)
    -- ======================================================================
    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM TaiKhoan
        WHERE RTRIM(SOTK) = RTRIM(@SOTK);

        COMMIT TRANSACTION;

        SELECT @SOTK AS SOTK_DA_DONG;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO

GRANT EXECUTE ON [dbo].[SP_DongTaiKhoan] TO NganHang;
GO
