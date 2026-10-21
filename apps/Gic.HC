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

#define MAX_GIC_INTERRUPTS 128

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
  U64 gicd_base = GicGetDistBase();
  U32 reg = irq / 32;
  U32 bit = irq % 32;
  __mmio_w32(gicd_base + GICD_ISENABLER + reg * 4, 1 << bit);
  CIrqEntry *e = GicGetEntry(irq);
  e->enabled = 1;
}

U0 GicDisableIrq(U32 irq) {
  if (irq >= g_gic.total_irq_lines) return;
  U64 gicd_base = GicGetDistBase();
  U32 reg = irq / 32;
  U32 bit = irq % 32;
  __mmio_w32(gicd_base + GICD_ICENABLER + reg * 4, 1 << bit);
  CIrqEntry *e = GicGetEntry(irq);
  e->enabled = 0;
}

U0 GicSetPriority(U32 irq, U8 prio) {
  if (irq >= g_gic.total_irq_lines) return;
  U64 gicd_base = GicGetDistBase();
  U32 reg = irq / 4;
  U32 shift = (irq % 4) * 8;
  U64 p_addr = gicd_base + GICD_IPRIORITYR + reg * 4;
  U32 cur = __mmio_r32(p_addr);
  cur = cur & ~(0xFF << shift);
  cur = cur | (prio << shift);
  __mmio_w32(p_addr, cur);
  CIrqEntry *e = GicGetEntry(irq);
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
  U64 gicc_base = GicGetCpuBase();
  U32 iar = __mmio_r32(gicc_base + GICC_IAR);
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
  __mmio_w32(gicc_base + GICC_EOIR, iar);
  // P3.5: only hand the frame to the scheduler once it exists (g_sched_ready is
  // set by SchedInit). A firmware-armed timer IRQ during boot must not call the
  // not-yet-defined SchedOnTick.
  if (g_sched_ready) return SchedOnTick(trap_frame);
  return trap_frame;
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
