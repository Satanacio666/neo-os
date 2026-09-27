#include "holygl.h"
#include "raster_tile.h"
#include "../../drivers/gpu/gfx_backend.h"
#include "../../gui/render.h"
#include <uefi.h>

holygl_context_t g_holygl = {0};

void holygl_init(void) {
    memset(&g_holygl, 0, sizeof(g_holygl));
    g_holygl.matrix_mode = GL_MODELVIEW;
    mat4_identity(&g_holygl.modelview_stack[0]);
    g_holygl.modelview_depth = 0;
    mat4_identity(&g_holygl.projection_stack[0]);
    g_holygl.projection_depth = 0;
    mat4_identity(&g_holygl.mvp);
    g_holygl.mvp_dirty = 1;

    g_holygl.depth_test = 1;
    g_holygl.cull_face = 1;
    g_holygl.lighting = 0;

    g_holygl.current_color = 0xFFFFFFFF;
    g_holygl.current_normal = (vec3_t){0.0f, 0.0f, 1.0f};
    g_holygl.current_uv = (vec2_t){0.0f, 0.0f};

    g_holygl.in_begin = 0;
    g_holygl.vertex_count = 0;

    g_holygl.vp_x = 0;
    g_holygl.vp_y = 0;
    g_holygl.vp_w = gfx_get_canvas_width() ? gfx_get_canvas_width() : 1280;
    g_holygl.vp_h = gfx_get_canvas_height() ? gfx_get_canvas_height() : 720;
    g_holygl.zbuffer = NULL;
    g_holygl.target_buffer = NULL;
    g_holygl.pitch = gfx_get_canvas_pitch() ? gfx_get_canvas_pitch() : 1280;
}

void holygl_set_target(int x, int y, int w, int h, zbuffer_t *zb, uint32_t *target, uint32_t pitch) {
    g_holygl.vp_x = x;
    g_holygl.vp_y = y;
    g_holygl.vp_w = w;
    g_holygl.vp_h = h;
    g_holygl.zbuffer = zb;
    g_holygl.target_buffer = target;
    g_holygl.pitch = pitch;
}

void glViewport(int x, int y, int width, int height) {
    g_holygl.vp_x = x;
    g_holygl.vp_y = y;
    g_holygl.vp_w = width;
    g_holygl.vp_h = height;
}

void glMatrixMode(uint32_t mode) {
    g_holygl.matrix_mode = mode;
}

static mat4_t* holygl_current_matrix(void) {
    if (g_holygl.matrix_mode == GL_PROJECTION) {
        return &g_holygl.projection_stack[g_holygl.projection_depth];
    }
    return &g_holygl.modelview_stack[g_holygl.modelview_depth];
}

void glLoadIdentity(void) {
    mat4_t *m = holygl_current_matrix();
    mat4_identity(m);
    g_holygl.mvp_dirty = 1;
}

void glPushMatrix(void) {
    if (g_holygl.matrix_mode == GL_PROJECTION) {
        if (g_holygl.projection_depth < HOLYGL_PROJECTION_STACK_DEPTH - 1) {
            g_holygl.projection_stack[g_holygl.projection_depth + 1] = g_holygl.projection_stack[g_holygl.projection_depth];
            g_holygl.projection_depth++;
        }
    } else {
        if (g_holygl.modelview_depth < HOLYGL_MODELVIEW_STACK_DEPTH - 1) {
            g_holygl.modelview_stack[g_holygl.modelview_depth + 1] = g_holygl.modelview_stack[g_holygl.modelview_depth];
            g_holygl.modelview_depth++;
        }
    }
    g_holygl.mvp_dirty = 1;
}

void glPopMatrix(void) {
    if (g_holygl.matrix_mode == GL_PROJECTION) {
        if (g_holygl.projection_depth > 0) {
            g_holygl.projection_depth--;
        }
    } else {
        if (g_holygl.modelview_depth > 0) {
            g_holygl.modelview_depth--;
        }
    }
    g_holygl.mvp_dirty = 1;
}

void glTranslatef(float x, float y, float z) {
    mat4_t *curr = holygl_current_matrix();
    mat4_t trans, res;
    mat4_translate(&trans, x, y, z);
    mat4_mul(&res, curr, &trans);
    *curr = res;
    g_holygl.mvp_dirty = 1;
}

