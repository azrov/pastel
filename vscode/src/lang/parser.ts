// Declarations of a Pascal unit or program: types with their members,
// routines with parameters, variables, constants, routine bodies with their
// local declarations. Forgiving: what it does not understand it skips.
import { docFor, Lexed, Token } from './lexer';

export type DeclKind =
  'unit' | 'class' | 'record' | 'interface' | 'object' | 'enum' | 'type' |
  'const' | 'var' | 'field' | 'property' | 'method' | 'routine' | 'param' | 'enumvalue' | 'result';

export interface Param {
  name: string;
  type: string;
  modifier: string;   // const, var, out, constref or ''
  defaultValue?: string;
  line?: number;
  col?: number;
}

export interface Decl {
  name: string;
  kind: DeclKind;
  line: number;
  col: number;
  file: string;
  type?: string;          // of a variable/field/property/constant/parameter; the result of a function
  params?: Param[];
  routineKind?: string;   // procedure, function, constructor, destructor, operator
  isClassMember?: boolean; // class function, class var...
  visibility?: string;
  directives?: string[];
  doc?: string;
  members?: Decl[];       // of classes, records, interfaces, enums
  ancestor?: string;
  interfaces?: string[];
  container?: Decl;       // the type a member belongs to
  aliasOf?: string;       // type X = Y; also "array of T", "^T", "set of T"
  endLine?: number;
  forward?: boolean;      // "TFoo = class;"
  interfaceSection?: boolean;
  propertyIndex?: Param[];
  isDefault?: boolean;    // property ... default;
}

export interface Body {
  name: string;           // "TFoo.Bar" or "Bar"
  className?: string;
  routineName: string;
  decl: Decl;             // the header, as a routine declaration
  locals: Decl[];
  nameLine: number;
  nameCol: number;
  classNameCol?: number;
  startLine: number;      // of the header
  beginLine: number;
  beginCol: number;
  endLine: number;
  endCol: number;
  parent?: Body;
}

export interface Use {
  name: string;
  line: number;
  col: number;
}

export interface ParsedUnit {
  name: string;
  file: string;
  isProgram: boolean;
  interfaceUses: Use[];
  implementationUses: Use[];
  interfaceDecls: Decl[];
  implementationDecls: Decl[];
  bodies: Body[];
  implementationLine: number;   // -1 when none
  tokens: Token[];
}

const SECTION_END = new Set(['type', 'var', 'const', 'resourcestring', 'threadvar', 'procedure', 'function',
  'constructor', 'destructor', 'operator', 'implementation', 'initialization', 'finalization', 'begin', 'end',
  'class', 'property', 'generic', 'label', 'exports']);
const VISIBILITY = new Set(['private', 'protected', 'public', 'published', 'strict', 'automated']);
const ROUTINE = new Set(['procedure', 'function', 'constructor', 'destructor', 'operator']);
const DIRECTIVES = new Set(['virtual', 'override', 'overload', 'abstract', 'reintroduce', 'static', 'dynamic',
  'cdecl', 'stdcall', 'register', 'inline', 'external', 'forward', 'assembler', 'message', 'deprecated',
  'platform', 'experimental', 'unimplemented', 'final', 'safecall', 'pascal', 'varargs', 'export',
  'noreturn', 'local', 'nostackframe', 'interrupt', 'alias', 'compilerproc', 'rtlproc', 'internproc', 'internconst',
  'hardfloat', 'mwpascal', 'ms_abi_default', 'sysv_abi_default', 'vectorcall', 'enumerator', 'iocheck', 'winapi']);

