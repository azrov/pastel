// "Send Request" for the routes of a web API, CodeLens above routes, and
// the migration commands.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { currentProjectRoot, findProjectRoot, runPastel } from './cli';
import { devSettings, fillPath, formatResult, parseRoutes, pathParams, Route, sendHttp } from './routes';

const VERBS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
let output: vscode.OutputChannel | undefined;
let state: vscode.Memento | undefined;

function channel(): vscode.OutputChannel {
  output ??= vscode.window.createOutputChannel('Pastel Requests');
  return output;
}

export function projectSources(root: string): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    if (!fs.existsSync(dir)) {
      return;
    }
    for (const name of fs.readdirSync(dir).sort()) {
      const full = path.join(dir, name);
      if (name.startsWith('.')) {
        continue;
      }
      if (fs.statSync(full).isDirectory()) {
        walk(full);
      } else if (/\.(pas|pp)$/i.test(name)) {
        out.push(full);
      }
    }
  };
  walk(path.join(root, 'src'));
  return out;
}

export interface FoundRoute extends Route {
  file: string;
}

export function projectRoutes(root: string): FoundRoute[] {
  const out: FoundRoute[] = [];
  for (const file of projectSources(root)) {
    for (const r of parseRoutes(fs.readFileSync(file, 'utf8'))) {
      out.push({ ...r, file });
    }
  }
  return out;
}

function baseUrl(root: string): { url: string; apiKey?: string } {
  const configured = vscode.workspace.getConfiguration('pastel').get<string>('serverUrl', '');
  const file = path.join(root, 'config.toml');
  const dev = fs.existsSync(file) ? devSettings(fs.readFileSync(file, 'utf8')) : {};
  return { url: (configured || `http://localhost:${dev.port ?? 8080}`).replace(/\/+$/, ''), apiKey: dev.apiKey };
}

export async function sendRequest(arg?: { method: string; path: string } | { route?: Route }): Promise<void> {
  const root = await currentProjectRoot();
  if (!root) {
    vscode.window.showWarningMessage('Pastel: open a Pastel project first.');
    return;
  }
  let route: { method: string; path: string } | undefined =
    arg && 'method' in arg ? arg : arg && 'route' in arg ? arg.route : undefined;
  if (!route) {
    const routes = projectRoutes(root).filter(r => VERBS.includes(r.method));
    if (routes.length === 0) {
      vscode.window.showInformationMessage('Pastel: no routes found (Web.Get(\'/path\', @Handler) in src/).');
      return;
    }
    const pick = await vscode.window.showQuickPick(
      routes.map(r => ({ label: `${r.method} ${r.path}`, description: r.handler, route: r })),
      { placeHolder: 'Which route?' });
    if (!pick) {
      return;
    }
    route = pick.route;
  }

  const values: Record<string, string> = {};
  for (const p of pathParams(route.path)) {
    const key = `param:${p}`;
    const v = await vscode.window.showInputBox({
      prompt: `${route.method} ${route.path}: value for ${p === '*' ? 'the rest of the path' : ':' + p}`,
      value: state?.get<string>(key) ?? (p === 'id' ? '1' : ''),
    });
    if (v === undefined) {
      return;
    }
    values[p] = v;
    await state?.update(key, v);
  }
  const base = baseUrl(root);
  const url = await vscode.window.showInputBox({
    prompt: 'URL (add ?name=value for query parameters; the server must be running: F9)',
    value: base.url + fillPath(route.path, values),
  });
  if (!url) {
    return;
  }
  let body: string | undefined;
  if (['POST', 'PUT', 'PATCH'].includes(route.method)) {
    const key = `body:${route.method} ${route.path}`;
    body = await vscode.window.showInputBox({
      prompt: `JSON body for ${route.method} ${route.path}`,
      value: state?.get<string>(key) ?? '{}',
    });
    if (body === undefined) {
      return;
    }
    await state?.update(key, body);
  }
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  if (base.apiKey) {
    headers['X-API-Key'] = base.apiKey;
  }
  const out = channel();
  out.show(true);
  try {
    const r = await sendHttp(route.method, url, headers, body);
    out.appendLine(formatResult(route.method, url, r));
    vscode.window.setStatusBarMessage(`Pastel: ${route.method} ${route.path} → ${r.status} (${r.ms} ms)`, 5000);
  } catch (e) {
    const msg = (e as Error).message;
    out.appendLine(`${route.method} ${url}\nfailed: ${msg}\n`);
    vscode.window.showErrorMessage(`Pastel: ${route.method} ${url} failed: ${msg}` +
      (/ECONNREFUSED/.test(msg) ? ' (is the server running? F9 starts it)' : ''));
  }
}

class RouteLenses implements vscode.CodeLensProvider {
  provideCodeLenses(doc: vscode.TextDocument): vscode.CodeLens[] {
    if (!findProjectRoot(doc.uri.fsPath)) {
      return [];
    }
    return parseRoutes(doc.getText())
      .filter(r => VERBS.includes(r.method))
      .map(r => new vscode.CodeLens(new vscode.Range(r.line, 0, r.line, 0), {
        title: `▶ Send ${r.method} ${r.path}`,
        command: 'pastel.sendRequest',
        arguments: [{ method: r.method, path: r.path }],
      }));
  }
}

async function migrate(args: string[]): Promise<void> {
  const root = await currentProjectRoot();
  if (!root) {
    return;
  }
  await vscode.workspace.saveAll(false);
  const r = await runPastel(['migrate', ...args], root);
  const out = channel();
  out.appendLine(`pastel migrate ${args.join(' ')}`.trim());
  out.appendLine((r.stdout + r.stderr).replace(/\x1b\[[0-9;]*m/g, ''));
  out.show(true);
  if (r.code !== 0) {
    vscode.window.showErrorMessage('Pastel: migrate failed; see "Pastel Requests" output.');
  }
  vscode.commands.executeCommand('pastel.refreshTree');
}

async function newMigration(): Promise<void> {
  const root = await currentProjectRoot();
  if (!root) {
    return;
  }
  const name = await vscode.window.showInputBox({ prompt: 'Name of the change, e.g. add_priority_to_tasks' });
  if (!name) {
    return;
  }
  const dir = path.join(root, 'database', 'migrations');
  const before = new Set(fs.existsSync(dir) ? fs.readdirSync(dir) : []);
  const r = await runPastel(['migrate', 'new', name], root);
  if (r.code !== 0) {
    vscode.window.showErrorMessage('Pastel: ' + (r.stderr || r.stdout).replace(/\x1b\[[0-9;]*m/g, '').trim());
    return;
  }
  const created = fs.readdirSync(dir).find(f => !before.has(f));
  if (created) {
    const doc = await vscode.workspace.openTextDocument(path.join(dir, created));
    await vscode.window.showTextDocument(doc);
  }
  vscode.commands.executeCommand('pastel.refreshTree');
}

export function registerRequests(context: vscode.ExtensionContext): void {
  state = context.workspaceState;
  context.subscriptions.push(
    vscode.commands.registerCommand('pastel.sendRequest', sendRequest),
    vscode.commands.registerCommand('pastel.migrate', () => migrate([])),
    vscode.commands.registerCommand('pastel.migrateStatus', () => migrate(['status'])),
    vscode.commands.registerCommand('pastel.newMigration', newMigration),
    vscode.languages.registerCodeLensProvider({ language: 'pascal' }, new RouteLenses()),
  );
}
