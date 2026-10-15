// ==============================================================================
// Compositor.HC - Sovereign Pure HolyC Desktop Compositor & Styling Continuum
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Scene-Graph Layering, Damage-Rect Blitting, CSS Box Model & Aero Glass
// ==============================================================================

// ------------------------------------------------------------------------------
// 1. Catppuccin Mocha Declarative Color Tokens
// ------------------------------------------------------------------------------
#define CAT_BASE        0xFF1E1E2E
#define CAT_MANTLE      0xFF181825
#define CAT_CRUST       0xFF11111B
#define CAT_SURFACE0    0xFF313244
#define CAT_SURFACE1    0xFF45475A
#define CAT_SURFACE2    0xFF585B70
#define CAT_OVERLAY0    0xFF6C7086
#define CAT_OVERLAY1    0xFF7F849C
#define CAT_TEXT        0xFFCDD6F4
#define CAT_SUBTEXT0    0xFFA6ADC8
#define CAT_SUBTEXT1    0xFFBAC2DE
#define CAT_BLUE        0xFF89B4FA
#define CAT_SAPPHIRE    0xFF74C7EC
#define CAT_TEAL        0xFF94E2D5
#define CAT_GREEN       0xFFA6E3A1
#define CAT_YELLOW      0xFFF9E2AF
#define CAT_PEACH       0xFFFAB387
#define CAT_MAROON      0xFFEBA0AC
#define CAT_RED         0xFFF38BA8
#define CAT_MAUVE       0xFFCBA6F7
#define CAT_PINK        0xFFF5C2E7
#define CAT_FLAMINGO    0xFFF2CDCD
#define CAT_ROSEWATER   0xFFF5E0DC

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
// 3. Compositor State & Damage Tracking Substrate
// ------------------------------------------------------------------------------
class CCompositorState {
    I64 screen_w;
    I64 screen_h;
    I64 screen_pitch;
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
};

CCompositorState g_comp;

// ------------------------------------------------------------------------------
// 4. Compositor Core Primitives & Initialization
// ------------------------------------------------------------------------------
U0 CompositorInit() {
    g_comp.screen_w = gfx_get_canvas_width();
    g_comp.screen_h = gfx_get_canvas_height();
    g_comp.screen_pitch = gfx_get_canvas_pitch();
    g_comp.vsync_hz = 60;
    g_comp.shadows_enabled = 1;
    g_comp.glass_enabled = 1;
    g_comp.rounded_corners = 1;
    g_comp.dirty_blit_enabled = 1;
    g_comp.dmg_active = 1;
    g_comp.dmg_x = 0;
    g_comp.dmg_y = 0;
    g_comp.dmg_w = g_comp.screen_w;
    g_comp.dmg_h = g_comp.screen_h;
    g_comp.frame_count = 0;
    g_comp.fps = 60;
    g_comp.last_fps_time_sec = timer_get_uptime_sec();
    g_comp.frame_time_us = 16666;
    g_comp.last_frame_start_us = timer_get_uptime_us();
}

U0 CompositorClearDamage() {
    g_comp.dmg_active = 0;
    g_comp.dmg_x = 0;
    g_comp.dmg_y = 0;
    g_comp.dmg_w = 0;
    g_comp.dmg_h = 0;
}

U0 CompositorDamageAll() {
    g_comp.dmg_active = 1;
    g_comp.dmg_x = 0;
    g_comp.dmg_y = 0;
    g_comp.dmg_w = g_comp.screen_w;
    g_comp.dmg_h = g_comp.screen_h;
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
    wm_set_dirty();
}

U0 CompositorDamageWindow(I64 wx, I64 wy, I64 ww, I64 wh) {
    I64 pad = g_comp.shadows_enabled ? 16 : 4;
    CompositorDamageRect(wx - pad, wy - pad, ww + pad * 2, wh + pad * 2);
}

