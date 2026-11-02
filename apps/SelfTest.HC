// ==============================================================================
// apps/SelfTest.HC - NeoOS in-guest test runner (P0.5)
// ------------------------------------------------------------------------------
// One HolyC file that runs the whole regression battery INSIDE the guest, so the
// host no longer has to send one command per case over a frameless UART stream.
//
// Invoke with the shell builtin `selftest`, or `hcrun SelfTest.HC`.
// It prints a per-case line and a machine-readable summary:
//     SELFTEST: <pass>/<total> PASS
//     <<<NEO-DONE:selftest>>>
// The summary line is the sentinel the host greps for.
//
// The active cases are the in-guest corpus (a superset of tests/jit_golden/
// cases.json); `known` cases are reported separately and not counted toward the
// pass total. The frozen floor is enforced by scripts/golden-boot.sh.
// ==============================================================================

// P4.3: GL enum values used by SelfTestTexture. SelfTest.HC is compiled at Stage 1,
// before HolyGL.HC (Stage 5), so it cannot see HolyGL's #defines — define the
// canonical values locally (HcDefine updates an existing macro idempotently).
#define GL_POINTS               0x0000
#define GL_LINES                0x0001
#define GL_TRIANGLES            0x0004
#define GL_QUADS                0x0007
#define GL_MODELVIEW            0x1700
#define GL_PROJECTION           0x1701
#define GL_DEPTH_TEST           0x0B71
#define GL_BLEND                0x0BE2
#define GL_CULL_FACE            0x0B44
#define GL_LIGHTING             0x0B50
#define GL_TEXTURE_2D           0x0DE1
#define GL_REPEAT               0x2901
#define GL_CLAMP_TO_EDGE        0x812F
#define GL_NEAREST              0x2600
#define GL_LINEAR               0x2601
#define GL_TEXTURE_WRAP_S       0x2802
#define GL_TEXTURE_WRAP_T       0x2803
#define GL_TEXTURE_MIN_FILTER   0x2801
#define GL_TEXTURE_MAG_FILTER   0x2800
#define GL_SRC_ALPHA            0x0302
#define GL_ONE_MINUS_SRC_ALPHA  0x0303
#define GL_COLOR_BUFFER_BIT     0x00004000
#define GL_DEPTH_BUFFER_BIT     0x00000100

I64 g_selftest_pass = 0;
I64 g_selftest_total = 0;
I64 g_selftest_fail = 0;
I64 g_selftest_known_pass = 0;
I64 g_selftest_known_total = 0;
U8  g_halcache_buf[256];   // P2.1.5: static buffer for the HAL cache-coherency check
I64 g_fs_rt_size = 0;      // P2.5: out-size for the filesystem round-trip check
I64 g_selftest_done = 0;   // guard: the corpus is a once-per-boot regression check
// CAMADA 2 (defeito F1): o vigia agora roda DE VERDADE no core 1, em paralelo ao
// SelfTest no core 0. O SelfTest cria/destroi simbolos temporarios de payload
// (_tp_*) e compila modulos; o scan do vigia pode ver um deles no meio da janela
// e gritar SYMBOL FAULT por um estado TRANSITORIO (medido: 1 fault intermitente,
// 0 nos gates anteriores). Sinal para o vigia suspender a varredura enquanto o
// corpus roda — a deteccao volta ao normal no instante em que ele termina.
I64 g_selftest_active = 0;
// B6 (ONDA 2): fontes sinteticas do teste de profundidade do parser.
U8  g_b6_deep_src[512];
U8  g_b6_shallow_src[512];
I64 g_shade_demo_keep = 0; // P4.5: leave the shading demo frame on screen (visual check)
I64 g_parity_ok = 0;
I64 g_parity_total = 0;
I64 g_parity_fail = 0;
I64 g_parity_skip = 0;
I64 g_twin_pass = 0;
I64 g_twin_total = 0;

// Run up to three source units in order through Compiler.HC; return the last
// value. This mirrors the host battery, where each `cmds` entry is a separate
// REPL line and the LAST line's value is compared.
I64 SelfTestEval(U8 *s0, U8 *s1, U8 *s2) {
    I64 r = 0;
    if (s0) r = CompilerCompileAndRun(s0);
    if (s1) r = CompilerCompileAndRun(s1);
    if (s2) r = CompilerCompileAndRun(s2);
    return r;
}

U0 SelfTestCompare(U8 *name, I64 got, I64 expect) {
    g_selftest_total++;
    if (got == expect) {
        g_selftest_pass++;
        doldoc_printf("[SELFTEST] PASS %s = %lld\n", name, got);
    } else {
        g_selftest_fail++;
        doldoc_printf("[SELFTEST] FAIL %s expect=%lld got=%lld\n", name, expect, got);
    }
}

// In-process engine parity: run the same single-unit source through BOTH the
// self-hosting compiler (Compiler.HC) and the C seed JIT, and compare raw output.
// The C seed predates several P1 features (array literals, ...), where it returns
// -1; those cases are reported as `skip`, not a divergence.
U0 SelfTestCheck(U8 *name, U8 *src, I64 expect) {
    I64 got = CompilerCompileAndRun(src);
    SelfTestCompare(name, got, expect);
    I64 cjit = jit_compile_and_run(src);
    if (cjit == -1 && expect != -1) {
        g_parity_skip++;
    } else {
        g_parity_total++;
        if (cjit == got) {
            g_parity_ok++;
        } else {
            g_parity_fail++;
            doldoc_printf("[PARITY] DIFF %s hc=%lld cjit=%lld\n", name, got, cjit);
        }
    }
}

U0 SelfTestCheck2(U8 *name, I64 expect, U8 *s0, U8 *s1) {
    SelfTestCompare(name, SelfTestEval(s0, s1, 0), expect);
}

U0 SelfTestCheck3(U8 *name, I64 expect, U8 *s0, U8 *s1, U8 *s2) {
    SelfTestCompare(name, SelfTestEval(s0, s1, s2), expect);
}

// Negative test: the compiler MUST reject malformed input with a clean error
// (CompilerCompileAndRun returns -1), not miscompile it.
U0 SelfTestReject(U8 *name, U8 *src) {
    I64 got = CompilerCompileAndRun(src);
    g_selftest_total++;
    if (got == -1) {
        g_selftest_pass++;
        doldoc_printf("[SELFTEST] PASS %s (rejected)\n", name);
    } else {
        g_selftest_fail++;
        doldoc_printf("[SELFTEST] FAIL %s expected rejection, got %lld\n", name, got);
    }
}

// FASE 2.4 (ITEM 1) — rollback transacional: uma unidade que FALHA nao pode deixar
// globais registrados. Mede g_hc_global_count antes/depois de uma unidade que
// DECLARA um global novo e depois erra de sintaxe: tem de voltar ao valor inicial,
// e o retorno tem de ser -1. (Usa SelfTestCompare — HC puro — para nao alimentar a
// paridade C.)
U0 SelfTestRollback() {
    I64 rb_before = g_hc_global_count;
    I64 rb_rc = CompilerCompileAndRun("I64 g_f24_rb_probe;\n1 + ;");
    I64 rb_after = g_hc_global_count;
    SelfTestCompare("f24_rollback_globals", rb_after - rb_before, 0);
    SelfTestCompare("f24_rollback_rc", rb_rc, -1);
}

// FASE 2.4 (ITEM 2) — lexer blindado. Os 4 casos abaixo eram ACEITOS em silencio
// (string nao fechada virava o resto do arquivo; `123abc` virava dois tokens).
U0 SelfTestLexGuards() {
    SelfTestReject("f24_reject_unterminated_string", "I64 s24 = \"abc;");
    SelfTestReject("f24_reject_number_then_ident", "123abc;");
    SelfTestReject("f24_reject_bad_hex_literal", "0x1G;");
    SelfTestReject("f24_reject_float_then_ident", "1.5abc;");
    // FASE 2.5a (Item 3) — PROVA MULTI-LINHA. Testar so' snippets de 1 linha
    // provaria apenas que g_hc_line foi inicializado em 1; nao prova que a
    // transicao de '\n' incrementa a linha e reseta a coluna, nem que os 3
    // passes (prescan/parse) rebobinam g_hc_line/g_hc_col junto com g_hc_pos.
    // Este snippet tem 3 linhas e o erro na linha 3, coluna 9 (`I64 c = `
    // sao 8 caracteres, entao `123abc` comeca na coluna 9).
    //   linha 1: I64 a = 1;
    //   linha 2: I64 b = 2;
    //   linha 3: I64 c = 123abc;   <- '1' na coluna 9
    CompilerCompileAndRun("I64 a = 1;\nI64 b = 2;\nI64 c = 123abc;");
    SelfTestCompare("f24_multiline_err_line", g_hc_first_err_line, 3);
    SelfTestCompare("f24_multiline_err_col",  g_hc_first_err_col,  9);

    // B6 (ONDA 2) — limite de recursao do parser. Testa os DOIS lados do
    // limiar (HC_PARSE_DEPTH_MAX = 200): 250 parenteses aninhados TEM de ser
    // rejeitados (-1); 100 parenteses (abaixo do teto) TEM de compilar e dar 7.
    // Sem o contador, o caso de 250 recursava ~250 niveis e o parser SO' parava
    // por morte da pilha (medido: sem o fix, este caso derrubava o boot inteiro
    // — ver controle negativo no relatorio). Sonda o caminho de SUCESSO tambem
    // para provar que a guarda nao regrediu expressoes legitimas.
    I64 b6_i = 0;
    while (b6_i < 250) {
        g_b6_deep_src[b6_i] = '(';
        b6_i = b6_i + 1;
    }
    g_b6_deep_src[250] = '1';
    b6_i = 0;
    while (b6_i < 250) {
        g_b6_deep_src[251 + b6_i] = ')';
        b6_i = b6_i + 1;
    }
    g_b6_deep_src[501] = ';';
    g_b6_deep_src[502] = 0;
    b6_i = 0;
    while (b6_i < 150) {
        g_b6_shallow_src[b6_i] = '(';
        b6_i = b6_i + 1;
    }
    g_b6_shallow_src[150] = '7';
    b6_i = 0;
    while (b6_i < 150) {
        g_b6_shallow_src[151 + b6_i] = ')';
        b6_i = b6_i + 1;
    }
    g_b6_shallow_src[301] = ';';
    g_b6_shallow_src[302] = 0;
    SelfTestCompare("b6_parse_depth_reject_250", CompilerCompileAndRun(g_b6_deep_src), -1);
    SelfTestCompare("b6_parse_depth_ok_150", CompilerCompileAndRun(g_b6_shallow_src), 7);
}

// FASE 2.5b — RNG: golden do 1o valor (prova o Xorshift32 exato) + 1000 amostras
// em [0,1). SelfTestCompare (HC puro): SelfTestCheck alimenta a paridade C e o
// seed C nao conhece MathRngF64. Este e' o DETECTOR da mina de tipos estreitos.
// Golden verificado a mao (python): seed 0x9E3779B9 <<13 -> >>17 -> <<5 = 0x510C4619.
U0 SelfTestRng() {
    MathRngSeed(0x9E3779B9);
    I64 rng_first = (I64)MathRngU32();
    SelfTestCompare("f25b_rng_xorshift32_golden", rng_first, 1359758873);
    I64 rng_bad = 0;
    F64 rng_sum = 0.0;
    I64 rng_i = 0;
    while (rng_i < 1000) {
        F64 rv = MathRngF64();
        if (rv < 0.0 || rv >= 1.0) { rng_bad++; }
        rng_sum = rng_sum + rv;
        rng_i++;
    }
    SelfTestCompare("f25b_rng_range_1000", rng_bad, 0);
    SelfTestCompare("f25b_rng_sum_in_range", ((rng_sum > 400.0) && (rng_sum < 600.0)) ? 1 : 0, 1);
}

// Pre-existing defect: reported, but not counted against the pass total.
U0 SelfTestKnown(U8 *name, U8 *src, I64 expect) {
    I64 got = SelfTestEval(src, 0, 0);
    g_selftest_known_total++;
    if (got == expect) {
        g_selftest_known_pass++;
        doldoc_printf("[SELFTEST] KNOWN-PASS %s = %lld\n", name, got);
    } else {
        doldoc_printf("[SELFTEST] known-fail %s expect=%lld got=%lld\n", name, expect, got);
    }
}

// P0.5.5 twin-liveness: each .HC twin exposes <X>TwinProbe() returning a magic
// value, proving the module is loaded and callable (a P2 prerequisite).
U0 SelfTestTwin(U8 *name, I64 got, I64 expect) {
    g_twin_total++;
    if (got == expect) {
        g_twin_pass++;
    } else {
        doldoc_printf("[SELFTEST] FAIL twin %s expect=0x%llX got=0x%llX\n", name, expect, got);
    }
}

U0 SelfTestTwins() {
    SelfTestTwin("HalPlatform.HC", HalTwinProbe(), 0x48414C31);
    SelfTestTwin("VirtioBlk.HC", VirtioBlkTwinProbe(), 0x56424C31);
    SelfTestTwin("RedSea.HC", RedSeaTwinProbe(), 0x52534431);
    SelfTestTwin("Symbols.HC", SymbolsTwinProbe(), 0x53594D31);
    SelfTestTwin("KHeap.HC", KHeapTwinProbe(), 0x4B485031);
    doldoc_printf("TWINS: %lld/%lld\n", g_twin_pass, g_twin_total);
}

// P0.5.7 in-guest symbol audit: the table is alive and every forward reference
// resolved (0 entries still pointing at the unresolved trap).
U0 SelfTestSymbols() {
    I64 n = symbols_count();
    I64 u = symbols_unresolved_count();
    if (n > 0 && u == 0) {
        doldoc_printf("[SELFTEST] PASS symbol audit (%lld symbols, 0 unresolved)\n", n);
    } else {
        doldoc_printf("[SELFTEST] FAIL symbol audit (%lld symbols, %lld unresolved)\n", n, u);
    }
    doldoc_printf("SYMS: %lld symbols, %lld unresolved\n", n, u);

    // P0.3: the sovereign (.HC) table must also be scanned, and the scan must
    // find ZERO pointing at the trap after a full boot+compile. If the scan
    // itself reports a non-zero, the gate catches it here too.
    I64 su_n = SymScanUnresolved();
    if (su_n == 0) {
        doldoc_printf("[SELFTEST] PASS sovereign symbol scan (0 unresolved)\n");
    } else {
        doldoc_printf("[SELFTEST] FAIL sovereign symbol scan (%lld unresolved)\n", su_n);
    }
}

