#include "gears3d.h"
#include "holygl.h"
#include "raster_tile.h"
#include "../../drivers/gpu/gfx_backend.h"
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
    (void)zb; (void)wireframe;
    if (!gear || !view_proj || viewport_w <= 0 || viewport_h <= 0) return;

    glViewport(viewport_x, viewport_y, viewport_w, viewport_h);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    mat4_t *proj_top = &g_holygl.projection_stack[g_holygl.projection_depth];
    *proj_top = *view_proj;

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glPushMatrix();
    glTranslatef(gear->pos.x, gear->pos.y, gear->pos.z);
    glRotatef(gear->angle, 0.0f, 0.0f, 1.0f);

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glEnable(GL_LIGHTING);

    glBegin(GL_TRIANGLES);
    for (int i = 0; i < gear->num_triangles; i++) {
        const gear_tri_t *tri = &gear->triangles[i];
        glNormal3f(tri->normal.x, tri->normal.y, tri->normal.z);
        glColor3ub((tri->color >> 16) & 0xFF, (tri->color >> 8) & 0xFF, tri->color & 0xFF);

        const vec3_t *p0 = &gear->vertices[tri->v[0]].pos;
        const vec3_t *p1 = &gear->vertices[tri->v[1]].pos;
        const vec3_t *p2 = &gear->vertices[tri->v[2]].pos;

        glVertex3f(p0->x, p0->y, p0->z);
        glVertex3f(p1->x, p1->y, p1->z);
        glVertex3f(p2->x, p2->y, p2->z);
    }
    glEnd();
    glPopMatrix();
}

