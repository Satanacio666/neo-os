// ==============================================================================
// HolyGL.HC - Pure HolyC 3D Graphics Substrate & OpenGL State Machine
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Mathematical Core: Homogeneous 4D Frustum Clipping & Barycentric Rasterizer
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

class GLVertex {
    F64 x, y, z, w;
    F64 u, v;
    U32 color;
    F64 nx, ny, nz;
};

class HolyGLContext {
    Mat4x4 modelview;
    Mat4x4 projection;
    Mat4x4 mvp;
    Mat4x4 modelview_stack[8];
    I64    modelview_sp;
    
    I64    matrix_mode;
    I64    primitive_mode;
    I64    depth_test;
    I64    cull_face;
    
    GLVertex v_curr;
    GLVertex v_queue[16];
    I64      v_count;
    
    I64 vp_x, vp_y, vp_w, vp_h;
};

HolyGLContext g_hgl;

U0 HolyGLInit() {
    Mat4x4Identity(&g_hgl.modelview);
    Mat4x4Identity(&g_hgl.projection);
    Mat4x4Identity(&g_hgl.mvp);
    g_hgl.modelview_sp = 0;
    g_hgl.matrix_mode = GL_MODELVIEW;
    g_hgl.primitive_mode = 0;
    g_hgl.depth_test = 1;
    g_hgl.cull_face = 1;
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
}

U0 HolyGLUpdateMVP() {
    Mat4x4Mul(&g_hgl.mvp, &g_hgl.projection, &g_hgl.modelview);
}

// ------------------------------------------------------------------------------
// Matrix Stack Operations
// ------------------------------------------------------------------------------
U0 HolyGLMatrixMode(I64 mode) {
    g_hgl.matrix_mode = mode;
}

U0 HolyGLLoadIdentity() {
    if (g_hgl.matrix_mode == GL_MODELVIEW) {
        Mat4x4Identity(&g_hgl.modelview);
    } else {
        Mat4x4Identity(&g_hgl.projection);
    }
    HolyGLUpdateMVP();
}

U0 HolyGLPushMatrix() {
    if (g_hgl.matrix_mode == GL_MODELVIEW && g_hgl.modelview_sp < 7) {
        I64 i;
        for (i = 0; i < 16; i++) {
            g_hgl.modelview_stack[g_hgl.modelview_sp].m[i] = g_hgl.modelview.m[i];
        }
        g_hgl.modelview_sp++;
    }
}

U0 HolyGLPopMatrix() {
    if (g_hgl.matrix_mode == GL_MODELVIEW && g_hgl.modelview_sp > 0) {
        g_hgl.modelview_sp--;
        I64 i;
        for (i = 0; i < 16; i++) {
            g_hgl.modelview.m[i] = g_hgl.modelview_stack[g_hgl.modelview_sp].m[i];
        }
        HolyGLUpdateMVP();
    }
}

U0 HolyGLTranslatef(F64 tx, F64 ty, F64 tz) {
    if (g_hgl.matrix_mode == GL_MODELVIEW) {
        Mat4x4Translate(&g_hgl.modelview, tx, ty, tz);
    } else {
        Mat4x4Translate(&g_hgl.projection, tx, ty, tz);
    }
    HolyGLUpdateMVP();
}

U0 HolyGLRotatef(F64 angle_deg, F64 x, F64 y, F64 z) {
    F64 rad = angle_deg * (PI / 180.0);
    if (x > 0.5) Mat4x4RotateX(&g_hgl.modelview, rad);
    if (y > 0.5) Mat4x4RotateY(&g_hgl.modelview, rad);
    if (z > 0.5) Mat4x4RotateZ(&g_hgl.modelview, rad);
    HolyGLUpdateMVP();
}

U0 HolyGLScalef(F64 sx, F64 sy, F64 sz) {
    Mat4x4Scale(&g_hgl.modelview, sx, sy, sz);
    HolyGLUpdateMVP();
}

U0 HolyGLPerspective(F64 fovy, F64 aspect, F64 z_near, F64 z_far) {
    Mat4x4Perspective(&g_hgl.projection, fovy * (PI / 180.0), aspect, z_near, z_far);
    HolyGLUpdateMVP();
}

