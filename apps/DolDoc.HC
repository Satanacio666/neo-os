// ==============================================================================
// DolDoc.HC - Sovereign Pure HolyC DolDoc 2.0 Document & Geometry Continuum
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Interactive Text-as-Geometry, Reactive Widgets & Catppuccin Styling
// ==============================================================================

#define DOLDOC_MAX_COLS     96
#define DOLDOC_MAX_ROWS     32
#define DOLDOC_CELLS        3072 // 96 * 32
#define DOLDOC_HIST_LINES   256
#define DOLDOC_HIST_CELLS   24576 // 256 * 96
#define DOLDOC_MAX_WIDGETS  64

#define WIDGET_NONE         0
#define WIDGET_BUTTON       1
#define WIDGET_LINK         2
#define WIDGET_CHECKBOX     3
#define WIDGET_TREE         4

// Catppuccin Mocha Styling Palette
#define COLOR_BASE          0xFF1E1E2E
#define COLOR_MANTLE        0xFF181825
#define COLOR_CRUST         0xFF11111B
#define COLOR_SURFACE0      0xFF313244
#define COLOR_SURFACE1      0xFF45475A
#define COLOR_OVERLAY0      0xFF6C7086
#define COLOR_TEXT          0xFFCDD6F4
#define COLOR_BLUE          0xFF89B4FA
#define COLOR_SAPPHIRE      0xFF74C7EC
#define COLOR_SKY           0xFF89DCEB
#define COLOR_TEAL          0xFF94E2D5
#define COLOR_GREEN         0xFFA6E3A1
#define COLOR_YELLOW        0xFFF9E2AF
#define COLOR_PEACH         0xFFFAB387
#define COLOR_MAROON        0xFFEBA0AC
#define COLOR_RED           0xFFF38BA8
#define COLOR_MAUVE         0xFFCBA6F7
#define COLOR_PINK          0xFFF5C2E7
#define COLOR_FLAMINGO      0xFFF2CDCD
#define COLOR_ROSEWATER     0xFFF5E0DC

class CDolDocOps {
    I64 putc;
    I64 print;
    I64 clear;
    I64 redraw;
    I64 click;
    I64 move;
    I64 scroll_up;
    I64 scroll_down;
    I64 backspace;
    I64 draw_cursor;
    I64 set_bg;
    I64 get_bg;
    I64 mark_all_dirty;
};

// Viewport Geometry & State
I64 g_doc_x = 32;
I64 g_doc_y = 84;
I64 g_doc_w = 596;
I64 g_doc_h = 592;
I64 g_doc_cols = 72;
I64 g_doc_rows = 30;
I64 g_doc_cur_col = 0;
I64 g_doc_cur_row = 0;

U32 g_doc_cur_fg = COLOR_TEXT;
U32 g_doc_cur_bg = COLOR_MANTLE;

I64 g_doc_cursor_x = 40;
I64 g_doc_cursor_y = 92;
I64 g_doc_cursor_visible = 1;

U64 g_doc_dirty_mask = -1;
I64 g_doc_scroll_offset = 0;
I64 g_doc_history_count = 0;

// Flat Buffers for Grid and History
U8  g_doc_chars[DOLDOC_CELLS];
U32 g_doc_fg[DOLDOC_CELLS];
U32 g_doc_bg[DOLDOC_CELLS];
I64 g_doc_link_idx[DOLDOC_CELLS];

U8  g_hist_chars[DOLDOC_HIST_CELLS];
U32 g_hist_fg[DOLDOC_HIST_CELLS];
U32 g_hist_bg[DOLDOC_HIST_CELLS];

// Interactive Widgets Table
I64 g_widget_type[DOLDOC_MAX_WIDGETS];
I64 g_widget_row[DOLDOC_MAX_WIDGETS];
I64 g_widget_start_col[DOLDOC_MAX_WIDGETS];
I64 g_widget_end_col[DOLDOC_MAX_WIDGETS];
I64 g_widget_state[DOLDOC_MAX_WIDGETS];
U8  g_widget_label[3072]; // 64 * 48
U8  g_widget_cmd[4096];   // 64 * 64
I64 g_widget_count = 0;

// Global Tag Parsing Scratch Buffers (persistent heap, zero stack clobbering)
U8  g_tag_buf[128];
U8  g_tag_label[64];
U8  g_tag_cmd[64];
U8  g_tag_title[64];
U8  g_click_cmd_buf[64];

