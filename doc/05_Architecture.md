# 🏗️ Kiến Trúc Phần Mềm & Cấu Trúc Giao Diện

Ứng dụng được thiết kế theo mô hình **MVC (Model-View-Controller)** đơn giản bằng Node.js:
- **Ngôn ngữ:** JavaScript (Node.js)
- **Framework:** Express.js (để tạo Web Server và quản lý Routing)
- **View Engine:** EJS (Embedded JavaScript) để render HTML động dựa trên dữ liệu từ server.
- **Database Driver:** `mssql` (Microsoft SQL Server driver for Node.js)

## 1. Luồng Hoạt Động Điển Hình (MVC Flow)
1. **Client (Browser)** gửi request (GET/POST) tới một Endpoint (VD: `/khachhang/them`).
2. **Express Router (`routes/*.js`)** tiếp nhận request.
3. **Middleware** kiểm tra xem người dùng đã đăng nhập chưa (`requireLogin`) và có quyền không (`requireRole`).
4. **Controller logic (trong các route)** lấy `serverKey` từ Session của user, gọi hàm truy vấn từ `db.js` (gọi SQL trực tiếp hoặc Stored Procedure).
5. **Database** trả dữ liệu về Server.
6. Server truyền dữ liệu này vào file **EJS (`views/...`)** để render ra mã HTML.
7. HTML được gửi trả về Browser để hiển thị cho người dùng.

## 2. Thư Mục Tĩnh (`public/`) và View (`views/`)
- Mặc dù project hiện tại gộp trực tiếp CSS vào file `layout.ejs` cho tiện demo, nhưng trong mô hình thực tế, file CSS/JS tĩnh sẽ nằm trong `/public/`.
- File `views/layout.ejs` đóng vai trò là Master Page, chứa phần Header, Menu trái. Các trang con sẽ được nhúng vào phần nội dung của layout này bằng biến `<%- body %>` thông qua thư viện `express-ejs-layouts`.
