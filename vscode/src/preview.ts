import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { findProjectRoot, runPastel } from './cli';
import { designerHtml } from './designerHtml';
import {
  deleteObject, findBlock, formatValue, insertObject, moveObject, parseBlocks, parseValue, setProperty,
} from './edit';
import { declaredProcedures, enclosingObjects, findProcedure, Schema, SchemaClass } from './model';

export interface DesignerServices {
  loadSchema(): Promise<Schema | undefined>;
  addHandler(pform: vscode.Uri, name: string, params: string): Promise<void>;
}

/**
 * The form designer: a live picture of a .pform file beside the editor.
 * Click to select a control, edit its properties, drag controls to move
 * them, drag new ones in from the toolbox. Every change is a normal text
 * edit of the .pform file, so Undo works in the editor.
 */
export class FormPreview {
  private static current: FormPreview | undefined;
  private readonly panel: vscode.WebviewPanel;
  private document: vscode.TextDocument;
  private timer: NodeJS.Timeout | undefined;
  private running = false;
  private pending = false;
  private selected: string | undefined;
  private ignoreSelectionUntil = 0;
  private readonly imageFile: string;
  private readonly layoutFile: string;
  private readonly disposables: vscode.Disposable[] = [];

  /** The .pform shown in the designer, if the designer is the active tab. */
  static get activeDocument(): vscode.TextDocument | undefined {
    const c = FormPreview.current;
    return c && c.panel.active ? c.document : undefined;
  }

  static show(document: vscode.TextDocument, services: DesignerServices): void {
    if (FormPreview.current) {
      FormPreview.current.document = document;
      FormPreview.current.panel.reveal(vscode.ViewColumn.Beside, true);
      FormPreview.current.schedule(0);
      return;
    }
    FormPreview.current = new FormPreview(document, services);
  }

  private constructor(document: vscode.TextDocument, private readonly services: DesignerServices) {
    this.document = document;
    const base = path.join(os.tmpdir(), `pastel-designer-${process.pid}`);
    this.imageFile = base + '.png';
    this.layoutFile = base + '.json';
    this.panel = vscode.window.createWebviewPanel(
      'pastelPreview', 'Form Designer',
      { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true },
      { enableScripts: true, retainContextWhenHidden: true });
    this.panel.webview.html = this.html();
    this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    this.panel.webview.onDidReceiveMessage(m => this.onMessage(m), null, this.disposables);
    vscode.workspace.onDidChangeTextDocument(e => {
      if (e.document === this.document) {
        this.schedule(200);
      }
    }, null, this.disposables);
    vscode.window.onDidChangeActiveTextEditor(e => {
      if (e && e.document.languageId === 'pform' && e.document !== this.document) {
        this.document = e.document;
        this.selected = undefined;
        this.schedule(0);
      }
    }, null, this.disposables);
    vscode.window.onDidChangeTextEditorSelection(e => this.onEditorSelection(e), null, this.disposables);
    this.sendSchema();
    this.schedule(0);
  }

