// ==============================================================================
// Menu.HC - Sovereign Pure HolyC Application, Shadertoy & Theme Drawer
// Architecture: ARMv8-A Ring 0 SASOS | 100% Native AArch64 JIT Execution
// ==============================================================================

U0 MenuMain() {
    doldoc_print("\n$CARD,title=\"NeoOS 3.0 Sovereign Application, Shadertoy & Theme Drawer (Menu.HC)\",w=110,h=11$\n");
    doldoc_print("  $FONT,text=\"NEO-OS APPLICATION CONTINUUM\",scale=140,color=\"CYAN\"$\n");
    doldoc_printf("  Active Theme Skin: $FG,YELLOW$%s$FG$ | Select any application, shader, or theme below:\n", g_theme.name);
    doldoc_print("$HR$\n");

    doldoc_print("  $FG,YELLOW$1. Flagship Continuum, Shaders & 3D Graphics:$FG$\n");
    doldoc_print("    $BT,\"Master Showcase\",LM=\"showcase\"$  $BT,\"Shadertoy IDE\",LM=\"shader\"$  $BT,\"Desktop WM\",LM=\"wm\"$  $BT,\"GLXGears 3D\",LM=\"gears\"$  $BT,\"Physics 3D\",LM=\"physics\"$  $BT,\"HolyGL\",LM=\"holygl\"$\n");

    doldoc_print("  $FG,YELLOW$2. Runtime Semantic Themes (CThemePalette):$FG$\n");
    doldoc_print("    $BT,\"Catppuccin Mocha\",LM=\"theme mocha\"$  $BT,\"Latte (Light)\",LM=\"theme latte\"$  $BT,\"Tokyo Night\",LM=\"theme tokyo\"$  $BT,\"Nord Arctic\",LM=\"theme nord\"$  $BT,\"TempleOS CGA\",LM=\"theme temple\"$  $BT,\"Cyberpunk OLED\",LM=\"theme cyberpunk\"$\n");

    doldoc_print("  $FG,YELLOW$3. Compiler, Benchmarks & Telemetry:$FG$\n");
    doldoc_print("    $BT,\"Stage-2 Compiler\",LM=\"run Compiler.HC\"$  $BT,\"JIT Suite (P0)\",LM=\"run TestJitP0.HC\"$  $BT,\"HolyBenchmark\",LM=\"bench\"$  $BT,\"Task Top\",LM=\"top\"$  $BT,\"Heap Memory\",LM=\"mem\"$\n");

    doldoc_print("  $FG,YELLOW$4. Storage, Code Inspection & Utilities:$FG$\n");
    doldoc_print("    $BT,\"RedSea Filer\",LM=\"filer\"$  $BT,\"Code Editor\",LM=\"edit\"$  $BT,\"Calculator\",LM=\"run calc.HC\"$  $BT,\"Factorials\",LM=\"run fact.HC\"$  $BT,\"Morphic Halos\",LM=\"inspect\"$\n");
    doldoc_print("$HR$\n\n");
}

MenuMain();
0;
