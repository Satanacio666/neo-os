#include "virtio_blk.h"
#include "../../kernel/symbols/symbols.h"
#include <uefi.h>

static uintptr_t mmio_base = 0;
static uint64_t  disk_capacity_sectors = 0;

// Aligned 32KB buffer for VirtIO queue rings (descriptors, available, used)
static uint8_t __attribute__((aligned(4096))) vq_buffer[32768];
static uint32_t g_queue_num = 256;
static vring_desc_t  *vq_desc = NULL;
static vring_avail_t *vq_avail = NULL;
static vring_used_t  *vq_used = NULL;

static virtio_blk_req_t __attribute__((aligned(16))) g_req;
static volatile uint8_t __attribute__((aligned(16))) g_status;

static inline void mmio_write32(uintptr_t reg, uint32_t val) {
    *(volatile uint32_t*)(mmio_base + reg) = val;
}

static inline uint32_t mmio_read32(uintptr_t reg) {
    return *(volatile uint32_t*)(mmio_base + reg);
}

static inline void flush_cache_range(uintptr_t vaddr, size_t size) {
    uintptr_t start = vaddr & ~63ULL;
    uintptr_t end = vaddr + size;
    for (uintptr_t p = start; p < end; p += 64) {
        asm volatile("dc civac, %0" :: "r"(p) : "memory");
    }
    asm volatile("dsb sy\nisb" ::: "memory");
}

int virtio_blk_init(void) {
    mmio_base = 0;

    // In ARM QEMU 'virt' board, 32 VirtIO MMIO slots are mapped at 0x0A000000 - 0x0A003E00
    for (int slot = 0; slot < 32; slot++) {
        uintptr_t base = 0x0A000000 + slot * 0x200;
        uint32_t magic = *(volatile uint32_t*)(base + VIRTIO_MMIO_MAGIC_VALUE);
        if (magic == VIRTIO_MMIO_MAGIC) {
            uint32_t dev_id = *(volatile uint32_t*)(base + VIRTIO_MMIO_DEVICE_ID);
            if (dev_id == VIRTIO_DEV_BLOCK) {
                mmio_base = base;
                printf("[VIRTIO-BLK] Found VirtIO Block Device at MMIO Slot #%d (0x%08llX)\n",
                       slot, (unsigned long long)mmio_base);
                break;
            }
        }
    }

    if (!mmio_base) {
        printf("[VIRTIO-BLK] No VirtIO block device detected.\n");
        return -1;
    }

    // 1. Reset device
    mmio_write32(VIRTIO_MMIO_STATUS, 0);

    // 2. Set ACKNOWLEDGE and DRIVER bits
    mmio_write32(VIRTIO_MMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);

    uint32_t version = mmio_read32(VIRTIO_MMIO_VERSION);
    printf("[VIRTIO-BLK] VirtIO MMIO Version: %u\n", version);

    // 3. Negotiate features
    if (version == 2) {
        mmio_write32(VIRTIO_MMIO_DEVICE_FEATURES_SEL, 1);
        uint32_t f1 = mmio_read32(VIRTIO_MMIO_DEVICE_FEATURES);
        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES, f1 & 1); // Accept VIRTIO_F_VERSION_1

        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0);
        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES, 0);

        mmio_write32(VIRTIO_MMIO_STATUS, mmio_read32(VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_FEATURES_OK);
        uint32_t st = mmio_read32(VIRTIO_MMIO_STATUS);
        if (!(st & VIRTIO_STATUS_FEATURES_OK)) {
            printf("[VIRTIO-BLK] Error: Device rejected FEATURES_OK (status: 0x%X)\n", st);
            return -1;
        }
    } else {
        // Legacy VirtIO: guest page size must be set before queue setup
        mmio_write32(0x028, 4096); // GuestPageSize = 4096
    }

    // 4. Configure Virtqueue 0
    mmio_write32(VIRTIO_MMIO_QUEUE_SEL, 0);
    uint32_t q_max = mmio_read32(VIRTIO_MMIO_QUEUE_NUM_MAX);
    printf("[VIRTIO-BLK] Queue 0 Max Elements: %u\n", q_max);
    if (q_max == 0) {
        printf("[VIRTIO-BLK] Error: Queue 0 not supported by device\n");
        return -1;
    }
    g_queue_num = (q_max > 256) ? 256 : q_max;

    size_t avail_offset = g_queue_num * sizeof(vring_desc_t);
    size_t avail_end = avail_offset + sizeof(uint16_t) * (3 + g_queue_num);
    size_t used_offset = (avail_end + 4095) & ~4095;

    memset(vq_buffer, 0, sizeof(vq_buffer));
    vq_desc = (vring_desc_t*)&vq_buffer[0];
    vq_avail = (vring_avail_t*)&vq_buffer[avail_offset];
    vq_used = (vring_used_t*)&vq_buffer[used_offset];

    if (version == 1) {
        // Legacy VirtIO MMIO (Version 1)
        mmio_write32(0x038, g_queue_num);       // QueueNum
        mmio_write32(0x03C, 4096);              // QueueAlign = 4096
        uint32_t pfn = (uint32_t)(((uintptr_t)vq_buffer) >> 12);
        mmio_write32(0x040, pfn);               // QueuePFN
        printf("[VIRTIO-BLK] Configured Legacy Queue 0 (Size: %u, PFN: 0x%X, Addr: 0x%p, Avail: +%zu, Used: +%zu)\n",
               g_queue_num, pfn, vq_buffer, avail_offset, used_offset);
    } else {
        // Modern VirtIO MMIO (Version 2)
        mmio_write32(VIRTIO_MMIO_QUEUE_NUM, g_queue_num);
        mmio_write32(VIRTIO_MMIO_QUEUE_DESC_LOW, (uint32_t)((uintptr_t)vq_desc));
        mmio_write32(VIRTIO_MMIO_QUEUE_DESC_HIGH, (uint32_t)(((uintptr_t)vq_desc) >> 32));
        mmio_write32(VIRTIO_MMIO_QUEUE_DRIVER_LOW, (uint32_t)((uintptr_t)vq_avail));
        mmio_write32(VIRTIO_MMIO_QUEUE_DRIVER_HIGH, (uint32_t)(((uintptr_t)vq_avail) >> 32));
        mmio_write32(VIRTIO_MMIO_QUEUE_DEVICE_LOW, (uint32_t)((uintptr_t)vq_used));
        mmio_write32(VIRTIO_MMIO_QUEUE_DEVICE_HIGH, (uint32_t)(((uintptr_t)vq_used) >> 32));
        mmio_write32(VIRTIO_MMIO_QUEUE_READY, 1);
    }

    // 5. Set DRIVER_OK status
    mmio_write32(VIRTIO_MMIO_STATUS, mmio_read32(VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_DRIVER_OK);
    printf("[VIRTIO-BLK] Device Status: 0x%X\n", mmio_read32(VIRTIO_MMIO_STATUS));

    // 6. Read disk capacity from device configuration space
    uint32_t cap_low = mmio_read32(VIRTIO_MMIO_CONFIG);
    uint32_t cap_high = mmio_read32(VIRTIO_MMIO_CONFIG + 4);
    disk_capacity_sectors = ((uint64_t)cap_high << 32) | cap_low;

    printf("[VIRTIO-BLK] Storage ready: %llu MB (%llu sectors @ 512 bytes)\n",
           (unsigned long long)((disk_capacity_sectors * 512) / (1024 * 1024)),
           (unsigned long long)disk_capacity_sectors);

    // Register storage routines in HolyC symbol table
    symbols_register("virtio_read", (void*)virtio_blk_read_sectors, SYM_FUNC);
    symbols_register("virtio_write", (void*)virtio_blk_write_sectors, SYM_FUNC);
    symbols_register("virtio_capacity", (void*)virtio_blk_get_capacity, SYM_FUNC);

    return 0;
}

