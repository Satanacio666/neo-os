#!/usr/bin/env python3
"""P0.4 — Matriz de portabilidade rápida (P0.4).

Valida as células da matriz de portabilidade que já funcionam hoje:
  (GICv2, GOP), (GICv3, GOP), (GICv2, Headless NEO_NO_GOP=1),
  (GICv3, Headless NEO_NO_GOP=1)

em SMP=1 e SMP=4. Para cada célula executa um boot via
scripts/run-viewer-vm.sh (make all + QEMU) e checa se o shell ativo
("DolDocShell active") apareceu antes do timeout.

Uso:
    python3 scripts/neo-matrix.py           # todas as células
    python3 scripts/neo-matrix.py --smp 4   # só SMP=4
    python3 scripts/neo-matrix.py --gic 2   # só GICv2

Saída: tabela PASS/FAIL por célula e rc=0 se todas passaram.
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEWER = os.path.join(ROOT, "scripts", "run-viewer-vm.sh")

# Cada célula: (nome, NEO_GIC_VERSION, NEO_NO_GOP, NEO_SMP)
CELLS = [
    ("GICv2 + GOP + SMP=1",   "2", "0", "1"),
    ("GICv3 + GOP + SMP=1",   "3", "0", "1"),
    ("GICv2 + Headless + SMP=1", "2", "1", "1"),
    ("GICv3 + Headless + SMP=1", "3", "1", "1"),
    ("GICv2 + GOP + SMP=4",   "2", "0", "4"),
    ("GICv3 + GOP + SMP=4",   "3", "0", "4"),
    ("GICv2 + Headless + SMP=4", "2", "1", "4"),
    ("GICv3 + Headless + SMP=4", "3", "1", "4"),
]


def run_cell(name, gic, nogop, smp, timeout=180):
    """Executa um boot na célula dada. Retorna True se o shell ativou."""
    env = dict(os.environ)
    env["NEO_GIC_VERSION"] = gic
    env["NEO_NO_GOP"] = nogop
    env["NEO_SMP"] = smp
    env["NEO_MTTCG"] = "0"  # determinístico no TCG (medido: MTTCG=1 mais lento)

    serial = "/tmp/neo-matrix-serial.log"
    try:
        os.remove(serial)
    except FileNotFoundError:
        pass

    # Boot direto (o run-viewer-vm.sh já faz make all internamente? Não — fazemos
    # make all uma vez antes e depois só reiniciamos a VM para não reconstruir).
    proc = subprocess.Popen(
        [VIEWER, "restart"],
        stdout=open(serial, "wb"),
        stderr=subprocess.STDOUT,
        env=env,
        cwd=ROOT,
    )
    started = time.time()
    active = False
    bsod = False
    while time.time() - started < timeout:
        try:
            with open(serial, "r", errors="ignore") as f:
                txt = f.read()
            if "DolDocShell active" in txt:
                active = True
                break
            if "BSOD:TIER0" in txt:
                bsod = True
                break
        except FileNotFoundError:
            pass
        time.sleep(2)
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
    return active, bsod


def main():
    args = sys.argv[1:]
    filter_smp = None
    filter_gic = None
    for a in args:
        if a == "--smp=1" or a == "--smp 1":
            filter_smp = "1"
        elif a == "--smp=4" or a == "--smp 4":
            filter_smp = "4"
        elif a == "--gic=2" or a == "--gic 2":
            filter_gic = "2"
        elif a == "--gic=3" or a == "--gic 3":
            filter_gic = "3"

    print("=" * 70)
    print("MATRIZ DE PORTABILIDADE — NeoOS (P0.4)")
    print("=" * 70)

    results = []
    for name, gic, nogop, smp in CELLS:
        if filter_smp and smp != filter_smp:
            continue
        if filter_gic and gic != filter_gic:
            continue
        active, bsod = run_cell(name, gic, nogop, smp)
        status = "PASS" if active else ("FAIL-BSOD" if bsod else "FAIL-TIMEOUT")
        results.append((name, status))
        mark = "✓" if active else "✗"
        print(f"  [{mark}] {name:<32} -> {status}")

    print("-" * 70)
    all_pass = all(s == "PASS" for _, s in results)
    print(f"Resultado: {'TODAS PASSARAM' if all_pass else 'ALGUMA FALHOU'}")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