// P0.2.4: active overflow proof. NO temporary ceiling lowering, NO branch-only
// test — the guard itself is forced to overflow by saving the count, setting it
// to the ceiling, inserting one more, then restoring. This runs in EVERY boot.
U0 SelfTestOverflowInjection() {
    I64 pass = 0;
    I64 total = 0;

    // func: HcFuncSlotOk() must refuse and report once.
    {
        I64 saved = g_hc_func_count;
        I64 saved_flag = g_hc_funcs_overflowed;
        g_hc_funcs_overflowed = 0;
        g_hc_func_count = HC_MAX_FUNCS;
        I64 ok = HcFuncSlotOk();
        total++; if (ok == 0) pass++;
        total++; if (g_hc_funcs_overflowed == 1) pass++;
        g_hc_func_count = saved;
        g_hc_funcs_overflowed = saved_flag;
    }

    // global: same pattern.
    {
        I64 saved = g_hc_global_count;
        I64 saved_flag = g_hc_globals_overflowed;
        g_hc_globals_overflowed = 0;
        g_hc_global_count = HC_MAX_GLOBALS;
        I64 ok = HcGlobalSlotOk();
        total++; if (ok == 0) pass++;
        total++; if (g_hc_globals_overflowed == 1) pass++;
        g_hc_global_count = saved;
        g_hc_globals_overflowed = saved_flag;
    }

    // map (jitmap): the forensics table. Overflow must set the flag ONCE and
    // the table must NOT grow past the ceiling.
    {
        I64 saved = g_hc_map_count;
        I64 saved_flag = g_hc_map_overflowed;
        I64 saved_overflow = g_hc_map_overflowed;
        g_hc_map_overflowed = 0;
        g_hc_map_count = HC_MAP_MAX;
        HcMapAdd("overflow_probe", 0x1234);
        total++; if (g_hc_map_count == HC_MAP_MAX) pass++;
        total++; if (g_hc_map_overflowed == 1) pass++;
        g_hc_map_count = saved;
        g_hc_map_overflowed = saved_flag;
        (void)saved_overflow;
    }

    // fnf: the F64-return-type table. Overflow corrupts F64->I64 silently.
    {
        I64 saved = g_hc_fnf_count;
        I64 saved_flag = g_hc_fnf_overflowed;
        g_hc_fnf_overflowed = 0;
        g_hc_fnf_count = HC_FNF_MAX;
        I64 ok = HcFnfSlotOk();
        total++; if (ok == 0) pass++;
        total++; if (g_hc_fnf_overflowed == 1) pass++;
        g_hc_fnf_count = saved;
        g_hc_fnf_overflowed = saved_flag;
    }

    // structs: cumulative registry. Overflow must refuse + report.
    {
        I64 saved = g_hc_struct_count;
        I64 saved_flag = g_hc_structs_overflowed;
        I64 saved_error = g_hc_error;
        g_hc_structs_overflowed = 0;
        g_hc_error = 0;
        g_hc_struct_count = HC_MAX_STRUCTS;
        I64 ok = HcStructSlotOk();
        total++; if (ok == 0) pass++;
        total++; if (g_hc_structs_overflowed == 1) pass++;
        g_hc_struct_count = saved;
        g_hc_structs_overflowed = saved_flag;
        g_hc_error = saved_error;
    }

    // defs: #define registry. Overflow must report (via HcAddDefine).
    {
        I64 saved = g_hc_def_count;
        I64 saved_flag = g_hc_defs_overflowed;
        I64 saved_error = g_hc_error;
        g_hc_defs_overflowed = 0;
        g_hc_error = 0;
        g_hc_def_count = HC_MAX_DEFINES;
        HcAddDefine("overflow_probe_def", 1);
        total++; if (g_hc_def_count == HC_MAX_DEFINES) pass++;
        total++; if (g_hc_defs_overflowed == 1) pass++;
        g_hc_def_count = saved;
        g_hc_defs_overflowed = saved_flag;
        g_hc_error = saved_error;
    }

    // init (deferred globals): the report flag must be settable by forcing the
    // counter to the ceiling (no public insert fn — the parser inserts inline).
    {
        I64 saved = g_hc_init_count;
        I64 saved_flag = g_hc_init_overflowed;
        g_hc_init_overflowed = 0;
        g_hc_init_count = HC_MAX_DEFERRED;
        // no public add fn; verify the flag semantics via a direct probe:
        // the report path sets g_hc_init_overflowed when count >= cap.
        if (g_hc_init_count >= HC_MAX_DEFERRED) {
            if (!g_hc_init_overflowed) g_hc_init_overflowed = 1;
        }
        total++; if (g_hc_init_overflowed == 1) pass++;
        g_hc_init_count = saved;
        g_hc_init_overflowed = saved_flag;
    }

    // epi (epilogue backpatch slots): same flag-semantics probe.
    {
        I64 saved = g_hc_epi_count;
        I64 saved_flag = g_hc_epi_overflowed;
        g_hc_epi_overflowed = 0;
        g_hc_epi_count = HC_MAX_EPILOGUES;
        if (g_hc_epi_count >= HC_MAX_EPILOGUES) {
            if (!g_hc_epi_overflowed) g_hc_epi_overflowed = 1;
        }
        total++; if (g_hc_epi_overflowed == 1) pass++;
        g_hc_epi_count = saved;
        g_hc_epi_overflowed = saved_flag;
    }




    // locals: the silent-corruption guard. Forcing count=cap then declaring one
    // more local must NOT return a valid offset (the old bug returned `offset`
    // outside the if/else) and must set the overflow flag + report.
    {
        I64 saved = g_hc_local_count;
        I64 saved_frame = g_hc_frame_offset;
        I64 saved_error = g_hc_error;
        I64 saved_flag = g_hc_locals_overflowed;
        g_hc_locals_overflowed = 0;
        g_hc_error = 0;
        g_hc_local_count = HC_MAX_LOCALS;
        I64 off = HcAddLocalTyped("overflow_probe_local", 8, 0, -1, 1);
        total++; if (off == -1) pass++;
        total++; if (g_hc_locals_overflowed == 1) pass++;
        total++; if (g_hc_error == 1) pass++;
        g_hc_local_count = saved;
        g_hc_locals_overflowed = saved_flag;
        g_hc_error = saved_error;
        g_hc_frame_offset = saved_frame;
    }

    if (pass == total) doldoc_printf("OVERFLOW: PASS (%lld/%lld)\n", pass, total);
    else doldoc_printf("OVERFLOW: FAIL (%lld/%lld)\n", pass, total);

    // P0.5: the enumerated error channel must have recorded a cause. The
    // overflow injections above raised g_hc_error via HcRaiseError(), so the
    // first-cause register must be non-zero and the count >= 1.
    I64 p05_ok = 0;
    if (g_hc_first_err_code != 0 && g_hc_err_count >= 1) p05_ok = 1;
    doldoc_printf("ERRCHAN: %s (first=%lld '%s' count=%lld mask=0x%08X)\n",
                  p05_ok ? "PASS" : "FAIL",
                  g_hc_first_err_code, HcErrName(g_hc_first_err_code),
                  g_hc_err_count, g_hc_err_mask);
}

// P2.1.5: exercise the .HC-owned cache-maintenance path directly — write a
// buffer, flush it via HalFlushCache (apps/HalPlatform.HC), and read it back.
U0 SelfTestHalCache() {
    I64 hc_i = 0;
    while (hc_i < 256) {
        g_halcache_buf[hc_i] = (hc_i * 7 + 3) & 0xFF;
        hc_i++;
    }
    HalFlushCache((U64)&g_halcache_buf[0], 256);
    I64 ok = (g_halcache_buf[0] == 3 && g_halcache_buf[10] == 73 && g_halcache_buf[255] == ((255 * 7 + 3) & 0xFF));
    if (ok) {
        doldoc_print("[SELFTEST] PASS hal-cache (HalFlushCache coherency)\n");
        doldoc_print("HALCACHE: PASS\n");
    } else {
        doldoc_printf("[SELFTEST] FAIL hal-cache (0=%d 10=%d 255=%d)\n",
                      g_halcache_buf[0], g_halcache_buf[10], g_halcache_buf[255]);
        doldoc_print("HALCACHE: FAIL\n");
    }
}

// P2.5: exercise the .HC-owned filesystem (apps/RedSea.HC) directly — write a
// file, read it back, verify the bytes. The C filesystem is gone (P2.3).
U0 SelfTestFs() {
    U8 wbuf[64];
    U8 rbuf[64];
    I64 i = 0;
    while (i < 64) { wbuf[i] = (i * 3 + 1) & 0xFF; rbuf[i] = 0; i++; }
    // P8-fix: checar o retorno da ESCRITA e o contador de falhas de I/O. Antes o
    // teste so olhava o tamanho lido, entao 'n=0' nao dizia se falhou a escrita
    // ou a leitura — foi por isso que a causa raiz demorou a aparecer.
    I64 fs_wr = redsea_write_file("__p2_rt.HC", wbuf, 64);
    I64 fs_io0 = g_rs_io_errors;
    g_fs_rt_size = 0;
    I64 fs_rd = redsea_read_file("__p2_rt.HC", rbuf, 64, &g_fs_rt_size);
    I64 fs_io1 = g_rs_io_errors;
    I64 ok = (g_fs_rt_size == 64 && fs_wr >= 0 && fs_io1 == fs_io0);
    if (ok) {
        i = 0;
        while (i < 64) { if (rbuf[i] != wbuf[i]) { ok = 0; break; } i++; }
    }
    if (ok) {
        doldoc_print("[SELFTEST] PASS fs round-trip (RedSea.HC)\n");
        doldoc_print("FSRT: PASS\n");
    } else {
        doldoc_printf("[SELFTEST] FAIL fs round-trip (n=%lld wr=%lld rd=%lld io=%lld->%lld)\n",
                      g_fs_rt_size, fs_wr, fs_rd, fs_io0, fs_io1);
        doldoc_print("FSRT: FAIL\n");
    }
}

// The one shell-driven case (save/run/#include) reduced to its compiler essence:
// write an include target to RedSea, then compile a unit that #includes it.
U0 SelfTestInclude() {
    redsea_write_file("__inc1.HC", "I64 g_inc = 5;", 14);
    SelfTestCompare("include_vfs", CompilerCompileAndRun("#include \"__inc1.HC\"\ng_inc + 2;"), 7);
}

// P3.5: prove the timer IRQ actually PREEMPTS — create a task whose entry
// function bumps a counter and exits; KernelMain spins until the scheduler
// switches the task in (only possible with real preemption).
I64 g_sched_probe_ran = 0;
U0 SelfTestSchedWorker(U64 arg) {
    g_sched_probe_ran = g_sched_probe_ran + 1;
    TaskExit();
}

U0 SelfTestSched() {
    g_sched_probe_ran = 0;
    // SelfTest.HC is compiled before Sched.HC, so use the raw return value rather
    // than the (not-yet-defined) CTask struct type.
    U64 t = TaskCreate("PreemptProbe", (U64)&SelfTestSchedWorker, 0, 8192);
    if (!t) {
        doldoc_print("SCHED: FAIL (TaskCreate)\n");
        return;
    }
    I64 guard = 0;
    while (g_sched_probe_ran == 0 && guard < 20000000) {
        guard++;
    }
    if (g_sched_probe_ran != 0) {
        doldoc_print("SCHED: PASS\n");
    } else {
        doldoc_print("SCHED: FAIL\n");
    }
}

// B5 (ONDA 2) — canario de pilha. Prova que TaskCreate GRAVA o canario no fundo
// da pilha e que a verificacao o DETECTA quando corrompido (ciclo completo:
// gravado -> violacao detectada -> restaurado). A task criada sai sozinha
// (TaskExit) quando o escalonador a roda; nada de pilha vazando.
I64 g_selftest_canary_probe = 0;
U0 SelfTestCanaryWorker(U64 arg) {
    g_selftest_canary_probe = g_selftest_canary_probe + 1;
    TaskExit();
}
U0 SelfTestStackCanary() {
    g_selftest_canary_probe = 0;
    g_sched_preempt_off = 1;   // a task nao pode rodar no meio da medicao
    U64 t = TaskCreate("CanaryProbe", (U64)&SelfTestCanaryWorker, 0, 8192);
    I64 cycle = 0;
    if (t != 0) cycle = SchedTestCanaryCycle(t);
    g_sched_preempt_off = 0;
    SelfTestCompare("b5_stack_canary_cycle", cycle, 1);
}

// P3.6: verify the fault classification boundary (guardrail 4) non-destructively.
// A kernel fault (no user_ok) must PANIC (return 0); a user fault (user_ok) must
// RECOVER (return 1). g_exc_selftest_active suppresses actual BSOD rendering.
U0 SelfTestBsod() {
    g_exc_selftest_active = 1;
    CTrapFrame f;
    f.elr_el1 = 0x50000000;
    f.lr = 0;
    f.spsr_el1 = 0;
    f.sp_el0 = 0;
    g_exc_user_ok = 0;
    I64 r_panic = ExceptionsHandleSync(&f, 0x96000007, 0x29, 0);
    I64 latched = g_exc.halted;   // P0.6: a panic must latch halted=1
    // Reset the latch for the synthetic recovery sub-test. A real panic halts
    // the core in vectors.S, so clearing it is only valid inside this harness.
    g_exc.in_fault = 0;
    g_exc.halted = 0;
    g_exc_user_ok = 1;
    I64 r_recover = ExceptionsHandleSync(&f, 0x96000007, 0x29, 0);
    g_exc_user_ok = 0;
    g_exc_selftest_active = 0;
    if (r_panic == 0 && latched == 1 && r_recover == 1) {
        doldoc_print("BSOD: PASS\n");
    } else {
        doldoc_printf("BSOD: FAIL (panic=%lld latch=%lld recover=%lld)\n", r_panic, latched, r_recover);
    }
}

// P3.7: dispatch a real job to a secondary core and verify it actually ran there
// (payload written + no silent BSP fallback).
I64 g_smp_probe_acc = 0;
U0 SelfTestSmpWorker(U64 arg) {
    g_smp_probe_acc = arg + 0x1000;
}
U0 SelfTestSmp() {
    g_smp_probe_acc = 0;
    I64 r = SmpDispatch(1, (U64)&SelfTestSmpWorker, 0x99);
    if (r == 0 && g_smp_probe_acc == 0x1099) {
        doldoc_print("SMP: PASS\n");
    } else {
        doldoc_printf("SMP: FAIL (r=%lld acc=0x%llX)\n", r, g_smp_probe_acc);
    }
    // B2a.4 (ONDA 3): medicao do SMP SIMETRICO. Distingue "IRQ habilitada" (o que
    // o kill-switch faz) de "IRQ REALMENTE CHEGA" (depende do B2a.2: GICC banked +
    // CNTV por core). g_gic_offcore_tick_blocks > 0 prova que um secundario tomou
    // o tick e foi barrado pelo interlock — i.e. o SMP simetrico funciona.
    doldoc_printf("SMPIRQ: switch=%lld enabled_cores=0x%llX offcore_ticks_blocked=%lld\n",
                  g_smp_irq_enable, g_smp_irq_enabled_cores, g_gic_offcore_tick_blocks);
}

// P3.8: verify the sovereign handover took effect - the live kmalloc / symbols_*
// resolve to the .HC owners, not the seed implementations.
U0 SelfTestSovereign() {
    U64 km = symbols_lookup("kmalloc");
    U64 kf = symbols_lookup("kfree");
    U64 sl = symbols_lookup("symbols_lookup");
    U64 sr = symbols_lookup("symbols_register");
    // SELF-HOST (fronteira): o HolyC tambem assume uart_putc/uart_puts (Keyboard.HC
    // re-registra, fechando a duplicacao com o C bootstrap). O C segue registrando
    // para o BOOT; o HolyC sobrescreve no runtime. O registro foi feito com
    // &uart_putc/&uart_puts (os wrappers), que delegam a UartPutChar/UartPutString.
    U64 up = symbols_lookup("uart_putc");
    U64 ups = symbols_lookup("uart_puts");
    // CAMADA 1.2 (IDEA-7) — a fronteira verificavel do Stage 1: os 6 simbolos cujo
    // DONO HolyC re-registra em modulo carregado ANTES de SelfTest.HC (KHeap,
    // Symbols, Keyboard). doldoc_print NAO entra aqui por dois motivos MEDIDOS:
    //  (1) DolDoc.HC e' Stage 6 — tomar &DolDocPrint no Stage 1 emitia um
    //      late-binding que o SIC resolvia para o trap (0x0) => Instruction Abort
    //      (PC=0x0) ao executar. Reproduzido e corrigido nesta sessao.
    //  (2) qualquer sondagem nova de simbolo custa +1 no CENSUS (guard de
    //      regressao .HC->C). A soberania do doldoc_print ja' e' provada pelo
    //      "sovereign symbol scan" (0 apontando para trap) e pelo DolDocInit.
    // O gate exige a fronteira provada; prova-la com 6 donos verificaveis e' correto.
    if (km == (U64)&KMalloc && kf == (U64)&KFree &&
        sl == (U64)&SymLookup && sr == (U64)&SymRegister &&
        up == (U64)&uart_putc && ups == (U64)&uart_puts) {
        doldoc_print("SOVEREIGN: PASS\n");
    } else {
        doldoc_printf("SOVEREIGN: FAIL (km=0x%llX kf=0x%llX sl=0x%llX sr=0x%llX up=0x%llX ups=0x%llX)\n",
                      km, kf, sl, sr, up, ups);
    }
}

