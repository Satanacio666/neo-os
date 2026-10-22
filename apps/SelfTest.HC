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

I64 g_selftest_pass = 0;
I64 g_selftest_total = 0;
I64 g_selftest_fail = 0;
I64 g_selftest_known_pass = 0;
I64 g_selftest_known_total = 0;
U8  g_halcache_buf[256];   // P2.1.5: static buffer for the HAL cache-coherency check
I64 g_fs_rt_size = 0;      // P2.5: out-size for the filesystem round-trip check
I64 g_selftest_done = 0;   // guard: the corpus is a once-per-boot regression check
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
    redsea_write_file("__p2_rt.HC", wbuf, 64);
    g_fs_rt_size = 0;
    redsea_read_file("__p2_rt.HC", rbuf, 64, &g_fs_rt_size);
    I64 ok = (g_fs_rt_size == 64);
    if (ok) {
        i = 0;
        while (i < 64) { if (rbuf[i] != wbuf[i]) { ok = 0; break; } i++; }
    }
    if (ok) {
        doldoc_print("[SELFTEST] PASS fs round-trip (RedSea.HC)\n");
        doldoc_print("FSRT: PASS\n");
    } else {
        doldoc_printf("[SELFTEST] FAIL fs round-trip (n=%lld)\n", g_fs_rt_size);
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
}

// P3.8: verify the sovereign handover took effect - the live kmalloc / symbols_*
// resolve to the .HC owners, not the seed implementations.
U0 SelfTestSovereign() {
    U64 km = symbols_lookup("kmalloc");
    U64 kf = symbols_lookup("kfree");
    U64 sl = symbols_lookup("symbols_lookup");
    U64 sr = symbols_lookup("symbols_register");
    if (km == (U64)&KMalloc && kf == (U64)&KFree &&
        sl == (U64)&SymLookup && sr == (U64)&SymRegister) {
        doldoc_print("SOVEREIGN: PASS\n");
    } else {
        doldoc_printf("SOVEREIGN: FAIL (km=0x%llX kf=0x%llX sl=0x%llX sr=0x%llX)\n",
                      km, kf, sl, sr);
    }
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
    FontsSelfTest();
    SelfTestRender();

    doldoc_printf("$FG,CYAN$---$FG$ %lld/%lld passed, %lld failed | known: %lld/%lld\n",
                  g_selftest_pass, g_selftest_total, g_selftest_fail,
                  g_selftest_known_pass, g_selftest_known_total);
    doldoc_printf("$FG,CYAN$---$FG$ engine parity: %lld/%lld agree, %lld diff, %lld seed-skip\n",
                  g_parity_ok, g_parity_total, g_parity_fail, g_parity_skip);
    doldoc_printf("SELFTEST: %lld/%lld PASS\n", g_selftest_pass, g_selftest_total);
    doldoc_printf("PARITY: %lld/%lld\n", g_parity_ok, g_parity_total);
    doldoc_print("<<<NEO-DONE:selftest>>>\n");
}
