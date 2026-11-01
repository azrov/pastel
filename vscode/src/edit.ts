// Text edits on .pform files for the visual designer: set a property, add,
// move and delete controls. Pure functions on text, unit tested.
import { stripComment } from './model';
import { lex } from './lang/lexer';

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

/** The text of a control with its children, without the indentation of its place (for copying). */
export function extractObject(text: string, name: string): string | undefined {
  const root = parseBlocks(text);
  const block = root && findBlock(root, name);
  if (!root || !block || block === root) {
    return undefined;
  }
  const lines = splitLines(text).slice(block.start, block.end + 1);
  return lines.map(l => l.substring(Math.min(block.indent, l.length - l.trimStart().length))).join('\n');
}

/** True for text that is one or more .pform objects (from the clipboard). */
export function isObjectText(clip: string): boolean {
  const wrapped = `object X__: TForm\n${clip}\nend`;
  const root = parseBlocks(wrapped);
  return !!root && root.children.length > 0 && /^\s*object\s/i.test(clip);
}

/**
 * Pastes copied objects as children of `parentName` at `index`. Names that
 * are taken get a free number (Button1 -> Button2). Returns the new text
 * and the name of the first pasted control.
 */
export function pasteObjects(text: string, clip: string, parentName: string, index: number):
  { text: string; name: string } | undefined {
  const root = parseBlocks(text);
  const parent = root && findBlock(root, parentName);
  if (!root || !parent || !isObjectText(clip)) {
    return undefined;
  }
  const used = new Set(allBlocks(root).map(b => b.name.toLowerCase()));
  let first = '';
  const renamed = clip.split(/\r?\n/).map(line => {
    const m = /^(\s*object\s+)([A-Za-z_]\w*)(\s*:.*)$/i.exec(line);
    if (!m) {
      return line;
    }
    let name = m[2];
    if (used.has(name.toLowerCase())) {
      const base = name.replace(/\d+$/, '');
      for (let n = 1; ; n++) {
        if (!used.has((base + n).toLowerCase())) {
          name = base + n;
          break;
        }
      }
    }
    used.add(name.toLowerCase());
    first ||= name;
    return m[1] + name + m[3];
  });
  const pad = ' '.repeat(parent.indent + indentUnit(root));
  const lines = splitLines(text);
  lines.splice(insertionLine(parent, Math.min(index, parent.children.length)), 0,
    ...renamed.map(l => (l.trim() === '' ? l : pad + l)));
  return { text: lines.join(eol(text)), name: first };
}

