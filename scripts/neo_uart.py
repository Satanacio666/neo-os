#!/usr/bin/env python3
"""Shared NeoOS UART driver: send lines to the guest and read framed output.

The guest prints a SENTINEL line (e.g. ``<<<NEO-DONE:selftest>>>``) when a
command finishes. ``run(cmd, sentinel=...)`` reads the serial log until the
sentinel appears, so callers no longer guess completion by watching log-size
stability (the old ``uart-repl.py`` heuristic). When no sentinel is given it
falls back to the size-stability wait.

  input  -> unix socket  /tmp/neo-os-uart-in.sock   (NEO_UART_IN_SOCK)
  output -> log file     /tmp/neo-os-serial.log     (NEO_SERIAL_LOG)

CLI:
  neo_uart.py '2 + 2;'                                  # one command, best-effort wait
  neo_uart.py --sentinel '<<<NEO-DONE:selftest>>>' 'selftest'
  neo_uart.py --timeout 90 --sentinel '...' 'selftest'
"""
import os
import socket
import sys
import time

IN_SOCK = os.environ.get("NEO_UART_IN_SOCK", "/tmp/neo-os-uart-in.sock")
LOG = os.environ.get("NEO_SERIAL_LOG", "/tmp/neo-os-serial.log")
WAIT = float(os.environ.get("NEO_WAIT", "1.5"))
SETTLE = float(os.environ.get("NEO_SETTLE", "0.4"))
PER_CHAR = float(os.environ.get("NEO_PER_CHAR", "0.005"))


def log_size():
    try:
        return os.path.getsize(LOG)
    except OSError:
        return 0


def read_from(offset):
    try:
        with open(LOG, "rb") as fh:
            fh.seek(offset)
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


def send(text, per_char=PER_CHAR):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(IN_SOCK)
    for ch in text:
        s.sendall(ch.encode())
        time.sleep(per_char)
    s.close()


def run(cmd, sentinel=None, wait=None, settle=None, timeout=None):
    """Send ``cmd`` (a CR is appended) and return the guest output delta.

    If ``sentinel`` is given, read until it appears (up to ``timeout`` seconds).
    Otherwise poll until the serial log stops growing for ``settle`` seconds.
    """
    start = log_size()
    send(cmd + "\r")
    if sentinel:
        deadline = time.time() + (timeout if timeout is not None else 120.0)
        while time.time() < deadline:
            out = read_from(start)
            if sentinel in out:
                return out
            time.sleep(0.05)
        return read_from(start)

    wait = WAIT if wait is None else wait
    settle = SETTLE if settle is None else settle
    deadline = time.time() + wait
    last_len = -1
    stable = time.time()
    while time.time() < deadline:
        time.sleep(0.1)
        cur = log_size()
        if cur != last_len:
            last_len = cur
            stable = time.time()
        elif time.time() - stable > settle:
            break
    return read_from(start)


def wait_for(marker, timeout=90.0, poll=1.0):
    """Block until ``marker`` appears anywhere in the serial log."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if marker in read_from(0):
            return True
        time.sleep(poll)
    return False


def main():
    args = sys.argv[1:]
    sentinel = None
    timeout = None
    cmds = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sentinel":
            i += 1
            sentinel = args[i]
        elif a == "--timeout":
            i += 1
            timeout = float(args[i])
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            cmds.append(a)
        i += 1

    if not cmds:
        print(__doc__)
        return 2

    rc = 0
    for cmd in cmds:
        print(f"\n>>> {cmd}", flush=True)
        out = run(cmd, sentinel=sentinel, timeout=timeout)
        sys.stdout.write(out if out.endswith("\n") else out + "\n")
        sys.stdout.flush()
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
