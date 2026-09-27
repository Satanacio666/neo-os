// StdLib.HC - HolyC 2.0 Dynamic Data Structures & Systems Utilities
// NeoOS AArch64 Ring 0 SASOS

class CArray {
    I64 *data;
    I64 count;
    I64 capacity;
};

CArray* ArrayNew(I64 initial_cap) {
    if (initial_cap < 8) initial_cap = 8;
    CArray *arr = kmalloc(sizeof(CArray));
    arr->data = kmalloc(initial_cap * 8);
    arr->count = 0;
    arr->capacity = initial_cap;
    return arr;
}

U0 ArrayPush(CArray *arr, I64 val) {
    if (arr->count >= arr->capacity) {
        I64 new_cap = arr->capacity * 2;
        I64 *new_data = kmalloc(new_cap * 8);
        I64 *old_data = arr->data;
        for (I64 i = 0; i < arr->count; i++) {
            new_data[i] = old_data[i];
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
    if (idx < 0 || idx >= arr->count) return 0;
    return arr->data[idx];
}

U0 ArrayFree(CArray *arr) {
    if (arr) {
        if (arr->data) kfree(arr->data);
        kfree(arr);
    }
}

// ─── Dynamic Hash Map (CDict) ─────────────────────────────────────────────────

class CDictEntry {
    U8 *key;
    I64 val;
    CDictEntry *next;
};

class CDict {
    CDictEntry **buckets;
    I64 num_buckets;
    I64 count;
};

CDict* DictNew(I64 num_buckets) {
    if (num_buckets < 16) num_buckets = 16;
    CDict *d = kmalloc(sizeof(CDict));
    d->buckets = kmalloc(num_buckets * 8);
    CDictEntry **b = d->buckets;
    for (I64 i = 0; i < num_buckets; i++) {
        b[i] = NULL;
    }
    d->num_buckets = num_buckets;
    d->count = 0;
    return d;
}

U0 DictSet(CDict *d, U8 *key, I64 val) {
    if (!d || !key) return;
    I64 h = 5381;
    U8 *p = key;
    while (*p) {
        h = ((h << 5) + h) + *p;
        p++;
    }
    I64 b = (h & 0x7FFFFFFFFFFFFFFF) % d->num_buckets;
    CDictEntry **buckets = d->buckets;
    CDictEntry *curr = buckets[b];
    while (curr) {
        if (strcmp(curr->key, key) == 0) {
            curr->val = val;
            return;
        }
        curr = curr->next;
    }
    CDictEntry *ent = kmalloc(sizeof(CDictEntry));
    ent->key = key;
    ent->val = val;
    ent->next = buckets[b];
    buckets[b] = ent;
    d->count = d->count + 1;
}

I64 DictGet(CDict *d, U8 *key) {
    if (!d || !key) return 0;
    I64 h = 5381;
    U8 *p = key;
    while (*p) {
        h = ((h << 5) + h) + *p;
        p++;
    }
    I64 b = (h & 0x7FFFFFFFFFFFFFFF) % d->num_buckets;
    CDictEntry **buckets = d->buckets;
    CDictEntry *curr = buckets[b];
    while (curr) {
        if (strcmp(curr->key, key) == 0) {
            return curr->val;
        }
        curr = curr->next;
    }
    return 0;
}

I64 StdLibTest() {
    CArray *arr = ArrayNew(8);
    ArrayPush(arr, 100);
    ArrayPush(arr, 200);
    ArrayPush(arr, 300);
    I64 v1 = ArrayGet(arr, 0);
    I64 v2 = ArrayGet(arr, 1);
    I64 v3 = ArrayGet(arr, 2);
    ArrayFree(arr);

    CDict *dict = DictNew(16);
    DictSet(dict, "alpha", 42);
    DictSet(dict, "beta", 84);
    I64 d1 = DictGet(dict, "alpha");
    I64 d2 = DictGet(dict, "beta");

    return v1 + v2 + v3 + d1 + d2;
}

StdLibTest();
