#include "physics3d.h"
#include "../math/math3d.h"

void physics3d_init(rigid_body_t *body, float size) {
    if (!body) return;
    body->size = size;
    body->mass = 1.0f;
    body->restitution = 0.74f;
    body->friction = 0.94f;
    physics3d_reset(body);
}

void physics3d_reset(rigid_body_t *body) {
    if (!body) return;
    body->pos = (vec3_t){0.0f, 1.8f, 0.0f}; // Drop from top
    body->vel = (vec3_t){0.6f, 0.0f, 0.2f};
    body->accel = (vec3_t){0.0f, -9.8f, 0.0f}; // Gravity
    body->rot = (vec3_t){15.0f, 25.0f, 10.0f};
    body->ang_vel = (vec3_t){45.0f, 60.0f, 30.0f};
    body->settle_ticks = 0;
    body->collision_count = 0;
}

void physics3d_step(rigid_body_t *body, float dt) {
    if (!body) return;
    if (dt <= 0.0f || dt > 0.1f) dt = 0.016f; // ~60 FPS time step

    // Symplectic Euler Integration
    body->vel.x += body->accel.x * dt;
    body->vel.y += body->accel.y * dt;
    body->vel.z += body->accel.z * dt;

    body->pos.x += body->vel.x * dt;
    body->pos.y += body->vel.y * dt;
    body->pos.z += body->vel.z * dt;

    body->rot.x += body->ang_vel.x * dt;
    body->rot.y += body->ang_vel.y * dt;
    body->rot.z += body->ang_vel.z * dt;

    // Wrap angles 0..360
    while (body->rot.x >= 360.0f) body->rot.x -= 360.0f;
    while (body->rot.x < 0.0f)    body->rot.x += 360.0f;
    while (body->rot.y >= 360.0f) body->rot.y -= 360.0f;
    while (body->rot.y < 0.0f)    body->rot.y += 360.0f;
    while (body->rot.z >= 360.0f) body->rot.z -= 360.0f;
    while (body->rot.z < 0.0f)    body->rot.z += 360.0f;

    // Viewport box boundaries in normalized 3D space
    float floor_y = -1.6f;
    float wall_x  = 2.1f;
    float wall_z  = 1.5f;

    // Check collision against floor
    float h = body->size * 0.5f;
    // Approximate lowest point of bounding sphere/box
    if (body->pos.y - h <= floor_y) {
        body->pos.y = floor_y + h;
        if (body->vel.y < 0.0f) {
            body->vel.y = -body->vel.y * body->restitution;
            body->vel.x *= body->friction;
            body->vel.z *= body->friction;

            // Torque impulse on bounce
            body->ang_vel.x += (body->vel.z * 15.0f);
            body->ang_vel.z -= (body->vel.x * 15.0f);
            body->collision_count++;

            // Settle check
            if (body->vel.y < 0.35f && body->vel.y > -0.35f) {
                body->vel.y = 0.0f;
                body->settle_ticks++;
            }
        }
    }

    // Left/Right Wall bounce
    if (body->pos.x + h >= wall_x) {
        body->pos.x = wall_x - h;
        body->vel.x = -body->vel.x * body->restitution;
        body->collision_count++;
    } else if (body->pos.x - h <= -wall_x) {
        body->pos.x = -wall_x + h;
        body->vel.x = -body->vel.x * body->restitution;
        body->collision_count++;
    }

    // Front/Back Wall bounce
    if (body->pos.z + h >= wall_z) {
        body->pos.z = wall_z - h;
        body->vel.z = -body->vel.z * body->restitution;
        body->collision_count++;
    } else if (body->pos.z - h <= -wall_z) {
        body->pos.z = -wall_z + h;
        body->vel.z = -body->vel.z * body->restitution;
        body->collision_count++;
    }

    // Keep the physics active and tumbling continuously:
    // If settled for ~1.5s, launch again with a jump and new spin!
    if (body->settle_ticks > 90) {
        body->vel = (vec3_t){((body->collision_count % 3) == 0) ? 1.2f : -1.2f,
                             5.8f,
                             ((body->collision_count % 2) == 0) ? 0.8f : -0.8f};
        body->ang_vel = (vec3_t){70.0f, 95.0f, 40.0f};
        body->settle_ticks = 0;
    }
}

void physics3d_get_transform(const rigid_body_t *body, mat4_t *out_model) {
    if (!body || !out_model) return;
    mat4_t rx, ry, rz, trans, rot_tmp1, rot_tmp2;
    mat4_rotate_x(&rx, body->rot.x);
    mat4_rotate_y(&ry, body->rot.y);
    mat4_rotate_z(&rz, body->rot.z);
    mat4_mul(&rot_tmp1, &ry, &rx);
    mat4_mul(&rot_tmp2, &rz, &rot_tmp1);

    mat4_translate(&trans, body->pos.x, body->pos.y, body->pos.z);
    mat4_mul(out_model, &trans, &rot_tmp2);
}
