// ==============================================================================
// apps/Fonts.HC - NeoOS unified font engine (P4.4)
// ------------------------------------------------------------------------------
// Merged from FontMono.HC + FontVector.HC. One module owns:
//   1. The 8x16 bitmap font (crisp small text) - delegates to Render's gfx_draw_char.
//   2. The analytical 95-glyph quadratic-Bezier outline table (32..126).
//   3. A boot-baked ANTI-ALIASED atlas: each glyph's outlines are rasterised at 4x
//      supersample, box-downsampled to 24x24 coverage, and packed into one
//      power-of-two ARGB texture (alpha = coverage, RGB = white).
//   4. Anti-aliased text: each glyph is sampled from the atlas with a bilinear
//      coverage read and alpha-composited straight into the framebuffer
//      (clip-safe, no GL state). The stroke outline is the scalable source; the
//      atlas is its boot-baked coverage, so text stays smooth at any size.
//
// The bitmap path (Render.HC gfx_draw_char) is UNTOUCHED, so the golden-frame
// hash 0xD28836F is preserved. The legacy FontVectorDrawString / MeasureString
// names are kept because DolDoc.HC late-binds to them.
//
// All arithmetic is integer or F64; no >8-arg calls (compiler limit).
// ==============================================================================


// ------------------------------------------------------------------------------
// Metrics (from FontMono.HC)
// ------------------------------------------------------------------------------
class CFontMetrics {
  I64 units_per_em;
  I64 ascent;
  I64 descent;
  I64 line_gap;
  I64 num_glyphs;
  I64 char_width;
  I64 line_height;
};
CFontMetrics g_font_metrics;

// ------------------------------------------------------------------------------
// Bitmap font (8x16, printable ASCII 32..126). The live data lives in C
// (font_get_8x16_data); Render.HC already renders it. We expose thin wrappers so
// small/crisp text has a single home.
// ------------------------------------------------------------------------------
U0 FontsDrawBitmapChar(I64 px, I64 py, U8 ch, U32 fg, U32 bg) {
  gfx_draw_char(px, py, ch, fg, bg);
}

U0 FontsDrawBitmapText(I64 px, I64 py, U8 *str, U32 fg, U32 bg) {
  gfx_draw_text(px, py, str, fg, bg);
}

// ------------------------------------------------------------------------------
// Vector outline engine (from FontVector.HC). Grid is 0..60 wide x 0..100 tall
// (descenders to ~120). FvLine/FvBez funnel into VectorDrawLine, which either
// draws to the screen (strokes) or rasterises into the supersample buffer (bake).
// ------------------------------------------------------------------------------
class CFvCtx {
  I64 ox;
  I64 oy;
  I64 scale_pct;
  U32 color;
};
CFvCtx g_fv;

// Analytical quadratic Bezier, 64-bit fixed point (scale = 1000).
I64 BezierEval1D(I64 p0, I64 p1, I64 p2, I64 t) {
  I64 be_u = 1000 - t;
  I64 be_term0 = be_u * be_u * p0;
  I64 be_term1 = 2 * be_u * t * p1;
  I64 be_term2 = t * t * p2;
  return (be_term0 + be_term1 + be_term2) / 1000000;
}

// ---- bake: supersample buffer + Bresenham ----
#define FONTS_SS 96           // 24 px cell * 4x supersample
U8 g_fonts_ss[FONTS_SS * FONTS_SS];
I64 g_fonts_bake = 0;         // 1 => VectorDrawLine rasterises into g_fonts_ss

// Plot a 4x4 (1 cell-px) block at each Bresenham step so strokes have unit width.
U0 FontsSsPlot(I64 x, I64 y) {
  I64 oy = 0;
  while (oy < 4) {
    I64 ox = 0;
    while (ox < 4) {
      I64 sx = x + ox;
      I64 sy = y + oy;
      if (sx >= 0 && sx < FONTS_SS && sy >= 0 && sy < FONTS_SS) {
        g_fonts_ss[sy * FONTS_SS + sx] = 1;
      }
      ox++;
    }
    oy++;
  }
}

U0 FontsSsLine(I64 x0, I64 y0, I64 x1, I64 y1) {
  I64 dx = x1 - x0; if (dx < 0) dx = -dx;
  I64 dy = y1 - y0; if (dy < 0) dy = -dy;
  I64 sx = 1; if (x0 > x1) sx = -1;
  I64 sy = 1; if (y0 > y1) sy = -1;
  I64 err = dx - dy;
  while (1) {
    FontsSsPlot(x0, y0);
    if (x0 == x1 && y0 == y1) break;
    I64 e2 = 2 * err;
    if (e2 > -dy) { err = err - dy; x0 = x0 + sx; }
    if (e2 < dx) { err = err + dx; y0 = y0 + sy; }
  }
}

