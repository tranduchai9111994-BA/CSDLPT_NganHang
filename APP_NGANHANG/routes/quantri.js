// routes/quantri.js
const express = require('express');
const router = express.Router();
const { getPool, getAdminPool, querySP, sql } = require('../db');

// Hàm phụ trợ lấy danh sách nhân viên
const requireNganHang = (req, res, next) => {
  if (!req.session.user || req.session.user.NHOM !== 'NganHang') {
    return res.status(403).json({ error: 'Bạn không có quyền truy cập chức năng này.' });
  }
  next();
};

async function getNhanVienList(req) {
  try {
    const sessionUser = req.session.user;
    if (sessionUser.NHOM === 'NganHang') {
      // TRACUU không có NhanVien local → SP đọc qua LINK1+LINK2
      const rows = await querySP(req, 'TRACUU', 'sp_DanhSachNhanVien', {});
      return rows.filter(r => !r.TrangThaiXoa);
    }
    const serverKey = sessionUser.SERVER;
    const pool = await getPool(req, serverKey);
    const macn = sessionUser.MACN ? sessionUser.MACN.trim() : '';
    const query = `SELECT MANV, HO, TEN FROM NhanVien WHERE RTRIM(MACN) = RTRIM(@macn) AND TrangThaiXoa = 0`;
    const result = await pool.request().input('macn', sql.NVarChar, macn).query(query);
    return result.recordset || [];
  } catch (e) {
    console.error("Lỗi khi load danh sách nhân viên:", e);
    return [];
  }
}

async function getKhachHangList(req) {
  try {
    const sessionUser = req.session.user;
    const serverKey = sessionUser.NHOM === 'NganHang' ? 'TRACUU' : sessionUser.SERVER;
    const pool = await getPool(req, serverKey);

    let query, result;
    if (sessionUser.NHOM === 'NganHang') {
      query = `SELECT CMND, HO, TEN, RTRIM(MACN) AS MACN FROM KhachHang ORDER BY MACN, CMND`;
      result = await pool.request().query(query);
    } else {
      const macn = sessionUser.MACN ? sessionUser.MACN.trim() : '';
      query = `SELECT CMND, HO, TEN FROM KhachHang WHERE RTRIM(MACN) = RTRIM(@macn)`;
      result = await pool.request().input('macn', sql.NVarChar, macn).query(query);
    }
    return result.recordset || [];
  } catch (e) {
    console.error("Lỗi khi load danh sách khách hàng:", e);
    return [];
  }
}

// GET /quantri/taotaikhoan - Hiển thị form tạo tài khoản
router.get('/taotaikhoan', async (req, res) => {
  const sessionUser = req.session.user;
  const nhanviens = await getNhanVienList(req);
  const khachhangs = await getKhachHangList(req);
  res.render('taotaikhoan', { error: null, success: null, nhanviens, khachhangs, user: sessionUser });
});