uint64_t virtio_blk_get_capacity(void) {
    return disk_capacity_sectors;
}

int virtio_blk_read_sectors(uint64_t lba, uint32_t count, void *buffer) {
    if (!mmio_base || !buffer || count == 0) return -1;
    if (lba + count > disk_capacity_sectors) return -1;

    g_req.type = VIRTIO_BLK_T_IN;
    g_req.reserved = 0;
    g_req.sector = lba;
    g_status = 0xFF; // Sentinel

    // Descriptor 0: Request Header (Read by device)
    vq_desc[0].addr = (uint64_t)(uintptr_t)&g_req;
    vq_desc[0].len = sizeof(virtio_blk_req_t);
    vq_desc[0].flags = VRING_DESC_F_NEXT;
    vq_desc[0].next = 1;

    // Descriptor 1: Data Buffer (Written by device)
    vq_desc[1].addr = (uint64_t)(uintptr_t)buffer;
    vq_desc[1].len = count * SECTOR_SIZE;
    vq_desc[1].flags = VRING_DESC_F_NEXT | VRING_DESC_F_WRITE;
    vq_desc[1].next = 2;

    // Descriptor 2: Status Byte (Written by device)
    vq_desc[2].addr = (uint64_t)(uintptr_t)&g_status;
    vq_desc[2].len = 1;
    vq_desc[2].flags = VRING_DESC_F_WRITE;
    vq_desc[2].next = 0;

    uint16_t last_used = vq_used->idx;

    // Submit into available ring
    uint16_t avail_idx = vq_avail->idx;
    vq_avail->ring[avail_idx % g_queue_num] = 0;

    asm volatile("dmb sy" ::: "memory");
    vq_avail->idx = avail_idx + 1;
    asm volatile("dmb sy" ::: "memory");

    flush_cache_range((uintptr_t)&g_req, sizeof(g_req));
    flush_cache_range((uintptr_t)&g_status, 16);
    flush_cache_range((uintptr_t)buffer, count * SECTOR_SIZE);
    flush_cache_range((uintptr_t)vq_desc, sizeof(vring_desc_t) * 3);
    flush_cache_range((uintptr_t)vq_avail, sizeof(vring_avail_t) + sizeof(uint16_t) * g_queue_num);

    // Notify queue
    mmio_write32(VIRTIO_MMIO_QUEUE_NOTIFY, 0);

    // Wait for completion (poll used ring and status byte)
    uint32_t timeout = 10000000;
    while (vq_used->idx == last_used && g_status == 0xFF && --timeout) {
        flush_cache_range((uintptr_t)&g_status, 16);
        flush_cache_range((uintptr_t)vq_used, sizeof(vring_used_t) + sizeof(vring_used_elem_t) * 4);
        asm volatile("dmb sy\nyield" ::: "memory");
    }

    flush_cache_range((uintptr_t)buffer, count * SECTOR_SIZE);

    if (timeout == 0) {
        printf("[VIRTIO-BLK] Timeout waiting for sector transfer (LBA: %llu, used: %u, st: 0x%X)!\n",
               (unsigned long long)lba, vq_used->idx, g_status);
        return -1;
    }

    return (g_status == 0) ? 0 : -1;
}

