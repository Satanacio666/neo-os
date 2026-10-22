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
# RASTER: is printed by RasterTile.HC's boot self-check (Stage 5), i.e. in $LOG.
raline="$(grep -a 'RASTER: ' "$LOG" 2>/dev/null | tail -1)"
if printf '%s' "$raline" | grep -aq 'PASS'; then
    echo "  [PASS] $raline (single rasterizer boot check)"
else
    echo "  [FAIL] rasterizer: ${raline:-<none>} (want RASTER: PASS)"
    fail=1
fi

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
    sline="$(printf '%s\n' "$out" | grep -a 'SYMS: ' | tail -1)"
    if printf '%s' "$sline" | grep -aq '0 unresolved'; then
        echo "  [PASS] $sline"
    else
        echo "  [FAIL] symbol audit: ${sline:-<none>} (want 0 unresolved)"
        fail=1
    fi
    hline="$(printf '%s\n' "$out" | grep -a 'HALCACHE: ' | tail -1)"
    if printf '%s' "$hline" | grep -aq 'PASS'; then
        echo "  [PASS] $hline (HalFlushCache coherency)"
    else
        echo "  [FAIL] hal-cache: ${hline:-<none>} (want PASS)"
        fail=1
    fi
    fline="$(printf '%s\n' "$out" | grep -a 'FSRT: ' | tail -1)"
    if printf '%s' "$fline" | grep -aq 'PASS'; then
        echo "  [PASS] $fline (RedSea.HC round-trip)"
    else
        echo "  [FAIL] fs round-trip: ${fline:-<none>} (want PASS)"
        fail=1
    fi
    kline="$(printf '%s\n' "$out" | grep -a 'KERNEL: ' | tail -1)"
    if printf '%s' "$kline" | grep -aq 'KERNEL:'; then
        echo "  [PASS] $kline"
    else
        echo "  [FAIL] kernel report: ${kline:-<none>} (want KERNEL: line)"
        fail=1
    fi
    tkline="$(printf '%s\n' "$out" | grep -a 'TICK: ' | tail -1)"
    if printf '%s' "$tkline" | grep -aq 'PASS'; then
        echo "  [PASS] $tkline (hardware timer IRQ)"
    else
        echo "  [FAIL] timer tick: ${tkline:-<none>} (want TICK: PASS)"
        fail=1
    fi
    scline="$(printf '%s\n' "$out" | grep -a 'SCHED: ' | tail -1)"
    if printf '%s' "$scline" | grep -aq 'PASS'; then
        echo "  [PASS] $scline (preemptive scheduling)"
    else
        echo "  [FAIL] preemption: ${scline:-<none>} (want SCHED: PASS)"
        fail=1
    fi
    bline="$(printf '%s\n' "$out" | grep -a 'BSOD: ' | tail -1)"
    if printf '%s' "$bline" | grep -aq 'PASS'; then
        echo "  [PASS] $bline (kernel-fault vs REPL boundary)"
    else
        echo "  [FAIL] bsod boundary: ${bline:-<none>} (want BSOD: PASS)"
        fail=1
    fi
    mline="$(printf '%s\n' "$out" | grep -a 'SMP: ' | tail -1)"
    if printf '%s' "$mline" | grep -aq 'PASS'; then
        echo "  [PASS] $mline (secondary-core dispatch)"
    else
        echo "  [FAIL] smp dispatch: ${mline:-<none>} (want SMP: PASS)"
        fail=1
    fi
    ovline="$(printf '%s\n' "$out" | grep -a 'SOVEREIGN: ' | tail -1)"
    if printf '%s' "$ovline" | grep -aq 'PASS'; then
        echo "  [PASS] $ovline (.HC owns kmalloc/kfree/symbols_*)"
    else
        echo "  [FAIL] sovereign handover: ${ovline:-<none>} (want SOVEREIGN: PASS)"
        fail=1
    fi
    rdline="$(printf '%s\n' "$out" | grep -a 'RENDER: ' | tail -1)"
    if printf '%s' "$rdline" | grep -aq 'PASS'; then
        echo "  [PASS] $rdline (golden-frame hash)"
    else
        echo "  [FAIL] render golden-frame: ${rdline:-<none>} (want RENDER: PASS)"
        fail=1
    fi
    psline="$(printf '%s\n' "$out" | grep -a 'PTRSCALE: ' | tail -1)"
    if printf '%s' "$psline" | grep -aq 'PASS'; then
        echo "  [PASS] $psline (global-pointer element width)"
    else
        echo "  [FAIL] pointer element width: ${psline:-<none>} (want PTRSCALE: PASS)"
        fail=1
    fi
    a2line="$(printf '%s\n' "$out" | grep -a 'ARRAY2D: ' | tail -1)"
    if printf '%s' "$a2line" | grep -aq 'PASS'; then
        echo "  [PASS] $a2line (multidimensional array indexing)"
    else
        echo "  [FAIL] 2D array indexing: ${a2line:-<none>} (want ARRAY2D: PASS)"
        fail=1
    fi
    hcline="$(printf '%s\n' "$out" | grep -a 'KHEAP: ' | tail -1)"
    if printf '%s' "$hcline" | grep -aq 'PASS'; then
        echo "  [PASS] $hcline (heap: split/coalesce, no overlap)"
    else
        echo "  [FAIL] heap stress: ${hcline:-<none>} (want KHEAP: PASS)"
        fail=1
    fi
fi

echo "== .HC -> C runtime census =="
"$ROOT/scripts/census-c-runtime.sh" | tail -1 || fail=1

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