/** Renames a control in the .pform; undefined when the name is not usable. */
export function renameObject(text: string, oldName: string, newName: string): string | undefined {
  const root = parseBlocks(text);
  const block = root && findBlock(root, oldName);
  if (!root || !block || !/^[A-Za-z_]\w*$/.test(newName)) {
    return undefined;
  }
  if (newName.toLowerCase() !== oldName.toLowerCase() && findBlock(root, newName)) {
    return undefined;
  }
  const lines = splitLines(text);
  lines[block.start] = lines[block.start].replace(new RegExp(`(object\\s+)${oldName}\\b`, 'i'), `$1${newName}`);
  return lines.join(eol(text));
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
    case 'set': {
      // Anchors: [Left, Top, Right]
      const names = value.trim().replace(/^\[|\]$/g, '').split(',').map(n => n.trim()).filter(n => n !== '');
      return names.every(n => /^[A-Za-z_]\w*$/.test(n)) ? `[${names.join(', ')}]` : undefined;
    }
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

/** Renames an identifier in Pascal code (not in strings or comments). */
export function renameIdentifier(pas: string, oldName: string, newName: string): string {
  const lines = pas.split('\n');
  const hits = lex(pas).tokens.filter(t => t.kind === 'ident' && !t.file && t.lower === oldName.toLowerCase());
  for (const t of hits.reverse()) {
    const l = lines[t.line];
    lines[t.line] = l.substring(0, t.col) + newName + l.substring(t.col + t.text.length);
  }
  return lines.join('\n');
}

/**
 * Puts controls that have the same parent into a new container (TRow,
 * TColumn, TCard...) at the place of the first one. Returns the new text and
 * the container's name; undefined when they do not share a parent.
 */
export function wrapObjects(text: string, names: string[], className: string):
  { text: string; name: string } | undefined {
  const root = parseBlocks(text);
  if (!root || names.length === 0) {
    return undefined;
  }
  const blocks = names.map(n => findBlock(root, n));
  if (blocks.some(b => !b || b === root)) {
    return undefined;
  }
  const parent = blocks[0]!.parent!;
  if (blocks.some(b => b!.parent !== parent)) {
    return undefined;
  }
  // in the order they have in the file
  const ordered = (blocks as Block[]).sort((a, b) => a.start - b.start);
  const index = parent.children.indexOf(ordered[0]);
  const added = insertObject(text, parent.name, index, className);
  if (!added) {
    return undefined;
  }
  let out = added.text;
  ordered.forEach((b, i) => {
    out = moveObject(out, b.name, added.name, i);
  });
  return { text: out, name: added.name };
}

/** Takes the children out of a container (to its place in its parent) and removes it. */
export function unwrapObject(text: string, name: string): string {
  const root = parseBlocks(text);
  const block = root && findBlock(root, name);
  if (!root || !block || block === root || !block.parent) {
    return text;
  }
  const parentName = block.parent.name;
  let index = block.parent.children.indexOf(block);
  const kids = block.children.map(c => c.name);
  let out = text;
  for (const k of kids) {
    out = moveObject(out, k, parentName, index);
    index++;
  }
  return deleteObject(out, name);
}

/** Moves a control one place earlier (-1) or later (+1) among its siblings. */
export function moveSibling(text: string, name: string, delta: number): string {
  const root = parseBlocks(text);
  const block = root && findBlock(root, name);
  if (!root || !block || !block.parent) {
    return text;
  }
  const i = block.parent.children.indexOf(block) + delta;
  if (i < 0 || i >= block.parent.children.length) {
    return text;
  }
  return moveObject(text, name, block.parent.name, i);
}

/** Several controls as clipboard text, in the order of the file; ones inside another are left out. */
export function extractObjects(text: string, names: string[]): string | undefined {
  const root = parseBlocks(text);
  if (!root) {
    return undefined;
  }
  const blocks = names.map(n => findBlock(root, n)).filter((b): b is Block => !!b && b !== root);
  const top = blocks.filter(b => !blocks.some(o => o !== b && contains(o, b)));
  const parts = top.sort((a, b) => a.start - b.start).map(b => extractObject(text, b.name)!);
  return parts.length ? parts.join('\n') : undefined;
}

/** Removes several controls. */
export function deleteObjects(text: string, names: string[]): string {
  let out = text;
  for (const n of names) {
    out = deleteObject(out, n);
  }
  return out;
}

/** The objects of the form as a list for the structure view: name, class, depth. */
export function outline(text: string): { name: string; className: string; depth: number }[] {
  const root = parseBlocks(text);
  const out: { name: string; className: string; depth: number }[] = [];
  const walk = (b: Block, d: number) => {
    out.push({ name: b.name, className: b.className, depth: d });
    b.children.forEach(c => walk(c, d + 1));
  };
  if (root) {
    walk(root, 0);
  }
  return out;
}

/** A place in a parent with Layout = Free; a size of 0 (or a place of 0) is the default and is not written. */
export interface Placement {
  name: string;
  left?: number;
  top?: number;
  width?: number;
  height?: number;
}

function setNumber(text: string, name: string, prop: string, v: number | undefined): string {
  if (v === undefined) {
    return text;
  }
  const n = Math.round(v);
  return setProperty(text, name, prop, n === 0 ? undefined : String(n));
}

/** Moves controls into `parentName` (when given and different) and sets Left, Top, Width, Height: one edit. */
export function placeObjects(text: string, parentName: string | undefined, items: Placement[]): string {
  let out = text;
  for (const it of items) {
    const root = parseBlocks(out);
    const b = root && findBlock(root, it.name);
    if (!root || !b) {
      continue;
    }
    if (parentName && b.parent && b.parent.name.toLowerCase() !== parentName.toLowerCase()) {
      const parent = findBlock(root, parentName);
      if (!parent || parent === b || isInsideBlock(parent, b)) {
        continue;
      }
      out = moveObject(out, it.name, parentName, parent.children.length);
    }
    out = setNumber(out, it.name, 'Left', it.left);
    out = setNumber(out, it.name, 'Top', it.top);
    out = setNumber(out, it.name, 'Width', it.width);
    out = setNumber(out, it.name, 'Height', it.height);
  }
  return out;
}

function isInsideBlock(b: Block, ancestor: Block): boolean {
  for (let p: Block | undefined = b; p; p = p.parent) {
    if (p === ancestor) {
      return true;
    }
  }
  return false;
}

const containerClasses = /^(TPanel|TCard|TColumn|TRow|TFlow|TScrollBox|TTabControl|TToolBar|TStatusBar)$/i;

/** Adds a new control at a place in a parent with Layout = Free (containers get a size to draw). */
export function insertObjectAt(text: string, parentName: string, className: string, left: number, top: number):
  { text: string; name: string } | undefined {
  const r = insertObject(text, parentName, 1 << 20, className);
  if (!r) {
    return undefined;
  }
  const size = containerClasses.test(className) ? { width: 200, height: 120 } : {};
  return { name: r.name, text: placeObjects(r.text, undefined, [{ name: r.name, left, top, ...size }]) };
}
