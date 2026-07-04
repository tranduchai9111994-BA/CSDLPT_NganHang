// routes/auth.js
const express = require('express');
const router = express.Router();
const { sql, configs } = require('../db');

// GET /login
router.get('/login', (req, res) => {
  if (req.session.user) return res.redirect('/');
  res.render('login', { layout: false, error: null });
});

// POST /login – xử lý đăng nhập
router.post('/login', async (req, res) => {
  const { username, password, chinhanh } = req.body;
  const serverKey = chinhanh || 'BENTHANH';

  try {
    const serverConfig = configs[serverKey];
    if (!serverConfig) throw new Error('Cấu hình chi nhánh không hợp lệ.');

    // Tạo cấu hình kết nối TỪNG LẦN ĐĂNG NHẬP bằng thông tin user cung cấp
    const userConfig = {
      server: serverConfig.server,
      database: serverConfig.database,
      user: username,
      password: password,
      options: {
        encrypt: false,
        trustServerCertificate: true,
        enableArithAbort: true
      }
    };

    // =====================================================================
    // SQL AUTHENTICATION (ÁP DỤNG CHO CẢ NHÂN VIÊN, GIÁM ĐỐC VÀ KHÁCH HÀNG)
    // Hệ thống sẽ dùng chính username và password người dùng cung cấp
    // để mở một phiên kết nối thực thụ tới SQL Server.
    // =====================================================================
    let poolUser;
    try {
      poolUser = await new sql.ConnectionPool(userConfig).connect();
    } catch (dbErr) {
      console.error('[SQL AUTH ERROR - CHI TIẾT LỖI TỪ DB]:', dbErr.message);
      return res.render('login', { layout: false, error: 'Sai tài khoản hoặc mật khẩu (Lỗi Database: ' + dbErr.message + ')', oldUsername: req.body.username, oldBranch: req.body.chinhanh });
    }

    const request = poolUser.request();
    request.input('LoginName', sql.NVarChar, username);

    let loginResult;
    try {
      loginResult = await request.execute('sp_Login_App');
    } catch (err) {
      poolUser.close();
      throw err;
    }

    poolUser.close();

    if (!loginResult || !loginResult.recordset || loginResult.recordset.length === 0) {
      return res.render('login', { layout: false, error: 'Tài khoản SQL chưa được phân quyền trong hệ thống (Mapping User).', oldUsername: req.body.username, oldBranch: req.body.chinhanh });
    }

    const nv = loginResult.recordset[0];
    
    // Nếu MACN trả về từ Database khác với Server người dùng đã chọn ở Form thì báo lỗi ngay
    if (nv.NHOM && nv.NHOM.trim() === 'ChiNhanh' && nv.MACN && nv.MACN.trim() !== serverKey) {
      return res.render('login', { layout: false, error: 'Bạn không có quyền đăng nhập vào chi nhánh này!', oldUsername: req.body.username, oldBranch: req.body.chinhanh });
    }
    
    req.session.user = {
      USERNAME: username,
      PASSWORD: password,
      MANV: nv.MANV ? nv.MANV.trim() : username,
      HOTEN: nv.HOTEN ? nv.HOTEN.trim() : '',
      NHOM: nv.NHOM, // Sẽ là 'NganHang', 'ChiNhanh', hoặc 'KhachHang'
      MACN: nv.MACN ? nv.MACN.trim() : '', 
      SERVER: serverKey
    };

    return res.redirect('/');

  } catch (err) {
    console.error('[LOGIN ERROR]', err.message);
    res.render('login', { layout: false, error: 'Lỗi hệ thống: ' + err.message, oldUsername: req.body.username, oldBranch: req.body.chinhanh });
  }
});

// GET /logout
router.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

module.exports = router;
