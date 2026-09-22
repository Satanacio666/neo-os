.global cpu_switch_context
.type cpu_switch_context, %function

// void cpu_switch_context(cpu_context_t *prev, cpu_context_t *next);
// x0 = pointer to outgoing task context
// x1 = pointer to incoming task context
cpu_switch_context:
    // 1. Save outgoing general callee-saved registers
    stp x19, x20, [x0, #0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x2, sp
    str x2,       [x0, #96]

    // 2. Save outgoing NEON callee-saved registers (D8-D15)
    stp d8,  d9,  [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]

    // 3. Restore incoming general callee-saved registers
    ldp x19, x20, [x1, #0]
    ldp x21, x22, [x1, #16]
    ldp x23, x24, [x1, #32]
    ldp x25, x26, [x1, #48]
    ldp x27, x28, [x1, #64]
    ldp x29, x30, [x1, #80]
    ldr x2,       [x1, #96]
    mov sp, x2

    // 4. Restore incoming NEON registers
    ldp d8,  d9,  [x1, #104]
    ldp d10, d11, [x1, #120]
    ldp d12, d13, [x1, #136]
    ldp d14, d15, [x1, #152]

    // 5. Jump directly into incoming task's PC (stored in x30/LR)
    ret
