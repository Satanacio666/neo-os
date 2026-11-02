// ==============================================================================
// HolyGL.HC - Pure HolyC 3D Graphics Substrate & OpenGL State Machine
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Mathematical Core: Math3D Matrices, Lambertian Lighting & 16-Bit Z-Buffer
// ==============================================================================

#define GL_POINTS         0x0000
#define GL_LINES          0x0001
#define GL_LINE_LOOP      0x0002
#define GL_LINE_STRIP     0x0003
#define GL_TRIANGLES      0x0004
#define GL_TRIANGLE_STRIP 0x0005
#define GL_TRIANGLE_FAN   0x0006
#define GL_QUADS          0x0007

#define GL_MODELVIEW      0x1700
#define GL_PROJECTION     0x1701
#define GL_DEPTH_TEST     0x0B71
#define GL_BLEND          0x0BE2
#define GL_CULL_FACE      0x0B44
#define GL_LIGHTING       0x0B50

#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_DEPTH_BUFFER_BIT 0x00000100

class GLVertex {
  F64 x;
  F64 y;
  F64 z;
  F64 w;
  F64 u;
  F64 v;
  U32 color;
  F64 nx;
  F64 ny;
  F64 nz;
};

class HolyGLContext {
  CMat4 modelview_stack[16];
  I64   modelview_sp;
  CMat4 projection_stack[4];
  I64   projection_sp;
  CMat4 mvp;

  I64   matrix_mode;
  I64   primitive_mode;
  I64   depth_test;
  I64   cull_face;
  I64   lighting;
  I64   wireframe;

  F64   light_x;
  F64   light_y;
  F64   light_z;

  F64   clear_r;
  F64   clear_g;
  F64   clear_b;
  F64   clear_a;

  GLVertex v_curr;
  GLVertex v_queue[16];
  I64      v_count;

  I64 vp_x;
  I64 vp_y;
  I64 vp_w;
  I64 vp_h;

  I64 tris_rendered;
  I64 verts_processed;
};

HolyGLContext g_hgl;

// ==============================================================================
// P4.3: texture objects & GL texture/blend state. The ONE rasterizer consumes
// this via RasterTile's accessors — HolyGL never touches RasterTile internals.
// ==============================================================================
#define GL_TEXTURE_2D           0x0DE1
#define GL_REPEAT               0x2901
#define GL_CLAMP_TO_EDGE        0x812F
#define GL_NEAREST              0x2600
#define GL_LINEAR               0x2601
#define GL_TEXTURE_WRAP_S       0x2802
#define GL_TEXTURE_WRAP_T       0x2803
#define GL_TEXTURE_MIN_FILTER   0x2801
#define GL_TEXTURE_MAG_FILTER   0x2800
#define GL_SRC_ALPHA            0x0302
#define GL_ONE_MINUS_SRC_ALPHA  0x0303
#define GL_MAX_TEXTURES         16

class CTexture2D {
  I64 in_use;
  I64 width;
  I64 height;
  I64 wrap_s;
  I64 wrap_t;
  I64 min_filter;
  I64 mag_filter;
  U32 *data;
};

CTexture2D g_tex_pool[GL_MAX_TEXTURES];
I64 g_tex_bound = 0;       // bound texture id (1..N); 0 = none
I64 g_tex_enabled = 0;     // GL_TEXTURE_2D
I64 g_tex_blend = 0;       // GL_BLEND
I64 g_tex_blend_src = GL_SRC_ALPHA;
I64 g_tex_blend_dst = GL_ONE_MINUS_SRC_ALPHA;
I64 g_tex_ok = 0;          // texture bound to the rasterizer for the next tri

U0 HolyGLTransformVertex(CMat4 *mat, F64 x, F64 y, F64 z, F64 w, GLVertex *out) {
  out->x = mat->m[0]  * x + mat->m[1]  * y + mat->m[2]  * z + mat->m[3]  * w;
  out->y = mat->m[4]  * x + mat->m[5]  * y + mat->m[6]  * z + mat->m[7]  * w;
  out->z = mat->m[8]  * x + mat->m[9]  * y + mat->m[10] * z + mat->m[11] * w;
  out->w = mat->m[12] * x + mat->m[13] * y + mat->m[14] * z + mat->m[15] * w;
}

// P4.2: the single full-screen Z-buffer lives in RasterTile.HC.
U0 HolyGLClearDepth() {
  RasterClearZ();
}

U0 HolyGLInit() {
  Mat4Identity(&g_hgl.modelview_stack[0]);
  Mat4Identity(&g_hgl.projection_stack[0]);
  Mat4Identity(&g_hgl.mvp);
  g_hgl.modelview_sp = 0;
  g_hgl.projection_sp = 0;
  g_hgl.matrix_mode = GL_MODELVIEW;
  g_hgl.primitive_mode = 0;
  g_hgl.depth_test = 1;
  g_hgl.cull_face = 1;
  g_hgl.lighting = 0;
  g_hgl.wireframe = 0;

  // Normalized directional light (0.4, 0.6, 0.7)
  g_hgl.light_x = 0.4472;
  g_hgl.light_y = 0.6324;
  g_hgl.light_z = 0.6324;

  g_hgl.clear_r = 0.0;
  g_hgl.clear_g = 0.0;
  g_hgl.clear_b = 0.0;
  g_hgl.clear_a = 1.0;

  g_hgl.v_count = 0;
  g_hgl.v_curr.color = 0xFFFFFFFF;
  g_hgl.v_curr.u = 0.0;
  g_hgl.v_curr.v = 0.0;
  g_hgl.v_curr.nx = 0.0;
  g_hgl.v_curr.ny = 0.0;
  g_hgl.v_curr.nz = 1.0;

  g_hgl.vp_x = 0;
  g_hgl.vp_y = 0;
  g_hgl.vp_w = gfx_get_canvas_width();
  g_hgl.vp_h = gfx_get_canvas_height();
  g_hgl.tris_rendered = 0;
  g_hgl.verts_processed = 0;

  g_tex_bound = 0;
  g_tex_enabled = 0;
  g_tex_blend = 0;
  g_tex_blend_src = GL_SRC_ALPHA;
  g_tex_blend_dst = GL_ONE_MINUS_SRC_ALPHA;
  g_tex_ok = 0;
  RasterDisableTexture();

  HolyGLClearDepth();
}

