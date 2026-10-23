// ==============================================================================
// DolDoc.HC - Sovereign Pure HolyC DolDoc 3.0 CDoc/CTree Continuum  (P5)
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
//
// P5 rewrite: the fixed character grid (g_doc_chars/fg/bg, g_doc_link_idx,
// g_hist_chars) and the parallel g_widget_* tables are GONE. A document is now a
// genuine CDoc/CTree: a flat, index-linked tree of CDocNode entries whose text
// lives in a contiguous arena with a PER-CHARACTER attribute word (fg|bg). The
// full TempleOS two-letter tag set is parsed ($TX CR SR CU TB CL PB PL LM RM HD
// FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI), plus $WIN$
// windows, $SPLIT$/$BLUR$/$ELEV$ and reactive cells ($DA/$SL target= binding).
//
// WM.HC and Compositor.HC are dissolved here: windows are documents ($WIN$),
// the desktop is a document, damage/present/effects live in this module.
// ==============================================================================

#define DOC_MAX_NODES     2048
#define DOC_MAX_TEXT      65536
#define DOC_MAX_ARGS      32768
#define DOC_MAX_WINDOWS   8
#define DOC_MAX_MACROS    32
#define DOC_MAX_ANCHORS   64
#define DOC_MAX_ATTRS     4096

// ---- Node kinds (the CDoc/CTree entry vocabulary) ----------------------------
#define DOC_ROOT       0
#define DOC_TEXT       1
#define DOC_LINK       2
#define DOC_BUTTON     3
#define DOC_DATA       4
#define DOC_SLIDER     5
#define DOC_TOGGLE     6
#define DOC_PROGRESS   7
#define DOC_TREE       8
#define DOC_BITMAP     9
#define DOC_SCENE3D    10
#define DOC_SHADER     11
#define DOC_GRAPH      12
#define DOC_MACRO      13
#define DOC_INCLUDE    14
#define DOC_ANCHOR     15
#define DOC_WINDOW     16
#define DOC_SPLIT      17
#define DOC_EQ         18
#define DOC_RULE       19
#define DOC_CARD       20
#define DOC_BOX        21
#define DOC_GLASS      22
#define DOC_SHADOW     23
#define DOC_FONT       24
#define DOC_INPUT      25

// ---- Node flags --------------------------------------------------------------
#define DOCF_OPEN      1
#define DOCF_ACTIVE    2
#define DOCF_MIN       4
#define DOCF_MAX       8
#define DOCF_ELEV      16
#define DOCF_BLUR      32
#define DOCF_WRAP      64
#define DOCF_INVERT    128

// Semantic Color Token IDs (resolved dynamically via g_theme at render time)
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

// ============================================================================
// CDocNode - one entry in the document tree
// ============================================================================
class CDocNode {
    I64 kind;
    I64 flags;
    I64 parent;
    I64 first;
    I64 last;
    I64 next;
    I64 prev;
    I64 x;
    I64 y;
    I64 w;
    I64 h;
    I64 val;
    I64 min;
    I64 max;
    U64 target;
    I64 text_off;
    I64 text_len;
    I64 arg_off;
    U32 fg;
    U32 bg;
    I64 state;
    I64 win_id;
};

// Live reactive parameters for shaders, 3D sprites & oscilloscopes
I64 g_shader_speed       = 50;
I64 g_shader_zoom        = 40;
I64 g_shader_morph       = 60;
I64 g_sprite_rot_speed   = 50;
I64 g_doc_inspector_mode = 0;
I64 g_doc_inspected_nid  = -1;
I64 g_doc_anim_tick      = 0;

// Telemetry ring buffers for $PL$ / $GRAPH$ oscilloscopes
I64 g_osc_sine_buf[64];
I64 g_osc_fps_buf[64];
I64 g_osc_head = 0;

// Fast integer sine table (64 entries, -256..256)
I64 g_doc_sin64[64];
I64 g_doc_trig_ready = 0;
I64 g_cube_px[8];
I64 g_cube_py[8];

U0 DolDocInitTrig() {
    if (g_doc_trig_ready) return;
    g_doc_sin64[0]  = 0;   g_doc_sin64[1]  = 25;  g_doc_sin64[2]  = 50;  g_doc_sin64[3]  = 74;
    g_doc_sin64[4]  = 98;  g_doc_sin64[5]  = 121; g_doc_sin64[6]  = 142; g_doc_sin64[7]  = 162;
    g_doc_sin64[8]  = 181; g_doc_sin64[9]  = 198; g_doc_sin64[10] = 213; g_doc_sin64[11] = 226;
    g_doc_sin64[12] = 237; g_doc_sin64[13] = 245; g_doc_sin64[14] = 251; g_doc_sin64[15] = 255;
    g_doc_sin64[16] = 256;
    for (I64 ti = 1; ti < 16; ti++) g_doc_sin64[16 + ti] = g_doc_sin64[16 - ti];
    for (I64 ti2 = 0; ti2 < 32; ti2++) g_doc_sin64[32 + ti2] = -g_doc_sin64[ti2];
    for (I64 oi = 0; oi < 64; oi++) {
        g_osc_sine_buf[oi] = g_doc_sin64[oi];
        g_osc_fps_buf[oi]  = 60 + (g_doc_sin64[(oi * 3) & 63] / 32);
    }
    g_doc_trig_ready = 1;
}

I64 DocFastSin(I64 idx) { if (!g_doc_trig_ready) DolDocInitTrig(); return g_doc_sin64[idx & 63]; }
I64 DocFastCos(I64 idx) { if (!g_doc_trig_ready) DolDocInitTrig(); return g_doc_sin64[(idx + 16) & 63]; }

