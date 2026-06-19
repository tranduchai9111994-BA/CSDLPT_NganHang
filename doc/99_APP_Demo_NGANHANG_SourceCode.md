# APP_Demo_NGANHANG.md
> Full code app demo cho đồ án CSDL Phân Tán – Ngân Hàng  
> Ngôn ngữ: **Node.js + Express + EJS**

---

## VÌ SAO CHỌN NODE.JS THAY VÌ C# WINFORMS?

| Tiêu chí | C# WinForms | Node.js + Express |
|---|---|---|
| Cài đặt | Visual Studio ~5GB | Node.js ~50MB |
| Thời gian setup | 30–60 phút | 5 phút |
| Kết nối SQL Server | Cần .NET driver | Package `mssql` (1 lệnh) |
| Chạy demo | Build → exe | `node app.js` xong |
| Giao diện | Windows only | Chạy trên browser, đẹp hơn |
| Sinh viên năm 2 tự sửa | Khó nếu không học .NET | Dễ sửa HTML/JS |
| Phù hợp demo | Ổn | **Tốt hơn** |

**Kết luận: Node.js phù hợp hơn cho demo đồ án này.**  
Chạy lệnh `node app.js` → mở browser `http://localhost:3000` → demo ngay.

---

## CẤU TRÚC PROJECT

```
APP_NGANHANG/
├── package.json          ← khai báo dependencies
├── app.js                ← server chính
├── db.js                 ← kết nối SQL Server
├── routes/
│   ├── auth.js           ← đăng nhập / đăng xuất
│   ├── khachhang.js      ← quản lý khách hàng
│   ├── taikhoan.js       ← mở tài khoản
│   ├── giaodich.js       ← gửi / rút / chuyển tiền
│   └── baocao.js         ← sao kê, liệt kê
└── views/
    ├── layout.ejs         ← layout chung (header/nav)
    ├── login.ejs          ← form đăng nhập
    ├── index.ejs          ← trang chủ sau đăng nhập
    ├── khachhang/
    │   ├── list.ejs       ← danh sách khách hàng
    │   └── form.ejs       ← thêm/sửa khách hàng
    ├── taikhoan/
    │   ├── list.ejs       ← danh sách tài khoản
    │   └── form.ejs       ← mở tài khoản
    ├── giaodich/
    │   ├── goirut.ejs     ← gửi/rút tiền
    │   └── chuyentien.ejs ← chuyển tiền
    └── baocao/
        ├── saoke.ejs      ← sao kê giao dịch
        └── lietke.ejs     ← liệt kê KH/TK
```

---

## BƯỚC 1: CÀI ĐẶT

```bash
# 1. Cài Node.js từ https://nodejs.org (LTS version)
# Kiểm tra:
node --version   # v18.x hoặc cao hơn
npm --version

# 2. Tạo thư mục project
mkdir APP_NGANHANG
cd APP_NGANHANG

# 3. Khởi tạo project
npm init -y

# 4. Cài dependencies
npm install express ejs express-session mssql

# 5. Tạo cấu trúc thư mục
mkdir routes views views/khachhang views/taikhoan views/giaodich views/baocao
```

---

## FILE: package.json

```json
{
  "name": "app-nganhang",
  "version": "1.0.0",
  "description": "Demo CSDL Phan Tan - Ngan Hang",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ejs": "^3.1.9",
    "express-session": "^1.17.3",
    "mssql": "^10.0.1"
  }
}
```

---

## FILE: db.js – Kết nối SQL Server

```javascript
// db.js
const sql = require('mssql');

// Cấu hình mặc định - kết nối NGANHANG1 (BENTHANH)
// Thay 'TEN_MAY_TINH' bằng tên máy tính của bạn
const configs = {
  NGUON: {
    server: 'ES-HAITD16',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },

  BENTHANH: {
    server: 'ES-HAITD16\\SQL1',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },

  TANDINH: {
    server: 'ES-HAITD16\\SQL2',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },

  TRACUU: {
    server: 'ES-HAITD16\\SQL3',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  }
};

// Pool connections lưu theo tên server
const pools = {};

// Lấy pool kết nối theo tên server
async function getPool(serverKey) {
  if (!configs[serverKey]) {
    throw new Error(`Không tìm thấy cấu hình server: ${serverKey}`);
  }
  if (!pools[serverKey]) {
    pools[serverKey] = await new sql.ConnectionPool(configs[serverKey]).connect();
    console.log(`[DB] Đã kết nối: ${serverKey}`);
  }
  return pools[serverKey];
}

// Gọi Stored Procedure – không trả về dữ liệu
async function execSP(serverKey, spName, params = {}) {
  const pool = await getPool(serverKey);
  const request = pool.request();
  for (const [key, val] of Object.entries(params)) {
    request.input(key, val);
  }
  return await request.execute(spName);
}

// Gọi SP – trả về recordset (mảng dòng dữ liệu)
async function querySP(serverKey, spName, params = {}) {
  const result = await execSP(serverKey, spName, params);
  return result.recordset || [];
}

// Chạy câu SQL trực tiếp (dùng cho test nhanh)
async function querySQL(serverKey, sqlStr, params = {}) {
  const pool = await getPool(serverKey);
  const request = pool.request();
  for (const [key, val] of Object.entries(params)) {
    request.input(key, val);
  }
  const result = await request.query(sqlStr);
  return result.recordset || [];
}

module.exports = { getPool, execSP, querySP, querySQL, sql, configs };
```

---

## FILE: app.js – Server chính

```javascript
// app.js
const express = require('express');
const session = require('express-session');
const path = require('path');

const app = express();
const PORT = 3000;

// ==== CẤU HÌNH VIEW ENGINE ====
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// ==== MIDDLEWARE ====
app.use(express.urlencoded({ extended: true }));  // parse form POST
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Session – lưu thông tin đăng nhập
app.use(session({
  secret: 'nganhang_secret_key_2024',
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 8 * 60 * 60 * 1000 }  // 8 giờ
}));

// ==== MIDDLEWARE KIỂM TRA ĐĂNG NHẬP ====
// Truyền thông tin user vào tất cả view
app.use((req, res, next) => {
  res.locals.user = req.session.user || null;
  next();
});

// Middleware bảo vệ route – chưa login thì redirect về /login
function requireLogin(req, res, next) {
  if (!req.session.user) {
    return res.redirect('/login');
  }
  next();
}

// Middleware kiểm tra nhóm quyền
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.session.user) return res.redirect('/login');
    if (!roles.includes(req.session.user.NHOM)) {
      return res.status(403).render('error', {
        message: 'Bạn không có quyền truy cập chức năng này.',
        user: req.session.user
      });
    }
    next();
  };
}

// ==== ROUTES ====
const authRoutes      = require('./routes/auth');
const khachHangRoutes = require('./routes/khachhang');
const taiKhoanRoutes  = require('./routes/taikhoan');
const giaoDichRoutes  = require('./routes/giaodich');
const baoCaoRoutes    = require('./routes/baocao');

app.use('/', authRoutes);
app.use('/khachhang', requireLogin, khachHangRoutes);
app.use('/taikhoan',  requireLogin, taiKhoanRoutes);
app.use('/giaodich',  requireLogin, giaoDichRoutes);
app.use('/baocao',    requireLogin, baoCaoRoutes);

// Trang chủ
app.get('/', requireLogin, (req, res) => {
  res.render('index');
});

// Xử lý lỗi 404
app.use((req, res) => {
  res.status(404).render('error', { message: 'Trang không tồn tại.' });
});

// ==== KHỞI ĐỘNG SERVER ====
app.listen(PORT, () => {
  console.log(`\n========================================`);
  console.log(`  APP NGÂN HÀNG đang chạy tại:`);
  console.log(`  http://localhost:${PORT}`);
  console.log(`========================================\n`);
});

module.exports = { requireLogin, requireRole };
```

---

## FILE: routes/auth.js – Đăng nhập / Đăng xuất

```javascript
// routes/auth.js
const express = require('express');
const router = express.Router();
const { querySQL } = require('../db');

// GET /login
router.get('/login', (req, res) => {
  if (req.session.user) return res.redirect('/');
  res.render('login', { error: null });
});

