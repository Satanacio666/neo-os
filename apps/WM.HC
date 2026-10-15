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
    I64 is_maximized;
    I64 saved_x;
    I64 saved_y;
    I64 saved_w;
    I64 saved_h;
    I64 bg_color;
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
    I64 prev_btn;
    I64 last_mx;
    I64 last_my;
};

CWindowManager g_wm;
CWindow g_main_win;
CWindow g_tool_win;

U0 ToolWinDraw(CWindow *win) {
    if (!win || win->is_minimized) return;

    // Header badge
    gfx_draw_rect(win->x + 10, win->y + 40, win->w - 20, 24, 0xFF313244);
    gfx_draw_string(win->x + 18, win->y + 45, "✦ NeoOS Sovereign Task Monitor", 0xFF89B4FA, 0);

    // Live diagnostics list
    gfx_draw_string(win->x + 18, win->y + 74, "Architecture : ARMv8-A Ring 0 (EL1)", 0xFFA6E3A1, 0);
    gfx_draw_string(win->x + 18, win->y + 96, "Memory Model : Single Flat Address Space", 0xFFCDD6F4, 0);
    gfx_draw_string(win->x + 18, win->y + 118, "GPU Engine   : VirtIO-GPU 2D / Page-Flip", 0xFFCDD6F4, 0);
    gfx_draw_string(win->x + 18, win->y + 140, "Compositor   : 100% Pure HolyC (WM.HC)", 0xFFF9E2AF, 0);
    gfx_draw_string(win->x + 18, win->y + 162, "JIT Dispatch : Native AAPCS (BLR X16)", 0xFFCDD6F4, 0);

    // Dynamic animated activity bar
    I64 sec = timer_get_uptime_sec();
    I64 bar_w = ((sec * 20) % (win->w - 40)) + 10;
    gfx_draw_rect(win->x + 18, win->y + 195, win->w - 36, 18, 0xFF181825);
    gfx_draw_rect(win->x + 18, win->y + 195, bar_w, 18, 0xFF89B4FA);
    gfx_draw_string(win->x + 24, win->y + 198, "Pulse: Active", 0xFF11111B, 0);

    // Interactive launch button inside tool window
    gfx_draw_rect(win->x + 18, win->y + 225, 120, 24, 0xFF45475A);
    gfx_draw_string(win->x + 28, win->y + 230, "✦ Launch Top", 0xFFCDD6F4, 0);
}

I64 ToolWinClick(CWindow *win, I64 mx, I64 my) {
    if (!win) return 0;
    // Check [✦ Launch Top] button inside tool window
    if (mx >= win->x + 18 && mx <= win->x + 138 &&
        my >= win->y + 225 && my <= win->y + 249) {
        shell_run_command("top");
        return 1;
    }
    return 0;
}

U0 WMInit() {
    g_wm.screen_w = gfx_get_canvas_width();
    g_wm.screen_h = gfx_get_canvas_height();
    g_wm.count = 2;
    g_wm.active_id = 1;
    g_wm.is_dirty = 1;
    g_wm.is_dragging = 0;
    g_wm.drag_win_id = 0;
    g_wm.drag_off_x = 0;
    g_wm.drag_off_y = 0;
    g_wm.prev_btn = 0;
    g_wm.last_mx = 0;
    g_wm.last_my = 0;

    // Window 1: Central Interactive Shell & DolDoc Console
    g_main_win.id = 1;
    g_main_win.x = 20;
    g_main_win.y = 44;
    g_main_win.w = 620;
    g_main_win.h = g_wm.screen_h - 44 - 48;
    g_main_win.is_active = 1;
    g_main_win.is_minimized = 0;
    g_main_win.is_maximized = 0;
    g_main_win.saved_x = g_main_win.x;
    g_main_win.saved_y = g_main_win.y;
    g_main_win.saved_w = g_main_win.w;
    g_main_win.saved_h = g_main_win.h;
    g_main_win.bg_color = 0xFF181825; // Mantle
    g_main_win.draw_content = 0;
    g_main_win.handle_click = 0;
    doldoc_move(g_main_win.x + 12, g_main_win.y + 40, g_main_win.w - 24, g_main_win.h - 48);

    // Window 2: Sovereign System Monitor & Diagnostics Window
    g_tool_win.id = 2;
    g_tool_win.x = 656;
    g_tool_win.y = 44;
    g_tool_win.w = 348;
    g_tool_win.h = 320;
    g_tool_win.is_active = 0;
    g_tool_win.is_minimized = 0;
    g_tool_win.is_maximized = 0;
    g_tool_win.saved_x = g_tool_win.x;
    g_tool_win.saved_y = g_tool_win.y;
    g_tool_win.saved_w = g_tool_win.w;
    g_tool_win.saved_h = g_tool_win.h;
    g_tool_win.bg_color = 0xFF1E1E2E; // Base
    g_tool_win.draw_content = ToolWinDraw;
    g_tool_win.handle_click = ToolWinClick;
}