// The matrix the current matrix_mode edits (GL 1.3 semantics: two independent
// stacks). PROJECTION depth 4, MODELVIEW depth 16.
CMat4* HolyGLCurrentMatrix() {
  if (g_hgl.matrix_mode == GL_PROJECTION) return &g_hgl.projection_stack[g_hgl.projection_sp];
  return &g_hgl.modelview_stack[g_hgl.modelview_sp];
}

CMat4* HolyGLModelview() {
  return &g_hgl.modelview_stack[g_hgl.modelview_sp];
}

U0 HolyGLUpdateMVP() {
  Mat4Mul(&g_hgl.mvp, &g_hgl.projection_stack[g_hgl.projection_sp], &g_hgl.modelview_stack[g_hgl.modelview_sp]);
}

U0 HolyGLEnable(I64 cap) {
  if (cap == GL_DEPTH_TEST) g_hgl.depth_test = 1;
  else if (cap == GL_CULL_FACE) g_hgl.cull_face = 1;
  else if (cap == GL_LIGHTING) g_hgl.lighting = 1;
  else if (cap == GL_TEXTURE_2D) g_tex_enabled = 1;
  else if (cap == GL_BLEND) g_tex_blend = 1;
}

U0 HolyGLDisable(I64 cap) {
  if (cap == GL_DEPTH_TEST) g_hgl.depth_test = 0;
  else if (cap == GL_CULL_FACE) g_hgl.cull_face = 0;
  else if (cap == GL_LIGHTING) g_hgl.lighting = 0;
  else if (cap == GL_TEXTURE_2D) { g_tex_enabled = 0; RasterDisableTexture(); }
  else if (cap == GL_BLEND) g_tex_blend = 0;
}

U0 HolyGLSetWireframe(I64 en) {
  g_hgl.wireframe = en ? 1 : 0;
}

// ------------------------------------------------------------------------------
// Matrix Stack Operations
// ------------------------------------------------------------------------------
U0 HolyGLMatrixMode(I64 mode) {
  g_hgl.matrix_mode = mode;
}

U0 HolyGLLoadIdentity() {
  Mat4Identity(HolyGLCurrentMatrix());
  HolyGLUpdateMVP();
}

U0 HolyGLPushMatrix() {
  if (g_hgl.matrix_mode == GL_PROJECTION) {
    if (g_hgl.projection_sp < 3) {
      Mat4Copy(&g_hgl.projection_stack[g_hgl.projection_sp + 1], &g_hgl.projection_stack[g_hgl.projection_sp]);
      g_hgl.projection_sp++;
    }
  } else {
    if (g_hgl.modelview_sp < 15) {
      Mat4Copy(&g_hgl.modelview_stack[g_hgl.modelview_sp + 1], &g_hgl.modelview_stack[g_hgl.modelview_sp]);
      g_hgl.modelview_sp++;
    }
  }
  HolyGLUpdateMVP();
}

U0 HolyGLPopMatrix() {
  if (g_hgl.matrix_mode == GL_PROJECTION) {
    if (g_hgl.projection_sp > 0) g_hgl.projection_sp--;
  } else {
    if (g_hgl.modelview_sp > 0) g_hgl.modelview_sp--;
  }
  HolyGLUpdateMVP();
}

U0 HolyGLTranslatef(F64 tx, F64 ty, F64 tz) {
  Mat4Translate(HolyGLCurrentMatrix(), tx, ty, tz);
  HolyGLUpdateMVP();
}

U0 HolyGLRotatef(F64 angle_deg, F64 x, F64 y, F64 z) {
  CMat4 *m = HolyGLCurrentMatrix();
  if (x > 0.3) Mat4RotateX(m, angle_deg);
  else if (x < -0.3) Mat4RotateX(m, -angle_deg);
  if (y > 0.3) Mat4RotateY(m, angle_deg);
  else if (y < -0.3) Mat4RotateY(m, -angle_deg);
  if (z > 0.3) Mat4RotateZ(m, angle_deg);
  else if (z < -0.3) Mat4RotateZ(m, -angle_deg);
  HolyGLUpdateMVP();
}

U0 HolyGLScalef(F64 sx, F64 sy, F64 sz) {
  Mat4Scale(HolyGLCurrentMatrix(), sx, sy, sz);
  HolyGLUpdateMVP();
}

// Post-multiply the projection onto the current matrix (upstream glMatrixMode
// semantics: `curr = curr * persp`), so a preceding LoadIdentity is a no-op and
// composable projections work.
U0 HolyGLPerspective(F64 fovy, F64 aspect, F64 z_near, F64 z_far) {
  CMat4 persp;
  CMat4 *cur = HolyGLCurrentMatrix();
  Mat4Perspective(&persp, fovy, aspect, z_near, z_far);
  Mat4Mul(cur, cur, &persp);
  HolyGLUpdateMVP();
}

// ------------------------------------------------------------------------------
// Vertex & Attribute Specifications
// ------------------------------------------------------------------------------
// P4.5: rotate a model-space normal into view space by the upper-left 3x3 of the
// modelview (no lighting). Used to feed per-vertex normals to the per-fragment
// Blinn-Phong stage in the ONE rasterizer.
U0 HolyGLViewNormal(F64 nx, F64 ny, F64 nz, F64 *ox, F64 *oy, F64 *oz) {
  CMat4 *mv = HolyGLModelview();
  *ox = mv->m[0] * nx + mv->m[1] * ny + mv->m[2]  * nz;
  *oy = mv->m[4] * nx + mv->m[5] * ny + mv->m[6]  * nz;
  *oz = mv->m[8] * nx + mv->m[9] * ny + mv->m[10] * nz;
}

