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

// ==============================================================================
// P4.3: unified texture span state. The ONE rasterizer (RasterRow) reads
// `g_raster_tex_active`; when a texture is bound it runs the textured span, when
// not it runs the byte-identical NEON solid span (golden hash 0xD28836F). The
// per-texel work is scalar because AArch64 NEON has no gather; everything else
// (coverage, blending) stays in the unified pipeline. Wrap/filter codes match the
// GL constants HolyGL.HC passes.
// ==============================================================================
// Canonical OpenGL enum values (HolyGL passes these straight through; RasterTile
// is compiled before HolyGL, so it defines the same numeric values locally).
#define WRAP_REPEAT   0x2901
#define WRAP_CLAMP    0x812F
#define FILT_NEAREST  0x2600
#define FILT_LINEAR   0x2601

class CRasterTex {
  U32 *data;     // texels (ARGB); must be a typed pointer so data[i] scales by 4
  I64 w;
  I64 h;
  I64 wmask;     // w-1 (power-of-two mask for REPEAT)
  I64 hmask;     // h-1
  I64 wrap_s;
  I64 wrap_t;
  I64 filter;
  I64 blend_en;
};

CRasterTex g_rtex;
I64 g_raster_tex_active = 0;

// Per-vertex perspective attributes (fixed 16.16): u/W, v/W, 1/W. Set by HolyGL
// before each triangle via RasterSetTexUV.
I64 g_rt_uow0 = 0; I64 g_rt_uow1 = 0; I64 g_rt_uow2 = 0;
I64 g_rt_vow0 = 0; I64 g_rt_vow1 = 0; I64 g_rt_vow2 = 0;
I64 g_rt_iw0  = 0; I64 g_rt_iw1  = 0; I64 g_rt_iw2  = 0;

U0 RasterSetTexture(U32 *data, I64 w, I64 h, I64 wrap_s, I64 wrap_t, I64 filter) {
  g_rtex.data = data;
  g_rtex.w = w;
  g_rtex.h = h;
  g_rtex.wmask = w - 1;
  g_rtex.hmask = h - 1;
  g_rtex.wrap_s = wrap_s;
  g_rtex.wrap_t = wrap_t;
  g_rtex.filter = filter;
  g_raster_tex_active = 1;
}

U0 RasterSetBlend(I64 en) { g_rtex.blend_en = en ? 1 : 0; }

// Unbind: the unified span returns to the NEON solid path (used by the 2D golden
// scene so its hash is bit-exact).
U0 RasterDisableTexture() { g_raster_tex_active = 0; }
I64 RasterTextureActive() { return g_raster_tex_active; }

// idx: 0/1/2 -> vertex A/B/C. Values are F64 u/W, v/W, 1/W; stored as 16.16.
U0 RasterSetTexUV(I64 idx, F64 uow, F64 vow, F64 iw) {
  I64 a = (I64)(uow * 65536.0);
  I64 b = (I64)(vow * 65536.0);
  I64 c = (I64)(iw  * 65536.0);
  if (idx == 0) { g_rt_uow0 = a; g_rt_vow0 = b; g_rt_iw0 = c; }
  else if (idx == 1) { g_rt_uow1 = a; g_rt_vow1 = b; g_rt_iw1 = c; }
  else { g_rt_uow2 = a; g_rt_vow2 = b; g_rt_iw2 = c; }
}

// Called by RasterTriangleZ when it swaps B<->C to normalise winding, so the
// per-vertex attributes stay attached to the right vertex.
U0 RasterSwapTexUV12() {
  I64 t = g_rt_uow1; g_rt_uow1 = g_rt_uow2; g_rt_uow2 = t;
  t = g_rt_vow1; g_rt_vow1 = g_rt_vow2; g_rt_vow2 = t;
  t = g_rt_iw1;  g_rt_iw1  = g_rt_iw2;  g_rt_iw2  = t;
}

I64 RasterFloorF(F64 x) {
  I64 i = (I64)x;
  if ((F64)i > x) i = i - 1;
  return i;
}