// Resolve a semantic colour token (or legacy hex) against the live theme palette
U32 DolDocResolveColor(U32 col) {
    if (g_theme.bg_base == 0) {
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

// ============================================================================
// Document storage: flat node arena + per-character text/attr arena
// ============================================================================
CDocNode g_doc_nodes[DOC_MAX_NODES];
U8  g_doc_text[DOC_MAX_TEXT];
U64 g_doc_attr[DOC_MAX_TEXT];       // low 32 = fg token, high 32 = bg token
U8  g_doc_args[DOC_MAX_ARGS];
I64 g_doc_node_count = 0;
I64 g_doc_text_used  = 0;
I64 g_doc_args_used  = 0;
I64 g_doc_root       = 0;
I64 g_doc_cur        = 0;           // flow parent (usually root)
I64 g_doc_cur_run    = -1;          // current single-line text run
I64 g_doc_col        = 0;
I64 g_doc_row        = 0;
I64 g_doc_cols       = 126;
I64 g_doc_rows       = 41;

// Viewport geometry
I64 g_doc_x = 0;
I64 g_doc_y = 0;
I64 g_doc_w = 1024;
I64 g_doc_h = 768;

// Flow style (colour stack + margins + wrap)
U32 g_doc_cur_fg = SEM_COLOR_TEXT;
U32 g_doc_cur_bg = SEM_COLOR_MANTLE;
U32 g_doc_fg_stack[16];
U32 g_doc_bg_stack[16];
I64 g_style_depth = 0;
I64 g_doc_lmargin = 0;
I64 g_doc_rmargin = 126;
I64 g_doc_wrap    = 1;
I64 g_doc_underline = 0;

// Cursor
I64 g_doc_cursor_x = 8;
I64 g_doc_cursor_y = 8;
I64 g_doc_cursor_visible = 1;

// Dirty tracking: one bit per row (fixed: 64-bit shift) + whole-doc flag
U64 g_doc_dirty_mask = -1;
I64 g_doc_dirty = 1;
I64 g_doc_quiet = 0;
I64 g_doc_scroll_offset = 0;
I64 g_doc_drag_nid = -1;

// ============================================================================
// Compositor state (dissolved from Compositor.HC). Declared before any use so
// that functions earlier in the module resolve `g_comp` to the real struct.
// ============================================================================
class CCompositorState {
    I64 screen_w;
    I64 screen_h;
    I64 screen_pitch;
    I64 vsync_hz;
    I64 shadows_enabled;
    I64 glass_enabled;
    I64 rounded_corners;
    I64 dirty_blit_enabled;
    I64 frame_count;
    I64 fps;
    I64 last_fps_time_sec;
    I64 frame_time_us;
    I64 last_frame_start_us;
};
CCompositorState g_comp;
I64 g_doc_comp_ready = 0;

// ============================================================================
// P6 action protocol — documents EMIT actions; the Shell EXECUTES them. This is
// the seam that breaks the DolDoc -> Shell cycle: DolDoc never names a Shell
// function, it only enqueues actions (and calls a Shell-registered pump via a
// function pointer).
// ============================================================================
#define DOC_ACT_NONE  0
#define DOC_ACT_RUN   1
#define DOC_ACT_OPEN  2
#define DOC_ACT_SET   3
#define DOC_ACT_CLONE 4
#define DOC_ACT_FOCUS 5
#define DOC_ACT_Q     64

class CDocAction {
    I64 kind;
    I64 target_id;
    I64 val;
    U8  payload[128];
};
CDocAction g_doc_act_q[DOC_ACT_Q];
I64 g_doc_act_head = 0;
I64 g_doc_act_tail = 0;
U64 g_doc_pump_cb = 0;   // Shell registers its input/action pump here

I64 DolDocPushAction(I64 kind, I64 target_id, I64 val, U8 *payload) {
    I64 next = (g_doc_act_head + 1) % DOC_ACT_Q;
    if (next == g_doc_act_tail) return 0;   // queue full
    CDocAction *ac = &g_doc_act_q[g_doc_act_head];
    ac->kind = kind; ac->target_id = target_id; ac->val = val;
    I64 i = 0;
    if (payload) { while (payload[i] && i < 127) { ac->payload[i] = payload[i]; i++; } }
    ac->payload[i] = 0;
    g_doc_act_head = next;
    return 1;
}

I64 DolDocPollAction(I64 *out_kind, I64 *out_target, I64 *out_val, U8 *out_payload) {
    if (g_doc_act_tail == g_doc_act_head) return 0;
    CDocAction *ac = &g_doc_act_q[g_doc_act_tail];
    *out_kind = ac->kind; *out_target = ac->target_id; *out_val = ac->val;
    if (out_payload) { I64 i = 0; while (ac->payload[i] && i < 127) { out_payload[i] = ac->payload[i]; i++; } out_payload[i] = 0; }
    g_doc_act_tail = (g_doc_act_tail + 1) % DOC_ACT_Q;
    return 1;
}

I64 DolDocActionCount() {
    I64 n = g_doc_act_head - g_doc_act_tail;
    if (n < 0) n += DOC_ACT_Q;
    return n;
}

U0 DolDocSetPump(U64 fn) { g_doc_pump_cb = fn; }

// Anchors & macros
U8  g_doc_anchor_names[DOC_MAX_ANCHORS * 32];
I64 g_doc_anchor_nodes[DOC_MAX_ANCHORS];
I64 g_doc_anchor_count = 0;
U8  g_doc_macro_names[DOC_MAX_MACROS * 32];
U8  g_doc_macro_bodies[DOC_MAX_MACROS * 256];
I64 g_doc_macro_count = 0;

// ============================================================================
// OmniTape: every CDocNode compiles to one 64-byte command record
// ============================================================================
#define OMNITAPE_ARENA_SIZE 1048576
#define OMNITAPE_MAGIC      0x544150454E454F31
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

I64 OmniTapeAppendNode(I64 nid) {
    if (!g_omnitape_buf) return -1;
    CDocNode *nd = &g_doc_nodes[nid];
    I64 aligned = ((g_omnitape_tail + 63) / 64) * 64;
    I64 total = 64 + nd->text_len + 1;
    if (aligned + total >= OMNITAPE_ARENA_SIZE) return -1;
    CTapeCmdHeader *hdr = g_omnitape_buf + aligned;
    hdr->opcode = nd->kind;
    hdr->flags = nid;
    hdr->payload_size = nd->text_len;
    hdr->rel_child_offset = nd->first;
    hdr->box_x = nd->x;
    hdr->box_y = nd->y;
    hdr->box_w = nd->w;
    hdr->box_h = nd->h;
    U8 *dst = g_omnitape_buf + aligned + 64;
    for (I64 i = 0; i < nd->text_len; i++) dst[i] = g_doc_text[nd->text_off + i];
    dst[nd->text_len] = 0;
    g_omnitape_tail = aligned + ((total + 63) / 64) * 64;
    g_omnitape_cmd_count++;
    return aligned;
}

// ============================================================================
// Tree primitives
// ============================================================================
U0 DolDocLink(I64 parent, I64 n) {
    CDocNode *p = &g_doc_nodes[parent];
    CDocNode *c = &g_doc_nodes[n];
    c->parent = parent;
    c->next = -1;
    c->prev = p->last;
    if (p->last >= 0) g_doc_nodes[p->last].next = n;
    else p->first = n;
    p->last = n;
}

U0 DolDocUnlink(I64 n) {
    CDocNode *c = &g_doc_nodes[n];
    I64 p = c->parent;
    if (p >= 0) {
        if (g_doc_nodes[p].first == n) g_doc_nodes[p].first = c->next;
        if (g_doc_nodes[p].last == n) g_doc_nodes[p].last = c->prev;
    }
    if (c->prev >= 0) g_doc_nodes[c->prev].next = c->next;
    if (c->next >= 0) g_doc_nodes[c->next].prev = c->prev;
    c->next = -1; c->prev = -1;
}

I64 DolDocNewNode(I64 kind, I64 parent) {
    if (g_doc_node_count >= DOC_MAX_NODES) return -1;
    I64 n = g_doc_node_count;
    g_doc_node_count++;
    CDocNode *nd = &g_doc_nodes[n];
    nd->kind = kind; nd->flags = 0;
    nd->parent = parent; nd->first = -1; nd->last = -1; nd->next = -1; nd->prev = -1;
    nd->x = 0; nd->y = 0; nd->w = 0; nd->h = 0;
    nd->val = 0; nd->min = 0; nd->max = 100; nd->target = 0;
    nd->text_off = 0; nd->text_len = 0; nd->arg_off = 0;
    nd->fg = SEM_COLOR_TEXT; nd->bg = SEM_COLOR_MANTLE;
    nd->state = 0; nd->win_id = 0;
    if (parent >= 0) DolDocLink(parent, n);
    return n;
}

I64 DolDocArgStore(U8 *tag) {
    if (!tag) return 0;
    I64 len = strlen(tag);
    if (g_doc_args_used + len + 1 >= DOC_MAX_ARGS) return 0;
    I64 off = g_doc_args_used;
    for (I64 i = 0; i < len; i++) g_doc_args[off + i] = tag[i];
    g_doc_args[off + len] = 0;
    g_doc_args_used += len + 1;
    return off;
}

// ============================================================================
// Text arena (per-character attributes)
// ============================================================================
I64 DolDocNewRun(I64 parent, I64 px, I64 py) {
    I64 n = DolDocNewNode(DOC_TEXT, parent);
    if (n < 0) return -1;
    CDocNode *nd = &g_doc_nodes[n];
    nd->x = px; nd->y = py; nd->h = 18; nd->w = 0;
    nd->text_off = g_doc_text_used; nd->text_len = 0;
    return n;
}

U0 DolDocRunPutc(I64 n, U8 c, U32 fg, U32 bg) {
    if (n < 0 || g_doc_text_used >= DOC_MAX_TEXT) return;
    CDocNode *nd = &g_doc_nodes[n];
    I64 off = nd->text_off + nd->text_len;
    g_doc_text[off] = c;
    g_doc_attr[off] = ((U64)bg << 32) | (U64)(fg & 0xFFFFFFFF);
    nd->text_len++;
    nd->w = nd->text_len * 8;
    g_doc_text_used = off + 1;
}

U0 DolDocRunAppendStr(I64 n, U8 *s, U32 fg, U32 bg) {
    if (!s) return;
    for (I64 i = 0; s[i]; i++) DolDocRunPutc(n, s[i], fg, bg);
}

// ============================================================================
// Style stack / flow helpers
// ============================================================================
U0 DolDocStylePush(U32 fg, U32 bg) {
    if (g_style_depth < 15) {
        g_doc_fg_stack[g_style_depth] = g_doc_cur_fg;
        g_doc_bg_stack[g_style_depth] = g_doc_cur_bg;
        g_style_depth++;
    }
    g_doc_cur_fg = fg; g_doc_cur_bg = bg;
}

U0 DolDocStylePop() {
    if (g_style_depth > 0) {
        g_style_depth--;
        g_doc_cur_fg = g_doc_fg_stack[g_style_depth];
        g_doc_cur_bg = g_doc_bg_stack[g_style_depth];
    }
}

U0 DolDocUpdateCursor() {
    g_doc_cursor_x = g_doc_x + 8 + g_doc_col * 8;
    g_doc_cursor_y = g_doc_y + 8 + g_doc_row * 18;
}

I64 DolDocEnsureRun() {
    if (g_doc_cur_run < 0) {
        g_doc_cur_run = DolDocNewRun(g_doc_cur, g_doc_x + 8 + g_doc_col * 8, g_doc_y + 8 + g_doc_row * 18);
    }
    return g_doc_cur_run;
}

U0 DolDocBreakRun() { g_doc_cur_run = -1; }

// Word-wrap: split the current run at its last space, moving the tail to a new
// line. Returns 1 if a wrap happened.
I64 DolDocWordWrap() {
    I64 r = g_doc_cur_run;
    if (r < 0) return 0;
    CDocNode *nd = &g_doc_nodes[r];
    I64 sp = -1;
    for (I64 k = nd->text_len - 1; k >= 0; k--) {
        if (g_doc_text[nd->text_off + k] == ' ') { sp = k; break; }
    }
    if (sp <= 0) return 0;
    I64 tail = nd->text_len - sp - 1;
    if (tail <= 0) { nd->text_len = sp; nd->w = sp * 8; g_doc_text_used = nd->text_off + sp; }
    // new row
    g_doc_row++;
    if (g_doc_row >= g_doc_rows) { DolDocScroll(); return 1; }
    I64 n2 = DolDocNewRun(g_doc_cur, g_doc_x + 8, g_doc_y + 8 + g_doc_row * 18);
    if (tail > 0 && n2 >= 0) {
        for (I64 i = 0; i < tail; i++) {
            I64 si = nd->text_off + sp + 1 + i;
            U32 fgc = (U32)(g_doc_attr[si] & 0xFFFFFFFF);
            U32 bgc = (U32)(g_doc_attr[si] >> 32);
            DolDocRunPutc(n2, g_doc_text[si], fgc, bgc);
        }
    }
    nd->text_len = sp; nd->w = sp * 8;
    g_doc_text_used = nd->text_off + sp;
    g_doc_cur_run = n2;
    g_doc_col = tail;
    DolDocUpdateCursor();
    return 1;
}

U0 DolDocScroll() {
    if (g_doc_rows > 1) {
        // Archive the oldest line (the topmost text run) is implicit: the tree
        // already retains every run. We only shift the live flow upward.
        for (I64 i = 0; i < g_doc_node_count; i++) {
            CDocNode *nd = &g_doc_nodes[i];
            if (nd->kind != DOC_WINDOW && nd->y > g_doc_y - 200) nd->y -= 18;
        }
        g_doc_row = g_doc_rows - 1;
        g_doc_cur_run = -1;
        DolDocUpdateCursor();
    }
    DolDocMarkAllDirty();
}

U0 DolDocBackspace() {
    if (g_doc_cur_run < 0) return;
    CDocNode *nd = &g_doc_nodes[g_doc_cur_run];
    if (nd->text_len > 0) {
        nd->text_len--;
        nd->w = nd->text_len * 8;
        g_doc_text_used = nd->text_off + nd->text_len;
        if (g_doc_col > 0) g_doc_col--;
        DolDocUpdateCursor();
        gfx_draw_rect(g_doc_cursor_x, g_doc_cursor_y, 8, 16, DolDocResolveColor(g_doc_cur_bg));
    }
}

U0 doldoc_backspace() { DolDocBackspace(); }

U0 DolDocDrawCursor(I64 visible) {
    U32 color = visible ? DolDocResolveColor(SEM_COLOR_SKY) : DolDocResolveColor(g_doc_cur_bg);
    gfx_draw_rect(g_doc_cursor_x, g_doc_cursor_y + 1, 2, 14, color);
}

U0 doldoc_draw_cursor(I64 visible) { DolDocDrawCursor(visible); }

// ============================================================================
// Character flow (drives the text runs; wraps at words or characters)
// ============================================================================
U0 DolDocPutc(U8 c) {
    if (g_doc_scroll_offset != 0) { g_doc_scroll_offset = 0; DolDocMarkAllDirty(); }
    g_doc_dirty = 1;
    if (c == 10) {
        if (!g_doc_quiet) { uart_putc(13); uart_putc(10); }
        DolDocBreakRun();
        g_doc_col = 0; g_doc_row++;
        if (g_doc_row >= g_doc_rows) DolDocScroll();
        else DolDocUpdateCursor();
        return;
    }
    if (c == 13) { if (!g_doc_quiet) uart_putc(13); g_doc_col = 0; DolDocUpdateCursor(); return; }
    if (c == 8) { if (!g_doc_quiet) { uart_putc(8); uart_putc(32); uart_putc(8); } DolDocBackspace(); return; }
    if (c == 9) { DolDocPutc(' '); DolDocPutc(' '); DolDocPutc(' '); DolDocPutc(' '); return; }

    if (!g_doc_quiet) uart_putc(c);
    if (g_doc_row >= g_doc_rows) return;

    // word-wrap before overflow
    if (g_doc_wrap && g_doc_col >= g_doc_cols - 1 && c != ' ') {
        if (DolDocWordWrap()) return;
    }

    I64 r = DolDocEnsureRun();
    DolDocRunPutc(r, c, g_doc_cur_fg, g_doc_cur_bg);
    g_doc_col++;
    if (g_doc_col >= g_doc_cols) {
        DolDocBreakRun();
        g_doc_col = 0; g_doc_row++;
        if (g_doc_row >= g_doc_rows) DolDocScroll();
    }
    DolDocUpdateCursor();
}

// ============================================================================
// Tag attribute parsing helpers
// ============================================================================
U8  g_tag_buf[2048];
U8  g_tag_label[256];
U8  g_tag_cmd[256];
U8  g_tag_title[256];
U8  g_click_cmd_buf[256];
U8  g_doc_inc_buf[4096];

U8* DolDocParseQuoted(U8 *p, U8 *out, I64 max_out) {
    if (!p) return 0;
    if (!out) return p;
    while (*p && *p != '"') p++;
    if (!*p) { out[0] = 0; return p; }
    p++;
    I64 idx = 0;
    while (*p && *p != '"' && idx < max_out - 1) { out[idx] = *p; idx++; p++; }
    out[idx] = 0;
    if (*p == '"') p++;
    return p;
}

I64 DolDocAtoi(U8 *p) {
    if (!p) return 0;
    I64 neg = 0;
    if (*p == '-') { neg = 1; p++; }
    I64 res = 0;
    while (*p >= '0' && *p <= '9') { res = res * 10 + (*p - '0'); p++; }
    return neg ? -res : res;
}

U8* DolDocFindKey(U8 *tag, U8 *key) { if (!tag || !key) return 0; return strstr(tag, key); }

I64 DolDocGetAttrInt(U8 *tag, U8 *key, I64 def_val) {
    U8 *p = DolDocFindKey(tag, key);
    if (!p) return def_val;
    p += strlen(key);
    while (*p == ' ' || *p == '=') p++;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2; I64 val = 0;
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
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
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
    if (*p == '"') { DolDocParseQuoted(p, out, max_len); return; }
    I64 i = 0;
    while (*p && *p != ',' && *p != '$' && i < max_len - 1) { out[i] = *p; i++; p++; }
    out[i] = 0;
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
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
    U32 h = 0; I64 digits = 0;
    while ((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F')) {
        h = h << 4;
        if (*p >= '0' && *p <= '9') h |= (*p - '0');
        else if (*p >= 'a' && *p <= 'f') h |= (*p - 'a' + 10);
        else if (*p >= 'A' && *p <= 'F') h |= (*p - 'A' + 10);
        p++; digits++;
    }
    if (digits == 6) return 0xFF000000 | h;
    if (digits == 8) return h;
    return def_col;
}

U0 DolDocMarkAllDirty() { g_doc_dirty_mask = -1; g_doc_dirty = 1; }

U0 DolDocMarkRowDirty(I64 r) {
    if (r >= 0 && r < 64) g_doc_dirty_mask = g_doc_dirty_mask | (((U64)1) << r);
    else g_doc_dirty_mask = -1;
    g_doc_dirty = 1;
}

U0 doldoc_mark_all_dirty() { DolDocMarkAllDirty(); }

// ============================================================================
// Reactive cells: bind a node value to a live memory word and patch it
// ============================================================================
U0 DolDocPatchTarget(U64 target_addr, I64 new_val) {
    if (!target_addr) return;
    U32 *ins_ptr = (U32*)target_addr;
    U32 ins = *ins_ptr;
    if ((ins & 0x7F800000) == 0x52800000 || (ins & 0x7F800000) == 0x72800000) {
        *ins_ptr = (ins & ~(0xFFFF << 5)) | (((U32)new_val & 0xFFFF) << 5);
        __dc_civac((U64)ins_ptr); __dsb_sy(); __ic_ivau((U64)ins_ptr); __isb();
    } else {
        *(I64*)target_addr = new_val;
        __dc_civac(target_addr); __dsb_sy(); __ic_ivau(target_addr); __isb();
    }
}

U0 DolDocCellWrite(I64 nid, I64 new_val) {
    if (nid < 0 || nid >= g_doc_node_count) return;
    CDocNode *nd = &g_doc_nodes[nid];
    if (new_val < nd->min) new_val = nd->min;
    if (new_val > nd->max) new_val = nd->max;
    nd->val = new_val;
    if (nd->target != 0) DolDocPatchTarget(nd->target, new_val);
    DolDocMarkRowDirty(nd->y / 18);
}

// ============================================================================
// Node constructors for the widget/tag vocabulary
// ============================================================================
I64 g_widget_count = 0;

I64 DolDocWidget(I64 kind, I64 px, I64 py, I64 pw, I64 ph, U8 *tag) {
    I64 n = DolDocNewNode(kind, g_doc_cur);
    if (n < 0) return -1;
    CDocNode *nd = &g_doc_nodes[n];
    nd->x = px; nd->y = py; nd->w = pw; nd->h = ph;
    nd->arg_off = DolDocArgStore(tag);
    g_widget_count++;
    g_doc_dirty = 1;
    OmniTapeAppendNode(n);
    return n;
}

// store a label string into the text arena (NUL-terminated) and point the node at it
U0 DolDocSetLabel(I64 nid, U8 *s) {
    if (nid < 0 || !s) return;
    CDocNode *nd = &g_doc_nodes[nid];
    nd->text_off = g_doc_text_used;
    I64 i = 0;
    for (; s[i] && g_doc_text_used < DOC_MAX_TEXT - 1; i++) {
        g_doc_text[g_doc_text_used] = s[i]; g_doc_attr[g_doc_text_used] = 0; g_doc_text_used++;
    }
    g_doc_text[g_doc_text_used] = 0; g_doc_text_used++;
    nd->text_len = i;
}

// advance the flow past a widget of `cols` cells, wrapping if needed
U0 DolDocAdvance(I64 cols) {
    if (g_doc_col > 0 && (g_doc_col + cols >= g_doc_cols)) {
        DolDocBreakRun();
        g_doc_col = 0; g_doc_row++;
        if (g_doc_row >= g_doc_rows) DolDocScroll();
    }
    DolDocBreakRun();
    g_doc_col += cols;
    DolDocUpdateCursor();
}

I64 DolDocFlowPx() { return g_doc_x + 8 + g_doc_col * 8; }
I64 DolDocFlowPy() { return g_doc_y + 8 + g_doc_row * 18; }

// ============================================================================
// Anchor & macro tables
// ============================================================================
U0 DolDocAddAnchor(U8 *name, I64 nid) {
    if (!name || !*name || g_doc_anchor_count >= DOC_MAX_ANCHORS) return;
    I64 idx = g_doc_anchor_count;
    strncpy(g_doc_anchor_names + idx * 32, name, 31);
    g_doc_anchor_names[idx * 32 + 31] = 0;
    g_doc_anchor_nodes[idx] = nid;
    g_doc_anchor_count++;
}

I64 DolDocFindAnchor(U8 *name) {
    for (I64 i = 0; i < g_doc_anchor_count; i++) {
        if (strcmp(g_doc_anchor_names + i * 32, name) == 0) return g_doc_anchor_nodes[i];
    }
    return -1;
}

U0 DolDocDefineMacro(U8 *name, U8 *body) {
    if (!name || !*name || g_doc_macro_count >= DOC_MAX_MACROS) return;
    I64 idx = g_doc_macro_count;
    strncpy(g_doc_macro_names + idx * 32, name, 31);
    g_doc_macro_names[idx * 32 + 31] = 0;
    strncpy(g_doc_macro_bodies + idx * 256, body, 255);
    g_doc_macro_bodies[idx * 256 + 255] = 0;
    g_doc_macro_count++;
}

U8* DolDocFindMacro(U8 *name) {
    for (I64 i = 0; i < g_doc_macro_count; i++) {
        if (strcmp(g_doc_macro_names + i * 32, name) == 0) return g_doc_macro_bodies + i * 256;
    }
    return 0;
}

// ============================================================================
// Full two-letter tag executor
// ============================================================================

// $EQ$ mathematical typography (FRAC/SQRT/SUM/INT)
U0 DolDocParseEquation(U8 *tag) {
    U8 *lbl = 0;
    I64 w = 120;
    I64 h = 34;
    if (strstr(tag, "FRAC")) { lbl = "FRAC"; }
    else if (strstr(tag, "SQRT")) { lbl = "SQRT"; }
    else if (strstr(tag, "SUM")) { lbl = "SUM"; }
    else if (strstr(tag, "INT")) { lbl = "INT"; }
    else return;
    I64 cols = (w + 7) / 8;
    I64 n = DolDocWidget(DOC_EQ, DolDocFlowPx(), DolDocFlowPy() - 6, w, h, tag);
    if (n >= 0) {
        g_doc_nodes[n].state = (strcmp(lbl, "FRAC") == 0) ? 0 : (strcmp(lbl, "SQRT") == 0 ? 1 : (strcmp(lbl, "SUM") == 0 ? 2 : 3));
    }
    DolDocAdvance(cols);
}

// $FI$ include (distributed documents)
U0 DolDocParseInclude(U8 *tag) {
    U8 fname[64]; fname[0] = 0;
    DolDocGetAttrStr(tag, "file=", fname, 60);
    if (!fname[0]) DolDocParseQuoted(tag + 2, fname, 60);
    if (!fname[0]) return;
    I64 sz = 0;
    I64 rc = redsea_read_file(fname, g_doc_inc_buf, 4000, &sz);
    if (rc >= 0 && sz > 0) {
        g_doc_inc_buf[sz] = 0;
        DolDocPrint(g_doc_inc_buf);
    }
}

// $MA$ macro definition/expansion
U0 DolDocParseMacro(U8 *tag) {
    U8 name[32]; name[0] = 0;
    DolDocGetAttrStr(tag, "name=", name, 30);
    if (!name[0]) {
        U8 *p = tag + 2;
        while (*p == ' ' || *p == ',') p++;
        I64 i = 0;
        while (*p && *p != ',' && i < 30) { name[i] = *p; i++; p++; }
        name[i] = 0;
    }
    U8 body[256]; body[0] = 0;
    DolDocGetAttrStr(tag, "text=", body, 250);
    if (body[0]) { DolDocDefineMacro(name, body); return; }
    U8 *m = DolDocFindMacro(name);
    if (m) DolDocPrint(m);
}

// $DA$ data / form field
U0 DolDocParseData(U8 *tag) {
    U8 lbl[64]; lbl[0] = 0;
    U8 *tp = tag + 2;
    tp = DolDocParseQuoted(tp, lbl, 60);
    I64 val = DolDocGetAttrInt(tag, "val=", 0);
    I64 mn = DolDocGetAttrInt(tag, "min=", 0);
    I64 mx = DolDocGetAttrInt(tag, "max=", 1000);
    I64 w = DolDocGetAttrInt(tag, "w=", 160);
    U64 target = DolDocGetAttrInt(tag, "target=", 0);
    if (target == 0) {
        U8 vn[64]; vn[0] = 0;
        DolDocGetAttrStr(tag, "var=", vn, 60);
        if (vn[0]) target = SymLookup(vn);
    }
    if (target != 0) {
        val = *(I64*)target;
        if (val < mn) val = mn;
        if (val > mx) val = mx;
    }
    I64 cols = (w + 32 + 7) / 8;
    I64 n = DolDocWidget(DOC_DATA, DolDocFlowPx(), DolDocFlowPy(), w + 32, 18, tag);
    if (n >= 0) {
        CDocNode *nd = &g_doc_nodes[n];
        nd->val = val; nd->min = mn; nd->max = mx; nd->target = target;
        DolDocSetLabel(n, lbl);
    }
    DolDocAdvance(cols);
}

// $SL$ reactive slider
U0 DolDocParseSlider(U8 *tag) {
    U8 lbl[64]; lbl[0] = 0;
    U8 *tp = tag + 2;
    tp = DolDocParseQuoted(tp, lbl, 60);
    I64 val = DolDocGetAttrInt(tag, "val=", 50);
    I64 mn = DolDocGetAttrInt(tag, "min=", 0);
    I64 mx = DolDocGetAttrInt(tag, "max=", 100);
    I64 w = DolDocGetAttrInt(tag, "w=", 140);
    if (w < 60) w = 60;
    U64 target = DolDocGetAttrInt(tag, "target=", 0);
    if (target == 0) {
        U8 vn[64]; vn[0] = 0;
        DolDocGetAttrStr(tag, "var=", vn, 60);
        if (vn[0]) { target = SymLookup(vn); if (target == 0) target = symbols_lookup(vn); }
    }
    if (target == 0 && lbl[0]) { target = SymLookup(lbl); if (target == 0) target = symbols_lookup(lbl); }
    if (target != 0) {
        val = *(I64*)target;
        if (val < mn) val = mn;
        if (val > mx) val = mx;
    }
    I64 cols = (w + 7) / 8 + 5;
    I64 n = DolDocWidget(DOC_SLIDER, DolDocFlowPx(), DolDocFlowPy(), w, 18, tag);
    if (n >= 0) {
        CDocNode *nd = &g_doc_nodes[n];
        nd->val = val; nd->min = mn; nd->max = mx; nd->target = target;
    }
    DolDocAdvance(cols);
}

// $IV$ toggle / $CB$ checkbox
U0 DolDocParseToggle(U8 *tag) {
    U8 lbl[64]; lbl[0] = 0;
    U8 *tp = tag + 2;
    tp = DolDocParseQuoted(tp, lbl, 60);
    I64 chk = 0;
    if (*tp == ',') { tp++; if (*tp == '1' || *tp == 't' || *tp == 'T') chk = 1; }
    I64 w = 20 + strlen(lbl) * 8 + 8;
    I64 cols = (w + 7) / 8;
    I64 n = DolDocWidget(DOC_TOGGLE, DolDocFlowPx(), DolDocFlowPy(), w, 18, tag);
    if (n >= 0) {
        g_doc_nodes[n].state = chk;
        DolDocSetLabel(n, lbl);
    }
    DolDocAdvance(cols);
}

// $PB$ progress bar
U0 DolDocParseProgress(U8 *tag) {
    I64 val = DolDocGetAttrInt(tag, "val=", 0);
    I64 mx = DolDocGetAttrInt(tag, "max=", 100);
    if (mx <= 0) mx = 100;
    if (val < 0) val = 0;
    if (val > mx) val = mx;
    I64 w = 160;
    I64 cols = (w + 48 + 7) / 8;
    I64 n = DolDocWidget(DOC_PROGRESS, DolDocFlowPx(), DolDocFlowPy(), w, 18, tag);
    if (n >= 0) { g_doc_nodes[n].val = val; g_doc_nodes[n].max = mx; }
    DolDocAdvance(cols);
}

// $ID$ collapsible tree
U0 DolDocParseTree(U8 *tag) {
    U8 title[64]; title[0] = 0;
    DolDocGetAttrStr(tag, "title=", title, 60);
    if (!title[0]) DolDocParseQuoted(tag + 2, title, 60);
    I64 lvl = DolDocGetAttrInt(tag, "level=", 0);
    I64 len = strlen(title) + 4 + lvl * 2;
    I64 cols = (len * 8 + 7) / 8;
    I64 n = DolDocWidget(DOC_TREE, DolDocFlowPx() + lvl * 12, DolDocFlowPy(), len * 8, 18, tag);
    if (n >= 0) {
        g_doc_nodes[n].state = 1;
        DolDocSetLabel(n, title);
    }
    DolDocAdvance(cols);
}

// $SP$ in-code sprite / 3D mesh
U0 DolDocParseSprite(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 96);
    I64 h = DolDocGetAttrInt(tag, "h=", 72);
    U8 st[32]; st[0] = 0;
    DolDocGetAttrStr(tag, "type=", st, 30);
    if (!st[0]) strcpy(st, "cube");
    I64 cols = (w + 7) / 8;
    I64 n = DolDocWidget(DOC_BITMAP, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n >= 0) strncpy(g_doc_args + g_doc_nodes[n].arg_off, st, 32);
    DolDocAdvance(cols);
}

// $SH$ / $SHADER$ fragment shader viewport
U0 DolDocParseShader(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 220);
    I64 h = DolDocGetAttrInt(tag, "h=", 72);
    U8 st[32]; st[0] = 0;
    DolDocGetAttrStr(tag, "type=", st, 30);
    if (!st[0]) strcpy(st, "plasma");
    I64 cols = (w + 7) / 8;
    I64 n = DolDocWidget(DOC_SHADER, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n >= 0) strncpy(g_doc_args + g_doc_nodes[n].arg_off, st, 32);
    DolDocAdvance(cols);
}

// $GR$ / $PL$ telemetry oscilloscope
U0 DolDocParseGraph(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 220);
    I64 h = DolDocGetAttrInt(tag, "h=", 52);
    U8 gt[32]; gt[0] = 0;
    DolDocGetAttrStr(tag, "type=", gt, 30);
    if (!gt[0]) strcpy(gt, "sine");
    I64 cols = (w + 7) / 8;
    I64 n = DolDocWidget(DOC_GRAPH, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n >= 0) strncpy(g_doc_args + g_doc_nodes[n].arg_off, gt, 32);
    DolDocAdvance(cols);
}

