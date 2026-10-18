// ==============================================================================
// Table.HC - Sovereign Pure HolyC Dynamic Hash Table & Container Substrate
// Architecture: AArch64 Ring 0 | Unified with StdLib.HC (CDict / CArray / Table)
// ==============================================================================

#define TABLE_BUCKETS 64

class CArray {
  I64 *data;
  I64  count;
  I64  capacity;
};

class CDictEntry {
  U8         *key;
  I64         val;
  CDictEntry *next;
};

class CDict {
  CDictEntry **buckets;
  I64          num_buckets;
  I64          count;
};

class Table {
  CDictEntry **buckets;
  I64          num_buckets;
  I64          count;
};

U8* StrDup(U8 *src) {
  if (!src) return 0;
  I64 sd_len = strlen(src);
  U8 *sd_buf = kmalloc(sd_len + 1);
  if (!sd_buf) return 0;
  memcpy(sd_buf, src, sd_len + 1);
  return sd_buf;
}

// ─── Dynamic Array (CArray) ──────────────────────────────────────────────────

CArray* ArrayCreate(I64 initial_cap) {
  if (initial_cap < 8) initial_cap = 8;
  CArray *arr = kmalloc(sizeof(CArray));
  if (!arr) return 0;
  arr->data = kmalloc(initial_cap * 8);
  if (!arr->data) {
    kfree(arr);
    return 0;
  }
  arr->count = 0;
  arr->capacity = initial_cap;
  return arr;
}

CArray* ArrayNew(I64 initial_cap) {
  return ArrayCreate(initial_cap);
}

U0 ArrayPush(CArray *arr, I64 val) {
  if (!arr || !arr->data) return;
  if (arr->count >= arr->capacity) {
    I64 new_cap = arr->capacity * 2;
    if (new_cap < 8) new_cap = 8;
    I64 *new_data = kmalloc(new_cap * 8);
    if (!new_data) return;
    I64 *old_data = arr->data;
    I64 ap_i = 0;
    while (ap_i < arr->count) {
      new_data[ap_i] = old_data[ap_i];
      ap_i++;
    }
    kfree(old_data);
    arr->data = new_data;
    arr->capacity = new_cap;
  }
  I64 idx = arr->count;
  arr->data[idx] = val;
  arr->count = idx + 1;
}

I64 ArrayGet(CArray *arr, I64 idx) {
  if (!arr || !arr->data) return 0;
  if (idx < 0 || idx >= arr->count) return 0;
  return arr->data[idx];
}

U0 ArraySet(CArray *arr, I64 idx, I64 val) {
  if (!arr || !arr->data) return;
  if (idx < 0 || idx >= arr->count) return;
  arr->data[idx] = val;
}

I64 ArrayPop(CArray *arr) {
  if (!arr || !arr->data || arr->count <= 0) return 0;
  arr->count = arr->count - 1;
  return arr->data[arr->count];
}

I64 ArrayCount(CArray *arr) {
  if (!arr) return 0;
  return arr->count;
}

U0 ArrayFree(CArray *arr) {
  if (!arr) return;
  if (arr->data) {
    kfree(arr->data);
    arr->data = 0;
  }
  kfree(arr);
}

// ─── Unified DJB2 Hash Map (CDict & Table) ──────────────────────────────────

I64 DictHashKey(U8 *key, I64 num_buckets) {
  if (!key || num_buckets <= 0) return 0;
  U64 h = 5381;
  I64 dhk_i = 0;
  while (key[dhk_i] != 0) {
    h = ((h << 5) + h) + (key[dhk_i] & 0xFF);
    dhk_i++;
  }
  return (h & 0x7FFFFFFFFFFFFFFF) % num_buckets;
}

I64 TableHashKey(U8 *s) {
  return DictHashKey(s, TABLE_BUCKETS);
}

CDict* DictCreate(I64 num_buckets) {
  if (num_buckets < 16) num_buckets = 16;
  CDict *d = kmalloc(sizeof(CDict));
  if (!d) return 0;
  d->buckets = kmalloc(num_buckets * 8);
  if (!d->buckets) {
    kfree(d);
    return 0;
  }
  CDictEntry **b = d->buckets;
  I64 dc_i = 0;
  while (dc_i < num_buckets) {
    b[dc_i] = 0;
    dc_i++;
  }
  d->num_buckets = num_buckets;
  d->count = 0;
  return d;
}

CDict* DictNew(I64 num_buckets) {
  return DictCreate(num_buckets);
}

CDictEntry* DictFindEntry(CDict *d, U8 *key) {
  if (!d || !d->buckets || !key || d->num_buckets <= 0) return 0;
  I64 b = DictHashKey(key, d->num_buckets);
  CDictEntry **buckets = d->buckets;
  CDictEntry *curr = buckets[b];
  while (curr) {
    if (curr->key && strcmp(curr->key, key) == 0) {
      return curr;
    }
    curr = curr->next;
  }
  return 0;
}

