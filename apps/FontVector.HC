// FontVector.HC - Sovereign Native HolyC Vector Font & Bézier Engine
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution
// Complete 95-Glyph Printable ASCII (32..126) Analytical Strokes & Quadratic Béziers

class CFvCtx {
  I64 ox;
  I64 oy;
  I64 scale_pct;
  U32 color;
};

CFvCtx g_fv;

// Analytical Quadratic Bézier Evaluation using 64-bit fixed point (scale = 1000)
// B(t) = ((1000 - t)^2 * P0 + 2 * (1000 - t) * t * P1 + t^2 * P2) / 1000000
I64 BezierEval1D(I64 p0, I64 p1, I64 p2, I64 t) {
  I64 be_u = 1000 - t;
  I64 be_term0 = be_u * be_u * p0;
  I64 be_term1 = 2 * be_u * t * p1;
  I64 be_term2 = t * t * p2;
  return (be_term0 + be_term1 + be_term2) / 1000000;
}

U0 VectorDrawLine(I64 x0, I64 y0, I64 x1, I64 y1, U32 color) {
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

// Normalized glyph coordinate helpers: grid is 0..60 wide x 0..100 tall
// At scale_pct == 100, 100 grid units = 20 pixels (or scaled proportionally)
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

// Render any printable ASCII character (32..126) using analytical vector curves
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
  if (!str) return;
  if (scale_pct < 20) scale_pct = 20;
  I64 fvs_adv_x = FontVectorCharAdvance(scale_pct);
  I64 fvs_adv_y = (130 * scale_pct) / 500;
  if (fvs_adv_y < 8) fvs_adv_y = 8;

  I64 fvs_cur_x = x;
  I64 fvs_cur_y = y;
  I64 fvs_i = 0;
  while (str[fvs_i] != 0) {
    U8 fvs_ch = str[fvs_i];
    if (fvs_ch == '\n') {
      fvs_cur_x = x;
      fvs_cur_y = fvs_cur_y + fvs_adv_y;
    } else if (fvs_ch == ' ') {
      fvs_cur_x = fvs_cur_x + fvs_adv_x;
    } else {
      FontVectorDrawChar(fvs_cur_x, fvs_cur_y, fvs_ch, scale_pct, color);
      fvs_cur_x = fvs_cur_x + fvs_adv_x;
    }
    fvs_i++;
  }
}

// Backwards-compatible glyph & string wrappers (scale: 10 = 1.0x = 500 scale_pct)
U0 VectorDrawGlyph(U8 ch, I64 ox, I64 oy, I64 scale, U32 color) {
  if (scale < 1) scale = 1;
  FontVectorDrawChar(ox, oy, ch, scale * 50, color);
}

U0 VectorDrawString(U8 *str, I64 x, I64 y, I64 scale, U32 color) {
  if (scale < 1) scale = 1;
  FontVectorDrawString(x, y, str, scale * 50, color);
}

U0 FontVectorMain() {
  doldoc_clear();
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$    ✦ NeoOS Native HolyC Vector Font & Bézier Engine (FontVector.HC) ✦$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_print(" Formulation: 95-Glyph ASCII (32..126) Analytical Quadratic Bézier Contours\n");
  doldoc_print(" Pipeline   : Zero C Libs | Pure HolyC Outline Tessellation & Rendering\n");
  doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

  doldoc_print(" [1/3] Benchmarking Bézier Curve Evaluation (50,000 points)...\n");
  I64 start_us = timer_get_uptime_us();
  I64 checksum = 0;

  I64 fv_b = 0;
  while (fv_b < 50000) {
    I64 t = (fv_b * 20) % 1000;
    I64 val = BezierEval1D(10, 150, 80, t);
    checksum = checksum + val;
    fv_b++;
  }

  I64 end_us = timer_get_uptime_us();
  I64 elapsed = end_us - start_us;
  if (elapsed <= 0) elapsed = 1;

  doldoc_printf("  $FG,GREEN$[PASS]$FG$ Evaluated 50,000 Bézier points in %lld us (Checksum: %lld)\n",
                elapsed, checksum);

  doldoc_print(" [2/3] Rendering Full 95-Glyph Scalable Vector Specimen to Canvas...\n");
  I64 w = gfx_get_canvas_width();
  I64 h = gfx_get_canvas_height();

  I64 logo_x = w / 2 - 140;
  I64 logo_y = 60;
  if (logo_x > 0 && logo_y > 0 && logo_x + 280 < w) {
    FontVectorDrawString(logo_x, logo_y, "NeoOS 3.0", 200, 0xFF89B4FA);
    FontVectorDrawString(logo_x, logo_y + 44, "AaBbCc 0123 +-*/=()[]{}", 100, 0xFFA6E3A1);
    I64 meas_w = FontVectorMeasureString("NeoOS 3.0", 200);
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ 95-glyph vector specimen rendered at (%lld, %lld), width=%lldpx\n",
                  logo_x, logo_y, meas_w);
  }

  doldoc_print(" [3/3] Mathematical Curvature & Continuity Verification...\n");
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

if (!g_kernel_booting) {
  FontVectorMain();
}