// $FO$ / $HD$ / $FONT$ scalable vector typography
U0 DolDocParseFontText(U8 *tag) {
    U8 lbl[64]; lbl[0] = 0;
    DolDocGetAttrStr(tag, "text=", lbl, 60);
    if (!lbl[0]) DolDocParseQuoted(tag + 2, lbl, 60);
    I64 scale = DolDocGetAttrInt(tag, "scale=", 180);
    if (scale < 100) scale = 100;
    if (scale > 400) scale = 400;
    U8 cs[32]; cs[0] = 0;
    DolDocGetAttrStr(tag, "color=", cs, 30);
    U32 fcol = SEM_COLOR_SAPPHIRE;
    if (cs[0]) fcol = DolDocParseColor(cs, SEM_COLOR_SAPPHIRE);
    I64 char_adv = (10 * scale) / 100;
    I64 char_h = (16 * scale) / 100 + 6;
    I64 fw = strlen(lbl) * char_adv + 12;
    I64 cols = (fw + 7) / 8;
    I64 n = DolDocWidget(DOC_FONT, DolDocFlowPx(), DolDocFlowPy(), fw, char_h, tag);
    if (n >= 0) {
        CDocNode *nd = &g_doc_nodes[n];
        nd->val = scale; nd->min = (I64)fcol;
        DolDocSetLabel(n, lbl);
    }
    DolDocAdvance(cols);
}

// $WIN$ window container (creates a desktop window node; children via $EW$)
U0 DolDocParseWindow(U8 *tag) {
    U8 title[64]; title[0] = 0;
    DolDocGetAttrStr(tag, "title=", title, 60);
    I64 x = DolDocGetAttrInt(tag, "x=", 40);
    I64 y = DolDocGetAttrInt(tag, "y=", 60);
    I64 w = DolDocGetAttrInt(tag, "w=", 400);
    I64 h = DolDocGetAttrInt(tag, "h=", 300);
    I64 kind = DolDocGetAttrInt(tag, "kind=", 0);
    DolDocWinCreate(title, x, y, w, h, kind);
}

U0 DolDocParseEndWindow() { }

// $CARD$ / $BD$ / $BK$ container box
U0 DolDocParseCard(U8 *tag, I64 kind) {
    U8 title[64]; title[0] = 0;
    DolDocGetAttrStr(tag, "title=", title, 60);
    I64 w = DolDocGetAttrInt(tag, "w=", 50);
    I64 h = DolDocGetAttrInt(tag, "h=", 5);
    if (w < 6) w = 6;
    if (h < 2) h = 2;
    I64 n = DolDocWidget(kind, DolDocFlowPx(), DolDocFlowPy(), w * 8, h * 18, tag);
    if (n >= 0) {
        CDocNode *nd = &g_doc_nodes[n];
        nd->val = (I64)DolDocGetAttrHex(tag, "bg=", kind == DOC_CARD ? SEM_COLOR_BASE : SEM_COLOR_SURFACE0);
        nd->min = (I64)DolDocGetAttrHex(tag, "border=", SEM_COLOR_BLUE);
        DolDocSetLabel(n, title);
    }
    // Containers do not advance the flow; following text flows inside them.
}

// $GLASS$ / $BLUR$ frosted panel
U0 DolDocParseGlass(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 40);
    I64 h = DolDocGetAttrInt(tag, "h=", 4);
    I64 alpha = DolDocGetAttrInt(tag, "alpha=", 0xC8);
    I64 n = DolDocWidget(DOC_GLASS, DolDocFlowPx(), DolDocFlowPy(), w * 8, h * 18, tag);
    if (n >= 0) g_doc_nodes[n].val = alpha;
}

U0 DolDocParseShadow(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 40);
    I64 h = DolDocGetAttrInt(tag, "h=", 4);
    I64 rad = DolDocGetAttrInt(tag, "radius=", 6);
    I64 n = DolDocWidget(DOC_SHADOW, DolDocFlowPx(), DolDocFlowPy(), w * 8, h * 18, tag);
    if (n >= 0) g_doc_nodes[n].val = rad;
}

// ============================================================================
// The tag dispatcher (full two-letter set + legacy aliases)
// ============================================================================
U0 DolDocExecTag(U8 *tag) {
    if (!tag || !*tag) return;
    I64 t0 = tag[0]; I64 t1 = tag[1];

    // ---- colour tags ----
    if (t0 == 'F' && t1 == 'G') {
        if (tag[2] == ',') g_doc_cur_fg = DolDocParseColor(tag + 3, SEM_COLOR_TEXT);
        else g_doc_cur_fg = SEM_COLOR_TEXT;
        return;
    }
    if (t0 == 'B' && t1 == 'G') {
        if (tag[2] == ',') g_doc_cur_bg = DolDocParseColor(tag + 3, SEM_COLOR_MANTLE);
        else g_doc_cur_bg = SEM_COLOR_MANTLE;
        return;
    }
    if (t0 == 'F' && t1 == 'D') { g_doc_cur_fg = SEM_COLOR_TEXT; return; }
    if (t0 == 'B' && t1 == 'D') { g_doc_cur_bg = SEM_COLOR_MANTLE; return; }
    if (t0 == 'C' && t1 == 'L' && (tag[2] == 'S' || tag[2] == 0)) { DolDocClear(); return; }
    if (strcmp(tag, "CLEAR") == 0) { DolDocClear(); return; }
    if (t0 == 'C' && t1 == 'L') {
        U8 a[32]; a[0] = 0; U8 b[32]; b[0] = 0;
        U8 *p = tag + 2;
        while (*p == ',' || *p == ' ') p++;
        I64 i = 0; while (*p && *p != ',' && i < 30) { a[i] = *p; i++; p++; } a[i] = 0;
        if (*p == ',') p++;
        while (*p == ' ') p++;
        i = 0; while (*p && *p != ',' && i < 30) { b[i] = *p; i++; p++; } b[i] = 0;
        if (a[0]) g_doc_cur_fg = DolDocParseColor(a, SEM_COLOR_TEXT);
        if (b[0]) g_doc_cur_bg = DolDocParseColor(b, SEM_COLOR_MANTLE);
        return;
    }
    // ---- text / flow ----
    if (t0 == 'T' && t1 == 'X') { U8 s[256]; DolDocParseQuoted(tag + 2, s, 250); DolDocPrint(s); return; }
    if (t0 == 'P' && t1 == 'T') { U8 s[256]; DolDocParseQuoted(tag + 2, s, 250); DolDocPrint(s); return; }
    if (t0 == 'C' && t1 == 'R') { DolDocPutc(10); return; }
    if (t0 == 'T' && t1 == 'B') { DolDocPutc(9); return; }
    if (t0 == 'C' && t1 == 'U') { I64 c = DolDocGetAttrInt(tag, "x=", -1); I64 r = DolDocGetAttrInt(tag, "y=", -1);
        if (c >= 0 && c < g_doc_cols) g_doc_col = c; if (r >= 0 && r < g_doc_rows) g_doc_row = r; DolDocUpdateCursor(); return; }
    if (t0 == 'L' && t1 == 'M') { g_doc_lmargin = DolDocGetAttrInt(tag, "x=", 0); return; }
    if (t0 == 'R' && t1 == 'M') { g_doc_rmargin = DolDocGetAttrInt(tag, "x=", g_doc_cols); return; }
    if (t0 == 'S' && t1 == 'R') { g_doc_rmargin = g_doc_col; return; }
    if (t0 == 'W' && t1 == 'W') { g_doc_wrap = !g_doc_wrap; return; }
    if (t0 == 'U' && t1 == 'L') { g_doc_underline = !g_doc_underline; return; }
    if (t0 == 'P' && t1 == 'U') { DolDocStylePush(g_doc_cur_fg, g_doc_cur_bg); return; }
    if (t0 == 'P' && t1 == 'O') { DolDocStylePop(); return; }
    if (t0 == 'R' && t1 == 'O') { DolDocPutc(10); return; }
    if (t0 == 'C' && t1 == 'O') { I64 c = DolDocAtoi(tag + 4); while (g_doc_col < c && g_doc_col < g_doc_cols) DolDocPutc(' '); return; }
    // ---- anchors / links ----
    if (t0 == 'A' && t1 == 'N') {
        U8 nm[32]; nm[0] = 0;
        DolDocGetAttrStr(tag, "name=", nm, 30);
        if (!nm[0] && tag[2] == ',') {
            U8 *p = tag + 3; I64 i = 0;
            while (*p == ' ') p++;
            while (*p && *p != ',' && *p != '$' && i < 30) { nm[i] = *p; i++; p++; }
            nm[i] = 0;
        }
        if (!nm[0]) DolDocParseQuoted(tag + 2, nm, 30);
        if (nm[0]) DolDocAddAnchor(nm, g_doc_cur);
        return;
    }
    if (t0 == 'B' && t1 == 'K') {
        U8 nm[32]; nm[0] = 0;
        DolDocGetAttrStr(tag, "name=", nm, 30);
        if (!nm[0] && tag[2] == ',') { U8 *p = tag + 3; I64 i = 0; while (*p == ' ') p++; while (*p && *p != ',' && *p != '$' && i < 30) { nm[i] = *p; i++; p++; } nm[i] = 0; }
        if (nm[0]) DolDocAddAnchor(nm, g_doc_cur);
        return;
    }
    if (t0 == 'L' && t1 == 'K') {
        U8 lbl[64]; lbl[0] = 0; U8 cmd[128]; cmd[0] = 0; U8 id[64]; id[0] = 0;
        U8 *p = DolDocParseQuoted(tag + 2, lbl, 60);
        U8 *ap = strstr(p, "A="); if (ap) DolDocParseQuoted(ap + 2, cmd, 120);
        U8 *ip = strstr(p, "ID="); if (ip) DolDocParseQuoted(ip + 3, id, 60);
        if (!id[0]) { U8 *lp = strstr(p, "LK="); if (lp) DolDocParseQuoted(lp + 3, id, 60); }
        I64 cols = strlen(lbl) + 2;
        I64 n = DolDocWidget(DOC_LINK, DolDocFlowPx(), DolDocFlowPy(), strlen(lbl) * 8, 18, tag);
        if (n >= 0) {
            U8 both[200]; both[0] = 0;
            if (cmd[0]) strcpy(both, cmd); else if (id[0]) { strcpy(both, "#"); strcat(both, id); }
            strncpy(g_doc_args + g_doc_nodes[n].arg_off, both, strlen(both) + 1);
            DolDocSetLabel(n, lbl);
        }
        DolDocAdvance(cols);
        return;
    }
    if (t0 == 'C' && t1 == 'M') { U8 cmd[128]; DolDocParseQuoted(tag + 2, cmd, 120); if (cmd[0]) DolDocPushAction(DOC_ACT_RUN, -1, 0, cmd); return; }
    // ---- widgets ----
    if (t0 == 'B' && t1 == 'T') {
        U8 lbl[64]; lbl[0] = 0; U8 cmd[128]; cmd[0] = 0;
        U8 *p = DolDocParseQuoted(tag + 2, lbl, 60);
        U8 *lp = strstr(p, "LM="); if (lp) DolDocParseQuoted(lp + 3, cmd, 120);
        I64 vw = strlen(lbl) * 8 + 16;
        I64 cols = (vw + 7) / 8 + 1;
        I64 n = DolDocWidget(DOC_BUTTON, DolDocFlowPx(), DolDocFlowPy(), vw, 18, tag);
        if (n >= 0) {
            strncpy(g_doc_args + g_doc_nodes[n].arg_off, cmd, strlen(cmd) + 1);
            DolDocSetLabel(n, lbl);
        }
        DolDocAdvance(cols);
        return;
    }
    if (t0 == 'D' && t1 == 'A') { DolDocParseData(tag); return; }
    if (t0 == 'S' && t1 == 'L') { DolDocParseSlider(tag); return; }
    if (t0 == 'C' && t1 == 'B') { DolDocParseToggle(tag); return; }
    if (t0 == 'I' && t1 == 'V') { DolDocParseToggle(tag); return; }
    if (t0 == 'P' && t1 == 'B') { DolDocParseProgress(tag); return; }
    if (t0 == 'I' && t1 == 'D') { DolDocParseTree(tag); return; }
    if (strncmp(tag, "SPLIT", 5) == 0) { return; }
    if (t0 == 'S' && t1 == 'P') { DolDocParseSprite(tag); return; }
    if (strncmp(tag, "SHADOW", 6) == 0) { DolDocParseShadow(tag); return; }
    if (strncmp(tag, "SHADER", 6) == 0) { DolDocParseShader(tag); return; }
    if (t0 == 'S' && t1 == 'H') { DolDocParseShader(tag); return; }
    if (t0 == 'S' && t1 == 'X') { DolDocParseSprite(tag); return; }
    if (t0 == 'S' && t1 == 'Y') { DolDocParseSprite(tag); return; }
    if (t0 == 'G' && t1 == 'R') { DolDocParseGraph(tag); return; }
    if (t0 == 'P' && t1 == 'L') { DolDocParseGraph(tag); return; }
    if (t0 == 'E' && t1 == 'Q') { DolDocParseEquation(tag); return; }
    if (t0 == 'F' && t1 == 'O') { DolDocParseFontText(tag); return; }
    if (t0 == 'H' && t1 == 'D') { DolDocParseFontText(tag); return; }
    if (t0 == 'M' && t1 == 'A') { DolDocParseMacro(tag); return; }
    if (t0 == 'F' && t1 == 'I') { DolDocParseInclude(tag); return; }
    if (t0 == 'H' && t1 == 'R') { I64 n = DolDocWidget(DOC_RULE, g_doc_x + 12, DolDocFlowPy(), g_doc_w - 24, 18, tag); DolDocAdvance(1); return; }
    if (t0 == 'B' && t1 == 'O') { DolDocParseCard(tag, DOC_BOX); return; }
    if (t0 == 'C' && t1 == 'A') { DolDocParseCard(tag, DOC_CARD); return; }
    if (t0 == 'G' && t1 == 'L') { DolDocParseGlass(tag); return; }
    if (t0 == 'B' && t1 == 'L') { DolDocParseGlass(tag); return; }
    if (t0 == 'W' && t1 == 'I') { DolDocParseWindow(tag); return; }
    if (t0 == 'E' && t1 == 'W') { DolDocParseEndWindow(); return; }
    if (t0 == 'E' && t1 == 'L') { if (g_doc_cur >= 0) g_doc_nodes[g_doc_cur].flags |= DOCF_ELEV; return; }
    // ---- legacy long tags ----
    if (strncmp(tag, "SHADER", 6) == 0) { DolDocParseShader(tag); return; }
    if (strncmp(tag, "GRAPH", 5) == 0) { DolDocParseGraph(tag); return; }
    if (strncmp(tag, "GLASS", 5) == 0) { DolDocParseGlass(tag); return; }
    if (strncmp(tag, "SHADOW", 6) == 0) { DolDocParseShadow(tag); return; }
    if (strncmp(tag, "FONT", 4) == 0) { DolDocParseFontText(tag); return; }
    if (strncmp(tag, "CARD", 4) == 0) { DolDocParseCard(tag, DOC_CARD); return; }
    if (strncmp(tag, "H1", 2) == 0) { DolDocParseFontText(tag); return; }
    if (strncmp(tag, "BOX", 3) == 0) { DolDocParseCard(tag, DOC_BOX); return; }
    // ---- macro invocation fallback ----
    U8 *m = DolDocFindMacro(tag);
    if (m) { DolDocPrint(m); return; }
}

// ============================================================================
// DolDocPrint: the stream parser / compiler
// ============================================================================
U0 DolDocPrint(U8 *str) {
    if (!str) return;
    while (*str) {
        if (*str == '$') {
            str++;
            if (*str == '$') { DolDocPutc('$'); str++; continue; }
            I64 tlen = 0;
            while (*str && *str != '$' && tlen < 2047) { g_tag_buf[tlen] = *str; tlen++; str++; }
            g_tag_buf[tlen] = 0;
            if (*str == '$') str++;
            DolDocExecTag(g_tag_buf);
            continue;
        }
        DolDocPutc(*str);
        str++;
    }
}

U0 DolDocExportPrint(U8 *str) { DolDocPrint(str); }

