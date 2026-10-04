// Gears.HC - Sovereign 3D GLXGears Engine & Benchmark in Pure HolyC
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 GearsMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign 3D GLXGears Application (Gears.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Architecture: 3D Procedural Involute Gears | Directional Lighting & Z-Buffer\n");
    doldoc_print(" Pipeline    : Unified L1-Tiled NEON / HolyGL Immediate State Machine\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Launching 3D Viewport in Window Manager...\n");
    bench_unified_start(0); // BENCH_MODE_GEARS

    doldoc_print(" Interactive 3D Controls:\n");
    doldoc_print("  Modes   : $BT,\"Standard Shaded\",LM=\"gears\"$  $BT,\"Wireframe Mode\",LM=\"gears_wire\"$  $BT,\"Parallel Dual SMP\",LM=\"gears_dual\"$\n");
    doldoc_print("  Telemetry: $BT,\"Export Bench Log\",LM=\"gears_log\"$  $BT,\"RivaTuner Perf HUD\",LM=\"perf\"$\n");
    doldoc_print("  Dismiss : $BT,\"Stop Gears Viewport\",LM=\"stopbench\"$  $BT,\"App Menu\",LM=\"menu\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

GearsMain();
