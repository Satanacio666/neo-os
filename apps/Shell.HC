// Shell.HC - Pure HolyC Interactive Shell Console
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 ShellMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Pure HolyC Shell Command Console (Shell.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Environment: ARMv8-A Ring 0 SASOS | 100% Native AArch64 JIT\n");
    doldoc_print(" Filesystem : RedSea Contiguous Partition (/)\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Available Commands & Actions:\n");
    doldoc_print("  System & Bench : $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$  $BT,\"Top Monitor\",LM=\"run Top.HC\"$  $BT,\"JIT Tests\",LM=\"jittest\"$\n");
    doldoc_print("  Graphics & Font: $BT,\"L1 Rasterizer\",LM=\"run RasterTile.HC\"$  $BT,\"Vector Font\",LM=\"run FontVector.HC\"$  $BT,\"Compositor\",LM=\"run Compositor.HC\"$\n");
    doldoc_print("  Filesystem     : $BT,\"Filer Explorer\",LM=\"run Filer.HC\"$  $BT,\"List (ls)\",LM=\"ls\"$  $BT,\"Pwd\",LM=\"pwd\"$\n");
    doldoc_print("  Navigation     : $BT,\"App Drawer\",LM=\"run Menu.HC\"$  $BT,\"Window Mgr\",LM=\"run WM.HC\"$  $BT,\"Clear Console\",LM=\"clear\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

ShellMain();
