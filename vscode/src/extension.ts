import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { registerFormatter } from './format';
import { registerDebugging } from './debug';
import { registerTesting } from './testing';
import { currentProjectRoot, findProjectRoot, pastelPath, readProjectInfo, runnableProjectRoot, runPastel, workspaceProjects } from './cli';
import {
  allObjects, classFor, completionContext, declaredProcedures, enclosingObjects,
  findProcedure, handlerInserts, missingHandlerName, missingHandlerParams, parseIssues, Schema, SchemaClass,
  SchemaProperty, stripComment,
} from './model';
import { FormPreview } from './preview';
import { PascalIndex, registerNavigation, setDefinitionHook, toggleDeclarationCommand } from './navigation';
import { registerSidebar } from './sidebar';
import { registerRequests } from './requests';
import { analyzerDefinition, registerIntellisense } from './intellisense';

let schema: Schema | undefined;
let schemaLoading: Promise<Schema | undefined> | undefined;
let diagnostics: vscode.DiagnosticCollection;
const pascalIndex = new PascalIndex();
const checkTimers = new Map<string, NodeJS.Timeout>();

const PLATFORMS: { label: string; description: string }[] = [
  { label: 'linux', description: 'Linux, 64-bit PC' },
  { label: 'windows', description: 'Windows, 64-bit' },
  { label: 'windows32', description: 'Windows, 32-bit' },
  { label: 'rpi', description: 'Raspberry Pi, 64-bit OS' },
  { label: 'rpi32', description: 'Raspberry Pi, 32-bit OS' },
  { label: 'macos', description: 'macOS, Intel' },
  { label: 'macos-arm64', description: 'macOS, Apple Silicon' },
];

let extensionContext: vscode.ExtensionContext | undefined;

/** The units of packages and of libraries outside the workspace, for completion and go to definition. */
async function indexPackages(): Promise<void> {
  const inWorkspace = (dir: string) => (vscode.workspace.workspaceFolders ?? [])
    .some(f => (dir + path.sep).startsWith(f.uri.fsPath + path.sep));
  for (const p of await workspaceProjects()) {
    const r = await runPastel(['deps', '--json'], p.root);
    if (r.code !== 0) {
      continue;
    }
    try {
      for (const d of JSON.parse(r.stdout) as { root: string }[]) {
        if (d.root && !inWorkspace(d.root)) {
          pascalIndex.addLibrary(d.root);
        }
      }
    } catch {
      // not JSON: an older pastel
    }
  }
}

