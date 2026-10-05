const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
let driver;
try {
  driver = require(process.env.REVIEW_BROWSER_DRIVER || 'playwright-core');
} catch {
  console.log('SKIP: 검토 브라우저 드라이버 없음 (REVIEW_BROWSER_DRIVER 지정 가능)');
  process.exit(77);
}
async function verify() {
  const executablePath = process.env.REVIEW_BROWSER_CHROMIUM || driver.chromium.executablePath();
  if (!fs.existsSync(executablePath)) {
    console.log('SKIP: headless Chromium 없음 (REVIEW_BROWSER_CHROMIUM 지정 가능)');
    process.exitCode = 77;
    return;
  }
  const browser = await driver.chromium.launch({headless: true, executablePath,
    args: ['--disable-features=MacAppCodeSignClone', '--disable-background-networking']});
  try {
    const context = await browser.newContext({viewport: {width: 1440, height: 1100}});
    const page = await context.newPage();
    const errors = [], requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (/^https?:/.test(request.url())) requests.push(request.url()); });
    await page.goto(pathToFileURL(process.argv[2]).href);
    assert.equal(await page.evaluate(() => document.scripts.length), 2, '주석·script 페이로드가 실행 스크립트를 삼켰습니다');
    assert.equal(await page.evaluate(() => window.fixtureAttack), undefined);
    assert.equal(await page.evaluate(() => render().text), fs.readFileSync(process.argv[3], 'utf8').replace(/\n$/, ''), 'JS 미리보기 텍스트가 저장된 초안과 다릅니다');
    const actualHTML = await page.evaluate(() => preview.innerHTML);
    const expectedHTML = await page.evaluate(expected => {
      const element = document.createElement('div'); element.innerHTML = expected.replace(/\n$/, ''); return element.innerHTML;
    }, fs.readFileSync(process.argv[4], 'utf8'));
    assert.equal(actualHTML, expectedHTML, 'JS 미리보기 HTML이 저장된 초안과 다릅니다');
    if (process.argv[5] === '--format-only') {
      assert.equal(await page.evaluate(() => format.layout), 'flat');
      await page.evaluate(() => {
        Object.defineProperty(navigator, 'clipboard', {configurable: true, value: {
          write: async items => { window.copied = {}; for (const type of items[0].types) window.copied[type] = await (await items[0].getType(type)).text(); }
        }});
      });
      await page.locator('#copy').click();
      await page.locator('#toast').filter({hasText: 'HTML과 텍스트를 복사'}).waitFor();
      assert.equal(await page.evaluate(() => window.copied['text/plain']), await page.evaluate(() => render().text));
      assert.equal(await page.evaluate(() => window.copied['text/html']), await page.evaluate(() => render().html));
      const first = await page.evaluate(() => data.items.findIndex(item => item.selected && !item.disabled));
      const text = await page.evaluate(id => data.items[id].text, first);
      await page.locator(`[data-select="${first}"]`).uncheck();
      assert.equal(await page.evaluate(value => render().text.includes(value), text), false);
      assert.deepEqual(requests, []); assert.deepEqual(errors, []);
      console.log('PASS: headless Chromium flat·커스텀 글머리·스냅샷·선택·복사 회귀');
      return;
    }
    const index = async topic => page.evaluate(value => data.items.findIndex(item => item.topic === value), topic);
    const first = await index('기능 점검'), edit = await index('리뷰 계획'), held = await index('보류 점검'), candidate = await index('결제 API 배포 완료');
    const todayHeld = await page.evaluate(() => data.items.findIndex(item => item.section === 'today' && item.held));
    assert.equal(await page.locator(`[data-select="${first}"]`).isChecked(), true);
    assert.equal(await page.locator(`[data-select="${candidate}"]`).isChecked(), false);
    assert.equal(await page.locator(`[data-select="${todayHeld}"]`).isDisabled(), true);
    assert.equal(await page.locator(`[data-select="${todayHeld}"]`).isChecked(), false);
    assert.equal(await page.evaluate(() => data.items.find(item => item.topic === '결제').reasons.length), 0);
    const shots = process.env.REVIEW_BROWSER_SHOTS;
    const screenshot = async name => {
      if (!shots) return;
      fs.mkdirSync(shots, {recursive: true}); await page.screenshot({path: path.join(shots, name), fullPage: true});
    };
    await screenshot('light-desktop.png');
    await page.locator(`[data-select="${first}"]`).focus();
    await page.keyboard.press('Space');
    assert.equal(await page.evaluate(() => render().text.includes('기능 점검')), false);
    await page.locator(`[data-edit="${edit}"]`).fill('  편집 한 줄\n다음 줄\n\n  ');
    assert.equal(await page.evaluate(id => data.items[id].text, edit), '편집 한 줄 다음 줄');
    assert.match(await page.evaluate(() => render().text), /편집 한 줄 다음 줄/);
    await page.locator(`[data-edit="${edit}"]`).fill('');
    assert.equal(await page.evaluate(() => render().text.includes('리뷰 계획')), false, '빈 문구 글머리가 남았습니다');
    await page.locator(`[data-edit="${edit}"]`).fill('리뷰를 확인하고 다음 작업 정리');
    await page.locator(`[data-select="${candidate}"]`).check();
    assert.match(await page.evaluate(() => render().text), /어제 작업한 내용[\s\S]*결제 API 배포 완료[\s\S]*오늘의 작업 계획/);
    assert.equal(await page.locator(`[data-select="${held}"]`).isChecked(), true);
    await page.evaluate(() => {
      Object.defineProperty(navigator, 'clipboard', {configurable: true, value: {
        write: async items => { window.copied = {}; for (const type of items[0].types) window.copied[type] = await (await items[0].getType(type)).text(); },
        writeText: async text => { window.copiedText = text; }
      }});
    });
    await page.locator('#copy').click();
    await page.locator('#toast').filter({hasText: 'HTML과 텍스트를 복사'}).waitFor();
    assert.equal(await page.evaluate(() => window.copied['text/plain']), await page.evaluate(() => render().text));
    assert.equal(await page.evaluate(() => window.copied['text/html']), await page.evaluate(() => render().html));
    await page.evaluate(() => { window.ClipboardItem = undefined; });
    await page.locator('#copy').click();
    await page.locator('#toast').filter({hasText: '텍스트를 복사'}).waitFor();
    assert.equal(await page.evaluate(() => window.copiedText), await page.evaluate(() => render().text));
    await page.evaluate(() => { navigator.clipboard.writeText = async () => { throw new Error('권한 거부 스텁'); }; });
    await page.locator('#copy').click();
    await page.locator('#toast').filter({hasText: '복사하지 못했습니다'}).waitFor();
    await screenshot('edited-desktop.png');
    await page.emulateMedia({colorScheme: 'dark'}); await screenshot('dark-desktop.png');
    await page.setViewportSize({width: 390, height: 844}); await screenshot('dark-mobile.png');
    assert.equal(await page.evaluate(() => getComputedStyle(document.querySelector('.layout')).gridTemplateColumns.split(' ').length), 1);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth), false);
    assert.deepEqual(requests, []); assert.deepEqual(errors, []);
    if (shots) fs.writeFileSync(path.join(shots, 'evidence.json'), JSON.stringify({
      initial_preview: '저장된 초안 텍스트/HTML과 JS render() 일치', parser_payload: '<!--<script> 비실행·스크립트 2개',
      edit_selection: '키보드 선택·편집 줄바꿈 정리·빈 항목 제외·오늘 보류 비활성 통과',
      clipboard: '실제 ClipboardItem/Blob, clipboard sink 스텁으로 HTML/text·폴백·실패 검증',
      external_requests: requests, page_errors: errors
    }, null, 2));
    if (process.env.REVIEW_BROWSER_SAMPLE_DIR) {
      fs.mkdirSync(process.env.REVIEW_BROWSER_SAMPLE_DIR, {recursive: true});
      const sample = path.join(process.env.REVIEW_BROWSER_SAMPLE_DIR, '2026-09-28.review.html');
      fs.copyFileSync(process.argv[2], sample); fs.chmodSync(sample, 0o600);
    }
    console.log('PASS: 실제 headless Chromium JS 트리·스냅샷·주입 경계·편집·복사 API·반응형 회귀');
  } finally {
    await browser.close();
  }
}
verify().catch(error => { console.error(error); process.exitCode = 1; });
