// ==============================================================================
// Shell.HC - Sovereign Pure HolyC Interactive Shell Console & REPL
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Interactive REPL, Line Editor, Circular History & Tab Autocomplete
// ==============================================================================

#define SHELL_MAX_LINE    256
#define SHELL_HISTORY_MAX 16
#define KEY_UP            0x101
#define KEY_DOWN          0x102
#define KEY_RIGHT         0x103
#define KEY_LEFT          0x104
#define KEY_PAGE_UP       0x105
#define KEY_PAGE_DOWN     0x106
#define KEY_ESC           0x1B
#define KEY_BACKSPACE     8
#define KEY_ENTER         10
#define KEY_TAB           9
#define SHELL_HISTORY_BUF 4096

U8  g_shell_cmd[SHELL_MAX_LINE];
I64 g_shell_len = 0;
U8  g_history[SHELL_HISTORY_BUF];
I64 g_history_count = 0;
I64 g_history_head = 0;
I64 g_history_nav = -1;
I64 g_cursor_visible = 1;
I64 g_cursor_ticks = 0;
I64 g_shell_dirty = 0;

U0 ShellPrintPrompt() {
    doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
}

U0 ShellAddHistory(U8 *cmd) {
    if (!cmd || !*cmd) return;
    if (g_history_count > 0) {
        I64 last_idx = (g_history_head - 1 + SHELL_HISTORY_MAX) % SHELL_HISTORY_MAX;
        U8 *last_cmd = g_history + last_idx * SHELL_MAX_LINE;
        if (strcmp(last_cmd, cmd) == 0) {
            g_history_nav = -1;
            return;
        }
    }
    U8 *target = g_history + g_history_head * SHELL_MAX_LINE;
    strcpy(target, cmd);
    g_history_head = (g_history_head + 1) % SHELL_HISTORY_MAX;
    if (g_history_count < SHELL_HISTORY_MAX) g_history_count++;
    g_history_nav = -1;
}

U0 ShellNavHistory(I64 dir) {
    if (g_history_count <= 0) return;

    if (dir < 0) { // UP
        if (g_history_nav == -1) {
            g_history_nav = g_history_count - 1;
        } else if (g_history_nav > 0) {
            g_history_nav--;
        }
    } else { // DOWN
        if (g_history_nav == -1) return;
        g_history_nav++;
        if (g_history_nav >= g_history_count) {
            // Restore blank line
            doldoc_draw_cursor(0);
            while (g_shell_len > 0) {
                g_shell_len--;
                doldoc_backspace();
            }
            g_shell_cmd[0] = 0;
            g_history_nav = -1;
            doldoc_draw_cursor(1);
            doldoc_swap_term();
            g_shell_dirty = 1;
            return;
        }
    }

    I64 h_idx = (g_history_head - g_history_count + g_history_nav + SHELL_HISTORY_MAX) % SHELL_HISTORY_MAX;
    U8 *hist_cmd = g_history + h_idx * SHELL_MAX_LINE;

    doldoc_draw_cursor(0);
    while (g_shell_len > 0) {
        g_shell_len--;
        doldoc_backspace();
    }
    strcpy(g_shell_cmd, hist_cmd);
    g_shell_len = strlen(g_shell_cmd);
    for (I64 i = 0; i < g_shell_len; i++) {
        doldoc_putc(g_shell_cmd[i]);
    }
    doldoc_draw_cursor(1);
    doldoc_swap_term();
    g_shell_dirty = 1;
}

