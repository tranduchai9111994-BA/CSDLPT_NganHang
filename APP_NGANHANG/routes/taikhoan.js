// routes/taikhoan.js
const express = require('express');
const router  = express.Router();
const { querySQL, execSP, execSPAdmin, querySP, getAdminPool, sql } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// Tiền tố SOTK theo chi nhánh — đảm bảo không trùng khóa khi đồng bộ liên site
const MACN_PREFIX = { BENTHANH: 'BT', TANDINH: 'TD' };

// KhachHang phân mảnh ngang → local chỉ có KH chi nhánh mình.
// Dùng admin pool + LINK1 để lấy KH cả 2 chi nhánh cho form mở TK.
async function getAllKhachHang(serverKey) {
  const pool = await getAdminPool(serverKey);
  const result = await pool.request().query(`
    SELECT RTRIM(CMND) AS CMND, RTRIM(HO)+' '+RTRIM(TEN) AS HoTen, RTRIM(MACN) AS MACN
    FROM KhachHang
    UNION ALL
    SELECT RTRIM(CMND), RTRIM(HO)+' '+RTRIM(TEN), RTRIM(MACN)
    FROM [LINK1].NGANHANG.dbo.KhachHang
    ORDER BY MACN, HoTen
  `);
  return result.recordset || [];
}

// Sinh số TK tự động: <prefix_chinhanh> + 7 chữ số (ví dụ BT0000001, TD0000001)
async function sinhSOTK(req, serverKey, macn) {
  const prefix = MACN_PREFIX[macn] || 'TK';
  const rows = await querySQL(req, serverKey, `
    SELECT TOP 1 SOTK FROM TaiKhoan WHERE SOTK LIKE @prefix ORDER BY SOTK DESC
  `, { prefix: prefix + '%' });
  if (rows.length === 0) return prefix + '0000001';
  const last = rows[0].SOTK.trim();
  const num  = parseInt(last.slice(prefix.length)) + 1;
  return prefix + String(num).padStart(7, '0');
}

// GET /taikhoan – Danh sách tài khoản
router.get('/', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    let sql;
    let params = {};
    if (user.NHOM === 'NganHang') {
      // sp_DanhSachTaiKhoan chạy trên TRACUU, gộp TaiKhoan từ cả 2 chi nhánh qua LINK1+LINK2
      // và JOIN KhachHang local (TRACUU replicate full KhachHang) — không cần fan-out ở Node
      const rows = await querySP(req, 'TRACUU', 'sp_DanhSachTaiKhoan', {});
      return res.render('taikhoan/list', { rows, error: req.query.error || null, success: req.query.success || null });
    } else if (user.NHOM === 'ChiNhanh') {
      // TaiKhoan nhân bản toàn vẹn → hiển thị tất cả, không filter theo MACN
      // KhachHang phân mảnh ngang → UNION local + LINK1 để có tên KH cả 2 chi nhánh
      // Dùng admin pool vì user ChiNhanh không có quyền query LINK1
      const pool = await getAdminPool(server);
      const result = await pool.request().query(`
        SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
               RTRIM(kh.HO)+' '+RTRIM(kh.TEN) AS HoTen,
               tk.SODU, RTRIM(tk.MACN) AS MACN,
               CONVERT(varchar,tk.NGAYMOTK,103) AS NGAYMOTK
        FROM TaiKhoan tk
        OUTER APPLY (
          SELECT TOP 1 HO, TEN FROM (
            SELECT HO, TEN FROM KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)
            UNION ALL
            SELECT HO, TEN FROM [LINK1].NGANHANG.dbo.KhachHang WHERE RTRIM(CMND)=RTRIM(tk.CMND)
          ) allKH
        ) kh
        ORDER BY tk.NGAYMOTK DESC
      `);
      const rows = result.recordset || [];
      return res.render('taikhoan/list', { rows, error: req.query.error || null, success: req.query.success || null });
    } else {
      // KhachHang: dùng SP để tránh raw SELECT trực tiếp (KhachHang không có GRANT SELECT trên TaiKhoan)
      const rows = await querySP(req, server, 'sp_TaiKhoanKhachHang', { CMND: user.MANV });
      return res.render('taikhoan/list', { rows, error: req.query.error || null, success: req.query.success || null });
    }
  } catch (err) {
    res.render('taikhoan/list', { rows: [], error: err.message, success: null });
  }
});

// GET /taikhoan/mo – Form mở tài khoản
router.get('/mo', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  if (user.NHOM !== 'ChiNhanh') {
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  try {
    const sotk = await sinhSOTK(req, server, user.MACN);
    const khRows = await getAllKhachHang(server);
    res.render('taikhoan/form', {
      sotk, khRows, macn: user.MACN, error: null
    });
  } catch (err) {
    res.render('taikhoan/form', { sotk: '', khRows: [], macn: user.MACN, error: err.message });
  }
});

// POST /taikhoan/mo – Thực hiện mở TK
// 2 FK trên TaiKhoan: FK_TaiKhoan_KhachHang (CMND) + FK_TaiKhoan_ChiNhanh (MACN).
// KhachHang + ChiNhanh đều phân mảnh ngang → cả 2 FK chỉ thỏa trên server có KH.
// Cross-branch: MACN = chi nhánh KH, INSERT trên server KH → TK replicate full sang.
router.post('/mo', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  if (user.NHOM !== 'ChiNhanh') {
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  let { SOTK, CMND, SODU, KH_MACN } = req.body;
  const khMacn = (KH_MACN || '').trim();
  const userMacn = (user.MACN || '').trim();
  const crossBranch = khMacn && khMacn !== userMacn;
  const MACN = crossBranch ? khMacn : userMacn;
  try {
    SOTK = await sinhSOTK(req, server, userMacn);
    const spParams = { SOTK, CMND, SODU: parseFloat(SODU) || 0, MACN };

    if (crossBranch) {
      await execSPAdmin(khMacn, 'sp_MoTaiKhoan', spParams);
    } else {
      await execSP(req, server, 'sp_MoTaiKhoan', spParams);
    }
    res.redirect('/taikhoan?success=Mở tài khoản thành công');
  } catch (err) {
    const khRows = await getAllKhachHang(server);
    res.render('taikhoan/form', { sotk: SOTK, khRows, macn: user.MACN, error: err.message });
  }
});

// POST /taikhoan/dong – Đóng (xóa) tài khoản
router.post('/dong', async (req, res) => {
  const server = getServer(req);
  const user = req.session.user;
  if (user.NHOM !== 'ChiNhanh') {
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
