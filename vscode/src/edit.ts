// Text edits on .pform files for the visual designer: set a property, add,
// move and delete controls. Pure functions on text, unit tested.
import { stripComment } from './model';

export interface PropLine {
  name: string;
  line: number;
  value: string;
}

export interface Block {
  name: string;
  className: string;
  start: number;      // line of "object"
  end: number;        // line of "end"
  indent: number;     // spaces before "object"
  parent?: Block;
  children: Block[];
  props: PropLine[];
}

const objectRe = /^(\s*)object\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)/i;
const endRe = /^\s*end\b/i;
const propRe = /^\s*([A-Za-z_][\w.]*)\s*=\s*(.*?)\s*$/;

function eol(text: string): string {
  return text.includes('\r\n') ? '\r\n' : '\n';
}

function splitLines(text: string): string[] {
  return text.split(/\r?\n/);
}

/** Parses the object tree. Returns undefined if objects and ends do not match. */
export function parseBlocks(text: string): Block | undefined {
  const lines = splitLines(text);
  const stack: Block[] = [];
  let root: Block | undefined;
  for (let i = 0; i < lines.length; i++) {
    const t = stripComment(lines[i]);
    const m = objectRe.exec(t);
    if (m) {
      const b: Block = {
        name: m[2], className: m[3], start: i, end: -1, indent: m[1].replace(/\t/g, '  ').length,
        parent: stack[stack.length - 1], children: [], props: [],
      };
      if (b.parent) {
        b.parent.children.push(b);
      } else if (root) {
        return undefined;
      } else {
        root = b;
      }
      stack.push(b);
      continue;
    }
    if (endRe.test(t)) {
      const b = stack.pop();
      if (!b) {
        return undefined;
      }
      b.end = i;
      continue;
    }
    const p = propRe.exec(t);
    if (p && stack.length > 0) {
      stack[stack.length - 1].props.push({ name: p[1], line: i, value: p[2] });
    }
  }
  if (stack.length > 0 || !root) {
    return undefined;
  }
  return root;
}

export function allBlocks(root: Block): Block[] {
  const out: Block[] = [];
  const walk = (b: Block) => { out.push(b); b.children.forEach(walk); };
  walk(root);
  return out;
}

export function findBlock(root: Block, name: string): Block | undefined {
  return allBlocks(root).find(b => b.name.toLowerCase() === name.toLowerCase());
}

/** Indent step used in the file (2 if it cannot be seen). */
function indentUnit(root: Block): number {
  const child = allBlocks(root).find(b => b.parent);
  if (child && child.indent > child.parent!.indent) {
    return child.indent - child.parent!.indent;
  }
  return 2;
}

/** Sets (value given) or removes (value undefined) a property. `value` is pform text, e.g. 'Hi' or True. */
export function setProperty(text: string, objectName: string, prop: string, value: string | undefined): string {
  const root = parseBlocks(text);
  if (!root) {
    return text;
  }
  const block = findBlock(root, objectName);
  if (!block) {
    return text;
  }
  const lines = splitLines(text);
  const existing = block.props.find(p => p.name.toLowerCase() === prop.toLowerCase());
  const pad = ' '.repeat(block.indent + indentUnit(root));
  if (existing) {
    if (value === undefined) {
      lines.splice(existing.line, 1);
    } else {
      // keep a // comment at the end of the line
      const original = lines[existing.line];
      const code = stripComment(original);
      const comment = code.length < original.length ? ' ' + original.substring(code.length).trim() : '';
      lines[existing.line] = `${pad}${existing.name} = ${value}${comment}`;
    }
  } else if (value !== undefined) {
    const after = block.props.length > 0 ? block.props[block.props.length - 1].line : block.start;
    lines.splice(after + 1, 0, `${pad}${prop} = ${value}`);
  }
  return lines.join(eol(text));
}

/** A free name like Button1, Button2 for a new control. */
export function uniqueName(root: Block, className: string): string {
  const base = className.replace(/^T/i, '') || 'Control';
  const used = new Set(allBlocks(root).map(b => b.name.toLowerCase()));
  for (let n = 1; ; n++) {
    if (!used.has((base + n).toLowerCase())) {
      return base + n;
    }
  }
}

