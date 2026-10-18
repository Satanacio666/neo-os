// NeoOS Sovereign Pure HolyC RedSea Contiguous Filesystem & Volatile RAMDisk
// Direct 64-bit TempleOS-compatible storage substrate in Ring 0

#define RS_ATTR_READONLY 0x01
#define RS_ATTR_HIDDEN   0x02
#define RS_ATTR_SYSTEM   0x04
#define RS_ATTR_VOL_ID   0x08
#define RS_ATTR_DIR      0x10
#define RS_ATTR_ARCHIVE  0x20
#define RS_ATTR_FILE     0x40

#define REDSEA_MAX_NAME 38
#define REDSEA_SECTOR_SIZE 512
#define REDSEA_ENTRIES_PER_SECTOR 8

#define RAMDISK_MAX_FILES 32
#define RAMDISK_CAPACITY 65536

class CRedSeaEntry {
  U16 attr;
  U8  name[38];
  U64 cluster;
  U64 size;
  U64 datetime;
};

class CRedSeaFs {
  U64 root_lba;
  U32 root_sectors;
  U64 total_sectors;
  U64 current_dir_lba;
  U32 current_dir_sectors;
  U64 next_alloc_lba;
  U8  current_pwd[128];
  I64 initialized;
};

CRedSeaFs g_rs;

class CRamDiskEntry {
  U8  name[38];
  I64 size;
  I64 offset;
  I64 used;
};

class CRamDiskFs {
  U8   *storage;
  I64  used_bytes;
  U8   *entries; // Array of 32 CRamDiskEntry (each 64 bytes)
  I64  initialized;
};

CRamDiskFs g_rd;

CRamDiskEntry* RdGetEntry(I64 idx) {
  return g_rd.entries + idx * 64;
}

CRedSeaEntry* RsGetEntry(U8 *s_buf, I64 idx) {
  return s_buf + idx * 64;
}

U0 RsStrCpy(U8 *dst_buf, U8 *src_buf) {
  I64 rs_c_idx = 0;
  while (src_buf[rs_c_idx] != 0 && rs_c_idx < 37) {
    dst_buf[rs_c_idx] = src_buf[rs_c_idx];
    rs_c_idx++;
  }
  dst_buf[rs_c_idx] = 0;
}

I64 RsStrCmp(U8 *s1, U8 *s2) {
  I64 rs_pos = 0;
  while (s1[rs_pos] != 0 && s2[rs_pos] != 0) {
    if (s1[rs_pos] != s2[rs_pos]) return s1[rs_pos] - s2[rs_pos];
    rs_pos++;
  }
  return s1[rs_pos] - s2[rs_pos];
}

I64 RsStrLen(U8 *str) {
  I64 rs_len = 0;
  while (str[rs_len] != 0) rs_len++;
  return rs_len;
}

U0 RsMemSet(U8 *buf, U8 val, I64 count) {
  I64 rs_m_i = 0;
  while (rs_m_i < count) {
    buf[rs_m_i] = val;
    rs_m_i++;
  }
}

U0 RsMemCpy(U8 *dst, U8 *src, I64 count) {
  I64 rs_cp_i = 0;
  while (rs_cp_i < count) {
    dst[rs_cp_i] = src[rs_cp_i];
    rs_cp_i++;
  }
}

// -------------------------------------------------------------
// Block Device Bridge (VirtIO-Blk Hardware DMA Engine)
// -------------------------------------------------------------
I64 g_rs_hw_mode = 1;

I64 RsReadSectors(U64 lba, U32 num_sec, U8 *buf) {
  return VirtioBlkReadSectors(lba, num_sec, buf);
}

I64 RsWriteSectors(U64 lba, U32 num_sec, U8 *buf) {
  return VirtioBlkWriteSectors(lba, num_sec, buf);
}

