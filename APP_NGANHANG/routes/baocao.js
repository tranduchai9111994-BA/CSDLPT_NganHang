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
  const { SOTK, TUNGAY, DENNGAY } = req.body;

  // Kiểm tra KhachHang chỉ xem TK của mình
  if (user.NHOM === 'KhachHang') {
    const own = await querySQL(req, server, `
      SELECT COUNT(*) AS cnt FROM TaiKhoan
      WHERE RTRIM(SOTK)=@sotk AND RTRIM(CMND)=@cmnd
    `, { sotk: SOTK, cmnd: user.MANV });
    if (own[0].cnt === 0) {
      return res.redirect('/baocao/saoke?error=Bạn không có quyền xem tài khoản này.');
    }
  }

  try {
    // Lấy số dư hiện tại
    const tkInfo = await querySQL(req, server, `
      SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK)=@sotk
    `, { sotk: SOTK });
    const sodu_hientai = tkInfo.length > 0 ? tkInfo[0].SODU : 0;

    // Gọi trực tiếp SP từ CSDL
    const allGD = await querySP(req, server, 'SP_SaoKeTaiKhoan', {
      SOTK: SOTK,
      TUNGAY: TUNGAY,
      DENNGAY: DENNGAY
    });

    let sodu_dau = sodu_hientai;
    let sodu_cuoi = sodu_hientai;

    if (allGD.length > 0) {
      const firstGD = allGD[0];
      const isVaoFirst = ['GT', 'NT'].includes(firstGD.LOAIGD);
      sodu_dau = firstGD.SODU_LUYKE - (isVaoFirst ? firstGD.SOTIEN : -firstGD.SOTIEN);
      sodu_cuoi = allGD[allGD.length - 1].SODU_LUYKE;
    }

    // Nodejs chỉ format ngày tháng và map thuộc tính cho view
    const rows = allGD.map(gd => {
      const isVao = ['GT', 'NT'].includes(gd.LOAIGD);
      const soduTruoc = gd.SODU_LUYKE - (isVao ? gd.SOTIEN : -gd.SOTIEN);
      
      return {
        ...gd,
        NGAYGD: new Date(gd.NGAYGD).toLocaleDateString('vi-VN'),
        LoaiGD: gd.LOAIGD,
        SoTien: gd.SOTIEN,
        SoDuDau: soduTruoc,
        SoDuSau: gd.SODU_LUYKE,
        TienVao: isVao ? gd.SOTIEN : 0 // Cung cấp thuộc tính này để EJS tô màu
      };
    });

    // Lấy danh sách TK để re-render combo
    const tkRows = user.NHOM === 'KhachHang'
      ? await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan WHERE RTRIM(CMND)=@cmnd`, { cmnd: user.MANV })
      : await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK`);

    res.render('baocao/saoke', {
      tkRows, rows, sodu_dau, sodu_cuoi, error: null,
      query: { SOTK, TUNGAY, DENNGAY }
    });
  } catch (err) {
    res.render('baocao/saoke', {
      tkRows: [], rows: null, sodu_dau: 0, sodu_cuoi: 0,
      error: err.message, query: { SOTK, TUNGAY, DENNGAY }
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
