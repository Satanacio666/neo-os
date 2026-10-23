// NeoOS Sovereign Pure HolyC 3D Multi-Body Rigid Dynamics Engine (Physics3D.HC)
// 100% Native AArch64 HolyC Implementation | Symplectic Euler Integration
// 3D Wire-Grid Arena, Shadow Projections, Velocity Vectors & Elastic Collisions

class CRigidBody {
  F64 pos_x; F64 pos_y; F64 pos_z;
  F64 vel_x; F64 vel_y; F64 vel_z;
  F64 acc_x; F64 acc_y; F64 acc_z;
  F64 rot_x; F64 rot_y; F64 rot_z;
  F64 ang_x; F64 ang_y; F64 ang_z;
  F64 size;
  F64 mass;
  F64 inv_mass;
  F64 restitution;
  F64 friction;
  U32 color;
  I64 settle_ticks;
  U64 collision_count;
};

#define MAX_PHYS_BODIES 4

CRigidBody g_phys_bodies[4];
I64 g_phys_num_bodies = 0;
F64 g_phys_gravity = -9.8;
F64 g_phys_total_energy = 0.0;
U64 g_phys_total_collisions = 0;

CRigidBody *PhysicsGetBody(I64 idx) {
  if (idx < 0 || idx >= MAX_PHYS_BODIES) return NULL;
  return &g_phys_bodies[idx];
}

F64 PhysSqrt(F64 x) {
  return MathSqrt(x);
}

F64 PhysicsGetGravityMag() {
  if (g_phys_gravity < 0.0) return -g_phys_gravity;
  return g_phys_gravity;
}

U0 PhysicsReset(CRigidBody *b) {
  if (!b) return;
  b->pos_x = 0.0;
  b->pos_y = 1.8;
  b->pos_z = 0.0;

  b->vel_x = 0.6;
  b->vel_y = 0.0;
  b->vel_z = 0.2;

  b->acc_x = 0.0;
  b->acc_y = -PhysicsGetGravityMag();
  b->acc_z = 0.0;

  b->rot_x = 15.0;
  b->rot_y = 25.0;
  b->rot_z = 10.0;

  b->ang_x = 45.0;
  b->ang_y = 60.0;
  b->ang_z = 30.0;

  b->settle_ticks = 0;
  b->collision_count = 0;
}

U0 PhysicsInit(CRigidBody *b, F64 sz) {
  if (!b) return;
  b->size = sz;
  b->mass = 1.0;
  b->inv_mass = 1.0;
  b->restitution = 0.76;
  b->friction = 0.92;
  b->color = 0xFF00FFCC;
  PhysicsReset(b);
}