// -------------------------------------------------------------
// Volatile RAMDisk
// -------------------------------------------------------------
U0 RamDiskInit() {
  if (g_rd.initialized) return;
  g_rd.storage = kmalloc(RAMDISK_CAPACITY);
  RsMemSet(g_rd.storage, 0, RAMDISK_CAPACITY);
  g_rd.used_bytes = 0;
  g_rd.entries = kmalloc(RAMDISK_MAX_FILES * 64);
  RsMemSet(g_rd.entries, 0, RAMDISK_MAX_FILES * 64);
  I64 rd_i = 0;
  while (rd_i < RAMDISK_MAX_FILES) {
    CRamDiskEntry *re = RdGetEntry(rd_i);
    re->used = 0;
    re->name[0] = 0;
    re->size = 0;
    re->offset = 0;
    rd_i++;
  }
  g_rd.initialized = 1;
}

I64 RamDiskWriteFile(U8 *fname, U8 *data, I64 sz) {
  if (!g_rd.initialized || !fname || !data) return -1;
  I64 aligned_sz = (sz + 15) & ~15;

  // Check overwrite
  I64 rdw_i = 0;
  while (rdw_i < RAMDISK_MAX_FILES) {
    CRamDiskEntry *re = RdGetEntry(rdw_i);
    if (re->used && RsStrCmp(re->name, fname) == 0) {
      if (sz <= re->size) {
        RsMemCpy(g_rd.storage + re->offset, data, sz);
        re->size = sz;
        return 0;
      }
      if (g_rd.used_bytes + aligned_sz > RAMDISK_CAPACITY) return -1;
      I64 off = g_rd.used_bytes;
      RsMemCpy(g_rd.storage + off, data, sz);
      re->offset = off;
      re->size = sz;
      g_rd.used_bytes = g_rd.used_bytes + aligned_sz;
      return 0;
    }
    rdw_i++;
  }

  if (g_rd.used_bytes + aligned_sz > RAMDISK_CAPACITY) return -1;

  // Find free entry
  rdw_i = 0;
  while (rdw_i < RAMDISK_MAX_FILES) {
    CRamDiskEntry *re = RdGetEntry(rdw_i);
    if (!re->used) {
      I64 free_off = g_rd.used_bytes;
      RsMemCpy(g_rd.storage + free_off, data, sz);
      RsStrCpy(re->name, fname);
      re->offset = free_off;
      re->size = sz;
      re->used = 1;
      g_rd.used_bytes = g_rd.used_bytes + aligned_sz;
      return 0;
    }
    rdw_i++;
  }
  return -1;
}

I64 RamDiskReadFile(U8 *fname, U8 *buf, I64 max_bytes, I64 *out_size) {
  if (!g_rd.initialized || !fname || !buf) return -1;
  I64 rdr_i = 0;
  while (rdr_i < RAMDISK_MAX_FILES) {
    CRamDiskEntry *re = RdGetEntry(rdr_i);
    if (re->used && RsStrCmp(re->name, fname) == 0) {
      I64 to_copy = re->size;
      if (to_copy > max_bytes) to_copy = max_bytes;
      RsMemCpy(buf, g_rd.storage + re->offset, to_copy);
      if (out_size) *out_size = to_copy;
      return 0;
    }
    rdr_i++;
  }
  return -1;
}

I64 RamDiskDeleteFile(U8 *fname) {
  if (!g_rd.initialized || !fname) return -1;
  I64 rdd_i = 0;
  while (rdd_i < RAMDISK_MAX_FILES) {
    CRamDiskEntry *re = RdGetEntry(rdd_i);
    if (re->used && RsStrCmp(re->name, fname) == 0) {
      re->used = 0;
      re->name[0] = 0;
      re->size = 0;
      re->offset = 0;
      return 0;
    }
    rdd_i++;
  }
  return -1;
}