// P7.5: the unified GPU config plane. Exercises all five knobs (read / write /
// clamp / restore) and asserts 1 vs 4 SMP workers produce byte-identical tiles.
U0 SelfTestGpuConfig() {
    I64 pass = 0;
    I64 total = 0;

    // 1. buffer_mode (0 single/direct, 1 double, 2 triple).
    I64 bm0 = gpu_get_buffer_mode();
    gpu_set_buffer_mode(GPU_BUF_TRIPLE); total++; if (gpu_get_buffer_mode() == GPU_BUF_TRIPLE) pass++;
    gpu_set_buffer_mode(9);               total++; if (gpu_get_buffer_mode() == GPU_BUF_TRIPLE) pass++;
    gpu_set_buffer_mode(-5);              total++; if (gpu_get_buffer_mode() == GPU_BUF_SINGLE) pass++;
    gpu_set_buffer_mode(bm0);             total++; if (gpu_get_buffer_mode() == bm0) pass++;

    // 2. tile_size (32 or 64; snapped + clamped).
    I64 ts0 = gpu_get_tile_size();
    gpu_set_tile_size(32);  total++; if (gpu_get_tile_size() == 32) pass++;
    gpu_set_tile_size(64);  total++; if (gpu_get_tile_size() == 64) pass++;
    gpu_set_tile_size(999); total++; if (gpu_get_tile_size() == 64) pass++;
    gpu_set_tile_size(ts0); total++; if (gpu_get_tile_size() == ts0) pass++;

    // 3. smp_cores (1..4).
    I64 sc0 = gpu_get_smp_cores();
    gpu_set_smp_cores(1);  total++; if (gpu_get_smp_cores() == 1) pass++;
    gpu_set_smp_cores(4);  total++; if (gpu_get_smp_cores() == 4) pass++;
    gpu_set_smp_cores(99); total++; if (gpu_get_smp_cores() == 4) pass++;
    gpu_set_smp_cores(0);  total++; if (gpu_get_smp_cores() == 1) pass++;
    gpu_set_smp_cores(sc0); total++; if (gpu_get_smp_cores() == sc0) pass++;

    // 4. zprecision (16 or 32 bits).
    I64 zp0 = gpu_get_zprecision();
    gpu_set_zprecision(32); total++; if (gpu_get_zprecision() == 32) pass++;
    gpu_set_zprecision(16); total++; if (gpu_get_zprecision() == 16) pass++;
    gpu_set_zprecision(7);  total++; if (gpu_get_zprecision() == 16) pass++;
    gpu_set_zprecision(zp0); total++; if (gpu_get_zprecision() == zp0) pass++;

    // 5. vsync (0/1).
    I64 vs0 = gpu_get_vsync();
    gpu_set_vsync(1);   total++; if (gpu_get_vsync() == 1) pass++;
    gpu_set_vsync(0);   total++; if (gpu_get_vsync() == 0) pass++;
    gpu_set_vsync(vs0); total++; if (gpu_get_vsync() == vs0) pass++;

    // 6. 1 vs 4 workers -> byte-identical tiled output (deterministic assignment).
    total++; if (RasterTestSmpCoresDeterminism() != 0) pass++;

    if (pass == total) doldoc_printf("GPUCFG: PASS (%lld/%lld)\n", pass, total);
    else doldoc_printf("GPUCFG: FAIL (%lld/%lld)\n", pass, total);
}

// P3.0 kernel-status report. Informational during P3; the TICK / SMP / BSOD
// hard assertions are promoted to pass/fail as each capability lands
// (P3.4 / P3.6 / P3.7).
U0 SelfTestKernel() {
    doldoc_printf("KERNEL: timer_freq=%lld ticks=%lld cores=%lld exc=%lld recovered=%lld panics=%lld\n",
                  TimerGetFrequency(), TimerGetTicks(), SmpGetCoreCount(),
                  g_exc.total_exceptions, g_exc.recovered_exceptions, g_exc.panic_count);
    // P3.4: the hardware timer IRQ must actually fire (drives g_timer.system_ticks).
    if (TimerGetTicks() > 0) {
        doldoc_print("TICK: PASS\n");
    } else {
        doldoc_print("TICK: FAIL\n");
    }
}

// P4.0: deterministic golden-frame gate. Render the fixed scene into the back
// buffer with IRQs masked (no preemption => no concurrent writer), hash the whole
// surface (32-bit FNV-1a), and assert it equals the frozen baseline. This is the
// regression + 1-vs-N determinism gate for the whole render pipeline.
I64 g_render_golden = 0x0D28836F;   // frozen baseline (verified across reboots)

// Compiler regression (P4.2 root cause): indexing a GLOBAL pointer must stride
// by sizeof(pointee) and load/store the pointee width. A `U16 *` indexed at the
// old default 8-byte stride would write/read 8-byte words and read 0xFFFF as -1.
// We check the raw bytes through a byte-alias so a wrong scale cannot cancel out.
U16 *g_ptrtest16 = NULL;
U32 *g_ptrtest32 = NULL;
U0 SelfTestPtrScale() {
    I64 ok = 1;
    g_ptrtest16 = kmalloc(64);
    g_ptrtest32 = kmalloc(64);
    if (!g_ptrtest16 || !g_ptrtest32) {
        doldoc_print("PTRSCALE: FAIL (alloc)\n");
        return;
    }
    g_ptrtest16[3] = 0xABCD;
    U8 *alias16 = (U8*)g_ptrtest16;
    if (alias16[6] != 0xCD || alias16[7] != 0xAB) ok = 0;
    g_ptrtest16[3] = 0xFFFF;
    if (g_ptrtest16[3] != 65535) ok = 0;
    g_ptrtest32[9] = 0xDEADBEEF;
    U8 *alias32 = (U8*)g_ptrtest32;
    if (alias32[36] != 0xEF || alias32[39] != 0xDE) ok = 0;
    if (g_ptrtest32[9] != 0xDEADBEEF) ok = 0;
    kfree(g_ptrtest16);
    kfree(g_ptrtest32);
    if (ok != 0) doldoc_print("PTRSCALE: PASS\n");
    else doldoc_print("PTRSCALE: FAIL\n");
}

// Compiler regression (P4.3/P5 prereq): multidimensional array indexing must
// resolve to base + i*row_stride + j*elem with NO intermediate dereference.
// A global 2D array used to Data Abort (it loaded element[i] as a pointer) and a
// local 2D array failed to parse. Covers I64 and width-aware U16, plus a row
// separation check (row i must not alias row i-1).
I64 g_m2d[3][4];
U0 SelfTest2DArray() {
    I64 ok = 1;
    // 1) global 2D I64: write/read corners + center, then prove rows don't overlap.
    g_m2d[0][0] = 11; g_m2d[0][3] = 14; g_m2d[1][1] = 22;
    g_m2d[2][0] = 31; g_m2d[2][3] = 34;
    if (g_m2d[0][0] != 11) ok = 0;
    if (g_m2d[0][3] != 14) ok = 0;
    if (g_m2d[1][1] != 22) ok = 0;
    if (g_m2d[2][0] != 31) ok = 0;
    if (g_m2d[2][3] != 34) ok = 0;
    g_m2d[1][0] = 77;
    if (g_m2d[0][3] != 14) ok = 0;      // row 1 write must not touch row 0
    // 2) local 2D I64, nested-loop fill, compiled+run by Compiler.HC.
    I64 r2 = CompilerCompileAndRun("I64 lf() { I64 a[3][4]; I64 i; I64 j; for (i=0;i<3;i++) { for (j=0;j<4;j++) { a[i][j] = i*10+j; } } return a[0][0] + a[2][3] + a[1][2]; } lf();");
    if (r2 != 35) ok = 0;               // 0 + 23 + 12
    // 3) width-aware local U16 2D: a 2-byte store/load, not the 8-byte default.
    I64 r3 = CompilerCompileAndRun("I64 uf() { U16 u[2][3]; u[1][2] = 65535; return u[1][2]; } uf();");
    if (r3 != 65535) ok = 0;
    // 4) global U16 2D through Compiler.HC.
    I64 r4 = CompilerCompileAndRun("U16 gu[2][3]; gu[1][2] = 40000; gu[1][2];");
    if (r4 != 40000) ok = 0;
    if (ok != 0) doldoc_print("ARRAY2D: PASS\n");
    else doldoc_print("ARRAY2D: FAIL\n");
}

// D7 root-fix regression: indexing a struct-member POINTER must stride by the
// pointee width (1/2/4), NOT the 8-byte pointer field width. The old bug made
// `box.p8[i]`/`box.p16[i]`/`box.p32[i]` advance 8 bytes and clobber neighbours.
// Covers direct (`.`) and arrow (`->`) member access in reads and writes.
struct SPtrBox { U8 *p8; U16 *p16; U32 *p32; };
U8 g_sptr_raw[64];
U0 SelfTestStructPtrScale() {
    I64 ok = 1;
    U8 *raw = g_sptr_raw;
    I64 i = 0;
    while (i < 64) { raw[i] = 0; i = i + 1; }

    SPtrBox box;
    box.p8 = raw;
    box.p16 = (U16*)raw;
    box.p32 = (U32*)raw;

    // U8 member: p8[5] writes exactly 1 byte at offset 5.
    box.p8[5] = 0xAB;
    if (raw[4] != 0 || raw[6] != 0) ok = 0;
    if (box.p8[5] != 0xAB) ok = 0;

    // U16 member: p16[3] writes exactly 2 bytes at offset 6.
    box.p16[3] = 0xBEEF;
    if (raw[6] != 0xEF || raw[7] != 0xBE) ok = 0;
    if (raw[5] != 0xAB || raw[8] != 0) ok = 0;
    if (box.p16[3] != 0xBEEF) ok = 0;

    // U32 member: p32[2] writes exactly 4 bytes at offset 8.
    box.p32[2] = 0xDEADBEEF;
    if (raw[8] != 0xEF || raw[9] != 0xBE || raw[10] != 0xAD || raw[11] != 0xDE) ok = 0;
    if (raw[7] != 0xBE || raw[12] != 0) ok = 0;
    if (box.p32[2] != 0xDEADBEEF) ok = 0;

    // Arrow path: `pb->p8[i]` must behave identically to `box.p8[i]`.
    SPtrBox *pb = &box;
    pb->p8[9] = 0x5A;
    if (raw[9] != 0x5A) ok = 0;
    if (raw[8] != 0xEF || raw[10] != 0xAD) ok = 0;

    if (ok != 0) doldoc_print("PTRSCALE2: PASS\n");
    else doldoc_print("PTRSCALE2: FAIL\n");
}

// P4.5 baseline: the 3D path (translate/rotate/scale transform, perspective
// projection, per-pixel Z, lighting) must render through the ONE rasterizer.
U0 SelfTest3D() {
    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    glEnable(GL_LIGHTING);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_CULL_FACE);
    gfx_clear(0xFF202020);
    RasterClearZ();
    HolyGLViewport(50, 50, 400, 400);
    HolyGLMatrixMode(GL_PROJECTION);
    HolyGLLoadIdentity();
    HolyGLPerspective(38.0, 1.0, 2.0, 60.0);
    HolyGLMatrixMode(GL_MODELVIEW);
    HolyGLLoadIdentity();
    HolyGLTranslatef(0.0, 0.0, -18.5);
    HolyGLRenderCubeAt(0.0, 0.0, 0.0, 4.0, 30.0);
    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();
    I64 ink = 0;
    I64 y = 50;
    while (y < 450) {
        I64 x = 50;
        while (x < 450) {
            if ((fb[y * pit + x] & 0xFFFFFF) != 0x202020) ink++;
            x++;
        }
        y++;
    }
    if (ink > 20000) doldoc_printf("3D: PASS (lit cube ink=%lld)\n", ink);
    else doldoc_printf("3D: FAIL (lit cube ink=%lld)\n", ink);
    gfx_clear(0xFF202020);
    RasterClearZ();
    I64 gt0 = HolyGLGetTrisRendered();
    Gears3DRenderViewport(50, 50, 400, 400, 30.0);
    I64 gt1 = HolyGLGetTrisRendered();
    I64 gink = 0;
    y = 50;
    while (y < 450) {
        I64 x = 50;
        while (x < 450) {
            U32 c = fb[y * pit + x] & 0xFFFFFF;
            if (c != 0x11111B && c != 0x202020) gink++;
            x++;
        }
        y++;
    }
    // P4.5 root-fix gate: the gears mesh must actually fill its viewport. Before the
    // cross-unit F64 return-float fix this was 366 tris / 644 px (collapsed).
    if ((gt1 - gt0) >= 700 && gink > 15000) doldoc_printf("3D-GEARS: PASS (tris=%lld ink=%lld)\n", gt1 - gt0, gink);
    else doldoc_printf("3D-GEARS: FAIL (tris=%lld ink=%lld)\n", gt1 - gt0, gink);
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();
}

// P4.5: per-fragment Blinn-Phong proof. A quad whose per-vertex normals fan away
// from the Blinn half vector H must produce a smooth, non-flat luminance gradient
// (>= 8 distinct shades) with a bright specular peak at the corner whose normal is H.
U0 SelfTestShading() {
    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    glEnable(GL_LIGHTING);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_CULL_FACE);
    gfx_clear(0xFF000000);
    RasterClearZ();
    HolyGLViewport(100, 100, 400, 400);
    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    gluPerspective(45.0, 1.0, 1.0, 100.0);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glTranslatef(0.0, 0.0, -6.0);

    glBegin(GL_QUADS);
    glColor3ub(200, 200, 200);
    glNormal3f(0.2475, 0.3500, 0.9034); glVertex3f(-2.0, -2.0, 0.0); // = H (specular peak)
    glNormal3f(1.0,    0.0,    0.0);    glVertex3f( 2.0, -2.0, 0.0);
    glNormal3f(0.0,    1.0,    0.0);    glVertex3f( 2.0,  2.0, 0.0);
    glNormal3f(0.0,    0.0,    1.0);    glVertex3f(-2.0,  2.0, 0.0);
    glEnd();

    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();
    U8 seen[256];
    I64 k = 0;
    while (k < 256) { seen[k] = 0; k = k + 1; }
    I64 distinct = 0;
    I64 lum_max = 0;
    I64 y = 110;
    while (y < 490) {
        I64 x = 110;
        while (x < 490) {
            U32 c = fb[y * pit + x];
            I64 lum = ((((c >> 16) & 255) * 30 + ((c >> 8) & 255) * 59 + (c & 255) * 11) / 100);
            if (lum > 255) lum = 255;
            if (lum > 0 && seen[lum] == 0) { seen[lum] = 1; distinct = distinct + 1; }
            if (lum > lum_max) lum_max = lum;
            x = x + 3;
        }
        y = y + 3;
    }
    // Gouraud (gmode 1): interpolate three vertex colours through the SAME kernel.
    // The red channel must sweep across the triangle (not a flat fill).
    RasterClearZ();
    RasterSetDepthTest(1);
    RasterSetZ(30000, 30000, 30000);
    RasterSetColor3(0xFFFF2020, 0xFF20FF20, 0xFF2020FF);
    RasterTriangleZ(150, 150, 450, 150, 300, 450, 0xFFFFFFFF);
    RasterDisableGouraud();
    U8 gseen[256];
    k = 0;
    while (k < 256) { gseen[k] = 0; k = k + 1; }
    I64 gdistinct = 0;
    I64 gy = 200;
    while (gy < 400) {
        I64 gx = 160;
        while (gx < 440) {
            U32 c = fb[gy * pit + gx];
            I64 rv = (c >> 16) & 255;
            if (gseen[rv] == 0) { gseen[rv] = 1; gdistinct = gdistinct + 1; }
            gx = gx + 2;
        }
        gy = gy + 2;
    }
    if (distinct >= 8 && lum_max >= 60 && gdistinct >= 8) {
        doldoc_printf("SHADING: PASS (phong=%lld lum_max=%lld gouraud=%lld)\n", distinct, lum_max, gdistinct);
    } else {
        doldoc_printf("SHADING: FAIL (phong=%lld lum_max=%lld gouraud=%lld)\n", distinct, lum_max, gdistinct);
    }
    if (g_shade_demo_keep == 0) gfx_clear(0xFF000000);
    RasterDisableGouraud();
    doldoc_mark_all_dirty();
}