int virtio_blk_write_sectors(uint64_t lba, uint32_t count, const void *buffer) {
    if (!mmio_base || !buffer || count == 0) return -1;
    if (lba + count > disk_capacity_sectors) return -1;

    g_req.type = VIRTIO_BLK_T_OUT;
    g_req.reserved = 0;
    g_req.sector = lba;
    g_status = 0xFF; // Sentinel

    // Descriptor 0: Request Header (Read by device)
    vq_desc[0].addr = (uint64_t)(uintptr_t)&g_req;
    vq_desc[0].len = sizeof(virtio_blk_req_t);
    vq_desc[0].flags = VRING_DESC_F_NEXT;
    vq_desc[0].next = 1;

    // Descriptor 1: Data Buffer (Read by device)
    vq_desc[1].addr = (uint64_t)(uintptr_t)buffer;
    vq_desc[1].len = count * SECTOR_SIZE;
    vq_desc[1].flags = VRING_DESC_F_NEXT; // Not VRING_DESC_F_WRITE!
    vq_desc[1].next = 2;

    // Descriptor 2: Status Byte (Written by device)
    vq_desc[2].addr = (uint64_t)(uintptr_t)&g_status;
    vq_desc[2].len = 1;
    vq_desc[2].flags = VRING_DESC_F_WRITE;
    vq_desc[2].next = 0;

    uint16_t last_used = vq_used->idx;

    // Submit into available ring
    uint16_t avail_idx = vq_avail->idx;
    vq_avail->ring[avail_idx % g_queue_num] = 0;

    asm volatile("dmb sy" ::: "memory");
    vq_avail->idx = avail_idx + 1;
    asm volatile("dmb sy" ::: "memory");

    flush_cache_range((uintptr_t)&g_req, sizeof(g_req));
    flush_cache_range((uintptr_t)&g_status, 16);
    flush_cache_range((uintptr_t)buffer, count * SECTOR_SIZE);
    flush_cache_range((uintptr_t)vq_desc, sizeof(vring_desc_t) * 3);
    flush_cache_range((uintptr_t)vq_avail, sizeof(vring_avail_t) + sizeof(uint16_t) * g_queue_num);

    // Notify queue
    mmio_write32(VIRTIO_MMIO_QUEUE_NOTIFY, 0);

    // Wait for completion (poll used ring and status byte)
    uint32_t timeout = 10000000;
    while (vq_used->idx == last_used && g_status == 0xFF && --timeout) {
        flush_cache_range((uintptr_t)&g_status, 16);
        flush_cache_range((uintptr_t)vq_used, sizeof(vring_used_t) + sizeof(vring_used_elem_t) * 4);
        asm volatile("dmb sy\nyield" ::: "memory");
    }

    if (timeout == 0) {
        printf("[VIRTIO-BLK] Timeout waiting for sector write (LBA: %llu, used: %u, st: 0x%X)!\n",
               (unsigned long long)lba, vq_used->idx, g_status);
        return -1;
    }

    return (g_status == 0) ? 0 : -1;
}