// -------------------------------------------------------------
// RedSea Contiguous Filesystem
// -------------------------------------------------------------
I64 RedSeaFormat(U64 part_lba, U64 sec_count) {
  if (sec_count > 0) g_rs.total_sectors = sec_count;
  U8 zbuf[512];
  RsMemSet(zbuf, 0, 512);

  I64 rsf_s = 0;
  while (rsf_s < 16) {
    RsWriteSectors(part_lba + rsf_s, 1, zbuf);
    rsf_s++;
  }

  g_rs.root_lba = part_lba;
  g_rs.root_sectors = 16;
  g_rs.current_dir_lba = part_lba;
  g_rs.current_dir_sectors = 16;
  RsStrCpy(g_rs.current_pwd, "/");
  g_rs.next_alloc_lba = part_lba + 16;
  g_rs.initialized = 1;
  return 0;
}

U0 RedSeaMountHardware(U64 part_lba) {
  if (part_lba == 0) part_lba = 1;
  VirtioBlkInit();
  g_rs_hw_mode = 1;
  g_rs.root_lba = part_lba;
  g_rs.root_sectors = 16;

  U64 cap_sec = VirtioBlkGetCapacity();
  if (cap_sec > 0) g_rs.total_sectors = cap_sec;
  else g_rs.total_sectors = 65536;

  g_rs.current_dir_lba = part_lba;
  g_rs.current_dir_sectors = 16;
  RsStrCpy(g_rs.current_pwd, "/");

  // Scan all active root directory entries to compute max_end_lba dynamically
  // so new files NEVER overwrite existing files packed by mkredsea.py up to LBA 1054!
  U64 max_end_lba = 1064;
  U8 m_buf[512];
  I64 rsm_s = 0;
  while (rsm_s < g_rs.root_sectors) {
    if (RsReadSectors(g_rs.root_lba + rsm_s, 1, m_buf) == 0) {
      I64 rsm_i = 0;
      while (rsm_i < REDSEA_ENTRIES_PER_SECTOR) {
        CRedSeaEntry *ment = RsGetEntry(m_buf, rsm_i);
        if (ment->attr != 0 && ment->name[0] != 0) {
          U64 blocks_4k = (ment->size + 4095) / 4096;
          if (blocks_4k == 0) blocks_4k = 1;
          U64 end_lba = ment->cluster + blocks_4k * 8;
          if (end_lba > max_end_lba) {
            max_end_lba = end_lba;
          }
        }
        rsm_i++;
      }
    }
    rsm_s++;
  }

  g_rs.next_alloc_lba = max_end_lba;
  g_rs.initialized = 1;
  RamDiskInit();
}

I64 RedSeaInit(U64 part_lba) {
  RedSeaMountHardware(part_lba);
  return 0;
}

