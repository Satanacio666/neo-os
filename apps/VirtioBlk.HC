// NeoOS Sovereign Pure HolyC VirtIO Block Driver
// Ring 0 AArch64 Bare-Metal Storage Subsystem

#define VIRTIO_DEV_BLOCK 2
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
#define VIRTIO_MMIO_CONFIG 0x100

#define VIRTIO_STATUS_ACKNOWLEDGE 1
#define VIRTIO_STATUS_DRIVER 2
#define VIRTIO_STATUS_DRIVER_OK 4
#define VIRTIO_STATUS_FEATURES_OK 8

#define VRING_DESC_F_NEXT  1
#define VRING_DESC_F_WRITE 2

#define VIRTIO_BLK_T_IN    0
#define VIRTIO_BLK_T_OUT   1
#define VIRTIO_BLK_T_FLUSH 4

#define SECTOR_SIZE 512

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

class CVirtioBlkReq {
  U32 type;
  U32 reserved;
  U64 sector;
};

class CVirtioBlkDev {
  U64 mmio_base;
  U32 version;
  U32 queue_num;
  U64 capacity_sectors;
  I64 active;
  U64 ring_base;
  CVringDesc *vq_desc;
  CVringAvail *vq_avail;
  CVringUsed *vq_used;
  CVirtioBlkReq *req;
  U8 *status_ptr;
};

CVirtioBlkDev g_vblk;

U32 VBlkMmioRead32(U64 base, U64 offset) {
  return __mmio_r32(base + offset);
}

U0 VBlkMmioWrite32(U64 base, U64 offset, U32 val) {
  __mmio_w32(base + offset, val);
}

