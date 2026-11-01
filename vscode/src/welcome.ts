// The Welcome page in VS Code: recent projects, the New Project wizard (its page is in welcomeHtml.ts).
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { runPastel } from './cli';
import { RecentProject, validProjectName, welcomeHtml, withPlatforms } from './welcomeHtml';

const RECENT_KEY = 'pastel.recentProjects';
const LOCATION_KEY = 'pastel.projectLocation';
const JUST_CREATED_KEY = 'pastel.justCreated';

/** Opens the main form's designer (or main.pas) of a project the wizard just made. */
export async function openJustCreated(context: vscode.ExtensionContext, root: string): Promise<void> {
  if (context.globalState.get<string>(JUST_CREATED_KEY) !== root) {
    return;
  }
  await context.globalState.update(JUST_CREATED_KEY, undefined);
  const home = path.join(root, 'src', 'forms', 'Home.pform');
  if (fs.existsSync(home)) {
    await vscode.window.showTextDocument(vscode.Uri.file(home.replace(/\.pform$/, '.pas')), { preview: false });
    await vscode.commands.executeCommand('pastel.openPreview', vscode.Uri.file(home));
  } else if (fs.existsSync(path.join(root, 'src', 'main.pas'))) {
    await vscode.window.showTextDocument(vscode.Uri.file(path.join(root, 'src', 'main.pas')), { preview: false });
  }
}

/** Keeps the list of projects for the Welcome page (newest first, at most 12). */
export function rememberProject(context: vscode.ExtensionContext, root: string): void {
  const toml = path.join(root, 'pastel.toml');
  if (!fs.existsSync(toml)) {
    return;
  }
  const text = fs.readFileSync(toml, 'utf8');
  const name = /^name\s*=\s*"([^"]*)"/m.exec(text)?.[1] ?? path.basename(root);
  const kind = /^type\s*=\s*"([^"]*)"/m.exec(text)?.[1] ?? 'console';
  const list = (context.globalState.get<RecentProject[]>(RECENT_KEY) ?? []).filter(r => r.path !== root);
  list.unshift({ name, path: root, kind });
  context.globalState.update(RECENT_KEY, list.slice(0, 12));
}

export class WelcomePanel {
  private static current: WelcomePanel | undefined;
  private readonly panel: vscode.WebviewPanel;

  static show(context: vscode.ExtensionContext, version: string, wizard = false): void {
    if (WelcomePanel.current) {
      WelcomePanel.current.panel.reveal();
      if (wizard) {
        WelcomePanel.current.panel.webview.postMessage({ type: 'wizard' });
      }
      return;
    }
    WelcomePanel.current = new WelcomePanel(context, version, wizard);
  }

  private constructor(private readonly context: vscode.ExtensionContext, version: string, wizard: boolean) {
    this.panel = vscode.window.createWebviewPanel('pastelWelcome', 'Welcome to Pastel', vscode.ViewColumn.One,
      { enableScripts: true, retainContextWhenHidden: true });
    const recent = (context.globalState.get<RecentProject[]>(RECENT_KEY) ?? []).filter(r => fs.existsSync(path.join(r.path, 'pastel.toml')));
    const location = context.globalState.get<string>(LOCATION_KEY) ?? path.join(os.homedir(), 'PastelProjects');
    this.panel.webview.html = welcomeHtml(Math.random().toString(36).slice(2), { recent, location, version });
    this.panel.webview.onDidReceiveMessage(m => this.onMessage(m));
    this.panel.onDidDispose(() => { WelcomePanel.current = undefined; });
    if (wizard) {
      this.panel.webview.postMessage({ type: 'wizard' });
    }
  }

  private async onMessage(m: any): Promise<void> {
    switch (m.type) {
      case 'open': {
        const r = await vscode.window.showOpenDialog({ canSelectFolders: true, canSelectFiles: false, openLabel: 'Open Project' });
        if (r && r.length) {
          await vscode.commands.executeCommand('vscode.openFolder', r[0], false);
        }
        break;
      }
      case 'openRecent':
        await vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(m.path), false);
        break;
      case 'browse': {
        const start = fs.existsSync(m.location) ? vscode.Uri.file(m.location) : undefined;
        const r = await vscode.window.showOpenDialog({ canSelectFolders: true, canSelectFiles: false, defaultUri: start, openLabel: 'Choose' });
        if (r && r.length) {
          this.panel.webview.postMessage({ type: 'location', location: r[0].fsPath });
        }
        break;
      }
      case 'doc': {
        const r = await runPastel(['schema'], os.homedir());
        let dir = '';
        try { dir = path.resolve(JSON.parse(r.stdout).frameworkDir, '..', '..', 'docs'); } catch { dir = ''; }
        const file = path.join(dir, m.file);
        if (dir && fs.existsSync(file)) {
          await vscode.commands.executeCommand('markdown.showPreview', vscode.Uri.file(file));
        } else {
          vscode.env.openExternal(vscode.Uri.parse(`https://github.com/azrov/pastel/blob/main/docs/${m.file}`));
        }
        break;
      }
      case 'create':
        await this.create(m.kind, m.name, m.location, Array.isArray(m.platforms) ? m.platforms : []);
        break;
    }
  }

  private async create(kind: string, name: string, location: string, platforms: string[]): Promise<void> {
    const bad = validProjectName(name);
    if (bad) {
      this.panel.webview.postMessage({ type: 'failed', message: bad });
      return;
    }
    const target = path.join(location, name);
    if (fs.existsSync(target)) {
      this.panel.webview.postMessage({ type: 'failed', message: `${target} exists already.` });
      return;
    }
    try {
      fs.mkdirSync(location, { recursive: true });
    } catch (e) {
      this.panel.webview.postMessage({ type: 'failed', message: `The folder cannot be made: ${(e as Error).message}` });
      return;
    }
    const r = await runPastel(['new', kind, name], location);
    if (r.code !== 0) {
      this.panel.webview.postMessage({ type: 'failed', message: (r.stderr || r.stdout).replace(/\x1b\[[0-9;]*m/g, '').trim() });
      return;
    }
    const toml = path.join(target, 'pastel.toml');
    if (platforms.length && fs.existsSync(toml)) {
      fs.writeFileSync(toml, withPlatforms(fs.readFileSync(toml, 'utf8'), platforms));
    }
    this.context.globalState.update(LOCATION_KEY, location);
    rememberProject(this.context, target);
    // the new project opens with its main form (or main program)
    this.context.globalState.update(JUST_CREATED_KEY, target);
    const hasFolder = (vscode.workspace.workspaceFolders ?? []).length > 0;
    await vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(target), hasFolder);
  }
}
