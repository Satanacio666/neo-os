// ==============================================================================
// apps/GfxDevice.HC - NeoOS unified graphics device (P4.1)
// ------------------------------------------------------------------------------
// One target resolver, one damage tracker, one present, and the VirtIO-GPU 2D
// transport — merged from the old GfxBackend.HC + VirtioGpu.HC. The device is a
// 2D blitter for P4: the guest software-renders into a surface and the device
// presents it (CPU copy or VirtIO-GPU DMA). Virgl/Venus 3D is deferred to P9.
//
// The single damage tracker lives in Render.HC (g_canv.dirty); GfxDeviceDamage()
// and GfxPresent() are the only writers of the present path.
// ==============================================================================

#define GFX_MODE_CPU_SW    0
#define GFX_MODE_GPU_HW    1
#define GFX_MODE_SMP_TILED 2

#define GFX_BUFFER_DOUBLE      0
#define GFX_BUFFER_DIRECT_VRAM 1

#define RASTER_SHADE_FLAT      0
#define RASTER_SHADE_GOURAUD   1
#define RASTER_SHADE_WIREFRAME 2

class CGfxDeviceState {
  I64 mode;
  I64 buffering;
  I64 shading;
  U8  name[64];
  U64 ops_counter;
  U64 dma_bytes;
};

CGfxDeviceState g_gdev;

// ==============================================================================
// VirtIO-GPU 2D transport (moved from VirtioGpu.HC; command sizes corrected)
// ==============================================================================
#define VIRTIO_DEV_GPU 16
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

#define VRING_DESC_F_NEXT  1
#define VRING_DESC_F_WRITE 2

#define VIRTIO_GPU_CMD_GET_DISPLAY_INFO        0x0100
#define VIRTIO_GPU_CMD_RESOURCE_CREATE_2D      0x0101
#define VIRTIO_GPU_CMD_RESOURCE_UNREF          0x0102
#define VIRTIO_GPU_CMD_SET_SCANOUT             0x0103
#define VIRTIO_GPU_CMD_RESOURCE_FLUSH          0x0104
#define VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D     0x0105
#define VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING 0x0106
#define VIRTIO_GPU_CMD_RESOURCE_DETACH_BACKING 0x0107

#define VIRTIO_GPU_RESP_OK_NODATA              0x1100
#define VIRTIO_GPU_RESP_OK_DISPLAY_INFO        0x1101

#define VIRTIO_GPU_FORMAT_B8G8R8X8_UNORM       2

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

class CVirtioGpuCtrlHdr {
  U32 type;
  U32 flags;
  U64 fence_id;
  U32 ctx_id;
  U32 padding;
};

class CVirtioGpuRect {
  U32 x;
  U32 y;
  U32 width;
  U32 height;
};

class CVirtioGpuResourceCreate2D {
  CVirtioGpuCtrlHdr hdr;
  U32 resource_id;
  U32 format;
  U32 width;
  U32 height;
};

class CVirtioGpuSetScanout {
  CVirtioGpuCtrlHdr hdr;
  CVirtioGpuRect r;
  U32 scanout_id;
  U32 resource_id;
};

class CVirtioGpuResourceFlush {
  CVirtioGpuCtrlHdr hdr;
  CVirtioGpuRect r;
  U32 resource_id;
  U32 padding;
};

class CVirtioGpuTransferToHost2D {
  CVirtioGpuCtrlHdr hdr;
  CVirtioGpuRect r;
  U64 offset;
  U32 resource_id;
  U32 padding;
};

class CVirtioGpuAttachBackingReq {
  CVirtioGpuCtrlHdr hdr;
  U32 resource_id;
  U32 nr_entries;
  U64 mem_addr;
  U32 mem_len;
  U32 mem_pad;
};

class CVirtioGpuDev {
  U64 mmio_base;
  U32 version;
  U32 queue_num;
  I64 active;
  U64 ring_base;
  CVringDesc *vq_desc;
  CVringAvail *vq_avail;
  CVringUsed *vq_used;
  U32 width;
  U32 height;
  U32 pitch;
  U64 cmd_buf;
  U64 resp_buf;
};

CVirtioGpuDev g_vgpu;

