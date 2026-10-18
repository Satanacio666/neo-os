// ==============================================================================
// Compositor.HC - Sovereign Pure HolyC Desktop Compositor, Theme & Skin Engine
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Semantic CThemePalette (6 Themes), KolibriOS Tile Map & Aero Glass
// ==============================================================================

#define THEME_MOCHA      0
#define THEME_LATTE      1
#define THEME_TOKYO      2
#define THEME_NORD       3
#define THEME_TEMPLE     4
#define THEME_CYBERPUNK  5
#define THEME_COUNT      6

// ------------------------------------------------------------------------------
// 1. Dynamic Semantic Theme & KolibriOS Skin Specification (Zero Hardcoded Hex)
// ------------------------------------------------------------------------------
class CThemePalette {
    I64 theme_id;
    U8  name[32];
    U32 bg_crust;
    U32 bg_mantle;
    U32 bg_base;
    U32 bg_surface0;
    U32 bg_surface1;
    U32 bg_surface2;
    U32 border_subtle;
    U32 border_active;
    U32 text_primary;
    U32 text_secondary;
    U32 text_muted;
    U32 accent_primary;
    U32 accent_secondary;
    U32 accent_tertiary;
    U32 accent_cyan;
    U32 accent_teal;
    U32 status_success;
    U32 status_warning;
    U32 status_peach;
    U32 status_danger;
    U32 glass_tint;
    U32 shadow_color;
    // KolibriOS SKIN_PARAMS metrics
    I64 titlebar_h;
    I64 border_w;
    I64 corner_radius;
    I64 btn_size;
};

CThemePalette g_theme;

// ------------------------------------------------------------------------------
// 2. CSS-Inspired Declarative Box-Model Specification
// ------------------------------------------------------------------------------
class CBoxStyle {
    I64 border_radius;
    I64 border_width;
    I64 border_color;
    I64 bg_color;
    I64 shadow_layers;
    I64 shadow_spread;
    I64 shadow_color;
    I64 glass_alpha;
};

// ------------------------------------------------------------------------------
// 3. Compositor State, KolibriOS Screen Ownership Map & Damage Tracking
// ------------------------------------------------------------------------------
class CCompositorState {
    I64 screen_w;
    I64 screen_h;
    I64 screen_pitch;
    I64 tiles_x;
    I64 tiles_y;
    I64 vsync_hz;
    I64 shadows_enabled;
    I64 glass_enabled;
    I64 rounded_corners;
    I64 dirty_blit_enabled;
    I64 dmg_active;
    I64 dmg_x;
    I64 dmg_y;
    I64 dmg_w;
    I64 dmg_h;
    I64 frame_count;
    I64 fps;
    I64 last_fps_time_sec;
    I64 frame_time_us;
    I64 last_frame_start_us;
    U8  win_tile_map[640];
    U8  tile_dirty_map[640];
};

CCompositorState g_comp;

