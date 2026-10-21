// ==============================================================================
// Shell.HC - Sovereign Pure HolyC Interactive Shell Console, Disassembler & REPL
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Dynamic Command Registry, AArch64 Disassembler (uf), Syntax Source
//            Inspector (src), Theme/Shader/Window Control & Direct HolyC JIT REPL
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

// Dynamic Command Registry Table
class CShellCmdEntry {
    U8  name[24];
    U8  help[56];
    U64 fn_addr;
};

CShellCmdEntry g_shell_cmds[32];
I64 g_shell_cmd_count = 0;

U8  g_shell_cmd[SHELL_MAX_LINE];
I64 g_shell_len = 0;
U8  g_history[SHELL_HISTORY_BUF];
I64 g_history_count = 0;
I64 g_history_head = 0;
I64 g_history_nav = -1;
I64 g_cursor_visible = 1;
I64 g_cursor_ticks = 0;
I64 g_shell_dirty = 0;

U0 shell_register_cmd(U8 *name, U64 fn_addr, U8 *help_str) {
    if (!name || g_shell_cmd_count >= 32) return;
    for (I64 sr_i = 0; sr_i < g_shell_cmd_count; sr_i++) {
        CShellCmdEntry *sc = &g_shell_cmds[sr_i];
        if (strcmp(sc->name, name) == 0) {
            sc->fn_addr = fn_addr;
            if (help_str) strncpy(sc->help, help_str, 55);
            return;
        }
    }
    I64 idx = g_shell_cmd_count++;
    CShellCmdEntry *sc_new = &g_shell_cmds[idx];
    strncpy(sc_new->name, name, 23);
    sc_new->name[23] = 0;
    if (help_str) {
        strncpy(sc_new->help, help_str, 55);
        sc_new->help[55] = 0;
    } else {
        sc_new->help[0] = 0;
    }
    sc_new->fn_addr = fn_addr;
}

U0 ShellPrintPrompt() {
    doldoc_printf("$FG,MAUVE$neo$FG,SAPPHIRE$:%s$FG,GREEN$> $FG,TEXT$", redsea_get_pwd());
}

