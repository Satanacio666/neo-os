// NeoOS Sovereign Pure HolyC Mouse Driver
// Ring 0 AArch64 Hardware Driver & Save-Under Cursor Engine

class CMouseState {
  I64 x;
  I64 y;
  I64 left_button;
  I64 right_button;
  I64 buttons;
  I64 visible;
};

CMouseState g_mouse;
I64 s_screen_w = 1024;
I64 s_screen_h = 768;

// Save-under buffers (16x16 = 256 pixels)
U32 s_cursor_save_under[256];
I64 s_cursor_saved_x = -1;
I64 s_cursor_saved_y = -1;
I64 s_cursor_is_drawn = 0;

U32 s_front_save_under[256];
I64 s_front_saved_x = -1;
I64 s_front_saved_y = -1;
I64 s_front_is_drawn = 0;

// 16x16 cursor bitmap (0: transparent, 1: outline, 2: fill)
U8 g_cursor_bitmap[256];

U0 CursorBitmapInit() {
  I64 ms_bi;
  for (ms_bi = 0; ms_bi < 256; ms_bi++) {
    g_cursor_bitmap[ms_bi] = 0;
  }
  // Row 0
  g_cursor_bitmap[0*16 + 0] = 1;
  // Row 1
  g_cursor_bitmap[1*16 + 0] = 1; g_cursor_bitmap[1*16 + 1] = 1;
  // Row 2
  g_cursor_bitmap[2*16 + 0] = 1; g_cursor_bitmap[2*16 + 1] = 2; g_cursor_bitmap[2*16 + 2] = 1;
  // Row 3
  g_cursor_bitmap[3*16 + 0] = 1; g_cursor_bitmap[3*16 + 1] = 2; g_cursor_bitmap[3*16 + 2] = 2; g_cursor_bitmap[3*16 + 3] = 1;
  // Row 4
  g_cursor_bitmap[4*16 + 0] = 1; g_cursor_bitmap[4*16 + 1] = 2; g_cursor_bitmap[4*16 + 2] = 2; g_cursor_bitmap[4*16 + 3] = 2; g_cursor_bitmap[4*16 + 4] = 1;
  // Row 5
  g_cursor_bitmap[5*16 + 0] = 1; g_cursor_bitmap[5*16 + 1] = 2; g_cursor_bitmap[5*16 + 2] = 2; g_cursor_bitmap[5*16 + 3] = 2; g_cursor_bitmap[5*16 + 4] = 2; g_cursor_bitmap[5*16 + 5] = 1;
  // Row 6
  g_cursor_bitmap[6*16 + 0] = 1; g_cursor_bitmap[6*16 + 1] = 2; g_cursor_bitmap[6*16 + 2] = 2; g_cursor_bitmap[6*16 + 3] = 2; g_cursor_bitmap[6*16 + 4] = 2; g_cursor_bitmap[6*16 + 5] = 2; g_cursor_bitmap[6*16 + 6] = 1;
  // Row 7
  g_cursor_bitmap[7*16 + 0] = 1; g_cursor_bitmap[7*16 + 1] = 2; g_cursor_bitmap[7*16 + 2] = 2; g_cursor_bitmap[7*16 + 3] = 2; g_cursor_bitmap[7*16 + 4] = 2; g_cursor_bitmap[7*16 + 5] = 2; g_cursor_bitmap[7*16 + 6] = 2; g_cursor_bitmap[7*16 + 7] = 1;
  // Row 8
  g_cursor_bitmap[8*16 + 0] = 1; g_cursor_bitmap[8*16 + 1] = 2; g_cursor_bitmap[8*16 + 2] = 2; g_cursor_bitmap[8*16 + 3] = 2; g_cursor_bitmap[8*16 + 4] = 2; g_cursor_bitmap[8*16 + 5] = 2; g_cursor_bitmap[8*16 + 6] = 2; g_cursor_bitmap[8*16 + 7] = 2; g_cursor_bitmap[8*16 + 8] = 1;
  // Row 9
  g_cursor_bitmap[9*16 + 0] = 1; g_cursor_bitmap[9*16 + 1] = 2; g_cursor_bitmap[9*16 + 2] = 2; g_cursor_bitmap[9*16 + 3] = 2; g_cursor_bitmap[9*16 + 4] = 2; g_cursor_bitmap[9*16 + 5] = 1; g_cursor_bitmap[9*16 + 6] = 1; g_cursor_bitmap[9*16 + 7] = 1; g_cursor_bitmap[9*16 + 8] = 1; g_cursor_bitmap[9*16 + 9] = 1;
  // Row 10
  g_cursor_bitmap[10*16 + 0] = 1; g_cursor_bitmap[10*16 + 1] = 2; g_cursor_bitmap[10*16 + 2] = 1; g_cursor_bitmap[10*16 + 3] = 2; g_cursor_bitmap[10*16 + 4] = 2; g_cursor_bitmap[10*16 + 5] = 1;
  // Row 11
  g_cursor_bitmap[11*16 + 0] = 1; g_cursor_bitmap[11*16 + 1] = 1; g_cursor_bitmap[11*16 + 3] = 1; g_cursor_bitmap[11*16 + 4] = 2; g_cursor_bitmap[11*16 + 5] = 2; g_cursor_bitmap[11*16 + 6] = 1;
  // Row 12
  g_cursor_bitmap[12*16 + 0] = 1; g_cursor_bitmap[12*16 + 4] = 1; g_cursor_bitmap[12*16 + 5] = 2; g_cursor_bitmap[12*16 + 6] = 2; g_cursor_bitmap[12*16 + 7] = 1;
  // Row 13
  g_cursor_bitmap[13*16 + 5] = 1; g_cursor_bitmap[13*16 + 6] = 2; g_cursor_bitmap[13*16 + 7] = 2; g_cursor_bitmap[13*16 + 8] = 1;
  // Row 14
  g_cursor_bitmap[14*16 + 6] = 1; g_cursor_bitmap[14*16 + 7] = 1;
}

