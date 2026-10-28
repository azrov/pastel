// Integration test: loads the real extension with a small stand-in for the
// VS Code API and drives its providers against a real Pastel project and the
// real pastel program. Usage: node out/test/integration.js <project-folder>
import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const Module = require('module');

const projectDir = path.resolve(process.argv[2] ?? '.');
const pformPath = path.join(projectDir, 'src', 'forms', 'Home.pform');
const pasPath = path.join(projectDir, 'src', 'forms', 'Home.pas');

// ---------------- fake VS Code API ----------------
class Position { constructor(public line: number, public character: number) {} }
class Range {
  start: Position; end: Position;
  constructor(a: number | Position, b: number | Position, c?: number, d?: number) {
    if (typeof a === 'number') { this.start = new Position(a, b as number); this.end = new Position(c!, d!); }
    else { this.start = a; this.end = b as Position; }
  }
}
class Selection extends Range {}
class SnippetString {
  value: string;
  constructor(v = '') { this.value = v; }
  appendText(t: string) { this.value += t; return this; }
  appendTabstop(n: number) { this.value += '$' + n; return this; }
  appendPlaceholder(t: string) { this.value += '${1:' + t + '}'; return this; }
  appendChoice(v: string[]) { this.value += '${1|' + v.join(',') + '|}'; return this; }
}
class CompletionItem {
  insertText?: unknown; detail?: string; documentation?: unknown; sortText?: string;
  constructor(public label: string, public kind?: number) {}
}
class MarkdownString { constructor(public value: string) {} }
class Hover { constructor(public contents: MarkdownString, public range?: Range) {} }
class Location { constructor(public uri: Uri, public range: Position) {} }
class Diagnostic { source?: string; constructor(public range: Range, public message: string, public severity: number) {} }
class CodeAction { command?: { command: string; arguments: unknown[] }; diagnostics?: Diagnostic[]; isPreferred?: boolean;
  constructor(public title: string, public kind?: unknown) {} }
class DocumentSymbol { children: DocumentSymbol[] = [];
  constructor(public name: string, public detail: string, public kind: number, public range: Range, public sel: Range) {} }
class Uri {
  constructor(public fsPath: string) {}
  get scheme() { return 'file'; }
  toString() { return 'file://' + this.fsPath; }
  static file(p: string) { return new Uri(p); }
}
class Task { group?: unknown; presentationOptions?: unknown;
  constructor(public definition: unknown, public scope: unknown, public name: string, public source: string,
    public execution: unknown, public matcher?: unknown) {} }
class ProcessExecution { constructor(public process: string, public args: string[], public options: unknown) {} }

class FakeDocument {
  version = 1;
  constructor(public uri: Uri, public languageId: string, private text: string) {}
  getText(r?: Range) { return r ? this.lineAt(r.start.line).text.substring(r.start.character, r.end.character) : this.text; }
  setText(t: string) { this.text = t; this.version++; }
  get lineCount() { return this.text.split('\n').length; }
  lineAt(i: number) {
    const t = this.text.split('\n')[i] ?? '';
    return { text: t, firstNonWhitespaceCharacterIndex: Math.max(0, t.search(/\S/)) };
  }
  getWordRangeAtPosition(pos: Position, re: RegExp) {
    const line = this.lineAt(pos.line).text;
    const g = new RegExp(re.source, 'g');
    let m: RegExpExecArray | null;
    while ((m = g.exec(line)) !== null) {
      if (pos.character >= m.index && pos.character <= m.index + m[0].length) {
        return new Range(pos.line, m.index, pos.line, m.index + m[0].length);
      }
    }
    return undefined;
  }
  positionAt(offset: number) {
    const before = this.text.substring(0, offset).split('\n');
    return new Position(before.length - 1, before[before.length - 1].length);
  }
  getRangeText(r: Range) { return this.lineAt(r.start.line).text.substring(r.start.character, r.end.character); }
  async save() { fs.writeFileSync(this.uri.fsPath, this.text); return true; }
}

const docs: FakeDocument[] = [];
const providers: Record<string, any> = {};
const commands: Record<string, (...a: any[]) => any> = {};
const diagnosticStore = new Map<string, Diagnostic[]>();
const webviewMessages: any[] = [];
const listeners: Record<string, ((e: any) => void)[]> = {};
const on = (name: string) => (fn: (e: any) => void) => { (listeners[name] ??= []).push(fn); return { dispose() {} }; };

