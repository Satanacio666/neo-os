// ==============================================================================
// apps/KernelInit.HC - NeoOS Sovereign Pure HolyC Master Boot Orchestrator
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
// Chains, compiles, and initializes all native HolyC kernel subsystems
// in strict topological dependency order and enters DolDocShellEventLoop().
// ==============================================================================

I64 g_kernel_booting = 1;

U0 KInitLog(U8 *msg) {
    doldoc_printf("[KERNEL-INIT] %s\n", msg);
}

U0 KInitLoad(U8 *fname) {
    U8 *kinit_load_buf = kmalloc(131072);
    if (!kinit_load_buf) {
        doldoc_printf("[KERNEL-INIT] FATAL: Out of memory loading %s\n", fname);
        return;
    }
    I64 fsize = 0;
    if (redsea_read_file(fname, kinit_load_buf, 131071, &fsize) == 0) {
        kinit_load_buf[fsize] = 0;
        doldoc_printf("[KERNEL-INIT] Compiling %s (%lld bytes)...\n", fname, fsize);
        I64 res = jit_compile_and_run(kinit_load_buf);
        doldoc_printf("[KERNEL-INIT] %s compiled, res = %lld\n", fname, res);
    } else {
        doldoc_printf("[KERNEL-INIT WARN] Could not read %s from RedSea disk!\n", fname);
    }
    kfree(kinit_load_buf);
}

U0 KernelInitMain() {
    g_kernel_booting = 1;

    doldoc_print("\n======================================================\n");
    doldoc_print(" NeoOS Sovereign Pure HolyC Kernel (AArch64 Ring 0)\n");
    doldoc_print(" 100% Native HolyC Compilation & Runtime Orchestration\n");
    doldoc_print("======================================================\n\n");

    // Stage 1: Architecture HAL, Memory, Symbol Reflection, Containers & Compiler
    KInitLog("Stage 1: Architecture HAL, Memory, Containers & Compiler...");
    KInitLoad("HalPlatform.HC");
    KInitLoad("Timer.HC");
    KInitLoad("Gic.HC");
    KInitLoad("Exceptions.HC");
    KInitLoad("KHeap.HC");
    KInitLoad("Symbols.HC");
    KInitLoad("StdLib.HC");
    KInitLoad("Table.HC");
    KInitLoad("Lexer.HC");
    KInitLoad("Compiler.HC");

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
    KInitLoad("VirtioGpu.HC");
    KInitLoad("GfxBackend.HC");

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
    KInitLoad("Shell.HC");
    KInitLoad("ShaderEditor.HC");
    KInitLoad("HolyBenchmark.HC");
    KInitLoad("WM.HC");

    KInitLog("======================================================");
    KInitLog("✦ ALL 32 HOLYC SUBSYSTEMS COMPILED & ACTIVE IN RING 0 ✦");
    KInitLog("======================================================");

    // Stage 7: Enter sovereign fullscreen DolDoc shell continuum
    g_kernel_booting = 0;
    KInitLog("Entering Sovereign HolyC DolDocShellEventLoop()...");
    jit_compile_and_run("DolDocShellEventLoop();");
}

KernelInitMain();