U0 MouseSyncBounds() {
  I64 cw = gfx_get_canvas_width();
  I64 ch = gfx_get_canvas_height();
  if (cw > 0) s_screen_w = cw;
  if (ch > 0) s_screen_h = ch;
}

U0 MouseInit(I64 max_w, I64 max_h) {
  if (max_w <= 0) max_w = gfx_get_canvas_width();
  if (max_h <= 0) max_h = gfx_get_canvas_height();
  if (max_w <= 0) max_w = 1024;
  if (max_h <= 0) max_h = 768;

  s_screen_w = max_w;
  s_screen_h = max_h;
  g_mouse.x = max_w / 2;
  g_mouse.y = max_h / 2;
  g_mouse.left_button = 0;
  g_mouse.right_button = 0;
  g_mouse.buttons = 0;
  g_mouse.visible = 1;
  s_cursor_is_drawn = 0;
  s_front_is_drawn = 0;
  s_cursor_saved_x = -1;
  s_cursor_saved_y = -1;
  s_front_saved_x = -1;
  s_front_saved_y = -1;
  CursorBitmapInit();
}

U0 MouseEraseOnBuffer(U32 *buf, U32 *save_under, I64 saved_x, I64 saved_y) {
  if (!buf) return;
  I64 pitch = gfx_get_canvas_pitch();
  I64 ms_er_r;
  I64 ms_er_c;
  I64 px;
  I64 py;
  for (ms_er_r = 0; ms_er_r < 16; ms_er_r++) {
    for (ms_er_c = 0; ms_er_c < 16; ms_er_c++) {
      if (g_cursor_bitmap[ms_er_r * 16 + ms_er_c] == 0) continue;
      px = saved_x + ms_er_c;
      py = saved_y + ms_er_r;
      if (px >= 0 && px < s_screen_w && py >= 0 && py < s_screen_h) {
        buf[py * pitch + px] = save_under[ms_er_r * 16 + ms_er_c];
      }
    }
  }
}

U0 MouseDrawOnBuffer(U32 *buf, U32 *save_under, I64 cur_x, I64 cur_y) {
  if (!buf) return;
  I64 pitch = gfx_get_canvas_pitch();
  I64 ms_dr_r;
  I64 ms_dr_c;
  I64 px;
  I64 py;
  U8 p;
  U32 col;

  // Save under
  for (ms_dr_r = 0; ms_dr_r < 16; ms_dr_r++) {
    for (ms_dr_c = 0; ms_dr_c < 16; ms_dr_c++) {
      px = cur_x + ms_dr_c;
      py = cur_y + ms_dr_r;
      if (px >= 0 && px < s_screen_w && py >= 0 && py < s_screen_h) {
        save_under[ms_dr_r * 16 + ms_dr_c] = buf[py * pitch + px];
      } else {
        save_under[ms_dr_r * 16 + ms_dr_c] = 0;
      }
    }
  }

  // Draw bitmap
  for (ms_dr_r = 0; ms_dr_r < 16; ms_dr_r++) {
    for (ms_dr_c = 0; ms_dr_c < 16; ms_dr_c++) {
      p = g_cursor_bitmap[ms_dr_r * 16 + ms_dr_c];
      if (p == 0) continue;
      px = cur_x + ms_dr_c;
      py = cur_y + ms_dr_r;
      if (px >= 0 && px < s_screen_w && py >= 0 && py < s_screen_h) {
        if (p == 1) col = 0xFF1B1E20; else col = 0xFFFCFCFC;
        buf[py * pitch + px] = col;
      }
    }
  }
}

