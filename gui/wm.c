#include "wm.h"
#include "render.h"
#include "menu.h"
#include "../kernel/mem/kheap.h"
#include <uefi.h>

static window_t window_list[MAX_WINDOWS];
static int      window_count = 0;
static int      active_window_idx = -1;
static uint32_t screen_width = 1024;
static uint32_t screen_height = 768;
static int      wm_dirty_flag = 1;

int wm_is_dirty(void) {
    return wm_dirty_flag;
}

void wm_set_dirty(void) {
    wm_dirty_flag = 1;
}

void wm_clear_dirty(void) {
    wm_dirty_flag = 0;
}

void wm_init(uint32_t screen_w, uint32_t screen_h) {
    screen_width = screen_w;
    screen_height = screen_h;
    window_count = 0;
    active_window_idx = -1;
    wm_dirty_flag = 1;

    for (int i = 0; i < MAX_WINDOWS; i++) {
        window_list[i].id = 0;
        window_list[i].is_active = 0;
        window_list[i].is_minimized = 0;
    }
}

window_t* wm_create_window(const char *title, int x, int y, int w, int h) {
    if (window_count >= MAX_WINDOWS) return NULL;

    int idx = window_count++;
    window_t *win = &window_list[idx];
    win->id = (uint32_t)(idx + 1);
    strncpy(win->title, title ? title : "Window", sizeof(win->title) - 1);
    win->title[sizeof(win->title) - 1] = '\0';
    win->x = x;
    win->y = y;
    win->width = w;
    win->height = h;
    win->saved_x = win->x;
    win->saved_y = win->y;
    win->saved_w = win->width;
    win->saved_h = win->height;
    win->is_active = 1;
    win->is_minimized = 0;
    win->is_maximized = 0;
    win->custom_render = NULL;
    win->custom_update = NULL;
    win->custom_click = NULL;
    win->user_data = NULL;
    wm_dirty_flag = 1;

    // Deactivate previous active window
    if (active_window_idx >= 0 && active_window_idx < window_count) {
        window_list[active_window_idx].is_active = 0;
    }
    active_window_idx = idx;

    return win;
}

void wm_destroy_window(uint32_t id) {
    int idx = -1;
    for (int i = 0; i < window_count; i++) {
        if (window_list[i].id == id) {
            idx = i;
            break;
        }
    }
    if (idx < 0) return;
    for (int i = idx; i < window_count - 1; i++) {
        window_list[i] = window_list[i + 1];
    }
    window_count--;
    if (active_window_idx >= window_count) {
        active_window_idx = window_count - 1;
    }
    if (active_window_idx >= 0) {
        window_list[active_window_idx].is_active = 1;
    }
}

window_t* wm_get_window_by_id(uint32_t id) {
    for (int i = 0; i < window_count; i++) {
        if (window_list[i].id == id) return &window_list[i];
    }
    return NULL;
}

int wm_get_window_count(void) {
    return window_count;
}

window_t* wm_get_active(void) {
    if (active_window_idx >= 0 && active_window_idx < window_count) {
        return &window_list[active_window_idx];
    }
    return NULL;
}

