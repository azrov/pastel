// Tests for the Pascal analyzer on a small project with the real Pastel
// framework and, when installed, the Free Pascal sources. Run: npm test
import * as assert from 'assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { Analyzer, signature } from '../lang/analyzer';

let passed = 0;
let skipped = 0;
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

const root = path.resolve(__dirname, '..', '..', '..');
const framework = path.join(root, 'framework', 'src');
const fpcCandidates = ['/usr/share/fpcsrc/3.2.2', process.env.FPCDIR ?? ''];
const fpcSourceDir = fpcCandidates.find(d => d && fs.existsSync(path.join(d, 'rtl', 'objpas')));
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pastel-analyzer-'));

const files: Record<string, string> = {
  'shapes.pas': `unit Shapes;

interface

uses
  Classes, SysUtils;

type
  TColor = (clRed, clGreen);

  { A shape that can be drawn. }
  TShape = class
  private
    FName: string;
    FItems: TStringList;
    function GetItem(Index: Integer): TShape;
  public
    Color: TColor;
    constructor Create(const AName: string);
    destructor Destroy; override;
    { How big it is, in square pixels. }
    function Area: Double; virtual;
    procedure Move(DX, DY: Integer); overload;
    procedure Move(const P: TPoint); overload;
    property Name: string read FName write FName;
    property Items[Index: Integer]: TShape read GetItem; default;
    property List: TStringList read FItems;
  end;

  TCircle = class(TShape)
  public
    Radius: Double;
    function Area: Double; override;
  end;

{ A circle with radius R. }
function MakeCircle(R: Double): TCircle;

implementation

function TShape.GetItem(Index: Integer): TShape;
begin
  Result := nil;
end;

constructor TShape.Create(const AName: string);
begin
  FName := AName;
  FItems := TStringList.Create;
end;

destructor TShape.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TShape.Area: Double;
begin
  Result := 0;
end;

procedure TShape.Move(DX, DY: Integer);
begin
end;

procedure TShape.Move(const P: TPoint);
begin
end;

function TCircle.Area: Double;
begin
  Result := Pi * Radius * Radius;
end;

function MakeCircle(R: Double): TCircle;
begin
  Result := TCircle.Create('circle');
  Result.Radius := R;
end;

end.
`,
  'main.pas': `program Demo;

uses
  SysUtils, Shapes, Pastel.UI;

var
  C: TCircle;
  Edit: TEdit;
  Names: array of string;
  S: string;

procedure Show(const Prefix: string; Value: Double);
var
  Line: string;
begin
  Line := Format('%s %f', [Prefix, Value]);
  WriteLn(Line);
end;

begin
  C := MakeCircle(2);
  Show('area', C.Area);
  C.Move(1, 2);
  C.List.Add('x');
  C[0].Name := 'first';
  Edit.Text := Names[0];
  S := S.ToUpper;
end.
`,
};
for (const [n, t] of Object.entries(files)) {
  fs.writeFileSync(path.join(dir, n), t);
}
const file = (n: string) => path.join(dir, n);
const a = new Analyzer({
  readFile: f => { try { return fs.readFileSync(f, 'utf8'); } catch { return undefined; } },
  projectFiles: () => Object.keys(files).map(file),
  frameworkDir: framework,
  fpcSourceDir,
  systemFile: path.join(root, 'vscode', 'pascal', 'system.pas'),
});
const main = a.unitForFile(file('main.pas'))!;
const shapes = a.unitForFile(file('shapes.pas'))!;
const lines = files['main.pas'].split('\n');
const at = (needle: string, after = needle.length) => {
  const line = lines.findIndex(l => l.includes(needle));
  return { line, col: lines[line].indexOf(needle) + after };
};
const names = (ds: { name: string }[]) => ds.map(d => d.name);

test('parses classes, members and bodies', () => {
  const shape = shapes.interfaceDecls.find(d => d.name === 'TShape')!;
  assert.strictEqual(shape.kind, 'class');
  assert.ok(names(shape.members!).includes('Area'));
  assert.strictEqual(shape.doc, 'A shape that can be drawn.');
  assert.strictEqual(shape.members!.find(m => m.name === 'Area')!.doc, 'How big it is, in square pixels.');
  assert.ok(shapes.bodies.some(b => b.name === 'TCircle.Area'));
});

test('members after a dot, with the ancestors', () => {
  const p = at('C.Move', 2);
  const r = a.completionAt(main, p.line, p.col);
  assert.strictEqual(r.kind, 'member');
  const n = names(r.decls);
  assert.ok(n.includes('Radius') && n.includes('Area') && n.includes('Name') && n.includes('Free'), n.join(','));
  assert.ok(!n.includes('FName'), 'private members of another unit are hidden');
});

