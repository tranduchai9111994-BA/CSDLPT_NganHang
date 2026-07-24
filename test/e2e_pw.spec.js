// @ts-check
// Playwright E2E test — verify tương tự HTTP test nhưng qua browser thật.
// Kiểm cả JS validation phía client (input SODU format, submit form).
// Chạy: cd test && npx playwright test
const { test, expect } = require('@playwright/test');
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

test.describe('E2E App Ngân Hàng (RF-A/B fix verification)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await page.fill('input[name="username"]', 'BT001');
    await page.fill('input[name="password"]', '1');
    await page.selectOption('select[name="chinhanh"]', 'BENTHANH');
    // Chờ navigation sau click submit — form action=/login → 302 → GET /
    await Promise.all([
      page.waitForURL(url => !url.pathname.startsWith('/login'), { timeout: 15000 }),
      page.click('button[type="submit"]'),
    ]);
    // Xác nhận đã đăng nhập bằng cách kiểm tra thông tin session hiển thị
    await expect(page.locator('body')).toContainText(/ChiNhanh|BENTHANH/i);
  });

  let createdSOTK = null;

  test('01. Mở TK: SP tự sinh SOTK atomic, form không truyền SOTK', async ({ page }) => {
    await page.goto('/taikhoan/mo');

    // SOTK input hiển thị placeholder "(Sẽ tự động sinh khi lưu)"
    const sotkInput = page.locator('input[name="SOTK"]');
    await expect(sotkInput).toHaveValue(/tự động sinh|Sẽ tự động/i);

    // Chọn KH BENTHANH đầu tiên (option đầu tiên khả dụng)
    await page.selectOption('select[name="CMND"]', { index: 1 });

    // Nhập số dư qua UI (test JS format: '500000' → '500.000')
    await page.fill('#SODU_DISPLAY', '500000');
    const soduDisplay = await page.inputValue('#SODU_DISPLAY');
    expect(soduDisplay).toMatch(/500[.,]000/); // JS format vi-VN

    const soduHidden = await page.inputValue('input[name="SODU"]');
    expect(soduHidden).toBe('500000'); // Hidden field vẫn là số nguyên

    const before = Number((await sql('ES-HAITD16\\SQL1',
      "SELECT COUNT(*) FROM TaiKhoan WHERE SOTK LIKE 'BT%'"))[0][0]);

    // Submit form
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/taikhoan/, { timeout: 8000 });

    // URL redirect chứa SOTK
    const url = page.url();
    const match = url.match(/(BT|TD)\d{7}/);
    expect(match, `URL không chứa SOTK: ${url}`).not.toBeNull();
    createdSOTK = match[0];
    console.log('  [INFO] SOTK vừa tạo:', createdSOTK);

    // Verify DB
    const after = Number((await sql('ES-HAITD16\\SQL1',
      "SELECT COUNT(*) FROM TaiKhoan WHERE SOTK LIKE 'BT%'"))[0][0]);
    expect(after).toBe(before + 1);

    const row = await sql('ES-HAITD16\\SQL1',
      `SELECT RTRIM(SOTK), SODU, RTRIM(MACN) FROM TaiKhoan WHERE RTRIM(SOTK)='${createdSOTK}'`);
    expect(row.length).toBe(1);
    expect(Number(row[0][1])).toBe(500000);
    expect(row[0][2]).toBe('BENTHANH');
  });

  test('02. Đóng TK: SP_DongTaiKhoan chặn khi SODU>0 (RF-B guard G2)', async ({ page }) => {
    // Dùng TK BT0000006 luôn có SODU=500,000 sẵn
    await page.goto('/taikhoan');

    // Tìm nút đóng cho BT0000006. Route redirect với error nếu SODU khác 0.
    // Giả lập submit trực tiếp form dong (nhanh hơn tìm button DOM)
    const resp = await page.request.post('/taikhoan/dong', {
      form: { SOTK: 'BT0000006' },
      maxRedirects: 0,
      failOnStatusCode: false,
    });
    expect(resp.status()).toBe(302);
    const loc = decodeURIComponent(resp.headers()['location'] || '');
    expect(loc).toContain('error');
    expect(loc).toMatch(/số dư khác 0|số dư/);
  });

  test('03. Đóng TK: SP_DongTaiKhoan positive - TK vừa tạo được đóng khi SODU=0', async ({ page }) => {
    // Tạo TK mới với SODU=0 (dùng sqlcmd để nhanh hơn qua UI)
    const create = (await sql('ES-HAITD16\\SQL1',
      "EXEC sp_MoTaiKhoan @CMND='1111111111', @SODU=0, @MACN='BENTHANH'"))[0][0];
    expect(create).toMatch(/BT\d{7}/);
    const tempSOTK = create;

    // Đóng qua UI
    const resp = await page.request.post('/taikhoan/dong', {
      form: { SOTK: tempSOTK },
      maxRedirects: 0,
      failOnStatusCode: false,
    });
    expect(resp.status()).toBe(302);
    const loc = decodeURIComponent(resp.headers()['location'] || '');
    expect(loc).toContain('success');
    expect(loc).toContain(tempSOTK);

    // Verify DB đã xóa
    const cnt = Number((await sql('ES-HAITD16\\SQL1',
      `SELECT COUNT(*) FROM TaiKhoan WHERE RTRIM(SOTK)='${tempSOTK}'`))[0][0]);
    expect(cnt).toBe(0);
  });

  test('04. Đóng TK: SP_DongTaiKhoan chặn cross-branch (RF-B guard G3)', async ({ page }) => {
    // Tạo TK TANDINH SODU=0 để test guard G3
    const created = (await sql('ES-HAITD16\\SQL2',
      "EXEC sp_MoTaiKhoan @CMND='2222222222', @SODU=0, @MACN='TANDINH'"))[0][0];
    const tdSOTK = created;

    // Poll SQL1 chờ merge replication sync TK về (up to 30s)
    let synced = false;
    for (let i = 0; i < 30; i++) {
      const cnt = Number((await sql('ES-HAITD16\\SQL1',
        `SELECT COUNT(*) FROM TaiKhoan WHERE RTRIM(SOTK)='${tdSOTK}'`))[0][0]);
      if (cnt > 0) { synced = true; break; }
      await new Promise(r => setTimeout(r, 1000));
    }

    try {
      expect(synced, `TK ${tdSOTK} không sync từ SQL2 về SQL1 trong 30s (merge lag)`).toBe(true);

      // NV BT001 login BENTHANH thử đóng TK TANDINH → phải bị chặn
      const resp = await page.request.post('/taikhoan/dong', {
        form: { SOTK: tdSOTK },
        maxRedirects: 0,
        failOnStatusCode: false,
      });
      expect(resp.status()).toBe(302);
      const loc = decodeURIComponent(resp.headers()['location'] || '');
      expect(loc).toContain('error');
      expect(loc).toMatch(/chi nhánh sở hữu|Chỉ nhân viên/);
    } finally {
      // Cleanup dù test có fail
      await sql('ES-HAITD16\\SQL2', `DELETE FROM TaiKhoan WHERE RTRIM(SOTK)='${tdSOTK}'`);
      await sql('ES-HAITD16\\SQL1', `DELETE FROM TaiKhoan WHERE RTRIM(SOTK)='${tdSOTK}'`);
    }
  });
});
