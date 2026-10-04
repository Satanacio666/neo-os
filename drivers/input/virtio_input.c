#include "virtio_input.h"
#include "keyboard.h"
#include "mouse.h"
#include "../block/virtio_blk.h" // vring descriptors, avail, used structs
#include "../../kernel/arch/aarch64/hal_platform.h"
#include <uefi.h>

#define MAX_VIRTIO_INPUT_DEVS 4
#define VIRTIO_INPUT_QUEUE_SIZE 64

typedef struct {
    uintptr_t mmio_base;
    uint32_t  version;
    uint32_t  queue_num;
    uint16_t  last_used_idx;
    vring_desc_t  *vq_desc;
    vring_avail_t *vq_avail;
    vring_used_t  *vq_used;
    virtio_input_event_t event_buf[VIRTIO_INPUT_QUEUE_SIZE] __attribute__((aligned(16)));
    uint8_t   vq_ring_mem[8192] __attribute__((aligned(4096)));
    int       active;
} virtio_input_dev_t;

static virtio_input_dev_t s_input_devs[MAX_VIRTIO_INPUT_DEVS];
static int s_num_input_devs = 0;

static uint32_t s_screen_w = 1024;
static uint32_t s_screen_h = 768;

static int s_shift_state = 0;
static int s_mouse_btn_l = 0;
static int s_mouse_btn_r = 0;
static int s_mouse_curr_x = 512;
static int s_mouse_curr_y = 384;

static inline void mmio_write32(uintptr_t addr, uint32_t val) {
    *(volatile uint32_t*)addr = val;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    return *(volatile uint32_t*)addr;
}

static inline void flush_cache_range(uintptr_t vaddr, size_t size) {
    uintptr_t start = vaddr & ~63ULL;
    uintptr_t end = vaddr + size;
    for (uintptr_t p = start; p < end; p += 64) {
        asm volatile("dc civac, %0" :: "r"(p) : "memory");
    }
    asm volatile("dsb sy\nisb" ::: "memory");
}

static const int s_keymap_lower[128] = {
    [1] = KEY_ESC,
    [2] = '1', [3] = '2', [4] = '3', [5] = '4', [6] = '5',
    [7] = '6', [8] = '7', [9] = '8', [10] = '9', [11] = '0',
    [12] = '-', [13] = '=', [14] = KEY_BACKSPACE, [15] = '\t',
    [16] = 'q', [17] = 'w', [18] = 'e', [19] = 'r', [20] = 't',
    [21] = 'y', [22] = 'u', [23] = 'i', [24] = 'o', [25] = 'p',
    [26] = '[', [27] = ']', [28] = KEY_ENTER,
    [29] = 0,    // Left Ctrl
    [30] = 'a', [31] = 's', [32] = 'd', [33] = 'f', [34] = 'g',
    [35] = 'h', [36] = 'j', [37] = 'k', [38] = 'l', [39] = ';',
    [40] = '\'', [41] = '`',
    [42] = 0,    // Left Shift
    [43] = '\\', [44] = 'z', [45] = 'x', [46] = 'c', [47] = 'v',
    [48] = 'b', [49] = 'n', [50] = 'm', [51] = ',', [52] = '.',
    [53] = '/',  [54] = 0, // Right Shift
    [55] = '*',  [56] = 0, // Left Alt
    [57] = ' ',  // Space
    [58] = 0,    // CapsLock
    [71] = '7', [72] = '8', [73] = '9', [74] = '-',
    [75] = '4', [76] = '5', [77] = '6', [78] = '+',
    [79] = '1', [80] = '2', [81] = '3', [82] = '0', [83] = '.',
    [96] = KEY_ENTER,
    [103] = KEY_UP,
    [104] = KEY_PAGE_UP,
    [105] = KEY_LEFT,
    [106] = KEY_RIGHT,
    [108] = KEY_DOWN,
    [109] = KEY_PAGE_DOWN,
};

