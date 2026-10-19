#!/usr/bin/env python3
"""Send lines to the running NeoOS guest over UART and print the resulting output.

  input  -> unix socket  /tmp/neo-os-uart-in.sock   (NEO_UART_IN_SOCK)
  output -> log file     /tmp/neo-os-serial.log     (NEO_SERIAL_LOG)

Usage:
  uart-repl.py "2 + 2;" "jittest"
  NEO_WAIT=3 uart-repl.py "bench"
"""
import os
import socket
import sys
import time

IN_SOCK = os.environ.get("NEO_UART_IN_SOCK", "/tmp/neo-os-uart-in.sock")
LOG = os.environ.get("NEO_SERIAL_LOG", "/tmp/neo-os-serial.log")
WAIT = float(os.environ.get("NEO_WAIT", "1.5"))
SETTLE = float(os.environ.get("NEO_SETTLE", "0.4"))


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


def send(text):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(IN_SOCK)
    for ch in text:
        s.sendall(ch.encode())
        time.sleep(0.005)
    s.close()


def main():
    commands = sys.argv[1:]
    if not commands:
        print(__doc__)
        return 2
    for cmd in commands:
        start = log_size()
        print(f"\n>>> {cmd}", flush=True)
        send(cmd + "\r")
        deadline = time.time() + WAIT
        last_len = -1
        stable = time.time()
        while time.time() < deadline:
            time.sleep(0.1)
            cur = log_size()
            if cur != last_len:
                last_len = cur
                stable = time.time()
            elif time.time() - stable > SETTLE:
                break
        out = read_from(start)
        sys.stdout.write(out if out.endswith("\n") else out + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
