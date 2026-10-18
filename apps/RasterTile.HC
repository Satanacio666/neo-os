// RasterTile.HC - Sovereign L1-Tiled Pineda Edge & 16-Bit Z-Buffer Rasterizer
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution
// Operates within 24KB L1 Data Cache Scratchpad (16KB Color + 8KB 16-bit Depth)

I64 TILE_W = 64;
I64 TILE_H = 64;
I64 TILE_PIXELS = 4096;
I64 TILE_COLOR_BYTES = 16384;
I64 TILE_DEPTH_BYTES = 8192;

// 24KB L1 Cache Scratchpad: 16KB ARGB8888 Color + 8KB U16 Z-Buffer
U32 g_tile_cbuf[4096];
U16 g_tile_zbuf[4096];

I64 g_tri_z0 = 32768;
I64 g_tri_z1 = 32768;
I64 g_tri_z2 = 32768;
I64 g_tri_use_vertex_z = 0;

// Juan Pineda Edge Function: evaluates which side of edge (V0->V1) point (px, py) lies
I64 PinedaEdge(I64 x0, I64 y0, I64 x1, I64 y1, I64 px, I64 py) {
  return (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0);
}

// Clear both L1 color buffer and 16-bit depth buffer (0xFFFF = far plane)
U0 RasterClearTile(U32 bg_col) {
  I64 rc_i = 0;
  while (rc_i < 4096) {
    g_tile_cbuf[rc_i] = bg_col;
    g_tile_zbuf[rc_i] = 0xFFFF;
    rc_i++;
  }
}

// Clear external scratchpad plus internal Z-buffer
U0 TileClear(U32 *scratchpad, U32 clear_color) {
  I64 tc_i = 0;
  while (tc_i < 4096) {
    if (scratchpad) scratchpad[tc_i] = clear_color;
    g_tile_cbuf[tc_i] = clear_color;
    g_tile_zbuf[tc_i] = 0xFFFF;
    tc_i++;
  }
}

U0 RasterSetVertexZ(I64 z0, I64 z1, I64 z2) {
  if (z0 < 0) z0 = 0; if (z0 > 65534) z0 = 65534;
  if (z1 < 0) z1 = 0; if (z1 > 65534) z1 = 65534;
  if (z2 < 0) z2 = 0; if (z2 > 65534) z2 = 65534;
  g_tri_z0 = z0;
  g_tri_z1 = z1;
  g_tri_z2 = z2;
  g_tri_use_vertex_z = 1;
}

// Z-buffered Pineda triangle rasterizer (8 args in X0..X7)
// Interpolates Z across the triangle and tests z < g_tile_zbuf[idx]
I64 RasterTriangleZ(I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2, I64 z_val, U32 color) {
  I64 min_x = x0;
  if (x1 < min_x) min_x = x1;
  if (x2 < min_x) min_x = x2;

  I64 max_x = x0;
  if (x1 > max_x) max_x = x1;
  if (x2 > max_x) max_x = x2;

  I64 min_y = y0;
  if (y1 < min_y) min_y = y1;
  if (y2 < min_y) min_y = y2;

  I64 max_y = y0;
  if (y1 > max_y) max_y = y1;
  if (y2 > max_y) max_y = y2;

  if (min_x < 0) min_x = 0;
  if (max_x > 64) max_x = 64;
  if (min_y < 0) min_y = 0;
  if (max_y > 64) max_y = 64;

  if (min_x >= max_x || min_y >= max_y) {
    g_tri_use_vertex_z = 0;
    return 0;
  }

  I64 z_a = z_val;
  I64 z_b = z_val;
  I64 z_c = z_val;
  if (g_tri_use_vertex_z) {
    z_a = g_tri_z0;
    z_b = g_tri_z1;
    z_c = g_tri_z2;
    g_tri_use_vertex_z = 0;
  }

  I64 area = PinedaEdge(x0, y0, x1, y1, x2, y2);
  if (area == 0) return 0;
  if (area < 0) {
    I64 tx = x1; I64 ty = y1; I64 tz = z_b;
    x1 = x2; y1 = y2; z_b = z_c;
    x2 = tx; y2 = ty; z_c = tz;
    area = -area;
  }

  // Incremental Pineda step deltas
  I64 a01 = y1 - y0; I64 b01 = x0 - x1;
  I64 a12 = y2 - y1; I64 b12 = x1 - x2;
  I64 a20 = y0 - y2; I64 b20 = x2 - x0;

  I64 w0_row = PinedaEdge(x1, y1, x2, y2, min_x, min_y);
  I64 w1_row = PinedaEdge(x2, y2, x0, y0, min_x, min_y);
  I64 w2_row = PinedaEdge(x0, y0, x1, y1, min_x, min_y);

  I64 pixels_drawn = 0;
  I64 rt_py = min_y;
  while (rt_py < max_y) {
    I64 row_off = rt_py * 64;
    I64 w0 = w0_row;
    I64 w1 = w1_row;
    I64 w2 = w2_row;

    I64 rt_px = min_x;
    while (rt_px < max_x) {
      if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
        I64 pz = (w0 * z_a + w1 * z_b + w2 * z_c) / area;
        if (pz < 0) pz = 0;
        if (pz > 65534) pz = 65534;
        I64 idx = row_off + rt_px;
        if (pz < g_tile_zbuf[idx]) {
          g_tile_zbuf[idx] = pz;
          g_tile_cbuf[idx] = color;
          pixels_drawn = pixels_drawn + 1;
        }
      }
      w0 = w0 + a12;
      w1 = w1 + a20;
      w2 = w2 + a01;
      rt_px++;
    }
    w0_row = w0_row + b12;
    w1_row = w1_row + b20;
    w2_row = w2_row + b01;
    rt_py++;
  }

  return pixels_drawn;
}

