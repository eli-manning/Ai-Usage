/* The mini's panel (panel.html), opened by right-clicking the mini: Mochi's panel, for agent sessions. The app hands
   it everything to show as one state object and gets back what you click: panel.show(state, below) when it opens,
   panel.update(state) every second while open, panel.place(tailX, below) to point the tail at the mini. It posts
   {type: 'act' | 'tab' | 'size' | 'close'} to the app. Also opens in a browser with sample data, for working on the look. */
(() => {
  'use strict';
  const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.panel;
  const post = (m) => { if (native) native.postMessage(m); };
  const act = (name, arg) => post({ type: 'act', name, arg: arg == null ? null : String(arg) });
  const $ = (id) => document.getElementById(id);

  // tiny element builder: h('div', {class: 'x', onclick}, child, 'text', ...)
  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (v !== false && v != null) el.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat()) if (k != null && k !== false) el.append(k.nodeType ? k : document.createTextNode(k));
    return el;
  }
  const say = (tag, attrs, text) => { const el = h(tag, attrs); MochiIcons.render(el, text, false); return el; };

  const TABS = [['sessions', 'sessions'], ['pick', 'pick a mini'], ['settings', ':gear:']];
  const IDS = Object.keys(MINI_LOOKS);

  let S = {}, tab = 'sessions', drawn = '';
  const name = () => (MINI_LOOKS[S.provider] || {}).name || S.provider || '';

  const VIEWS = {
    sessions() {
      const out = [];
      if (S.usage) {
        const w = S.usage;
        const fill = w.pct >= 90 ? 'var(--red)' : w.pct >= 70 ? '#e0a43b' : 'var(--orange)';
        const lit = Math.round(Math.min(100, Math.max(0, w.pct)) / 5);   // 20 blocks, 5% each
        out.push(h('h2', {}, 'your ' + name().toLowerCase() + ' plan', h('span', { class: 'end' }, w.updated || '')),
          h('div', { class: 'meter' },
            h('div', { class: 'top' }, h('span', {}, 'used'), h('span', {}, Math.round(w.pct) + '%')),
            h('div', { class: 'bar', style: `--fill:${fill}` }, Array.from({ length: 20 }, (_, k) => h('i', { class: k < Math.max(1, lit) ? 'lit' : '' })))));
      }
      if (!S.connected && !(S.sessions || []).length) {
        out.push(h('div', { class: 'empty' }, h('p', {}, S.canConnect
          ? `connect ${name().toLowerCase()} and this mini follows its sessions.`
          : `run ${name().toLowerCase()} once on this mac, then connect it here.`),
          S.canConnect && h('button', { class: 'pxb primary', onclick: () => act('connect') }, 'connect')));
        if (S.followUp) out.push(h('div', { class: 'small muted' }, S.followUp));
        return out;
      }
      // each session, most recent first: red needs you, coloured is working; click one to jump to its window
      const alerts = (S.sessions || []).filter((s) => s.need || s.done);
      out.push(h('h2', {}, 'sessions', alerts.length > 0 && h('span', { class: 'end' },
        h('button', { class: 'pxb', onclick: () => act('dismissAll') }, 'clear alerts'))));
      if (!(S.sessions || []).length) out.push(h('div', { class: 'muted small' }, `no ${name().toLowerCase()} sessions right now.`));
      for (const s of S.sessions || []) {
        out.push(h('button', { class: 'set sess', title: 'switch to it', onclick: () => act('focus', s.id) },
          h('span', {}, h('span', { class: 'dot' + (s.need ? ' need' : s.busy ? ' busy' : s.done ? ' on' : '') }), s.project || 'session'),
          h('span', { class: 'line' + (s.need ? ' need' : '') }, s.line)));
      }
      if (S.followUp) out.push(h('div', { class: 'small muted' }, S.followUp));
      return out;
    },

    pick() {
      picker.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.id === S.provider));
      return [h('h2', {}, 'pick a mini', h('span', { class: 'end small' }, 'it follows that tool')), picker];
    },

    settings() {
      const c = S.config || {};
      const sw = (label, on, key, value) => h('button', { class: 'set', onclick: () => act('set', key + '=' + value) }, label, h('span', { class: 'switch' + (on ? ' on' : '') }));
      const seg = (label, key, cur, opts) => h('div', { class: 'set' }, label, h('span', { class: 'seg' }, opts.map(([l, v]) =>
        h('button', { class: cur === v ? 'on' : '', onclick: () => act('set', key + '=' + v) }, l))));
      const alerts = c.alerts || {};
      return [
        h('h2', {}, 'mini'),
        seg('size', 'scale', c.scale, [['s', 2], ['m', 2.5], ['l', 3], ['xl', 4]]),
        seg('says', 'speech', c.speech, [['alerts', 'alertsOnly'], ['status', 'status'], ['detail', 'detailed']]),
        seg('moves', 'animation', c.animation, [['full', 'full'], ['subtle', 'subtle'], ['still', 'minimal']]),
        sw('pace while working', c.motion === 'pace', 'motion', c.motion === 'pace' ? 'still' : 'pace'),
        h('h2', {}, 'alerts', h('span', { class: 'end small' }, 'they wait for you')),
        sw('when it finishes', alerts.done !== false, 'alert.done', alerts.done === false),
        sw('when it needs input', alerts.needsInput !== false, 'alert.needsInput', alerts.needsInput === false),
        sw('when it fails', alerts.failed !== false, 'alert.failed', alerts.failed === false),
        seg('repeat sound', 'repeatSeconds', c.repeatSeconds, [['once', 0], ['30s', 30], ['1m', 60], ['5m', 300]]),
        sw('notifications', c.notifications !== false, 'notifications', c.notifications === false),
        h('h2', {}, name().toLowerCase()),
        h('div', { class: 'set' }, h('span', {}, h('span', { class: 'dot' + (S.connected ? ' on' : '') }),
          S.connected ? 'connected' : S.listening ? 'not connected' : `can't listen on port ${S.port}`),
          (S.connected || S.canConnect) && h('button', { class: 'pxb' + (S.connected ? '' : ' primary'), onclick: () => act('connect') }, S.connected ? 'disconnect' : 'connect')),
        h('div', { class: 'foot' }, h('span', { class: 'muted' }, ''),
          h('button', { class: 'pxb', onclick: () => act('settings') }, 'all settings')),
      ];
    },
  };

  // the picker is built once, so each little critter keeps animating instead of restarting every second
  const picker = h('div', { class: 'closet' }, IDS.map((id) => {
    const stage = h('div', { class: 'stage' });
    const look = MINI_LOOKS[id];
    new Critter(stage, { pose: 'idle', scale: 1.5, species: look.species, palette: look.palette });
    return h('button', { 'data-id': id, title: look.name, onclick: () => act('provider', id) }, stage, h('span', {}, look.name.toLowerCase()));
  }));

  function render(force) {
    const key = JSON.stringify([tab, S]);
    if (key === drawn && !force) return;
    drawn = key;
    $('card').style.setProperty('--accent', (MINI_LOOKS[S.provider] || {}).accent || '#e5714b');
    $('name').textContent = name().toLowerCase();
    $('mood').textContent = S.mood || '';
    const eye = $('eye');
    eye.title = S.hidden ? 'show the mini' : 'hide it until something needs you';
    MochiIcons.render(eye, ':eye:', false);
    eye.style.opacity = S.hidden ? 0.4 : 1;
    $('tabs').replaceChildren(...TABS.map(([id, label]) => {
      const b = say('button', { class: id === tab ? 'on' : '', title: id, onclick: () => { tab = id; post({ type: 'tab', tab }); render(true); } }, label);
      if (id === 'settings') b.classList.add('gear');
      return b;
    }));
    $('body').replaceChildren(...[(VIEWS[tab] || VIEWS.sessions)()].flat().filter(Boolean));
    $('body').classList.toggle('scroll', tab === 'settings');
  }

  $('eye').addEventListener('click', () => act('visible'));
  addEventListener('keydown', (e) => { if (e.key === 'Escape') post({ type: 'close' }); });
  const wrap = $('wrap');
  new ResizeObserver(() => post({ type: 'size', w: wrap.offsetWidth, h: wrap.offsetHeight })).observe(wrap);

  window.panel = {
    show(state, below) {
      S = state;
      tab = VIEWS[state.tab] ? state.tab : 'sessions';
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
      $('card').style.setProperty('--tail-left', tail - 9 + 'px');   // less #wrap's padding and the card's margin
    },
  };

  // opened in a browser: sample data
  if (!native) {
    const params = new URLSearchParams(location.search);
    panel.show({
      tab: params.get('tab') || 'sessions', provider: params.get('provider') || 'codex', mood: 'web · needs input', hidden: false,
      connected: true, canConnect: true, listening: true, port: 47834, usage: { pct: 42, updated: '2 min ago' },
      sessions: [{ id: 'a', project: 'web', line: 'needs input: rm -rf build', need: true },
        { id: 'b', project: 'api', line: 'testing swift test', busy: true }, { id: 'c', project: 'docs', line: 'idle' }],
      config: { scale: 2.5, speech: 'status', animation: 'subtle', motion: 'still', alerts: {}, repeatSeconds: 30, notifications: true },
    }, params.has('below'));
    panel.place(170, params.has('below'));
  }
})();