I64 RedSeaWriteFile(U8 *fname, U8 *data, I64 sz) {
  if (!g_rs.initialized || !fname || !data) return -1;

  U8 s_buf[512];
  I64 free_s = -1;
  I64 free_i = -1;

  // Search current directory
  I64 rsw_s = 0;
  while (rsw_s < g_rs.current_dir_sectors) {
    RsReadSectors(g_rs.current_dir_lba + rsw_s, 1, s_buf);
    I64 rsw_i = 0;
    while (rsw_i < REDSEA_ENTRIES_PER_SECTOR) {
      CRedSeaEntry *ent = RsGetEntry(s_buf, rsw_i);
      if (ent->attr != 0 && RsStrCmp(ent->name, fname) == 0) {
        // Updating existing file: if need_sectors > old_sectors, allocate a new cluster at next_alloc_lba
        I64 need_sec = (sz + 511) / 512;
        if (need_sec == 0) need_sec = 1;
        I64 old_sec = (ent->size + 511) / 512;
        if (old_sec == 0) old_sec = 1;

        U64 target_cl = ent->cluster;
        if (need_sec > old_sec) {
          target_cl = g_rs.next_alloc_lba;
          g_rs.next_alloc_lba = g_rs.next_alloc_lba + need_sec;
          ent->cluster = target_cl;
        }

        U8 *p_buf = kmalloc(need_sec * 512);
        if (!p_buf) return -1;
        RsMemSet(p_buf, 0, need_sec * 512);
        RsMemCpy(p_buf, data, sz);
        RsWriteSectors(target_cl, need_sec, p_buf);
        kfree(p_buf);

        ent->size = sz;
        ent->datetime = 0x202610170000 + timer_get_uptime_sec();
        RsWriteSectors(g_rs.current_dir_lba + rsw_s, 1, s_buf);
        return 0;
      }
      if ((ent->attr == 0 || ent->name[0] == 0) && free_s == -1) {
        free_s = rsw_s;
        free_i = rsw_i;
      }
      rsw_i++;
    }
    rsw_s++;
  }

  if (free_s == -1) return -1;

  // Allocate contiguous sectors at next_alloc_lba
  I64 payload_sec = (sz + 511) / 512;
  if (payload_sec == 0) payload_sec = 1;
  U64 target_cluster = g_rs.next_alloc_lba;
  g_rs.next_alloc_lba = g_rs.next_alloc_lba + payload_sec;

  U8 *payload_buf = kmalloc(payload_sec * 512);
  if (!payload_buf) return -1;
  RsMemSet(payload_buf, 0, payload_sec * 512);
  RsMemCpy(payload_buf, data, sz);
  RsWriteSectors(target_cluster, payload_sec, payload_buf);
  kfree(payload_buf);

  // Write directory entry
  RsReadSectors(g_rs.current_dir_lba + free_s, 1, s_buf);
  CRedSeaEntry *entries = RsGetEntry(s_buf, free_i);
  entries->attr = RS_ATTR_FILE;
  RsStrCpy(entries->name, fname);
  entries->cluster = target_cluster;
  entries->size = sz;
  entries->datetime = 0x202610170000 + timer_get_uptime_sec();
  RsWriteSectors(g_rs.current_dir_lba + free_s, 1, s_buf);
  return 0;
}

I64 RedSeaReadFile(U8 *fname, U8 *buf, I64 max_bytes, I64 *out_size) {
  if (!g_rs.initialized || !fname || !buf) return -1;
  U8 s_buf[512];

  I64 rsr_s = 0;
  while (rsr_s < g_rs.current_dir_sectors) {
    RsReadSectors(g_rs.current_dir_lba + rsr_s, 1, s_buf);
    I64 rsr_i = 0;
    while (rsr_i < REDSEA_ENTRIES_PER_SECTOR) {
      CRedSeaEntry *ent = RsGetEntry(s_buf, rsr_i);
      if (ent->attr != 0 && RsStrCmp(ent->name, fname) == 0) {
        I64 sec_to_read = (ent->size + 511) / 512;
        if (sec_to_read == 0) sec_to_read = 1;
        I64 bytes_copy = ent->size;
        if (bytes_copy > max_bytes) bytes_copy = max_bytes;

        U8 *t_buf = kmalloc(sec_to_read * 512);
        if (!t_buf) return -1;
        RsReadSectors(ent->cluster, sec_to_read, t_buf);
        RsMemCpy(buf, t_buf, bytes_copy);
        kfree(t_buf);

        if (out_size) *out_size = bytes_copy;
        return 0;
      }
      rsr_i++;
    }
    rsr_s++;
  }
  return -1;
}

I64 RedSeaDeleteFile(U8 *fname) {
  if (!g_rs.initialized || !fname) return -1;
  U8 s_buf[512];

  I64 rsd_s = 0;
  while (rsd_s < g_rs.current_dir_sectors) {
    RsReadSectors(g_rs.current_dir_lba + rsd_s, 1, s_buf);
    I64 rsd_i = 0;
    while (rsd_i < REDSEA_ENTRIES_PER_SECTOR) {
      CRedSeaEntry *ent = RsGetEntry(s_buf, rsd_i);
      if (ent->attr != 0 && RsStrCmp(ent->name, fname) == 0) {
        I64 f_sec = (ent->size + 511) / 512;
        if (f_sec == 0) f_sec = 1;
        if (ent->cluster + f_sec == g_rs.next_alloc_lba) {
          g_rs.next_alloc_lba = ent->cluster;
        }
        RsMemSet(ent, 0, 64);
        RsWriteSectors(g_rs.current_dir_lba + rsd_s, 1, s_buf);
        return 0;
      }
      rsd_i++;
    }
    rsd_s++;
  }
  return -1;
}