U0 VectorDrawLine(I64 x0, I64 y0, I64 x1, I64 y1, U32 color) {
  if (g_fonts_bake != 0) { FontsSsLine(x0, y0, x1, y1); return; }
  gfx_draw_line(x0, y0, x1, y1, color);
}

U0 VectorDrawBezier(I64 p0x, I64 p0y, I64 p1x, I64 p1y, I64 p2x, I64 p2y, U32 color) {
  I64 vb_steps = 12;
  I64 vb_last_x = p0x;
  I64 vb_last_y = p0y;
  I64 vb_i = 1;
  while (vb_i <= vb_steps) {
    I64 vb_t = (vb_i * 1000) / vb_steps;
    I64 vb_cur_x = BezierEval1D(p0x, p1x, p2x, vb_t);
    I64 vb_cur_y = BezierEval1D(p0y, p1y, p2y, vb_t);
    VectorDrawLine(vb_last_x, vb_last_y, vb_cur_x, vb_cur_y, color);
    vb_last_x = vb_cur_x;
    vb_last_y = vb_cur_y;
    vb_i++;
  }
}

// Grid -> device mapping. At scale_pct == 100, 100 grid units = 20 pixels.
I64 FvMapX(I64 gx) {
  return g_fv.ox + (gx * g_fv.scale_pct) / 500;
}

I64 FvMapY(I64 gy) {
  return g_fv.oy + (gy * g_fv.scale_pct) / 500;
}

U0 FvLine(I64 x0, I64 y0, I64 x1, I64 y1) {
  VectorDrawLine(FvMapX(x0), FvMapY(y0), FvMapX(x1), FvMapY(y1), g_fv.color);
}

U0 FvBez(I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2) {
  VectorDrawBezier(FvMapX(x0), FvMapY(y0), FvMapX(x1), FvMapY(y1), FvMapX(x2), FvMapY(y2), g_fv.color);
}

U0 FvArcTop(I64 cx, I64 cy, I64 rx, I64 ry) {
  FvBez(cx - rx, cy, cx - rx, cy - ry, cx, cy - ry);
  FvBez(cx, cy - ry, cx + rx, cy - ry, cx + rx, cy);
}

U0 FvArcBot(I64 cx, I64 cy, I64 rx, I64 ry) {
  FvBez(cx + rx, cy, cx + rx, cy + ry, cx, cy + ry);
  FvBez(cx, cy + ry, cx - rx, cy + ry, cx - rx, cy);
}

U0 FvArcLeft(I64 cx, I64 cy, I64 rx, I64 ry) {
  FvBez(cx, cy - ry, cx - rx, cy - ry, cx - rx, cy);
  FvBez(cx - rx, cy, cx - rx, cy + ry, cx, cy + ry);
}

U0 FvArcRight(I64 cx, I64 cy, I64 rx, I64 ry) {
  FvBez(cx, cy - ry, cx + rx, cy - ry, cx + rx, cy);
  FvBez(cx + rx, cy, cx + rx, cy + ry, cx, cy + ry);
}

U0 FvOval(I64 cx, I64 cy, I64 rx, I64 ry) {
  FvArcTop(cx, cy, rx, ry);
  FvArcBot(cx, cy, rx, ry);
}

U0 FvDot(I64 cx, I64 cy) {
  FvLine(cx - 3, cy, cx + 3, cy);
  FvLine(cx, cy - 3, cx, cy + 3);
}

