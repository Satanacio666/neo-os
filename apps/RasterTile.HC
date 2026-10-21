// ==============================================================================
// apps/RasterTile.HC - NeoOS single rasterizer (P4.2 / p4.2b)
// ------------------------------------------------------------------------------
// The ONE triangle rasterizer for the whole system (2D fills and HolyGL 3D both
// go through RasterTriangleZ). Properties:
//   * Real per-pixel Z: a single full-screen 16-bit depth buffer owned here.
//   * Juan Pineda edge functions, exact integer arithmetic (bit-exact coverage).
//   * Top-left fill rule: shared mesh edges are drawn exactly once.
//   * Deterministic row-major scan, identical on 1 vs N cores.
//
// p4.2b: each scanline is split head(scalar) | body(NEON, 8 px/iter) | tail(scalar).
// The NEON body (RasterSpanNEON) vectorizes the 3 biased edge tests, the 8-lane
// depth compare (CMHI.8H) and the masked Z + framebuffer stores, while the depth
// numerator/division stays EXACT 64-bit (8 scalar SDIV per block) so the Z written
// to the buffer is bit-identical to the scalar path.
//
// P4.2 depended on a Compiler.HC fix: indexing a global POINTER must stride by
// and load/store sizeof(pointee) (HcResolveLValue / HcRegisterGlobalScale).
// RasterBootCheck (below) is the regression test.
// ==============================================================================

I64 TILE_W = 64;
I64 TILE_H = 64;

U16 *g_zbuf = NULL;
I64 g_zbuf_w = 0;
I64 g_zbuf_h = 0;
I64 g_zbuf_cap = 0;

I64 g_raster_z0 = 0;
I64 g_raster_z1 = 0;
I64 g_raster_z2 = 0;
I64 g_raster_depth_test = 1;

// Per-triangle job state for RasterRow (single-threaded renderer).
U32 *g_raster_fb = NULL;
I64 g_raster_pitch = 0;
I64 g_raster_cw = 0;
I64 g_raster_min_x = 0;
I64 g_raster_max_x = 0;
I64 g_rj_ax = 0; I64 g_rj_ay = 0; I64 g_rj_az = 0;
I64 g_rj_bx = 0; I64 g_rj_by = 0; I64 g_rj_bz = 0;
I64 g_rj_cx = 0; I64 g_rj_cy = 0; I64 g_rj_cz = 0;
I64 g_rj_b0 = 0;
I64 g_rj_b1 = 0;
I64 g_rj_b2 = 0;
I64 g_rj_area = 1;
U32 g_rj_color = 0;

U0 RasterSetZ(I64 z0, I64 z1, I64 z2) {
  if (z0 < 0) z0 = 0; if (z0 > 65534) z0 = 65534;
  if (z1 < 0) z1 = 0; if (z1 > 65534) z1 = 65534;
  if (z2 < 0) z2 = 0; if (z2 > 65534) z2 = 65534;
  g_raster_z0 = z0;
  g_raster_z1 = z1;
  g_raster_z2 = z2;
}

U0 RasterSetDepthTest(I64 en) { g_raster_depth_test = en ? 1 : 0; }
I64 RasterGetDepthTest() { return g_raster_depth_test; }

U0 RasterInit() {
  I64 w = gfx_get_canvas_width();
  I64 h = gfx_get_canvas_height();
  if (w <= 0) w = 1024;
  if (h <= 0) h = 768;
  if (g_zbuf && g_zbuf_w == w && g_zbuf_h == h) return;
  if (g_zbuf && (w * h > g_zbuf_cap)) {
    kfree(g_zbuf);
    g_zbuf = NULL;
  }
  if (!g_zbuf) {
    g_zbuf = kmalloc(w * h * 2);
    g_zbuf_cap = w * h;
  }
  g_zbuf_w = w;
  g_zbuf_h = h;
}

U0 RasterClearZ() {
  RasterInit();
  if (!g_zbuf) return;
  memset(g_zbuf, 0xFF, g_zbuf_w * g_zbuf_h * 2);
}

I64 PinedaEdge(I64 ax, I64 ay, I64 bx, I64 by, I64 px, I64 py) {
  return (px - ax) * (by - ay) - (py - ay) * (bx - ax);
}

I64 RasterTopLeft(I64 ax, I64 ay, I64 bx, I64 by) {
  I64 dx = bx - ax;
  I64 dy = by - ay;
  if (dy > 0) return 1;
  if (dy == 0 && dx < 0) return 1;
  return 0;
}