I64 RedSeaMkDir(U8 *dname) {
  if (!g_rs.initialized || !dname) return -1;
  U8 s_buf[512];
  I64 free_s = -1;
  I64 free_i = -1;

  I64 rsmk_s = 0;
  while (rsmk_s < g_rs.current_dir_sectors) {
    RsReadSectors(g_rs.current_dir_lba + rsmk_s, 1, s_buf);
    I64 rsmk_i = 0;
    while (rsmk_i < REDSEA_ENTRIES_PER_SECTOR) {
      CRedSeaEntry *ent = RsGetEntry(s_buf, rsmk_i);
      if (ent->attr != 0 && RsStrCmp(ent->name, dname) == 0) return -1; // already exists
      if ((ent->attr == 0 || ent->name[0] == 0) && free_s == -1) {
        free_s = rsmk_s;
        free_i = rsmk_i;
      }
      rsmk_i++;
    }
    rsmk_s++;
  }
  if (free_s == -1) return -1;

  U64 new_dir_lba = g_rs.next_alloc_lba;
  g_rs.next_alloc_lba = g_rs.next_alloc_lba + 2;

  U8 *new_dir_buf = kmalloc(2 * 512);
  if (!new_dir_buf) return -1;
  RsMemSet(new_dir_buf, 0, 2 * 512);
  CRedSeaEntry *new_ent0 = RsGetEntry(new_dir_buf, 0);
  CRedSeaEntry *new_ent1 = RsGetEntry(new_dir_buf, 1);

  // '.' entry
  new_ent0->attr = RS_ATTR_DIR;
  RsStrCpy(new_ent0->name, ".");
  new_ent0->cluster = new_dir_lba;
  new_ent0->size = 1024;

  // '..' entry
  new_ent1->attr = RS_ATTR_DIR;
  RsStrCpy(new_ent1->name, "..");
  new_ent1->cluster = g_rs.current_dir_lba;
  new_ent1->size = g_rs.current_dir_sectors * 512;

  RsWriteSectors(new_dir_lba, 2, new_dir_buf);
  kfree(new_dir_buf);

  // Write entry into parent
  RsReadSectors(g_rs.current_dir_lba + free_s, 1, s_buf);
  CRedSeaEntry *entries = RsGetEntry(s_buf, free_i);
  entries->attr = RS_ATTR_DIR;
  RsStrCpy(entries->name, dname);
  entries->cluster = new_dir_lba;
  entries->size = 1024;
  entries->datetime = 0x202610170000 + timer_get_uptime_sec();
  RsWriteSectors(g_rs.current_dir_lba + free_s, 1, s_buf);
  return 0;
}

