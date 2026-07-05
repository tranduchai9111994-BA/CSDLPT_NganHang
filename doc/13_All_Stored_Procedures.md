# Toàn bộ Stored Procedures hiện tại trong CSDL

Tài liệu này tổng hợp code mới nhất của tất cả các Stored Procedures đang chạy trong hệ thống (đã bao gồm các bản vá lỗi gần nhất).

**[Cập nhật 19/06/2026] Thông tin đưa vào Article (Replication):**
- **PUB_BENTHANH & PUB_TANDINH:** Đã add toàn bộ 11 SP nghiệp vụ bên dưới vào Article (chế độ Replicate stored procedure definitions).
- **PUB_TRACUU:** Article gồm: `sp_Login_App`, `SP_TaoTaiKhoan`, `sp_LietKeKhachHang`, `sp_LietKeTaiKhoanTheoNgay`, `sp_DanhSachTaiKhoan` (tổng 5 SP).
- **[Cập nhật 05/07/2026] SP riêng của TRACUU** (không qua Replication, cài bằng `setup_db.js` hoặc [`sql/deploy_tracuu.sql`](../sql/deploy_tracuu.sql)):
  - `sp_SaoKeToanBo` — gộp GD_GOIRUT + GD_CHUYENTIEN từ LINK1+LINK2
  - `sp_DanhSachNhanVien` — gộp NhanVien từ LINK1+LINK2 (TRACUU không có NhanVien local)
  - `SP_DanhSachTrangThaiLogin` — phiên bản TRACUU, đọc NhanVien qua LINK, KhachHang+QuanTriLogin local
- **[Cập nhật 05/07/2026] Lưu ý quan trọng về TaiKhoan:** TaiKhoan replicate full (giống ChiNhanh) → mỗi site đã có đủ TK cả 2 chi nhánh. SP trên TRACUU chỉ đọc từ **LINK1** (không UNION ALL LINK1+LINK2, vì sẽ bị duplicate). JOIN KhachHang local dùng **OUTER APPLY TOP 1** để tránh nhân bản kết quả.
- **Lưu ý:** Đã xoá bỏ `SP_DangNhap` (không phải là Article, xoá thành công bằng `DROP PROCEDURE IF EXISTS`).