// Render any printable ASCII character (32..126) using analytical vector curves.
U0 FontVectorDrawChar(I64 x, I64 y, U8 ch, I64 scale_pct, U32 color) {
  if (scale_pct < 20) scale_pct = 20;
  g_fv.ox = x;
  g_fv.oy = y;
  g_fv.scale_pct = scale_pct;
  g_fv.color = color;

  if (ch <= 32 || ch > 126) return;

  // Uppercase A-Z (65..90)
  if (ch == 'A') {
    FvLine(5, 100, 30, 0); FvLine(30, 0, 55, 100); FvLine(14, 65, 46, 65);
  } else if (ch == 'B') {
    FvLine(8, 0, 8, 100); FvLine(8, 0, 34, 0); FvLine(8, 48, 36, 48); FvLine(8, 100, 36, 100);
    FvArcRight(34, 24, 20, 24); FvArcRight(36, 74, 22, 26);
  } else if (ch == 'C') {
    FvBez(54, 20, 48, 0, 30, 0); FvArcLeft(30, 50, 24, 50); FvBez(30, 100, 48, 100, 54, 80);
  } else if (ch == 'D') {
    FvLine(8, 0, 8, 100); FvLine(8, 0, 28, 0); FvLine(8, 100, 28, 100); FvArcRight(28, 50, 26, 50);
  } else if (ch == 'E') {
    FvLine(8, 0, 8, 100); FvLine(8, 0, 54, 0); FvLine(8, 48, 44, 48); FvLine(8, 100, 54, 100);
  } else if (ch == 'F') {
    FvLine(8, 0, 8, 100); FvLine(8, 0, 54, 0); FvLine(8, 48, 44, 48);
  } else if (ch == 'G') {
    FvBez(54, 20, 48, 0, 30, 0); FvArcLeft(30, 50, 24, 50);
    FvBez(30, 100, 54, 100, 54, 65); FvLine(54, 65, 54, 52); FvLine(32, 52, 54, 52);
  } else if (ch == 'H') {
    FvLine(8, 0, 8, 100); FvLine(52, 0, 52, 100); FvLine(8, 48, 52, 48);
  } else if (ch == 'I') {
    FvLine(14, 0, 46, 0); FvLine(30, 0, 30, 100); FvLine(14, 100, 46, 100);
  } else if (ch == 'J') {
    FvLine(20, 0, 52, 0); FvLine(44, 0, 44, 72); FvArcBot(26, 72, 18, 28);
  } else if (ch == 'K') {
    FvLine(8, 0, 8, 100); FvLine(52, 0, 8, 54); FvLine(22, 38, 54, 100);
  } else if (ch == 'L') {
    FvLine(8, 0, 8, 100); FvLine(8, 100, 54, 100);
  } else if (ch == 'M') {
    FvLine(6, 100, 6, 0); FvLine(6, 0, 30, 55); FvLine(30, 55, 54, 0); FvLine(54, 0, 54, 100);
  } else if (ch == 'N') {
    FvLine(8, 100, 8, 0); FvLine(8, 0, 52, 100); FvLine(52, 100, 52, 0);
  } else if (ch == 'O') {
    FvOval(30, 50, 24, 50);
  } else if (ch == 'P') {
    FvLine(8, 0, 8, 100); FvLine(8, 0, 34, 0); FvLine(8, 52, 34, 52); FvArcRight(34, 26, 20, 26);
  } else if (ch == 'Q') {
    FvOval(30, 48, 24, 48); FvLine(34, 72, 56, 102);
  } else if (ch == 'R') {
    FvLine(8, 0, 8, 100); FvLine(8, 0, 34, 0); FvLine(8, 50, 34, 50);
    FvArcRight(34, 25, 20, 25); FvLine(32, 50, 54, 100);
  } else if (ch == 'S') {
    FvBez(52, 18, 50, 0, 28, 0); FvBez(28, 0, 6, 0, 8, 26);
    FvBez(8, 26, 10, 46, 30, 50); FvBez(30, 50, 52, 54, 54, 76);
    FvBez(54, 76, 54, 100, 30, 100); FvBez(30, 100, 8, 100, 6, 80);
  } else if (ch == 'T') {
    FvLine(4, 0, 56, 0); FvLine(30, 0, 30, 100);
  } else if (ch == 'U') {
    FvLine(8, 0, 8, 68); FvLine(52, 0, 52, 68); FvArcBot(30, 68, 22, 32);
  } else if (ch == 'V') {
    FvLine(6, 0, 30, 100); FvLine(30, 100, 54, 0);
  } else if (ch == 'W') {
    FvLine(4, 0, 16, 100); FvLine(16, 100, 30, 42); FvLine(30, 42, 44, 100); FvLine(44, 100, 56, 0);
  } else if (ch == 'X') {
    FvLine(6, 0, 54, 100); FvLine(54, 0, 6, 100);
  } else if (ch == 'Y') {
    FvLine(6, 0, 30, 50); FvLine(54, 0, 30, 50); FvLine(30, 50, 30, 100);
  } else if (ch == 'Z') {
    FvLine(6, 0, 54, 0); FvLine(54, 0, 6, 100); FvLine(6, 100, 54, 100);
  }
  // Lowercase a-z (97..122)
  else if (ch == 'a') {
    FvBez(12, 46, 18, 32, 34, 32); FvBez(34, 32, 50, 32, 50, 52);
    FvLine(50, 52, 50, 100); FvOval(30, 78, 20, 20);
  } else if (ch == 'b') {
    FvLine(10, 0, 10, 100); FvOval(30, 68, 20, 32);
  } else if (ch == 'c') {
    FvBez(50, 48, 44, 34, 30, 34); FvArcLeft(30, 67, 20, 33); FvBez(30, 100, 44, 100, 50, 86);
  } else if (ch == 'd') {
    FvLine(50, 0, 50, 100); FvOval(30, 68, 20, 32);
  } else if (ch == 'e') {
    FvLine(10, 66, 50, 66); FvArcTop(30, 66, 20, 32);
    FvBez(10, 66, 10, 100, 30, 100); FvBez(30, 100, 46, 100, 50, 86);
  } else if (ch == 'f') {
    FvBez(46, 8, 36, 0, 26, 0); FvBez(26, 0, 18, 0, 18, 22);
    FvLine(18, 22, 18, 100); FvLine(6, 38, 38, 38);
  } else if (ch == 'g') {
    FvOval(30, 66, 20, 30); FvLine(50, 36, 50, 102); FvArcBot(30, 102, 20, 18);
  } else if (ch == 'h') {
    FvLine(10, 0, 10, 100); FvArcTop(30, 56, 20, 22); FvLine(50, 56, 50, 100);
  } else if (ch == 'i') {
    FvDot(30, 14); FvLine(22, 36, 30, 36); FvLine(30, 36, 30, 100); FvLine(18, 100, 42, 100);
  } else if (ch == 'j') {
    FvDot(38, 14); FvLine(26, 36, 38, 36); FvLine(38, 36, 38, 102); FvArcBot(24, 102, 14, 18);
  } else if (ch == 'k') {
    FvLine(10, 0, 10, 100); FvLine(48, 36, 10, 70); FvLine(24, 58, 50, 100);
  } else if (ch == 'l') {
    FvLine(20, 0, 30, 0); FvLine(30, 0, 30, 100); FvLine(18, 100, 42, 100);
  } else if (ch == 'm') {
    FvLine(6, 36, 6, 100); FvArcTop(18, 54, 12, 18); FvLine(30, 54, 30, 100);
    FvArcTop(42, 54, 12, 18); FvLine(54, 54, 54, 100);
  } else if (ch == 'n') {
    FvLine(10, 36, 10, 100); FvArcTop(30, 56, 20, 20); FvLine(50, 56, 50, 100);
  } else if (ch == 'o') {
    FvOval(30, 68, 20, 32);
  } else if (ch == 'p') {
    FvLine(10, 36, 10, 120); FvOval(30, 68, 20, 32);
  } else if (ch == 'q') {
    FvLine(50, 36, 50, 120); FvOval(30, 68, 20, 32);
  } else if (ch == 'r') {
    FvLine(14, 36, 14, 100); FvBez(14, 56, 20, 36, 44, 36);
  } else if (ch == 's') {
    FvBez(48, 46, 44, 34, 28, 34); FvBez(28, 34, 10, 34, 10, 50);
    FvBez(10, 50, 10, 64, 30, 66); FvBez(30, 66, 50, 68, 50, 84);
    FvBez(50, 84, 50, 100, 28, 100); FvBez(28, 100, 12, 100, 8, 86);
  } else if (ch == 't') {
    FvLine(26, 10, 26, 86); FvBez(26, 86, 26, 100, 44, 100); FvLine(12, 36, 44, 36);
  } else if (ch == 'u') {
    FvLine(10, 36, 10, 78); FvArcBot(30, 78, 20, 22); FvLine(50, 36, 50, 100);
  } else if (ch == 'v') {
    FvLine(8, 36, 30, 100); FvLine(30, 100, 52, 36);
  } else if (ch == 'w') {
    FvLine(4, 36, 16, 100); FvLine(16, 100, 30, 58); FvLine(30, 58, 44, 100); FvLine(44, 100, 56, 36);
  } else if (ch == 'x') {
    FvLine(10, 36, 50, 100); FvLine(50, 36, 10, 100);
  } else if (ch == 'y') {
    FvLine(10, 36, 30, 96); FvLine(50, 36, 18, 120);
  } else if (ch == 'z') {
    FvLine(10, 36, 50, 36); FvLine(50, 36, 10, 100); FvLine(10, 100, 50, 100);
  }
  // Digits 0-9 (48..57)
  else if (ch == '0') {
    FvOval(30, 50, 22, 50); FvLine(14, 82, 46, 18);
  } else if (ch == '1') {
    FvLine(14, 20, 32, 0); FvLine(32, 0, 32, 100); FvLine(14, 100, 50, 100);
  } else if (ch == '2') {
    FvArcTop(30, 26, 22, 26); FvLine(52, 26, 8, 100); FvLine(8, 100, 54, 100);
  } else if (ch == '3') {
    FvBez(10, 16, 16, 0, 32, 0); FvArcRight(32, 24, 20, 24);
    FvLine(22, 48, 32, 48); FvArcRight(32, 74, 22, 26); FvBez(32, 100, 14, 100, 8, 82);
  } else if (ch == '4') {
    FvLine(40, 0, 6, 68); FvLine(6, 68, 56, 68); FvLine(40, 0, 40, 100);
  } else if (ch == '5') {
    FvLine(50, 0, 10, 0); FvLine(10, 0, 10, 44); FvLine(10, 44, 32, 44);
    FvArcRight(32, 72, 22, 28); FvBez(32, 100, 14, 100, 8, 84);
  } else if (ch == '6') {
    FvBez(48, 12, 40, 0, 28, 0); FvArcLeft(30, 50, 22, 50); FvOval(30, 72, 22, 28);
  } else if (ch == '7') {
    FvLine(8, 0, 54, 0); FvLine(54, 0, 20, 100);
  } else if (ch == '8') {
    FvOval(30, 24, 20, 24); FvOval(30, 74, 22, 26);
  } else if (ch == '9') {
    FvOval(30, 28, 22, 28); FvArcRight(30, 50, 22, 50); FvBez(30, 100, 16, 100, 10, 86);
  }
  // Punctuation & Mathematical Symbols
  else if (ch == '!') {
    FvLine(30, 0, 30, 72); FvDot(30, 96);
  } else if (ch == '"') {
    FvLine(20, 0, 18, 28); FvLine(40, 0, 38, 28);
  } else if (ch == '#') {
    FvLine(20, 10, 14, 90); FvLine(44, 10, 38, 90); FvLine(6, 36, 54, 36); FvLine(6, 64, 54, 64);
  } else if (ch == '$') {
    FvLine(30, -6, 30, 108);
    FvBez(48, 22, 46, 8, 28, 8); FvBez(28, 8, 10, 8, 10, 30);
    FvBez(10, 30, 10, 48, 30, 50); FvBez(30, 50, 50, 52, 50, 72);
    FvBez(50, 72, 50, 92, 30, 92); FvBez(30, 92, 12, 92, 10, 78);
  } else if (ch == '%') {
    FvLine(10, 96, 50, 4); FvOval(16, 20, 10, 14); FvOval(44, 80, 10, 14);
  } else if (ch == '&') {
    FvOval(26, 22, 14, 18); FvBez(18, 40, 6, 54, 6, 74);
    FvBez(6, 74, 6, 100, 26, 100); FvBez(26, 100, 42, 100, 52, 62);
    FvLine(18, 38, 54, 100);
  } else if (ch == 39) {
    FvLine(30, 0, 26, 28);
  } else if (ch == '(') {
    FvBez(42, 0, 14, 24, 14, 52); FvBez(14, 52, 14, 80, 42, 104);
  } else if (ch == ')') {
    FvBez(18, 0, 46, 24, 46, 52); FvBez(46, 52, 46, 80, 18, 104);
  } else if (ch == '*') {
    FvLine(30, 16, 30, 64); FvLine(10, 26, 50, 54); FvLine(50, 26, 10, 54);
  } else if (ch == '+') {
    FvLine(8, 50, 52, 50); FvLine(30, 22, 30, 78);
  } else if (ch == ',') {
    FvDot(30, 94); FvLine(32, 94, 22, 114);
  } else if (ch == '-') {
    FvLine(10, 50, 50, 50);
  } else if (ch == '.') {
    FvDot(30, 96);
  } else if (ch == '/') {
    FvLine(10, 100, 50, 0);
  } else if (ch == ':') {
    FvDot(30, 38); FvDot(30, 92);
  } else if (ch == ';') {
    FvDot(30, 38); FvDot(30, 92); FvLine(32, 92, 22, 112);
  } else if (ch == '<') {
    FvLine(48, 20, 12, 50); FvLine(12, 50, 48, 80);
  } else if (ch == '=') {
    FvLine(10, 36, 50, 36); FvLine(10, 64, 50, 64);
  } else if (ch == '>') {
    FvLine(12, 20, 48, 50); FvLine(48, 50, 12, 80);
  } else if (ch == '?') {
    FvArcTop(30, 24, 20, 24); FvBez(50, 24, 50, 44, 30, 54);
    FvLine(30, 54, 30, 72); FvDot(30, 96);
  } else if (ch == '@') {
    FvOval(30, 54, 12, 16); FvLine(42, 38, 42, 68);
    FvBez(42, 68, 54, 68, 54, 48); FvArcTop(30, 48, 24, 38);
    FvArcLeft(30, 52, 24, 42); FvBez(30, 94, 46, 94, 52, 84);
  } else if (ch == '[') {
    FvLine(42, 0, 20, 0); FvLine(20, 0, 20, 104); FvLine(20, 104, 42, 104);
  } else if (ch == 92) {
    FvLine(10, 0, 50, 100);
  } else if (ch == ']') {
    FvLine(18, 0, 40, 0); FvLine(40, 0, 40, 104); FvLine(40, 104, 18, 104);
  } else if (ch == '^') {
    FvLine(10, 38, 30, 4); FvLine(30, 4, 50, 38);
  } else if (ch == '_') {
    FvLine(4, 104, 56, 104);
  } else if (ch == '`') {
    FvLine(22, 0, 36, 22);
  } else if (ch == '{') {
    FvBez(42, 0, 26, 0, 26, 18); FvLine(26, 18, 26, 40);
    FvBez(26, 40, 26, 52, 12, 52); FvBez(12, 52, 26, 52, 26, 64);
    FvLine(26, 64, 26, 86); FvBez(26, 86, 26, 104, 42, 104);
  } else if (ch == '|') {
    FvLine(30, -4, 30, 108);
  } else if (ch == '}') {
    FvBez(18, 0, 34, 0, 34, 18); FvLine(34, 18, 34, 40);
    FvBez(34, 40, 34, 52, 48, 52); FvBez(48, 52, 34, 52, 34, 64);
    FvLine(34, 64, 34, 86); FvBez(34, 86, 34, 104, 18, 104);
  } else if (ch == '~') {
    FvBez(6, 56, 18, 34, 30, 50); FvBez(30, 50, 42, 66, 54, 44);
  }
}

