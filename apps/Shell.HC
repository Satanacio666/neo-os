// ==============================================================================
// Shell.HC - Sovereign Pure HolyC Interactive Shell Console, Disassembler & REPL
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Dynamic Command Registry, AArch64 Disassembler (uf), Syntax Source
//            Inspector (src), Theme/Shader/Window Control & Direct HolyC JIT REPL
// ==============================================================================

#define SHELL_MAX_LINE    256
#define SHELL_HISTORY_MAX 16
// P0.7: module source buffer. 128 KB silently truncated large modules (see
// KernelInit.HC HC_MODULE_MAX); 1 MB never truncates a .HC source.
#define SHELL_MODULE_MAX  1048576
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

// ============================================================================
// P6: FNV-1a command registry — O(1) verb dispatch (replaces the if/else ladder)
// ============================================================================
#define SHELL_MAX_CMDS    128
#define SHELL_CMD_BUCKETS 128

class CShellCmd {
    U8  name[32];
    U8  usage[64];
    I64 category;   // 0=Core 1=Desktop/Doc 2=Graphics/3D 3=Filesystem 4=Compiler/Diag
    U64 fn_addr;    // handler address: U0 (*)(U8 *args, U8 *raw)
    I64 next;       // collision chain (index into g_shell_cmds, -1 = end)
};

CShellCmd g_shell_cmds[SHELL_MAX_CMDS];
I64 g_shell_cmd_count = 0;
I64 g_shell_buckets[SHELL_CMD_BUCKETS];

U8  g_shell_cmd[SHELL_MAX_LINE];
I64 g_shell_len = 0;
U8  g_history[SHELL_HISTORY_BUF];
// P6: static scratch buffers (avoid per-command kmalloc; keeps the C-runtime census flat)
U8  g_shell_iobuf[SHELL_MODULE_MAX];
U8  g_filer_entries[64 * 128];
I64 g_history_count = 0;
I64 g_history_head = 0;
I64 g_history_nav = -1;
I64 g_cursor_visible = 1;
I64 g_cursor_ticks = 0;
I64 g_shell_dirty = 0;

U64 ShellHash(U8 *s) {
    U64 h = 0xCBF29CE484222325; // FNV-1a 64-bit offset basis
    while (*s) { h = h ^ (U64)(U8)(*s); h = h * 0x100000001B3; s++; }
    return h;
}

I64 ShellFindCmd(U8 *name) {
    if (!name || !*name) return -1;
    I64 b = (I64)(ShellHash(name) & (SHELL_CMD_BUCKETS - 1));
    I64 i = g_shell_buckets[b];
    while (i >= 0) {
        if (strcmp(g_shell_cmds[i].name, name) == 0) return i;
        i = g_shell_cmds[i].next;
    }
    return -1;
}

