// Pascal tokens with positions, comments (for documentation) and the
// conditional-compilation directives applied. No VS Code dependency.

export type TokenKind = 'ident' | 'number' | 'string' | 'symbol';

export interface Token {
  kind: TokenKind;
  text: string;
  lower: string;     // for identifiers and keywords
  line: number;      // 0-based
  col: number;       // 0-based
  file?: string;     // set for tokens that came from an include file
}

export interface Comment {
  text: string;      // without the comment markers
  line: number;      // first line
  endLine: number;   // last line
  ownLine: boolean;  // nothing but the comment on its first line
  file?: string;     // set for comments from an include file
}

export interface Lexed {
  tokens: Token[];
  comments: Comment[];
  includes: { name: string; index: number; line: number }[];   // {$i name} before tokens[index]
}

const SYMBOLS = [':=', '+=', '-=', '*=', '/=', '<=', '>=', '<>', '..', '><', '**', '(.', '.)'];

/** Evaluates {$if} expressions well enough: defined(X), not, and, or; anything else counts as true. */
function evalIf(expr: string, defines: Set<string>): boolean {
  const e = expr.replace(/defined\s*\(\s*(\w+)\s*\)/gi, (_m, n: string) => (defines.has(n.toLowerCase()) ? ' T ' : ' F '))
    .replace(/declared\s*\(\s*\w+\s*\)/gi, ' T ');
  const toks = e.split(/\s+|(?=[()])|(?<=[()])/).filter(t => t !== '');
  let pos = 0;
  const atom = (): boolean => {
    const t = (toks[pos++] ?? '').toLowerCase();
    if (t === 'not') {
      return !atom();
    }
    if (t === '(') {
      const v = orExpr();
      if (toks[pos] === ')') {
        pos++;
      }
      return v;
    }
    if (t === 'f') {
      return false;
    }
    // T, or something we do not evaluate (FPC_FULLVERSION >= 30000): true
    if (/^(=|<>|<|>|<=|>=)$/.test(toks[pos] ?? '')) {
      pos += 2;
    }
    return true;
  };
  const andExpr = (): boolean => {
    let v = atom();
    while ((toks[pos] ?? '').toLowerCase() === 'and') {
      pos++;
      v = atom() && v;
    }
    return v;
  };
  const orExpr = (): boolean => {
    let v = andExpr();
    while ((toks[pos] ?? '').toLowerCase() === 'or') {
      pos++;
      v = andExpr() || v;
    }
    return v;
  };
  try {
    return orExpr();
  } catch {
    return true;
  }
}

export function defaultDefines(platform: string = process.platform): Set<string> {
  const d = ['fpc', 'objfpc', 'fpc_objfpc', 'cpu64', 'fpc_has_feature_ansistrings', 'fpc_has_feature_widestrings',
    'fpc_has_feature_unicodestrings', 'fpc_has_feature_classes', 'fpc_has_feature_exceptions',
    'fpc_has_feature_threading', 'fpc_has_feature_rtti', 'fpc_has_feature_dynarrays', 'fpc_has_feature_text_io',
    'fpc_has_feature_file_io', 'fpc_has_feature_console_io', 'fpc_has_feature_variants', 'fpc_has_feature_resources',
    'fpc_has_unicodestring', 'fpc_has_feature_heap', 'fpc_has_feature_init', 'fpc_has_feature_stackcheck',
    'fpc_has_feature_random', 'fpc_has_feature_process', 'fpc_has_feature_commandargs', 'fpc_has_feature_supportsrtti',
    'fpc_unicodestrings_off', 'endian_little', 'fpc_little_endian', 'ver3', 'ver3_2', 'ver3_2_2', 'fpc_fullversion'];
  if (platform === 'win32') {
    d.push('windows', 'mswindows', 'win64', 'cpux86_64');
  } else if (platform === 'darwin') {
    d.push('unix', 'darwin', 'bsd', 'cpuaarch64');
  } else {
    d.push('unix', 'linux', 'cpux86_64', 'cpuamd64', 'fpc_use_libc');
  }
  return new Set(d);
}

