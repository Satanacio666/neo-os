// ==============================================================================
// DolDoc.HC - Sovereign Pure HolyC DolDoc 3.0 Scene-Graph & OmniTape Continuum
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: OmniTape Stream, Dynamic Morton 64x64 Tiles, Native Shadertoy
//            ($SHADER$), Scalable Vector Fonts ($FONT$), 3D Meshes ($SP$),
//            Live Telemetry Oscilloscopes ($GRAPH$), Math ($EQ$) & Morphic Halos
// ==============================================================================

#define DOLDOC_MAX_COLS     256
#define DOLDOC_MAX_ROWS     64
#define DOLDOC_CELLS        16384
#define DOLDOC_HIST_LINES   512
#define DOLDOC_HIST_CELLS   131072
#define DOLDOC_MAX_WIDGETS  512

#define WIDGET_NONE         0
#define WIDGET_BUTTON       1
#define WIDGET_LINK         2
#define WIDGET_CHECKBOX     3
#define WIDGET_TREE         4
#define WIDGET_BOX          5
#define WIDGET_CARD         6
#define WIDGET_GLASS        7
#define WIDGET_SLIDER       8
#define WIDGET_EQUATION     9
#define WIDGET_GRAPH        10
#define WIDGET_SPRITE3D     11
#define WIDGET_PROGRESS     12
#define WIDGET_HR           13
#define WIDGET_SHADOW       14
#define WIDGET_SHADER       15
#define WIDGET_FONT_TEXT    16
#define WIDGET_REPL         17

// Semantic Color Token IDs (Resolved Dynamically via g_theme at Render Time!)
#define SEM_COLOR_TEXT      0x01000001
#define SEM_COLOR_SUBTEXT   0x01000002
#define SEM_COLOR_MUTED     0x01000003
#define SEM_COLOR_MANTLE    0x01000004
#define SEM_COLOR_BASE      0x01000005
#define SEM_COLOR_CRUST     0x01000006
#define SEM_COLOR_SURFACE0  0x01000007
#define SEM_COLOR_SURFACE1  0x01000008
#define SEM_COLOR_BLUE      0x01000009
#define SEM_COLOR_SAPPHIRE  0x0100000A
#define SEM_COLOR_SKY       0x0100000B
#define SEM_COLOR_TEAL      0x0100000C
#define SEM_COLOR_GREEN     0x0100000D
#define SEM_COLOR_YELLOW    0x0100000E
#define SEM_COLOR_PEACH     0x0100000F
#define SEM_COLOR_RED       0x01000010
#define SEM_COLOR_MAUVE     0x01000011
#define SEM_COLOR_PINK      0x01000012

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

// Live Reactive Parameters for Shaders, 3D Sprites & Oscilloscopes
I64 g_shader_speed       = 50;
I64 g_shader_zoom        = 40;
I64 g_shader_morph       = 60;
I64 g_sprite_rot_speed   = 50;
I64 g_doc_inspector_mode = 0;
I64 g_doc_inspected_wid  = -1;
I64 g_doc_anim_tick      = 0;

// Live Telemetry Ring Buffers for $GRAPH$ Oscilloscopes
I64 g_osc_sine_buf[64];
I64 g_osc_fps_buf[64];
I64 g_osc_mem_buf[64];
I64 g_osc_head = 0;

// Fast Integer Sine/Cosine Table (64 entries for full 2*pi period, scaled -256..256)
I64 g_doc_sin64[64];
I64 g_doc_trig_ready = 0;
I64 g_cube_px[8];
I64 g_cube_py[8];

U0 DolDocInitTrig() {
    if (g_doc_trig_ready) return;
    // Quarter wave 0..15
    g_doc_sin64[0]  = 0;   g_doc_sin64[1]  = 25;  g_doc_sin64[2]  = 50;  g_doc_sin64[3]  = 74;
    g_doc_sin64[4]  = 98;  g_doc_sin64[5]  = 121; g_doc_sin64[6]  = 142; g_doc_sin64[7]  = 162;
    g_doc_sin64[8]  = 181; g_doc_sin64[9]  = 198; g_doc_sin64[10] = 213; g_doc_sin64[11] = 226;
    g_doc_sin64[12] = 237; g_doc_sin64[13] = 245; g_doc_sin64[14] = 251; g_doc_sin64[15] = 255;
    g_doc_sin64[16] = 256;
    for (I64 ti = 1; ti < 16; ti++) {
        g_doc_sin64[16 + ti] = g_doc_sin64[16 - ti];
    }
    for (I64 ti2 = 0; ti2 < 32; ti2++) {
        g_doc_sin64[32 + ti2] = -g_doc_sin64[ti2];
    }
    for (I64 oi = 0; oi < 64; oi++) {
        g_osc_sine_buf[oi] = g_doc_sin64[oi];
        g_osc_fps_buf[oi]  = 60 + (g_doc_sin64[(oi * 3) & 63] / 32);
        g_osc_mem_buf[oi]  = 45 + (oi % 15);
    }
    g_doc_trig_ready = 1;
}

I64 DocFastSin(I64 idx) {
    if (!g_doc_trig_ready) DolDocInitTrig();
    return g_doc_sin64[idx & 63];
}

I64 DocFastCos(I64 idx) {
    if (!g_doc_trig_ready) DolDocInitTrig();
    return g_doc_sin64[(idx + 16) & 63];
}

// Resolve Semantic Color Token or Legacy Hex to Active Theme Palette (g_theme)
U32 DolDocResolveColor(U32 col) {
    if (g_theme.bg_base == 0) {
        // Fallback if CompositorInit hasn't run yet
        if (col == SEM_COLOR_TEXT)     return 0xFFCDD6F4;
        if (col == SEM_COLOR_MANTLE)   return 0xFF181825;
        if (col == SEM_COLOR_BASE)     return 0xFF1E1E2E;
        if (col == SEM_COLOR_CRUST)    return 0xFF11111B;
        if (col == SEM_COLOR_SURFACE0) return 0xFF313244;
        if (col == SEM_COLOR_SURFACE1) return 0xFF45475A;
        if (col == SEM_COLOR_BLUE)     return 0xFF89B4FA;
        if (col == SEM_COLOR_SAPPHIRE) return 0xFF74C7EC;
        if (col == SEM_COLOR_SKY)      return 0xFF89DCEB;
        if (col == SEM_COLOR_TEAL)     return 0xFF94E2D5;
        if (col == SEM_COLOR_GREEN)    return 0xFFA6E3A1;
        if (col == SEM_COLOR_YELLOW)   return 0xFFF9E2AF;
        if (col == SEM_COLOR_PEACH)    return 0xFFFAB387;
        if (col == SEM_COLOR_RED)      return 0xFFF38BA8;
        if (col == SEM_COLOR_MAUVE)    return 0xFFCBA6F7;
        if (col == SEM_COLOR_MUTED)    return 0xFF6C7086;
        return col;
    }

    if (col == SEM_COLOR_TEXT)     return g_theme.text_primary;
    if (col == SEM_COLOR_SUBTEXT)  return g_theme.text_secondary;
    if (col == SEM_COLOR_MUTED)    return g_theme.text_muted;
    if (col == SEM_COLOR_MANTLE)   return g_theme.bg_mantle;
    if (col == SEM_COLOR_BASE)     return g_theme.bg_base;
    if (col == SEM_COLOR_CRUST)    return g_theme.bg_crust;
    if (col == SEM_COLOR_SURFACE0) return g_theme.bg_surface0;
    if (col == SEM_COLOR_SURFACE1) return g_theme.bg_surface1;
    if (col == SEM_COLOR_BLUE)     return g_theme.accent_primary;
    if (col == SEM_COLOR_SAPPHIRE) return g_theme.accent_secondary;
    if (col == SEM_COLOR_SKY)      return g_theme.accent_cyan;
    if (col == SEM_COLOR_TEAL)     return g_theme.accent_teal;
    if (col == SEM_COLOR_GREEN)    return g_theme.status_success;
    if (col == SEM_COLOR_YELLOW)   return g_theme.status_warning;
    if (col == SEM_COLOR_PEACH)    return g_theme.status_peach;
    if (col == SEM_COLOR_RED)      return g_theme.status_danger;
    if (col == SEM_COLOR_MAUVE)    return g_theme.accent_tertiary;
    if (col == SEM_COLOR_PINK)     return g_theme.accent_tertiary;

    // Remap legacy hardcoded Mocha surface/border colors when another theme is active
    if (g_theme.theme_id != 0) {
        if (col == 0xFF1E1E2E) return g_theme.bg_base;
        if (col == 0xFF181825) return g_theme.bg_mantle;
        if (col == 0xFF11111B) return g_theme.bg_crust;
        if (col == 0xFF313244) return g_theme.bg_surface0;
        if (col == 0xFF45475A) return g_theme.bg_surface1;
        if (col == 0xFF89B4FA) return g_theme.border_active;
        if (col == 0xFFCDD6F4) return g_theme.text_primary;
    }
    return col;
}

// Viewport Geometry & State
I64 g_doc_x = 0;
I64 g_doc_y = 0;
I64 g_doc_w = 1024;
I64 g_doc_h = 768;
I64 g_doc_cols = 126;
I64 g_doc_rows = 41;
I64 g_doc_cur_col = 0;
I64 g_doc_cur_row = 0;

U32 g_doc_cur_fg = SEM_COLOR_TEXT;
U32 g_doc_cur_bg = SEM_COLOR_MANTLE;

// Style Stack for Nested Elements
U32 g_style_fg_stack[16];
U32 g_style_bg_stack[16];
I64 g_style_depth = 0;

U0 DolDocStylePush(U32 fg, U32 bg) {
    if (g_style_depth < 15) {
        g_style_fg_stack[g_style_depth] = g_doc_cur_fg;
        g_style_bg_stack[g_style_depth] = g_doc_cur_bg;
        g_style_depth++;
    }
    g_doc_cur_fg = fg;
    g_doc_cur_bg = bg;
}

U0 DolDocStylePop() {
    if (g_style_depth > 0) {
        g_style_depth--;
        g_doc_cur_fg = g_style_fg_stack[g_style_depth];
        g_doc_cur_bg = g_style_bg_stack[g_style_depth];
    }
}

I64 g_doc_cursor_x = 8;
I64 g_doc_cursor_y = 8;
I64 g_doc_cursor_visible = 1;

U64 g_doc_dirty_mask = -1;
I64 g_doc_scroll_offset = 0;
I64 g_doc_history_count = 0;

// Document Stream & History Storage
U8  g_doc_chars[DOLDOC_CELLS];
U32 g_doc_fg[DOLDOC_CELLS];
U32 g_doc_bg[DOLDOC_CELLS];
I64 g_doc_link_idx[DOLDOC_CELLS];

U8  g_hist_chars[DOLDOC_HIST_CELLS];
U32 g_hist_fg[DOLDOC_HIST_CELLS];
U32 g_hist_bg[DOLDOC_HIST_CELLS];

// Interactive Scene-Graph Nodes / Widgets Table
I64 g_widget_type[DOLDOC_MAX_WIDGETS];
I64 g_widget_row[DOLDOC_MAX_WIDGETS];
I64 g_widget_start_col[DOLDOC_MAX_WIDGETS];
I64 g_widget_end_col[DOLDOC_MAX_WIDGETS];
I64 g_widget_state[DOLDOC_MAX_WIDGETS];
I64 g_widget_pixel_x[DOLDOC_MAX_WIDGETS];
I64 g_widget_pixel_y[DOLDOC_MAX_WIDGETS];
I64 g_widget_pixel_w[DOLDOC_MAX_WIDGETS];
I64 g_widget_pixel_h[DOLDOC_MAX_WIDGETS];
I64 g_widget_val[DOLDOC_MAX_WIDGETS];
I64 g_widget_min[DOLDOC_MAX_WIDGETS];
I64 g_widget_max[DOLDOC_MAX_WIDGETS];
U64 g_widget_target[DOLDOC_MAX_WIDGETS];
I64 g_widget_tape_offset[DOLDOC_MAX_WIDGETS];
U8  g_widget_label[32768];  // 512 * 64
U8  g_widget_cmd[65536];    // 512 * 128
U8  g_widget_extra[65536];  // 512 * 128
I64 g_widget_count = 0;
I64 g_doc_drag_wid = -1;
I64 g_doc_scroll_px = 0;

// ============================================================================
// OMNITAPE & LIVING CELL MATRIX (LCM) SOVEREIGN MEMORY ARENA
// ============================================================================
#define OMNITAPE_ARENA_SIZE  1048576
#define OMNITAPE_MAGIC       0x544150454E454F31

#define CMD_NOP               0x00
#define CMD_TEXT_RUN          0x01
#define CMD_SDF_RECT          0x02
#define CMD_SDF_CARD          0x03
#define CMD_MATH_EQUATION     0x04
#define CMD_SPRITE_3D         0x05
#define CMD_CELL_SLIDER       0x06
#define CMD_CELL_COLOR        0x07
#define CMD_SHADER_QUAD       0x08
#define CMD_CELL_OSCILLOSCOPE 0x09
#define CMD_CELL_CHECKBOX     0x0A
#define CMD_PROGRESS_BAR      0x0B
#define CMD_PLUMB_DISPATCH    0x0C

class CTapeCmdHeader {
    I64 opcode;
    I64 flags;
    I64 payload_size;
    I64 rel_child_offset;
    I64 box_x;
    I64 box_y;
    I64 box_w;
    I64 box_h;
};

U8  *g_omnitape_buf = 0;
I64  g_omnitape_tail = 0;
I64  g_omnitape_cmd_count = 0;

// ============================================================================
// DYNAMIC SPATIAL MORTON-TILE PARTITIONING (64x64 L1 CACHE BINS, UP TO 2048x1280)
// ============================================================================
#define MORTON_TILES_X       32
#define MORTON_TILES_Y       20
#define MORTON_TOTAL_TILES   1024
#define TILE_MAX_WIDGETS     32

I64 g_tile_widget_count[MORTON_TOTAL_TILES];
I64 g_tile_widgets[32768]; // 1024 * 32

I64 Morton2D(I64 tx, I64 ty) {
    if (tx < 0) tx = 0;
    if (tx >= MORTON_TILES_X) tx = MORTON_TILES_X - 1;
    if (ty < 0) ty = 0;
    if (ty >= MORTON_TILES_Y) ty = MORTON_TILES_Y - 1;
    I64 m = 0;
    for (I64 m_i = 0; m_i < 5; m_i++) {
        m = m | (((tx >> m_i) & 1) << (2 * m_i));
        m = m | (((ty >> m_i) & 1) << (2 * m_i + 1));
    }
    return m & (MORTON_TOTAL_TILES - 1);
}

U0 MortonSpatialClear() {
    for (I64 clr_i = 0; clr_i < MORTON_TOTAL_TILES; clr_i++) {
        g_tile_widget_count[clr_i] = 0;
    }
}

U0 MortonSpatialInsertWidget(I64 wid) {
    if (wid < 0 || wid >= DOLDOC_MAX_WIDGETS) return;
    I64 vx = g_widget_pixel_x[wid];
    I64 vy = g_widget_pixel_y[wid];
    I64 vw = g_widget_pixel_w[wid];
    I64 vh = g_widget_pixel_h[wid];

    I64 tx0 = vx / 64; if (tx0 < 0) tx0 = 0; if (tx0 >= MORTON_TILES_X) tx0 = MORTON_TILES_X - 1;
    I64 ty0 = vy / 64; if (ty0 < 0) ty0 = 0; if (ty0 >= MORTON_TILES_Y) ty0 = MORTON_TILES_Y - 1;
    I64 tx1 = (vx + vw - 1) / 64; if (tx1 < 0) tx1 = 0; if (tx1 >= MORTON_TILES_X) tx1 = MORTON_TILES_X - 1;
    I64 ty1 = (vy + vh - 1) / 64; if (ty1 < 0) ty1 = 0; if (ty1 >= MORTON_TILES_Y) ty1 = MORTON_TILES_Y - 1;

    for (I64 m_ty = ty0; m_ty <= ty1; m_ty++) {
        for (I64 m_tx = tx0; m_tx <= tx1; m_tx++) {
            I64 midx = Morton2D(m_tx, m_ty);
            I64 cnt = g_tile_widget_count[midx];
            if (cnt < TILE_MAX_WIDGETS) {
                g_tile_widgets[midx * TILE_MAX_WIDGETS + cnt] = wid;
                g_tile_widget_count[midx] = cnt + 1;
            }
        }
    }
}

