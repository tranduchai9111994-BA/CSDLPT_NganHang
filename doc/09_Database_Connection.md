# Kết Nối Cơ Sở Dữ Liệu (`db.js`)

`APP_NGANHANG/db.js` là module trung tâm quản lý toàn bộ kết nối tới 4 SQL Server instance. Nó cung cấp 2 loại pool và 5 hàm helper phục vụ mọi route.

---

## 1. Cấu Hình Kết Nối

```javascript
const configs = {
  NGUON:    { server: 'ES-HAITD16',       database: 'NGANHANG', user: 'HTKN', password: '123', ... },
  BENTHANH: { server: 'ES-HAITD16\\SQL1', database: 'NGANHANG', user: 'HTKN', password: '123', ... },
  TANDINH:  { server: 'ES-HAITD16\\SQL2', database: 'NGANHANG', user: 'HTKN', password: '123', ... },
  TRACUU:   { server: 'ES-HAITD16\\SQL3', database: 'NGANHANG', user: 'HTKN', password: '123', ... }
};
```

- `user/password` ở `configs` là **admin login `HTKN`** — chỉ dùng cho `adminPool` (không phải cho pool người dùng).
- Người dùng thật đăng nhập bằng SQL Login riêng (BT001, TD001, NV_..., KH_..., admin) — mật khẩu lấy từ `session.user.PASSWORD`.
- Cả 4 instance đều nằm trên cùng máy `ES-HAITD16`, được tách bằng tên instance (`SQL1/SQL2/SQL3`) hoặc default instance (NGUON).

---

## 2. Hai Loại Pool

### 2.1. Per-User Pool (`pools`) — mặc định cho request người dùng

- **Key**: `${serverKey}_${username}` (ví dụ `BENTHANH_BT001`).
- **Login dùng để kết nối**: chính SQL Login của người dùng trong `session.user.USERNAME/PASSWORD`.
- **Ý nghĩa**: mọi câu SQL do người dùng gây ra đều chạy dưới danh nghĩa họ → SQL Server tự phân quyền theo GRANT/DENY đã cấp cho role → `LOGIN_NAME()` trong SP là chính họ (dễ audit).
- **Tạo bởi**: `getPool(req, serverKey)`.
- **Được dùng bởi**: `execSP`, `querySP`, `querySQL`.

### 2.2. Admin Pool (`adminPools`) — dùng cho tác vụ đặc quyền

- **Key**: `serverKey` (ví dụ `BENTHANH`).
- **Login dùng để kết nối**: `HTKN` (đã được cấp `sysadmin` / các quyền server-level cần thiết).
- **Ý nghĩa**: một số tác vụ đòi hỏi quyền server-level mà người dùng thường không có (CREATE LOGIN, DROP LOGIN, ALTER SERVER ROLE), hoặc muốn cô lập việc điều phối Distributed Tran khỏi phiên người dùng.
- **Tạo bởi**: `getAdminPool(serverKey)`.
- **Được dùng bởi**: `queryAdminSQL` (raw SQL admin) và trực tiếp trong các route quản trị.

> Vì sao cần chia 2 loại?
> - Người dùng thường không có quyền `CREATE LOGIN`; nếu cho, sẽ vỡ mô hình bảo mật.
> - Admin pool cần dùng chung 1 login cho toàn service (không phụ thuộc ai đang đăng nhập).

---

## 3. Helper Chính — Bảng So Sánh

| Hàm | Pool | Ai gọi | Dùng khi nào |
|---|---|---|---|
| `getPool(req, serverKey)` | per-user | nội bộ | Base primitive; ít khi gọi trực tiếp |
| `execSP(req, key, sp, params)` | per-user | route | SP thông thường (SELECT/UPDATE local), không MSDTC |
| `querySP(req, key, sp, params)` | per-user | route | Giống `execSP` nhưng trả về `recordset` sạch |
| `querySQL(req, key, sqlStr, params)` | per-user | route | Raw SQL người dùng (SELECT trực tiếp, không dùng SP) |
| `getAdminPool(serverKey)` | admin (HTKN) | route quản trị | Chuẩn bị pool cho DDL server-level |
| `queryAdminSQL(key, sqlStr, params)` | admin (HTKN) | route | Raw SQL admin (VD dùng Linked Server LINK1 để tạo login từ xa) |
| `execSPAdmin(key, sp, params)` | **KHÔNG dùng pool** — bung `sqlcmd` | route ghi tiền | SP có `BEGIN DISTRIBUTED TRANSACTION` (MSDTC) |

---

## 4. `execSPAdmin` — Vì Sao Phải Dùng `sqlcmd`?

