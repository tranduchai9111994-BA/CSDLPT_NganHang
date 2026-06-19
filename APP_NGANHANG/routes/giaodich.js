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
    const tkRows = await querySQL(req, server, `
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
    await execSP(req, server, 'sp_GuiTien', {
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
    await execSP(req, server, 'sp_RutTien', {
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
    const tkRows = await querySQL(req, server, `
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
    await execSP(req, server, 'sp_ChuyenTien', {
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
    const rows = await querySQL(req, server, `
      SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK)=@sotk
    `, { sotk });
    if (rows.length === 0) return res.json({ error: 'Tài khoản không tồn tại' });
    res.json({ SODU: rows[0].SODU });
  } catch (err) {
    res.json({ error: err.message });
  }
});

module.exports = router;