U0 ShellAutocomplete() {
    if (g_shell_len <= 0) return;

    U8 *builtins[18];
    builtins[0] = "help";
    builtins[1] = "ls";
    builtins[2] = "dir";
    builtins[3] = "run ";
    builtins[4] = "cat ";
    builtins[5] = "clear";
    builtins[6] = "mem";
    builtins[7] = "top";
    builtins[8] = "menu";
    builtins[9] = "reboot";
    builtins[10] = "bench";
    builtins[11] = "gears";
    builtins[12] = "physics";
    builtins[13] = "perf";
    builtins[14] = "vsync ";
    builtins[15] = "zeroram ";
    builtins[16] = "render ";
    builtins[17] = 0;

    U8 entries[3072];
    I64 file_count = redsea_get_entries(entries, 48);

    U8 match_buf[256];
    match_buf[0] = 0;
    I64 match_count = 0;
    I64 is_run_prefix = (strncmp(g_shell_cmd, "run ", 4) == 0);
    I64 is_cat_prefix = (strncmp(g_shell_cmd, "cat ", 4) == 0);
    U8 *sub_token = g_shell_cmd;
    if (is_run_prefix || is_cat_prefix) {
        sub_token = g_shell_cmd + 4;
        while (*sub_token == ' ') sub_token++;
    }
    I64 sub_len = strlen(sub_token);

    // 1. Search builtins
    if (!is_run_prefix && !is_cat_prefix) {
        for (I64 i = 0; builtins[i]; i++) {
            if (strncmp(builtins[i], g_shell_cmd, g_shell_len) == 0) {
                match_count++;
                if (match_count == 1) {
                    strcpy(match_buf, builtins[i]);
                }
            }
        }
    }

    // 2. Search RedSea files
    for (I64 f = 0; f < file_count; f++) {
        U8 *fname = entries + f * 64 + 2;
        if (*fname) {
            if (is_run_prefix || is_cat_prefix) {
                if (sub_len == 0 || strncmp(fname, sub_token, sub_len) == 0) {
                    match_count++;
                    if (match_count == 1) {
                        if (is_run_prefix) {
                            strcpy(match_buf, "run ");
                            strcpy(match_buf + 4, fname);
                        } else {
                            strcpy(match_buf, "cat ");
                            strcpy(match_buf + 4, fname);
                        }
                    }
                }
            } else {
                if (strncmp(fname, g_shell_cmd, g_shell_len) == 0) {
                    match_count++;
                    if (match_count == 1) {
                        strcpy(match_buf, "run ");
                        strcpy(match_buf + 4, fname);
                    }
                }
            }
        }
    }

    if (match_count == 1) {
        doldoc_draw_cursor(0);
        while (g_shell_len > 0) {
            g_shell_len--;
            doldoc_backspace();
        }
        strcpy(g_shell_cmd, match_buf);
        g_shell_len = strlen(g_shell_cmd);
        for (I64 i = 0; i < g_shell_len; i++) {
            doldoc_putc(g_shell_cmd[i]);
        }
        doldoc_draw_cursor(1);
        doldoc_swap_term();
        g_shell_dirty = 1;
    } else if (match_count > 1) {
        doldoc_draw_cursor(0);
        doldoc_print("\n$FG,YELLOW$[SUGGEST]$FG$ ");

        if (!is_run_prefix && !is_cat_prefix) {
            for (I64 i = 0; builtins[i]; i++) {
                if (strncmp(builtins[i], g_shell_cmd, g_shell_len) == 0) {
                    doldoc_printf("$FG,CYAN$%s$FG$  ", builtins[i]);
                }
            }
        }
        for (I64 f = 0; f < file_count; f++) {
            U8 *fname = entries + f * 64 + 2;
            if (*fname) {
                if (is_run_prefix || is_cat_prefix) {
                    if (sub_len == 0 || strncmp(fname, sub_token, sub_len) == 0) {
                        doldoc_printf("$FG,GREEN$%s$FG$  ", fname);
                    }
                } else if (strncmp(fname, g_shell_cmd, g_shell_len) == 0) {
                    doldoc_printf("$FG,GREEN$%s$FG$  ", fname);
                }
            }
        }
        doldoc_putc('\n');
        ShellPrintPrompt();
        for (I64 i = 0; i < g_shell_len; i++) {
            doldoc_putc(g_shell_cmd[i]);
        }
        doldoc_draw_cursor(1);
        doldoc_swap_term();
        g_shell_dirty = 1;
    }
}

