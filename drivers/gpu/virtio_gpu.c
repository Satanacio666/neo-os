#include "virtio_gpu.h"
#include "../../kernel/symbols/symbols.h"
#include <uefi.h>
#include "../block/virtio_blk.h" // For MMIO defines and vring structs
#include "gfx_backend.h"

static uintptr_t mmio_base = 0;
static uint32_t screen_width = 1280;
static uint32_t screen_height = 720;

extern uint32_t* gfx_get_backbuffer(void);
extern uint32_t gfx_get_canvas_width(void);
extern uint32_t gfx_get_canvas_height(void);

// Virtqueue 0 (Control Queue)
static uint8_t __attribute__((aligned(4096))) vq_buffer[32768];
static uint32_t g_queue_num = 64;
static vring_desc_t  *vq_desc = NULL;
static vring_avail_t *vq_avail = NULL;
static vring_used_t  *vq_used = NULL;

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

static int virtio_gpu_send_cmd(void *cmd, uint32_t cmd_size, void *resp, uint32_t resp_size) {
    uint16_t last_used = vq_used->idx;

    vq_desc[0].addr = (uint64_t)(uintptr_t)cmd;
    vq_desc[0].len = cmd_size;
    vq_desc[0].flags = VRING_DESC_F_NEXT;
    vq_desc[0].next = 1;

    vq_desc[1].addr = (uint64_t)(uintptr_t)resp;
    vq_desc[1].len = resp_size;
    vq_desc[1].flags = VRING_DESC_F_WRITE;
    vq_desc[1].next = 0;

    uint16_t avail_idx = vq_avail->idx;
    vq_avail->ring[avail_idx % g_queue_num] = 0;

    asm volatile("dmb sy" ::: "memory");
    vq_avail->idx = avail_idx + 1;
    asm volatile("dmb sy" ::: "memory");

    flush_cache_range((uintptr_t)cmd, cmd_size);
    flush_cache_range((uintptr_t)resp, resp_size);
    flush_cache_range((uintptr_t)vq_desc, sizeof(vring_desc_t) * 2);
    flush_cache_range((uintptr_t)vq_avail, sizeof(vring_avail_t) + sizeof(uint16_t) * g_queue_num);

    asm volatile("dsb sy" ::: "memory");
    mmio_write32(VIRTIO_MMIO_QUEUE_NOTIFY, 0);

    uint32_t timeout = 1000000;
    while (*(volatile uint16_t*)&vq_used->idx == last_used && --timeout) {
        asm volatile("dmb ld\nyield" ::: "memory");
    }

    flush_cache_range((uintptr_t)vq_used, sizeof(vring_used_t) + sizeof(vring_used_elem_t) * 4);
    flush_cache_range((uintptr_t)resp, resp_size);

    if (timeout == 0) {
        printf("[VIRTIO-GPU] Command timeout!\n");
        return -1;
    }

    return 0;
}

static virtio_gpu_ctrl_hdr __attribute__((aligned(16))) cmd_get_info;
static virtio_gpu_resp_display_info __attribute__((aligned(16))) resp_get_info;

static virtio_gpu_resource_create_2d __attribute__((aligned(16))) cmd_create;
static virtio_gpu_ctrl_hdr __attribute__((aligned(16))) resp_create;

static struct {
    virtio_gpu_resource_attach_backing cmd;
    virtio_gpu_mem_entry entry;
} __attribute__((packed)) __attribute__((aligned(16))) cmd_attach;
static virtio_gpu_ctrl_hdr __attribute__((aligned(16))) resp_attach;

static virtio_gpu_set_scanout __attribute__((aligned(16))) cmd_scanout;
static virtio_gpu_ctrl_hdr __attribute__((aligned(16))) resp_scanout;

static virtio_gpu_transfer_to_host_2d __attribute__((aligned(16))) cmd_transfer;
static virtio_gpu_ctrl_hdr __attribute__((aligned(16))) resp_transfer;

static virtio_gpu_resource_flush __attribute__((aligned(16))) cmd_flush;
static virtio_gpu_ctrl_hdr __attribute__((aligned(16))) resp_flush;