static const int s_keymap_upper[128] = {
    [1] = KEY_ESC,
    [2] = '!', [3] = '@', [4] = '#', [5] = '$', [6] = '%',
    [7] = '^', [8] = '&', [9] = '*', [10] = '(', [11] = ')',
    [12] = '_', [13] = '+', [14] = KEY_BACKSPACE, [15] = '\t',
    [16] = 'Q', [17] = 'W', [18] = 'E', [19] = 'R', [20] = 'T',
    [21] = 'Y', [22] = 'U', [23] = 'I', [24] = 'O', [25] = 'P',
    [26] = '{', [27] = '}', [28] = KEY_ENTER,
    [29] = 0,
    [30] = 'A', [31] = 'S', [32] = 'D', [33] = 'F', [34] = 'G',
    [35] = 'H', [36] = 'J', [37] = 'K', [38] = 'L', [39] = ':',
    [40] = '"', [41] = '~',
    [42] = 0,
    [43] = '|', [44] = 'Z', [45] = 'X', [46] = 'C', [47] = 'V',
    [48] = 'B', [49] = 'N', [50] = 'M', [51] = '<', [52] = '>',
    [53] = '?', [54] = 0,
    [55] = '*', [56] = 0,
    [57] = ' ',
    [58] = 0,
    [71] = '7', [72] = '8', [73] = '9', [74] = '-',
    [75] = '4', [76] = '5', [77] = '6', [78] = '+',
    [79] = '1', [80] = '2', [81] = '3', [82] = '0', [83] = '.',
    [96] = KEY_ENTER,
    [103] = KEY_UP,
    [104] = KEY_PAGE_UP,
    [105] = KEY_LEFT,
    [106] = KEY_RIGHT,
    [108] = KEY_DOWN,
    [109] = KEY_PAGE_DOWN,
};

static void process_input_event(const virtio_input_event_t *ev) {
    if (!ev) return;

    if (ev->type == EV_KEY) {
        // Mouse Buttons
        if (ev->code == BTN_LEFT) {
            s_mouse_btn_l = (ev->value != 0);
            mouse_set_button(s_mouse_btn_l, s_mouse_btn_r);
        } else if (ev->code == BTN_RIGHT) {
            s_mouse_btn_r = (ev->value != 0);
            mouse_set_button(s_mouse_btn_l, s_mouse_btn_r);
        } else if (ev->code == 42 || ev->code == 54) {
            // Shift modifier
            s_shift_state = (ev->value != 0);
        } else if (ev->value == 1 || ev->value == 2) {
            // Key press or autorepeat
            if (ev->code < 128) {
                int ch = s_shift_state ? s_keymap_upper[ev->code] : s_keymap_lower[ev->code];
                if (ch != 0) {
                    keyboard_queue_char(ch);
                }
            }
        }
    } else if (ev->type == EV_ABS) {
        // Absolute Coordinates (Tablet)
        if (ev->code == ABS_X) {
            s_mouse_curr_x = (int)(((uint64_t)ev->value * (uint64_t)s_screen_w) / 32767ULL);
            if (s_mouse_curr_x >= (int)s_screen_w) s_mouse_curr_x = s_screen_w - 1;
            mouse_set_pos(s_mouse_curr_x, s_mouse_curr_y);
        } else if (ev->code == ABS_Y) {
            s_mouse_curr_y = (int)(((uint64_t)ev->value * (uint64_t)s_screen_h) / 32767ULL);
            if (s_mouse_curr_y >= (int)s_screen_h) s_mouse_curr_y = s_screen_h - 1;
            mouse_set_pos(s_mouse_curr_x, s_mouse_curr_y);
        }
    } else if (ev->type == EV_REL) {
        // Relative Coordinates (Mouse)
        if (ev->code == REL_X) {
            s_mouse_curr_x += (int32_t)ev->value;
            if (s_mouse_curr_x < 0) s_mouse_curr_x = 0;
            if (s_mouse_curr_x >= (int)s_screen_w) s_mouse_curr_x = s_screen_w - 1;
            mouse_set_pos(s_mouse_curr_x, s_mouse_curr_y);
        } else if (ev->code == REL_Y) {
            s_mouse_curr_y += (int32_t)ev->value;
            if (s_mouse_curr_y < 0) s_mouse_curr_y = 0;
            if (s_mouse_curr_y >= (int)s_screen_h) s_mouse_curr_y = s_screen_h - 1;
            mouse_set_pos(s_mouse_curr_x, s_mouse_curr_y);
        }
    }
}

