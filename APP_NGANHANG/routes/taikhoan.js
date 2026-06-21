// routes/taikhoan.js
const express = require('express');
const router  = express.Router();
const { querySQL, execSP } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// Sinh số TK tự động: TK + 7 chữ số
async function sinhSOTK(req, serverKey) {
  const rows = await querySQL(req, serverKey, `
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
    const rows = await querySQL(req, server, sql, params);
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
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  try {
    const sotk = await sinhSOTK(req, server);
    // Lấy danh sách KH để chọn
    const khRows = await querySQL(req, server, `
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
  if (!['NganHang', 'ChiNhanh'].includes(user.NHOM)) {
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  let { SOTK, CMND, SODU, MACN } = req.body;
  try {
    if (!SOTK) {
      SOTK = await sinhSOTK(req, server);
    }
    await execSP(req, server, 'sp_MoTaiKhoan', {
      SOTK, CMND, SODU: parseFloat(SODU) || 0, MACN
    });
    res.redirect('/taikhoan?success=Mở tài khoản thành công');
  } catch (err) {
    const khRows = await querySQL(req, server, `
      SELECT RTRIM(CMND) AS CMND, RTRIM(HO)+' '+RTRIM(TEN) AS HoTen
      FROM KhachHang WHERE RTRIM(MACN)=@macn ORDER BY HO,TEN
    `, { macn: user.MACN });
    res.render('taikhoan/form', { sotk: SOTK, khRows, macn: MACN, error: err.message });
  }
});

// POST /taikhoan/dong – Đóng (xóa) tài khoản
router.post('/dong', async (req, res) => {
  const server = getServer(req);
  const user = req.session.user;
  if (!['NganHang', 'ChiNhanh'].includes(user.NHOM)) {
    return res.redirect('/taikhoan?error=Không có quyền');
  }
  const { SOTK } = req.body;
  try {
    // Kiểm tra số dư
    const tkRows = await querySQL(req, server, `
      SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK) = @sotk
    `, { sotk: SOTK });
    if (tkRows.length === 0) return res.redirect('/taikhoan?error=Tài khoản không tồn tại');
    if (Number(tkRows[0].SODU) !== 0) {
      return res.redirect('/taikhoan?error=Không thể đóng tài khoản có số dư khác 0. Vui lòng rút hết tiền trước.');
    }

    // Kiểm tra giao dịch
    const gdRows = await querySQL(req, server, `
      SELECT COUNT(*) AS cnt FROM GD_GOIRUT WHERE RTRIM(SOTK) = @sotk
    `, { sotk: SOTK });
    const ctRows = await querySQL(req, server, `
      SELECT COUNT(*) AS cnt FROM GD_CHUYENTIEN WHERE RTRIM(SOTK_CHUYEN) = @sotk OR RTRIM(SOTK_NHAN) = @sotk
    `, { sotk: SOTK });

    if (gdRows[0].cnt > 0 || ctRows[0].cnt > 0) {
      return res.redirect('/taikhoan?error=Không thể đóng tài khoản đã có giao dịch.');
    }

    await querySQL(req, server, `DELETE FROM TaiKhoan WHERE RTRIM(SOTK) = @sotk`, { sotk: SOTK });
    res.redirect('/taikhoan?success=Đã đóng tài khoản ' + SOTK);
  } catch (err) {
    res.redirect('/taikhoan?error=' + encodeURIComponent(err.message));
  }
});

module.exports = router;
