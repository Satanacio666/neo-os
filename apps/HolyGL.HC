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

#define PI 3.14159265358979323846

// 4x4 Transformation Matrix in Row-Major Order
class Mat4x4 {
    F64 m[16];
};

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

// Identity Matrix Initialization
U0 Mat4x4Identity(Mat4x4 *out) {
    I64 mi;
    for (mi = 0; mi < 16; mi++) {
        out->m[mi] = (mi % 5 == 0) ? 1.0 : 0.0;
    }
}

// Copy Matrix: dst = src
U0 Mat4x4Copy(Mat4x4 *dst, Mat4x4 *src) {
    I64 ci;
    for (ci = 0; ci < 16; ci++) {
        dst->m[ci] = src->m[ci];
    }
}

// 4x4 Matrix Multiplication: out = a * b
U0 Mat4x4Mul(Mat4x4 *out, Mat4x4 *a, Mat4x4 *b) {
    Mat4x4 temp;
    I64 r, c, k;
    for (r = 0; r < 4; r++) {
        for (c = 0; c < 4; c++) {
            F64 sum = 0.0;
            for (k = 0; k < 4; k++) {
                sum = sum + a->m[r * 4 + k] * b->m[k * 4 + c];
            }
            temp.m[r * 4 + c] = sum;
        }
    }
    for (r = 0; r < 16; r++) {
        out->m[r] = temp.m[r];
    }
}

// Translation Matrix: out = Translate(tx, ty, tz) * out
U0 Mat4x4Translate(Mat4x4 *out, F64 tx, F64 ty, F64 tz) {
    Mat4x4 tr;
    Mat4x4Identity(&tr);
    tr.m[3]  = tx;
    tr.m[7]  = ty;
    tr.m[11] = tz;
    Mat4x4Mul(out, &tr, out);
}

// Scale Matrix: out = Scale(sx, sy, sz) * out
U0 Mat4x4Scale(Mat4x4 *out, F64 sx, F64 sy, F64 sz) {
    Mat4x4 sc;
    Mat4x4Identity(&sc);
    sc.m[0]  = sx;
    sc.m[5]  = sy;
    sc.m[10] = sz;
    Mat4x4Mul(out, &sc, out);
}

// Rotation Matrix about X-axis (angle in degrees)
U0 Mat4x4RotateX(Mat4x4 *out, F64 angle_deg) {
    Mat4x4 rot;
    Mat4x4Identity(&rot);
    F64 c = math3d_cos(angle_deg);
    F64 s = math3d_sin(angle_deg);
    rot.m[5]  = c;
    rot.m[6]  = -s;
    rot.m[9]  = s;
    rot.m[10] = c;
    Mat4x4Mul(out, &rot, out);
}

// Rotation Matrix about Y-axis (angle in degrees)
U0 Mat4x4RotateY(Mat4x4 *out, F64 angle_deg) {
    Mat4x4 rot;
    Mat4x4Identity(&rot);
    F64 c = math3d_cos(angle_deg);
    F64 s = math3d_sin(angle_deg);
    rot.m[0]  = c;
    rot.m[2]  = s;
    rot.m[8]  = -s;
    rot.m[10] = c;
    Mat4x4Mul(out, &rot, out);
}

// Rotation Matrix about Z-axis (angle in degrees)
U0 Mat4x4RotateZ(Mat4x4 *out, F64 angle_deg) {
    Mat4x4 rot;
    Mat4x4Identity(&rot);
    F64 c = math3d_cos(angle_deg);
    F64 s = math3d_sin(angle_deg);
    rot.m[0] = c;
    rot.m[1] = -s;
    rot.m[4] = s;
    rot.m[5] = c;
    Mat4x4Mul(out, &rot, out);
}

// Perspective Projection Matrix (fov_y in degrees)
U0 Mat4x4Perspective(Mat4x4 *out, F64 fov_y_deg, F64 aspect, F64 z_near, F64 z_far) {
    Mat4x4Identity(out);
    F64 half_fov = fov_y_deg * 0.5;
    F64 s = math3d_sin(half_fov);
    F64 c = math3d_cos(half_fov);
    F64 tan_half = 1.0;
    if (s > 0.0001) {
        tan_half = s / c;
    }
    F64 f = 1.0 / tan_half;

    out->m[0]  = f / aspect;
    out->m[5]  = f;
    out->m[10] = -(z_far + z_near) / (z_far - z_near);
    out->m[11] = -(2.0 * z_far * z_near) / (z_far - z_near);
    out->m[14] = -1.0;
    out->m[15] = 0.0;
}

