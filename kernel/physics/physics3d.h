#ifndef NEO_PHYSICS3D_H
#define NEO_PHYSICS3D_H

#include <uefi.h>
#include "../math/math3d.h"

#define MAX_PHYSICS_BODIES 4

typedef struct {
    double   pos[3];          // Position (X, Y, Z) in 64-bit precision
    double   vel[3];          // Linear velocity (dx, dy, dz)
    double   accel[3];        // Acceleration (gravity)
    double   rot[3];          // Rotation angles (degrees)
    double   ang_vel[3];      // Angular velocity (deg/s)
    double   size;            // Cube side length
    double   mass;            // Mass
    double   inv_mass;        // 1.0 / Mass
    double   restitution;     // Bounciness (0.0 to 1.0)
    double   friction;        // Surface friction
    uint32_t color;           // Rendering color
    int      settle_ticks;    // Settle tracker
    uint64_t collision_count;
} rigid_body_t;

typedef struct {
    rigid_body_t bodies[MAX_PHYSICS_BODIES];
    int          num_bodies;
    double       gravity;
    double       total_energy; // Kinetic + Potential energy
    uint64_t     total_collisions;
} physics_world_t;

extern physics_world_t g_physics_world;

void physics3d_init(rigid_body_t *body, float size);
void physics3d_reset(rigid_body_t *body);
void physics3d_step(rigid_body_t *body, float dt);
void physics3d_get_transform(const rigid_body_t *body, mat4_t *out_model);

void physics3d_world_init(void);
void physics3d_world_reset(void);
void physics3d_world_step(float dt);
void physics3d_world_explode(void);
void physics3d_world_apply_impulse(int id, double fx, double fy, double fz);

#endif // NEO_PHYSICS3D_H
