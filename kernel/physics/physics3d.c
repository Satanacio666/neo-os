#include "physics3d.h"
#include "../math/math3d.h"

static inline double physics_sqrt(double x) {
    if (x <= 0.0) return 0.0;
    double res;
    asm volatile("fsqrt %d0, %d1" : "=w"(res) : "w"(x));
    return res;
}

physics_world_t g_physics_world = {0};

void physics3d_init(rigid_body_t *body, float size) {
    if (!body) return;
    memset(body, 0, sizeof(rigid_body_t));
    body->size = (double)size;
    body->mass = 1.0;
    body->inv_mass = 1.0;
    body->restitution = 0.76;
    body->friction = 0.92;
    body->color = 0xFF00FFCC; // Cyan default
    physics3d_reset(body);
}

void physics3d_reset(rigid_body_t *body) {
    if (!body) return;
    body->pos[0] = 0.0;
    body->pos[1] = 1.8;
    body->pos[2] = 0.0;

    body->vel[0] = 0.6;
    body->vel[1] = 0.0;
    body->vel[2] = 0.2;

    body->accel[0] = 0.0;
    body->accel[1] = -9.8; // Gravity
    body->accel[2] = 0.0;

    body->rot[0] = 15.0;
    body->rot[1] = 25.0;
    body->rot[2] = 10.0;

    body->ang_vel[0] = 45.0;
    body->ang_vel[1] = 60.0;
    body->ang_vel[2] = 30.0;

    body->settle_ticks = 0;
    body->collision_count = 0;
}

void physics3d_step(rigid_body_t *body, float dt_f) {
    if (!body) return;
    double dt = (double)dt_f;
    if (dt <= 0.0 || dt > 0.1) dt = 0.016667;

    // 1. Symplectic Euler Integration (Velocity then Position)
    body->vel[0] += body->accel[0] * dt;
    body->vel[1] += body->accel[1] * dt;
    body->vel[2] += body->accel[2] * dt;

    body->pos[0] += body->vel[0] * dt;
    body->pos[1] += body->vel[1] * dt;
    body->pos[2] += body->vel[2] * dt;

    body->rot[0] += body->ang_vel[0] * dt;
    body->rot[1] += body->ang_vel[1] * dt;
    body->rot[2] += body->ang_vel[2] * dt;

    // Wrap Euler angles 0..360
    for (int i = 0; i < 3; i++) {
        while (body->rot[i] >= 360.0) body->rot[i] -= 360.0;
        while (body->rot[i] < 0.0)    body->rot[i] += 360.0;
    }

    // 2. Arena Boundary Planes
    double floor_y = -1.6;
    double ceil_y  =  2.4;
    double wall_x  =  2.2;
    double wall_z  =  1.8;
    double h = body->size * 0.5;

    // Floor collision
    if (body->pos[1] - h <= floor_y) {
        body->pos[1] = floor_y + h;
        if (body->vel[1] < 0.0) {
            body->vel[1] = -body->vel[1] * body->restitution;
            body->vel[0] *= body->friction;
            body->vel[2] *= body->friction;
            body->ang_vel[0] += body->vel[2] * 12.0;
            body->ang_vel[2] -= body->vel[0] * 12.0;
            body->collision_count++;

            if (body->vel[1] < 0.35 && body->vel[1] > -0.35) {
                body->vel[1] = 0.0;
                body->settle_ticks++;
            }
        }
    }

    // Ceiling collision
    if (body->pos[1] + h >= ceil_y) {
        body->pos[1] = ceil_y - h;
        if (body->vel[1] > 0.0) {
            body->vel[1] = -body->vel[1] * body->restitution;
            body->collision_count++;
        }
    }

    // X-wall collisions
    if (body->pos[0] + h >= wall_x) {
        body->pos[0] = wall_x - h;
        body->vel[0] = -body->vel[0] * body->restitution;
        body->collision_count++;
    } else if (body->pos[0] - h <= -wall_x) {
        body->pos[0] = -wall_x + h;
        body->vel[0] = -body->vel[0] * body->restitution;
        body->collision_count++;
    }

    // Z-wall collisions
    if (body->pos[2] + h >= wall_z) {
        body->pos[2] = wall_z - h;
        body->vel[2] = -body->vel[2] * body->restitution;
        body->collision_count++;
    } else if (body->pos[2] - h <= -wall_z) {
        body->pos[2] = -wall_z + h;
        body->vel[2] = -body->vel[2] * body->restitution;
        body->collision_count++;
    }

    // Auto-relaunch when settled
    if (body->settle_ticks > 90) {
        body->vel[0] = ((body->collision_count % 3) == 0) ? 1.4 : -1.4;
        body->vel[1] = 5.6;
        body->vel[2] = ((body->collision_count % 2) == 0) ? 0.9 : -0.9;
        body->ang_vel[0] = 75.0;
        body->ang_vel[1] = 90.0;
        body->ang_vel[2] = 45.0;
        body->settle_ticks = 0;
    }
}

