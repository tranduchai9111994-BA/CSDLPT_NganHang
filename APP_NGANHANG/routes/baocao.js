// routes/baocao.js
const express = require('express');
const router  = express.Router();
const { querySQL, querySP } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// ============================================================
// SAO KÊ GIAO DỊCH
// ============================================================

// GET /baocao/saoke
router.get('/saoke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    // KhachHang: chỉ thấy TK của mình
    let tkRows;
    if (user.NHOM === 'KhachHang') {
      tkRows = await querySQL(req, server, `
        SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd
      `, { cmnd: user.MANV });
    } else {
      tkRows = await querySQL(req, server, `
        SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK
      `);
    }
    res.render('baocao/saoke', { tkRows, rows: null, sodu_dau: 0, sodu_cuoi: 0, error: null, query: {} });
  } catch (err) {
    res.render('baocao/saoke', { tkRows: [], rows: null, sodu_dau: 0, sodu_cuoi: 0, error: err.message, query: {} });
  }
});

// POST /baocao/saoke – Thực hiện sao kê
router.post('/saoke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { SOTK, TUNGAY } = req.body;
  const DENNGAY_raw = req.body.DENNGAY || '';
  // Đặt DENNGAY thành cuối ngày để bao gồm tất cả GD trong ngày đó
  const DENNGAY = DENNGAY_raw ? DENNGAY_raw + ' 23:59:59' : null;

  // Kiểm tra KhachHang chỉ xem TK của mình
  if (SOTK && user.NHOM === 'KhachHang') {
    const own = await querySQL(req, server, `
      SELECT COUNT(*) AS cnt FROM TaiKhoan
      WHERE RTRIM(SOTK)=@sotk AND RTRIM(CMND)=@cmnd
    `, { sotk: SOTK, cmnd: user.MANV });
    if (own[0].cnt === 0) {
      return res.redirect('/baocao/saoke?error=Bạn không có quyền xem tài khoản này.');
    }
  }

  try {
    let rows = [];

    if (SOTK) {
      // Có chọn TK: dùng SP để có số dư đầu/cuối kỳ chính xác
      const tkInfo = await querySQL(req, server, `SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK)=@sotk`, { sotk: SOTK });
      const sodu_hientai = tkInfo.length > 0 ? tkInfo[0].SODU : 0;

      const allGD = await querySP(req, server, 'SP_SaoKeTaiKhoan', { SOTK, TUNGAY, DENNGAY });

      let sodu_dau = sodu_hientai, sodu_cuoi = sodu_hientai;
      if (allGD.length > 0) {
        const firstGD = allGD[0];
        sodu_dau = firstGD.SODU_LUYKE - (['GT','NT'].includes(firstGD.LOAIGD) ? firstGD.SOTIEN : -firstGD.SOTIEN);
        sodu_cuoi = allGD[allGD.length - 1].SODU_LUYKE;
      }

      rows = allGD.map(gd => {
        const isVao = ['GT','NT'].includes(gd.LOAIGD);
        return {
          ...gd,
          SOTK: SOTK,
          NGAYGD: new Date(gd.NGAYGD).toLocaleDateString('vi-VN'),
          LoaiGD: gd.LOAIGD, SoTien: gd.SOTIEN,
          SoDuDau: gd.SODU_LUYKE - (isVao ? gd.SOTIEN : -gd.SOTIEN),
          SoDuSau: gd.SODU_LUYKE, TienVao: isVao ? gd.SOTIEN : 0
        };
      });

      const tkRows = user.NHOM === 'KhachHang'
        ? await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd`, { cmnd: user.MANV })
        : await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK`);

      return res.render('baocao/saoke', {
        tkRows, rows, sodu_dau, sodu_cuoi, error: null,
        showSodu: true, query: { SOTK, TUNGAY, DENNGAY: DENNGAY_raw }
      });
    }

    // Không chọn TK: query trực tiếp tất cả GD theo quyền
    let whereClause = `NGAYGD BETWEEN @tungay AND @denngay`;
    let params = { tungay: TUNGAY, denngay: DENNGAY };

    if (user.NHOM === 'KhachHang') {
      whereClause += ` AND SOTK IN (SELECT SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd)`;
      params.cmnd = user.MANV;
    } else if (user.NHOM === 'ChiNhanh') {
      whereClause += ` AND SOTK IN (SELECT SOTK FROM TaiKhoan WHERE RTRIM(MACN)=@macn)`;
      params.macn = user.MACN;
    }

    const gdGui = await querySQL(req, server, `
      SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
      FROM GD_GOIRUT g WHERE ${whereClause}
    `, params);
    const gdCT_chuyen = await querySQL(req, server, `
      SELECT RTRIM(SOTK_CHUYEN) AS SOTK, NGAYGD, 'CT' AS LOAIGD, SOTIEN
      FROM GD_CHUYENTIEN WHERE ${whereClause.replace(/SOTK IN/g, 'SOTK_CHUYEN IN')}
    `, params);
    const gdCT_nhan = await querySQL(req, server, `
      SELECT RTRIM(SOTK_NHAN) AS SOTK, NGAYGD, 'NT' AS LOAIGD, SOTIEN
      FROM GD_CHUYENTIEN WHERE ${whereClause.replace(/SOTK IN/g, 'SOTK_NHAN IN')}
    `, params);

    const allRaw = [...gdGui, ...gdCT_chuyen, ...gdCT_nhan]
      .sort((a, b) => new Date(a.NGAYGD) - new Date(b.NGAYGD));

    rows = allRaw.map(gd => {
      const isVao = ['GT','NT'].includes(gd.LOAIGD);
      return {
        ...gd,
        NGAYGD: new Date(gd.NGAYGD).toLocaleDateString('vi-VN'),
        LoaiGD: gd.LOAIGD, SoTien: gd.SOTIEN,
        SoDuDau: null, SoDuSau: null, TienVao: isVao ? gd.SOTIEN : 0
      };
    });

    const tkRows = user.NHOM === 'KhachHang'
      ? await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd`, { cmnd: user.MANV })
      : await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK`);

    res.render('baocao/saoke', {
      tkRows, rows, sodu_dau: null, sodu_cuoi: null, error: null,
      showSodu: false, query: { SOTK: '', TUNGAY, DENNGAY: DENNGAY_raw }
    });
  } catch (err) {
    res.render('baocao/saoke', {
      tkRows: [], rows: null, sodu_dau: 0, sodu_cuoi: 0,
      showSodu: false, error: err.message, query: { SOTK, TUNGAY, DENNGAY: DENNGAY_raw }
    });
  }
});

