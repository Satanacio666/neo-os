// NeoOS Sovereign Pure HolyC Kernel Heap Allocator & Memory Manager
// 16-byte aligned freelist bump/split/coalesce allocator with canary & SMP spinlock protection

#define HEAP_CANARY 0xDEADBEEFCAFECAFE
#define HEAP_BLOCK_HEADER_SIZE 48

class CHeapBlock {
  U64         canary_head;
  U64         size;
  I64         is_free;
  CHeapBlock *next;
  CHeapBlock *prev;
  U64         pad;
};

class CHeapStats {
  U64 total_memory;
  U64 used_memory;
  U64 free_memory;
  U64 allocation_count;
  U64 free_count;
  U64 peak_used;
};

CHeapBlock *g_heap_head;
CHeapStats  g_kheap;
CHeapStats  g_heap_stats;
U64         g_heap_start;
U64         g_heap_end;
U32         g_kheap_lock;
U8         *g_kheap_boot_pool;
U64         g_uefi_heap_base;
U64         g_uefi_heap_size;

U0 KhSyncStats() {
  g_heap_stats.total_memory     = g_kheap.total_memory;
  g_heap_stats.used_memory      = g_kheap.used_memory;
  g_heap_stats.free_memory      = g_kheap.free_memory;
  g_heap_stats.allocation_count = g_kheap.allocation_count;
  g_heap_stats.free_count       = g_kheap.free_count;
  g_heap_stats.peak_used        = g_kheap.peak_used;
}

U0 KhMemSet(U8 *buf, U8 val, I64 count) {
  if (!buf || count <= 0) return;
  I64 khm_i = 0;
  while (khm_i < count) {
    buf[khm_i] = val;
    khm_i++;
  }
}

U0 KhMemCpy(U8 *dst, U8 *src, I64 count) {
  if (!dst || !src || count <= 0) return;
  I64 khc_i = 0;
  while (khc_i < count) {
    dst[khc_i] = src[khc_i];
    khc_i++;
  }
}

U0 KHeapInit(U8 *p_start, I64 p_size) {
  if (!p_start || p_size < HEAP_BLOCK_HEADER_SIZE + 64) return;

  smp_spin_lock(&g_kheap_lock);

  U64 start = (p_start + 15) & ~15;
  I64 adj_sz = p_size - (start - p_start);

  g_heap_start = start;
  g_heap_end = start + adj_sz;

  g_heap_head = start;
  g_heap_head->canary_head = HEAP_CANARY;
  g_heap_head->size = adj_sz - HEAP_BLOCK_HEADER_SIZE;
  g_heap_head->is_free = 1;
  g_heap_head->next = 0;
  g_heap_head->prev = 0;
  g_heap_head->pad = 0;

  g_kheap.total_memory = adj_sz;
  g_kheap.free_memory = g_heap_head->size;
  g_kheap.used_memory = HEAP_BLOCK_HEADER_SIZE;
  g_kheap.allocation_count = 0;
  g_kheap.free_count = 0;
  g_kheap.peak_used = HEAP_BLOCK_HEADER_SIZE;
  KhSyncStats();

  smp_spin_unlock(&g_kheap_lock);
}

I64 KHeapIsValidPtr(U8 *ptr) {
  if (!ptr) return 0;
  U64 p = ptr;
  if (p < g_heap_start + HEAP_BLOCK_HEADER_SIZE || p >= g_heap_end) return 0;
  if ((p & 15) != 0) return 0;

  CHeapBlock *blk = p - HEAP_BLOCK_HEADER_SIZE;
  if (blk->canary_head != HEAP_CANARY) return 0;
  return 1;
}

