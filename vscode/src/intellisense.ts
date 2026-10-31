// Pascal code intelligence in VS Code: completion, hover, parameter hints,
// go to definition, find references, rename, compiler errors while typing,
// "add unit to uses" and Delphi's class completion (Ctrl+Shift+C).
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { findProjectRoot, runPastel } from './cli';
import { Analyzer, Decl, ParsedUnit, signature } from './lang/analyzer';
import { blankComments } from './pascal';
import { PascalIndex, pascalSelector } from './navigation';

let analyzer: Analyzer | undefined;
let frameworkDir: string | undefined;

const KIND: Record<string, vscode.CompletionItemKind> = {
  class: vscode.CompletionItemKind.Class,
  record: vscode.CompletionItemKind.Struct,
  object: vscode.CompletionItemKind.Class,
  interface: vscode.CompletionItemKind.Interface,
  enum: vscode.CompletionItemKind.Enum,
  enumvalue: vscode.CompletionItemKind.EnumMember,
  type: vscode.CompletionItemKind.TypeParameter,
  const: vscode.CompletionItemKind.Constant,
  var: vscode.CompletionItemKind.Variable,
  param: vscode.CompletionItemKind.Variable,
  result: vscode.CompletionItemKind.Variable,
  field: vscode.CompletionItemKind.Field,
  property: vscode.CompletionItemKind.Property,
  method: vscode.CompletionItemKind.Method,
  routine: vscode.CompletionItemKind.Function,
  unit: vscode.CompletionItemKind.Module,
};

const KEYWORDS = ['begin', 'end', 'if', 'then', 'else', 'for', 'to', 'downto', 'do', 'while', 'repeat', 'until',
  'case', 'of', 'try', 'except', 'finally', 'raise', 'with', 'var', 'const', 'type', 'procedure', 'function',
  'constructor', 'destructor', 'property', 'class', 'record', 'array', 'string', 'nil', 'not', 'and', 'or', 'xor',
  'div', 'mod', 'in', 'is', 'as', 'inherited', 'exit', 'uses', 'interface', 'implementation', 'initialization',
  'finalization', 'private', 'protected', 'public', 'published', 'override', 'virtual', 'overload', 'specialize'];

export function getAnalyzer(): Analyzer | undefined {
  return analyzer;
}

