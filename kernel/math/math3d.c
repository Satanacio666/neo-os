#include "math3d.h"
#include "../../gui/render.h"
#include "../mem/kheap.h"

#define PI 3.14159265358979323846f
#define DEG2RAD (PI / 180.0f)

static float sin_table[360];
static float cos_table[360];
static int   math3d_initialized = 0;

static inline float fast_sqrt(float x) {
    if (x <= 0.0f) return 0.0f;
    float res;
    asm volatile("fsqrt %s0, %s1" : "=w"(res) : "w"(x));
    return res;
}

static float calc_taylor_sin(float deg) {
    while (deg < 0.0f) deg += 360.0f;
    while (deg >= 360.0f) deg -= 360.0f;

    float sign = 1.0f;
    if (deg > 180.0f) {
        deg -= 180.0f;
        sign = -1.0f;
    }
    if (deg > 90.0f) {
        deg = 180.0f - deg;
    }

    float r = deg * DEG2RAD;
    float r2 = r * r;
    // 5-term Taylor expansion: x - x^3/6 + x^5/120 - x^7/5040 + x^9/362880
    float s = r - (r * r2) / 6.0f 
                + (r * r2 * r2) / 120.0f 
                - (r * r2 * r2 * r2) / 5040.0f 
                + (r * r2 * r2 * r2 * r2) / 362880.0f;
    return sign * s;
}

void math3d_init(void) {
    if (math3d_initialized) return;
    for (int i = 0; i < 360; i++) {
        sin_table[i] = calc_taylor_sin((float)i);
        cos_table[i] = calc_taylor_sin((float)(i + 90));
    }
    math3d_initialized = 1;
}

float math3d_sin(float deg) {
    if (!math3d_initialized) math3d_init();
    int idx = (int)deg % 360;
    if (idx < 0) idx += 360;
    return sin_table[idx];
}

float math3d_cos(float deg) {
    if (!math3d_initialized) math3d_init();
    int idx = (int)deg % 360;
    if (idx < 0) idx += 360;
    return cos_table[idx];
}

vec3_t vec3_add(vec3_t a, vec3_t b) {
    return (vec3_t){a.x + b.x, a.y + b.y, a.z + b.z};
}

vec3_t vec3_sub(vec3_t a, vec3_t b) {
    return (vec3_t){a.x - b.x, a.y - b.y, a.z - b.z};
}

vec3_t vec3_scale(vec3_t v, float s) {
    return (vec3_t){v.x * s, v.y * s, v.z * s};
}

float vec3_dot(vec3_t a, vec3_t b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

vec3_t vec3_cross(vec3_t a, vec3_t b) {
    return (vec3_t){
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
}

vec3_t vec3_normalize(vec3_t v) {
    float len = fast_sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (len > 0.00001f) {
        float inv = 1.0f / len;
        return (vec3_t){v.x * inv, v.y * inv, v.z * inv};
    }
    return (vec3_t){0, 0, 0};
}

void mat4_identity(mat4_t *out) {
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            out->m[r][c] = (r == c) ? 1.0f : 0.0f;
        }
    }
}

void mat4_translate(mat4_t *out, float tx, float ty, float tz) {
    mat4_identity(out);
    out->m[0][3] = tx;
    out->m[1][3] = ty;
    out->m[2][3] = tz;
}

void mat4_scale(mat4_t *out, float sx, float sy, float sz) {
    mat4_identity(out);
    out->m[0][0] = sx;
    out->m[1][1] = sy;
    out->m[2][2] = sz;
}

void mat4_rotate_x(mat4_t *out, float deg) {
    mat4_identity(out);
    float s = math3d_sin(deg);
    float c = math3d_cos(deg);
    out->m[1][1] = c;  out->m[1][2] = -s;
    out->m[2][1] = s;  out->m[2][2] = c;
}

void mat4_rotate_y(mat4_t *out, float deg) {
    mat4_identity(out);
    float s = math3d_sin(deg);
    float c = math3d_cos(deg);
    out->m[0][0] = c;   out->m[0][2] = s;
    out->m[2][0] = -s;  out->m[2][2] = c;
}

void mat4_rotate_z(mat4_t *out, float deg) {
    mat4_identity(out);
    float s = math3d_sin(deg);
    float c = math3d_cos(deg);
    out->m[0][0] = c;  out->m[0][1] = -s;
    out->m[1][0] = s;  out->m[1][1] = c;
}

void mat4_mul(mat4_t *out, const mat4_t *a, const mat4_t *b) {
    mat4_t tmp;
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            tmp.m[r][c] = a->m[r][0] * b->m[0][c] +
                          a->m[r][1] * b->m[1][c] +
                          a->m[r][2] * b->m[2][c] +
                          a->m[r][3] * b->m[3][c];
        }
    }
    *out = tmp;
}

void mat4_mul_vec4(vec4_t *out, const mat4_t *m, const vec4_t *v) {
    out->x = m->m[0][0] * v->x + m->m[0][1] * v->y + m->m[0][2] * v->z + m->m[0][3] * v->w;
    out->y = m->m[1][0] * v->x + m->m[1][1] * v->y + m->m[1][2] * v->z + m->m[1][3] * v->w;
    out->z = m->m[2][0] * v->x + m->m[2][1] * v->y + m->m[2][2] * v->z + m->m[2][3] * v->w;
    out->w = m->m[3][0] * v->x + m->m[3][1] * v->y + m->m[3][2] * v->z + m->m[3][3] * v->w;
}