/** Default properties for a new control, so it is visible right away. */
export function defaultProps(className: string, name: string): [string, string][] {
  switch (className.toLowerCase()) {
    case 'tbutton': return [['Text', `'${name}'`]];
    case 'tlabel': return [['Text', `'${name}'`]];
    case 'tedit': return [['Placeholder', `'${name}'`]];
    case 'trow': return [['Gap', '8']];
    case 'tcolumn': return [['Gap', '8']];
    default: return [];
  }
}

function insertionLine(parent: Block, index: number): number {
  return index < parent.children.length ? parent.children[index].start : parent.end;
}

/** Adds a new control as child number `index` of `parentName`. */
export function insertObject(text: string, parentName: string, index: number, className: string):
  { text: string; name: string } | undefined {
  const root = parseBlocks(text);
  const parent = root && findBlock(root, parentName);
  if (!root || !parent) {
    return undefined;
  }
  const unit = indentUnit(root);
  const name = uniqueName(root, className);
  const pad = ' '.repeat(parent.indent + unit);
  const inner = ' '.repeat(parent.indent + 2 * unit);
  const block = [
    `${pad}object ${name}: ${className}`,
    ...defaultProps(className, name).map(([p, v]) => `${inner}${p} = ${v}`),
    `${pad}end`,
  ];
  const lines = splitLines(text);
  lines.splice(insertionLine(parent, index), 0, ...block);
  return { text: lines.join(eol(text)), name };
}

function contains(outer: Block, inner: Block): boolean {
  for (let b: Block | undefined = inner; b; b = b.parent) {
    if (b === outer) {
      return true;
    }
  }
  return false;
}

/**
 * Moves a control to be child number `index` of `parentName`. The index
 * counts the new parent's children without the moved control.
 */
export function moveObject(text: string, name: string, parentName: string, index: number): string {
  const root = parseBlocks(text);
  const block = root && findBlock(root, name);
  const target = root && findBlock(root, parentName);
  if (!root || !block || !target || block === root || contains(block, target)) {
    return text;
  }
  const unit = indentUnit(root);
  const lines = splitLines(text);
  const moved = lines.slice(block.start, block.end + 1);
  const delta = target.indent + unit - block.indent;
  const reindented = moved.map(l => {
    if (delta >= 0) {
      return l.length > 0 ? ' '.repeat(delta) + l : l;
    }
    const lead = l.length - l.trimStart().length;
    return l.substring(Math.min(lead, -delta));
  });
  lines.splice(block.start, block.end - block.start + 1);
  const rest = lines.join(eol(text));
  const root2 = parseBlocks(rest);
  const target2 = root2 && findBlock(root2, parentName);
  if (!target2) {
    return text;
  }
  const lines2 = splitLines(rest);
  lines2.splice(insertionLine(target2, Math.min(index, target2.children.length)), 0, ...reindented);
  return lines2.join(eol(text));
}

export function deleteObject(text: string, name: string): string {
  const root = parseBlocks(text);
  const block = root && findBlock(root, name);
  if (!root || !block || block === root) {
    return text;
  }
  const lines = splitLines(text);
  lines.splice(block.start, block.end - block.start + 1);
  return lines.join(eol(text));
}

/** Turns a value from the property panel into .pform text. */
export function formatValue(type: string, value: string): string | undefined {
  switch (type) {
    case 'string':
      return value === '' ? undefined : `'${value.replace(/'/g, "''")}'`;
    case 'color':
      return /^#[0-9A-Fa-f]{3,8}$/.test(value) ? `'${value.toUpperCase()}'` : undefined;
    case 'integer':
    case 'number':
      return /^-?\d+(\.\d+)?$/.test(value.trim()) ? value.trim() : undefined;
    case 'boolean':
      return value === 'true' || value === 'True' ? 'True' : 'False';
    default:
      return /^[A-Za-z_]\w*$/.test(value.trim()) ? value.trim() : undefined;
  }
}

/** Turns .pform text back into a plain value for the property panel. */
export function parseValue(raw: string): string {
  const t = stripComment(raw).trim();
  if (t.startsWith("'") && t.endsWith("'") && t.length >= 2) {
    return t.substring(1, t.length - 1).replace(/''/g, "'");
  }
  return t;
}