// ---- NEON span descriptor (offsets MUST match the assembly below) -------------
//   0x00 fb_ptr (byte addr of the block's first framebuffer pixel)
//   0x08 zb_ptr (byte addr of the block's first Z word)
//   0x10 x_start, 0x18 count (number of 8-pixel blocks)
//   0x20 w0,0x28 w1,0x30 w2   edge values at x_start
//   0x38 dw0,0x40 dw1,0x48 dw2 per-pixel edge deltas
//   0x50 b0,0x58 b1,0x60 b2   top-left biases
//   0x68 z0,0x70 z1,0x78 z2   vertex depths
//   0x80 area, 0x88 color, 0x8C depth_test
class CRasterSpan {
  U64 fb_ptr;
  U64 zb_ptr;
  I64 x_start;
  I64 count;
  I64 w0; I64 w1; I64 w2;
  I64 dw0; I64 dw1; I64 dw2;
  I64 b0; I64 b1; I64 b2;
  I64 z0; I64 z1; I64 z2;
  I64 area;
  U32 color;
  U32 depth_test;
};
CRasterSpan g_rspan;

// NEON 8-pixel span kernel. The raw words are assembled from scripts/raster_span.s
// (regenerate/audit there). Returns the drawn pixel count in X0.
I64 RasterSpanNEON(CRasterSpan *s) {
  asm {
    0xA9BF53F3, 0xA9BF5BF5, 0xA9BF63F7, 0xF81F0FF9, 0xAA0003E9, 0xF9400121, 0xF9400522, 0xF9400D23,
    0xF9401124, 0xF9401525, 0xF9401926, 0xF9401D27, 0xF9402128, 0xF940252A, 0xF940292B, 0xF9402D2C,
    0xF940312D, 0xF940352E, 0xF940392F, 0xF9403D30, 0xF9404131, 0xB9408933, 0xB9408D34, 0xD2800015,
    0x529FFFD9, 0x4F000400, 0x52800036, 0x4E0C1EC0, 0x52800056, 0x4E141EC0, 0x52800076, 0x4E1C1EC0,
    0x4F000481, 0x528000B6, 0x4E0C1EC1, 0x528000D6, 0x4E141EC1, 0x528000F6, 0x4E1C1EC1, 0x4E040CF0,
    0x4E040D11, 0x4E040D52, 0x4E040D73, 0x4E040D94, 0x4E040DB5, 0x4EB09C16, 0x4EB09C37, 0x4EB19C18,
    0x4EB19C39, 0x4EB29C1A, 0x4EB29C3B, 0x4E040E6F, 0xB40013C3, 0x4E040C82, 0x4EB68442, 0x4EB38442,
    0x4E040CA3, 0x4EB88463, 0x4EB48463, 0x4E040CC4, 0x4EBA8484, 0x4EB58484, 0x4E040C85, 0x4EB784A5,
    0x4EB384A5, 0x4E040CA6, 0x4EB984C6, 0x4EB484C6, 0x4E040CC7, 0x4EBB84E7, 0x4EB584E7, 0x6EA08842,
    0x6EA08863, 0x6EA08884, 0x4E231C42, 0x4E241C42, 0x6EA088A5, 0x6EA088C6, 0x6EA088E7, 0x4E261CA5,
    0x4E271CA5, 0x0E612842, 0x0E6128A5, 0x6E1804A2, 0xAA0403F6, 0xAA0503F7, 0xAA0603F8, 0x9B0E7EC0,
    0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F, 0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E021C1C,
    0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0, 0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F,
    0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E061C1C, 0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0,
    0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F, 0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E0A1C1C,
    0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0, 0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F,
    0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E0E1C1C, 0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0,
    0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F, 0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E121C1C,
    0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0, 0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F,
    0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E161C1C, 0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0,
    0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F, 0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E1A1C1C,
    0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x9B0E7EC0, 0x9B0F02E0, 0x9B100300, 0x9AD10C00, 0xEB1F001F,
    0x9A80B3E0, 0xEB19001F, 0x9A80C320, 0x4E1E1C1C, 0x8B0702D6, 0x8B0802F7, 0x8B0A0318, 0x3DC0005D,
    0x34000074, 0x6E7C37BE, 0x4E3E1C42, 0x4EA21C5F, 0x6E7D1F82, 0x3D800042, 0x4E205BE2, 0x4E31B842,
    0x0E013C40, 0x53047C00, 0x8B0002B5, 0x4E5F3BE2, 0x4E5F7BE3, 0x3DC0002A, 0x6E6A1DE2, 0x3D800022,
    0x3DC0042A, 0x6E6A1DE3, 0x3D800423, 0x91008021, 0x91004042, 0x8B070C84, 0x8B080CA5, 0x8B0A0CC6,
    0xD1000463, 0x17FFFF63, 0xAA1503E0, 0xF84107F9, 0xA8C163F7, 0xA8C15BF5, 0xA8C153F3,
  };
}

