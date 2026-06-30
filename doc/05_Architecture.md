# Kiến Trúc Phần Mềm & Cấu Trúc Giao Diện

Ứng dụng theo mô hình **MVC** bằng Node.js + Express.js.

| Tầng | Công nghệ | Vai trò |
|------|-----------|---------|
| View | EJS (Embedded JavaScript) | Render HTML động từ dữ liệu server |
| Controller | Express Router (`routes/*.js`) | Điều phối request, gọi DB |
| Model | `db.js` + SQL Server | Pool kết nối, SP, query |
| Database | SQL Server 4 instance | NGUON, BENTHANH, TANDINH, TRACUU |

---

## 1. Luồng MVC Điển Hình

```
[Browser] GET/POST /path
    │
    ▼
[app.js] — Express entry point
    ├─ express-session (đọc/ghi req.session.user)
    ├─ express-ejs-layouts (render layout.ejs bọc ngoài view con)
    ├─ Middleware: requireLogin (kiểm tra req.session.user)
    └─ Middleware: requireRole('NhanVien','ChiNhanh',...) → HTTP 403 nếu sai nhóm
    │
    ▼
[routes/*.js] — Controller
    ├─ getServer(req)  →  req.session.user.SERVER ('BENTHANH'/'TANDINH'/'TRACUU')
    ├─ querySQL(req, serverKey, sql, params)    — raw SELECT/DELETE
    ├─ execSP(req, serverKey, spName, params)   — SP thông thường (tedious)
    ├─ execSPAdmin(serverKey, spName, params)   — SP có Distributed Tran (sqlcmd)
    └─ querySP(req, serverKey, spName, params)  — SP + trả về recordset
    │
    ▼
[db.js] — Pool Manager
    ├─ getPool(req, serverKey)      → pool[serverKey_username]  (per-user SQL Auth)
    └─ getAdminPool(serverKey)      → pool admin HTKN            (DDL: CREATE LOGIN)
    │
    ▼
[SQL Server] — Thực thi
    ├─ Local query / SP
    └─ Linked Server [LINK1] / MSDTC nếu giao dịch liên site
    │
    ▼
[routes/*.js] — Nhận kết quả
    └─ res.render('view/file', { data })  hoặc  res.redirect('/path?success=...')
    │
    ▼
[views/*.ejs] — Render HTML → trả về Browser
```

---

## 2. Cấu Trúc Thư Mục

```
APP_NGANHANG/
├── app.js              — Khởi tạo Express, mount routes, middleware toàn cục
├── db.js               — Connection pools, hàm querySQL/execSP/execSPAdmin
├── setup_db.js         — Deploy SP và schema lúc khởi động (gọi 1 lần)
├── routes/
│   ├── auth.js         — Đăng nhập / Đăng xuất (SQL Auth + sp_Login_App)
│   ├── khachhang.js    — CRUD Khách hàng
│   ├── nhanvien.js     — CRUD Nhân viên + Chuyển chi nhánh
│   ├── taikhoan.js     — Mở/Đóng tài khoản
│   ├── giaodich.js     — Gửi / Rút / Chuyển tiền
│   ├── baocao.js       — Sao kê, Liệt kê
│   └── quantri.js      — Tạo SQL Login, Phân quyền
└── views/
    ├── layout.ejs      — Master page: Header, menu trái (ẩn/hiện theo NHOM)
    ├── login.ejs
    ├── khachhang/      — list.ejs, form.ejs
    ├── nhanvien/       — list.ejs, form.ejs
    ├── taikhoan/       — list.ejs, form.ejs
    ├── giaodich/       — goirut.ejs, chuyentien.ejs
    └── baocao/         — lietke.ejs, saoke.ejs
```

---

## 3. Middleware Phân Quyền (`app.js`)

```javascript
// Middleware — chạy TRƯỚC khi vào route handler
function requireLogin(req, res, next) {
  if (!req.session.user) return res.redirect('/login');
  next();
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.session.user.NHOM))
      return res.status(403).render('error', { message: 'Không có quyền.' });
    next();
  };
}

// Mount — thứ tự middleware quan trọng
app.use('/khachhang', requireLogin, requireRole('NganHang','ChiNhanh'), khRouter);
app.use('/giaodich',  requireLogin, requireRole('NganHang','ChiNhanh'), gdRouter);
app.use('/taikhoan',  requireLogin, requireRole('NganHang','ChiNhanh','KhachHang'), tkRouter);
app.use('/baocao',    requireLogin, requireRole('NganHang','ChiNhanh','KhachHang'), bcRouter);
app.use('/quantri',   requireLogin, requireRole('NganHang'), qtRouter);
```

**3 lớp bảo vệ phối hợp:**
1. **Middleware** (`requireRole`) → chặn HTTP request trái phép → HTTP 403
2. **SQL Role** (GRANT/DENY) → chặn ngay tại DB nếu ai kết nối trực tiếp SSMS
3. **UI** (EJS `if`) → ẩn menu không có quyền → UX tốt hơn

---

## 4. Render Layout — Master Page

File `views/layout.ejs` là khung chung. Mọi trang con được nhúng vào `<%- body %>`:

```html
<!-- layout.ejs lược giản -->
<nav>
  <% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>
    <a href="/khachhang">Khách hàng</a>
    <a href="/giaodich">Giao dịch</a>
  <% } %>
  <% if (user.NHOM === 'NganHang') { %>
    <a href="/quantri">Quản trị</a>
  <% } %>
</nav>
<main><%- body %></main>
```

Menu ẩn/hiện theo `user.NHOM` đọc từ `res.locals.user` (được gán trong `app.js`).

---

## 5. Điểm Khác Biệt Với App Web Thông Thường

| Đặc điểm | App thông thường | App này |
|-----------|-----------------|---------|
| Kết nối DB | 1 pool chung, tài khoản service | Pool riêng theo từng SQL Login người dùng |
| Xác thực | Bảng users trong DB | SQL Server Authentication trực tiếp |
| Distributed Transaction | Không | `BEGIN DISTRIBUTED TRANSACTION` + MSDTC qua sqlcmd |
| Multi-server | Không | 4 instance, chọn đúng server theo chi nhánh user |
| Audit trail | App tự ghi log | SQL Server tự ghi theo LOGIN_NAME() |
