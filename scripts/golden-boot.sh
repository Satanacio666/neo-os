#!/usr/bin/env bash
# Golden boot regression gate for NeoOS.
#
# Boots once, asserts the boot-log invariants, then runs the ENTIRE regression
# battery with a SINGLE in-guest command (`selftest`, apps/SelfTest.HC) framed by
# a sentinel — no per-case UART round trips. Self-host stays a second command.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=/tmp/neo-os-serial.log
SHOT="${1:-/tmp/golden-boot.png}"
SENTINEL='<<<NEO-DONE:selftest>>>'

fail=0
check() { if [ "$2" = "$3" ]; then echo "  [PASS] $1 = $3"; else echo "  [FAIL] $1: expected $2 got $3"; fail=1; fi; }

echo "== rebuilding =="
( cd "$ROOT" && make all >/tmp/golden-boot-build.log 2>&1 ) || { echo "BUILD FAILED"; exit 2; }

echo "== booting =="
"$ROOT/scripts/run-viewer-vm.sh" restart >/dev/null 2>&1
for i in $(seq 1 40); do grep -q 'DolDocShell active' "$LOG" 2>/dev/null && break; sleep 1; done

count() { rg -c "$1" "$LOG" 2>/dev/null || echo 0; }
check "shell active"        1 "$(count 'DolDocShell active')"
check "all 32 subsystems"   1 "$(count 'ALL 32 HOLYC SUBSYSTEMS')"
check "exceptions"          0 "$(count 'Synchronous Exception')"
check "undefined identifiers" 0 "$(count 'undefined identifier')"
check "compiler internal errors" 0 "$(count 'COMPILER.HC\] internal error')"
check "C JIT errors"        0 "$(count '\[JIT\] Error')"
check "unresolved forward refs" 0 "$(count 'unresolved reference')"

echo "== in-guest SELFTEST (one command, apps/SelfTest.HC) =="
out="$(python3 "$ROOT/scripts/neo_uart.py" --sentinel "$SENTINEL" --timeout 120 'selftest' 2>/dev/null || true)"
if ! printf '%s' "$out" | grep -aq "$SENTINEL"; then
    echo "  [FAIL] selftest did not finish (no sentinel — fault or hang)"
    grep -aE "internal error|EXC #" "$LOG" 2>/dev/null | tail -2
    fail=1
else
    line="$(printf '%s\n' "$out" | grep -a 'SELFTEST: ' | tail -1)"
    res="${line##*SELFTEST: }"; res="${res%% *}"       # "74/74"
    a="${res%%/*}"; b="${res##*/}"
    if [ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" -ge 74 ] 2>/dev/null; then
        echo "  [PASS] SELFTEST = $res"
    else
        echo "  [FAIL] SELFTEST = ${res:-<none>} (want a==b and a>=74)"
        printf '%s\n' "$out" | grep -a '\[SELFTEST\] FAIL' | head -5
        fail=1
    fi
    pline="$(printf '%s\n' "$out" | grep -a 'engine parity:' | tail -1)"
    if printf '%s' "$pline" | grep -aq '0 diff'; then
        echo "  [PASS] $pline"
    else
        echo "  [FAIL] parity: ${pline:-<none>} (want 0 diff)"
        fail=1
    fi
    tline="$(printf '%s\n' "$out" | grep -a 'TWINS: ' | tail -1)"
    if printf '%s' "$tline" | grep -aq '5/5'; then
        echo "  [PASS] $tline (twin-liveness)"
    else
        echo "  [FAIL] twin-liveness: ${tline:-<none>} (want 5/5)"
        fail=1
    fi
fi

echo "== compiler self-host =="
"$ROOT/scripts/self-host-test.sh" || fail=1

echo "== screenshot =="
curl -sN --max-time 12 http://localhost:4000/api/neo-os/stream 2>/dev/null | python3 -c "
import sys,json,base64
for line in sys.stdin:
    if line.startswith('data: '):
        o=json.loads(line[6:]); open('$SHOT','wb').write(base64.b64decode(o['png']))
        print('  saved', o['width'],'x',o['height'],'->','$SHOT'); break
" || fail=1

echo
if [ $fail -eq 0 ]; then echo "GOLDEN BOOT: PASS"; else echo "GOLDEN BOOT: FAIL"; fi
exit $fail
