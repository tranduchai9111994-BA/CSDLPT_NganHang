# Kiến Trúc Phần Mềm

Ứng dụng theo mô hình **MVC** trên Node.js + Express.js. Tầng dữ liệu là **4 SQL Server instance** phân tán.

| Tầng | Công nghệ | Vai trò |
|------|-----------|---------|
| View | EJS (Embedded JavaScript) + `express-ejs-layouts` | Render HTML động từ dữ liệu server |
| Controller | Express Router (`APP_NGANHANG/routes/*.js`) | Điều phối request, gọi tầng DB |
| Model | `APP_NGANHANG/db.js` + Stored Procedures | Pool kết nối, thực thi SP/SQL, retry |
| Database | 4 SQL Server instance | NGUON / BENTHANH / TANDINH / TRACUU |

---

## 1. Luồng Request Điển Hình

```
[Browser] GET/POST /path
    │
    ▼
[app.js] — Express entry point (cổng 3001)
    ├─ express-session               (đọc/ghi req.session.user — chứa USERNAME, PASSWORD, NHOM, MACN, SERVER)
    ├─ express-ejs-layouts           (layout.ejs bọc ngoài view con)
    ├─ Middleware: requireLogin      (kiểm tra req.session.user)
    ├─ Middleware: requireRole(...)  (HTTP 403 nếu NHOM không nằm trong danh sách)
    └─ Middleware: requireChiNhanh / requireNganHang  (bảo vệ route ghi)
    │
    ▼
[routes/*.js] — Controller
    ├─ getServer(req)                              → req.session.user.SERVER (BENTHANH/TANDINH/TRACUU)
    ├─ querySQL(req, serverKey, sql, params)       — raw SELECT/INSERT/UPDATE/DELETE qua per-user pool
    ├─ execSP(req, serverKey, spName, params)      — SP thông thường qua per-user pool (tedious driver)
    ├─ querySP(req, serverKey, spName, params)     — SP + trả về recordset
    ├─ execSPAdmin(serverKey, spName, params)      — SP có Distributed Transaction qua sqlcmd (admin login HTKN)
    ├─ queryAdminSQL(serverKey, sqlStr, params)    — raw SQL qua admin pool (dùng khi cần LINK1, có retry)
    └─ getAdminPool(serverKey)                     — pool admin HTKN (dùng cho DDL: CREATE LOGIN, DROP LOGIN)
    │
    ▼
[db.js] — Pool Manager
    ├─ getPool(req, serverKey)      → pools[serverKey_username]  (per-user SQL Auth)
    ├─ getAdminPool(serverKey)      → adminPools[serverKey]      (dùng login HTKN)
    ├─ isPoolDead(pool)             — kiểm tra pool.connected + pool._closed
    ├─ isSessionKilled(err)         — nhận diện lỗi kill state / connection closed / socket error
    └─ Retry logic (1 lần)          — pool chết → xóa cache → tạo mới → thử lại
    │
    ▼
[SQL Server] — Thực thi
    ├─ Local query / SP
    └─ Linked Server [LINK1] / MSDTC nếu SP có BEGIN DISTRIBUTED TRANSACTION
    │
    ▼
[routes/*.js] — Nhận kết quả
    └─ res.render('view/file', { data }) hoặc res.redirect('/path?success=...')
    │
    ▼
[views/*.ejs] — Render HTML → trả về Browser
```

---

## 2. Cấu Trúc Thư Mục

```
D:/CSDLPT_NganHang/
├── APP_NGANHANG/
│   ├── app.js              — Express entry: session, middleware, mount routes
│   ├── db.js               — Connection pools + execSP/execSPAdmin/queryAdminSQL/...
│   ├── setup_db.js         — Deploy SP/schema lúc khởi động (gọi 1 lần khi npm start)
│   ├── routes/
│   │   ├── auth.js         — Đăng nhập / Đăng xuất
│   │   ├── khachhang.js    — CRUD KH + fan-out CREATE LOGIN
│   │   ├── nhanvien.js     — CRUD NV + Chuyển CN + Phục hồi
│   │   ├── taikhoan.js     — Mở / Đóng tài khoản (cross-branch aware)
│   │   ├── giaodich.js     — Gửi / Rút / Chuyển tiền (đều qua execSPAdmin)
│   │   ├── baocao.js       — Sao kê, Liệt kê KH, Liệt kê TK
│   │   └── quantri.js      — Tạo Login, Đổi role, Reset password
│   ├── views/
│   │   ├── layout.ejs      — Master page: header + sidebar (ẩn/hiện theo NHOM)
│   │   ├── login.ejs
│   │   ├── khachhang/ nhanvien/ taikhoan/ giaodich/ baocao/ quantri/
│   └── package.json
├── sql/
│   ├── setup/              — Schema + roles + demo accounts (chạy trên từng instance)
│   ├── stored_procedures/  — Source code SP (nguồn sự thật cho SP)
│   ├── deploy_tracuu.sql   — SP đặc thù chạy trên SQL3 (dùng LINK1/LINK2)
│   └── ...
├── doc/                    — Toàn bộ tài liệu (file này)
└── README.md
```

