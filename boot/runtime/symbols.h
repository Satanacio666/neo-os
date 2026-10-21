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
int      symbols_is_defined(const char *name);
int      symbols_is_func(const char *name);
int      symbols_is_var(const char *name);
void*    symbols_lookup(const char *name);
symbol_t* symbols_lookup_entry(const char *name);
symbol_t* symbols_lookup_or_reserve(const char *name, symbol_type_t default_type);
int64_t  symbols_unresolved_trap(void);
void     symbols_report_unresolved(void);
int64_t  symbols_unresolved_count(void);
void*    symbols_sic_cell(const char *name);
void*    symbols_var_cell(const char *name);
uint64_t symbols_count(void);

#endif // NEO_SYMBOLS_H
