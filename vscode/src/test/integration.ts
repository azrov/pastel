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
class Selection extends Range {
  get active() { return this.end; }
  get anchor() { return this.start; }
}
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
class MarkdownString {
  constructor(public value = '') {}
  appendCodeblock(code: string, _lang?: string) { this.value += '\n```\n' + code + '\n```\n'; return this; }
  appendMarkdown(t: string) { this.value += t; return this; }
}
class CompletionList { constructor(public items: CompletionItem[], public isIncomplete?: boolean) {} }
class SignatureHelp { signatures: any[] = []; activeSignature = 0; activeParameter = 0; }
class SignatureInformation { parameters: any[] = []; constructor(public label: string, public documentation?: unknown) {} }
class ParameterInformation { constructor(public label: string) {} }
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
class TextEdit {
  constructor(public range: Range, public newText: string) {}
  static replace(r: Range, t: string) { return new TextEdit(r, t); }
}
class FakeCollection {
  map = new Map<string, any>();
  add(i: any) { this.map.set(i.id, i); }
  delete(id: string) { this.map.delete(id); }
  get(id: string) { return this.map.get(id); }
  replace(items: any[]) { this.map.clear(); items.forEach(i => this.add(i)); }
  forEach(fn: (i: any) => void) { [...this.map.values()].forEach(fn); }
  get size() { return this.map.size; }
}
class TestMessage { location?: Location; constructor(public message: string) {} }
const testProfiles: Record<string, (req: any, token: any) => Promise<void>> = {};
const testResults: Record<string, { state: string; message?: TestMessage }> = {};
const testController: any = {
  items: new FakeCollection(),
  resolveHandler: undefined as any,
  refreshHandler: undefined as any,
  createTestItem: (id: string, label: string, uri: Uri) => ({ id, label, uri, children: new FakeCollection(), range: undefined }),
  createRunProfile: (label: string, _kind: number, handler: any) => { testProfiles[label] = handler; return { dispose() {} }; },
  createTestRun: () => ({
    started: (i: any) => { testResults[i.id] = { state: 'started' }; },
    passed: (i: any) => { testResults[i.id] = { state: 'passed' }; },
    skipped: (i: any) => { testResults[i.id] = { state: 'skipped' }; },
    failed: (i: any, m: TestMessage) => { testResults[i.id] = { state: 'failed', message: m }; },
    errored: (i: any, m: TestMessage) => { testResults[i.id] = { state: 'errored', message: m }; },
    appendOutput() {},
    end() {},
  }),
  dispose() {},
};
class ThemeIcon { constructor(public id: string) {} }
class TreeItem {
  iconPath?: unknown; description?: string; tooltip?: string; command?: any; resourceUri?: Uri; contextValue?: string;
  constructor(public label: string, public collapsibleState?: number) {}
}
class EventEmitter { event = () => ({ dispose() {} }); fire() {} }
class SymbolInformation { constructor(public name: string, public kind: number, public containerName: string, public location: Location) {} }
class ProcessExecution { constructor(public process: string, public args: string[], public options: unknown) {} }