U0 WMDrawShadow(CWindow *win) {
    if (!win || win->is_minimized) return;
    CompositorDrawShadow(win->x, win->y, win->w, win->h, 8);
}

U0 WMDrawWindow(CWindow *win) {
    if (!win || win->is_minimized) return;

    // 1. Soft Drop Shadow via Compositor
    WMDrawShadow(win);

    // 2. Window Border (Accent Sapphire glow if active, Surface0 if inactive)
    I64 border_col = (win->id == g_wm.active_id) ? CAT_BLUE : CAT_SURFACE0;
    gfx_draw_rect(win->x - 1, win->y - 1, win->w + 2, win->h + 2, border_col);

    // 3. Window Body: Acrylic Glass or Catppuccin Base
    if (g_comp.glass_enabled) {
        CompositorDrawGlass(win->x, win->y, win->w, win->h, 0xCC);
    } else if (g_comp.rounded_corners) {
        gfx_draw_rounded_rect(win->x, win->y, win->w, win->h, 6, win->bg_color);
    } else {
        gfx_draw_rect(win->x, win->y, win->w, win->h, win->bg_color);
    }

    // 4. Titlebar
    I64 tb_col = (win->id == g_wm.active_id) ? CAT_SURFACE0 : CAT_MANTLE;
    gfx_draw_rect(win->x, win->y, win->w, 32, tb_col);

    // Accent line below titlebar
    gfx_draw_rect(win->x, win->y + 31, win->w, 1, 0xFF45475A);

    // Title string
    if (win->id == 1) {
        gfx_draw_string(win->x + 12, win->y + 8, "NeoOS Interactive Shell (DolDoc 2.0 / ARM64 JIT)", 0xFFCDD6F4, 0);
    } else {
        gfx_draw_string(win->x + 12, win->y + 8, "NeoOS System Monitor & Diagnostics", 0xFFCDD6F4, 0);
    }

    // Traffic-light control buttons:
    // Close button [X] (Red)
    gfx_draw_rect(win->x + win->w - 26, win->y + 8, 16, 16, 0xFFF38BA8);
    gfx_draw_char(win->x + win->w - 21, win->y + 9, 'x', 0xFF11111B, 0);

    // Maximize button [+] (Green)
    gfx_draw_rect(win->x + win->w - 48, win->y + 8, 16, 16, 0xFFA6E3A1);
    gfx_draw_char(win->x + win->w - 43, win->y + 9, '+', 0xFF11111B, 0);

    // Minimize button [-] (Yellow)
    gfx_draw_rect(win->x + win->w - 70, win->y + 8, 16, 16, 0xFFF9E2AF);
    gfx_draw_char(win->x + win->w - 65, win->y + 9, '-', 0xFF11111B, 0);

    // 5. Client Content Area with Hardware Scissor Clipping
    I64 cx = win->x + 2;
    I64 cy = win->y + 32;
    I64 cw = win->w - 4;
    I64 ch = win->h - 34;

    if (cw > 0 && ch > 0) {
        gfx_set_clip(cx, cy, cw, ch);
        if (win->draw_content) {
            win->draw_content(win);
        } else if (win->id == 1) {
            doldoc_mark_all_dirty();
            doldoc_redraw();
        }
        gfx_reset_clip();
    }
}

U0 WMDrawWindows() {
    if (g_wm.active_id == 1) {
        WMDrawWindow(&g_tool_win);
        WMDrawWindow(&g_main_win);
    } else {
        WMDrawWindow(&g_main_win);
        WMDrawWindow(&g_tool_win);
    }
}

