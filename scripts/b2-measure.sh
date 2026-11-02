#!/bin/sh
# b2-measure.sh — mede a compilacao do boot pelo BOOTSTAGE (B2), N vezes.
# Uso: sh scripts/b2-measure.sh [n]
# Imprime, por rodada: total de compilacao e o top de modulos. O QEMU TCG tem
# variancia alta entre boots, por isso N>1 e a mediana sao necessarios.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="${1:-2}"
cd "$ROOT" || exit 1

run_once() {
    for d in /proc/[0-9]*; do
        a=$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null | head -1)
        case "$a" in *qemu-system*) kill -9 "${d#/proc/}" 2>/dev/null;; esac
    done
    sleep 2
    rm -f /tmp/neo-os-serial.log
    bash scripts/run-viewer-vm.sh start >/dev/null 2>&1
    i=0
    while [ "$i" -lt 150 ]; do
        grep -aq 'DolDocShell active' /tmp/neo-os-serial.log 2>/dev/null && break
        i=$((i+1)); sleep 2
    done
    grep -a '\[BOOTSTAGE\] timeline' /tmp/neo-os-serial.log | head -1
    grep -aA9 '\[BOOTSTAGE\] modulos por tempo' /tmp/neo-os-serial.log
}

r=1
while [ "$r" -le "$N" ]; do
    echo "=========== RODADA $r/$N ==========="
    run_once
    r=$((r+1))
done