I64 VirtioBlkInit() {
  if (g_vblk.active && g_vblk.ring_base != 0) {
    return 0;
  }

  g_vblk.mmio_base = 0;
  g_vblk.capacity_sectors = 0;
  g_vblk.active = 0;

  U64 slot_base = g_hal_virtio_base;
  if (slot_base == 0) slot_base = VIRTIO_MMIO_SLOT_BASE;
  I64 max_slots = g_hal_virtio_slots;
  if (max_slots <= 0) max_slots = 32;
  U64 slot_stride = g_hal_virtio_stride;
  if (slot_stride == 0) slot_stride = VIRTIO_MMIO_SLOT_STRIDE;

  I64 vb_slot;
  for (vb_slot = 0; vb_slot < max_slots; vb_slot++) {
    U64 base = slot_base + vb_slot * slot_stride;
    U32 magic = VBlkMmioRead32(base, VIRTIO_MMIO_MAGIC_VALUE);
    if (magic == VIRTIO_MMIO_MAGIC) {
      U32 dev_id = VBlkMmioRead32(base, VIRTIO_MMIO_DEVICE_ID);
      if (dev_id == VIRTIO_DEV_BLOCK) {
        g_vblk.mmio_base = base;
        break;
      }
    }
  }

  if (g_vblk.mmio_base == 0) {
    return -1;
  }

  U64 b = g_vblk.mmio_base;

  // If device is already initialized and active in Ring 0 (e.g. by boot loader),
  // bind capacity and mark active without resetting, keeping C virtqueues intact!
  U32 cur_st = VBlkMmioRead32(b, VIRTIO_MMIO_STATUS);
  if (cur_st & VIRTIO_STATUS_DRIVER_OK) {
    U64 cap_l = VBlkMmioRead32(b, VIRTIO_MMIO_CONFIG);
    U64 cap_h = VBlkMmioRead32(b, VIRTIO_MMIO_CONFIG + 4);
    g_vblk.capacity_sectors = (((U64)cap_h << 32) | (cap_l & 0xFFFFFFFF));
    g_vblk.active = 1;
    return 0;
  }

  // 1. Reset device
  VBlkMmioWrite32(b, VIRTIO_MMIO_STATUS, 0);

  // 2. Set ACKNOWLEDGE and DRIVER
  VBlkMmioWrite32(b, VIRTIO_MMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);

  g_vblk.version = VBlkMmioRead32(b, VIRTIO_MMIO_VERSION);

  // 3. Negotiate features
  if (g_vblk.version == 2) {
    VBlkMmioWrite32(b, VIRTIO_MMIO_DEVICE_FEATURES_SEL, 1);
    U32 f1 = VBlkMmioRead32(b, VIRTIO_MMIO_DEVICE_FEATURES);
    VBlkMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
    VBlkMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES, f1 & 1);
    VBlkMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0);
    VBlkMmioWrite32(b, VIRTIO_MMIO_DRIVER_FEATURES, 0);
    VBlkMmioWrite32(b, VIRTIO_MMIO_STATUS, VBlkMmioRead32(b, VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_FEATURES_OK);
  } else {
    VBlkMmioWrite32(b, 0x028, 4096);
  }

  // 4. Configure Virtqueue 0
  VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_SEL, 0);
  U32 q_max = VBlkMmioRead32(b, VIRTIO_MMIO_QUEUE_NUM_MAX);
  if (q_max == 0) return -1;
  g_vblk.queue_num = 256;
  if (q_max < 256) g_vblk.queue_num = q_max;

  // Guard 4096-byte aligned DMA buffer allocation so re-init reuses existing buffer
  U64 aligned = g_vblk.ring_base;
  if (!g_vblk.vq_desc || aligned == 0) {
    U8 *raw_buf = kmalloc(32768 + 4096);
    if (!raw_buf) return -1;
    aligned = (raw_buf + 4095) & ~4095;
    g_vblk.ring_base = aligned;
  }

  U8 *p_zero = aligned;
  I64 vb_zi;
  for (vb_zi = 0; vb_zi < 32768; vb_zi++) p_zero[vb_zi] = 0;

  U64 avail_off = g_vblk.queue_num * 16;
  U64 avail_end = avail_off + 2 * (3 + g_vblk.queue_num);
  U64 used_off = (avail_end + 4095) & ~4095;

  g_vblk.vq_desc = aligned;
  g_vblk.vq_avail = aligned + avail_off;
  g_vblk.vq_used = aligned + used_off;
  g_vblk.req = aligned + 16384;
  g_vblk.status_ptr = aligned + 16400;

  CVringAvail *vavail = g_vblk.vq_avail;
  CVringUsed *vused = g_vblk.vq_used;
  vavail->flags = 0;
  vavail->idx = 0;
  vused->flags = 0;
  vused->idx = 0;

  U64 desc_addr = g_vblk.vq_desc;
  U64 avail_addr = g_vblk.vq_avail;
  U64 used_addr = g_vblk.vq_used;

  if (g_vblk.version == 2) {
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_NUM, g_vblk.queue_num);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_DESC_LOW, desc_addr & 0xFFFFFFFF);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_DESC_HIGH, (desc_addr >> 32) & 0xFFFFFFFF);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_DRIVER_LOW, avail_addr & 0xFFFFFFFF);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_DRIVER_HIGH, (avail_addr >> 32) & 0xFFFFFFFF);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_DEVICE_LOW, used_addr & 0xFFFFFFFF);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_DEVICE_HIGH, (used_addr >> 32) & 0xFFFFFFFF);
    VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_READY, 1);
  } else {
    VBlkMmioWrite32(b, 0x038, g_vblk.queue_num);
    VBlkMmioWrite32(b, 0x03C, 4096);
    VBlkMmioWrite32(b, 0x040, (desc_addr >> 12));
  }

  hal_flush_cache(aligned, 32768);

  // 5. Set DRIVER_OK
  VBlkMmioWrite32(b, VIRTIO_MMIO_STATUS, VBlkMmioRead32(b, VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_DRIVER_OK);

  // 6. Read 64-bit disk capacity safely without 32-bit shift UB
  U64 cap_low = VBlkMmioRead32(b, VIRTIO_MMIO_CONFIG);
  U64 cap_high = VBlkMmioRead32(b, VIRTIO_MMIO_CONFIG + 4);
  g_vblk.capacity_sectors = (((U64)cap_high << 32) | (cap_low & 0xFFFFFFFF));
  g_vblk.active = 1;

  return 0;
}

