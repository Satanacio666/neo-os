#include "gears3d.h"
#include "../../gui/render.h"
#include "../mem/kheap.h"
#include <uefi.h>

#define PI 3.14159265358979323846f

static int add_vertex(gear_mesh_t *g, float x, float y, float z, float nx, float ny, float nz) {
    if (g->num_vertices >= MAX_GEAR_VERTS) return g->num_vertices - 1;
    int idx = g->num_vertices++;
    g->vertices[idx].pos = (vec3_t){x, y, z};
    g->vertices[idx].normal = (vec3_t){nx, ny, nz};
    return idx;
}

static void add_triangle(gear_mesh_t *g, int v0, int v1, int v2, vec3_t normal, uint32_t color) {
    if (g->num_triangles >= MAX_GEAR_TRIS) return;
    int idx = g->num_triangles++;
    g->triangles[idx].v[0] = v0;
    g->triangles[idx].v[1] = v1;
    g->triangles[idx].v[2] = v2;
    g->triangles[idx].normal = normal;
    g->triangles[idx].color = color;
}

static void add_quad(gear_mesh_t *g, int v0, int v1, int v2, int v3, vec3_t normal, uint32_t color) {
    add_triangle(g, v0, v1, v2, normal, color);
    add_triangle(g, v0, v2, v3, normal, color);
}