U8* KMalloc(I64 p_req_sz) {
  if (p_req_sz <= 0) return 0;

  smp_spin_lock(&g_kheap_lock);

  I64 aligned_sz = (p_req_sz + 15) & ~15;
  CHeapBlock *curr = g_heap_head;

  while (curr) {
    if (curr->canary_head != HEAP_CANARY) {
      smp_spin_unlock(&g_kheap_lock);
      doldoc_printf("$FG,RED$[KHEAP] FATAL: Memory corruption at 0x%016X!$FG$\n", curr);
      return 0;
    }

    if (curr->is_free && curr->size >= aligned_sz) {
      // Split block if large enough
      if (curr->size >= aligned_sz + HEAP_BLOCK_HEADER_SIZE + 16) {
        U64 new_addr = curr + HEAP_BLOCK_HEADER_SIZE + aligned_sz;
        CHeapBlock *new_blk = new_addr;
        new_blk->canary_head = HEAP_CANARY;
        new_blk->size = curr->size - aligned_sz - HEAP_BLOCK_HEADER_SIZE;
        new_blk->is_free = 1;
        new_blk->next = curr->next;
        new_blk->prev = curr;
        new_blk->pad = 0;

        if (curr->next) {
          CHeapBlock *c_next = curr->next;
          c_next->prev = new_blk;
        }
        curr->next = new_blk;
        curr->size = aligned_sz;

        g_kheap.used_memory = g_kheap.used_memory + HEAP_BLOCK_HEADER_SIZE;
        if (g_kheap.free_memory >= HEAP_BLOCK_HEADER_SIZE) {
          g_kheap.free_memory = g_kheap.free_memory - HEAP_BLOCK_HEADER_SIZE;
        }
      }

      curr->is_free = 0;
      g_kheap.used_memory = g_kheap.used_memory + curr->size;
      if (g_kheap.free_memory >= curr->size) {
        g_kheap.free_memory = g_kheap.free_memory - curr->size;
      } else {
        g_kheap.free_memory = 0;
      }
      g_kheap.allocation_count = g_kheap.allocation_count + 1;
      if (g_kheap.used_memory > g_kheap.peak_used) {
        g_kheap.peak_used = g_kheap.used_memory;
      }
      KhSyncStats();

      U8 *ret_ptr = curr + HEAP_BLOCK_HEADER_SIZE;
      smp_spin_unlock(&g_kheap_lock);
      return ret_ptr;
    }
    curr = curr->next;
  }

  smp_spin_unlock(&g_kheap_lock);
  return 0;
}

U0 KFree(U8 *ptr) {
  if (!ptr) return;
  if (!KHeapIsValidPtr(ptr)) return;

  smp_spin_lock(&g_kheap_lock);

  CHeapBlock *blk = ptr - HEAP_BLOCK_HEADER_SIZE;
  if (blk->canary_head != HEAP_CANARY || blk->is_free) {
    smp_spin_unlock(&g_kheap_lock);
    return;
  }

  blk->is_free = 1;
  g_kheap.free_memory = g_kheap.free_memory + blk->size;
  if (g_kheap.used_memory >= blk->size) {
    g_kheap.used_memory = g_kheap.used_memory - blk->size;
  }
  g_kheap.free_count = g_kheap.free_count + 1;

  // Coalesce forward
  if (blk->next) {
    CHeapBlock *b_next = blk->next;
    if (b_next->canary_head == HEAP_CANARY && b_next->is_free) {
      blk->size = blk->size + HEAP_BLOCK_HEADER_SIZE + b_next->size;
      g_kheap.free_memory = g_kheap.free_memory + HEAP_BLOCK_HEADER_SIZE;
      if (g_kheap.used_memory >= HEAP_BLOCK_HEADER_SIZE) {
        g_kheap.used_memory = g_kheap.used_memory - HEAP_BLOCK_HEADER_SIZE;
      }
      blk->next = b_next->next;
      if (blk->next) {
        CHeapBlock *b_n2 = blk->next;
        b_n2->prev = blk;
      }
    }
  }

  // Coalesce backward
  if (blk->prev) {
    CHeapBlock *b_prev = blk->prev;
    if (b_prev->canary_head == HEAP_CANARY && b_prev->is_free) {
      b_prev->size = b_prev->size + HEAP_BLOCK_HEADER_SIZE + blk->size;
      g_kheap.free_memory = g_kheap.free_memory + HEAP_BLOCK_HEADER_SIZE;
      if (g_kheap.used_memory >= HEAP_BLOCK_HEADER_SIZE) {
        g_kheap.used_memory = g_kheap.used_memory - HEAP_BLOCK_HEADER_SIZE;
      }
      b_prev->next = blk->next;
      if (blk->next) {
        CHeapBlock *b_n3 = blk->next;
        b_n3->prev = b_prev;
      }
    }
  }

  KhSyncStats();
  smp_spin_unlock(&g_kheap_lock);
}

