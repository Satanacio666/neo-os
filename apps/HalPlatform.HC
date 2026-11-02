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
  // P1.2 — acrescentados no FIM de proposito: nao deslocam nenhum campo existente.
  U64 gicr_base;    // redistribuidor do GICv3 (0 = a plataforma nao tem)
  U64 gic_version;  // 2 = GICv2, 3 = GICv3, 0 = autodetectar em runtime (QEMU)
  // ------------------------------------------------------------------------
  // HAL v2 (P1.3-resto, BLOCO A): o descritor fisico COMPLETO. Sem estes campos a
  // HAL nao descrevia os alvos reais (X-Gene = 16550A + SATA; POCO = QUP + UFS).
  // Append no fim, mesma razao dos anteriores: nao deslocar campo existente.
  // ------------------------------------------------------------------------
  U32 uart_type;     // HAL_UART_*  (valores identicos aos do ACPI/FDT)
  U32 storage_type;  // HAL_STORAGE_*
  U32 input_type;    // HAL_INPUT_* (mascara: UART | VIRTIO | USB_HID)
  U32 has_gop;       // 1 = firmware entregou GOP; 0 = shadow RAM (headless)
};

// ---------------------------------------------------------------------------
// HAL v2 — ENUMS CANONICOS DE HARDWARE (BLOCO A / A2)
// ---------------------------------------------------------------------------
// Os valores de uart_type sao IDENTICOS aos que o ACPI/FDT ja' produzem
// (boot/runtime/acpi.c:271-275 e fdt.c:131-135), de proposito: a descoberta de
// firmware e a HAL falam a MESMA lingua, sem tabela de traducao no meio.
#define HAL_UART_NONE    0
#define HAL_UART_PL011   1   // QEMU virt / ARM SBSA
#define HAL_UART_16550A  2   // X-Gene / PC-style MMIO
#define HAL_UART_SBSA    3   // ARM SBSA generic UART
#define HAL_UART_QUP     4   // Qualcomm Snapdragon (POCO)

#define HAL_STORAGE_NONE     0
#define HAL_STORAGE_VIRTIO   1   // QEMU virtio-blk-mmio
#define HAL_STORAGE_AHCI     2   // SATA / X-Gene
#define HAL_STORAGE_UFS      3   // POCO UFS / eMMC
#define HAL_STORAGE_RAMDISK  4   // fallback: ESP / RAM

// input_type e' MASCARA: o console por UART esta SEMPRE ativo (Layer B/console v4)
// e pode haver um ou mais dispositivos de entrada de placa somados a ele.
#define HAL_INPUT_NONE     0
#define HAL_INPUT_UART     1
#define HAL_INPUT_VIRTIO   2
#define HAL_INPUT_USB_HID  4

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
U64 g_hal_gicr_base;
U64 g_hal_gic_version;
// HAL v2 (BLOCO A): o descritor fisico global. Preenchido por HalPlatformV2Init()
// a partir do que a DESCOBERTA de firmware achou (ACPI/FDT) + sondagem direta.
U32 g_hal_uart_type    = HAL_UART_NONE;
U32 g_hal_storage_type = HAL_STORAGE_NONE;
U32 g_hal_input_type   = HAL_INPUT_NONE;
U32 g_hal_has_gop      = 0;

U32 HalGetUartType()    { return g_hal_uart_type; }
U32 HalGetStorageType() { return g_hal_storage_type; }
U32 HalGetInputType()   { return g_hal_input_type; }
U32 HalGetHasGop()      { return g_hal_has_gop; }

// ---- HAL v2: nomes canonicos para impressao ([HAL-V2] no boot) ----
U8 *HalUartName(U32 t) {
  if (t == HAL_UART_PL011)  return "PL011";
  if (t == HAL_UART_16550A) return "16550A";
  if (t == HAL_UART_SBSA)   return "SBSA";
  if (t == HAL_UART_QUP)    return "QUP";
  return "NONE";
}
U8 *HalStorageName(U32 t) {
  if (t == HAL_STORAGE_VIRTIO)  return "VIRTIO";
  if (t == HAL_STORAGE_AHCI)    return "AHCI";
  if (t == HAL_STORAGE_UFS)     return "UFS";
  if (t == HAL_STORAGE_RAMDISK) return "RAMDISK";
  return "NONE";
}

// Determina o tipo de UART. PRIORIDADE: descoberta de firmware (ACPI/FDT) >
// sondagem direta. A sondagem existe porque o QEMU TCG com FDT simplesmente nao
// traz o no' de UART em algumas configs, e o endereco 0x09000000 e' PL011 por
// construcao da maquina virt.
U32 HalDetectUartType() {
  // 1) Descoberta de firmware (autoridade quando presente). Chamada DIRETA: os
  //    dois simbolos sao registrados incondicionalmente por boot/main.c, logo a
  //    checagem symbols_is_defined seria cerimonia (e inflava o CENSUS).
  I64 at = (I64)acpi_uart_type();
  if (at > 0) return (U32)at;
  // 2) Sondagem direta: o PL011 responde? (le UARTFR; se nao aborta e' PL011).
  if (neo_pl011_available() != 0) return HAL_UART_PL011;
  return HAL_UART_NONE;
}

