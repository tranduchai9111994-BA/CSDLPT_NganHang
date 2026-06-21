# 🚨 Báo Cáo Hiện Trạng Đồng Bộ Stored Procedures (Bất Đồng Nhất)

Sau khi chạy lệnh kiểm tra trực tiếp (`sys.procedures`) trên tất cả 4 Server trong hệ thống CSDL Phân Tán, tôi đã phát hiện ra sự bất đồng nhất cực kỳ nghiêm trọng về các Stored Procedures (SPs) giữa Site Chủ và các Site phân mảnh. 

Do tính chất của SQL Server Replication (đặc biệt là Transactional Replication), nếu khi cấu hình Publication bạn không check vào ô để tự động Replicate các SP, hoặc các SP được viết sau khi quá trình đồng bộ đã chạy, chúng sẽ **không tự động được đẩy xuống các phân mảnh**.

Dưới đây là chi tiết hiện trạng các SP đang có mặt trên từng Server:

## 1. NGUON (Site Chủ - `ES-HAITD16`)
Site Chủ hiện tại đang **thiếu trầm trọng** toàn bộ các SP nghiệp vụ. Nó chỉ đang chứa 3 SP cơ bản:
- `SP_DangNhap` (Bản cũ, lỗi thời)
- `sp_Login_App` (Bản chuẩn xác thực mới)
- `SP_TaoTaiKhoan` (Quản trị tạo tài khoản)
❌ **Thiếu:** Tất cả các SP Giao dịch, Báo cáo và Quản lý nhân sự (`sp_GuiTien`, `sp_ChuyenTien`, `SP_SaoKeTaiKhoan`...).

> ✅ **Cập nhật (đã xác nhận đúng theo thiết kế):** Việc NGUON thiếu các SP nghiệp vụ là **HỢP LÝ**, không phải lỗi. NGUON là Publisher, chỉ lưu dữ liệu gốc và phát hành Replication, không trực tiếp phục vụ giao dịch khách hàng. Chỉ cần đảm bảo NGUON có đủ `sp_Login_App` và `SP_TaoTaiKhoan` để phục vụ quản trị.

## 2. BENTHANH (Phân Mảnh 1 - `ES-HAITD16\SQL1`)
Đây là server chứa đầy đủ và cập nhật nhất các SP nghiệp vụ.
- `sp_Login_App`
- `SP_TaoTaiKhoan`
- `sp_ChuyenNhanVien`
- `sp_ChuyenTien`
- `sp_GuiTien`, `sp_RutTien`
- `sp_MoTaiKhoan`, `sp_ThemKhachHang`
- `SP_SaoKeTaiKhoan`
- `sp_LietKeTaiKhoanTheoNgay`
- `sp_LietKeKhachHang` (Duy nhất SQL1 có SP này)
✅ Đã dọn dẹp sạch sẽ các SP cũ như `SP_DangNhap` hay `sp_SaoKe`.

## 3. TANDINH (Phân Mảnh 2 - `ES-HAITD16\SQL2`)
Tân Định có gần đủ các SP nghiệp vụ nhưng lại chứa các "tàn dư" cũ và thiếu sót một vài SP so với Bến Thành.
- `SP_DangNhap` ⚠️ (SP cũ, rác chưa xóa)
- `sp_Login_App`, `SP_TaoTaiKhoan`
- `sp_ChuyenNhanVien`, `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`
- `sp_MoTaiKhoan`, `sp_ThemKhachHang`
- `SP_SaoKeTaiKhoan`
- `sp_LietKeTaiKhoanTheoNgay`
❌ **Thiếu:** `sp_LietKeKhachHang` (Không tồn tại trên SQL2).

> ⚠️ **Cập nhật cũ:** Không thể `DROP PROCEDURE dbo.SP_DangNhap` trực tiếp tại TANDINH do báo lỗi đang được sử dụng cho replication.
> ✅ **Cập nhật mới nhất [19/06/2026]:** Đã kiểm tra lại bằng `sp_helparticle` và xác nhận `SP_DangNhap` KHÔNG nằm trong Article nào (chỉ là SP rác sót lại). Đã tiến hành xoá thành công bằng lệnh `DROP PROCEDURE IF EXISTS SP_DangNhap;` mà không gặp lỗi khoá DDL.

## 4. TRACUU (Server Tra Cứu - `ES-HAITD16\SQL3`)
Server Tra Cứu đang ở trạng thái sơ sài nhất và chứa các SP rất cũ.
- *Đã xoá thành công `SP_DangNhap` [Cập nhật 19/06/2026]*
- `sp_SaoKe` ⚠️ (SP cũ, đã được thay bằng `SP_SaoKeTaiKhoan`)
- `sp_Login_App`
- `SP_TaoTaiKhoan`
❌ **Thiếu:** Hệ thống báo cáo cần truy vấn vào mảnh này nhưng lại không có các SP cần thiết tương ứng.

