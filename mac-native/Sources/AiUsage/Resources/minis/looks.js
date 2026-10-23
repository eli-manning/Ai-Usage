/* Each provider's mini: its name, its critter (see SPECIES in pet.js) and its colours. Shared by the mini and its panel. */
window.MINI_LOOKS = {
  // Mochi, Claude Code's mascot.
  claude: { name: 'Claude', accent: '#e5714b' },
  // Codex's pet: periwinkle, with light eyes on its dark visor.
  codex: { name: 'Codex', accent: '#7183F2', species: 'codex',
    palette: { b: '#7183F2', l: '#97A6FF', s: '#5262D2', d: '#3C49A8', p: '#B9C3FF', e: '#D9E4FF' } },
  // Antigravity runs on Gemini, so it gets Gemini's orb and sparkle (the gradient lives in the sprite).
  antigravity: { name: 'Antigravity', accent: '#6C7EEB', species: 'gemini', palette: { b: '#6C7EEB', s: '#5465C9' } },
  // Cursor's greys: white arrow, light top, dark left face, mid right face.
  cursor: { name: 'Cursor', accent: '#55555c', species: 'cursor',
    palette: { l: '#F4F4F6', b: '#8E8E95', s: '#66666D', d: '#3B3B41', q: '#C9C9CF' } },
};