const vscodeFake = {
  Position, Range, Selection, SnippetString, CompletionItem, MarkdownString, Hover, Location, Diagnostic,
  CodeAction, DocumentSymbol, Uri, Task, ProcessExecution,
  CompletionItemKind: { Class: 6, Property: 9, Event: 22, EnumMember: 19, Value: 11, Method: 1, Keyword: 13, Color: 15 },
  DiagnosticSeverity: { Error: 0, Warning: 1 },
  SymbolKind: { Object: 18 },
  CodeActionKind: { QuickFix: 'quickfix' },
  StatusBarAlignment: { Left: 1 },
  ViewColumn: { Beside: -2, Active: -1 },
  TaskGroup: { Build: 'build' },
  TaskScope: { Workspace: 2 },
  TaskRevealKind: { Always: 1 },
  TaskPanelKind: { Dedicated: 2 },
  TextEditorRevealType: { InCenter: 2, InCenterIfOutsideViewport: 3 },
  WorkspaceEdit: class {
    inserts: { uri: Uri; pos: Position; text: string }[] = [];
    replaces: { uri: Uri; text: string }[] = [];
    insert(uri: Uri, pos: Position, text: string) { this.inserts.push({ uri, pos, text }); }
    // only whole-document replaces are used by the designer
    replace(uri: Uri, _r: Range, text: string) { this.replaces.push({ uri, text }); }
  },
  languages: {
    createDiagnosticCollection: () => ({
      set: (uri: Uri, d: Diagnostic[]) => diagnosticStore.set(uri.fsPath, d),
      delete: (uri: Uri) => diagnosticStore.delete(uri.fsPath),
      dispose() {},
    }),
    registerCompletionItemProvider: (_s: unknown, p: unknown) => { providers.completion = p; return { dispose() {} }; },
    registerHoverProvider: (_s: unknown, p: unknown) => { providers.hover = p; return { dispose() {} }; },
    registerDefinitionProvider: (_s: unknown, p: unknown) => { providers.definition = p; return { dispose() {} }; },
    registerDocumentSymbolProvider: (_s: unknown, p: unknown) => { providers.symbols = p; return { dispose() {} }; },
    registerCodeActionsProvider: (_s: unknown, p: unknown) => { providers.actions = p; return { dispose() {} }; },
  },
  commands: {
    registerCommand: (id: string, fn: (...a: any[]) => any) => { commands[id] = fn; return { dispose() {} }; },
    executeCommand: async () => undefined,
  },
  window: {
    activeTextEditor: undefined as any,
    createStatusBarItem: () => ({ show() {}, dispose() {} }),
    showErrorMessage: async (m: string) => { throw new Error('unexpected error message: ' + m); },
    showWarningMessage: async () => undefined,
    showInformationMessage: async () => undefined,
    showTextDocument: async () => ({ selection: undefined, revealRange() {} }),
    onDidChangeActiveTextEditor: on('activeEditor'),
    onDidChangeTextEditorSelection: on('selection'),
    visibleTextEditors: [] as any[],
    createWebviewPanel: () => ({
      webview: {
        html: '',
        postMessage: (m: any) => { webviewMessages.push(m); return Promise.resolve(true); },
        onDidReceiveMessage: (fn: (m: any) => void) => { providers.fromWebview = fn; return { dispose() {} }; },
      },
      onDidDispose: () => ({ dispose() {} }),
      reveal() {},
      title: '',
    }),
  },
  workspace: {
    textDocuments: docs,
    workspaceFolders: [{ uri: Uri.file(projectDir) }],
    getConfiguration: () => ({ get: (k: string, d?: unknown) => (k === 'path' ? process.env.PASTEL_BIN ?? 'pastel' : d) }),
    findFiles: async () => [Uri.file(path.join(projectDir, 'pastel.toml'))],
    onDidChangeWorkspaceFolders: on('folders'),
    onDidOpenTextDocument: on('open'),
    onDidSaveTextDocument: on('save'),
    onDidChangeTextDocument: on('change'),
    onDidCloseTextDocument: on('close'),
    openTextDocument: async (uri: Uri) => {
      let d = docs.find(x => x.uri.fsPath === uri.fsPath);
      if (!d) { d = new FakeDocument(uri, uri.fsPath.endsWith('.pform') ? 'pform' : 'pascal', fs.readFileSync(uri.fsPath, 'utf8')); docs.push(d); }
      return d;
    },
    applyEdit: async (edit: { inserts: { uri: Uri; pos: Position; text: string }[]; replaces: { uri: Uri; text: string }[] }) => {
      for (const r of edit.replaces ?? []) {
        const d = docs.find(x => x.uri.fsPath === r.uri.fsPath)!;
        d.setText(r.text);
        listeners.change?.forEach(f => f({ document: d }));
      }
      const byFile = new Map<string, { pos: Position; text: string }[]>();
      edit.inserts.forEach(i => byFile.set(i.uri.fsPath, [...(byFile.get(i.uri.fsPath) ?? []), i]));
      for (const [file, ins] of byFile) {
        const d = docs.find(x => x.uri.fsPath === file)!;
        const lines = d.getText().split('\n');
        ins.sort((a, b) => b.pos.line - a.pos.line).forEach(i => lines.splice(i.pos.line, 0, i.text.replace(/\n$/, '')));
        d.setText(lines.join('\n'));
      }
      return true;
    },
    saveAll: async () => true,
    getWorkspaceFolder: () => ({ uri: Uri.file(projectDir) }),
  },
  tasks: {
    registerTaskProvider: (_t: string, p: unknown) => { providers.tasks = p; return { dispose() {} }; },
    taskExecutions: [],
    executeTask: async (t: Task) => { providers.lastTask = t; },
  },
};

