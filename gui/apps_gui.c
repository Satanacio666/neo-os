#include "apps_gui.h"
#include "render.h"
#include "../fs/redsea.h"
#include "../compiler/jit_arm64.h"
#include <uefi.h>

extern void shell_run_command(const char *cmd);

// =========================================================================
// 1. DEDICATED WINDOWED FILER (Filer.HC / explorer.exe)
// =========================================================================

static window_t *s_filer_win = NULL;
static int s_filer_active_disk = 0; // 0 = RedSea, 1 = RAMDisk

void filer_open(void) {
    if (s_filer_win) {
        s_filer_win->is_minimized = 0;
        s_filer_win->is_active = 1;
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        return;
    }

    s_filer_win = wm_create_window("DolDoc File Explorer (Ring 0 VFS)", 120, 50, 640, 430);
    if (s_filer_win) {
        s_filer_win->custom_render = filer_render;
        s_filer_win->custom_click = filer_click;
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
    }
}

void filer_close(void) {
    if (s_filer_win) {
        wm_destroy_window(s_filer_win->id);
        s_filer_win = NULL;
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
    }
}

int filer_is_open(void) {
    return (s_filer_win != NULL && !s_filer_win->is_minimized && !s_filer_win->marked_for_destruction);
}

void filer_render(window_t *win, void *user_data) {
    (void)user_data;
    if (!win) return;

    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;
    int ch = win->height - 38;

    // Window Client Background
    gfx_draw_rect(cx, cy, cw, ch, COLOR_WINDOW_BODY);

    // Toolbar Header (Navigation Breadcrumbs & Disks)
    gfx_draw_rect(cx, cy, cw, 34, 0xFF1C2025);
    gfx_draw_rect(cx, cy + 33, cw, 1, COLOR_ACCENT_CYAN);

    // Breadcrumb path
    char pbuf[64];
    snprintf(pbuf, sizeof(pbuf), "Location: %s%s", (s_filer_active_disk == 0) ? "RedSea:/" : "RAMDisk:/", redsea_get_pwd());
    gfx_draw_string(cx + 12, cy + 10, pbuf, COLOR_TEXT_WHITE, 0);

    // Drive selector tabs
    uint32_t col_rs = (s_filer_active_disk == 0) ? COLOR_ACCENT_CYAN : 0xFF2C3E50;
    uint32_t col_rd = (s_filer_active_disk == 1) ? COLOR_ACCENT_CYAN : 0xFF2C3E50;
    gfx_draw_rounded_rect(cx + cw - 260, cy + 5, 120, 24, 4, col_rs);
    gfx_draw_string(cx + cw - 250, cy + 9, "RedSea (32M)", COLOR_TEXT_WHITE, 0);

    gfx_draw_rounded_rect(cx + cw - 130, cy + 5, 120, 24, 4, col_rd);
    gfx_draw_string(cx + cw - 120, cy + 9, "RAMDisk (16M)", COLOR_TEXT_WHITE, 0);

    // Column Headers
    int th_y = cy + 40;
    gfx_draw_rect(cx + 8, th_y, cw - 16, 22, 0xFF14171A);
    gfx_draw_string(cx + 16, th_y + 4, "Name", COLOR_GOLD_ACCENT, 0);
    gfx_draw_string(cx + 180, th_y + 4, "Type", COLOR_GOLD_ACCENT, 0);
    gfx_draw_string(cx + 310, th_y + 4, "Size", COLOR_GOLD_ACCENT, 0);
    gfx_draw_string(cx + 420, th_y + 4, "Action Commands", COLOR_GOLD_ACCENT, 0);

    // Read entries from active filesystem
    redsea_entry_t entries[32];
    int count = redsea_get_entries(entries, 32);

    int row_y = th_y + 26;
    for (int i = 0; i < count && i < 11; i++) {
        uint32_t row_bg = (i % 2 == 0) ? 0xFF1E2228 : 0xFF23272F;
        gfx_draw_rect(cx + 8, row_y, cw - 16, 26, row_bg);

        // Icon & Name
        const char *ext = "";
        char *dot = strrchr(entries[i].name, '.');
        if (dot) ext = dot + 1;

        uint32_t name_col = COLOR_TEXT_WHITE;
        if (strcmp(ext, "HC") == 0 || strcmp(ext, "NC") == 0) name_col = 0xFF2ECC71;
        else if (strcmp(ext, "lua") == 0) name_col = 0xFF3498DB;
        else if (strcmp(ext, "TXT") == 0 || strcmp(ext, "LOG") == 0) name_col = 0xFFF1C40F;

        gfx_draw_string(cx + 16, row_y + 6, entries[i].name, name_col, 0);

        // Type
        const char *type_str = (entries[i].attr & RS_ATTR_DIR) ? "Directory" :
                               (strcmp(ext, "HC") == 0) ? "HolyC / NeoC" :
                               (strcmp(ext, "lua") == 0) ? "Lua Script" :
                               (strcmp(ext, "LOG") == 0) ? "Audit Log" : "Text Document";
        gfx_draw_string(cx + 180, row_y + 6, type_str, COLOR_TEXT_MUTED, 0);

        // Size
        char s_buf[24];
        if (entries[i].attr & RS_ATTR_DIR) {
            snprintf(s_buf, sizeof(s_buf), "<DIR>");
        } else {
            snprintf(s_buf, sizeof(s_buf), "%llu B", (unsigned long long)entries[i].size);
        }
        gfx_draw_string(cx + 310, row_y + 6, s_buf, COLOR_TEXT_MUTED, 0);

        // Action Buttons: [RUN] [EDIT]
        if (!(entries[i].attr & RS_ATTR_DIR)) {
            // Run button
            gfx_draw_rounded_rect(cx + 420, row_y + 3, 56, 20, 3, 0xFF27AE60);
            gfx_draw_string(cx + 432, row_y + 6, "RUN", COLOR_TEXT_WHITE, 0);

            // Edit button
            gfx_draw_rounded_rect(cx + 486, row_y + 3, 56, 20, 3, 0xFF2980B9);
            gfx_draw_string(cx + 498, row_y + 6, "EDIT", COLOR_TEXT_WHITE, 0);
        }

        row_y += 28;
    }

    // Status footer
    int foot_y = cy + ch - 26;
    gfx_draw_rect(cx, foot_y, cw, 26, 0xFF14171A);
    char fbuf[128];
    snprintf(fbuf, sizeof(fbuf), "Total: %d items | Contiguous RedSea Storage | Double-click or click [RUN] to execute", count);
    gfx_draw_string(cx + 12, foot_y + 6, fbuf, COLOR_TEXT_MUTED, 0);
}

