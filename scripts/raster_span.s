// ==============================================================================
// scripts/raster_span.s - SOURCE for the hand-encoded NEON span in
// apps/RasterTile.HC (RasterSpanNEON). This file is NOT built by the Makefile;
// it exists so the raw instruction words embedded in RasterTile.HC can be
// regenerated/audited. To regenerate:
//
//   aarch64-linux-gnu-as -o /tmp/span.o scripts/raster_span.s
//   aarch64-linux-gnu-objdump -d /tmp/span.o | \
//     awk '/^[ ]*[0-9a-f]+:/{print "0x"$2}' | tr a-f A-F
//
// Contract: X0 = &CRasterSpan (see the class in RasterTile.HC), returns the
// drawn pixel count in X0. The compiler emits the prologue/epilogue, so this
// block MUST NOT contain `ret`. All Z arithmetic is exact 64-bit.
//
// P4.3b: the SAME kernel now rasterises the textured span. When CRasterSpan.tex_ptr
// (0x90) is non-zero the coverage/depth mask is produced exactly as for the solid
// path (bit-identical to the golden 2D hash), then a compact 8-lane loop computes
// perspective-correct (u,v) with exact 64-bit integer division, gathers texels
// (scalar LDR: NEON has no gather), and the bilinear filter, vertex-colour
// modulate and alpha blend all run in 128-bit NEON. The solid path is byte-for-byte
// the same computation as before (tex_ptr == 0), so 0xD28836F is preserved.
//
// CRasterSpan layout (bytes):
//   0x00 fb_ptr   0x08 zb_ptr   0x10 x_start  0x18 count
//   0x20 w0       0x28 w1       0x30 w2
//   0x38 dw0      0x40 dw1      0x48 dw2
//   0x50 b0       0x58 b1       0x60 b2
//   0x68 z0       0x70 z1       0x78 z2
//   0x80 area     0x88 color    0x8C depth_test
//   0x90 tex_ptr  0x98 uow0     0xA0 uow1     0xA8 uow2
//   0xB0 vow0     0xB8 vow1     0xC0 vow2
//   0xC8 iw0      0xD0 iw1      0xD8 iw2
//   0xE0 dnumU    0xE8 dnumV    0xF0 dden
//
// CRasterTex layout (bytes): 0x00 data 0x08 w 0x10 h 0x18 wmask 0x20 hmask
//   0x28 wrap_s 0x30 wrap_t 0x38 filter 0x40 blend_en
// ==============================================================================
.text
.global RasterSpanNEON