// Wrap a signed texel coordinate and fetch one ARGB texel.
U32 RasterTexFetch(I64 tx, I64 ty) {
  if (g_rtex.wrap_s == WRAP_CLAMP) {
    if (tx < 0) tx = 0;
    if (tx > g_rtex.w - 1) tx = g_rtex.w - 1;
  } else {
    tx = tx & g_rtex.wmask;          // REPEAT (power-of-two mask handles negatives)
  }
  if (g_rtex.wrap_t == WRAP_CLAMP) {
    if (ty < 0) ty = 0;
    if (ty > g_rtex.h - 1) ty = g_rtex.h - 1;
  } else {
    ty = ty & g_rtex.hmask;
  }
  // D7 root fix (Compiler.HC): indexing a struct-member pointer (`g_rtex.data[k]`)
  // now strides by sizeof(pointee)=4 and emits LDR W. The old typed-local
  // workaround (`U32 *td = g_rtex.data; td[...]`) is no longer needed.
  return g_rtex.data[ty * g_rtex.w + tx];
}

// Bilinear tap of 4 texels. fx,fy in [0,1).
U32 RasterTexBilerp(U32 c00, U32 c10, U32 c01, U32 c11, F64 fx, F64 fy) {
  I64 w00 = (I64)((1.0 - fx) * (1.0 - fy) * 256.0);
  I64 w10 = (I64)(fx * (1.0 - fy) * 256.0);
  I64 w01 = (I64)((1.0 - fx) * fy * 256.0);
  I64 w11 = (I64)(fx * fy * 256.0);
  I64 r = ((((c00 >> 16) & 255) * w00 + ((c10 >> 16) & 255) * w10 +
            ((c01 >> 16) & 255) * w01 + ((c11 >> 16) & 255) * w11) >> 8);
  I64 g = ((((c00 >> 8) & 255) * w00 + ((c10 >> 8) & 255) * w10 +
            ((c01 >> 8) & 255) * w01 + ((c11 >> 8) & 255) * w11) >> 8);
  I64 b = ((((c00) & 255) * w00 + ((c10) & 255) * w10 +
            ((c01) & 255) * w01 + ((c11) & 255) * w11) >> 8);
  I64 a = ((((c00 >> 24) & 255) * w00 + ((c10 >> 24) & 255) * w10 +
            ((c01 >> 24) & 255) * w01 + ((c11 >> 24) & 255) * w11) >> 8);
  if (r > 255) r = 255; if (g > 255) g = 255; if (b > 255) b = 255; if (a > 255) a = 255;
  return ((U32)a << 24) | ((U32)r << 16) | ((U32)g << 8) | (U32)b;
}

// Sample the bound texture at (u,v) with the active filter.
U32 RasterTexSample(F64 u, F64 v) {
  if (g_rtex.filter == FILT_NEAREST) {
    I64 tx = (I64)(u * (F64)g_rtex.w);
    I64 ty = (I64)(v * (F64)g_rtex.h);
    return RasterTexFetch(tx, ty);
  }
  F64 x = u * (F64)g_rtex.w - 0.5;
  F64 y = v * (F64)g_rtex.h - 0.5;
  I64 x0 = RasterFloorF(x);
  I64 y0 = RasterFloorF(y);
  F64 fx = x - (F64)x0;
  F64 fy = y - (F64)y0;
  U32 c00 = RasterTexFetch(x0,     y0);
  U32 c10 = RasterTexFetch(x0 + 1, y0);
  U32 c01 = RasterTexFetch(x0,     y0 + 1);
  U32 c11 = RasterTexFetch(x0 + 1, y0 + 1);
  return RasterTexBilerp(c00, c10, c01, c11, fx, fy);
}

// GL_MODULATE: texel * vertex colour (alpha stays the texel's).
U32 RasterTexModulate(U32 texel, U32 color) {
  I64 r = (((texel >> 16) & 255) * ((color >> 16) & 255)) / 255;
  I64 g = (((texel >> 8)  & 255) * ((color >> 8)  & 255)) / 255;
  I64 b = (((texel)       & 255) * ((color)       & 255)) / 255;
  return ((texel >> 24) << 24) | ((U32)r << 16) | ((U32)g << 8) | (U32)b;
}

// GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA over the framebuffer pixel.
U32 RasterBlendSrcAlpha(U32 src, U32 dst) {
  if (g_rtex.blend_en == 0) return src;
  I64 sa = (src >> 24) & 255;
  I64 ia = 255 - sa;
  I64 r = ((((src >> 16) & 255) * sa + ((dst >> 16) & 255) * ia) + 127) / 255;
  I64 g = ((((src >> 8)  & 255) * sa + ((dst >> 8)  & 255) * ia) + 127) / 255;
  I64 b = ((((src)       & 255) * sa + ((dst)       & 255) * ia) + 127) / 255;
  if (r > 255) r = 255; if (g > 255) g = 255; if (b > 255) b = 255;
  return 0xFF000000 | ((U32)r << 16) | ((U32)g << 8) | (U32)b;
}

// One textured pixel of the unified span. Perspective-correct: interpolate
// (u/W, v/W, 1/W) barycentrically, recover (u,v) = (u/W)/(1/W).
I64 RasterPixelTextured(I64 xx, I64 yy) {
  I64 w0 = PinedaEdge(g_rj_bx, g_rj_by, g_rj_cx, g_rj_cy, xx, yy);
  I64 w1 = PinedaEdge(g_rj_cx, g_rj_cy, g_rj_ax, g_rj_ay, xx, yy);
  I64 w2 = PinedaEdge(g_rj_ax, g_rj_ay, g_rj_bx, g_rj_by, xx, yy);
  if ((w0 + g_rj_b0) < 0 || (w1 + g_rj_b1) < 0 || (w2 + g_rj_b2) < 0) return 0;
  I64 pz = (w0 * g_rj_az + w1 * g_rj_bz + w2 * g_rj_cz) / g_rj_area;
  if (pz < 0) pz = 0;
  if (pz > 65534) pz = 65534;
  I64 zi = yy * g_raster_cw + xx;
  if (g_raster_depth_test != 0 && pz >= g_zbuf[zi]) return 0;

  F64 l0 = (F64)w0 / (F64)g_rj_area;
  F64 l1 = (F64)w1 / (F64)g_rj_area;
  F64 l2 = (F64)w2 / (F64)g_rj_area;
  F64 cw = l0 * (F64)g_rt_iw0  + l1 * (F64)g_rt_iw1  + l2 * (F64)g_rt_iw2;
  F64 uu = l0 * (F64)g_rt_uow0 + l1 * (F64)g_rt_uow1 + l2 * (F64)g_rt_uow2;
  F64 vv = l0 * (F64)g_rt_vow0 + l1 * (F64)g_rt_vow1 + l2 * (F64)g_rt_vow2;
  F64 u = uu; F64 v = vv;
  if (cw > 0.0000001 || cw < -0.0000001) { u = uu / cw; v = vv / cw; }
  U32 texel = RasterTexSample(u, v);
  U32 src = RasterTexModulate(texel, g_rj_color);
  U32 dst = g_raster_fb[yy * g_raster_pitch + xx];
  U32 out = RasterBlendSrcAlpha(src, dst);
  if (g_raster_depth_test != 0) g_zbuf[zi] = pz;
  g_raster_fb[yy * g_raster_pitch + xx] = out;
  return 1;
}

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
//   0x90 tex_ptr (CRasterTex* or 0); then the per-vertex 16.16 attributes
//   0x98 uow0,0xA0 uow1,0xA8 uow2, 0xB0 vow0,0xB8 vow1,0xC0 vow2,
//   0xC8 iw0,0xD0 iw1,0xD8 iw2, and the per-pixel deltas
//   0xE0 dnumU,0xE8 dnumV,0xF0 dden  (p4.3b perspective accumulators)
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
  U64 tex_ptr;
  I64 uow0; I64 uow1; I64 uow2;
  I64 vow0; I64 vow1; I64 vow2;
  I64 iw0; I64 iw1; I64 iw2;
  I64 dnumU; I64 dnumV; I64 dden;
};
CRasterSpan g_rspan;

