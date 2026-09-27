.global vector_table_el1
.global install_vector_table
.extern gic_dispatch
.extern arm64_sync_exception

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

// Out-of-line exception and interrupt dispatchers
.balign 4
handle_curr_el_sp0_sync:
    SAVE_ALL
    mov x0, sp // Pass pointer to trap frame in x0
    bl arm64_sync_exception
    RESTORE_ALL
    eret

.balign 4
handle_curr_el_sp0_irq:
    SAVE_ALL
    bl gic_dispatch
    RESTORE_ALL
    eret

.balign 4
handle_curr_el_spx_sync:
    SAVE_ALL
    mov x0, sp // Pass pointer to trap frame in x0
    bl arm64_sync_exception
    RESTORE_ALL
    eret

.balign 4
handle_curr_el_spx_irq:
    SAVE_ALL
    bl gic_dispatch
    RESTORE_ALL
    eret

.balign 4
handle_unhandled_exception:
    SAVE_ALL
    mov x0, sp
    bl arm64_unhandled_abort
    b . // Halt if unhandled

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
