#!/usr/bin/env node
// Bridges the native Swift app to the Cursor CLI's `/usage` panel, the same
// PTY-drive-and-parse approach fetch-codex-usage.js uses for `codex`.
"use strict";
const { spawn, exec } = require("child_process");
const path = require("path");
const os = require("os");
const fs = require("fs");
const { ansiToLines, stripBoxChars } = require("./ansi-grid.js");

function findCursorPath() {
  return [
    path.join(os.homedir(), ".local/bin/cursor-agent"),
    "/opt/homebrew/bin/cursor-agent",
    "/usr/local/bin/cursor-agent",
  ];
}

// "Usage • Free                                    Resets Sep 1" — the plan
// tier and the one reset date that applies to every row below it.
const headerRe = /^Usage\s*[•·]\s*(.+?)\s{2,}Resets\s+(.+)$/;
// Row shape is "<category>   <optional current-value column>   NN% used" —
// e.g. "Included        0% used" (nothing in the middle column) or
// something like "API    42 requests    12% used" on a plan that actually
// has on-demand usage. The label and the final percentage are what matter;
// whatever sits between them is skipped rather than assumed to have a
// fixed shape.
const rowRe = /^([A-Za-z][\w/ -]*?)\s{2,}.*?(\d+)%\s*used\s*$/i;

function parseCursorOutput(raw) {
  const lines = ansiToLines(raw)
    .map((l) => stripBoxChars(l).trim())
    .filter(Boolean);

  const header = lines.map((l) => l.match(headerRe)).find(Boolean);
  if (!header) {
    // A logged-out cursor-agent blocks on its own sign-in flow instead of
    // ever reaching /usage — same situation as a logged-out `codex`.
    if (/sign in|log ?in|not authenticated/i.test(raw)) {
      return { signedIn: false, plan: null, reset: null, rows: [], error: null };
    }
    return { signedIn: true, plan: null, reset: null, rows: [], error: "Could not find usage panel." };
  }

  const rows = [];
  for (const line of lines) {
    const m = line.match(rowRe);
    if (m) {
      rows.push({ name: m[1].trim(), pctUsed: parseInt(m[2], 10) });
    }
  }

  return {
    signedIn: true,
    plan: header[1].trim(),
    reset: header[2].trim(),
    rows,
    error: rows.length === 0 ? "Could not parse quota." : null,
  };
}

function runCursorUsage(cursorPath, augmentedEnv) {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => resolve({ error: "Timed out." }), 30000);
    const ptyWrapper = path.join(__dirname, "cursor-pty-wrapper.py");
    const child = spawn("python3", [ptyWrapper, cursorPath], {
      env: { ...augmentedEnv, TERM: "dumb", FORCE_COLOR: "0" },
    });
    const doneTimeout = setTimeout(() => child.kill(), 28000);
    let accumulated = "";
    child.stdout.on("data", (d) => (accumulated += d.toString()));
    child.on("close", () => {
      clearTimeout(timeout);
      clearTimeout(doneTimeout);
      resolve(parseCursorOutput(accumulated));
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

  const cursorPath = await new Promise((resolve) => {
    exec("which cursor-agent", { env: augmentedEnv }, (err, stdout) => {
      const fromWhich = (stdout || "").trim().split("\n")[0];
      resolve(
        fromWhich ||
          findCursorPath().find((p) => {
            try { fs.accessSync(p); return true; } catch { return false; }
          }) ||
          "cursor-agent"
      );
    });
  });

  const usage = await runCursorUsage(cursorPath, augmentedEnv);
  process.stdout.write(JSON.stringify(usage) + "\n");
}

main();
