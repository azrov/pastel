// Code intelligence for Pascal: finds units (project, Pastel framework,
// Free Pascal sources), resolves names in their scope, the types of
// expressions like `Edit.Font.`, and answers completion, hover, signature
// help, definition and references. No VS Code dependency.
import * as fs from 'fs';
import * as path from 'path';
import { defaultDefines, lex, Lexed, Token } from './lexer';
import { Body, Decl, ParsedUnit, parseUnit } from './parser';

export interface AnalyzerHost {
  readFile(file: string): string | undefined;
  /** Pascal files of the project (and of generated code), absolute paths */
  projectFiles(): string[];
  frameworkDir?: string;
  fpcSourceDir?: string;
  systemFile: string;
  platform?: string;
}

const TYPE_KINDS = new Set(['class', 'record', 'interface', 'object', 'enum', 'type']);
const STRING_TYPES = new Set(['string', 'ansistring', 'unicodestring', 'widestring', 'shortstring', 'rawbytestring',
  'utf8string']);

export interface TypeRef {
  decl?: Decl;            // class, record, interface, enum...
  text: string;           // as written
  isStatic?: boolean;     // the type itself (TFoo.), not a value of it
  element?: string;       // arrays: the element type
  pointerTo?: string;
  isString?: boolean;
  unit?: ParsedUnit;      // where the text is to be resolved
}

export interface Segment {
  name: string;
  lower: string;
  call: boolean;
  index: boolean;
  deref: boolean;
  token: Token;
}

export interface Context {
  unit: ParsedUnit;
  inImplementation: boolean;
  body?: Body;
  line?: number;
  col?: number;
}

function key(d: Decl): string {
  return `${d.file}|${d.line}|${d.col}|${d.name.toLowerCase()}`;
}

export class Analyzer {
  private readonly parsed = new Map<string, { text: string; unit: ParsedUnit }>();
  private readonly unitOf = new WeakMap<Decl, ParsedUnit>();
  private fpcIndex: Map<string, string> | undefined;
  private projectIndex: Map<string, string> | undefined;
  private readonly overlays = new Map<string, string>();

  constructor(private readonly host: AnalyzerHost) {}

  /** Unsaved text of an open document (undefined: read from disk again). */
  setText(file: string, text: string | undefined): void {
    if (text === undefined) {
      this.overlays.delete(file);
    } else {
      this.overlays.set(file, text);
    }
    this.projectIndex = undefined;
  }

  invalidate(file?: string): void {
    if (file) {
      this.parsed.delete(file);
    }
    this.projectIndex = undefined;
  }

  // ---------------- files and units ----------------

  private read(file: string): string | undefined {
    return this.overlays.get(file) ?? this.host.readFile(file);
  }

  private includeDirs(file: string): string[] {
    const dirs = [path.dirname(file)];
    const fpc = this.host.fpcSourceDir;
    if (fpc && file.startsWith(fpc)) {
      const rtl = path.join(fpc, 'rtl');
      const plat = this.platformDirs();
      for (const d of [...plat, 'objpas/sysutils', 'objpas/classes', 'objpas', 'inc', 'x86_64', 'linux/x86_64']) {
        dirs.push(path.join(rtl, d));
      }
      // packages: the src folder and its platform folders
      const m = /^(.*[\\/]packages[\\/][^\\/]+[\\/]src)/.exec(file);
      if (m) {
        for (const d of ['', 'unix', 'linux', 'win', 'inc']) {
          dirs.push(path.join(m[1], d));
        }
      }
    }
    return dirs;
  }

  private platformDirs(): string[] {
    const p = this.host.platform ?? process.platform;
    return p === 'win32' ? ['win', 'win64', 'win32'] : p === 'darwin' ? ['darwin', 'bsd', 'unix'] : ['linux', 'unix'];
  }

  private lexWithIncludes(file: string, text: string, defines: Set<string>, depth = 0): Lexed {
    const lexed = lex(text, defines);
    if (depth > 6 || lexed.includes.length === 0) {
      return lexed;
    }
    for (let k = lexed.includes.length - 1; k >= 0; k--) {
      const inc = lexed.includes[k];
      let found: string | undefined;
      const names = /\.\w+$/.test(inc.name) ? [inc.name] : [inc.name + '.inc', inc.name + '.pp', inc.name];
      for (const d of this.includeDirs(file)) {
        for (const n of names) {
          const f = path.join(d, n);
          if (fs.existsSync(f)) {
            found = f;
            break;
          }
          // case-insensitive on Linux
          const lower = path.join(d, n.toLowerCase());
          if (fs.existsSync(lower)) {
            found = lower;
            break;
          }
        }
        if (found) {
          break;
        }
      }
      const big = found ? fs.statSync(found).size > 1_000_000 : false;     // data tables
      const incText = found && !big ? this.read(found) : undefined;
      if (!found || incText === undefined) {
        continue;
      }
      const sub = this.lexWithIncludes(found, incText, defines, depth + 1);
      for (const t of sub.tokens) {
        t.file ??= found;
      }
      for (const c of sub.comments) {
        c.file ??= found;
      }
      // concat, not splice(...): include files with big tables have more tokens than the stack has room for arguments
      lexed.tokens = lexed.tokens.slice(0, inc.index).concat(sub.tokens, lexed.tokens.slice(inc.index));
      lexed.comments = lexed.comments.concat(sub.comments);
    }
    return lexed;
  }

