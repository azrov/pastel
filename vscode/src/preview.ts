import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { findProjectRoot, runPastel } from './cli';
import { designerHtml } from './designerHtml';
import {
  deleteObjects, extractObject, extractObjects, findBlock, formatValue, insertObject, isObjectText, moveObject,
  moveSibling, outline, parseBlocks, placeObjects, insertObjectAt, parseValue, pasteObjects, renameIdentifier, renameObject, setProperty,
  unwrapObject, wrapObjects,
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
/** The pictures in the project's assets/ folder, as a .pform names them ('logo.png', 'icons/save.png'). */
export function assetImages(pformPath: string): string[] {
  let dir = path.dirname(pformPath);
  for (let i = 0; i < 6 && !fs.existsSync(path.join(dir, 'pastel.toml')); i++) {
    dir = path.dirname(dir);
  }
  const assets = path.join(dir, 'assets');
  const out: string[] = [];
  const walk = (d: string, prefix: string) => {
    let entries: fs.Dirent[];
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (out.length >= 200) return;
      if (e.isDirectory()) walk(path.join(d, e.name), prefix + e.name + '/');
      else if (/\.(png|jpe?g|bmp)$/i.test(e.name)) out.push(prefix + e.name);
    }
  };
  walk(assets, '');
  return out.sort();
}

export class FormPreview {
  private static current: FormPreview | undefined;
  private readonly panel: vscode.WebviewPanel;
  private document: vscode.TextDocument;
  private timer: NodeJS.Timeout | undefined;
  private running = false;
  private pending = false;
  private selected: string | undefined;
  // all selected controls (Ctrl+click); selected is the last one
  private selectedAll: string[] = [];
  private ignoreSelectionUntil = 0;
  private readonly imageFile: string;
  private readonly layoutFile: string;
  private readonly disposables: vscode.Disposable[] = [];
  // the designer's own undo: texts before each change made in the designer
  private queue: Promise<void> = Promise.resolve();
  private undoStack: string[] = [];
  private redoStack: string[] = [];
  private lastApplied: string | undefined;
  // how the preview is drawn
  private view: { width: number; height: number; dark: boolean } = { width: 0, height: 0, dark: false };

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
    // one message at a time: each edit starts from the text the one before left
    this.panel.webview.onDidReceiveMessage(m => {
      this.queue = this.queue.then(() => this.onMessage(m)).catch(e => console.error('pastel designer', e));
    }, null, this.disposables);
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

  /** The project's own controls changed: new toolbox and a new picture. */
  static async controlsChanged(): Promise<void> {
    const p = FormPreview.current;
    if (p) {
      await p.sendSchema();
      p.schedule(0);
    }
  }

