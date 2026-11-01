// The designer's web page (HTML, CSS and script), kept apart so it can be
// tested in a browser-like environment without VS Code.
export function designerHtml(nonce: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy"
  content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<style>
  body { margin: 0; padding: 0; font-family: var(--vscode-font-family); font-size: 13px; color: var(--vscode-foreground); }
  .toolbar { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; padding: 8px 12px;
    border-bottom: 1px solid var(--vscode-panel-border); position: sticky; top: 0; background: var(--vscode-editor-background); z-index: 5; }
  .chip { padding: 3px 10px; border-radius: 12px; border: 1px solid var(--vscode-button-border, var(--vscode-panel-border));
    background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); cursor: grab; user-select: none; }
  .chip:hover { background: var(--vscode-button-secondaryHoverBackground); }
  .chip.project { border-style: dashed; font-style: italic; }
  .chip.nonvisual::before { content: '◇ '; opacity: .7; }
  .toolbar .hint { opacity: .7; margin-left: auto; font-size: 12px; }
  .toolbar select { width: auto; }
  .main { display: flex; flex-wrap: wrap; gap: 16px; padding: 16px; align-items: flex-start; }
  .stage { position: relative; display: inline-block; box-shadow: 0 2px 12px rgba(0,0,0,.25); border-radius: 6px; line-height: 0; user-select: none; }
  .stage img { display: block; max-width: 100%; height: auto; border-radius: 6px; }
  body.actual .stage img { max-width: none; }
  .box { position: absolute; box-sizing: border-box; pointer-events: none; }
  .hover { outline: 1px dashed var(--vscode-focusBorder); }
  .selected { outline: 2px solid var(--vscode-focusBorder); }
  .selected .tag { position: absolute; top: -18px; left: -2px; font-size: 10px; line-height: 16px; padding: 0 5px;
    background: var(--vscode-focusBorder); color: var(--vscode-editor-background); border-radius: 3px 3px 0 0; white-space: nowrap; }
  .drop { position: absolute; background: var(--vscode-charts-orange, #f0a030); pointer-events: none; z-index: 3; }
  .ghost { opacity: .45; }
  .props { flex: 0 0 260px; min-width: 220px; }
  .props h3 { margin: 0 0 2px; font-size: 13px; }
  .props .cls { opacity: .7; font-size: 12px; margin-bottom: 10px; }
  .row { display: grid; grid-template-columns: 96px 1fr; gap: 6px; align-items: center; margin-bottom: 6px; }
  .row label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .row label.set { font-weight: 600; }
  input, select { width: 100%; box-sizing: border-box; background: var(--vscode-input-background); color: var(--vscode-input-foreground);
    border: 1px solid var(--vscode-input-border, transparent); padding: 3px 5px; font: inherit; }
  input[type=checkbox] { width: auto; }
  input[type=color] { padding: 0; height: 24px; }
  .inline { display: flex; gap: 4px; align-items: center; }
  button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 4px 10px; cursor: pointer; font: inherit; }
  button.secondary { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); }
  button.small { padding: 2px 6px; }
  h3 input.name { font: inherit; font-weight: 600; width: 100%; box-sizing: border-box; background: transparent;
    color: inherit; border: 1px solid transparent; padding: 2px 4px; }
  h3 input.name:hover, h3 input.name:focus { border-color: var(--vscode-input-border, #888); background: var(--vscode-input-background); }
  .section { margin: 12px 0 6px; font-size: 11px; text-transform: uppercase; opacity: .7; }
  .empty { opacity: .7; }
  .error { display: none; margin: 0 16px 16px; padding: 10px 12px; border-radius: 6px; white-space: pre-wrap;
    background: var(--vscode-inputValidation-errorBackground); border: 1px solid var(--vscode-inputValidation-errorBorder);
    font-family: var(--vscode-editor-font-family); font-size: 12px; }
  body.has-error .error { display: block; }
  body.has-error .stage { opacity: .5; }
  .issue { outline: 2px dashed var(--vscode-editorWarning-foreground, #cca700); outline-offset: 1px; }
  .issue.error { outline-color: var(--vscode-editorError-foreground, #f14c4c); }
  .issues { margin-top: 10px; line-height: 1.4; max-width: 640px; }
  .issues div { cursor: pointer; padding: 3px 6px; border-radius: 3px; }
  .issues div:hover { background: var(--vscode-list-hoverBackground); }
  .issues .sev { font-weight: 600; margin-right: 6px; }
  .issues .warning .sev { color: var(--vscode-editorWarning-foreground, #cca700); }
  .issues .error .sev { color: var(--vscode-editorError-foreground, #f14c4c); }
  .side { flex: 0 0 260px; min-width: 220px; display: flex; flex-direction: column; gap: 14px; }
  .side .props { flex: none; }
  details.tree summary { cursor: pointer; font-size: 11px; text-transform: uppercase; opacity: .7; margin-bottom: 4px; }
  .tree .item { cursor: pointer; padding: 1px 4px; border-radius: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .tree .item:hover { background: var(--vscode-list-hoverBackground); }
  .tree .item.on { background: var(--vscode-list-activeSelectionBackground); color: var(--vscode-list-activeSelectionForeground); }
  .tree .item .c { opacity: .6; font-size: 11px; margin-left: 4px; }
  .tree .item.nv::before { content: '◇ '; opacity: .7; }
  .tree .item .bad { color: var(--vscode-editorWarning-foreground, #cca700); margin-left: 4px; }
  .buttons { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
</style>
</head>
<body>
  <div class="toolbar" id="toolbox"><span class="hint">Drag a control onto the form</span>
    <select id="size" title="Preview size">
      <option value="0x0">Form size</option>
      <option value="360x640">Phone 360 × 640</option>
      <option value="768x1024">Tablet 768 × 1024</option>
      <option value="1280x800">Laptop 1280 × 800</option>
      <option value="1920x1080">Full HD 1920 × 1080</option>
    </select>
    <label><input type="checkbox" id="dark"> Dark</label>
    <label><input type="checkbox" id="actual"> Actual size</label>
    <button class="secondary small" id="undo" title="Undo (Ctrl+Z)">↶</button>
    <button class="secondary small" id="redo" title="Redo (Ctrl+Y)">↷</button></div>
  <div class="error" id="error"></div>
  <div class="main">
    <div>
      <div class="stage" id="stage"><img id="img" alt="" draggable="false"></div>
      <div class="issues" id="issues"></div>
    </div>
    <div class="side">
      <div class="props" id="props"><div class="empty">Click a control to edit it. Ctrl+click selects more.</div></div>
      <details class="tree" id="treeBox" open><summary>Structure</summary><div id="tree"></div></details>
    </div>
  </div>
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  const img = document.getElementById('img');
  const stage = document.getElementById('stage');
  const propsEl = document.getElementById('props');
  const toolbox = document.getElementById('toolbox');
  let layout = null, selected = null, selection = null, hoverName = null, drag = null;
  let controlsInfo = [], multi = [], issues = [], tree = [];
  const issuesEl = document.getElementById('issues');
  const treeEl = document.getElementById('tree');

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
  document.getElementById('actual').addEventListener('change', e => {
    document.body.classList.toggle('actual', e.target.checked);
    drawBoxes();
  });

  function scale() { return layout ? img.clientWidth / layout.width : 1; }
  function byName(n) { return layout && layout.controls.find(c => c.name === n); }
  function depth(c) { let d = 0; while (c && c.parent) { c = byName(c.parent); d++; } return d; }
  function isInside(c, ancestor) { while (c) { if (c.name === ancestor) return true; c = byName(c.parent); } return false; }

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
      if (d > bestDepth) { best = c; bestDepth = d; }
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

  function drawBoxes() {
    stage.querySelectorAll('.box, .drop').forEach(e => e.remove());
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
      box(s, 'selected' + (drag && drag.name === s.name && drag.active ? ' ghost' : ''), label);
    }
    if (drag && drag.target) drawDrop(drag.target);
  }

  function drawTree() {
    treeEl.innerHTML = '';
    for (const t of tree) {
      const d = document.createElement('div');
      d.className = 'item' + (multi.includes(t.name) ? ' on' : '') + (t.nonvisual ? ' nv' : '');
      d.style.paddingLeft = (4 + t.depth * 14) + 'px';
      d.textContent = t.name;
      const c = document.createElement('span'); c.className = 'c'; c.textContent = t.className; d.appendChild(c);
      if (issues.some(i => i.name === t.name)) { const b = document.createElement('span'); b.className = 'bad'; b.textContent = '⚠'; d.appendChild(b); }
      d.addEventListener('click', e => choose(t.name, (e.ctrlKey || e.metaKey || e.shiftKey) && t.depth > 0));
      treeEl.appendChild(d);
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

  // where a drop at point p would go: container + index among its children
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

  // ---- selecting and moving controls with the mouse ----
  stage.addEventListener('mousemove', e => {
    const p = pointFromEvent(e);
    if (drag) {
      if (!drag.active && Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy) > 5) drag.active = true;
      if (drag.active) { drag.target = dropTarget(p, drag.name); drawBoxes(); }
      return;
    }
    const c = hit(p);
    const n = c ? c.name : null;
    if (n !== hoverName) { hoverName = n; drawBoxes(); }
  });
  stage.addEventListener('mouseleave', () => { hoverName = null; if (!drag) drawBoxes(); });
  stage.addEventListener('mousedown', e => {
    if (e.button !== 0) return;
    const c = hit(pointFromEvent(e));
    if (!c) return;
    const add = (e.ctrlKey || e.metaKey || e.shiftKey) && !!c.parent;
    if (add || c.name !== selected || multi.length > 1) choose(c.name, add);
    drag = c.parent && !add ? { name: c.name, sx: e.clientX, sy: e.clientY, active: false, target: null } : null;
    drawBoxes();
    e.preventDefault();
  });
  window.addEventListener('mouseup', () => {
    if (drag && drag.active && drag.target) {
      vscode.postMessage({ type: 'move', name: drag.name, parent: drag.target.container.name, index: drag.target.index });
    }
    drag = null;
    drawBoxes();
  });
  window.addEventListener('keydown', e => {
    const typing = document.activeElement && ['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement.tagName);
    if ((e.key === 'Delete' || e.key === 'Backspace') && selected && !typing) {
      const names = multi.filter(n => { const c = byName(n); return !c || c.parent; });
      if (names.length && selected !== (layout && layout.controls[0].name)) vscode.postMessage({ type: 'delete', name: names[0], names });
    }
    // Alt+arrows: earlier or later among its siblings
    if (e.altKey && !typing && selected && multi.length === 1 && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
      e.preventDefault();
      vscode.postMessage({ type: 'moveSibling', name: selected, delta: e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 1 });
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
        if ((cmd === 'copy' || cmd === 'cut' || cmd === 'duplicate') && !(c && c.parent) && multi.length < 2) return;
        vscode.postMessage({ type: cmd, name: selected, names: multi });
      }
    }
    if (e.key === 'F2' && selected && !typing) {
      const c = byName(selected);
      if (c && c.parent) vscode.postMessage({ type: 'rename', name: selected });
    }
    if (e.key === 'Escape' && !typing) {
      if (drag) { drag = null; drawBoxes(); }
      else if (multi.length > 1) choose(selected, false);
      else if (selected) { const c = byName(selected); if (c && c.parent) choose(c.parent, false); }
    }
  });

  // ---- toolbox: drag new controls in ----
  function buildToolbox() {
    toolbox.querySelectorAll('.chip').forEach(e => e.remove());
    const hint = toolbox.querySelector('.hint');
    // the project's own controls first
    const ordered = controlsInfo.filter(c => c.project).concat(controlsInfo.filter(c => !c.project));
    for (const c of ordered) {
      const chip = document.createElement('span');
      chip.className = 'chip' + (c.project ? ' project' : '') + (c.nonvisual ? ' nonvisual' : '');
      chip.textContent = c.name.replace(/^T/, '');
      chip.draggable = true;
      chip.title = (c.project ? 'From this project or its libraries (src/controls). ' : '') +
        (c.nonvisual ? 'Not visible on the form: it goes to the top of the .pform. ' : '') +
        'Drag onto the form, or click to add after the selected control';
      chip.addEventListener('dragstart', e => { e.dataTransfer.setData('text/plain', c.name); e.dataTransfer.effectAllowed = 'copy'; });
      chip.addEventListener('click', () => addNear(c.name));
      toolbox.insertBefore(chip, hint);
    }
  }
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
    if (sel.container) {
      // into the selected container, at the end
      vscode.postMessage({ type: 'add', className, parent: sel.name, index: 9999 });
    } else {
      // right after the selected control
      const siblings = layout.controls.filter(c => c.parent === sel.parent);
      vscode.postMessage({ type: 'add', className, parent: sel.parent, index: siblings.indexOf(sel) + 1 });
    }
  }
  stage.addEventListener('dragover', e => {
    e.preventDefault();
    drag = { name: null, active: true, target: dropTarget(pointFromEvent(e), null), isNew: true };
    drawBoxes();
  });
  stage.addEventListener('dragleave', () => { drag = null; drawBoxes(); });
  stage.addEventListener('drop', e => {
    e.preventDefault();
    const className = e.dataTransfer.getData('text/plain');
    const t = dropTarget(pointFromEvent(e), null);
    drag = null;
    if (className && isNonVisual(className)) addNear(className);
    else if (className && t) vscode.postMessage({ type: 'add', className, parent: t.container.name, index: t.index });
    drawBoxes();
  });

  // ---- property panel ----
  function send(prop, propType, value) {
    vscode.postMessage({ type: 'setProp', name: selection.name, names: selection.names, prop, propType, value });
  }
  function input(p) {
    const cur = p.value === undefined ? '' : p.value;
    let el;
    if (p.type === 'enum') {
      el = document.createElement('select');
      el.appendChild(new Option('(default)', ''));
      for (const v of p.values) el.appendChild(new Option(v, v));
      el.value = cur;
      el.addEventListener('change', () => send(p.name, p.type, el.value === '' ? null : el.value));
    } else if (p.type === 'boolean') {
      el = document.createElement('input'); el.type = 'checkbox';
      el.checked = cur === 'True';
      el.addEventListener('change', () => send(p.name, p.type, el.checked ? 'True' : 'False'));
    } else if (p.type === 'color') {
      el = document.createElement('span'); el.className = 'inline';
      const c = document.createElement('input'); c.type = 'color';
      c.value = /^#[0-9a-fA-F]{6}$/.test(cur) ? cur : (/^#[0-9a-fA-F]{8}$/.test(cur) ? '#' + cur.slice(3) : '#000000');
      c.addEventListener('change', () => send(p.name, p.type, c.value));
      const clear = document.createElement('button'); clear.className = 'secondary small'; clear.textContent = '×';
      clear.title = 'Use the default'; clear.addEventListener('click', () => send(p.name, p.type, null));
      el.append(c, clear);
    } else if (p.type === 'event') {
      el = document.createElement('span'); el.className = 'inline';
      const t = document.createElement('input'); t.value = cur; t.placeholder = '(none)';
      t.setAttribute('list', 'handlers');
      t.addEventListener('change', () => send(p.name, p.type, t.value.trim() === '' ? null : t.value.trim()));
      const go = document.createElement('button'); go.className = 'small'; go.textContent = '→';
      go.title = cur ? 'Open the code' : 'Create the handler in the code';
      go.addEventListener('click', () => vscode.postMessage({ type: 'code', name: selection.name, prop: p.name,
        handler: t.value.trim(), signature: p.signature }));
      el.append(t, go);
    } else {
      el = document.createElement('input');
      el.value = cur;
      if (p.type === 'integer' || p.type === 'number') el.inputMode = 'numeric';
      if (p.suggest) {
        // a list to choose from (icon names), typing something else stays possible
        const id = 'suggest-' + p.name;
        if (!document.getElementById(id)) {
          const dl = document.createElement('datalist'); dl.id = id;
          for (const v of p.suggest) dl.appendChild(new Option(v, v));
          document.body.appendChild(dl);
        }
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
    selection = sel;
    if (same) {
      for (const p of sel.props) {
        const lab = propsEl.querySelector('label[data-for="' + p.name + '"]');
        if (lab) lab.classList.toggle('set', p.value !== undefined);
      }
      return;
    }
    propsEl.innerHTML = '';
    if (!sel) { propsEl.innerHTML = '<div class="empty">Click a control to edit it. Ctrl+click selects more.</div>'; return; }
    const several = sel.names && sel.names.length > 1;
    const h = document.createElement('h3');
    if (several) {
      h.textContent = sel.names.length + ' controls';
    } else if (sel.isRoot) {
      h.textContent = sel.name;
    } else {
      // the name can be changed here: the form's code follows
      const nm = document.createElement('input'); nm.value = sel.name; nm.className = 'name'; nm.title = 'Rename (F2): the code in the .pas file is updated too';
      nm.addEventListener('change', () => vscode.postMessage({ type: 'rename', name: sel.name, newName: nm.value.trim() }));
      nm.addEventListener('keydown', e => { if (e.key === 'Enter') nm.blur(); if (e.key === 'Escape') { nm.value = sel.name; nm.blur(); } });
      h.appendChild(nm);
    }
    const cls = document.createElement('div'); cls.className = 'cls';
    cls.textContent = several ? sel.names.join(', ') + ' — what they all have' : sel.className;
    propsEl.append(h, cls);
    const dl = document.createElement('datalist'); dl.id = 'handlers';
    for (const n of sel.handlers) dl.appendChild(new Option(n));
    propsEl.appendChild(dl);
    const groups = [['Properties', sel.props.filter(p => p.type !== 'event')], ['Events', sel.props.filter(p => p.type === 'event')]];
    for (const [title, list] of groups) {
      if (!list.length) continue;
      const s = document.createElement('div'); s.className = 'section'; s.textContent = title; propsEl.appendChild(s);
      for (const p of list) {
        const row = document.createElement('div'); row.className = 'row';
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
        for (const [label, cls] of [['Row', 'TRow'], ['Column', 'TColumn'], ['Card', 'TCard']]) {
          btn('⊞ ' + label, 'Put ' + (several ? 'them' : 'it') + ' into a new ' + cls, () =>
            vscode.postMessage({ type: 'wrap', names: sel.names, className: cls }));
        }
      }
      if (!several && sel.children > 0) {
        btn('Unwrap', 'Take the controls out of ' + sel.name + ' and remove it', () =>
          vscode.postMessage({ type: 'unwrap', name: sel.name }));
      }
      if (!several) {
        btn('↑', 'Earlier (Alt+Up)', () => vscode.postMessage({ type: 'moveSibling', name: sel.name, delta: -1 }));
        btn('↓', 'Later (Alt+Down)', () => vscode.postMessage({ type: 'moveSibling', name: sel.name, delta: 1 }));
      }
      btn('Delete' + (several ? ' ' + sel.names.length : ''), 'Delete (Del)', () =>
        vscode.postMessage({ type: 'delete', name: sel.names[0], names: sel.names }));
      propsEl.appendChild(bar);
    }
  }

  window.addEventListener('message', e => {
    const m = e.data;
    if (m.type === 'schema') { controlsInfo = m.controls; buildToolbox(); }
    else if (m.type === 'render') {
      img.onload = () => drawBoxes();
      img.src = 'data:image/png;base64,' + m.data;
      layout = m.layout;
      document.body.classList.remove('has-error');
    } else if (m.type === 'select') {
      selected = m.name;
      multi = m.names || (m.name ? [m.name] : []);
      renderProps(m.name ? m : null);
      drawBoxes();
      drawTree();
    } else if (m.type === 'tree') {
      tree = m.items;
      drawTree();
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
</script>
</body>
</html>`;
}
