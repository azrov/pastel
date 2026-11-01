// Unit tests for the designer's .pform edits. Run: npm test
import * as assert from 'assert';
import {
  deleteObject, extractObject, findBlock, formatValue, insertObject, isObjectText, moveObject, parseBlocks,
  parseValue, pasteObjects, renameIdentifier, renameObject, setProperty,
  wrapObjects, unwrapObject, moveSibling, extractObjects, deleteObjects, outline,
} from '../edit';

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
  'object HomeForm: THomeForm',
  "  Title = 'Demo'",
  '  object Card: TCard',
  '    object NameEdit: TEdit',
  "      Placeholder = 'Name' // shown when empty",
  '    end',
  '    object Buttons: TRow',
  '      object Ok: TButton',
  "        Text = 'OK'",
  '      end',
  '    end',
  '  end',
  '  object Info: TLabel',
  '  end',
  'end',
].join('\n');

test('parse blocks', () => {
  const root = parseBlocks(form)!;
  assert.strictEqual(root.name, 'HomeForm');
  assert.deepStrictEqual(root.children.map(c => c.name), ['Card', 'Info']);
  const ok = findBlock(root, 'ok')!;
  assert.strictEqual(ok.parent!.name, 'Buttons');
  assert.strictEqual(ok.start, 7);
  assert.strictEqual(ok.end, 9);
  assert.strictEqual(ok.props[0].value, "'OK'");
  assert.strictEqual(parseBlocks('object A: TForm\n'), undefined);
});

test('set an existing property, keeping the comment', () => {
  const out = setProperty(form, 'NameEdit', 'placeholder', "'Your name'");
  assert.ok(out.includes("      Placeholder = 'Your name' // shown when empty"), out);
});

test('add a new property after the existing ones', () => {
  const out = setProperty(form, 'Ok', 'Style', 'Secondary').split('\n');
  assert.strictEqual(out[8], "        Text = 'OK'");
  assert.strictEqual(out[9], '        Style = Secondary');
});

test('add a property to an object without properties', () => {
  const out = setProperty(form, 'Info', 'Text', "'Hi'").split('\n');
  assert.strictEqual(out[12], '  object Info: TLabel');
  assert.strictEqual(out[13], "    Text = 'Hi'");
  assert.strictEqual(out[14], '  end');
});

test('remove a property', () => {
  const out = setProperty(form, 'HomeForm', 'Title', undefined);
  assert.ok(!out.includes('Title'));
  assert.ok(parseBlocks(out));
});

test('insert a control with a free name', () => {
  const r = insertObject(form, 'Buttons', 0, 'TButton')!;
  assert.strictEqual(r.name, 'Button1');
  const lines = r.text.split('\n');
  assert.strictEqual(lines[7], '      object Button1: TButton');
  assert.strictEqual(lines[8], "        Text = 'Button1'");
  assert.strictEqual(lines[9], '      end');
  const root = parseBlocks(r.text)!;
  assert.deepStrictEqual(findBlock(root, 'Buttons')!.children.map(c => c.name), ['Button1', 'Ok']);
});

test('insert at the end of a container', () => {
  const r = insertObject(form, 'HomeForm', 2, 'TLabel')!;
  const root = parseBlocks(r.text)!;
  assert.deepStrictEqual(root.children.map(c => c.name), ['Card', 'Info', 'Label1']);
  assert.ok(r.text.includes("  object Label1: TLabel\n    Text = 'Label1'\n  end\nend"));
});

test('move a control into another container, reindenting it', () => {
  const out = moveObject(form, 'Ok', 'HomeForm', 1);
  const root = parseBlocks(out)!;
  assert.deepStrictEqual(root.children.map(c => c.name), ['Card', 'Ok', 'Info']);
  assert.ok(out.includes("  object Ok: TButton\n    Text = 'OK'\n  end"), out);
  assert.deepStrictEqual(findBlock(root, 'Buttons')!.children, []);
});

test('move a container with its children deeper', () => {
  const out = moveObject(form, 'Info', 'Buttons', 0);
  assert.ok(out.includes("    object Buttons: TRow\n      object Info: TLabel\n      end\n      object Ok: TButton"), out);
});

