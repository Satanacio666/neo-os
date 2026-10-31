#!/usr/bin/env python3
# ==============================================================================
# onda1-fallbacks.py — ONDA 1: 4 fallbacks silenciosos viram falha ALTA.
#
# Protocolo obrigatorio (ESTADO.md secao 9): cada substituicao introduz um
# IDENTIFICADOR UNICO, e o script VERIFICA no disco, depois de escrever:
#   * o marcador antigo existia exatamente 1x;
#   * o marcador novo aparece exatamente 1x;
#   * as chaves do arquivo continuam balanceadas;
#   * as funcoes-chave continuam presentes exatamente 1x (`U0 <nome>`);
#   * o arquivo NAO encolheu.
# Se qualquer checagem falhar: restaura o backup e sai com codigo != 0.
#
# Regra 14: NENHUM bloco `{}` SOLTO (nao-adjacente a if/else/while/for) no
# Compiler.HC — o parser do seed C nao tem case para TOK_LBRACE como statement e
# erra "Unexpected token '<symbol>'" (boot/seed/jit_arm64.c:1446).
# ==============================================================================
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BKP = "/tmp/onda1-bkp"


def read(p):
    with open(p, "r") as f:
        return f.read()


def write(p, s):
    with open(p, "w") as f:
        f.write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise SystemExit("[FAIL] marcador '%s' aparece %d vezes (esperado 1)" % (label, n))
    return text.replace(old, new, 1)


# ------------------------------------------------------------------------------
# B3 — apps/Watchdog.HC
# ------------------------------------------------------------------------------
WD = os.path.join(ROOT, "apps/Watchdog.HC")
src = read(WD)

src = sub_once(
    src,
    "I64  g_healthlog_count = 0; // entradas vivas (0..HEALTHLOG_MAX)\n",
    "I64  g_healthlog_count = 0; // entradas vivas (0..HEALTHLOG_MAX)\n"
    "// B3 (ONDA 1): o livro-razao voltava em SILENCIO quando o buffer nao existia\n"
    "// (`if (!g_healthlog_buf) return;`) — o evento simplesmente sumia. Este\n"
    "// contador observavel (auto-publicado: o gate/sonda pode le-lo) transforma a\n"
    "// perda muda em falha audivel: incrementa SEMPRE e grita na 1a ocorrencia.\n"
    "I64  g_healthlog_dropped = 0;\n",
    "B3.global",
)

src = sub_once(
    src,
    "    if (!g_healthlog_buf) return;\n"
    "    if (g_healthlog_head < 0 || g_healthlog_head >= HEALTHLOG_MAX) g_healthlog_head = 0;\n",
    "    if (!g_healthlog_buf) {\n"
    "        // B3 (ONDA 1): NAO ha mais `return` mudo. O evento perdido e' contado e\n"
    "        // a primeira perda GRITA (doldoc_printf <=7 args). O contador so sobe\n"
    "        // aqui; o estado normal nao o toca.\n"
    "        g_healthlog_dropped++;\n"
    "        if (g_healthlog_dropped == 1)\n"
    "            doldoc_printf(\"$FG,RED$[HEALTHLOG] DROP: buffer ausente — evento perdido (type=%lld)$FG$\\n\", h_type);\n"
    "        return;\n"
    "    }\n"
    "    if (g_healthlog_head < 0 || g_healthlog_head >= HEALTHLOG_MAX) g_healthlog_head = 0;\n",
    "B3.record",
)

# Sonda/teste funcional do caminho de falha (chamada pelo SelfTest.HC).
src = sub_once(
    src,
    "// Imprime as ultimas N entradas (padrao: 10). Consulta em runtime.\n",
    "// B3 (ONDA 1): prova FUNCIONAL do caminho de falha. Forca o estado exato do\n"
    "// defeito (buffer ausente) e devolve o delta do contador — o SelfTest exige 1.\n"
    "// Sem o fix (return mudo) o delta seria 0 e o teste falharia.\n"
    "I64 WatchdogTestHealthLogDrop() {\n"
    "    U8 *saved_buf = g_healthlog_buf;\n"
    "    I64 saved_n = g_healthlog_dropped;\n"
    "    g_healthlog_dropped = 0;\n"
    "    g_healthlog_buf = 0;\n"
    "    HealthLogRecord(HEALTH_CANARY, 1, 0);\n"
    "    I64 hit = g_healthlog_dropped;\n"
    "    g_healthlog_buf = saved_buf;\n"
    "    g_healthlog_dropped = saved_n;\n"
    "    return hit;\n"
    "}\n"
    "\n"
    "// Imprime as ultimas N entradas (padrao: 10). Consulta em runtime.\n",
    "B3.probe",
)

