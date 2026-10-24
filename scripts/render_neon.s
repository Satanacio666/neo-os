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

// I64 RenderNeonBlendRect(U32 *dst, I64 n, U32 color, U32 a)
//   x0=dst, x1=n, w2=color (0xAARRGGBB), w3=a (1..254); returns n.
//   128-bit NEON SRC_ALPHA / ONE_MINUS_SRC_ALPHA. Per byte/channel (little-endian
//   byte order B,G,R,A):
//     out = (color_byte*a + 128 + dst_byte*inv_a) >> 8, alpha forced to 0xFF,
//   with inv_a = 255 - a. Byte-identical to the scalar loop in Render.HC gfx_blend_rect:
//     src_c = color_c*a + 128;  out_c = (src_c + dst_c*inv_a) >> 8.
//   The intermediate fits U16 because color_byte,dst_byte <= 255 and a+inv_a = 255, so
//   color_byte*a + dst_byte*inv_a <= 255*255 = 65025; +128 = 65153 < 65536.
//   Four pixels (16 channels) per iteration; scalar 1-pixel tail.
    .global RenderNeonBlendRect
    .type RenderNeonBlendRect, %function
RenderNeonBlendRect:
    mov     x6, x1                      // result = n
    cbz     x1, .Lblend_done
    mov     w4, #255
    sub     w4, w4, w3                  // w4 = inv_a = 255 - a
    dup     v1.4s, w2                   // v1.16b = [B,G,R,A] x4
    dup     v2.16b, w3                  // v2 = a in every byte
    dup     v3.16b, w4                  // v3 = inv_a in every byte
    movi    v5.8h, #128                 // rounding term
    lsr     x5, x1, #2                  // x5 = number of whole 4-pixel quads
    cbz     x5, .Lblend_tail
.Lblend_vec:
    ldr     q0, [x0]                    // 4 dst pixels
    umull   v4.8h, v1.8b, v2.8b         // src_ch*a          (pixels 0,1)
    umull2  v6.8h, v1.16b, v2.16b       // src_ch*a          (pixels 2,3)
    add     v4.8h, v4.8h, v5.8h         // +128
    add     v6.8h, v6.8h, v5.8h
    umlal   v4.8h, v0.8b, v3.8b         // + dst_ch*inv_a    (pixels 0,1)
    umlal2  v6.8h, v0.16b, v3.16b       // + dst_ch*inv_a    (pixels 2,3)
    shrn    v0.8b, v4.8h, #8            // >>8, narrow       (pixels 0,1)
    shrn2   v0.16b, v6.8h, #8           // >>8, narrow       (pixels 2,3)
    orr     v0.4s, #0xFF, lsl #24       // force alpha = 0xFF
    str     q0, [x0], #16
    subs    x5, x5, #1                  // subs — MUST set Z for the b.ne below
    b.ne    .Lblend_vec
.Lblend_tail:
    and     x1, x1, #3                  // remaining 0..3 pixels
    cbz     x1, .Lblend_done
.Lblend_tail_loop:
    ldr     s0, [x0]                    // 1 dst pixel (zero-extends into v0)
    umull   v4.8h, v1.8b, v2.8b         // src_ch*a
    add     v4.8h, v4.8h, v5.8h         // +128
    umlal   v4.8h, v0.8b, v3.8b         // + dst_ch*inv_a
    shrn    v0.8b, v4.8h, #8            // >>8, narrow
    orr     v0.2s, #0xFF, lsl #24       // force alpha = 0xFF
    str     s0, [x0], #4
    subs    x1, x1, #1
    b.ne    .Lblend_tail_loop
.Lblend_done:
    mov     x0, x6
    .size RenderNeonBlendRect, .-RenderNeonBlendRect