// Scalar single-pixel path (head/tail), bit-identical to the NEON body.
I64 RasterPixelScalar(I64 xx, I64 yy) {
  I64 w0 = PinedaEdge(g_rj_bx, g_rj_by, g_rj_cx, g_rj_cy, xx, yy);
  I64 w1 = PinedaEdge(g_rj_cx, g_rj_cy, g_rj_ax, g_rj_ay, xx, yy);
  I64 w2 = PinedaEdge(g_rj_ax, g_rj_ay, g_rj_bx, g_rj_by, xx, yy);
  if ((w0 + g_rj_b0) >= 0 && (w1 + g_rj_b1) >= 0 && (w2 + g_rj_b2) >= 0) {
    I64 pz = (w0 * g_rj_az + w1 * g_rj_bz + w2 * g_rj_cz) / g_rj_area;
    if (pz < 0) pz = 0;
    if (pz > 65534) pz = 65534;
    I64 zi = yy * g_raster_cw + xx;
    if (g_raster_depth_test == 0 || pz < g_zbuf[zi]) {
      if (g_raster_depth_test != 0) g_zbuf[zi] = pz;
      g_raster_fb[yy * g_raster_pitch + xx] = g_rj_color;
      return 1;
    }
  }
  return 0;
}

// Fill one scanline of the current triangle: scalar head | NEON body | scalar tail.
I64 RasterRow(I64 yy) {
  I64 xx = g_raster_min_x;
  I64 drawn = 0;
  while (xx < g_raster_max_x && (xx & 7) != 0) {
    drawn = drawn + RasterPixelScalar(xx, yy);
    xx = xx + 1;
  }
  I64 blocks = (g_raster_max_x - xx) >> 3;
  if (blocks > 0) {
    I64 rowoff = yy * g_raster_pitch;
    I64 zrowoff = yy * g_raster_cw;
    g_rspan.fb_ptr = (U64)g_raster_fb + (rowoff + xx) * 4;
    g_rspan.zb_ptr = (U64)g_zbuf + (zrowoff + xx) * 2;
    g_rspan.x_start = xx;
    g_rspan.count = blocks;
    g_rspan.w0 = PinedaEdge(g_rj_bx, g_rj_by, g_rj_cx, g_rj_cy, xx, yy);
    g_rspan.w1 = PinedaEdge(g_rj_cx, g_rj_cy, g_rj_ax, g_rj_ay, xx, yy);
    g_rspan.w2 = PinedaEdge(g_rj_ax, g_rj_ay, g_rj_bx, g_rj_by, xx, yy);
    g_rspan.dw0 = g_rj_cy - g_rj_by;
    g_rspan.dw1 = g_rj_ay - g_rj_cy;
    g_rspan.dw2 = g_rj_by - g_rj_ay;
    g_rspan.b0 = g_rj_b0;
    g_rspan.b1 = g_rj_b1;
    g_rspan.b2 = g_rj_b2;
    g_rspan.z0 = g_rj_az;
    g_rspan.z1 = g_rj_bz;
    g_rspan.z2 = g_rj_cz;
    g_rspan.area = g_rj_area;
    g_rspan.color = g_rj_color;
    g_rspan.depth_test = g_raster_depth_test;
    drawn = drawn + RasterSpanNEON(&g_rspan);
    xx = xx + (blocks << 3);
  }
  while (xx < g_raster_max_x) {
    drawn = drawn + RasterPixelScalar(xx, yy);
    xx = xx + 1;
  }
  return drawn;
}