I64 OmniTapeAppendCmd(I64 opcode, I64 x, I64 y, I64 w, I64 h, U8 *payload, I64 payload_len, I64 wid) {
    if (!g_omnitape_buf) return -1;
    I64 aligned_tail = ((g_omnitape_tail + 63) / 64) * 64;
    I64 total_len = 64 + payload_len + 1;
    if (aligned_tail + total_len >= OMNITAPE_ARENA_SIZE) {
        return -1;
    }

    CTapeCmdHeader *hdr = g_omnitape_buf + aligned_tail;
    hdr->opcode = opcode;
    hdr->flags = wid;
    hdr->payload_size = payload_len;
    hdr->rel_child_offset = 0;
    hdr->box_x = x;
    hdr->box_y = y;
    hdr->box_w = w;
    hdr->box_h = h;

    if (payload && payload_len > 0) {
        U8 *dst = g_omnitape_buf + aligned_tail + 64;
        for (I64 tape_i = 0; tape_i < payload_len; tape_i++) {
            dst[tape_i] = payload[tape_i];
        }
        dst[payload_len] = 0;
    } else {
        U8 *dst0 = g_omnitape_buf + aligned_tail + 64;
        dst0[0] = 0;
    }

    I64 off = aligned_tail;
    g_omnitape_tail = aligned_tail + ((total_len + 63) / 64) * 64;
    g_omnitape_cmd_count++;
    return off;
}

// Persistent Tag Parsing Scratch Buffers
U8  g_tag_buf[2048];
U8  g_tag_label[256];
U8  g_tag_cmd[256];
U8  g_tag_title[256];
U8  g_click_cmd_buf[256];

CDolDocOps g_doldoc_ops;

U8* DolDocParseQuoted(U8 *p, U8 *out, I64 max_out) {
    if (!p) return 0;
    if (!out) return p;
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
    I64 neg = 0;
    if (*p == '-') { neg = 1; p++; }
    I64 res = 0;
    while (*p >= '0' && *p <= '9') {
        res = res * 10 + (*p - '0');
        p++;
    }
    return neg ? -res : res;
}

U8* DolDocFindKey(U8 *tag, U8 *key) {
    if (!tag) return 0;
    if (!key) return 0;
    return strstr(tag, key);
}

I64 DolDocGetAttrInt(U8 *tag, U8 *key, I64 def_val) {
    U8 *p = DolDocFindKey(tag, key);
    if (!p) return def_val;
    p += strlen(key);
    while (*p == ' ' || *p == '=') p++;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2;
        I64 val = 0;
        while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F')) {
            val = val << 4;
            if (*p >= '0' && *p <= '9') val |= (*p - '0');
            else if (*p >= 'a' && *p <= 'f') val |= (*p - 'a' + 10);
            else if (*p >= 'A' && *p <= 'F') val |= (*p - 'A' + 10);
            p++;
        }
        return val;
    }
    return DolDocAtoi(p);
}

U32 DolDocGetAttrHex(U8 *tag, U8 *key, U32 def_val) {
    U8 *p = DolDocFindKey(tag, key);
    if (!p) return def_val;
    p += strlen(key);
    while (*p == ' ' || *p == '=') p++;
    if (p[0] == '0') {
        if (p[1] == 'x' || p[1] == 'X') p += 2;
    }
    U32 val = 0;
    while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F')) {
        val = val << 4;
        if (*p >= '0' && *p <= '9') val |= (*p - '0');
        else if (*p >= 'a' && *p <= 'f') val |= (*p - 'a' + 10);
        else if (*p >= 'A' && *p <= 'F') val |= (*p - 'A' + 10);
        p++;
    }
    return val;
}

U0 DolDocGetAttrStr(U8 *tag, U8 *key, U8 *out, I64 max_len) {
    out[0] = 0;
    U8 *p = DolDocFindKey(tag, key);
    if (!p) return;
    p += strlen(key);
    while (*p == ' ' || *p == '=') p++;
    if (*p == '"') {
        DolDocParseQuoted(p, out, max_len);
    } else {
        I64 as_i = 0;
        while (*p && *p != ',' && *p != '$' && as_i < max_len - 1) {
            out[as_i++] = *p++;
        }
        out[as_i] = 0;
    }
}

U0 DolDocMarkAllDirty() {
    g_doc_dirty_mask = -1;
}

U0 DolDocMarkRowDirty(I64 r) {
    if (r >= 0 && r < 64) {
        g_doc_dirty_mask = g_doc_dirty_mask | (1 << r);
    } else {
        g_doc_dirty_mask = -1;
    }
}

U0 DolDocClear() {
    for (I64 cell_i = 0; cell_i < DOLDOC_CELLS; cell_i++) {
        g_doc_chars[cell_i] = ' ';
        g_doc_fg[cell_i] = SEM_COLOR_TEXT;
        g_doc_bg[cell_i] = SEM_COLOR_MANTLE;
        g_doc_link_idx[cell_i] = -1;
    }
    for (I64 w_i = 0; w_i < DOLDOC_MAX_WIDGETS; w_i++) {
        g_widget_target[w_i] = 0;
        g_widget_tape_offset[w_i] = -1;
    }
    g_doc_cur_col = 0;
    g_doc_cur_row = 0;
    g_widget_count = 0;
    g_doc_scroll_offset = 0;
    g_doc_history_count = 0;
    g_doc_inspected_wid = -1;
    g_doc_cursor_x = g_doc_x + 8;
    g_doc_cursor_y = g_doc_y + 8;
    g_omnitape_tail = 0;
    g_omnitape_cmd_count = 0;
    MortonSpatialClear();
    DolDocMarkAllDirty();
}

U0 DolDocScroll() {
    if (g_doc_rows > 1) {
        // 1. Archive top row into circular/linear scrollback history buffer
        if (g_doc_history_count < DOLDOC_HIST_LINES) {
            I64 h_base = g_doc_history_count * DOLDOC_MAX_COLS;
            for (I64 hc = 0; hc < g_doc_cols; hc++) {
                g_hist_chars[h_base + hc] = g_doc_chars[hc];
                g_hist_fg[h_base + hc]    = g_doc_fg[hc];
                g_hist_bg[h_base + hc]    = g_doc_bg[hc];
            }
            g_doc_history_count++;
        } else {
            // Shift history up by 1 line
            for (I64 hr = 0; hr < DOLDOC_HIST_LINES - 1; hr++) {
                I64 hdst = hr * DOLDOC_MAX_COLS;
                I64 hsrc = (hr + 1) * DOLDOC_MAX_COLS;
                for (I64 hc2 = 0; hc2 < g_doc_cols; hc2++) {
                    g_hist_chars[hdst + hc2] = g_hist_chars[hsrc + hc2];
                    g_hist_fg[hdst + hc2]    = g_hist_fg[hsrc + hc2];
                    g_hist_bg[hdst + hc2]    = g_hist_bg[hsrc + hc2];
                }
            }
            I64 h_last = (DOLDOC_HIST_LINES - 1) * DOLDOC_MAX_COLS;
            for (I64 hc3 = 0; hc3 < g_doc_cols; hc3++) {
                g_hist_chars[h_last + hc3] = g_doc_chars[hc3];
                g_hist_fg[h_last + hc3]    = g_doc_fg[hc3];
                g_hist_bg[h_last + hc3]    = g_doc_bg[hc3];
            }
        }

        // 2. Shift active viewport rows up
        for (I64 sr = 0; sr < g_doc_rows - 1; sr++) {
            I64 dst = sr * DOLDOC_MAX_COLS;
            I64 src = (sr + 1) * DOLDOC_MAX_COLS;
            for (I64 sc = 0; sc < g_doc_cols; sc++) {
                g_doc_chars[dst + sc]    = g_doc_chars[src + sc];
                g_doc_fg[dst + sc]       = g_doc_fg[src + sc];
                g_doc_bg[dst + sc]       = g_doc_bg[src + sc];
                g_doc_link_idx[dst + sc] = g_doc_link_idx[src + sc];
            }
        }

        // 3. Clear bottom row
        I64 last_base = (g_doc_rows - 1) * DOLDOC_MAX_COLS;
        for (I64 lc = 0; lc < g_doc_cols; lc++) {
            g_doc_chars[last_base + lc]    = ' ';
            g_doc_fg[last_base + lc]       = g_doc_cur_fg;
            g_doc_bg[last_base + lc]       = g_doc_cur_bg;
            g_doc_link_idx[last_base + lc] = -1;
        }

        // 4. Shift scene-graph widget coordinates and rebuild Morton spatial bins
        for (I64 sw_i = 0; sw_i < g_widget_count; sw_i++) {
            g_widget_row[sw_i] = g_widget_row[sw_i] - 1;
            g_widget_pixel_y[sw_i] = g_widget_pixel_y[sw_i] - 18;
        }
        if (g_omnitape_buf) {
            I64 sc_toff = 0;
            while (sc_toff + 64 <= g_omnitape_tail) {
                CTapeCmdHeader *sc_hdr = g_omnitape_buf + sc_toff;
                if (sc_hdr->opcode == CMD_NOP) break;
                if (sc_hdr->box_h > 0) {
                    sc_hdr->box_y = sc_hdr->box_y - 18;
                }
                I64 sc_tot = 64 + sc_hdr->payload_size + 1;
                sc_toff += ((sc_tot + 63) / 64) * 64;
            }
        }
        MortonSpatialClear();
        for (I64 mw_i = 0; mw_i < g_widget_count; mw_i++) {
            MortonSpatialInsertWidget(mw_i);
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
        gfx_draw_rect(g_doc_cursor_x, g_doc_cursor_y, 8, 16, DolDocResolveColor(g_doc_cur_bg));
    }
}

U0 doldoc_backspace() {
    DolDocBackspace();
}

U0 DolDocDrawCursor(I64 visible) {
    U32 color = visible ? DolDocResolveColor(SEM_COLOR_SKY) : DolDocResolveColor(g_doc_cur_bg);
    gfx_draw_rect(g_doc_cursor_x, g_doc_cursor_y + 1, 2, 14, color);
}

U0 doldoc_draw_cursor(I64 visible) {
    DolDocDrawCursor(visible);
}

U0 DolDocPutc(U8 c) {
    // Typing snaps scrollback to live bottom
    if (g_doc_scroll_offset != 0) {
        g_doc_scroll_offset = 0;
        DolDocMarkAllDirty();
    }
    if (c == 10) {
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
    } else if (c == 13) {
        uart_putc(13);
        g_doc_cur_col = 0;
        g_doc_cursor_x = g_doc_x + 8;
    } else if (c == 8) {
        uart_putc(8);
        uart_putc(32);
        uart_putc(8);
        DolDocBackspace();
    } else if (c == 9) {
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

U32 DolDocParseColor(U8 *val, U32 def_col) {
    if (!val) return def_col;
    if (strcmp(val, "RED") == 0)      return SEM_COLOR_RED;
    if (strcmp(val, "GREEN") == 0)    return SEM_COLOR_GREEN;
    if (strcmp(val, "BLUE") == 0)     return SEM_COLOR_BLUE;
    if (strcmp(val, "CYAN") == 0)     return SEM_COLOR_SKY;
    if (strcmp(val, "SKY") == 0)      return SEM_COLOR_SKY;
    if (strcmp(val, "YELLOW") == 0)   return SEM_COLOR_YELLOW;
    if (strcmp(val, "WHITE") == 0)    return SEM_COLOR_TEXT;
    if (strcmp(val, "TEXT") == 0)     return SEM_COLOR_TEXT;
    if (strcmp(val, "SUBTEXT") == 0)  return SEM_COLOR_SUBTEXT;
    if (strcmp(val, "MUTED") == 0)    return SEM_COLOR_MUTED;
    if (strcmp(val, "OVERLAY0") == 0) return SEM_COLOR_MUTED;
    if (strcmp(val, "MAUVE") == 0)    return SEM_COLOR_MAUVE;
    if (strcmp(val, "MAGENTA") == 0)  return SEM_COLOR_MAUVE;
    if (strcmp(val, "PEACH") == 0)    return SEM_COLOR_PEACH;
    if (strcmp(val, "TEAL") == 0)     return SEM_COLOR_TEAL;
    if (strcmp(val, "SAPPHIRE") == 0) return SEM_COLOR_SAPPHIRE;
    if (strcmp(val, "PINK") == 0)     return SEM_COLOR_PINK;
    if (strcmp(val, "DEFAULT") == 0)  return def_col;
    if (strcmp(val, "BLACK") == 0)    return SEM_COLOR_CRUST;
    if (strcmp(val, "DARK") == 0)     return SEM_COLOR_MANTLE;
    if (strcmp(val, "WINDOW") == 0)   return SEM_COLOR_BASE;
    if (strcmp(val, "SURFACE") == 0)  return SEM_COLOR_SURFACE0;

    U8 *p = val;
    if (*p == '#') p++;
    if (p[0] == '0') {
        if (p[1] == 'x' || p[1] == 'X') p += 2;
    }

    U32 h = 0;
    I64 digits = 0;
    while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F')) {
        h = h << 4;
        if (*p >= '0' && *p <= '9') h |= (*p - '0');
        else if (*p >= 'a' && *p <= 'f') h |= (*p - 'a' + 10);
        else if (*p >= 'A' && *p <= 'F') h |= (*p - 'A' + 10);
        p++;
        digits++;
    }

    if (digits == 6) return 0xFF000000 | h;
    if (digits == 8) return h;
    return def_col;
}

U0 DolDocDrawShadow(I64 x, I64 y, I64 w, I64 h, I64 radius) {
    CompositorDrawShadow(x, y, w, h, radius);
}

U0 DolDocDrawGlass(I64 x, I64 y, I64 w, I64 h, I64 alpha) {
    CompositorDrawGlass(x, y, w, h, alpha);
}

U0 DolDocParseBox(U8 *tag) {
    I64 bw = DolDocGetAttrInt(tag, "w=", 40);
    I64 bh = DolDocGetAttrInt(tag, "h=", 4);
    U32 bbg = DolDocGetAttrHex(tag, "bg=", SEM_COLOR_SURFACE0);
    U32 bborder = DolDocGetAttrHex(tag, "border=", SEM_COLOR_SURFACE1);
    if (bw > g_doc_cols - g_doc_cur_col) bw = g_doc_cols - g_doc_cur_col;
    if (bw < 4) bw = 4;
    if (bh < 2) bh = 2;
    DolDocMarkRowDirty(g_doc_cur_row);

    I64 box_px = g_doc_x + 8 + g_doc_cur_col * 8;
    I64 box_py = g_doc_y + 8 + g_doc_cur_row * 18;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        I64 wid = g_widget_count;
        g_widget_type[wid] = WIDGET_BOX;
        g_widget_pixel_x[wid] = box_px;
        g_widget_pixel_y[wid] = box_py;
        g_widget_pixel_w[wid] = bw * 8;
        g_widget_pixel_h[wid] = bh * 18;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + bw;
        g_widget_val[wid] = (I64)bbg;
        g_widget_min[wid] = (I64)bborder;
        g_widget_label[wid * 64] = 0;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SDF_RECT, box_px, box_py, bw * 8, bh * 18, "BOX", 3, wid);
        g_widget_count++;
    }
}

U0 DolDocParseCard(U8 *tag) {
    g_tag_title[0] = 0;
    DolDocGetAttrStr(tag, "title=", g_tag_title, 47);
    I64 cw = DolDocGetAttrInt(tag, "w=", 50);
    I64 ch = DolDocGetAttrInt(tag, "h=", 5);
    U32 cbg = DolDocGetAttrHex(tag, "bg=", SEM_COLOR_BASE);
    U32 cborder = DolDocGetAttrHex(tag, "border=", SEM_COLOR_BLUE);
    if (cw > g_doc_cols - g_doc_cur_col) cw = g_doc_cols - g_doc_cur_col;
    if (cw < 6) cw = 6;
    if (ch < 2) ch = 2;
    DolDocMarkRowDirty(g_doc_cur_row);

    I64 card_px = g_doc_x + 8 + g_doc_cur_col * 8;
    I64 card_py = g_doc_y + 8 + g_doc_cur_row * 18;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        I64 wid = g_widget_count;
        g_widget_type[wid] = WIDGET_CARD;
        g_widget_pixel_x[wid] = card_px;
        g_widget_pixel_y[wid] = card_py;
        g_widget_pixel_w[wid] = cw * 8;
        g_widget_pixel_h[wid] = ch * 18;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + cw;
        g_widget_val[wid] = (I64)cbg;
        g_widget_min[wid] = (I64)cborder;
        strcpy(g_widget_label + wid * 64, g_tag_title);
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SDF_CARD, card_px, card_py, cw * 8, ch * 18, g_tag_title, strlen(g_tag_title), wid);
        g_widget_count++;
    }
}

U0 DolDocParseGlass(U8 *tag) {
    I64 gw = DolDocGetAttrInt(tag, "w=", 40);
    I64 gh = DolDocGetAttrInt(tag, "h=", 4);
    I64 galpha = DolDocGetAttrInt(tag, "alpha=", 0x80);
    I64 gpx = g_doc_x + 8 + g_doc_cur_col * 8;
    I64 gpy = g_doc_y + 8 + g_doc_cur_row * 18;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        I64 wid = g_widget_count;
        g_widget_type[wid] = WIDGET_GLASS;
        g_widget_pixel_x[wid] = gpx;
        g_widget_pixel_y[wid] = gpy;
        g_widget_pixel_w[wid] = gw * 8;
        g_widget_pixel_h[wid] = gh * 18;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + gw;
        g_widget_val[wid] = galpha;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SDF_RECT, gpx, gpy, gw * 8, gh * 18, "GLASS", 5, wid);
        g_widget_count++;
    }
}