int filer_click(window_t *win, int mouse_x, int mouse_y) {
    if (!win) return 0;
    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;

    // Check Drive selector tabs
    if (mouse_y >= cy + 5 && mouse_y <= cy + 29) {
        if (mouse_x >= cx + cw - 260 && mouse_x <= cx + cw - 140) {
            s_filer_active_disk = 0;
            wm_set_dirty();
            wm_draw_all();
            gfx_swap_buffers();
            return 1;
        } else if (mouse_x >= cx + cw - 130 && mouse_x <= cx + cw - 10) {
            s_filer_active_disk = 1;
            wm_set_dirty();
            wm_draw_all();
            gfx_swap_buffers();
            return 1;
        }
    }

    // Check row buttons
    int th_y = cy + 40;
    int row_y = th_y + 26;

    redsea_entry_t entries[32];
    int count = redsea_get_entries(entries, 32);

    for (int i = 0; i < count && i < 11; i++) {
        if (mouse_y >= row_y && mouse_y <= row_y + 26) {
            // Clicked RUN
            if (mouse_x >= cx + 420 && mouse_x <= cx + 476) {
                char cmd[64];
                snprintf(cmd, sizeof(cmd), "run %s", entries[i].name);
                shell_run_command(cmd);
                return 1;
            }
            // Clicked EDIT
            if (mouse_x >= cx + 486 && mouse_x <= cx + 542) {
                editor_open(entries[i].name);
                return 1;
            }
        }
        row_y += 28;
    }

    return 0;
}


// =========================================================================
// 2. DEDICATED WINDOWED CODE EDITOR (Editor.HC)
// =========================================================================

static window_t *s_editor_win = NULL;
static char s_editor_filename[64] = "fact.HC";
static char s_editor_buffer[8192] = "";

void editor_open(const char *filename) {
    if (filename && filename[0] != '\0') {
        strncpy(s_editor_filename, filename, sizeof(s_editor_filename) - 1);
        s_editor_filename[sizeof(s_editor_filename) - 1] = '\0';
    } else if (s_editor_filename[0] == '\0') {
        strcpy(s_editor_filename, "fact.HC");
    }

    // Load file from RedSea disk
    size_t fsize = 0;
    if (redsea_read_file(s_editor_filename, s_editor_buffer, sizeof(s_editor_buffer) - 1, &fsize) != 0) {
        snprintf(s_editor_buffer, sizeof(s_editor_buffer),
                 "// NeoOS NeoC Source: %s\n\nI64 Main() {\n    \"Hello from %s\\n\";\n    return 0;\n}\nMain();\n",
                 s_editor_filename, s_editor_filename);
    } else {
        s_editor_buffer[fsize] = '\0';
    }

    if (s_editor_win) {
        s_editor_win->is_minimized = 0;
        s_editor_win->is_active = 1;
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        return;
    }

    char wtitle[96];
    snprintf(wtitle, sizeof(wtitle), "NeoC DolDoc Code Editor - %s", s_editor_filename);
    s_editor_win = wm_create_window(wtitle, 180, 70, 640, 440);
    if (s_editor_win) {
        s_editor_win->custom_render = editor_render;
        s_editor_win->custom_click = editor_click;
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
    }
}