export function parseUnit(lexed: Lexed, file: string, text?: string): ParsedUnit {
  const toks = lexed.tokens;
  const lines = text?.split(/\r?\n/);
  let p = 0;
  const unit: ParsedUnit = {
    name: '', file, isProgram: false, interfaceUses: [], implementationUses: [],
    interfaceDecls: [], implementationDecls: [], bodies: [], implementationLine: -1, tokens: toks,
  };

  const peek = (k = 0): Token | undefined => toks[p + k];
  const is = (w: string, k = 0): boolean => toks[p + k]?.lower === w;
  const isSym = (s: string, k = 0): boolean => toks[p + k]?.kind === 'symbol' && toks[p + k]?.text === s;
  const next = (): Token | undefined => {
    const t = toks[p++];
    docFile = t?.file ?? file;
    return t;
  };
  const byFile = new Map<string, Lexed['comments']>();
  for (const c of lexed.comments) {
    const f = c.file ?? file;
    if (!byFile.has(f)) {
      byFile.set(f, []);
    }
    byFile.get(f)!.push(c);
  }
  let docFile = file;
  const doc = (line: number): string | undefined => docFor(byFile.get(docFile) ?? [], line, lines);
  const fileOf = (t: Token | undefined): string => t?.file ?? file;

  const skipTo = (sym: string): void => {
    let depth = 0;
    while (p < toks.length) {
      const t = toks[p];
      if (t.kind === 'symbol') {
        if (t.text === sym && depth <= ((sym === ')' || sym === ']') ? 1 : 0) && !(t.text === '(' || t.text === '[')) {
          p++;
          return;
        }
        if (t.text === '(' || t.text === '[') {
          depth++;
        } else if (t.text === ')' || t.text === ']') {
          depth--;
        }
      }
      p++;
    }
  };

  // text of a type up to ; ) = or a directive, with balanced brackets
  const typeText = (stops: string[] = [';']): string => {
    const parts: string[] = [];
    let depth = 0;
    let lastLine = -1;
    while (p < toks.length) {
      const t = toks[p];
      if (depth === 0 && t.kind === 'symbol' && (stops.includes(t.text) || t.text === ')' || t.text === ']')) {
        break;
      }
      if (depth === 0 && t.kind === 'ident' && stops.includes(t.lower)) {
        break;
      }
      if (depth === 0 && t.kind === 'ident' && (t.lower === 'read' || t.lower === 'write' || t.lower === 'default' ||
          t.lower === 'stored' || t.lower === 'index' || t.lower === 'implements' || t.lower === 'nodefault')) {
        if (stops.includes('read')) {
          break;
        }
      }
      if (t.kind === 'ident' && (t.lower === 'record' || t.lower === 'object' && depth > 0)) {
        depth++;       // array of record ... end
      } else if (t.kind === 'ident' && t.lower === 'end' && depth > 0) {
        depth--;
      }
      if (t.kind === 'symbol' && (t.text === '(' || t.text === '[' || t.text === '<')) {
        depth++;
      } else if (t.kind === 'symbol' && (t.text === ')' || t.text === ']' || t.text === '>')) {
        depth--;
      }
      if (t.kind === 'string') {
        parts.push(`'${t.text}'`);
      } else {
        const glue = parts.length > 0 && !(t.kind === 'symbol' && /^[.,)\]<>^]$/.test(t.text)) &&
          !/[.([<^]$/.test(parts[parts.length - 1]) ? ' ' : '';
        parts.push(glue + t.text);
      }
      lastLine = t.line;
      p++;
    }
    void lastLine;
    return parts.join('').replace(/\s+/g, ' ').replace(/(^|[=(,:\[]\s?)- (?=[\d$])/g, '$1-').trim();
  };

  const params = (): Param[] => {
    const out: Param[] = [];
    if (!isSym('(') && !isSym('[')) {
      return out;
    }
    const close = isSym('(') ? ')' : ']';
    p++;
    while (p < toks.length && !isSym(close)) {
      let modifier = '';
      if (['const', 'var', 'out', 'constref'].includes(peek()?.lower ?? '')) {
        modifier = next()!.lower;
      }
      const names: Token[] = [];
      while (peek()?.kind === 'ident') {
        names.push(next()!);
        if (isSym(',')) {
          p++;
        } else {
          break;
        }
      }
      let type = '';
      let def: string | undefined;
      if (isSym(':')) {
        p++;
        type = typeText([';', '=', ')', ']']);
      }
      if (isSym('=')) {
        p++;
        def = typeText([';', ')', ']']);
      }
      for (const n of names) {
        out.push({ name: n.text, type, modifier, defaultValue: def, line: n.line, col: n.col });
      }
      if (isSym(';')) {
        p++;
      } else if (!isSym(close)) {
        p++;    // something we do not understand
      }
    }
    p++;
    return out;
  };

  const HINTS = new Set(['deprecated', 'platform', 'experimental', 'unimplemented']);
  const directives = (onlyHints = false): string[] => {
    const out: string[] = [];
    const known = (w: string): boolean => (onlyHints ? HINTS.has(w) : DIRECTIVES.has(w));
    for (;;) {
      if (isSym(';') && peek(1)?.kind === 'ident' && known(peek(1)!.lower)) {
        p++;
      }
      const t = peek();
      if (t?.kind === 'ident' && known(t.lower)) {
        out.push(t.lower);
        p++;
        // external 'lib' name 'x'; message 'x'; deprecated 'text'
        while (p < toks.length && !isSym(';') && !(peek()?.kind === 'ident' && known(peek()!.lower))) {
          p++;
        }
        continue;
      }
      if (isSym('[')) {      // [public, alias: 'x']
        skipTo(']');
        continue;
      }
      break;
    }
    if (isSym(';')) {
      p++;
    }
    return out;
  };

  // after procedure/function/...: name, params, result, directives
  const routineHeader = (kindWord: string, container?: Decl): { decl: Decl; qualified: Token[] } => {
    const nameToks: Token[] = [];
    while (peek()?.kind === 'ident' || (kindWord === 'operator' && peek()?.kind === 'symbol' && !isSym('('))) {
      nameToks.push(next()!);
      if (isSym('<')) {      // generic method parameters
        skipTo('>');
      }
      if (isSym('.') && peek(1)?.kind === 'ident') {
        p++;
        continue;
      }
      break;
    }
    const nameTok = nameToks[nameToks.length - 1] ?? peek()!;
    const decl: Decl = {
      name: nameTok?.text ?? '', kind: container ? 'method' : 'routine', line: nameTok?.line ?? 0,
      col: nameTok?.col ?? 0, file: fileOf(nameTok), routineKind: kindWord, container,
    };
    decl.params = params();
    if (isSym(':')) {
      p++;
      decl.type = typeText([';', '=']);
    }
    if (isSym(';')) {
      p++;
    }
    decl.directives = directives();
    decl.doc = doc(nameToks[0]?.line ?? decl.line);
    return { decl, qualified: nameToks };
  };

  // members of a class, record, object or interface, until "end"
  const members = (owner: Decl): void => {
    owner.members = [];
    let visibility = owner.kind === 'record' ? 'public' : 'published';
    let section: 'field' | 'var' | 'const' | 'type' = 'field';
    let classVar = false;
    let guard = -1;
    while (p < toks.length && !is('end')) {
      if (p === guard) {
        p++;
        continue;
      }
      guard = p;
      const t = peek()!;
      if (t.kind === 'ident' && VISIBILITY.has(t.lower)) {
        p++;
        if (t.lower === 'strict') {
          visibility = 'strict ' + (next()?.lower ?? 'private');
        } else {
          visibility = t.lower;
        }
        section = 'field';
        classVar = false;
        continue;
      }
      if (is('case') && owner.kind === 'record') {     // variant part
        p++;
        if (peek(1) && isSym(':', 1)) {
          const n = next()!;
          p++;
          owner.members.push({ name: n.text, kind: 'field', line: n.line, col: n.col, file: fileOf(n), type: typeText([';', 'of']),
            container: owner, visibility });
        } else {
          typeText(['of']);
        }
        if (is('of')) {
          p++;
        }
        // value: (fields); ...
        while (p < toks.length && !is('end')) {
          const before = p;
          typeText([':']);
          if (isSym(':')) {
            p++;
          }
          if (isSym('(')) {
            p++;
            while (p < toks.length && !isSym(')')) {
              const at = p;
              fieldList(owner, visibility, false);
              if (isSym(';')) {
                p++;
              }
              if (p === at) {
                p++;
              }
            }
            p++;
          }
          if (isSym(';')) {
            p++;
          }
          if (p === before) {
            p++;
          }
        }
        break;
      }
      if (t.lower === 'class' && peek(1)?.kind === 'ident' &&
          (ROUTINE.has(peek(1)!.lower) || peek(1)!.lower === 'property' || peek(1)!.lower === 'var' ||
           peek(1)!.lower === 'threadvar')) {
        p++;
        if (is('var') || is('threadvar')) {
          p++;
          section = 'var';
          classVar = true;
          continue;
        }
        member(owner, visibility, true);
        continue;
      }
      if (t.lower === 'var' || t.lower === 'threadvar') {
        p++;
        section = 'var';
        classVar = false;
        continue;
      }
      if (t.lower === 'const') {
        p++;
        section = 'const';
        continue;
      }
      if (t.lower === 'type') {
        p++;
        section = 'type';
        continue;
      }
      if (t.lower === 'generic' || ROUTINE.has(t.lower) || t.lower === 'property') {
        if (t.lower === 'generic') {
          p++;
        }
        member(owner, visibility, false);
        continue;
      }
      if (t.kind === 'symbol' && t.text === '[') {      // GUID or attributes
        skipTo(']');
        continue;
      }
      if (t.kind === 'string') {      // interface GUID without brackets
        p++;
        continue;
      }
      if (t.kind === 'ident') {
        if (section === 'type') {
          typeDecl(owner.members, owner.interfaceSection ?? false, owner);
          continue;
        }
        if (section === 'const') {
          constDecl(owner.members, owner);
          continue;
        }
        fieldList(owner, visibility, classVar);
        if (isSym(';')) {
          p++;
        }
        continue;
      }
      p++;
    }
    owner.endLine = peek()?.line;
    if (is('end')) {
      p++;
    }
  };

  const fieldList = (owner: Decl, visibility: string, classVar: boolean): void => {
    const names: Token[] = [];
    while (peek()?.kind === 'ident') {
      names.push(next()!);
      if (isSym(',')) {
        p++;
      } else {
        break;
      }
    }
    if (!isSym(':')) {
      if (!isSym(';') && !isSym(')') && !is('end')) {
        p++;
      }
      return;
    }
    p++;
    const startType = p;
    let type: string;
    if (is('record') || is('packed')) {          // anonymous record field
      const anon: Decl = { name: names[0]?.text ?? '', kind: 'record', line: names[0]?.line ?? 0, col: 0, file, container: owner };
      if (is('packed')) {
        p++;
      }
      p++;
      members(anon);
      type = 'record';
      for (const n of names) {
        owner.members!.push({ name: n.text, kind: 'field', line: n.line, col: n.col, file: fileOf(n), type, container: owner,
          visibility, members: anon.members, doc: doc(n.line) });
      }
      return;
    }
    p = startType;
    type = typeText([';', '=', ')']);
    if (isSym('=')) {      // initial value
      p++;
      typeText([';', ')']);
    }
    // hint directives after a field: deprecated; platform
    for (const n of names) {
      owner.members!.push({ name: n.text, kind: 'field', line: n.line, col: n.col, file: fileOf(n), type, container: owner,
        visibility, isClassMember: classVar, doc: doc(n.line) });
    }
  };

  const member = (owner: Decl, visibility: string, isClass: boolean): void => {
    const kw = next()!.lower;
    if (kw === 'property') {
      const n = next();
      if (!n) {
        return;
      }
      const prop: Decl = { name: n.text, kind: 'property', line: n.line, col: n.col, file: fileOf(n), container: owner,
        visibility, isClassMember: isClass, doc: doc(n.line) };
      if (isSym('[')) {
        prop.propertyIndex = params();
      }
      if (isSym(':')) {
        p++;
        prop.type = typeText([';', 'read']);
      }
      skipTo(';');
      if (is('default') && isSym(';', 1)) {
        prop.isDefault = true;
        p += 2;
      }
      directives();
      // a property that only changes visibility (property Align;) gets its type from the ancestor
      owner.members!.push(prop);
      return;
    }
    const { decl } = routineHeader(kw, owner);
    decl.visibility = visibility;
    decl.isClassMember = isClass;
    owner.members!.push(decl);
  };

  const constDecl = (out: Decl[], container?: Decl, interfaceSection = false): void => {
    const n = next()!;
    const d: Decl = { name: n.text, kind: 'const', line: n.line, col: n.col, file: fileOf(n), container, doc: doc(n.line), interfaceSection };
    if (isSym(':')) {
      p++;
      d.type = typeText([';', '=']);
    }
    if (isSym('=')) {
      p++;
      const value = typeText([';']);
      if (!d.type) {
        d.type = /^'/.test(value) ? 'string' : /^-?\d+$/.test(value) || /^\$/.test(value) ? 'Integer' :
          /^-?\d+\.\d/.test(value) ? 'Double' : /^(true|false)$/i.test(value) ? 'Boolean' : undefined;
        d.aliasOf = value;
      }
    }
    directives(true);
    out.push(d);
  };

  const varDecl = (out: Decl[], interfaceSection: boolean, kind: DeclKind = 'var'): void => {
    const names: Token[] = [];
    while (peek()?.kind === 'ident') {
      names.push(next()!);
      if (isSym(',')) {
        p++;
      } else {
        break;
      }
    }
    if (!isSym(':')) {
      skipTo(';');
      return;
    }
    p++;
    let type: string;
    let anonMembers: Decl[] | undefined;
    if (is('record') || (is('packed') && is('record', 1))) {
      const anon: Decl = { name: names[0]?.text ?? '', kind: 'record', line: names[0].line, col: 0, file };
      p += is('packed') ? 2 : 1;
      members(anon);
      anonMembers = anon.members;
      type = 'record';
    } else {
      type = typeText([';', '=']);
    }
    if (is('absolute')) {
      typeText([';']);
    }
    if (isSym('=')) {
      p++;
      typeText([';']);
    }
    directives(true);
    for (const n of names) {
      out.push({ name: n.text, kind, line: n.line, col: n.col, file: fileOf(n), type, doc: doc(n.line), interfaceSection, members: anonMembers });
    }
  };

  // Name = ...;
  const typeDecl = (out: Decl[], interfaceSection: boolean, container?: Decl): void => {
    if (is('generic')) {
      p++;
    }
    const n = next()!;
    if (isSym('<')) {      // generic parameters
      skipTo('>');
    }
    if (!isSym('=')) {
      skipTo(';');
      return;
    }
    p++;
    const d: Decl = { name: n.text, kind: 'type', line: n.line, col: n.col, file: fileOf(n), doc: doc(n.line), interfaceSection, container };
    if (is('type') && is('helper', 1)) {        // type helper for string
      p += 2;
      if (isSym('(')) {
        skipTo(')');
      }
      if (is('for')) {
        p++;
      }
      d.kind = 'record';
      d.aliasOf = 'helper for ' + typeText([';', 'end', 'private', 'public', 'strict', 'function', 'procedure', 'property',
        'class', 'constructor', 'const', 'type', 'var']);
      members(d);
      directives(true);
      out.push(d);
      return;
    }
    if (is('type')) {
      p++;
    }
    if (is('packed') || is('bitpacked')) {
      p++;
    }
    const w = peek()?.lower ?? '';
    if ((w === 'class' || w === 'object' || w === 'record' || w === 'interface' || w === 'dispinterface' ||
         w === 'objcclass' || w === 'objcprotocol') && !(w === 'class' && is('of', 1))) {
      p++;
      d.kind = w === 'record' ? 'record' : w === 'interface' || w === 'dispinterface' || w === 'objcprotocol' ? 'interface' :
        w === 'object' ? 'object' : 'class';
      if (isSym(';')) {      // forward
        d.forward = true;
        p++;
        out.push(d);
        return;
      }
      while (is('abstract') || is('sealed') || is('external')) {
        p++;
      }
      if (is('helper')) {       // class helper for TFoo, record helper for string
        p++;
        if (isSym('(')) {
          skipTo(')');
        }
        if (is('for')) {
          p++;
          d.aliasOf = 'helper for ' + typeText([';', 'end', 'private', 'public', 'function', 'procedure', 'property', 'class', 'constructor']);
        }
      }
      if (isSym('(')) {
        p++;
        const parents: string[] = [];
        while (p < toks.length && !isSym(')')) {
          const at = p;
          const pt = typeText([',', ')']);
          if (pt) {
            parents.push(pt.replace(/^specialize\s+/i, ''));
          }
          if (isSym(',') || p === at) {
            p++;
          }
        }
        p++;
        if (d.kind === 'class' || d.kind === 'object' || d.kind === 'interface') {
          d.ancestor = parents[0];
          d.interfaces = parents.slice(1);
        }
      }
      if (isSym(';')) {          // TFoo = class(Exception);
        p++;
        d.members = [];
        out.push(d);
        return;
      }
      members(d);
      directives(true);
      out.push(d);
      return;
    }
    if (isSym('(')) {           // enum
      p++;
      d.kind = 'enum';
      d.members = [];
      while (p < toks.length && !isSym(')')) {
        const e = next()!;
        if (e.kind === 'symbol' && e.text === ';') {
          p--;
          break;
        }
        if (e.kind === 'ident') {
          d.members.push({ name: e.text, kind: 'enumvalue', line: e.line, col: e.col, file: fileOf(e), type: d.name, container: d, doc: doc(e.line) });
        }
        if (isSym('=') || isSym(':=')) {
          p++;
          typeText([',', ')']);
        }
        if (isSym(',')) {
          p++;
        }
      }
      p++;
      directives(true);
      out.push(d);
      return;
    }
    if (ROUTINE.has(w) || (w === 'reference' && is('to', 1))) {
      if (w === 'reference') {
        p += 2;
      }
      const kw = next()!.lower;
      const h: Decl = { name: d.name, kind: 'type', line: d.line, col: d.col, file: d.file, routineKind: kw };
      h.params = params();
      if (isSym(':')) {
        p++;
        h.type = typeText([';', 'of']);
      }
      if (is('of') && is('object', 1)) {
        p += 2;
      }
      if (is('is') && is('nested', 1)) {
        p += 2;
      }
      d.aliasOf = `${kw}${h.params.length ? '(' + h.params.map(x => `${x.name}: ${x.type}`).join('; ') + ')' : ''}${h.type ? ': ' + h.type : ''}`;
      d.params = h.params;
      d.type = h.type;
      d.routineKind = kw;
      if (isSym(';')) {
        p++;
      }
      directives(true);
      out.push(d);
      return;
    }
    if (is('set') && is('of', 1) && isSym('(', 2)) {     // set of (a, b): the values are names too
      p += 3;
      d.members = [];
      const vals: string[] = [];
      while (p < toks.length && !isSym(')')) {
        const e = next()!;
        if (e.kind === 'ident') {
          vals.push(e.text);
          d.members.push({ name: e.text, kind: 'enumvalue', line: e.line, col: e.col, file: fileOf(e), type: d.name, container: d });
        }
        if (isSym('=')) {
          p++;
          typeText([',', ')']);
        }
        if (isSym(',')) {
          p++;
        }
      }
      p++;
      d.kind = 'enum';
      d.aliasOf = `set of (${vals.join(', ')})`;
      if (isSym(';')) {
        p++;
      }
      out.push(d);
      return;
    }
    d.aliasOf = typeText([';']);
    if (isSym(';')) {
      p++;
    }
    directives(true);
    out.push(d);
  };

  // skip statements from "begin" (or "asm", "initialization") to the matching end
  const skipBlock = (): { line: number; col: number } => {
    let depth = 0;
    while (p < toks.length) {
      const t = toks[p];
      if (t.kind === 'ident') {
        if (t.lower === 'begin' || t.lower === 'case' || t.lower === 'try' || t.lower === 'asm' ||
            (t.lower === 'record' && depth > 0)) {
          depth++;
        } else if (t.lower === 'end') {
          depth--;
          if (depth <= 0) {
            p++;
            return { line: t.line, col: t.col };
          }
        }
      }
      p++;
    }
    const last = toks[toks.length - 1];
    return { line: last?.line ?? 0, col: last?.col ?? 0 };
  };

  // declarations of a section or a routine, until begin/implementation/...
  const declarations = (out: Decl[], interfaceSection: boolean, bodies: Body[] | undefined, parentBody?: Body,
    localSection = false): void => {
    let mode: 'none' | 'type' | 'var' | 'const' = 'none';
    let guard = -1;
    while (p < toks.length) {
      if (p === guard) {
        p++;
        continue;
      }
      guard = p;
      const t = peek()!;
      const w = t.kind === 'ident' ? t.lower : '';
      if (w === 'implementation' || w === 'initialization' || w === 'finalization' || w === 'begin' ||
          (w === 'end' && !localSection) || w === 'asm') {
        return;
      }
      if (w === 'end') {
        return;
      }
      if (w === 'type') {
        p++;
        mode = 'type';
        continue;
      }
      if (w === 'var' || w === 'threadvar') {
        p++;
        mode = 'var';
        continue;
      }
      if (w === 'const' || w === 'resourcestring') {
        p++;
        mode = 'const';
        continue;
      }
      if (w === 'uses') {
        p++;
        const list = interfaceSection ? unit.interfaceUses : unit.implementationUses;
        while (p < toks.length && !isSym(';')) {
          const u = peek()!;
          if (u.kind === 'ident') {
            const parts = [next()!.text];
            while (isSym('.') && peek(1)?.kind === 'ident') {
              p++;
              parts.push(next()!.text);
            }
            list.push({ name: parts.join('.'), line: u.line, col: u.col });
            if (is('in')) {
              p += 2;
            }
          } else {
            p++;
          }
        }
        p++;
        continue;
      }
      if (w === 'label') {
        skipTo(';');
        continue;
      }
      if (w === 'exports') {
        skipTo(';');
        continue;
      }
      if (w === 'generic' && ROUTINE.has(peek(1)?.lower ?? '')) {
        p++;
        continue;
      }
      if (w === 'class' && ROUTINE.has(peek(1)?.lower ?? '')) {
        p++;
        continue;
      }
      if (ROUTINE.has(w)) {
        const start = t.line;
        p++;
        const { decl, qualified } = routineHeader(w);
        decl.interfaceSection = interfaceSection;
        const isForward = (decl.directives ?? []).includes('forward') || (decl.directives ?? []).includes('external');
        if (interfaceSection || isForward || !bodies) {
          if (qualified.length <= 1) {
            out.push(decl);
          }
          continue;
        }
        // a body: local declarations, then begin ... end;
        const body: Body = {
          name: qualified.map(q => q.text).join('.'), routineName: decl.name, decl, locals: [],
          nameLine: decl.line, nameCol: decl.col, startLine: start, beginLine: 0, beginCol: 0, endLine: 0, endCol: 0,
          parent: parentBody,
        };
        if (qualified.length > 1) {
          body.className = qualified[qualified.length - 2].text;
          body.classNameCol = qualified[qualified.length - 2].col;
          decl.kind = 'method';
        } else {
          out.push(decl);
        }
        for (const prm of decl.params ?? []) {
          body.locals.push({ name: prm.name, kind: 'param', line: prm.line ?? decl.line, col: prm.col ?? decl.col, file, type: prm.type,
            doc: prm.modifier ? `${prm.modifier} parameter` : undefined });
        }
        if (decl.type) {
          body.locals.push({ name: 'Result', kind: 'result', line: decl.line, col: decl.col, file, type: decl.type });
        }
        declarations(body.locals, false, bodies, body, true);
        bodies.push(body);
        if (is('begin') || is('asm')) {
          const b = peek()!;
          body.beginLine = b.line;
          body.beginCol = b.col;
          const e = skipBlock();
          body.endLine = e.line;
          body.endCol = e.col;
          if (isSym(';')) {
            p++;
          }
        } else {
          body.beginLine = body.endLine = peek()?.line ?? decl.line;
        }
        continue;
      }
      if (t.kind === 'ident' && mode === 'type') {
        typeDecl(out, interfaceSection);
        continue;
      }
      if (t.kind === 'ident' && mode === 'const') {
        constDecl(out, undefined, interfaceSection);
        continue;
      }
      if (t.kind === 'ident' && mode === 'var') {
        varDecl(out, interfaceSection);
        continue;
      }
      if (t.kind === 'symbol' && t.text === '{') {
        p++;
        continue;
      }
      p++;      // not understood
    }
  };

  // unit X; / program X; / library X;
  if (is('unit') || is('program') || is('library')) {
    unit.isProgram = !is('unit');
    p++;
    const parts: string[] = [];
    while (peek()?.kind === 'ident') {
      parts.push(next()!.text);
      if (isSym('.')) {
        p++;
      } else {
        break;
      }
    }
    unit.name = parts.join('.');
    if (isSym('(')) {
      skipTo(')');
    }
    directives();
  }
  if (unit.isProgram || !is('interface')) {
    // a program: uses, declarations, bodies
    declarations(unit.implementationDecls, false, unit.bodies);
    unit.interfaceUses = unit.implementationUses;
    unit.implementationUses = [];
    return unit;
  }
  p++;
  declarations(unit.interfaceDecls, true, undefined);
  if (is('implementation')) {
    unit.implementationLine = peek()!.line;
    p++;
    declarations(unit.implementationDecls, false, unit.bodies);
  }
  return unit;
}
