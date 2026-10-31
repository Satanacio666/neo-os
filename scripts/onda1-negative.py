#!/usr/bin/env python3
# ==============================================================================
# onda1-negative.py — CONTROLE NEGATIVO da ONDA 1.
#
# Prova que os 3 testes novos do SelfTest.HC FALHARIAM sem os fixes: reverte
# SOMENTE os corpos dos fixes (mantendo as globais, as sondas e os testes) e
# recompila. Se o boot negativo mostrar b3/b4/b7 = FAIL, a prova e' real (o
# teste discrimina). Depois restaura os arquivos de /tmp/onda1-bkp.
#
# B8 nao tem teste (nao e' forcavel sem quebrar o kmalloc do pool) — documentado.
# ==============================================================================
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BKP = "/tmp/onda1-bkp"


def read(p):
    with open(p) as f:
        return f.read()


def write(p, s):
    with open(p, "w") as f:
        f.write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise SystemExit("[FAIL] marcador '%s' aparece %d vezes" % (label, n))
    return text.replace(old, new, 1)


# --- B3: volta o `return` mudo (a sonda continua existindo e devolvera 0). ---
p = os.path.join(ROOT, "apps/Watchdog.HC")
s = read(p)
s = sub_once(
    s,
    "    if (!g_healthlog_buf) {\n"
    "        // B3 (ONDA 1): NAO ha mais `return` mudo. O evento perdido e' contado e\n"
    "        // a primeira perda GRITA (doldoc_printf <=7 args). O contador so sobe\n"
    "        // aqui; o estado normal nao o toca.\n"
    "        g_healthlog_dropped++;\n"
    "        if (g_healthlog_dropped == 1)\n"
    "            doldoc_printf(\"$FG,RED$[HEALTHLOG] DROP: buffer ausente — evento perdido (type=%lld)$FG$\\n\", h_type);\n"
    "        return;\n"
    "    }\n",
    "    if (!g_healthlog_buf) return;\n",
    "neg.B3",
)
write(p, s)

# --- B4: remove o `else` (volta ao descarte mudo). ---
p = os.path.join(ROOT, "apps/RasterTile.HC")
s = read(p)
s = sub_once(
    s,
    "      else {\n"
    "        if (!g_rs_tile_overflowed) {\n"
    "          g_rs_tile_overflowed = 1;\n"
    "          doldoc_printf(\"$FG,RED$[RASTER] FATAL: RASTER_MAX_TRIS_PER_TILE overflow (prod=%lld tile=%lld count=%lld max=%lld)$FG$\\n\",\n"
    "                        producer, ty * g_rs_cols + tx, b->count, (I64)RASTER_MAX_TRIS_PER_TILE);\n"
    "        }\n"
    "      }\n",
    "",
    "neg.B4",
)
write(p, s)

# --- B7: remove o `else HcRaiseError(...)` (volta ao offset 0 mudo). ---
p = os.path.join(ROOT, "apps/Compiler.HC")
s = read(p)
s = sub_once(
    s,
    "                else HcRaiseError(HC_ERR_UNRESOLVED_TYPE);  // B7: membro desconhecido NAO compila como offset 0 (sem chaves: Regra 14)\n",
    "",
    "neg.B7",
)
write(p, s)

print("[NEGATIVO] fixes revertidos (globais, sondas e testes preservados)")
print("[NEGATIVO] esperado no boot: b3=0, b4=0, b7=nao-rejeitado -> os 3 FALHAM")
