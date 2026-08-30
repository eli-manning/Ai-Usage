#!/usr/bin/env python3
"""
Runs the Codex CLI (`codex`) in a PTY and drives it to the /status panel.
Usage: python3 codex-pty-wrapper.py <path-to-codex>

Like Antigravity's `agy` (see agy-pty-wrapper.py) and unlike Claude Code,
codex does not treat a slash command passed as an argv value as a command —
it starts an interactive session with that text as the first prompt. The
command only gets intercepted by codex's own input handling when typed live
into the running TUI, so this driver launches codex bare, waits for its
starting box to render, then types "/status" and Enter as if a user had.
"""
import os
import pty
import select
import sys
import time
import signal
import struct

try:
    import fcntl
    import termios
except ImportError:
    fcntl = None
    termios = None

READY_MARKER = b"to change"       # "/model to change" — the starting box
PANEL_READY_MARKER = b"Account:"   # only present once /status has rendered
IDLE_QUIET_S = 1.0
COMMAND_SETTLE_S = 0.8
PANEL_FALLBACK_TIMEOUT_S = 10.0
TOTAL_TIMEOUT_S = 20.0


class _Terminated(Exception):
    pass


def _handle_sigterm(signum, frame):
    raise _Terminated()


# A CLI that's authenticated and running its own background sync/refresh
# loop (observed with agy — see agy-pty-wrapper.py) may not exit reliably
# on SIGTERM. SIGKILL can't be caught/blocked/ignored, so escalate to it if
# SIGTERM hasn't reaped the process within a short grace period.
#
# The forked child called os.setsid() to become its own session/process-group
# leader, so any subprocess it spawns (a sandboxed helper, an MCP server,
# etc.) lands in that same group. Signaling just `pid` only ever killed the
# CLI's top-level process — any such subprocess survived it and was orphaned
# to init instead of being cleaned up. Use killpg to hit the whole group.
def _kill_and_reap(pid):
    # Once cleanup starts, a second external SIGTERM (e.g. main.js's
    # doneTimeout racing this function's own 2s grace period) must not be
    # allowed to raise _Terminated again here — that unwound this function
    # before reaching the SIGKILL escalation below, silently orphaning the
    # child. Ignore SIGTERM for the remainder of cleanup; SIGKILL still
    # applies below regardless.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    try:
        os.killpg(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.time() + 2.0
    while time.time() < deadline:
        try:
            if os.waitpid(pid, os.WNOHANG)[0] == pid:
                return
        except OSError:
            return
        time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except OSError:
        pass


def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    codex_path = sys.argv[1]
    # Node kills this wrapper with SIGTERM on a stall (see main.js's
    # doneTimeout). Python's default SIGTERM disposition terminates the
    # process immediately without running `finally` blocks, which orphaned
    # the forked codex child below instead of ever reaching the
    # os.kill(pid) cleanup — this handler turns SIGTERM into a normal
    # exception so the existing try/finally still runs.
    signal.signal(signal.SIGTERM, _handle_sigterm)

    master, slave = pty.openpty()
    if fcntl and termios:
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 200, 0, 0))
        except Exception:
            pass

    pid = os.fork()
    if pid == 0:
        # CHILD PROCESS
        os.close(master)
        os.setsid()
        try:
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        except Exception:
            pass
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
        os.chdir(os.path.expanduser("~"))
        os.execv(codex_path, [codex_path])
        os._exit(1)

    # PARENT PROCESS
    os.close(slave)
    buf = b""
    start = time.time()
    last_data = start
    ready_seen_at = None
    typed_command = False
    command_sent_at = None
    enter_after_command_at = None

    try:
        try:
            while True:
                now = time.time()
                if now - start > TOTAL_TIMEOUT_S:
                    break

                r, _, _ = select.select([master], [], [], 0.1)
                if r:
                    try:
                        data = os.read(master, 4096)
                        if not data:
                            break
                        buf += data
                        last_data = time.time()
                    except OSError:
                        break

                now = time.time()
                idle_for = now - last_data

                if ready_seen_at is None and READY_MARKER in buf:
                    ready_seen_at = now

                if (
                    ready_seen_at is not None
                    and not typed_command
                    and idle_for > IDLE_QUIET_S
                    and now - ready_seen_at > 0.2
                ):
                    try:
                        os.write(master, b"/status")
                        typed_command = True
                        command_sent_at = now
                        last_data = now
                    except OSError:
                        pass

                if (
                    typed_command
                    and enter_after_command_at is None
                    and now - command_sent_at > COMMAND_SETTLE_S
                ):
                    try:
                        os.write(master, b"\r")
                        enter_after_command_at = now
                    except OSError:
                        pass

                if enter_after_command_at is not None and idle_for > IDLE_QUIET_S:
                    if PANEL_READY_MARKER in buf or (now - enter_after_command_at) > PANEL_FALLBACK_TIMEOUT_S:
                        break

                if os.waitpid(pid, os.WNOHANG)[0] != 0:
                    break
        finally:
            try:
                os.close(master)
            except OSError:
                pass
            _kill_and_reap(pid)
    except _Terminated:
        pass

    sys.stdout.buffer.write(buf)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
