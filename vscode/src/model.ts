// Pure helpers for .pform and Pascal text. No VS Code dependency, so they
// can be unit tested with plain Node.

export interface SchemaProperty {
  name: string;
  type: 'string' | 'integer' | 'boolean' | 'enum' | 'color' | 'event' | 'number';
  values?: string[];
  doc: string;
}

export interface SchemaClass {
  name: string;
  container: boolean;
  form: boolean;
  /** A control of the project (src/controls/), not of Pastel. */
  project?: boolean;
  /** A component without a place on the form (TTimer, TAction, TDataBinding...). */
  nonvisual?: boolean;
  properties: SchemaProperty[];
}

export interface Schema {
  version: string;
  frameworkDir?: string;
  fpcSourceDir?: string;
  form: SchemaClass;
  controls: SchemaClass[];
}

const objectRe = /^\s*object\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)/i;
const endRe = /^\s*end\b/i;

/** Removes // comments and { } comments that start and end on the line. */
export function stripComment(line: string): string {
  let inString = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "'") {
      inString = !inString;
    } else if (!inString && c === '/' && line[i + 1] === '/') {
      return line.substring(0, i);
    }
  }
  return line.replace(/\{[^}]*\}/g, '');
}

export interface ObjectInfo {
  name: string;
  className: string;
  line: number;
  depth: number;
}

/** The chain of objects that contain the given line (outermost first). */
export function enclosingObjects(lines: string[], lineIndex: number): ObjectInfo[] {
  const stack: ObjectInfo[] = [];
  for (let i = 0; i < lineIndex && i < lines.length; i++) {
    const text = stripComment(lines[i]);
    const m = objectRe.exec(text);
    if (m) {
      stack.push({ name: m[1], className: m[2], line: i, depth: stack.length });
    } else if (endRe.test(text)) {
      stack.pop();
    }
  }
  return stack;
}

/** All objects in the document with their line numbers. */
export function allObjects(lines: string[]): ObjectInfo[] {
  const result: ObjectInfo[] = [];
  let depth = 0;
  lines.forEach((raw, i) => {
    const text = stripComment(raw);
    const m = objectRe.exec(text);
    if (m) {
      result.push({ name: m[1], className: m[2], line: i, depth });
      depth++;
    } else if (endRe.test(text)) {
      depth--;
    }
  });
  return result;
}

export function classFor(schema: Schema, chain: ObjectInfo[]): SchemaClass | undefined {
  if (chain.length === 0) {
    return undefined;
  }
  if (chain.length === 1) {
    return schema.form;
  }
  const name = chain[chain.length - 1].className.toLowerCase();
  return schema.controls.find(c => c.name.toLowerCase() === name);
}

export type CompletionContext =
  | { kind: 'type' }
  | { kind: 'property'; prefix: string }
  | { kind: 'value'; property: string; prefix: string }
  | { kind: 'none' };

/** What the user is typing at the end of `before` (the line up to the cursor). */
export function completionContext(before: string): CompletionContext {
  if (/^\s*object\s+[A-Za-z_]\w*\s*:\s*\w*$/i.test(before)) {
    return { kind: 'type' };
  }
  const value = /^\s*([A-Za-z_]\w*)\s*=\s*(\S*)$/.exec(before);
  if (value) {
    return { kind: 'value', property: value[1], prefix: value[2] };
  }
  const prop = /^\s*([A-Za-z_]\w*)?$/.exec(before);
  if (prop) {
    return { kind: 'property', prefix: prop[1] ?? '' };
  }
  return { kind: 'none' };
}

/** Names of the procedures declared in a Pascal unit (like "SendClick"). */
export function declaredProcedures(pascal: string): string[] {
  const names = new Set<string>();
  const re = /^\s*procedure\s+(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)\s*[(;]/gim;
  let m: RegExpExecArray | null;
  while ((m = re.exec(pascal)) !== null) {
    names.add(m[1]);
  }
  return [...names].sort();
}

export interface Position {
  line: number;
  character: number;
}

/** Where the implementation (or declaration) of a handler is, 0-based. */
export function findProcedure(pascal: string, name: string): Position | undefined {
  const lines = pascal.split(/\r?\n/);
  const impl = new RegExp(`^\\s*procedure\\s+[A-Za-z_]\\w*\\.${name}\\s*[(;]`, 'i');
  const decl = new RegExp(`^\\s*procedure\\s+${name}\\s*[(;]`, 'i');
  let declPos: Position | undefined;
  for (let i = 0; i < lines.length; i++) {
    if (impl.test(lines[i])) {
      return { line: i, character: lines[i].search(/\S/) };
    }
    if (!declPos && decl.test(lines[i])) {
      declPos = { line: i, character: lines[i].search(/\S/) };
    }
  }
  return declPos;
}

export interface TextInsert {
  line: number;   // insert before this 0-based line
  text: string;
}

/**
 * Edits that add an event handler to a form unit: a declaration in the
 * form class and an empty implementation before "end.".
 */
export function handlerInserts(pascal: string, name: string,
  params = '(Sender: TObject)'): TextInsert[] | undefined {
  const lines = pascal.split(/\r?\n/);
  const classRe = /^\s*(T[A-Za-z_]\w*)\s*=\s*class\s*\(\s*T[A-Za-z_]\w*Base\s*\)/i;
  let classLine = -1;
  let className = '';
  for (let i = 0; i < lines.length; i++) {
    const m = classRe.exec(lines[i]);
    if (m) {
      classLine = i;
      className = m[1];
      break;
    }
  }
  if (classLine < 0) {
    return undefined;
  }
  // after the last procedure declared in the class, or right after "class(...)"
  let declLine = classLine + 1;
  for (let i = classLine + 1; i < lines.length; i++) {
    if (/^\s*end\s*;/i.test(lines[i])) {
      break;
    }
    if (/^\s*(procedure|function)\b/i.test(lines[i])) {
      declLine = i + 1;
    }
  }
  let endLine = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (/^\s*end\s*\.\s*$/i.test(lines[i])) {
      endLine = i;
      break;
    }
  }
  if (endLine < 0) {
    return undefined;
  }
  return [
    { line: declLine, text: `    procedure ${name}${params};\n` },
    {
      line: endLine,
      text: `procedure ${className}.${name}${params};\nbegin\n  \nend;\n\n`,
    },
  ];
}

export interface Issue {
  file: string;
  line: number;
  severity: 'error' | 'warning';
  message: string;
}

export function parseIssues(json: string): Issue[] {
  const data = JSON.parse(json);
  if (!Array.isArray(data)) {
    return [];
  }
  return data.filter(
    (i: unknown): i is Issue =>
      typeof i === 'object' && i !== null && typeof (i as Issue).line === 'number' &&
      typeof (i as Issue).message === 'string');
}

/** The handler name from a "is not declared" diagnostic message. */
export function missingHandlerName(message: string): string | undefined {
  const m = /^event handler "([A-Za-z_]\w*)" is not declared/.exec(message);
  return m ? m[1] : undefined;
}

/** The parameter list suggested in a "is not declared" message, e.g. "(Sender: TObject)". */
export function missingHandlerParams(message: string): string {
  const m = /add: procedure [A-Za-z_]\w*(\(.*\));\s*$/.exec(message);
  return m ? m[1] : '(Sender: TObject)';
}