U0 ShellRecover() {
    doldoc_printf("\n$FG,RED$[TRAP] Sovereign Fault Recovered back to Shell$FG$\n");
    g_shell_len = 0;
    g_shell_cmd[0] = 0;
    ShellPrintPrompt();
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

    if (dir < 0) {
        if (g_history_nav == -1) {
            g_history_nav = g_history_count - 1;
        } else if (g_history_nav > 0) {
            g_history_nav--;
        }
    } else {
        if (g_history_nav == -1) return;
        g_history_nav++;
        if (g_history_nav >= g_history_count) {
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
    for (I64 nh_i = 0; nh_i < g_shell_len; nh_i++) {
        doldoc_putc(g_shell_cmd[nh_i]);
    }
    doldoc_draw_cursor(1);
    doldoc_swap_term();
    g_shell_dirty = 1;
}

U0 ShellAutocomplete() {
    if (g_shell_len <= 0) return;

    U8 *builtins[30];
    builtins[0]  = "help";
    builtins[1]  = "ls";
    builtins[2]  = "dir";
    builtins[3]  = "run ";
    builtins[4]  = "cat ";
    builtins[5]  = "clear";
    builtins[6]  = "mem";
    builtins[7]  = "top";
    builtins[8]  = "menu";
    builtins[9]  = "reboot";
    builtins[10] = "bench";
    builtins[11] = "gears";
    builtins[12] = "physics";
    builtins[13] = "holygl";
    builtins[14] = "showcase";
    builtins[15] = "shader";
    builtins[16] = "theme ";
    builtins[17] = "wm";
    builtins[18] = "filer";
    builtins[19] = "edit";
    builtins[20] = "smp";
    builtins[21] = "perf";
    builtins[22] = "uf ";
    builtins[23] = "src ";
    builtins[24] = "newwin";
    builtins[25] = "inspect";
    builtins[26] = "vsync ";
    builtins[27] = "zeroram ";
    builtins[28] = "save ";
    builtins[29] = 0;

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

    if (!is_run_prefix && !is_cat_prefix) {
        for (I64 ac_i = 0; builtins[ac_i]; ac_i++) {
            if (strncmp(builtins[ac_i], g_shell_cmd, g_shell_len) == 0) {
                match_count++;
                if (match_count == 1) {
                    strcpy(match_buf, builtins[ac_i]);
                }
            }
        }
    }

    for (I64 f_i = 0; f_i < file_count; f_i++) {
        U8 *fname = entries + f_i * 64 + 2;
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
        for (I64 m_i = 0; m_i < g_shell_len; m_i++) {
            doldoc_putc(g_shell_cmd[m_i]);
        }
        doldoc_draw_cursor(1);
        doldoc_swap_term();
        g_shell_dirty = 1;
    } else if (match_count > 1) {
        doldoc_draw_cursor(0);
        doldoc_print("\n$FG,YELLOW$[SUGGEST]$FG$ ");

        if (!is_run_prefix && !is_cat_prefix) {
            for (I64 s_i = 0; builtins[s_i]; s_i++) {
                if (strncmp(builtins[s_i], g_shell_cmd, g_shell_len) == 0) {
                    doldoc_printf("$FG,CYAN$%s$FG$  ", builtins[s_i]);
                }
            }
        }
        for (I64 sf_i = 0; sf_i < file_count; sf_i++) {
            U8 *fname2 = entries + sf_i * 64 + 2;
            if (*fname2) {
                if (is_run_prefix || is_cat_prefix) {
                    if (sub_len == 0 || strncmp(fname2, sub_token, sub_len) == 0) {
                        doldoc_printf("$FG,GREEN$%s$FG$  ", fname2);
                    }
                } else if (strncmp(fname2, g_shell_cmd, g_shell_len) == 0) {
                    doldoc_printf("$FG,GREEN$%s$FG$  ", fname2);
                }
            }
        }
        doldoc_putc('\n');
        ShellPrintPrompt();
        for (I64 rp_i = 0; rp_i < g_shell_len; rp_i++) {
            doldoc_putc(g_shell_cmd[rp_i]);
        }
        doldoc_draw_cursor(1);
        doldoc_swap_term();
        g_shell_dirty = 1;
    }
}

// ==============================================================================
// Native AArch64 Disassembler (TempleOS Uf() Parity)
// ==============================================================================
U0 DisasmFunction(U8 *fn_name) {
    if (!fn_name || !*fn_name) {
        doldoc_print("Usage: uf <function_name>\n");
        return;
    }
    U64 addr = symbols_lookup(fn_name);
    if (addr == 0) {
        doldoc_printf("$FG,RED$[DISASM ERR]$FG$ Symbol '%s' not found in kernel symbol table!\n", fn_name);
        return;
    }
    U32 *code = addr;
    doldoc_printf("\n$CARD,title=\"AArch64 Native Disassembly: %s (RAM: 0x%016llX)\",w=108,h=2$\n", fn_name, addr);
    doldoc_print("$HR$\n");

    for (I64 d_i = 0; d_i < 44; d_i++) {
        U32 ins = code[d_i];
        U64 ins_addr = addr + d_i * 4;
        doldoc_printf("  $FG,CYAN$0x%08llX$FG$  $FG,YELLOW$%08X$FG$  ", ins_addr, ins);

        if (ins == 0xD65F03C0) {
            doldoc_print("$FG,RED$RET$FG$\n");
            doldoc_print("$HR$\n");
            doldoc_printf("  Function size: $FG,GREEN$%lld bytes$FG$ ($FG,YELLOW$%lld instructions$FG$)\n$HR$\n\n", (d_i + 1) * 4, d_i + 1);
            return;
        } else if (ins == 0xD503201F) {
            doldoc_print("$FG,MUTED$NOP$FG$\n");
        } else if (ins == 0xA9BF7BFD) {
            doldoc_print("$FG,MAUVE$STP$FG$     X29, X30, [SP, #-16]!\n");
        } else if (ins == 0xA8C17BFD) {
            doldoc_print("$FG,MAUVE$LDP$FG$     X29, X30, [SP], #16\n");
        } else if (ins == 0x910003FD) {
            doldoc_print("$FG,GREEN$MOV$FG$     X29, SP\n");
        } else if (ins == 0x910003BF) {
            doldoc_print("$FG,GREEN$MOV$FG$     SP, X29\n");
        } else if ((ins & 0xFFC003E0) == 0xAA0003E0) {
            I64 rd = ins & 0x1F;
            I64 rm = (ins >> 16) & 0x1F;
            doldoc_printf("$FG,GREEN$MOV$FG$     X%lld, X%lld\n", rd, rm);
        } else if ((ins & 0xFF800000) == 0xD2800000) {
            I64 rd = ins & 0x1F;
            I64 imm16 = (ins >> 5) & 0xFFFF;
            I64 hw = (ins >> 21) & 3;
            if (hw == 0) doldoc_printf("$FG,GREEN$MOVZ$FG$    X%lld, #0x%llX\n", rd, imm16);
            else doldoc_printf("$FG,GREEN$MOVZ$FG$    X%lld, #0x%llX, LSL #%lld\n", rd, imm16, hw * 16);
        } else if ((ins & 0xFF800000) == 0xF2800000) {
            I64 rd = ins & 0x1F;
            I64 imm16 = (ins >> 5) & 0xFFFF;
            I64 hw = (ins >> 21) & 3;
            doldoc_printf("$FG,GREEN$MOVK$FG$    X%lld, #0x%llX, LSL #%lld\n", rd, imm16, hw * 16);
        } else if ((ins & 0xFF000000) == 0x91000000) {
            I64 rd = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 imm12 = (ins >> 10) & 0xFFF;
            doldoc_printf("$FG,GREEN$ADD$FG$     X%lld, X%lld, #%lld\n", rd, rn, imm12);
        } else if ((ins & 0xFF000000) == 0xD1000000) {
            I64 rd = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 imm12 = (ins >> 10) & 0xFFF;
            doldoc_printf("$FG,GREEN$SUB$FG$     X%lld, X%lld, #%lld\n", rd, rn, imm12);
        } else if ((ins & 0xFF200000) == 0x8B000000) {
            I64 rd = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 rm = (ins >> 16) & 0x1F;
            doldoc_printf("$FG,GREEN$ADD$FG$     X%lld, X%lld, X%lld\n", rd, rn, rm);
        } else if ((ins & 0xFF200000) == 0xCB000000) {
            I64 rd = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 rm = (ins >> 16) & 0x1F;
            doldoc_printf("$FG,GREEN$SUB$FG$     X%lld, X%lld, X%lld\n", rd, rn, rm);
        } else if ((ins & 0xFFE0FC00) == 0x9B007C00) {
            I64 rd = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 rm = (ins >> 16) & 0x1F;
            doldoc_printf("$FG,GREEN$MUL$FG$     X%lld, X%lld, X%lld\n", rd, rn, rm);
        } else if ((ins & 0xFFC00000) == 0xF9400000) {
            I64 rt = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 imm12 = ((ins >> 10) & 0xFFF) * 8;
            doldoc_printf("$FG,SKY$LDR$FG$     X%lld, [X%lld, #%lld]\n", rt, rn, imm12);
        } else if ((ins & 0xFFC00000) == 0xF9000000) {
            I64 rt = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            I64 imm12 = ((ins >> 10) & 0xFFF) * 8;
            doldoc_printf("$FG,SKY$STR$FG$     X%lld, [X%lld, #%lld]\n", rt, rn, imm12);
        } else if ((ins & 0xFFFFFC00) == 0x1E61C000) {
            I64 rd = ins & 0x1F;
            I64 rn = (ins >> 5) & 0x1F;
            doldoc_printf("$FG,TEAL$FSQRT$FG$   D%lld, D%lld\n", rd, rn);
        } else if ((ins & 0xFF000000) == 0xB4000000) {
            I64 rt = ins & 0x1F;
            I64 imm19 = (ins >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= ~0x7FFFF;
            doldoc_printf("$FG,PEACH$CBZ$FG$     X%lld, 0x%llX\n", rt, ins_addr + imm19 * 4);
        } else if ((ins & 0xFF000000) == 0xB5000000) {
            I64 rt = ins & 0x1F;
            I64 imm19 = (ins >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= ~0x7FFFF;
            doldoc_printf("$FG,PEACH$CBNZ$FG$    X%lld, 0x%llX\n", rt, ins_addr + imm19 * 4);
        } else if ((ins & 0xFFFFFC1F) == 0xD63F0000) {
            I64 rn = (ins >> 5) & 0x1F;
            doldoc_printf("$FG,PEACH$BLR$FG$     X%lld\n", rn);
        } else if ((ins & 0xFC000000) == 0x94000000) {
            I64 imm26 = ins & 0x03FFFFFF;
            if (imm26 & 0x02000000) imm26 |= ~0x03FFFFFF;
            U64 target = ins_addr + imm26 * 4;
            doldoc_printf("$FG,PEACH$BL$FG$      0x%llX\n", target);
        } else if ((ins & 0xFC000000) == 0x14000000) {
            I64 imm26 = ins & 0x03FFFFFF;
            if (imm26 & 0x02000000) imm26 |= ~0x03FFFFFF;
            U64 target = ins_addr + imm26 * 4;
            doldoc_printf("$FG,PEACH$B$FG$       0x%llX\n", target);
        } else {
            doldoc_printf("$FG,MUTED$.word 0x%08X$FG$\n", ins);
        }
    }
    doldoc_print("$HR$\n\n");
}

U0 ShellInspectSource(U8 *target) {
    if (!target || !*target) {
        doldoc_print("Usage: src <filename.HC>\n");
        return;
    }
    U8 fname[64];
    strcpy(fname, target);
    I64 len = strlen(fname);
    if (len < 3 || strcmp(fname + len - 3, ".HC") != 0) {
        if (len < 59) {
            strcat(fname, ".HC");
        }
    }
    U8 *src_buf = kmalloc(131072);
    I64 fsize = 0;
    if (redsea_read_file(fname, src_buf, 131071, &fsize) == 0) {
        src_buf[fsize] = 0;
        doldoc_printf("\n$CARD,title=\"HolyC Source Inspector: %s (%lld bytes)\",w=108,h=2$\n", fname, fsize);
        doldoc_print("$HR$\n");
        I64 line_no = 1;
        doldoc_printf("$FG,MUTED$%3lld | $FG$", line_no);
        I64 col = 0;
        for (I64 si = 0; si < fsize; si++) {
            U8 ch = src_buf[si];
            if (ch == 10) {
                doldoc_putc(10);
                col = 0;
                line_no++;
                if (line_no > 38) {
                    doldoc_printf("$FG,YELLOW$  ... [Showing first 38 lines of %lld bytes. Use 'edit' or PageUp/PageDown] ...$FG$\n", fsize);
                    break;
                }
                doldoc_printf("$FG,MUTED$%3lld | $FG$", line_no);
            } else if (ch >= 32 && ch <= 126) {
                if (col < 104) {
                    if (ch == '$') {
                        doldoc_putc('$');
                        doldoc_putc('$');
                    } else {
                        doldoc_putc(ch);
                    }
                    col++;
                }
            } else if (ch == 9) {
                doldoc_print("    ");
                col += 4;
            }
        }
        doldoc_putc(10);
        doldoc_print("$HR$\n\n");
    } else {
        doldoc_printf("$FG,RED$[SRC ERR]$FG$ File '%s' not found on RedSea disk!\n", fname);
    }
    kfree(src_buf);
}

U0 ShellPrintBootBanner() {
    I64 sw = gfx_get_canvas_width();
    I64 sh = gfx_get_canvas_height();
    I64 cw = (sw - 32) / 8;
    if (cw < 72) cw = 72;

    doldoc_printf("\n$CARD,title=\"NeoOS 3.0 Sovereign Continuum (ARM64 Ring-0)\",w=%lld,h=11$\n", cw);
    doldoc_print("  $FONT,text=\"NEO-OS 3.0 PURE HOLYC RING-0\",scale=130,color=\"CYAN\"$\n\n");
    doldoc_printf("  $FG,SAPPHIRE$Substrate:$FG$ 100%% Native AArch64 JIT | $FG,SAPPHIRE$Skin:$FG$ $FG,YELLOW$%s$FG$ | $FG,SAPPHIRE$Storage:$FG$ RedSea 64-bit FS\n", g_theme.name);
    doldoc_print("  $FG,SAPPHIRE$Continuum:$FG$ Unified Scene-Graph, OmniTape Stream, Morton 64x64 Tiles & Native Shadertoy ($$SHADER$$)\n\n");
    doldoc_print("  $FG,YELLOW$Flagship & Desktop:$FG$ $BT,\"Shadertoy IDE\",LM=\"shader\"$  $BT,\"Desktop WM\",LM=\"wm\"$  $BT,\"GLXGears 3D\",LM=\"gears\"$  $BT,\"HolyBenchmark\",LM=\"bench\"$\n");
    doldoc_print("  $FG,YELLOW$Semantic Themes   :$FG$ $BT,\"Mocha\",LM=\"theme mocha\"$  $BT,\"Latte\",LM=\"theme latte\"$  $BT,\"Tokyo\",LM=\"theme tokyo\"$  $BT,\"Nord\",LM=\"theme nord\"$  $BT,\"TempleOS\",LM=\"theme temple\"$  $BT,\"Cyberpunk\",LM=\"theme cyberpunk\"$\n");
    doldoc_print("  $FG,YELLOW$Compiler & Tools  :$FG$ $BT,\"Disasm (uf)\",LM=\"uf DolDocRedraw\"$  $BT,\"Inspect Src\",LM=\"src DolDoc.HC\"$  $BT,\"Compiler.HC\",LM=\"run Compiler.HC\"$  $BT,\"Files (ls)\",LM=\"ls\"$  $BT,\"Memory\",LM=\"mem\"$\n\n\n");
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
        doldoc_print("\n$CARD,title=\"NeoOS Sovereign Pure HolyC Shell Console & Command Reference\",w=110,h=8$\n");
        doldoc_print("  $FG,YELLOW$Flagship & UI :$FG$ $FG,CYAN$shader [0..3]$FG$ (Shadertoy IDE), $FG,CYAN$wm$FG$ (Desktop), $FG,CYAN$newwin$FG$, $FG,CYAN$inspect$FG$ (Morphic Halos)\n");
        doldoc_print("  $FG,YELLOW$Themes & Skins:$FG$ $FG,CYAN$theme <mocha|latte|tokyo|nord|temple|cyberpunk>$FG$, $FG,CYAN$compositor$FG$\n");
        doldoc_print("  $FG,YELLOW$Compiler/Debug:$FG$ $FG,CYAN$uf <symbol>$FG$ (ARM64 Disasm), $FG,CYAN$src <file.HC>$FG$, $FG,CYAN$run Compiler.HC$FG$, $FG,CYAN$run TestJitP0.HC$FG$\n");
        doldoc_print("  $FG,YELLOW$3D & Bench    :$FG$ $FG,CYAN$bench$FG$, $FG,CYAN$gears$FG$, $FG,CYAN$physics$FG$, $FG,CYAN$holygl$FG$, $FG,CYAN$perf$FG$, $FG,CYAN$mem$FG$\n");
        doldoc_print("  $FG,YELLOW$RedSea Disk   :$FG$ $FG,CYAN$ls$FG$, $FG,CYAN$cd <dir>$FG$, $FG,CYAN$mkdir <dir>$FG$, $FG,CYAN$rm <file>$FG$, $FG,CYAN$cat <file>$FG$, $FG,CYAN$save <file> <text>$FG$\n");
        doldoc_print("  $FG,YELLOW$Live HolyC JIT:$FG$ Type any HolyC expression or function directly at the prompt (e.g. $FG,GREEN$2 + 2 * 10;$FG$)\n\n\n");
    } else if (strcmp(cmd, "clear") == 0 || strcmp(cmd, "cls") == 0) {
        doldoc_clear();
    } else if (strcmp(cmd, "wm") == 0 || strcmp(cmd, "desktop") == 0) {
        doldoc_print("\n$FG,YELLOW$[CONTINUUM]$FG$ Entering N-Window Desktop Manager (Preserving Document State)...\n");
        WMEventLoop();
        I64 full_w = gfx_get_canvas_width();
        I64 full_h = gfx_get_canvas_height();
        if (full_w <= 0) full_w = 1024;
        if (full_h <= 0) full_h = 768;
        doldoc_move(0, 0, full_w, full_h);
        doldoc_mark_all_dirty();
        ShellPrintPrompt();
        doldoc_redraw();
        doldoc_swap_term();
        return;
    } else if (strcmp(cmd, "exit") == 0 || strcmp(cmd, "shell") == 0) {
        doldoc_print("\n$FG,YELLOW$[CONTINUUM]$FG$ Returning to Fullscreen Sovereign DolDoc Console...\n");
        WMExit();
        return;
    } else if (strcmp(cmd, "newwin") == 0) {
        I64 off = (g_wm.count * 28) % 160;
        I64 wid = WMCreateWindow("Dynamic Studio Window", 180 + off, 90 + off, 340, 220, 2, StudioWinDraw, StudioWinClick);
        doldoc_printf("$FG,GREEN$[WM]$FG$ Spawned dynamic window #%lld (Total windows: %lld)\n", wid, g_wm.count);
    } else if (strncmp(cmd, "inspect", 7) == 0) {
        U8 *arg = cmd + 7;
        while (*arg == ' ') arg++;
        if (*arg) {
            I64 target_wid = -1;
            if (*arg >= '0' && *arg <= '9') {
                target_wid = 0;
                while (*arg >= '0' && *arg <= '9') {
                    target_wid = target_wid * 10 + (*arg - '0');
                    arg++;
                }
            } else {
                target_wid = doldoc_find_widget(arg);
            }
            if (target_wid >= 0 && target_wid < doldoc_get_widget_count()) {
                doldoc_set_inspected_wid(target_wid);
                doldoc_set_inspector_mode(1);
                U8 *wlbl = doldoc_get_widget_label(target_wid);
                doldoc_printf("$FG,YELLOW$[MORPHIC HALO]$FG$ Inspecting Widget #%lld ($FG,CYAN$%s$FG$)\n",
                              target_wid, wlbl[0] ? wlbl : "Widget");
                doldoc_mark_all_dirty();
                doldoc_redraw();
                doldoc_swap_term();
                return;
            } else {
                doldoc_printf("$FG,RED$[MORPHIC HALO]$FG$ Widget '%s' not found (Total widgets: %lld)\n",
                              arg, doldoc_get_widget_count());
                return;
            }
        }
        I64 new_mode = !doldoc_get_inspector_mode();
        doldoc_set_inspector_mode(new_mode);
        if (!new_mode) doldoc_set_inspected_wid(-1);
        doldoc_printf("$FG,YELLOW$[MORPHIC HALO]$FG$ Live Widget Inspector Mode: $FG,CYAN$%s$FG$ (Click any widget to inspect)\n",
                      new_mode ? "ENABLED" : "DISABLED");
        doldoc_mark_all_dirty();
        doldoc_redraw();
        doldoc_swap_term();
    } else if (strncmp(cmd, "theme", 5) == 0) {
        U8 *targ = cmd + 5;
        while (*targ == ' ') targ++;
        if (!*targ) targ = "next";
        ThemeSetByName(targ);
        CompositorDamageAll();
        doldoc_mark_all_dirty();
        if (strstr(g_doc_chars, "Switch Live:") != 0 || strstr(g_doc_chars, "Catmull-Rom") != 0) {
            doldoc_printf("$FG,GREEN$[THEME]$FG$ Active Semantic Theme Skin: $FG,YELLOW$%s$FG$\n", g_theme.name);
        } else if (strstr(g_doc_chars, "Continuum:") != 0 || strstr(g_doc_chars, "Flagship & Desktop") != 0) {
            doldoc_clear();
            ShellPrintBootBanner();
            ShellPrintPrompt();
        } else {
            doldoc_printf("$FG,GREEN$[THEME]$FG$ Active Semantic Theme Skin: $FG,YELLOW$%s$FG$\n", g_theme.name);
        }
        doldoc_redraw();
        doldoc_swap_term();
        return;
    } else if (strcmp(cmd, "shader") == 0 || strncmp(cmd, "shader ", 7) == 0) {
        U64 sh_fn = symbols_lookup("ShaderEditorCmd");
        if (sh_fn != 0) {
            ShaderEditorCmd(cmd + 6);
        } else {
            ShellRunCommand("run ShaderEditor.HC");
            return;
        }
    } else if (strcmp(cmd, "ls") == 0 || strcmp(cmd, "dir") == 0) {
        redsea_list_dir();
    } else if (strcmp(cmd, "mem") == 0) {
        kheap_dump_doldoc();
        U64 kh_fn = symbols_lookup("KHeapPrintStats");
        if (kh_fn != 0) KHeapPrintStats();
    } else if (strcmp(cmd, "reboot") == 0) {
        hal_reset_system();
    } else if (strncmp(cmd, "uf ", 3) == 0) {
        U8 *arg = cmd + 3;
        while (*arg == ' ') arg++;
        DisasmFunction(arg);
    } else if (strcmp(cmd, "uf") == 0) {
        doldoc_print("Usage: uf <function_name> (e.g. uf DolDocRedraw, uf WMExit, uf SchedInit)\n");
    } else if (strncmp(cmd, "src ", 4) == 0) {
        U8 *arg = cmd + 4;
        while (*arg == ' ') arg++;
        ShellInspectSource(arg);
    } else if (strcmp(cmd, "src") == 0) {
        doldoc_print("Usage: src <file.HC> (e.g. src DolDoc.HC, src DolDoc.HC, src Compiler.HC)\n");
    } else if (strcmp(cmd, "bench") == 0) {
        ShellRunCommand("run HolyBenchmark.HC");
        return;
    } else if (strcmp(cmd, "gears") == 0) {
        ShellRunCommand("run Gears3D.HC");
        return;
    } else if (strcmp(cmd, "physics") == 0) {
        ShellRunCommand("run Physics3D.HC");
        return;
    } else if (strcmp(cmd, "holygl") == 0) {
        ShellRunCommand("run HolyGL.HC");
        return;
    } else if (strcmp(cmd, "stopbench") == 0) {
        bench_unified_stop();
        doldoc_print("$FG,YELLOW$[3D VIEWPORT]$FG$ Stopped 3D rendering pipeline.\n");
    } else if (strcmp(cmd, "explode") == 0) {
        physics3d_world_explode();
        doldoc_print("$FG,RED$[3D DYNAMICS]$FG$ Polyhedral explosion impulse applied!\n");
    } else if (strcmp(cmd, "impulse") == 0) {
        bench_unified_trigger_impulse();
        doldoc_print("$FG,GREEN$[3D DYNAMICS]$FG$ Rigid body dynamic impulse applied.\n");
    } else if (strcmp(cmd, "compositor") == 0 || strncmp(cmd, "compositor ", 11) == 0) {
        CompositorCmd(cmd + 10);
    } else if (strcmp(cmd, "perf") == 0) {
        doldoc_print("$CARD,title=\"NeoOS RivaTuner (RTSS) Hardware Telemetry\",w=96,h=4$\n");
        doldoc_printf("  Uptime: $FG,GREEN$%lld sec$FG$ | Frame Time: $FG,YELLOW$%lld us$FG$ | FPS: $FG,CYAN$%lld$FG$\n",
                      timer_get_uptime_sec(), g_comp.frame_time_us, g_comp.fps);
        doldoc_print("$HR$\n");
    } else if (strncmp(cmd, "vsync", 5) == 0) {
        U8 *arg = cmd + 5;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "on") == 0 || strcmp(arg, "60") == 0) {
            gfx_vsync_set(1, 60);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ V-Sync locked to 60 Hz.\n");
        } else if (strcmp(arg, "120") == 0) {
            gfx_vsync_set(1, 120);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ V-Sync locked to 120 Hz.\n");
        } else {
            gfx_vsync_set(0, 0);
            doldoc_print("$FG,YELLOW$[VSYNC]$FG$ V-Sync disabled.\n");
        }
    } else if (strncmp(cmd, "zeroram", 7) == 0) {
        U8 *arg = cmd + 7;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "on") == 0 || strcmp(arg, "1") == 0) {
            gfx_set_zero_ram_mode(1);
            doldoc_print("$FG,GREEN$[ZERORAM]$FG$ Zero-RAM Direct Scanout enabled (0 ms blit)!\n");
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
            doldoc_print("$FG,MAUVE$[GFX]$FG$ Switched to VirtIO-GPU Hardware DMA Scanout.\n");
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
    } else if (strncmp(cmd, "save ", 5) == 0) {
        U8 *arg = cmd + 5;
        while (*arg == ' ') arg++;
        U8 s_name[48];
        I64 s_idx = 0;
        while (*arg && *arg != ' ' && s_idx < 47) {
            s_name[s_idx] = *arg;
            s_idx++;
            arg++;
        }
        s_name[s_idx] = 0;
        while (*arg == ' ') arg++;
        I64 s_len = strlen(arg);
        if (s_name[0] && s_len > 0) {
            if (redsea_write_file(s_name, arg, s_len) == 0) {
                doldoc_printf("$FG,GREEN$[SAVE]$FG$ Persisted '%s' (%lld bytes) to RedSea disk!\n", s_name, s_len);
            } else {
                doldoc_printf("$FG,RED$[SAVE ERR]$FG$ Failed writing '%s' to disk!\n", s_name);
            }
        } else {
            doldoc_print("Usage: save <filename> <text content>\n");
        }
    } else if (strncmp(cmd, "hcrun ", 6) == 0) {
        U8 *fname = cmd + 6;
        while (*fname == ' ') fname++;
        U8 *fbuf = kmalloc(131072);
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 131071, &fsize) == 0) {
            fbuf[fsize] = 0;
            I64 hcrun_save_boot = g_kernel_booting;
            g_kernel_booting = 1;
            doldoc_printf("[HCRUN] Compiling %s (%lld bytes) with Compiler.HC...\n", fname, fsize);
            I64 res = CompilerCompileAndRun(fbuf);
            g_kernel_booting = hcrun_save_boot;
            doldoc_printf("[HCRUN] %s -> %lld\n", fname, res);
        } else {
            doldoc_printf("[HCRUN ERR] file not found on RedSea: %s\n", fname);
        }
        kfree(fbuf);
    } else if (strncmp(cmd, "run ", 4) == 0) {
        U8 *fname = cmd + 4;
        while (*fname == ' ') fname++;
        U8 *fbuf = kmalloc(131072);
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 131071, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("$FG,GREEN$[RUN]$FG$ Compiling and executing %s (%lld bytes)...\n", fname, fsize);
            I64 res;
            if (g_hc_ready) { res = CompilerCompileAndRun(fbuf); } else { res = jit_compile_and_run(fbuf); }
            doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
        } else {
            doldoc_printf("$FG,RED$File not found on RedSea disk: %s$FG$\n", fname);
        }
        kfree(fbuf);
    } else if (strncmp(cmd, "cat ", 4) == 0) {
        U8 *fname = cmd + 4;
        while (*fname == ' ') fname++;
        U8 *fbuf = kmalloc(131072);
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 131071, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("\n$CARD,title=\"RedSea File Content: %s (%lld bytes)\",w=108,h=2$\n", fname, fsize);
            doldoc_print("$HR$\n");
            for (I64 ci = 0; ci < fsize; ci++) {
                U8 ch = fbuf[ci];
                if (ch == '$') {
                    doldoc_putc('$');
                    doldoc_putc('$');
                } else {
                    doldoc_putc(ch);
                }
            }
            doldoc_print("\n$HR$\n\n");
        } else {
            doldoc_printf("$FG,RED$[CAT ERR]$FG$ File '%s' not found on RedSea disk!\n", fname);
        }
        kfree(fbuf);
    } else {
        I64 res;
        if (g_hc_ready) { res = CompilerCompileAndRun(cmd); } else { res = jit_compile_and_run(cmd); }
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
    }

    ShellPrintPrompt();
    g_shell_dirty = 1;
}