export function activate(context: vscode.ExtensionContext): void {
  extensionContext = context;
  diagnostics = vscode.languages.createDiagnosticCollection('pastel');
  context.subscriptions.push(diagnostics);

  updateProjectContext();
  registerSidebar(context);
  registerRequests(context);
  registerNavigation(context, pascalIndex);
  const schemaReady = loadSchema();
  schemaReady.then(sch => pascalIndex.build(sch?.frameworkDir)).then(() => indexPackages());
  const lockWatcher = vscode.workspace.createFileSystemWatcher('**/{pastel.toml,pastel.lock}');
  lockWatcher.onDidChange(() => indexPackages());
  lockWatcher.onDidCreate(() => indexPackages());
  context.subscriptions.push(lockWatcher);
  registerIntellisense(context, pascalIndex, schemaReady);
  setDefinitionHook(analyzerDefinition);
  updateFormContext(vscode.window.activeTextEditor);
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(e => updateFormContext(e)),
    vscode.workspace.onDidChangeTextDocument(e => {
      if (e.document.languageId === 'pascal' || e.document.languageId === 'objectpascal') {
        pascalIndex.update(e.document.uri.fsPath, e.document.getText());
      }
    }),
  );
  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => updateProjectContext()),
    // a control of the project (src/controls/) was saved: the toolbox and the designer follow
    vscode.workspace.onDidSaveTextDocument(async d => {
      if (/[\\/]src[\\/]controls[\\/][^\\/]+\.pas$/i.test(d.uri.fsPath)) {
        schema = undefined;
        schemaLoading = undefined;
        await loadSchema();
        await FormPreview.controlsChanged();
      }
    }));

  // status bar: run button
  const runItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  runItem.text = '$(play) Pastel Run';
  runItem.tooltip = 'Build and run the Pastel project';
  runItem.command = 'pastel.run';
  context.subscriptions.push(runItem);
  vscode.workspace.findFiles('**/pastel.toml', '**/build/**', 1).then(found => {
    if (found.length > 0) {
      runItem.show();
    }
  });

  // commands
  registerFormatter(context);
  registerDebugging(context);
  registerTesting(context);

  context.subscriptions.push(
    vscode.commands.registerCommand('pastel.run', () => runTask('run')),
    vscode.commands.registerCommand('pastel.chooseRunProject', async () => {
      await context.workspaceState.update('pastel.runProject', undefined);
      await runTask('run');
    }),
    vscode.commands.registerCommand('pastel.runWatch', () => runTask('run', { watch: true })),
    vscode.commands.registerCommand('pastel.testWatch', () => runTask('test', { watch: true })),
    vscode.commands.registerCommand('pastel.formatAll', () => runTask('fmt')),
    vscode.commands.registerCommand('pastel.build', () => runTask('build')),
    vscode.commands.registerCommand('pastel.test', () => runTask('test')),
    vscode.commands.registerCommand('pastel.buildRelease', () => runTask('build', { release: true })),
    vscode.commands.registerCommand('pastel.buildTarget', buildForPlatform),
    vscode.commands.registerCommand('pastel.clean', () => runTask('clean')),
    vscode.commands.registerCommand('pastel.doctor', doctor),
    vscode.commands.registerCommand('pastel.newProject', newProject),
    vscode.commands.registerCommand('pastel.newForm', newForm),
    vscode.commands.registerCommand('pastel.openPreview', openPreview),
    vscode.commands.registerCommand('pastel.refreshSchema', async () => {
      schema = undefined;
      schemaLoading = undefined;
      if (await loadSchema()) {
        vscode.window.showInformationMessage('Pastel: control list reloaded.');
      }
    }),
    vscode.commands.registerCommand('pastel.addHandler', addHandler),
    vscode.commands.registerCommand('pastel.toggleFormCode', toggleFormCode),
    vscode.commands.registerCommand('pastel.toggleDeclaration', () => toggleDeclarationCommand(pascalIndex)),
  );

  // tasks ("pastel: build" etc. in Terminal > Run Task, and in tasks.json)
  context.subscriptions.push(vscode.tasks.registerTaskProvider('pastel', {
    provideTasks: async () => {
      const root = await currentProjectRoot();
      if (!root) {
        return [];
      }
      return [
        makeTask('build', root),
        makeTask('run', root),
        makeTask('test', root),
        makeTask('build', root, { release: true }),
        makeTask('clean', root),
      ];
    },
    resolveTask: task => {
      const def = task.definition as PastelTaskDefinition;
      const folder = task.scope && typeof task.scope === 'object' ? task.scope.uri.fsPath : undefined;
      const root = folder ? findProjectRoot(folder) ?? folder : undefined;
      return root ? makeTask(def.command, root, def, task.definition) : undefined;
    },
  }));

  // .pform language features
  const selector: vscode.DocumentSelector = { language: 'pform' };
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider(selector, { provideCompletionItems }, ' ', '=', ':'),
    vscode.languages.registerHoverProvider(selector, { provideHover }),
    vscode.languages.registerDefinitionProvider(selector, { provideDefinition }),
    vscode.languages.registerDocumentSymbolProvider(selector, { provideDocumentSymbols }),
    vscode.languages.registerCodeActionsProvider(selector, { provideCodeActions },
      { providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] }),
  );

  // checks
  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument(doc => scheduleCheck(doc, 0)),
    vscode.workspace.onDidSaveTextDocument(doc => scheduleCheck(doc, 0)),
    vscode.workspace.onDidChangeTextDocument(e => {
      if (vscode.workspace.getConfiguration('pastel').get<boolean>('checkWhileTyping', true)) {
        scheduleCheck(e.document, 400);
      }
    }),
    vscode.workspace.onDidCloseTextDocument(doc => diagnostics.delete(doc.uri)),
  );
  vscode.workspace.textDocuments.forEach(doc => scheduleCheck(doc, 0));
}

