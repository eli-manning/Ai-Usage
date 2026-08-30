#!/usr/bin/env bash
# Re-checks the ported Swift parsers against os-menu's JavaScript originals,
# using the committed fixtures. The XCTest suite already asserts this against
# the checked-in expected JSON; this script instead re-runs the *live* JS to
# catch the case where os-menu's parsers changed and the expectations are now
# stale.
set -euo pipefail

# os-menu lives in this repo now, so resolve it relative to the script
# rather than to a sibling checkout of the retired claude-usage-tracker.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OSMENU="${OSMENU:-$REPO_ROOT/os-menu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$HERE/Tests/UsageCoreTests/Fixtures"
BIN="$(swift build --show-bin-path)"

if [ ! -d "$OSMENU" ]; then
  echo "skip: os-menu checkout not found at $OSMENU (set OSMENU=…)" >&2
  exit 0
fi

swift build --product parsecheck >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

node -e "
const fs=require('fs'), path=require('path');
const {parseUsageOutput,parseStatsOutput}=require('$OSMENU/usage-parser.js');
const {ansiToLines,stripBoxChars}=require('$OSMENU/ansi-grid.js');
// main.js is an Electron entrypoint, so lift its three pure parsers out.
const m=fs.readFileSync('$OSMENU/main.js','utf8');
const src=m.slice(m.indexOf('function usedPctFromRemaining'), m.indexOf('function runCursorCommand'));
const P=new Function('ansiToLines','stripBoxChars',src+'; return {parseAgyOutput,parseCodexOutput,parseCursorOutput};')(ansiToLines,stripBoxChars);
const rd=f=>fs.readFileSync('$FIX/'+f,'utf8');
const w=(f,o)=>fs.writeFileSync('$tmp/'+f,JSON.stringify(o));
w('usage.json',  parseUsageOutput(rd('claude-usage.ansi')));
w('stats.json',  parseStatsOutput(rd('claude-stats.ansi')).stats);
w('agy.json',    P.parseAgyOutput(rd('antigravity-usage.ansi')));
w('cursor.json', P.parseCursorOutput(rd('cursor-usage.ansi')));
"

"$BIN/parsecheck" usage  "$FIX/claude-usage.ansi"      > "$tmp/usage.swift.json"
"$BIN/parsecheck" stats  "$FIX/claude-stats.ansi"      > "$tmp/stats.swift.json"
"$BIN/parsecheck" agy    "$FIX/antigravity-usage.ansi" > "$tmp/agy.swift.json"
"$BIN/parsecheck" cursor "$FIX/cursor-usage.ansi"      > "$tmp/cursor.swift.json"

status=0
for name in usage stats agy cursor; do
  if python3 - "$tmp/$name.json" "$tmp/$name.swift.json" <<'PY'
import json,sys
def norm(o):
    if isinstance(o,dict): return {k:norm(v) for k,v in sorted(o.items()) if v is not None}
    if isinstance(o,list): return [norm(x) for x in o]
    return o
sys.exit(0 if norm(json.load(open(sys.argv[1])))==norm(json.load(open(sys.argv[2]))) else 1)
PY
  then printf '  ok    %s\n' "$name"
  else printf '  DIFF  %s\n' "$name"; status=1
  fi
done

[ $status -eq 0 ] && echo "Swift and JavaScript parsers agree." || echo "PARSERS HAVE DRIFTED." >&2
exit $status