`node-mssql` (driver `tedious`) **không hỗ trợ đầy đủ `BEGIN DISTRIBUTED TRANSACTION`**: khi SP mở distributed tran, driver dễ mất kết nối, không rollback được, hoặc treo. Do vậy các SP dạng phân tán được gọi qua **`sqlcmd`** — CLI native dùng ODBC/OLE DB, hỗ trợ MSDTC nguyên vẹn.

Chi tiết implementation quan trọng:

- **SQL template tĩnh** (chuỗi `-Q`) chỉ chứa placeholder `$(VarName)` — không nhúng giá trị. Giá trị được truyền qua `-v` (channel riêng). ⇒ **chống shell injection tuyệt đối**.
- Vẫn thay `'` → `''` trong giá trị để tránh vỡ SQL string literal.
- Ghi output ra file tạm với `-o outFile -f 65001` → sqlcmd xuất **UTF-8 chuẩn** thay vì OEM codepage (giữ được dấu tiếng Việt trong `RAISERROR`).
- Dùng flag `-b` để `sqlcmd` exit với error code nếu SQL lỗi.
- Sau khi đọc file, lọc bỏ dòng header kỹ thuật `Msg ###, Level ##, ...` để chỉ giữ lại nội dung `RAISERROR` thật hiển thị cho user.

SP dùng `execSPAdmin`:
- `sp_ChuyenTien`, `sp_GuiTien`, `sp_RutTien`
- `sp_MoTaiKhoan`
- `sp_ChuyenNhanVien`, `SP_PhucHoiNhanVien`

---

## 5. Xử Lý Session Bị Kill / Pool Chết

Khi Publisher đang chạy Merge/Transactional Replication, session có thể bị SQL Server kill (thấy log `The client was unable to reuse a session with SPID N`). `db.js` phòng vệ hai tầng:

### 5.1. Phát hiện pool "chết" trước khi dùng

```javascript
function isPoolDead(pool) {
  return !pool || !pool.connected || pool._closed;
}
```

Trước mỗi lần lấy pool: nếu chết → close cứng → xóa khỏi cache → tạo mới.

### 5.2. Retry 1 lần khi query bung lỗi mạng

```javascript
function isSessionKilled(err) {
  const msg = (err.message || '').toLowerCase();
  return msg.includes('kill state') || msg.includes('connection is closed') ||
         msg.includes('socket error') || msg.includes('network') ||
         err.code === 'ECONNCLOSED' || err.code === 'ESOCKET';
}
```

Trong `execSP`, `querySQL`, `queryAdminSQL`: bọc lời gọi trong vòng `for (attempt=0; attempt<2; attempt++)`. Attempt 0 lỗi + `isSessionKilled` trả `true` → xóa pool → attempt 1 sẽ tạo pool mới và chạy lại. Vòng 2 lỗi → ném lên caller.

Cơ chế này giúp app tự "hồi" sau khi replication làm bay session mà không cần user F5.

---

## 6. Vòng Đời Kết Nối

```
User đăng nhập (auth.js)
    └─ Không giữ pool sẵn — chỉ gọi 1 câu SELECT thử qua getPool() để xác thực Login/Password.

User bấm menu, gửi POST /giaodich/guitien
    └─ route gọi execSPAdmin('BENTHANH', 'sp_GuiTien', { ... })
        └─ execSPAdmin bung sqlcmd (không đụng pool per-user)

User bấm /baocao/saoke
    └─ route gọi querySP(req, 'TRACUU', 'SP_SaoKeTaiKhoan', { ... })
        └─ getPool(req, 'TRACUU') → tìm pool 'TRACUU_KH_...' → nếu chết thì tạo mới
            └─ Kết nối tới ES-HAITD16\\SQL3 với LOGIN của KH đó
                └─ SP đọc dữ liệu qua LINK1/LINK2 (theo MACN của KH)

User logout
    └─ req.session.destroy() — Pool không bị đóng ngay (giữ cache trong RAM đến khi process tắt).
```

Pool per-user chỉ bị đóng khi:
1. Node process khởi động lại.
2. `isPoolDead()` phát hiện và xóa để tạo lại.
3. `isSessionKilled()` bung retry → xóa pool cũ.

---

## 7. Export

```javascript
module.exports = { getPool, getAdminPool, execSP, execSPAdmin, querySP, querySQL, queryAdminSQL, sql, configs };
```

- `sql`: re-export namespace `mssql` để route có thể dùng `sql.Int`, `sql.NVarChar(...)` khi cần binding kiểu chặt.
- `configs`: export để `setup_db.js` biết địa chỉ 4 instance.