int virtio_input_init(uint32_t screen_width, uint32_t screen_height) {
    s_screen_w = screen_width;
    s_screen_h = screen_height;
    s_mouse_curr_x = screen_width / 2;
    s_mouse_curr_y = screen_height / 2;
    s_num_input_devs = 0;

    uint32_t slots = hal_get_virtio_slots();
    for (uint32_t slot = 0; slot < slots && s_num_input_devs < MAX_VIRTIO_INPUT_DEVS; slot++) {
        uintptr_t base = hal_get_virtio_base(slot);
        uint32_t magic = mmio_read32(base + VIRTIO_MMIO_MAGIC_VALUE);
        if (magic == VIRTIO_MMIO_MAGIC) {
            uint32_t dev_id = mmio_read32(base + VIRTIO_MMIO_DEVICE_ID);
            if (dev_id == VIRTIO_DEV_INPUT) {
                virtio_input_dev_t *dev = &s_input_devs[s_num_input_devs];
                memset(dev, 0, sizeof(*dev));
                dev->mmio_base = base;

                // 1. Reset device
                mmio_write32(base + VIRTIO_MMIO_STATUS, 0);

                // 2. Acknowledge & Driver status
                mmio_write32(base + VIRTIO_MMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);

                // 3. Negotiate features
                uint32_t version = mmio_read32(base + VIRTIO_MMIO_VERSION);
                dev->version = version;
                if (version == 2) {
                    mmio_write32(base + VIRTIO_MMIO_DEVICE_FEATURES_SEL, 1);
                    uint32_t f1 = mmio_read32(base + VIRTIO_MMIO_DEVICE_FEATURES);
                    mmio_write32(base + VIRTIO_MMIO_DRIVER_FEATURES_SEL, 1);
                    mmio_write32(base + VIRTIO_MMIO_DRIVER_FEATURES, f1 & 1); // VIRTIO_F_VERSION_1

                    mmio_write32(base + VIRTIO_MMIO_DRIVER_FEATURES_SEL, 0);
                    mmio_write32(base + VIRTIO_MMIO_DRIVER_FEATURES, 0);

                    mmio_write32(base + VIRTIO_MMIO_STATUS, mmio_read32(base + VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_FEATURES_OK);
                    if (!(mmio_read32(base + VIRTIO_MMIO_STATUS) & VIRTIO_STATUS_FEATURES_OK)) {
                        printf("[VIRTIO-INPUT] Slot #%u: FEATURES_OK rejected!\n", slot);
                        continue;
                    }
                } else {
                    mmio_write32(base + 0x028, 4096);
                }

                // 4. Configure Queue 0 (Event Queue)
                mmio_write32(base + VIRTIO_MMIO_QUEUE_SEL, 0);
                uint32_t max_q = mmio_read32(base + VIRTIO_MMIO_QUEUE_NUM_MAX);
                if (max_q == 0) {
                    printf("[VIRTIO-INPUT] Slot #%u: Queue 0 unavailable!\n", slot);
                    continue;
                }
                dev->queue_num = (max_q < VIRTIO_INPUT_QUEUE_SIZE) ? max_q : VIRTIO_INPUT_QUEUE_SIZE;

                size_t avail_offset = dev->queue_num * sizeof(vring_desc_t);
                size_t avail_end = avail_offset + sizeof(uint16_t) * (3 + dev->queue_num);
                size_t used_offset = (avail_end + 4095) & ~4095;

                dev->vq_desc  = (vring_desc_t*)&dev->vq_ring_mem[0];
                dev->vq_avail = (vring_avail_t*)&dev->vq_ring_mem[avail_offset];
                dev->vq_used  = (vring_used_t*)&dev->vq_ring_mem[used_offset];

                // Pre-populate descriptors pointing to writeable event buffers
                for (uint32_t i = 0; i < dev->queue_num; i++) {
                    dev->vq_desc[i].addr = (uint64_t)(uintptr_t)&dev->event_buf[i];
                    dev->vq_desc[i].len = sizeof(virtio_input_event_t);
                    dev->vq_desc[i].flags = VRING_DESC_F_WRITE;
                    dev->vq_desc[i].next = 0;
                    dev->vq_avail->ring[i] = (uint16_t)i;
                }
                dev->vq_avail->idx = (uint16_t)dev->queue_num;
                dev->last_used_idx = 0;

                if (version == 1) {
                    mmio_write32(base + 0x038, dev->queue_num);
                    mmio_write32(base + 0x03C, 4096);
                    mmio_write32(base + 0x040, (uint32_t)(((uintptr_t)dev->vq_ring_mem) >> 12));
                } else {
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_NUM, dev->queue_num);
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_DESC_LOW, (uint32_t)((uintptr_t)dev->vq_desc));
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_DESC_HIGH, (uint32_t)(((uintptr_t)dev->vq_desc) >> 32));
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_DRIVER_LOW, (uint32_t)((uintptr_t)dev->vq_avail));
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_DRIVER_HIGH, (uint32_t)(((uintptr_t)dev->vq_avail) >> 32));
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_DEVICE_LOW, (uint32_t)((uintptr_t)dev->vq_used));
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_DEVICE_HIGH, (uint32_t)(((uintptr_t)dev->vq_used) >> 32));
                    mmio_write32(base + VIRTIO_MMIO_QUEUE_READY, 1);
                }

                // 5. Set DRIVER_OK
                mmio_write32(base + VIRTIO_MMIO_STATUS, mmio_read32(base + VIRTIO_MMIO_STATUS) | VIRTIO_STATUS_DRIVER_OK);

                // Flush cache and notify device that buffers are posted
                flush_cache_range((uintptr_t)dev->event_buf, sizeof(dev->event_buf));
                flush_cache_range((uintptr_t)dev->vq_ring_mem, sizeof(dev->vq_ring_mem));
                asm volatile("dsb sy" ::: "memory");
                mmio_write32(base + VIRTIO_MMIO_QUEUE_NOTIFY, 0);

                dev->active = 1;
                s_num_input_devs++;
                printf("[VIRTIO-INPUT] Device #%d initialized at MMIO Slot #%u (0x%08llX)\n",
                       s_num_input_devs, slot, (unsigned long long)base);
            }
        }
    }

    if (s_num_input_devs == 0) {
        printf("[VIRTIO-INPUT] No VirtIO input devices detected.\n");
        return -1;
    }

    printf("[VIRTIO-INPUT] %d VirtIO input device(s) ready (Ring 0 bare-metal).\n", s_num_input_devs);
    return 0;
}