export function deactivate(): void {
  checkTimers.forEach(t => clearTimeout(t));
}

async function updateProjectContext(): Promise<void> {
  const found = await vscode.workspace.findFiles('**/pastel.toml', '**/build/**', 1);
  vscode.commands.executeCommand('setContext', 'pastel.isProject', found.length > 0);
}

/** pastel.hasForm: the active .pas file has a .pform next to it (a form unit). */
function updateFormContext(editor: vscode.TextEditor | undefined): void {
  const file = editor?.document.uri.fsPath;
  const has = !!file && /\.pas$/i.test(file) && fs.existsSync(file.replace(/\.pas$/i, '.pform'));
  vscode.commands.executeCommand('setContext', 'pastel.hasForm', has);
}

/** Delphi's F12: from the form (designer or .pform) to its code, and back. */
async function toggleFormCode(): Promise<void> {
  const designed = FormPreview.activeDocument;
  const editorDoc = vscode.window.activeTextEditor?.document;
  const pform = designed ?? (editorDoc?.languageId === 'pform' ? editorDoc : undefined);
  if (pform) {
    const pas = pform.uri.fsPath.replace(/\.pform$/i, '.pas');
    if (!fs.existsSync(pas)) {
      vscode.window.showInformationMessage(`Pastel: ${path.basename(pas)} was not found.`);
      return;
    }
    await vscode.window.showTextDocument(vscode.Uri.file(pas), { viewColumn: vscode.ViewColumn.One });
    return;
  }
  if (editorDoc && /\.pas$/i.test(editorDoc.uri.fsPath)) {
    const form = editorDoc.uri.fsPath.replace(/\.pas$/i, '.pform');
    if (fs.existsSync(form)) {
      await openPreview(vscode.Uri.file(form));
      return;
    }
  }
  vscode.window.setStatusBarMessage('Pastel: this file is not part of a form', 2500);
}

// ---------- tasks ----------

interface PastelTaskDefinition extends vscode.TaskDefinition {
  command: string;
  target?: string;
  release?: boolean;
}

function makeTask(command: string, root: string,
  opts: { target?: string; release?: boolean; watch?: boolean } = {},
  definition?: vscode.TaskDefinition): vscode.Task {
  const def: PastelTaskDefinition = definition as PastelTaskDefinition ??
    { type: 'pastel', command, ...opts };
  const args = [command];
  if (opts.target) {
    args.push('--target', opts.target);
  }
  if (opts.release) {
    args.push('--release');
  }
  if (opts.watch) {
    args.push('--watch');
  }
  let name = command;
  if (opts.release) {
    name += ' (release)';
  }
  if (opts.target) {
    name += ` (${opts.target})`;
  }
  if (opts.watch) {
    name += ' (watch)';
  }
  const folder = vscode.workspace.getWorkspaceFolder(vscode.Uri.file(root));
  const task = new vscode.Task(def, folder ?? vscode.TaskScope.Workspace, name, 'pastel',
    new vscode.ProcessExecution(pastelPath(), args, { cwd: root, env: { NO_COLOR: '1' } }),
    '$pastel');
  if (command === 'build') {
    task.group = vscode.TaskGroup.Build;
  }
  if (opts.watch) {
    task.isBackground = true;
  }
  task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, clear: true, panel: vscode.TaskPanelKind.Dedicated };
  return task;
}

