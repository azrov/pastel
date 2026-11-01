// The Welcome page and the New Project wizard, like Android Studio's: recent
// projects on the first page, then a gallery of project templates in groups,
// then the name, the folder and the platforms. Kept apart from VS Code so it
// can be tested in a browser-like environment.

/** A kind of project `pastel new` makes. */
export interface ProjectTemplate {
  kind: string;            // the argument of "pastel new"
  category: string;
  title: string;
  description: string;
  icon: string;
  platforms: string[];     // where it runs
  forms: boolean;          // has windows and the designer
  soon?: string;           // not there yet: when it comes
}

export const TEMPLATES: ProjectTemplate[] = [
  { kind: 'app', category: 'Desktop', title: 'Desktop App', icon: '🪟', platforms: ['Windows', 'Linux'], forms: true,
    description: 'A program with windows: forms you design by dragging controls, menus, dialogs, grids.' },
  { kind: 'console', category: 'Console', title: 'Console Program', icon: '⌨', platforms: ['Windows', 'Linux'], forms: false,
    description: 'A program for the terminal: arguments and options, text in and out, files. No windows.' },
  { kind: 'api', category: 'Server', title: 'Web API', icon: '🌐', platforms: ['Linux', 'Windows'], forms: false,
    description: 'A REST API with a database: models, controllers, migrations and tests.' },
  { kind: 'service', category: 'Server', title: 'Service', icon: '⚙', platforms: ['Linux', 'Windows'], forms: false,
    description: 'Keeps running in the background: jobs on a timer, settings, logs; a systemd or Windows service.' },
  { kind: 'lib', category: 'Library', title: 'Library', icon: '📦', platforms: ['Windows', 'Linux'], forms: false,
    description: 'Units (and controls) that other projects use, with tests; shared with "pastel add".' },
  { kind: 'android', category: 'Mobile', title: 'Android App', icon: '📱', platforms: ['Android'], forms: true, soon: 'Pastel 1.5',
    description: 'The same forms and code on phones and tablets.' },
];

export const CATEGORIES = ['Desktop', 'Console', 'Server', 'Library', 'Mobile'];

export interface RecentProject { name: string; path: string; kind: string }

/** Whether a project name can be used: a folder name and a Pascal-friendly name. */
export function validProjectName(name: string): string | undefined {
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(name)) {
    return 'Start with a letter; use letters, digits, "-" and "_".';
  }
  return undefined;
}

/** pastel.toml with the platforms chosen in the wizard ("platforms = [...]" under [targets]). */
export function withPlatforms(toml: string, platforms: string[]): string {
  const list = platforms.map(p => `"${p.toLowerCase()}"`).join(', ');
  return /^platforms\s*=.*$/m.test(toml) ? toml.replace(/^platforms\s*=.*$/m, `platforms = [${list}]`) : toml;
}

