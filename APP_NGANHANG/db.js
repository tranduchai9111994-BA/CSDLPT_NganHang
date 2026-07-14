// db.js
const sql = require('mssql');
const { execFile } = require('child_process');

// Cấu hình mặc định - kết nối NGANHANG1 (BENTHANH)
const configs = {
  NGUON: {
    server: 'ES-HAITD16',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },

  BENTHANH: {
    server: 'ES-HAITD16\\SQL1',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },

  TANDINH: {
    server: 'ES-HAITD16\\SQL2',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },

  TRACUU: {
    server: 'ES-HAITD16\\SQL3',
    database: 'NGANHANG',
    user: 'HTKN',
    password: '123',
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  }
};

const pools = {};

// Pool dùng account HTKN (admin) - cho các lệnh DDL cần quyền server-level
const adminPools = {};

function isPoolDead(pool) {
  return !pool || !pool.connected || pool._closed;
}

async function getAdminPool(serverKey) {
  const key = serverKey || 'BENTHANH';
  if (isPoolDead(adminPools[key])) {
    if (adminPools[key]) {
      try { await adminPools[key].close(); } catch (_) {}
      delete adminPools[key];
    }
    const serverConfig = configs[key];
    if (!serverConfig) throw new Error(`Không tìm thấy cấu hình server: ${key}`);
    adminPools[key] = await new sql.ConnectionPool({
      server: serverConfig.server,
      database: serverConfig.database,
      user: serverConfig.user,
      password: serverConfig.password,
      options: serverConfig.options,
      pool: serverConfig.pool
    }).connect();
    console.log(`[DB Admin] Đã kết nối admin pool: ${key}`);
  }
  return adminPools[key];
}

async function getPool(req, serverKey) {
  const user = req.session.user;
  if (!user || !user.USERNAME || !user.PASSWORD) {
    throw new Error('Bạn chưa đăng nhập hoặc phiên làm việc đã hết hạn.');
  }

  const targetServer = serverKey || user.SERVER || 'BENTHANH';
  const poolKey = `${targetServer}_${user.USERNAME}`;

  if (isPoolDead(pools[poolKey])) {
    if (pools[poolKey]) {
      try { await pools[poolKey].close(); } catch (_) {}
      delete pools[poolKey];
    }
    const serverConfig = configs[targetServer];
    if (!serverConfig) {
      throw new Error(`Không tìm thấy cấu hình server: ${targetServer}`);
    }

    const userConfig = {
      server: serverConfig.server,
      database: serverConfig.database,
      user: user.USERNAME,
      password: user.PASSWORD,
      options: serverConfig.options,
      pool: serverConfig.pool
    };

    pools[poolKey] = await new sql.ConnectionPool(userConfig).connect();
    console.log(`[DB] Đã kết nối: ${poolKey}`);
  }
  return pools[poolKey];
}

function isSessionKilled(err) {
  const msg = (err.message || '').toLowerCase();
  return msg.includes('kill state') || msg.includes('connection is closed') ||
    msg.includes('socket error') || msg.includes('network') ||
    err.code === 'ECONNCLOSED' || err.code === 'ESOCKET';
}

async function execSP(req, serverKey, spName, params = {}) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const pool = await getPool(req, serverKey);
      const request = pool.request();
      for (const [key, val] of Object.entries(params))
        request.input(key, val);
      return await request.execute(spName);
    } catch (err) {
      if (attempt === 0 && isSessionKilled(err)) {
        const user = req.session.user;
        const target = serverKey || user.SERVER || 'BENTHANH';
        const poolKey = `${target}_${user.USERNAME}`;
        if (pools[poolKey]) {
          try { await pools[poolKey].close(); } catch (_) {}
          delete pools[poolKey];
        }
        console.log(`[DB] Pool ${poolKey} bị lỗi session, đang tạo lại...`);
        continue;
      }
      throw err;
    }
  }
}

// Map serverKey → tên SQL Server instance
const serverAddresses = {
  BENTHANH: 'ES-HAITD16\\SQL1',
  TANDINH:  'ES-HAITD16\\SQL2',
  TRACUU:   'ES-HAITD16\\SQL3',
};

// Dùng sqlcmd (native SQL Server CLI) cho SP có MSDTC distributed transaction.
// tedious driver không hỗ trợ distributed tran, sqlcmd dùng native client nên OK.
//
// Bảo mật: SQL template (chuỗi -Q) chỉ chứa placeholder $(VarName) — không nhúng giá trị.
// Giá trị truyền qua -v (channel riêng), tránh shell injection hoàn toàn.
// ' vẫn được escape thành '' trong giá trị để ngăn SQL string literal breakage.
async function execSPAdmin(serverKey, spName, params = {}) {
  const serverAddr = serverAddresses[serverKey];
  if (!serverAddr) throw new Error(`Không tìm thấy server: ${serverKey}`);

  // SQL template tĩnh: chỉ tên SP + placeholder $(VarName) — không có user data
  const paramStr = Object.keys(params)
    .map(k => `@${k}=N'$(${k})'`)
    .join(', ');
  const query = `EXEC ${spName} ${paramStr}`;

  // Giá trị đi qua -v args (tách biệt khỏi SQL template), vẫn escape ' → ''
  const vArgs = Object.entries(params)
    .flatMap(([k, v]) => ['-v', `${k}=${String(v).replace(/'/g, "''")}`]);

  return new Promise((resolve, reject) => {
    execFile('sqlcmd', [
      '-S', serverAddr,
      '-d', 'NGANHANG',
      '-U', 'HTKN',
      '-P', '123',
      ...vArgs,
      '-Q', query,
      '-b'   // exit với error code nếu SQL lỗi
    ], (error, stdout, stderr) => {
      if (error) {
        const msg = stderr || stdout || error.message;
        return reject(new Error(msg.trim()));
      }
      resolve(stdout);
    });
  });
}

async function querySP(req, serverKey, spName, params = {}) {
  const result = await execSP(req, serverKey, spName, params);
  return result.recordset || [];
}

async function querySQL(req, serverKey, sqlStr, params = {}) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const pool = await getPool(req, serverKey);
      const request = pool.request();
      for (const [key, val] of Object.entries(params))
        request.input(key, val);
      const result = await request.query(sqlStr);
      return result.recordset || [];
    } catch (err) {
      if (attempt === 0 && isSessionKilled(err)) {
        const user = req.session.user;
        const target = serverKey || user.SERVER || 'BENTHANH';
        const poolKey = `${target}_${user.USERNAME}`;
        if (pools[poolKey]) {
          try { await pools[poolKey].close(); } catch (_) {}
          delete pools[poolKey];
        }
        console.log(`[DB] Pool ${poolKey} bị lỗi session, đang tạo lại...`);
        continue;
      }
      throw err;
    }
  }
}

async function queryAdminSQL(serverKey, sqlStr, params = {}) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const pool = await getAdminPool(serverKey);
      const request = pool.request();
      for (const [key, val] of Object.entries(params))
        request.input(key, val);
      const result = await request.query(sqlStr);
      return result.recordset || [];
    } catch (err) {
      if (attempt === 0 && isSessionKilled(err)) {
        const key = serverKey || 'BENTHANH';
        if (adminPools[key]) {
          try { await adminPools[key].close(); } catch (_) {}
          delete adminPools[key];
        }
        console.log(`[DB Admin] Pool ${key} bị lỗi session, đang tạo lại...`);
        continue;
      }
      throw err;
    }
  }
}

module.exports = { getPool, getAdminPool, execSP, execSPAdmin, querySP, querySQL, queryAdminSQL, sql, configs };