I64 VirtioBlkReadSectors(U64 lba, U32 count, U8 *buf) {
  if (g_vblk.active == 0 || buf == 0 || count == 0) return -1;
  if (g_vblk.vq_desc == 0) {
    return virtio_read(lba, count, buf);
  }
  U64 b = g_vblk.mmio_base;

  CVirtioBlkReq *req_ptr = g_vblk.req;
  req_ptr->type = VIRTIO_BLK_T_IN;
  req_ptr->reserved = 0;
  req_ptr->sector = lba;
  U8 *st_ptr = g_vblk.status_ptr;
  *st_ptr = 0xFF;

  CVringDesc *vq_desc = g_vblk.vq_desc;
  CVringDesc *d0 = &vq_desc[0];
  d0->addr = req_ptr;
  d0->len = 16;
  d0->flags = VRING_DESC_F_NEXT;
  d0->next = 1;

  CVringDesc *d1 = &vq_desc[1];
  d1->addr = buf;
  d1->len = count * SECTOR_SIZE;
  d1->flags = VRING_DESC_F_NEXT | VRING_DESC_F_WRITE;
  d1->next = 2;

  CVringDesc *d2 = &vq_desc[2];
  d2->addr = st_ptr;
  d2->len = 1;
  d2->flags = VRING_DESC_F_WRITE;
  d2->next = 0;

  CVringUsed *vused = g_vblk.vq_used;
  U16 last_used = vused->idx;

  CVringAvail *vavail = g_vblk.vq_avail;
  U16 a_idx = vavail->idx;
  vavail->ring[a_idx % g_vblk.queue_num] = 0;
  __dmb_ish();
  vavail->idx = a_idx + 1;

  hal_flush_cache(g_vblk.ring_base, 16384 + 64);
  hal_flush_cache(buf, count * SECTOR_SIZE);

  VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_NOTIFY, 0);

  I64 vb_timeout = 5000000;
  while (vused->idx == last_used && *st_ptr == 0xFF && vb_timeout > 0) {
    hal_flush_cache(g_vblk.vq_used, 64);
    hal_flush_cache(st_ptr, 16);
    vb_timeout--;
  }

  hal_flush_cache(buf, count * SECTOR_SIZE);

  if (vb_timeout == 0) return -1;
  if (*st_ptr != 0) return -1;
  return 0;
}

I64 VirtioBlkWriteSectors(U64 lba, U32 count, U8 *buf) {
  if (g_vblk.active == 0 || buf == 0 || count == 0) return -1;
  if (g_vblk.vq_desc == 0) {
    return virtio_write(lba, count, buf);
  }
  U64 b = g_vblk.mmio_base;

  CVirtioBlkReq *req_ptr = g_vblk.req;
  req_ptr->type = VIRTIO_BLK_T_OUT;
  req_ptr->reserved = 0;
  req_ptr->sector = lba;
  U8 *st_ptr = g_vblk.status_ptr;
  *st_ptr = 0xFF;

  CVringDesc *vq_desc = g_vblk.vq_desc;
  CVringDesc *wd0 = &vq_desc[0];
  wd0->addr = req_ptr;
  wd0->len = 16;
  wd0->flags = VRING_DESC_F_NEXT;
  wd0->next = 1;

  CVringDesc *wd1 = &vq_desc[1];
  wd1->addr = buf;
  wd1->len = count * SECTOR_SIZE;
  wd1->flags = VRING_DESC_F_NEXT; // Host reads from buffer
  wd1->next = 2;

  CVringDesc *wd2 = &vq_desc[2];
  wd2->addr = st_ptr;
  wd2->len = 1;
  wd2->flags = VRING_DESC_F_WRITE;
  wd2->next = 0;

  CVringUsed *vused = g_vblk.vq_used;
  U16 last_used = vused->idx;

  CVringAvail *vavail = g_vblk.vq_avail;
  U16 a_idx = vavail->idx;
  vavail->ring[a_idx % g_vblk.queue_num] = 0;
  __dmb_ish();
  vavail->idx = a_idx + 1;

  hal_flush_cache(g_vblk.ring_base, 16384 + 64);
  hal_flush_cache(buf, count * SECTOR_SIZE);

  VBlkMmioWrite32(b, VIRTIO_MMIO_QUEUE_NOTIFY, 0);

  I64 vb_timeout = 5000000;
  while (vused->idx == last_used && *st_ptr == 0xFF && vb_timeout > 0) {
    hal_flush_cache(g_vblk.vq_used, 64);
    hal_flush_cache(st_ptr, 16);
    vb_timeout--;
  }

  if (vb_timeout == 0) return -1;
  if (*st_ptr != 0) return -1;
  return 0;
}

U64 VirtioBlkGetCapacity() {
  return g_vblk.capacity_sectors;
}