// POST /login – xử lý đăng nhập
router.post('/login', async (req, res) => {
  const { username, password, chinhanh } = req.body;

  // Xác định server để kết nối dựa vào chi nhánh chọn
  // chinhanh = 'BENTHANH' | 'TANDINH' | 'TRACUU'
  const serverKey = chinhanh || 'BENTHANH';

  try {
    // Thử kết nối với login/password người dùng nhập
    // Cách đơn giản: dùng sa để query, rồi kiểm tra user trong DB
    // (Trong thực tế nên dùng SQL Server Login thật)

    // Tìm nhóm quyền của user trong database
    const rows = await querySQL(serverKey, `
      SELECT 
        dp.name AS UserName,
        rp.name AS RoleName
      FROM sys.database_role_members rm
      JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
      JOIN sys.database_principals rp ON rm.role_principal_id = rp.principal_id
      WHERE dp.name = @uname
        AND rp.name IN ('NganHang','ChiNhanh','KhachHang')
    `, { uname: username });

    if (rows.length === 0) {
      // Thử kiểm tra bằng cách khác: tìm trong NhanVien hoặc KhachHang
      // Đơn giản hóa: dùng bảng NhanVien làm user registry
      const nvRows = await querySQL(serverKey, `
        SELECT MANV, HO, TEN, MACN
        FROM NhanVien
        WHERE RTRIM(MANV) = @uname AND TrangThaiXoa = 0
      `, { uname: username });

      if (nvRows.length === 0) {
        return res.render('login', { error: 'Tên đăng nhập không tồn tại.' });
      }

      const nv = nvRows[0];
      // Gán nhóm mặc định là ChiNhanh nếu không tìm thấy role
      req.session.user = {
        USERNAME: username,
        MANV: nv.MANV.trim(),
        HOTEN: `${nv.HO.trim()} ${nv.TEN.trim()}`,
        NHOM: 'ChiNhanh',
        MACN: nv.MACN ? nv.MACN.trim() : '',
        SERVER: serverKey
      };
      return res.redirect('/');
    }

    const roleName = rows[0].RoleName;

    // Lấy thông tin NV (nếu là ChiNhanh hoặc NganHang)
    let hoten = username;
    let manv = '';
    let macn = '';

    if (roleName !== 'KhachHang') {
      const nvRows = await querySQL(serverKey, `
        SELECT MANV, HO, TEN, MACN FROM NhanVien
        WHERE RTRIM(MANV) = @uname AND TrangThaiXoa = 0
      `, { uname: username });
      if (nvRows.length > 0) {
        const nv = nvRows[0];
        hoten = `${nv.HO.trim()} ${nv.TEN.trim()}`;
        manv  = nv.MANV.trim();
        macn  = nv.MACN ? nv.MACN.trim() : '';
      }
    } else {
      // KhachHang: tìm trong bảng KhachHang
      const khRows = await querySQL(serverKey, `
        SELECT CMND, HO, TEN, MACN FROM KhachHang
        WHERE RTRIM(CMND) = @uname
      `, { uname: username });
      if (khRows.length > 0) {
        const kh = khRows[0];
        hoten = `${kh.HO.trim()} ${kh.TEN.trim()}`;
        manv  = kh.CMND.trim();
        macn  = kh.MACN ? kh.MACN.trim() : '';
      }
    }

    req.session.user = {
      USERNAME: username,
      MANV: manv,
      HOTEN: hoten,
      NHOM: roleName,
      MACN: macn,
      SERVER: serverKey
    };

    res.redirect('/');

  } catch (err) {
    console.error('[LOGIN ERROR]', err.message);
    res.render('login', { error: 'Kết nối thất bại: ' + err.message });
  }
});

// GET /logout
router.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

module.exports = router;
```

---

## FILE: routes/khachhang.js – Quản lý khách hàng

```javascript
// routes/khachhang.js
const express = require('express');
const router = express.Router();
const { querySQL, execSP } = require('../db');

// Lấy serverKey từ session
function getServer(req) {
  return req.session.user.SERVER || 'BENTHANH';
}

// GET /khachhang – Danh sách khách hàng
router.get('/', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    let rows;
    if (user.NHOM === 'NganHang') {
      // NganHang xem tất cả qua TRACUU hoặc UNION
      rows = await querySQL('TRACUU', `
        SELECT RTRIM(CMND) AS CMND,
               RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
               RTRIM(MACN) AS MACN, SODT, DIACHI
        FROM KhachHang
        ORDER BY MACN, HO, TEN
      `);
    } else {
      // ChiNhanh chỉ xem của chi nhánh mình
      rows = await querySQL(server, `
        SELECT RTRIM(CMND) AS CMND,
               RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
               RTRIM(MACN) AS MACN, SODT, DIACHI
        FROM KhachHang
        WHERE RTRIM(MACN) = @macn
        ORDER BY HO, TEN
      `, { macn: user.MACN });
    }
    res.render('khachhang/list', { rows, error: null, success: null });
  } catch (err) {
    res.render('khachhang/list', { rows: [], error: err.message, success: null });
  }
});

// GET /khachhang/them – Form thêm mới
router.get('/them', (req, res) => {
  const user = req.session.user;
  if (!['NganHang', 'ChiNhanh'].includes(user.NHOM)) {
    return res.status(403).render('error', { message: 'Không có quyền.' });
  }
  res.render('khachhang/form', {
    kh: null, action: 'them', error: null,
    macn: user.MACN
  });
});

// POST /khachhang/them – Thực hiện thêm
router.post('/them', async (req, res) => {
  const user   = req.session.user;
  const server = getServer(req);
  const { CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT } = req.body;
  const MACN = user.MACN || req.body.MACN;

  try {
    // Gọi SP thêm KH (SP đã viết trong SQL Server)
    await execSP(server, 'sp_ThemKhachHang', {
      CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT, MACN
    });
    res.redirect('/khachhang?success=Thêm khách hàng thành công');
  } catch (err) {
    res.render('khachhang/form', {
      kh: req.body, action: 'them',
      error: err.message, macn: MACN
    });
  }
});

// GET /khachhang/sua/:cmnd – Form sửa
router.get('/sua/:cmnd', async (req, res) => {
  const server = getServer(req);
  const { cmnd } = req.params;
  try {
    const rows = await querySQL(server, `
      SELECT * FROM KhachHang WHERE RTRIM(CMND) = @cmnd
    `, { cmnd });
    if (rows.length === 0) return res.redirect('/khachhang');
    const kh = rows[0];
    // Format date cho input type=date
    kh.NGAYCAP = kh.NGAYCAP ? kh.NGAYCAP.toISOString().split('T')[0] : '';
    res.render('khachhang/form', {
      kh, action: 'sua', error: null,
      macn: req.session.user.MACN
    });
  } catch (err) {
    res.redirect('/khachhang');
  }
});

// POST /khachhang/sua – Thực hiện sửa
router.post('/sua', async (req, res) => {
  const server = getServer(req);
  const { CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT } = req.body;
  try {
    await querySQL(server, `
      UPDATE KhachHang
      SET HO=@ho, TEN=@ten, DIACHI=@diachi, PHAI=@phai, NGAYCAP=@ngaycap, SODT=@sodt
      WHERE RTRIM(CMND) = @cmnd
    `, { ho: HO, ten: TEN, diachi: DIACHI, phai: PHAI, ngaycap: NGAYCAP, sodt: SODT, cmnd: CMND });
    res.redirect('/khachhang?success=Cập nhật thành công');
  } catch (err) {
    res.render('khachhang/form', {
      kh: req.body, action: 'sua',
      error: err.message, macn: req.session.user.MACN
    });
  }
});

// POST /khachhang/xoa – Xóa mềm (đặt flag nếu có, hoặc xóa thật nếu chưa có GD)
router.post('/xoa', async (req, res) => {
  const server = getServer(req);
  const { CMND } = req.body;
  try {
    // Kiểm tra KH có TK không
    const tkRows = await querySQL(server, `
      SELECT COUNT(*) AS cnt FROM TaiKhoan WHERE RTRIM(CMND) = @cmnd
    `, { cmnd: CMND });
    if (tkRows[0].cnt > 0) {
      return res.redirect('/khachhang?error=Không thể xóa: KH đang có tài khoản');
    }
    await querySQL(server, `DELETE FROM KhachHang WHERE RTRIM(CMND) = @cmnd`, { cmnd: CMND });
    res.redirect('/khachhang?success=Đã xóa khách hàng');
  } catch (err) {
    res.redirect('/khachhang?error=' + err.message);
  }
});

module.exports = router;
```

---

## FILE: routes/taikhoan.js – Mở tài khoản

```javascript
// routes/taikhoan.js
const express = require('express');
const router  = express.Router();
const { querySQL, execSP } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// Sinh số TK tự động: TK + 7 chữ số
async function sinhSOTK(serverKey) {
  const rows = await querySQL(serverKey, `
    SELECT TOP 1 SOTK FROM TaiKhoan ORDER BY SOTK DESC
  `);
  if (rows.length === 0) return 'TK0000001';
  const last = rows[0].SOTK.trim();
  const num  = parseInt(last.replace('TK', '')) + 1;
  return 'TK' + String(num).padStart(7, '0');
}