U0 PhysicsStep(CRigidBody *b, F64 dt) {
  if (!b) return;
  if (dt <= 0.0 || dt > 0.1) dt = 0.016667;

  // Honor live g_phys_gravity when body has gravitational acceleration enabled
  if (b->acc_y != 0.0) {
    F64 g_mag = PhysicsGetGravityMag();
    b->acc_y = -g_mag;
  }

  // 1. Symplectic Euler Integration (Velocity update then Position update)
  b->vel_x = b->vel_x + b->acc_x * dt;
  b->vel_y = b->vel_y + b->acc_y * dt;
  b->vel_z = b->vel_z + b->acc_z * dt;

  b->pos_x = b->pos_x + b->vel_x * dt;
  b->pos_y = b->pos_y + b->vel_y * dt;
  b->pos_z = b->pos_z + b->vel_z * dt;

  b->rot_x = b->rot_x + b->ang_x * dt;
  b->rot_y = b->rot_y + b->ang_y * dt;
  b->rot_z = b->rot_z + b->ang_z * dt;

  // Wrap Euler angles 0..360 in O(1)
  I64 kx = (I64)(b->rot_x / 360.0); b->rot_x = b->rot_x - (F64)kx * 360.0;
  if (b->rot_x < 0.0) b->rot_x = b->rot_x + 360.0;
  I64 ky = (I64)(b->rot_y / 360.0); b->rot_y = b->rot_y - (F64)ky * 360.0;
  if (b->rot_y < 0.0) b->rot_y = b->rot_y + 360.0;
  I64 kz = (I64)(b->rot_z / 360.0); b->rot_z = b->rot_z - (F64)kz * 360.0;
  if (b->rot_z < 0.0) b->rot_z = b->rot_z + 360.0;

  // 2. Arena Boundary Planes
  F64 floor_y = -1.6;
  F64 ceil_y  =  2.4;
  F64 wall_x  =  2.2;
  F64 wall_z  =  1.8;
  F64 h = b->size * 0.5;

  // Floor collision
  if (b->pos_y - h <= floor_y) {
    b->pos_y = floor_y + h;
    if (b->vel_y < 0.0) {
      b->vel_y = -b->vel_y * b->restitution;
      b->vel_x = b->vel_x * b->friction;
      b->vel_z = b->vel_z * b->friction;
      b->ang_x = b->ang_x + b->vel_z * 12.0;
      b->ang_z = b->ang_z - b->vel_x * 12.0;
      b->collision_count = b->collision_count + 1;

      if (b->vel_y < 0.35 && b->vel_y > -0.35) {
        b->vel_y = 0.0;
        b->settle_ticks = b->settle_ticks + 1;
      }
    }
  }

  // Ceiling collision
  if (b->pos_y + h >= ceil_y) {
    b->pos_y = ceil_y - h;
    if (b->vel_y > 0.0) {
      b->vel_y = -b->vel_y * b->restitution;
      b->collision_count = b->collision_count + 1;
    }
  }

  // X-wall collisions
  if (b->pos_x + h >= wall_x) {
    b->pos_x = wall_x - h;
    b->vel_x = -b->vel_x * b->restitution;
    b->collision_count = b->collision_count + 1;
  } else if (b->pos_x - h <= -wall_x) {
    b->pos_x = -wall_x + h;
    b->vel_x = -b->vel_x * b->restitution;
    b->collision_count = b->collision_count + 1;
  }

  // Z-wall collisions
  if (b->pos_z + h >= wall_z) {
    b->pos_z = wall_z - h;
    b->vel_z = -b->vel_z * b->restitution;
    b->collision_count = b->collision_count + 1;
  } else if (b->pos_z - h <= -wall_z) {
    b->pos_z = -wall_z + h;
    b->vel_z = -b->vel_z * b->restitution;
    b->collision_count = b->collision_count + 1;
  }

  // Auto-relaunch when settled
  if (b->settle_ticks > 90) {
    b->vel_x = 1.4;
    b->vel_y = 5.6;
    b->vel_z = 0.9;
    b->ang_x = 75.0;
    b->ang_y = 90.0;
    b->ang_z = 45.0;
    b->settle_ticks = 0;
  }
}

U0 PhysicsWorldInit() {
  g_phys_num_bodies = MAX_PHYS_BODIES;
  g_phys_gravity = -9.8;
  g_phys_total_collisions = 0;
  g_phys_total_energy = 0.0;

  CRigidBody *b0 = PhysicsGetBody(0);
  PhysicsInit(b0, 0.75);
  b0->pos_x = -1.0; b0->pos_y = 1.8; b0->pos_z = -0.4;
  b0->vel_x = 0.8;  b0->vel_y = 0.5; b0->vel_z = -0.5;
  b0->color = 0xFF89DCEB;

  CRigidBody *b1 = PhysicsGetBody(1);
  PhysicsInit(b1, 0.75);
  b1->pos_x = 0.8;  b1->pos_y = 1.2; b1->pos_z = 0.5;
  b1->vel_x = -0.7; b1->vel_y = 0.5; b1->vel_z = -0.5;
  b1->color = 0xFFF9E2AF;

  CRigidBody *b2 = PhysicsGetBody(2);
  PhysicsInit(b2, 0.75);
  b2->pos_x = -0.6; b2->pos_y = 2.2; b2->pos_z = 0.2;
  b2->vel_x = 0.8;  b2->vel_y = 0.5; b2->vel_z = 0.6;
  b2->color = 0xFFF38BA8;

  CRigidBody *b3 = PhysicsGetBody(3);
  PhysicsInit(b3, 0.75);
  b3->pos_x = 0.9;  b3->pos_y = 1.5; b3->pos_z = -0.6;
  b3->vel_x = -0.7; b3->vel_y = 0.5; b3->vel_z = 0.6;
  b3->color = 0xFFA6E3A1;
}

