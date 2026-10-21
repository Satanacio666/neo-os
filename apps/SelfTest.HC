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
// The 74 active cases are the exact corpus from tests/jit_golden/cases.json
// (1 additional case is `known` and reported separately, not counted).
// ==============================================================================

I64 g_selftest_pass = 0;
I64 g_selftest_total = 0;
I64 g_selftest_fail = 0;
I64 g_selftest_known_pass = 0;
I64 g_selftest_known_total = 0;
I64 g_selftest_done = 0;   // guard: the corpus is a once-per-boot regression check
I64 g_parity_ok = 0;
I64 g_parity_total = 0;
I64 g_parity_fail = 0;
I64 g_parity_skip = 0;

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

// The one shell-driven case (save/run/#include) reduced to its compiler essence:
// write an include target to RedSea, then compile a unit that #includes it.
U0 SelfTestInclude() {
    redsea_write_file("__inc1.HC", "I64 g_inc = 5;", 14);
    SelfTestCompare("include_vfs", CompilerCompileAndRun("#include \"__inc1.HC\"\ng_inc + 2;"), 7);
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

    g_selftest_pass = 0;
    g_selftest_total = 0;
    g_selftest_fail = 0;
    g_selftest_known_pass = 0;
    g_selftest_known_total = 0;
    g_parity_ok = 0;
    g_parity_total = 0;
    g_parity_fail = 0;
    g_parity_skip = 0;

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
    SelfTestInclude();
    SelfTestKnown("known_over8_args", "I64 nine(I64 a,I64 b,I64 c,I64 d,I64 e,I64 f,I64 g,I64 h,I64 i) { return a + i; } nine(1,2,3,4,5,6,7,8,9);", -1);

    doldoc_printf("$FG,CYAN$---$FG$ %lld/%lld passed, %lld failed | known: %lld/%lld\n",
                  g_selftest_pass, g_selftest_total, g_selftest_fail,
                  g_selftest_known_pass, g_selftest_known_total);
    doldoc_printf("$FG,CYAN$---$FG$ engine parity: %lld/%lld agree, %lld diff, %lld seed-skip\n",
                  g_parity_ok, g_parity_total, g_parity_fail, g_parity_skip);
    doldoc_printf("SELFTEST: %lld/%lld PASS\n", g_selftest_pass, g_selftest_total);
    doldoc_printf("PARITY: %lld/%lld\n", g_parity_ok, g_parity_total);
    doldoc_print("<<<NEO-DONE:selftest>>>\n");
}