// GET /taikhoan – Danh sách tài khoản
router.get('/', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    let sql;
    let params = {};
    if (user.NHOM === 'NganHang') {
      sql = `
        SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
               RTRIM(kh.HO)+' '+RTRIM(kh.TEN) AS HoTen,
               tk.SODU, RTRIM(tk.MACN) AS MACN,
               CONVERT(varchar,tk.NGAYMOTK,103) AS NGAYMOTK
        FROM TaiKhoan tk
        LEFT JOIN KhachHang kh ON RTRIM(tk.CMND)=RTRIM(kh.CMND)
        ORDER BY tk.NGAYMOTK DESC
      `;
    } else if (user.NHOM === 'ChiNhanh') {
      sql = `
        SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
               RTRIM(kh.HO)+' '+RTRIM(kh.TEN) AS HoTen,
               tk.SODU, RTRIM(tk.MACN) AS MACN,
               CONVERT(varchar,tk.NGAYMOTK,103) AS NGAYMOTK
        FROM TaiKhoan tk
        LEFT JOIN KhachHang kh ON RTRIM(tk.CMND)=RTRIM(kh.CMND)
        WHERE RTRIM(tk.MACN) = @macn
        ORDER BY tk.NGAYMOTK DESC
      `;
      params = { macn: user.MACN };
    } else {
      // KhachHang chỉ xem TK của mình
      sql = `
        SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
               tk.SODU, RTRIM(tk.MACN) AS MACN,
               CONVERT(varchar,tk.NGAYMOTK,103) AS NGAYMOTK
        FROM TaiKhoan tk
        WHERE RTRIM(tk.CMND) = @cmnd
        ORDER BY tk.NGAYMOTK DESC
      `;
      params = { cmnd: user.MANV };
    }
    const rows = await querySQL(server, sql, params);
    res.render('taikhoan/list', { rows, error: req.query.error || null, success: req.query.success || null });
  } catch (err) {
    res.render('taikhoan/list', { rows: [], error: err.message, success: null });
  }
});

// GET /taikhoan/mo – Form mở tài khoản
router.get('/mo', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  if (!['NganHang', 'ChiNhanh'].includes(user.NHOM)) {
    return res.status(403).render('error', { message: 'Không có quyền.' });
  }
  try {
    const sotk = await sinhSOTK(server);
    // Lấy danh sách KH để chọn
    const khRows = await querySQL(server, `
      SELECT RTRIM(CMND) AS CMND, RTRIM(HO)+' '+RTRIM(TEN) AS HoTen
      FROM KhachHang WHERE RTRIM(MACN)=@macn ORDER BY HO,TEN
    `, { macn: user.MACN });
    res.render('taikhoan/form', {
      sotk, khRows, macn: user.MACN, error: null
    });
  } catch (err) {
    res.render('taikhoan/form', { sotk: '', khRows: [], macn: user.MACN, error: err.message });
  }
});

// POST /taikhoan/mo – Thực hiện mở TK
router.post('/mo', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, CMND, SODU, MACN } = req.body;
  try {
    await execSP(server, 'sp_MoTaiKhoan', {
      SOTK, CMND, SODU: parseFloat(SODU) || 0, MACN, MANV: user.MANV
    });
    res.redirect('/taikhoan?success=Mở tài khoản thành công');
  } catch (err) {
    const khRows = await querySQL(server, `
      SELECT RTRIM(CMND) AS CMND, RTRIM(HO)+' '+RTRIM(TEN) AS HoTen
      FROM KhachHang WHERE RTRIM(MACN)=@macn ORDER BY HO,TEN
    `, { macn: user.MACN });
    res.render('taikhoan/form', { sotk: SOTK, khRows, macn: MACN, error: err.message });
  }
});

module.exports = router;
```

---

## FILE: routes/giaodich.js – Gửi / Rút / Chuyển tiền

```javascript
// routes/giaodich.js
const express = require('express');
const router  = express.Router();
const { querySQL, execSP } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// ============================================================
// GỬI / RÚT TIỀN
// ============================================================

// GET /giaodich/goirut
router.get('/goirut', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    // Lấy danh sách TK thuộc chi nhánh (để chọn)
    const tkRows = await querySQL(server, `
      SELECT RTRIM(SOTK) AS SOTK, SODU, RTRIM(CMND) AS CMND
      FROM TaiKhoan WHERE RTRIM(MACN)=@macn
    `, { macn: user.MACN });
    res.render('giaodich/goirut', {
      tkRows, error: req.query.error || null, success: req.query.success || null
    });
  } catch (err) {
    res.render('giaodich/goirut', { tkRows: [], error: err.message, success: null });
  }
});

// POST /giaodich/guitien
router.post('/guitien', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, SOTIEN } = req.body;
  try {
    await execSP(server, 'sp_GuiTien', {
      SOTK: SOTK.trim(),
      SOTIEN: parseFloat(SOTIEN),
      MANV: user.MANV
    });
    res.redirect('/giaodich/goirut?success=Gửi tiền thành công! Số tiền: ' + Number(SOTIEN).toLocaleString('vi-VN') + ' VNĐ');
  } catch (err) {
    res.redirect('/giaodich/goirut?error=' + encodeURIComponent(err.message));
  }
});

// POST /giaodich/ruttien
router.post('/ruttien', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, SOTIEN } = req.body;
  try {
    await execSP(server, 'sp_RutTien', {
      SOTK: SOTK.trim(),
      SOTIEN: parseFloat(SOTIEN),
      MANV: user.MANV
    });
    res.redirect('/giaodich/goirut?success=Rút tiền thành công! Số tiền: ' + Number(SOTIEN).toLocaleString('vi-VN') + ' VNĐ');
  } catch (err) {
    res.redirect('/giaodich/goirut?error=' + encodeURIComponent(err.message));
  }
});

// ============================================================
// CHUYỂN TIỀN
// ============================================================

// GET /giaodich/chuyentien
router.get('/chuyentien', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    const tkRows = await querySQL(server, `
      SELECT RTRIM(SOTK) AS SOTK, SODU FROM TaiKhoan WHERE RTRIM(MACN)=@macn
    `, { macn: user.MACN });
    res.render('giaodich/chuyentien', {
      tkRows, error: req.query.error || null, success: req.query.success || null
    });
  } catch (err) {
    res.render('giaodich/chuyentien', { tkRows: [], error: err.message, success: null });
  }
});

// POST /giaodich/chuyentien
router.post('/chuyentien', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK_CHUYEN, SOTK_NHAN, SOTIEN } = req.body;
  try {
    await execSP(server, 'sp_ChuyenTien', {
      SOTK_CHUYEN: SOTK_CHUYEN.trim(),
      SOTK_NHAN: SOTK_NHAN.trim(),
      SOTIEN: parseFloat(SOTIEN),
      MANV: user.MANV
    });
    res.redirect('/giaodich/chuyentien?success=Chuyển tiền thành công! '
      + SOTK_CHUYEN + ' → ' + SOTK_NHAN + ': '
      + Number(SOTIEN).toLocaleString('vi-VN') + ' VNĐ');
  } catch (err) {
    res.redirect('/giaodich/chuyentien?error=' + encodeURIComponent(err.message));
  }
});

// API lấy số dư TK (dùng cho AJAX kiểm tra trước khi chuyển)
router.get('/api/sodu/:sotk', async (req, res) => {
  const server = getServer(req);
  const { sotk } = req.params;
  try {
    const rows = await querySQL(server, `
      SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK)=@sotk
    `, { sotk });
    if (rows.length === 0) return res.json({ error: 'Tài khoản không tồn tại' });
    res.json({ SODU: rows[0].SODU });
  } catch (err) {
    res.json({ error: err.message });
  }
});

module.exports = router;
```

---

## FILE: routes/baocao.js – Sao kê và Liệt kê

```javascript
// routes/baocao.js
const express = require('express');
const router  = express.Router();
const { querySQL } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// ============================================================
// SAO KÊ GIAO DỊCH
// ============================================================

// GET /baocao/saoke
router.get('/saoke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    // KhachHang: chỉ thấy TK của mình
    let tkRows;
    if (user.NHOM === 'KhachHang') {
      tkRows = await querySQL(server, `
        SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd
      `, { cmnd: user.MANV });
    } else {
      tkRows = await querySQL(server, `
        SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK
      `);
    }
    res.render('baocao/saoke', { tkRows, rows: null, sodu_dau: 0, sodu_cuoi: 0, error: null, query: {} });
  } catch (err) {
    res.render('baocao/saoke', { tkRows: [], rows: null, sodu_dau: 0, sodu_cuoi: 0, error: err.message, query: {} });
  }
});