  /** The parsed unit of a file (cached until its text changes). */
  unitForFile(file: string): ParsedUnit | undefined {
    const text = this.read(file);
    if (text === undefined) {
      return undefined;
    }
    const cached = this.parsed.get(file);
    if (cached && cached.text === text) {
      return cached.unit;
    }
    const unit = parseUnit(this.lexWithIncludes(file, text, defaultDefines(this.host.platform)), file, text);
    this.parsed.set(file, { text, unit });
    const mark = (decls: Decl[] | undefined): void => {
      for (const d of decls ?? []) {
        this.unitOf.set(d, unit);
        mark(d.members);
      }
    };
    mark(unit.interfaceDecls);
    mark(unit.implementationDecls);
    for (const b of unit.bodies) {
      this.unitOf.set(b.decl, unit);
      mark(b.locals);
    }
    return unit;
  }

  private projectUnits(): Map<string, string> {
    if (!this.projectIndex) {
      const m = new Map<string, string>();
      const files = [...this.host.projectFiles()];
      if (this.host.frameworkDir && fs.existsSync(this.host.frameworkDir)) {
        for (const n of fs.readdirSync(this.host.frameworkDir)) {
          if (/\.(pas|pp)$/i.test(n)) {
            files.push(path.join(this.host.frameworkDir, n));
          }
        }
      }
      for (const f of files) {
        const text = this.read(f);
        const name = text ? /^\s*(?:\{[^}]*\}|\(\*[\s\S]*?\*\)|\/\/[^\n]*|\s)*unit\s+([\w.]+)/i.exec(text)?.[1] : undefined;
        if (name && !m.has(name.toLowerCase())) {
          m.set(name.toLowerCase(), f);
        }
      }
      this.projectIndex = m;
    }
    return this.projectIndex;
  }

  private fpcUnits(): Map<string, string> {
    if (this.fpcIndex) {
      return this.fpcIndex;
    }
    const m = new Map<string, string>();
    const fpc = this.host.fpcSourceDir;
    if (fpc && fs.existsSync(fpc)) {
      const add = (dir: string, depth: number): void => {
        if (!fs.existsSync(dir)) {
          return;
        }
        for (const n of fs.readdirSync(dir)) {
          const f = path.join(dir, n);
          if (/^(tests?|examples?|demo|fpmake.*|utils?|docs?)$/i.test(n)) {
            continue;
          }
          let st: fs.Stats;
          try {
            st = fs.statSync(f);
          } catch {
            continue;
          }
          if (st.isDirectory()) {
            if (depth > 0) {
              add(f, depth - 1);
            }
          } else if (/\.(pp|pas)$/i.test(n)) {
            const u = n.replace(/\.(pp|pas)$/i, '').toLowerCase();
            if (!m.has(u)) {
              m.set(u, f);
            }
          }
        }
      };
      for (const d of this.platformDirs()) {
        add(path.join(fpc, 'rtl', d), 0);
      }
      add(path.join(fpc, 'rtl', 'objpas'), 1);
      add(path.join(fpc, 'rtl', 'inc'), 0);
      const pk = path.join(fpc, 'packages');
      if (fs.existsSync(pk)) {
        for (const p of fs.readdirSync(pk)) {
          add(path.join(pk, p, 'src'), 2);
        }
      }
    }
    m.delete('system');
    this.fpcIndex = m;
    return m;
  }

  /** All unit names that can be used (for completion in uses). */
  unitNames(): { name: string; file: string; source: 'project' | 'framework' | 'fpc' }[] {
    const out: { name: string; file: string; source: 'project' | 'framework' | 'fpc' }[] = [];
    for (const [, f] of this.projectUnits()) {
      const u = this.unitForFile(f);
      if (u?.name) {
        out.push({ name: u.name, file: f, source: this.host.frameworkDir && f.startsWith(this.host.frameworkDir) ? 'framework' : 'project' });
      }
    }
    for (const [n, f] of this.fpcUnits()) {
      if (!this.projectUnits().has(n)) {
        const pretty = /([^\\/]+)\.(pp|pas)$/i.exec(f)?.[1] ?? n;
        out.push({ name: pretty, file: f, source: 'fpc' });
      }
    }
    return out;
  }

  unitByName(name: string): ParsedUnit | undefined {
    const n = name.toLowerCase();
    if (n === 'system') {
      return this.unitForFile(this.host.systemFile);
    }
    const f = this.projectUnits().get(n) ?? this.fpcUnits().get(n);
    return f ? this.unitForFile(f) : undefined;
  }

  unitOfDecl(d: Decl): ParsedUnit | undefined {
    return this.unitOf.get(d);
  }

  isProjectFile(file: string): boolean {
    return this.host.projectFiles().includes(file);
  }

  // ---------------- scopes ----------------

  contextAt(unit: ParsedUnit, line: number, col: number): Context {
    let body: Body | undefined;
    for (const b of unit.bodies) {
      const after = line > b.startLine || (line === b.startLine);
      const before = line < b.endLine || (line === b.endLine && col <= b.endCol);
      if (after && before && (!body || b.startLine >= body.startLine)) {
        body = b;
      }
    }
    const inImpl = unit.isProgram || (unit.implementationLine >= 0 && line > unit.implementationLine);
    return { unit, inImplementation: inImpl, body, line, col };
  }

  private unitLevel(u: ParsedUnit, withImplementation: boolean): Decl[] {
    const decls = withImplementation ? [...u.interfaceDecls, ...u.implementationDecls] : u.interfaceDecls;
    const out: Decl[] = [];
    for (const d of decls) {
      out.push(d);
      if (d.kind === 'enum') {
        out.push(...(d.members ?? []));
      }
    }
    return out;
  }

  private usedUnits(ctx: Context): ParsedUnit[] {
    const uses = ctx.inImplementation ? [...ctx.unit.interfaceUses, ...ctx.unit.implementationUses] : ctx.unit.interfaceUses;
    const out: ParsedUnit[] = [];
    for (let k = uses.length - 1; k >= 0; k--) {
      const u = this.unitByName(uses[k].name);
      if (u) {
        out.push(u);
      }
    }
    const sys = this.unitByName('system');
    if (sys && sys !== ctx.unit) {
      out.push(sys);
    }
    return out;
  }

  /** The class a method body belongs to, with its unit. */
  private bodyClass(ctx: Context, body: Body): Decl | undefined {
    if (!body.className) {
      return undefined;
    }
    return this.resolveTypeName(body.className, ctx.unit, true);
  }

  /** Every name visible at a point, closest first (for completion). */
  visibleNames(ctx: Context): Decl[] {
    const out: Decl[] = [];
    const seen = new Set<string>();
    const add = (ds: Decl[]): void => {
      for (const d of ds) {
        const n = d.name.toLowerCase();
        if (!seen.has(n)) {
          seen.add(n);
          out.push(d);
        }
      }
    };
    for (let b = ctx.body; b; b = b.parent) {
      add(b.locals);
      const cls = this.bodyClass(ctx, b);
      if (cls) {
        add(this.membersOf(cls, ctx.unit));
      }
    }
    add(this.unitLevel(ctx.unit, ctx.inImplementation));
    for (const u of this.usedUnits(ctx)) {
      add(this.unitLevel(u, false));
    }
    return out;
  }

  /** Declarations a name refers to at a point (several for overloads). */
  lookup(name: string, ctx: Context): Decl[] {
    const n = name.toLowerCase();
    const match = (ds: Decl[]): Decl[] => ds.filter(d => d.name.toLowerCase() === n);
    for (let b = ctx.body; b; b = b.parent) {
      const local = match(b.locals);
      if (local.length) {
        return local;
      }
      const handlerVar = b === ctx.body ? this.exceptionVar(ctx, b, n) : undefined;
      if (handlerVar) {
        return [handlerVar];
      }
      const cls = this.bodyClass(ctx, b);
      if (cls) {
        if (n === 'self') {
          return [{ ...cls, kind: 'var', type: cls.name, name: 'Self', doc: `The ${cls.name} object the method runs for.` } as Decl];
        }
        const m = match(this.membersOf(cls, ctx.unit));
        if (m.length) {
          return m;
        }
      }
    }
    const own = match(this.unitLevel(ctx.unit, ctx.inImplementation));
    if (own.length) {
      return this.preferFull(own);
    }
    for (const u of this.usedUnits(ctx)) {
      const m = match(this.unitLevel(u, false));
      if (m.length) {
        return this.preferFull(m);
      }
    }
    return [];
  }

  // "on E: EFoo do" in the body before the position declares E
  private exceptionVar(ctx: Context, b: Body, n: string): Decl | undefined {
    const toks = ctx.unit.tokens;
    let found: Decl | undefined;
    for (let k = 0; k < toks.length - 3; k++) {
      const t = toks[k];
      if (t.file || t.line < b.beginLine) {
        continue;
      }
      if (t.line > b.endLine || (ctx.line !== undefined && (t.line > ctx.line || (t.line === ctx.line && t.col > (ctx.col ?? 0))))) {
        break;
      }
      if (t.lower === 'on' && toks[k + 1].lower === n && toks[k + 2].text === ':' && toks[k + 3].kind === 'ident') {
        const v = toks[k + 1];
        let type = toks[k + 3].text;
        for (let j = k + 4; toks[j]?.text === '.' && toks[j + 1]?.kind === 'ident'; j += 2) {
          type += '.' + toks[j + 1].text;
        }
        found = { name: v.text, kind: 'var', line: v.line, col: v.col, file: ctx.unit.file, type, doc: 'the exception being handled' };
        this.unitOf.set(found, ctx.unit);
      }
    }
    return found;
  }

  // a forward class declaration and the full one: the full one
  private preferFull(ds: Decl[]): Decl[] {
    const full = ds.filter(d => !d.forward);
    return full.length ? full : ds;
  }

  // ---------------- types ----------------

  private baseName(text: string): string {
    return text.replace(/^specialize\s+/i, '').replace(/<.*$/, '').trim();
  }

  /** A type by name as seen from a unit: the class/record/enum..., following aliases. */
  resolveTypeName(text: string, from: ParsedUnit | undefined, inImpl = true, container?: Decl, depth = 0): Decl | undefined {
    if (!from || depth > 10) {
      return undefined;
    }
    const name = this.baseName(text);
    if (!/^[\w.]+$/.test(name)) {
      return undefined;
    }
    // nested types of the container (and its ancestors)
    if (container?.members) {
      const nested = container.members.find(m => m.name.toLowerCase() === name.toLowerCase() && TYPE_KINDS.has(m.kind));
      if (nested) {
        return this.followAlias(nested, from, depth);
      }
    }
    // Unit.Type
    if (name.includes('.')) {
      const dot = name.lastIndexOf('.');
      const u = this.unitByName(name.slice(0, dot));
      if (u) {
        const d = this.unitLevel(u, false).find(x => x.name.toLowerCase() === name.slice(dot + 1).toLowerCase() && TYPE_KINDS.has(x.kind));
        return d ? this.followAlias(d, u, depth) : undefined;
      }
    }
    const ctx: Context = { unit: from, inImplementation: inImpl };
    const found = this.lookup(name, ctx).filter(d => TYPE_KINDS.has(d.kind));
    if (!found.length) {
      return undefined;
    }
    return this.followAlias(found[0], this.unitOf.get(found[0]) ?? from, depth);
  }

  private followAlias(d: Decl, unit: ParsedUnit, depth: number): Decl {
    if (d.kind === 'type' && d.aliasOf && /^[\w.]+(<.*>)?$/.test(d.aliasOf.replace(/^specialize\s+/i, '')) &&
        this.baseName(d.aliasOf).toLowerCase() !== d.name.toLowerCase()) {
      const target = this.resolveTypeName(d.aliasOf, unit, true, undefined, depth + 1);
      if (target) {
        return target;
      }
    }
    if (d.forward) {
      const full = this.unitLevel(unit, true).find(x => x.name.toLowerCase() === d.name.toLowerCase() && !x.forward);
      if (full) {
        return full;
      }
    }
    return d;
  }

  /** Members of a type with those of its ancestors, the type's own first. */
  membersOf(type: Decl, from?: ParsedUnit, seen = new Set<string>()): Decl[] {
    if (seen.has(key(type)) || seen.size > 30) {
      return [];
    }
    seen.add(key(type));
    const out = [...(type.members ?? [])];
    const unit = this.unitOf.get(type) ?? from;
    let ancestorName = type.ancestor;
    if (!ancestorName && type.kind === 'class' && type.name.toLowerCase() !== 'tobject') {
      ancestorName = 'TObject';
    }
    if (!ancestorName && type.kind === 'interface' && !/^iinterface|iunknown$/i.test(type.name)) {
      ancestorName = 'IInterface';
    }
    if (type.aliasOf?.startsWith('helper for ')) {
      ancestorName = undefined;
    }
    if (ancestorName) {
      const anc = this.resolveTypeName(ancestorName, unit, true);
      if (anc) {
        for (const m of this.membersOf(anc, unit, seen)) {
          // a property redeclared to change visibility keeps the ancestor's type
          const own = out.find(o => o.name.toLowerCase() === m.name.toLowerCase());
          if (own && own.kind === 'property' && !own.type && m.type) {
            own.type = m.type;
            own.doc ??= m.doc;
          }
          if (!own || (own.kind === 'method' && m.kind === 'method' && (own.directives ?? []).includes('overload'))) {
            out.push(m);
          }
        }
      }
    }
    return out;
  }

  typeFromText(text: string | undefined, unit: ParsedUnit | undefined, container?: Decl, depth = 0): TypeRef | undefined {
    if (!text || depth > 8) {
      return undefined;
    }
    const t = text.trim();
    const lower = t.toLowerCase();
    const arr = /^(?:packed\s+)?array\s*(?:\[[^\]]*\])?\s*of\s+(.+)$/i.exec(t);
    if (arr) {
      return { text: t, element: arr[1], unit };
    }
    if (t.startsWith('^')) {
      return { text: t, pointerTo: t.slice(1), unit };
    }
    if (STRING_TYPES.has(lower) || /^string\[/.test(lower)) {
      return { text: t, isString: true, unit };
    }
    const decl = this.resolveTypeName(t, unit, true, container);
    if (decl) {
      if (decl.kind === 'type' && decl.aliasOf && this.baseName(decl.aliasOf).toLowerCase() !== decl.name.toLowerCase()) {
        const inner = this.typeFromText(decl.aliasOf, this.unitOf.get(decl) ?? unit, undefined, depth + 1);
        if (inner && (inner.element || inner.pointerTo || inner.isString)) {
          return inner;
        }
        if (STRING_TYPES.has(decl.aliasOf.toLowerCase()) || STRING_TYPES.has(decl.name.toLowerCase())) {
          return { text: t, isString: true, unit, decl };
        }
      }
      return { text: t, decl, unit: this.unitOf.get(decl) ?? unit };
    }
    return { text: t, unit };
  }

  /** The type of what a declaration names, as a value (or the type itself). */
  typeOfDecl(d: Decl): TypeRef | undefined {
    const unit = this.unitOf.get(d);
    switch (d.kind) {
      case 'class':
      case 'record':
      case 'interface':
      case 'object':
      case 'enum':
      case 'type': {
        const resolved = unit ? this.followAlias(d, unit, 0) : d;
        return { text: d.name, decl: resolved, isStatic: true, unit };
      }
      case 'method':
      case 'routine':
        if (d.routineKind === 'constructor' && d.container) {
          return { text: d.container.name, decl: d.container, unit };
        }
        return this.typeFromText(d.type, unit, d.container);
      case 'unit':
        return undefined;
      default:
        if (d.members && d.type === 'record') {      // var X: record ... end;
          return { text: 'record', decl: { ...d, kind: 'record' }, unit };
        }
        return this.typeFromText(d.type, unit, d.container);
    }
  }

  private applyAccess(t: TypeRef | undefined, seg: Segment): TypeRef | undefined {
    let cur = t;
    if (cur && seg.index) {
      if (cur.element) {
        cur = this.typeFromText(cur.element, cur.unit);
      } else if (cur.isString) {
        cur = { text: 'Char' };
      } else if (cur.decl) {
        const def = this.membersOf(cur.decl, cur.unit).find(m => m.kind === 'property' && m.isDefault);
        cur = def ? this.typeOfDecl(def) : undefined;
      }
    }
    if (cur && seg.deref && cur.pointerTo) {
      cur = this.typeFromText(cur.pointerTo, cur.unit);
    }
    return cur;
  }

  // ---------------- expressions ----------------

  /** The dotted expression that ends at token `end` (inclusive): A.B(1).C[2] */
  chainAt(tokens: Token[], end: number): Segment[] | undefined {
    const segs: Segment[] = [];
    let k = end;
    for (;;) {
      let call = false;
      let index = false;
      let deref = false;
      // postfix parts, read backwards: ^, (...), [...]
      for (;;) {
        const t = tokens[k];
        if (!t) {
          return segs.length ? segs : undefined;
        }
        if (t.kind === 'symbol' && t.text === '^') {
          deref = true;
          k--;
          continue;
        }
        if (t.kind === 'symbol' && (t.text === ')' || t.text === ']')) {
          const open = t.text === ')' ? '(' : '[';
          let depth = 0;
          while (k >= 0) {
            const x = tokens[k];
            if (x.kind === 'symbol' && (x.text === ')' || x.text === ']')) {
              depth++;
            } else if (x.kind === 'symbol' && (x.text === '(' || x.text === '[')) {
              depth--;
              if (depth === 0) {
                break;
              }
            }
            k--;
          }
          if (open === '(') {
            call = true;
          } else {
            index = true;
          }
          k--;
          continue;
        }
        break;
      }
      const t = tokens[k];
      if (!t || t.kind !== 'ident') {
        return segs.length ? segs : undefined;
      }
      segs.unshift({ name: t.text, lower: t.lower, call, index, deref, token: t });
      if (tokens[k - 1]?.kind === 'symbol' && tokens[k - 1].text === '.') {
        k -= 2;
        continue;
      }
      if (tokens[k - 1]?.lower === 'inherited') {
        segs[0] = { ...segs[0], name: 'inherited ' + segs[0].name };
      }
      return segs;
    }
  }

  /** What a chain refers to: the declarations of its last part and the type of it. */
  resolveChain(segs: Segment[], ctx: Context): { decls: Decl[]; type?: TypeRef } {
    let decls: Decl[] = [];
    let type: TypeRef | undefined;
    let start = 0;
    // a unit name (also dotted, like Pastel.UI) in front
    for (let k = segs.length - 1; k >= 1; k--) {
      const unitName = segs.slice(0, k).map(s => s.name).join('.');
      const u = this.unitByName(unitName);
      const used = [...ctx.unit.interfaceUses, ...ctx.unit.implementationUses].some(x => x.name.toLowerCase() === unitName.toLowerCase());
      if (u && (used || unitName.toLowerCase() === 'system')) {
        const nextName = segs[k].lower;
        decls = this.unitLevel(u, false).filter(d => d.name.toLowerCase() === nextName);
        type = decls[0] ? this.applyAccess(this.typeOfDecl(decls[0]), segs[k]) : undefined;
        start = k + 1;
        if (!decls.length) {
          return { decls: [] };
        }
        break;
      }
    }
    for (let i = start; i < segs.length; i++) {
      const seg = segs[i];
      if (i === 0) {
        if (seg.name.startsWith('inherited ')) {
          const cls = ctx.body ? this.bodyClass(ctx, ctx.body) : undefined;
          const ancName = cls?.ancestor ?? (cls && cls.kind === 'class' && cls.name.toLowerCase() !== 'tobject' ? 'TObject' : undefined);
          const anc = ancName ? this.resolveTypeName(ancName, (cls && this.unitOf.get(cls)) ?? ctx.unit) : undefined;
          const n = seg.lower.replace(/^inherited /, '');
          decls = anc ? this.membersOf(anc, ctx.unit).filter(m => m.name.toLowerCase() === n) : [];
        } else {
          decls = this.lookup(seg.name, ctx);
          if (!decls.length) {
            const u = this.unitByName(seg.name);
            if (u && segs.length === 1) {
              return { decls: [{ name: u.name, kind: 'unit', line: 0, col: 0, file: u.file }] };
            }
          }
        }
      } else {
        if (type && (!type.decl || (type.decl.kind === 'type' && !type.decl.members))) {
          const helper = this.helperFor(type, ctx);
          type = helper ? { ...type, decl: helper, isStatic: false } : type;
        }
        if (!type?.decl) {
          return { decls: [] };
        }
        const members = this.membersOf(type.decl, ctx.unit);
        decls = members.filter(m => m.name.toLowerCase() === seg.lower);
      }
      if (!decls.length) {
        return { decls: [] };
      }
      type = this.applyAccess(this.typeOfDecl(decls[0]), seg);
    }
    return { decls, type };
  }

  /** A type helper (TStringHelper for strings...) visible at ctx for a type without members of its own. */
  helperFor(t: TypeRef, ctx: Context): Decl | undefined {
    const names = new Set<string>();
    if (t.isString) {
      STRING_TYPES.forEach(n => names.add(n));
    }
    names.add(this.baseName(t.text).toLowerCase());
    if (t.decl) {
      names.add(t.decl.name.toLowerCase());
    }
    const units = [ctx.unit, ...this.usedUnits(ctx)];
    for (const u of units) {
      for (const d of this.unitLevel(u, u === ctx.unit && ctx.inImplementation)) {
        const target = /^helper for (.+)$/i.exec(d.aliasOf ?? '')?.[1]?.toLowerCase();
        if (target && names.has(target)) {
          return d;
        }
      }
    }
    return undefined;
  }

  /** Members that make sense after "expr." */
  completeMembers(t: TypeRef, ctx: Context): Decl[] {
    if (!t.decl || (t.decl.kind === 'type' && !t.decl.members)) {
      const helper = this.helperFor(t, ctx);
      if (!helper) {
        return [];
      }
      t = { ...t, decl: helper, isStatic: false };
    }
    const decl = t.decl!;
    const sameUnit = this.unitOf.get(decl) === ctx.unit;
    const seen = new Set<string>();
    const out: Decl[] = [];
    for (const m of this.membersOf(decl, ctx.unit)) {
      const n = m.name.toLowerCase();
      if (seen.has(n)) {
        continue;
      }
      if (!sameUnit && m.visibility && /private|strict/.test(m.visibility)) {
        continue;
      }
      if (t.isStatic && decl.kind !== 'enum' && m.kind === 'field' && !m.isClassMember) {
        continue;     // TFoo.Field makes no sense; TFoo.Create does
      }
      if (TYPE_KINDS.has(m.kind) && !t.isStatic) {
        continue;
      }
      seen.add(n);
      out.push(m);
    }
    return out;
  }

  // ---------------- what is at a position ----------------

  tokenIndexAt(tokens: Token[], line: number, col: number, file?: string): number {
    for (let k = 0; k < tokens.length; k++) {
      const t = tokens[k];
      if (t.file && t.file !== file) {
        continue;
      }
      if (t.line === line && col >= t.col && col <= t.col + t.text.length) {
        return k;
      }
      if (t.line > line) {
        break;
      }
    }
    return -1;
  }

  /** The declarations an identifier token refers to. */
  resolveToken(unit: ParsedUnit, k: number): Decl[] {
    const tokens = unit.tokens;
    const t = tokens[k];
    if (!t || t.kind !== 'ident') {
      return [];
    }
    const ctx = this.contextAt(unit, t.line, t.col);
    // the name in a method body header: procedure TFoo.Bar(...)
    for (const b of unit.bodies) {
      if (b.className && t.line === b.nameLine) {
        if (t.col === b.nameCol) {
          const cls = this.resolveTypeName(b.className, unit, true);
          const ms = cls ? (cls.members ?? []).filter(m => m.name.toLowerCase() === t.lower) : [];
          if (ms.length) {
            return ms;
          }
        }
        if (t.col === b.classNameCol) {
          const cls = this.resolveTypeName(b.className, unit, true);
          return cls ? [cls] : [];
        }
      }
    }
    // a declaration itself
    const own = this.declarationAt(unit, t);
    if (own) {
      return [own];
    }
    // in uses: the unit
    for (const u of [...unit.interfaceUses, ...unit.implementationUses]) {
      if (u.line === t.line && t.col >= u.col && t.col <= u.col + u.name.length) {
        const pu = this.unitByName(u.name);
        return pu ? [{ name: pu.name, kind: 'unit', line: 0, col: 0, file: pu.file }] : [];
      }
    }
    // type names in declarations: resolve as type
    const segs = this.chainAt(tokens, k);
    if (!segs) {
      return [];
    }
    return this.resolveChain(segs, ctx).decls;
  }

  private declarationAt(unit: ParsedUnit, t: Token): Decl | undefined {
    const file = t.file ?? unit.file;
    let hit: Decl | undefined;
    const at = (d: { line?: number; col?: number }): boolean => d.line === t.line && d.col === t.col;
    const visit = (ds: Decl[] | undefined): void => {
      for (const d of ds ?? []) {
        if (hit) {
          return;
        }
        if (at(d) && d.file === file && d.kind !== 'result') {
          hit = d;
          return;
        }
        // a parameter in a declaration (not a body): its own little declaration
        for (const prm of d.params ?? []) {
          if (at(prm) && d.file === file) {
            hit = { name: prm.name, kind: 'param', line: t.line, col: t.col, file, type: prm.type,
              doc: prm.modifier ? `${prm.modifier} parameter` : undefined };
            this.unitOf.set(hit, unit);
            return;
          }
        }
        visit(d.members);
      }
    };
    visit(unit.interfaceDecls);
    visit(unit.implementationDecls);
    for (const b of unit.bodies) {
      if (!hit) {
        visit(b.locals.filter(l => l.kind !== 'result'));
      }
    }
    return hit;
  }

  /** Index of the last token that starts before (line, col) in the main file. */
  private tokenBefore(tokens: Token[], line: number, col: number, file: string): number {
    let k = -1;
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      if (t.file && t.file !== file) {
        continue;
      }
      if (t.line > line || (t.line === line && t.col >= col)) {
        break;
      }
      k = i;
    }
    return k;
  }

  /** What to offer at a cursor position. */
  completionAt(unit: ParsedUnit, line: number, col: number):
    { kind: 'member' | 'scope' | 'uses' | 'none'; decls: Decl[]; prefix: string; units?: ReturnType<Analyzer['unitNames']> } {
    const tokens = unit.tokens;
    let k = this.tokenBefore(tokens, line, col, unit.file);
    let prefix = '';
    const t = tokens[k];
    if (t && t.kind === 'ident' && t.line === line && t.col + t.text.length >= col) {
      prefix = t.text.slice(0, col - t.col);
      k--;
    } else if (t && (t.kind === 'number' || t.kind === 'string') && t.line === line && t.col + t.text.length >= col) {
      return { kind: 'none', decls: [], prefix: '' };
    }
    // uses clause?
    for (let i = k; i >= 0; i--) {
      const x = tokens[i];
      if (x.kind === 'symbol' && x.text === ';') {
        break;
      }
      if (x.lower === 'uses') {
        return { kind: 'uses', decls: [], prefix, units: this.unitNames() };
      }
      if (x.kind !== 'ident' && !(x.kind === 'symbol' && (x.text === ',' || x.text === '.'))) {
        break;
      }
    }
    const ctx = this.contextAt(unit, line, col);
    const prev = tokens[k];
    if (prev && prev.kind === 'symbol' && prev.text === '.') {
      const segs = this.chainAt(tokens, k - 1);
      if (!segs) {
        return { kind: 'none', decls: [], prefix };
      }
      // Unit. → what the unit declares
      const unitName = segs.map(x => x.name).join('.');
      const used = [...unit.interfaceUses, ...unit.implementationUses].some(u => u.name.toLowerCase() === unitName.toLowerCase());
      if (used) {
        const u = this.unitByName(unitName);
        if (u) {
          return { kind: 'member', decls: this.unitLevel(u, false), prefix };
        }
      }
      const r = this.resolveChain(segs, ctx);
      return { kind: 'member', decls: r.type ? this.completeMembers(r.type, ctx) : [], prefix };
    }
    return { kind: 'scope', decls: this.visibleNames(ctx), prefix };
  }

  /** The call the cursor is in: the routines it may be (overloads) and which parameter. */
  callAt(unit: ParsedUnit, line: number, col: number): { decls: Decl[]; active: number } | undefined {
    const tokens = unit.tokens;
    let k = this.tokenBefore(tokens, line, col, unit.file);
    let depth = 0;
    let commas = 0;
    for (; k >= 0; k--) {
      const t = tokens[k];
      if (t.kind !== 'symbol') {
        if (t.lower === 'begin' || t.lower === 'end' || t.lower === 'then' || t.lower === 'do') {
          return undefined;
        }
        continue;
      }
      if (t.text === ';') {
        return undefined;
      }
      if (t.text === ')' || t.text === ']') {
        depth++;
      } else if (t.text === '[') {
        if (depth === 0) {
          return undefined;
        }
        depth--;
      } else if (t.text === '(') {
        if (depth === 0) {
          break;
        }
        depth--;
      } else if (t.text === ',' && depth === 0) {
        commas++;
      }
    }
    if (k < 1 || tokens[k - 1].kind !== 'ident') {
      return undefined;
    }
    const segs = this.chainAt(tokens, k - 1);
    if (!segs) {
      return undefined;
    }
    const ctx = this.contextAt(unit, line, col);
    const r = this.resolveChain(segs, ctx);
    const all = this.overloadsOf(r.decls, segs, ctx);
    const routines = all.filter(d => d.kind === 'method' || d.kind === 'routine' || (d.kind === 'type' && d.routineKind));
    return routines.length ? { decls: routines, active: commas } : undefined;
  }

  // every overload of a routine, also from the ancestors
  private overloadsOf(found: Decl[], segs: Segment[], ctx: Context): Decl[] {
    if (!found.length) {
      return found;
    }
    const first = found[0];
    if (first.container) {
      const owner = this.membersOf(first.container, ctx.unit);
      const same = owner.filter(m => m.name.toLowerCase() === first.name.toLowerCase());
      return same.length ? same : found;
    }
    void segs;
    return found;
  }

  sameDecl(a: Decl, b: Decl): boolean {
    return key(a) === key(b);
  }

  /** For a method declaration, its body in the implementation (and the other way round). */
  bodyOf(d: Decl): Body | undefined {
    const unit = this.unitOf.get(d);
    if (!unit || !d.container) {
      return undefined;
    }
    return unit.bodies.find(b => b.className?.toLowerCase() === d.container!.name.toLowerCase() &&
      b.routineName.toLowerCase() === d.name.toLowerCase() &&
      paramsKey(b.decl) === paramsKey(d));
  }

  /** Every place in the project files that refers to d (with its declaration). */
  references(d: Decl, files: string[]): { file: string; line: number; col: number; length: number }[] {
    const out: { file: string; line: number; col: number; length: number }[] = [];
    const n = d.name.toLowerCase();
    const targetKeys = new Set([key(d)]);
    const add = (file: string, line: number, col: number): void => {
      if (!out.some(o => o.file === file && o.line === line && o.col === col)) {
        out.push({ file, line, col, length: d.name.length });
      }
    };
    for (const f of new Set([d.file, ...files])) {
      const text = this.read(f);
      if (!text || !text.toLowerCase().includes(n)) {
        continue;
      }
      const unit = this.unitForFile(f);
      if (!unit) {
        continue;
      }
      unit.tokens.forEach((t, k) => {
        if (t.kind !== 'ident' || t.lower !== n || (t.file && t.file !== f)) {
          return;
        }
        const found = this.resolveToken(unit, k);
        if (found.some(x => targetKeys.has(key(x)))) {
          add(f, t.line, t.col);
        }
      });
    }
    return out;
  }
}