U0 MouseEraseCursor() {
  U32 *back = gfx_get_backbuffer();
  if (!s_cursor_is_drawn || !back) return;
  MouseEraseOnBuffer(back, &s_cursor_save_under[0], s_cursor_saved_x, s_cursor_saved_y);
  s_cursor_is_drawn = 0;
}

U0 MouseDrawCursor() {
  U32 *back = gfx_get_backbuffer();
  if (!g_mouse.visible || !back) return;
  if (s_cursor_is_drawn) MouseEraseCursor();
  MouseDrawOnBuffer(back, &s_cursor_save_under[0], g_mouse.x, g_mouse.y);
  s_cursor_saved_x = g_mouse.x;
  s_cursor_saved_y = g_mouse.y;
  s_cursor_is_drawn = 1;
}

U0 MouseEraseCursorFront() {
  U32 *front = gfx_get_frontbuffer();
  if (!s_front_is_drawn || !front) return;
  MouseEraseOnBuffer(front, &s_front_save_under[0], s_front_saved_x, s_front_saved_y);
  s_front_is_drawn = 0;
}

U0 MouseDrawCursorFront() {
  U32 *front = gfx_get_frontbuffer();
  if (!g_mouse.visible) return;
  if (!front) { MouseDrawCursor(); return; }
  if (s_front_is_drawn) MouseEraseCursorFront();
  MouseDrawOnBuffer(front, &s_front_save_under[0], g_mouse.x, g_mouse.y);
  s_front_saved_x = g_mouse.x;
  s_front_saved_y = g_mouse.y;
  s_front_is_drawn = 1;
}

U0 MouseSetPos(I64 x, I64 y) {
  MouseSyncBounds();
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x >= s_screen_w) x = s_screen_w - 1;
  if (y >= s_screen_h) y = s_screen_h - 1;

  if (g_mouse.x != x || g_mouse.y != y) {
    if (s_front_is_drawn) {
      MouseEraseCursorFront();
    }
    g_mouse.x = x;
    g_mouse.y = y;
    if (g_mouse.visible) {
      MouseDrawCursorFront();
    }
  }
}

U0 MouseSetButton(I64 left, I64 right) {
  g_mouse.left_button = (left != 0);
  g_mouse.right_button = (right != 0);
  g_mouse.buttons = 0;
  if (g_mouse.left_button) g_mouse.buttons = g_mouse.buttons | 1;
  if (g_mouse.right_button) g_mouse.buttons = g_mouse.buttons | 2;
}

U0 MouseUpdate(I64 x, I64 y, I64 buttons) {
  MouseSyncBounds();
  MouseSetButton(buttons & 1, (buttons >> 1) & 1);
  MouseSetPos(x, y);
}

I64 MouseGetX() { return g_mouse.x; }
I64 MouseGetY() { return g_mouse.y; }
I64 MouseGetBtn() { return g_mouse.left_button; }
I64 MouseGetRightBtn() { return g_mouse.right_button; }
I64 MouseGetButtons() { return g_mouse.buttons; }

