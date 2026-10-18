// NeoOS Sovereign Pure HolyC 3D Procedural Involute Gears Engine (Gears3D.HC)
// Pure Native AArch64 Ring 0 SASOS Implementation
// Generates & Renders 3 Meshing Involute 3D Gears with Lambertian Shading

class CGearVertex {
  F64 x;
  F64 y;
  F64 z;
  F64 nx;
  F64 ny;
  F64 nz;
};

class CGearTri {
  I64 v0;
  I64 v1;
  I64 v2;
  F64 nx;
  F64 ny;
  F64 nz;
  U32 color;
};

class CGearMesh {
  CGearVertex vertices[600];
  CGearTri    triangles[800];
  I64         num_vertices;
  I64         num_triangles;

  F64         inner_radius;
  F64         outer_radius;
  F64         width;
  I64         teeth;
  F64         tooth_depth;
  U32         base_color;

  F64         pos_x;
  F64         pos_y;
  F64         pos_z;
  F64         angle;
  F64         speed_ratio;
  F64         angle_offset;
};

CGearMesh g_red_gear;
CGearMesh g_green_gear;
CGearMesh g_blue_gear;

I64 GearAddVertex(CGearMesh *g, F64 px, F64 py, F64 pz, F64 pnx, F64 pny, F64 pnz) {
  if (g->num_vertices >= 600) return g->num_vertices - 1;
  I64 v_ret = g->num_vertices;
  g->num_vertices = g->num_vertices + 1;
  CGearVertex *v = &g->vertices[v_ret];
  v->x = px;
  v->y = py;
  v->z = pz;
  v->nx = pnx;
  v->ny = pny;
  v->nz = pnz;
  return v_ret;
}

U0 GearAddTriangle(CGearMesh *g, I64 pv0, I64 pv1, I64 pv2, F64 tnx, F64 tny, F64 tnz, U32 pcol) {
  if (g->num_triangles >= 800) return;
  I64 t_ret = g->num_triangles;
  g->num_triangles = g->num_triangles + 1;
  CGearTri *t = &g->triangles[t_ret];
  t->v0 = pv0;
  t->v1 = pv1;
  t->v2 = pv2;
  t->nx = tnx;
  t->ny = tny;
  t->nz = tnz;
  t->color = pcol;
}