int virtio_gpu_init(void) {
    mmio_base = 0;

    for (int slot = 0; slot < 32; slot++) {
        uintptr_t base = 0x0A000000 + slot * 0x200;
        uint32_t magic = *(volatile uint32_t*)(base + VIRTIO_MMIO_MAGIC_VALUE);
        if (magic == VIRTIO_MMIO_MAGIC) {
            uint32_t dev_id = *(volatile uint32_t*)(base + VIRTIO_MMIO_DEVICE_ID);
            if (dev_id == VIRTIO_DEV_GPU) {
                mmio_base = base;
                printf("[VIRTIO-GPU] Found at MMIO Slot #%d (0x%08llX)\n", slot, (unsigned long long)mmio_base);
                break;
            }
        }
    }

    if (!mmio_base) {
        printf("[VIRTIO-GPU] Not found.\n");
        return -1;
    }

    mmio_write32(VIRTIO_MMIO_STATUS, 0);
    mmio_write32(VIRTIO_MMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);

    uint32_t version = mmio_read32(VIRTIO_MMIO_VERSION);
    if (version == 2) {
        mmio_write32(VIRTIO_MMIO_DEVICE_FEATURES_SEL, 1);
        uint32_t f1 = mmio_read32(VIRTIO_MMIO_DEVICE_FEATURES);
        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES, f1 & 1); // VIRTIO_F_VERSION_1

        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0);
        mmio_write32(VIRTIO_MMIO_DRIVER_FEATURES, 0);

        mmio_write32(VIRTIO_MMIO_STATUS, mmio_read32(VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_FEATURES_OK);
        if (!(mmio_read32(VIRTIO_MMIO_STATUS) & VIRTIO_STATUS_FEATURES_OK)) {
            printf("[VIRTIO-GPU] FEATURES_OK failed.\n");
            return -1;
        }
    } else {
        mmio_write32(0x028, 4096);
    }

    // Configure Queue 0
    mmio_write32(VIRTIO_MMIO_QUEUE_SEL, 0);
    size_t avail_offset = g_queue_num * sizeof(vring_desc_t);
    size_t avail_end = avail_offset + sizeof(uint16_t) * (3 + g_queue_num);
    size_t used_offset = (avail_end + 4095) & ~4095;

    memset(vq_buffer, 0, sizeof(vq_buffer));
    vq_desc = (vring_desc_t*)&vq_buffer[0];
    vq_avail = (vring_avail_t*)&vq_buffer[avail_offset];
    vq_used = (vring_used_t*)&vq_buffer[used_offset];

    if (version == 1) {
        mmio_write32(0x038, g_queue_num);
        mmio_write32(0x03C, 4096);
        mmio_write32(0x040, (uint32_t)(((uintptr_t)vq_buffer) >> 12));
    } else {
        mmio_write32(VIRTIO_MMIO_QUEUE_NUM, g_queue_num);
        mmio_write32(VIRTIO_MMIO_QUEUE_DESC_LOW, (uint32_t)((uintptr_t)vq_desc));
        mmio_write32(VIRTIO_MMIO_QUEUE_DESC_HIGH, (uint32_t)(((uintptr_t)vq_desc) >> 32));
        mmio_write32(VIRTIO_MMIO_QUEUE_DRIVER_LOW, (uint32_t)((uintptr_t)vq_avail));
        mmio_write32(VIRTIO_MMIO_QUEUE_DRIVER_HIGH, (uint32_t)(((uintptr_t)vq_avail) >> 32));
        mmio_write32(VIRTIO_MMIO_QUEUE_DEVICE_LOW, (uint32_t)((uintptr_t)vq_used));
        mmio_write32(VIRTIO_MMIO_QUEUE_DEVICE_HIGH, (uint32_t)(((uintptr_t)vq_used) >> 32));
        mmio_write32(VIRTIO_MMIO_QUEUE_READY, 1);
    }

    // Skip Queue 1 (Cursor)
    mmio_write32(VIRTIO_MMIO_QUEUE_SEL, 1);
    if (version == 1) {
        mmio_write32(0x038, 0);
    } else {
        mmio_write32(VIRTIO_MMIO_QUEUE_READY, 0);
    }

    mmio_write32(VIRTIO_MMIO_STATUS, mmio_read32(VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_DRIVER_OK);

    memset(&cmd_get_info, 0, sizeof(cmd_get_info));
    cmd_get_info.type = VIRTIO_GPU_CMD_GET_DISPLAY_INFO;
    memset(&resp_get_info, 0, sizeof(resp_get_info));
    
    if (virtio_gpu_send_cmd(&cmd_get_info, sizeof(cmd_get_info), &resp_get_info, sizeof(resp_get_info)) == 0) {
        if (resp_get_info.hdr.type == VIRTIO_GPU_RESP_OK_DISPLAY_INFO && resp_get_info.pmodes[0].enabled) {
            screen_width = resp_get_info.pmodes[0].r.width;
            screen_height = resp_get_info.pmodes[0].r.height;
            printf("[VIRTIO-GPU] Native display: %ux%u\n", screen_width, screen_height);
        }
    }

    // Crucial: Always synchronize VirtIO-GPU dimensions with the actual backbuffer canvas dimensions
    uint32_t c_w = gfx_get_canvas_width();
    uint32_t c_h = gfx_get_canvas_height();
    if (c_w > 0 && c_h > 0) {
        screen_width = c_w;
        screen_height = c_h;
        printf("[VIRTIO-GPU] Synchronized with kernel canvas: %ux%u\n", screen_width, screen_height);
    }

    memset(&cmd_create, 0, sizeof(cmd_create));
    cmd_create.hdr.type = VIRTIO_GPU_CMD_RESOURCE_CREATE_2D;
    cmd_create.resource_id = 1;
    cmd_create.format = VIRTIO_GPU_FORMAT_B8G8R8X8_UNORM;
    cmd_create.width = screen_width;
    cmd_create.height = screen_height;
    virtio_gpu_send_cmd(&cmd_create, sizeof(cmd_create), &resp_create, sizeof(resp_create));

    uint32_t* backbuffer = gfx_get_backbuffer();
    if (!backbuffer) {
        printf("[VIRTIO-GPU] No backbuffer available!\n");
        return -1;
    }

    memset(&cmd_attach, 0, sizeof(cmd_attach));
    cmd_attach.cmd.hdr.type = VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING;
    cmd_attach.cmd.resource_id = 1;
    cmd_attach.cmd.nr_entries = 1;
    cmd_attach.entry.addr = (uint64_t)(uintptr_t)backbuffer;
    cmd_attach.entry.length = screen_width * screen_height * 4;
    virtio_gpu_send_cmd(&cmd_attach, sizeof(cmd_attach), &resp_attach, sizeof(resp_attach));

    memset(&cmd_scanout, 0, sizeof(cmd_scanout));
    cmd_scanout.hdr.type = VIRTIO_GPU_CMD_SET_SCANOUT;
    cmd_scanout.scanout_id = 0;
    cmd_scanout.resource_id = 1;
    cmd_scanout.r.x = 0;
    cmd_scanout.r.y = 0;
    cmd_scanout.r.width = screen_width;
    cmd_scanout.r.height = screen_height;
    virtio_gpu_send_cmd(&cmd_scanout, sizeof(cmd_scanout), &resp_scanout, sizeof(resp_scanout));

    symbols_register("virtio_gpu_flush_rect", (void*)virtio_gpu_flush_rect, SYM_FUNC);
    symbols_register("virtio_gpu_flush_full", (void*)virtio_gpu_flush_full, SYM_FUNC);

    virtio_gpu_flush_full();

    printf("[VIRTIO-GPU] Initialized.\n");
    return 0;
}