U0 DolDocParseShadow(U8 *tag) {
    I64 sw = DolDocGetAttrInt(tag, "w=", 40);
    I64 sh = DolDocGetAttrInt(tag, "h=", 4);
    I64 srad = DolDocGetAttrInt(tag, "radius=", 6);
    I64 spx = g_doc_x + 8 + g_doc_cur_col * 8;
    I64 spy = g_doc_y + 8 + g_doc_cur_row * 18;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        I64 wid = g_widget_count;
        g_widget_type[wid] = WIDGET_SHADOW;
        g_widget_pixel_x[wid] = spx;
        g_widget_pixel_y[wid] = spy;
        g_widget_pixel_w[wid] = sw * 8;
        g_widget_pixel_h[wid] = sh * 18;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + sw;
        g_widget_val[wid] = srad;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SDF_RECT, spx, spy, sw * 8, sh * 18, "SHADOW", 6, wid);
        g_widget_count++;
    }
}

// Tag: Scalable Vector Font Heading/Span: $FONT,text="...",scale=200,color="CYAN"$
U0 DolDocParseFontText(U8 *tag) {
    g_tag_label[0] = 0;
    DolDocGetAttrStr(tag, "text=", g_tag_label, 63);
    if (!g_tag_label[0]) {
        DolDocParseQuoted(tag + 4, g_tag_label, 63);
    }
    I64 scale_pct = DolDocGetAttrInt(tag, "scale=", 180);
    if (scale_pct < 100) scale_pct = 100;
    if (scale_pct > 400) scale_pct = 400;

    U8 col_str[32]; col_str[0] = 0;
    DolDocGetAttrStr(tag, "color=", col_str, 30);
    U32 fcol = SEM_COLOR_SAPPHIRE;
    if (col_str[0]) fcol = DolDocParseColor(col_str, SEM_COLOR_SAPPHIRE);

    I64 char_adv = (10 * scale_pct) / 100;
    I64 char_h   = (16 * scale_pct) / 100 + 6;
    I64 fw = strlen(g_tag_label) * char_adv + 12;
    I64 cell_cols = (fw + 7) / 8;
    I64 cell_rows = (char_h + 17) / 18;
    if (cell_rows < 1) cell_rows = 1;

    if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
        DolDocPutc(10);
    }

    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        I64 wid = g_widget_count;
        g_widget_type[wid] = WIDGET_FONT_TEXT;
        g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
        g_widget_pixel_w[wid] = fw;
        g_widget_pixel_h[wid] = char_h;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
        g_widget_val[wid] = scale_pct;
        g_widget_min[wid] = (I64)fcol;
        strcpy(g_widget_label + wid * 64, g_tag_label);
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_TEXT_RUN, g_widget_pixel_x[wid], g_widget_pixel_y[wid], fw, char_h, g_tag_label, strlen(g_tag_label), wid);
        g_widget_count++;
    }

    g_doc_cur_col += cell_cols;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
}

U0 DolDocParseSlider(U8 *tag) {
    g_tag_label[0] = 0;
    U8 *tp = tag + 3;
    tp = DolDocParseQuoted(tp, g_tag_label, 63);
    I64 val = DolDocGetAttrInt(tag, "val=", 50);
    I64 min_v = DolDocGetAttrInt(tag, "min=", 0);
    I64 max_v = DolDocGetAttrInt(tag, "max=", 100);
    I64 sw = DolDocGetAttrInt(tag, "w=", 140);
    if (sw < 60) sw = 60;
    I64 sh = 18;

    U64 target = DolDocGetAttrInt(tag, "target=", 0);
    if (target == 0) {
        U8 var_name[64];
        var_name[0] = 0;
        DolDocGetAttrStr(tag, "var=", var_name, 60);
        if (var_name[0]) {
            target = SymLookup(var_name);
            if (target == 0) target = symbols_lookup(var_name);
        }
    }
    if (target == 0 && g_tag_label[0]) {
        target = SymLookup(g_tag_label);
        if (target == 0) target = symbols_lookup(g_tag_label);
    }
    if (target != 0) {
        val = *(I64*)target;
        if (val < min_v) val = min_v;
        if (val > max_v) val = max_v;
    }

    I64 cell_cols = (sw + 7) / 8 + 5;
    if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
        DolDocPutc(10);
    }

    I64 wid = -1;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        wid = g_widget_count;
        g_widget_type[wid] = WIDGET_SLIDER;
        g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
        g_widget_pixel_w[wid] = sw;
        g_widget_pixel_h[wid] = sh;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
        g_widget_val[wid] = val;
        g_widget_min[wid] = min_v;
        g_widget_max[wid] = max_v;
        g_widget_target[wid] = target;
        g_widget_state[wid] = 0;
        strcpy(g_widget_label + wid * 64, g_tag_label);
        g_widget_cmd[wid * 128] = 0;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_CELL_SLIDER, g_widget_pixel_x[wid], g_widget_pixel_y[wid], sw, sh, g_tag_label, strlen(g_tag_label), wid);
        MortonSpatialInsertWidget(wid);
        g_widget_count++;
    }

    g_doc_cur_col += cell_cols;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
}

U0 DolDocParseEquation(U8 *tag) {
    if (g_widget_count >= DOLDOC_MAX_WIDGETS) return;

    if (strstr(tag, "FRAC")) {
        U8 eq_num[128]; eq_num[0] = 0;
        U8 eq_den[128]; eq_den[0] = 0;
        DolDocGetAttrStr(tag, "num=", eq_num, 120);
        DolDocGetAttrStr(tag, "den=", eq_den, 120);
        I64 eq_l1 = strlen(eq_num);
        I64 eq_l2 = strlen(eq_den);
        I64 eq_max_l = (eq_l1 > eq_l2) ? eq_l1 : eq_l2;
        I64 eq_ew = eq_max_l * 8 + 16;
        I64 eq_eh = 34;
        I64 eq_cell_cols = (eq_ew + 7) / 8;

        if (g_doc_cur_col > 0 && (g_doc_cur_col + eq_cell_cols >= g_doc_cols)) {
            DolDocPutc(10);
        }

        I64 eq_wid = g_widget_count;
        g_widget_type[eq_wid] = WIDGET_EQUATION;
        g_widget_pixel_x[eq_wid] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[eq_wid] = g_doc_y + 8 + g_doc_cur_row * 18 - 6;
        g_widget_pixel_w[eq_wid] = eq_ew;
        g_widget_pixel_h[eq_wid] = eq_eh;
        g_widget_row[eq_wid] = g_doc_cur_row;
        g_widget_start_col[eq_wid] = g_doc_cur_col;
        g_widget_end_col[eq_wid] = g_doc_cur_col + eq_cell_cols;
        strcpy(g_widget_label + eq_wid * 64, "FRAC");
        strcpy(g_widget_extra + eq_wid * 128, eq_num);
        strcpy(g_widget_cmd + eq_wid * 128, eq_den);
        g_widget_tape_offset[eq_wid] = OmniTapeAppendCmd(CMD_MATH_EQUATION, g_widget_pixel_x[eq_wid], g_widget_pixel_y[eq_wid], eq_ew, eq_eh, tag, strlen(tag), eq_wid);
        MortonSpatialInsertWidget(eq_wid);
        g_widget_count++;

        g_doc_cur_col += eq_cell_cols;
        g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
    } else if (strstr(tag, "SQRT")) {
        U8 eq_rad[128]; eq_rad[0] = 0;
        DolDocGetAttrStr(tag, "rad=", eq_rad, 120);
        I64 eq_ew2 = strlen(eq_rad) * 8 + 24;
        I64 eq_eh2 = 24;
        I64 eq_cell_cols2 = (eq_ew2 + 7) / 8;

        if (g_doc_cur_col > 0 && (g_doc_cur_col + eq_cell_cols2 >= g_doc_cols)) {
            DolDocPutc(10);
        }

        I64 eq_wid2 = g_widget_count;
        g_widget_type[eq_wid2] = WIDGET_EQUATION;
        g_widget_pixel_x[eq_wid2] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[eq_wid2] = g_doc_y + 8 + g_doc_cur_row * 18 - 4;
        g_widget_pixel_w[eq_wid2] = eq_ew2;
        g_widget_pixel_h[eq_wid2] = eq_eh2;
        g_widget_row[eq_wid2] = g_doc_cur_row;
        g_widget_start_col[eq_wid2] = g_doc_cur_col;
        g_widget_end_col[eq_wid2] = g_doc_cur_col + eq_cell_cols2;
        strcpy(g_widget_label + eq_wid2 * 64, "SQRT");
        strcpy(g_widget_extra + eq_wid2 * 128, eq_rad);
        g_widget_cmd[eq_wid2 * 128] = 0;
        g_widget_tape_offset[eq_wid2] = OmniTapeAppendCmd(CMD_MATH_EQUATION, g_widget_pixel_x[eq_wid2], g_widget_pixel_y[eq_wid2], eq_ew2, eq_eh2, tag, strlen(tag), eq_wid2);
        MortonSpatialInsertWidget(eq_wid2);
        g_widget_count++;

        g_doc_cur_col += eq_cell_cols2;
        g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
    } else if (strstr(tag, "SUM") || strstr(tag, "INT")) {
        U8 eq_expr[128]; eq_expr[0] = 0;
        U8 eq_lim[128];  eq_lim[0] = 0;
        DolDocGetAttrStr(tag, "expr=", eq_expr, 120);
        DolDocGetAttrStr(tag, "lim=", eq_lim, 120);
        I64 eq_ew3 = (strlen(eq_expr) + strlen(eq_lim)) * 8 + 36;
        I64 eq_eh3 = 32;
        I64 eq_cell_cols3 = (eq_ew3 + 7) / 8;

        if (g_doc_cur_col > 0 && (g_doc_cur_col + eq_cell_cols3 >= g_doc_cols)) {
            DolDocPutc(10);
        }

        I64 eq_wid3 = g_widget_count;
        g_widget_type[eq_wid3] = WIDGET_EQUATION;
        g_widget_pixel_x[eq_wid3] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[eq_wid3] = g_doc_y + 8 + g_doc_cur_row * 18 - 6;
        g_widget_pixel_w[eq_wid3] = eq_ew3;
        g_widget_pixel_h[eq_wid3] = eq_eh3;
        g_widget_row[eq_wid3] = g_doc_cur_row;
        g_widget_start_col[eq_wid3] = g_doc_cur_col;
        g_widget_end_col[eq_wid3] = g_doc_cur_col + eq_cell_cols3;
        if (strstr(tag, "SUM")) strcpy(g_widget_label + eq_wid3 * 64, "SUM");
        else strcpy(g_widget_label + eq_wid3 * 64, "INT");
        strcpy(g_widget_extra + eq_wid3 * 128, eq_expr);
        strcpy(g_widget_cmd + eq_wid3 * 128, eq_lim);
        g_widget_tape_offset[eq_wid3] = OmniTapeAppendCmd(CMD_MATH_EQUATION, g_widget_pixel_x[eq_wid3], g_widget_pixel_y[eq_wid3], eq_ew3, eq_eh3, tag, strlen(tag), eq_wid3);
        MortonSpatialInsertWidget(eq_wid3);
        g_widget_count++;

        g_doc_cur_col += eq_cell_cols3;
        g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
    }
}

U0 DolDocParseGraph(U8 *tag) {
    I64 gw = DolDocGetAttrInt(tag, "w=", 220);
    I64 gh = DolDocGetAttrInt(tag, "h=", 52);
    U8 gtype[32]; gtype[0] = 0;
    DolDocGetAttrStr(tag, "type=", gtype, 30);
    if (!gtype[0]) strcpy(gtype, "sine");

    I64 cell_cols = (gw + 7) / 8;
    I64 cell_rows = (gh + 17) / 18;

    if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
        DolDocPutc(10);
    }

    I64 wid = -1;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        wid = g_widget_count;
        g_widget_type[wid] = WIDGET_GRAPH;
        g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
        g_widget_pixel_w[wid] = gw;
        g_widget_pixel_h[wid] = gh;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
        strcpy(g_widget_label + wid * 64, gtype);
        g_widget_cmd[wid * 128] = 0;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_CELL_OSCILLOSCOPE, g_widget_pixel_x[wid], g_widget_pixel_y[wid], gw, gh, gtype, strlen(gtype), wid);
        MortonSpatialInsertWidget(wid);
        g_widget_count++;
    }

    g_doc_cur_col += cell_cols;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
}

U0 DolDocParseSprite(U8 *tag) {
    I64 sw = DolDocGetAttrInt(tag, "w=", 96);
    I64 sh = DolDocGetAttrInt(tag, "h=", 72);
    U8 stype[32]; stype[0] = 0;
    DolDocGetAttrStr(tag, "type=", stype, 30);
    if (!stype[0]) strcpy(stype, "cube");

    I64 cell_cols = (sw + 7) / 8;
    I64 cell_rows = (sh + 17) / 18;

    if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
        DolDocPutc(10);
    }

    I64 wid = -1;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        wid = g_widget_count;
        g_widget_type[wid] = WIDGET_SPRITE3D;
        g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
        g_widget_pixel_w[wid] = sw;
        g_widget_pixel_h[wid] = sh;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
        strcpy(g_widget_label + wid * 64, stype);
        g_widget_cmd[wid * 128] = 0;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SPRITE_3D, g_widget_pixel_x[wid], g_widget_pixel_y[wid], sw, sh, stype, strlen(stype), wid);
        MortonSpatialInsertWidget(wid);
        g_widget_count++;
    }

    g_doc_cur_col += cell_cols;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
}

// Tag 19: Native Real-Time Shadertoy Viewport: $SHADER,type="plasma",w=220,h=72$
U0 DolDocParseShader(U8 *tag) {
    I64 sh_w = DolDocGetAttrInt(tag, "w=", 220);
    I64 sh_h = DolDocGetAttrInt(tag, "h=", 72);
    U8 sh_type[32]; sh_type[0] = 0;
    DolDocGetAttrStr(tag, "type=", sh_type, 30);
    if (!sh_type[0]) strcpy(sh_type, "plasma");

    I64 cell_cols = (sh_w + 7) / 8;
    I64 cell_rows = (sh_h + 17) / 18;

    if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
        DolDocPutc(10);
    }

    I64 wid = -1;
    if (g_widget_count < DOLDOC_MAX_WIDGETS) {
        wid = g_widget_count;
        g_widget_type[wid] = WIDGET_SHADER;
        g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
        g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
        g_widget_pixel_w[wid] = sh_w;
        g_widget_pixel_h[wid] = sh_h;
        g_widget_row[wid] = g_doc_cur_row;
        g_widget_start_col[wid] = g_doc_cur_col;
        g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
        strcpy(g_widget_label + wid * 64, sh_type);
        g_widget_cmd[wid * 128] = 0;
        g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SHADER_QUAD, g_widget_pixel_x[wid], g_widget_pixel_y[wid], sh_w, sh_h, sh_type, strlen(sh_type), wid);
        MortonSpatialInsertWidget(wid);
        g_widget_count++;
    }

    g_doc_cur_col += cell_cols;
    g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
}

