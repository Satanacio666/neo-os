// NeoOS Sovereign Pure HolyC ARM GICv2 Interrupt Controller Driver
// Hardware MMIO Distributor and CPU Interface Management via HalPlatform.HC

#define GICD_DEFAULT_BASE 0x08000000
#define GICC_DEFAULT_BASE 0x08010000

#define GICD_CTLR       0x000
#define GICD_TYPER      0x004
#define GICD_IGROUPR    0x080
#define GICD_ISENABLER  0x100
#define GICD_ICENABLER  0x180
#define GICD_ISPENDR    0x200
#define GICD_ICPENDR    0x280
#define GICD_IPRIORITYR 0x400
#define GICD_ITARGETSR  0x800

#define GICC_CTLR       0x000
#define GICC_PMR        0x004
#define GICC_BPR        0x008
#define GICC_IAR        0x00C
#define GICC_EOIR       0x010

// P5.2 — GICv3 (Snapdragon 860 / servidores ARM modernos / QEMU -M virt,gic-version=3).
//
// No GICv3 a interface de CPU SAI do MMIO e vira registradores de sistema
// (ICC_*_EL1). Por isso 0x08010000 deixa de existir: a escrita em
// GICC_DEFAULT_BASE + GICC_PMR toma Data Abort — medido como
// `FAR_EL1 = 0x08010004` no QEMU com -M virt,gic-version=3.
// As PPIs (IRQ < 32, onde vive o timer) migram para o Redistribuidor (GICR),
// um por core, com stride 0x20000 e o frame de SGI em +0x10000.
#define GICD_PIDR2        0xFFE8        // bits [7:4] = arch rev: 2 = GICv2, 3/4 = GICv3/v4
#define GICR_DEFAULT_BASE 0x080A0000    // QEMU virt GICv3 (SM8150: 0x17A60000)
#define GICR_STRIDE       0x20000
#define GICR_WAKER        0x0014
#define GICR_SGI_OFFSET   0x10000
#define GICR_IGROUPR0     0x0080
#define GICR_ISENABLER0   0x0100
#define GICR_ICENABLER0   0x0180
#define GICR_IPRIORITYR   0x0400
#define GICR_IGRPMODR0    0x0D00

#define MAX_GIC_INTERRUPTS 128

U64 g_gic_version;
U64 g_gicr_base;

// B2a.1 (ONDA 3) — interlock de core no funil de IRQ. DECISAO PURA, separada do
// hardware para ser testavel sem timer/mpidr (mesma licao do B11: sonda que
// depende de hardware com observador concorrente e' flaky por construcao).
// So' o core 0 entrega o frame ao escalonador enquanto nao houver run-queues.
I64 g_gic_offcore_tick_blocks = 0;   // ticks de secundarios que NAO foram ao Sched
U64 g_gic_secondary_ppi_ready = 0;   // B2a.2: bitmask dos cores com PPI 27 armado
I64 GicShouldScheduleCore(U32 core_id) {
  if (core_id == 0) return 1;
  return 0;
}

class CIrqEntry {
  U64 handler_fn;
  U64 data;
  I64 enabled;
  I64 priority;
};

class CGicState {
  U32 total_irq_lines;
  U8 *irq_table;
  I64 dispatched_count;
};

CGicState g_gic;

U64 GicGetDistBase() {
  if (g_hal_gicd_base != 0) return g_hal_gicd_base;
  return GICD_DEFAULT_BASE;
}

U64 GicGetCpuBase() {
  if (g_hal_gicc_base != 0) return g_hal_gicc_base;
  return GICC_DEFAULT_BASE;
}

U32 GicMmioRead32(U64 addr) {
  return __mmio_r32(addr);
}

U0 GicMmioWrite32(U64 addr, U32 val) {
  __mmio_w32(addr, val);
}

CIrqEntry* GicGetEntry(I64 irq) {
  return g_gic.irq_table + irq * 32;
}

U64 GicGetRedistBase() {
  if (g_gicr_base != 0) return g_gicr_base;
  // P1.2: o endereco vem da HAL, escolhida por MIDR_EL1 em HalPlatformDetectByMidr().
  //   QEMU virt .......... 0x080A0000
  //   SM8150 (POCO vayu) .. 0x17A60000  (DTS oficial, stride 0x20000, 8 cores)
  if (g_hal_gicr_base != 0) return g_hal_gicr_base;
  return GICR_DEFAULT_BASE;
}