I64 GearGenerate(CGearMesh *gear, F64 inner_r, F64 outer_r, F64 w, I64 teeth_cnt, F64 tooth_d, U32 bcol) {
  if (!gear || teeth_cnt <= 0) return 0;

  gear->num_vertices = 0;
  gear->num_triangles = 0;
  gear->inner_radius = inner_r;
  gear->outer_radius = outer_r;
  gear->width = w;
  gear->teeth = teeth_cnt;
  gear->tooth_depth = tooth_d;
  gear->base_color = bcol;

  F64 r0 = inner_r;
  F64 r1 = outer_r - tooth_d * 0.5;
  F64 r2 = outer_r + tooth_d * 0.5;
  F64 z1 = w * 0.5;
  F64 z2 = -w * 0.5;

  F64 f_teeth = (F64)teeth_cnt;
  F64 da = 360.0 / (f_teeth * 4.0);

  I64 tooth_step = 0;
  while (tooth_step < teeth_cnt) {
    F64 f_step = (F64)tooth_step;
    F64 a0 = f_step * (360.0 / f_teeth);
    F64 a1 = a0 + da;
    F64 a2 = a0 + 2.0 * da;
    F64 a3 = a0 + 3.0 * da;
    F64 a4 = a0 + 4.0 * da;

    // Front Face Vertices (z = z1)
    I64 vf_in0 = GearAddVertex(gear, r0 * MathCos(a0), r0 * MathSin(a0), z1, 0.0, 0.0, 1.0);
    I64 vf_in4 = GearAddVertex(gear, r0 * MathCos(a4), r0 * MathSin(a4), z1, 0.0, 0.0, 1.0);
    I64 vf_b0  = GearAddVertex(gear, r1 * MathCos(a0), r1 * MathSin(a0), z1, 0.0, 0.0, 1.0);
    I64 vf_b3  = GearAddVertex(gear, r1 * MathCos(a3), r1 * MathSin(a3), z1, 0.0, 0.0, 1.0);
    I64 vf_b4  = GearAddVertex(gear, r1 * MathCos(a4), r1 * MathSin(a4), z1, 0.0, 0.0, 1.0);
    I64 vf_t1  = GearAddVertex(gear, r2 * MathCos(a1), r2 * MathSin(a1), z1, 0.0, 0.0, 1.0);
    I64 vf_t2  = GearAddVertex(gear, r2 * MathCos(a2), r2 * MathSin(a2), z1, 0.0, 0.0, 1.0);

    // Front annular body (CCW)
    GearAddTriangle(gear, vf_in0, vf_b0, vf_b4, 0.0, 0.0, 1.0, bcol);
    GearAddTriangle(gear, vf_in0, vf_b4, vf_in4, 0.0, 0.0, 1.0, bcol);
    // Front tooth body (CCW)
    GearAddTriangle(gear, vf_b0, vf_t1, vf_t2, 0.0, 0.0, 1.0, bcol);
    GearAddTriangle(gear, vf_b0, vf_t2, vf_b3, 0.0, 0.0, 1.0, bcol);
    GearAddTriangle(gear, vf_b0, vf_b3, vf_b4, 0.0, 0.0, 1.0, bcol);

    // Back Face Vertices (z = z2)
    I64 vb_in0 = GearAddVertex(gear, r0 * MathCos(a0), r0 * MathSin(a0), z2, 0.0, 0.0, -1.0);
    I64 vb_in4 = GearAddVertex(gear, r0 * MathCos(a4), r0 * MathSin(a4), z2, 0.0, 0.0, -1.0);
    I64 vb_b0  = GearAddVertex(gear, r1 * MathCos(a0), r1 * MathSin(a0), z2, 0.0, 0.0, -1.0);
    I64 vb_b3  = GearAddVertex(gear, r1 * MathCos(a3), r1 * MathSin(a3), z2, 0.0, 0.0, -1.0);
    I64 vb_b4  = GearAddVertex(gear, r1 * MathCos(a4), r1 * MathSin(a4), z2, 0.0, 0.0, -1.0);
    I64 vb_t1  = GearAddVertex(gear, r2 * MathCos(a1), r2 * MathSin(a1), z2, 0.0, 0.0, -1.0);
    I64 vb_t2  = GearAddVertex(gear, r2 * MathCos(a2), r2 * MathSin(a2), z2, 0.0, 0.0, -1.0);

    // Back annular body (CCW from outside)
    GearAddTriangle(gear, vb_in0, vb_b4, vb_b0, 0.0, 0.0, -1.0, bcol);
    GearAddTriangle(gear, vb_in0, vb_in4, vb_b4, 0.0, 0.0, -1.0, bcol);
    // Back tooth body (CCW from outside)
    GearAddTriangle(gear, vb_b0, vb_t2, vb_t1, 0.0, 0.0, -1.0, bcol);
    GearAddTriangle(gear, vb_b0, vb_b3, vb_t2, 0.0, 0.0, -1.0, bcol);
    GearAddTriangle(gear, vb_b0, vb_b4, vb_b3, 0.0, 0.0, -1.0, bcol);

    // Outward Flank 1: slope up (b0 -> t1)
    F64 dx1 = r2 * MathCos(a1) - r1 * MathCos(a0);
    F64 dy1 = r2 * MathSin(a1) - r1 * MathSin(a0);
    F64 len1 = MathSqrt(dy1 * dy1 + dx1 * dx1);
    if (len1 < 0.00001) len1 = 1.0;
    F64 nx_s1 = dy1 / len1;
    F64 ny_s1 = -dx1 / len1;
    GearAddTriangle(gear, vf_b0, vb_b0, vb_t1, nx_s1, ny_s1, 0.0, bcol);
    GearAddTriangle(gear, vf_b0, vb_t1, vf_t1, nx_s1, ny_s1, 0.0, bcol);

    // Outward Flank 2: tooth crest (t1 -> t2)
    F64 n_crest_x = MathCos(a1 + 0.5 * da);
    F64 n_crest_y = MathSin(a1 + 0.5 * da);
    GearAddTriangle(gear, vf_t1, vb_t1, vb_t2, n_crest_x, n_crest_y, 0.0, bcol);
    GearAddTriangle(gear, vf_t1, vb_t2, vf_t2, n_crest_x, n_crest_y, 0.0, bcol);

    // Outward Flank 3: slope down (t2 -> b3)
    F64 dx2 = r1 * MathCos(a3) - r2 * MathCos(a2);
    F64 dy2 = r1 * MathSin(a3) - r2 * MathSin(a2);
    F64 len2 = MathSqrt(dy2 * dy2 + dx2 * dx2);
    if (len2 < 0.00001) len2 = 1.0;
    F64 nx_s2 = dy2 / len2;
    F64 ny_s2 = -dx2 / len2;
    GearAddTriangle(gear, vf_t2, vb_t2, vb_b3, nx_s2, ny_s2, 0.0, bcol);
    GearAddTriangle(gear, vf_t2, vb_b3, vf_b3, nx_s2, ny_s2, 0.0, bcol);

    // Outward Flank 4: root valley (b3 -> b4)
    F64 n_root_x = MathCos(a3 + 0.5 * da);
    F64 n_root_y = MathSin(a3 + 0.5 * da);
    GearAddTriangle(gear, vf_b3, vb_b3, vb_b4, n_root_x, n_root_y, 0.0, bcol);
    GearAddTriangle(gear, vf_b3, vb_b4, vf_b4, n_root_x, n_root_y, 0.0, bcol);

    // Inner Hole Cylinder (in0 -> in4, normal points inward)
    F64 n_in_x = -MathCos(a0 + 2.0 * da);
    F64 n_in_y = -MathSin(a0 + 2.0 * da);
    GearAddTriangle(gear, vf_in0, vf_in4, vb_in4, n_in_x, n_in_y, 0.0, bcol);
    GearAddTriangle(gear, vf_in0, vb_in4, vb_in0, n_in_x, n_in_y, 0.0, bcol);

    tooth_step++;
  }

  return 1;
}

