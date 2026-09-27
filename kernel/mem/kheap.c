#include "kheap.h"
#include <uefi.h>

extern void smp_spin_lock(volatile uint32_t *lock);
extern void smp_spin_unlock(volatile uint32_t *lock);
static volatile uint32_t s_heap_spinlock = 0;

static heap_block_t *head = NULL;
static heap_stats_t stats = {0};
static uintptr_t s_heap_start = 0;
static uintptr_t s_heap_end = 0;

uintptr_t kheap_get_start(void) { return s_heap_start; }
uintptr_t kheap_get_end(void) { return s_heap_end; }

int kheap_is_valid_ptr(void *ptr) {
    if (!ptr) return 0;
    uintptr_t p = (uintptr_t)ptr;
    if (p < s_heap_start + sizeof(heap_block_t) || p >= s_heap_end) return 0;
    if (p & 15) return 0; // Heap allocations are 16-byte aligned
    heap_block_t *block = (heap_block_t*)ptr - 1;
    if (block->canary_head != HEAP_CANARY) return 0;
    return 1;
}

void kheap_init(void *heap_start, size_t heap_size) {
    if (!heap_start || heap_size < sizeof(heap_block_t) + 64) {
        printf("[HEAP] Error: Invalid heap region specified!\n");
        return;
    }

    // Align start to 16 bytes
    uintptr_t start = ((uintptr_t)heap_start + 15) & ~15;
    size_t adjusted_size = heap_size - (start - (uintptr_t)heap_start);

    s_heap_start = start;
    s_heap_end = start + adjusted_size;

    head = (heap_block_t*)start;
    head->canary_head = HEAP_CANARY;
    head->size = adjusted_size - sizeof(heap_block_t);
    head->is_free = 1;
    head->next = NULL;
    head->prev = NULL;

    stats.total_memory = adjusted_size;
    stats.free_memory = head->size;
    stats.used_memory = sizeof(heap_block_t);
    stats.allocation_count = 0;
    stats.free_count = 0;

    printf("[HEAP] Initialized at 0x%016llX (%llu KB total, %llu KB usable)\n",
           (unsigned long long)start,
           (unsigned long long)(adjusted_size / 1024),
           (unsigned long long)(head->size / 1024));
}

void* kmalloc(size_t size) {
    if (size == 0 || size > 0x40000000ULL) return NULL;

    smp_spin_lock(&s_heap_spinlock);

    // Align requested size to 16 bytes
    size_t aligned_size = (size + 15) & ~15;
    heap_block_t *curr = head;

    while (curr) {
        if (curr->canary_head != HEAP_CANARY) {
            printf("[HEAP] FATAL: Memory corruption detected at block 0x%016llX!\n", (unsigned long long)curr);
            smp_spin_unlock(&s_heap_spinlock);
            return NULL;
        }

        if (curr->is_free && curr->size >= aligned_size) {
            // Can we split this block? Need at least sizeof(heap_block_t) + 16 bytes leftover
            if (curr->size >= aligned_size + sizeof(heap_block_t) + 16) {
                heap_block_t *new_block = (heap_block_t*)((uintptr_t)(curr + 1) + aligned_size);
                new_block->canary_head = HEAP_CANARY;
                new_block->size = curr->size - aligned_size - sizeof(heap_block_t);
                new_block->is_free = 1;
                new_block->next = curr->next;
                new_block->prev = curr;

                if (curr->next) {
                    curr->next->prev = new_block;
                }
                curr->next = new_block;
                curr->size = aligned_size;

                stats.used_memory += sizeof(heap_block_t);
                if (stats.free_memory >= sizeof(heap_block_t)) {
                    stats.free_memory -= sizeof(heap_block_t);
                }
            }

            curr->is_free = 0;
            stats.used_memory += curr->size;
            if (stats.free_memory >= curr->size) {
                stats.free_memory -= curr->size;
            } else {
                stats.free_memory = 0;
            }
            stats.allocation_count++;

            smp_spin_unlock(&s_heap_spinlock);
            return (void*)(curr + 1);
        }
        curr = curr->next;
    }

    printf("[HEAP] Out of memory! Requested: %llu bytes\n", (unsigned long long)size);
    smp_spin_unlock(&s_heap_spinlock);
    return NULL;
}

void kfree(void *ptr) {
    if (!ptr) return;

    if (!kheap_is_valid_ptr(ptr)) {
        return;
    }

    smp_spin_lock(&s_heap_spinlock);

    heap_block_t *block = (heap_block_t*)ptr - 1;

    if (block->is_free) {
        printf("[HEAP] Warning: Double free detected at 0x%016llX!\n", (unsigned long long)ptr);
        smp_spin_unlock(&s_heap_spinlock);
        return;
    }

    block->is_free = 1;
    stats.free_memory += block->size;
    if (stats.used_memory >= block->size) {
        stats.used_memory -= block->size;
    }
    stats.free_count++;

    // Coalesce with next block if free
    if (block->next && block->next->is_free) {
        block->size += sizeof(heap_block_t) + block->next->size;
        stats.free_memory += sizeof(heap_block_t);
        if (stats.used_memory >= sizeof(heap_block_t)) {
            stats.used_memory -= sizeof(heap_block_t);
        }
        block->next = block->next->next;
        if (block->next) {
            block->next->prev = block;
        }
    }

    // Coalesce with prev block if free
    if (block->prev && block->prev->is_free) {
        block->prev->size += sizeof(heap_block_t) + block->size;
        stats.free_memory += sizeof(heap_block_t);
        if (stats.used_memory >= sizeof(heap_block_t)) {
            stats.used_memory -= sizeof(heap_block_t);
        }
        block->prev->next = block->next;
        if (block->next) {
            block->next->prev = block->prev;
        }
    }

    smp_spin_unlock(&s_heap_spinlock);
}

void* kcalloc(size_t num, size_t size) {
    if (num != 0 && size > (size_t)-1 / num) return NULL;
    size_t total = num * size;
    void *ptr = kmalloc(total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

void* krealloc(void *ptr, size_t new_size) {
    if (!ptr) return kmalloc(new_size);
    if (new_size == 0) {
        kfree(ptr);
        return NULL;
    }

    heap_block_t *block = (heap_block_t*)ptr - 1;
    if (block->canary_head != HEAP_CANARY) {
        printf("[HEAP] FATAL: Invalid canary in krealloc!\n");
        return NULL;
    }

    if (block->size >= new_size) {
        return ptr; // Already big enough
    }

    void *new_ptr = kmalloc(new_size);
    if (new_ptr) {
        memcpy(new_ptr, ptr, block->size);
        kfree(ptr);
    }
    return new_ptr;
}

void kheap_get_stats(heap_stats_t *out_stats) {
    if (out_stats) {
        *out_stats = stats;
    }
}

void kheap_dump(void) {
    printf("[HEAP] Total: %llu KB | Used: %llu KB | Free: %llu KB | Allocs: %llu | Frees: %llu\n",
           (unsigned long long)(stats.total_memory / 1024),
           (unsigned long long)(stats.used_memory / 1024),
           (unsigned long long)(stats.free_memory / 1024),
           (unsigned long long)stats.allocation_count,
           (unsigned long long)stats.free_count);
}
