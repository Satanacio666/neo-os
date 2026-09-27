#ifndef NEO_KHEAP_H
#define NEO_KHEAP_H

#include <uefi.h>

#define HEAP_CANARY 0xDEADBEEFCAFECAFEULL

typedef struct heap_block {
    uint64_t canary_head;
    size_t size;
    int is_free;
    struct heap_block *next;
    struct heap_block *prev;
    // Data starts here (16-byte aligned)
} __attribute__((aligned(16))) heap_block_t;

typedef struct {
    uint64_t total_memory;
    uint64_t used_memory;
    uint64_t free_memory;
    uint64_t allocation_count;
    uint64_t free_count;
} heap_stats_t;

void  kheap_init(void *heap_start, size_t heap_size);
void* kmalloc(size_t size);
void  kfree(void *ptr);
void* kcalloc(size_t num, size_t size);
void* krealloc(void *ptr, size_t new_size);
void  kheap_get_stats(heap_stats_t *stats);
void  kheap_dump(void);
int   kheap_is_valid_ptr(void *ptr);
uintptr_t kheap_get_start(void);
uintptr_t kheap_get_end(void);

#endif // NEO_KHEAP_H