---

## 3. Middleware Phân Quyền (`app.js`)

```javascript
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

// Route ghi (thêm/sửa/xóa) — chỉ ChiNhanh; chặn NganHang
function requireChiNhanh(req, res, next) {
  if (req.session.user.NHOM !== 'ChiNhanh')
    return res.status(403).render('error', { message: 'Chỉ nhân viên chi nhánh mới có quyền.' });
  next();
}

// Mount routes
app.use('/khachhang', requireLogin, requireRole('NganHang','ChiNhanh'), khRouter);
app.use('/nhanvien',  requireLogin, requireRole('NganHang','ChiNhanh'), nvRouter);
app.use('/taikhoan',  requireLogin, requireRole('NganHang','ChiNhanh','KhachHang'), tkRouter);
app.use('/giaodich',  requireLogin, requireRole('NganHang','ChiNhanh'), gdRouter);
app.use('/baocao',    requireLogin, requireRole('NganHang','ChiNhanh','KhachHang'), bcRouter);
app.use('/quantri',   requireLogin, requireRole('NganHang'), qtRouter);
```

**3 lớp bảo vệ phối hợp:**
1. **Middleware** (`requireRole`) → chặn HTTP request trái phép → HTTP 403.
2. **DB Role** (`GRANT/DENY`) → chặn ngay tại DB nếu ai đó kết nối trực tiếp qua SSMS.
3. **UI** (`<% if user.NHOM ... %>`) → ẩn menu không có quyền → UX tốt hơn.

---

## 4. Sự Khác Biệt Cốt Lõi Của App Này So Với Web Thông Thường

| Đặc điểm | Web thông thường | App này |
|---|---|---|
| Kết nối DB | 1 pool chung dùng tài khoản service | Pool riêng theo **từng SQL Login người dùng** (`db.js:getPool`) |
| Xác thực | Bảng `users` trong DB, hash mật khẩu | **SQL Server Authentication trực tiếp** — Login/Password đúng chuẩn SQL Server |
| Audit trail | App tự log bằng cột `created_by` | SQL Server tự log qua `SUSER_SNAME()` — chính xác đến từng người |
| Distributed Transaction | Hiếm khi dùng | **6 SP có `BEGIN DISTRIBUTED TRAN`** (rẽ nhánh: local khi cùng CN, DTC khi khác CN) qua `sqlcmd` để đi qua MSDTC |
| Multi‑server | Không | 4 instance, `db.js` chọn đúng server theo `session.SERVER` |
| Report tính toán | Backend/frontend tính | **Tính tại SQL Server** bằng Window Function |
| Phân quyền | 1 tầng (backend) | **3 tầng** (DB Role + Middleware + UI) + defense-in-depth ở SP (`SP_DongTaiKhoan`, `SP_SaoKeTaiKhoan` check ownership) |

---

## 5. Render Layout — Master Page

`views/layout.ejs` là khung chung. Mọi trang con nhúng vào `<%- body %>`. Menu ẩn/hiện theo `user.NHOM`:

```html
<nav>
  <% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>
    <a href="/khachhang">Khách hàng</a>
    <a href="/nhanvien">Nhân viên</a>
    <a href="/giaodich">Giao dịch</a>
    <a href="/baocao">Báo cáo</a>
  <% } %>
  <% if (user.NHOM === 'KhachHang') { %>
    <a href="/baocao/saoke">Sao kê</a>
  <% } %>
  <% if (user.NHOM === 'NganHang') { %>
    <a href="/quantri">Quản trị</a>
  <% } %>
</nav>
<main><%- body %></main>
```

Biến `user` được inject vào `res.locals` trong `app.js`:
```javascript
app.use((req, res, next) => { res.locals.user = req.session.user || null; next(); });
```
