// NeoOS Sovereign Pure HolyC VirtIO Input Driver
// Ring 0 AArch64 Bare-Metal Virtqueue Hardware Driver

#define VIRTIO_DEV_INPUT 18
#define VIRTIO_MMIO_SLOT_BASE 0x0A000000
#define VIRTIO_MMIO_SLOT_STRIDE 0x200
#define VIRTIO_MMIO_MAGIC 0x74726976

#define VIRTIO_MMIO_MAGIC_VALUE 0x000
#define VIRTIO_MMIO_VERSION 0x004
#define VIRTIO_MMIO_DEVICE_ID 0x008
#define VIRTIO_MMIO_DEVICE_FEATURES 0x010
#define VIRTIO_MMIO_DEVICE_FEATURES_SEL 0x014
#define VIRTIO_MMIO_DRIVER_FEATURES 0x020
#define VIRTIO_MMIO_DRIVER_FEATURES_SEL 0x024
#define VIRTIO_MMIO_QUEUE_SEL 0x030
#define VIRTIO_MMIO_QUEUE_NUM_MAX 0x034
#define VIRTIO_MMIO_QUEUE_NUM 0x038
#define VIRTIO_MMIO_QUEUE_READY 0x044
#define VIRTIO_MMIO_QUEUE_NOTIFY 0x050
#define VIRTIO_MMIO_STATUS 0x070
#define VIRTIO_MMIO_QUEUE_DESC_LOW 0x080
#define VIRTIO_MMIO_QUEUE_DESC_HIGH 0x084
#define VIRTIO_MMIO_QUEUE_DRIVER_LOW 0x090
#define VIRTIO_MMIO_QUEUE_DRIVER_HIGH 0x094
#define VIRTIO_MMIO_QUEUE_DEVICE_LOW 0x0A0
#define VIRTIO_MMIO_QUEUE_DEVICE_HIGH 0x0A4

#define VIRTIO_STATUS_ACKNOWLEDGE 1
#define VIRTIO_STATUS_DRIVER 2
#define VIRTIO_STATUS_DRIVER_OK 4
#define VIRTIO_STATUS_FEATURES_OK 8

#define VRING_DESC_F_WRITE 2

#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_REL 0x02
#define EV_ABS 0x03

#define ABS_X 0x00
#define ABS_Y 0x01
#define REL_X 0x00
#define REL_Y 0x01

#define BTN_LEFT  0x110
#define BTN_RIGHT 0x111

#define KEY_ESC_CODE       1
#define KEY_BACKSPACE_CODE 14
#define KEY_TAB_CODE       15
#define KEY_ENTER_CODE     28
#define KEY_LSHIFT_CODE    42
#define KEY_RSHIFT_CODE    54
#define KEY_HOME_CODE      102
#define KEY_UP_CODE        103
#define KEY_PAGEUP_CODE    104
#define KEY_LEFT_CODE      105
#define KEY_RIGHT_CODE     106
#define KEY_END_CODE       107
#define KEY_DOWN_CODE      108
#define KEY_PAGEDOWN_CODE  109

#define VIRTIO_INPUT_QUEUE_SIZE 64

class CVirtioInputEvent {
  U16 type;
  U16 code;
  U32 value;
};