> ⚠️ **Cập nhật:** Khi chạy `CREATE OR ALTER PROCEDURE` lên `sp_Login_App` và `SP_TaoTaiKhoan` tại TRACUU, gặp lỗi:
> `Msg 21531/21530 - DDL command cannot be executed at the Subscriber. In a republishing hierarchy, DDL commands can only be executed at the root Publisher.`
> **Nguyên nhân:** Giống TANDINH — 2 SP này đã thuộc Publication, TRACUU (Subscriber) không có quyền sửa cấu trúc.
> **Hướng xử lý đã áp dụng:** Không `ALTER` lại 2 SP này tại TRACUU (giữ nguyên bản đã được Replicate sẵn). Nếu cần sửa nội dung, phải sửa tại NGUON (Publisher) và để Replication tự đẩy xuống.
>
> ✅ Đã bổ sung thành công 3 SP đọc/báo cáo còn thiếu: `SP_SaoKeTaiKhoan`, `sp_LietKeTaiKhoanTheoNgay`, `sp_LietKeKhachHang` (bản dành riêng cho TRACUU, dùng `[LINK1]`→BENTHANH và `[LINK2]`→TANDINH vì TRACUU không có dữ liệu giao dịch/tài khoản cục bộ).

---

## 🎯 Giải Pháp Khắc Phục (Action Plan)

1. **Chuẩn hóa SP trên toàn bộ hệ thống:** Cần phải có một file Script chứa toàn bộ SP chuẩn (hiện đang nằm ở `doc/All_Stored_Procedures.md`) và chạy Script đó lên **CẢ 4 SERVER**.
2. **Dọn dẹp rác:** Chạy lệnh `DROP PROCEDURE` để xóa bỏ `SP_DangNhap` và `sp_SaoKe` trên những mảnh còn tồn đọng (NGUON, TANDINH, TRACUU).
   > ⚠️ **Cập nhật:** Bước này KHÔNG thực hiện được tại TANDINH/TRACUU do bị Replication khoá (xem mục 3, 4 ở trên). Tại NGUON (Publisher) thì `DROP` được bình thường vì đây là gốc của Article.
3. **Mảnh NGUON:** Tuy mảnh Nguồn không trực tiếp thực thi giao dịch, nhưng việc thiếu SP sẽ gây lỗi khi tạo mới môi trường hoặc khi cấp quyền đồng bộ.
   > ✅ **Cập nhật:** Đã xác nhận lại — NGUON **không cần** đủ SP giao dịch như BENTHANH/TANDINH. Chỉ cần `sp_Login_App` + `SP_TaoTaiKhoan`.
4. **Mảnh TRACUU:** Bắt buộc phải có các SP như `sp_Login_App`, `SP_TaoTaiKhoan` và các SP đọc dữ liệu (nếu dùng SP để đọc) để phục vụ cho nhóm NganHang tra cứu.
   > ✅ **Cập nhật:** Đã hoàn tất bổ sung. Xem script `04_SP_TRACUU.sql`.

5. **(MỚI) Chuẩn hoá Login cấp Server (`HTKN`):** Phát hiện thêm một lớp vấn đề độc lập với SP — Login `HTKN` (tài khoản dùng chung cho ứng dụng Node.js, xem `database_connection.md`) **không tự động tồn tại trên tất cả 4 server**, vì Login là đối tượng cấp Server (instance-level), không nằm trong phạm vi đồng bộ của Replication (vốn chỉ đồng bộ ở cấp Database). Phải tạo `HTKN` thủ công ở từng instance, đồng thời cấu hình lại `sp_addlinkedsrvlogin` đúng mật khẩu cho từng Linked Server (LINK1, LINK2 tại TRACUU). Xem chi tiết quy trình xử lý tại file `Su_Co_Va_Xu_Ly.md`.

6. **(MỚI 21/06/2026) Triển khai SP Quản trị đồng loạt qua Node.js (`setup_db.js`):**
   Do giới hạn của Replication chặn các lệnh DDL (`ALTER PROCEDURE`) tại các Subscriber (Bến Thành, Tân Định, Tra Cứu), hệ thống đã xây dựng một script tự động: `APP_NGANHANG/setup_db.js`.
   - Script này sẽ chủ động kết nối trực tiếp đến **CẢ 4 SERVER** (`NGUON`, `BENTHANH`, `TANDINH`, `TRACUU`).
   - Tự động thực thi `CREATE/ALTER` các SP quản trị: `sp_Login_App`, `SP_TaoTaiKhoan`, `SP_ResetMatKhau`, `SP_DanhSachTrangThaiLogin`, `SP_XoaLoiDongBo` cùng bảng phụ `QuanTriLogin`.
   - **Kết quả:** Xoá bỏ hoàn toàn nỗi lo bất đồng nhất SP quản trị giữa các mảnh. Mọi server đều đang chạy chung một phiên bản Stored Procedure cấp quyền và xác thực mới nhất.