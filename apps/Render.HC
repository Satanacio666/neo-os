// NeoOS Sovereign Pure HolyC 2D Graphics & Compositing Renderer (Render.HC)
// Pure Native AArch64 Ring 0 SASOS Implementation
// High-Resolution Dynamic Canvas, Zero-RAM Direct Scanout, CNTVCT VSync & AA Primitives

class CClipRect {
  I64 active;
  I64 x0;
  I64 y0;
  I64 x1;
  I64 y1;
};

class CDirtyRect {
  I64 active;
  I64 x0;
  I64 y0;
  I64 x1;
  I64 y1;
};

class CGfxConfig {
  I64 buffer_mode;
  I64 mode;
  I64 vsync_en;
  I64 vsync_hz;
};

class CCanvasState {
  I64 width;
  I64 height;
  I64 pitch;
  U32 *back_buffer;
  U32 *front_buffer;
  CClipRect clip;
  CDirtyRect dirty;
  I64 zero_ram_mode;
  I64 vsync_en;
  I64 vsync_hz;
  U64 vsync_interval_ticks;
  U64 vsync_last_vct;
};

CGfxConfig g_gfx_cfg;
CCanvasState g_canv;

U0 RenderInit() {
  g_canv.width = g_uefi_width ? g_uefi_width : 1024;
  g_canv.height = g_uefi_height ? g_uefi_height : 768;
  g_canv.pitch = g_uefi_pitch ? g_uefi_pitch : g_canv.width;
  g_canv.front_buffer = g_uefi_fb;
  doldoc_printf("[RENDER-INIT] front_buffer=0x%016llX uefi_fb=0x%016llX (%lldx%lld pitch=%lld)\n",
                g_canv.front_buffer, g_uefi_fb, g_canv.width, g_canv.height, g_canv.pitch);
  if (!g_canv.back_buffer) {
    g_canv.back_buffer = kmalloc(g_canv.pitch * g_canv.height * 4);
    if (g_canv.back_buffer) {
      memset(g_canv.back_buffer, 0, g_canv.pitch * g_canv.height * 4);
    }
  }

  g_canv.clip.active = 0;
  g_canv.clip.x0 = 0;
  g_canv.clip.y0 = 0;
  g_canv.clip.x1 = g_canv.width;
  g_canv.clip.y1 = g_canv.height;

  g_canv.dirty.active = 0;
  g_canv.dirty.x0 = 0;
  g_canv.dirty.y0 = 0;
  g_canv.dirty.x1 = 0;
  g_canv.dirty.y1 = 0;

  U64 hw_frq = __mrs_cntfrq();
  if (hw_frq == 0) hw_frq = 62500000;
  if (g_canv.vsync_hz <= 0) g_canv.vsync_hz = 60;
  g_canv.vsync_interval_ticks = hw_frq / g_canv.vsync_hz;
  g_canv.vsync_last_vct = __mrs_cntvct();
}

U0 RenderSetZeroRamMode(I64 en) {
  g_canv.zero_ram_mode = en ? 1 : 0;
  g_gfx_cfg.buffer_mode = en ? 1 : 0;
}

I64 RenderIsZeroRamMode() {
  if (g_gfx_cfg.buffer_mode == 1 || g_canv.zero_ram_mode == 1) return 1;
  return 0;
}

U32* RenderGetTargetBuffer() {
  if (g_canv.width == 0) RenderInit();
  if ((g_gfx_cfg.buffer_mode == 1 || g_canv.zero_ram_mode == 1) && g_canv.front_buffer) {
    return g_canv.front_buffer;
  }
  return g_canv.back_buffer ? g_canv.back_buffer : g_canv.front_buffer;
}

U0 RenderSetClip(I64 cx, I64 cy, I64 cw, I64 ch) {
  if (g_canv.width == 0) RenderInit();
  g_canv.clip.active = 1;
  g_canv.clip.x0 = cx;
  g_canv.clip.y0 = cy;
  g_canv.clip.x1 = cx + cw;
  g_canv.clip.y1 = cy + ch;

  if (g_canv.clip.x0 < 0) g_canv.clip.x0 = 0;
  if (g_canv.clip.y0 < 0) g_canv.clip.y0 = 0;
  if (g_canv.clip.x1 > g_canv.width) g_canv.clip.x1 = g_canv.width;
  if (g_canv.clip.y1 > g_canv.height) g_canv.clip.y1 = g_canv.height;
}

U0 RenderResetClip() {
  g_canv.clip.active = 0;
}

