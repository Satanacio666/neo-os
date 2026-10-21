#!/usr/bin/env python3
"""Back-compat shim: send lines to the running NeoOS guest over UART.

Thin wrapper over ``scripts/neo_uart.py`` (the shared driver). Kept so existing
callers (run-jit-golden.py, self-host-test.sh, ...) keep working unchanged.

Usage:
  uart-repl.py "2 + 2;" "jittest"
  NEO_WAIT=3 uart-repl.py "bench"
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import neo_uart  # noqa: E402


def main():
    commands = sys.argv[1:]
    if not commands:
        print(__doc__)
        return 2
    for cmd in commands:
        print(f"\n>>> {cmd}", flush=True)
        out = neo_uart.run(cmd)
        sys.stdout.write(out if out.endswith("\n") else out + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