CDolDocOps g_doldoc_ops;

U8* DolDocParseQuoted(U8 *p, U8 *out, I64 max_out) {
    if (!p || !out) return p;
    while (*p && *p != '"') p++;
    if (!*p) {
        out[0] = 0;
        return p;
    }
    p++;
    I64 idx = 0;
    while (*p && *p != '"' && idx < max_out - 1) {
        out[idx] = *p;
        idx++;
        p++;
    }
    out[idx] = 0;
    if (*p == '"') p++;
    return p;
}

I64 DolDocAtoi(U8 *p) {
    if (!p) return 0;
    I64 res = 0;
    while (*p >= '0' && *p <= '9') {
        res = res * 10 + (*p - '0');
        p++;
    }
    return res;
}

U0 DolDocMarkAllDirty() {
    g_doc_dirty_mask = -1;
}

U0 DolDocMarkRowDirty(I64 r) {
    if (r >= 0 && r < 64) {
        g_doc_dirty_mask = g_doc_dirty_mask | (1 << r);
    }
}

U0 DolDocClear() {
    for (I64 i = 0; i < DOLDOC_CELLS; i++) {
        g_doc_chars[i] = ' ';
        g_doc_fg[i] = g_doc_cur_fg;
        g_doc_bg[i] = g_doc_cur_bg;
        g_doc_link_idx[i] = -1;
    }
    g_doc_cur_col = 0;
    g_doc_cur_row = 0;
    g_widget_count = 0;
    g_doc_scroll_offset = 0;
    g_doc_cursor_x = g_doc_x + 8;
    g_doc_cursor_y = g_doc_y + 8;
    DolDocMarkAllDirty();
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h, g_doc_cur_bg);
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, 1, COLOR_SURFACE0);
}

U0 DolDocScroll() {
    if (g_doc_rows > 1) {
        // 1. Copy row 0 into history buffer
        if (g_doc_history_count < DOLDOC_HIST_LINES) {
            I64 h_base = g_doc_history_count * DOLDOC_MAX_COLS;
            for (I64 c = 0; c < g_doc_cols; c++) {
                g_hist_chars[h_base + c] = g_doc_chars[c];
                g_hist_fg[h_base + c] = g_doc_fg[c];
                g_hist_bg[h_base + c] = g_doc_bg[c];
            }
            g_doc_history_count++;
        }
        // 2. Shift rows up
        for (I64 r = 0; r < g_doc_rows - 1; r++) {
            I64 dst = r * DOLDOC_MAX_COLS;
            I64 src = (r + 1) * DOLDOC_MAX_COLS;
            for (I64 c = 0; c < g_doc_cols; c++) {
                g_doc_chars[dst + c] = g_doc_chars[src + c];
                g_doc_fg[dst + c] = g_doc_fg[src + c];
                g_doc_bg[dst + c] = g_doc_bg[src + c];
                g_doc_link_idx[dst + c] = g_doc_link_idx[src + c];
            }
        }
        // 3. Clear bottom row
        I64 last_base = (g_doc_rows - 1) * DOLDOC_MAX_COLS;
        for (I64 c = 0; c < g_doc_cols; c++) {
            g_doc_chars[last_base + c] = ' ';
            g_doc_fg[last_base + c] = g_doc_cur_fg;
            g_doc_bg[last_base + c] = g_doc_cur_bg;
            g_doc_link_idx[last_base + c] = -1;
        }
        // 4. Shift widget row coordinates
        for (I64 w = 0; w < g_widget_count; w++) {
            g_widget_row[w] = g_widget_row[w] - 1;
        }
    }
    g_doc_cur_row = g_doc_rows - 1;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
    g_doc_cursor_y = g_doc_y + 8 + g_doc_cur_row * 18;
    DolDocMarkAllDirty();
}

U0 DolDocBackspace() {
    if (g_doc_cur_col > 0) {
        g_doc_cur_col--;
        I64 idx = g_doc_cur_row * DOLDOC_MAX_COLS + g_doc_cur_col;
        g_doc_chars[idx] = ' ';
        g_doc_link_idx[idx] = -1;
        g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
        DolDocMarkRowDirty(g_doc_cur_row);
        gfx_draw_rect(g_doc_cursor_x, g_doc_cursor_y, 8, 16, g_doc_cur_bg);
    }
}

