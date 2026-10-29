// The Testing view: every test in tests/ of each Pastel project, run or
// debugged one by one, by file or all together, with failures shown at the
// line of the failing assert.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { runPastel } from './cli';
import { buildForDebugging, hasNativeDebugger, nativeDebugConfig } from './debug';
import { findTests, parseLocation, parseResults } from './testParse';

const testIds = new WeakMap<vscode.TestItem, { root: string; id: string }>();

function listPascalFiles(dir: string): string[] {
  const out: string[] = [];
  if (!fs.existsSync(dir)) {
    return out;
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'build' && !entry.name.startsWith('.')) out.push(...listPascalFiles(full));
    } else if (/\.(pas|pp)$/i.test(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

export class PastelTests {
  readonly controller: vscode.TestController;
  private roots: string[] = [];

  constructor(context: vscode.ExtensionContext) {
    this.controller = vscode.tests.createTestController('pastel', 'Pastel');
    this.controller.resolveHandler = async item => {
      if (!item) {
        await this.discover();
      }
    };
    this.controller.refreshHandler = () => this.discover();
    this.controller.createRunProfile('Run', vscode.TestRunProfileKind.Run,
      (request, token) => this.run(request, token), true);
    this.controller.createRunProfile('Debug', vscode.TestRunProfileKind.Debug,
      (request, token) => this.debug(request, token), true);

    const watcher = vscode.workspace.createFileSystemWatcher('**/tests/**/*.{pas,pp}');
    watcher.onDidChange(uri => this.updateFile(uri.fsPath));
    watcher.onDidCreate(uri => this.updateFile(uri.fsPath));
    watcher.onDidDelete(uri => this.removeFile(uri.fsPath));
    context.subscriptions.push(this.controller, watcher,
      vscode.workspace.onDidChangeTextDocument(e => {
        if (this.isTestFile(e.document.uri.fsPath)) {
          this.updateFile(e.document.uri.fsPath, e.document.getText());
        }
      }));
  }

  private rootOf(file: string): string | undefined {
    return this.roots.find(r => file.startsWith(path.join(r, 'tests') + path.sep));
  }

  private isTestFile(file: string): boolean {
    return /\.(pas|pp)$/i.test(file) && this.rootOf(file) !== undefined;
  }

  async discover(): Promise<void> {
    const found = await vscode.workspace.findFiles('**/pastel.toml', '**/{build,node_modules}/**');
    this.roots = found.map(u => path.dirname(u.fsPath)).sort();
    this.controller.items.replace([]);
    for (const root of this.roots) {
      for (const file of listPascalFiles(path.join(root, 'tests'))) {
        this.updateFile(file);
      }
    }
  }

  /** The item that holds a project's files: the controller itself when there is one project. */
  private parentFor(root: string): vscode.TestItemCollection {
    if (this.roots.length <= 1) {
      return this.controller.items;
    }
    let project = this.controller.items.get(root);
    if (!project) {
      project = this.controller.createTestItem(root, path.basename(root), vscode.Uri.file(root));
      this.controller.items.add(project);
    }
    return project.children;
  }

  updateFile(file: string, text?: string): void {
    const root = this.rootOf(file);
    if (!root) {
      return;
    }
    if (text === undefined) {
      try {
        text = fs.readFileSync(file, 'utf8');
      } catch {
        return;
      }
    }
    const found = findTests(text);
    const parent = this.parentFor(root);
    if (found.suites.length === 0 && found.loose.length === 0) {
      parent.delete(file);
      return;
    }
    const uri = vscode.Uri.file(file);
    const fileItem = this.controller.createTestItem(file, path.relative(root, file), uri);
    const make = (key: string, label: string, line: number, id?: string): vscode.TestItem => {
      const item = this.controller.createTestItem(key, label, uri);
      item.range = new vscode.Range(line, 0, line, 0);
      if (id) {
        testIds.set(item, { root, id });
      }
      return item;
    };
    for (const suite of found.suites) {
      const s = make(`${root}::${suite.className}`, suite.label, suite.line);
      for (const t of suite.tests) {
        s.children.add(make(`${root}::${t.id}`, t.label, t.line, t.id));
      }
      fileItem.children.add(s);
    }
    for (const t of found.loose) {
      fileItem.children.add(make(`${root}::${t.id}`, t.label, t.line, t.id));
    }
    parent.add(fileItem);
  }

  removeFile(file: string): void {
    const root = this.rootOf(file);
    if (root) {
      this.parentFor(root).delete(file);
    }
  }

  /** The single tests in the request, grouped by project. */
  private collect(request: vscode.TestRunRequest): Map<string, vscode.TestItem[]> {
    const byRoot = new Map<string, vscode.TestItem[]>();
    const excluded = new Set(request.exclude ?? []);
    const visit = (item: vscode.TestItem) => {
      if (excluded.has(item)) return;
      const t = testIds.get(item);
      if (t) {
        byRoot.set(t.root, [...(byRoot.get(t.root) ?? []), item]);
      }
      item.children.forEach(visit);
    };
    if (request.include) {
      request.include.forEach(visit);
    } else {
      this.controller.items.forEach(visit);
    }
    return byRoot;
  }

  private allTestsOf(root: string): number {
    let n = 0;
    const visit = (item: vscode.TestItem) => {
      if (testIds.get(item)?.root === root) n++;
      item.children.forEach(visit);
    };
    this.controller.items.forEach(visit);
    return n;
  }

  async run(request: vscode.TestRunRequest, token: vscode.CancellationToken): Promise<void> {
    const run = this.controller.createTestRun(request);
    await vscode.workspace.saveAll(false);
    for (const [root, items] of this.collect(request)) {
      if (token.isCancellationRequested) break;
      items.forEach(i => run.started(i));
      const ids = items.map(i => testIds.get(i)!.id);
      const args = ['test', '--json'];
      if (ids.length < this.allTestsOf(root)) {
        args.push(...ids.map(id => '=' + id));
      }
      const result = await runPastel(args, root);
      const results = parseResults(result.stdout);
      const text = (result.stdout + result.stderr).replace(/\r?\n/g, '\r\n');
      if (!results) {
        run.appendOutput(text);
        const msg = new vscode.TestMessage('The tests could not be built or run:\n' +
          (result.stdout + result.stderr).trim());
        items.forEach(i => run.errored(i, msg));
        continue;
      }
      const byId = new Map(items.map(i => [testIds.get(i)!.id, i]));
      for (const r of results) {
        const item = byId.get(r.id);
        if (!item) continue;
        byId.delete(r.id);
        if (r.outcome === 'passed') {
          run.passed(item, r.ms);
        } else if (r.outcome === 'skipped') {
          run.skipped(item);
          if (r.message) run.appendOutput(`${r.id}: skipped - ${r.message}\r\n`, undefined, item);
        } else {
          const msg = new vscode.TestMessage(r.message);
          const loc = parseLocation(r.location);
          if (loc) {
            msg.location = new vscode.Location(vscode.Uri.file(path.join(root, loc.file)),
              new vscode.Position(loc.line, 0));
          }
          if (r.outcome === 'failed') run.failed(item, msg, r.ms);
          else run.errored(item, msg, r.ms);
        }
      }
      byId.forEach(item => run.skipped(item));   // not found by the runner (renamed?)
    }
    run.end();
  }

  async debug(request: vscode.TestRunRequest, token: vscode.CancellationToken): Promise<void> {
    const run = this.controller.createTestRun(request);
    try {
      if (!(await hasNativeDebugger())) return;
      await vscode.workspace.saveAll(false);
      for (const [root, items] of this.collect(request)) {
        if (token.isCancellationRequested) break;
        const built = await buildForDebugging(root, ['test', '--no-run']);
        if (!built.ok) break;
        const exe = built.stdout.split(/\r?\n/).map(l => l.trim()).filter(l => l !== '').pop() ?? '';
        items.forEach(i => run.started(i));
        const ids = items.map(i => '=' + testIds.get(i)!.id);
        const folder = vscode.workspace.getWorkspaceFolder(vscode.Uri.file(root));
        const config = nativeDebugConfig('Debug Pastel tests', exe, ids, root);
        const ended = new Promise<void>(resolve => {
          const sub = vscode.debug.onDidTerminateDebugSession(s => {
            if (s.name === config.name) {
              sub.dispose();
              resolve();
            }
          });
        });
        if (await vscode.debug.startDebugging(folder, config)) {
          await ended;
        }
        // the results are in the debug console
      }
    } finally {
      run.end();
    }
  }
}

export function registerTesting(context: vscode.ExtensionContext): PastelTests {
  const tests = new PastelTests(context);
  tests.discover();
  return tests;
}