// ------------------------------------------------------------------------------
// 5. Modern Visual Effects & Box Rendering
// ------------------------------------------------------------------------------
U0 CompositorDrawShadow(I64 x, I64 y, I64 w, I64 h, I64 spread) {
    if (!g_comp.shadows_enabled) return;
    // Layer 1: Ambient diffusion (8px spread)
    gfx_blend_rect(x - 8, y - 4, w + 16, h + 16, 0x1A000000);
    // Layer 2: Penumbra (5px spread)
    gfx_blend_rect(x - 5, y - 2, w + 10, h + 11, 0x2E000000);
    // Layer 3: Umbra (2px spread)
    gfx_blend_rect(x - 2, y - 1, w + 4,  h + 5,  0x4D000000);
}

U0 CompositorDrawGlass(I64 x, I64 y, I64 w, I64 h, I64 alpha) {
    if (!g_comp.glass_enabled) return;
    U32 col = ((alpha & 0xFF) << 24) | 0x00181C22;
    gfx_blend_rect(x, y, w, h, col);
}

U0 CompositorDrawBox(I64 x, I64 y, I64 w, I64 h, CBoxStyle *st) {
    if (!st) return;

    // 1. Soft Shadow
    if (st->shadow_layers > 0 && g_comp.shadows_enabled) {
        CompositorDrawShadow(x, y, w, h, st->shadow_spread);
    }

    // 2. Border Outline
    if (st->border_width > 0) {
        I64 bw = st->border_width;
        gfx_draw_rect(x - bw, y - bw, w + bw * 2, h + bw * 2, st->border_color);
    }

    // 3. Body: Translucent Glass or Solid Background
    if (st->glass_alpha > 0 && g_comp.glass_enabled) {
        U32 gcol = ((st->glass_alpha & 0xFF) << 24) | (st->bg_color & 0x00FFFFFF);
        gfx_blend_rect(x, y, w, h, gcol);
    } else if (st->border_radius > 0 && g_comp.rounded_corners) {
        gfx_draw_rounded_rect(x, y, w, h, st->border_radius, st->bg_color);
    } else {
        gfx_draw_rect(x, y, w, h, st->bg_color);
    }
}

// ------------------------------------------------------------------------------
// 6. Presentation, Damage Blit & Frame Pacing Engine
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
        g_comp.frame_count = 0;
        g_comp.last_fps_time_sec = cur_sec;
    }
}

U0 CompositorPresent() {
    CompositorBeginFrame();

    if (g_comp.dirty_blit_enabled && g_comp.dmg_active) {
        I64 x = g_comp.dmg_x;
        I64 y = g_comp.dmg_y;
        I64 w = g_comp.dmg_w;
        I64 h = g_comp.dmg_h;

        // Screen clipping
        if (x < 0) { w = w + x; x = 0; }
        if (y < 0) { h = h + y; y = 0; }
        if (x + w > g_comp.screen_w) w = g_comp.screen_w - x;
        if (y + h > g_comp.screen_h) h = g_comp.screen_h - y;

        if (w > 0 && h > 0) {
            gfx_swap_rect(x, y, w, h);
        }
        CompositorClearDamage();
    } else {
        gfx_swap_buffers();
        CompositorClearDamage();
    }

    if (g_comp.vsync_hz > 0) {
        gfx_vsync_wait();
    }

    CompositorEndFrame();
}

