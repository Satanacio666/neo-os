#include "hal_platform.h"

// Standard QEMU AArch64 Virt Platform Definition
const hal_platform_t g_platform_qemu_virt = {
    .id            = HAL_PLATFORM_QEMU_VIRT,
    .name          = "QEMU ARM64 Virt",
    .uart_base     = 0x09000000ULL,
    .gicd_base     = 0x08000000ULL,
    .gicc_base     = 0x08010000ULL,
    .virtio_base   = 0x0A000000ULL,
    .virtio_slots  = 32,
    .virtio_stride = 0x200,
    .irq_timer     = 27,
    .irq_uart      = 33,
    .timer_freq_hz = 62500000ULL,
};

// Broadcom BCM2711 Platform (Raspberry Pi 4)
const hal_platform_t g_platform_rpi4 = {
    .id            = HAL_PLATFORM_RPI4,
    .name          = "Raspberry Pi 4 (BCM2711)",
    .uart_base     = 0xFE201000ULL, // PL011 UART0
    .gicd_base     = 0xFF841000ULL, // GIC-400 Distributor
    .gicc_base     = 0xFF842000ULL, // GIC-400 CPU Interface
    .virtio_base   = 0x00000000ULL, // Direct eMMC / PCIe
    .virtio_slots  = 0,
    .virtio_stride = 0,
    .irq_timer     = 30,
    .irq_uart      = 153,
    .timer_freq_hz = 54000000ULL,
};

// Broadcom BCM2712 Platform (Raspberry Pi 5)
const hal_platform_t g_platform_rpi5 = {
    .id            = HAL_PLATFORM_RPI5,
    .name          = "Raspberry Pi 5 (BCM2712/RP1)",
    .uart_base     = 0x107D001000ULL, // RP1 UART0
    .gicd_base     = 0x107D500000ULL, // GIC-500 Distributor
    .gicc_base     = 0x107D580000ULL, // GICv3 Redistributor
    .virtio_base   = 0x00000000ULL,
    .virtio_slots  = 0,
    .virtio_stride = 0,
    .irq_timer     = 30,
    .irq_uart      = 146,
    .timer_freq_hz = 54000000ULL,
};

static const hal_platform_t *s_current_platform = &g_platform_qemu_virt;

// Cached global variables for fast static inline lookups
uintptr_t g_hal_uart_base     = 0x09000000ULL;
uintptr_t g_hal_gicd_base     = 0x08000000ULL;
uintptr_t g_hal_gicc_base     = 0x08010000ULL;
uintptr_t g_hal_virtio_base   = 0x0A000000ULL;
uint32_t  g_hal_virtio_slots  = 32;
uint32_t  g_hal_virtio_stride = 0x200;

void hal_platform_init(void) {
    hal_set_platform(&g_platform_qemu_virt);
    printf("[HAL] Platform initialized: %s\n", s_current_platform->name);
    printf("[HAL]   UART: 0x%016llX | GICD: 0x%016llX | GICC: 0x%016llX\n",
           (unsigned long long)g_hal_uart_base,
           (unsigned long long)g_hal_gicd_base,
           (unsigned long long)g_hal_gicc_base);
    if (g_hal_virtio_slots > 0) {
        printf("[HAL]   VirtIO MMIO: 0x%016llX (%u slots, stride 0x%X)\n",
               (unsigned long long)g_hal_virtio_base,
               g_hal_virtio_slots, g_hal_virtio_stride);
    } else {
        printf("[HAL]   Physical Silicon Mode: Direct Native MMIO bus\n");
    }
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

int hal_platform_select(hal_platform_id_t id) {
    switch (id) {
        case HAL_PLATFORM_QEMU_VIRT:
            hal_set_platform(&g_platform_qemu_virt);
            return 0;
        case HAL_PLATFORM_RPI4:
            hal_set_platform(&g_platform_rpi4);
            return 0;
        case HAL_PLATFORM_RPI5:
            hal_set_platform(&g_platform_rpi5);
            return 0;
        default:
            return -1;
    }
}

