// A small, forgiving reader for Object Pascal source: finds the unit name,
// uses clauses, types, methods and routines with their lines. It is not a
// compiler; it is good enough for outline, symbol search and go-to-definition.
// No VS Code dependency, so it can be unit tested.

export type PascalSymbolKind =
  'unit' | 'class' | 'record' | 'interface' | 'type' | 'method' | 'routine' | 'field' | 'property';

export interface PascalSymbol {
  name: string;           // short name, e.g. "SendClick"
  kind: PascalSymbolKind;
  line: number;
  character: number;
  container?: string;     // owning type for members and method bodies, e.g. "THomeForm"
  implementation: boolean; // a routine body (as opposed to a declaration)
  endLine?: number;       // for types: the line of their "end;"
}

export interface PascalFile {
  unitName?: string;
  uses: { name: string; line: number }[];
  symbols: PascalSymbol[];
}

/** Replaces comments and string contents with spaces, keeping line/column positions. */
export function blankComments(text: string): string {
  let out = '';
  let i = 0;
  const n = text.length;
  const blank = (s: string) => s.replace(/[^\n]/g, ' ');
  while (i < n) {
    const c = text[i];
    if (c === '/' && text[i + 1] === '/') {
      const j = text.indexOf('\n', i);
      const end = j < 0 ? n : j;
      out += blank(text.substring(i, end));
      i = end;
    } else if (c === '{') {
      const j = text.indexOf('}', i + 1);
      const end = j < 0 ? n : j + 1;
      out += blank(text.substring(i, end));
      i = end;
    } else if (c === '(' && text[i + 1] === '*') {
      const j = text.indexOf('*)', i + 2);
      const end = j < 0 ? n : j + 2;
      out += blank(text.substring(i, end));
      i = end;
    } else if (c === "'") {
      let j = i + 1;
      while (j < n && text[j] !== '\n') {
        if (text[j] === "'") {
          if (text[j + 1] === "'") { j += 2; continue; }
          break;
        }
        j++;
      }
      out += "'" + blank(text.substring(i + 1, j)) + (text[j] === "'" ? "'" : '');
      i = text[j] === "'" ? j + 1 : j;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

const routineRe = /^(\s*)(?:class\s+)?(procedure|function|constructor|destructor|operator)\s+([A-Za-z_][\w.]*)/i;
const typeRe = /^(\s*)([A-Za-z_]\w*)\s*=\s*(?:packed\s+)?(class|record|object|interface|dispinterface)\b(.*)$/i;
const simpleTypeRe = /^(\s*)([A-Za-z_]\w*)\s*=\s*(?!class\b|record\b|object\b|interface\b)(?:type\s+)?[^;]+;/i;
const propertyRe = /^\s*(?:class\s+)?property\s+([A-Za-z_]\w*)/i;
const fieldRe = /^\s*([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*[^=;]+;/;
const sectionRe = /^\s*(interface|implementation|initialization|finalization)\b/i;
const visibilityRe = /^\s*(strict\s+)?(private|protected|public|published)\b/i;

export function parsePascal(text: string): PascalFile {
  const code = blankComments(text);
  const lines = code.split(/\r?\n/);
  const result: PascalFile = { uses: [], symbols: [] };
  let section: 'none' | 'interface' | 'implementation' = 'none';
  let inType: { name: string; indent: number; symbol: PascalSymbol } | undefined;
  let inTypeBlock = false;
  let usesOpen = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (result.unitName === undefined) {
      const u = /^\s*(unit|program|library)\s+([A-Za-z_][\w.]*)\s*;/i.exec(line);
      if (u) {
        result.unitName = u[2];
        result.symbols.push({ name: u[2], kind: 'unit', line: i, character: line.indexOf(u[2]), implementation: false });
        continue;
      }
    }

    // uses clauses (may span several lines)
    let rest = line;
    const usesStart = /^\s*uses\b/i.exec(line);
    if (usesStart) {
      usesOpen = true;
      rest = line.substring(usesStart[0].length);
    }
    if (usesOpen) {
      const semi = rest.indexOf(';');
      const part = semi >= 0 ? rest.substring(0, semi) : rest;
      for (const m of part.matchAll(/[A-Za-z_][\w.]*/g)) {
        if (m[0].toLowerCase() !== 'in') {
          result.uses.push({ name: m[0], line: i });
        }
      }
      if (semi >= 0) {
        usesOpen = false;
      }
      continue;
    }

    const sec = sectionRe.exec(line);
    if (sec && !inType) {
      const s = sec[1].toLowerCase();
      section = s === 'interface' ? 'interface' : s === 'implementation' ? 'implementation' : section;
      inTypeBlock = false;
      continue;
    }
    if (/^\s*type\b/i.test(line) && !inType) {
      inTypeBlock = true;
      continue;
    }
    if (/^\s*(var|const|resourcestring|threadvar|begin)\b/i.test(line) && !inType) {
      inTypeBlock = false;
    }

    if (inType) {
      if (/^\s*end\s*;/i.test(line) && line.search(/\S/) <= inType.indent) {
        inType.symbol.endLine = i;
        inType = undefined;
        continue;
      }
      if (visibilityRe.test(line)) {
        continue;
      }
      const r = routineRe.exec(line);
      if (r) {
        const name = r[3];
        result.symbols.push({ name, kind: 'method', line: i, character: line.indexOf(name, r[1].length),
          container: inType.name, implementation: false });
        continue;
      }
      const p = propertyRe.exec(line);
      if (p) {
        result.symbols.push({ name: p[1], kind: 'property', line: i, character: line.indexOf(p[1]),
          container: inType.name, implementation: false });
        continue;
      }
      const f = fieldRe.exec(line);
      if (f) {
        for (const m of f[1].matchAll(/[A-Za-z_]\w*/g)) {
          result.symbols.push({ name: m[0], kind: 'field', line: i, character: (m.index ?? 0) + line.indexOf(f[1]),
            container: inType.name, implementation: false });
        }
      }
      continue;
    }

    if (inTypeBlock || section === 'interface' || section === 'implementation' || section === 'none') {
      const t = typeRe.exec(line);
      if (t && inTypeBlock) {
        const after = t[4].trim();
        if (after === ';') {
          continue;   // forward declaration: "TForm = class;"
        }
        if (/^of\b/i.test(after)) {
          // class reference: "TControlClass = class of TControl;"
          result.symbols.push({ name: t[2], kind: 'type', line: i, character: t[1].length, implementation: false });
          continue;
        }
        const kind = t[3].toLowerCase() === 'record' ? 'record' :
          t[3].toLowerCase().endsWith('interface') ? 'interface' : 'class';
        const symbol: PascalSymbol = { name: t[2], kind, line: i, character: t[1].length, implementation: false };
        result.symbols.push(symbol);
        // "TErr = class(Exception);" has no body
        if (!/^\([^)]*\)\s*;$/.test(after)) {
          inType = { name: t[2], indent: t[1].length, symbol };
        }
        continue;
      }
      const st = simpleTypeRe.exec(line);
      if (st && inTypeBlock) {
        result.symbols.push({ name: st[2], kind: 'type', line: i, character: st[1].length, implementation: false });
        continue;
      }
    }

    const r = routineRe.exec(line);
    if (r) {
      inTypeBlock = false;
      const full = r[3];
      const dot = full.lastIndexOf('.');
      const name = dot >= 0 ? full.substring(dot + 1) : full;
      const container = dot >= 0 ? full.substring(0, dot) : undefined;
      result.symbols.push({
        name, kind: container ? 'method' : 'routine', line: i,
        character: line.indexOf(full, r[1].length) + (dot >= 0 ? dot + 1 : 0),
        container, implementation: section !== 'interface',
      });
    }
  }
  return result;
}

/** The symbol that contains a line: the method body or declaration at or above it. */
export function symbolAtLine(file: PascalFile, line: number): PascalSymbol | undefined {
  let best: PascalSymbol | undefined;
  for (const s of file.symbols) {
    if ((s.kind === 'method' || s.kind === 'routine') && s.line <= line) {
      if (!best || s.line > best.line) {
        best = s;
      }
    }
  }
  return best;
}

/**
 * Delphi's Ctrl+Shift+Up/Down: from a method declaration to its body and
 * back. Returns the target symbol, or undefined.
 */
export function toggleDeclaration(file: PascalFile, line: number): PascalSymbol | undefined {
  const here = file.symbols.find(s => s.line === line && (s.kind === 'method' || s.kind === 'routine'))
    ?? symbolAtLine(file, line);
  if (!here) {
    return undefined;
  }
  const same = (a?: string, b?: string) => (a ?? '').toLowerCase() === (b ?? '').toLowerCase();
  return file.symbols.find(s =>
    s !== here && (s.kind === 'method' || s.kind === 'routine') &&
    same(s.name, here.name) && same(s.container, here.container) &&
    s.implementation !== here.implementation);
}

/** The word (or dotted name like Pastel.UI) at a column. */
export function dottedWordAt(line: string, character: number): { word: string; start: number } | undefined {
  for (const m of line.matchAll(/[A-Za-z_][\w.]*/g)) {
    const start = m.index ?? 0;
    if (character >= start && character <= start + m[0].length) {
      return { word: m[0].replace(/\.$/, ''), start };
    }
  }
  return undefined;
}