async function runTask(command: string, opts: { target?: string; release?: boolean; watch?: boolean } = {}): Promise<void> {
  let root = await currentProjectRoot();
  if (!root) {
    vscode.window.showWarningMessage('Pastel: no pastel.toml found in this workspace. Create a project with "Pastel: New Project".');
    return;
  }
  if (command === 'run') {
    // a library has no program: run one that uses it, or offer its tests
    const runnable = await runnableProjectRoot(extensionContext?.workspaceState);
    if (!runnable) {
      const info = readProjectInfo(root);
      if (info?.kind === 'lib') {
        const choice = await vscode.window.showInformationMessage(
          `Pastel: ${info.name} is a library and has no program to run. Run its tests instead?`, 'Run Tests');
        if (choice === 'Run Tests') {
          command = 'test';
        } else {
          return;
        }
      }
    } else {
      root = runnable;
    }
  }
  await vscode.workspace.saveAll(false);
  if (command === 'run' || opts.watch) {
    // stop a previous run (or watch) first
    for (const exec of vscode.tasks.taskExecutions) {
      const def = exec.task.definition as PastelTaskDefinition;
      if (exec.task.source === 'pastel' && def.command === command) {
        exec.terminate();
      }
    }
  }
  await vscode.tasks.executeTask(makeTask(command, root, opts));
}

async function newForm(): Promise<void> {
  const root = await currentProjectRoot();
  if (!root) {
    vscode.window.showWarningMessage('Pastel: open a Pastel app first.');
    return;
  }
  const name = await vscode.window.showInputBox({
    prompt: 'Name of the new form (it is shown with Form.ShowModal or as a dialog)',
    placeHolder: 'Settings',
    validateInput: v => (/^[A-Za-z][A-Za-z0-9_]*$/.test(v.trim()) ? undefined : 'Letters and digits, like Settings'),
  });
  if (!name) {
    return;
  }
  const r = await runPastel(['new', 'form', name.trim()], root);
  if (r.code !== 0) {
    vscode.window.showErrorMessage('Pastel: ' + (r.stderr || r.stdout).replace(/\x1b\[[0-9;]*m/g, '').trim());
    return;
  }
  const base = name.trim().replace(/form$/i, '');
  const file = path.join(root, 'src', 'forms', base.charAt(0).toUpperCase() + base.slice(1) + '.pform');
  const doc = await vscode.workspace.openTextDocument(file);
  await vscode.window.showTextDocument(doc, vscode.ViewColumn.One);
  vscode.commands.executeCommand('pastel.openPreview', doc.uri);
  vscode.commands.executeCommand('pastel.refreshTree');
}

async function buildForPlatform(): Promise<void> {
  const pick = await vscode.window.showQuickPick(PLATFORMS, {
    placeHolder: 'Build for which platform? (run "Pastel: Check Setup" to see what is installed)',
  });
  if (!pick) {
    return;
  }
  const release = await vscode.window.showQuickPick(['Release', 'Debug'], { placeHolder: 'Build type' });
  if (!release) {
    return;
  }
  await runTask('build', { target: pick.label, release: release === 'Release' });
}

async function doctor(): Promise<void> {
  const root = (await currentProjectRoot()) ?? vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? process.cwd();
  const task = new vscode.Task({ type: 'pastel', command: 'doctor' }, vscode.TaskScope.Workspace, 'doctor', 'pastel',
    new vscode.ProcessExecution(pastelPath(), ['doctor'], { cwd: root }));
  task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, clear: true };
  await vscode.tasks.executeTask(task);
}