void physics3d_get_transform(const rigid_body_t *body, mat4_t *out_model) {
    if (!body || !out_model) return;
    mat4_t rx, ry, rz, trans, rot_tmp1, rot_tmp2;
    mat4_rotate_x(&rx, (float)body->rot[0]);
    mat4_rotate_y(&ry, (float)body->rot[1]);
    mat4_rotate_z(&rz, (float)body->rot[2]);
    mat4_mul(&rot_tmp1, &ry, &rx);
    mat4_mul(&rot_tmp2, &rz, &rot_tmp1);

    mat4_translate(&trans, (float)body->pos[0], (float)body->pos[1], (float)body->pos[2]);
    mat4_mul(out_model, &trans, &rot_tmp2);
}

// ─── Multi-Body World Simulation ──────────────────────────────────────────────

void physics3d_world_init(void) {
    memset(&g_physics_world, 0, sizeof(physics_world_t));
    g_physics_world.num_bodies = MAX_PHYSICS_BODIES;
    g_physics_world.gravity = -9.8;

    uint32_t colors[4] = {
        0xFF00E5FF, // Cyan
        0xFFFFD700, // Gold
        0xFFFF007F, // Magenta / Neon Rose
        0xFF00FF7F  // Emerald Spring Green
    };

    double initial_x[4] = {-1.0,  0.8, -0.6,  0.9};
    double initial_y[4] = { 1.8,  1.2,  2.2,  1.5};
    double initial_z[4] = {-0.4,  0.5,  0.2, -0.6};

    for (int i = 0; i < MAX_PHYSICS_BODIES; i++) {
        rigid_body_t *b = &g_physics_world.bodies[i];
        physics3d_init(b, 0.7f);
        b->pos[0] = initial_x[i];
        b->pos[1] = initial_y[i];
        b->pos[2] = initial_z[i];
        b->vel[0] = (i % 2 == 0) ? 0.8 : -0.7;
        b->vel[1] = 0.5;
        b->vel[2] = (i >= 2) ? 0.6 : -0.5;
        b->color = colors[i];
    }
}

void physics3d_world_reset(void) {
    physics3d_world_init();
}