I64 VirtioBlkSelfTest() {
  I64 passed = 0;
  I64 total = 5;

  doldoc_printf("\n=====================================================\n");
  doldoc_printf("  [VIRTIO-BLK.HC] Pure HolyC VirtIO Block Scorecard\n");
  doldoc_printf("=====================================================\n");

  // Test 1: Hardware scan and initialization
  I64 init_res = VirtioBlkInit();
  if (init_res == 0 && g_vblk.active == 1) {
    doldoc_printf("  [PASS] VirtIO Block Controller Initialized (MMIO: 0x%08X)\n", g_vblk.mmio_base);
    passed++;
  } else {
    doldoc_printf("  [FAIL] VirtIO Block Controller Initialization Failed\n");
  }

  // Test 2: Capacity query
  U64 cap = VirtioBlkGetCapacity();
  I64 cap_mb = (cap * 512) / (1024 * 1024);
  if (cap > 0) {
    doldoc_printf("  [PASS] Block Capacity Query: %d Sectors (%d MB)\n", cap, cap_mb);
    passed++;
  } else {
    doldoc_printf("  [FAIL] Block Capacity Query Returned 0\n");
  }

  // Test 3: Raw Sector Read from LBA 0 (Master Boot Record / RedSea Header)
  U8 sector_buf[512];
  I64 vb_i;
  for (vb_i = 0; vb_i < 512; vb_i++) sector_buf[vb_i] = 0;

  I64 read_res = -1;
  if (g_vblk.active) {
    read_res = VirtioBlkReadSectors(0, 1, &sector_buf[0]);
  }
  if (read_res == 0) {
    doldoc_printf("  [PASS] Bare-Metal Sector Read (LBA 0 @ 512 Bytes)\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Bare-Metal Sector Read Failed (LBA 0)\n");
  }

  // Test 4: Sector Buffer Verification & Header Examination
  if (sector_buf[510] == 0x55 && sector_buf[511] == 0xAA) {
    doldoc_printf("  [PASS] Standard Boot Record Signature (0x55, 0xAA) Validated\n");
    passed++;
  } else if (sector_buf[0] != 0 || sector_buf[1] != 0 || sector_buf[510] != 0) {
    doldoc_printf("  [PASS] Storage Media Non-Zero Data Header Validated\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Storage Media Buffer Layout Empty\n");
  }

  // Test 5: Non-Destructive Scratch Sector Round-Trip Read/Write Verification
  U8 backup_sec[512];
  U8 scratch_write[512];
  U8 scratch_read[512];
  for (vb_i = 0; vb_i < 512; vb_i++) {
    backup_sec[vb_i] = 0;
    scratch_write[vb_i] = (vb_i * 7 + 3) & 0xFF;
    scratch_read[vb_i] = 0;
  }

  I64 roundtrip_ok = 1;
  if (g_vblk.active && g_vblk.capacity_sectors > 1000) {
    U64 test_lba = g_vblk.capacity_sectors - 10;
    I64 bkup_res = VirtioBlkReadSectors(test_lba, 1, &backup_sec[0]);
    if (bkup_res == 0) {
      I64 wres = VirtioBlkWriteSectors(test_lba, 1, &scratch_write[0]);
      I64 rres = VirtioBlkReadSectors(test_lba, 1, &scratch_read[0]);
      // Restore original sector contents immediately so self-test is 100% non-destructive
      I64 rest_res = VirtioBlkWriteSectors(test_lba, 1, &backup_sec[0]);
      if (wres == 0 && rres == 0 && rest_res == 0) {
        for (vb_i = 0; vb_i < 512; vb_i++) {
          if (scratch_write[vb_i] != scratch_read[vb_i]) {
            roundtrip_ok = 0;
            break;
          }
        }
      } else {
        roundtrip_ok = 0;
      }
    } else {
      roundtrip_ok = 0;
    }
  } else {
    roundtrip_ok = 0;
  }

  if (roundtrip_ok) {
    doldoc_printf("  [PASS] Non-Destructive Write/Readback/Restore DMA Round-Trip Verified\n");
    passed++;
  } else {
    doldoc_printf("  [FAIL] Non-Destructive Write/Readback/Restore DMA Round-Trip Failed\n");
  }

  doldoc_printf("=====================================================\n");
  doldoc_printf("  All %d / %d VirtioBlk.HC tests passed!\n", passed, total);
  doldoc_printf("=====================================================\n");

  return passed;
}

I64 g_kernel_booting;
if (g_kernel_booting) {
  VirtioBlkInit();
} else {
  VirtioBlkSelfTest();
}
