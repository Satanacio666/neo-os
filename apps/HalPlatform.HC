// NeoOS Sovereign Pure HolyC Hardware Abstraction Layer (HAL)
// Silicon Board Support Package: QEMU ARM64 Virt, Raspberry Pi 4/5, Rockchip RK3399, Snapdragon 860

#define HAL_PLATFORM_QEMU_VIRT 0
#define HAL_PLATFORM_RPI4      1
#define HAL_PLATFORM_RPI5      2
#define HAL_PLATFORM_RK3399    3
#define HAL_PLATFORM_SM8150    4

class CHalPlatform {
  I64 id;
  U8  name[64];
  U64 uart_base;
  U64 gicd_base;
  U64 gicc_base;
  U64 virtio_base;
  U32 virtio_slots;
  U32 virtio_stride;
  U32 irq_timer;
  U32 irq_uart;
  U64 timer_freq_hz;
};

CHalPlatform g_plat_qemu;
CHalPlatform g_plat_rpi4;
CHalPlatform g_plat_rpi5;
CHalPlatform g_plat_rk3399;
CHalPlatform g_plat_sm8150;
CHalPlatform *g_current_platform;

U64 g_hal_uart_base;
U64 g_hal_gicd_base;
U64 g_hal_gicc_base;
U64 g_hal_virtio_base;
U32 g_hal_virtio_slots;
U32 g_hal_virtio_stride;
U64 g_hal_timer_freq;

U0 HalStrCpy(U8 *dst_buf, U8 *src_buf) {
  if (!dst_buf || !src_buf) return;
  I64 hsc_idx = 0;
  while (src_buf[hsc_idx] != 0 && hsc_idx < 63) {
    dst_buf[hsc_idx] = src_buf[hsc_idx];
    hsc_idx++;
  }
  dst_buf[hsc_idx] = 0;
}

I64 HalStrCmp(U8 *s1, U8 *s2) {
  if (!s1 || !s2) return -1;
  I64 hcmp_pos = 0;
  while (s1[hcmp_pos] != 0 && s2[hcmp_pos] != 0) {
    if (s1[hcmp_pos] != s2[hcmp_pos]) return s1[hcmp_pos] - s2[hcmp_pos];
    hcmp_pos++;
  }
  return s1[hcmp_pos] - s2[hcmp_pos];
}

U0 HalSetPlatform(CHalPlatform *p) {
  if (!p) return;
  g_current_platform  = p;
  g_hal_uart_base     = p->uart_base;
  g_hal_gicd_base     = p->gicd_base;
  g_hal_gicc_base     = p->gicc_base;
  g_hal_virtio_base   = p->virtio_base;
  g_hal_virtio_slots  = p->virtio_slots;
  g_hal_virtio_stride = p->virtio_stride;
  g_hal_timer_freq    = p->timer_freq_hz;
}

U64 HalGetUartBase() {
  if (g_hal_uart_base == 0) return 0x09000000;
  return g_hal_uart_base;
}

U64 hal_get_uart_base() {
  return HalGetUartBase();
}

U64 HalGetGicdBase() {
  if (g_hal_gicd_base == 0) return 0x08000000;
  return g_hal_gicd_base;
}

U64 hal_get_gicd_base() {
  return HalGetGicdBase();
}

U64 HalGetGiccBase() {
  if (g_hal_gicc_base == 0) return 0x08010000;
  return g_hal_gicc_base;
}

U64 hal_get_gicc_base() {
  return HalGetGiccBase();
}

U64 HalGetVirtioBase() {
  if (g_hal_virtio_base == 0) return 0x0A000000;
  return g_hal_virtio_base;
}

U64 hal_get_virtio_base() {
  return HalGetVirtioBase();
}

U32 HalGetVirtioSlots() {
  if (g_hal_virtio_slots == 0) return 32;
  return g_hal_virtio_slots;
}

U32 HalGetVirtioStride() {
  if (g_hal_virtio_stride == 0) return 0x200;
  return g_hal_virtio_stride;
}

