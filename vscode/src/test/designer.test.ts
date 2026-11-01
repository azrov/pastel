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

test('a property the .pform does not set shows its default; Name can be changed', () => {
  post({
    type: 'select', name: 'Ok', names: ['Ok'], className: 'TButton', isRoot: false, handlers: [],
    props: [
      { name: 'Enabled', type: 'boolean', doc: '', default: 'True' },
      { name: 'Style', type: 'enum', values: ['Primary', 'Secondary'], doc: '', default: 'Primary' },
      { name: 'Width', type: 'integer', doc: '', default: '0' },
    ],
  });
  const en = doc.querySelector('[data-prop="Enabled"]');
  assert.strictEqual(en.checked, true, 'not set: enabled, like the running app');
  en.checked = true;
  en.dispatchEvent(new w.Event('change'));
  assert.strictEqual(last('setProp').value, null, 'the default is not written into the .pform');
  en.checked = false;
  en.dispatchEvent(new w.Event('change'));
  assert.strictEqual(last('setProp').value, 'False');
  assert.ok(doc.querySelector('[data-prop="Style"]').options[0].text.includes('Primary'));
  assert.strictEqual(doc.querySelector('[data-prop="Width"]').placeholder, '0');
  const nm = doc.querySelector('[data-prop="Name"]');
  assert.strictEqual(nm.value, 'Ok');
  nm.value = 'SaveButton';
  nm.dispatchEvent(new w.Event('change'));
  assert.deepStrictEqual(last('rename'), { type: 'rename', name: 'Ok', newName: 'SaveButton' });
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

test('a Flow form offers to place its controls freely, where they are now', () => {
  assert.ok(doc.getElementById('flowBanner').classList.contains('on'), 'the banner is shown');
  doc.getElementById('makeFree').click();
  assert.deepStrictEqual(last('makeFree'), { type: 'makeFree', name: 'HomeForm', items: [
    { name: 'Buttons', left: 20, top: 20, width: 360, height: 40 },
    { name: 'Info', left: 20, top: 80, width: 360 },
  ] });
});

// ---- a form with Layout = Free, like a Delphi form ----
const free = {
  width: 400, height: 300, controls: [
    { name: 'LoginForm', class: 'TForm', parent: '', x: 0, y: 0, w: 400, h: 300, container: true, row: false, free: true, visible: true },
    { name: 'NameEdit', class: 'TEdit', parent: 'LoginForm', x: 16, y: 16, w: 200, h: 32, container: false, row: false, visible: true },
    { name: 'OkButton', class: 'TButton', parent: 'LoginForm', x: 16, y: 64, w: 80, h: 40, container: false, row: false, visible: true },
    { name: 'Box', class: 'TPanel', parent: 'LoginForm', x: 200, y: 120, w: 160, h: 120, container: true, row: false, free: true, visible: true },
    { name: 'Bar', class: 'TPanel', parent: 'LoginForm', x: 0, y: 260, w: 400, h: 40, container: true, row: false, free: true, dock: true, visible: true },
  ],
};

test('free layout: a control is dragged to a place on the grid', () => {
  post({ type: 'render', data: '', layout: free, file: 'Login.pform', title: 'Sign in' });
  assert.strictEqual(doc.getElementById('wtitle').textContent, 'Sign in', 'the window frame shows the title');
  assert.ok(!doc.getElementById('flowBanner').classList.contains('on'), 'no banner on a free form');
  sent.length = 0;
  mouse(stage, 'mousedown', 20, 70);
  mouse(w, 'mouseup', 20, 70);
  mouse(stage, 'mousedown', 20, 70);
  mouse(stage, 'mousemove', 60, 90);
  mouse(stage, 'mousemove', 71, 93);
  assert.ok(doc.querySelector('.ghostbox'), 'where it will go is shown');
  mouse(w, 'mouseup', 71, 93);
  assert.deepStrictEqual(last('place'), { type: 'place', parent: 'LoginForm', items: [{ name: 'OkButton', left: 64, top: 88 }] },
    '16 + 51 = 67 snaps to 64; 64 + 23 = 87 snaps to 88');
});

test('free layout: dragged into a panel, the place is inside it', () => {
  sent.length = 0;
  mouse(stage, 'mousedown', 20, 70);
  mouse(stage, 'mousemove', 220, 150);
  mouse(stage, 'mousemove', 230, 150);
  mouse(w, 'mouseup', 230, 150);
  assert.deepStrictEqual(last('place'), { type: 'place', parent: 'Box', items: [{ name: 'OkButton', left: 24, top: 24 }] });
});

test('free layout: the grips resize the control', () => {
  post({ type: 'select', name: 'OkButton', names: ['OkButton'], className: 'TButton', isRoot: false, handlers: [], props: [] });
  const grips = [...doc.querySelectorAll('.handle')];
  assert.strictEqual(grips.length, 8, 'eight grips, like Delphi');
  const se = grips.find((g: any) => g.dataset.dir === 'se');
  sent.length = 0;
  se.dispatchEvent(new w.MouseEvent('mousedown', { clientX: 96, clientY: 104, button: 0, bubbles: true }));
  mouse(stage, 'mousemove', 137, 111);
  mouse(w, 'mouseup', 137, 111);
  assert.deepStrictEqual(last('place'), { type: 'place', parent: null,
    items: [{ name: 'OkButton', width: 120, height: 48, left: 16, top: 64 }] });
});

test('free layout: Ctrl+arrows move by a pixel, Shift+arrows resize', () => {
  sent.length = 0;
  w.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'ArrowRight', ctrlKey: true }));
  assert.deepStrictEqual(last('place').items, [{ name: 'OkButton', left: 17, top: 64 }]);
  w.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'ArrowDown', shiftKey: true }));
  assert.deepStrictEqual(last('place').items, [{ name: 'OkButton', height: 41 }]);
});

