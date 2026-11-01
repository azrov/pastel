// What pastel.toml files say about the projects of a workspace, and which
// program F9 should run. No VS Code here, so it can be tested alone.
import * as fs from 'fs';
import * as path from 'path';

/** What a pastel.toml says about the project: its kind and the projects it depends on. */
export interface ProjectInfo {
  root: string;
  name: string;
  kind: string;            // console, app, service, lib
  dependsOn: string[];     // absolute roots of [dependencies]
}

export function parseProjectInfo(root: string, text: string): ProjectInfo {
  const section = (name: string) => {
    const m = text.match(new RegExp(`^\\[${name}\\]\\s*$([\\s\\S]*?)(?=^\\[|(?![\\s\\S]))`, 'm'));
    return m ? m[1] : '';
  };
  const project = section('project');
  const value = (src: string, key: string) => src.match(new RegExp(`^\\s*${key}\\s*=\\s*"([^"]*)"`, 'm'))?.[1] ?? '';
  const deps: string[] = [];
  for (const m of section('dependencies').matchAll(/path\s*=\s*"([^"]+)"/g)) {
    deps.push(path.resolve(root, m[1]));
  }
  return { root, name: value(project, 'name') || path.basename(root), kind: value(project, 'type') || 'console', dependsOn: deps };
}

export function readProjectInfo(root: string): ProjectInfo | undefined {
  try {
    return parseProjectInfo(root, fs.readFileSync(path.join(root, 'pastel.toml'), 'utf8'));
  } catch {
    return undefined;
  }
}

/**
 * The programs F9 may run: the active project when it is a program; for a
 * library, the programs that use it (all programs when none does); with no
 * active project, every program.
 */
export function runCandidates(all: ProjectInfo[], active: ProjectInfo | undefined): ProjectInfo[] {
  if (active && active.kind !== 'lib') {
    return [active];
  }
  const programs = all.filter(p => p.kind !== 'lib');
  if (active?.kind === 'lib') {
    const users = programs.filter(p => p.dependsOn.some(d => path.resolve(d) === path.resolve(active.root)));
    if (users.length > 0) {
      return users;
    }
  }
  return programs;
}