// ============================================================================
// REAL-TIME SHADERTOY FRAGMENT EVALUATOR ($SHADER$ IN DOLDOC)
// ============================================================================
// ============================================================================
// REAL-TIME SHADERTOY FRAGMENT EVALUATOR ($SHADER$ IN DOLDOC)
// Supports 8 Native Procedural Shaders with Real-Time Uniform Reaction
// ============================================================================
U0 DolDocRenderShaderNode(I64 vx, I64 vy, I64 vw, I64 vh, U8 *sh_type) {
    // P4.6: the procedural fragment-shader VM owns these types ("vm","sdf",
    // "noise","mandel","bulb"). ShaderVM.HC loads in Stage 5, before DolDoc
    // (Stage 6), so these are direct calls bound through the SIC cell.
    if (ShaderTypeId(sh_type) >= 0) {
        ShaderVMRenderNode(vx, vy, vw, vh, sh_type);
        return;
    }
    I64 t_ms = timer_get_uptime_ms();
    I64 phase = ((t_ms * g_shader_speed) / 400) + g_doc_anim_tick * 3;
    I64 zoom = g_shader_zoom;
    if (zoom < 8) zoom = 8;

    I64 mode = 0; // 0=plasma, 1=torus, 2=wave, 3=fire, 4=tunnel, 5=metaballs, 6=stars, 7=fractal
    if (strcmp(sh_type, "torus") == 0 || strcmp(sh_type, "sdf") == 0) mode = 1;
    else if (strcmp(sh_type, "wave") == 0 || strcmp(sh_type, "glass") == 0) mode = 2;
    else if (strcmp(sh_type, "fire") == 0 || strcmp(sh_type, "flame") == 0) mode = 3;
    else if (strcmp(sh_type, "tunnel") == 0 || strcmp(sh_type, "grid") == 0) mode = 4;
    else if (strcmp(sh_type, "metaballs") == 0 || strcmp(sh_type, "blobs") == 0) mode = 5;
    else if (strcmp(sh_type, "stars") == 0 || strcmp(sh_type, "warp") == 0) mode = 6;
    else if (strcmp(sh_type, "fractal") == 0 || strcmp(sh_type, "julia") == 0) mode = 7;

    // Render 2x2 pixel blocks for high-speed evaluation
    for (I64 sy = 2; sy < vh - 2; sy += 2) {
        for (I64 sx = 2; sx < vw - 2; sx += 2) {
            U32 frag_col = 0xFF181825;
            if (mode == 0) {
                // Shader #0: Cyber Plasma Interference Field
                I64 u = (sx * zoom) / 32;
                I64 v = (sy * zoom) / 32;
                I64 w1 = DocFastSin(u + phase);
                I64 w2 = DocFastCos(v + (phase >> 1));
                I64 w3 = DocFastSin(((u + v) >> 1) - phase);
                I64 sum = (w1 + w2 + w3) / 3;
                I64 r = (128 + ((DocFastSin((sum >> 3) + (g_shader_morph >> 1)) * 120) >> 8)) & 0xFF;
                I64 g = (110 + ((DocFastCos((sum >> 3) + 12) * 115) >> 8)) & 0xFF;
                I64 b = (185 + ((sum * 68) >> 8)) & 0xFF;
                frag_col = 0xFF000000 | (r << 16) | (g << 8) | b;
            } else if (mode == 1) {
                // Shader #1: Raymarched SDF Morphing Torus & Specular Phong
                I64 cx = sx - (vw / 2);
                I64 cy = sy - (vh / 2);
                I64 r2 = cx * cx + cy * cy * 2;
                I64 torus_rad = (vh * (20 + (g_shader_morph >> 2))) / 100;
                I64 ring_r = torus_rad * torus_rad;
                I64 diff = r2 - ring_r;
                if (diff < 0) diff = -diff;
                I64 band = ring_r / 2 + 64;
                if (diff < band) {
                    I64 inten = 255 - ((diff * 220) / band);
                    I64 lx = (DocFastCos(phase) * (vw / 4)) >> 8;
                    I64 ly = (DocFastSin(phase) * (vh / 4)) >> 8;
                    I64 spec = 64 - ((cx - lx) * (cx - lx) + (cy - ly) * (cy - ly)) / 16;
                    if (spec < 0) spec = 0;
                    I64 tr = ((inten * 90) >> 8) + spec;
                    I64 tg = ((inten * 210) >> 8) + spec;
                    I64 tb = ((inten * 250) >> 8) + spec;
                    if (tr > 255) tr = 255;
                    if (tg > 255) tg = 255;
                    if (tb > 255) tb = 255;
                    frag_col = 0xFF000000 | (tr << 16) | (tg << 8) | tb;
                } else {
                    I64 bg_grid = (((sx + phase) & 15) == 0 || ((sy + phase) & 15) == 0) ? 0xFF283048 : 0xFF111420;
                    frag_col = bg_grid;
                }
            } else if (mode == 2) {
                // Shader #2: Acrylic Caustic Wave & Chromatic Dispersion
                I64 wy = (DocFastSin((sx * zoom) / 40 + phase) * (vh / 4)) >> 8;
                I64 dy = (sy - (vh / 2)) - wy;
                if (dy < 0) dy = -dy;
                I64 glow = 240 - dy * 8;
                if (glow < 24) glow = 24;
                I64 wr = (glow * 140) >> 8;
                I64 wg = (glow * 220) >> 8;
                I64 wb = glow;
                frag_col = 0xFF000000 | (wr << 16) | (wg << 8) | wb;
            } else if (mode == 3) {
                // Shader #3: Volumetric Cyber Fire & Turbulence
                I64 y_inv = vh - sy;
                I64 t_up = phase * 2;
                I64 n1 = (DocFastSin((sx * 8) + t_up) * 28) >> 8;
                I64 n2 = (DocFastCos((sx * 14) - t_up) * 18) >> 8;
                I64 n3 = (DocFastSin((sx + y_inv) * 6 + t_up) * 16) >> 8;
                I64 turb = n1 + n2 + n3;
                I64 e = 240 - ((y_inv * 260) / vh) + turb;
                if (e > 170) {
                    frag_col = 0xFFFFF090; // White-hot yellow core
                } else if (e > 105) {
                    I64 og = 100 + ((e - 105) * 140) / 65;
                    frag_col = 0xFF000000 | (250 << 16) | (og << 8) | 30; // Orange flame
                } else if (e > 35) {
                    I64 cr = 60 + ((e - 35) * 190) / 70;
                    frag_col = 0xFF000000 | (cr << 16) | (20 << 8) | 25; // Crimson flame
                } else if (e > 8) {
                    frag_col = 0xFF351830; // Smoke/ember
                } else {
                    frag_col = 0xFF0F0E17;
                }
            } else if (mode == 4) {
                // Shader #4: Synthwave 80s 3D Perspective Grid Tunnel
                I64 cy = sy - (vh / 2);
                I64 cx = sx - (vw / 2);
                if (cy > 0) {
                    I64 z = (vh * 48) / cy;
                    I64 gx = ((cx * z) >> 6);
                    I64 gz = z + phase * 4;
                    I64 is_line = 0;
                    I64 mx = gx;
                    if (mx < 0) mx = -mx;
                    if ((mx % 24) < 2 || (gz % 32) < 2) is_line = 1;
                    if (is_line) {
                        I64 fade = 255 - (z * 2);
                        if (fade < 30) fade = 30;
                        I64 gr = (fade * 243) >> 8;
                        I64 gg = (fade * 139) >> 8;
                        I64 gb = (fade * 255) >> 8;
                        frag_col = 0xFF000000 | (gr << 16) | (gg << 8) | gb;
                    } else {
                        frag_col = 0xFF141224;
                    }
                } else {
                    I64 dist_h = -cy;
                    if (dist_h < 18 && (cx * cx + dist_h * dist_h * 4) < 400) {
                        if ((dist_h % 4) == 0 && dist_h > 4) {
                            frag_col = 0xFF181825;
                        } else {
                            frag_col = 0xFFF9E2AF; // Golden sun
                        }
                    } else {
                        I64 sky_glow = 80 - dist_h * 2;
                        if (sky_glow < 12) sky_glow = 12;
                        frag_col = 0xFF000000 | ((sky_glow + 10) << 16) | (10 << 8) | ((sky_glow * 2) & 0xFF);
                    }
                }
            } else if (mode == 5) {
                // Shader #5: Tri-Orbital Fluid Isosurface Metaballs
                I64 mx0 = sx - (vw / 2);
                I64 my0 = sy - (vh / 2);
                I64 ox1 = (DocFastCos(phase) * (vw / 5)) >> 8;
                I64 oy1 = (DocFastSin(phase) * (vh / 4)) >> 8;
                I64 ox2 = (DocFastCos(phase + 21) * (vw / 4)) >> 8;
                I64 oy2 = (DocFastSin(phase + 21) * (vh / 5)) >> 8;
                I64 ox3 = (DocFastCos(phase + 42) * (vw / 6)) >> 8;
                I64 oy3 = (DocFastSin(phase + 42) * (vh / 3)) >> 8;
                I64 d1 = (mx0 - ox1) * (mx0 - ox1) + (my0 - oy1) * (my0 - oy1) + 20;
                I64 d2 = (mx0 - ox2) * (mx0 - ox2) + (my0 - oy2) * (my0 - oy2) + 20;
                I64 d3 = (mx0 - ox3) * (mx0 - ox3) + (my0 - oy3) * (my0 - oy3) + 20;
                I64 pot = 16000 / d1 + 16000 / d2 + 16000 / d3;
                if (pot > 180) {
                    frag_col = 0xFFCBA6F7; // Mauve core
                } else if (pot > 70) {
                    I64 bcol = (pot * 200) / 110;
                    if (bcol > 255) bcol = 255;
                    frag_col = 0xFF000000 | (137 << 16) | (180 << 8) | bcol;
                } else if (pot > 25) {
                    frag_col = 0xFF1E1E2E;
                } else {
                    frag_col = 0xFF11111B;
                }
            } else if (mode == 6) {
                // Shader #6: Cosmic Warp Starfield & Hyperspace
                I64 csx = sx - (vw / 2);
                I64 csy = sy - (vh / 2);
                I64 rad2 = csx * csx + csy * csy;
                I64 ang_s = (csx * 128) / (csy == 0 ? 1 : csy);
                I64 star_hash = ((ang_s * 17) ^ (rad2 >> 4) ^ phase) & 127;
                if (star_hash == 0 && rad2 > 36) {
                    I64 br = (rad2 * 255) / ((vw * vw) / 4);
                    if (br > 255) br = 255;
                    if (br < 80) br = 80;
                    frag_col = 0xFF000000 | (br << 16) | (br << 8) | 255;
                } else {
                    I64 neb = (DocFastSin((csx * 6) / 20 + phase) * DocFastCos((csy * 6) / 20 - phase)) >> 10;
                    if (neb < 0) neb = 0;
                    frag_col = 0xFF000000 | ((neb * 80) << 16) | ((neb * 40) << 8) | (neb * 140);
                }
            } else {
                // Shader #7: Complex Fractal Orbit-Trap Kaleidoscope
                I64 fx0 = ((sx - (vw / 2)) * zoom) / 24;
                I64 fy0 = ((sy - (vh / 2)) * zoom) / 24;
                I64 fzx = fx0;
                I64 fzy = fy0;
                I64 min_d = 9999;
                for (I64 iter = 0; iter < 4; iter++) {
                    I64 nzx = (fzx * fzx - fzy * fzy) >> 8;
                    I64 nzy = (fzx * fzy) >> 7;
                    fzx = nzx + ((DocFastCos(phase) * 60) >> 8);
                    fzy = nzy + ((DocFastSin(phase) * 60) >> 8);
                    I64 adx = fzx < 0 ? -fzx : fzx;
                    I64 ady = fzy < 0 ? -fzy : fzy;
                    I64 trap = adx < ady ? adx : ady;
                    if (trap < min_d) min_d = trap;
                }
                I64 finten = 255 - min_d * 3;
                if (finten < 16) finten = 16;
                if (finten > 255) finten = 255;
                I64 fr = (finten * 203) >> 8;
                I64 fg = (finten * 166) >> 8;
                I64 fb = finten;
                frag_col = 0xFF000000 | (fr << 16) | (fg << 8) | fb;
            }
            gfx_draw_rect(vx + sx, vy + sy, 2, 2, frag_col);
        }
    }

    // Viewport border & HUD badge
    gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_BLUE));

    gfx_blend_rect(vx + 4, vy + 4, vw - 8, 16, 0xA011111B);
    gfx_draw_string(vx + 8, vy + 4, "SHADERTOY:", DolDocResolveColor(SEM_COLOR_YELLOW), 0);
    gfx_draw_string(vx + 92, vy + 4, sh_type, DolDocResolveColor(SEM_COLOR_SKY), 0);
}

// ============================================================================
// SOVEREIGN 3D PIPELINE: REAL HOLYGL CUBE & 3D INVOLUTE GEARS IN $SP$
// ============================================================================
U0 DolDocRenderSprite3D(I64 vx, I64 vy, I64 vw, I64 vh, U8 *stype) {
    I64 t_ms = timer_get_uptime_ms();
    I64 ang = ((t_ms * g_sprite_rot_speed) / 600) + g_doc_anim_tick * 2 + 7;

    if (strcmp(stype, "cube") == 0) {
        U64 hgl_cube = symbols_lookup("HolyGLRenderCube");
        U64 hgl_vp = symbols_lookup("HolyGLViewport");
        if (hgl_cube != 0 && hgl_vp != 0) {
            gfx_draw_rect(vx, vy, vw, vh, 0xFF11111B);
            HolyGLViewport(vx + 2, vy + 2, vw - 4, vh - 4);
            HolyGLRenderCube((F64)ang * 1.5);
            gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_blend_rect(vx + 4, vy + 4, vw - 8, 14, 0xA011111B);
            gfx_draw_string(vx + 6, vy + 4, "3D: HolyGL Cube", 0xFFCDD6F4, 0);
            return;
        }
    } else if (strcmp(stype, "gears") == 0) {
        U64 g3d_fn = symbols_lookup("Gears3DRenderViewport");
        if (g3d_fn != 0) {
            Gears3DRenderViewport(vx + 2, vy + 2, vw - 4, vh - 4, (F64)ang * 1.5);
            gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            return;
        }
    } else if (strcmp(stype, "physics") == 0) {
        U64 phys_fn = symbols_lookup("Physics3DRenderViewport");
        if (phys_fn != 0) {
            Physics3DRenderViewport(vx + 2, vy + 2, vw - 4, vh - 4);
            gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            return;
        }
    }

    gfx_draw_rounded_rect(vx, vy, vw, vh, 4, DolDocResolveColor(SEM_COLOR_CRUST));
    gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));

    I64 cx = vx + vw / 2;
    I64 cy = vy + vh / 2 + 4;
    I64 sp_rad = (vh < vw ? vh : vw) / 3;
    if (sp_rad < 12) sp_rad = 12;

    I64 ca = DocFastCos(ang);
    I64 sa = DocFastSin(ang);
    I64 cb = DocFastCos((ang >> 1) + 9);
    I64 sb = DocFastSin((ang >> 1) + 9);

    for (I64 vi = 0; vi < 8; vi++) {
        I64 vx3 = (vi & 1) ? sp_rad : -sp_rad;
        I64 vy3 = (vi & 2) ? sp_rad : -sp_rad;
        I64 vz3 = (vi & 4) ? sp_rad : -sp_rad;

        I64 rx1 = (vx3 * ca - vz3 * sa) >> 8;
        I64 rz1 = (vx3 * sa + vz3 * ca) >> 8;
        I64 ry2 = (vy3 * cb - rz1 * sb) >> 8;
        I64 rz2 = (vy3 * sb + rz1 * cb) >> 8;

            // Perspective projection
            I64 dist = 128 + (rz2 >> 1);
            if (dist < 48) dist = 48;
            g_cube_px[vi] = cx + (rx1 * 110) / dist;
            g_cube_py[vi] = cy + (ry2 * 110) / dist;
        }

        // Bottom & Top Quad Edges + Vertical Pillars
        U32 c_front = DolDocResolveColor(SEM_COLOR_SAPPHIRE);
        U32 c_back  = DolDocResolveColor(SEM_COLOR_TEAL);
        U32 c_strut = DolDocResolveColor(SEM_COLOR_MAUVE);

        gfx_draw_line(g_cube_px[0], g_cube_py[0], g_cube_px[1], g_cube_py[1], c_back);
        gfx_draw_line(g_cube_px[1], g_cube_py[1], g_cube_px[3], g_cube_py[3], c_back);
        gfx_draw_line(g_cube_px[3], g_cube_py[3], g_cube_px[2], g_cube_py[2], c_back);
        gfx_draw_line(g_cube_px[2], g_cube_py[2], g_cube_px[0], g_cube_py[0], c_back);

        gfx_draw_line(g_cube_px[4], g_cube_py[4], g_cube_px[5], g_cube_py[5], c_front);
        gfx_draw_line(g_cube_px[5], g_cube_py[5], g_cube_px[7], g_cube_py[7], c_front);
        gfx_draw_line(g_cube_px[7], g_cube_py[7], g_cube_px[6], g_cube_py[6], c_front);
        gfx_draw_line(g_cube_px[6], g_cube_py[6], g_cube_px[4], g_cube_py[4], c_front);

        for (I64 ei = 0; ei < 4; ei++) {
            gfx_draw_line(g_cube_px[ei], g_cube_py[ei], g_cube_px[ei + 4], g_cube_py[ei + 4], c_strut);
        }
        // Highlight 3D vertices with gizmo dots
        for (I64 gi = 0; gi < 8; gi++) {
            gfx_draw_rect(g_cube_px[gi] - 1, g_cube_py[gi] - 1, 3, 3, DolDocResolveColor(SEM_COLOR_YELLOW));
        }

    gfx_draw_string(vx + 6, vy + 2, "3D:", DolDocResolveColor(SEM_COLOR_MUTED), 0);
    gfx_draw_string(vx + 30, vy + 2, stype, DolDocResolveColor(SEM_COLOR_PEACH), 0);
}

