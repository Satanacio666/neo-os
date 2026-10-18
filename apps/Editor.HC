// ==============================================================================
// Editor.HC - Sovereign Pure HolyC Syntax-Highlighted Code Inspector & Editor
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Token-Colored Source Viewer, Live JIT Execution & RedSea Writeback
// ==============================================================================

U8 g_editor_target[64];

U0 EditorPrintHighlightedLine(U8 *line_str) {
    if (!line_str) return;
    I64 ei = 0;
    // Check if leading comment
    I64 first_non_space = 0;
    while (line_str[first_non_space] == ' ' || line_str[first_non_space] == 9) first_non_space++;
    if (line_str[first_non_space] == '/' && line_str[first_non_space + 1] == '/') {
        doldoc_print("$FG,MUTED$");
        while (line_str[ei]) {
            if (line_str[ei] == '$') doldoc_print("$$");
            else doldoc_putc(line_str[ei]);
            ei++;
        }
        doldoc_print("$FG$");
        return;
    }
    if (line_str[first_non_space] == '#') {
        doldoc_print("$FG,MAUVE$");
        while (line_str[ei]) {
            if (line_str[ei] == '$') doldoc_print("$$");
            else doldoc_putc(line_str[ei]);
            ei++;
        }
        doldoc_print("$FG$");
        return;
    }

    I64 in_str = 0;
    while (line_str[ei]) {
        U8 ch = line_str[ei];
        if (ch == '/' && line_str[ei + 1] == '/' && !in_str) {
            doldoc_print("$FG,MUTED$");
            while (line_str[ei]) {
                if (line_str[ei] == '$') doldoc_print("$$");
                else doldoc_putc(line_str[ei]);
                ei++;
            }
            doldoc_print("$FG$");
            return;
        }
        if (ch == '"') {
            if (!in_str) {
                in_str = 1;
                doldoc_print("$FG,GREEN$\"");
            } else {
                in_str = 0;
                doldoc_print("\"$FG$");
            }
            ei++;
            continue;
        }
        if (!in_str && (ch == 'U' || ch == 'I' || ch == 'F') &&
            (line_str[ei + 1] == '0' || line_str[ei + 1] == '8' || line_str[ei + 1] == '1' ||
             line_str[ei + 1] == '3' || line_str[ei + 1] == '6')) {
            doldoc_print("$FG,CYAN$");
            while ((line_str[ei] >= 'A' && line_str[ei] <= 'Z') || (line_str[ei] >= '0' && line_str[ei] <= '9')) {
                doldoc_putc(line_str[ei]);
                ei++;
            }
            doldoc_print("$FG$");
            continue;
        }
        if (ch == '$') {
            doldoc_print("$$");
        } else {
            doldoc_putc(ch);
        }
        ei++;
    }
    if (in_str) doldoc_print("$FG$");
}

U0 EditorInspect(U8 *filename) {
    if (!filename || !*filename) {
        filename = "fact.HC";
    }
    strncpy(g_editor_target, filename, 63);
    g_editor_target[63] = 0;

    I64 buf_sz = 131072;
    U8 *buf = kmalloc(buf_sz);
    if (!buf) {
        doldoc_print("$FG,RED$[EDITOR] Memory allocation failure!$FG$\n");
        return;
    }
    memset(buf, 0, buf_sz);

    I64 read_bytes = 0;
    if (redsea_read_file(g_editor_target, buf, buf_sz - 1, &read_bytes) == 0) {
        buf[read_bytes] = 0;

        // Count total lines
        I64 total_lines = 1;
        for (I64 ci = 0; ci < read_bytes; ci++) {
            if (buf[ci] == 10) total_lines++;
        }

        doldoc_printf("\n$CARD,title=\"NeoOS Sovereign HolyC Code Editor & Syntax Inspector: %s\",w=110,h=4$\n", g_editor_target);
        doldoc_printf("  Path: $FG,YELLOW$%s/%s$FG$ | Size: $FG,GREEN$%lld bytes$FG$ ($FG,CYAN$%lld lines$FG$)\n",
                      redsea_get_pwd(), g_editor_target, read_bytes, total_lines);
        doldoc_printf("  Actions: $BT,\"Compile & Run [F5]\",LM=\"run %s\"$  $BT,\"Files (Filer)\",LM=\"filer\"$  $BT,\"Inspect Showcase.HC\",LM=\"src Showcase.HC\"$  $BT,\"Inspect ShaderEditor.HC\",LM=\"src ShaderEditor.HC\"$\n",
                      g_editor_target);
        doldoc_print("$HR$\n");

        U8 line_buf[128];
        I64 l_idx = 0;
        I64 line_num = 1;
        I64 pos = 0;

        while (pos < read_bytes && line_num <= 60) {
            U8 ch = buf[pos];
            if (ch == 10 || pos == read_bytes - 1) {
                if (ch != 10 && ch >= 32 && l_idx < 104) {
                    line_buf[l_idx++] = ch;
                }
                line_buf[l_idx] = 0;
                doldoc_printf(" $FG,MUTED$%3lld |$FG$ ", line_num);
                EditorPrintHighlightedLine(line_buf);
                doldoc_putc(10);
                l_idx = 0;
                line_num++;
            } else if (ch >= 32 && ch <= 126) {
                if (l_idx < 104) {
                    line_buf[l_idx++] = ch;
                }
            } else if (ch == 9) {
                if (l_idx < 100) {
                    line_buf[l_idx++] = ' ';
                    line_buf[l_idx++] = ' ';
                }
            }
            pos++;
        }
        if (total_lines > 60) {
            doldoc_printf(" $FG,YELLOW$... [Showing 60 of %lld lines (%lld bytes)] ...$FG$\n", total_lines, read_bytes);
        }
        doldoc_print("$HR$\n\n");
    } else {
        doldoc_printf(" $FG,RED$[EDITOR] File '%s' not found on RedSea disk!$FG$\n", g_editor_target);
        doldoc_print(" Tip: Use $FG,YELLOW$save <file> <text>$FG$ to create a new file.\n");
    }

    kfree(buf);
}

U0 EditorMain() {
    if (!g_editor_target[0]) strcpy(g_editor_target, "fact.HC");
    EditorInspect(g_editor_target);
}

EditorInspect("fact.HC");
0;