test('reorder inside the same container', () => {
  const out = moveObject(form, 'Info', 'HomeForm', 0);
  assert.deepStrictEqual(parseBlocks(out)!.children.map(c => c.name), ['Info', 'Card']);
});

test('a control cannot move into itself', () => {
  assert.strictEqual(moveObject(form, 'Card', 'Buttons', 0), form);
  assert.strictEqual(moveObject(form, 'HomeForm', 'Card', 0), form);
});

test('delete a control with its children', () => {
  const out = deleteObject(form, 'Card');
  assert.deepStrictEqual(parseBlocks(out)!.children.map(c => c.name), ['Info']);
  assert.strictEqual(deleteObject(form, 'HomeForm'), form);
});

test('Windows line endings are kept', () => {
  const crlf = form.replace(/\n/g, '\r\n');
  const out = setProperty(crlf, 'Ok', 'Text', "'Yes'");
  assert.ok(out.includes("        Text = 'Yes'\r\n"));
  assert.ok(!/[^\r]\n/.test(out));
});

test('format and parse values', () => {
  assert.strictEqual(formatValue('string', "It's"), "'It''s'");
  assert.strictEqual(formatValue('string', ''), undefined);
  assert.strictEqual(formatValue('color', '#4f46e5'), "'#4F46E5'");
  assert.strictEqual(formatValue('integer', '12'), '12');
  assert.strictEqual(formatValue('integer', 'x'), undefined);
  assert.strictEqual(formatValue('boolean', 'true'), 'True');
  assert.strictEqual(formatValue('enum', 'Center'), 'Center');
  assert.strictEqual(parseValue("'It''s' // c"), "It's");
  assert.strictEqual(parseValue('True'), 'True');
});

test('copy a control with its children', () => {
  const t = extractObject(form, 'Buttons')!;
  assert.strictEqual(t, "object Buttons: TRow\n  object Ok: TButton\n    Text = 'OK'\n  end\nend");
  assert.ok(isObjectText(t));
  assert.ok(!isObjectText('hello'));
  assert.strictEqual(extractObject(form, 'HomeForm'), undefined, 'not the form');
});

test('paste gives free names and the right indentation', () => {
  const t = extractObject(form, 'Buttons')!;
  const r = pasteObjects(form, t, 'HomeForm', 99)!;
  assert.strictEqual(r.name, 'Buttons1');
  const root = parseBlocks(r.text)!;
  assert.ok(findBlock(root, 'Ok1'), 'children renamed too');
  assert.strictEqual(findBlock(root, 'Buttons1')!.parent!.name, 'HomeForm');
  assert.ok(r.text.includes("\n  object Buttons1: TRow\n    object Ok1: TButton\n      Text = 'OK'\n    end\n  end\nend"), r.text);
  assert.strictEqual(pasteObjects(form, 'not an object', 'HomeForm', 0), undefined);
});

test('rename a control', () => {
  const t = renameObject(form, 'Ok', 'SaveButton')!;
  assert.ok(t.includes('object SaveButton: TButton'));
  assert.strictEqual(renameObject(form, 'Ok', 'Info'), undefined, 'the name is taken');
  assert.strictEqual(renameObject(form, 'Ok', '1x'), undefined, 'not a Pascal name');
});

test('rename an identifier in code, not in strings or comments', () => {
  const pas = "procedure THomeForm.X;\nbegin\n  Ok.Text := 'Ok'; // Ok\n  ok.SetFocus; { Ok }\n  OkDone := True;\nend;";
  assert.strictEqual(renameIdentifier(pas, 'Ok', 'SaveButton'),
    "procedure THomeForm.X;\nbegin\n  SaveButton.Text := 'Ok'; // Ok\n  SaveButton.SetFocus; { Ok }\n  OkDone := True;\nend;");
});