  private async sendSchema(): Promise<void> {
    const schema = await this.services.loadSchema();
    if (schema) {
      this.panel.webview.postMessage({
        type: 'schema',
        controls: schema.controls.map(c => ({ name: c.name, container: c.container, project: !!c.project, nonvisual: !!c.nonvisual })),
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
      const args = ['preview', rel, '--stdin', '-o', this.imageFile, '--layout', this.layoutFile, '--json'];
      if (this.view.width > 0) {
        args.push('--width', String(this.view.width), '--height', String(this.view.height));
      }
      if (this.view.dark) {
        args.push('--dark');
      }
      const result = await runPastel(args, cwd, this.document.getText());
      if (result.code === 0 && fs.existsSync(this.imageFile)) {
        const data = fs.readFileSync(this.imageFile).toString('base64');
        let layout: unknown = undefined;
        try {
          layout = JSON.parse(fs.readFileSync(this.layoutFile, 'utf8'));
        } catch {
          layout = undefined;
        }
        const root = parseBlocks(this.document.getText());
        const titleLine = root?.props.find(p => p.name.toLowerCase() === 'title');
        const title = titleLine ? parseValue(titleLine.value) : root?.name ?? '';
        this.panel.webview.postMessage({ type: 'render', data, layout, file: path.basename(file), title });
        await this.sendSelection();
        await this.sendTree();
        this.sendIssues(cwd, rel);
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

  /** The objects of the form, for the structure list (non-visual ones are only there). */
  private async sendTree(): Promise<void> {
    const schema = await this.services.loadSchema();
    const items = outline(this.document.getText()).map(o => ({
      ...o,
      nonvisual: !!schema?.controls.find(c => c.name.toLowerCase() === o.className.toLowerCase())?.nonvisual,
    }));
    this.panel.webview.postMessage({ type: 'tree', items });
  }

  /** What "pastel check" says about the form, drawn on the controls it is about. */
  private async sendIssues(cwd: string, rel: string): Promise<void> {
    const text = this.document.getText();
    const r = await runPastel(['check', rel, '--stdin', '--json'], cwd, text);
    let found: { line: number; severity: string; message: string }[] = [];
    try {
      found = JSON.parse(r.stdout || '[]');
    } catch {
      found = [];
    }
    const lines = text.split(/\r?\n/);
    const items = found.map(i => {
      const chain = enclosingObjects(lines, i.line);
      return { name: chain.length ? chain[chain.length - 1].name : undefined, severity: i.severity, message: i.message, line: i.line };
    });
    if (text === this.document.getText()) {
      this.panel.webview.postMessage({ type: 'issues', items });
    }
  }

  private async sendSelection(): Promise<void> {
    const schema = await this.services.loadSchema();
    const root = parseBlocks(this.document.getText());
    const block = root && this.selected ? findBlock(root, this.selected) : undefined;
    if (!schema || !root || !block) {
      this.selected = undefined;
      this.selectedAll = [];
      this.panel.webview.postMessage({ type: 'select', name: null });
      return;
    }
    const blocks = this.selectedAll.map(n => findBlock(root, n)).filter(b => !!b && b !== root) as NonNullable<typeof block>[];
    if (blocks.length > 1) {
      // several: the properties they all have, with the value when it is the same
      const classes = blocks.map(b => schema.controls.find(c => c.name.toLowerCase() === b.className.toLowerCase()));
      const first = classes[0]?.properties ?? [];
      const common = first.filter(p => p.type !== 'event' &&
        classes.every(c => c?.properties.some(q => q.name === p.name && q.type === p.type)));
      const props = common.map(p => {
        const values = blocks.map(b => {
          const line = b.props.find(x => x.name.toLowerCase() === p.name.toLowerCase());
          return line ? parseValue(line.value) : undefined;
        });
        const same = values.every(v => v === values[0]);
        return { ...p, value: same ? values[0] : undefined, mixed: !same };
      });
      const sameParent = blocks.every(b => b.parent === blocks[0].parent);
      this.selectedAll = blocks.map(b => b.name);
      this.panel.webview.postMessage({
        type: 'select', name: block.name, names: this.selectedAll, className: '', isRoot: false, props, handlers: [],
        sameParent,
      });
      return;
    }
    this.selectedAll = [block.name];
    const cls: SchemaClass | undefined = block === root ? schema.form :
      schema.controls.find(c => c.name.toLowerCase() === block.className.toLowerCase());
    const pas = this.formUnitText();
    const handlers = pas ? declaredProcedures(pas) : [];
    const images = assetImages(this.document.uri.fsPath);
    const props = (cls?.properties ?? []).map(p => {
      const line = block.props.find(x => x.name.toLowerCase() === p.name.toLowerCase());
      // the pictures in assets/ for FileName and BackgroundImage
      const suggest = p.type === 'string' && /^(FileName|BackgroundImage)$/i.test(p.name) && images.length ? images : p.suggest;
      return { ...p, suggest, value: line ? parseValue(line.value) : undefined };
    });
    this.panel.webview.postMessage({
      type: 'select', name: block.name, names: [block.name], className: block.className, isRoot: block === root,
      props, handlers, children: block.children.length,
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

  private async applyText(text: string, history = true): Promise<void> {
    const old = this.document.getText();
    if (text === old) {
      return;
    }
    // never write a form whose objects and ends do not match (it would not compile)
    if (parseBlocks(old) && !parseBlocks(text)) {
      vscode.window.showErrorMessage('Pastel: the designer did not make this change; it would leave the form unbalanced.');
      return;
    }
    if (history) {
      // edits typed in the editor since our last change end the designer's history
      if (this.lastApplied !== undefined && this.lastApplied !== old) {
        this.undoStack = [];
      }
      this.undoStack.push(old);
      if (this.undoStack.length > 100) {
        this.undoStack.shift();
      }
      this.redoStack = [];
    }
    this.lastApplied = text;
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
      this.selectedAll = [name];
      this.sendSelection();
    }
  }

  private async onMessage(m: any): Promise<void> {
    const text = this.document.getText();
    switch (m.type) {
      case 'select':
        this.selected = m.name ?? undefined;
        this.selectedAll = Array.isArray(m.names) && m.names.length ? m.names : (m.name ? [m.name] : []);
        await this.sendSelection();
        if (m.name) {
          this.revealInEditor(m.name);
        }
        break;
      case 'setProp': {
        const value = m.value === null ? undefined : formatValue(m.propType, String(m.value));
        let out = text;
        for (const n of (Array.isArray(m.names) && m.names.length ? m.names : [m.name])) {
          out = setProperty(out, n, m.prop, value);
        }
        await this.applyText(out);
        break;
      }
      case 'wrap': {
        const r = wrapObjects(text, m.names, m.className);
        if (r) {
          this.selected = r.name;
          this.selectedAll = [r.name];
          await this.applyText(r.text);
          this.revealInEditor(r.name);
        } else {
          vscode.window.showWarningMessage('Pastel: only controls in the same container can be put together.');
        }
        break;
      }
      case 'unwrap': {
        const root = parseBlocks(text);
        const first = root && findBlock(root, m.name)?.children[0];
        this.selected = first?.name ?? findBlock(root!, m.name)?.parent?.name;
        this.selectedAll = this.selected ? [this.selected] : [];
        await this.applyText(unwrapObject(text, m.name));
        break;
      }
      case 'moveSibling':
        await this.applyText(moveSibling(text, m.name, m.delta));
        break;
      case 'add': {
        // into a parent with Layout = Free: at the place it was dropped
        const r = typeof m.left === 'number' && typeof m.top === 'number'
          ? insertObjectAt(text, m.parent, m.className, m.left, m.top)
          : insertObject(text, m.parent, m.index, m.className);
        if (r) {
          this.selected = r.name;
          await this.applyText(r.text);
          this.revealInEditor(r.name);
        }
        break;
      }
      case 'place': {
        // moved or resized in a parent with Layout = Free (or the form resized)
        const items = Array.isArray(m.items) ? m.items : [];
        await this.applyText(placeObjects(text, m.parent ?? undefined, items));
        if (items.length) {
          this.selected = items[items.length - 1].name;
          this.selectedAll = items.map((i: { name: string }) => i.name);
        }
        break;
      }
      case 'move':
        await this.applyText(moveObject(text, m.name, m.parent, m.index));
        this.selected = m.name;
        break;
      case 'undo':
      case 'redo': {
        const from = m.type === 'undo' ? this.undoStack : this.redoStack;
        const to = m.type === 'undo' ? this.redoStack : this.undoStack;
        if (this.lastApplied !== undefined && this.lastApplied !== text) {
          // changed in the editor meanwhile: the editor's own undo knows best
          this.undoStack = [];
          this.redoStack = [];
          vscode.window.setStatusBarMessage('Pastel: the .pform was edited in the editor; use Undo there', 4000);
          break;
        }
        const prev = from.pop();
        if (prev === undefined) {
          break;
        }
        to.push(text);
        await this.applyText(prev, false);
        break;
      }
      case 'copy':
      case 'cut': {
        const names: string[] = Array.isArray(m.names) && m.names.length ? m.names : (m.name ? [m.name] : []);
        const obj = names.length > 1 ? extractObjects(text, names) : (m.name ? extractObject(text, m.name) : undefined);
        if (obj) {
          await vscode.env.clipboard.writeText(obj);
          if (m.type === 'cut') {
            const root = parseBlocks(text);
            this.selected = (root && findBlock(root, names[0]))?.parent?.name;
            this.selectedAll = this.selected ? [this.selected] : [];
            await this.applyText(deleteObjects(text, names));
          }
        }
        break;
      }
      case 'paste':
      case 'duplicate': {
        const clip = m.type === 'duplicate' ? (m.name ? extractObject(text, m.name) : undefined)
          : await vscode.env.clipboard.readText();
        if (!clip || !isObjectText(clip)) {
          break;
        }
        const root = parseBlocks(text);
        const sel = root && (m.name ? findBlock(root, m.name) : root);
        if (!root || !sel) {
          break;
        }
        // into a selected container (paste), else after the selected control
        const info = (await this.services.loadSchema())?.controls.find(c => c.name.toLowerCase() === sel.className.toLowerCase());
        const intoSel = sel === root || (m.type === 'paste' && info?.container);
        const parent = intoSel ? sel : sel.parent!;
        const index = intoSel ? parent.children.length : parent.children.indexOf(sel) + 1;
        const r = pasteObjects(text, clip, parent.name, index);
        if (r) {
          this.selected = r.name;
          await this.applyText(r.text);
        }
        break;
      }
      case 'rename': {
        let newName: string | undefined = m.newName;
        if (newName === undefined) {
          newName = await vscode.window.showInputBox({ prompt: `New name for ${m.name}`, value: m.name });
        }
        if (!newName || newName === m.name) {
          break;
        }
        const renamed = renameObject(text, m.name, newName);
        if (!renamed) {
          vscode.window.showErrorMessage(`Pastel: "${newName}" cannot be used: it is not a Pascal name or the form has it already.`);
          await this.sendSelection();
          break;
        }
        await this.applyText(renamed);
        this.selected = newName;
        // the form's code uses the control by name too
        const pasPath = this.document.uri.fsPath.replace(/\.pform$/i, '.pas');
        const pas = this.formUnitText();
        if (pas) {
          const newPas = renameIdentifier(pas, m.name, newName);
          if (newPas !== pas) {
            const doc = await vscode.workspace.openTextDocument(pasPath);
            const edit = new vscode.WorkspaceEdit();
            edit.replace(doc.uri, new vscode.Range(new vscode.Position(0, 0), doc.positionAt(doc.getText().length)), newPas);
            await vscode.workspace.applyEdit(edit);
          }
        }
        break;
      }
      case 'view':
        this.view = { width: Number(m.width) || 0, height: Number(m.height) || 0, dark: !!m.dark };
        this.schedule(0);
        break;
      case 'delete': {
        const names: string[] = Array.isArray(m.names) && m.names.length ? m.names : [m.name];
        const root = parseBlocks(text);
        const block = root && findBlock(root, names[0]);
        this.selected = block?.parent?.name;
        this.selectedAll = this.selected ? [this.selected] : [];
        await this.applyText(deleteObjects(text, names));
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