// ------------------------------------------------------------------------------
// Boot-baked AA atlas.
//   CELL = 24 px per glyph; 10x10 cells -> 256x256 PoT ARGB texture.
//   Bake scale: 4x supersample (96x96) at cell scale_pct 90 => ox=24, oy=4.
//   Cell scale_pct 90 maps grid y 0..100 -> cell y 2..20 (em height 18 px);
//   at draw time k = scale_pct/90 screen px per cell px.
// ------------------------------------------------------------------------------
#define FONTS_CELL 24
#define FONTS_ATLAS_W 256
#define FONTS_ATLAS_H 256
U32 g_font_atlas[FONTS_ATLAS_W * FONTS_ATLAS_H];
I64 g_fonts_baked = 0;

U0 FontsBakeGlyph(U8 ch, I64 ax, I64 ay) {
  I64 s = 0;
  while (s < FONTS_SS * FONTS_SS) { g_fonts_ss[s] = 0; s++; }
  g_fonts_bake = 1;
  // 4x scale (cell scale_pct 90 * 4 = 360); ox=24, oy=4 places grid 0..100 in-cell.
  FontVectorDrawChar(24, 4, ch, 360, 0xFFFFFFFF);
  g_fonts_bake = 0;
  I64 cy = 0;
  while (cy < FONTS_CELL) {
    I64 cx = 0;
    while (cx < FONTS_CELL) {
      I64 sum = 0;
      I64 sy = 0;
      while (sy < 4) {
        I64 sx = 0;
        while (sx < 4) {
          if (g_fonts_ss[(cy * 4 + sy) * FONTS_SS + (cx * 4 + sx)] != 0) sum++;
          sx++;
        }
        sy++;
      }
      I64 cov = (sum * 255) / 16;
      g_font_atlas[(ay + cy) * FONTS_ATLAS_W + (ax + cx)] = ((U64)cov << 24) | 0x00FFFFFF;
      cx++;
    }
    cy++;
  }
}