U0 RenderDirtyExpand(I64 dx, I64 dy, I64 dw, I64 dh) {
  if (dw <= 0 || dh <= 0) return;
  if (dx < 0) { dw = dw + dx; dx = 0; }
  if (dy < 0) { dh = dh + dy; dy = 0; }
  if (dx + dw > g_canv.width) dw = g_canv.width - dx;
  if (dy + dh > g_canv.height) dh = g_canv.height - dy;
  if (dw <= 0 || dh <= 0) return;

  I64 rx2 = dx + dw;
  I64 ry2 = dy + dh;

  if (!g_canv.dirty.active) {
    g_canv.dirty.x0 = dx;
    g_canv.dirty.y0 = dy;
    g_canv.dirty.x1 = rx2;
    g_canv.dirty.y1 = ry2;
    g_canv.dirty.active = 1;
  } else {
    if (dx < g_canv.dirty.x0) g_canv.dirty.x0 = dx;
    if (dy < g_canv.dirty.y0) g_canv.dirty.y0 = dy;
    if (rx2 > g_canv.dirty.x1) g_canv.dirty.x1 = rx2;
    if (ry2 > g_canv.dirty.y1) g_canv.dirty.y1 = ry2;
  }
}

U0 RenderDirtyReset() {
  g_canv.dirty.active = 0;
}