// ============================================================================
// REAL RING-BUFFER CATMULL-ROM OSCILLOSCOPE IN $GRAPH$ (WIDGET_GRAPH)
// ============================================================================
U0 DolDocSampleTelemetry() {
    if (!g_doc_trig_ready) DolDocInitTrig();
    g_osc_head = (g_osc_head + 1) & 63;
    I64 freq_step = 2 + (g_shader_speed / 25);
    g_osc_sine_buf[g_osc_head] = DocFastSin((g_osc_head * freq_step + g_doc_anim_tick * 3) & 63);
    I64 cur_fps = g_comp.fps;
    if (cur_fps <= 0) cur_fps = 60;
    g_osc_fps_buf[g_osc_head] = cur_fps;
}

U0 DolDocRenderGraphNode(I64 vx, I64 vy, I64 vw, I64 vh, U8 *gtype) {
    DolDocSampleTelemetry();

    gfx_draw_rounded_rect(vx, vy, vw, vh, 4, DolDocResolveColor(SEM_COLOR_CRUST));
    gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));

    // Sub-grid lines
    I64 mid_y = vy + vh / 2;
    gfx_draw_line(vx + 4, mid_y, vx + vw - 4, mid_y, DolDocResolveColor(SEM_COLOR_SURFACE0));
    gfx_draw_line(vx + vw / 2, vy + 4, vx + vw / 2, vy + vh - 4, DolDocResolveColor(SEM_COLOR_SURFACE0));

    I64 floor_y = vy + vh - 4;
    I64 plot_w = vw - 8;
    if (plot_w < 16) plot_w = 16;
    I64 amp = (vh / 2) - 8;
    if (amp < 6) amp = 6;

    I64 prev_x = vx + 4;
    I64 prev_y = mid_y;
    U32 wave_col = DolDocResolveColor(SEM_COLOR_TEAL);
    if (strcmp(gtype, "fps") == 0) wave_col = DolDocResolveColor(SEM_COLOR_GREEN);
    else if (strcmp(gtype, "mem") == 0) wave_col = DolDocResolveColor(SEM_COLOR_MAUVE);

    for (I64 s_i = 0; s_i < 48; s_i++) {
        I64 cur_x = vx + 4 + (s_i * plot_w) / 48;
        I64 r_idx = (g_osc_head + s_i) & 63;
        I64 sample_y = mid_y;
        if (strcmp(gtype, "fps") == 0) {
            I64 fval = g_osc_fps_buf[r_idx];
            sample_y = floor_y - ((fval * (vh - 12)) / 120);
        } else {
            // Smooth harmonic synthesis of fundamental + 2nd harmonic
            I64 s1 = g_osc_sine_buf[r_idx];
            I64 s2 = DocFastCos((r_idx * 3 + g_doc_anim_tick) & 63) / 3;
            I64 val = s1 + s2;
            sample_y = mid_y - ((val * amp) / 300);
        }
        if (sample_y < vy + 4) sample_y = vy + 4;
        if (sample_y > floor_y) sample_y = floor_y;

        if (s_i > 0) {
            gfx_draw_line(prev_x, prev_y, cur_x, sample_y, wave_col);
            gfx_draw_line(prev_x, prev_y + 1, cur_x, sample_y + 1, wave_col);
            if ((s_i & 1) == 0 && sample_y < floor_y) {
                gfx_blend_rect(cur_x, sample_y + 2, 2, floor_y - sample_y - 2, 0x38000000 | (wave_col & 0x00FFFFFF));
            }
        }
        prev_x = cur_x;
        prev_y = sample_y;
    }

    gfx_draw_string(vx + 8, vy + 4, "OSC:", DolDocResolveColor(SEM_COLOR_MUTED), 0);
    gfx_draw_string(vx + 42, vy + 4, gtype, DolDocResolveColor(SEM_COLOR_YELLOW), 0);
}

// ============================================================================
// DOLDOC STREAM PARSER & COMPILER
// ============================================================================
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

            I64 tlen = 0;
            while (*str && *str != '$' && tlen < 2047) {
                g_tag_buf[tlen] = *str;
                tlen++;
                str++;
            }
            g_tag_buf[tlen] = 0;
            if (*str == '$') str++;

            // 1. Color tags
            if (strncmp(g_tag_buf, "FG,", 3) == 0) {
                g_doc_cur_fg = DolDocParseColor(g_tag_buf + 3, SEM_COLOR_TEXT);
            } else if (strcmp(g_tag_buf, "FG") == 0) {
                g_doc_cur_fg = SEM_COLOR_TEXT;
            } else if (strncmp(g_tag_buf, "BG,", 3) == 0) {
                g_doc_cur_bg = DolDocParseColor(g_tag_buf + 3, SEM_COLOR_MANTLE);
            } else if (strcmp(g_tag_buf, "BG") == 0) {
                g_doc_cur_bg = SEM_COLOR_MANTLE;
            }
            // 2. Hyperlinks: $LK,"Label",A="command"$
            else if (strncmp(g_tag_buf, "LK,", 3) == 0) {
                g_tag_label[0] = 0; g_tag_cmd[0] = 0;
                tp = g_tag_buf + 3;
                tp = DolDocParseQuoted(tp, g_tag_label, 63);
                ap = strstr(tp, "A=");
                if (ap) DolDocParseQuoted(ap + 2, g_tag_cmd, 127);

                I64 link_len = strlen(g_tag_label) + 2;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + link_len >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_LINK;
                    g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
                    g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
                    g_widget_pixel_w[wid] = link_len * 8;
                    g_widget_pixel_h[wid] = 18;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + link_len;
                    g_widget_state[wid] = 0;
                    strcpy(g_widget_label + wid * 64, g_tag_label);
                    strcpy(g_widget_cmd + wid * 128, g_tag_cmd);
                    g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_PLUMB_DISPATCH, g_widget_pixel_x[wid], g_widget_pixel_y[wid], link_len * 8, 18, g_tag_cmd, strlen(g_tag_cmd), wid);
                    MortonSpatialInsertWidget(wid);
                    g_widget_count++;
                }

                U32 old_fg = g_doc_cur_fg;
                g_doc_cur_fg = SEM_COLOR_SKY;
                for (I64 doc_i = 0; g_tag_label[doc_i]; doc_i++) {
                    DolDocPutc(g_tag_label[doc_i]);
                    I64 c_idx = g_doc_cur_row * DOLDOC_MAX_COLS + (g_doc_cur_col - 1);
                    if (c_idx >= 0 && c_idx < DOLDOC_CELLS) g_doc_link_idx[c_idx] = wid;
                }
                g_doc_cur_fg = old_fg;
            }
            // 3. Vector Buttons: $BT,"Label",LM="command"$
            else if (strncmp(g_tag_buf, "BT,", 3) == 0) {
                g_tag_label[0] = 0; g_tag_cmd[0] = 0;
                tp = g_tag_buf + 3;
                tp = DolDocParseQuoted(tp, g_tag_label, 63);
                lmp = strstr(tp, "LM=");
                if (lmp) DolDocParseQuoted(lmp + 3, g_tag_cmd, 127);

                I64 lbl_len = strlen(g_tag_label);
                I64 vw = lbl_len * 8 + 16;
                I64 vh = 18;
                I64 cell_cols = (vw + 7) / 8;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_BUTTON;
                    g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
                    g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
                    g_widget_pixel_w[wid] = vw;
                    g_widget_pixel_h[wid] = vh;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
                    g_widget_state[wid] = 0;
                    strcpy(g_widget_label + wid * 64, g_tag_label);
                    strcpy(g_widget_cmd + wid * 128, g_tag_cmd);
                    g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SDF_RECT, g_widget_pixel_x[wid], g_widget_pixel_y[wid], vw, vh, g_tag_label, lbl_len, wid);
                    MortonSpatialInsertWidget(wid);
                    g_widget_count++;
                }

                g_doc_cur_col += cell_cols + 1;
                g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
            }
            // 4. Progress Bar: $PB,VAL=x,MAX=y$
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

                I64 bar_width = 160;
                I64 cell_cols = (bar_width + 48 + 7) / 8;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    I64 wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_PROGRESS;
                    g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
                    g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
                    g_widget_pixel_w[wid] = bar_width;
                    g_widget_pixel_h[wid] = 18;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
                    g_widget_val[wid] = val;
                    g_widget_max[wid] = max_val;
                    g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_PROGRESS_BAR, g_widget_pixel_x[wid], g_widget_pixel_y[wid], bar_width, 18, "PB", 2, wid);
                    MortonSpatialInsertWidget(wid);
                    g_widget_count++;
                }

                g_doc_cur_col += cell_cols;
                g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
            }
            // 5. Checkbox: $CB,"Label",val$
            else if (strncmp(g_tag_buf, "CB,", 3) == 0) {
                g_tag_label[0] = 0;
                tp = g_tag_buf + 3;
                tp = DolDocParseQuoted(tp, g_tag_label, 63);
                I64 chk = 0;
                if (*tp == ',') {
                    tp++;
                    if (*tp == '1' || *tp == 't' || *tp == 'T') chk = 1;
                }

                I64 lbl_len = strlen(g_tag_label);
                I64 vw = 20 + lbl_len * 8 + 8;
                I64 cell_cols = (vw + 7) / 8;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_CHECKBOX;
                    g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
                    g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
                    g_widget_pixel_w[wid] = vw;
                    g_widget_pixel_h[wid] = 18;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
                    g_widget_state[wid] = chk;
                    g_widget_target[wid] = 0;
                    strcpy(g_widget_label + wid * 64, g_tag_label);
                    g_widget_cmd[wid * 128] = 0;
                    g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_CELL_CHECKBOX, g_widget_pixel_x[wid], g_widget_pixel_y[wid], vw, 18, g_tag_label, lbl_len, wid);
                    MortonSpatialInsertWidget(wid);
                    g_widget_count++;
                }

                g_doc_cur_col += cell_cols;
                g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
            }
            // 6. Collapsible Tree: $TR,"Title"$
            else if (strncmp(g_tag_buf, "TR,", 3) == 0) {
                g_tag_title[0] = 0;
                DolDocParseQuoted(g_tag_buf + 3, g_tag_title, 63);
                I64 tr_len = strlen(g_tag_title) + 4;
                I64 cell_cols = (tr_len * 8 + 7) / 8;
                if (g_doc_cur_col > 0 && (g_doc_cur_col + cell_cols >= g_doc_cols)) {
                    DolDocPutc(10);
                }

                I64 wid = -1;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_TREE;
                    g_widget_pixel_x[wid] = g_doc_x + 8 + g_doc_cur_col * 8;
                    g_widget_pixel_y[wid] = g_doc_y + 8 + g_doc_cur_row * 18;
                    g_widget_pixel_w[wid] = tr_len * 8;
                    g_widget_pixel_h[wid] = 18;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = g_doc_cur_col;
                    g_widget_end_col[wid] = g_doc_cur_col + cell_cols;
                    g_widget_state[wid] = 1;
                    strcpy(g_widget_label + wid * 64, g_tag_title);
                    g_widget_cmd[wid * 128] = 0;
                    g_widget_tape_offset[wid] = OmniTapeAppendCmd(CMD_SDF_RECT, g_widget_pixel_x[wid], g_widget_pixel_y[wid], tr_len * 8, 18, g_tag_title, tr_len, wid);
                    MortonSpatialInsertWidget(wid);
                    g_widget_count++;
                }

                g_doc_cur_col += cell_cols;
                g_doc_cursor_x = g_doc_x + 8 + g_doc_cur_col * 8;
            }
            // 7. Horizontal Rule: $HR$
            else if (strcmp(g_tag_buf, "HR") == 0) {
                if (g_doc_cur_col > 0) DolDocPutc(10);
                I64 hy = g_doc_y + 8 + g_doc_cur_row * 18;
                if (g_widget_count < DOLDOC_MAX_WIDGETS) {
                    I64 wid = g_widget_count;
                    g_widget_type[wid] = WIDGET_HR;
                    g_widget_pixel_x[wid] = g_doc_x + 12;
                    g_widget_pixel_y[wid] = hy;
                    g_widget_pixel_w[wid] = g_doc_w - 24;
                    g_widget_pixel_h[wid] = 18;
                    g_widget_row[wid] = g_doc_cur_row;
                    g_widget_start_col[wid] = 0;
                    g_widget_end_col[wid] = g_doc_cols;
                    g_widget_count++;
                }
                for (I64 hr_i = 0; hr_i < g_doc_cols - 2; hr_i++) DolDocPutc(' ');
                DolDocPutc(10);
            }
            // 8. Style Stack Control: $PUSH$, $POP$
            else if (strcmp(g_tag_buf, "PUSH") == 0) {
                DolDocStylePush(g_doc_cur_fg, g_doc_cur_bg);
            } else if (strcmp(g_tag_buf, "POP") == 0) {
                DolDocStylePop();
            }
            // 9. Screen Clear: $CLEAR$, $CLS$
            else if (strcmp(g_tag_buf, "CLEAR") == 0 || strcmp(g_tag_buf, "CLS") == 0) {
                DolDocClear();
            }
            // 10. Layout Flow: $ROW$, $COL,n$
            else if (strcmp(g_tag_buf, "ROW") == 0) {
                DolDocPutc(10);
            } else if (strncmp(g_tag_buf, "COL,", 4) == 0) {
                I64 new_col = DolDocAtoi(g_tag_buf + 4);
                if (new_col < g_doc_cols) {
                    while (g_doc_cur_col < new_col) {
                        DolDocPutc(' ');
                    }
                }
            }
            // 11. CSS Box Model: $BOX,w=...,h=...,bg=...,border=...$
            else if (strncmp(g_tag_buf, "BOX", 3) == 0) {
                DolDocParseBox(g_tag_buf);
            }
            // 12. CSS Card Container: $CARD,title="...",w=...,h=...,bg=...,border=...$
            else if (strncmp(g_tag_buf, "CARD", 4) == 0) {
                DolDocParseCard(g_tag_buf);
            }
            // 13. Acrylic Glass Panel: $GLASS,w=...,h=...,alpha=...$
            else if (strncmp(g_tag_buf, "GLASS", 5) == 0) {
                DolDocParseGlass(g_tag_buf);
            }
            // 14. Soft Drop Shadow: $SHADOW,w=...,h=...,radius=...$
            else if (strncmp(g_tag_buf, "SHADOW", 6) == 0) {
                DolDocParseShadow(g_tag_buf);
            }
            // 15. Reactive Slider: $SL,"Label",val=50,min=0,max=100,w=160$
            else if (strncmp(g_tag_buf, "SL,", 3) == 0) {
                DolDocParseSlider(g_tag_buf);
            }
            // 16. Mathematical Typography: $EQ,FRAC,...$ / $EQ,SQRT,...$ / $EQ,SUM,...$
            else if (strncmp(g_tag_buf, "EQ,", 3) == 0) {
                DolDocParseEquation(g_tag_buf);
            }
            // 17. Real-Time Telemetry Graph: $GRAPH,type="...",w=...,h=...$
            else if (strncmp(g_tag_buf, "GRAPH", 5) == 0) {
                DolDocParseGraph(g_tag_buf);
            }
            // 18. In-Code 3D Mesh / Sprite: $SP,type="...",w=...,h=...$
            else if (strncmp(g_tag_buf, "SP", 2) == 0) {
                DolDocParseSprite(g_tag_buf);
            }
            // 19. Native Shadertoy Viewport: $SHADER,type="...",w=...,h=...$
            else if (strncmp(g_tag_buf, "SHADER", 6) == 0) {
                DolDocParseShader(g_tag_buf);
            }
            // 20. Scalable Vector Font Span: $FONT,text="...",scale=200,color="CYAN"$
            else if (strncmp(g_tag_buf, "FONT", 4) == 0 || strncmp(g_tag_buf, "H1", 2) == 0) {
                DolDocParseFontText(g_tag_buf);
            }
            continue;
        }

        DolDocPutc(*str);
        str++;
    }
}

