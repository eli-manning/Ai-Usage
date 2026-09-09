// Drives win-pty-driver.js against a fake ConPTY.
//
// The real thing can only be exercised on Windows with the provider CLIs
// installed and signed in, which no CI runner has — but the part that actually
// goes wrong is the state machine (does it wait for the ready prompt, type the
// command, hold out for the panel rather than grabbing a half-painted screen),
// and that only needs something that looks like a terminal.
const assert = require("assert");
const { SPECS, driveWindows, resolveLaunchable } = require("../win-pty-driver");

// Stands in for a node-pty session: records what the driver writes, and lets a
// test push screen content back as if the CLI had painted it.
function fakePty() {
  const written = [];
  let dataHandler = () => {};
  let exitHandler = () => {};
  const proc = {
    written,
    killed: false,
    write: (s) => written.push(s),
    kill: () => {
      proc.killed = true;
    },
    onData: (fn) => (dataHandler = fn),
    onExit: (fn) => (exitHandler = fn),
    emit: (s) => dataHandler(s),
    exit: () => exitHandler(),
  };
  const module = {
    spawn: (file, args) => {
      proc.file = file;
      proc.args = args;
      return proc;
    },
  };
  return { proc, module };
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function testDrivesToPanel() {
  const spec = SPECS.codex;
  const { proc, module } = fakePty();

  const result = driveWindows({
    providerId: "codex",
    binaryPath: "C:\\fake\\codex",
    env: {},
    trackChild: (c) => c,
    ptyModule: module,
  });

  // Nothing typed before the ready marker shows up.
  await wait(300);
  assert.deepStrictEqual(proc.written, [], "typed before the prompt was ready");

  proc.emit("codex v1.0\r\n/model to change\r\n");
  // idleQuiet + the 300ms settle after the ready marker.
  await wait(spec.idleQuietMs + 600);
  assert.deepStrictEqual(proc.written, [spec.typedCommand], "did not type the command");

  // Enter follows a second later, not immediately.
  await wait(1200);
  assert.deepStrictEqual(
    proc.written,
    [spec.typedCommand, "\r"],
    "did not send Enter after the command"
  );

  // A quiet screen with no panel on it must NOT settle the capture — this is
  // the network round trip the wrappers' panelMarker rule exists for.
  await wait(spec.idleQuietMs + 500);
  assert.strictEqual(proc.killed, false, "settled before the panel rendered");

  proc.emit("Account: someone@example.com (Plus)\r\nWeekly limit: 12% left\r\n");
  const raw = await result;
  assert.ok(raw.includes("Account: someone@example.com"), "lost the captured panel");
  assert.ok(raw.includes("/model to change"), "lost the earlier screen content");
  assert.strictEqual(proc.killed, true, "left the PTY running");
  console.log("ok  drives a CLI to its quota panel");
}

async function testPanelFallback() {
  // With no panel marker ever arriving, the capture still has to end — on the
  // fallback timer — rather than hanging until the total timeout.
  const { proc, module } = fakePty();
  const started = Date.now();
  const result = driveWindows({
    providerId: "codex",
    binaryPath: "codex",
    env: {},
    trackChild: (c) => c,
    ptyModule: module,
  });
  proc.emit("/model to change\r\n");
  await wait(2500);
  proc.emit("signed out, please log in\r\n");
  const raw = await result;
  const elapsed = Date.now() - started;
  assert.ok(raw.includes("please log in"), "lost the logged-out screen");
  // It has to have actually waited out the fallback rather than settling on
  // the first quiet moment, and still have ended well before the total timeout.
  assert.ok(
    elapsed >= SPECS.codex.panelFallbackMs,
    `settled on quiet instead of the fallback timer (${elapsed}ms)`
  );
  assert.ok(
    elapsed < SPECS.codex.totalTimeoutMs,
    `fell through to the total timeout (${elapsed}ms)`
  );
  console.log("ok  falls back when the panel never renders");
}

async function testWizardNudgeIsAgyOnly() {
  // agy's first run blocks on an onboarding prompt that only Enter clears;
  // codex and cursor have no such screen and must never be sent stray Enters,
  // which would submit an empty prompt to the model.
  assert.ok(SPECS.antigravity.wizardNudgeMs > 0, "agy lost its onboarding nudge");
  assert.strictEqual(SPECS.codex.wizardNudgeMs, 0);
  assert.strictEqual(SPECS.cursor.wizardNudgeMs, 0);

  const { proc, module } = fakePty();
  driveWindows({
    providerId: "antigravity",
    binaryPath: "agy",
    env: {},
    trackChild: (c) => c,
    ptyModule: module,
  });
  // Stay silent past idleQuiet without ever showing the ready marker.
  await wait(SPECS.antigravity.idleQuietMs + 700);
  assert.deepStrictEqual(proc.written, ["\r"], "did not nudge through onboarding");
  proc.exit();
  console.log("ok  nudges only the provider with an onboarding screen");
}

function testSpecsMatchTheWrappers() {
  // These numbers are the contract the *-pty-wrapper.py scripts and
  // PTYSession.swift also encode; drifting on one platform is how the same CLI
  // starts reporting differently depending on where you run it.
  assert.deepStrictEqual(Object.keys(SPECS).sort(), ["antigravity", "codex", "cursor"]);
  assert.strictEqual(SPECS.antigravity.typedCommand, "/usage");
  assert.strictEqual(SPECS.antigravity.panelMarker, "GEMINI MODELS");
  assert.strictEqual(SPECS.codex.typedCommand, "/status");
  assert.strictEqual(SPECS.codex.panelMarker, "Account:");
  assert.strictEqual(SPECS.cursor.typedCommand, "/usage");
  assert.strictEqual(SPECS.cursor.panelMarker, "Esc to close");
  // cursor-agent refuses to start in a directory it hasn't been trusted for.
  assert.deepStrictEqual(SPECS.cursor.args, ["--trust"]);
  console.log("ok  specs match the POSIX wrappers");
}

function testResolveLaunchable() {
  // A path that already names an executable is left alone; ConPTY can't launch
  // the extensionless shell-script variant `where` hands back first.
  assert.strictEqual(resolveLaunchable("C:\\npm\\codex.cmd"), "C:\\npm\\codex.cmd");
  assert.strictEqual(resolveLaunchable("C:\\npm\\codex.EXE"), "C:\\npm\\codex.EXE");
  assert.strictEqual(resolveLaunchable("codex\r\n"), "codex");
  console.log("ok  resolves a launchable path");
}

async function testUnknownProvider() {
  assert.strictEqual(await driveWindows({ providerId: "nope", ptyModule: {} }), "");
  console.log("ok  unknown provider yields an empty capture");
}

(async () => {
  testSpecsMatchTheWrappers();
  testResolveLaunchable();
  await testUnknownProvider();
  await testDrivesToPanel();
  await testWizardNudgeIsAgyOnly();
  await testPanelFallback();
  console.log("\nall win-pty-driver tests passed");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