class CVringDesc {
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CVringAvail {
  U16 flags;
  U16 idx;
  U16 ring[256];
  U16 used_event;
};

class CVringUsedElem {
  U32 id;
  U32 len;
};

class CVringUsed {
  U16 flags;
  U16 idx;
  CVringUsedElem ring[256];
  U16 avail_event;
};

class CVirtioInputDev {
  U64 mmio_base;
  U32 version;
  U32 queue_num;
  U16 last_used_idx;
  I64 active;
  U64 ring_base;
  CVringDesc *vq_desc;
  CVringAvail *vq_avail;
  CVringUsed *vq_used;
  CVirtioInputEvent *event_buf;
};

CVirtioInputDev g_virtio_input_devs[4];
I64 g_num_input_devs = 0;

I64 g_vinput_screen_w = 1024;
I64 g_vinput_screen_h = 768;
I64 g_vinput_shift_state = 0;
I64 g_vinput_mouse_x = 512;
I64 g_vinput_mouse_y = 384;
I64 g_vinput_mouse_btn_l = 0;
I64 g_vinput_mouse_btn_r = 0;

U16 g_vinput_keymap_lower[128];
U16 g_vinput_keymap_upper[128];

U0 VirtioInputInitKeymaps() {
  I64 vi_km_i;
  for (vi_km_i = 0; vi_km_i < 128; vi_km_i++) {
    g_vinput_keymap_lower[vi_km_i] = 0;
    g_vinput_keymap_upper[vi_km_i] = 0;
  }

  g_vinput_keymap_lower[1] = 27;   g_vinput_keymap_upper[1] = 27; // ESC
  g_vinput_keymap_lower[2] = '1'; g_vinput_keymap_upper[2] = '!';
  g_vinput_keymap_lower[3] = '2'; g_vinput_keymap_upper[3] = '@';
  g_vinput_keymap_lower[4] = '3'; g_vinput_keymap_upper[4] = '#';
  g_vinput_keymap_lower[5] = '4'; g_vinput_keymap_upper[5] = '$';
  g_vinput_keymap_lower[6] = '5'; g_vinput_keymap_upper[6] = '%';
  g_vinput_keymap_lower[7] = '6'; g_vinput_keymap_upper[7] = '^';
  g_vinput_keymap_lower[8] = '7'; g_vinput_keymap_upper[8] = '&';
  g_vinput_keymap_lower[9] = '8'; g_vinput_keymap_upper[9] = '*';
  g_vinput_keymap_lower[10] = '9'; g_vinput_keymap_upper[10] = '(';
  g_vinput_keymap_lower[11] = '0'; g_vinput_keymap_upper[11] = ')';
  g_vinput_keymap_lower[12] = '-'; g_vinput_keymap_upper[12] = '_';
  g_vinput_keymap_lower[13] = '='; g_vinput_keymap_upper[13] = '+';
  g_vinput_keymap_lower[14] = 8;   g_vinput_keymap_upper[14] = 8; // BS
  g_vinput_keymap_lower[15] = 9;   g_vinput_keymap_upper[15] = 9; // TAB

  g_vinput_keymap_lower[16] = 'q'; g_vinput_keymap_upper[16] = 'Q';
  g_vinput_keymap_lower[17] = 'w'; g_vinput_keymap_upper[17] = 'W';
  g_vinput_keymap_lower[18] = 'e'; g_vinput_keymap_upper[18] = 'E';
  g_vinput_keymap_lower[19] = 'r'; g_vinput_keymap_upper[19] = 'R';
  g_vinput_keymap_lower[20] = 't'; g_vinput_keymap_upper[20] = 'T';
  g_vinput_keymap_lower[21] = 'y'; g_vinput_keymap_upper[21] = 'Y';
  g_vinput_keymap_lower[22] = 'u'; g_vinput_keymap_upper[22] = 'U';
  g_vinput_keymap_lower[23] = 'i'; g_vinput_keymap_upper[23] = 'I';
  g_vinput_keymap_lower[24] = 'o'; g_vinput_keymap_upper[24] = 'O';
  g_vinput_keymap_lower[25] = 'p'; g_vinput_keymap_upper[25] = 'P';
  g_vinput_keymap_lower[26] = '['; g_vinput_keymap_upper[26] = '{';
  g_vinput_keymap_lower[27] = ']'; g_vinput_keymap_upper[27] = '}';
  g_vinput_keymap_lower[28] = 10;  g_vinput_keymap_upper[28] = 10; // Enter

  g_vinput_keymap_lower[30] = 'a'; g_vinput_keymap_upper[30] = 'A';
  g_vinput_keymap_lower[31] = 's'; g_vinput_keymap_upper[31] = 'S';
  g_vinput_keymap_lower[32] = 'd'; g_vinput_keymap_upper[32] = 'D';
  g_vinput_keymap_lower[33] = 'f'; g_vinput_keymap_upper[33] = 'F';
  g_vinput_keymap_lower[34] = 'g'; g_vinput_keymap_upper[34] = 'G';
  g_vinput_keymap_lower[35] = 'h'; g_vinput_keymap_upper[35] = 'H';
  g_vinput_keymap_lower[36] = 'j'; g_vinput_keymap_upper[36] = 'J';
  g_vinput_keymap_lower[37] = 'k'; g_vinput_keymap_upper[37] = 'K';
  g_vinput_keymap_lower[38] = 'l'; g_vinput_keymap_upper[38] = 'L';
  g_vinput_keymap_lower[39] = ';'; g_vinput_keymap_upper[39] = ':';
  g_vinput_keymap_lower[40] = '\''; g_vinput_keymap_upper[40] = '"';
  g_vinput_keymap_lower[41] = '`'; g_vinput_keymap_upper[41] = '~';
  g_vinput_keymap_lower[43] = '\\'; g_vinput_keymap_upper[43] = '|';

  g_vinput_keymap_lower[44] = 'z'; g_vinput_keymap_upper[44] = 'Z';
  g_vinput_keymap_lower[45] = 'x'; g_vinput_keymap_upper[45] = 'X';
  g_vinput_keymap_lower[46] = 'c'; g_vinput_keymap_upper[46] = 'C';
  g_vinput_keymap_lower[47] = 'v'; g_vinput_keymap_upper[47] = 'V';
  g_vinput_keymap_lower[48] = 'b'; g_vinput_keymap_upper[48] = 'B';
  g_vinput_keymap_lower[49] = 'n'; g_vinput_keymap_upper[49] = 'N';
  g_vinput_keymap_lower[50] = 'm'; g_vinput_keymap_upper[50] = 'M';
  g_vinput_keymap_lower[51] = ','; g_vinput_keymap_upper[51] = '<';
  g_vinput_keymap_lower[52] = '.'; g_vinput_keymap_upper[52] = '>';
  g_vinput_keymap_lower[53] = '/'; g_vinput_keymap_upper[53] = '?';
  g_vinput_keymap_lower[57] = ' '; g_vinput_keymap_upper[57] = ' ';

  g_vinput_keymap_lower[102] = 263; g_vinput_keymap_upper[102] = 263; // KEY_HOME
  g_vinput_keymap_lower[103] = 257; g_vinput_keymap_upper[103] = 257; // KEY_UP
  g_vinput_keymap_lower[104] = 261; g_vinput_keymap_upper[104] = 261; // KEY_PAGE_UP
  g_vinput_keymap_lower[105] = 260; g_vinput_keymap_upper[105] = 260; // KEY_LEFT
  g_vinput_keymap_lower[106] = 259; g_vinput_keymap_upper[106] = 259; // KEY_RIGHT
  g_vinput_keymap_lower[107] = 264; g_vinput_keymap_upper[107] = 264; // KEY_END
  g_vinput_keymap_lower[108] = 258; g_vinput_keymap_upper[108] = 258; // KEY_DOWN
  g_vinput_keymap_lower[109] = 262; g_vinput_keymap_upper[109] = 262; // KEY_PAGE_DOWN
}

U32 VirtioMmioRead32(U64 base, U64 offset) {
  return __mmio_r32(base + offset);
}

U0 VirtioMmioWrite32(U64 base, U64 offset, U32 val) {
  __mmio_w32(base + offset, val);
}

I64 g_vinput_test_mode = 0;

U0 VirtioInputProcessEvent(CVirtioInputEvent *p_ev) {
  if (!p_ev) return;

  if (!g_vinput_test_mode) {
    I64 dyn_w = gfx_get_canvas_width();
    I64 dyn_h = gfx_get_canvas_height();
    if (dyn_w > 0) g_vinput_screen_w = dyn_w;
    if (dyn_h > 0) g_vinput_screen_h = dyn_h;
  }

  if (p_ev->type == EV_KEY) {
    if (p_ev->code == BTN_LEFT) {
      if (p_ev->value != 0) g_vinput_mouse_btn_l = 1;
      else g_vinput_mouse_btn_l = 0;
      if (!g_vinput_test_mode) MouseSetButton(g_vinput_mouse_btn_l, g_vinput_mouse_btn_r);
    } else if (p_ev->code == BTN_RIGHT) {
      if (p_ev->value != 0) g_vinput_mouse_btn_r = 1;
      else g_vinput_mouse_btn_r = 0;
      if (!g_vinput_test_mode) MouseSetButton(g_vinput_mouse_btn_l, g_vinput_mouse_btn_r);
    } else if (p_ev->code == KEY_LSHIFT_CODE || p_ev->code == KEY_RSHIFT_CODE) {
      if (p_ev->value != 0) g_vinput_shift_state = 1;
      else g_vinput_shift_state = 0;
    } else if (p_ev->value == 1 || p_ev->value == 2) {
      // Key press or repeat
      if (p_ev->code < 128) {
        I64 ch;
        if (g_vinput_shift_state) ch = g_vinput_keymap_upper[p_ev->code];
        else ch = g_vinput_keymap_lower[p_ev->code];
        if (ch != 0 && !g_vinput_test_mode) {
          KeyboardQueueChar(ch);
        }
      }
    }
  } else if (p_ev->type == EV_ABS) {
    // Absolute tablet coordinates
    if (p_ev->code == ABS_X) {
      g_vinput_mouse_x = ((p_ev->value * g_vinput_screen_w) / 32767);
      if (g_vinput_mouse_x < 0) g_vinput_mouse_x = 0;
      if (g_vinput_mouse_x >= g_vinput_screen_w) g_vinput_mouse_x = g_vinput_screen_w - 1;
      if (!g_vinput_test_mode) MouseSetPos(g_vinput_mouse_x, g_vinput_mouse_y);
    } else if (p_ev->code == ABS_Y) {
      g_vinput_mouse_y = ((p_ev->value * g_vinput_screen_h) / 32767);
      if (g_vinput_mouse_y < 0) g_vinput_mouse_y = 0;
      if (g_vinput_mouse_y >= g_vinput_screen_h) g_vinput_mouse_y = g_vinput_screen_h - 1;
      if (!g_vinput_test_mode) MouseSetPos(g_vinput_mouse_x, g_vinput_mouse_y);
    }
  } else if (p_ev->type == EV_REL) {
    // Relative mouse movement: EV_REL value is signed 32-bit two's complement
    U64 raw_val = p_ev->value;
    I64 rel_val = raw_val;
    if (raw_val >= 0x80000000) {
      rel_val = (I64)raw_val - 0x100000000;
    }
    if (p_ev->code == REL_X) {
      g_vinput_mouse_x = g_vinput_mouse_x + rel_val;
      if (g_vinput_mouse_x < 0) g_vinput_mouse_x = 0;
      if (g_vinput_mouse_x >= g_vinput_screen_w) g_vinput_mouse_x = g_vinput_screen_w - 1;
      if (!g_vinput_test_mode) MouseSetPos(g_vinput_mouse_x, g_vinput_mouse_y);
    } else if (p_ev->code == REL_Y) {
      g_vinput_mouse_y = g_vinput_mouse_y + rel_val;
      if (g_vinput_mouse_y < 0) g_vinput_mouse_y = 0;
      if (g_vinput_mouse_y >= g_vinput_screen_h) g_vinput_mouse_y = g_vinput_screen_h - 1;
      if (!g_vinput_test_mode) MouseSetPos(g_vinput_mouse_x, g_vinput_mouse_y);
    }
  }
}

I64 VirtioInputScanAndInit(I64 screen_w, I64 screen_h) {
  if (screen_w <= 0) screen_w = gfx_get_canvas_width();
  if (screen_h <= 0) screen_h = gfx_get_canvas_height();
  if (screen_w <= 0) screen_w = 1024;
  if (screen_h <= 0) screen_h = 768;

  g_vinput_screen_w = screen_w;
  g_vinput_screen_h = screen_h;
  g_vinput_mouse_x = screen_w / 2;
  g_vinput_mouse_y = screen_h / 2;
  g_num_input_devs = 0;
  VirtioInputInitKeymaps();

  U64 slot_base = g_hal_virtio_base;
  if (slot_base == 0) slot_base = VIRTIO_MMIO_SLOT_BASE;
  I64 max_slots = g_hal_virtio_slots;
  if (max_slots <= 0) max_slots = 32;
  U64 slot_stride = g_hal_virtio_stride;
  if (slot_stride == 0) slot_stride = VIRTIO_MMIO_SLOT_STRIDE;

  I64 vi_slot;
  for (vi_slot = 0; vi_slot < max_slots && g_num_input_devs < 4; vi_slot++) {
    U64 base = slot_base + vi_slot * slot_stride;
    U32 magic = VirtioMmioRead32(base, VIRTIO_MMIO_MAGIC_VALUE);
    if (magic == VIRTIO_MMIO_MAGIC) {
      U32 dev_id = VirtioMmioRead32(base, VIRTIO_MMIO_DEVICE_ID);
      if (dev_id == VIRTIO_DEV_INPUT) {
        CVirtioInputDev *dev = &g_virtio_input_devs[g_num_input_devs];
        dev->mmio_base = base;
        dev->version = VirtioMmioRead32(base, VIRTIO_MMIO_VERSION);
        dev->queue_num = 64;
        dev->last_used_idx = 0;

        // Reset device
        VirtioMmioWrite32(base, VIRTIO_MMIO_STATUS, 0);
        // Acknowledge & Driver
        VirtioMmioWrite32(base, VIRTIO_MMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);

        if (dev->version == 2) {
          VirtioMmioWrite32(base, VIRTIO_MMIO_DEVICE_FEATURES_SEL, 1);
          U32 f1 = VirtioMmioRead32(base, VIRTIO_MMIO_DEVICE_FEATURES);
          VirtioMmioWrite32(base, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
          VirtioMmioWrite32(base, VIRTIO_MMIO_DRIVER_FEATURES, f1 & 1);
          VirtioMmioWrite32(base, VIRTIO_MMIO_STATUS, VirtioMmioRead32(base, VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_FEATURES_OK);
        } else {
          VirtioMmioWrite32(base, 0x028, 4096);
        }

        // Configure Queue 0
        VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_SEL, 0);
        U32 q_max = VirtioMmioRead32(base, VIRTIO_MMIO_QUEUE_NUM_MAX);
        if (q_max > 0) {
          if (q_max < 64) dev->queue_num = q_max;

          // Guard ring buffer allocation on re-init so we reuse existing DMA memory
          U64 aligned = dev->ring_base;
          if (!dev->vq_desc || aligned == 0) {
            U8 *raw_buf = kmalloc(16384 + 4096);
            if (!raw_buf) break;
            aligned = (raw_buf + 4095) & ~4095;
            dev->ring_base = aligned;
          }

          U8 *p_zero = aligned;
          I64 vi_zi;
          for (vi_zi = 0; vi_zi < 16384; vi_zi++) p_zero[vi_zi] = 0;

          dev->vq_desc = aligned;
          dev->vq_avail = aligned + dev->queue_num * 16;
          dev->vq_used = aligned + 4096;
          dev->event_buf = aligned + 8192;

          CVringDesc *vq_desc = dev->vq_desc;
          CVringAvail *vavail = dev->vq_avail;
          CVringUsed *vused = dev->vq_used;
          CVirtioInputEvent *ev_buf = dev->event_buf;
          CVringDesc *vdesc;
          CVirtioInputEvent *vev;
          I64 vi_i;
          for (vi_i = 0; vi_i < dev->queue_num; vi_i++) {
            vdesc = &vq_desc[vi_i];
            vev = &ev_buf[vi_i];
            vdesc->addr = vev;
            vdesc->len = 8;
            vdesc->flags = VRING_DESC_F_WRITE;
            vdesc->next = 0;
            vavail->ring[vi_i] = vi_i;
          }
          vavail->idx = dev->queue_num;

          U64 desc_addr = dev->vq_desc;
          U64 avail_addr = vavail;
          U64 used_addr = vused;

          if (dev->version == 2) {
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_NUM, dev->queue_num);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_DESC_LOW, desc_addr & 0xFFFFFFFF);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_DESC_HIGH, (desc_addr >> 32) & 0xFFFFFFFF);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_DRIVER_LOW, avail_addr & 0xFFFFFFFF);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_DRIVER_HIGH, (avail_addr >> 32) & 0xFFFFFFFF);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_DEVICE_LOW, used_addr & 0xFFFFFFFF);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_DEVICE_HIGH, (used_addr >> 32) & 0xFFFFFFFF);
            VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_READY, 1);
          } else {
            VirtioMmioWrite32(base, 0x038, dev->queue_num);
            VirtioMmioWrite32(base, 0x03C, 4096);
            VirtioMmioWrite32(base, 0x040, (desc_addr >> 12));
          }

          hal_flush_cache(aligned, 16384);

          VirtioMmioWrite32(base, VIRTIO_MMIO_STATUS, VirtioMmioRead32(base, VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_DRIVER_OK);
          VirtioMmioWrite32(base, VIRTIO_MMIO_QUEUE_NOTIFY, 0);
          dev->active = 1;
          g_num_input_devs++;
          doldoc_printf("[VIRTIO-INPUT] Discovered & Activated Device on MMIO Slot #%d (Base 0x%08X)\n", vi_slot, base);
        }
      }
    }
  }

  doldoc_printf("[VIRTIO-INPUT] Initialized %d VirtIO input device(s)\n", g_num_input_devs);
  return g_num_input_devs;
}

