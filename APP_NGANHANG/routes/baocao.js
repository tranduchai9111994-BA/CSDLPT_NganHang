// routes/baocao.js
const express = require('express');
const router  = express.Router();
const { querySQL, querySP, execSP } = require('../db');

function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }

// ============================================================
// SAO KÊ GIAO DỊCH
// ============================================================

// GET /baocao/saoke
router.get('/saoke', async (req, res) => {
  const server = getServer(req);
  const user   = req.session.user;
  try {
    let tkRows;
    if (user.NHOM === 'KhachHang') {
      // SP thay raw SELECT: KhachHang không có GRANT SELECT trên TaiKhoan
      const myTK = await querySP(req, server, 'sp_TaiKhoanKhachHang', { CMND: user.MANV });
      tkRows = myTK.map(tk => ({ SOTK: tk.SOTK }));
    } else if (server === 'TRACUU') {
      tkRows = await querySQL(req, server, `
        SELECT DISTINCT RTRIM(SOTK) AS SOTK FROM [LINK1].NGANHANG.dbo.TaiKhoan
        ORDER BY SOTK`);
    } else {
      tkRows = await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK`);
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
  const DENNGAY = DENNGAY_raw ? DENNGAY_raw + ' 23:59:59' : null;

  // KhachHang: pre-fetch danh sách TK qua SP (không raw SELECT) — dùng lại nhiều chỗ bên dưới
  let myTKList = [];
  let myTKRows = [];
  if (user.NHOM === 'KhachHang') {
    try {
      myTKList = await querySP(req, server, 'sp_TaiKhoanKhachHang', { CMND: user.MANV });
      myTKRows = myTKList.map(tk => ({ SOTK: tk.SOTK }));
    } catch (e) {
      return res.render('baocao/saoke', {
        tkRows: [], rows: null, sodu_dau: 0, sodu_cuoi: 0,
        showSodu: false, error: e.message, query: { SOTK, TUNGAY, DENNGAY: DENNGAY_raw }
      });
    }
  }

  // Kiểm tra KhachHang chỉ xem TK của mình (so sánh với danh sách đã fetch)
  if (SOTK && user.NHOM === 'KhachHang') {
    if (!myTKList.some(tk => tk.SOTK.trim() === SOTK.trim())) {
      return res.redirect('/baocao/saoke?error=Bạn không có quyền xem tài khoản này.');
    }
  }

  try {
    let rows = [];

    if (SOTK) {
      // Có chọn TK: dùng SP để có số dư đầu/cuối kỳ chính xác
      // SP_SaoKeTaiKhoan chỉ chạy được trên chi nhánh (SQL1/SQL2) — TRACUU không có local TaiKhoan/GD_GOIRUT/GD_CHUYENTIEN.
      // NganHang (server=TRACUU) mượn tạm BENTHANH để gọi SP: TaiKhoan nhân bản toàn vẹn + GD đọc Local+LINK1 nên vẫn đủ dữ liệu dù TK thuộc chi nhánh nào.
      const spServer = server === 'TRACUU' ? 'BENTHANH' : server;

      let sodu_hientai;
      if (user.NHOM === 'KhachHang') {
        // SODU đã có trong myTKList (không cần thêm query)
        const tkInfo = myTKList.find(tk => tk.SOTK.trim() === SOTK.trim());
        sodu_hientai = tkInfo ? tkInfo.SODU : 0;
      } else {
        const tkInfo = await querySQL(req, spServer, `SELECT SODU FROM TaiKhoan WHERE RTRIM(SOTK)=@sotk`, { sotk: SOTK });
        sodu_hientai = tkInfo.length > 0 ? tkInfo[0].SODU : 0;
      }

      const allGD = await querySP(req, spServer, 'SP_SaoKeTaiKhoan', { SOTK, TUNGAY, DENNGAY });

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
          NGAYGD: gd.NGAYGD,
          LoaiGD: gd.LOAIGD, SoTien: gd.SOTIEN,
          SoDuDau: gd.SODU_LUYKE - (isVao ? gd.SOTIEN : -gd.SOTIEN),
          SoDuSau: gd.SODU_LUYKE, TienVao: isVao ? gd.SOTIEN : 0
        };
      });

      const tkRows = user.NHOM === 'KhachHang'
        ? myTKRows
        : server === 'TRACUU'
          ? await querySQL(req, server, `SELECT DISTINCT RTRIM(SOTK) AS SOTK FROM [LINK1].NGANHANG.dbo.TaiKhoan ORDER BY SOTK`)
          : await querySQL(req, server, `SELECT RTRIM(SOTK) AS SOTK FROM TaiKhoan ORDER BY SOTK`);

      return res.render('baocao/saoke', {
        tkRows, rows, sodu_dau, sodu_cuoi, error: null,
        showSodu: true, query: { SOTK, TUNGAY, DENNGAY: DENNGAY_raw }
      });
    }

    // Không chọn TK: tổng hợp GD theo quyền
    let allRaw;

    if (user.NHOM === 'NganHang') {
      // sp_SaoKeToanBo trên TRACUU gộp từ cả 2 chi nhánh qua LINK1+LINK2
      allRaw = await querySP(req, 'TRACUU', 'sp_SaoKeToanBo', { TUNGAY, DENNGAY });
      allRaw.sort((a, b) => new Date(a.NGAYGD) - new Date(b.NGAYGD));
    } else if (user.NHOM === 'KhachHang') {
      // Gọi SP_SaoKeTaiKhoan cho từng TK của KhachHang rồi merge
      // (KhachHang không có SELECT trực tiếp trên GD_GOIRUT/GD_CHUYENTIEN)
      allRaw = [];
      for (const tk of myTKList) {
        const gdTK = await querySP(req, server, 'SP_SaoKeTaiKhoan', { SOTK: tk.SOTK, TUNGAY, DENNGAY });
        for (const gd of gdTK) {
          allRaw.push({ SOTK: tk.SOTK, NGAYGD: gd.NGAYGD, LOAIGD: gd.LOAIGD, SOTIEN: gd.SOTIEN });
        }
      }
      allRaw.sort((a, b) => new Date(a.NGAYGD) - new Date(b.NGAYGD));
    } else {
      // ChiNhanh: có GRANT SELECT trên TaiKhoan và bảng GD → raw query là hợp lệ
      const whereClause = `NGAYGD BETWEEN @tungay AND @denngay AND SOTK IN (SELECT SOTK FROM TaiKhoan WHERE RTRIM(MACN)=@macn)`;
      const params = { tungay: TUNGAY, denngay: DENNGAY, macn: user.MACN };

      const gdGui = await querySQL(req, server, `
        SELECT RTRIM(g.SOTK) AS SOTK, g.NGAYGD, g.LOAIGD, g.SOTIEN
        FROM GD_GOIRUT g WHERE ${whereClause}
      `, params);
      const gdCT_chuyen = await querySQL(req, server, `
        SELECT RTRIM(SOTK_CHUYEN) AS SOTK, NGAYGD, 'CT' AS LOAIGD, SOTIEN
        FROM GD_CHUYENTIEN WHERE NGAYGD BETWEEN @tungay AND @denngay AND SOTK_CHUYEN IN (SELECT SOTK FROM TaiKhoan WHERE RTRIM(MACN)=@macn)
      `, params);
      const gdCT_nhan = await querySQL(req, server, `
        SELECT RTRIM(SOTK_NHAN) AS SOTK, NGAYGD, 'NT' AS LOAIGD, SOTIEN
        FROM GD_CHUYENTIEN WHERE NGAYGD BETWEEN @tungay AND @denngay AND SOTK_NHAN IN (SELECT SOTK FROM TaiKhoan WHERE RTRIM(MACN)=@macn)
      `, params);

      allRaw = [...gdGui, ...gdCT_chuyen, ...gdCT_nhan]
        .sort((a, b) => new Date(a.NGAYGD) - new Date(b.NGAYGD));
    }

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
      ? myTKRows
      : server === 'TRACUU'
        ? await querySQL(req, server, `SELECT DISTINCT RTRIM(SOTK) AS SOTK FROM [LINK1].NGANHANG.dbo.TaiKhoan ORDER BY SOTK`)
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
  const { loai, macn, tungay, denngay, search } = req.query;
  const searchLike = search ? `%${search}%` : null;

  try {
    let rows = [];
    let title = '';

    if (loai === 'kh') {
      title = 'Danh sách khách hàng';
      const searchClause = searchLike
        ? `AND (RTRIM(CMND) LIKE @search OR RTRIM(HO)+' '+RTRIM(TEN) LIKE @search)`
        : '';
      if (user.NHOM === 'NganHang' && !macn) {
        rows = await querySQL(req, 'TRACUU', `
          SELECT RTRIM(CMND) AS CMND,
                 RTRIM(HO)+' '+RTRIM(TEN) AS HoTen,
                 RTRIM(MACN) AS MACN, SODT
          FROM KhachHang WHERE 1=1 ${searchClause} ORDER BY MACN, HO, TEN
        `, searchLike ? { search: searchLike } : {});
      } else {
        const filterMACN = macn || user.MACN;
        rows = await querySQL(req, server, `
          SELECT RTRIM(CMND) AS CMND,
                 RTRIM(HO)+' '+RTRIM(TEN) AS HoTen,
                 RTRIM(MACN) AS MACN, SODT
          FROM KhachHang WHERE RTRIM(MACN)=@macn ${searchClause} ORDER BY HO, TEN
        `, { macn: filterMACN, ...(searchLike ? { search: searchLike } : {}) });
      }
    } else if (loai === 'tk') {
      title = 'Danh sách tài khoản mở';
      const sqlParams = {
        MACN: null,
        TUNGAY: tungay || null,
        DENNGAY: denngay || null
      };

      if (user.NHOM === 'NganHang') {
        if (macn) sqlParams.MACN = macn;
        rows = await querySP(req, 'TRACUU', 'sp_LietKeTaiKhoanTheoNgay', sqlParams);
      } else {
        const cnMACN = user.MACN;
        rows = await querySQL(req, server, `
          SELECT RTRIM(tk.SOTK) AS SOTK, RTRIM(tk.CMND) AS CMND,
                 RTRIM(kh.HO)+' '+RTRIM(kh.TEN) AS HoTen,
                 tk.SODU, RTRIM(tk.MACN) AS MACN,
                 CONVERT(varchar, tk.NGAYMOTK, 103) AS NGAYMOTK
          FROM TaiKhoan tk
          LEFT JOIN KhachHang kh ON RTRIM(tk.CMND)=RTRIM(kh.CMND)
          WHERE RTRIM(tk.MACN)=@macn
            AND (@tungay IS NULL OR CAST(tk.NGAYMOTK AS DATE)>=@tungay)
            AND (@denngay IS NULL OR CAST(tk.NGAYMOTK AS DATE)<=@denngay)
          ORDER BY tk.NGAYMOTK DESC
        `, { macn: cnMACN, tungay: tungay || null, denngay: denngay || null });
      }
      if (searchLike) {
        const kw = search.toLowerCase();
        rows = rows.filter(r => (r.CMND && r.CMND.toLowerCase().includes(kw)) || (r.HoTen && r.HoTen.toLowerCase().includes(kw)));
      }
    }

    res.render('baocao/lietke', {
      rows, title, loai: loai || '', error: null,
      query: { macn, tungay, denngay, search }
    });
  } catch (err) {
    res.render('baocao/lietke', {
      rows: [], title: '', loai: loai || '', error: err.message,
      query: {}
    });
  }
});

module.exports = router;
