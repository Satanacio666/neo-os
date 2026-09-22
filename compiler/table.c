#include "table.h"
#include "../kernel/mem/kheap.h"

static uint32_t hash_key(const char *s) {
    uint32_t h = 5381;
    while (*s) {
        h = ((h << 5) + h) + (unsigned char)(*s++);
    }
    return h % TABLE_BUCKETS;
}

table_t* table_create(void) {
    table_t *tbl = (table_t*)kmalloc(sizeof(table_t));
    if (!tbl) return NULL;
    memset(tbl, 0, sizeof(table_t));
    return tbl;
}

void table_set(table_t *tbl, const char *key, int64_t val) {
    if (!tbl || !key) return;

    uint32_t b = hash_key(key);
    table_entry_t *curr = tbl->buckets[b];
    while (curr) {
        if (strcmp(curr->key, key) == 0) {
            curr->value = val;
            return;
        }
        curr = curr->next;
    }

    table_entry_t *entry = (table_entry_t*)kmalloc(sizeof(table_entry_t));
    if (!entry) return;
    strncpy(entry->key, key, sizeof(entry->key) - 1);
    entry->key[sizeof(entry->key) - 1] = '\0';
    entry->value = val;
    entry->next = tbl->buckets[b];
    tbl->buckets[b] = entry;
    tbl->count++;
}

int64_t table_get(table_t *tbl, const char *key) {
    if (!tbl || !key) return 0;

    uint32_t b = hash_key(key);
    table_entry_t *curr = tbl->buckets[b];
    while (curr) {
        if (strcmp(curr->key, key) == 0) {
            return curr->value;
        }
        curr = curr->next;
    }
    return 0;
}

int table_has(table_t *tbl, const char *key) {
    if (!tbl || !key) return 0;

    uint32_t b = hash_key(key);
    table_entry_t *curr = tbl->buckets[b];
    while (curr) {
        if (strcmp(curr->key, key) == 0) {
            return 1;
        }
        curr = curr->next;
    }
    return 0;
}

void table_free(table_t *tbl) {
    if (!tbl) return;
    for (int i = 0; i < TABLE_BUCKETS; i++) {
        table_entry_t *curr = tbl->buckets[i];
        while (curr) {
            table_entry_t *next = curr->next;
            kfree(curr);
            curr = next;
        }
    }
    kfree(tbl);
}