U32 VGpuMmioRead32(U64 base, U64 offset) {
  return __mmio_r32(base + offset);
}

U0 VGpuMmioWrite32(U64 base, U64 offset, U32 val) {
  __mmio_w32(base + offset, val);
}

I64 VirtioGpuSendCmd(U64 cmd, U32 cmd_size, U64 resp, U32 resp_size) {
  if (g_vgpu.active == 0) return -1;
  U64 b = g_vgpu.mmio_base;

  CVirtioGpuCtrlHdr *rhdr = resp;
  rhdr->type = 0;

  CVringDesc *vq_desc = g_vgpu.vq_desc;
  CVringDesc *d0 = &vq_desc[0];
  d0->addr = cmd;
  d0->len = cmd_size;
  d0->flags = VRING_DESC_F_NEXT;
  d0->next = 1;

  CVringDesc *d1 = &vq_desc[1];
  d1->addr = resp;
  d1->len = resp_size;
  d1->flags = VRING_DESC_F_WRITE;
  d1->next = 0;

  CVringUsed *vused = g_vgpu.vq_used;
  U16 last_used = vused->idx;

  CVringAvail *vavail = g_vgpu.vq_avail;
  U16 a_idx = vavail->idx;
  vavail->ring[a_idx % g_vgpu.queue_num] = 0;
  __dmb_ish();
  vavail->idx = a_idx + 1;

  hal_flush_cache(cmd, cmd_size);
  hal_flush_cache(resp, resp_size);
  hal_flush_cache(g_vgpu.ring_base, 4096);

  VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_NOTIFY, 0);

  I64 vg_timeout = 5000000;
  while (vused->idx == last_used && vg_timeout > 0) {
    hal_flush_cache(g_vgpu.vq_used, 64);
    hal_flush_cache(resp, resp_size);
    vg_timeout--;
  }

  if (vg_timeout == 0) return -1;
  if (rhdr->type != VIRTIO_GPU_RESP_OK_NODATA && rhdr->type != VIRTIO_GPU_RESP_OK_DISPLAY_INFO) {
    return -1;
  }
  return 0;
}