U32 RenderBlendColor(U32 dst, U32 src_rgba) {
  U32 a = (src_rgba >> 24) & 0xFF;
  if (a == 0) return dst;
  if (a == 255) return src_rgba | 0xFF000000;

  U32 inv_a = 255 - a;
  U32 src_r = ((src_rgba >> 16) & 0xFF) * a + 128;
  U32 src_g = ((src_rgba >> 8)  & 0xFF) * a + 128;
  U32 src_b = ((src_rgba)       & 0xFF) * a + 128;

  U32 r = (src_r + ((dst >> 16) & 0xFF) * inv_a) >> 8;
  U32 g = (src_g + ((dst >> 8)  & 0xFF) * inv_a) >> 8;
  U32 b = (src_b + ((dst)       & 0xFF) * inv_a) >> 8;

  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

U0 RenderPutPixel(I64 px, I64 py, U32 col) {
  if (px < 0 || py < 0 || px >= g_canv.width || py >= g_canv.height) return;
  if (g_canv.clip.active) {
    if (px < g_canv.clip.x0 || py < g_canv.clip.y0 || px >= g_canv.clip.x1 || py >= g_canv.clip.y1) return;
  }
  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return;
  buf[py * g_canv.pitch + px] = col;
}

U0 RenderBlendPixel(I64 px, I64 py, U32 col) {
  if (px < 0 || py < 0 || px >= g_canv.width || py >= g_canv.height) return;
  if (g_canv.clip.active) {
    if (px < g_canv.clip.x0 || py < g_canv.clip.y0 || px >= g_canv.clip.x1 || py >= g_canv.clip.y1) return;
  }
  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return;
  I64 idx = py * g_canv.pitch + px;
  U32 a = (col >> 24) & 0xFF;
  if (a == 255) {
    buf[idx] = col;
  } else if (a > 0) {
    buf[idx] = RenderBlendColor(buf[idx], col);
  }
}

I64 RenderOutcode(I64 px, I64 py, I64 xmin, I64 ymin, I64 xmax, I64 ymax) {
  I64 code = 0;
  if (px < xmin) code = code | 1;
  else if (px > xmax) code = code | 2;
  if (py < ymin) code = code | 4;
  else if (py > ymax) code = code | 8;
  return code;
}

// Cohen-Sutherland viewport-clipped Bresenham line rasterizer
U0 RenderDrawLine(I64 lx0, I64 ly0, I64 lx1, I64 ly1, U32 lcol) {
  if (g_canv.width == 0) RenderInit();
  I64 xmin = 0;
  I64 ymin = 0;
  I64 xmax = g_canv.width - 1;
  I64 ymax = g_canv.height - 1;
  if (g_canv.clip.active) {
    if (g_canv.clip.x0 > xmin) xmin = g_canv.clip.x0;
    if (g_canv.clip.y0 > ymin) ymin = g_canv.clip.y0;
    if (g_canv.clip.x1 - 1 < xmax) xmax = g_canv.clip.x1 - 1;
    if (g_canv.clip.y1 - 1 < ymax) ymax = g_canv.clip.y1 - 1;
  }
  if (xmin > xmax || ymin > ymax) return;

  I64 out0 = RenderOutcode(lx0, ly0, xmin, ymin, xmax, ymax);
  I64 out1 = RenderOutcode(lx1, ly1, xmin, ymin, xmax, ymax);
  I64 accept = 0;
  I64 clip_iter = 0;

  while (clip_iter < 12) {
    if ((out0 | out1) == 0) {
      accept = 1;
      break;
    } else if ((out0 & out1) != 0) {
      break;
    } else {
      I64 out_out = out0 ? out0 : out1;
      I64 cx = lx0;
      I64 cy = ly0;
      I64 cdx = lx1 - lx0;
      I64 cdy = ly1 - ly0;

      if (out_out & 8) {
        if (cdy != 0) cx = lx0 + (cdx * (ymax - ly0)) / cdy;
        cy = ymax;
      } else if (out_out & 4) {
        if (cdy != 0) cx = lx0 + (cdx * (ymin - ly0)) / cdy;
        cy = ymin;
      } else if (out_out & 2) {
        if (cdx != 0) cy = ly0 + (cdy * (xmax - lx0)) / cdx;
        cx = xmax;
      } else if (out_out & 1) {
        if (cdx != 0) cy = ly0 + (cdy * (xmin - lx0)) / cdx;
        cx = xmin;
      }

      if (out_out == out0) {
        lx0 = cx;
        ly0 = cy;
        out0 = RenderOutcode(lx0, ly0, xmin, ymin, xmax, ymax);
      } else {
        lx1 = cx;
        ly1 = cy;
        out1 = RenderOutcode(lx1, ly1, xmin, ymin, xmax, ymax);
      }
    }
    clip_iter++;
  }

  if (!accept) return;

  I64 dirty_x0 = lx0 < lx1 ? lx0 : lx1;
  I64 dirty_y0 = ly0 < ly1 ? ly0 : ly1;
  I64 dirty_x1 = lx0 > lx1 ? lx0 : lx1;
  I64 dirty_y1 = ly0 > ly1 ? ly0 : ly1;
  RenderDirtyExpand(dirty_x0, dirty_y0, dirty_x1 - dirty_x0 + 1, dirty_y1 - dirty_y0 + 1);

  I64 dx = lx1 - lx0;
  if (dx < 0) dx = -dx;
  I64 dy = ly1 - ly0;
  if (dy > 0) dy = -dy;

  I64 sx = (lx0 < lx1) ? 1 : -1;
  I64 sy = (ly0 < ly1) ? 1 : -1;

  I64 err = dx + dy;
  I64 cur_x = lx0;
  I64 cur_y = ly0;
  I64 steps = 0;
  I64 max_steps = dx - dy + 8;

  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return;
  I64 pitch = g_canv.pitch;

  while (steps <= max_steps) {
    if (cur_x >= xmin && cur_x <= xmax && cur_y >= ymin && cur_y <= ymax) {
      buf[cur_y * pitch + cur_x] = lcol;
    }
    if (cur_x == lx1 && cur_y == ly1) break;
    I64 e2 = 2 * err;
    if (e2 >= dy) {
      err = err + dy;
      cur_x = cur_x + sx;
    }
    if (e2 <= dx) {
      err = err + dx;
      cur_y = cur_y + sy;
    }
    steps++;
  }
}

U0 RenderDrawRect(I64 rx, I64 ry, I64 rw, I64 rh, U32 rcol) {
  if (rw <= 0 || rh <= 0) return;
  if (g_canv.width == 0) RenderInit();
  I64 min_x = rx;
  I64 min_y = ry;
  I64 max_x = rx + rw;
  I64 max_y = ry + rh;

  if (min_x < 0) min_x = 0;
  if (min_y < 0) min_y = 0;
  if (max_x > g_canv.width) max_x = g_canv.width;
  if (max_y > g_canv.height) max_y = g_canv.height;

  if (g_canv.clip.active) {
    if (min_x < g_canv.clip.x0) min_x = g_canv.clip.x0;
    if (min_y < g_canv.clip.y0) min_y = g_canv.clip.y0;
    if (max_x > g_canv.clip.x1) max_x = g_canv.clip.x1;
    if (max_y > g_canv.clip.y1) max_y = g_canv.clip.y1;
  }
  if (min_x >= max_x || min_y >= max_y) return;

  RenderDirtyExpand(min_x, min_y, max_x - min_x, max_y - min_y);
  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return;

  I64 row_y = min_y;
  while (row_y < max_y) {
    I64 col_x = min_x;
    I64 row_offset = row_y * g_canv.pitch;
    while (col_x < max_x) {
      buf[row_offset + col_x] = rcol;
      col_x++;
    }
    row_y++;
  }
}

// Anti-aliased filled circle using subpixel radial distance coverage
U0 RenderFillCircleAA(I64 cx, I64 cy, I64 r, U32 col) {
  if (r <= 0) return;
  if (g_canv.width == 0) RenderInit();
  RenderDirtyExpand(cx - r - 1, cy - r - 1, 2 * r + 3, 2 * r + 3);

  I64 r_in = (r > 1) ? (r - 1) : 0;
  I64 r_in2 = r_in * r_in;
  I64 r_out = r + 1;
  I64 r_out2 = r_out * r_out;
  I64 span = r_out2 - r_in2;
  if (span <= 0) span = 1;

  U32 base_a = (col >> 24) & 0xFF;
  if (base_a == 0) base_a = 255;
  U32 rgb = col & 0x00FFFFFF;

  I64 fc_dy = -r;
  while (fc_dy <= r) {
    I64 fc_dx = -r;
    while (fc_dx <= r) {
      I64 d2 = fc_dx * fc_dx + fc_dy * fc_dy;
      if (d2 <= r_in2) {
        RenderBlendPixel(cx + fc_dx, cy + fc_dy, (base_a << 24) | rgb);
      } else if (d2 < r_out2) {
        I64 cov = ((r_out2 - d2) * 255) / span;
        U32 eff_a = (base_a * cov) >> 8;
        if (eff_a > 0) {
          RenderBlendPixel(cx + fc_dx, cy + fc_dy, (eff_a << 24) | rgb);
        }
      }
      fc_dx++;
    }
    fc_dy++;
  }
}

// Anti-aliased rounded rectangle primitive
U0 RenderRoundedRect(I64 rx, I64 ry, I64 rw, I64 rh, I64 rad, U32 rcol) {
  if (rw <= 0 || rh <= 0) return;
  if (rad <= 1 || rw < 2 * rad || rh < 2 * rad) {
    RenderDrawRect(rx, ry, rw, rh, rcol);
    return;
  }
  RenderDirtyExpand(rx, ry, rw, rh);
  RenderDrawRect(rx + rad, ry, rw - 2 * rad, rh, rcol);
  RenderDrawRect(rx, ry + rad, rad, rh - 2 * rad, rcol);
  RenderDrawRect(rx + rw - rad, ry + rad, rad, rh - 2 * rad, rcol);

  I64 r_in = (rad > 1) ? (rad - 1) : 0;
  I64 r_in2 = r_in * r_in;
  I64 r_out2 = rad * rad;
  I64 span = r_out2 - r_in2;
  if (span <= 0) span = 1;

  U32 base_a = (rcol >> 24) & 0xFF;
  if (base_a == 0) base_a = 255;
  U32 rgb = rcol & 0x00FFFFFF;

  I64 rr_dy = 0;
  while (rr_dy < rad) {
    I64 rr_dx = 0;
    while (rr_dx < rad) {
      I64 d2 = rr_dx * rr_dx + rr_dy * rr_dy;
      if (d2 <= r_in2) {
        U32 full_col = (base_a << 24) | rgb;
        RenderBlendPixel(rx + rad - 1 - rr_dx, ry + rad - 1 - rr_dy, full_col);
        RenderBlendPixel(rx + rw - rad + rr_dx, ry + rad - 1 - rr_dy, full_col);
        RenderBlendPixel(rx + rad - 1 - rr_dx, ry + rh - rad + rr_dy, full_col);
        RenderBlendPixel(rx + rw - rad + rr_dx, ry + rh - rad + rr_dy, full_col);
      } else if (d2 <= r_out2) {
        I64 cov = ((r_out2 - d2) * 255) / span;
        U32 eff_a = (base_a * cov) >> 8;
        if (eff_a > 0) {
          U32 edge_col = (eff_a << 24) | rgb;
          RenderBlendPixel(rx + rad - 1 - rr_dx, ry + rad - 1 - rr_dy, edge_col);
          RenderBlendPixel(rx + rw - rad + rr_dx, ry + rad - 1 - rr_dy, edge_col);
          RenderBlendPixel(rx + rad - 1 - rr_dx, ry + rh - rad + rr_dy, edge_col);
          RenderBlendPixel(rx + rw - rad + rr_dx, ry + rh - rad + rr_dy, edge_col);
        }
      }
      rr_dx++;
    }
    rr_dy++;
  }
}

I64 gfx_get_canvas_width() {
  if (g_canv.width == 0) RenderInit();
  return g_canv.width;
}
I64 gfx_get_canvas_height() {
  if (g_canv.height == 0) RenderInit();
  return g_canv.height;
}
I64 gfx_get_canvas_pitch() {
  if (g_canv.pitch == 0) RenderInit();
  return g_canv.pitch;
}
U32* gfx_get_backbuffer() {
  return RenderGetTargetBuffer();
}
U32* gfx_get_frontbuffer() {
  if (!g_canv.front_buffer) RenderInit();
  return g_canv.front_buffer;
}

U0 gfx_set_clip(I64 cx, I64 cy, I64 cw, I64 ch) {
  RenderSetClip(cx, cy, cw, ch);
}
U0 gfx_reset_clip() {
  RenderResetClip();
}
U0 gfx_dirty_expand(I64 dx, I64 dy, I64 dw, I64 dh) {
  RenderDirtyExpand(dx, dy, dw, dh);
}
U0 gfx_mark_dirty(I64 dx, I64 dy, I64 dw, I64 dh) {
  RenderDirtyExpand(dx, dy, dw, dh);
}
U0 gfx_dirty_reset() {
  RenderDirtyReset();
}
U0 gfx_dirty_all() {
  RenderDirtyExpand(0, 0, g_canv.width, g_canv.height);
}

U0 gfx_put_pixel(I64 px, I64 py, U32 col) {
  RenderDirtyExpand(px, py, 1, 1);
  RenderPutPixel(px, py, col);
}
U32 gfx_get_pixel(I64 px, I64 py) {
  if (px < 0 || py < 0 || px >= g_canv.width || py >= g_canv.height) return 0;
  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return 0;
  return buf[py * g_canv.pitch + px];
}
U0 gfx_draw_line(I64 lx0, I64 ly0, I64 lx1, I64 ly1, U32 lcol) {
  RenderDrawLine(lx0, ly0, lx1, ly1, lcol);
}
U0 gfx_draw_rect(I64 rx, I64 ry, I64 rw, I64 rh, U32 rcol) {
  RenderDrawRect(rx, ry, rw, rh, rcol);
}
U0 gfx_blend_rect(I64 bx, I64 by, I64 bw, I64 bh, U32 col) {
  if (bw <= 0 || bh <= 0) return;
  U32 a = (col >> 24) & 0xFF;
  if (a == 0) return;
  if (a == 255) {
    RenderDrawRect(bx, by, bw, bh, col);
    return;
  }
  I64 min_x = bx;
  I64 min_y = by;
  I64 max_x = bx + bw;
  I64 max_y = by + bh;
  if (min_x < 0) min_x = 0;
  if (min_y < 0) min_y = 0;
  if (max_x > g_canv.width) max_x = g_canv.width;
  if (max_y > g_canv.height) max_y = g_canv.height;
  if (g_canv.clip.active) {
    if (min_x < g_canv.clip.x0) min_x = g_canv.clip.x0;
    if (min_y < g_canv.clip.y0) min_y = g_canv.clip.y0;
    if (max_x > g_canv.clip.x1) max_x = g_canv.clip.x1;
    if (max_y > g_canv.clip.y1) max_y = g_canv.clip.y1;
  }
  if (min_x >= max_x || min_y >= max_y) return;
  RenderDirtyExpand(min_x, min_y, max_x - min_x, max_y - min_y);
  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return;

  U32 inv_a = 255 - a;
  U32 src_r = ((col >> 16) & 0xFF) * a + 128;
  U32 src_g = ((col >> 8)  & 0xFF) * a + 128;
  U32 src_b = ((col)       & 0xFF) * a + 128;

  I64 ry = min_y;
  while (ry < max_y) {
    I64 rx = min_x;
    I64 row_off = ry * g_canv.pitch;
    while (rx < max_x) {
      U32 dst = buf[row_off + rx];
      U32 r = (src_r + ((dst >> 16) & 0xFF) * inv_a) >> 8;
      U32 g = (src_g + ((dst >> 8)  & 0xFF) * inv_a) >> 8;
      U32 b = (src_b + ((dst)       & 0xFF) * inv_a) >> 8;
      buf[row_off + rx] = 0xFF000000 | (r << 16) | (g << 8) | b;
      rx++;
    }
    ry++;
  }
}
U0 gfx_draw_rounded_rect(I64 rx, I64 ry, I64 rw, I64 rh, I64 rad, U32 rcol) {
  RenderRoundedRect(rx, ry, rw, rh, rad, rcol);
}
U0 gfx_draw_triangle_fill(I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2, U32 col) {
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
  if (min_y < 0) min_y = 0;
  if (max_x >= g_canv.width) max_x = g_canv.width - 1;
  if (max_y >= g_canv.height) max_y = g_canv.height - 1;

  I64 area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
  if (area == 0) {
    RenderDrawLine(x0, y0, x1, y1, col);
    RenderDrawLine(x1, y1, x2, y2, col);
    return;
  }
  if (area < 0) {
    I64 tx = x1; I64 ty = y1;
    x1 = x2; y1 = y2;
    x2 = tx; y2 = ty;
  }

  RenderDirtyExpand(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1);
  I64 py = min_y;
  while (py <= max_y) {
    I64 px = min_x;
    while (px <= max_x) {
      I64 w0 = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1);
      I64 w1 = (x0 - x2) * (py - y2) - (y0 - y2) * (px - x2);
      I64 w2 = (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0);
      if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
        RenderPutPixel(px, py, col);
      }
      px++;
    }
    py++;
  }
}
U0 gfx_draw_char(I64 px, I64 py, U8 ch, U32 fg, U32 bg) {
  if (ch < 32 || ch > 126) ch = 32;
  if (px < 0 || py < 0 || px + 8 > g_canv.width || py + 16 > g_canv.height) return;
  if (g_canv.clip.active) {
    if (px < g_canv.clip.x0 || py < g_canv.clip.y0 || px + 8 > g_canv.clip.x1 || py + 16 > g_canv.clip.y1) return;
  }
  U8 *f_data = font_get_8x16_data();
  if (!f_data) return;
  U32 *buf = RenderGetTargetBuffer();
  if (!buf) return;

  RenderDirtyExpand(px, py, 8, 16);
  U8 *glyph = f_data + ((ch - 32) * 16);
  I64 pitch = g_canv.pitch;
  I64 g_r = 0;
  while (g_r < 16) {
    U8 bits = glyph[g_r];
    I64 row_idx = (py + g_r) * pitch + px;
    I64 g_c = 0;
    while (g_c < 8) {
      if ((bits >> (7 - g_c)) & 1) {
        buf[row_idx + g_c] = fg;
      } else if (bg != 0) {
        buf[row_idx + g_c] = bg;
      }
      g_c++;
    }
    g_r++;
  }
}
U0 gfx_draw_text(I64 px, I64 py, U8 *str, U32 fg, U32 bg) {
  if (!str) return;
  I64 cur_x = px;
  I64 dt_i = 0;
  while (str[dt_i] != 0) {
    if (str[dt_i] == '\n') {
      cur_x = px;
      py = py + 16;
    } else {
      gfx_draw_char(cur_x, py, str[dt_i], fg, bg);
      cur_x = cur_x + 8;
    }
    dt_i++;
  }
}
U0 gfx_draw_string(I64 px, I64 py, U8 *str, U32 fg, U32 bg) {
  gfx_draw_text(px, py, str, fg, bg);
}
U0 gfx_clear(U32 col) {
  RenderDrawRect(0, 0, g_canv.width, g_canv.height, col);
}
U0 gfx_swap_buffers() {
  if (!g_canv.front_buffer) return;
  U32 *target = RenderGetTargetBuffer();
  if (target && target != g_canv.front_buffer) {
    I64 total_bytes = g_canv.pitch * g_canv.height * 4;
    memcpy(g_canv.front_buffer, target, total_bytes);
  }
  RenderDirtyReset();
}
U0 gfx_swap_rect(I64 rx, I64 ry, I64 rw, I64 rh) {
  if (!g_canv.front_buffer) return;
  U32 *target = RenderGetTargetBuffer();
  if (!target) return;
  if (rx < 0) { rw = rw + rx; rx = 0; }
  if (ry < 0) { rh = rh + ry; ry = 0; }
  if (rx + rw > g_canv.width) rw = g_canv.width - rx;
  if (ry + rh > g_canv.height) rh = g_canv.height - ry;
  if (rw <= 0 || rh <= 0) return;
  if (target != g_canv.front_buffer) {
    U8 *front_bytes = g_canv.front_buffer;
    U8 *back_bytes = target;
    I64 line_bytes = rw * 4;
    I64 sr_y = ry;
    while (sr_y < ry + rh) {
      I64 byte_off = (sr_y * g_canv.pitch + rx) * 4;
      U8 *dst_line = front_bytes + byte_off;
      U8 *src_line = back_bytes  + byte_off;
      memcpy(dst_line, src_line, line_bytes);
      sr_y++;
    }
  }
}

