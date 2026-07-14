USE NGANHANG;
GO

-- ==========================================================================
-- SP MO TAI KHOAN (tao ban ghi TaiKhoan moi cho khach hang)
-- Chay tren: BENTHANH (SQL1), TANDINH (SQL2).
-- Goi boi: routes/taikhoan.js - POST /taikhoan/mo (qua execSPAdmin / sqlcmd)
--
-- KhachHang phan manh ngang -> local chi co KH chi nhanh minh.
-- Check KH can query ca LINK1 (chi nhanh doi tac).
--
-- Luu y merge replication: INSERT vao TaiKhoan kich hoat MSmerge_ins trigger.
-- Neu query LINK1 nam cung scope voi INSERT -> implicit distributed tran
-- conflict voi merge trigger -> session bi kill.
-- Giai phap: check KH (local + LINK1) TRUOC, luu ket qua vao bien.
-- INSERT nam trong BEGIN DISTRIBUTED TRANSACTION rieng, khong con LINK1 query.
-- Giong pattern sp_GuiTien: read truoc -> distributed tran chi chua write.
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_MoTaiKhoan]
    @SOTK nchar(9),         -- So tai khoan moi (da sinh san o tang app bang sinhSOTK)
    @CMND nchar(10),        -- So CMND cua khach hang dung ten TK
    @SODU money,            -- So du ban dau khi mo TK
    @MACN nchar(10)         -- Ma chi nhanh quan ly TK (= chi nhanh KH)
AS
BEGIN
    SET NOCOUNT ON;          -- Tat thong bao so dong anh huong (giam traffic)
    SET XACT_ABORT ON;       -- Tu dong ROLLBACK khi gap bat ky loi nao (bat buoc cho DTC)

    -- ======================================================================
    -- BUOC 1: Kiem tra khach hang ton tai (TRUOC distributed tran)
    -- KhachHang phan manh ngang: SQL1 chi co KH BENTHANH, SQL2 chi co KH TANDINH.
    -- Nen phai check ca local va LINK1 (chi nhanh doi tac) de ho tro cross-branch.
    -- QUAN TRONG: phai check TRUOC BEGIN DISTRIBUTED TRANSACTION.
    -- Neu check LINK1 nam cung scope voi INSERT -> merge trigger tao implicit
    -- distributed tran -> conflict -> SQL Server kill session.
    -- ======================================================================
    DECLARE @KHFound bit = 0;   -- Bien luu ket qua: 0 = chua tim thay, 1 = da tim thay

    -- Check 1: Tim KH trong bang KhachHang local (cung chi nhanh)
    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
        SET @KHFound = 1;       -- Tim thay KH o local -> khong can query LINK1

    -- Check 2: Neu local khong co -> query LINK1 (chi nhanh doi tac qua Linked Server)
    ELSE IF EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
        SET @KHFound = 1;       -- Tim thay KH o chi nhanh doi tac

    -- Neu ca local va LINK1 deu khong co -> bao loi, ket thuc SP
    IF @KHFound = 0
    BEGIN
        RAISERROR(N'Khach hang khong ton tai tren he thong.',16,1);
        RETURN;                 -- Thoat SP, khong INSERT
    END

    -- ======================================================================
    -- BUOC 2: INSERT trong BEGIN DISTRIBUTED TRANSACTION
    -- Scope nay CHI CO lenh INSERT, KHONG co bat ky query LINK1 nao.
    -- -> merge replication trigger (MSmerge_ins_*) hoat dong binh thuong
    --    trong distributed tran tuong minh, khong bi conflict.
    -- Sau INSERT, Merge Replication tu dong dong bo TK sang server doi tac.
    -- ======================================================================
    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;  -- Mo giao dich phan tan (MSDTC 2-phase commit)

        -- Chen ban ghi TaiKhoan moi
        -- SOTK: da sinh tu dong (BT0000001 / TD0000001) o tang app
        -- CMND: lien ket voi KhachHang (FK_TaiKhoan_KhachHang)
        -- MACN: chi nhanh quan ly TK (FK_TaiKhoan_ChiNhanh)
        -- NGAYMOTK: ngay mo TK = thoi diem hien tai
        INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK)
        VALUES(@SOTK, @CMND, @SODU, @MACN, GETDATE());

        COMMIT TRANSACTION;            -- Xac nhan giao dich -> MSDTC commit ca 2 site

    END TRY
    BEGIN CATCH
        -- Neu co loi bat ky -> ROLLBACK toan bo (ca 2 site nho MSDTC)
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        -- Lay thong bao loi goc va nem lai cho tang app xu ly
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
GO