void wm_draw_desktop(void) {
    // 1. Wallpaper background (KDE Breeze Dark gradient style)
    gfx_clear(0xFF1E242B);

    // Desktop subtle grid pattern
    for (uint32_t y = 30; y < screen_height - 50; y += 40) {
        for (uint32_t x = 30; x < screen_width; x += 40) {
            gfx_put_pixel(x, y, 0xFF272D36);
        }
    }

    // 2. Bottom Taskbar Panel
    uint32_t panel_h = 44;
    uint32_t panel_y = screen_height - panel_h;
    gfx_draw_rect(0, panel_y, screen_width, panel_h, COLOR_PANEL_HEADER);
    gfx_draw_rect(0, panel_y, screen_width, 2, COLOR_ACCENT_CYAN); // Accent highlight

    // Application Launcher Button ("[*] NeoMenu")
    gfx_draw_rounded_rect(8, panel_y + 5, 114, 34, 6, COLOR_ACCENT_CYAN);
    gfx_draw_string(14, panel_y + 14, "[*] NeoMenu", COLOR_TEXT_WHITE, 0);

    // Running Window Tabs in Panel
    uint32_t tab_x = 130;
    for (int i = 0; i < window_count; i++) {
        window_t *w = &window_list[i];
        uint32_t tab_w = 170;
        uint32_t tab_color = w->is_active ? COLOR_WINDOW_BODY : COLOR_PANEL_HEADER;
        gfx_draw_rounded_rect(tab_x, panel_y + 6, tab_w, 32, 4, tab_color);

        if (w->is_active) {
            gfx_draw_rect(tab_x + 4, panel_y + 36, tab_w - 8, 2, COLOR_ACCENT_CYAN);
        }

        char title_trunc[22];
        strncpy(title_trunc, w->title, 18);
        title_trunc[18] = '\0';
        gfx_draw_string(tab_x + 10, panel_y + 14, title_trunc, COLOR_TEXT_WHITE, 0);
        tab_x += tab_w + 6;
    }

    // System Tray (Right side of panel) with Live Clock & Telemetry
    uint32_t tray_w = 290;
    uint32_t tray_x = screen_width - tray_w - 8;
    gfx_draw_rounded_rect(tray_x, panel_y + 6, tray_w, 32, 4, COLOR_WINDOW_BODY);

    extern uint64_t timer_get_ticks(void);
    uint64_t ticks = timer_get_ticks();
    uint64_t sec = ticks / 100;
    uint64_t s = sec % 60;
    uint64_t m = (sec / 60) % 60;
    uint64_t h = (sec / 3600) % 24;

    char tray_buf[64];
    snprintf(tray_buf, sizeof(tray_buf), "CPU [||||]  %02llu:%02llu:%02llu | Ring 0",
             (unsigned long long)h, (unsigned long long)m, (unsigned long long)s);
    gfx_draw_string(tray_x + 12, panel_y + 14, tray_buf, COLOR_ACCENT_CYAN, 0);
}

void wm_draw_window(window_t *win) {
    if (!win || win->is_minimized) return;

    // 1. Drop Shadow
    gfx_draw_shadow(win->x, win->y, win->width, win->height, 8);

    // 2. Window Body (Rounded)
    gfx_draw_rounded_rect(win->x, win->y, win->width, win->height, 8, COLOR_WINDOW_BODY);

    // 3. Titlebar
    uint32_t title_h = 36;
    uint32_t title_color = win->is_active ? COLOR_PANEL_HEADER : 0xFF232629;
    gfx_draw_rounded_rect(win->x, win->y, win->width, title_h, 8, title_color);
    gfx_draw_rect(win->x, win->y + title_h - 4, win->width, 4, title_color);

    // Title text
    uint32_t title_text_color = win->is_active ? COLOR_TEXT_WHITE : COLOR_TEXT_MUTED;
    gfx_draw_string(win->x + 16, win->y + 10, win->title, title_text_color, 0);

    // Window Control Buttons (Close, Maximize, Minimize)
    gfx_draw_rounded_rect(win->x + win->width - 24, win->y + 11, 14, 14, 7, COLOR_BTN_CLOSE);
    gfx_draw_rounded_rect(win->x + win->width - 44, win->y + 11, 14, 14, 7, COLOR_BTN_MAX);
    gfx_draw_rounded_rect(win->x + win->width - 64, win->y + 11, 14, 14, 7, COLOR_BTN_MIN);

    // 4. Client Content Area with strict clipping (Terry Davis draw_it pattern)
    int client_x = win->x + 2;
    int client_y = win->y + (int)title_h;
    int client_w = win->width - 4;
    int client_h = win->height - (int)title_h - 2;

    if (client_w > 0 && client_h > 0) {
        gfx_set_clip(client_x, client_y, client_w, client_h);
        if (win->custom_render) {
            win->custom_render(win, win->user_data);
        } else if (win->id == 1) {
            doldoc_redraw();
        }
        gfx_reset_clip();
    }
}

