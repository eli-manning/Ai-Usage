#!/usr/bin/env node
// Bridges the native Swift app to the Codex CLI's `/status` panel, the same
// PTY-drive-and-parse approach fetch-antigravity-usage.js uses for `agy`.
"use strict";
const { spawn, exec } = require("child_process");
const path = require("path");
const os = require("os");
const fs = require("fs");
const { ansiToLines, stripBoxChars } = require("./ansi-grid.js");

function findCodexPath() {
  return [
    "/opt/homebrew/bin/codex",
    "/usr/local/bin/codex",
    "/usr/bin/codex",
    path.join(os.homedir(), ".local/bin/codex"),
  ];
}

// Every limit row on the panel reads like:
//   "Monthly limit:        [] 99% left (resets 20:27 on 30 Aug)"
//   "5h limit:              [] 82% left (resets in 3h 12m)"
// — free accounts only ever show "Monthly limit"; paid plans add a rolling
// 5-hour and/or weekly one, but the row shape is identical, so one regex
// picks up whichever set of rows a given account actually has instead of
// hardcoding which limits exist.
const limitRe = /^(.+?limit):\s*\[.*?\]\s*(\d+)%\s*left(?:\s*\(resets\s+([^)]+)\))?$/i;
const accountRe = /^Account:\s*(\S+)\s*\(([^)]+)\)/;

function parseCodexOutput(raw) {
  const lines = ansiToLines(raw)
    .map((l) => stripBoxChars(l).trim())
    .filter(Boolean);

  const account = lines.map((l) => l.match(accountRe)).find(Boolean);
  if (!account) {
    // A logged-out `codex` blocks on its own sign-in flow (ChatGPT OAuth or
    // an API key prompt) instead of ever reaching /status — this app can't
    // drive that interactively, so it just reports "not signed in" and
    // leaves it to the user the same way Claude/Antigravity's own sign-in
    // wedge does.
    if (/sign in|log ?in/i.test(raw)) {
      return { signedIn: false, plan: null, limits: [], error: null };
    }
    return { signedIn: true, plan: null, limits: [], error: "Could not find status panel." };
  }

  const limits = [];
  for (const line of lines) {
    const m = line.match(limitRe);
    if (m) {
      limits.push({
        name: m[1].trim(),
        pctUsed: 100 - parseInt(m[2], 10),
        reset: m[3] ? m[3].trim() : null,
      });
    }
  }

  return {
    signedIn: true,
    plan: account[2].trim(),
    limits,
    error: limits.length === 0 ? "Could not parse quota." : null,
  };
}

function runCodexStatus(codexPath, augmentedEnv) {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => resolve({ error: "Timed out." }), 30000);
    const ptyWrapper = path.join(__dirname, "codex-pty-wrapper.py");
    const child = spawn("python3", [ptyWrapper, codexPath], {
      env: { ...augmentedEnv, TERM: "dumb", FORCE_COLOR: "0" },
    });
    const doneTimeout = setTimeout(() => child.kill(), 28000);
    let accumulated = "";
    child.stdout.on("data", (d) => (accumulated += d.toString()));
    child.on("close", () => {
      clearTimeout(timeout);
      clearTimeout(doneTimeout);
      resolve(parseCodexOutput(accumulated));
    });
    child.on("error", (e) => {
      clearTimeout(timeout);
      resolve({ error: `Process error: ${e.message}` });
    });
  });
}

async function main() {
  const extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", path.join(os.homedir(), ".local/bin")];
  const augmentedEnv = { ...process.env, PATH: `${extraPaths.join(":")}:${process.env.PATH || ""}` };

  const codexPath = await new Promise((resolve) => {
    exec("which codex", { env: augmentedEnv }, (err, stdout) => {
      const fromWhich = (stdout || "").trim().split("\n")[0];
      resolve(
        fromWhich ||
          findCodexPath().find((p) => {
            try { fs.accessSync(p); return true; } catch { return false; }
          }) ||
          "codex"
      );
    });
  });

  const usage = await runCodexStatus(codexPath, augmentedEnv);
  process.stdout.write(JSON.stringify(usage) + "\n");
}

main();
