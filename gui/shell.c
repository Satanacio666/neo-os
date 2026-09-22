#include "shell.h"
#include "render.h"
#include "wm.h"
#include "menu.h"
#include "../compiler/jit_arm64.h"
#include "../drivers/input/keyboard.h"
#include "../kernel/mem/kheap.h"
#include "../kernel/sched/sched.h"
#include "../kernel/symbols/symbols.h"
#include "../fs/redsea.h"
#include "../kernel/arch/aarch64/smp.h"
#include "../kernel/bench/bench3d.h"
#include "../kernel/bench/bench_suite.h"
#include "../kernel/bench/glxgears.h"
#include "../drivers/input/mouse.h"
#include <uefi.h>

#define SHELL_MAX_LINE 256
static char cmd_buf[SHELL_MAX_LINE];
static int  cmd_len = 0;
static int  cursor_visible = 1;
static uint32_t cursor_ticks = 0;

static void print_prompt(void) {
    doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
}

void shell_init(void) {
    cmd_len = 0;
    cmd_buf[0] = '\0';
    cursor_visible = 1;
    cursor_ticks = 0;

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$ NeoOS DolDoc 2.0 / Native HolyC Interactive Shell (Ring 0)$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Architecture: ARMv8-A (AArch64) SASOS | Identity Paging 1:1\n");
    doldoc_print(" Actions: $BT,\"✦ NeoMenu\",LM=\"menu\"$ $BT,\"GLXGears\",LM=\"gears\"$ $BT,\"NeoBench\",LM=\"benchsuite\"$ $BT,\"3D Bench\",LM=\"bench3d\"$ $BT,\"Top\",LM=\"top\"$ $BT,\"Files\",LM=\"ls\"$ $BT,\"Help\",LM=\"help\"$\n");
    doldoc_print(" Code: $FG,YELLOW$menu$FG$, $FG,YELLOW$gears$FG$, $FG,YELLOW$gears_dual$FG$, $FG,YELLOW$benchsuite$FG$, $FG,YELLOW$top$FG$, $FG,YELLOW$run Gears.HC$FG$\n\n");

    print_prompt();
    doldoc_draw_cursor(1);
    gfx_swap_buffers();
}

static int is_whitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static const char* skip_leading_ws(const char *s) {
    while (*s && is_whitespace(*s)) s++;
    return s;
}

