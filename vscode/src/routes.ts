// Routes and jobs found in Pascal source, and sending HTTP requests to them.
// No VS Code here, so the unit tests can use it.
import * as http from 'http';
import * as https from 'https';

export interface Route {
  method: string;      // GET, POST, ... ; STATIC and HEALTH too
  path: string;
  handler: string;
  line: number;        // 0-based
}

export interface Job {
  schedule: string;    // "every 30 s" or "daily 23:55"
  handler: string;
  line: number;
}

function stripLineComment(line: string): string {
  let inString = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "'") {
      inString = !inString;
    } else if (!inString && c === '/' && line[i + 1] === '/') {
      return line.slice(0, i);
    }
  }
  return line;
}

const routeRe = /\b(?:\w+)\.(Get|Post|Put|Patch|Delete)\(\s*'([^']*)'\s*,\s*@?([\w.]+)/gi;
const staticRe = /\b(?:\w+)\.Static\(\s*'([^']*)'\s*,\s*'([^']*)'/gi;
const healthRe = /\b(?:\w+)\.Health\(\s*'([^']*)'/gi;
const everyRe = /\bEvery\(\s*([\d.]+)\s*,\s*@?([\w.]+)/gi;
const dailyRe = /\bDailyAt\(\s*'([^']*)'\s*,\s*@?([\w.]+)/gi;

export function parseRoutes(text: string): Route[] {
  const out: Route[] = [];
  let inBrace = false;
  text.split(/\r?\n/).forEach((raw, line) => {
    let s = raw;
    // { ... } comments (also over several lines)
    let clean = '';
    for (let i = 0; i < s.length; i++) {
      if (inBrace) {
        if (s[i] === '}') {
          inBrace = false;
        }
      } else if (s[i] === '{' && !(clean.split("'").length % 2 === 0)) {
        inBrace = true;
      } else {
        clean += s[i];
      }
    }
    s = stripLineComment(clean);
    for (const m of s.matchAll(routeRe)) {
      out.push({ method: m[1].toUpperCase(), path: m[2], handler: m[3], line });
    }
    for (const m of s.matchAll(staticRe)) {
      out.push({ method: 'STATIC', path: m[1], handler: m[2], line });
    }
    for (const m of s.matchAll(healthRe)) {
      out.push({ method: 'GET', path: m[1], handler: 'health check', line });
    }
  });
  return out;
}

export function parseJobs(text: string): Job[] {
  const out: Job[] = [];
  text.split(/\r?\n/).forEach((raw, line) => {
    const s = stripLineComment(raw);
    for (const m of s.matchAll(everyRe)) {
      out.push({ schedule: `every ${m[1]} s`, handler: m[2], line });
    }
    for (const m of s.matchAll(dailyRe)) {
      out.push({ schedule: `daily ${m[1]}`, handler: m[2], line });
    }
  });
  return out;
}

// ":id" and "*" parts of a route path
export function pathParams(path: string): string[] {
  const out: string[] = [];
  for (const part of path.split('/')) {
    if (part.startsWith(':')) {
      out.push(part.slice(1));
    } else if (part === '*') {
      out.push('*');
    }
  }
  return out;
}

export function fillPath(path: string, values: Record<string, string>): string {
  return path.split('/').map(part => {
    if (part.startsWith(':')) {
      return encodeURIComponent(values[part.slice(1)] ?? '');
    }
    if (part === '*') {
      return values['*'] ?? '';
    }
    return part;
  }).join('/');
}

// [server] port and the first [api] keys entry of a config.toml (development settings)
export function devSettings(toml: string): { port?: number; apiKey?: string } {
  let section = '';
  const result: { port?: number; apiKey?: string } = {};
  for (const raw of toml.split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, '').trim();
    const sec = /^\[([^\]]+)\]$/.exec(line);
    if (sec) {
      section = sec[1].trim();
      continue;
    }
    const kv = /^([\w.]+)\s*=\s*(.+)$/.exec(line);
    if (!kv) {
      continue;
    }
    if (section === 'server' && kv[1] === 'port') {
      const n = parseInt(kv[2], 10);
      if (!isNaN(n)) {
        result.port = n;
      }
    }
    if (section === 'api' && kv[1] === 'keys') {
      const first = /"([^"]*)"/.exec(kv[2]);
      if (first && !/change-me/i.test(first[1])) {
        result.apiKey = first[1];
      }
    }
  }
  return result;
}

export interface HttpResult {
  status: number;
  statusText: string;
  headers: Record<string, string>;
  body: string;
  ms: number;
}

export function sendHttp(method: string, url: string, headers: Record<string, string>, body?: string,
  timeoutMs = 30000): Promise<HttpResult> {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const u = new URL(url);
    const lib = u.protocol === 'https:' ? https : http;
    const h: Record<string, string> = { ...headers };
    if (body !== undefined && body !== '') {
      h['Content-Length'] = String(Buffer.byteLength(body));
    }
    const req = lib.request(u, { method, headers: h, timeout: timeoutMs }, res => {
      const chunks: Buffer[] = [];
      res.on('data', c => chunks.push(c as Buffer));
      res.on('end', () => {
        const out: Record<string, string> = {};
        for (const [k, v] of Object.entries(res.headers)) {
          out[k] = Array.isArray(v) ? v.join(', ') : String(v ?? '');
        }
        resolve({
          status: res.statusCode ?? 0, statusText: res.statusMessage ?? '', headers: out,
          body: Buffer.concat(chunks).toString('utf8'), ms: Date.now() - started,
        });
      });
    });
    req.on('timeout', () => req.destroy(new Error(`no answer after ${timeoutMs / 1000} s`)));
    req.on('error', reject);
    if (body !== undefined && body !== '') {
      req.write(body);
    }
    req.end();
  });
}

// A readable report: status line, headers, and the body (JSON pretty-printed)
export function formatResult(method: string, url: string, r: HttpResult): string {
  let body = r.body;
  if ((r.headers['content-type'] ?? '').includes('json')) {
    try {
      body = JSON.stringify(JSON.parse(r.body), null, 2);
    } catch {
      // keep as it came
    }
  }
  const head = Object.entries(r.headers).map(([k, v]) => `${k}: ${v}`).join('\n');
  return `${method} ${url}\nHTTP ${r.status} ${r.statusText} (${r.ms} ms)\n${head}\n\n${body}\n`;
}
