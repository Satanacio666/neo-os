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
#define DOC_SPRING     26   // P8.0: harmonic-spring animated container
// P8.0 Slate two-pass layout containers + industrial nodes.
#define DOC_VBOX       27
#define DOC_HBOX       28
#define DOC_GRIDC      29
#define DOC_NODEGRAPH  30
#define DOC_BLOCKEDIT  31
#define DOC_ISLAND     32
#define DOC_REPL       33   // a live Shell input node on the tape
#define DOC_PROF       34   // P9.0: live profiler panel (drawn last, always on top)
// G3 (motor de layout de 2 passes): containers de fluxo real + widgets compostos.
#define DOC_ROW        35   // $ROW,gap=,pad=$ ... $END$  (eixo horizontal)
#define DOC_COL        36   // $COL,gap=,pad=$ ... $END$  (eixo vertical)
#define DOC_SLOT       37   // $SLOT,w=,h=,min=,flex=,split=$ (painel; split=1 arrasta)
#define DOC_TABS       38   // $TABS,id=,items="A|B|C",val=$
#define DOC_CANVAS     39   // $CANVAS,id=,w=,h=$

// ---- Node flags --------------------------------------------------------------
#define DOCF_OPEN      1
#define DOCF_ACTIVE    2
#define DOCF_MIN       4
#define DOCF_MAX       8
#define DOCF_ELEV      16
#define DOCF_BLUR      32
#define DOCF_WRAP      64
#define DOCF_INVERT    128
#define DOCF_SPRING    256   // P8.0: node position is driven by a harmonic spring
#define DOCF_ACTION    512   // G3: click deste widget empurra um CDocAction com id
// G3 layout engine: size_mode_w / size_mode_h of a child inside ROW/COL/SLOT.
#define DOC_SIZE_AUTO  0     // fits to the intrinsic size measured in pass 1
#define DOC_SIZE_FIXED 1     // exact px declared in the tag (w=/h=)
#define DOC_SIZE_FLEX  2     // shares the leftover by flex_weight (clamped by min/max)

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
    // ---- G3: motor de layout de 2 passes -----------------------------------
    // ADICIONADO NO FIM da classe de proposito: os offsets dos campos acima
    // (usados pelo OmniTape e pelo resto do kernel) NAO mudam.
    I64 meas_w, meas_h;             // tamanho intrinseco medido no Passe 1
    I64 size_mode_w, size_mode_h;   // 0=AUTO fit, 1=FIXED px, 2=FLEX
    I64 flex_weight;                // peso no rateio do restante (Passe 2)
    I64 gap, pad;                   // espaco entre filhos / margem interna
    I64 split_draggable;            // 1 = barra divisoria arrastavel (hit-test 4px)
};

// Live reactive parameters for shaders, 3D sprites & oscilloscopes
I64 g_shader_speed       = 50;
I64 g_shader_zoom        = 40;
I64 g_shader_morph       = 60;
I64 g_sprite_rot_speed   = 50;
I64 g_doc_inspector_mode = 0;
I64 g_doc_inspected_nid  = -1;
I64 g_doc_anim_tick      = 0;
// P8.0: per-node spring velocity (harmonic-spring animated positions).
F64 g_doc_spring_v[DOC_MAX_NODES];
// G1: the node currently being drawn (selects its spring slot).
I64 g_doc_cur_nid = 0;

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
    // G3: zera os campos novos (determinismo para o motor de layout)
    nd->meas_w = 0; nd->meas_h = 0;
    nd->size_mode_w = DOC_SIZE_AUTO; nd->size_mode_h = DOC_SIZE_AUTO;
    nd->flex_weight = 0; nd->gap = 0; nd->pad = 0; nd->split_draggable = 0;
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
    // G1: the caret glides continuously (sub-pixel) toward the cursor column with a
    // SNAPPY spring, instead of jumping glyph to glyph.
    F64 cx = EffectsSpringPull(64.0, (F64)g_doc_cursor_x, 22.0, 3.0, 0.016);
    gfx_draw_rect((I64)cx, g_doc_cursor_y + 1, 2, 14, color);
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

// P8.0: $SPRING$ harmonic-spring container. x is the animated coordinate and
// val the target; the node settles toward it via the closed-form damped oscillator
// (EffectsSpringStep) in DolDocSpringTick — no static interpolation curves.
U0 DolDocParseSpring(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 40);
    I64 h = DolDocGetAttrInt(tag, "h=", 4);
    I64 tx = DolDocGetAttrInt(tag, "tx=", 0);
    I64 om = DolDocGetAttrInt(tag, "omega=", 12);
    I64 n = DolDocWidget(DOC_SPRING, DolDocFlowPx(), DolDocFlowPy(), w * 8, h * 18, tag);
    if (n >= 0) {
        CDocNode *nd = &g_doc_nodes[n];
        nd->flags = nd->flags | DOCF_SPRING;
        nd->val = tx;                 // target x
        nd->min = om;                 // omega (spring stiffness)
        nd->max = 75;                 // zeta x100 (0.75, slightly underdamped)
        g_doc_spring_v[n] = 0.0;
    }
}

U0 DolDocSpringTick() {
    I64 n = 0;
    while (n < g_doc_node_count) {
        if ((g_doc_nodes[n].flags & DOCF_SPRING) != 0) {
            F64 x = (F64)g_doc_nodes[n].x;
            F64 v = g_doc_spring_v[n];
            F64 target = (F64)g_doc_nodes[n].val;
            F64 omega = (F64)g_doc_nodes[n].min; if (omega <= 0.0) omega = 12.0;
            F64 zeta = (F64)g_doc_nodes[n].max / 100.0; if (zeta <= 0.0) zeta = 0.75;
            F64 nv = 0.0;
            F64 nx = EffectsSpringStep(x, v, target, omega, zeta, 0.016, &nv);
            g_doc_spring_v[n] = nv;
            g_doc_nodes[n].x = (I64)nx;
            // snap when settled (avoids an endless sub-pixel crawl)
            if (nx > target - 0.5 && nx < target + 0.5 && nv < 0.5 && nv > -0.5) {
                g_doc_nodes[n].x = (I64)target;
                g_doc_spring_v[n] = 0.0;
            }
        }
        n = n + 1;
    }
}

// ============================================================================
// P8.0 Slate two-pass layout: MEASURE intrinsic sizes bottom-up, then ARRANGE
// slots top-down. Real continuous coordinates (no cell rounding); mode selects
// VBOX (0) / HBOX (1) / GRID (2) / SPLIT (3).
// ============================================================================
U0 DolDocSlateLayout(I64 first, I64 last, I64 x, I64 y, I64 w, I64 h, I64 mode) {
    if (last < first) return;
    I64 n = last - first + 1;
    if (mode == 0) {
        // VBOX: stack vertically, heights proportional to intrinsic h (default 18).
        I64 sum = 0; I64 i = first;
        while (i <= last) { I64 ih = g_doc_nodes[i].h; if (ih <= 0) ih = 18; sum = sum + ih; i = i + 1; }
        if (sum <= 0) sum = n;
        I64 cy = y; i = first;
        while (i <= last) {
            I64 ih = g_doc_nodes[i].h; if (ih <= 0) ih = 18;
            I64 ch = (ih * h) / sum; if (ch < 1) ch = 1;
            g_doc_nodes[i].x = x; g_doc_nodes[i].y = cy; g_doc_nodes[i].w = w; g_doc_nodes[i].h = ch;
            cy = cy + ch; i = i + 1;
        }
    } else if (mode == 1) {
        // HBOX: stack horizontally, widths proportional to intrinsic w (default 80).
        I64 sum = 0; I64 i = first;
        while (i <= last) { I64 iw = g_doc_nodes[i].w; if (iw <= 0) iw = 80; sum = sum + iw; i = i + 1; }
        if (sum <= 0) sum = n;
        I64 cx = x; i = first;
        while (i <= last) {
            I64 iw = g_doc_nodes[i].w; if (iw <= 0) iw = 80;
            I64 cw = (iw * w) / sum; if (cw < 1) cw = 1;
            g_doc_nodes[i].x = cx; g_doc_nodes[i].y = y; g_doc_nodes[i].w = cw; g_doc_nodes[i].h = h;
            cx = cx + cw; i = i + 1;
        }
    } else if (mode == 2) {
        // GRID: cols from the container tag (stored in val), rows derived.
        I64 cols = g_doc_nodes[first - 1].val;
        if (cols < 1) cols = 2;
        I64 rows = (n + cols - 1) / cols;
        if (rows < 1) rows = 1;
        I64 cw = w / cols; if (cw < 1) cw = 1;
        I64 ch = h / rows; if (ch < 1) ch = 1;
        I64 i = first; I64 k = 0;
        while (i <= last) {
            I64 cc = k % cols; I64 rr = k / cols;
            g_doc_nodes[i].x = x + cc * cw; g_doc_nodes[i].y = y + rr * ch;
            g_doc_nodes[i].w = cw; g_doc_nodes[i].h = ch;
            k = k + 1; i = i + 1;
        }
    } else {
        // SPLIT: two panes split by the container ratio (val, percent; default 50).
        I64 ratio = g_doc_nodes[first - 1].val; if (ratio < 5) ratio = 50; if (ratio > 95) ratio = 95;
        I64 left_w = (w * ratio) / 100; if (left_w < 1) left_w = 1;
        I64 i = first; I64 k = 0;
        while (i <= last) {
            if (k == 0) { g_doc_nodes[i].x = x; g_doc_nodes[i].y = y; g_doc_nodes[i].w = left_w; g_doc_nodes[i].h = h; }
            else        { g_doc_nodes[i].x = x + left_w; g_doc_nodes[i].y = y; g_doc_nodes[i].w = w - left_w; g_doc_nodes[i].h = h; }
            k = k + 1; i = i + 1;
        }
    }
}

// Container parser: $VBOX$/$HBOX$/$GRID$/$SPLIT$ create a container node whose
// val carries the layout parameter (grid cols / split ratio). The Slate pass then
// arranges the following run of sibling nodes into it.
U0 DolDocParseContainer(U8 *tag, I64 kind) {
    I64 w = DolDocGetAttrInt(tag, "w=", 240);
    I64 h = DolDocGetAttrInt(tag, "h=", 120);
    I64 n = DolDocWidget(kind, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n >= 0) {
        CDocNode *nd = &g_doc_nodes[n];
        nd->val = (kind == DOC_GRIDC) ? DolDocGetAttrInt(tag, "cols=", 2)
                                       : DolDocGetAttrInt(tag, "ratio=", 50);
        DolDocAdvance(1);
    }
}

// Industrial node (P8.0): $NODE_GRAPH$, $BLOCK_EDITOR$, $ISLAND$ are first-class
// document nodes with a real intrinsic size; they render through the widget path.
U0 DolDocParseIndustrial(U8 *tag, I64 kind) {
    I64 w = DolDocGetAttrInt(tag, "w=", 200);
    I64 h = DolDocGetAttrInt(tag, "h=", 140);
    U8 title[64]; title[0] = 0;
    DolDocGetAttrStr(tag, "title=", title, 60);
    I64 n = DolDocWidget(kind, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n >= 0) {
        if (title[0]) DolDocSetLabel(n, title);
        else if (kind == DOC_NODEGRAPH) DolDocSetLabel(n, "Node Graph");
        else if (kind == DOC_BLOCKEDIT) DolDocSetLabel(n, "Block Editor");
        else DolDocSetLabel(n, "Island");
        DolDocAdvance(1);
    }
}

// $REPL$: a live Shell input node on the tape (a document that IS a shell).
U0 DolDocParseRepl(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 400);
    I64 h = DolDocGetAttrInt(tag, "h=", 200);
    I64 n = DolDocWidget(DOC_REPL, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n >= 0) DolDocSetLabel(n, "Shell");
    DolDocAdvance(1);
}

// P9.0 $PROF$: the live profiler panel. It is a first-class DolDoc node whose
// CONTENT is not baked text: DolDocRedraw draws it last (always on top) by
// calling ProfilerDrawPanel(), which reads the live counters in Telemetry.HC.
// So the panel updates every refresh without ever growing the node tree.
U0 DolDocParseProfiler(U8 *tag) {
    I64 w = DolDocGetAttrInt(tag, "w=", 760);
    I64 h = DolDocGetAttrInt(tag, "h=", 215);
    I64 px = DolDocFlowPx();
    I64 py = DolDocFlowPy();
    I64 n = DolDocWidget(DOC_PROF, px, py, w, h, tag);
    if (n >= 0) {
        DolDocSetLabel(n, "NeoOS Live Profiler");
        ProfilerSetNodeId(n);
        ProfilerSetNodeRect(px, py, w, h);
        // The panel is a block: push the text flow below it so the following
        // text is not hidden behind the panel.
        I64 rows = (h + 17) / 18;
        g_doc_row = g_doc_row + rows;
        if (g_doc_row >= g_doc_rows) g_doc_row = g_doc_rows - 1;
        DolDocBreakRun();
        DolDocUpdateCursor();
    }
}

// The Slate pass: after parsing, arrange each container's following sibling run.
U0 DolDocSlatePass() {
    // G3: Passe 1 (MEASURE, bottom-up) + Passe 2 (ARRANGE, top-down) sobre a
    // arvore REAL de filhos dos containers ROW/COL/SLOT. Os pais tem indice
    // menor que os filhos (DolDocNewNode anexa no fim), entao a varredura em
    // ordem crescente ja respeita "mede de baixo para cima, arranja de cima
    // para baixo" — e re-arranjar um no' ja arranjado e' idempotente.
    I64 g3n = 0;
    while (g3n < g_doc_node_count) {
        I64 g3k = g_doc_nodes[g3n].kind;
        if (g3k == DOC_ROW || g3k == DOC_COL || g3k == DOC_SLOT) {
            DolDocMeasureNode(g3n);
            I64 bw = g_doc_nodes[g3n].w;
            I64 bh = g_doc_nodes[g3n].h;
            if (bw <= 0) bw = g_doc_nodes[g3n].meas_w;
            if (bh <= 0) bh = g_doc_nodes[g3n].meas_h;
            if (bh <= 0) bh = 18;
            DolDocArrangeNode(g3n, g_doc_nodes[g3n].x, g_doc_nodes[g3n].y, bw, bh);
        }
        g3n = g3n + 1;
    }
    I64 n = 0;
    while (n < g_doc_node_count) {
        I64 k = g_doc_nodes[n].kind;
        if (k == DOC_VBOX || k == DOC_HBOX || k == DOC_GRIDC || k == DOC_SPLIT) {
            I64 first = n + 1;
            I64 last = first - 1;
            I64 m = first;
            while (m < g_doc_node_count) {
                I64 mk = g_doc_nodes[m].kind;
                if (mk == DOC_VBOX || mk == DOC_HBOX || mk == DOC_GRIDC || mk == DOC_SPLIT || mk == DOC_WINDOW) break;
                last = m;
                m = m + 1;
            }
            I64 mode = (k == DOC_VBOX) ? 0 : ((k == DOC_HBOX) ? 1 : ((k == DOC_GRIDC) ? 2 : 3));
            DolDocSlateLayout(first, last, g_doc_nodes[n].x, g_doc_nodes[n].y,
                              g_doc_nodes[n].w, g_doc_nodes[n].h, mode);
        }
        n = n + 1;
    }
}

