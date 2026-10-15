// ==============================================================================
// Editor.HC - Sovereign Pure HolyC Code Inspector & Persistent Disk Editor
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Line-Numbered Source Viewer, Syntax Highlighting & RedSea Writeback
// ==============================================================================

U8 g_editor_target[64];

U0 EditorInspect(U8 *filename) {
    if (!filename || !*filename) {
        filename = "fact.HC";
    }
    strncpy(g_editor_target, filename, 63);
    g_editor_target[63] = 0;

    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf("$FG,WHITE$    ✦ NeoOS Sovereign HolyC Code Inspector & Editor: %s ✦$FG$\n", g_editor_target);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf(" Volume: RedSea 32MB Disk | Path: $FG,YELLOW$%s/%s$FG$\n", redsea_get_pwd(), g_editor_target);
    doldoc_printf(" Actions: $BT,\"Execute [F5]\",LM=\"run %s\"$  $BT,\"Writeback Test\",LM=\"save %s // edited\"$  $BT,\"Filer\",LM=\"filer\"$\n",
                  g_editor_target, g_editor_target);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    I64 buf_sz = 16384;
    U8 *buf = kmalloc(buf_sz);
    if (!buf) {
        doldoc_print("$FG,RED$Memory allocation failure in Editor!$FG$\n");
        return;
    }
    memset(buf, 0, buf_sz);

    I64 read_bytes = 0;
    if (redsea_read_file(g_editor_target, buf, buf_sz - 1, &read_bytes) == 0) {
        buf[read_bytes] = 0;
        doldoc_printf(" File Size: $FG,GREEN$%lld bytes$FG$ | Format: Plaintext HolyC Source (.HC)\n\n", read_bytes);

        // Line-Numbered Syntax Viewer
        I64 line_num = 1;
        I64 pos = 0;
        doldoc_printf("$FG,OVERLAY0$[%02lld]$FG$ ", line_num);

        while (pos < read_bytes) {
            U8 ch = buf[pos];
            if (ch == '\n') {
                line_num++;
                doldoc_putc('\n');
                if (pos + 1 < read_bytes) {
                    doldoc_printf("$FG,OVERLAY0$[%02lld]$FG$ ", line_num);
                }
            } else if (ch == '$') {
                // Escape DolDoc tag markers
                doldoc_print("$$");
            } else {
                doldoc_putc(ch);
            }
            pos++;
        }
        doldoc_putc('\n');
    } else {
        doldoc_printf(" $FG,RED$File '%s' not found on RedSea disk!$FG$\n", g_editor_target);
        doldoc_print(" Tip: Use $FG,YELLOW$save <file> <text>$FG$ to create a new file.\n");
    }

    kfree(buf);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

U0 EditorMain() {
    EditorInspect(g_editor_target);
}

EditorInspect("fact.HC");
0;
