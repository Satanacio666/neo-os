#!/usr/bin/env bash
# ==============================================================================
# harness-full.sh — HARNESS COMPLETO do NeoOS
#
# Roda o gate oficial (golden-boot.sh) MAIS os verificadores que a matriz de
# verificacao dos docs exige mas que o gate NAO chama:
#   * check-token-parity.py   (71 tokens: Compiler.HC vs boot/seed/tok.h)
#   * check-source-sanity.py  (tamanho + chaves de cada .HC vs HEAD)
#   * census-c-runtime.sh     (ja no gate, mas rodado aqui com veredito explicito)
#   * audit-symbols.sh        (emissao de zero literal, stubs nao resolvidos)
#   * run-jit-golden.py       (86 casos golden do C JIT)   [opcional: --jit]
#   * p1-parity.sh            (paridade dos 2 motores)     [opcional: --parity]
#
# Uso:
#   bash scripts/harness-full.sh            # rapido: estaticos + gate oficial
#   bash scripts/harness-full.sh --all      # + jit-golden + p1-parity (mais lento)
#
# Saida: PASS/FAIL por etapa + veredito final. Codigo 0 = tudo verde.
# ==============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
RUN_ALL=0
[ "${1:-}" = "--all" ] && RUN_ALL=1

fail=0
pass_n=0
fail_n=0
step() { printf '\n=== [%s] %s ===\n' "$1" "$2"; }
ok()   { echo "  [PASS] $1"; pass_n=$((pass_n+1)); }
bad()  { echo "  [FAIL] $1"; fail_n=$((fail_n+1)); fail=1; }

echo "############################################################"
echo "#  NeoOS — HARNESS COMPLETO"
echo "#  repo: $ROOT"
echo "#  head: $(git rev-parse --short HEAD 2>/dev/null || echo n/a)  arvore: $( [ -z "$(git status --porcelain 2>/dev/null)" ] && echo limpa || echo SUJA )"
echo "############################################################"

# ---------------------------------------------------------------- 1. estaticos
step 1/6 "sanidade de fonte (.HC vs HEAD)"
if python3 scripts/check-source-sanity.py 2>&1 | tail -1 | grep -q 'PASS'; then
    ok "source-sanity"
else
    bad "source-sanity"; python3 scripts/check-source-sanity.py 2>&1 | tail -3
fi

step 2/6 "paridade de tokens (Compiler.HC vs boot/seed/tok.h)"
if python3 scripts/check-token-parity.py >/tmp/hf-tok.log 2>&1; then
    ok "$(tail -1 /tmp/hf-tok.log)"
else
    bad "token parity"; tail -5 /tmp/hf-tok.log
fi

step 3/6 "census .HC->C (baseline 181)"
if bash scripts/census-c-runtime.sh >/tmp/hf-census.log 2>&1; then
    ok "$(tail -1 /tmp/hf-census.log)"
else
    bad "census"; tail -5 /tmp/hf-census.log
fi

step 4/6 "auditoria de simbolos (emissao zero / stubs)"
if bash scripts/audit-symbols.sh >/tmp/hf-syms.log 2>&1; then
    ok "audit-symbols (sem zero-literal / stub suspeito)"
else
    bad "audit-symbols encontrou algo"; tail -10 /tmp/hf-syms.log
fi

# ---------------------------------------------------------------- 5. gate oficial
step 5/6 "GATE OFICIAL (golden-boot.sh) — boot + selftest + self-host + determinism"
bash scripts/golden-boot.sh >/tmp/hf-gate.log 2>&1
gate_rc=$?
tail -40 /tmp/hf-gate.log | sed 's/^/  | /'
if [ "$gate_rc" -eq 0 ] && grep -q 'GOLDEN BOOT: PASS' /tmp/hf-gate.log; then
    ok "golden-boot (rc=$gate_rc)"
else
    bad "golden-boot (rc=$gate_rc)"
fi

# ---------------------------------------------------------------- 6. opcionais
if [ "$RUN_ALL" = "1" ]; then
    step 6a/7 "golden do C JIT (86 casos)"
    if python3 scripts/run-jit-golden.py >/tmp/hf-jit.log 2>&1; then
        ok "$(tail -1 /tmp/hf-jit.log)"
    else
        bad "jit-golden"; tail -5 /tmp/hf-jit.log
    fi

    step 6b/7 "paridade dos motores (p1-parity, varios boots)"
    if bash scripts/p1-parity.sh >/tmp/hf-parity.log 2>&1; then
        ok "$(tail -1 /tmp/hf-parity.log)"
    else
        bad "p1-parity"; tail -8 /tmp/hf-parity.log
    fi
else
    echo
    echo "  (pulados: run-jit-golden.py e p1-parity.sh — rode com --all)"
fi

# ---------------------------------------------------------------- veredito
echo
echo "############################################################"
printf "#  VEREDITO: %d PASS, %d FAIL\n" "$pass_n" "$fail_n"
if [ "$fail" -eq 0 ]; then
    echo "#  HARNESS COMPLETO: PASS"
else
    echo "#  HARNESS COMPLETO: FAIL"
fi
echo "############################################################"
exit "$fail"