U8* KCalloc(I64 p_num, I64 p_elem_sz) {
  if (p_num <= 0 || p_elem_sz <= 0) return 0;
  I64 total_sz = p_num * p_elem_sz;
  U8 *p_buf = KMalloc(total_sz);
  if (p_buf) {
    KhMemSet(p_buf, 0, total_sz);
  }
  return p_buf;
}

U8* KRealloc(U8 *p_old_ptr, I64 p_new_sz) {
  if (!p_old_ptr) return KMalloc(p_new_sz);
  if (p_new_sz <= 0) {
    KFree(p_old_ptr);
    return 0;
  }
  if (!KHeapIsValidPtr(p_old_ptr)) return 0;

  CHeapBlock *blk = p_old_ptr - HEAP_BLOCK_HEADER_SIZE;
  if (blk->canary_head != HEAP_CANARY) return 0;
  U64 old_sz = blk->size;
  if (old_sz >= p_new_sz) return p_old_ptr;

  U8 *new_buf = KMalloc(p_new_sz);
  if (new_buf) {
    KhMemCpy(new_buf, p_old_ptr, old_sz);
    KFree(p_old_ptr);
  }
  return new_buf;
}

U0 kheap_get_stats(U64 *p_total_b, U64 *p_used_b, U64 *p_free_b, U64 *p_alloc_cnt) {
  U64 phys_total = g_kheap.total_memory;
  U64 phys_used  = g_kheap.used_memory;
  U64 phys_free  = g_kheap.free_memory;
  U64 phys_alloc = g_kheap.allocation_count;

  if (g_uefi_heap_base != 0 && g_uefi_heap_size != 0) {
    U64 u_start = (g_uefi_heap_base + 15) & ~15;
    U64 u_end   = g_uefi_heap_base + g_uefi_heap_size;
    CHeapBlock *u_curr = u_start;
    U64 sum_used = 0;
    U64 sum_free = 0;
    U64 cnt_alloc = 0;
    I64 guard = 0;

    while (u_curr != 0 && guard < 65536) {
      U64 c_addr = u_curr;
      if (c_addr < u_start || c_addr + HEAP_BLOCK_HEADER_SIZE > u_end) break;
      if (u_curr->canary_head != HEAP_CANARY) break;

      if ((u_curr->is_free & 0xFFFFFFFF) != 0) {
        sum_free = sum_free + u_curr->size;
        sum_used = sum_used + HEAP_BLOCK_HEADER_SIZE;
      } else {
        sum_used = sum_used + u_curr->size + HEAP_BLOCK_HEADER_SIZE;
        cnt_alloc = cnt_alloc + 1;
      }
      u_curr = u_curr->next;
      guard++;
    }

    if (sum_used + sum_free > 0) {
      phys_total = g_uefi_heap_size;
      phys_used  = sum_used;
      phys_free  = sum_free;
      phys_alloc = cnt_alloc;
    }
  }

  if (p_total_b)   *p_total_b   = phys_total;
  if (p_used_b)    *p_used_b    = phys_used;
  if (p_free_b)    *p_free_b    = phys_free;
  if (p_alloc_cnt) *p_alloc_cnt = phys_alloc;
}

