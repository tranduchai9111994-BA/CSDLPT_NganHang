// routes/taikhoan.js
const express = require('express');
const router  = express.Router();
const { querySQL, queryAdminSQL, execSP, execSPAdmin, querySP, getAdminPool, sql } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// KhachHang phân mảnh ngang → local chỉ có KH chi nhánh mình.
// Dùng admin pool + LINK1 để lấy KH cả 2 chi nhánh cho form mở TK.
async function getAllKhachHang(serverKey) {
  return await queryAdminSQL(serverKey, `
    SELECT RTRIM(CMND) AS CMND, RTRIM(HO)+' '+RTRIM(TEN) AS HoTen, RTRIM(MACN) AS MACN
    FROM KhachHang
    UNION ALL
    SELECT RTRIM(CMND), RTRIM(HO)+' '+RTRIM(TEN), RTRIM(MACN)
    FROM [LINK1].NGANHANG.dbo.KhachHang
    ORDER BY MACN, HoTen
  `);
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
      const rows = await queryAdminSQL(server, `
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
// SOTK KHÔNG còn được sinh ở tầng app — SP sp_MoTaiKhoan tự sinh atomic khi INSERT.
// Form chỉ hiển thị placeholder "(Sẽ tự động sinh khi lưu)" — server bỏ qua giá trị SOTK trong body.
router.get('/mo', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  if (user.NHOM !== 'ChiNhanh') {
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  try {
    const khRows = await getAllKhachHang(server);
    res.render('taikhoan/form', {
      sotk: '(Sẽ tự động sinh khi lưu)', khRows, macn: user.MACN, error: null
    });
  } catch (err) {
    res.render('taikhoan/form', { sotk: '(Sẽ tự động sinh khi lưu)', khRows: [], macn: user.MACN, error: err.message });
  }
});

// POST /taikhoan/mo – Thực hiện mở TK
// SP sp_MoTaiKhoan tự sinh SOTK trong scope distributed tran (fix race condition).
// Prefix theo @MACN (chi nhánh sở hữu TK): BENTHANH→BT, TANDINH→TD.
// Cross-branch: MACN = chi nhánh KH → SP chạy trên server đó (FK_KhachHang thỏa local).
router.post('/mo', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  if (user.NHOM !== 'ChiNhanh') {
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  const { CMND, SODU, KH_MACN } = req.body;
  const khMacn = (KH_MACN || '').trim();
  const userMacn = (user.MACN || '').trim();
  const crossBranch = khMacn && khMacn !== userMacn;
  const MACN = crossBranch ? khMacn : userMacn;
  try {
    const spParams = { CMND, SODU: parseFloat(SODU) || 0, MACN };
    // SP tự sinh SOTK trong distributed tran và SELECT trả về ở cuối.
    // Chạy trên server sở hữu TK (server chi nhánh KH khi cross-branch, server NV khi cùng CN).
    const targetServer = crossBranch ? khMacn : userMacn;
    const output = await execSPAdmin(targetServer, 'sp_MoTaiKhoan', spParams);

    // Parse SOTK từ output text của sqlcmd. SOTK có format 'BTxxxxxxx' hoặc 'TDxxxxxxx'.
    const sotkMatch = String(output).match(/\b(?:BT|TD)\d{7}\b/);
    const newSOTK = sotkMatch ? sotkMatch[0] : null;

    const msg = newSOTK
      ? `Mở tài khoản thành công. Số tài khoản: ${newSOTK}`
      : 'Mở tài khoản thành công';
    res.redirect('/taikhoan?success=' + encodeURIComponent(msg));
  } catch (err) {
    const khRows = await getAllKhachHang(server);
    res.render('taikhoan/form', { sotk: '(Sẽ tự động sinh khi lưu)', khRows, macn: user.MACN, error: err.message });
  }
});

// POST /taikhoan/dong – Đóng (xóa) tài khoản.
// Toàn bộ guard nghiệp vụ (SODU, GD_GOIRUT, GD_CHUYENTIEN, same-branch)
// đã được đẩy vào SP_DongTaiKhoan (RF-B: defense-in-depth SQL-side).
// Route chỉ check quyền + forward gọi SP.
router.post('/dong', async (req, res) => {
  const server = getServer(req);
  const user = req.session.user;
  if (user.NHOM !== 'ChiNhanh') {
    return res.redirect('/taikhoan?error=Không có quyền');
  }
  const { SOTK } = req.body;
  try {
    // execSPAdmin vì SP query LINK1 để đếm GD_GOIRUT/GD_CHUYENTIEN ở site kia
    // (guard G4/G5), pool user ChiNhanh thường không có quyền select LINK.
    await execSPAdmin(server, 'SP_DongTaiKhoan', {
      SOTK: SOTK,
      MANV: user.MANV
    });
    res.redirect('/taikhoan?success=Đã đóng tài khoản ' + SOTK);
  } catch (err) {
    res.redirect('/taikhoan?error=' + encodeURIComponent(err.message));
  }
});

module.exports = router;