U0 WMDrawDesktop() {
    // Deep dark abyss background
    gfx_draw_rect(0, 0, g_wm.screen_w, g_wm.screen_h - 40, 0xFF11111B);

    // Subtle desktop branding
    gfx_draw_string(24, 18, "✦ NeoOS Sovereign SASOS", 0xFF313244, 0);
    gfx_draw_string(24, 36, "ARMv8-A Ring 0 | Pure HolyC Desktop", 0xFF1E1E2E, 0);
}

U0 WMDrawTaskbar() {
    I64 ty = g_wm.screen_h - 40;

    // Taskbar surface & top border
    gfx_draw_rect(0, ty, g_wm.screen_w, 40, 0xFF11111B);
    gfx_draw_rect(0, ty, g_wm.screen_w, 1, 0xFF313244);

    // [✦ NeoMenu] Launcher button
    gfx_draw_rect(8, ty + 6, 96, 28, 0xFF89B4FA);
    gfx_draw_string(14, ty + 12, "✦ NeoMenu", 0xFF11111B, 0);

    // Dock quick-launch chips: [Term] [Bench] [Files] [Edit] [Top]
    gfx_draw_rect(112, ty + 6, 52, 28, 0xFF1E1E2E);
    gfx_draw_string(118, ty + 12, "Term", 0xFFCDD6F4, 0);

    gfx_draw_rect(170, ty + 6, 58, 28, 0xFF1E1E2E);
    gfx_draw_string(176, ty + 12, "Bench", 0xFFCDD6F4, 0);

    gfx_draw_rect(234, ty + 6, 54, 28, 0xFF1E1E2E);
    gfx_draw_string(240, ty + 12, "Files", 0xFFCDD6F4, 0);

    gfx_draw_rect(294, ty + 6, 50, 28, 0xFF1E1E2E);
    gfx_draw_string(300, ty + 12, "Edit", 0xFFCDD6F4, 0);

    gfx_draw_rect(350, ty + 6, 46, 28, 0xFF1E1E2E);
    gfx_draw_string(356, ty + 12, "Top", 0xFFCDD6F4, 0);

    // Running Window Tabs
    // Tab for Shell
    I64 tab1_col = (g_main_win.id == g_wm.active_id && !g_main_win.is_minimized) ? 0xFF45475A : 0xFF181825;
    gfx_draw_rect(404, ty + 6, 130, 28, tab1_col);
    gfx_draw_string(412, ty + 12, "NeoOS Shell", 0xFFCDD6F4, 0);

    // Tab for System Monitor
    I64 tab2_col = (g_tool_win.id == g_wm.active_id && !g_tool_win.is_minimized) ? 0xFF45475A : 0xFF181825;
    gfx_draw_rect(540, ty + 6, 130, 28, tab2_col);
    gfx_draw_string(548, ty + 12, "Sys Monitor", 0xFFCDD6F4, 0);

    // Real-time Tray Clock (Uptime in seconds)
    I64 uptime = timer_get_uptime_sec();
    gfx_draw_rect(g_wm.screen_w - 130, ty + 6, 122, 28, 0xFF181825);
    gfx_draw_string(g_wm.screen_w - 120, ty + 12, "UPTIME: ", 0xFF6C7086, 0);
    I64 u_tens = (uptime / 10) % 10;
    I64 u_ones = uptime % 10;
    I64 u_hundreds = (uptime / 100) % 10;
    if (uptime >= 100) {
        gfx_draw_char(g_wm.screen_w - 56, ty + 12, '0' + u_hundreds, 0xFFA6E3A1, 0);
        gfx_draw_char(g_wm.screen_w - 48, ty + 12, '0' + u_tens, 0xFFA6E3A1, 0);
        gfx_draw_char(g_wm.screen_w - 40, ty + 12, '0' + u_ones, 0xFFA6E3A1, 0);
    } else {
        gfx_draw_char(g_wm.screen_w - 48, ty + 12, '0' + u_tens, 0xFFA6E3A1, 0);
        gfx_draw_char(g_wm.screen_w - 40, ty + 12, '0' + u_ones, 0xFFA6E3A1, 0);
    }
    gfx_draw_char(g_wm.screen_w - 30, ty + 12, 's', 0xFFA6E3A1, 0);
}