class FakeDocument {
  version = 1;
  constructor(public uri: Uri, public languageId: string, private text: string) {}
  getText(r?: Range) {
    if (!r) { return this.text; }
    if (r.start.line === r.end.line) { return this.lineAt(r.start.line).text.substring(r.start.character, r.end.character); }
    const ls = this.text.split('\n').slice(r.start.line, r.end.line + 1);
    ls[ls.length - 1] = ls[ls.length - 1].substring(0, r.end.character);
    ls[0] = ls[0].substring(r.start.character);
    return ls.join('\n');
  }
  setText(t: string) { this.text = t; this.version++; }
  get fileName() { return this.uri.fsPath; }
  get lineCount() { return this.text.split('\n').length; }
  lineAt(i: number) {
    const t = this.text.split('\n')[i] ?? '';
    return { text: t, firstNonWhitespaceCharacterIndex: Math.max(0, t.search(/\S/)), range: new Range(i, 0, i, t.length) };
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

let clip = '';
const vscodeFake = {
  env: { clipboard: { writeText: async (t: string) => { clip = t; }, readText: async () => clip } },
  Position, Range, Selection, SnippetString, CompletionItem, MarkdownString, Hover, Location, Diagnostic,
  CompletionList, SignatureHelp, SignatureInformation, ParameterInformation,
  CodeAction, DocumentSymbol, Uri, Task, ProcessExecution, TextEdit, TestMessage,
  TestRunProfileKind: { Run: 1, Debug: 2 },
  DebugConfigurationProviderTriggerKind: { Initial: 1, Dynamic: 2 },
  tests: { createTestController: () => testController },
  debug: {
    registerDebugConfigurationProvider: (_t: string, p: unknown) => { providers.debug = p; return { dispose() {} }; },
    onDidTerminateDebugSession: () => ({ dispose() {} }),
    startDebugging: async () => true,
  },
  extensions: { getExtension: (id: string) => (id === 'ms-vscode.cpptools' ? {} : undefined) },
  CompletionItemKind: { Class: 6, Property: 9, Event: 22, EnumMember: 19, Value: 11, Method: 1, Keyword: 13, Color: 15,
    Text: 0, Function: 2, Field: 4, Variable: 5, Interface: 7, Module: 8, Enum: 12, Constant: 20, Struct: 21, TypeParameter: 24 },
  DiagnosticSeverity: { Error: 0, Warning: 1 },
  SymbolKind: { Module: 1, Class: 4, Method: 5, Property: 6, Field: 7, Interface: 10, Function: 11, Variable: 12,
    Object: 18, Struct: 22, TypeParameter: 25 },
  TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
  ThemeIcon, TreeItem, EventEmitter, SymbolInformation,
  CodeActionKind: { QuickFix: 'quickfix' },
  StatusBarAlignment: { Left: 1 },
  ViewColumn: { Beside: -2, Active: -1 },
  TaskGroup: { Build: 'build' },
  TaskScope: { Workspace: 2 },
  TaskRevealKind: { Always: 1 },
  TaskPanelKind: { Dedicated: 2 },
  CodeLens: class { constructor(public range: unknown, public command: any) {} },
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
    registerCompletionItemProvider: (s: any, p: unknown) => {
      providers[JSON.stringify(s).includes('pascal') ? 'pascalCompletion' : 'completion'] = p; return { dispose() {} };
    },
    registerHoverProvider: (s: any, p: unknown) => {
      providers[JSON.stringify(s).includes('pascal') ? 'pascalHover' : 'hover'] = p; return { dispose() {} };
    },
    registerDefinitionProvider: (s: any, p: unknown) => {
      providers[JSON.stringify(s).includes('pascal') ? 'pascalDefinition' : 'definition'] = p; return { dispose() {} };
    },
    registerDocumentSymbolProvider: (s: any, p: unknown) => {
      providers[JSON.stringify(s).includes('pascal') ? 'pascalSymbols' : 'symbols'] = p; return { dispose() {} };
    },
    registerCodeActionsProvider: (s: any, p: unknown) => {
      providers[JSON.stringify(s).includes('pascal') ? 'pascalActions' : 'actions'] = p; return { dispose() {} };
    },
    registerSignatureHelpProvider: (_s: unknown, p: unknown) => { providers.signature = p; return { dispose() {} }; },
    registerReferenceProvider: (_s: unknown, p: unknown) => { providers.references = p; return { dispose() {} }; },
    registerRenameProvider: (_s: unknown, p: unknown) => { providers.rename = p; return { dispose() {} }; },
    registerWorkspaceSymbolProvider: (p: unknown) => { providers.workspaceSymbols = p; return { dispose() {} }; },
    registerDocumentFormattingEditProvider: (_s: unknown, p: unknown) => { providers.formatting = p; return { dispose() {} }; },
    registerCodeLensProvider: (_s: unknown, p: unknown) => { providers.codeLens = p; return { dispose() {} }; },
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
    showTextDocument: async (d: any) => { providers.lastShown = d; return { selection: undefined, revealRange() {} }; },
    setStatusBarMessage: (m: string) => { providers.status = m; return { dispose() {} }; },
    showInputBox: async (o: { prompt: string; value?: string }) =>
      o.prompt.startsWith('URL') ? (o.value ?? '').replace('http://localhost:8080', providers.serverBase) : o.value,
    createOutputChannel: () => ({ appendLine: (t: string) => { providers.requestLog = (providers.requestLog ?? '') + t; }, show() {} }),
    registerTreeDataProvider: (_id: string, p: unknown) => { providers.tree = p; return { dispose() {} }; },
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
      active: false,
      title: '',
    }),
  },
  workspace: {
    textDocuments: docs,
    workspaceFolders: [{ uri: Uri.file(projectDir) }],
    getConfiguration: () => ({ get: (k: string, d?: unknown) => (k === 'path' ? process.env.PASTEL_BIN ?? 'pastel' : d) }),
    findFiles: async (pattern: string) => {
      if (pattern.includes('pastel.toml')) { return [Uri.file(path.join(projectDir, 'pastel.toml'))]; }
      const out: Uri[] = [];
      const walk = (d: string) => fs.readdirSync(d).forEach(n => {
        const f = path.join(d, n);
        if (fs.statSync(f).isDirectory()) { walk(f); } else if (/\.pas$/.test(n)) { out.push(Uri.file(f)); }
      });
      walk(projectDir);
      return out;
    },
    createFileSystemWatcher: () => ({ onDidChange() {}, onDidCreate() {}, onDidDelete() {}, dispose() {} }),
    onDidChangeWorkspaceFolders: on('folders'),
    onDidOpenTextDocument: on('open'),
    onDidSaveTextDocument: on('save'),
    onDidChangeTextDocument: on('change'),
    onDidCloseTextDocument: on('close'),
    openTextDocument: async (u: Uri | string) => {
      const uri = typeof u === 'string' ? Uri.file(u) : u;
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
  const stored = new Map<string, unknown>();
  const globalState = { get: (k: string) => stored.get(k), update: async (k: string, v: unknown) => { stored.set(k, v); } };
  ext.activate({ subscriptions: [], extensionPath: path.resolve(__dirname, '..', '..'), globalState });
  vscodeFake.window.activeTextEditor = { document: pform };
  const lines = () => pform.getText().split('\n');
  const lineOf = (re: RegExp) => lines().findIndex(l => re.test(l));

  await test('the open project is remembered for the Welcome page', () => {
    const recent = stored.get('pastel.recentProjects') as { name: string; kind: string }[];
    assert.ok(recent && recent[0].kind === 'app', JSON.stringify(recent));
  });

  await test('commands are registered', () => {
    for (const c of ['pastel.run', 'pastel.build', 'pastel.openPreview', 'pastel.addHandler', 'pastel.newProject', 'pastel.welcome']) {
      assert.ok(commands[c], c);
    }
  });

  await test('completion: control types after "object X:"', async () => {
    const l = lineOf(/object HintLabel: TLabel/);
    pform.setText(lines().map((t, i) => (i === l ? '    object HintLabel: T' : t)).join('\n'));
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, '    object HintLabel: T'.length));
    assert.ok(items.some((i: CompletionItem) => i.label === 'TButton'));
    pform.setText(fs.readFileSync(pformPath, 'utf8'));
  });

  await test('completion: properties of the enclosing control', async () => {
    const l = lineOf(/Placeholder = 'Your name'/);
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 4));
    const names = items.map((i: CompletionItem) => i.label);
    assert.ok(names.includes('OnSubmit') === false, 'OnSubmit is already set, so it is not offered');
    assert.ok(names.includes('OnChange'));
    assert.ok(names.includes('Text'));
    assert.ok(!names.includes('Style'), 'TButton property must not appear on TEdit');
  });

  await test('completion: enum values', async () => {
    const l = lineOf(/Style = Secondary/);
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 12));
    assert.deepStrictEqual(items.map((i: CompletionItem) => i.label), ['Primary', 'Secondary', 'Danger', 'Flat']);
  });

  await test('completion: event handlers from Home.pas', async () => {
    const l = lineOf(/OnClick = ClearClick/);
    const items = await providers.completion.provideCompletionItems(pform, new Position(l, 14));
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
    assert.ok(syms[0].children.some((s: DocumentSymbol) => s.name === 'SendButton'));
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
    assert.ok(pform.getText().includes("    Text = 'Gönder'"), pform.getText());
    await send({ type: 'setProp', name: 'SendButton', prop: 'Style', propType: 'enum', value: 'Danger' });
    assert.ok(pform.getText().includes('    Style = Danger'));
  });

  await test('designer: add, move and delete controls', async () => {
    // the form has Layout = Free: a new control goes where it was dropped
    await send({ type: 'add', className: 'TLabel', parent: 'HomeForm', index: 9999, left: 24, top: 256 });
    assert.ok(/  object Label1: TLabel\n    Text = 'Label1'\n    Left = 24\n    Top = 256\n  end\nend/.test(pform.getText()), pform.getText());
    let r0 = [...webviewMessages].reverse().find(m => m.type === 'render');
    const lab = r0.layout.controls.find((c: any) => c.name === 'Label1');
    assert.ok(lab && lab.x === 24 && lab.y === 256, JSON.stringify(lab));
    assert.ok(r0.layout.controls[0].free, 'the form is free');
    await send({ type: 'place', parent: null, items: [{ name: 'Label1', left: 40, top: 264, width: 120 }] });
    assert.ok(/Left = 40\n    Top = 264\n    Width = 120/.test(pform.getText()), pform.getText());
    r0 = [...webviewMessages].reverse().find(m => m.type === 'render');
    assert.ok(r0.layout.controls.some((c: any) => c.name === 'Label1' && c.x === 40 && c.w === 120), 'redrawn at its new place');
    await send({ type: 'move', name: 'Label1', parent: 'HomeForm', index: 0 });
    assert.ok(/object HomeForm: THomeForm[\s\S]*?\n  object Label1: TLabel\n    Text = 'Label1'[\s\S]*?\n  end\n  object Heading/.test(pform.getText()), pform.getText());
    await send({ type: 'delete', name: 'Label1' });
    assert.ok(!pform.getText().includes('Label1'));
    const r = [...webviewMessages].reverse().find(m => m.type === 'render');
    assert.ok(r.layout.controls.every((c: any) => c.name !== 'Label1'), 'redrawn after delete');
  });

  await test('Send Request lens above a route, and the request', async () => {
    const apiDoc = new FakeDocument(Uri.file(path.join(projectDir, 'src', 'api.pas')), 'pascal',
      "procedure TApi.Routes(Web: TWebServer);\nbegin\n  Web.Post('/api/tasks/:id', @Change);\nend;\n");
    const lenses = providers.codeLens.provideCodeLenses(apiDoc);
    assert.strictEqual(lenses.length, 1);
    assert.strictEqual(lenses[0].command.title, '▶ Send POST /api/tasks/:id');
    const http = await import('http');
    const server = http.createServer((req, res) => {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ url: req.url, body })); });
    });
    await new Promise<void>(r => server.listen(0, '127.0.0.1', r));
    providers.serverBase = `http://127.0.0.1:${(server.address() as any).port}`;
    try {
      await commands['pastel.sendRequest'](...lenses[0].command.arguments);
    } finally {
      server.close();
    }
    assert.ok(providers.requestLog.includes('HTTP 200'), providers.requestLog);
    assert.ok(providers.requestLog.includes('"url": "/api/tasks/1"'), providers.requestLog);
    assert.ok(providers.requestLog.includes('"body": "{}"'), providers.requestLog);
  });

  await test('sidebar shows actions, forms and settings', async () => {
    const top = await providers.tree.getChildren();
    assert.deepStrictEqual(top.map((n: any) => n.label), [path.basename(projectDir), 'Forms', 'Source', 'Project settings']);
    const actions = top[0].children.map((n: any) => `${n.label}${n.description ? ' ' + n.description : ''}`);
    assert.ok(actions.includes('Run F9') && actions.includes('Build Ctrl+F9'), actions.join(','));
    const home = top[1].children[0];
    assert.strictEqual(home.label, 'Home');
    assert.strictEqual(home.command.command, 'pastel.openPreview');
    assert.deepStrictEqual(home.children.map((n: any) => n.label), ['Home.pform', 'Home.pas']);
  });

  await test('designer: copy, paste, duplicate, rename with code, undo', async () => {
    const before = pform.getText();
    const pasBefore = fs.readFileSync(pasPath, 'utf8');
    await send({ type: 'copy', name: 'SendButton' });
    assert.ok(/^object SendButton: TButton/.test(clip), clip);
    await send({ type: 'duplicate', name: 'SendButton' });
    assert.ok(/object SendButton1: TButton/.test(pform.getText()), pform.getText());
    await send({ type: 'undo' });
    assert.strictEqual(pform.getText(), before, 'undo takes the copy away');
    await send({ type: 'redo' });
    assert.ok(/object SendButton1: TButton/.test(pform.getText()), 'redo');
    await send({ type: 'undo' });
    await send({ type: 'rename', name: 'NameEdit', newName: 'FullNameEdit' });
    assert.ok(pform.getText().includes('object FullNameEdit: TEdit'));
    const pasDoc2 = docs.find(x => x.uri.fsPath === pasPath)!;
    assert.ok(/FullNameEdit\.Text/.test(pasDoc2.getText()) && !/\bNameEdit\.Text/.test(pasDoc2.getText()),
      'the code follows: ' + pasDoc2.getText());
    pform.setText(before);
    pasDoc2.setText(pasBefore);
    fs.writeFileSync(pasPath, pasBefore);
  });

  await test('sidebar shows routes, jobs and migrations', async () => {
    const api = path.join(projectDir, 'src', 'apiroutes.pas');
    const mig = path.join(projectDir, 'database', 'migrations');
    fs.writeFileSync(api, "unit ApiRoutes;\n// Web.Get('/no', @No);\nWeb.Get('/api/tasks', @ListTasks);\nWeb.Delete('/api/tasks/:id', @DeleteTask);\nEvery(60, @Cleanup);\n");
    fs.mkdirSync(mig, { recursive: true });
    fs.writeFileSync(path.join(mig, '001_create_tasks.sql'), 'create table tasks (id {{id}});\n');
    try {
      const top = await providers.tree.getChildren();
      const names = top.map((n: any) => n.label);
      assert.deepStrictEqual(names.slice(1, 5), ['Forms', 'Routes', 'Jobs', 'Migrations'], names.join(','));
      const routes = top[2].children;
      assert.deepStrictEqual(routes.map((n: any) => `${n.label} ${n.description}`), ['GET /api/tasks ListTasks', 'DELETE /api/tasks/:id DeleteTask']);
      assert.strictEqual(routes[1].contextValue, 'pastelRoute');
      assert.strictEqual(routes[1].command.arguments[1].selection.start.line, 3, 'opens at the route');
      assert.strictEqual(top[3].children[0].description, 'every 60 s');
      const m = top[4].children.map((n: any) => n.label);
      assert.deepStrictEqual(m, ['Run Migrations', 'Migration Status', 'New Migration…', '001_create_tasks']);
    } finally {
      fs.unlinkSync(api);
      fs.rmSync(path.join(projectDir, 'database'), { recursive: true });
    }
  });

  const pasDoc = new FakeDocument(Uri.file(pasPath), 'pascal', fs.readFileSync(pasPath, 'utf8'));
  docs.push(pasDoc);
  const pasLine = (re: RegExp) => pasDoc.getText().split('\n').findIndex(l => re.test(l));

  await test('Pascal: members of a form control, hover, parameter hints', async () => {
    // the form's generated unit exists after a check or build
    const text = pasDoc.getText();
    pasDoc.setText(text.replace("  NameEdit.SetFocus;", "  NameEdit.SetFocus;\n  NameEdit."));
    listeners.change.forEach(f => f({ document: pasDoc, contentChanges: [{}] }));
    await wait(4000);
    const l = pasLine(/^  NameEdit\.$/);
    const list = await providers.pascalCompletion.provideCompletionItems(pasDoc, new Position(l, 11));
    const names = (list?.items ?? []).map((i: any) => i.label);
    assert.ok(names.includes('Text') && names.includes('SetFocus'), names.slice(0, 30).join(','));
    const errs = (diagnosticStore.get(pasPath) ?? []).map(d => d.message);
    assert.ok(errs.some(m => /Syntax error|expected/i.test(m)), 'the compiler sees the unfinished line: ' + errs.join(' | '));
    pasDoc.setText(text);
    const h = providers.pascalHover.provideHover(pasDoc, new Position(pasLine(/if Trim\(NameEdit/), 6));
    assert.ok(h && /function Trim/.test(h.contents.value), h?.contents.value);
    const sl = pasLine(/if Trim\(NameEdit/);
    const sig = providers.signature.provideSignatureHelp(pasDoc, new Position(sl, pasDoc.lineAt(sl).text.indexOf('Trim(') + 5));
    assert.ok(sig && sig.signatures.some((s: any) => /Trim\(const S: (string|ansistring)/i.test(s.label)), JSON.stringify(sig?.signatures.map((s: any) => s.label)));
  });

  await test('Pascal: add a missing unit, create method bodies', async () => {
    const text = pasDoc.getText();
    const l = pasLine(/^  NameEdit\.Text := '';/);
    const diag = new Diagnostic(new Range(l, 2, l, 9), 'Identifier not found "StrToIntDef"', 0);
    pasDoc.setText(text.replace('uses\n  SysUtils, Pastel.UI, Home.g;', 'uses\n  Pastel.UI, Home.g;'));
    const acts = providers.pascalActions.provideCodeActions(pasDoc, diag.range, { diagnostics: [diag] });
    const add = acts.find((a: any) => /Add "SysUtils" to uses/i.test(a.title));
    assert.ok(add, acts.map((a: any) => a.title).join(','));
    pasDoc.setText(text.replace('    procedure ResetClick(Sender: TObject);', '    procedure ResetClick(Sender: TObject);\n    function Total(A, B: Integer; const Name: string): Integer;'));
    const cls = pasLine(/function Total/);
    const fix = providers.pascalActions.provideCodeActions(pasDoc, new Range(cls, 4, cls, 4), { diagnostics: [] });
    assert.ok(fix.some((a: any) => /Create 1 method body/.test(a.title)), fix.map((a: any) => a.title).join(','));
    const before = fs.readFileSync(pasPath, 'utf8');
    vscodeFake.window.activeTextEditor = { document: pasDoc, selection: { active: new Position(cls, 4) }, revealRange() {} } as any;
    await commands['pastel.completeClass']();
    assert.ok(!providers.status || !/Pastel: (put|every)/.test(providers.status), providers.status);
    const edited = docs.find(x => x.uri.fsPath === pasPath)!;     // applyEdit changes the first open copy
    assert.ok(/function THomeForm\.Total\(A, B: Integer; const Name: string\): Integer;\nbegin\n\nend;/.test(edited.getText()), edited.getText().split('implementation')[1]);
    edited.setText(before);
    fs.writeFileSync(pasPath, before);
    pasDoc.setText(before);
  });

  await test('Pascal outline', () => {
    const syms = providers.pascalSymbols.provideDocumentSymbols(pasDoc);
    const cls = syms.find((s: any) => s.name === 'THomeForm');
    assert.ok(cls, syms.map((s: any) => s.name).join(','));
    assert.ok(cls.children.some((c: any) => c.name === 'SendClick'));
    assert.ok(syms.some((s: any) => s.name === 'THomeForm.SendClick'));
  });

  await test('Ctrl+click on a unit in uses opens the framework file', async () => {
    const l = pasLine(/Pastel\.UI/);
    const ch = pasDoc.lineAt(l).text.indexOf('Pastel.UI') + 8;
    const loc = await providers.pascalDefinition.provideDefinition(pasDoc, new Position(l, ch));
    assert.ok(loc && /pastel\.ui\.pas$/.test(loc.uri.fsPath), JSON.stringify(loc));
  });

  await test('Ctrl+click on a method declaration goes to its body', async () => {
    const l = pasLine(/^\s+procedure SendClick/);
    const ch = pasDoc.lineAt(l).text.indexOf('SendClick') + 2;
    const loc = await providers.pascalDefinition.provideDefinition(pasDoc, new Position(l, ch));
    assert.strictEqual(loc.range.start.line, pasLine(/^procedure THomeForm\.SendClick/));
  });

  await test('Ctrl+click on a framework class finds it', async () => {
    const l = pasLine(/THomeForm = class/);
    pasDoc.setText(pasDoc.getText().replace('THomeForm = class(THomeFormBase)', 'THomeForm = class(THomeFormBase) // TCanvas32'));
    const ch = pasDoc.lineAt(l).text.indexOf('TCanvas32') + 3;
    const locs = await providers.pascalDefinition.provideDefinition(pasDoc, new Position(l, ch));
    assert.ok(Array.isArray(locs) && locs.some((x: any) => /pastel\.graphics\.pas$/.test(x.uri.fsPath)));
    pasDoc.setText(fs.readFileSync(pasPath, 'utf8'));
  });

  await test('workspace symbol search includes the framework', async () => {
    const res = await providers.workspaceSymbols.provideWorkspaceSymbols('TCanvas32');
    assert.ok(res.some((r: any) => r.name === 'TCanvas32' && r.containerName === 'Pastel framework'));
  });

  await test('Ctrl+Shift+Down: declaration to body', async () => {
    const l = pasLine(/^\s+procedure ClearClick/);
    const editor: any = { document: pasDoc, selection: new Selection(new Position(l, 6), new Position(l, 6)), revealRange() {} };
    vscodeFake.window.activeTextEditor = editor;
    await commands['pastel.toggleDeclaration']();
    assert.strictEqual(editor.selection.start.line, pasLine(/^procedure THomeForm\.ClearClick/));
  });

  await test('F12: from the form to its code', async () => {
    vscodeFake.window.activeTextEditor = { document: pform };
    await commands['pastel.toggleFormCode']();
    assert.strictEqual(providers.lastShown.fsPath, pasPath);
  });

  await test('build command runs a task with the problem matcher', async () => {
    await commands['pastel.build']();
    const t = providers.lastTask as Task;
    assert.deepStrictEqual((t.execution as ProcessExecution).args, ['build']);
    assert.strictEqual(t.matcher, '$pastel');
  });

  await test('Format Document uses pastel fmt', async () => {
    const messy = new FakeDocument(Uri.file(pasPath), 'pascal', 'unit X;\ninterface\nimplementation\nprocedure P;\nbegin\nif A then\nB:=1;\nend;\nend.\n');
    const edits = await providers.formatting.provideDocumentFormattingEdits(messy);
    assert.strictEqual(edits.length, 1);
    assert.ok(edits[0].newText.includes('\n  if A then\n    B := 1;\n'), edits[0].newText);
  });

  await test('broken code is left alone, with a note in the status bar', async () => {
    const broken = new FakeDocument(Uri.file(pasPath), 'pascal', 'begin\nif A then begin\nend.\n');
    const edits = await providers.formatting.provideDocumentFormattingEdits(broken);
    assert.strictEqual(edits.length, 0);
    assert.ok(String(providers.status).includes('could not format'), providers.status);
  });

  await test('run and watch, format all', async () => {
    await commands['pastel.runWatch']();
    assert.deepStrictEqual(((providers.lastTask as Task).execution as ProcessExecution).args, ['run', '--watch']);
    await commands['pastel.formatAll']();
    assert.deepStrictEqual(((providers.lastTask as Task).execution as ProcessExecution).args, ['fmt']);
  });

  await test('F5 builds and starts the program in gdb', async () => {
    const config = await providers.debug.resolveDebugConfiguration(undefined, {});
    assert.strictEqual(config.type, 'cppdbg');
    assert.ok(config.program.endsWith(path.join('build', 'linux', 'debug', path.basename(projectDir))), config.program);
    assert.ok(fs.existsSync(config.program));
    assert.strictEqual(config.cwd, projectDir);
    const script = config.setupCommands.map((c: { text: string }) => c.text).find((t: string) => t.startsWith('source '));
    assert.ok(script && fs.existsSync(script.substring(7)), 'gdb script for Pascal strings');
  });

  await test('Testing view finds, runs and reports tests', async () => {
    const testFile = path.join(projectDir, 'tests', 'sample_test.pas');
    fs.mkdirSync(path.dirname(testFile), { recursive: true });
    fs.writeFileSync(testFile, [
      'unit Sample_Test;', '{$mode objfpc}{$H+}', 'interface', 'uses Pastel.Testing;', 'type',
      '  TSampleTests = class(TTestSuite)', '  published', '    procedure AddsUp;', '    procedure GoesWrong;', '  end;',
      'implementation', 'procedure TSampleTests.AddsUp;', 'begin', '  AssertEquals(4, 2 + 2);', 'end;',
      'procedure TSampleTests.GoesWrong;', 'begin', '  AssertEquals(5, 2 + 2);', 'end;',
      'initialization', '  RegisterTests(TSampleTests);', 'end.', ''].join('\n'));
    try {
      await testController.resolveHandler(undefined);
      const fileItem = testController.items.get(testFile);
      assert.ok(fileItem, 'test file listed');
      const suite = fileItem.children.get(`${projectDir}::TSampleTests`);
      assert.strictEqual(suite.label, 'Sample');
      const ok = suite.children.get(`${projectDir}::TSampleTests.AddsUp`);
      assert.strictEqual(ok.label, 'adds up');
      await testProfiles.Run({ include: undefined, exclude: [] }, { isCancellationRequested: false });
      assert.strictEqual(testResults[`${projectDir}::TSampleTests.AddsUp`].state, 'passed');
      const bad = testResults[`${projectDir}::TSampleTests.GoesWrong`];
      assert.strictEqual(bad.state, 'failed');
      assert.ok(bad.message!.message.includes('expected 5 but got 4'), bad.message!.message);
      assert.strictEqual((bad.message!.location!.range as unknown as Position).line, 17);
      delete testResults[`${projectDir}::TSampleTests.AddsUp`];
      await testProfiles.Run({ include: [ok], exclude: [] }, { isCancellationRequested: false });
      assert.strictEqual(testResults[`${projectDir}::TSampleTests.AddsUp`].state, 'passed');
    } finally {
      fs.rmSync(path.dirname(testFile), { recursive: true, force: true });
    }
  });

  console.log(`integration: ${passed} passed`);
  process.exit(process.exitCode ?? 0);
}

main();
