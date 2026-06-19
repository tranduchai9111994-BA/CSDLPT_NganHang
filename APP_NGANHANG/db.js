// db.js
const sql = require('mssql');

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

module.exports = { getPool, execSP, querySP, querySQL, sql, configs };