I64 VirtioGpuInit() {
  if (g_vgpu.active && g_vgpu.ring_base != 0) {
    return 0;
  }

  I64 cw = gfx_get_canvas_width();
  I64 ch = gfx_get_canvas_height();
  I64 cp = gfx_get_canvas_pitch();
  if (cw <= 0) cw = 1024;
  if (ch <= 0) ch = 768;
  if (cp <= 0) cp = cw;

  g_vgpu.mmio_base = 0;
  g_vgpu.active = 0;
  g_vgpu.width = cw;
  g_vgpu.height = ch;
  g_vgpu.pitch = cp;

  U64 slot_base = g_hal_virtio_base;
  if (slot_base == 0) slot_base = VIRTIO_MMIO_SLOT_BASE;
  I64 max_slots = g_hal_virtio_slots;
  if (max_slots <= 0) max_slots = 32;
  U64 slot_stride = g_hal_virtio_stride;
  if (slot_stride == 0) slot_stride = VIRTIO_MMIO_SLOT_STRIDE;

  I64 vg_slot;
  for (vg_slot = 0; vg_slot < max_slots; vg_slot++) {
    U64 base = slot_base + vg_slot * slot_stride;
    U32 magic = VGpuMmioRead32(base, VIRTIO_MMIO_MAGIC_VALUE);
    if (magic == VIRTIO_MMIO_MAGIC) {
      U32 dev_id = VGpuMmioRead32(base, VIRTIO_MMIO_DEVICE_ID);
      if (dev_id == VIRTIO_DEV_GPU) {
        g_vgpu.mmio_base = base;
        break;
      }
    }
  }

  if (g_vgpu.mmio_base == 0) {
    return -1;
  }

  U64 b = g_vgpu.mmio_base;

  // 1. Reset device
  VGpuMmioWrite32(b, VIRTIO_MMIO_STATUS, 0);

  // 2. Set ACKNOWLEDGE and DRIVER
  VGpuMmioWrite32(b, VIRTIO_MMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);

  g_vgpu.version = VGpuMmioRead32(b, VIRTIO_MMIO_VERSION);

  // 3. Features
  if (g_vgpu.version == 2) {
    VGpuMmioWrite32(b, VIRTIO_MMIO_DEVICE_FEATURES_SEL, 1);
    U32 f1 = VGpuMmioRead32(b, VIRTIO_MMIO_DEVICE_FEATURES);
    VGpuMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
    VGpuMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES, f1 & 1);
    VGpuMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0);
    VGpuMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES, 0);
    VGpuMmioWrite32(b, VIRTIO_MMIO_STATUS, VGpuMmioRead32(b, VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_FEATURES_OK);
  } else {
    VGpuMmioWrite32(b, 0x028, 4096);
  }

  // 4. Configure Queue 0
  VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_SEL, 0);
  U32 q_max = VGpuMmioRead32(b, VIRTIO_MMIO_QUEUE_NUM_MAX);
  if (q_max == 0) return -1;
  g_vgpu.queue_num = 64;
  if (q_max < 64) g_vgpu.queue_num = q_max;

  U64 aligned = g_vgpu.ring_base;
  if (!g_vgpu.vq_desc || aligned == 0) {
    U8 *raw_buf = kmalloc(32768 + 4096);
    if (!raw_buf) return -1;
    aligned = (raw_buf + 4095) & ~4095;
    g_vgpu.ring_base = aligned;
  }

  U8 *p_zero = aligned;
  I64 vg_zi;
  for (vg_zi = 0; vg_zi < 32768; vg_zi++) p_zero[vg_zi] = 0;

  U64 avail_off = g_vgpu.queue_num * 16;
  U64 avail_end = avail_off + 2 * (3 + g_vgpu.queue_num);
  U64 used_off = (avail_end + 4095) & ~4095;

  g_vgpu.vq_desc = aligned;
  g_vgpu.vq_avail = aligned + avail_off;
  g_vgpu.vq_used = aligned + used_off;
  g_vgpu.cmd_buf = aligned + 8192;
  g_vgpu.resp_buf = aligned + 12288;

  CVringAvail *vavail = g_vgpu.vq_avail;
  CVringUsed *vused = g_vgpu.vq_used;
  vavail->flags = 0;
  vavail->idx = 0;
  vused->flags = 0;
  vused->idx = 0;

  U64 desc_addr = g_vgpu.vq_desc;
  U64 avail_addr = g_vgpu.vq_avail;
  U64 used_addr = g_vgpu.vq_used;

  if (g_vgpu.version == 2) {
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_NUM, g_vgpu.queue_num);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_DESC_LOW, desc_addr & 0xFFFFFFFF);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_DESC_HIGH, (desc_addr >> 32) & 0xFFFFFFFF);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_DRIVER_LOW, avail_addr & 0xFFFFFFFF);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_DRIVER_HIGH, (avail_addr >> 32) & 0xFFFFFFFF);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_DEVICE_LOW, used_addr & 0xFFFFFFFF);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_DEVICE_HIGH, (used_addr >> 32) & 0xFFFFFFFF);
    VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_READY, 1);
  } else {
    VGpuMmioWrite32(b, 0x038, g_vgpu.queue_num);
    VGpuMmioWrite32(b, 0x03C, 4096);
    VGpuMmioWrite32(b, 0x040, (desc_addr >> 12));
  }

  hal_flush_cache(aligned, 32768);

  // 5. DRIVER_OK
  VGpuMmioWrite32(b, VIRTIO_MMIO_STATUS, VGpuMmioRead32(b, VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_DRIVER_OK);
  g_vgpu.active = 1;

  // 6. Create 2D Resource (P4.1: send the FULL 40-byte struct, was truncated to 32)
  CVirtioGpuResourceCreate2D *c2d = g_vgpu.cmd_buf;
  c2d->hdr.type = VIRTIO_GPU_CMD_RESOURCE_CREATE_2D;
  c2d->hdr.flags = 0;
  c2d->hdr.fence_id = 0;
  c2d->hdr.ctx_id = 0;
  c2d->hdr.padding = 0;
  c2d->resource_id = 1;
  c2d->format = VIRTIO_GPU_FORMAT_B8G8R8X8_UNORM;
  c2d->width = g_vgpu.width;
  c2d->height = g_vgpu.height;

  CVirtioGpuCtrlHdr *resp = g_vgpu.resp_buf;
  if (VirtioGpuSendCmd(c2d, 40, resp, 24) != 0 || resp->type != VIRTIO_GPU_RESP_OK_NODATA) {
    g_vgpu.active = 0;
    return -1;
  }

  // 7. Attach Backing (48-byte struct; matches the spec)
  U32 *back = gfx_get_backbuffer();
  if (back) {
    CVirtioGpuAttachBackingReq *att = g_vgpu.cmd_buf;
    att->hdr.type = VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING;
    att->hdr.flags = 0;
    att->hdr.fence_id = 0;
    att->hdr.ctx_id = 0;
    att->hdr.padding = 0;
    att->resource_id = 1;
    att->nr_entries = 1;
    att->mem_addr = back;
    att->mem_len = g_vgpu.pitch * g_vgpu.height * 4;
    att->mem_pad = 0;

    if (VirtioGpuSendCmd(att, 48, resp, 24) != 0 || resp->type != VIRTIO_GPU_RESP_OK_NODATA) {
      g_vgpu.active = 0;
      return -1;
    }

    // 8. Set Scanout (48-byte struct; matches the spec)
    CVirtioGpuSetScanout *scan = g_vgpu.cmd_buf;
    scan->hdr.type = VIRTIO_GPU_CMD_SET_SCANOUT;
    scan->hdr.flags = 0;
    scan->hdr.fence_id = 0;
    scan->hdr.ctx_id = 0;
    scan->hdr.padding = 0;
    scan->r.x = 0;
    scan->r.y = 0;
    scan->r.width = g_vgpu.width;
    scan->r.height = g_vgpu.height;
    scan->scanout_id = 0;
    scan->resource_id = 1;

    if (VirtioGpuSendCmd(scan, 48, resp, 24) != 0 || resp->type != VIRTIO_GPU_RESP_OK_NODATA) {
      g_vgpu.active = 0;
      return -1;
    }
  }

  return 0;
}