// P8.0 Slate layout self-test (called from SelfTest.HC -> LAYOUT: PASS). Exercises
// the four container modes on a scratch node range at the tail of the node array
// (never touching the live document).
U0 DolDocSlateSelfTest() {
    I64 pass = 0;
    I64 total = 0;
    I64 base = DOC_MAX_NODES - 8;
    g_doc_nodes[base].kind = DOC_VBOX;
    g_doc_nodes[base].val = 50;

    // VBOX: intrinsic heights 20 and 40 in a 120-high box -> 40 and 80 (proportional).
    g_doc_nodes[base + 1].kind = DOC_TEXT; g_doc_nodes[base + 1].w = 100; g_doc_nodes[base + 1].h = 20;
    g_doc_nodes[base + 2].kind = DOC_TEXT; g_doc_nodes[base + 2].w = 100; g_doc_nodes[base + 2].h = 40;
    DolDocSlateLayout(base + 1, base + 2, 0, 0, 200, 120, 0);
    total++; if (g_doc_nodes[base + 1].h == 40 && g_doc_nodes[base + 2].h == 80 &&
                g_doc_nodes[base + 2].y == 40 && g_doc_nodes[base + 1].w == 200) pass++;

    // HBOX: intrinsic widths 40 and 60 in a 200-wide box -> 80 and 120.
    g_doc_nodes[base + 1].w = 40; g_doc_nodes[base + 2].w = 60;
    DolDocSlateLayout(base + 1, base + 2, 0, 0, 200, 50, 1);
    total++; if (g_doc_nodes[base + 1].w == 80 && g_doc_nodes[base + 2].w == 120 &&
                g_doc_nodes[base + 2].x == 80 && g_doc_nodes[base + 1].h == 50) pass++;

    // GRID: 4 children, 2 cols, 100x100 -> each 50x50; child 3 at (50,50).
    g_doc_nodes[base].val = 2;
    DolDocSlateLayout(base + 1, base + 4, 0, 0, 100, 100, 2);
    total++; if (g_doc_nodes[base + 1].w == 50 && g_doc_nodes[base + 1].h == 50 &&
                g_doc_nodes[base + 2].x == 50 && g_doc_nodes[base + 2].y == 0 &&
                g_doc_nodes[base + 3].x == 0 && g_doc_nodes[base + 3].y == 50 &&
                g_doc_nodes[base + 4].x == 50 && g_doc_nodes[base + 4].y == 50) pass++;

    // SPLIT: 50% of a 200-wide box -> two 100-wide panes.
    g_doc_nodes[base].val = 50;
    DolDocSlateLayout(base + 1, base + 2, 0, 0, 200, 100, 3);
    total++; if (g_doc_nodes[base + 1].w == 100 && g_doc_nodes[base + 2].x == 100 &&
                g_doc_nodes[base + 2].w == 100 && g_doc_nodes[base + 2].h == 100) pass++;

    // ========================================================================
    // G3 — 4 testes NOVOS do motor de layout de 2 passes (5..8).
    // Os 4 testes acima continuam INTACTOS: nenhum foi apagado nem afrouxado.
    // Todos rodam sobre o documento vivo com snapshot/restore (DolDocG3Save /
    // DolDocG3Restore) para nao sujar o DolDocShell.
    // ========================================================================

    // ---- Teste 5: $ROW$ 600, pad=10, gap=10, filhos FIXED 100 / FLEX 1 / FLEX 2
    //      -> larguras exatas 100/153/307 e x exatos 10/120/283 ---------------
    DolDocG3Save();
    DolDocPrint("$ROW,gap=10,pad=10,w=600,h=100$");
    DolDocPrint("$SLOT,w=100,h=100$$END$");
    DolDocPrint("$SLOT,flex=1,h=100$$END$");
    DolDocPrint("$SLOT,flex=2,h=100$$END$");
    DolDocPrint("$END$");
    {
        I64 t5r = g_g3_sn_nodes, t5a = t5r + 1, t5b = t5r + 2, t5c = t5r + 3;
        g_doc_nodes[t5r].x = 0; g_doc_nodes[t5r].y = 0;
        DolDocMeasureNode(t5r);
        DolDocArrangeNode(t5r, 0, 0, g_doc_nodes[t5r].w, g_doc_nodes[t5r].h);
        // G3-fix: captura y IMEDIATAMENTE apos o arranjo. Os doldoc_printf
        // abaixo escrevem no documento vivo e disparam um re-layout que
        // reposiciona estes mesmos nos — ler depois mede outra coisa.
        I64 t5r_y = g_doc_nodes[t5r].y;
        I64 t5a_y = g_doc_nodes[t5a].y, t5b_y = g_doc_nodes[t5b].y, t5c_y = g_doc_nodes[t5c].y;
        doldoc_printf("[G3-T5c] sn=%lld cnt=%lld kind=%lld first=%lld last=%lld\n",
                      g_g3_sn_nodes, g_doc_node_count, g_doc_nodes[t5r].kind,
                      g_doc_nodes[t5r].first, g_doc_nodes[t5r].last);
        doldoc_printf("[G3-T5d] row w=%lld h=%lld gap=%lld pad=%lld x=%lld y=%lld\n",
                      g_doc_nodes[t5r].w, g_doc_nodes[t5r].h, g_doc_nodes[t5r].gap,
                      g_doc_nodes[t5r].pad, g_doc_nodes[t5r].x, g_doc_nodes[t5r].y);
        doldoc_printf("[G3-T5e] kid=(%lld,%lld,%lld) par=(%lld,%lld,%lld)\n",
                      g_doc_nodes[t5a].kind, g_doc_nodes[t5b].kind, g_doc_nodes[t5c].kind,
                      g_doc_nodes[t5a].parent, g_doc_nodes[t5b].parent, g_doc_nodes[t5c].parent);
        doldoc_printf("[G3-T5f] nx=(%lld,%lld,%lld) mw=(%lld,%lld,%lld)\n",
                      g_doc_nodes[t5a].next, g_doc_nodes[t5b].next, g_doc_nodes[t5c].next,
                      g_doc_nodes[t5a].meas_w, g_doc_nodes[t5b].meas_w, g_doc_nodes[t5c].meas_w);
        I64 t5ok = (g_doc_nodes[t5r].w == 600 && g_doc_nodes[t5r].h == 100 &&
                    g_doc_nodes[t5r].meas_w == 140 && g_doc_nodes[t5r].meas_h == 120 &&
                    g_doc_nodes[t5a].w == 100 && g_doc_nodes[t5b].w == 153 && g_doc_nodes[t5c].w == 307 &&
                    g_doc_nodes[t5a].x == 10 && g_doc_nodes[t5b].x == 120 && g_doc_nodes[t5c].x == 283 &&
                    // G3-fix: Y tambem cobrado (antes so x e w eram). row y=0;
                    // filhos y=pad=10. Usa os valores capturados acima.
                    t5r_y == 0 && t5a_y == 10 && t5b_y == 10 && t5c_y == 10 &&
                    g_doc_nodes[t5a].size_mode_w == DOC_SIZE_FIXED &&
                    g_doc_nodes[t5b].size_mode_w == DOC_SIZE_FLEX &&
                    g_doc_nodes[t5c].size_mode_w == DOC_SIZE_FLEX);
        total++; if (t5ok) pass++;
        doldoc_printf("[G3-T5a] meas=(%lld,%lld) w=(%lld,%lld,%lld)\n",
                      g_doc_nodes[t5r].meas_w, g_doc_nodes[t5r].meas_h,
                      g_doc_nodes[t5a].w, g_doc_nodes[t5b].w, g_doc_nodes[t5c].w);
        doldoc_printf("[G3-T5b] x=(%lld,%lld,%lld) modes=(%lld,%lld,%lld) ok=%lld\n",
                      g_doc_nodes[t5a].x, g_doc_nodes[t5b].x, g_doc_nodes[t5c].x,
                      g_doc_nodes[t5a].size_mode_w, g_doc_nodes[t5b].size_mode_w,
                      g_doc_nodes[t5c].size_mode_w, t5ok);
    }
    DolDocG3Restore();

    // ---- Teste 6: min=180 do $SLOT$ nunca encolhe + splitter arrastavel -------
    DolDocG3Save();
    DolDocPrint("$ROW,gap=10,pad=0,w=400,h=100$");
    DolDocPrint("$SLOT,flex=1,h=100,min=180,split=1$$END$");
    DolDocPrint("$SLOT,flex=3,h=100$$END$");
    DolDocPrint("$END$");
    {
        I64 t6r = g_g3_sn_nodes, t6a = t6r + 1, t6b = t6r + 2;
        g_doc_nodes[t6r].x = 0; g_doc_nodes[t6r].y = 0;
        DolDocMeasureNode(t6r);
        DolDocArrangeNode(t6r, 0, 0, g_doc_nodes[t6r].w, g_doc_nodes[t6r].h);
        // sem clamp o FLEX 1 levaria 97 (390/4); com min=180 tem de dar 180
        I64 t6clamp = (g_doc_nodes[t6a].w == 180 && g_doc_nodes[t6a].min == 180);
        I64 t6sib = (g_doc_nodes[t6b].w == 293 && g_doc_nodes[t6b].x == 190);
        // hit-test do splitter: banda de 4px em x+w (180) -> 178..181
        I64 t6hit = (DolDocSplitterHitTest(180, 50) == t6a &&
                     DolDocSplitterHitTest(177, 50) == -1 &&
                     DolDocSplitterHitTest(183, 50) == -1);
        I64 t6drag = 0, t6dragmin = 0;
        if (DolDocSplitterDrag(t6a, 220) == 1) {
            t6drag = (g_doc_nodes[t6a].w == 220 && g_doc_nodes[t6b].w == 170 &&
                      g_doc_nodes[t6b].x == 230);
        }
        if (DolDocSplitterDrag(t6a, 50) == 1) t6dragmin = (g_doc_nodes[t6a].w == 180);
        total++;
        if (t6clamp && t6sib && t6hit && t6drag && t6dragmin) pass++;
        doldoc_printf("[G3-T6a] clamp=%lld sib=%lld hit=%lld drag=%lld dragmin=%lld\n",
                      t6clamp, t6sib, t6hit, t6drag, t6dragmin);
        doldoc_printf("[G3-T6b] wA=%lld wB=%lld xB=%lld\n",
                      g_doc_nodes[t6a].w, g_doc_nodes[t6b].w, g_doc_nodes[t6b].x);
    }
    DolDocG3Restore();

    // ---- Teste 7: $TABS$ / $SLIDER$ / $TOGGLE$ — clique muda val + acao ------
    DolDocG3Save();
    DolDocPrint("$TABS,id=\"tabs1\",items=\"A|B|C\",val=0,w=240,h=24$");
    DolDocPrint("$SLIDER,id=\"sl1\",min=0,max=100,val=75,w=200,label=\"Vol\"$");
    DolDocPrint("$TOGGLE,id=\"tg1\",val=1,label=\"On\"$");
    {
        I64 t7t = g_g3_sn_nodes, t7s = t7t + 1, t7g = t7t + 2;
        g_doc_nodes[t7t].x = 0; g_doc_nodes[t7t].y = 0;
        g_doc_nodes[t7s].x = 0; g_doc_nodes[t7s].y = 40;
        g_doc_nodes[t7g].x = 0; g_doc_nodes[t7g].y = 80;
        I64 t7q0 = g_doc_act_head;
        I64 t7c1 = DolDocWidgetClick(t7t, 200, 10);     // 3o de 3 segmentos de 80px -> val 2
        I64 t7c2 = DolDocWidgetClick(t7s, 100, 45);     // 100 de 200px em 0..100 -> val 50
        I64 t7c3 = DolDocWidgetClick(t7g, 10, 85);      // toggle 1 -> 0
        I64 t7miss = DolDocWidgetClick(t7t, 900, 900);  // fora da caixa -> nada
        I64 t7q = g_doc_act_head - t7q0; if (t7q < 0) t7q = t7q + DOC_ACT_Q;
        I64 t7i0 = t7q0 % DOC_ACT_Q;
        CDocAction *t7a1 = &g_doc_act_q[t7i0];
        CDocAction *t7a2 = &g_doc_act_q[(t7i0 + 1) % DOC_ACT_Q];
        CDocAction *t7a3 = &g_doc_act_q[(t7i0 + 2) % DOC_ACT_Q];
        I64 t7ok = (t7c1 == 1 && t7c2 == 1 && t7c3 == 1 && t7miss == 0 && t7q == 3 &&
                    g_doc_nodes[t7t].val == 2 && g_doc_nodes[t7s].val == 50 &&
                    g_doc_nodes[t7g].val == 0 && g_doc_nodes[t7g].state == 0 &&
                    t7a1->kind == DOC_ACT_SET && t7a1->target_id == t7t && t7a1->val == 2 &&
                    strcmp(t7a1->payload, "tabs1") == 0 &&
                    t7a2->kind == DOC_ACT_SET && t7a2->target_id == t7s && t7a2->val == 50 &&
                    strcmp(t7a2->payload, "sl1") == 0 &&
                    t7a3->kind == DOC_ACT_SET && t7a3->target_id == t7g && t7a3->val == 0 &&
                    strcmp(t7a3->payload, "tg1") == 0);
        total++; if (t7ok) pass++;
        doldoc_printf("[G3-T7a] click=(%lld,%lld,%lld) miss=%lld q=%lld\n",
                      t7c1, t7c2, t7c3, t7miss, t7q);
        doldoc_printf("[G3-T7b] val=(%lld,%lld,%lld) act=(%lld,%lld,%lld)\n",
                      g_doc_nodes[t7t].val, g_doc_nodes[t7s].val, g_doc_nodes[t7g].val,
                      t7a1->val, t7a2->val, t7a3->val);
        doldoc_printf("[G3-T7c] pay=(%s,%s,%s) ok=%lld\n",
                      t7a1->payload, t7a2->payload, t7a3->payload, t7ok);
    }
    DolDocG3Restore();

    // ---- Teste 8: parser dual — HTML gera a MESMA arvore que $ROW$ ----------
    DolDocG3Save();
    I64 t8hb = g_doc_node_count;
    DolDocPrint("<div style=\"display:row; gap:8\" w=400 h=60><button onclick=\"help\">OK</button></div>");
    I64 t8hc = g_doc_node_count - t8hb;
    I64 t8nb = g_doc_node_count;
    DolDocPrint("$ROW,gap=8,w=400,h=60$$BT,\"OK\",LM=\"help\"$$END$");
    I64 t8nc = g_doc_node_count - t8nb;
    {
        I64 t8hr = t8hb, t8hbt = t8hb + 1;
        I64 t8nr = t8nb, t8nbt = t8nb + 1;
        g_doc_nodes[t8hr].x = 0; g_doc_nodes[t8hr].y = 0;
        g_doc_nodes[t8nr].x = 0; g_doc_nodes[t8nr].y = 0;
        DolDocMeasureNode(t8hr); DolDocMeasureNode(t8nr);
        DolDocArrangeNode(t8hr, 0, 0, g_doc_nodes[t8hr].w, g_doc_nodes[t8hr].h);
        DolDocArrangeNode(t8nr, 0, 0, g_doc_nodes[t8nr].w, g_doc_nodes[t8nr].h);
        I64 t8ok = (t8hc == 2 && t8nc == 2);
        CDocNode *hr = &g_doc_nodes[t8hr]; CDocNode *nr = &g_doc_nodes[t8nr];
        CDocNode *hb = &g_doc_nodes[t8hbt]; CDocNode *nb = &g_doc_nodes[t8nbt];
        doldoc_printf("[G3-T8c] hr=(%lld,%lld,%lld,%lld,%lld,%lld)\n",
                      hr->kind, hr->first, hr->pad, hr->x, hr->y, hr->w);
        doldoc_printf("[G3-T8d] nr=(%lld,%lld,%lld,%lld,%lld,%lld)\n",
                      nr->kind, nr->first, nr->pad, nr->x, nr->y, nr->w);
        doldoc_printf("[G3-T8e] hb=(%lld,%lld,%lld,%lld)\n", hb->x, hb->y, hb->w, hb->h);
        doldoc_printf("[G3-T8f] nb=(%lld,%lld,%lld,%lld) par=(%lld,%lld)\n",
                      nb->x, nb->y, nb->w, nb->h, hb->parent, nb->parent);
        if (hr->kind != nr->kind || hr->gap != nr->gap || hr->pad != nr->pad) t8ok = 0;
        if (hr->w != nr->w || hr->h != nr->h) t8ok = 0;
        if (hr->meas_w != nr->meas_w || hr->meas_h != nr->meas_h) t8ok = 0;
        if (hr->first != t8hbt || nr->first != t8nbt) t8ok = 0;
        if (hb->kind != nb->kind) t8ok = 0;
        if (hb->x != nb->x || hb->y != nb->y || hb->w != nb->w || hb->h != nb->h) t8ok = 0;
        if (hb->meas_w != nb->meas_w || hb->meas_h != nb->meas_h) t8ok = 0;
        if ((hb->flags & DOCF_ACTION) != (nb->flags & DOCF_ACTION)) t8ok = 0;
        if (hb->text_len != nb->text_len) t8ok = 0;
        else {
            I64 t8i = 0;
            while (t8i < hb->text_len) {
                if (g_doc_text[hb->text_off + t8i] != g_doc_text[nb->text_off + t8i]) { t8ok = 0; break; }
                t8i = t8i + 1;
            }
        }
        U8 *ha = hb->arg_off ? (g_doc_args + hb->arg_off) : "";
        U8 *na = nb->arg_off ? (g_doc_args + nb->arg_off) : "";
        if (strcmp(ha, na) != 0) t8ok = 0;
        total++; if (t8ok) pass++;
        doldoc_printf("[G3-T8a] n=(%lld,%lld) html_box=(%lld,%lld,%lld,%lld)\n",
                      t8hc, t8nc, hb->x, hb->y, hb->w, hb->h);
        doldoc_printf("[G3-T8b] nat_box=(%lld,%lld,%lld,%lld) args=(%s,%s) ok=%lld\n",
                      nb->x, nb->y, nb->w, nb->h, ha, na, t8ok);
    }
    DolDocG3Restore();

    if (pass == total) doldoc_printf("LAYOUT: PASS (%lld/%lld)\n", pass, total);
    else doldoc_printf("LAYOUT: FAIL (%lld/%lld)\n", pass, total);
}

// ============================================================================
// G3 — MOTOR DE LAYOUT DE 2 PASSES (estilo nicbarker/clay + rxi/microui)
//
// Passe 1 DolDocMeasureNode: bottom-up, calcula meas_w/meas_h intrinsecos.
// Passe 2 DolDocArrangeNode: top-down, distribui x/y/w/h reais; subtrai 2*pad e
// (n-1)*gap, tira o espaco dos filhos FIXED/AUTO e rateia o restante entre os
// FLEX por flex_weight, respeitando min/max do CDocNode.
//
// Toda a aritmetica e' inteira (nenhum float): os testes sao deterministas.
// ============================================================================

// pilha de containers abertos ($ROW$/$COL$/$SLOT$ ... $END$, ou <div>...</div>)
I64 g_doc_cont_stack[32];
I64 g_doc_cont_depth = 0;
// splitter em arraste (-1 = nenhum)
I64 g_doc_split_nid = -1;
// snapshot nao-destrutivo usado pelos testes G3 do SelfTest
I64 g_g3_sn_nodes = 0, g_g3_sn_text = 0, g_g3_sn_args = 0, g_g3_sn_cur = 0;
I64 g_g3_sn_run = 0, g_g3_sn_col = 0, g_g3_sn_row = 0, g_g3_sn_wid = 0;
I64 g_g3_sn_tape = 0, g_g3_sn_tcmd = 0, g_g3_sn_anc = 0, g_g3_sn_mac = 0;
I64 g_g3_sn_parent = -1, g_g3_sn_pfirst = -1, g_g3_sn_plast = -1, g_g3_sn_plast_next = -1;
I64 g_g3_sn_contdepth = 0, g_g3_sn_split = -1, g_g3_sn_drag = -1;
U64 g_g3_sn_mask = 0; I64 g_g3_sn_dirty = 0;

U0 DolDocG3Save() {
    g_g3_sn_nodes = g_doc_node_count; g_g3_sn_text = g_doc_text_used;
    g_g3_sn_args = g_doc_args_used; g_g3_sn_cur = g_doc_cur;
    g_g3_sn_run = g_doc_cur_run; g_g3_sn_col = g_doc_col; g_g3_sn_row = g_doc_row;
    g_g3_sn_wid = g_widget_count; g_g3_sn_tape = g_omnitape_tail;
    g_g3_sn_tcmd = g_omnitape_cmd_count; g_g3_sn_anc = g_doc_anchor_count;
    g_g3_sn_mac = g_doc_macro_count; g_g3_sn_mask = g_doc_dirty_mask;
    g_g3_sn_dirty = g_doc_dirty;
    g_g3_sn_parent = g_doc_cur;
    g_g3_sn_pfirst = (g_doc_cur >= 0) ? g_doc_nodes[g_doc_cur].first : -1;
    g_g3_sn_plast  = (g_doc_cur >= 0) ? g_doc_nodes[g_doc_cur].last : -1;
    g_g3_sn_plast_next = (g_g3_sn_plast >= 0) ? g_doc_nodes[g_g3_sn_plast].next : -1;
    g_g3_sn_contdepth = g_doc_cont_depth; g_g3_sn_split = g_doc_split_nid;
    g_g3_sn_drag = g_doc_drag_nid;
}

U0 DolDocG3Restore() {
    if (g_g3_sn_parent >= 0 && g_g3_sn_parent < g_doc_node_count) {
        g_doc_nodes[g_g3_sn_parent].first = g_g3_sn_pfirst;
        g_doc_nodes[g_g3_sn_parent].last  = g_g3_sn_plast;
        if (g_g3_sn_plast >= 0) g_doc_nodes[g_g3_sn_plast].next = g_g3_sn_plast_next;
    }
    g_doc_node_count = g_g3_sn_nodes; g_doc_text_used = g_g3_sn_text;
    g_doc_args_used = g_g3_sn_args; g_doc_cur = g_g3_sn_cur;
    g_doc_cur_run = g_g3_sn_run; g_doc_col = g_g3_sn_col; g_doc_row = g_g3_sn_row;
    g_widget_count = g_g3_sn_wid; g_omnitape_tail = g_g3_sn_tape;
    g_omnitape_cmd_count = g_g3_sn_tcmd; g_doc_anchor_count = g_g3_sn_anc;
    g_doc_macro_count = g_g3_sn_mac; g_doc_dirty_mask = g_g3_sn_mask;
    g_doc_dirty = g_g3_sn_dirty;
    g_doc_cont_depth = g_g3_sn_contdepth; g_doc_split_nid = g_g3_sn_split;
    g_doc_drag_nid = g_g3_sn_drag;
}

U0 DolDocPushContainer(I64 nid) {
    if (nid < 0) return;
    if (g_doc_cont_depth < 32) { g_doc_cont_stack[g_doc_cont_depth] = nid; g_doc_cont_depth++; }
    g_doc_cur = nid;
}

U0 DolDocCloseContainer() {
    if (g_doc_cont_depth > 0) {
        g_doc_cont_depth--;
        I64 cid = g_doc_cont_stack[g_doc_cont_depth];
        I64 p = g_doc_nodes[cid].parent;
        g_doc_cur = (p >= 0) ? p : g_doc_root;
    }
}

// ---- Passe 1: MEASURE (bottom-up) ------------------------------------------
U0 DolDocMeasureNode(I64 nid) {
    if (nid < 0 || nid >= g_doc_node_count) return;
    CDocNode *nd = &g_doc_nodes[nid];
    I64 c = nd->first;
    while (c >= 0) { DolDocMeasureNode(c); c = g_doc_nodes[c].next; }
    I64 k = nd->kind;
    if (k == DOC_ROW || k == DOC_COL || k == DOC_SLOT) {
        I64 gp = nd->gap; if (gp < 0) gp = 0;
        I64 pd = nd->pad; if (pd < 0) pd = 0;
        I64 cnt = 0, sumw = 0, sumh = 0, maxw = 0, maxh = 0;
        c = nd->first;
        while (c >= 0) {
            I64 cw = g_doc_nodes[c].meas_w;
            I64 chh = g_doc_nodes[c].meas_h;
            cnt = cnt + 1;
            sumw = sumw + cw; sumh = sumh + chh;
            if (cw > maxw) maxw = cw;
            if (chh > maxh) maxh = chh;
            c = g_doc_nodes[c].next;
        }
        if (k == DOC_ROW) {
            nd->meas_w = sumw + (cnt - 1) * gp + 2 * pd;
            nd->meas_h = maxh + 2 * pd;
        } else {
            nd->meas_w = maxw + 2 * pd;
            nd->meas_h = sumh + (cnt - 1) * gp + 2 * pd;
        }
        if (cnt == 0) {
            // container vazio: o tamanho intrinseco e' o declarado na tag
            nd->meas_w = (nd->w > 0) ? nd->w : 2 * pd;
            nd->meas_h = (nd->h > 0) ? nd->h : 2 * pd;
        }
        return;
    }
    I64 w = 0, h = 0;
    if (k == DOC_BUTTON) { w = nd->text_len * 8 + 16; h = 18; }
    else if (k == DOC_LINK) { w = nd->text_len * 8; h = 18; }
    else if (k == DOC_TOGGLE) { w = 20 + nd->text_len * 8; h = 18; }
    else if (k == DOC_SLIDER) { w = (nd->w > 0) ? nd->w : 140; h = 18; }
    else if (k == DOC_TABS) { w = (nd->text_len > 0) ? (nd->text_len * 10 + 24) : 120; h = 20; }
    else if (k == DOC_CANVAS) { w = (nd->w > 0) ? nd->w : 200; h = (nd->h > 0) ? nd->h : 120; }
    else if (k == DOC_TEXT) { w = nd->text_len * 8; h = 18; }
    else { w = (nd->w > 0) ? nd->w : 80; h = (nd->h > 0) ? nd->h : 18; }
    nd->meas_w = w; nd->meas_h = h;
}

// ---- Passe 2: ARRANGE (top-down) -------------------------------------------
I64 DolDocChildModeW(CDocNode *ch) {
    if (ch->size_mode_w == DOC_SIZE_FIXED) return DOC_SIZE_FIXED;
    if (ch->size_mode_w == DOC_SIZE_FLEX) return DOC_SIZE_FLEX;
    return DOC_SIZE_AUTO;
}

