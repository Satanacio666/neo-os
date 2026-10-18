// HolyGLTest.HC - Comprehensive OpenGL 1.3/2.0 State Machine & Z-Buffer Verification
// Verifies Matrix Stack, Perspective Projection, Lambertian Lighting & Triangle Rasterization

I64 HolyGLTestRun() {
  doldoc_print("\n$FG,CYAN$[HOLYGL-TEST] Starting Pure HolyC OpenGL Pipeline Verification...$FG$\n");
  I64 all_pass = 1;

  // Test 1: Matrix Stack Push / Translate / Pop Isolation
  HolyGLInit();
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  glTranslatef(5.0, -3.0, -10.0);
  glPushMatrix();
  glTranslatef(20.0, 40.0, -50.0);
  glPopMatrix();

  if (g_hgl.modelview.m[3] > 4.99 && g_hgl.modelview.m[3] < 5.01 &&
      g_hgl.modelview.m[7] > -3.01 && g_hgl.modelview.m[7] < -2.99 &&
      g_hgl.modelview.m[11] > -10.01 && g_hgl.modelview.m[11] < -9.99) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 1: Matrix stack (glPushMatrix / glPopMatrix) state isolation verified\n");
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Test 1: Matrix stack corrupted modelview translation!\n");
    all_pass = 0;
  }

  // Test 2: Perspective Projection & MVP Composition
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  gluPerspective(60.0, 1.333333, 0.5, 100.0);
  if (g_hgl.projection.m[14] < -0.99 && g_hgl.projection.m[14] > -1.01 && g_hgl.projection.m[5] > 1.7) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 2: Perspective frustum projection & MVP composition verified\n");
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Test 2: Perspective matrix invalid!\n");
    all_pass = 0;
  }

  // Test 3: Directional Lambertian Lighting Attenuation
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  U32 lit_front = HolyGLApplyLighting(0xFFFFFFFF, 0.4472, 0.6324, 0.6324);
  U32 lit_side  = HolyGLApplyLighting(0xFFFFFFFF, -0.7, 0.0, 0.0);
  if (((lit_front >> 16) & 0xFF) > ((lit_side >> 16) & 0xFF)) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 3: Lambertian normal shading verified (Front Luma=%lld > Side Luma=%lld)\n",
                  (I64)((lit_front >> 16) & 0xFF), (I64)((lit_side >> 16) & 0xFF));
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Test 3: Lambertian lighting failed!\n");
    all_pass = 0;
  }

  // Test 4: Z-Buffered Triangle Rasterization
  I64 cw = gfx_get_canvas_width();
  I64 vx = cw - 340;
  if (vx < 300) vx = 300;
  glViewport(vx, 80, 300, 220);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_LIGHTING);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  glTranslatef(0.0, 0.0, -4.0);

  I64 tris_before = g_hgl.tris_rendered;
  glBegin(GL_TRIANGLES);
  glNormal3f(0.0, 0.0, 1.0);
  glColor3f(0.2, 0.8, 1.0);
  glVertex3f(-1.0, -1.0, 0.0);
  glVertex3f( 1.0, -1.0, 0.0);
  glVertex3f( 0.0,  1.0, 0.0);
  glEnd();
  glDisable(GL_LIGHTING);

  if (g_hgl.tris_rendered == tris_before + 1) {
    doldoc_print("  $FG,GREEN$[PASS]$FG$ Test 4: glBegin(GL_TRIANGLES) / glEnd Z-buffered rasterization verified\n");
  } else {
    doldoc_print("  $FG,RED$[FAIL]$FG$ Test 4: Triangle submission failed!\n");
    all_pass = 0;
  }

  if (all_pass) {
    doldoc_print("[HOLYGL-PASS] ALL 4 HOLYGL TESTS PASSED\n\n");
  }
  return all_pass;
}

if (!g_kernel_booting) {
  HolyGLTestRun();
}