U0 WMHandleMouse() {
    I64 mx = mouse_get_x();
    I64 my = mouse_get_y();
    I64 btn = mouse_get_btn();
    I64 ty = g_wm.screen_h - 40;

    // 1. Mouse Button Pressed (Click event)
    if ((btn & 1) && !g_wm.prev_btn) {
        // A. Check Taskbar & Dock
        if (my >= ty) {
            // [✦ NeoMenu]
            if (mx >= 8 && mx <= 104) {
                menu();
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            // [Term] Quick-Launch
            if (mx >= 112 && mx <= 164) {
                g_main_win.is_minimized = 0;
                g_main_win.is_active = 1;
                g_tool_win.is_active = 0;
                g_wm.active_id = 1;
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            // [Bench] Quick-Launch
            if (mx >= 170 && mx <= 228) {
                shell_run_command("bench");
                g_wm.prev_btn = 1;
                return;
            }
            // [Files] Quick-Launch
            if (mx >= 234 && mx <= 288) {
                shell_run_command("filer");
                g_wm.prev_btn = 1;
                return;
            }
            // [Edit] Quick-Launch
            if (mx >= 294 && mx <= 344) {
                shell_run_command("edit");
                g_wm.prev_btn = 1;
                return;
            }
            // [Top] Quick-Launch
            if (mx >= 350 && mx <= 396) {
                shell_run_command("top");
                g_wm.prev_btn = 1;
                return;
            }
            // Shell Tab
            if (mx >= 404 && mx <= 534) {
                if (g_main_win.is_minimized) {
                    g_main_win.is_minimized = 0;
                    g_main_win.is_active = 1;
                    g_tool_win.is_active = 0;
                    g_wm.active_id = 1;
                } else if (g_wm.active_id == 1) {
                    g_main_win.is_minimized = 1;
                } else {
                    g_main_win.is_active = 1;
                    g_tool_win.is_active = 0;
                    g_wm.active_id = 1;
                }
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
            // Sys Monitor Tab
            if (mx >= 540 && mx <= 670) {
                if (g_tool_win.is_minimized) {
                    g_tool_win.is_minimized = 0;
                    g_tool_win.is_active = 1;
                    g_main_win.is_active = 0;
                    g_wm.active_id = 2;
                } else if (g_wm.active_id == 2) {
                    g_tool_win.is_minimized = 1;
                } else {
                    g_tool_win.is_active = 1;
                    g_main_win.is_active = 0;
                    g_wm.active_id = 2;
                }
                g_wm.is_dirty = 1;
                g_wm.prev_btn = 1;
                return;
            }
        }

        // B. Check Window Titlebars & Controls (Active window checked first)
        CWindow *w_top = (g_wm.active_id == 1) ? &g_main_win : &g_tool_win;
        CWindow *w_bot = (g_wm.active_id == 1) ? &g_tool_win : &g_main_win;

        // Test w_top first
        if (!w_top->is_minimized &&
            mx >= w_top->x && mx < w_top->x + w_top->w &&
            my >= w_top->y && my < w_top->y + w_top->h) {

            // Click is inside w_top
            if (my < w_top->y + 32) {
                // Titlebar click: check buttons
                // Close button [X]
                if (mx >= w_top->x + w_top->w - 26 && mx <= w_top->x + w_top->w - 10) {
                    w_top->is_minimized = 1;
                    g_wm.is_dirty = 1;
                    g_wm.prev_btn = 1;
                    return;
                }
                // Maximize button [+]
                if (mx >= w_top->x + w_top->w - 48 && mx <= w_top->x + w_top->w - 32) {
                    if (!w_top->is_maximized) {
                        w_top->saved_x = w_top->x;
                        w_top->saved_y = w_top->y;
                        w_top->saved_w = w_top->w;
                        w_top->saved_h = w_top->h;
                        w_top->x = 0;
                        w_top->y = 0;
                        w_top->w = g_wm.screen_w;
                        w_top->h = g_wm.screen_h - 40;
                        w_top->is_maximized = 1;
                    } else {
                        w_top->x = w_top->saved_x;
                        w_top->y = w_top->saved_y;
                        w_top->w = w_top->saved_w;
                        w_top->h = w_top->saved_h;
                        w_top->is_maximized = 0;
                    }
                    if (w_top->id == 1) {
                        doldoc_move(w_top->x + 12, w_top->y + 40, w_top->w - 24, w_top->h - 48);
                    }
                    g_wm.is_dirty = 1;
                    g_wm.prev_btn = 1;
                    return;
                }
                // Minimize button [-]
                if (mx >= w_top->x + w_top->w - 70 && mx <= w_top->x + w_top->w - 54) {
                    w_top->is_minimized = 1;
                    g_wm.is_dirty = 1;
                    g_wm.prev_btn = 1;
                    return;
                }

                // Start Dragging Titlebar
                if (!w_top->is_maximized) {
                    g_wm.is_dragging = 1;
                    g_wm.drag_win_id = w_top->id;
                    g_wm.drag_off_x = mx - w_top->x;
                    g_wm.drag_off_y = my - w_top->y;
                }
                g_wm.prev_btn = 1;
                return;
            } else {
                // Client area click
                if (w_top->id == 1) {
                    doldoc_handle_click(mx, my);
                } else if (w_top->handle_click) {
                    w_top->handle_click(w_top, mx, my);
                }
                g_wm.prev_btn = 1;
                return;
            }
        }

        // Test w_bot if w_top was not hit
        if (!w_bot->is_minimized &&
            mx >= w_bot->x && mx < w_bot->x + w_bot->w &&
            my >= w_bot->y && my < w_bot->y + w_bot->h) {

            // Elevate w_bot to top
            g_wm.active_id = w_bot->id;
            w_bot->is_active = 1;
            w_top->is_active = 0;
            g_wm.is_dirty = 1;

            if (my < w_bot->y + 32) {
                // Titlebar click: check buttons
                if (mx >= w_bot->x + w_bot->w - 26 && mx <= w_bot->x + w_bot->w - 10) {
                    w_bot->is_minimized = 1;
                    g_wm.prev_btn = 1;
                    return;
                }
                if (mx >= w_bot->x + w_bot->w - 48 && mx <= w_bot->x + w_bot->w - 32) {
                    if (!w_bot->is_maximized) {
                        w_bot->saved_x = w_bot->x;
                        w_bot->saved_y = w_bot->y;
                        w_bot->saved_w = w_bot->w;
                        w_bot->saved_h = w_bot->h;
                        w_bot->x = 0;
                        w_bot->y = 0;
                        w_bot->w = g_wm.screen_w;
                        w_bot->h = g_wm.screen_h - 40;
                        w_bot->is_maximized = 1;
                    } else {
                        w_bot->x = w_bot->saved_x;
                        w_bot->y = w_bot->saved_y;
                        w_bot->w = w_bot->saved_w;
                        w_bot->h = w_bot->saved_h;
                        w_bot->is_maximized = 0;
                    }
                    if (w_bot->id == 1) {
                        doldoc_move(w_bot->x + 12, w_bot->y + 40, w_bot->w - 24, w_bot->h - 48);
                    }
                    g_wm.prev_btn = 1;
                    return;
                }
                if (mx >= w_bot->x + w_bot->w - 70 && mx <= w_bot->x + w_bot->w - 54) {
                    w_bot->is_minimized = 1;
                    g_wm.prev_btn = 1;
                    return;
                }

                // Start Dragging Titlebar
                if (!w_bot->is_maximized) {
                    g_wm.is_dragging = 1;
                    g_wm.drag_win_id = w_bot->id;
                    g_wm.drag_off_x = mx - w_bot->x;
                    g_wm.drag_off_y = my - w_bot->y;
                }
                g_wm.prev_btn = 1;
                return;
            } else {
                // Client area click
                if (w_bot->id == 1) {
                    doldoc_handle_click(mx, my);
                } else if (w_bot->handle_click) {
                    w_bot->handle_click(w_bot, mx, my);
                }
                g_wm.prev_btn = 1;
                return;
            }
        }
    }

    // 2. Mouse Dragging Motion
    if ((btn & 1) && g_wm.is_dragging) {
        CWindow *win = (g_wm.drag_win_id == 1) ? &g_main_win : &g_tool_win;
        I64 nx = mx - g_wm.drag_off_x;
        I64 ny = my - g_wm.drag_off_y;

        // Magnetic Edge Snapping (16px threshold)
        if (nx < 16 && nx > -16) nx = 0;
        if (nx + win->w > g_wm.screen_w - 16 && nx + win->w < g_wm.screen_w + 16) {
            nx = g_wm.screen_w - win->w;
        }
        if (ny < 16 && ny > -16) ny = 0;
        I64 max_y = g_wm.screen_h - 40 - win->h;
        if (ny > max_y - 16 && ny < max_y + 16) {
            ny = max_y;
        }

        // Clamp within visible screen bounds
        if (nx < -win->w + 60) nx = -win->w + 60;
        if (nx > g_wm.screen_w - 60) nx = g_wm.screen_w - 60;
        if (ny < 0) ny = 0;
        if (ny > g_wm.screen_h - 50) ny = g_wm.screen_h - 50;

        if (win->x != nx || win->y != ny) {
            CompositorDamageWindow(win->x, win->y, win->w, win->h);
            win->x = nx;
            win->y = ny;
            CompositorDamageWindow(win->x, win->y, win->w, win->h);
            if (win->id == 1) {
                doldoc_move(win->x + 12, win->y + 40, win->w - 24, win->h - 48);
            }
            g_wm.is_dirty = 1;
        }
    }

    // 3. Mouse Released
    if (!(btn & 1)) {
        g_wm.is_dragging = 0;
        g_wm.prev_btn = 0;
    } else {
        g_wm.prev_btn = 1;
    }
}

U0 WMMain() {
    WMInit();

    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Pure HolyC Sovereign Window Manager ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();
    I64 pitch = gfx_get_canvas_pitch();
    
    doldoc_printf(" Canvas Resolution: $FG,YELLOW$%lld x %lld$FG$ (Pitch: %lld pixels)\n", w, h, pitch);
    doldoc_print(" Styling Engine   : Catppuccin Mocha Declarative Styling (CTheme)\n");
    doldoc_print(" Compositor Model : Sovereign Ring 0 Event Loop (WMEventLoop)\n");
    doldoc_printf(" Sovereign Windows: %lld managed (Shell + Task Monitor)\n", g_wm.count);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Desktop Quick Launch:\n");
    doldoc_print("  Apps: $BT,\"HolyBenchmark\",LM=\"bench\"$  $BT,\"GLXGears 3D\",LM=\"run Gears.HC\"$  $BT,\"Physics 3D\",LM=\"physics\"$  $BT,\"Filer\",LM=\"filer\"$\n");
    doldoc_print("  Tools: $BT,\"System Top\",LM=\"top\"$  $BT,\"Compositor\",LM=\"compositor\"$  $BT,\"GPU Profile\",LM=\"gpuconfig\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

U0 WMEventLoop() {
    doldoc_print("[WM.HC] WMEventLoop starting...\n");
    WMInit();
    gfx_dirty_all();
    WMDrawDesktop();
    WMDrawWindows();
    WMDrawTaskbar();
    CompositorPresent();
    mouse_draw_cursor_front();
    g_wm.is_dirty = 0;

    I64 last_sec = timer_get_uptime_sec();

    while (1) {
        // 1. Non-blocking keyboard & shell poll
        shell_poll();
        if (g_shell_dirty) {
            g_wm.is_dirty = 1;
            g_shell_dirty = 0;
        }

        // 2. Non-blocking mouse poll & dispatch
        mouse_poll();
        WMHandleMouse();

        // 3. Update tray clock when second changes
        I64 cur_sec = timer_get_uptime_sec();
        if (cur_sec != last_sec) {
            last_sec = cur_sec;
            g_wm.is_dirty = 1;
        }

        if (bench_unified_is_active()) {
            wm_draw_animating_windows();
            gfx_vsync_wait();
        } else if (g_wm.is_dirty || g_comp.dmg_active) {
            gfx_dirty_all();
            WMDrawDesktop();
            WMDrawWindows();
            WMDrawTaskbar();
            CompositorPresent();
            mouse_draw_cursor_front();
            g_wm.is_dirty = 0;
        }

        // 5. Cooperative yield to scheduler tasks
        task_yield();

        // 6. CPU cycle budgeting: When system is idle, yield CPU execution slice
        if (!bench_unified_is_active() && !g_wm.is_dirty && !keyboard_has_char()) {
            // Idle yield
        }
    }
}

WMMain();
