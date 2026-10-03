// FontVector.HC - Sovereign Native HolyC Vector Font & Bézier Engine
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution
// Analytical Quadratic Bézier Curves & Contour Tessellation

class CVectorPoint {
    I64 x;
    I64 y;
};

class CBezierCurve {
    I64 p0x; I64 p0y; // Start point
    I64 p1x; I64 p1y; // Control point
    I64 p2x; I64 p2y; // End point
};

// Analytical Quadratic Bézier Evaluation using 64-bit fixed point (scale = 1000)
// B(t) = ((1000 - t)^2 * P0 + 2 * (1000 - t) * t * P1 + t^2 * P2) / 1000000
I64 BezierEval1D(I64 p0, I64 p1, I64 p2, I64 t) {
    I64 u = 1000 - t;
    I64 term0 = u * u * p0;
    I64 term1 = 2 * u * t * p1;
    I64 term2 = t * t * p2;
    return (term0 + term1 + term2) / 1000000;
}

// Draw a line using integer DDA / Bresenham directly to target framebuffer
U0 VectorDrawLine(I64 x0, I64 y0, I64 x1, I64 y1, U32 color) {
    gfx_draw_line(x0, y0, x1, y1, color);
}

// Draw a quadratic Bézier curve segmented into 16 linear chords
U0 VectorDrawBezier(I64 p0x, I64 p0y, I64 p1x, I64 p1y, I64 p2x, I64 p2y, U32 color) {
    I64 steps = 16;
    I64 last_x = p0x;
    I64 last_y = p0y;

    for (I64 i = 1; i <= steps; i++) {
        I64 t = (i * 1000) / steps;
        I64 cur_x = BezierEval1D(p0x, p1x, p2x, t);
        I64 cur_y = BezierEval1D(p0y, p1y, p2y, t);
        VectorDrawLine(last_x, last_y, cur_x, cur_y, color);
        last_x = cur_x;
        last_y = cur_y;
    }
}

// Render a scalable vector glyph based on outline segments
U0 VectorDrawGlyph(U8 ch, I64 ox, I64 oy, I64 scale, U32 color) {
    // scale is fixed-point (e.g. 10 = 1.0x, 20 = 2.0x, 30 = 3.0x)
    if (scale < 5) scale = 5;

    // Vector character definitions (normalized 100x100 grid)
    if (ch == 'N') {
        I64 x0 = ox;
        I64 y0 = oy + (100 * scale) / 10;
        I64 y1 = oy;
        I64 x1 = ox + (70 * scale) / 10;
        VectorDrawLine(x0, y0, x0, y1, color);
        VectorDrawLine(x0, y1, x1, y0, color);
        VectorDrawLine(x1, y0, x1, y1, color);
    } else if (ch == 'E') {
        I64 x0 = ox;
        I64 y0 = oy;
        I64 y1 = oy + (100 * scale) / 10;
        I64 w  = (60 * scale) / 10;
        VectorDrawLine(x0, y0, x0, y1, color);
        VectorDrawLine(x0, y0, x0 + w, y0, color);
        VectorDrawLine(x0, y0 + (50 * scale) / 10, x0 + (45 * scale) / 10, y0 + (50 * scale) / 10, color);
        VectorDrawLine(x0, y1, x0 + w, y1, color);
    } else if (ch == 'O') {
        // Render 'O' using 4 smooth quadratic Bézier curves
        I64 cx = ox + (40 * scale) / 10;
        I64 cy = oy + (50 * scale) / 10;
        I64 rx = (35 * scale) / 10;
        I64 ry = (48 * scale) / 10;

        // Top arc
        VectorDrawBezier(cx - rx, cy, cx - rx, cy - ry, cx, cy - ry, color);
        VectorDrawBezier(cx, cy - ry, cx + rx, cy - ry, cx + rx, cy, color);
        // Bottom arc
        VectorDrawBezier(cx + rx, cy, cx + rx, cy + ry, cx, cy + ry, color);
        VectorDrawBezier(cx, cy + ry, cx - rx, cy + ry, cx - rx, cy, color);
    } else if (ch == 'S') {
        // Render 'S' using 2 continuous Bézier curves
        I64 x0 = ox + (50 * scale) / 10;
        I64 y0 = oy + (15 * scale) / 10;
        I64 mx = ox + (25 * scale) / 10;
        I64 my = oy + (50 * scale) / 10;
        I64 x1 = ox;
        I64 y1 = oy + (85 * scale) / 10;

        VectorDrawBezier(x0, y0, ox - (10 * scale) / 10, oy, mx, my, color);
        VectorDrawBezier(mx, my, ox + (60 * scale) / 10, oy + (100 * scale) / 10, x1, y1, color);
    } else {
        // Generic rectangular fallback glyph
        I64 w = (40 * scale) / 10;
        I64 h = (70 * scale) / 10;
        VectorDrawLine(ox, oy, ox + w, oy, color);
        VectorDrawLine(ox + w, oy, ox + w, oy + h, color);
        VectorDrawLine(ox + w, oy + h, ox, oy + h, color);
        VectorDrawLine(ox, oy + h, ox, oy, color);
    }
}

