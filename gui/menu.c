#include "menu.h"
#include "render.h"
#include "wm.h"
#include "../fs/redsea.h"
#include "../gui/shell.h"
#include "../kernel/bench/bench_unified.h"
#include "../kernel/sched/sched.h"
#include <uefi.h>

#define MAX_MENU_APPS 24

typedef struct {
    char name[32];
    char desc[48];
    char command[48];
    uint32_t tag_color;
    char category[20];
} menu_item_t;

static menu_item_t menu_items[MAX_MENU_APPS];
static int menu_item_count = 0;
static uint32_t g_menu_win_id = 0;

static void scan_apps(void) {
    menu_item_count = 0;

    // 1. Hardware & System Pipeline Toggles (System Controls, not files)
    strncpy(menu_items[menu_item_count].name, "CPU Render", 31);
    strncpy(menu_items[menu_item_count].desc, "Original UEFI SW Graphics", 47);
    strncpy(menu_items[menu_item_count].command, "render cpu", 47);
    menu_items[menu_item_count].tag_color = 0xFF27AE60;
    strncpy(menu_items[menu_item_count].category, "System Control", 19);
    menu_item_count++;

    strncpy(menu_items[menu_item_count].name, "GPU Render", 31);
    strncpy(menu_items[menu_item_count].desc, "VirtIO-GPU Hardware DMA", 47);
    strncpy(menu_items[menu_item_count].command, "render gpu", 47);
    menu_items[menu_item_count].tag_color = 0xFF8E44AD;
    strncpy(menu_items[menu_item_count].category, "System Control", 19);
    menu_item_count++;

    strncpy(menu_items[menu_item_count].name, "SMP Render", 31);
    strncpy(menu_items[menu_item_count].desc, "SMP Multi-Core Parallel", 47);
    strncpy(menu_items[menu_item_count].command, "render smp", 47);
    menu_items[menu_item_count].tag_color = 0xFF16A085;
    strncpy(menu_items[menu_item_count].category, "System Control", 19);
    menu_item_count++;

    // 2. 100% Dynamic RedSea Filesystem Reflection: Query ONLY files that actually exist
    redsea_entry_t entries[32];
    int count = redsea_get_entries(entries, 32);
    for (int i = 0; i < count && menu_item_count < MAX_MENU_APPS; i++) {
        if ((entries[i].attr & RS_ATTR_DIR) || !strstr(entries[i].name, ".HC")) {
            continue; // Skip directories and non-HolyC files
        }

        char *dot = strrchr(entries[i].name, '.');
        if (!dot || (strcmp(dot, ".HC") != 0 && strcmp(dot, ".hc") != 0)) {
            continue;
        }

        // Verify file actually exists and read first-line comment for description
        char fbuf[256];
        size_t rsize = 0;
        char desc[48] = "HolyC Application";
        if (redsea_read_file(entries[i].name, fbuf, sizeof(fbuf) - 1, &rsize) == 0 && rsize > 2) {
            fbuf[rsize] = '\0';
            if (fbuf[0] == '/' && fbuf[1] == '/') {
                char *end = strchr(fbuf, '\n');
                if (end) *end = '\0';
                char *txt = fbuf + 2;
                while (*txt == ' ' || *txt == '-') txt++;
                strncpy(desc, txt, 46);
                desc[46] = '\0';
            }
        }

        // Categorize based on verified application profile
        char category[20] = "HolyC Apps";
        uint32_t tag_col = COLOR_EMERALD_GREEN;

        if (strcmp(entries[i].name, "HolyBenchmark.HC") == 0) {
            strncpy(category, "Benchmarks", 19);
            tag_col = COLOR_GOLD_ACCENT;
            strncpy(desc, "HolyC Compute Benchmark", 46);
        } else if (strcmp(entries[i].name, "Bench.HC") == 0) {
            strncpy(category, "Benchmarks", 19);
            tag_col = COLOR_GOLD_ACCENT;
            strncpy(desc, "NeoBench Extreme 3D", 46);
        } else if (strcmp(entries[i].name, "HolyGLTest.HC") == 0) {
            strncpy(category, "3D & Graphics", 19);
            tag_col = COLOR_ACCENT_CYAN;
            strncpy(desc, "HolyGL OpenGL Demo", 46);
        } else if (strcmp(entries[i].name, "Filer.HC") == 0) {
            strncpy(category, "Files", 19);
            tag_col = COLOR_MAGENTA;
            strncpy(desc, "RedSea File Navigator", 46);
        } else if (strcmp(entries[i].name, "Editor.HC") == 0) {
            strncpy(category, "Development", 19);
            tag_col = COLOR_ACCENT_BLUE;
            strncpy(desc, "HolyC Source Editor", 46);
        } else if (strcmp(entries[i].name, "Top.HC") == 0) {
            strncpy(category, "System", 19);
            tag_col = 0xFF2ECC71;
            strncpy(desc, "SMP Task & CPU Top", 46);
        } else if (strcmp(entries[i].name, "StdLib.HC") == 0) {
            strncpy(category, "HolyC", 19);
            tag_col = COLOR_ACCENT_CYAN;
            strncpy(desc, "Dynamic Collections", 46);
        } else if (strcmp(entries[i].name, "Compositor.HC") == 0) {
            strncpy(category, "System Control", 19);
            tag_col = 0xFF9B59B6;
            strncpy(desc, "Compositor Effects Hub", 46);
        } else if (strcmp(entries[i].name, "GpuConfig.HC") == 0) {
            strncpy(category, "3D & Graphics", 19);
            tag_col = COLOR_ACCENT_CYAN;
            strncpy(desc, "GPU & Render Mode Hub", 46);
        } else if (strcmp(entries[i].name, "fact.HC") == 0) {
            strncpy(desc, "Recursive Factorial", 46);
        } else if (strcmp(entries[i].name, "calc.HC") == 0) {
            strncpy(desc, "Arithmetic Calculator", 46);
        }

        strncpy(menu_items[menu_item_count].name, entries[i].name, 31);
        strncpy(menu_items[menu_item_count].desc, desc, 47);
        snprintf(menu_items[menu_item_count].command, 47, "run %s", entries[i].name);
        menu_items[menu_item_count].tag_color = tag_col;
        strncpy(menu_items[menu_item_count].category, category, 19);
        menu_item_count++;
    }

    // 8. System Utilities
    if (menu_item_count < MAX_MENU_APPS) {
        strncpy(menu_items[menu_item_count].name, "Scheduler", 31);
        strncpy(menu_items[menu_item_count].desc, "Ring 0 Multitasking List", 47);
        strncpy(menu_items[menu_item_count].command, "tasks", 47);
        menu_items[menu_item_count].tag_color = 0xFF3DAEE9;
        strncpy(menu_items[menu_item_count].category, "System", 19);
        menu_item_count++;
    }
    if (menu_item_count < MAX_MENU_APPS) {
        strncpy(menu_items[menu_item_count].name, "Memory Info", 31);
        strncpy(menu_items[menu_item_count].desc, "Kernel Heap Allocator", 47);
        strncpy(menu_items[menu_item_count].command, "mem", 47);
        menu_items[menu_item_count].tag_color = COLOR_GOLD_ACCENT;
        strncpy(menu_items[menu_item_count].category, "System", 19);
        menu_item_count++;
    }
}