U0 FontsInit() {
  g_font_metrics.units_per_em = 1000;
  g_font_metrics.ascent = 800;
  g_font_metrics.descent = -200;
  g_font_metrics.line_gap = 100;
  g_font_metrics.num_glyphs = 95;
  g_font_metrics.char_width = 8;
  g_font_metrics.line_height = 16;
  I64 g = 0;
  while (g < 95) {
    I64 col = g % 10;
    I64 row = g / 10;
    FontsBakeGlyph((U8)(g + 32), col * FONTS_CELL, row * FONTS_CELL);
    g++;
  }
  g_fonts_baked = 1;
}

// ------------------------------------------------------------------------------
// SDF/AA text composited as textured quads through the one rasterizer.
// ------------------------------------------------------------------------------
// Composite one glyph from the baked atlas straight into the framebuffer with a
// bilinear (anti-aliased) coverage sample. Clip-safe; no GL state involved.
I64 FontsFloorF(F64 v) {
  I64 fi = (I64)v;
  if ((F64)fi > v) fi = fi - 1;
  return fi;
}

U0 FontsDrawGlyphSdf(I64 x, I64 y, I64 scale_pct, U8 ch, U32 color) {
  if (ch < 32 || ch > 126) return;
  U32 *fb = RenderGetTargetBuffer();
  I64 pit = gfx_get_canvas_pitch();
  I64 W = gfx_get_canvas_width();
  I64 H = gfx_get_canvas_height();
  if (!fb || W <= 0 || H <= 0) return;
  I64 i = ch - 32;
  I64 col = i % 10;
  I64 row = i / 10;
  // k = screen px per cell px = scale_pct/90; grid(0,0) sits at cell (6,2).
  I64 qx0 = x - (6 * scale_pct) / 90;
  I64 qy0 = y - (2 * scale_pct) / 90;
  I64 cell = (FONTS_CELL * scale_pct) / 90;
  if (cell < 1) cell = 1;
  I64 cr = (color >> 16) & 255;
  I64 cg = (color >> 8) & 255;
  I64 cb = color & 255;
  F64 sc = (F64)FONTS_CELL / (F64)cell;   // atlas texels per screen px
  I64 sy = qy0;
  while (sy < qy0 + cell) {
    if (sy >= 0 && sy < H) {
      F64 av = (F64)(row * FONTS_CELL) + ((F64)(sy - qy0) + 0.5) * sc - 0.5;
      I64 av0 = FontsFloorF(av);
      F64 fv = av - (F64)av0;
      if (av0 < 0) { av0 = 0; fv = 0.0; }
      if (av0 > FONTS_ATLAS_H - 2) { av0 = FONTS_ATLAS_H - 2; fv = 1.0; }
      I64 sx = qx0;
      while (sx < qx0 + cell) {
        if (sx >= 0 && sx < W) {
          F64 au = (F64)(col * FONTS_CELL) + ((F64)(sx - qx0) + 0.5) * sc - 0.5;
          I64 au0 = FontsFloorF(au);
          F64 fu = au - (F64)au0;
          if (au0 < 0) { au0 = 0; fu = 0.0; }
          if (au0 > FONTS_ATLAS_W - 2) { au0 = FONTS_ATLAS_W - 2; fu = 1.0; }
          I64 a00 = (g_font_atlas[av0 * FONTS_ATLAS_W + au0] >> 24) & 255;
          I64 a10 = (g_font_atlas[av0 * FONTS_ATLAS_W + au0 + 1] >> 24) & 255;
          I64 a01 = (g_font_atlas[(av0 + 1) * FONTS_ATLAS_W + au0] >> 24) & 255;
          I64 a11 = (g_font_atlas[(av0 + 1) * FONTS_ATLAS_W + au0 + 1] >> 24) & 255;
          F64 a0 = (F64)a00 + ((F64)a10 - (F64)a00) * fu;
          F64 a1 = (F64)a01 + ((F64)a11 - (F64)a01) * fu;
          F64 cov = a0 + (a1 - a0) * fv;
          I64 al = (I64)(cov + 0.5);
          if (al > 0) {
            U32 dst = fb[sy * pit + sx];
            I64 dr = (dst >> 16) & 255;
            I64 dg = (dst >> 8) & 255;
            I64 db = dst & 255;
            I64 o_r = (cr * al + dr * (255 - al)) / 255;
            I64 o_g = (cg * al + dg * (255 - al)) / 255;
            I64 o_b = (cb * al + db * (255 - al)) / 255;
            fb[sy * pit + sx] = 0xFF000000 | (o_r << 16) | (o_g << 8) | o_b;
          }
        }
        sx++;
      }
    }
    sy++;
  }
}

