// Tests for projectinfo.ts: which program F9 runs. Run: npm test
import * as assert from 'assert';
import { parseProjectInfo, runCandidates } from '../projectinfo';

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

console.log(`projectinfo: ${passed} passed`);