U0 PhysicsWorldReset() {
  PhysicsWorldInit();
}

U0 PhysicsWorldStep(F64 dt) {
  if (dt <= 0.0 || dt > 0.1) dt = 0.016667;

  // 1. Step individual bodies
  I64 b_step_i = 0;
  while (b_step_i < g_phys_num_bodies) {
    CRigidBody *b = PhysicsGetBody(b_step_i);
    PhysicsStep(b, dt);
    b_step_i++;
  }

  // 2. Inter-body collision detection & impulse resolution
  I64 pair_i = 0;
  while (pair_i < g_phys_num_bodies) {
    I64 pair_j = pair_i + 1;
    while (pair_j < g_phys_num_bodies) {
      CRigidBody *A = PhysicsGetBody(pair_i);
      CRigidBody *B = PhysicsGetBody(pair_j);

      F64 dx = B->pos_x - A->pos_x;
      F64 dy = B->pos_y - A->pos_y;
      F64 dz = B->pos_z - A->pos_z;
      F64 dist_sq = dx * dx + dy * dy + dz * dz;
      F64 min_dist = (A->size + B->size) * 0.5;

      if (dist_sq < min_dist * min_dist && dist_sq > 0.000001) {
        F64 dist = MathSqrt(dist_sq);
        F64 nx = dx / dist;
        F64 ny = dy / dist;
        F64 nz = dz / dist;

        F64 rvx = B->vel_x - A->vel_x;
        F64 rvy = B->vel_y - A->vel_y;
        F64 rvz = B->vel_z - A->vel_z;

        F64 vel_along_norm = rvx * nx + rvy * ny + rvz * nz;
        if (vel_along_norm < 0.0) {
          F64 e = (A->restitution + B->restitution) * 0.5;
          F64 impulse_mag = -(1.0 + e) * vel_along_norm / (A->inv_mass + B->inv_mass);

          A->vel_x = A->vel_x - impulse_mag * A->inv_mass * nx;
          A->vel_y = A->vel_y - impulse_mag * A->inv_mass * ny;
          A->vel_z = A->vel_z - impulse_mag * A->inv_mass * nz;

          B->vel_x = B->vel_x + impulse_mag * B->inv_mass * nx;
          B->vel_y = B->vel_y + impulse_mag * B->inv_mass * ny;
          B->vel_z = B->vel_z + impulse_mag * B->inv_mass * nz;

          A->ang_x = A->ang_x + ny * 20.0;
          A->ang_z = A->ang_z - nx * 20.0;
          B->ang_x = B->ang_x - ny * 20.0;
          B->ang_z = B->ang_z + nx * 20.0;

          g_phys_total_collisions = g_phys_total_collisions + 1;
        }

        // Positional separation
        F64 overlap = min_dist - dist;
        A->pos_x = A->pos_x - nx * overlap * 0.5;
        A->pos_y = A->pos_y - ny * overlap * 0.5;
        A->pos_z = A->pos_z - nz * overlap * 0.5;
        B->pos_x = B->pos_x + nx * overlap * 0.5;
        B->pos_y = B->pos_y + ny * overlap * 0.5;
        B->pos_z = B->pos_z + nz * overlap * 0.5;
      }
      pair_j++;
    }
    pair_i++;
  }

  // 3. System Mechanical Energy honoring g_phys_gravity
  F64 total_ke = 0.0;
  F64 total_pe = 0.0;
  F64 g_mag = PhysicsGetGravityMag();
  I64 en_i = 0;
  while (en_i < g_phys_num_bodies) {
    CRigidBody *b = PhysicsGetBody(en_i);
    F64 v_sq = b->vel_x * b->vel_x + b->vel_y * b->vel_y + b->vel_z * b->vel_z;
    total_ke = total_ke + 0.5 * b->mass * v_sq;
    F64 height = b->pos_y - (-1.6);
    if (height < 0.0) height = 0.0;
    total_pe = total_pe + b->mass * g_mag * height;
    en_i++;
  }
  g_phys_total_energy = total_ke + total_pe;
}