function inCommentOrString(doc: vscode.TextDocument, pos: vscode.Position): boolean {
  const upTo = doc.getText(new vscode.Range(new vscode.Position(Math.max(0, pos.line - 200), 0), pos));
  const blanked = blankComments(upTo);
  const line = blanked.split('\n').pop() ?? '';
  const raw = upTo.split('\n').pop() ?? '';
  const ch = raw.length - 1;
  if (ch < 0) {
    return false;
  }
  // a comment or string covers the character before the cursor
  if (line[ch] === ' ' && raw[ch] !== ' ') {
    return true;
  }
  const quotes = (line.match(/'/g) ?? []).length;
  return quotes % 2 === 1;
}

function unitFor(doc: vscode.TextDocument): ParsedUnit | undefined {
  if (!analyzer) {
    return undefined;
  }
  analyzer.setText(doc.uri.fsPath, doc.getText());
  return analyzer.unitForFile(doc.uri.fsPath);
}

function docMarkdown(d: Decl): vscode.MarkdownString {
  const md = new vscode.MarkdownString();
  md.appendCodeblock(signature(d), 'pascal');
  if (d.doc) {
    md.appendMarkdown('\n' + d.doc.replace(/\n/g, '  \n'));
  }
  const unit = analyzer?.unitOfDecl(d);
  if (unit?.name && d.kind !== 'param' && d.kind !== 'result' && d.kind !== 'unit') {
    md.appendMarkdown(`\n\n*${unit.name}*`);
  }
  return md;
}

function location(d: Decl): vscode.Location {
  const p = new vscode.Position(d.line, Math.max(0, d.col));
  return new vscode.Location(vscode.Uri.file(d.file), new vscode.Range(p, p));
}

function declAt(doc: vscode.TextDocument, pos: vscode.Position): { decls: Decl[]; unit: ParsedUnit; range?: vscode.Range } | undefined {
  const unit = unitFor(doc);
  if (!unit || !analyzer) {
    return undefined;
  }
  const k = analyzer.tokenIndexAt(unit.tokens, pos.line, pos.character, doc.uri.fsPath);
  if (k < 0) {
    return undefined;
  }
  const t = unit.tokens[k];
  return {
    decls: analyzer.resolveToken(unit, k), unit,
    range: new vscode.Range(t.line, t.col, t.line, t.col + t.text.length),
  };
}

function projectPascalFiles(index: PascalIndex): string[] {
  return index.all().filter(e => !e.framework && !/[\\/]build[\\/]/.test(e.file)).map(e => e.file);
}

// units generated from .pform files (build/<platform>/<debug|check>/gen), newest build first
function generatedFiles(): string[] {
  const out: string[] = [];
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const build = path.join(folder.uri.fsPath, 'build');
    if (!fs.existsSync(build)) {
      continue;
    }
    for (const target of fs.readdirSync(build)) {
      for (const profile of ['check', 'debug']) {
        const gen = path.join(build, target, profile, 'gen');
        if (fs.existsSync(gen)) {
          for (const f of fs.readdirSync(gen)) {
            if (/\.pas$/i.test(f)) {
              out.push(path.join(gen, f));
            }
          }
        }
      }
    }
  }
  return out;
}

// ---------------- compiler errors while typing ----------------

const compilerDiagnostics = vscode.languages.createDiagnosticCollection('pastel-compiler');
const pending = new Map<string, NodeJS.Timeout>();
const running = new Set<string>();
const again = new Set<string>();

async function checkWithCompiler(doc: vscode.TextDocument): Promise<void> {
  const root = findProjectRoot(doc.uri.fsPath);
  if (!root) {
    return;
  }
  const key = doc.uri.fsPath;
  if (running.has(key)) {
    again.add(key);
    return;
  }
  running.add(key);
  try {
    const version = doc.version;
    const r = await runPastel(['check', path.relative(root, doc.uri.fsPath), '--stdin', '--json'], root, doc.getText());
    if (doc.version !== version && doc.isDirty) {
      again.add(key);
      return;
    }
    let items: { file: string; line: number; column: number; severity: string; message: string }[];
    try {
      items = JSON.parse(r.stdout.trim().split('\n').pop() || '[]');
    } catch {
      return;
    }
    const byFile = new Map<string, vscode.Diagnostic[]>();
    byFile.set(doc.uri.fsPath, []);
    for (const it of items) {
      if (it.severity === 'info') {
        continue;
      }
      const line = Math.max(0, it.line - 1);
      const col = Math.max(0, it.column - 1);
      const d = new vscode.Diagnostic(new vscode.Range(line, col, line, col + 1), it.message,
        it.severity === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning);
      d.source = 'fpc';
      if (!byFile.has(it.file)) {
        byFile.set(it.file, []);
      }
      byFile.get(it.file)!.push(d);
    }
    for (const [file, diags] of byFile) {
      // underline the whole word at the column
      const open = vscode.workspace.textDocuments.find(x => x.uri.fsPath === file);
      if (open) {
        for (const d of diags) {
          const w = open.getWordRangeAtPosition(d.range.start, /[A-Za-z_]\w*/);
          if (w) {
            d.range = w;
          }
        }
      }
      compilerDiagnostics.set(vscode.Uri.file(file), diags);
    }
  } finally {
    running.delete(key);
    if (again.delete(key)) {
      schedule(doc, 300);
    }
  }
}

function schedule(doc: vscode.TextDocument, ms: number): void {
  if (doc.languageId !== 'pascal' && doc.languageId !== 'objectpascal') {
    return;
  }
  if (!vscode.workspace.getConfiguration('pastel').get<boolean>('compileWhileTyping', true)) {
    return;
  }
  if (!findProjectRoot(doc.uri.fsPath)) {
    return;
  }
  clearTimeout(pending.get(doc.uri.fsPath));
  pending.set(doc.uri.fsPath, setTimeout(() => {
    pending.delete(doc.uri.fsPath);
    void checkWithCompiler(doc);
  }, ms));
}

// ---------------- quick fixes ----------------

const COMMON_UNITS = ['SysUtils', 'Classes', 'StrUtils', 'Math', 'DateUtils', 'Types', 'TypInfo', 'Variants', 'SyncObjs',
  'fpjson', 'jsonparser', 'Process', 'RegExpr', 'IniFiles', 'base64', 'md5', 'sha1', 'URIParser', 'ZStream', 'Contnrs',
  'fgl', 'Generics.Collections', 'Generics.Defaults', 'DB', 'SQLDB', 'BaseUnix', 'Unix', 'Windows', 'CTypes',
  'StreamEx', 'Character', 'fphttpclient', 'opensslsockets'];

function unitsDeclaring(name: string, exclude: string): string[] {
  if (!analyzer) {
    return [];
  }
  const n = name.toLowerCase();
  const out: string[] = [];
  const candidates = analyzer.unitNames().filter(u => u.source !== 'fpc').map(u => u.name);
  for (const c of COMMON_UNITS) {
    if (!candidates.some(x => x.toLowerCase() === c.toLowerCase())) {
      candidates.push(c);
    }
  }
  for (const u of candidates) {
    if (u.toLowerCase() === exclude.toLowerCase()) {
      continue;
    }
    const pu = analyzer.unitByName(u);
    if (pu && !pu.isProgram && pu.interfaceDecls.some(d => d.name.toLowerCase() === n ||
        (d.kind === 'enum' && (d.members ?? []).some(m => m.name.toLowerCase() === n)))) {
      out.push(pu.name || u);
    }
  }
  return out;
}

function addUnitEdit(doc: vscode.TextDocument, unit: ParsedUnit, unitName: string, line: number): vscode.WorkspaceEdit {
  const edit = new vscode.WorkspaceEdit();
  const inImpl = !unit.isProgram && unit.implementationLine >= 0 && line > unit.implementationLine;
  const uses = inImpl ? unit.implementationUses : unit.interfaceUses;
  const tokens = unit.tokens.filter(t => !t.file || t.file === unit.file);
  if (uses.length) {
    const last = uses[uses.length - 1];
    const semi = tokens.find(t => t.kind === 'symbol' && t.text === ';' && (t.line > last.line || (t.line === last.line && t.col > last.col)));
    if (semi) {
      edit.insert(doc.uri, new vscode.Position(semi.line, semi.col), `, ${unitName}`);
      return edit;
    }
  }
  // no uses clause yet: after "implementation", "interface" or "program X;"
  let after: number;
  if (unit.isProgram) {
    const prog = tokens.find(t => t.lower === 'program' || t.lower === 'library');
    after = prog ? tokens.find(t => t.kind === 'symbol' && t.text === ';' && t.line >= prog.line)?.line ?? 0 : 0;
  } else if (inImpl) {
    after = unit.implementationLine;
  } else {
    after = tokens.find(t => t.lower === 'interface')?.line ?? 0;
  }
  edit.insert(doc.uri, new vscode.Position(after + 1, 0), `\nuses\n  ${unitName};\n`);
  return edit;
}

/** Delphi's class completion: bodies for the methods of the class at the cursor that have none. */
export function classCompletionEdit(doc: vscode.TextDocument, line: number): { edit: vscode.WorkspaceEdit; count: number; at?: vscode.Position } | undefined {
  const unit = unitFor(doc);
  if (!unit || !analyzer) {
    return undefined;
  }
  const types = [...unit.interfaceDecls, ...unit.implementationDecls].filter(d =>
    (d.kind === 'class' || d.kind === 'record' || d.kind === 'object') && d.file === doc.uri.fsPath);
  const cls = types.find(d => d.line <= line && (d.endLine ?? d.line) >= line);
  if (!cls) {
    return undefined;
  }
  const missing = (cls.members ?? []).filter(m => m.kind === 'method' && !analyzer!.bodyOf(m) &&
    !(m.directives ?? []).some(x => x === 'abstract' || x === 'external'));
  const edit = new vscode.WorkspaceEdit();
  if (!missing.length) {
    return { edit, count: 0 };
  }
  const group = (m: Decl): string => {
    const parts: string[] = [];
    for (const p of m.params ?? []) {
      const prev = parts.length ? parts[parts.length - 1] : undefined;
      const tail = `: ${p.type}${p.defaultValue ? '' : ''}`;
      if (prev && prev.endsWith(tail) && prev.startsWith(p.modifier ? p.modifier + ' ' : '') && p.type && !p.defaultValue &&
          (p.modifier ? prev.startsWith(p.modifier + ' ') : !/^(const|var|out|constref) /.test(prev))) {
        parts[parts.length - 1] = prev.slice(0, -tail.length) + `, ${p.name}` + tail;
      } else {
        parts.push(`${p.modifier ? p.modifier + ' ' : ''}${p.name}${p.type ? ': ' + p.type : ''}`);
      }
    }
    return parts.length ? `(${parts.join('; ')})` : '';
  };
  const text = missing.map(m =>
    `${m.isClassMember ? 'class ' : ''}${m.routineKind} ${cls.name}.${m.name}${group(m)}${m.type ? ': ' + m.type : ''};\nbegin\n\nend;\n`,
  ).join('\n');
  // after the last body of this class, else before initialization / the final end.
  const own = unit.bodies.filter(b => b.className?.toLowerCase() === cls.name.toLowerCase() && !b.parent);
  let insertLine: number;
  let prefix = '\n';
  if (own.length) {
    insertLine = Math.max(...own.map(b => b.endLine)) + 1;
  } else {
    const tokens = unit.tokens.filter(t => !t.file || t.file === unit.file);
    const stop = tokens.find(t => (t.lower === 'initialization' || t.lower === 'finalization') && t.line > unit.implementationLine) ??
      [...tokens].reverse().find(t => t.lower === 'end');
    insertLine = stop ? stop.line : doc.lineCount;
    prefix = '';
  }
  const pos = new vscode.Position(Math.min(insertLine, doc.lineCount), 0);
  edit.insert(doc.uri, pos, prefix + text + (prefix ? '' : '\n'));
  return { edit, count: missing.length, at: pos };
}

async function completeClass(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    return;
  }
  const r = classCompletionEdit(editor.document, editor.selection.active.line);
  if (!r) {
    vscode.window.setStatusBarMessage('Pastel: put the cursor in a class declaration', 3000);
    return;
  }
  if (r.count === 0) {
    vscode.window.setStatusBarMessage('Pastel: every method of this class has a body', 3000);
    return;
  }
  await vscode.workspace.applyEdit(r.edit);
  if (r.at) {
    const p = new vscode.Position(r.at.line + 3, 2);
    editor.selection = new vscode.Selection(p, p);
    editor.revealRange(new vscode.Range(p, p), vscode.TextEditorRevealType.InCenterIfOutsideViewport);
  }
}