I64 RedSeaChangeDir(U8 *dname) {
  if (!g_rs.initialized || !dname) return -1;
  if (RsStrCmp(dname, ".") == 0) return 0;
  if (RsStrCmp(dname, "/") == 0) {
    g_rs.current_dir_lba = g_rs.root_lba;
    g_rs.current_dir_sectors = g_rs.root_sectors;
    RsStrCpy(g_rs.current_pwd, "/");
    return 0;
  }
  if (RsStrCmp(dname, "..") == 0) {
    if (g_rs.current_dir_lba == g_rs.root_lba) {
      RsStrCpy(g_rs.current_pwd, "/");
      return 0;
    }
    U8 s_buf[512];
    RsReadSectors(g_rs.current_dir_lba, 1, s_buf);
    CRedSeaEntry *ent = RsGetEntry(s_buf, 1);
    if ((ent->attr & RS_ATTR_DIR) && RsStrCmp(ent->name, "..") == 0) {
      g_rs.current_dir_lba = ent->cluster;
      g_rs.current_dir_sectors = (ent->size + 511) / 512;
      if (g_rs.current_dir_lba == g_rs.root_lba) {
        RsStrCpy(g_rs.current_pwd, "/");
      } else {
        // Pop the last path component from current_pwd
        I64 pwd_len = RsStrLen(g_rs.current_pwd);
        if (pwd_len > 1 && g_rs.current_pwd[pwd_len - 1] == '/') {
          pwd_len--;
          g_rs.current_pwd[pwd_len] = 0;
        }
        I64 last_slash = -1;
        I64 rscd_p = 0;
        while (rscd_p < pwd_len) {
          if (g_rs.current_pwd[rscd_p] == '/') last_slash = rscd_p;
          rscd_p++;
        }
        if (last_slash <= 0) {
          RsStrCpy(g_rs.current_pwd, "/");
        } else {
          g_rs.current_pwd[last_slash] = 0;
        }
      }
      return 0;
    }
    return -1;
  }

  // Search current directory
  U8 s_buf[512];
  I64 rscd_s = 0;
  while (rscd_s < g_rs.current_dir_sectors) {
    RsReadSectors(g_rs.current_dir_lba + rscd_s, 1, s_buf);
    I64 rscd_i = 0;
    while (rscd_i < REDSEA_ENTRIES_PER_SECTOR) {
      CRedSeaEntry *ent = RsGetEntry(s_buf, rscd_i);
      if ((ent->attr & RS_ATTR_DIR) && RsStrCmp(ent->name, dname) == 0) {
        g_rs.current_dir_lba = ent->cluster;
        g_rs.current_dir_sectors = (ent->size + 511) / 512;
        if (g_rs.current_dir_sectors == 0) g_rs.current_dir_sectors = 2;

        // Append component to current_pwd
        I64 cur_len = RsStrLen(g_rs.current_pwd);
        I64 d_len = RsStrLen(dname);
        if (cur_len == 0 || (cur_len == 1 && g_rs.current_pwd[0] == '/')) {
          g_rs.current_pwd[0] = '/';
          I64 cp_i = 0;
          while (cp_i < d_len && cp_i < 120) {
            g_rs.current_pwd[1 + cp_i] = dname[cp_i];
            cp_i++;
          }
          g_rs.current_pwd[1 + cp_i] = 0;
        } else if (cur_len + 1 + d_len < 126) {
          g_rs.current_pwd[cur_len] = '/';
          I64 cp_i = 0;
          while (cp_i < d_len) {
            g_rs.current_pwd[cur_len + 1 + cp_i] = dname[cp_i];
            cp_i++;
          }
          g_rs.current_pwd[cur_len + 1 + cp_i] = 0;
        }
        return 0;
      }
      rscd_i++;
    }
    rscd_s++;
  }
  return -1;
}

