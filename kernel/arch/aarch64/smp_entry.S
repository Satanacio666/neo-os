.section .bss
.align 16
.global smp_core_stacks
smp_core_stacks:
    .skip 4 * 16384 // 16KB stack for each of the 4 cores

.section .text
.global psci_call_hvc
.global psci_call_smc
.global smp_get_mpidr
.global smp_get_sctlr
.global smp_get_tcr
.global smp_get_mair
.global smp_get_ttbr0
.global smp_get_vbar
.global smp_spin_lock
.global smp_spin_unlock
.global smp_entry

psci_call_hvc:
    // x0: function id
    // x1: target cpu
    // x2: entry point
    // x3: context id
    hvc #0
    ret

psci_call_smc:
    smc #0
    ret

smp_get_mpidr:
    mrs x0, mpidr_el1
    ret

smp_get_sctlr:
    mrs x0, sctlr_el1
    ret

smp_get_tcr:
    mrs x0, tcr_el1
    ret

smp_get_mair:
    mrs x0, mair_el1
    ret

smp_get_ttbr0:
    mrs x0, ttbr0_el1
    ret

smp_get_vbar:
    mrs x0, vbar_el1
    ret

smp_spin_lock:
    mov w2, #1
1:  ldaxr w1, [x0]
    cbnz w1, 2f
    stxr w1, w2, [x0]
    cbnz w1, 1b
    ret
2:  wfe
    b 1b

smp_spin_unlock:
    stlr wzr, [x0]
    sev
    ret

.align 4
smp_entry:
    // When called from PSCI CPU_ON:
    // X0 contains context_id (core_id)
    mov x19, x0

    // Setup per-core stack
    adrp x1, smp_core_stacks
    add x1, x1, :lo12:smp_core_stacks
    mov x2, #16384
    add x3, x19, #1
    mul x2, x2, x3
    add sp, x1, x2

    // Enable FP/SIMD
    mrs x1, cpacr_el1
    orr x1, x1, #(3 << 20)
    msr cpacr_el1, x1
    isb

    // Configure MMU registers from g_mmu_config
    adrp x1, g_mmu_config
    add x1, x1, :lo12:g_mmu_config

    tlbi vmalle1
    dsb ish
    isb

    ldr x2, [x1, #16] // mair
    msr mair_el1, x2

    ldr x2, [x1, #8]  // tcr
    msr tcr_el1, x2

    ldr x2, [x1, #24] // ttbr0
    msr ttbr0_el1, x2

    ldr x2, [x1, #32] // vbar
    msr vbar_el1, x2
    isb

    ic iallu
    dsb ish
    isb

    // Enable MMU
    ldr x2, [x1, #0]  // sctlr
    msr sctlr_el1, x2
    isb

    // Call C secondary worker
    mov x0, x19
    bl smp_secondary_core_worker

1:  wfe
    b 1b
