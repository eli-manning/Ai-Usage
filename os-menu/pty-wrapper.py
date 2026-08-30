#!/usr/bin/env python3
"""
Runs Claude Code in a PTY with a slash command passed as an argument.
Captures the output and exits once the screen has settled.
Usage: python3 pty-wrapper.py <path-to-claude> [command]
  command defaults to /usage; also used for /stats.
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

IDLE_QUIET_S = 0.8  # no new bytes for this long => screen considered settled
MIN_ELAPSED_S = 1.0  # ignore idle detection until at least this much has elapsed (startup animation)
# claude writes a small fixed terminal-setup preamble (mode-set escapes, a
# device-attributes query, ~60-90 bytes) before it ever draws its first real
# frame. Observed in the wild: claude occasionally pauses noticeably longer
# than IDLE_QUIET_S between that preamble and its first frame (system load,
# a slow terminfo/capability round-trip) — with no byte-count floor, idle
# detection reads that pause as "screen settled" and kills the process right
# there, producing an output that's nothing but the preamble. Reproduced
# directly (bypassing this wrapper, in a plain fork/exec harness): given a
# longer leash instead of an early idle-triggered kill, every one of these
# runs went on to render normally within ~2s — so the fix is to not let idle
# detection conclude "done" until real content (not just the preamble) has
# actually arrived. The hard `timeout` cap below still applies regardless,
# so a genuinely hung claude is still bounded.
MIN_BYTES_FOR_IDLE_DONE = 300


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

    claude_path = sys.argv[1]
    command = sys.argv[2] if len(sys.argv) > 2 else "/usage"
    # Node kills this wrapper with SIGTERM on a stall (see main.js's
    # doneTimeout). Python's default SIGTERM disposition terminates the
    # process immediately without running `finally` blocks, which orphaned
    # the forked claude child below instead of ever reaching the
    # os.kill(pid) cleanup — this handler turns SIGTERM into a normal
    # exception so the existing try/finally still runs.
    signal.signal(signal.SIGTERM, _handle_sigterm)

    master, slave = pty.openpty()

    # Default PTY size (24x80) truncates content past row 24 — /stats runs
    # past that. Grow it so the TUI renders everything in one frame.
    if fcntl and termios:
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 60, 200, 0, 0))
        except Exception:
            pass

    pid = os.fork()
    if pid == 0:
        # CHILD PROCESS
        os.close(master)
        os.setsid()

        # Standard PTY setup
        try:
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        except Exception:
            pass

        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)

        if slave > 2:
            os.close(slave)

        # Run from home dir so Claude saves its trust decision to ~/.claude/
        os.chdir(os.path.expanduser('~'))

        os.execv(claude_path, [claude_path, command])
        os._exit(1)

    # PARENT PROCESS
    os.close(slave)
    buf = b''
    start_time = time.time()
    last_data_time = start_time
    # Was 14s — a slow cold start (network round-trip, a busy machine) could
    # get cut off mid-render before /usage's output ever settled, producing a
    # spurious "Could not find usage data" that only went away if the user
    # mashed Refresh until one attempt got lucky. main.js now also retries
    # once automatically on error, but raising this cap reduces how often
    # that retry is even needed. Must stay under main.js's own doneTimeout
    # (23s) so this wrapper's own graceful idle/timeout path — which parses
    # whatever was captured — gets to run instead of being SIGTERM'd first.
    timeout = 20  # Maximum seconds to wait
    trust_answered = False

    try:
        try:
            while True:
                now = time.time()
                if (now - start_time) > timeout:
                    break

                r, _, _ = select.select([master], [], [], 0.1)
                if r:
                    try:
                        data = os.read(master, 4096)
                        if not data:
                            break

                        buf += data
                        last_data_time = time.time()
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()

                        # Auto-answer Claude's directory trust prompt
                        # "safety check" has ANSI sequences between words so match on "safety" alone
                        if not trust_answered and b'safety' in buf.lower():
                            trust_answered = True
                            time.sleep(0.1)
                            try:
                                os.write(master, b'\r')
                            except OSError:
                                pass
                            last_data_time = time.time()  # don't treat the trust prompt as "settled"
                    except OSError:
                        break

                # Once the screen stops changing, give it a moment more (in case a
                # trust prompt was just accepted) then stop.
                now = time.time()
                idle_for = now - last_data_time
                elapsed = now - start_time
                if elapsed > MIN_ELAPSED_S and idle_for > IDLE_QUIET_S and len(buf) > MIN_BYTES_FOR_IDLE_DONE:
                    break

                # If the child process has already exited, stop reading
                if os.waitpid(pid, os.WNOHANG)[0] != 0:
                    break

        finally:
            # Cleanup
            try:
                os.close(master)
            except OSError:
                pass

            # Ensure the Claude process is killed
            _kill_and_reap(pid)
    except _Terminated:
        pass


if __name__ == "__main__":
    main()