## sp_ChuyenNhanVien
```sql
CREATE PROCEDURE [dbo].[sp_ChuyenNhanVien]
    @MANV nchar(10),
    @MACN_MOI nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Kiểm tra nhân viên có tồn tại và đang làm việc không
    IF NOT EXISTS (
        SELECT 1 FROM NhanVien 
        WHERE RTRIM(MANV) = RTRIM(@MANV) AND TrangThaiXoa = 0
    )
    BEGIN
        RAISERROR(N'Nhân viên không tồn tại hoặc đã nghỉ việc tại chi nhánh này.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        -- Bắt đầu giao dịch phân tán (vì sẽ thao tác trên 2 server khác nhau)
        BEGIN DISTRIBUTED TRANSACTION;
        
        -- Đọc thông tin nhân viên trước khi chuyển
        DECLARE @HO nvarchar(50), @TEN nvarchar(10), @CMND nchar(10);
        DECLARE @DIACHI nvarchar(100), @PHAI nvarchar(3), @SODT nvarchar(15);
        
        SELECT @HO = HO, @TEN = TEN, @CMND = CMND, 
               @DIACHI = DIACHI, @PHAI = PHAI, @SODT = SODT
        FROM NhanVien 
        WHERE RTRIM(MANV) = RTRIM(@MANV);

        -- ✅ ĐÚNG ĐỀ BÀI: Đánh dấu đã chuyển ở chi nhánh cũ (KHÔNG xóa hẳn)
        UPDATE NhanVien 
        SET TrangThaiXoa = 1 
        WHERE RTRIM(MANV) = RTRIM(@MANV);
        
        -- Chèn bản ghi mới vào chi nhánh đối tác qua Linked Server
        -- LINK1 luôn trỏ đến chi nhánh đối tác (quy tắc cố định)
        INSERT INTO [LINK1].NGANHANG.dbo.NhanVien 
            (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
        VALUES 
            (@MANV, @HO, @TEN, @CMND, @DIACHI, @PHAI, @SODT, @MACN_MOI, 0);
        -- TrangThaiXoa = 0 ở chi nhánh mới: nhân viên đang hoạt động

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

## sp_ChuyenTien
```sql
-- TaiKhoan được NHÂN BẢN TOÀN VẸN → mọi TK đều tồn tại local.
-- Dùng MACN để phân biệt: cùng CN → ghi local, khác CN → ghi qua LINK1.
CREATE   PROCEDURE [dbo].[sp_ChuyenTien]
    @SOTK_CHUYEN nchar(9),
    @SOTK_NHAN   nchar(9),
    @SOTIEN      money,
    @MANV        nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SOTIEN <= 0
    BEGIN
        RAISERROR(N'Số tiền chuyển phải lớn hơn 0.',16,1);
        RETURN;
    END

    -- Kiểm tra TK chuyển + lấy MACN (đọc local — nhân bản full)
    DECLARE @MACN_CHUYEN nchar(10);
    SELECT @MACN_CHUYEN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN);
    IF @MACN_CHUYEN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản chuyển không tồn tại.',16,1);
        RETURN;
    END

    -- Kiểm tra TK nhận + lấy MACN (đọc local — nhân bản full, không cần LINK1)
    DECLARE @MACN_NHAN nchar(10);
    SELECT @MACN_NHAN = RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
    IF @MACN_NHAN IS NULL
    BEGIN
        RAISERROR(N'Tài khoản nhận không tồn tại trên toàn hệ thống.',16,1);
        RETURN;
    END

    -- So sánh MACN: cùng CN → ghi local, khác CN → ghi qua LINK1
    DECLARE @IsNhanLocal bit = 0;
    IF @MACN_NHAN = @MACN_CHUYEN
        SET @IsNhanLocal = 1;

    BEGIN TRY
        BEGIN DISTRIBUTED TRANSACTION;

        UPDATE TaiKhoan 
        SET SODU = SODU - @SOTIEN 
        WHERE RTRIM(SOTK) = RTRIM(@SOTK_CHUYEN) AND SODU >= @SOTIEN;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Tài khoản chuyển không tồn tại hoặc số dư không đủ.',16,1);
            RETURN;
        END

        IF @IsNhanLocal = 1
        BEGIN
            UPDATE TaiKhoan 
            SET SODU = SODU + @SOTIEN 
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END
        ELSE
        BEGIN
            UPDATE [LINK1].NGANHANG.dbo.TaiKhoan 
            SET SODU = SODU + @SOTIEN 
            WHERE RTRIM(SOTK) = RTRIM(@SOTK_NHAN);
        END

        INSERT INTO GD_CHUYENTIEN(SOTK_CHUYEN, SOTK_NHAN, SOTIEN, NGAYGD, MANV)
        VALUES(@SOTK_CHUYEN, @SOTK_NHAN, @SOTIEN, GETDATE(), @MANV);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

## sp_GuiTien
```sql
CREATE  PROCEDURE sp_GuiTien
    @SOTK   nchar(9),
    @SOTIEN money,
    @MANV   nchar(10)
AS
BEGIN
    SET NOCOUNT ON

    -- Kiểm tra số tiền hợp lệ
    IF @SOTIEN < 100000
    BEGIN
        RAISERROR(N'Số tiền gửi tối thiểu là 100,000 VNĐ.', 16, 1)
        RETURN
    END

    -- Kiểm tra tài khoản tồn tại
    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE SOTK = @SOTK)
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại.', 16, 1)
        RETURN
    END

    BEGIN TRY
        BEGIN TRANSACTION

        -- Cập nhật số dư
        UPDATE TaiKhoan
        SET SODU = SODU + @SOTIEN
        WHERE SOTK = @SOTK

        -- Ghi giao dịch gửi tiền
        INSERT INTO GD_GOIRUT (SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
        VALUES (@SOTK, 'GT', GETDATE(), @SOTIEN, @MANV)

        COMMIT TRANSACTION

        PRINT N'Gửi tiền thành công.'
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION

        DECLARE @msg NVARCHAR(4000)
        SET @msg = ERROR_MESSAGE()

        RAISERROR(@msg, 16, 1)
    END CATCH
END
```

