#include "symbols.h"
#include "../mem/kheap.h"
extern void doldoc_print(const char *str);
extern void doldoc_printf(const char *fmt, ...);
#include <uefi.h>

static symbol_t *buckets[SYMBOL_HASH_BUCKETS] = {NULL};
static uint64_t total_symbols = 0;

// DJB2 Hash algorithm
static uint32_t hash_string(const char *str) {
    uint32_t hash = 5381;
    int c;
    while ((c = (unsigned char)*str++)) {
        hash = ((hash << 5) + hash) + c; // hash * 33 + c
    }
    return hash % SYMBOL_HASH_BUCKETS;
}

void symbols_init(void) {
    for (int i = 0; i < SYMBOL_HASH_BUCKETS; i++) {
        buckets[i] = NULL;
    }
    total_symbols = 0;
    printf("[SYMBOLS] Global Hash Table initialized (%d buckets)\n", SYMBOL_HASH_BUCKETS);
}

int64_t symbols_unresolved_trap(void) {
    return 0;
}

// Report every symbol still pointing at the unresolved trap after all modules
// have loaded. Any entry listed here would fault (or return 0) if invoked.
void* symbols_sic_cell(const char *name) {
    symbol_t *sym = symbols_lookup_or_reserve(name, SYM_FUNC);
    return sym ? (void*)&sym->address : NULL;
}

void symbols_report_unresolved(void) {
    int n = 0;
    for (int i = 0; i < SYMBOL_HASH_BUCKETS; i++) {
        for (symbol_t *c = buckets[i]; c; c = c->next) {
            if (c->address == (void*)symbols_unresolved_trap) {
                if (n == 0) printf("\n[SYMBOLS] UNRESOLVED FORWARD REFERENCES:\n");
                printf("  - %s\n", c->name);
                n++;
            }
        }
    }
    if (n == 0) printf("[SYMBOLS] No unresolved forward references.\n");
    else printf("[SYMBOLS] %d unresolved reference(s) — invoking them would trap.\n", n);
}

int symbols_register(const char *name, void *address, symbol_type_t type) {
    if (!name || !address) return 0;

    uint32_t bucket = hash_string(name);

    // Check if symbol already exists (or was pre-reserved as a SIC cell); update address atomically
    symbol_t *curr = buckets[bucket];
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            curr->address = address;
            curr->type = type;
            __asm__ volatile("dmb ish" ::: "memory");
            return 1; // Updated in-place SIC cell
        }
        curr = curr->next;
    }

    // Allocate new persistent symbol record (SIC cell) in kernel heap
    symbol_t *sym = (symbol_t*)kmalloc(sizeof(symbol_t));
    if (!sym) {
        printf("[SYMBOLS] Failed to allocate symbol: %s\n", name);
        return 0;
    }

    strncpy(sym->name, name, sizeof(sym->name) - 1);
    sym->name[sizeof(sym->name) - 1] = '\0';
    sym->address = address;
    sym->type = type;
    sym->hash = bucket;
    sym->next = buckets[bucket];
    buckets[bucket] = sym;
    total_symbols++;
    __asm__ volatile("dmb ish" ::: "memory");

    return 1;
}

void* symbols_lookup(const char *name) {
    symbol_t *sym = symbols_lookup_entry(name);
    return sym ? sym->address : NULL;
}

symbol_t* symbols_lookup_entry(const char *name) {
    if (!name) return NULL;

    uint32_t bucket = hash_string(name);
    symbol_t *curr = buckets[bucket];

    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            return curr;
        }
        curr = curr->next;
    }

    return NULL;
}

symbol_t* symbols_lookup_or_reserve(const char *name, symbol_type_t default_type) {
    if (!name) return NULL;
    symbol_t *existing = symbols_lookup_entry(name);
    if (existing) return existing;

    if (default_type == SYM_VAR) {
        // Forward global variable: reserve a real, zeroed storage cell. A later
        // declaration reuses this same cell (symbols_register updates in place),
        // so reads compiled before the definition observe the defined value.
        int64_t *cell = (int64_t*)kmalloc(sizeof(int64_t));
        if (cell) *cell = 0;
        symbols_register(name, (void*)cell, SYM_VAR);
    } else {
        // Forward function: SIC cell points at the unresolved trap until defined.
        symbols_register(name, (void*)symbols_unresolved_trap, default_type);
    }
    return symbols_lookup_entry(name);
}

uint64_t symbols_count(void) {
    return total_symbols;
}

int symbols_iterate(int (*callback)(symbol_t *sym, void *user_data), void *user_data) {
    int count = 0;
    for (int i = 0; i < SYMBOL_HASH_BUCKETS; i++) {
        symbol_t *curr = buckets[i];
        while (curr) {
            count++;
            if (callback && callback(curr, user_data) != 0) {
                return count;
            }
            curr = curr->next;
        }
    }
    return count;
}

void symbols_dump(void) {
    printf("\n--- GLOBAL SYMBOL TABLE DUMP (%llu symbols) ---\n", (unsigned long long)total_symbols);
    for (int i = 0; i < SYMBOL_HASH_BUCKETS; i++) {
        symbol_t *curr = buckets[i];
        while (curr) {
            const char *type_str = (curr->type == SYM_FUNC) ? "FUNC" :
                                   (curr->type == SYM_VAR) ? "VAR " : "HW  ";
            printf(" [%s] %s -> 0x%016llX\n",
                   type_str, curr->name, (unsigned long long)curr->address);
            curr = curr->next;
        }
    }
    printf("----------------------------------------------\n\n");
}

void symbols_print_doldoc(void) {
    doldoc_printf("$FG,CYAN$--- DYNAMIC SYMBOL TABLE (%llu symbols) ---$FG$\n", (unsigned long long)total_symbols);
    for (int i = 0; i < SYMBOL_HASH_BUCKETS; i++) {
        symbol_t *curr = buckets[i];
        while (curr) {
            const char *type_str = (curr->type == SYM_FUNC) ? "FUNC" :
                                   (curr->type == SYM_VAR) ? "VAR " : "HW  ";
            doldoc_printf(" [$FG,YELLOW$%s$FG$] %s -> 0x%016llX\n",
                          type_str, curr->name, (unsigned long long)curr->address);
            curr = curr->next;
        }
    }
    doldoc_print("$FG,CYAN$----------------------------------------$FG$\n");
}

