// ==============================================================================
// Compositor.HC - Sovereign Pure HolyC desktop compositor (P4.8, post-unification)
//
// P4.8: the duplicate damage tracker + present path and the write-only KolibriOS
// tile maps are GONE. Damage now forwards to the ONE tracker (`GfxDeviceDamage`
// -> Render's `g_canv.dirty`) and presentation reads that same rect; the theme
// palette moved to `apps/Theme.HC`. What remains is the visual-effects layer
// (soft shadow / acrylic glass), the frame-pacing counter and the dashboard.
// P5 will dissolve this module into the DolDoc continuum.
// ==============================================================================

// ------------------------------------------------------------------------------
// 1. Compositor state (display metrics, effect toggles, frame pacing)
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
    I64 frame_count;
    I64 fps;
    I64 last_fps_time_sec;
    I64 frame_time_us;
    I64 last_frame_start_us;
};

CCompositorState g_comp;

// ------------------------------------------------------------------------------
// 2. Damage forwarding — there is exactly ONE damage tracker (Render's dirty
//    rect, written via GfxDeviceDamage). These keep the call-site names WM/Shell
//    already use, but no longer maintain a second bounding box.
// ------------------------------------------------------------------------------
U0 CompositorDamageAll() {
    gfx_dirty_all();
    wm_set_dirty();
}

U0 CompositorDamageRect(I64 x, I64 y, I64 w, I64 h) {
    if (w <= 0 || h <= 0) return;
    GfxDeviceDamage(x, y, w, h);
    wm_set_dirty();
}

U0 CompositorDamageWindow(I64 wx, I64 wy, I64 ww, I64 wh) {
    I64 pad = g_comp.shadows_enabled ? 16 : 4;
    CompositorDamageRect(wx - pad, wy - pad, ww + pad * 2, wh + pad * 2);
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

    if (g_theme.bg_base == 0) {
        ThemeApply(THEME_MOCHA);
    }
    CompositorDamageAll();
}

// ------------------------------------------------------------------------------
// 3. Modern Visual Effects (Driven by the shared CThemePalette)
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

// ------------------------------------------------------------------------------
// 4. Presentation & frame pacing (reads the ONE dirty rect, then presents it)
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

    if (g_comp.dirty_blit_enabled && RenderDirtyActive()) {
        I64 c_x = 0; I64 c_y = 0; I64 c_w = 0; I64 c_h = 0;
        RenderDirtyBounds(&c_x, &c_y, &c_w, &c_h);

        if (c_x < 0) { c_w = c_w + c_x; c_x = 0; }
        if (c_y < 0) { c_h = c_h + c_y; c_y = 0; }
        if (c_x + c_w > g_comp.screen_w) c_w = g_comp.screen_w - c_x;
        if (c_y + c_h > g_comp.screen_h) c_h = g_comp.screen_h - c_y;

        if (c_w >= g_comp.screen_w && c_h >= g_comp.screen_h) {
            GfxPresent(0, 0, g_comp.screen_w, g_comp.screen_h, 1);
        } else if (c_w > 0 && c_h > 0) {
            GfxPresent(c_x, c_y, c_w, c_h, 0);
        }
    } else {
        GfxPresent(0, 0, g_comp.screen_w, g_comp.screen_h, 1);
    }

    gfx_dirty_reset();

    if (g_comp.vsync_hz > 0) {
        gfx_vsync_wait();
    }

    CompositorEndFrame();
}

// ------------------------------------------------------------------------------
// 5. DolDoc interactive compositor & theme dashboard
// ------------------------------------------------------------------------------
U0 CompositorDashboard() {
    doldoc_print("\n$CARD,title=\"NeoOS Sovereign Compositor & Theme Engine\",w=108,h=10$\n");
    doldoc_printf("  Canvas Resolution : $FG,YELLOW$%lld x %lld$FG$ (Pitch: %lld px | Tile Grid: %lld x %lld)\n",
                  g_comp.screen_w, g_comp.screen_h, g_comp.screen_pitch,
                  g_comp.tiles_x, g_comp.tiles_y);
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
// 6. Compositor & Theme command dispatcher
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
        doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Dirty Rect Blitting: %s\n", g_comp.dirty_blit_enabled ? "ENABLED" : "DISABLED");
    } else if (strncmp(cmd, "round", 5) == 0) {
        g_comp.rounded_corners = !g_comp.rounded_corners;
        doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Rounded Corners: %s\n", g_comp.rounded_corners ? "ENABLED" : "DISABLED");
        CompositorDamageAll();
    } else {
        CompositorDashboard();
    }
}

CompositorInit();
0;