test('a chain: property, then a class from the RTL', () => {
  const p = at('C.List.', 7);
  const r = a.completionAt(main, p.line, p.col);
  if (!fpcSourceDir) {
    skipped++;
    return;
  }
  assert.ok(names(r.decls).includes('Add') && names(r.decls).includes('Count'), names(r.decls).join(','));
});

test('the default property: C[0].', () => {
  const p = at('C[0].', 5);
  const r = a.completionAt(main, p.line, p.col);
  assert.ok(names(r.decls).includes('Name'), names(r.decls).join(','));
});

test('a framework control', () => {
  const p = at('Edit.Text', 5);
  const r = a.completionAt(main, p.line, p.col);
  assert.ok(names(r.decls).includes('Text'), names(r.decls).join(','));
});

test('string helpers from SysUtils', () => {
  if (!fpcSourceDir) {
    skipped++;
    return;
  }
  const p = at('S.ToUpper', 2);
  const r = a.completionAt(main, p.line, p.col);
  assert.ok(names(r.decls).includes('ToUpper'), names(r.decls).slice(0, 20).join(','));
});

test('names in scope: locals, parameters, globals, used units', () => {
  const p = at('WriteLn(Line)', 0);
  const r = a.completionAt(main, p.line, p.col);
  const n = names(r.decls);
  for (const x of ['Line', 'Prefix', 'Value', 'C', 'MakeCircle', 'TShape', 'clRed', 'WriteLn']) {
    assert.ok(n.includes(x), x);
  }
});

test('units in uses', () => {
  const r = a.completionAt(main, 3, 2);
  assert.strictEqual(r.kind, 'uses');
  const n = r.units!.map(u => u.name);
  assert.ok(n.includes('Shapes') && n.includes('Pastel.UI'), n.slice(0, 10).join(','));
  if (fpcSourceDir) {
    assert.ok(n.some(x => x.toLowerCase() === 'sysutils'));
  }
});

test('hover: what a name is', () => {
  const p = at('MakeCircle(2)', 3);
  const k = a.tokenIndexAt(main.tokens, p.line, p.col);
  const d = a.resolveToken(main, k)[0];
  assert.strictEqual(signature(d), 'function MakeCircle(R: Double): TCircle');
  assert.strictEqual(d.doc, 'A circle with radius R.');
  const q = at('C.Area', 3);
  const area = a.resolveToken(main, a.tokenIndexAt(main.tokens, q.line, q.col))[0];
  assert.strictEqual(signature(area), 'function TCircle.Area: Double');
});

test('parameter hints, with overloads', () => {
  const p = at('C.Move(1, ', 10);
  const r = a.callAt(main, p.line, p.col)!;
  assert.ok(r, 'a call');
  assert.strictEqual(r.active, 1);
  assert.strictEqual(r.decls.length, 2);
  const q = at("Show('area', ", 7);
  const s = a.callAt(main, q.line, q.col)!;
  assert.strictEqual(signature(s.decls[0]), 'procedure Show(const Prefix: string; Value: Double)');
  assert.strictEqual(s.active, 0);
});

test('references and the method body', () => {
  const area = shapes.interfaceDecls.find(d => d.name === 'TShape')!.members!.find(m => m.name === 'Area')!;
  const refs = a.references(area, Object.keys(files).map(file));
  const where = refs.map(r => `${path.basename(r.file)}:${r.line}`);
  assert.ok(where.includes('shapes.pas:21'), 'the declaration ' + where.join(','));
  assert.ok(where.includes('shapes.pas:57'), 'the body header');
  assert.ok(!where.includes('shapes.pas:70'), 'TCircle.Area is another method');
  const circleArea = shapes.interfaceDecls.find(d => d.name === 'TCircle')!.members!.find(m => m.name === 'Area')!;
  const r2 = a.references(circleArea, Object.keys(files).map(file)).map(r => `${path.basename(r.file)}:${r.line}`);
  assert.ok(r2.includes('main.pas:21'), 'C.Area in main: ' + r2.join(','));
});

test('a local variable is not a global one', () => {
  const p = at('WriteLn(Line)', 9);
  const d = a.resolveToken(main, a.tokenIndexAt(main.tokens, p.line, p.col))[0];
  assert.strictEqual(d.kind, 'var');
  const refs = a.references(d, Object.keys(files).map(file));
  assert.deepStrictEqual(refs.map(r => r.line), [13, 15, 16]);
});

fs.rmSync(dir, { recursive: true });
console.log(`analyzer: ${passed} passed${skipped ? `, ${skipped} skipped (no Free Pascal sources)` : ''}`);
