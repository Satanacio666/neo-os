// ==============================================================================
// WM.HC - Sovereign HolyC N-Window Spatial Scene Manager & Compositor Continuum
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Dynamic N-Window Table, Z-Order Stack, KolibriOS Tile Map & CTheme
// ==============================================================================

#define WM_MAX_WINDOWS 8

class CWindow {
    I64 id;
    U8  title[64];
    I64 x;
    I64 y;
    I64 w;
    I64 h;
    I64 is_used;
    I64 is_active;
    I64 is_minimized;
    I64 is_maximized;
    I64 saved_x;
    I64 saved_y;
    I64 saved_w;
    I64 saved_h;
    I64 win_kind; // 0 = Main Console, 1 = Telemetry, 2 = 3D Studio, 3 = Dynamic
    U0 (*draw_content)(CWindow *win);
    I64 (*handle_click)(CWindow *win, I64 mx, I64 my);
};

class CWindowManager {
    I64 count;
    I64 active_id;
    I64 screen_w;
    I64 screen_h;
    I64 is_dirty;
    I64 is_dragging;
    I64 drag_win_id;
    I64 drag_off_x;
    I64 drag_off_y;
    I64 is_resizing;
    I64 resize_win_id;
    I64 resize_orig_w;
    I64 resize_orig_h;
    I64 resize_start_mx;
    I64 resize_start_my;
    I64 menu_open;
    I64 prev_btn;
    I64 last_mx;
    I64 last_my;
    I64 zorder[8]; // Back-to-front window indices (0..count-1)
};

CWindowManager g_wm;
CWindow g_wm_wins[8];
CWindow g_main_win;
CWindow g_tool_win;
I64 g_wm_running = 0;
I64 g_wm_initialized = 0;

U0 wm_set_dirty() {
    g_wm.is_dirty = 1;
}