// Stroke fallback (used before the atlas is baked).
U0 FontsStrokeString(I64 x, I64 y, U8 *str, I64 scale_pct, U32 color) {
  if (!str) return;
  if (scale_pct < 20) scale_pct = 20;
  I64 adv_x = FontVectorCharAdvance(scale_pct);
  I64 adv_y = (130 * scale_pct) / 500;
  if (adv_y < 8) adv_y = 8;
  I64 cur_x = x;
  I64 cur_y = y;
  I64 i = 0;
  while (str[i] != 0) {
    U8 ch = str[i];
    if (ch == '\n') { cur_x = x; cur_y = cur_y + adv_y; }
    else if (ch == ' ') { cur_x = cur_x + adv_x; }
    else { FontVectorDrawChar(cur_x, cur_y, ch, scale_pct, color); cur_x = cur_x + adv_x; }
    i++;
  }
}

U0 FontsDrawSdfText(I64 x, I64 y, U8 *str, I64 scale_pct, U32 color) {
  if (!str) return;
  if (scale_pct < 20) scale_pct = 20;
  if (g_fonts_baked == 0) { FontsStrokeString(x, y, str, scale_pct, color); return; }
  I64 adv_x = FontVectorCharAdvance(scale_pct);
  I64 adv_y = (130 * scale_pct) / 500;
  if (adv_y < 8) adv_y = 8;
  I64 cur_x = x;
  I64 cur_y = y;
  I64 i = 0;
  while (str[i] != 0) {
    U8 ch = str[i];
    if (ch == '\n') { cur_x = x; cur_y = cur_y + adv_y; }
    else if (ch == ' ') { cur_x = cur_x + adv_x; }
    else { FontsDrawGlyphSdf(cur_x, cur_y, scale_pct, ch, color); cur_x = cur_x + adv_x; }
    i++;
  }
}