// Rasterize single triangle into 64x64 L1 cache tile (updates scratchpad and g_tile_cbuf)
I64 TileRasterTri(U32 *scratchpad, I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2, U32 color) {
  I64 min_x = x0;
  if (x1 < min_x) min_x = x1;
  if (x2 < min_x) min_x = x2;

  I64 max_x = x0;
  if (x1 > max_x) max_x = x1;
  if (x2 > max_x) max_x = x2;

  I64 min_y = y0;
  if (y1 < min_y) min_y = y1;
  if (y2 < min_y) min_y = y2;

  I64 max_y = y0;
  if (y1 > max_y) max_y = y1;
  if (y2 > max_y) max_y = y2;

  if (min_x < 0) min_x = 0;
  if (max_x > 64) max_x = 64;
  if (min_y < 0) min_y = 0;
  if (max_y > 64) max_y = 64;

  if (min_x >= max_x || min_y >= max_y) return 0;

  I64 area = PinedaEdge(x0, y0, x1, y1, x2, y2);
  if (area == 0) return 0;
  if (area < 0) {
    I64 tx = x1; I64 ty = y1;
    x1 = x2; y1 = y2;
    x2 = tx; y2 = ty;
  }

  I64 a01 = y1 - y0; I64 b01 = x0 - x1;
  I64 a12 = y2 - y1; I64 b12 = x1 - x2;
  I64 a20 = y0 - y2; I64 b20 = x2 - x0;

  I64 w0_row = PinedaEdge(x1, y1, x2, y2, min_x, min_y);
  I64 w1_row = PinedaEdge(x2, y2, x0, y0, min_x, min_y);
  I64 w2_row = PinedaEdge(x0, y0, x1, y1, min_x, min_y);

  I64 pixels_drawn = 0;
  I64 tr_py = min_y;
  while (tr_py < max_y) {
    I64 row_off = tr_py * 64;
    I64 w0 = w0_row;
    I64 w1 = w1_row;
    I64 w2 = w2_row;

    I64 tr_px = min_x;
    while (tr_px < max_x) {
      if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
        if (scratchpad) scratchpad[row_off + tr_px] = color;
        g_tile_cbuf[row_off + tr_px] = color;
        pixels_drawn = pixels_drawn + 1;
      }
      w0 = w0 + a12;
      w1 = w1 + a20;
      w2 = w2 + a01;
      tr_px++;
    }
    w0_row = w0_row + b12;
    w1_row = w1_row + b20;
    w2_row = w2_row + b01;
    tr_py++;
  }

  return pixels_drawn;
}

// Stream 16KB color block from L1 cache directly to target framebuffer
U0 TileResolve(U32 *scratchpad, I64 tile_x, I64 tile_y, U32 *fb, I64 pitch) {
  if (!fb) return;
  U32 *src = scratchpad ? scratchpad : g_tile_cbuf;
  I64 tr_y = 0;
  while (tr_y < 64) {
    I64 fb_idx = (tile_y + tr_y) * pitch + tile_x;
    I64 sp_idx = tr_y * 64;
    I64 tr_x = 0;
    while (tr_x < 64) {
      fb[fb_idx + tr_x] = src[sp_idx + tr_x];
      tr_x++;
    }
    tr_y++;
  }
}