async function newProject(): Promise<void> {
  const kind = await vscode.window.showQuickPick([
    { label: 'app', description: 'Desktop app with a window and forms' },
    { label: 'console', description: 'Terminal program' },
    { label: 'service', description: 'Keeps running: jobs, settings, systemd (a server program)' },
    { label: 'api', description: 'Web API with a database: models, controllers, migrations' },
    { label: 'lib', description: 'Units for other projects (a library)' },
  ], { placeHolder: 'What kind of project?' });
  if (!kind) {
    return;
  }
  const name = await vscode.window.showInputBox({
    prompt: 'Project name',
    placeHolder: 'my-app',
    validateInput: v => /^[A-Za-z][A-Za-z0-9_-]*$/.test(v) ? undefined :
      'Start with a letter; use letters, digits, "-" and "_".',
  });
  if (!name) {
    return;
  }
  const parent = await vscode.window.showOpenDialog({
    canSelectFolders: true, canSelectFiles: false, canSelectMany: false,
    openLabel: 'Create project here',
  });
  if (!parent || parent.length === 0) {
    return;
  }
  const result = await runPastel(['new', kind.label, name], parent[0].fsPath);
  if (result.code !== 0) {
    vscode.window.showErrorMessage(`Pastel: ${(result.stderr || result.stdout).trim()}`);
    return;
  }
  vscode.commands.executeCommand('pastel.refreshTree');
  const folder = vscode.Uri.file(path.join(parent[0].fsPath, name));
  const open = await vscode.window.showInformationMessage(
    `Project "${name}" was created. Open it now?`, { modal: true },
    'Open in This Window', 'Open in New Window');
  if (open) {
    await vscode.commands.executeCommand('vscode.openFolder', folder, open === 'Open in New Window');
  }
}

async function openPreview(uri?: vscode.Uri): Promise<void> {
  let doc = vscode.window.activeTextEditor?.document;
  if (uri) {
    doc = await vscode.workspace.openTextDocument(uri);
  } else if (doc && /\.pas$/i.test(doc.uri.fsPath) && fs.existsSync(doc.uri.fsPath.replace(/\.pas$/i, '.pform'))) {
    // from a form's code: design its .pform
    doc = await vscode.workspace.openTextDocument(vscode.Uri.file(doc.uri.fsPath.replace(/\.pas$/i, '.pform')));
  }
  if (!doc || doc.languageId !== 'pform') {
    vscode.window.showInformationMessage('Pastel: open a .pform file to preview it.');
    return;
  }
  FormPreview.show(doc, {
    loadSchema,
    addHandler: (uri, name, params) => addHandler(uri, name, params),
  });
}

// ---------- checks ----------

function scheduleCheck(doc: vscode.TextDocument, delay: number): void {
  if (doc.languageId !== 'pform' || doc.uri.scheme !== 'file') {
    return;
  }
  const key = doc.uri.toString();
  const old = checkTimers.get(key);
  if (old) {
    clearTimeout(old);
  }
  checkTimers.set(key, setTimeout(() => {
    checkTimers.delete(key);
    checkDocument(doc);
  }, delay));
}

async function checkDocument(doc: vscode.TextDocument): Promise<void> {
  const file = doc.uri.fsPath;
  const root = findProjectRoot(file) ?? path.dirname(file);
  const rel = path.relative(root, file);
  const result = await runPastel(['check', rel, '--stdin', '--json'], root, doc.getText());
  if (result.code === -1) {
    return;
  }
  let issues;
  try {
    issues = parseIssues(result.stdout);
  } catch {
    return;
  }
  diagnostics.set(doc.uri, issues.map(issue => {
    const line = Math.min(Math.max(issue.line - 1, 0), doc.lineCount - 1);
    const text = doc.lineAt(line);
    const range = new vscode.Range(line, text.firstNonWhitespaceCharacterIndex, line, text.text.length);
    const d = new vscode.Diagnostic(range, issue.message,
      issue.severity === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning);
    d.source = 'pastel';
    return d;
  }));
}

// ---------- schema ----------

async function loadSchema(): Promise<Schema | undefined> {
  if (schema) {
    return schema;
  }
  if (!schemaLoading) {
    schemaLoading = (async () => {
      const cwd = (await currentProjectRoot()) ?? process.cwd();
      const result = await runPastel(['schema'], cwd);
      if (result.code !== 0) {
        return undefined;
      }
      try {
        schema = JSON.parse(result.stdout) as Schema;
        return schema;
      } catch {
        return undefined;
      } finally {
        schemaLoading = undefined;
      }
    })();
  }
  return schemaLoading;
}

