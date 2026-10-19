#!/usr/bin/env bash
# Golden boot regression gate for NeoOS.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=/tmp/neo-os-serial.log
SHOT="${1:-/tmp/golden-boot.png}"

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

echo "== golden JIT battery =="
python3 "$ROOT/scripts/run-jit-golden.py" 2>&1 | tail -1 || fail=1

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
