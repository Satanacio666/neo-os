#!/usr/bin/env python3
# ==============================================================================
# scripts/_p1_flip.py — aplica o flip de self-host numa COPIA do KernelInit.HC.
# (CAMADA 1.3 / IDEA-8) Extraido do patch embutido que antes rodava na arvore viva.
# Uso: _p1_flip.py <destino.HC> off|full|module:NAME
# ==============================================================================
import sys

if len(sys.argv) != 3:
    sys.exit("uso: _p1_flip.py <destino.HC> off|full|module:NAME")

p, variant = sys.argv[1], sys.argv[2]
src = open(p).read()

FLIP_ON = "    g_hc_ready = 1;"
COND = "if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }"

if COND not in src:
    sys.exit("parity: flipped call site not found (tree not at 0b2db9d?)")
if FLIP_ON not in src:
    sys.exit("parity: flip anchor %r not found" % FLIP_ON)

if variant == "full":
    pass  # committed state == full flip ON
elif variant == "off":
    src = src.replace(FLIP_ON, "    g_hc_ready = 0;", 1)
elif variant.startswith("module:"):
    name = variant[len("module:"):]
    src = src.replace(FLIP_ON, "    g_hc_ready = 0;", 1)
    anchor = '    KInitLoad("%s");' % name
    if anchor not in src:
        sys.exit("parity: module anchor not found: %s" % name)
    src = src.replace(anchor, "    g_hc_ready = 1;\n" + anchor + "\n    g_hc_ready = 0;", 1)
else:
    sys.exit("parity: unknown variant %s" % variant)

open(p, "w").write(src)