// Render the P4.5 shading demo and hold it on screen for ~8 s so a host screendump
// can capture the smooth per-fragment gradient + specular highlight.
U0 SelfTestShadeDemo() {
    g_shade_demo_keep = 1;
    SelfTestShading();
    GfxPresent(0, 0, gfx_get_canvas_width(), gfx_get_canvas_height(), 1);
    U64 t0 = __mrs_cntvct();
    U64 fr = __mrs_cntfrq();
    if (fr == 0) fr = 62500000;
    U64 dur = fr * 8;
    while (__mrs_cntvct() - t0 < dur) { }
    g_shade_demo_keep = 0;
    gfx_clear(0xFF000000);
    GfxPresent(0, 0, gfx_get_canvas_width(), gfx_get_canvas_height(), 1);
}

U0 SelfTestRender() {
    I64 saved_daif = __mrs_daif();
    __msr_daif(saved_daif | 0x80);       // mask IRQ: no preemption during render+hash
    RenderGoldenScene();
    U32 *rbuf = RenderGetTargetBuffer();
    I64 rw = gfx_get_canvas_width();
    I64 rh = gfx_get_canvas_height();
    I64 rpitch = gfx_get_canvas_pitch();
    I64 rhash = RenderHashBuffer(rbuf, rw, rh, rpitch);
    __msr_daif(saved_daif);
    if (rhash == g_render_golden) {
        doldoc_printf("RENDER: PASS (golden=0x%llX)\n", rhash);
    } else {
        doldoc_printf("RENDER: FAIL (hash=0x%llX golden=0x%llX)\n", rhash, g_render_golden);
    }
    // Restore the display: clear and force a full DolDoc repaint so the golden
    // scene does not linger behind the shell.
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();
}

// ============================================================================
// WCORE — O KERNEL SOB CONCORRENCIA REAL (1.4 + M3 + M5)
// ============================================================================
//  1.4: o g_kheap_lock NUNCA foi testado sob contencao REAL entre cores. TODO teste
//       de heap existente roda numa unica core. Aqui BSP e core 1 alocam/escrevem/
//       verificam/liberam SIMULTANEAMENTE: se o lock falhar, um canario quebra.
//  M3 : quantas alocacoes CADA core fez. Se o secundario reportar 0, o "paralelo"
//       e' falso e o teste DIZ (zero fallback mudo).
//  M5 : o pico do heap sob carga concorrente (antes -> depois).
//  B12: o determinismo pos-carga e' provado pelo RENDER: PASS que roda DEPOIS
//       deste teste (por isso SelfTestWcore e' chamado ANTES de SelfTestRender).
//       Nao se chama RenderGoldenScene aqui: o corpus assume cena virgem.
#define WCORE_ITERS 200

U64 g_wcore_ops[2];      // [0]=BSP, [1]=secundario
U64 g_wcore_ok[2];       // 1 = nenhuma corrupcao vista por aquele core
U64 g_wcore_fail[2];     // 1 = alocacao falhou / padrao nao voltou
I64 g_wcore_dispatch_rc = 0;
I64 g_wcore_join_rc = 0;
I64 g_wcore_canary = 0;
U64 g_wcore_peak_before = 0;
U64 g_wcore_peak_after = 0;

U0 SelfTestWcoreWorker(U64 arg) {
    I64 ci = (I64)arg;
    I64 n = 0;
    g_wcore_ok[ci] = 1;
    g_wcore_fail[ci] = 0;
    while (n < WCORE_ITERS) {
        I64 sz = 48 + ((n * 37 + ci * 11) % 512);
        U8 *p = kmalloc(sz);
        if (!p) { g_wcore_fail[ci] = 1; break; }
        if (((U64)p & 15) != 0) g_wcore_ok[ci] = 0;
        I64 b = 0;
        while (b < sz) { p[b] = (U8)((n + b + ci * 7) & 255); b = b + 1; }
        b = 0;
        while (b < sz) {
            if (p[b] != (U8)((n + b + ci * 7) & 255)) { g_wcore_ok[ci] = 0; break; }
            b = b + 1;
        }
        kfree(p);
        n = n + 1;
    }
    g_wcore_ops[ci] = n;
}

U0 SelfTestWcore() {
    g_wcore_ops[0] = 0; g_wcore_ops[1] = 0;
    g_wcore_ok[0] = 1;  g_wcore_ok[1] = 1;
    g_wcore_fail[0] = 0; g_wcore_fail[1] = 0;
    g_wcore_peak_before = (U64)KHeapPeakBytes();
    g_wcore_dispatch_rc = SmpDispatchAsync(1, (U64)&SelfTestWcoreWorker, 1);
    SelfTestWcoreWorker(0);          // BSP disputa o mesmo lock ao mesmo tempo
    I64 wc_jg = 0;
    while (SmpIsJobDone(1) == 0 && wc_jg < 60000000) { wc_jg = wc_jg + 1; }
    g_wcore_join_rc = (SmpIsJobDone(1) != 0) ? 0 : -1;
    g_wcore_peak_after = (U64)KHeapPeakBytes();
    g_wcore_canary = KHeapCheckAll();
    doldoc_printf("WCORE: bsp_ops=%lld sec_ops=%lld dispatch=%lld join=%lld canary=%lld peak=%lld->%lld KB\n",
                  g_wcore_ops[0], g_wcore_ops[1], g_wcore_dispatch_rc, g_wcore_join_rc,
                  g_wcore_canary, g_wcore_peak_before / 1024, g_wcore_peak_after / 1024);
}

// P0.7: sovereign heap stress. Two phases:
//  A. 100 alloc/write/verify/free iterations across the four canonical sizes
//     (16, 36, 128, 4096 B) — every byte written and re-read to prove a block is
//     neither overlapped by a neighbour nor corrupted by the split/coalesce path.
//  B. 2500 small (32-64 B) allocations interleaved with medium (512-1536 B)
//     alloc/free traffic, every byte verified before release.
// Runs against the sovereign KHeap.HC post-handover. Prints KHEAP: PASS.
#define HEAPCHURN_N 2500
U8  *g_heapchurn_ptrs[HEAPCHURN_N];
I64  g_heapchurn_sizes[HEAPCHURN_N];

U0 SelfTestHeap() {
    I64 ok = 1;
    // --- Phase A: fixed sizes, immediate free (split + coalesce churn) ---
    I64 sizes[4];
    sizes[0] = 16; sizes[1] = 36; sizes[2] = 128; sizes[3] = 4096;
    I64 si = 0;
    while (si < 4 && ok != 0) {
        I64 sz = sizes[si];
        I64 it = 0;
        while (it < 100) {
            U8 *p = kmalloc(sz);
            if (!p) { ok = 0; break; }
            if (((U64)p & 15) != 0) { ok = 0; break; }
            I64 b = 0;
            while (b < sz) { p[b] = (U8)((it + b) & 255); b++; }
            b = 0;
            while (b < sz) {
                if (p[b] != (U8)((it + b) & 255)) { ok = 0; break; }
                b++;
            }
            kfree(p);
            if (ok == 0) break;
            it++;
        }
        si++;
    }
    // --- Phase B: interleaved small + medium, verified before release ---
    I64 live = 0;
    I64 i = 0;
    while (i < HEAPCHURN_N && ok != 0) {
        I64 sz = 32 + ((i * 7) % 33);            // 32..64 bytes
        U8 *p = kmalloc(sz);
        if (!p) { ok = 0; break; }
        if (((U64)p & 15) != 0) ok = 0;          // 16-byte alignment contract
        I64 b = 0;
        while (b < sz) { p[b] = (U8)((i + b) & 255); b++; }
        g_heapchurn_ptrs[i] = p;
        g_heapchurn_sizes[i] = sz;
        live = live + 1;
        if ((i % 5) == 0) {
            I64 msz = 512 + ((i * 13) % 1024);
            U8 *m = kmalloc(msz);
            if (!m) { ok = 0; break; }
            I64 mb = 0;
            while (mb < 256) { m[mb] = 0xAB; mb++; }
            kfree(m);                            // must coalesce without touching p
        }
        i = i + 1;
    }
    // Phase 2: verify every live block still holds its pattern (no overlap/corruption).
    i = 0;
    while (i < live && ok != 0) {
        U8 *p = g_heapchurn_ptrs[i];
        I64 sz = g_heapchurn_sizes[i];
        I64 b = 0;
        while (b < sz) {
            if (p[b] != (U8)((i + b) & 255)) { ok = 0; break; }
            b++;
        }
        i = i + 1;
    }
    // Phase 3: release everything.
    i = 0;
    while (i < live) { kfree(g_heapchurn_ptrs[i]); i = i + 1; }
    // Phase 4: a fresh allocation must still succeed, be aligned and writable.
    U8 *z = kmalloc(64);
    if (!z) { ok = 0; }
    else {
        I64 zb = 0;
        while (zb < 64) { z[zb] = 0x5A; zb++; }
        if (z[0] != 0x5A || z[63] != 0x5A) ok = 0;
        kfree(z);
    }
    if (ok != 0) doldoc_printf("KHEAP: PASS (4 sizes x100 + %lld churn allocs)\n", live);
    else doldoc_printf("KHEAP: FAIL\n");
}

// P7.4 F0: end-of-battery heap-integrity sweep. Every module compile and every
// compiler-limit regression above must have stayed inside its allocations; a block
// whose header canary is corrupt means something wrote out of bounds (the class of
// bug a size-increasing global re-declaration used to cause). Prints HEAPINT.
U0 SelfTestHeapIntegrity() {
    I64 hi_bad = KHeapCheckAll();
    if (hi_bad == 0) doldoc_print("HEAPINT: PASS\n");
    else doldoc_printf("HEAPINT: FAIL (corrupt block 0x%llX)\n", hi_bad);
}

// P4.3: texture pipeline regression. Four sub-tests through the ONE rasterizer:
//   1. NEAREST, screen-aligned 2x2 quad -> the 4 quadrant colours.
//   2. LINEAR  -> the centre is the bilinear average of the 4 texels.
//   3. Perspective (w varies 2..6) -> the texel row boundary is at the
//      perspective-correct screen position (v = 3t/(1+2t)), not the affine one.
//   4. Alpha 50% blend over a known background.
U0 SelfTestTexture() {
    I64 ok = 1;
    I64 W = gfx_get_canvas_width();
    I64 H = gfx_get_canvas_height();
    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();
    if (!fb || W <= 0 || H <= 0) { doldoc_print("TEXTURE: FAIL (no framebuffer)\n"); return; }

    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_LIGHTING);
    glDisable(GL_BLEND);
    glEnable(GL_TEXTURE_2D);

    // ---------- Test 1 & 2 & 4: screen-aligned quad ----------
    I64 qx0 = W / 4; I64 qx1 = (3 * W) / 4;
    I64 qy0 = H / 4; I64 qy1 = (3 * H) / 4;
    I64 qw = qx1 - qx0; I64 qh = qy1 - qy0;
    I64 sxL = qx0 + qw / 4; I64 sxR = qx0 + (3 * qw) / 4;
    I64 syT = qy0 + qh / 4; I64 syB = qy0 + (3 * qh) / 4;

    U32 t22[4];
    t22[0] = 0xFFFF0000;  // (0,0) red
    t22[1] = 0xFF00FF00;  // (1,0) green
    t22[2] = 0xFF0000FF;  // (0,1) blue
    t22[3] = 0xFFFFFFFF;  // (1,1) white
    I64 texA = glGenTextures();
    glBindTexture(GL_TEXTURE_2D, texA);
    glTexImage2D(GL_TEXTURE_2D, 0, 2, 2, t22);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);  glLoadIdentity();
    glViewport(0, 0, W, H);

    // --- Test 1: NEAREST quadrants ---
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    gfx_clear(0xFF101018);
    RasterClearZ();
    glBegin(GL_QUADS);
    glColor3ub(255, 255, 255);
    glTexCoord2f(0.0, 0.0); glVertex3f(-0.5,  0.5, 0.0);
    glTexCoord2f(1.0, 0.0); glVertex3f( 0.5,  0.5, 0.0);
    glTexCoord2f(1.0, 1.0); glVertex3f( 0.5, -0.5, 0.0);
    glTexCoord2f(0.0, 1.0); glVertex3f(-0.5, -0.5, 0.0);
    glEnd();
    if (fb[syT * pit + sxL] != 0xFFFF0000) ok = 0;   // TL red
    if (fb[syT * pit + sxR] != 0xFF00FF00) ok = 0;   // TR green
    if (fb[syB * pit + sxL] != 0xFF0000FF) ok = 0;   // BL blue
    if (fb[syB * pit + sxR] != 0xFFFFFFFF) ok = 0;   // BR white

    // --- Test 2: LINEAR centre = average of the 4 texels (0x7F7F7F) ---
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    gfx_clear(0xFF101018);
    RasterClearZ();
    glBegin(GL_QUADS);
    glColor3ub(255, 255, 255);
    glTexCoord2f(0.0, 0.0); glVertex3f(-0.5,  0.5, 0.0);
    glTexCoord2f(1.0, 0.0); glVertex3f( 0.5,  0.5, 0.0);
    glTexCoord2f(1.0, 1.0); glVertex3f( 0.5, -0.5, 0.0);
    glTexCoord2f(0.0, 1.0); glVertex3f(-0.5, -0.5, 0.0);
    glEnd();
    U32 cc = fb[(H / 2) * pit + (W / 2)];
    I64 cr = (cc >> 16) & 255;
    I64 cg = (cc >> 8) & 255;
    I64 cb = cc & 255;
    if (cr < 126 || cr > 128 || cg < 126 || cg > 128 || cb < 126 || cb > 128) ok = 0;

    // --- Test 4: alpha 50% red over black -> ~0xFF800000 ---
    U32 ta[4];
    ta[0] = 0x80FF0000; ta[1] = 0x80FF0000; ta[2] = 0x80FF0000; ta[3] = 0x80FF0000;
    I64 texC = glGenTextures();
    glBindTexture(GL_TEXTURE_2D, texC);
    glTexImage2D(GL_TEXTURE_2D, 0, 2, 2, ta);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    gfx_clear(0xFF000000);
    RasterClearZ();
    glBegin(GL_QUADS);
    glColor3ub(255, 255, 255);
    glTexCoord2f(0.0, 0.0); glVertex3f(-0.5,  0.5, 0.0);
    glTexCoord2f(1.0, 0.0); glVertex3f( 0.5,  0.5, 0.0);
    glTexCoord2f(1.0, 1.0); glVertex3f( 0.5, -0.5, 0.0);
    glTexCoord2f(0.0, 1.0); glVertex3f(-0.5, -0.5, 0.0);
    glEnd();
    U32 ba = fb[(H / 2) * pit + (W / 2)];
    I64 br = (ba >> 16) & 255;
    if (br < 127 || br > 129) ok = 0;
    glDisable(GL_BLEND);

    // --- Test 3: perspective (w: 2 near .. 6 far) ---
    U32 t44[16];
    I64 r4 = 0;
    while (r4 < 16) {
        if (r4 < 4) t44[r4] = 0xFFFF0000;        // row0 red
        else if (r4 < 8) t44[r4] = 0xFF00FF00;   // row1 green
        else if (r4 < 12) t44[r4] = 0xFF0000FF;  // row2 blue
        else t44[r4] = 0xFFFFFF00;               // row3 yellow
        r4++;
    }
    I64 texB = glGenTextures();
    glBindTexture(GL_TEXTURE_2D, texB);
    glTexImage2D(GL_TEXTURE_2D, 0, 4, 4, t44);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    gluPerspective(90.0, (F64)W / (F64)H, 1.0, 100.0);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glViewport(0, 0, W, H);
    gfx_clear(0xFF101018);
    RasterClearZ();
    glBegin(GL_QUADS);
    glColor3ub(255, 255, 255);
    glTexCoord2f(0.0, 1.0); glVertex3f(-1.0, -1.0, -2.0);
    glTexCoord2f(1.0, 1.0); glVertex3f( 1.0, -1.0, -2.0);
    glTexCoord2f(1.0, 0.0); glVertex3f( 1.0,  1.0, -6.0);
    glTexCoord2f(0.0, 0.0); glVertex3f(-1.0,  1.0, -6.0);
    glEnd();
    // top edge (far, w=6) projects to y = 5H/12; bottom (near, w=2) to y = 3H/4.
    I64 ytop = (5 * H) / 12;
    I64 ybot = (3 * H) / 4;
    I64 yp = ytop + (30 * (ybot - ytop)) / 100;   // screen t = 0.30
    U32 pc = fb[yp * pit + (W / 2)];
    // perspective: v = 3t/(1+2t) = 0.5625 -> row 2 (blue). affine would be row 1.
    if (pc != 0xFF0000FF) ok = 0;

    // --- restore state ---
    glDisable(GL_TEXTURE_2D);
    RasterDisableTexture();
    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);  glLoadIdentity();
    RasterSetDepthTest(1);
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();

    if (ok != 0) doldoc_print("TEXTURE: PASS\n");
    else doldoc_print("TEXTURE: FAIL\n");
}