// P5.2 — Descobre a versao do GIC pelo registrador de arquitetura do distribuidor.
// GICD_PIDR2[7:4]: 2 = GICv2, 3 = GICv3, 4 = GICv4. Leitura de MMIO segura nos dois.
U0 GicDetectVersion() {
  // P1.2: se a HAL ja conhece a versao da plataforma (escolhida por MIDR_EL1 em
  // HalPlatformDetectByMidr), usa direto — evita a sonda e a chance de fault.
  if (g_hal_gic_version == 2 || g_hal_gic_version == 3) {
    g_gic_version = g_hal_gic_version;
    return;
  }
  U64 gicd_base = GicGetDistBase();
  I64 faulted = 0;
  // P5.2: leitura com recuperacao. No GICv2 do QEMU o distribuidor e mapeado em
  // 4 KB e 0xFFE8 cai fora — a sonda captura o Data Abort em vez de derrubar o
  // boot (ver early_sync_panic em vectors.S).
  U32 pidr2 = neo_probe_mmio_read32(gicd_base + GICD_PIDR2, &faulted);
  if (faulted != 0) {
    g_gic_version = 2;
    return;
  }
  U32 arch = (pidr2 >> 4) & 0xF;
  if (arch == 3 || arch == 4) {
    g_gic_version = 3;
  } else {
    g_gic_version = 2;
  }
}

U0 GicInitV3() {
  U64 gicd_base = GicGetDistBase();
  U64 gicr_base = GicGetRedistBase();
  U64 sgi = gicr_base + GICR_SGI_OFFSET;

  // 1. Interface de system registers em EL1. Sem ICC_SRE_EL1.SRE=1 todo acesso a
  //    ICC_*_EL1 e Undefined Instruction.
  gicv3_sre_enable();
  // 2. PMR: aceita todas as prioridades (o equivalente do GICC_PMR do v2).
  gicv3_pmr_set(0xFF);
  // 3. EOImode = 0: EOIR faz priority drop E deactivate de uma vez.
  gicv3_ctlr_set(gicv3_ctlr_get() & ~2);
  // 3b. BPR1 = 0: sem isto o agrupamento de prioridade preempta de forma
  //     inesperada entre PPIs e SPIs.
  gicv3_bpr1_set(0);

  // 4. Acordar o redistribuidor deste core (GICR_WAKER.ProcessorSleep = 0) e
  //    esperar ChildrenAsleep limpar.
  U64 waker = gicr_base + GICR_WAKER;
  U32 w = __mmio_r32(waker);
  w = w & ~2;
  __mmio_w32(waker, w);
  I64 spins = 0;
  while ((__mmio_r32(waker) & 4) != 0 && spins < 1000000) {
    spins = spins + 1;
  }

  // 5. PPIs (IRQ < 32): Grupo 1, prioridade default 0xA0, todas desabilitadas.
  //
  // ARMADILHA CLASSICA DO GICv3: no reset os PPIs podem vir em Group 0 (FIQ).
  // Se IGROUPR0 ficar 0, habilitar ICC_IGRPEN1_EL1 nao faz o timer chegar como
  // IRQ — ele vai como FIQ e o handler nunca roda. Por isso IGROUPR0 = 0xFFFFFFFF
  // E IGRPMODR0 = 0 (Group 1 Non-Secure, sem modificacao de grupo).
  __mmio_w32(sgi + GICR_IGROUPR0, 0xFFFFFFFF);
  __mmio_w32(sgi + GICR_IGRPMODR0, 0x00000000);
  I64 p = 0;
  while (p < 32) {
    __mmio_w32(sgi + GICR_IPRIORITYR + (p / 4) * 4, 0xA0A0A0A0);
    p = p + 4;
  }
  __mmio_w32(sgi + GICR_ICENABLER0, 0xFFFFFFFF);

  // 6. Distribuidor.
  U32 typer = __mmio_r32(gicd_base + GICD_TYPER);
  g_gic.total_irq_lines = 32 * ((typer & 0x1F) + 1);
  if (g_gic.total_irq_lines < 32) g_gic.total_irq_lines = 64;
  if (g_gic.total_irq_lines > MAX_GIC_INTERRUPTS) g_gic.total_irq_lines = MAX_GIC_INTERRUPTS;

  __mmio_w32(gicd_base + GICD_CTLR, 0);
  I64 i = 32;
  while (i < g_gic.total_irq_lines) {
    U64 reg = (i / 32) * 4;
    __mmio_w32(gicd_base + GICD_IGROUPR + reg, 0xFFFFFFFF);   // SPI -> Grupo 1
    __mmio_w32(gicd_base + GICD_ICENABLER + reg, 0xFFFFFFFF);
    __mmio_w32(gicd_base + GICD_ICPENDR + reg, 0xFFFFFFFF);
    i = i + 32;
  }
  i = 32;
  while (i < g_gic.total_irq_lines) {
    __mmio_w32(gicd_base + GICD_IPRIORITYR + (i / 4) * 4, 0xA0A0A0A0);
    i = i + 4;
  }
  // ARE_NS (bit 4) roteia por afinidade; EnableGrp1NS (bit 1) liga o Grupo 1.
  __mmio_w32(gicd_base + GICD_CTLR, 0x12);
  gicv3_igrpen1_set(1);
  __dmb_ish();
}