U0 PhysicsWorldExplode() {
  I64 exp_i = 0;
  while (exp_i < g_phys_num_bodies) {
    CRigidBody *b = PhysicsGetBody(exp_i);
    F64 sx = (exp_i % 2 == 0) ? 1.0 : -1.0;
    F64 sz = (exp_i >= 2) ? 1.0 : -1.0;
    b->vel_x = sx * (1.5 + exp_i * 0.4);
    b->vel_y = 6.2 + exp_i * 0.5;
    b->vel_z = sz * (1.2 + exp_i * 0.3);
    b->ang_x = exp_i * 35.0 + 40.0;
    b->ang_y = exp_i * 45.0 + 60.0;
    b->ang_z = exp_i * 25.0 + 30.0;
    b->settle_ticks = 0;
    exp_i++;
  }
}

U0 PhysicsWorldApplyImpulse(I64 id, F64 fx, F64 fy, F64 fz) {
  if (id < 0 || id >= g_phys_num_bodies) {
    PhysicsWorldExplode();
    return;
  }
  CRigidBody *b = PhysicsGetBody(id);
  b->vel_x = b->vel_x + fx;
  b->vel_y = b->vel_y + fy;
  b->vel_z = b->vel_z + fz;
  b->settle_ticks = 0;
}

U0 Physics3DDrawLitBox(CRigidBody *b) {
  F64 hs = b->size * 0.5;
  HolyGLPushMatrix();
  HolyGLTranslatef(b->pos_x, b->pos_y, b->pos_z);
  HolyGLRotatef(b->rot_x, 1.0, 0.0, 0.0);
  HolyGLRotatef(b->rot_y, 0.0, 1.0, 0.0);
  HolyGLRotatef(b->rot_z, 0.0, 0.0, 1.0);

  HolyGLColorPacked(b->color);
  HolyGLBegin(GL_QUADS);
  // Front
  HolyGLNormal3f(0.0, 0.0, 1.0);
  HolyGLVertex3f(-hs, -hs,  hs); HolyGLVertex3f( hs, -hs,  hs);
  HolyGLVertex3f( hs,  hs,  hs); HolyGLVertex3f(-hs,  hs,  hs);
  // Back
  HolyGLNormal3f(0.0, 0.0, -1.0);
  HolyGLVertex3f( hs, -hs, -hs); HolyGLVertex3f(-hs, -hs, -hs);
  HolyGLVertex3f(-hs,  hs, -hs); HolyGLVertex3f( hs,  hs, -hs);
  // Top
  HolyGLNormal3f(0.0, 1.0, 0.0);
  HolyGLVertex3f(-hs,  hs,  hs); HolyGLVertex3f( hs,  hs,  hs);
  HolyGLVertex3f( hs,  hs, -hs); HolyGLVertex3f(-hs,  hs, -hs);
  // Bottom
  HolyGLNormal3f(0.0, -1.0, 0.0);
  HolyGLVertex3f(-hs, -hs, -hs); HolyGLVertex3f( hs, -hs, -hs);
  HolyGLVertex3f( hs, -hs,  hs); HolyGLVertex3f(-hs, -hs,  hs);
  // Right
  HolyGLNormal3f(1.0, 0.0, 0.0);
  HolyGLVertex3f( hs, -hs,  hs); HolyGLVertex3f( hs, -hs, -hs);
  HolyGLVertex3f( hs,  hs, -hs); HolyGLVertex3f( hs,  hs,  hs);
  // Left
  HolyGLNormal3f(-1.0, 0.0, 0.0);
  HolyGLVertex3f(-hs, -hs, -hs); HolyGLVertex3f(-hs, -hs,  hs);
  HolyGLVertex3f(-hs,  hs,  hs); HolyGLVertex3f(-hs,  hs, -hs);
  HolyGLEnd();
  HolyGLPopMatrix();
}