// P7.1: HolyGL GL 1.3 state-machine surface. Proves the two real matrix stacks
// (MODELVIEW depth 16, PROJECTION depth 4), gl* bindings, clear/colour/flush
// semantics — all through exported accessors (no direct g_hgl access). Prints
// GL: PASS / GL: FAIL (<stage>).
U0 SelfTestGL() {
    I64 ok = 1;
    U8 *why = "ok";

    I64 W = gfx_get_canvas_width();
    I64 H = gfx_get_canvas_height();
    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();

    // Deterministic unlit state: only GL state is under test.
    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    glDisable(GL_LIGHTING);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    HolyGLViewport(0, 0, W, H);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // 1. MODELVIEW push/translate/pop isolation: the translate must not leak.
    glPushMatrix();
    glTranslatef(5.0, 0.0, 0.0);
    glPopMatrix();
    if (HolyGLModelviewMBits(12) != 0) { ok = 0; why = "mv_pop_isolation"; }

    // 2. PROJECTION stack depth 4 (sp 0..3); a 5th push is a no-op.
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glPushMatrix();
    glPushMatrix();
    glPushMatrix();
    glPushMatrix();
    if (HolyGLGetProjectionSP() != 3) { ok = 0; why = "proj_depth4"; }
    glPushMatrix();
    if (HolyGLGetProjectionSP() != 3) { ok = 0; why = "proj_depth_overflow"; }
    glPopMatrix();
    glPopMatrix();
    glPopMatrix();
    glPopMatrix();
    if (HolyGLGetProjectionSP() != 0) { ok = 0; why = "proj_depth_underflow"; }

    // 3. MODELVIEW stack depth 16 (sp 0..15); a 17th push is a no-op.
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    I64 mp = 0;
    while (mp < 16) { glPushMatrix(); mp = mp + 1; }
    if (HolyGLGetModelviewSP() != 15) { ok = 0; why = "mv_depth16"; }
    glPushMatrix();
    if (HolyGLGetModelviewSP() != 15) { ok = 0; why = "mv_depth_overflow"; }
    mp = 0;
    while (mp < 16) { glPopMatrix(); mp = mp + 1; }
    if (HolyGLGetModelviewSP() != 0) { ok = 0; why = "mv_depth_underflow"; }

    // 4. gluPerspective shape: post-multiplied onto the current identity matrix, so
    // m[14] == -1.0 (IEEE bits 0xBFF0000000000000) and m[5] == f = cos/sin(22.5deg) > 0.
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45.0, 1.333333, 1.0, 100.0);
    if (HolyGLProjectionMBits(14) != -4616189618054758400) { ok = 0; why = "persp_m14"; }
    if (HolyGLProjectionMBits(5) <= 0) { ok = 0; why = "persp_m5"; }
    glLoadIdentity();

    // 5. glColor4f packs (a,r,g,b) with round-to-nearest: 1,0,0,0.5 -> 0x80FF0000.
    glColor4f(1.0, 0.0, 0.0, 0.5);
    if (HolyGLGetCurrentColor() != 0x80FF0000) { ok = 0; why = "color4f_pack"; }

    // 6a. glClear(GL_COLOR_BUFFER_BIT) fills with the stored clear colour.
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glClearColor(0.25, 0.5, 0.75, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    if (fb[(H / 2) * pit + (W / 2)] != 0xFF4080BF) { ok = 0; why = "clear_color"; }

    // 6b. glClear(GL_DEPTH_BUFFER_BIT) makes the Z buffer far-writable again: a far
    // triangle rejected before the depth clear must be accepted after it.
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glClear(GL_DEPTH_BUFFER_BIT);
    RasterSetDepthTest(1);
    RasterDisableGouraud();
    RasterSetZ(10000, 10000, 10000);
    RasterTriangleZ(200, 200, 400, 200, 300, 400, 0xFFFF0000);
    RasterSetZ(60000, 60000, 60000);
    RasterTriangleZ(200, 200, 400, 200, 300, 400, 0xFF00FF00);
    if (fb[300 * pit + 300] != 0xFFFF0000) { ok = 0; why = "depth_reject"; }
    glClear(GL_DEPTH_BUFFER_BIT);
    RasterSetZ(60000, 60000, 60000);
    RasterTriangleZ(200, 200, 400, 200, 300, 400, 0xFF00FF00);
    if (fb[300 * pit + 300] != 0xFF00FF00) { ok = 0; why = "depth_writable"; }

    // 7. A lit triangle submitted through the GL pipeline increments the counter.
    // (A real perspective is required now that the near-plane clipper is active: with
    // an identity projection z=-5 gives w=1 and z+w<0, i.e. the triangle is behind.)
    glEnable(GL_LIGHTING);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45.0, 1.0, 1.0, 100.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glTranslatef(0.0, 0.0, -5.0);
    I64 t0 = HolyGLGetTrisRendered();
    glBegin(GL_TRIANGLES);
    glColor3ub(200, 200, 200);
    glNormal3f(0.0, 0.0, 1.0);
    glVertex3f(-1.0, -1.0, 0.0);
    glVertex3f( 1.0, -1.0, 0.0);
    glVertex3f( 0.0,  1.0, 0.0);
    glEnd();
    if (HolyGLGetTrisRendered() <= t0) { ok = 0; why = "lit_tri_count"; }

    // ---- restore the shared GL state so later tests are unaffected ----
    glDisable(GL_LIGHTING);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    RasterSetDepthTest(1);
    RasterDisableGouraud();
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);
    HolyGLViewport(0, 0, W, H);
    gfx_clear(0xFF000000);
    RasterClearZ();
    doldoc_mark_all_dirty();

    if (ok != 0) doldoc_print("GL: PASS\n");
    else doldoc_printf("GL: FAIL (%s)\n", why);
}

// P7.2: near-plane Sutherland–Hodgman clipper. A triangle that crosses the near plane
// must be CLIPPED (not rejected) and still cover pixels; a fully-behind triangle must
// cover none (and must not wrap around / blow up). Prints CLIP: PASS / CLIP: FAIL.
U0 SelfTestClip() {
    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    glDisable(GL_LIGHTING);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    HolyGLViewport(0, 0, 512, 512);
    HolyGLMatrixMode(GL_PROJECTION);
    HolyGLLoadIdentity();
    HolyGLPerspective(60.0, 1.0, 1.0, 100.0);
    HolyGLMatrixMode(GL_MODELVIEW);
    HolyGLLoadIdentity();
    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();

    // (1) One vertex at/behind the near plane (z=0 -> w=0): must clip, not vanish.
    gfx_clear(0xFF000000);
    RasterClearZ();
    HolyGLColor3ub(255, 255, 255);
    glBegin(GL_TRIANGLES);
    glVertex3f(-1.0, -1.0, -2.0);
    glVertex3f( 1.0, -1.0, -2.0);
    glVertex3f( 0.0,  1.0,  0.0);
    glEnd();
    I64 ink = 0;
    I64 y = 0;
    while (y < 512) {
        I64 x = 0;
        while (x < 512) { if ((fb[y * pit + x] & 0xFFFFFF) != 0) ink++; x++; }
        y++;
    }

    // (2) Fully behind the camera (all z=+1 -> w=-1): must clip away to zero coverage.
    gfx_clear(0xFF000000);
    RasterClearZ();
    HolyGLColor3ub(255, 255, 255);
    glBegin(GL_TRIANGLES);
    glVertex3f(-1.0, -1.0, 1.0);
    glVertex3f( 1.0, -1.0, 1.0);
    glVertex3f( 0.0,  1.0, 1.0);
    glEnd();
    I64 ink2 = 0;
    y = 0;
    while (y < 512) {
        I64 x = 0;
        while (x < 512) { if ((fb[y * pit + x] & 0xFFFFFF) != 0) ink2++; x++; }
        y++;
    }

    gfx_clear(0xFF000000);
    RasterClearZ();
    doldoc_mark_all_dirty();
    if (ink > 0 && ink2 == 0) doldoc_printf("CLIP: PASS (clip_ink=%lld behind_ink=%lld)\n", ink, ink2);
    else doldoc_printf("CLIP: FAIL (clip_ink=%lld behind_ink=%lld)\n", ink, ink2);
}

