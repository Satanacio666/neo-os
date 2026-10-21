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
// ==============================================================================
.text
.global RasterSpanNEON
// X0 = &CRasterSpan  (returns drawn pixel count in X0)
RasterSpanNEON:
    stp   x19, x20, [sp, #-16]!
    stp   x21, x22, [sp, #-16]!
    stp   x23, x24, [sp, #-16]!
    str   x25, [sp, #-16]!
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
    bsl   v2.16b, v28.16b, v29.16b
    str   q2, [x2]
    cnt   v2.16b, v31.16b
    addv  b2, v2.16b
    umov  w0, v2.b[0]
    lsr   w0, w0, #4
    add   x21, x21, x0
    zip1  v2.8h, v31.8h, v31.8h
    zip2  v3.8h, v31.8h, v31.8h
    ldr   q10, [x1]
    bsl   v2.16b, v15.16b, v10.16b
    str   q2, [x1]
    ldr   q10, [x1, #16]
    bsl   v3.16b, v15.16b, v10.16b
    str   q3, [x1, #16]
    add   x1, x1, #32
    add   x2, x2, #16
    add   x4, x4, x7, lsl #3
    add   x5, x5, x8, lsl #3
    add   x6, x6, x10, lsl #3
    sub   x3, x3, #1
    b     span_loop
span_done:
    mov   x0, x21
    ldr   x25, [sp], #16
    ldp   x23, x24, [sp], #16
    ldp   x21, x22, [sp], #16
    ldp   x19, x20, [sp], #16
