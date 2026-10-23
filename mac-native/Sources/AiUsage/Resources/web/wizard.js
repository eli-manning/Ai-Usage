/* The setup wizard (wizard.html), in a PageWindow. The app sends what it detected with page.update(state) every
   second; the step you're on lives here, so that never moves you. Clicks post {type: 'act', name, arg} to `page`:
   install / signin (a provider id), recheck, mode ('tray' | 'notch'), startAtLogin ('true' | 'false'), finish.
   Opened in a browser it shows sample data; ?step=N picks the step. */
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
  // a provider's mini, live, standing on a little stage
  function mini(id, pose, scale, cls) {
    const stage = h('div', { class: 'stage ' + (cls || '') });
    const look = MINI_LOOKS[id] || {};
    new Critter(stage, { pose, scale, species: look.species, palette: look.palette });
    return stage;
  }

  let S = {}, step = 0, drawn = '';
  const steps = () => ['welcome', 'claude', 'providers', ...(S.notch ? ['appearance'] : []), 'login', 'done'];
  const tool = (id) => (S.providers || []).find((p) => p.id === id) || { id, name: (MINI_LOOKS[id] || {}).name || id, line: 'looking...' };

  // one detected tool: its mini, its status, and whatever unblocks it
  function card(p, bare) {
    return h('div', { class: 'set det' }, !bare && mini(p.id, 'idle', 1.25),
      h('div', { class: 'who' }, h('div', {}, p.name.toLowerCase()), h('div', { class: 'line ' + (p.tone || '') }, p.line)),
      p.action ? h('button', { class: 'pxb', onclick: () => act(p.action.name, p.id) }, p.action.title)
        : h('span', { class: 'mark' }, p.tone === 'ok' ? 'ready' : ''));
  }

  // a step's centrepiece: one mini, big, in the space above the step's controls
  const hero = (pose, id) => [h('div', { class: 'grow' }), h('div', { class: 'hero' }, mini(id || S.provider || 'claude', pose, 3.5)), h('div', { class: 'grow' })];

  const STEPS = {
    welcome: () => ({
      title: 'welcome to ai usage',
      sub: 'your plans, and a mini for your agents.',
      body: [
        h('div', { class: 'row' }, Object.keys(MINI_LOOKS).map((id) => mini(id, 'wave', 2.5))),
        h('div', { class: 'floor' }),
        h('p', {}, 'ai usage reads how much of your plan you\'ve used, straight from the claude, antigravity, codex and cursor clis you already have.'),
        h('p', { class: 'muted' }, 'it checks every few minutes. nothing leaves your mac.'),
      ],
    }),
    claude: () => ({
      title: 'checking claude code',
      sub: 'ai usage reads your claude plan from it.',
      body: [hero(tool('claude').tone === 'ok' ? 'wave' : tool('claude').tone ? 'idle' : 'think', 'claude'), card(tool('claude'), true)],
    }),
    providers: () => ({
      title: 'other tools',
      sub: "anything that isn't installed is skipped. you can add it later.",
      body: ['antigravity', 'codex', 'cursor'].map((id) => card(tool(id))),
    }),
    appearance: () => ({
      title: 'where should it live?',
      sub: 'you can change this any time in settings.',
      body: [h('div', { class: 'where' },
        [['tray', 'menu bar', 'a badge that opens a panel.', 'badge'], ['notch', 'notch', 'a pill that fans out every tool.', 'pill']].map(([id, t, d, mark]) =>
          h('button', { class: S.displayMode === id ? 'on' : '', onclick: () => { S.displayMode = id; act('mode', id); render(true); } },
            h('div', { class: 'screen' }, h('i', { class: mark })), h('div', { class: 't' }, t), h('div', { class: 'd' }, d))))],
    }),
    login: () => ({
      title: 'start automatically',
      sub: "usage only helps if it's already there when you look.",
      body: [hero(S.launchAtLogin ? 'stretch' : 'sleep'),
        h('button', { class: 'set', onclick: () => { S.launchAtLogin = !S.launchAtLogin; act('startAtLogin', S.launchAtLogin); render(true); } },
          'open ai usage when i log in', h('span', { class: 'switch' + (S.launchAtLogin ? ' on' : '') }))],
    }),
    done: () => ({
      title: "you're all set",
      sub: S.displayMode === 'notch' ? 'look just under the notch. click the pill to fan out every tool.'
        : 'look for the badge in your menu bar. click it any time to see your usage.',
      body: [hero('cheer'),
        h('p', { class: 'muted' }, 'your mini sits in the corner and follows your sessions. right-click it for its panel.')],
    }),
  };

  function render(force) {
    const all = steps();
    step = Math.max(0, Math.min(step, all.length - 1));
    const name = all[step];
    // only what this step shows, so a second's poll doesn't restart the critters for nothing
    const key = JSON.stringify([name, name === 'claude' || name === 'providers' ? S.providers : [S.provider, S.displayMode, S.launchAtLogin, S.notch]]);
    if (key === drawn && !force) return;
    drawn = key;
    const v = STEPS[name]();
    const card = $('card');
    card.style.setProperty('--accent', (MINI_LOOKS[S.provider] || MINI_LOOKS.claude).accent);
    $('title').textContent = v.title;
    $('sub').textContent = v.sub;
    $('body').replaceChildren(...v.body.flat());
    const last = step === all.length - 1;
    $('foot').replaceChildren(...[
      h('div', { class: 'steps' }, all.map((_, i) => h('i', { class: i === step ? 'on' : '' }))),
      step > 0 && h('button', { class: 'pxb', onclick: () => { step--; render(true); } }, 'back'),
      (name === 'claude' || name === 'providers') && h('button', { class: 'pxb', onclick: () => act('recheck') }, 'recheck'),
      last ? h('button', { class: 'pxb primary', onclick: () => act('finish') }, 'finish')
        : h('button', { class: 'pxb primary', onclick: () => { step++; render(true); } }, step === 0 ? 'get started' : 'continue'),
    ].filter(Boolean));
  }

  addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { const b = $('foot').querySelector('.primary'); if (b) b.click(); }
  });

  window.page = { update(state) { S = state; render(); } };

  if (native) post({ type: 'ready' });
  else {
    // opened in a browser: sample data
    step = Number(new URLSearchParams(location.search).get('step')) || 0;
    page.update({
      notch: true, displayMode: 'tray', launchAtLogin: true, provider: 'claude',
      providers: [
        { id: 'claude', name: 'Claude', line: 'signed in. 21% used.', tone: 'ok' },
        { id: 'antigravity', name: 'Antigravity', line: 'not installed.', action: { title: 'install', name: 'install' } },
        { id: 'codex', name: 'Codex', line: 'found it. sign in to read your usage.', tone: 'warn', action: { title: 'log in', name: 'signin' } },
        { id: 'cursor', name: 'Cursor', line: 'signed in.', tone: 'ok' },
      ],
    });
  }
})();