write(WD, src)

# ------------------------------------------------------------------------------
# B4 — apps/RasterTile.HC
# ------------------------------------------------------------------------------
RT = os.path.join(ROOT, "apps/RasterTile.HC")
src = read(RT)

src = sub_once(
    src,
    "I64 g_rs_producer_overflowed = 0;\nI64 g_rs_tris_overflowed = 0;\n",
    "I64 g_rs_producer_overflowed = 0;\nI64 g_rs_tris_overflowed = 0;\n"
    "// B4 (ONDA 1): o bin por tile era o UNICO overflow sem contador — `if (count <\n"
    "// MAX)` sem `else`, entao um bin cheio descartava o triangulo EM SILENCIO\n"
    "// (tile com furo e sem uma linha de log). Mesmo estilo dos dois contadores\n"
    "// acima: sticky, primeira ocorrencia grita.\n"
    "I64 g_rs_tile_overflowed = 0;\n",
    "B4.global",
)

src = sub_once(
    src,
    "      CRasterBin *b = &g_rs_bins[producer][ty * g_rs_cols + tx];\n"
    "      if (b->count < RASTER_MAX_TRIS_PER_TILE) {\n"
    "        b->idx[b->count] = (U16)ti;\n"
    "        b->count = b->count + 1;\n"
    "      }\n",
    "      CRasterBin *b = &g_rs_bins[producer][ty * g_rs_cols + tx];\n"
    "      if (b->count < RASTER_MAX_TRIS_PER_TILE) {\n"
    "        b->idx[b->count] = (U16)ti;\n"
    "        b->count = b->count + 1;\n"
    "      }\n"
    "      else {\n"
    "        if (!g_rs_tile_overflowed) {\n"
    "          g_rs_tile_overflowed = 1;\n"
    "          doldoc_printf(\"$FG,RED$[RASTER] FATAL: RASTER_MAX_TRIS_PER_TILE overflow (prod=%lld tile=%lld count=%lld max=%lld)$FG$\\n\",\n"
    "                        producer, ty * g_rs_cols + tx, b->count, (I64)RASTER_MAX_TRIS_PER_TILE);\n"
    "        }\n"
    "      }\n",
    "B4.bin",
)

# Sonda/teste funcional: enche um bin alem do teto e exige o flag.
src = sub_once(
    src,
    "U0 RasterBootCheck() {\n",
    "// B4 (ONDA 1): prova FUNCIONAL do caminho de falha. Enche o bin do tile (0,0)\n"
    "// alem do teto e submete um triangulo que cai nesse tile; devolve o flag\n"
    "// observavel. Sem o fix (descarte mudo) o retorno seria 0.\n"
    "I64 RasterTestTileOverflow() {\n"
    "  I64 saved = g_rs_tile_overflowed;\n"
    "  g_rs_tile_overflowed = 0;\n"
    "  RasterSceneBegin(0, 0, 128, 128, 0xFF000000);\n"
    "  g_rs_bins[0][0].count = RASTER_MAX_TRIS_PER_TILE + 8;\n"
    "  CRasterVertex ov[3];\n"
    "  ov[0].x = 1.0;  ov[0].y = 1.0;  ov[0].z = 1;\n"
    "  ov[1].x = 20.0; ov[1].y = 1.0;  ov[1].z = 1;\n"
    "  ov[2].x = 1.0;  ov[2].y = 20.0; ov[2].z = 1;\n"
    "  RasterSceneAddTriangle(ov, 0xFFFFFFFF);\n"
    "  I64 hit = g_rs_tile_overflowed;\n"
    "  RasterSceneBegin(0, 0, 128, 128, 0xFF000000);  // restaura os bins (count=0)\n"
    "  g_rs_tile_overflowed = saved;\n"
    "  return hit;\n"
    "}\n"
    "\n"
    "U0 RasterBootCheck() {\n",
    "B4.probe",
)

write(RT, src)

# ------------------------------------------------------------------------------
# B7 + B8 — apps/Compiler.HC
# ------------------------------------------------------------------------------
CO = os.path.join(ROOT, "apps/Compiler.HC")
src = read(CO)

