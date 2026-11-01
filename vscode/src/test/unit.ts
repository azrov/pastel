// Unit tests for the VS Code-independent helpers. Run: npm test
import * as assert from 'assert';
import {
  allObjects, classFor, completionContext, declaredProcedures, enclosingObjects,
  findProcedure, handlerInserts, missingHandlerName, parseIssues, Schema, stripComment,
} from '../model';

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

const form = [
  'object HomeForm: THomeForm',      // 0
  "  Title = 'x' // comment",        // 1
  '  object Card: TCard',            // 2
  '    object NameEdit: TEdit',      // 3
  '      Placeholder = \'a\'',       // 4
  '    end',                         // 5
  '    ',                            // 6
  '  end',                           // 7
  '  ',                              // 8
  'end',                             // 9
];

test('enclosing object inside a control', () => {
  const chain = enclosingObjects(form, 4);
  assert.deepStrictEqual(chain.map(c => c.className), ['THomeForm', 'TCard', 'TEdit']);
});
test('enclosing object after end', () => {
  assert.deepStrictEqual(enclosingObjects(form, 6).map(c => c.name), ['HomeForm', 'Card']);
  assert.deepStrictEqual(enclosingObjects(form, 8).map(c => c.name), ['HomeForm']);
});
test('all objects with depth', () => {
  assert.deepStrictEqual(allObjects(form).map(o => `${o.name}:${o.depth}`), ['HomeForm:0', 'Card:1', 'NameEdit:2']);
});
test('strip comments but not inside strings', () => {
  assert.strictEqual(stripComment("Text = 'a // b' // c"), "Text = 'a // b' ");
  assert.strictEqual(stripComment('Gap = 2 { note }'), 'Gap = 2 ');
});
test('completion contexts', () => {
  assert.deepStrictEqual(completionContext('  object X: TBu'), { kind: 'type' });
  assert.deepStrictEqual(completionContext('    Align = Ce'), { kind: 'value', property: 'Align', prefix: 'Ce' });
  assert.deepStrictEqual(completionContext('    Te'), { kind: 'property', prefix: 'Te' });
  assert.deepStrictEqual(completionContext("    Text = 'a' x"), { kind: 'none' });
});
test('class for chain', () => {
  const schema: Schema = {
    version: '1',
    form: { name: 'TForm', container: true, form: true, properties: [] },
    controls: [{ name: 'TEdit', container: false, form: false, properties: [] }],
  };
  assert.strictEqual(classFor(schema, enclosingObjects(form, 1))?.name, 'TForm');
  assert.strictEqual(classFor(schema, enclosingObjects(form, 4))?.name, 'TEdit');
  assert.strictEqual(classFor(schema, []), undefined);
});

const unit = [
  'unit Home;',
  'interface',
  'type',
  '  THomeForm = class(THomeFormBase)',
  '    procedure SendClick(Sender: TObject);',
  '  end;',
  'implementation',
  'procedure THomeForm.SendClick(Sender: TObject);',
  'begin',
  'end;',
  '',
  'end.',
].join('\n');

test('declared procedures', () => {
  assert.deepStrictEqual(declaredProcedures(unit), ['SendClick']);
});
test('find implementation first', () => {
  assert.deepStrictEqual(findProcedure(unit, 'SendClick'), { line: 7, character: 0 });
  assert.strictEqual(findProcedure(unit, 'Nope'), undefined);
});
test('handler inserts', () => {
  const ins = handlerInserts(unit, 'ClearClick');
  assert.ok(ins);
  assert.strictEqual(ins![0].line, 5);
  assert.strictEqual(ins![0].text, '    procedure ClearClick(Sender: TObject);\n');
  assert.strictEqual(ins![1].line, 11);
  assert.ok(ins![1].text.startsWith('procedure THomeForm.ClearClick(Sender: TObject);'));
  assert.strictEqual(handlerInserts('unit X; end.', 'A'), undefined);
});
test('handlers go before initialization', () => {
  const src = ['unit Home;', 'interface', 'type', '  THomeForm = class(THomeFormBase)', '  end;', 'implementation',
    'initialization', '  RegisterIt;', 'end.'].join('\n');
  const ins = handlerInserts(src, 'OkClick');
  assert.strictEqual(ins![1].line, 6);
});
test('parse issues and handler names', () => {
  const issues = parseIssues('[{"file":"a","line":3,"severity":"error","message":"event handler \\"Go\\" is not declared in Home.pas"}]');
  assert.strictEqual(issues.length, 1);
  assert.strictEqual(missingHandlerName(issues[0].message), 'Go');
  assert.strictEqual(missingHandlerName('something else'), undefined);
});

console.log(`model: ${passed} passed`);
