#!/usr/bin/env bash
# P4.8 determinism gate: the ONE renderer must produce a byte-identical image
# regardless of core count. We boot the whole OS twice — once on a single core
# and once on N cores — run the in-guest battery, and compare the golden-frame
# hash asserted by SelfTestRender (RENDER: PASS (golden=0x...)).
#
# The hash is a 32-bit FNV-1a over the whole back buffer, rendered with IRQs
# masked, so it is the ground truth for "same image on 1 vs N cores".
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=/tmp/neo-os-serial.log
SENTINEL='<<<NEO-DONE:selftest>>>'
SMP_N="${1:-4}"

hash_for_smp() {
    local smp="$1"
    NEO_SMP="$smp" "$ROOT/scripts/run-viewer-vm.sh" restart >/dev/null 2>&1
    for i in $(seq 1 60); do
        grep -q 'DolDocShell active' "$LOG" 2>/dev/null && break
        sleep 1
    done
    python3 "$ROOT/scripts/neo_uart.py" --sentinel "$SENTINEL" --timeout 120 'selftest' >/dev/null 2>&1 || true
    # SO a ultima linha RENDER: PASS conta. Uma linha FAIL imprime a CONSTANTE golden
    # (SelfTest.HC:940 — "golden=0x%llX" com g_render_golden), nao o hash real; extrai-la
    # faria os dois boots "concordarem" na constante e o gate daria PASS mesmo com o
    # render quebrado nos dois. Se nenhum boot renderizar PASS, sai vazio -> FAIL.
    grep -a 'RENDER: ' "$LOG" 2>/dev/null | grep -a 'PASS' | tail -1 \
        | sed -E 's/.*golden=(0x[0-9A-Fa-f]+).*/\1/'
}

echo "== determinism: 1 core vs ${SMP_N} cores =="
H1="$(hash_for_smp 1)"
HN="$(hash_for_smp "$SMP_N")"

echo "  1-core   RENDER hash: ${H1:-<none>}"
echo "  ${SMP_N}-core   RENDER hash: ${HN:-<none>}"

if [ -n "$H1" ] && [ "$H1" = "$HN" ]; then
    echo "DETERMINISM: PASS (1 vs ${SMP_N} cores identical: $H1)"
    exit 0
else
    echo "DETERMINISM: FAIL (1 vs ${SMP_N} cores differ)"
    exit 1
fi