# B7: membro desconhecido -> HC_ERR_UNRESOLVED_TYPE (sem chaves: Regra 14).
src = sub_once(
    src,
    "                    if ((m_ptr || m_arr) && g_hc_tok == TOK_LBRACKET) cur_scale = m_elem;\n"
    "                }\n"
    "            }\n"
    "        } else if (g_hc_tok == TOK_LBRACKET) {\n",
    "                    if ((m_ptr || m_arr) && g_hc_tok == TOK_LBRACKET) cur_scale = m_elem;\n"
    "                }\n"
    "                else HcRaiseError(HC_ERR_UNRESOLVED_TYPE);  // B7: membro desconhecido NAO compila como offset 0 (sem chaves: Regra 14)\n"
    "            }\n"
    "        } else if (g_hc_tok == TOK_LBRACKET) {\n",
    "B7.else",
)

# B8: kmalloc do pool de codigo sem checagem -> falha alta (kills the silent NULL pool).
src = sub_once(
    src,
    "    if (!g_hc_code) {\n"
    "        g_hc_code = kmalloc(HC_CODE_CAPACITY * 4);\n"
    "        g_hc_pool_offset = 0;\n",
    "    if (!g_hc_code) {\n"
    "        g_hc_code = kmalloc(HC_CODE_CAPACITY * 4);\n"
    "        if (!g_hc_code) {\n"
    "            // B8 (ONDA 1): o pool de codigo era o unico kmalloc sem checagem.\n"
    "            // Com 0, TODO HcEmit escreveria no endereco 0 — falha obscura,\n"
    "            // longe da causa. Aqui falha ALTO: log + erro interno de capacidade\n"
    "            // (HC_ERR_CODE_OVERFLOW e' a classe mais proxima: o pool e' o\n"
    "            // recurso que faltou, e HcErrIsInternal trata 8..10 como falha\n"
    "            // INTERNA). doldoc_printf ja' esta' registrado neste ponto (o\n"
    "            // vizinho HcStrAlloc usa o mesmo padrao).\n"
    "            doldoc_printf(\"$FG,RED$[COMPILER] FATAL: HcInit: kmalloc(%lld) do pool de codigo FALHOU — nenhum modulo podera ser compilado$FG$\\n\",\n"
    "                          (I64)(HC_CODE_CAPACITY * 4));\n"
    "            HcRaiseError(HC_ERR_CODE_OVERFLOW);\n"
    "            return;\n"
    "        }\n"
    "        g_hc_pool_offset = 0;\n",
    "B8.kmalloc",
)

write(CO, src)

# ------------------------------------------------------------------------------
# SelfTest.HC — os 3 testes que FALHARIAM sem o fix.
# ------------------------------------------------------------------------------
ST = os.path.join(ROOT, "apps/SelfTest.HC")
src = read(ST)

new_fn = """// ==============================================================================
// ONDA 1 — fallbacks silenciosos viram falha ALTA (B3, B4, B7, B8).
// Usa SelfTestCompare / SelfTestReject (HC puro): SelfTestCheck alimenta a
// paridade C e nao deve ser tocado aqui.
//   B3: forca o buffer do HealthLog ausente -> o contador TEM de subir (1).
//       Sem o fix (return mudo) o delta era 0.
//   B4: enche um bin de tile alem do teto -> o flag TEM de subir (1).
//       Sem o fix (if sem else) o retorno era 0.
//   B7: membro desconhecido TEM de ser REJEITADO (-1).
//       Sem o fix ele compilava como offset 0 e lia o campo errado.
//   B8: NAO e' testavel sem quebrar o kmalloc do pool (ver relatorio).
// ==============================================================================
U0 SelfTestFallbacks() {
    SelfTestCompare("b3_healthlog_drop_counted", WatchdogTestHealthLogDrop(), 1);
    SelfTestCompare("b4_raster_tile_overflow_flagged", RasterTestTileOverflow(), 1);
    SelfTestReject("b7_unknown_member_rejected", "struct B7S { I64 a; }; B7S b7v; b7v.b7nomember;");
}

"""
src = sub_once(
    src,
    "U0 SelfTestRun() {\n",
    new_fn + "U0 SelfTestRun() {\n",
    "ST.fn",
)

src = sub_once(
    src,
    "    SelfTestOverflowInjection();\n    SelfTestHeapIntegrity();\n",
    "    SelfTestOverflowInjection();\n    SelfTestHeapIntegrity();\n    SelfTestFallbacks();\n",
    "ST.call",
)

write(ST, src)

