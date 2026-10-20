#!/usr/bin/env bash
# ==============================================================================
# scripts/p1-parity.sh — P1 compile-parity harness (Agent B)
# ==============================================================================
#
# Backs P1 Definition-of-Done item #5 (docs/master/P1-DELEGATION.md §0):
#   "scripts/compile-parity.sh shows both engines agree (same module set compiled,
#    same key globals) for all 34 modules."
#
# WHAT IT DOES
#   * Boots the OS with the self-hosting flip OFF (C JIT, the golden reference)
#     and captures the serial log + the values of KEY_GLOBALS probed over UART.
#   * Boots with the flip ON (all post-Compiler.HC modules through
#     CompilerCompileAndRun) and captures the same.
#   * Optionally (`--per-module`) also boots once per module, flipping ONLY that
#     module through Compiler.HC, to isolate the first module that diverges.
#   * Diffs the set of modules compiled, the per-module compile result, the
#     undefined-identifier / late-bound / unresolved-forward-reference reports,
#     and the key globals; prints a per-module PASS/FAIL table.
#
# USAGE
#   scripts/p1-parity.sh                     # baseline (off) + full flip (on)
#   scripts/p1-parity.sh --per-module        # + one isolated boot per module
#   scripts/p1-parity.sh --module Math3D.HC  # single focused module parity
#   NO_BUILD=1 scripts/p1-parity.sh          # reuse current build/ (skip make)
#   HANG_SECONDS=90 scripts/p1-parity.sh     # slower host
#
# ENV
#   HANG_SECONDS   serial-silence hang threshold per boot (45)
#   BOOT_TIMEOUT   hard ceiling per boot (600)
#   POLL           serial poll interval seconds (1)
#   NO_BUILD       1 = do not run `make all` before each boot
#   PARITY_OUT     output dir (default /tmp/p1-parity)
#   FORCE          1 = allow running with a dirty apps/KernelInit.HC
#
# LOCKING
#   Takes the shared singleton lock /tmp/neo-os-vm.lock for its whole lifetime
#   (flock fd 9). The VM, build dir and git index are singletons — do not run
#   concurrently with Agent A or golden-boot.sh.
#
# EXIT CODES
#   0 both engines agree for every module and key global
#   1 one or more module/global divergences (table printed)
#   2 build failure
#   3 could not acquire the shared lock
#   4 refusing to run (KernelInit.HC dirty and FORCE != 1)
# ==============================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KI="$ROOT/apps/KernelInit.HC"
SERLOG=/tmp/neo-os-serial.log
LOCK=/tmp/neo-os-vm.lock
HANG_SECONDS="${HANG_SECONDS:-45}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"
POLL="${POLL:-1}"
OUT="${PARITY_OUT:-/tmp/p1-parity}"

PER_MODULE=0
ONLY_MODULE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --per-module) PER_MODULE=1 ;;
        --module) shift; ONLY_MODULE="${1:-}" ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$OUT"

# --- shared singleton lock ---------------------------------------------------
exec 9>"$LOCK"
if ! flock -w 900 9; then
    echo "p1-parity: could not acquire $LOCK (another agent holds the VM)" >&2
    exit 3
fi

# --- module compile order straight from the real boot script -----------------
mapfile -t MODULES < <(sed -n 's/.*KInitLoad("\([^"]*\)").*/\1/p' "$KI")
if [ "${#MODULES[@]}" -eq 0 ]; then
    echo "p1-parity: could not parse module order from $KI" >&2
    exit 4
fi

# --- key globals probed over the UART REPL after a clean boot ----------------
KEY_GLOBALS=(
    "g_canv.width"
    "g_canv.height"
    "g_canv.pitch"
    "g_gfx.mode"
    "g_vgpu.active"
    "g_vgpu.width"
    "g_theme.theme_id"
    "g_wm.count"
    "g_wm.screen_w"
    "g_comp.tiles_x"
    "g_font_metrics.char_width"
    "g_hgl_zbuf_w"
    "g_shell_cmd_count"
    "g_mono_glyphs[0]"
    "doldoc_get_widget_count()"
)

