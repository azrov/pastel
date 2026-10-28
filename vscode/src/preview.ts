import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { findProjectRoot, runPastel } from './cli';

/** A panel beside the editor that shows how a .pform file looks, live. */
export class FormPreview {
  private static current: FormPreview | undefined;
  private readonly panel: vscode.WebviewPanel;
  private document: vscode.TextDocument;
  private timer: NodeJS.Timeout | undefined;
  private running = false;
  private pending = false;
  private readonly imageFile: string;
  private readonly disposables: vscode.Disposable[] = [];

  static show(document: vscode.TextDocument): void {
    if (FormPreview.current) {
      FormPreview.current.document = document;
      FormPreview.current.panel.reveal(vscode.ViewColumn.Beside, true);
      FormPreview.current.schedule(0);
      return;
    }
    FormPreview.current = new FormPreview(document);
  }

  private constructor(document: vscode.TextDocument) {
    this.document = document;
    this.imageFile = path.join(os.tmpdir(), `pastel-preview-${process.pid}.png`);
    this.panel = vscode.window.createWebviewPanel(
      'pastelPreview', 'Form Preview',
      { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true },
      { enableScripts: true, retainContextWhenHidden: true });
    this.panel.webview.html = this.html();
    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    vscode.workspace.onDidChangeTextDocument(e => {
      if (e.document === this.document) {
        this.schedule(250);
      }
    }, null, this.disposables);
    vscode.window.onDidChangeActiveTextEditor(e => {
      if (e && e.document.languageId === 'pform' && e.document !== this.document) {
        this.document = e.document;
        this.schedule(0);
      }
    }, null, this.disposables);
    this.schedule(0);
  }

  private schedule(delay: number): void {
    if (this.timer) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => this.render(), delay);
  }

  private async render(): Promise<void> {
    if (this.running) {
      this.pending = true;
      return;
    }
    this.running = true;
    try {
      const file = this.document.uri.fsPath;
      const cwd = findProjectRoot(file) ?? path.dirname(file);
      const rel = path.relative(cwd, file);
      this.panel.title = `Preview: ${path.basename(file)}`;
      const result = await runPastel(
        ['preview', rel, '--stdin', '-o', this.imageFile, '--json'], cwd, this.document.getText());
      if (result.code === 0 && fs.existsSync(this.imageFile)) {
        const data = fs.readFileSync(this.imageFile).toString('base64');
        this.panel.webview.postMessage({ type: 'image', data, file: path.basename(file) });
      } else {
        const message = (result.stderr || result.stdout || 'The preview could not be drawn.').trim();
        this.panel.webview.postMessage({ type: 'error', message });
      }
    } finally {
      this.running = false;
      if (this.pending) {
        this.pending = false;
        this.schedule(0);
      }
    }
  }

  private html(): string {
    const nonce = Math.random().toString(36).slice(2);
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<style>
  body { margin: 0; padding: 16px; font-family: var(--vscode-font-family); color: var(--vscode-foreground); }
  .bar { display: flex; gap: 12px; align-items: center; margin-bottom: 12px; font-size: 12px; opacity: .8; }
  .frame { display: inline-block; box-shadow: 0 2px 12px rgba(0,0,0,.25); border-radius: 6px; overflow: hidden; line-height: 0; }
  img { max-width: 100%; height: auto; image-rendering: auto; }
  body.actual img { max-width: none; }
  .error { display: none; margin-top: 12px; padding: 10px 12px; border-radius: 6px; white-space: pre-wrap;
    background: var(--vscode-inputValidation-errorBackground); border: 1px solid var(--vscode-inputValidation-errorBorder);
    font-family: var(--vscode-editor-font-family); font-size: 12px; }
  body.has-error .error { display: block; }
  body.has-error .frame { opacity: .5; }
  .empty { opacity: .7; }
</style>
</head>
<body>
  <div class="bar">
    <span id="name">Drawing the form…</span>
    <label><input type="checkbox" id="actual"> Actual size</label>
  </div>
  <div class="frame"><img id="img" alt=""></div>
  <div class="error" id="error"></div>
<script nonce="${nonce}">
  const img = document.getElementById('img');
  const err = document.getElementById('error');
  const name = document.getElementById('name');
  document.getElementById('actual').addEventListener('change', e => {
    document.body.classList.toggle('actual', e.target.checked);
  });
  window.addEventListener('message', e => {
    const m = e.data;
    if (m.type === 'image') {
      img.src = 'data:image/png;base64,' + m.data;
      name.textContent = m.file + ' - updates as you type';
      document.body.classList.remove('has-error');
    } else if (m.type === 'error') {
      err.textContent = m.message;
      document.body.classList.add('has-error');
    }
  });
</script>
</body>
</html>`;
  }

  private dispose(): void {
    FormPreview.current = undefined;
    if (this.timer) {
      clearTimeout(this.timer);
    }
    this.disposables.forEach(d => d.dispose());
    fs.rm(this.imageFile, { force: true }, () => undefined);
  }
}