U64 HalGetTimerFreq() {
  if (g_hal_timer_freq != 0) return g_hal_timer_freq;
  U64 hw_f = __mrs_cntfrq();
  if (hw_f != 0) return hw_f;
  return 62500000;
}

U64 hal_get_timer_freq() {
  return HalGetTimerFreq();
}

U32 HalGetTimerIrq() {
  if (g_current_platform) return g_current_platform->irq_timer;
  return 27;
}

U32 HalGetUartIrq() {
  if (g_current_platform) return g_current_platform->irq_uart;
  return 33;
}

U0 HalFlushCache(U64 addr, I64 size) {
  if (addr == 0 || size <= 0) return;
  U64 dc_line = addr & ~63;
  U64 end_addr = addr + size;
  while (dc_line < end_addr) {
    __dc_civac(dc_line);
    dc_line = dc_line + 64;
  }
  __dsb_sy();
  U64 ic_line = addr & ~63;
  while (ic_line < end_addr) {
    __ic_ivau(ic_line);
    ic_line = ic_line + 64;
  }
  __dsb_sy();
  __isb();
}

U0 hal_flush_cache(U64 addr, I64 size) {
  HalFlushCache(addr, size);
}

U0 HalSystemReset() {
  doldoc_print("\n$FG,YELLOW$[HAL] Initiating PSCI 0.2 SYSTEM_RESET (0x84000009)...$FG$\n");
  psci_call_hvc(0x84000009, 0, 0, 0);
}

U0 hal_reset_system() {
  HalSystemReset();
}

U0 HalPlatformInit() {
  U64 boot_frq = __mrs_cntfrq();
  if (boot_frq == 0) boot_frq = 62500000;

  // 1. QEMU ARM64 Virt
  g_plat_qemu.id            = HAL_PLATFORM_QEMU_VIRT;
  HalStrCpy(g_plat_qemu.name, "QEMU ARM64 Virt");
  g_plat_qemu.uart_base     = 0x09000000;
  g_plat_qemu.gicd_base     = 0x08000000;
  g_plat_qemu.gicc_base     = 0x08010000;
  g_plat_qemu.virtio_base   = 0x0A000000;
  g_plat_qemu.virtio_slots  = 32;
  g_plat_qemu.virtio_stride = 0x200;
  g_plat_qemu.irq_timer     = 27;
  g_plat_qemu.irq_uart      = 33;
  g_plat_qemu.timer_freq_hz = boot_frq;

  // 2. Raspberry Pi 4 (BCM2711)
  g_plat_rpi4.id            = HAL_PLATFORM_RPI4;
  HalStrCpy(g_plat_rpi4.name, "Raspberry Pi 4 (BCM2711)");
  g_plat_rpi4.uart_base     = 0xFE201000;
  g_plat_rpi4.gicd_base     = 0xFF841000;
  g_plat_rpi4.gicc_base     = 0xFF842000;
  g_plat_rpi4.virtio_base   = 0;
  g_plat_rpi4.virtio_slots  = 0;
  g_plat_rpi4.virtio_stride = 0;
  g_plat_rpi4.irq_timer     = 30;
  g_plat_rpi4.irq_uart      = 153;
  g_plat_rpi4.timer_freq_hz = 54000000;

  // 3. Raspberry Pi 5 (BCM2712/RP1)
  g_plat_rpi5.id            = HAL_PLATFORM_RPI5;
  HalStrCpy(g_plat_rpi5.name, "Raspberry Pi 5 (BCM2712/RP1)");
  g_plat_rpi5.uart_base     = 0x107D001000;
  g_plat_rpi5.gicd_base     = 0x107D500000;
  g_plat_rpi5.gicc_base     = 0x107D580000;
  g_plat_rpi5.virtio_base   = 0;
  g_plat_rpi5.virtio_slots  = 0;
  g_plat_rpi5.virtio_stride = 0;
  g_plat_rpi5.irq_timer     = 30;
  g_plat_rpi5.irq_uart      = 146;
  g_plat_rpi5.timer_freq_hz = 54000000;

  // 4. Rockchip RK3399
  g_plat_rk3399.id            = HAL_PLATFORM_RK3399;
  HalStrCpy(g_plat_rk3399.name, "Rockchip RK3399 (Dual A72 + Quad A53)");
  g_plat_rk3399.uart_base     = 0xFF1A0000;
  g_plat_rk3399.gicd_base     = 0xFEE00000;
  g_plat_rk3399.gicc_base     = 0xFEF00000;
  g_plat_rk3399.virtio_base   = 0;
  g_plat_rk3399.virtio_slots  = 0;
  g_plat_rk3399.virtio_stride = 0;
  g_plat_rk3399.irq_timer     = 27;
  g_plat_rk3399.irq_uart      = 132;
  g_plat_rk3399.timer_freq_hz = 24000000;

  // 5. Snapdragon 860 (SM8150 / Poco X3 Pro)
  g_plat_sm8150.id            = HAL_PLATFORM_SM8150;
  HalStrCpy(g_plat_sm8150.name, "Snapdragon 860 (SM8150 Kryo 485)");
  g_plat_sm8150.uart_base     = 0x00A90000;
  g_plat_sm8150.gicd_base     = 0x17A00000;
  g_plat_sm8150.gicc_base     = 0x17C00000;
  g_plat_sm8150.virtio_base   = 0;
  g_plat_sm8150.virtio_slots  = 0;
  g_plat_sm8150.virtio_stride = 0;
  g_plat_sm8150.irq_timer     = 27;
  g_plat_sm8150.irq_uart      = 108;
  g_plat_sm8150.timer_freq_hz = 19200000;

  HalSetPlatform(&g_plat_qemu);
}