void wm_draw_all(void) {
    wm_draw_desktop();
    for (int i = 0; i < window_count; i++) {
        wm_draw_window(&window_list[i]);
    }
    wm_dirty_flag = 0;
}

void wm_draw_animating_windows(void) {
    for (int i = 0; i < window_count; i++) {
        window_t *w = &window_list[i];
        if (!w->is_minimized && w->custom_render) {
            int client_x = w->x + 2;
            int client_y = w->y + 36;
            int client_w = w->width - 4;
            int client_h = w->height - 38;
            if (client_w > 0 && client_h > 0) {
                gfx_set_clip(client_x, client_y, client_w, client_h);
                w->custom_render(w, w->user_data);
                gfx_reset_clip();
                gfx_swap_rect(client_x, client_y, client_w, client_h);
            }
        }
    }
}

static void wm_bring_to_front(int idx) {
    if (idx < 0 || idx >= window_count || idx == window_count - 1) {
        active_window_idx = window_count - 1;
        return;
    }
    window_t target = window_list[idx];
    for (int i = idx; i < window_count - 1; i++) {
        window_list[i] = window_list[i + 1];
    }
    window_list[window_count - 1] = target;
    for (int i = 0; i < window_count; i++) {
        window_list[i].is_active = (i == window_count - 1);
    }
    active_window_idx = window_count - 1;
}

static int is_resizing = 0;
static int resize_win_idx = -1;
static int is_dragging = 0;
static int drag_win_idx = -1;
static int drag_offset_x = 0;
static int drag_offset_y = 0;
static int prev_left_btn = 0;
static int app_menu_open = 0;

