// routes/khachhang.js
const express = require('express');
const router = express.Router();
const { querySQL, execSP, getAdminPool, sql } = require('../db');

function getServer(req) {
  return req.session.user.SERVER || 'BENTHANH';
}

function requireChiNhanh(req, res, next) {
  if (req.session.user?.NHOM !== 'ChiNhanh') {
    return res.status(403).render('error', { message: 'Không có quyền.', layout: false });
  }
  next();
}

// GET /khachhang – Danh sách khách hàng
router.get('/', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    let rows;
    if (user.NHOM === 'NganHang') {
      // NganHang xem tất cả qua TRACUU hoặc UNION
      rows = await querySQL(req, 'TRACUU', `
        SELECT RTRIM(CMND) AS CMND,
               RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
               RTRIM(MACN) AS MACN, SODT, DIACHI
        FROM KhachHang
        ORDER BY MACN, HO, TEN
      `);
    } else {
      // ChiNhanh chỉ xem của chi nhánh mình
      rows = await querySQL(req, server, `
        SELECT RTRIM(CMND) AS CMND,
               RTRIM(HO) + ' ' + RTRIM(TEN) AS HoTen,
               RTRIM(MACN) AS MACN, SODT, DIACHI
        FROM KhachHang
        WHERE RTRIM(MACN) = @macn
        ORDER BY HO, TEN
      `, { macn: user.MACN });
    }
    res.render('khachhang/list', { rows, error: req.query.error || null, success: req.query.success || null });
  } catch (err) {
    res.render('khachhang/list', { rows: [], error: err.message, success: null });
  }
});

// GET /khachhang/them – Form thêm mới
router.get('/them', requireChiNhanh, (req, res) => {
  const user = req.session.user;
  res.render('khachhang/form', {
    kh: null, action: 'them', error: null,
    macn: user.MACN
  });
});

// POST /khachhang/them – Thực hiện thêm
router.post('/them', requireChiNhanh, async (req, res) => {
  const user   = req.session.user;
  const server = getServer(req);
  const { CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT, MACPIN } = req.body;
  const MACN = user.MACN || req.body.MACN;
  const password = MACPIN || CMND; // Mặc định pass là CMND nếu không nhập MACPIN

  try {
    // Gọi SP thêm KH (SP đã viết trong SQL Server)
    await execSP(req, server, 'sp_ThemKhachHang', {
      CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT, MACN
    });

    // Tạo Login SQL trên tất cả server bằng adminPool
    const safeCMND = CMND.replace(/]/g, ']]');
    const safePass = password.replace(/'/g, "''");
    const serverKeys = ['BENTHANH', 'TANDINH', 'TRACUU'];

    for (const srvKey of serverKeys) {
      try {
        const pool = await getAdminPool(srvKey);

        const loginExists = await pool.request()
          .input('LN', sql.VarChar, CMND)
          .query(`SELECT 1 FROM sys.server_principals WHERE name = @LN`);
        if (loginExists.recordset.length === 0) {
          await pool.request().query(
            `CREATE LOGIN [${safeCMND}] WITH PASSWORD = '${safePass}', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF`
          );
        }

        const userExists = await pool.request()
          .input('UN', sql.VarChar, CMND)
          .query(`SELECT 1 FROM sys.database_principals WHERE name = @UN`);
        if (userExists.recordset.length === 0) {
          await pool.request().query(`CREATE USER [${safeCMND}] FOR LOGIN [${safeCMND}]`);
        }

        await pool.request().query(`EXEC sp_addrolemember 'KhachHang', [${safeCMND}]`);

        const qtlExists = await pool.request()
          .input('LN2', sql.VarChar, CMND)
          .query(`SELECT 1 FROM dbo.QuanTriLogin WHERE LoginName = @LN2`);
        if (qtlExists.recordset.length === 0) {
          await pool.request()
            .input('LoginName', sql.VarChar, CMND)
            .input('MatKhau', sql.VarChar, password)
            .input('MaThamChieu', sql.VarChar, CMND)
            .query(`INSERT INTO dbo.QuanTriLogin (LoginName, MatKhauHienTai, LoaiTaiKhoan, MaThamChieu, NhomQuyen, NgayTao)
                    VALUES (@LoginName, @MatKhau, 'KhachHang', @MaThamChieu, 'KhachHang', GETDATE())`);
        }
      } catch (e) {
        console.error(`[ThemKH-Login] ${srvKey}: ${e.message}`);
      }
    }

    res.redirect('/khachhang?success=Thêm khách hàng và tạo tài khoản thành công');
  } catch (err) {
    res.render('khachhang/form', {
      kh: req.body, action: 'them',
      error: err.message, macn: MACN
    });
  }
});

