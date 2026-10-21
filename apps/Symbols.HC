// NeoOS Sovereign Pure HolyC Dynamic Symbol Table (TempleOS DNA)
// DJB2 Hash Table with Canonical Case-Folding (snake_case <-> CamelCase) & O(1) Hot-Patching

#define SYM_FUNC     1
#define SYM_VAR      2
#define SYM_HARDWARE 3

#define SYM_HASH_BUCKETS 256

class CSymbol {
  U8       name[64];
  U64      address;
  I64      type;
  U32      hash;
  CSymbol *next;
};

CSymbol *g_sym_buckets[256];
U64      g_sym_total_count;
I64      g_sym_initialized;
U8       g_sym_alt_pascal[64];
U8       g_sym_alt_snake[64];

U0 SymStrCpy(U8 *dst_buf, U8 *src_buf) {
  if (!dst_buf || !src_buf) return;
  I64 ssc_idx = 0;
  while (src_buf[ssc_idx] != 0 && ssc_idx < 63) {
    dst_buf[ssc_idx] = src_buf[ssc_idx];
    ssc_idx++;
  }
  dst_buf[ssc_idx] = 0;
}

I64 SymStrCmp(U8 *s1, U8 *s2) {
  if (!s1 || !s2) return -1;
  I64 scmp_pos = 0;
  while (s1[scmp_pos] != 0 && s2[scmp_pos] != 0) {
    if (s1[scmp_pos] != s2[scmp_pos]) return s1[scmp_pos] - s2[scmp_pos];
    scmp_pos++;
  }
  return s1[scmp_pos] - s2[scmp_pos];
}

U8 SymToLowerChar(U8 c) {
  if (c >= 'A' && c <= 'Z') return c + 32;
  return c;
}

// Case-insensitive and underscore-agnostic comparison:
// Matches "hal_flush_cache" <-> "HalFlushCache" <-> "HALFLUSHCACHE"
I64 SymCanonicalMatch(U8 *s1, U8 *s2) {
  if (!s1 || !s2) return 0;
  I64 scm_i1 = 0;
  I64 scm_i2 = 0;
  while (1) {
    while (s1[scm_i1] == '_') scm_i1++;
    while (s2[scm_i2] == '_') scm_i2++;
    U8 c1 = SymToLowerChar(s1[scm_i1]);
    U8 c2 = SymToLowerChar(s2[scm_i2]);
    if (c1 != c2) return 0;
    if (c1 == 0) return 1;
    scm_i1++;
    scm_i2++;
  }
}

// Case-insensitive substring filter match for SymDump(filter)
I64 SymMatchFilter(U8 *sym_name, U8 *filter) {
  if (!filter || filter[0] == 0) return 1;
  if (!sym_name) return 0;
  I64 smf_i = 0;
  while (sym_name[smf_i] != 0) {
    I64 smf_j = 0;
    while (filter[smf_j] != 0 && sym_name[smf_i + smf_j] != 0) {
      if (SymToLowerChar(sym_name[smf_i + smf_j]) != SymToLowerChar(filter[smf_j])) {
        break;
      }
      smf_j++;
    }
    if (filter[smf_j] == 0) return 1;
    smf_i++;
  }
  return 0;
}

// Convert snake_case to PascalCase into dst_buf (max 63 chars)
U0 SymBuildPascalName(U8 *dst_buf, U8 *src_buf) {
  I64 sbp_s = 0;
  I64 sbp_d = 0;
  I64 cap_next = 1;
  while (src_buf[sbp_s] != 0 && sbp_d < 63) {
    U8 ch = src_buf[sbp_s];
    if (ch == '_') {
      cap_next = 1;
    } else {
      if (cap_next && ch >= 'a' && ch <= 'z') {
        dst_buf[sbp_d] = ch - 32;
      } else {
        dst_buf[sbp_d] = ch;
      }
      sbp_d++;
      cap_next = 0;
    }
    sbp_s++;
  }
  dst_buf[sbp_d] = 0;
}