function formUnitText(doc: vscode.TextDocument): string | undefined {
  const pas = doc.uri.fsPath.replace(/\.pform$/i, '.pas');
  const open = vscode.workspace.textDocuments.find(d => d.uri.fsPath === pas);
  if (open) {
    return open.getText();
  }
  return fs.existsSync(pas) ? fs.readFileSync(pas, 'utf8') : undefined;
}

function propertyDetail(p: SchemaProperty): string {
  switch (p.type) {
    case 'enum': return (p.values ?? []).join(' | ');
    case 'event': return 'event';
    default: return p.type;
  }
}

function propertySnippet(p: SchemaProperty, doc: vscode.TextDocument, owner: string): vscode.SnippetString {
  const s = new vscode.SnippetString(`${p.name} = `);
  switch (p.type) {
    case 'string': s.appendText("'").appendTabstop(1).appendText("'"); break;
    case 'color': s.appendText("'#").appendPlaceholder('4F46E5').appendText("'"); break;
    case 'boolean': s.appendChoice(['True', 'False']); break;
    case 'enum': s.appendChoice(p.values ?? []); break;
    case 'event': s.appendPlaceholder(owner + p.name.replace(/^On/, '')); break;
    default: s.appendPlaceholder('0');
  }
  return s;
}

async function provideCompletionItems(doc: vscode.TextDocument, pos: vscode.Position): Promise<vscode.CompletionItem[]> {
  const sch = await loadSchema();
  if (!sch) {
    return [];
  }
  const before = stripComment(doc.lineAt(pos.line).text.substring(0, pos.character));
  const ctx = completionContext(before);
  const lines = doc.getText().split(/\r?\n/);
  const chain = enclosingObjects(lines, pos.line);
  const cls = classFor(sch, chain);

  if (ctx.kind === 'type') {
    return sch.controls.map(c => {
      const item = new vscode.CompletionItem(c.name, vscode.CompletionItemKind.Class);
      item.detail = c.container ? 'container' : 'control';
      return item;
    });
  }

  if (ctx.kind === 'value' && cls) {
    const prop = cls.properties.find(p => p.name.toLowerCase() === ctx.property.toLowerCase());
    if (!prop) {
      return [];
    }
    switch (prop.type) {
      case 'enum':
        return (prop.values ?? []).map(v => new vscode.CompletionItem(v, vscode.CompletionItemKind.EnumMember));
      case 'boolean':
        return ['True', 'False'].map(v => new vscode.CompletionItem(v, vscode.CompletionItemKind.Value));
      case 'event': {
        const pas = formUnitText(doc);
        const items = (pas ? declaredProcedures(pas) : []).map(n => {
          const item = new vscode.CompletionItem(n, vscode.CompletionItemKind.Method);
          item.detail = 'in ' + path.basename(doc.uri.fsPath).replace(/\.pform$/i, '.pas');
          return item;
        });
        const owner = chain.length > 1 ? chain[chain.length - 1].name : 'Form';
        const suggested = owner.replace(/(Button|Edit|Label)$/, '') + prop.name.replace(/^On/, '');
        if (!items.some(i => i.label === suggested)) {
          const item = new vscode.CompletionItem(suggested, vscode.CompletionItemKind.Method);
          item.detail = 'new handler (use the quick fix to add it to the code)';
          items.push(item);
        }
        return items;
      }
      case 'color': {
        const item = new vscode.CompletionItem("'#4F46E5'", vscode.CompletionItemKind.Color);
        item.insertText = new vscode.SnippetString("'#").appendPlaceholder('4F46E5').appendText("'");
        return [item];
      }
      default:
        return [];
    }
  }

  if (ctx.kind === 'property') {
    const items: vscode.CompletionItem[] = [];
    if (cls) {
      // properties already set on this object are not offered again
      const set = new Set<string>();
      const start = chain[chain.length - 1].line + 1;
      let depth = 0;
      for (let i = start; i < lines.length; i++) {
        const t = stripComment(lines[i]);
        if (/^\s*object\b/i.test(t)) { depth++; continue; }
        if (/^\s*end\b/i.test(t)) { if (depth === 0) { break; } depth--; continue; }
        const m = /^\s*([A-Za-z_]\w*)\s*=/.exec(t);
        if (m && depth === 0 && i !== pos.line) { set.add(m[1].toLowerCase()); }
      }
      const owner = chain.length > 1 ? chain[chain.length - 1].name : 'Form';
      for (const p of cls.properties) {
        if (set.has(p.name.toLowerCase())) {
          continue;
        }
        const item = new vscode.CompletionItem(p.name,
          p.type === 'event' ? vscode.CompletionItemKind.Event : vscode.CompletionItemKind.Property);
        item.detail = propertyDetail(p);
        item.documentation = p.doc;
        item.insertText = propertySnippet(p, doc, owner.replace(/(Button|Edit|Label)$/, ''));
        item.sortText = (p.type === 'event' ? '2' : '1') + p.name;
        items.push(item);
      }
    }
    if (chain.length === 0 || cls?.container || cls?.form) {
      const obj = new vscode.CompletionItem('object', vscode.CompletionItemKind.Keyword);
      obj.insertText = new vscode.SnippetString('object ${1:Name}: ${2|' +
        sch.controls.map(c => c.name).join(',') + '|}\n\t$0\nend');
      obj.detail = 'Add a control';
      obj.sortText = '0object';
      items.push(obj);
    }
    if (chain.length > 0) {
      const end = new vscode.CompletionItem('end', vscode.CompletionItemKind.Keyword);
      end.sortText = '3end';
      items.push(end);
    }
    return items;
  }
  return [];
}

