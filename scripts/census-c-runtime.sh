#!/usr/bin/env bash
# ==============================================================================
# scripts/census-c-runtime.sh — .HC -> C runtime call census gate (P0.5.6 / P2.0)
# ==============================================================================
# Counts how often apps/*.HC still call into the C bootstrap runtime
# (kmalloc/kfree/symbols_*/hal_flush_cache/redsea_*/jit_compile_and_run) and
# fails if any count INCREASES vs tests/census-baseline.txt. This is the
# regression guard for P2: each step must drive the counts DOWN, never up.
#
#   scripts/census-c-runtime.sh            # compare against the baseline
#   scripts/census-c-runtime.sh --write    # (re)generate the baseline
#
# Exit 0 = no count increased, 1 = regression.
# ==============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/tests/census-baseline.txt"

count() { rg -o --no-filename "\b$1\b" "$ROOT/apps"/*.HC 2>/dev/null | wc -l | tr -d ' '; }

SYMBOLS="kmalloc kfree symbols_register symbols_lookup hal_flush_cache \
redsea_read_file redsea_write_file redsea_list_dir symbols_is_defined \
symbols_var_cell symbols_sic_cell symbols_count symbols_unresolved_count \
jit_compile_and_run"

if [ "${1:-}" = "--write" ]; then
    : > "$BASELINE"
    for s in $SYMBOLS; do printf '%s\t%s\n' "$s" "$(count "$s")" >> "$BASELINE"; done
    echo "census-c-runtime: wrote baseline ($BASELINE)"
    exit 0
fi

if [ ! -f "$BASELINE" ]; then
    echo "census-c-runtime: no baseline; run with --write" >&2
    exit 2
fi

fail=0
total=0
while IFS=$'\t' read -r s base; do
    [ -z "$s" ] && continue
    cur=$(count "$s")
    total=$((total + cur))
    if [ "$cur" -gt "$base" ]; then
        echo "  [FAIL] $s: $base -> $cur (increased)"
        fail=1
    elif [ "$cur" -lt "$base" ]; then
        echo "  [DOWN] $s: $base -> $cur"
    fi
done < "$BASELINE"

if [ $fail -eq 0 ]; then
    echo "CENSUS: PASS ($total total .HC->C runtime calls, none increased)"
else
    echo "CENSUS: FAIL"
fi
exit $fail