void wm_handle_mouse(mouse_state_t mouse) {
    uint32_t panel_h = 44;
    uint32_t panel_y = screen_height - panel_h;

    // 1. Mouse Button Pressed (Click event)
    if (mouse.left_button && !prev_left_btn) {
        // A. Check bottom taskbar panel
        if ((uint32_t)mouse.y >= panel_y) {
            // Check Start Menu / NeoMenu button
            if (mouse.x >= 8 && mouse.x <= 124) {
                menu_toggle();
                wm_dirty_flag = 1;
                wm_draw_all();
                doldoc_redraw();
                mouse_draw_cursor();
                gfx_swap_buffers();
                prev_left_btn = 1;
                return;
            }

            // Check Window Tabs
            uint32_t tab_x = 130;
            for (int i = 0; i < window_count; i++) {
                uint32_t tab_w = 170;
                if (mouse.x >= (int)tab_x && mouse.x < (int)(tab_x + tab_w)) {
                    window_list[i].is_minimized = 0;
                    window_list[i].is_active = 1;
                    if (active_window_idx >= 0 && active_window_idx != i) {
                        window_list[active_window_idx].is_active = 0;
                    }
                    active_window_idx = i;
                    wm_dirty_flag = 1;
                    wm_draw_all();
                    doldoc_redraw();
                    mouse_draw_cursor();
                    gfx_swap_buffers();
                    prev_left_btn = 1;
                    return;
                }
                tab_x += tab_w + 6;
            }
        }

        // B. Check App Menu Items if open
        if (app_menu_open && mouse.x >= 8 && mouse.x <= 208) {
            uint32_t menu_y = panel_y - 164;
            if (mouse.y >= (int)menu_y && mouse.y < (int)panel_y) {
                int item = (mouse.y - menu_y) / 28;
                app_menu_open = 0;
                extern void shell_run_command(const char *cmd);
                if (item == 0) shell_run_command("help");
                else if (item == 1) shell_run_command("mem");
                else if (item == 2) shell_run_command("tasks");
                else if (item == 3) shell_run_command("sym");
                else if (item == 4) shell_run_command("reboot");
                wm_draw_all();
                doldoc_redraw();
                mouse_draw_cursor();
                gfx_swap_buffers();
                prev_left_btn = 1;
                return;
            }
        }
        if (app_menu_open) {
            app_menu_open = 0;
            wm_draw_all();
            doldoc_redraw();
        }

        // C. Check Window Resizing, Titlebars & Controls
        for (int i = window_count - 1; i >= 0; i--) {
            window_t *win = &window_list[i];
            if (win->is_minimized) continue;

            // Check Bottom-Right corner resize
            if (mouse.x >= win->x + win->width - 16 && mouse.x <= win->x + win->width + 4 &&
                mouse.y >= win->y + win->height - 16 && mouse.y <= win->y + win->height + 4) {
                wm_bring_to_front(i);
                is_resizing = 1;
                resize_win_idx = window_count - 1;
                prev_left_btn = 1;
                return;
            }

            if (mouse.x >= win->x && mouse.x < win->x + win->width &&
                mouse.y >= win->y && mouse.y < win->y + 36) {

                wm_bring_to_front(i);
                win = &window_list[window_count - 1];
                int win_idx = window_count - 1;

                // Check Close button
                if (mouse.x >= win->x + win->width - 26 && mouse.x <= win->x + win->width - 8) {
                    if (win->id == 1) {
                        win->is_minimized = 1;
                    } else {
                        wm_destroy_window(win->id);
                    }
                    wm_draw_all();
                    mouse_draw_cursor();
                    gfx_swap_buffers();
                    prev_left_btn = 1;
                    return;
                }

                // Check Maximize button
                if (mouse.x >= win->x + win->width - 46 && mouse.x <= win->x + win->width - 28) {
                    if (!win->is_maximized) {
                        win->saved_x = win->x;
                        win->saved_y = win->y;
                        win->saved_w = win->width;
                        win->saved_h = win->height;
                        win->x = 0;
                        win->y = 0;
                        win->width = screen_width;
                        win->height = screen_height - panel_h;
                        win->is_maximized = 1;
                    } else {
                        win->x = win->saved_x;
                        win->y = win->saved_y;
                        win->width = win->saved_w;
                        win->height = win->saved_h;
                        win->is_maximized = 0;
                    }
                    if (win->id == 1) {
                        doldoc_move(win->x + 12, win->y + 40, win->width - 24, win->height - 48);
                    } else if (win->custom_update) {
                        win->custom_update(win, win->user_data);
                    }
                    wm_draw_all();
                    mouse_draw_cursor();
                    gfx_swap_buffers();
                    prev_left_btn = 1;
                    return;
                }

                // Check Minimize button
                if (mouse.x >= win->x + win->width - 66 && mouse.x <= win->x + win->width - 48) {
                    win->is_minimized = 1;
                    wm_draw_all();
                    doldoc_redraw();
                    mouse_draw_cursor();
                    gfx_swap_buffers();
                    prev_left_btn = 1;
                    return;
                }

                // Start Dragging Titlebar
                if (!win->is_maximized) {
                    is_dragging = 1;
                    drag_win_idx = win_idx;
                    drag_offset_x = mouse.x - win->x;
                    drag_offset_y = mouse.y - win->y;
                }
                prev_left_btn = 1;
                return;
            }

            // D. Check Click inside Window Client Area (Custom Click or DolDoc)
            if (!win->is_minimized) {
                if (win->custom_click) {
                    if (win->custom_click(win, mouse.x, mouse.y)) {
                        wm_dirty_flag = 1;
                        wm_draw_all();
                        mouse_draw_cursor();
                        gfx_swap_buffers();
                        prev_left_btn = 1;
                        return;
                    }
                } else if (win->id == 1) {
                    if (doldoc_handle_click(mouse.x, mouse.y)) {
                        wm_dirty_flag = 1;
                        wm_draw_all();
                        doldoc_redraw();
                        mouse_draw_cursor();
                        gfx_swap_buffers();
                        prev_left_btn = 1;
                        return;
                    }
                }
            }
        }
    }

    // 2. Mouse Dragging in Progress
    if (mouse.left_button && is_dragging && drag_win_idx >= 0 && drag_win_idx < window_count) {
        window_t *win = &window_list[drag_win_idx];
        int new_x = mouse.x - drag_offset_x;
        int new_y = mouse.y - drag_offset_y;

        if (new_x < -win->width + 50) new_x = -win->width + 50;
        if (new_x > (int)screen_width - 50) new_x = (int)screen_width - 50;
        if (new_y < 0) new_y = 0;
        if (new_y > (int)screen_height - (int)panel_h - 40) new_y = (int)screen_height - (int)panel_h - 40;

        if (win->x != new_x || win->y != new_y) {
            win->x = new_x;
            win->y = new_y;
            if (win->id == 1) {
                doldoc_move(win->x + 12, win->y + 40, win->width - 24, win->height - 48);
            } else if (win->custom_update) {
                win->custom_update(win, win->user_data);
            }
            wm_draw_all();
            mouse_draw_cursor();
            gfx_swap_buffers();
        }
    }

    // 2B. Mouse Edge Resizing in Progress
    if (mouse.left_button && is_resizing && resize_win_idx >= 0 && resize_win_idx < window_count) {
        window_t *win = &window_list[resize_win_idx];
        int new_w = mouse.x - win->x;
        int new_h = mouse.y - win->y;
        if (new_w < 260) new_w = 260;
        if (new_h < 160) new_h = 160;
        if (win->x + new_w > (int)screen_width) new_w = screen_width - win->x;
        if (win->y + new_h > (int)panel_y) new_h = panel_y - win->y;

        if (win->width != new_w || win->height != new_h) {
            win->width = new_w;
            win->height = new_h;
            if (win->id == 1) {
                doldoc_move(win->x + 12, win->y + 40, win->width - 24, win->height - 48);
            } else if (win->custom_update) {
                win->custom_update(win, win->user_data);
            }
            wm_draw_all();
            mouse_draw_cursor();
            gfx_swap_buffers();
        }
    }

    // 3. Mouse Button Released (Check Window Snapping)
    if (!mouse.left_button && prev_left_btn) {
        if (is_dragging && drag_win_idx >= 0 && drag_win_idx < window_count) {
            window_t *win = &window_list[drag_win_idx];
            uint32_t work_h = screen_height - panel_h;
            if (mouse.y <= 6) {
                // Snap Top: Maximize
                win->saved_x = win->x; win->saved_y = win->y;
                win->saved_w = win->width; win->saved_h = win->height;
                win->x = 0; win->y = 0;
                win->width = screen_width; win->height = work_h;
                win->is_maximized = 1;
                if (win->id == 1) doldoc_move(12, 40, win->width - 24, win->height - 48);
                else if (win->custom_update) win->custom_update(win, win->user_data);
                wm_draw_all(); mouse_draw_cursor(); gfx_swap_buffers();
            } else if (mouse.x <= 6) {
                // Snap Left: 50% split
                win->saved_x = win->x; win->saved_y = win->y;
                win->saved_w = win->width; win->saved_h = win->height;
                win->x = 0; win->y = 0;
                win->width = screen_width / 2; win->height = work_h;
                win->is_maximized = 0;
                if (win->id == 1) doldoc_move(12, 40, win->width - 24, win->height - 48);
                else if (win->custom_update) win->custom_update(win, win->user_data);
                wm_draw_all(); mouse_draw_cursor(); gfx_swap_buffers();
            } else if (mouse.x >= (int)screen_width - 6) {
                // Snap Right: 50% split
                win->saved_x = win->x; win->saved_y = win->y;
                win->saved_w = win->width; win->saved_h = win->height;
                win->x = screen_width / 2; win->y = 0;
                win->width = screen_width / 2; win->height = work_h;
                win->is_maximized = 0;
                if (win->id == 1) doldoc_move(win->x + 12, 40, win->width - 24, win->height - 48);
                else if (win->custom_update) win->custom_update(win, win->user_data);
                wm_draw_all(); mouse_draw_cursor(); gfx_swap_buffers();
            }
        }
        is_dragging = 0;
        drag_win_idx = -1;
        is_resizing = 0;
        resize_win_idx = -1;
    }

    prev_left_btn = mouse.left_button;
}