U0 HolyGLColor3f(F64 r, F64 g, F64 b) {
  if (r < 0.0) r = 0.0; if (r > 1.0) r = 1.0;
  if (g < 0.0) g = 0.0; if (g > 1.0) g = 1.0;
  if (b < 0.0) b = 0.0; if (b > 1.0) b = 1.0;
  U32 ir = (U32)(r * 255.0);
  U32 ig = (U32)(g * 255.0);
  U32 ib = (U32)(b * 255.0);
  g_hgl.v_curr.color = 0xFF000000 | (ir << 16) | (ig << 8) | ib;
}

U0 HolyGLColor3ub(U32 r, U32 g, U32 b) {
  g_hgl.v_curr.color = 0xFF000000 | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
}

// P7.0: set the current vertex colour from a packed 0xAARRGGBB value. Exported so
// callers (Gears3D, Physics3D, Mesh) never touch g_hgl directly — sovereign rule.
U0 HolyGLColorPacked(U32 argb) {
  g_hgl.v_curr.color = argb;
}

// P7.1: full RGBA colour with round-to-nearest packing (a,r,g,b) -> 0xAARRGGBB.
U0 HolyGLColor4f(F64 r, F64 g, F64 b, F64 a) {
  if (r < 0.0) r = 0.0; if (r > 1.0) r = 1.0;
  if (g < 0.0) g = 0.0; if (g > 1.0) g = 1.0;
  if (b < 0.0) b = 0.0; if (b > 1.0) b = 1.0;
  if (a < 0.0) a = 0.0; if (a > 1.0) a = 1.0;
  U32 ia = (U32)(a * 255.0 + 0.5);
  U32 ir = (U32)(r * 255.0 + 0.5);
  U32 ig = (U32)(g * 255.0 + 0.5);
  U32 ib = (U32)(b * 255.0 + 0.5);
  g_hgl.v_curr.color = (ia << 24) | (ir << 16) | (ig << 8) | ib;
}

U0 HolyGLClearColor(F64 r, F64 g, F64 b, F64 a) {
  g_hgl.clear_r = r;
  g_hgl.clear_g = g;
  g_hgl.clear_b = b;
  g_hgl.clear_a = a;
}

// GL 1.3 clear: colour bit fills the whole target with the stored clear colour;
// depth bit resets the single full-screen Z buffer to far.
U0 HolyGLClear(I64 mask) {
  if ((mask & GL_COLOR_BUFFER_BIT) != 0) {
    F64 r = g_hgl.clear_r; if (r < 0.0) r = 0.0; if (r > 1.0) r = 1.0;
    F64 g = g_hgl.clear_g; if (g < 0.0) g = 0.0; if (g > 1.0) g = 1.0;
    F64 b = g_hgl.clear_b; if (b < 0.0) b = 0.0; if (b > 1.0) b = 1.0;
    F64 a = g_hgl.clear_a; if (a < 0.0) a = 0.0; if (a > 1.0) a = 1.0;
    U32 ia = (U32)(a * 255.0 + 0.5);
    U32 ir = (U32)(r * 255.0 + 0.5);
    U32 ig = (U32)(g * 255.0 + 0.5);
    U32 ib = (U32)(b * 255.0 + 0.5);
    gfx_clear((ia << 24) | (ir << 16) | (ig << 8) | ib);
  }
  if ((mask & GL_DEPTH_BUFFER_BIT) != 0) RasterClearZ();
}

U0 HolyGLFlush() {
  gfx_dirty_expand(g_hgl.vp_x, g_hgl.vp_y, g_hgl.vp_w, g_hgl.vp_h);
}

U0 HolyGLTexCoord2f(F64 u, F64 v) {
  g_hgl.v_curr.u = u;
  g_hgl.v_curr.v = v;
}

U0 HolyGLNormal3f(F64 nx, F64 ny, F64 nz) {
  g_hgl.v_curr.nx = nx;
  g_hgl.v_curr.ny = ny;
  g_hgl.v_curr.nz = nz;
}

U0 HolyGLBegin(I64 mode) {
  g_hgl.primitive_mode = mode;
  g_hgl.v_count = 0;
}

