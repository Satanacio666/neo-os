// NeoOS NEON memory kernels — SOURCE OF TRUTH (P7.2).
//
// Assembled to raw words and embedded in apps/Render.HC as `asm { ... }` blocks.
// Regenerate:  aarch64-linux-gnu-as -o /tmp/render_neon.o scripts/render_neon.s
//              aarch64-linux-gnu-objdump -d /tmp/render_neon.o
//
// Constraints: caller-saved registers only (x0-x15, v0-v7); NO `ret` (the HolyC
// asm{} wrapper supplies prologue/epilogue); each function leaves its result in X0.
    .text

// I64 RenderNeonFill(U32 *dst, I64 count, U32 color)   x0,x1,x2 -> x0=count
    .global RenderNeonFill
    .type RenderNeonFill, %function
RenderNeonFill:
    mov     x3, x1
    cmp     x1, #8
    b.lt    .Lfill_tail
    dup     v0.4s, w2
.Lfill_vec:
    stp     q0, q0, [x0], #32
    sub     x1, x1, #8
    cmp     x1, #8
    b.ge    .Lfill_vec
.Lfill_tail:
    cbz     x1, .Lfill_done
.Lfill_loop:
    str     w2, [x0], #4
    subs    x1, x1, #1
    b.ne    .Lfill_loop
.Lfill_done:
    mov     x0, x3
    .size RenderNeonFill, .-RenderNeonFill

// I64 RenderNeonBlit(U32 *dst, U32 *src, I64 bytes)    x0,x1,x2 -> x0=bytes
    .global RenderNeonBlit
    .type RenderNeonBlit, %function
RenderNeonBlit:
    mov     x3, x2
    cmp     x2, #64
    b.lt    .Lblit_tail
.Lblit_vec:
    ldr     q0, [x1]
    ldr     q1, [x1, #16]
    ldr     q2, [x1, #32]
    ldr     q3, [x1, #48]
    add     x1, x1, #64
    str     q0, [x0]
    str     q1, [x0, #16]
    str     q2, [x0, #32]
    str     q3, [x0, #48]
    add     x0, x0, #64
    sub     x2, x2, #64
    cmp     x2, #64
    b.ge    .Lblit_vec
.Lblit_tail:
    cbz     x2, .Lblit_done
.Lblit_loop:
    ldrb    w4, [x1], #1
    strb    w4, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lblit_loop
.Lblit_done:
    mov     x0, x3
    .size RenderNeonBlit, .-RenderNeonBlit

// I64 RenderNeonBlendRect(U32 *dst, I64 n, U32 src_r, U32 src_g, U32 src_b, U32 inv_a)
//   x0=dst, x1=n, x2=src_r, x3=src_g, x4=src_b, x5=inv_a; src_* are the PREMULTIPLIED
//   channels (src_channel*alpha + 128). Per pixel/channel:
//     out_c = (src_c + dst_c * inv_a) >> 8 ; alpha = 0xFF.
//   Byte-identical to the scalar loop in Render.HC gfx_blend_rect. Returns n.
    .global RenderNeonBlendRect
    .type RenderNeonBlendRect, %function
RenderNeonBlendRect:
    mov     x6, x1                  // result = n
    cbz     x1, .Lblend_done
.Lblend_loop:
    ldr     w7, [x0]
    and     w8, w7, #0xFF           // B
    mul     w8, w8, w5
    add     w8, w8, w4
    lsr     w8, w8, #8
    and     w8, w8, #0xFF
    ubfx    w9, w7, #8, #8          // G
    mul     w9, w9, w5
    add     w9, w9, w3
    lsr     w9, w9, #8
    and     w9, w9, #0xFF
    orr     w8, w8, w9, lsl #8
    ubfx    w9, w7, #16, #8         // R
    mul     w9, w9, w5
    add     w9, w9, w2
    lsr     w9, w9, #8
    and     w9, w9, #0xFF
    orr     w8, w8, w9, lsl #16
    orr     w8, w8, #0xFF000000
    str     w8, [x0], #4
    sub     x1, x1, #1
    b.ne    .Lblend_loop
.Lblend_done:
    mov     x0, x6
    .size RenderNeonBlendRect, .-RenderNeonBlendRect
