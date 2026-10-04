// Menu.HC - Pure HolyC Application Drawer & Launcher
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 MenuMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$             ✦ NeoOS Sovereign HolyC App Drawer (Menu.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Select any category or application to launch in Ring 0:\n\n");

    doldoc_print(" $FG,YELLOW$🚀 System Compute & Telemetry:$FG$\n");
    doldoc_print("   $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$  $BT,\"System Monitor (Top)\",LM=\"run Top.HC\"$  $BT,\"Unified 3D Suite\",LM=\"run HolyBenchmark3D.HC\"$\n\n");

    doldoc_print(" $FG,YELLOW$🎮 3D Graphics, Physics & Vector Fonts:$FG$\n");
    doldoc_print("   $BT,\"GLXGears 3D\",LM=\"run Gears.HC\"$  $BT,\"Physics Dynamics\",LM=\"run Physics3D.HC\"$  $BT,\"L1 Rasterizer\",LM=\"run RasterTile.HC\"$  $BT,\"Vector Font\",LM=\"run FontVector.HC\"$\n");
    doldoc_print("   $BT,\"Compositor Aero\",LM=\"run Compositor.HC\"$  $BT,\"GPU Profile\",LM=\"run GpuConfig.HC\"$\n\n");

    doldoc_print(" $FG,YELLOW$📁 Storage & Filesystem:$FG$\n");
    doldoc_print("   $BT,\"RedSea Filer\",LM=\"run Filer.HC\"$  $BT,\"Directory Listing\",LM=\"ls\"$\n\n");

    doldoc_print(" $FG,YELLOW$💻 Development & HolyC Utilities:$FG$\n");
    doldoc_print("   $BT,\"Editor\",LM=\"run Editor.HC\"$  $BT,\"StdLib Structures\",LM=\"run StdLib.HC\"$  $BT,\"JIT Self-Test\",LM=\"jittest\"$\n\n");

    doldoc_print(" $FG,YELLOW$⚡ System Controls:$FG$\n");
    doldoc_print("   $BT,\"Clear Console\",LM=\"clear\"$  $BT,\"Shell Help\",LM=\"help\"$  $BT,\"Refresh Menu\",LM=\"run Menu.HC\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

MenuMain();
