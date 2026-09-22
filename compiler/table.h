#ifndef NEO_TABLE_H
#define NEO_TABLE_H

#include <uefi.h>

#define TABLE_BUCKETS 32

typedef struct table_entry {
    char key[32];
    int64_t value;
    struct table_entry *next;
} table_entry_t;

typedef struct table {
    table_entry_t *buckets[TABLE_BUCKETS];
    int count;
} table_t;

table_t* table_create(void);
void     table_set(table_t *tbl, const char *key, int64_t val);
int64_t  table_get(table_t *tbl, const char *key);
int      table_has(table_t *tbl, const char *key);
void     table_free(table_t *tbl);

#endif // NEO_TABLE_H