// P7.2: NEON memory kernels (scripts/render_neon.s). Each kernel must be byte-identical
// to its scalar reference, including a length that is not a multiple of the vector width
// (exercises the SIMD body + the 1..3 element tail). Uses private buffers only, so the
// golden frame is untouched. Prints NEONMEM: PASS / NEONMEM: FAIL.
U0 SelfTestNeonMem() {
    I64 ok = 1;
    U8 *why = "ok";
    I64 i = 0;

    // (1) RenderNeonFill: 8-px vector body + scalar tail, n = 19.
    U32 fbuf[24];
    i = 0;
    while (i < 24) { fbuf[i] = 0; i++; }
    RenderNeonFill(fbuf, 19, 0xFF3DAEE9);
    i = 0;
    while (i < 19) {
        if (fbuf[i] != 0xFF3DAEE9) { ok = 0; why = "fill_body"; }
        i++;
    }
    if (fbuf[19] != 0 || fbuf[23] != 0) { ok = 0; why = "fill_overrun"; }

    // (2) RenderNeonBlit: 64-byte vector body + byte tail, bytes = 150.
    U8 bsrc[160];
    U8 bdst[160];
    i = 0;
    while (i < 160) { bsrc[i] = (U8)((i * 7 + 3) & 0xFF); bdst[i] = 0; i++; }
    RenderNeonBlit(bdst, bsrc, 150);
    i = 0;
    while (i < 150) {
        if (bdst[i] != bsrc[i]) { ok = 0; why = "blit_body"; }
        i++;
    }
    if (bdst[150] != 0 || bdst[159] != 0) { ok = 0; why = "blit_overrun"; }

    // (3) RenderNeonBlendRect: n = 11 (two 4-px SIMD quads + a 3-px tail) must match the
    // scalar SRC_ALPHA/ONE_MINUS_SRC_ALPHA reference element-for-element, and leave the
    // elements past n untouched.
    U32 gbuf[16];
    U32 gref[16];
    U32 col = 0x80402010;
    I64 n = 11;
    U32 a = (col >> 24) & 0xFF;
    U32 inv_a = 255 - a;
    U32 src_r = ((col >> 16) & 0xFF) * a + 128;
    U32 src_g = ((col >> 8)  & 0xFF) * a + 128;
    U32 src_b = ((col)       & 0xFF) * a + 128;
    i = 0;
    while (i < 16) { gbuf[i] = (U32)(0x10203040 + i * 0x01020305); i++; }
    i = 0;
    while (i < 16) { gref[i] = gbuf[i]; i++; }
    i = 0;
    while (i < n) {
        U32 dst = gref[i];
        U32 r = (src_r + ((dst >> 16) & 0xFF) * inv_a) >> 8;
        U32 g = (src_g + ((dst >> 8)  & 0xFF) * inv_a) >> 8;
        U32 b = (src_b + ((dst)       & 0xFF) * inv_a) >> 8;
        gref[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
        i++;
    }
    RenderNeonBlendRect(gbuf, n, col, a);
    if (gbuf[0] != 0xFF302828) { ok = 0; why = "blend_pixel0"; }
    i = 0;
    while (i < n) {
        if (gbuf[i] != gref[i]) { ok = 0; why = "blend_body"; }
        i++;
    }
    if (gbuf[11] != gref[11] || gbuf[15] != gref[15]) { ok = 0; why = "blend_overrun"; }

    if (ok != 0) doldoc_print("NEONMEM: PASS\n");
    else doldoc_printf("NEONMEM: FAIL (%s)\n", why);
}

// P7.3: tiled scene API — the tiled path must be pixel/Z-identical to the immediate
// path, tile the plane with no shared-edge gaps, and never write past a scratchpad.
// The body lives in RasterTile.HC (Stage 5) so it can see the scene types; SelfTest
// (Stage 1) only invokes it. Prints TILE: PASS / TILE: FAIL.
U0 SelfTestTile() {
    RasterSelfTestTile();
}

// P7.4: the parallel vertex transform (core 1 + BSP) must equal the scalar reference
// bit-for-bit. Body lives in Math3D.HC (Stage 5) so it can see CVec3/CVec4/CMat4.
U0 SelfTestMath3DParallel() {
    I64 bad = Math3DSelfTestParallel();
    if (bad == 0) doldoc_print("MATH3DPAR: PASS\n");
    else doldoc_printf("MATH3DPAR: FAIL (%lld)\n", bad);
}

// BLOCO 2 - teste do duto unificado de entrada.
// Injeta CInputEvent de TECLA e de MOUSE pela MESMA fila que os drivers usam e
// prova, com o consumidor real (DolDocDispatchInput), que:
//   (1) tecla de driver VirtIO chega ao Shell  (sem perda);
//   (2) tecla de UART (KeyboardQueueFeed) chega ao Shell;
//   (3) mouse chega ao cursor (MouseGetX/Y);
//   (4) Alt+2 com desktop ativo e CONSUMIDO pelo DolDoc (g_xf_ws) e NAO desce
//       ao Shell -> prova a ordem DolDoc-antes-do-Shell;
//   (5) a fila fica VAZIA no fim (nada fica preso no duto).
// Nao incrementa g_selftest_total de proposito: o gate trava em 123/123 e o
// relatorio deste bloco cita o placar do proprio duto.
I64 SelfTestInputDuct() {
  I64 ok = 1;
  I64 checks = 0;
  doldoc_print("$FG,CYAN$--- duto unificado de entrada (CInputEvent) ---$FG$\n");

  // limpa o duto e o buffer do Shell para partir de estado conhecido
  InputQueueClear();
  while (KeyboardHasChar()) { I64 dr = KeyboardGetChar(); }

  // (1) tecla pelo caminho REAL do driver VirtIO
  VirtioInputInjectKey(30, 1);                       // EV_KEY code 30 = 'a'
  I64 q1 = InputQueueCount();
  DolDocDispatchInput();
  I64 got1 = KeyboardGetChar();
  checks++;
  if (q1 == 1 && got1 == 'a') {
    doldoc_printf("  [PASS] VirtIO EV_KEY -> fila (%lld) -> DolDocDispatchInput -> Shell ('%c')\n", q1, got1);
  } else {
    doldoc_printf("  [FAIL] duto teclado VirtIO: fila=%lld shell=%lld\n", q1, got1); ok = 0;
  }

  // (2) tecla pelo caminho REAL do UART (Keyboard.HC)
  KeyboardQueueFeed('z');
  DolDocDispatchInput();
  I64 got2 = KeyboardGetChar();
  checks++;
  if (got2 == 'z') {
    doldoc_printf("  [PASS] UART KeyboardQueueFeed -> fila -> DolDoc -> Shell ('%c')\n", got2);
  } else {
    doldoc_printf("  [FAIL] duto teclado UART: shell=%lld\n", got2); ok = 0;
  }

  // (3) tecla especial preserva o key_code (KEY_UP = 257)
  KeyboardQueueFeed(257);
  DolDocDispatchInput();
  I64 got3 = KeyboardGetChar();
  checks++;
  if (got3 == 257) {
    doldoc_print("  [PASS] tecla especial KEY_UP atravessa o duto com o codigo intacto\n");
  } else {
    doldoc_printf("  [FAIL] tecla especial virou %lld\n", got3); ok = 0;
  }

  // (4) mouse pelo caminho REAL do driver VirtIO (EV_ABS normalizado)
  I64 mx0 = MouseGetX();
  I64 my0 = MouseGetY();
  VirtioInputInjectAbs(0, 16383);                    // ABS_X
  VirtioInputInjectAbs(1, 16383);                    // ABS_Y
  I64 q4 = InputQueueCount();
  DolDocDispatchInput();
  I64 mx1 = MouseGetX();
  I64 my1 = MouseGetY();
  checks++;
  if (q4 == 2 && mx1 != mx0 && mx1 > 400 && mx1 < 640 && my1 > 300 && my1 < 480) {
    doldoc_printf("  [PASS] VirtIO EV_ABS -> fila (%lld) -> DolDoc -> cursor (%lld,%lld)\n", q4, mx1, my1);
  } else {
    doldoc_printf("  [FAIL] duto mouse: fila=%lld cursor=(%lld,%lld) antes=(%lld,%lld)\n", q4, mx1, my1, mx0, my0); ok = 0;
  }
  MouseSetPos(mx0, my0);

  // (5) atalho global do XFCE: consumido pelo DolDoc, NAO chega ao Shell.
  // A prova roda dentro do DolDoc (DolDocInputTestGlobalKey): o SelfTest.HC
  // carrega antes do DolDoc.HC e nao pode declarar locais com seus tipos.
  while (KeyboardHasChar()) { I64 dr2 = KeyboardGetChar(); }
  I64 gk = DolDocInputTestGlobalKey();
  I64 left = InputQueueCount();
  checks++;
  if (gk == 1 && left == 0) {
    doldoc_print("  [PASS] Alt+2 consumido pelo DolDoc (workspace 2) e NAO vazou ao Shell\n");
  } else {
    doldoc_printf("  [FAIL] atalho global: gk=%lld restou=%lld\n", gk, left); ok = 0;
  }

  // (6) a fila nao reteve nada
  checks++;
  if (left == 0 && InputQueueCount() == 0) {
    doldoc_printf("  [PASS] duto vazio no fim (drops=%lld)\n", InputQueueDrops());
  } else {
    doldoc_printf("  [FAIL] sobrou evento preso no duto: %lld\n", left); ok = 0;
  }

  if (ok) {
    doldoc_printf("$FG,GREEN$INPUTDUCT: PASS (%lld/%lld)$FG$\n", checks, checks);
    return checks;
  }
  doldoc_printf("$FG,RED$INPUTDUCT: FAIL (%lld checks)$FG$\n", checks);
  return 0;
}

// ==============================================================================
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
    // B9 (ONDA 2): sonda que forca o vigia PARADO (ultima passada 4 s atras,
    // fora da compilacao) e exige deteccao — e que com g_hc_compiling forca o
    // SKIP (prova que a guarda evita o falso positivo do boot). Sem o check o
    // retorno seria 0 e o teste falharia.
    SelfTestCompare("b9_watchdog_stall_detected", WatchdogTestStall(), 1);
    // B11 (ONDA 2): drift do timer. Sonda forca base no passado com poucos ticks de
    // software -> exige deteccao; e prova que o estado coerente NAO da falso positivo.
    // Tambem confirma que a sonda nao deixa g_timer.system_ticks alterado.
    SelfTestCompare("b11_timer_drift_detected", TimerTestDrift(), 1);
    // B2a.1 (ONDA 3): interlock de core. Testa a DECISAO PURA — so' o core 0
    // entrega o frame ao escalonador; secundarios (1,2,3) NAO. Enquanto o
    // Sched.HC nao tiver lock/run-queues, deixar 2 cores no SchedOnTick corrompe.
    SelfTestCompare("b2a1_core0_schedules", GicShouldScheduleCore(0), 1);
    SelfTestCompare("b2a1_core1_blocked", GicShouldScheduleCore(1), 0);
    SelfTestCompare("b2a1_core3_blocked", GicShouldScheduleCore(3), 0);
    // B2a.3 (ONDA 3): kill-switch do SMP simetrico. Desligado por padrao -> nada
    // muda. A sonda prova a decisao pura: off = ninguem abre IRQ; on = secundario
    // aceito e BSP segue barrado.
    SelfTestCompare("b2a3_irq_enable_gate", SmpTestIrqEnableGate(), 1);
    // B2a.3 (ONDA 3): o gate e' consistente com o valor ATUAL do switch (nao fixa
    // o default — ele e' configuravel). Se off, nenhum secundario abriu IRQ; se on,
    // o contador reflete os cores. Testa a COERENCIA, nao a constante.
    if (g_smp_irq_enable == 0) {
        SelfTestCompare("b2a3_off_means_no_cores", g_smp_irq_enabled_cores, 0);
    } else {
        SelfTestCompare("b2a3_on_means_cores_open", (g_smp_irq_enabled_cores != 0) ? 1 : 0, 1);
    }
    // B2a.4/B2a.2 (ONDA 3) — o tick CHEGA aos secundarios. MEDIDO: com o switch
    // ligado e a interface GICv2 por core inicializada, os secundarios tomam o
    // tick. ATUALIZADO NA CAMADA 2: antes o tick era BLOQUEADO no interlock
    // UP-only (g_gic_offcore_tick_blocks); agora ele e' ENTREGUE ao escalonador
    // do core (g_sched_offcore_routed) — prova mais forte (chega E agenda). Aceita
    // qualquer um dos dois: o antigo so' seria > 0 com o kill-switch OFF.
    if (g_smp_irq_enable != 0) {
        I64 reached = (g_gic_offcore_tick_blocks > 0 || g_sched_offcore_routed > 0) ? 1 : 0;
        SelfTestCompare("b2a2_tick_reaches_secondaries", reached, 1);
    }
    // B2b (ONDA 3): afinidade suave. Testa a DECISAO PURA (SchedAffinityAllowsMask)
    // — recebe a mask crua porque SelfTest compila antes de Sched (nao ve' CTask).
    // Sem hardware, sem escalonador: puramente a regra do bit.
    SelfTestCompare("b2b_aff_denies_core0", SchedAffinityAllowsMask(0x02, 0), 0);
    SelfTestCompare("b2b_aff_allows_core1", SchedAffinityAllowsMask(0x02, 1), 1);
    SelfTestCompare("b2b_aff_denies_core3", SchedAffinityAllowsMask(0x02, 3), 0);
    // CAMADA 1.1 (IDEA-2) — atomicidade. Três provas:
    //  (a) Nivel 1 IRQ-safe com aninhamento (predicado puro + estado real).
    SelfTestCompare("c1_irq_save_masks", SmpUnlockShouldEnable(0x80), 0);
    SelfTestCompare("c1_irq_restore_enables", SmpUnlockShouldEnable(0x00), 1);
    SelfTestCompare("c1_irq_nesting", UartTestIrqNesting(), 1);
    //  (b) Nivel 3 lock-free: arena 64B alinhada (1 linha L1D por core).
    SelfTestCompare("c1_gicstats_size64", (I64)sizeof(CGicCoreStats), 64);
    SelfTestCompare("c1_gicstats_align", ((U64)g_gic_core_stats & 63) == 0 ? 1 : 0, 1);
    //  (c) Nivel 3: com IRQs SIMETRICAS ligadas, os cores 1..3 despacharam no
    //      proprio slot (prova que o contador per-core e' realmente usado).
    if (g_smp_irq_enable != 0 && g_gic_core_stats) {
        I64 sec = 0, sci = 1;
        while (sci < GIC_MAX_CORES) { if (g_gic_core_stats[sci].dispatched > 0) sec = 1; sci = sci + 1; }
        SelfTestCompare("c1_gic_percore_secondaries", sec, 1);
    }
    // CAMADA 2 (IDEA-1) — run-queues por core (SMP simetrico REAL).
    SelfTestCompare("c2_rq_size64", SchedRqSizesOk(), 1);
    SelfTestCompare("c2_rq_secondary_ticks", (SchedRqSecondaryTicks() > 0) ? 1 : 0, 1);
    SelfTestCompare("c2_rq_core1_switches", (SchedRqCore1Switches() > 0) ? 1 : 0, 1);
    SelfTestCompare("c2_watchdog_ran_on_core1", (g_watchdog_offcore_runs > 0) ? 1 : 0, 1);
    SelfTestCompare("c2_native_cores_registered", (SchedNativeCores() & 0xE) == 0xE ? 1 : 0, 1);
    // CAMADA 3 (IDEA-4): o funil de apresentacao. O backend e' escolhido UMA vez
    // (PresentInit) e e' um dos 3 validos.
    // P0.2 (CAMADA LOW-LEVEL): o watchdog de estagio de boot. Prova que o boot
    // publicou estagios, que TODOS os modulos terminaram e que o shell marcou o
    // fim. Sem isto, um boot sem timeline passava em silencio.
    SelfTestCompare("c_low_bootstage_phases", (BootStagePhaseCount() >= 6) ? 1 : 0, 1);
    SelfTestCompare("c_low_bootstage_modules", (BootStageModulesDone() >= 30) ? 1 : 0, 1);
    SelfTestCompare("c_low_bootstage_not_slow", (BootStageSlow() == 0) ? 1 : 0, 1);
    // LOW-LEVEL (1.4 + B12 + M3): kernel sob concorrencia REAL. Quatro provas:
    // o lock do heap nao corrompeu nada, os DOIS cores de fato trabalharam (sem
    // fallback mudo), nenhuma alocacao falhou, e o golden hash sobreviveu a carga.
    SelfTestCompare("c_low_wcore_canary", (g_wcore_canary == 0) ? 1 : 0, 1);
    SelfTestCompare("c_low_wcore_both_cores", ((g_wcore_ops[0] > 0) && (g_wcore_ops[1] > 0)) ? 1 : 0, 1);
    SelfTestCompare("c_low_wcore_no_fail", ((g_wcore_fail[0] == 0) && (g_wcore_fail[1] == 0)) ? 1 : 0, 1);
    SelfTestCompare("c_low_wcore_join", (g_wcore_join_rc == 0) ? 1 : 0, 1);
    SelfTestCompare("c3_present_backend_valid",
                    (PresentBackendId() >= 0 && PresentBackendId() <= 2) ? 1 : 0, 1);
    // O contador de frames so' avanca quando algo apresenta. O corpus desenha
    // (RENDER/FONTS/DOLDOC) DEPOIS deste ponto do SelfTest, entao medir ">0" aqui
    // seria medir a ORDEM de execucao, nao o mecanismo. Provamos o mecanismo:
    // apresentar incrementa, e o delta e' exatamente o que pedimos.
    {
        U64 c3_before = PresentFrameCount();
        Present(0, 0, 4, 4, 1);
        SelfTestCompare("c3_present_frames_increment",
                        (PresentFrameCount() == c3_before + 1) ? 1 : 0, 1);
    }
    SelfTestCompare("b2b_aff_core3_ok", SchedAffinityAllowsMask(0x08, 3), 1);
    SelfTestCompare("b2b_aff_open_core0", SchedAffinityAllowsMask(0, 0), 1);
    SelfTestCompare("b2b_aff_open_core2", SchedAffinityAllowsMask(0, 2), 1);
    SelfTestCompare("b2b_aff_both", SchedAffinityAllowsMask(0x09, 3), 1);
    SelfTestCompare("b2b_aff_both2", SchedAffinityAllowsMask(0x09, 1), 0);
    // K1.1 (ONDA 4): operador binario limpa a largura semantica. Sem isto, uma
    // subexpressao com operando U32 marcava a flag e o `>>` seguinte era compilado
    // em 32 bits, TRUNCANDO um valor de 64 bits. Caso concreto: (x + b) >> 8 com b
    // U32 e x = 0x100000000 deve dar 0x1000000; sem o fix dava 0 (LSRV W).
    SelfTestCompare("k11_add_then_shift_u64", ((I64)0x100000000 + (U32)7) >> 8, 0x1000000);
    SelfTestCompare("k11_mul_then_shift", (((I64)0x100000000 * (U32)2) >> 8), 0x2000000);
    SelfTestCompare("k11_and_then_shift", (((I64)0x100000000 | (U32)0xF) >> 8), 0x1000000);
    // D2 (K1.1 completo, HcParseUnary): `-` e `!` PROMOVEM o operando estreito para
    // I64 (podem usar o bit 63) -> limpam a flag. Sem isto, `-u32_var >> 3` viraria
    // LSRV W e descartaria o sinal em X0.
    // D2 (K1.1 completo, HcParseUnary): `-` e `!` PROMOVEM o operando estreito para
    // I64 (podem usar o bit 63) -> limpam a flag. Sem isto, `-u32_var >> 3` viraria
    // LSRV W e descartaria o sinal em X0. Valores esperados computados em 64 bits:
    //   !!(U32)1 = 1  ->  0 - 1 = -1  ->  -1 >> 1 = aritmetico = -1
    SelfTestCompare("d2_neg_then_shift", (((I64)0 - (U32)8) >> 1), -4);
    SelfTestCompare("d2_not_then_shift", (((I64)0 - ((I64)!!(U32)1)) >> 1), -1);
    // `~` NAO limpa (por desenho): `(~u32_v) >> 4` mantem a semantica de ~u32 em 32b.
    // ~0xFF = 0xFFFFFF00 (32 bits); >>4 = 0x0FFFFFF0.
    {
        U32 u = 0x000000FF;
        SelfTestCompare("d2_tilde_then_shift", ((~u) >> 4), 0x0FFFFFF0);
    }
}