U0 DolDocDrawCursor(I64 visible) {
    I64 color = visible ? COLOR_SKY : g_doc_cur_bg;
    gfx_draw_rect(g_doc_cursor_x, g_doc_cursor_y, 8, 16, color);
}

U0 DolDocPutc(U8 c) {
    if (c == 10) { // '\n'
        uart_putc(13);
        uart_putc(10);
        g_doc_cur_col = 0;
        g_doc_cur_row++;
        if (g_doc_cur_row >= g_doc_rows) {
            DolDocScroll();
        } else {
            g_doc_cursor_x = g_doc_x + 8;
            g_doc_cursor_y = g_doc_y + 8 + g_doc_cur_row * 18;
            DolDocMarkRowDirty(g_doc_cur_row);
        }
    } else if (c == 13) { // '\r'
        uart_putc(13);
        g_doc_cur_col = 0;
        g_doc_cursor_x = g_doc_x + 8;
    } else if (c == 8) { // '\b'
        uart_putc(8);
        uart_putc(32);
        uart_putc(8);
        DolDocBackspace();
    } else if (c == 9) { // '\t'
        DolDocPutc(' ');
        DolDocPutc(' ');
        DolDocPutc(' ');
        DolDocPutc(' ');
    } else {
        uart_putc(c);
        if (g_doc_cur_row < g_doc_rows && g_doc_cur_col < g_doc_cols) {
            I64 idx = g_doc_cur_row * DOLDOC_MAX_COLS + g_doc_cur_col;
            g_doc_chars[idx] = c;
            g_doc_fg[idx] = g_doc_cur_fg;
            g_doc_bg[idx] = g_doc_cur_bg;
            g_doc_link_idx[idx] = -1;

            DolDocMarkRowDirty(g_doc_cur_row);
            gfx_draw_char(g_doc_x + 8 + g_doc_cur_col * 8, g_doc_y + 8 + g_doc_cur_row * 18,
                          c, g_doc_cur_fg, g_doc_cur_bg);
            g_doc_cur_col++;
            if (g_doc_cur_col >= g_doc_cols) {
                g_doc_cur_col = 0;
                g_doc_cur_row++;
                if (g_doc_cur_row >= g_doc_rows) {
                    DolDocScroll();
                }
            }
            g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
            g_doc_cursor_y = g_doc_y + 8 + g_doc_cur_row * 18;
        }
    }
}

