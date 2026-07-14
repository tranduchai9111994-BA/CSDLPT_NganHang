# Quản Lý Kết Nối CSDL Phân Tán (`db.js`)

Đây là trái tim của ứng dụng. File `db.js` định nghĩa toàn bộ cơ chế kết nối tới các SQL Server instance.

---

## 1. Khái Niệm `serverKey`

Mỗi instance SQL Server được định danh bằng một key cố định:

| serverKey | Instance | Vai trò |
|-----------|----------|---------|
| `NGUON` | `ES-HAITD16` | Publisher / Server gốc |
| `BENTHANH` | `ES-HAITD16\SQL1` | Chi nhánh Bến Thành |
| `TANDINH` | `ES-HAITD16\SQL2` | Chi nhánh Tân Định |
| `TRACUU` | `ES-HAITD16\SQL3` | Server tra cứu / báo cáo toàn cục |

`serverKey` được gán cho từng user khi đăng nhập (`req.session.user.SERVER`) và dùng xuyên suốt phiên làm việc. Nhân viên BENTHANH luôn thao tác trên SQL1, nhân viên TANDINH trên SQL2.

---

## 2. Hai Loại Connection Pool

### 2.1. `getPool(req, serverKey)` — Pool theo từng User (chính)

Đây là cơ chế **quan trọng nhất và đặc biệt nhất** của hệ thống.

```javascript
// db.js:83
async function getPool(req, serverKey) {
  const user = req.session.user;             // lấy username/password từ session
  const poolKey = `${targetServer}_${user.USERNAME}`;

  if (!pools[poolKey]) {
    const userConfig = {
      server: serverConfig.server,
      user: user.USERNAME,      // ← dùng ĐÚNG username của người dùng
      password: user.PASSWORD,  // ← dùng ĐÚNG password của người dùng
      ...
    };
    pools[poolKey] = await new sql.ConnectionPool(userConfig).connect();
  }
  return pools[poolKey];
}
```

**Tại sao quan trọng?**
- Mỗi user kết nối bằng SQL Login của chính họ, không qua tài khoản trung gian.
- SQL Server ghi nhận đúng `LOGIN_NAME()` → mọi thao tác đều có dấu vết audit.
- Pool được cache theo `serverKey + username` — user thứ 2 không dùng chung pool với user thứ 1.
- `username` và `password` được lưu trong `req.session.user` khi đăng nhập (xem `auth.js`).

**Hàm wrapper dùng pool này:**
- `querySQL(req, serverKey, sql, params)` — chạy raw SQL
- `execSP(req, serverKey, spName, params)` — gọi SP bằng tedious driver
- `querySP(req, serverKey, spName, params)` — gọi SP và trả về recordset

### 2.2. `getAdminPool(serverKey)` — Pool Admin (phụ, dùng riêng cho DDL)

```javascript
// db.js:65
async function getAdminPool(serverKey) {
  adminPools[key] = await new sql.ConnectionPool({
    user: serverConfig.user,     // ← tài khoản HTKN (hardcoded)
    password: serverConfig.password,
    ...
  }).connect();
}
```

Dùng tài khoản `HTKN` (có quyền `securityadmin`). Chỉ dùng cho `quantri.js` khi tạo/xóa SQL Login (`CREATE LOGIN`, `ALTER LOGIN`) — việc không thể làm bằng tài khoản nhân viên thường.

---

## 3. `execSP` vs `execSPAdmin` — Hai Đường Gọi SP

| Hàm | Cách gọi | Dùng khi |
|-----|----------|----------|
| `execSP(req, serverKey, spName, params)` | tedious driver (mssql package) | SP thông thường — Login, DanhSachTaiKhoan... |
| `execSPAdmin(serverKey, spName, params)` | `sqlcmd` (CLI, Native Client) | SP có `BEGIN DISTRIBUTED TRANSACTION` — **GuiTien, RutTien, ChuyenTien, MoTaiKhoan**, ChuyenNhanVien, PhucHoiNhanVien |

**Tại sao cần `execSPAdmin` cho Distributed Transaction?**

Driver `tedious` (Node.js) không hỗ trợ `BEGIN DISTRIBUTED TRANSACTION` vì đây là tính năng của SQL Server Native Client, không có trong protocol TDS được tedious implement.

`sqlcmd` dùng Native Client thật sự của Windows → hỗ trợ MSDTC đầy đủ.