// POST /baocao/saoke – Thực hiện sao kê
router.post('/saoke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, TUNGAY, DENNGAY } = req.body;

  // Kiểm tra KhachHang chỉ xem TK của mình
  if (user.NHOM === 'KhachHang') {
    const own = await querySQL(server, `
      SELECT COUNT(*) AS cnt FROM TaiKhoan
      WHERE RTRIM(SOTK)=@sotk AND RTRIM(CMND)=@cmnd
    `, { sotk: SOTK, cmnd: user.MANV });
    if (own[0].cnt === 0) {
      return res.redirect('/baocao/saoke?error=Bạn không có quyền xem tài khoản này.');
    }
  }

  try {
    // Lấy số dư hiện tại
    const tkInfo = await querySQL(server, `
      SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK)=@sotk
    `, { sotk: SOTK });
    const sodu_hientai = tkInfo.length > 0 ? tkInfo[0].SODU : 0;

    // Lấy tất cả GD trong khoảng thời gian
    // GD_GOIRUT
    const gdGoiRut = await querySQL(server, `
      SELECT NGAYGD,
             CASE LOAIGD WHEN 'GT' THEN N'Gửi tiền' ELSE N'Rút tiền' END AS LoaiGD,
             CASE LOAIGD WHEN 'GT' THEN SOTIEN ELSE 0 END AS TienVao,
             CASE LOAIGD WHEN 'RT' THEN SOTIEN ELSE 0 END AS TienRa
      FROM GD_GOIRUT
      WHERE RTRIM(SOTK)=@sotk
        AND NGAYGD BETWEEN @tungay AND DATEADD(day,1,@denngay)
      ORDER BY NGAYGD
    `, { sotk: SOTK, tungay: TUNGAY, denngay: DENNGAY });

    // GD_CHUYENTIEN liên quan
    const gdChuyen = await querySQL(server, `
      SELECT NGAYGD,
             CASE WHEN RTRIM(SOTK_CHUYEN)=@sotk THEN N'Chuyển đi' ELSE N'Chuyển đến' END AS LoaiGD,
             CASE WHEN RTRIM(SOTK_NHAN)=@sotk THEN SOTIEN ELSE 0 END AS TienVao,
             CASE WHEN RTRIM(SOTK_CHUYEN)=@sotk THEN SOTIEN ELSE 0 END AS TienRa
      FROM GD_CHUYENTIEN
      WHERE (RTRIM(SOTK_CHUYEN)=@sotk OR RTRIM(SOTK_NHAN)=@sotk)
        AND NGAYGD BETWEEN @tungay AND DATEADD(day,1,@denngay)
      ORDER BY NGAYGD
    `, { sotk: SOTK, tungay: TUNGAY, denngay: DENNGAY });

    // Gộp và sắp xếp theo ngày
    const allGD = [...gdGoiRut, ...gdChuyen].sort(
      (a, b) => new Date(a.NGAYGD) - new Date(b.NGAYGD)
    );

    // Tính số dư tích lũy
    // Tổng GD từ @TUNGAY đến @DENNGAY
    const tongVao = allGD.reduce((s, r) => s + (r.TienVao || 0), 0);
    const tongRa  = allGD.reduce((s, r) => s + (r.TienRa || 0), 0);

    // Số dư đầu kỳ = số dư hiện tại - tất cả GD trong kỳ
    const sodu_dau  = sodu_hientai - tongVao + tongRa;
    const sodu_cuoi = sodu_hientai;

    // Tính số dư sau từng GD
    let runBalance = sodu_dau;
    const rows = allGD.map(gd => {
      runBalance += (gd.TienVao || 0) - (gd.TienRa || 0);
      return {
        ...gd,
        NGAYGD: new Date(gd.NGAYGD).toLocaleDateString('vi-VN'),
        TienVao: gd.TienVao || 0,
        TienRa: gd.TienRa || 0,
        SoDuSau: runBalance
      };
    });

    // Lấy danh sách TK để re-render combo
    const tkRows = user.NHOM === 'KhachHang'
      ? await querySQL(server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd`, { cmnd: user.MANV })
      : await querySQL(server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK`);

    res.render('baocao/saoke', {
      tkRows, rows, sodu_dau, sodu_cuoi, error: null,
      query: { SOTK, TUNGAY, DENNGAY }
    });
  } catch (err) {
    res.render('baocao/saoke', {
      tkRows: [], rows: null, sodu_dau: 0, sodu_cuoi: 0,
      error: err.message, query: { SOTK, TUNGAY, DENNGAY }
    });
  }
});

// ============================================================
// LIỆT KÊ KHÁCH HÀNG VÀ TÀI KHOẢN
// ============================================================

// GET /baocao/lietke
router.get('/lietke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { loai, macn, tungay, denngay } = req.query;

  try {
    let rows = [];
    let title = '';

    if (loai === 'kh') {
      title = 'Danh sách khách hàng';
      if (user.NHOM === 'NganHang' && !macn) {
        // Tất cả chi nhánh
        rows = await querySQL('TRACUU', `
          SELECT RTRIM(CMND) AS CMND,
                 RTRIM(HO)+' '+RTRIM(TEN) AS HoTen,
                 RTRIM(MACN) AS MACN, SODT
          FROM KhachHang ORDER BY MACN, HO, TEN
        `);
      } else {
        const filterMACN = macn || user.MACN;
        rows = await querySQL(server, `
          SELECT RTRIM(CMND) AS CMND,
                 RTRIM(HO)+' '+RTRIM(TEN) AS HoTen,
                 RTRIM(MACN) AS MACN, SODT
          FROM KhachHang WHERE RTRIM(MACN)=@macn ORDER BY HO, TEN
        `, { macn: filterMACN });
      }
    } else if (loai === 'tk') {
      title = 'Danh sách tài khoản mở';
      const sqlParams = {};
      let sqlStr = `
        SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
               RTRIM(kh.HO)+' '+RTRIM(kh.TEN) AS HoTen,
               tk.SODU, RTRIM(tk.MACN) AS MACN,
               CONVERT(varchar,tk.NGAYMOTK,103) AS NGAYMOTK
        FROM TaiKhoan tk
        LEFT JOIN KhachHang kh ON RTRIM(tk.CMND)=RTRIM(kh.CMND)
        WHERE 1=1
      `;
      if (user.NHOM === 'ChiNhanh') {
        sqlStr += ' AND RTRIM(tk.MACN)=@macn';
        sqlParams.macn = user.MACN;
      }
      if (tungay) { sqlStr += ' AND tk.NGAYMOTK >= @tungay'; sqlParams.tungay = tungay; }
      if (denngay) { sqlStr += ' AND tk.NGAYMOTK <= DATEADD(day,1,@denngay)'; sqlParams.denngay = denngay; }
      sqlStr += ' ORDER BY tk.NGAYMOTK DESC';
      rows = await querySQL(server, sqlStr, sqlParams);
    }

    res.render('baocao/lietke', {
      rows, title, loai: loai || '', error: null,
      query: { macn, tungay, denngay }
    });
  } catch (err) {
    res.render('baocao/lietke', {
      rows: [], title: '', loai: loai || '', error: err.message,
      query: {}
    });
  }
});

