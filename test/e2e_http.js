// E2E test qua HTTP (không cần browser).
// Đăng nhập → POST form → assert redirect và trạng thái DB.
// Chạy: node test/e2e_http.js
'use strict';

// 127.0.0.1 thay vì localhost để Node 20+ tránh happy-eyeballs IPv6 fail trên Windows.
const BASE = 'http://127.0.0.1:3001';

// Đơn giản: giữ cookie session giữa các request.
let cookieJar = '';

function setCookiesFrom(res) {
  const raw = res.headers.getSetCookie
    ? res.headers.getSetCookie()
    : (res.headers.get('set-cookie') || '').split(/,(?=[^;]+?=)/);
  if (!raw || !raw.length) return;
  const parts = [];
  for (const c of raw) {
    const first = String(c).split(';')[0];
    if (first && first.includes('=')) parts.push(first.trim());
  }
  if (parts.length) cookieJar = parts.join('; ');
}

async function request(method, path, { form, follow = false } = {}) {
  const headers = {};
  if (cookieJar) headers['Cookie'] = cookieJar;
  let body;
  if (form) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    body = new URLSearchParams(form).toString();
  }
  try {
    const res = await fetch(BASE + path, {
      method,
      headers,
      body,
      redirect: follow ? 'follow' : 'manual'
    });
    setCookiesFrom(res);
    const text = await res.text();
    return { status: res.status, location: res.headers.get('location'), text };
  } catch (e) {
    throw new Error(`${method} ${path} → ${e.message} (cause: ${e.cause && e.cause.message ? e.cause.message : 'n/a'})`);
  }
}

// -------- Utility: assertion + query DB qua sqlcmd wrapper --------
const { execFile } = require('child_process');
const util = require('util');
const execFileP = util.promisify(execFile);

async function sql(server, query) {
  const args = [
    '-S', server, '-E', '-d', 'NGANHANG', '-f', '65001',
    '-h', '-1', '-W', '-s', '|',
    '-Q', 'SET NOCOUNT ON; ' + query
  ];
  const { stdout } = await execFileP('sqlcmd', args, { maxBuffer: 10 * 1024 * 1024 });
  return stdout.trim().split(/\r?\n/).filter(l => l && !l.startsWith('-')).map(l => l.split('|'));
}

let passed = 0, failed = 0;
function ok(name) { console.log('  [PASS] ' + name); passed++; }
function fail(name, detail) { console.log('  [FAIL] ' + name + ' — ' + detail); failed++; }
async function step(name, fn) {
  console.log('\n=== ' + name + ' ===');
  try { await fn(); } catch (e) { fail(name, e.message); }
}

// -------- Test flow --------
(async () => {
  console.log('E2E HTTP test — App http://localhost:3001');

  await step('LOGIN BT001/1 @ BENTHANH', async () => {
    const r = await request('POST', '/login', {
      form: { username: 'BT001', password: '1', chinhanh: 'BENTHANH' }
    });
    if (r.status !== 302) throw new Error('expected 302 redirect, got ' + r.status + '\n' + r.text.slice(0, 300));
    if (!cookieJar) throw new Error('không nhận được cookie session');
    ok('login redirect 302 + cookie session set');
  });

  let newSOTK = null;
  await step('POST /taikhoan/mo (CMND=1111111111, SODU=500k, MACN=BENTHANH)', async () => {
    const before = (await sql('ES-HAITD16\\SQL1', "SELECT COUNT(*) FROM TaiKhoan WHERE SOTK LIKE 'BT%'"))[0][0];
    const r = await request('POST', '/taikhoan/mo', {
      form: { CMND: '1111111111', SODU: '500000', MACN: 'BENTHANH', KH_MACN: 'BENTHANH' }
    });
    if (r.status !== 302) throw new Error('expected 302, got ' + r.status);
    const msgMatch = decodeURIComponent(r.location || '').match(/(BT|TD)\d{7}/);
    if (!msgMatch) throw new Error('không thấy SOTK trong redirect: ' + r.location);
    newSOTK = msgMatch[0];
    ok('SOTK ' + newSOTK + ' trong redirect message');

    const after = (await sql('ES-HAITD16\\SQL1', "SELECT COUNT(*) FROM TaiKhoan WHERE SOTK LIKE 'BT%'"))[0][0];
    if (Number(after) !== Number(before) + 1) {
      throw new Error(`TK count không tăng đúng 1: ${before} → ${after}`);
    }
    ok('DB TK BT% count tăng đúng 1');

    const row = await sql('ES-HAITD16\\SQL1',
      `SELECT RTRIM(SOTK), RTRIM(CMND), SODU, RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK)='${newSOTK}'`);
    if (!row.length) throw new Error(`Không tìm thấy TK ${newSOTK} trong DB`);
    const [sotk, cmnd, sodu, macn] = row[0];
    if (sotk !== newSOTK) throw new Error('SOTK sai: ' + sotk);
    if (cmnd !== '1111111111') throw new Error('CMND sai: ' + cmnd);
    if (Number(sodu) !== 500000) throw new Error('SODU sai: ' + sodu);
    if (macn !== 'BENTHANH') throw new Error('MACN sai: ' + macn);
    ok('DB row TK khớp: SOTK=' + sotk + ', CMND=' + cmnd + ', SODU=' + sodu + ', MACN=' + macn);
  });

  await step('SET SODU=0 để test đóng TK', async () => {
    if (!newSOTK) throw new Error('không có SOTK từ bước trước');
    await sql('ES-HAITD16\\SQL1', `UPDATE TaiKhoan SET SODU=0 WHERE RTRIM(SOTK)='${newSOTK}'`);
    ok('SODU set 0 cho ' + newSOTK);
  });

  await step('POST /taikhoan/dong ' + newSOTK, async () => {
    const r = await request('POST', '/taikhoan/dong', {
      form: { SOTK: newSOTK }
    });
    if (r.status !== 302) throw new Error('expected 302, got ' + r.status);
    if (!decodeURIComponent(r.location).includes('Đã đóng')) {
      throw new Error('redirect không có success: ' + r.location);
    }
    ok('redirect success: ' + r.location);

    const cnt = (await sql('ES-HAITD16\\SQL1',
      `SELECT COUNT(*) FROM TaiKhoan WHERE RTRIM(SOTK)='${newSOTK}'`))[0][0];
    if (Number(cnt) !== 0) throw new Error('TK vẫn còn trong DB: ' + cnt);
    ok('DB đã xóa TK ' + newSOTK);
  });

  await step('POST /taikhoan/dong ' + '[negative] TK có SODU>0', async () => {
    const r = await request('POST', '/taikhoan/dong', {
      form: { SOTK: 'BT0000006' }
    });
    if (r.status !== 302) throw new Error('expected 302, got ' + r.status);
    const loc = decodeURIComponent(r.location);
    if (!loc.includes('error')) throw new Error('expected error redirect: ' + loc);
    if (!loc.includes('số dư khác 0') && !loc.includes('số dư')) {
      throw new Error('error message không đúng: ' + loc);
    }
    ok('redirect error đúng: ' + loc);
  });

  console.log('\n========================================');
  console.log(`RESULT: ${passed} PASS, ${failed} FAIL`);
  console.log('========================================');
  process.exit(failed === 0 ? 0 : 1);
})().catch(e => { console.error('FATAL:', e); process.exit(2); });