int gear_generate(gear_mesh_t *gear,
                  float inner_radius, float outer_radius, float width,
                  int teeth, float tooth_depth, uint32_t base_color) {
    if (!gear || teeth <= 0) return 0;

    memset(gear, 0, sizeof(gear_mesh_t));
    gear->inner_radius = inner_radius;
    gear->outer_radius = outer_radius;
    gear->width = width;
    gear->teeth = teeth;
    gear->tooth_depth = tooth_depth;
    gear->base_color = base_color;

    float r0 = inner_radius;
    float r1 = outer_radius - tooth_depth * 0.5f;
    float r2 = outer_radius + tooth_depth * 0.5f;
    float z1 = width * 0.5f;
    float z2 = -width * 0.5f;

    float da = 360.0f / (teeth * 4.0f);
    vec3_t fnorm = {0.0f, 0.0f, 1.0f};
    vec3_t bnorm = {0.0f, 0.0f, -1.0f};

    for (int i = 0; i < teeth; i++) {
        float a0 = (float)i * (360.0f / (float)teeth);
        float a1 = a0 + da;
        float a2 = a0 + 2.0f * da;
        float a3 = a0 + 3.0f * da;
        float a4 = a0 + 4.0f * da;

        // Front Face Vertices (z = z1)
        int vf_in0 = add_vertex(gear, r0 * math3d_cos(a0), r0 * math3d_sin(a0), z1, 0, 0, 1);
        int vf_in4 = add_vertex(gear, r0 * math3d_cos(a4), r0 * math3d_sin(a4), z1, 0, 0, 1);
        int vf_b0  = add_vertex(gear, r1 * math3d_cos(a0), r1 * math3d_sin(a0), z1, 0, 0, 1);
        int vf_b3  = add_vertex(gear, r1 * math3d_cos(a3), r1 * math3d_sin(a3), z1, 0, 0, 1);
        int vf_b4  = add_vertex(gear, r1 * math3d_cos(a4), r1 * math3d_sin(a4), z1, 0, 0, 1);
        int vf_t1  = add_vertex(gear, r2 * math3d_cos(a1), r2 * math3d_sin(a1), z1, 0, 0, 1);
        int vf_t2  = add_vertex(gear, r2 * math3d_cos(a2), r2 * math3d_sin(a2), z1, 0, 0, 1);

        // Front annular body (CCW)
        add_triangle(gear, vf_in0, vf_b0, vf_b4, fnorm, base_color);
        add_triangle(gear, vf_in0, vf_b4, vf_in4, fnorm, base_color);
        // Front tooth body (CCW)
        add_triangle(gear, vf_b0, vf_t1, vf_t2, fnorm, base_color);
        add_triangle(gear, vf_b0, vf_t2, vf_b3, fnorm, base_color);
        add_triangle(gear, vf_b0, vf_b3, vf_b4, fnorm, base_color);

        // Back Face Vertices (z = z2)
        int vb_in0 = add_vertex(gear, r0 * math3d_cos(a0), r0 * math3d_sin(a0), z2, 0, 0, -1);
        int vb_in4 = add_vertex(gear, r0 * math3d_cos(a4), r0 * math3d_sin(a4), z2, 0, 0, -1);
        int vb_b0  = add_vertex(gear, r1 * math3d_cos(a0), r1 * math3d_sin(a0), z2, 0, 0, -1);
        int vb_b3  = add_vertex(gear, r1 * math3d_cos(a3), r1 * math3d_sin(a3), z2, 0, 0, -1);
        int vb_b4  = add_vertex(gear, r1 * math3d_cos(a4), r1 * math3d_sin(a4), z2, 0, 0, -1);
        int vb_t1  = add_vertex(gear, r2 * math3d_cos(a1), r2 * math3d_sin(a1), z2, 0, 0, -1);
        int vb_t2  = add_vertex(gear, r2 * math3d_cos(a2), r2 * math3d_sin(a2), z2, 0, 0, -1);

        // Back annular body (CCW from outside)
        add_triangle(gear, vb_in0, vb_b4, vb_b0, bnorm, base_color);
        add_triangle(gear, vb_in0, vb_in4, vb_b4, bnorm, base_color);
        // Back tooth body (CCW from outside)
        add_triangle(gear, vb_b0, vb_t2, vb_t1, bnorm, base_color);
        add_triangle(gear, vb_b0, vb_b3, vb_t2, bnorm, base_color);
        add_triangle(gear, vb_b0, vb_b4, vb_b3, bnorm, base_color);

        // Outward Flank 1: slope up (b0 -> t1)
        float dx1 = r2 * math3d_cos(a1) - r1 * math3d_cos(a0);
        float dy1 = r2 * math3d_sin(a1) - r1 * math3d_sin(a0);
        vec3_t n_slope1 = vec3_normalize((vec3_t){dy1, -dx1, 0.0f});
        // CCW outward quad: vf_b0 -> vb_b0 -> vb_t1 -> vf_t1
        add_quad(gear, vf_b0, vb_b0, vb_t1, vf_t1, n_slope1, base_color);

        // Outward Flank 2: tooth crest (t1 -> t2)
        vec3_t n_crest = {math3d_cos(a1 + 0.5f * da), math3d_sin(a1 + 0.5f * da), 0.0f};
        // CCW outward quad: vf_t1 -> vb_t1 -> vb_t2 -> vf_t2
        add_quad(gear, vf_t1, vb_t1, vb_t2, vf_t2, n_crest, base_color);

        // Outward Flank 3: slope down (t2 -> b3)
        float dx2 = r1 * math3d_cos(a3) - r2 * math3d_cos(a2);
        float dy2 = r1 * math3d_sin(a3) - r2 * math3d_sin(a2);
        vec3_t n_slope2 = vec3_normalize((vec3_t){dy2, -dx2, 0.0f});
        // CCW outward quad: vf_t2 -> vb_t2 -> vb_b3 -> vf_b3
        add_quad(gear, vf_t2, vb_t2, vb_b3, vf_b3, n_slope2, base_color);

        // Outward Flank 4: root valley (b3 -> b4)
        vec3_t n_root = {math3d_cos(a3 + 0.5f * da), math3d_sin(a3 + 0.5f * da), 0.0f};
        // CCW outward quad: vf_b3 -> vb_b3 -> vb_b4 -> vf_b4
        add_quad(gear, vf_b3, vb_b3, vb_b4, vf_b4, n_root, base_color);

        // Inner Hole Cylinder (in0 -> in4, normal points inward toward axis)
        vec3_t n_in = {-math3d_cos(a0 + 2.0f * da), -math3d_sin(a0 + 2.0f * da), 0.0f};
        // CCW when viewed from inside hole: vf_in0 -> vf_in4 -> vb_in4 -> vb_in0
        add_quad(gear, vf_in0, vf_in4, vb_in4, vb_in0, n_in, base_color);
    }

    return 1;
}