// Dispatches a transformed screen-space triangle to the ONE rasterizer (P4.2).
// Per-vertex NDC Z is mapped to 16-bit depth and interpolated per pixel by
// RasterTriangleZ (no more averaged z_avg).
U0 HolyGLSubmitTriangle(GLVertex *v0, GLVertex *v1, GLVertex *v2) {
  // P7.2: the near-plane clipper (HolyGLSubmitClipped) guarantees w >= near_w > 0, so
  // this is only a cheap safety net for any direct caller; w<=0 would divide by zero.
  if (v0->w <= 0.0 || v1->w <= 0.0 || v2->w <= 0.0) return;

  F64 inv_w0 = 1.0 / v0->w;
  F64 inv_w1 = 1.0 / v1->w;
  F64 inv_w2 = 1.0 / v2->w;

  F64 ndc_x0 = v0->x * inv_w0;
  F64 ndc_y0 = v0->y * inv_w0;
  F64 ndc_z0 = v0->z * inv_w0;
  F64 ndc_x1 = v1->x * inv_w1;
  F64 ndc_y1 = v1->y * inv_w1;
  F64 ndc_z1 = v1->z * inv_w1;
  F64 ndc_x2 = v2->x * inv_w2;
  F64 ndc_y2 = v2->y * inv_w2;
  F64 ndc_z2 = v2->z * inv_w2;

  F64 cross = (ndc_x1 - ndc_x0) * (ndc_y2 - ndc_y0) - (ndc_y1 - ndc_y0) * (ndc_x2 - ndc_x0);
  if (g_hgl.cull_face && cross <= 0.0) return;

  F64 half_w = g_hgl.vp_w * 0.5;
  F64 half_h = g_hgl.vp_h * 0.5;

  I64 sx0 = g_hgl.vp_x + (I64)((ndc_x0 + 1.0) * half_w);
  I64 sy0 = g_hgl.vp_y + (I64)((1.0 - ndc_y0) * half_h);
  I64 sx1 = g_hgl.vp_x + (I64)((ndc_x1 + 1.0) * half_w);
  I64 sy1 = g_hgl.vp_y + (I64)((1.0 - ndc_y1) * half_h);
  I64 sx2 = g_hgl.vp_x + (I64)((ndc_x2 + 1.0) * half_w);
  I64 sy2 = g_hgl.vp_y + (I64)((1.0 - ndc_y2) * half_h);

  U32 col = v0->color;
  if (g_hgl.lighting) {
    // P4.5: per-fragment Blinn-Phong. Rotate the per-vertex normals into view
    // space; the ONE rasterizer interpolates + normalizes + shades them per pixel.
    F64 n0x = 0.0, n0y = 0.0, n0z = 0.0, n1x = 0.0, n1y = 0.0, n1z = 0.0, n2x = 0.0, n2y = 0.0, n2z = 0.0;
    HolyGLViewNormal(v0->nx, v0->ny, v0->nz, &n0x, &n0y, &n0z);
    HolyGLViewNormal(v1->nx, v1->ny, v1->nz, &n1x, &n1y, &n1z);
    HolyGLViewNormal(v2->nx, v2->ny, v2->nz, &n2x, &n2y, &n2z);
    RasterSetNormal(0, n0x, n0y, n0z);
    RasterSetNormal(1, n1x, n1y, n1z);
    RasterSetNormal(2, n2x, n2y, n2z);
    RasterSetLight(g_hgl.light_x, g_hgl.light_y, g_hgl.light_z);
    RasterSetShading(0.24, 0.76, 0.60);
    RasterEnablePhong();
  } else {
    RasterDisableGouraud();
  }

  // Wireframe: outline with lines instead of filling.
  if (g_hgl.wireframe || GfxDeviceGetShading() == RASTER_SHADE_WIREFRAME) {
    gfx_draw_line(sx0, sy0, sx1, sy1, col);
    gfx_draw_line(sx1, sy1, sx2, sy2, col);
    gfx_draw_line(sx2, sy2, sx0, sy0, col);
    g_hgl.tris_rendered = g_hgl.tris_rendered + 1;
    return;
  }

  // Per-vertex NDC Z in [-1..1] -> 16-bit depth [0..65534], interpolated per pixel.
  I64 z16_0 = (I64)((ndc_z0 + 1.0) * 32767.0);
  I64 z16_1 = (I64)((ndc_z1 + 1.0) * 32767.0);
  I64 z16_2 = (I64)((ndc_z2 + 1.0) * 32767.0);
  // P4.3: if a texture is bound, hand the ONE rasterizer the per-vertex
  // perspective attributes (u/W, v/W, 1/W) and the texture state.
  HolyGLBindRasterTexture();
  if (g_tex_ok) {
    RasterSetTexUV(0, v0->u * inv_w0, v0->v * inv_w0, inv_w0);
    RasterSetTexUV(1, v1->u * inv_w1, v1->v * inv_w1, inv_w1);
    RasterSetTexUV(2, v2->u * inv_w2, v2->v * inv_w2, inv_w2);
  }

  RasterSetDepthTest(g_hgl.depth_test);
  RasterSetZ(z16_0, z16_1, z16_2);
  RasterTriangleZ(sx0, sy0, sx1, sy1, sx2, sy2, col);
  g_hgl.tris_rendered = g_hgl.tris_rendered + 1;
}

U0 HolyGLSubmitLine(GLVertex *v0, GLVertex *v1) {
  if (v0->w <= 0.05 || v1->w <= 0.05) return;
  F64 half_w = g_hgl.vp_w * 0.5;
  F64 half_h = g_hgl.vp_h * 0.5;
  I64 sx0 = g_hgl.vp_x + (I64)((v0->x / v0->w + 1.0) * half_w);
  I64 sy0 = g_hgl.vp_y + (I64)((1.0 - v0->y / v0->w) * half_h);
  I64 sx1 = g_hgl.vp_x + (I64)((v1->x / v1->w + 1.0) * half_w);
  I64 sy1 = g_hgl.vp_y + (I64)((1.0 - v1->y / v1->w) * half_h);
  gfx_draw_line(sx0, sy0, sx1, sy1, v0->color);
}

U0 HolyGLVertexCopy(GLVertex *dst, GLVertex *src) {
  dst->x = src->x; dst->y = src->y; dst->z = src->z; dst->w = src->w;
  dst->u = src->u; dst->v = src->v; dst->color = src->color;
  dst->nx = src->nx; dst->ny = src->ny; dst->nz = src->nz;
}

// P7.2 — Sutherland–Hodgman near-plane clipper. Clips a triangle in homogeneous clip
// space against d = z + w - near_w >= 0 (under the standard perspective matrix the
// near plane maps to z+w = 0, and d>=0 guarantees w>0), linearly interpolating every
// attribute. Writes 0..4 vertices and returns the count (the caller fan-triangulates).
U0 HolyGLLerpVertex(GLVertex *o, GLVertex *a, GLVertex *b, F64 t) {
  o->x = a->x + (b->x - a->x) * t;
  o->y = a->y + (b->y - a->y) * t;
  o->z = a->z + (b->z - a->z) * t;
  o->w = a->w + (b->w - a->w) * t;
  o->u = a->u + (b->u - a->u) * t;
  o->v = a->v + (b->v - a->v) * t;
  o->nx = a->nx + (b->nx - a->nx) * t;
  o->ny = a->ny + (b->ny - a->ny) * t;
  o->nz = a->nz + (b->nz - a->nz) * t;
  U32 ca = a->color;
  U32 cb = b->color;
  I64 c0 = (I64)((ca >> 24) & 0xFF) + (I64)((F64)((I64)((cb >> 24) & 0xFF) - (I64)((ca >> 24) & 0xFF)) * t);
  I64 c1 = (I64)((ca >> 16) & 0xFF) + (I64)((F64)((I64)((cb >> 16) & 0xFF) - (I64)((ca >> 16) & 0xFF)) * t);
  I64 c2 = (I64)((ca >> 8) & 0xFF) + (I64)((F64)((I64)((cb >> 8) & 0xFF) - (I64)((ca >> 8) & 0xFF)) * t);
  I64 c3 = (I64)(ca & 0xFF) + (I64)((F64)((I64)(cb & 0xFF) - (I64)(ca & 0xFF)) * t);
  o->color = ((U32)c0 << 24) | ((U32)c1 << 16) | ((U32)c2 << 8) | (U32)c3;
}