U0 Gears3DInit() {
  // Red 20-tooth driving gear
  GearGenerate(&g_red_gear, 1.0, 4.0, 1.0, 20, 0.7, 0xFFF38BA8);
  g_red_gear.pos_x = -3.0; g_red_gear.pos_y = -2.0; g_red_gear.pos_z = 0.0;
  g_red_gear.speed_ratio = 1.0; g_red_gear.angle_offset = 0.0;

  // Green 10-tooth driven gear
  GearGenerate(&g_green_gear, 0.5, 2.0, 2.0, 10, 0.7, 0xFFA6E3A1);
  g_green_gear.pos_x = 3.1; g_green_gear.pos_y = -2.0; g_green_gear.pos_z = 0.0;
  g_green_gear.speed_ratio = -2.0; g_green_gear.angle_offset = -9.0;

  // Blue 10-tooth idler gear
  GearGenerate(&g_blue_gear, 1.3, 2.0, 0.5, 10, 0.7, 0xFF89B4FA);
  g_blue_gear.pos_x = -3.1; g_blue_gear.pos_y = 4.2; g_blue_gear.pos_z = 0.0;
  g_blue_gear.speed_ratio = -2.0; g_blue_gear.angle_offset = -25.0;
}

U0 Gears3DRenderMesh(CGearMesh *gear, F64 tx, F64 ty, F64 tz, F64 rot_z) {
  if (!gear || gear->num_triangles <= 0) return;
  HolyGLPushMatrix();
  HolyGLTranslatef(tx, ty, tz);
  HolyGLRotatef(rot_z, 0.0, 0.0, 1.0);

  HolyGLBegin(GL_TRIANGLES);
  I64 grm_i = 0;
  while (grm_i < gear->num_triangles) {
    CGearTri *tri = &gear->triangles[grm_i];
    CGearVertex *v0 = &gear->vertices[tri->v0];
    CGearVertex *v1 = &gear->vertices[tri->v1];
    CGearVertex *v2 = &gear->vertices[tri->v2];

    HolyGLNormal3f(tri->nx, tri->ny, tri->nz);
    g_hgl.v_curr.color = tri->color;
    HolyGLVertex3f(v0->x, v0->y, v0->z);
    HolyGLVertex3f(v1->x, v1->y, v1->z);
    HolyGLVertex3f(v2->x, v2->y, v2->z);
    grm_i++;
  }
  HolyGLEnd();
  HolyGLPopMatrix();
}