// GET /khachhang/sua/:cmnd – Form sửa
router.get('/sua/:cmnd', requireChiNhanh, async (req, res) => {
  const server = getServer(req);
  const { cmnd } = req.params;
  try {
    const rows = await querySQL(req, server, `
      SELECT * FROM KhachHang WHERE RTRIM(CMND) = @cmnd
    `, { cmnd });
    if (rows.length === 0) return res.redirect('/khachhang');
    const kh = rows[0];
    // Format date cho input type=date
    kh.NGAYCAP = kh.NGAYCAP ? kh.NGAYCAP.toISOString().split('T')[0] : '';
    res.render('khachhang/form', {
      kh, action: 'sua', error: null,
      macn: req.session.user.MACN
    });
  } catch (err) {
    res.redirect('/khachhang');
  }
});

// POST /khachhang/sua – Thực hiện sửa
router.post('/sua', requireChiNhanh, async (req, res) => {
  const server = getServer(req);
  const { CMND, HO, TEN, DIACHI, PHAI, NGAYCAP, SODT } = req.body;
  try {
    await querySQL(req, server, `
      UPDATE KhachHang
      SET HO=@ho, TEN=@ten, DIACHI=@diachi, PHAI=@phai, NGAYCAP=@ngaycap, SODT=@sodt
      WHERE RTRIM(CMND) = @cmnd
    `, { ho: HO, ten: TEN, diachi: DIACHI, phai: PHAI, ngaycap: NGAYCAP, sodt: SODT, cmnd: CMND });
    res.redirect('/khachhang?success=Cập nhật thành công');
  } catch (err) {
    res.render('khachhang/form', {
      kh: req.body, action: 'sua',
      error: err.message, macn: req.session.user.MACN
    });
  }
});

// POST /khachhang/xoa – Xóa mềm (đặt flag nếu có, hoặc xóa thật nếu chưa có GD)
router.post('/xoa', requireChiNhanh, async (req, res) => {
  const server = getServer(req);
  const { CMND } = req.body;
  try {
    // Kiểm tra KH có TK không
    const tkRows = await querySQL(req, server, `
      SELECT COUNT(*) AS cnt FROM TaiKhoan WHERE RTRIM(CMND) = @cmnd
    `, { cmnd: CMND });
    if (tkRows[0].cnt > 0) {
      return res.redirect('/khachhang?error=Không thể xóa: KH đang có tài khoản');
    }
    await querySQL(req, server, `DELETE FROM KhachHang WHERE RTRIM(CMND) = @cmnd`, { cmnd: CMND });
    res.redirect('/khachhang?success=Đã xóa khách hàng');
  } catch (err) {
    res.redirect('/khachhang?error=' + err.message);
  }
});

// GET /khachhang/:cmnd/taikhoan – API phục vụ SubForm
router.get('/:cmnd/taikhoan', async (req, res) => {
  const server = getServer(req);
  try {
    const rows = await querySQL(req, server, `
      SELECT RTRIM(SOTK) AS SOTK, SODU, RTRIM(MACN) AS MACN, 
             CONVERT(varchar, NGAYMOTK, 103) AS NGAYMOTK 
      FROM TaiKhoan 
      WHERE RTRIM(CMND) = @cmnd
      ORDER BY NGAYMOTK DESC
    `, { cmnd: req.params.cmnd });
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
