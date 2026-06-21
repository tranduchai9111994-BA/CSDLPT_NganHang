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

async function getAdminPool(serverKey) {
  const key = serverKey || 'BENTHANH';
  if (!adminPools[key]) {
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

  if (!pools[poolKey]) {
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

async function execSP(req, serverKey, spName, params = {}) {
  const pool = await getPool(req, serverKey);
  const request = pool.request();
  for (const [key, val] of Object.entries(params)) {
    request.input(key, val);
  }
  return await request.execute(spName);
}

// Map serverKey → tên SQL Server instance
const serverAddresses = {
  BENTHANH: 'ES-HAITD16\\SQL1',
  TANDINH:  'ES-HAITD16\\SQL2',
  TRACUU:   'ES-HAITD16\\SQL3',
};

// Dùng sqlcmd (native SQL Server CLI) cho SP có MSDTC distributed transaction.
// tedious driver không hỗ trợ distributed tran, sqlcmd dùng native client nên OK.
async function execSPAdmin(serverKey, spName, params = {}) {
  const serverAddr = serverAddresses[serverKey];
  if (!serverAddr) throw new Error(`Không tìm thấy server: ${serverKey}`);

  // Build câu EXEC với tham số
  const paramStr = Object.entries(params)
    .map(([k, v]) => `@${k}=N'${String(v).replace(/'/g, "''")}'`)
    .join(', ');
  const query = `EXEC ${spName} ${paramStr}`;

  return new Promise((resolve, reject) => {
    execFile('sqlcmd', [
      '-S', serverAddr,
      '-d', 'NGANHANG',
      '-U', 'HTKN',
      '-P', '123',
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
  const pool = await getPool(req, serverKey);
  const request = pool.request();
  for (const [key, val] of Object.entries(params)) {
    request.input(key, val);
  }
  const result = await request.query(sqlStr);
  return result.recordset || [];
}

module.exports = { getPool, getAdminPool, execSP, execSPAdmin, querySP, querySQL, sql, configs };