// ------------------------------------------------------------------------------
// 7. DolDoc Interactive Compositor Dashboard
// ------------------------------------------------------------------------------
U0 CompositorDashboard() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign Pure HolyC Desktop Compositor ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf(" Canvas Resolution : %lld x %lld (Pitch: %lld bytes/line)\n",
                  g_comp.screen_w, g_comp.screen_h, g_comp.screen_pitch);

    if (g_comp.vsync_hz > 0) {
        doldoc_printf(" V-Sync Mode       : $FG,GREEN$%lld Hz (Hardware Paced)$FG$\n", g_comp.vsync_hz);
    } else {
        doldoc_print(" V-Sync Mode       : $FG,YELLOW$Uncapped / Immediate$FG$\n");
    }

    if (g_comp.shadows_enabled) {
        doldoc_print(" Soft Drop Shadows : $FG,GREEN$3-Layer Ambient Occlusion [ENABLED]$FG$\n");
    } else {
        doldoc_print(" Soft Drop Shadows : $FG,RED$[DISABLED]$FG$\n");
    }

    if (g_comp.glass_enabled) {
        doldoc_print(" Acrylic Glass     : $FG,GREEN$NEON Vectorized SIMD Alpha [ENABLED]$FG$\n");
    } else {
        doldoc_print(" Acrylic Glass     : $FG,RED$[DISABLED]$FG$\n");
    }

    if (g_comp.dirty_blit_enabled) {
        doldoc_print(" Presentation      : $FG,GREEN$Damage Rect Union Blitting (Zero Waste)$FG$\n");
    } else {
        doldoc_print(" Presentation      : $FG,YELLOW$Full Screen Framebuffer Swap$FG$\n");
    }

    doldoc_printf(" Performance       : $FG,YELLOW$FPS: %lld$FG$ | $FG,CYAN$Frame Time: %lld us$FG$\n",
                  g_comp.fps, g_comp.frame_time_us);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_print(" Interactive Quick Toggles:\n");
    doldoc_print("  V-Sync : $BT,\"60 Hz\",LM=\"compositor vsync 60\"$  $BT,\"120 Hz\",LM=\"compositor vsync 120\"$  $BT,\"Uncapped\",LM=\"compositor vsync 0\"$\n");
    doldoc_print("  Effects: $BT,\"Toggle Shadows\",LM=\"compositor shadow\"$  $BT,\"Toggle Glass\",LM=\"compositor glass\"$\n");
    doldoc_print("  Engine : $BT,\"Toggle Dirty Blit\",LM=\"compositor blit\"$  $BT,\"Toggle Corners\",LM=\"compositor round\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

// ------------------------------------------------------------------------------
// 8. Compositor Command Dispatcher
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
        } else if (strcmp(arg, "0") == 0 || strcmp(arg, "off") == 0) {
            g_comp.vsync_hz = 0;
            gfx_vsync_set(0, 0);
            doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ V-Sync disabled (Uncapped FPS).\n");
        } else {
            doldoc_print("Usage: compositor vsync <60 | 120 | 0 | off>\n");
        }
    } else if (strncmp(cmd, "shadow", 6) == 0) {
        g_comp.shadows_enabled = !g_comp.shadows_enabled;
        if (g_comp.shadows_enabled) {
            doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ 3-Layer Diffused Shadows ENABLED.\n");
        } else {
            doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ Shadows DISABLED.\n");
        }
        CompositorDamageAll();
    } else if (strncmp(cmd, "glass", 5) == 0) {
        g_comp.glass_enabled = !g_comp.glass_enabled;
        if (g_comp.glass_enabled) {
            doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ Translucent Acrylic Glass ENABLED.\n");
        } else {
            doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ Acrylic Glass DISABLED.\n");
        }
        CompositorDamageAll();
    } else if (strncmp(cmd, "blit", 4) == 0) {
        g_comp.dirty_blit_enabled = !g_comp.dirty_blit_enabled;
        if (g_comp.dirty_blit_enabled) {
            doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ Dirty Rect Union Blitting ENABLED.\n");
        } else {
            doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ Full-screen Double Buffer Swap ENABLED.\n");
        }
    } else if (strncmp(cmd, "round", 5) == 0) {
        g_comp.rounded_corners = !g_comp.rounded_corners;
        if (g_comp.rounded_corners) {
            doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ Rounded Window Corners ENABLED.\n");
        } else {
            doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ Sharp Window Rectangles ENABLED.\n");
        }
        CompositorDamageAll();
    } else {
        CompositorDashboard();
    }
}

// ------------------------------------------------------------------------------
// 9. Initial Launch
// ------------------------------------------------------------------------------
U0 CompositorMain() {
    CompositorInit();
    CompositorDashboard();
}

CompositorInit();
0;