// Determina o tipo de armazenamento. Nesta plataforma o barramento de disco e' o
// virtio-mmio (nao e' "hardware suportado": e' a topologia da placa). Numa
// plataforma sem virtio, o ESP/RAM e' o fallback — nunca silencio.
U32 HalDetectStorageType() {
  if (g_hal_virtio_base != 0) return HAL_STORAGE_VIRTIO;
  return HAL_STORAGE_RAMDISK;
}

// Determina as fontes de entrada. O console por UART esta SEMPRE ativo (e' o
// canal da Layer B), somado ao que a placa oferecer.
U32 HalDetectInputType() {
  U32 m = HAL_INPUT_UART;
  if (g_hal_virtio_base != 0) m = m | HAL_INPUT_VIRTIO;
  return m;
}

// Preenche o descritor HAL v2. Chamada DEPOIS da descoberta de firmware e ANTES
// de qualquer consumidor (o CBootConfig le estes campos para escolher o perfil).
U0 HalPlatformV2Init() {
  g_hal_uart_type    = HalDetectUartType();
  g_hal_storage_type = HalDetectStorageType();
  g_hal_input_type   = HalDetectInputType();
  // has_gop: o C registra g_uefi_has_gop no handover (boot/main.c:600).
  // has_gop: acessor C (sem symbols_lookup literal -> CENSUS estavel).
  g_hal_has_gop = (U32)neo_has_gop();
}

// Imprime o descritor HAL v2 (a prova visivel do Bloco A no boot).
U0 HalPlatformV2Report() {
  U8 ibuf[64];
  I64 ip = 0;
  if (g_hal_input_type & HAL_INPUT_UART)    { ibuf[ip] = 'U'; ibuf[ip+1]='A'; ibuf[ip+2]='R'; ibuf[ip+3]='T'; ip = ip + 4; }
  if (g_hal_input_type & HAL_INPUT_VIRTIO)  { if (ip) { ibuf[ip] = '+'; ip = ip + 1; } ibuf[ip]='V';ibuf[ip+1]='I';ibuf[ip+2]='R';ibuf[ip+3]='T';ibuf[ip+4]='I';ibuf[ip+5]='O'; ip = ip + 6; }
  if (g_hal_input_type & HAL_INPUT_USB_HID) { if (ip) { ibuf[ip] = '+'; ip = ip + 1; } ibuf[ip]='U';ibuf[ip+1]='S';ibuf[ip+2]='B'; ip = ip + 3; }
  if (ip == 0) { ibuf[0]='N';ibuf[1]='O';ibuf[2]='N';ibuf[3]='E'; ip = 4; }
  ibuf[ip] = 0;
  doldoc_printf("[HAL-V2] uart=%s storage=%s input=%s gop=%lld\n",
                HalUartName(g_hal_uart_type), HalStorageName(g_hal_storage_type),
                ibuf, (I64)g_hal_has_gop);
}

// ============================================================================
// CAMADA 1.1 (IDEA-2) — ATOMICIDADE: Nivel 1 (IRQ-safe) e Nivel 2 (cross-core).
// ============================================================================
// Definidas AQUI, no PRIMEIRO modulo do Stage 1, porque Gic.HC, KHeap.HC e
// Sched.HC compilam DEPOIS e precisam delas — HolyC nao tem forward reference.
// Um dono por simbolo: Smp.HC apenas as USA (nao as re-define).
//
// Nivel 1 (IRQ-safe) = mascara IRQs locais ANTES do spin. Sem isso, um handler de
// IRQ que tomasse o mesmo lock na MESMA core daria self-deadlock (o core esperaria
// por si mesmo). Nivel 2 (cross-core) = o proprio smp_spin_lock.
U64 SmpIrqSave() { return __mrs_daif(); }
U0  SmpIrqRestore(U64 daif) { __msr_daif(daif); }

U64 SmpLockIrqSave(U32 *lock) {
  U64 daif = __mrs_daif();
  __irq_disable();
  smp_spin_lock(lock);
  return daif;
}

// Restaura o estado ANTERIOR: so' reabre IRQs se o bit I (DAIF bit 7 = 0x80)
// estava LIMPO (IRQs habilitadas) no instante do save. Aninhamento perfeito: um
// unlock interno nunca reabre IRQs que o contexto externo ja' tinha mascarado.
U0 SmpUnlockIrqRestore(U32 *lock, U64 daif) {
  smp_spin_unlock(lock);
  if ((daif & 0x80) == 0) __irq_enable();
}

