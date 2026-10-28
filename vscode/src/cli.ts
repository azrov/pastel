import * as cp from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export function pastelPath(): string {
  return vscode.workspace.getConfiguration('pastel').get<string>('path') || 'pastel';
}

/** The folder with pastel.toml that contains `file`, or undefined. */
export function findProjectRoot(file: string): string | undefined {
  let dir = fs.existsSync(file) && fs.statSync(file).isDirectory() ? file : path.dirname(file);
  for (;;) {
    if (fs.existsSync(path.join(dir, 'pastel.toml'))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      return undefined;
    }
    dir = parent;
  }
}

/** The project to work on: the active editor's, else the first in the workspace. */
export async function currentProjectRoot(): Promise<string | undefined> {
  const active = vscode.window.activeTextEditor?.document.uri;
  if (active && active.scheme === 'file') {
    const root = findProjectRoot(active.fsPath);
    if (root) {
      return root;
    }
  }
  const found = await vscode.workspace.findFiles('**/pastel.toml', '**/build/**', 1);
  return found.length > 0 ? path.dirname(found[0].fsPath) : undefined;
}

let reportedMissing = false;

/** Runs pastel and collects its output. Never rejects. */
export function runPastel(args: string[], cwd: string, stdin?: string): Promise<RunResult> {
  return new Promise(resolve => {
    let stdout = '';
    let stderr = '';
    let child: cp.ChildProcess;
    try {
      child = cp.spawn(pastelPath(), args, {
        cwd,
        env: { ...process.env, NO_COLOR: '1' },
      });
    } catch (e) {
      resolve({ code: -1, stdout: '', stderr: String(e) });
      return;
    }
    child.stdout?.on('data', d => (stdout += d.toString()));
    child.stderr?.on('data', d => (stderr += d.toString()));
    child.on('error', err => {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT' && !reportedMissing) {
        reportedMissing = true;
        vscode.window
          .showErrorMessage(
            `Pastel: the "${pastelPath()}" program was not found. Put it on your PATH or set "pastel.path".`,
            'Open Settings')
          .then(choice => {
            if (choice) {
              vscode.commands.executeCommand('workbench.action.openSettings', 'pastel.path');
            }
          });
      }
      resolve({ code: -1, stdout, stderr: String(err) });
    });
    child.on('close', code => resolve({ code: code ?? -1, stdout, stderr }));
    if (stdin !== undefined) {
      child.stdin?.end(stdin, 'utf8');
    }
  });
}
