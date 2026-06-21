# 🧪 TESTCASE BỔ SUNG (TC-14 → TC-17) — Đồ Án CSDL Phân Tán Ngân Hàng

> **File này dùng kèm với `98_testcase.md` (TC-00 → TC-13) đã có sẵn.**
> Không lặp lại nội dung cũ — chỉ bổ sung các thao tác trên **giao diện web** mà file gốc
> chưa test kỹ: Sửa/Xóa Khách hàng, Sửa/Thêm/Xóa Nhân viên, tạo Login cho Khách hàng
> qua màn hình Quản trị, và Reset mật khẩu.
>
> **Cách dùng:** Làm sau khi đã Pass TC-00 → TC-13. Đánh số tiếp theo TC-13 nên gọi là
> TC-14, TC-15, TC-16, TC-17 để không trùng số với file gốc.
> Tất cả testcase trong file này test trên **giao diện** (`http://localhost:3000`),
> KHÔNG thao tác trực tiếp trên database — chỉ dùng SSMS để **đối chiếu kết quả**, không phải để thực hiện hành động.

---

## TC-14. SỬA / XÓA KHÁCH HÀNG (BẮT BUỘC)

**Mục tiêu:** Đề bài yêu cầu form Khách hàng phải có đủ: Thêm, Sửa, Xóa, Phục hồi, Ghi, Thoát.
TC-02 (file gốc) mới test phần Thêm. File này test tiếp phần **Sửa** và **Xóa**.

**Chuẩn bị:** Login `NV01`/`BENTHANH`. Dùng KH `9999900001` đã tạo ở TC-02.

| # | Bước thực hiện | Kết quả mong đợi | Pass |
|---|---|---|---|
| 14.1 | Vào menu **Khách hàng**, tìm KH `9999900001`, bấm **Sửa** | Hiện form Sửa, các ô đã có sẵn dữ liệu cũ (Họ, Tên, Địa chỉ, SĐT...) | [ ] |
| 14.2 | Đổi SĐT thành `0909999999`, Địa chỉ thành `456 Nguyễn Huệ Q1` → bấm **Ghi** | Báo "Cập nhật thành công". Quay về danh sách, thấy dữ liệu mới | [ ] |
| 14.3 | Mở lại form Sửa của KH này lần nữa để kiểm tra | SĐT và Địa chỉ đúng là giá trị vừa sửa (không bị mất, không bị ghi đè sai trường) | [ ] |
| 14.4 | Thử **Sửa** nhưng để trống ô Họ hoặc Tên → bấm **Ghi** | Báo lỗi validate, không lưu dữ liệu rỗng | [ ] |
| 14.5 | Thử **Sửa** CMND thành CMND của 1 KH khác đã tồn tại → bấm **Ghi** | Báo lỗi trùng CMND, không cho lưu (nếu form cho sửa CMND) — nếu form khóa ô CMND khi Sửa thì bỏ qua bước này | [ ] |
| 14.6 | Bấm **Xóa** trên KH `9999900001` | Hiện hộp xác nhận (hoặc xóa ngay tùy thiết kế) → sau khi xác nhận, báo "Xóa thành công" | [ ] |
| 14.7 | Quay lại danh sách Khách hàng (danh sách đang hoạt động) | KH `9999900001` **không còn xuất hiện** trong danh sách hiển thị mặc định | [ ] |
| 14.8 | Mở SSMS, đối chiếu trên SQL1 (BENTHANH): `SELECT CMND, HO, TEN, TrangThaiXoa FROM KhachHang WHERE CMND='9999900001'` | Bản ghi **vẫn còn**, chỉ đổi `TrangThaiXoa = 1` — KHÔNG bị `DELETE` xóa hẳn | [ ] |
| 14.9 | Quay lại giao diện, tìm cách xem danh sách KH đã xóa (bộ lọc, tab, hoặc nút "Xem đã xóa" nếu có) → bấm **Phục hồi** trên KH `9999900001` | Báo "Phục hồi thành công" | [ ] |
| 14.10 | Quay lại danh sách KH đang hoạt động | KH `9999900001` xuất hiện lại bình thường, `TrangThaiXoa = 0` | [ ] |
| 14.11 (MỞ RỘNG) | Thử **Xóa** một KH **đang có tài khoản còn số dư > 0** | Tùy thiết kế: có thể chặn xóa (báo lỗi "KH còn TK đang hoạt động") hoặc cho xóa mềm bình thường — ghi rõ thực tế hệ thống xử lý thế nào để trả lời vấn đáp | [ ] |

