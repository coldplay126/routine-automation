const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const page = fs.readFileSync(process.argv[2], 'utf8');
const data = JSON.parse(page.match(/<script id="review-data" type="application\/json">([^\n]+)<\/script>/)[1]);
const initial = page.match(/<div id="preview">([\s\S]*?)<\/div><\/aside>/)[1];
const expectedText = fs.readFileSync(process.argv[3], 'utf8').replace(/\n$/, '');
const expectedHTML = fs.readFileSync(process.argv[4], 'utf8').replace(/\n$/, '');
const normalize = html => html.replace(/&quot;/g, '"').replace(/&#39;/g, "'");
const elements = new Map();
function element(id) {
  if (!elements.has(id)) elements.set(id, {textContent: id === 'review-data' ? JSON.stringify(data) : '', innerHTML: '',
    handlers: {}, addEventListener(event, handler) { this.handlers[event] = handler; }});
  return elements.get(id);
}
const copied = {};
const context = vm.createContext({document: {getElementById: element, querySelectorAll: () => []},
  Blob, ClipboardItem: class { constructor(values) { this.values = values; } },
  navigator: {clipboard: {write: async items => {
    for (const [type, value] of Object.entries(items[0].values)) copied[type] = await value.text();
  }}}, setTimeout: () => 1, clearTimeout: () => {}});
vm.runInContext(page.match(/<script>\n([\s\S]*?)<\/script>/)[1], context);
assert.equal(normalize(initial), normalize(expectedHTML), '초기 HTML과 저장된 HTML 불일치');
assert.equal(vm.runInContext('render().text', context), expectedText, 'JS 텍스트와 저장된 텍스트 불일치');
assert.equal(normalize(element('preview').innerHTML), normalize(expectedHTML), 'JS HTML과 저장된 HTML 불일치');
async function verify() {
  await element('copy').handlers.click();
  assert.equal(copied['text/plain'], expectedText, '복사 텍스트 형식 불일치');
  assert.equal(normalize(copied['text/html']), normalize(expectedHTML), '복사 HTML 형식 불일치');
  if (data.settings.format.max_items_per_section !== null) {
    const omitted = data.items.find(item => item.omitted);
    assert.ok(omitted, '상한 검증용 생략 항목 없음');
    const id = data.items.indexOf(omitted);
    vm.runInContext(`data.items[${id}].selected=true; render()`, context);
    assert.match(element('selection-count').textContent, /생략됨 1개/, '선택 초과 항목을 조용히 숨김');
    const first = data.items.findIndex(item => item.selected && item.section === omitted.section && !item.disabled);
    vm.runInContext(`data.items[${first}].selected=false; render()`, context);
    assert.ok(vm.runInContext('render().text', context).includes(omitted.text), '다른 항목 해제 후 생략 항목 복원 실패');
  }
  console.log('PASS: 초기 HTML·JS 렌더·복사·상한 선택 회귀');
}
verify().catch(error => { console.error(error); process.exitCode = 1; });