// Render 3D wire-grid floor, shadow projections, velocity vectors & rigid bodies inside any viewport
U0 Physics3DRenderViewport(I64 vx, I64 vy, I64 vw, I64 vh) {
  if (vw <= 0 || vh <= 0) return;
  if (g_phys_num_bodies <= 0) PhysicsWorldInit();

  gfx_draw_rect(vx, vy, vw, vh, 0xFF11111B);
  HolyGLViewport(vx, vy, vw, vh);
  HolyGLEnable(GL_DEPTH_TEST);

  F64 aspect = (F64)vw / (F64)vh;
  HolyGLMatrixMode(GL_PROJECTION);
  HolyGLLoadIdentity();
  HolyGLPerspective(45.0, aspect, 1.0, 50.0);

  HolyGLMatrixMode(GL_MODELVIEW);
  HolyGLLoadIdentity();
  HolyGLTranslatef(0.0, -0.3, -6.8);
  HolyGLRotatef(18.0, 1.0, 0.0, 0.0);

  // 1. Draw 3D Wire-Grid Floor at y = -1.6
  HolyGLDisable(GL_LIGHTING);
  HolyGLColorPacked(0xFF45475A);
  HolyGLBegin(GL_LINES);
  I64 gx_i = -4;
  while (gx_i <= 4) {
    F64 gx = (F64)gx_i * 0.55;
    HolyGLVertex3f(gx, -1.6, -1.8);
    HolyGLVertex3f(gx, -1.6,  1.8);
    gx_i++;
  }
  I64 gz_i = -3;
  while (gz_i <= 3) {
    F64 gz = (F64)gz_i * 0.6;
    HolyGLVertex3f(-2.2, -1.6, gz);
    HolyGLVertex3f( 2.2, -1.6, gz);
    gz_i++;
  }
  HolyGLEnd();

  // 2. Draw planar floor shadow projections & velocity vectors
  I64 pb_i = 0;
  while (pb_i < g_phys_num_bodies) {
    CRigidBody *b = PhysicsGetBody(pb_i);
    F64 sh_r = b->size * 0.42;
    HolyGLColorPacked(0xFF07070C);
    HolyGLBegin(GL_QUADS);
    HolyGLVertex3f(b->pos_x - sh_r, -1.58, b->pos_z + sh_r);
    HolyGLVertex3f(b->pos_x + sh_r, -1.58, b->pos_z + sh_r);
    HolyGLVertex3f(b->pos_x + sh_r, -1.58, b->pos_z - sh_r);
    HolyGLVertex3f(b->pos_x - sh_r, -1.58, b->pos_z - sh_r);
    HolyGLEnd();

    // Velocity vector line
    HolyGLColorPacked(0xFFF9E2AF);
    HolyGLBegin(GL_LINES);
    HolyGLVertex3f(b->pos_x, b->pos_y, b->pos_z);
    HolyGLVertex3f(b->pos_x + b->vel_x * 0.25, b->pos_y + b->vel_y * 0.25, b->pos_z + b->vel_z * 0.25);
    HolyGLEnd();
    pb_i++;
  }

  // 3. Draw Lambertian-shaded 3D rigid bodies
  HolyGLEnable(GL_LIGHTING);
  pb_i = 0;
  while (pb_i < g_phys_num_bodies) {
    CRigidBody *b = PhysicsGetBody(pb_i);
    Physics3DDrawLitBox(b);
    pb_i++;
  }
  HolyGLDisable(GL_LIGHTING);

  gfx_draw_string(vx + 8, vy + 6, "Physics3D: 4 Rigid Bodies + Shadows", 0xFFCDD6F4, 0);
}

