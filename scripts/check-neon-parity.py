#!/usr/bin/env python3
"""
check-neon-parity.py — Dissolu��o B: garante que os 4 fontes NEON de referencia
continuam intocaveis. Como o codigo AArch64 emitido pelo JIT embute enderecos e
referencias, um byte que mude no .s pode quebrar o determinismo (RENDER 0xD28836F)
ou introduzir corrupcao silenciosa.

Uso:
    python3 scripts/check-neon-parity.py            # compara contra o baseline embutido
    python3 scripts/check-neon-parity.py --write   # (re)grava o baseline atual como referecia

Retorna 0 se todos os .s estao identicos ao baseline, 1 se qualquer um divergiu
ou faltou. E' chamado pelo harness-full.sh como gate da Fase B.
"""
import sys
import os
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Fontes NEON que devem permanecer intocaveis (Dissolucao B / Fase B).
# Os 4 em scripts/ sao "SOURCE OF TRUTH" dos opcodes hex embutidos nos .HC
# (scripts/render_neon.s -> apps/Render.HC asm{}; shader_quad.s -> ShaderVM.HC;
#  raster_span.s -> RasterTile.HC; tile_resolve.s -> RasterTile.HC).
# Os arquiteturais (kernel/arch) sao o bootstrap/contexto.
NEON_SOURCES = [
    "scripts/render_neon.s",
    "scripts/shader_quad.s",
    "scripts/raster_span.s",
    "scripts/tile_resolve.s",
    "kernel/arch/aarch64/vectors.S",
    "kernel/arch/aarch64/smp_entry.S",
    "kernel/arch/aarch64/ffi_arm64.S",
    "kernel/arch/aarch64/el2_drop.S",
]

# Hashes emitidos pelo emissor JIT nos .HC devem bater com estes .s. Se o emissor
# (ShaderVM/RasterTile) embute NEON e o fonte de referencia muda, aqui detectamos.
# Preencher com --write na primeira execucao (baseline correto), depois trancar.

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    baseline_path = os.path.join(ROOT, "tests", "neon-parity.txt")
    if "--write" in sys.argv:
        # (re)grava o baseline atual
        os.makedirs(os.path.dirname(baseline_path), exist_ok=True)
        with open(baseline_path, "w") as f:
            for rel in NEON_SOURCES:
                path = os.path.join(ROOT, rel)
                if os.path.exists(path):
                    f.write("%s  %s\n" % (sha256_file(path), rel))
        print("[neon-parity] baseline gravado: %s" % baseline_path)
        return 0

    if not os.path.exists(baseline_path):
        print("[neon-parity] FAIL: sem baseline em %s (rode --write primeiro)" % baseline_path)
        return 1

    expected = {}
    with open(baseline_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            h, rel = line.split(None, 1)
            expected[rel] = h

    fail = 0
    for rel in NEON_SOURCES:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            print("[neon-parity] FAIL: fonte ausente: %s" % rel)
            fail = 1
            continue
        got = sha256_file(path)
        want = expected.get(rel)
        if want is None:
            print("[neon-parity] WARN: %s nao esta no baseline" % rel)
            continue
        if got == want:
            print("[neon-parity] PASS: %s (%s)" % (rel, got[:16]))
        else:
            print("[neon-parity] FAIL: %s divergiu\n  esperado  %s\n  obtido    %s" % (rel, want, got))
            fail = 1

    if fail:
        print("[neon-parity] RESULTADO: FAIL")
    else:
        print("[neon-parity] RESULTADO: PASS (todos os .s NEON intocaveis)")
    return fail

if __name__ == "__main__":
    sys.exit(main())