// Rasterize one screen-space triangle with per-vertex Z (set via RasterSetZ).
I64 RasterTriangleZ(I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2, U32 color) {
  RasterInit();
  if (!g_zbuf) return 0;
  U32 *fb = GfxDeviceTarget();
  if (!fb) return 0;
  I64 pitch = gfx_get_canvas_pitch();
  I64 cw = g_zbuf_w;
  I64 ch = g_zbuf_h;

  I64 ax = x0; I64 ay = y0; I64 az = g_raster_z0;
  I64 bx = x1; I64 by = y1; I64 bz = g_raster_z1;
  I64 cx = x2; I64 cy = y2; I64 cz = g_raster_z2;

  I64 area = PinedaEdge(ax, ay, bx, by, cx, cy);
  if (area == 0) return 0;
  if (area < 0) {
    I64 sw = bx; bx = cx; cx = sw;
    sw = by; by = cy; cy = sw;
    sw = bz; bz = cz; cz = sw;
    area = 0 - area;
  }

  I64 min_x = ax; if (bx < min_x) min_x = bx; if (cx < min_x) min_x = cx;
  I64 max_x = ax; if (bx > max_x) max_x = bx; if (cx > max_x) max_x = cx;
  I64 min_y = ay; if (by < min_y) min_y = by; if (cy < min_y) min_y = cy;
  I64 max_y = ay; if (by > max_y) max_y = by; if (cy > max_y) max_y = cy;
  max_x = max_x + 1;
  max_y = max_y + 1;
  if (min_x < 0) min_x = 0;
  if (min_y < 0) min_y = 0;
  if (max_x > cw) max_x = cw;
  if (max_y > ch) max_y = ch;
  if (min_x >= max_x || min_y >= max_y) return 0;

  g_raster_fb = fb;
  g_raster_pitch = pitch;
  g_raster_cw = cw;
  g_raster_min_x = min_x;
  g_raster_max_x = max_x;
  g_rj_ax = ax; g_rj_ay = ay; g_rj_az = az;
  g_rj_bx = bx; g_rj_by = by; g_rj_bz = bz;
  g_rj_cx = cx; g_rj_cy = cy; g_rj_cz = cz;
  g_rj_b0 = -1; if (RasterTopLeft(bx, by, cx, cy) != 0) g_rj_b0 = 0;
  g_rj_b1 = -1; if (RasterTopLeft(cx, cy, ax, ay) != 0) g_rj_b1 = 0;
  g_rj_b2 = -1; if (RasterTopLeft(ax, ay, bx, by) != 0) g_rj_b2 = 0;
  g_rj_area = area;
  g_rj_color = color;

  I64 drawn = 0;
  for (I64 yy = min_y; yy < max_y; yy = yy + 1) {
    drawn = drawn + RasterRow(yy);
  }
  return drawn;
}

U0 RasterBootCheck() {
  RasterInit();
  I64 ok = 1;
  I64 pit = gfx_get_canvas_pitch();

  RasterSetDepthTest(1);
  RasterClearZ();
  RasterSetZ(1, 1, 1);
  I64 n = RasterTriangleZ(20, 20, 60, 20, 40, 60, 0xFFFF00FF);
  if (n < 700 || n > 900) { ok = 0; doldoc_printf("[RASTER] coverage n=%lld (want ~800)\n", n); }
  if (g_raster_fb[30 * pit + 40] != 0xFFFF00FF) { ok = 0; doldoc_print("[RASTER] center pixel not filled\n"); }

  RasterClearZ();
  RasterSetZ(100, 100, 100);
  RasterTriangleZ(20, 20, 60, 20, 40, 60, 0xFF00FF00);
  RasterSetZ(5000, 5000, 5000);
  RasterTriangleZ(20, 20, 60, 20, 40, 60, 0xFFFF0000);
  if (g_raster_fb[30 * pit + 40] != 0xFF00FF00) { ok = 0; doldoc_print("[RASTER] depth rejection failed\n"); }

  // Two triangles sharing the diagonal (100,100)-(200,200) tile the square
  // [100,200)x[100,200); every pixel must be filled.
  RasterClearZ();
  RasterSetZ(1, 1, 1);
  RasterTriangleZ(100, 100, 200, 100, 200, 200, 0xFFF1C40F);
  RasterTriangleZ(100, 100, 200, 200, 100, 200, 0xFFF1C40F);
  I64 gaps = 0;
  I64 gy = 100;
  while (gy < 200) {
    I64 gx = 100;
    while (gx < 200) {
      if (g_raster_fb[gy * pit + gx] != 0xFFF1C40F) gaps = gaps + 1;
      gx++;
    }
    gy++;
  }
  if (gaps != 0) { ok = 0; doldoc_printf("[RASTER] shared-edge gaps=%lld\n", gaps); }

  if (ok != 0) {
    doldoc_print("RASTER: PASS\n");
  } else {
    doldoc_print("RASTER: FAIL\n");
  }
}

U0 RasterTileMain() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$   NeoOS Single Rasterizer (RasterTile.HC, P4.2b)$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_print(" Algorithm: Juan Pineda edges + top-left rule (scalar head/tail)\n");
  doldoc_print(" Body     : NEON 8-pixel span (exact 64-bit Z + 8-lane depth/color)\n");
  doldoc_print(" Depth    : ONE full-screen 16-bit Z-buffer (owned here)\n");
  doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
  RasterBootCheck();
  doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

if (g_kernel_booting) {
  RasterInit();
  RasterBootCheck();
} else {
  RasterTileMain();
}