void glRotatef(float angle, float x, float y, float z) {
    mat4_t *curr = holygl_current_matrix();
    mat4_t rot, res;
    mat4_identity(&rot);
    if (x != 0.0f) mat4_rotate_x(&rot, angle * x);
    if (y != 0.0f) mat4_rotate_y(&rot, angle * y);
    if (z != 0.0f) mat4_rotate_z(&rot, angle * z);
    mat4_mul(&res, curr, &rot);
    *curr = res;
    g_holygl.mvp_dirty = 1;
}

void glScalef(float x, float y, float z) {
    mat4_t *curr = holygl_current_matrix();
    mat4_t scale, res;
    mat4_scale(&scale, x, y, z);
    mat4_mul(&res, curr, &scale);
    *curr = res;
    g_holygl.mvp_dirty = 1;
}

void gluPerspective(float fovy, float aspect, float zNear, float zFar) {
    mat4_t *curr = holygl_current_matrix();
    mat4_t persp, res;
    mat4_perspective(&persp, fovy, aspect, zNear, zFar);
    mat4_mul(&res, curr, &persp);
    *curr = res;
    g_holygl.mvp_dirty = 1;
}

static void holygl_update_mvp(void) {
    if (g_holygl.mvp_dirty) {
        mat4_mul(&g_holygl.mvp,
                 &g_holygl.projection_stack[g_holygl.projection_depth],
                 &g_holygl.modelview_stack[g_holygl.modelview_depth]);
        g_holygl.mvp_dirty = 0;
    }
}

void glClear(uint32_t mask) {
    if (!g_holygl.target_buffer) {
        g_holygl.target_buffer = gfx_get_backbuffer();
        g_holygl.pitch = gfx_get_canvas_pitch();
    }
    if (mask & GL_COLOR_BUFFER_BIT) {
        raster_tile_begin_scene(g_holygl.vp_x, g_holygl.vp_y, g_holygl.vp_w, g_holygl.vp_h,
                                g_holygl.target_buffer, g_holygl.pitch, 0xFF000000);
        g_holygl.scene_active = 1;
    }
    if ((mask & GL_DEPTH_BUFFER_BIT) && g_holygl.zbuffer) {
        zbuffer_clear(g_holygl.zbuffer);
    }
}

void glClearColor(float red, float green, float blue, float alpha) {
    (void)red; (void)green; (void)blue; (void)alpha;
}

void glEnable(uint32_t cap) {
    if (cap == GL_DEPTH_TEST) g_holygl.depth_test = 1;
    else if (cap == GL_CULL_FACE) g_holygl.cull_face = 1;
    else if (cap == GL_LIGHTING) g_holygl.lighting = 1;
}

void glDisable(uint32_t cap) {
    if (cap == GL_DEPTH_TEST) g_holygl.depth_test = 0;
    else if (cap == GL_CULL_FACE) g_holygl.cull_face = 0;
    else if (cap == GL_LIGHTING) g_holygl.lighting = 0;
}

void glColor4f(float red, float green, float blue, float alpha) {
    uint32_t a = (uint32_t)(alpha * 255.0f) & 0xFF;
    uint32_t r = (uint32_t)(red * 255.0f) & 0xFF;
    uint32_t g = (uint32_t)(green * 255.0f) & 0xFF;
    uint32_t b = (uint32_t)(blue * 255.0f) & 0xFF;
    g_holygl.current_color = (a << 24) | (r << 16) | (g << 8) | b;
}

void glColor3f(float red, float green, float blue) {
    glColor4f(red, green, blue, 1.0f);
}