// ============================================================================
// Scrollback & clear
// ============================================================================
U0 DolDocClear() {
    g_doc_node_count = 0;
    g_doc_text_used = 0;
    g_doc_args_used = 1;   // offset 0 reserved (0 == "no args")
    g_doc_root = DolDocNewNode(DOC_ROOT, -1);
    g_doc_cur = g_doc_root;
    g_doc_cur_run = -1;
    g_doc_col = 0; g_doc_row = 0;
    g_widget_count = 0;
    g_doc_scroll_offset = 0;
    g_doc_inspected_nid = -1;
    g_doc_anchor_count = 0;
    g_doc_cursor_x = g_doc_x + 8;
    g_doc_cursor_y = g_doc_y + 8;
    g_omnitape_tail = 0;
    g_omnitape_cmd_count = 0;
    DolDocMarkAllDirty();
}

U0 DolDocScrollUp(I64 lines) {
    g_doc_scroll_offset += lines;
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

U0 DolDocSetBgColor(U32 bg) { g_doc_cur_bg = bg; DolDocMarkAllDirty(); }
U32 DolDocGetBgColor() { return DolDocResolveColor(g_doc_cur_bg); }

// ============================================================================
// Real-time shader viewport ($SH$ / $SHADER$)
// ============================================================================
U0 DolDocRenderShaderNode(I64 vx, I64 vy, I64 vw, I64 vh, U8 *sh_type) {
    if (ShaderTypeId(sh_type) >= 0) { ShaderVMRenderNode(vx, vy, vw, vh, sh_type); return; }
    I64 t_ms = timer_get_uptime_ms();
    I64 phase = ((t_ms * g_shader_speed) / 400) + g_doc_anim_tick * 3;
    I64 zoom = g_shader_zoom;
    if (zoom < 8) zoom = 8;

    I64 mode = 0;
    if (strcmp(sh_type, "torus") == 0 || strcmp(sh_type, "sdf") == 0) mode = 1;
    else if (strcmp(sh_type, "wave") == 0 || strcmp(sh_type, "glass") == 0) mode = 2;
    else if (strcmp(sh_type, "fire") == 0 || strcmp(sh_type, "flame") == 0) mode = 3;
    else if (strcmp(sh_type, "tunnel") == 0 || strcmp(sh_type, "grid") == 0) mode = 4;
    else if (strcmp(sh_type, "metaballs") == 0 || strcmp(sh_type, "blobs") == 0) mode = 5;
    else if (strcmp(sh_type, "stars") == 0 || strcmp(sh_type, "warp") == 0) mode = 6;
    else if (strcmp(sh_type, "fractal") == 0 || strcmp(sh_type, "julia") == 0) mode = 7;

    for (I64 sy = 2; sy < vh - 2; sy += 2) {
        for (I64 sx = 2; sx < vw - 2; sx += 2) {
            U32 frag_col = 0xFF181825;
            if (mode == 0) {
                I64 u = (sx * zoom) / 32; I64 v = (sy * zoom) / 32;
                I64 w1 = DocFastSin(u + phase); I64 w2 = DocFastCos(v + (phase >> 1));
                I64 w3 = DocFastSin(((u + v) >> 1) - phase);
                I64 sum = (w1 + w2 + w3) / 3;
                I64 r = (128 + ((DocFastSin((sum >> 3) + (g_shader_morph >> 1)) * 120) >> 8)) & 0xFF;
                I64 g = (110 + ((DocFastCos((sum >> 3) + 12) * 115) >> 8)) & 0xFF;
                I64 b = (185 + ((sum * 68) >> 8)) & 0xFF;
                frag_col = 0xFF000000 | (r << 16) | (g << 8) | b;
            } else if (mode == 1) {
                I64 cx = sx - (vw / 2); I64 cy = sy - (vh / 2);
                I64 r2 = cx * cx + cy * cy * 2;
                I64 torus_rad = (vh * (20 + (g_shader_morph >> 2))) / 100;
                I64 ring_r = torus_rad * torus_rad;
                I64 diff = r2 - ring_r; if (diff < 0) diff = -diff;
                I64 band = ring_r / 2 + 64;
                if (diff < band) {
                    I64 inten = 255 - ((diff * 220) / band);
                    I64 lx = (DocFastCos(phase) * (vw / 4)) >> 8;
                    I64 ly = (DocFastSin(phase) * (vh / 4)) >> 8;
                    I64 spec = 64 - ((cx - lx) * (cx - lx) + (cy - ly) * (cy - ly)) / 16;
                    if (spec < 0) spec = 0;
                    I64 tr = ((inten * 90) >> 8) + spec; I64 tg = ((inten * 210) >> 8) + spec; I64 tb = ((inten * 250) >> 8) + spec;
                    if (tr > 255) tr = 255; if (tg > 255) tg = 255; if (tb > 255) tb = 255;
                    frag_col = 0xFF000000 | (tr << 16) | (tg << 8) | tb;
                } else {
                    frag_col = (((sx + phase) & 15) == 0 || ((sy + phase) & 15) == 0) ? 0xFF283048 : 0xFF111420;
                }
            } else if (mode == 2) {
                I64 wy = (DocFastSin((sx * zoom) / 40 + phase) * (vh / 4)) >> 8;
                I64 dy = (sy - (vh / 2)) - wy; if (dy < 0) dy = -dy;
                I64 glow = 240 - dy * 8; if (glow < 24) glow = 24;
                frag_col = 0xFF000000 | (((glow * 140) >> 8) << 16) | (((glow * 220) >> 8) << 8) | glow;
            } else if (mode == 3) {
                I64 y_inv = vh - sy; I64 t_up = phase * 2;
                I64 n1 = (DocFastSin((sx * 8) + t_up) * 28) >> 8;
                I64 n2 = (DocFastCos((sx * 14) - t_up) * 18) >> 8;
                I64 n3 = (DocFastSin((sx + y_inv) * 6 + t_up) * 16) >> 8;
                I64 e = 240 - ((y_inv * 260) / vh) + n1 + n2 + n3;
                if (e > 170) frag_col = 0xFFFFF090;
                else if (e > 105) frag_col = 0xFF000000 | (250 << 16) | ((100 + ((e - 105) * 140) / 65) << 8) | 30;
                else if (e > 35) frag_col = 0xFF000000 | ((60 + ((e - 35) * 190) / 70) << 16) | (20 << 8) | 25;
                else if (e > 8) frag_col = 0xFF351830;
                else frag_col = 0xFF0F0E17;
            } else if (mode == 4) {
                I64 cy = sy - (vh / 2); I64 cx = sx - (vw / 2);
                if (cy > 0) {
                    I64 z = (vh * 48) / cy; I64 gx = ((cx * z) >> 6); I64 gz = z + phase * 4;
                    I64 mx = gx; if (mx < 0) mx = -mx;
                    if ((mx % 24) < 2 || (gz % 32) < 2) {
                        I64 fade = 255 - (z * 2); if (fade < 30) fade = 30;
                        frag_col = 0xFF000000 | (((fade * 243) >> 8) << 16) | (((fade * 139) >> 8) << 8) | ((fade * 255) >> 8);
                    } else frag_col = 0xFF141224;
                } else {
                    I64 dist_h = -cy;
                    if (dist_h < 18 && (cx * cx + dist_h * dist_h * 4) < 400) frag_col = ((dist_h % 4) == 0 && dist_h > 4) ? 0xFF181825 : 0xFFF9E2AF;
                    else { I64 sky = 80 - dist_h * 2; if (sky < 12) sky = 12; frag_col = 0xFF000000 | ((sky + 10) << 16) | (10 << 8) | ((sky * 2) & 0xFF); }
                }
            } else if (mode == 5) {
                I64 mx0 = sx - (vw / 2); I64 my0 = sy - (vh / 2);
                I64 ox1 = (DocFastCos(phase) * (vw / 5)) >> 8; I64 oy1 = (DocFastSin(phase) * (vh / 4)) >> 8;
                I64 ox2 = (DocFastCos(phase + 21) * (vw / 4)) >> 8; I64 oy2 = (DocFastSin(phase + 21) * (vh / 5)) >> 8;
                I64 ox3 = (DocFastCos(phase + 42) * (vw / 6)) >> 8; I64 oy3 = (DocFastSin(phase + 42) * (vh / 3)) >> 8;
                I64 d1 = (mx0 - ox1) * (mx0 - ox1) + (my0 - oy1) * (my0 - oy1) + 20;
                I64 d2 = (mx0 - ox2) * (mx0 - ox2) + (my0 - oy2) * (my0 - oy2) + 20;
                I64 d3 = (mx0 - ox3) * (mx0 - ox3) + (my0 - oy3) * (my0 - oy3) + 20;
                I64 pot = 16000 / d1 + 16000 / d2 + 16000 / d3;
                if (pot > 180) frag_col = 0xFFCBA6F7;
                else if (pot > 70) { I64 bcol = (pot * 200) / 110; if (bcol > 255) bcol = 255; frag_col = 0xFF000000 | (137 << 16) | (180 << 8) | bcol; }
                else if (pot > 25) frag_col = 0xFF1E1E2E;
                else frag_col = 0xFF11111B;
            } else if (mode == 6) {
                I64 csx = sx - (vw / 2); I64 csy = sy - (vh / 2);
                I64 rad2 = csx * csx + csy * csy;
                I64 ang_s = (csx * 128) / (csy == 0 ? 1 : csy);
                I64 star_hash = ((ang_s * 17) ^ (rad2 >> 4) ^ phase) & 127;
                if (star_hash == 0 && rad2 > 36) { I64 br = (rad2 * 255) / ((vw * vw) / 4); if (br > 255) br = 255; if (br < 80) br = 80; frag_col = 0xFF000000 | (br << 16) | (br << 8) | 255; }
                else { I64 neb = (DocFastSin((csx * 6) / 20 + phase) * DocFastCos((csy * 6) / 20 - phase)) >> 10; if (neb < 0) neb = 0; frag_col = 0xFF000000 | ((neb * 80) << 16) | ((neb * 40) << 8) | (neb * 140); }
            } else {
                I64 fzx = ((sx - (vw / 2)) * zoom) / 24; I64 fzy = ((sy - (vh / 2)) * zoom) / 24;
                I64 min_d = 9999;
                for (I64 iter = 0; iter < 4; iter++) {
                    I64 nzx = (fzx * fzx - fzy * fzy) >> 8; I64 nzy = (fzx * fzy) >> 7;
                    fzx = nzx + ((DocFastCos(phase) * 60) >> 8); fzy = nzy + ((DocFastSin(phase) * 60) >> 8);
                    I64 adx = fzx < 0 ? -fzx : fzx; I64 ady = fzy < 0 ? -fzy : fzy;
                    I64 trap = adx < ady ? adx : ady;
                    if (trap < min_d) min_d = trap;
                }
                I64 finten = 255 - min_d * 3; if (finten < 16) finten = 16; if (finten > 255) finten = 255;
                frag_col = 0xFF000000 | (((finten * 203) >> 8) << 16) | (((finten * 166) >> 8) << 8) | finten;
            }
            gfx_draw_rect(vx + sx, vy + sy, 2, 2, frag_col);
        }
    }
    gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_BLUE));
    gfx_blend_rect(vx + 4, vy + 4, vw - 8, 16, 0xA011111B);
    gfx_draw_string(vx + 8, vy + 4, "SHADERTOY:", DolDocResolveColor(SEM_COLOR_YELLOW), 0);
    gfx_draw_string(vx + 92, vy + 4, sh_type, DolDocResolveColor(SEM_COLOR_SKY), 0);
}

// ============================================================================
// 3D scene viewport ($SP$ / $SX$ / $CM$)
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
        if (symbols_lookup("Gears3DRenderViewport") != 0) {
            Gears3DRenderViewport(vx + 2, vy + 2, vw - 4, vh - 4, (F64)ang * 1.5);
            gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            return;
        }
    } else if (strcmp(stype, "physics") == 0) {
        if (symbols_lookup("Physics3DRenderViewport") != 0) {
            Physics3DRenderViewport(vx + 2, vy + 2, vw - 4, vh - 4);
            gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
            return;
        }
    } else if (strcmp(stype, "mesh") == 0) {
        MeshRenderViewport(vx + 2, vy + 2, vw - 4, vh - 4, (F64)ang * 0.6);
        gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
        gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
        gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
        gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
        return;
    }

    gfx_draw_rounded_rect(vx, vy, vw, vh, 4, DolDocResolveColor(SEM_COLOR_CRUST));
    gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));

    I64 cx = vx + vw / 2; I64 cy = vy + vh / 2 + 4;
    I64 sp_rad = (vh < vw ? vh : vw) / 3; if (sp_rad < 12) sp_rad = 12;
    I64 ca = DocFastCos(ang); I64 sa = DocFastSin(ang);
    I64 cb = DocFastCos((ang >> 1) + 9); I64 sb = DocFastSin((ang >> 1) + 9);
    for (I64 vi = 0; vi < 8; vi++) {
        I64 vx3 = (vi & 1) ? sp_rad : -sp_rad;
        I64 vy3 = (vi & 2) ? sp_rad : -sp_rad;
        I64 vz3 = (vi & 4) ? sp_rad : -sp_rad;
        I64 rx1 = (vx3 * ca - vz3 * sa) >> 8;
        I64 rz1 = (vx3 * sa + vz3 * ca) >> 8;
        I64 ry2 = (vy3 * cb - rz1 * sb) >> 8;
        I64 rz2 = (vy3 * sb + rz1 * cb) >> 8;
        I64 dist = 128 + (rz2 >> 1); if (dist < 48) dist = 48;
        g_cube_px[vi] = cx + (rx1 * 110) / dist;
        g_cube_py[vi] = cy + (ry2 * 110) / dist;
    }
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
    for (I64 ei = 0; ei < 4; ei++) gfx_draw_line(g_cube_px[ei], g_cube_py[ei], g_cube_px[ei + 4], g_cube_py[ei + 4], c_strut);
    for (I64 gi = 0; gi < 8; gi++) gfx_draw_rect(g_cube_px[gi] - 1, g_cube_py[gi] - 1, 3, 3, DolDocResolveColor(SEM_COLOR_YELLOW));
    gfx_draw_string(vx + 6, vy + 2, "3D:", DolDocResolveColor(SEM_COLOR_MUTED), 0);
    gfx_draw_string(vx + 30, vy + 2, stype, DolDocResolveColor(SEM_COLOR_PEACH), 0);
}

// ============================================================================
// Telemetry oscilloscope ($PL$ / $GR$)
// ============================================================================
U0 DolDocSampleTelemetry() {
    if (!g_doc_trig_ready) DolDocInitTrig();
    g_osc_head = (g_osc_head + 1) & 63;
    I64 freq_step = 2 + (g_shader_speed / 25);
    g_osc_sine_buf[g_osc_head] = DocFastSin((g_osc_head * freq_step + g_doc_anim_tick * 3) & 63);
    I64 cur_fps = g_comp.fps; if (cur_fps <= 0) cur_fps = 60;
    g_osc_fps_buf[g_osc_head] = cur_fps;
}