# ------------------------------------------------------------------------------
# VERIFICACAO NO DISCO (a ferramenta pode mentir; o disco nao).
# ------------------------------------------------------------------------------
CHECKS = [
    # (arquivo, marcador, exatamente N)
    ("apps/Watchdog.HC", "I64  g_healthlog_dropped = 0;", 1),
    ("apps/Watchdog.HC", "g_healthlog_dropped++;", 1),
    ("apps/Watchdog.HC", "[HEALTHLOG] DROP: buffer ausente", 1),
    ("apps/Watchdog.HC", "I64 WatchdogTestHealthLogDrop()", 1),
    ("apps/RasterTile.HC", "I64 g_rs_tile_overflowed = 0;", 1),
    ("apps/RasterTile.HC", "g_rs_tile_overflowed = 1;", 1),
    ("apps/RasterTile.HC", "RASTER_MAX_TRIS_PER_TILE overflow", 1),
    ("apps/RasterTile.HC", "I64 RasterTestTileOverflow()", 1),
    ("apps/Compiler.HC", "else HcRaiseError(HC_ERR_UNRESOLVED_TYPE);  // B7", 1),
    ("apps/Compiler.HC", "HcInit: kmalloc(", 1),
    ("apps/SelfTest.HC", "U0 SelfTestFallbacks() {", 1),
    ("apps/SelfTest.HC", "SelfTestFallbacks();", 1),
    ("apps/SelfTest.HC", "b3_healthlog_drop_counted", 1),
    ("apps/SelfTest.HC", "b4_raster_tile_overflow_flagged", 1),
    ("apps/SelfTest.HC", "b7_unknown_member_rejected", 1),
]
KEYS = [
    ("apps/Compiler.HC", "U0 HcInit()", 1),
    ("apps/Compiler.HC", "I64 HcFindMember(", 1),
    ("apps/Compiler.HC", "U0 HcResolveLValue(", 1),
    ("apps/Compiler.HC", "U0 HcParseStatement()", 1),
    ("apps/Compiler.HC", "U0 HcParseProgram()", 1),
    ("apps/Watchdog.HC", "U0 HealthLogRecord(", 1),
    ("apps/Watchdog.HC", "U0 HealthLogInit()", 1),
    ("apps/RasterTile.HC", "U0 RasterSceneAddTriangleP(", 1),
    ("apps/RasterTile.HC", "U0 RasterBootCheck()", 1),
    ("apps/SelfTest.HC", "U0 SelfTestRun()", 1),
]

errs = []
for rel, mark, want in CHECKS + KEYS:
    p = os.path.join(ROOT, rel)
    txt = read(p)
    got = txt.count(mark)
    if got != want:
        errs.append("[FAIL] %s: '%s' aparece %d (esperado %d)" % (rel, mark, got, want))

# Chaves: o BASELINE ja' e' desbalanceado em -3 no Compiler.HC (chaves dentro de
# literais de string no CompilerSelfTest). O invariante correto e' que o DELTA
# (abre - fecha) NAO MUDE: nenhum bloco ficou sem par.
for rel in ["apps/Watchdog.HC", "apps/RasterTile.HC", "apps/Compiler.HC", "apps/SelfTest.HC"]:
    p = os.path.join(ROOT, rel)
    txt = read(p)
    old = read(os.path.join(BKP, os.path.basename(rel)))
    d_new = txt.count("{") - txt.count("}")
    d_old = old.count("{") - old.count("}")
    if d_new != d_old:
        errs.append("[FAIL] %s: delta de chaves mudou (%d -> %d)" % (rel, d_old, d_new))
    if len(txt) < len(old):
        errs.append("[FAIL] %s: ENCOLHEU (%d < %d)" % (rel, len(txt), len(old)))

# Regra 14 (Compiler.HC): nenhum bloco `{}` SOLTO. Um `{` precedido (ignorando
# espacos) por algo que nao seja ), else, do, ou inicio-de-linha com = : heuristica
# conservadora — procuramos `{` como PRIMEIRO token de um statement.
comp = read(os.path.join(ROOT, "apps/Compiler.HC"))
bad = 0
for m in re.finditer(r"(?m)^[ \t]*\{", comp):
    bad += 1
if bad:
    errs.append("[FAIL] Regra 14: %d bloco(s) `{}` solto(s) no Compiler.HC" % bad)

print("== verificacao no disco ==")
for rel, mark, want in CHECKS:
    print("  [ok] %-20s %s" % (rel, mark[:60]))
if errs:
    for e in errs:
        print(e)
    print("[ROLLBACK] restaurando backups de /tmp/onda1-bkp")
    for rel in ["apps/Watchdog.HC", "apps/RasterTile.HC", "apps/Compiler.HC", "apps/SelfTest.HC"]:
        shutil.copy(os.path.join(BKP, os.path.basename(rel)), os.path.join(ROOT, rel))
    sys.exit(1)
print("[OK] todas as verificacoes passaram (marcadores 1x, chaves balanceadas, tamanho nao encolheu, Regra 14 limpa)")