// ------------------------------------------------------------------------------
// Public metrics + legacy API (DolDoc late-binds to FontVectorDrawString).
// ------------------------------------------------------------------------------
I64 FontVectorCharAdvance(I64 scale_pct) {
  if (scale_pct < 20) scale_pct = 20;
  I64 adv = (72 * scale_pct) / 500;
  if (adv < 4) adv = 4;
  return adv;
}

I64 FontVectorMeasureString(U8 *str, I64 scale_pct) {
  if (!str) return 0;
  I64 fvm_adv = FontVectorCharAdvance(scale_pct);
  I64 fvm_max_w = 0;
  I64 fvm_cur_w = 0;
  I64 fvm_m = 0;
  while (str[fvm_m] != 0) {
    if (str[fvm_m] == '\n') {
      if (fvm_cur_w > fvm_max_w) fvm_max_w = fvm_cur_w;
      fvm_cur_w = 0;
    } else {
      fvm_cur_w = fvm_cur_w + fvm_adv;
    }
    fvm_m++;
  }
  if (fvm_cur_w > fvm_max_w) fvm_max_w = fvm_cur_w;
  return fvm_max_w;
}

U0 FontVectorDrawString(I64 x, I64 y, U8 *str, I64 scale_pct, U32 color) {
  FontsDrawSdfText(x, y, str, scale_pct, color);
}