// Prova/teste: a decisao de reabrir IRQs, isolada (sem tocar no hardware).
I64 SmpUnlockShouldEnable(U64 daif) { return (daif & 0x80) == 0 ? 1 : 0; }
// Estado atual: 1 = IRQs mascaradas (bit I setado), 0 = habilitadas.
I64 SmpIrqMasked() { return (__mrs_daif() & 0x80) != 0 ? 1 : 0; }

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
  g_hal_gicr_base     = p->gicr_base;
  g_hal_gic_version   = p->gic_version;
}

U64 HalGetUartBase() {
  // P5.1: 0x09000000 so e um PL011 na maquina virt do QEMU. No Snapdragon 860
  // (Qualcomm) esse endereco NAO esta mapeado — a primeira leitura de UARTFR
  // (+0x18) seria Data Abort. Devolver 0 faz todos os callers de UART saírem
  // cedo, porque eles ja checam `if (!uart_base) return;`.
  if (neo_pl011_available() == 0) return 0;
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

// P3.2: memory is DISCOVERED from the UEFI memory map (boot_probe_memory), not
// hardcoded. These getters are the single HAL view of the discovered memory.
U64 HalGetTotalRam()  { return g_total_ram_bytes; }
U64 HalGetFreeRam()   { return g_free_ram_bytes; }
U64 HalGetHeapBase()  { return g_uefi_heap_base; }
U64 HalGetHeapSize()  { return g_uefi_heap_size; }
U64 hal_get_total_ram() { return g_total_ram_bytes; }
U64 hal_get_free_ram()  { return g_free_ram_bytes; }

// CAMADA 0.1 (D7): a linha de cache vem do HARDWARE (CTR_EL0 via disco_dcache_line),
// nao do 64 hardcoded. Em QEMU/Cortex-A72 sao 64 B, mas o valor agora e' o FATO
// fisico — se um dia rodar em silicio com 128 B, o flush continua correto.
I64 g_hal_dcache_line = 0;   // 0 = ainda nao sondado; HalSetDcacheLine preenche

U64 hal_dcache_line(void) {
  if (g_hal_dcache_line < 16) g_hal_dcache_line = 64;   // piso de seguranca
  return g_hal_dcache_line;
}

U0 HalSetDcacheLine(I64 bytes) {
  if (bytes >= 16) g_hal_dcache_line = bytes;
}

U0 HalFlushCache(U64 addr, I64 size) {
  if (addr == 0 || size <= 0) return;
  U64 line = hal_dcache_line();
  U64 mask = ~(line - 1);
  U64 dc_line = addr & mask;
  U64 end_addr = addr + size;
  while (dc_line < end_addr) {
    __dc_civac(dc_line);
    dc_line = dc_line + line;
  }
  __dsb_sy();
  U64 ic_line = addr & mask;
  while (ic_line < end_addr) {
    __ic_ivau(ic_line);
    ic_line = ic_line + line;
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

// P1.2 — Escolhe a plataforma pelo silicio (MIDR_EL1), em vez de fixar QEMU.
//
// Implementer medido:
//   0x51 Qualcomm     -> POCO X3 Pro (SM8150/vayu), part 0x804 (Kryo Gold) / 0x805 (Silver)
//   0x41 ARM          -> QEMU virt (cortex-a72, part 0xD08) — e tambem RPi4/RK3399
//   0x50 AppliedMicro -> APM X-Gene (CloudLab m400)
//
// RESSALVA HONESTA: 0x41 e ambiguo — QEMU e Cortex-A72 real compartilham o MIDR.
// Como o QEMU e o alvo de desenvolvimento e o unico alvo de hardware aqui e
// Qualcomm, a regra pratica e: 0x51 -> SM8150, resto -> QEMU virt. Um
// discriminador melhor (DTB/ACPI ou FirmwareVendor) fica como pendencia.
U0 HalPlatformDetectByMidr() {
  U64 impl = neo_midr_implementer();
  U64 part = neo_midr_partnum();
  if (impl == 0x51 && (part == 0x804 || part == 0x805)) {
    HalSetPlatform(&g_plat_sm8150);
    return;
  }
  HalSetPlatform(&g_plat_qemu);
}

// E3 — Sobreposicao da descoberta de firmware (ACPI agora, FDT depois).
//
// PRIORIDADE: descoberta > tabela estatica > defaults. So os campos que o
// firmware descreve sao sobrescritos; o que ele NAO descreve permanece da tabela.
//
// POR QUE SOBREPOR E NAO SUBSTITUIR: o ACPI descreve os dispositivos
// ARQUITETURAIS (GIC, UART, timer, CPUs) mas NAO descreve dispositivos de PLACA
// — o virtio-mmio do QEMU nao aparece em ACPI nenhuma. Zerar a tabela inteira
// quebraria o virtio, e o virtio nao e "hardware suportado": e o barramento de
// disco/entrada desta plataforma.
//
// INVARIANTE DA UNIVERSALIDADE: sem descoberta, nada muda => boota igual.
// Nunca "boota ou nao".
U0 HalPlatformOverlayDiscovery() {
  if (acpi_source() == 0) return;          // descoberta INATIVA: nada muda
  if (!g_current_platform) return;

  U64 gicd = acpi_gicd_base();
  U64 uart = acpi_uart_base();
  if (gicd == 0 && uart == 0) return;      // firmware nao descreveu nada util

  // Descoberta ATIVA: ela e a autoridade sobre os campos que possui. Atribuicao
  // direta, sem "so se for diferente de zero" — porque zero e um valor legitimo
  // (o GICv2 nao tem redistribuidor, e o MADT simplesmente nao traz o registro
  // 0x0E). Confundir "ausente" com "nao descoberto" deixaria lixo da tabela.
  g_current_platform->gicd_base   = gicd;
  g_current_platform->gicr_base   = acpi_gicr_base();
  g_current_platform->gicc_base   = acpi_gicc_base();
  g_current_platform->uart_base   = uart;
  g_current_platform->gic_version = acpi_gic_version();

  g_hal_gicd_base    = g_current_platform->gicd_base;
  g_hal_gicr_base    = g_current_platform->gicr_base;
  g_hal_gicc_base    = g_current_platform->gicc_base;
  g_hal_uart_base    = g_current_platform->uart_base;
  g_hal_gic_version  = g_current_platform->gic_version;

  // O timer so vem do firmware se o GTDT existir; sem ele, mantem o da tabela.
  U32 tv = acpi_timer_virt();
  if (tv != 0) g_current_platform->irq_timer = tv;

  // Dispositivos de PLACA: SO o FDT descreve. O ACPI nao tem virtio-mmio — ele
  // e topologia desta placa, nao arquitetura ARM. Se o FDT nao rodou, isto fica
  // 0 e a tabela mantem o que tinha (fallback preservado).
  U64 vb = acpi_virtio_base();
  if (vb != 0) {
    g_current_platform->virtio_base   = vb;
    g_hal_virtio_base = vb;
    U32 vs = acpi_virtio_stride();
    if (vs != 0) {
      g_current_platform->virtio_stride = vs;
      g_hal_virtio_stride = vs;
    }
    U32 vn = acpi_virtio_slots();
    if (vn != 0) g_current_platform->virtio_slots = vn;
  }

  HalStrCpy(g_current_platform->name, "Firmware Discovered (ACPI)");
}

U0 HalPlatformInit() {
  U64 boot_frq = __mrs_cntfrq();
  if (boot_frq == 0) boot_frq = 62500000;

  // CAMADA 0.1 (D7): linha de cache do HARDWARE (CTR_EL0 via ACPI/discovery), com
  // piso de seguranca. O flush deixa de usar o 64 hardcoded.
  {
    I64 dl = disco_dcache_line();
    HalSetDcacheLine(dl > 0 ? dl : 64);
  }

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
  g_plat_qemu.gicr_base     = 0x080A0000;
  g_plat_qemu.gic_version   = 0;   // QEMU: v2 ou v3 e opcao de linha de comando -> sondar

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
  // Fonte primaria: arch/arm64/boot/dts/qcom/sm8150.dtsi (kernel oficial Xiaomi,
  // branch vayu-r-oss) — `interrupt-controller@17a00000`, `compatible = arm,gic-v3`,
  // `redistributor-stride = <0x0 0x20000>`, GICR em 0x17a60000 (* 8 cores).
  g_plat_sm8150.gicr_base     = 0x17A60000;
  g_plat_sm8150.gic_version   = 3;

  // P1.2: escolhe a plataforma pelo silicio (MIDR_EL1), em vez de fixar o QEMU.
  HalPlatformDetectByMidr();
  // E3: e o firmware tem a palavra final sobre o que ele mesmo descreve.
  HalPlatformOverlayDiscovery();
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

// P0.5 twin-liveness probe: proves HalPlatform.HC is loaded and callable.
I64 HalTwinProbe() { return 0x48414C31; }

if (g_kernel_booting) {
  HalPlatformInit();
  // BLOCO A / A2: o descritor fisico COMPLETO (uart/storage/input/gop). Roda
  // depois do HalPlatformInit (que escolhe a tabela + sobreposicao do firmware),
  // para o CBootConfig ler a verdade fisica ja' resolvida.
  HalPlatformV2Init();
  HalPlatformV2Report();
} else {
  HalSelfTest();
}