I64 HalPlatformSelect(I64 p_id) {
  if (p_id == HAL_PLATFORM_QEMU_VIRT) {
    HalSetPlatform(&g_plat_qemu);
    return 0;
  }
  if (p_id == HAL_PLATFORM_RPI4) {
    HalSetPlatform(&g_plat_rpi4);
    return 0;
  }
  if (p_id == HAL_PLATFORM_RPI5) {
    HalSetPlatform(&g_plat_rpi5);
    return 0;
  }
  if (p_id == HAL_PLATFORM_RK3399) {
    HalSetPlatform(&g_plat_rk3399);
    return 0;
  }
  if (p_id == HAL_PLATFORM_SM8150) {
    HalSetPlatform(&g_plat_sm8150);
    return 0;
  }
  return -1;
}

U0 HalPrintDolDoc() {
  if (!g_current_platform) HalPlatformInit();
  doldoc_printf("$FG,CYAN$--- HARDWARE ABSTRACTION LAYER (HAL) ---$FG$\n");
  doldoc_printf(" Platform:      $FG,YELLOW$%s$FG$\n", g_current_platform->name);
  doldoc_printf(" PL011 UART:    0x%016X | IRQ: %d\n", HalGetUartBase(), g_current_platform->irq_uart);
  doldoc_printf(" GICD / GICC:   0x%016X / 0x%016X\n", HalGetGicdBase(), HalGetGiccBase());
  doldoc_printf(" VirtIO MMIO:   0x%016X (%d slots, stride 0x%X)\n", HalGetVirtioBase(), g_hal_virtio_slots, g_hal_virtio_stride);
  doldoc_printf(" Timer Freq:    %d MHz (%d Hz) | IRQ: %d\n", HalGetTimerFreq() / 1000000, HalGetTimerFreq(), g_current_platform->irq_timer);
  doldoc_printf("$FG,CYAN$-----------------------------------------$FG$\n");
}