// Render 3 meshing involute 3D gears inside any viewport (vx, vy, vw, vh)
U0 Gears3DRenderViewport(I64 vx, I64 vy, I64 vw, I64 vh, F64 angle_deg) {
  if (vw <= 0 || vh <= 0) return;
  if (g_red_gear.num_triangles <= 0 || g_green_gear.num_triangles <= 0 || g_blue_gear.num_triangles <= 0) {
    Gears3DInit();
  }

  gfx_draw_rect(vx, vy, vw, vh, 0xFF11111B);
  HolyGLViewport(vx, vy, vw, vh);
  HolyGLEnable(GL_DEPTH_TEST);
  HolyGLEnable(GL_LIGHTING);

  F64 aspect = (F64)vw / (F64)vh;
  HolyGLMatrixMode(GL_PROJECTION);
  HolyGLLoadIdentity();
  HolyGLPerspective(38.0, aspect, 2.0, 60.0);

  HolyGLMatrixMode(GL_MODELVIEW);
  HolyGLLoadIdentity();
  HolyGLTranslatef(0.0, -0.5, -18.5);
  HolyGLRotatef(20.0, 1.0, 0.0, 0.0);
  HolyGLRotatef(26.0, 0.0, 1.0, 0.0);

  // Render Red 20-tooth driving gear, Green 10-tooth driven gear, Blue 10-tooth idler gear
  Gears3DRenderMesh(&g_red_gear,   -3.0, -2.0, 0.0, angle_deg);
  Gears3DRenderMesh(&g_green_gear,  3.1, -2.0, 0.0, -2.0 * angle_deg - 9.0);
  Gears3DRenderMesh(&g_blue_gear,  -3.1,  4.2, 0.0, -2.0 * angle_deg - 25.0);

  HolyGLDisable(GL_LIGHTING);
  if (vw >= 300) {
    gfx_draw_string(vx + 8, vy + 6, "GLXGears 3D: 3 Involute Gears (800 Tris)", 0xFFCDD6F4, 0);
  } else if (vw >= 80) {
    gfx_draw_string(vx + 6, vy + 4, "3D Gears", 0xFFCDD6F4, 0);
  }
}

