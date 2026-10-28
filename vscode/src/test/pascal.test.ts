// Unit tests for the Pascal reader. Run: npm test
import * as assert from 'assert';
import { blankComments, dottedWordAt, parsePascal, symbolAtLine, toggleDeclaration } from '../pascal';

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

const src = [
  'unit Home;',                                          // 0
  '{$mode objfpc}{$H+}',                                 // 1
  'interface',                                           // 2
  'uses',                                                // 3
  '  SysUtils, Pastel.UI,',                              // 4
  '  Home.g;',                                           // 5
  'type',                                                // 6
  '  TCounter = Integer;',                               // 7
  '  TErr = class(Exception);',                          // 8
  '  THomeForm = class(THomeFormBase)',                  // 9
  '  private',                                           // 10
  '    FCount, FTotal: Integer;',                        // 11
  '  public',                                            // 12
  '    procedure SendClick(Sender: TObject);',           // 13
  "    function Greeting(const S: string): string; // { not a comment end",  // 14
  '    property Count: Integer read FCount;',            // 15
  '  end;',                                              // 16
  '  TPoint2 = record',                                  // 17
  '    X, Y: Integer;',                                  // 18
  '  end;',                                              // 19
  'function Twice(N: Integer): Integer;',                // 20
  'implementation',                                      // 21
  'uses Math;',                                          // 22
  '(* procedure Fake; *)',                               // 23
  'function Twice(N: Integer): Integer;',                // 24
  'begin',                                               // 25
  '  Result := N * 2;',                                  // 26
  'end;',                                                // 27
  'procedure THomeForm.SendClick(Sender: TObject);',     // 28
  'begin',                                               // 29
  "  Greeting('procedure Nope;');",                      // 30
  'end;',                                                // 31
  'function THomeForm.Greeting(const S: string): string;', // 32
  'begin',                                               // 33
  'end;',                                                // 34
  'end.',                                                // 35
].join('\n');

const file = parsePascal(src);
const find = (name: string, impl?: boolean) =>
  file.symbols.find(s => s.name === name && (impl === undefined || s.implementation === impl));

test('unit name and uses', () => {
  assert.strictEqual(file.unitName, 'Home');
  assert.deepStrictEqual(file.uses.map(u => u.name), ['SysUtils', 'Pastel.UI', 'Home.g', 'Math']);
});

test('types', () => {
  assert.strictEqual(find('TCounter')!.kind, 'type');
  assert.strictEqual(find('TErr')!.kind, 'class');
  assert.strictEqual(find('THomeForm')!.kind, 'class');
  assert.strictEqual(find('THomeForm')!.endLine, 16);
  assert.strictEqual(find('TPoint2')!.kind, 'record');
});

test('class members', () => {
  assert.deepStrictEqual(
    file.symbols.filter(s => s.container === 'THomeForm' && !s.implementation).map(s => `${s.kind}:${s.name}`),
    ['field:FCount', 'field:FTotal', 'method:SendClick', 'method:Greeting', 'property:Count']);
  assert.deepStrictEqual(file.symbols.filter(s => s.container === 'TPoint2').map(s => s.name), ['X', 'Y']);
});

test('routines and method bodies; comments and strings are ignored', () => {
  assert.strictEqual(find('Twice', false)!.line, 20);
  assert.strictEqual(find('Twice', true)!.line, 24);
  const body = find('SendClick', true)!;
  assert.strictEqual(body.container, 'THomeForm');
  assert.strictEqual(body.line, 28);
  assert.strictEqual(body.character, 'procedure THomeForm.'.length);
  assert.ok(!find('Fake') && !find('Nope'));
});

test('toggle declaration and body', () => {
  assert.strictEqual(toggleDeclaration(file, 13)!.line, 28);
  assert.strictEqual(toggleDeclaration(file, 30)!.line, 13, 'from inside the body');
  assert.strictEqual(toggleDeclaration(file, 20)!.line, 24);
  assert.strictEqual(toggleDeclaration(file, 26)!.line, 20);
  assert.strictEqual(symbolAtLine(file, 33)!.name, 'Greeting');
});

test('blank comments keeps positions', () => {
  const t = "a { b } c // d\n'x' (* y *) z";
  const b = blankComments(t);
  assert.strictEqual(b.length, t.length);
  assert.strictEqual(b, "a       c     \n' '         z");
});

test('dotted word under the cursor', () => {
  assert.deepStrictEqual(dottedWordAt('  SysUtils, Pastel.UI,', 15), { word: 'Pastel.UI', start: 12 });
  assert.strictEqual(dottedWordAt('  x := 1;', 5), undefined);
});

console.log(`pascal: ${passed} passed`);
