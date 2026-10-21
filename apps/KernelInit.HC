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

U0 KInitLoad(U8 *fname) {
    U8 *kinit_load_buf = kmalloc(131072);
    if (!kinit_load_buf) {
        doldoc_printf("[KERNEL-INIT] FATAL: Out of memory loading %s\n", fname);
        return;
    }
    // P2.2: boot modules come from the FAT32 ESP via the UEFI firmware's file
    // reader (seed_read_file), not from the C RedSea filesystem.
    I64 fsize = seed_read_file(fname, kinit_load_buf, 131071);
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
    KInitLog("Stage 2: 2D Graphics Canvas & Scalable Vector Typography...");
    KInitLoad("Render.HC");
    KInitLoad("FontMono.HC");
    KInitLoad("FontVector.HC");

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
    KInitLoad("Physics3D.HC");
    KInitLoad("Gears3D.HC");

    // Stage 6: Telemetry, Theme Compositor, DolDoc 3.0, Shell & Window Manager
    KInitLog("Stage 6: Theme Compositor, DolDoc 3.0, Shadertoy & Desktop...");
    KInitLoad("Profiler.HC");
    KInitLoad("PerfOverlay.HC");
    KInitLoad("BenchCpu.HC");
    KInitLoad("BenchReport.HC");
    KInitLoad("Compositor.HC");
    KInitLoad("DolDoc.HC");
    // WM.HC defines g_wm/StudioWin* which Shell.HC references. Load WM first;
    // WM's own dependency on Shell (shell_run_command) late-binds via SIC.
    KInitLoad("WM.HC");
    KInitLoad("Shell.HC");
    KInitLoad("ShaderEditor.HC");
    KInitLoad("HolyBenchmark.HC");

    KInitLog("======================================================");
    KInitLog("✦ ALL 32 HOLYC SUBSYSTEMS COMPILED & ACTIVE IN RING 0 ✦");
    KInitLog("======================================================");

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