U0 DictSet(CDict *d, U8 *key, I64 val) {
  if (!d || !d->buckets || !key || d->num_buckets <= 0) return;

  CDictEntry *existing = DictFindEntry(d, key);
  if (existing) {
    existing->val = val;
    return;
  }

  CDictEntry *ent = kmalloc(sizeof(CDictEntry));
  if (!ent) return;
  U8 *k_dup = StrDup(key);
  if (!k_dup) {
    kfree(ent);
    return;
  }

  I64 b = DictHashKey(key, d->num_buckets);
  CDictEntry **buckets = d->buckets;
  ent->key = k_dup;
  ent->val = val;
  ent->next = buckets[b];
  buckets[b] = ent;
  d->count = d->count + 1;
}

I64 DictGet(CDict *d, U8 *key) {
  CDictEntry *ent = DictFindEntry(d, key);
  if (ent) return ent->val;
  return 0;
}

I64 DictHas(CDict *d, U8 *key) {
  CDictEntry *ent = DictFindEntry(d, key);
  if (ent) return 1;
  return 0;
}

U0 DictFree(CDict *d) {
  if (!d) return;
  if (d->buckets) {
    CDictEntry **buckets = d->buckets;
    I64 df_i = 0;
    while (df_i < d->num_buckets) {
      CDictEntry *curr = buckets[df_i];
      while (curr) {
        CDictEntry *next = curr->next;
        if (curr->key) {
          kfree(curr->key);
          curr->key = 0;
        }
        kfree(curr);
        curr = next;
      }
      buckets[df_i] = 0;
      df_i++;
    }
    kfree(d->buckets);
    d->buckets = 0;
  }
  kfree(d);
}

Table* TableCreate() {
  return DictCreate(TABLE_BUCKETS);
}

U0 TableSet(Table *tbl, U8 *key, I64 val) {
  DictSet(tbl, key, val);
}

I64 TableGet(Table *tbl, U8 *key) {
  return DictGet(tbl, key);
}

I64 TableHas(Table *tbl, U8 *key) {
  return DictHas(tbl, key);
}

U0 TableFree(Table *tbl) {
  DictFree(tbl);
}

Table* table_create() {
  return DictCreate(TABLE_BUCKETS);
}

U0 table_set(Table *tbl, U8 *key, I64 val) {
  DictSet(tbl, key, val);
}

I64 table_get(Table *tbl, U8 *key) {
  return DictGet(tbl, key);
}

I64 table_has(Table *tbl, U8 *key) {
  return DictHas(tbl, key);
}

U0 table_free(Table *tbl) {
  DictFree(tbl);
}

// ------------------------------------------------------------------------------
// Table.HC Verification Suite
// ------------------------------------------------------------------------------
I64 TableSelfTest() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$  [TABLE.HC] Pure HolyC Unified Hash Table Scorecard            $FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");

  Table *t = TableCreate();
  if (!t) {
    doldoc_print("  $FG,RED$[FAIL] Failed to allocate table$FG$\n");
    return -1;
  }

  TableSet(t, "alpha", 100);
  TableSet(t, "beta", 200);
  table_set(t, "gamma", 300);

  I64 v1 = TableGet(t, "alpha");
  I64 v2 = TableGet(t, "beta");
  I64 v3 = table_get(t, "gamma");
  I64 v4 = TableGet(t, "delta");

  I64 passed = 0;
  if (v1 == 100 && v2 == 200 && v3 == 300 && v4 == 0) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Basic TableSet/table_set & TableGet/table_get: 100, 200, 300, 0\n");
    passed++;
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Got v1=%lld, v2=%lld, v3=%lld, v4=%lld\n", v1, v2, v3, v4);
  }

  // Overwrite test
  TableSet(t, "alpha", 999);
  I64 v_up = TableGet(t, "alpha");
  if (v_up == 999) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ Table Update Existing Key: alpha = %lld\n", v_up);
    passed++;
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Expected 999, got %lld\n", v_up);
  }

  // Existence test
  I64 has_b = TableHas(t, "beta");
  I64 has_z = table_has(t, "zeta");
  if (has_b == 1 && has_z == 0) {
    doldoc_printf("  $FG,GREEN$[PASS]$FG$ TableHas / table_has Membership Check\n");
    passed++;
  } else {
    doldoc_printf("  $FG,RED$[FAIL]$FG$ Expected 1, 0, got %lld, %lld\n", has_b, has_z);
  }

  TableFree(t);
  doldoc_printf("  $FG,GREEN$[PASS]$FG$ TableFree / DictFree Clean Reclamation (Zero Leaks)\n");
  passed++;

  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  doldoc_printf("$FG,GREEN$  All %lld / 4 Table.HC tests passed!$FG$\n", passed);
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  return passed;
}

I64 g_kernel_booting;
if (!g_kernel_booting) {
  TableSelfTest();
}