## sp_LietKeKhachHang
```sql
-- KhachHang replicate full trên mọi site → chỉ cần đọc local, không cần Linked Server.
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeKhachHang]
    @MACN nchar(10) = NULL  -- NULL = tất cả; có giá trị = lọc theo chi nhánh
AS
BEGIN
    SET NOCOUNT ON;

    SELECT HO, TEN, CMND, MACN, SODT
    FROM KhachHang
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
```

## sp_LietKeTaiKhoanTheoNgay *(TRACUU — đọc TaiKhoan qua LINK1)*
```sql
-- TaiKhoan replicate full → LINK1 đã có đủ data cả 2 CN. Không UNION ALL (sẽ duplicate).
-- JOIN KhachHang local dùng OUTER APPLY TOP 1 để tránh nhân bản kết quả.
CREATE OR ALTER PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,
    @TUNGAY date = NULL,
    @DENNGAY date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK) AS SOTK,
           RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU,
           RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
```

## sp_TaiKhoanKhachHang *(chạy trên BENTHANH/TANDINH — GRANT EXECUTE cho KhachHang)*
```sql
-- Trả danh sách TK thuộc về 1 CMND. KhachHang có EXECUTE nhưng không có SELECT trực tiếp
-- trên TaiKhoan → SP là cửa ngõ duy nhất, đảm bảo KhachHang chỉ thấy TK của mình.
CREATE OR ALTER PROCEDURE sp_TaiKhoanKhachHang
    @CMND nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM TaiKhoan tk
    WHERE RTRIM(tk.CMND) = RTRIM(@CMND)
    ORDER BY tk.NGAYMOTK DESC;
END
```

## sp_DanhSachTaiKhoan *(TRACUU — đọc TaiKhoan qua LINK1)*
```sql
-- TaiKhoan replicate full → LINK1 đã có đủ data cả 2 CN. Không UNION ALL (sẽ duplicate).
-- JOIN KhachHang local dùng OUTER APPLY TOP 1 để tránh nhân bản kết quả.
CREATE OR ALTER PROCEDURE sp_DanhSachTaiKhoan
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RTRIM(tk.SOTK)  AS SOTK,
           RTRIM(tk.CMND)  AS CMND,
           tk.SODU,
           RTRIM(tk.MACN)  AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen
    FROM [LINK1].NGANHANG.dbo.TaiKhoan tk
    OUTER APPLY (SELECT TOP 1 HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)) kh
    ORDER BY tk.NGAYMOTK DESC;
END
```

## sp_SaoKeToanBo *(TRACUU only — dùng LINK1+LINK2)*
```sql
-- Chạy trên TRACUU. Tổng hợp GD_GOIRUT + GD_CHUYENTIEN từ cả 2 chi nhánh
-- trong khoảng thời gian @TUNGAY–@DENNGAY, không lọc theo SOTK cụ thể.
CREATE OR ALTER PROCEDURE sp_SaoKeToanBo
    @TUNGAY datetime,
    @DENNGAY datetime
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(g.SOTK), g.NGAYGD, g.LOAIGD, g.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_GOIRUT g
    WHERE g.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_CHUYEN), c.NGAYGD, 'CT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    UNION ALL
    SELECT RTRIM(c.SOTK_NHAN), c.NGAYGD, 'NT', c.SOTIEN
    FROM [LINK2].NGANHANG.dbo.GD_CHUYENTIEN c
    WHERE c.NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ORDER BY NGAYGD;
END
```

