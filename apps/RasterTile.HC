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

// ==============================================================================
// P7.3: L1 tile binning + per-core scratchpad + stnp streaming resolve.
// The immediate RasterTriangleZ path stays byte-identical (it now delegates to
// RasterTriangleZCore). A scene's triangles are binned into 64x64 tiles; each tile
// is rasterized into a per-core scratchpad by the ONE kernel, then resolved to the
// target with a non-temporal copy. Tiles are disjoint -> order-independent.
// ==============================================================================
#define RASTER_MAX_SCENE_TRIS     4096
#define RASTER_MAX_TRIS_PER_TILE  256
#define RASTER_MAX_TILES          (48 * 32)

// Screen-space integers (the ONE kernel is integer-exact; F64 members would cross
// the struct boundary as D0 and are unnecessary here).
class CRasterVertex { I64 x; I64 y; I64 z; };
class CRasterTri {
  I64 x[3];
  I64 y[3];
  I64 z[3];
  U32 color;
  I64 min_tx; I64 max_tx; I64 min_ty; I64 max_ty;
};
class CRasterBin { U16 idx[RASTER_MAX_TRIS_PER_TILE]; I64 count; };

CRasterTri  g_rs_tris[RASTER_MAX_SCENE_TRIS];
CRasterBin  g_rs_bins[RASTER_MAX_TILES];
I64 g_rs_tri_count = 0;
I64 g_rs_cols = 0;
I64 g_rs_rows = 0;
I64 g_rs_tile_size = 64;
U32 *g_rs_target = NULL;
I64 g_rs_pitch = 0;
U32 g_rs_clear = 0;
I64 g_rs_vx = 0; I64 g_rs_vy = 0; I64 g_rs_vw = 0; I64 g_rs_vh = 0;
I64 g_rs_cull = 0;
// 1D (not [4][N]): the self-hosted compiler mis-evaluates a partial index of a 2D
// global array (`g_arr[0]` for the first row yields NULL), so keep them flat and
// index per-core at `core*4096 + ...`.
U32 g_tile_color[4 * 4096];
U16 g_tile_depth[4 * 4096];

U0 RasterSetZ(I64 z0, I64 z1, I64 z2) {
  if (z0 < 0) z0 = 0; if (z0 > 65534) z0 = 65534;
  if (z1 < 0) z1 = 0; if (z1 > 65534) z1 = 65534;
  if (z2 < 0) z2 = 0; if (z2 > 65534) z2 = 65534;
  g_raster_z0 = z0;
  g_raster_z1 = z1;
  g_raster_z2 = z2;
}

U0 RasterSetDepthTest(I64 en) { g_raster_depth_test = en ? 1 : 0; }

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

// ------------------------------------------------------------------------------
// P4.5: smooth shading in the ONE rasterizer.
//   mode 0 = flat   (byte-identical to the golden solid path)
//   mode 1 = Gouraud (per-vertex lit colours, affine across the span)
//   mode 2 = per-fragment Blinn-Phong (per-vertex normals interpolated per pixel,
//            normalized with NEON FRSQRTE/FRSQRTS, diffuse + specular + gamma)
// All three run inside RasterSpanNEON; only the colour stage differs.
// ------------------------------------------------------------------------------
I64 g_rj_shade_mode = 0;
U32 g_rj_c0 = 0; U32 g_rj_c1 = 0; U32 g_rj_c2 = 0;
F64 g_rj_n0x = 0.0; F64 g_rj_n0y = 0.0; F64 g_rj_n0z = 1.0;
F64 g_rj_n1x = 0.0; F64 g_rj_n1y = 0.0; F64 g_rj_n1z = 1.0;
F64 g_rj_n2x = 0.0; F64 g_rj_n2y = 0.0; F64 g_rj_n2z = 1.0;
F64 g_rj_lx = 0.4472; F64 g_rj_ly = 0.6324; F64 g_rj_lz = 0.6324;
F64 g_rj_amb = 0.24; F64 g_rj_diff = 0.76; F64 g_rj_spec = 0.60;