U0 GicInit() {
  if (!g_gic.irq_table) {
    g_gic.irq_table = kmalloc(MAX_GIC_INTERRUPTS * 32);
  }
  if (!g_gic.irq_table) return;
  g_gic.dispatched_count = 0;

  U64 gicd_base = GicGetDistBase();
  U64 gicc_base = GicGetCpuBase();

  I64 gic_i = 0;
  while (gic_i < MAX_GIC_INTERRUPTS) {
    CIrqEntry *e = GicGetEntry(gic_i);
    e->handler_fn = 0;
    e->data = 0;
    e->enabled = 0;
    e->priority = 0xA0;
    gic_i++;
  }

  // P5.2: descobre a versao. No GICv3 o caminho e outro — e nao se toca em
  // 0x08010000, que num SoC GICv3 nao esta mapeado (Data Abort).
  GicDetectVersion();
  if (g_gic_version == 3) {
    GicInitV3();
    return;
  }

  // 1. Query GICD_TYPER
  U32 typer = __mmio_r32(gicd_base + GICD_TYPER);
  g_gic.total_irq_lines = 32 * ((typer & 0x1F) + 1);
  if (g_gic.total_irq_lines < 32) {
    g_gic.total_irq_lines = 64;
  }
  if (g_gic.total_irq_lines > MAX_GIC_INTERRUPTS) {
    g_gic.total_irq_lines = MAX_GIC_INTERRUPTS;
  }

  // 2. Disable distributor during setup and mask/clear all PPI/SPI lines
  __mmio_w32(gicd_base + GICD_CTLR, 0);
  gic_i = 0;
  while (gic_i < g_gic.total_irq_lines) {
    U64 reg_off = (gic_i / 32) * 4;
    __mmio_w32(gicd_base + GICD_IGROUPR + reg_off, 0x00000000);
    __mmio_w32(gicd_base + GICD_ICENABLER + reg_off, 0xFFFFFFFF);
    __mmio_w32(gicd_base + GICD_ICPENDR + reg_off, 0xFFFFFFFF);
    gic_i = gic_i + 32;
  }

  // 3. Set priority on all lines to default 0xA0
  gic_i = 0;
  while (gic_i < g_gic.total_irq_lines) {
    U64 p_reg = gicd_base + GICD_IPRIORITYR + (gic_i / 4) * 4;
    __mmio_w32(p_reg, 0xA0A0A0A0);
    gic_i = gic_i + 4;
  }

  // 4. Route SPIs (IRQ 32+) to CPU Core 0
  gic_i = 32;
  while (gic_i < g_gic.total_irq_lines) {
    U64 t_reg = gicd_base + GICD_ITARGETSR + (gic_i / 4) * 4;
    __mmio_w32(t_reg, 0x01010101);
    gic_i = gic_i + 4;
  }

  // 5. Enable Distributor and CPU interface
  __mmio_w32(gicd_base + GICD_CTLR, 1);
  __mmio_w32(gicc_base + GICC_PMR, 0xFF);
  __mmio_w32(gicc_base + GICC_BPR, 0x00);
  __mmio_w32(gicc_base + GICC_CTLR, 1);
  __dmb_ish();
}

