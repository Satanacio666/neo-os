#ifndef NEO_MATH3D_H
#define NEO_MATH3D_H

#include <uefi.h>

// Vector 3D
typedef struct {
    float x, y, z;
} vec3_t;

// Vector 4D (Homogeneous coordinates)
typedef struct {
    float x, y, z, w;
} vec4_t;

// Matrix 4x4 (Row-major)
typedef struct {
    float m[4][4];
} mat4_t;

// Fast Trigonometric lookup table (360 degrees)
void  math3d_init(void);
float math3d_sin(float deg);
float math3d_cos(float deg);

// Vector Operations
vec3_t vec3_add(vec3_t a, vec3_t b);
vec3_t vec3_sub(vec3_t a, vec3_t b);
vec3_t vec3_scale(vec3_t v, float s);
float  vec3_dot(vec3_t a, vec3_t b);
vec3_t vec3_cross(vec3_t a, vec3_t b);
vec3_t vec3_normalize(vec3_t v);
float  fast_rsqrt_neon(float x);
float  fast_sqrt_neon(float x);
double math3d_sin_d(double deg);
double fast_sqrt_d(double x);

// Matrix Operations (Model-View-Projection pipeline)
void mat4_identity(mat4_t *out);
void mat4_translate(mat4_t *out, float tx, float ty, float tz);
void mat4_scale(mat4_t *out, float sx, float sy, float sz);
void mat4_rotate_x(mat4_t *out, float deg);
void mat4_rotate_y(mat4_t *out, float deg);
void mat4_rotate_z(mat4_t *out, float deg);
void mat4_mul(mat4_t *out, const mat4_t *a, const mat4_t *b);
void mat4_mul_vec4(vec4_t *out, const mat4_t *m, const vec4_t *v);
void mat4_perspective(mat4_t *out, float fov_deg, float aspect, float near_z, float far_z);
void math3d_transform_vertices_parallel(const vec3_t *in, vec4_t *out, int count, const mat4_t *mvp);

// Vector 2D (UV texture coordinates)
typedef struct {
    float u, v;
} vec2_t;

// 3D Triangle structure
typedef struct {
    int      v[3];          // Indices into vertex array
    vec2_t   uv[3];         // Texture UVs
    vec3_t   normal;        // Surface normal
    float    avg_depth;     // Depth for Painter's sorting
    uint32_t color;        // Shaded surface color
} tri3d_t;

// 3D Cube Mesh structure
typedef struct {
    vec3_t  vertices[8];
    int     num_vertices;
    tri3d_t triangles[12];
    int     num_triangles;
    int     edges[12][2];
    int     num_edges;
} mesh3d_cube_t;

void mesh3d_init_cube(mesh3d_cube_t *cube, float size);

// Software Depth Buffer (16-bit Z-Buffer)
typedef struct {
    uint16_t *buffer;
    int       width;
    int       height;
} zbuffer_t;

int  zbuffer_init(zbuffer_t *zb, int w, int h);
int  zbuffer_resize(zbuffer_t *zb, int new_w, int new_h);
void zbuffer_clear(zbuffer_t *zb);
void zbuffer_free(zbuffer_t *zb);

// Vertex format for homogenous frustum clipping
typedef struct {
    vec4_t   pos;     // Homogeneous coordinates (x, y, z, w)
    vec3_t   normal;  // Vertex/face normal
    uint32_t color;   // Vertex/face color
} clip_vertex_t;

// Analytical Near-Plane Triangle Clipper (Sutherland-Hodgman)
int clip_triangle_near_plane(const clip_vertex_t in_v[3], float near_w, clip_vertex_t out_tris[2][3]);

// High-performance fixed-point scanline rasterizer with top-left fill convention
void rasterize_triangle_scanline(
    int x0, int y0, uint16_t z0,
    int x1, int y1, uint16_t z1,
    int x2, int y2, uint16_t z2,
    uint32_t shaded_color,
    int viewport_x, int viewport_y, int viewport_w, int viewport_h,
    zbuffer_t *zb, uint32_t *target_buffer, uint32_t pitch);

// Render routines (Clipped to Window Viewport)
void mesh3d_render_wireframe(const mesh3d_cube_t *cube, const mat4_t *mvp,
                             int vp_x, int vp_y, int vp_w, int vp_h,
                             uint32_t wire_color, uint32_t vert_color);

void mesh3d_render_subdivided_wireframe(const mesh3d_cube_t *cube, const mat4_t *mvp,
                                        int vp_x, int vp_y, int vp_w, int vp_h,
                                        uint32_t wire_color, int divisions);

void mesh3d_render_solid(const mesh3d_cube_t *cube, const mat4_t *mvp,
                         int vp_x, int vp_y, int vp_w, int vp_h,
                         uint32_t base_color, vec3_t light_dir);

// Full Z-Buffered Solid Cube Render (Robust Scanline Pipeline)
void mesh3d_render_solid_zbuffered(const mesh3d_cube_t *cube, const mat4_t *mvp,
                                   int vp_x, int vp_y, int vp_w, int vp_h,
                                   zbuffer_t *zb, uint32_t *target_buffer, uint32_t pitch,
                                   uint32_t base_color, vec3_t light_dir);

void mesh3d_render_textured(const mesh3d_cube_t *cube, const mat4_t *mvp,
                            int vp_x, int vp_y, int vp_w, int vp_h,
                            const uint32_t *texture, int tex_w, int tex_h);

void mesh3d_render_phong(const mesh3d_cube_t *cube, const mat4_t *mvp,
                         int vp_x, int vp_y, int vp_w, int vp_h,
                         uint32_t base_color, vec3_t light_dir, vec3_t point_light_pos, uint32_t point_color);

void texture_generate_procedural(uint32_t *buffer, int w, int h, int mode);

#endif // NEO_MATH3D_H