void mat4_perspective(mat4_t *out, float fov_deg, float aspect, float near_z, float far_z) {
    mat4_identity(out);
    float half_fov = fov_deg * 0.5f;
    float s = math3d_sin(half_fov);
    float c = math3d_cos(half_fov);
    float tan_half = (s > 0.0001f) ? (s / c) : 1.0f;
    float inv_tan = 1.0f / tan_half;

    out->m[0][0] = inv_tan / aspect;
    out->m[1][1] = inv_tan;
    out->m[2][2] = -(far_z + near_z) / (far_z - near_z);
    out->m[2][3] = -(2.0f * far_z * near_z) / (far_z - near_z);
    out->m[3][2] = -1.0f;
    out->m[3][3] = 0.0f;
}

void mesh3d_init_cube(mesh3d_cube_t *cube, float size) {
    float h = size * 0.5f;
    cube->num_vertices = 8;
    cube->vertices[0] = (vec3_t){-h, -h, -h};
    cube->vertices[1] = (vec3_t){ h, -h, -h};
    cube->vertices[2] = (vec3_t){ h,  h, -h};
    cube->vertices[3] = (vec3_t){-h,  h, -h};
    cube->vertices[4] = (vec3_t){-h, -h,  h};
    cube->vertices[5] = (vec3_t){ h, -h,  h};
    cube->vertices[6] = (vec3_t){ h,  h,  h};
    cube->vertices[7] = (vec3_t){-h,  h,  h};

    cube->num_edges = 12;
    int edges[12][2] = {
        {0, 1}, {1, 2}, {2, 3}, {3, 0}, // Back
        {4, 5}, {5, 6}, {6, 7}, {7, 4}, // Front
        {0, 4}, {1, 5}, {2, 6}, {3, 7}  // Connectors
    };
    for (int i = 0; i < 12; i++) {
        cube->edges[i][0] = edges[i][0];
        cube->edges[i][1] = edges[i][1];
    }

    cube->num_triangles = 12;
    int tris[12][3] = {
        // Front face (+Z)
        {4, 5, 6}, {4, 6, 7},
        // Back face (-Z)
        {1, 0, 3}, {1, 3, 2},
        // Top face (+Y)
        {3, 6, 2}, {3, 7, 6},
        // Bottom face (-Y)
        {4, 0, 1}, {4, 1, 5},
        // Right face (+X)
        {5, 1, 2}, {5, 2, 6},
        // Left face (-X)
        {0, 4, 7}, {0, 7, 3}
    };
    for (int i = 0; i < 12; i++) {
        cube->triangles[i].v[0] = tris[i][0];
        cube->triangles[i].v[1] = tris[i][1];
        cube->triangles[i].v[2] = tris[i][2];
        cube->triangles[i].color = 0xFF3DAEE9;
        if ((i % 2) == 0) {
            cube->triangles[i].uv[0] = (vec2_t){0.0f, 0.0f};
            cube->triangles[i].uv[1] = (vec2_t){1.0f, 0.0f};
            cube->triangles[i].uv[2] = (vec2_t){1.0f, 1.0f};
        } else {
            cube->triangles[i].uv[0] = (vec2_t){0.0f, 0.0f};
            cube->triangles[i].uv[1] = (vec2_t){1.0f, 1.0f};
            cube->triangles[i].uv[2] = (vec2_t){0.0f, 1.0f};
        }
    }
}

// Wireframe Cube Render
void mesh3d_render_wireframe(const mesh3d_cube_t *cube, const mat4_t *mvp,
                             int vp_x, int vp_y, int vp_w, int vp_h,
                             uint32_t wire_color, uint32_t vert_color) {
    int screen_x[8];
    int screen_y[8];
    int valid[8];

    float half_w = (float)vp_w * 0.5f;
    float half_h = (float)vp_h * 0.5f;
    float center_x = (float)vp_x + half_w;
    float center_y = (float)vp_y + half_h;

    // Transform and project all 8 vertices
    for (int i = 0; i < cube->num_vertices; i++) {
        vec4_t v = {cube->vertices[i].x, cube->vertices[i].y, cube->vertices[i].z, 1.0f};
        vec4_t p;
        mat4_mul_vec4(&p, mvp, &v);

        if (p.w > 0.05f) {
            float inv_w = 1.0f / p.w;
            float ndc_x = p.x * inv_w;
            float ndc_y = p.y * inv_w;
            screen_x[i] = (int)(center_x + ndc_x * half_w);
            screen_y[i] = (int)(center_y - ndc_y * half_h); // Invert Y
            valid[i] = 1;
        } else {
            valid[i] = 0;
        }
    }

    // Draw 12 edges with Bresenham
    for (int i = 0; i < cube->num_edges; i++) {
        int v0 = cube->edges[i][0];
        int v1 = cube->edges[i][1];
        if (valid[v0] && valid[v1]) {
            gfx_draw_line_clipped(screen_x[v0], screen_y[v0],
                                  screen_x[v1], screen_y[v1], wire_color);
        }
    }

    // Draw vertex highlight points
    if (vert_color != 0) {
        for (int i = 0; i < cube->num_vertices; i++) {
            if (valid[i]) {
                gfx_fill_circle(screen_x[i], screen_y[i], 3, vert_color);
            }
        }
    }
}

