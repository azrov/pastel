// Runs the designer's web page in jsdom and checks that mouse and panel
// actions send the right messages to the extension. Run: npm test
import * as assert from 'assert';
import { JSDOM } from 'jsdom';
import { designerHtml } from '../designerHtml';

let passed = 0;
function test(name: string, fn: () => void): void {
  try {
    fn();
    passed++;
  } catch (e) {
    console.error('FAIL:', name);
    console.error(e);
    process.exitCode = 1;
  }
}

const sent: any[] = [];
const dom = new JSDOM(designerHtml('n'), {
  runScripts: 'dangerously',
  beforeParse(window: any) {
    window.acquireVsCodeApi = () => ({ postMessage: (m: unknown) => sent.push(m) });
    // jsdom has no layout: the picture is shown at its natural size, at 0,0
    Object.defineProperty(window.HTMLImageElement.prototype, 'clientWidth', { get: () => 400 });
  },
});
const w = dom.window as any;
const doc = w.document;
const post = (data: unknown) => w.dispatchEvent(new w.MessageEvent('message', { data }));
const mouse = (target: any, type: string, x: number, y: number) =>
  target.dispatchEvent(new w.MouseEvent(type, { clientX: x, clientY: y, button: 0, bubbles: true }));
// messages come from the page's own realm; copy them so deepStrictEqual compares plain objects
const last = (type: string) => {
  const m = [...sent].reverse().find(x => x.type === type);
  return m === undefined ? undefined : JSON.parse(JSON.stringify(m));
};

const layout = {
  width: 400, height: 300, controls: [
    { name: 'HomeForm', class: 'TForm', parent: '', x: 0, y: 0, w: 400, h: 300, container: true, row: false, visible: true },
    { name: 'Buttons', class: 'TRow', parent: 'HomeForm', x: 20, y: 20, w: 360, h: 40, container: true, row: true, visible: true },
    { name: 'Ok', class: 'TButton', parent: 'Buttons', x: 20, y: 20, w: 80, h: 40, container: false, row: false, visible: true },
    { name: 'Cancel', class: 'TButton', parent: 'Buttons', x: 110, y: 20, w: 80, h: 40, container: false, row: false, visible: true },
    { name: 'Info', class: 'TLabel', parent: 'HomeForm', x: 20, y: 80, w: 360, h: 20, container: false, row: false, visible: true },
  ],
};

post({ type: 'schema', controls: [{ name: 'TButton', container: false }, { name: 'TRow', container: true }] });
post({ type: 'render', data: '', layout, file: 'Home.pform' });
const stage = doc.getElementById('stage');

test('toolbox shows the controls', () => {
  const chips = [...doc.querySelectorAll('.chip')].map((c: any) => c.textContent);
  assert.deepStrictEqual(chips, ['Button', 'Row']);
});

test('clicking a control selects it', () => {
  mouse(stage, 'mousedown', 50, 30);
  mouse(w, 'mouseup', 50, 30);
  assert.deepStrictEqual(last('select'), { type: 'select', name: 'Ok', names: ['Ok'] });
});

test('dragging a control moves it (into the form, after Info)', () => {
  sent.length = 0;
  mouse(stage, 'mousedown', 50, 30);
  mouse(stage, 'mousemove', 60, 150);
  mouse(stage, 'mousemove', 70, 200);
  assert.ok(doc.querySelector('.drop'), 'a drop marker is shown');
  mouse(w, 'mouseup', 70, 200);
  assert.deepStrictEqual(last('move'), { type: 'move', name: 'Ok', parent: 'HomeForm', index: 2 });
});

test('dragging inside a row reorders by x position', () => {
  sent.length = 0;
  mouse(stage, 'mousedown', 50, 30);
  mouse(stage, 'mousemove', 170, 35);
  mouse(w, 'mouseup', 170, 35);
  assert.deepStrictEqual(last('move'), { type: 'move', name: 'Ok', parent: 'Buttons', index: 1 });
});

test('a small mouse movement is a click, not a move', () => {
  sent.length = 0;
  mouse(stage, 'mousedown', 150, 30);
  mouse(stage, 'mousemove', 152, 31);
  mouse(w, 'mouseup', 152, 31);
  assert.strictEqual(last('move'), undefined);
  assert.deepStrictEqual(last('select'), { type: 'select', name: 'Cancel', names: ['Cancel'] });
});