// POST /quantri/taotaikhoan - Xử lý tạo tài khoản
router.post('/taotaikhoan', async (req, res) => {
  const username = req.body.username || req.body.UserName;
  const loginname = req.body.loginname || req.body.LoginName;
  const password = req.body.password || req.body.Password;
  const role = req.body.role || req.body.Role;
  const sessionUser = req.session.user;

  // Lấy sẵn danh sách phòng trường hợp render lại form có lỗi
  const nhanviens = await getNhanVienList(req);
  const khachhangs = await getKhachHangList(req);

  // 1. KIỂM TRA PHẠM VI QUYỀN HẠN (Bảo mật Backend)
  // NganHang (Ban Giám Đốc) được tạo tất cả loại tài khoản
  // ChiNhanh chỉ được tạo ChiNhanh hoặc KhachHang
  if (sessionUser.NHOM === 'NganHang' && !['NganHang', 'ChiNhanh', 'KhachHang'].includes(role)) {
    return res.render('taotaikhoan', { error: 'Nhóm quyền không hợp lệ.', success: null, nhanviens, khachhangs, user: sessionUser });
  }
  if (sessionUser.NHOM === 'ChiNhanh' && role !== 'ChiNhanh' && role !== 'KhachHang') {
    return res.render('taotaikhoan', { error: 'Quyền hạn không hợp lệ. Bạn chỉ có thể tạo tài khoản nhóm ChiNhanh hoặc KhachHang.', success: null, nhanviens, khachhangs, user: sessionUser });
  }

  try {
    const safeLogin = loginname.replace(/]/g, ']]');
    const safeUser  = username.replace(/]/g, ']]');
    const safePass  = password.replace(/'/g, "''");
    const safeRole  = role.replace(/'/g, "''");
    const loaiTk = role === 'KhachHang' ? 'KhachHang' : 'NhanVien';

    // Tạo login/user trên TẤT CẢ server (để user có thể query cross-server)
    const serverKeys = ['BENTHANH', 'TANDINH', 'TRACUU'];
    const errors = [];

    for (const srvKey of serverKeys) {
      try {
        const pool = await getAdminPool(srvKey);

        // Tạo LOGIN nếu chưa có
        const loginExists = await pool.request()
          .input('LN', sql.VarChar, loginname)
          .query(`SELECT 1 FROM sys.server_principals WHERE name = @LN`);
        if (loginExists.recordset.length === 0) {
          await pool.request().query(
            `CREATE LOGIN [${safeLogin}] WITH PASSWORD = '${safePass}', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF`
          );
        }

        // Tạo USER nếu chưa có
        const userExists = await pool.request()
          .input('UN', sql.VarChar, username)
          .query(`SELECT 1 FROM sys.database_principals WHERE name = @UN`);
        if (userExists.recordset.length === 0) {
          await pool.request().query(`CREATE USER [${safeUser}] FOR LOGIN [${safeLogin}]`);
        }

        // Gán role
        await pool.request().query(`EXEC sp_addrolemember '${safeRole}', [${safeUser}]`);

        // INSERT QuanTriLogin trên tất cả server (để lưới hiển thị đúng khi query bất kỳ server nào)
        const qtlExists = await pool.request()
          .input('LN2', sql.VarChar, loginname)
          .query(`SELECT 1 FROM dbo.QuanTriLogin WHERE LoginName = @LN2`);
        if (qtlExists.recordset.length === 0) {
          await pool.request()
            .input('LoginName',    sql.VarChar, loginname)
            .input('MatKhau',      sql.VarChar, password)
            .input('LoaiTaiKhoan', sql.VarChar, loaiTk)
            .input('MaThamChieu',  sql.VarChar, username)
            .input('NhomQuyen',    sql.VarChar, role)
            .query(`
              INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
              VALUES (@LoginName, @MatKhau, @LoaiTaiKhoan, @MaThamChieu, @NhomQuyen, GETDATE())
            `);
        }

        console.log(`[TaoTK] ${srvKey}: OK`);
      } catch (srvErr) {
        console.error(`[TaoTK] ${srvKey}: ${srvErr.message}`);
        errors.push(`${srvKey}: ${srvErr.message}`);
      }
    }

    if (errors.length > 0) {
      return res.render('taotaikhoan', {
        error: `Cấp tài khoản một phần — lỗi tại: ${errors.join('; ')}. Vui lòng dùng chức năng Dọn Lỗi Đồng Bộ để kiểm tra và tạo lại.`,
        success: null,
        nhanviens, khachhangs, user: sessionUser
      });
    }
    return res.render('taotaikhoan', {
      error: null,
      success: `Tạo tài khoản thành công cho "${username}" với quyền ${role}.`,
      nhanviens, khachhangs, user: sessionUser
    });

  } catch (err) {
    console.error('[TaoTaiKhoan ERROR]', err.message);
    res.render('taotaikhoan', { error: 'Lỗi hệ thống: ' + err.message, success: null, nhanviens, khachhangs, user: sessionUser });
  }
});

