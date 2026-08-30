#!/usr/bin/env bash
# Re-captures parser fixtures from the CLIs installed on this machine and
# regenerates the expected JSON from os-menu's JavaScript parsers.
#
# This rewrites the contract the test suite checks against, so only run it when
# a CLI's output format has actually changed — and read the resulting diff.
set -euo pipefail

# os-menu lives in this repo now, so resolve it relative to the script
# rather than to a sibling checkout of the retired claude-usage-tracker.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OSMENU="${OSMENU:-$REPO_ROOT/os-menu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$HERE/Tests/UsageCoreTests/Fixtures"
BIN="$(swift build --show-bin-path)"

capture() {
  local provider="$1" binary="$2" out="$3"; shift 3
  local path
  if ! path="$(command -v "$binary")"; then
    echo "  skip  $provider ($binary not installed)"; return
  fi
  echo "  drive $provider …"
  "$BIN/ptydrive" "$provider" "$path" "$@" > "$FIX/$out"
  echo "        $(wc -c < "$FIX/$out" | tr -d ' ') bytes → $out"
}

capture claude      claude       claude-usage.ansi      /usage
capture claude      claude       claude-stats.ansi      /stats
capture antigravity agy          antigravity-usage.ansi
capture codex       codex        codex-status.ansi
capture cursor      cursor-agent cursor-usage.ansi

echo "regenerating expected JSON from the JavaScript parsers…"
node -e "
const fs=require('fs');
const {parseUsageOutput,parseStatsOutput}=require('$OSMENU/usage-parser.js');
const {ansiToLines,stripBoxChars}=require('$OSMENU/ansi-grid.js');
const m=fs.readFileSync('$OSMENU/main.js','utf8');
const src=m.slice(m.indexOf('function usedPctFromRemaining'), m.indexOf('function runCursorCommand'));
const P=new Function('ansiToLines','stripBoxChars',src+'; return {parseAgyOutput,parseCodexOutput,parseCursorOutput};')(ansiToLines,stripBoxChars);
const has=f=>fs.existsSync('$FIX/'+f);
const rd=f=>fs.readFileSync('$FIX/'+f,'utf8');
const w=(f,o)=>fs.writeFileSync('$FIX/'+f, JSON.stringify(o,null,2)+'\n');
if(has('claude-usage.ansi'))      w('claude-usage.expected.json',      parseUsageOutput(rd('claude-usage.ansi')));
if(has('claude-stats.ansi'))      w('claude-stats.expected.json',      parseStatsOutput(rd('claude-stats.ansi')).stats);
if(has('antigravity-usage.ansi')) w('antigravity-usage.expected.json', P.parseAgyOutput(rd('antigravity-usage.ansi')));
if(has('codex-status.ansi'))      w('codex-status.expected.json',      P.parseCodexOutput(rd('codex-status.ansi')));
if(has('cursor-usage.ansi'))      w('cursor-usage.expected.json',      P.parseCursorOutput(rd('cursor-usage.ansi')));
"
echo "done — review the diff before committing."
