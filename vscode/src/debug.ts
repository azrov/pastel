// F5 without a launch.json: the "pastel" debug type builds the project and
// starts the program in gdb (lldb on macOS) through the C/C++ extension.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { currentProjectRoot, findProjectRoot, runnableProjectRoot, runPastel } from './cli';

export interface ProjectInfo {
  name: string;
  kind: string;
}

/** name and type from [project] in pastel.toml */
export function readProjectInfo(root: string): ProjectInfo {
  const text = fs.readFileSync(path.join(root, 'pastel.toml'), 'utf8');
  let section = '';
  const info: ProjectInfo = { name: path.basename(root), kind: 'console' };
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, '').trim();
    const sec = /^\[([^\]]+)\]$/.exec(line);
    if (sec) {
      section = sec[1].trim();
      continue;
    }
    const kv = /^(\w+)\s*=\s*["']([^"']*)["']/.exec(line);
    if (kv && section === 'project') {
      if (kv[1] === 'name') info.name = kv[2];
      if (kv[1] === 'type') info.kind = kv[2];
    }
  }
  return info;
}

/** The platform name "pastel build" uses for this computer. */
export function hostTarget(): string {
  if (process.platform === 'win32') return process.arch === 'ia32' ? 'windows32' : 'windows';
  if (process.platform === 'darwin') return process.arch === 'arm64' ? 'macos-arm64' : 'macos';
  if (process.arch === 'arm64') return 'linux-arm64';
  if (process.arch === 'arm') return 'linux-arm';
  return 'linux';
}

let gdbScript = '';

export function nativeDebugConfig(name: string, program: string, args: string[], cwd: string): vscode.DebugConfiguration {
  const setup = [{ description: 'Readable values', text: '-enable-pretty-printing', ignoreFailures: true }];
  if (gdbScript && process.platform !== 'darwin') {
    // Pascal strings as text, also in fields of classes and records
    setup.push({ description: 'Pascal strings', text: `source ${gdbScript}`, ignoreFailures: true });
  }
  return {
    type: 'cppdbg',
    request: 'launch',
    name,
    program,
    args,
    cwd,
    MIMode: process.platform === 'darwin' ? 'lldb' : 'gdb',
    externalConsole: false,
    stopAtEntry: false,
    setupCommands: setup,
  };
}

/** The C/C++ extension does the actual debugging; offer it when missing. */
export async function hasNativeDebugger(): Promise<boolean> {
  if (vscode.extensions.getExtension('ms-vscode.cpptools')) {
    return true;
  }
  const choice = await vscode.window.showInformationMessage(
    'Pastel debugs Pascal programs with gdb through the C/C++ extension (ms-vscode.cpptools). Install it now?',
    'Install');
  if (choice) {
    await vscode.commands.executeCommand('workbench.extensions.installExtension', 'ms-vscode.cpptools');
    vscode.window.showInformationMessage('C/C++ installed. Press F5 again to debug.');
  }
  return false;
}

/** Builds; on errors shows them (Problems panel) and returns false. */
export async function buildForDebugging(root: string, args: string[] = ['build']): Promise<{ ok: boolean; stdout: string }> {
  const result = await runPastel(args, root);
  if (result.code !== 0) {
    vscode.commands.executeCommand('pastel.build');
    vscode.window.showErrorMessage('Pastel: the build failed, so there is nothing to debug yet. See the Problems panel.');
    return { ok: false, stdout: result.stdout };
  }
  return { ok: true, stdout: result.stdout };
}

export function registerDebugging(context: vscode.ExtensionContext): void {
  gdbScript = path.join(context.extensionPath, 'gdb', 'pastel.py');
  const provider: vscode.DebugConfigurationProvider = {
    provideDebugConfigurations() {
      return [{ type: 'pastel', request: 'launch', name: 'Debug Pastel program' }];
    },
    async resolveDebugConfiguration(folder, config) {
      let root: string | undefined;
      if (config.project) {
        root = path.resolve(folder?.uri.fsPath ?? '', String(config.project));
      } else {
        root = (await currentProjectRoot()) ?? (folder ? findProjectRoot(folder.uri.fsPath) : undefined);
        // in a library: the program that uses it, like F9
        if (root && readProjectInfo(root).kind === 'lib') {
          root = (await runnableProjectRoot(context.workspaceState)) ?? root;
        }
      }
      if (!root) {
        vscode.window.showWarningMessage('Pastel: no pastel.toml found to debug. Create a project with "Pastel: New Project".');
        return undefined;
      }
      const info = readProjectInfo(root);
      if (info.kind === 'lib') {
        vscode.window.showInformationMessage('A library has no program of its own, and no program in this workspace uses it. Debug one of its tests from the Testing view instead.');
        return undefined;
      }
      if (!(await hasNativeDebugger())) {
        return undefined;
      }
      await vscode.workspace.saveAll(false);
      if (!(await buildForDebugging(root)).ok) {
        return undefined;
      }
      const exe = info.name + (process.platform === 'win32' ? '.exe' : '');
      const program = path.join(root, 'build', hostTarget(), 'debug', exe);
      return nativeDebugConfig(config.name || `Debug ${info.name}`, program,
        Array.isArray(config.args) ? config.args.map(String) : [], root);
    },
  };
  context.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider('pastel', provider),
    vscode.debug.registerDebugConfigurationProvider('pastel', provider,
      vscode.DebugConfigurationProviderTriggerKind.Dynamic));
}