## sp_Login_App
```sql
CREATE   PROCEDURE [dbo].[sp_Login_App]
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NHOM nvarchar(50), @MANV nvarchar(50), @HOTEN nvarchar(100), @MACN nvarchar(10);
    DECLARE @DBUserName nvarchar(128);

    -- Resolve DB user name từ login name (hỗ trợ login name khác user name)
    SELECT @DBUserName = dp.name
    FROM sys.database_principals dp
    JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE sp.name = @LoginName;

    -- Fallback: nếu login name = user name
    IF @DBUserName IS NULL SET @DBUserName = @LoginName;

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

    IF @NHOM != 'KhachHang'
    BEGIN
        SELECT @MANV = MANV, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM NhanVien
        WHERE RTRIM(MANV) = @DBUserName AND TrangThaiXoa = 0;

        IF @MANV IS NULL AND @NHOM = 'NganHang'
        BEGIN
            SET @MANV = @DBUserName;
            SET @HOTEN = N'Quan Tri Vien (Ban Giam Doc)';
            SET @MACN = (SELECT TOP 1 MACN FROM ChiNhanh);
        END
    END
    ELSE
    BEGIN
        SELECT @MANV = CMND, @HOTEN = RTRIM(HO) + ' ' + RTRIM(TEN), @MACN = MACN
        FROM KhachHang
        WHERE RTRIM(CMND) = @DBUserName;
    END

    IF @MANV IS NULL RETURN;

    SELECT
        @LoginName AS USERNAME,
        @MANV AS MANV,
        @HOTEN AS HOTEN,
        @NHOM AS NHOM,
        @MACN AS MACN;
END
```

## sp_MoTaiKhoan
```sql
CREATE   PROCEDURE [dbo].[sp_MoTaiKhoan]
    @SOTK nchar(9),
    @CMND nchar(10),
    @SODU money,
    @MACN nchar(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK))
    BEGIN
        RAISERROR(N'Số tài khoản đã tồn tại.',16,1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM LINK0.NGANHANG.dbo.KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng không tồn tại trên hệ thống.',16,1);
        RETURN;
    END

    INSERT INTO TaiKhoan(SOTK, CMND, SODU, MACN, NGAYMOTK)
    VALUES(@SOTK, @CMND, @SODU, @MACN, GETDATE());
END
```

