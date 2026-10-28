#!/usr/bin/env python3
# Splice verificado do bloco P3A (JIT de shaders) em apps/ShaderVM.HC.
# Protocolo obrigatorio: ancora derivada dos bytes, marcadores 1x, chaves
# balanceadas, funcoes-chave presentes, tamanho nao encolheu, backup + restore.
import os, re, shutil, sys

ROOT = "/var/minis/workspace/merge/work"
TGT = os.path.join(ROOT, "apps/ShaderVM.HC")
BLK = os.path.join(ROOT, "apps/_svjit_block.hc")
BAK = "/tmp/ShaderVM.HC.bak3a"

src = open(TGT, "r").read()
blk = open(BLK, "r").read()
open(BAK, "w").write(src)
n0 = len(src)

def fail(msg):
    shutil.copy(BAK, TGT)
    print("SPLICE FAIL:", msg, "-> restaurado")
    sys.exit(1)

ANCHOR = "// ==============================================================================\n// Type routing + render entry.\n"
if src.count(ANCHOR) != 1:
    fail("ancora Type routing != 1 (count=%d)" % src.count(ANCHOR))

DISP_OLD = """U0 ShaderVMQuad(CShaderCtx *ctx, F64 qx, F64 qy, F64 sx, F64 sy, F64 t) {
    I64 i = 0;"""
DISP_NEW = """U0 ShaderVMQuad(CShaderCtx *ctx, F64 qx, F64 qy, F64 sx, F64 sy, F64 t) {
    // P3A: se houver bloco JIT valido para o programa corrente, executa por
    // ponteiro de funcao (ShaderJitTryRun devolve 1). Caso contrario cai no
    // interpretador abaixo — que e o FALLBACK e nunca sai do binario.
    if (ShaderJitTryRun(ctx, qx, qy, sx, sy, t) != 0) return;
    I64 i = 0;"""
if src.count(DISP_OLD) != 1:
    fail("dispatch anchor != 1 (count=%d)" % src.count(DISP_OLD))

ST_OLD = """    g_sv_cur_type = -99;
    if (pass == total) doldoc_printf("SHADERVM: PASS (%lld/%lld)\\n", pass, total);"""
ST_NEW = """    // 8. P3A — JIT: o bloco emitido tem de reproduzir o interpretador pixel a pixel.
    g_sv_cur_type = -99;
    ShaderVMBuildProgram(SVB_SDF);
    ShaderJitCompile();
    total = total + 1;
    if (g_sv_jit_ok != 0 && g_sv_jit_words > 0) pass = pass + 1;
    I64 jmm = 0;
    I64 jink = 0;
    I64 jok = ShaderJitCompareGrid(60, &jmm, &jink);
    total = total + 1;
    if (jok != 0 && jmm == 0 && jink > 0) pass = pass + 1;

    // 9. FALLBACK explicito: JIT desligado -> o interpretador continua desenhando.
    ShaderJitSetEnabled(0);
    total = total + 1;
    if (g_sv_jit_ok == 0) pass = pass + 1;
    ShaderVMQuad(&g_sv_ctx[0], 0.5, 0.5, 0.01, 0.01, 0.0);
    total = total + 1;
    if ((g_sv_ctx[0].out[0] & 0x00FFFFFF) != 0) pass = pass + 1;
    ShaderJitSetEnabled(1);

    // 10. ganho medido (A/B no mesmo programa) — impresso no serial, nao assertado.
    I64 b_interp = 0;
    I64 b_jit = 0;
    ShaderJitBenchGrid(60, 1, &b_interp, &b_jit);
    doldoc_printf("[SVJIT] prog=%lld instr words=%lld compile=%lldus | grid60 interp=%lldms jit=%lldms\\n",
                  g_sv_prog_len / 4, g_sv_jit_words, g_sv_jit_us, b_interp, b_jit);

    g_sv_cur_type = -99;
    if (pass == total) doldoc_printf("SHADERVM: PASS (%lld/%lld)\\n", pass, total);"""
if src.count(ST_OLD) != 1:
    fail("selftest anchor != 1 (count=%d)" % src.count(ST_OLD))

out = src.replace(ANCHOR, blk + "\n" + ANCHOR, 1)
out = out.replace(DISP_OLD, DISP_NEW, 1)
out = out.replace(ST_OLD, ST_NEW, 1)

# --- verificacoes ---
if out.count("ShaderJitTryRun(ctx, qx, qy, sx, sy, t) != 0") != 1: fail("marcador tryrun")
if out.count("U0 ShaderJitCompile()") != 1: fail("ShaderJitCompile count")
if out.count("U0 ShaderVMStep1(") != 1: fail("ShaderVMStep1 count")
if out.count("I64 ShaderJitCompareGrid(") != 1: fail("CompareGrid count")
if out.count("I64 ShaderJitBenchGrid(") != 1: fail("BenchGrid count")
if out.count("U0 ShaderVMQuad(CShaderCtx") != 1: fail("ShaderVMQuad count")
if out.count("U0 ShaderVMSelfTest()") != 1: fail("SelfTest count")
if out.count("U0 ShaderVMRenderNode(") != 1: fail("RenderNode count")
if out.count("U0 ShaderRaymarchQuad(") != 1: fail("RaymarchQuad count")
if len(out) <= n0: fail("tamanho encolheu: %d -> %d" % (n0, len(out)))
b0 = src.count("{") - src.count("}")
b1 = out.count("{") - out.count("}")
if b0 != b1: fail("chaves desbalanceadas: %d -> %d" % (b0, b1))

open(TGT, "w").write(out)
print("SPLICE OK: %d -> %d bytes (+%d), brace delta %d == %d" % (n0, len(out), len(out)-n0, b0, b1))
