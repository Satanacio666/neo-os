// HolyBenchmark.HC - Master Unified Benchmark Orchestrator
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 HolyBenchmarkCpu() {
    doldoc_print("$FG,CYAN$[STAGE 1/2] Executing Pure HolyC CPU Architecture Benchmarks...$FG$\n");
    shell_run_command("run BenchCpu.HC");
}

U0 HolyBenchmarkSuite() {
    doldoc_print("\n$FG,CYAN$[STAGE 2/2] Launching Symmetrical 40-Phase 3D & GPU Pipeline Suite...$FG$\n");
    doldoc_print(" Pipeline Architecture (5 Visual Engines x 8 Standard Variations):\n");
    doldoc_print("  • Engines    : GLXGears (1-8), Cubes SMP (9-16), Dynamics (17-24), Sphere (25-32), Fillrate (33-40)\n");
    doldoc_print("  • Variations : SW 1C, NEON SIMD, SMP 4C, Direct VRAM, VirtIO DMA, VirtIO+SMP, Wireframe, VSync\n");
    doldoc_print("  • Profiler   : cntvct_el0 Sub-ms Logic/Raster/Blit/DMA + Automated Bottleneck Diagnosis\n");
    doldoc_print("  • Telemetry  : Exported to /BENCH_COMPARISON.TXT, /BENCH_PROFILER.LOG, /BENCH_SPIKES.LOG\n\n");

    bench_unified_start(3); // BENCH_MODE_SUITE (40 Phases)
}

U0 HolyBenchmarkMain() {
    doldoc_print("\n$FG,CYAN$======================================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS HolyBenchmark: Sovereign Unified Benchmark Suite ✦$FG$\n");
    doldoc_print("               100% Ring 0 SASOS AArch64 Native Pipeline\n");
    doldoc_print("$FG,CYAN$======================================================================$FG$\n");

    // 1. Run CPU compute benchmarks
    HolyBenchmarkCpu();

    // 2. Launch Autonomous 16-Phase 3D & GPU Comparative Suite
    HolyBenchmarkSuite();

    doldoc_print("$FG,CYAN$----------------------------------------------------------------------$FG$\n");
    doldoc_print(" Interactive Suite Controls & Standalone Subsystem Viewports:\n");
    doldoc_print("  Standalone: $BT,\"GLXGears 3D Only\",LM=\"gears\"$  $BT,\"Physics 3D Only\",LM=\"physics\"$  $BT,\"Dual Cubes SMP\",LM=\"cube2\"$\n");
    doldoc_print("  Telemetry : $BT,\"View Scorecard & Spikes\",LM=\"run BenchReport.HC\"$  $BT,\"RivaTuner HUD\",LM=\"perf\"$\n");
    doldoc_print("  Management: $BT,\"Stop / Close Viewport\",LM=\"stopbench\"$  $BT,\"App Drawer Menu\",LM=\"menu\"$\n");
    doldoc_print("$FG,CYAN$======================================================================$FG$\n\n");
}

HolyBenchmarkMain();