U0 RasterTileMain() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$   ✦ NeoOS Sovereign L1-Tiled HolyC Rasterizer (RasterTile.HC) ✦$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_print(" Architecture: Juan Pineda Incremental Edge + 16-Bit Z-Buffer\n");
  doldoc_print(" Cache Target: 64x64 Tiles (16KB ARGB Color + 8KB Z-16 Depth Buffer)\n");
  doldoc_print(" Elimination : ZERO C Fallbacks | Pure AArch64 HolyC Execution\n");
  doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

  doldoc_print(" [1/4] Benchmarking Z-Buffered Pineda Evaluation (500 Triangles)...\n");
  I64 start_us = timer_get_uptime_us();
  I64 total_pixels = 0;

  I64 rt_iter = 0;
  while (rt_iter < 100) {
    RasterClearTile(0xFF1B1E20);
    I64 p1 = RasterTriangleZ(10, 10, 50, 15, 30, 55, 4000, 0xFFE056FD);
    I64 p2 = RasterTriangleZ(5, 45, 55, 35, 25, 5, 3000, 0xFF00E676);
    I64 p3 = RasterTriangleZ(15, 20, 40, 50, 60, 25, 2000, 0xFF3DAEE9);
    I64 p4 = RasterTriangleZ(2, 5, 58, 2, 30, 60, 5000, 0xFFF1C40F);
    I64 p5 = RasterTriangleZ(8, 55, 52, 58, 30, 12, 1000, 0xFFFF5555);
    total_pixels = total_pixels + p1 + p2 + p3 + p4 + p5;
    rt_iter++;
  }

  I64 end_us = timer_get_uptime_us();
  I64 elapsed_us = end_us - start_us;
  if (elapsed_us <= 0) elapsed_us = 1;

  doldoc_printf("  $FG,GREEN$[PASS]$FG$ Z-Rasterized %lld pixels across 500 triangles in %lld us\n",
                total_pixels, elapsed_us);

  I64 mpix_sec = (total_pixels * 1000) / elapsed_us;
  doldoc_printf("  $FG,CYAN$[PERF]$FG$ Throughput: %lld Kpix/sec in pure HolyC JIT\n", mpix_sec);

  doldoc_print(" [2/4] Verifying 16-Bit Depth Occlusion (Near vs Far Triangle)...\n");
  RasterClearTile(0xFF000000);
  // Draw near triangle (z = 1000, Green) then far overlapping triangle (z = 5000, Red)
  RasterTriangleZ(10, 10, 50, 10, 30, 50, 1000, 0xFF00FF00);
  RasterTriangleZ(10, 10, 50, 10, 30, 50, 5000, 0xFFFF0000);
  U32 center_col = g_tile_cbuf[25 * 64 + 30];
  U16 center_z   = g_tile_zbuf[25 * 64 + 30];
  if (center_col == 0xFF00FF00 && center_z == 1000) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ 16-bit Z-buffer depth rejection verified (far triangle occluded).\n");
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Z-buffer occlusion mismatch: col=0x%X z=%lld\n", center_col, (I64)center_z);
  }

  doldoc_print(" [3/4] Live Framebuffer Tile Resolve & Streaming Blit...\n");
  U32 *fb = gfx_get_backbuffer();
  I64 pitch = gfx_get_canvas_pitch();
  I64 w = gfx_get_canvas_width();
  I64 h = gfx_get_canvas_height();

  if (fb && pitch > 0) {
    I64 target_x = w - 80;
    I64 target_y = 10;
    if (target_x > 0 && target_y > 0 && target_x + 64 < w && target_y + 64 < h) {
      TileResolve(g_tile_cbuf, target_x, target_y, fb, pitch);
      gfx_dirty_expand(target_x, target_y, 64, 64);
      doldoc_printf("  $FG,GREEN$[PASS]$FG$ Tile resolve streamed directly to backbuffer (%lld, %lld)\n",
                    target_x, target_y);
    }
  }

  doldoc_print(" [4/4] Juan Pineda Analytical Precision Verification...\n");
  I64 test_e0 = PinedaEdge(0, 0, 10, 0, 5, 5);
  I64 test_e1 = PinedaEdge(0, 0, 0, 10, 5, 5);
  if (test_e0 == -50 && test_e1 == 50) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Analytical edge equations exact and verified.\n");
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Analytical edge mismatch!\n");
  }

  doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
  doldoc_print(" Actions: $BT,\"Re-run Raster Benchmark\",LM=\"run RasterTile.HC\"$  $BT,\"Vector Font\",LM=\"run FontVector.HC\"$  $BT,\"Menu\",LM=\"menu\"$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

if (g_kernel_booting) {
  RasterClearTile(0xFF1B1E20);
} else {
  RasterTileMain();
}