// Solid Shaded Cube Render with Painter's Algorithm and Lambertian Diffuse Lighting
void mesh3d_render_solid(const mesh3d_cube_t *cube, const mat4_t *mvp,
                         int vp_x, int vp_y, int vp_w, int vp_h,
                         uint32_t base_color, vec3_t light_dir) {
    int screen_x[8];
    int screen_y[8];
    float screen_z[8];
    int valid[8];

    float half_w = (float)vp_w * 0.5f;
    float half_h = (float)vp_h * 0.5f;
    float center_x = (float)vp_x + half_w;
    float center_y = (float)vp_y + half_h;

    for (int i = 0; i < cube->num_vertices; i++) {
        vec4_t v = {cube->vertices[i].x, cube->vertices[i].y, cube->vertices[i].z, 1.0f};
        vec4_t p;
        mat4_mul_vec4(&p, mvp, &v);

        if (p.w > 0.05f) {
            float inv_w = 1.0f / p.w;
            float ndc_x = p.x * inv_w;
            float ndc_y = p.y * inv_w;
            screen_x[i] = (int)(center_x + ndc_x * half_w);
            screen_y[i] = (int)(center_y - ndc_y * half_h);
            screen_z[i] = p.w;
            valid[i] = 1;
        } else {
            valid[i] = 0;
        }
    }

    light_dir = vec3_normalize(light_dir);

    // Compute triangle depth and backface culling
    tri3d_t draw_tris[12];
    int num_draw = 0;

    for (int i = 0; i < cube->num_triangles; i++) {
        int i0 = cube->triangles[i].v[0];
        int i1 = cube->triangles[i].v[1];
        int i2 = cube->triangles[i].v[2];

        if (!valid[i0] || !valid[i1] || !valid[i2]) continue;

        // 2D Screen Space Cross Product for Backface Culling (CCW front-facing)
        int x0 = screen_x[i0], y0 = screen_y[i0];
        int x1 = screen_x[i1], y1 = screen_y[i1];
        int x2 = screen_x[i2], y2 = screen_y[i2];
        int cross = (x1 - x0) * (y0 - y2) - (y1 - y0) * (x0 - x2);
        if (cross <= 0) continue; // Culled!

        // Compute 3D normal in model space
        vec3_t e1 = vec3_sub(cube->vertices[i1], cube->vertices[i0]);
        vec3_t e2 = vec3_sub(cube->vertices[i2], cube->vertices[i0]);
        vec3_t norm = vec3_normalize(vec3_cross(e1, e2));

        // Diffuse Lambertian Lighting
        float dot = vec3_dot(norm, light_dir);
        if (dot < 0.2f) dot = 0.2f; // Ambient term

        uint32_t r = (base_color >> 16) & 0xFF;
        uint32_t g = (base_color >> 8) & 0xFF;
        uint32_t b = (base_color) & 0xFF;

        r = (uint32_t)((float)r * dot);
        g = (uint32_t)((float)g * dot);
        b = (uint32_t)((float)b * dot);
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;

        draw_tris[num_draw] = cube->triangles[i];
        draw_tris[num_draw].color = 0xFF000000 | (r << 16) | (g << 8) | b;
        draw_tris[num_draw].avg_depth = (screen_z[i0] + screen_z[i1] + screen_z[i2]) / 3.0f;
        num_draw++;
    }

    // Sort visible triangles by depth descending (Painter's Algorithm)
    for (int i = 0; i < num_draw - 1; i++) {
        for (int j = 0; j < num_draw - i - 1; j++) {
            if (draw_tris[j].avg_depth < draw_tris[j + 1].avg_depth) {
                tri3d_t tmp = draw_tris[j];
                draw_tris[j] = draw_tris[j + 1];
                draw_tris[j + 1] = tmp;
            }
        }
    }

    // Rasterize sorted triangles and draw darker edge highlights
    for (int i = 0; i < num_draw; i++) {
        int i0 = draw_tris[i].v[0];
        int i1 = draw_tris[i].v[1];
        int i2 = draw_tris[i].v[2];

        gfx_draw_triangle_fill(screen_x[i0], screen_y[i0],
                               screen_x[i1], screen_y[i1],
                               screen_x[i2], screen_y[i2],
                               draw_tris[i].color);

        // Edge accent wire
        gfx_draw_triangle_wire(screen_x[i0], screen_y[i0],
                               screen_x[i1], screen_y[i1],
                               screen_x[i2], screen_y[i2],
                               0xFF1B1E20);
    }
}

void texture_generate_procedural(uint32_t *buffer, int w, int h, int mode) {
    if (!buffer || w <= 0 || h <= 0) return;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint32_t col = 0xFF18202A;
            if (mode == 0) {
                if (x < 3 || x >= w - 3 || y < 3 || y >= h - 3) {
                    col = COLOR_NEON_CYAN;
                } else if ((x >= w / 2 - 1 && x <= w / 2 + 1) || (y >= h / 2 - 1 && y <= h / 2 + 1)) {
                    col = COLOR_MAGENTA;
                } else if ((x % 8) == 0 || (y % 8) == 0) {
                    col = 0xFF2A3644;
                }
            } else {
                int check = ((x / 8) + (y / 8)) % 2;
                col = check ? COLOR_BRIGHT_GOLD : 0xFF232830;
            }
            buffer[y * w + x] = col;
        }
    }
}