void shell_run_command(const char *raw_cmd) {
    const char *cmd = skip_leading_ws(raw_cmd);
    if (!*cmd) {
        print_prompt();
        return;
    }

    if (strcmp(cmd, "help") == 0) {
        doldoc_print("$FG,CYAN$--- NeoOS Interactive Shell Help ---$FG$\n");
        doldoc_print(" $FG,YELLOW$Application Hub:$FG$     menu, [✦ NeoMenu] button\n");
        doldoc_print(" $FG,YELLOW$GLXGears 3D:$FG$          gears, gears_wire, gears_dual, closegears\n");
        doldoc_print(" $FG,YELLOW$Zero-RAM Buffer:$FG$      zeroram (on, off, status)\n");
        doldoc_print(" $FG,YELLOW$JIT Engine:$FG$           jittest, arithmetic, loops, switch/case\n");
        doldoc_print(" $FG,YELLOW$Multi-Core Suites:$FG$    benchsuite, stopbench, bench3d, close3d\n");
        doldoc_print(" $FG,YELLOW$System Telemetry:$FG$     top, smp, tasks, mem, sym\n");
        doldoc_print(" $FG,YELLOW$Storage & RedSea:$FG$     ls, cd, mkdir, rm, cat, write, run\n");
        doldoc_print(" $FG,YELLOW$Arithmetic & HolyC:$FG$   10 + 4 * 8;, I64 x = 10; x * 2;\n");
        doldoc_print(" $FG,YELLOW$Control flow:$FG$         for, while, do..while, switch/case, ? :\n");
        doldoc_print(" $FG,YELLOW$Interactive Tags:$FG$     $BT,\"NeoMenu\",LM=\"menu\"$ $BT,\"ZeroRAM\",LM=\"zeroram on\"$ $BT,\"JITTest\",LM=\"jittest\"$ $BT,\"GLXGears\",LM=\"gears\"$\n");
        doldoc_print("$FG,CYAN$------------------------------------$FG$\n");
    } else if (strcmp(cmd, "menu") == 0) {
        menu_toggle();
        doldoc_print("$FG,CYAN$[NEOMENU]$FG$ Toggled NeoMenu application hub.\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "clear") == 0 || strcmp(cmd, "cls") == 0) {
        doldoc_clear();
    } else if (strcmp(cmd, "mem") == 0) {
        heap_stats_t stats;
        kheap_get_stats(&stats);
        doldoc_print("$FG,CYAN$--- KERNEL HEAP ALLOCATOR STATS ---$FG$\n");
        doldoc_printf(" Total Memory:     %llu MB (%llu bytes)\n",
                      (unsigned long long)(stats.total_memory / (1024 * 1024)),
                      (unsigned long long)stats.total_memory);
        doldoc_printf(" Allocated (Used): %llu KB (%llu bytes)\n",
                      (unsigned long long)(stats.used_memory / 1024),
                      (unsigned long long)stats.used_memory);
        doldoc_printf(" Free Space:       %llu MB (%llu bytes)\n",
                      (unsigned long long)(stats.free_memory / (1024 * 1024)),
                      (unsigned long long)stats.free_memory);
        doldoc_printf(" Live Allocations: %llu (Total frees: %llu)\n",
                      (unsigned long long)stats.allocation_count,
                      (unsigned long long)stats.free_count);
        uint64_t pct = (stats.total_memory > 0) ? ((stats.used_memory * 100) / stats.total_memory) : 0;
        doldoc_printf(" Heap Utilization: $PB,VAL=%llu,MAX=100$\n", (unsigned long long)pct);
        doldoc_print("$FG,CYAN$-----------------------------------$FG$\n");
    } else if (strcmp(cmd, "scroll up") == 0) {
        doldoc_scroll_up(10);
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "scroll down") == 0) {
        doldoc_scroll_down(10);
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "benchsuite") == 0 || strcmp(cmd, "bench") == 0) {
        bench3d_stop();
        bench_suite_start();
        doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Started NeoBench Extreme multi-cycle suite!\n");
        doldoc_print(" Testing 6 cycles across 1T, 3T SMP, Dual Window, and HW Accel...\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "stopbench") == 0) {
        bench_suite_stop();
        doldoc_print("$FG,YELLOW$[NEOBENCH]$FG$ NeoBench suite stopped. Focus returned to shell.\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "bench3d") == 0 || strcmp(cmd, "cube2") == 0) {
        bench_suite_stop();
        bench3d_start();
        doldoc_print("$FG,GREEN$[BENCH3D]$FG$ Launched 2 concurrent 3D viewports on Core 1 & Core 2!\n");
        doldoc_print(" Type $FG,YELLOW$close3d$FG$ to close benchmark windows.\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "close3d") == 0) {
        bench3d_stop();
        doldoc_print("$FG,YELLOW$[BENCH3D]$FG$ 3D viewports closed. Focus returned to shell.\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strncmp(cmd, "zeroram", 7) == 0) {
        const char *arg = cmd + 7;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "on") == 0 || strcmp(arg, "1") == 0) {
            gfx_set_zero_ram_mode(1);
        } else if (strcmp(arg, "off") == 0 || strcmp(arg, "0") == 0) {
            gfx_set_zero_ram_mode(0);
        }
        int is_zr = gfx_is_zero_ram_mode();
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        doldoc_print("$FG,WHITE$ NeoOS Zero-RAM Framebuffer Architecture (TempleOS SASOS)$FG$\n");
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        if (is_zr) {
            doldoc_print(" Mode:               $FG,GREEN$Zero-RAM Direct-to-VRAM (Active)$FG$\n");
            doldoc_print(" RAM Buffer:         $FG,YELLOW$0 MB allocated$FG$ ($FG,GREEN$3.14 MB RAM saved$FG$)\n");
            doldoc_print(" Memcpy Latency:     $FG,GREEN$0 ms (100%% Copy Overhead Eliminated)$FG$\n");
            doldoc_printf(" Hardware VRAM Base: 0x%p (GOP Linear Scanout)\n", gfx_get_frontbuffer());
        } else {
            doldoc_print(" Mode:               $FG,YELLOW$Double-Buffering (RAM Backbuffer)$FG$\n");
            doldoc_print(" RAM Buffer:         3.14 MB (Dedicated Pages)\n");
            doldoc_printf(" Hardware VRAM Base: 0x%p (GOP Linear Scanout)\n", gfx_get_frontbuffer());
            doldoc_print(" Type $FG,CYAN$zeroram on$FG$ to eliminate the 3.14 MB backbuffer!\n");
        }
        doldoc_print("$FG,CYAN$-------------------------------------------------------$FG$\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "jittest") == 0) {
        jit_run_self_tests();
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "gears") == 0 || strcmp(cmd, "glxgears") == 0) {
        bench3d_stop();
        bench_suite_stop();
        glxgears_start(0, 0, 0);
        doldoc_print("$FG,GREEN$[GLXGEARS]$FG$ Launched Authentic 3D GLXGears with Z-Buffer & Lighting!\n");
        doldoc_print(" Click and drag mouse inside window to rotate view. Type $FG,YELLOW$closegears$FG$ to dismiss.\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "gears_wire") == 0) {
        bench3d_stop();
        bench_suite_stop();
        glxgears_start(1, 0, 0);
        doldoc_print("$FG,CYAN$[GLXGEARS]$FG$ Launched GLXGears in Wireframe Mode!\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "gears_dual") == 0) {
        bench3d_stop();
        bench_suite_stop();
        glxgears_start(0, 1, 1);
        doldoc_print("$FG,MAGENTA$[GLXGEARS]$FG$ Launched Dual Concurrent GLXGears on SMP Cores 1 & 2!\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "closegears") == 0) {
        glxgears_stop();
        doldoc_print("$FG,YELLOW$[GLXGEARS]$FG$ GLXGears window closed. Focus returned to shell.\n");
        wm_draw_all();
        mouse_draw_cursor();
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "top") == 0) {
        top_print_doldoc();
    } else if (strcmp(cmd, "tasks") == 0) {
        sched_print_doldoc();
    } else if (strcmp(cmd, "sym") == 0) {
        symbols_print_doldoc();
    } else if (strcmp(cmd, "smp") == 0 || strcmp(cmd, "cpu") == 0) {
        smp_print_doldoc();
    } else if (strcmp(cmd, "pwd") == 0) {
        doldoc_printf("$FG,CYAN$%s$FG$\n", redsea_get_pwd());
    } else if (strncmp(cmd, "cd ", 3) == 0 || strcmp(cmd, "cd") == 0) {
        const char *dir = (cmd[2] == '\0') ? "/" : skip_leading_ws(cmd + 3);
        if (redsea_change_dir(dir) != 0) {
            doldoc_printf("$FG,RED$Directory not found: %s$FG$\n", dir);
        }
    } else if (strncmp(cmd, "mkdir ", 6) == 0) {
        const char *dir = skip_leading_ws(cmd + 6);
        if (redsea_mkdir(dir) == 0) {
            doldoc_printf("$FG,GREEN$Created directory: %s$FG$\n", dir);
        } else {
            doldoc_printf("$FG,RED$Failed to create directory: %s$FG$\n", dir);
        }
    } else if (strncmp(cmd, "rm ", 3) == 0 || strncmp(cmd, "del ", 4) == 0) {
        const char *fname = (cmd[0] == 'r') ? skip_leading_ws(cmd + 3) : skip_leading_ws(cmd + 4);
        if (redsea_delete_file(fname) == 0) {
            doldoc_printf("$FG,GREEN$Deleted: %s$FG$\n", fname);
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else if (strcmp(cmd, "ramdisk") == 0 || strcmp(cmd, "ramls") == 0) {
        ramdisk_list_dir();
    } else if (strncmp(cmd, "ramcat ", 7) == 0) {
        const char *fname = skip_leading_ws(cmd + 7);
        char fbuf[4096];
        size_t fsize = 0;
        if (ramdisk_read_file(fname, fbuf, sizeof(fbuf) - 1, &fsize) == 0) {
            fbuf[fsize] = '\0';
            doldoc_printf("$FG,YELLOW$--- RAMDISK %s (%llu bytes) ---$FG$\n", fname, (unsigned long long)fsize);
            doldoc_print(fbuf);
            doldoc_print("\n$FG,YELLOW$-------------------------$FG$\n");
        } else {
            doldoc_printf("$FG,RED$RAMDisk file not found: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "ramwrite ", 9) == 0) {
        const char *p = skip_leading_ws(cmd + 9);
        char fname[64];
        int fi = 0;
        while (*p && *p != ' ' && fi < (int)sizeof(fname) - 1) {
            fname[fi++] = *p++;
        }
        fname[fi] = '\0';
        p = skip_leading_ws(p);
        size_t dlen = strlen(p);
        if (ramdisk_write_file(fname, p, dlen) == 0) {
            doldoc_printf("$FG,GREEN$[RAMDISK]$FG$ Saved %s (%llu bytes) to RAMDisk.\n", fname, (unsigned long long)dlen);
        } else {
            doldoc_printf("$FG,RED$Failed to write %s to RAMDisk.\n$FG$", fname);
        }
    } else if (strcmp(cmd, "ls") == 0 || strcmp(cmd, "dir") == 0) {
        redsea_list_dir();
    } else if (strncmp(cmd, "cat ", 4) == 0 || strncmp(cmd, "type ", 5) == 0) {
        const char *fname = (cmd[0] == 'c') ? cmd + 4 : cmd + 5;
        fname = skip_leading_ws(fname);
        char fbuf[4096];
        size_t fsize = 0;
        if (redsea_read_file(fname, fbuf, sizeof(fbuf) - 1, &fsize) == 0) {
            fbuf[fsize] = '\0';
            doldoc_printf("$FG,CYAN$--- %s (%llu bytes) ---$FG$\n", fname, (unsigned long long)fsize);
            doldoc_print(fbuf);
            doldoc_print("\n$FG,CYAN$-------------------------$FG$\n");
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "run ", 4) == 0) {
        const char *fname = skip_leading_ws(cmd + 4);
        char fbuf[8192];
        size_t fsize = 0;
        if (redsea_read_file(fname, fbuf, sizeof(fbuf) - 1, &fsize) == 0) {
            fbuf[fsize] = '\0';
            doldoc_printf("$FG,GREEN$[RUN]$FG$ Compiling and executing %s (%llu bytes)...\n", fname, (unsigned long long)fsize);
            int64_t res = jit_compile_and_run(fbuf);
            doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", (long long)res, (unsigned long long)res);
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "write ", 6) == 0) {
        const char *p = skip_leading_ws(cmd + 6);
        char fname[64];
        int fi = 0;
        while (*p && *p != ' ' && fi < (int)sizeof(fname) - 1) {
            fname[fi++] = *p++;
        }
        fname[fi] = '\0';
        p = skip_leading_ws(p);
        size_t dlen = strlen(p);
        if (redsea_write_file(fname, p, dlen) == 0) {
            doldoc_printf("$FG,GREEN$[WRITE]$FG$ Saved %s (%llu bytes) to RedSea disk.\n", fname, (unsigned long long)dlen);
        } else {
            doldoc_printf("$FG,RED$Failed to write %s to disk.\n$FG$", fname);
        }
    } else if (strncmp(cmd, "mouse ", 6) == 0) {
        const char *p = skip_leading_ws(cmd + 6);
        int mx = atoi(p);
        while (*p && *p != ' ') p++;
        p = skip_leading_ws(p);
        int my = atoi(p);
        while (*p && *p != ' ') p++;
        p = skip_leading_ws(p);
        int btn = (*p) ? atoi(p) : 0;
        mouse_set_pos(mx, my);
        mouse_set_button(btn, 0);
        extern void wm_handle_mouse(mouse_state_t mouse);
        wm_handle_mouse(mouse_get_state());
        doldoc_printf("[MOUSE] Pos (%d, %d), button=%d\n", mx, my, btn);
    } else if (strcmp(cmd, "reboot") == 0) {
        doldoc_print("$FG,RED$Rebooting system via UEFI Runtime Services...$FG$\n");
        gfx_swap_buffers();
        if (RT && RT->ResetSystem) {
            RT->ResetSystem(EfiResetCold, EFI_SUCCESS, 0, NULL);
        }
    } else {
        // Execute C/HolyC source code through AArch64 JIT
        int is_func = (strstr(cmd, "{") != NULL && (strstr(cmd, "I64 ") != NULL || strstr(cmd, "U0 ") != NULL || strstr(cmd, "F64 ") != NULL || strstr(cmd, "int ") != NULL));
        int64_t val = jit_compile_and_run(cmd);
        if (!is_func) {
            doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", (long long)val, (unsigned long long)val);
        }
    }

    print_prompt();
}

void shell_poll(void) {
    while (keyboard_has_char()) {
        int c = keyboard_getchar();
        if (c == '\n') {
            doldoc_draw_cursor(0);
            doldoc_putc('\n');
            cmd_buf[cmd_len] = '\0';
            shell_run_command(cmd_buf);
            cmd_len = 0;
            cmd_buf[0] = '\0';
            cursor_visible = 1;
            doldoc_draw_cursor(1);
            wm_draw_all();
            mouse_draw_cursor();
            gfx_swap_buffers();
        } else if (c == KEY_BACKSPACE) {
            if (cmd_len > 0) {
                doldoc_draw_cursor(0);
                cmd_len--;
                cmd_buf[cmd_len] = '\0';
                doldoc_backspace();
                doldoc_draw_cursor(1);
                gfx_swap_buffers();
            }
        } else if (c == KEY_PAGE_UP) {
            doldoc_scroll_up(5);
            gfx_swap_buffers();
        } else if (c == KEY_PAGE_DOWN) {
            doldoc_scroll_down(5);
            gfx_swap_buffers();
        } else if (c >= 32 && c < 127) {
            if (cmd_len < SHELL_MAX_LINE - 1) {
                doldoc_draw_cursor(0);
                cmd_buf[cmd_len++] = (char)c;
                cmd_buf[cmd_len] = '\0';
                doldoc_putc((char)c);
                doldoc_draw_cursor(1);
                gfx_swap_buffers();
            }
        }
    }

    // Cursor Blink animation
    cursor_ticks++;
    if (cursor_ticks % 20 == 0) {
        cursor_visible = !cursor_visible;
        doldoc_draw_cursor(cursor_visible);
        gfx_swap_buffers();
    }
}