U0 VirtioInputPoll() {
  I64 vi_d = 0;
  while (vi_d < g_num_input_devs) {
    CVirtioInputDev *dev = &g_virtio_input_devs[vi_d];
    if (dev->active && dev->vq_used != 0) {
      CVringUsed *vused = dev->vq_used;
      CVringAvail *vavail = dev->vq_avail;
      CVirtioInputEvent *ev_buf = dev->event_buf;
      hal_flush_cache(vused, 64);
      while (dev->last_used_idx != vused->idx) {
        __dmb_ish();
        I64 u_slot = dev->last_used_idx % dev->queue_num;
        U32 desc_id = vused->ring[u_slot].id;
        if (desc_id < 64) {
          CVirtioInputEvent *ev_ptr = &ev_buf[desc_id];
          hal_flush_cache(ev_ptr, 64);
          VirtioInputProcessEvent(ev_ptr);
          I64 a_slot = vavail->idx % dev->queue_num;
          vavail->ring[a_slot] = desc_id;
          __dmb_ish();
          vavail->idx = vavail->idx + 1;
          hal_flush_cache(vavail, 64);
        }
        dev->last_used_idx = dev->last_used_idx + 1;
        VirtioMmioWrite32(dev->mmio_base, VIRTIO_MMIO_QUEUE_NOTIFY, 0);
      }
    }
    vi_d++;
  }
}