// Gouraud: per-vertex lit ARGB colours, interpolated (affine) across the span.
U0 RasterSetColor3(U32 c0, U32 c1, U32 c2) {
  g_rj_c0 = c0; g_rj_c1 = c1; g_rj_c2 = c2;
  g_rj_shade_mode = 1;
}
// Per-fragment Phong: per-vertex normals (view space). idx 0/1/2 = vertex A/B/C.
U0 RasterSetNormal(I64 idx, F64 nx, F64 ny, F64 nz) {
  if (idx == 0) { g_rj_n0x = nx; g_rj_n0y = ny; g_rj_n0z = nz; }
  else if (idx == 1) { g_rj_n1x = nx; g_rj_n1y = ny; g_rj_n1z = nz; }
  else { g_rj_n2x = nx; g_rj_n2y = ny; g_rj_n2z = nz; }
}
U0 RasterSetLight(F64 lx, F64 ly, F64 lz) { g_rj_lx = lx; g_rj_ly = ly; g_rj_lz = lz; }
U0 RasterSetShading(F64 amb, F64 diff, F64 spec) { g_rj_amb = amb; g_rj_diff = diff; g_rj_spec = spec; }
U0 RasterEnablePhong() { g_rj_shade_mode = 2; }
U0 RasterDisableGouraud() { g_rj_shade_mode = 0; }
U0 RasterSwapColor12() {
  U32 t = g_rj_c1; g_rj_c1 = g_rj_c2; g_rj_c2 = t;
  F64 f = g_rj_n1x; g_rj_n1x = g_rj_n2x; g_rj_n2x = f;
  f = g_rj_n1y; g_rj_n1y = g_rj_n2y; g_rj_n2y = f;
  f = g_rj_n1z; g_rj_n1z = g_rj_n2z; g_rj_n2z = f;
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
//   0xF8 gmode (0 flat, 1 Gouraud, 2 Phong); then the smooth-shading state:
//   0x100 gr0,0x108 gg0,0x110 gb0   affine colour at x_start (0..1)
//   0x118 gdr,0x120 gdg,0x128 gdb   per-pixel colour delta
//   0x130 nr0,0x138 ng0,0x140 nb0   affine normal at x_start
//   0x148 ndr,0x150 ndg,0x158 ndb   per-pixel normal delta
//   0x160 lx,0x168 ly,0x170 lz      light direction (unit, view space)
//   0x178 hx,0x180 hy,0x188 hz      Blinn half vector (unit)
//   0x190 br2,0x198 bg2,0x1A0 bb2   base colour linearised ((c/255)^2)
//   0x1A8 amb,0x1B0 diff,0x1B8 spec lighting constants
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
  I64 gmode;
  F64 gr0; F64 gg0; F64 gb0;
  F64 gdr; F64 gdg; F64 gdb;
  F64 nr0; F64 ng0; F64 nb0;
  F64 ndr; F64 ndg; F64 ndb;
  F64 lx; F64 ly; F64 lz;
  F64 hx; F64 hy; F64 hz;
  F64 br2; F64 bg2; F64 bb2;
  F64 amb; F64 diff; F64 spec;
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
    0x4EA81D29 0xF9407D2C 0xB40012CC 0xF100099F 0x54000400 0xF940812B 0x9E670160 0x1E624000
    0x1E26000B 0xB90003EB 0xF940852B 0x9E670160 0x1E624000 0x1E26000B 0xB90007EB 0xF940892B
    0x9E670160 0x1E624000 0x1E26000B 0xB9000BEB 0xF9408D2B 0x9E670160 0x1E624000 0x1E26000B
    0xB9001BEB 0xF940912B 0x9E670160 0x1E624000 0x1E26000B 0xB9001FEB 0xF940952B 0x9E670160
    0x1E624000 0x1E26000B 0xB90023EB 0x1400001F 0xF940992B 0x9E670160 0x1E624000 0x1E26000B
    0xB90003EB 0xF9409D2B 0x9E670160 0x1E624000 0x1E26000B 0xB90007EB 0xF940A12B 0x9E670160
    0x1E624000 0x1E26000B 0xB9000BEB 0xF940A52B 0x9E670160 0x1E624000 0x1E26000B 0xB9001BEB
    0xF940A92B 0x9E670160 0x1E624000 0x1E26000B 0xB9001FEB 0xF940AD2B 0x9E670160 0x1E624000
    0x1E26000B 0xB90023EB 0xB9401BEB 0x1E270161 0x1E241002 0x1E220821 0x1E26002B 0xB9000FEB
    0xB9401FEB 0x1E270161 0x1E241002 0x1E220821 0x1E26002B 0xB90013EB 0xB94023EB 0x1E270161
    0x1E241002 0x1E220821 0x1E26002B 0xB90017EB 0xF940B12B 0x9E670160 0x1E624000 0x1E26000B
    0xB90027EB 0xF940B52B 0x9E670160 0x1E624000 0x1E26000B 0xB9002BEB 0xF940B92B 0x9E670160
    0x1E624000 0x1E26000B 0xB9002FEB 0xF940BD2B 0x9E670160 0x1E624000 0x1E26000B 0xB90033EB
    0xF940C12B 0x9E670160 0x1E624000 0x1E26000B 0xB90037EB 0xF940C52B 0x9E670160 0x1E624000
    0x1E26000B 0xB9003BEB 0xF940C92B 0x9E670160 0x1E624000 0x1E26000B 0xB9003FEB 0xF940CD2B
    0x9E670160 0x1E624000 0x1E26000B 0xB90043EB 0xF940D12B 0x9E670160 0x1E624000 0x1E26000B
    0xB90047EB 0xF940D52B 0x9E670160 0x1E624000 0x1E26000B 0xB9004BEB 0xF940D92B 0x9E670160
    0x1E624000 0x1E26000B 0xB9004FEB 0xF940DD2B 0x9E670160 0x1E624000 0x1E26000B 0xB90053EB
    0x52A86FEB 0xB90057EB 0x5280000B 0xB9005BEB 0x52A7F00B 0xB9005FEB 0x52A6B0CB 0xB90063EB
    0xB4006283 0x4E040C82 0x4EB68442 0x4EB38442 0x4E040CA3 0x4EB88463 0x4EB48463 0x4E040CC4
    0x4EBA8484 0x4EB58484 0x4E040C85 0x4EB784A5 0x4EB384A5 0x4E040CA6 0x4EB984C6 0x4EB484C6
    0x4E040CC7 0x4EBB84E7 0x4EB584E7 0x6EA08842 0x6EA08863 0x6EA08884 0x4E231C42 0x4E241C42
    0x6EA088A5 0x6EA088C6 0x6EA088E7 0x4E261CA5 0x4E271CA5 0x0E612842 0x0E6128A5 0x6E1804A2
    0xAA0403F6 0xAA0503F7 0xAA0603F8 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F
    0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E021C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0
    0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E061C1C
    0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F
    0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E0A1C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0
    0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E0E1C1C
    0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F
    0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E121C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0
    0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E161C1C
    0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0 0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F
    0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E1A1C1C 0x8B0702D6 0x8B0802F7 0x8B0A0318 0x9B0E7EC0
    0x9B0F02E0 0x9B100300 0x9AD10C00 0xEB1F001F 0x9A80B3E0 0xEB19001F 0x9A80C320 0x4E1E1C1C
    0x8B0702D6 0x8B0802F7 0x8B0A0318 0x3DC0005D 0x34000074 0x6E7C37BE 0x4E3E1C42 0x4EA21C5F
    0x6E7D1F82 0x3D800042 0x4E205BE2 0x4E31B842 0x0E013C40 0x53047C00 0x8B0002B5 0xF940493A
    0xB500019A 0xF9407D2C 0xB50024CC 0x4E5F3BE2 0x4E5F7BE3 0x3DC0002A 0x6E6A1DE2 0x3D800022
    0x3DC0042A 0x6E6A1DE3 0x3D800423 0x14000272 0x4F008420 0x4F00E421 0x4F0387E6 0xF9404D36
    0x9B167C96 0xF940512C 0x9B0C58B6 0xF940552C 0x9B0C58D6 0xF9405937 0x9B177C97 0xF9405D2C
    0x9B0C5CB7 0xF940612C 0x9B0C5CD7 0xF9406538 0x9B187C98 0xF940692C 0x9B0C60B8 0xF9406D2C
    0x9B0C60D8 0xF940712F 0xF9407539 0xF940792B 0x4E083FFB 0x4E183FFC 0x910003F1 0xD2800000
    0xF100101F 0x54000041 0xAA1C03FB 0xF2403F7F 0x540013A0 0xD370BED3 0x9AD80E73 0xD370BEF4
    0x9AD80E94 0xF9401F4C 0x5284C00D 0xEB0D019F 0x54000461 0xF940074C 0x9B0C7E6D 0x9350FDAD
    0xF9400B4E 0x9B0E7E90 0x9350FE10 0xF940174C 0x3778008C 0xF9400F4C 0x8A0C01AD 0x14000007
    0xF10001BF 0x9A8DB3ED 0xF940074C 0xD100058C 0xEB0C01BF 0x9A8DC18D 0xF9401B4E 0x3778008E
    0xF940134E 0x8A0E0210 0x14000007 0xF100021F 0x9A90B3F0 0xF9400B4E 0xD10005CE 0xEB0E021F
    0x9A90C1D0 0xF940074C 0x9B0C360D 0xF940034E 0xB86D79CD 0xB900022D 0x14000073 0xF940074C
    0x9B0C7E6E 0xD14021CE 0xF9400B4D 0x9B0D7E90 0xD1402210 0x9350FDD3 0x92403DCC 0x9350FE14
    0x92403E0D 0xB90043EC 0xB90047ED 0xF940174E 0x3778008E 0xF9400F4E 0x8A0E0273 0x14000007
    0xF100027F 0x9A93B3F3 0xF940074E 0xD10005CE 0xEB0E027F 0x9A93C1D3 0xB90023F3 0x91000670
    0xF940174E 0x3778008E 0xF9400F4E 0x8A0E0210 0x14000007 0xF100021F 0x9A90B3F0 0xF940074E
    0xD10005CE 0xEB0E021F 0x9A90C1D0 0xB90027F0 0xF9401B4E 0x3778008E 0xF940134E 0x8A0E0294
    0x14000007 0xF100029F 0x9A94B3F4 0xF9400B4E 0xD10005CE 0xEB0E029F 0x9A94C1D4 0xB9002BF4
    0x91000690 0xF9401B4E 0x3778008E 0xF940134E 0x8A0E0210 0x14000007 0xF100021F 0x9A90B3F0
    0xF9400B4E 0xD10005CE 0xEB0E021F 0x9A90C1D0 0xB9002FF0 0xF940074C 0xF940034D 0xB9402BF4
    0xB94023F3 0x9B0C4E8E 0xB86E79AE 0xB90033EE 0xB94027F3 0x9B0C4E8E 0xB86E79AE 0xB90037EE
    0xB9402FF4 0xB94023F3 0x9B0C4E8E 0xB86E79AE 0xB9003BEE 0xB94027F3 0x9B0C4E8E 0xB86E79AE
    0xB9003FEE 0xB94043EC 0xB94047ED 0xD2A0002E 0xCB0C01D3 0xCB0D01D4 0x9B147E6E 0xD358FDCE
    0x9B147D90 0xD358FE10 0x9B0D7E73 0xD358FE73 0x9B0D7D8C 0xD358FD8C 0x0E020DC3 0x0E020E07
    0x6E1804E3 0x0E020E64 0x0E020D8C 0x6E180584 0x3DC00FE5 0x2F08A4A7 0x6F08A4AC 0x2E63C0ED
    0x2E64818D 0x6E63C0EE 0x6E64818E 0x4EAE85AD 0x0F1885AD 0x0E2129AD 0x0E043DAE 0xB900022E
    0x14000001 0xD350FF7B 0x8B0F02D6 0x8B1902F7 0x8B0B0318 0x91001231 0x91000400 0xF100201F
    0x54FFEB01 0x3DC003EA 0x3DC007EB 0x2E29C143 0x6E29C144 0x6F180465 0x4E658463 0x4E608463
    0x6F180463 0x6F180485 0x4E658484 0x4E608484 0x6F180484 0x0E21286A 0x0E212885 0x6E1804AA
    0x2E29C163 0x6E29C164 0x6F180465 0x4E658463 0x4E608463 0x6F180463 0x6F180485 0x4E658484
    0x4E608484 0x6F180484 0x0E21286B 0x0E212885 0x6E1804AB 0xF940234C 0xB400062C 0x3DC0002C
    0x3DC0042D 0x6F28054E 0x4EA19DCE 0x6E2059C5 0x2E2EC143 0x6E2EC144 0x2E25C187 0x6E25C18C
    0x4E678463 0x4E6C8484 0x4E668463 0x4E668484 0x6F180465 0x4E658463 0x4E608463 0x6F180463
    0x6F180485 0x4E658484 0x4E608484 0x6F180484 0x0E21286A 0x0E212885 0x6E1804AA 0x4EA81D4A
    0x6F28056E 0x4EA19DCE 0x6E2059C5 0x2E2EC163 0x6E2EC164 0x2E25C1A7 0x6E25C1AD 0x4E678463
    0x4E6D8484 0x4E668463 0x4E668484 0x6F180465 0x4E658463 0x4E608463 0x6F180463 0x6F180485
    0x4E658484 0x4E608484 0x6F180484 0x0E21286B 0x0E212885 0x6E1804AB 0x4EA81D6B 0x4E5F3BE2
    0x4E5F7BE3 0x3DC0002C 0x6E6C1D42 0x3D800022 0x3DC0042D 0x6E6D1D63 0x3D800423 0x14000156
    0xF100059F 0x54000941 0xB94003EB 0xB9401BEC 0x4E040D6A 0x4E040D90 0x4E20CE0A 0x4E040D6B
    0x4E21CE0B 0xB94007EB 0xB9401FEC 0x4E040D6C 0x4E040D90 0x4E20CE0C 0x4E040D6D 0x4E21CE0D
    0xB9400BEB 0xB94023EC 0x4E040D6E 0x4E040D90 0x4E20CE0E 0x4E040D6F 0x4E21CE0F 0x4EA1B94A
    0x4EA1B96B 0x4EA1B98C 0x4EA1B9AD 0x4EA1B9CE 0x4EA1B9EF 0x4F000410 0x4F0707F1 0x4EB0654A
    0x4EB16D4A 0x4EB0656B 0x4EB16D6B 0x4EB0658C 0x4EB16D8C 0x4EB065AD 0x4EB16DAD 0x4EB065CE
    0x4EB16DCE 0x4EB065EF 0x4EB16DEF 0x4F30554A 0x4F28558C 0x4EAC1D4A 0x4EAE1D4A 0x4EA81D4A
    0x4F30556B 0x4F2855AD 0x4EAD1D6B 0x4EAF1D6B 0x4EA81D6B 0xB94003EB 0xB9400FEC 0x1E270160
    0x1E270181 0x1E212800 0x1E26000B 0xB90003EB 0xB94007EB 0xB94013EC 0x1E270160 0x1E270181
    0x1E212800 0x1E26000B 0xB90007EB 0xB9400BEB 0xB94017EC 0x1E270160 0x1E270181 0x1E212800
    0x1E26000B 0xB9000BEB 0x14000102 0xB94003EB 0xB9401BEC 0x4E040D62 0x4E040D85 0x4E20CCA2
    0xB94007EB 0xB9401FEC 0x4E040D63 0x4E040D85 0x4E20CCA3 0xB9400BEB 0xB94023EC 0x4E040D64
    0x4E040D85 0x4E20CCA4 0x6E22DC46 0x6E23DC67 0x4E27D4C6 0x6E24DC87 0x4E27D4C6 0xB94063EB
    0x4E040D67 0x4E27F4C6 0x6EA1D8C7 0x6E27DCE9 0x4EA9FCC9 0x6E29DCE7 0x6E27DC42 0x6E27DC63
    0x6E27DC84 0xB94027EB 0x4E040D65 0x6E25DC46 0xB9402BEB 0x4E040D65 0x6E25DC67 0x4E27D4C6
    0xB9402FEB 0x4E040D65 0x6E25DC87 0x4E27D4C6 0x4F000405 0x4E25F4C6 0xB94033EB 0x4E040D65
    0x6E25DC47 0xB94037EB 0x4E040D65 0x6E25DC69 0x4E29D4E7 0xB9403BEB 0x4E040D65 0x6E25DC89
    0x4E29D4E7 0x4F000405 0x4E25F4E7 0x6E27DCE7 0x6E27DCE7 0x6E27DCE7 0x6E27DCE7 0xB9404FEB
    0x4E040D65 0x6E26DCA5 0xB9404BEB 0x4E040D69 0x4E29D4A5 0xB94053EB 0x4E040D69 0x6E29DCE7
    0xB9403FEB 0x4E040D69 0x6E25DD29 0x4E27D529 0xB9405FEB 0x4E040D7C 0x4EBCF529 0x6EA1F929
    0xB94057EB 0x4E040D7C 0x6E3CDD29 0x4EA1B92A 0xB94043EB 0x4E040D69 0x6E25DD29 0x4E27D529
    0xB9405FEB 0x4E040D7C 0x4EBCF529 0x6EA1F929 0xB94057EB 0x4E040D7C 0x6E3CDD29 0x4EA1B92C
    0xB94047EB 0x4E040D69 0x6E25DD29 0x4E27D529 0xB9405FEB 0x4E040D7C 0x4EBCF529 0x6EA1F929
    0xB94057EB 0x4E040D7C 0x6E3CDD29 0x4EA1B92E 0x4F00041C 0x4F0707FD 0x4EBC654A 0x4EBD6D4A
    0x4EBC658C 0x4EBD6D8C 0x4EBC65CE 0x4EBD6DCE 0xB94003EB 0xB9401BEC 0x4E040D62 0x4E040D85
    0x4E21CCA2 0xB94007EB 0xB9401FEC 0x4E040D63 0x4E040D85 0x4E21CCA3 0xB9400BEB 0xB94023EC
    0x4E040D64 0x4E040D85 0x4E21CCA4 0x6E22DC46 0x6E23DC67 0x4E27D4C6 0x6E24DC87 0x4E27D4C6
    0xB94063EB 0x4E040D67 0x4E27F4C6 0x6EA1D8C7 0x6E27DCE9 0x4EA9FCC9 0x6E29DCE7 0x6E27DC42
    0x6E27DC63 0x6E27DC84 0xB94027EB 0x4E040D65 0x6E25DC46 0xB9402BEB 0x4E040D65 0x6E25DC67
    0x4E27D4C6 0xB9402FEB 0x4E040D65 0x6E25DC87 0x4E27D4C6 0x4F000405 0x4E25F4C6 0xB94033EB
    0x4E040D65 0x6E25DC47 0xB94037EB 0x4E040D65 0x6E25DC69 0x4E29D4E7 0xB9403BEB 0x4E040D65
    0x6E25DC89 0x4E29D4E7 0x4F000405 0x4E25F4E7 0x6E27DCE7 0x6E27DCE7 0x6E27DCE7 0x6E27DCE7
    0xB9404FEB 0x4E040D65 0x6E26DCA5 0xB9404BEB 0x4E040D69 0x4E29D4A5 0xB94053EB 0x4E040D69
    0x6E29DCE7 0xB9403FEB 0x4E040D69 0x6E25DD29 0x4E27D529 0xB9405FEB 0x4E040D7C 0x4EBCF529
    0x6EA1F929 0xB94057EB 0x4E040D7C 0x6E3CDD29 0x4EA1B92B 0xB94043EB 0x4E040D69 0x6E25DD29
    0x4E27D529 0xB9405FEB 0x4E040D7C 0x4EBCF529 0x6EA1F929 0xB94057EB 0x4E040D7C 0x6E3CDD29
    0x4EA1B92D 0xB94047EB 0x4E040D69 0x6E25DD29 0x4E27D529 0xB9405FEB 0x4E040D7C 0x4EBCF529
    0x6EA1F929 0xB94057EB 0x4E040D7C 0x6E3CDD29 0x4EA1B92F 0x4F00041C 0x4F0707FD 0x4EBC656B
    0x4EBD6D6B 0x4EBC65AD 0x4EBD6DAD 0x4EBC65EF 0x4EBD6DEF 0x4F30554A 0x4F28558C 0x4EAC1D4A
    0x4EAE1D4A 0x4EA81D4A 0x4F30556B 0x4F2855AD 0x4EAD1D6B 0x4EAF1D6B 0x4EA81D6B 0xB94003EB
    0xB9400FEC 0x1E270160 0x1E270181 0x1E212800 0x1E26000B 0xB90003EB 0xB94007EB 0xB94013EC
    0x1E270160 0x1E270181 0x1E212800 0x1E26000B 0xB90007EB 0xB9400BEB 0xB94017EC 0x1E270160
    0x1E270181 0x1E212800 0x1E26000B 0xB9000BEB 0x4E5F3BE2 0x4E5F7BE3 0x3DC0002C 0x6E6C1D42
    0x3D800022 0x3DC0042D 0x6E6D1D63 0x3D800423 0x14000001 0x91008021 0x91004042 0x8B070C84
    0x8B080CA5 0x8B0A0CC6 0xD1000463 0x17FFFCED 0xAA1503E0 0x910203FF 0xA8C173FB 0xA8C16BF9
    0xA8C163F7 0xA8C15BF5 0xA8C153F3
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
  // P4.5: smooth shading. Colour/normal are affine in x, so pass the value at
  // x_start plus the per-pixel delta; the NEON kernel accumulates per block.
  I64 mode = (tex != 0) ? 0 : g_rj_shade_mode;
  g_rspan.gmode = mode;
  if (mode != 0) {
    F64 inv_area = 1.0 / (F64)g_rspan.area;
    F64 nscale = inv_area;   // Gouraud colours are carried in 0..255 (not 0..1)
    U32 c0 = g_rj_c0; U32 c1 = g_rj_c1; U32 c2 = g_rj_c2;
    F64 c0r = (F64)((c0 >> 16) & 255); F64 c1r = (F64)((c1 >> 16) & 255); F64 c2r = (F64)((c2 >> 16) & 255);
    F64 c0g = (F64)((c0 >> 8) & 255);  F64 c1g = (F64)((c1 >> 8) & 255);  F64 c2g = (F64)((c2 >> 8) & 255);
    F64 c0b = (F64)(c0 & 255);         F64 c1b = (F64)(c1 & 255);         F64 c2b = (F64)(c2 & 255);
    g_rspan.gr0 = (g_rspan.w0 * c0r + g_rspan.w1 * c1r + g_rspan.w2 * c2r) * nscale;
    g_rspan.gg0 = (g_rspan.w0 * c0g + g_rspan.w1 * c1g + g_rspan.w2 * c2g) * nscale;
    g_rspan.gb0 = (g_rspan.w0 * c0b + g_rspan.w1 * c1b + g_rspan.w2 * c2b) * nscale;
    g_rspan.gdr = (g_rspan.dw0 * c0r + g_rspan.dw1 * c1r + g_rspan.dw2 * c2r) * nscale;
    g_rspan.gdg = (g_rspan.dw0 * c0g + g_rspan.dw1 * c1g + g_rspan.dw2 * c2g) * nscale;
    g_rspan.gdb = (g_rspan.dw0 * c0b + g_rspan.dw1 * c1b + g_rspan.dw2 * c2b) * nscale;
    if (mode == 2) {
      g_rspan.nr0 = (g_rspan.w0 * g_rj_n0x + g_rspan.w1 * g_rj_n1x + g_rspan.w2 * g_rj_n2x) * inv_area;
      g_rspan.ng0 = (g_rspan.w0 * g_rj_n0y + g_rspan.w1 * g_rj_n1y + g_rspan.w2 * g_rj_n2y) * inv_area;
      g_rspan.nb0 = (g_rspan.w0 * g_rj_n0z + g_rspan.w1 * g_rj_n1z + g_rspan.w2 * g_rj_n2z) * inv_area;
      g_rspan.ndr = (g_rspan.dw0 * g_rj_n0x + g_rspan.dw1 * g_rj_n1x + g_rspan.dw2 * g_rj_n2x) * inv_area;
      g_rspan.ndg = (g_rspan.dw0 * g_rj_n0y + g_rspan.dw1 * g_rj_n1y + g_rspan.dw2 * g_rj_n2y) * inv_area;
      g_rspan.ndb = (g_rspan.dw0 * g_rj_n0z + g_rspan.dw1 * g_rj_n1z + g_rspan.dw2 * g_rj_n2z) * inv_area;
      g_rspan.lx = g_rj_lx; g_rspan.ly = g_rj_ly; g_rspan.lz = g_rj_lz;
      F64 hx = g_rj_lx, hy = g_rj_ly, hz = g_rj_lz + 1.0;
      F64 hl = MathSqrt(hx * hx + hy * hy + hz * hz);
      if (hl > 0.0001) { hx = hx / hl; hy = hy / hl; hz = hz / hl; }
      g_rspan.hx = hx; g_rspan.hy = hy; g_rspan.hz = hz;
      F64 br = (F64)((g_rj_color >> 16) & 255) / 255.0;
      F64 bg = (F64)((g_rj_color >> 8)  & 255) / 255.0;
      F64 bb = (F64)(g_rj_color & 255) / 255.0;
      g_rspan.br2 = br * br; g_rspan.bg2 = bg * bg; g_rspan.bb2 = bb * bb;
      g_rspan.amb = g_rj_amb; g_rspan.diff = g_rj_diff; g_rspan.spec = g_rj_spec;
    }
  }
  return RasterSpanNEON(&g_rspan);
}

