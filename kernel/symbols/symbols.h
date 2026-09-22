#ifndef NEO_SYMBOLS_H
#define NEO_SYMBOLS_H

#include <uefi.h>

typedef enum {
    SYM_FUNC = 1,
    SYM_VAR = 2,
    SYM_HARDWARE = 3
} symbol_type_t;

typedef struct symbol {
    char name[64];
    void *address;
    symbol_type_t type;
    uint32_t hash;
    struct symbol *next;
} symbol_t;

#define SYMBOL_HASH_BUCKETS 1024

void     symbols_init(void);
int      symbols_register(const char *name, void *address, symbol_type_t type);
void*    symbols_lookup(const char *name);
symbol_t* symbols_lookup_entry(const char *name);
int      symbols_iterate(int (*callback)(symbol_t *sym, void *user_data), void *user_data);
void     symbols_dump(void);
void     symbols_print_doldoc(void);
uint64_t symbols_count(void);

#endif // NEO_SYMBOLS_H