test('free layout: a control from the palette goes where it is dropped', () => {
  sent.length = 0;
  const drop = new w.Event('drop', { bubbles: true }) as any;
  drop.clientX = 250; drop.clientY = 13;
  drop.dataTransfer = { getData: () => 'TButton' };
  stage.dispatchEvent(drop);
  assert.deepStrictEqual(last('add'), { type: 'add', className: 'TButton', parent: 'LoginForm', index: 9999, left: 248, top: 16 });
});

test('free layout: several controls are aligned to the one chosen last', () => {
  post({ type: 'select', name: 'NameEdit', names: ['OkButton', 'NameEdit'], className: '', isRoot: false, handlers: [], props: [], sameParent: true });
  const right = doc.querySelector('[data-align="right"]');
  assert.ok(right, 'the align tools are shown');
  right.click();
  assert.deepStrictEqual(last('place').items, [
    { name: 'OkButton', left: 136, top: 64 },
    { name: 'NameEdit', left: 16, top: 16 },
  ]);
});

test('the palette is grouped and can be searched; non-visual components sit in the tray', () => {
  post({ type: 'schema', controls: [{ name: 'TButton' }, { name: 'TPanel', container: true }, { name: 'TGrid' }, { name: 'TTimer', nonvisual: true }] });
  const cats = [...doc.querySelectorAll('.cat')].map((c: any) => c.textContent);
  assert.deepStrictEqual(cats, ['Standard', 'Lists and tables', 'Non-visual']);
  const search = doc.getElementById('paletteSearch');
  search.value = 'gri';
  search.dispatchEvent(new w.Event('input'));
  assert.deepStrictEqual([...doc.querySelectorAll('.chip:not(.hidden)')].map((c: any) => c.textContent), ['Grid']);
  const grid = doc.querySelector('.chip:not(.hidden)');
  assert.ok(grid.title.includes('Windows ✓') && grid.title.includes('Linux ✓') && grid.title.includes('Android: coming'), grid.title);
  post({ type: 'tree', items: [{ name: 'LoginForm', className: 'TLoginForm', depth: 0 }, { name: 'Tick', className: 'TTimer', depth: 1, nonvisual: true }] });
  const nv = doc.querySelector('#tray .nv');
  assert.ok(nv && nv.textContent.includes('Tick'));
  nv.click();
  assert.deepStrictEqual(last('select'), { type: 'select', name: 'Tick', names: ['Tick'] });
});

test('the inspector: events on their own tab, Anchors as check boxes, search', () => {
  post({
    type: 'select', name: 'OkButton', names: ['OkButton'], className: 'TButton', isRoot: false, handlers: [],
    props: [
      { name: 'Anchors', type: 'set', values: ['Left', 'Top', 'Right', 'Bottom'], default: 'Left, Top', doc: '' },
      { name: 'Text', type: 'string', doc: '', value: 'OK' },
      { name: 'OnClick', type: 'event', doc: '', signature: '(Sender: TObject)' },
    ],
  });
  assert.ok(doc.getElementById('props').classList.contains('props'));
  doc.getElementById('tabEvents').click();
  assert.ok(doc.getElementById('props').classList.contains('events'), 'the Events tab');
  doc.getElementById('tabProps').click();
  const boxes = [...doc.querySelectorAll('[data-prop="Anchors"] input')];
  assert.deepStrictEqual(boxes.map((b: any) => b.checked), [true, true, false, false], 'the default: Left, Top');
  boxes[2].checked = true;
  boxes[2].dispatchEvent(new w.Event('change'));
  assert.deepStrictEqual(last('setProp'), { type: 'setProp', name: 'OkButton', names: ['OkButton'], prop: 'Anchors', propType: 'set', value: '[Left, Top, Right]' });
  const q = doc.getElementById('propSearch');
  q.value = 'tex';
  q.dispatchEvent(new w.Event('input'));
  assert.ok(doc.querySelector('[data-for="Anchors"]').parentElement.classList.contains('hidden'));
  assert.ok(!doc.querySelector('[data-for="Text"]').parentElement.classList.contains('hidden'));
  q.value = '';
  q.dispatchEvent(new w.Event('input'));
});

console.log(`designer: ${passed} passed`);