I64 VirtioGpuFlushRect(I64 x, I64 y, I64 w, I64 h) {
  if (g_vgpu.active == 0) return -1;

  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x + w > g_vgpu.width) w = g_vgpu.width - x;
  if (y + h > g_vgpu.height) h = g_vgpu.height - y;
  if (w <= 0 || h <= 0) return 0;

  // P4.1: send the FULL 56-byte struct (was truncated to 48 — dropped resource_id)
  CVirtioGpuTransferToHost2D *t2d = g_vgpu.cmd_buf;
  t2d->hdr.type = VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D;
  t2d->hdr.flags = 0;
  t2d->hdr.fence_id = 0;
  t2d->hdr.ctx_id = 0;
  t2d->hdr.padding = 0;
  t2d->r.x = x;
  t2d->r.y = y;
  t2d->r.width = w;
  t2d->r.height = h;
  t2d->offset = (y * g_vgpu.pitch + x) * 4;
  t2d->resource_id = 1;
  t2d->padding = 0;

  CVirtioGpuCtrlHdr *resp = g_vgpu.resp_buf;
  if (VirtioGpuSendCmd(t2d, 56, resp, 24) != 0 || resp->type != VIRTIO_GPU_RESP_OK_NODATA) {
    return -1;
  }

  CVirtioGpuResourceFlush *rf = g_vgpu.cmd_buf;
  rf->hdr.type = VIRTIO_GPU_CMD_RESOURCE_FLUSH;
  rf->hdr.flags = 0;
  rf->hdr.fence_id = 0;
  rf->hdr.ctx_id = 0;
  rf->hdr.padding = 0;
  rf->r.x = x;
  rf->r.y = y;
  rf->r.width = w;
  rf->r.height = h;
  rf->resource_id = 1;
  rf->padding = 0;

  if (VirtioGpuSendCmd(rf, 48, resp, 24) != 0 || resp->type != VIRTIO_GPU_RESP_OK_NODATA) {
    return -1;
  }
  return 0;
}

I64 VirtioGpuFlushFull() {
  return VirtioGpuFlushRect(0, 0, g_vgpu.width, g_vgpu.height);
}