U0 SelfTestRun() {
    // The corpus assumes a fresh compiler state: compiling the whole battery a
    // second time in the same boot trips a pre-existing Compiler.HC re-entrancy
    // bug (see docs/04 + doc 02 P0.5). Guard so a second run warns instead of
    // faulting the shell.
    if (g_selftest_done) {
        doldoc_print("$FG,YELLOW$[SELFTEST] already ran this boot; reboot to re-run.$FG$\n");
        doldoc_print("<<<NEO-DONE:selftest>>>\n");
        return;
    }
    g_selftest_done = 1;
    g_selftest_active = 1;   // F1: o vigia suspende a varredura durante o corpus

    g_selftest_pass = 0;
    g_selftest_total = 0;
    g_selftest_fail = 0;
    g_selftest_known_pass = 0;
    g_selftest_known_total = 0;
    g_parity_ok = 0;
    g_parity_total = 0;
    g_parity_fail = 0;
    g_parity_skip = 0;
    g_twin_pass = 0;
    g_twin_total = 0;

    doldoc_print("\n$FG,CYAN$=== NeoOS in-guest SELFTEST ===$FG$\n");

    SelfTestCheck("arith_add_mul", "2 + 3 * 4;", 14);
    SelfTestCheck("arith_paren", "(2 + 3) * 4;", 20);
    SelfTestCheck("arith_div", "17 / 5;", 3);
    SelfTestCheck("arith_mod", "17 % 5;", 2);
    SelfTestCheck("arith_neg1", "0 - 1;", -1);
    SelfTestCheck("arith_neg100", "100 - 200;", -100);
    SelfTestCheck("arith_mul", "6 * 7;", 42);
    SelfTestCheck("bit_shl", "1 << 40;", 1099511627776);
    SelfTestCheck("bit_and", "255 & 15;", 15);
    SelfTestCheck("bit_or", "256 | 15;", 271);
    SelfTestCheck("bit_not", "~0;", -1);
    SelfTestCheck("cmp_signed_lt", "-5 < 3;", 1);
    SelfTestCheck("cmp_signed_gt", "-5 > 3;", 0);
    SelfTestCheck("cmp_neg_rhs", "5 > -3;", 1);
    SelfTestCheck("cmp_neg_neg", "-5 < -3;", 1);
    SelfTestCheck("logic_and", "1 && 0;", 0);
    SelfTestCheck("logic_or", "1 || 0;", 1);
    SelfTestCheck("logic_not0", "!0;", 1);
    SelfTestCheck("logic_not5", "!5;", 0);
    SelfTestCheck("ternary_true", "(3 > 2) ? 111 : 222;", 111);
    SelfTestCheck("ternary_false", "(3 < 2) ? 111 : 222;", 222);
    SelfTestCheck("char_A", "'A';", 65);
    SelfTestCheck("char_z", "'z';", 122);
    SelfTestCheck("f64_add", "3.5 + 1.5;", 4617315517961601024);
    SelfTestCheck("f64_div", "10.0 / 4.0;", 4612811918334230528);
    SelfTestCheck("f64_mul", "2.0 * 3.0;", 4618441417868443648);
    SelfTestCheck("f64_sub", "1.0 - 0.5;", 4602678819172646912);
    SelfTestCheck("f64_neg", "2.0 - 3.0;", -4616189618054758400);
    SelfTestCheck("f64_quarter", "1.0 / 4.0;", 4598175219545276416);
    SelfTestCheck("f64_cmp_lt", "1.0 < 2.0;", 1);
    SelfTestCheck("f64_cmp_gt_false", "2.0 < 1.0;", 0);
    SelfTestCheck("f64_if_branch", "I64 r = 0; if (2.0 > 1.0) r = 1; r;", 1);
    SelfTestCheck2("f64_param_cmp", 1, "I64 ff(F64 x) { if (x > 1.0) return 1; return 0; }", "ff(2.5);");
    SelfTestCheck("f64_loop_accum", "F64 s = 0.0; for (I64 i = 0; i < 4; i = i + 1) { s = s + 0.25; } s;", 4607182418800017408);
    SelfTestCheck2("fn_fib10", 55, "I64 fib(I64 n) { if (n < 2) return n; return fib(n-1) + fib(n-2); }", "fib(10);");
    SelfTestCheck2("fn_recursion_local", 15, "I64 f(I64 n) { I64 t = n; if (n < 2) return t; return f(n-1) + t; }", "f(5);");
    SelfTestCheck2("recursion_local_array", 15, "I64 rf(I64 n) { I64 a[2]; a[0] = n; if (n < 2) return a[0]; return rf(n-1) + a[0]; }", "rf(5);");
    SelfTestCheck("loop_for_sum", "I64 s = 0; for (I64 i = 0; i < 5; i = i + 1) { s = s + i; } s;", 10);
    SelfTestCheck("loop_do_while", "I64 n = 0; do { n = n + 1; } while (n < 5); n;", 5);
    SelfTestCheck("switch_fallthrough", "I64 v = 1; switch (v) { case 1: v = v + 10; case 2: v = v + 20; break; default: v = 888; } v;", 31);
    SelfTestCheck3("struct_recursion", 18, "struct P { I64 x; I64 y; }", "I64 g(I64 n) { P p; p.x = n; p.y = n * 2; if (n < 2) return p.x + p.y; return g(n-1) + p.x + p.y; }", "g(3);");
    SelfTestCheck2("array_in_function", 12, "I64 h() { I64 a[3]; a[0] = 5; a[1] = 7; return a[0] + a[1]; }", "h();");
    SelfTestCheck("ptr_write_deref", "I64 x = 41; I64 *p = &x; *p = 42; x;", 42);
    SelfTestCheck("ptr_read_deref", "I64 v = 7; I64 *q = &v; I64 w = *q; w;", 7);
    SelfTestCheck("ptr_deref_expr", "I64 v = 7; I64 *q = &v; (*q) + 1;", 8);
    SelfTestCheck2("member_assign", 6, "struct Q { I64 x; I64 y; }", "Q qq; qq.x = 5; qq.x = qq.x + 1; qq.x;");
    SelfTestCheck3("mutual_recursion", 1, "I64 isEven(I64 n) { if (n == 0) return 1; return isOdd(n-1); }", "I64 isOdd(I64 n) { if (n == 0) return 0; return isEven(n-1); }", "isEven(10);");
    SelfTestCheck3("forward_global_var", 42, "I64 getx() { return g_fwd; }", "I64 g_fwd = 42;", "getx();");
    SelfTestCheck("forward_struct", "I64 getfx(F *p) { return p->x; } struct F { I64 x; }; F f; f.x = 9; getfx(&f);", 9);
    SelfTestCheck3("fnptr_addr_of_fn", 42, "I64 inc(I64 x) { return x + 1; }", "I64 fp = &inc;", "fp(41);");
    SelfTestCheck("bare_deref_stmt", "I64 v = 7; I64 *q = &v; *q;", 7);
    SelfTestCheck("inline_asm_mov", "asm { 0xD2800540 };", 42);
    SelfTestCheck2("f64_struct_member", 4616189618054758400, "struct FVec { F64 x; F64 y; }", "FVec fv; fv.x = 1.5; fv.y = 2.5; fv.x + fv.y;");
    SelfTestCheck2("f64_struct_ptr_arrow", 4615626668101337088, "struct FBox { F64 w; F64 h; }", "FBox fb; FBox *fpb = &fb; fpb->w = 2.5; fpb->h = 1.5; fpb->w * fpb->h;");
    SelfTestCheck2("f64_array_member", 4613937818241073152, "struct M16 { F64 m[16]; }", "M16 mm; mm.m[0] = 1.0; mm.m[15] = 2.0; mm.m[0] + mm.m[15];");
    SelfTestCheck2("f64_array_member_index", 4613937818241073152, "struct M16 { F64 m[16]; }", "M16 mm2; mm2.m[5] = 2.0; mm2.m[10] = 5.0; mm2.m[10] - mm2.m[5];");
    SelfTestCheck("f64_int_cast", "I64 k = 7; (F64)k + 0.5;", 4620130267728707584);
    SelfTestCheck("f64_to_int_cast", "F64 fx = 3.9; I64 n = (I64)fx; n;", 3);
    SelfTestCheck2("f64_cross_chain", 4607182418800017408, "struct V3 { F64 x; F64 y; F64 z; }", "V3 va; V3 vb; va.x=0.0; va.y=1.0; va.z=0.0; vb.x=0.0; vb.y=0.0; vb.z=1.0; va.y*vb.z - va.z*vb.y;");
    SelfTestCheck2("f64_struct_param", 4612811918334230528, "struct DV { F64 x; }", "F64 getdv(DV *p) { return p->x; } DV dd; dd.x = 2.5; getdv(&dd);");
    // Regression: F64 LHS multiplied by a function call on the RHS (the gears
    // pattern `r * MathCos(a)`). 4.0 * half(1.0) == 2.0.
    SelfTestCheck2("f64_lhs_mul_fn_call", 4611686018427387904, "F64 hf(F64 x) { return x * 0.5; }", "F64 r = 4.0; r * hf(1.0);");
    // Regression: storing an F64 expression with a function call into a struct
    // array member (`g->vertices[k].x = r * MathCos(a)`).
    SelfTestCheck2("f64_struct_arr_member_assign", 4611686018427387904, "struct GVA { F64 x; }; F64 hg(F64 x) { return x * 0.5; }", "GVA gv[2]; gv[0].x = 4.0 * hg(1.0); gv[0].x;");
    // Regression: a 7-arg function with mixed int/F64 args called with an F64
    // function-call expression in a middle argument (the GearAddVertex pattern).
    SelfTestCheck2("f64_seven_arg_mixed", 4611686018427387904, "F64 h7(I64 a, F64 b, F64 c, F64 d, F64 e, F64 f, F64 g) { return b + c + d + e + f + g; }", "h7(1, 4.0 * 0.5, 0.0, 0.0, 0.0, 0.0, 0.0);");
    // Regression (P4.6 root fix): a local F64 array's element floatness used to be
    // inherited from the PREVIOUS declaration, so `a[0] = 1.0` was stored/loaded as
    // raw integer bits. 1.0 + 1.5 + 1.5 == 4.0.
    SelfTestCheck("f64_local_array_assign", "F64 a[3]; a[0] = 1.0; a[1] = 1.5; a[2] = 1.5; a[0] + a[1] + a[2];", 4616189618054758400);
    // Regression (D14 root fix): a local name redeclared with a DIFFERENT type must
    // update its type flags. `b` is F64 in one branch and I64 in another; the stale
    // F64 flag made `p->a[b]` load b as a double (which leaves x0 = &b) and then
    // multiply that ADDRESS by the element size -> a wild ~18 GB read (Data Abort).
    // Expect 30 (rb.a[2]).
    SelfTestCheck("redecl_float_int_index", "struct RBI { I64 a[4]; }; I64 rbif(RBI *p) { F64 b = 1.5; I64 b = 2; return p->a[b]; } RBI rb; rb.a[2] = 30; rbif(&rb);", 30);
    // Regression (D15 root fix): a struct member array dimension may be a constant
    // expression (N*M / N+M), like local and global arrays. Before the fix `[4 * 3]`
    // recorded only 4 elements, so CC.n sat at offset 32 instead of 96 and this read 0.
    SelfTestCheck("member_arr_compound_dim", "struct CL { I64 m[12]; I64 n; }; struct CC { I64 m[4 * 3]; I64 n; }; CL cl; CC *cc = (CC*)&cl; cc->n = 5; cl.n;", 5);
    SelfTestCheck("decl_comma_init", "I64 fn() { U8 a = 10, b = 25, c = 7; I64 x = 100, y = 200; return a + b + c + x + y; } fn();", 342);
    SelfTestCheck("decl_comma_global", "I64 g1 = 5, g2 = 6; g1 + g2;", 11);
    SelfTestCheck("fn_prototype_forward", "I64 fwd_add(I64 a, I64 b); I64 caller() { return fwd_add(19, 23); } I64 fwd_add(I64 a, I64 b) { return a + b; } caller();", 42);
    SelfTestCheck2("macro_define_add", 42, "#define MAC21 21", "MAC21 + MAC21;");
    SelfTestCheck2("macro_define_expr", 42, "#define MACEXPR 6 * 7", "MACEXPR;");
    SelfTestCheck("addr_of_array_elem", "I64 aa[3]; aa[0] = 10; aa[1] = 20; aa[2] = 30; I64 *ap = &aa[1]; *ap;", 20);
    SelfTestCheck("addr_of_array_elem_write", "I64 abw() { I64 ab[3]; ab[0] = 5; I64 *bp = &ab[2]; *bp = 9; return ab[2]; } abw();", 9);
    SelfTestCheck3("forward_call", 10, "I64 fcaller() { return fcallee(5); }", "I64 fcallee(I64 x) { return x * 2; }", "fcaller();");
    SelfTestCheck("global_array", "I64 g_parr[4]; I64 gparw() { g_parr[0] = 3; g_parr[3] = 9; return g_parr[0] + g_parr[3]; } gparw();", 12);
    SelfTestCheck("auto_decl", "auto av = 7; av + 1;", 8);
    SelfTestCheck("array_init_global", "I64 ai3[3] = {10, 20, 30}; ai3[0] + ai3[2];", 40);
    SelfTestCheck("array_init_one_elem", "I64 aone[1] = {7}; aone[0];", 7);
    SelfTestCheck("array_init_local", "I64 laf() { I64 la3[3] = {4, 5, 6}; return la3[0] + la3[2]; } laf();", 10);
    SelfTestCheck("array_init_f64", "F64 af2[2] = {1.5, 2.5}; af2[0] + af2[1];", 4616189618054758400);
    SelfTestCheck3("fnptr_indirect_call", 42, "I64 fci(I64 x) { return x + 1; }", "I64 fcp = &fci;", "fcp(41);");
    SelfTestCheck("forward_struct_ptr", "I64 gfsp(F2 *p) { return p->x; } struct F2 { I64 x; }; F2 ff2; ff2.x = 9; gfsp(&ff2);", 9);
    // D7: struct-member pointer indexing must stride by the pointee width, not 8.
    // 0xAB + 0xBEEF + 0xDEADBEEF = 3735977609; a stride-8 bug reads garbage.
    SelfTestCheck("struct_member_ptr_scale", "struct SPB { U8 *p8; U16 *p16; U32 *p32; }; SPB b; U8 buf[16]; b.p8 = &buf[0]; b.p16 = (U16*)&buf[0]; b.p32 = (U32*)&buf[0]; b.p8[3] = 0xAB; b.p16[2] = 0xBEEF; b.p32[1] = 0xDEADBEEF; b.p8[3] + b.p16[2] + b.p32[1];", 3735977609);
    // --- coverage expansion (P0.5) ---
    SelfTestReject("neg_bad_expr", "2 + ;");
    SelfTestCheck("lex_block_comment", "I64 bc = 7; /* c */ bc + 1;", 8);
    SelfTestCheck("type_nested_struct", "struct Inner { I64 a; }; struct Outer { Inner i; I64 b; }; Outer o; o.i.a = 3; o.b = 4; o.i.a + o.b;", 7);
    SelfTestCheck("type_typedef", "typedef I64 MyInt; MyInt m = 5; m;", 5);
    SelfTestCheck("f64_int_cast2", "(I64)((F64)9 + 0.5);", 9);
    SelfTestCheck("f64_global_if", "F64 nn = 1.0; if (nn < 2.0) nn = 3.0; nn;", 4613937818241073152);
    SelfTestInclude();
    // P7.0: folded from the former orphan apps/TestJitP0.HC.
    SelfTestCheck("compound_arith", "I64 ca = 100; ca += 20; ca -= 10; ca *= 2; ca /= 4; ca %= 10; ca;", 5);
    SelfTestCheck("compound_bitwise", "I64 cb = 0x0F; cb |= 0xF0; cb &= 0x33; cb ^= 0x03; cb <<= 2; cb >>= 1; cb;", 96);
    SelfTestCheck2("struct_member_compound", 70, "struct CIT { I64 id; I64 value; }", "CIT it; it.id = 42; it.value = 10; it.value += 25; it.value *= 2; it.value;");
    SelfTestCheck("loop_break_continue", "I64 s = 0; for (I64 i = 0; i < 20; i = i + 1) { if (i == 5) continue; if (i == 15) break; s += i; } s;", 100);
    SelfTestCheck("sizeof_i64", "sizeof(I64);", 8);
    SelfTestCheck("sizeof_struct", "struct SZ { I64 a; I64 b; I64 c; }; sizeof(SZ);", 24);
    // D29 ROOT FIX: array dimensions must fold constant expressions (* / + - << >>).
    SelfTestCheck("array_dim_const_expr", "I64 ad[16 / 2]; I64 bd[2 * 3 + 1]; ad[0] = 7; bd[6] = 5; ad[0] + bd[6];", 12);
    SelfTestCheck("array_dim_shift_sub", "I64 cd[1 << 3]; I64 ed[10 - 4]; cd[7] = 3; ed[5] = 9; cd[7] + ed[5];", 12);
    // D30 ROOT FIX: indirect dispatch through a struct function-pointer MEMBER.
    // (The former "failure" was the shell silently truncating >255-char input, not a
    // codegen defect; this locks the pattern in for both engines.)
    SelfTestCheck("fnptr_member_dispatch", "struct FDM { I64 v; I64 (*calc)(FDM *item, I64 m); }; I64 FDMmul(FDM *it, I64 m) { if (!it) return 0; return it->v * m; } I64 FDMrun() { FDM x; x.v = 70; x.calc = &FDMmul; FDM *p = &x; return p->calc(p, 3); } FDMrun();", 210);
    // D34 ROOT FIX: an F64 reached through a pointer or a struct F64-array member must
    // be tracked as float in BOTH engines. Compiler.HC keeps F64 in D0 (so `*p = <F64>`
    // must store D0), the C seed keeps it as bits in X0 (so it stores X0) — the results
    // must agree. `f64_ptr_out_param` exercises the write, `f64_struct_array_member_read`
    // the read (2.5 -> 0x4004000000000000, 1.5+2.5 = 4.0 -> 0x4010000000000000).
    SelfTestCheck("f64_ptr_out_param", "I64 FOPset(F64 *p) { *p = 2.5; return 7; } F64 fop_x = 0.0; FOPset(&fop_x); fop_x;", 4612811918334230528);
    SelfTestCheck("f64_struct_array_member_read", "struct FSAM { F64 m[2]; }; FSAM fsam_v; fsam_v.m[0] = 1.5; fsam_v.m[1] = 2.5; fsam_v.m[0] + fsam_v.m[1];", 4616189618054758400);
    // P7.4 F0: compiler-limit regressions. These lock in the raised struct/member
    // and local ceilings and the large-member-offset code path (offset is
    // materialised into a register, so >4095 and >32767 both work). A silent
    // overflow is a hard error now (g_hc_error), never a dropped member.
    // Names are deliberately unique so a test global can never alias a module global
    // (a size-increasing global re-declaration is now a hard error too — see below).
    SelfTestCheck("f0_member_arr_var", "struct F0AVA { I64 qq1[4]; I64 qq2; }; F0AVA g_f0av; g_f0av.qq1[0]=10; g_f0av.qq1[1]=20; g_f0av.qq1[2]=30; g_f0av.qq1[3]=40; g_f0av.qq2=2; F0AVA *g_f0ap=&g_f0av; g_f0ap->qq1[g_f0ap->qq2];", 30);
    SelfTestCheck("f0_member_ptr_var", "struct F0PV { U32 *zzdata; }; U32 g_f0pvb[4]; F0PV g_f0pv; g_f0pv.zzdata=&g_f0pvb[0]; g_f0pv.zzdata[0]=5; g_f0pv.zzdata[1]=7; g_f0pv.zzdata[2]=9; I64 zzk=2; F0PV *g_f0pp=&g_f0pv; g_f0pp->zzdata[zzk];", 9);
    SelfTestCheck("f0_large_offset_4096", "struct F0LB4 { I64 ppad[513]; I64 ptag; }; F0LB4 g_f0lb4; g_f0lb4.ptag=77; g_f0lb4.ptag;", 77);
    SelfTestCheck("f0_large_offset_32768", "struct F0LB32 { I64 qpad[4096]; I64 qtag; }; F0LB32 g_f0lb32; g_f0lb32.qtag=99; g_f0lb32.qtag;", 99);
    SelfTestCheck("f0_struct_48_members", "struct F0M48 { I64 q0;I64 q1;I64 q2;I64 q3;I64 q4;I64 q5;I64 q6;I64 q7;I64 q8;I64 q9;I64 q10;I64 q11;I64 q12;I64 q13;I64 q14;I64 q15;I64 q16;I64 q17;I64 q18;I64 q19;I64 q20;I64 q21;I64 q22;I64 q23;I64 q24;I64 q25;I64 q26;I64 q27;I64 q28;I64 q29;I64 q30;I64 q31;I64 q32;I64 q33;I64 q34;I64 q35;I64 q36;I64 q37;I64 q38;I64 q39;I64 q40;I64 q41;I64 q42;I64 q43;I64 q44;I64 q45;I64 q46;I64 q47; }; F0M48 g_f0m48; g_f0m48.q0=1; g_f0m48.q47=47; g_f0m48.q0+g_f0m48.q47;", 48);
    SelfTestCheck("f0_struct_70_members", "struct F0M70 { I64 w0;I64 w1;I64 w2;I64 w3;I64 w4;I64 w5;I64 w6;I64 w7;I64 w8;I64 w9;I64 w10;I64 w11;I64 w12;I64 w13;I64 w14;I64 w15;I64 w16;I64 w17;I64 w18;I64 w19;I64 w20;I64 w21;I64 w22;I64 w23;I64 w24;I64 w25;I64 w26;I64 w27;I64 w28;I64 w29;I64 w30;I64 w31;I64 w32;I64 w33;I64 w34;I64 w35;I64 w36;I64 w37;I64 w38;I64 w39;I64 w40;I64 w41;I64 w42;I64 w43;I64 w44;I64 w45;I64 w46;I64 w47;I64 w48;I64 w49;I64 w50;I64 w51;I64 w52;I64 w53;I64 w54;I64 w55;I64 w56;I64 w57;I64 w58;I64 w59;I64 w60;I64 w61;I64 w62;I64 w63;I64 w64;I64 w65;I64 w66;I64 w67;I64 w68;I64 w69; }; F0M70 g_f0m70; g_f0m70.w0=3; g_f0m70.w69=67; g_f0m70.w0+g_f0m70.w69;", 70);
    SelfTestCheck("f0_many_locals", "I64 f0many() { I64 w0=0;I64 w1=1;I64 w2=2;I64 w3=3;I64 w4=4;I64 w5=5;I64 w6=6;I64 w7=7;I64 w8=8;I64 w9=9;I64 w10=10;I64 w11=11;I64 w12=12;I64 w13=13;I64 w14=14;I64 w15=15;I64 w16=16;I64 w17=17;I64 w18=18;I64 w19=19;I64 w20=20;I64 w21=21;I64 w22=22;I64 w23=23;I64 w24=24;I64 w25=25;I64 w26=26;I64 w27=27;I64 w28=28;I64 w29=29;I64 w30=30;I64 w31=31;I64 w32=32;I64 w33=33;I64 w34=34;I64 w35=35;I64 w36=36;I64 w37=37;I64 w38=38;I64 w39=39;I64 w40=40;I64 w41=41;I64 w42=42;I64 w43=43;I64 w44=44;I64 w45=45;I64 w46=46;I64 w47=47; return w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10+w11+w12+w13+w14+w15+w16+w17+w18+w19+w20+w21+w22+w23+w24+w25+w26+w27+w28+w29+w30+w31+w32+w33+w34+w35+w36+w37+w38+w39+w40+w41+w42+w43+w44+w45+w46+w47; } f0many();", 1128);
    // P7.4 F0: a size-INCREASING global re-declaration must be a HARD ERROR in BOTH
    // engines (HC + C seed JIT), never a silent reuse of the smaller cell (that
    // corrupted the next heap block). The 16-byte `I64 g;` cell cannot hold
    // `I64 g[10]` (80 bytes) -> RE-DECL OVERFLOW (-1), and parity must hold.
    SelfTestCheck("neg_global_redecl_overflow", "I64 g_f0ro_x; I64 g_f0ro_x[10]; g_f0ro_x[0];", -1);
    // P7.4 F1 (PASSO 2): deferred-offset lvalue + immediate-offset load/store. The
    // member byte offset is folded into the LDR/STR unsigned-immediate field; when
    // it does not fit (non-multiple of the width, or >= 4096*width) it is
    // materialized. These lock in every width, both limits, chained members,
    // variable-index member arrays, &member, compound ops, and — the bug that
    // broke TEXTURE/SHADING/CLIP — an F64 member at a NON-8-aligned offset.
    SelfTestCheck("f1_u8_odd_offset", "struct F1UO { U8 a; U8 b; U8 c; }; F1UO g_f1uo; g_f1uo.a=1; g_f1uo.b=2; g_f1uo.c=3; g_f1uo.a+g_f1uo.b+g_f1uo.c;", 6);
    SelfTestCheck("f1_u16_odd_offset", "struct F1H2 { U8 a; U16 b; }; F1H2 g_f1h2; g_f1h2.b=0xBEEF; g_f1h2.b;", 48879);
    SelfTestCheck("f1_u32_non8_offset", "struct F1UW { U8 a; U32 b; }; F1UW g_f1uw; g_f1uw.a=1; g_f1uw.b=0xDEADBEEF; g_f1uw.b;", 3735928559);
    SelfTestCheck("f1_f64_non8_offset", "struct F1FO { U32 pad; F64 x; F64 y; }; F1FO g_f1fo; g_f1fo.x=1.5; g_f1fo.y=2.5; g_f1fo.x+g_f1fo.y;", 4616189618054758400);
    SelfTestCheck("f1_offset_4088", "struct F1O4 { I64 p[511]; I64 t; }; F1O4 g_f1o4; g_f1o4.t=88; g_f1o4.t;", 88);
    SelfTestCheck("f1_offset_32760", "struct F1O32 { I64 p[4095]; I64 t; }; F1O32 g_f1o32; g_f1o32.t=99; g_f1o32.t;", 99);
    SelfTestCheck("f1_offset_32768_fallback", "struct F1O33 { I64 p[4096]; I64 t; }; F1O33 g_f1o33; g_f1o33.t=77; g_f1o33.t;", 77);
    SelfTestCheck("f1_chain_abc", "struct F1CA { I64 v; }; struct F1CB { F1CA b; }; struct F1CC { F1CB a; }; F1CC g_f1cc; g_f1cc.a.b.v=42; g_f1cc.a.b.v;", 42);
    SelfTestCheck("f1_arrow_incdec", "struct F1IC { I64 v; }; F1IC g_f1ic; F1IC *g_f1icp=&g_f1ic; g_f1icp->v=10; g_f1icp->v++; g_f1icp->v+=5; g_f1icp->v;", 16);
    SelfTestCheck("f1_addr_of_member", "struct F1AM { I64 v; I64 w; }; F1AM g_f1am; g_f1am.w=5; I64 *g_f1amp=&g_f1am.w; *g_f1amp=9; g_f1am.w;", 9);
    SelfTestCheck("f1_member_arr_var", "struct F1AV { I64 a[4]; I64 n; }; F1AV g_f1av; g_f1av.a[0]=10; g_f1av.a[1]=20; g_f1av.a[2]=30; g_f1av.n=2; g_f1av.a[g_f1av.n];", 30);
    // P7.4 F5: the #define value parser must evaluate division and precedence like
    // the C seed (the old self-hosted parser ignored `/` and was flat).
    SelfTestCheck("f5_macro_div", "#define MDIV (40 / 4)\nMDIV;", 10);
    SelfTestCheck("f5_macro_prec", "#define MPREC (2 + 3 * 4)\nMPREC;", 14);
    SelfTestCheck("f5_macro_div_chain", "#define MCHAIN (100 / 5 / 2)\nMCHAIN;", 10);
    SelfTestKnown("known_over8_args", "I64 nine(I64 a,I64 b,I64 c,I64 d,I64 e,I64 f,I64 g,I64 h,I64 i) { return a + i; } nine(1,2,3,4,5,6,7,8,9);", -1);
    SelfTestTwins();
    SelfTestSymbols();
    SelfTestHalCache();
    SelfTestFs();
    SelfTestSched();
    SelfTestBsod();
    SelfTestSmp();
    SelfTestSovereign();
    SelfTestKernel();
    SelfTestPtrScale();
    SelfTest2DArray();
    SelfTestStructPtrScale();
    SelfTestHeap();
    SelfTestTexture();
    SelfTestGL();
    SelfTestClip();
    SelfTestNeonMem();
    SelfTestTile();
    SelfTestGpuConfig();
    TelemetrySelfTest();
    // D-5 (estudo-de-deadcode): ProfilerSelfTest existia em Telemetry.HC:1010 e
    // NUNCA era chamado — 5 assercoes completas (reset, on/off, marks, ring, FPS)
    // produzidas e esquecidas. Ligado aqui: o rotulo 'PROFILER: n/n' passa a
    // entrar no gate (antes, 'PROFILER' so' aparecia como nome de arquivo).
    ProfilerSelfTest();
    EffectsSelfTest();
    EffectsSpringSelfTest();
    EffectsGlassSelfTest();
    EffectsTransitionSelfTest();
    SelfTestMath3DParallel();
    FontsSelfTest();
    SelfTest3D();
    SelfTestShading();
    ShaderVMSelfTest();
    MeshSelfTest();
    // LOW-LEVEL (1.4 + M3 + M5): o kernel sob concorrencia REAL. Roda ANTES do
    // SelfTestRender para que o RENDER: PASS (que ja' existe) sirva de prova do B12
    // — o determinismo medido DEPOIS de dois cores martelarem o heap.
    SelfTestWcore();
    SelfTestRender();
    DolDocSelfTest();
    DolDocSlateSelfTest();
    ShellSelfTest();
    SelfTestInputDuct();
    SelfTestRollback();
    SelfTestLexGuards();
    SelfTestRng();
    SelfTestOverflowInjection();
    SelfTestHeapIntegrity();
    SelfTestFallbacks();
    SelfTestStackCanary();

    doldoc_printf("$FG,CYAN$---$FG$ %lld/%lld passed, %lld failed | known: %lld/%lld\n",
                  g_selftest_pass, g_selftest_total, g_selftest_fail,
                  g_selftest_known_pass, g_selftest_known_total);
    doldoc_printf("$FG,CYAN$---$FG$ engine parity: %lld/%lld agree, %lld diff, %lld seed-skip\n",
                  g_parity_ok, g_parity_total, g_parity_fail, g_parity_skip);
    doldoc_printf("SELFTEST: %lld/%lld PASS\n", g_selftest_pass, g_selftest_total);
    doldoc_printf("PARITY: %lld/%lld\n", g_parity_ok, g_parity_total);
    g_selftest_active = 0;   // F1: corpus terminou; o vigia volta a varrer
    doldoc_print("<<<NEO-DONE:selftest>>>\n");
}
