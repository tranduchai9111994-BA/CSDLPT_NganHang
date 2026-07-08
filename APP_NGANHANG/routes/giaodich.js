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
  await renderGoiRut(req, res, {
    error: req.query.error || null,
    success: req.query.success || null
  });
});

async function renderGoiRut(req, res, { error = null, success = null, activeTab = 'gui', prevSOTK = '', prevSOTIEN = '' } = {}) {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    const tkRows = await querySQL(req, server, `
      SELECT RTRIM(SOTK) AS SOTK, SODU, RTRIM(CMND) AS CMND, RTRIM(MACN) AS MACN
      FROM TaiKhoan ORDER BY MACN, SOTK
    `, {});
    res.render('giaodich/goirut', { tkRows, error, success, activeTab, prevSOTK, prevSOTIEN });
  } catch (err) {
    res.render('giaodich/goirut', { tkRows: [], error: err.message, success: null, activeTab, prevSOTK, prevSOTIEN });
  }
}

// POST /giaodich/guitien
// SP luôn chạy local (server NV) — GD_GOIRUT phân mảnh theo NV.
// SP tự xử lý UPDATE TK qua LINK1 nếu TK thuộc CN khác.
router.post('/guitien', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, SOTIEN } = req.body;
  try {
    await execSP(req, server, 'sp_GuiTien', {
      SOTK: SOTK.trim(), SOTIEN: parseFloat(SOTIEN), MANV: user.MANV
    });
    res.redirect('/giaodich/goirut?success=Gửi tiền thành công! Số tiền: ' + Number(SOTIEN).toLocaleString('vi-VN') + ' VNĐ');
  } catch (err) {
    await renderGoiRut(req, res, { error: err.message, activeTab: 'gui', prevSOTK: SOTK, prevSOTIEN: SOTIEN });
  }
});

// POST /giaodich/ruttien
router.post('/ruttien', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, SOTIEN } = req.body;
  try {
    await execSP(req, server, 'sp_RutTien', {
      SOTK: SOTK.trim(), SOTIEN: parseFloat(SOTIEN), MANV: user.MANV
    });
    res.redirect('/giaodich/goirut?success=Rút tiền thành công! Số tiền: ' + Number(SOTIEN).toLocaleString('vi-VN') + ' VNĐ');
  } catch (err) {
    await renderGoiRut(req, res, { error: err.message, activeTab: 'rut', prevSOTK: SOTK, prevSOTIEN: SOTIEN });
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
      SELECT RTRIM(SOTK) AS SOTK, SODU, RTRIM(MACN) AS MACN FROM TaiKhoan ORDER BY MACN, SOTK
    `, {});
    res.render('giaodich/chuyentien', {
      tkRows, error: req.query.error || null, success: req.query.success || null
    });
  } catch (err) {
    res.render('giaodich/chuyentien', { tkRows: [], error: err.message, success: null });
  }
});

// POST /giaodich/chuyentien
// SP luôn chạy local (server NV) — GD_CHUYENTIEN phân mảnh theo NV.
// sp_ChuyenTien đã có logic LINK1 để UPDATE TK nhận nếu khác CN.
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