void mesh3d_render_subdivided_wireframe(const mesh3d_cube_t *cube, const mat4_t *mvp,
                                        int vp_x, int vp_y, int vp_w, int vp_h,
                                        uint32_t wire_color, int divisions) {
    mesh3d_render_wireframe(cube, mvp, vp_x, vp_y, vp_w, vp_h, wire_color, COLOR_EMERALD_GREEN);
    int screen_x[8], screen_y[8], valid[8];
    float half_w = (float)vp_w * 0.5f, half_h = (float)vp_h * 0.5f;
    float center_x = (float)vp_x + half_w, center_y = (float)vp_y + half_h;

    for (int i = 0; i < cube->num_vertices; i++) {
        vec4_t v = {cube->vertices[i].x, cube->vertices[i].y, cube->vertices[i].z, 1.0f};
        vec4_t p;
        mat4_mul_vec4(&p, mvp, &v);
        if (p.w > 0.05f) {
            float inv_w = 1.0f / p.w;
            screen_x[i] = (int)(center_x + p.x * inv_w * half_w);
            screen_y[i] = (int)(center_y - p.y * inv_w * half_h);
            valid[i] = 1;
        } else valid[i] = 0;
    }

    int diags[6][4] = {
        {4, 6, 5, 7}, {0, 2, 1, 3}, {3, 6, 2, 7},
        {4, 1, 0, 5}, {5, 2, 1, 6}, {0, 7, 4, 3}
    };
    for (int f = 0; f < 6; f++) {
        int a = diags[f][0], b = diags[f][1], c = diags[f][2], d = diags[f][3];
        if (valid[a] && valid[b]) gfx_draw_line_clipped(screen_x[a], screen_y[a], screen_x[b], screen_y[b], 0xFF2A829E);
        if (valid[c] && valid[d]) gfx_draw_line_clipped(screen_x[c], screen_y[c], screen_x[d], screen_y[d], 0xFF2A829E);
    }
}

void mesh3d_render_textured(const mesh3d_cube_t *cube, const mat4_t *mvp,
                            int vp_x, int vp_y, int vp_w, int vp_h,
                            const uint32_t *texture, int tex_w, int tex_h) {
    if (!cube || !mvp || !texture || tex_w <= 0 || tex_h <= 0) return;

    int screen_x[8], screen_y[8];
    float screen_z[8];
    int valid[8];

    float half_w = (float)vp_w * 0.5f, half_h = (float)vp_h * 0.5f;
    float center_x = (float)vp_x + half_w, center_y = (float)vp_y + half_h;

    for (int i = 0; i < cube->num_vertices; i++) {
        vec4_t v = {cube->vertices[i].x, cube->vertices[i].y, cube->vertices[i].z, 1.0f};
        vec4_t p;
        mat4_mul_vec4(&p, mvp, &v);
        if (p.w > 0.05f) {
            float inv_w = 1.0f / p.w;
            screen_x[i] = (int)(center_x + p.x * inv_w * half_w);
            screen_y[i] = (int)(center_y - p.y * inv_w * half_h);
            screen_z[i] = p.w;
            valid[i] = 1;
        } else valid[i] = 0;
    }

    tri3d_t draw_tris[12];
    int num_draw = 0;

    for (int i = 0; i < cube->num_triangles; i++) {
        int i0 = cube->triangles[i].v[0];
        int i1 = cube->triangles[i].v[1];
        int i2 = cube->triangles[i].v[2];
        if (!valid[i0] || !valid[i1] || !valid[i2]) continue;

        int cross = (screen_x[i1] - screen_x[i0]) * (screen_y[i2] - screen_y[i0]) -
                    (screen_y[i1] - screen_y[i0]) * (screen_x[i2] - screen_x[i0]);
        if (cross <= 0) continue;

        draw_tris[num_draw] = cube->triangles[i];
        draw_tris[num_draw].avg_depth = (screen_z[i0] + screen_z[i1] + screen_z[i2]) / 3.0f;
        num_draw++;
    }

    for (int i = 0; i < num_draw - 1; i++) {
        for (int j = 0; j < num_draw - i - 1; j++) {
            if (draw_tris[j].avg_depth < draw_tris[j + 1].avg_depth) {
                tri3d_t tmp = draw_tris[j];
                draw_tris[j] = draw_tris[j + 1];
                draw_tris[j + 1] = tmp;
            }
        }
    }

    for (int i = 0; i < num_draw; i++) {
        int i0 = draw_tris[i].v[0], i1 = draw_tris[i].v[1], i2 = draw_tris[i].v[2];
        int x0 = screen_x[i0], y0 = screen_y[i0];
        int x1 = screen_x[i1], y1 = screen_y[i1];
        int x2 = screen_x[i2], y2 = screen_y[i2];

        vec2_t uv0 = draw_tris[i].uv[0];
        vec2_t uv1 = draw_tris[i].uv[1];
        vec2_t uv2 = draw_tris[i].uv[2];

        if (y0 > y1) {
            int tx = x0; x0 = x1; x1 = tx;
            int ty = y0; y0 = y1; y1 = ty;
            vec2_t tu = uv0; uv0 = uv1; uv1 = tu;
        }
        if (y1 > y2) {
            int tx = x1; x1 = x2; x2 = tx;
            int ty = y1; y1 = y2; y2 = ty;
            vec2_t tu = uv1; uv1 = uv2; uv2 = tu;
        }
        if (y0 > y1) {
            int tx = x0; x0 = x1; x1 = tx;
            int ty = y0; y0 = y1; y1 = ty;
            vec2_t tu = uv0; uv0 = uv1; uv1 = tu;
        }

        int total_h = y2 - y0;
        if (total_h <= 0) continue;

        for (int row = 0; row <= total_h; row++) {
            int second_half = row > (y1 - y0) || y1 == y0;
            int seg_h = second_half ? (y2 - y1) : (y1 - y0);
            if (seg_h <= 0) continue;

            float alpha = (float)row / (float)total_h;
            float beta = (float)(row - (second_half ? (y1 - y0) : 0)) / (float)seg_h;

            int ax = x0 + (int)((float)(x2 - x0) * alpha);
            int bx = second_half ? (x1 + (int)((float)(x2 - x1) * beta)) : (x0 + (int)((float)(x1 - x0) * beta));

            float au = uv0.u + (uv2.u - uv0.u) * alpha;
            float av = uv0.v + (uv2.v - uv0.v) * alpha;
            float bu = second_half ? (uv1.u + (uv2.u - uv1.u) * beta) : (uv0.u + (uv1.u - uv0.u) * beta);
            float bv = second_half ? (uv1.v + (uv2.v - uv1.v) * beta) : (uv0.v + (uv1.v - uv0.v) * beta);

            if (ax > bx) {
                int swp = ax; ax = bx; bx = swp;
                float swpu = au; au = bu; bu = swpu;
                float swpv = av; av = bv; bv = swpv;
            }

            int cy = y0 + row;
            int span_w = bx - ax;
            if (span_w <= 0) span_w = 1;

            for (int cx = ax; cx <= bx; cx++) {
                float t = (float)(cx - ax) / (float)span_w;
                float cu = au + (bu - au) * t;
                float cv = av + (bv - av) * t;
                int tx = (int)(cu * (tex_w - 1));
                int ty = (int)(cv * (tex_h - 1));
                if (tx < 0) { tx = 0; }
                if (tx >= tex_w) { tx = tex_w - 1; }
                if (ty < 0) { ty = 0; }
                if (ty >= tex_h) { ty = tex_h - 1; }

                uint32_t texel = texture[ty * tex_w + tx];
                gfx_put_pixel((uint32_t)cx, (uint32_t)cy, texel);
            }
        }
        gfx_draw_triangle_wire(x0, y0, x1, y1, x2, y2, 0xFF1B1E20);
    }
}