test('wrap siblings in a row, and unwrap them again', () => {
  const two = form.replace("  object Info: TLabel\n  end", "  object Info: TLabel\n  end\n  object More: TLabel\n  end");
  const r = wrapObjects(two, ['More', 'Info'], 'TRow')!;
  const root = parseBlocks(r.text)!;
  assert.strictEqual(r.name, 'Row1');
  assert.deepStrictEqual(root.children.map(c => c.name), ['Card', 'Row1']);
  assert.deepStrictEqual(findBlock(root, 'Row1')!.children.map(c => c.name), ['Info', 'More'], 'in file order');
  assert.ok(r.text.includes('  object Row1: TRow\n    Gap = 8\n    object Info: TLabel\n    end'), r.text);
  assert.strictEqual(wrapObjects(form, ['Ok', 'Info'], 'TRow'), undefined, 'different parents');
  const back = unwrapObject(r.text, 'Row1');
  assert.strictEqual(back, two);
});

test('move among siblings', () => {
  const root = parseBlocks(moveSibling(form, 'Info', -1))!;
  assert.deepStrictEqual(root.children.map(c => c.name), ['Info', 'Card']);
  assert.strictEqual(moveSibling(form, 'Card', -1), form, 'already first');
  assert.strictEqual(moveSibling(form, 'Info', 1), form, 'already last');
});

test('several controls: copy, delete, outline', () => {
  const clip = extractObjects(form, ['Info', 'Ok', 'Buttons'])!;
  assert.strictEqual(clip, "object Buttons: TRow\n  object Ok: TButton\n    Text = 'OK'\n  end\nend\nobject Info: TLabel\nend");
  const root = parseBlocks(deleteObjects(form, ['Info', 'NameEdit']))!;
  assert.deepStrictEqual(outline(deleteObjects(form, ['Info', 'NameEdit'])).map(o => o.name), ['HomeForm', 'Card', 'Buttons', 'Ok']);
  assert.strictEqual(root.children.length, 1);
  assert.deepStrictEqual(outline(form).map(o => o.depth), [0, 1, 2, 2, 3, 1]);
});

test('any series of designer edits keeps every object closed by its own end', () => {
  // a fixed seed: the same series each run
  let seed = 7;
  const rnd = (n: number) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
  let text = form;
  let clip = '';
  for (let step = 0; step < 1500; step++) {
    const root = parseBlocks(text)!;
    assert.ok(root, `step ${step} broke the form:\n${text}`);
    const all: { name: string; className: string; parent?: unknown; children: unknown[] }[] = [];
    const walk = (b: any) => { all.push(b); b.children.forEach(walk); };
    walk(root);
    const kids = all.filter(b => b !== root);
    const boxes = all.filter(b => b === root || /^(TCard|TRow|TColumn)$/.test(b.className));
    const pick = <T>(xs: T[]) => xs[rnd(xs.length)];
    const box = pick(boxes) as any;
    const some = kids.length ? pick(kids) as any : undefined;
    let next = text;
    switch (rnd(9)) {
      case 0: next = insertObject(text, box.name, rnd(box.children.length + 1), pick(['TButton', 'TRow', 'TCard', 'TLabel']))?.text ?? text; break;
      case 1: if (some) next = deleteObjects(text, [some.name]); break;
      case 2: if (some) next = moveObject(text, some.name, box.name, rnd(box.children.length + 1)); break;
      case 3: if (some) next = moveSibling(text, some.name, rnd(2) ? 1 : -1); break;
      case 4: if (some) next = wrapObjects(text, [some.name], pick(['TRow', 'TCard']))?.text ?? text; break;
      case 5: if (some) next = unwrapObject(text, some.name); break;
      case 6: if (some) clip = extractObjects(text, [some.name]) ?? clip; break;
      case 7: if (clip) next = pasteObjects(text, clip, box.name, rnd(box.children.length + 1))?.text ?? text; break;
      case 8: if (some) next = setProperty(text, some.name, 'Text', rnd(2) ? "'end'" : undefined); break;
    }
    if (kids.length > 40) next = deleteObjects(next, [kids[0].name]);
    text = next;
  }
  assert.ok(parseBlocks(text));
});

console.log(`edit: ${passed} passed`);
