// HolyBenchmark3D.HC - Unified 3D, SMP & Physics Scientific Benchmark Suite
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 Bench3DMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS Unified 3D, SMP & Physics Benchmark (HolyBenchmark3D) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Phases    : 16 Automated Multi-Configuration Benchmarks (10s per phase)\n");
    doldoc_print(" Subsystems: CPU SW GOP | Zero-RAM VRAM | VirtIO DMA | SMP Cores 1-4 | L1-Tile\n");
    doldoc_print(" Output    : Real-Time Telemetry & Auto-Export to /BENCH_COMPARISON.TXT\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Launching Autonomous 16-Phase Scientific Comparison Suite...\n");
    bench_unified_start(3); // BENCH_MODE_SUITE

    doldoc_print(" Benchmark Controls:\n");
    doldoc_print("  Actions: $BT,\"View Performance HUD\",LM=\"perf\"$  $BT,\"Export Telemetry\",LM=\"benchlog\"$\n");
    doldoc_print("  Dismiss: $BT,\"Abort / Stop Benchmark\",LM=\"stopbench\"$  $BT,\"Return to Shell\",LM=\"help\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

Bench3DMain();
