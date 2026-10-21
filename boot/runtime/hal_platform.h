#ifndef NEO_HAL_PLATFORM_H
#define NEO_HAL_PLATFORM_H

#include <uefi.h>

/*
 * Minimal early-boot HAL stub (P2.1).
 *
 * The full HAL — board profiles, cache maintenance, platform switching, reset —
 * now lives in apps/HalPlatform.HC, which is the single source of truth. This C
 * stub exists ONLY because the C VirtIO block driver (boot/runtime/virtio_blk.c)
 * must locate its MMIO aperture at early boot, before any .HC module can run.
 * It is retired at P2.2 when virtio_blk moves to VirtioBlk.HC.
 */

// VirtIO MMIO aperture used by the C block driver during bootstrap.
uintptr_t hal_get_virtio_base(uint32_t slot);
uint32_t  hal_get_virtio_slots(void);

// Initialise the bootstrap HAL (QEMU virt defaults).
void hal_platform_init(void);

#endif // NEO_HAL_PLATFORM_H