I64 VirtioGpuIsAvailable() {
  return g_vgpu.active;
}

// ==============================================================================
// Unified device layer — one target resolver, one damage tracker, one present.
// ==============================================================================
U0 GfxDeviceInit() {
  g_gdev.mode = GFX_MODE_CPU_SW;
  g_gdev.buffering = GFX_BUFFER_DOUBLE;
  g_gdev.shading = RASTER_SHADE_GOURAUD;
  strcpy(g_gdev.name, "CPU Software (UEFI)");
  g_gdev.ops_counter = 0;
  g_gdev.dma_bytes = 0;
  g_gfx_cfg.mode = GFX_MODE_CPU_SW;
  RenderSetZeroRamMode(0);
}

U0 GfxDeviceSetMode(I64 m) {
  g_gdev.mode = m;
  g_gfx_cfg.mode = m;
  if (m == GFX_MODE_GPU_HW) {
    strcpy(g_gdev.name, "VirtIO-GPU Hardware");
  } else if (m == GFX_MODE_SMP_TILED) {
    strcpy(g_gdev.name, "SMP Multi-Core (4C)");
  } else {
    strcpy(g_gdev.name, "CPU Software (UEFI)");
  }
}

I64 GfxDeviceGetMode() { return g_gdev.mode; }
U8* GfxDeviceGetName() { return g_gdev.name; }

U0 GfxDeviceSetBuffering(I64 m) {
  g_gdev.buffering = m;
  RenderSetZeroRamMode(m == GFX_BUFFER_DIRECT_VRAM ? 1 : 0);
}
I64 GfxDeviceGetBuffering() { return g_gdev.buffering; }

I64 GfxDeviceIsZeroRam() {
  return (g_gdev.buffering == GFX_BUFFER_DIRECT_VRAM || g_gfx_cfg.buffer_mode == 1) ? 1 : 0;
}
U0 GfxDeviceSetZeroRam(I64 en) {
  GfxDeviceSetBuffering(en ? GFX_BUFFER_DIRECT_VRAM : GFX_BUFFER_DOUBLE);
}

U0 GfxDeviceSetShading(I64 s) { g_gdev.shading = s; }
I64 GfxDeviceGetShading() { return g_gdev.shading; }

// The one target resolver: where the renderer draws. Delegates to Render, which
// owns the double-buffer / zero-RAM decision.
U32* GfxDeviceTarget() {
  return RenderGetTargetBuffer();
}

// The one damage tracker: expands Render's single dirty rect.
U0 GfxDeviceDamage(I64 x, I64 y, I64 w, I64 h) {
  gfx_dirty_expand(x, y, w, h);
}

// The one present: copy the dirty region to the front buffer (double-buffered),
// or nothing in direct-VRAM mode; then DMA to the host if the GPU backend is on.
U0 GfxPresent(I64 x, I64 y, I64 w, I64 h, I64 full) {
  if (!GfxDeviceIsZeroRam()) {
    if (full) {
      gfx_swap_buffers();
    } else {
      gfx_swap_rect(x, y, w, h);
    }
  } else {
    gfx_dirty_reset();
  }
  if (g_gdev.mode == GFX_MODE_GPU_HW && VirtioGpuIsAvailable()) {
    if (full) {
      VirtioGpuFlushFull();
    } else {
      VirtioGpuFlushRect(x, y, w, h);
    }
  }
  g_gdev.ops_counter = g_gdev.ops_counter + 1;
  g_gdev.dma_bytes = g_gdev.dma_bytes + (w * h * 4);
}

U0 GfxDeviceFastClear(U32 *dst_pixels, I64 num_px, U32 clr_val) {
  I64 fc_idx = 0;
  while (fc_idx + 8 <= num_px) {
    dst_pixels[fc_idx + 0] = clr_val;
    dst_pixels[fc_idx + 1] = clr_val;
    dst_pixels[fc_idx + 2] = clr_val;
    dst_pixels[fc_idx + 3] = clr_val;
    dst_pixels[fc_idx + 4] = clr_val;
    dst_pixels[fc_idx + 5] = clr_val;
    dst_pixels[fc_idx + 6] = clr_val;
    dst_pixels[fc_idx + 7] = clr_val;
    fc_idx = fc_idx + 8;
  }
  while (fc_idx < num_px) {
    dst_pixels[fc_idx] = clr_val;
    fc_idx++;
  }
}