// Convenience: pixel height variant (h px em-height; scale_pct = h*5).
U0 FontsDrawText(I64 x, I64 y, U8 *str, I64 px_height, U32 color) {
  FontsDrawSdfText(x, y, str, px_height * 5, color);
}

// ------------------------------------------------------------------------------
// In-guest self-test: bake integrity + a real AA composite through the rasterizer.
// ------------------------------------------------------------------------------
U0 FontsSelfTest() {
  doldoc_print("\n$FG,CYAN$=== NeoOS Fonts (bitmap + vector + AA atlas) ===$FG$\n");
  I64 ok = 1;
  if (g_fonts_baked == 0) { FontsInit(); }
  if (g_fonts_baked == 0) ok = 0;

  // 1. Atlas has ink: the 'A' cell must contain non-zero coverage.
  I64 ai = ('A' - 32);
  I64 aax = (ai % 10) * FONTS_CELL;
  I64 aay = (ai / 10) * FONTS_CELL;
  I64 ink = 0;
  I64 yy = 0;
  while (yy < FONTS_CELL) {
    I64 xx = 0;
    while (xx < FONTS_CELL) {
      if ((g_font_atlas[(aay + yy) * FONTS_ATLAS_W + (aax + xx)] >> 24) != 0) ink++;
      xx++;
    }
    yy++;
  }
  if (ink > 20) doldoc_printf("  $FG,GREEN$[PASS]$FG$ atlas baked, 'A' coverage texels=%lld\n", ink);
  else { doldoc_printf("  $FG,RED$[FAIL]$FG$ atlas ink too low (%lld)\n", ink); ok = 0; }

  // 2. Metrics.
  if (g_font_metrics.char_width == 8 && g_font_metrics.line_height == 16 &&
      FontVectorMeasureString("NeoOS", 500) == 5 * FontVectorCharAdvance(500)) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ metrics verified (8x16 bitmap, vector advance)\n");
  } else { doldoc_print("  $FG,RED$[FAIL]$FG$ metrics invalid\n"); ok = 0; }

  // 3. Real AA composite: draw a glyph big through the one rasterizer and verify
  //    anti-aliased (intermediate) coverage appears.
  U32 *fb = RenderGetTargetBuffer();
  I64 pit = gfx_get_canvas_pitch();
  I64 W = gfx_get_canvas_width();
  I64 H = gfx_get_canvas_height();
  if (fb && W > 0 && H > 0) {
    I64 bx = W / 2 - 60;
    I64 by = H / 2;
    gfx_clear(0xFF000000);
    FontsDrawSdfText(bx, by, "W", 400, 0xFF00FF00);   // em height 80 px
    I64 aa = 0;
    I64 ink = 0;
    I64 gmax = 0;
    I64 ry = 0;
    while (ry < 80) {
      I64 rx = 0;
      while (rx < 80) {
        I64 sx = bx + rx;
        I64 sy = by + ry;
        if (sx >= 0 && sx < W && sy >= 0 && sy < H) {
          I64 g = (fb[sy * pit + sx] >> 8) & 255;
          if (g > 0) ink++;
          if (g > 0 && g < 255) aa++;
          if (g > gmax) gmax = g;
        }
        rx++;
      }
      ry++;
    }
    I64 wi = ('W' - 32);
    I64 wx = (wi % 10) * FONTS_CELL;
    I64 wy = (wi / 10) * FONTS_CELL;
    I64 wink = 0;
    I64 wyy = 0;
    while (wyy < FONTS_CELL) {
      I64 wxx = 0;
      while (wxx < FONTS_CELL) {
        if (((g_font_atlas[(wy + wyy) * FONTS_ATLAS_W + (wx + wxx)] >> 24) & 255) != 0) wink++;
        wxx++;
      }
      wyy++;
    }
    if (aa > 20 && gmax > 150) doldoc_printf("  $FG,GREEN$[PASS]$FG$ AA composite (ink=%lld aa=%lld peak=%lld)\n", ink, aa, gmax);
    else { doldoc_printf("  $FG,RED$[FAIL]$FG$ AA composite (ink=%lld aa=%lld peak=%lld)\n", ink, aa, gmax); ok = 0; }
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();
  } else { ok = 0; }

  if (ok != 0) doldoc_print("FONTS: PASS\n");
  else doldoc_print("FONTS: FAIL\n");
}

// Boot tail: bake the atlas during boot; self-test when loaded from the shell.
if (g_kernel_booting) {
  FontsInit();
} else {
  FontsSelfTest();
}