U0 DolDocPrint(U8 *str) {
    if (!str) return;
    U8 *tp = 0;
    U8 *ap = 0;
    U8 *lmp = 0;
    U8 *vp = 0;
    U8 *mp = 0;

    while (*str) {
        if (*str == '$') {
            str++;
            if (*str == '$') {
                DolDocPutc('$');
                str++;
                continue;
            }

            // Parse tag
            I64 tlen = 0;
            while (*str && *str != '$' && tlen < 127) {
                g_tag_buf[tlen] = *str;
                tlen++;
                str++;
            }
            g_tag_buf[tlen] = 0;
            if (*str == '$') str++;

            // Tag 1: Color tags
            if (strcmp(g_tag_buf, "FG,RED") == 0) {
                g_doc_cur_fg = COLOR_RED;
            } else if (strcmp(g_tag_buf, "FG,GREEN") == 0) {
                g_doc_cur_fg = COLOR_GREEN;
            } else if (strcmp(g_tag_buf, "FG,BLUE") == 0) {
                g_doc_cur_fg = COLOR_BLUE;
            } else if (strcmp(g_tag_buf, "FG,CYAN") == 0) {
                g_doc_cur_fg = COLOR_SKY;
            } else if (strcmp(g_tag_buf, "FG,YELLOW") == 0) {
                g_doc_cur_fg = COLOR_YELLOW;
            } else if (strcmp(g_tag_buf, "FG,WHITE") == 0) {
                g_doc_cur_fg = COLOR_TEXT;
            } else if (strcmp(g_tag_buf, "FG,MUTED") == 0) {
                g_doc_cur_fg = COLOR_OVERLAY0;
            } else if (strcmp(g_tag_buf, "FG,MAUVE") == 0) {
                g_doc_cur_fg = COLOR_MAUVE;
            } else if (strcmp(g_tag_buf, "FG,PEACH") == 0) {
                g_doc_cur_fg = COLOR_PEACH;
            } else if (strcmp(g_tag_buf, "FG,TEAL") == 0) {
                g_doc_cur_fg = COLOR_TEAL;
            } else if (strcmp(g_tag_buf, "FG,SAPPHIRE") == 0) {
                g_doc_cur_fg = COLOR_SAPPHIRE;
            } else if (strcmp(g_tag_buf, "FG,PINK") == 0) {
                g_doc_cur_fg = COLOR_PINK;
            } else if (strcmp(g_tag_buf, "FG,DEFAULT") == 0 || strcmp(g_tag_buf, "FG") == 0) {
                g_doc_cur_fg = COLOR_TEXT;
            } else if (strcmp(g_tag_buf, "BG,BLACK") == 0) {
                g_doc_cur_bg = COLOR_CRUST;
            } else if (strcmp(g_tag_buf, "BG,DARK") == 0) {
                g_doc_cur_bg = COLOR_MANTLE;
            } else if (strcmp(g_tag_buf, "BG,WINDOW") == 0) {
                g_doc_cur_bg = COLOR_BASE;
            } else if (strcmp(g_tag_buf, "BG,SURFACE") == 0) {
                g_doc_cur_bg = COLOR_SURFACE0;
            } else if (strcmp(g_tag_buf, "BG,DEFAULT") == 0 || strcmp(g_tag_buf, "BG") == 0) {
                g_doc_cur_bg = COLOR_MANTLE;
            }
            // Tag 2: Hyperlinks: $LK,"Label",A="command"$
            else if (strncmp(g_tag_buf, "LK,", 3) == 0) {
                g_tag_label[0] = 0; g_tag_cmd[0] = 0;
                tp = g_tag_buf + 3;
                tp = DolDocParseQuoted(tp, g_tag_label, 64);
                ap = strstr(tp, "A=");
                if (ap) DolDocParseQuoted(ap + 2, g_tag_cmd, 64);

                I64 link_len = strlen(g_tag_label) + 2;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + link_len >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_LINK;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + link_len;
                    g_widget_state[wid] = 0;
                    strcpy(g_widget_label + wid * 48, g_tag_label);
                    strcpy(g_widget_cmd + wid * 64, g_tag_cmd);
                    g_widget_count++;
                }

                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = COLOR_SKY;
                DolDocPutc('[');
                for (I64 i = 0; g_tag_label[i]; i++) {
                    DolDocPutc(g_tag_label[i]);
                    I64 c_idx = g_doc_cur_row * DOLDOC_MAX_COLS + (g_doc_cur_col - 1);
                    if (c_idx >= 0 && c_idx < DOLDOC_CELLS) g_doc_link_idx[c_idx] = wid;
                }
                DolDocPutc(']');
                g_doc_cur_fg = old_fg;
            }
            // Tag 3: Buttons: $BT,"Label",LM="command"$
            else if (strncmp(g_tag_buf, "BT,", 3) == 0) {
                g_tag_label[0] = 0; g_tag_cmd[0] = 0;
                tp = g_tag_buf + 3;
                tp = DolDocParseQuoted(tp, g_tag_label, 48);
                lmp = strstr(tp, "LM=");
                if (lmp) DolDocParseQuoted(lmp + 3, g_tag_cmd, 64);

                I64 btn_len = strlen(g_tag_label) + 4;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + btn_len >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_BUTTON;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + btn_len;
                    g_widget_state[wid] = 0;
                    strcpy(g_widget_label + wid * 48, g_tag_label);
                    strcpy(g_widget_cmd + wid * 64, g_tag_cmd);
                    g_widget_count++;
                }

                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = COLOR_YELLOW;
                DolDocPutc('<');
                DolDocPutc(' ');
                g_doc_cur_fg = COLOR_TEXT;
                for (I64 i = 0; g_tag_label[i]; i++) {
                    DolDocPutc(g_tag_label[i]);
                    I64 c_idx = g_doc_cur_row * DOLDOC_MAX_COLS + (g_doc_cur_col - 1);
                    if (c_idx >= 0 && c_idx < DOLDOC_CELLS) g_doc_link_idx[c_idx] = wid;
                }
                g_doc_cur_fg = COLOR_YELLOW;
                DolDocPutc(' ');
                DolDocPutc('>');
                g_doc_cur_fg = old_fg;
            }
            // Tag 4: Progress Bar: $PB,VAL=x,MAX=y$
            else if (strncmp(g_tag_buf, "PB,", 3) == 0) {
                I64 val = 0;
                I64 max_val = 100;
                vp = strstr(g_tag_buf, "VAL=");
                if (vp) val = DolDocAtoi(vp + 4);
                mp = strstr(g_tag_buf, "MAX=");
                if (mp) max_val = DolDocAtoi(mp + 4);
                if (max_val <= 0) max_val = 100;
                if (val < 0) val = 0;
                if (val > max_val) val = max_val;

                I64 bar_width = 20;
                I64 filled = (val * bar_width) / max_val;
                I64 pb_len = bar_width + 8;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + pb_len >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = COLOR_OVERLAY0;
                DolDocPutc('[');
                g_doc_cur_fg = COLOR_SKY;
                for (I64 i = 0; i < filled; i++) DolDocPutc('=');
                if (filled < bar_width) {
                    DolDocPutc('>');
                    g_doc_cur_fg = COLOR_OVERLAY0;
                    for (I64 i = filled + 1; i < bar_width; i++) DolDocPutc('-');
                }
                g_doc_cur_fg = COLOR_OVERLAY0;
                DolDocPutc(']');
                g_doc_cur_fg = COLOR_PEACH;
                DolDocPutc(' ');
                I64 pct = (val * 100) / max_val;
                if (pct >= 100) DolDocPutc('1');
                if (pct >= 10) DolDocPutc('0' + ((pct / 10) % 10));
                DolDocPutc('0' + (pct % 10));
                DolDocPutc('%');
                g_doc_cur_fg = old_fg;
            }
            // Tag 5: Checkbox: $CB,"Label",val$
            else if (strncmp(g_tag_buf, "CB,", 3) == 0) {
                g_tag_label[0] = 0;
                tp = g_tag_buf + 3;
                tp = DolDocParseQuoted(tp, g_tag_label, 48);
                I64 chk = 0;
                if (*tp == ',') {
                    tp++;
                    if (*tp == '1' || *tp == 't' || *tp == 'T') chk = 1;
                }

                I64 cb_len = strlen(g_tag_label) + 4;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + cb_len >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_CHECKBOX;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + cb_len;
                    g_widget_state[wid] = chk;
                    strcpy(g_widget_label + wid * 48, g_tag_label);
                    g_widget_cmd[wid * 64] = 0;
                    g_widget_count++;
                }

                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = COLOR_SKY;
                DolDocPutc('[');
                g_doc_cur_fg = chk ? COLOR_GREEN : COLOR_OVERLAY0;
                DolDocPutc(chk ? 'x' : ' ');
                g_doc_cur_fg = COLOR_SKY;
                DolDocPutc(']');
                DolDocPutc(' ');
                g_doc_cur_fg = COLOR_TEXT;
                for (I64 i = 0; g_tag_label[i]; i++) {
                    DolDocPutc(g_tag_label[i]);
                    I64 c_idx = g_doc_cur_row * DOLDOC_MAX_COLS + (g_doc_cur_col - 1);
                    if (c_idx >= 0 && c_idx < DOLDOC_CELLS) g_doc_link_idx[c_idx] = wid;
                }
                g_doc_cur_fg = old_fg;
            }
            // Tag 6: Collapsible Tree: $TR,"Title"$
            else if (strncmp(g_tag_buf, "TR,", 3) == 0) {
                g_tag_title[0] = 0;
                DolDocParseQuoted(g_tag_buf + 3, g_tag_title, 64);
                I64 tr_len = strlen(g_tag_title) + 4;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + tr_len >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_TREE;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + tr_len;
                    g_widget_state[wid] = 1; // Default expanded
                    strcpy(g_widget_label + wid * 48, g_tag_title);
                    g_widget_cmd[wid * 64] = 0;
                    g_widget_count++;
                }

                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = COLOR_SKY;
                DolDocPutc('[');
                g_doc_cur_fg = COLOR_YELLOW;
                DolDocPutc('-');
                g_doc_cur_fg = COLOR_SKY;
                DolDocPutc(']');
                DolDocPutc(' ');
                g_doc_cur_fg = COLOR_TEXT;
                for (I64 i = 0; g_tag_title[i]; i++) {
                    DolDocPutc(g_tag_title[i]);
                    I64 c_idx = g_doc_cur_row * DOLDOC_MAX_COLS + (g_doc_cur_col - 1);
                    if (c_idx >= 0 && c_idx < DOLDOC_CELLS) g_doc_link_idx[c_idx] = wid;
                }
                g_doc_cur_fg = old_fg;
            }
            // Tag 7: Horizontal Rule: $HR$
            else if (strcmp(g_tag_buf, "HR") == 0) {
                if (g_doc_cur_col > 0) DolDocPutc(10);
                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = COLOR_SURFACE1;
                for (I64 i = 0; i < g_doc_cols - 2; i++) DolDocPutc('-');
                DolDocPutc(10);
                g_doc_cur_fg = old_fg;
            }
            continue;
        }

        // Word-level flow wrapping
        if (*str != ' ' && *str != 10 && *str != 9 && *str != 13) {
            U8 *wp = str;
            I64 wlen = 0;
            while (*wp && *wp != ' ' && *wp != 10 && *wp != 9 && *wp != 13 && *wp != '$') {
                wlen++;
                wp++;
            }
            if (wlen > 0 && wlen < g_doc_cols && g_doc_cur_col > 0 && (g_doc_cur_col + wlen >= g_doc_cols)) {
                DolDocPutc(10);
            }
        }

        DolDocPutc(*str);
        str++;
    }
}

