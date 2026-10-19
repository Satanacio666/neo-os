#!/usr/bin/env bash
# Symbol/zero-emission audit.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${NEO_SERIAL_LOG:-/tmp/neo-os-serial.log}"

echo "=== STATIC: literal-zero emissions in compiler/jit_arm64.c ==="
rg -n 'emit_mov_imm64\((cb|&fn_cb), [0-9]+, 0\)' "$ROOT/compiler/jit_arm64.c" || echo "  (none)"
echo
echo "=== STATIC: unresolved-stub registrations ==="
rg -n 'symbols_unresolved_trap|symbols_lookup_or_reserve' "$ROOT/kernel/symbols/symbols.c" "$ROOT/compiler/jit_arm64.c" | head -20
echo
echo "=== RUNTIME: undefined identifiers at boot ==="
rg -n 'undefined identifier' "$LOG" || echo "  (none)"
echo "=== RUNTIME: late-bound forward references ==="
rg -n 'late-bound' "$LOG" || echo "  (none)"
echo "=== RUNTIME: unresolved report ==="
rg -n 'UNRESOLVED|No unresolved' "$LOG" || echo "  (none)"
echo
echo "Summary: $(rg -c 'undefined identifier' "$LOG" 2>/dev/null || echo 0) undefined, $(rg -c 'late-bound' "$LOG" 2>/dev/null || echo 0) late-bound"