export function paramsKey(d: Decl): string {
  return (d.params ?? []).map(p => p.type.toLowerCase().replace(/\s+/g, '')).join(';');
}

// ---------------- text for people ----------------

export function signature(d: Decl): string {
  const params = (ps: Decl['params']): string => (ps && ps.length
    ? '(' + ps.map(p => `${p.modifier ? p.modifier + ' ' : ''}${p.name}${p.type ? ': ' + p.type : ''}${p.defaultValue ? ' = ' + p.defaultValue : ''}`).join('; ') + ')'
    : '');
  const owner = d.container && d.kind !== 'enumvalue' ? d.container.name + '.' : '';
  switch (d.kind) {
    case 'method':
    case 'routine':
      return `${d.isClassMember ? 'class ' : ''}${d.routineKind ?? 'procedure'} ${owner}${d.name}${params(d.params)}${d.type ? ': ' + d.type : ''}`;
    case 'property':
      return `property ${owner}${d.name}${d.propertyIndex ? '[' + params(d.propertyIndex).slice(1, -1) + ']' : ''}${d.type ? ': ' + d.type : ''}`;
    case 'class':
    case 'object':
    case 'interface':
      return `type ${d.name} = ${d.kind}${d.ancestor || d.interfaces?.length ? '(' + [d.ancestor, ...(d.interfaces ?? [])].filter(Boolean).join(', ') + ')' : ''}`;
    case 'record':
      return `type ${d.name} = record`;
    case 'enum':
      return `type ${d.name} = (${(d.members ?? []).map(m => m.name).join(', ')})`;
    case 'type':
      return `type ${d.name} = ${d.aliasOf ?? ''}`;
    case 'const':
      return `const ${d.name}${d.type && !d.aliasOf ? ': ' + d.type : ''}${d.aliasOf ? ' = ' + d.aliasOf : ''}`;
    case 'enumvalue':
      return `${d.name}: ${d.type}`;
    case 'unit':
      return `unit ${d.name}`;
    case 'param':
      return `${d.doc?.endsWith('parameter') ? d.doc.replace(' parameter', '') + ' ' : ''}${d.name}: ${d.type}`;
    case 'result':
      return `Result: ${d.type}`;
    default:
      return `${d.kind === 'field' ? '' : 'var '}${owner}${d.name}: ${d.type ?? ''}`;
  }
}

export function lineText(lines: string[], line: number): string {
  return lines[line] ?? '';
}

export type { Body, Decl, ParsedUnit } from './parser';
