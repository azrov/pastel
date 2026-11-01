// Runs the Welcome page and the New Project wizard in jsdom. Run: npm test
import * as assert from 'assert';
import { JSDOM } from 'jsdom';
import { validProjectName, welcomeHtml, withPlatforms } from '../welcomeHtml';

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
const dom = new JSDOM(welcomeHtml('n', {
  recent: [{ name: 'salon-desk', path: '/home/a/salon-desk', kind: 'app' }], location: '/home/a/PastelProjects', version: '1.4.0',
}), {
  runScripts: 'dangerously',
  beforeParse(window: any) {
    window.acquireVsCodeApi = () => ({ postMessage: (m: unknown) => sent.push(m) });
  },
});
const w = dom.window as any;
const doc = w.document;
const $ = (id: string) => doc.getElementById(id);
const last = (type: string) => {
  const m = [...sent].reverse().find(x => x.type === type);
  return m === undefined ? undefined : JSON.parse(JSON.stringify(m));
};

test('the first page lists the recent projects', () => {
  assert.ok(!$('projects').hidden);
  const p = doc.querySelector('#recent .p');
  assert.ok(p.textContent.includes('salon-desk') && p.textContent.includes('app'));
  p.click();
  assert.deepStrictEqual(last('openRecent'), { type: 'openRecent', path: '/home/a/salon-desk' });
});

test('New Project shows the templates by category; Android is coming', () => {
  $('newProject').click();
  assert.ok(!$('wizard1').hidden && $('projects').hidden);
  const cats = [...doc.querySelectorAll('#cats button')].map((b: any) => b.textContent);
  assert.deepStrictEqual(cats, ['Desktop', 'Console', 'Server', 'Library', 'Mobile']);
  assert.deepStrictEqual([...doc.querySelectorAll('.card')].map((c: any) => c.dataset.kind), ['app']);
  assert.ok($('next').disabled, 'nothing chosen yet');
  doc.querySelectorAll('#cats button')[2].click();
  assert.deepStrictEqual([...doc.querySelectorAll('.card')].map((c: any) => c.dataset.kind), ['api', 'service']);
  doc.querySelectorAll('#cats button')[4].click();
  const android = doc.querySelector('.card');
  assert.ok(android.classList.contains('soon') && android.textContent.includes('Coming in Pastel 1.5'));
  android.click();
  assert.ok($('next').disabled, 'it cannot be chosen yet');
});

test('a desktop app: name, folder, platforms, Create', () => {
  doc.querySelectorAll('#cats button')[0].click();
  doc.querySelector('.card').click();
  assert.ok(!$('next').disabled);
  $('next').click();
  assert.ok(!$('wizard2').hidden);
  assert.strictEqual($('chosenTitle').textContent, 'Desktop App');
  assert.strictEqual($('name').value, 'my-app');
  assert.strictEqual($('where').textContent, 'The project goes into /home/a/PastelProjects/my-app');
  $('name').value = '1abc';
  $('name').dispatchEvent(new w.Event('input'));
  assert.ok(!$('nameBad').hidden && $('finish').disabled, 'a name must start with a letter');
  $('name').value = 'shop';
  $('name').dispatchEvent(new w.Event('input'));
  assert.ok($('nameBad').hidden && !$('finish').disabled);
  $('browse').click();
  assert.strictEqual(last('browse').type, 'browse');
  w.dispatchEvent(new w.MessageEvent('message', { data: { type: 'location', location: 'C:\\Users\\a\\Projects' } }));
  assert.strictEqual($('where').textContent, 'The project goes into C:\\Users\\a\\Projects\\shop', 'Windows paths');
  doc.querySelectorAll('#platforms input')[1].checked = false;
  $('finish').click();
  assert.deepStrictEqual(last('create'), { type: 'create', kind: 'app', name: 'shop', location: 'C:\\Users\\a\\Projects', platforms: ['Windows'] });
  w.dispatchEvent(new w.MessageEvent('message', { data: { type: 'failed', message: 'shop exists already.' } }));
  assert.strictEqual($('msg').textContent, 'shop exists already.');
  assert.ok(!$('finish').disabled, 'it can be tried again');
});

test('names and platforms', () => {
  assert.strictEqual(validProjectName('my-app'), undefined);
  assert.ok(validProjectName('my app'));
  assert.strictEqual(withPlatforms('[targets]\nplatforms = ["linux", "windows"]\n', ['Windows']), '[targets]\nplatforms = ["windows"]\n');
});

console.log(`welcome: ${passed} passed`);