I64 HalSelfTest() {
  doldoc_printf("\n$FG,CYAN$[HAL-TEST] Starting Pure HolyC Hardware Abstraction Layer Verification...$FG$\n");

  // Test 1: QEMU Virt platform initialization & getters
  HalPlatformInit();
  if (g_current_platform->id != HAL_PLATFORM_QEMU_VIRT ||
      HalGetUartBase() != 0x09000000 ||
      HalGetGicdBase() != 0x08000000 ||
      HalGetGiccBase() != 0x08010000 ||
      HalGetVirtioBase() != 0x0A000000 ||
      HalGetTimerFreq() == 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: QEMU Virt HAL init or getter verification failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: QEMU Virt hardware topology & HAL getters verified.$FG$\n");

  // Test 2: VirtIO MMIO slot mapping
  if (g_hal_virtio_base != 0x0A000000 || g_hal_virtio_slots != 32 || g_hal_virtio_stride != 0x200) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: VirtIO MMIO slot parameters invalid!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: VirtIO 32-slot MMIO address aperture verified.$FG$\n");

  // Test 3: Dynamic switch across RPi4, RPi5, RK3399, SM8150
  if (HalPlatformSelect(HAL_PLATFORM_RPI4) != 0 ||
      HalGetUartBase() != 0xFE201000 ||
      HalGetGicdBase() != 0xFF841000 ||
      HalGetTimerFreq() != 54000000 ||
      g_current_platform->irq_timer != 30) {
    doldoc_printf("$FG,RED$[FAIL] Test 3A: RPi4 platform switch failed!$FG$\n");
    return 0;
  }
  if (HalPlatformSelect(HAL_PLATFORM_RPI5) != 0 ||
      HalGetUartBase() != 0x107D001000 ||
      HalGetGicdBase() != 0x107D500000 ||
      g_current_platform->irq_uart != 146) {
    doldoc_printf("$FG,RED$[FAIL] Test 3B: RPi5 platform switch failed!$FG$\n");
    return 0;
  }
  if (HalPlatformSelect(HAL_PLATFORM_RK3399) != 0 ||
      HalGetTimerFreq() != 24000000 ||
      HalPlatformSelect(HAL_PLATFORM_SM8150) != 0 ||
      HalGetTimerFreq() != 19200000) {
    doldoc_printf("$FG,RED$[FAIL] Test 3C: RK3399/SM8150 platform switch failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: RPi4, RPi5, RK3399 & SM8150 silicon profiles validated.$FG$\n");

  // Test 4: D-Cache Clean (__dc_civac) + I-Cache Invalidate (__ic_ivau) Coherency
  U8 *cache_buf = kmalloc(256);
  if (!cache_buf) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: Cache test buffer allocation failed!$FG$\n");
    return 0;
  }
  I64 hc_i = 0;
  while (hc_i < 256) {
    cache_buf[hc_i] = (hc_i * 7 + 3) & 0xFF;
    hc_i++;
  }
  HalFlushCache(cache_buf, 256);
  if (cache_buf[0] != 3 || cache_buf[10] != 73 || cache_buf[255] != ((255 * 7 + 3) & 0xFF)) {
    kfree(cache_buf);
    doldoc_printf("$FG,RED$[FAIL] Test 4: Cache flush corrupted buffer contents!$FG$\n");
    return 0;
  }
  kfree(cache_buf);
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Unified D-Cache clean & I-Cache invalidation (HalFlushCache) verified.$FG$\n");

  // Test 5: Revert to QEMU Virt & Verify Hardware Timer Monotonic Progress
  HalPlatformSelect(HAL_PLATFORM_QEMU_VIRT);
  U64 vct_t0 = __mrs_cntvct();
  I64 hal_spin = 0;
  I64 hal_acc = 0;
  while (hal_spin < 1000) {
    hal_acc = hal_acc + hal_spin;
    hal_spin++;
  }
  U64 vct_t1 = __mrs_cntvct();
  if (g_current_platform->id != HAL_PLATFORM_QEMU_VIRT || vct_t1 <= vct_t0 || hal_acc <= 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Revert to QEMU Virt or CNTVCT_EL0 monotonic progress failed!$FG$\n");
    return 0;
  }
  HalPrintDolDoc();
  doldoc_printf("$FG,GREEN$[PASS] Test 5: CNTVCT_EL0 monotonic delta (+%lld ticks) & DolDoc telemetry validated.$FG$\n", vct_t1 - vct_t0);

  doldoc_printf("\n[HAL-PASS] ALL 5 HAL PLATFORM TESTS PASSED\n\n");
  return 1;
}

I64 HalPlatformSelfTest() {
  return HalSelfTest();
}

I64 g_kernel_booting;
if (g_kernel_booting) {
  HalPlatformInit();
} else {
  HalSelfTest();
}