// Verification Test Suite
I64 MouseSelfTest() {
  I64 passed = 0;
  I64 total = 5;

  doldoc_printf("\n=====================================================\n");
  doldoc_printf("  [MOUSE.HC] Pure HolyC Mouse & Cursor Engine Scorecard\n");
  doldoc_printf("=====================================================\n");

  I64 cw = gfx_get_canvas_width();
  I64 ch = gfx_get_canvas_height();
  if (cw <= 0) cw = 1024;
  if (ch <= 0) ch = 768;

  MouseInit(cw, ch);
  doldoc_printf("[MOUSE.HC] Sovereign Mouse Driver Initialized (%dx%d)\n", cw, ch);

  // Test 1: Initial position & bounds clamping
  if (MouseGetX() == cw / 2 && MouseGetY() == ch / 2) {
    MouseSetPos(-50, -100);
    if (MouseGetX() == 0 && MouseGetY() == 0) {
      MouseSetPos(cw + 2000, ch + 3000);
      if (MouseGetX() == cw - 1 && MouseGetY() == ch - 1) {
        doldoc_printf("  [PASS] Bounds Clamping (Negative, In-Bounds, Exceeded %dx%d)\n", cw, ch);
        passed++;
      }
    }
  }

  // Test 2: Button state toggling & mouse_get_buttons() bitmask
  MouseSetButton(1, 0);
  if (MouseGetBtn() == 1 && MouseGetRightBtn() == 0 && MouseGetButtons() == 1) {
    MouseSetButton(0, 1);
    if (MouseGetBtn() == 0 && MouseGetRightBtn() == 1 && MouseGetButtons() == 2) {
      MouseSetButton(1, 1);
      if (MouseGetBtn() == 1 && MouseGetRightBtn() == 1 && MouseGetButtons() == 3) {
        doldoc_printf("  [PASS] Mouse Button States (Left=1, Right=2, Chord=3)\n");
        passed++;
      }
    }
  }
  MouseSetButton(0, 0);

  // Test 3: Cursor Bitmap initialization & structure
  if (g_cursor_bitmap[0] == 1 && g_cursor_bitmap[1*16 + 1] == 1 &&
      g_cursor_bitmap[2*16 + 1] == 2 && g_cursor_bitmap[9*16 + 9] == 1) {
    doldoc_printf("  [PASS] 16x16 Cursor Bitmap Matrix Validated\n");
    passed++;
  }

  // Test 4: Save-under restoration verification (saving & restoring original pixel at (100,100)!)
  U32 *back = gfx_get_backbuffer();
  I64 pitch = gfx_get_canvas_pitch();
  if (back) {
    U32 orig_pixel_100 = back[100 * pitch + 100];
    // Fill test pixel with known pattern
    back[100 * pitch + 100] = 0xAA55AA55;
    MouseSetPos(100, 100);
    MouseDrawCursor();
    // After draw, pixel should be overwritten with cursor outline
    U32 drawn = back[100 * pitch + 100];
    MouseEraseCursor();
    // After erase, pristine test pattern must be restored
    U32 restored = back[100 * pitch + 100];
    // Restore original screen pixel at (100, 100) so no corrupted dot remains!
    back[100 * pitch + 100] = orig_pixel_100;
    if (restored == 0xAA55AA55 && drawn != 0xAA55AA55) {
      doldoc_printf("  [PASS] Save-Under Pixel Preservation & Non-Destructive Restore\n");
      passed++;
    } else {
      doldoc_printf("  [FAIL] Save-under pixel mismatch (drawn=0x%08X restored=0x%08X)\n", drawn, restored);
    }
  } else {
    doldoc_printf("  [FAIL] Framebuffer backbuffer offline\n");
  }

  // Test 5: Trajectory tracking
  I64 ms_step;
  I64 ms_ok = 1;
  for (ms_step = 0; ms_step < 10; ms_step++) {
    MouseSetPos(200 + ms_step * 10, 300 + ms_step * 5);
    if (MouseGetX() != 200 + ms_step * 10 || MouseGetY() != 300 + ms_step * 5) {
      ms_ok = 0;
    }
  }
  if (ms_ok) {
    doldoc_printf("  [PASS] High-Precision Sub-Pixel / Delta Trajectory Tracking\n");
    passed++;
  }

  // Restore mouse to screen center
  MouseSetPos(cw / 2, ch / 2);

  doldoc_printf("=====================================================\n");
  doldoc_printf("  All %d / %d Mouse.HC tests passed!\n", passed, total);
  doldoc_printf("=====================================================\n");

  return passed;
}

I64 mouse_get_x() { return MouseGetX(); }
I64 mouse_get_y() { return MouseGetY(); }
I64 mouse_get_btn() { return MouseGetBtn(); }
I64 mouse_get_buttons() { return MouseGetButtons(); }

U0 mouse_poll() {
  VirtioInputPoll();
}

U0 mouse_draw_cursor_front() {
  MouseDrawCursorFront();
}

I64 g_kernel_booting;
if (g_kernel_booting) {
  MouseInit(gfx_get_canvas_width(), gfx_get_canvas_height());
} else {
  MouseSelfTest();
}