// Draw string of scalable vector typography
U0 VectorDrawString(U8 *str, I64 x, I64 y, I64 scale, U32 color) {
    if (!str) return;
    I64 cur_x = x;
    U8 *p = str;
    while (*p) {
        if (*p == ' ') {
            cur_x = cur_x + (40 * scale) / 10;
        } else {
            VectorDrawGlyph(*p, cur_x, y, scale, color);
            cur_x = cur_x + (75 * scale) / 10;
        }
        p++;
    }
}

// Standalone HolyC Vector Font & Bézier Engine Suite
U0 FontVectorMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS Native HolyC Vector Font & Bézier Engine (FontVector.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Formulation: Analytical Quadratic Bézier Contours | Fixed-Point Arithmetic\n");
    doldoc_print(" Pipeline   : Zero C Libs | Pure HolyC Outline Tessellation & Rendering\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" [1/3] Benchmarking Bézier Curve Evaluation (50,000 points)...\n");
    I64 start_us = timer_get_uptime_us();
    I64 checksum = 0;

    for (I64 i = 0; i < 50000; i++) {
        I64 t = (i * 20) % 1000;
        I64 val = BezierEval1D(10, 150, 80, t);
        checksum = checksum + val;
    }

    I64 end_us = timer_get_uptime_us();
    I64 elapsed = end_us - start_us;
    if (elapsed <= 0) elapsed = 1;

    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Evaluated 50,000 Bézier points in %lld us (Checksum: %lld)\n",
                  elapsed, checksum);

    doldoc_print(" [2/3] Rendering Scalable Vector Glyphs to Canvas...\n");
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();

    // Render "NEO" in vector outlines in top-center of screen
    I64 logo_x = w / 2 - 120;
    I64 logo_y = 60;
    if (logo_x > 0 && logo_y > 0 && logo_x + 250 < w) {
        VectorDrawGlyph('N', logo_x, logo_y, 8, 0xFF3DAEE9);
        VectorDrawGlyph('E', logo_x + 70, logo_y, 8, 0xFF00E676);
        VectorDrawGlyph('O', logo_x + 140, logo_y, 8, 0xFFE056FD);
        VectorDrawGlyph('S', logo_x + 210, logo_y, 8, 0xFFF1C40F);
        gfx_dirty_expand(logo_x - 10, logo_y - 10, 300, 120);
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Vector glyphs 'NEOS' rendered live at (%lld, %lld)\n",
                      logo_x, logo_y);
    }

    doldoc_print(" [3/3] Mathematical Curvature & Continuity Verification...\n");
    // Verify B(0) == P0, B(1000) == P2, and B(500) == (P0 + 2*P1 + P2) / 4
    I64 b_start = BezierEval1D(100, 500, 900, 0);
    I64 b_mid   = BezierEval1D(100, 500, 900, 500);
    I64 b_end   = BezierEval1D(100, 500, 900, 1000);

    if (b_start == 100 && b_mid == 500 && b_end == 900) {
        doldoc_print("  $FG,GREEN$[PASS]$FG$ Bézier boundary conditions verified exact.\n");
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Boundary mismatch: start=%lld mid=%lld end=%lld\n",
                      b_start, b_mid, b_end);
    }

    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_print(" Actions: $BT,\"Re-run Vector Font\",LM=\"run FontVector.HC\"$  $BT,\"L1 Rasterizer\",LM=\"run RasterTile.HC\"$  $BT,\"Menu\",LM=\"menu\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

FontVectorMain();