**Điểm dễ bị hỏi:** *"Vì sao không dùng DELETE thật mà dùng UPDATE TrangThaiXoa?"* → Vì khách hàng đã có thể có tài khoản/giao dịch liên quan (khóa ngoại). Xóa cứng sẽ làm vỡ ràng buộc dữ liệu hoặc mất lịch sử giao dịch — vi phạm nguyên tắc toàn vẹn dữ liệu trong ngân hàng. Xóa mềm giữ lại dấu vết cho mục đích kiểm toán (audit).

**Lỗi thường gặp:** Form Sửa load thiếu dữ liệu cũ (các ô trống) khiến người dùng tưởng phải nhập lại từ đầu, dễ làm mất dữ liệu các trường không sửa tới.

---

## TC-15. THÊM / SỬA / XÓA / PHỤC HỒI NHÂN VIÊN (BẮT BUỘC)

**Mục tiêu:** TC-11 (file gốc) tập trung vào **chuyển chi nhánh**. File này test các thao tác CRUD cơ bản trên Nhân viên trước khi chuyển, đúng yêu cầu form phải có đủ Thêm/Sửa/Xóa/Phục hồi/Ghi/Thoát.

**Chuẩn bị:** Login `NV01`/`BENTHANH`.

| # | Bước thực hiện | Kết quả mong đợi | Pass |
|---|---|---|---|
| 15.1 | Vào menu **Nhân viên** → bấm **Thêm** | Hiện form Thêm NV với đủ trường: Họ tên, Chức vụ, Ngày sinh, SĐT... | [ ] |
| 15.2 | Nhập đầy đủ thông tin NV mới (vd Họ=`Trần Thị`, Tên=`Test01`) → bấm **Ghi** | Báo thành công, NV mới xuất hiện trong danh sách, MACN = BENTHANH (đúng chi nhánh đang đăng nhập) | [ ] |
| 15.3 | **Ghi lại Mã NV vừa tạo:** MANV = `_____________` | (dùng cho các bước sau) | [ ] |
| 15.4 | Chọn NV vừa tạo → bấm **Sửa**, đổi SĐT → **Ghi** | Cập nhật thành công, mở lại thấy đúng SĐT mới | [ ] |
| 15.5 | Thử **Sửa** nhưng để trống Họ hoặc Tên | Báo lỗi validate, không lưu | [ ] |
| 15.6 | Bấm **Xóa** trên NV vừa tạo (NV này **chưa từng** thực hiện giao dịch nào) | Báo thành công | [ ] |
| 15.7 | Mở SSMS đối chiếu SQL1: `SELECT MANV, TrangThaiXoa FROM NhanVien WHERE MANV='<MANV ghi ở 15.3>'` | Bản ghi còn, `TrangThaiXoa = 1` (xóa mềm, giống nguyên tắc ở TC-14) | [ ] |
| 15.8 | Quay lại danh sách NV đang hoạt động | NV vừa xóa không còn xuất hiện | [ ] |
| 15.9 | Tìm danh sách NV đã xóa → bấm **Phục hồi** | Báo thành công, NV xuất hiện lại trong danh sách hoạt động | [ ] |
| 15.10 (MỞ RỘNG) | Thử **Xóa** một NV **đã từng thực hiện giao dịch** (vd NV01 — người đã làm các giao dịch ở TC-04 đến TC-08) | Quan sát thực tế: hệ thống có chặn xóa NV đang có lịch sử giao dịch không? Ghi lại để trả lời vấn đáp, vì đây là NV đang là chính người đăng nhập | [ ] |

