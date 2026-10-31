#!/bin/sh
# scripts/checkpoint.sh "<mensagem do commit>"
#
# P0.2 — Checkpoint disciplinado: compila, roda o gate oficial e SÓ comita se o
# gate estiver verde. Um checkpoint que passa por cima de regressão não é
# checkpoint, é dívida.
#
# Uso:
#   scripts/checkpoint.sh "P1.1: Makefile autodetecta toolchain nativa"
#
# Saída: relatório do gate em ../gate-reports/gate-<sha>.txt
set -u
MSG="${1:-checkpoint}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORTS="$(dirname "$ROOT")/gate-reports"
cd "$ROOT" || exit 1
mkdir -p "$REPORTS"

echo "== 1/3 build =="
if ! make all -j"$(nproc)" > /tmp/checkpoint-build.log 2>&1; then
   echo "BUILD FALHOU — sem commit."
   tail -15 /tmp/checkpoint-build.log
   exit 2
fi
echo "   ok ($(rg -c '' /tmp/checkpoint-build.log) linhas de log)"

echo "== 2/3 gate =="
if [ ! -f "$ROOT/scripts/neo-gate.py" ]; then
   echo "scripts/neo-gate.py ausente — sem gate, sem commit."
   exit 3
fi
python3 "$ROOT/scripts/neo-gate.py" > /tmp/checkpoint-gate.txt 2>&1
if ! rg -q 'SELFTEST: 99/99' /tmp/checkpoint-gate.txt; then
   echo "GATE VERMELHO — sem commit. Relatório: /tmp/checkpoint-gate.txt"
   rg 'SELFTEST|PARITY|RENDER|FAIL|Exception' /tmp/checkpoint-gate.txt | tail -12
   exit 4
fi
rg 'SELFTEST|PARITY|RENDER|HOLYC SUBSYSTEMS|DolDocShell' /tmp/checkpoint-gate.txt | tail -6

echo "== 3/3 commit =="
git add -A
if git -c user.email=minis@local -c user.name=minis commit -q -m "$MSG"; then
   SHA="$(git rev-parse --short HEAD)"
   cp /tmp/checkpoint-gate.txt "$REPORTS/gate-$SHA.txt"
   echo "   checkpoint $SHA"
   echo "   relatorio do gate: $REPORTS/gate-$SHA.txt"
else
   echo "   nada novo para comitar (gate continua verde)"
fi
