// routes/nhanvien.js
const express = require('express');
const router = express.Router();
const { querySQL, execSP } = require('../db');

function getServer(req) {
  return req.session.user.SERVER || 'BENTHANH';
}

// GET /nhanvien - Danh sách nhân viên
router.get('/', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    let rows;
    if (user.NHOM === 'NganHang') {
      rows = await querySQL(req, 'TRACUU', `
        SELECT RTRIM(MANV) AS MANV,
               RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
               RTRIM(CMND) AS CMND,
               RTRIM(MACN) AS MACN, SODT, DIACHI, TrangThaiXoa
        FROM NhanVien
        ORDER BY MACN, HO, TEN
      `);
    } else {
      rows = await querySQL(req, server, `
        SELECT RTRIM(MANV) AS MANV,
               RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
               RTRIM(CMND) AS CMND,
               RTRIM(MACN) AS MACN, SODT, DIACHI, TrangThaiXoa
        FROM NhanVien
        WHERE RTRIM(MACN) = @macn
        ORDER BY HO, TEN
      `, { macn: user.MACN });
    }
    res.render('nhanvien/list', { rows, error: req.query.error, success: req.query.success });
  } catch (err) {
    res.render('nhanvien/list', { rows: [], error: err.message, success: null });
  }
});

// GET /nhanvien/them - Form thêm mới
router.get('/them', (req, res) => {
  const user = req.session.user;
  res.render('nhanvien/form', {
    nv: null, action: 'them', error: null,
    macn: user.MACN
  });
});

// POST /nhanvien/them - Thực hiện thêm
router.post('/them', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { MANV, HO, TEN, CMND, DIACHI, PHAI, SODT } = req.body;
  const MACN = user.MACN || req.body.MACN || 'BENTHANH';

  try {
    await querySQL(req, server, `
      INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
      VALUES (@manv, @ho, @ten, @cmnd, @diachi, @phai, @sodt, @macn, 0)
    `, { manv: MANV, ho: HO, ten: TEN, cmnd: CMND, diachi: DIACHI, phai: PHAI, sodt: SODT, macn: MACN });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Thêm nhân viên thành công'));
  } catch (err) {
    res.render('nhanvien/form', {
      nv: req.body, action: 'them',
      error: err.message, macn: MACN
    });
  }
});

// GET /nhanvien/sua/:manv
router.get('/sua/:manv', async (req, res) => {
  const server = getServer(req);
  const { manv } = req.params;
  try {
    const rows = await querySQL(req, server, `
      SELECT * FROM NhanVien WHERE RTRIM(MANV) = @manv
    `, { manv });
    if (rows.length === 0) return res.redirect('/nhanvien');
    const nv = rows[0];
    res.render('nhanvien/form', {
      nv, action: 'sua', error: null,
      macn: req.session.user.MACN
    });
  } catch (err) {
    res.redirect('/nhanvien');
  }
});

// POST /nhanvien/sua
router.post('/sua', async (req, res) => {
  const server = getServer(req);
  const { MANV, HO, TEN, CMND, DIACHI, PHAI, SODT } = req.body;
  try {
    await querySQL(req, server, `
      UPDATE NhanVien
      SET HO=@ho, TEN=@ten, CMND=@cmnd, DIACHI=@diachi, PHAI=@phai, SODT=@sodt
      WHERE RTRIM(MANV) = @manv
    `, { ho: HO, ten: TEN, cmnd: CMND, diachi: DIACHI, phai: PHAI, sodt: SODT, manv: MANV });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Cập nhật thành công'));
  } catch (err) {
    res.render('nhanvien/form', {
      nv: req.body, action: 'sua',
      error: err.message, macn: req.session.user.MACN
    });
  }
});

// POST /nhanvien/xoa
router.post('/xoa', async (req, res) => {
  const server = getServer(req);
  const { MANV } = req.body;
  try {
    await querySQL(req, server, `
      UPDATE NhanVien SET TrangThaiXoa = 1 WHERE RTRIM(MANV) = @manv
    `, { manv: MANV });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Đã xóa nhân viên'));
  } catch (err) {
    res.redirect('/nhanvien?error=' + encodeURIComponent(err.message));
  }
});

// POST /nhanvien/chuyen
router.post('/chuyen', async (req, res) => {
  const server = getServer(req);
  const { MANV, MACN_MOI } = req.body;
  try {
    await execSP(req, server, 'sp_ChuyenNhanVien', {
      MANV, MACN_MOI
    });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Đã chuyển chi nhánh thành công'));
  } catch (err) {
    res.redirect('/nhanvien?error=' + encodeURIComponent(err.message));
  }
});

// POST /nhanvien/phuchoi
router.post('/phuchoi', async (req, res) => {
  const server = getServer(req);
  const { MANV } = req.body;
  try {
    await querySQL(req, server, `
      UPDATE NhanVien SET TrangThaiXoa = 0 WHERE RTRIM(MANV) = @manv
    `, { manv: MANV });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Đã phục hồi nhân viên'));
  } catch (err) {
    res.redirect('/nhanvien?error=' + encodeURIComponent(err.message));
  }
});

module.exports = router;
