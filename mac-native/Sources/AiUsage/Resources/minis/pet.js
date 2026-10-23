/* Mochi, the pixel critter. Draws every frame on a tiny canvas (46×34 "real" pixels),
   scaled up crisp. Shared by the desktop app and the preview pages. No dependencies. */
(function (root) {
  'use strict';

  // ---------- palette: one letter per color ----------
  const PAL = {
    b: '#E5714B', l: '#EE8862', s: '#CC5F3C', d: '#A84B2E', e: '#1F1A1C', p: '#F6A08C',   // critter
    w: '#FFFFFF', q: '#D7D7DE', g: '#A2A2AE', G: '#6E6E7A', k: '#26252B', K: '#141317',    // neutrals
    C: '#F6EFE4', D: '#D8C9B4', o: '#5B3A27', t: '#D6BFA2',                                // mug + steam
    W: '#F2F2F2', v: '#7FE3A2',                                                            // screen text
    A: '#E3F5FF', a: '#9CCDEA', u: '#4FAEE3', U: '#2E87C3', r: '#FF6F8E',                  // water
    R: '#EF5350', c: '#C23B39', n: '#8A5A3B', N: '#6B4329', P: '#FBF3E2', m: '#D7C7AC',                  // ball, book
    L: '#6CC36F', M: '#3F9A4C', T: '#C96C43', X: '#A3532F', S: '#5B3B29',                  // plant
    B: '#69A7E6', V: '#4A80C0',                                                            // watering can
    Y: '#2E3B8F', y: '#1F2766', j: '#5A78E0',                                              // navy: wizard, headphones, nightcap
    z: '#FFD54A', Z: '#F2A93B', O: '#FFF6C8',                                              // gold, glow
    x: '#FF4F6E', i: '#FF5C7C', h: '#7A5233', H: '#54381F', F: '#F2C27A', f: '#D99A4E',    // misc
    E: '#D3C7A3', Q: '#A99B76', J: '#1F4D3E', I: '#C8E86B',                                // tv
  };

  const sp = (rows) => ({ rows, w: rows[0].length, h: rows.length });
  const flipRows = (rows) => rows.map((r) => [...r].reverse().join(''));

  // ---------- canvas layout ----------
  const CW = 46, CH = 34;           // canvas in critter pixels
  const BX = 16, BY = 20;           // body top-left at rest
  const BW = 14, BH = 10;           // body size at rest
  const LEGS = [2, 4, 9, 11];       // leg columns under the body

  function bodySprite(w, h) {
    const rows = [];
    for (let y = 0; y < h; y++) {
      let r = '';
      for (let x = 0; x < w; x++) {
        if ((y === 0 || y === h - 1) && (x === 0 || x === w - 1)) r += '.';
        else r += y === 0 ? 'l' : y === h - 1 ? 's' : x === w - 1 ? 's' : 'b';
      }
      rows.push(r);
    }
    return sp(rows);
  }
  const BODIES = {
    base: { s: bodySprite(14, 10), dx: 0, dy: 0 },
    squash: { s: bodySprite(16, 9), dx: -1, dy: 1 },
    tall: { s: bodySprite(12, 11), dx: 1, dy: -1 },
    flat: { s: bodySprite(16, 8), dx: -1, dy: 2 },
    // squished by scrolling
    taller: { s: bodySprite(10, 13), dx: 2, dy: -3 },
    pancake: { s: bodySprite(18, 6), dx: -2, dy: 4 },
    // turning sideways, mid-spin
    thin: { s: bodySprite(8, 10), dx: 3, dy: 0 },
    edge: { s: bodySprite(4, 10), dx: 5, dy: 0 },
  };

  // eyes: [sprite rows, x offset from body center, y offset from body top]; right eye mirrors the left
  const EYES = {
    open:    [['e', 'e'], -3, 3],
    wide:    [['we', 'ee', 'ee'], -4, 2],
    dash:    [['ee'], -4, 4],
    sleep:   [['ee'], -4, 5],
    happy:   [['.e.', 'e.e'], -4, 3],
    squeeze: [['e.', '.e', 'e.'], -4, 2],
    star:    [['.z.', 'zzz', '.z.'], -4, 2],
    heart:   [['i.i', 'iii', '.i.'], -4, 2],
    blink:   [['e'], -3, 4],
    x:       [['e.e', '.e.', 'e.e'], -4, 2],
  };
  const MOUTHS = { none: null, o: [['ee'], -1, 6], yawn: [['ee', 'ee'], -1, 6], smile: [['e..e', '.ee.'], -2, 6], line: [['eeee'], -2, 6] };
  const BROWS = { determined: [['e.', '.e'], -5, 1], worried: [['.e', 'e.'], -5, 1] };

  // arms, drawn for the left side (x relative to the body's left edge, y relative to the shoulder row)
  const ARMS = {
    rest:   [['bb', 'b.'], -2, 0],
    down:   [['b', 'b'], -1, 0],
    up:     [['b.', 'bb'], -2, -2],
    out:    [['bbb'], -3, 0],
    hold:   [['bbb'], -3, 0],
    holdUp: [['b..', '.bb'], -3, -1],
    tap:    [['bb'], -2, 1],
    tap2:   [['bb'], -2, 2],
    none:   null,
  };
  // where an arm's hand ends up (used to place held items)
  const HANDS = { hold: [-4, 0], holdUp: [-4, -1], out: [-4, 0], rest: [-3, 0], up: [-3, -2] };

  // ---------- props ----------
  const ITEMS = {
    mug: { s: sp(['..DDDDD', '..DoooD', 'DDCCCCD', 'D.CCCCD', 'DDCCCCD', '..DCCCD', '...DDD.']), grab: [6, 3], steam: true },
    can: { s: sp(['.qgggq.', 'wwwwwwq', 'wgwgwgq', 'wgwgwgq', 'wgwgwgq', 'wwgwgwq', 'wwwwwwq', 'wGGGGwq', 'wwwwwwq', '.qgggq.']), grab: [6, 4] },
    glass: { s: sp(['..rr.', '...r.', 'a..ra', 'aAAAa', 'auuua', 'auUua', 'aUuua', '.aaa.']), grab: [4, 4] },
    water: { s: sp(['......VVV.', 'B....V...V', '.B.BBBBBBV', '..BBBBBBB.', '...BBBBBB.', '...VVVVVV.']), grab: [9, 2] },
    waterTilt: { s: sp(['......VVV.', '.....V...V', '...BBBBBBV', 'BBBBBBBBB.', '...BBBBBB.', '...VVVVVV.']), grab: [9, 2] },
    pan: { s: sp(['....K.....K', 'GGGGKKKKKKK', '.....KKKKK.']), grab: [0, 1] },
    magnifier: { s: sp(['.ggg.', 'gAAwg', 'gAAAg', 'gAAAg', '.ggg.', 'h....', 'h....']), grab: [0, 6] },
    popcorn: { s: sp(['.OwOzO.', 'OzOwOwO', 'RwRwRwR', 'RwRwRwR', '.RwRwR.', '.RwRwR.']), grab: [6, 3] },
    duck: { s: sp(['..zz...', '.zezz..', 'ZZzzz..', '..zzzzz', '.zzzzzz', '..zzzz.']), grab: [6, 4] },
    // Claude Code's work: a checklist (tests, the plan) and a parcel (a commit going out)
    clip: { s: sp(['..gg..', 'nPggPn', 'nPPPPn', 'nPMMPn', 'nPPPPn', 'nPMMPn', 'nPPPPn', 'nnnnnn']), grab: [5, 4] },
    box: { s: sp(['ffffffff', 'fFFzzFFf', 'fFFzzFFf', 'fFFFFFFf', 'fFFFFFFf', 'ffffffff']), grab: [7, 3] },
  };
  const LAPTOP = sp(['...KKKKKKK', '..KkkkkkkK', '..KkkkkkK.', '.KkkkkkkK.', '.KKKKKKKK.', 'gggggggggg', 'KKKKKKKKKK']);
  const BOOK = sp(['.PPPPP.PPPPP', 'NnnnnnNnnnnN', 'NnzznnNnnzzN', 'NnnnnnNnnnnN', 'NnnnnnNnnnnN', 'NNNNNNNNNNNN']);
  const NAPBOOK = sp([
    '.....PPP..PPP.....',
    '...PPPPPPmPPPPPP..',
    '.PPPPPPPPmPPPPPPP.',
    'PPPPPPPPmmPPPPPPPP',
    'nnnnnnnnNNnnnnnnnn',
  ]);
  const PLANT = sp(['.L...L.', 'LLM.MLL', '..MLM..', 'TTTTTTT', '.TTTTT.', '.XTTTX.', '..XXX..']);
  const BALL = sp(['.RR.', 'RwRR', 'RRRR', '.RR.']);
  // the fetch ball and the treat (main.swift draws the same two when they're out in the world)
  const TOYS = {
    ball: sp(['.RRR.', 'RwRRR', 'RRRRR', 'RRRRc', '.ccc.']),
    treat: sp(['.FFFF.', 'FFoFFF', 'FFFFoF', 'FoFFFF', '.ffff.']),
  };
  ITEMS.treat = { s: TOYS.treat, grab: [5, 2] };
  const FOOD = [sp(['fFFf']), sp(['Ff', 'fF']), sp(['F', 'f'])];
  // little signs that float over Mochi's head
  const MUTE = sp(['..G....', '.GG.x.x', 'GGG..x.', '.GG.x.x', '..G....']);
  const BATTERY = sp(['GGGGGGG.', 'G.....GG', 'G.....GG', 'GGGGGGG.']);
  const BOLT = sp(['..z', '.z.', 'zzz', '.z.', 'z..']);
  const ALERT = sp(['xx', 'xx', 'xx', '..', 'xx']);
  // a tiny helper Mochi (Claude's sub-agents)
  const MINI = sp(['.lll.', 'bebeb', 'bbbbs', '.s.s.']);

  // hats & costumes: [sprite, x offset from body left, rows overlapping the body top]
  const HATS = {
    chef: [sp(['..qww.wwq...', '.wwwwwwwwwq.', 'wwwwwwwwwwwq', '.wwwwwwwwwq.', '.wwwwwwwwww.', '.qqqqqqqqqq.']), 1, 1],
    detective: [sp([
      '......hh........',
      '....hhhhhh......',
      '...hHhHhHhh.....',
      '..hhhhhhhhhhh...',
      'HHhhhhhhhhhhhHHH',
      '..HHHHHHHHHHHH..',
    ]), -1, 1],
    wizard: [sp([
      '..........YY....',
      '.........YYy....',
      '........YYYy....',
      '.......YYYYy....',
      '......YYzYYy....',
      '.....YYYYYYYy...',
      '....YYYYYYYYYy..',
      'yyyyyyyyyyyyyyyy',
    ]), -1, 1],
    nightcap: [sp([
      '.......jjj......',
      '.....jjjjjjj....',
      '...jjjjjjjjjjj.w',
      '..jjjjjjjjjjjjww',
      'wwwwwwwwwwwwwwww',
    ]), -1, 1],
  };
  const BEARD = sp(['wwwwwwwwww', '.wwwqwwww.', '.wwwwwqww.', '..wwwqww..', '..wwwwww..', '...wqww...', '....ww....']);
  const TV = sp([
    '.EEEEEEEEEEEEEE.',
    'EEJJJJJJJJJJJJEQ',
    'EEJJJJJJJJJJJJEQ',
    'EEJJJJJJJJJJJJEQ',
    'EEJJJJJJJJJJJJEQ',
    'EEJJJJJJJJJJJJEQ',
    'EEJJJJJJJJJJJJEQ',
    'EEJJJJJJJJJJJJEQ',
    'EEEEEEEEEEEEEEEQ',
    '.QQQQQQQQQQQQQQ.',
  ]);

  // ---------- particles ----------
  const FX = {
    z: { sprites: [sp(['jjjj', '..j.', '.j..', 'jjjj']), sp(['jjj', '..j', 'j..', 'jjj'])], life: 30 },
    heart: { sprites: [sp(['.i.i.', 'iiiii', '.iii.', '..i..'])], life: 18 },
    note: { sprites: [sp(['..zz', '..z.', '..z.', 'zzz.', 'zz..']), sp(['z'])], life: 26 },
    sparkle: { sprites: [sp(['.z.', 'zwz', '.z.']), sp(['..z..', '..z..', 'zzwzz', '..z..', '..z..'])], life: 9 },
    drop: { sprites: [sp(['.u', 'uu', 'uu'])], life: 14 },
    bang: { sprites: [sp(['x', 'x', 'x', '.', 'x'])], life: 12 },
    bit: { sprites: [sp(['z']), sp(['Z'])], life: 10 },
    crumb: { sprites: [sp(['F']), sp(['f'])], life: 10 },
    dust: { sprites: [sp(['.q.', 'qqq']), sp(['q'])], life: 7 },
    confetti: { sprites: null, life: 46 },
  };
  const CONFETTI = ['x', 'z', 'j', 'L', 'u', 'i', 'w'];

  // ---------- poses ----------
  const DEFAULT = { eyes: 'open', mouth: 'none', brows: '', armL: 'rest', armR: 'rest', held: null, heldR: null, front: null, hat: null,
    acc: [], legs: 'plain', body: 'base', anim: 'breathe', look: null, fx: null, blush: false, ground: null };
  const POSES = {
    idle:        {},
    content:     { eyes: 'happy', anim: 'bob', blush: true },
    happy:       { eyes: 'happy', anim: 'hop', blush: true },
    tired:       { eyes: 'dash', armL: 'down', armR: 'down', anim: 'slow', body: 'squash' },
    yawn:        { eyes: 'dash', armL: 'down', armR: 'down', anim: 'yawn' },
    coffee:      { held: 'mug', armL: 'hold', front: 'laptop', armR: 'tap', look: [1, 0], anim: 'type' },
    sip:         { held: 'mug', armL: 'hold', anim: 'sip', blush: true },
    offerCoffee: { eyes: 'wide', held: 'mug', armL: 'hold', anim: 'offer' },
    energy:      { eyes: 'wide', held: 'can', armL: 'hold', anim: 'offer' },
    sipEnergy:   { held: 'can', armL: 'hold', anim: 'sip', fx: ['sparkle', 14] },
    water:       { eyes: 'wide', held: 'glass', armL: 'hold', anim: 'offer' },
    sipWater:    { held: 'glass', armL: 'hold', anim: 'sip', blush: true },
    walkAsk:     { eyes: 'wide', legs: 'sneakers', acc: ['headband'], anim: 'wave' },
    walk:        { eyes: 'happy', legs: 'sneakers', acc: ['headband'], anim: 'walk' },
    stretch:     { eyes: 'happy', anim: 'stretch' },
    lookfar:     { armL: 'up', look: [-1, -1] },
    cheer:       { eyes: 'happy', anim: 'cheer', acc: ['poms'], blush: true },
    wave:        { eyes: 'happy', anim: 'wave' },
    type:        { front: 'laptop', armR: 'tap', look: [1, 0], anim: 'type' },
    focus:       { eyes: 'dash', front: 'laptop', armR: 'tap', acc: ['headphones'], anim: 'type nod', fx: ['note', 16] },
    wizard:      { hat: 'wizard', acc: ['beard'], heldR: 'staff', armR: 'out', anim: 'wizard', fx: ['sparkle', 10] },
    detective:   { hat: 'detective', heldR: 'magnifier', armR: 'holdUp', anim: 'detective' },
    chef:        { eyes: 'happy', hat: 'chef', heldR: 'pan', armR: 'hold', anim: 'chef', blush: true },
    read:        { front: 'book', armL: 'none', armR: 'none', look: [0, 1], anim: 'read' },
    juggle:      { anim: 'juggle' },
    plant:       { eyes: 'happy', held: 'water', armL: 'hold', ground: 'plant', look: [-1, 1], anim: 'pour' },
    nap:         { eyes: 'sleep', body: 'flat', acc: ['napbook'], armL: 'down', armR: 'down', anim: 'sleep', fx: ['z', 20] },
    sleep:       { eyes: 'sleep', body: 'squash', armL: 'down', armR: 'down', anim: 'sleep', fx: ['z', 20] },
    nightSleep:  { eyes: 'sleep', body: 'squash', hat: 'nightcap', armL: 'down', armR: 'down', anim: 'sleep', fx: ['z', 20] },
    night:       { eyes: 'dash', hat: 'nightcap', anim: 'slow' },
    love:        { eyes: 'heart', anim: 'wiggle', fx: ['heart', 9], blush: true },
    poke:        { eyes: 'squeeze', anim: 'hop1', blush: true },
    party:       { eyes: 'star', armL: 'up', armR: 'up', anim: 'party', fx: ['confetti', 5] },
    proud:       { eyes: 'happy', look: [0, -1], anim: 'bob', fx: ['sparkle', 12], blush: true },
    sweaty:      { eyes: 'dash', acc: ['sweat'], armL: 'down', armR: 'down', anim: 'slow' },
    tv:          { acc: ['tv'], anim: 'tv' },
    surprised:   { eyes: 'wide', mouth: 'o', anim: 'jump' },
    dangle:      { eyes: 'wide', mouth: 'o', armL: 'up', armR: 'up', anim: 'dangle' },
    // getting around the screen (the app moves the window; these just look the part)
    stroll:      { anim: 'stroll' },
    crouch:      { body: 'squash', armL: 'down', armR: 'down', anim: 'none' },
    jump:        { eyes: 'happy', armL: 'up', armR: 'up', body: 'tall', anim: 'air' },
    fall:        { eyes: 'wide', mouth: 'o', armL: 'up', armR: 'up', anim: 'air' },
    land:        { eyes: 'squeeze', body: 'flat', armL: 'out', armR: 'out', anim: 'none' },
    dizzy:       { eyes: 'x', anim: 'dizzy' },
    // what's going on with your Mac
    shh:         { mouth: 'line', acc: ['mute'], anim: 'slow' },
    popcorn:     { held: 'popcorn', armL: 'hold', look: [0, -1], anim: 'munch' },
    jam:         { eyes: 'happy', acc: ['headphones'], anim: 'nod', fx: ['note', 14] },
    duck:        { held: 'duck', armL: 'hold', look: [-1, 0], anim: 'squeak' },
    lowbatt:     { eyes: 'dash', body: 'squash', armL: 'down', armR: 'down', acc: ['lowbatt'], anim: 'slow' },
    zap:         { eyes: 'star', acc: ['charging'], anim: 'hop', fx: ['sparkle', 8] },
    shades:      { acc: ['shades'], look: [0, 0], anim: 'bob' },
    // playing with you
    pet:         { eyes: 'happy', body: 'squash', armL: 'down', armR: 'down', anim: 'purr', fx: ['heart', 12], blush: true },
    eager:       { eyes: 'wide', anim: 'eager' },
    run:         { brows: 'determined', anim: 'run' },
    eat:         { eyes: 'happy', held: 'treat', armL: 'hold', anim: 'eat', blush: true },
    sniff:       { eyes: 'wide', mouth: 'o', anim: 'sniff' },
    chomp:       { eyes: 'happy', anim: 'chomp', fx: ['crumb', 4] },
    spin:        { eyes: 'happy', anim: 'spin', blush: true },
    shaken:      { eyes: 'x', mouth: 'o', armL: 'up', armR: 'up', anim: 'dangle' },
    splat:       { eyes: 'x', body: 'flat', armL: 'out', armR: 'out', anim: 'none' },
    // following along with Claude Code
    think:       { look: [1, -1], acc: ['dots'], anim: 'slow' },
    needsYou:    { eyes: 'wide', acc: ['alert'], anim: 'wave' },
    terminal:    { front: 'terminal', armR: 'tap', look: [1, 0], anim: 'type' },
    clipboard:   { held: 'clip', armL: 'hold', armR: 'tap', look: [-1, 1], anim: 'tick' },
    binoculars:  { acc: ['binoculars'], armL: 'holdUp', armR: 'holdUp', anim: 'scan' },
    ship:        { eyes: 'happy', held: 'box', armL: 'hold', armR: 'hold', anim: 'offer' },
    conduct:     { eyes: 'happy', acc: ['helpers'], anim: 'conduct', fx: ['note', 12] },
    squish:      { eyes: 'squeeze', anim: 'squish' },
    oops:        { eyes: 'x', mouth: 'o', acc: ['sweat'], armL: 'up', armR: 'up', anim: 'slow', fx: ['bang', 30] },
  };

  // ---------- animation: each one adjusts the frame state ----------
  const HOP = [0, -2, -4, -5, -5, -4, -2, 0, 0];
  const hop = (st, k) => { st.oy = HOP[k] || 0; if (k === 8) st.body = 'squash'; else if (k === 1) st.body = 'tall'; };
  const tri = (f, period) => { const x = (f % period) / period; return x < 0.5 ? x * 4 - 1 : 3 - x * 4; };
  const ANIMS = {
    breathe(st, f) { st.bob = f % 30 >= 15 ? 1 : 0; },
    slow(st, f) { st.bob = f % 48 >= 24 ? 1 : 0; },
    bob(st, f) { st.bob = f % 16 >= 8 ? 1 : 0; },
    hop(st, f) { hop(st, f % 9); },
    hop1(st, f, pf) { if (pf < 9) hop(st, pf); },
    jump(st, f, pf) { if (pf < 9) { hop(st, pf); st.oy *= 1.6; st.oy = Math.round(st.oy); } },
    cheer(st, f) { hop(st, f % 9); const a = (f >> 1) % 2; st.armL = a ? 'up' : 'out'; st.armR = a ? 'out' : 'up'; },
    party(st, f) { hop(st, f % 9); const a = (f >> 1) % 2; st.armL = st.armR = a ? 'up' : 'out'; },
    wave(st, f) { st.armR = (f >> 1) % 2 ? 'up' : 'out'; st.bob = f % 30 >= 15 ? 1 : 0; },
    walk(st, f) {
      const step = (f >> 1) % 4;
      st.legLift = step === 0 ? [1, 0, 1, 0] : step === 2 ? [0, 1, 0, 1] : [0, 0, 0, 0];
      st.bob = step % 2;
      const p = tri(f, 140);
      st.ox = Math.round(p * 7);
      st.lx = tri(f + 1, 140) > p ? 1 : -1;
      st.armL = step < 2 ? 'rest' : 'out';
      st.armR = step < 2 ? 'out' : 'rest';
    },
    type(st, f) { st.armR = f % 2 ? 'tap' : 'tap2'; st.bob = f % 30 >= 15 ? 1 : 0; st.typing = true; },
    nod(st, f) { st.bob = f % 6 < 3 ? 1 : 0; },
    sip(st, f) {
      const c = f % 40;
      if (c >= 12 && c < 30) { st.armL = 'holdUp'; st.eyes = 'happy'; }
      st.bob = f % 30 >= 15 ? 1 : 0;
    },
    offer(st, f) { st.heldDy = f % 16 < 8 ? 0 : -1; },
    stretch(st, f) {
      const c = f % 50;
      if (c >= 8 && c < 38) { st.armL = st.armR = 'up'; st.body = 'tall'; } else st.eyes = 'open';
    },
    yawn(st, f) {
      const c = f % 44;
      if (c >= 8 && c < 30) { st.mouth = c < 12 || c > 26 ? 'o' : 'yawn'; st.eyes = 'sleep'; st.armL = st.armR = 'up'; st.body = 'tall'; }
      else st.bob = f % 48 >= 24 ? 1 : 0;
    },
    juggle(st, f) {
      const c = f % 24, k = c % 12, t = k / 11;
      const leftToRight = c < 12;
      const x0 = BX - 4, x1 = BX + BW;
      st.ball = [Math.round(leftToRight ? x0 + (x1 - x0) * t : x1 - (x1 - x0) * t), Math.round(BY + 3 - 15 * 4 * t * (1 - t))];
      st.lx = st.ball[0] < BX + 5 ? -1 : st.ball[0] > BX + 9 ? 1 : 0;
      st.ly = t > 0.2 && t < 0.8 ? -1 : 0;
      if (k === 0) { if (leftToRight) st.armL = 'up'; else st.armR = 'up'; }
      st.eyes = k < 2 ? 'happy' : 'open';
    },
    pour(st, f) { const c = f % 36; st.tilt = c >= 8 && c < 30; st.grow = c >= 24 && c < 34; },
    read(st, f) {
      st.lx = [-1, 0, 1, 1, 0, -1][((f / 7) | 0) % 6];
      st.flip = f % 60 >= 56 ? f % 60 - 55 : 0;
      st.bob = f % 30 >= 15 ? 1 : 0;
    },
    sleep(st, f) { st.bob = f % 40 >= 20 ? 1 : 0; },
    wiggle(st, f) { st.ox = [0, -1, 0, 1][(f >> 1) % 4]; },
    dangle(st, f) { st.ox = [0, -1, 0, 1][(f >> 1) % 4]; st.oy = -2; st.legLift = f % 4 < 2 ? [1, 0, 1, 0] : [0, 1, 0, 1]; st.shadow = 0.5; },
    wizard(st, f) { st.bob = f % 30 >= 15 ? 1 : 0; st.glow = f % 12 < 6 ? 1 : 0; if (f % 50 > 44) st.eyes = 'happy'; },
    detective(st, f) {
      const c = f % 40;
      st.lx = c < 12 ? -1 : c < 24 ? 1 : 0;
      st.heldRDx = c < 12 ? -1 : 0;
      st.bob = f % 30 >= 15 ? 1 : 0;
    },
    chef(st, f) {
      const c = f % 18;
      st.foodY = c < 12 ? Math.round(-10 * Math.sin((c / 12) * Math.PI)) : 0;
      st.foodSpin = c < 12 ? ((c / 2) | 0) % 3 : 0;
      st.armR = c === 0 || c === 1 ? 'holdUp' : 'hold';
      st.heldRDy = c === 0 || c === 1 ? -1 : 0;
      st.sizzle = c >= 12;
    },
    tv(st, f) { st.bob = f % 30 >= 15 ? 1 : 0; st.tvFace = f % 50 > 46 ? 'blink' : f % 120 > 100 ? 'sad' : 'smile'; },
    stroll(st, f, pf, v) {
      const step = (f >> 1) % 4;
      st.legLift = step === 0 ? [1, 0, 1, 0] : step === 2 ? [0, 1, 0, 1] : [0, 0, 0, 0];
      st.bob = step % 2;
      st.lx = v.facing;
      st.armL = step < 2 ? 'rest' : 'out';
      st.armR = step < 2 ? 'out' : 'rest';
    },
    air(st, f, pf, v) { st.legLift = f % 2 ? [1, 0, 1, 0] : [0, 1, 0, 1]; st.shadow = 0; st.lx = v.facing; },
    none() {},
    dizzy(st, f) { st.ox = [0, -1, 0, 1][(f >> 1) % 4]; st.orbit = f; },
    munch(st, f) {
      const c = f % 30;
      if (c >= 10 && c < 20) { st.armL = 'holdUp'; st.mouth = c % 4 < 2 ? 'o' : 'none'; st.eyes = 'happy'; }
      st.bob = f % 30 >= 15 ? 1 : 0;
    },
    squeak(st, f, pf, v) {
      const c = f % 36;
      st.heldDy = c < 3 ? 1 : 0;
      if (c === 0 && pf > 0) v.burst('note', 1);
      st.bob = f % 30 >= 15 ? 1 : 0;
    },
    purr(st, f) { st.ox = [0, 0, 1, 1, 0, 0, -1, -1][(f >> 1) % 8]; },
    // bouncing on its toes, waiting for you to throw
    eager(st, f) {
      const c = f % 20;
      if (c < 9) hop(st, c); else st.bob = f % 4 < 2 ? 1 : 0;
      st.armL = st.armR = (f >> 1) % 2 ? 'up' : 'out';
    },
    run(st, f, pf, v) {
      const step = f % 4;
      st.legLift = step === 0 ? [1, 0, 1, 0] : step === 2 ? [0, 1, 0, 1] : [0, 0, 0, 0];
      st.oy = step % 2 ? -1 : 0;
      st.lx = v.facing;
      st.armL = st.armR = 'out';
      if (f % 3 === 0) v.burst('dust', 1);
    },
    eat(st, f, pf, v) {
      const c = f % 16;
      if (c >= 4 && c < 12) { st.armL = 'holdUp'; st.mouth = c % 4 < 2 ? 'o' : 'none'; }
      if (c === 8) v.burst('crumb', 2);
      st.bob = f % 30 >= 15 ? 1 : 0;
    },
    sniff(st, f) { st.bob = f % 6 < 3 ? 1 : 0; st.ly = 1; },
    tick(st, f) { st.armR = f % 8 < 4 ? 'tap' : 'tap2'; st.bob = f % 30 >= 15 ? 1 : 0; },
    scan(st, f) { const c = f % 40; st.lx = c < 14 ? -1 : c < 28 ? 1 : 0; st.bob = f % 30 >= 15 ? 1 : 0; },
    conduct(st, f) { const a = (f >> 2) % 2; st.armL = a ? 'up' : 'out'; st.armR = a ? 'out' : 'up'; st.bob = a; st.helperHop = (f >> 1) % 4; },
    squish(st, f) { st.body = ['base', 'flat', 'pancake', 'pancake', 'flat', 'base', 'tall', 'base'][(f >> 1) % 8]; },
    chomp(st, f) { const c = f % 6; st.mouth = c < 3 ? 'o' : 'line'; st.body = c < 3 ? 'base' : 'squash'; },
    // a full turn in the air: front, side, back, side, front
    spin(st, f, pf, v) {
      const k = Math.min(pf, 12);
      st.oy = [0, -3, -6, -8, -9, -9, -9, -8, -6, -3, 0, 0, 0][k];
      st.body = ['squash', 'tall', 'thin', 'edge', 'thin', 'base', 'thin', 'edge', 'thin', 'tall', 'squash', 'base', 'base'][k];
      if (k >= 3 && k <= 7) st.eyes = 'none';                  // its back
      if (k === 2) st.lx = 1;
      if (k === 8) st.lx = -1;
      if (st.body === 'thin' || st.body === 'edge') st.armL = st.armR = 'none';
      st.legLift = k > 1 && k < 10 ? [1, 1, 1, 1] : [0, 0, 0, 0];
      st.shadow = k > 1 && k < 10 ? 0.6 : 1;
      if (pf === 10) v.burst('sparkle', 3);
    },
  };

  // ---------- one shared clock for every critter on the page ----------
  const all = new Set();
  let frame = 0;
  setInterval(() => {
    if (typeof document !== 'undefined' && document.hidden) return;
    frame++;
    all.forEach((v) => v._step(frame));
  }, 100);

  class Critter {
    constructor(el, opts = {}) {
      this.el = el;
      this.scale = opts.scale || 6;
      el.classList.add('critter');
      el.innerHTML = '';
      this.canvas = document.createElement('canvas');
      this.canvas.setAttribute('aria-hidden', 'true');
      el.appendChild(this.canvas);
      this.buf = document.createElement('canvas');
      this.buf.width = CW;
      this.buf.height = CH;
      this.b = this.buf.getContext('2d');
      this.parts = [];
      this.gaze = [0, 0];
      this.blinking = 0;
      this.fidgetK = null;
      this.facing = 1;
      this.current = null;
      this._size();
      this.pose(opts.pose || 'idle');
      if (opts.blink !== false) this._blinkLoop();
      all.add(this);
      this._step(frame);
    }

    _size() {
      const dpr = Math.max(1, Math.round((typeof devicePixelRatio === 'number' ? devicePixelRatio : 1) * 2) / 2);
      this.canvas.width = Math.round(CW * this.scale * dpr);
      this.canvas.height = Math.round(CH * this.scale * dpr);
      this.canvas.style.width = CW * this.scale + 'px';
      this.canvas.style.height = CH * this.scale + 'px';
      this.ctx = this.canvas.getContext('2d');
      this.ctx.imageSmoothingEnabled = false;
    }

    setScale(s) { this.scale = s; this._size(); this._step(frame, true); }

    pose(name) {
      if (this.current === name) return this;
      this.current = name;
      this.spec = Object.assign({}, DEFAULT, POSES[name] || {});
      this.poseFrame = frame;
      this.el.dataset.pose = name;
      this.fxEvery = this.spec.fx ? this.spec.fx[1] : 0;
      if (this.spec.fx) this.burst(this.spec.fx[0], this.spec.fx[0] === 'confetti' ? 18 : 1);
      this._step(frame, true);
      return this;
    }
    flash(name, ms = 700) {
      const back = this.current;
      clearTimeout(this._flashT);
      this.current = null;
      this.pose(name);
      this._flashT = setTimeout(() => { if (this.current === name) { this.current = null; this.pose(back); } }, ms);
    }
    look(x, y) { this.gaze = [x, y]; }
    lookAtPoint(px, py) {
      const r = this.canvas.getBoundingClientRect(), k = r.width / CW;
      const dx = px - (r.left + (BX + BW / 2) * k), dy = py - (r.top + (BY + 4) * k);
      const d = Math.hypot(dx, dy) || 1;
      const f = d < 4 * k ? 0 : 1;
      this.gaze = [Math.abs(dx / d) > 0.38 ? Math.sign(dx) * f : 0, Math.abs(dy / d) > 0.5 ? Math.sign(dy) * f : 0];
    }
    fidget(kind) { this.fidgetK = kind; this.fidgetFrame = frame; if (kind === 'hum') this.burst('note', 2); }
    // scrolled on: +1 squashes it a step flatter, -1 stretches it a step taller; it springs back on its own
    squish(dir) { this.squishLv = Math.max(-2, Math.min(2, (this.squishLv || 0) + dir)); this.squishAt = frame; this._step(frame, true); }
    // something in its mouth ('ball'), or null
    hold(toy) { this.carry = toy; this._step(frame, true); }
    blink() { if (this.spec && ['open', 'wide'].includes(this.spec.eyes)) { this.blinking = 2; } }
    _blinkLoop() {
      const next = () => { this._blinkT = setTimeout(() => { this.blink(); if (Math.random() < 0.18) setTimeout(() => this.blink(), 320); next(); }, 2200 + Math.random() * 4000); };
      next();
    }
    // the clickable area in viewport pixels
    hitBox() {
      const r = this.canvas.getBoundingClientRect(), k = r.width / CW;
      const wide = this.current === 'walk' ? 8 : 4;
      return [r.left + (BX - wide) * k, r.top + (BY - 6) * k, (BW + wide * 2) * k, (BH + 9) * k];
    }

    burst(kind, n = 1) { for (let i = 0; i < n; i++) this.parts.push(this._particle(kind)); }
    _particle(kind) {
      const R = (a, b) => a + Math.random() * (b - a);
      const P = { kind, age: 0, life: FX[kind].life, x: 0, y: 0, vx: 0, vy: 0, g: 0, spr: 0 };
      const cx = BX + BW / 2;
      switch (kind) {
        case 'z': Object.assign(P, { x: BX + BW - 2 + R(0, 2), y: BY - 3, vx: 0.22, vy: -0.32, spr: Math.random() < 0.5 ? 0 : 1 }); break;
        case 'heart': Object.assign(P, { x: cx + R(-7, 5), y: BY - 2, vx: R(-0.15, 0.15), vy: -0.45 }); break;
        case 'note': Object.assign(P, { x: cx + R(-2, 6), y: BY - 4, vx: R(0.05, 0.3), vy: -0.35, spr: Math.random() < 0.6 ? 0 : 1 }); break;
        case 'sparkle': Object.assign(P, { x: cx + R(-13, 11), y: BY + R(-9, 6) }); break;
        case 'drop': Object.assign(P, { x: cx + R(-4, 3), y: BY - 1, vx: R(-0.6, 0.6), vy: -0.9, g: 0.12 }); break;
        case 'bang': Object.assign(P, { x: BX + BW + 1, y: BY - 7 }); break;
        case 'bit': Object.assign(P, { x: BX + BW + 7 + R(-2, 3), y: BY + 2, vx: R(-0.3, 0.4), vy: R(-0.9, -0.5), g: 0.08, spr: Math.random() < 0.5 ? 0 : 1 }); break;
        case 'crumb': Object.assign(P, { x: cx + R(-4, 3), y: BY + 6, vx: R(-0.4, 0.4), vy: R(-0.6, -0.2), g: 0.12, spr: Math.random() < 0.5 ? 0 : 1 }); break;
        case 'dust': { const s = Math.random() < 0.5 ? -1 : 1; Object.assign(P, { x: cx + s * R(4, 8) - 1, y: BY + BH, vx: s * R(0.2, 0.6), vy: -0.12, spr: 0 }); break; }
        case 'confetti': Object.assign(P, { x: R(1, CW - 2), y: R(-6, 4), vx: R(-0.2, 0.2), vy: R(0.5, 0.9), color: CONFETTI[(Math.random() * CONFETTI.length) | 0] }); break;
      }
      return P;
    }

    // ---------- drawing ----------
    _px(x, y, c) {
      const col = PAL[c] || c;
      if (!col || x < 0 || y < 0 || x >= CW || y >= CH) return;
      this.b.fillStyle = col;
      this.b.fillRect(x | 0, y | 0, 1, 1);
    }
    _spr(s, x, y, flip = false, map) {
      const rows = flip ? flipRows(s.rows) : s.rows;
      for (let j = 0; j < rows.length; j++) {
        const row = rows[j];
        for (let i = 0; i < row.length; i++) {
          const c = row[i];
          if (c !== '.') this._px(x + i, y + j, map && map[c] ? map[c] : c);
        }
      }
    }
    _glyph(g, cx, top, ex, ey, mirror = true) {
      if (!g) return;
      const [rows, ox, oy] = g;
      const s = sp(rows);
      this._spr(s, cx + ox + ex, top + oy + ey);
      if (mirror) this._spr(s, cx + (-ox - s.w) + ex, top + oy + ey, true);
    }

    _step(f, force) {
      if (!this.spec) return;
      const P = this.spec;
      const pf = f - this.poseFrame;
      const st = {
        ox: 0, oy: 0, bob: 0, body: P.body, eyes: P.eyes, mouth: P.mouth, armL: P.armL, armR: P.armR,
        legLift: [0, 0, 0, 0], heldDy: 0, heldRDx: 0, heldRDy: 0, shadow: 1,
        lx: P.look ? P.look[0] : this.gaze[0], ly: P.look ? P.look[1] : this.gaze[1],
      };
      P.anim.split(' ').forEach((a) => ANIMS[a] && ANIMS[a](st, f, pf, this));
      if (this.fidgetK && f - this.fidgetFrame < 9) {
        const k = f - this.fidgetFrame;
        if (this.fidgetK === 'hop') hop(st, k);
        if (this.fidgetK === 'wiggle') st.ox = [0, -1, 0, 1, 0, -1, 0, 1, 0][k];
        if (this.fidgetK === 'look') st.lx = k < 4 ? -1 : k < 8 ? 1 : 0;
      }
      if (this.squishLv) {
        const lv = this.squishLv;
        st.body = lv >= 2 ? 'pancake' : lv === 1 ? 'flat' : lv === -1 ? 'tall' : 'taller';
        st.oy = 0;
        if (lv >= 2) { st.eyes = 'squeeze'; st.armL = st.armR = 'out'; }
        if (lv <= -2) { st.eyes = 'wide'; st.armL = st.armR = 'up'; }
        if (f - this.squishAt > 5) { this.squishLv -= Math.sign(lv); this.squishAt = f - 3; }  // spring back, a step at a time
      }
      if (this.blinking > 0) { if (['open', 'wide'].includes(st.eyes)) st.eyes = 'blink'; this.blinking--; }
      this._draw(st, f, pf);
    }

    _draw(st, f, pf) {
      const P = this.spec;
      const b = this.b;
      b.clearRect(0, 0, CW, CH);
      const ox = st.ox, oy = st.oy;
      const body = BODIES[st.body] || BODIES.base;
      const bx = BX + ox + body.dx, top = BY + oy + body.dy + st.bob;
      const bw = body.s.w, bh = body.s.h;
      const cx = bx + bw / 2;
      const ex = Math.max(-1, Math.min(1, st.lx | 0)), ey = Math.max(-1, Math.min(1, st.ly | 0));
      const shoulder = top + 5;

      // ground: plant
      if (P.ground === 'plant') {
        this._spr(PLANT, 1, 25);
        if (st.grow) this._px(4, 24, 'L');
      }
      // shadow
      const sw = Math.round((oy < -3 ? 8 : 12) * st.shadow);
      for (let i = 0; i < sw; i++) this._px(BX + ox + 1 + (12 - sw) / 2 + i, BY + BH + 2, 'rgba(60,30,20,0.16)');
      // legs
      LEGS.forEach((lx0, i) => {
        const lx = bw < BW ? Math.round(body.dx + (lx0 * (bw - 1)) / (BW - 1)) : lx0;   // tucked in under a narrow body
        const x = BX + ox + lx, y0 = BY + oy + BH - 1 - st.legLift[i];
        const shoes = P.legs === 'sneakers';
        this._px(x, y0, 'b');
        this._px(x, y0 + 1, 'b');
        this._px(x, y0 + 2, shoes ? 'w' : 's');
      });
      // body
      this._spr(body.s, bx, top);
      const costume = P.acc.includes('tv');
      if (!costume && st.eyes !== 'none') {   // 'none': we're looking at its back
        if (P.blush) { this._px(Math.round(cx - 6), top + 5, 'p'); this._px(Math.round(cx - 5), top + 5, 'p'); this._px(Math.round(cx + 4), top + 5, 'p'); this._px(Math.round(cx + 5), top + 5, 'p'); }
        const eyeCx = Math.round(cx);
        this._glyph(EYES[st.eyes] || EYES.open, eyeCx, top, ex, ey);
        if (P.brows && BROWS[P.brows]) this._glyph(BROWS[P.brows], eyeCx, top, ex, Math.min(ey, 0));
        if (st.mouth && MOUTHS[st.mouth]) this._glyph(MOUTHS[st.mouth], eyeCx, top, ex, ey, false);
        if (P.acc.includes('shades')) {
          const y = top + 3;
          for (let i = 0; i < 3; i++) for (let j = 0; j < 2; j++) { this._px(eyeCx - 5 + i, y + j, 'K'); this._px(eyeCx + 2 + i, y + j, 'K'); }
          for (let i = -2; i < 2; i++) this._px(eyeCx + i, y, 'K');
          this._px(eyeCx - 6, y, 'K'); this._px(eyeCx + 5, y, 'K');
          this._px(eyeCx - 4, y, 'G'); this._px(eyeCx + 3, y, 'G');
        }
      }
      // accessories on the body
      if (P.acc.includes('beard')) this._spr(BEARD, bx + 2, top + 5);
      if (P.acc.includes('headband')) {
        for (let x = 0; x < bw; x++) this._px(bx + x, top + 1, x % 4 === 1 ? 'w' : 'x');
        this._px(bx + bw, top + 1, 'x'); this._px(bx + bw + 1, top + 2, 'x'); this._px(bx + bw, top + 2, 'x');
      }
      if (P.acc.includes('sweat')) { const k = f % 16; if (k < 12) { const y = top - 1 + (k >> 2); this._px(bx + bw - 2, y, 'u'); this._px(bx + bw - 2, y + 1, 'u'); this._px(bx + bw - 1, y + 1, 'u'); } }
      if (costume) {
        this._spr(TV, bx - 1, top - 1);
        const face = st.tvFace, fx = bx + 3, fy = top + 2;
        if (face === 'blink') { this._px(fx + 2, fy + 2, 'I'); this._px(fx + 3, fy + 2, 'I'); this._px(fx + 7, fy + 2, 'I'); this._px(fx + 8, fy + 2, 'I'); }
        else { this._px(fx + 2, fy + 1, 'I'); this._px(fx + 2, fy + 2, 'I'); this._px(fx + 8, fy + 1, 'I'); this._px(fx + 8, fy + 2, 'I'); }
        if (face === 'sad') { this._px(fx + 4, fy + 5, 'I'); this._px(fx + 5, fy + 4, 'I'); this._px(fx + 6, fy + 4, 'I'); this._px(fx + 7, fy + 5, 'I'); }
        else { this._px(fx + 3, fy + 4, 'I'); this._px(fx + 4, fy + 5, 'I'); this._px(fx + 5, fy + 5, 'I'); this._px(fx + 6, fy + 5, 'I'); this._px(fx + 7, fy + 4, 'I'); }
        if (f % 8 < 4) this._px(bx + 12, top + 6, 'I');
      }
      if (P.acc.includes('headphones')) {
        for (let x = 2; x < bw - 2; x++) { this._px(bx + x, top - 2, 'Y'); this._px(bx + x, top - 1, 'y'); }
        this._px(bx + 1, top - 1, 'Y'); this._px(bx + bw - 2, top - 1, 'Y');
        this._px(bx, top, 'Y'); this._px(bx + bw - 1, top, 'Y');
        for (let y = 1; y <= 5; y++) {
          const edge = y === 1 || y === 5;
          this._px(bx - 1, top + y, 'Y'); this._px(bx, top + y, edge ? 'Y' : 'j');
          this._px(bx + bw, top + y, 'Y'); this._px(bx + bw - 1, top + y, edge ? 'Y' : 'j');
        }
      }
      if (P.acc.includes('napbook')) this._spr(NAPBOOK, bx - 1, top - 4);
      if (P.hat && HATS[P.hat]) { const [s, hx, overlap] = HATS[P.hat]; this._spr(s, bx + hx + (bw - BW) / 2, top - s.h + overlap); }
      // signs over the head
      const sign = (s) => { const x = Math.round(bx + (bw - s.w) / 2), y = top - s.h - 2 - (f % 30 < 15 ? 0 : 1); this._spr(s, x, y); return [x, y]; };
      if (P.acc.includes('mute')) sign(MUTE);
      if (P.acc.includes('alert')) sign(ALERT);
      if (P.acc.includes('dots')) {   // ... thinking
        const n = 1 + ((f >> 2) % 3), y = top - 4 - (f % 30 < 15 ? 0 : 1);
        for (let i = 0; i < n; i++) { this._px(bx + bw + 1 + i * 2, y - i, 'G'); }
      }
      if (P.acc.includes('binoculars')) {
        const ec = Math.round(cx) + ex, y = top + 2;
        [ec - 6, ec + 1].forEach((x0) => { for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) this._px(x0 + i, y + j, i > 0 && i < 3 && j === 1 ? 'a' : 'K'); });
        this._px(ec - 2, y + 1, 'K'); this._px(ec, y + 1, 'K'); this._px(ec - 1, y + 1, 'K');
      }
      if (P.acc.includes('helpers')) {
        const k = st.helperHop || 0;
        this._spr(MINI, 2, BY + BH - 2 - (k === 1 ? 1 : 0));
        this._spr(MINI, CW - 8, BY + BH - 2 - (k === 3 ? 1 : 0), true);
      }
      if (P.acc.includes('lowbatt')) { const [x, y] = sign(BATTERY); if (f % 10 < 6) { this._px(x + 1, y + 1, 'R'); this._px(x + 1, y + 2, 'R'); } }
      if (P.acc.includes('charging')) {
        const [x, y] = sign(BATTERY);
        for (let i = 0; i <= (f >> 1) % 5; i++) { this._px(x + 1 + i, y + 1, 'L'); this._px(x + 1 + i, y + 2, 'L'); }
        this._spr(BOLT, x + 9, y - 1);
      }
      if (st.orbit != null) for (let k = 0; k < 2; k++) {
        const a = st.orbit * 0.7 + k * Math.PI;
        this._spr(FX.sparkle.sprites[0], Math.round(cx - 1 + Math.cos(a) * 8), Math.round(top - 3 + Math.sin(a) * 2));
      }

      // held item, left hand
      if (P.held) {
        const key = P.held === 'water' && st.tilt ? 'waterTilt' : P.held;
        const it = ITEMS[key];
        const hand = HANDS[st.armL] || HANDS.hold;
        const x = bx + hand[0] - it.grab[0], y = shoulder + hand[1] + st.heldDy - it.grab[1];
        this._spr(it.s, x, y);
        if (it.steam) for (let k = 0; k < 3; k++) {
          const ph = (f + k * 4) % 12;
          if (ph < 9) this._px(x + 3 + (k % 2) + ((ph >> 1) % 2), y - 1 - (ph >> 1), 't');
        }
        if (P.held === 'water' && st.tilt) for (let k = 0; k < 3; k++) { const ph = (f + k * 2) % 6; this._px(x - 1 + (k % 2), y + 3 + ph, 'u'); }
        if (P.held === 'can' && P.anim === 'sip' && f % 6 < 3) this._px(x + 2 + (f % 3), y - 1 - (f % 2), 'q');
      }
      // held item, right hand
      if (P.heldR) {
        const hand = HANDS[st.armR] || HANDS.hold;
        const hxR = bx + bw - 1 - hand[0], hyR = shoulder + hand[1] + st.heldRDy;
        if (P.heldR === 'staff') {
          const sx = hxR, sy = top - 6;
          for (let y = sy + 2; y <= BY + oy + BH + 1; y++) this._px(sx, y, y === shoulder ? 'H' : 'h');
          if (st.glow) { [[-2, 0], [2, 0], [0, -2], [0, 2], [-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([a, c]) => this._px(sx + a, sy + c, 'rgba(255,214,74,0.45)')); }
          this._px(sx, sy, 'O'); this._px(sx - 1, sy, 'z'); this._px(sx + 1, sy, 'z'); this._px(sx, sy - 1, 'z'); this._px(sx, sy + 1, 'Z');
        } else {
          const it = ITEMS[P.heldR];
          const x = hxR - it.grab[0] + st.heldRDx, y = hyR - it.grab[1];
          this._spr(it.s, x, y);
          if (P.heldR === 'pan') {
            const fs = FOOD[st.foodSpin || 0];
            this._spr(fs, x + 6, y - 1 + (st.foodY || 0) - (fs.h - 1));
            if (st.sizzle && f % 3 === 0) this.burst('bit', 1);
          }
        }
      }
      // ball
      if (st.ball) this._spr(BALL, st.ball[0], st.ball[1]);
      // book held in front (arms hidden behind it)
      if (P.front === 'book') {
        const y = shoulder + 1;
        this._spr(BOOK, bx + 1, y);
        if (st.flip) { for (let j = 0; j < 5; j++) this._px(bx + 7 + st.flip, y + j, 'P'); }
      }
      // arms
      const drawArm = (name, side) => {
        const a = ARMS[name];
        if (!a) return;
        const [rows, ax, ay] = a;
        const s = sp(rows);
        if (side === 'L') this._spr(s, bx + ax, shoulder + ay);
        else this._spr(s, bx + bw - ax - s.w, shoulder + ay, true);
      };
      drawArm(st.armL, 'L');
      drawArm(st.armR, 'R');
      if (P.acc.includes('poms')) {
        const pom = (x, y) => { this._px(x, y, 'z'); this._px(x - 1, y, 'i'); this._px(x + 1, y, 'i'); this._px(x, y - 1, 'i'); this._px(x, y + 1, 'i'); };
        const hand = (name, side) => { const h = HANDS[name] || HANDS.rest; return side === 'L' ? [bx + h[0], shoulder + h[1]] : [bx + bw - 1 - h[0], shoulder + h[1]]; };
        pom(...hand(st.armL, 'L'));
        pom(...hand(st.armR, 'R'));
      }
      // laptop in front, with live "code" on the screen (or a terminal: green text, a block cursor)
      if (P.front === 'laptop' || P.front === 'terminal') {
        const term = P.front === 'terminal';
        const lx = BX + ox + 8, ly = BY + oy + 5;
        this._spr(LAPTOP, lx, ly);
        const seed = st.typing ? (f >> 1) : 0;
        const rows = [[lx + 4, ly + 1], [lx + 3, ly + 2], [lx + 3, ly + 3]];
        rows.forEach(([x0, y], row) => {
          const len = row === 2 ? 1 : 1 + ((seed * 7 + row * 5) % 3);
          for (let i = 0; i < len; i++) this._px(x0 + i, y, term ? 'v' : 'W');
        });
        if (f % 6 < 3) this._px(lx + 5, ly + 3, term ? 'W' : 'v');
      }
      // carrying the ball in its mouth, like a dog
      if (this.carry && TOYS[this.carry] && st.eyes !== 'none') {
        const s = TOYS[this.carry];
        this._spr(s, Math.round(cx) - (s.w >> 1) + ex, top + 5);
      }

      // particles
      if (this.fxEvery && pf > 0 && pf % this.fxEvery === 0) this.burst(this.spec.fx[0], this.spec.fx[0] === 'confetti' ? 6 : 1);
      this.parts = this.parts.filter((p) => {
        p.age++;
        p.vy += p.g;
        p.x += p.vx;
        p.y += p.vy;
        if (p.age > p.life) return false;
        const def = FX[p.kind];
        if (p.kind === 'confetti') { this._px(Math.round(p.x), Math.round(p.y), p.color); return true; }
        let s = def.sprites[p.spr] || def.sprites[0];
        if (p.kind === 'sparkle') s = def.sprites[p.age > 2 && p.age < 7 ? 1 : 0];
        if (p.kind === 'z' && p.age > p.life - 6) s = def.sprites[1];
        const wob = p.kind === 'heart' ? Math.round(Math.sin(p.age / 2)) : 0;
        this._spr(s, Math.round(p.x) + wob, Math.round(p.y));
        return true;
      });

      // blit, crisp
      const c = this.ctx;
      c.imageSmoothingEnabled = false;
      c.clearRect(0, 0, this.canvas.width, this.canvas.height);
      c.drawImage(this.buf, 0, 0, this.canvas.width, this.canvas.height);
    }

    destroy() { all.delete(this); clearTimeout(this._blinkT); this.el.innerHTML = ''; }
  }

  Critter.POSES = Object.keys(POSES);
  Critter.PAL = PAL;
  Critter.SIZE = [CW, CH];
  root.Critter = Critter;
  root.MochiView = Critter;
})(typeof window !== 'undefined' ? window : this);