U0 DolDocRedraw() {
    if (g_doc_dirty_mask == 0) return;

    if (g_doc_dirty_mask == -1) {
        gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h, g_doc_cur_bg);
        gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, 1, COLOR_SURFACE0);
    }

    for (I64 r = 0; r < g_doc_rows; r++) {
        if (r < 64 && !(g_doc_dirty_mask & (1 << r))) continue;

        I64 rx = g_doc_x + 8;
        I64 ry = g_doc_y + 8 + r * 18;
        I64 rw = g_doc_w - 16;
        I64 rh = 18;

        gfx_draw_rect(rx, ry, rw, rh, g_doc_cur_bg);

        I64 row_base = r * DOLDOC_MAX_COLS;
        for (I64 c = 0; c < g_doc_cols; c++) {
            U8 ch = g_doc_chars[row_base + c];
            if (ch >= 32 && ch <= 126) {
                U32 fg = g_doc_fg[row_base + c];
                U32 bg = g_doc_bg[row_base + c];
                if (bg == 0) bg = g_doc_cur_bg;
                gfx_draw_char(rx + c * 8, ry, ch, fg, bg);
            }
        }
    }

    // Scrollbar Track & Thumb
    I64 bar_x = g_doc_x + g_doc_w - 8;
    I64 bar_y = g_doc_y + 4;
    I64 bar_h = g_doc_h - 8;
    gfx_draw_rect(bar_x, bar_y, 4, bar_h, COLOR_CRUST);

    I64 total_lines = g_doc_history_count + g_doc_rows;
    if (total_lines > g_doc_rows && g_doc_history_count > 0) {
        I64 thumb_h = (bar_h * g_doc_rows) / total_lines;
        if (thumb_h < 14) thumb_h = 14;
        I64 scroll_pos = g_doc_history_count - g_doc_scroll_offset;
        if (scroll_pos < 0) scroll_pos = 0;
        I64 thumb_y = bar_y + ((bar_h - thumb_h) * scroll_pos) / g_doc_history_count;
        gfx_draw_rect(bar_x - 1, thumb_y, 6, thumb_h, COLOR_SKY);
    }

    g_doc_dirty_mask = 0;
}