void virtio_input_poll(void) {
    if (s_num_input_devs == 0) return;

    for (int d = 0; d < s_num_input_devs; d++) {
        virtio_input_dev_t *dev = &s_input_devs[d];
        if (!dev->active) continue;

        // Invalidate used ring cache to see new host completions
        flush_cache_range((uintptr_t)dev->vq_used, sizeof(vring_used_t) + sizeof(vring_used_elem_t) * dev->queue_num);

        uint16_t cur_used = dev->vq_used->idx;
        int recycled = 0;

        while (dev->last_used_idx != cur_used) {
            uint16_t ring_idx = dev->last_used_idx % dev->queue_num;
            uint32_t desc_id = dev->vq_used->ring[ring_idx].id;
            dev->last_used_idx++;

            if (desc_id < dev->queue_num) {
                flush_cache_range((uintptr_t)&dev->event_buf[desc_id], sizeof(virtio_input_event_t));
                process_input_event(&dev->event_buf[desc_id]);

                // Recycle buffer back into available ring
                uint16_t avail_idx = dev->vq_avail->idx;
                dev->vq_avail->ring[avail_idx % dev->queue_num] = (uint16_t)desc_id;
                asm volatile("dmb sy" ::: "memory");
                dev->vq_avail->idx = avail_idx + 1;
                asm volatile("dmb sy" ::: "memory");
                recycled = 1;
            }
        }

        if (recycled) {
            flush_cache_range((uintptr_t)dev->vq_avail, sizeof(vring_avail_t) + sizeof(uint16_t) * dev->queue_num);
            asm volatile("dsb sy" ::: "memory");
            mmio_write32(dev->mmio_base + VIRTIO_MMIO_QUEUE_NOTIFY, 0);
        }
    }
}

int virtio_input_is_active(void) {
    return (s_num_input_devs > 0);
}
