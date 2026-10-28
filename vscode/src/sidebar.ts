// The Pastel panel in the activity bar: actions, forms and source files.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { currentProjectRoot } from './cli';

type NodeKind = 'group' | 'action' | 'form' | 'file';

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
    if (pforms.length === 0) {
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

    return [actions, forms, sources, settings];
  }
}

export function registerSidebar(context: vscode.ExtensionContext): ProjectTree {
  const tree = new ProjectTree();
  context.subscriptions.push(vscode.window.registerTreeDataProvider('pastel.project', tree));
  const watcher = vscode.workspace.createFileSystemWatcher('**/{src/**,pastel.toml}');
  watcher.onDidCreate(() => tree.refresh());
  watcher.onDidDelete(() => tree.refresh());
  context.subscriptions.push(watcher, vscode.commands.registerCommand('pastel.refreshTree', () => tree.refresh()));
  return tree;
}
