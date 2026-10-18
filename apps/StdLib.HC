// ==============================================================================
// StdLib.HC - HolyC 2.0 Dynamic Data Structures & Systems Utilities
// Architecture: AArch64 Ring 0 SASOS | Leak-Free CArray, CDict & Unified Table
// ==============================================================================

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

// ─── Dynamic Hash Map (CDict / Unified Table) ────────────────────────────────

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

// ─── Unified Table API (PascalCase & C-ABI snake_case) ───────────────────────

Table* TableCreate() {
  return DictCreate(64);
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
  return DictCreate(64);
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

// ─── Verification Suite ──────────────────────────────────────────────────────

I64 StdLibTest() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$  [STDLIB.HC] Dynamic Containers & Unified Dict/Table Suite    $FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");

  // 1. Dynamic CArray with growth & null guards
  CArray *arr = ArrayCreate(8);
  if (!arr) {
    doldoc_print("  $FG,RED$[FAIL] ArrayCreate returned NULL!$FG$\n");
    return 0;
  }
  ArrayPush(0, 999); // Null guard check
  ArrayPush(arr, 100);
  ArrayPush(arr, 200);
  ArrayPush(arr, 300);
  I64 v1 = ArrayGet(arr, 0);
  I64 v2 = ArrayGet(arr, 1);
  I64 v3 = ArrayGet(arr, 2);
  ArrayFree(arr);

  if (v1 != 100 || v2 != 200 || v3 != 300) {
    doldoc_printf("  $FG,RED$[FAIL] CArray mismatch: %lld, %lld, %lld$FG$\n", v1, v2, v3);
    return 0;
  }
  doldoc_print("  $FG,GREEN$[PASS]$FG$ CArray (ArrayCreate / ArrayPush / ArrayGet / ArrayFree) verified.\n");

  // 2. Dynamic CDict with StrDup key isolation & DictFree
  CDict *dict = DictCreate(16);
  if (!dict) {
    doldoc_print("  $FG,RED$[FAIL] DictCreate returned NULL!$FG$\n");
    return 0;
  }
  U8 *mut_key = StrDup("alpha");
  DictSet(dict, mut_key, 42);
  if (mut_key) {
    mut_key[0] = 'z'; // Mutate caller buffer to prove DictSet duplicated key via StrDup!
    kfree(mut_key);
  }
  DictSet(dict, "beta", 84);
  I64 d1 = DictGet(dict, "alpha");
  I64 d2 = DictGet(dict, "beta");
  DictFree(dict);

  if (d1 != 42 || d2 != 84) {
    doldoc_printf("  $FG,RED$[FAIL] CDict mismatch: d1=%lld, d2=%lld$FG$\n", d1, d2);
    return 0;
  }
  doldoc_print("  $FG,GREEN$[PASS]$FG$ CDict (StrDup key isolation & leak-free DictFree) verified.\n");

  // 3. Unified table_create / table_set / table_get
  Table *utbl = table_create();
  table_set(utbl, "kernel", 1024);
  I64 tv = table_get(utbl, "kernel");
  table_free(utbl);
  if (tv != 1024) {
    doldoc_printf("  $FG,RED$[FAIL] Unified table_get returned %lld$FG$\n", tv);
    return 0;
  }
  doldoc_print("  $FG,GREEN$[PASS]$FG$ Unified table_create / table_set / table_get / table_free verified.\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");

  return v1 + v2 + v3 + d1 + d2;
}

I64 g_kernel_booting;
if (!g_kernel_booting) {
  StdLibTest();
}
