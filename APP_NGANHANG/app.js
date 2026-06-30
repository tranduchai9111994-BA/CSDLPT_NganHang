// app.js
const express = require('express');
const session = require('express-session');
const path = require('path');
const ejsLayouts = require('express-ejs-layouts');

const app = express();
const PORT = 3000;

// ==== CẤU HÌNH VIEW ENGINE ====
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(ejsLayouts);
app.set('layout', 'layout');

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
app.use((req, res, next) => {
  res.locals.user = req.session.user || null;
  next();
});

function requireLogin(req, res, next) {
  if (!req.session.user) {
    return res.redirect('/login');
  }
  next();
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.session.user) return res.redirect('/login');
    if (!roles.includes(req.session.user.NHOM)) {
      return res.status(403).render('error', {
        layout: false,
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
const nhanVienRoutes  = require('./routes/nhanvien');
const quantriRoutes   = require('./routes/quantri');

app.use('/', authRoutes);
app.use('/quantri',   requireLogin, requireRole('NganHang', 'ChiNhanh'), quantriRoutes);
app.use('/khachhang', requireLogin, requireRole('NganHang', 'ChiNhanh'), khachHangRoutes);
app.use('/taikhoan',  requireLogin, requireRole('NganHang', 'ChiNhanh', 'KhachHang'), taiKhoanRoutes);
app.use('/giaodich',  requireLogin, requireRole('NganHang', 'ChiNhanh'), giaoDichRoutes);
app.use('/baocao',    requireLogin, requireRole('NganHang', 'ChiNhanh', 'KhachHang'), baoCaoRoutes);
app.use('/nhanvien',  requireLogin, requireRole('NganHang', 'ChiNhanh'), nhanVienRoutes);

// Trang chủ
app.get('/', requireLogin, (req, res) => {
  res.render('index');
});

// Xử lý lỗi 404
app.use((req, res) => {
  res.status(404).render('error', { layout: false, message: 'Trang không tồn tại.' });
});

// ==== KHỞI ĐỘNG SERVER ====
app.listen(PORT, () => {
  console.log(`\n========================================`);
  console.log(`  APP NGÂN HÀNG đang chạy tại:`);
  console.log(`  http://localhost:${PORT}`);
  console.log(`========================================\n`);
});

module.exports = { requireLogin, requireRole };