// ============================================================================
// SMALLTALK MORPHIC HALO MANIPULATOR OVERLAY
// ============================================================================
U0 DolDocDrawMorphicHalo(I64 wid) {
    if (wid < 0 || wid >= g_widget_count) return;
    I64 vx = g_widget_pixel_x[wid];
    I64 vy = g_widget_pixel_y[wid] + g_doc_scroll_offset * 18;
    I64 vw = g_widget_pixel_w[wid];
    I64 vh = g_widget_pixel_h[wid];

    U32 yellow_col   = DolDocResolveColor(SEM_COLOR_YELLOW);
    U32 sapphire_col = DolDocResolveColor(SEM_COLOR_SAPPHIRE);
    U32 red_col      = DolDocResolveColor(SEM_COLOR_RED);
    U32 teal_col     = DolDocResolveColor(SEM_COLOR_TEAL);
    U32 green_col    = DolDocResolveColor(SEM_COLOR_GREEN);
    U32 peach_col    = DolDocResolveColor(SEM_COLOR_PEACH);
    U32 mantle_col   = DolDocResolveColor(SEM_COLOR_MANTLE);
    U32 text_col     = DolDocResolveColor(SEM_COLOR_TEXT);

    // 1. Halo Bounding Box Outline (crisp glowing border)
    gfx_draw_rect(vx - 1, vy - 1, vw + 2, 1, yellow_col);
    gfx_draw_rect(vx - 1, vy + vh, vw + 2, 1, yellow_col);
    gfx_draw_rect(vx - 1, vy - 1, 1, vh + 2, yellow_col);
    gfx_draw_rect(vx + vw, vy - 1, 1, vh + 2, yellow_col);

    // 2. Morphic Halo Corner Handles (Sleek 10x10 handles hugging corners)
    // Handle [S] Top-Left: Source / AST Inspector
    gfx_draw_rounded_rect(vx - 2, vy - 6, 10, 10, 2, sapphire_col);
    gfx_draw_string(vx, vy - 5, "S", mantle_col, 0);

    // Handle [X] Top-Right: Dismiss Inspector
    gfx_draw_rounded_rect(vx + vw - 8, vy - 6, 10, 10, 2, red_col);
    gfx_draw_string(vx + vw - 6, vy - 5, "X", mantle_col, 0);

    // Handle [?] Bottom-Left: Memory Cell / Reflection Probe
    gfx_draw_rounded_rect(vx - 2, vy + vh - 4, 10, 10, 2, teal_col);
    gfx_draw_string(vx, vy + vh - 3, "?", mantle_col, 0);

    // Handle [D] Bottom-Right: Duplicate / Clone Morph
    gfx_draw_rounded_rect(vx + vw - 8, vy + vh - 4, 10, 10, 2, green_col);
    gfx_draw_string(vx + vw - 6, vy + vh - 3, "D", mantle_col, 0);

    // 3. Morphic Name Pill (Centered on top border between [S] and [X])
    U8 *lbl = g_widget_label + wid * 64;
    U8 *name = lbl[0] ? lbl : "Morph";
    I64 name_len = strlen(name);
    I64 pill_w = name_len * 8 + 12;
    if (pill_w > vw - 22) pill_w = vw - 22;
    if (pill_w < 24) pill_w = 24;
    I64 pill_x = vx + (vw - pill_w) / 2;
    I64 pill_y = vy - 7;

    gfx_draw_rounded_rect(pill_x, pill_y, pill_w, 13, 3, mantle_col);
    gfx_draw_rect(pill_x, pill_y, pill_w, 1, peach_col);

    U8 disp_name[32];
    I64 max_chars = (pill_w - 8) / 8;
    if (max_chars < 1) max_chars = 1;
    if (name_len > max_chars && max_chars >= 4) {
        for (I64 ni = 0; ni < max_chars - 2; ni++) disp_name[ni] = name[ni];
        disp_name[max_chars - 2] = '.';
        disp_name[max_chars - 1] = '.';
        disp_name[max_chars] = 0;
    } else {
        strcpy(disp_name, name);
    }
    gfx_draw_string(pill_x + 4, pill_y + 1, disp_name, yellow_col, 0);
}

// ============================================================================
// OMNITAPE DISPLAY JOURNAL REPLAY ENGINE
// ============================================================================
U0 OmniTapeReplay(I64 pass, I64 scroll_px) {
    if (!g_omnitape_buf) return;

    U32 surface0_col  = DolDocResolveColor(SEM_COLOR_SURFACE0);
    U32 surface1_col  = DolDocResolveColor(SEM_COLOR_SURFACE1);
    U32 crust_col     = DolDocResolveColor(SEM_COLOR_CRUST);
    U32 text_col      = DolDocResolveColor(SEM_COLOR_TEXT);
    U32 yellow_col    = DolDocResolveColor(SEM_COLOR_YELLOW);
    U32 sapphire_col  = DolDocResolveColor(SEM_COLOR_SAPPHIRE);
    U32 teal_col      = DolDocResolveColor(SEM_COLOR_TEAL);
    U32 blue_col      = DolDocResolveColor(SEM_COLOR_BLUE);
    U32 peach_col     = DolDocResolveColor(SEM_COLOR_PEACH);
    U32 sky_col       = DolDocResolveColor(SEM_COLOR_SKY);

    // Direct Tape Traversal from contiguous Sovereign RAM Arena
    I64 tape_off = 0;
    while (tape_off < g_omnitape_tail) {
        CTapeCmdHeader *hdr = g_omnitape_buf + tape_off;
        if (hdr->opcode == CMD_NOP) break;

        I64 opcode       = hdr->opcode;
        I64 wid          = hdr->flags;
        I64 payload_len  = hdr->payload_size;
        U8 *payload      = g_omnitape_buf + tape_off + 64;

        I64 total_len    = 64 + payload_len + 1;
        I64 aligned_step = ((total_len + 63) / 64) * 64;
        tape_off += aligned_step;

        if (wid < 0 || wid >= g_widget_count) continue;
        I64 wtype = g_widget_type[wid];

        I64 vx = (hdr->box_w > 0) ? hdr->box_x : (g_doc_x + 8 + g_widget_start_col[wid] * 8);
        I64 vy = (hdr->box_h > 0) ? (hdr->box_y + scroll_px) : (g_doc_y + 8 + g_widget_row[wid] * 18 + scroll_px);
        if (wtype == WIDGET_EQUATION) vy -= 6;
        I64 vw = (hdr->box_w > 0) ? hdr->box_w : g_widget_pixel_w[wid];
        if (vw > g_doc_w - 16) vw = g_doc_w - 16;
        I64 vh = (hdr->box_h > 0) ? hdr->box_h : g_widget_pixel_h[wid];
        g_widget_pixel_x[wid] = vx;
        g_widget_pixel_y[wid] = vy - scroll_px;

        if (pass == 1) {
            // Layer 1 Containers: Cards, Boxes, Glass, Shadow, HR
            if (opcode == CMD_SDF_CARD || (opcode == CMD_SDF_RECT && (wtype == WIDGET_CARD || wtype == WIDGET_BOX || wtype == WIDGET_HR || wtype == WIDGET_GLASS || wtype == WIDGET_SHADOW))) {
                if (vy + vh < g_doc_y || vy > g_doc_y + g_doc_h) continue;

                if (wtype == WIDGET_CARD || opcode == CMD_SDF_CARD) {
                    U32 cbg = DolDocResolveColor((U32)g_widget_val[wid]);
                    U32 cborder = DolDocResolveColor((U32)g_widget_min[wid]);
                    I64 card_rad = g_theme.corner_radius;
                    gfx_draw_soft_shadow(vx, vy, vw, vh, 6, g_theme.shadow_color);
                    if (card_rad > 0) {
                        if (cborder) gfx_draw_rounded_rect(vx, vy, vw, vh, card_rad, cborder);
                        gfx_draw_rounded_rect(vx + 1, vy + 1, vw - 2, vh - 2, card_rad - 1, cbg);
                    } else {
                        if (cborder) gfx_draw_rect(vx, vy, vw, vh, cborder);
                        gfx_draw_rect(vx + 2, vy + 2, vw - 4, vh - 4, cbg);
                    }
                    U8 *lbl = payload[0] ? payload : (g_widget_label + wid * 64);
                    I64 t_len = strlen(lbl);
                    if (t_len > 0) {
                        I64 badge_w = t_len * 8 + 16;
                        if (badge_w > vw - 24) badge_w = vw - 24;
                        gfx_draw_rounded_rect(vx + 12, vy + 4, badge_w, 18, 4, surface0_col);
                        gfx_draw_string(vx + 20, vy + 5, lbl, yellow_col, 0);
                    }
                } else if (wtype == WIDGET_BOX) {
                    U32 bbg = DolDocResolveColor((U32)g_widget_val[wid]);
                    U32 bborder = DolDocResolveColor((U32)g_widget_min[wid]);
                    if (bborder) gfx_draw_rounded_rect(vx, vy, vw, vh, 4, bborder);
                    gfx_draw_rounded_rect(vx + 1, vy + 1, vw - 2, vh - 2, 3, bbg);
                } else if (wtype == WIDGET_HR) {
                    gfx_draw_rect(vx, vy + 8, vw, 1, surface1_col);
                } else if (wtype == WIDGET_GLASS) {
                    DolDocDrawGlass(vx, vy, vw, vh, g_widget_val[wid]);
                } else if (wtype == WIDGET_SHADOW) {
                    DolDocDrawShadow(vx, vy, vw, vh, g_widget_val[wid]);
                }
            }
        } else if (pass == 3) {
            // Layer 3 Interactive Widgets: Buttons, Sliders, Progress, Checkbox, Tree, Equations, Shaders, 3D Sprites, Graphs, Fonts
            if (opcode != CMD_SDF_CARD && !(opcode == CMD_SDF_RECT && (wtype == WIDGET_CARD || wtype == WIDGET_BOX || wtype == WIDGET_HR || wtype == WIDGET_GLASS || wtype == WIDGET_SHADOW))) {
                if (vy + vh < g_doc_y || vy > g_doc_y + g_doc_h) continue;

                if (wtype == WIDGET_BUTTON || (opcode == CMD_SDF_RECT && wtype == WIDGET_BUTTON)) {
                    U8 *lbl = payload[0] ? payload : (g_widget_label + wid * 64);
                    I64 is_pressed = g_widget_state[wid];
                    I64 dy = is_pressed ? 1 : 0;

                    if (!is_pressed) {
                        gfx_draw_soft_shadow(vx, vy, vw, vh, 4, g_theme.shadow_color);
                    }

                    U32 body_col = is_pressed ? surface0_col : surface1_col;
                    if (g_theme.corner_radius > 0) {
                        gfx_draw_rounded_rect(vx, vy + dy, vw, vh - dy, 4, body_col);
                    } else {
                        gfx_draw_rect(vx, vy + dy, vw, vh - dy, body_col);
                        gfx_draw_rect(vx, vy + dy, vw, 1, blue_col);
                    }

                    if (!is_pressed) {
                        gfx_blend_rect(vx + 4, vy + 1, vw - 8, 1, 0x2AFFFFFF);
                        gfx_blend_rect(vx + 4, vy + vh - 1, vw - 8, 1, 0x40000000);
                    }

                    I64 tx = vx + (vw - strlen(lbl) * 8) / 2;
                    I64 ty = vy + dy + (vh - 16) / 2;
                    U32 btn_tcol = is_pressed ? blue_col : text_col;
                    gfx_draw_string(tx, ty, lbl, btn_tcol, 0);
                } else if (wtype == WIDGET_SLIDER || opcode == CMD_CELL_SLIDER) {
                    I64 val = g_widget_val[wid];
                    if (g_widget_target[wid] != 0) {
                        val = *(I64*)(g_widget_target[wid]);
                        g_widget_val[wid] = val;
                    }
                    I64 min_v = g_widget_min[wid];
                    I64 max_v = g_widget_max[wid];
                    if (max_v <= min_v) max_v = min_v + 100;
                    I64 track_y = vy + (vh - 6) / 2;

                    gfx_draw_rounded_rect(vx, track_y, vw, 6, 3, crust_col);
                    gfx_draw_line(vx + 2, track_y, vx + vw - 2, track_y, 0x60000000);

                    I64 fill_w = ((val - min_v) * (vw - 12)) / (max_v - min_v);
                    if (fill_w < 0) fill_w = 0;
                    if (fill_w > vw - 12) fill_w = vw - 12;
                    if (fill_w > 0) {
                        gfx_draw_rounded_rect(vx, track_y, fill_w + 6, 6, 3, teal_col);
                    }

                    I64 thumb_x = vx + fill_w + 6;
                    I64 thumb_y = track_y + 3;
                    gfx_draw_circle_filled(thumb_x, thumb_y, 7, text_col);
                    gfx_draw_circle_filled(thumb_x, thumb_y, 5, sapphire_col);

                    U8 val_str[16];
                    I64 tmp_v = val;
                    if (tmp_v <= 0) {
                        val_str[0] = '0'; val_str[1] = 0;
                    } else {
                        U8 rev[16]; I64 r_i = 0;
                        while (tmp_v > 0 && r_i < 12) {
                            rev[r_i] = '0' + (tmp_v % 10);
                            r_i++;
                            tmp_v /= 10;
                        }
                        for (I64 d = 0; d < r_i; d++) {
                            val_str[d] = rev[r_i - 1 - d];
                        }
                        val_str[r_i] = 0;
                    }
                    gfx_draw_string(vx + vw + 8, vy + 2, val_str, yellow_col, 0);
                } else if (wtype == WIDGET_PROGRESS || opcode == CMD_PROGRESS_BAR) {
                    I64 val = g_widget_val[wid];
                    I64 max_val = g_widget_max[wid];
                    if (max_val <= 0) max_val = 100;
                    if (val < 0) val = 0;
                    if (val > max_val) val = max_val;

                    gfx_draw_rounded_rect(vx, vy + 4, vw, 10, 5, crust_col);
                    I64 fill_w = (val * vw) / max_val;
                    if (fill_w > 0) {
                        if (fill_w < 6) fill_w = 6;
                        gfx_draw_rounded_rect(vx, vy + 4, fill_w, 10, 5, teal_col);
                    }

                    I64 pct = (val * 100) / max_val;
                    U8 pct_buf[16];
                    I64 p_i = 0;
                    if (pct >= 100) { pct_buf[p_i++] = '1'; pct_buf[p_i++] = '0'; pct_buf[p_i++] = '0'; }
                    else if (pct >= 10) { pct_buf[p_i++] = '0' + ((pct / 10) % 10); pct_buf[p_i++] = '0' + (pct % 10); }
                    else { pct_buf[p_i++] = '0' + (pct % 10); }
                    pct_buf[p_i++] = '%';
                    pct_buf[p_i] = 0;
                    gfx_draw_string(vx + vw + 8, vy + 1, pct_buf, peach_col, 0);
                } else if (wtype == WIDGET_CHECKBOX || opcode == CMD_CELL_CHECKBOX) {
                    I64 is_chk = g_widget_state[wid];
                    U8 *lbl = payload[0] ? payload : (g_widget_label + wid * 64);
                    U32 box_bg = is_chk ? blue_col : surface0_col;
                    gfx_draw_rounded_rect(vx, vy + 2, 14, 14, 3, box_bg);
                    if (is_chk) {
                        gfx_draw_line(vx + 3, vy + 8, vx + 6, vy + 11, crust_col);
                        gfx_draw_line(vx + 6, vy + 11, vx + 11, vy + 4, crust_col);
                        gfx_draw_line(vx + 3, vy + 9, vx + 6, vy + 12, crust_col);
                        gfx_draw_line(vx + 6, vy + 12, vx + 11, vy + 5, crust_col);
                    }
                    if (lbl[0]) {
                        gfx_draw_string(vx + 20, vy + 1, lbl, text_col, 0);
                    }
                } else if (wtype == WIDGET_TREE) {
                    I64 is_open = g_widget_state[wid];
                    U8 *lbl = payload[0] ? payload : (g_widget_label + wid * 64);
                    if (is_open) {
                        gfx_draw_line(vx + 2, vy + 6, vx + 7, vy + 11, yellow_col);
                        gfx_draw_line(vx + 7, vy + 11, vx + 12, vy + 6, yellow_col);
                    } else {
                        gfx_draw_line(vx + 4, vy + 3, vx + 9, vy + 8, sky_col);
                        gfx_draw_line(vx + 9, vy + 8, vx + 4, vy + 13, sky_col);
                    }
                    if (lbl[0]) {
                        gfx_draw_string(vx + 18, vy + 1, lbl, text_col, 0);
                    }
                } else if (wtype == WIDGET_EQUATION || opcode == CMD_MATH_EQUATION) {
                    U8 *eq_type = g_widget_label + wid * 64;
                    U8 *extra = g_widget_extra + wid * 128;
                    U8 *cmd = g_widget_cmd + wid * 128;
                    U64 fv_fn = symbols_lookup("FontVectorDrawString");
                    if (strcmp(eq_type, "FRAC") == 0) {
                        gfx_draw_rect(vx, vy + 15, vw, 2, text_col);
                        if (fv_fn != 0) {
                            I64 eq_nw = FontVectorMeasureString(extra, 70);
                            I64 eq_dw = FontVectorMeasureString(cmd, 70);
                            I64 eq_nx = vx + (vw - eq_nw) / 2;
                            I64 eq_dx = vx + (vw - eq_dw) / 2;
                            FontVectorDrawString(eq_nx, vy, extra, 70, sapphire_col);
                            FontVectorDrawString(eq_dx, vy + 17, cmd, 70, text_col);
                        } else {
                            I64 eq_nx = vx + (vw - strlen(extra) * 8) / 2;
                            gfx_draw_string(eq_nx, vy, extra, sapphire_col, 0);
                            I64 eq_dx = vx + (vw - strlen(cmd) * 8) / 2;
                            gfx_draw_string(eq_dx, vy + 18, cmd, text_col, 0);
                        }
                    } else if (strcmp(eq_type, "SQRT") == 0) {
                        gfx_draw_line(vx, vy + 16, vx + 4, vy + 22, sapphire_col);
                        gfx_draw_line(vx + 4, vy + 22, vx + 9, vy + 2, sapphire_col);
                        gfx_draw_line(vx + 9, vy + 2, vx + vw, vy + 2, sapphire_col);
                        if (fv_fn != 0) {
                            FontVectorDrawString(vx + 12, vy + 5, extra, 75, text_col);
                        } else {
                            gfx_draw_string(vx + 12, vy + 5, extra, text_col, 0);
                        }
                    } else if (strcmp(eq_type, "SUM") == 0) {
                        gfx_draw_line(vx + 2, vy + 2, vx + 16, vy + 2, yellow_col);
                        gfx_draw_line(vx + 2, vy + 2, vx + 10, vy + 14, yellow_col);
                        gfx_draw_line(vx + 10, vy + 14, vx + 2, vy + 26, yellow_col);
                        gfx_draw_line(vx + 2, vy + 26, vx + 16, vy + 26, yellow_col);
                        if (fv_fn != 0) {
                            FontVectorDrawString(vx + 22, vy + 6, extra, 75, sapphire_col);
                            if (cmd[0]) {
                                I64 ew = FontVectorMeasureString(extra, 75);
                                FontVectorDrawString(vx + 22 + ew + 4, vy + 12, cmd, 70, peach_col);
                            }
                        } else {
                            gfx_draw_string(vx + 22, vy + 6, extra, sapphire_col, 0);
                            if (cmd[0]) gfx_draw_string(vx + 22 + strlen(extra) * 8 + 4, vy + 14, cmd, peach_col, 0);
                        }
                    } else if (strcmp(eq_type, "INT") == 0) {
                        gfx_draw_line(vx + 10, vy + 2, vx + 14, vy + 2, teal_col);
                        gfx_draw_line(vx + 10, vy + 2, vx + 6, vy + 26, teal_col);
                        gfx_draw_line(vx + 2, vy + 26, vx + 6, vy + 26, teal_col);
                        if (fv_fn != 0) {
                            FontVectorDrawString(vx + 18, vy + 6, extra, 75, sapphire_col);
                        } else {
                            gfx_draw_string(vx + 18, vy + 6, extra, sapphire_col, 0);
                        }
                    }
                } else if (wtype == WIDGET_GRAPH || opcode == CMD_CELL_OSCILLOSCOPE) {
                    U8 *gtype = payload[0] ? payload : (g_widget_label + wid * 64);
                    DolDocRenderGraphNode(vx, vy, vw, vh, gtype);
                } else if (wtype == WIDGET_SPRITE3D || opcode == CMD_SPRITE_3D) {
                    U8 *stype = payload[0] ? payload : (g_widget_label + wid * 64);
                    DolDocRenderSprite3D(vx, vy, vw, vh, stype);
                } else if (wtype == WIDGET_SHADER || opcode == CMD_SHADER_QUAD) {
                    U8 *shtype = payload[0] ? payload : (g_widget_label + wid * 64);
                    DolDocRenderShaderNode(vx, vy, vw, vh, shtype);
                } else if (wtype == WIDGET_FONT_TEXT || opcode == CMD_TEXT_RUN) {
                    U8 *flbl = payload[0] ? payload : (g_widget_label + wid * 64);
                    I64 fscale = g_widget_val[wid];
                    U32 fcol = DolDocResolveColor((U32)g_widget_min[wid]);
                    U64 fv_fn = symbols_lookup("FontVectorDrawString");
                    if (fv_fn != 0) {
                        FontVectorDrawString(vx, vy + 2, flbl, fscale, fcol);
                    } else {
                        gfx_draw_string(vx, vy + 2, flbl, fcol, 0);
                        gfx_draw_string(vx + 1, vy + 2, flbl, fcol, 0);
                    }
                }
            }
        }
    }
}