// NEON 8-pixel span kernel. The raw words are assembled from scripts/raster_span.s
// (regenerate/audit there). Returns the drawn pixel count in X0.
I64 RasterSpanNEON(CRasterSpan *s) {
  asm {

    0xA9BF53F3 0xA9BF5BF5 0xA9BF63F7 0xA9BF6BF9 0xA9BF73FB 0xD10203FF 0xAA0003E9 0xF9400121
    0xF9400522 0xF9400D23 0xF9401124 0xF9401525 0xF9401926 0xF9401D27 0xF9402128 0xF940252A
    0xF940292B 0xF9402D2C 0xF940312D 0xF940352E 0xF940392F 0xF9403D30 0xF9404131 0xB9408933
    0xB9408D34 0xD2800015 0x529FFFD9 0x4F000400 0x52800036 0x4E0C1EC0 0x52800056 0x4E141EC0
    0x52800076 0x4E1C1EC0 0x4F000481 0x528000B6 0x4E0C1EC1 0x528000D6 0x4E141EC1 0x528000F6
    0x4E1C1EC1 0x4E040CF0 0x4E040D11 0x4E040D52 0x4E040D73 0x4E040D94 0x4E040DB5 0x4EB09C16
    0x4EB09C37 0x4EB19C18 0x4EB19C39 0x4EB29C1A 0x4EB29C3B 0x4E040E6F 0x4F0767E8 0x4E040E69
    0x4EA81D29 0xB40037A3 0x4E040C82 0x4EB68442 0x4EB38442 0x4E040CA3 0x4EB88463 0x4EB48463
    0x4E040CC4 0x4EBA8484 0x4EB58484 0x4E040C85 0x4EB784A5 0x4EB384A5 0x4E040CA6 0x4EB984C6
    0x4EB484C6 0x4E040CC7 0x4EBB84E7 0x4EB584E7 0x6EA08842 0x6EA08863 0x6EA08884 0x4E231C42
    0x4E241C42 0x6EA088A5 0x6EA088C6 0x6EA088E7 0x4E261CA5 0x4E271CA5 0x0E612842 0x0E6128A5
    0x6E1804A2 0xAA0403F6 0xAA0503F7 0xAA0603F8 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00
    0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E021C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318
    0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320
    0x4E061C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00
    0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E0A1C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318
    0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320
    0x4E0E1C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00
    0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E121C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318
    0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320
    0x4E161C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00
    0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E1A1C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318
    0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320
    0x4E1E1C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x3DC0005D 0x34000074 0x6E7C37BE 0x4E3E1C42
    0x4EA21C5F 0x6E7D1F82 0x3D800042 0x4E205BE2 0x4E31B842 0x0E013C40 0x53047C00 0x8B0002B5
    0xF940493A 0xB500015A 0x4E5F3BE2 0x4E5F7BE3 0x3DC0002A 0x6E6A1DE2 0x3D800022 0x3DC0042A
    0x6E6A1DE3 0x3D800423 0x1400011D 0x4F008420 0x4F00E421 0x4F0387E6 0xF9404D36 0x9B167C96
    0xF940512C 0x9B0C58B6 0xF940552C 0x9B0C58D6 0xF9405937 0x9B177C97 0xF9405D2C 0x9B0C5CB7
    0xF940612C 0x9B0C5CD7 0xF9406538 0x9B187C98 0xF940692C 0x9B0C60B8 0xF9406D2C 0x9B0C60D8
    0xF940712F 0xF9407539 0xF940792B 0x4E083FFB 0x4E183FFC 0x910003F1 0xD2800000 0xF100101F
    0x54000041 0xAA1C03FB 0xF2403F7F 0x540013A0 0xD370BED3 0x9AD80E73 0xD370BEF4 0x9AD80E94
    0xF9401F4C 0x5284C00D 0xEB0D019F 0x54000461 0xF940074C 0x9B0C7E6D 0x9350FDAD 0xF9400B4E
    0x9B0E7E90 0x9350FE10 0xF940174C 0x3778008C 0xF9400F4C 0x8A0C01AD 0x14000007 0xF10001BF
    0x9A8DB3ED 0xF940074C 0xD100058C 0xEB0C01BF 0x9A8DC18D 0xF9401B4E 0x3778008E 0xF940134E
    0x8A0E0210 0x14000007 0xF100021F 0x9A90B3F0 0xF9400B4E 0xD10005CE 0xEB0E021F 0x9A90C1D0
    0xF940074C 0x9B0C360D 0xF940034E 0xB86D79CD 0xB900022D 0x14000073 0xF940074C 0x9B0C7E6E
    0xD14021CE 0xF9400B4D 0x9B0D7E90 0xD1402210 0x9350FDD3 0x92403DCC 0x9350FE14 0x92403E0D
    0xB90043EC 0xB90047ED 0xF940174E 0x3778008E 0xF9400F4E 0x8A0E0273 0x14000007 0xF100027F
    0x9A93B3F3 0xF940074E 0xD10005CE 0xEB0E027F 0x9A93C1D3 0xB90023F3 0x91000670 0xF940174E
    0x3778008E 0xF9400F4E 0x8A0E0210 0x14000007 0xF100021F 0x9A90B3F0 0xF940074E 0xD10005CE
    0xEB0E021F 0x9A90C1D0 0xB90027F0 0xF9401B4E 0x3778008E 0xF940134E 0x8A0E0294 0x14000007
    0xF100029F 0x9A94B3F4 0xF9400B4E 0xD10005CE 0xEB0E029F 0x9A94C1D4 0xB9002BF4 0x91000690
    0xF9401B4E 0x3778008E 0xF940134E 0x8A0E0210 0x14000007 0xF100021F 0x9A90B3F0 0xF9400B4E
    0xD10005CE 0xEB0E021F 0x9A90C1D0 0xB9002FF0 0xF940074C 0xF940034D 0xB9402BF4 0xB94023F3
    0x9B0C4E8E 0xB86E79AE 0xB90033EE 0xB94027F3 0x9B0C4E8E 0xB86E79AE 0xB90037EE 0xB9402FF4
    0xB94023F3 0x9B0C4E8E 0xB86E79AE 0xB9003BEE 0xB94027F3 0x9B0C4E8E 0xB86E79AE 0xB9003FEE
    0xB94043EC 0xB94047ED 0xD2A0002E 0xCB0C01D3 0xCB0D01D4 0x9B147E6E 0xD358FDCE 0x9B147D90
    0xD358FE10 0x9B0D7E73 0xD358FE73 0x9B0D7D8C 0xD358FD8C 0x0E020DC3 0x0E020E07 0x6E1804E3
    0x0E020E64 0x0E020D8C 0x6E180584 0x3DC00FE5 0x2F08A4A7 0x6F08A4AC 0x2E63C0ED 0x2E64818D
    0x6E63C0EE 0x6E64818E 0x4EAE85AD 0x0F1885AD 0x0E2129AD 0x0E043DAE 0xB900022E 0x14000001
    0xD350FF7B 0x8B0F02D6 0x8B1902F7 0x8B0B0318 0x91001231 0x91000400 0xF100201F 0x54FFEB01
    0x3DC003EA 0x3DC007EB 0x2E29C143 0x6E29C144 0x6F180465 0x4E658463 0x4E608463 0x6F180463
    0x6F180485 0x4E658484 0x4E608484 0x6F180484 0x0E21286A 0x0E212885 0x6E1804AA 0x2E29C163
    0x6E29C164 0x6F180465 0x4E658463 0x4E608463 0x6F180463 0x6F180485 0x4E658484 0x4E608484
    0x6F180484 0x0E21286B 0x0E212885 0x6E1804AB 0xF940234C 0xB400062C 0x3DC0002C 0x3DC0042D
    0x6F28054E 0x4EA19DCE 0x6E2059C5 0x2E2EC143 0x6E2EC144 0x2E25C187 0x6E25C18C 0x4E678463
    0x4E6C8484 0x4E668463 0x4E668484 0x6F180465 0x4E658463 0x4E608463 0x6F180463 0x6F180485
    0x4E658484 0x4E608484 0x6F180484 0x0E21286A 0x0E212885 0x6E1804AA 0x4EA81D4A 0x6F28056E
    0x4EA19DCE 0x6E2059C5 0x2E2EC163 0x6E2EC164 0x2E25C1A7 0x6E25C1AD 0x4E678463 0x4E6D8484
    0x4E668463 0x4E668484 0x6F180465 0x4E658463 0x4E608463 0x6F180463 0x6F180485 0x4E658484
    0x4E608484 0x6F180484 0x0E21286B 0x0E212885 0x6E1804AB 0x4EA81D6B 0x4E5F3BE2 0x4E5F7BE3
    0x3DC0002C 0x6E6C1D42 0x3D800022 0x3DC0042D 0x6E6D1D63 0x3D800423 0x14000001 0x91008021
    0x91004042 0x8B070C84 0x8B080CA5 0x8B0A0CC6 0xD1000463 0x17FFFE44 0xAA1503E0 0x910203FF
    0xA8C173FB 0xA8C16BF9 0xA8C163F7 0xA8C15BF5 0xA8C153F3
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

// Fill the CRasterSpan descriptor for the aligned 8-pixel blocks starting at
// (xx,yy) and invoke the ONE NEON kernel. `tex` selects the textured path
// (p4.3b, tex_ptr != 0) or the byte-identical solid path (tex_ptr == 0). The
// perspective accumulators numU/numV/den are affine in x, so the kernel advances
// them by dnumU/dnumV/dden per pixel with no per-pixel edge recomputation.
I64 RasterSpanBlocks(I64 xx, I64 yy, I64 tex) {
  I64 blocks = (g_raster_max_x - xx) >> 3;
  if (blocks <= 0) return 0;
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
  if (tex != 0) {
    g_rspan.tex_ptr = (U64)&g_rtex;
    g_rspan.uow0 = g_rt_uow0; g_rspan.uow1 = g_rt_uow1; g_rspan.uow2 = g_rt_uow2;
    g_rspan.vow0 = g_rt_vow0; g_rspan.vow1 = g_rt_vow1; g_rspan.vow2 = g_rt_vow2;
    g_rspan.iw0  = g_rt_iw0;  g_rspan.iw1  = g_rt_iw1;  g_rspan.iw2  = g_rt_iw2;
    g_rspan.dnumU = g_rspan.dw0 * g_rt_uow0 + g_rspan.dw1 * g_rt_uow1 + g_rspan.dw2 * g_rt_uow2;
    g_rspan.dnumV = g_rspan.dw0 * g_rt_vow0 + g_rspan.dw1 * g_rt_vow1 + g_rspan.dw2 * g_rt_vow2;
    g_rspan.dden  = g_rspan.dw0 * g_rt_iw0  + g_rspan.dw1 * g_rt_iw1  + g_rspan.dw2 * g_rt_iw2;
  } else {
    g_rspan.tex_ptr = 0;
  }
  return RasterSpanNEON(&g_rspan);
}

// Fill one scanline of the current triangle. ONE pipeline: when a texture is
// bound the aligned body runs the NEON textured span (p4.3b) and only the
// head/tail (<8 px) use the scalar perspective pixel; otherwise the
// byte-identical NEON solid span runs, preserving the golden hash.
I64 RasterRow(I64 yy) {
  if (g_raster_tex_active) {
    I64 xx = g_raster_min_x;
    I64 drawn = 0;
    while (xx < g_raster_max_x && (xx & 7) != 0) {
      drawn = drawn + RasterPixelTextured(xx, yy);
      xx = xx + 1;
    }
    I64 tb = (g_raster_max_x - xx) >> 3;
    if (tb > 0) {
      drawn = drawn + RasterSpanBlocks(xx, yy, 1);
      xx = xx + (tb << 3);
    }
    while (xx < g_raster_max_x) {
      drawn = drawn + RasterPixelTextured(xx, yy);
      xx = xx + 1;
    }
    return drawn;
  }
  I64 xx = g_raster_min_x;
  I64 drawn = 0;
  while (xx < g_raster_max_x && (xx & 7) != 0) {
    drawn = drawn + RasterPixelScalar(xx, yy);
    xx = xx + 1;
  }
  I64 blocks = (g_raster_max_x - xx) >> 3;
  if (blocks > 0) {
    drawn = drawn + RasterSpanBlocks(xx, yy, 0);
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
    RasterSwapTexUV12();   // keep per-vertex texture attributes attached to B/C
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