void mesh3d_render_phong(const mesh3d_cube_t *cube, const mat4_t *mvp,
                         int vp_x, int vp_y, int vp_w, int vp_h,
                         uint32_t base_color, vec3_t light_dir,
                         vec3_t point_light_pos, uint32_t point_color) {
    int screen_x[8], screen_y[8];
    float screen_z[8];
    int valid[8];

    float half_w = (float)vp_w * 0.5f, half_h = (float)vp_h * 0.5f;
    float center_x = (float)vp_x + half_w, center_y = (float)vp_y + half_h;

    for (int i = 0; i < cube->num_vertices; i++) {
        vec4_t v = {cube->vertices[i].x, cube->vertices[i].y, cube->vertices[i].z, 1.0f};
        vec4_t p;
        mat4_mul_vec4(&p, mvp, &v);
        if (p.w > 0.05f) {
            float inv_w = 1.0f / p.w;
            screen_x[i] = (int)(center_x + p.x * inv_w * half_w);
            screen_y[i] = (int)(center_y - p.y * inv_w * half_h);
            screen_z[i] = p.w;
            valid[i] = 1;
        } else valid[i] = 0;
    }

    light_dir = vec3_normalize(light_dir);
    tri3d_t draw_tris[12];
    int num_draw = 0;

    for (int i = 0; i < cube->num_triangles; i++) {
        int i0 = cube->triangles[i].v[0], i1 = cube->triangles[i].v[1], i2 = cube->triangles[i].v[2];
        if (!valid[i0] || !valid[i1] || !valid[i2]) continue;

        int cross = (screen_x[i1] - screen_x[i0]) * (screen_y[i2] - screen_y[i0]) -
                    (screen_y[i1] - screen_y[i0]) * (screen_x[i2] - screen_x[i0]);
        if (cross <= 0) continue;

        vec3_t e1 = vec3_sub(cube->vertices[i1], cube->vertices[i0]);
        vec3_t e2 = vec3_sub(cube->vertices[i2], cube->vertices[i0]);
        vec3_t norm = vec3_normalize(vec3_cross(e1, e2));

        float diff = vec3_dot(norm, light_dir);
        if (diff < 0.15f) diff = 0.15f;

        vec3_t view_dir = {0.0f, 0.0f, 1.0f};
        vec3_t half_vec = vec3_normalize(vec3_add(light_dir, view_dir));
        float spec = vec3_dot(norm, half_vec);
        if (spec < 0.0f) spec = 0.0f;
        spec = spec * spec;
        spec = spec * spec;
        spec = spec * spec;

        uint32_t r = (base_color >> 16) & 0xFF;
        uint32_t g = (base_color >> 8) & 0xFF;
        uint32_t b = (base_color) & 0xFF;

        r = (uint32_t)((float)r * diff + 255.0f * spec * 0.7f);
        g = (uint32_t)((float)g * diff + 255.0f * spec * 0.7f);
        b = (uint32_t)((float)b * diff + 255.0f * spec * 0.7f);
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;

        draw_tris[num_draw] = cube->triangles[i];
        draw_tris[num_draw].color = 0xFF000000 | (r << 16) | (g << 8) | b;
        draw_tris[num_draw].avg_depth = (screen_z[i0] + screen_z[i1] + screen_z[i2]) / 3.0f;
        num_draw++;
    }

    for (int i = 0; i < num_draw - 1; i++) {
        for (int j = 0; j < num_draw - i - 1; j++) {
            if (draw_tris[j].avg_depth < draw_tris[j + 1].avg_depth) {
                tri3d_t tmp = draw_tris[j];
                draw_tris[j] = draw_tris[j + 1];
                draw_tris[j + 1] = tmp;
            }
        }
    }

    for (int i = 0; i < num_draw; i++) {
        int i0 = draw_tris[i].v[0], i1 = draw_tris[i].v[1], i2 = draw_tris[i].v[2];
        gfx_draw_triangle_fill(screen_x[i0], screen_y[i0],
                               screen_x[i1], screen_y[i1],
                               screen_x[i2], screen_y[i2],
                               draw_tris[i].color);
        gfx_draw_triangle_wire(screen_x[i0], screen_y[i0],
                               screen_x[i1], screen_y[i1],
                               screen_x[i2], screen_y[i2],
                               0xFF1B1E20);
    }
}