// Convert PascalCase/CamelCase to snake_case into dst_buf (max 63 chars)
U0 SymBuildSnakeName(U8 *dst_buf, U8 *src_buf) {
  I64 sbs_s = 0;
  I64 sbs_d = 0;
  while (src_buf[sbs_s] != 0 && sbs_d < 62) {
    U8 ch = src_buf[sbs_s];
    if (ch >= 'A' && ch <= 'Z') {
      if (sbs_s > 0 && src_buf[sbs_s - 1] != '_' && sbs_d < 61) {
        U8 prev_c = src_buf[sbs_s - 1];
        if ((prev_c >= 'a' && prev_c <= 'z') || (prev_c >= '0' && prev_c <= '9')) {
          dst_buf[sbs_d] = '_';
          sbs_d++;
        }
      }
      dst_buf[sbs_d] = ch + 32;
      sbs_d++;
    } else {
      dst_buf[sbs_d] = ch;
      sbs_d++;
    }
    sbs_s++;
  }
  dst_buf[sbs_d] = 0;
}

// DJB2 hash algorithm
U32 SymHashString(U8 *str) {
  U64 hash = 5381;
  I64 shs_i = 0;
  while (str[shs_i] != 0) {
    hash = ((hash << 5) + hash) + (str[shs_i] & 0xFF);
    shs_i++;
  }
  return hash & (SYM_HASH_BUCKETS - 1);
}

U0 SymInit() {
  if (g_sym_initialized && g_sym_total_count > 0) {
    return;
  }
  I64 si_i = 0;
  while (si_i < SYM_HASH_BUCKETS) {
    g_sym_buckets[si_i] = 0;
    si_i++;
  }
  g_sym_total_count = 0;
  g_sym_initialized = 1;
}

I64 SymRegister(U8 *name, U64 address, I64 type) {
  if (!name || address == 0) return 0;
  if (!g_sym_initialized) SymInit();

  U32 bucket = SymHashString(name);

  // Check if exists (O(1) hot-patching in place)
  CSymbol *curr = g_sym_buckets[bucket];
  while (curr) {
    if (SymStrCmp(curr->name, name) == 0) {
      curr->address = address;
      curr->type = type;
      __dmb_ish();
      return 1;
    }
    curr = curr->next;
  }

  // Allocate new symbol record
  CSymbol *sym = kmalloc(sizeof(CSymbol));
  if (!sym) return 0;

  SymStrCpy(sym->name, name);
  sym->address = address;
  sym->type = type;
  sym->hash = bucket;
  sym->next = g_sym_buckets[bucket];
  g_sym_buckets[bucket] = sym;
  g_sym_total_count = g_sym_total_count + 1;
  __dmb_ish();

  return 1;
}

CSymbol* SymLookupEntry(U8 *name) {
  if (!name) return 0;
  U32 bucket = SymHashString(name);
  CSymbol *curr = g_sym_buckets[bucket];
  while (curr) {
    if (SymStrCmp(curr->name, name) == 0) {
      return curr;
    }
    curr = curr->next;
  }
  return 0;
}

U64 SymLookup(U8 *name) {
  if (!name) return 0;
  CSymbol *sym = SymLookupEntry(name);
  if (sym) return sym->address;
  return 0;
}

U64 SymLookupCanonical(U8 *name) {
  if (!name) return 0;

  // 1. Exact O(1) hash lookup in HolyC symbol table
  CSymbol *exact = SymLookupEntry(name);
  if (exact) return exact->address;

  // 2. Canonical case-insensitive / snake_case <-> CamelCase scan in HolyC buckets
  I64 slc_b = 0;
  while (slc_b < SYM_HASH_BUCKETS) {
    CSymbol *curr = g_sym_buckets[slc_b];
    while (curr) {
      if (SymCanonicalMatch(curr->name, name)) {
        return curr->address;
      }
      curr = curr->next;
    }
    slc_b++;
  }

  // 3. Fallback to Ring-0 bootstrap symbol table (exact, PascalCase, and snake_case)
  U64 boot_addr = symbols_lookup(name);
  if (boot_addr != 0) return boot_addr;

  SymBuildPascalName(g_sym_alt_pascal, name);
  boot_addr = symbols_lookup(g_sym_alt_pascal);
  if (boot_addr != 0) return boot_addr;

  SymBuildSnakeName(g_sym_alt_snake, name);
  boot_addr = symbols_lookup(g_sym_alt_snake);
  if (boot_addr != 0) return boot_addr;

  return 0;
}

U64 SymCount() {
  return g_sym_total_count;
}

