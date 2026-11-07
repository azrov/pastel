// Tests for projectinfo.ts: which program F9 runs. Run: npm test
import * as assert from 'assert';
import { defaultPlatform, parseProjectInfo, platformCommand, pngSize, runCandidates } from '../projectinfo';

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

const lib = parseProjectInfo('/w/core', '[project]\nname = "core"\ntype = "lib"\n');
const desk = parseProjectInfo('/w/desk', '# app\n[project]\nname = "desk"\ntitle = "Desk"\ntype = "app"\n\n' +
  '[dependencies]\ncore = { path = "../core" }\nui = { path = "/w/ui" }\n');
const api = parseProjectInfo('/w/api', '[project]\nname = "api"\ntype = "service"\n[dependencies]\ncore = { path = "../core" }\n');
const tool = parseProjectInfo('/w/tool', '[project]\nname = "tool"\n');
const other = parseProjectInfo('/w/other', '[project]\nname = "other"\ntype = "lib"\n');
const all = [lib, desk, api, tool, other];

test('reads the kind, the name and the dependencies', () => {
  assert.strictEqual(desk.kind, 'app');
  assert.strictEqual(desk.name, 'desk');
  assert.deepStrictEqual(desk.dependsOn, ['/w/core', '/w/ui']);
  assert.strictEqual(tool.kind, 'console', 'console when type is missing');
});

test('a program runs itself', () => {
  assert.deepStrictEqual(runCandidates(all, tool).map(p => p.name), ['tool']);
});

test('a library runs the programs that use it', () => {
  assert.deepStrictEqual(runCandidates(all, lib).map(p => p.name), ['desk', 'api']);
});

test('a library nobody uses offers every program', () => {
  assert.deepStrictEqual(runCandidates(all, other).map(p => p.name), ['desk', 'api', 'tool']);
});

test('only libraries: nothing to run', () => {
  assert.deepStrictEqual(runCandidates([lib, other], lib), []);
});

test('no active file: every program', () => {
  assert.strictEqual(runCandidates(all, undefined).length, 3);
});

test('the platform F9 uses: this computer, or Android for a phone app', () => {
  const phone = parseProjectInfo('/w/phone', '[project]\nname = "phone"\ntype = "app"\n\n[targets]\nplatforms = ["android"]\n');
  assert.deepStrictEqual(phone.platforms, ['android']);
  assert.strictEqual(defaultPlatform(phone, 'linux'), 'android');
  const both = parseProjectInfo('/w/b', '[project]\ntype = "app"\n[targets]\nplatforms = ["linux", "windows", "android"]\n');
  assert.strictEqual(defaultPlatform(both, 'linux'), 'linux');
  assert.strictEqual(defaultPlatform(both, 'windows'), 'windows');
  assert.strictEqual(defaultPlatform(tool, 'linux'), 'linux', 'no platforms listed');
});

test('F9 and Ctrl+F9 for each platform', () => {
  assert.deepStrictEqual(platformCommand('run', 'android', 'linux').args, ['run', '--target', 'android']);
  assert.deepStrictEqual(platformCommand('build', 'android', 'linux').args, ['package', 'apk'], 'one .apk for every CPU');
  assert.deepStrictEqual(platformCommand('build', 'android-arm', 'linux').args, ['package', 'apk', '--target', 'android-arm']);
  assert.deepStrictEqual(platformCommand('run', 'linux', 'linux', true).args, ['run', '--release']);
  const win = platformCommand('run', 'windows', 'linux');
  assert.deepStrictEqual(win.args, ['build', '--target', 'windows']);
  assert.ok(win.note && win.note.includes('cannot run'), 'a Windows program is built, not run, on Linux');
});

test('the size of a PNG', () => {
  const png = Buffer.alloc(24);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png);
  png.write('IHDR', 12, 'ascii');
  png.writeUInt32BE(512, 16);
  png.writeUInt32BE(256, 20);
  assert.deepStrictEqual(pngSize(png), { width: 512, height: 256 });
  assert.strictEqual(pngSize(Buffer.from('not a picture at all, not at all')), undefined);
});

console.log(`projectinfo: ${passed} passed`);