test('property panel sends edits', () => {
  post({
    type: 'select', name: 'Cancel', names: ['Cancel'], className: 'TButton', isRoot: false, handlers: ['OkClick'],
    props: [
      { name: 'Text', type: 'string', doc: '', value: 'Cancel' },
      { name: 'Style', type: 'enum', values: ['Primary', 'Secondary'], doc: '' },
      { name: 'Visible', type: 'boolean', doc: '', value: 'True' },
      { name: 'OnClick', type: 'event', doc: '', signature: '(Sender: TObject)' },
    ],
  });
  const text = doc.querySelector('[data-prop="Text"]');
  assert.strictEqual(text.value, 'Cancel');
  text.value = 'Close';
  text.dispatchEvent(new w.Event('change'));
  assert.deepStrictEqual(last('setProp'), { type: 'setProp', name: 'Cancel', names: ['Cancel'], prop: 'Text', propType: 'string', value: 'Close' });

  const style = doc.querySelector('[data-prop="Style"]');
  style.value = 'Secondary';
  style.dispatchEvent(new w.Event('change'));
  assert.strictEqual(last('setProp').value, 'Secondary');

  const vis = doc.querySelector('[data-prop="Visible"]');
  vis.checked = false;
  vis.dispatchEvent(new w.Event('change'));
  assert.strictEqual(last('setProp').value, 'False');

  doc.querySelector('[data-prop="OnClick"] button').click();
  assert.deepStrictEqual(last('code'), {
    type: 'code', name: 'Cancel', prop: 'OnClick', handler: '', signature: '(Sender: TObject)',
  });
  assert.ok(doc.querySelector('.selected .tag').textContent.includes('Cancel: TButton'));
});

test('clicking a toolbox chip adds after the selected control', () => {
  doc.querySelectorAll('.chip')[0].click();
  assert.deepStrictEqual(last('add'), { type: 'add', className: 'TButton', parent: 'Buttons', index: 2 });
});

test('Delete key removes the selected control', () => {
  doc.body.focus();
  w.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Delete' }));
  assert.deepStrictEqual(last('delete'), { type: 'delete', name: 'Cancel', names: ['Cancel'] });
});

test('Ctrl+click selects several; their common properties go to all', () => {
  sent.length = 0;
  mouse(stage, 'mousedown', 50, 30);
  mouse(w, 'mouseup', 50, 30);
  stage.dispatchEvent(new w.MouseEvent('mousedown', { clientX: 150, clientY: 30, button: 0, ctrlKey: true, bubbles: true }));
  mouse(w, 'mouseup', 150, 30);
  assert.deepStrictEqual(last('select'), { type: 'select', name: 'Cancel', names: ['Ok', 'Cancel'] });
  assert.strictEqual(doc.querySelectorAll('.selected').length, 2);
  post({
    type: 'select', name: 'Cancel', names: ['Ok', 'Cancel'], className: '', isRoot: false, handlers: [], sameParent: true,
    props: [{ name: 'Style', type: 'enum', values: ['Primary', 'Secondary'], doc: '', mixed: true }],
  });
  assert.ok(doc.querySelector('#props h3').textContent.includes('2 controls'));
  const style = doc.querySelector('[data-prop="Style"]');
  assert.strictEqual(style.options[0].text, '(several values)');
  style.value = 'Secondary';
  style.dispatchEvent(new w.Event('change'));
  assert.deepStrictEqual(last('setProp').names, ['Ok', 'Cancel']);
  const row = [...doc.querySelectorAll('#props button')].find((b: any) => b.textContent.includes('Row'));
  row.click();
  assert.deepStrictEqual(last('wrap'), { type: 'wrap', names: ['Ok', 'Cancel'], className: 'TRow' });
  w.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'c', ctrlKey: true }));
  assert.deepStrictEqual(last('copy'), { type: 'copy', name: 'Cancel', names: ['Ok', 'Cancel'] });
  w.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
  assert.deepStrictEqual(last('select').names, ['Cancel'], 'Escape keeps one');
});

test('Alt+Up moves the control earlier', () => {
  w.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'ArrowUp', altKey: true }));
  assert.deepStrictEqual(last('moveSibling'), { type: 'moveSibling', name: 'Cancel', delta: -1 });
});

test('the structure lists every object, also the non-visual ones', () => {
  post({ type: 'tree', items: [
    { name: 'HomeForm', className: 'THomeForm', depth: 0 },
    { name: 'Tick', className: 'TTimer', depth: 1, nonvisual: true },
    { name: 'Buttons', className: 'TRow', depth: 1 },
  ] });
  const items = [...doc.querySelectorAll('#tree .item')];
  assert.strictEqual(items.length, 3);
  assert.ok(items[1].classList.contains('nv'));
  items[1].click();
  assert.deepStrictEqual(last('select'), { type: 'select', name: 'Tick', names: ['Tick'] });
});

test('what pastel check says is drawn on the control', () => {
  post({ type: 'issues', items: [{ name: 'Buttons', severity: 'warning', message: 'Buttons: its controls need 500 pixels', line: 7 }] });
  assert.ok(doc.querySelector('.box.issue.warning'), 'outlined on the form');
  const item = doc.querySelector('#issues .warning');
  assert.ok(item.textContent.includes('line 7: Buttons: its controls need'));
  item.click();
  assert.deepStrictEqual(last('select'), { type: 'select', name: 'Buttons', names: ['Buttons'] });
  assert.ok(doc.querySelector('#tree .bad'), 'marked in the structure');
});

test('errors are shown', () => {
  post({ type: 'error', message: 'Home.pform(3) Error: bad' });
  assert.ok(doc.body.classList.contains('has-error'));
  assert.strictEqual(doc.getElementById('error').textContent, 'Home.pform(3) Error: bad');
});

console.log(`designer: ${passed} passed`);