void gear_render(const gear_mesh_t *gear, const mat4_t *view_proj,
                 int viewport_x, int viewport_y, int viewport_w, int viewport_h,
                 zbuffer_t *zb, int wireframe) {
    if (!gear || !view_proj || viewport_w <= 0 || viewport_h <= 0) return;

    uint32_t *backbuffer = gfx_get_backbuffer();
    uint32_t pitch = gfx_get_canvas_pitch();

    // 1. Build Model Matrix for this gear
    mat4_t rot_z, trans, model, mvp;
    mat4_rotate_z(&rot_z, gear->angle);
    mat4_translate(&trans, gear->pos.x, gear->pos.y, gear->pos.z);
    mat4_mul(&model, &trans, &rot_z);
    mat4_mul(&mvp, view_proj, &model);

    // 2. Pre-transform all vertices to homogeneous clip space (SIMD / fast arithmetic)
    vec4_t clip_v[MAX_GEAR_VERTS];
    for (int i = 0; i < gear->num_vertices; i++) {
        vec4_t in_v = {gear->vertices[i].pos.x, gear->vertices[i].pos.y, gear->vertices[i].pos.z, 1.0f};
        mat4_mul_vec4(&clip_v[i], &mvp, &in_v);
    }

    float half_w = (float)viewport_w * 0.5f;
    float half_h = (float)viewport_h * 0.5f;

    // Directional Light Vector in World Space
    vec3_t light_dir = vec3_normalize((vec3_t){5.0f, 5.0f, 10.0f});

    // 3. Process and Render Triangles with Analytical Near-Plane Clipping
    for (int i = 0; i < gear->num_triangles; i++) {
        int i0 = gear->triangles[i].v[0];
        int i1 = gear->triangles[i].v[1];
        int i2 = gear->triangles[i].v[2];

        clip_vertex_t in_tri[3];
        in_tri[0].pos = clip_v[i0];
        in_tri[1].pos = clip_v[i1];
        in_tri[2].pos = clip_v[i2];

        // Normal computation in rotated gear coordinate space
        vec3_t n_local = gear->triangles[i].normal;
        vec3_t n_rot = {
            n_local.x * math3d_cos(gear->angle) - n_local.y * math3d_sin(gear->angle),
            n_local.x * math3d_sin(gear->angle) + n_local.y * math3d_cos(gear->angle),
            n_local.z
        };
        in_tri[0].normal = in_tri[1].normal = in_tri[2].normal = n_rot;

        // Clip triangle against near camera plane (w >= 0.5f)
        clip_vertex_t clipped_tris[2][3];
        int num_clipped = clip_triangle_near_plane(in_tri, 0.5f, clipped_tris);

        for (int t = 0; t < num_clipped; t++) {
            int sx[3], sy[3];
            uint16_t depth[3];

            for (int k = 0; k < 3; k++) {
                float inv_w = 1.0f / clipped_tris[t][k].pos.w;
                float ndc_x = clipped_tris[t][k].pos.x * inv_w;
                float ndc_y = clipped_tris[t][k].pos.y * inv_w;
                float ndc_z = clipped_tris[t][k].pos.z * inv_w;

                sx[k] = viewport_x + (int)((ndc_x + 1.0f) * half_w);
                sy[k] = viewport_y + (int)((1.0f - ndc_y) * half_h);

                float z_clamped = (ndc_z < -1.0f) ? -1.0f : (ndc_z > 1.0f ? 1.0f : ndc_z);
                depth[k] = (uint16_t)((z_clamped + 1.0f) * 32767.0f);
            }

            // Screen-space CCW Backface Culling
            int cross = (sx[1] - sx[0]) * (sy[0] - sy[2]) - (sy[1] - sy[0]) * (sx[0] - sx[2]);
            if (cross <= 0) continue; // Face is oriented away from camera

            if (wireframe) {
                gfx_draw_triangle_wire(sx[0], sy[0], sx[1], sy[1], sx[2], sy[2], gear->base_color);
                continue;
            }

            // Directional lighting
            float dot = vec3_dot(n_rot, light_dir);
            if (dot < 0.0f) dot = 0.0f;
            float intensity = 0.28f + 0.72f * dot;

            uint32_t r = (uint32_t)(((gear->base_color >> 16) & 0xFF) * intensity);
            uint32_t g_col = (uint32_t)(((gear->base_color >> 8) & 0xFF) * intensity);
            uint32_t b = (uint32_t)((gear->base_color & 0xFF) * intensity);
            if (r > 255) r = 255;
            if (g_col > 255) g_col = 255;
            if (b > 255) b = 255;
            uint32_t shaded_color = 0xFF000000 | (r << 16) | (g_col << 8) | b;

            rasterize_triangle_scanline(sx[0], sy[0], depth[0],
                                        sx[1], sy[1], depth[1],
                                        sx[2], sy[2], depth[2],
                                        shaded_color,
                                        viewport_x, viewport_y, viewport_w, viewport_h,
                                        zb, backbuffer, pitch);
        }
    }
}