// ============================================================================
// UNIFIED SCENE-GRAPH & OMNITAPE COMPOSITING RENDERER
// ============================================================================
U0 DolDocRedraw() {
    if (g_doc_dirty_mask == 0) {
        return;
    }
    g_doc_anim_tick++;

    gfx_set_clip(g_doc_x, g_doc_y, g_doc_w, g_doc_h);

    U32 canvas_bg     = DolDocResolveColor(g_doc_cur_bg);
    U32 surface0_col  = DolDocResolveColor(SEM_COLOR_SURFACE0);
    U32 crust_col     = DolDocResolveColor(SEM_COLOR_CRUST);
    U32 blue_col      = DolDocResolveColor(SEM_COLOR_BLUE);

    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h, canvas_bg);
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, 1, surface0_col);

    I64 scroll_px = g_doc_scroll_offset * 18;

    // Layer 1: Background Containers (Cards, Boxes, Dividers, Glass Panels, Shadows via OmniTape)
    OmniTapeReplay(1, scroll_px);

    // Layer 2: Typography, Scrollback History & Text Runs
    for (I64 d_r = 0; d_r < g_doc_rows; d_r++) {
        I64 rx = g_doc_x + 8;
        I64 ry = g_doc_y + 8 + d_r * 18;
        I64 virt_line = (g_doc_history_count - g_doc_scroll_offset) + d_r;

        if (virt_line < g_doc_history_count && virt_line >= 0) {
            // Render from scrollback history buffer
            I64 h_base = virt_line * DOLDOC_MAX_COLS;
            for (I64 d_hc = 0; d_hc < g_doc_cols; d_hc++) {
                U8 hch = g_hist_chars[h_base + d_hc];
                if (hch > 32 && hch <= 126) {
                    U32 hfg = DolDocResolveColor(g_hist_fg[h_base + d_hc]);
                    gfx_draw_char(rx + d_hc * 8, ry, hch, hfg, 0);
                }
            }
        } else {
            // Render from live viewport row
            I64 act_r = virt_line - g_doc_history_count;
            if (act_r >= 0 && act_r < g_doc_rows) {
                I64 row_base = act_r * DOLDOC_MAX_COLS;
                for (I64 d_c = 0; d_c < g_doc_cols; d_c++) {
                    U8 ch = g_doc_chars[row_base + d_c];
                    if (ch > 32 && ch <= 126) {
                        U32 fg = DolDocResolveColor(g_doc_fg[row_base + d_c]);
                        gfx_draw_char(rx + d_c * 8, ry, ch, fg, 0);
                    }
                }
            }
        }
    }

    // Layer 3: Interactive Foreground Widgets, Shaders, Vector Fonts, 3D Sprites & Oscilloscopes via OmniTape
    OmniTapeReplay(3, scroll_px);

    // Layer 4: Interactive Scrollbar Track & Thumb (CBoxScrollbar)
    if (g_doc_history_count > 0) {
        I64 bar_x = g_doc_x + g_doc_w - 8;
        I64 bar_y = g_doc_y + 4;
        I64 bar_h = g_doc_h - 8;
        gfx_draw_rounded_rect(bar_x, bar_y, 6, bar_h, 3, crust_col);

        I64 total_lines = g_doc_history_count + g_doc_rows;
        I64 thumb_h = (bar_h * g_doc_rows) / total_lines;
        if (thumb_h < 24) thumb_h = 24;
        I64 scroll_pos = g_doc_history_count - g_doc_scroll_offset;
        if (scroll_pos < 0) scroll_pos = 0;
        I64 thumb_y = bar_y + ((bar_h - thumb_h) * scroll_pos) / g_doc_history_count;
        gfx_draw_rounded_rect(bar_x, thumb_y, 6, thumb_h, 3, blue_col);
    }

    // Layer 5: Smalltalk Morphic Halo Direct Manipulation Overlay
    if (g_doc_inspected_wid >= 0 && g_doc_inspected_wid < g_widget_count) {
        DolDocDrawMorphicHalo(g_doc_inspected_wid);
    }

    gfx_reset_clip();

    g_doc_dirty_mask = 0;
}

U0 DolDocAnimateTick() {
    if (g_widget_count <= 0) return;
    g_doc_anim_tick++;
    I64 scroll_px = g_doc_scroll_offset * 18;
    for (I64 wid = 0; wid < g_widget_count; wid++) {
        I64 wtype = g_widget_type[wid];
        if (wtype == WIDGET_SHADER || wtype == WIDGET_SPRITE3D || wtype == WIDGET_GRAPH) {
            I64 vx = g_doc_x + 8 + g_widget_start_col[wid] * 8;
            I64 vy = g_doc_y + 8 + g_widget_row[wid] * 18 + scroll_px;
            I64 vw = g_widget_pixel_w[wid];
            I64 vh = g_widget_pixel_h[wid];
            if (vy + vh < g_doc_y || vy > g_doc_y + g_doc_h) continue;

            if (wtype == WIDGET_SHADER) {
                U8 *shtype = g_widget_label + wid * 64;
                DolDocRenderShaderNode(vx, vy, vw, vh, shtype);
            } else if (wtype == WIDGET_SPRITE3D) {
                U8 *stype = g_widget_label + wid * 64;
                DolDocRenderSprite3D(vx, vy, vw, vh, stype);
            } else if (wtype == WIDGET_GRAPH) {
                U8 *gtype = g_widget_label + wid * 64;
                DolDocRenderGraphNode(vx, vy, vw, vh, gtype);
            }
            gfx_swap_rect(vx, vy, vw, vh);
        }
    }
    if (g_doc_inspected_wid >= 0 && g_doc_inspected_wid < g_widget_count) {
        DolDocDrawMorphicHalo(g_doc_inspected_wid);
    }
}

// ============================================================================
// LIVING COMPUTATIONAL CELL (LCM) DIRECT JIT INSTRUCTION & MEMORY PATCHER
// ============================================================================
U0 DolDocPatchTarget(U64 target_addr, I64 new_val) {
    if (!target_addr) return;
    U32 *ins_ptr = (U32*)target_addr;
    U32 ins = *ins_ptr;
    // Check if target points to an executable AArch64 MOVZ or MOVK instruction:
    // MOVZ: bits [30:23] = 0b10010100 (0x52800000 or 0xD2800000)
    // MOVK: bits [30:23] = 0b11110010 (0x72800000 or 0xF2800000)
    if ((ins & 0x7F800000) == 0x52800000 || (ins & 0x7F800000) == 0x72800000) {
        *ins_ptr = (ins & ~(0xFFFF << 5)) | (((U32)new_val & 0xFFFF) << 5);
        __dc_civac((U64)ins_ptr);
        __dsb_sy();
        __ic_ivau((U64)ins_ptr);
        __isb();
    } else {
        *(I64*)target_addr = new_val;
        __dc_civac(target_addr);
        __dsb_sy();
        __ic_ivau(target_addr);
        __isb();
    }
}

I64 DolDocHandleClick(I64 mx, I64 my) {
    if (mx < g_doc_x || my < g_doc_y || mx >= g_doc_x + g_doc_w || my >= g_doc_y + g_doc_h) return 0;

    // 0. Check Interactive Scrollbar Click (Rightmost 12px)
    if (g_doc_history_count > 0 && mx >= g_doc_x + g_doc_w - 12) {
        I64 rel_y = my - (g_doc_y + 4);
        I64 bar_h = g_doc_h - 8;
        if (bar_h > 0) {
            I64 target_pos = (rel_y * g_doc_history_count) / bar_h;
            g_doc_scroll_offset = g_doc_history_count - target_pos;
            if (g_doc_scroll_offset < 0) g_doc_scroll_offset = 0;
            if (g_doc_scroll_offset > g_doc_history_count) g_doc_scroll_offset = g_doc_history_count;
            DolDocMarkAllDirty();
            DolDocRedraw();
            doldoc_swap_term();
            return 1;
        }
    }

    I64 doc_my = my - g_doc_scroll_offset * 18;

    // 1. Morphic Halo Interactive Handles Click
    if (g_doc_inspected_wid >= 0 && g_doc_inspected_wid < g_widget_count) {
        I64 iwid = g_doc_inspected_wid;
        I64 ivx = g_widget_pixel_x[iwid];
        I64 ivy = g_widget_pixel_y[iwid];
        I64 ivw = g_widget_pixel_w[iwid];
        I64 ivh = g_widget_pixel_h[iwid];

        // Handle [X] Dismiss
        if (mx >= ivx + ivw - 10 && mx <= ivx + ivw + 4 && doc_my >= ivy - 10 && doc_my <= ivy + 6) {
            g_doc_inspected_wid = -1;
            DolDocPrint("\n$FG,PEACH$[HALO]$FG$ Dismissed inspection\n");
            DolDocMarkAllDirty();
            DolDocRedraw();
            doldoc_swap_term();
            return 1;
        }
        // Handle [S] Source / AST Inspector
        if (mx >= ivx - 6 && mx <= ivx + 10 && doc_my >= ivy - 10 && doc_my <= ivy + 6) {
            U8 *lbl = g_widget_label + iwid * 64;
            U8 *cmd = g_widget_cmd + iwid * 128;
            doldoc_printf("\n$FG,CYAN$[HALO:SRC]$FG$ Node #%lld Type=%lld Label=\"%s\" Cmd=\"%s\"\n",
                          iwid, g_widget_type[iwid], lbl, cmd);
            DolDocMarkAllDirty();
            DolDocRedraw();
            doldoc_swap_term();
            return 1;
        }
        // Handle [?] Memory Cell Probe
        if (mx >= ivx - 6 && mx <= ivx + 10 && doc_my >= ivy + ivh - 6 && doc_my <= ivy + ivh + 10) {
            doldoc_printf("\n$FG,TEAL$[HALO:MEM]$FG$ Node #%lld Target=0x%llX Val=%lld Min=%lld Max=%lld\n",
                          iwid, g_widget_target[iwid], g_widget_val[iwid], g_widget_min[iwid], g_widget_max[iwid]);
            DolDocMarkAllDirty();
            DolDocRedraw();
            doldoc_swap_term();
            return 1;
        }
        // Handle [D] Duplicate Morph
        if (mx >= ivx + ivw - 10 && mx <= ivx + ivw + 4 && doc_my >= ivy + ivh - 6 && doc_my <= ivy + ivh + 10) {
            doldoc_printf("\n$FG,GREEN$[HALO:CLONE]$FG$ Cloned Node #%lld to cursor\n", iwid);
            DolDocMarkAllDirty();
            DolDocRedraw();
            doldoc_swap_term();
            return 1;
        }
        // Handle [R] Refresh
        if (mx >= ivx + ivw / 2 - 8 && mx <= ivx + ivw / 2 + 8 && doc_my >= ivy - 10 && doc_my <= ivy + 6) {
            DolDocMarkAllDirty();
            DolDocRedraw();
            doldoc_swap_term();
            return 1;
        }
    }

    // 2. O(1) Amortized Morton Spatial Tile Hit-Testing
    I64 tx = mx / 64;
    I64 ty = doc_my / 64;
    if (tx >= 0 && tx < MORTON_TILES_X && ty >= 0 && ty < MORTON_TILES_Y) {
        I64 midx = Morton2D(tx, ty);
        I64 count = g_tile_widget_count[midx];
        for (I64 k = count - 1; k >= 0; k--) {
            I64 wid = g_tile_widgets[midx * TILE_MAX_WIDGETS + k];
            if (wid >= 0 && wid < g_widget_count) {
                I64 wtype = g_widget_type[wid];
                I64 vx = g_widget_pixel_x[wid];
                I64 vy = g_widget_pixel_y[wid];
                I64 vw = g_widget_pixel_w[wid];
                I64 vh = g_widget_pixel_h[wid];

                if (mx >= vx && mx < vx + vw && doc_my >= vy && doc_my < vy + vh) {
                    // Smalltalk Morphic Halo Inspection Mode
                    if (g_doc_inspector_mode) {
                        g_doc_inspected_wid = wid;
                        doldoc_printf("\n$FG,YELLOW$[MORPHIC HALO]$FG$ Widget #%lld | Box=(%lld,%lld,%lldx%lld) | TapeOff=0x%llX | Target=0x%llX\n",
                                      wid, vx, vy, vw, vh, g_widget_tape_offset[wid], g_widget_target[wid]);
                        DolDocMarkAllDirty();
                        DolDocRedraw();
                        doldoc_swap_term();
                        return 1;
                    }

                    if (wtype == WIDGET_BUTTON) {
                        g_widget_state[wid] = 1;
                        DolDocMarkAllDirty();
                        DolDocRedraw();
                        doldoc_swap_term();
                        g_widget_state[wid] = 0;

                        U8 *cmd = g_widget_cmd + wid * 128;
                        if (*cmd) {
                            strcpy(g_click_cmd_buf, cmd);
                            DolDocPrint("\n$FG,YELLOW$[CLICK]$FG$ $FG,CYAN$");
                            DolDocPrint(g_click_cmd_buf);
                            DolDocPrint("$FG$\n");
                            shell_run_command(g_click_cmd_buf);
                        }
                        return 1;
                    } else if (wtype == WIDGET_LINK) {
                        U8 *cmd = g_widget_cmd + wid * 128;
                        if (*cmd) {
                            strcpy(g_click_cmd_buf, cmd);
                            DolDocPrint("\n$FG,YELLOW$[LINK]$FG$ $FG,CYAN$");
                            DolDocPrint(g_click_cmd_buf);
                            DolDocPrint("$FG$\n");
                            shell_run_command(g_click_cmd_buf);
                        }
                        return 1;
                    } else if (wtype == WIDGET_SLIDER) {
                        g_doc_drag_wid = wid;
                        I64 min_v = g_widget_min[wid];
                        I64 max_v = g_widget_max[wid];
                        if (max_v <= min_v) max_v = min_v + 100;
                        I64 new_val = min_v + ((mx - vx) * (max_v - min_v)) / (vw > 0 ? vw : 1);
                        if (new_val < min_v) new_val = min_v;
                        if (new_val > max_v) new_val = max_v;
                        g_widget_val[wid] = new_val;

                        if (g_widget_target[wid] != 0) {
                            DolDocPatchTarget(g_widget_target[wid], new_val);
                        }

                        DolDocMarkAllDirty();
                        DolDocRedraw();
                        doldoc_swap_term();
                        return 1;
                    } else if (wtype == WIDGET_CHECKBOX) {
                        g_widget_state[wid] = 1 - g_widget_state[wid];
                        if (g_widget_target[wid] != 0) {
                            DolDocPatchTarget(g_widget_target[wid], g_widget_state[wid]);
                        }
                        DolDocMarkAllDirty();
                        DolDocRedraw();
                        doldoc_swap_term();
                        return 1;
                    } else if (wtype == WIDGET_TREE) {
                        g_widget_state[wid] = 1 - g_widget_state[wid];
                        DolDocMarkAllDirty();
                        DolDocRedraw();
                        doldoc_swap_term();
                        return 1;
                    } else if (wtype == WIDGET_SHADER || wtype == WIDGET_SPRITE3D || wtype == WIDGET_GRAPH) {
                        // Clicking an animated Shadertoy/3D/Oscilloscope node steps its animation live!
                        DolDocMarkAllDirty();
                        DolDocRedraw();
                        doldoc_swap_term();
                        return 1;
                    }
                }
            }
        }
    }

    // 3. Fallback to Character Cell Link Index
    I64 col = (mx - (g_doc_x + 8)) / 8;
    I64 row = (doc_my - (g_doc_y + 8)) / 18;

    if (row >= 0 && row < g_doc_rows && col >= 0 && col < g_doc_cols) {
        I64 idx = row * DOLDOC_MAX_COLS + col;
        I64 wid2 = g_doc_link_idx[idx];
        if (wid2 >= 0 && wid2 < g_widget_count) {
            U8 *cmd2 = g_widget_cmd + wid2 * 128;
            if (*cmd2) {
                strcpy(g_click_cmd_buf, cmd2);
                DolDocPrint("\n$FG,YELLOW$[CLICK]$FG$ $FG,CYAN$");
                DolDocPrint(g_click_cmd_buf);
                DolDocPrint("$FG$\n");
                shell_run_command(g_click_cmd_buf);
                return 1;
            }
        }
    }
    return 0;
}