// ---------------------------------------------------------------------------
// Unified 16-bit Z-Buffer Management
// ---------------------------------------------------------------------------

int zbuffer_init(zbuffer_t *zb, int w, int h) {
    if (!zb || w <= 0 || h <= 0) return 0;
    zb->width = w;
    zb->height = h;
    zb->buffer = (uint16_t*)kmalloc((size_t)w * h * sizeof(uint16_t));
    if (!zb->buffer) return 0;
    zbuffer_clear(zb);
    return 1;
}

void zbuffer_clear(zbuffer_t *zb) {
    if (!zb || !zb->buffer) return;
    memset(zb->buffer, 0xFF, (size_t)zb->width * zb->height * sizeof(uint16_t));
}

void zbuffer_free(zbuffer_t *zb) {
    if (zb && zb->buffer) {
        kfree(zb->buffer);
        zb->buffer = NULL;
    }
}

// ---------------------------------------------------------------------------
// Analytical Homogenous Near-Plane Frustum Triangle Clipping (Sutherland-Hodgman)
// ---------------------------------------------------------------------------

static inline clip_vertex_t lerp_clip_vert(const clip_vertex_t *a, const clip_vertex_t *b, float t) {
    clip_vertex_t out;
    out.pos.x = a->pos.x + t * (b->pos.x - a->pos.x);
    out.pos.y = a->pos.y + t * (b->pos.y - a->pos.y);
    out.pos.z = a->pos.z + t * (b->pos.z - a->pos.z);
    out.pos.w = a->pos.w + t * (b->pos.w - a->pos.w);
    out.normal.x = a->normal.x + t * (b->normal.x - a->normal.x);
    out.normal.y = a->normal.y + t * (b->normal.y - a->normal.y);
    out.normal.z = a->normal.z + t * (b->normal.z - a->normal.z);
    out.color = a->color;
    return out;
}

int clip_triangle_near_plane(const clip_vertex_t in_v[3], float near_w, clip_vertex_t out_tris[2][3]) {
    int inside[3];
    int num_inside = 0;
    for (int i = 0; i < 3; i++) {
        if (in_v[i].pos.w >= near_w) {
            inside[i] = 1;
            num_inside++;
        } else {
            inside[i] = 0;
        }
    }

    if (num_inside == 3) {
        out_tris[0][0] = in_v[0];
        out_tris[0][1] = in_v[1];
        out_tris[0][2] = in_v[2];
        return 1;
    }

    if (num_inside == 0) {
        return 0;
    }

    if (num_inside == 1) {
        int in_idx = inside[0] ? 0 : (inside[1] ? 1 : 2);
        int out1 = (in_idx + 1) % 3;
        int out2 = (in_idx + 2) % 3;

        const clip_vertex_t *A = &in_v[in_idx];
        const clip_vertex_t *B = &in_v[out1];
        const clip_vertex_t *C = &in_v[out2];

        float denom1 = B->pos.w - A->pos.w;
        float denom2 = C->pos.w - A->pos.w;
        float t1 = (denom1 != 0.0f) ? ((near_w - A->pos.w) / denom1) : 0.0f;
        float t2 = (denom2 != 0.0f) ? ((near_w - A->pos.w) / denom2) : 0.0f;
        if (t1 < 0.0f) t1 = 0.0f; else if (t1 > 1.0f) t1 = 1.0f;
        if (t2 < 0.0f) t2 = 0.0f; else if (t2 > 1.0f) t2 = 1.0f;

        clip_vertex_t B_prime = lerp_clip_vert(A, B, t1);
        clip_vertex_t C_prime = lerp_clip_vert(A, C, t2);

        out_tris[0][0] = *A;
        out_tris[0][1] = B_prime;
        out_tris[0][2] = C_prime;
        return 1;
    }

    if (num_inside == 2) {
        int out_idx = (!inside[0]) ? 0 : ((!inside[1]) ? 1 : 2);
        int in1 = (out_idx + 1) % 3;
        int in2 = (out_idx + 2) % 3;

        const clip_vertex_t *A = &in_v[in1];
        const clip_vertex_t *B = &in_v[in2];
        const clip_vertex_t *C = &in_v[out_idx];

        float denom1 = C->pos.w - A->pos.w;
        float denom2 = C->pos.w - B->pos.w;
        float t1 = (denom1 != 0.0f) ? ((near_w - A->pos.w) / denom1) : 0.0f;
        float t2 = (denom2 != 0.0f) ? ((near_w - B->pos.w) / denom2) : 0.0f;
        if (t1 < 0.0f) t1 = 0.0f; else if (t1 > 1.0f) t1 = 1.0f;
        if (t2 < 0.0f) t2 = 0.0f; else if (t2 > 1.0f) t2 = 1.0f;

        clip_vertex_t A_prime = lerp_clip_vert(A, C, t1);
        clip_vertex_t B_prime = lerp_clip_vert(B, C, t2);

        out_tris[0][0] = *A;
        out_tris[0][1] = *B;
        out_tris[0][2] = B_prime;

        out_tris[1][0] = *A;
        out_tris[1][1] = B_prime;
        out_tris[1][2] = A_prime;
        return 2;
    }

    return 0;
}

// ---------------------------------------------------------------------------
// High-Performance 16.16 Fixed-Point Scanline Rasterizer (Top-Left Rule)
// ---------------------------------------------------------------------------

