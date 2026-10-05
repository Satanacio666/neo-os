// ==============================================================================
// WM.HC - Sovereign HolyC Window Manager & Compositing Environment
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// ==============================================================================

class CWindow {
    I64 id;
    I64 x;
    I64 y;
    I64 w;
    I64 h;
    I64 is_active;
    I64 is_minimized;
    I64 bg_color;
};

class CWindowManager {
    I64 count;
    I64 active_id;
    I64 screen_w;
    I64 screen_h;
};

CWindowManager g_wm;
CWindow g_main_win;

U0 WMInit() {
    g_wm.screen_w = gfx_get_canvas_width();
    g_wm.screen_h = gfx_get_canvas_height();
    g_wm.count = 1;
    g_wm.active_id = 1;

    g_main_win.id = 1;
    g_main_win.w = 880;
    g_main_win.h = 520;
    g_main_win.x = (g_wm.screen_w - 880) / 2;
    g_main_win.y = (g_wm.screen_h - 44 - 520) / 2;
    g_main_win.is_active = 1;
    g_main_win.is_minimized = 0;
    g_main_win.bg_color = 0xFF181825;
}

U0 WMDrawWindow(CWindow *win) {
    if (!win || win->is_minimized) return;

    // 1. Soft Drop Shadow (Alpha blend quad)
    gfx_blend_rect(win->x - 6, win->y - 6, win->w + 12, win->h + 12, 0x40000000);

    // 2. Window Body
    gfx_draw_rect(win->x, win->y, win->w, win->h, win->bg_color);

    // 3. Titlebar
    I64 tb_col = (win->id == g_wm.active_id) ? 0xFF313244 : 0xFF181825;
    gfx_draw_rect(win->x, win->y, win->w, 32, tb_col);

    // Accent line below titlebar
    gfx_draw_rect(win->x, win->y + 31, win->w, 1, 0xFF45475A);

    // Title string
    gfx_draw_string(win->x + 12, win->y + 8, "NeoOS Interactive Shell (DolDoc 2.0 / ARM64 JIT)", 0xFFCDD6F4, 0);

    // Close button [X]
    gfx_draw_rect(win->x + win->w - 28, win->y + 6, 20, 20, 0xFFF38BA8);
    gfx_draw_char(win->x + win->w - 21, win->y + 8, 'x', 0xFF11111B, 0);

    // Minimize button [-]
    gfx_draw_rect(win->x + win->w - 52, win->y + 6, 20, 20, 0xFFF9E2AF);
    gfx_draw_char(win->x + win->w - 45, win->y + 8, '-', 0xFF11111B, 0);
}

U0 WMDrawTaskbar() {
    I64 ty = g_wm.screen_h - 40;

    // Taskbar surface & top border
    gfx_draw_rect(0, ty, g_wm.screen_w, 40, 0xFF11111B);
    gfx_draw_rect(0, ty, g_wm.screen_w, 1, 0xFF313244);

    // [✦ NeoMenu] Launcher button
    gfx_draw_rect(8, ty + 6, 100, 28, 0xFF89B4FA);
    gfx_draw_string(16, ty + 12, "✦ NeoMenu", 0xFF11111B, 0);

    // Main Window tab
    I64 tab_col = (g_main_win.id == g_wm.active_id) ? 0xFF45475A : 0xFF1E1E2E;
    gfx_draw_rect(118, ty + 6, 180, 28, tab_col);
    gfx_draw_string(126, ty + 12, "NeoOS Shell", 0xFFCDD6F4, 0);
}

U0 WMMain() {
    WMInit();

    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Pure HolyC Window Manager (WM.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();
    I64 pitch = gfx_get_canvas_pitch();
    
    doldoc_printf(" Canvas Resolution: $FG,YELLOW$%lld x %lld$FG$ (Pitch: %lld pixels)\n", w, h, pitch);
    doldoc_print(" Pipeline Mode    : Unified HolyGL Orthographic Canvas\n");
    doldoc_printf(" Active Windows   : %lld sovereign window managed\n", g_wm.count);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Desktop Styling & Compositing Controls:\n");
    doldoc_print("  Actions: $BT,\"Compositor Panel\",LM=\"run Compositor.HC\"$  $BT,\"GPU Profile\",LM=\"run GpuConfig.HC\"$\n");
    doldoc_print("  Toggles: $BT,\"VSync 60Hz\",LM=\"vsync 60\"$  $BT,\"Redraw Desktop\",LM=\"run WM.HC\"$\n\n");

    doldoc_print(" Desktop Quick Launch:\n");
    doldoc_print("  Apps: $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$  $BT,\"GLXGears 3D\",LM=\"run Gears.HC\"$  $BT,\"Physics 3D\",LM=\"run Physics3D.HC\"$  $BT,\"Filer\",LM=\"run Filer.HC\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

U0 WMEventLoop() {
    WMInit();
    while (1) {
        wm_step_frame();
    }
}

WMMain();