async function provideHover(doc: vscode.TextDocument, pos: vscode.Position): Promise<vscode.Hover | undefined> {
  const sch = await loadSchema();
  const range = doc.getWordRangeAtPosition(pos, /[A-Za-z_]\w*/);
  if (!sch || !range) {
    return undefined;
  }
  const word = doc.getText(range);
  const line = doc.lineAt(pos.line).text;
  const control = sch.controls.find(c => c.name.toLowerCase() === word.toLowerCase());
  if (control && /:\s*\w*$/.test(line.substring(0, range.end.character))) {
    const md = new vscode.MarkdownString(`**${control.name}**${control.container ? ' (container)' : ''}\n\n` +
      control.properties.map(p => `- \`${p.name}\`: ${propertyDetail(p)}`).join('\n'));
    return new vscode.Hover(md, range);
  }
  const chain = enclosingObjects(doc.getText().split(/\r?\n/), pos.line);
  const cls: SchemaClass | undefined = classFor(sch, chain);
  const before = line.substring(0, range.start.character);
  if (cls && /^\s*$/.test(before)) {
    const prop = cls.properties.find(p => p.name.toLowerCase() === word.toLowerCase());
    if (prop) {
      const md = new vscode.MarkdownString(`**${prop.name}**: ${propertyDetail(prop)}\n\n${prop.doc}`);
      return new vscode.Hover(md, range);
    }
  }
  return undefined;
}

function handlerAt(doc: vscode.TextDocument, pos: vscode.Position): { name: string; range: vscode.Range } | undefined {
  const line = doc.lineAt(pos.line).text;
  const m = /^(\s*On[A-Za-z_]\w*\s*=\s*)([A-Za-z_]\w*)/.exec(line);
  if (!m) {
    return undefined;
  }
  const start = m[1].length;
  const end = start + m[2].length;
  if (pos.character < start || pos.character > end) {
    return undefined;
  }
  return { name: m[2], range: new vscode.Range(pos.line, start, pos.line, end) };
}