void rasterize_triangle_scanline(
    int x0, int y0, uint16_t z0,
    int x1, int y1, uint16_t z1,
    int x2, int y2, uint16_t z2,
    uint32_t shaded_color,
    int viewport_x, int viewport_y, int viewport_w, int viewport_h,
    zbuffer_t *zb, uint32_t *target_buffer, uint32_t pitch)
{
    // Sort vertices by Y ascending (sy0 <= sy1 <= sy2)
    int sx0 = x0, sy0 = y0, sz0 = (int)z0;
    int sx1 = x1, sy1 = y1, sz1 = (int)z1;
    int sx2 = x2, sy2 = y2, sz2 = (int)z2;

    if (sy0 > sy1) {
        int tx = sx0; sx0 = sx1; sx1 = tx;
        int ty = sy0; sy0 = sy1; sy1 = ty;
        int tz = sz0; sz0 = sz1; sz1 = tz;
    }
    if (sy0 > sy2) {
        int tx = sx0; sx0 = sx2; sx2 = tx;
        int ty = sy0; sy0 = sy2; sy2 = ty;
        int tz = sz0; sz0 = sz2; sz2 = tz;
    }
    if (sy1 > sy2) {
        int tx = sx1; sx1 = sx2; sx2 = tx;
        int ty = sy1; sy1 = sy2; sy2 = ty;
        int tz = sz1; sz1 = sz2; sz2 = tz;
    }

    int dy02 = sy2 - sy0;
    if (dy02 <= 0) return; // Flat zero-height triangle

    int dy01 = sy1 - sy0;
    int dy12 = sy2 - sy1;

    // Fixed-point slopes for major long edge 0 -> 2
    int32_t dx02 = (int32_t)(((int64_t)(sx2 - sx0) << 16) / dy02);
    int32_t dz02 = (int32_t)(((int64_t)(sz2 - sz0) << 16) / dy02);

    int32_t dx01 = (dy01 > 0) ? (int32_t)(((int64_t)(sx1 - sx0) << 16) / dy01) : 0;
    int32_t dz01 = (dy01 > 0) ? (int32_t)(((int64_t)(sz1 - sz0) << 16) / dy01) : 0;

    int32_t dx12 = (dy12 > 0) ? (int32_t)(((int64_t)(sx2 - sx1) << 16) / dy12) : 0;
    int32_t dz12 = (dy12 > 0) ? (int32_t)(((int64_t)(sz2 - sz1) << 16) / dy12) : 0;

    int32_t xA = (int32_t)((int64_t)sx0 << 16);
    int32_t zA = (int32_t)((int64_t)sz0 << 16);
    int32_t xB = xA;
    int32_t zB = zA;

    int v_min_x = viewport_x;
    int v_max_x = viewport_x + viewport_w; // Half-open interval
    int v_min_y = viewport_y;
    int v_max_y = viewport_y + viewport_h;

    // Section 1: Scanlines from sy0 to sy1
    for (int y = sy0; y < sy1; y++) {
        if (y >= v_min_y && y < v_max_y) {
            int xl = (int)(xA >> 16);
            int xr = (int)(xB >> 16);
            int32_t zl = zA, zr = zB;

            if (xl > xr) {
                int tx = xl; xl = xr; xr = tx;
                int32_t tz = zl; zl = zr; zr = tz;
            }

            int span_w = xr - xl;
            if (span_w > 0) {
                int32_t dz_dx = (int32_t)(((int64_t)(zr - zl)) / span_w);
                int x_start = (xl < v_min_x) ? v_min_x : xl;
                int x_end   = (xr > v_max_x) ? v_max_x : xr;

                if (x_start < x_end) {
                    int32_t cur_z = zl + (int32_t)((int64_t)dz_dx * (x_start - xl));
                    uint32_t *dst_pixel = target_buffer ? (target_buffer + y * pitch + x_start) : NULL;
                    uint16_t *dst_z = (zb && zb->buffer) ? (zb->buffer + (y - viewport_y) * zb->width + (x_start - viewport_x)) : NULL;

                    for (int px = x_start; px < x_end; px++) {
                        uint16_t z16 = (uint16_t)(cur_z >> 16);
                        if (!dst_z || z16 < *dst_z) {
                            if (dst_z) *dst_z = z16;
                            if (dst_pixel) *dst_pixel = shaded_color;
                        }
                        cur_z += dz_dx;
                        if (dst_pixel) dst_pixel++;
                        if (dst_z) dst_z++;
                    }
                }
            }
        }
        xA += dx02;
        zA += dz02;
        xB += dx01;
        zB += dz01;
    }

    // Section 2: Scanlines from sy1 to sy2
    xB = (int32_t)((int64_t)sx1 << 16);
    zB = (int32_t)((int64_t)sz1 << 16);

    for (int y = sy1; y < sy2; y++) {
        if (y >= v_min_y && y < v_max_y) {
            int xl = (int)(xA >> 16);
            int xr = (int)(xB >> 16);
            int32_t zl = zA, zr = zB;

            if (xl > xr) {
                int tx = xl; xl = xr; xr = tx;
                int32_t tz = zl; zl = zr; zr = tz;
            }

            int span_w = xr - xl;
            if (span_w > 0) {
                int32_t dz_dx = (int32_t)(((int64_t)(zr - zl)) / span_w);
                int x_start = (xl < v_min_x) ? v_min_x : xl;
                int x_end   = (xr > v_max_x) ? v_max_x : xr;

                if (x_start < x_end) {
                    int32_t cur_z = zl + (int32_t)((int64_t)dz_dx * (x_start - xl));
                    uint32_t *dst_pixel = target_buffer ? (target_buffer + y * pitch + x_start) : NULL;
                    uint16_t *dst_z = (zb && zb->buffer) ? (zb->buffer + (y - viewport_y) * zb->width + (x_start - viewport_x)) : NULL;

                    for (int px = x_start; px < x_end; px++) {
                        uint16_t z16 = (uint16_t)(cur_z >> 16);
                        if (!dst_z || z16 < *dst_z) {
                            if (dst_z) *dst_z = z16;
                            if (dst_pixel) *dst_pixel = shaded_color;
                        }
                        cur_z += dz_dx;
                        if (dst_pixel) dst_pixel++;
                        if (dst_z) dst_z++;
                    }
                }
            }
        }
        xA += dx02;
        zA += dz02;
        xB += dx12;
        zB += dz12;
    }
}

