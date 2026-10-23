/* The menu bar dropdown (menu.html): your plan usage for each provider, in Mochi's panel. The app hands it one state
   object (see StatusItemController.state) through panel.show / panel.update, and panel.place points the tail up at
   the menu bar icon. Clicks go back as {type: 'act', name, arg}. Also opens in a browser with sample data. */
(() => {
  'use strict';
  const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.panel;
  const post = (m) => { if (native) native.postMessage(m); };
  const act = (name, arg) => post({ type: 'act', name, arg: arg == null ? null : String(arg) });
  const $ = (id) => document.getElementById(id);

  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (v !== false && v != null) el.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat()) if (k != null && k !== false) el.append(k.nodeType ? k : document.createTextNode(k));
    return el;
  }
  const icon = (el, name) => { MochiIcons.render(el, `:${name}:`, false); return el; };

  let S = {}, drawn = '', details = false, face = null, faceFor = '';
  const look = (id) => MINI_LOOKS[id] || MINI_LOOKS.claude;
  // past 70% a meter turns amber, past 90% red, whichever provider it is
  const tier = (pct) => pct >= 90 ? 'var(--red)' : pct >= 70 ? '#e0a43b' : 'var(--orange)';

  function meter(g) {
    const lit = g.pct == null ? 0 : Math.round(Math.min(100, Math.max(0, g.pct)) / 5);   // 20 blocks, 5% each
    return h('div', { class: 'meter' },
      h('div', { class: 'top' }, h('span', {}, g.label), h('span', { class: 'pct' }, g.pct == null ? '–' : g.pct + '%')),
      h('div', { class: 'bar', style: `--fill:${tier(g.pct || 0)}` }, Array.from({ length: 20 }, (_, k) => h('i', { class: k < Math.max(g.pct ? 1 : 0, lit) ? 'lit' : '' }))),
      (g.reset || g.sub) && h('div', { class: 'small muted sub' }, h('span', {}, g.reset ? 'resets ' + g.reset : ''), h('span', {}, g.sub || '')));
  }

  function chart(hist) {
    const bars = hist.bars || [];
    return [
      h('h2', {}, 'history', h('span', { class: 'end' }, h('span', { class: 'seg' }, [['session', 'day'], ['weekly', 'week']].map(([m, l]) =>
        h('button', { class: hist.mode === m ? 'on' : '', onclick: () => act('chart', m) }, l))))),
      h('div', { class: 'chart' }, bars.map((v) => h('i', { class: v == null ? 'none' : '', style: v == null ? '' : `height:${Math.max(4, v)}%;--fill:${tier(v)}`, title: v == null ? '' : v + '%' }))),
      h('div', { class: 'chart-axis small muted' }, h('span', {}, hist.mode === 'weekly' ? '7 days ago' : '24h ago'), h('span', {}, 'now')),
    ];
  }

  function body() {
    const b = S.body || { kind: 'empty', title: '...' };
    if (b.kind === 'empty') {
      return h('div', { class: 'empty' + (b.error ? ' error' : '') }, h('p', {}, b.title),
        b.hint && h('div', { class: 'hint' }, b.hint),
        b.action && h('button', { class: 'pxb primary', onclick: () => act(b.action.name, b.action.arg) }, b.action.label));
    }
    const out = [];
    if (b.banner) out.push(h('div', { class: 'banner' }, b.banner));
    out.push(...(b.gauges || []).map(meter));
    const d = b.details;
    if (d) {
      out.push(h('div', { class: 'details-toggle' }, h('button', { class: 'pxb', onclick: () => { details = !details; render(true); } }, details ? 'less' : 'more')));
      if (details) {
        if (d.history) out.push(...chart(d.history));
        if (d.promo) out.push(h('div', { class: 'promo' }, d.promo));
        for (const [title, rows] of [['skills', d.skills], ['mcp servers', d.mcp]]) {
          if (!rows || !rows.length) continue;
          out.push(h('h2', {}, title), ...rows.map((r) => h('div', { class: 'set' }, h('span', {}, r.name), h('span', { class: 'pct' }, r.pct + '%'))));
        }
        if (d.stats && d.stats.length) {
          out.push(h('h2', {}, 'all time'), h('div', { class: 'stats' }, d.stats.map(([label, value]) => h('div', {}, h('b', { title: value }, value), h('span', {}, label)))));
          if (d.fact) out.push(h('div', { class: 'fact' }, d.fact));
        }
      }
    }
    return out;
  }

  function render(force) {
    const key = JSON.stringify([S, details]);
    if (key === drawn && !force) return;
    drawn = key;
    const L = look(S.provider);
    $('card').style.setProperty('--accent', L.accent);
    // the provider's own mini, live, so the dropdown and the mini read as one app
    if (faceFor !== S.provider) {
      faceFor = S.provider;
      if (face) face.destroy();
      face = new Critter($('face'), { pose: 'idle', scale: 1.5, species: L.species, palette: L.palette, particles: false });
    }
    $('name').textContent = (L.name || '').toLowerCase();
    $('mood').textContent = S.mood || '';
    $('refresh').classList.toggle('spin', !!S.refreshing);
    $('tabs').replaceChildren(...(S.tabs || []).map((t) => h('button', { class: t.id === S.provider ? 'on' : '', title: t.title || '', onclick: () => { if (t.id !== S.provider) { details = false; act('select', t.id); } } },
      (look(t.id).name || t.id).toLowerCase(), h('span', { class: 'tab-dot ' + (t.dot || '') }))));
    $('tabs').hidden = (S.tabs || []).length < 2;
    $('body').replaceChildren(...[body()].flat().filter(Boolean));
    $('body').classList.toggle('scroll', details);
    $('version').textContent = S.version ? 'ai usage ' + S.version : '';
  }

  icon($('refresh'), 'refresh').addEventListener('click', () => act('refresh'));
  icon($('gear'), 'gear').addEventListener('click', () => act('settings'));
  $('quit').addEventListener('click', () => act('quit'));
  addEventListener('keydown', (e) => { if (e.key === 'Escape') post({ type: 'close' }); });
  const wrap = $('wrap');
  new ResizeObserver(() => post({ type: 'size', w: wrap.offsetWidth, h: wrap.offsetHeight })).observe(wrap);

  window.panel = {
    show(state, below) {
      S = state;
      details = false;
      $('wrap').classList.toggle('below', !!below);
      render(true);
      const card = $('card');
      card.focus({ preventScroll: true });
      card.classList.remove('pop');
      void card.offsetWidth;
      card.classList.add('pop');
    },
    update(state) { S = state; render(); },
    place(tail, below) {
      $('wrap').classList.toggle('below', !!below);
      $('card').style.setProperty('--tail-left', tail - 9 + 'px');
    },
  };

  if (!native) {
    const q = new URLSearchParams(location.search);
    const p = q.get('provider') || 'claude';
    const bars = Array.from({ length: 24 }, (_, i) => (i < 4 ? null : Math.round(10 + i * 3.2 + (i % 5) * 4)));
    const sample = {
      claude: { kind: 'gauges', gauges: [{ label: 'session', pct: 38, reset: '9:20 pm' }, { label: 'weekly', pct: 74, reset: 'sun 12:00 pm' },
        { label: 'credits', pct: 12, reset: 'nov 1', sub: '$6.00 / $50.00 spent' }],
        details: { history: { mode: 'session', bars }, promo: 'double usage on weekends this month',
          skills: [{ name: 'frontend-design', pct: 21 }, { name: 'pdf', pct: 8 }], mcp: [{ name: 'linear', pct: 4 }],
          stats: [['favorite model', 'opus 5.5'], ['total tokens', '48.2m'], ['sessions', '312'], ['active days', '61/90'], ['longest streak', '19 days'], ['current streak', '6 days']],
          fact: "you've written about 3 novels' worth of tokens." } },
      codex: { kind: 'gauges', banner: 'offline: showing last known usage', gauges: [{ label: '5h', pct: 91, reset: '4:10 pm' }, { label: 'weekly', pct: 46, reset: 'fri' }] },
      antigravity: { kind: 'empty', title: "antigravity isn't installed.", hint: 'brew install --cask antigravity-cli', action: { label: 'install', name: 'install', arg: 'antigravity' } },
      cursor: { kind: 'empty', title: 'cursor is installed, but not signed in yet.', hint: 'run cursor-agent, then /usage.', action: { label: 'log in', name: 'login', arg: 'cursor' } },
    };
    panel.show({
      provider: p, mood: 'updated 2m ago', refreshing: q.has('refreshing'), version: '1.3',
      tabs: [{ id: 'claude', dot: 'warn' }, { id: 'antigravity', dot: '' }, { id: 'codex', dot: 'bad' }, { id: 'cursor', dot: '' }],
      body: sample[p],
    }, true);
    if (q.has('details')) { details = true; render(true); }
    panel.place(240, true);
  }
})();