// ------------------------------------------------------------------------------
// Vertex & Attribute Specifications
// ------------------------------------------------------------------------------
U0 HolyGLColor3f(F64 r, F64 g, F64 b) {
    U32 ir = (r * 255.0);
    U32 ig = (g * 255.0);
    U32 ib = (b * 255.0);
    g_hgl.v_curr.color = 0xFF000000 | (ir << 16) | (ig << 8) | ib;
}

U0 HolyGLColor3ub(U32 r, U32 g, U32 b) {
    g_hgl.v_curr.color = 0xFF000000 | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
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

// Dispatches a transformed screen-space triangle to the L1-tile SIMD rasterizer
U0 HolyGLSubmitTriangle(GLVertex *v0, GLVertex *v1, GLVertex *v2) {
    // Frustum and near plane rejection
    if (v0->w <= 0.01 && v1->w <= 0.01 && v2->w <= 0.01) return;

    // Perspective Division to Normalized Device Coordinates [-1, 1]
    F64 inv_w0 = 1.0 / v0->w;
    F64 inv_w1 = 1.0 / v1->w;
    F64 inv_w2 = 1.0 / v2->w;

    F64 ndc_x0 = v0->x * inv_w0;
    F64 ndc_y0 = v0->y * inv_w0;
    F64 ndc_x1 = v1->x * inv_w1;
    F64 ndc_y1 = v1->y * inv_w1;
    F64 ndc_x2 = v2->x * inv_w2;
    F64 ndc_y2 = v2->y * inv_w2;

    // Backface Culling in Screen Space
    F64 cross = (ndc_x1 - ndc_x0) * (ndc_y2 - ndc_y0) - (ndc_y1 - ndc_y0) * (ndc_x2 - ndc_x0);
    if (g_hgl.cull_face && cross <= 0.0) return;

    // Viewport Mapping: NDC [-1, 1] -> Viewport Pixel Coordinates
    F64 half_w = g_hgl.vp_w * 0.5;
    F64 half_h = g_hgl.vp_h * 0.5;

    I64 sx0 = g_hgl.vp_x + (ndc_x0 + 1.0) * half_w;
    I64 sy0 = g_hgl.vp_y + (1.0 - ndc_y0) * half_h;
    I64 sx1 = g_hgl.vp_x + (ndc_x1 + 1.0) * half_w;
    I64 sy1 = g_hgl.vp_y + (1.0 - ndc_y1) * half_h;
    I64 sx2 = g_hgl.vp_x + (ndc_x2 + 1.0) * half_w;
    I64 sy2 = g_hgl.vp_y + (1.0 - ndc_y2) * half_h;

    // Submit to Tier 0 SIMD Rasterizer
    gfx_draw_triangle_fill(sx0, sy0, sx1, sy1, sx2, sy2, v0->color);
}

U0 HolyGLVertex3f(F64 x, F64 y, F64 z) {
    GLVertex *v = &g_hgl.v_queue[g_hgl.v_count++];
    v->u = g_hgl.v_curr.u;
    v->v = g_hgl.v_curr.v;
    v->color = g_hgl.v_curr.color;
    v->nx = g_hgl.v_curr.nx;
    v->ny = g_hgl.v_curr.ny;
    v->nz = g_hgl.v_curr.nz;

    // Transform by MVP matrix into clip coordinates
    Mat4x4Transform(&g_hgl.mvp, x, y, z, 1.0, &v->x, &v->y, &v->z, &v->w);

    if (g_hgl.primitive_mode == GL_TRIANGLES && g_hgl.v_count == 3) {
        HolyGLSubmitTriangle(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
        g_hgl.v_count = 0;
    } else if (g_hgl.primitive_mode == GL_QUADS && g_hgl.v_count == 4) {
        // Quad decomposed into two triangles
        HolyGLSubmitTriangle(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
        HolyGLSubmitTriangle(&g_hgl.v_queue[0], &g_hgl.v_queue[2], &g_hgl.v_queue[3]);
        g_hgl.v_count = 0;
    }
}

U0 HolyGLVertex2f(F64 x, F64 y) {
    HolyGLVertex3f(x, y, 0.0);
}

U0 HolyGLEnd() {
    g_hgl.v_count = 0;
}

HolyGLInit();
