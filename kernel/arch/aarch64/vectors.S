.global vector_table_el1
.global install_vector_table
.global g_arch_vectors

// Macro to save complete CPU state (trap frame)
// Macro to save complete CPU state (trap frame: GPRs + SP + NEON Q0-Q31)
.macro SAVE_ALL
    sub sp, sp, #784
    stp x0,  x1,  [sp, #16 * 0]
    stp x2,  x3,  [sp, #16 * 1]
    stp x4,  x5,  [sp, #16 * 2]
    stp x6,  x7,  [sp, #16 * 3]
    stp x8,  x9,  [sp, #16 * 4]
    stp x10, x11, [sp, #16 * 5]
    stp x12, x13, [sp, #16 * 6]
    stp x14, x15, [sp, #16 * 7]
    stp x16, x17, [sp, #16 * 8]
    stp x18, x19, [sp, #16 * 9]
    stp x20, x21, [sp, #16 * 10]
    stp x22, x23, [sp, #16 * 11]
    stp x24, x25, [sp, #16 * 12]
    stp x26, x27, [sp, #16 * 13]
    stp x28, x29, [sp, #16 * 14]

    mrs x21, elr_el1
    mrs x22, spsr_el1
    mrs x23, sp_el0
    stp x30, x21, [sp, #16 * 15]
    stp x22, x23, [sp, #16 * 16]

    // Save NEON / Floating Point registers Q0-Q31
    stp q0,  q1,  [sp, #272 + 32 * 0]
    stp q2,  q3,  [sp, #272 + 32 * 1]
    stp q4,  q5,  [sp, #272 + 32 * 2]
    stp q6,  q7,  [sp, #272 + 32 * 3]
    stp q8,  q9,  [sp, #272 + 32 * 4]
    stp q10, q11, [sp, #272 + 32 * 5]
    stp q12, q13, [sp, #272 + 32 * 6]
    stp q14, q15, [sp, #272 + 32 * 7]
    stp q16, q17, [sp, #272 + 32 * 8]
    stp q18, q19, [sp, #272 + 32 * 9]
    stp q20, q21, [sp, #272 + 32 * 10]
    stp q22, q23, [sp, #272 + 32 * 11]
    stp q24, q25, [sp, #272 + 32 * 12]
    stp q26, q27, [sp, #272 + 32 * 13]
    stp q28, q29, [sp, #272 + 32 * 14]
    stp q30, q31, [sp, #272 + 32 * 15]
.endm

// Macro to restore complete CPU state
.macro RESTORE_ALL
    // Restore NEON / Floating Point registers Q0-Q31
    ldp q0,  q1,  [sp, #272 + 32 * 0]
    ldp q2,  q3,  [sp, #272 + 32 * 1]
    ldp q4,  q5,  [sp, #272 + 32 * 2]
    ldp q6,  q7,  [sp, #272 + 32 * 3]
    ldp q8,  q9,  [sp, #272 + 32 * 4]
    ldp q10, q11, [sp, #272 + 32 * 5]
    ldp q12, q13, [sp, #272 + 32 * 6]
    ldp q14, q15, [sp, #272 + 32 * 7]
    ldp q16, q17, [sp, #272 + 32 * 8]
    ldp q18, q19, [sp, #272 + 32 * 9]
    ldp q20, q21, [sp, #272 + 32 * 10]
    ldp q22, q23, [sp, #272 + 32 * 11]
    ldp q24, q25, [sp, #272 + 32 * 12]
    ldp q26, q27, [sp, #272 + 32 * 13]
    ldp q28, q29, [sp, #272 + 32 * 14]
    ldp q30, q31, [sp, #272 + 32 * 15]

    ldp x30, x21, [sp, #16 * 15]
    ldp x22, x23, [sp, #16 * 16]
    msr elr_el1,  x21
    msr spsr_el1, x22
    msr sp_el0,   x23

    ldp x0,  x1,  [sp, #16 * 0]
    ldp x2,  x3,  [sp, #16 * 1]
    ldp x4,  x5,  [sp, #16 * 2]
    ldp x6,  x7,  [sp, #16 * 3]
    ldp x8,  x9,  [sp, #16 * 4]
    ldp x10, x11, [sp, #16 * 5]
    ldp x12, x13, [sp, #16 * 6]
    ldp x14, x15, [sp, #16 * 7]
    ldp x16, x17, [sp, #16 * 8]
    ldp x18, x19, [sp, #16 * 9]
    ldp x20, x21, [sp, #16 * 10]
    ldp x22, x23, [sp, #16 * 11]
    ldp x24, x25, [sp, #16 * 12]
    ldp x26, x27, [sp, #16 * 13]
    ldp x28, x29, [sp, #16 * 14]
    add sp, sp, #784
.endm

// Official ARM64 Vector Table: strictly aligned to 2048 bytes
.section .text.vectors
.balign 2048
vector_table_el1:

// 1. Current EL with SP0
.balign 128
curr_el_sp0_sync:
    b handle_curr_el_sp0_sync

.balign 128
curr_el_sp0_irq:
    b handle_curr_el_sp0_irq

.balign 128
curr_el_sp0_fiq:
    b handle_unhandled_exception

.balign 128
curr_el_sp0_serror:
    b handle_unhandled_exception

// 2. Current EL with SPx (This is where NeoOS kernel & tasks execute)
.balign 128
curr_el_spx_sync:
    b handle_curr_el_spx_sync

.balign 128
curr_el_spx_irq:
    b handle_curr_el_spx_irq

.balign 128
curr_el_spx_fiq:
    b handle_unhandled_exception

.balign 128
curr_el_spx_serror:
    b handle_unhandled_exception

// 3. Lower EL using AArch64
.balign 128
lower_el_a64_sync:
    b handle_unhandled_exception

.balign 128
lower_el_a64_irq:
    b handle_unhandled_exception

.balign 128
lower_el_a64_fiq:
    b handle_unhandled_exception

.balign 128
lower_el_a64_serror:
    b handle_unhandled_exception

// 4. Lower EL using AArch32
.balign 128
lower_el_a32_sync:
    b handle_unhandled_exception

.balign 128
lower_el_a32_irq:
    b handle_unhandled_exception

.balign 128
lower_el_a32_fiq:
    b handle_unhandled_exception

.balign 128
lower_el_a32_serror:
    b handle_unhandled_exception

// Out-of-line exception and interrupt dispatchers via g_arch_vectors[8]
// g_arch_vectors[0] = el1_sync_handler (ExceptionsHandleSync in Exceptions.HC)
// g_arch_vectors[1] = el1_irq_handler  (GicHardwareIrqHandler in Gic.HC)
// g_arch_vectors[2] = el1_fiq_handler
// g_arch_vectors[3] = el1_serror_handler
// g_arch_vectors[4] = smp_secondary_entry (SmpSecondaryWorker in Smp.HC)
.balign 4
handle_curr_el_sp0_sync:
    SAVE_ALL
    mov  x0, sp
    mrs  x1, esr_el1
    mrs  x2, far_el1
    mov  x3, #0
    adrp x16, g_arch_vectors
    add  x16, x16, :lo12:g_arch_vectors
    ldr  x16, [x16, #0]
    cbnz x16, 2f
    b    early_sync_panic   // P0.8: no Ring-0 handler yet -> report and halt
2:  blr  x16
    cbz  x0, panic_halt     // X0==0 => kernel panic: halt, never eret to the fault
1:  RESTORE_ALL
    eret

.balign 4
handle_curr_el_sp0_irq:
    SAVE_ALL
    mov  x0, sp
    adrp x16, g_arch_vectors
    add  x16, x16, :lo12:g_arch_vectors
    ldr  x16, [x16, #8]
    cbnz x16, 2f
    // P0.8: see handle_curr_el_spx_irq — no Ring-0 handler yet, so mask IRQs in
    // the saved PSTATE instead of storming the GIC.
    // RESTORE_ALL reloads SPSR_EL1 from the trap frame (offset 256), so the live
    // register must NOT be touched: mask IRQs in the saved frame instead.
    ldr  x17, [sp, #256]
    orr  x17, x17, #0x80
    str  x17, [sp, #256]
    b    1f
2:  blr  x16
1:  RESTORE_ALL
    eret

.balign 4
handle_curr_el_spx_sync:
    SAVE_ALL
    mov  x0, sp
    mrs  x1, esr_el1
    mrs  x2, far_el1
    mov  x3, #0
    adrp x16, g_arch_vectors
    add  x16, x16, :lo12:g_arch_vectors
    ldr  x16, [x16, #0]
    cbnz x16, 2f
    b    early_sync_panic   // P0.8: no Ring-0 handler yet -> report and halt
2:  blr  x16
    cbz  x0, panic_halt     // X0==0 => kernel panic: halt, never eret to the fault
1:  RESTORE_ALL
    eret

.balign 4
handle_curr_el_spx_irq:
    SAVE_ALL
    mov  x0, sp
    adrp x16, g_arch_vectors
    add  x16, x16, :lo12:g_arch_vectors
    ldr  x16, [x16, #8]
    cbnz x16, 2f
    // P0.8: IRQ arrived before apps/Gic.HC registered its Ring-0 handler. We
    // cannot acknowledge the GIC yet (its base belongs to HalPlatform.HC), and
    // returning with PSTATE.I==0 would re-enter immediately forever. Mask IRQs
    // in the saved PSTATE so the eret below returns with interrupts disabled;
    // the real handler unmasks when Gic.HC installs it.
    // RESTORE_ALL reloads SPSR_EL1 from the trap frame (offset 256), so the live
    // register must NOT be touched: mask IRQs in the saved frame instead.
    ldr  x17, [sp, #256]
    orr  x17, x17, #0x80
    str  x17, [sp, #256]
    b    1f
2:  blr  x16
    // P3.5: honor the scheduler-chosen SP (preemption).
1:  mov  sp, x0
    RESTORE_ALL
    eret

.balign 4
handle_unhandled_exception:
    SAVE_ALL
    mov  x0, sp
    mrs  x1, esr_el1
    mrs  x2, far_el1
    mov  x3, #0
    adrp x16, g_arch_vectors
    add  x16, x16, :lo12:g_arch_vectors
    ldr  x16, [x16, #24]
    cbnz x16, 2f
    // P0.8: no SError handler registered yet -> report the syndrome instead of a
    // silent `b .` spin (a swallowed exception is an undiagnosable hang).
    b    early_sync_panic
2:  blr  x16
1:  b . // Halt if unhandled

// P0.6: terminal halt for an unrecoverable kernel panic. The synchronous
// handler returns X0==0 to request a halt; we must NEVER eret back to the
// faulting instruction (that re-faults forever and floods the serial log).
.balign 4
panic_halt:
    msr  daifset, #0xf      // mask D/A/I/F
1:  wfe
    b    1b

// P0.8: tier-0 synchronous-fault reporter. Used while g_arch_vectors[0] is still
// NULL, i.e. before apps/Exceptions.HC installs the Ring-0 handler (modules 1..4
// of Stage 1: Compiler.HC, HalPlatform.HC, Timer.HC, Gic.HC). Without this, such a
// fault is taken by the firmware's VBAR_EL1 and reported as an opaque
// "Synchronous Exception at 0x..." with no syndrome at all.
// Calls g_early_panic_hook(esr, elr, far, spsr) — a C reporter in boot/main.c —
// and then halts. It never returns to the faulting instruction.
.balign 4
early_sync_panic:
    msr  daifset, #0xf      // mask D/A/I/F while we report

    // P5.2 — sonda de MMIO com recuperacao.
    // Se g_mmio_probe_active != 0, este fault e ESPERADO: marca o resultado,
    // avanca ELR_EL1 em 4 (pula a instrucao de load que faltou) e devolve o
    // controle, em vez de derrubar o boot. Necessario porque a versao do GIC
    // so pode ser descoberta por GICD_PIDR2 (0xFFE8), que no GICv2 do QEMU fica
    // FORA da regiao mapeada do distribuidor (4 KB) e da Data Abort.
    // x16/x17 sao IP0/IP1 — scratch pela ABI, seguros de clobber.
    adrp x16, g_mmio_probe_active
    add  x16, x16, :lo12:g_mmio_probe_active
    ldr  w17, [x16]
    cbz  w17, 2f
    adrp x16, g_mmio_probe_faulted
    add  x16, x16, :lo12:g_mmio_probe_faulted
    mov  w17, #1
    str  w17, [x16]
    mrs  x16, elr_el1
    add  x16, x16, #4
    msr  elr_el1, x16
    eret                    // retoma logo apos o load; PSTATE volta do SPSR_EL1
2:
    mrs  x0, esr_el1
    mrs  x1, elr_el1
    mrs  x2, far_el1
    mrs  x3, spsr_el1
    adrp x16, g_early_panic_hook
    add  x16, x16, :lo12:g_early_panic_hook
    ldr  x16, [x16]
    cbz  x16, 1f
    blr  x16
1:  b    panic_halt

.section .data
.balign 64
.global g_arch_vectors
g_arch_vectors:
    .quad 0 // [0] el1_sync_handler
    .quad 0 // [1] el1_irq_handler
    .quad 0 // [2] el1_fiq_handler
    .quad 0 // [3] el1_serror_handler
    .quad 0 // [4] smp_secondary_entry
    .quad 0 // [5] reserved
    .quad 0 // [6] reserved
    .quad 0 // [7] reserved

.section .text.vectors
// Function to install VBAR_EL1
.global install_vector_table
.type install_vector_table, %function
install_vector_table:
    adr x0, vector_table_el1
    msr vbar_el1, x0
    isb
    ret

.global enable_interrupts
.type enable_interrupts, %function
enable_interrupts:
    msr daifclr, #2
    isb
    ret

.global disable_interrupts
.type disable_interrupts, %function
disable_interrupts:
    msr daifset, #2
    isb
    ret