// ------------------------------------------------------------------------------
// 4. Runtime Theme Engine (6 Built-In Semantic Themes)
// ------------------------------------------------------------------------------
U0 ThemeApply(I64 tid) {
    if (tid < 0 || tid >= THEME_COUNT) tid = THEME_MOCHA;
    g_theme.theme_id = tid;
    g_theme.titlebar_h = 30;
    g_theme.border_w = 1;
    g_theme.corner_radius = 6;
    g_theme.btn_size = 16;

    if (tid == THEME_MOCHA) {
        strcpy(g_theme.name, "Catppuccin Mocha");
        g_theme.bg_crust         = 0xFF11111B;
        g_theme.bg_mantle        = 0xFF181825;
        g_theme.bg_base          = 0xFF1E1E2E;
        g_theme.bg_surface0      = 0xFF313244;
        g_theme.bg_surface1      = 0xFF45475A;
        g_theme.bg_surface2      = 0xFF585B70;
        g_theme.border_subtle    = 0xFF313244;
        g_theme.border_active    = 0xFF89B4FA;
        g_theme.text_primary     = 0xFFCDD6F4;
        g_theme.text_secondary   = 0xFFBAC2DE;
        g_theme.text_muted       = 0xFF6C7086;
        g_theme.accent_primary   = 0xFF89B4FA;
        g_theme.accent_secondary = 0xFF74C7EC;
        g_theme.accent_tertiary  = 0xFFCBA6F7;
        g_theme.accent_cyan      = 0xFF89DCEB;
        g_theme.accent_teal      = 0xFF94E2D5;
        g_theme.status_success   = 0xFFA6E3A1;
        g_theme.status_warning   = 0xFFF9E2AF;
        g_theme.status_peach     = 0xFFFAB387;
        g_theme.status_danger    = 0xFFF38BA8;
        g_theme.glass_tint       = 0xC8181825;
        g_theme.shadow_color     = 0x4011111B;
    } else if (tid == THEME_LATTE) {
        strcpy(g_theme.name, "Catppuccin Latte");
        g_theme.bg_crust         = 0xFFDCE0E8;
        g_theme.bg_mantle        = 0xFFE6E9EF;
        g_theme.bg_base          = 0xFFEFF1F5;
        g_theme.bg_surface0      = 0xFFCCD0DA;
        g_theme.bg_surface1      = 0xFFBCC0CC;
        g_theme.bg_surface2      = 0xFFACB0BE;
        g_theme.border_subtle    = 0xFFBCC0CC;
        g_theme.border_active    = 0xFF1E66F5;
        g_theme.text_primary     = 0xFF4C4F69;
        g_theme.text_secondary   = 0xFF5C5F77;
        g_theme.text_muted       = 0xFF8C8FA1;
        g_theme.accent_primary   = 0xFF1E66F5;
        g_theme.accent_secondary = 0xFF209FB5;
        g_theme.accent_tertiary  = 0xFF8839EF;
        g_theme.accent_cyan      = 0xFF04A5E5;
        g_theme.accent_teal      = 0xFF179299;
        g_theme.status_success   = 0xFF40A02B;
        g_theme.status_warning   = 0xFFDF8E1D;
        g_theme.status_peach     = 0xFFFE640B;
        g_theme.status_danger    = 0xFFD20F39;
        g_theme.glass_tint       = 0xC8E6E9EF;
        g_theme.shadow_color     = 0x304C4F69;
    } else if (tid == THEME_TOKYO) {
        strcpy(g_theme.name, "Tokyo Night");
        g_theme.bg_crust         = 0xFF16161E;
        g_theme.bg_mantle        = 0xFF1A1B26;
        g_theme.bg_base          = 0xFF24283B;
        g_theme.bg_surface0      = 0xFF292E42;
        g_theme.bg_surface1      = 0xFF3B4261;
        g_theme.bg_surface2      = 0xFF414868;
        g_theme.border_subtle    = 0xFF292E42;
        g_theme.border_active    = 0xFF7AA2F7;
        g_theme.text_primary     = 0xFFC0CAF5;
        g_theme.text_secondary   = 0xFFA9B1D6;
        g_theme.text_muted       = 0xFF565F89;
        g_theme.accent_primary   = 0xFF7AA2F7;
        g_theme.accent_secondary = 0xFF2AC3DE;
        g_theme.accent_tertiary  = 0xFFBB9AF7;
        g_theme.accent_cyan      = 0xFF7DCFFF;
        g_theme.accent_teal      = 0xFF73DACA;
        g_theme.status_success   = 0xFF9ECE6A;
        g_theme.status_warning   = 0xFFE0AF68;
        g_theme.status_peach     = 0xFFFF9E64;
        g_theme.status_danger    = 0xFFF7768E;
        g_theme.glass_tint       = 0xC81A1B26;
        g_theme.shadow_color     = 0x48101018;
    } else if (tid == THEME_NORD) {
        strcpy(g_theme.name, "Nord Arctic");
        g_theme.bg_crust         = 0xFF242933;
        g_theme.bg_mantle        = 0xFF2E3440;
        g_theme.bg_base          = 0xFF3B4252;
        g_theme.bg_surface0      = 0xFF434C5E;
        g_theme.bg_surface1      = 0xFF4C566A;
        g_theme.bg_surface2      = 0xFF616E88;
        g_theme.border_subtle    = 0xFF434C5E;
        g_theme.border_active    = 0xFF88C0D0;
        g_theme.text_primary     = 0xFFECEFF4;
        g_theme.text_secondary   = 0xFFE5E9F0;
        g_theme.text_muted       = 0xFFD8DEE9;
        g_theme.accent_primary   = 0xFF81A1C1;
        g_theme.accent_secondary = 0xFF88C0D0;
        g_theme.accent_tertiary  = 0xFFB48EAD;
        g_theme.accent_cyan      = 0xFF8FBCBB;
        g_theme.accent_teal      = 0xFF8FBCBB;
        g_theme.status_success   = 0xFFA3BE8C;
        g_theme.status_warning   = 0xFFEBCB8B;
        g_theme.status_peach     = 0xFFD08770;
        g_theme.status_danger    = 0xFFBF616A;
        g_theme.glass_tint       = 0xC82E3440;
        g_theme.shadow_color     = 0x401E222A;
    } else if (tid == THEME_TEMPLE) {
        strcpy(g_theme.name, "TempleOS Divine CGA");
        g_theme.bg_crust         = 0xFF000055;
        g_theme.bg_mantle        = 0xFF0000AA;
        g_theme.bg_base          = 0xFF000088;
        g_theme.bg_surface0      = 0xFF0055AA;
        g_theme.bg_surface1      = 0xFF00AAAA;
        g_theme.bg_surface2      = 0xFF55FFFF;
        g_theme.border_subtle    = 0xFF55FFFF;
        g_theme.border_active    = 0xFFFFFF55;
        g_theme.text_primary     = 0xFFFFFFFF;
        g_theme.text_secondary   = 0xFF55FFFF;
        g_theme.text_muted       = 0xFFAAAAAA;
        g_theme.accent_primary   = 0xFFFFFF55;
        g_theme.accent_secondary = 0xFF55FFFF;
        g_theme.accent_tertiary  = 0xFFFF55FF;
        g_theme.accent_cyan      = 0xFF55FFFF;
        g_theme.accent_teal      = 0xFF55FF55;
        g_theme.status_success   = 0xFF55FF55;
        g_theme.status_warning   = 0xFFFFFF55;
        g_theme.status_peach     = 0xFFFFAA00;
        g_theme.status_danger    = 0xFFFF5555;
        g_theme.glass_tint       = 0xD00000AA;
        g_theme.shadow_color     = 0x60000000;
        g_theme.corner_radius    = 0;
        g_theme.border_w         = 2;
    } else if (tid == THEME_CYBERPUNK) {
        strcpy(g_theme.name, "Cyberpunk OLED");
        g_theme.bg_crust         = 0xFF05050A;
        g_theme.bg_mantle        = 0xFF090A14;
        g_theme.bg_base          = 0xFF101224;
        g_theme.bg_surface0      = 0xFF1A1E36;
        g_theme.bg_surface1      = 0xFF282E52;
        g_theme.bg_surface2      = 0xFF384070;
        g_theme.border_subtle    = 0xFF282E52;
        g_theme.border_active    = 0xFFFF007F;
        g_theme.text_primary     = 0xFFE8F7FF;
        g_theme.text_secondary   = 0xFF00F0FF;
        g_theme.text_muted       = 0xFF6A78A0;
        g_theme.accent_primary   = 0xFFFF007F;
        g_theme.accent_secondary = 0xFF00F0FF;
        g_theme.accent_tertiary  = 0xFFBD00FF;
        g_theme.accent_cyan      = 0xFF00F0FF;
        g_theme.accent_teal      = 0xFF00FF9F;
        g_theme.status_success   = 0xFF00FF9F;
        g_theme.status_warning   = 0xFFFCEE09;
        g_theme.status_peach     = 0xFFFF6600;
        g_theme.status_danger    = 0xFFFF0055;
        g_theme.glass_tint       = 0xC8090A14;
        g_theme.shadow_color     = 0x60000000;
    }
}