```javascript
// db.js:135 — execSPAdmin dùng sqlcmd
execFile('sqlcmd', [
  '-S', serverAddr,
  '-d', 'NGANHANG',
  '-U', 'HTKN', '-P', '123',
  ...vArgs,            // ← giá trị đi qua -v (tách biệt khỏi SQL template)
  '-Q', query,         // ← SQL template chỉ có $(VarName) placeholder
  '-b'                 // ← exit với error code nếu SQL lỗi
], callback);
```

**Bảo mật `execSPAdmin`:** Giá trị params đi qua `-v Key=Value` (channel riêng), không nhúng trực tiếp vào chuỗi SQL → tránh shell injection. Dấu `'` trong giá trị được escape thành `''`.

---

## 4. Luồng Request Đầy Đủ (Browser → SQL)

```
[Browser] POST /giaodich/chuyentien
    │
    ▼
[app.js] middleware: requireLogin → requireRole('NganHang','ChiNhanh')
    │
    ▼
[routes/giaodich.js:85] router.post('/chuyentien', ...)
    │  lấy serverKey = req.session.user.SERVER (ví dụ: 'BENTHANH')
    │  params: { SOTK_CHUYEN, SOTK_NHAN, SOTIEN, MANV }
    │
    ▼
[db.js:execSP] → [db.js:getPool] → pool[BENTHANH_BT001]
    │            (kết nối bằng username=BT001, password=... )
    │            (kết nối tới ES-HAITD16\SQL1)
    │
    ▼
SQL Server SQL1: EXEC sp_ChuyenTien @SOTK_CHUYEN=..., @SOTK_NHAN=..., ...
    │
    ├─ Nếu SOTK_NHAN local → UPDATE local
    └─ Nếu SOTK_NHAN ở SQL2 →
           BEGIN DISTRIBUTED TRANSACTION
           UPDATE SQL1.TaiKhoan (trừ tiền)
           UPDATE [LINK1].SQL2.TaiKhoan (cộng tiền) ← MSDTC 2PC
           COMMIT
    │
    ▼
[routes/giaodich.js] nhận kết quả → res.redirect('/...?success=...')
    │
    ▼
[Browser] thấy thông báo thành công
```

---

## 5. Connection Pool Resilience (Retry & Recovery)

Pool có thể rơi vào trạng thái "chết" (session bị kill, mất kết nối mạng, SQL Server restart). `db.js` xử lý bằng 3 cơ chế:

1. **`isPoolDead(pool)`**: Kiểm tra `pool.connected` + `pool._closed` trước mỗi lần reuse. Nếu pool chết → xóa khỏi cache, tạo pool mới.

2. **`isSessionKilled(err)`**: Nhận diện các lỗi session bị kill (`kill state`, `connection is closed`, `socket error`, `ECONNCLOSED`, `ESOCKET`).

3. **Retry logic** (1 lần) trong `execSP`, `querySQL`, `queryAdminSQL`: khi gặp lỗi session killed → xóa pool cũ → tạo pool mới → thử lại 1 lần. Nếu vẫn lỗi → throw.

**Hàm `queryAdminSQL(serverKey, sqlStr, params)`** — bổ sung mới, tương tự `querySQL` nhưng dùng admin pool (`HTKN`). Có retry tự động. Dùng cho các query cần quyền cao hoặc query LINK1 (admin pool có mapping Linked Server, user pool thường thì không).

---

## 6. Quản Lý Session & Pool

- Pool được cache trong module-level object `pools` theo key `${serverKey}_${username}`.
- Khi user logout (`/logout`), `req.session.destroy()` xóa session nhưng **pool vẫn tồn tại** trong bộ nhớ process.
- Điều này có nghĩa: nếu user A và B cùng login với cùng username (không thực tế), họ sẽ share pool → cần đảm bảo mỗi username là duy nhất.
- Pool có `idleTimeoutMillis: 30000` — tự đóng connection sau 30s không dùng, tránh leak.

---

## 7. Xác Định Server Trong Routes

Hàm helper xuất hiện trong mọi route file:

```javascript
function getServer(req) { return req.session.user.SERVER || 'BENTHANH'; }
```

- Nhân viên ChiNhanh: SERVER = 'BENTHANH' hoặc 'TANDINH' (gán lúc login theo chi nhánh chọn).
- Nhóm NganHang: SERVER = 'TRACUU' (luôn kết nối server tra cứu).
- Fallback về 'BENTHANH' nếu thiếu (không nên xảy ra).
