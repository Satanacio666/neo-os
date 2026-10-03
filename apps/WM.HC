// WM.HC - Pure HolyC Window Manager & Desktop Styling Controller
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 WMMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Pure HolyC Window Manager (WM.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();
    I64 pitch = gfx_get_canvas_pitch();
    
    doldoc_printf(" Canvas Resolution: $FG,YELLOW$%lld x %lld$FG$ (Pitch: %lld pixels)\n", w, h, pitch);
    doldoc_print(" Pipeline Mode    : Sovereign Double-Buffered RAM Canvas\n");
    doldoc_print(" Active Windows   : DolDoc Interactive Terminal Window\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Desktop Styling & Compositing Controls:\n");
    doldoc_print("  Actions: $BT,\"Compositor Panel\",LM=\"run Compositor.HC\"$  $BT,\"GPU Profile\",LM=\"run GpuConfig.HC\"$\n");
    doldoc_print("  Toggles: $BT,\"VSync 60Hz\",LM=\"vsync 60\"$  $BT,\"Aero Shadows\",LM=\"compositor_gui\"$\n\n");

    doldoc_print(" Desktop Quick Launch:\n");
    doldoc_print("  Apps: $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$  $BT,\"L1 Rasterizer\",LM=\"run RasterTile.HC\"$  $BT,\"Filer\",LM=\"run Filer.HC\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

WMMain();
