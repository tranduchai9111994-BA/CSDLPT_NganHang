# 🔧 Bản Vá Stored Procedures — Sửa Lỗi Logic Theo Đề Bài

> **Mục đích:** Sửa 2 lỗi logic trong SP hiện tại để đúng yêu cầu đề bài.  
> **Ưu tiên:** CAO — Sai đề bài = bị trừ điểm trực tiếp + dễ bị hỏi xoáy vấn đáp.

---

## Vấn đề 1: `sp_ChuyenNhanVien` — DELETE → phải là UPDATE TrangThaiXoa = 1

### Đề bài yêu cầu gì?

> "Khi chuyển một nhân viên từ chi nhánh này sang chi nhánh kia thì tự động chuyển dữ liệu  
> của nhân viên đó sang chi nhánh mới (Đổi MACN) đồng thời **cập nhật trạng thái xóa  
> của nhân viên đó ở chi nhánh cũ là 1**."

Hai từ khóa quan trọng: **"cập nhật trạng thái xóa"** và **"ở chi nhánh cũ"**.  
→ Giữ lại bản ghi cũ, đánh dấu `TrangThaiXoa = 1`. Không phải xóa hẳn.

### Vì sao phải giữ lại bản ghi cũ?

Lý do nghiệp vụ ngân hàng:
- Nhân viên cũ đã xử lý các giao dịch (`GD_GOIRUT`, `GD_CHUYENTIEN` có cột `MANV`).
- Nếu xóa hẳn bản ghi nhân viên → các giao dịch cũ bị mất tham chiếu (orphan FK).
- Ngân hàng cần lưu vết ai đã từng làm ở chi nhánh nào để phục vụ kiểm toán (audit).

### Code hiện tại (SAI)

```sql
-- ❌ SAI: Xóa hẳn bản ghi ở chi nhánh cũ
DELETE FROM NhanVien WHERE RTRIM(MANV) = RTRIM(@MANV);
```

### Code đúng (BẢN VÁ)

```sql
-- Chạy lệnh ALTER tại BENTHANH (SQL1) và TANDINH (SQL2)
-- KHÔNG chạy tại NGUON vì SP này không phải Article của Replication

ALTER PROCEDURE [dbo].[sp_ChuyenNhanVien]
    @MANV nchar(10),
    @MACN_MOI nchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- SET XACT_ABORT ON: nếu bất kỳ lỗi nào xảy ra, tự động ROLLBACK toàn bộ
    -- Đặc biệt quan trọng khi dùng DISTRIBUTED TRANSACTION

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

### Giải thích sự khác biệt

| Phần | Bản cũ (SAI) | Bản vá (ĐÚNG) |
|---|---|---|
| Xử lý ở chi nhánh cũ | `DELETE` — xóa hẳn | `UPDATE TrangThaiXoa = 1` — giữ bản ghi |
| Kiểm tra trước khi chuyển | Chỉ check `EXISTS` | Check `EXISTS` + `TrangThaiXoa = 0` |
| Bản ghi ở chi nhánh cũ sau khi chuyển | Biến mất | Vẫn còn, đánh dấu đã chuyển |
| Tham chiếu từ bảng giao dịch | Bị treo (orphan FK) | Vẫn hợp lệ |

### ⚠️ Điểm dễ bị hỏi vấn đáp

**Câu hỏi:** "Vì sao không xóa hẳn nhân viên khi chuyển chi nhánh?"

**Gợi ý trả lời:** "Vì nhân viên đó đã thực hiện các giao dịch trước đó (bảng GD_GOIRUT và GD_CHUYENTIEN có tham chiếu MANV). Nếu xóa hẳn sẽ mất tham chiếu. Ngoài ra, ngân hàng cần lưu vết lịch sử làm việc cho mục đích kiểm toán, nên chỉ đánh dấu TrangThaiXoa = 1 chứ không xóa."

**Câu hỏi:** "Nếu nhân viên đã bị đánh dấu TrangThaiXoa = 1 rồi, có chuyển tiếp được không?"

**Gợi ý trả lời:** "Không, vì SP đã check điều kiện `TrangThaiXoa = 0`. Nhân viên phải đang làm việc mới cho chuyển. Muốn chuyển lại phải Phục hồi trước (set TrangThaiXoa = 0)."

---

## Vấn đề 2: `sp_RutTien` — Thiếu kiểm tra số tiền tối thiểu 100.000đ

### Đề bài yêu cầu gì?

> "Số tiền gửi / rút **lớn hơn 100.000đ**."

### So sánh 2 SP hiện tại

| SP | Check hiện tại | Đúng chưa? |
|---|---|---|
| `sp_GuiTien` | `IF @SOTIEN < 100000` → ✅ Đã có | OK |
| `sp_RutTien` | `IF @SOTIEN <= 0` → ❌ Chỉ check > 0 | **THIẾU** |

### Code cần thêm vào `sp_RutTien`

```sql
-- Chạy ALTER tại BENTHANH (SQL1) và TANDINH (SQL2)

