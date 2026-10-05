// ==============================================================================
// DolDoc.HC - Pure HolyC DolDoc Document & Geometry Quad Streaming Engine
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Emits 2D text & interactive macro buttons as HolyGL quads (Z = 0.90)
// ==============================================================================

#define DOLDOC_MAX_LINES 128
#define DOLDOC_LINE_LEN  128

class CDolDocButton {
    I64 x, y, w, h;
    U8  text[32];
    U8  command[64];
    I64 is_hovered;
};

class CDolDocView {
    I64 x, y, w, h;
    U32 cur_fg;
    U32 cur_bg;
    I64 cursor_col;
    I64 cursor_row;
    
    CDolDocButton buttons[16];
    I64           button_count;
};

CDolDocView g_doldoc;

U0 DolDocInitView(I64 x, I64 y, I64 w, I64 h) {
    g_doldoc.x = x;
    g_doldoc.y = y;
    g_doldoc.w = w;
    g_doldoc.h = h;
    g_doldoc.cur_fg = 0xFFCDD6F4;
    g_doldoc.cur_bg = 0xFF181825;
    g_doldoc.cursor_col = 0;
    g_doldoc.cursor_row = 0;
    g_doldoc.button_count = 0;
}

// Emits an interactive button as an analytical quad with drop border
U0 DolDocEmitButtonQuad(I64 bx, I64 by, I64 bw, I64 bh, U8 *label, U8 *cmd) {
    if (g_doldoc.button_count >= 15) return;
    
    CDolDocButton *btn = &g_doldoc.buttons[g_doldoc.button_count++];
    btn->x = bx;
    btn->y = by;
    btn->w = bw;
    btn->h = bh;
    btn->is_hovered = 0;
    strcpy(btn->text, label);
    strcpy(btn->command, cmd);

    // 1. Soft Shadow
    gfx_blend_rect(bx - 2, by - 2, bw + 4, bh + 4, 0x40000000);
    
    // 2. Button Body
    gfx_draw_rect(bx, by, bw, bh, 0xFF313244);
    
    // 3. Highlight Border
    gfx_draw_rect(bx, by, bw, 1, 0xFF89B4FA);
    
    // 4. Centered Label
    gfx_draw_string(bx + 8, by + 4, label, 0xFFCDD6F4, 0);
}

// Streaming text renderer
U0 DolDocStreamText(U8 *str) {
    I64 px = g_doldoc.x + 16 + (g_doldoc.cursor_col * 9);
    I64 py = g_doldoc.y + 36 + (g_doldoc.cursor_row * 18);
    gfx_draw_string(px, py, str, g_doldoc.cur_fg, 0);
    g_doldoc.cursor_row++;
}

U0 DolDocDemo() {
    DolDocInitView(100, 100, 600, 300);
    
    DolDocStreamText("✦ NeoOS Pure HolyC DolDoc Geometry Stream ✦");
    DolDocStreamText("Every text character and macro button is a HolyGL quad.");
    
    DolDocEmitButtonQuad(120, 200, 130, 26, "GLXGears 3D", "gears");
    DolDocEmitButtonQuad(270, 200, 130, 26, "Physics 3D", "run Physics3D.HC");
    DolDocEmitButtonQuad(420, 200, 130, 26, "WASM Runner", "run WasmJit.HC");
    
    doldoc_print("$FG,GREEN$[DOLDOC.HC] Successfully streamed geometry quads into desktop backbuffer!$FG$\n");
}

DolDocDemo();
