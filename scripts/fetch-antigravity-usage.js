#!/usr/bin/env node
// Bridges the native Swift app to Antigravity's `agy` CLI /usage panel, the
// same PTY-drive-and-parse approach fetch-usage.js uses for `claude`. Swift
// shells out to this instead of re-implementing the ANSI-grid parser.
"use strict";
const { spawn, exec } = require("child_process");
const path = require("path");
const os = require("os");
const fs = require("fs");
const { ansiToLines, stripBoxChars } = require("./ansi-grid.js");

function findAgyPath() {
  return [
    "/opt/homebrew/bin/agy",
    "/usr/local/bin/agy",
    "/usr/bin/agy",
    path.join(os.homedir(), ".local/bin/agy"),
  ];
}

// The quota panel's bar/percentage is how much is *remaining*, not used —
// e.g. "98.68%" full means almost nothing has been used. Every other
// provider's `pct` in this app means percent USED, so this inverts it.
function usedPctFromRemaining(remainingStr) {
  const remaining = parseFloat(remainingStr);
  if (Number.isNaN(remaining)) return null;
  return Math.round(100 - remaining);
}

// agy's own duration text is always "<N>h <M>m" (e.g. "157h 4m") — never
// days, and never correctly pluralized. Re-express in days/hours (falling
// back to minutes for anything under an hour), singular/plural picked per unit.
function formatAgyDuration(str) {
  const hMatch = str.match(/(\d+)\s*h/);
  const mMatch = str.match(/(\d+)\s*m/);
  const totalMinutes = (hMatch ? parseInt(hMatch[1], 10) : 0) * 60 + (mMatch ? parseInt(mMatch[1], 10) : 0);
  if (totalMinutes <= 0) return str;

  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
  const minutes = totalMinutes % 60;
  const unit = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

  const parts = [];
  if (days > 0) parts.push(unit(days, "day"));
  if (hours > 0) parts.push(unit(hours, "hour"));
  if (days === 0 && hours === 0 && minutes > 0) parts.push(unit(minutes, "minute"));
  return parts.join(" ") || str;
}

function parseAgyOutput(raw) {
  const lines = ansiToLines(raw)
    .map((l) => stripBoxChars(l).trim())
    .filter(Boolean);
  const text = lines.join("\n");

  const geminiSectionMatch = text.match(/GEMINI MODELS([\s\S]*?)(?:CLAUDE AND GPT MODELS|$)/);
  if (!geminiSectionMatch) {
    // "not signed in" also flashes during the normal startup handshake
    // (banner shows it, then silently signs in from a cached token), so
    // only trust it once we know the quota panel never showed up at all —
    // if an account email did show, sign-in actually succeeded and the
    // panel parse itself just failed.
    const sawAccount = /[\w.+-]+@[\w-]+\.[\w.-]+/.test(text);
    if (!sawAccount && /currently not signed in/.test(raw)) {
      return { signedIn: false, weeklyPct: null, fiveHourPct: null, error: null };
    }
    return { signedIn: true, weeklyPct: null, fiveHourPct: null, error: "Could not find quota panel." };
  }
  const section = geminiSectionMatch[1];

  // "100% remaining · Refreshes in 157h 4m" — the "Refreshes in …" clause is
  // only present once some quota has actually been consumed; a completely
  // untouched limit just reads "Quota available" with nothing to count down.
  const weeklyMatch = section.match(/Weekly Limit[\s\S]*?([\d.]+)%\s*\n\s*(?:([\d.]+)% remaining(?:\s*·\s*Refreshes in ([^\n]+))?|Quota available)/);
  const fiveHourMatch = section.match(/Five Hour Limit[\s\S]*?([\d.]+)%\s*\n\s*(?:([\d.]+)% remaining(?:\s*·\s*Refreshes in ([^\n]+))?|Quota available)/);

  const weeklyPct = weeklyMatch ? usedPctFromRemaining(weeklyMatch[2] ?? weeklyMatch[1]) : null;
  const fiveHourPct = fiveHourMatch ? usedPctFromRemaining(fiveHourMatch[2] ?? fiveHourMatch[1]) : null;
  const weeklyReset = weeklyMatch?.[3] ? `Refreshes in ${formatAgyDuration(weeklyMatch[3].trim())}` : null;
  const fiveHourReset = fiveHourMatch?.[3] ? `Refreshes in ${formatAgyDuration(fiveHourMatch[3].trim())}` : null;

  return {
    signedIn: true,
    weeklyPct,
    fiveHourPct,
    weeklyReset,
    fiveHourReset,
    error: weeklyPct == null && fiveHourPct == null ? "Could not parse quota." : null,
  };
}

function runAgyUsage(agyPath, augmentedEnv) {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => resolve({ error: "Timed out." }), 60000);
    const ptyWrapper = path.join(__dirname, "agy-pty-wrapper.py");
    const child = spawn("python3", [ptyWrapper, agyPath], {
      env: { ...augmentedEnv, TERM: "dumb", FORCE_COLOR: "0" },
    });
    const doneTimeout = setTimeout(() => child.kill(), 58000);
    let accumulated = "";
    child.stdout.on("data", (d) => (accumulated += d.toString()));
    child.on("close", () => {
      clearTimeout(timeout);
      clearTimeout(doneTimeout);
      resolve(parseAgyOutput(accumulated));
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

  const agyPath = await new Promise((resolve) => {
    exec("which agy", { env: augmentedEnv }, (err, stdout) => {
      const fromWhich = (stdout || "").trim().split("\n")[0];
      resolve(
        fromWhich ||
          findAgyPath().find((p) => {
            try { fs.accessSync(p); return true; } catch { return false; }
          }) ||
          "agy"
      );
    });
  });

  const usage = await runAgyUsage(agyPath, augmentedEnv);
  process.stdout.write(JSON.stringify(usage) + "\n");
}

main();
