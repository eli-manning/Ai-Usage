/* Settings (settings.html), in a regular window on Mochi's paper. The app hands it everything to show as one state
   object with page.update(state), every second while it's open, and gets back {type: 'act', name, arg} for each
   click (arg is a provider id or key=value). Also opens in a browser with sample data, for working on the look. */
(() => {
  'use strict';
  const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.page;
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

  const IDS = Object.keys(MINI_LOOKS);
  let S = null, drawn = '';

  // ---------- pieces ----------
  const sw = (on, name, arg) => h('button', { class: 'switch' + (on ? ' on' : ''), title: on ? 'on' : 'off', onclick: () => act(name, arg) });
  const row = (label, ...end) => h('div', { class: 'set' }, h('span', {}, label), h('span', { class: 'end' }, end));
  const toggleRow = (label, on, name, arg) => h('button', { class: 'set', onclick: () => act(name, arg) },
    h('span', {}, label), h('span', { class: 'switch' + (on ? ' on' : '') }));
  const seg = (cur, key, opts) => h('span', { class: 'seg' }, opts.map(([l, v]) =>
    h('button', { class: String(cur) === String(v) ? 'on' : '', onclick: () => act('set', key + '=' + v) }, l)));
  const pxb = (label, onclick, cls) => h('button', { class: 'pxb' + (cls ? ' ' + cls : ''), onclick }, label);

  // the critters are built once each, so they keep animating instead of restarting every second
  const faces = {};
  function face(id) {
    if (!faces[id]) {
      const el = h('div', { class: 'face' });
      const look = MINI_LOOKS[id] || {};
      new Critter(el, { pose: 'idle', scale: 1, species: look.species, palette: look.palette, particles: false });
      faces[id] = el;
    }
    return faces[id];
  }
  const picker = h('div', { class: 'closet' }, IDS.map((id) => {
    const stage = h('div', { class: 'stage' });
    const look = MINI_LOOKS[id];
    new Critter(stage, { pose: 'idle', scale: 1.5, species: look.species, palette: look.palette });
    return h('button', { 'data-id': id, title: look.name, onclick: () => act('set', 'provider=' + id) }, stage, h('span', {}, look.name.toLowerCase()));
  }));

  // ---------- sections ----------
  function appearance() {
    const notchOff = !S.hasNotch;
    return [
      h('h2', {}, 'appearance'),
      h('div', { class: 'cap' }, 'where your usage lives while the app runs.'),
      h('div', { class: 'set' }, h('span', { class: 'two' }, h('span', {}, 'show usage in'),
        h('span', { class: 'line' }, notchOff ? 'this display has no notch.' : S.displayMode === 'notch' ? 'a pill under the notch.' : 'a badge in the menu bar.')),
        h('span', { class: 'seg' },
          h('button', { class: S.displayMode === 'tray' ? 'on' : '', onclick: () => act('displayMode', 'tray') }, 'menu bar'),
          h('button', { class: S.displayMode === 'notch' ? 'on' : '', disabled: notchOff, onclick: () => act('displayMode', 'notch') }, 'notch'))),
    ];
  }

  function providers() {
    return [
      h('h2', {}, 'providers'),
      h('div', { class: 'cap' }, 'switching one off stops this app from launching its cli at all.'),
      S.providers.map((p) => h('div', { class: 'set' + (p.enabled ? '' : ' off') },
        h('span', { class: 'who' }, face(p.id), h('span', { class: 'two' }, h('span', {}, p.name),
          h('span', { class: 'line ' + (p.tone || '') }, p.status))),
        h('span', { class: 'end' }, p.action && pxb(p.action, () => act('providerAction', p.id), 'primary'),
          sw(p.enabled, 'enable', p.id + '=' + !p.enabled)))),
    ];
  }

  function mini() {
    const m = S.minis;
    const off = !m.enabled;
    const dim = (el) => { if (off) el.classList.add('disabled'); return el; };
    const hookLine = (k) => k.installed ? (k.live ? `connected · ${k.live} session${k.live === 1 ? '' : 's'} open.` : 'connected.')
      : k.canInstall ? 'not connected.' : "cli hasn't been run on this mac yet.";
    picker.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.id === m.provider));
    const out = [
      h('h2', {}, 'mini'),
      h('div', { class: 'cap' }, "one critter on screen that follows the agent sessions of the provider you pick. right-click it for its panel. nothing leaves your mac."),
      h('button', { class: 'set', onclick: () => act('set', 'enabled=' + off) },
        h('span', { class: 'two' }, h('span', {}, 'show the mini'),
          h('span', { class: 'line' + (!m.listening && m.enabled ? ' error' : '') },
            !m.listening && m.enabled ? `can't listen on port ${m.port}. is another copy running?` : 'connected providers alert you, whichever mini is out.')),
        h('span', { class: 'switch' + (m.enabled ? ' on' : '') })),
      dim(picker),
      h('h2', {}, 'hooks', h('span', { class: 'end' }, 'alerts')),
      m.hooks.map((k) => dim(h('div', { class: 'set' },
        h('span', { class: 'two' }, h('span', {}, k.name), h('span', { class: 'line' + (k.installed ? ' ok' : '') }, hookLine(k))),
        h('span', { class: 'end' },
          k.installed && pxb('test', () => act('test', k.id)),
          (k.installed || k.canInstall) && pxb(k.installed ? 'disconnect' : 'connect', () => act('hook', k.id + '=' + !k.installed), k.installed ? '' : 'primary'),
          sw(k.alertsOn, 'set', 'alerts.' + k.id + '=' + !k.alertsOn))))),
      m.note && h('div', { class: 'note' }, m.note),
      m.error && h('div', { class: 'note error' }, m.error),

      h('h2', {}, 'how it behaves'),
      dim(row('says', seg(m.speech, 'speech', [['alerts', 'alertsOnly'], ['status', 'status'], ['detail', 'detailed']]))),
      dim(row('animation', seg(m.animation, 'animation', [['full', 'full'], ['subtle', 'subtle'], ['still', 'minimal']]))),
      dim(row('moves', seg(m.motion, 'motion', [['stays put', 'still'], ['paces', 'pace']]))),
      dim(row('corner', seg(m.placement, 'placement', [['left', 'bottomLeft'], ['right', 'bottomRight']]))),
      dim(row('size', seg(m.scale, 'scale', [['s', 2], ['m', 2.5], ['l', 3], ['xl', 4]]))),
      dim(row('forget idle sessions', seg(m.idleMinutes, 'idleMinutes', [['5m', 5], ['10m', 10], ['20m', 20], ['1h', 60], ['4h', 240]]))),

      h('h2', {}, 'alerts', h('span', { class: 'end' }, 'they wait until you answer')),
      [['done', 'when it finishes'], ['needsInput', 'when it needs input'], ['failed', 'when it fails']].map(([kind, label]) => {
        const a = m.alerts[kind] || {};
        const i = Math.max(0, m.sounds.indexOf(a.sound));
        const step = (d) => act('set', `sound.${kind}=` + m.sounds[(i + d + m.sounds.length) % m.sounds.length]);
        return dim(h('div', { class: 'set' }, h('span', {}, label), h('span', { class: 'end' },
          h('span', { class: 'sound' }, pxb('‹', () => step(-1), 'tiny'), h('span', { class: 'name' }, (a.sound || '').toLowerCase()), pxb('›', () => step(1), 'tiny')),
          pxb('play', () => act('preview', kind), 'tiny'),
          sw(a.on !== false, 'set', `alert.${kind}=` + (a.on === false)))));
      }),
      dim(row('repeat sound', seg(m.repeatSeconds, 'repeatSeconds', [['once', 0], ['15s', 15], ['30s', 30], ['1m', 60], ['2m', 120], ['5m', 300]]))),
      dim(row('volume', seg(Math.round(m.volume * 4) / 4, 'volume', [['25%', 0.25], ['50%', 0.5], ['75%', 0.75], ['100%', 1]]))),
      dim(h('div', { class: 'set' }, h('span', { class: 'two' }, h('span', {}, 'notifications'),
        h('span', { class: 'line' }, 'to keep them up, use the alerts style.')),
        h('span', { class: 'end' }, pxb('open', () => act('openNotifications')), sw(m.notifications, 'set', 'notifications=' + !m.notifications)))),
    ];
    return out;
  }

  function general() {
    return [
      h('h2', {}, 'general'),
      toggleRow('start at login', S.launchAtLogin, 'login', !S.launchAtLogin),
      h('div', { class: 'set' }, h('span', { class: 'two' }, h('span', {}, 'setup wizard'), h('span', { class: 'line' }, 'walk through finding and signing in again.')),
        h('span', { class: 'end' }, pxb('run', () => act('wizard')))),
      h('div', { class: 'set' }, h('span', { class: 'two' }, h('span', {}, 'stored data'), h('span', { class: 'line' }, 'settings and usage history, in application support.')),
        h('span', { class: 'end' }, pxb('reveal', () => act('reveal')))),
      h('div', { class: 'foot' }, h('span', { class: 'muted' }, S.version ? 'ai usage ' + S.version : 'ai usage'), pxb('quit', () => act('quit'))),
    ];
  }

  // ---------- drawing ----------
  function render() {
    const key = JSON.stringify(S);
    if (key === drawn) return;
    drawn = key;
    const body = $('body'), top = body.scrollTop;
    body.replaceChildren(...[appearance(), providers(), mini(), general()].flat(3).filter(Boolean));
    body.scrollTop = top;   // a redraw every second mustn't jump you back to the top
  }

  window.page = { update(state) { S = state; render(); } };
  if (native) post({ type: 'ready' });

  // opened in a browser: sample data
  if (!native) {
    if (new URLSearchParams(location.search).has('full')) document.documentElement.classList.add('full');
    page.update({
      version: '1.3', displayMode: 'tray', hasNotch: true, launchAtLogin: true,
      providers: [
        { id: 'claude', name: 'claude', enabled: true, status: 'signed in.', tone: 'ok' },
        { id: 'antigravity', name: 'antigravity', enabled: true, status: 'installed, not signed in.', tone: '', action: 'log in' },
        { id: 'codex', name: 'codex', enabled: true, status: 'signed in (showing last known usage)', tone: 'warn' },
        { id: 'cursor', name: 'cursor', enabled: false, status: 'turned off.', tone: '' },
      ],
      minis: {
        enabled: true, listening: true, port: 47834, provider: 'codex',
        hooks: [
          { id: 'claude', name: 'claude', installed: true, canInstall: true, alertsOn: true, live: 2 },
          { id: 'antigravity', name: 'antigravity', installed: false, canInstall: false, alertsOn: true, live: 0 },
          { id: 'codex', name: 'codex', installed: true, canInstall: true, alertsOn: true, live: 1 },
          { id: 'cursor', name: 'cursor', installed: false, canInstall: true, alertsOn: false, live: 0 },
        ],
        note: 'codex: codex runs new hooks only after you approve them: open codex and type /hooks.', error: '',
        speech: 'status', animation: 'subtle', motion: 'still', placement: 'bottomRight', scale: 2.5, idleMinutes: 20,
        alerts: { done: { on: true, sound: 'Glass' }, needsInput: { on: true, sound: 'Ping' }, failed: { on: false, sound: 'Basso' } },
        repeatSeconds: 30, volume: 0.6, notifications: true,
        sounds: ['None', 'Basso', 'Blow', 'Bottle', 'Frog', 'Funk', 'Glass', 'Hero', 'Morse', 'Ping', 'Pop', 'Purr', 'Sosumi', 'Submarine', 'Tink'],
      },
    });
  }
})();