I64 ThemeSetByName(U8 *tname) {
    if (!tname || !*tname) return g_theme.theme_id;
    while (*tname == ' ') tname++;
    if (strncmp(tname, "mocha", 5) == 0 || strcmp(tname, "0") == 0) {
        ThemeApply(THEME_MOCHA);
    } else if (strncmp(tname, "latte", 5) == 0 || strcmp(tname, "1") == 0 || strncmp(tname, "light", 5) == 0) {
        ThemeApply(THEME_LATTE);
    } else if (strncmp(tname, "tokyo", 5) == 0 || strcmp(tname, "2") == 0) {
        ThemeApply(THEME_TOKYO);
    } else if (strncmp(tname, "nord", 4) == 0 || strcmp(tname, "3") == 0) {
        ThemeApply(THEME_NORD);
    } else if (strncmp(tname, "temple", 6) == 0 || strcmp(tname, "4") == 0 || strncmp(tname, "cga", 3) == 0) {
        ThemeApply(THEME_TEMPLE);
    } else if (strncmp(tname, "cyber", 5) == 0 || strcmp(tname, "5") == 0 || strncmp(tname, "oled", 4) == 0) {
        ThemeApply(THEME_CYBERPUNK);
    } else {
        // Cycle to next theme
        ThemeApply((g_theme.theme_id + 1) % THEME_COUNT);
    }
    return g_theme.theme_id;
}

