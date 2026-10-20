#!/usr/bin/env bash
# ==============================================================================
# scripts/p1-flip-test.sh — P1 self-hosting flip smoke / hang detector (Agent B)
# ==============================================================================
#
# WHAT IT DOES
#   1. Applies the P1 self-hosting flip to apps/KernelInit.HC (the 3-line change
#      from docs/master/P1-DELEGATION.md §9: route every module after Compiler.HC
#      through CompilerCompileAndRun).
#   2. Rebuilds (`make all`) and boots the viewer VM.
#   3. Watches /tmp/neo-os-serial.log for `[KERNEL-INIT] Compiling <module>` lines.
#   4. Declares a HANG when the serial log stops growing for HANG_SECONDS.
#      On a hang it reports the last module that started compiling, the tail of
#      the serial log, and runs scripts/crash-decode.py for the fault/disasm.
#   5. Always reverts apps/KernelInit.HC to its pre-run contents (trap), so the
#      tree is never left red.
#
# USAGE
#   scripts/p1-flip-test.sh                 # full flip, all modules
#   HANG_SECONDS=60 scripts/p1-flip-test.sh # slower host / longer compile
#   FORCE=1 scripts/p1-flip-test.sh         # allow running with dirty KernelInit.HC
#   NO_REBUILD=1 scripts/p1-flip-test.sh    # restore source only (skip final make)
#
# ENV
#   HANG_SECONDS  seconds of no new serial bytes before declaring a hang (45)
#   BOOT_TIMEOUT  hard ceiling for the whole boot (600)
#   POLL          serial poll interval seconds (1)
#   FORCE         1 = do not refuse when KernelInit.HC has uncommitted edits
#   NO_REBUILD    1 = do not `make all` after reverting the flip
#
# LOCKING
#   The VM, build dir and git index are singletons. This script takes the shared
#   lock /tmp/neo-os-vm.lock for its entire lifetime (flock fd 9). Do NOT run it
#   concurrently with golden-boot.sh, Agent A's builds, or a manual VM.
#
# EXIT CODES
#   0 flip ON booted clean (all modules compiled, shell active)
#   1 hang or crash detected (details printed; flip already reverted)
#   2 build failure
#   3 could not acquire the shared lock
#   4 refusing to run (KernelInit.HC dirty and FORCE != 1)
# ==============================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KI="$ROOT/apps/KernelInit.HC"
LOG="${NEO_SERIAL_LOG:-/tmp/neo-os-serial.log}"
LOCK=/tmp/neo-os-vm.lock
HANG_SECONDS="${HANG_SECONDS:-45}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"
POLL="${POLL:-1}"

log() { printf '%s\n' "$*"; }

# --- shared singleton lock for the whole script lifetime ---------------------
exec 9>"$LOCK"
if ! flock -w 900 9; then
    echo "p1-flip-test: could not acquire $LOCK (another agent holds the VM)" >&2
    exit 3
fi

if [ ! -f "$KI" ]; then
    echo "p1-flip-test: $KI not found" >&2
    exit 4
fi

