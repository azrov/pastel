// Finding tests in Pascal test units, without VS Code: the Testing view
// shows what this returns. The ids are the ones "pastel test" uses
// (TGreetingTests.GreetsByName, or the name given to Test(...)).

export interface FoundTest {
  id: string;          // as in "pastel test --json"
  label: string;       // as the runner prints it: "greets by name"
  line: number;        // 0-based, the method's declaration
}

export interface FoundSuite {
  className: string;   // TGreetingTests
  label: string;       // Greeting
  line: number;
  tests: FoundTest[];
}

export interface FoundTests {
  suites: FoundSuite[];
  loose: FoundTest[];  // Test('name', @Proc)
}

/** "GreetsByName" -> "greets by name", "ParsesHTTPHeaders" -> "parses HTTP headers" */
export function humanName(identifier: string): string {
  let out = '';
  for (let i = 0; i < identifier.length; i++) {
    const c = identifier[i];
    if (c === '_') {
      out += ' ';
      continue;
    }
    const prev = identifier[i - 1] ?? '';
    const next = identifier[i + 1] ?? '';
    if (i > 0 && /[A-Z]/.test(c) && (/[a-z0-9]/.test(prev) || (/[a-z]/.test(next) && /[A-Z]/.test(prev)))) {
      out += ' ';
    }
    out += c;
  }
  return out.trim().split(' ').filter(w => w !== '')
    .map(w => (w.length < 2 || w.toUpperCase() !== w ? w.toLowerCase() : w)).join(' ');
}

/** TGreetingTests -> Greeting */
export function suiteLabel(className: string): string {
  let n = className;
  if (n.length > 1 && n[0] === 'T' && /[A-Z]/.test(n[1])) {
    n = n.substring(1);
  }
  if (n.length > 5 && n.endsWith('Tests')) {
    n = n.substring(0, n.length - 5);
  } else if (n.length > 4 && n.endsWith('Test')) {
    n = n.substring(0, n.length - 4);
  }
  const h = humanName(n);
  return h.charAt(0).toUpperCase() + h.substring(1);
}

/** Blanks out comments and strings, keeping line and column positions. */
function stripCode(text: string): string {
  let out = '';
  let i = 0;
  while (i < text.length) {
    const c = text[i];
    const two = text.substr(i, 2);
    let end = -1;
    if (two === '//') {
      end = text.indexOf('\n', i);
      if (end < 0) end = text.length;
    } else if (c === '{') {
      end = text.indexOf('}', i);
      end = end < 0 ? text.length : end + 1;
    } else if (two === '(*') {
      end = text.indexOf('*)', i + 2);
      end = end < 0 ? text.length : end + 2;
    } else if (c === "'") {
      // keep strings: Test('name') needs them; but blank comment-like text inside
      end = i + 1;
      while (end < text.length && text[end] !== '\n') {
        if (text[end] === "'") {
          if (text[end + 1] === "'") { end += 2; continue; }
          end++;
          break;
        }
        end++;
      }
      out += text.substring(i, end);
      i = end;
      continue;
    }
    if (end >= 0) {
      out += text.substring(i, end).replace(/[^\n]/g, ' ');
      i = end;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

export function findTests(text: string): FoundTests {
  const lines = stripCode(text).split('\n');
  const result: FoundTests = { suites: [], loose: [] };
  let suite: FoundSuite | undefined;
  let published = false;
  for (let n = 0; n < lines.length; n++) {
    const line = lines[n];
    const head = /^\s*(\w+)\s*=\s*class\s*\(\s*TTestSuite\s*\)/i.exec(line);
    if (head) {
      suite = { className: head[1], label: suiteLabel(head[1]), line: n, tests: [] };
      result.suites.push(suite);
      published = false;
      continue;
    }
    if (suite) {
      if (/^\s*end\s*;/i.test(line)) {
        suite = undefined;
        continue;
      }
      if (/^\s*published\b/i.test(line)) {
        published = true;
        continue;
      }
      if (/^\s*(strict\s+)?(private|protected|public)\b/i.test(line)) {
        published = false;
        continue;
      }
      const m = /^\s*procedure\s+(\w+)\s*;/i.exec(line);
      if (m && published) {
        suite.tests.push({ id: `${suite.className}.${m[1]}`, label: humanName(m[1]), line: n });
      }
      continue;
    }
    const re = /\bTest\s*\(\s*'((?:[^']|'')*)'/gi;
    let t: RegExpExecArray | null;
    while ((t = re.exec(line)) !== null) {
      const name = t[1].replace(/''/g, "'");
      result.loose.push({ id: name, label: name, line: n });
    }
  }
  return result;
}

export interface TestResult {
  id: string;
  outcome: 'passed' | 'failed' | 'error' | 'skipped';
  ms: number;
  message: string;
  location: string;    // "tests/greeting_test.pas:12", or ''
}

/** The results in "pastel test --json" output (after any compiler lines). */
export function parseResults(output: string): TestResult[] | undefined {
  const lines = output.split(/\r?\n/).filter(l => l.trim() !== '');
  for (let i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trimStart().startsWith('[')) {
      try {
        return JSON.parse(lines[i]) as TestResult[];
      } catch {
        return undefined;
      }
    }
  }
  return undefined;
}

/** "tests/greeting_test.pas:12" -> file and 0-based line */
export function parseLocation(location: string): { file: string; line: number } | undefined {
  const m = /^(.*):(\d+)$/.exec(location);
  return m ? { file: m[1], line: Number(m[2]) - 1 } : undefined;
}