// ------------------------------------------------------------------------------
// 5. Compositor Core Primitives, KolibriOS Tile Map & Damage Tracking
// ------------------------------------------------------------------------------
U0 CompositorClearDamage() {
    g_comp.dmg_active = 0;
    g_comp.dmg_x = 0;
    g_comp.dmg_y = 0;
    g_comp.dmg_w = 0;
    g_comp.dmg_h = 0;
    for (I64 tc_i = 0; tc_i < 640; tc_i++) {
        g_comp.tile_dirty_map[tc_i] = 0;
    }
}

U0 CompositorDamageAll() {
    g_comp.dmg_active = 1;
    g_comp.dmg_x = 0;
    g_comp.dmg_y = 0;
    g_comp.dmg_w = g_comp.screen_w;
    g_comp.dmg_h = g_comp.screen_h;
    for (I64 td_i = 0; td_i < 640; td_i++) {
        g_comp.tile_dirty_map[td_i] = 1;
    }
    wm_set_dirty();
}

U0 CompositorDamageRect(I64 x, I64 y, I64 w, I64 h) {
    if (w <= 0 || h <= 0) return;
    if (!g_comp.dmg_active) {
        g_comp.dmg_x = x;
        g_comp.dmg_y = y;
        g_comp.dmg_w = w;
        g_comp.dmg_h = h;
        g_comp.dmg_active = 1;
    } else {
        I64 x0 = (g_comp.dmg_x < x) ? g_comp.dmg_x : x;
        I64 y0 = (g_comp.dmg_y < y) ? g_comp.dmg_y : y;
        I64 x1 = (g_comp.dmg_x + g_comp.dmg_w > x + w) ? (g_comp.dmg_x + g_comp.dmg_w) : (x + w);
        I64 y1 = (g_comp.dmg_y + g_comp.dmg_h > y + h) ? (g_comp.dmg_y + g_comp.dmg_h) : (y + h);
        g_comp.dmg_x = x0;
        g_comp.dmg_y = y0;
        g_comp.dmg_w = x1 - x0;
        g_comp.dmg_h = y1 - y0;
    }

    // Mark intersected 64x64 tiles dirty in KolibriOS tile map
    I64 tx0 = x / 64;
    I64 ty0 = y / 64;
    I64 tx1 = (x + w - 1) / 64;
    I64 ty1 = (y + h - 1) / 64;
    if (tx0 < 0) tx0 = 0;
    if (ty0 < 0) ty0 = 0;
    if (tx1 >= g_comp.tiles_x) tx1 = g_comp.tiles_x - 1;
    if (ty1 >= g_comp.tiles_y) ty1 = g_comp.tiles_y - 1;
    for (I64 d_ty = ty0; d_ty <= ty1; d_ty++) {
        for (I64 d_tx = tx0; d_tx <= tx1; d_tx++) {
            I64 tidx = d_ty * g_comp.tiles_x + d_tx;
            if (tidx >= 0 && tidx < 640) {
                g_comp.tile_dirty_map[tidx] = 1;
            }
        }
    }

    wm_set_dirty();
}

U0 CompositorDamageWindow(I64 wx, I64 wy, I64 ww, I64 wh) {
    I64 pad = g_comp.shadows_enabled ? 16 : 4;
    CompositorDamageRect(wx - pad, wy - pad, ww + pad * 2, wh + pad * 2);
}

