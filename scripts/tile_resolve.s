// NeoOS tile→target streaming resolve — SOURCE OF TRUTH (P7.3).
//
// Assembled to raw words and embedded in apps/RasterTile.HC as an `asm { ... }`
// block. Regenerate:  aarch64-linux-gnu-as -o /tmp/tile_resolve.o scripts/tile_resolve.s
//                     aarch64-linux-gnu-objdump -d /tmp/tile_resolve.o
//
// Constraints: caller-saved registers only (x0-x15, v0-v7); NO `ret` (the HolyC
// asm{} wrapper supplies prologue/epilogue); the result is left in X0.
    .text

// I64 TileResolveRow(U32 *dst, U32 *src, I64 n)   x0=dst, x1=src, x2=n -> x0=n
//   Non-temporal 16-px (64 B) blocks (ldp q0,q1 / ldp q2,q3 / stnp q0,q1 / stnp
//   q2,q3) + scalar 1-px tail. `stnp` avoids polluting the cache with tile data
//   that will not be read again.
    .global TileResolveRow
    .type TileResolveRow, %function
TileResolveRow:
    mov     x3, x2
    cmp     x2, #16
    b.lt    .Lres_tail
.Lres_vec:
    ldp     q0, q1, [x1], #32
    ldp     q2, q3, [x1], #32
    stnp    q0, q1, [x0]
    stnp    q2, q3, [x0, #32]
    add     x0, x0, #64
    sub     x2, x2, #16
    cmp     x2, #16
    b.ge    .Lres_vec
.Lres_tail:
    cbz     x2, .Lres_done
.Lres_tail_loop:
    ldr     w4, [x1], #4
    str     w4, [x0], #4
    subs    x2, x2, #1
    b.ne    .Lres_tail_loop
.Lres_done:
    mov     x0, x3
    .size TileResolveRow, .-TileResolveRow
