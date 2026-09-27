/*
 * kernel/arch/aarch64/ffi_arm64.S
 *
 * Native AArch64 AAPCS FFI Call Dispatcher
 * Allows dynamic function calls with full 64-bit integer (x0..x7)
 * and floating-point (d0..d7 / s0..s7) register marshaling.
 *
 * Signature:
 * uint64_t arm64_ffi_call(
 *     void *fn,                    // x0: Function pointer to invoke
 *     const uint64_t *int_args,    // x1: Array of up to 8 uint64_t integer args
 *     int int_count,               // x2: Number of integer args (0..8)
 *     const double *fp_args,       // x3: Array of up to 8 double-precision float args
 *     int fp_count,                // x4: Number of float args (0..8)
 *     int is_fp32,                 // x5: 1 if function expects/returns 32-bit float, 0 for 64-bit double
 *     double *out_fp               // x6: Optional pointer to store d0 float return value
 * );
 */

.text
.align 4
.global arm64_ffi_call
.type arm64_ffi_call, %function

arm64_ffi_call:
    // Frame setup: save frame pointer, link register, and callee-saved registers
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                 // x19 = fn pointer
    mov     x20, x6                 // x20 = out_fp pointer (or NULL)
    mov     x22, x5                 // x22 = is_fp32 flag

    // 1. Load Floating-Point Arguments into d0..d7
    cbz     x4, .Lload_ints         // if fp_count == 0, skip float loading
    cbz     x3, .Lload_ints         // if fp_args == NULL, skip float loading

    // Load up to 8 doubles into d0..d7
    ldp     d0, d1, [x3, #0]
    ldp     d2, d3, [x3, #16]
    ldp     d4, d5, [x3, #32]
    ldp     d6, d7, [x3, #48]

    // If is_fp32 is set, convert d0..d7 to single-precision in s0..s7
    cbz     x22, .Lload_ints
    fcvt    s0, d0
    fcvt    s1, d1
    fcvt    s2, d2
    fcvt    s3, d3
    fcvt    s4, d4
    fcvt    s5, d5
    fcvt    s6, d6
    fcvt    s7, d7

.Lload_ints:
    // 2. Load Integer Arguments into x0..x7
    cbz     x2, .Lno_ints           // if int_count == 0, clear x0 and call
    cbz     x1, .Lno_ints

    // Load up to 8 64-bit integers into x0..x7 from array in x1
    ldp     x6, x7, [x1, #48]
    ldp     x4, x5, [x1, #32]
    ldp     x2, x3, [x1, #16]
    ldp     x0, x1, [x1, #0]
    b       .Lcall_fn

.Lno_ints:
    mov     x0, #0

.Lcall_fn:
    // 3. Branch with link to the target function
    blr     x19

    // 4. Capture Floating-Point Return Value (d0 or s0) if out_fp pointer was provided
    cbz     x20, .Ldone
    cbz     x22, .Lstore_f64
    // Convert 32-bit single-precision float return in s0 to 64-bit double in d0
    fcvt    d0, s0
.Lstore_f64:
    str     d0, [x20]

.Ldone:
    // x0 already holds the 64-bit integer return value from the called function
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.size arm64_ffi_call, .-arm64_ffi_call