// ---------------------------------------------------------------------------
// Solid Z-Buffered Cube Mesh Rendering
// ---------------------------------------------------------------------------

void mesh3d_render_solid_zbuffered(const mesh3d_cube_t *cube, const mat4_t *mvp,
                                   int vp_x, int vp_y, int vp_w, int vp_h,
                                   zbuffer_t *zb, uint32_t *target_buffer, uint32_t pitch,
                                   uint32_t base_color, vec3_t light_dir)
{
    if (!cube || !mvp || vp_w <= 0 || vp_h <= 0) return;

    float half_w = (float)vp_w * 0.5f;
    float half_h = (float)vp_h * 0.5f;
    vec3_t light = vec3_normalize(light_dir);

    for (int i = 0; i < cube->num_triangles; i++) {
        int i0 = cube->triangles[i].v[0];
        int i1 = cube->triangles[i].v[1];
        int i2 = cube->triangles[i].v[2];

        // 1. Transform vertices to clip space
        clip_vertex_t in_v[3];
        vec4_t v0 = {cube->vertices[i0].x, cube->vertices[i0].y, cube->vertices[i0].z, 1.0f};
        vec4_t v1 = {cube->vertices[i1].x, cube->vertices[i1].y, cube->vertices[i1].z, 1.0f};
        vec4_t v2 = {cube->vertices[i2].x, cube->vertices[i2].y, cube->vertices[i2].z, 1.0f};
        mat4_mul_vec4(&in_v[0].pos, mvp, &v0);
        mat4_mul_vec4(&in_v[1].pos, mvp, &v1);
        mat4_mul_vec4(&in_v[2].pos, mvp, &v2);

        // 2. Compute Normal in Model Space
        vec3_t e1 = vec3_sub(cube->vertices[i1], cube->vertices[i0]);
        vec3_t e2 = vec3_sub(cube->vertices[i2], cube->vertices[i0]);
        vec3_t norm = vec3_normalize(vec3_cross(e1, e2));
        in_v[0].normal = in_v[1].normal = in_v[2].normal = norm;

        // 3. Clip triangle against near plane (w >= 0.2f)
        clip_vertex_t clipped_tris[2][3];
        int num_clipped = clip_triangle_near_plane(in_v, 0.2f, clipped_tris);

        for (int t = 0; t < num_clipped; t++) {
            // Project vertices to screen space
            int sx[3], sy[3];
            uint16_t depth[3];

            for (int k = 0; k < 3; k++) {
                float inv_w = 1.0f / clipped_tris[t][k].pos.w;
                float ndc_x = clipped_tris[t][k].pos.x * inv_w;
                float ndc_y = clipped_tris[t][k].pos.y * inv_w;
                float ndc_z = clipped_tris[t][k].pos.z * inv_w;

                sx[k] = vp_x + (int)((ndc_x + 1.0f) * half_w);
                sy[k] = vp_y + (int)((1.0f - ndc_y) * half_h);

                float z_clamped = (ndc_z < -1.0f) ? -1.0f : (ndc_z > 1.0f ? 1.0f : ndc_z);
                depth[k] = (uint16_t)((z_clamped + 1.0f) * 32767.0f);
            }

            // Screen-space CCW Backface Culling
            int cross = (sx[1] - sx[0]) * (sy[0] - sy[2]) - (sy[1] - sy[0]) * (sx[0] - sx[2]);
            if (cross <= 0) continue; // Culled!

            // Diffuse Lambertian Lighting with World-Transformed Normal
            vec4_t n_in = {norm.x, norm.y, norm.z, 0.0f};
            vec4_t n_out;
            mat4_mul_vec4(&n_out, mvp, &n_in);
            vec3_t n_world = vec3_normalize((vec3_t){n_out.x, n_out.y, n_out.z});

            float dot = vec3_dot(n_world, light);
            if (dot < 0.22f) dot = 0.22f; // Ambient term

            uint32_t r = (uint32_t)(((base_color >> 16) & 0xFF) * dot);
            uint32_t g = (uint32_t)(((base_color >> 8) & 0xFF) * dot);
            uint32_t b = (uint32_t)((base_color & 0xFF) * dot);
            if (r > 255) r = 255;
            if (g > 255) g = 255;
            if (b > 255) b = 255;
            uint32_t shaded_color = 0xFF000000 | (r << 16) | (g << 8) | b;

            rasterize_triangle_scanline(
                sx[0], sy[0], depth[0],
                sx[1], sy[1], depth[1],
                sx[2], sy[2], depth[2],
                shaded_color,
                vp_x, vp_y, vp_w, vp_h,
                zb, target_buffer, pitch);

            // Subtle dark facet edge highlight
            gfx_draw_triangle_wire(sx[0], sy[0], sx[1], sy[1], sx[2], sy[2], 0xFF14171A);
        }
    }
}


