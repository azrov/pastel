// Tests for finding Pascal tests and reading "pastel test --json". Run: npm test
import * as assert from 'assert';
import { findTests, humanName, parseLocation, parseResults, suiteLabel } from '../testParse';

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

test('names like the runner prints them', () => {
  assert.strictEqual(humanName('GreetsByName'), 'greets by name');
  assert.strictEqual(humanName('ParsesHTTPHeaders'), 'parses HTTP headers');
  assert.strictEqual(humanName('Utf8_Text'), 'utf8 text');
  assert.strictEqual(suiteLabel('TGreetingTests'), 'Greeting');
  assert.strictEqual(suiteLabel('TJsonTest'), 'Json');
});

test('suites, published methods and Test() calls', () => {
  const src = [
    'unit Greeting_Test;',                                 // 0
    'interface',                                           // 1
    'type',                                                // 2
    '  TGreetingTests = class(TTestSuite)',                // 3
    '  private',                                           // 4
    '    procedure Helper;',                               // 5
    '  published',                                         // 6
    '    procedure GreetsByName;',                         // 7
    '    // procedure Commented;',                         // 8
    '    { procedure AlsoCommented; }',                    // 9
    '    procedure MentionsTheProgram;',                   // 10
    '  end;',                                              // 11
    'implementation',                                      // 12
    'procedure Loose; begin end;',                         // 13
    'initialization',                                      // 14
    "  RegisterTests(TGreetingTests);",                    // 15
    "  Test('it''s loose', @Loose);",                      // 16
    'end.',
  ].join('\n');
  const found = findTests(src);
  assert.strictEqual(found.suites.length, 1);
  assert.strictEqual(found.suites[0].label, 'Greeting');
  assert.deepStrictEqual(found.suites[0].tests.map(t => [t.id, t.label, t.line]), [
    ['TGreetingTests.GreetsByName', 'greets by name', 7],
    ['TGreetingTests.MentionsTheProgram', 'mentions the program', 10],
  ]);
  assert.deepStrictEqual(found.loose.map(t => [t.id, t.line]), [["it's loose", 16]]);
});

test('results after compiler output', () => {
  const out = '   Compiling 1 test unit(s)\n' +
    '[{"id":"TA.B","suite":"A","name":"b","method":"B","outcome":"failed","ms":3,"message":"expected 1 but got 2","location":"tests/a_test.pas:12"}]\n';
  const r = parseResults(out)!;
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].outcome, 'failed');
  assert.deepStrictEqual(parseLocation(r[0].location), { file: 'tests/a_test.pas', line: 11 });
  assert.strictEqual(parseResults('src/x.pas(3,1) Error: boom\n'), undefined);
});

console.log(`testparse: ${passed} passed`);