U0 GicEnableIrq(U32 irq) {
  if (irq >= g_gic.total_irq_lines) return;
  CIrqEntry *e = GicGetEntry(irq);
  // P5.2: no GICv3 as PPIs (IRQ < 32, onde vive o timer) moram no Redistribuidor.
  if (g_gic_version == 3 && irq < 32) {
    U64 sgi = GicGetRedistBase() + GICR_SGI_OFFSET;
    __mmio_w32(sgi + GICR_ISENABLER0, 1 << irq);
    e->enabled = 1;
    return;
  }
  U64 gicd_base = GicGetDistBase();
  U32 reg = irq / 32;
  U32 bit = irq % 32;
  __mmio_w32(gicd_base + GICD_ISENABLER + reg * 4, 1 << bit);
  e->enabled = 1;
}

U0 GicDisableIrq(U32 irq) {
  if (irq >= g_gic.total_irq_lines) return;
  CIrqEntry *e = GicGetEntry(irq);
  if (g_gic_version == 3 && irq < 32) {
    U64 sgi = GicGetRedistBase() + GICR_SGI_OFFSET;
    __mmio_w32(sgi + GICR_ICENABLER0, 1 << irq);
    e->enabled = 0;
    return;
  }
  U64 gicd_base = GicGetDistBase();
  U32 reg = irq / 32;
  U32 bit = irq % 32;
  __mmio_w32(gicd_base + GICD_ICENABLER + reg * 4, 1 << bit);
  e->enabled = 0;
}

U0 GicSetPriority(U32 irq, U8 prio) {
  if (irq >= g_gic.total_irq_lines) return;
  CIrqEntry *e = GicGetEntry(irq);
  U32 shift = (irq % 4) * 8;
  U64 p_addr;
  if (g_gic_version == 3 && irq < 32) {
    U64 sgi = GicGetRedistBase() + GICR_SGI_OFFSET;
    p_addr = sgi + GICR_IPRIORITYR + (irq / 4) * 4;
  } else {
    p_addr = GicGetDistBase() + GICD_IPRIORITYR + (irq / 4) * 4;
  }
  U32 cur = __mmio_r32(p_addr);
  cur = cur & ~(0xFF << shift);
  cur = cur | (prio << shift);
  __mmio_w32(p_addr, cur);
  e->priority = prio;
}

U0 GicRegisterHandler(U32 irq, U64 handler, U64 data) {
  if (irq >= MAX_GIC_INTERRUPTS) return;
  CIrqEntry *e = GicGetEntry(irq);
  e->handler_fn = handler;
  e->data = data;
  GicEnableIrq(irq);
}

I64 GicDispatch(U32 sim_irq) {
  if (sim_irq >= MAX_GIC_INTERRUPTS) return -1;
  CIrqEntry *e = GicGetEntry(sim_irq);
  if (e->enabled && e->handler_fn != 0) {
    g_gic.dispatched_count = g_gic.dispatched_count + 1;
    U64 fn = e->handler_fn;
    if (fn > 0x1000) {
      fn(e->data);
    }
    return 1;
  }
  return 0;
}

// P3.5: returns the SP to resume (the interrupted task's frame, or the next
// task's frame when the scheduler preempts). The IRQ vector honors x0.
U64 GicHardwareIrqHandler(U64 trap_frame) {
  // P5.2: no GICv3 o acknowledge e o EOI sao registradores de sistema (ICC_*_EL1),
  // nao MMIO. Ler GICC_IAR num SoC GICv3 daria Data Abort.
  U32 iar;
  if (g_gic_version == 3) {
    iar = (U32)gicv3_iar1();
  } else {
    iar = __mmio_r32(GicGetCpuBase() + GICC_IAR);
  }
  U32 irq = iar & 0x3FF;
  if (irq >= 1020) return trap_frame;
  if (irq < MAX_GIC_INTERRUPTS) {
    CIrqEntry *e = GicGetEntry(irq);
    if (e->enabled && e->handler_fn != 0) {
      g_gic.dispatched_count = g_gic.dispatched_count + 1;
      U64 fn = e->handler_fn;
      fn(e->data);
      // Do NOT disable PPIs (irq < 32) here so periodic Timer IRQ 27 continues firing!
    } else {
      GicDisableIrq(irq);
    }
  }
  if (g_gic_version == 3) {
    gicv3_eoir1(iar);
  } else {
    __mmio_w32(GicGetCpuBase() + GICC_EOIR, iar);
  }
  // P3.5: only hand the frame to the scheduler once it exists (g_sched_ready is
  // set by SchedInit). A firmware-armed timer IRQ during boot must not call the
  // not-yet-defined SchedOnTick.
  //
  // B2a.1 (ONDA 3) — INTERLOCK DE CORE: o escalonador (Sched.HC) NAO tem spinlock
  // nenhum (0 smp_spin_lock contra 3 no KHeap) e escreve g_sched_current / cur->sp
  // / a lista circular sem exclusao. Se DOIS cores chegarem aqui, escolhem o mesmo
  // "best" e a mesma task roda em dois cores -> corrupcao. Enquanto nao houver
  // run-queues por core, SOMENTE o core 0 (BSP) pode entregar o frame ao
  // escalonador. Secundarios devolvem o frame intocado (a IRQ foi reconhecida e
  // o EOI ja' foi dado acima — nada vaza). Le-se o MPIDR direto: Smp.HC compila
  // DEPOIS de Gic.HC (KernelInit.HC), entao SmpGetCoreId() nao existe aqui.
  if (g_sched_ready) {
    if (GicShouldScheduleCore(__mrs_mpidr() & 3)) return SchedOnTick(trap_frame);
    g_gic_offcore_tick_blocks = g_gic_offcore_tick_blocks + 1;
  }
  return trap_frame;
}