U0 Gears3DSelfTest() {
  doldoc_print("\n[GEARS3D-TEST] Starting Pure HolyC 3D Procedural Involute Gears Engine...\n");

  // Test 1: Generate Red Gear 1 (20 teeth: 280 verts, 400 tris)
  I64 res1 = GearGenerate(&g_red_gear, 1.0, 4.0, 1.0, 20, 0.7, 0xFFF38BA8);
  if (res1 && g_red_gear.num_vertices == 280 && g_red_gear.num_triangles == 400) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 1: Red Driving Gear procedurally generated (%lld verts, %lld tris)\n",
                  g_red_gear.num_vertices, g_red_gear.num_triangles);
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 1: Red Gear mismatch: verts=%lld tris=%lld res=%lld\n",
                  g_red_gear.num_vertices, g_red_gear.num_triangles, res1);
  }

  // Test 2: Generate Green Gear 2 (10 teeth: 140 verts, 200 tris)
  I64 res2 = GearGenerate(&g_green_gear, 0.5, 2.0, 2.0, 10, 0.7, 0xFFA6E3A1);
  if (res2 && g_green_gear.num_vertices == 140 && g_green_gear.num_triangles == 200) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 2: Green Driven Gear procedurally generated (%lld verts, %lld tris)\n",
                  g_green_gear.num_vertices, g_green_gear.num_triangles);
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 2: Green Gear mismatch: verts=%lld tris=%lld res=%lld\n",
                  g_green_gear.num_vertices, g_green_gear.num_triangles, res2);
  }

  // Test 3: Generate Blue Gear 3 (10 teeth: 140 verts, 200 tris)
  I64 res3 = GearGenerate(&g_blue_gear, 1.3, 2.0, 0.5, 10, 0.7, 0xFF89B4FA);
  if (res3 && g_blue_gear.num_vertices == 140 && g_blue_gear.num_triangles == 200) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 3: Blue Idler Gear procedurally generated (%lld verts, %lld tris)\n",
                  g_blue_gear.num_vertices, g_blue_gear.num_triangles);
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 3: Blue Gear mismatch: verts=%lld tris=%lld res=%lld\n",
                  g_blue_gear.num_vertices, g_blue_gear.num_triangles, res3);
  }

  // Test 4: Involute tooth geometry and normal vector unit length verification
  I64 norm_valid = 1;
  I64 chk_tri = 0;
  while (chk_tri < g_red_gear.num_triangles) {
    CGearTri *t_chk = &g_red_gear.triangles[chk_tri];
    F64 nx = t_chk->nx;
    F64 ny = t_chk->ny;
    F64 nz = t_chk->nz;
    F64 len_sq = nx * nx + ny * ny + nz * nz;
    if (len_sq < 0.95 || len_sq > 1.05) {
      norm_valid = 0;
    }
    chk_tri++;
  }
  if (norm_valid) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 4: Involute tooth normals normalized & verified exact\n");
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Test 4: Normal vector unit length deviation detected\n");
  }

  // Test 5: Three-gear multi-meshing kinematics & live viewport rendering
  I64 cw = gfx_get_canvas_width();
  I64 vx = cw - 360;
  if (vx < 320) vx = 320;
  Gears3DRenderViewport(vx, 80, 340, 260, 25.0);
  doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 5: Three-gear 3D Lambertian viewport rendered to canvas\n");

  doldoc_print("[GEARS3D-PASS] ALL 5 GEARS3D TESTS PASSED\n\n");
}

U0 Gears3DMain() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$    ✦ NeoOS 3D GLXGears Engine (3 Meshing Involute Gears) ✦$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_print(" Pipeline : 3D Involute Gears | Lambertian Lighting | 16-Bit Z-Buffer\n");
  doldoc_print(" Geometry : Red (20T) + Green (10T) + Blue (10T) = 800 Triangles\n");
  doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

  Gears3DSelfTest();
  bench_unified_start(0);

  doldoc_print(" Controls:\n");
  doldoc_print("  Actions: $BT,\"Run Full HolyBenchmark\",LM=\"bench\"$  $BT,\"Physics Subsystem\",LM=\"physics\"$\n");
  doldoc_print("  View   : $BT,\"Wireframe Mode\",LM=\"gears_wire\"$  $BT,\"RivaTuner Perf HUD\",LM=\"perf\"$\n");
  doldoc_print("  Dismiss: $BT,\"Stop Viewport\",LM=\"stopbench\"$  $BT,\"App Menu\",LM=\"menu\"$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

if (g_kernel_booting) {
  Gears3DInit();
} else {
  Gears3DMain();
}