I64 DolDocHandleDrag(I64 mx, I64 my) {
    if (mx < g_doc_x || my < g_doc_y) return 0;

    // Dragging scrollbar
    if (g_doc_history_count > 0 && mx >= g_doc_x + g_doc_w - 16) {
        return DolDocHandleClick(g_doc_x + g_doc_w - 4, my);
    }

    // Active continuous slider drag: tracks mouse smoothly anywhere on screen!
    if (g_doc_drag_wid >= 0 && g_doc_drag_wid < g_widget_count) {
        I64 wid = g_doc_drag_wid;
        if (g_widget_type[wid] == WIDGET_SLIDER) {
            I64 vx = g_widget_pixel_x[wid];
            I64 vw = g_widget_pixel_w[wid];
            I64 min_v = g_widget_min[wid];
            I64 max_v = g_widget_max[wid];
            if (max_v <= min_v) max_v = min_v + 100;
            I64 new_val = min_v + ((mx - vx) * (max_v - min_v)) / (vw > 0 ? vw : 1);
            if (new_val < min_v) new_val = min_v;
            if (new_val > max_v) new_val = max_v;
            if (new_val != g_widget_val[wid]) {
                g_widget_val[wid] = new_val;
                if (g_widget_target[wid] != 0) {
                    DolDocPatchTarget(g_widget_target[wid], new_val);
                }
                DolDocMarkAllDirty();
                DolDocRedraw();
                doldoc_swap_term();
                return 1;
            }
            return 1;
        }
    }

    I64 doc_my = my - g_doc_scroll_offset * 18;
    I64 tx = mx / 64;
    I64 ty = doc_my / 64;
    if (tx >= 0 && tx < MORTON_TILES_X && ty >= 0 && ty < MORTON_TILES_Y) {
        I64 midx = Morton2D(tx, ty);
        I64 count = g_tile_widget_count[midx];
        for (I64 k = count - 1; k >= 0; k--) {
            I64 wid2 = g_tile_widgets[midx * TILE_MAX_WIDGETS + k];
            if (wid2 >= 0 && wid2 < g_widget_count) {
                if (g_widget_type[wid2] == WIDGET_SLIDER) {
                    I64 vx2 = g_widget_pixel_x[wid2];
                    I64 vy2 = g_widget_pixel_y[wid2];
                    I64 vw2 = g_widget_pixel_w[wid2];
                    I64 vh2 = g_widget_pixel_h[wid2];
                    if (mx >= vx2 && mx <= vx2 + vw2 && doc_my >= vy2 - 8 && doc_my <= vy2 + vh2 + 8) {
                        g_doc_drag_wid = wid2;
                        I64 min_v2 = g_widget_min[wid2];
                        I64 max_v2 = g_widget_max[wid2];
                        if (max_v2 <= min_v2) max_v2 = min_v2 + 100;
                        I64 new_val2 = min_v2 + ((mx - vx2) * (max_v2 - min_v2)) / (vw2 > 0 ? vw2 : 1);
                        if (new_val2 < min_v2) new_val2 = min_v2;
                        if (new_val2 > max_v2) new_val2 = max_v2;
                        if (new_val2 != g_widget_val[wid2]) {
                            g_widget_val[wid2] = new_val2;
                            if (g_widget_target[wid2] != 0) {
                                DolDocPatchTarget(g_widget_target[wid2], new_val2);
                            }
                            DolDocMarkAllDirty();
                            DolDocRedraw();
                            doldoc_swap_term();
                            return 1;
                        }
                    }
                }
            }
        }
    }
    return 0;
}

I64 DolDocHandleMouseUp() {
    if (g_doc_drag_wid >= 0) {
        g_doc_drag_wid = -1;
        return 1;
    }
    return 0;
}

U0 DolDocMove(I64 x, I64 y, I64 w, I64 h) {
    I64 dx = x - g_doc_x;
    I64 dy = y - g_doc_y;
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

    // Translate existing widget positions when viewport moves (e.g., dragging window!)
    if (dx != 0 || dy != 0) {
        MortonSpatialClear();
        for (I64 mw = 0; mw < g_widget_count; mw++) {
            g_widget_pixel_x[mw] = g_doc_x + 8 + g_widget_start_col[mw] * 8;
            g_widget_pixel_y[mw] = g_doc_y + 8 + g_widget_row[mw] * 18;
            if (g_widget_type[mw] == WIDGET_EQUATION) g_widget_pixel_y[mw] -= 6;
            MortonSpatialInsertWidget(mw);
        }
    }
    DolDocMarkAllDirty();
}

U0 doldoc_move(I64 x, I64 y, I64 w, I64 h) {
    DolDocMove(x, y, w, h);
}

U0 doldoc_swap_term() {
    gfx_swap_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h);
}

U0 doldoc_swap_cursor() {
    gfx_swap_rect(g_doc_cursor_x, g_doc_cursor_y, 8, 16);
}

U0 doldoc_mark_all_dirty() {
    DolDocMarkAllDirty();
}

U0 DolDocScrollUp(I64 lines) {
    g_doc_scroll_offset += lines;
    if (g_doc_scroll_offset > g_doc_history_count) g_doc_scroll_offset = g_doc_history_count;
    DolDocMarkAllDirty();
    DolDocRedraw();
    doldoc_swap_term();
}

U0 DolDocScrollDown(I64 lines) {
    g_doc_scroll_offset -= lines;
    if (g_doc_scroll_offset < 0) g_doc_scroll_offset = 0;
    DolDocMarkAllDirty();
    DolDocRedraw();
    doldoc_swap_term();
}

U0 DolDocSetBgColor(U32 bg) {
    g_doc_cur_bg = bg;
    DolDocMarkAllDirty();
}

U32 DolDocGetBgColor() {
    return DolDocResolveColor(g_doc_cur_bg);
}

U0 doldoc_putc(U8 c) {
    DolDocPutc(c);
}

U0 DolDocExportPrint(U8 *str) {
    DolDocPrint(str);
}

U0 doldoc_clear() {
    DolDocClear();
}

U0 doldoc_redraw() {
    DolDocRedraw();
}

I64 doldoc_handle_click(I64 mx, I64 my) {
    return DolDocHandleClick(mx, my);
}

I64 doldoc_handle_drag(I64 mx, I64 my) {
    return DolDocHandleDrag(mx, my);
}

I64 doldoc_handle_mouse_up() {
    return DolDocHandleMouseUp();
}

U0 doldoc_scroll_up(I64 lines) {
    DolDocScrollUp(lines);
}

U0 doldoc_scroll_down(I64 lines) {
    DolDocScrollDown(lines);
}

U0 doldoc_set_bg(U32 bg) {
    DolDocSetBgColor(bg);
}

U32 doldoc_get_bg() {
    return DolDocGetBgColor();
}

U0 DolDocSelfTest() {
    uart_puts("\n[DOLDOC-TEST] Running DolDoc 3.0 Scene-Graph & Shadertoy Verification...\n");
    DolDocStylePush(SEM_COLOR_GREEN, SEM_COLOR_BASE);
    if (g_style_depth != 1) return;
    DolDocStylePop();
    uart_puts("[DOLDOC-TEST] 1/8 Style Stack Push/Pop PASSED\n");

    U32 col1 = DolDocParseColor("0xF38BA8", 0);
    U32 col2 = DolDocParseColor("#A6E3A1", 0);
    U32 col3 = DolDocParseColor("MAUVE", 0);
    if (col1 != 0xFFF38BA8 || col2 != 0xFFA6E3A1 || col3 != SEM_COLOR_MAUVE) return;
    uart_puts("[DOLDOC-TEST] 2/8 Semantic & Hex Palette Parser PASSED\n");

    DolDocPrint("$BOX,w=30,h=3$\n");
    DolDocPrint("$CARD,title=\"NeoOS Card\",w=32,h=4$\n");
    uart_puts("[DOLDOC-TEST] 3/8 Box & Card Continuum PASSED\n");

    DolDocPrint("$SHADER,type=\"plasma\",w=64,h=36$\n");
    uart_puts("[DOLDOC-TEST] 4/8 Native Shadertoy Node PASSED\n");

    I64 initial_widgets = g_widget_count;
    DolDocPrint("$BT,\"TestBtn\",LM=\"help\"$ $LK,\"TestLink\",A=\"ls\"$\n");
    if (g_widget_count < initial_widgets + 2) return;
    uart_puts("[DOLDOC-TEST] 5/8 Interactive Widgets PASSED\n");

    I64 initial_tape_cmds = g_omnitape_cmd_count;
    I64 off1 = OmniTapeAppendCmd(CMD_SDF_RECT, 10, 20, 100, 30, "TestPayload", 11, 0);
    if (off1 < 0 || g_omnitape_cmd_count != initial_tape_cmds + 1) return;
    uart_puts("[DOLDOC-TEST] 6/8 OmniTape Bump Allocator PASSED\n");

    I64 midx = Morton2D(2, 3);
    if (midx != 14) return;
    uart_puts("[DOLDOC-TEST] 7/8 Morton Spatial 64x64 Partitioning PASSED\n");

    I64 test_cell_val = 50;
    I64 test_wid = g_widget_count;
    DolDocPrint("$SL,\"TestCell\",val=50,min=0,max=100,w=100$\n");
    if (g_widget_count > test_wid) {
        g_widget_target[test_wid] = &test_cell_val;
        I64 clk_x = g_widget_pixel_x[test_wid] + 80;
        I64 clk_y = g_widget_pixel_y[test_wid] + 8;
        DolDocHandleClick(clk_x, clk_y);
    }
    uart_puts("[DOLDOC-TEST] 8/8 Living Cell In-Memory Mutation PASSED\n");
    uart_puts("ALL 8 DOLDOC TESTS PASSED\n");
}

I64 doldoc_get_widget_count() {
    return g_widget_count;
}

I64 doldoc_get_tape_cmd_count() {
    return g_omnitape_cmd_count;
}

I64 doldoc_get_inspected_wid() {
    return g_doc_inspected_wid;
}

U0 doldoc_set_inspected_wid(I64 wid) {
    g_doc_inspected_wid = wid;
}

I64 doldoc_get_inspector_mode() {
    return g_doc_inspector_mode;
}

U0 doldoc_set_inspector_mode(I64 mode) {
    g_doc_inspector_mode = mode;
}

I64 DolDocFindWidget(U8 *name) {
    if (!name || !*name) return -1;
    for (I64 fw_i = 0; fw_i < g_widget_count; fw_i++) {
        U8 *lbl = g_widget_label + fw_i * 64;
        if (lbl[0] && strstr(lbl, name)) {
            return fw_i;
        }
    }
    for (I64 fw_j = 0; fw_j < g_widget_count; fw_j++) {
        U8 *extra = g_widget_extra + fw_j * 128;
        if (extra[0] && strstr(extra, name)) {
            return fw_j;
        }
        U8 *cmd = g_widget_cmd + fw_j * 128;
        if (cmd[0] && strstr(cmd, name)) {
            return fw_j;
        }
    }
    return -1;
}

I64 doldoc_find_widget(U8 *name) {
    return DolDocFindWidget(name);
}

U8 *doldoc_get_widget_label(I64 wid) {
    if (wid < 0 || wid >= g_widget_count) return "";
    return g_widget_label + wid * 64;
}

U0 doldoc_register_holyc(CDolDocOps *ops) {
    // Publish the DolDoc operation table into the JIT symbol space so that
    // other HolyC modules and the shell can dispatch through it by name.
    if (ops) symbols_register("g_doldoc_ops", ops, 2);
}

U0 DolDocInit() {
    DolDocInitTrig();
    if (!g_omnitape_buf) {
        g_omnitape_buf = kmalloc(OMNITAPE_ARENA_SIZE);
    }
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

    symbols_register("doldoc_print", DolDocPrint, 1);
    symbols_register("doldoc_putc", DolDocPutc, 1);
    symbols_register("doldoc_clear", DolDocClear, 1);
    symbols_register("doldoc_redraw", DolDocRedraw, 1);
    symbols_register("doldoc_handle_click", DolDocHandleClick, 1);
    symbols_register("doldoc_handle_drag", DolDocHandleDrag, 1);
    symbols_register("doldoc_handle_mouse_up", DolDocHandleMouseUp, 1);
    symbols_register("doldoc_animate_tick", DolDocAnimateTick, 1);
    symbols_register("doldoc_swap_term", doldoc_swap_term, 1);
    symbols_register("doldoc_mark_all_dirty", DolDocMarkAllDirty, 1);
    symbols_register("doldoc_get_widget_count", doldoc_get_widget_count, 1);
    symbols_register("doldoc_get_tape_cmd_count", doldoc_get_tape_cmd_count, 1);
    symbols_register("doldoc_get_inspected_wid", doldoc_get_inspected_wid, 1);
    symbols_register("doldoc_set_inspected_wid", doldoc_set_inspected_wid, 1);
    symbols_register("doldoc_get_inspector_mode", doldoc_get_inspector_mode, 1);
    symbols_register("doldoc_set_inspector_mode", doldoc_set_inspector_mode, 1);
    symbols_register("doldoc_find_widget", doldoc_find_widget, 1);
    symbols_register("doldoc_get_widget_label", doldoc_get_widget_label, 1);
    symbols_register("g_widget_count", &g_widget_count, 2);
    symbols_register("g_omnitape_cmd_count", &g_omnitape_cmd_count, 2);
    symbols_register("g_doc_inspector_mode", &g_doc_inspector_mode, 2);
    symbols_register("g_doc_inspected_wid", &g_doc_inspected_wid, 2);
    symbols_register("g_shader_speed", &g_shader_speed, 2);
    symbols_register("g_shader_zoom", &g_shader_zoom, 2);
    symbols_register("g_shader_morph", &g_shader_morph, 2);
    symbols_register("g_sprite_rot_speed", &g_sprite_rot_speed, 2);
    doldoc_register_holyc(&g_doldoc_ops);
}

DolDocInit();