U0 DolDocRenderGraphNode(I64 vx, I64 vy, I64 vw, I64 vh, U8 *gtype) {
    DolDocSampleTelemetry();
    gfx_draw_rounded_rect(vx, vy, vw, vh, 4, DolDocResolveColor(SEM_COLOR_CRUST));
    gfx_draw_rect(vx, vy, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy + vh - 1, vw, 1, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
    gfx_draw_rect(vx + vw - 1, vy, 1, vh, DolDocResolveColor(SEM_COLOR_SURFACE1));
    I64 mid_y = vy + vh / 2;
    gfx_draw_line(vx + 4, mid_y, vx + vw - 4, mid_y, DolDocResolveColor(SEM_COLOR_SURFACE0));
    gfx_draw_line(vx + vw / 2, vy + 4, vx + vw / 2, vy + vh - 4, DolDocResolveColor(SEM_COLOR_SURFACE0));
    I64 floor_y = vy + vh - 4; I64 plot_w = vw - 8; if (plot_w < 16) plot_w = 16;
    I64 amp = (vh / 2) - 8; if (amp < 6) amp = 6;
    I64 prev_x = vx + 4; I64 prev_y = mid_y;
    U32 wave_col = DolDocResolveColor(SEM_COLOR_TEAL);
    if (strcmp(gtype, "fps") == 0) wave_col = DolDocResolveColor(SEM_COLOR_GREEN);
    else if (strcmp(gtype, "mem") == 0) wave_col = DolDocResolveColor(SEM_COLOR_MAUVE);
    for (I64 s_i = 0; s_i < 48; s_i++) {
        I64 cur_x = vx + 4 + (s_i * plot_w) / 48;
        I64 r_idx = (g_osc_head + s_i) & 63;
        I64 sample_y = mid_y;
        if (strcmp(gtype, "fps") == 0) { sample_y = floor_y - ((g_osc_fps_buf[r_idx] * (vh - 12)) / 120); }
        else {
            I64 s1 = g_osc_sine_buf[r_idx];
            I64 s2 = DocFastCos((r_idx * 3 + g_doc_anim_tick) & 63) / 3;
            sample_y = mid_y - (((s1 + s2) * amp) / 300);
        }
        if (sample_y < vy + 4) sample_y = vy + 4;
        if (sample_y > floor_y) sample_y = floor_y;
        if (s_i > 0) {
            gfx_draw_line(prev_x, prev_y, cur_x, sample_y, wave_col);
            gfx_draw_line(prev_x, prev_y + 1, cur_x, sample_y + 1, wave_col);
            if ((s_i & 1) == 0 && sample_y < floor_y) gfx_blend_rect(cur_x, sample_y + 2, 2, floor_y - sample_y - 2, 0x38000000 | (wave_col & 0x00FFFFFF));
        }
        prev_x = cur_x; prev_y = sample_y;
    }
    gfx_draw_string(vx + 8, vy + 4, "OSC:", DolDocResolveColor(SEM_COLOR_MUTED), 0);
    gfx_draw_string(vx + 42, vy + 4, gtype, DolDocResolveColor(SEM_COLOR_YELLOW), 0);
}

// ============================================================================
// Mathematical typography ($EQ$)
// ============================================================================
U0 DolDocRenderEquation(I64 vx, I64 vy, I64 vw, I64 vh, I64 sub, U8 *tag) {
    U8 num[128]; num[0] = 0; U8 den[128]; den[0] = 0;
    DolDocGetAttrStr(tag, "num=", num, 120);
    DolDocGetAttrStr(tag, "den=", den, 120);
    if (!num[0]) DolDocGetAttrStr(tag, "rad=", num, 120);
    if (!num[0]) DolDocGetAttrStr(tag, "expr=", num, 120);
    if (!den[0]) DolDocGetAttrStr(tag, "lim=", den, 120);
    U32 text_col = DolDocResolveColor(SEM_COLOR_TEXT);
    U32 sapphire = DolDocResolveColor(SEM_COLOR_SAPPHIRE);
    U32 yellow = DolDocResolveColor(SEM_COLOR_YELLOW);
    U32 teal = DolDocResolveColor(SEM_COLOR_TEAL);
    U64 fv_fn = symbols_lookup("FontVectorDrawString");
    if (sub == 0) {
        gfx_draw_rect(vx, vy + 15, vw, 2, text_col);
        if (fv_fn != 0) {
            FontVectorDrawString(vx + (vw - FontVectorMeasureString(num, 70)) / 2, vy, num, 70, sapphire);
            FontVectorDrawString(vx + (vw - FontVectorMeasureString(den, 70)) / 2, vy + 17, den, 70, text_col);
        } else {
            gfx_draw_string(vx + (vw - strlen(num) * 8) / 2, vy, num, sapphire, 0);
            gfx_draw_string(vx + (vw - strlen(den) * 8) / 2, vy + 18, den, text_col, 0);
        }
    } else if (sub == 1) {
        gfx_draw_line(vx, vy + 16, vx + 4, vy + 22, sapphire);
        gfx_draw_line(vx + 4, vy + 22, vx + 9, vy + 2, sapphire);
        gfx_draw_line(vx + 9, vy + 2, vx + vw, vy + 2, sapphire);
        if (fv_fn != 0) FontVectorDrawString(vx + 12, vy + 5, num, 75, text_col);
        else gfx_draw_string(vx + 12, vy + 5, num, text_col, 0);
    } else if (sub == 2) {
        gfx_draw_line(vx + 2, vy + 2, vx + 16, vy + 2, yellow);
        gfx_draw_line(vx + 2, vy + 2, vx + 10, vy + 14, yellow);
        gfx_draw_line(vx + 10, vy + 14, vx + 2, vy + 26, yellow);
        gfx_draw_line(vx + 2, vy + 26, vx + 16, vy + 26, yellow);
        if (fv_fn != 0) { FontVectorDrawString(vx + 22, vy + 6, num, 75, sapphire); if (den[0]) FontVectorDrawString(vx + 22 + FontVectorMeasureString(num, 75) + 4, vy + 12, den, 70, DolDocResolveColor(SEM_COLOR_PEACH)); }
        else { gfx_draw_string(vx + 22, vy + 6, num, sapphire, 0); if (den[0]) gfx_draw_string(vx + 22 + strlen(num) * 8 + 4, vy + 14, den, DolDocResolveColor(SEM_COLOR_PEACH), 0); }
    } else {
        gfx_draw_line(vx + 10, vy + 2, vx + 14, vy + 2, teal);
        gfx_draw_line(vx + 10, vy + 2, vx + 6, vy + 26, teal);
        gfx_draw_line(vx + 2, vy + 26, vx + 6, vy + 26, teal);
        if (fv_fn != 0) FontVectorDrawString(vx + 18, vy + 6, num, 75, sapphire);
        else gfx_draw_string(vx + 18, vy + 6, num, sapphire, 0);
    }
}

// ============================================================================
// Widget drawing (dispatched from the tree walk)
// ============================================================================
U0 DolDocDrawWidget(CDocNode *nd, I64 scroll) {
    I64 vx = nd->x;
    I64 vy = nd->y + scroll;
    I64 vw = nd->w;
    I64 vh = nd->h;
    U8 *args = nd->arg_off ? (g_doc_args + nd->arg_off) : "";
    U8 *lbl = nd->text_len ? (g_doc_text + nd->text_off) : "";

    U32 surface0 = DolDocResolveColor(SEM_COLOR_SURFACE0);
    U32 surface1 = DolDocResolveColor(SEM_COLOR_SURFACE1);
    U32 crust = DolDocResolveColor(SEM_COLOR_CRUST);
    U32 text_col = DolDocResolveColor(SEM_COLOR_TEXT);
    U32 yellow = DolDocResolveColor(SEM_COLOR_YELLOW);
    U32 sapphire = DolDocResolveColor(SEM_COLOR_SAPPHIRE);
    U32 teal = DolDocResolveColor(SEM_COLOR_TEAL);
    U32 blue = DolDocResolveColor(SEM_COLOR_BLUE);
    U32 sky = DolDocResolveColor(SEM_COLOR_SKY);
    U32 peach = DolDocResolveColor(SEM_COLOR_PEACH);

    I64 kind = nd->kind;
    if (kind == DOC_CARD || kind == DOC_BOX) {
        U32 bg = DolDocResolveColor((U32)nd->val);
        U32 border = DolDocResolveColor((U32)nd->min);
        I64 rad = g_theme.corner_radius;
        if (kind == DOC_CARD) gfx_draw_soft_shadow(vx, vy, vw, vh, 6, g_theme.shadow_color);
        if (rad > 0) {
            if (border) gfx_draw_rounded_rect(vx, vy, vw, vh, rad, border);
            gfx_draw_rounded_rect(vx + 1, vy + 1, vw - 2, vh - 2, rad - 1, bg);
        } else {
            if (border) gfx_draw_rect(vx, vy, vw, vh, border);
            gfx_draw_rect(vx + 2, vy + 2, vw - 4, vh - 4, bg);
        }
        if (kind == DOC_CARD && lbl[0]) {
            I64 bl = strlen(lbl);
            I64 badge_w = bl * 8 + 16; if (badge_w > vw - 24) badge_w = vw - 24;
            gfx_draw_rounded_rect(vx + 12, vy + 4, badge_w, 18, 4, surface0);
            gfx_draw_string(vx + 20, vy + 5, lbl, yellow, 0);
        }
        return;
    }
    if (kind == DOC_RULE) { gfx_draw_rect(vx, vy + 8, vw, 1, surface1); return; }
    if (kind == DOC_GLASS) { DolDocDrawGlass(vx, vy, vw, vh, nd->val); return; }
    if (kind == DOC_SHADOW) { DolDocDrawShadow(vx, vy, vw, vh, nd->val); return; }
    if (kind == DOC_BUTTON) {
        I64 pressed = nd->state;
        I64 dy = pressed ? 1 : 0;
        if (!pressed) gfx_draw_soft_shadow(vx, vy, vw, vh, 4, g_theme.shadow_color);
        U32 body = pressed ? surface0 : surface1;
        if (g_theme.corner_radius > 0) gfx_draw_rounded_rect(vx, vy + dy, vw, vh - dy, 4, body);
        else { gfx_draw_rect(vx, vy + dy, vw, vh - dy, body); gfx_draw_rect(vx, vy + dy, vw, 1, blue); }
        if (!pressed) { gfx_blend_rect(vx + 4, vy + 1, vw - 8, 1, 0x2AFFFFFF); gfx_blend_rect(vx + 4, vy + vh - 1, vw - 8, 1, 0x40000000); }
        gfx_draw_string(vx + (vw - strlen(lbl) * 8) / 2, vy + dy + (vh - 16) / 2, lbl, pressed ? blue : text_col, 0);
        return;
    }
    if (kind == DOC_LINK) {
        gfx_draw_string(vx, vy + 1, lbl, sky, 0);
        gfx_draw_rect(vx, vy + 15, strlen(lbl) * 8, 1, sky);
        return;
    }
    if (kind == DOC_SLIDER) {
        I64 val = nd->val;
        if (nd->target != 0) { val = *(I64*)(nd->target); nd->val = val; }
        I64 mn = nd->min; I64 mx = nd->max; if (mx <= mn) mx = mn + 100;
        if (val < mn) val = mn; if (val > mx) val = mx;
        I64 track_y = vy + (vh - 6) / 2;
        gfx_draw_rounded_rect(vx, track_y, vw, 6, 3, crust);
        I64 fill_w = ((val - mn) * (vw - 12)) / (mx - mn);
        if (fill_w < 0) fill_w = 0; if (fill_w > vw - 12) fill_w = vw - 12;
        if (fill_w > 0) gfx_draw_rounded_rect(vx, track_y, fill_w + 6, 6, 3, teal);
        I64 thumb_x = vx + fill_w + 6; I64 thumb_y = track_y + 3;
        gfx_draw_circle_filled(thumb_x, thumb_y, 7, text_col);
        gfx_draw_circle_filled(thumb_x, thumb_y, 5, sapphire);
        U8 vs[16]; I64 tv = val; I64 pi = 0;
        if (tv <= 0) { vs[0] = '0'; vs[1] = 0; }
        else { U8 rev[16]; I64 ri = 0; while (tv > 0 && ri < 12) { rev[ri] = '0' + (tv % 10); ri++; tv /= 10; } for (I64 d = 0; d < ri; d++) vs[d] = rev[ri - 1 - d]; vs[ri] = 0; }
        gfx_draw_string(vx + vw + 8, vy + 2, vs, yellow, 0);
        return;
    }
    if (kind == DOC_DATA) {
        I64 val = nd->val;
        if (nd->target != 0) { val = *(I64*)(nd->target); nd->val = val; }
        gfx_draw_rounded_rect(vx, vy + 2, vw, 14, 3, surface0);
        U8 vs[24]; I64 tv = val; I64 ri = 0; U8 rev[24];
        if (tv < 0) { vs[0] = '-'; tv = -tv; ri = 1; }
        I64 ri2 = 0;
        if (tv == 0) { rev[ri2] = '0'; ri2++; } else { while (tv > 0 && ri2 < 20) { rev[ri2] = '0' + (tv % 10); ri2++; tv /= 10; } }
        for (I64 d = 0; d < ri2; d++) vs[ri + d] = rev[ri2 - 1 - d];
        vs[ri + ri2] = 0;
        gfx_draw_string(vx + 6, vy + 1, lbl, DolDocResolveColor(SEM_COLOR_SUBTEXT), 0);
        gfx_draw_string(vx + 6, vy + 1 + 0, "", text_col, 0);
        gfx_draw_rounded_rect(vx + vw - 34, vy + 2, 16, 14, 2, surface1);
        gfx_draw_string(vx + vw - 30, vy + 1, "-", text_col, 0);
        gfx_draw_rounded_rect(vx + vw - 16, vy + 2, 16, 14, 2, surface1);
        gfx_draw_string(vx + vw - 12, vy + 1, "+", text_col, 0);
        gfx_draw_string(vx + vw / 2 - 8, vy + 1, vs, yellow, 0);
        return;
    }
    if (kind == DOC_TOGGLE) {
        I64 is_chk = nd->state;
        U32 box_bg = is_chk ? blue : surface0;
        gfx_draw_rounded_rect(vx, vy + 2, 14, 14, 3, box_bg);
        if (is_chk) {
            gfx_draw_line(vx + 3, vy + 8, vx + 6, vy + 11, crust);
            gfx_draw_line(vx + 6, vy + 11, vx + 11, vy + 4, crust);
        }
        if (lbl[0]) gfx_draw_string(vx + 20, vy + 1, lbl, text_col, 0);
        return;
    }
    if (kind == DOC_PROGRESS) {
        I64 val = nd->val; I64 mx = nd->max; if (mx <= 0) mx = 100;
        if (val < 0) val = 0; if (val > mx) val = mx;
        gfx_draw_rounded_rect(vx, vy + 4, vw, 10, 5, crust);
        I64 fill_w = (val * vw) / mx;
        if (fill_w > 0) { if (fill_w < 6) fill_w = 6; gfx_draw_rounded_rect(vx, vy + 4, fill_w, 10, 5, teal); }
        I64 pct = (val * 100) / mx; U8 pb[8]; I64 pi = 0;
        if (pct >= 100) { pb[pi++] = '1'; pb[pi++] = '0'; pb[pi++] = '0'; }
        else if (pct >= 10) { pb[pi++] = '0' + ((pct / 10) % 10); pb[pi++] = '0' + (pct % 10); }
        else pb[pi++] = '0' + (pct % 10);
        pb[pi++] = '%'; pb[pi] = 0;
        gfx_draw_string(vx + vw + 8, vy + 1, pb, peach, 0);
        return;
    }
    if (kind == DOC_TREE) {
        I64 is_open = nd->state;
        if (is_open) { gfx_draw_line(vx + 2, vy + 6, vx + 7, vy + 11, yellow); gfx_draw_line(vx + 7, vy + 11, vx + 12, vy + 6, yellow); }
        else { gfx_draw_line(vx + 4, vy + 3, vx + 9, vy + 8, sky); gfx_draw_line(vx + 9, vy + 8, vx + 4, vy + 13, sky); }
        if (lbl[0]) gfx_draw_string(vx + 18, vy + 1, lbl, text_col, 0);
        return;
    }
    if (kind == DOC_EQ) { DolDocRenderEquation(vx, vy, vw, vh, nd->state, args); return; }
    if (kind == DOC_GRAPH) { DolDocRenderGraphNode(vx, vy, vw, vh, args); return; }
    if (kind == DOC_BITMAP) { DolDocRenderSprite3D(vx, vy, vw, vh, args); return; }
    if (kind == DOC_SHADER) { DolDocRenderShaderNode(vx, vy, vw, vh, args); return; }
    if (kind == DOC_FONT) {
        U32 fcol = DolDocResolveColor((U32)nd->min);
        if (symbols_lookup("FontVectorDrawString") != 0) FontVectorDrawString(vx, vy + 2, lbl, nd->val, fcol);
        else { gfx_draw_string(vx, vy + 2, lbl, fcol, 0); gfx_draw_string(vx + 1, vy + 2, lbl, fcol, 0); }
        return;
    }
}

// ============================================================================
// Tree rendering
// ============================================================================
U0 DolDocDrawChildren(I64 parent, I64 scroll) {
    I64 n = g_doc_nodes[parent].first;
    while (n >= 0) {
        DolDocDrawNode(n, scroll);
        n = g_doc_nodes[n].next;
    }
}

U0 DolDocDrawNode(I64 nid, I64 scroll) {
    CDocNode *nd = &g_doc_nodes[nid];
    if (nd->kind == DOC_TEXT) {
        I64 x = nd->x;
        I64 y = nd->y + scroll;
        if (y + nd->h < g_doc_y || y > g_doc_y + g_doc_h) return;
        for (I64 i = 0; i < nd->text_len; i++) {
            I64 ci = nd->text_off + i;
            U8 ch = g_doc_text[ci];
            if (ch > 32 && ch <= 126) {
                U32 fg = (U32)(g_doc_attr[ci] & 0xFFFFFFFF);
                gfx_draw_char(x + i * 8, y, ch, DolDocResolveColor(fg), 0);
            }
        }
        return;
    }
    if (nd->kind == DOC_WINDOW) { DolDocDrawWindowNode(nid, scroll); return; }
    DolDocDrawWidget(nd, scroll);
}

U0 DolDocRedraw() {
    if (g_doc_dirty_mask == 0 && g_doc_dirty == 0) return;
    g_doc_anim_tick++;
    gfx_set_clip(g_doc_x, g_doc_y, g_doc_w, g_doc_h);
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h, DolDocResolveColor(g_doc_cur_bg));
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, 1, DolDocResolveColor(SEM_COLOR_SURFACE0));
    DolDocDrawChildren(g_doc_root, g_doc_scroll_offset * 18);
    if (g_doc_inspected_nid >= 0 && g_doc_inspected_nid < g_doc_node_count) DolDocDrawHalo(g_doc_inspected_nid);
    gfx_reset_clip();
    g_doc_dirty_mask = 0;
    g_doc_dirty = 0;
}

U0 DolDocAnimateTick() {
    if (g_doc_node_count <= 0) return;
    g_doc_anim_tick++;
    I64 scroll = g_doc_scroll_offset * 18;
    for (I64 n = 0; n < g_doc_node_count; n++) {
        I64 k = g_doc_nodes[n].kind;
        if (k == DOC_SHADER || k == DOC_BITMAP || k == DOC_GRAPH) {
            I64 vx = g_doc_nodes[n].x; I64 vy = g_doc_nodes[n].y + scroll;
            I64 vw = g_doc_nodes[n].w; I64 vh = g_doc_nodes[n].h;
            if (vy + vh < g_doc_y || vy > g_doc_y + g_doc_h) continue;
            U8 *a = g_doc_nodes[n].arg_off ? (g_doc_args + g_doc_nodes[n].arg_off) : "";
            if (k == DOC_SHADER) DolDocRenderShaderNode(vx, vy, vw, vh, a);
            else if (k == DOC_BITMAP) DolDocRenderSprite3D(vx, vy, vw, vh, a);
            else DolDocRenderGraphNode(vx, vy, vw, vh, a);
            gfx_swap_rect(vx, vy, vw, vh);
        }
    }
    if (g_doc_inspected_nid >= 0 && g_doc_inspected_nid < g_doc_node_count) DolDocDrawHalo(g_doc_inspected_nid);
}

// ============================================================================
// Smalltalk Morphic halo
// ============================================================================
U0 DolDocDrawHalo(I64 nid) {
    if (nid < 0 || nid >= g_doc_node_count) return;
    CDocNode *nd = &g_doc_nodes[nid];
    I64 vx = nd->x; I64 vy = nd->y + g_doc_scroll_offset * 18; I64 vw = nd->w; I64 vh = nd->h;
    U32 yellow = DolDocResolveColor(SEM_COLOR_YELLOW);
    U32 sapphire = DolDocResolveColor(SEM_COLOR_SAPPHIRE);
    U32 red = DolDocResolveColor(SEM_COLOR_RED);
    U32 teal = DolDocResolveColor(SEM_COLOR_TEAL);
    U32 green = DolDocResolveColor(SEM_COLOR_GREEN);
    U32 mantle = DolDocResolveColor(SEM_COLOR_MANTLE);
    gfx_draw_rect(vx - 1, vy - 1, vw + 2, 1, yellow);
    gfx_draw_rect(vx - 1, vy + vh, vw + 2, 1, yellow);
    gfx_draw_rect(vx - 1, vy - 1, 1, vh + 2, yellow);
    gfx_draw_rect(vx + vw, vy - 1, 1, vh + 2, yellow);
    gfx_draw_rounded_rect(vx - 2, vy - 6, 10, 10, 2, sapphire); gfx_draw_string(vx, vy - 5, "S", mantle, 0);
    gfx_draw_rounded_rect(vx + vw - 8, vy - 6, 10, 10, 2, red); gfx_draw_string(vx + vw - 6, vy - 5, "X", mantle, 0);
    gfx_draw_rounded_rect(vx - 2, vy + vh - 4, 10, 10, 2, teal); gfx_draw_string(vx, vy + vh - 3, "?", mantle, 0);
    gfx_draw_rounded_rect(vx + vw - 8, vy + vh - 4, 10, 10, 2, green); gfx_draw_string(vx + vw - 6, vy + vh - 3, "D", mantle, 0);
}

