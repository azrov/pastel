// Writes the API reference of the Pastel framework (docs/api/*.md) from the
// declarations and documentation comments of framework/src.
//   node out/lang/apidoc.js ../framework/src ../docs/api
import * as fs from 'fs';
import * as path from 'path';
import { lex } from './lexer';
import { Decl, parseUnit } from './parser';
import { signature } from './analyzer';

function anchor(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

function docText(d: Decl): string {
  return d.doc ? d.doc.replace(/\n{2,}/g, '\n\n') + '\n' : '';
}

function isPublic(m: Decl): boolean {
  return !m.visibility || !/private|protected|strict/.test(m.visibility);
}

function typeSection(d: Decl): string {
  let out = `### ${d.name}\n\n\`\`\`pascal\n${signature(d)}\n\`\`\`\n\n${docText(d)}`;
  if (d.kind === 'enum') {
    const vals = (d.members ?? []).map(m => `\`${m.name}\`${m.doc ? ' ' + m.doc.replace(/\n/g, ' ') : ''}`);
    return out + (vals.length ? '\n' + vals.map(v => `- ${v}`).join('\n') + '\n' : '');
  }
  const members = (d.members ?? []).filter(m => isPublic(m) && m.kind !== 'field' || (m.kind === 'field' && isPublic(m) && d.kind === 'record'));
  const rows = members.filter(m => !/^F[A-Z]/.test(m.name) || d.kind === 'record');
  if (rows.length) {
    out += '\n| | |\n|---|---|\n';
    for (const m of rows) {
      const sig = signature(m).replace(`${d.name}.`, '').replace(/\|/g, '\\|');
      out += `| \`${sig}\` | ${(m.doc ?? '').replace(/\n/g, ' ').replace(/\|/g, '\\|')} |\n`;
    }
  }
  return out + '\n';
}

export function unitMarkdown(file: string): { name: string; markdown: string; summary: string } | undefined {
  const text = fs.readFileSync(file, 'utf8');
  const lexed = lex(text);
  const unit = parseUnit(lexed, file, text);
  if (!unit.name || unit.isProgram) {
    return undefined;
  }
  // the unit's own comment: the first comment in the file
  const first = lexed.comments[0]?.text.replace(/\n\s*Part of the Pastel project.*$/s, '').trim() ?? '';
  const line1 = first.split('\n')[0].replace(/^Pastel - /, '');
  const summary = line1.charAt(0).toUpperCase() + line1.slice(1);
  const decls = unit.interfaceDecls;
  const types = decls.filter(d => ['class', 'record', 'interface', 'object', 'enum'].includes(d.kind) && !d.forward);
  const aliases = decls.filter(d => d.kind === 'type');
  const routines = decls.filter(d => d.kind === 'routine');
  const consts = decls.filter(d => d.kind === 'const' || d.kind === 'var');
  const intro = first.replace(/^Pastel - /, '');
  let md = `# ${unit.name}\n\n${intro.charAt(0).toUpperCase() + intro.slice(1)}\n\n`;
  md += `\`uses ${unit.name};\` · source: [framework/src/${path.basename(file)}](../../framework/src/${path.basename(file)})\n\n`;
  if (types.length + routines.length > 6) {
    md += '**Contents:** ' + [...types, ...routines].map(d => `[${d.name}](#${anchor(d.name)})`).join(' · ') + '\n\n';
  }
  if (types.length) {
    md += '## Types\n\n' + types.map(typeSection).join('');
  }
  if (aliases.length) {
    md += '## Other types\n\n| | |\n|---|---|\n' +
      aliases.map(d => `| \`${signature(d).replace(/\|/g, '\\|')}\` | ${(d.doc ?? '').replace(/\n/g, ' ')} |`).join('\n') + '\n\n';
  }
  if (routines.length) {
    md += '## Routines\n\n' + routines.map(d => `### ${d.name}\n\n\`\`\`pascal\n${signature(d)}\n\`\`\`\n\n${docText(d)}\n`).join('');
  }
  if (consts.length) {
    md += '## Constants and variables\n\n| | |\n|---|---|\n' +
      consts.map(d => `| \`${signature(d).replace(/\|/g, '\\|')}\` | ${(d.doc ?? '').replace(/\n/g, ' ')} |`).join('\n') + '\n';
  }
  return { name: unit.name, markdown: md.replace(/\n{3,}/g, '\n\n'), summary };
}

export function writeApiDocs(srcDir: string, outDir: string): string[] {
  fs.mkdirSync(outDir, { recursive: true });
  const index: string[] = [];
  const written: string[] = [];
  for (const f of fs.readdirSync(srcDir).filter(n => /\.(pas|pp)$/i.test(n)).sort()) {
    const r = unitMarkdown(path.join(srcDir, f));
    if (!r || /^Pastel\.(Startup|ErrorExit|SDL2|FreeType)$/i.test(r.name)) {
      continue;
    }
    const out = path.join(outDir, r.name.toLowerCase() + '.md');
    fs.writeFileSync(out, r.markdown);
    written.push(out);
    index.push(`| [${r.name}](${path.basename(out)}) | ${r.summary} |`);
  }
  fs.writeFileSync(path.join(outDir, 'README.md'),
    '# Pastel API reference\n\nMade from the declarations and comments in `framework/src` ' +
    '(`npm run apidoc` in `vscode/`). The guides in [docs/](..) explain how the parts fit together.\n\n' +
    '| Unit | |\n|---|---|\n' + index.join('\n') + '\n');
  return written;
}

if (require.main === module) {
  const [src, out] = process.argv.slice(2);
  const files = writeApiDocs(src ?? '../framework/src', out ?? '../docs/api');
  console.log(`apidoc: ${files.length} units`);
}
