// The Pastel panel in the activity bar: actions, forms and source files.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { currentProjectRoot } from './cli';
import { parseJobs, parseRoutes } from './routes';

type NodeKind = 'group' | 'action' | 'form' | 'file' | 'route';

export class ProjectNode extends vscode.TreeItem {
  children: ProjectNode[] = [];
  constructor(label: string, public readonly nodeKind: NodeKind, collapsed?: vscode.TreeItemCollapsibleState) {
    super(label, collapsed ?? vscode.TreeItemCollapsibleState.None);
  }
}

function action(label: string, command: string, icon: string, key?: string, args: unknown[] = []): ProjectNode {
  const n = new ProjectNode(label, 'action');
  n.iconPath = new vscode.ThemeIcon(icon);
  n.description = key;
  n.command = { command, title: label, arguments: args };
  return n;
}

function fileNode(file: string, root: string, label?: string, icon?: string): ProjectNode {
  const n = new ProjectNode(label ?? path.basename(file), 'file');
  n.resourceUri = vscode.Uri.file(file);
  n.tooltip = path.relative(root, file);
  if (icon) {
    n.iconPath = new vscode.ThemeIcon(icon);
  }
  n.command = { command: 'vscode.open', title: 'Open', arguments: [vscode.Uri.file(file)] };
  return n;
}

function at(file: string, line: number): vscode.Command {
  return {
    command: 'vscode.open', title: 'Open',
    arguments: [vscode.Uri.file(file), { selection: new vscode.Range(line, 0, line, 0) }],
  };
}

const METHOD_ICONS: Record<string, string> = {
  GET: 'arrow-down', POST: 'add', PUT: 'edit', PATCH: 'edit', DELETE: 'trash', STATIC: 'file-media',
};

// Routes, jobs and migrations of a service project
function serviceGroups(root: string, files: string[]): ProjectNode[] {
  const groups: ProjectNode[] = [];
  const routes = new ProjectNode('Routes', 'group', vscode.TreeItemCollapsibleState.Expanded);
  routes.iconPath = new vscode.ThemeIcon('globe');
  routes.contextValue = 'pastelRoutes';
  const jobs = new ProjectNode('Jobs', 'group', vscode.TreeItemCollapsibleState.Expanded);
  jobs.iconPath = new vscode.ThemeIcon('watch');
  for (const f of files.filter(x => /\.(pas|pp)$/i.test(x))) {
    const text = fs.readFileSync(f, 'utf8');
    for (const r of parseRoutes(text)) {
      const n = new ProjectNode(`${r.method === 'STATIC' ? 'files' : r.method} ${r.path}`, 'route');
      n.description = r.handler;
      n.tooltip = `${path.relative(root, f)}:${r.line + 1}`;
      n.iconPath = new vscode.ThemeIcon(METHOD_ICONS[r.method] ?? 'symbol-method');
      n.command = at(f, r.line);
      if (r.method !== 'STATIC') {
        n.contextValue = 'pastelRoute';
        (n as ProjectNode & { route?: unknown }).route = { method: r.method, path: r.path };
      }
      routes.children.push(n);
    }
    for (const j of parseJobs(text)) {
      const n = new ProjectNode(j.handler, 'route');
      n.description = j.schedule;
      n.tooltip = `${path.relative(root, f)}:${j.line + 1}`;
      n.iconPath = new vscode.ThemeIcon('clock');
      n.command = at(f, j.line);
      jobs.children.push(n);
    }
  }
  if (routes.children.length > 0) {
    groups.push(routes);
  }
  if (jobs.children.length > 0) {
    groups.push(jobs);
  }
  const dir = path.join(root, 'database', 'migrations');
  if (fs.existsSync(dir)) {
    const migrations = new ProjectNode('Migrations', 'group', vscode.TreeItemCollapsibleState.Collapsed);
    migrations.iconPath = new vscode.ThemeIcon('database');
    migrations.contextValue = 'pastelMigrations';
    migrations.children = [
      action('Run Migrations', 'pastel.migrate', 'run-all'),
      action('Migration Status', 'pastel.migrateStatus', 'list-ordered'),
      action('New Migration…', 'pastel.newMigration', 'new-file'),
      ...fs.readdirSync(dir).filter(f => /\.sql$/i.test(f)).sort()
        .map(f => fileNode(path.join(dir, f), root, f.replace(/\.sql$/i, ''), 'symbol-file')),
    ];
    groups.push(migrations);
  }
  return groups;
}

function walk(dir: string, out: string[]): void {
  if (!fs.existsSync(dir)) {
    return;
  }
  for (const name of fs.readdirSync(dir).sort()) {
    if (name.startsWith('.')) {
      continue;
    }
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) {
      walk(full, out);
    } else {
      out.push(full);
    }
  }
}