void menu_init(void) {
    g_menu_win_id = 0;
    scan_apps();
}

void menu_open(void) {
    if (g_menu_win_id) {
        window_t *w = wm_get_window_by_id(g_menu_win_id);
        if (w) {
            w->is_minimized = 0;
            w->is_active = 1;
            return;
        }
    }

    scan_apps();
    // Create dedicated NeoMenu window (600 x 440)
    window_t *win = wm_create_window("NeoMenu 2.0 - TempleOS HolyC Hub", 30, 20, 600, 440);
    if (win) {
        g_menu_win_id = win->id;
        win->custom_render = menu_render;
        win->custom_click = menu_handle_click;
        win->user_data = NULL;
    }
}

void menu_close(void) {
    if (g_menu_win_id) {
        wm_destroy_window(g_menu_win_id);
        g_menu_win_id = 0;
    }
}

void menu_toggle(void) {
    if (g_menu_win_id) {
        window_t *w = wm_get_window_by_id(g_menu_win_id);
        if (w) {
            menu_close();
            return;
        }
    }
    menu_open();
}

int menu_is_open(void) {
    return (g_menu_win_id != 0 && wm_get_window_by_id(g_menu_win_id) != NULL);
}

void menu_render(window_t *win, void *user_data) {
    (void)user_data;
    if (!win) return;

    int client_x = win->x + 2;
    int client_y = win->y + 36;
    int client_w = win->width - 4;
    int client_h = win->height - 38;

    // 1. Background
    gfx_draw_rect(client_x, client_y, client_w, client_h, 0xFF1B1E22);

    // 2. Header Banner
    int banner_y = client_y + 8;
    gfx_draw_rounded_rect(client_x + 10, banner_y, client_w - 20, 42, 6, 0xFF252A30);
    gfx_draw_rect(client_x + 10, banner_y + 40, client_w - 20, 2, COLOR_ACCENT_CYAN);
    gfx_draw_string(client_x + 22, banner_y + 6, "[*] NeoMenu 2.0 - TempleOS HolyC Application Hub", COLOR_TEXT_WHITE, 0);
    gfx_draw_string(client_x + 22, banner_y + 22, "SASOS Ring 0 | Zero main() | Dynamic JIT Execution | Contiguous RedSea", COLOR_ACCENT_CYAN, 0);

    // 3. Grid of Application Cards (2 Columns)
    int card_w = (client_w - 32) / 2;
    int card_h = 58;
    int start_y = client_y + 58;

    for (int i = 0; i < menu_item_count; i++) {
        int col = i % 2;
        int row = i / 2;
        int cx = client_x + 10 + col * (card_w + 12);
        int cy = start_y + row * (card_h + 8);

        if (cy + card_h > client_y + client_h - 26) break;

        // Card body
        gfx_draw_rounded_rect(cx, cy, card_w, card_h, 4, 0xFF24282F);
        // Accent edge tag
        gfx_draw_rect(cx, cy + 4, 4, card_h - 8, menu_items[i].tag_color);

        // App Name
        gfx_draw_string(cx + 12, cy + 8, menu_items[i].name, COLOR_TEXT_WHITE, 0);
        // Category pill
        gfx_draw_string(cx + 12, cy + 24, menu_items[i].desc, COLOR_TEXT_MUTED, 0);

        // Launch Button [ Exec ]
        int btn_w = 64;
        int btn_h = 26;
        int btn_x = cx + card_w - btn_w - 10;
        int btn_y = cy + (card_h - btn_h) / 2;
        gfx_draw_rounded_rect(btn_x, btn_y, btn_w, btn_h, 4, COLOR_ACCENT_CYAN);
        gfx_draw_string(btn_x + 12, btn_y + 6, "Exec", COLOR_TEXT_WHITE, 0);
    }

    // 4. Footer Help Line
    gfx_draw_string(client_x + 14, client_y + client_h - 22,
                    "Dica: Clique em 'Exec' ou digite 'run Nome.HC' no Terminal DolDoc.",
                    COLOR_TEXT_MUTED, 0);
}