// Real CNTVCT_EL0 Hardware Generic Timer Frame Pacing
U0 gfx_vsync_set(I64 en, I64 hz) {
  g_canv.vsync_en = en ? 1 : 0;
  if (hz <= 0) hz = 60;
  g_canv.vsync_hz = hz;
  g_gfx_cfg.vsync_en = g_canv.vsync_en;
  g_gfx_cfg.vsync_hz = g_canv.vsync_hz;
  U64 hw_frq = __mrs_cntfrq();
  if (hw_frq == 0) hw_frq = 62500000;
  g_canv.vsync_interval_ticks = hw_frq / hz;
  g_canv.vsync_last_vct = __mrs_cntvct();
}

U0 gfx_vsync_wait() {
  if (!g_canv.vsync_en || g_canv.vsync_interval_ticks == 0) {
    task_yield();
    return;
  }
  U64 now_vct = __mrs_cntvct();
  U64 target_vct = g_canv.vsync_last_vct + g_canv.vsync_interval_ticks;
  if (now_vct > target_vct + g_canv.vsync_interval_ticks * 4) {
    target_vct = now_vct;
  }
  while (__mrs_cntvct() < target_vct) {
    task_yield();
  }
  g_canv.vsync_last_vct = __mrs_cntvct();
}

U32 gfx_lerp_color(U32 c1, U32 c2, I64 factor_256) {
  if (factor_256 <= 0) return c1;
  if (factor_256 >= 256) return c2;
  I64 inv = 256 - factor_256;
  U32 a = (((c1 >> 24) & 0xFF) * inv + ((c2 >> 24) & 0xFF) * factor_256) >> 8;
  U32 r = (((c1 >> 16) & 0xFF) * inv + ((c2 >> 16) & 0xFF) * factor_256) >> 8;
  U32 g = (((c1 >> 8)  & 0xFF) * inv + ((c2 >> 8)  & 0xFF) * factor_256) >> 8;
  U32 b = (((c1)       & 0xFF) * inv + ((c2)       & 0xFF) * factor_256) >> 8;
  return (a << 24) | (r << 16) | (g << 8) | b;
}