export class ProjectTree implements vscode.TreeDataProvider<ProjectNode> {
  private readonly changed = new vscode.EventEmitter<ProjectNode | undefined>();
  readonly onDidChangeTreeData = this.changed.event;

  refresh(): void {
    this.changed.fire(undefined);
  }

  getTreeItem(node: ProjectNode): vscode.TreeItem {
    return node;
  }

  async getChildren(node?: ProjectNode): Promise<ProjectNode[]> {
    if (node) {
      return node.children;
    }
    const root = await currentProjectRoot();
    if (!root) {
      return [];   // the welcome view (New Project) is shown instead
    }
    const name = path.basename(root);

    const actions = new ProjectNode(name, 'group', vscode.TreeItemCollapsibleState.Expanded);
    actions.iconPath = new vscode.ThemeIcon('package');
    actions.tooltip = root;
    actions.children = [
      action('Run', 'pastel.run', 'play', 'F9'),
      action('Build', 'pastel.build', 'tools', 'Ctrl+F9'),
      action('Run Tests', 'pastel.test', 'beaker'),
      action('Build Release', 'pastel.buildRelease', 'rocket'),
      action('Build for Platform…', 'pastel.buildTarget', 'device-desktop'),
      action('Clean', 'pastel.clean', 'trash'),
      action('Check Setup', 'pastel.doctor', 'pulse'),
    ];

    const files: string[] = [];
    walk(path.join(root, 'src'), files);
    const pforms = files.filter(f => /\.pform$/i.test(f));
    const formPas = new Set(pforms.map(f => f.replace(/\.pform$/i, '.pas').toLowerCase()));

    const forms = new ProjectNode('Forms', 'group', vscode.TreeItemCollapsibleState.Expanded);
    forms.iconPath = new vscode.ThemeIcon('window');
    for (const f of pforms) {
      const base = path.basename(f, path.extname(f));
      const form = new ProjectNode(base, 'form', vscode.TreeItemCollapsibleState.Collapsed);
      form.iconPath = new vscode.ThemeIcon('layout');
      form.description = 'designer';
      form.tooltip = `Open ${base} in the form designer`;
      form.resourceUri = vscode.Uri.file(f);
      form.contextValue = 'pastelForm';
      form.command = { command: 'pastel.openPreview', title: 'Open Form Designer', arguments: [vscode.Uri.file(f)] };
      const pas = f.replace(/\.pform$/i, '.pas');
      form.children = [
        fileNode(f, root, `${base}.pform`, 'symbol-structure'),
        ...(fs.existsSync(pas) ? [fileNode(pas, root, `${base}.pas`, 'code')] : []),
      ];
      forms.children.push(form);
    }
    if (pforms.length > 0) {
      forms.children.push(action('New Form…', 'pastel.newForm', 'add'));
    }
    const service = serviceGroups(root, files);
    if (pforms.length === 0 && service.length === 0) {
      const none = new ProjectNode('No forms yet', 'group');
      none.description = 'console project';
      forms.children.push(none);
    }

    const sources = new ProjectNode('Source', 'group', vscode.TreeItemCollapsibleState.Expanded);
    sources.iconPath = new vscode.ThemeIcon('folder-library');
    for (const f of files) {
      if (/\.(pas|pp|inc)$/i.test(f) && !formPas.has(f.toLowerCase())) {
        sources.children.push(fileNode(f, root, path.relative(path.join(root, 'src'), f)));
      }
    }

    const settings = fileNode(path.join(root, 'pastel.toml'), root, 'Project settings', 'settings-gear');
    settings.description = 'pastel.toml';

    return [actions, ...(pforms.length > 0 || service.length === 0 ? [forms] : []), ...service, sources, settings];
  }
}

export function registerSidebar(context: vscode.ExtensionContext): ProjectTree {
  const tree = new ProjectTree();
  context.subscriptions.push(vscode.window.registerTreeDataProvider('pastel.project', tree));
  const watcher = vscode.workspace.createFileSystemWatcher('**/{src/**,database/migrations/*,pastel.toml}');
  watcher.onDidCreate(() => tree.refresh());
  watcher.onDidDelete(() => tree.refresh());
  watcher.onDidChange(uri => {
    if (/\.(pas|pp)$/i.test(uri.fsPath)) {
      tree.refresh();     // routes may have changed
    }
  });
  context.subscriptions.push(watcher, vscode.commands.registerCommand('pastel.refreshTree', () => tree.refresh()));
  return tree;
}