**Lưu ý phân biệt với TC-11:** TC-11 (file gốc) test việc **chuyển NV sang chi nhánh khác**. TC-15 này chỉ test thao tác CRUD cơ bản (Thêm/Sửa/Xóa/Phục hồi) khi NV **vẫn ở nguyên 1 chi nhánh**, không chuyển đi đâu.

---

## TC-16. QUẢN TRỊ — TẠO LOGIN CHO KHÁCH HÀNG (BẮT BUỘC)

**Mục tiêu:** Theo xác nhận thực tế, hệ thống có **form riêng trong Quản trị** để tạo Login cho Khách hàng (không chỉ tự sinh khi Thêm KH). Test riêng luồng này.

**Chuẩn bị:** Login `admin`/`admin` (nhóm NganHang) **hoặc** `NV01`/`BENTHANH` (nhóm ChiNhanh) — test cả 2 vai trò vì phạm vi quyền khác nhau (xem lại C1/C2 trong `01_DoiChieuDeBai.md`).

| # | Vai trò | Bước thực hiện | Kết quả mong đợi | Pass |
|---|---|---|---|---|
| 16.1 | NganHang | Login `admin` → vào **Quản trị** → tìm form **Tạo Login** | Hiện form cho phép chọn: Khách hàng cần tạo Login, Username (hoặc tự dùng CMND), Mật khẩu/PIN | [ ] |
| 16.2 | NganHang | Chọn 1 KH **chưa có Login** (vd KH vừa Phục hồi ở TC-14.9, hoặc KH bất kỳ chưa được cấp Login) → đặt mật khẩu → **Ghi** | Báo "Tạo Login thành công" | [ ] |
| 16.3 | NganHang | Vào bảng theo dõi trạng thái cấp tài khoản (đã nhắc trong `03_DemoAccounts.md`) | Thấy đúng KH này đã chuyển trạng thái từ "Chưa có Login" → "Đã có Login" | [ ] |
| 16.4 | — | Đăng xuất → thử đăng nhập bằng CMND của KH này + mật khẩu vừa đặt ở bước 16.2 | Đăng nhập thành công, vào đúng giao diện nhóm KhachHang (chỉ thấy Sao kê) | [ ] |
| 16.5 | ChiNhanh [BT] | Đăng xuất → login `NV01`/`BENTHANH` → vào **Quản trị** → form Tạo Login | Chỉ thấy được danh sách KH **thuộc chi nhánh BENTHANH** để chọn tạo Login | [ ] |
| 16.6 | ChiNhanh [BT] | Thử tạo Login cho 1 KH thuộc **TANDINH** (nếu có cách chọn được, ví dụ sửa tay dropdown/URL) | Phải bị chặn — ChiNhanh không được tạo Login cho KH chi nhánh khác | [ ] |
| 16.7 | NganHang/ChiNhanh | Thử tạo Login cho 1 KH **đã có Login từ trước** | Báo lỗi rõ ràng ("KH này đã có Login" hoặc tương đương), không tạo trùng/ghi đè âm thầm | [ ] |
| 16.8 (MỞ RỘNG) | NganHang | Thử để trống mật khẩu khi tạo Login → bấm Ghi | Báo lỗi validate, không tạo Login với mật khẩu rỗng | [ ] |

**Điểm dễ bị hỏi:** *"Login Khách hàng được tạo tự động hay phải thao tác thủ công?"* → Trả lời đúng theo thực tế hệ thống: có **form riêng trong Quản trị** để Ngân hàng/Chi nhánh chủ động tạo Login cho khách hàng, không phải tự động 100% khi Thêm KH. Cần nói rõ điều này để không bị "lố" so với những gì hệ thống thực sự làm.

---

## TC-17. RESET MẬT KHẨU (BẮT BUỘC)

**Mục tiêu:** TC-12.8 (file gốc) mới xác nhận **giao diện có hiển thị** nút Reset MK, nhưng chưa thực sự **bấm thử**. File này test hành động Reset thật.

**Chuẩn bị:** Dùng Login KH đã tạo ở TC-16.2 (đã biết CMND + mật khẩu hiện tại).