// ------------------------------------------------------------------------------
// 1. Built-In Secondary Window Renderers (Declarative DolDoc Style)
// ------------------------------------------------------------------------------
U0 ToolWinDraw(CWindow *win) {
    if (!win || win->is_minimized) return;

    I64 wx = win->x;
    I64 wy = win->y;
    I64 ww = win->w;

    // Header badge
    gfx_draw_rounded_rect(wx + 10, wy + 38, ww - 20, 22, 4, g_theme.bg_surface0);
    gfx_draw_string(wx + 18, wy + 42, "✦ NeoOS Sovereign Telemetry & Theme", g_theme.accent_primary, 0);

    // Live hardware & theme diagnostics
    gfx_draw_string(wx + 16, wy + 68, "Arch  : ARMv8-A Ring 0 (EL1 SASOS)", g_theme.status_success, 0);
    gfx_draw_string(wx + 16, wy + 86, "Skin  :", g_theme.text_secondary, 0);
    gfx_draw_string(wx + 80, wy + 86, g_theme.name, g_theme.status_warning, 0);

    // Mini embedded live Shadertoy preview inside Tool Window
    DolDocRenderShaderNode(wx + 16, wy + 106, ww - 32, 68, "plasma");

    // Dynamic animated activity pulse bar ($PB$ style)
    I64 sec = timer_get_uptime_sec();
    I64 bar_w = ((sec * 24 + g_doc_anim_tick * 6) % (ww - 44)) + 12;
    gfx_draw_rounded_rect(wx + 16, wy + 182, ww - 32, 16, 4, g_theme.bg_crust);
    gfx_draw_rounded_rect(wx + 16, wy + 182, bar_w, 16, 4, g_theme.accent_teal);

    // Interactive Theme & App Buttons inside Tool Window
    gfx_draw_rounded_rect(wx + 16, wy + 208, 96, 22, 4, g_theme.bg_surface1);
    gfx_draw_string(wx + 24, wy + 212, "Next Theme", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(wx + 120, wy + 208, 96, 22, 4, g_theme.bg_surface1);
    gfx_draw_string(wx + 128, wy + 212, "Shader IDE", g_theme.accent_cyan, 0);

    gfx_draw_rounded_rect(wx + 224, wy + 208, 96, 22, 4, g_theme.bg_surface1);
    gfx_draw_string(wx + 232, wy + 212, "Showcase", g_theme.status_warning, 0);
}

I64 ToolWinClick(CWindow *win, I64 mx, I64 my) {
    if (!win) return 0;
    I64 wx = win->x;
    I64 wy = win->y;

    if (my >= wy + 208 && my <= wy + 232) {
        if (mx >= wx + 16 && mx <= wx + 112) {
            ThemeApply((g_theme.theme_id + 1) % 6);
            CompositorDamageAll();
            g_wm.is_dirty = 1;
            return 1;
        }
        if (mx >= wx + 120 && mx <= wx + 216) {
            shell_run_command("shader");
            g_wm.is_dirty = 1;
            return 1;
        }
        if (mx >= wx + 224 && mx <= wx + 320) {
            shell_run_command("showcase");
            g_wm.is_dirty = 1;
            return 1;
        }
    }
    return 0;
}

U0 StudioWinDraw(CWindow *win) {
    if (!win || win->is_minimized) return;
    I64 wx = win->x;
    I64 wy = win->y;
    I64 ww = win->w;
    I64 wh = win->h;

    gfx_draw_string(wx + 14, wy + 38, "Live 3D Involute Gears & Oscilloscope:", g_theme.accent_secondary, 0);
    I64 sp_w = (ww - 36) / 2;
    I64 sp_h = wh - 70;
    if (sp_w > 16 && sp_h > 16) {
        DolDocRenderSprite3D(wx + 14, wy + 54, sp_w, sp_h, "gears");
        DolDocRenderGraphNode(wx + 22 + sp_w, wy + 54, sp_w, sp_h, "sine");
    }
}

I64 StudioWinClick(CWindow *win, I64 mx, I64 my) {
    g_wm.is_dirty = 1;
    return 1;
}

U0 DynamicWinDraw(CWindow *win) {
    if (!win || win->is_minimized) return;
    I64 wx = win->x;
    I64 wy = win->y;
    I64 ww = win->w;
    I64 wh = win->h;

    // Header badge
    gfx_draw_rounded_rect(wx + 10, wy + 38, ww - 20, 22, 4, g_theme.bg_surface0);
    gfx_draw_string(wx + 18, wy + 42, "✦ Dynamic Procedural Shader Studio", g_theme.accent_cyan, 0);

    I64 half_w = (ww - 36) / 2;
    I64 sh_h = wh - 98;
    if (half_w > 20 && sh_h > 20) {
        DolDocRenderShaderNode(wx + 14, wy + 66, half_w, sh_h, "torus");
        DolDocRenderShaderNode(wx + 22 + half_w, wy + 66, half_w, sh_h, "wave");
    }

    // Bottom action buttons
    I64 by = wy + wh - 28;
    gfx_draw_rounded_rect(wx + 14, by, 76, 20, 3, g_theme.bg_surface1);
    gfx_draw_string(wx + 22, by + 4, "Torus", g_theme.status_warning, 0);

    gfx_draw_rounded_rect(wx + 98, by, 76, 20, 3, g_theme.bg_surface1);
    gfx_draw_string(wx + 106, by + 4, "Plasma", g_theme.accent_cyan, 0);

    gfx_draw_rounded_rect(wx + 182, by, 76, 20, 3, g_theme.bg_surface1);
    gfx_draw_string(wx + 190, by + 4, "Caustics", g_theme.status_success, 0);
}

I64 DynamicWinClick(CWindow *win, I64 mx, I64 my) {
    if (!win) return 0;
    I64 wx = win->x;
    I64 wy = win->y;
    I64 wh = win->h;
    I64 by = wy + wh - 28;

    if (my >= by && my <= by + 20) {
        if (mx >= wx + 14 && mx <= wx + 90) {
            shell_run_command("shader 1");
            g_wm.is_dirty = 1;
            return 1;
        }
        if (mx >= wx + 98 && mx <= wx + 174) {
            shell_run_command("shader 0");
            g_wm.is_dirty = 1;
            return 1;
        }
        if (mx >= wx + 182 && mx <= wx + 258) {
            shell_run_command("shader 2");
            g_wm.is_dirty = 1;
            return 1;
        }
    }
    return 0;
}

// ------------------------------------------------------------------------------
// 2. Dynamic N-Window Creation, Destruction & Focus Management
// ------------------------------------------------------------------------------
CWindow* WMGetWindowById(I64 id) {
    for (I64 wi = 0; wi < g_wm.count; wi++) {
        CWindow *win = &g_wm_wins[wi];
        if (win->is_used && win->id == id) {
            return win;
        }
    }
    return 0;
}

U0 WMFocusWindow(I64 id) {
    g_wm.active_id = id;
    I64 found_pos = -1;
    for (I64 zi = 0; zi < g_wm.count; zi++) {
        I64 idx = g_wm.zorder[zi];
        CWindow *wz = &g_wm_wins[idx];
        if (wz->id == id) {
            wz->is_active = 1;
            found_pos = zi;
        } else {
            wz->is_active = 0;
        }
    }
    if (found_pos >= 0 && found_pos < g_wm.count - 1) {
        I64 top_idx = g_wm.zorder[found_pos];
        for (I64 zj = found_pos; zj < g_wm.count - 1; zj++) {
            g_wm.zorder[zj] = g_wm.zorder[zj + 1];
        }
        g_wm.zorder[g_wm.count - 1] = top_idx;
    }
    g_wm.is_dirty = 1;
}

I64 WMCreateWindow(U8 *title, I64 x, I64 y, I64 w, I64 h, I64 kind, U64 draw_fn, U64 click_fn) {
    if (g_wm.count >= WM_MAX_WINDOWS) return -1;
    I64 slot = g_wm.count;
    CWindow *win = &g_wm_wins[slot];
    win->id = slot + 1;
    strncpy(win->title, title, 63);
    win->title[63] = 0;
    win->x = x;
    win->y = y;
    win->w = w;
    win->h = h;
    win->is_used = 1;
    win->is_active = 1;
    win->is_minimized = 0;
    win->is_maximized = 0;
    win->saved_x = x;
    win->saved_y = y;
    win->saved_w = w;
    win->saved_h = h;
    win->win_kind = kind;
    win->draw_content = draw_fn;
    win->handle_click = click_fn;

    g_wm.zorder[slot] = slot;
    g_wm.count++;
    WMFocusWindow(win->id);
    return win->id;
}

U0 WMCloseWindow(I64 id) {
    CWindow *win = WMGetWindowById(id);
    if (!win) return;

    if (win->id == 1) {
        // Window 1 is root console - minimize instead of destroy
        win->is_minimized = 1;
        g_wm.is_dirty = 1;
        return;
    }

    CompositorDamageWindow(win->x, win->y, win->w, win->h);
    win->is_used = 0;
    win->is_active = 0;

    // Find its slot in g_wm_wins
    I64 slot = -1;
    for (I64 wi = 0; wi < g_wm.count; wi++) {
        if (&g_wm_wins[wi] == win) {
            slot = wi;
            break;
        }
    }

    // Remove from zorder
    I64 z_pos = -1;
    for (I64 zi = 0; zi < g_wm.count; zi++) {
        if (g_wm.zorder[zi] == slot) {
            z_pos = zi;
            break;
        }
    }
    if (z_pos >= 0) {
        for (I64 zj = z_pos; zj < g_wm.count - 1; zj++) {
            g_wm.zorder[zj] = g_wm.zorder[zj + 1];
        }
    }

    // Focus top remaining window
    if (g_wm.count > 1) {
        I64 new_top = g_wm.zorder[g_wm.count - 2];
        CWindow *top_win = &g_wm_wins[new_top];
        WMFocusWindow(top_win->id);
    }
    g_wm.is_dirty = 1;
}

U0 WMInit() {
    g_wm.screen_w = gfx_get_canvas_width();
    g_wm.screen_h = gfx_get_canvas_height();
    if (g_wm.screen_w <= 0) g_wm.screen_w = 1024;
    if (g_wm.screen_h <= 0) g_wm.screen_h = 768;

    g_wm.is_dirty = 1;
    g_wm.is_dragging = 0;
    g_wm.drag_win_id = 0;
    g_wm.drag_off_x = 0;
    g_wm.drag_off_y = 0;
    g_wm.is_resizing = 0;
    g_wm.resize_win_id = 0;
    g_wm.resize_orig_w = 0;
    g_wm.resize_orig_h = 0;
    g_wm.resize_start_mx = 0;
    g_wm.resize_start_my = 0;
    g_wm.menu_open = 0;
    g_wm.prev_btn = 0;

    if (!g_wm_initialized) {
        g_wm.count = 0;
        I64 main_w = g_wm.screen_w - 384;
        if (main_w < 580) main_w = 580;
        I64 main_h = g_wm.screen_h - 88;

        // Window 1: Central Interactive DolDoc Console & Shell
        WMCreateWindow("NeoOS DolDoc 3.0 Scene Continuum (ARM64 Ring-0)", 16, 36, main_w, main_h, 0, 0, 0);

        // Window 2: Sovereign Telemetry, Theme & Live Shadertoy Monitor
        WMCreateWindow("Sovereign Telemetry & Shader Preview", main_w + 28, 36, 340, 250, 1, ToolWinDraw, ToolWinClick);

        // Window 3: Live 3D Gears & Hardware Oscilloscope Studio
        WMCreateWindow("3D Involute Gears & Oscilloscope", main_w + 28, 298, 340, 210, 2, StudioWinDraw, StudioWinClick);

        WMFocusWindow(1);
        g_wm_initialized = 1;
    }

    // Sync DolDoc viewport to Window 1 client area
    CWindow *w1 = &g_wm_wins[0];
    doldoc_move(w1->x + 4, w1->y + 34, w1->w - 8, w1->h - 40);
}

// ------------------------------------------------------------------------------
// 3. Theme-Aware Window Chrome & Desktop Compositing
// ------------------------------------------------------------------------------
U0 WMDrawWindow(CWindow *win) {
    if (!win || !win->is_used || win->is_minimized) return;

    I64 tb_h = g_theme.titlebar_h;
    if (tb_h < 26) tb_h = 30;
    I64 rad = g_theme.corner_radius;

    // 1. Soft Drop Shadow via Compositor
    CompositorDrawShadow(win->x, win->y, win->w, win->h, 8);

    // 2. Window Border (Semantic active/inactive border from CThemePalette)
    U32 border_col = (win->id == g_wm.active_id) ? g_theme.border_active : g_theme.border_subtle;
    I64 bw = g_theme.border_w;
    if (bw < 1) bw = 1;
    gfx_draw_rect(win->x - bw, win->y - bw, win->w + bw * 2, win->h + bw * 2, border_col);

    // 3. Window Body: Acrylic Glass or Semantic Base/Mantle
    U32 body_bg = (win->win_kind == 0) ? g_theme.bg_mantle : g_theme.bg_base;
    if (g_comp.glass_enabled && win->win_kind != 0) {
        CompositorDrawGlass(win->x, win->y, win->w, win->h, 0xD8);
    } else if (g_comp.rounded_corners && rad > 0) {
        gfx_draw_rounded_rect(win->x, win->y, win->w, win->h, rad, body_bg);
    } else {
        gfx_draw_rect(win->x, win->y, win->w, win->h, body_bg);
    }

    // 4. Titlebar
    U32 tb_col = (win->id == g_wm.active_id) ? g_theme.bg_surface0 : g_theme.bg_mantle;
    gfx_draw_rect(win->x, win->y, win->w, tb_h, tb_col);
    gfx_draw_rect(win->x, win->y + tb_h - 1, win->w, 1, border_col);

    // Title string with truncation guard (Zero Collision with traffic lights!)
    U8 title_buf[64];
    I64 max_title_chars = (win->w - 82) / 8;
    if (max_title_chars < 4) max_title_chars = 4;
    if (strlen(win->title) > max_title_chars) {
        strncpy(title_buf, win->title, max_title_chars - 3);
        title_buf[max_title_chars - 3] = '.';
        title_buf[max_title_chars - 2] = '.';
        title_buf[max_title_chars - 1] = '.';
        title_buf[max_title_chars] = 0;
    } else {
        strcpy(title_buf, win->title);
    }
    gfx_draw_string(win->x + 12, win->y + 7, title_buf, g_theme.text_primary, 0);

    // Traffic-light window control buttons: [X] [+] [-]
    // Close [X]
    gfx_draw_rounded_rect(win->x + win->w - 24, win->y + 7, 16, 16, 3, g_theme.status_danger);
    gfx_draw_char(win->x + win->w - 20, win->y + 7, 'x', g_theme.bg_crust, 0);

    // Maximize [+]
    gfx_draw_rounded_rect(win->x + win->w - 44, win->y + 7, 16, 16, 3, g_theme.status_success);
    gfx_draw_char(win->x + win->w - 40, win->y + 7, '+', g_theme.bg_crust, 0);

    // Minimize [-]
    gfx_draw_rounded_rect(win->x + win->w - 64, win->y + 7, 16, 16, 3, g_theme.status_warning);
    gfx_draw_char(win->x + win->w - 60, win->y + 7, '-', g_theme.bg_crust, 0);

    // Corner resize grip indicator (3 diagonal lines in bottom-right corner)
    if (!win->is_maximized) {
        I64 gx = win->x + win->w;
        I64 gy = win->y + win->h;
        gfx_draw_line(gx - 4, gy - 12, gx - 12, gy - 4, g_theme.text_muted);
        gfx_draw_line(gx - 4, gy - 8,  gx - 8,  gy - 4, g_theme.text_muted);
        gfx_draw_line(gx - 4, gy - 4,  gx - 4,  gy - 4, g_theme.text_muted);
    }

    // 5. Client Content Area with Hardware Scissor Clipping
    I64 cx = win->x + 2;
    I64 cy = win->y + tb_h;
    I64 cw = win->w - 4;
    I64 ch = win->h - tb_h - 2;

    if (cw > 0 && ch > 0) {
        gfx_set_clip(cx, cy, cw, ch);
        if (win->win_kind == 0) {
            doldoc_move(win->x + 4, win->y + tb_h + 2, win->w - 8, win->h - tb_h - 6);
            doldoc_mark_all_dirty();
            doldoc_redraw();
        } else if (win->draw_content) {
            win->draw_content(win);
        }
        gfx_reset_clip();
    }
}

U0 WMDrawWindows() {
    for (I64 zi = 0; zi < g_wm.count; zi++) {
        I64 widx = g_wm.zorder[zi];
        WMDrawWindow(&g_wm_wins[widx]);
    }
}

U0 WMDrawDesktop() {
    // Theme-driven desktop background + subtle grid accent
    gfx_draw_rect(0, 0, g_wm.screen_w, g_wm.screen_h - 40, g_theme.bg_crust);

    // Top-bar status ribbon (28px height)
    gfx_draw_rect(0, 0, g_wm.screen_w, 28, g_theme.bg_mantle);
    gfx_draw_rect(0, 27, g_wm.screen_w, 1, g_theme.border_subtle);
    gfx_draw_string(14, 6, "✦ NeoOS Sovereign 3.0 Desktop Continuum", g_theme.accent_primary, 0);

    // Center theme skin indicator
    gfx_draw_string(390, 6, "Skin:", g_theme.text_muted, 0);
    gfx_draw_string(436, 6, g_theme.name, g_theme.status_warning, 0);

    // Right hardware telemetry
    I64 cur_fps = g_comp.fps;
    if (cur_fps <= 0) cur_fps = 60;
    gfx_draw_string(g_wm.screen_w - 240, 6, "FPS:", g_theme.text_muted, 0);
    gfx_draw_string(g_wm.screen_w - 200, 6, "60", g_theme.status_success, 0);
    gfx_draw_string(g_wm.screen_w - 150, 6, "SMP:", g_theme.text_muted, 0);
    gfx_draw_string(g_wm.screen_w - 110, 6, "4 Cores", g_theme.accent_cyan, 0);
}

U0 WMDrawClockTray() {
    I64 ty = g_wm.screen_h - 40;
    I64 cx = g_wm.screen_w - 124;

    gfx_draw_rounded_rect(cx, ty + 6, 116, 28, 4, g_theme.bg_crust);
    gfx_draw_rect(cx, ty + 6, 116, 1, g_theme.border_subtle);
    gfx_draw_string(cx + 8, ty + 12, "UP:", g_theme.text_muted, 0);

    I64 uptime = timer_get_uptime_sec();
    I64 u_h = (uptime / 100) % 10;
    I64 u_t = (uptime / 10) % 10;
    I64 u_o = uptime % 10;
    gfx_draw_char(cx + 44, ty + 12, '0' + u_h, g_theme.status_success, 0);
    gfx_draw_char(cx + 52, ty + 12, '0' + u_t, g_theme.status_success, 0);
    gfx_draw_char(cx + 60, ty + 12, '0' + u_o, g_theme.status_success, 0);
    gfx_draw_char(cx + 70, ty + 12, 's', g_theme.status_success, 0);

    // Live reactive VSync pulse indicator
    U32 pulse_col = ((g_doc_anim_tick & 15) < 8) ? g_theme.accent_teal : g_theme.bg_surface1;
    gfx_draw_rect(cx + 96, ty + 16, 6, 6, pulse_col);
}

U0 WMDrawMenuDrawer() {
    if (!g_wm.menu_open) return;

    I64 mx = 8;
    I64 my = g_wm.screen_h - 40 - 280;
    I64 mw = 490;
    I64 mh = 274;

    CompositorDrawShadow(mx, my, mw, mh, 12);
    gfx_draw_rect(mx - 1, my - 1, mw + 2, mh + 2, g_theme.border_active);
    CompositorDrawGlass(mx, my, mw, mh, 0xE8);

    // Header
    gfx_draw_rounded_rect(mx + 8, my + 8, mw - 16, 26, 4, g_theme.bg_surface0);
    gfx_draw_string(mx + 16, my + 13, "✦ NeoOS Sovereign Application & Theme Drawer", g_theme.accent_primary, 0);

    // Category 1: Flagship & 3D Shaders
    gfx_draw_string(mx + 12, my + 44, "Flagship & 3D:", g_theme.status_warning, 0);
    gfx_draw_rounded_rect(mx + 110, my + 40, 80, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 116, my + 44, "Showcase", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 196, my + 40, 68, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 202, my + 44, "Shaders", g_theme.accent_cyan, 0);

    gfx_draw_rounded_rect(mx + 270, my + 40, 68, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 276, my + 44, "GLXGears", g_theme.status_success, 0);

    gfx_draw_rounded_rect(mx + 344, my + 40, 68, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 350, my + 44, "Physics", g_theme.status_peach, 0);

    gfx_draw_rounded_rect(mx + 418, my + 40, 60, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 424, my + 44, "HolyGL", g_theme.accent_tertiary, 0);

    // Category 2: Themes & Skins
    gfx_draw_string(mx + 12, my + 80, "Themes & Skins:", g_theme.accent_secondary, 0);
    gfx_draw_rounded_rect(mx + 130, my + 76, 52, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 136, my + 80, "Mocha", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 188, my + 76, 52, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 194, my + 80, "Latte", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 246, my + 76, 52, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 252, my + 80, "Tokyo", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 304, my + 76, 48, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 310, my + 80, "Nord", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 358, my + 76, 60, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 364, my + 80, "Temple", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 424, my + 76, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 430, my + 80, "Cyber", g_theme.accent_primary, 0);

    // Category 3: System & Compiler
    gfx_draw_string(mx + 12, my + 116, "Compiler & JIT:", g_theme.status_success, 0);
    gfx_draw_rounded_rect(mx + 130, my + 112, 74, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 136, my + 116, "Compiler", g_theme.accent_cyan, 0);

    gfx_draw_rounded_rect(mx + 210, my + 112, 74, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 216, my + 116, "JIT Test", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 290, my + 112, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 296, my + 116, "Bench", g_theme.status_warning, 0);

    gfx_draw_rounded_rect(mx + 350, my + 112, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 356, my + 116, "Top", g_theme.status_success, 0);

    gfx_draw_rounded_rect(mx + 410, my + 112, 68, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 416, my + 116, "Memory", g_theme.text_muted, 0);

    // Category 4: Storage & Tools
    gfx_draw_string(mx + 12, my + 152, "Storage & Tools:", g_theme.accent_tertiary, 0);
    gfx_draw_rounded_rect(mx + 130, my + 148, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 136, my + 152, "Filer", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 190, my + 148, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 196, my + 152, "Editor", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 250, my + 148, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 256, my + 152, "Calc", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 310, my + 148, 54, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 316, my + 152, "Fact", g_theme.text_primary, 0);

    gfx_draw_rounded_rect(mx + 370, my + 148, 64, 22, 3, g_theme.bg_surface1);
    gfx_draw_string(mx + 376, my + 152, "Inspect", g_theme.accent_teal, 0);

    // Close tip
    gfx_draw_string(mx + 14, my + 248, "Click outside or on [✦ NeoMenu] to dismiss", g_theme.text_muted, 0);
}

U0 WMDrawTaskbar() {
    I64 ty = g_wm.screen_h - 40;

    gfx_draw_rect(0, ty, g_wm.screen_w, 40, g_theme.bg_mantle);
    gfx_draw_rect(0, ty, g_wm.screen_w, 1, g_theme.border_active);

    // [✦ NeoMenu] Launcher button
    U32 menu_btn_col = g_wm.menu_open ? g_theme.accent_secondary : g_theme.accent_primary;
    gfx_draw_rounded_rect(8, ty + 6, 92, 28, 4, menu_btn_col);
    gfx_draw_string(14, ty + 12, "✦ NeoMenu", g_theme.bg_crust, 0);

    // Quick-launch dock chips: [Showcase] [Shaders] [Theme] [+Win]
    gfx_draw_rounded_rect(106, ty + 6, 74, 28, 4, g_theme.bg_surface0);
    gfx_draw_string(112, ty + 12, "Showcase", g_theme.status_warning, 0);

    gfx_draw_rounded_rect(186, ty + 6, 66, 28, 4, g_theme.bg_surface0);
    gfx_draw_string(192, ty + 12, "Shaders", g_theme.accent_cyan, 0);

    gfx_draw_rounded_rect(258, ty + 6, 56, 28, 4, g_theme.bg_surface0);
    gfx_draw_string(266, ty + 12, "Theme", g_theme.accent_tertiary, 0);

    gfx_draw_rounded_rect(320, ty + 6, 50, 28, 4, g_theme.bg_surface0);
    gfx_draw_string(328, ty + 12, "+Win", g_theme.status_success, 0);

    // Dynamic Window Tabs for all open windows
    I64 tab_x = 378;
    I64 fs_x = g_wm.screen_w - 210;
    for (I64 wi = 0; wi < g_wm.count; wi++) {
        CWindow *w = &g_wm_wins[wi];
        if (w->is_used && tab_x + 96 < fs_x) {
            U32 tcol = (w->id == g_wm.active_id && !w->is_minimized) ? g_theme.bg_surface1 : g_theme.bg_base;
            gfx_draw_rounded_rect(tab_x, ty + 6, 92, 28, 4, tcol);
            if (w->id == g_wm.active_id && !w->is_minimized) {
                gfx_draw_rect(tab_x, ty + 6, 92, 1, g_theme.border_active);
            }

            U8 tab_label[16];
            if (w->win_kind == 0) strcpy(tab_label, "[1] Console");
            else if (w->win_kind == 1) strcpy(tab_label, "[2] Telem");
            else if (w->win_kind == 2) strcpy(tab_label, "[3] Gears");
            else {
                tab_label[0] = '[';
                tab_label[1] = '0' + (w->id % 10);
                tab_label[2] = ']';
                tab_label[3] = ' ';
                strncpy(tab_label + 4, w->title, 6);
                tab_label[10] = 0;
            }
            gfx_draw_string(tab_x + 6, ty + 12, tab_label, g_theme.text_primary, 0);
            tab_x += 96;
        }
    }

    // [Console >] Seamless Switch to Fullscreen DolDoc Mode
    gfx_draw_rounded_rect(fs_x, ty + 6, 82, 28, 4, g_theme.bg_surface0);
    gfx_draw_string(fs_x + 8, ty + 12, "Console >", g_theme.status_peach, 0);

    // Real-time Tray Clock (UP: 123s)
    WMDrawClockTray();
}

// ------------------------------------------------------------------------------
// 4. Unified N-Window Mouse Hit-Testing, Dragging & Resizing
// ------------------------------------------------------------------------------
U0 WMHandleMouse() {
    I64 mx = mouse_get_x();
    I64 my = mouse_get_y();
    I64 btn = mouse_get_btn();
    I64 ty = g_wm.screen_h - 40;

    if ((btn & 1) && !g_wm.prev_btn) {
        // A. Handle Application Drawer Clicks
        if (g_wm.menu_open) {
            I64 d_x = 8;
            I64 d_y = g_wm.screen_h - 40 - 280;
            I64 d_w = 490;
            I64 d_h = 274;

            if (mx >= d_x && mx <= d_x + d_w && my >= d_y && my <= d_y + d_h) {
                // Category 1 Clicks
                if (my >= d_y + 40 && my <= d_y + 62) {
                    if (mx >= d_x + 110 && mx <= d_x + 190) { shell_run_command("showcase"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 196 && mx <= d_x + 264) { shell_run_command("shader"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 270 && mx <= d_x + 338) { shell_run_command("gears"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 344 && mx <= d_x + 412) { shell_run_command("physics"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 418 && mx <= d_x + 478) { shell_run_command("holygl"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                }
                // Category 2 Clicks (Themes)
                if (my >= d_y + 76 && my <= d_y + 98) {
                    if (mx >= d_x + 130 && mx <= d_x + 182) { ThemeApply(0); g_wm.menu_open = 0; CompositorDamageAll(); g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 188 && mx <= d_x + 240) { ThemeApply(1); g_wm.menu_open = 0; CompositorDamageAll(); g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 246 && mx <= d_x + 298) { ThemeApply(2); g_wm.menu_open = 0; CompositorDamageAll(); g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 304 && mx <= d_x + 352) { ThemeApply(3); g_wm.menu_open = 0; CompositorDamageAll(); g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 358 && mx <= d_x + 418) { ThemeApply(4); g_wm.menu_open = 0; CompositorDamageAll(); g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 424 && mx <= d_x + 478) { ThemeApply(5); g_wm.menu_open = 0; CompositorDamageAll(); g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                }
                // Category 3 Clicks (Compiler & JIT)
                if (my >= d_y + 112 && my <= d_y + 134) {
                    if (mx >= d_x + 130 && mx <= d_x + 204) { shell_run_command("run Compiler.HC"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 210 && mx <= d_x + 284) { shell_run_command("run TestJitP0.HC"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 290 && mx <= d_x + 344) { shell_run_command("bench"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 350 && mx <= d_x + 404) { shell_run_command("top"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 410 && mx <= d_x + 478) { shell_run_command("mem"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                }
                // Category 4 Clicks (Storage & Tools)
                if (my >= d_y + 148 && my <= d_y + 170) {
                    if (mx >= d_x + 130 && mx <= d_x + 184) { shell_run_command("filer"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 190 && mx <= d_x + 244) { shell_run_command("edit"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 250 && mx <= d_x + 304) { shell_run_command("run calc.HC"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 310 && mx <= d_x + 364) { shell_run_command("run fact.HC"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                    if (mx >= d_x + 370 && mx <= d_x + 434) { shell_run_command("inspect 0"); g_wm.menu_open = 0; g_wm.is_dirty = 1; g_wm.prev_btn = 1; return; }
                }
                g_wm.prev_btn = 1;
                return;
            } else {
                // Click outside closes menu
                g_wm.menu_open = 0;
                CompositorDamageAll();
                g_wm.is_dirty = 1;
            }
        }

        // B. Taskbar Clicks
        if (my >= ty) {
            I64 fs_x = g_wm.screen_w - 210;
            if (mx >= fs_x && mx <= fs_x + 82) {
                uart_puts("[WM] g_wm_running set to 0 in Taskbar Console click\n");
                g_wm_running = 0;
                g_wm.prev_btn = 1;
                return;
            }
            if (mx >= 8 && mx <= 100) {
                g_wm.menu_open = !g_wm.menu_open;
                CompositorDamageAll();
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            if (mx >= 106 && mx <= 180) {
                shell_run_command("showcase");
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            if (mx >= 186 && mx <= 252) {
                shell_run_command("shader");
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            if (mx >= 258 && mx <= 314) {
                ThemeApply((g_theme.theme_id + 1) % 6);
                CompositorDamageAll();
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            if (mx >= 320 && mx <= 370) {
                if (g_wm.count < WM_MAX_WINDOWS) {
                    I64 off = (g_wm.count * 28) % 160;
                    WMCreateWindow("Shadertoy Torus & Caustics Studio", 140 + off, 80 + off, 360, 240, 3, DynamicWinDraw, DynamicWinClick);
                }
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }

            // Dynamic Window Tab Clicks
            I64 tab_x = 378;
            for (I64 twi = 0; twi < g_wm.count; twi++) {
                CWindow *tw = &g_wm_wins[twi];
                if (tw->is_used && tab_x + 96 < fs_x) {
                    if (mx >= tab_x && mx <= tab_x + 92) {
                        if (tw->is_minimized) {
                            tw->is_minimized = 0;
                            WMFocusWindow(tw->id);
                        } else if (g_wm.active_id == tw->id) {
                            tw->is_minimized = 1;
                        } else {
                            WMFocusWindow(tw->id);
                        }
                        g_wm.is_dirty = 1;
                        g_wm.prev_btn = 1;
                        return;
                    }
                    tab_x += 96;
                }
            }
        }

        // C. Front-to-Back Z-Order Window Hit Testing
        for (I64 zi = g_wm.count - 1; zi >= 0; zi--) {
            I64 widx = g_wm.zorder[zi];
            CWindow *win = &g_wm_wins[widx];
            if (!win->is_used || win->is_minimized) continue;

            if (mx >= win->x && mx < win->x + win->w &&
                my >= win->y && my < win->y + win->h) {

                WMFocusWindow(win->id);
                I64 tb_h = g_theme.titlebar_h;
                if (tb_h < 26) tb_h = 30;

                // 1. Bottom-Right Corner Resize Grip
                if (!win->is_maximized &&
                    mx >= win->x + win->w - 16 && mx <= win->x + win->w + 4 &&
                    my >= win->y + win->h - 16 && my <= win->y + win->h + 4) {
                    g_wm.is_resizing = 1;
                    g_wm.resize_win_id = win->id;
                    g_wm.resize_orig_w = win->w;
                    g_wm.resize_orig_h = win->h;
                    g_wm.resize_start_mx = mx;
                    g_wm.resize_start_my = my;
                    g_wm.prev_btn = 1;
                    return;
                }

                // 2. Titlebar Clicks (Close, Maximize, Minimize, Drag)
                if (my < win->y + tb_h) {
                    // Close [X]
                    if (mx >= win->x + win->w - 24 && mx <= win->x + win->w - 8) {
                        WMCloseWindow(win->id);
                        g_wm.prev_btn = 1;
                        return;
                    }
                    // Maximize [+]
                    if (mx >= win->x + win->w - 44 && mx <= win->x + win->w - 28) {
                        if (!win->is_maximized) {
                            win->saved_x = win->x;
                            win->saved_y = win->y;
                            win->saved_w = win->w;
                            win->saved_h = win->h;
                            win->x = 0;
                            win->y = 28;
                            win->w = g_wm.screen_w;
                            win->h = g_wm.screen_h - 68;
                            win->is_maximized = 1;
                        } else {
                            win->x = win->saved_x;
                            win->y = win->saved_y;
                            win->w = win->saved_w;
                            win->h = win->saved_h;
                            win->is_maximized = 0;
                        }
                        if (win->win_kind == 0) {
                            doldoc_move(win->x + 4, win->y + 34, win->w - 8, win->h - 40);
                            doldoc_mark_all_dirty();
                        }
                        WMFocusWindow(win->id);
                        g_wm.is_dirty = 1;
                        g_wm.prev_btn = 1;
                        return;
                    }
                    // Minimize [-]
                    if (mx >= win->x + win->w - 64 && mx <= win->x + win->w - 48) {
                        win->is_minimized = 1;
                        g_wm.is_dirty = 1;
                        g_wm.prev_btn = 1;
                        return;
                    }

                    // Start Titlebar Dragging
                    if (!win->is_maximized) {
                        g_wm.is_dragging = 1;
                        g_wm.drag_win_id = win->id;
                        g_wm.drag_off_x = mx - win->x;
                        g_wm.drag_off_y = my - win->y;
                    }
                    g_wm.prev_btn = 1;
                    return;
                } else {
                    // 3. Client Area Click
                    if (win->win_kind == 0) {
                        doldoc_handle_click(mx, my);
                    } else if (win->handle_click) {
                        win->handle_click(win, mx, my);
                    }
                    g_wm.is_dirty = 1;
                    g_wm.prev_btn = 1;
                    return;
                }
            }
        }
    }

    // 2. Mouse Dragging / Resizing Motion
    if (btn & 1) {
        if (g_wm.is_resizing) {
            CWindow *rwin = WMGetWindowById(g_wm.resize_win_id);
            if (rwin && !rwin->is_maximized) {
                I64 nw = g_wm.resize_orig_w + (mx - g_wm.resize_start_mx);
                I64 nh = g_wm.resize_orig_h + (my - g_wm.resize_start_my);
                if (nw < 260) nw = 260;
                if (nh < 160) nh = 160;
                if (rwin->x + nw > g_wm.screen_w) nw = g_wm.screen_w - rwin->x;
                if (rwin->y + nh > g_wm.screen_h - 40) nh = g_wm.screen_h - 40 - rwin->y;

                if (rwin->w != nw || rwin->h != nh) {
                    CompositorDamageWindow(rwin->x, rwin->y, rwin->w, rwin->h);
                    rwin->w = nw;
                    rwin->h = nh;
                    CompositorDamageWindow(rwin->x, rwin->y, rwin->w, rwin->h);
                    if (rwin->win_kind == 0) {
                        doldoc_move(rwin->x + 4, rwin->y + 34, rwin->w - 8, rwin->h - 40);
                    }
                    g_wm.is_dirty = 1;
                }
            }
        } else if (g_wm.is_dragging) {
            CWindow *dwin = WMGetWindowById(g_wm.drag_win_id);
            if (dwin && !dwin->is_maximized) {
                I64 nx = mx - g_wm.drag_off_x;
                I64 ny = my - g_wm.drag_off_y;

                // Magnetic Edge Snapping
                if (nx < 12 && nx > -12) nx = 0;
                if (ny < 40 && ny > 16) ny = 28;
                if (nx < -dwin->w + 60) nx = -dwin->w + 60;
                if (nx > g_wm.screen_w - 60) nx = g_wm.screen_w - 60;
                if (ny < 28) ny = 28;
                if (ny > g_wm.screen_h - 60) ny = g_wm.screen_h - 60;

                if (dwin->x != nx || dwin->y != ny) {
                    CompositorDamageWindow(dwin->x, dwin->y, dwin->w, dwin->h);
                    dwin->x = nx;
                    dwin->y = ny;
                    CompositorDamageWindow(dwin->x, dwin->y, dwin->w, dwin->h);
                    if (dwin->win_kind == 0) {
                        doldoc_move(dwin->x + 4, dwin->y + 34, dwin->w - 8, dwin->h - 40);
                    }
                    g_wm.is_dirty = 1;
                }
            }
        } else {
            CWindow *awin = WMGetWindowById(g_wm.active_id);
            if (awin && awin->win_kind == 0) {
                if (doldoc_handle_drag(mx, my)) {
                    g_wm.is_dirty = 1;
                }
            }
        }
    }

    if (!(btn & 1)) {
        if (g_wm.prev_btn & 1) {
            doldoc_handle_mouse_up();
        }
        g_wm.is_dragging = 0;
        g_wm.is_resizing = 0;
        g_wm.prev_btn = 0;
    } else {
        g_wm.prev_btn = 1;
    }
}

U0 menu() {
    g_wm.menu_open = !g_wm.menu_open;
    CompositorDamageAll();
    g_wm.is_dirty = 1;
}

U0 menu_toggle() {
    menu();
}

U0 gpu_config_open() {
    GfxDevicePrintDolDoc();
    g_wm.is_dirty = 1;
}

U0 wm_draw_animating_windows() {
    bench_unified_tick_and_draw();
    WMDrawWindows();
    WMDrawTaskbar();
    WMDrawMenuDrawer();
    CompositorPresent();
    mouse_draw_cursor_front();
}

U0 WMExit() {
    g_wm_running = 0;
}

U0 WMMain() {
    WMInit();
    doldoc_printf("\n$CARD,title=\"NeoOS Sovereign N-Window Spatial Manager (%lldx%lld)\",w=96,h=4$\n",
                  g_wm.screen_w, g_wm.screen_h);
    doldoc_printf("  Active Skin : $FG,CYAN$%s$FG$ | Managed Windows: $FG,YELLOW$%lld$FG$ | KolibriOS Tile Map: ACTIVE\n",
                  g_theme.name, g_wm.count);
    doldoc_print("  Actions     : $BT,\"Spawn New Window\",LM=\"newwin\"$  $BT,\"Switch Theme\",LM=\"theme next\"$  $BT,\"Shadertoy IDE\",LM=\"shader\"$  $BT,\"Fullscreen Console\",LM=\"shell\"$\n");
    doldoc_print("$HR$\n\n");
}

U0 WMEventLoop() {
    uart_puts("[WM] Entered WMEventLoop\n");
    g_wm_running = 1;
    WMInit();
    CompositorDamageAll();
    gfx_dirty_all();
    WMDrawDesktop();
    WMDrawWindows();
    WMDrawTaskbar();
    WMDrawMenuDrawer();
    CompositorPresent();
    mouse_draw_cursor_front();
    g_wm.is_dirty = 0;
    uart_puts("[WM] Completed first frame draw\n");

    I64 last_sec = timer_get_uptime_sec();
    I64 last_anim_ms = timer_get_uptime_ms();

    while (g_wm_running) {
        virtio_input_poll();
        shell_poll();
        if (g_shell_dirty) {
            g_wm.is_dirty = 1;
            g_shell_dirty = 0;
        }

        mouse_poll();
        WMHandleMouse();

        // Optimized Clock Tray Update: only updates the 116x28 clock badge without redrawing the desktop!
        I64 cur_sec = timer_get_uptime_sec();
        if (cur_sec != last_sec) {
            last_sec = cur_sec;
            WMDrawClockTray();
            gfx_swap_rect(g_wm.screen_w - 124, g_wm.screen_h - 40 + 6, 116, 28);
        }

        // Live shader and 3D mesh animation ticks (30 FPS pacing)
        I64 cur_anim_ms = timer_get_uptime_ms();
        if (cur_anim_ms - last_anim_ms >= 33) {
            last_anim_ms = cur_anim_ms;
            g_doc_anim_tick++;
            CWindow *w2 = WMGetWindowById(2);
            if (w2 && w2->is_used && !w2->is_minimized) {
                DolDocRenderShaderNode(w2->x + 16, w2->y + 106, w2->w - 32, 68, "plasma");
                gfx_swap_rect(w2->x + 16, w2->y + 106, w2->w - 32, 68);
            }
            CWindow *w3 = WMGetWindowById(3);
            if (w3 && w3->is_used && !w3->is_minimized) {
                I64 sp_w = (w3->w - 36) / 2;
                I64 sp_h = w3->h - 70;
                if (sp_w > 16 && sp_h > 16) {
                    DolDocRenderSprite3D(w3->x + 14, w3->y + 54, sp_w, sp_h, "gears");
                    DolDocRenderGraphNode(w3->x + 22 + sp_w, w3->y + 54, sp_w, sp_h, "sine");
                    gfx_swap_rect(w3->x + 14, w3->y + 54, w3->w - 28, sp_h);
                }
            }
            doldoc_animate_tick();
        }

        if (bench_unified_is_active()) {
            wm_draw_animating_windows();
            gfx_vsync_wait();
        } else if (g_wm.is_dirty || RenderDirtyActive()) {
            gfx_dirty_all();
            WMDrawDesktop();
            WMDrawWindows();
            WMDrawTaskbar();
            WMDrawMenuDrawer();
            CompositorPresent();
            mouse_draw_cursor_front();
            g_wm.is_dirty = 0;
        }

        task_yield();
    }
    uart_puts("[WM] Exited WMEventLoop while loop\n");
}

if (!g_kernel_booting) {
    WMMain();
}