U0 shell_run_command(U8 *raw_cmd) {
    ShellRunCommand(raw_cmd);
}

U0 ShellPoll() {
    while (keyboard_has_char()) {
        I64 c = keyboard_getchar();
        if (c == KEY_ENTER || c == 10 || c == 13) {
            doldoc_draw_cursor(0);
            doldoc_putc('\n');
            g_shell_cmd[g_shell_len] = 0;
            U8 cur_cmd[SHELL_MAX_LINE];
            strcpy(cur_cmd, g_shell_cmd);
            g_shell_len = 0;
            g_shell_cmd[0] = 0;
            ShellRunCommand(cur_cmd);
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
        } else if (c == KEY_PAGE_UP) {
            doldoc_scroll_up(5);
        } else if (c == KEY_PAGE_DOWN) {
            doldoc_scroll_down(5);
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

    g_cursor_ticks++;
    if (g_cursor_ticks % 20 == 0) {
        g_cursor_visible = !g_cursor_visible;
        doldoc_draw_cursor(g_cursor_visible);
        doldoc_swap_cursor();
    }
}

U0 shell_poll() {
    ShellPoll();
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
}

I64 g_shell_running = 1;

U0 DolDocShellEventLoop() {
    uart_puts("[SHELL.HC] DolDocShell starting...\n");
    DolDocInit();
    I64 full_w = gfx_get_canvas_width();
    I64 full_h = gfx_get_canvas_height();
    if (full_w <= 0) full_w = 1024;
    if (full_h <= 0) full_h = 768;

    doldoc_move(0, 0, full_w, full_h);
    doldoc_clear();
    ShellInit();
    ShellPrintBootBanner();
    ShellPrintPrompt();
    doldoc_redraw();
    doldoc_swap_term();
    uart_puts("[SHELL.HC] DolDocShell active\n");

    g_shell_running = 1;
    I64 prev_mb = 0;
    I64 last_anim_ms = timer_get_uptime_ms();

    while (g_shell_running) {
        virtio_input_poll();
        keyboard_poll();
        mouse_poll();

        I64 mb = mouse_get_buttons();
        if (mb != 0) {
            I64 mx = mouse_get_x();
            I64 my = mouse_get_y();
            if (prev_mb == 0) {
                doldoc_handle_click(mx, my);
            } else {
                doldoc_handle_drag(mx, my);
            }
        } else if (prev_mb != 0) {
            doldoc_handle_mouse_up();
        }
        prev_mb = mb;

        shell_poll();

        I64 cur_anim_ms = timer_get_uptime_ms();
        if (cur_anim_ms - last_anim_ms >= 33) {
            last_anim_ms = cur_anim_ms;
            doldoc_animate_tick();
        }

        if (g_shell_dirty != 0) {
            doldoc_redraw();
            doldoc_swap_term();
            g_shell_dirty = 0;
        }

        task_yield();
    }
}

ShellInit();