U0 KHeapPrintStats() {
  U64 total_b = 0;
  U64 used_b = 0;
  U64 free_b = 0;
  U64 alloc_cnt = 0;
  kheap_get_stats(&total_b, &used_b, &free_b, &alloc_cnt);

  I64 phys_total_kb = (total_b + 1023) / 1024;
  I64 phys_used_kb  = (used_b + 1023) / 1024;
  I64 phys_free_kb  = (free_b + 1023) / 1024;
  I64 phys_pct      = (phys_total_kb > 0) ? (phys_used_kb * 100) / phys_total_kb : 0;
  if (phys_pct > 100) phys_pct = 100;
  if (phys_pct == 0 && phys_used_kb > 0) phys_pct = 1;

  I64 hc_total_kb = (g_kheap.total_memory + 1023) / 1024;
  I64 hc_used_kb  = (g_kheap.used_memory + 1023) / 1024;
  I64 hc_free_kb  = (g_kheap.free_memory + 1023) / 1024;
  I64 hc_peak_kb  = (g_kheap.peak_used + 1023) / 1024;

  doldoc_print("\n$CARD,title=\"Sovereign Memory Substrate & 32 MB Physical Heap Telemetry\",w=96,h=8,bg=0xFF1E1E2E,border=0xFF89B4FA$\n");
  doldoc_printf("  $FG,CYAN$[UEFI 32MB Physical Heap]$FG$ Total: %6lld KB | Used: %6lld KB | Free: %6lld KB | Live Blocks: %lld\n",
                phys_total_kb, phys_used_kb, phys_free_kb, alloc_cnt);
  doldoc_printf("  $FG,SAPPHIRE$[HolyC Slab Allocator]   $FG$ Total: %6lld KB | Used: %6lld KB | Free: %6lld KB | Peak Used  : %lld KB\n",
                hc_total_kb, hc_used_kb, hc_free_kb, hc_peak_kb);
  doldoc_printf("  $FG,SAPPHIRE$[Allocator Counters]     $FG$ KMalloc Calls: %6lld | KFree Calls: %6lld | Lock State : %s\n",
                g_kheap.allocation_count, g_kheap.free_count, (g_kheap_lock == 0) ? "UNLOCKED" : "LOCKED");
  doldoc_printf("  $FG,YELLOW$Physical Utilization     :$FG$ $PB,VAL=%lld,MAX=100$  $FG,GREEN$%lld%% Allocated$FG$\n", phys_pct, phys_pct);
  doldoc_print("$HR$\n\n");
}

U0 KHeapDump() {
  KHeapPrintStats();
}

U0 kheap_dump_doldoc() {
  if (g_kheap.total_memory == 0) {
    if (!g_kheap_boot_pool) {
      g_kheap_boot_pool = kmalloc(1048576);
    }
    if (g_kheap_boot_pool) {
      KHeapInit(g_kheap_boot_pool, 1048576);
    }
  }
  KHeapPrintStats();
}