I64 DolDocHandleClick(I64 mx, I64 my) {
    if (mx < g_doc_x + 8 || my < g_doc_y + 8) return 0;
    I64 col = (mx - (g_doc_x + 8)) / 8;
    I64 row = (my - (g_doc_y + 8)) / 18;

    if (row >= 0 && row < g_doc_rows && col >= 0 && col < g_doc_cols) {
        I64 idx = row * DOLDOC_MAX_COLS + col;
        I64 wid = g_doc_link_idx[idx];
        if (wid >= 0 && wid < g_widget_count) {
            I64 w_type = g_widget_type[wid];
            if (w_type == WIDGET_CHECKBOX) {
                g_widget_state[wid] = 1 - g_widget_state[wid];
                I64 chk_col = g_widget_start_col[wid] + 1;
                I64 chk_idx = row * DOLDOC_MAX_COLS + chk_col;
                if (chk_idx >= 0 && chk_idx < DOLDOC_CELLS) {
                    g_doc_chars[chk_idx] = g_widget_state[wid] ? 'x' : ' ';
                    g_doc_fg[chk_idx] = g_widget_state[wid] ? COLOR_GREEN : COLOR_OVERLAY0;
                    DolDocMarkRowDirty(row);
                    DolDocRedraw();
                }
                return 1;
            } else if (w_type == WIDGET_TREE) {
                g_widget_state[wid] = 1 - g_widget_state[wid];
                I64 tr_col = g_widget_start_col[wid] + 1;
                I64 tr_idx = row * DOLDOC_MAX_COLS + tr_col;
                if (tr_idx >= 0 && tr_idx < DOLDOC_CELLS) {
                    g_doc_chars[tr_idx] = g_widget_state[wid] ? '-' : '+';
                    DolDocMarkRowDirty(row);
                    DolDocRedraw();
                }
                return 1;
            } else if (w_type == WIDGET_BUTTON || w_type == WIDGET_LINK) {
                U8 *cmd = g_widget_cmd + wid * 64;
                if (*cmd) {
                    strcpy(g_click_cmd_buf, cmd);
                    DolDocPrint("\n$FG,YELLOW$[CLICK]$FG$ $FG,CYAN$");
                    DolDocPrint(g_click_cmd_buf);
                    DolDocPrint("$FG$\n");
                    shell_run_command(g_click_cmd_buf);
                    return 1;
                }
            }
        }
    }
    return 0;
}