U0 GfxDevicePrintDolDoc() {
  doldoc_printf("$FG,CYAN$=== Sovereign Graphics Device ===$FG$\n");
  doldoc_printf(" Active Backend:   $FG,YELLOW$%s$FG$\n", g_gdev.name);
  doldoc_printf(" Shading / Depth:  $FG,WHITE$%s | %s$FG$\n",
                (g_gdev.shading == RASTER_SHADE_GOURAUD) ? "Gouraud" : "Flat",
                "16-Bit Z");
  doldoc_printf(" Buffering:        $FG,GREEN$%s$FG$\n",
                (g_gdev.buffering == GFX_BUFFER_DOUBLE) ? "Double-Buffered (DDR RAM)" : "Direct VRAM (Zero-RAM)");
  doldoc_printf(" GPU Transport:    $FG,%s$%s$FG$\n",
                VirtioGpuIsAvailable() ? "GREEN" : "PEACH",
                VirtioGpuIsAvailable() ? "VirtIO-GPU 2D (DMA)" : "Unavailable (CPU blit)");
  doldoc_printf(" Ops / Transfers:  %lld ops | %lld bytes\n", g_gdev.ops_counter, g_gdev.dma_bytes);
  doldoc_printf("$FG,CYAN$==================================$FG$\n");
}

I64 GfxDeviceSelfTest() {
  doldoc_printf("\n$FG,CYAN$[GFXDEVICE-TEST] Unified graphics device test suite...$FG$\n");

  GfxDeviceInit();
  if (g_gdev.mode != GFX_MODE_CPU_SW || g_gdev.buffering != GFX_BUFFER_DOUBLE ||
      g_gdev.shading != RASTER_SHADE_GOURAUD) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: default state$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: default state validated.$FG$\n");

  GfxDeviceSetMode(GFX_MODE_GPU_HW);
  if (g_gdev.mode != GFX_MODE_GPU_HW || strcmp(g_gdev.name, "VirtIO-GPU Hardware") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: mode switch$FG$\n");
    return 0;
  }
  GfxDeviceSetMode(GFX_MODE_CPU_SW);
  doldoc_printf("$FG,GREEN$[PASS] Test 2: mode switching validated.$FG$\n");

  GfxDeviceSetBuffering(GFX_BUFFER_DIRECT_VRAM);
  I64 zr_ok = (GfxDeviceGetBuffering() == GFX_BUFFER_DIRECT_VRAM && GfxDeviceTarget() == gfx_get_frontbuffer());
  GfxDeviceSetBuffering(GFX_BUFFER_DOUBLE);
  if (!zr_ok) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: zero-RAM target resolution$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: one target resolver validated (zero-RAM vs double-buffer).$FG$\n");

  U32 *t_buf = kmalloc(256 * 4);
  if (!t_buf) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: kmalloc$FG$\n");
    return 0;
  }
  GfxDeviceFastClear(t_buf, 256, 0x11223344);
  I64 clr_ok = 1;
  I64 chk_i = 0;
  while (chk_i < 256) { if (t_buf[chk_i] != 0x11223344) { clr_ok = 0; break; } chk_i++; }
  kfree(t_buf);
  if (!clr_ok) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: fast clear$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: fast clear verified.$FG$\n");

  U64 ops_before = g_gdev.ops_counter;
  GfxPresent(0, 0, gfx_get_canvas_width(), gfx_get_canvas_height(), 1);
  GfxPresent(10, 10, 100, 100, 0);
  if (g_gdev.ops_counter != ops_before + 2) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: present ops counter$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: one present path verified (%s).$FG$\n",
                VirtioGpuIsAvailable() ? "VirtIO-GPU live" : "CPU blit");

  GfxDeviceInit();
  doldoc_printf("\n[GFXDEVICE-PASS] ALL 5 GRAPHICS DEVICE TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  GfxDeviceInit();
  VirtioGpuInit();
} else {
  GfxDeviceSelfTest();
}