// ============================================================================
// Hit testing & interaction
// ============================================================================
I64 DolDocHitTest(I64 mx, I64 my) {
    I64 doc_my = my - g_doc_scroll_offset * 18;
    for (I64 n = g_doc_node_count - 1; n >= 0; n--) {
        CDocNode *nd = &g_doc_nodes[n];
        if (nd->kind == DOC_ROOT || nd->kind == DOC_TEXT || nd->kind == DOC_WINDOW) continue;
        if (nd->kind == DOC_CARD || nd->kind == DOC_BOX || nd->kind == DOC_GLASS || nd->kind == DOC_SHADOW) continue;
        if (mx >= nd->x && mx < nd->x + nd->w && doc_my >= nd->y && doc_my < nd->y + nd->h) return n;
    }
    return -1;
}

I64 DolDocHandleClick(I64 mx, I64 my) {
    if (mx < g_doc_x || my < g_doc_y || mx >= g_doc_x + g_doc_w || my >= g_doc_y + g_doc_h) return 0;
    I64 nid = DolDocHitTest(mx, my);
    if (nid < 0) return 0;
    CDocNode *nd = &g_doc_nodes[nid];

    if (g_doc_inspector_mode) {
        g_doc_inspected_nid = nid;
        doldoc_printf("\n$FG,YELLOW$[MORPHIC HALO]$FG$ Node #%lld kind=%lld box=(%lld,%lld,%lldx%lld) target=0x%llX\n",
                      nid, nd->kind, nd->x, nd->y, nd->w, nd->h, nd->target);
        DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
        return 1;
    }

    U8 *cmd = nd->arg_off ? (g_doc_args + nd->arg_off) : "";
    if (nd->kind == DOC_BUTTON || nd->kind == DOC_LINK) {
        if (cmd[0] == '#') {
            I64 an = DolDocFindAnchor(cmd + 1);
            if (an >= 0 && an < g_doc_node_count) {
                g_doc_scroll_offset = 0;
                DolDocMarkAllDirty();
            }
        } else if (cmd[0]) {
            strcpy(g_click_cmd_buf, cmd);
            DolDocPrint("\n$FG,YELLOW$[CLICK]$FG$ $FG,CYAN$");
            DolDocPrint(g_click_cmd_buf);
            DolDocPrint("$FG$\n");
            DolDocPushAction(DOC_ACT_RUN, -1, 0, g_click_cmd_buf);
            return 1;
        }
        DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
        return 1;
    }
    if (nd->kind == DOC_SLIDER) {
        g_doc_drag_nid = nid;
        I64 mn = nd->min; I64 mx = nd->max; if (mx <= mn) mx = mn + 100;
        I64 nv = mn + ((mx - nd->x) * (mx - mn)) / (nd->w > 0 ? nd->w : 1);
        DolDocCellWrite(nid, nv);
        DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
        return 1;
    }
    if (nd->kind == DOC_DATA) {
        I64 mn = nd->min; I64 mx = nd->max;
        if (mx - nd->x > 0) { }
        if (mx > nd->x + nd->w - 16) DolDocCellWrite(nid, nd->val + (mx - mn) / 20 + 1);
        else DolDocCellWrite(nid, nd->val - ((mx - mn) / 20 + 1));
        DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
        return 1;
    }
    if (nd->kind == DOC_TOGGLE || nd->kind == DOC_TREE) {
        nd->state = 1 - nd->state;
        if (nd->target != 0) DolDocPatchTarget(nd->target, nd->state);
        DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
        return 1;
    }
    if (nd->kind == DOC_SHADER || nd->kind == DOC_BITMAP || nd->kind == DOC_GRAPH) {
        DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
        return 1;
    }
    return 0;
}

I64 DolDocHandleDrag(I64 mx, I64 my) {
    if (g_doc_drag_nid >= 0 && g_doc_drag_nid < g_doc_node_count) {
        CDocNode *nd = &g_doc_nodes[g_doc_drag_nid];
        if (nd->kind == DOC_SLIDER) {
            I64 mn = nd->min; I64 mx = nd->max; if (mx <= mn) mx = mn + 100;
            I64 nv = mn + ((mx - nd->x) * (mx - mn)) / (nd->w > 0 ? nd->w : 1);
            if (nv != nd->val) { DolDocCellWrite(g_doc_drag_nid, nv); DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term(); }
            return 1;
        }
    }
    return 0;
}

I64 DolDocHandleMouseUp() {
    if (g_doc_drag_nid >= 0) { g_doc_drag_nid = -1; return 1; }
    return 0;
}

U0 DolDocMove(I64 x, I64 y, I64 w, I64 h) {
    I64 dx = x - g_doc_x;
    I64 dy = y - g_doc_y;
    g_doc_x = x; g_doc_y = y; g_doc_w = w; g_doc_h = h;
    g_doc_cols = (w > 16) ? (w - 16) / 8 : 80;
    g_doc_rows = (h > 16) ? (h - 16) / 18 : 24;
    if (g_doc_cols > 256) g_doc_cols = 256;
    if (g_doc_rows > 64) g_doc_rows = 64;
    if (g_doc_col >= g_doc_cols) g_doc_col = g_doc_cols - 1;
    if (g_doc_row >= g_doc_rows) g_doc_row = g_doc_rows - 1;
    if (dx != 0 || dy != 0) {
        for (I64 n = 0; n < g_doc_node_count; n++) {
            if (g_doc_nodes[n].kind == DOC_WINDOW) continue;
            g_doc_nodes[n].x += dx;
            g_doc_nodes[n].y += dy;
        }
    }
    DolDocUpdateCursor();
    DolDocMarkAllDirty();
}

// ============================================================================
// Compositor (dissolved from Compositor.HC): damage, present, effects, pacing
// ============================================================================
// Compositor (dissolved from Compositor.HC): damage, present, effects, pacing
// ============================================================================
U0 DolDocCompositorInit() {
    g_comp.screen_w = gfx_get_canvas_width();
    g_comp.screen_h = gfx_get_canvas_height();
    g_comp.screen_pitch = gfx_get_canvas_pitch();
    if (g_comp.screen_w <= 0) g_comp.screen_w = 1024;
    if (g_comp.screen_h <= 0) g_comp.screen_h = 768;
    g_comp.vsync_hz = 0;
    g_comp.shadows_enabled = 1;
    g_comp.glass_enabled = 1;
    g_comp.rounded_corners = 1;
    g_comp.dirty_blit_enabled = 1;
    g_comp.frame_count = 0;
    g_comp.fps = 60;
    g_comp.last_fps_time_sec = timer_get_uptime_sec();
    g_comp.frame_time_us = 12000;
    g_comp.last_frame_start_us = timer_get_uptime_us();
    if (g_theme.bg_base == 0) ThemeApply(THEME_MOCHA);
    g_doc_comp_ready = 1;
}

U0 DolDocDamageAll() { gfx_dirty_all(); g_doc_dirty = 1; }
U0 DolDocDamageRect(I64 x, I64 y, I64 w, I64 h) { if (w <= 0 || h <= 0) return; GfxDeviceDamage(x, y, w, h); g_doc_dirty = 1; }
U0 DolDocDamageWindow(I64 wx, I64 wy, I64 ww, I64 wh) {
    I64 pad = g_comp.shadows_enabled ? 16 : 4;
    DolDocDamageRect(wx - pad, wy - pad, ww + pad * 2, wh + pad * 2);
}

U0 DolDocDrawShadow(I64 x, I64 y, I64 w, I64 h, I64 spread) {
    if (!g_comp.shadows_enabled) return;
    if (spread <= 0) spread = 6;
    U32 base_rgb = g_theme.shadow_color & 0x00FFFFFF;
    gfx_blend_rect(x - spread, y - spread / 2, w + spread * 2, h + spread * 2, 0x18000000 | base_rgb);
    gfx_blend_rect(x - spread / 2, y - 1, w + spread, h + spread + 2, 0x2C000000 | base_rgb);
    gfx_blend_rect(x - 2, y + 1, w + 4, h + 4, 0x48000000 | base_rgb);
}

U0 DolDocDrawGlass(I64 x, I64 y, I64 w, I64 h, I64 alpha) {
    if (alpha <= 0) alpha = 0xC8;
    U32 col = ((alpha & 0xFF) << 24) | (g_theme.glass_tint & 0x00FFFFFF);
    gfx_blend_rect(x, y, w, h, col);
    gfx_blend_rect(x + 2, y, w - 4, 1, 0x30FFFFFF);
}

U0 DolDocCompositorEndFrame() {
    I64 cur_us = timer_get_uptime_us();
    if (cur_us > g_comp.last_frame_start_us) g_comp.frame_time_us = cur_us - g_comp.last_frame_start_us;
    g_comp.frame_count++;
    I64 cur_sec = timer_get_uptime_sec();
    if (cur_sec != g_comp.last_fps_time_sec) {
        g_comp.fps = g_comp.frame_count;
        if (g_comp.fps <= 0) g_comp.fps = 60;
        g_comp.frame_count = 0;
        g_comp.last_fps_time_sec = cur_sec;
    }
}

U0 DolDocPresent() {
    g_comp.last_frame_start_us = timer_get_uptime_us();
    if (g_comp.dirty_blit_enabled && RenderDirtyActive()) {
        I64 c_x = 0; I64 c_y = 0; I64 c_w = 0; I64 c_h = 0;
        RenderDirtyBounds(&c_x, &c_y, &c_w, &c_h);
        if (c_x < 0) { c_w = c_w + c_x; c_x = 0; }
        if (c_y < 0) { c_h = c_h + c_y; c_y = 0; }
        if (c_x + c_w > g_comp.screen_w) c_w = g_comp.screen_w - c_x;
        if (c_y + c_h > g_comp.screen_h) c_h = g_comp.screen_h - c_y;
        if (c_w >= g_comp.screen_w && c_h >= g_comp.screen_h) GfxPresent(0, 0, g_comp.screen_w, g_comp.screen_h, 1);
        else if (c_w > 0 && c_h > 0) GfxPresent(c_x, c_y, c_w, c_h, 0);
    } else {
        GfxPresent(0, 0, g_comp.screen_w, g_comp.screen_h, 1);
    }
    gfx_dirty_reset();
    if (g_comp.vsync_hz > 0) gfx_vsync_wait();
    DolDocCompositorEndFrame();
}

U0 DolDocCompositorDashboard() {
    doldoc_print("\n$CARD,title=\"NeoOS Sovereign Compositor & Theme Engine\",w=108,h=10$\n");
    doldoc_printf("  Canvas Resolution : $FG,YELLOW$%lld x %lld$FG$ (Pitch: %lld px)\n", g_comp.screen_w, g_comp.screen_h, g_comp.screen_pitch);
    doldoc_printf("  Active Theme Skin : $FG,CYAN$%s$FG$ (ID #%lld | Radius: %lldpx | Border: %lldpx)\n", g_theme.name, g_theme.theme_id, g_theme.corner_radius, g_theme.border_w);
    doldoc_printf("  Effects Pipeline  : Shadows=%s | AcrylicGlass=%s | DirtyBlit=%s | VSync=%lld Hz\n",
                  g_comp.shadows_enabled ? "ON" : "OFF", g_comp.glass_enabled ? "ON" : "OFF", g_comp.dirty_blit_enabled ? "ON" : "OFF", g_comp.vsync_hz);
    doldoc_printf("  Live Frame Pacing : $FG,GREEN$%lld FPS$FG$ ($FG,YELLOW$%lld us/frame$FG$)\n", g_comp.fps, g_comp.frame_time_us);
    doldoc_print("$HR$\n");
    doldoc_print("  $FG,YELLOW$Switch Semantic Theme Skin:$FG$\n");
    doldoc_print("   $BT,\"Mocha\",LM=\"theme mocha\"$  $BT,\"Latte (Light)\",LM=\"theme latte\"$  $BT,\"Tokyo Night\",LM=\"theme tokyo\"$  $BT,\"Nord\",LM=\"theme nord\"$  $BT,\"TempleOS CGA\",LM=\"theme temple\"$  $BT,\"Cyberpunk OLED\",LM=\"theme cyberpunk\"$\n");
    doldoc_print("  $FG,YELLOW$Compositor Pipeline Controls:$FG$\n");
    doldoc_print("   $BT,\"Toggle Shadows\",LM=\"compositor shadow\"$  $BT,\"Toggle Glass\",LM=\"compositor glass\"$  $BT,\"Toggle Corners\",LM=\"compositor round\"$  $BT,\"V-Sync 60Hz\",LM=\"compositor vsync 60\"$  $BT,\"Uncapped\",LM=\"compositor vsync 0\"$\n");
    doldoc_print("$HR$\n\n");
}