U0 DolDocMove(I64 x, I64 y, I64 w, I64 h) {
    g_doc_x = x;
    g_doc_y = y;
    g_doc_w = w;
    g_doc_h = h;
    g_doc_cols = (w > 16) ? (w - 16) / 8 : 80;
    g_doc_rows = (h > 16) ? (h - 16) / 18 : 24;
    if (g_doc_cols > DOLDOC_MAX_COLS) g_doc_cols = DOLDOC_MAX_COLS;
    if (g_doc_rows > DOLDOC_MAX_ROWS) g_doc_rows = DOLDOC_MAX_ROWS;
    if (g_doc_cur_row >= g_doc_rows) g_doc_cur_row = g_doc_rows - 1;
    if (g_doc_cur_col >= g_doc_cols) g_doc_cur_col = g_doc_cols - 1;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
    g_doc_cursor_y = g_doc_y + 8 + g_doc_cur_row * 18;
    DolDocMarkAllDirty();
    DolDocRedraw();
}

U0 DolDocScrollUp(I64 lines) {
    g_doc_scroll_offset += lines;
    if (g_doc_scroll_offset > g_doc_history_count) g_doc_scroll_offset = g_doc_history_count;
    DolDocMarkAllDirty();
    DolDocRedraw();
}

U0 DolDocScrollDown(I64 lines) {
    g_doc_scroll_offset -= lines;
    if (g_doc_scroll_offset < 0) g_doc_scroll_offset = 0;
    DolDocMarkAllDirty();
    DolDocRedraw();
}

U0 DolDocSetBgColor(U32 bg) {
    g_doc_cur_bg = bg;
    DolDocMarkAllDirty();
}

U32 DolDocGetBgColor() {
    return g_doc_cur_bg;
}

U0 DolDocInit() {
    DolDocClear();

    g_doldoc_ops.putc           = DolDocPutc;
    g_doldoc_ops.print          = DolDocPrint;
    g_doldoc_ops.clear          = DolDocClear;
    g_doldoc_ops.redraw         = DolDocRedraw;
    g_doldoc_ops.click          = DolDocHandleClick;
    g_doldoc_ops.move           = DolDocMove;
    g_doldoc_ops.scroll_up      = DolDocScrollUp;
    g_doldoc_ops.scroll_down    = DolDocScrollDown;
    g_doldoc_ops.backspace      = DolDocBackspace;
    g_doldoc_ops.draw_cursor    = DolDocDrawCursor;
    g_doldoc_ops.set_bg         = DolDocSetBgColor;
    g_doldoc_ops.get_bg         = DolDocGetBgColor;
    g_doldoc_ops.mark_all_dirty = DolDocMarkAllDirty;

    doldoc_register_holyc(&g_doldoc_ops);
    DolDocPrint("$FG,GREEN$[DOLDOC.HC]$FG$ Sovereign Pure HolyC DolDoc 2.0 Engine activated!\n");
}

DolDocInit();