// Stamp a window ID onto the KolibriOS 64x64 tile ownership map
U0 CompositorStampWindowTiles(I64 win_id, I64 wx, I64 wy, I64 ww, I64 wh) {
    I64 tx0 = wx / 64;
    I64 ty0 = wy / 64;
    I64 tx1 = (wx + ww - 1) / 64;
    I64 ty1 = (wy + wh - 1) / 64;
    if (tx0 < 0) tx0 = 0;
    if (ty0 < 0) ty0 = 0;
    if (tx1 >= g_comp.tiles_x) tx1 = g_comp.tiles_x - 1;
    if (ty1 >= g_comp.tiles_y) ty1 = g_comp.tiles_y - 1;
    for (I64 s_ty = ty0; s_ty <= ty1; s_ty++) {
        for (I64 s_tx = tx0; s_tx <= tx1; s_tx++) {
            I64 tidx = s_ty * g_comp.tiles_x + s_tx;
            if (tidx >= 0 && tidx < 640) {
                g_comp.win_tile_map[tidx] = win_id & 0xFF;
            }
        }
    }
}

I64 CompositorQueryTileOwner(I64 mx, I64 my) {
    I64 tx = mx / 64;
    I64 ty = my / 64;
    if (tx < 0 || tx >= g_comp.tiles_x || ty < 0 || ty >= g_comp.tiles_y) return 0;
    I64 tidx = ty * g_comp.tiles_x + tx;
    if (tidx < 0 || tidx >= 640) return 0;
    return g_comp.win_tile_map[tidx];
}

U0 CompositorInit() {
    g_comp.screen_w = gfx_get_canvas_width();
    g_comp.screen_h = gfx_get_canvas_height();
    g_comp.screen_pitch = gfx_get_canvas_pitch();
    if (g_comp.screen_w <= 0) g_comp.screen_w = 1024;
    if (g_comp.screen_h <= 0) g_comp.screen_h = 768;
    g_comp.tiles_x = (g_comp.screen_w + 63) / 64;
    g_comp.tiles_y = (g_comp.screen_h + 63) / 64;
    if (g_comp.tiles_x > 32) g_comp.tiles_x = 32;
    if (g_comp.tiles_y > 20) g_comp.tiles_y = 20;

    g_comp.vsync_hz = 0;
    g_comp.shadows_enabled = 1;
    g_comp.glass_enabled = 1;
    g_comp.rounded_corners = 1;
    g_comp.dirty_blit_enabled = 1;
    g_comp.frame_count = 0;
    g_comp.fps = 60;
    g_comp.last_fps_time_sec = timer_get_uptime_sec();
    g_comp.frame_time_us = 12000;
    g_comp.last_frame_start_us = timer_get_uptime_us();

    for (I64 ci_i = 0; ci_i < 640; ci_i++) {
        g_comp.win_tile_map[ci_i] = 0;
        g_comp.tile_dirty_map[ci_i] = 1;
    }

    if (g_theme.bg_base == 0) {
        ThemeApply(THEME_MOCHA);
    }
    CompositorDamageAll();
}

// ------------------------------------------------------------------------------
// 6. Modern Visual Effects & Box Rendering (Driven by CThemePalette)
// ------------------------------------------------------------------------------
U0 CompositorDrawShadow(I64 x, I64 y, I64 w, I64 h, I64 spread) {
    if (!g_comp.shadows_enabled) return;
    if (spread <= 0) spread = 6;
    U32 base_rgb = g_theme.shadow_color & 0x00FFFFFF;
    gfx_blend_rect(x - spread, y - spread / 2, w + spread * 2, h + spread * 2, 0x18000000 | base_rgb);
    gfx_blend_rect(x - spread / 2, y - 1, w + spread, h + spread + 2, 0x2C000000 | base_rgb);
    gfx_blend_rect(x - 2, y + 1, w + 4, h + 4, 0x48000000 | base_rgb);
}

U0 CompositorDrawGlass(I64 x, I64 y, I64 w, I64 h, I64 alpha) {
    if (alpha <= 0) alpha = 0xC8;
    U32 col = ((alpha & 0xFF) << 24) | (g_theme.glass_tint & 0x00FFFFFF);
    gfx_blend_rect(x, y, w, h, col);
    // Specular top edge highlight
    gfx_blend_rect(x + 2, y, w - 4, 1, 0x30FFFFFF);
}

