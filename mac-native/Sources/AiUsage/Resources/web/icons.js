/* Little pixel icons for the speech bubble, drawn with Mochi's own palette.
   Emoji are off by default: each one Mochi says is swapped for the matching icon here, or dropped if there's none.
   Lines can also name an icon directly, like ":check:", which turns into its emoji when emoji are on. */
(function (root) {
  'use strict';
  const PAL = root.Critter.PAL;

  const ICONS = {
    drop: ['...u...', '..uuu..', '.uuuuu.', '.uAuuu.', 'uAuuuuU', '.uuuuU.', '..UUU..'],
    mug: ['..DDDDD', '..DoooD', 'DDCCCCD', 'D.CCCCD', 'DDCCCCD', '..DCCCD', '...DDD.'],
    bolt: ['...zz', '..zz.', '.zzzz', '..zz.', '.zz..', 'zz...'],
    shoe: ['..xx...', '.xxxx..', '.xxwxxx', 'xxxxxxx', 'wwwwwww'],
    sparkle: ['..z..', '..z..', 'zzwzz', '..z..', '..z..'],
    heart: ['.jj.jj.', 'jjjjjjj', 'jjjjjjj', '.jjjjj.', '..jjj..', '...j...'],
    moon: ['..zzz.', '.zz...', 'zz....', 'zz....', '.zz...', '..zzz.'],
    star: ['...z...', '..zzz..', 'zzzzzzz', '.zzzzz.', '.zz.zz.', 'z.....z'],
    note: ['..zzz', '..z.z', '..z.z', 'zzz.z', 'zz.zz', '...zz'],
    book: ['NnnnnN', 'NPPPPN', 'NPmmPN', 'NPPPPN', 'NNNNNN'],
    duck: ['..zz...', '.zezz..', 'ZZzzz..', '..zzzzz', '.zzzzzz', '..zzzz.'],
    popcorn: ['.OwOzO.', 'OzOwOwO', 'RwRwRwR', 'RwRwRwR', '.RwRwR.', '.RwRwR.'],
    tv: ['EEEEEEE', 'EJJJJJE', 'EJIJIJE', 'EJJJJJE', 'EEEEEEE', '.Q...Q.'],
    battery: ['GGGGGGG.', 'GRR...GG', 'GRR...GG', 'GGGGGGG.'],
    magnifier: ['.ggg.', 'gAAwg', 'gAAAg', 'gAAAg', '.ggg.', '....h', '....h'],
    plant: ['.L...L.', 'LLM.MLL', '..MLM..', 'TTTTTTT', '.TTTTT.', '..XXX..'],
    pancake: ['.FFFFF.', 'fffffff', '.FFFFF.', 'fffffff', '.qqqqq.'],
    ball: ['.RR.', 'RwRR', 'RRRR', '.RR.'],
    clock: ['.ggggg.', 'gwwGwwg', 'gwwGwwg', 'gwwGGwg', 'gwwwwwg', '.ggggg.'],
    shades: ['KKK.KKK', 'KGKKKGK', 'KKK.KKK'],
    sun: ['z..z..z', '..zzz..', 'zzzzzzz', '..zzz..', 'z..z..z'],
    check: ['......M', '.....MM', 'M...MM.', 'MM.MM..', '.MMM...', '..M....'],
    cross: ['c....c', 'cc..cc', '.cccc.', '.cccc.', 'cc..cc', 'c....c'],
    hand: ['.b.b.b.', '.b.b.b.', '.bbbbbb', 'bbbbbbb', '.bbbbb.', '..bbb..'],
    bang: ['RR', 'RR', 'RR', 'RR', '..', 'RR'],
    gear: ['...kkk...', '.kkkqkkk.', '.kqqqqqk.', 'kkqqkqqkk', 'kqqk.kqqk', 'kkqqkqqkk', '.kqqqqqk.', '.kkkqkkk.', '...kkk...'],   // the cog Mochi holds
    window: ['GGGGGGGG', 'GRGzGMGG', 'GwwwwwwG', 'GwwwwwwG', 'GwwwwwwG', 'GGGGGGGG'],
    eye: ['..kkk..', '.kwwwk.', 'kwwkwwk', '.kwwwk.', '..kkk..'],
    refresh: ['..GGG.G', '.G...GG', 'G...GGG', 'G......', 'G.....G', '.G...G.', '..GGG..'],
  };

  // which icon stands in for which emoji (anything not listed is dropped)
  const EMOJI = {
    '💧': 'drop', '☕': 'mug', '⚡': 'bolt', '🚶': 'shoe', '✨': 'sparkle', '💜': 'heart', '🌙': 'moon', '💤': 'moon',
    '🎉': 'star', '🎧': 'note', '📚': 'book', '🦆': 'duck', '🍿': 'popcorn', '📺': 'tv', '🪫': 'battery', '🔍': 'magnifier',
    '🌱': 'plant', '🌿': 'plant', '🥞': 'pancake', '🍳': 'pancake', '🍽': 'pancake', '⚽': 'ball', '⏰': 'clock', '😎': 'shades',
    '☀': 'sun', '✅': 'check', '❌': 'cross', '✋': 'hand', '❗': 'bang',
  };
  const TOKEN_EMOJI = Object.fromEntries(Object.entries(EMOJI).map(([e, n]) => [n, e]).reverse());

  const EMOJI_RE = /\p{Extended_Pictographic}(?:️|‍\p{Extended_Pictographic})*️?/gu;
  const TOKEN_RE = /:([a-z]+):/g;

  const urls = {};
  function iconURL(name) {
    if (urls[name]) return urls[name];
    const rows = ICONS[name];
    const k = 2;
    const c = document.createElement('canvas');
    c.width = rows[0].length * k;
    c.height = rows.length * k;
    const g = c.getContext('2d');
    rows.forEach((row, y) => [...row].forEach((ch, x) => {
      if (ch === '.' || !PAL[ch]) return;
      g.fillStyle = PAL[ch];
      g.fillRect(x * k, y * k, k, k);
    }));
    return (urls[name] = c.toDataURL());
  }

  function icon(name) {
    const img = document.createElement('img');
    img.className = 'px-icon';
    img.src = iconURL(name);
    img.alt = '';
    const rows = ICONS[name];
    img.style.width = rows[0].length * 2 + 'px';
    img.style.height = rows.length * 2 + 'px';
    return img;
  }

  // Fills `el` with `text`: emoji as they are, or swapped for pixel icons.
  function render(el, text, emoji) {
    el.textContent = '';
    if (emoji) { el.textContent = text.replace(TOKEN_RE, (m, n) => TOKEN_EMOJI[n] || m); return; }
    const marked = text.replace(TOKEN_RE, (m, n) => (ICONS[n] ? `\u0000${n}\u0000` : m))
      .replace(EMOJI_RE, (m) => { const n = EMOJI[m.replace(/️/g, '')]; return n ? `\u0000${n}\u0000` : ''; });
    const parts = marked.split('\u0000');
    parts.forEach((part, i) => {
      if (i % 2) el.appendChild(icon(part));
      else if (part) el.appendChild(document.createTextNode(part));
    });
    // tidy the gaps dropped emoji leave behind
    el.normalize();
    el.childNodes.forEach((n) => { if (n.nodeType === 3) n.textContent = n.textContent.replace(/ {2,}/g, ' '); });
    if (el.firstChild && el.firstChild.nodeType === 3) el.firstChild.textContent = el.firstChild.textContent.replace(/^\s+/, '');
    if (el.lastChild && el.lastChild.nodeType === 3) el.lastChild.textContent = el.lastChild.textContent.replace(/\s+$/, '');
  }

  root.MochiIcons = { render, ICONS };
})(typeof window !== 'undefined' ? window : this);