## sp_RutTien
```sql
CREATE PROCEDURE [dbo].[sp_RutTien]
    @SOTK nchar(9),
    @SOTIEN money,
    @MANV nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- ✅ BẢN VÁ: Thêm kiểm tra số tiền tối thiểu (đúng đề bài)
    IF @SOTIEN < 100000
    BEGIN
        RAISERROR(N'Số tiền rút tối thiểu là 100,000 VNĐ.', 16, 1);
        RETURN;
    END

    -- Kiểm tra tài khoản tồn tại
    IF NOT EXISTS (SELECT 1 FROM TaiKhoan WHERE RTRIM(SOTK) = RTRIM(@SOTK))
    BEGIN
        RAISERROR(N'Tài khoản không tồn tại.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Trừ tiền + kiểm tra số dư đủ trong cùng 1 câu lệnh (atomic)
        UPDATE TaiKhoan 
        SET SODU = SODU - @SOTIEN 
        WHERE RTRIM(SOTK) = RTRIM(@SOTK) AND SODU >= @SOTIEN;
        -- Nếu SODU < @SOTIEN thì WHERE không match → @@ROWCOUNT = 0

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR(N'Số dư không đủ để rút.', 16, 1);
            RETURN;
        END

        -- Ghi log giao dịch rút tiền
        INSERT INTO GD_GOIRUT(SOTK, LOAIGD, NGAYGD, SOTIEN, MANV)
        VALUES(@SOTK, 'RT', GETDATE(), @SOTIEN, @MANV);
        -- LOAIGD = 'RT' nghĩa là Rút Tiền

        COMMIT TRANSACTION;
        PRINT N'Rút tiền thành công.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

## SP_SaoKeTaiKhoan
```sql
CREATE   PROCEDURE SP_SaoKeTaiKhoan
    @SOTK NVARCHAR(50),
    @TUNGAY DATETIME,
    @DENNGAY DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    -- =========================================================================================
    -- BÆ¯á»šC 1: KIá»‚M TRA TÃ€I KHOáº¢N VÃ€ Láº¤Y Sá» DÆ¯ HIá»†N Táº I (Táº I THá»œI ÄIá»‚M CHáº Y BÃO CÃO)
    -- =========================================================================================
    DECLARE @SODU_HIENTAI MONEY;
    
    -- Æ¯u tiÃªn tÃ¬m á»Ÿ máº£nh Local trÆ°á»›c
    SELECT @SODU_HIENTAI = SODU FROM TaiKhoan WHERE SOTK = @SOTK;
    
    -- Náº¿u khÃ´ng cÃ³ á»Ÿ Local, tÃ¬m á»Ÿ Linked Server (chi nhÃ¡nh Ä‘á»‘i tÃ¡c)
    IF @SODU_HIENTAI IS NULL
    BEGIN
        SELECT @SODU_HIENTAI = SODU FROM [LINK1].NGANHANG.dbo.TaiKhoan WHERE SOTK = @SOTK;
    END

    -- Náº¿u tÃ¬m cáº£ 2 nÆ¡i khÃ´ng tháº¥y, bÃ¡o lá»—i vÃ  thoÃ¡t
    IF @SODU_HIENTAI IS NULL
    BEGIN
        RAISERROR(N'TÃ i khoáº£n khÃ´ng tá»“n táº¡i trÃªn há»‡ thá»‘ng.', 16, 1);
        RETURN;
    END

    -- =========================================================================================
    -- BÆ¯á»šC 2: Tá»I Æ¯U HÃ“A - TÃNH Sá» DÆ¯ Äáº¦U Ká»² Báº°NG CÃCH "TRá»ª NGÆ¯á»¢C" Tá»ª HIá»†N Táº I
    -- Thay vÃ¬ lÃ´i toÃ n bá»™ dá»¯ liá»‡u tá»« quÃ¡ khá»© (tá»‘n Network IO vÃ  Memory), ta láº¥y Sá»‘ dÆ° hiá»‡n táº¡i
    -- trá»« Ä‘i tá»•ng cÃ¡c biáº¿n Ä‘á»™ng diá»…n ra tá»« @TUNGAY cho Ä‘áº¿n nay (>= @TUNGAY).
    -- Äiá»u nÃ y báº£o Ä‘áº£m chÃ­nh xÃ¡c 100% ká»ƒ cáº£ khi tÃ i khoáº£n cÃ³ sá»‘ dÆ° khá»Ÿi táº¡o khÃ´ng náº±m trong báº£ng GD.
    -- =========================================================================================
    DECLARE @BIENDONG_SAU_TUNGAY MONEY = 0;

    SELECT @BIENDONG_SAU_TUNGAY = ISNULL(SUM(
        CASE 
            WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN
            WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN
            ELSE 0
        END
    ), 0)
    FROM (
        -- CÃ¡c giao dá»‹ch phÃ¡t sinh Tá»ª @TUNGAY trá»Ÿ vá» sau táº¡i Local
        SELECT SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
        
        UNION ALL
        
        -- CÃ¡c giao dá»‹ch phÃ¡t sinh Tá»ª @TUNGAY trá»Ÿ vá» sau táº¡i Linked Server
        SELECT SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD >= @TUNGAY
        UNION ALL
        SELECT SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD >= @TUNGAY
    ) AS LstBienDong;

    DECLARE @SODU_DAUKY MONEY = @SODU_HIENTAI - @BIENDONG_SAU_TUNGAY;

    -- =========================================================================================
    -- BÆ¯á»šC 3: TRÃCH XUáº¤T CHI TIáº¾T GIAO Dá»ŠCH TRONG Ká»² VÃ€ TÃNH Sá» DÆ¯ LÅ¨Y Káº¾
    -- DÃ¹ng CTE giá»›i háº¡n Ä‘Ãºng trong khoáº£ng [@TUNGAY, @DENNGAY] Ä‘á»ƒ giáº£m táº£i dá»¯ liá»‡u truyá»n máº¡ng.
    -- DÃ¹ng Window Function káº¿t há»£p vá»›i @SODU_DAUKY Ä‘á»ƒ ra sá»‘ dÆ° lÅ©y káº¿ chÃ­nh xÃ¡c sau má»—i GD.
    -- =========================================================================================
    WITH TransactionsInPeriod AS (
        SELECT NGAYGD, SOTIEN, LOAIGD FROM GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        
        UNION ALL
        
        SELECT NGAYGD, SOTIEN, LOAIGD FROM [LINK1].NGANHANG.dbo.GD_GOIRUT WHERE SOTK = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'CT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_CHUYEN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
        UNION ALL
        SELECT NGAYGD, SOTIEN, 'NT' AS LOAIGD FROM [LINK1].NGANHANG.dbo.GD_CHUYENTIEN WHERE SOTK_NHAN = @SOTK AND NGAYGD BETWEEN @TUNGAY AND @DENNGAY
    ),
    RunningBalance AS (
        SELECT 
            NGAYGD,
            LOAIGD,
            SOTIEN,
            SODU_LUYKE = @SODU_DAUKY + SUM(
                CASE 
                    WHEN LOAIGD IN ('GT', 'NT') THEN SOTIEN
                    WHEN LOAIGD IN ('RT', 'CT') THEN -SOTIEN
                    ELSE 0
                END
            ) OVER (ORDER BY NGAYGD ASC ROWS UNBOUNDED PRECEDING)
        FROM TransactionsInPeriod
    )
    SELECT * 
    FROM RunningBalance 
    ORDER BY NGAYGD ASC;

