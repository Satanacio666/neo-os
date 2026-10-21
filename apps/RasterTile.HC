// ==============================================================================
// apps/RasterTile.HC - NeoOS single rasterizer (P4.2)
// ------------------------------------------------------------------------------
// The ONE triangle rasterizer for the whole system (2D fills and HolyGL 3D both
// go through RasterTriangleZ). Properties:
//   * Real per-pixel Z: a single full-screen 16-bit depth buffer owned here.
//   * Juan Pineda edge functions, exact integer arithmetic.
//   * Top-left fill rule: shared mesh edges are drawn exactly once.
//   * Deterministic row-major scan, identical on 1 vs N cores.
//
// Structure: RasterTriangleZ (setup + row loop) -> RasterRow (one scanline).
// P4.2 depended on a Compiler.HC fix: indexing a global POINTER must stride by
// and load/store sizeof(pointee) (HcResolveLValue / HcRegisterGlobalScale). With
// that fixed, `g_zbuf[i]` is a 2-byte LDRH and `g_raster_fb[i]` a 4-byte STR — no
// masks or helper shims needed. RasterBootCheck (below) is the regression test.
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

// Fill one scanline of the current triangle. Returns pixels drawn.
I64 RasterRow(I64 yy) {
  I64 rowoff = yy * g_raster_pitch;
  I64 zrowoff = yy * g_raster_cw;
  I64 xx = g_raster_min_x;
  I64 drawn = 0;
  while (xx < g_raster_max_x) {
    I64 w0 = PinedaEdge(g_rj_bx, g_rj_by, g_rj_cx, g_rj_cy, xx, yy);
    I64 w1 = PinedaEdge(g_rj_cx, g_rj_cy, g_rj_ax, g_rj_ay, xx, yy);
    I64 w2 = PinedaEdge(g_rj_ax, g_rj_ay, g_rj_bx, g_rj_by, xx, yy);
    if ((w0 + g_rj_b0) >= 0 && (w1 + g_rj_b1) >= 0 && (w2 + g_rj_b2) >= 0) {
      I64 pz = (w0 * g_rj_az + w1 * g_rj_bz + w2 * g_rj_cz) / g_rj_area;
      if (pz < 0) pz = 0;
      if (pz > 65534) pz = 65534;
      I64 zi = zrowoff + xx;
      if (g_raster_depth_test == 0 || pz < g_zbuf[zi]) {
        if (g_raster_depth_test != 0) g_zbuf[zi] = pz;
        g_raster_fb[rowoff + xx] = g_rj_color;
        drawn = drawn + 1;
      }
    }
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

  RasterClearZ(); RasterSetDepthTest(0); RasterSetZ(1, 1, 1);
  I64 bn = RasterTriangleZ(100, 100, 300, 100, 200, 300, 0xFF00FF00);
  doldoc_printf("[RASTER-DIAG] big n=%lld r0=0x%X r64=0x%X r150=0x%X r192=0x%X r290=0x%X\n",
                bn, g_raster_fb[0 * pit + 200], g_raster_fb[64 * pit + 200],
                g_raster_fb[150 * pit + 200], g_raster_fb[192 * pit + 200], g_raster_fb[290 * pit + 200]);

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
  I64 n1 = RasterTriangleZ(100, 100, 200, 100, 200, 200, 0xFFF1C40F);
  I64 n2 = RasterTriangleZ(100, 100, 200, 200, 100, 200, 0xFFF1C40F);
  doldoc_printf("[RASTER-DIAG] seam n1=%lld n2=%lld\n", n1, n2);
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
  doldoc_print("$FG,WHITE$   NeoOS Single Rasterizer (RasterTile.HC, P4.2)$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_print(" Algorithm: Juan Pineda incremental edges + top-left rule\n");
  doldoc_print(" Depth    : ONE full-screen 16-bit Z-buffer (owned here)\n");
  doldoc_print(" Order    : row-major, deterministic (1 vs N cores)\n");
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