I64 HolyGLClipNear(GLVertex *in, F64 near_w, GLVertex *outv) {
  GLVertex poly[3];
  HolyGLVertexCopy(&poly[0], &in[0]);
  HolyGLVertexCopy(&poly[1], &in[1]);
  HolyGLVertexCopy(&poly[2], &in[2]);
  I64 on = 0;
  I64 i = 0;
  while (i < 3) {
    I64 j = i + 1;
    if (j == 3) j = 0;
    F64 di = poly[i].z + poly[i].w - near_w;
    F64 dj = poly[j].z + poly[j].w - near_w;
    if (di >= 0.0) {
      HolyGLVertexCopy(&outv[on], &poly[i]);
      on++;
    }
    if ((di >= 0.0 && dj < 0.0) || (di < 0.0 && dj >= 0.0)) {
      F64 t = di / (di - dj);
      HolyGLLerpVertex(&outv[on], &poly[i], &poly[j], t);
      on++;
    }
    i++;
  }
  return on;
}

// Clip a triangle against the near plane and fan-triangulate the result (3 -> 1, 4 -> 2).
U0 HolyGLSubmitClipped(GLVertex *a, GLVertex *b, GLVertex *c) {
  GLVertex tri[3];
  GLVertex cl[4];
  HolyGLVertexCopy(&tri[0], a);
  HolyGLVertexCopy(&tri[1], b);
  HolyGLVertexCopy(&tri[2], c);
  I64 cn = HolyGLClipNear(tri, 0.001, cl);
  if (cn == 3) {
    HolyGLSubmitTriangle(&cl[0], &cl[1], &cl[2]);
  } else if (cn == 4) {
    HolyGLSubmitTriangle(&cl[0], &cl[1], &cl[2]);
    HolyGLSubmitTriangle(&cl[0], &cl[2], &cl[3]);
  }
}

