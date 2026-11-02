// Pastel's website: search over search.json, light or dark, code colors, "On this page".
(function () {
  const root = document.documentElement;

  // light or dark: the system's choice until a click, then remembered
  function applyTheme(t) {
    root.dataset.bsTheme = t;
    const light = document.getElementById('hl-light'), dark = document.getElementById('hl-dark');
    if (light) light.disabled = t === 'dark';
    if (dark) dark.disabled = t !== 'dark';
  }
  applyTheme(root.dataset.bsTheme || 'light');
  const themeButton = document.getElementById('theme');
  if (themeButton) themeButton.addEventListener('click', () => {
    const t = root.dataset.bsTheme === 'dark' ? 'light' : 'dark';
    applyTheme(t);
    try { localStorage.setItem('pastel-theme', t); } catch (e) { /* private window */ }
  });

  // code colors: ```pascal is Delphi's grammar
  if (window.hljs) {
    document.querySelectorAll('pre code').forEach(el => {
      if (/language-(pascal|pas|delphi|pform)/.test(el.className)) el.className = 'language-delphi';
      if (/language-(toml|ini)/.test(el.className)) el.className = 'language-ini';
      if (!/language-/.test(el.className)) el.classList.add('nohighlight');
      try { hljs.highlightElement(el); } catch (e) { /* an unknown language */ }
    });
  }

  // On this page: the heading being read
  const toc = document.querySelectorAll('.docs-toc a');
  if (toc.length && 'IntersectionObserver' in window) {
    const byId = new Map([...toc].map(a => [decodeURIComponent(a.hash.slice(1)), a]));
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          toc.forEach(a => a.classList.remove('active'));
          const a = byId.get(e.target.id);
          if (a) a.classList.add('active');
        }
      });
    }, { rootMargin: '0px 0px -75% 0px' });
    document.querySelectorAll('.markdown h2[id]').forEach(h => io.observe(h));
  }
  const current = document.querySelector('.docs-nav a.current');
  const side = document.querySelector('.docs-sidebar');
  if (current && side && side.scrollHeight > side.clientHeight) {
    side.scrollTop = current.getBoundingClientRect().top - side.getBoundingClientRect().top - side.clientHeight / 2;
  }

  // search over the pages' titles, headings and text
  const input = document.getElementById('search');
  const box = document.getElementById('results');
  if (!input || !box) return;
  const base = input.dataset.base;
  let index = null;
  let active = -1;
  async function load() {
    if (!index) index = await (await fetch(base + 'search.json')).json();
    return index;
  }
  function score(p, words) {
    let s = 0;
    const t = p.title.toLowerCase(), h = p.headings.join(' ').toLowerCase(), x = p.text.toLowerCase();
    for (const w of words) {
      if (t.includes(w)) s += 10; else if (h.includes(w)) s += 4; else if (x.includes(w)) s += 1; else return 0;
    }
    return s;
  }
  function esc(s) { return s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]); }
  function slug(s) {
    return s.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\p{L}\p{N}\s_-]/gu, '').trim().replace(/\s/g, '-');
  }
  input.addEventListener('input', async () => {
    const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) { box.style.display = 'none'; return; }
    let pages;
    try { pages = await load(); } catch (e) { box.innerHTML = '<span class="dropdown-item-text">The search needs the site on a web server.</span>'; box.style.display = 'block'; return; }
    const hits = pages.map(p => ({ p, s: score(p, words) })).filter(h => h.s > 0).sort((a, b) => b.s - a.s).slice(0, 12);
    active = -1;
    box.innerHTML = hits.length ? hits.map(h => {
      const head = h.p.headings.find(x => words.some(w => x.toLowerCase().includes(w)));
      const href = base + h.p.page + (head ? '#' + slug(head) : '');
      return `<a href="${esc(href)}">${esc(h.p.title)}${head ? `<small>${esc(head)}</small>` : ''}</a>`;
    }).join('') : '<span class="dropdown-item-text text-body-secondary">Nothing found</span>';
    box.style.display = 'block';
  });
  input.addEventListener('keydown', e => {
    const links = box.querySelectorAll('a[href]');
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      active = Math.max(0, Math.min(links.length - 1, active + (e.key === 'ArrowDown' ? 1 : -1)));
      links.forEach((l, i) => l.classList.toggle('active', i === active));
    } else if (e.key === 'Enter' && links.length) {
      location.href = links[Math.max(0, active)].href;
    } else if (e.key === 'Escape') {
      box.style.display = 'none';
      input.blur();
    }
  });
  document.addEventListener('click', e => { if (e.target !== input) box.style.display = 'none'; });
  document.addEventListener('keydown', e => {
    if (e.key === '/' && !/^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName)) { e.preventDefault(); input.focus(); }
  });
})();
