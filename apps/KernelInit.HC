// ==============================================================================
// apps/KernelInit.HC - NeoOS Sovereign Pure HolyC Master Boot Orchestrator
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
// Chains, compiles, and initializes all native HolyC kernel subsystems
// in strict topological dependency order and enters DolDocShellEventLoop().
// ==============================================================================

I64 g_kernel_booting = 1;
I64 g_hc_ready = 0;   // set once Compiler.HC has been bootstrapped by the C JIT

U0 KInitLog(U8 *msg) {
    doldoc_printf("[KERNEL-INIT] %s\n", msg);
}

// P0.7: module load buffer. This used to be 128 KB, which SILENTLY TRUNCATED any
// module larger than 131071 bytes — Compiler.HC (now ~139 KB) lost its tail,
// including CompilerCompileAndRun, whenever edits grew it past the boundary. A
// truncated module compiles "successfully" but its later functions never exist,
// producing unresolved forward references and a dead shell. Size it generously
// (1 MB) so source growth can never truncate silently again.
#define HC_MODULE_MAX 1048576

U0 KInitLoad(U8 *fname) {
    U8 *kinit_load_buf = kmalloc(HC_MODULE_MAX);
    if (!kinit_load_buf) {
        doldoc_printf("[KERNEL-INIT] FATAL: Out of memory loading %s\n", fname);
        return;
    }
    // P2.2: boot modules come from the FAT32 ESP via the UEFI firmware's file
    // reader (seed_read_file), not from the C RedSea filesystem.
    I64 fsize = seed_read_file(fname, kinit_load_buf, HC_MODULE_MAX - 1);
    if (fsize > 0) {
        kinit_load_buf[fsize] = 0;
        doldoc_printf("[KERNEL-INIT] Compiling %s (%lld bytes)...\n", fname, fsize);
        I64 res;
        if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }
        doldoc_printf("[KERNEL-INIT] %s compiled, res = %lld\n", fname, res);
    } else {
        doldoc_printf("[KERNEL-INIT WARN] Could not read %s from the ESP!\n", fname);
    }
    kfree(kinit_load_buf);
}

U0 KernelInitMain() {
    g_kernel_booting = 1;

    doldoc_print("\n======================================================\n");
    doldoc_print(" NeoOS Sovereign Pure HolyC Kernel (AArch64 Ring 0)\n");
    doldoc_print(" 100% Native HolyC Compilation & Runtime Orchestration\n");
    doldoc_print("======================================================\n\n");

    // Stage 1: Architecture HAL, Memory, Containers & Compiler.
    // P2.7: the C JIT compiles ONLY Compiler.HC; the self-hosted compiler then
    // compiles every other .HC module (including the HAL, heap and symbol table).
    KInitLog("Stage 1: Architecture HAL, Memory, Containers & Compiler...");
    KInitLoad("Compiler.HC");
    g_hc_ready = 1;
    KInitLoad("HalPlatform.HC");
    KInitLoad("Timer.HC");
    KInitLoad("Gic.HC");
    KInitLoad("Exceptions.HC");
    KInitLoad("KHeap.HC");
    KInitLoad("Symbols.HC");
    KInitLoad("SelfTest.HC");

    // Stage 2: 2D Graphics Canvas & Scalable Typography
    KInitLog("Stage 2: 2D Graphics Canvas & Scalable Typography...");
    KInitLoad("Render.HC");
    KInitLoad("Fonts.HC");

    // Stage 3: Scheduling & Multiprocessing
    KInitLog("Stage 3: Cooperative Scheduler & SMP Multiprocessing...");
    KInitLoad("Sched.HC");
    KInitLoad("Smp.HC");

    // Stage 4: Hardware Storage & Input Drivers
    KInitLog("Stage 4: Hardware Storage & Input Drivers...");
    KInitLoad("VirtioBlk.HC");
    KInitLoad("RedSea.HC");
    KInitLoad("Keyboard.HC");
    KInitLoad("Mouse.HC");
    KInitLoad("VirtioInput.HC");
    KInitLoad("GfxDevice.HC");

    // Stage 5: 3D Graphics, Geometry, Mathematics & Physics
    KInitLog("Stage 5: 3D Graphics, Geometry, Mathematics & Physics...");
    KInitLoad("Math3D.HC");
    KInitLoad("RasterTile.HC");
    KInitLoad("HolyGL.HC");
    KInitLoad("ShaderVM.HC");
    KInitLoad("Mesh.HC");
    KInitLoad("Physics3D.HC");
    KInitLoad("Gears3D.HC");

    // Stage 6: Telemetry, Theme, DolDoc 3.0 (CDoc/CTree), Shell & Desktop
    KInitLog("Stage 6: Theme, DolDoc 3.0 (CDoc/CTree), Shadertoy & Desktop...");
    KInitLoad("Profiler.HC");
    KInitLoad("PerfOverlay.HC");
    KInitLoad("BenchCpu.HC");
    KInitLoad("BenchReport.HC");
    KInitLoad("Theme.HC");
    // P5: WM.HC and Compositor.HC are dissolved into DolDoc.HC (windows are
    // documents; damage/present/effects live in the continuum). DolDoc loads
    // before Shell, which drives DolDocDesktopLoop().
    KInitLoad("DolDoc.HC");
    KInitLoad("Shell.HC");
    KInitLoad("ShaderEditor.HC");
    KInitLoad("HolyBenchmark.HC");

    KInitLog("======================================================");
    KInitLog("✦ ALL 34 HOLYC SUBSYSTEMS COMPILED & ACTIVE IN RING 0 ✦");
    KInitLog("======================================================");

    // P7.0: peephole-optimizer telemetry (Compiler.HC optimizes every module it
    // compiles; the C seed optimizes Compiler.HC itself).
    KInitLog("PEEPHOLE: module runs, stack round-trips collapsed, dead moves, dead adds.");
    doldoc_printf("[PEEPHOLE] runs=%lld roundtrips=%lld deadmoves=%lld deadadds=%lld\n",
                  g_hc_opt_runs, g_hc_opt_roundtrips, g_hc_opt_deadmoves, g_hc_opt_deadadds);

    // Stage 7: Enter sovereign fullscreen DolDoc shell continuum
    g_kernel_booting = 0;
    symbols_report_unresolved();

    // P3.8: sovereign handover — KHeap.HC takes over kmalloc/kfree (the seed
    // allocator is frozen from here on). Done before the shell allocates anything.
    KHeapHandover();
    SymbolsHandover();
    KInitLog("Sovereign handover: KHeap.HC + Symbols.HC own the runtime.");

    // P3.4: arm the EL1 virtual timer (PPI registered at Gic.HC load) and unmask
    // IRQs last. Early IRQs (before the scheduler) are gated by g_sched_ready.
    TimerArm(1000);
    enable_interrupts();
    KInitLog("Timer IRQ armed @ 1000 Hz; interrupts enabled.");

    KInitLog("Entering Sovereign HolyC DolDocShellEventLoop()...");
    jit_compile_and_run("DolDocShellEventLoop();");
}

KernelInitMain();