void virtio_gpu_flush_rect(int x, int y, int w, int h) {
    if (!mmio_base || w <= 0 || h <= 0) return;

    // Cache clean for backbuffer region so host reads latest CPU-written pixels
    uint32_t *bb = gfx_get_backbuffer();
    if (bb) {
        if (w == (int)screen_width && h == (int)screen_height) {
            uintptr_t start = (uintptr_t)bb & ~63ULL;
            uintptr_t end = (uintptr_t)bb + (size_t)screen_width * screen_height * 4;
            for (uintptr_t p = start; p < end; p += 64) {
                asm volatile("dc civac, %0" :: "r"(p) : "memory");
            }
        } else {
            for (int r = y; r < y + h; r++) {
                uintptr_t start = (uintptr_t)(bb + r * screen_width + x) & ~63ULL;
                uintptr_t end = (uintptr_t)(bb + r * screen_width + x + w);
                for (uintptr_t p = start; p < end; p += 64) {
                    asm volatile("dc civac, %0" :: "r"(p) : "memory");
                }
            }
        }
        asm volatile("dsb sy\nisb" ::: "memory");
    }

    memset(&cmd_transfer, 0, sizeof(cmd_transfer));
    cmd_transfer.hdr.type = VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D;
    cmd_transfer.resource_id = 1;
    cmd_transfer.offset = (y * screen_width + x) * 4;
    cmd_transfer.r.x = x;
    cmd_transfer.r.y = y;
    cmd_transfer.r.width = w;
    cmd_transfer.r.height = h;
    virtio_gpu_send_cmd(&cmd_transfer, sizeof(cmd_transfer), &resp_transfer, sizeof(resp_transfer));

    memset(&cmd_flush, 0, sizeof(cmd_flush));
    cmd_flush.hdr.type = VIRTIO_GPU_CMD_RESOURCE_FLUSH;
    cmd_flush.resource_id = 1;
    cmd_flush.r.x = x;
    cmd_flush.r.y = y;
    cmd_flush.r.width = w;
    cmd_flush.r.height = h;
    virtio_gpu_send_cmd(&cmd_flush, sizeof(cmd_flush), &resp_flush, sizeof(resp_flush));

    g_gfx_backend.dma_transfers_bytes += (uint64_t)w * h * 4;
    g_gfx_backend.ops_counter++;
}

void virtio_gpu_flush_full(void) {
    virtio_gpu_flush_rect(0, 0, screen_width, screen_height);
}

int virtio_gpu_is_available(void) {
    return mmio_base != 0;
}
