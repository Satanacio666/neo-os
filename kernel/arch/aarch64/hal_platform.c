#include "hal_platform.h"

// Standard QEMU AArch64 Virt Platform Definition
static const hal_platform_t s_platform_qemu_virt = {
    .name          = "QEMU ARM64 Virt",
    .uart_base     = 0x09000000ULL,
    .gicd_base     = 0x08000000ULL,
    .gicc_base     = 0x08010000ULL,
    .virtio_base   = 0x0A000000ULL,
    .virtio_slots  = 32,
    .virtio_stride = 0x200,
    .irq_timer     = 27,
    .irq_uart      = 33,
};

static const hal_platform_t *s_current_platform = &s_platform_qemu_virt;

// Cached global variables for fast static inline lookups
uintptr_t g_hal_uart_base     = 0x09000000ULL;
uintptr_t g_hal_gicd_base     = 0x08000000ULL;
uintptr_t g_hal_gicc_base     = 0x08010000ULL;
uintptr_t g_hal_virtio_base   = 0x0A000000ULL;
uint32_t  g_hal_virtio_slots  = 32;
uint32_t  g_hal_virtio_stride = 0x200;

void hal_platform_init(void) {
    hal_set_platform(&s_platform_qemu_virt);
    printf("[HAL] Platform initialized: %s\n", s_current_platform->name);
    printf("[HAL]   UART: 0x%016llX | GICD: 0x%016llX | GICC: 0x%016llX\n",
           (unsigned long long)g_hal_uart_base,
           (unsigned long long)g_hal_gicd_base,
           (unsigned long long)g_hal_gicc_base);
    printf("[HAL]   VirtIO MMIO: 0x%016llX (%u slots, stride 0x%X)\n",
           (unsigned long long)g_hal_virtio_base,
           g_hal_virtio_slots, g_hal_virtio_stride);
}

const hal_platform_t* hal_get_platform(void) {
    return s_current_platform;
}

void hal_set_platform(const hal_platform_t *platform) {
    if (!platform) return;
    s_current_platform  = platform;
    g_hal_uart_base     = platform->uart_base;
    g_hal_gicd_base     = platform->gicd_base;
    g_hal_gicc_base     = platform->gicc_base;
    g_hal_virtio_base   = platform->virtio_base;
    g_hal_virtio_slots  = platform->virtio_slots;
    g_hal_virtio_stride = platform->virtio_stride;
}