// ============================================================
// LIỆT KÊ KHÁCH HÀNG VÀ TÀI KHOẢN
// ============================================================

// GET /baocao/lietke
router.get('/lietke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  const { loai, macn, tungay, denngay } = req.query;

  try {
    let rows = [];
    let title = '';

    if (loai === 'kh') {
      title = 'Danh sách khách hàng';
      if (user.NHOM === 'NganHang' && !macn) {
        // Tất cả chi nhánh
        rows = await querySQL(req, 'TRACUU', `
          SELECT RTRIM(CMND) AS CMND,
                 RTRIM(HO)+' '+RTRIM(TEN) AS HoTen,
                 RTRIM(MACN) AS MACN, SODT
          FROM KhachHang ORDER BY MACN, HO, TEN
        `);
      } else {
        const filterMACN = macn || user.MACN;
        rows = await querySQL(req, server, `
          SELECT RTRIM(CMND) AS CMND,
                 RTRIM(HO)+' '+RTRIM(TEN) AS HoTen,
                 RTRIM(MACN) AS MACN, SODT
          FROM KhachHang WHERE RTRIM(MACN)=@macn ORDER BY HO, TEN
        `, { macn: filterMACN });
      }
    } else if (loai === 'tk') {
      title = 'Danh sách tài khoản mở';
      const sqlParams = {
        MACN: null,
        TUNGAY: tungay || null,
        DENNGAY: denngay || null
      };

      let executeServer = server;
      if (user.NHOM === 'NganHang') {
        executeServer = 'TRACUU';
        if (macn) sqlParams.MACN = macn;
      } else if (user.NHOM === 'ChiNhanh') {
        sqlParams.MACN = user.MACN;
      }

      rows = await querySP(req, executeServer, 'sp_LietKeTaiKhoanTheoNgay', sqlParams);
    }

    res.render('baocao/lietke', {
      rows, title, loai: loai || '', error: null,
      query: { macn, tungay, denngay }
    });
  } catch (err) {
    res.render('baocao/lietke', {
      rows: [], title: '', loai: loai || '', error: err.message,
      query: {}
    });
  }
});

module.exports = router;