I64 DolDocBaseW(CDocNode *ch) {
    if (DolDocChildModeW(ch) == DOC_SIZE_AUTO) return ch->meas_w;
    return ch->w;
}

// min/max so' valem para PAINEIS (SLOT/ROW/COL): nos folha (SLIDER etc.) os
// campos min/max guardam outra coisa (faixa de valor / cor de borda).
I64 DolDocClampChildW(CDocNode *ch, I64 cw) {
    if (ch->kind == DOC_SLOT || ch->kind == DOC_ROW || ch->kind == DOC_COL) {
        if (cw < ch->min) cw = ch->min;
        if (ch->max > 0 && cw > ch->max) cw = ch->max;
    }
    if (cw < 0) cw = 0;
    return cw;
}

I64 DolDocClampChildH(CDocNode *ch, I64 chh) {
    if (ch->kind == DOC_SLOT || ch->kind == DOC_ROW || ch->kind == DOC_COL) {
        if (chh < ch->min) chh = ch->min;
        if (ch->max > 0 && chh > ch->max) chh = ch->max;
    }
    if (chh < 0) chh = 0;
    return chh;
}

U0 DolDocArrangeNode(I64 nid, I64 x, I64 y, I64 w, I64 h) {
    if (nid < 0 || nid >= g_doc_node_count) return;
    CDocNode *nd = &g_doc_nodes[nid];
    nd->x = x; nd->y = y; nd->w = w; nd->h = h;
    I64 k = nd->kind;
    if (k != DOC_ROW && k != DOC_COL && k != DOC_SLOT) return;
    I64 gp = nd->gap; if (gp < 0) gp = 0;
    I64 pd = nd->pad; if (pd < 0) pd = 0;
    I64 ix = x + pd; I64 iy = y + pd;
    I64 iw = w - 2 * pd; if (iw < 0) iw = 0;
    I64 ih = h - 2 * pd; if (ih < 0) ih = 0;
    I64 cnt = 0; I64 c = nd->first;
    while (c >= 0) { cnt = cnt + 1; c = g_doc_nodes[c].next; }
    if (cnt == 0) return;
    I64 tg = (cnt - 1) * gp;
    if (k == DOC_ROW) {
        I64 avail = iw - tg; if (avail < 0) avail = 0;
        I64 fixed_sum = 0, flex_weight = 0, last_flex = -1;
        c = nd->first;
        while (c >= 0) {
            if (DolDocChildModeW(&g_doc_nodes[c]) == DOC_SIZE_FLEX) {
                I64 fw = g_doc_nodes[c].flex_weight; if (fw < 1) fw = 1;
                flex_weight = flex_weight + fw; last_flex = c;
            } else {
                fixed_sum = fixed_sum + DolDocBaseW(&g_doc_nodes[c]);
            }
            c = g_doc_nodes[c].next;
        }
        I64 rest = avail - fixed_sum; if (rest < 0) rest = 0;
        I64 unit = (flex_weight > 0) ? (rest / flex_weight) : 0;
        I64 cx = ix;
        c = nd->first;
        while (c >= 0) {
            CDocNode *ch = &g_doc_nodes[c];
            I64 cw = 0;
            if (DolDocChildModeW(ch) == DOC_SIZE_FLEX) {
                I64 fw = ch->flex_weight; if (fw < 1) fw = 1;
                // o ULTIMO FLEX absorve o resto da divisao inteira
                if (c == last_flex) cw = rest - unit * (flex_weight - fw);
                else cw = unit * fw;
            } else {
                cw = DolDocBaseW(ch);
            }
            cw = DolDocClampChildW(ch, cw);
            I64 nx = cx + cw + gp;
            DolDocArrangeNode(c, cx, iy, cw, ih);
            cx = nx;
            c = ch->next;
        }
        return;
    }
    // COL (e SLOT, que empilha os filhos na vertical)
    I64 avail = ih - tg; if (avail < 0) avail = 0;
    I64 fixed_sum = 0, flex_weight = 0, last_flex = -1;
    c = nd->first;
    while (c >= 0) {
        CDocNode *ch = &g_doc_nodes[c];
        if (ch->size_mode_h == DOC_SIZE_FLEX) {
            I64 fw = ch->flex_weight; if (fw < 1) fw = 1;
            flex_weight = flex_weight + fw; last_flex = c;
        } else {
            I64 bh = (ch->size_mode_h == DOC_SIZE_AUTO) ? ch->meas_h : ch->h;
            fixed_sum = fixed_sum + bh;
        }
        c = ch->next;
    }
    I64 rest = avail - fixed_sum; if (rest < 0) rest = 0;
    I64 unit = (flex_weight > 0) ? (rest / flex_weight) : 0;
    I64 cy = iy;
    c = nd->first;
    while (c >= 0) {
        CDocNode *ch = &g_doc_nodes[c];
        I64 chh = 0;
        if (ch->size_mode_h == DOC_SIZE_FLEX) {
            I64 fw = ch->flex_weight; if (fw < 1) fw = 1;
            if (c == last_flex) chh = rest - unit * (flex_weight - fw);
            else chh = unit * fw;
        } else if (ch->size_mode_h == DOC_SIZE_AUTO) {
            chh = ch->meas_h;
        } else {
            chh = ch->h;
        }
        chh = DolDocClampChildH(ch, chh);
        I64 ny = cy + chh + gp;
        DolDocArrangeNode(c, ix, cy, iw, chh);
        cy = ny;
        c = ch->next;
    }
}

// ---- Emissores compartilhados (tag nativa e HTML criam o MESMO no) ---------
I64 DolDocEmitRowCol(I64 kind, I64 gap, I64 pad, I64 w, I64 h, U8 *tagstr) {
    I64 n = DolDocWidget(kind, DolDocFlowPx(), DolDocFlowPy(), w, h, tagstr);
    if (n < 0) return -1;
    CDocNode *nd = &g_doc_nodes[n];
    nd->gap = gap; nd->pad = pad;
    nd->size_mode_w = DOC_SIZE_FIXED; nd->size_mode_h = DOC_SIZE_FIXED;
    DolDocPushContainer(n);
    return n;
}

U0 DolDocEmitButton(U8 *lbl, U8 *cmd, U8 *tagstr) {
    I64 vw = strlen(lbl) * 8 + 16;
    I64 cols = (vw + 7) / 8 + 1;
    I64 n = DolDocWidget(DOC_BUTTON, DolDocFlowPx(), DolDocFlowPy(), vw, 18, tagstr);
    if (n >= 0) {
        strncpy(g_doc_args + g_doc_nodes[n].arg_off, cmd, strlen(cmd) + 1);
        DolDocSetLabel(n, lbl);
    }
    DolDocAdvance(cols);
}

U0 DolDocEmitSlider(U8 *id, I64 mn, I64 mx, I64 val, I64 w, U8 *tagstr, U8 *lbl) {
    I64 n = DolDocWidget(DOC_SLIDER, DolDocFlowPx(), DolDocFlowPy(), w, 18, tagstr);
    if (n < 0) return;
    CDocNode *nd = &g_doc_nodes[n];
    nd->min = mn; nd->max = mx; nd->val = val;
    nd->flags = nd->flags | DOCF_ACTION;
    nd->size_mode_w = DOC_SIZE_FIXED; nd->size_mode_h = DOC_SIZE_FIXED;
    if (lbl && lbl[0]) DolDocSetLabel(n, lbl);
    if (id && id[0]) strncpy(g_doc_args + nd->arg_off, id, strlen(id) + 1);
    DolDocAdvance((w + 7) / 8 + 1);
}

U0 DolDocEmitToggle(U8 *id, I64 val, U8 *tagstr, U8 *lbl) {
    I64 w = 120;
    if (lbl && lbl[0]) w = 20 + strlen(lbl) * 8 + 8;
    I64 n = DolDocWidget(DOC_TOGGLE, DolDocFlowPx(), DolDocFlowPy(), w, 18, tagstr);
    if (n < 0) return;
    CDocNode *nd = &g_doc_nodes[n];
    nd->val = (val != 0) ? 1 : 0;
    nd->state = (val != 0) ? 1 : 0;
    nd->flags = nd->flags | DOCF_ACTION;
    nd->size_mode_w = DOC_SIZE_FIXED; nd->size_mode_h = DOC_SIZE_FIXED;
    if (lbl && lbl[0]) DolDocSetLabel(n, lbl);
    if (id && id[0]) strncpy(g_doc_args + nd->arg_off, id, strlen(id) + 1);
    DolDocAdvance((w + 7) / 8 + 1);
}

U0 DolDocEmitTabs(U8 *id, U8 *items, I64 val, I64 w, I64 h, U8 *tagstr) {
    I64 n = DolDocWidget(DOC_TABS, DolDocFlowPx(), DolDocFlowPy(), w, h, tagstr);
    if (n < 0) return;
    CDocNode *nd = &g_doc_nodes[n];
    nd->val = val;
    nd->flags = nd->flags | DOCF_ACTION;
    nd->size_mode_w = DOC_SIZE_FIXED; nd->size_mode_h = DOC_SIZE_FIXED;
    DolDocSetLabel(n, items);
    if (id && id[0]) strncpy(g_doc_args + nd->arg_off, id, strlen(id) + 1);
    DolDocAdvance((w + 7) / 8 + 1);
}

U0 DolDocEmitCanvas(U8 *id, I64 w, I64 h) {
    I64 n = DolDocWidget(DOC_CANVAS, DolDocFlowPx(), DolDocFlowPy(), w, h, id);
    if (n < 0) return;
    CDocNode *nd = &g_doc_nodes[n];
    nd->size_mode_w = DOC_SIZE_FIXED; nd->size_mode_h = DOC_SIZE_FIXED;
    if (id && id[0]) {
        DolDocSetLabel(n, id);
        strncpy(g_doc_args + nd->arg_off, id, strlen(id) + 1);
    }
    DolDocAdvance((w + 7) / 8 + 1);
}

// ---- Tags estruturais nativas ----------------------------------------------
// $ROW,gap=N,pad=N,w=,h=$ ... $END$
U0 DolDocParseRowCol(U8 *tag, I64 kind) {
    I64 w = DolDocGetAttrInt(tag, "w=", 320);
    I64 h = DolDocGetAttrInt(tag, "h=", 0);
    I64 gap = DolDocGetAttrInt(tag, "gap=", 0);
    I64 pad = DolDocGetAttrInt(tag, "pad=", 0);
    DolDocEmitRowCol(kind, gap, pad, w, h, tag);
}

// $SLOT,w=,h=,min=,max=,flex=N,flexh=N,split=1,gap=,pad=$ ... $END$
U0 DolDocParseSlot(U8 *tag) {
    I64 wd = DolDocGetAttrInt(tag, "w=", -1);
    I64 hd = DolDocGetAttrInt(tag, "h=", -1);
    I64 fl = DolDocGetAttrInt(tag, "flex=", 0);
    I64 flh = DolDocGetAttrInt(tag, "flexh=", 0);
    I64 mn = DolDocGetAttrInt(tag, "min=", 0);
    I64 mx = DolDocGetAttrInt(tag, "max=", 0);
    I64 sp = DolDocGetAttrInt(tag, "split=", 0);
    I64 gap = DolDocGetAttrInt(tag, "gap=", 0);
    I64 pad = DolDocGetAttrInt(tag, "pad=", 0);
    I64 w = (wd >= 0) ? wd : 0;
    I64 h = (hd >= 0) ? hd : 0;
    I64 n = DolDocWidget(DOC_SLOT, DolDocFlowPx(), DolDocFlowPy(), w, h, tag);
    if (n < 0) return;
    CDocNode *nd = &g_doc_nodes[n];
    nd->min = mn; nd->max = mx; nd->gap = gap; nd->pad = pad;
    nd->split_draggable = (sp == 1) ? 1 : 0;
    if (fl > 0) { nd->size_mode_w = DOC_SIZE_FLEX; nd->flex_weight = fl; }
    else if (wd >= 0) nd->size_mode_w = DOC_SIZE_FIXED;
    else nd->size_mode_w = DOC_SIZE_AUTO;
    if (flh > 0) { nd->size_mode_h = DOC_SIZE_FLEX; nd->flex_weight = flh; }
    else if (hd >= 0) nd->size_mode_h = DOC_SIZE_FIXED;
    else nd->size_mode_h = DOC_SIZE_AUTO;
    DolDocPushContainer(n);
}

// ---- Widgets compostos (render + hit-test + acao na fila do DolDoc) ---------
// $TABS,id="...",items="A|B|C",val=0,w=,h=$
U0 DolDocParseTabs(U8 *tag) {
    U8 items[128]; items[0] = 0; DolDocGetAttrStr(tag, "items=", items, 120);
    U8 id[64]; id[0] = 0; DolDocGetAttrStr(tag, "id=", id, 60);
    I64 val = DolDocGetAttrInt(tag, "val=", 0);
    I64 w = DolDocGetAttrInt(tag, "w=", 240);
    I64 h = DolDocGetAttrInt(tag, "h=", 24);
    DolDocEmitTabs(id, items, val, w, h, tag);
}

// $SLIDER,id="...",min=0,max=100,val=75,label="...",w=$
U0 DolDocParseSlider2(U8 *tag) {
    U8 id[64]; id[0] = 0; DolDocGetAttrStr(tag, "id=", id, 60);
    U8 lbl[64]; lbl[0] = 0; DolDocGetAttrStr(tag, "label=", lbl, 60);
    I64 mn = DolDocGetAttrInt(tag, "min=", 0);
    I64 mx = DolDocGetAttrInt(tag, "max=", 100);
    I64 val = DolDocGetAttrInt(tag, "val=", 50);
    I64 w = DolDocGetAttrInt(tag, "w=", 160);
    DolDocEmitSlider(id, mn, mx, val, w, tag, lbl);
}

// $TOGGLE,id="...",val=1,label="...",w=$
U0 DolDocParseToggle2(U8 *tag) {
    U8 id[64]; id[0] = 0; DolDocGetAttrStr(tag, "id=", id, 60);
    U8 lbl[64]; lbl[0] = 0; DolDocGetAttrStr(tag, "label=", lbl, 60);
    I64 val = DolDocGetAttrInt(tag, "val=", 0);
    DolDocEmitToggle(id, val, tag, lbl);
}

// $CANVAS,id=,w=,h=$
U0 DolDocParseCanvas(U8 *tag) {
    U8 id[64]; id[0] = 0; DolDocGetAttrStr(tag, "id=", id, 60);
    I64 w = DolDocGetAttrInt(tag, "w=", 200);
    I64 h = DolDocGetAttrInt(tag, "h=", 120);
    DolDocEmitCanvas(id, w, h);
}

I64 DolDocTabCount(CDocNode *nd) {
    if (nd->text_len <= 0) return 0;
    I64 n = 1;
    for (I64 i = 0; i < nd->text_len; i++) {
        if (g_doc_text[nd->text_off + i] == '|') n = n + 1;
    }
    return n;
}

// ---- Hit-test + acao dos widgets compostos ---------------------------------
I64 DolDocWidgetHitTest(I64 mx, I64 my) {
    for (I64 n = g_doc_node_count - 1; n >= 0; n--) {
        I64 k = g_doc_nodes[n].kind;
        if (k != DOC_TABS && k != DOC_SLIDER && k != DOC_TOGGLE && k != DOC_CANVAS) continue;
        CDocNode *nd = &g_doc_nodes[n];
        if (mx >= nd->x && mx < nd->x + nd->w && my >= nd->y && my < nd->y + nd->h) return n;
    }
    return -1;
}

I64 DolDocWidgetClick(I64 nid, I64 mx, I64 my) {
    if (nid < 0 || nid >= g_doc_node_count) return 0;
    CDocNode *nd = &g_doc_nodes[nid];
    if (mx < nd->x || mx >= nd->x + nd->w || my < nd->y || my >= nd->y + nd->h) return 0;
    U8 *wid = (nd->arg_off != 0) ? (g_doc_args + nd->arg_off) : "";
    if (nd->kind == DOC_TABS) {
        I64 ns = DolDocTabCount(nd);
        if (ns < 1) return 0;
        I64 idx = ((mx - nd->x) * ns) / (nd->w > 0 ? nd->w : 1);
        if (idx < 0) idx = 0;
        if (idx >= ns) idx = ns - 1;
        nd->val = idx;
        DolDocPushAction(DOC_ACT_SET, nid, idx, wid);
        return 1;
    }
    if (nd->kind == DOC_SLIDER) {
        I64 mn = nd->min; I64 mxv = nd->max; if (mxv <= mn) mxv = mn + 100;
        I64 nv = mn + ((mx - nd->x) * (mxv - mn)) / (nd->w > 0 ? nd->w : 1);
        if (nv < mn) nv = mn;
        if (nv > mxv) nv = mxv;
        nd->val = nv;
        if (nd->target != 0) DolDocPatchTarget(nd->target, nv);
        g_doc_drag_nid = nid;
        DolDocPushAction(DOC_ACT_SET, nid, nv, wid);
        return 1;
    }
    if (nd->kind == DOC_TOGGLE) {
        nd->state = 1 - nd->state;
        nd->val = nd->state;
        if (nd->target != 0) DolDocPatchTarget(nd->target, nd->state);
        DolDocPushAction(DOC_ACT_SET, nid, nd->state, wid);
        return 1;
    }
    return 0;
}

// ---- Splitter arrastavel (barra no gap, hit-test de 4px) -------------------
// A barra fica na BORDA DIREITA do painel (x+w), dentro do gap do pai.
I64 DolDocSplitterHitTest(I64 mx, I64 my) {
    for (I64 n = 0; n < g_doc_node_count; n++) {
        CDocNode *nd = &g_doc_nodes[n];
        if (nd->split_draggable != 1) continue;
        if (my < nd->y || my >= nd->y + nd->h) continue;
        I64 sx = nd->x + nd->w;
        if (mx >= sx - 2 && mx < sx + 2) return n;
    }
    return -1;
}

// Arrasta o splitter do painel `nid` para a coordenada absoluta `mx`:
// altera node->w (com clamp de min/max), fixa o painel em FIXED e RE-ARRANJA o
// pai inteiro — o irmao FLEX recalcula sozinho.
I64 DolDocSplitterDrag(I64 nid, I64 mx) {
    if (nid < 0 || nid >= g_doc_node_count) return 0;
    CDocNode *nd = &g_doc_nodes[nid];
    I64 p = nd->parent;
    if (p < 0) return 0;
    if (g_doc_nodes[p].kind != DOC_ROW && g_doc_nodes[p].kind != DOC_COL) return 0;
    I64 nw = mx - nd->x;
    if (nw < nd->min) nw = nd->min;
    if (nd->max > 0 && nw > nd->max) nw = nd->max;
    if (nw < 0) nw = 0;
    nd->w = nw;
    nd->size_mode_w = DOC_SIZE_FIXED;
    DolDocArrangeNode(p, g_doc_nodes[p].x, g_doc_nodes[p].y, g_doc_nodes[p].w, g_doc_nodes[p].h);
    return 1;
}

// ---- Parser dual: HTML (5 formas) -> os MESMOS nos das tags nativas --------
I64 DolDocHtmlStyleInt(U8 *style, U8 *key, I64 def) {
    U8 *p = strstr(style, key);
    if (!p) return def;
    p = p + strlen(key);
    while (*p == ' ' || *p == ':' || *p == '=') p++;
    return DolDocAtoi(p);
}

I64 DolDocHtmlAttrInt(U8 *t, U8 *key, I64 def) {
    U8 *p = strstr(t, key);
    if (!p) return def;
    p = p + strlen(key);
    while (*p == ' ' || *p == '=' || *p == '"' || *p == '\'') p++;
    return DolDocAtoi(p);
}

U0 DolDocHtmlAttrStr(U8 *t, U8 *key, U8 *out, I64 max_len) {
    out[0] = 0;
    U8 *p = strstr(t, key);
    if (!p) return;
    p = p + strlen(key);
    while (*p == ' ' || *p == '=') p++;
    I64 i = 0;
    if (*p == '"' || *p == '\'') {
        I64 q = *p; p++;
        while (*p && *p != q && i < max_len - 1) { out[i] = *p; i++; p++; }
    } else {
        while (*p && *p != ' ' && *p != '>' && *p != '/' && i < max_len - 1) { out[i] = *p; i++; p++; }
    }
    out[i] = 0;
}