# --- refuse to clobber concurrent Agent A edits ------------------------------
if [ -n "$(git -C "$ROOT" diff --name-only -- apps/KernelInit.HC 2>/dev/null)" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "p1-flip-test: apps/KernelInit.HC has uncommitted changes." >&2
    echo "  Commit/stash them first, or re-run with FORCE=1 to overwrite." >&2
    exit 4
fi

BACKUP="$(mktemp /tmp/neo-os-kinit.XXXXXX.HC)"
cp "$KI" "$BACKUP"
RESTORED=0

restore() {
    [ "$RESTORED" = "1" ] && return
    RESTORED=1
    cp "$BACKUP" "$KI" && rm -f "$BACKUP"
    log "[p1-flip-test] reverted apps/KernelInit.HC to pre-run contents"
    if [ "${NO_REBUILD:-0}" != "1" ]; then
        log "[p1-flip-test] rebuilding reverted image (make all)..."
        ( cd "$ROOT" && make all >/tmp/p1-flip-rebuild.log 2>&1 ) \
            && log "[p1-flip-test] rebuild OK" \
            || log "[p1-flip-test] WARNING: rebuild failed; see /tmp/p1-flip-rebuild.log"
    fi
}
trap restore EXIT INT TERM

# --- apply the flip ----------------------------------------------------------
python3 - "$KI" <<'PY'
import sys
p = sys.argv[1]
src = open(p).read()

old_call = "        I64 res = jit_compile_and_run(kinit_load_buf);"
new_call = ("        I64 res;\n"
            "        if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }")
if old_call not in src:
    sys.exit("flip: could not find the jit_compile_and_run call site (already flipped?)")
src = src.replace(old_call, new_call, 1)

anchor = '    KInitLoad("Compiler.HC");'
if anchor not in src:
    sys.exit("flip: could not find KInitLoad(\"Compiler.HC\"); anchor")
src = src.replace(anchor, anchor + "\n    g_hc_ready = 1;", 1)

open(p, "w").write(src)
print("flip applied")
PY
if [ $? -ne 0 ]; then echo "p1-flip-test: flip patch failed" >&2; exit 2; fi

# --- build + boot ------------------------------------------------------------
log "[p1-flip-test] building (make all)..."
if ! ( cd "$ROOT" && make all >/tmp/p1-flip-build.log 2>&1 ); then
    echo "p1-flip-test: BUILD FAILED; see /tmp/p1-flip-build.log" >&2
    exit 2
fi

log "[p1-flip-test] booting with flip ON (hang threshold ${HANG_SECONDS}s)..."
"$ROOT/scripts/run-viewer-vm.sh" restart >/dev/null 2>&1

# --- monitor serial log ------------------------------------------------------
size_of() { stat -c %s "$LOG" 2>/dev/null || echo 0; }
read_from() { python3 -c "import sys; f=open('$LOG','rb'); f.seek($1); sys.stdout.write(f.read().decode('utf-8','replace'))" 2>/dev/null; }

start=$(date +%s)
last_size=$(size_of)
last_change=$(date +%s)
cursor=0
last_module=""
compiled_last=""
verdict="timeout"
reason=""

while :; do
    now=$(date +%s)
    cur=$(size_of)

    if [ "$cur" -gt "$cursor" ]; then
        chunk="$(read_from "$cursor")"
        cursor="$cur"
        # last `Compiling X.HC` seen
        m=$(printf '%s\n' "$chunk" | sed -n 's/.*\[KERNEL-INIT\] Compiling \([^ ]*\) .*/\1/p' | tail -1)
        [ -n "$m" ] && last_module="$m"
        c=$(printf '%s\n' "$chunk" | sed -n 's/.*\[KERNEL-INIT\] \([^ ]*\) compiled, res = \(.*\)/\1/p' | tail -1)
        [ -n "$c" ] && compiled_last="$c"
        last_change="$now"
    fi

    if [ "$cur" -ne "$last_size" ]; then last_size="$cur"; last_change="$now"; fi

    if grep -q 'DolDocShell active' "$LOG" 2>/dev/null; then
        verdict="clean"; reason="DolDocShell active"; break
    fi
    if grep -q 'ALL 32 HOLYC SUBSYSTEMS' "$LOG" 2>/dev/null; then
        verdict="clean"; reason="all modules compiled"; break
    fi
    if grep -q 'Synchronous Exception' "$LOG" 2>/dev/null; then
        verdict="crash"; reason="Synchronous Exception"; break
    fi

    if [ $((now - last_change)) -ge "$HANG_SECONDS" ] && [ "$now" -gt "$start" ]; then
        verdict="hang"; reason="no serial output for ${HANG_SECONDS}s"; break
    fi
    if [ $((now - start)) -ge "$BOOT_TIMEOUT" ]; then
        verdict="timeout"; reason="boot exceeded ${BOOT_TIMEOUT}s"; break
    fi
    sleep "$POLL"
done

# --- report ------------------------------------------------------------------
echo
log "================ P1 FLIP TEST REPORT ================"
log "verdict        : $verdict ($reason)"
log "last module    : ${last_module:-<none>}"
log "last completed : ${compiled_last:-<none>}"
if [ "$verdict" = "hang" ]; then
    log "--> HANG: Compiler.HC stopped advancing while compiling '${last_module:-?}'."
    log "    Reproduce per docs/master/P1-DELEGATION.md §5 (bisect the source, instrument"
    log "    HcLexNext/HcParseStatement; find the token where g_hc_pos stops advancing)."
fi
log "-----------------------------------------------------"
log "serial tail ($LOG):"
tail -n 40 "$LOG" 2>/dev/null || true
log "-----------------------------------------------------"
log "crash decode:"
python3 "$ROOT/scripts/crash-decode.py" 2>&1 || true
log "====================================================="

restore
[ "$verdict" = "clean" ] && exit 0 || exit 1