export function welcomeHtml(nonce: string, data: { recent: RecentProject[]; location: string; version: string }): string {
  const json = JSON.stringify({ templates: TEMPLATES, categories: CATEGORIES, ...data }).replace(/</g, '\\u003c');
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<style>
  html, body { height: 100%; }
  body { margin: 0; font-family: var(--vscode-font-family); font-size: 13px; color: var(--vscode-foreground);
    background: var(--vscode-editor-background); display: flex; }
  nav { width: 210px; flex: none; padding: 22px 12px; border-right: 1px solid var(--vscode-panel-border);
    background: var(--vscode-sideBar-background, var(--vscode-editor-background)); }
  nav .brand { font-size: 18px; font-weight: 600; padding: 0 8px 4px; }
  nav .ver { opacity: .6; font-size: 12px; padding: 0 8px 18px; }
  nav button.nav { display: block; width: 100%; text-align: left; background: none; color: var(--vscode-foreground); border: none;
    padding: 6px 8px; border-radius: 4px; cursor: pointer; font: inherit; }
  nav button.nav.on { background: var(--vscode-list-activeSelectionBackground); color: var(--vscode-list-activeSelectionForeground); }
  main { flex: 1; overflow: auto; padding: 22px 28px; }
  h1 { font-size: 20px; font-weight: 600; margin: 0 0 4px; }
  .sub { opacity: .75; margin-bottom: 18px; }
  .actions { display: flex; gap: 8px; margin-bottom: 20px; flex-wrap: wrap; }
  button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 6px 14px;
    cursor: pointer; font: inherit; border-radius: 3px; }
  button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
  button:disabled { opacity: .5; cursor: default; }
  .recent .p { display: flex; gap: 10px; align-items: center; padding: 8px 10px; border-radius: 4px; cursor: pointer; }
  .recent .p:hover { background: var(--vscode-list-hoverBackground); }
  .recent .p .i { width: 28px; height: 28px; border-radius: 6px; display: grid; place-items: center; font-weight: 600;
    background: var(--vscode-button-secondaryBackground); }
  .recent .p .n { font-weight: 600; }
  .recent .p .d { opacity: .65; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .recent .p .k { margin-left: auto; opacity: .6; font-size: 12px; }
  .empty { opacity: .7; padding: 8px 0; }
  .wizard { display: grid; grid-template-columns: 170px 1fr; gap: 18px; }
  .cats button { display: block; width: 100%; text-align: left; background: none; color: var(--vscode-foreground); padding: 6px 10px; }
  .cats button.on { background: var(--vscode-list-activeSelectionBackground); color: var(--vscode-list-activeSelectionForeground); }
  .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 12px; align-content: start; }
  .card { border: 1px solid var(--vscode-panel-border); border-radius: 8px; padding: 14px; cursor: pointer; min-height: 120px;
    display: flex; flex-direction: column; gap: 6px; }
  .card:hover { border-color: var(--vscode-focusBorder); }
  .card.on { outline: 2px solid var(--vscode-focusBorder); border-color: transparent; }
  .card.soon { opacity: .55; cursor: default; }
  .card .ic { font-size: 26px; line-height: 30px; }
  .card .t { font-weight: 600; }
  .card .ds { opacity: .8; font-size: 12px; line-height: 1.4; flex: 1; }
  .card .pl { font-size: 11px; opacity: .7; }
  .foot { display: flex; gap: 8px; justify-content: flex-end; margin-top: 20px; align-items: center; }
  .foot .msg { margin-right: auto; opacity: .8; }
  .foot .msg.err { color: var(--vscode-errorForeground, #f14c4c); opacity: 1; white-space: pre-wrap; }
  .form { max-width: 560px; display: grid; grid-template-columns: 120px 1fr; gap: 10px 14px; align-items: center; }
  .form .hint { grid-column: 2; font-size: 12px; opacity: .7; margin-top: -6px; }
  .form .bad { grid-column: 2; font-size: 12px; color: var(--vscode-errorForeground, #f14c4c); margin-top: -6px; }
  input[type=text] { width: 100%; box-sizing: border-box; background: var(--vscode-input-background); color: var(--vscode-input-foreground);
    border: 1px solid var(--vscode-input-border, transparent); padding: 5px 7px; font: inherit; }
  .loc { display: flex; gap: 6px; }
  .checks { display: flex; gap: 16px; }
  .checks label { display: inline-flex; gap: 4px; align-items: center; }
  .chosen { display: flex; gap: 10px; align-items: center; margin-bottom: 16px; }
  .chosen .ic { font-size: 26px; }
  .steps { display: flex; gap: 6px; font-size: 12px; opacity: .75; margin-bottom: 12px; }
  .steps .on { font-weight: 600; opacity: 1; }
  .links a { display: block; padding: 4px 0; color: var(--vscode-textLink-foreground); cursor: pointer; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
  <nav>
    <div class="brand">Pastel</div>
    <div class="ver" id="ver"></div>
    <button class="nav on" data-page="projects">Projects</button>
    <button class="nav" data-page="learn">Learn</button>
  </nav>
  <main>
    <section id="projects">
      <h1>Welcome to Pastel</h1>
      <div class="sub">Object Pascal apps for Windows and Linux — Android is coming.</div>
      <div class="actions">
        <button id="newProject">New Project</button>
        <button class="secondary" id="open">Open…</button>
      </div>
      <div class="recent" id="recent"></div>
    </section>

    <section id="wizard1" hidden>
      <div class="steps"><span class="on">1. Template</span><span>›</span><span>2. Project</span></div>
      <h1>New Project</h1>
      <div class="sub">Choose what you are making.</div>
      <div class="wizard">
        <div class="cats" id="cats"></div>
        <div class="gallery" id="gallery"></div>
      </div>
      <div class="foot">
        <span class="msg" id="tplInfo"></span>
        <button class="secondary" id="cancel1">Cancel</button>
        <button id="next" disabled>Next</button>
      </div>
    </section>

    <section id="wizard2" hidden>
      <div class="steps"><span>1. Template</span><span>›</span><span class="on">2. Project</span></div>
      <div class="chosen"><span class="ic" id="chosenIcon"></span><div><h1 id="chosenTitle"></h1><div class="sub" id="chosenDesc" style="margin:0"></div></div></div>
      <div class="form">
        <label for="name">Name</label><input type="text" id="name" value="my-app" spellcheck="false">
        <div class="bad" id="nameBad" hidden></div>
        <label for="location">Location</label>
        <span class="loc"><input type="text" id="location" spellcheck="false"><button class="secondary" id="browse">Browse…</button></span>
        <div class="hint" id="where"></div>
        <label>Platforms</label>
        <span class="checks" id="platforms"></span>
        <div class="hint">What "pastel build --all" builds; any platform can still be built with --target.</div>
      </div>
      <div class="foot">
        <span class="msg" id="msg"></span>
        <button class="secondary" id="back">Back</button>
        <button id="finish">Create</button>
      </div>
    </section>

    <section id="learn" hidden>
      <h1>Learn</h1>
      <div class="sub">The documentation, in the folder Pastel is installed in.</div>
      <div class="links">
        <a data-doc="getting-started.md">Getting started</a>
        <a data-doc="guide-desktop.md">A desktop app, step by step</a>
        <a data-doc="forms.md">Forms and the designer</a>
        <a data-doc="controls.md">Controls reference</a>
        <a data-doc="guide-api.md">A web API, step by step</a>
        <a data-doc="commands.md">The pastel commands</a>
      </div>
    </section>
  </main>
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  const D = ${json};
  let category = 'Desktop', chosen = null;
  const $ = id => document.getElementById(id);
  $('ver').textContent = D.version ? 'Version ' + D.version : '';
  $('location').value = D.location;

  function show(page) {
    for (const id of ['projects', 'wizard1', 'wizard2', 'learn']) $(id).hidden = id !== page;
    document.querySelectorAll('nav .nav').forEach(b => b.classList.toggle('on',
      b.dataset.page === page || (b.dataset.page === 'projects' && page.startsWith('wizard'))));
  }
  document.querySelectorAll('nav .nav').forEach(b => b.addEventListener('click', () => show(b.dataset.page)));
  document.querySelectorAll('[data-doc]').forEach(a => a.addEventListener('click', () => vscode.postMessage({ type: 'doc', file: a.dataset.doc })));

  function drawRecent() {
    const el = $('recent');
    el.innerHTML = '';
    if (!D.recent.length) { el.innerHTML = '<div class="empty">Projects you open or make are listed here.</div>'; return; }
    for (const r of D.recent) {
      const p = document.createElement('div'); p.className = 'p'; p.title = r.path;
      const i = document.createElement('div'); i.className = 'i'; i.textContent = (r.name[0] || '?').toUpperCase();
      const t = document.createElement('div');
      const n = document.createElement('div'); n.className = 'n'; n.textContent = r.name;
      const d = document.createElement('div'); d.className = 'd'; d.textContent = r.path;
      t.append(n, d);
      const k = document.createElement('span'); k.className = 'k'; k.textContent = r.kind;
      p.append(i, t, k);
      p.addEventListener('click', () => vscode.postMessage({ type: 'openRecent', path: r.path }));
      el.appendChild(p);
    }
  }

  function drawCats() {
    const el = $('cats');
    el.innerHTML = '';
    for (const c of D.categories) {
      const b = document.createElement('button'); b.textContent = c; b.className = c === category ? 'on' : '';
      b.addEventListener('click', () => { category = c; drawCats(); drawGallery(); });
      el.appendChild(b);
    }
  }
  function drawGallery() {
    const el = $('gallery');
    el.innerHTML = '';
    for (const t of D.templates.filter(x => x.category === category)) {
      const c = document.createElement('div');
      c.className = 'card' + (chosen === t ? ' on' : '') + (t.soon ? ' soon' : '');
      c.dataset.kind = t.kind;
      c.innerHTML = '<div class="ic"></div><div class="t"></div><div class="ds"></div><div class="pl"></div>';
      c.querySelector('.ic').textContent = t.icon;
      c.querySelector('.t').textContent = t.title;
      c.querySelector('.ds').textContent = t.description;
      c.querySelector('.pl').textContent = t.soon ? 'Coming in ' + t.soon : t.platforms.join(' · ') + (t.forms ? ' · forms' : '');
      if (!t.soon) {
        c.addEventListener('click', () => { chosen = t; drawGallery(); });
        c.addEventListener('dblclick', () => { chosen = t; next(); });
      }
      el.appendChild(c);
    }
    $('next').disabled = !chosen;
    $('tplInfo').textContent = chosen ? chosen.title + (chosen.forms ? ': with the form designer' : ': no windows') : '';
  }

  function next() {
    if (!chosen) return;
    $('chosenIcon').textContent = chosen.icon;
    $('chosenTitle').textContent = chosen.title;
    $('chosenDesc').textContent = chosen.description;
    const pl = $('platforms');
    pl.innerHTML = '';
    for (const p of ['Windows', 'Linux']) {
      const l = document.createElement('label');
      const c = document.createElement('input'); c.type = 'checkbox'; c.checked = true; c.value = p;
      l.append(c, document.createTextNode(p));
      pl.appendChild(l);
    }
    if (!$('name').dataset.typed) $('name').value = { app: 'my-app', console: 'my-tool', api: 'my-api', service: 'my-service', lib: 'my-library' }[chosen.kind] || 'my-project';
    $('msg').textContent = ''; $('msg').className = 'msg';
    show('wizard2');
    validate();
  }

  function validate() {
    const n = $('name').value.trim();
    const bad = !/^[A-Za-z][A-Za-z0-9_-]*$/.test(n) ? 'Start with a letter; use letters, digits, "-" and "_".' : '';
    $('nameBad').hidden = !bad; $('nameBad').textContent = bad;
    const loc = $('location').value.trim();
    const sep = loc.includes('\\\\') && !loc.includes('/') ? '\\\\' : '/';
    $('where').textContent = loc && n ? 'The project goes into ' + loc.replace(/[\\\\/]+$/, '') + sep + n : '';
    $('finish').disabled = !!bad || !loc;
    return !bad && !!loc;
  }
  $('name').addEventListener('input', () => { $('name').dataset.typed = '1'; validate(); });
  $('location').addEventListener('input', validate);

  $('newProject').addEventListener('click', () => { show('wizard1'); drawCats(); drawGallery(); });
  $('open').addEventListener('click', () => vscode.postMessage({ type: 'open' }));
  $('cancel1').addEventListener('click', () => show('projects'));
  $('next').addEventListener('click', next);
  $('back').addEventListener('click', () => show('wizard1'));
  $('browse').addEventListener('click', () => vscode.postMessage({ type: 'browse', location: $('location').value }));
  $('finish').addEventListener('click', () => {
    if (!validate()) return;
    const platforms = [...document.querySelectorAll('#platforms input')].filter(c => c.checked).map(c => c.value);
    $('finish').disabled = true;
    $('msg').className = 'msg'; $('msg').textContent = 'Creating…';
    vscode.postMessage({ type: 'create', kind: chosen.kind, name: $('name').value.trim(), location: $('location').value.trim(), platforms });
  });

  window.addEventListener('message', e => {
    const m = e.data;
    if (m.type === 'location') { $('location').value = m.location; validate(); }
    else if (m.type === 'failed') { $('msg').className = 'msg err'; $('msg').textContent = m.message; $('finish').disabled = false; }
    else if (m.type === 'wizard') { show('wizard1'); drawCats(); drawGallery(); }
  });

  drawRecent();
</script>
</body>
</html>`;
}