async function provideDefinition(doc: vscode.TextDocument, pos: vscode.Position): Promise<vscode.Location | undefined> {
  const handler = handlerAt(doc, pos);
  if (!handler) {
    return undefined;
  }
  const pasPath = doc.uri.fsPath.replace(/\.pform$/i, '.pas');
  const text = formUnitText(doc);
  if (!text) {
    return undefined;
  }
  const found = findProcedure(text, handler.name);
  if (!found) {
    return undefined;
  }
  return new vscode.Location(vscode.Uri.file(pasPath), new vscode.Position(found.line, found.character));
}

function provideDocumentSymbols(doc: vscode.TextDocument): vscode.DocumentSymbol[] {
  const lines = doc.getText().split(/\r?\n/);
  const objects = allObjects(lines);
  const roots: vscode.DocumentSymbol[] = [];
  const stack: { depth: number; symbol: vscode.DocumentSymbol }[] = [];
  for (const o of objects) {
    const range = new vscode.Range(o.line, 0, o.line, lines[o.line].length);
    const symbol = new vscode.DocumentSymbol(o.name, o.className, vscode.SymbolKind.Object, range, range);
    while (stack.length > 0 && stack[stack.length - 1].depth >= o.depth) {
      stack.pop();
    }
    if (stack.length === 0) {
      roots.push(symbol);
    } else {
      stack[stack.length - 1].symbol.children.push(symbol);
    }
    stack.push({ depth: o.depth, symbol });
  }
  return roots;
}

function provideCodeActions(doc: vscode.TextDocument, _range: vscode.Range,
  context: vscode.CodeActionContext): vscode.CodeAction[] {
  const actions: vscode.CodeAction[] = [];
  for (const d of context.diagnostics) {
    const name = missingHandlerName(d.message);
    if (!name) {
      continue;
    }
    const action = new vscode.CodeAction(`Add "${name}" to the form's code`, vscode.CodeActionKind.QuickFix);
    action.command = {
      command: 'pastel.addHandler', title: 'Add handler',
      arguments: [doc.uri, name, missingHandlerParams(d.message)],
    };
    action.diagnostics = [d];
    action.isPreferred = true;
    actions.push(action);
  }
  return actions;
}

async function addHandler(pformUri: vscode.Uri, name: string, params?: string): Promise<void> {
  const pasUri = vscode.Uri.file(pformUri.fsPath.replace(/\.pform$/i, '.pas'));
  let pasDoc: vscode.TextDocument;
  try {
    pasDoc = await vscode.workspace.openTextDocument(pasUri);
  } catch {
    vscode.window.showErrorMessage(`Pastel: ${path.basename(pasUri.fsPath)} was not found next to the .pform file.`);
    return;
  }
  const inserts = handlerInserts(pasDoc.getText(), name, params);
  if (!inserts) {
    vscode.window.showErrorMessage('Pastel: could not find the form class (T...Form = class(T...FormBase)) in ' +
      path.basename(pasUri.fsPath));
    return;
  }
  const edit = new vscode.WorkspaceEdit();
  for (const ins of inserts) {
    edit.insert(pasUri, new vscode.Position(ins.line, 0), ins.text);
  }
  await vscode.workspace.applyEdit(edit);
  await pasDoc.save();
  const editor = await vscode.window.showTextDocument(pasDoc, vscode.ViewColumn.Active);
  const pos = findProcedure(pasDoc.getText(), name);
  if (pos) {
    const body = new vscode.Position(pos.line + 2, 2);
    editor.selection = new vscode.Selection(body, body);
    editor.revealRange(new vscode.Range(body, body), vscode.TextEditorRevealType.InCenter);
  }
  const pformDoc = vscode.workspace.textDocuments.find(d => d.uri.toString() === pformUri.toString());
  if (pformDoc) {
    scheduleCheck(pformDoc, 0);
  }
}