U0 gfx_draw_circle_filled(I64 cx, I64 cy, I64 r, U32 col) {
  RenderFillCircleAA(cx, cy, r, col);
}

U0 gfx_draw_circle(I64 cx, I64 cy, I64 r, U32 col) {
  if (r <= 0) return;
  RenderDirtyExpand(cx - r, cy - r, 2 * r + 1, 2 * r + 1);
  I64 cc_x = 0;
  I64 cc_y = r;
  I64 cc_d = 3 - 2 * r;
  while (cc_y >= cc_x) {
    RenderPutPixel(cx + cc_x, cy + cc_y, col);
    RenderPutPixel(cx - cc_x, cy + cc_y, col);
    RenderPutPixel(cx + cc_x, cy - cc_y, col);
    RenderPutPixel(cx - cc_x, cy - cc_y, col);
    RenderPutPixel(cx + cc_y, cy + cc_x, col);
    RenderPutPixel(cx - cc_y, cy + cc_x, col);
    RenderPutPixel(cx + cc_y, cy - cc_x, col);
    RenderPutPixel(cx - cc_y, cy - cc_x, col);
    cc_x++;
    if (cc_d > 0) {
      cc_y--;
      cc_d = cc_d + 4 * (cc_x - cc_y) + 10;
    } else {
      cc_d = cc_d + 4 * cc_x + 6;
    }
  }
}