# --- safety + backup ---------------------------------------------------------
if [ -n "$(git -C "$ROOT" diff --name-only -- apps/KernelInit.HC 2>/dev/null)" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "p1-parity: apps/KernelInit.HC has uncommitted changes (FORCE=1 to override)" >&2
    exit 4
fi
BACKUP="$(mktemp /tmp/neo-os-kinit.XXXXXX.HC)"
cp "$KI" "$BACKUP"
RESTORED=0
restore() {
    [ "$RESTORED" = "1" ] && return
    RESTORED=1
    cp "$BACKUP" "$KI" && rm -f "$BACKUP"
    echo "[p1-parity] reverted apps/KernelInit.HC"
}
trap restore EXIT INT TERM

# --- flip patcher ------------------------------------------------------------
apply_variant() {  # $1 = off | full | module:NAME
    cp "$BACKUP" "$KI"
    [ "$1" = "off" ] && return 0
    python3 - "$KI" "$1" <<'PY'
import sys
p, variant = sys.argv[1], sys.argv[2]
src = open(p).read()

old = "        I64 res = jit_compile_and_run(kinit_load_buf);"
new = ("        I64 res;\n"
       "        if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }")
if old not in src:
    sys.exit("parity: call site not found (already flipped?)")
src = src.replace(old, new, 1)

if variant == "full":
    anchor = '    KInitLoad("Compiler.HC");'
    if anchor not in src:
        sys.exit("parity: Compiler.HC anchor not found")
    src = src.replace(anchor, anchor + "\n    g_hc_ready = 1;", 1)
elif variant.startswith("module:"):
    name = variant[len("module:"):]
    anchor = '    KInitLoad("%s");' % name
    if anchor not in src:
        sys.exit("parity: module anchor not found: %s" % name)
    src = src.replace(anchor, "    g_hc_ready = 1;\n" + anchor + "\n    g_hc_ready = 0;", 1)
else:
    sys.exit("parity: unknown variant %s" % variant)

open(p, "w").write(src)
PY
}

# --- build + boot + monitor one variant, capture log -------------------------
# echoes the verdict: clean | hang | crash | timeout | build-fail
boot_variant() {  # $1 = tag
    local tag="$1"
    if [ "${NO_BUILD:-0}" != "1" ]; then
        if ! ( cd "$ROOT" && make all >"$OUT/$tag.build.log" 2>&1 ); then
            echo "build-fail"; return
        fi
    fi
    : > "$SERLOG"
    "$ROOT/scripts/run-viewer-vm.sh" restart >/dev/null 2>&1

    local start last_change now cur cursor=0
    start=$(date +%s); last_change=$start
    while :; do
        now=$(date +%s); cur=$(stat -c %s "$SERLOG" 2>/dev/null || echo 0)
        [ "$cur" -gt "$cursor" ] && { cursor=$cur; last_change=$now; }
        if grep -q 'DolDocShell active' "$SERLOG" 2>/dev/null; then echo "clean"; break; fi
        if grep -q 'ALL 32 HOLYC SUBSYSTEMS' "$SERLOG" 2>/dev/null; then echo "clean"; break; fi
        if grep -q 'Synchronous Exception' "$SERLOG" 2>/dev/null; then echo "crash"; break; fi
        if [ $((now - last_change)) -ge "$HANG_SECONDS" ]; then echo "hang"; break; fi
        if [ $((now - start)) -ge "$BOOT_TIMEOUT" ]; then echo "timeout"; break; fi
        sleep "$POLL"
    done
}

# --- probe KEY_GLOBALS over UART, write TSV ----------------------------------
probe_globals() {  # $1 = tag
    local tag="$1" g out hex
    : > "$OUT/$tag.globals"
    for g in "${KEY_GLOBALS[@]}"; do
        out="$(python3 "$ROOT/scripts/uart-repl.py" "$g;" 2>/dev/null || true)"
        hex="$(printf '%s\n' "$out" | sed -n 's/.*-->.*(0x\([0-9A-Fa-f]*\)).*/\1/p' | tail -1)"
        printf '%s\t%s\n' "$g" "${hex:-N/A}" >> "$OUT/$tag.globals"
    done
}

run_one() {  # $1 = tag  $2 = variant
    local tag="$1" variant="$2" verdict
    echo "[p1-parity] variant '$variant' -> tag '$tag'"
    apply_variant "$variant" || { echo "patch failed"; exit 4; }
    verdict="$(boot_variant "$tag")"
    cp "$SERLOG" "$OUT/$tag.log" 2>/dev/null || : > "$OUT/$tag.log"
    echo "[p1-parity]   verdict: $verdict"
    if [ "$verdict" = "clean" ]; then
        probe_globals "$tag"
    else
        : > "$OUT/$tag.globals"
    fi
    printf '%s\n' "$verdict" > "$OUT/$tag.verdict"
}

# --- run the variants --------------------------------------------------------
run_one off  off
if [ -n "$ONLY_MODULE" ]; then
    run_one "on_${ONLY_MODULE%.HC}" "module:$ONLY_MODULE"
    ON_TAG="on_${ONLY_MODULE%.HC}"
elif [ "$PER_MODULE" = "1" ]; then
    run_one full full
    ON_TAG=full
    for m in "${MODULES[@]}"; do
        [ "$m" = "Compiler.HC" ] && continue
        run_one "mod_${m%.HC}" "module:$m"
    done
else
    run_one full full
    ON_TAG=full
fi
restore

# --- diff + per-module PASS/FAIL table ---------------------------------------
python3 - "$OUT" "$ON_TAG" "${MODULES[@]}" <<'PY'
import os, re, sys

out, on_tag = sys.argv[1], sys.argv[2]
modules = sys.argv[3:]

def read(p):
    try:
        return open(p, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""

def res_map(log):
    """module -> 'HANG' | int(res) | 'ABSENT'."""
    m = {}
    started, done = [], set()
    for line in log.splitlines():
        mm = re.search(r"\[KERNEL-INIT\] Compiling (\S+) ", line)
        if mm:
            started.append(mm.group(1))
        rm = re.search(r"\[KERNEL-INIT\] (\S+) compiled, res = (-?\d+)", line)
        if rm:
            m[rm.group(1)] = int(rm.group(2))
            done.add(rm.group(1))
    # any module that started compiling but never finished, and is the last
    # started one, is the hang site.
    for s in started:
        if s not in done:
            m[s] = "HANG"
    return m

def names(log, pat):
    return sorted(set(re.findall(pat, log, re.MULTILINE)))

off_log = read(os.path.join(out, "off.log"))
on_log = read(os.path.join(out, f"{on_tag}.log"))
off_res = res_map(off_log)
on_res = res_map(on_log)

def gmap(tag):
    d = {}
    for line in read(os.path.join(out, f"{tag}.globals")).splitlines():
        if "\t" in line:
            k, v = line.split("\t", 1)
            d[k] = v
    return d

off_g = gmap("off")
on_g = gmap(on_tag)

print()
print("==================== P1 ENGINE PARITY ====================")
print(f"baseline (C JIT) : {out}/off.log  [{read(os.path.join(out,'off.verdict')).strip()}]")
print(f"flip ON          : {out}/{on_tag}.log  [{read(os.path.join(out,on_tag+'.verdict')).strip()}]")
print()
print(f"{'MODULE':<24}{'C-JIT':<12}{'COMPILER.HC':<14}VERDICT")
print("-" * 60)
fails = 0
for mod in modules:
    a = off_res.get(mod, "ABSENT")
    b = on_res.get(mod, "ABSENT")
    if b == "HANG":
        v = "FAIL(hang)"
    elif a == "ABSENT" and b == "ABSENT":
        v = "SKIP"
    elif a == "ABSENT" or b == "ABSENT":
        v = "FAIL(missing)"
    elif a == b:
        v = "PASS"
    else:
        v = "FAIL(res)"
    if v.startswith("FAIL"):
        fails += 1
    sa = "HANG" if a == "HANG" else (str(a) if a != "ABSENT" else "-")
    sb = "HANG" if b == "HANG" else (str(b) if b != "ABSENT" else "-")
    print(f"{mod:<24}{sa:<12}{sb:<14}{v}")

print()
print("--- key globals ---")
print(f"{'GLOBAL':<28}{'C-JIT':<14}{'COMPILER.HC':<14}VERDICT")
print("-" * 68)
for g in off_g:
    a = off_g.get(g, "N/A")
    b = on_g.get(g, "N/A")
    v = "PASS" if a == b and a != "N/A" else ("FAIL" if a != b else "SKIP")
    if v == "FAIL":
        fails += 1
    print(f"{g:<28}{a:<14}{b:<14}{v}")

print()
print("--- undefined identifiers ---")
off_u = names(off_log, r"undefined identifier '([^']+)'")
on_u = names(on_log, r"undefined identifier '([^']+)'")
print(f"C-JIT       : {len(off_u)} {off_u}")
print(f"COMPILER.HC : {len(on_u)} {on_u}")
if set(off_u) != set(on_u):
    fails += 1
    print(f"  DIFF only-C-JIT={sorted(set(off_u)-set(on_u))} only-HC={sorted(set(on_u)-set(off_u))}")

print()
print("--- late-bound / unresolved forward refs ---")
off_lb = names(off_log, r"late-bound via SIC")
on_lb = names(on_log, r"late-bound via SIC")
off_un = names(off_log, r"^\s+- (\S+)\s*$")
on_un = names(on_log, r"^\s+- (\S+)\s*$")
print(f"late-bound  C-JIT={len(off_lb)} COMPILER.HC={len(on_lb)}")
print(f"unresolved  C-JIT={sorted(set(off_un))}")
print(f"unresolved  COMPILER.HC={sorted(set(on_un))}")
if set(off_un) != set(on_un):
    fails += 1

print()
print("==========================================================")
print(f"RESULT: {'PASS — engines agree' if fails == 0 else f'FAIL — {fails} divergence(s)'}")
print("==========================================================")
sys.exit(0 if fails == 0 else 1)
PY
rc=$?
exit $rc