export function lex(text: string, defines: Set<string> = defaultDefines()): Lexed {
  const tokens: Token[] = [];
  const comments: Comment[] = [];
  const includes: Lexed['includes'] = [];
  const n = text.length;
  let i = 0;
  let line = 0;
  let lineStart = 0;
  // conditional stack: each entry is [active, someBranchTaken, parentActive]
  const cond: [boolean, boolean, boolean][] = [];
  let active = true;
  let lastTokenLine = -1;
  // macros live with the defines, so include files see them too
  const macros: Map<string, string> = (defines as Set<string> & { macros?: Map<string, string> }).macros ??= new Map();

  const directive = (body: string, startLine: number): void => {
    const m = /^\$(\w+)\s*(.*)$/s.exec(body.trim());
    if (!m) {
      return;
    }
    const name = m[1].toLowerCase();
    const arg = m[2].trim();
    const word = (arg.split(/\s+/)[0] ?? '').toLowerCase();
    switch (name) {
      case 'ifdef':
      case 'ifndef':
      case 'if':
      case 'ifopt': {
        const v = name === 'ifdef' ? defines.has(word) : name === 'ifndef' ? !defines.has(word) :
          name === 'if' ? evalIf(arg, defines) : false;
        cond.push([active && v, v, active]);
        active = active && v;
        break;
      }
      case 'elseif': {
        const top = cond[cond.length - 1];
        if (top) {
          const v = !top[1] && evalIf(arg, defines);
          top[0] = top[2] && v;
          top[1] = top[1] || v;
          active = top[0];
        }
        break;
      }
      case 'else': {
        const top = cond[cond.length - 1];
        if (top) {
          top[0] = top[2] && !top[1];
          top[1] = true;
          active = top[0];
        }
        break;
      }
      case 'endif':
      case 'ifend': {
        const top = cond.pop();
        active = top ? top[2] : true;
        break;
      }
      case 'define':
        if (active && word) {
          const macro = /^(\w+)\s*:=\s*(\w+)\s*$/.exec(arg);
          if (macro) {          // {$define TProcessnamemacro:=TProcess}
            macros.set(macro[1].toLowerCase(), macro[2]);
          }
          defines.add(word.replace(/:=.*$/, ''));
        }
        break;
      case 'undef':
        if (active && word) {
          defines.delete(word);
        }
        break;
      case 'i':
      case 'include':
        if (active && arg && !arg.startsWith('%')) {
          includes.push({ name: arg.replace(/^'|'$/g, ''), index: tokens.length, line: startLine });
        }
        break;
    }
  };

  while (i < n) {
    const c = text[i];
    if (c === '\n') {
      line++;
      i++;
      lineStart = i;
      continue;
    }
    if (c === ' ' || c === '\t' || c === '\r' || c === '\f') {
      i++;
      continue;
    }
    const col = i - lineStart;
    const startLine = line;
    const ownLine = lastTokenLine !== line;
    // comments and directives
    if (c === '{' || (c === '(' && text[i + 1] === '*') || (c === '/' && text[i + 1] === '/')) {
      let body: string;
      if (c === '/') {
        const j = text.indexOf('\n', i);
        const end = j < 0 ? n : j;
        body = text.substring(i + 2, end);
        i = end;
      } else if (c === '{') {
        let depth = 1;
        let j = i + 1;
        const isDirective = text[j] === '$';
        while (j < n && depth > 0) {
          if (text[j] === '{' && !isDirective) {
            depth++;
          } else if (text[j] === '}') {
            depth--;
          }
          if (text[j] === '\n') {
            line++;
            lineStart = j + 1;
          }
          j++;
        }
        body = text.substring(i + 1, j - 1);
        i = j;
      } else {
        const j = text.indexOf('*)', i + 2);
        const end = j < 0 ? n : j + 2;
        body = text.substring(i + 2, j < 0 ? n : j);
        for (let k = i; k < end; k++) {
          if (text[k] === '\n') {
            line++;
            lineStart = k + 1;
          }
        }
        i = end;
      }
      if (body.startsWith('$') && c !== '/') {
        directive(body, startLine);
      } else if (active) {
        comments.push({ text: body, line: startLine, endLine: line, ownLine });
      }
      continue;
    }
    // strings: 'abc', #13, mixed
    if (c === "'" || c === '#') {
      let j = i;
      let s = '';
      while (j < n && (text[j] === "'" || text[j] === '#')) {
        if (text[j] === '#') {
          j++;
          while (j < n && /[0-9$a-fA-F]/.test(text[j])) {
            j++;
          }
        } else {
          j++;
          while (j < n && text[j] !== '\n') {
            if (text[j] === "'") {
              if (text[j + 1] === "'") {
                s += "'";
                j += 2;
                continue;
              }
              break;
            }
            s += text[j];
            j++;
          }
          j++;
        }
      }
      if (active) {
        tokens.push({ kind: 'string', text: s, lower: s, line, col });
        lastTokenLine = line;
      }
      i = j;
      continue;
    }
    // identifiers (also &begin)
    if (/[A-Za-z_]/.test(c) || (c === '&' && /[A-Za-z_]/.test(text[i + 1] ?? ''))) {
      let j = c === '&' ? i + 1 : i;
      const start = j;
      while (j < n && /[A-Za-z0-9_]/.test(text[j])) {
        j++;
      }
      let word = text.substring(start, j);
      if (macros.size && macros.has(word.toLowerCase())) {
        word = macros.get(word.toLowerCase())!;
      }
      if (active) {
        tokens.push({ kind: 'ident', text: word, lower: word.toLowerCase(), line, col: start - lineStart });
        lastTokenLine = line;
      }
      i = j;
      continue;
    }
    // numbers
    if (/[0-9$%]/.test(c) || (c === '&' && /[0-7]/.test(text[i + 1] ?? ''))) {
      let j = i + 1;
      while (j < n && /[0-9A-Fa-f_.eE]/.test(text[j]) && !(text[j] === '.' && text[j + 1] === '.')) {
        if ((text[j] === 'e' || text[j] === 'E') && /[+-]/.test(text[j + 1] ?? '') && c !== '$') {
          j++;
        }
        j++;
      }
      if (active) {
        tokens.push({ kind: 'number', text: text.substring(i, j), lower: '', line, col });
        lastTokenLine = line;
      }
      i = j;
      continue;
    }
    const two = text.substring(i, i + 2);
    const sym = SYMBOLS.includes(two) ? two : c;
    if (active) {
      tokens.push({ kind: 'symbol', text: sym, lower: sym, line, col });
      lastTokenLine = line;
    }
    i += sym.length;
  }
  return { tokens, comments, includes };
}

/** Text of the documentation comment for a declaration on `line`: the
 *  comments right above it (no blank line between), or one after it on the same line. */
export function docFor(comments: Comment[], line: number, lines?: string[]): string | undefined {
  const parts: string[] = [];
  let want = line - 1;
  for (let k = comments.length - 1; k >= 0; k--) {
    const c = comments[k];
    if (c.endLine > want) {
      continue;
    }
    if (c.endLine === want && c.ownLine) {
      parts.unshift(c.text);
      want = c.line - 1;
      continue;
    }
    break;
  }
  if (parts.length === 0) {
    const same = comments.find(c => c.line === line && !c.ownLine);
    if (same) {
      parts.push(same.text);
    }
  }
  if (parts.length === 0) {
    return undefined;
  }
  void lines;
  const text = parts.map(p => p.replace(/^\s*\*?/gm, '').trim()).join('\n').trim();
  // licence headers and separators are not documentation
  if (/^-{3,}|^={3,}|copyright|license/i.test(text) || text === '') {
    return undefined;
  }
  return text;
}
