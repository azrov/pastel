// Pascal code navigation: outline, symbol search across the project and the
// Pastel framework, go to definition, and Delphi's declaration/body toggle.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { dottedWordAt, parsePascal, PascalFile, PascalSymbol, toggleDeclaration } from './pascal';

export const pascalSelector: vscode.DocumentSelector = [
  { language: 'pascal' }, { language: 'objectpascal' },
];

interface Entry {
  file: string;
  parsed: PascalFile;
  framework: boolean;
}

const kindMap: Record<string, vscode.SymbolKind> = {
  unit: vscode.SymbolKind.Module,
  class: vscode.SymbolKind.Class,
  record: vscode.SymbolKind.Struct,
  interface: vscode.SymbolKind.Interface,
  type: vscode.SymbolKind.TypeParameter,
  method: vscode.SymbolKind.Method,
  routine: vscode.SymbolKind.Function,
  field: vscode.SymbolKind.Field,
  property: vscode.SymbolKind.Property,
};

/** Keeps a parsed copy of every Pascal file in the workspace and the framework. */
export class PascalIndex {
  private readonly entries = new Map<string, Entry>();
  private frameworkDir: string | undefined;

  async build(frameworkDir: string | undefined): Promise<void> {
    this.frameworkDir = frameworkDir;
    const files = await vscode.workspace.findFiles('**/*.{pas,pp,lpr,dpr}', '**/node_modules/**', 5000);
    for (const f of files) {
      if (/[\\/]release[\\/]gen[\\/]/.test(f.fsPath)) {
        continue;   // the debug copy of generated code is enough
      }
      this.update(f.fsPath);
    }
    if (frameworkDir && fs.existsSync(frameworkDir)) {
      for (const name of fs.readdirSync(frameworkDir)) {
        if (/\.(pas|pp)$/i.test(name)) {
          this.update(path.join(frameworkDir, name), undefined, true);
        }
      }
    }
  }

  /** The units of a library outside the workspace (a package in the cache): read-only, like the framework. */
  addLibrary(dir: string): void {
    const walk = (d: string, depth: number): void => {
      let names: string[];
      try {
        names = fs.readdirSync(d);
      } catch {
        return;
      }
      for (const name of names) {
        const full = path.join(d, name);
        if (/\.(pas|pp|inc)$/i.test(name)) {
          if (!/\.inc$/i.test(name)) {
            this.update(full, undefined, true);
          }
        } else if (depth < 6 && name !== 'build' && name !== 'tests' && !name.startsWith('.')) {
          try {
            if (fs.statSync(full).isDirectory()) {
              walk(full, depth + 1);
            }
          } catch {
            // gone meanwhile
          }
        }
      }
    };
    walk(path.join(dir, 'src'), 0);
  }

  update(file: string, text?: string, framework = false): void {
    try {
      const content = text ?? fs.readFileSync(file, 'utf8');
      const old = this.entries.get(file);
      this.entries.set(file, { file, parsed: parsePascal(content), framework: framework || (old?.framework ?? false) });
    } catch {
      this.entries.delete(file);
    }
  }

  remove(file: string): void {
    this.entries.delete(file);
  }

  get(file: string): PascalFile | undefined {
    return this.entries.get(file)?.parsed;
  }

  all(): Entry[] {
    return [...this.entries.values()];
  }

  /** File of a unit by name, e.g. "Pastel.UI" or "Home". */
  unitFile(name: string): string | undefined {
    const n = name.toLowerCase();
    for (const e of this.entries.values()) {
      if (e.parsed.unitName?.toLowerCase() === n) {
        return e.file;
      }
    }
    return undefined;
  }

  get framework(): string | undefined {
    return this.frameworkDir;
  }
}

function location(file: string, s: PascalSymbol): vscode.Location {
  const pos = new vscode.Position(s.line, Math.max(0, s.character));
  return new vscode.Location(vscode.Uri.file(file), new vscode.Range(pos, pos));
}

function displayName(s: PascalSymbol): string {
  return s.container && s.kind === 'method' && s.implementation ? `${s.container}.${s.name}` : s.name;
}

let definitionHook: ((doc: vscode.TextDocument, pos: vscode.Position) => vscode.Location[] | undefined) | undefined;

/** A more precise go-to-definition (the analyzer), tried first. */
export function setDefinitionHook(hook: typeof definitionHook): void {
  definitionHook = hook;
}