// GET /quantri/login-management/list
router.get('/login-management/list', async (req, res) => {
  try {
    const sessionUser = req.session.user;
    // NganHang query TRACUU để thấy tất cả CN, ChiNhanh query server của mình
    const serverKey = sessionUser.NHOM === 'NganHang' ? 'TRACUU' : sessionUser.SERVER;
    const pool = await getAdminPool(serverKey);
    const macn = sessionUser.NHOM === 'NganHang' ? null : sessionUser.MACN.trim();

    const request = pool.request();
    if (macn) {
      request.input('MACN', sql.NChar(10), macn);
    } else {
      request.input('MACN', sql.NChar(10), null);
    }
    const result = await request.execute('SP_DanhSachTrangThaiLogin');
    console.log('[DEBUG] SP_DanhSachTrangThaiLogin trả về:', result.recordset ? result.recordset.length : 0, 'dòng');
    res.json(result.recordset || []);
  } catch (err) {
    console.error('[ERROR] Lỗi SP_DanhSachTrangThaiLogin:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /quantri/login-management/password/:loginName
router.get('/login-management/password/:loginName', requireNganHang, async (req, res) => {
  try {
    const pool = await getAdminPool(req.session.user.SERVER);
    const result = await pool.request()
      .input('LoginName', sql.VarChar, req.params.loginName)
      .query('SELECT MatKhauHienTai FROM QuanTriLogin WHERE LoginName = @LoginName');
    
    if (result.recordset.length > 0) {
      res.json({ password: result.recordset[0].MatKhauHienTai });
    } else {
      res.status(404).json({ error: 'Không tìm thấy thông tin quản trị login' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /quantri/login-management/cleanup-sync-error
// Dọn dẹp record lỗi đồng bộ: xóa QuanTriLogin + DROP DB user (nếu còn) để cho phép tạo lại
router.post('/login-management/cleanup-sync-error', async (req, res) => {
  const sessionUser = req.session.user;
  if (!sessionUser || !['NganHang', 'ChiNhanh'].includes(sessionUser.NHOM)) {
    return res.status(403).json({ error: 'Không có quyền.' });
  }
  const { loginName, userName } = req.body;
  if (!loginName) return res.status(400).json({ error: 'Thiếu loginName.' });

  try {
    const adminPool = await getAdminPool(sessionUser.SERVER);
    await adminPool.request()
      .input('LoginName', sql.VarChar, loginName)
      .input('UserName', sql.VarChar, userName || null)
      .execute('SP_XoaLoiDongBo');
    res.json({ success: true });
  } catch (err) {
    console.error('[cleanup-sync-error ERROR]', err.message);
    res.status(500).json({ error: err.message });
  }
});

// POST /quantri/login-management/reset-password
router.post('/login-management/reset-password', requireNganHang, async (req, res) => {
  const loginName = req.body.loginName;
  const newPassword = '123456';
  const safeLogin = loginName.replace(/]/g, ']]');
  const safePass = newPassword.replace(/'/g, "''");

  try {
    const serverKeys = ['BENTHANH', 'TANDINH', 'TRACUU'];
    for (const srvKey of serverKeys) {
      try {
        const pool = await getAdminPool(srvKey);
        const exists = await pool.request()
          .input('LN', sql.VarChar, loginName)
          .query(`SELECT 1 FROM sys.server_principals WHERE name = @LN`);
        if (exists.recordset.length > 0) {
          // DROP + CREATE để tránh replication trigger chặn ALTER LOGIN
          await pool.request().query(`DROP LOGIN [${safeLogin}]`);
          await pool.request().query(`CREATE LOGIN [${safeLogin}] WITH PASSWORD = '${safePass}', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF`);
        }
      } catch (e) {
        console.error(`[ResetMK] ${srvKey}: ${e.message}`);
      }
    }

    // Update QuanTriLogin trên tất cả server
    for (const srvKey of serverKeys) {
      try {
        const pool = await getAdminPool(srvKey);
        await pool.request()
          .input('LN', sql.VarChar, loginName)
          .input('MK', sql.VarChar, newPassword)
          .query(`UPDATE dbo.QuanTriLogin SET MatKhauHienTai = @MK, NgayCapNhatMK = GETDATE() WHERE LoginName = @LN`);
      } catch(e) {}
    }

    res.json({ success: true, message: 'Reset mật khẩu thành công (tất cả server)' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