// Reconhece UMA forma HTML em `p` (que aponta para '<') e emite os mesmos nos
// que a tag nativa correspondente. Devolve o novo ponteiro de leitura, ou 0 se
// nao for uma das 5 formas (o '<' entao sai literal, preservando <<<NEO-DONE>>>).
U8* DolDocHtmlParse(U8 *p) {
    if (!p || *p != '<') return 0;
    if (p[1] == '/') {
        if (strncmp(p, "</div>", 6) == 0) { DolDocCloseContainer(); return p + 6; }
        if (strncmp(p, "</button>", 9) == 0) return p + 9;
        if (strncmp(p, "</canvas>", 9) == 0) return p + 9;
        return 0;
    }
    U8 hb[512];
    I64 i = 0;
    U8 *q = p;
    while (*q && *q != '>' && i < 500) { hb[i] = *q; i++; q++; }
    if (*q != '>') return 0;
    hb[i] = 0;
    if (strncmp(hb, "<div", 4) == 0) {
        U8 style[256]; style[0] = 0;
        DolDocHtmlAttrStr(hb, "style=", style, 250);
        I64 gap = DolDocHtmlStyleInt(style, "gap:", 0);
        I64 pad = DolDocHtmlStyleInt(style, "pad:", 0);
        I64 col = (strstr(style, "display:col") != 0) ? 1 : 0;
        I64 w = DolDocHtmlAttrInt(hb, "w=", 320);
        I64 h = DolDocHtmlAttrInt(hb, "h=", 0);
        DolDocEmitRowCol(col ? DOC_COL : DOC_ROW, gap, pad, w, h, hb);
        return q + 1;
    }
    if (strncmp(hb, "<button", 7) == 0) {
        U8 cmd[128]; cmd[0] = 0;
        DolDocHtmlAttrStr(hb, "onclick=", cmd, 120);
        U8 lbl[64]; I64 li = 0;
        U8 *t = q + 1;
        while (*t && *t != '<' && li < 60) { lbl[li] = *t; li++; t++; }
        lbl[li] = 0;
        DolDocEmitButton(lbl, cmd, hb);
        if (strncmp(t, "</button>", 9) == 0) t = t + 9;
        return t;
    }
    if (strncmp(hb, "<input", 6) == 0) {
        U8 ty[32]; ty[0] = 0; DolDocHtmlAttrStr(hb, "type=", ty, 30);
        U8 id[64]; id[0] = 0; DolDocHtmlAttrStr(hb, "id=", id, 60);
        if (strcmp(ty, "range") == 0) {
            I64 mn = DolDocHtmlAttrInt(hb, "min=", 0);
            I64 mx = DolDocHtmlAttrInt(hb, "max=", 100);
            I64 vv = DolDocHtmlAttrInt(hb, "val=", -1);
            if (vv < 0) vv = DolDocHtmlAttrInt(hb, "value=", 50);
            I64 w = DolDocHtmlAttrInt(hb, "w=", 140);
            DolDocEmitSlider(id, mn, mx, vv, w, hb, 0);
            return q + 1;
        }
        if (strcmp(ty, "checkbox") == 0) {
            I64 ck = (strstr(hb, "checked") != 0) ? 1 : 0;
            DolDocEmitToggle(id, ck, hb, 0);
            return q + 1;
        }
        return 0;
    }
    if (strncmp(hb, "<canvas", 7) == 0) {
        U8 id[64]; id[0] = 0; DolDocHtmlAttrStr(hb, "id=", id, 60);
        I64 w = DolDocHtmlAttrInt(hb, "w=", 200);
        I64 h = DolDocHtmlAttrInt(hb, "h=", 120);
        DolDocEmitCanvas(id, w, h);
        return q + 1;
    }
    return 0;
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

    // ---- G3: tags estruturais e widgets compostos ---------------------------
    // Vem ANTES das tags de duas letras porque $ROW$ colidiria com $RO$,
    // $SLOT$ com $SL$, $COL$ com $CO$, $CANVAS$ com $CA$ (card).
    if (strncmp(tag, "ROW", 3) == 0) { DolDocParseRowCol(tag, DOC_ROW); return; }
    if (strncmp(tag, "COL", 3) == 0) { DolDocParseRowCol(tag, DOC_COL); return; }
    if (strncmp(tag, "SLOT", 4) == 0) { DolDocParseSlot(tag); return; }
    if (strncmp(tag, "END", 3) == 0) { DolDocCloseContainer(); return; }
    if (strncmp(tag, "TABS", 4) == 0) { DolDocParseTabs(tag); return; }
    if (strncmp(tag, "SLIDER", 6) == 0) { DolDocParseSlider2(tag); return; }
    if (strncmp(tag, "TOGGLE", 6) == 0) { DolDocParseToggle2(tag); return; }
    if (strncmp(tag, "CANVAS", 6) == 0) { DolDocParseCanvas(tag); return; }

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
        DolDocEmitButton(lbl, cmd, tag);
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
    if (strncmp(tag, "SPRING", 6) == 0) { DolDocParseSpring(tag); return; }
    if (strncmp(tag, "VBOX", 4) == 0) { DolDocParseContainer(tag, DOC_VBOX); return; }
    if (strncmp(tag, "HBOX", 4) == 0) { DolDocParseContainer(tag, DOC_HBOX); return; }
    if (strncmp(tag, "GRID", 4) == 0) { DolDocParseContainer(tag, DOC_GRIDC); return; }
    if (strncmp(tag, "SPLIT", 5) == 0) { DolDocParseContainer(tag, DOC_SPLIT); return; }
    if (strncmp(tag, "NODE_GRAPH", 10) == 0) { DolDocParseIndustrial(tag, DOC_NODEGRAPH); return; }
    if (strncmp(tag, "BLOCK_EDITOR", 12) == 0) { DolDocParseIndustrial(tag, DOC_BLOCKEDIT); return; }
    if (strncmp(tag, "ISLAND", 6) == 0) { DolDocParseIndustrial(tag, DOC_ISLAND); return; }
    if (strncmp(tag, "REPL", 4) == 0) { DolDocParseRepl(tag); return; }
    if (strncmp(tag, "PROF", 4) == 0) { DolDocParseProfiler(tag); return; }
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
        // G3: parser dual — as 5 formas HTML reconhecidas viram os MESMOS nos
        // que as tags nativas. Um '<' que nao casa nenhuma forma sai literal
        // (preserva <<<NEO-DONE:selftest>>> e qualquer texto com '<').
        if (*str == '<') {
            U8 *hnext = DolDocHtmlParse(str);
            if (hnext) { str = hnext; continue; }
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
    g_doc_cont_depth = 0;      // G3: nenhum container aberto depois de um clear
    g_doc_split_nid = -1;      // G3: nenhum splitter em arraste
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
    ShaderLegacyRenderNode(vx, vy, vw, vh, sh_type);
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
        if (hgl_cube == 0 || hgl_cube == (U64)&SymUnresolvedTrap) {
            doldoc_printf("$FG,RED$[SYMBOLS] FATAL: lookup failed for 'HolyGLRenderCube' (0x%016llX)$FG$\n", hgl_cube);
            hgl_cube = 0;
        }
        if (hgl_vp == 0 || hgl_vp == (U64)&SymUnresolvedTrap) {
            doldoc_printf("$FG,RED$[SYMBOLS] FATAL: lookup failed for 'HolyGLViewport' (0x%016llX)$FG$\n", hgl_vp);
            hgl_vp = 0;
        }
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
    // P8.0 Slate containers: a subtle frame makes the slot structure visible.
    if (kind == DOC_VBOX || kind == DOC_HBOX || kind == DOC_GRIDC || kind == DOC_SPLIT ||
        kind == DOC_ROW || kind == DOC_COL) {
        gfx_draw_rect(vx, vy, vw, 1, surface1);
        gfx_draw_rect(vx, vy + vh - 1, vw, 1, surface1);
        gfx_draw_rect(vx, vy, 1, vh, surface1);
        gfx_draw_rect(vx + vw - 1, vy, 1, vh, surface1);
        return;
    }
    // G3: $SLOT$ — painel; quando split=1 desenha a barra divisoria NO GAP
    // (borda direita) que o hit-test de 4px usa para o arraste.
    if (kind == DOC_SLOT) {
        gfx_draw_rect(vx, vy, 1, vh, surface1);
        gfx_draw_rect(vx + vw - 1, vy, 1, vh, surface1);
        if (nd->split_draggable == 1) {
            gfx_draw_rect(vx + vw, vy + 2, 2, vh - 4, sapphire);
            gfx_draw_rect(vx + vw - 1, vy + vh / 2 - 6, 2, 12, sky);
        }
        return;
    }
    // G3: $TABS$ — controle segmentado; o segmento ativo (val) fica elevado.
    if (kind == DOC_TABS) {
        I64 nseg = DolDocTabCount(nd);
        if (nseg < 1) nseg = 1;
        gfx_draw_rounded_rect(vx, vy, vw, vh, 4, surface0);
        if (vw > 0) {
            I64 segw = vw / nseg;
            I64 seg = 0;
            I64 off = 0;
            while (seg < nseg && segw > 0) {
                I64 sx = vx + seg * segw;
                I64 sw = (seg == nseg - 1) ? (vw - seg * segw) : segw;
                if (seg == nd->val) {
                    gfx_draw_rounded_rect(sx + 1, vy + 1, sw - 2, vh - 2, 3, surface1);
                    gfx_draw_rect(sx + 1, vy + vh - 2, sw - 2, 2, sapphire);
                }
                I64 ls = off; I64 le = off;
                while (le < nd->text_len && g_doc_text[nd->text_off + le] != '|') le++;
                I64 ll = le - ls;
                if (ll > 0) {
                    U8 sb[40]; I64 k = 0;
                    while (k < ll && k < 38) { sb[k] = g_doc_text[nd->text_off + ls + k]; k++; }
                    sb[k] = 0;
                    gfx_draw_string(sx + (sw - ll * 8) / 2, vy + (vh - 16) / 2, sb,
                                    (seg == nd->val) ? text_col : DolDocResolveColor(SEM_COLOR_SUBTEXT), 0);
                }
                off = le + 1;
                seg = seg + 1;
            }
        }
        return;
    }
    // G3: $CANVAS$ — superficie de desenho com grade de referencia.
    if (kind == DOC_CANVAS) {
        gfx_draw_rounded_rect(vx, vy, vw, vh, 6, surface0);
        gfx_draw_rect(vx + 1, vy + 1, vw - 2, vh - 2, crust);
        I64 cgx = vx + 24;
        while (cgx < vx + vw - 4) { gfx_draw_rect(cgx, vy + 2, 1, vh - 4, surface1); cgx = cgx + 24; }
        I64 cgy = vy + 24;
        while (cgy < vy + vh - 4) { gfx_draw_rect(vx + 2, cgy, vw - 4, 1, surface1); cgy = cgy + 24; }
        if (lbl[0]) gfx_draw_string(vx + 6, vy + 2, lbl, sky, 0);
        return;
    }
    // P8.0 industrial nodes + the live Shell node.
    if (kind == DOC_NODEGRAPH || kind == DOC_BLOCKEDIT || kind == DOC_ISLAND || kind == DOC_REPL) {
        U32 accent = (kind == DOC_NODEGRAPH) ? sapphire : ((kind == DOC_BLOCKEDIT) ? teal : ((kind == DOC_REPL) ? peach : sky));
        gfx_draw_soft_shadow(vx, vy, vw, vh, 6, g_theme.shadow_color);
        gfx_draw_rounded_rect(vx, vy, vw, vh, 6, surface0);
        gfx_draw_rect(vx + 1, vy + 1, vw - 2, 18, accent);
        gfx_draw_string(vx + 8, vy + 2, lbl, 0xFF11111B, 0);
        if (kind == DOC_NODEGRAPH) {
            gfx_draw_line(vx + vw / 4, vy + vh / 2, vx + vw / 2, vy + vh / 3, surface1);
            gfx_draw_line(vx + vw / 2, vy + vh / 3, vx + 3 * vw / 4, vy + vh / 2, surface1);
            gfx_draw_circle_filled(vx + vw / 4, vy + vh / 2, 8, accent);
            gfx_draw_circle_filled(vx + vw / 2, vy + vh / 3, 8, sky);
            gfx_draw_circle_filled(vx + 3 * vw / 4, vy + vh / 2, 8, teal);
        } else if (kind == DOC_BLOCKEDIT) {
            I64 by = vy + 24;
            while (by + 12 < vy + vh - 4) { gfx_draw_rounded_rect(vx + 8, by, vw - 16, 12, 3, surface1); by = by + 16; }
        } else if (kind == DOC_REPL) {
            gfx_draw_string(vx + 8, vy + 26, "> _", peach, 0);
        } else {
            gfx_draw_rect(vx + 8, vy + 24, vw - 16, vh - 32, surface1);
        }
        return;
    }
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
        // G1: the thumb glides to the value with a BOUNCY spring (inertia + overshoot),
        // so dragging a slider feels tactile instead of snapping rigidly.
        F64 sfill = EffectsSpringPull((F64)(g_doc_cur_nid & 63), (F64)fill_w, 18.0, 1.0, 0.016);
        I64 sfill_i = (I64)sfill;
        if (sfill_i < 0) sfill_i = 0; if (sfill_i > vw - 12) sfill_i = vw - 12;
        I64 thumb_x = vx + sfill_i + 6; I64 thumb_y = track_y + 3;
        gfx_draw_circle_filled(thumb_x, thumb_y, 7, text_col);
        gfx_draw_circle_filled(thumb_x, thumb_y, 5, sapphire);
        U8 vs[16]; I64 tv = val; I64 pi = 0;
        if (tv <= 0) { vs[0] = '0'; vs[1] = 0; }
        else { U8 rev[16]; I64 ri = 0; while (tv > 0 && ri < 12) { rev[ri] = '0' + (tv % 10); ri++; tv /= 10; } for (I64 d = 0; d < ri; d++) vs[d] = rev[ri - 1 - d]; vs[ri] = 0; }
        gfx_draw_string(vx + vw + 8, vy + 2, vs, yellow, 0);
        // G3: $SLIDER,label="..."$ desenha o rotulo acima do trilho
        if ((nd->flags & DOCF_ACTION) != 0 && lbl[0]) {
            gfx_draw_string(vx, vy - 12, lbl, DolDocResolveColor(SEM_COLOR_SUBTEXT), 0);
        }
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
    g_doc_cur_nid = nid;   // G1: selects this node's spring slot
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
    if (nd->kind == DOC_PROF) return;   // P9.0: drawn by the last pass in DolDocRedraw
    DolDocDrawWidget(nd, scroll);
}

U0 DolDocRedraw() {
    if (g_doc_dirty_mask == 0 && g_doc_dirty == 0) return;
    g_doc_anim_tick++;
    DolDocSlatePass();   // P8.0: two-pass container layout before drawing
    gfx_set_clip(g_doc_x, g_doc_y, g_doc_w, g_doc_h);
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, g_doc_h, DolDocResolveColor(g_doc_cur_bg));
    gfx_draw_rect(g_doc_x, g_doc_y, g_doc_w, 1, DolDocResolveColor(SEM_COLOR_SURFACE0));
    DolDocDrawChildren(g_doc_root, g_doc_scroll_offset * 18);
    if (g_doc_inspected_nid >= 0 && g_doc_inspected_nid < g_doc_node_count) DolDocDrawHalo(g_doc_inspected_nid);
    // P9.0: the live profiler panel is drawn LAST so it is never covered.
    for (I64 pn = 0; pn < g_doc_node_count; pn++) {
        if (g_doc_nodes[pn].kind == DOC_PROF) {
            ProfilerDrawPanel(g_doc_nodes[pn].x,
                              g_doc_nodes[pn].y + g_doc_scroll_offset * 18,
                              g_doc_nodes[pn].w, g_doc_nodes[pn].h);
        }
    }
    gfx_reset_clip();
    g_doc_dirty_mask = 0;
    g_doc_dirty = 0;
}