export function registerNavigation(context: vscode.ExtensionContext, index: PascalIndex): void {
  const parsedFor = (doc: vscode.TextDocument): PascalFile => {
    index.update(doc.uri.fsPath, doc.getText());
    return index.get(doc.uri.fsPath)!;
  };

  context.subscriptions.push(
    vscode.languages.registerDocumentSymbolProvider(pascalSelector, {
      provideDocumentSymbols(doc) {
        const file = parsedFor(doc);
        const out: vscode.DocumentSymbol[] = [];
        const types = new Map<string, vscode.DocumentSymbol>();
        for (const s of file.symbols) {
          const line = doc.lineAt(Math.min(s.line, doc.lineCount - 1));
          const end = s.endLine !== undefined ? doc.lineAt(Math.min(s.endLine, doc.lineCount - 1)).range.end : line.range.end;
          const sym = new vscode.DocumentSymbol(displayName(s), s.implementation ? '' : s.kind,
            kindMap[s.kind] ?? vscode.SymbolKind.Variable,
            new vscode.Range(line.range.start, end), new vscode.Range(s.line, Math.max(0, s.character), s.line,
              Math.max(0, s.character) + s.name.length));
          if (s.kind === 'unit') {
            continue;
          }
          const owner = s.container && !s.implementation ? types.get(s.container.toLowerCase()) : undefined;
          if (owner) {
            owner.children.push(sym);
          } else {
            out.push(sym);
          }
          if (s.kind === 'class' || s.kind === 'record' || s.kind === 'interface') {
            types.set(s.name.toLowerCase(), sym);
          }
        }
        return out;
      },
    }),

    vscode.languages.registerWorkspaceSymbolProvider({
      provideWorkspaceSymbols(query) {
        const q = query.toLowerCase();
        const out: vscode.SymbolInformation[] = [];
        for (const e of index.all()) {
          for (const s of e.parsed.symbols) {
            if (s.kind === 'field' || (q && !displayName(s).toLowerCase().includes(q))) {
              continue;
            }
            out.push(new vscode.SymbolInformation(displayName(s), kindMap[s.kind] ?? vscode.SymbolKind.Variable,
              e.framework ? 'Pastel framework' : path.basename(e.file), location(e.file, s)));
            if (out.length >= 500) {
              return out;
            }
          }
        }
        return out;
      },
    }),

    vscode.languages.registerDefinitionProvider(pascalSelector, {
      provideDefinition(doc, pos) {
        const precise = definitionHook?.(doc, pos);
        if (precise && precise.length) {
          return precise.length === 1 ? precise[0] : precise;
        }
        const file = parsedFor(doc);
        const lineText = doc.lineAt(pos.line).text;
        // a unit name: in a uses clause, or a dotted name like Pastel.UI
        const dotted = dottedWordAt(lineText, pos.character);
        if (dotted) {
          const inUses = file.uses.some(u => u.line === pos.line && u.name.toLowerCase() === dotted.word.toLowerCase());
          const unitFile = index.unitFile(dotted.word);
          if (unitFile && (inUses || dotted.word.includes('.'))) {
            return new vscode.Location(vscode.Uri.file(unitFile), new vscode.Position(0, 0));
          }
        }
        const range = doc.getWordRangeAtPosition(pos, /[A-Za-z_]\w*/);
        if (!range) {
          return undefined;
        }
        const word = doc.getText(range).toLowerCase();
        // on a method declaration or body: go to the other one (like Delphi)
        const here = file.symbols.find(s => s.line === pos.line && s.name.toLowerCase() === word &&
          (s.kind === 'method' || s.kind === 'routine'));
        if (here) {
          const other = toggleDeclaration(file, pos.line);
          if (other) {
            return location(doc.uri.fsPath, other);
          }
        }
        const results: { loc: vscode.Location; rank: number }[] = [];
        for (const e of index.all()) {
          for (const s of e.parsed.symbols) {
            if (s.name.toLowerCase() !== word || (s.line === pos.line && e.file === doc.uri.fsPath)) {
              continue;
            }
            // declarations before bodies; this file, then the project, then the framework
            let rank = s.implementation ? 1 : 0;
            rank += e.file === doc.uri.fsPath ? 0 : e.framework ? 20 : 10;
            results.push({ loc: location(e.file, s), rank });
          }
        }
        results.sort((a, b) => a.rank - b.rank);
        return results.slice(0, 20).map(r => r.loc);
      },
    }),
  );

  // keep the index current
  const watcher = vscode.workspace.createFileSystemWatcher('**/*.{pas,pp,lpr,dpr}');
  watcher.onDidChange(u => index.update(u.fsPath));
  watcher.onDidCreate(u => index.update(u.fsPath));
  watcher.onDidDelete(u => index.remove(u.fsPath));
  context.subscriptions.push(watcher);
}

/** Delphi's Ctrl+Shift+Up/Down: jump between a method's declaration and its body. */
export async function toggleDeclarationCommand(index: PascalIndex): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    return;
  }
  index.update(editor.document.uri.fsPath, editor.document.getText());
  const file = index.get(editor.document.uri.fsPath);
  const target = file && toggleDeclaration(file, editor.selection.active.line);
  if (!target) {
    vscode.window.setStatusBarMessage('Pastel: no matching declaration or body here', 2500);
    return;
  }
  const pos = new vscode.Position(target.line, Math.max(0, target.character));
  editor.selection = new vscode.Selection(pos, pos);
  editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenterIfOutsideViewport);
}
