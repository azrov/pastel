// The designer's web page (HTML, CSS and script), kept apart so it can be
// tested in a browser-like environment without VS Code.
//
// Laid out like Delphi's IDE: Structure and Object Inspector on the left, the
// form in a window frame in the middle (non-visual components in a tray under
// it), the Tool Palette on the right. In a parent with Layout = Free controls
// are placed, moved and resized freely (snapped to a grid); in Flow parents
// they are ordered among their neighbours.
export function designerHtml(nonce: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<style>
  html, body { height: 100%; }
  body { margin: 0; padding: 0; font-family: var(--vscode-font-family); font-size: 13px; color: var(--vscode-foreground);
    display: flex; flex-direction: column; overflow: hidden; }
  .topbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; padding: 5px 10px;
    border-bottom: 1px solid var(--vscode-panel-border); background: var(--vscode-editor-background); }
  .topbar .sep { width: 1px; align-self: stretch; background: var(--vscode-panel-border); }
  .topbar select { width: auto; }
  .topbar label { display: inline-flex; gap: 4px; align-items: center; white-space: nowrap; }
  .topbar .grow { flex: 1; }
  .topbar .pos { opacity: .75; font-variant-numeric: tabular-nums; font-size: 12px; min-width: 120px; text-align: right; }
  .ide { flex: 1; display: grid; grid-template-columns: minmax(230px, 290px) 1fr minmax(170px, 210px); min-height: 0; }
  aside { display: flex; flex-direction: column; min-height: 0; border-right: 1px solid var(--vscode-panel-border);
    background: var(--vscode-sideBar-background, var(--vscode-editor-background)); }
  aside.right { border-right: none; border-left: 1px solid var(--vscode-panel-border); }
  .pane { display: flex; flex-direction: column; min-height: 0; }
  .pane.structure { flex: 0 0 34%; border-bottom: 1px solid var(--vscode-panel-border); }
  .pane.inspector { flex: 1; }
  .pane-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .04em; padding: 6px 8px; opacity: .85;
    border-bottom: 1px solid var(--vscode-panel-border); }
  .scroll { overflow: auto; flex: 1; min-height: 0; }
  #tree { padding: 4px 0; }
  .tree .item { cursor: pointer; padding: 1px 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .tree .item:hover { background: var(--vscode-list-hoverBackground); }
  .tree .item.on { background: var(--vscode-list-activeSelectionBackground); color: var(--vscode-list-activeSelectionForeground); }
  .tree .item .c { opacity: .6; font-size: 11px; margin-left: 4px; }
  .tree .item.nv::before { content: '◇ '; opacity: .7; }
  .tree .item .bad { color: var(--vscode-editorWarning-foreground, #cca700); margin-left: 4px; }
  .insp-head { padding: 6px 8px 4px; }
  .insp-head h3 { margin: 0; font-size: 13px; }
  .insp-head .cls { opacity: .7; font-size: 12px; }
  .tabs { display: flex; border-bottom: 1px solid var(--vscode-panel-border); padding: 0 6px; }
  .tabs button { background: none; color: var(--vscode-foreground); border: none; border-bottom: 2px solid transparent; padding: 4px 10px;
    cursor: pointer; opacity: .75; }
  .tabs button.on { border-bottom-color: var(--vscode-focusBorder); opacity: 1; }
  .search { margin: 6px 8px; width: calc(100% - 16px) !important; }
  #props { padding: 0 0 8px; }
  #props.events .row.p, #props.props .row.e, #props.events .section.p, #props.props .section.e { display: none; }
  #props .row.hidden { display: none; }
  .row { display: grid; grid-template-columns: 44% 1fr; align-items: stretch; border-bottom: 1px solid var(--vscode-panel-border); min-height: 24px; }
  .row > label { padding: 3px 8px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; align-self: center; }
  .row > label.set { font-weight: 600; }
  .row > :not(label) { border-left: 1px solid var(--vscode-panel-border); }
  .row input, .row select { border-color: transparent; background: transparent; height: 100%; }
  .row input:focus, .row select:focus { background: var(--vscode-input-background); }
  .row input[type=checkbox] { height: auto; margin: 4px 8px; justify-self: start; align-self: center; }
  input, select { width: 100%; box-sizing: border-box; background: var(--vscode-input-background); color: var(--vscode-input-foreground);
    border: 1px solid var(--vscode-input-border, transparent); padding: 3px 5px; font: inherit; }
  input[type=checkbox] { width: auto; }
  input[type=color] { padding: 0; height: 22px; width: 36px; flex: none; }
  .inline { display: flex; gap: 4px; align-items: center; padding-right: 2px; }
  .setbox { display: flex; flex-wrap: wrap; gap: 2px 8px; padding: 3px 6px; }
  .setbox label { display: inline-flex; gap: 2px; align-items: center; font-size: 12px; }
  .setbox input[type=checkbox] { margin: 0; }
  button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 4px 10px; cursor: pointer; font: inherit; }
  button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
  button.small { padding: 2px 6px; }
  .section { padding: 5px 8px 3px; font-size: 11px; text-transform: uppercase; opacity: .7; }
  .empty { opacity: .7; padding: 8px; }
  .buttons { display: flex; flex-wrap: wrap; gap: 4px; padding: 8px; }
  .center { overflow: auto; min-width: 0; background: var(--vscode-editorWidget-background, var(--vscode-editor-background)); }
  .canvas { padding: 24px; display: inline-flex; flex-direction: column; gap: 12px; min-width: calc(100% - 48px); align-items: flex-start; }
  .window { border-radius: 8px; overflow: visible; box-shadow: 0 4px 18px rgba(0,0,0,.35); background: var(--vscode-editor-background); }
  .titlebar { display: flex; align-items: center; gap: 8px; height: 30px; padding: 0 6px 0 12px; border-radius: 8px 8px 0 0;
    background: var(--vscode-titleBar-activeBackground, #3c3c3c); color: var(--vscode-titleBar-activeForeground, #ddd); user-select: none; font-size: 12px; }
  .titlebar .t { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .titlebar .wb { opacity: .7; letter-spacing: 10px; }
  .stage { position: relative; display: inline-block; line-height: 0; user-select: none; }
  .stage img { display: block; height: auto; }
  body.fit .stage img { max-width: calc(100vw - 600px); }
  .stage.grid::after { content: ''; position: absolute; inset: 0; pointer-events: none; opacity: .3;
    background-image: radial-gradient(circle, rgba(110,110,110,.9) 1px, transparent 1.2px); background-size: var(--grid, 8px) var(--grid, 8px); }
  .box { position: absolute; box-sizing: border-box; pointer-events: none; }
  .hover { outline: 1px dashed var(--vscode-focusBorder); }
  .selected { outline: 2px solid var(--vscode-focusBorder); }
  .selected .tag, .ghostbox .tag { position: absolute; top: -18px; left: -2px; font-size: 10px; line-height: 16px; padding: 0 5px;
    background: var(--vscode-focusBorder); color: var(--vscode-editor-background); border-radius: 3px 3px 0 0; white-space: nowrap; }
  .ghostbox { outline: 2px dashed var(--vscode-charts-orange, #f0a030); background: rgba(240,160,48,.12); z-index: 4; }
  .ghostbox .tag { background: var(--vscode-charts-orange, #f0a030); }
  .handle { position: absolute; width: 7px; height: 7px; margin: -4px 0 0 -4px; box-sizing: border-box; pointer-events: auto; z-index: 6;
    background: var(--vscode-editor-background); border: 1px solid var(--vscode-focusBorder); }
  .drop { position: absolute; background: var(--vscode-charts-orange, #f0a030); pointer-events: none; z-index: 3; }
  .ghost { opacity: .45; }
  .tray { display: flex; flex-wrap: wrap; gap: 8px; min-height: 0; }
  .tray .nv { display: flex; flex-direction: column; align-items: center; gap: 2px; width: 72px; padding: 6px 2px; cursor: pointer;
    border: 1px solid var(--vscode-panel-border); border-radius: 4px; font-size: 11px; background: var(--vscode-editor-background); }
  .tray .nv .i { font-size: 18px; line-height: 20px; opacity: .8; }
  .tray .nv.on { outline: 2px solid var(--vscode-focusBorder); }
  .tray .nv span { max-width: 68px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .error { display: none; padding: 10px 12px; border-radius: 6px; white-space: pre-wrap; max-width: 640px; line-height: 1.4;
    background: var(--vscode-inputValidation-errorBackground); border: 1px solid var(--vscode-inputValidation-errorBorder);
    font-family: var(--vscode-editor-font-family); font-size: 12px; }
  body.has-error .error { display: block; }
  body.has-error .stage { opacity: .5; }
  .issue { outline: 2px dashed var(--vscode-editorWarning-foreground, #cca700); outline-offset: 1px; }
  .issue.error { outline-color: var(--vscode-editorError-foreground, #f14c4c); }
  .issues { line-height: 1.4; max-width: 640px; }
  .issues div { cursor: pointer; padding: 3px 6px; border-radius: 3px; }
  .issues div:hover { background: var(--vscode-list-hoverBackground); }
  .issues .sev { font-weight: 600; margin-right: 6px; }
  .issues .warning .sev { color: var(--vscode-editorWarning-foreground, #cca700); }
  .issues .error .sev { color: var(--vscode-editorError-foreground, #f14c4c); }
  #toolbox { padding: 2px 0 8px; }
  .cat { font-size: 11px; font-weight: 600; padding: 6px 8px 2px; opacity: .8; cursor: pointer; user-select: none; }
  .cat::before { content: '▾ '; }
  .cat.closed::before { content: '▸ '; }
  .chip { display: block; padding: 2px 8px 2px 18px; cursor: grab; user-select: none; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .chip:hover { background: var(--vscode-list-hoverBackground); }
  .chip.project { font-style: italic; }
  .chip.nonvisual::before { content: '◇ '; opacity: .7; }
  .chip.hidden { display: none; }
</style>
</head>
<body class="">
  <div class="topbar">
    <button class="secondary small" id="undo" title="Undo (Ctrl+Z)">↶</button>
    <button class="secondary small" id="redo" title="Redo (Ctrl+Y)">↷</button>
    <span class="sep"></span>
    <select id="size" title="Preview size">
      <option value="0x0">Form size</option>
      <option value="360x640">Phone 360 × 640</option>
      <option value="768x1024">Tablet 768 × 1024</option>
      <option value="1280x800">Laptop 1280 × 800</option>
      <option value="1920x1080">Full HD 1920 × 1080</option>
    </select>
    <label title="Show the form in the dark theme"><input type="checkbox" id="dark"> Dark</label>
    <label title="Shrink a big form to fit the window"><input type="checkbox" id="fit"> Fit</label>
    <label title="Free-placed controls snap to an 8 pixel grid (hold Alt while dragging to place freely)"><input type="checkbox" id="snap" checked> Snap to grid</label>
    <span class="sep"></span>
    <span id="align"></span>
    <span class="grow"></span>
    <span class="pos" id="pos"></span>
  </div>
  <div class="ide">
    <aside class="left">
      <section class="pane structure">
        <div class="pane-title">Structure</div>
        <div class="scroll"><div class="tree" id="tree"></div></div>
      </section>
      <section class="pane inspector">
        <div class="pane-title">Object Inspector</div>
        <div class="tabs"><button id="tabProps" class="on">Properties</button><button id="tabEvents">Events</button></div>
        <input class="search" id="propSearch" placeholder="Search properties">
        <div class="scroll"><div id="props" class="props"><div class="empty">Click a control to edit it. Ctrl+click selects more.</div></div></div>
      </section>
    </aside>
    <main class="center">
      <div class="canvas">
        <div class="window">
          <div class="titlebar"><span class="t" id="wtitle"></span><span class="wb">—▢✕</span></div>
          <div class="stage" id="stage"><img id="img" alt="" draggable="false"></div>
        </div>
        <div class="tray" id="tray"></div>
        <div class="error" id="error"></div>
        <div class="issues" id="issues"></div>
      </div>
    </main>
    <aside class="right">
      <div class="pane-title">Tool Palette</div>
      <input class="search" id="paletteSearch" placeholder="Search controls">
      <div class="scroll"><div id="toolbox"></div></div>
    </aside>
  </div>
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  const img = document.getElementById('img');
  const stage = document.getElementById('stage');
  const propsEl = document.getElementById('props');
  const toolbox = document.getElementById('toolbox');
  const trayEl = document.getElementById('tray');
  const posEl = document.getElementById('pos');
  const alignEl = document.getElementById('align');
  let layout = null, selected = null, selection = null, hoverName = null, drag = null;
  let controlsInfo = [], multi = [], issues = [], tree = [];
  let tab = 'props';
  const issuesEl = document.getElementById('issues');
  const treeEl = document.getElementById('tree');
  const GRID = 8;

  // the Tool Palette's groups, like Delphi's Standard, Additional...
  const CATEGORIES = [
    ['Standard', ['TButton', 'TLabel', 'TEdit', 'TMemo', 'TCheckBox', 'TRadioButton', 'TComboBox', 'TListBox', 'TSwitch', 'TImage', 'TPanel']],
    ['Layout', ['TCard', 'TColumn', 'TRow', 'TFlow', 'TScrollBox', 'TTabControl', 'TTabSheet', 'TSplitter', 'TSpacer', 'TToolBar', 'TStatusBar']],
    ['Input', ['TDatePicker', 'TCalendarView', 'TTimeEdit', 'TNumberEdit', 'TCurrencyEdit', 'TSlider']],
    ['Lists and tables', ['TGrid', 'TGridColumn', 'TListView', 'TTreeView']],
    ['Progress', ['TProgressBar', 'TSpinner']],
    ['Menus', ['TMenuBar', 'TMenuItem', 'TPopupMenu']],
  ];

  // selects one control (or, with add, adds/removes it to the selection)
  function choose(name, add) {
    if (add && name) {
      if (multi.includes(name)) multi = multi.filter(n => n !== name);
      else multi = multi.concat([name]);
      selected = multi.length ? multi[multi.length - 1] : null;
    } else {
      multi = name ? [name] : [];
      selected = name;
    }
    vscode.postMessage({ type: 'select', name: selected, names: multi });
    drawBoxes();
    drawTree();
  }

  function sendView() {
    const [w, h] = document.getElementById('size').value.split('x').map(Number);
    vscode.postMessage({ type: 'view', width: w, height: h, dark: document.getElementById('dark').checked });
  }
  document.getElementById('size').addEventListener('change', sendView);
  document.getElementById('dark').addEventListener('change', sendView);
  document.getElementById('undo').addEventListener('click', () => vscode.postMessage({ type: 'undo' }));
  document.getElementById('redo').addEventListener('click', () => vscode.postMessage({ type: 'redo' }));
  document.getElementById('fit').addEventListener('change', e => {
    document.body.classList.toggle('fit', e.target.checked);
    drawBoxes();
  });

  function snapOn(e) { return document.getElementById('snap').checked && !(e && e.altKey); }
  function snap(v, e) { return snapOn(e) ? Math.round(v / GRID) * GRID : Math.round(v); }
  function scale() { return layout && img.clientWidth ? img.clientWidth / layout.width : 1; }
  function byName(n) { return layout && n ? layout.controls.find(c => c.name === n) : null; }
  function root() { return layout ? layout.controls[0] : null; }
  function depth(c) { let d = 0; while (c && c.parent) { c = byName(c.parent); d++; } return d; }
  function isInside(c, ancestor) { while (c) { if (c.name === ancestor) return true; c = byName(c.parent); } return false; }
  // placed by Left and Top: its parent has Layout = Free and it is not docked
  function isFree(c) { const p = c && byName(c.parent); return !!(p && p.free && !c.dock); }

  function pointFromEvent(e) {
    const r = img.getBoundingClientRect();
    return { x: (e.clientX - r.left) / scale(), y: (e.clientY - r.top) / scale() };
  }

  function hit(p, filter) {
    if (!layout) return null;
    let best = null, bestDepth = -1;
    for (const c of layout.controls) {
      if (!c.visible || p.x < c.x || p.y < c.y || p.x >= c.x + c.w || p.y >= c.y + c.h) continue;
      if (filter && !filter(c)) continue;
      const d = depth(c);
      if (d >= bestDepth) { best = c; bestDepth = d; }
    }
    return best;
  }

  function box(c, cls, label) {
    const s = scale();
    const el = document.createElement('div');
    el.className = 'box ' + cls;
    el.style.left = (c.x * s) + 'px'; el.style.top = (c.y * s) + 'px';
    el.style.width = (c.w * s) + 'px'; el.style.height = (c.h * s) + 'px';
    if (label) { const t = document.createElement('div'); t.className = 'tag'; t.textContent = label; el.appendChild(t); }
    stage.appendChild(el);
    return el;
  }

  // the 8 grips of Delphi's selection; in flow parents only the right and bottom ones (fixed Width, Height)
  function drawHandles(c) {
    const s = scale();
    const free = isFree(c);
    const dirs = free ? ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'] : ['e', 'se', 's'];
    for (const d of dirs) {
      const h = document.createElement('div');
      h.className = 'handle';
      h.dataset.dir = d;
      const x = d.includes('w') ? c.x : d.includes('e') ? c.x + c.w : c.x + c.w / 2;
      const y = d.includes('n') ? c.y : d.includes('s') ? c.y + c.h : c.y + c.h / 2;
      h.style.left = (x * s) + 'px'; h.style.top = (y * s) + 'px';
      h.style.cursor = d + '-resize';
      h.addEventListener('mousedown', e => startResize(e, c, d));
      stage.appendChild(h);
    }
  }

  function drawBoxes() {
    stage.querySelectorAll('.box, .drop, .handle').forEach(e => e.remove());
    stage.classList.toggle('grid', !!(root() && root().free && document.getElementById('snap').checked));
    stage.style.setProperty('--grid', (GRID * scale()) + 'px');
    if (!layout) return;
    const h = byName(hoverName);
    if (h && hoverName !== selected) box(h, 'hover');
    for (const i of issues) {
      const c = i.name && byName(i.name);
      if (c && c.parent) box(c, 'issue ' + i.severity);
    }
    for (const n of multi) {
      const s = byName(n);
      if (!s) continue;
      const label = n === selected ? (multi.length > 1 ? multi.length + ' selected' : s.name + ': ' + s.class) : null;
      box(s, 'selected' + (drag && drag.active && drag.names && drag.names.includes(s.name) ? ' ghost' : ''), label);
    }
    if (multi.length === 1 && !drag) {
      const s = byName(selected);
      if (s && !s.dock) drawHandles(s);
    }
    if (drag && drag.active && drag.ghosts) {
      for (const g of drag.ghosts) box(g, 'ghostbox', g.label);
      if (drag.into) box(drag.into, 'hover');
    } else if (drag && drag.target) drawDrop(drag.target);
    drawTray();
    drawAlign();
  }

  function drawTree() {
    treeEl.innerHTML = '';
    for (const t of tree) {
      const d = document.createElement('div');
      d.className = 'item' + (multi.includes(t.name) ? ' on' : '') + (t.nonvisual ? ' nv' : '');
      d.style.paddingLeft = (6 + t.depth * 14) + 'px';
      d.textContent = t.name;
      const c = document.createElement('span'); c.className = 'c'; c.textContent = t.className; d.appendChild(c);
      if (issues.some(i => i.name === t.name)) { const b = document.createElement('span'); b.className = 'bad'; b.textContent = '⚠'; d.appendChild(b); }
      d.addEventListener('click', e => choose(t.name, (e.ctrlKey || e.metaKey || e.shiftKey) && t.depth > 0));
      treeEl.appendChild(d);
    }
  }

  // non-visual components (timers, actions, data bindings) under the form, like Delphi's icons on it
  function drawTray() {
    trayEl.innerHTML = '';
    for (const t of tree.filter(x => x.nonvisual)) {
      const d = document.createElement('div');
      d.className = 'nv' + (multi.includes(t.name) ? ' on' : '');
      const icon = /Timer/.test(t.className) ? '⏱' : /Action/.test(t.className) ? '⚡' : /Binding/.test(t.className) ? '⛓' : /Menu/.test(t.className) ? '☰' : '◇';
      const i = document.createElement('div'); i.className = 'i'; i.textContent = icon;
      const n = document.createElement('span'); n.textContent = t.name;
      d.title = t.name + ': ' + t.className;
      d.append(i, n);
      d.addEventListener('click', e => choose(t.name, e.ctrlKey || e.metaKey || e.shiftKey));
      trayEl.appendChild(d);
    }
  }

  function drawIssues() {
    issuesEl.innerHTML = '';
    for (const i of issues) {
      const d = document.createElement('div');
      d.className = i.severity;
      const sev = document.createElement('span'); sev.className = 'sev'; sev.textContent = i.severity === 'error' ? 'Error' : 'Warning';
      d.append(sev, document.createTextNode((i.line ? 'line ' + i.line + ': ' : '') + i.message));
      d.title = 'Select the control';
      d.addEventListener('click', () => { if (i.name) choose(i.name, false); });
      issuesEl.appendChild(d);
    }
  }

  // ---- align and size tools for several free-placed controls (Delphi's Align palette) ----
  function freeSelection() {
    const cs = multi.map(byName).filter(c => c && isFree(c));
    return cs.length === multi.length && cs.length > 1 && cs.every(c => c.parent === cs[0].parent) ? cs : null;
  }
  function drawAlign() {
    const cs = freeSelection();
    const key = cs ? cs.map(c => c.name).join(',') : '';
    if (alignEl.dataset.key === key) return;
    alignEl.dataset.key = key;
    alignEl.innerHTML = '';
    if (!cs) return;
    const tools = [['⇤', 'Align left edges', 'left'], ['⇥', 'Align right edges', 'right'], ['⤒', 'Align tops', 'top'],
      ['⤓', 'Align bottoms', 'bottom'], ['↔', 'Same width', 'width'], ['↕', 'Same height', 'height']];
    for (const [text, title, what] of tools) {
      const b = document.createElement('button'); b.className = 'secondary small'; b.textContent = text; b.title = title;
      b.dataset.align = what;
      b.addEventListener('click', () => alignSelection(what));
      alignEl.appendChild(b);
    }
  }
  // the control chosen last is the model, like in Delphi
  function alignSelection(what) {
    const cs = freeSelection();
    if (!cs) return;
    const model = byName(selected) || cs[0];
    const parent = byName(model.parent);
    const items = cs.map(c => {
      const it = { name: c.name, left: c.x - parent.x, top: c.y - parent.y };
      if (what === 'left') it.left = model.x - parent.x;
      if (what === 'right') it.left = model.x + model.w - c.w - parent.x;
      if (what === 'top') it.top = model.y - parent.y;
      if (what === 'bottom') it.top = model.y + model.h - c.h - parent.y;
      if (what === 'width') it.width = model.w;
      if (what === 'height') it.height = model.h;
      return it;
    });
    vscode.postMessage({ type: 'place', parent: null, items });
  }

  // where a drop at point p would go in a Flow parent: container + index among its children
  function dropTarget(p, draggedName) {
    const container = hit(p, c => c.container && !(draggedName && isInside(c, draggedName)));
    if (!container) return null;
    const kids = layout.controls.filter(c => c.parent === container.name && c.visible && c.name !== draggedName);
    let index = 0;
    for (const k of kids) {
      const mid = container.row ? k.x + k.w / 2 : k.y + k.h / 2;
      if ((container.row ? p.x : p.y) > mid) index++;
    }
    return { container, kids, index };
  }

  function drawDrop(t) {
    const s = scale(), c = t.container, k = t.kids;
    // the marker goes before the child at the drop index; if the dragged
    // control sits right before that child, the marker goes before it instead
    const all = layout.controls.filter(x => x.parent === c.name && x.visible);
    let before = t.index < k.length ? k[t.index] : null;
    if (before) {
      const i = all.indexOf(before);
      if (i > 0 && drag && all[i - 1].name === drag.name) before = all[i - 1];
    }
    const lastKid = all.length ? all[all.length - 1] : null;
    let x, y, w, hgt;
    if (c.row) {
      const at = before ? before.x - 3 : (lastKid ? lastKid.x + lastKid.w + 1 : c.x + 6);
      x = at; y = c.y + 4; w = 2; hgt = c.h - 8;
    } else {
      const at = before ? before.y - 3 : (lastKid ? lastKid.y + lastKid.h + 1 : c.y + 6);
      x = c.x + 4; y = at; w = c.w - 8; hgt = 2;
    }
    const el = document.createElement('div');
    el.className = 'drop';
    el.style.left = (x * s) + 'px'; el.style.top = (y * s) + 'px';
    el.style.width = Math.max(2, w * s) + 'px'; el.style.height = Math.max(2, hgt * s) + 'px';
    stage.appendChild(el);
    box(c, 'hover');
  }

  // ---- moving: free placement (Left, Top) or a new place among the children of a Flow parent ----
  function updateMove(e) {
    const s = scale();
    const p = pointFromEvent(e);
    const dx = (e.clientX - drag.sx) / s, dy = (e.clientY - drag.sy) / s;
    const lead = byName(drag.name);
    const into = hit(p, c => c.container && !drag.names.some(n => isInside(c, n)));
    drag.ghosts = null; drag.into = null; drag.target = null; drag.place = null;
    if (into && into.free) {
      // where the lead control's top left goes, in the new parent; the others keep their distance to it
      const left = snap(lead.x + dx - into.x, e), top = snap(lead.y + dy - into.y, e);
      const ox = left - (lead.x - into.x), oy = top - (lead.y - into.y);
      const items = drag.names.map(byName).map(c => ({ name: c.name, left: c.x - into.x + ox, top: c.y - into.y + oy }));
      drag.place = { parent: into.name, items };
      drag.into = into.name === byName(lead.parent).name ? null : into;
      drag.ghosts = items.map(it => {
        const c = byName(it.name);
        return { x: into.x + it.left, y: into.y + it.top, w: c.w, h: c.h, label: it.name === lead.name ? it.left + ', ' + it.top : null };
      });
      posEl.textContent = lead.name + ': ' + left + ', ' + top;
    } else if (drag.names.length === 1) {
      drag.target = dropTarget(p, drag.name);
      posEl.textContent = '';
    }
  }

  function startResize(e, c, dir) {
    if (e.button !== 0) return;
    e.preventDefault(); e.stopPropagation();
    const parent = byName(c.parent);
    drag = { mode: 'resize', name: c.name, names: [c.name], dir, sx: e.clientX, sy: e.clientY, active: true, free: isFree(c),
      orig: { left: parent ? c.x - parent.x : 0, top: parent ? c.y - parent.y : 0, w: c.w, h: c.h }, px: parent ? parent.x : 0, py: parent ? parent.y : 0 };
  }

  function updateResize(e) {
    const s = scale();
    const dx = (e.clientX - drag.sx) / s, dy = (e.clientY - drag.sy) / s, o = drag.orig, d = drag.dir;
    let l = o.left, t = o.top, r = o.left + o.w, b = o.top + o.h;
    if (d.includes('w')) l = Math.min(snap(o.left + dx, e), r - GRID);
    if (d.includes('e')) r = Math.max(snap(o.left + o.w + dx, e), l + GRID);
    if (d.includes('n')) t = Math.min(snap(o.top + dy, e), b - GRID);
    if (d.includes('s')) b = Math.max(snap(o.top + o.h + dy, e), t + GRID);
    const it = { name: drag.name, width: r - l, height: b - t };
    if (drag.free) { it.left = l; it.top = t; }
    if (!d.includes('e') && !d.includes('w')) delete it.width;
    if (!d.includes('n') && !d.includes('s')) delete it.height;
    drag.place = { parent: null, items: [it] };
    drag.ghosts = [{ x: drag.px + l, y: drag.py + t, w: r - l, h: b - t, label: (r - l) + ' × ' + (b - t) }];
    posEl.textContent = drag.name + ': ' + (r - l) + ' × ' + (b - t);
  }

  stage.addEventListener('mousemove', e => {
    const p = pointFromEvent(e);
    if (drag && drag.mode === 'resize') { updateResize(e); drawBoxes(); return; }
    if (drag) {
      if (!drag.active && Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy) > 5) drag.active = true;
      if (drag.active) { updateMove(e); drawBoxes(); }
      return;
    }
    const c = hit(p);
    const n = c ? c.name : null;
    if (c) {
      const parent = byName(c.parent);
      posEl.textContent = c.name + (parent ? ': ' + (c.x - parent.x) + ', ' + (c.y - parent.y) : '') + ' — ' + c.w + ' × ' + c.h;
    }
    if (n !== hoverName) { hoverName = n; drawBoxes(); }
  });
  stage.addEventListener('mouseleave', () => { hoverName = null; if (!drag) drawBoxes(); });
  stage.addEventListener('mousedown', e => {
    if (e.button !== 0) return;
    const c = hit(pointFromEvent(e));
    if (!c) return;
    const add = (e.ctrlKey || e.metaKey || e.shiftKey) && !!c.parent;
    if (add || !multi.includes(c.name)) choose(c.name, add);
    else if (multi.length > 1 && !freeSelection()) choose(c.name, false);
    // the whole selection moves when it is free-placed in one parent
    const names = multi.length > 1 && freeSelection() && multi.includes(c.name) ? multi.slice() : [c.name];
    drag = c.parent && !add ? { name: c.name, names, sx: e.clientX, sy: e.clientY, active: false, target: null } : null;
    drawBoxes();
    e.preventDefault();
  });
  window.addEventListener('mouseup', () => {
    if (drag && drag.active) {
      if (drag.place) vscode.postMessage({ type: 'place', parent: drag.place.parent, items: drag.place.items });
      else if (drag.target) vscode.postMessage({ type: 'move', name: drag.name, parent: drag.target.container.name, index: drag.target.index });
    }
    drag = null;
    drawBoxes();
  });

  // Ctrl+arrows move a free-placed control by one pixel, Shift+arrows change its size (like Delphi)
  function nudge(e) {
    const cs = multi.map(byName).filter(Boolean);
    if (!cs.length || !cs.every(c => c.parent)) return false;
    const dx = e.key === 'ArrowLeft' ? -1 : e.key === 'ArrowRight' ? 1 : 0;
    const dy = e.key === 'ArrowUp' ? -1 : e.key === 'ArrowDown' ? 1 : 0;
    if (e.shiftKey) {
      vscode.postMessage({ type: 'place', parent: null, items: cs.map(c => {
        const it = { name: c.name };
        if (dx) it.width = Math.max(1, c.w + dx);
        if (dy) it.height = Math.max(1, c.h + dy);
        return it;
      }) });
      return true;
    }
    if (!cs.every(isFree)) return false;
    vscode.postMessage({ type: 'place', parent: null, items: cs.map(c => {
      const p = byName(c.parent);
      return { name: c.name, left: c.x - p.x + dx, top: c.y - p.y + dy };
    }) });
    return true;
  }

  window.addEventListener('keydown', e => {
    const typing = document.activeElement && ['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement.tagName);
    const arrow = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key);
    if ((e.key === 'Delete' || e.key === 'Backspace') && selected && !typing) {
      const names = multi.filter(n => { const c = byName(n); return !c || c.parent; });
      if (names.length && selected !== (layout && layout.controls[0].name)) vscode.postMessage({ type: 'delete', name: names[0], names });
    }
    // Alt+arrows: earlier or later among its siblings
    if (e.altKey && !typing && selected && multi.length === 1 && arrow) {
      e.preventDefault();
      vscode.postMessage({ type: 'moveSibling', name: selected, delta: e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 1 });
      return;
    }
    if (arrow && !typing && !e.altKey && (e.ctrlKey || e.metaKey || e.shiftKey) && selected) {
      if (nudge(e)) { e.preventDefault(); return; }
    }
    const mod = e.ctrlKey || e.metaKey;
    if (mod && !typing) {
      const k = e.key.toLowerCase();
      const cmd = k === 'z' ? (e.shiftKey ? 'redo' : 'undo') : k === 'y' ? 'redo' : k === 'c' ? 'copy' :
        k === 'x' ? 'cut' : k === 'v' ? 'paste' : k === 'd' ? 'duplicate' : null;
      if (cmd) {
        e.preventDefault();
        const c = selected && byName(selected);
        // copying and cutting the form itself makes no sense
        if ((cmd === 'copy' || cmd === 'cut' || cmd === 'duplicate') && !(c && c.parent) && multi.length < 2 &&
          !tree.some(t => t.name === selected && t.nonvisual)) return;
        vscode.postMessage({ type: cmd, name: selected, names: multi });
      }
    }
    if (e.key === 'F2' && selected && !typing) {
      const c = byName(selected);
      if ((c && c.parent) || tree.some(t => t.name === selected && t.depth > 0)) vscode.postMessage({ type: 'rename', name: selected });
    }
    if (e.key === 'Escape' && !typing) {
      if (drag) { drag = null; drawBoxes(); }
      else if (multi.length > 1) choose(selected, false);
      else if (selected) { const c = byName(selected); if (c && c.parent) choose(c.parent, false); }
    }
  });

  // ---- Tool Palette: drag new controls in, or click to add ----
  function buildToolbox() {
    toolbox.innerHTML = '';
    const known = new Set(CATEGORIES.flatMap(c => c[1]));
    const groups = [];
    const project = controlsInfo.filter(c => c.project);
    if (project.length) groups.push(['This project', project]);
    for (const [title, names] of CATEGORIES) {
      const list = names.map(n => controlsInfo.find(c => c.name === n && !c.project)).filter(Boolean);
      if (list.length) groups.push([title, list]);
    }
    const nonvisual = controlsInfo.filter(c => !c.project && c.nonvisual);
    if (nonvisual.length) groups.push(['Non-visual', nonvisual]);
    const other = controlsInfo.filter(c => !c.project && !c.nonvisual && !known.has(c.name));
    if (other.length) groups.push(['Other', other]);
    for (const [title, list] of groups) {
      const head = document.createElement('div'); head.className = 'cat'; head.textContent = title;
      const items = [];
      head.addEventListener('click', () => {
        head.classList.toggle('closed');
        for (const i of items) i.style.display = head.classList.contains('closed') ? 'none' : '';
      });
      toolbox.appendChild(head);
      for (const c of list) {
        const chip = document.createElement('span');
        chip.className = 'chip' + (c.project ? ' project' : '') + (c.nonvisual ? ' nonvisual' : '');
        chip.textContent = c.name.replace(/^T/, '');
        chip.draggable = true;
        chip.title = c.name + '. ' + (c.project ? 'From this project or its libraries (src/controls). ' : '') +
          (c.nonvisual ? 'Not visible on the form: it goes to the top of the .pform. ' : '') +
          'Drag onto the form, or click to add it next to the selected control';
        chip.addEventListener('dragstart', e => { e.dataTransfer.setData('text/plain', c.name); e.dataTransfer.effectAllowed = 'copy'; });
        chip.addEventListener('click', () => addNear(c.name));
        toolbox.appendChild(chip);
        items.push(chip);
      }
    }
    filterPalette();
  }
  function filterPalette() {
    const q = document.getElementById('paletteSearch').value.trim().toLowerCase();
    toolbox.querySelectorAll('.chip').forEach(ch => ch.classList.toggle('hidden', !!q && !ch.textContent.toLowerCase().includes(q)));
  }
  document.getElementById('paletteSearch').addEventListener('input', filterPalette);

  function isNonVisual(className) {
    return controlsInfo.some(c => c.name === className && c.nonvisual);
  }
  function addNear(className) {
    if (!layout) return;
    if (isNonVisual(className)) {
      // a timer, an action...: at the start of the form
      vscode.postMessage({ type: 'add', className, parent: layout.controls[0].name, index: 0 });
      return;
    }
    const sel = byName(selected) || layout.controls[0];
    if (sel.container && sel.free) {
      // into the selected free container: below what is in it
      const kids = layout.controls.filter(c => c.parent === sel.name && c.visible && !c.dock);
      const top = kids.length ? Math.max(...kids.map(k => k.y + k.h)) - sel.y + GRID : 2 * GRID;
      vscode.postMessage({ type: 'add', className, parent: sel.name, index: 9999, left: 2 * GRID, top: snap(top) });
    } else if (sel.container) {
      // into the selected container, at the end
      vscode.postMessage({ type: 'add', className, parent: sel.name, index: 9999 });
    } else if (isFree(sel)) {
      // under the selected control
      const p = byName(sel.parent);
      vscode.postMessage({ type: 'add', className, parent: p.name, index: 9999, left: sel.x - p.x, top: snap(sel.y - p.y + sel.h + GRID) });
    } else {
      // right after the selected control
      const siblings = layout.controls.filter(c => c.parent === sel.parent);
      vscode.postMessage({ type: 'add', className, parent: sel.parent, index: siblings.indexOf(sel) + 1 });
    }
  }
  function newPlace(e) {
    const p = pointFromEvent(e);
    const into = hit(p, c => c.container);
    if (into && into.free) {
      const left = snap(p.x - into.x, e), top = snap(p.y - into.y, e);
      return { free: true, into, left, top };
    }
    return { free: false, target: dropTarget(p, null) };
  }
  stage.addEventListener('dragover', e => {
    e.preventDefault();
    const np = newPlace(e);
    drag = np.free
      ? { name: null, names: [], active: true, ghosts: [{ x: np.into.x + np.left, y: np.into.y + np.top, w: 80, h: 32, label: np.left + ', ' + np.top }], into: np.into }
      : { name: null, names: [], active: true, target: np.target, isNew: true };
    drawBoxes();
  });
  stage.addEventListener('dragleave', () => { drag = null; drawBoxes(); });
  stage.addEventListener('drop', e => {
    e.preventDefault();
    const className = e.dataTransfer.getData('text/plain');
    const np = newPlace(e);
    drag = null;
    if (className && isNonVisual(className)) addNear(className);
    else if (className && np.free) vscode.postMessage({ type: 'add', className, parent: np.into.name, index: 9999, left: np.left, top: np.top });
    else if (className && np.target) vscode.postMessage({ type: 'add', className, parent: np.target.container.name, index: np.target.index });
    drawBoxes();
  });

  // ---- Object Inspector ----
  function setTab(t) {
    tab = t;
    document.getElementById('tabProps').classList.toggle('on', t === 'props');
    document.getElementById('tabEvents').classList.toggle('on', t === 'events');
    propsEl.classList.toggle('events', t === 'events');
    propsEl.classList.toggle('props', t === 'props');
  }
  document.getElementById('tabProps').addEventListener('click', () => setTab('props'));
  document.getElementById('tabEvents').addEventListener('click', () => setTab('events'));
  function filterProps() {
    const q = document.getElementById('propSearch').value.trim().toLowerCase();
    propsEl.querySelectorAll('.row').forEach(r => {
      const l = r.querySelector('label');
      r.classList.toggle('hidden', !!q && !!l && !l.textContent.toLowerCase().includes(q));
    });
  }
  document.getElementById('propSearch').addEventListener('input', filterProps);

  function send(prop, propType, value, def) {
    // the default value is not written into the .pform
    if (def !== undefined && value === def) value = null;
    vscode.postMessage({ type: 'setProp', name: selection.name, names: selection.names, prop, propType, value });
  }
  function setNames(v) { return (v || '').replace(/^\\[|\\]$/g, '').split(',').map(s => s.trim()).filter(Boolean); }
  function input(p) {
    const cur = p.value === undefined ? '' : p.value;
    let el;
    if (p.type === 'enum') {
      el = document.createElement('select');
      el.appendChild(new Option(p.default !== undefined ? '(default: ' + p.default + ')' : '(default)', ''));
      for (const v of p.values) el.appendChild(new Option(v, v));
      el.value = cur;
      el.addEventListener('change', () => send(p.name, p.type, el.value === '' ? null : el.value, p.default));
    } else if (p.type === 'boolean') {
      el = document.createElement('input'); el.type = 'checkbox';
      // not set in the .pform: it has its default (Enabled, Visible, Resizable are True)
      el.checked = (cur === '' ? p.default : cur) === 'True';
      el.addEventListener('change', () => send(p.name, p.type, el.checked ? 'True' : 'False', p.default));
    } else if (p.type === 'set') {
      // Anchors: a check box for each value
      el = document.createElement('span'); el.className = 'setbox';
      const on = setNames(cur === '' ? p.default : cur);
      const boxes = [];
      for (const v of p.values) {
        const l = document.createElement('label');
        const c = document.createElement('input'); c.type = 'checkbox'; c.checked = on.includes(v); c.dataset.value = v;
        c.addEventListener('change', () => {
          const value = '[' + boxes.filter(b => b.checked).map(b => b.dataset.value).join(', ') + ']';
          send(p.name, p.type, value, p.default !== undefined ? '[' + setNames(p.default).join(', ') + ']' : undefined);
        });
        boxes.push(c);
        l.append(c, document.createTextNode(v));
        el.appendChild(l);
      }
    } else if (p.type === 'color') {
      el = document.createElement('span'); el.className = 'inline';
      const c = document.createElement('input'); c.type = 'color';
      c.value = /^#[0-9a-fA-F]{6}$/.test(cur) ? cur : (/^#[0-9a-fA-F]{8}$/.test(cur) ? '#' + cur.slice(3) : '#000000');
      c.addEventListener('change', () => send(p.name, p.type, c.value));
      // any color can also be typed: #RRGGBB or #AARRGGBB
      const t = document.createElement('input'); t.value = cur; t.placeholder = '(default)';
      t.addEventListener('change', () => send(p.name, p.type, t.value.trim() === '' ? null : t.value.trim()));
      t.addEventListener('keydown', e => { if (e.key === 'Enter') t.blur(); });
      const clear = document.createElement('button'); clear.className = 'secondary small'; clear.textContent = '×';
      clear.title = 'Use the default'; clear.addEventListener('click', () => send(p.name, p.type, null));
      el.append(c, t, clear);
    } else if (p.type === 'event') {
      el = document.createElement('span'); el.className = 'inline';
      const t = document.createElement('input'); t.value = cur; t.placeholder = '(none)';
      t.setAttribute('list', 'handlers');
      t.addEventListener('change', () => send(p.name, p.type, t.value.trim() === '' ? null : t.value.trim()));
      // a double click makes the handler, like in Delphi
      t.addEventListener('dblclick', () => vscode.postMessage({ type: 'code', name: selection.name, prop: p.name,
        handler: t.value.trim(), signature: p.signature }));
      const go = document.createElement('button'); go.className = 'small'; go.textContent = '→';
      go.title = cur ? 'Open the code' : 'Create the handler in the code (or double-click the field)';
      go.addEventListener('click', () => vscode.postMessage({ type: 'code', name: selection.name, prop: p.name,
        handler: t.value.trim(), signature: p.signature }));
      el.append(t, go);
    } else {
      el = document.createElement('input');
      el.value = cur;
      if (p.type === 'integer' || p.type === 'number') el.inputMode = 'numeric';
      if (p.default !== undefined && cur === '') el.placeholder = p.default;
      if (p.suggest) {
        // a list to choose from (icon names, pictures), typing something else stays possible
        const id = 'suggest-' + p.name;
        let dl = document.getElementById(id);
        if (!dl) { dl = document.createElement('datalist'); dl.id = id; document.body.appendChild(dl); }
        dl.innerHTML = '';
        for (const v of p.suggest) dl.appendChild(new Option(v, v));
        el.setAttribute('list', id);
      }
      el.addEventListener('change', () => send(p.name, p.type, el.value === '' ? null : el.value));
      el.addEventListener('keydown', e => { if (e.key === 'Enter') el.blur(); });
    }
    if (p.mixed && el.tagName === 'INPUT' && el.type !== 'checkbox') el.placeholder = '(several values)';
    if (p.mixed && el.tagName === 'SELECT') el.options[0].text = '(several values)';
    el.dataset.prop = p.name;
    return el;
  }
  function renderProps(sel) {
    // keep the panel (and the field being typed in) when only values changed
    const same = selection && sel && selection.name === sel.name &&
      JSON.stringify(selection.names) === JSON.stringify(sel.names) &&
      JSON.stringify(selection.props.map(p => p.name)) === JSON.stringify(sel.props.map(p => p.name));
    const old = selection;
    selection = sel;
    if (same) {
      for (const p of sel.props) {
        const lab = propsEl.querySelector('label[data-for="' + p.name + '"]');
        if (lab) lab.classList.toggle('set', p.value !== undefined);
        // values changed by dragging (Left, Top, Width, Height) show at once, unless being typed in
        const before = old.props.find(q => q.name === p.name);
        const el = propsEl.querySelector('[data-prop="' + p.name + '"]');
        if (el && before && before.value !== p.value && el.tagName === 'INPUT' && el.type !== 'checkbox' && document.activeElement !== el) {
          el.value = p.value === undefined ? '' : p.value;
        }
      }
      return;
    }
    propsEl.innerHTML = '';
    if (!sel) { propsEl.innerHTML = '<div class="empty">Click a control to edit it. Ctrl+click selects more.</div>'; return; }
    const several = sel.names && sel.names.length > 1;
    const head = document.createElement('div'); head.className = 'insp-head';
    const h = document.createElement('h3');
    h.textContent = several ? sel.names.length + ' controls' : sel.name;
    const cls = document.createElement('div'); cls.className = 'cls';
    cls.textContent = several ? sel.names.join(', ') + ' — what they all have' : sel.className;
    head.append(h, cls);
    propsEl.appendChild(head);
    const dl = document.createElement('datalist'); dl.id = 'handlers';
    for (const n of sel.handlers) dl.appendChild(new Option(n));
    propsEl.appendChild(dl);
    if (!several) {
      // Name, like Delphi's Object Inspector: renaming changes the form's .pas code too
      const row = document.createElement('div'); row.className = 'row p';
      const lab = document.createElement('label'); lab.textContent = 'Name'; lab.className = 'set';
      const nm = document.createElement('input'); nm.value = sel.name; nm.dataset.prop = 'Name';
      if (sel.isRoot) {
        nm.readOnly = true;
        nm.title = 'The name of the form goes with its class (T' + sel.name + ') and its unit; rename it in the code';
      } else {
        nm.title = 'Rename (F2): the code in the .pas file is updated too';
        nm.addEventListener('change', () => vscode.postMessage({ type: 'rename', name: sel.name, newName: nm.value.trim() }));
        nm.addEventListener('keydown', e => { if (e.key === 'Enter') nm.blur(); if (e.key === 'Escape') { nm.value = sel.name; nm.blur(); } });
      }
      row.append(lab, nm);
      propsEl.appendChild(row);
    }
    // alphabetical, like the Object Inspector
    const byAbc = (a, b) => a.name.localeCompare(b.name);
    const groups = [['p', '', sel.props.filter(p => p.type !== 'event').sort(byAbc)], ['e', '', sel.props.filter(p => p.type === 'event').sort(byAbc)]];
    for (const [kind, , list] of groups) {
      if (!list.length) { if (kind === 'e') { const s = document.createElement('div'); s.className = 'section e empty'; s.textContent = 'No events'; propsEl.appendChild(s); } continue; }
      for (const p of list) {
        const row = document.createElement('div'); row.className = 'row ' + kind;
        const lab = document.createElement('label'); lab.textContent = p.name; lab.title = p.doc || p.name;
        lab.dataset.for = p.name;
        if (p.value !== undefined) lab.classList.add('set');
        row.append(lab, input(p));
        propsEl.appendChild(row);
      }
    }
    if (!sel.isRoot) {
      const bar = document.createElement('div'); bar.className = 'buttons';
      const btn = (text, title, fn, secondary = true) => {
        const b = document.createElement('button'); b.className = secondary ? 'secondary small' : 'small';
        b.textContent = text; b.title = title; b.addEventListener('click', fn); bar.appendChild(b);
      };
      if (!several || sel.sameParent) {
        for (const [label, cls] of [['Panel', 'TPanel'], ['Row', 'TRow'], ['Column', 'TColumn'], ['Card', 'TCard']]) {
          btn('⊞ ' + label, 'Put ' + (several ? 'them' : 'it') + ' into a new ' + cls, () =>
            vscode.postMessage({ type: 'wrap', names: sel.names, className: cls }));
        }
      }
      if (!several && sel.children > 0) {
        btn('Unwrap', 'Take the controls out of ' + sel.name + ' and remove it', () =>
          vscode.postMessage({ type: 'unwrap', name: sel.name }));
      }
      if (!several) {
        btn('↑', 'Earlier, or in front (Alt+Up)', () => vscode.postMessage({ type: 'moveSibling', name: sel.name, delta: -1 }));
        btn('↓', 'Later, or behind (Alt+Down)', () => vscode.postMessage({ type: 'moveSibling', name: sel.name, delta: 1 }));
      }
      btn('Delete' + (several ? ' ' + sel.names.length : ''), 'Delete (Del)', () =>
        vscode.postMessage({ type: 'delete', name: sel.names[0], names: sel.names }));
      propsEl.appendChild(bar);
    }
    setTab(tab);
    filterProps();
  }

  window.addEventListener('message', e => {
    const m = e.data;
    if (m.type === 'schema') { controlsInfo = m.controls; buildToolbox(); }
    else if (m.type === 'render') {
      img.onload = () => drawBoxes();
      img.src = 'data:image/png;base64,' + m.data;
      layout = m.layout;
      document.getElementById('wtitle').textContent = m.title || m.file || '';
      document.body.classList.remove('has-error');
      drawBoxes();
    } else if (m.type === 'select') {
      selected = m.name;
      multi = m.names || (m.name ? [m.name] : []);
      renderProps(m.name ? m : null);
      drawBoxes();
      drawTree();
    } else if (m.type === 'tree') {
      tree = m.items;
      drawTree();
      drawTray();
    } else if (m.type === 'issues') {
      issues = m.items;
      drawIssues();
      drawBoxes();
      drawTree();
    } else if (m.type === 'error') {
      document.getElementById('error').textContent = m.message;
      document.body.classList.add('has-error');
    }
  });
  window.addEventListener('resize', drawBoxes);
  setTab('props');
</script>
</body>
</html>`;
}