U0 CompositorDrawBox(I64 x, I64 y, I64 w, I64 h, CBoxStyle *st) {
    if (!st) return;

    if (st->shadow_layers > 0 && g_comp.shadows_enabled) {
        CompositorDrawShadow(x, y, w, h, st->shadow_spread);
    }

    if (st->border_width > 0) {
        I64 bw = st->border_width;
        gfx_draw_rect(x - bw, y - bw, w + bw * 2, h + bw * 2, st->border_color);
    }

    if (st->glass_alpha > 0 && g_comp.glass_enabled) {
        U32 gcol = ((st->glass_alpha & 0xFF) << 24) | (st->bg_color & 0x00FFFFFF);
        gfx_blend_rect(x, y, w, h, gcol);
    } else if (st->border_radius > 0 && g_comp.rounded_corners && g_theme.corner_radius > 0) {
        gfx_draw_rounded_rect(x, y, w, h, st->border_radius, st->bg_color);
    } else {
        gfx_draw_rect(x, y, w, h, st->bg_color);
    }
}

// ------------------------------------------------------------------------------
// 7. Presentation, Damage Blit & Frame Pacing Engine
// ------------------------------------------------------------------------------
U0 CompositorBeginFrame() {
    g_comp.last_frame_start_us = timer_get_uptime_us();
}

U0 CompositorEndFrame() {
    I64 cur_us = timer_get_uptime_us();
    if (cur_us > g_comp.last_frame_start_us) {
        g_comp.frame_time_us = cur_us - g_comp.last_frame_start_us;
    }
    g_comp.frame_count++;

    I64 cur_sec = timer_get_uptime_sec();
    if (cur_sec != g_comp.last_fps_time_sec) {
        g_comp.fps = g_comp.frame_count;
        if (g_comp.fps <= 0) g_comp.fps = 60;
        g_comp.frame_count = 0;
        g_comp.last_fps_time_sec = cur_sec;
    }
}

U0 CompositorPresent() {
    CompositorBeginFrame();

    if (g_comp.dirty_blit_enabled && g_comp.dmg_active) {
        I64 c_x = g_comp.dmg_x;
        I64 c_y = g_comp.dmg_y;
        I64 c_w = g_comp.dmg_w;
        I64 c_h = g_comp.dmg_h;

        if (c_x < 0) { c_w = c_w + c_x; c_x = 0; }
        if (c_y < 0) { c_h = c_h + c_y; c_y = 0; }
        if (c_x + c_w > g_comp.screen_w) c_w = g_comp.screen_w - c_x;
        if (c_y + c_h > g_comp.screen_h) c_h = g_comp.screen_h - c_y;

        if (c_w >= g_comp.screen_w && c_h >= g_comp.screen_h) {
            gfx_backend_present(0, 0, g_comp.screen_w, g_comp.screen_h, 1);
        } else if (c_w > 0 && c_h > 0) {
            gfx_backend_present(c_x, c_y, c_w, c_h, 0);
        }
        CompositorClearDamage();
    } else {
        gfx_backend_present(0, 0, g_comp.screen_w, g_comp.screen_h, 1);
        CompositorClearDamage();
    }

    if (g_comp.vsync_hz > 0) {
        gfx_vsync_wait();
    }

    CompositorEndFrame();
}