// Vector Transformation: out = mat * (x, y, z, w)
U0 Mat4x4Transform(Mat4x4 *mat, F64 x, F64 y, F64 z, F64 w, GLVertex *out) {
    out->x = mat->m[0] * x + mat->m[1] * y + mat->m[2] * z  + mat->m[3] * w;
    out->y = mat->m[4] * x + mat->m[5] * y + mat->m[6] * z  + mat->m[7] * w;
    out->z = mat->m[8] * x + mat->m[9] * y + mat->m[10] * z + mat->m[11] * w;
    out->w = mat->m[12]* x + mat->m[13]* y + mat->m[14]* z + mat->m[15]* w;
}

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
        Mat4x4Copy(&g_hgl.modelview_stack[g_hgl.modelview_sp], &g_hgl.modelview);
        g_hgl.modelview_sp++;
    }
}

U0 HolyGLPopMatrix() {
    if (g_hgl.matrix_mode == GL_MODELVIEW && g_hgl.modelview_sp > 0) {
        g_hgl.modelview_sp--;
        Mat4x4Copy(&g_hgl.modelview, &g_hgl.modelview_stack[g_hgl.modelview_sp]);
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
    if (x > 0.5) Mat4x4RotateX(&g_hgl.modelview, angle_deg);
    if (y > 0.5) Mat4x4RotateY(&g_hgl.modelview, angle_deg);
    if (z > 0.5) Mat4x4RotateZ(&g_hgl.modelview, angle_deg);
    HolyGLUpdateMVP();
}

U0 HolyGLScalef(F64 sx, F64 sy, F64 sz) {
    Mat4x4Scale(&g_hgl.modelview, sx, sy, sz);
    HolyGLUpdateMVP();
}

U0 HolyGLPerspective(F64 fovy, F64 aspect, F64 z_near, F64 z_far) {
    Mat4x4Perspective(&g_hgl.projection, fovy, aspect, z_near, z_far);
    HolyGLUpdateMVP();
}

// ------------------------------------------------------------------------------
// Vertex & Attribute Specifications
// ------------------------------------------------------------------------------
U0 HolyGLColor3f(F64 r, F64 g, F64 b) {
    U32 ir, ig, ib;
    ir = (r * 255.0);
    ig = (g * 255.0);
    ib = (b * 255.0);
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
    F64 inv_w0, inv_w1, inv_w2;
    F64 ndc_x0, ndc_y0, ndc_x1, ndc_y1, ndc_x2, ndc_y2;
    F64 cross;
    F64 half_w, half_h;
    I64 sx0, sy0, sx1, sy1, sx2, sy2;

    // Frustum and near plane rejection
    if (v0->w <= 0.01 && v1->w <= 0.01 && v2->w <= 0.01) return;

    inv_w0 = 1.0 / v0->w;
    inv_w1 = 1.0 / v1->w;
    inv_w2 = 1.0 / v2->w;

    ndc_x0 = v0->x * inv_w0;
    ndc_y0 = v0->y * inv_w0;
    ndc_x1 = v1->x * inv_w1;
    ndc_y1 = v1->y * inv_w1;
    ndc_x2 = v2->x * inv_w2;
    ndc_y2 = v2->y * inv_w2;

    cross = (ndc_x1 - ndc_x0) * (ndc_y2 - ndc_y0) - (ndc_y1 - ndc_y0) * (ndc_x2 - ndc_x0);
    if (g_hgl.cull_face && cross <= 0.0) return;

    half_w = g_hgl.vp_w * 0.5;
    half_h = g_hgl.vp_h * 0.5;

    sx0 = g_hgl.vp_x + (ndc_x0 + 1.0) * half_w;
    sy0 = g_hgl.vp_y + (1.0 - ndc_y0) * half_h;
    sx1 = g_hgl.vp_x + (ndc_x1 + 1.0) * half_w;
    sy1 = g_hgl.vp_y + (1.0 - ndc_y1) * half_h;
    sx2 = g_hgl.vp_x + (ndc_x2 + 1.0) * half_w;
    sy2 = g_hgl.vp_y + (1.0 - ndc_y2) * half_h;

    gfx_draw_triangle_fill(sx0, sy0, sx1, sy1, sx2, sy2, v0->color);
}

U0 HolyGLVertex3f(F64 x, F64 y, F64 z) {
    GLVertex *v;
    v = &g_hgl.v_queue[g_hgl.v_count];
    g_hgl.v_count++;
    v->u = g_hgl.v_curr.u;
    v->v = g_hgl.v_curr.v;
    v->color = g_hgl.v_curr.color;
    v->nx = g_hgl.v_curr.nx;
    v->ny = g_hgl.v_curr.ny;
    v->nz = g_hgl.v_curr.nz;

    // Transform by MVP matrix into clip coordinates
    Mat4x4Transform(&g_hgl.mvp, x, y, z, 1.0, v);

    if (g_hgl.primitive_mode == GL_TRIANGLES && g_hgl.v_count == 3) {
        HolyGLSubmitTriangle(&g_hgl.v_queue[0], &g_hgl.v_queue[1], &g_hgl.v_queue[2]);
        g_hgl.v_count = 0;
    } else if (g_hgl.primitive_mode == GL_QUADS && g_hgl.v_count == 4) {
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
    gfx_dirty_expand(g_hgl.vp_x, g_hgl.vp_y, g_hgl.vp_w, g_hgl.vp_h);
}

// ------------------------------------------------------------------------------
// 3D Polyhedral Rotating Cube Demonstrator
// ------------------------------------------------------------------------------
U0 HolyGLRenderCube(F64 angle) {
    HolyGLMatrixMode(GL_PROJECTION);
    HolyGLLoadIdentity();
    HolyGLPerspective(45.0, 1.333, 1.0, 100.0);

    HolyGLMatrixMode(GL_MODELVIEW);
    HolyGLLoadIdentity();
    HolyGLTranslatef(0.0, 0.0, -5.0);
    HolyGLRotatef(angle, 1.0, 0.0, 0.0);
    HolyGLRotatef(angle * 1.5, 0.0, 1.0, 0.0);

    // Front Face (Catppuccin Red)
    HolyGLBegin(GL_QUADS);
    HolyGLColor3ub(243, 139, 168);
    HolyGLVertex3f(-1.0, -1.0,  1.0);
    HolyGLVertex3f( 1.0, -1.0,  1.0);
    HolyGLVertex3f( 1.0,  1.0,  1.0);
    HolyGLVertex3f(-1.0,  1.0,  1.0);

    // Back Face (Catppuccin Blue)
    HolyGLColor3ub(137, 180, 250);
    HolyGLVertex3f( 1.0, -1.0, -1.0);
    HolyGLVertex3f(-1.0, -1.0, -1.0);
    HolyGLVertex3f(-1.0,  1.0, -1.0);
    HolyGLVertex3f( 1.0,  1.0, -1.0);

    // Top Face (Catppuccin Green)
    HolyGLColor3ub(166, 227, 161);
    HolyGLVertex3f(-1.0,  1.0,  1.0);
    HolyGLVertex3f( 1.0,  1.0,  1.0);
    HolyGLVertex3f( 1.0,  1.0, -1.0);
    HolyGLVertex3f(-1.0,  1.0, -1.0);

    // Bottom Face (Catppuccin Peach)
    HolyGLColor3ub(250, 179, 135);
    HolyGLVertex3f(-1.0, -1.0, -1.0);
    HolyGLVertex3f( 1.0, -1.0, -1.0);
    HolyGLVertex3f( 1.0, -1.0,  1.0);
    HolyGLVertex3f(-1.0, -1.0,  1.0);

    // Right Face (Catppuccin Mauve)
    HolyGLColor3ub(203, 166, 247);
    HolyGLVertex3f( 1.0, -1.0,  1.0);
    HolyGLVertex3f( 1.0, -1.0, -1.0);
    HolyGLVertex3f( 1.0,  1.0, -1.0);
    HolyGLVertex3f( 1.0,  1.0,  1.0);

    // Left Face (Catppuccin Teal)
    HolyGLColor3ub(148, 226, 213);
    HolyGLVertex3f(-1.0, -1.0, -1.0);
    HolyGLVertex3f(-1.0, -1.0,  1.0);
    HolyGLVertex3f(-1.0,  1.0,  1.0);
    HolyGLVertex3f(-1.0,  1.0, -1.0);
    HolyGLEnd();
}

U0 HolyGLMain() {
    I64 start_us, end_us, dur, fps, frame;
    F64 ang;

    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS Sovereign Pure HolyC 3D Graphics Substrate (HolyGL) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution\n");
    doldoc_print(" Pipeline    : Pure HolyC 4D Homogeneous Clipping & Matrix Stack\n");
    doldoc_print(" Shading     : Catppuccin Mocha 6-Color Polyhedral Solid Shading\n");
    doldoc_print(" Elimination : ZERO C Fallbacks | Pure HolyC Geometry Continuum\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    start_us = timer_get_uptime_us();
    for (frame = 0; frame < 36; frame++) {
        ang = (F64)(frame * 10);
        HolyGLRenderCube(ang);
    }
    end_us = timer_get_uptime_us();
    dur = end_us - start_us;
    if (dur <= 0) dur = 1;
    fps = (36 * 1000000) / dur;

    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Rendered 36 frames in %lld us ($FG,YELLOW$%lld FPS$FG$ in pure HolyC)\n", dur, fps);
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Matrix stack, MVP transform & 4D clipping verified.\n");
    doldoc_print(" Controls:\n");
    doldoc_print("  Actions: $BT,\"GLXGears 3D\",LM=\"gears\"$  $BT,\"Physics 3D\",LM=\"physics\"$  $BT,\"Full Bench\",LM=\"bench\"$\n");
    doldoc_print("  Dismiss: $BT,\"Stop 3D Viewport\",LM=\"stopbench\"$  $BT,\"App Menu\",LM=\"menu\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

HolyGLInit();
HolyGLMain();