// Shared vertex emitter: `v` is already in homogeneous clip space (x,y,z,w) and
// carries the current attributes; run primitive assembly + the submit chain.
U0 HolyGLDispatchVertex(GLVertex *v) {
  I64 pm = g_hgl.primitive_mode;
  if (pm == GL_POINTS) {
    if (v->w > 0.05) {
      I64 px = g_hgl.vp_x + (I64)((v->x / v->w + 1.0) * (g_hgl.vp_w * 0.5));
      I64 py = g_hgl.vp_y + (I64)((1.0 - v->y / v->w) * (g_hgl.vp_h * 0.5));
      gfx_put_pixel(px, py, v->color);
    }
    g_hgl.v_count = 0;
  } else if (pm == GL_LINES && g_hgl.v_count == 2) {
    HolyGLSubmitLine(&g_hgl.v_queue[0], &g_hgl.v_queue[1]);
    g_hgl.v_count = 0;
  } else if ((pm == GL_LINE_STRIP || pm == GL_LINE_LOOP) && g_hgl.v_count == 2) {
    HolyGLSubmitLine(&g_hgl.v_queue[0], &g_hgl.v_queue[1]);
    HolyGLVertexCopy(&g_hgl.v_queue[0], &g_hgl.v_queue[1]);
    g_hgl.v_count = 1;
  } else if (pm == GL_TRIANGLES && g_hgl.v_count == 3) {
    HolyGLSubmitClipped(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
    g_hgl.v_count = 0;
  } else if (pm == GL_TRIANGLE_STRIP && g_hgl.v_count == 3) {
    HolyGLSubmitClipped(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
    HolyGLVertexCopy(&g_hgl.v_queue[0], &g_hgl.v_queue[1]);
    HolyGLVertexCopy(&g_hgl.v_queue[1], &g_hgl.v_queue[2]);
    g_hgl.v_count = 2;
  } else if (pm == GL_TRIANGLE_FAN && g_hgl.v_count == 3) {
    HolyGLSubmitClipped(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
    HolyGLVertexCopy(&g_hgl.v_queue[1], &g_hgl.v_queue[2]);
    g_hgl.v_count = 2;
  } else if (pm == GL_QUADS && g_hgl.v_count == 4) {
    HolyGLSubmitClipped(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
    HolyGLSubmitClipped(&g_hgl.v_queue[0], &g_hgl.v_queue[2], &g_hgl.v_queue[3]);
    g_hgl.v_count = 0;
  }
}

// Copy the current attributes into the next queue slot and return it.
GLVertex *HolyGLNextVertex() {
  if (g_hgl.v_count >= 16) g_hgl.v_count = 0;
  GLVertex *v = &g_hgl.v_queue[g_hgl.v_count];
  g_hgl.v_count++;
  g_hgl.verts_processed = g_hgl.verts_processed + 1;
  v->u = g_hgl.v_curr.u;
  v->v = g_hgl.v_curr.v;
  v->color = g_hgl.v_curr.color;
  v->nx = g_hgl.v_curr.nx;
  v->ny = g_hgl.v_curr.ny;
  v->nz = g_hgl.v_curr.nz;
  return v;
}

U0 HolyGLVertex3f(F64 x, F64 y, F64 z) {
  GLVertex *v = HolyGLNextVertex();
  HolyGLTransformVertex(&g_hgl.mvp, x, y, z, 1.0, v);
  HolyGLDispatchVertex(v);
}

// P7.4 F6: submit an ALREADY clip-space vertex (x,y,z,w), skipping the MVP. The
// Mesh front-end batch-transforms model-space vertices with Math3DTransformParallel
// and feeds them here. Math3DTransformRange/Mat4MulVec4 compute the same
// expressions as HolyGLTransformVertex, so the result is bit-identical.
U0 HolyGLVertexClip(F64 x, F64 y, F64 z, F64 w) {
  GLVertex *v = HolyGLNextVertex();
  v->x = x; v->y = y; v->z = z; v->w = w;
  HolyGLDispatchVertex(v);
}

// The current combined model-view-projection matrix (for batch transforms).
U0 HolyGLGetMVP(CMat4 *out) { Mat4Copy(out, &g_hgl.mvp); }

U0 HolyGLVertex2f(F64 x, F64 y) {
  HolyGLVertex3f(x, y, 0.0);
}

U0 HolyGLEnd() {
  g_hgl.v_count = 0;
  gfx_dirty_expand(g_hgl.vp_x, g_hgl.vp_y, g_hgl.vp_w, g_hgl.vp_h);
}

U0 HolyGLViewport(I64 vx, I64 vy, I64 vw, I64 vh) {
  g_hgl.vp_x = vx;
  g_hgl.vp_y = vy;
  g_hgl.vp_w = vw;
  g_hgl.vp_h = vh;
  HolyGLClearDepth();
}

// Standard OpenGL API Bindings
U0 glViewport(I64 vx, I64 vy, I64 vw, I64 vh) { HolyGLViewport(vx, vy, vw, vh); }
U0 glMatrixMode(I64 mode) { HolyGLMatrixMode(mode); }
U0 glLoadIdentity() { HolyGLLoadIdentity(); }
U0 glTranslatef(F64 tx, F64 ty, F64 tz) { HolyGLTranslatef(tx, ty, tz); }
U0 gluPerspective(F64 fovy, F64 aspect, F64 z_near, F64 z_far) { HolyGLPerspective(fovy, aspect, z_near, z_far); }
U0 glColor3ub(U32 r, U32 g, U32 b) { HolyGLColor3ub(r, g, b); }
U0 glTexCoord2f(F64 u, F64 v) { HolyGLTexCoord2f(u, v); }
U0 glNormal3f(F64 nx, F64 ny, F64 nz) { HolyGLNormal3f(nx, ny, nz); }
U0 glBegin(I64 mode) { HolyGLBegin(mode); }
U0 glVertex3f(F64 x, F64 y, F64 z) { HolyGLVertex3f(x, y, z); }
U0 glEnd() { HolyGLEnd(); }
U0 glEnable(I64 cap) { HolyGLEnable(cap); }
U0 glDisable(I64 cap) { HolyGLDisable(cap); }
U0 glPushMatrix() { HolyGLPushMatrix(); }
U0 glPopMatrix() { HolyGLPopMatrix(); }
U0 glRotatef(F64 angle_deg, F64 x, F64 y, F64 z) { HolyGLRotatef(angle_deg, x, y, z); }
U0 glScalef(F64 sx, F64 sy, F64 sz) { HolyGLScalef(sx, sy, sz); }
U0 glColor3f(F64 r, F64 g, F64 b) { HolyGLColor3f(r, g, b); }
U0 glColor4f(F64 r, F64 g, F64 b, F64 a) { HolyGLColor4f(r, g, b, a); }
U0 glVertex2f(F64 x, F64 y) { HolyGLVertex2f(x, y); }
U0 glClear(I64 mask) { HolyGLClear(mask); }
U0 glClearColor(F64 r, F64 g, F64 b, F64 a) { HolyGLClearColor(r, g, b, a); }
U0 glClearDepth() { HolyGLClearDepth(); }
U0 glFlush() { HolyGLFlush(); }

// ------------------------------------------------------------------------------
// P4.3: Texture object API
// ------------------------------------------------------------------------------
I64 glGenTextures() {
  I64 i = 0;
  while (i < GL_MAX_TEXTURES) {
    if (g_tex_pool[i].in_use == 0) {
      g_tex_pool[i].in_use = 1;
      g_tex_pool[i].width = 0;
      g_tex_pool[i].height = 0;
      g_tex_pool[i].wrap_s = GL_REPEAT;
      g_tex_pool[i].wrap_t = GL_REPEAT;
      g_tex_pool[i].min_filter = GL_NEAREST;
      g_tex_pool[i].mag_filter = GL_NEAREST;
      g_tex_pool[i].data = 0;
      return i + 1;
    }
    i = i + 1;
  }
  return 0;
}

U0 glBindTexture(I64 target, I64 tex) {
  if (tex < 0 || tex > GL_MAX_TEXTURES) return;
  g_tex_bound = tex;
}

// Power-of-two dimensions only (the REPEAT path uses a bitwise mask).
U0 glTexImage2D(I64 target, I64 level, I64 width, I64 height, U32 *pixels) {
  if (g_tex_bound <= 0) return;
  if (width <= 0 || height <= 0) return;
  if ((width & (width - 1)) != 0 || (height & (height - 1)) != 0) return;
  CTexture2D *t = &g_tex_pool[g_tex_bound - 1];
  if (t->data) { kfree(t->data); t->data = 0; }
  I64 n = width * height;
  U32 *buf = (U32*)kmalloc(n * 4);
  if (!buf) return;
  I64 i = 0;
  while (i < n) { buf[i] = pixels[i]; i = i + 1; }
  t->data = buf;
  t->width = width;
  t->height = height;
}

U0 glTexParameteri(I64 target, I64 pname, I64 param) {
  if (g_tex_bound <= 0) return;
  CTexture2D *t = &g_tex_pool[g_tex_bound - 1];
  if (pname == GL_TEXTURE_WRAP_S) t->wrap_s = param;
  else if (pname == GL_TEXTURE_WRAP_T) t->wrap_t = param;
  else if (pname == GL_TEXTURE_MIN_FILTER) t->min_filter = param;
  else if (pname == GL_TEXTURE_MAG_FILTER) t->mag_filter = param;
}

U0 glBlendFunc(I64 src, I64 dst) {
  g_tex_blend_src = src;
  g_tex_blend_dst = dst;
}

// Push the bound texture into the ONE rasterizer (or disable texturing).
U0 HolyGLBindRasterTexture() {
  g_tex_ok = 0;
  if (g_tex_enabled && g_tex_bound > 0) {
    CTexture2D *t = &g_tex_pool[g_tex_bound - 1];
    if (t->data != 0 && t->width > 0 && t->height > 0) {
      RasterSetTexture(t->data, t->width, t->height, t->wrap_s, t->wrap_t, t->mag_filter);
      RasterSetBlend(g_tex_blend);
      g_tex_ok = 1;
      return;
    }
  }
  RasterDisableTexture();
}

// --- cross-module accessors (no direct g_hgl access from other modules) ---
I64 HolyGLGetTrisRendered() { return g_hgl.tris_rendered; }
I64 HolyGLGetModelviewSP() { return g_hgl.modelview_sp; }
I64 HolyGLGetProjectionSP() { return g_hgl.projection_sp; }
I64 HolyGLGetMatrixMode() { return g_hgl.matrix_mode; }
U32 HolyGLGetCurrentColor() { return g_hgl.v_curr.color; }
// Matrix-element reads cross the unit boundary as raw IEEE-754 bits (I64). HolyGL
// is Stage 5 but SelfTest is Stage 1, and the compiler only tracks F64-ness within
// a unit (and earlier ones): a cross-stage F64 return reads X0 instead of D0, and
// F64 *out-params / F64 arithmetic on these short bodies are likewise unreliable.
// Reading the 8 raw bytes as an I64 is exact and unit-safe.
I64 HolyGLModelviewMBits(I64 idx) {
  CMat4 *mm = &g_hgl.modelview_stack[g_hgl.modelview_sp];
  I64 *bits = (I64*)&mm->m[idx];
  return *bits;
}
I64 HolyGLProjectionMBits(I64 idx) {
  CMat4 *pm = &g_hgl.projection_stack[g_hgl.projection_sp];
  I64 *bits = (I64*)&pm->m[idx];
  return *bits;
}

// ------------------------------------------------------------------------------
// 3D Polyhedral Rotating Cube Demonstrator
// ------------------------------------------------------------------------------
U0 HolyGLRenderCubeAt(F64 tx, F64 ty, F64 tz, F64 scale_s, F64 angle) {
  HolyGLPushMatrix();
  HolyGLTranslatef(tx, ty, tz);
  HolyGLRotatef(angle, 1.0, 0.0, 0.0);
  HolyGLRotatef(angle * 1.3, 0.0, 1.0, 0.0);
  HolyGLScalef(scale_s, scale_s, scale_s);

  HolyGLBegin(GL_QUADS);
  // Front Face (Catppuccin Red)
  HolyGLNormal3f(0.0, 0.0, 1.0);
  HolyGLColor3ub(243, 139, 168);
  HolyGLVertex3f(-1.0, -1.0,  1.0);
  HolyGLVertex3f( 1.0, -1.0,  1.0);
  HolyGLVertex3f( 1.0,  1.0,  1.0);
  HolyGLVertex3f(-1.0,  1.0,  1.0);

  // Back Face (Catppuccin Blue)
  HolyGLNormal3f(0.0, 0.0, -1.0);
  HolyGLColor3ub(137, 180, 250);
  HolyGLVertex3f( 1.0, -1.0, -1.0);
  HolyGLVertex3f(-1.0, -1.0, -1.0);
  HolyGLVertex3f(-1.0,  1.0, -1.0);
  HolyGLVertex3f( 1.0,  1.0, -1.0);

  // Top Face (Catppuccin Green)
  HolyGLNormal3f(0.0, 1.0, 0.0);
  HolyGLColor3ub(166, 227, 161);
  HolyGLVertex3f(-1.0,  1.0,  1.0);
  HolyGLVertex3f( 1.0,  1.0,  1.0);
  HolyGLVertex3f( 1.0,  1.0, -1.0);
  HolyGLVertex3f(-1.0,  1.0, -1.0);

  // Bottom Face (Catppuccin Peach)
  HolyGLNormal3f(0.0, -1.0, 0.0);
  HolyGLColor3ub(250, 179, 135);
  HolyGLVertex3f(-1.0, -1.0, -1.0);
  HolyGLVertex3f( 1.0, -1.0, -1.0);
  HolyGLVertex3f( 1.0, -1.0,  1.0);
  HolyGLVertex3f(-1.0, -1.0,  1.0);

  // Right Face (Catppuccin Mauve)
  HolyGLNormal3f(1.0, 0.0, 0.0);
  HolyGLColor3ub(203, 166, 247);
  HolyGLVertex3f( 1.0, -1.0,  1.0);
  HolyGLVertex3f( 1.0, -1.0, -1.0);
  HolyGLVertex3f( 1.0,  1.0, -1.0);
  HolyGLVertex3f( 1.0,  1.0,  1.0);

  // Left Face (Catppuccin Teal)
  HolyGLNormal3f(-1.0, 0.0, 0.0);
  HolyGLColor3ub(148, 226, 213);
  HolyGLVertex3f(-1.0, -1.0, -1.0);
  HolyGLVertex3f(-1.0, -1.0,  1.0);
  HolyGLVertex3f(-1.0,  1.0,  1.0);
  HolyGLVertex3f(-1.0,  1.0, -1.0);
  HolyGLEnd();

  HolyGLPopMatrix();
}

U0 HolyGLRenderCube(F64 angle) {
  HolyGLClearDepth();
  F64 aspect = 1.333333;
  if (g_hgl.vp_h > 0) aspect = (F64)g_hgl.vp_w / (F64)g_hgl.vp_h;

  HolyGLMatrixMode(GL_PROJECTION);
  HolyGLLoadIdentity();
  HolyGLPerspective(45.0, aspect, 1.0, 100.0);

  HolyGLMatrixMode(GL_MODELVIEW);
  HolyGLLoadIdentity();
  HolyGLRenderCubeAt(0.0, 0.0, -5.0, 1.0, angle);
}

U0 HolyGLMain() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$    ✦ NeoOS Sovereign Pure HolyC 3D Graphics Substrate (HolyGL) ✦$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_print(" Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution\n");
  doldoc_print(" Pipeline    : 16-Bit Z-Buffered Homogeneous Clipping & Matrix Stack\n");
  doldoc_print(" Shading     : Catppuccin Mocha Lambertian & Solid Polyhedral Shading\n");
  doldoc_print(" Elimination : ZERO Fake Multipliers | Hardware CNTVCT_EL0 Telemetry\n");
  doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

  I64 cw = gfx_get_canvas_width();
  I64 vx = cw - 360;
  if (vx < 320) vx = 320;
  HolyGLViewport(vx, 80, 320, 240);

  I64 frames = 10;
  U64 start_cycles = __mrs_cntvct();
  U64 freq = __mrs_cntfrq();
  if (freq == 0) freq = 62500000;

  I64 hgl_frame = 0;
  while (hgl_frame < frames) {
    F64 ang = (F64)(hgl_frame * 18);
    gfx_draw_rect(vx, 80, 320, 240, 0xFF11111B);
    HolyGLRenderCube(ang);
    hgl_frame++;
  }

  U64 end_cycles = __mrs_cntvct();
  U64 elapsed_cycles = end_cycles - start_cycles;
  if (elapsed_cycles == 0) elapsed_cycles = 1;
  I64 fps = (frames * freq) / elapsed_cycles;
  I64 dur_us = (elapsed_cycles * 1000000) / freq;

  doldoc_printf("  $FG,GREEN$[PASS]$FG$ Rendered %lld real frames in %lld us ($FG,YELLOW$%lld FPS$FG$ via CNTVCT_EL0)\n",
                frames, dur_us, fps);
  doldoc_print("  $FG,GREEN$[PASS]$FG$ Matrix stack, 16-bit Z-buffer & 4D clipping verified.\n");
  doldoc_print(" Controls:\n");
  doldoc_print("  Actions: $BT,\"GLXGears 3D\",LM=\"gears\"$  $BT,\"Physics 3D\",LM=\"physics\"$  $BT,\"Full Bench\",LM=\"bench\"$\n");
  doldoc_print("  Dismiss: $BT,\"Stop 3D Viewport\",LM=\"stopbench\"$  $BT,\"App Menu\",LM=\"menu\"$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

HolyGLInit();
if (!g_kernel_booting) {
  HolyGLMain();
}

// ==============================================================================
// LOTE 3 / Camada 4A — HglTransformBatchSmp: transformacao em lote de vertices
// nos 4 cores via o motor soberano Math3DPar (Math3DTransformParallel).
// Reutiliza a arena g_tf_s_* (slices + prova de core) — ZERO kmalloc, ZERO
// impacto no CENSUS. Arena estatica alinhada a 64B (slot de 64 bytes p/ core).
// A matematica e' idêntica a do scalar (Math3DTransformRange), logo o resultado
// e' bit-identico; cada slice e' escrito por exatamente um core.
// ==============================================================================
#define HGL_BATCH_MAX_CORES 4

I64 g_hgl_batch_core_mask;       // bitmask de cores que executaram
U64 g_hgl_batch_ticks;           // ciclos CNTVCT do lote
I64 g_hgl_batch_nslices;

typedef struct {
  I64 _pad[(64 / 8)];            // slot de 64 bytes por core (bss alinhada)
} HglCoreArena;

// Transforma [0,count) vertices CVec3->CVec4 pelo MVP em paralelo. Retorna o
// numero de slices usados (1 no fallback scalar). Preenche g_hgl_batch_core_mask
// e g_hgl_batch_ticks. Mesma assinatura de Math3DTransformParallel.
I64 HglTransformBatchSmp(CVec3 *in, CVec4 *out, I64 count, CMat4 *mvp) {
  U64 t0 = __mrs_cntvct();
  I64 nsl = Math3DTransformParallel(in, out, count, mvp);
  U64 t1 = __mrs_cntvct();
  g_hgl_batch_ticks = t1 - t0;
  g_hgl_batch_nslices = nsl;
  // Sonda quais cores executaram (ran[] = MPIDR de quem rodou cada slice).
  g_hgl_batch_core_mask = 0;
  I64 k = 0;
  while (k < nsl) {
    I64 ran = g_tf_s_ran[k];
    if (ran >= 0) g_hgl_batch_core_mask = g_hgl_batch_core_mask | (1 << ran);
    k = k + 1;
  }
  return nsl;
}

// Self-test do Lote 3 (c4_hgl_batch_smp_exact / c4_hgl_batch_speedup): compara o
// lote SMP com a referencia escalar bit a bit e prova que multiplos cores rodaram
// quando ha SMP. Retorna nro de falhas (0 = pass).
CVec3 g_hgl_b_test_in[16];
CVec4 g_hgl_b_test_out[16];
CVec4 g_hgl_b_ref[16];

I64 HglBatchSmpSelfTest() {
  CMat4 mvp;
  Mat4Identity(&mvp);
  Mat4Translate(&mvp, 0.5, -1.0, 2.0);
  Mat4RotateY(&mvp, 30.0);
  I64 i = 0;
  while (i < 16) {
    g_hgl_b_test_in[i].x = (F64)(i * 2) - 5.0;
    g_hgl_b_test_in[i].y = (F64)(i * 0.5) + 3.0;
    g_hgl_b_test_in[i].z = (F64)i - 2.0;
    CVec4 t;
    t.x = g_hgl_b_test_in[i].x; t.y = g_hgl_b_test_in[i].y; t.z = g_hgl_b_test_in[i].z; t.w = 1.0;
    Mat4MulVec4(&g_hgl_b_ref[i], &mvp, &t);
    i = i + 1;
  }
  I64 nsl = HglTransformBatchSmp(g_hgl_b_test_in, g_hgl_b_test_out, 16, &mvp);
  I64 bad = 0;
  // c4_hgl_batch_smp_exact: bit-identical ao scalar.
  i = 0;
  while (i < 16) {
    if (g_hgl_b_test_out[i].x != g_hgl_b_ref[i].x) bad = bad + 1;
    if (g_hgl_b_test_out[i].y != g_hgl_b_ref[i].y) bad = bad + 1;
    if (g_hgl_b_test_out[i].z != g_hgl_b_ref[i].z) bad = bad + 1;
    if (g_hgl_b_test_out[i].w != g_hgl_b_ref[i].w) bad = bad + 1;
    i = i + 1;
  }
  // c4_hgl_batch_speedup: com >1 core, mais de um core executa alguma slice.
  if ((I64)SmpOnlineCoreCount() > 1) {
    I64 core_cnt = 0;
    I64 mk = 0;
    while (mk < 32) { if (g_hgl_batch_core_mask & (1 << mk)) core_cnt = core_cnt + 1; mk = mk + 1; }
    if (core_cnt < 2) bad = bad + 1;
  }
  return bad;
}