// Scalar shaded colour at a pixel, from its raw edge values (head/tail <8px).
// Mirrors the NEON colour stage exactly enough for the fill rule; the bulk of
// every row is still the NEON span.
U32 RasterShadeColorAt(I64 w0, I64 w1, I64 w2) {
  F64 ia = 1.0 / (F64)g_rj_area;
  F64 l0 = (F64)w0 * ia;
  F64 l1 = (F64)w1 * ia;
  F64 l2 = (F64)w2 * ia;
  if (g_rj_shade_mode == 2) {
    F64 nx = l0 * g_rj_n0x + l1 * g_rj_n1x + l2 * g_rj_n2x;
    F64 ny = l0 * g_rj_n0y + l1 * g_rj_n1y + l2 * g_rj_n2y;
    F64 nz = l0 * g_rj_n0z + l1 * g_rj_n1z + l2 * g_rj_n2z;
    F64 nl = MathSqrt(nx * nx + ny * ny + nz * nz);
    if (nl > 0.00001) { nx = nx / nl; ny = ny / nl; nz = nz / nl; }
    F64 ndl = nx * g_rj_lx + ny * g_rj_ly + nz * g_rj_lz;
    if (ndl < 0.0) ndl = 0.0;
    F64 hx = g_rj_lx, hy = g_rj_ly, hz = g_rj_lz + 1.0;
    F64 hl = MathSqrt(hx * hx + hy * hy + hz * hz);
    if (hl > 0.0001) { hx = hx / hl; hy = hy / hl; hz = hz / hl; }
    F64 ndh = nx * hx + ny * hy + nz * hz;
    if (ndh < 0.0) ndh = 0.0;
    F64 s = ndh * ndh; s = s * s; s = s * s; s = s * s; // ndh^16
    F64 lam = g_rj_amb + g_rj_diff * ndl;
    F64 br = (F64)((g_rj_color >> 16) & 255) / 255.0;
    F64 bg = (F64)((g_rj_color >> 8)  & 255) / 255.0;
    F64 bb = (F64)(g_rj_color & 255) / 255.0;
    F64 ir = br * br * lam + g_rj_spec * s; if (ir > 1.0) ir = 1.0;
    F64 ig = bg * bg * lam + g_rj_spec * s; if (ig > 1.0) ig = 1.0;
    F64 ib = bb * bb * lam + g_rj_spec * s; if (ib > 1.0) ib = 1.0;
    I64 r = (I64)(MathSqrt(ir) * 255.0 + 0.5);
    I64 g = (I64)(MathSqrt(ig) * 255.0 + 0.5);
    I64 b = (I64)(MathSqrt(ib) * 255.0 + 0.5);
    if (r > 255) r = 255; if (g > 255) g = 255; if (b > 255) b = 255;
    return 0xFF000000 | ((U32)r << 16) | ((U32)g << 8) | (U32)b;
  }
  // Gouraud: affine blend of the three lit vertex colours.
  I64 r = (I64)(l0 * (F64)((g_rj_c0 >> 16) & 255) + l1 * (F64)((g_rj_c1 >> 16) & 255) + l2 * (F64)((g_rj_c2 >> 16) & 255) + 0.5);
  I64 g = (I64)(l0 * (F64)((g_rj_c0 >> 8)  & 255) + l1 * (F64)((g_rj_c1 >> 8)  & 255) + l2 * (F64)((g_rj_c2 >> 8)  & 255) + 0.5);
  I64 b = (I64)(l0 * (F64)(g_rj_c0 & 255)        + l1 * (F64)(g_rj_c1 & 255)        + l2 * (F64)(g_rj_c2 & 255)        + 0.5);
  if (r < 0) r = 0; if (r > 255) r = 255;
  if (g < 0) g = 0; if (g > 255) g = 255;
  if (b < 0) b = 0; if (b > 255) b = 255;
  return 0xFF000000 | ((U32)r << 16) | ((U32)g << 8) | (U32)b;
}