| # | Vai trò | Bước thực hiện | Kết quả mong đợi | Pass |
|---|---|---|---|---|
| 17.1 | NganHang | Login `admin` → vào **Quản trị** → bảng trạng thái Login → tìm đúng KH ở TC-16.2 | Thấy nút **Reset MK** ở cột Thao tác | [ ] |
| 17.2 | NganHang | Bấm nút **Reset MK** | Hiện xác nhận (hoặc reset ngay) → báo "Reset thành công", mật khẩu mới = `123456` (theo quy ước trong `03_DemoAccounts.md`) | [ ] |
| 17.3 | — | Đăng xuất → thử đăng nhập bằng CMND của KH này với **mật khẩu cũ** (đặt ở TC-16.2) | Phải **đăng nhập thất bại** — mật khẩu cũ không còn dùng được | [ ] |
| 17.4 | — | Thử đăng nhập lại với mật khẩu mới `123456` | Đăng nhập **thành công** | [ ] |
| 17.5 | NganHang | Bấm icon con mắt để **xem mật khẩu gốc** của 1 NV/KH bất kỳ trong bảng | Hiện đúng mật khẩu hiện tại đang lưu (dạng plain-text hoặc giải mã được) | [ ] |
| 17.6 | ChiNhanh [BT] | Login `NV01` → vào **Quản trị** → bảng trạng thái Login | Theo TC-12.9 (file gốc): KHÔNG thấy cột Mật khẩu, KHÔNG thấy nút Reset MK — chỉ NganHang mới có quyền này | [ ] |
| 17.7 (MỞ RỘNG) | NganHang | Reset mật khẩu cho 1 **Nhân viên** (không phải KH) | Hoạt động tương tự, NV đó đăng nhập lại được bằng mật khẩu mới | [ ] |

**Điểm dễ bị hỏi:** *"Mật khẩu lưu trong DB có được mã hóa không?"* → Trả lời trung thực theo thực tế hệ thống: vì màn hình Quản trị có chức năng "xem mật khẩu gốc" (hiện nguyên văn), nên mật khẩu **không hash một chiều** mà lưu dạng có thể đọc lại được (plain-text hoặc mã hóa 2 chiều/đối xứng). Đây là điểm **nên chủ động thừa nhận** là đơn giản hóa cho mục đích demo đồ án, không phải chuẩn bảo mật production thật (production thật nên dùng hash một chiều như bcrypt, không bao giờ cho xem lại mật khẩu gốc).

---

## CẬP NHẬT BẢNG TỔNG HỢP TIẾN ĐỘ (nối thêm vào bảng trong `98_testcase.md`)

| Testcase | Bắt buộc/Mở rộng | Số bước | Đã Pass | Trạng thái |
|---|---|---|---|---|
| TC-14 Sửa/Xóa Khách hàng | Bắt buộc | 11 | __/11 | |
| TC-15 Thêm/Sửa/Xóa Nhân viên | Bắt buộc | 10 | __/10 | |
| TC-16 Tạo Login Khách hàng ⭐ | Bắt buộc | 8 | __/8 | |
| TC-17 Reset mật khẩu | Bắt buộc | 7 | __/7 | |

---

## GHI CHÚ LỖI PHÁT SINH KHI TEST (tự điền — dùng riêng cho phần bổ sung này)

| Ngày test | Testcase | Mô tả lỗi | Nguyên nhân (nếu đã rõ) | Đã sửa? |
|---|---|---|---|---|
| | | | | [ ] |
| | | | | [ ] |
| | | | | [ ] |

---

*File này BỔ SUNG cho `98_testcase.md` (không thay thế). Dùng chung với `02_KichBanDemo.md` (kịch bản demo) và bộ câu hỏi vấn đáp. Trọng tâm của file này: các nút Sửa/Xóa/Phục hồi mà đề bài yêu cầu đủ 5 nút trên mỗi form, và luồng tạo/reset Login — hai mảng dễ bị giảng viên hỏi xoáy vì sinh viên hay làm thiếu hoặc làm tắt.*