int menu_handle_click(window_t *win, int mouse_x, int mouse_y) {
    if (!win) return 0;

    int client_x = win->x + 2;
    int client_y = win->y + 36;
    int client_w = win->width - 4;
    int client_h = win->height - 38;

    int card_w = (client_w - 32) / 2;
    int card_h = 58;
    int start_y = client_y + 58;

    for (int i = 0; i < menu_item_count; i++) {
        int col = i % 2;
        int row = i / 2;
        int cx = client_x + 10 + col * (card_w + 12);
        int cy = start_y + row * (card_h + 8);

        if (cy + card_h > client_y + client_h - 26) break;

        int btn_w = 64;
        int btn_h = 26;
        int btn_x = cx + card_w - btn_w - 10;
        int btn_y = cy + (card_h - btn_h) / 2;

        if (mouse_x >= btn_x && mouse_x < btn_x + btn_w &&
            mouse_y >= btn_y && mouse_y < btn_y + btn_h) {
            
            char cmd_copy[64];
            strncpy(cmd_copy, menu_items[i].command, sizeof(cmd_copy) - 1);
            cmd_copy[sizeof(cmd_copy) - 1] = '\0';
            doldoc_printf("\n$FG,YELLOW$[NEOMENU]$FG$ Launching $FG,CYAN$%s$FG$ (%s)...\n",
                          menu_items[i].name, cmd_copy);
            menu_close();
            if (strcmp(menu_items[i].name, "Bench.HC") == 0 || strcmp(menu_items[i].name, "Gears.HC") == 0) {
                bench_unified_start(BENCH_MODE_GEARS);
            } else if (strcmp(menu_items[i].name, "Dynamics.HC") == 0) {
                bench_unified_start(BENCH_MODE_DYNAMICS);
            } else if (strcmp(menu_items[i].name, "Top.HC") == 0) {
                top_print_doldoc();
            } else {
                shell_run_command(cmd_copy);
            }
            return 1;
        }
    }
    return 0;
}