void glColor3ub(uint8_t r, uint8_t g, uint8_t b) {
    g_holygl.current_color = 0xFF000000 | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

void glNormal3f(float nx, float ny, float nz) {
    g_holygl.current_normal = (vec3_t){nx, ny, nz};
}

void glTexCoord2f(float u, float v) {
    g_holygl.current_uv = (vec2_t){u, v};
}

void glBegin(uint32_t mode) {
    g_holygl.primitive_mode = mode;
    g_holygl.vertex_count = 0;
    g_holygl.in_begin = 1;
    holygl_update_mvp();
}

void glVertex3f(float x, float y, float z) {
    if (!g_holygl.in_begin || g_holygl.vertex_count >= HOLYGL_MAX_VERTICES) return;

    vec4_t in_v = {x, y, z, 1.0f};
    vec4_t out_v;
    mat4_mul_vec4(&out_v, &g_holygl.mvp, &in_v);

    uint32_t col = g_holygl.current_color;
    if (g_holygl.lighting) {
        // Transform normal by upper 3x3 of active ModelView matrix
        const mat4_t *mv = &g_holygl.modelview_stack[g_holygl.modelview_depth];
        float nx = g_holygl.current_normal.x;
        float ny = g_holygl.current_normal.y;
        float nz = g_holygl.current_normal.z;
        float rot_nx = mv->m[0][0]*nx + mv->m[0][1]*ny + mv->m[0][2]*nz;
        float rot_ny = mv->m[1][0]*nx + mv->m[1][1]*ny + mv->m[1][2]*nz;
        float rot_nz = mv->m[2][0]*nx + mv->m[2][1]*ny + mv->m[2][2]*nz;
        float len_sq = rot_nx*rot_nx + rot_ny*rot_ny + rot_nz*rot_nz;
        if (len_sq > 0.00001f) {
            float inv = fast_rsqrt_neon(len_sq);
            rot_nx *= inv;
            rot_ny *= inv;
            rot_nz *= inv;
        }
        // Directional light vector L = (0.577, 0.577, 0.577) normalized (illuminates front surfaces)
        float lx = 0.57735f, ly = 0.57735f, lz = 0.57735f;
        float dot = rot_nx * lx + rot_ny * ly + rot_nz * lz;
        if (dot < 0.0f) dot = 0.0f;
        float factor = 0.35f + 0.65f * dot; // 0.35 ambient + 0.65 diffuse
        if (factor > 1.0f) factor = 1.0f;

        uint32_t a = (col >> 24) & 0xFF;
        uint32_t r = (uint32_t)(((col >> 16) & 0xFF) * factor);
        uint32_t g = (uint32_t)(((col >> 8) & 0xFF) * factor);
        uint32_t b = (uint32_t)((col & 0xFF) * factor);
        col = (a << 24) | (r << 16) | (g << 8) | b;
    }

    holygl_vertex_t *v = &g_holygl.vertex_buffer[g_holygl.vertex_count++];
    v->x = out_v.x;
    v->y = out_v.y;
    v->z = out_v.z;
    v->w = out_v.w;
    v->nx = g_holygl.current_normal.x;
    v->ny = g_holygl.current_normal.y;
    v->nz = g_holygl.current_normal.z;
    v->u = g_holygl.current_uv.u;
    v->v = g_holygl.current_uv.v;
    v->color = col;
}

void glVertex2f(float x, float y) {
    glVertex3f(x, y, 0.0f);
}

static inline void holygl_rasterize_tri(const holygl_vertex_t *v0, const holygl_vertex_t *v1, const holygl_vertex_t *v2) {
    if (v0->w <= 0.001f || v1->w <= 0.001f || v2->w <= 0.001f) return;

    float inv_w0 = 1.0f / v0->w;
    float inv_w1 = 1.0f / v1->w;
    float inv_w2 = 1.0f / v2->w;

    float half_w = (float)g_holygl.vp_w * 0.5f;
    float half_h = (float)g_holygl.vp_h * 0.5f;

    int sx0 = (int)((v0->x * inv_w0 + 1.0f) * half_w) + g_holygl.vp_x;
    int sy0 = (int)((-v0->y * inv_w0 + 1.0f) * half_h) + g_holygl.vp_y;
    int sx1 = (int)((v1->x * inv_w1 + 1.0f) * half_w) + g_holygl.vp_x;
    int sy1 = (int)((-v1->y * inv_w1 + 1.0f) * half_h) + g_holygl.vp_y;
    int sx2 = (int)((v2->x * inv_w2 + 1.0f) * half_w) + g_holygl.vp_x;
    int sy2 = (int)((-v2->y * inv_w2 + 1.0f) * half_h) + g_holygl.vp_y;

    // Backface culling
    if (g_holygl.cull_face) {
        int64_t edge = (int64_t)(sx1 - sx0) * (int64_t)(sy2 - sy0) - (int64_t)(sy1 - sy0) * (int64_t)(sx2 - sx0);
        if (edge >= 0) return; // Discard back-facing triangle
    }

    float norm_z0 = (v0->z * inv_w0 + 1.0f) * 0.5f;
    float norm_z1 = (v1->z * inv_w1 + 1.0f) * 0.5f;
    float norm_z2 = (v2->z * inv_w2 + 1.0f) * 0.5f;

    raster_vertex_t rv0 = { .x = (float)sx0, .y = (float)sy0, .z = norm_z0, .color = v0->color };
    raster_vertex_t rv1 = { .x = (float)sx1, .y = (float)sy1, .z = norm_z1, .color = v1->color };
    raster_vertex_t rv2 = { .x = (float)sx2, .y = (float)sy2, .z = norm_z2, .color = v2->color };
    raster_tile_add_triangle(&rv0, &rv1, &rv2, v0->color);
}

void glEnd(void) {
    if (!g_holygl.in_begin) return;
    g_holygl.in_begin = 0;

    if (!g_holygl.target_buffer) {
        g_holygl.target_buffer = gfx_get_backbuffer();
        g_holygl.pitch = gfx_get_canvas_pitch();
    }

    if (!g_holygl.scene_active && g_raster_scene.target_buffer == NULL) {
        raster_tile_begin_scene(g_holygl.vp_x, g_holygl.vp_y, g_holygl.vp_w, g_holygl.vp_h,
                                g_holygl.target_buffer, g_holygl.pitch, 0xFF000000);
        g_holygl.scene_active = 1;
    }

    if (g_holygl.primitive_mode == GL_TRIANGLES) {
        for (int i = 0; i + 2 < g_holygl.vertex_count; i += 3) {
            holygl_rasterize_tri(&g_holygl.vertex_buffer[i],
                                 &g_holygl.vertex_buffer[i + 1],
                                 &g_holygl.vertex_buffer[i + 2]);
        }
    } else if (g_holygl.primitive_mode == GL_QUADS) {
        for (int i = 0; i + 3 < g_holygl.vertex_count; i += 4) {
            holygl_rasterize_tri(&g_holygl.vertex_buffer[i],
                                 &g_holygl.vertex_buffer[i + 1],
                                 &g_holygl.vertex_buffer[i + 2]);
            holygl_rasterize_tri(&g_holygl.vertex_buffer[i],
                                 &g_holygl.vertex_buffer[i + 2],
                                 &g_holygl.vertex_buffer[i + 3]);
        }
    } else if (g_holygl.primitive_mode == GL_TRIANGLE_FAN) {
        for (int i = 1; i + 1 < g_holygl.vertex_count; i++) {
            holygl_rasterize_tri(&g_holygl.vertex_buffer[0],
                                 &g_holygl.vertex_buffer[i],
                                 &g_holygl.vertex_buffer[i + 1]);
        }
    } else if (g_holygl.primitive_mode == GL_LINES) {
        for (int i = 0; i + 1 < g_holygl.vertex_count; i += 2) {
            const holygl_vertex_t *v0 = &g_holygl.vertex_buffer[i];
            const holygl_vertex_t *v1 = &g_holygl.vertex_buffer[i + 1];
            if (v0->w > 0.001f && v1->w > 0.001f) {
                float inv_w0 = 1.0f / v0->w;
                float inv_w1 = 1.0f / v1->w;
                float half_w = (float)g_holygl.vp_w * 0.5f;
                float half_h = (float)g_holygl.vp_h * 0.5f;
                int sx0 = (int)((v0->x * inv_w0 + 1.0f) * half_w) + g_holygl.vp_x;
                int sy0 = (int)((-v0->y * inv_w0 + 1.0f) * half_h) + g_holygl.vp_y;
                int sx1 = (int)((v1->x * inv_w1 + 1.0f) * half_w) + g_holygl.vp_x;
                int sy1 = (int)((-v1->y * inv_w1 + 1.0f) * half_h) + g_holygl.vp_y;
                gfx_draw_line(sx0, sy0, sx1, sy1, v0->color);
            }
        }
    }
}

void glFlush(void) {
    if (g_raster_scene.target_buffer != NULL) {
        raster_tile_end_scene();
        g_holygl.scene_active = 0;
    }
}