// Wrap the S coordinate in \r (clobbers \t). REPEAT uses the PoT mask; CLAMP
// clamps into [0,w-1]. WRAP_T does the same for T.
.macro WRAP_S r, t
    ldr  \t, [x26, #0x28]
    tbnz \t, #15, 9f
    ldr  \t, [x26, #0x18]
    and  \r, \r, \t
    b 8f
9:
    cmp  \r, #0
    csel \r, xzr, \r, lt
    ldr  \t, [x26, #0x08]
    sub  \t, \t, #1
    cmp  \r, \t
    csel \r, \t, \r, gt
8:
.endm

.macro WRAP_T r, t
    ldr  \t, [x26, #0x30]
    tbnz \t, #15, 7f
    ldr  \t, [x26, #0x20]
    and  \r, \r, \t
    b 6f
7:
    cmp  \r, #0
    csel \r, xzr, \r, lt
    ldr  \t, [x26, #0x10]
    sub  \t, \t, #1
    cmp  \r, \t
    csel \r, \t, \r, gt
6:
.endm

// X0 = &CRasterSpan  (returns drawn pixel count in X0)
RasterSpanNEON:
    stp   x19, x20, [sp, #-16]!
    stp   x21, x22, [sp, #-16]!
    stp   x23, x24, [sp, #-16]!
    stp   x25, x26, [sp, #-16]!
    stp   x27, x28, [sp, #-16]!
    sub   sp, sp, #128           // scratch: [0..31] texels, [32..] temps
    mov   x9, x0
    ldr   x1, [x9, #0x00]
    ldr   x2, [x9, #0x08]
    ldr   x3, [x9, #0x18]
    ldr   x4, [x9, #0x20]
    ldr   x5, [x9, #0x28]
    ldr   x6, [x9, #0x30]
    ldr   x7, [x9, #0x38]
    ldr   x8, [x9, #0x40]
    ldr   x10,[x9, #0x48]
    ldr   x11,[x9, #0x50]
    ldr   x12,[x9, #0x58]
    ldr   x13,[x9, #0x60]
    ldr   x14,[x9, #0x68]
    ldr   x15,[x9, #0x70]
    ldr   x16,[x9, #0x78]
    ldr   x17,[x9, #0x80]
    ldr   w19,[x9, #0x88]
    ldr   w20,[x9, #0x8C]
    mov   x21, #0
    mov   w25, #65534
    movi  v0.4s, #0
    mov   w22, #1
    ins   v0.s[1], w22
    mov   w22, #2
    ins   v0.s[2], w22
    mov   w22, #3
    ins   v0.s[3], w22
    movi  v1.4s, #4
    mov   w22, #5
    ins   v1.s[1], w22
    mov   w22, #6
    ins   v1.s[2], w22
    mov   w22, #7
    ins   v1.s[3], w22
    dup   v16.4s, w7
    dup   v17.4s, w8
    dup   v18.4s, w10
    dup   v19.4s, w11
    dup   v20.4s, w12
    dup   v21.4s, w13
    mul   v22.4s, v0.4s, v16.4s
    mul   v23.4s, v1.4s, v16.4s
    mul   v24.4s, v0.4s, v17.4s
    mul   v25.4s, v1.4s, v17.4s
    mul   v26.4s, v0.4s, v18.4s
    mul   v27.4s, v1.4s, v18.4s
    dup   v15.4s, w19
    movi  v8.4s, #0xff, lsl #24  // alpha force mask
    dup   v9.4s, w19             // modulate colour (alpha forced to 255)
    orr   v9.16b, v9.16b, v8.16b
span_loop:
    cbz   x3, span_done
    dup   v2.4s, w4
    add   v2.4s, v2.4s, v22.4s
    add   v2.4s, v2.4s, v19.4s
    dup   v3.4s, w5
    add   v3.4s, v3.4s, v24.4s
    add   v3.4s, v3.4s, v20.4s
    dup   v4.4s, w6
    add   v4.4s, v4.4s, v26.4s
    add   v4.4s, v4.4s, v21.4s
    dup   v5.4s, w4
    add   v5.4s, v5.4s, v23.4s
    add   v5.4s, v5.4s, v19.4s
    dup   v6.4s, w5
    add   v6.4s, v6.4s, v25.4s
    add   v6.4s, v6.4s, v20.4s
    dup   v7.4s, w6
    add   v7.4s, v7.4s, v27.4s
    add   v7.4s, v7.4s, v21.4s
    cmge  v2.4s, v2.4s, #0
    cmge  v3.4s, v3.4s, #0
    cmge  v4.4s, v4.4s, #0
    and   v2.16b, v2.16b, v3.16b
    and   v2.16b, v2.16b, v4.16b
    cmge  v5.4s, v5.4s, #0
    cmge  v6.4s, v6.4s, #0
    cmge  v7.4s, v7.4s, #0
    and   v5.16b, v5.16b, v6.16b
    and   v5.16b, v5.16b, v7.16b
    xtn   v2.4h, v2.4s
    xtn   v5.4h, v5.4s
    mov   v2.d[1], v5.d[0]
    mov   x22, x4
    mov   x23, x5
    mov   x24, x6
    .macro ZLANE k
    mul   x0, x22, x14
    madd  x0, x23, x15, x0
    madd  x0, x24, x16, x0
    sdiv  x0, x0, x17
    cmp   x0, xzr
    csel  x0, xzr, x0, lt
    cmp   x0, x25
    csel  x0, x25, x0, gt
    ins   v28.h[\k], w0
    add   x22, x22, x7
    add   x23, x23, x8
    add   x24, x24, x10
    .endm
    ZLANE 0
    ZLANE 1
    ZLANE 2
    ZLANE 3
    ZLANE 4
    ZLANE 5
    ZLANE 6
    ZLANE 7
    ldr   q29, [x2]
    cbz   w20, span_nodepth
    cmhi  v30.8h, v29.8h, v28.8h
    and   v2.16b, v2.16b, v30.16b
span_nodepth:
    mov   v31.16b, v2.16b
    // --- shared Z write + drawn-pixel count ---
    bsl   v2.16b, v28.16b, v29.16b
    str   q2, [x2]
    cnt   v2.16b, v31.16b
    addv  b2, v2.16b
    umov  w0, v2.b[0]
    lsr   w0, w0, #4
    add   x21, x21, x0
    // --- dispatch: textured span or byte-identical solid span ---
    ldr   x26, [x9, #0x90]
    cbnz  x26, span_tex
    zip1  v2.8h, v31.8h, v31.8h
    zip2  v3.8h, v31.8h, v31.8h
    ldr   q10, [x1]
    bsl   v2.16b, v15.16b, v10.16b
    str   q2, [x1]
    ldr   q10, [x1, #16]
    bsl   v3.16b, v15.16b, v10.16b
    str   q3, [x1, #16]
    b     span_advance

// ------------------------------------------------------------------------------
// Textured span (P4.3b). Per active lane: perspective-correct (u,v) via exact
// 64-bit integer division, scalar texel gather, NEON bilinear. Then NEON modulate
// + alpha blend across all 8 pixels, masked store.
// ------------------------------------------------------------------------------
span_tex:
    movi  v0.8h, #1              // 1s (for /255 rounding)
    movi  v1.16b, #1             // 0x01010101 per lane (alpha replicate)
    movi  v6.8h, #127            // blend rounding constant
    ldr   x22, [x9, #0x98]       // uow0
    mul   x22, x4, x22
    ldr   x12, [x9, #0xA0]       // uow1
    madd  x22, x5, x12, x22
    ldr   x12, [x9, #0xA8]       // uow2
    madd  x22, x6, x12, x22      // numU = w0*uow0 + w1*uow1 + w2*uow2
    ldr   x23, [x9, #0xB0]       // vow0
    mul   x23, x4, x23
    ldr   x12, [x9, #0xB8]       // vow1
    madd  x23, x5, x12, x23
    ldr   x12, [x9, #0xC0]       // vow2
    madd  x23, x6, x12, x23      // numV
    ldr   x24, [x9, #0xC8]       // iw0
    mul   x24, x4, x24
    ldr   x12, [x9, #0xD0]       // iw1
    madd  x24, x5, x12, x24
    ldr   x12, [x9, #0xD8]       // iw2
    madd  x24, x6, x12, x24      // den
    ldr   x15, [x9, #0xE0]       // dnumU
    ldr   x25, [x9, #0xE8]       // dnumV
    ldr   x11, [x9, #0xF0]       // dden
    umov  x27, v31.d[0]          // mask lanes 0..3
    umov  x28, v31.d[1]          // mask lanes 4..7
    mov   x17, sp                // texel buffer cursor
    mov   x0, #0                 // lane counter
tex_loop:
    cmp   x0, #4
    b.ne  tex_l0
    mov   x27, x28
tex_l0:
    tst   x27, #0xFFFF
    b.eq  tex_next
    lsl   x19, x22, #16
    sdiv  x19, x19, x24          // u (16.16)
    lsl   x20, x23, #16
    sdiv  x20, x20, x24          // v (16.16)
    ldr   x12, [x26, #0x38]      // filter
    mov   w13, #0x2600           // FILT_NEAREST
    cmp   x12, x13
    b.ne  tex_linear
    // --- nearest: one gather ---
    ldr   x12, [x26, #0x08]      // w
    mul   x13, x19, x12
    asr   x13, x13, #16          // tx
    ldr   x14, [x26, #0x10]      // h
    mul   x16, x20, x14
    asr   x16, x16, #16          // ty
    WRAP_S x13, x12
    WRAP_T x16, x14
    ldr   x12, [x26, #0x08]      // w
    madd  x13, x16, x12, x13
    ldr   x14, [x26, #0x00]      // data
    ldr   w13, [x14, x13, lsl #2]
    str   w13, [x17]
    b     tex_next
tex_linear:
    // --- linear: 4 gathers + NEON bilinear ---
    ldr   x12, [x26, #0x08]      // w
    mul   x14, x19, x12
    sub   x14, x14, #32768       // x_fp = u*w - 0.5
    ldr   x13, [x26, #0x10]      // h
    mul   x16, x20, x13
    sub   x16, x16, #32768       // y_fp = v*h - 0.5
    asr   x19, x14, #16          // x0
    and   x12, x14, #0xFFFF      // fx
    asr   x20, x16, #16          // y0
    and   x13, x16, #0xFFFF      // fy
    str   w12, [sp, #64]         // fx
    str   w13, [sp, #68]         // fy
    WRAP_S x19, x14              // tx0
    str   w19, [sp, #32]
    add   x16, x19, #1
    WRAP_S x16, x14              // tx1
    str   w16, [sp, #36]
    WRAP_T x20, x14              // ty0
    str   w20, [sp, #40]
    add   x16, x20, #1
    WRAP_T x16, x14              // ty1
    str   w16, [sp, #44]
    ldr   x12, [x26, #0x08]      // w
    ldr   x13, [x26, #0x00]      // data
    ldr   w20, [sp, #40]         // ty0
    ldr   w19, [sp, #32]         // tx0
    madd  x14, x20, x12, x19
    ldr   w14, [x13, x14, lsl #2]
    str   w14, [sp, #48]         // c00
    ldr   w19, [sp, #36]         // tx1
    madd  x14, x20, x12, x19
    ldr   w14, [x13, x14, lsl #2]
    str   w14, [sp, #52]         // c10
    ldr   w20, [sp, #44]         // ty1
    ldr   w19, [sp, #32]         // tx0
    madd  x14, x20, x12, x19
    ldr   w14, [x13, x14, lsl #2]
    str   w14, [sp, #56]         // c01
    ldr   w19, [sp, #36]         // tx1
    madd  x14, x20, x12, x19
    ldr   w14, [x13, x14, lsl #2]
    str   w14, [sp, #60]         // c11
    // weights (0..256): w00,w10,w01,w11
    ldr   w12, [sp, #64]         // fx
    ldr   w13, [sp, #68]         // fy
    mov   x14, #65536
    sub   x19, x14, x12          // ifx
    sub   x20, x14, x13          // ify
    mul   x14, x19, x20
    lsr   x14, x14, #24          // w00
    mul   x16, x12, x20
    lsr   x16, x16, #24          // w10
    mul   x19, x19, x13
    lsr   x19, x19, #24          // w01
    mul   x12, x12, x13
    lsr   x12, x12, #24          // w11
    dup   v3.4h, w14
    dup   v7.4h, w16
    ins   v3.d[1], v7.d[0]       // [w00x4, w10x4]
    dup   v4.4h, w19
    dup   v12.4h, w12
    ins   v4.d[1], v12.d[0]      // [w01x4, w11x4]
    ldr   q5, [sp, #48]          // c00,c10,c01,c11
    uxtl  v7.8h, v5.8b
    uxtl2 v12.8h, v5.16b
    umull v13.4s, v7.4h, v3.4h
    umlal v13.4s, v12.4h, v4.4h
    umull2 v14.4s, v7.8h, v3.8h
    umlal2 v14.4s, v12.8h, v4.8h
    add   v13.4s, v13.4s, v14.4s
    shrn  v13.4h, v13.4s, #8
    xtn   v13.8b, v13.8h
    umov  w14, v13.s[0]
    str   w14, [x17]
    b     tex_next
tex_next:
    lsr   x27, x27, #16
    add   x22, x22, x15
    add   x23, x23, x25
    add   x24, x24, x11
    add   x17, x17, #4
    add   x0, x0, #1
    cmp   x0, #8
    b.ne  tex_loop
    // ---- modulate (texel * vertex colour / 255) ----
    ldr   q10, [sp]              // texels 0..3
    ldr   q11, [sp, #16]         // texels 4..7
    umull v3.8h, v10.8b, v9.8b
    umull2 v4.8h, v10.16b, v9.16b
    ushr  v5.8h, v3.8h, #8
    add   v3.8h, v3.8h, v5.8h
    add   v3.8h, v3.8h, v0.8h
    ushr  v3.8h, v3.8h, #8
    ushr  v5.8h, v4.8h, #8
    add   v4.8h, v4.8h, v5.8h
    add   v4.8h, v4.8h, v0.8h
    ushr  v4.8h, v4.8h, #8
    xtn   v10.8b, v3.8h
    xtn   v5.8b, v4.8h
    mov   v10.d[1], v5.d[0]
    umull v3.8h, v11.8b, v9.8b
    umull2 v4.8h, v11.16b, v9.16b
    ushr  v5.8h, v3.8h, #8
    add   v3.8h, v3.8h, v5.8h
    add   v3.8h, v3.8h, v0.8h
    ushr  v3.8h, v3.8h, #8
    ushr  v5.8h, v4.8h, #8
    add   v4.8h, v4.8h, v5.8h
    add   v4.8h, v4.8h, v0.8h
    ushr  v4.8h, v4.8h, #8
    xtn   v11.8b, v3.8h
    xtn   v5.8b, v4.8h
    mov   v11.d[1], v5.d[0]
    // ---- alpha blend (SRC_ALPHA, ONE_MINUS_SRC_ALPHA) ----
    ldr   x12, [x26, #0x40]      // blend_en
    cbz   x12, tex_store
    ldr   q12, [x1]
    ldr   q13, [x1, #16]
    ushr  v14.4s, v10.4s, #24
    mul   v14.4s, v14.4s, v1.4s
    mvn   v5.16b, v14.16b
    umull v3.8h, v10.8b, v14.8b
    umull2 v4.8h, v10.16b, v14.16b
    umull v7.8h, v12.8b, v5.8b
    umull2 v12.8h, v12.16b, v5.16b
    add   v3.8h, v3.8h, v7.8h
    add   v4.8h, v4.8h, v12.8h
    add   v3.8h, v3.8h, v6.8h
    add   v4.8h, v4.8h, v6.8h
    ushr  v5.8h, v3.8h, #8
    add   v3.8h, v3.8h, v5.8h
    add   v3.8h, v3.8h, v0.8h
    ushr  v3.8h, v3.8h, #8
    ushr  v5.8h, v4.8h, #8
    add   v4.8h, v4.8h, v5.8h
    add   v4.8h, v4.8h, v0.8h
    ushr  v4.8h, v4.8h, #8
    xtn   v10.8b, v3.8h
    xtn   v5.8b, v4.8h
    mov   v10.d[1], v5.d[0]
    orr   v10.16b, v10.16b, v8.16b
    ushr  v14.4s, v11.4s, #24
    mul   v14.4s, v14.4s, v1.4s
    mvn   v5.16b, v14.16b
    umull v3.8h, v11.8b, v14.8b
    umull2 v4.8h, v11.16b, v14.16b
    umull v7.8h, v13.8b, v5.8b
    umull2 v13.8h, v13.16b, v5.16b
    add   v3.8h, v3.8h, v7.8h
    add   v4.8h, v4.8h, v13.8h
    add   v3.8h, v3.8h, v6.8h
    add   v4.8h, v4.8h, v6.8h
    ushr  v5.8h, v3.8h, #8
    add   v3.8h, v3.8h, v5.8h
    add   v3.8h, v3.8h, v0.8h
    ushr  v3.8h, v3.8h, #8
    ushr  v5.8h, v4.8h, #8
    add   v4.8h, v4.8h, v5.8h
    add   v4.8h, v4.8h, v0.8h
    ushr  v4.8h, v4.8h, #8
    xtn   v11.8b, v3.8h
    xtn   v5.8b, v4.8h
    mov   v11.d[1], v5.d[0]
    orr   v11.16b, v11.16b, v8.16b
tex_store:
    zip1  v2.8h, v31.8h, v31.8h
    zip2  v3.8h, v31.8h, v31.8h
    ldr   q12, [x1]
    bsl   v2.16b, v10.16b, v12.16b
    str   q2, [x1]
    ldr   q13, [x1, #16]
    bsl   v3.16b, v11.16b, v13.16b
    str   q3, [x1, #16]
    b     span_advance

span_advance:
    add   x1, x1, #32
    add   x2, x2, #16
    add   x4, x4, x7, lsl #3
    add   x5, x5, x8, lsl #3
    add   x6, x6, x10, lsl #3
    sub   x3, x3, #1
    b     span_loop
span_done:
    mov   x0, x21
    add   sp, sp, #128
    ldp   x27, x28, [sp], #16
    ldp   x25, x26, [sp], #16
    ldp   x23, x24, [sp], #16
    ldp   x21, x22, [sp], #16
    ldp   x19, x20, [sp], #16