I64 RasterPixelShaded(I64 xx, I64 yy) {
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
      g_raster_fb[yy * g_raster_pitch + xx] = RasterShadeColorAt(w0, w1, w2);
      return 1;
    }
  }
  return 0;
}

// Fill one scanline of the current triangle. ONE pipeline: when a texture is
// bound the aligned body runs the NEON textured span (p4.3b) and only the
// head/tail (<8 px) use the scalar perspective pixel; otherwise the NEON span
// runs the solid (gmode 0), Gouraud (1) or per-fragment Phong (2) colour stage.
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
  I64 smode = g_rj_shade_mode;
  I64 xx = g_raster_min_x;
  I64 drawn = 0;
  while (xx < g_raster_max_x && (xx & 7) != 0) {
    if (smode != 0) drawn = drawn + RasterPixelShaded(xx, yy);
    else drawn = drawn + RasterPixelScalar(xx, yy);
    xx = xx + 1;
  }
  I64 blocks = (g_raster_max_x - xx) >> 3;
  if (blocks > 0) {
    drawn = drawn + RasterSpanBlocks(xx, yy, 0);
    xx = xx + (blocks << 3);
  }
  while (xx < g_raster_max_x) {
    if (smode != 0) drawn = drawn + RasterPixelShaded(xx, yy);
    else drawn = drawn + RasterPixelScalar(xx, yy);
    xx = xx + 1;
  }
  return drawn;
}

