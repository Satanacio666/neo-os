#!/usr/bin/env bash
# ==============================================================================
# scripts/self-host-test.sh — HolyC compiler self-hosting check
# ==============================================================================
#
# The ultimate compiler test: apps/Compiler.HC must compile ITSELF. It runs
# `hcrun Compiler.HC` over UART (which routes the file through CompilerCompileAndRun,
# i.e. Compiler.HC compiling Compiler.HC) and requires a result of 0.
#
# Exit 0 = PASS (self-hosting), 1 = FAIL.
# ==============================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${NEO_SERIAL_LOG:-/tmp/neo-os-serial.log}"

# The compiler is silent for the whole self-compile, which can exceed the shared
# driver's size-stability settle window; poll for the result marker explicitly so
# the check is deterministic instead of racing the UART idle heuristic.
out="$(python3 - "$ROOT" <<'PY'
import os, sys, time
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import neo_uart
start = neo_uart.log_size()
neo_uart.send("hcrun Compiler.HC\r")
deadline = time.time() + 120.0
while time.time() < deadline:
    out = neo_uart.read_from(start)
    if "[HCRUN] Compiler.HC ->" in out:
        sys.stdout.write(out)
        break
    time.sleep(0.1)
else:
    sys.stdout.write(neo_uart.read_from(start))
PY
)"
line="$(printf '%s\n' "$out" | grep -a '\[HCRUN\] Compiler.HC ->' | tail -1)"

if [ -z "$line" ]; then
    echo "SELF-HOST: FAIL — no result (compiler faulted or hung)"
    grep -aE "internal error|EXC #" "$LOG" 2>/dev/null | tail -2
    exit 1
fi

res="${line##*-> }"
res="${res%"${res##*[![:space:]]}"}"   # trim trailing whitespace
if [ "$res" = "0" ]; then
    echo "SELF-HOST: PASS — Compiler.HC compiled itself"
    exit 0
fi

echo "SELF-HOST: FAIL — $line"
exit 1
