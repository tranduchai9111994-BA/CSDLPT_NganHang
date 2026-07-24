USE NGANHANG;
GO

-- ==========================================================================
-- SP MO TAI KHOAN (tao ban ghi TaiKhoan moi cho khach hang)
-- Chay tren: BENTHANH (SQL1), TANDINH (SQL2).
-- Goi boi: routes/taikhoan.js - POST /taikhoan/mo (qua execSPAdmin / sqlcmd)
--
-- === CO CHE PHAN TAN ===
-- KhachHang phan manh ngang -> local chi co KH chi nhanh minh.
-- Check KH can query ca LINK1 (chi nhanh doi tac).
--
-- Luu y merge replication: INSERT vao TaiKhoan kich hoat MSmerge_ins trigger.
-- Neu query LINK1 nam cung scope voi INSERT -> implicit distributed tran
-- conflict voi merge trigger -> session bi kill.
-- Giai phap: check KH (local + LINK1) TRUOC, luu ket qua vao bien.
-- INSERT nam trong BEGIN DISTRIBUTED TRANSACTION rieng, khong con LINK1 query.
--
-- === CO CHE SINH SOTK (fix race condition #3) ===
-- SOTK duoc sinh BEN TRONG SP (khong con o tang app) de tranh race condition
-- khi 2 NV cung luc mo TK. Prefix lay theo @MACN (chi nhanh so huu TK):
--   MACN = 'BENTHANH' -> prefix 'BT'
--   MACN = 'TANDINH'  -> prefix 'TD'
-- Vong WHILE retry toi da 5 lan neu gap PK violation (error 2627) -> ROLLBACK +
-- tang so + thu lai. Neu 5 lan deu fail -> nem loi "he thong ban".
-- SP tra ve @SOTK moi qua SELECT de app hien thi cho user.
--
-- === NGHIEP VU MO TK CROSS-BRANCH ===
-- KH BENTHANH co the mo TK "thuoc" TANDINH neu he thong cho phep:
-- app truyen @MACN = TANDINH, SP se sinh SOTK bat dau bang 'TD',
-- INSERT tren server dich (chinh SP nay chay tren SQL2 khi crossBranch).
-- ==========================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_MoTaiKhoan]
    @CMND nchar(10),        -- So CMND cua khach hang dung ten TK
    @SODU money,            -- So du ban dau khi mo TK
    @MACN nchar(10)         -- Ma chi nhanh so huu TK (quyet dinh prefix SOTK)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ======================================================================
    -- BUOC 1: Kiem tra khach hang ton tai (TRUOC distributed tran)
    -- KhachHang phan manh ngang: SQL1 chi co KH BENTHANH, SQL2 chi co KH TANDINH.
    -- Nen phai check ca local va LINK1 (chi nhanh doi tac) de ho tro cross-branch.
    -- QUAN TRONG: phai check TRUOC BEGIN DISTRIBUTED TRANSACTION.
    -- Neu check LINK1 nam cung scope voi INSERT -> merge trigger tao implicit
    -- distributed tran -> conflict -> SQL Server kill session.
    -- ======================================================================
    DECLARE @KHFound bit = 0;

    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
        SET @KHFound = 1;
    ELSE IF EXISTS (SELECT 1 FROM [LINK1].NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
        SET @KHFound = 1;

    IF @KHFound = 0
    BEGIN
        RAISERROR(N'Khach hang khong ton tai tren he thong.',16,1);
        RETURN;
    END

    -- ======================================================================
    -- BUOC 2: Xac dinh prefix SOTK theo @MACN
    -- BENTHANH -> 'BT', TANDINH -> 'TD'. Neu MACN khong hop le -> RAISERROR.
    -- ======================================================================
    DECLARE @Prefix nchar(2);
    SET @Prefix = CASE RTRIM(@MACN)
                    WHEN 'BENTHANH' THEN 'BT'
                    WHEN 'TANDINH'  THEN 'TD'
                    ELSE NULL
                  END;

    IF @Prefix IS NULL
    BEGIN
        RAISERROR(N'MACN khong hop le. Chi ho tro BENTHANH hoac TANDINH.', 16, 1);
        RETURN;
    END

    -- ======================================================================
    -- BUOC 3: Vong WHILE retry sinh SOTK va INSERT
    -- Toi da 5 lan thu. Moi lan:
    --   3a. Tim SOTK lon nhat theo prefix -> +1 -> pad 7 chu so
    --   3b. BEGIN DISTRIBUTED TRANSACTION
    --   3c. INSERT
    --   3d. Neu PK violation (error 2627) -> ROLLBACK + tang bien counter -> thu lai
    --   3e. Loi khac -> THROW ra ngoai
    -- ======================================================================
    DECLARE @Attempt int = 0;
    DECLARE @MaxAttempt int = 5;
    DECLARE @SOTK nchar(9);
    DECLARE @Max nchar(9);
    DECLARE @Num int;

    WHILE @Attempt < @MaxAttempt
    BEGIN
        -- 3a. Sinh SOTK moi tu MAX(SOTK) hien tai + 1
        SET @Max = NULL;
        SELECT TOP 1 @Max = SOTK
        FROM TaiKhoan
        WHERE SOTK LIKE @Prefix + '%'
        ORDER BY SOTK DESC;

        IF @Max IS NULL
            SET @Num = 1;
        ELSE
            SET @Num = CAST(SUBSTRING(RTRIM(@Max), 3, 7) AS INT) + 1;

        -- Neu da retry vai lan, cong them counter de nhay so cao hon
        SET @Num = @Num + @Attempt;

        SET @SOTK = @Prefix + RIGHT('0000000' + CAST(@Num AS VARCHAR(7)), 7);

        -- 3b + 3c. INSERT trong distributed transaction
        BEGIN TRY
            BEGIN DISTRIBUTED TRANSACTION;

            INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK)
            VALUES(@SOTK, @CMND, @SODU, @MACN, GETDATE());

            COMMIT TRANSACTION;

            -- Thanh cong -> tra SOTK moi cho app va thoat vong lap
            SELECT @SOTK AS SOTK;
            RETURN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

            -- Error 2627 = Violation of PRIMARY KEY constraint (SOTK bi trung)
            -- Error 2601 = Cannot insert duplicate key row in object (unique index)
            IF ERROR_NUMBER() IN (2627, 2601)
            BEGIN
                SET @Attempt = @Attempt + 1;
                -- Tiep tuc vong WHILE de thu SOTK khac
            END
            ELSE
            BEGIN
                -- Loi khac (VD: FK violation, connection loi...) -> throw ngay
                DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
                RAISERROR(@ErrMsg, 16, 1);
                RETURN;
            END
        END CATCH
    END

    -- Da retry 5 lan van fail -> tra loi "he thong ban"
    RAISERROR(N'He thong ban, khong sinh duoc SOTK sau nhieu lan thu. Vui long thu lai.', 16, 1);
END
GO