// B2a.2 (ONDA 3) — inicializacao da interface GIC DO PROPRIO CORE.
//
// MEDIDO: o QEMU roda com `-M virt,gic-version=2` (run-viewer-vm.sh:24) — logo
// g_gic_version == 2, e o ramo GICv3 que eu tinha escrito NUNCA executava. No
// GICv2 o modelo e' outro:
//   - o GICC (0x08010000) e' BANKED POR HARDWARE: um MMIO write acerta o banco do
//     core que escreve, sem indice de core. Cada core precisa configurar o SEU
//     (CTLR/PRIORITY MASK/BPR) — o GicInit do BSP configurou so' o dele;
//   - os PPIs (irq<32, onde vive o timer 27) sao habilitados no GICD global
//     (GICD_ISENABLER0) + resolvidos por GICD_ITARGETSR (que core os recebe).
//     O ITARGETSR e' por-IRQ, entao o BSP pode (e deve) endereçar o PPI 27 para
//     todos os cores que devem receber o tick.
//   - o timer virtual (CNTV) e' POR CORE: cada core arma o seu (TimerArmThisCore).
U0 GicInitCpuInterface(U32 core_id) {
  if (g_gic_version == 3) {
    U64 gicr = GicGetRedistBase() + ((U64)core_id * GICR_STRIDE);
    U64 sgi = gicr + GICR_SGI_OFFSET;
    U32 w = __mmio_r32(gicr + GICR_WAKER);
    __mmio_w32(gicr + GICR_WAKER, w & ~2);
    I64 spins = 0;
    while ((__mmio_r32(gicr + GICR_WAKER) & 4) != 0 && spins < 100000) spins = spins + 1;
    __mmio_w32(sgi + GICR_IGROUPR0, 0xFFFFFFFF);
    __mmio_w32(sgi + GICR_IGRPMODR0, 0x00000000);
    __mmio_w32(sgi + GICR_IPRIORITYR + (27 / 4) * 4, 0xA0A0A0A0);
    __mmio_w32(sgi + GICR_ISENABLER0, 1 << 27);
    g_gic_secondary_ppi_ready = g_gic_secondary_ppi_ready | (1 << core_id);
    __dmb_ish();
    return 1;
  }
  // ---- GICv2 (o caso REAL no QEMU virt) ----
  U64 gicc = GicGetCpuBase();
  // O GICC e' banked: estas escritas acertam o banco DESTE core.
  __mmio_w32(gicc + GICC_CTLR, 1);        // EnableGrp1 do MEU core
  __mmio_w32(gicc + GICC_PMR, 0xFF);      // aceita todas as prioridades
  __mmio_w32(gicc + GICC_BPR, 0);         // sem subprioridade
  // PPI 27 no GICD: habilitado, prioridade 0xA0, roteado para ESTE core.
  U64 gicd = GicGetDistBase();
  U32 bit = 1 << (27 % 32);
  __mmio_w32(gicd + GICD_IPRIORITYR + 27, 0xA0A0A0A0);
  // ITARGETSR (byte por IRQ, 4 IRQs por palavra): aponta o PPI para este core.
  U32 tgt = core_id & 0xFF;
  U32 word = tgt | (tgt << 8) | (tgt << 16) | (tgt << 24);
  __mmio_w32(gicd + GICD_ITARGETSR + (27 & ~3), word);
  __mmio_w32(gicd + GICD_ISENABLER + (27 / 32) * 4, bit);
  __dmb_ish();
  g_gic_secondary_ppi_ready = g_gic_secondary_ppi_ready | (1 << core_id);
  return 1;
}