void physics3d_world_step(float dt_f) {
    double dt = (double)dt_f;
    if (dt <= 0.0 || dt > 0.1) dt = 0.016667;

    // 1. Step individual bodies
    for (int i = 0; i < g_physics_world.num_bodies; i++) {
        physics3d_step(&g_physics_world.bodies[i], (float)dt);
    }

    // 2. Inter-Body Elastic Collision Detection & Impulse Resolution
    for (int i = 0; i < g_physics_world.num_bodies; i++) {
        for (int j = i + 1; j < g_physics_world.num_bodies; j++) {
            rigid_body_t *A = &g_physics_world.bodies[i];
            rigid_body_t *B = &g_physics_world.bodies[j];

            double dx = B->pos[0] - A->pos[0];
            double dy = B->pos[1] - A->pos[1];
            double dz = B->pos[2] - A->pos[2];
            double dist_sq = dx*dx + dy*dy + dz*dz;
            double min_dist = (A->size + B->size) * 0.5;

            if (dist_sq < min_dist * min_dist && dist_sq > 0.000001) {
                double dist = physics_sqrt(dist_sq);
                double nx = dx / dist;
                double ny = dy / dist;
                double nz = dz / dist;

                // Relative velocity
                double rvx = B->vel[0] - A->vel[0];
                double rvy = B->vel[1] - A->vel[1];
                double rvz = B->vel[2] - A->vel[2];

                double vel_along_norm = rvx * nx + rvy * ny + rvz * nz;
                if (vel_along_norm < 0.0) { // Moving toward each other
                    double e = (A->restitution + B->restitution) * 0.5;
                    double impulse_mag = -(1.0 + e) * vel_along_norm / (A->inv_mass + B->inv_mass);

                    // Apply linear impulse
                    A->vel[0] -= impulse_mag * A->inv_mass * nx;
                    A->vel[1] -= impulse_mag * A->inv_mass * ny;
                    A->vel[2] -= impulse_mag * A->inv_mass * nz;

                    B->vel[0] += impulse_mag * B->inv_mass * nx;
                    B->vel[1] += impulse_mag * B->inv_mass * ny;
                    B->vel[2] += impulse_mag * B->inv_mass * nz;

                    // Rotational spin transfer
                    A->ang_vel[0] += ny * 20.0;
                    A->ang_vel[2] -= nx * 20.0;
                    B->ang_vel[0] -= ny * 20.0;
                    B->ang_vel[2] += nx * 20.0;

                    g_physics_world.total_collisions++;
                }

                // Positional separation to prevent sinking/sticking
                double overlap = min_dist - dist;
                A->pos[0] -= nx * overlap * 0.5;
                A->pos[1] -= ny * overlap * 0.5;
                A->pos[2] -= nz * overlap * 0.5;
                B->pos[0] += nx * overlap * 0.5;
                B->pos[1] += ny * overlap * 0.5;
                B->pos[2] += nz * overlap * 0.5;
            }
        }
    }

    // 3. Compute Total System Mechanical Energy (Kinetic + Potential)
    double total_ke = 0.0;
    double total_pe = 0.0;
    for (int i = 0; i < g_physics_world.num_bodies; i++) {
        rigid_body_t *b = &g_physics_world.bodies[i];
        double v_sq = b->vel[0]*b->vel[0] + b->vel[1]*b->vel[1] + b->vel[2]*b->vel[2];
        total_ke += 0.5 * b->mass * v_sq;
        // Potential energy relative to floor at -1.6
        double height = b->pos[1] - (-1.6);
        if (height < 0.0) height = 0.0;
        total_pe += b->mass * 9.8 * height;
    }
    g_physics_world.total_energy = total_ke + total_pe;
}

void physics3d_world_explode(void) {
    for (int i = 0; i < g_physics_world.num_bodies; i++) {
        rigid_body_t *b = &g_physics_world.bodies[i];
        b->vel[0] = ((i % 2 == 0) ? 1.0 : -1.0) * (1.5 + (i * 0.4));
        b->vel[1] = 6.2 + (i * 0.5); // Big upward pop
        b->vel[2] = ((i >= 2) ? 1.0 : -1.0) * (1.2 + (i * 0.3));
        b->ang_vel[0] = (i * 35.0) + 40.0;
        b->ang_vel[1] = (i * 45.0) + 60.0;
        b->ang_vel[2] = (i * 25.0) + 30.0;
        b->settle_ticks = 0;
    }
}

void physics3d_world_apply_impulse(int id, double fx, double fy, double fz) {
    if (id < 0 || id >= g_physics_world.num_bodies) {
        physics3d_world_explode();
        return;
    }
    rigid_body_t *b = &g_physics_world.bodies[id];
    b->vel[0] += fx;
    b->vel[1] += fy;
    b->vel[2] += fz;
    b->settle_ticks = 0;
}
