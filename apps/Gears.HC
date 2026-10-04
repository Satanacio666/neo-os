// Gears.HC - Sovereign 3D GLXGears Engine (HolyBenchmark Subsystem)
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 GearsMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS 3D GLXGears Engine (HolyBenchmark Subsystem) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Pipeline : 3D Involute Gears | Directional Lighting | L1-Tile NEON\n");
    doldoc_print(" Subsystem: Module of HolyBenchmark.HC (Individual 3D Viewport)\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    bench_unified_start(0); // BENCH_MODE_GEARS

    doldoc_print(" Controls:\n");
    doldoc_print("  Actions: $BT,\"Run Full HolyBenchmark\",LM=\"bench\"$  $BT,\"Physics Subsystem\",LM=\"physics\"$\n");
    doldoc_print("  View   : $BT,\"Wireframe Mode\",LM=\"gears_wire\"$  $BT,\"RivaTuner Perf HUD\",LM=\"perf\"$\n");
    doldoc_print("  Dismiss: $BT,\"Stop Viewport\",LM=\"stopbench\"$  $BT,\"App Menu\",LM=\"menu\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

GearsMain();