END
```

## SP_TaoTaiKhoan
```sql
CREATE PROCEDURE [dbo].[SP_TaoTaiKhoan]
    @LGNAME VARCHAR(50), 
    @PASS VARCHAR(50), 
    @USERNAME VARCHAR(50), 
    @ROLE VARCHAR(50),
    @LOAITK VARCHAR(20),   -- 'NhanVien' hoặc 'KhachHang'
    @MATHAMCHIEU VARCHAR(50) -- MANV hoặc CMND
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS(SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
    BEGIN
        RAISERROR('Login name is already in use', 16, 1);
        RETURN 1;
    END

    IF EXISTS(SELECT 1 FROM sys.database_principals WHERE name = @USERNAME)
    BEGIN
        RAISERROR('User name is already in use in the current database', 16, 1);
        RETURN 2;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@PASS, '''', '''''');
        
        SET @SqlStr = 'CREATE LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;';
        EXEC(@SqlStr);

        SET @SqlStr = 'CREATE USER ' + QUOTENAME(@USERNAME) + ' FOR LOGIN ' + QUOTENAME(@LGNAME) + ';';
        EXEC(@SqlStr);

        SET @SqlStr = 'EXEC sp_addrolemember ''' + REPLACE(@ROLE, '''', '''''') + ''', ' + QUOTENAME(@USERNAME) + ';';
        EXEC(@SqlStr);

        -- Ghi vào bảng quản trị để phục vụ tính năng theo dõi + xem mật khẩu
        INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
        VALUES (@LGNAME, @PASS, @LOAITK, @MATHAMCHIEU, @ROLE, GETDATE());

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 3;
    END CATCH
END
```

## sp_ThemKhachHang
```sql
CREATE   PROCEDURE [dbo].[sp_ThemKhachHang]
    @CMND nchar(10),
    @HO nvarchar(40),
    @TEN nvarchar(10),
    @DIACHI nvarchar(100),
    @PHAI nvarchar(3),
    @NGAYCAP date,
    @SODT nvarchar(15),
    @MACN nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM KhachHang WHERE RTRIM(CMND) = RTRIM(@CMND))
    BEGIN
        RAISERROR(N'Khách hàng đã tồn tại.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        INSERT INTO KhachHang(CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT, MACN)
        VALUES(@CMND, @HO, @TEN, @DIACHI, @PHAI, @NGAYCAP, @SODT, @MACN);
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH
END
```

## SP_ResetMatKhau
```sql
CREATE PROCEDURE [dbo].[SP_ResetMatKhau]
    @LGNAME      VARCHAR(50),
    @MATKHAU_MOI VARCHAR(50) = '123456'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LGNAME)
    BEGIN
        RAISERROR(N'Login không tồn tại trên server này.', 16, 1);
        RETURN 1;
    END

    BEGIN TRY
        DECLARE @SqlStr VARCHAR(MAX);
        DECLARE @PassEscaped VARCHAR(50) = REPLACE(@MATKHAU_MOI, '''', '''''');

        SET @SqlStr = 'ALTER LOGIN ' + QUOTENAME(@LGNAME) + ' WITH PASSWORD = ''' + @PassEscaped + ''';';
        EXEC(@SqlStr);

        UPDATE dbo.QuanTriLogin
        SET MatKhauHienTai = @MATKHAU_MOI,
            NgayCapNhatMK  = GETDATE()
        WHERE LoginName = @LGNAME;

        RETURN 0;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN 2;
    END CATCH
END
```

## SP_DanhSachTrangThaiLogin
```sql
CREATE PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- TrangThaiTK: 0 = Chua cap, 1 = Da cap va login ton tai, 2 = Loi dong bo (trong QuanTriLogin nhung login bi xoa)
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
    FROM NhanVien nv
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(nv.MANV) AND ql.LoaiTaiKhoan = 'NhanVien'
    WHERE nv.TrangThaiXoa = 0
      AND (@MACN IS NULL OR RTRIM(nv.MACN) = RTRIM(@MACN))

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

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
```

## SP_XoaLoiDongBo
```sql
CREATE PROCEDURE [dbo].[SP_XoaLoiDongBo]
    @LoginName  VARCHAR(50),
    @UserName   VARCHAR(50) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    -- Xóa record trong QuanTriLogin
    DELETE FROM dbo.QuanTriLogin WHERE LoginName = @LoginName;

    -- DROP DB user nếu còn tồn tại
    DECLARE @TargetUser VARCHAR(50) = ISNULL(@UserName, @LoginName);
    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @TargetUser)
    BEGIN
        DECLARE @Sql NVARCHAR(200) = N'DROP USER ' + QUOTENAME(@TargetUser);
        EXEC sp_executesql @Sql;
    END

    RETURN 0;
END
```

## sp_DanhSachNhanVien *(TRACUU only — dùng LINK1+LINK2)*
```sql
-- TRACUU không có NhanVien local (PUB_TRACUU chỉ replicate KhachHang).
-- SP đọc NhanVien từ BENTHANH (LINK1) + TANDINH (LINK2).
-- Dùng bởi: nhanvien.js (NganHang GET /), quantri.js (getNhanVienList)
CREATE PROCEDURE [dbo].[sp_DanhSachNhanVien]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(MANV) AS MANV,
           RTRIM(HO) AS HO, RTRIM(TEN) AS TEN,
           RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
           RTRIM(CMND) AS CMND,
           RTRIM(MACN) AS MACN,
           SODT, DIACHI, TrangThaiXoa
    FROM (
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK1].NGANHANG.dbo.NhanVien
        UNION ALL
        SELECT MANV, HO, TEN, CMND, MACN, SODT, DIACHI, TrangThaiXoa
        FROM [LINK2].NGANHANG.dbo.NhanVien
    ) AS AllNV
    WHERE (@MACN IS NULL OR RTRIM(MACN) = RTRIM(@MACN))
    ORDER BY MACN, HO, TEN;
END
```

## sp_LietKeTaiKhoanTheoNgay *(phiên bản TRACUU — dùng LINK1+LINK2)*
```sql
-- Phiên bản chạy trên TRACUU. Bản gốc (ở SQL1/SQL2) đọc TaiKhoan local.
-- TRACUU không có TaiKhoan local → đọc qua LINK1+LINK2, JOIN KhachHang local.
-- Dùng bởi: baocao.js (NganHang liệt kê TK theo ngày)
CREATE PROCEDURE [dbo].[sp_LietKeTaiKhoanTheoNgay]
    @MACN nchar(10) = NULL,
    @TUNGAY date = NULL,
    @DENNGAY date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
           RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
           tk.SODU, RTRIM(tk.MACN) AS MACN,
           CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
    FROM (
        SELECT SOTK, CMND, SODU, MACN, NGAYMOTK
        FROM [LINK1].NGANHANG.dbo.TaiKhoan
        UNION ALL
        SELECT SOTK, CMND, SODU, MACN, NGAYMOTK
        FROM [LINK2].NGANHANG.dbo.TaiKhoan
    ) AS tk
    LEFT JOIN KhachHang kh ON RTRIM(tk.CMND) = RTRIM(kh.CMND)
    WHERE (@MACN IS NULL OR RTRIM(tk.MACN) = RTRIM(@MACN))
      AND (@TUNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) >= @TUNGAY)
      AND (@DENNGAY IS NULL OR CAST(tk.NGAYMOTK AS DATE) <= @DENNGAY)
    ORDER BY tk.NGAYMOTK DESC;
END
```

## SP_DanhSachTrangThaiLogin *(phiên bản TRACUU — NhanVien qua LINK)*
```sql
-- Phiên bản chạy trên TRACUU. Bản gốc (SQL1/SQL2) đọc NhanVien local.
-- TRACUU không có NhanVien → đọc qua LINK1+LINK2. KhachHang + QuanTriLogin vẫn local.
-- Dùng bởi: quantri.js (GET /login-management/list khi NganHang)
CREATE PROCEDURE [dbo].[SP_DanhSachTrangThaiLogin]
    @MACN nchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        'NhanVien' AS LoaiTK, nv.MANV AS MaThamChieu,
        RTRIM(nv.HO) + ' ' + RTRIM(nv.TEN) AS HoTen,
        RTRIM(nv.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName, ql.NhomQuyen, ql.NgayTao, ql.NgayCapNhatMK
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

    UNION ALL

    SELECT
        'KhachHang' AS LoaiTK, kh.CMND AS MaThamChieu,
        RTRIM(kh.HO) + ' ' + RTRIM(kh.TEN) AS HoTen,
        RTRIM(kh.MACN) AS MACN,
        CASE
            WHEN ql.LoginName IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ql.LoginName) THEN 1
            ELSE 2
        END AS DaCapTaiKhoan,
        ql.LoginName, ql.NhomQuyen, ql.NgayTao, ql.NgayCapNhatMK
    FROM KhachHang kh
    LEFT JOIN dbo.QuanTriLogin ql ON RTRIM(ql.MaThamChieu) = RTRIM(kh.CMND) AND ql.LoaiTaiKhoan = 'KhachHang'
    WHERE (@MACN IS NULL OR RTRIM(kh.MACN) = RTRIM(@MACN))

    ORDER BY LoaiTK, DaCapTaiKhoan ASC, HoTen;
END
```