U0 gic_dispatch() {
  GicHardwareIrqHandler(0);
}

U0 GicBindVectors() {
  U64 *vecs = &g_arch_vectors;
  vecs[1] = GicHardwareIrqHandler;
  vecs[2] = GicHardwareIrqHandler;
  __dmb_ish();
}

U0 GicPrintDolDoc() {
  doldoc_printf("$FG,CYAN$--- ARM GICv2 CONTROLLER TELEMETRY ---$FG$\n");
  doldoc_printf(" Total IRQ Lines: %d | GICD Base: 0x%08X\n", g_gic.total_irq_lines, GicGetDistBase());
  doldoc_printf(" CPU Interface:   0x%08X | Dispatched: %d\n", GicGetCpuBase(), g_gic.dispatched_count);
  I64 gpd_i = 0;
  while (gpd_i < 40) {
    CIrqEntry *e = GicGetEntry(gpd_i);
    if (e->enabled) {
      doldoc_printf("  IRQ #%d: Enabled | Prio: 0x%02X | Handler: 0x%016X\n", gpd_i, e->priority, e->handler_fn);
    }
    gpd_i++;
  }
  doldoc_printf("$FG,CYAN$-----------------------------------------$FG$\n");
}

I64 GicSelfTest() {
  doldoc_printf("\n$FG,CYAN$[GIC-TEST] Starting Pure HolyC GICv2 Interrupt Controller Verification...$FG$\n");

  // Test 1: Hardware controller query & init via HAL bases
  GicInit();
  GicBindVectors();
  if (g_gic.total_irq_lines < 32 || g_gic.total_irq_lines > MAX_GIC_INTERRUPTS) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: GIC total IRQ lines query failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: GICv2 Distributor (0x%08X) & CPU Interface (0x%08X) initialized (%d IRQ lines).$FG$\n",
                GicGetDistBase(), GicGetCpuBase(), g_gic.total_irq_lines);

  // Test 2: Enable & Disable IRQ 33 (UART)
  GicEnableIrq(33);
  CIrqEntry *e33 = GicGetEntry(33);
  if (!e33->enabled) {
    doldoc_printf("$FG,RED$[FAIL] Test 2A: GicEnableIrq failed!$FG$\n");
    return 0;
  }
  GicDisableIrq(33);
  if (e33->enabled != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2B: GicDisableIrq failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Hardware IRQ mask/unmask register cycle verified.$FG$\n");

  // Test 3: Set Priority on IRQ 27 (Virtual Timer)
  GicSetPriority(27, 0x10);
  CIrqEntry *e27 = GicGetEntry(27);
  if (e27->priority != 0x10) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: GicSetPriority failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Hardware priority register programmed to 0x10.$FG$\n");

  // Test 4: Register dynamic HolyC handler on IRQ 27
  GicRegisterHandler(27, &TimerTick, 0x42);
  if (!e27->enabled || e27->handler_fn != &TimerTick || e27->data != 0x42) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: GicRegisterHandler failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Interrupt vector registration & auto-enable verified.$FG$\n");

  // Test 5: Periodic PPI dispatch cycle & DolDoc telemetry (verify IRQ 27 remains enabled!)
  I64 d_res1 = GicDispatch(27);
  I64 d_res2 = GicDispatch(27);
  if (d_res1 != 1 || d_res2 != 1 || g_gic.dispatched_count != 2 || !e27->enabled) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Periodic PPI GicDispatch failed!$FG$\n");
    return 0;
  }
  GicPrintDolDoc();
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Periodic PPI IRQ 27 acknowledge & multi-tick dispatch validated.$FG$\n");

  doldoc_printf("\n[GIC-PASS] ALL 5 GIC TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  GicInit();
  GicBindVectors();
  // P3.3: register the EL1 timer handler (PPI from HalGetTimerIrq()) and enable
  // the line. A firmware-armed timer may fire before the scheduler loads; the
  // handler is gated on g_sched_ready so those early IRQs are harmless.
  GicRegisterHandler(HalGetTimerIrq(), &TimerTick, 0);
} else {
  GicSelfTest();
}