// ------------------------------------------------------------------------------
// 8. DolDoc Interactive Compositor & Theme Dashboard
// ------------------------------------------------------------------------------
U0 CompositorDashboard() {
    doldoc_print("\n$CARD,title=\"NeoOS Sovereign Compositor, KolibriOS Tile Map & Theme Engine\",w=108,h=10$\n");
    doldoc_printf("  Canvas Resolution : $FG,YELLOW$%lld x %lld$FG$ (Pitch: %lld px | Tile Grid: %lld x %lld = %lld L1 tiles)\n",
                  g_comp.screen_w, g_comp.screen_h, g_comp.screen_pitch,
                  g_comp.tiles_x, g_comp.tiles_y, g_comp.tiles_x * g_comp.tiles_y);
    doldoc_printf("  Active Theme Skin : $FG,CYAN$%s$FG$ (ID #%lld | Radius: %lldpx | Border: %lldpx)\n",
                  g_theme.name, g_theme.theme_id, g_theme.corner_radius, g_theme.border_w);
    doldoc_printf("  Effects Pipeline  : Shadows=%s | AcrylicGlass=%s | DirtyBlit=%s | VSync=%lld Hz\n",
                  g_comp.shadows_enabled ? "ON" : "OFF",
                  g_comp.glass_enabled ? "ON" : "OFF",
                  g_comp.dirty_blit_enabled ? "ON" : "OFF",
                  g_comp.vsync_hz);
    doldoc_printf("  Live Frame Pacing : $FG,GREEN$%lld FPS$FG$ ($FG,YELLOW$%lld us/frame$FG$)\n",
                  g_comp.fps, g_comp.frame_time_us);
    doldoc_print("$HR$\n");
    doldoc_print("  $FG,YELLOW$Switch Semantic Theme Skin:$FG$\n");
    doldoc_print("   $BT,\"Mocha\",LM=\"theme mocha\"$  $BT,\"Latte (Light)\",LM=\"theme latte\"$  $BT,\"Tokyo Night\",LM=\"theme tokyo\"$  $BT,\"Nord\",LM=\"theme nord\"$  $BT,\"TempleOS CGA\",LM=\"theme temple\"$  $BT,\"Cyberpunk OLED\",LM=\"theme cyberpunk\"$\n");
    doldoc_print("  $FG,YELLOW$Compositor Pipeline Controls:$FG$\n");
    doldoc_print("   $BT,\"Toggle Shadows\",LM=\"compositor shadow\"$  $BT,\"Toggle Glass\",LM=\"compositor glass\"$  $BT,\"Toggle Corners\",LM=\"compositor round\"$  $BT,\"V-Sync 60Hz\",LM=\"compositor vsync 60\"$  $BT,\"Uncapped\",LM=\"compositor vsync 0\"$\n");
    doldoc_print("$HR$\n\n");
}

// ------------------------------------------------------------------------------
// 9. Compositor & Theme Command Dispatcher
// ------------------------------------------------------------------------------
U0 CompositorCmd(U8 *cmd) {
    if (!cmd) {
        CompositorDashboard();
        return;
    }
    while (*cmd == ' ') cmd++;
    if (*cmd == 0) {
        CompositorDashboard();
        return;
    }

    if (strncmp(cmd, "theme", 5) == 0) {
        U8 *targ = cmd + 5;
        while (*targ == ' ') targ++;
        ThemeSetByName(targ);
        doldoc_set_bg(g_theme.bg_mantle);
        CompositorDamageAll();
        doldoc_printf("$FG,GREEN$[THEME]$FG$ Applied semantic theme skin: $FG,CYAN$%s$FG$\n", g_theme.name);
        return;
    }

    if (strncmp(cmd, "vsync", 5) == 0) {
        U8 *arg = cmd + 5;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "60") == 0) {
            g_comp.vsync_hz = 60;
            gfx_vsync_set(1, 60);
            doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ V-Sync locked to 60 Hz.\n");
        } else if (strcmp(arg, "120") == 0) {
            g_comp.vsync_hz = 120;
            gfx_vsync_set(1, 120);
            doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ V-Sync locked to 120 Hz.\n");
        } else {
            g_comp.vsync_hz = 0;
            gfx_vsync_set(0, 0);
            doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ V-Sync disabled (Uncapped FPS).\n");
        }
    } else if (strncmp(cmd, "shadow", 6) == 0) {
        g_comp.shadows_enabled = !g_comp.shadows_enabled;
        doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Soft Drop Shadows: %s\n", g_comp.shadows_enabled ? "ENABLED" : "DISABLED");
        CompositorDamageAll();
    } else if (strncmp(cmd, "glass", 5) == 0) {
        g_comp.glass_enabled = !g_comp.glass_enabled;
        doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Acrylic Glass: %s\n", g_comp.glass_enabled ? "ENABLED" : "DISABLED");
        CompositorDamageAll();
    } else if (strncmp(cmd, "blit", 4) == 0) {
        g_comp.dirty_blit_enabled = !g_comp.dirty_blit_enabled;
        doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Dirty Tile Blitting: %s\n", g_comp.dirty_blit_enabled ? "ENABLED" : "DISABLED");
    } else if (strncmp(cmd, "round", 5) == 0) {
        g_comp.rounded_corners = !g_comp.rounded_corners;
        doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Rounded Corners: %s\n", g_comp.rounded_corners ? "ENABLED" : "DISABLED");
        CompositorDamageAll();
    } else {
        CompositorDashboard();
    }
}

U0 CompositorMain() {
    CompositorInit();
    CompositorDashboard();
}

CompositorInit();
0;