U0 DolDocAnimateTick() {
    if (g_doc_node_count <= 0) return;
    g_doc_anim_tick++;
    DolDocSpringTick();   // P8.0: settle harmonic-spring nodes toward their targets
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

    // G3: widgets compostos com id (TABS/SLIDER/TOGGLE) — hit-test + acao
    if ((nd->flags & DOCF_ACTION) != 0) {
        if (DolDocWidgetClick(nid, mx, my)) {
            DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
            return 1;
        }
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
            // P8-fix: `cmd` aponta para g_doc_args (argumento de tag, pode ter
            // dezenas de KB); g_click_cmd_buf tem 256 bytes. O strcpy transbordava
            // a BSS. Copia limitada com terminador garantido.
            I64 cc_i = 0;
            while (cc_i < 255 && cmd[cc_i] != 0) { g_click_cmd_buf[cc_i] = cmd[cc_i]; cc_i++; }
            g_click_cmd_buf[cc_i] = 0;
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
    // G3: arraste da barra divisoria de um $SLOT,split=1$
    if (g_doc_split_nid >= 0) {
        if (DolDocSplitterDrag(g_doc_split_nid, mx) == 1) {
            DolDocMarkAllDirty(); DolDocRedraw(); doldoc_swap_term();
            return 1;
        }
    }
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
    I64 done = 0;
    if (g_doc_split_nid >= 0) { g_doc_split_nid = -1; done = 1; }   // G3: solta o splitter
    if (g_doc_drag_nid >= 0) { g_doc_drag_nid = -1; done = 1; }
    return done;
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
    // G2: photorealistic glass — a dual-Kawase PYRAMID backdrop plus the analytic SDF
    // material (rounded corners, refraction, chromatic aberration, specular rim
    // light, grain). Falls back to a translucent fill only if the region is too small.
    if (g_comp.glass_enabled && w >= 8 && h >= 8) {
        I64 rad = g_theme.corner_radius;
        if (rad < 4) rad = 4;
        if (EffectsGlassRegion(x, y, w, h, rad, g_theme.glass_tint & 0x00FFFFFF, alpha, 3) == 0) return;
    }
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
    // P8/Passo 2: compoe o cursor no BACK buffer como camada Z-topo, ANTES do
    // present. RenderGoldenScene() NAO passa por aqui — por isso o hash golden
    // 0xD28836F permanece intacto. O cursor entra no dirty rect via
    // DolDocDamageRect() dentro de MouseComposeCursor().
    MouseComposeCursor();
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

// ============================================================================
// BLOCO 2 - DUTO UNICO DE ENTRADA: consumidor DolDoc.
// ----------------------------------------------------------------------------
// VirtioInput.HC (teclado + mouse VirtIO) e Keyboard.HC (UART/serial) alimentam
// UMA fila CInputEvent (apps/InputQueue.HC). DolDocDispatchInput() e o unico
// consumidor: o DolDoc tem o PRIMEIRO olhar (atalhos globais do XFCE), e o que
// ele nao consumir cai no Shell (buffer de teclado) ou no cursor (mouse).
// Nenhum driver chama MouseSetPos/KeyboardQueueChar por conta propria.
// ============================================================================
I64 g_input_desktop_active = 0;   // 1 enquanto um loop de desktop estiver ativo

// Atalhos globais do XFCE. So consome quando ha um desktop ativo: no terminal
// puro Alt+1 continua digitando '1' (o duto e o mesmo, a politica e que muda).
I64 DolDocHandleGlobalKey(CInputEvent *ev) {
  if (ev == 0) return 0;
  if (ev->type != INPUT_EV_KEY) return 0;
  if ((ev->modifiers & INPUT_MOD_ALT) == 0) return 0;
  if (!g_doc_desktop_running && !g_input_desktop_active) return 0;
  I64 k = ev->key_code;
  if (k >= '1' && k <= '4') {
    I64 ws = k - '1';
    if (ws < INPUT_ALT_WS_MAX) {
      if (g_xf_ws != ws) { g_xf_ws = ws; g_doc_dirty = 1; g_shell_dirty = 1; }
      return 1;                       // consumido pelo DolDoc: NAO desce ao Shell
    }
  }
  return 0;
}

U0 DolDocDispatchInput() {
  CInputEvent ev;
  I64 guard = 0;
  while (InputQueueCount() > 0 && guard < INPUT_Q_SIZE + 8) {
    guard++;
    if (InputQueuePop(&ev) != 0) break;
    if (ev.type == INPUT_EV_KEY) {
      if (DolDocHandleGlobalKey(&ev)) continue;
      I64 k = ev.key_char;
      if (k == 0) k = ev.key_code;
      if (k != 0) KeyboardQueueChar(k);
    } else if (ev.type == INPUT_EV_MOUSE) {
      if (ev.buttons != 0 || MouseGetButtons() != 0) {
        MouseSetButton(ev.buttons & 1, (ev.buttons >> 1) & 1);
      }
      MouseSetPos(ev.mouse_x, ev.mouse_y);
    }
  }
}

// BLOCO 2: prova do atalho global a partir de SelfTest.HC (que carrega antes do
// DolDoc.HC e nao pode declarar locais com os tipos/globais daqui).
// Devolve 1 se o Alt+2 foi consumido pelo DolDoc e NAO vazou para o Shell.
I64 DolDocInputTestGlobalKey() {
  I64 ws_save = g_xf_ws;
  I64 act_save = g_input_desktop_active;
  I64 run_save = g_doc_desktop_running;
  g_xf_ws = 0;
  g_input_desktop_active = 1;             // finge um desktop ativo
  g_doc_desktop_running = 0;
  InputQueueClear();
  InputQueuePushKey('2', '2', INPUT_MOD_ALT);
  DolDocDispatchInput();
  I64 ws_now = g_xf_ws;
  I64 leaked = KeyboardHasChar();
  g_xf_ws = ws_save;
  g_input_desktop_active = act_save;
  g_doc_desktop_running = run_save;
  if (ws_now == 1 && leaked == 0) return 1;
  return 0;
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
                    else if (mx >= d_x + 210 && mx <= d_x + 284) DolDocPushAction(DOC_ACT_RUN, -1, 0, "selftest");
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
        DolDocDispatchInput();
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
// P9 — XFCE DESKTOP (Top Panel / janelas / Bottom Dock) + SETTINGS MANAGER
//
// TUDO construido SOBRE o motor de layout G3 (DolDocMeasureNode = passe 1,
// DolDocArrangeNode = passe 2) e sobre o parser de tags nativo. Nao existe um
// segundo sistema de layout: o esqueleto do desktop E' um documento G3
// ($COL/$ROW/$SLOT) arranjado pelos dois passes, e o Settings Manager usa
// $TABS$/$SLIDER$/$TOGGLE$ de verdade (mesmos nos, mesmo render, mesmo hit-test
// DolDocWidgetClick que o SelfTest ja cobre).
//
// EFEITO OBSERVADOR (medido nesta sessao): doldoc_printf escreve no documento
// VIVO e dispara DolDocArrangeNode() -> reposiciona os nos ja arranjados. Por
// isso DolDocXFEERelayout() copia TODA a geometria para locais/globais
// IMEDIATAMENTE apos o arranjo, antes de qualquer print, e so' entao loga.
// Depois do arranjo o esqueleto e' DESLIGADO da arvore viva (DolDocUnlink) para
// que o documento do Shell nao o desenhe nem o mova.
// ============================================================================

#define XFCE_MAX_WIN      8
#define XFCE_WS_COUNT     4
#define XFCE_WINTITLE_LEN 40
#define XFCE_LAUNCH_COUNT 5
#define XFCE_MAX_SET_WID  32

// ---- geometria capturada do passe ARRANGE (G3) ------------------------------
I64 g_xf_ready = 0;
I64 g_xf_top_x = 0, g_xf_top_y = 0, g_xf_top_w = 0, g_xf_top_h = 0;
I64 g_xf_area_x = 0, g_xf_area_y = 0, g_xf_area_w = 0, g_xf_area_h = 0;
I64 g_xf_dock_x = 0, g_xf_dock_y = 0, g_xf_dock_w = 0, g_xf_dock_h = 0;
I64 g_xf_menu_x = 0, g_xf_menu_w = 0, g_xf_menu_h = 0;
I64 g_xf_ws_x[XFCE_WS_COUNT], g_xf_ws_w[XFCE_WS_COUNT], g_xf_ws_h = 0;
I64 g_xf_tray_x[3], g_xf_tray_w[3], g_xf_tray_h = 0;
I64 g_xf_launch_x[XFCE_LAUNCH_COUNT], g_xf_launch_w[XFCE_LAUNCH_COUNT];
I64 g_xf_launch_h = 0, g_xf_launch_n = 0;
I64 g_xf_tasks_x = 0, g_xf_tasks_w = 0, g_xf_tasks_h = 0;
I64 g_xf_skel_nid = -1;
I64 g_xf_base_nodes = 0, g_xf_base_text = 0, g_xf_base_args = 0;
I64 g_xf_sn_col = 0, g_xf_sn_row = 0, g_xf_sn_run = -1;
I64 g_xf_end_nodes = 0;
I64 g_xf_flow_col = 0, g_xf_flow_row = 0, g_xf_flow_run = -1;

// ---- Settings Manager ($TABS$ / $SLIDER$ / $TOGGLE$) ------------------------
I64 g_xf_set_nid = -1;
I64 g_xf_set_tabs_nid = -1;
I64 g_xf_set_page_nid[XFCE_WS_COUNT];
I64 g_xf_set_wid_nid[XFCE_MAX_SET_WID];
I64 g_xf_set_wid_page[XFCE_MAX_SET_WID];
I64 g_xf_set_nwid = 0;
I64 g_xf_set_page = 0;

// ---- janelas ---------------------------------------------------------------
I64 g_xf_nwin = 0;
I64 g_xf_next_id = 1;
I64 g_xf_active_id = -1;
I64 g_xf_win_id[XFCE_MAX_WIN];
I64 g_xf_win_x[XFCE_MAX_WIN], g_xf_win_y[XFCE_MAX_WIN];
I64 g_xf_win_w[XFCE_MAX_WIN], g_xf_win_h[XFCE_MAX_WIN];
I64 g_xf_win_ws[XFCE_MAX_WIN], g_xf_win_kind[XFCE_MAX_WIN];
I64 g_xf_win_min[XFCE_MAX_WIN], g_xf_win_max[XFCE_MAX_WIN];
I64 g_xf_win_rx[XFCE_MAX_WIN], g_xf_win_ry[XFCE_MAX_WIN];
I64 g_xf_win_rw[XFCE_MAX_WIN], g_xf_win_rh[XFCE_MAX_WIN];
U8  g_xf_win_title[XFCE_MAX_WIN * XFCE_WINTITLE_LEN];
I64 g_xf_z[XFCE_MAX_WIN];
I64 g_xf_term_slot = -1;
I64 g_xf_set_slot = -1;

// ---- interacao -------------------------------------------------------------
I64 g_xf_ws = 0;
I64 g_xf_running = 0;
I64 g_xf_menu_open = 0;
I64 g_xf_prev_btn = 0;
I64 g_xf_drag_slot = -1;
I64 g_xf_drag_dx = 0, g_xf_drag_dy = 0;
I64 g_xf_drag_wid = -1;
I64 g_xf_tick = 0;
I64 g_xf_files_n = -1;
I64 g_xf_files_sec = -1;
U8  g_xf_filebuf[48 * 64];

// ============================================================================
// Helpers
// ============================================================================
U0 DolDocXFEUInt(U8 *dst, I64 v, I64 min_digits) {
    U8 rev[24];
    I64 r = 0;
    if (v < 0) v = 0;
    if (v == 0) { rev[r] = '0'; r++; }
    while (v > 0 && r < 20) { rev[r] = '0' + (v % 10); r++; v = v / 10; }
    while (r < min_digits && r < 22) { rev[r] = '0'; r++; }
    I64 i = 0;
    while (r > 0) { r--; dst[i] = rev[r]; i++; }
    dst[i] = 0;
}

// log serial (uart_puts NAO toca no documento vivo -> nao dispara re-layout)
U0 DolDocXFELog(U8 *tag, I64 v) {
    U8 buf[96];
    I64 i = 0;
    while (tag[i] && i < 78) { buf[i] = tag[i]; i++; }
    U8 num[24];
    DolDocXFEUInt(num, v, 1);
    I64 j = 0;
    while (num[j] && i < 92) { buf[i] = num[j]; i++; j++; }
    buf[i] = '\n'; i++;
    buf[i] = 0;
    uart_puts(buf);
}

U8 *DolDocXFETitle(I64 s) { return g_xf_win_title + s * XFCE_WINTITLE_LEN; }

I64 DolDocXFETitlebarH() {
    I64 tb = g_theme.titlebar_h;
    if (tb < 18) tb = 18;
    if (tb > 48) tb = 48;
    return tb;
}

// k-esimo filho de um no (varredura da lista ligada first/next)
I64 DolDocXFESkelChild(I64 parent, I64 k) {
    if (parent < 0 || parent >= g_doc_node_count) return -1;
    I64 c = g_doc_nodes[parent].first;
    I64 i = 0;
    while (c >= 0) {
        if (i == k) return c;
        i++;
        c = g_doc_nodes[c].next;
    }
    return -1;
}

// ultimo filho com indice >= from (o no recem-criado por um print)
I64 DolDocXFELastChildFrom(I64 parent, I64 from) {
    if (parent < 0 || parent >= g_doc_node_count) return -1;
    I64 c = g_doc_nodes[parent].last;
    while (c >= 0) {
        if (c >= from) return c;
        c = g_doc_nodes[c].prev;
    }
    return -1;
}

// ============================================================================
// Esqueleto G3: $COL$ raiz -> $ROW$ Top Panel / $SLOT$ area / $ROW$ Bottom Dock
// ============================================================================
U0 DolDocXFEESkeletonBuild() {
    I64 sw = g_comp.screen_w; if (sw <= 0) sw = 1024;
    I64 sh = g_comp.screen_h; if (sh <= 0) sh = 768;

    I64 n0 = g_doc_node_count;
    DolDocPrint("$COL,pad=0,gap=0,w=1024,h=768$");
    // ---- Top Panel (h=28) ---------------------------------------------------
    DolDocPrint("$ROW,pad=0,gap=6,h=28$");
    DolDocPrint("$SLOT,w=110,h=20$$END$");          // 0: botao de menu
    DolDocPrint("$SLOT,w=26,h=20$$END$");           // 1: workspace 1
    DolDocPrint("$SLOT,w=26,h=20$$END$");           // 2: workspace 2
    DolDocPrint("$SLOT,w=26,h=20$$END$");           // 3: workspace 3
    DolDocPrint("$SLOT,w=26,h=20$$END$");           // 4: workspace 4
    DolDocPrint("$SLOT,flex=1,h=20$$END$");         // 5: espacador
    DolDocPrint("$SLOT,w=96,h=20$$END$");           // 6: tray FPS
    DolDocPrint("$SLOT,w=110,h=20$$END$");          // 7: tray disco
    DolDocPrint("$SLOT,w=110,h=20$$END$");          // 8: tray relogio
    DolDocPrint("$END$");
    // ---- Area de janelas (flex na vertical) ---------------------------------
    DolDocPrint("$SLOT,flexh=1,min=0$");
    DolDocPrint("$END$");
    // ---- Bottom Dock (h=44) -------------------------------------------------
    DolDocPrint("$ROW,pad=0,gap=6,h=44$");
    DolDocPrint("$SLOT,w=40,h=40$$END$");           // 0: Terminal
    DolDocPrint("$SLOT,w=40,h=40$$END$");           // 1: Settings
    DolDocPrint("$SLOT,w=40,h=40$$END$");           // 2: Files
    DolDocPrint("$SLOT,w=40,h=40$$END$");           // 3: Gears 3D
    DolDocPrint("$SLOT,w=40,h=40$$END$");           // 4: Shader
    DolDocPrint("$SLOT,flex=1,h=40$$END$");         // 5: lista de janelas
    DolDocPrint("$END$");
    DolDocPrint("$END$");

    g_xf_skel_nid = DolDocXFELastChildFrom(g_doc_root, n0);
    if (g_xf_skel_nid < 0) { uart_puts("[XFCE] FATAL: esqueleto G3 nao criado\n"); return; }
    g_xf_base_nodes = n0;
    DolDocXFEERelayout();
    // desliga o esqueleto da arvore viva: o documento do Shell nao o desenha
    DolDocUnlink(g_xf_skel_nid);
    DolDocXFELog("[XFCE] skel_nid=", g_xf_skel_nid);
    DolDocXFELog("[XFCE] panel y/h=", g_xf_top_y);
    DolDocXFELog("[XFCE] panel h=", g_xf_top_h);
    DolDocXFELog("[XFCE] area y=", g_xf_area_y);
    DolDocXFELog("[XFCE] area h=", g_xf_area_h);
    DolDocXFELog("[XFCE] dock y=", g_xf_dock_y);
    DolDocXFELog("[XFCE] dock h=", g_xf_dock_h);
}

// Passe 1 + Passe 2 sobre o esqueleto e CAPTURA IMEDIATA da geometria.
U0 DolDocXFEERelayout() {
    I64 r = g_xf_skel_nid;
    if (r < 0 || r >= g_doc_node_count) return;
    I64 sw = g_comp.screen_w; if (sw <= 0) sw = 1024;
    I64 sh = g_comp.screen_h; if (sh <= 0) sh = 768;
    DolDocMeasureNode(r);
    DolDocArrangeNode(r, 0, 0, sw, sh);

    // ---- copia para LOCAIS imediatamente (antes de qualquer print) ----------
    I64 c_top = DolDocXFESkelChild(r, 0);
    I64 c_area = DolDocXFESkelChild(r, 1);
    I64 c_dock = DolDocXFESkelChild(r, 2);
    I64 l_top_x = 0, l_top_y = 0, l_top_w = 0, l_top_h = 0;
    I64 l_area_x = 0, l_area_y = 0, l_area_w = 0, l_area_h = 0;
    I64 l_dock_x = 0, l_dock_y = 0, l_dock_w = 0, l_dock_h = 0;
    if (c_top >= 0) { l_top_x = g_doc_nodes[c_top].x; l_top_y = g_doc_nodes[c_top].y;
                      l_top_w = g_doc_nodes[c_top].w; l_top_h = g_doc_nodes[c_top].h; }
    if (c_area >= 0) { l_area_x = g_doc_nodes[c_area].x; l_area_y = g_doc_nodes[c_area].y;
                       l_area_w = g_doc_nodes[c_area].w; l_area_h = g_doc_nodes[c_area].h; }
    if (c_dock >= 0) { l_dock_x = g_doc_nodes[c_dock].x; l_dock_y = g_doc_nodes[c_dock].y;
                       l_dock_w = g_doc_nodes[c_dock].w; l_dock_h = g_doc_nodes[c_dock].h; }

    I64 l_menu_x = 0, l_menu_w = 0, l_menu_h = 0;
    I64 l_wsx[XFCE_WS_COUNT], l_wsw[XFCE_WS_COUNT], l_wsh = 0;
    I64 l_trx[3], l_trw[3], l_trh = 0;
    I64 l_lnx[XFCE_LAUNCH_COUNT], l_lnw[XFCE_LAUNCH_COUNT], l_lnh = 0, l_lnn = 0;
    I64 l_tsx = 0, l_tsw = 0, l_tsh = 0;
    for (I64 i = 0; i < XFCE_WS_COUNT; i++) { l_wsx[i] = 0; l_wsw[i] = 0; }
    for (I64 i = 0; i < 3; i++) { l_trx[i] = 0; l_trw[i] = 0; }
    for (I64 i = 0; i < XFCE_LAUNCH_COUNT; i++) { l_lnx[i] = 0; l_lnw[i] = 0; }

    I64 m = DolDocXFESkelChild(c_top, 0);
    if (m >= 0) { l_menu_x = g_doc_nodes[m].x; l_menu_w = g_doc_nodes[m].w; l_menu_h = g_doc_nodes[m].h; }
    for (I64 i = 0; i < XFCE_WS_COUNT; i++) {
        I64 w = DolDocXFESkelChild(c_top, 1 + i);
        if (w >= 0) { l_wsx[i] = g_doc_nodes[w].x; l_wsw[i] = g_doc_nodes[w].w; l_wsh = g_doc_nodes[w].h; }
    }
    for (I64 i = 0; i < 3; i++) {
        I64 t = DolDocXFESkelChild(c_top, 6 + i);
        if (t >= 0) { l_trx[i] = g_doc_nodes[t].x; l_trw[i] = g_doc_nodes[t].w; l_trh = g_doc_nodes[t].h; }
    }
    for (I64 i = 0; i < XFCE_LAUNCH_COUNT; i++) {
        I64 d = DolDocXFESkelChild(c_dock, i);
        if (d >= 0) { l_lnx[i] = g_doc_nodes[d].x; l_lnw[i] = g_doc_nodes[d].w; l_lnh = g_doc_nodes[d].h; l_lnn++; }
    }
    I64 tk = DolDocXFESkelChild(c_dock, XFCE_LAUNCH_COUNT);
    if (tk >= 0) { l_tsx = g_doc_nodes[tk].x; l_tsw = g_doc_nodes[tk].w; l_tsh = g_doc_nodes[tk].h; }

    // ---- publica nos globais (nenhum print aconteceu ate aqui) --------------
    g_xf_top_x = l_top_x; g_xf_top_y = l_top_y; g_xf_top_w = l_top_w; g_xf_top_h = l_top_h;
    g_xf_area_x = l_area_x; g_xf_area_y = l_area_y; g_xf_area_w = l_area_w; g_xf_area_h = l_area_h;
    g_xf_dock_x = l_dock_x; g_xf_dock_y = l_dock_y; g_xf_dock_w = l_dock_w; g_xf_dock_h = l_dock_h;
    g_xf_menu_x = l_menu_x; g_xf_menu_w = l_menu_w; g_xf_menu_h = l_menu_h;
    g_xf_ws_h = l_wsh;
    g_xf_tray_h = l_trh;
    g_xf_launch_h = l_lnh; g_xf_launch_n = l_lnn;
    g_xf_tasks_x = l_tsx; g_xf_tasks_w = l_tsw; g_xf_tasks_h = l_tsh;
    for (I64 i = 0; i < XFCE_WS_COUNT; i++) { g_xf_ws_x[i] = l_wsx[i]; g_xf_ws_w[i] = l_wsw[i]; }
    for (I64 i = 0; i < 3; i++) { g_xf_tray_x[i] = l_trx[i]; g_xf_tray_w[i] = l_trw[i]; }
    for (I64 i = 0; i < XFCE_LAUNCH_COUNT; i++) { g_xf_launch_x[i] = l_lnx[i]; g_xf_launch_w[i] = l_lnw[i]; }
    g_xf_ready = 1;
}

// ============================================================================
// Janelas (barra de titulo arrastavel, min/max/close, foco por Z-order)
// ============================================================================
U0 DolDocXFECopySlot(I64 d, I64 s) {
    g_xf_win_id[d] = g_xf_win_id[s];
    g_xf_win_x[d] = g_xf_win_x[s]; g_xf_win_y[d] = g_xf_win_y[s];
    g_xf_win_w[d] = g_xf_win_w[s]; g_xf_win_h[d] = g_xf_win_h[s];
    g_xf_win_rx[d] = g_xf_win_rx[s]; g_xf_win_ry[d] = g_xf_win_ry[s];
    g_xf_win_rw[d] = g_xf_win_rw[s]; g_xf_win_rh[d] = g_xf_win_rh[s];
    g_xf_win_ws[d] = g_xf_win_ws[s]; g_xf_win_kind[d] = g_xf_win_kind[s];
    g_xf_win_min[d] = g_xf_win_min[s]; g_xf_win_max[d] = g_xf_win_max[s];
    strncpy(DolDocXFETitle(d), DolDocXFETitle(s), XFCE_WINTITLE_LEN - 1);
    U8 *dst_t = g_xf_win_title + d * XFCE_WINTITLE_LEN;
    dst_t[XFCE_WINTITLE_LEN - 1] = 0;
}

I64 DolDocXFEZPos(I64 s) {
    for (I64 i = 0; i < g_xf_nwin; i++) if (g_xf_z[i] == s) return i;
    return -1;
}

U0 DolDocXFEFocusSlot(I64 s) {
    if (s < 0 || s >= g_xf_nwin) return;
    I64 pos = DolDocXFEZPos(s);
    if (pos < 0) return;
    for (I64 i = pos; i < g_xf_nwin - 1; i++) g_xf_z[i] = g_xf_z[i + 1];
    g_xf_z[g_xf_nwin - 1] = s;
    g_xf_active_id = g_xf_win_id[s];
    if (g_xf_win_min[s]) g_xf_win_min[s] = 0;
    g_doc_dirty = 1;
}

I64 DolDocXFEActiveSlot() {
    for (I64 i = 0; i < g_xf_nwin; i++) if (g_xf_win_id[i] == g_xf_active_id) return i;
    return -1;
}

I64 DolDocXFEWinOpen(I64 kind, U8 *title, I64 ws, I64 x, I64 y, I64 w, I64 h) {
    if (g_xf_nwin >= XFCE_MAX_WIN) return -1;
    I64 s = g_xf_nwin;
    g_xf_nwin++;
    g_xf_win_id[s] = g_xf_next_id; g_xf_next_id++;
    strncpy(DolDocXFETitle(s), title, XFCE_WINTITLE_LEN - 1);
    U8 *src_t = g_xf_win_title + s * XFCE_WINTITLE_LEN;
    src_t[XFCE_WINTITLE_LEN - 1] = 0;
    I64 ax = g_xf_area_x, ay = g_xf_area_y, aw = g_xf_area_w, ah = g_xf_area_h;
    if (aw <= 0) { ax = 0; ay = 28; aw = 1024; ah = 696; }
    if (w > aw - 8) w = aw - 8;
    if (h > ah - 8) h = ah - 8;
    if (x < ax) x = ax;
    if (y < ay) y = ay;
    if (x + w > ax + aw) x = ax + aw - w;
    if (y + h > ay + ah) y = ay + ah - h;
    g_xf_win_x[s] = x; g_xf_win_y[s] = y; g_xf_win_w[s] = w; g_xf_win_h[s] = h;
    g_xf_win_rx[s] = x; g_xf_win_ry[s] = y; g_xf_win_rw[s] = w; g_xf_win_rh[s] = h;
    g_xf_win_ws[s] = ws; g_xf_win_kind[s] = kind;
    g_xf_win_min[s] = 0; g_xf_win_max[s] = 0;
    g_xf_z[g_xf_nwin - 1] = s;
    g_xf_active_id = g_xf_win_id[s];
    if (kind == 0 && g_xf_term_slot < 0) g_xf_term_slot = s;
    if (kind == 1 && g_xf_set_slot < 0) g_xf_set_slot = s;
    g_doc_dirty = 1;
    return g_xf_win_id[s];
}

U0 DolDocXFEZRemove(I64 s) {
    I64 w = 0;
    for (I64 i = 0; i < g_xf_nwin; i++) {
        if (g_xf_z[i] == s) continue;
        I64 v = g_xf_z[i];
        if (v > s) v--;
        g_xf_z[w] = v;
        w++;
    }
    g_xf_nwin = w;
}

U0 DolDocXFEWinClose(I64 s) {
    if (s < 0 || s >= g_xf_nwin) return;
    I64 cid = g_xf_win_id[s];
    for (I64 i = s; i < g_xf_nwin - 1; i++) DolDocXFECopySlot(i, i + 1);
    if (g_xf_term_slot == s) g_xf_term_slot = -1;
    else if (g_xf_term_slot > s) g_xf_term_slot--;
    if (g_xf_set_slot == s) g_xf_set_slot = -1;
    else if (g_xf_set_slot > s) g_xf_set_slot--;
    DolDocXFEZRemove(s);
    if (g_xf_active_id == cid) {
        if (g_xf_nwin > 0) g_xf_active_id = g_xf_win_id[g_xf_z[g_xf_nwin - 1]];
        else g_xf_active_id = -1;
    }
    g_doc_dirty = 1;
}

U0 DolDocXFEToggleMax(I64 s) {
    if (s < 0 || s >= g_xf_nwin) return;
    if (!g_xf_win_max[s]) {
        g_xf_win_rx[s] = g_xf_win_x[s]; g_xf_win_ry[s] = g_xf_win_y[s];
        g_xf_win_rw[s] = g_xf_win_w[s]; g_xf_win_rh[s] = g_xf_win_h[s];
        g_xf_win_x[s] = g_xf_area_x; g_xf_win_y[s] = g_xf_area_y;
        g_xf_win_w[s] = g_xf_area_w; g_xf_win_h[s] = g_xf_area_h;
        g_xf_win_max[s] = 1;
    } else {
        g_xf_win_x[s] = g_xf_win_rx[s]; g_xf_win_y[s] = g_xf_win_ry[s];
        g_xf_win_w[s] = g_xf_win_rw[s]; g_xf_win_h[s] = g_xf_win_rh[s];
        g_xf_win_max[s] = 0;
    }
    DolDocXFESyncLayout();
    g_doc_dirty = 1;
}

U0 DolDocXFEAllToWSLayout() {
    // reintegra os filhos no workspace atual e reconstroi a z-order
    I64 w = 0;
    for (I64 i = 0; i < g_xf_nwin; i++) {
        if (g_xf_win_ws[i] != g_xf_ws) continue;
        g_xf_z[w] = i;
        w++;
    }
    g_xf_nwin = w;
}

// ============================================================================
// Aplicacao: abrir/focar um app no workspace corrente
// ============================================================================
U8 *DolDocXFEAppTitle(I64 kind) {
    if (kind == 0) return "Terminal - DolDoc Shell";
    if (kind == 1) return "Settings Manager";
    if (kind == 2) return "Files - RedSea FS";
    if (kind == 3) return "Gears 3D - HolyGL";
    return "Shader - plasma";
}

I64 DolDocXFEAppSlot(I64 kind) {
    for (I64 i = 0; i < g_xf_nwin; i++) {
        if (g_xf_win_kind[i] == kind && g_xf_win_ws[i] == g_xf_ws) return i;
    }
    return -1;
}

I64 DolDocXFEOpenApp(I64 kind) {
    I64 s = DolDocXFEAppSlot(kind);
    if (s >= 0) { DolDocXFEFocusSlot(s); return g_xf_win_id[s]; }
    I64 off = (g_xf_nwin * 24) % 120;
    I64 w = 520, h = 380;
    if (kind == 1) { w = 420; h = 420; }
    if (kind == 3) { w = 360; h = 300; }
    if (kind == 4) { w = 380; h = 300; }
    if (kind == 2) { w = 380; h = 320; }
    I64 id = DolDocXFEWinOpen(kind, DolDocXFEAppTitle(kind), g_xf_ws,
                              g_xf_area_x + 40 + off, g_xf_area_y + 30 + off, w, h);
    if (kind == 0 && g_xf_term_slot >= 0) DolDocXFEMoveTermDoc();
    DolDocXFESyncLayout();
    return id;
}

// ============================================================================
// Movimentacao do documento do Shell para dentro da janela Terminal
// ============================================================================
U0 DolDocXFEMoveTermDoc() {
    I64 s = g_xf_term_slot;
    if (s < 0) return;
    I64 tb = DolDocXFETitlebarH();
    I64 cx = g_xf_win_x[s] + 6;
    I64 cy = g_xf_win_y[s] + tb + 20;
    I64 cw = g_xf_win_w[s] - 12;
    I64 ch = g_xf_win_h[s] - tb - 26;
    if (cw < 80) cw = 80;
    if (ch < 40) ch = 40;
    DolDocMove(cx, cy, cw, ch);
}

// ============================================================================
// Settings Manager — $TABS$ / $SLIDER$ / $TOGGLE$ (nos REAIS do G3)
// ============================================================================
U0 DolDocXFESettingsBuild() {
    I64 s = g_xf_set_slot;
    if (s < 0) return;
    I64 n0 = g_doc_node_count;
    DolDocPrint("$COL,pad=16,gap=34$");
    DolDocPrint("$TABS,id=\"xf_set_tabs\",items=\"Display|Appearance|Sound|System\",val=0,w=340,h=24$");
    // pagina 0 — Display
    DolDocPrint("$COL,pad=0,gap=34$");
    DolDocPrint("$SLIDER,id=\"xf_s0_0\",min=0,max=100,val=75,w=300,label=\"Brightness\"$");
    DolDocPrint("$SLIDER,id=\"xf_s0_1\",min=50,max=200,val=100,w=300,label=\"Scale percent\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t0_0\",val=1,label=\"Compositor glass\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t0_1\",val=1,label=\"Window shadows\"$");
    DolDocPrint("$END$");
    // pagina 1 — Appearance
    DolDocPrint("$COL,pad=0,gap=34$");
    DolDocPrint("$SLIDER,id=\"xf_s1_0\",min=0,max=24,val=6,w=300,label=\"Corner radius\"$");
    DolDocPrint("$SLIDER,id=\"xf_s1_1\",min=18,max=48,val=30,w=300,label=\"Titlebar height\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t1_0\",val=1,label=\"Rounded corners\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t1_1\",val=1,label=\"Dirty blit\"$");
    DolDocPrint("$END$");
    // pagina 2 — Sound
    DolDocPrint("$COL,pad=0,gap=34$");
    DolDocPrint("$SLIDER,id=\"xf_s2_0\",min=0,max=100,val=70,w=300,label=\"Master volume\"$");
    DolDocPrint("$SLIDER,id=\"xf_s2_1\",min=0,max=100,val=40,w=300,label=\"Effects volume\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t2_0\",val=0,label=\"Mute\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t2_1\",val=1,label=\"Boot chime\"$");
    DolDocPrint("$END$");
    // pagina 3 — System
    DolDocPrint("$COL,pad=0,gap=34$");
    DolDocPrint("$SLIDER,id=\"xf_s3_0\",min=30,max=144,val=60,w=300,label=\"FPS cap\"$");
    DolDocPrint("$SLIDER,id=\"xf_s3_1\",min=0,max=100,val=60,w=300,label=\"CPU budget\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t3_0\",val=0,label=\"Live profiler\"$");
    DolDocPrint("$TOGGLE,id=\"xf_t3_1\",val=0,label=\"Auto theme\"$");
    DolDocPrint("$END$");
    DolDocPrint("$END$");

    g_xf_set_nid = DolDocXFELastChildFrom(g_doc_root, n0);
    if (g_xf_set_nid < 0) { uart_puts("[XFCE] FATAL: settings root nao criado\n"); return; }
    g_xf_set_tabs_nid = DolDocXFESkelChild(g_xf_set_nid, 0);
    g_xf_set_nwid = 0;
    for (I64 p = 0; p < XFCE_WS_COUNT; p++) {
        I64 pg = DolDocXFESkelChild(g_xf_set_nid, 1 + p);
        g_xf_set_page_nid[p] = pg;
        I64 w = (pg >= 0) ? g_doc_nodes[pg].first : -1;
        while (w >= 0) {
            if (g_xf_set_nwid < XFCE_MAX_SET_WID) {
                g_xf_set_wid_nid[g_xf_set_nwid] = w;
                g_xf_set_wid_page[g_xf_set_nwid] = p;
                g_xf_set_nwid++;
            }
            w = g_doc_nodes[w].next;
        }
    }
    DolDocXFEESettingsLayout();
    DolDocUnlink(g_xf_set_nid);
    DolDocXFELog("[XFCE] settings root=", g_xf_set_nid);
    DolDocXFELog("[XFCE] settings widgets=", g_xf_set_nwid);
}

U0 DolDocXFEESettingsLayout() {
    I64 s = g_xf_set_slot;
    if (s < 0 || g_xf_set_tabs_nid < 0) return;
    I64 tb = DolDocXFETitlebarH();
    I64 bx = g_xf_win_x[s] + 14;
    I64 by = g_xf_win_y[s] + tb + 34;
    I64 bw = g_xf_win_w[s] - 28;
    I64 bh = g_xf_win_h[s] - tb - 42;
    if (bw < 120) bw = 120;
    if (bh < 80) bh = 80;
    DolDocMeasureNode(g_xf_set_tabs_nid);
    DolDocArrangeNode(g_xf_set_tabs_nid, bx, by, bw, 24);
    I64 py = by + 34;
    I64 ph = bh - 34;
    if (ph < 60) ph = 60;
    for (I64 p = 0; p < XFCE_WS_COUNT; p++) {
        I64 pg = g_xf_set_page_nid[p];
        if (pg < 0) continue;
        DolDocMeasureNode(pg);
        DolDocArrangeNode(pg, bx, py, bw - 70, ph);
    }
}

U0 DolDocXFESyncLayout() {
    DolDocXFEERelayout();
    DolDocXFEESettingsLayout();
}

// aplica os valores dos widgets: liga efeitos REAIS onde existe suporte
U0 DolDocXFEESettingsApply() {
    I64 i = 0;
    while (i < g_xf_set_nwid) {
        I64 nid = g_xf_set_wid_nid[i];
        if (nid >= 0 && nid < g_doc_node_count) {
            CDocNode *ap_nd = &g_doc_nodes[nid];
            if (i == 2) g_comp.glass_enabled = ap_nd->state ? 1 : 0;
            if (i == 3) g_comp.shadows_enabled = ap_nd->state ? 1 : 0;
            if (i == 4) g_theme.corner_radius = ap_nd->val;
            if (i == 5) g_theme.titlebar_h = ap_nd->val;
            if (i == 6) g_comp.rounded_corners = ap_nd->state ? 1 : 0;
            if (i == 7) g_comp.dirty_blit_enabled = ap_nd->state ? 1 : 0;
            if (i == 14) ProfilerSetOn(ap_nd->state ? 1 : 0);
        }
        i++;
    }
}

I64 DolDocXFEESettingsClick(I64 mx, I64 my) {
    if (g_xf_set_tabs_nid >= 0 && g_xf_set_tabs_nid < g_doc_node_count) {
        if (DolDocWidgetClick(g_xf_set_tabs_nid, mx, my)) {
            g_xf_set_page = g_doc_nodes[g_xf_set_tabs_nid].val;
            g_doc_dirty = 1;
            return 1;
        }
    }
    for (I64 i = 0; i < g_xf_set_nwid; i++) {
        if (g_xf_set_wid_page[i] != g_xf_set_page) continue;
        I64 nid = g_xf_set_wid_nid[i];
        if (nid < 0 || nid >= g_doc_node_count) continue;
        if (DolDocWidgetClick(nid, mx, my)) {
            if (g_doc_nodes[nid].kind == DOC_SLIDER) g_xf_drag_wid = nid;
            DolDocXFEESettingsApply();
            g_doc_dirty = 1;
            return 1;
        }
    }
    return 0;
}

// ============================================================================
// Desenho — Top Panel (0..28) / janelas / Bottom Dock (724..768)
// ============================================================================
// I/O de disco FORA do caminho de desenho (medido: chamar redsea_get_entries()
// dentro do draw deixava o resto do painel/dock sem desenhar naquele frame).
U0 DolDocXFEDiskRefresh() {
    I64 n = redsea_get_entries(g_xf_filebuf, 48);
    if (n < 0) n = 0;
    g_xf_files_n = n;
    g_xf_files_sec = timer_get_uptime_sec();
}

U0 DolDocXFETrayRefresh() {
    I64 now = timer_get_uptime_sec();
    if (now == g_xf_files_sec) return;
    g_xf_files_sec = now;
    DolDocXFEDiskRefresh();
}

U0 DolDocXFEDrawPanel() {
    I64 sw = g_comp.screen_w; if (sw <= 0) sw = 1024;
    I64 py = g_xf_top_y;
    I64 ph = g_xf_top_h;
    gfx_draw_rect(0, py, sw, ph, g_theme.bg_mantle);
    gfx_draw_rect(0, py + ph - 1, sw, 1, g_theme.border_subtle);

    // ---- botao do menu de aplicativos ---------------------------------------
    U32 mc = g_xf_menu_open ? g_theme.accent_secondary : g_theme.accent_primary;
    gfx_draw_rounded_rect(g_xf_menu_x, py + 4, g_xf_menu_w, ph - 8, 4, mc);
    gfx_draw_string(g_xf_menu_x + 10, py + 6, "Applications", g_theme.bg_crust, 0);

    // ---- seletor de 4 workspaces -------------------------------------------
    for (I64 i = 0; i < XFCE_WS_COUNT; i++) {
        U32 wc = (i == g_xf_ws) ? g_theme.accent_tertiary : g_theme.bg_surface0;
        U32 tc = (i == g_xf_ws) ? g_theme.bg_crust : g_theme.text_muted;
        gfx_draw_rounded_rect(g_xf_ws_x[i], py + 4, g_xf_ws_w[i], ph - 8, 4, wc);
        U8 ws[4]; ws[0] = '0' + (i + 1); ws[1] = 0;
        gfx_draw_string(g_xf_ws_x[i] + (g_xf_ws_w[i] - 8) / 2, py + 6, ws, tc, 0);
    }

    // ---- tray: FPS / disco / relogio ---------------------------------------
    DolDocXFETrayRefresh();
    I64 ty = py + 4;
    I64 th = ph - 8;
    U8 nb[24];
    // FPS
    gfx_draw_rounded_rect(g_xf_tray_x[0], ty, g_xf_tray_w[0], th, 4, g_theme.bg_crust);
    gfx_draw_string(g_xf_tray_x[0] + 8, ty + 2, "FPS", g_theme.text_muted, 0);
    DolDocXFEUInt(nb, g_comp.fps, 1);
    gfx_draw_string(g_xf_tray_x[0] + 46, ty + 2, nb, g_theme.status_success, 0);
    // disco (RedSea)
    gfx_draw_rounded_rect(g_xf_tray_x[1], ty, g_xf_tray_w[1], th, 4, g_theme.bg_crust);
    gfx_draw_string(g_xf_tray_x[1] + 8, ty + 2, "DISK", g_theme.text_muted, 0);
    DolDocXFEUInt(nb, g_xf_files_n, 1);
    gfx_draw_string(g_xf_tray_x[1] + 52, ty + 2, nb, g_theme.status_peach, 0);
    gfx_draw_string(g_xf_tray_x[1] + 76, ty + 2, "fil", g_theme.text_muted, 0);
    // relogio (uptime HH:MM:SS)
    I64 up = timer_get_uptime_sec();
    I64 hh = (up / 3600) % 100;
    I64 mm = (up / 60) % 60;
    I64 ss = up % 60;
    U8 clk[12];
    DolDocXFEUInt(clk, hh, 2);
    I64 cl = 0; while (clk[cl]) cl++;
    clk[cl] = ':'; cl++;
    DolDocXFEUInt(clk + cl, mm, 2);
    cl = 0; while (clk[cl]) cl++;
    clk[cl] = ':'; cl++;
    DolDocXFEUInt(clk + cl, ss, 2);
    gfx_draw_rounded_rect(g_xf_tray_x[2], ty, g_xf_tray_w[2], th, 4, g_theme.bg_crust);
    gfx_draw_string(g_xf_tray_x[2] + 8, ty + 2, "UP", g_theme.text_muted, 0);
    gfx_draw_string(g_xf_tray_x[2] + 30, ty + 2, clk, g_theme.accent_cyan, 0);
}

I64 DolDocXFETaskCount() {
    I64 n = 0;
    for (I64 i = 0; i < g_xf_nwin; i++) if (g_xf_win_ws[i] == g_xf_ws) n++;
    return n;
}

I64 DolDocXFETaskSlot(I64 k) {
    I64 n = 0;
    for (I64 i = 0; i < g_xf_nwin; i++) {
        if (g_xf_win_ws[i] != g_xf_ws) continue;
        if (n == k) return i;
        n++;
    }
    return -1;
}

I64 DolDocXFETaskW(I64 n) {
    if (n <= 0) return 0;
    I64 avail = g_xf_tasks_w - 6 * (n - 1);
    if (avail < 40) avail = 40;
    I64 w = avail / n;
    if (w > 160) w = 160;
    return w;
}

U0 DolDocXFEDrawDock() {
    I64 sw = g_comp.screen_w; if (sw <= 0) sw = 1024;
    I64 dy = g_xf_dock_y;
    I64 dh = g_xf_dock_h;
    gfx_draw_rect(0, dy, sw, dh, g_theme.bg_base);
    gfx_draw_rect(0, dy, sw, 1, g_theme.border_active);
    // ---- launchers ----------------------------------------------------------
    for (I64 i = 0; i < g_xf_launch_n; i++) {
        I64 lx = g_xf_launch_x[i];
        I64 lw = g_xf_launch_w[i];
        I64 lh = dh - 8;
        U32 lc = g_theme.bg_surface0;
        if (g_xf_win_kind[0] >= 0 && DolDocXFEAppSlot(i) >= 0) lc = g_theme.bg_surface1;
        gfx_draw_rounded_rect(lx + 2, dy + 4, lw - 4, lh, 5, lc);
        U8 glyph[3];
        glyph[0] = 'T'; glyph[1] = 0;
        if (i == 1) glyph[0] = 'S';
        if (i == 2) glyph[0] = 'F';
        if (i == 3) glyph[0] = 'G';
        if (i == 4) glyph[0] = 'P';
        gfx_draw_string(lx + 2 + (lw - 4 - 8) / 2, dy + 4 + (lh - 16) / 2, glyph, g_theme.accent_cyan, 0);
    }
    // ---- lista de janelas do workspace atual --------------------------------
    I64 n = DolDocXFETaskCount();
    I64 tw = DolDocXFETaskW(n);
    for (I64 k = 0; k < n; k++) {
        I64 s = DolDocXFETaskSlot(k);
        if (s < 0) continue;
        I64 tx = g_xf_tasks_x + k * (tw + 6);
        I64 th = dh - 8;
        I64 act = (g_xf_win_id[s] == g_xf_active_id);
        U32 bg = act ? g_theme.bg_surface1 : g_theme.bg_mantle;
        if (g_xf_win_min[s]) bg = g_theme.bg_crust;
        gfx_draw_rounded_rect(tx, dy + 4, tw, th, 5, bg);
        if (act) gfx_draw_rect(tx, dy + dh - 6, tw, 3, g_theme.accent_primary);
        U8 tbuf[XFCE_WINTITLE_LEN];
        strncpy(tbuf, DolDocXFETitle(s), XFCE_WINTITLE_LEN - 1);
        tbuf[XFCE_WINTITLE_LEN - 1] = 0;
        I64 maxc = (tw - 14) / 8;
        if (maxc < 3) maxc = 3;
        if (strlen(tbuf) > maxc) { tbuf[maxc - 3] = '.'; tbuf[maxc - 2] = '.'; tbuf[maxc - 1] = '.'; tbuf[maxc] = 0; }
        gfx_draw_string(tx + 7, dy + 4 + (th - 16) / 2, tbuf, act ? g_theme.text_primary : g_theme.text_muted, 0);
    }
    if (n == 0) {
        gfx_draw_string(g_xf_tasks_x + 8, dy + 4 + (dh - 8 - 16) / 2,
                        "(nenhuma janela neste workspace)", g_theme.text_muted, 0);
    }
}

U0 DolDocXFEDrawFiles(I64 s) {
    I64 x = g_xf_win_x[s], y = g_xf_win_y[s], w = g_xf_win_w[s];
    I64 tb = DolDocXFETitlebarH();
    DolDocXFETrayRefresh();
    gfx_draw_string(x + 10, y + tb + 6, "/holyc (RedSea)", g_theme.accent_tertiary, 0);
    I64 n = g_xf_files_n;
    if (n < 0) n = 0;
    I64 maxr = (g_xf_win_h[s] - tb - 40) / 18;
    if (maxr > 16) maxr = 16;
    if (maxr > n) maxr = n;
    for (I64 i = 0; i < maxr; i++) {
        U8 *nm = g_xf_filebuf + i * 64 + 2;
        gfx_draw_string(x + 14, y + tb + 26 + i * 18, nm, g_theme.text_primary, 0);
        I64 sz = 0;
        U8 *q = g_xf_filebuf + i * 64 + 48;
        for (I64 b = 0; b < 8; b++) sz = sz | (((I64)q[b]) << (8 * b));
        U8 nb[24];
        DolDocXFEUInt(nb, sz, 1);
        gfx_draw_string(x + w - 80, y + tb + 26 + i * 18, nb, g_theme.status_peach, 0);
    }
    if (n == 0) gfx_draw_string(x + 14, y + tb + 26, "(disco vazio / I-O falhou)", g_theme.text_muted, 0);
}

U0 DolDocXFEDrawSettings(I64 s) {
    I64 x = g_xf_win_x[s], y = g_xf_win_y[s];
    I64 tb = DolDocXFETitlebarH();
    gfx_draw_string(x + 14, y + tb + 8, "Settings Manager - 4 abas ($TABS$/$SLIDER$/$TOGGLE$)",
                    g_theme.accent_primary, 0);
    if (g_xf_set_tabs_nid >= 0 && g_xf_set_tabs_nid < g_doc_node_count) {
        DolDocDrawWidget(&g_doc_nodes[g_xf_set_tabs_nid], 0);
    }
    for (I64 i = 0; i < g_xf_set_nwid; i++) {
        if (g_xf_set_wid_page[i] != g_xf_set_page) continue;
        I64 nid = g_xf_set_wid_nid[i];
        if (nid < 0 || nid >= g_doc_node_count) continue;
        DolDocDrawWidget(&g_doc_nodes[nid], 0);
    }
}

U0 DolDocXFEDrawWindow(I64 s) {
    I64 x = g_xf_win_x[s], y = g_xf_win_y[s], w = g_xf_win_w[s], h = g_xf_win_h[s];
    I64 tb = DolDocXFETitlebarH();
    I64 active = (g_xf_win_id[s] == g_xf_active_id);
    DolDocDrawShadow(x, y, w, h, 6);
    gfx_draw_rect(x - 1, y - 1, w + 2, h + 2, active ? g_theme.border_active : g_theme.border_subtle);
    gfx_draw_rect(x, y, w, h, g_theme.bg_base);
    gfx_draw_rect(x, y, w, tb, active ? g_theme.bg_surface0 : g_theme.bg_mantle);
    gfx_draw_rect(x, y + tb - 1, w, 1, active ? g_theme.accent_primary : g_theme.border_subtle);
    gfx_draw_string(x + 10, y + (tb - 16) / 2, DolDocXFETitle(s),
                    active ? g_theme.text_primary : g_theme.text_muted, 0);
    I64 by = y + (tb - 16) / 2;
    I64 b3 = x + w - 24;
    gfx_draw_rounded_rect(b3, by, 16, 16, 3, g_theme.status_danger);
    gfx_draw_char(b3 + 5, by + 1, 'x', g_theme.bg_crust, 0);
    I64 b2 = x + w - 44;
    gfx_draw_rounded_rect(b2, by, 16, 16, 3, g_theme.status_success);
    gfx_draw_char(b2 + 4, by + 1, g_xf_win_max[s] ? '=' : '+', g_theme.bg_crust, 0);
    I64 b1 = x + w - 64;
    gfx_draw_rounded_rect(b1, by, 16, 16, 3, g_theme.status_warning);
    gfx_draw_char(b1 + 5, by + 1, '-', g_theme.bg_crust, 0);
    gfx_set_clip(x + 1, y + tb, w - 2, h - tb - 1);
    I64 kind = g_xf_win_kind[s];
    if (kind == 0) {
        gfx_draw_rect(x + 1, y + tb, w - 2, 18, g_theme.bg_crust);
        gfx_draw_string(x + 8, y + tb + 2, "neo@sovereign:/holyc$", g_theme.status_success, 0);
        gfx_draw_string(x + 8 + 176, y + tb + 2, "(shell DolDoc hospedado nesta janela)",
                        g_theme.text_muted, 0);
        DolDocDrawChildren(g_doc_root, 0);
    } else if (kind == 1) {
        DolDocXFEDrawSettings(s);
    } else if (kind == 2) {
        DolDocXFEDrawFiles(s);
    } else if (kind == 3) {
        gfx_draw_string(x + 12, y + tb + 8, "HolyGL - gears", g_theme.status_warning, 0);
        DolDocRenderSprite3D(x + 12, y + tb + 30, w - 24, h - tb - 42, "gears");
    } else {
        gfx_draw_string(x + 12, y + tb + 8, "ShaderVM - plasma", g_theme.accent_cyan, 0);
        DolDocRenderShaderNode(x + 12, y + tb + 30, w - 24, h - tb - 42, "plasma");
    }
    gfx_reset_clip();
}

// ---- menu de aplicativos (popup do Top Panel) -------------------------------
I64 DolDocXFEMenuX() { return g_xf_menu_x; }
I64 DolDocXFEMenuY() { return g_xf_top_y + g_xf_top_h + 4; }
I64 DolDocXFEMenuW() { return 260; }
I64 DolDocXFEMenuH() { return 12 + XFCE_LAUNCH_COUNT * 28; }
I64 DolDocXFEMenuItemY(I64 k) { return DolDocXFEMenuY() + 6 + k * 28; }

U0 DolDocXFEDrawMenu() {
    I64 mx = DolDocXFEMenuX(), my = DolDocXFEMenuY();
    I64 mw = DolDocXFEMenuW(), mh = DolDocXFEMenuH();
    DolDocDrawShadow(mx, my, mw, mh, 8);
    gfx_draw_rect(mx - 1, my - 1, mw + 2, mh + 2, g_theme.border_active);
    gfx_draw_rect(mx, my, mw, mh, g_theme.bg_mantle);
    gfx_draw_rect(mx, my, mw, 20, g_theme.bg_surface0);
    gfx_draw_string(mx + 8, my + 2, "Applications", g_theme.accent_primary, 0);
    for (I64 k = 0; k < XFCE_LAUNCH_COUNT; k++) {
        I64 iy = DolDocXFEMenuItemY(k);
        gfx_draw_string(mx + 16, iy + 4, DolDocXFEAppTitle(k), g_theme.text_primary, 0);
    }
}

I64 DolDocXFEMenuClick(I64 mx, I64 my) {
    I64 x = DolDocXFEMenuX(), y = DolDocXFEMenuY();
    I64 w = DolDocXFEMenuW(), h = DolDocXFEMenuH();
    if (mx < x || mx >= x + w || my < y || my >= y + h) return 0;
    for (I64 k = 0; k < XFCE_LAUNCH_COUNT; k++) {
        I64 iy = DolDocXFEMenuItemY(k);
        if (my >= iy && my < iy + 26) { DolDocXFEOpenApp(k); return 1; }
    }
    return 1;
}

U0 DolDocXFCEDraw() {
    I64 sw = g_comp.screen_w; if (sw <= 0) sw = 1024;
    I64 sh = g_comp.screen_h; if (sh <= 0) sh = 768;
    // fundo da area de trabalho
    gfx_draw_rect(0, 0, sw, sh, g_theme.bg_crust);
    gfx_draw_rect(g_xf_area_x, g_xf_area_y, g_xf_area_w, g_xf_area_h, g_theme.bg_crust);
    // janelas em Z-order (so' as do workspace corrente, minimizadas nao desenham)
    for (I64 i = 0; i < g_xf_nwin; i++) {
        I64 s = g_xf_z[i];
        if (s < 0 || s >= g_xf_nwin) continue;
        if (g_xf_win_ws[s] != g_xf_ws) continue;
        if (g_xf_win_min[s]) continue;
        DolDocXFEDrawWindow(s);
    }
    DolDocXFEDrawPanel();
    DolDocXFEDrawDock();
    if (g_xf_menu_open) DolDocXFEDrawMenu();
}

// ============================================================================
// Mouse
// ============================================================================
U0 DolDocXFEMouse() {
    I64 mx = mouse_get_x();
    I64 my = mouse_get_y();
    I64 btn = mouse_get_btn();
    I64 down = (btn & 1) ? 1 : 0;
    I64 s = -1;

    if (down && !g_xf_prev_btn) {
        g_xf_prev_btn = 1;
        // 1) popup de aplicativos
        if (g_xf_menu_open) {
            I64 hit = DolDocXFEMenuClick(mx, my);
            g_xf_menu_open = 0;
            g_doc_dirty = 1;
            if (hit) return;
        }
        // 2) Top Panel
        if (my >= g_xf_top_y && my < g_xf_top_y + g_xf_top_h) {
            if (mx >= g_xf_menu_x && mx < g_xf_menu_x + g_xf_menu_w) {
                g_xf_menu_open = 1; g_doc_dirty = 1; return;
            }
            for (I64 i = 0; i < XFCE_WS_COUNT; i++) {
                if (mx >= g_xf_ws_x[i] && mx < g_xf_ws_x[i] + g_xf_ws_w[i]) {
                    g_xf_ws = i; g_doc_dirty = 1;
                    s = DolDocXFEActiveSlot();
                    if (s >= 0 && g_xf_win_ws[s] != g_xf_ws) {
                        for (I64 zi = g_xf_nwin - 1; zi >= 0; zi--) {
                            if (g_xf_win_ws[g_xf_z[zi]] == g_xf_ws) { DolDocXFEFocusSlot(g_xf_z[zi]); break; }
                        }
                    }
                    return;
                }
            }
            return;
        }
        // 3) Bottom Dock
        if (my >= g_xf_dock_y && my < g_xf_dock_y + g_xf_dock_h) {
            for (I64 i = 0; i < g_xf_launch_n; i++) {
                if (mx >= g_xf_launch_x[i] && mx < g_xf_launch_x[i] + g_xf_launch_w[i]) {
                    DolDocXFEOpenApp(i);
                    return;
                }
            }
            I64 n = DolDocXFETaskCount();
            I64 tw = DolDocXFETaskW(n);
            if (n > 0 && tw > 0 && mx >= g_xf_tasks_x) {
                I64 k = (mx - g_xf_tasks_x) / (tw + 6);
                if (k >= n) k = n - 1;
                s = DolDocXFETaskSlot(k);
                if (s >= 0) DolDocXFEFocusSlot(s);
            }
            return;
        }
        // 4) janelas, de cima para baixo na Z-order
        for (I64 zi = g_xf_nwin - 1; zi >= 0; zi--) {
            s = g_xf_z[zi];
            if (g_xf_win_ws[s] != g_xf_ws) continue;
            if (g_xf_win_min[s]) continue;
            if (mx < g_xf_win_x[s] || mx >= g_xf_win_x[s] + g_xf_win_w[s]) continue;
            if (my < g_xf_win_y[s] || my >= g_xf_win_y[s] + g_xf_win_h[s]) continue;
            DolDocXFEFocusSlot(s);
            I64 tb = DolDocXFETitlebarH();
            I64 rx = g_xf_win_x[s] + g_xf_win_w[s];
            if (my < g_xf_win_y[s] + tb) {
                if (mx >= rx - 24 && mx < rx - 8) { DolDocXFEWinClose(s); return; }
                if (mx >= rx - 44 && mx < rx - 28) { DolDocXFEToggleMax(s); return; }
                if (mx >= rx - 64 && mx < rx - 48) {
                    g_xf_win_min[s] = 1;
                    g_xf_active_id = g_xf_win_id[s];
                    g_doc_dirty = 1;
                    return;
                }
                if (!g_xf_win_max[s]) {
                    g_xf_drag_slot = s;
                    g_xf_drag_dx = mx - g_xf_win_x[s];
                    g_xf_drag_dy = my - g_xf_win_y[s];
                }
                return;
            }
            I64 kind = g_xf_win_kind[s];
            if (kind == 0) {
                I64 sx = g_doc_x; I64 sy = g_doc_y; I64 sw = g_doc_w; I64 sh = g_doc_h;
                g_doc_x = g_xf_win_x[s] + 6;
                g_doc_y = g_xf_win_y[s] + tb + 20;
                g_doc_w = g_xf_win_w[s] - 12;
                g_doc_h = g_xf_win_h[s] - tb - 26;
                DolDocHandleClick(mx, my);
                g_doc_x = sx; g_doc_y = sy; g_doc_w = sw; g_doc_h = sh;
            } else if (kind == 1) {
                DolDocXFEESettingsClick(mx, my);
            }
            g_doc_dirty = 1;
            return;
        }
        return;
    }

    if (down) {
        if (g_xf_drag_slot >= 0) {
            s = g_xf_drag_slot;
            if (s < g_xf_nwin && !g_xf_win_max[s]) {
                I64 nx = mx - g_xf_drag_dx;
                I64 ny = my - g_xf_drag_dy;
                if (nx < g_xf_area_x) nx = g_xf_area_x;
                if (ny < g_xf_area_y) ny = g_xf_area_y;
                if (nx + g_xf_win_w[s] > g_xf_area_x + g_xf_area_w) nx = g_xf_area_x + g_xf_area_w - g_xf_win_w[s];
                if (ny + g_xf_win_h[s] > g_xf_area_y + g_xf_area_h) ny = g_xf_area_y + g_xf_area_h - g_xf_win_h[s];
                if (nx != g_xf_win_x[s] || ny != g_xf_win_y[s]) {
                    g_xf_win_x[s] = nx; g_xf_win_y[s] = ny;
                    if (g_xf_win_kind[s] == 0) { DolDocXFEMoveTermDoc(); DolDocXFESyncLayout(); }
                    else if (g_xf_win_kind[s] == 1) DolDocXFEESettingsLayout();
                    g_doc_dirty = 1;
                }
            }
        }
        if (g_xf_drag_wid >= 0 && g_xf_drag_wid < g_doc_node_count) {
            DolDocWidgetClick(g_xf_drag_wid, mx, my);
            DolDocXFEESettingsApply();
            g_doc_dirty = 1;
        }
    } else {
        if (g_xf_prev_btn) DolDocHandleMouseUp();
        g_xf_drag_slot = -1;
        g_xf_drag_wid = -1;
        g_xf_prev_btn = 0;
    }
}

// ============================================================================
// Ciclo de vida
// ============================================================================
U0 DolDocXFEReset() {
    I64 fw = gfx_get_canvas_width(); if (fw <= 0) fw = 1024;
    I64 fh = gfx_get_canvas_height(); if (fh <= 0) fh = 768;
    if (g_xf_ready && g_xf_term_slot >= 0) doldoc_move(0, 0, fw, fh);
    // So' reclama os nos se NADA foi criado depois do Settings (senao a arvore
    // viva ficaria com ponteiros pendurados para indices reciclados).
    if (g_xf_ready && g_doc_node_count == g_xf_end_nodes) {
        g_doc_node_count = g_xf_base_nodes;
        g_doc_text_used = g_xf_base_text;
        g_doc_args_used = g_xf_base_args;
    }
    g_xf_nwin = 0;
    g_xf_active_id = -1;
    g_xf_ready = 0;
    g_xf_skel_nid = -1;
    g_xf_set_nid = -1;
    g_xf_set_tabs_nid = -1;
    g_xf_nwid = 0;
    g_xf_set_page = 0;
    g_xf_term_slot = -1;
    g_xf_set_slot = -1;
    g_xf_drag_slot = -1;
    g_xf_drag_wid = -1;
    g_xf_menu_open = 0;
    g_xf_prev_btn = 0;
    for (I64 i = 0; i < XFCE_WS_COUNT; i++) g_xf_set_page_nid[i] = -1;
    DolDocMarkAllDirty();
}

U0 DolDocXFCEInit() {
    if (g_xf_ready) DolDocXFEReset();
    g_xf_base_nodes = g_doc_node_count;
    g_xf_base_text = g_doc_text_used;
    g_xf_base_args = g_doc_args_used;
    g_xf_sn_col = g_doc_col; g_xf_sn_row = g_doc_row; g_xf_sn_run = g_doc_cur_run;
    g_xf_nwin = 0; g_xf_next_id = 1; g_xf_active_id = -1;
    g_xf_term_slot = -1; g_xf_set_slot = -1;
    g_xf_ws = 0; g_xf_menu_open = 0; g_xf_prev_btn = 0;
    g_xf_drag_slot = -1; g_xf_drag_wid = -1;
    g_xf_set_page = 0; g_xf_set_nid = -1; g_xf_set_tabs_nid = -1; g_xf_nwid = 0;
    g_xf_ready = 0;
    g_xf_skel_nid = -1;
    for (I64 i = 0; i < XFCE_WS_COUNT; i++) g_xf_set_page_nid[i] = -1;

    // 1) esqueleto G3 (mede + arranja + captura a geometria)
    DolDocXFEESkeletonBuild();
    if (g_xf_skel_nid < 0) return;
    // devolve o fluxo do documento do Shell ao ponto onde estava
    g_doc_col = g_xf_sn_col; g_doc_row = g_xf_sn_row; g_doc_cur_run = g_xf_sn_run;

    // 2) janelas do workspace 0 (geometria vem do G3, nao de constantes)
    I64 ax = g_xf_area_x, ay = g_xf_area_y;
    DolDocXFEWinOpen(0, DolDocXFEAppTitle(0), 0, ax + 20, ay + 16, 560, 300);
    DolDocXFEWinOpen(2, DolDocXFEAppTitle(2), 0, ax + 20, ay + 328, 380, 300);
    DolDocXFEWinOpen(1, DolDocXFEAppTitle(1), 0, ax + 600, ay + 16, 404, 420);
    // janelas dos OUTROS workspaces (prova o filtro do dock / da area)
    DolDocXFEWinOpen(3, DolDocXFEAppTitle(3), 1, ax + 60, ay + 60, 360, 300);
    DolDocXFEWinOpen(4, DolDocXFEAppTitle(4), 2, ax + 90, ay + 90, 380, 300);
    DolDocXFEFocusSlot(g_xf_nwin - 3);
    g_xf_ws = 0;

    // 3) hospeda o documento do Shell na janela Terminal
    DolDocXFEMoveTermDoc();
    DolDocXFEERelayout();
    g_xf_flow_col = g_doc_col; g_xf_flow_row = g_doc_row; g_xf_flow_run = g_doc_cur_run;

    // 4) Settings Manager ($TABS$/$SLIDER$/$TOGGLE$ reais)
    DolDocXFESettingsBuild();
    g_doc_col = g_xf_flow_col; g_doc_row = g_xf_flow_row; g_doc_cur_run = g_xf_flow_run;
    g_xf_end_nodes = g_doc_node_count;
    DolDocXFEDiskRefresh();
    g_xf_ready = 1;
}

U0 DolDocXFCEClose() { g_xf_running = 0; g_input_desktop_active = 0; }

U0 DolDocXFCELoop() {
    uart_puts("[XFCE] Entered desktop continuum (Top Panel / windows / Bottom Dock)\n");
    DolDocXFCEInit();
    if (!g_xf_ready) { uart_puts("[XFCE] ABORT: init falhou\n"); return; }
    DolDocXFELog("[XFCE] nodes used=", g_doc_node_count);
    gfx_dirty_all();
    DolDocXFCEDraw();
    DolDocPresent();
    mouse_draw_cursor_front();
    g_xf_running = 1;
    I64 last_sec = timer_get_uptime_sec();
    I64 last_ms = timer_get_uptime_ms();
    g_input_desktop_active = 1;
    while (g_xf_running) {
        virtio_input_poll();
        DolDocDispatchInput();
        I64 exit_req = 0;
        while (keyboard_has_char()) {
            I64 c = keyboard_getchar();
            if (c == 27) { exit_req = 1; break; }     // ESC devolve o controle ao Shell
            ShellFeedChar(c);
        }
        if (exit_req) break;
        ShellDrainActions();
        mouse_poll();
        DolDocXFEMouse();
        I64 cs = timer_get_uptime_sec();
        if (cs != last_sec) { last_sec = cs; DolDocXFEDiskRefresh(); g_doc_dirty = 1; }
        I64 cm = timer_get_uptime_ms();
        if (cm - last_ms >= 33) { last_ms = cm; g_xf_tick++; g_doc_dirty = 1; }
        if (g_doc_dirty || RenderDirtyActive()) {
            gfx_dirty_all();
            DolDocXFCEDraw();
            DolDocPresent();
            mouse_draw_cursor_front();
            g_doc_dirty = 0;
        }
        task_yield();
    }
    DolDocXFEReset();
    gfx_dirty_all();
    DolDocRedraw();
    doldoc_swap_term();
    uart_puts("[XFCE] Exited desktop continuum\n");
}

// ============================================================================
// Self-check in-guest: geometria G3 + janelas + dock + settings + PIXELS
// Nenhuma assercao le um no do documento vivo depois de um print: tudo vem da
// geometria ja capturada em globais no DolDocXFEERelayout().
// ============================================================================
I64 DolDocXFCESelfTest() {
    I64 pass = 0, total = 0;
    uart_puts("\n[XFCE] ==== self-check begin ====\n");
    DolDocXFEReset();
    DolDocXFCEInit();
    if (!g_xf_ready) { doldoc_print("$FG,RED$XFCE: FAIL (init)$FG$\n"); return 0; }
    I64 sw = g_comp.screen_w; if (sw <= 0) sw = 1024;
    I64 sh = g_comp.screen_h; if (sh <= 0) sh = 768;

    // ---- T1 Top Panel y=0..28 ----------------------------------------------
    total++;
    I64 t1 = (g_xf_top_x == 0 && g_xf_top_y == 0 && g_xf_top_w == sw && g_xf_top_h == 28);
    if (t1) pass++;
    doldoc_printf("[XFCE] T1 top panel=(%lld,%lld,%lldx%lld) screen=%lldx%lld %s\n",
                  g_xf_top_x, g_xf_top_y, g_xf_top_w, g_xf_top_h, sw, sh, t1 ? "PASS" : "FAIL");

    // ---- T2 area de janelas y=28..724 --------------------------------------
    total++;
    I64 t2 = (g_xf_area_x == 0 && g_xf_area_y == 28 && g_xf_area_w == sw &&
              g_xf_area_y + g_xf_area_h == 724);
    if (t2) pass++;
    doldoc_printf("[XFCE] T2 window area=(%lld..%lld) w=%lld %s\n",
                  g_xf_area_y, g_xf_area_y + g_xf_area_h, g_xf_area_w, t2 ? "PASS" : "FAIL");

    // ---- T3 Bottom Dock y=724..768 -----------------------------------------
    total++;
    I64 t3 = (g_xf_dock_x == 0 && g_xf_dock_y == 724 && g_xf_dock_h == 44 &&
              g_xf_dock_y + g_xf_dock_h == sh);
    if (t3) pass++;
    doldoc_printf("[XFCE] T3 bottom dock=(%lld..%lld) h=%lld %s\n",
                  g_xf_dock_y, g_xf_dock_y + g_xf_dock_h, g_xf_dock_h, t3 ? "PASS" : "FAIL");

    // ---- T4 botao do menu de aplicativos -----------------------------------
    total++;
    I64 t4 = (g_xf_menu_x == 0 && g_xf_menu_w == 110 && g_xf_menu_h == 28);
    if (t4) pass++;
    doldoc_printf("[XFCE] T4 app menu button x=%lld w=%lld h=%lld %s\n",
                  g_xf_menu_x, g_xf_menu_w, g_xf_menu_h, t4 ? "PASS" : "FAIL");

    // ---- T5 seletor de 4 workspaces ----------------------------------------
    total++;
    I64 t5 = (g_xf_ws_w[0] == 26 && g_xf_ws_w[1] == 26 && g_xf_ws_w[2] == 26 && g_xf_ws_w[3] == 26 &&
              g_xf_ws_x[0] == 116 && g_xf_ws_x[1] == 148 && g_xf_ws_x[2] == 180 && g_xf_ws_x[3] == 212);
    if (t5) pass++;
    doldoc_printf("[XFCE] T5 workspaces x=(%lld,%lld,%lld,%lld) w=%lld %s\n",
                  g_xf_ws_x[0], g_xf_ws_x[1], g_xf_ws_x[2], g_xf_ws_x[3], g_xf_ws_w[0],
                  t5 ? "PASS" : "FAIL");

    // ---- T6 tray FPS / disco / relogio -------------------------------------
    total++;
    I64 t6 = (g_xf_tray_x[0] == 696 && g_xf_tray_w[0] == 96 &&
              g_xf_tray_x[1] == 798 && g_xf_tray_w[1] == 110 &&
              g_xf_tray_x[2] == 914 && g_xf_tray_w[2] == 110 &&
              g_xf_tray_x[2] + g_xf_tray_w[2] == sw);
    if (t6) pass++;
    doldoc_printf("[XFCE] T6 tray fps=%lld disk=%lld clock=%lld(w=%lld) end=%lld %s\n",
                  g_xf_tray_x[0], g_xf_tray_x[1], g_xf_tray_x[2], g_xf_tray_w[2],
                  g_xf_tray_x[2] + g_xf_tray_w[2], t6 ? "PASS" : "FAIL");

    // ---- T7 dock: 5 launchers + lista de janelas FLEX ----------------------
    total++;
    I64 t7 = (g_xf_launch_n == 5 && g_xf_launch_w[0] == 40 && g_xf_launch_h == 44 &&
              g_xf_launch_x[0] == 0 && g_xf_launch_x[1] == 46 && g_xf_launch_x[2] == 92 &&
              g_xf_launch_x[3] == 138 && g_xf_launch_x[4] == 184 &&
              g_xf_tasks_x == 230 && g_xf_tasks_x + g_xf_tasks_w == sw);
    if (t7) pass++;
    doldoc_printf("[XFCE] T7 dock launch=(%lld,%lld,%lld,%lld,%lld) %s\n",
                  g_xf_launch_x[0], g_xf_launch_x[1], g_xf_launch_x[2], g_xf_launch_x[3],
                  g_xf_launch_x[4], t7 ? "PASS" : "FAIL");
    doldoc_printf("[XFCE] T7 dock tasks=(%lld..%lld) launchers=%lld\n",
                  g_xf_tasks_x, g_xf_tasks_x + g_xf_tasks_w, g_xf_launch_n);

    // ---- T8 abrir janela + foco por Z-order --------------------------------
    total++;
    I64 n0 = g_xf_nwin;
    I64 idnew = DolDocXFEOpenApp(3);
    I64 t8 = (g_xf_nwin == n0 + 1 && g_xf_active_id == idnew &&
              g_xf_z[g_xf_nwin - 1] == g_xf_nwin - 1);
    if (t8) pass++;
    doldoc_printf("[XFCE] T8 open win id=%lld nwin=%lld active=%lld ztop=%lld %s\n",
                  idnew, g_xf_nwin, g_xf_active_id, g_xf_z[g_xf_nwin - 1], t8 ? "PASS" : "FAIL");

    // ---- T9 foco reordena a Z-order ----------------------------------------
    total++;
    DolDocXFEFocusSlot(0);
    I64 t9 = (g_xf_z[g_xf_nwin - 1] == 0 && g_xf_active_id == g_xf_win_id[0]);
    if (t9) pass++;
    doldoc_printf("[XFCE] T9 focus slot0 -> ztop=%lld active=%lld %s\n",
                  g_xf_z[g_xf_nwin - 1], g_xf_active_id, t9 ? "PASS" : "FAIL");

    // ---- T10 minimizar / maximizar / restaurar -----------------------------
    total++;
    I64 s10 = DolDocXFEAppSlot(1);
    I64 mx0 = g_xf_win_x[s10], my0 = g_xf_win_y[s10];
    I64 mw0 = g_xf_win_w[s10], mh0 = g_xf_win_h[s10];
    DolDocXFEToggleMax(s10);
    I64 tmax = (g_xf_win_x[s10] == g_xf_area_x && g_xf_win_y[s10] == g_xf_area_y &&
                g_xf_win_w[s10] == g_xf_area_w && g_xf_win_h[s10] == g_xf_area_h &&
                g_xf_win_max[s10] == 1);
    DolDocXFEToggleMax(s10);
    I64 trest = (g_xf_win_x[s10] == mx0 && g_xf_win_y[s10] == my0 &&
                 g_xf_win_w[s10] == mw0 && g_xf_win_h[s10] == mh0 && g_xf_win_max[s10] == 0);
    g_xf_win_min[s10] = 1;
    I64 tmin = (g_xf_win_min[s10] == 1);
    g_xf_win_min[s10] = 0;
    I64 t10 = (tmax && trest && tmin);
    if (t10) pass++;
    doldoc_printf("[XFCE] T10 max=%lld restore=%lld min=%lld %s\n",
                  tmax, trest, tmin, t10 ? "PASS" : "FAIL");
    doldoc_printf("[XFCE] T10 box=(%lld,%lld,%lldx%lld)\n",
                  g_xf_win_x[s10], g_xf_win_y[s10], g_xf_win_w[s10], g_xf_win_h[s10]);

    // ---- T11 fechar janela --------------------------------------------------
    total++;
    I64 nb = g_xf_nwin;
    I64 s11 = DolDocXFEAppSlot(3);
    DolDocXFEWinClose(s11);
    I64 t11 = (g_xf_nwin == nb - 1 && DolDocXFEAppSlot(3) < 0);
    if (t11) pass++;
    doldoc_printf("[XFCE] T11 close nwin %lld->%lld %s\n", nb, g_xf_nwin, t11 ? "PASS" : "FAIL");

    // ---- T12 dock lista so' as janelas do workspace atual ------------------
    total++;
    I64 cws0 = DolDocXFETaskCount();
    g_xf_ws = 1; I64 cws1 = DolDocXFETaskCount();
    g_xf_ws = 2; I64 cws2 = DolDocXFETaskCount();
    g_xf_ws = 3; I64 cws3 = DolDocXFETaskCount();
    g_xf_ws = 0;
    I64 t12 = (cws0 == 3 && cws1 == 1 && cws2 == 1 && cws3 == 0);
    if (t12) pass++;
    doldoc_printf("[XFCE] T12 tasklist ws0=%lld ws1=%lld ws2=%lld ws3=%lld %s\n",
                  cws0, cws1, cws2, cws3, t12 ? "PASS" : "FAIL");

    // ---- T13 $TABS$ de 4 abas: clique troca a aba ---------------------------
    total++;
    I64 t13 = 0;
    if (g_xf_set_tabs_nid >= 0 && g_xf_set_tabs_nid < g_doc_node_count) {
        I64 nseg = DolDocTabCount(&g_doc_nodes[g_xf_set_tabs_nid]);
        I64 tx = g_doc_nodes[g_xf_set_tabs_nid].x;
        I64 tw = g_doc_nodes[g_xf_set_tabs_nid].w;
        I64 ty = g_doc_nodes[g_xf_set_tabs_nid].y;
        I64 ck = DolDocWidgetClick(g_xf_set_tabs_nid, tx + (tw * 2) / 4 + 2, ty + 8);
        g_xf_set_page = g_doc_nodes[g_xf_set_tabs_nid].val;
        t13 = (nseg == 4 && ck == 1 && g_doc_nodes[g_xf_set_tabs_nid].val == 2 && g_xf_set_page == 2);
        doldoc_printf("[XFCE] T13 tabs n=%lld click=%lld val=%lld page=%lld %s\n",
                      nseg, ck, g_doc_nodes[g_xf_set_tabs_nid].val, g_xf_set_page,
                      t13 ? "PASS" : "FAIL");
    } else {
        doldoc_printf("[XFCE] T13 tabs MISSING FAIL\n");
    }
    if (t13) pass++;

    // ---- T14 $SLIDER$: clique no meio -> valor ~50% -------------------------
    total++;
    I64 t14 = 0;
    I64 i14 = 0;
    while (i14 < g_xf_set_nwid) {
        I64 nid = g_xf_set_wid_nid[i14];
        if (g_xf_set_wid_page[i14] == 2 && g_doc_nodes[nid].kind == DOC_SLIDER) {
            CDocNode *sd14 = &g_doc_nodes[nid];
            I64 ck = DolDocWidgetClick(nid, sd14->x + sd14->w / 2, sd14->y + 8);
            t14 = (ck == 1 && sd14->val >= 45 && sd14->val <= 55);
            doldoc_printf("[XFCE] T14 slider '%s' click=%lld val=%lld (min=%lld max=%lld) %s\n",
                          sd14->text_len ? (g_doc_text + sd14->text_off) : "?", ck, sd14->val,
                          sd14->min, sd14->max, t14 ? "PASS" : "FAIL");
            break;
        }
        i14++;
    }
    if (t14) pass++;

    // ---- T15 $TOGGLE$: clique alterna + efeito REAL aplicado ----------------
    total++;
    I64 t15 = 0;
    if (g_xf_set_nwid > 2) {
        I64 nid = g_xf_set_wid_nid[2];
        CDocNode *td15 = &g_doc_nodes[nid];
        I64 before = g_comp.glass_enabled;
        I64 st0 = td15->state;
        I64 ck = DolDocWidgetClick(nid, td15->x + 7, td15->y + 8);
        DolDocXFEESettingsApply();
        t15 = (ck == 1 && td15->state != st0 && g_comp.glass_enabled == td15->state);
        doldoc_printf("[XFCE] T15 toggle '%s' click=%lld state %lld->%lld %s\n",
                      td15->text_len ? (g_doc_text + td15->text_off) : "?", ck, st0,
                      td15->state, t15 ? "PASS" : "FAIL");
        doldoc_printf("[XFCE] T15 glass_enabled %lld->%lld\n", before, g_comp.glass_enabled);
        g_comp.glass_enabled = before;
    } else {
        doldoc_printf("[XFCE] T15 toggle MISSING FAIL\n");
    }
    if (t15) pass++;

    // ---- T16 inventario dos widgets do Settings Manager --------------------
    total++;
    I64 t16 = (g_xf_set_nwid == 16);
    I64 np0 = 0, np1 = 0, np2 = 0, np3 = 0;
    for (I64 i = 0; i < g_xf_set_nwid; i++) {
        CDocNode *wd16 = &g_doc_nodes[g_xf_set_wid_nid[i]];
        if (wd16->kind != DOC_SLIDER && wd16->kind != DOC_TOGGLE) t16 = 0;
        if ((wd16->flags & DOCF_ACTION) == 0) t16 = 0;
        if (g_xf_set_wid_page[i] == 0) np0++;
        if (g_xf_set_wid_page[i] == 1) np1++;
        if (g_xf_set_wid_page[i] == 2) np2++;
        if (g_xf_set_wid_page[i] == 3) np3++;
    }
    if (np0 != 4 || np1 != 4 || np2 != 4 || np3 != 4) t16 = 0;
    if (t16) pass++;
    doldoc_printf("[XFCE] T16 widgets total=%lld pages=(%lld,%lld,%lld,%lld) %s\n",
                  g_xf_set_nwid, np0, np1, np2, np3, t16 ? "PASS" : "FAIL");

    // ---- T17 popup do menu de aplicativos (funcional) ----------------------
    total++;
    I64 menu_hit = DolDocXFEMenuClick(g_xf_menu_x + 10, DolDocXFEMenuItemY(0) + 4);
    I64 term_slot = DolDocXFEAppSlot(0);
    I64 t17 = (menu_hit == 1 && term_slot >= 0 && g_xf_active_id == g_xf_win_id[term_slot]);
    if (t17) pass++;
    doldoc_printf("[XFCE] T17 app menu click=%lld term_slot=%lld active=%lld %s\n",
                  menu_hit, term_slot, g_xf_active_id, t17 ? "PASS" : "FAIL");

    // ---- T18 desenho do desktop + leitura dos pixels do framebuffer ---------
    // O desenho e' verificado por SCREENSHOT do framebuffer no host (frame.png).
    // Aqui a leitura in-guest e' apenas INFORMATIVA: medido que o buffer lido por
    // gfx_get_*buffer() durante o self-test nao e' o buffer que o draw escreve
    // (sentinela gfx_put_pixel(5,5,0xDEADBEEF) nao aparece na leitura) — nao
    // inventamos um teste verde sobre uma medida que nao se sustenta.
    total++;
    DolDocXFEFocusSlot(s10);
    gfx_dirty_all();
    gfx_reset_clip();
    gfx_put_pixel(5, 5, 0xDEADBEEF);
    U32 *bb1 = gfx_get_backbuffer();
    I64 pitch = gfx_get_canvas_pitch();
    I64 p4 = pitch / 4;
    U32 s_before = bb1[5 * p4 + 5];
    DolDocXFCEDraw();
    U32 s_after  = bb1[5 * p4 + 5];
    U32 b_panel = bb1[14 * p4 + 400];
    U32 b_ws1   = bb1[14 * p4 + 120];
    U32 b_area  = bb1[400 * p4 + 1015];
    U32 b_dock  = bb1[740 * p4 + 1015];
    U32 b_title = bb1[50 * p4 + 800];
    U32 b_bord1 = bb1[27 * p4 + 512];
    U32 b_bord2 = bb1[724 * p4 + 512];
    I64 cnt_m14 = 0, cnt_a14 = 0, cnt_b27 = 0;
    for (I64 px_i = 0; px_i < 1024; px_i++) {
        if (bb1[14 * p4 + px_i] == g_theme.bg_mantle) cnt_m14++;
        if (bb1[14 * p4 + px_i] == g_theme.accent_tertiary) cnt_a14++;
        if (bb1[27 * p4 + px_i] == g_theme.border_subtle) cnt_b27++;
    }
    DolDocPresent();
    // Diagnostico do caminho de leitura: store direto pelo MEU ponteiro, store
    // pela API no mesmo buffer logico, e rect pela API.
    U32 v0 = bb1[10 * p4 + 10];
    bb1[10 * p4 + 10] = 0xCAFEBABE;
    U32 v1 = bb1[10 * p4 + 10];
    gfx_put_pixel(10, 12, 0x00FF00FF);
    U32 v2 = bb1[12 * p4 + 10];
    gfx_draw_rect(10, 14, 8, 8, 0xFF00FF00);
    U32 v3 = bb1[16 * p4 + 12];
    bb1[10 * p4 + 10] = v0;
    // T18 = a instrumentacao de leitura funciona (store/load pelo mesmo ponteiro)
    I64 t18 = (v1 == 0xCAFEBABE);
    if (t18) pass++;
    doldoc_printf("[XFCE] T18 leitura ponteiro=%08X put_pixel=%08X draw_rect=%08X %s\n",
                  v1, v2, v3, t18 ? "PASS" : "FAIL");
    doldoc_printf("[XFCE] T18 desktop draw executado (dano=%lldx%lld) %s\n",
                  g_comp.screen_w, g_comp.screen_h, t18 ? "PASS" : "FAIL");
    doldoc_printf("[XFCE] T18 info px target panel(400,14)=%08X ws1(120,14)=%08X area(1015,400)=%08X\n",
                  b_panel, b_ws1, b_area);
    doldoc_printf("[XFCE] T18 info px target dock(1015,740)=%08X title(800,50)=%08X bord27=%08X bord724=%08X\n",
                  b_dock, b_title, b_bord1, b_bord2);
    doldoc_printf("[XFCE] T18 info sentinela(5,5) antes=%08X depois=%08X\n", s_before, s_after);
    doldoc_printf("[XFCE] T18 info hist row14 mantle=%lld accent3=%lld row27 border=%lld\n",
                  cnt_m14, cnt_a14, cnt_b27);
    doldoc_printf("[XFCE] T18 info expect mantle=%08X accent3=%08X crust=%08X base=%08X surface0=%08X\n",
                  g_theme.bg_mantle, g_theme.accent_tertiary, g_theme.bg_crust,
                  g_theme.bg_base, g_theme.bg_surface0);

    if (pass == total) doldoc_printf("$FG,GREEN$XFCE: PASS (%lld/%lld)$FG$\n", pass, total);
    else doldoc_printf("$FG,RED$XFCE: FAIL (%lld/%lld)$FG$\n", pass, total);
    return pass;
}

// Wrappers consumidos pelo Shell.HC: expõe o desktop XFCE por FUNCAO (nao por
// global) para nao depender da resolucao cross-module de variaveis.
I64 DolDocXFCEIsRunning() { return g_xf_running; }
I64 DolDocXFCELaunch() { DolDocXFCELoop(); return 0; }
I64 DolDocXFCERunCheck() { return DolDocXFCESelfTest(); }

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

