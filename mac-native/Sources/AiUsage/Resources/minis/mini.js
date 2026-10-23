/* One mini: a pixel critter standing in for one agent session. The app tells it what the session is doing
   (mini.update) and it picks a pose and a word. No personality on purpose: it reports status, it doesn't chat. */
(function () {
  'use strict';

  // Each provider's own critter (see SPECIES in pet.js). Claude is Mochi, Claude Code's mascot.
  const LOOKS = {
    claude: {},
    // Codex's pet: periwinkle, with light eyes on its dark visor.
    codex: { species: 'codex', palette: { b: '#7183F2', l: '#97A6FF', s: '#5262D2', d: '#3C49A8', p: '#B9C3FF', e: '#D9E4FF' } },
    // Gemini's gradient, blue at the top to rose at the bottom.
    antigravity: { species: 'sparkle', palette: { l: '#4E8FF0', b: '#8C78D6', s: '#C9698D', d: '#9A4C6C', p: '#F0B7C9' } },
    // Lit from above: pale top, Cursor purple on the left, shade on the right.
    cursor: { species: 'cube', palette: { l: '#D6CFFF', b: '#8B7CF6', s: '#5B4BC9', d: '#43379C', p: '#C9C0FD' } },
  };
  const NAMES = { claude: 'Claude', codex: 'Codex', cursor: 'Cursor', antigravity: 'Antigravity' };

  // Neutral versions of Mochi's poses: no blushing, cheering, hearts or confetti.
  Critter.addPose('miniIdle', { anim: 'slow' });
  Critter.addPose('miniThink', { look: [1, -1], acc: ['dots'], anim: 'slow' });
  Critter.addPose('miniParcel', { held: 'box', armL: 'hold', armR: 'hold', anim: 'slow' });
  Critter.addPose('miniDelegate', { acc: ['helpers'], anim: 'slow' });
  Critter.addPose('miniCompact', { anim: 'squish' });
  Critter.addPose('miniDone', { acc: ['check'], anim: 'slow' });
  Critter.addPose('miniAsk', { eyes: 'wide', acc: ['alert'], anim: 'slow' });
  Critter.addPose('miniFail', { eyes: 'x', anim: 'slow' });
  Critter.addPose('miniPace', { anim: 'walk' });

  // Which pose each state gets, per animation level.
  const POSES = {
    // Mochi's original, expressive set.
    full: {
      idle: 'idle', thinking: 'think', reading: 'read', editing: 'type', searching: 'detective', browsing: 'binoculars',
      running: 'terminal', testing: 'clipboard', committing: 'ship', delegating: 'conduct', planning: 'clipboard',
      compacting: 'squish', tool: 'terminal', done: 'cheer', needsInput: 'needsYou', failed: 'oops',
    },
    // Props that say what it's doing, nothing more.
    subtle: {
      idle: 'miniIdle', thinking: 'miniThink', reading: 'read', editing: 'type', searching: 'binoculars', browsing: 'binoculars',
      running: 'terminal', testing: 'terminal', committing: 'miniParcel', delegating: 'miniDelegate', planning: 'clipboard',
      compacting: 'miniCompact', tool: 'terminal', done: 'miniDone', needsInput: 'miniAsk', failed: 'miniFail',
    },
    // A status light with eyes: working, done, needs you, failed.
    minimal: { idle: 'miniIdle', done: 'miniDone', needsInput: 'miniAsk', failed: 'miniFail' },
  };

  const WORDS = {
    thinking: 'Thinking', reading: 'Reading', editing: 'Editing', searching: 'Searching', browsing: 'Browsing',
    running: 'Running', testing: 'Testing', committing: 'Committing', delegating: 'Delegating', planning: 'Planning',
    compacting: 'Compacting', tool: 'Using a tool', done: 'Done', needsInput: 'Needs input', failed: 'Failed',
  };
  const ALERTS = ['done', 'needsInput', 'failed'];

  const post = (msg) => { try { window.webkit.messageHandlers.mini.postMessage(msg); } catch (e) { /* preview page */ } };

  const petEl = document.getElementById('pet');
  const bubble = document.getElementById('bubble');
  const bubbleText = bubble.firstElementChild;
  let critter = null;
  let s = { provider: 'claude', state: 'idle', detail: '', project: '', speech: 'status', animation: 'subtle', motion: 'still', scale: 2 };
  let built = '';
  let hovering = false;

  function build() {
    const key = [s.provider, s.animation, s.scale].join('|');
    if (key === built) return;
    built = key;
    if (critter) critter.destroy();
    const look = LOOKS[s.provider] || {};
    critter = new Critter(petEl, { scale: s.scale, palette: look.palette, species: look.species, particles: s.animation === 'full' });
    document.documentElement.style.setProperty('--bubble-bottom', 25 * s.scale + 4 + 'px');
  }

  const working = () => s.state !== 'idle' && !ALERTS.includes(s.state);

  function poseFor() {
    const set = POSES[s.animation] || POSES.subtle;
    if (s.motion === 'pace' && working() && pacing) return 'miniPace';
    return set[s.state] || (working() ? 'miniThink' : 'miniIdle');
  }

  function text() {
    const who = NAMES[s.provider] || s.provider;
    if (hovering) {
      const where = s.project ? who + ' · ' + s.project : who;
      const what = WORDS[s.state];
      return what ? where + ' — ' + what : where;
    }
    const word = WORDS[s.state];
    if (!word) return '';
    if (s.speech === 'alertsOnly' && !ALERTS.includes(s.state)) return '';
    if (s.speech === 'detailed') {
      if (ALERTS.includes(s.state)) return s.project ? word + ' · ' + s.project : who + ' ' + word.toLowerCase();
      return s.detail ? word + ' ' + s.detail : word;
    }
    return word;
  }

  let lastText = null;
  function render() {
    build();
    critter.pose(poseFor());
    const t = text();
    if (t !== lastText) {
      lastText = t;
      bubbleText.textContent = t;
      bubble.hidden = !t;
      bubble.classList.toggle('alert', ALERTS.includes(s.state) && s.state !== 'done');
    }
    requestAnimationFrame(sendHot);
  }

  // The areas that take clicks; everything else in the window lets them through.
  let lastHot = '';
  function sendHot() {
    if (!critter) return;
    const rects = [critter.hitBox()];
    if (!bubble.hidden) { const r = bubble.getBoundingClientRect(); rects.push([r.left, r.top, r.width, r.height]); }
    const out = rects.map((r) => r.map(Math.round));
    const k = JSON.stringify(out);
    if (k !== lastHot) { lastHot = k; post({ type: 'hot', rects: out }); }
  }

  // Pacing: a few seconds of walking in place every so often while the session works.
  let pacing = false;
  setInterval(() => {
    if (s.motion !== 'pace' || !working()) { if (pacing) { pacing = false; render(); } return; }
    pacing = !pacing;
    render();
  }, 5000);

  // Drag to move, click to acknowledge/focus, right-click for the menu.
  let down = null;
  document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    down = { x: e.screenX, y: e.screenY, moved: false };
  });
  document.addEventListener('mousemove', (e) => {
    if (!down) return;
    const dx = e.screenX - down.x, dy = e.screenY - down.y;
    if (!down.moved && Math.hypot(dx, dy) < 3) return;
    if (!down.moved) post({ type: 'dragStart' });
    down.moved = true;
    post({ type: 'drag', dx, dy });
  });
  document.addEventListener('mouseup', () => {
    if (!down) return;
    post({ type: down.moved ? 'dragEnd' : 'click' });
    down = null;
  });
  document.addEventListener('contextmenu', (e) => { e.preventDefault(); post({ type: 'menu' }); });

  window.mini = {
    update(next) { s = Object.assign({}, s, next); render(); },
    hover(on) { if (on !== hovering) { hovering = on; render(); } },
  };

  render();
  post({ type: 'ready' });
})();
