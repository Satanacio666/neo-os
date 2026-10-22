// ==============================================================================
// scripts/shader_quad.s - SOURCE for the hand-encoded NEON 4-lane op core in
// apps/ShaderVM.HC (ShaderOp4). This file is NOT built by the Makefile; it
// exists so the raw instruction words embedded in ShaderVM.HC can be
// regenerated/audited. To regenerate:
//
//   aarch64-linux-gnu-as -o /tmp/squad.o scripts/shader_quad.s
//   aarch64-linux-gnu-objdump -d /tmp/squad.o | \
//     awk '/^[ ]*[0-9a-f]+:/{print "0x"$2}' | tr a-f A-F
//
// Contract (P4.6 fragment-shader VM):
//   void ShaderOp4(F64 *dst, const F64 *a, const F64 *b, I64 op)
//   X0 = dst, X1 = a, X2 = b, X3 = op. Each pointer addresses FOUR doubles
//   (a 2x2 fragment quad, SoA lane order: (x,y) (x+1,y) (x,y+1) (x+1,y+1)).
//   The op is applied to all four lanes at once with 128-bit NEON (2x .2d).
//   The compiler emits the prologue/epilogue, so this block MUST NOT `ret`.
//
// Op map (must match the SV_* #defines in ShaderVM.HC):
//   0 ADD  1 SUB  2 MUL  3 DIV  4 MIN  5 MAX  6 SQRT  7 RSQ
//   8 ABS  9 NEG  10 FLOOR  11 FRACT  12 MOV   (anything else -> MOV)
// ==============================================================================
.text
.global ShaderOp4

ShaderOp4:
    ldr  q0, [x1]          // a[0..1]
    ldr  q1, [x1, #16]     // a[2..3]
    ldr  q2, [x2]          // b[0..1]
    ldr  q3, [x2, #16]     // b[2..3]

    cmp  x3, #0
    b.eq .Lop_add
    cmp  x3, #1
    b.eq .Lop_sub
    cmp  x3, #2
    b.eq .Lop_mul
    cmp  x3, #3
    b.eq .Lop_div
    cmp  x3, #4
    b.eq .Lop_min
    cmp  x3, #5
    b.eq .Lop_max
    cmp  x3, #6
    b.eq .Lop_sqrt
    cmp  x3, #7
    b.eq .Lop_rsq
    cmp  x3, #8
    b.eq .Lop_abs
    cmp  x3, #9
    b.eq .Lop_neg
    cmp  x3, #10
    b.eq .Lop_floor
    cmp  x3, #11
    b.eq .Lop_fract
    b    .Lop_store          // MOV (12) and any unknown op: dst = a

.Lop_add:
    fadd v0.2d, v0.2d, v2.2d
    fadd v1.2d, v1.2d, v3.2d
    b    .Lop_store
.Lop_sub:
    fsub v0.2d, v0.2d, v2.2d
    fsub v1.2d, v1.2d, v3.2d
    b    .Lop_store
.Lop_mul:
    fmul v0.2d, v0.2d, v2.2d
    fmul v1.2d, v1.2d, v3.2d
    b    .Lop_store
.Lop_div:
    fdiv v0.2d, v0.2d, v2.2d
    fdiv v1.2d, v1.2d, v3.2d
    b    .Lop_store
.Lop_min:
    fmin v0.2d, v0.2d, v2.2d
    fmin v1.2d, v1.2d, v3.2d
    b    .Lop_store
.Lop_max:
    fmax v0.2d, v0.2d, v2.2d
    fmax v1.2d, v1.2d, v3.2d
    b    .Lop_store
.Lop_sqrt:
    fsqrt v0.2d, v0.2d
    fsqrt v1.2d, v1.2d
    b     .Lop_store
.Lop_rsq:
    frsqrte v4.2d, v0.2d
    frsqrte v5.2d, v1.2d
    fmul    v6.2d, v4.2d, v4.2d
    fmul    v7.2d, v5.2d, v5.2d
    frsqrts v6.2d, v0.2d, v6.2d
    frsqrts v7.2d, v1.2d, v7.2d
    fmul    v0.2d, v4.2d, v6.2d
    fmul    v1.2d, v5.2d, v7.2d
    b       .Lop_store
.Lop_abs:
    fabs v0.2d, v0.2d
    fabs v1.2d, v1.2d
    b    .Lop_store
.Lop_neg:
    fneg v0.2d, v0.2d
    fneg v1.2d, v1.2d
    b    .Lop_store
.Lop_floor:
    frintm v0.2d, v0.2d
    frintm v1.2d, v1.2d
    b      .Lop_store
.Lop_fract:
    frintm v4.2d, v0.2d
    frintm v5.2d, v1.2d
    fsub   v0.2d, v0.2d, v4.2d
    fsub   v1.2d, v1.2d, v5.2d
    b      .Lop_store

.Lop_store:
    str  q0, [x0]
    str  q1, [x0, #16]