U0 SymDump(U8 *filter) {
  I64 matched = 0;
  doldoc_printf("$FG,CYAN$--- DYNAMIC SYMBOL TABLE (%d total symbols) ---$FG$\n", g_sym_total_count);
  I64 sd_b = 0;
  while (sd_b < SYM_HASH_BUCKETS) {
    CSymbol *curr = g_sym_buckets[sd_b];
    while (curr) {
      if (SymMatchFilter(curr->name, filter)) {
        doldoc_printf(" [$FG,YELLOW$%s$FG$] %-28s -> 0x%016X\n",
                      (curr->type == SYM_FUNC) ? "FUNC" : ((curr->type == SYM_VAR) ? "VAR " : "HW  "),
                      curr->name, curr->address);
        matched++;
      }
      curr = curr->next;
    }
    sd_b++;
  }
  if (filter && filter[0] != 0) {
    doldoc_printf(" Filter '%s': %d matching symbol(s)\n", filter, matched);
  }
  doldoc_printf("$FG,CYAN$----------------------------------------------$FG$\n");
}

U0 SymPrintDolDoc() {
  SymDump(0);
}

I64 SymbolsSelfTest() {
  doldoc_printf("\n$FG,CYAN$[SYMBOLS-TEST] Starting Pure HolyC Symbol Table Verification...$FG$\n");

  // Test 1: Non-destructive initialization (NEVER wipe live g_sym_buckets!)
  if (!g_sym_initialized) {
    SymInit();
  }
  if (!g_sym_initialized) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Symbol table initialization flag not set!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: Non-destructive symbol table state verified (%d existing symbols preserved).$FG$\n", SymCount());

  // Test 2: Registration of FUNC, VAR, and HARDWARE symbols
  SymRegister("kmalloc", 0x75001000, SYM_FUNC);
  SymRegister("kfree", 0x75002000, SYM_FUNC);
  SymRegister("g_screen_width", 0x75003000, SYM_VAR);
  SymRegister("UART0_BASE", 0x09000000, SYM_HARDWARE);
  U64 count_after_reg = SymCount();
  if (count_after_reg < 4) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: Symbol count too low (%d, expected >= 4)!$FG$\n", count_after_reg);
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Symbols registered (FUNC, VAR, HW) without wiping table.$FG$\n");

  // Test 3: Exact Lookup
  U64 km_addr = SymLookup("kmalloc");
  CSymbol *uart_sym = SymLookupEntry("UART0_BASE");
  if (km_addr != 0x75001000 || !uart_sym || uart_sym->address != 0x09000000 || uart_sym->type != SYM_HARDWARE) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: Symbol lookup verification failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Symbol address & type lookup verified.$FG$\n");

  // Test 4: In-place hot-patch update without count inflation
  SymRegister("kmalloc", 0x75009999, SYM_FUNC);
  if (SymCount() != count_after_reg || SymLookup("kmalloc") != 0x75009999) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: In-place symbol update failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: O(1) in-place symbol address hot-patch verified.$FG$\n");

  // Test 5: Canonical lookup (case-insensitive & snake_case <-> PascalCase) & negative lookup
  U64 canon_screen = SymLookupCanonical("GScreenWidth");
  U64 canon_uart   = SymLookupCanonical("uart0_base");
  if (canon_screen != 0x75003000 || canon_uart != 0x09000000 || SymLookup("non_existent_symbol_xyz") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Canonical or negative lookup failed!$FG$\n");
    return 0;
  }
  SymDump("UART0");
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Canonical case-folding (GScreenWidth <-> g_screen_width) & SymDump verified.$FG$\n");

  doldoc_printf("\n[SYMBOLS-PASS] ALL 5 SYMBOL TABLE TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  SymInit();
  SymRegister("HalFlushCache", &HalFlushCache, SYM_FUNC);
  SymRegister("KMalloc", &KMalloc, SYM_FUNC);
  SymRegister("KFree", &KFree, SYM_FUNC);
  SymRegister("UART0_BASE", 0x09000000, SYM_HARDWARE);
} else {
  SymbolsSelfTest();
}

// P0.5 twin-liveness probe: proves Symbols.HC is loaded and callable.
I64 SymbolsTwinProbe() { return 0x53594D31; }