  private async sendSchema(): Promise<void> {
    const schema = await this.services.loadSchema();
    if (schema) {
      this.panel.webview.postMessage({
        type: 'schema',
        controls: schema.controls.map(c => ({ name: c.name, container: c.container })),
      });
    }
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
      this.panel.title = `Design: ${path.basename(file)}`;
      const result = await runPastel(
        ['preview', rel, '--stdin', '-o', this.imageFile, '--layout', this.layoutFile, '--json'],
        cwd, this.document.getText());
      if (result.code === 0 && fs.existsSync(this.imageFile)) {
        const data = fs.readFileSync(this.imageFile).toString('base64');
        let layout: unknown = undefined;
        try {
          layout = JSON.parse(fs.readFileSync(this.layoutFile, 'utf8'));
        } catch {
          layout = undefined;
        }
        this.panel.webview.postMessage({ type: 'render', data, layout, file: path.basename(file) });
        await this.sendSelection();
      } else {
        const message = (result.stderr || result.stdout || 'The form could not be drawn.').trim();
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

  private async sendSelection(): Promise<void> {
    const schema = await this.services.loadSchema();
    const root = parseBlocks(this.document.getText());
    const block = root && this.selected ? findBlock(root, this.selected) : undefined;
    if (!schema || !root || !block) {
      this.selected = undefined;
      this.panel.webview.postMessage({ type: 'select', name: null });
      return;
    }
    const cls: SchemaClass | undefined = block === root ? schema.form :
      schema.controls.find(c => c.name.toLowerCase() === block.className.toLowerCase());
    const pas = this.formUnitText();
    const handlers = pas ? declaredProcedures(pas) : [];
    const props = (cls?.properties ?? []).map(p => {
      const line = block.props.find(x => x.name.toLowerCase() === p.name.toLowerCase());
      return { ...p, value: line ? parseValue(line.value) : undefined };
    });
    this.panel.webview.postMessage({
      type: 'select', name: block.name, className: block.className, isRoot: block === root,
      props, handlers,
    });
  }

  private formUnitText(): string | undefined {
    const pas = this.document.uri.fsPath.replace(/\.pform$/i, '.pas');
    const open = vscode.workspace.textDocuments.find(d => d.uri.fsPath === pas);
    if (open) {
      return open.getText();
    }
    return fs.existsSync(pas) ? fs.readFileSync(pas, 'utf8') : undefined;
  }

  private async applyText(text: string): Promise<void> {
    const old = this.document.getText();
    if (text === old) {
      return;
    }
    const edit = new vscode.WorkspaceEdit();
    const end = this.document.positionAt(old.length);
    edit.replace(this.document.uri, new vscode.Range(new vscode.Position(0, 0), end), text);
    await vscode.workspace.applyEdit(edit);
  }

  private revealInEditor(name: string): void {
    const root = parseBlocks(this.document.getText());
    const block = root && findBlock(root, name);
    const editor = vscode.window.visibleTextEditors.find(e => e.document === this.document);
    if (!block || !editor) {
      return;
    }
    const pos = new vscode.Position(block.start, editor.document.lineAt(block.start).firstNonWhitespaceCharacterIndex);
    this.ignoreSelectionUntil = Date.now() + 300;
    editor.selection = new vscode.Selection(pos, pos);
    editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenterIfOutsideViewport);
  }

  private onEditorSelection(e: vscode.TextEditorSelectionChangeEvent): void {
    if (e.textEditor.document !== this.document || Date.now() < this.ignoreSelectionUntil) {
      return;
    }
    const lines = this.document.getText().split(/\r?\n/);
    const chain = enclosingObjects(lines, e.selections[0].active.line + 1);
    const name = chain.length > 0 ? chain[chain.length - 1].name : undefined;
    if (name && name !== this.selected) {
      this.selected = name;
      this.sendSelection();
    }
  }

  private async onMessage(m: any): Promise<void> {
    const text = this.document.getText();
    switch (m.type) {
      case 'select':
        this.selected = m.name ?? undefined;
        await this.sendSelection();
        if (m.name) {
          this.revealInEditor(m.name);
        }
        break;
      case 'setProp':
        await this.applyText(setProperty(text, m.name, m.prop,
          m.value === null ? undefined : formatValue(m.propType, String(m.value))));
        break;
      case 'add': {
        const r = insertObject(text, m.parent, m.index, m.className);
        if (r) {
          this.selected = r.name;
          await this.applyText(r.text);
          this.revealInEditor(r.name);
        }
        break;
      }
      case 'move':
        await this.applyText(moveObject(text, m.name, m.parent, m.index));
        this.selected = m.name;
        break;
      case 'delete': {
        const root = parseBlocks(text);
        const block = root && findBlock(root, m.name);
        this.selected = block?.parent?.name;
        await this.applyText(deleteObject(text, m.name));
        break;
      }
      case 'code': {
        const pasPath = this.document.uri.fsPath.replace(/\.pform$/i, '.pas');
        const pas = this.formUnitText();
        let handler: string = m.handler;
        if (!handler) {
          handler = `${String(m.name).replace(/(Button|Edit|Label)$/, '')}${String(m.prop).replace(/^On/, '')}`;
          await this.applyText(setProperty(text, m.name, m.prop, handler));
        }
        const found = pas ? findProcedure(pas, handler) : undefined;
        if (found) {
          const doc = await vscode.workspace.openTextDocument(pasPath);
          const editor = await vscode.window.showTextDocument(doc, vscode.ViewColumn.One);
          const pos = new vscode.Position(found.line, found.character);
          editor.selection = new vscode.Selection(pos, pos);
          editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenter);
        } else {
          await this.services.addHandler(this.document.uri, handler, m.signature || '(Sender: TObject)');
        }
        break;
      }
    }
  }

  private html(): string {
    return designerHtml(Math.random().toString(36).slice(2));
  }

  private dispose(): void {
    FormPreview.current = undefined;
    if (this.timer) {
      clearTimeout(this.timer);
    }
    this.disposables.forEach(d => d.dispose());
    fs.rm(this.imageFile, { force: true }, () => undefined);
    fs.rm(this.layoutFile, { force: true }, () => undefined);
  }
}