const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request: string, ...rest: unknown[]) {
  if (request === 'vscode') { return 'vscode'; }
  return originalResolve.call(this, request, ...rest);
};
require.cache.vscode = { id: 'vscode', filename: 'vscode', loaded: true, exports: vscodeFake } as any;

// ---------------- tests ----------------
const wait = (ms: number) => new Promise(r => setTimeout(r, ms));
let passed = 0;
async function test(name: string, fn: () => Promise<void> | void) {
  try { await fn(); passed++; } catch (e) { console.error('FAIL:', name); console.error(e); process.exitCode = 1; }
}

async function main() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const ext = require('../extension');
  const pform = new FakeDocument(Uri.file(pformPath), 'pform', fs.readFileSync(pformPath, 'utf8'));
  docs.push(pform);
  ext.activate({ subscriptions: [] });
  vscodeFake.window.activeTextEditor = { document: pform };
  const lines = () => pform.getText().split('\n');
  const lineOf = (re: RegExp) => lines().findIndex(l => re.test(l));

  await test('commands are registered', () => {
    for (const c of ['pastel.run', 'pastel.build', 'pastel.openPreview', 'pastel.addHandler', 'pastel.newProject']) {
      assert.ok(commands[c], c);
    }
  });

  await test('completion: control types after "object X:"', async () => {
    const l = lineOf(/object Hint: TLabel/);
    pform.setText(lines().map((t, i) => (i === l ? '    object Hint: T' : t)).join('\n'));
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 18));
    assert.ok(items.some((i: CompletionItem) => i.label === 'TButton'));
    pform.setText(fs.readFileSync(pformPath, 'utf8'));
  });

  await test('completion: properties of the enclosing control', async () => {
    const l = lineOf(/Placeholder = 'Your name'/);
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 6));
    const names = items.map((i: CompletionItem) => i.label);
    assert.ok(names.includes('OnSubmit') === false, 'OnSubmit is already set, so it is not offered');
    assert.ok(names.includes('OnChange'));
    assert.ok(names.includes('Text'));
    assert.ok(!names.includes('Style'), 'TButton property must not appear on TEdit');
  });

  await test('completion: enum values', async () => {
    const l = lineOf(/Justify = End/);
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 16));
    assert.deepStrictEqual(items.map((i: CompletionItem) => i.label), ['Start', 'Center', 'End', 'SpaceBetween']);
  });

  await test('completion: event handlers from Home.pas', async () => {
    const l = lineOf(/OnClick = ClearClick/);
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 18));
    const names = items.map((i: CompletionItem) => i.label);
    assert.ok(names.includes('ClearClick') && names.includes('SendClick'), names.join(','));
  });

  await test('hover on a property', async () => {
    const l = lineOf(/Placeholder = /);
    const h = await providers.hover.provideHover(pform, new Position(l, 8));
    assert.ok(h && /Grey hint/.test(h.contents.value), h?.contents.value);
  });

  await test('Ctrl+click on a handler opens its code', async () => {
    const l = lineOf(/OnClick = SendClick/);
    const loc = await providers.definition.provideDefinition(pform, new Position(l, 20));
    assert.ok(loc, 'location');
    assert.strictEqual(loc.uri.fsPath, pasPath);
    assert.ok(/procedure THomeForm\.SendClick/.test(fs.readFileSync(pasPath, 'utf8').split('\n')[loc.range.line]));
  });

  await test('outline lists the controls', () => {
    const syms = providers.symbols.provideDocumentSymbols(pform);
    assert.strictEqual(syms[0].name, 'HomeForm');
    assert.ok(syms[0].children.some((s: DocumentSymbol) => s.name === 'Card'));
  });

  await test('typing a mistake shows a diagnostic', async () => {
    pform.setText(pform.getText().replace("Bold = True", "Bold = Yes"));
    listeners.change.forEach(f => f({ document: pform }));
    await wait(1500);
    const d = diagnosticStore.get(pformPath) ?? [];
    assert.ok(d.some(x => x.message === 'Bold expects True or False' && x.severity === 0), JSON.stringify(d));
    pform.setText(fs.readFileSync(pformPath, 'utf8'));
  });

  await test('missing handler: diagnostic, quick fix adds code', async () => {
    pform.setText(pform.getText().replace('OnClick = ClearClick', 'OnClick = ResetClick'));
    listeners.change.forEach(f => f({ document: pform }));
    await wait(1500);
    const d = (diagnosticStore.get(pformPath) ?? []).find(x => /ResetClick/.test(x.message));
    assert.ok(d, 'diagnostic for ResetClick');
    const actions = providers.actions.provideCodeActions(pform, d!.range, { diagnostics: [d] });
    assert.strictEqual(actions.length, 1);
    await commands[actions[0].command.command](...actions[0].command.arguments);
    const pas = fs.readFileSync(pasPath, 'utf8');
    assert.ok(/procedure ResetClick\(Sender: TObject\);/.test(pas), 'declaration');
    assert.ok(/procedure THomeForm\.ResetClick\(Sender: TObject\);\nbegin/.test(pas), 'implementation');
  });

  await test('form designer draws the unsaved text and the layout', async () => {
    pform.setText(pform.getText().replace("Text = 'Hello!'", "Text = 'Preview!'"));
    await commands['pastel.openPreview']();
    await wait(2500);
    const r = webviewMessages.find(m => m.type === 'render');
    assert.ok(r, JSON.stringify(webviewMessages.map(m => m.type === 'error' ? m.message : m.type)));
    assert.ok(Buffer.from(r.data, 'base64').subarray(1, 4).toString() === 'PNG');
    assert.ok(r.layout.controls.some((c: any) => c.name === 'SendButton' && c.w > 0), 'layout has SendButton');
    assert.ok(webviewMessages.some(m => m.type === 'schema'), 'toolbox schema sent');
  });

  const send = async (m: unknown) => { await providers.fromWebview(m); await wait(1200); };

  await test('designer: selecting shows the properties', async () => {
    await send({ type: 'select', name: 'SendButton' });
    const sel = [...webviewMessages].reverse().find(m => m.type === 'select');
    assert.strictEqual(sel.name, 'SendButton');
    assert.strictEqual(sel.props.find((p: any) => p.name === 'Text').value, 'Send');
    assert.ok(sel.handlers.includes('SendClick'));
  });

  await test('designer: editing a property changes the .pform text', async () => {
    await send({ type: 'setProp', name: 'SendButton', prop: 'Text', propType: 'string', value: 'Gönder' });
    assert.ok(pform.getText().includes("        Text = 'Gönder'"), pform.getText());
    await send({ type: 'setProp', name: 'SendButton', prop: 'Style', propType: 'enum', value: 'Danger' });
    assert.ok(pform.getText().includes('        Style = Danger'));
  });

  await test('designer: add, move and delete controls', async () => {
    await send({ type: 'add', className: 'TLabel', parent: 'Card', index: 0 });
    assert.ok(/object Card: TCard\n    object Label1: TLabel\n      Text = 'Label1'\n    end/.test(pform.getText()), pform.getText());
    await send({ type: 'move', name: 'Label1', parent: 'HomeForm', index: 0 });
    assert.ok(/object HomeForm: THomeForm[\s\S]*?\n  object Label1: TLabel\n    Text = 'Label1'\n  end\n  object Card/.test(pform.getText()), pform.getText());
    await send({ type: 'delete', name: 'Label1' });
    assert.ok(!pform.getText().includes('Label1'));
    const r = [...webviewMessages].reverse().find(m => m.type === 'render');
    assert.ok(r.layout.controls.every((c: any) => c.name !== 'Label1'), 'redrawn after delete');
  });

  await test('build command runs a task with the problem matcher', async () => {
    await commands['pastel.build']();
    const t = providers.lastTask as Task;
    assert.deepStrictEqual((t.execution as ProcessExecution).args, ['build']);
    assert.strictEqual(t.matcher, '$pastel');
  });

  console.log(`integration: ${passed} passed`);
  process.exit(process.exitCode ?? 0);
}

main();