U0 DolDocCompositorCmd(U8 *cmd) {
    if (!cmd) { DolDocCompositorDashboard(); return; }
    while (*cmd == ' ') cmd++;
    if (*cmd == 0) { DolDocCompositorDashboard(); return; }
    if (strncmp(cmd, "theme", 5) == 0) {
        U8 *targ = cmd + 5; while (*targ == ' ') targ++;
        ThemeSetByName(targ);
        DolDocSetBgColor(g_theme.bg_mantle);
        DolDocDamageAll();
        doldoc_printf("$FG,GREEN$[THEME]$FG$ Applied semantic theme skin: $FG,CYAN$%s$FG$\n", g_theme.name);
        return;
    }
    if (strncmp(cmd, "vsync", 5) == 0) {
        U8 *arg = cmd + 5; while (*arg == ' ') arg++;
        if (strcmp(arg, "60") == 0) { g_comp.vsync_hz = 60; gfx_vsync_set(1, 60); doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ V-Sync locked to 60 Hz.\n"); }
        else if (strcmp(arg, "120") == 0) { g_comp.vsync_hz = 120; gfx_vsync_set(1, 120); doldoc_print("$FG,GREEN$[COMPOSITOR]$FG$ V-Sync locked to 120 Hz.\n"); }
        else { g_comp.vsync_hz = 0; gfx_vsync_set(0, 0); doldoc_print("$FG,YELLOW$[COMPOSITOR]$FG$ V-Sync disabled (Uncapped FPS).\n"); }
    } else if (strncmp(cmd, "shadow", 6) == 0) { g_comp.shadows_enabled = !g_comp.shadows_enabled; doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Soft Drop Shadows: %s\n", g_comp.shadows_enabled ? "ENABLED" : "DISABLED"); DolDocDamageAll(); }
    else if (strncmp(cmd, "glass", 5) == 0) { g_comp.glass_enabled = !g_comp.glass_enabled; doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Acrylic Glass: %s\n", g_comp.glass_enabled ? "ENABLED" : "DISABLED"); DolDocDamageAll(); }
    else if (strncmp(cmd, "blit", 4) == 0) { g_comp.dirty_blit_enabled = !g_comp.dirty_blit_enabled; doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Dirty Rect Blitting: %s\n", g_comp.dirty_blit_enabled ? "ENABLED" : "DISABLED"); }
    else if (strncmp(cmd, "round", 5) == 0) { g_comp.rounded_corners = !g_comp.rounded_corners; doldoc_printf("$FG,GREEN$[COMPOSITOR]$FG$ Rounded Corners: %s\n", g_comp.rounded_corners ? "ENABLED" : "DISABLED"); DolDocDamageAll(); }
    else DolDocCompositorDashboard();
}

// ============================================================================
// Windows are documents ($WIN$): the desktop continuum (dissolved WM.HC)
// ============================================================================
I64 g_doc_win_count = 0;
I64 g_doc_win_active = 0;
I64 g_doc_desktop_running = 0;
I64 g_doc_menu_open = 0;
I64 g_doc_prev_btn = 0;
I64 g_doc_drag_win = 0;
I64 g_doc_drag_ox = 0;
I64 g_doc_drag_oy = 0;
I64 g_doc_resize_win = 0;
I64 g_doc_resize_ow = 0;
I64 g_doc_resize_oh = 0;
I64 g_doc_resize_mx = 0;
I64 g_doc_resize_my = 0;
I64 g_doc_is_drag = 0;
I64 g_doc_is_resize = 0;
I64 g_doc_win_nodes[DOC_MAX_WINDOWS];
I64 g_doc_win_zorder[DOC_MAX_WINDOWS];

U0 wm_set_dirty() { g_doc_dirty = 1; }

I64 DolDocWinById(I64 id) {
    for (I64 i = 0; i < g_doc_win_count; i++) if (g_doc_win_nodes[i] >= 0 && g_doc_nodes[g_doc_win_nodes[i]].win_id == id) return i;
    return -1;
}

U0 DolDocWinFocus(I64 id) {
    g_doc_win_active = id;
    I64 pos = -1;
    for (I64 i = 0; i < g_doc_win_count; i++) if (g_doc_nodes[g_doc_win_nodes[i]].win_id == id) pos = i;
    if (pos >= 0 && pos < g_doc_win_count - 1) {
        I64 t = g_doc_win_zorder[pos];
        for (I64 j = pos; j < g_doc_win_count - 1; j++) g_doc_win_zorder[j] = g_doc_win_zorder[j + 1];
        g_doc_win_zorder[g_doc_win_count - 1] = t;
    }
    g_doc_dirty = 1;
}

I64 DolDocWinCreate(U8 *title, I64 x, I64 y, I64 w, I64 h, I64 kind) {
    if (g_doc_win_count >= DOC_MAX_WINDOWS) return -1;
    I64 n = DolDocNewNode(DOC_WINDOW, -1);
    if (n < 0) return -1;
    CDocNode *nd = &g_doc_nodes[n];
    nd->x = x; nd->y = y; nd->w = w; nd->h = h; nd->state = kind;
    nd->flags = DOCF_OPEN;
    nd->win_id = g_doc_win_count + 1;
    nd->text_off = g_doc_text_used;
    for (I64 i = 0; title[i] && g_doc_text_used < DOC_MAX_TEXT - 1; i++) { g_doc_text[g_doc_text_used] = title[i]; g_doc_attr[g_doc_text_used] = 0; g_doc_text_used++; }
    nd->text_len = g_doc_text_used - nd->text_off;
    g_doc_win_nodes[g_doc_win_count] = n;
    g_doc_win_zorder[g_doc_win_count] = g_doc_win_count;
    g_doc_win_count++;
    DolDocWinFocus(nd->win_id);
    return nd->win_id;
}

U0 DolDocWinClose(I64 id) {
    I64 idx = DolDocWinById(id);
    if (idx < 0) return;
    I64 n = g_doc_win_nodes[idx];
    if (g_doc_nodes[n].win_id == 1) { g_doc_nodes[n].flags |= DOCF_MIN; g_doc_dirty = 1; return; }
    DolDocDamageWindow(g_doc_nodes[n].x, g_doc_nodes[n].y, g_doc_nodes[n].w, g_doc_nodes[n].h);
    DolDocUnlink(n);
    for (I64 i = idx; i < g_doc_win_count - 1; i++) { g_doc_win_nodes[i] = g_doc_win_nodes[i + 1]; g_doc_win_zorder[i] = g_doc_win_zorder[i + 1]; }
    g_doc_win_count--;
    if (g_doc_win_count > 0) DolDocWinFocus(g_doc_nodes[g_doc_win_nodes[g_doc_win_count - 1]].win_id);
    g_doc_dirty = 1;
}

U0 DolDocWinChrome(CDocNode *win, I64 active) {
    I64 tb_h = g_theme.titlebar_h; if (tb_h < 26) tb_h = 30;
    I64 rad = g_theme.corner_radius;
    U32 border_col = active ? g_theme.border_active : g_theme.border_subtle;
    I64 bw = g_theme.border_w; if (bw < 1) bw = 1;
    DolDocDrawShadow(win->x, win->y, win->w, win->h, 8);
    gfx_draw_rect(win->x - bw, win->y - bw, win->w + bw * 2, win->h + bw * 2, border_col);
    U32 body_bg = (win->state == 0) ? g_theme.bg_mantle : g_theme.bg_base;
    if (g_comp.glass_enabled && win->state != 0) DolDocDrawGlass(win->x, win->y, win->w, win->h, 0xD8);
    else if (g_comp.rounded_corners && rad > 0) gfx_draw_rounded_rect(win->x, win->y, win->w, win->h, rad, body_bg);
    else gfx_draw_rect(win->x, win->y, win->w, win->h, body_bg);
    U32 tb_col = active ? g_theme.bg_surface0 : g_theme.bg_mantle;
    gfx_draw_rect(win->x, win->y, win->w, tb_h, tb_col);
    gfx_draw_rect(win->x, win->y + tb_h - 1, win->w, 1, border_col);
    U8 title[64];
    strncpy(title, g_doc_text + win->text_off, 63); title[63] = 0;
    I64 maxc = (win->w - 82) / 8; if (maxc < 4) maxc = 4;
    if (strlen(title) > maxc) { title[maxc - 3] = '.'; title[maxc - 2] = '.'; title[maxc - 1] = '.'; title[maxc] = 0; }
    gfx_draw_string(win->x + 12, win->y + 7, title, g_theme.text_primary, 0);
    gfx_draw_rounded_rect(win->x + win->w - 24, win->y + 7, 16, 16, 3, g_theme.status_danger); gfx_draw_char(win->x + win->w - 20, win->y + 7, 'x', g_theme.bg_crust, 0);
    gfx_draw_rounded_rect(win->x + win->w - 44, win->y + 7, 16, 16, 3, g_theme.status_success); gfx_draw_char(win->x + win->w - 40, win->y + 7, '+', g_theme.bg_crust, 0);
    gfx_draw_rounded_rect(win->x + win->w - 64, win->y + 7, 16, 16, 3, g_theme.status_warning); gfx_draw_char(win->x + win->w - 60, win->y + 7, '-', g_theme.bg_crust, 0);
    if (!(win->flags & DOCF_MAX)) {
        I64 gx = win->x + win->w; I64 gy = win->y + win->h;
        gfx_draw_line(gx - 4, gy - 12, gx - 12, gy - 4, g_theme.text_muted);
        gfx_draw_line(gx - 4, gy - 8, gx - 8, gy - 4, g_theme.text_muted);
    }
}

U0 DolDocDrawWindowContent(CDocNode *win) {
    I64 tb_h = g_theme.titlebar_h; if (tb_h < 26) tb_h = 30;
    I64 cx = win->x + 2; I64 cy = win->y + tb_h; I64 cw = win->w - 4; I64 ch = win->h - tb_h - 2;
    if (cw <= 0 || ch <= 0) return;
    gfx_set_clip(cx, cy, cw, ch);
    I64 kind = win->state;
    if (kind == 0) {
        // console window hosts the main shell document (viewport already moved)
        DolDocDrawChildren(g_doc_root, 0);
    } else if (kind == 1) {
        gfx_draw_string(win->x + 16, win->y + 40, "Arch  : ARMv8-A Ring 0 (EL1 SASOS)", g_theme.status_success, 0);
        gfx_draw_string(win->x + 16, win->y + 58, "Skin  :", g_theme.text_secondary, 0);
        gfx_draw_string(win->x + 80, win->y + 58, g_theme.name, g_theme.status_warning, 0);
        DolDocRenderShaderNode(win->x + 16, win->y + 78, win->w - 32, 68, "plasma");
        I64 bar_w = ((timer_get_uptime_sec() * 24 + g_doc_anim_tick * 6) % (win->w - 44)) + 12;
        gfx_draw_rounded_rect(win->x + 16, win->y + 154, win->w - 32, 16, 4, g_theme.bg_crust);
        gfx_draw_rounded_rect(win->x + 16, win->y + 154, bar_w, 16, 4, g_theme.accent_teal);
    } else if (kind == 2) {
        I64 sp_w = (win->w - 36) / 2; I64 sp_h = win->h - tb_h - 40;
        if (sp_w > 16 && sp_h > 16) {
            DolDocRenderSprite3D(win->x + 14, win->y + tb_h + 24, sp_w, sp_h, "gears");
            DolDocRenderGraphNode(win->x + 22 + sp_w, win->y + tb_h + 24, sp_w, sp_h, "sine");
        }
    } else {
        I64 half_w = (win->w - 36) / 2; I64 sh_h = win->h - tb_h - 68;
        if (half_w > 20 && sh_h > 20) {
            DolDocRenderShaderNode(win->x + 14, win->y + tb_h + 36, half_w, sh_h, "torus");
            DolDocRenderShaderNode(win->x + 22 + half_w, win->y + tb_h + 36, half_w, sh_h, "wave");
        }
    }
    gfx_reset_clip();
}

U0 DolDocDrawWindowNode(I64 nid, I64 scroll) {
    CDocNode *win = &g_doc_nodes[nid];
    if (win->flags & DOCF_MIN) return;
    I64 active = (win->win_id == g_doc_win_active);
    DolDocWinChrome(win, active);
    DolDocDrawWindowContent(win);
}

U0 DolDocDesktopDraw() {
    I64 sw = g_comp.screen_w; I64 sh = g_comp.screen_h;
    gfx_draw_rect(0, 0, sw, sh - 40, g_theme.bg_crust);
    gfx_draw_rect(0, 0, sw, 28, g_theme.bg_mantle);
    gfx_draw_rect(0, 27, sw, 1, g_theme.border_subtle);
    gfx_draw_string(14, 6, "NeoOS Sovereign 3.0 Desktop Continuum", g_theme.accent_primary, 0);
    gfx_draw_string(390, 6, "Skin:", g_theme.text_muted, 0);
    gfx_draw_string(436, 6, g_theme.name, g_theme.status_warning, 0);
    gfx_draw_string(sw - 240, 6, "FPS:", g_theme.text_muted, 0);
    gfx_draw_string(sw - 200, 6, "60", g_theme.status_success, 0);
    gfx_draw_string(sw - 150, 6, "SMP:", g_theme.text_muted, 0);
    gfx_draw_string(sw - 110, 6, "4 Cores", g_theme.accent_cyan, 0);
    for (I64 zi = 0; zi < g_doc_win_count; zi++) DolDocDrawWindowNode(g_doc_win_nodes[g_doc_win_zorder[zi]], 0);
    // taskbar
    I64 ty = sh - 40;
    gfx_draw_rect(0, ty, sw, 40, g_theme.bg_mantle);
    gfx_draw_rect(0, ty, sw, 1, g_theme.border_active);
    U32 menu_col = g_doc_menu_open ? g_theme.accent_secondary : g_theme.accent_primary;
    gfx_draw_rounded_rect(8, ty + 6, 92, 28, 4, menu_col);
    gfx_draw_string(14, ty + 12, "NeoMenu", g_theme.bg_crust, 0);
    gfx_draw_rounded_rect(106, ty + 6, 74, 28, 4, g_theme.bg_surface0); gfx_draw_string(112, ty + 12, "Showcase", g_theme.status_warning, 0);
    gfx_draw_rounded_rect(186, ty + 6, 66, 28, 4, g_theme.bg_surface0); gfx_draw_string(192, ty + 12, "Shaders", g_theme.accent_cyan, 0);
    gfx_draw_rounded_rect(258, ty + 6, 56, 28, 4, g_theme.bg_surface0); gfx_draw_string(266, ty + 12, "Theme", g_theme.accent_tertiary, 0);
    gfx_draw_rounded_rect(320, ty + 6, 50, 28, 4, g_theme.bg_surface0); gfx_draw_string(328, ty + 12, "+Win", g_theme.status_success, 0);
    I64 tab_x = 378; I64 fs_x = sw - 210;
    for (I64 i = 0; i < g_doc_win_count; i++) {
        CDocNode *w = &g_doc_nodes[g_doc_win_nodes[i]];
        if (!(w->flags & DOCF_MIN) && tab_x + 96 < fs_x) {
            U32 tcol = (w->win_id == g_doc_win_active) ? g_theme.bg_surface1 : g_theme.bg_base;
            gfx_draw_rounded_rect(tab_x, ty + 6, 92, 28, 4, tcol);
            U8 tl[16]; tl[0] = '['; tl[1] = '0' + (w->win_id % 10); tl[2] = ']'; tl[3] = ' ';
            strncpy(tl + 4, g_doc_text + w->text_off, 6); tl[10] = 0;
            gfx_draw_string(tab_x + 6, ty + 12, tl, g_theme.text_primary, 0);
            tab_x += 96;
        }
    }
    gfx_draw_rounded_rect(fs_x, ty + 6, 82, 28, 4, g_theme.bg_surface0);
    gfx_draw_string(fs_x + 8, ty + 12, "Console >", g_theme.status_peach, 0);
    I64 cxx = sw - 124;
    gfx_draw_rounded_rect(cxx, ty + 6, 116, 28, 4, g_theme.bg_crust);
    gfx_draw_string(cxx + 8, ty + 12, "UP:", g_theme.text_muted, 0);
    I64 up = timer_get_uptime_sec();
    gfx_draw_char(cxx + 44, ty + 12, '0' + ((up / 100) % 10), g_theme.status_success, 0);
    gfx_draw_char(cxx + 52, ty + 12, '0' + ((up / 10) % 10), g_theme.status_success, 0);
    gfx_draw_char(cxx + 60, ty + 12, '0' + (up % 10), g_theme.status_success, 0);
    gfx_draw_char(cxx + 70, ty + 12, 's', g_theme.status_success, 0);
    if (g_doc_menu_open) DolDocDesktopMenu();
}

U0 DolDocDesktopMenu() {
    I64 mx = 8; I64 my = g_comp.screen_h - 40 - 280; I64 mw = 490; I64 mh = 274;
    DolDocDrawShadow(mx, my, mw, mh, 12);
    gfx_draw_rect(mx - 1, my - 1, mw + 2, mh + 2, g_theme.border_active);
    DolDocDrawGlass(mx, my, mw, mh, 0xE8);
    gfx_draw_rounded_rect(mx + 8, my + 8, mw - 16, 26, 4, g_theme.bg_surface0);
    gfx_draw_string(mx + 16, my + 13, "NeoOS Sovereign Application & Theme Drawer", g_theme.accent_primary, 0);
    gfx_draw_string(mx + 12, my + 44, "Flagship & 3D:", g_theme.status_warning, 0);
    gfx_draw_rounded_rect(mx + 110, my + 40, 80, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 116, my + 44, "Showcase", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 196, my + 40, 68, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 202, my + 44, "Shaders", g_theme.accent_cyan, 0);
    gfx_draw_rounded_rect(mx + 270, my + 40, 68, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 276, my + 44, "GLXGears", g_theme.status_success, 0);
    gfx_draw_rounded_rect(mx + 344, my + 40, 68, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 350, my + 44, "Physics", g_theme.status_peach, 0);
    gfx_draw_string(mx + 12, my + 80, "Themes & Skins:", g_theme.accent_secondary, 0);
    gfx_draw_rounded_rect(mx + 130, my + 76, 52, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 136, my + 80, "Mocha", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 188, my + 76, 52, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 194, my + 80, "Latte", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 246, my + 76, 52, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 252, my + 80, "Tokyo", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 304, my + 76, 48, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 310, my + 80, "Nord", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 358, my + 76, 60, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 364, my + 80, "Temple", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 424, my + 76, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 430, my + 80, "Cyber", g_theme.accent_primary, 0);
    gfx_draw_string(mx + 12, my + 116, "Compiler & JIT:", g_theme.status_success, 0);
    gfx_draw_rounded_rect(mx + 130, my + 112, 74, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 136, my + 116, "Compiler", g_theme.accent_cyan, 0);
    gfx_draw_rounded_rect(mx + 210, my + 112, 74, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 216, my + 116, "JIT Test", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 290, my + 112, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 296, my + 116, "Bench", g_theme.status_warning, 0);
    gfx_draw_rounded_rect(mx + 350, my + 112, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 356, my + 116, "Top", g_theme.status_success, 0);
    gfx_draw_rounded_rect(mx + 410, my + 112, 68, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 416, my + 116, "Memory", g_theme.text_muted, 0);
    gfx_draw_string(mx + 12, my + 152, "Storage & Tools:", g_theme.accent_tertiary, 0);
    gfx_draw_rounded_rect(mx + 130, my + 148, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 136, my + 152, "Filer", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 190, my + 148, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 196, my + 152, "Editor", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 250, my + 148, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 256, my + 152, "Calc", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 310, my + 148, 54, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 316, my + 152, "Fact", g_theme.text_primary, 0);
    gfx_draw_rounded_rect(mx + 370, my + 148, 64, 22, 3, g_theme.bg_surface1); gfx_draw_string(mx + 376, my + 152, "Inspect", g_theme.accent_teal, 0);
    gfx_draw_string(mx + 14, my + 248, "Click outside or on [NeoMenu] to dismiss", g_theme.text_muted, 0);
}

U0 DolDocDesktopInit() {
    if (g_doc_win_count > 0) return;
    I64 sw = g_comp.screen_w; I64 sh = g_comp.screen_h;
    I64 main_w = sw - 384; if (main_w < 580) main_w = 580;
    I64 main_h = sh - 88;
    DolDocWinCreate("NeoOS DolDoc 3.0 Scene Continuum (ARM64 Ring-0)", 16, 36, main_w, main_h, 0);
    DolDocWinCreate("Sovereign Telemetry & Shader Preview", main_w + 28, 36, 340, 250, 1);
    DolDocWinCreate("3D Involute Gears & Oscilloscope", main_w + 28, 298, 340, 210, 2);
    DolDocWinFocus(1);
    // Host the shell document inside window 1's client area
    DolDocMove(20, 70, main_w - 8, main_h - 40);
    g_doc_dirty = 1;
}

U0 DolDocDesktopMouse() {
    I64 mx = mouse_get_x(); I64 my = mouse_get_y(); I64 btn = mouse_get_btn();
    I64 sh = g_comp.screen_h; I64 ty = sh - 40;
    if ((btn & 1) && !g_doc_prev_btn) {
        if (g_doc_menu_open) {
            I64 d_x = 8; I64 d_y = sh - 40 - 280;
            if (mx >= d_x && mx <= d_x + 490 && my >= d_y && my <= d_y + 274) {
                if (my >= d_y + 40 && my <= d_y + 62) {
                    if (mx >= d_x + 110 && mx <= d_x + 190) DolDocPushAction(DOC_ACT_RUN, -1, 0, "showcase");
                    else if (mx >= d_x + 196 && mx <= d_x + 264) DolDocPushAction(DOC_ACT_RUN, -1, 0, "shader");
                    else if (mx >= d_x + 270 && mx <= d_x + 338) DolDocPushAction(DOC_ACT_RUN, -1, 0, "gears");
                    else if (mx >= d_x + 344 && mx <= d_x + 412) DolDocPushAction(DOC_ACT_RUN, -1, 0, "physics");
                } else if (my >= d_y + 76 && my <= d_y + 98) {
                    if (mx >= d_x + 130 && mx <= d_x + 182) { ThemeApply(0); DolDocDamageAll(); }
                    else if (mx >= d_x + 188 && mx <= d_x + 240) { ThemeApply(1); DolDocDamageAll(); }
                    else if (mx >= d_x + 246 && mx <= d_x + 298) { ThemeApply(2); DolDocDamageAll(); }
                    else if (mx >= d_x + 304 && mx <= d_x + 352) { ThemeApply(3); DolDocDamageAll(); }
                    else if (mx >= d_x + 358 && mx <= d_x + 418) { ThemeApply(4); DolDocDamageAll(); }
                    else if (mx >= d_x + 424 && mx <= d_x + 478) { ThemeApply(5); DolDocDamageAll(); }
                } else if (my >= d_y + 112 && my <= d_y + 134) {
                    if (mx >= d_x + 130 && mx <= d_x + 204) DolDocPushAction(DOC_ACT_RUN, -1, 0, "run Compiler.HC");
                    else if (mx >= d_x + 210 && mx <= d_x + 284) DolDocPushAction(DOC_ACT_RUN, -1, 0, "run TestJitP0.HC");
                    else if (mx >= d_x + 290 && mx <= d_x + 344) DolDocPushAction(DOC_ACT_RUN, -1, 0, "bench");
                    else if (mx >= d_x + 410 && mx <= d_x + 478) DolDocPushAction(DOC_ACT_RUN, -1, 0, "mem");
                } else if (my >= d_y + 148 && my <= d_y + 170) {
                    if (mx >= d_x + 130 && mx <= d_x + 184) DolDocPushAction(DOC_ACT_RUN, -1, 0, "filer");
                    else if (mx >= d_x + 370 && mx <= d_x + 434) DolDocPushAction(DOC_ACT_RUN, -1, 0, "inspect 0");
                }
                g_doc_menu_open = 0; DolDocDamageAll(); g_doc_prev_btn = 1; return;
            } else { g_doc_menu_open = 0; DolDocDamageAll(); }
        }
        if (my >= ty) {
            I64 fs_x = sh > 0 ? (g_comp.screen_w - 210) : 0;
            if (mx >= fs_x && mx <= fs_x + 82) { g_doc_desktop_running = 0; g_doc_prev_btn = 1; return; }
            if (mx >= 8 && mx <= 100) { g_doc_menu_open = !g_doc_menu_open; DolDocDamageAll(); g_doc_prev_btn = 1; return; }
            if (mx >= 106 && mx <= 180) { DolDocPushAction(DOC_ACT_RUN, -1, 0, "showcase"); g_doc_prev_btn = 1; return; }
            if (mx >= 186 && mx <= 252) { DolDocPushAction(DOC_ACT_RUN, -1, 0, "shader"); g_doc_prev_btn = 1; return; }
            if (mx >= 258 && mx <= 314) { ThemeApply((g_theme.theme_id + 1) % 6); DolDocDamageAll(); g_doc_prev_btn = 1; return; }
            if (mx >= 320 && mx <= 370) {
                I64 off = (g_doc_win_count * 28) % 160;
                DolDocWinCreate("Shadertoy Torus & Caustics Studio", 140 + off, 80 + off, 360, 240, 3);
                g_doc_prev_btn = 1; return;
            }
            I64 tab_x = 378;
            for (I64 i = 0; i < g_doc_win_count; i++) {
                CDocNode *w = &g_doc_nodes[g_doc_win_nodes[i]];
                if (!(w->flags & DOCF_MIN) && tab_x + 96 < g_comp.screen_w - 210) {
                    if (mx >= tab_x && mx <= tab_x + 92) {
                        if (w->flags & DOCF_MIN) { w->flags &= ~DOCF_MIN; DolDocWinFocus(w->win_id); }
                        else if (g_doc_win_active == w->win_id) w->flags |= DOCF_MIN;
                        else DolDocWinFocus(w->win_id);
                        g_doc_dirty = 1; g_doc_prev_btn = 1; return;
                    }
                    tab_x += 96;
                }
            }
        }
        for (I64 zi = g_doc_win_count - 1; zi >= 0; zi--) {
            CDocNode *win = &g_doc_nodes[g_doc_win_nodes[g_doc_win_zorder[zi]]];
            if (win->flags & DOCF_MIN) continue;
            if (mx >= win->x && mx < win->x + win->w && my >= win->y && my < win->y + win->h) {
                DolDocWinFocus(win->win_id);
                I64 tb_h = g_theme.titlebar_h; if (tb_h < 26) tb_h = 30;
                if (!(win->flags & DOCF_MAX) && mx >= win->x + win->w - 16 && mx <= win->x + win->w + 4 && my >= win->y + win->h - 16 && my <= win->y + win->h + 4) {
                    g_doc_is_resize = 1; g_doc_resize_win = win->win_id; g_doc_resize_ow = win->w; g_doc_resize_oh = win->h;
                    g_doc_resize_mx = mx; g_doc_resize_my = my; g_doc_prev_btn = 1; return;
                }
                if (my < win->y + tb_h) {
                    if (mx >= win->x + win->w - 24 && mx <= win->x + win->w - 8) { DolDocWinClose(win->win_id); g_doc_prev_btn = 1; return; }
                    if (mx >= win->x + win->w - 44 && mx <= win->x + win->w - 28) {
                        if (!(win->flags & DOCF_MAX)) { win->flags |= DOCF_MAX; win->x = 0; win->y = 28; win->w = g_comp.screen_w; win->h = g_comp.screen_h - 68; }
                        else { win->flags &= ~DOCF_MAX; win->x = 16; win->y = 36; }
                        DolDocWinFocus(win->win_id); g_doc_dirty = 1; g_doc_prev_btn = 1; return;
                    }
                    if (mx >= win->x + win->w - 64 && mx <= win->x + win->w - 48) { win->flags |= DOCF_MIN; g_doc_dirty = 1; g_doc_prev_btn = 1; return; }
                    if (!(win->flags & DOCF_MAX)) { g_doc_is_drag = 1; g_doc_drag_win = win->win_id; g_doc_drag_ox = mx - win->x; g_doc_drag_oy = my - win->y; }
                    g_doc_prev_btn = 1; return;
                } else {
                    if (win->state == 0) {
                        I64 sx = g_doc_x; I64 sy = g_doc_y; I64 sw = g_doc_w; I64 shh = g_doc_h;
                        g_doc_x = win->x + 4; g_doc_y = win->y + tb_h + 2; g_doc_w = win->w - 8; g_doc_h = win->h - tb_h - 6;
                        DolDocHandleClick(mx, my);
                        g_doc_x = sx; g_doc_y = sy; g_doc_w = sw; g_doc_h = shh;
                    }
                    g_doc_dirty = 1; g_doc_prev_btn = 1; return;
                }
            }
        }
    }
    if (btn & 1) {
        if (g_doc_is_resize) {
            I64 idx = DolDocWinById(g_doc_resize_win);
            if (idx >= 0) {
                CDocNode *w = &g_doc_nodes[g_doc_win_nodes[idx]];
                I64 nw = g_doc_resize_ow + (mx - g_doc_resize_mx);
                I64 nh = g_doc_resize_oh + (my - g_doc_resize_my);
                if (nw < 260) nw = 260; if (nh < 160) nh = 160;
                if (w->x + nw > g_comp.screen_w) nw = g_comp.screen_w - w->x;
                if (w->y + nh > g_comp.screen_h - 40) nh = g_comp.screen_h - 40 - w->y;
                if (w->w != nw || w->h != nh) { w->w = nw; w->h = nh; g_doc_dirty = 1; }
            }
        } else if (g_doc_is_drag) {
            I64 idx = DolDocWinById(g_doc_drag_win);
            if (idx >= 0) {
                CDocNode *w = &g_doc_nodes[g_doc_win_nodes[idx]];
                I64 nx = mx - g_doc_drag_ox; I64 ny = my - g_doc_drag_oy;
                if (nx < 12 && nx > -12) nx = 0;
                if (ny < 40 && ny > 16) ny = 28;
                if (ny < 28) ny = 28;
                if (ny > g_comp.screen_h - 60) ny = g_comp.screen_h - 60;
                if (w->x != nx || w->y != ny) { w->x = nx; w->y = ny; g_doc_dirty = 1; }
            }
        }
    } else {
        if (g_doc_prev_btn & 1) DolDocHandleMouseUp();
        g_doc_is_drag = 0; g_doc_is_resize = 0; g_doc_prev_btn = 0;
    }
}

U0 DolDocDesktopLoop() {
    uart_puts("[DOLDOC] Entered desktop continuum\n");
    g_doc_desktop_running = 1;
    I64 node_mark = g_doc_node_count;
    I64 text_mark = g_doc_text_used;
    DolDocDesktopInit();
    DolDocDamageAll();
    gfx_dirty_all();
    DolDocDesktopDraw();
    DolDocPresent();
    mouse_draw_cursor_front();
    I64 last_sec = timer_get_uptime_sec();
    I64 last_anim_ms = timer_get_uptime_ms();
    while (g_doc_desktop_running) {
        virtio_input_poll();
        if (g_doc_pump_cb) g_doc_pump_cb();
        mouse_poll();
        DolDocDesktopMouse();
        I64 cur_sec = timer_get_uptime_sec();
        if (cur_sec != last_sec) { last_sec = cur_sec; g_doc_dirty = 1; }
        I64 cur_ms = timer_get_uptime_ms();
        if (cur_ms - last_anim_ms >= 33) {
            last_anim_ms = cur_ms;
            g_doc_anim_tick++;
            g_doc_dirty = 1;
        }
        if (g_doc_dirty || RenderDirtyActive()) {
            gfx_dirty_all();
            DolDocDesktopDraw();
            DolDocPresent();
            mouse_draw_cursor_front();
            g_doc_dirty = 0;
        }
        task_yield();
    }
    g_doc_win_count = 0;
    g_doc_node_count = node_mark;
    g_doc_text_used = text_mark;
    uart_puts("[DOLDOC] Exited desktop continuum\n");
}

U0 DolDocDesktopClose() { g_doc_desktop_running = 0; }
I64 DolDocWindowCount() { return g_doc_win_count; }
I64 DolDocSpawnWindow(U8 *title, I64 x, I64 y, I64 w, I64 h, I64 kind) { return DolDocWinCreate(title, x, y, w, h, kind); }
U0 DolDocFocusWindow(I64 id) { DolDocWinFocus(id); }
I64 DolDocGetFps() { return g_comp.fps; }
I64 DolDocGetFrameUs() { return g_comp.frame_time_us; }

// ============================================================================
// Public API, aliases and introspection
// ============================================================================
U0 doldoc_move(I64 x, I64 y, I64 w, I64 h) { DolDocMove(x, y, w, h); }
U0 doldoc_swap_term() { gfx_swap_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h); }
U0 doldoc_swap_cursor() { gfx_swap_rect(g_doc_cursor_x, g_doc_cursor_y, 8, 16); }
U0 doldoc_putc(U8 c) { DolDocPutc(c); }
U0 doldoc_clear() { DolDocClear(); }
U0 doldoc_redraw() { DolDocRedraw(); }
I64 doldoc_handle_click(I64 mx, I64 my) { return DolDocHandleClick(mx, my); }
I64 doldoc_handle_drag(I64 mx, I64 my) { return DolDocHandleDrag(mx, my); }
I64 doldoc_handle_mouse_up() { return DolDocHandleMouseUp(); }
U0 doldoc_scroll_up(I64 lines) { DolDocScrollUp(lines); }
U0 doldoc_scroll_down(I64 lines) { DolDocScrollDown(lines); }
U0 doldoc_set_bg(U32 bg) { DolDocSetBgColor(bg); }
U32 doldoc_get_bg() { return DolDocGetBgColor(); }

I64 doldoc_get_widget_count() { return g_widget_count; }
I64 doldoc_get_tape_cmd_count() { return g_omnitape_cmd_count; }
I64 doldoc_get_inspected_wid() { return g_doc_inspected_nid; }
U0 doldoc_set_inspected_wid(I64 wid) { g_doc_inspected_nid = wid; }
I64 doldoc_get_inspector_mode() { return g_doc_inspector_mode; }
U0 doldoc_set_inspector_mode(I64 mode) { g_doc_inspector_mode = mode; }

I64 DolDocFindWidget(U8 *name) {
    if (!name || !*name) return -1;
    for (I64 n = 0; n < g_doc_node_count; n++) {
        CDocNode *nd = &g_doc_nodes[n];
        if (nd->kind == DOC_TEXT || nd->kind == DOC_ROOT) continue;
        if (nd->text_len) {
            U8 *lbl = g_doc_text + nd->text_off;
            if (strstr(lbl, name) != 0) return n;
        }
        if (nd->arg_off) {
            U8 *a = g_doc_args + nd->arg_off;
            if (strstr(a, name) != 0) return n;
        }
    }
    return -1;
}
I64 doldoc_find_widget(U8 *name) { return DolDocFindWidget(name); }

U8 *doldoc_get_widget_label(I64 nid) {
    if (nid < 0 || nid >= g_doc_node_count) return "";
    if (g_doc_nodes[nid].text_len == 0) return "";
    return g_doc_text + g_doc_nodes[nid].text_off;
}

// bounded substring search inside a run's text (runs are not NUL-terminated)
I64 DolDocBufContains(I64 off, I64 len, U8 *needle) {
    I64 nl = strlen(needle);
    if (nl == 0 || nl > len) return 0;
    for (I64 i = 0; i + nl <= len; i++) {
        I64 j = 0;
        while (j < nl && g_doc_text[off + i + j] == needle[j]) j++;
        if (j == nl) return 1;
    }
    return 0;
}

I64 DolDocTextContains(U8 *needle) {
    if (!needle) return 0;
    for (I64 n = 0; n < g_doc_node_count; n++) {
        if (g_doc_nodes[n].text_len == 0) continue;
        if (DolDocBufContains(g_doc_nodes[n].text_off, g_doc_nodes[n].text_len, needle)) return 1;
    }
    return 0;
}

U0 doldoc_register_holyc(U8 *ops) { if (ops) symbols_register("g_doldoc_ops", ops, 2); }

// ============================================================================
// DolDoc 3.0 self-test (CDoc/CTree + full tag set)
// ============================================================================
I64 DolDocSelfTest() {
    I64 ok = 1;
    DolDocInitTrig();
    g_doc_quiet = 1;
    // Snapshot the live document so the test is non-destructive.
    I64 s_nodes = g_doc_node_count; I64 s_text = g_doc_text_used; I64 s_args = g_doc_args_used;
    I64 s_cur = g_doc_cur; I64 s_run = g_doc_cur_run; I64 s_col = g_doc_col; I64 s_row = g_doc_row;
    I64 s_wid = g_widget_count; I64 s_tape = g_omnitape_tail; I64 s_tcmd = g_omnitape_cmd_count;
    I64 s_anc = g_doc_anchor_count; I64 s_mac = g_doc_macro_count;
    U64 s_mask = g_doc_dirty_mask; I64 s_dirty = g_doc_dirty;

    // 1. tree: the root entry is a DOC_ROOT
    if (g_doc_root < 0 || g_doc_nodes[g_doc_root].kind != DOC_ROOT) ok = 0;

    // 2. text runs + per-character attribute words
    DolDocPrint("$FG,GREEN$qq$FG,RED$ww$");
    I64 seen_q = 0; I64 seen_w = 0;
    for (I64 n = 0; n < g_doc_node_count; n++) {
        if (g_doc_nodes[n].kind == DOC_TEXT) {
            for (I64 i = 0; i + 1 < g_doc_nodes[n].text_len; i++) {
                I64 ci = g_doc_nodes[n].text_off + i;
                if (g_doc_text[ci] == 'q' && g_doc_text[ci + 1] == 'q' && (U32)(g_doc_attr[ci] & 0xFFFFFFFF) == SEM_COLOR_GREEN) seen_q = 1;
                if (g_doc_text[ci] == 'w' && g_doc_text[ci + 1] == 'w' && (U32)(g_doc_attr[ci] & 0xFFFFFFFF) == SEM_COLOR_RED) seen_w = 1;
            }
        }
    }
    if (!seen_q || !seen_w) ok = 0;

    // 3. widget tag set: BT LK SL CB ID PB DA HR
    I64 before = g_widget_count;
    DolDocPrint("$BT,\"Go\",LM=\"help\"$$LK,\"Lnk\",A=\"ls\"$$SL,\"S\",val=50,min=0,max=100,w=100$$CB,\"Chk\",1$$ID,\"Tree\",level=1$$PB,VAL=30,MAX=100$$DA,\"D\",val=5,min=0,max=9$$HR$");
    if (g_widget_count < before + 8) ok = 0;

    // 4. $AN anchors + $MA macros
    DolDocPrint("$AN,mark1$");
    if (DolDocFindAnchor("mark1") < 0) ok = 0;
    DolDocPrint("$MA,hi,text=\"hello\"$");
    if (!DolDocFindMacro("hi")) ok = 0;

    // 5. reactive cell: bind a node value to a live memory word and patch it
    I64 cell = 7;
    I64 nid = DolDocWidget(DOC_SLIDER, 0, 0, 100, 18, "SL");
    if (nid < 0) ok = 0;
    else {
        g_doc_nodes[nid].target = &cell;
        g_doc_nodes[nid].min = 0; g_doc_nodes[nid].max = 100;
        DolDocCellWrite(nid, 42);
        if (cell != 42) ok = 0;
    }

    // 6. windows are documents ($WIN$ node)
    I64 wn = DolDocNewNode(DOC_WINDOW, -1);
    if (wn < 0 || g_doc_nodes[wn].kind != DOC_WINDOW) ok = 0;

    // 7. dirty-mask shift fix (row 40 must set bit 40)
    g_doc_dirty_mask = 0;
    DolDocMarkRowDirty(40);
    if ((g_doc_dirty_mask & (((U64)1) << 40)) == 0) ok = 0;

    // 8. OmniTape compiled a command record per node
    if (g_omnitape_cmd_count <= 0) ok = 0;

    // Restore the live document.
    g_doc_node_count = s_nodes; g_doc_text_used = s_text; g_doc_args_used = s_args;
    g_doc_cur = s_cur; g_doc_cur_run = s_run; g_doc_col = s_col; g_doc_row = s_row;
    g_widget_count = s_wid; g_omnitape_tail = s_tape; g_omnitape_cmd_count = s_tcmd;
    g_doc_anchor_count = s_anc; g_doc_macro_count = s_mac;
    g_doc_dirty_mask = s_mask; g_doc_dirty = s_dirty;
    g_doc_quiet = 0;

    if (ok) { doldoc_print("$FG,GREEN$DOLDOC: PASS$FG$ (CDoc/CTree, per-char attrs, tag set, cells, windows)\n"); return 1; }
    doldoc_print("$FG,RED$DOLDOC: FAIL$FG$\n");
    return 0;
}

// ============================================================================
// Init
// ============================================================================
U0 DolDocInit() {
    DolDocInitTrig();
    if (!g_omnitape_buf) g_omnitape_buf = kmalloc(OMNITAPE_ARENA_SIZE);
    DolDocClear();
    if (!g_doc_comp_ready) DolDocCompositorInit();

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
    symbols_register("g_doc_inspected_nid", &g_doc_inspected_nid, 2);
    symbols_register("g_shader_speed", &g_shader_speed, 2);
    symbols_register("g_shader_zoom", &g_shader_zoom, 2);
    symbols_register("g_shader_morph", &g_shader_morph, 2);
    symbols_register("g_sprite_rot_speed", &g_sprite_rot_speed, 2);
}

DolDocInit();

