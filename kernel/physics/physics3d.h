#ifndef NEO_PHYSICS3D_H
#define NEO_PHYSICS3D_H

#include <uefi.h>
#include "../math/math3d.h"

typedef struct {
    vec3_t  pos;             // Position (X, Y, Z)
    vec3_t  vel;             // Linear velocity (dx, dy, dz)
    vec3_t  accel;           // Acceleration (gravity)
    vec3_t  rot;             // Rotation angles (degrees)
    vec3_t  ang_vel;         // Angular velocity (deg/s)
    float   size;            // Cube side length
    float   mass;            // Mass
    float   restitution;     // Bounciness (0.0 to 1.0)
    float   friction;        // Surface friction
    int     settle_ticks;    // Settle tracker
    uint64_t collision_count;
} rigid_body_t;

void physics3d_init(rigid_body_t *body, float size);
void physics3d_reset(rigid_body_t *body);
void physics3d_step(rigid_body_t *body, float dt);
void physics3d_get_transform(const rigid_body_t *body, mat4_t *out_model);

#endif // NEO_PHYSICS3D_H