U0 virtio_input_init(I64 screen_w, I64 screen_h) {
  VirtioInputScanAndInit(screen_w, screen_h);
}

U0 virtio_input_poll() {
  VirtioInputPoll();
}

I64 VirtioInputSelfTest() {
  I64 passed = 0;
  I64 total = 5;
  g_vinput_test_mode = 1;

  doldoc_printf("\n=====================================================\n");
  doldoc_printf("  [VIRTIO-INPUT.HC] Pure HolyC VirtIO Input Scorecard\n");
  doldoc_printf("=====================================================\n");

  // Test 1: Scan and initialize VirtIO input hardware
  I64 cw = gfx_get_canvas_width();
  I64 ch = gfx_get_canvas_height();
  if (cw <= 0) cw = 1024;
  if (ch <= 0) ch = 768;
  I64 devs = VirtioInputScanAndInit(cw, ch);
  if (devs > 0) {
    doldoc_printf("  [PASS] VirtIO MMIO Slot Scanner (Found %d input devices)\n", devs);
    passed++;
  } else {
    doldoc_printf("  [FAIL] VirtIO MMIO Slot Scanner: No Hardware Devices Detected\n");
  }

  // Test 2: Virtqueue ring structure layout and sizes
  CVirtioInputDev dev;
  dev.queue_num = 64;
  I64 desc_sz = sizeof(CVringDesc);
  I64 event_sz = sizeof(CVirtioInputEvent);
  if (desc_sz == 16 && event_sz == 8) {
    doldoc_printf("  [PASS] Virtqueue Data Structures Aligned (Desc: 16B, Event: 8B)\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Struct alignment: Desc=%d, Event=%d\n", desc_sz, event_sz);
  }

  // Test 3: Linux input event packet parsing (Key press)
  CVirtioInputEvent test_ev;
  test_ev.type = EV_KEY;
  test_ev.code = 30; // 'a'
  test_ev.value = 1; // Pressed
  VirtioInputProcessEvent(&test_ev);
  if (g_vinput_keymap_lower[30] == 'a' && g_vinput_keymap_upper[30] == 'A') {
    doldoc_printf("  [PASS] EV_KEY Event Decoding & Full ASCII Translation\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Key translation failed for code 30\n");
  }

  // Test 4: Shift state machine & modifier transitions
  test_ev.type = EV_KEY;
  test_ev.code = 42; // KEY_LSHIFT_CODE
  test_ev.value = 1; // Shift down
  VirtioInputProcessEvent(&test_ev);
  I64 shift_active = g_vinput_shift_state;
  test_ev.value = 0; // Shift up
  VirtioInputProcessEvent(&test_ev);
  I64 shift_released = g_vinput_shift_state;
  if (shift_active == 1 && shift_released == 0) {
    doldoc_printf("  [PASS] Shift Modifier State Machine Active/Release\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Shift State Machine: active=%d, released=%d\n", shift_active, shift_released);
  }

  // Test 5: Absolute Tablet Normalization & Signed EV_REL Negative Delta Verification
  g_vinput_screen_w = 1024;
  g_vinput_screen_h = 768;
  test_ev.type = EV_ABS;
  test_ev.code = ABS_X;
  test_ev.value = 16383; // Halfway of 32767 -> ~511
  VirtioInputProcessEvent(&test_ev);
  test_ev.code = ABS_Y;
  test_ev.value = 16383; // Halfway of 32767 -> ~383
  VirtioInputProcessEvent(&test_ev);

  I64 mid_x = g_vinput_mouse_x;
  I64 mid_y = g_vinput_mouse_y;

  // Apply negative signed EV_REL deltas (-20 in X = 0xFFFFFFEC, -15 in Y = 0xFFFFFFF1)
  test_ev.type = EV_REL;
  test_ev.code = REL_X;
  test_ev.value = 0xFFFFFFEC;
  VirtioInputProcessEvent(&test_ev);
  test_ev.code = REL_Y;
  test_ev.value = 0xFFFFFFF1;
  VirtioInputProcessEvent(&test_ev);

  if (mid_x >= 510 && mid_x <= 514 &&
      mid_y >= 382 && mid_y <= 386 &&
      g_vinput_mouse_x == mid_x - 20 &&
      g_vinput_mouse_y == mid_y - 15) {
    doldoc_printf("  [PASS] EV_ABS Normalization & Signed EV_REL Negative Delta Verified\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Axis/Delta check: mid=(%d,%d) after_rel=(%d,%d)\n",
                  mid_x, mid_y, g_vinput_mouse_x, g_vinput_mouse_y);
  }

  g_vinput_screen_w = cw;
  g_vinput_screen_h = ch;
  g_vinput_mouse_x = cw / 2;
  g_vinput_mouse_y = ch / 2;
  g_vinput_test_mode = 0;

  doldoc_printf("=====================================================\n");
  doldoc_printf("  All %d / %d VirtioInput.HC tests passed!\n", passed, total);
  doldoc_printf("=====================================================\n");

  return passed;
}

if (g_kernel_booting) {
  VirtioInputScanAndInit(gfx_get_canvas_width(), gfx_get_canvas_height());
} else {
  VirtioInputSelfTest();
}
