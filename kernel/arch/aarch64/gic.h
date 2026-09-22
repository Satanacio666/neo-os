#ifndef NEO_GIC_H
#define NEO_GIC_H

#include <uefi.h>

// Base addresses for QEMU 'virt' board (GICv2)
#define GICD_BASE 0x08000000ULL
#define GICC_BASE 0x08010000ULL

// GIC Distributor Register Offsets
#define GICD_CTLR            (GICD_BASE + 0x0000)
#define GICD_TYPER           (GICD_BASE + 0x0004)
#define GICD_IIDR            (GICD_BASE + 0x0008)
#define GICD_IGROUPR(n)      (GICD_BASE + 0x0080 + (4 * (n)))
#define GICD_ISENABLER(n)    (GICD_BASE + 0x0100 + (4 * (n)))
#define GICD_ICENABLER(n)    (GICD_BASE + 0x0180 + (4 * (n)))
#define GICD_ISPENDR(n)      (GICD_BASE + 0x0200 + (4 * (n)))
#define GICD_ICPENDR(n)      (GICD_BASE + 0x0280 + (4 * (n)))
#define GICD_ISACTIVER(n)    (GICD_BASE + 0x0300 + (4 * (n)))
#define GICD_ICACTIVER(n)    (GICD_BASE + 0x0380 + (4 * (n)))
#define GICD_IPRIORITYR(n)   (GICD_BASE + 0x0400 + (4 * (n)))
#define GICD_ITARGETSR(n)    (GICD_BASE + 0x0800 + (4 * (n)))
#define GICD_ICFGR(n)        (GICD_BASE + 0x0C00 + (4 * (n)))
#define GICD_SGIR            (GICD_BASE + 0x0F00)

// GIC CPU Interface Register Offsets
#define GICC_CTLR            (GICC_BASE + 0x0000)
#define GICC_PMR             (GICC_BASE + 0x0004)
#define GICC_BPR             (GICC_BASE + 0x0008)
#define GICC_IAR             (GICC_BASE + 0x000C)
#define GICC_EOIR            (GICC_BASE + 0x0010)
#define GICC_RPR             (GICC_BASE + 0x0014)
#define GICC_HPPIR           (GICC_BASE + 0x0018)
#define GICC_IIDR            (GICC_BASE + 0x00FC)

// Standard IRQ Lines on AArch64 Virt
#define IRQ_VIRT_TIMER       27
#define IRQ_PHYS_TIMER       30
#define IRQ_UART_PL011       33

#define MAX_GIC_INTERRUPTS   1024

typedef void (*irq_handler_t)(uint32_t irq, void *data);

void gic_init(void);
void gic_enable_irq(uint32_t irq);
void gic_disable_irq(uint32_t irq);
void gic_set_priority(uint32_t irq, uint8_t priority);
void gic_register_handler(uint32_t irq, irq_handler_t handler, void *data);
void gic_dispatch(void);

#endif // NEO_GIC_H