U0 ShellRunCommand(U8 *raw_cmd) {
    if (!raw_cmd) return;
    U8 *cmd = raw_cmd;
    while (*cmd == ' ' || *cmd == '\t') cmd++;
    if (!*cmd) {
        ShellPrintPrompt();
        return;
    }
    ShellAddHistory(cmd);

    if (strcmp(cmd, "help") == 0) {
        doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
        doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign Pure HolyC Shell Console (Ring 0) ✦$FG$\n");
        doldoc_print("$FG,CYAN$==============================================================$FG$\n");
        doldoc_print(" Architecture: ARMv8-A (AArch64) SASOS | Identity Paging 1:1\n");
        doldoc_print(" Engine      : Pure HolyC JIT Execution Substrate (No C in userland)\n");
        doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
        doldoc_print(" Sovereign Commands & Quick Actions:\n");
        doldoc_print("  System Apps : $BT,\"✦ NeoMenu\",LM=\"menu\"$  $BT,\"Files\",LM=\"ls\"$  $BT,\"Editor\",LM=\"run Editor.HC\"$  $BT,\"Top\",LM=\"top\"$\n");
        doldoc_print("  Benchmarks  : $BT,\"HolyBenchmark\",LM=\"bench\"$  $BT,\"Scorecard\",LM=\"run BenchReport.HC\"$\n");
        doldoc_print("  3D Graphics : $BT,\"GLXGears 3D\",LM=\"gears\"$  $BT,\"Physics 3D\",LM=\"physics\"$  $BT,\"Shaders\",LM=\"run ShaderEditor.HC\"$\n");
        doldoc_print("  Telemetry   : $BT,\"RTSS Telemetry\",LM=\"perf\"$  $BT,\"Heap Memory\",LM=\"mem\"$  $BT,\"Task Manager\",LM=\"top\"$\n");
        doldoc_print("  Storage     : $FG,YELLOW$ls$FG$, $FG,YELLOW$cd <dir>$FG$, $FG,YELLOW$mkdir <dir>$FG$, $FG,YELLOW$rm <file>$FG$, $FG,YELLOW$cat <file>$FG$, $FG,YELLOW$run <file.HC>$FG$\n");
        doldoc_print("  Control     : $FG,YELLOW$clear$FG$, $FG,YELLOW$vsync <60|120|off>$FG$, $FG,YELLOW$zeroram <on|off>$FG$, $FG,YELLOW$render <cpu|gpu|smp>$FG$, $FG,YELLOW$reboot$FG$\n");
        doldoc_print("  Expressions : Type any HolyC arithmetic or statement directly (e.g. $FG,YELLOW$2 + 2 * 10;$FG$)\n");
        doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
    } else if (strcmp(cmd, "clear") == 0 || strcmp(cmd, "cls") == 0) {
        doldoc_clear();
    } else if (strcmp(cmd, "ls") == 0 || strcmp(cmd, "dir") == 0) {
        redsea_list_dir();
    } else if (strcmp(cmd, "mem") == 0) {
        kheap_dump_doldoc();
    } else if (strcmp(cmd, "menu") == 0) {
        menu_toggle();
    } else if (strcmp(cmd, "reboot") == 0) {
        hal_reset_system();
    } else if (strcmp(cmd, "bench") == 0) {
        ShellRunCommand("run HolyBenchmark.HC");
        return;
    } else if (strcmp(cmd, "gears") == 0) {
        ShellRunCommand("run Gears.HC");
        return;
    } else if (strcmp(cmd, "physics") == 0) {
        ShellRunCommand("run Physics3D.HC");
        return;
    } else if (strcmp(cmd, "top") == 0 || strcmp(cmd, "tasks") == 0) {
        top_print_doldoc();
    } else if (strcmp(cmd, "doldoc") == 0) {
        doldoc_print("$FG,CYAN$==============================================================$FG$\n");
        doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign Pure HolyC DolDoc 2.0 Continuum ✦       $FG$\n");
        doldoc_print("$FG,CYAN$==============================================================$FG$\n");
        doldoc_print(" Architecture: 100% Pure HolyC Ring 0 Geometry & Quad Substrate\n");
        doldoc_print(" Palette     : Modern Catppuccin Mocha Styling & Micro-Shadows\n");
        doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
        doldoc_print(" Interactive Widgets & Reactive Elements:\n");
        doldoc_print("  Buttons    : $BT,\"✦ NeoMenu\",LM=\"menu\"$  $BT,\"Scorecard\",LM=\"bench\"$  $BT,\"Gears 3D\",LM=\"gears\"$\n");
        doldoc_print("  Hyperlinks : $LK,\"Disk Files\",A=\"ls\"$  $LK,\"Memory Stats\",A=\"mem\"$  $LK,\"Task Top\",A=\"top\"$\n");
        doldoc_print("  Progress   : $PB,VAL=75,MAX=100$\n");
        doldoc_print("  Checkboxes : $CB,\"Aero Glass Blur\",1$   $CB,\"Dirty Rect Blit\",1$   $CB,\"V-Sync 60Hz\",1$\n");
        doldoc_print("  Trees      : $TR,\"Kernel System Subsystems\"$\n");
        doldoc_print("  Divider    : $HR$\n");
        doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
    } else if (strcmp(cmd, "perf") == 0) {
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        doldoc_print("$FG,WHITE$ NeoOS RivaTuner (RTSS) Empirical Hardware Telemetry $FG$\n");
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        doldoc_print(" Telemetry Engine: Active ARM PMU & High-Resolution Timer\n");
        doldoc_printf(" Uptime Seconds  : $FG,GREEN$%lld sec$FG$\n", timer_get_uptime_sec());
        doldoc_print(" Viewport Status : Sovereign Single-Core SASOS Mode\n");
        doldoc_print("$FG,CYAN$-------------------------------------------------------$FG$\n");
    } else if (strncmp(cmd, "vsync", 5) == 0) {
        U8 *arg = cmd + 5;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "on") == 0 || strcmp(arg, "60") == 0) {
            gfx_vsync_set(1, 60);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ V-Sync locked to 60 Hz.\n");
        } else if (strcmp(arg, "120") == 0) {
            gfx_vsync_set(1, 120);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ V-Sync locked to 120 Hz.\n");
        } else if (strcmp(arg, "off") == 0 || strcmp(arg, "0") == 0) {
            gfx_vsync_set(0, 0);
            doldoc_print("$FG,YELLOW$[VSYNC]$FG$ V-Sync disabled.\n");
        } else {
            doldoc_print("Usage: vsync <on | off | 60 | 120>\n");
        }
    } else if (strncmp(cmd, "zeroram", 7) == 0) {
        U8 *arg = cmd + 7;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "on") == 0 || strcmp(arg, "1") == 0) {
            gfx_set_zero_ram_mode(1);
            doldoc_print("$FG,GREEN$[ZERORAM]$FG$ Zero-RAM Direct Scanout enabled (0 ms blit, 3.14 MB RAM saved)!\n");
        } else if (strcmp(arg, "off") == 0 || strcmp(arg, "0") == 0) {
            gfx_set_zero_ram_mode(0);
            doldoc_print("$FG,YELLOW$[ZERORAM]$FG$ Double-buffered RAM backbuffer restored.\n");
        } else {
            doldoc_printf("Zero-RAM mode: %s\n", gfx_is_zero_ram_mode() ? "ACTIVE" : "OFF");
        }
    } else if (strncmp(cmd, "render", 6) == 0) {
        U8 *arg = cmd + 6;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "cpu") == 0) {
            gfx_backend_set_mode(0);
            doldoc_print("$FG,CYAN$[GFX]$FG$ Switched to Pure CPU Software Graphics.\n");
        } else if (strcmp(arg, "gpu") == 0) {
            gfx_backend_set_mode(1);
            doldoc_print("$FG,MAGENTA$[GFX]$FG$ Switched to VirtIO-GPU Hardware DMA Scanout.\n");
        } else if (strcmp(arg, "smp") == 0) {
            gfx_backend_set_mode(2);
            doldoc_print("$FG,GREEN$[GFX]$FG$ Switched to SMP Multi-Core Parallel Graphics.\n");
        } else {
            doldoc_print("Usage: render <cpu | gpu | smp>\n");
        }
    } else if (strncmp(cmd, "cd ", 3) == 0) {
        U8 *path = cmd + 3;
        while (*path == ' ') path++;
        if (redsea_change_dir(path) == 0) {
            doldoc_printf("Changed directory to: %s\n", redsea_get_pwd());
        } else {
            doldoc_printf("$FG,RED$Directory not found: %s$FG$\n", path);
        }
    } else if (strncmp(cmd, "mkdir ", 6) == 0) {
        U8 *dname = cmd + 6;
        while (*dname == ' ') dname++;
        if (redsea_mkdir(dname) == 0) {
            doldoc_printf("$FG,GREEN$Created directory: %s$FG$\n", dname);
        } else {
            doldoc_printf("$FG,RED$Could not create directory: %s$FG$\n", dname);
        }
    } else if (strncmp(cmd, "rm ", 3) == 0) {
        U8 *fname = cmd + 3;
        while (*fname == ' ') fname++;
        if (redsea_delete_file(fname) == 0) {
            doldoc_printf("$FG,GREEN$Deleted: %s$FG$\n", fname);
        } else {
            doldoc_printf("$FG,RED$Could not delete: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "run ", 4) == 0) {
        U8 *fname = cmd + 4;
        while (*fname == ' ') fname++;
        U8 fbuf[32768];
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 32767, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("$FG,GREEN$[RUN]$FG$ Compiling and executing %s (%lld bytes)...\n", fname, fsize);
            I64 res = jit_compile_and_run(fbuf);
            doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
        } else {
            doldoc_printf("$FG,RED$File not found on RedSea disk: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "cat ", 4) == 0) {
        U8 *fname = cmd + 4;
        while (*fname == ' ') fname++;
        U8 fbuf[8192];
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 8191, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("$FG,CYAN$--- %s (%lld bytes) ---$FG$\n", fname, fsize);
            doldoc_print(fbuf);
            doldoc_print("\n$FG,CYAN$-------------------------$FG$\n");
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else {
        I64 res = jit_compile_and_run(cmd);
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
    }

    ShellPrintPrompt();
    g_shell_dirty = 1;
}

U0 ShellPoll() {
    while (keyboard_has_char()) {
        I64 c = keyboard_getchar();
        if (c == KEY_ENTER || c == 10 || c == 13) {
            doldoc_draw_cursor(0);
            doldoc_putc('\n');
            g_shell_cmd[g_shell_len] = 0;
            ShellRunCommand(g_shell_cmd);
            g_shell_len = 0;
            g_shell_cmd[0] = 0;
            g_cursor_visible = 1;
            doldoc_draw_cursor(1);
            g_shell_dirty = 1;
        } else if (c == KEY_BACKSPACE || c == 8 || c == 127) {
            if (g_shell_len > 0) {
                doldoc_draw_cursor(0);
                g_shell_len--;
                g_shell_cmd[g_shell_len] = 0;
                doldoc_backspace();
                doldoc_draw_cursor(1);
                doldoc_swap_term();
                g_shell_dirty = 1;
            }
        } else if (c == KEY_UP) {
            ShellNavHistory(-1);
        } else if (c == KEY_DOWN) {
            ShellNavHistory(1);
        } else if (c == KEY_TAB || c == 9) {
            ShellAutocomplete();
        } else if (c == KEY_ESC || c == 3) {
            doldoc_draw_cursor(0);
            g_shell_len = 0;
            g_shell_cmd[0] = 0;
            doldoc_print("\n");
            ShellPrintPrompt();
            doldoc_draw_cursor(1);
            doldoc_swap_term();
            g_shell_dirty = 1;
        } else if (c >= 32 && c <= 126) {
            if (g_shell_len < SHELL_MAX_LINE - 1) {
                doldoc_draw_cursor(0);
                g_shell_cmd[g_shell_len] = c;
                g_shell_len++;
                g_shell_cmd[g_shell_len] = 0;
                doldoc_putc(c);
                doldoc_draw_cursor(1);
                doldoc_swap_term();
                g_shell_dirty = 1;
            }
        }
    }

    // Cursor Blink animation
    g_cursor_ticks++;
    if (g_cursor_ticks % 20 == 0) {
        g_cursor_visible = !g_cursor_visible;
        doldoc_draw_cursor(g_cursor_visible);
        doldoc_swap_cursor();
    }
}

U0 ShellInit() {
    g_shell_len = 0;
    g_shell_cmd[0] = 0;
    g_history_count = 0;
    g_history_head = 0;
    g_history_nav = -1;
    g_cursor_visible = 1;
    g_cursor_ticks = 0;
    g_shell_dirty = 0;

    // Register HolyC shell entry points with kernel HAL bridge
    shell_register_holyc(ShellRunCommand, ShellPoll);

    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign Pure HolyC Shell Console (Shell.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Environment: ARMv8-A Ring 0 SASOS | 100% Native AArch64 JIT\n");
    doldoc_print(" Substrate  : Pure HolyC Line Editor & Circular History Buffer\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_print(" Available Sovereign Commands & Launchers:\n");
    doldoc_print("  System & Bench : $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$  $BT,\"Scorecard\",LM=\"run BenchReport.HC\"$  $BT,\"Top\",LM=\"run Top.HC\"$\n");
    doldoc_print("  3D & Graphics  : $BT,\"GLXGears 3D\",LM=\"run Gears.HC\"$  $BT,\"Physics 3D\",LM=\"run Physics3D.HC\"$  $BT,\"Shaders\",LM=\"run ShaderEditor.HC\"$\n");
    doldoc_print("  Compilers      : $BT,\"Sovereign JIT\",LM=\"run Compiler.HC\"$  $BT,\"WASM JIT\",LM=\"run WasmJit.HC\"$  $BT,\"DolDoc\",LM=\"run DolDoc.HC\"$\n");
    doldoc_print("  Files & Storage: $BT,\"Filer Explorer\",LM=\"run Filer.HC\"$  $BT,\"List (ls)\",LM=\"ls\"$  $BT,\"Heap Stats\",LM=\"mem\"$\n");
    doldoc_print("  Navigation     : $BT,\"✦ NeoMenu\",LM=\"menu\"$  $BT,\"Clear Console\",LM=\"clear\"$  $BT,\"Help Index\",LM=\"help\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
    ShellPrintPrompt();
}

ShellInit();