ALTER PROCEDURE [dbo].[sp_RutTien]
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

### Thay đổi so với bản cũ

Chỉ thay 1 đoạn duy nhất ở đầu SP:

```diff
- IF @SOTIEN <= 0
- BEGIN
-     RAISERROR(N'Số tiền rút phải lớn hơn 0.',16,1);
-     RETURN;
- END
+ IF @SOTIEN < 100000
+ BEGIN
+     RAISERROR(N'Số tiền rút tối thiểu là 100,000 VNĐ.', 16, 1);
+     RETURN;
+ END
```

Logic: `< 100000` bao gồm luôn cả trường hợp `<= 0`, nên không cần check riêng `> 0` nữa.

### ⚠️ Điểm dễ bị hỏi vấn đáp

**Câu hỏi:** "Tại sao check < 100000 mà không phải <= 100000?"

**Gợi ý trả lời:** "Đề bài nói 'lớn hơn 100.000đ', có thể hiểu là > 100.000 (strictly greater) hoặc >= 100.000 (cho phép đúng 100.000). Trong thực tế ngân hàng, gửi/rút đúng 100.000đ vẫn hợp lệ, nên em dùng `< 100000` tức là cho phép từ 100.000 trở lên."

---

## Checklist Thực Hiện Bản Vá

- [ ] Mở SSMS, kết nối vào **BENTHANH (SQL1)**
- [ ] Chạy `ALTER PROCEDURE sp_ChuyenNhanVien` (bản vá ở trên)
- [ ] Chạy `ALTER PROCEDURE sp_RutTien` (bản vá ở trên)
- [ ] Kết nối vào **TANDINH (SQL2)**
- [ ] Chạy lại cùng 2 lệnh `ALTER` ở trên (SP phải giống nhau ở cả 2 mảnh)
- [ ] Test: Chuyển nhân viên từ BT sang TD → kiểm tra BT vẫn còn bản ghi với TrangThaiXoa = 1
- [ ] Test: Rút tiền < 100.000 → phải báo lỗi
- [ ] Test: Rút tiền >= 100.000 với đủ số dư → phải thành công
- [ ] Cập nhật lại file `All_Stored_Procedures.md` với code mới

---

## Ghi Chú Bổ Sung: SP nào cần chạy ở TRACUU (SQL3)?

TRACUU **KHÔNG CẦN** 2 SP này vì:
- `sp_ChuyenNhanVien`: Chỉ nhân viên (nhóm ChiNhanh) mới chuyển NV, và họ login vào SQL1/SQL2, không vào SQL3.
- `sp_RutTien`: Tương tự, giao dịch rút tiền chỉ diễn ra tại chi nhánh (SQL1/SQL2).

TRACUU chỉ cần các SP đọc/báo cáo: `sp_Login_App`, `SP_TaoTaiKhoan`, `SP_SaoKeTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay`, `sp_LietKeKhachHang`.
