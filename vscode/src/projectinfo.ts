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
  platforms: string[];     // [targets] platforms
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
  const list = section('targets').match(/^\s*platforms\s*=\s*\[([^\]]*)\]/m);
  const platforms = list ? [...list[1].matchAll(/"([^"]+)"/g)].map(m => m[1]) : [];
  return {
    root, name: value(project, 'name') || path.basename(root), kind: value(project, 'type') || 'console', dependsOn: deps,
    platforms,
  };
}

/** The platforms a project can be built for, as the target picker shows them. */
export const PLATFORMS: { label: string; description: string }[] = [
  { label: 'linux', description: 'Linux, 64-bit PC' },
  { label: 'windows', description: 'Windows, 64-bit' },
  { label: 'windows32', description: 'Windows, 32-bit' },
  { label: 'rpi', description: 'Raspberry Pi, 64-bit OS' },
  { label: 'rpi32', description: 'Raspberry Pi, 32-bit OS' },
  { label: 'macos', description: 'macOS, Intel' },
  { label: 'macos-arm64', description: 'macOS, Apple Silicon' },
  { label: 'android', description: 'Android: every CPU set up (one .apk); F9 runs on the connected phone or emulator' },
  { label: 'android-arm64', description: 'Android, ARM 64-bit (most phones)' },
  { label: 'android-arm', description: 'Android, ARM 32-bit (older phones, TV boxes)' },
  { label: 'android-x86_64', description: 'Android x86 64-bit (the emulator on a PC)' },
  { label: 'android-x86', description: 'Android x86 32-bit (older emulators)' },
];

const ALIASES: Record<string, string> = { win: 'windows', win64: 'windows', win32: 'windows32', rpi64: 'rpi', 'linux-arm64': 'rpi', 'linux-arm': 'rpi32' };

function canonical(p: string): string {
  return ALIASES[p.toLowerCase()] ?? p.toLowerCase();
}

export function isAndroid(platform: string): boolean {
  return platform.toLowerCase().startsWith('android');
}

/**
 * The platform F9 and Ctrl+F9 use when none was chosen: this computer when
 * the project is made for it (or names no platforms); a phone app (platforms
 * = ["android"]) uses Android.
 */
export function defaultPlatform(info: ProjectInfo | undefined, host: string): string {
  const list = (info?.platforms ?? []).map(canonical);
  if (list.length === 0 || list.includes(canonical(host))) {
    return host;
  }
  return list.find(isAndroid) ?? host;
}

/**
 * What F9 (run) and Ctrl+F9 (build) do for a platform: the pastel command and
 * its arguments, and a note when the program cannot run here.
 */
export function platformCommand(action: 'run' | 'build', platform: string, host: string, release = false):
  { args: string[]; note?: string } {
  const p = canonical(platform);
  const rel = release ? ['--release'] : [];
  if (isAndroid(p)) {
    // F9: on the connected phone (its CPU decides); Ctrl+F9: one .apk with every CPU set up
    if (action === 'run') {
      return { args: ['run', '--target', p, ...rel] };
    }
    return { args: ['package', 'apk', ...(p === 'android' ? [] : ['--target', p])] };
  }
  if (p === canonical(host)) {
    return { args: [action, ...rel] };
  }
  if (action === 'run') {
    return {
      args: ['build', '--target', p, ...rel],
      note: `a ${p} program cannot run on this computer: it is built in build/${p}/; copy it to a ${p} computer to run it`,
    };
  }
  return { args: ['build', '--target', p, ...rel] };
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

/** Width and height of a PNG file (from its IHDR chunk), undefined when it is not a PNG. */
export function pngSize(data: Buffer): { width: number; height: number } | undefined {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (data.length < 24 || !data.subarray(0, 8).equals(sig) || data.toString('ascii', 12, 16) !== 'IHDR') {
    return undefined;
  }
  return { width: data.readUInt32BE(16), height: data.readUInt32BE(20) };
}
