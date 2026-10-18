// ==============================================================================
// Showcase.HC - Sovereign DolDoc 3.0 Master Flagship Capabilities Document
// Architecture: ARMv8-A (AArch64) Ring 0 SASOS | 100% Pure HolyC Execution
// Demonstrates simultaneously in a single unified document:
//  1. Scalable Vector Fonts ($FONT$) at multiple sizes + 6 Semantic Themes
//  2. Native Real-Time Shadertoy Viewports ($SHADER$: Plasma & SDF Raymarching)
//  3. Inline 3D Rotating Perspective Meshes & Involute Gears ($SP$)
//  4. Live Hardware Telemetry & Ring-Buffer Oscilloscopes ($GRAPH$)
//  5. Mathematical Equations ($EQ$: Fractions, Radicals, Summations, Integrals)
//  6. Living Cell Sliders ($SL$), Vector Buttons ($BT$), Checkboxes ($CB$), Links ($LK$)
// ==============================================================================

I64 g_display_brightness = 88;
I64 g_engine_frequency   = 1000;

U0 ShowcaseMain() {
    doldoc_clear();

    I64 scr_w = gfx_get_canvas_width();
    I64 scr_h = gfx_get_canvas_height();
    I64 card_w = (scr_w > 960) ? 116 : 108;

    // --------------------------------------------------------------------------
    // HEADER: SCALABLE VECTOR TYPOGRAPHY & RUNTIME SEMANTIC THEME BAR
    // Row 1 to Row 5 (h=5, ends at Row 6)
    // --------------------------------------------------------------------------
    doldoc_print("\n");
    doldoc_printf("$CARD,title=\"NeoOS Sovereign DolDoc 3.0 (%lldx%lld)\",w=%lld,h=6$\n",
                  scr_w, scr_h, card_w);
    doldoc_print("  $FONT,text=\"NEO-OS 3.0 SOVEREIGN CONTINUUM\",scale=160,color=\"CYAN\"$\n\n");
    doldoc_printf("  Theme: $FG,YELLOW$%s$FG$ | Switch Live: $BT,\"Mocha\",LM=\"theme mocha; showcase\"$ $BT,\"Latte\",LM=\"theme latte; showcase\"$ $BT,\"Tokyo\",LM=\"theme tokyo; showcase\"$ $BT,\"Nord\",LM=\"theme nord; showcase\"$ $BT,\"TempleOS\",LM=\"theme temple; showcase\"$ $BT,\"Cyberpunk\",LM=\"theme cyberpunk; showcase\"$\n",
                  g_theme.name);
    doldoc_print("\n\n");

    // --------------------------------------------------------------------------
    // SECTION 1: NATIVE SHADERTOY, 3D GEARS & OSCILLOSCOPE
    // Row 7 to Row 14 (h=8, ends at Row 15)
    // --------------------------------------------------------------------------
    doldoc_printf("$CARD,title=\"1. Native Shadertoy, 3D Meshes & Oscilloscopes\",w=%lld,h=8$\n", card_w);
    doldoc_print("  Real-time Ring-0 L1 Tile Shaders, 3D Involute Gears, Perspective Cube & Catmull-Rom Telemetry:\n\n");
    doldoc_print("   $SHADER,type=\"plasma\",w=176,h=72$  $SHADER,type=\"torus\",w=176,h=72$  $SP,type=\"gears\",w=140,h=72$  $SP,type=\"cube\",w=140,h=72$  $GRAPH,type=\"sine\",w=176,h=72$\n");
    doldoc_print("\n\n\n\n");

    // --------------------------------------------------------------------------
    // SECTION 2: MATHEMATICAL TYPOGRAPHY & SCALABLE FONTS
    // Row 15 to Row 20 (h=5, ends at Row 20)
    // --------------------------------------------------------------------------
    doldoc_printf("$CARD,title=\"2. Mathematical Typography & Vector Fonts\",w=%lld,h=5$\n", card_w);
    doldoc_print("  Closed-form expressions rendered via subpixel vector primitives & anti-aliased radicals:\n\n");
    doldoc_print("   Gravity: $EQ,FRAC,num=\"G * M1 * M2\",den=\"r^2 + eps\"$    Radical: $EQ,SQRT,rad=\"b^2 - 4*a*c\"$    Euler Sum: $EQ,SUM,expr=\"1/n^2\",lim=\"=pi^2/6\"$    Gauss: $EQ,INT,expr=\"e^(-x^2)dx\"$\n");
    doldoc_print("\n\n");

    // --------------------------------------------------------------------------
    // SECTION 3: LIVING COMPUTATIONAL CELLS ($SL$, $BT$, $CB$, $PB$, $LK$)
    // Row 21 to Row 31 (h=10, ends at Row 31)
    // --------------------------------------------------------------------------
    doldoc_printf("$CARD,title=\"3. Living Computational Cells & Reactive UI\",w=%lld,h=10$\n", card_w);
    doldoc_print("  Direct manipulation cells: drag sliders to dynamically patch JIT variables in real-time:\n\n");
    doldoc_printf("   Shader Speed: $SL,\"g_shader_speed\",min=5,max=100,val=%lld,w=140,target=%lld$  Shader Zoom: $SL,\"g_shader_zoom\",min=10,max=100,val=%lld,w=140,target=%lld$  3D Rot: $SL,\"g_sprite_rot_speed\",min=10,max=100,val=%lld,w=140,target=%lld$\n\n",
                  g_shader_speed, &g_shader_speed, g_shader_zoom, &g_shader_zoom, g_sprite_rot_speed, &g_sprite_rot_speed);
    doldoc_print("   Checkboxes  : $CB,\"VirtIO-GPU DMA\",1$  $CB,\"Acrylic Glass\",1$  $CB,\"Soft Shadows\",1$  Progress: $PB,VAL=96,MAX=100$\n");
    doldoc_print("   Quick Action: $BT,\"Shadertoy IDE\",LM=\"shader\"$  $BT,\"Desktop WM\",LM=\"wm\"$  $BT,\"Disasm (uf)\",LM=\"uf DolDocRedraw\"$  $BT,\"Inspect Src\",LM=\"src Showcase.HC\"$  $BT,\"Run 6!=720\",LM=\"calc\"$\n");
    doldoc_print("   Plumb Links : $LK,\"[Files: ls]\",A=\"ls\"$  $LK,\"[Heap: mem]\",A=\"mem\"$  $LK,\"[Tasks: top]\",A=\"top\"$  $LK,\"[Morphic Halos]\",A=\"inspect g_shader_speed\"$  $LK,\"[Benchmark]\",A=\"bench\"$\n");
    doldoc_print("\n\n");

    // --------------------------------------------------------------------------
    // SECTION 4: REAL-TIME RING-0 HARDWARE, SMP & OMNITAPE TELEMETRY
    // Row 32
    // --------------------------------------------------------------------------
    I64 up_sec = timer_get_uptime_sec();
    I64 up_ms  = timer_get_uptime_ms();
    I64 tape_cmds = doldoc_get_tape_cmd_count();
    I64 wid_count = doldoc_get_widget_count();
    doldoc_printf("  $FG,SAPPHIRE$[TELEMETRY]$FG$ Resolution: $FG,YELLOW$%lldx%lld$FG$ | Uptime: $FG,GREEN$%lld.%03lld s$FG$ | OmniTape Cmds: $FG,CYAN$%lld$FG$ | Widgets: $FG,PEACH$%lld$FG$\n",
                  scr_w, scr_h, up_sec, up_ms % 1000, tape_cmds, wid_count);
}

ShowcaseMain();
0;