// ---------------- registration ----------------

export function registerIntellisense(context: vscode.ExtensionContext, index: PascalIndex,
  schema: Promise<{ frameworkDir?: string; fpcSourceDir?: string } | undefined>): void {
  const systemFile = path.join(context.extensionPath, 'pascal', 'system.pas');
  schema.then(s => {
    frameworkDir = s?.frameworkDir;
    analyzer = new Analyzer({
      readFile: f => {
        const open = vscode.workspace.textDocuments.find(d => d.uri.fsPath === f);
        if (open) {
          return open.getText();
        }
        try {
          return fs.readFileSync(f, 'utf8');
        } catch {
          return undefined;
        }
      },
      projectFiles: () => projectPascalFiles(index).concat(generatedFiles()),
      frameworkDir: s?.frameworkDir,
      fpcSourceDir: s?.fpcSourceDir,
      systemFile,
    });
  });

  context.subscriptions.push(
    compilerDiagnostics,
    vscode.languages.registerCompletionItemProvider(pascalSelector, {
      provideCompletionItems(doc, pos) {
        const unit = unitFor(doc);
        if (!unit || !analyzer || inCommentOrString(doc, pos)) {
          return undefined;
        }
        const r = analyzer.completionAt(unit, pos.line, pos.character);
        if (r.kind === 'none') {
          return undefined;
        }
        if (r.kind === 'uses') {
          return r.units!.map(u => {
            const item = new vscode.CompletionItem(u.name, vscode.CompletionItemKind.Module);
            item.detail = u.source === 'fpc' ? 'Free Pascal' : u.source === 'framework' ? 'Pastel' : 'this project';
            item.sortText = (u.source === 'project' ? '0' : u.source === 'framework' ? '1' : '2') + u.name.toLowerCase();
            return item;
          });
        }
        const items = r.decls.map((d, i) => {
          const item = new vscode.CompletionItem(d.name, KIND[d.kind] ?? vscode.CompletionItemKind.Text);
          item.detail = signature(d);
          if (d.doc) {
            item.documentation = new vscode.MarkdownString(d.doc);
          }
          // the closest scope first; in members, the type's own before the ancestors'
          item.sortText = String(i).padStart(5, '0');
          return item;
        });
        if (r.kind === 'scope') {
          for (const k of KEYWORDS) {
            const item = new vscode.CompletionItem(k, vscode.CompletionItemKind.Keyword);
            item.sortText = '9' + k;
            items.push(item);
          }
        }
        return new vscode.CompletionList(items, r.kind === 'scope');
      },
    }, '.'),

    vscode.languages.registerHoverProvider(pascalSelector, {
      provideHover(doc, pos) {
        if (inCommentOrString(doc, new vscode.Position(pos.line, pos.character + 1))) {
          return undefined;
        }
        const r = declAt(doc, pos);
        if (!r || !r.decls.length) {
          return undefined;
        }
        const md = docMarkdown(r.decls[0]);
        if (r.decls.length > 1) {
          md.appendMarkdown(`\n\n*+${r.decls.length - 1} overload(s)*`);
        }
        return new vscode.Hover(md, r.range);
      },
    }),

    vscode.languages.registerSignatureHelpProvider(pascalSelector, {
      provideSignatureHelp(doc, pos) {
        const unit = unitFor(doc);
        if (!unit || !analyzer) {
          return undefined;
        }
        const call = analyzer.callAt(unit, pos.line, pos.character);
        if (!call) {
          return undefined;
        }
        const help = new vscode.SignatureHelp();
        for (const d of call.decls) {
          const sig = new vscode.SignatureInformation(signature(d), d.doc ? new vscode.MarkdownString(d.doc) : undefined);
          sig.parameters = (d.params ?? []).map(p =>
            new vscode.ParameterInformation(`${p.modifier ? p.modifier + ' ' : ''}${p.name}${p.type ? ': ' + p.type : ''}${p.defaultValue ? ' = ' + p.defaultValue : ''}`));
          help.signatures.push(sig);
        }
        // the first overload with enough parameters
        const fit = call.decls.findIndex(d => (d.params ?? []).length > call.active);
        help.activeSignature = Math.max(0, fit);
        help.activeParameter = call.active;
        return help;
      },
    }, '(', ','),

    vscode.languages.registerReferenceProvider(pascalSelector, {
      provideReferences(doc, pos, ctx) {
        const r = declAt(doc, pos);
        if (!r?.decls.length || !analyzer) {
          return undefined;
        }
        const files = projectPascalFiles(index);
        return analyzer.references(r.decls[0], files)
          .filter(x => ctx.includeDeclaration || !(x.file === r.decls[0].file && x.line === r.decls[0].line && x.col === r.decls[0].col))
          .map(x => new vscode.Location(vscode.Uri.file(x.file), new vscode.Range(x.line, x.col, x.line, x.col + x.length)));
      },
    }),

    vscode.languages.registerRenameProvider(pascalSelector, {
      prepareRename(doc, pos) {
        const r = declAt(doc, pos);
        if (!r?.decls.length || !r.range) {
          throw new Error('Nothing to rename here.');
        }
        const d = r.decls[0];
        const own = projectPascalFiles(index).includes(d.file) || d.file === doc.uri.fsPath;
        if (!own || d.kind === 'unit') {
          throw new Error(`${d.name} is declared outside this project (${path.basename(d.file)}); it cannot be renamed here.`);
        }
        if (/[\\/]gen[\\/]/.test(d.file)) {
          throw new Error(`${d.name} comes from a .pform file: rename it in the form designer or the .pform file.`);
        }
        return r.range;
      },
      provideRenameEdits(doc, pos, newName) {
        if (!/^[A-Za-z_]\w*$/.test(newName)) {
          throw new Error(`"${newName}" is not a Pascal name.`);
        }
        const r = declAt(doc, pos);
        if (!r?.decls.length || !analyzer) {
          return undefined;
        }
        const edit = new vscode.WorkspaceEdit();
        for (const x of analyzer.references(r.decls[0], projectPascalFiles(index))) {
          edit.replace(vscode.Uri.file(x.file), new vscode.Range(x.line, x.col, x.line, x.col + x.length), newName);
        }
        return edit;
      },
    }),

    vscode.languages.registerCodeActionsProvider(pascalSelector, {
      provideCodeActions(doc, range, ctx) {
        const out: vscode.CodeAction[] = [];
        const unit = unitFor(doc);
        if (!unit) {
          return out;
        }
        for (const diag of ctx.diagnostics) {
          const m = /Identifier not found "([\w.]+)"/.exec(diag.message);
          if (!m) {
            continue;
          }
          for (const u of unitsDeclaring(m[1], unit.name).slice(0, 4)) {
            const a = new vscode.CodeAction(`Add "${u}" to uses`, vscode.CodeActionKind.QuickFix);
            a.edit = addUnitEdit(doc, unit, u, diag.range.start.line);
            a.diagnostics = [diag];
            a.isPreferred = true;
            out.push(a);
          }
        }
        const cc = classCompletionEdit(doc, range.start.line);
        if (cc && cc.count > 0) {
          const a = new vscode.CodeAction(`Create ${cc.count} method bod${cc.count === 1 ? 'y' : 'ies'} (Ctrl+Shift+C)`,
            vscode.CodeActionKind.QuickFix);
          a.command = { command: 'pastel.completeClass', title: 'Complete class' };
          out.push(a);
        }
        return out;
      },
    }, { providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] }),

    vscode.commands.registerCommand('pastel.completeClass', completeClass),
    vscode.workspace.onDidChangeTextDocument(e => {
      if ((e.contentChanges ?? []).length) {
        schedule(e.document, 900);
      }
      analyzer?.invalidate();
    }),
    vscode.workspace.onDidSaveTextDocument(doc => schedule(doc, 0)),
    vscode.workspace.onDidOpenTextDocument(doc => schedule(doc, 200)),
    vscode.workspace.onDidCloseTextDocument(doc => {
      analyzer?.setText(doc.uri.fsPath, undefined);
      if (doc.isDirty === false) {
        compilerDiagnostics.delete(doc.uri);
      }
    }),
  );
}

/** Go to definition with the analyzer; undefined to let the simpler lookup try. */
export function analyzerDefinition(doc: vscode.TextDocument, pos: vscode.Position): vscode.Location[] | undefined {
  const r = declAt(doc, pos);
  if (!r?.decls.length || !analyzer) {
    return undefined;
  }
  const d = r.decls[0];
  if (d.kind === 'unit') {
    const p = new vscode.Position(0, 0);
    return [new vscode.Location(vscode.Uri.file(d.file), new vscode.Range(p, p))];
  }
  // on a method declaration: its body (Delphi); on a body's name: the declaration
  if (d.line === pos.line && d.file === doc.uri.fsPath && r.range?.start.character === d.col) {
    const body = analyzer.bodyOf(d);
    if (body) {
      const p = new vscode.Position(body.nameLine, body.nameCol);
      return [new vscode.Location(vscode.Uri.file(d.file), new vscode.Range(p, p))];
    }
  }
  void frameworkDir;
  return r.decls.slice(0, 10).map(location);
}