U0 shell_register_cmd(U8 *name, U64 fn_addr, U8 *usage) {
    if (!name || !*name || g_shell_cmd_count >= SHELL_MAX_CMDS) return;
    I64 ex = ShellFindCmd(name);
    if (ex >= 0) { g_shell_cmds[ex].fn_addr = fn_addr; return; }
    I64 idx = g_shell_cmd_count;
    g_shell_cmd_count++;
    CShellCmd *c = &g_shell_cmds[idx];
    strncpy(c->name, name, 31); c->name[31] = 0;
    c->usage[0] = 0;
    if (usage) { strncpy(c->usage, usage, 63); c->usage[63] = 0; }
    c->category = 0;
    c->fn_addr = fn_addr;
    I64 b = (I64)(ShellHash(name) & (SHELL_CMD_BUCKETS - 1));
    c->next = g_shell_buckets[b];
    g_shell_buckets[b] = idx;
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

    U8 *builtins[34];
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
    builtins[29] = "renderbench";
    builtins[30] = "shadervm";
    builtins[31] = "mesh";
    builtins[32] = "obj ";
    builtins[33] = 0;

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
    U8 *src_buf = kmalloc(SHELL_MODULE_MAX);
    I64 fsize = 0;
    if (redsea_read_file(fname, src_buf, SHELL_MODULE_MAX - 1, &fsize) == 0) {
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

// ============================================================================
// P6: action executor. Documents enqueue actions; the shell drains and runs them.
// ============================================================================
I64 g_shell_act_run = 0;

U0 ShellExecuteAction(I64 kind, I64 target, I64 val, U8 *payload) {
    if (kind == DOC_ACT_RUN) {
        if (payload && payload[0]) { ShellRunCommand(payload); g_shell_act_run++; }
    } else if (kind == DOC_ACT_OPEN) {
        U8 *fbuf = g_shell_iobuf;
        I64 fsize = 0;
        if (redsea_read_file(payload, fbuf, SHELL_MODULE_MAX - 1, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("\n$CARD,title=\"%s\",w=108,h=2$\n$HR$\n", payload);
            DolDocPrint(fbuf);
            doldoc_print("\n$HR$\n");
            g_shell_act_run++;
        } else {
            doldoc_printf("$FG,RED$[OPEN]$FG$ cannot open %s\n", payload);
        }
    } else if (kind == DOC_ACT_SET) {
        DolDocCellWrite(target, val);
        g_shell_act_run++;
    } else if (kind == DOC_ACT_CLONE) {
        I64 off = (DolDocWindowCount() * 28) % 160;
        DolDocSpawnWindow("Cloned Studio Window", 160 + off, 90 + off, 360, 240, 3);
        g_shell_act_run++;
    } else if (kind == DOC_ACT_FOCUS) {
        DolDocFocusWindow(target);
        g_shell_act_run++;
    }
}

U0 ShellDrainActions() {
    I64 k = 0; I64 t = 0; I64 v = 0;
    U8 payload[128];
    I64 guard = 0;
    while (DolDocPollAction(&k, &t, &v, payload) && guard < 256) {
        guard++;
        ShellExecuteAction(k, t, v, payload);
    }
}

// ============================================================================
// P6: command handlers — one per verb, dispatched O(1) via the FNV-1a registry
// ============================================================================
U0 ShellCmd_help(U8 *a, U8 *r) {
    doldoc_print("\n$CARD,title=\"NeoOS Sovereign Pure HolyC Shell Console & Command Reference\",w=110,h=8$\n");
    doldoc_print("  $FG,YELLOW$Flagship & UI :$FG$ $FG,CYAN$shader [0..3]$FG$ (Shadertoy IDE), $FG,CYAN$wm$FG$ (Desktop), $FG,CYAN$newwin$FG$, $FG,CYAN$inspect$FG$ (Morphic Halos)\n");
    doldoc_print("  $FG,YELLOW$Themes & Skins:$FG$ $FG,CYAN$theme <mocha|latte|tokyo|nord|temple|cyberpunk>$FG$, $FG,CYAN$compositor$FG$\n");
    doldoc_print("  $FG,YELLOW$Compiler/Debug:$FG$ $FG,CYAN$uf <symbol>$FG$ (ARM64 Disasm), $FG,CYAN$src <file.HC>$FG$, $FG,CYAN$run Compiler.HC$FG$, $FG,CYAN$run TestJitP0.HC$FG$\n");
    doldoc_print("  $FG,YELLOW$3D & Bench    :$FG$ $FG,CYAN$bench$FG$, $FG,CYAN$renderbench$FG$ (tri/s, Mpix/s), $FG,CYAN$shadervm$FG$ (raymarch), $FG,CYAN$gears$FG$, $FG,CYAN$physics$FG$, $FG,CYAN$holygl$FG$, $FG,CYAN$perf$FG$, $FG,CYAN$mem$FG$\n");
    doldoc_print("  $FG,YELLOW$RedSea Disk   :$FG$ $FG,CYAN$ls$FG$, $FG,CYAN$filer$FG$ (interactive), $FG,CYAN$cd$FG$, $FG,CYAN$mkdir$FG$, $FG,CYAN$rm$FG$, $FG,CYAN$cat$FG$, $FG,CYAN$save$FG$, $FG,CYAN$edit$FG$\n");
    doldoc_print("  $FG,YELLOW$System        :$FG$ $FG,CYAN$top$FG$ (live monitor), $FG,CYAN$selftest$FG$, $FG,CYAN$jitmap$FG$, $FG,CYAN$clear$FG$, $FG,CYAN$reboot$FG$\n");
    doldoc_print("  $FG,YELLOW$Live HolyC JIT:$FG$ Type any HolyC expression or function directly at the prompt (e.g. $FG,GREEN$2 + 2 * 10;$FG$)\n\n\n");
}

U0 ShellCmd_clear(U8 *a, U8 *r) { doldoc_clear(); }

U0 ShellCmd_wm(U8 *a, U8 *r) {
    doldoc_print("\n$FG,YELLOW$[CONTINUUM]$FG$ Entering N-Window Desktop Manager (Preserving Document State)...\n");
    DolDocDesktopLoop();
    I64 full_w = gfx_get_canvas_width();
    I64 full_h = gfx_get_canvas_height();
    if (full_w <= 0) full_w = 1024;
    if (full_h <= 0) full_h = 768;
    doldoc_move(0, 0, full_w, full_h);
    doldoc_mark_all_dirty();
    doldoc_redraw();
    doldoc_swap_term();
}

U0 ShellCmd_exit(U8 *a, U8 *r) {
    doldoc_print("\n$FG,YELLOW$[CONTINUUM]$FG$ Returning to Fullscreen Sovereign DolDoc Console...\n");
    DolDocDesktopClose();
}

U0 ShellCmd_newwin(U8 *a, U8 *r) {
    I64 off = (DolDocWindowCount() * 28) % 160;
    I64 wid = DolDocSpawnWindow("Dynamic Studio Window", 180 + off, 90 + off, 340, 220, 3);
    doldoc_printf("$FG,GREEN$[WM]$FG$ Spawned dynamic window #%lld (Total windows: %lld)\n", wid, DolDocWindowCount());
}

U0 ShellCmd_inspect(U8 *a, U8 *r) {
    if (*a) {
        I64 target_wid = -1;
        if (*a >= '0' && *a <= '9') {
            target_wid = 0;
            while (*a >= '0' && *a <= '9') { target_wid = target_wid * 10 + (*a - '0'); a++; }
        } else {
            target_wid = doldoc_find_widget(a);
        }
        if (target_wid >= 0 && target_wid < doldoc_get_widget_count()) {
            doldoc_set_inspected_wid(target_wid);
            doldoc_set_inspector_mode(1);
            U8 *wlbl = doldoc_get_widget_label(target_wid);
            doldoc_printf("$FG,YELLOW$[MORPHIC HALO]$FG$ Inspecting Widget #%lld ($FG,CYAN$%s$FG$)\n",
                          target_wid, wlbl[0] ? wlbl : "Widget");
            doldoc_mark_all_dirty(); doldoc_redraw(); doldoc_swap_term();
            return;
        }
        doldoc_printf("$FG,RED$[MORPHIC HALO]$FG$ Widget '%s' not found (Total widgets: %lld)\n", a, doldoc_get_widget_count());
        return;
    }
    I64 new_mode = !doldoc_get_inspector_mode();
    doldoc_set_inspector_mode(new_mode);
    if (!new_mode) doldoc_set_inspected_wid(-1);
    doldoc_printf("$FG,YELLOW$[MORPHIC HALO]$FG$ Live Widget Inspector Mode: $FG,CYAN$%s$FG$ (Click any widget to inspect)\n",
                  new_mode ? "ENABLED" : "DISABLED");
    doldoc_mark_all_dirty(); doldoc_redraw(); doldoc_swap_term();
}

U0 ShellCmd_theme(U8 *a, U8 *r) {
    if (!*a) a = "next";
    ThemeSetByName(a);
    DolDocDamageAll();
    doldoc_mark_all_dirty();
    doldoc_printf("$FG,GREEN$[THEME]$FG$ Active Semantic Theme Skin: $FG,YELLOW$%s$FG$\n", g_theme.name);
    doldoc_redraw(); doldoc_swap_term();
}

U0 ShellCmd_shader(U8 *a, U8 *r) {
    if (symbols_lookup("ShaderEditorCmd") != 0) {
        ShaderEditorCmd(a);
    } else {
        ShellRunCommand("run ShaderEditor.HC");
    }
}

U0 ShellCmd_ls(U8 *a, U8 *r) { redsea_list_dir(); }
U0 ShellCmd_mem(U8 *a, U8 *r) {
    kheap_dump_doldoc();
    if (symbols_lookup("KHeapPrintStats") != 0) KHeapPrintStats();
}
U0 ShellCmd_reboot(U8 *a, U8 *r) { hal_reset_system(); }
U0 ShellCmd_uf(U8 *a, U8 *r) {
    if (!*a) { doldoc_print("Usage: uf <function_name> (e.g. uf DolDocRedraw, uf SchedInit)\n"); return; }
    DisasmFunction(a);
}
U0 ShellCmd_src(U8 *a, U8 *r) {
    if (!*a) { doldoc_print("Usage: src <file.HC> (e.g. src DolDoc.HC, src Compiler.HC)\n"); return; }
    ShellInspectSource(a);
}
U0 ShellCmd_renderbench(U8 *a, U8 *r) { RenderBench(); }
U0 ShellCmd_shadervm(U8 *a, U8 *r) { ShaderVMDemo(); }
U0 ShellCmd_mesh(U8 *a, U8 *r) { MeshDemo(); }
U0 ShellCmd_obj(U8 *a, U8 *r) {
    if (!*a) { doldoc_print("Usage: obj <file.obj>\n"); return; }
    I64 ores = MeshLoadFile(a);
    if (ores < 0) doldoc_printf("$FG,RED$obj: cannot read %s (see `ls`)$FG$\n", a);
    else doldoc_printf("$FG,GREEN$obj: %s -> v=%lld tris=%lld$FG$\n", a, MeshGetVertexCount(), MeshGetTriCount());
}
U0 ShellCmd_bench(U8 *a, U8 *r) { ShellRunCommand("run HolyBenchmark.HC"); }
U0 ShellCmd_gears(U8 *a, U8 *r) { ShellRunCommand("run Gears3D.HC"); }
U0 ShellCmd_physics(U8 *a, U8 *r) { ShellRunCommand("run Physics3D.HC"); }
U0 ShellCmd_holygl(U8 *a, U8 *r) { ShellRunCommand("run HolyGL.HC"); }
U0 ShellCmd_stopbench(U8 *a, U8 *r) { bench_unified_stop(); doldoc_print("$FG,YELLOW$[3D VIEWPORT]$FG$ Stopped 3D rendering pipeline.\n"); }
U0 ShellCmd_explode(U8 *a, U8 *r) { physics3d_world_explode(); doldoc_print("$FG,RED$[3D DYNAMICS]$FG$ Polyhedral explosion impulse applied!\n"); }
U0 ShellCmd_impulse(U8 *a, U8 *r) { bench_unified_trigger_impulse(); doldoc_print("$FG,GREEN$[3D DYNAMICS]$FG$ Rigid body dynamic impulse applied.\n"); }
U0 ShellCmd_compositor(U8 *a, U8 *r) { DolDocCompositorCmd(a); }

U0 ShellCmd_perf(U8 *a, U8 *r) {
    doldoc_print("$CARD,title=\"NeoOS RivaTuner (RTSS) Hardware Telemetry\",w=96,h=4$\n");
    doldoc_printf("  Uptime: $FG,GREEN$%lld sec$FG$ | Frame Time: $FG,YELLOW$%lld us$FG$ | FPS: $FG,CYAN$%lld$FG$\n",
                  timer_get_uptime_sec(), DolDocGetFrameUs(), DolDocGetFps());
    doldoc_print("$HR$\n");
}

U0 ShellCmd_vsync(U8 *a, U8 *r) {
    if (strcmp(a, "on") == 0 || strcmp(a, "60") == 0) { gfx_vsync_set(1, 60); doldoc_print("$FG,GREEN$[VSYNC]$FG$ V-Sync locked to 60 Hz.\n"); }
    else if (strcmp(a, "120") == 0) { gfx_vsync_set(1, 120); doldoc_print("$FG,GREEN$[VSYNC]$FG$ V-Sync locked to 120 Hz.\n"); }
    else { gfx_vsync_set(0, 0); doldoc_print("$FG,YELLOW$[VSYNC]$FG$ V-Sync disabled.\n"); }
}

U0 ShellCmd_zeroram(U8 *a, U8 *r) {
    if (strcmp(a, "on") == 0 || strcmp(a, "1") == 0) { GfxDeviceSetZeroRam(1); doldoc_print("$FG,GREEN$[ZERORAM]$FG$ Zero-RAM Direct Scanout enabled (0 ms blit)!\n"); }
    else if (strcmp(a, "off") == 0 || strcmp(a, "0") == 0) { GfxDeviceSetZeroRam(0); doldoc_print("$FG,YELLOW$[ZERORAM]$FG$ Double-buffered RAM backbuffer restored.\n"); }
    else doldoc_printf("Zero-RAM mode: %s\n", GfxDeviceIsZeroRam() ? "ACTIVE" : "OFF");
}

U0 ShellCmd_render(U8 *a, U8 *r) {
    if (strcmp(a, "cpu") == 0) { GfxDeviceSetMode(0); doldoc_print("$FG,CYAN$[GFX]$FG$ Switched to Pure CPU Software Graphics.\n"); }
    else if (strcmp(a, "gpu") == 0) { GfxDeviceSetMode(1); doldoc_print("$FG,MAUVE$[GFX]$FG$ Switched to VirtIO-GPU Hardware DMA Scanout.\n"); }
    else if (strcmp(a, "smp") == 0) { GfxDeviceSetMode(2); doldoc_print("$FG,GREEN$[GFX]$FG$ Switched to SMP Multi-Core Parallel Graphics.\n"); }
    else doldoc_print("Usage: render <cpu | gpu | smp>\n");
}

U0 ShellCmd_cd(U8 *a, U8 *r) {
    if (!*a) { doldoc_printf("pwd: %s\n", redsea_get_pwd()); return; }
    if (redsea_change_dir(a) == 0) doldoc_printf("Changed directory to: %s\n", redsea_get_pwd());
    else doldoc_printf("$FG,RED$Directory not found: %s$FG$\n", a);
}
U0 ShellCmd_mkdir(U8 *a, U8 *r) {
    if (redsea_mkdir(a) == 0) doldoc_printf("$FG,GREEN$Created directory: %s$FG$\n", a);
    else doldoc_printf("$FG,RED$Could not create directory: %s$FG$\n", a);
}
U0 ShellCmd_rm(U8 *a, U8 *r) {
    if (redsea_delete_file(a) == 0) doldoc_printf("$FG,GREEN$Deleted: %s$FG$\n", a);
    else doldoc_printf("$FG,RED$Could not delete: %s$FG$\n", a);
}
U0 ShellCmd_save(U8 *a, U8 *r) {
    U8 s_name[48];
    I64 s_idx = 0;
    while (*a && *a != ' ' && s_idx < 47) { s_name[s_idx] = *a; s_idx++; a++; }
    s_name[s_idx] = 0;
    while (*a == ' ') a++;
    I64 s_len = strlen(a);
    if (s_name[0] && s_len > 0) {
        if (redsea_write_file(s_name, a, s_len) == 0) doldoc_printf("$FG,GREEN$[SAVE]$FG$ Persisted '%s' (%lld bytes) to RedSea disk!\n", s_name, s_len);
        else doldoc_printf("$FG,RED$[SAVE ERR]$FG$ Failed writing '%s' to disk!\n", s_name);
    } else {
        doldoc_print("Usage: save <filename> <text content>\n");
    }
}
U0 ShellCmd_selftest(U8 *a, U8 *r) { SelfTestRun(); }
U0 ShellCmd_jitmap(U8 *a, U8 *r) { HcMapDump(); }
U0 ShellCmd_kpanic(U8 *a, U8 *r) {
    g_exc_user_ok = 0;
    doldoc_print("$FG,RED$[KPANIC] forcing kernel null write...$FG$\n");
    *(U64*)0 = 0xDEADBEEF;
}
U0 ShellCmd_hcrun(U8 *a, U8 *r) {
    U8 *fbuf = kmalloc(SHELL_MODULE_MAX);
    I64 fsize = 0;
    if (redsea_read_file(a, fbuf, SHELL_MODULE_MAX - 1, &fsize) == 0) {
        fbuf[fsize] = 0;
        I64 hcrun_save_boot = g_kernel_booting;
        g_kernel_booting = 1;
        doldoc_printf("[HCRUN] Compiling %s (%lld bytes) with Compiler.HC...\n", a, fsize);
        I64 res = CompilerCompileAndRun(fbuf);
        g_kernel_booting = hcrun_save_boot;
        doldoc_printf("[HCRUN] %s -> %lld\n", a, res);
    } else {
        doldoc_printf("[HCRUN ERR] file not found on RedSea: %s\n", a);
    }
    kfree(fbuf);
}
U0 ShellCmd_run(U8 *a, U8 *r) {
    U8 *fbuf = kmalloc(SHELL_MODULE_MAX);
    I64 fsize = 0;
    if (redsea_read_file(a, fbuf, SHELL_MODULE_MAX - 1, &fsize) == 0) {
        fbuf[fsize] = 0;
        doldoc_printf("$FG,GREEN$[RUN]$FG$ Compiling and executing %s (%lld bytes)...\n", a, fsize);
        I64 res;
        if (g_hc_ready) res = CompilerCompileAndRun(fbuf); else res = jit_compile_and_run(fbuf);
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
    } else {
        doldoc_printf("$FG,RED$File not found on RedSea disk: %s$FG$\n", a);
    }
    kfree(fbuf);
}
U0 ShellCmd_cat(U8 *a, U8 *r) {
    U8 *fbuf = kmalloc(SHELL_MODULE_MAX);
    I64 fsize = 0;
    if (redsea_read_file(a, fbuf, SHELL_MODULE_MAX - 1, &fsize) == 0) {
        fbuf[fsize] = 0;
        doldoc_printf("\n$CARD,title=\"RedSea File Content: %s (%lld bytes)\",w=108,h=2$\n", a, fsize);
        doldoc_print("$HR$\n");
        for (I64 ci = 0; ci < fsize; ci++) {
            U8 ch = fbuf[ci];
            if (ch == '$') { doldoc_putc('$'); doldoc_putc('$'); } else doldoc_putc(ch);
        }
        doldoc_print("\n$HR$\n\n");
    } else {
        doldoc_printf("$FG,RED$[CAT ERR]$FG$ File '%s' not found on RedSea disk!\n", a);
    }
    kfree(fbuf);
}

// ---- P6 tools: top / filer / edit ------------------------------------------
U0 ShellCmd_top(U8 *a, U8 *r) {
    doldoc_print("\n$CARD,title=\"NeoOS Sovereign top - Tasks, Memory & Hardware\",w=110,h=10$\n");
    doldoc_printf("  $FG,YELLOW$Timer$FG$   : $FG,CYAN$%lld Hz$FG$ (CNTFRQ) | Preemption: $FG,GREEN$1000 Hz$FG$ | Uptime: %lld s\n",
                  HalGetTimerFreq(), timer_get_uptime_sec());
    doldoc_printf("  $FG,YELLOW$CPU$FG$     : $FG,CYAN$%lld cores$FG$ online (SMP) | Tasks: $FG,GREEN$%lld$FG$\n",
                  (I64)smp_get_core_count(), SchedCountTasks());
    doldoc_printf("  $FG,YELLOW$KHeap$FG$   : used $FG,YELLOW$%lld KB$FG$ / free $FG,GREEN$%lld KB$FG$ of %lld KB | allocs=%lld\n",
                  (I64)(KHeapUsedBytes() / 1024), (I64)(KHeapFreeBytes() / 1024),
                  (I64)(KHeapTotalBytes() / 1024), KHeapAllocCount());
    doldoc_printf("  $FG,YELLOW$Display$FG$ : %lld x %lld | $FG,CYAN$%lld FPS$FG$ (%lld us/frame)\n",
                  gfx_get_canvas_width(), gfx_get_canvas_height(), DolDocGetFps(), DolDocGetFrameUs());
    I64 heap_pct = 0;
    if (KHeapTotalBytes() > 0) heap_pct = (I64)((KHeapUsedBytes() * 100) / KHeapTotalBytes());
    doldoc_printf("  $FG,YELLOW$Heap use$FG$: $PB,VAL=%lld,MAX=100$ %lld%%\n", heap_pct, heap_pct);
    doldoc_print("$HR$\n");
    doldoc_print("  $BT,\"Refresh\",LM=\"top\"$  $BT,\"Memory (mem)\",LM=\"mem\"$  $BT,\"Run Bench\",LM=\"bench\"$  $BT,\"RenderBench\",LM=\"renderbench\"$  $BT,\"NeoMenu\",LM=\"wm\"$\n");
    doldoc_print("$HR$\n\n");
}

U0 ShellCmd_filer(U8 *a, U8 *r) {
    U8 *entries = g_filer_entries;
    I64 n = redsea_get_entries(entries, 128);
    doldoc_printf("\n$CARD,title=\"RedSea Filer\",w=110,h=4$\n");
    doldoc_printf("  $FG,YELLOW$Path:$FG$ %s  |  $FG,CYAN$%lld entries$FG$\n", redsea_get_pwd(), n);
    doldoc_print("  $BT,\"Up (cd ..)\",LM=\"cd ..\"$  $BT,\"Root (cd /)\",LM=\"cd /\"$  $BT,\"Refresh\",LM=\"filer\"$  $BT,\"Shell\",LM=\"exit\"$\n");
    doldoc_print("$HR$\n");
    for (I64 i = 0; i < n; i++) {
        U8 *nm = entries + i * 64 + 2;   // CRedSeaEntry: U16 attr; U8 name[38]
        if (!nm[0]) continue;
        doldoc_printf("  $BT,\"Open\",LM=\"cat %s\"$ $BT,\"Edit\",LM=\"edit %s\"$ $BT,\"Run\",LM=\"run %s\"$  $FG,CYAN$%s$FG$\n",
                      nm, nm, nm, nm);
    }
    doldoc_print("$HR$\n\n");
}

U8 g_edit_buf[SHELL_MODULE_MAX];
U8 g_edit_name[48];
I64 g_edit_len = 0;

U0 ShellCmd_edit(U8 *a, U8 *r) {
    if (!*a) { doldoc_print("Usage: edit <file.HC> | editline <n> <text> | editsave | editchrun\n"); return; }
    I64 fsize = 0;
    if (redsea_read_file(a, g_edit_buf, SHELL_MODULE_MAX - 1, &fsize) != 0) {
        doldoc_printf("$FG,RED$[EDIT]$FG$ cannot open %s\n", a);
        return;
    }
    g_edit_len = fsize;
    g_edit_buf[g_edit_len] = 0;
    strncpy(g_edit_name, a, 47); g_edit_name[47] = 0;
    doldoc_printf("\n$CARD,title=\"Editor: %s (%lld bytes)\",w=110,h=3$\n", a, g_edit_len);
    doldoc_print("  $BT,\"Save to RedSea\",LM=\"editsave\"$  $BT,\"Compile & Run\",LM=\"editchrun\"$  $BT,\"Close\",LM=\"clear\"$\n$HR$\n");
    I64 line = 1; I64 col = 0; I64 shown = 0;
    for (I64 ci = 0; ci < g_edit_len && shown < 400; ci++) {
        U8 ch = g_edit_buf[ci];
        if (col == 0) doldoc_printf("$FG,MUTED$%4lld $FG$", line);
        if (ch == '$') { doldoc_putc('$'); doldoc_putc('$'); }
        else if (ch == '\n') { doldoc_putc('\n'); line++; shown++; col = 0; continue; }
        else doldoc_putc(ch);
        col++;
    }
    doldoc_print("\n$HR$\n\n");
}

U0 ShellCmd_editline(U8 *a, U8 *r) {
    if (!g_edit_name[0]) { doldoc_print("$FG,RED$[EDIT]$FG$ no buffer; run `edit <file>` first\n"); return; }
    I64 ln = 0;
    while (*a >= '0' && *a <= '9') { ln = ln * 10 + (*a - '0'); a++; }
    while (*a == ' ') a++;
    U8 *nb = g_shell_iobuf;
    I64 oi = 0; I64 cur = 1; I64 bi = 0;
    while (bi < g_edit_len && oi < SHELL_MODULE_MAX - 2) {
        if (cur == ln) {
            while (*a && oi < SHELL_MODULE_MAX - 2) { nb[oi] = *a; oi++; a++; }
            nb[oi] = '\n'; oi++;
            while (bi < g_edit_len && g_edit_buf[bi] != '\n') bi++;
            if (bi < g_edit_len) bi++;
            cur++;
            continue;
        }
        nb[oi] = g_edit_buf[bi]; oi++;
        if (g_edit_buf[bi] == '\n') cur++;
        bi++;
    }
    for (I64 k = 0; k < oi; k++) g_edit_buf[k] = nb[k];
    g_edit_len = oi;
    doldoc_printf("$FG,GREEN$[EDIT]$FG$ line %lld replaced (%lld bytes)\n", ln, g_edit_len);
}

U0 ShellCmd_editsave(U8 *a, U8 *r) {
    if (g_edit_name[0] && redsea_write_file(g_edit_name, g_edit_buf, g_edit_len) == 0)
        doldoc_printf("$FG,GREEN$[EDIT]$FG$ Saved %lld bytes to %s\n", g_edit_len, g_edit_name);
    else
        doldoc_print("$FG,RED$[EDIT]$FG$ no buffer/file to save\n");
}

U0 ShellCmd_editchrun(U8 *a, U8 *r) {
    if (!g_edit_name[0]) { doldoc_print("$FG,RED$[EDIT]$FG$ no buffer\n"); return; }
    g_edit_buf[g_edit_len] = 0;
    doldoc_printf("$FG,GREEN$[EDIT]$FG$ Compiling buffer %s (%lld bytes)...\n", g_edit_name, g_edit_len);
    I64 res = CompilerCompileAndRun(g_edit_buf);
    doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
}

// ============================================================================
// P6: dispatcher — O(1) verb lookup, then <verb>.HC, then interactive JIT.
// ============================================================================
U0 ShellRunCommand(U8 *raw_cmd) {
    if (!raw_cmd) return;
    U8 *cmd = raw_cmd;
    while (*cmd == ' ' || *cmd == '\t') cmd++;
    if (!*cmd) { ShellPrintPrompt(); return; }
    ShellAddHistory(cmd);

    U8 verb[64];
    I64 vi = 0;
    U8 *p = cmd;
    while (*p && *p != ' ' && *p != '\t' && vi < 63) { verb[vi] = *p; vi++; p++; }
    verb[vi] = 0;
    U8 *args = p;
    while (*args == ' ' || *args == '\t') args++;

    I64 ci = ShellFindCmd(verb);
    if (ci >= 0) {
        U0 (*h)(U8 *, U8 *);
        h = g_shell_cmds[ci].fn_addr;
        if (h) h(args, cmd);
        ShellPrintPrompt();
        g_shell_dirty = 1;
        return;
    }

    // Not a builtin: try <verb>.HC on RedSea, else interactive HolyC JIT.
    U8 fname[80];
    strcpy(fname, verb);
    strcat(fname, ".HC");
    U8 *fbuf = g_shell_iobuf;
    I64 fsize = 0;
    if (redsea_read_file(fname, fbuf, SHELL_MODULE_MAX - 1, &fsize) == 0) {
        fbuf[fsize] = 0;
        I64 res = CompilerCompileAndRun(fbuf);
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
        ShellPrintPrompt();
        g_shell_dirty = 1;
        return;
    }
    I64 res;
    if (g_hc_ready) res = CompilerCompileAndRun(cmd); else res = jit_compile_and_run(cmd);
    doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
    ShellPrintPrompt();
    g_shell_dirty = 1;
}

U0 shell_run_command(U8 *raw_cmd) {
    // P3.6 guardrail 4: a fault during a user command unwinds to the shell.
    g_exc_user_ok = 1;
    ShellRunCommand(raw_cmd);
    g_exc_user_ok = 0;
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
            g_exc_user_ok = 1;
            ShellRunCommand(cur_cmd);
            g_exc_user_ok = 0;
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
    ShellDrainActions();
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

    for (I64 b = 0; b < SHELL_CMD_BUCKETS; b++) g_shell_buckets[b] = -1;
    g_shell_cmd_count = 0;
    shell_register_cmd("help", ShellCmd_help, "command reference");
    shell_register_cmd("clear", ShellCmd_clear, "clear the screen");
    shell_register_cmd("cls", ShellCmd_clear, "clear the screen");
    shell_register_cmd("wm", ShellCmd_wm, "desktop manager");
    shell_register_cmd("desktop", ShellCmd_wm, "desktop manager");
    shell_register_cmd("exit", ShellCmd_exit, "leave desktop");
    shell_register_cmd("shell", ShellCmd_exit, "leave desktop");
    shell_register_cmd("newwin", ShellCmd_newwin, "spawn window");
    shell_register_cmd("inspect", ShellCmd_inspect, "morphic halos");
    shell_register_cmd("theme", ShellCmd_theme, "set theme skin");
    shell_register_cmd("shader", ShellCmd_shader, "shadertoy IDE");
    shell_register_cmd("ls", ShellCmd_ls, "list directory");
    shell_register_cmd("dir", ShellCmd_ls, "list directory");
    shell_register_cmd("filer", ShellCmd_filer, "interactive filer");
    shell_register_cmd("edit", ShellCmd_edit, "edit file");
    shell_register_cmd("editline", ShellCmd_editline, "replace a line");
    shell_register_cmd("editsave", ShellCmd_editsave, "save edit buffer");
    shell_register_cmd("editchrun", ShellCmd_editchrun, "compile edit buffer");
    shell_register_cmd("top", ShellCmd_top, "live system monitor");
    shell_register_cmd("mem", ShellCmd_mem, "heap statistics");
    shell_register_cmd("reboot", ShellCmd_reboot, "reboot the machine");
    shell_register_cmd("uf", ShellCmd_uf, "disassemble symbol");
    shell_register_cmd("src", ShellCmd_src, "inspect source");
    shell_register_cmd("renderbench", ShellCmd_renderbench, "render benchmark");
    shell_register_cmd("shadervm", ShellCmd_shadervm, "shader VM demo");
    shell_register_cmd("mesh", ShellCmd_mesh, "mesh demo");
    shell_register_cmd("obj", ShellCmd_obj, "load OBJ mesh");
    shell_register_cmd("bench", ShellCmd_bench, "unified benchmark");
    shell_register_cmd("gears", ShellCmd_gears, "3D gears");
    shell_register_cmd("physics", ShellCmd_physics, "physics demo");
    shell_register_cmd("holygl", ShellCmd_holygl, "HolyGL demo");
    shell_register_cmd("stopbench", ShellCmd_stopbench, "stop benchmark");
    shell_register_cmd("explode", ShellCmd_explode, "physics explode");
    shell_register_cmd("impulse", ShellCmd_impulse, "physics impulse");
    shell_register_cmd("compositor", ShellCmd_compositor, "compositor/theme");
    shell_register_cmd("perf", ShellCmd_perf, "perf overlay");
    shell_register_cmd("vsync", ShellCmd_vsync, "vsync control");
    shell_register_cmd("zeroram", ShellCmd_zeroram, "zero-ram mode");
    shell_register_cmd("render", ShellCmd_render, "render backend");
    shell_register_cmd("cd", ShellCmd_cd, "change directory");
    shell_register_cmd("mkdir", ShellCmd_mkdir, "make directory");
    shell_register_cmd("rm", ShellCmd_rm, "delete file");
    shell_register_cmd("save", ShellCmd_save, "save file");
    shell_register_cmd("cat", ShellCmd_cat, "print file");
    shell_register_cmd("run", ShellCmd_run, "run a .HC file");
    shell_register_cmd("hcrun", ShellCmd_hcrun, "compile a .HC file");
    shell_register_cmd("selftest", ShellCmd_selftest, "run the selftest battery");
    shell_register_cmd("jitmap", ShellCmd_jitmap, "dump JIT symbol map");
    shell_register_cmd("kpanic", ShellCmd_kpanic, "force a kernel panic");

    // Break the DolDoc -> Shell cycle: DolDoc pumps input through this callback.
    DolDocSetPump(&shell_poll);
}

// ============================================================================
// P6 shell self-test (registry + action protocol + tools)
// ============================================================================
I64 ShellSelfTest() {
    I64 ok = 1;

    // 1. dynamic registration + O(1) hash lookup
    shell_register_cmd("testcmd_p6", ShellCmd_help, "p6 test command");
    if (ShellFindCmd("testcmd_p6") < 0) ok = 0;
    if (ShellFindCmd("help") < 0) ok = 0;
    if (ShellFindCmd("no_such_command_xyz") >= 0) ok = 0;

    // 2. action protocol: enqueue + drain all five action kinds
    I64 before_run = g_shell_act_run;
    DolDocPushAction(DOC_ACT_RUN, -1, 0, "help");
    DolDocPushAction(DOC_ACT_SET, -1, 7, 0);
    DolDocPushAction(DOC_ACT_CLONE, -1, 0, 0);
    DolDocPushAction(DOC_ACT_FOCUS, 1, 0, 0);
    DolDocPushAction(DOC_ACT_OPEN, -1, 0, "README.TXT");
    if (DolDocActionCount() < 5) ok = 0;
    ShellDrainActions();
    if (DolDocActionCount() != 0) ok = 0;
    if (g_shell_act_run <= before_run) ok = 0;

    // 3. tools emit interactive CDoc nodes (buttons)
    I64 w0 = doldoc_get_widget_count();
    ShellCmd_top("", "top");
    ShellCmd_filer("", "filer");
    if (doldoc_get_widget_count() <= w0) ok = 0;

    if (ok) { doldoc_print("$FG,GREEN$SHELL: PASS$FG$ (O(1) registry, action protocol, top/filer/edit)\n"); return 1; }
    doldoc_print("$FG,RED$SHELL: FAIL$FG$\n");
    return 0;
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

        I64 did_work = (mb != 0) ? 1 : 0;
        if (DolDocActionCount() > 0) did_work = 1;
        if (g_shell_dirty != 0) did_work = 1;

        shell_poll();

        I64 cur_anim_ms = timer_get_uptime_ms();
        if (cur_anim_ms - last_anim_ms >= 33) {
            last_anim_ms = cur_anim_ms;
            doldoc_animate_tick();
            did_work = 1;
        }

        if (g_shell_dirty != 0) {
            doldoc_redraw();
            doldoc_swap_term();
            g_shell_dirty = 0;
            did_work = 1;
        }

        // P6: hardware idle when there is no work this frame (WFE wakes on the
        // 1 kHz timer PPI); otherwise yield cooperatively to the scheduler.
        if (did_work) { task_yield(); } else { __wfe(); task_yield(); }
    }
}

ShellInit();