// P7.3: the triangle body, hoisted so the tiled path can reuse the ONE kernel.
// It reads the globals g_raster_fb / g_raster_pitch / g_zbuf / g_zbuf_w / g_zbuf_h,
// which the caller sets (immediate path: RasterTriangleZ; tiled: RasterRenderTile).
I64 RasterTriangleZCore(I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2, U32 color) {
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
    RasterSwapColor12();   // keep per-vertex Gouraud colours attached to B/C
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

// Rasterize one screen-space triangle with per-vertex Z (set via RasterSetZ).
// Immediate path: bind the live target + depth buffer, then run the core.
I64 RasterTriangleZ(I64 x0, I64 y0, I64 x1, I64 y1, I64 x2, I64 y2, U32 color) {
  RasterInit();
  if (!g_zbuf) return 0;
  g_raster_fb = GfxDeviceTarget();
  if (!g_raster_fb) return 0;
  g_raster_pitch = gfx_get_canvas_pitch();
  return RasterTriangleZCore(x0, y0, x1, y1, x2, y2, color);
}

// ------------------------------------------------------------------------------
// P7.3 — tiled scene API. RasterSceneBegin sets the viewport; triangles are added
// in screen space; RasterSceneEnd bins + renders + resolves every tile. All state
// is global (BSS) — no heap, census-neutral.
// ------------------------------------------------------------------------------

// Non-temporal streaming row copy (source of truth: scripts/tile_resolve.s).
I64 TileResolveRow(U32 *dst, U32 *src, I64 n) {
  asm {
    0xaa0203e3 0xf100405f 0x5400012b 0xacc10420 0xacc10c22 0xac000400 0xac010c02 0x91010000
    0xd1004042 0xf100405f 0x54ffff2a 0xb40000a2 0xb8404424 0xb8004404 0xf1000442 0x54ffffa1
    0xaa0303e0
  }
}

U0 RasterSceneBegin(I64 vx, I64 vy, I64 vw, I64 vh, U32 clear) {
  RasterInit();
  g_rs_target = GfxDeviceTarget();
  g_rs_pitch = gfx_get_canvas_pitch();
  g_rs_vx = vx; g_rs_vy = vy; g_rs_vw = vw; g_rs_vh = vh;
  g_rs_clear = clear;
  g_rs_tile_size = TILE_W;
  g_rs_tri_count = 0;
  g_rs_cols = (vw + TILE_W - 1) / TILE_W;
  g_rs_rows = (vh + TILE_H - 1) / TILE_H;
  if (g_rs_cols < 1) g_rs_cols = 1;
  if (g_rs_rows < 1) g_rs_rows = 1;
  if (g_rs_cols > 48) g_rs_cols = 48;
  if (g_rs_rows > 32) g_rs_rows = 32;
  I64 nt = g_rs_cols * g_rs_rows;
  I64 i = 0;
  while (i < nt) { g_rs_bins[i].count = 0; i = i + 1; }
}

U0 RasterSceneAddTriangle(CRasterVertex *v, U32 color) {
  if (!v) return;
  if (g_rs_tri_count >= RASTER_MAX_SCENE_TRIS) return;
  I64 ax = v[0].x; I64 ay = v[0].y;
  I64 bx = v[1].x; I64 by = v[1].y;
  I64 cx = v[2].x; I64 cy = v[2].y;
  I64 area = PinedaEdge(ax, ay, bx, by, cx, cy);
  if (area == 0) return;
  if (g_rs_cull != 0 && area < 0) return;
  I64 min_x = ax; if (bx < min_x) min_x = bx; if (cx < min_x) min_x = cx;
  I64 max_x = ax; if (bx > max_x) max_x = bx; if (cx > max_x) max_x = cx;
  I64 min_y = ay; if (by < min_y) min_y = by; if (cy < min_y) min_y = cy;
  I64 max_y = ay; if (by > max_y) max_y = by; if (cy > max_y) max_y = cy;
  max_x = max_x + 1; max_y = max_y + 1;
  if (min_x < g_rs_vx) min_x = g_rs_vx;
  if (min_y < g_rs_vy) min_y = g_rs_vy;
  I64 vx1 = g_rs_vx + g_rs_vw;
  I64 vy1 = g_rs_vy + g_rs_vh;
  if (max_x > vx1) max_x = vx1;
  if (max_y > vy1) max_y = vy1;
  if (min_x >= max_x || min_y >= max_y) return;
  I64 min_tx = (min_x - g_rs_vx) / TILE_W;
  I64 max_tx = (max_x - 1 - g_rs_vx) / TILE_W;
  I64 min_ty = (min_y - g_rs_vy) / TILE_H;
  I64 max_ty = (max_y - 1 - g_rs_vy) / TILE_H;
  if (min_tx < 0) min_tx = 0;
  if (min_ty < 0) min_ty = 0;
  if (max_tx >= g_rs_cols) max_tx = g_rs_cols - 1;
  if (max_ty >= g_rs_rows) max_ty = g_rs_rows - 1;
  if (min_tx > max_tx || min_ty > max_ty) return;
  I64 ti = g_rs_tri_count;
  CRasterTri *t = &g_rs_tris[ti];
  t->x[0] = v[0].x; t->y[0] = v[0].y; t->z[0] = v[0].z;
  t->x[1] = v[1].x; t->y[1] = v[1].y; t->z[1] = v[1].z;
  t->x[2] = v[2].x; t->y[2] = v[2].y; t->z[2] = v[2].z;
  t->color = color;
  t->min_tx = min_tx; t->max_tx = max_tx; t->min_ty = min_ty; t->max_ty = max_ty;
  I64 ty = min_ty;
  while (ty <= max_ty) {
    I64 tx = min_tx;
    while (tx <= max_tx) {
      CRasterBin *b = &g_rs_bins[ty * g_rs_cols + tx];
      if (b->count < RASTER_MAX_TRIS_PER_TILE) {
        b->idx[b->count] = (U16)ti;
        b->count = b->count + 1;
      }
      tx = tx + 1;
    }
    ty = ty + 1;
  }
  g_rs_tri_count = g_rs_tri_count + 1;
}

// Render one tile into core-0's scratchpad, reusing the ONE kernel with local
// (tile-relative) coordinates; the Pineda edge functions are translation-invariant,
// so the result is bit-identical to the immediate path.
U0 RasterRenderTile(I64 t) {
  I64 tx = t % g_rs_cols;
  I64 ty = t / g_rs_cols;
  I64 ox = g_rs_vx + tx * TILE_W;
  I64 oy = g_rs_vy + ty * TILE_H;
  RenderNeonFill(&g_tile_color[0], 4096, g_rs_clear);
  memset(&g_tile_depth[0], 0xFF, 4096 * 2);
  U32 *sv_fb = g_raster_fb;
  I64 sv_pitch = g_raster_pitch;
  I64 sv_cw = g_raster_cw;
  U16 *sv_zb = g_zbuf;
  I64 sv_zw = g_zbuf_w;
  I64 sv_zh = g_zbuf_h;
  g_raster_fb = &g_tile_color[0]; g_raster_pitch = 64; g_raster_cw = 64;
  g_zbuf = &g_tile_depth[0]; g_zbuf_w = 64; g_zbuf_h = 64;
  CRasterBin *b = &g_rs_bins[t];
  I64 i = 0;
  while (i < b->count) {
    I64 ti = (I64)b->idx[i];
    CRasterTri *tr = &g_rs_tris[ti];
    RasterSetZ(tr->z[0], tr->z[1], tr->z[2]);
    RasterTriangleZCore(tr->x[0] - ox, tr->y[0] - oy,
                        tr->x[1] - ox, tr->y[1] - oy,
                        tr->x[2] - ox, tr->y[2] - oy, tr->color);
    i = i + 1;
  }
  g_raster_fb = sv_fb; g_raster_pitch = sv_pitch; g_raster_cw = sv_cw;
  g_zbuf = sv_zb; g_zbuf_w = sv_zw; g_zbuf_h = sv_zh;
}

// Resolve one tile: colour to the target via the stnp kernel, depth to the main
// Z-buffer, clipped to the viewport and to the partial last tile.
U0 RasterTileResolve(I64 t) {
  if (!g_rs_target) return;
  I64 tx = t % g_rs_cols;
  I64 ty = t / g_rs_cols;
  I64 ox = g_rs_vx + tx * TILE_W;
  I64 oy = g_rs_vy + ty * TILE_H;
  I64 tw = TILE_W;
  I64 th = TILE_H;
  if (ox + tw > g_rs_vx + g_rs_vw) tw = g_rs_vx + g_rs_vw - ox;
  if (oy + th > g_rs_vy + g_rs_vh) th = g_rs_vy + g_rs_vh - oy;
  if (tw <= 0 || th <= 0) return;
  I64 r = 0;
  while (r < th) {
    U32 *src = &g_tile_color[r * TILE_W];
    U32 *dst = &g_rs_target[(oy + r) * g_rs_pitch + ox];
    TileResolveRow(dst, src, tw);
    U16 *zsrc = &g_tile_depth[r * TILE_W];
    I64 c = 0;
    while (c < tw) {
      g_zbuf[(oy + r) * g_zbuf_w + ox + c] = zsrc[c];
      c = c + 1;
    }
    r = r + 1;
  }
}

U0 RasterSceneEnd() {
  if (!g_rs_target) return;
  I64 nt = g_rs_cols * g_rs_rows;
  I64 t = 0;
  while (t < nt) { RasterRenderTile(t); RasterTileResolve(t); t = t + 1; }
}

// P7.3 self-test (called from apps/SelfTest.HC -> TILE: PASS). All three checks use
// private scratch/global state, then restore a clean frame.
U32 g_tile_snap_fb[256 * 256];
U16 g_tile_snap_zb[256 * 256];
CRasterVertex g_tile_tmpv[3];

U0 RasterSelfTestTile() {
  RasterInit();
  U32 *fb = GfxDeviceTarget();
  if (!fb || !g_zbuf) { doldoc_print("TILE: FAIL (no target/zbuf)\n"); return; }
  RasterDisableTexture();
  RasterDisableGouraud();
  RasterSetDepthTest(1);
  I64 ok = 1;
  I64 pit = gfx_get_canvas_pitch();
  I64 zw = g_zbuf_w;
  I64 R = 256;
  U32 BG = 0xFF202020;
  U32 COL = 0xFFE04010;
  I64 y = 0;
  I64 x = 0;

  // (1) tiled vs immediate: pixel- and Z-identical over [0,R)^2.
  gfx_clear(BG);
  RasterClearZ();
  RasterSetZ(100, 200, 300);
  RasterTriangleZ(30, 30, 200, 60, 90, 180, COL);
  y = 0;
  while (y < R) {
    x = 0;
    while (x < R) {
      g_tile_snap_fb[y * R + x] = fb[y * pit + x];
      g_tile_snap_zb[y * R + x] = g_zbuf[y * zw + x];
      x = x + 1;
    }
    y = y + 1;
  }
  gfx_clear(BG);
  RasterClearZ();
  g_tile_tmpv[0].x = 30;  g_tile_tmpv[0].y = 30;  g_tile_tmpv[0].z = 100;
  g_tile_tmpv[1].x = 200; g_tile_tmpv[1].y = 60;  g_tile_tmpv[1].z = 200;
  g_tile_tmpv[2].x = 90;  g_tile_tmpv[2].y = 180; g_tile_tmpv[2].z = 300;
  RasterSceneBegin(0, 0, R, R, BG);
  RasterSceneAddTriangle(g_tile_tmpv, COL);
  RasterSceneEnd();
  I64 diff = 0;
  I64 immed_col = 0;
  I64 tiled_col = 0;
  I64 fx = -1;
  I64 fy = -1;
  U32 fbv = 0;
  U32 svv = 0;
  y = 0;
  while (y < R) {
    x = 0;
    while (x < R) {
      U32 ta = fb[y * pit + x];
      U32 tb = g_tile_snap_fb[y * R + x];
      if (ta == COL) tiled_col = tiled_col + 1;
      if (tb == COL) immed_col = immed_col + 1;
      if (ta != tb) { diff = diff + 1; if (fx < 0) { fx = x; fy = y; fbv = ta; svv = tb; } }
      if (g_zbuf[y * zw + x] != g_tile_snap_zb[y * R + x]) diff = diff + 1;
      x = x + 1;
    }
    y = y + 1;
  }
  if (immed_col == 0 || tiled_col != immed_col) { ok = 0; doldoc_printf("[TILE] coverage immed=%lld tiled=%lld\n", immed_col, tiled_col); }
  if (diff != 0) { ok = 0; doldoc_printf("[TILE] tiled!=immediate diff=%lld\n", diff); }

  // (2) shared-edge square [60,120)^2 straddling 4 tiles: no gaps.
  gfx_clear(BG);
  RasterClearZ();
  RasterSceneBegin(0, 0, R, R, BG);
  g_tile_tmpv[0].x = 60;  g_tile_tmpv[0].y = 60;  g_tile_tmpv[0].z = 1;
  g_tile_tmpv[1].x = 120; g_tile_tmpv[1].y = 60;  g_tile_tmpv[1].z = 1;
  g_tile_tmpv[2].x = 120; g_tile_tmpv[2].y = 120; g_tile_tmpv[2].z = 1;
  RasterSceneAddTriangle(g_tile_tmpv, COL);
  g_tile_tmpv[0].x = 60;  g_tile_tmpv[0].y = 60;  g_tile_tmpv[0].z = 1;
  g_tile_tmpv[1].x = 120; g_tile_tmpv[1].y = 120; g_tile_tmpv[1].z = 1;
  g_tile_tmpv[2].x = 60;  g_tile_tmpv[2].y = 120; g_tile_tmpv[2].z = 1;
  RasterSceneAddTriangle(g_tile_tmpv, COL);
  RasterSceneEnd();
  I64 gaps = 0;
  y = 60;
  while (y < 120) {
    x = 60;
    while (x < 120) {
      if (fb[y * pit + x] != COL) gaps = gaps + 1;
      x = x + 1;
    }
    y = y + 1;
  }
  if (gaps != 0) { ok = 0; doldoc_printf("[TILE] shared-edge gaps=%lld\n", gaps); }

  // (3) no write past the scratchpad: guard words after g_tile_color[0]/g_tile_depth[0].
  g_tile_color[4096] = 0xDEADBEEF; g_tile_color[4097] = 0xDEADBEEF;
  g_tile_depth[4096] = 0x1234;     g_tile_depth[4097] = 0x5678;
  RasterSceneBegin(0, 0, R, R, BG);
  g_tile_tmpv[0].x = 0;   g_tile_tmpv[0].y = 0;   g_tile_tmpv[0].z = 1;
  g_tile_tmpv[1].x = 300; g_tile_tmpv[1].y = 0;   g_tile_tmpv[1].z = 1;
  g_tile_tmpv[2].x = 0;   g_tile_tmpv[2].y = 300; g_tile_tmpv[2].z = 1;
  RasterSceneAddTriangle(g_tile_tmpv, COL);
  g_tile_tmpv[0].x = 5000; g_tile_tmpv[0].y = 5000; g_tile_tmpv[0].z = 1;
  g_tile_tmpv[1].x = 5100; g_tile_tmpv[1].y = 5000; g_tile_tmpv[1].z = 1;
  g_tile_tmpv[2].x = 5000; g_tile_tmpv[2].y = 5100; g_tile_tmpv[2].z = 1;
  RasterSceneAddTriangle(g_tile_tmpv, COL);
  RasterRenderTile(0);
  if (g_tile_color[4096] != 0xDEADBEEF || g_tile_color[4097] != 0xDEADBEEF) { ok = 0; doldoc_print("[TILE] color scratchpad overrun\n"); }
  if (g_tile_depth[4096] != 0x1234 || g_tile_depth[4097] != 0x5678) { ok = 0; doldoc_print("[TILE] depth scratchpad overrun\n"); }

  gfx_clear(0xFF000000);
  RasterClearZ();
  doldoc_mark_all_dirty();

  if (ok != 0) doldoc_print("TILE: PASS\n");
  else doldoc_print("TILE: FAIL\n");
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
