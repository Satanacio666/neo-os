#ifndef NEO_GEARS3D_H
#define NEO_GEARS3D_H

#include <uefi.h>
#include "math3d.h"

#define MAX_GEAR_VERTS 600
#define MAX_GEAR_TRIS  800

typedef struct {
    vec3_t pos;      // Local 3D vertex position
    vec3_t normal;   // Vertex / face normal
} gear_vertex_t;

typedef struct {
    int      v[3];     // Indices into vertex array
    vec3_t   normal;   // Triangle normal
    uint32_t color;    // Shaded color
} gear_tri_t;

typedef struct {
    gear_vertex_t vertices[MAX_GEAR_VERTS];
    gear_tri_t    triangles[MAX_GEAR_TRIS];
    int           num_vertices;
    int           num_triangles;
    
    // Physical attributes (Classic GLXGears parameters)
    float         inner_radius;
    float         outer_radius;
    float         width;
    int           teeth;
    float         tooth_depth;
    uint32_t      base_color;
    
    // Scene position & angle
    vec3_t        pos;
    float         angle;
    float         speed_ratio;
    float         angle_offset;
} gear_mesh_t;

// Procedural 3D Gear Generator
int gear_generate(gear_mesh_t *gear,
                  float inner_radius, float outer_radius, float width,
                  int teeth, float tooth_depth, uint32_t base_color);

// Gear Scene Renderer with Z-Buffer, Backface Culling, and Directional Lighting
void gear_render(const gear_mesh_t *gear, const mat4_t *view_proj,
                 int viewport_x, int viewport_y, int viewport_w, int viewport_h,
                 zbuffer_t *zb, int wireframe);

#endif // NEO_GEARS3D_H
