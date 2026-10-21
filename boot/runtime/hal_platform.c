#include "hal_platform.h"

/*
 * Minimal early-boot HAL stub (P2.1). See hal_platform.h for why this exists.
 * The full, multi-platform HAL is apps/HalPlatform.HC.
 */

#define HAL_BOOT_VIRTIO_BASE   0x0A000000ULL
#define HAL_BOOT_VIRTIO_SLOTS  32u
#define HAL_BOOT_VIRTIO_STRIDE 0x200u

static uintptr_t s_hal_virtio_base   = HAL_BOOT_VIRTIO_BASE;
static uint32_t  s_hal_virtio_slots  = HAL_BOOT_VIRTIO_SLOTS;
static uint32_t  s_hal_virtio_stride = HAL_BOOT_VIRTIO_STRIDE;

uintptr_t hal_get_virtio_base(uint32_t slot) {
    return s_hal_virtio_base + (uintptr_t)slot * s_hal_virtio_stride;
}

uint32_t hal_get_virtio_slots(void) {
    return s_hal_virtio_slots;
}

void hal_platform_init(void) {
    s_hal_virtio_base   = HAL_BOOT_VIRTIO_BASE;
    s_hal_virtio_slots  = HAL_BOOT_VIRTIO_SLOTS;
    s_hal_virtio_stride = HAL_BOOT_VIRTIO_STRIDE;
    printf("[HAL] bootstrap stub: VirtIO MMIO 0x%016llX (%u slots, stride 0x%X)\n",
           (unsigned long long)s_hal_virtio_base, s_hal_virtio_slots, s_hal_virtio_stride);
}