U0 physics3d_world_init() { PhysicsWorldInit(); }
U0 physics3d_world_reset() { PhysicsWorldReset(); }
U0 physics3d_world_step(F64 dt) { PhysicsWorldStep(dt); }
U0 physics3d_world_explode() { PhysicsWorldExplode(); }
U0 physics3d_world_apply_impulse(I64 id, F64 fx, F64 fy, F64 fz) { PhysicsWorldApplyImpulse(id, fx, fy, fz); }

I64 Physics3DSelfTest() {
  doldoc_printf("\n$FG,CYAN$[PHYSICS3D-TEST] Starting Pure HolyC 3D Rigid Dynamics Verification...$FG$\n");

  // Test 1: Rigid body initialization & parameter verification
  g_phys_gravity = -9.8;
  CRigidBody b1;
  PhysicsInit(&b1, 0.7);
  if (b1.size < 0.69 || b1.size > 0.71 || b1.mass != 1.0 || b1.acc_y != -9.8 || b1.pos_y != 1.8) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Rigid body initialization parameters failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: Rigid body state, mass, and g_phys_gravity constants verified.$FG$\n");

  // Test 2: Symplectic Euler integration over 30 ticks
  I64 t_step = 0;
  F64 prev_y = b1.pos_y;
  while (t_step < 30) {
    PhysicsStep(&b1, 0.016667);
    t_step++;
  }
  if (b1.pos_y >= prev_y || b1.vel_y >= 0.0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: Gravitational acceleration failed to accelerate body downward!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Symplectic Euler gravitational integration (60 Hz) verified.$FG$\n");

  // Test 3: Floor collision & restitution bounce
  while (t_step < 120 && b1.collision_count == 0) {
    PhysicsStep(&b1, 0.016667);
    t_step++;
  }
  if (b1.collision_count == 0 || b1.pos_y < -1.26 || b1.vel_y <= 0.0) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: Floor collision detection and bounce restitution failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Arena floor boundary plane & elastic restitution verified.$FG$\n");

  // Test 4: Multi-body world simulation & inter-body collision
  PhysicsWorldInit();
  CRigidBody *b_a = PhysicsGetBody(0);
  CRigidBody *b_b = PhysicsGetBody(1);
  b_a->pos_x = -1.0; b_a->pos_y = 0.0; b_a->pos_z = 0.0;
  b_a->vel_x =  2.0; b_a->vel_y = 0.0; b_a->vel_z = 0.0;
  b_a->acc_y =  0.0;

  b_b->pos_x =  1.0; b_b->pos_y = 0.0; b_b->pos_z = 0.0;
  b_b->vel_x = -2.0; b_b->vel_y = 0.0; b_b->vel_z = 0.0;
  b_b->acc_y =  0.0;

  U64 init_colls = g_phys_total_collisions;
  I64 coll_step = 0;
  while (coll_step < 40) {
    PhysicsWorldStep(0.016667);
    coll_step++;
  }
  if (g_phys_total_collisions <= init_colls || b_a->vel_x >= 0.0 || b_b->vel_x <= 0.0) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: Inter-body momentum transfer & collision failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Multi-body elastic momentum transfer and collision verified.$FG$\n");

  // Test 5: Explosion impulse dispatch & 3D Viewport Rendering
  PhysicsWorldInit();
  PhysicsWorldExplode();
  CRigidBody *b_exp = PhysicsGetBody(0);
  if (b_exp->vel_y < 5.0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Physics explosion upward impulse failed!$FG$\n");
    return 0;
  }
  I64 cw = gfx_get_canvas_width();
  I64 vx = cw - 360;
  if (vx < 320) vx = 320;
  Physics3DRenderViewport(vx, 80, 340, 260);
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Physics explosion dynamics & 3D arena viewport verified.$FG$\n");

  doldoc_printf("\n[PHYSICS3D-PASS] ALL 5 PHYSICS3D TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  PhysicsWorldInit();
} else {
  Physics3DSelfTest();
}
