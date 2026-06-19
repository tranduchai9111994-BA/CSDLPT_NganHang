// routes/quantri.js
const express = require('express');
const router = express.Router();
const { getPool, sql } = require('../db');

// Hàm phụ trợ lấy danh sách nhân viên
async function getNhanVienList(req) {
  try {
    const sessionUser = req.session.user;
    const macn = sessionUser.MACN ? sessionUser.MACN.trim() : '';
    console.log(`[DEBUG] Đang nạp danh sách Nhân Viên cho Chi Nhánh: '${macn}' tại Server: '${sessionUser.SERVER}'`);
    const pool = await getPool(req, sessionUser.SERVER);
    const query = `
      SELECT MANV, HO, TEN 
      FROM NhanVien 
      WHERE RTRIM(MACN) = RTRIM(@macn) AND TrangThaiXoa = 0
    `;
    const result = await pool.request()
      .input('macn', sql.NVarChar, macn)
      .query(query);
    console.log(`[DEBUG] Số Nhân Viên load được: ${result.recordset ? result.recordset.length : 0}`);
    return result.recordset || [];
  } catch (e) {
    console.error("Lỗi khi load danh sách nhân viên:", e);
    return [];
  }
}

// Hàm phụ trợ lấy danh sách khách hàng
async function getKhachHangList(req) {
  try {
    const sessionUser = req.session.user;
    const macn = sessionUser.MACN ? sessionUser.MACN.trim() : '';
    console.log(`[DEBUG] Đang nạp danh sách Khách Hàng cho Chi Nhánh: '${macn}' tại Server: '${sessionUser.SERVER}'`);
    const pool = await getPool(req, sessionUser.SERVER);
    const query = `
      SELECT CMND, HO, TEN 
      FROM KhachHang 
      WHERE RTRIM(MACN) = RTRIM(@macn)
    `;
    const result = await pool.request()
      .input('macn', sql.NVarChar, macn)
      .query(query);
    console.log(`[DEBUG] Số Khách Hàng load được: ${result.recordset ? result.recordset.length : 0}`);
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
  // NganHang chỉ được tạo tài khoản NganHang, ChiNhanh chỉ được tạo tài khoản ChiNhanh
  if (sessionUser.NHOM === 'NganHang' && role !== 'NganHang') {
    return res.render('taotaikhoan', { error: 'Quyền hạn không hợp lệ. Bạn chỉ có thể tạo tài khoản nhóm NganHang.', success: null, nhanviens, khachhangs, user: sessionUser });
  }
  if (sessionUser.NHOM === 'ChiNhanh' && role !== 'ChiNhanh' && role !== 'KhachHang') {
    return res.render('taotaikhoan', { error: 'Quyền hạn không hợp lệ. Bạn chỉ có thể tạo tài khoản nhóm ChiNhanh hoặc KhachHang.', success: null, nhanviens, khachhangs, user: sessionUser });
  }

  try {
    // 2. KẾT NỐI DATABASE
    // Dùng cấu hình HTKN của chi nhánh/server hiện tại đang đăng nhập
    const pool = await getPool(req, sessionUser.SERVER);
    const request = pool.request();

    // Truyền tham số cho SP_TaoTaiKhoan
    request.input('LGNAME', sql.VarChar, loginname);
    request.input('PASS', sql.VarChar, password);
    request.input('USERNAME', sql.VarChar, username);
    request.input('ROLE', sql.VarChar, role);

    // Xử lý giá trị trả về từ SP
    request.output('RET', sql.Int); // Mặc dù SP dùng RETURN, Node mssql không bắt được RETURN code dễ dàng nếu không dùng procedure parameters.
    // Chú ý: Vì SP_TaoTaiKhoan dùng RETURN (1, 2, 0), trong node-mssql ta có thể lấy qua result.returnValue
    const result = await request.execute('SP_TaoTaiKhoan');
    
    const retCode = result.returnValue;

    if (retCode === 1) {
      return res.render('taotaikhoan', { error: 'Lỗi: Tên đăng nhập (Login Name) đã tồn tại trên Server.', success: null, nhanviens, khachhangs, user: sessionUser });
    } else if (retCode === 2) {
      return res.render('taotaikhoan', { error: 'Lỗi: Người này đã được cấp tài khoản (User Name đã tồn tại).', success: null, nhanviens, khachhangs, user: sessionUser });
    } else if (retCode === 0) {
      return res.render('taotaikhoan', { error: null, success: `✅ Tạo tài khoản thành công cho user ${username} với quyền ${role}.`, nhanviens, khachhangs, user: sessionUser });
    } else {
      return res.render('taotaikhoan', { error: 'Lỗi không xác định từ quá trình tạo tài khoản.', success: null, nhanviens, khachhangs, user: sessionUser });
    }

  } catch (err) {
    console.error('[SP_TaoTaiKhoan ERROR]', err.message);
    res.render('taotaikhoan', { error: 'Lỗi hệ thống: ' + err.message, success: null, nhanviens, khachhangs, user: sessionUser });
  }
});

module.exports = router;
