#ifndef NEO_HAL_PLATFORM_H
#define NEO_HAL_PLATFORM_H

#include <uefi.h>

/*
 * NeoOS Hardware Abstraction Layer (HAL)
 * Decouples platform-specific MMIO base addresses from kernel core logic.
 * Supports QEMU virt, Raspberry Pi 4/5, Rockchip RK3588, and custom silicon.
 */

typedef enum {
    HAL_PLATFORM_QEMU_VIRT = 0,
    HAL_PLATFORM_RPI4      = 1,
    HAL_PLATFORM_RPI5      = 2
} hal_platform_id_t;

typedef struct {
    hal_platform_id_t id;
    const char       *name;
    uintptr_t         uart_base;
    uintptr_t         gicd_base;
    uintptr_t         gicc_base;
    uintptr_t         virtio_base;
    uint32_t          virtio_slots;
    uint32_t          virtio_stride;
    uint32_t          irq_timer;
    uint32_t          irq_uart;
    uint64_t          timer_freq_hz;
} hal_platform_t;

// Platform lifecycle
void                   hal_platform_init(void);
const hal_platform_t*  hal_get_platform(void);
void                   hal_set_platform(const hal_platform_t *platform);
int                    hal_platform_select(hal_platform_id_t id);

// Pre-defined Board Profiles
extern const hal_platform_t g_platform_qemu_virt;
extern const hal_platform_t g_platform_rpi4;
extern const hal_platform_t g_platform_rpi5;

// Cached global accessors (Zero-overhead single LDR instructions)
extern uintptr_t g_hal_uart_base;
extern uintptr_t g_hal_gicd_base;
extern uintptr_t g_hal_gicc_base;
extern uintptr_t g_hal_virtio_base;
extern uint32_t  g_hal_virtio_slots;
extern uint32_t  g_hal_virtio_stride;

static inline uintptr_t hal_get_uart_base(void) {
    return g_hal_uart_base;
}

static inline uintptr_t hal_get_gicd_base(void) {
    return g_hal_gicd_base;
}

static inline uintptr_t hal_get_gicc_base(void) {
    return g_hal_gicc_base;
}

static inline uintptr_t hal_get_virtio_base(uint32_t slot) {
    return g_hal_virtio_base + slot * g_hal_virtio_stride;
}

static inline uint32_t hal_get_virtio_slots(void) {
    return g_hal_virtio_slots;
}

// Memory & instruction cache coherency flush for JIT emission
void hal_flush_cache(void *addr, size_t size);

#endif // NEO_HAL_PLATFORM_H