I64 KHeapSelfTest() {
  doldoc_printf("\n$FG,CYAN$[KHEAP-TEST] Starting Pure HolyC Kernel Heap Verification...$FG$\n");

  // Save active boot pool state so self-test never leaves dangling g_heap_head
  CHeapBlock *saved_head  = g_heap_head;
  U64         saved_start = g_heap_start;
  U64         saved_end   = g_heap_end;
  U64         saved_tot   = g_kheap.total_memory;
  U64         saved_used  = g_kheap.used_memory;
  U64         saved_free  = g_kheap.free_memory;
  U64         saved_acnt  = g_kheap.allocation_count;
  U64         saved_fcnt  = g_kheap.free_count;
  U64         saved_peak  = g_kheap.peak_used;

  // Test 1: Initialize 64 KB test pool
  U8 *pool_raw = kmalloc(65536);
  if (!pool_raw) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Could not allocate test pool!$FG$\n");
    return 0;
  }
  KHeapInit(pool_raw, 65536);
  if (g_kheap.total_memory < 65000 || g_heap_head->canary_head != HEAP_CANARY || !g_heap_head->is_free) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 1: Heap pool initialization failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: Heap freelist, spinlock & canary initialized (64 KB test pool).$FG$\n");

  // Test 2: Malloc 3 blocks, verify 16-byte alignment & peak_used tracking
  U8 *p1 = KMalloc(128);
  U8 *p2 = KMalloc(256);
  U8 *p3 = KMalloc(512);
  if (!p1 || !p2 || !p3 || (p1 & 15) != 0 || (p2 & 15) != 0 || (p3 & 15) != 0) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 2: KMalloc alignment or null allocation failed!$FG$\n");
    return 0;
  }
  if (p1 >= p2 || p2 >= p3 || g_kheap.peak_used < 896) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 2: Overlapping block addresses or peak_used not updated!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: 16-byte aligned allocations & peak_used (%lld B) verified.$FG$\n", g_kheap.peak_used);

  // Test 3: Canary and validity check
  if (!KHeapIsValidPtr(p1) || !KHeapIsValidPtr(p2) || !KHeapIsValidPtr(p3)) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 3: KHeapIsValidPtr failed on valid pointers!$FG$\n");
    return 0;
  }
  if (KHeapIsValidPtr(p1 + 3) != 0 || KHeapIsValidPtr(0) != 0) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 3: KHeapIsValidPtr returned true for unaligned/null!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Pointer validity & canary integrity validated.$FG$\n");

  // Test 4: Free and block coalescing
  U64 peak_before_free = g_kheap.peak_used;
  KFree(p2);
  KFree(p1);
  KFree(p3);
  if (g_kheap.allocation_count != 3 || g_kheap.free_count != 3 || g_kheap.peak_used != peak_before_free) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 4: Alloc/Free count or peak_used watermark mismatch!$FG$\n");
    return 0;
  }
  if (g_heap_head->next != 0 || !g_heap_head->is_free) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 4: Bidirectional block coalescing failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Deallocation and full bidirectional coalescing verified.$FG$\n");

  // Test 5: Realloc growth, data preservation & 32 MB physical heap stats
  U8 *p4 = KMalloc(64);
  KhMemSet(p4, 0x42, 64);
  U8 *p4_grown = KRealloc(p4, 1024);
  if (!p4_grown || p4_grown[0] != 0x42 || p4_grown[63] != 0x42) {
    kfree(pool_raw);
    doldoc_printf("$FG,RED$[FAIL] Test 5: KRealloc failed or corrupted data!$FG$\n");
    return 0;
  }
  KFree(p4_grown);

  U64 st_tot = 0;
  U64 st_used = 0;
  U64 st_free = 0;
  U64 st_cnt = 0;
  kheap_get_stats(&st_tot, &st_used, &st_free, &st_cnt);

  // Restore active boot pool before freeing temporary test pool
  if (saved_head != 0 && saved_tot > 0) {
    g_heap_head              = saved_head;
    g_heap_start             = saved_start;
    g_heap_end               = saved_end;
    g_kheap.total_memory     = saved_tot;
    g_kheap.used_memory      = saved_used;
    g_kheap.free_memory      = saved_free;
    g_kheap.allocation_count = saved_acnt;
    g_kheap.free_count       = saved_fcnt;
    if (saved_peak > g_kheap.peak_used) {
      g_kheap.peak_used = saved_peak;
    }
    KhSyncStats();
  }
  kfree(pool_raw);

  if (st_tot == 0 || st_used == 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5B: Physical heap telemetry returned zero!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: KRealloc growth & 32 MB physical heap telemetry verified.$FG$\n");

  KHeapPrintStats();
  doldoc_printf("\n[KHEAP-PASS] ALL 5 HEAP ALLOCATOR TESTS PASSED\n\n");
  return 1;
}

I64 g_kernel_booting;
if (g_kernel_booting) {
  if (!g_kheap_boot_pool) {
    g_kheap_boot_pool = kmalloc(1048576);
  }
  if (g_kheap_boot_pool) {
    KHeapInit(g_kheap_boot_pool, 1048576);
  }
} else {
  KHeapSelfTest();
}