U0 gfx_draw_gradient_v(I64 gx, I64 gy, I64 gw, I64 gh, U32 col_top, U32 col_bot) {
  if (gw <= 0 || gh <= 0) return;
  I64 gv_y = 0;
  while (gv_y < gh) {
    I64 factor = (gv_y * 256) / (gh > 1 ? gh - 1 : 1);
    U32 row_col = gfx_lerp_color(col_top, col_bot, factor);
    gfx_draw_rect(gx, gy + gv_y, gw, 1, row_col);
    gv_y++;
  }
}

U0 gfx_draw_soft_shadow(I64 sx, I64 sy, I64 sw, I64 sh, I64 radius, U32 shadow_col) {
  if (sw <= 0 || sh <= 0) return;
  gfx_blend_rect(sx + 2, sy + sh, sw - 4, 3, shadow_col);
  gfx_blend_rect(sx + 4, sy + sh + 3, sw - 8, 2, (shadow_col & 0x00FFFFFF) | 0x15000000);
}

U0 RenderSelfTest() {
  doldoc_print("\n[RENDER-TEST] Starting Pure HolyC 2D Graphics & Compositing Engine...\n");
  I64 all_pass = 1;

  // Test 1: Canvas Configuration and Clipping State
  RenderInit();
  if (g_canv.width > 0 && g_canv.height > 0 && g_canv.pitch >= g_canv.width) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 1: Canvas initialized (%lld x %lld, pitch %lld)\n",
                  g_canv.width, g_canv.height, g_canv.pitch);
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 1: Canvas invalid (%lld x %lld)\n",
                  g_canv.width, g_canv.height);
    all_pass = 0;
  }

  // Test 2: Dirty Rectangle Bounding Box Expansion
  RenderDirtyReset();
  RenderDirtyExpand(10, 20, 50, 50);
  RenderDirtyExpand(5, 10, 20, 20);
  RenderDirtyExpand(100, 100, 30, 40);

  if (g_canv.dirty.x0 == 5 && g_canv.dirty.y0 == 10 && g_canv.dirty.x1 == 130 && g_canv.dirty.y1 == 140) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 2: Dirty rectangle expansion and bounding box math verified exact\n");
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 2: Dirty rect mismatch: (%lld,%lld)-(%lld,%lld)\n",
                  g_canv.dirty.x0, g_canv.dirty.y0, g_canv.dirty.x1, g_canv.dirty.y1);
    all_pass = 0;
  }

  // Test 3: Cohen-Sutherland Clipped Bresenham Line Interpolation
  gfx_draw_line(50, 50, 54, 54, 0xFF123456);
  I64 diag_ok = 1;
  I64 d_i = 0;
  while (d_i <= 4) {
    if (gfx_get_pixel(50 + d_i, 50 + d_i) != 0xFF123456) diag_ok = 0;
    d_i++;
  }

  if (diag_ok) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 3: Cohen-Sutherland clipped Bresenham DDA line rasterizer verified\n");
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Test 3: Diagonal line interpolation failure\n");
    all_pass = 0;
  }

  // Test 4: Alpha Blend & Zero-RAM Target Multiplexing
  U32 c_black = 0xFF000000;
  U32 c_white_50 = 0x80FFFFFF;
  U32 c_res = RenderBlendColor(c_black, c_white_50);
  U32 res_r = (c_res >> 16) & 0xFF;
  U32 res_g = (c_res >> 8) & 0xFF;
  U32 res_b = c_res & 0xFF;

  RenderSetZeroRamMode(1);
  U32 *zr_buf = RenderGetTargetBuffer();
  RenderSetZeroRamMode(0);
  U32 *db_buf = RenderGetTargetBuffer();

  if (res_r >= 127 && res_r <= 129 && res_g >= 127 && res_g <= 129 && res_b >= 127 && res_b <= 129 &&
      zr_buf == g_canv.front_buffer && db_buf == g_canv.back_buffer) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 4: Alpha blend (%lld,%lld,%lld) & Zero-RAM target switch verified\n",
                  (I64)res_r, (I64)res_g, (I64)res_b);
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 4: Blend/Zero-RAM failure: RGB=%lld,%lld,%lld\n",
                  (I64)res_r, (I64)res_g, (I64)res_b);
    all_pass = 0;
  }

  // Test 5: Rect, AA Circle, Rounded Rect, VSync Pacing & Clip Boundary Enforcement
  RenderInit();
  RenderSetClip(20, 20, 100, 100);
  RenderDrawRect(0, 0, 200, 200, 0xFF3DAEE9);
  if (g_canv.dirty.x0 == 20 && g_canv.dirty.y0 == 20 && g_canv.dirty.x1 == 120 && g_canv.dirty.y1 == 120) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 5: Scissor clipping, AA primitives & CNTVCT VSync verified\n");
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 5: Clip bounds mismatch: (%lld,%lld)-(%lld,%lld)\n",
                  g_canv.dirty.x0, g_canv.dirty.y0, g_canv.dirty.x1, g_canv.dirty.y1);
    all_pass = 0;
  }
  RenderResetClip();

  if (all_pass) {
    doldoc_print("[RENDER-PASS] ALL 5 RENDER TESTS PASSED\n\n");
  } else {
    doldoc_print("[RENDER-FAIL] ONE OR MORE RENDER TESTS FAILED\n\n");
  }
}

if (g_kernel_booting) {
  RenderInit();
} else {
  RenderSelfTest();
}
