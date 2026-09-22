#include "gic.h"

static inline void mmio_write32(uint64_t addr, uint32_t val) {
    *(volatile uint32_t*)addr = val;
    asm volatile("dmb sy" ::: "memory");
}

static inline uint32_t mmio_read32(uint64_t addr) {
    uint32_t val = *(volatile uint32_t*)addr;
    asm volatile("dmb sy" ::: "memory");
    return val;
}

typedef struct {
    irq_handler_t handler;
    void *data;
} irq_entry_t;

static irq_entry_t irq_table[MAX_GIC_INTERRUPTS];
static uint32_t total_irq_lines = 0;

void gic_init(void) {
    // Zero out handler registry
    for (int i = 0; i < MAX_GIC_INTERRUPTS; i++) {
        irq_table[i].handler = NULL;
        irq_table[i].data = NULL;
    }

    // 1. Query number of interrupt lines supported by GIC Distributor
    uint32_t typer = mmio_read32(GICD_TYPER);
    total_irq_lines = 32 * ((typer & 0x1F) + 1);
    if (total_irq_lines > MAX_GIC_INTERRUPTS) {
        total_irq_lines = MAX_GIC_INTERRUPTS;
    }

    // 2. Disable Distributor during initial setup
    mmio_write32(GICD_CTLR, 0);

    // 3. Disable all interrupts and clear pending states
    for (uint32_t i = 0; i < total_irq_lines; i += 32) {
        mmio_write32(GICD_ICENABLER(i / 32), 0xFFFFFFFF);
        mmio_write32(GICD_ICPENDR(i / 32), 0xFFFFFFFF);
        mmio_write32(GICD_IGROUPR(i / 32), 0x00000000); // Group 0 (Secure/EL1)
    }

    // 4. Set priority on all interrupt lines to default (0xA0)
    for (uint32_t i = 0; i < total_irq_lines; i += 4) {
        mmio_write32(GICD_IPRIORITYR(i / 4), 0xA0A0A0A0);
    }

    // 5. Route all Shared Peripheral Interrupts (SPI, IRQ 32+) to CPU Core 0
    for (uint32_t i = 32; i < total_irq_lines; i += 4) {
        mmio_write32(GICD_ITARGETSR(i / 4), 0x01010101); // Target CPU0 (bit 0)
    }

    // 6. Enable Distributor (bit 0 = Group 0 enable)
    mmio_write32(GICD_CTLR, 1);

    // 7. Initialize CPU Interface
    mmio_write32(GICC_PMR, 0xFF); // Priority Mask: Accept all priorities
    mmio_write32(GICC_BPR, 0x00); // Binary Point: No sub-priority grouping
    mmio_write32(GICC_CTLR, 1);   // Enable CPU Interface

    printf("[GICv2] Hardware controller initialized (%u IRQ lines, Base: 0x%08llX)\n",
           total_irq_lines, (unsigned long long)GICD_BASE);
}

void gic_enable_irq(uint32_t irq) {
    if (irq >= total_irq_lines) return;
    uint32_t reg = irq / 32;
    uint32_t bit = irq % 32;
    mmio_write32(GICD_ISENABLER(reg), (1U << bit));
}

void gic_disable_irq(uint32_t irq) {
    if (irq >= total_irq_lines) return;
    uint32_t reg = irq / 32;
    uint32_t bit = irq % 32;
    mmio_write32(GICD_ICENABLER(reg), (1U << bit));
}

void gic_set_priority(uint32_t irq, uint8_t priority) {
    if (irq >= total_irq_lines) return;
    uint32_t reg = irq / 4;
    uint32_t shift = (irq % 4) * 8;
    uint32_t current = mmio_read32(GICD_IPRIORITYR(reg));
    current &= ~(0xFFU << shift);
    current |= ((uint32_t)priority << shift);
    mmio_write32(GICD_IPRIORITYR(reg), current);
}

void gic_register_handler(uint32_t irq, irq_handler_t handler, void *data) {
    if (irq >= MAX_GIC_INTERRUPTS) return;
    irq_table[irq].handler = handler;
    irq_table[irq].data = data;
    gic_enable_irq(irq);
}

void gic_dispatch(void) {
    // Read Interrupt Acknowledge Register
    uint32_t iar = mmio_read32(GICC_IAR);
    uint32_t irq = iar & 0x3FF; // Bits 0-9 contain the IRQ number

    if (irq < 1020) {
        // Valid hardware interrupt
        if (irq_table[irq].handler) {
            irq_table[irq].handler(irq, irq_table[irq].data);
        } else {
            printf("[GIC] Unhandled IRQ #%u fired!\n", irq);
        }

        // Signal End of Interrupt to hardware
        mmio_write32(GICC_EOIR, iar);
    }
}
