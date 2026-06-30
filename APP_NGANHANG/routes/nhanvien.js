// routes/nhanvien.js
const express = require('express');
const router = express.Router();
const { querySQL, execSP, execSPAdmin, querySP } = require('../db');

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
      // TRACUU không có NhanVien local → SP đọc qua LINK1+LINK2
      rows = await querySP(req, 'TRACUU', 'sp_DanhSachNhanVien', {});
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

// Sinh mã NV tự động theo prefix chi nhánh: BT001, TD001, ...
// Query trên chính server đích — SP_ChuyenNhanVien cũng dùng cùng logic phía SQL
// nên không cần cross-check thêm tại đây (SP đã có vòng lặp tránh race condition).
async function sinhMANV(req, server, macn) {
  const prefix = macn === 'BENTHANH' ? 'BT' : 'TD';
  const rows = await querySQL(req, server, `
    SELECT TOP 1 RTRIM(MANV) AS MANV FROM NhanVien
    WHERE RTRIM(MANV) LIKE @prefix + '%'
    ORDER BY MANV DESC
  `, { prefix });
  if (rows.length === 0) return prefix + '001';
  const last = rows[0].MANV;
  const numStr = last.slice(prefix.length);
  const num = parseInt(numStr, 10);
  return prefix + String(isNaN(num) ? 1 : num + 1).padStart(3, '0');
}

// GET /nhanvien/them - Form thêm mới
router.get('/them', async (req, res) => {
  const server = getServer(req);
  const user = req.session.user;
  try {
    const manv = await sinhMANV(req, server, user.MACN);
    res.render('nhanvien/form', {
      nv: null, action: 'them', error: null,
      macn: user.MACN, manv
    });
  } catch (err) {
    res.render('nhanvien/form', {
      nv: null, action: 'them', error: err.message,
      macn: user.MACN, manv: ''
    });
  }
});

// POST /nhanvien/them - Thực hiện thêm
router.post('/them', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  let { MANV, HO, TEN, CMND, DIACHI, PHAI, SODT } = req.body;
  const MACN = user.MACN || req.body.MACN || 'BENTHANH';

  try {
    if (!MANV) {
      MANV = await sinhMANV(req, server, MACN);
    }
    await querySQL(req, server, `
      INSERT INTO NhanVien (MANV, HO, TEN, CMND, DIACHI, PHAI, SODT, MACN, TrangThaiXoa)
      VALUES (@manv, @ho, @ten, @cmnd, @diachi, @phai, @sodt, @macn, 0)
    `, { manv: MANV, ho: HO, ten: TEN, cmnd: CMND, diachi: DIACHI, phai: PHAI, sodt: SODT, macn: MACN });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Thêm nhân viên thành công'));
  } catch (err) {
    res.render('nhanvien/form', {
      nv: req.body, action: 'them',
      error: err.message, macn: MACN, manv: MANV || ''
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
  const { MANV, MACN_MOI } = req.body;
  try {
    // SP phải chạy trên server chứa NV hiện tại (chi nhánh cũ)
    // Xác định chi nhánh hiện tại từ MACN_MOI (chuyển đi đâu → hiện tại ở phía ngược lại)
    const serverHienTai = MACN_MOI === 'TANDINH' ? 'BENTHANH' : 'TANDINH';
    await execSPAdmin(serverHienTai, 'SP_ChuyenNhanVien', { MANV, MACN_MOI });
    res.redirect('/nhanvien?success=' + encodeURIComponent('Đã chuyển chi nhánh thành công'));
  } catch (err) {
    console.error('[SP_ChuyenNhanVien] LỖI:', err);
    res.redirect('/nhanvien?error=' + encodeURIComponent(err.message || JSON.stringify(err)));
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