void editor_close(void) {
    if (s_editor_win) {
        wm_destroy_window(s_editor_win->id);
        s_editor_win = NULL;
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
    }
}

int editor_is_open(void) {
    return (s_editor_win != NULL && !s_editor_win->is_minimized && !s_editor_win->marked_for_destruction);
}

void editor_render(window_t *win, void *user_data) {
    (void)user_data;
    if (!win) return;

    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;
    int ch = win->height - 38;

    // Editor Canvas Background (Sublime / VSCode Monokai Dark)
    gfx_draw_rect(cx, cy, cw, ch, 0xFF181A1F);

    // Toolbar Header
    gfx_draw_rect(cx, cy, cw, 32, 0xFF21252B);
    gfx_draw_rect(cx, cy + 31, cw, 1, 0xFF3E4451);

    // Toolbar action buttons: [💾 Save] [▶ Run F5]
    gfx_draw_rounded_rect(cx + 8, cy + 4, 72, 24, 3, 0xFF27AE60);
    gfx_draw_string(cx + 16, cy + 8, "Save", COLOR_TEXT_WHITE, 0);

    gfx_draw_rounded_rect(cx + 88, cy + 4, 84, 24, 3, 0xFF2980B9);
    gfx_draw_string(cx + 96, cy + 8, "Run F5", COLOR_TEXT_WHITE, 0);

    // File info
    char infobuf[96];
    snprintf(infobuf, sizeof(infobuf), "Editing: %s | Length: %llu bytes | NeoC JIT Ready",
             s_editor_filename, (unsigned long long)strlen(s_editor_buffer));
    gfx_draw_string(cx + 185, cy + 8, infobuf, COLOR_TEXT_MUTED, 0);

    // Line numbers gutter & separator
    int gutter_w = 42;
    gfx_draw_rect(cx, cy + 32, gutter_w, ch - 54, 0xFF1E2227);
    gfx_draw_line(cx + gutter_w, cy + 32, cx + gutter_w, cy + ch - 22, 0xFF2C313C);

    // Render code lines
    int text_y = cy + 38;
    int line_num = 1;
    char line_buf[128];
    int line_idx = 0;

    for (int p = 0; s_editor_buffer[p] != '\0' && text_y < cy + ch - 40; p++) {
        char ch_c = s_editor_buffer[p];
        if (ch_c == '\n' || line_idx >= 120) {
            line_buf[line_idx] = '\0';

            // Draw line number
            char lnum_str[8];
            snprintf(lnum_str, sizeof(lnum_str), "%02d", line_num);
            gfx_draw_string(cx + 10, text_y, lnum_str, 0xFF5C6370, 0);

            // Syntax coloring hint
            uint32_t line_col = COLOR_TEXT_WHITE;
            if (line_buf[0] == '/' && line_buf[1] == '/') line_col = 0xFF5C6370; // Comments
            else if (strstr(line_buf, "I64") || strstr(line_buf, "U0") || strstr(line_buf, "class")) line_col = COLOR_GOLD_ACCENT;
            else if (strstr(line_buf, "return") || strstr(line_buf, "if")) line_col = 0xFFE06C75;

            gfx_draw_string(cx + gutter_w + 10, text_y, line_buf, line_col, 0);

            text_y += 18;
            line_num++;
            line_idx = 0;
        } else {
            line_buf[line_idx++] = ch_c;
        }
    }
    if (line_idx > 0 && text_y < cy + ch - 40) {
        line_buf[line_idx] = '\0';
        char lnum_str[8];
        snprintf(lnum_str, sizeof(lnum_str), "%02d", line_num);
        gfx_draw_string(cx + 10, text_y, lnum_str, 0xFF5C6370, 0);
        gfx_draw_string(cx + gutter_w + 10, text_y, line_buf, COLOR_TEXT_WHITE, 0);
    }

    // Status Footer
    int stat_y = cy + ch - 22;
    gfx_draw_rect(cx, stat_y, cw, 22, 0xFF21252B);
    gfx_draw_string(cx + 12, stat_y + 4, "Press [Run F5] to JIT-compile and execute directly in Ring 0.", COLOR_ACCENT_CYAN, 0);
}

int editor_click(window_t *win, int mouse_x, int mouse_y) {
    if (!win) return 0;
    int cx = win->x + 2;
    int cy = win->y + 36;

    // Check [Save] button
    if (mouse_x >= cx + 8 && mouse_x <= cx + 80 && mouse_y >= cy + 4 && mouse_y <= cy + 28) {
        redsea_write_file(s_editor_filename, s_editor_buffer, strlen(s_editor_buffer));
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        return 1;
    }

    // Check [Run F5] button
    if (mouse_x >= cx + 88 && mouse_x <= cx + 172 && mouse_y >= cy + 4 && mouse_y <= cy + 28) {
        jit_compile_and_run(s_editor_buffer);
        return 1;
    }

    return 0;
}