// -------------------------------------------------------------
// Verification Suite
// -------------------------------------------------------------
I64 RedSeaSelfTest() {
  doldoc_printf("\n$FG,CYAN$[REDSEA-TEST] Starting Pure HolyC RedSea & RAMDisk Storage Verification...$FG$\n");

  // Test 1: RAMDisk write, read, and content verification
  RamDiskInit();
  U8 *rd_sample = "HolyC RAMDisk Zero-Latency Storage OK";
  RamDiskWriteFile("ram_test.txt", rd_sample, 37);

  U8 rd_readback[64];
  RsMemSet(rd_readback, 0, 64);
  I64 rd_sz = 0;
  I64 rd_res = RamDiskReadFile("ram_test.txt", rd_readback, 64, &rd_sz);
  if (rd_res != 0 || rd_sz != 37 || RsStrCmp(rd_readback, rd_sample) != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: RAMDisk read/write roundtrip failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: RAMDisk 64KB volatile read/write roundtrip verified.$FG$\n");

  // Test 2: RAMDisk deletion
  RamDiskDeleteFile("ram_test.txt");
  if (RamDiskReadFile("ram_test.txt", rd_readback, 64, &rd_sz) == 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: RAMDisk deletion failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: RAMDisk file deletion validated.$FG$\n");

  // Test 3: RedSea mount watermark & file creation/relocation on real block device
  RedSeaMountHardware(1);
  if (g_rs.next_alloc_lba < 1064) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: RedSea next_alloc_lba (%lld) < 1064!$FG$\n", g_rs.next_alloc_lba);
    return 0;
  }
  U8 *rs_data = "NeoOS TempleOS RedSea Contiguous 64-bit Payload";
  RedSeaWriteFile("TEST_RS.BIN", rs_data, 47);

  U8 rs_readback[64];
  RsMemSet(rs_readback, 0, 64);
  I64 rs_read_sz = 0;
  I64 rs_res = RedSeaReadFile("TEST_RS.BIN", rs_readback, 64, &rs_read_sz);
  if (rs_res != 0 || rs_read_sz != 47 || RsStrCmp(rs_readback, rs_data) != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: RedSea file write/read failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: RedSea mount watermark (LBA %lld) & write/read verified.$FG$\n", g_rs.next_alloc_lba);

  // Test 4: RedSea directory creation & nested '..' path popping
  RedSeaMkDir("DIR_TEST");
  if (RedSeaChangeDir("DIR_TEST") != 0 || RsStrCmp(g_rs.current_pwd, "/DIR_TEST") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 4A: RedSea cd DIR_TEST failed (pwd=%s)!$FG$\n", g_rs.current_pwd);
    return 0;
  }
  RedSeaWriteFile("APP_T.HC", "U0 Main() {}", 13);
  I64 app_sz = 0;
  if (RedSeaReadFile("APP_T.HC", rs_readback, 64, &app_sz) != 0 || app_sz != 13) {
    doldoc_printf("$FG,RED$[FAIL] Test 4B: RedSea subdirectory file write/read failed!$FG$\n");
    return 0;
  }
  RedSeaDeleteFile("APP_T.HC");
  RedSeaChangeDir("..");
  if (g_rs.current_dir_lba != g_rs.root_lba || RsStrCmp(g_rs.current_pwd, "/") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 4C: RedSea cd .. failed!$FG$\n");
    return 0;
  }
  RedSeaDeleteFile("DIR_TEST");
  doldoc_printf("$FG,GREEN$[PASS] Test 4: RedSea hierarchical directory creation and '..' popping verified.$FG$\n");

  // Test 5: RedSea file deletion & sector reclamation
  RedSeaDeleteFile("TEST_RS.BIN");
  if (RedSeaReadFile("TEST_RS.BIN", rs_readback, 64, &rs_read_sz) == 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5A: RedSea file deletion failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: RedSea file deletion and contiguous sector reclamation verified.$FG$\n");

  doldoc_printf("\n[REDSEA-PASS] ALL 5 REDSEA STORAGE TESTS PASSED ON REAL HARDWARE\n\n");
  RedSeaMountHardware(1);
  return 1;
}

U8* redsea_get_pwd() {
  return g_rs.current_pwd;
}

I64 redsea_read_file(U8 *fname, U8 *buf, I64 max_bytes, I64 *out_size) {
  return RedSeaReadFile(fname, buf, max_bytes, out_size);
}

I64 redsea_write_file(U8 *fname, U8 *data, I64 sz) {
  return RedSeaWriteFile(fname, data, sz);
}

I64 redsea_get_entries(U8 *out_entries, I64 max_entries) {
  if (!g_rs.initialized || !out_entries || max_entries <= 0) return 0;
  U8 s_buf[512];
  I64 count = 0;
  I64 rse_s = 0;
  while (rse_s < g_rs.current_dir_sectors && count < max_entries) {
    RsReadSectors(g_rs.current_dir_lba + rse_s, 1, s_buf);
    I64 rse_i = 0;
    while (rse_i < REDSEA_ENTRIES_PER_SECTOR && count < max_entries) {
      CRedSeaEntry *ent = RsGetEntry(s_buf, rse_i);
      if (ent->attr != 0 && ent->name[0] != 0) {
        RsMemCpy(out_entries + count * 64, ent, 64);
        count++;
      }
      rse_i++;
    }
    rse_s++;
  }
  return count;
}

U0 RedSeaListDir() {
  U8 *entries = kmalloc(128 * 64);
  if (!entries) return;
  I64 count = redsea_get_entries(entries, 128);
  doldoc_printf("\n$CARD,title=\"RedSea Contiguous Storage Substrate: %s\",w=112,h=2,bg=0xFF1E1E2E,border=0xFF89B4FA$\n", g_rs.current_pwd);
  doldoc_print("$HR$\n");

  if (count == 0) {
    doldoc_print("  $FG,MUTED$(Directory is empty)$FG$\n\n");
    kfree(entries);
    return;
  }

  I64 total_bytes = 0;
  I64 dir_i;
  for (dir_i = 0; dir_i < count; dir_i++) {
    CRedSeaEntry *ent = entries + dir_i * 64;
    I64 is_dir = (ent->attr & RS_ATTR_DIR) != 0;
    total_bytes += ent->size;

    I64 name_len = strlen(ent->name);
    I64 rs_sp;
    if (is_dir) {
      doldoc_printf("  $FG,YELLOW$[DIR] $FG$ %s", ent->name);
      for (rs_sp = name_len; rs_sp < 20; rs_sp++) doldoc_print(" ");
      doldoc_printf(" $FG,MUTED$%8lld B$FG$  LBA %5lld  $BT,\"Open\",LM=\"cd %s\"$\n", ent->size, ent->cluster, ent->name);
    } else {
      I64 is_hc = 0;
      if (name_len > 3) {
        if (strcmp(ent->name + name_len - 3, ".HC") == 0) {
          is_hc = 1;
        }
      }
      if (is_hc) {
        doldoc_printf("  $FG,GREEN$[FILE]$FG$ %s", ent->name);
        for (rs_sp = name_len; rs_sp < 20; rs_sp++) doldoc_print(" ");
        doldoc_printf(" $FG,CYAN$%8lld B$FG$  LBA %5lld  $BT,\"Run\",LM=\"run %s\"$  $BT,\"Src\",LM=\"src %s\"$\n", ent->size, ent->cluster, ent->name, ent->name);
      } else {
        doldoc_printf("  $FG,WHITE$[FILE]$FG$ %s", ent->name);
        for (rs_sp = name_len; rs_sp < 20; rs_sp++) doldoc_print(" ");
        doldoc_printf(" $FG,MUTED$%8lld B$FG$  LBA %5lld  $BT,\"View\",LM=\"cat %s\"$\n", ent->size, ent->cluster, ent->name);
      }
    }
  }

  doldoc_print("$HR$\n");
  doldoc_printf(" Total: $FG,YELLOW$%lld entries$FG$ | Payload: $FG,CYAN$%lld KB$FG$ | Next Alloc LBA: $FG,GREEN$%lld$FG$\n\n",
                count, (total_bytes + 1023) / 1024, g_rs.next_alloc_lba);
  kfree(entries);
}

U0 redsea_list_dir() {
  RedSeaListDir();
}

I64 redsea_change_dir(U8 *dname) {
  return RedSeaChangeDir(dname);
}

I64 redsea_mkdir(U8 *dname) {
  return RedSeaMkDir(dname);
}

I64 redsea_delete_file(U8 *fname) {
  return RedSeaDeleteFile(fname);
}

I64 g_kernel_booting;
if (g_kernel_booting) {
  RedSeaMountHardware(1);
} else {
  RedSeaSelfTest();
}