module.exports = router;
```

---

## VIEWS – Giao diện EJS

### FILE: views/layout.ejs – Layout chung

```html
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>APP NGÂN HÀNG – CSDL Phân Tán</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: Arial, sans-serif; }
    body { background: #f0f2f5; }

    /* NAV */
    nav { background: #1a3c6e; color: white; padding: 12px 20px;
          display: flex; align-items: center; justify-content: space-between; }
    nav .brand { font-size: 18px; font-weight: bold; }
    nav .user-info { font-size: 13px; }
    nav .user-info span { background: #2e5da8; padding: 3px 8px; border-radius: 4px; margin-left: 6px; }
    nav a { color: #cce0ff; text-decoration: none; }
    nav a:hover { color: white; }

    /* SIDEBAR */
    .layout { display: flex; min-height: calc(100vh - 50px); }
    .sidebar { width: 200px; background: #1e2d45; padding: 15px 0; flex-shrink: 0; }
    .sidebar a { display: block; color: #b0c4de; padding: 10px 18px; text-decoration: none; font-size: 14px; }
    .sidebar a:hover { background: #2e4a6e; color: white; }
    .sidebar .section-title { color: #6a8faf; font-size: 11px; padding: 12px 18px 4px; text-transform: uppercase; }

    /* MAIN CONTENT */
    .main { flex: 1; padding: 20px; overflow-x: auto; }
    h1 { font-size: 20px; color: #1a3c6e; margin-bottom: 16px; border-bottom: 2px solid #1a3c6e; padding-bottom: 6px; }

    /* ALERTS */
    .alert { padding: 10px 14px; border-radius: 4px; margin-bottom: 14px; font-size: 14px; }
    .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
    .alert-error   { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }

    /* TABLE */
    table { width: 100%; border-collapse: collapse; background: white;
            box-shadow: 0 1px 4px rgba(0,0,0,0.1); border-radius: 6px; overflow: hidden; }
    th { background: #1a3c6e; color: white; padding: 10px 12px; font-size: 13px; text-align: left; }
    td { padding: 9px 12px; font-size: 13px; border-bottom: 1px solid #e9ecef; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: #f8f9fa; }

    /* FORM */
    .form-card { background: white; padding: 20px; border-radius: 6px;
                 box-shadow: 0 1px 4px rgba(0,0,0,0.1); max-width: 600px; }
    .form-group { margin-bottom: 14px; }
    label { display: block; font-size: 13px; font-weight: bold; color: #333; margin-bottom: 4px; }
    input, select { width: 100%; padding: 8px 10px; border: 1px solid #ced4da;
                    border-radius: 4px; font-size: 13px; }
    input:focus, select:focus { outline: none; border-color: #1a3c6e; }

    /* BUTTONS */
    .btn { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer;
           font-size: 13px; font-weight: bold; text-decoration: none; display: inline-block; }
    .btn-primary  { background: #1a3c6e; color: white; }
    .btn-success  { background: #28a745; color: white; }
    .btn-warning  { background: #ffc107; color: #333; }
    .btn-danger   { background: #dc3545; color: white; }
    .btn-secondary{ background: #6c757d; color: white; }
    .btn:hover { opacity: 0.88; }
    .btn-sm { padding: 4px 10px; font-size: 12px; }

    /* MONEY */
    .money { text-align: right; font-weight: bold; }
    .money-positive { color: #28a745; }
    .money-negative { color: #dc3545; }

    /* BADGE */
    .badge { padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: bold; }
    .badge-bn { background: #d4edda; color: #155724; }
    .badge-td { background: #cce5ff; color: #004085; }
    .badge-tc { background: #fff3cd; color: #856404; }
  </style>
</head>
<body>

<% if (user) { %>
<nav>
  <div class="brand">🏦 APP NGÂN HÀNG</div>
  <div class="user-info">
    <span>👤 <%= user.HOTEN %></span>
    <span>🔑 <%= user.NHOM %></span>
    <% if (user.MACN) { %><span>🏢 <%= user.MACN %></span><% } %>
    <span>🖥 <%= user.SERVER %></span>
    &nbsp;&nbsp;<a href="/logout">Đăng xuất</a>
  </div>
</nav>
<div class="layout">
  <div class="sidebar">
    <% if (user.NHOM === 'ChiNhanh' || user.NHOM === 'NganHang') { %>
      <div class="section-title">Cập nhật</div>
      <a href="/khachhang">👥 Khách hàng</a>
      <a href="/taikhoan">💳 Tài khoản</a>
      <% if (user.NHOM === 'ChiNhanh') { %>
        <a href="/giaodich/goirut">💰 Gửi / Rút tiền</a>
        <a href="/giaodich/chuyentien">↔️ Chuyển tiền</a>
      <% } %>
    <% } %>
    <div class="section-title">Báo cáo</div>
    <a href="/baocao/saoke">📋 Sao kê GD</a>
    <% if (user.NHOM !== 'KhachHang') { %>
      <a href="/baocao/lietke?loai=kh">📊 Liệt kê KH</a>
      <a href="/baocao/lietke?loai=tk">📊 Liệt kê TK</a>
    <% } %>
    <div class="section-title">Hệ thống</div>
    <a href="/logout">🚪 Đăng xuất</a>
  </div>
  <div class="main">
    <%- body %>
  </div>
</div>
<% } else { %>
  <%- body %>
<% } %>

</body>
</html>
```

> **Lưu ý:** EJS không hỗ trợ layout trực tiếp như `<%- body %>`. Cài thêm `express-ejs-layouts`:
> ```bash
> npm install express-ejs-layouts
> ```
> Rồi trong `app.js` thêm:
> ```javascript
> const ejsLayouts = require('express-ejs-layouts');
> app.use(ejsLayouts);
> app.set('layout', 'layout');
> ```

---

### FILE: views/login.ejs

```html
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <title>Đăng nhập – APP NGÂN HÀNG</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: Arial,sans-serif; }
    body { background: linear-gradient(135deg, #1a3c6e 0%, #2e5da8 100%);
           min-height: 100vh; display: flex; align-items: center; justify-content: center; }
    .login-card { background: white; border-radius: 10px; padding: 36px 32px; width: 360px;
                  box-shadow: 0 8px 30px rgba(0,0,0,0.3); }
    .logo { text-align: center; margin-bottom: 20px; }
    .logo h1 { color: #1a3c6e; font-size: 22px; }
    .logo p { color: #6c757d; font-size: 12px; margin-top: 4px; }
    label { display: block; font-size: 13px; font-weight: bold; color: #333; margin: 12px 0 4px; }
    input, select { width: 100%; padding: 9px 11px; border: 1px solid #ced4da;
                    border-radius: 5px; font-size: 14px; }
    input:focus, select:focus { outline: none; border-color: #1a3c6e; }
    .btn-login { width: 100%; background: #1a3c6e; color: white; border: none;
                 padding: 11px; border-radius: 5px; font-size: 15px; font-weight: bold;
                 cursor: pointer; margin-top: 18px; }
    .btn-login:hover { background: #2e5da8; }
    .alert-error { background: #f8d7da; color: #721c24; padding: 9px 12px;
                   border-radius: 4px; font-size: 13px; margin-bottom: 12px; }
    .hint { font-size: 11px; color: #6c757d; margin-top: 14px; text-align: center; }
  </style>
</head>
<body>
<div class="login-card">
  <div class="logo">
    <h1>🏦 APP NGÂN HÀNG</h1>
    <p>Hệ thống CSDL Phân Tán – Demo Đồ Án</p>
  </div>

  <% if (error) { %>
    <div class="alert-error">⚠️ <%= error %></div>
  <% } %>

  <form method="POST" action="/login">
    <label>Tên đăng nhập (MANV / CMND)</label>
    <input type="text" name="username" placeholder="VD: NV001" required autofocus>

    <label>Mật khẩu</label>
    <input type="password" name="password" placeholder="Nhập mật khẩu" required>

    <label>Kết nối chi nhánh</label>
    <select name="chinhanh">
      <option value="BENTHANH">Chi nhánh Bến Thành (NGANHANG1)</option>
      <option value="TANDINH">Chi nhánh Tân Định (NGANHANG2)</option>
      <option value="TRACUU">Tra Cứu – Khách Hàng (NGANHANG3)</option>
    </select>

    <button type="submit" class="btn-login">Đăng nhập</button>
  </form>

  <div class="hint">
    Demo: NV001/123456 (ChiNhanh BT) | NV003/123456 (ChiNhanh TD)
  </div>
</div>
</body>
</html>
```

---

### FILE: views/index.ejs – Trang chủ

```html
<h1>🏠 Trang chủ</h1>

<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-top:10px;">

  <% if (user.NHOM === 'ChiNhanh' || user.NHOM === 'NganHang') { %>
  <a href="/khachhang" style="text-decoration:none;">
    <div style="background:white;padding:20px;border-radius:8px;border-left:4px solid #1a3c6e;box-shadow:0 1px 4px rgba(0,0,0,.1);">
      <div style="font-size:28px;">👥</div>
      <div style="font-weight:bold;color:#1a3c6e;margin-top:6px;">Khách hàng</div>
      <div style="font-size:12px;color:#6c757d;">Thêm / Sửa / Xóa</div>
    </div>
  </a>

  <a href="/taikhoan" style="text-decoration:none;">
    <div style="background:white;padding:20px;border-radius:8px;border-left:4px solid #28a745;box-shadow:0 1px 4px rgba(0,0,0,.1);">
      <div style="font-size:28px;">💳</div>
      <div style="font-weight:bold;color:#28a745;margin-top:6px;">Tài khoản</div>
      <div style="font-size:12px;color:#6c757d;">Mở tài khoản</div>
    </div>
  </a>
  <% } %>

  <% if (user.NHOM === 'ChiNhanh') { %>
  <a href="/giaodich/goirut" style="text-decoration:none;">
    <div style="background:white;padding:20px;border-radius:8px;border-left:4px solid #ffc107;box-shadow:0 1px 4px rgba(0,0,0,.1);">
      <div style="font-size:28px;">💰</div>
      <div style="font-weight:bold;color:#856404;margin-top:6px;">Gửi / Rút tiền</div>
      <div style="font-size:12px;color:#6c757d;">Giao dịch tại quầy</div>
    </div>
  </a>

  <a href="/giaodich/chuyentien" style="text-decoration:none;">
    <div style="background:white;padding:20px;border-radius:8px;border-left:4px solid #dc3545;box-shadow:0 1px 4px rgba(0,0,0,.1);">
      <div style="font-size:28px;">↔️</div>
      <div style="font-weight:bold;color:#dc3545;margin-top:6px;">Chuyển tiền</div>
      <div style="font-size:12px;color:#6c757d;">Nội bộ & liên chi nhánh</div>
    </div>
  </a>
  <% } %>

  <a href="/baocao/saoke" style="text-decoration:none;">
    <div style="background:white;padding:20px;border-radius:8px;border-left:4px solid #6f42c1;box-shadow:0 1px 4px rgba(0,0,0,.1);">
      <div style="font-size:28px;">📋</div>
      <div style="font-weight:bold;color:#6f42c1;margin-top:6px;">Sao kê</div>
      <div style="font-size:12px;color:#6c757d;">Lịch sử giao dịch</div>
    </div>
  </a>

  <% if (user.NHOM !== 'KhachHang') { %>
  <a href="/baocao/lietke?loai=kh" style="text-decoration:none;">
    <div style="background:white;padding:20px;border-radius:8px;border-left:4px solid #17a2b8;box-shadow:0 1px 4px rgba(0,0,0,.1);">
      <div style="font-size:28px;">📊</div>
      <div style="font-weight:bold;color:#117a8b;margin-top:6px;">Báo cáo</div>
      <div style="font-size:12px;color:#6c757d;">Liệt kê KH / TK</div>
    </div>
  </a>
  <% } %>
</div>

<div style="margin-top:24px;background:white;padding:16px;border-radius:8px;box-shadow:0 1px 4px rgba(0,0,0,.1);">
  <h3 style="color:#1a3c6e;margin-bottom:10px;">ℹ️ Thông tin đăng nhập hiện tại</h3>
  <table style="width:auto;box-shadow:none;">
    <tr><td style="width:140px;color:#6c757d;">Nhân viên / KH:</td><td><strong><%= user.HOTEN %></strong></td></tr>
    <tr><td style="color:#6c757d;">Nhóm quyền:</td>
        <td><span class="badge <%= user.NHOM==='NganHang'?'badge-tc':(user.NHOM==='ChiNhanh'?'badge-bn':'badge-td') %>"><%= user.NHOM %></span></td></tr>
    <tr><td style="color:#6c757d;">Chi nhánh:</td><td><%= user.MACN || 'Toàn hệ thống' %></td></tr>
    <tr><td style="color:#6c757d;">Server:</td><td><%= user.SERVER %></td></tr>
  </table>
</div>
```

---

### FILE: views/khachhang/list.ejs

```html
<h1>👥 Danh sách khách hàng</h1>

<% if (success || (typeof query !== 'undefined' && query.success)) { %>
  <div class="alert alert-success">✅ <%= success || query.success %></div>
<% } %>
<% if (error) { %>
  <div class="alert alert-error">❌ <%= error %></div>
<% } %>

<% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>
  <a href="/khachhang/them" class="btn btn-primary" style="margin-bottom:14px;">+ Thêm khách hàng</a>
<% } %>

<table>
  <thead>
    <tr>
      <th>#</th><th>CMND</th><th>Họ tên</th>
      <th>Chi nhánh</th><th>SĐT</th><th>Địa chỉ</th>
      <% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %><th>Thao tác</th><% } %>
    </tr>
  </thead>
  <tbody>
    <% if (rows.length === 0) { %>
      <tr><td colspan="7" style="text-align:center;color:#6c757d;">Không có dữ liệu</td></tr>
    <% } %>
    <% rows.forEach((r, i) => { %>
    <tr>
      <td><%= i+1 %></td>
      <td><code><%= r.CMND %></code></td>
      <td><strong><%= r.HoTen %></strong></td>
      <td>
        <span class="badge <%= r.MACN==='BENTHANH'?'badge-bn':'badge-td' %>">
          <%= r.MACN %>
        </span>
      </td>
      <td><%= r.SODT %></td>
      <td><%= r.DIACHI || '—' %></td>
      <% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>
      <td>
        <a href="/khachhang/sua/<%= r.CMND %>" class="btn btn-warning btn-sm">Sửa</a>
        <form method="POST" action="/khachhang/xoa" style="display:inline;"
              onsubmit="return confirm('Xóa khách hàng <%= r.HoTen %>?')">
          <input type="hidden" name="CMND" value="<%= r.CMND %>">
          <button type="submit" class="btn btn-danger btn-sm">Xóa</button>
        </form>
      </td>
      <% } %>
    </tr>
    <% }) %>
  </tbody>
</table>
<div style="color:#6c757d;font-size:12px;margin-top:8px;">Tổng: <%= rows.length %> khách hàng</div>
```

---

### FILE: views/khachhang/form.ejs

```html
<h1><%= action === 'them' ? '➕ Thêm khách hàng mới' : '✏️ Sửa thông tin khách hàng' %></h1>

<% if (error) { %>
  <div class="alert alert-error">❌ <%= error %></div>
<% } %>

<div class="form-card">
  <form method="POST" action="/khachhang/<%= action %>">
    <% if (action === 'sua' && kh) { %>
      <input type="hidden" name="CMND" value="<%= kh.CMND.trim ? kh.CMND.trim() : kh.CMND %>">
      <div class="form-group">
        <label>CMND (không thể sửa)</label>
        <input type="text" value="<%= kh.CMND.trim ? kh.CMND.trim() : kh.CMND %>" disabled>
      </div>
    <% } else { %>
      <div class="form-group">
        <label>CMND *</label>
        <input type="text" name="CMND" maxlength="10" required
               value="<%= kh ? kh.CMND : '' %>" placeholder="10 ký tự số">
      </div>
    <% } %>

    <div style="display:grid;grid-template-columns:2fr 1fr;gap:12px;">
      <div class="form-group">
        <label>Họ *</label>
        <input type="text" name="HO" required value="<%= kh ? kh.HO : '' %>">
      </div>
      <div class="form-group">
        <label>Tên *</label>
        <input type="text" name="TEN" required value="<%= kh ? kh.TEN : '' %>">
      </div>
    </div>

    <div class="form-group">
      <label>Địa chỉ</label>
      <input type="text" name="DIACHI" value="<%= kh ? kh.DIACHI || '' : '' %>">
    </div>

    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">
      <div class="form-group">
        <label>Giới tính</label>
        <select name="PHAI">
          <option value="Nam" <%= (kh && kh.PHAI==='Nam') ? 'selected' : '' %>>Nam</option>
          <option value="Nữ"  <%= (kh && kh.PHAI==='Nữ')  ? 'selected' : '' %>>Nữ</option>
        </select>
      </div>
      <div class="form-group">
        <label>Ngày cấp CMND *</label>
        <input type="date" name="NGAYCAP" required value="<%= kh ? kh.NGAYCAP : '' %>">
      </div>
    </div>

    <div class="form-group">
      <label>Số điện thoại *</label>
      <input type="text" name="SODT" required value="<%= kh ? kh.SODT : '' %>">
    </div>

    <input type="hidden" name="MACN" value="<%= macn %>">

    <div style="margin-top:16px;display:flex;gap:10px;">
      <button type="submit" class="btn btn-primary">
        <%= action === 'them' ? 'Thêm mới' : 'Lưu thay đổi' %>
      </button>
      <a href="/khachhang" class="btn btn-secondary">Hủy</a>
    </div>
  </form>
</div>
```

---

### FILE: views/taikhoan/list.ejs

```html
<h1>💳 Danh sách tài khoản</h1>

<% if (success) { %><div class="alert alert-success">✅ <%= success %></div><% } %>
<% if (error)   { %><div class="alert alert-error">❌ <%= error %></div><% } %>

<% if (['ChiNhanh','NganHang'].includes(user.NHOM)) { %>
  <a href="/taikhoan/mo" class="btn btn-primary" style="margin-bottom:14px;">+ Mở tài khoản</a>
<% } %>

<table>
  <thead>
    <tr>
      <th>#</th><th>Số TK</th><th>CMND</th><th>Họ tên</th>
      <th>Chi nhánh</th><th>Ngày mở</th><th class="money">Số dư (VNĐ)</th>
    </tr>
  </thead>
  <tbody>
    <% rows.forEach((r, i) => { %>
    <tr>
      <td><%= i+1 %></td>
      <td><code><strong><%= r.SOTK %></strong></code></td>
      <td><code><%= r.CMND %></code></td>
      <td><%= r.HoTen || '—' %></td>
      <td><span class="badge <%= r.MACN==='BENTHANH'?'badge-bn':'badge-td' %>"><%= r.MACN %></span></td>
      <td><%= r.NGAYMOTK || '—' %></td>
      <td class="money money-positive"><%= Number(r.SODU).toLocaleString('vi-VN') %></td>
    </tr>
    <% }) %>
    <% if (rows.length === 0) { %>
      <tr><td colspan="7" style="text-align:center;color:#6c757d;">Không có tài khoản</td></tr>
    <% } %>
  </tbody>
</table>
<div style="color:#6c757d;font-size:12px;margin-top:8px;">Tổng: <%= rows.length %> tài khoản</div>
```

---

### FILE: views/taikhoan/form.ejs

```html
<h1>➕ Mở tài khoản mới</h1>

<% if (error) { %><div class="alert alert-error">❌ <%= error %></div><% } %>

<div class="form-card">
  <form method="POST" action="/taikhoan/mo">
    <div class="form-group">
      <label>Số tài khoản (tự động)</label>
      <input type="text" name="SOTK" value="<%= sotk %>" readonly
             style="background:#f8f9fa;font-weight:bold;">
    </div>

    <div class="form-group">
      <label>Khách hàng *</label>
      <select name="CMND" required>
        <option value="">-- Chọn khách hàng --</option>
        <% khRows.forEach(kh => { %>
          <option value="<%= kh.CMND %>"><%= kh.HoTen %> (<%= kh.CMND %>)</option>
        <% }) %>
      </select>
    </div>

    <div class="form-group">
      <label>Số dư ban đầu (VNĐ)</label>
      <input type="number" name="SODU" value="0" min="0" step="100000">
    </div>

    <input type="hidden" name="MACN" value="<%= macn %>">

    <div style="margin-top:16px;display:flex;gap:10px;">
      <button type="submit" class="btn btn-success">Mở tài khoản</button>
      <a href="/taikhoan" class="btn btn-secondary">Hủy</a>
    </div>
  </form>
</div>
```

---

### FILE: views/giaodich/goirut.ejs

```html
<h1>💰 Gửi / Rút tiền</h1>

<% if (success) { %><div class="alert alert-success">✅ <%= success %></div><% } %>
<% if (error)   { %><div class="alert alert-error">❌ <%= error %></div><% } %>

<div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;">

  <!-- GỬI TIỀN -->
  <div class="form-card">
    <h3 style="color:#28a745;margin-bottom:14px;">⬆️ Gửi tiền</h3>
    <form method="POST" action="/giaodich/guitien">
      <div class="form-group">
        <label>Số tài khoản</label>
        <select name="SOTK" id="sotk-gui" onchange="loadSoDu(this,'sodu-gui')" required>
          <option value="">-- Chọn tài khoản --</option>
          <% tkRows.forEach(tk => { %>
            <option value="<%= tk.SOTK %>"><%= tk.SOTK %></option>
          <% }) %>
        </select>
      </div>
      <div class="form-group">
        <label>Số dư hiện tại</label>
        <input type="text" id="sodu-gui" readonly style="background:#f8f9fa;color:#28a745;font-weight:bold;">
      </div>
      <div class="form-group">
        <label>Số tiền gửi (tối thiểu 100,000 VNĐ)</label>
        <input type="number" name="SOTIEN" min="100000" step="100000" required placeholder="100000">
      </div>
      <button type="submit" class="btn btn-success">Gửi tiền</button>
    </form>
  </div>

  <!-- RÚT TIỀN -->
  <div class="form-card">
    <h3 style="color:#dc3545;margin-bottom:14px;">⬇️ Rút tiền</h3>
    <form method="POST" action="/giaodich/ruttien">
      <div class="form-group">
        <label>Số tài khoản</label>
        <select name="SOTK" id="sotk-rut" onchange="loadSoDu(this,'sodu-rut')" required>
          <option value="">-- Chọn tài khoản --</option>
          <% tkRows.forEach(tk => { %>
            <option value="<%= tk.SOTK %>"><%= tk.SOTK %></option>
          <% }) %>
        </select>
      </div>
      <div class="form-group">
        <label>Số dư hiện tại</label>
        <input type="text" id="sodu-rut" readonly style="background:#f8f9fa;color:#dc3545;font-weight:bold;">
      </div>
      <div class="form-group">
        <label>Số tiền rút (tối thiểu 100,000 VNĐ)</label>
        <input type="number" name="SOTIEN" min="100000" step="100000" required placeholder="100000">
      </div>
      <button type="submit" class="btn btn-danger">Rút tiền</button>
    </form>
  </div>
</div>

<script>
async function loadSoDu(selectEl, targetId) {
  const sotk = selectEl.value;
  if (!sotk) return;
  try {
    const res = await fetch('/giaodich/api/sodu/' + sotk);
    const data = await res.json();
    const el = document.getElementById(targetId);
    if (data.SODU !== undefined) {
      el.value = Number(data.SODU).toLocaleString('vi-VN') + ' VNĐ';
    } else {
      el.value = data.error || 'Lỗi';
    }
  } catch(e) { console.error(e); }
}
</script>
```

---

### FILE: views/giaodich/chuyentien.ejs

```html
<h1>↔️ Chuyển tiền</h1>

<% if (success) { %><div class="alert alert-success">✅ <%= success %></div><% } %>
<% if (error)   { %><div class="alert alert-error">❌ <%= error %></div><% } %>

<div class="form-card" style="max-width:520px;">
  <form method="POST" action="/giaodich/chuyentien" onsubmit="return xacNhan()">

    <div class="form-group">
      <label>Tài khoản chuyển</label>
      <select name="SOTK_CHUYEN" id="sotk-chuyen"
              onchange="loadSoDu(this,'sodu-chuyen')" required>
        <option value="">-- Chọn TK chuyển --</option>
        <% tkRows.forEach(tk => { %>
          <option value="<%= tk.SOTK %>"><%= tk.SOTK %> (Số dư: <%= Number(tk.SODU).toLocaleString('vi-VN') %>)</option>
        <% }) %>
      </select>
    </div>

    <div class="form-group">
      <label>Số dư TK chuyển</label>
      <input type="text" id="sodu-chuyen" readonly style="background:#f8f9fa;font-weight:bold;color:#1a3c6e;">
    </div>

    <div class="form-group">
      <label>Tài khoản nhận <small style="color:#6c757d;">(có thể ở chi nhánh khác)</small></label>
      <input type="text" name="SOTK_NHAN" id="sotk-nhan"
             placeholder="Nhập số tài khoản nhận" required maxlength="9"
             onblur="kiemTraTKNhan()">
      <div id="tk-nhan-info" style="font-size:12px;color:#6c757d;margin-top:4px;"></div>
    </div>

    <div class="form-group">
      <label>Số tiền chuyển (VNĐ)</label>
      <input type="number" name="SOTIEN" id="sotien"
             min="1000" step="1000" required placeholder="VD: 500000">
    </div>

    <div style="background:#fff3cd;padding:10px;border-radius:4px;font-size:12px;margin-bottom:14px;">
      ⚠️ Nếu chuyển sang chi nhánh khác, giao dịch sẽ cập nhật cả 2 server qua Linked Server.
    </div>

    <div style="display:flex;gap:10px;">
      <button type="submit" class="btn btn-primary">Thực hiện chuyển tiền</button>
      <a href="/" class="btn btn-secondary">Hủy</a>
    </div>
  </form>
</div>

<script>
async function loadSoDu(selectEl, targetId) {
  const sotk = selectEl.value;
  if (!sotk) return;
  const res  = await fetch('/giaodich/api/sodu/' + sotk);
  const data = await res.json();
  document.getElementById(targetId).value =
    data.SODU !== undefined ? Number(data.SODU).toLocaleString('vi-VN') + ' VNĐ' : (data.error||'Lỗi');
}

async function kiemTraTKNhan() {
  const sotk = document.getElementById('sotk-nhan').value.trim();
  const info = document.getElementById('tk-nhan-info');
  if (!sotk) { info.textContent = ''; return; }
  const res  = await fetch('/giaodich/api/sodu/' + sotk);
  const data = await res.json();
  if (data.SODU !== undefined) {
    info.textContent = '✅ Tài khoản hợp lệ. Số dư: ' + Number(data.SODU).toLocaleString('vi-VN') + ' VNĐ';
    info.style.color = '#28a745';
  } else {
    info.textContent = '❌ ' + (data.error || 'Không tìm thấy tài khoản');
    info.style.color = '#dc3545';
  }
}

function xacNhan() {
  const from   = document.getElementById('sotk-chuyen').value;
  const to     = document.getElementById('sotk-nhan').value;
  const sotien = document.getElementById('sotien').value;
  return confirm(`Xác nhận chuyển ${Number(sotien).toLocaleString('vi-VN')} VNĐ\ntừ ${from} → ${to}?`);
}
</script>
```

---

### FILE: views/baocao/saoke.ejs

```html
<h1>📋 Sao kê giao dịch tài khoản</h1>

<% if (error) { %><div class="alert alert-error">❌ <%= error %></div><% } %>

<div class="form-card" style="margin-bottom:20px;">
  <form method="POST" action="/baocao/saoke" style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;">
    <div class="form-group" style="flex:1;min-width:140px;">
      <label>Số tài khoản</label>
      <select name="SOTK" required>
        <option value="">-- Chọn --</option>
        <% tkRows.forEach(tk => { %>
          <option value="<%= tk.SOTK %>" <%= (query.SOTK===tk.SOTK)?'selected':'' %>><%= tk.SOTK %></option>
        <% }) %>
      </select>
    </div>
    <div class="form-group" style="flex:1;min-width:130px;">
      <label>Từ ngày</label>
      <input type="date" name="TUNGAY" value="<%= query.TUNGAY||'' %>" required>
    </div>
    <div class="form-group" style="flex:1;min-width:130px;">
      <label>Đến ngày</label>
      <input type="date" name="DENNGAY" value="<%= query.DENNGAY||'' %>" required>
    </div>
    <div class="form-group">
      <button type="submit" class="btn btn-primary">Xem sao kê</button>
    </div>
  </form>
</div>

<% if (rows) { %>
<div style="background:white;padding:14px 18px;border-radius:6px;margin-bottom:12px;box-shadow:0 1px 4px rgba(0,0,0,.1);">
  <div style="display:flex;justify-content:space-between;">
    <span>📌 <strong>Số dư đầu kỳ</strong> (<%= query.TUNGAY %>):</span>
    <span class="money money-positive"><strong><%= Number(sodu_dau).toLocaleString('vi-VN') %> VNĐ</strong></span>
  </div>
</div>

<table>
  <thead>
    <tr>
      <th>#</th><th>Ngày GD</th><th>Loại GD</th>
      <th class="money">Tiền vào</th>
      <th class="money">Tiền ra</th>
      <th class="money">Số dư sau</th>
    </tr>
  </thead>
  <tbody>
    <% if (rows.length === 0) { %>
      <tr><td colspan="6" style="text-align:center;color:#6c757d;">Không có giao dịch trong kỳ</td></tr>
    <% } %>
    <% rows.forEach((r, i) => { %>
    <tr>
      <td><%= i+1 %></td>
      <td><%= r.NGAYGD %></td>
      <td>
        <span class="badge <%= r.LoaiGD.includes('Gửi')||r.LoaiGD.includes('Đến') ? 'badge-bn' : 'badge-td' %>">
          <%= r.LoaiGD %>
        </span>
      </td>
      <td class="money money-positive">
        <%= r.TienVao > 0 ? '+'+Number(r.TienVao).toLocaleString('vi-VN') : '—' %>
      </td>
      <td class="money money-negative">
        <%= r.TienRa > 0 ? '-'+Number(r.TienRa).toLocaleString('vi-VN') : '—' %>
      </td>
      <td class="money"><strong><%= Number(r.SoDuSau).toLocaleString('vi-VN') %></strong></td>
    </tr>
    <% }) %>
  </tbody>
</table>

<div style="background:white;padding:14px 18px;border-radius:6px;margin-top:12px;box-shadow:0 1px 4px rgba(0,0,0,.1);">
  <div style="display:flex;justify-content:space-between;">
    <span>📌 <strong>Số dư cuối kỳ</strong> (<%= query.DENNGAY %>):</span>
    <span class="money money-positive"><strong><%= Number(sodu_cuoi).toLocaleString('vi-VN') %> VNĐ</strong></span>
  </div>
</div>
<% } %>
```

---

### FILE: views/baocao/lietke.ejs

```html
<h1>📊 <%= title || 'Báo cáo liệt kê' %></h1>

<% if (error) { %><div class="alert alert-error">❌ <%= error %></div><% } %>

<div class="form-card" style="margin-bottom:16px;">
  <form method="GET" action="/baocao/lietke" style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;">
    <div class="form-group">
      <label>Loại báo cáo</label>
      <select name="loai" onchange="this.form.submit()">
        <option value="kh" <%= loai==='kh'?'selected':'' %>>Danh sách khách hàng</option>
        <option value="tk" <%= loai==='tk'?'selected':'' %>>Tài khoản mở theo thời gian</option>
      </select>
    </div>
    <% if (loai === 'tk') { %>
    <div class="form-group">
      <label>Từ ngày</label>
      <input type="date" name="tungay" value="<%= query.tungay||'' %>">
    </div>
    <div class="form-group">
      <label>Đến ngày</label>
      <input type="date" name="denngay" value="<%= query.denngay||'' %>">
    </div>
    <% } %>
    <div class="form-group">
      <button type="submit" class="btn btn-primary">Xem</button>
    </div>
  </form>
</div>

<% if (loai === 'kh') { %>
<table>
  <thead>
    <tr><th>#</th><th>CMND</th><th>Họ tên</th><th>Chi nhánh</th><th>SĐT</th></tr>
  </thead>
  <tbody>
    <% rows.forEach((r,i) => { %>
    <tr>
      <td><%= i+1 %></td>
      <td><code><%= r.CMND %></code></td>
      <td><strong><%= r.HoTen %></strong></td>
      <td><span class="badge <%= r.MACN==='BENTHANH'?'badge-bn':'badge-td' %>"><%= r.MACN %></span></td>
      <td><%= r.SODT %></td>
    </tr>
    <% }) %>
  </tbody>
</table>

<% } else if (loai === 'tk') { %>
<table>
  <thead>
    <tr><th>#</th><th>Số TK</th><th>CMND</th><th>Họ tên</th><th>Chi nhánh</th><th>Ngày mở</th><th class="money">Số dư</th></tr>
  </thead>
  <tbody>
    <% rows.forEach((r,i) => { %>
    <tr>
      <td><%= i+1 %></td>
      <td><code><strong><%= r.SOTK %></strong></code></td>
      <td><code><%= r.CMND %></code></td>
      <td><%= r.HoTen || '—' %></td>
      <td><span class="badge <%= r.MACN==='BENTHANH'?'badge-bn':'badge-td' %>"><%= r.MACN %></span></td>
      <td><%= r.NGAYMOTK %></td>
      <td class="money money-positive"><%= Number(r.SODU).toLocaleString('vi-VN') %></td>
    </tr>
    <% }) %>
  </tbody>
</table>
<% } %>

<div style="color:#6c757d;font-size:12px;margin-top:8px;">Tổng: <%= rows.length %> bản ghi</div>
```

---

### FILE: views/error.ejs

```html
<!DOCTYPE html>
<html lang="vi">
<head><meta charset="UTF-8"><title>Lỗi</title>
<style>
  body{font-family:Arial;display:flex;align-items:center;justify-content:center;min-height:100vh;background:#f0f2f5;}
  .box{background:white;padding:32px;border-radius:8px;text-align:center;max-width:400px;box-shadow:0 2px 8px rgba(0,0,0,.15);}
  h2{color:#dc3545;} p{color:#555;margin:10px 0 20px;}
  a{background:#1a3c6e;color:white;padding:9px 20px;border-radius:5px;text-decoration:none;}
</style>
</head>
<body>
<div class="box">
  <h2>⚠️ Lỗi</h2>
  <p><%= message %></p>
  <a href="/">Về trang chủ</a>
</div>
</body>
</html>
```

---

## CẬP NHẬT app.js – Thêm express-ejs-layouts

```javascript
// Thêm vào đầu app.js sau require('express')
const ejsLayouts = require('express-ejs-layouts');

// Thêm sau app.set('views', ...)
app.use(ejsLayouts);
app.set('layout', 'layout');

// Các view không cần layout dùng: res.render('login', { layout: false, ... })
// Sửa trong routes/auth.js:
//   res.render('login', { layout: false, error: null });
// Và error.ejs không cần layout nên khi render:
//   res.render('error', { layout: false, message: '...' });
```

Cài thêm package:
```bash
npm install express-ejs-layouts
```

---

## CHẠY APP

```bash
# 1. Đảm bảo SQL Server 4 instance đang chạy

# 2. Sửa db.js: thay 'TEN_MAY_TINH' bằng tên máy tính thật của bạn
#    VD: 'DESKTOP-ABC123\\NGANHANG1'

# 3. Chạy app
cd APP_NGANHANG
npm start

# 4. Mở browser
# http://localhost:3000

# 5. Đăng nhập test
# Username: NV001  | Password: 123456 | Chi nhánh: BENTHANH
# Username: NV003  | Password: 123456 | Chi nhánh: TANDINH
```

---

## LƯU Ý QUAN TRỌNG KHI DEMO

### Vấn đề xác thực password

App hiện tại dùng `sa` để query – không xác thực password người dùng thật sự. Để demo phân quyền đúng hơn, thêm đoạn kiểm tra sau vào `routes/auth.js`:

```javascript
// Kiểm tra login bằng cách thử kết nối với chính credentials người dùng nhập
const { sql } = require('../db');
const testConfig = {
  server: configs[serverKey].server,
  database: 'NGANHANG',
  user: username,
  password: password,
  options: { encrypt: false, trustServerCertificate: true }
};
try {
  const testPool = await new sql.ConnectionPool(testConfig).connect();
  await testPool.close();
  // Xác thực thành công → tiếp tục
} catch(e) {
  return res.render('login', { layout: false, error: 'Sai tên đăng nhập hoặc mật khẩu.' });
}
```

### Tìm tên máy tính

```cmd
# Chạy trong Command Prompt
hostname
# Hoặc
echo %COMPUTERNAME%
```

Kết quả VD: `DESKTOP-ABC123` → tên server sẽ là `DESKTOP-ABC123\\NGANHANG1`

### Cấu trúc thư mục hoàn chỉnh cần tạo

```
mkdir APP_NGANHANG
cd APP_NGANHANG
npm init -y
npm install express ejs express-session express-ejs-layouts mssql
mkdir routes views views\khachhang views\taikhoan views\giaodich views\baocao
```

Sau đó tạo từng file theo nội dung ở trên.

---

*File này chứa full code app demo Node.js cho đồ án CSDL Phân Tán – Ngân Hàng.*
*Chạy được ngay sau khi cài Node.js + sửa tên máy tính trong db.js.*
