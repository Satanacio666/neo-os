# NeoOS AArch64 / HolyC Ring-0 SASOS — Code-Level Engineering Brief

**Target:** the `neo-os` tree (`apps/RasterTile.HC`, `apps/HolyGL.HC`, `apps/Math3D.HC`,
`apps/Sched.HC`, `apps/Smp.HC`, `apps/Compiler.HC`, `boot/seed/*`, `kernel/arch/aarch64/*`).
**Audience:** implementers of the P4.x rendering, P3.x scheduler/SMP and P2.x seed-FS phases.
**Constraint:** all code is EL1 ring-0, single 64-bit address space (SASOS), no MMU protection
between "kernel" and "apps", no libc/libatomic, no Linux.

Every topic below gives: (a) algorithm/pseudocode, (b) exact ARM64/NEON instruction
sequences or C-style reference, (c) known pitfalls, (d) how to structure it for a
single-address-space ring-0 OS. Line references (`file:line`) point at the current tree.

---

## 0. Cross-cutting conventions used throughout

**Fixed point.** The existing rasterizer is integer-only: `RasterTile.HC:86-88` computes
Juan Pineda edge functions in exact `I64`, and `RasterTile.HC:162` does
`pz = (w0*az + w1*bz + w2*cz) / area`. We extend the *same* exact-edge pipeline to
attributes; do **not** introduce `F64` into the inner loop (the JIT has no FP register
allocator worth the name, and the trap frame already saves all 32 Q registers —
`Sched.HC:52`).

Notation: `X.Y` fixed point = `X` integer bits, `Y` fractional bits, stored in a
signed `I64`/`I32`. `>>` on a negative `I64` is an **arithmetic** shift on AArch64
(`ASR`), i.e. floor division by the power of two — this is load-bearing for texture
wrapping (§1.5).

**Barriers.** AArch64 is weakly ordered. Use the Linux-kernel mapping
(`smp_mb = DMB ISH`, `smp_rmb = DMB ISHLD`, `smp_wmb = DMB ISHST`,
`smp_store_release = STLR`, `smp_load_acquire = LDAR`). The current SMP mailbox
(`Smp.HC:57-85`) already uses `__dmb_ish()` around the `pending` flag; the lock-free
queue in §3 tightens this to `STLR`/`LDAR`.

**Cache maintenance for DMA/device-visible memory** (framebuffer, virtio rings):
`DC CVAC` (clean+invalidate by VA to PoC) then `DSB SY` before signalling the device;
`DC IVAC` before the CPU re-reads device-written memory.

---

# 1. Perspective-correct texture mapping in a software rasterizer

## 1.1 What the current code already gives us

`RasterTile.HC` rasterizes one screen-space triangle with per-vertex Z:

- `area = PinedaEdge(A,B,C)` (`RasterTile.HC:230`), made positive by swapping B/C.
- For a pixel `P`, `w0,w1,w2` are the three un-normalized edge functions
  (`RasterTile.HC:158-160`); a pixel is inside iff `w0+b0 ≥ 0 && w1+b1 ≥ 0 && w2+b2 ≥ 0`
  with top-left biases `b_i ∈ {-1,0}` (`RasterTile.HC:259-261`).
- Barycentric coordinates are `λ_i = w_i / area`. Depth is interpolated **linearly in
  screen space** because NDC `z` *is* an affine function of screen `x,y`:
  `z = (w0*z0 + w1*z1 + w2*z2)/area`.

The NEON body (`RasterSpanNEON`, `RasterTile.HC:124`, source `scripts/raster_span.s`)
does exactly the same with 8 pixels/iteration: it steps the three edge values by
`dw0 = Cy-By`, `dw1 = Ay-Cy`, `dw2 = By-Ay` (`RasterTile.HC:194-196`), then runs the
depth numerator in **exact 64-bit scalar** (`scripts/raster_span.s:107-128`, the
`ZLANE` macro: `mul/madd/madd/sdiv`, clamp, `ins v28.h[k]`), while the coverage test
and depth compare/store are 4-lane SIMD.

Texture coordinates are the *only* missing attribute: `GLVertex` already carries `u,v`
(`HolyGL.HC:28-29`) but `HolyGLSubmitTriangle` (`HolyGL.HC:258-311`) ignores them and
passes only a flat color.

## 1.2 Perspective-correct attribute interpolation (math)

A vertex attribute `A` (color, `u`, `v`, normal) defined in object/camera space must be
interpolated **hyperbolically**, not affinely in screen space. With screen-space
barycentrics `λ_i`:

```
A_screen(P) = Σ λ_i · A_i                      // WRONG for attributes
A_persp(P)  = Σ λ_i · (A_i / W_i)  /  Σ λ_i · (1 / W_i)   // CORRECT
```

Equivalently: interpolate `A/W` and `1/W` linearly, then divide per pixel. Depth is the
special case `A = z` (because `z_ndc = z/W`), which is why the existing Z path needs no
division by the interpolated `1/W`.

Substituting `λ_i = w_i/area`, **the `area` cancels**:

```
u = ( w0·(u0/W0) + w1·(u1/W1) + w2·(u2/W2) )
    -------------------------------------------------
    ( w0·(1/W0)  + w1·(1/W1)  + w2·(1/W2)  )
```

So with the *un-normalized* exact edge functions we can get `u` (and `v`) with **no
per-pixel `area` division at all** — only one division of the two 64-bit accumulators.
This mirrors `RasterTile.HC:162` exactly.

`1/W` at a vertex is just `invW_i = 1.0/W_i`, computed once in `HolyGLSubmitTriangle`
where `inv_w0..2` already exist (`HolyGL.HC:262-264`).

### Pseudocode (per triangle, done once, in `HolyGL`/`RasterSet*`)

```
// vertex prep (float, once per vertex)
invW[i] = 1 / W[i]
UoW[i]  = u[i] * invW[i]        // u/W
VoW[i]  = v[i] * invW[i]        // v/W

// fixed-point pre-scale (16.16 for u,v; use 8.24 or 4.28 if you need more range)
I0 = round(invW0 * 65536)       // I64
U0 = round(UoW0  * 65536)       // I64   (u in [0,1] ⇒ |U0| ≤ 2^16)
// ... same for I1,U1,V1, I2,U2,V2
```

### Pseudocode (per pixel)

```
numU = w0*U0 + w1*U1 + w2*U2        // exact I64
numV = w0*V0 + w1*V1 + w2*V2
den  = w0*I0 + w1*I1 + w2*I2        // exact I64, = area * (1/W_pixel)
if (den == 0) continue              // W→∞ guard (shouldn't happen: near-plane clip)
u_16_16 = (numU << 16) / den        // recover u in 16.16
v_16_16 = (numV << 16) / den
```

`den > 0` always, because `W > 0` is guaranteed by the near-plane reject at
`HolyGL.HC:260` (`w <= 0.05` → discard).

## 1.3 Exact vs fixed-point, and overflow bounds for edge/attribute products

**Recommendation: hybrid.** Keep coverage (`w_i`) exact integer (bit-exact fill, as the
current code does), and keep the attribute accumulators in exact `I64` with 16.16
attributes. This preserves the "1 core == N cores" determinism the project advertises
(`RasterTile.HC:8-9`) and avoids FP non-determinism.

**Bounds.** Let `C` = maximum absolute coordinate in subpixel units, `S` = number of
subpixel bits (screen pixel `p` → `p << S`). The edge function magnitude is bounded by

```
|E| = |(px-ax)(by-ay) - (py-ay)(bx-ax)|  ≤  8·C²          (worst case; 4·C² typical)
```

Each attribute accumulator term is `|w_i| · |A_i|`. With attributes in 16.16,
`|A_i| ≤ 2^16`; with `1/W` in 16.16 and `W ≥ 0.05`, `|I_i| ≤ 1.31e6 < 2^21`. Requiring the
3-term sum to stay below `2^62`:

| `C` (subpixel units) | `|E| ≤ 8C²` | `|E|·2^16` (numU) | `|E|·2^21` (den) |
|---|---|---|---|
| `2^11` (1024 px, S=0)   | 2^25 | 2^41 | 2^46 |
| `2^15` (4096 px, S=4)   | 2^33 | 2^49 | 2^54 |
| `2^19` (4096 px, S=8)   | 2^41 | 2^57 | **2^62 (borderline)** |

So with 8 subpixel bits and a 4096-px screen the **denominator is at the edge of `I64`**.
Two safe options:

1. **Normalize once per triangle** (preferred when `S ≥ 4`): precompute
   `inv_area = round(2^24 / area)` and form `λ_i = (w_i * inv_area) >> 24` as 16.16
   (a single `mul` + `asr` per pixel per edge). Then `λ_i ∈ [0,2^16]` and every product
   is bounded by `2^16 · 2^21 = 2^37`, sum `2^39` — huge headroom. Coverage still uses
   the exact `w_i`.
2. **Cap subpixel bits at 4** and keep the area-free exact form. For a 1024×768 GOP
   framebuffer this is ample.

Pitfall: `(numU << 16)` can overflow if `numU` is near `2^47`. Guard by shifting
*after* checking, or use a 128-bit `SMULH`-based divide (`sdiv` needs a 64-bit
numerator). If `numU`/`den` are large, instead divide first:
`u = (numU / (den >> 16))` with `den >> 16` as the 16.16 denominator — loses a little
precision but never overflows.

Pitfall: **rounding**. `sdiv` truncates toward zero. For a stable, dither-free result
add half a divisor: `u = (numU<<16 + (den>>1)) / den` (with sign handled; all of
`numU,den` share sign because `W>0` and the triangle was re-wound to `area>0`).

## 1.4 Bilinear filtering with 8.8 weights that sum to exactly 256

Given `u` in 16.16 (`u_i = u >> 16` integer texel, `u_f = (u >> 8) & 0xFF` = 8-bit
fraction in `[0,255]`):

```
fu = (u >> 8) & 0xFF            // 0..255
fv = (v >> 8) & 0xFF
iu = u >> 16                    // integer texel (floor; arithmetic shift handles negatives)
iv = v >> 16

// corner weights, each computed as an 8.8 fixed product >> 8
w00 = ((256-fu)*(256-fv)) >> 8
w10 = (     fu *(256-fv)) >> 8
w01 = ((256-fu)*    fv ) >> 8
w11 = 256 - w00 - w10 - w01     // ← force the sum to exactly 256
```

The naive `w11 = (fu*fv)>>8` can make the four floors sum to **255** (one ULP darkening
at every pixel). Compute three and derive the fourth. This is the same class of bug that
makes naive integer bilinear "pump" over a gradient.

Blend per channel (weights sum to 256 ⇒ `>>8` is exact, output stays `0..255`):

```
c = ( t00.c*w00 + t10.c*w10 + t01.c*w01 + t11.c*w11 ) >> 8
```

Pack four channels at once with `SDOT`? No — `SDOT` is 8-bit dot product (FEAT_DotProd,
Armv8.2) and only helps for 4-element dot products of bytes. For RGBA you can instead:

- widen bytes to 16-bit lanes with `USHLL`, multiply by weights with `MUL.8H`, accumulate
  with `ADD`, then `SHRN` back to bytes. That is the portable Armv8.0 path.

### NEON 8.8 bilinear weights (4 pixels at once, byte texture)

```asm
// vA = texel00 RGBA (4 pixels) in .16b, vB=10, vC=01, vD=11
// vW = [w00,w10,w01,w11] broadcast per pixel, 8 lanes of 16-bit
ushll   v0.8h, vA.8b, #0        // widen R,G,B,A... (do per channel or use zip)
// multiply-accumulate across the four corners:
umull   v4.8h, vA.8b, vW0.8b    // low
umlal   v4.8h, vB.8b, vW1.8b
umlal   v4.8h, vC.8b, vW2.8b
umlal   v4.8h, vD.8b, vW3.8b
shrn    v4.8b, v4.8h, #8        // >>8, back to 8-bit
```

(In practice you keep R,G,B,A in separate 8-lane 16-bit accumulators so the `>>8`
rounding is per channel; the layout above is the minimal illustration.)

Pitfall: bilinear on the **edges** must fetch the neighbour texel with the wrap mode
applied (see §1.5) *before* filtering; clamping the *coordinate* once at `[0,size-1]`
produces a hard seam. The standard fix is to compute the four texel indices
`iu,iu+1,iv,iv+1`, wrap each independently, then filter.

## 1.5 Wrap modes

**REPEAT, power-of-two** — the cheap, branchless form, valid for negative coordinates
because `ASR` floors and two's-complement `AND` maps back into range:

```
mask = tex_w - 1                 // tex_w must be a power of two
tx = (u >> 16) & mask            // u = -1 (i.e. -1/65536) ⇒ (-1)&mask = mask  ✔
```

Pitfalls:
- Requires power-of-two dimensions. Non-PoT needs `((x % n) + n) % n` (two `sdiv`s) or a
  multiply-shift reciprocal; just require PoT for HolyGL textures.
- If you use logical (zero-fill) right shift instead of arithmetic, negatives break.
  On AArch64 `LSR` on a negative gives a huge positive; use `ASR`/`SSHR`.
- `u >> 16` on a *float-derived* coordinate truncates toward zero, not floor. Convert
  with `FRINTM` before `FCVTZS` if you go the FP route (§2).

**CLAMP_TO_EDGE** — branchless with `SMIN`/`SMAX`:

```
tx = u >> 16
if (tx < 0)      tx = 0
if (tx >= tex_w) tx = tex_w - 1
```

NEON 4-lane form:

```asm
sshr    v0.4s, v0.4s, #16          // u >> 16
smax    v0.4s, v0.4s, v_zero.4s   // max(tx, 0)
smin    v0.4s, v0.4s, v_w1.4s     // min(tx, w-1)
```

For the four bilinear taps, CLAMP each of `iu, iu+1, iv, iv+1` independently; do not
clamp `iu` to `w-2`.

**BORDER / MIRROR** (optional): mirror = `mask ^ ((x>>log2w)&mask)` for PoT; border
returns a constant texel.

## 1.6 Alpha blending, `GL_SRC_ALPHA` / `GL_ONE_MINUS_SRC_ALPHA`

Straight (non-premultiplied) form, per channel, `a ∈ [0,255]`:

```
out = (src*a + dst*(255-a) + 127) / 255      // exact round-to-nearest
```

`/255` must be exact and branch-free. The identity for `x ∈ [0, 65025]`:

```
t   = x + 128
out = (t + (t >> 8)) >> 8                     // == round(x / 255), bit-exact
```

Proof sketch: `t + (t>>8) = t·(1 + 2^-8)` rounded down, and `>>8` divides by 256;
the `+128` biases to nearest. Verify on the boundaries `x=0→0`, `x=255→1`,
`x=65025→255`.

So:

```
a   = tex.a                                   // 0..255
inv = 255 - a
r   = div255(tex.r*a + fb.r*inv)
g   = div255(tex.g*a + fb.g*inv)
b   = div255(tex.b*a + fb.b*inv)
```

NEON 4-pixel version (keep channels in 8-lane `16-bit` lanes so the products fit):

```asm
// vS = source RGBA bytes, vD = dest RGBA bytes, vA = alpha broadcast to 16-bit lanes
ushll   v0.8h, vS.8b, #0
ushll   v1.8h, vD.8b, #0
// inv = 255 - a
mov     v2.8h, #255
sub     v2.8h, v2.8h, vA.8h
mul     v0.8h, v0.8h, vA.8h
mla     v0.8h, v1.8h, v2.8h        // v0 = src*a + dst*inv
add     v0.8h, v0.8h, #128
ushr    v3.8h, v0.8h, #8
add     v0.8h, v0.8h, v3.8h
ushr    v0.8h, v0.8h, #8           // div255
xtn     v0.8b, v0.8h                // pack back to bytes
```

**Premultiplied alternative** (recommended for a compositor — see the DolDoc/glass work
in the roadmap): store `rgb*a`, then `out = src + dst*(255-a)` and skip the source
multiply. This is one `MLA` instead of a `MUL`+`MLA`, and it composites correctly.

Pitfalls:
- The 16-bit intermediate `src*a + dst*inv` maxes at `255*255 + 255*0 = 65025 < 65536`
  ✔; never widen to 8-bit before the `div255`.
- Order matters: `GL_SRC_ALPHA` blends the **source over** the destination; do not swap
  for HUD overlays unless you want the inverse.
- Blending must happen *after* the depth test (the current `RasterPixelScalar` writes
  color and Z in one branch at `RasterTile.HC:166-169`); read the framebuffer, blend,
  then store, keeping the Z write unchanged.

## 1.7 Integration shape for RasterTile.HC / HolyGL.HC

Add a second entry point that carries a texture descriptor, leaving the flat-color path
untouched (P4.2 regression tests at `RasterTile.HC:272-314` must keep passing):

```
class CRasterSpan {                 // extend the existing struct (RasterTile.HC:107)
  ... existing fields ...
  U64 tex_base;                     // RGBA8 texel pointer
  I64 tex_w, tex_h, tex_mask;       // PoT ⇒ mask
  I64 u0,u1,u2, v0,v1,v2;           // per-vertex u/W, v/W in 16.16
  I64 iw0,iw1,iw2;                  // per-vertex 1/W in 16.16
  I64 wrap_mode;                    // 0=REPEAT, 1=CLAMP
  I64 blend_mode;                   // 0=opaque, 1=src_alpha
};

U0 RasterSetUVW(u0,u1,u2, v0,v1,v2, w0,w1,w2, tex*, tw,th, wrap, blend);
I64 RasterTriangleZTex(x0,y0,x1,y1,x2,y2, color);   // dispatches to the textured span
```

`HolyGLSubmitTriangle` then sets the texture state (from `glBindTexture`/`glTexImage2D`
state to be added in P4.3 per `docs/02-TASKLIST.md:670-674`) before calling the textured
path. The exact-edge coverage test is reused verbatim; only the per-pixel body changes:
compute `w0,w1,w2` → `den`, `numU`, `numV` → `u,v` → filter → blend → store.

## 1.8 Pitfalls checklist (Topic 1)

1. Interpolating `u,v` directly instead of `u/W, v/W` — the classic "affine texture warp"
   on floors/walls.
2. Forgetting that `area` cancels in the ratio form; or dividing by `area` *and* by `den`
   (double-normalization ⇒ wrong scale).
3. Overflow of the attribute accumulator once subpixel bits are added (§1.3).
4. Truncation vs rounding in `sdiv` — add `den>>1` (all operands same sign).
5. Bilinear weights not summing to 256 (§1.4).
6. Clamping the *coordinate* instead of each *tap* at the edges (§1.5).
7. Blend applied before the depth test, or blending a rejected pixel.
8. `W` interpolation at the near plane — keep the `w <= 0.05` reject from
   `HolyGL.HC:260`, and also clip the triangle against the near plane *before* computing
   `1/W` (the roadmap notes near-plane clipping exists; verify it runs before this path).

## 1.9 References (Topic 1)

- Scratchapixel, *Perspective Correct Interpolation and Vertex Attributes* —
  https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/perspective-correct-interpolation-vertex-attributes.html
- Scratchapixel, *The Rasterization Stage* (edge function, Pineda) —
  https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/rasterization-stage.html
- Andrew Chan, *Perspective-Correct Interpolation* —
  https://andrewkchan.dev/posts/perspective-interpolation.html
- gamedev.net, *Tip of the day: bilinear filtering accuracy* —
  https://gamedev.net/blogs/entry/1696749-tip-of-the-day-bilinear-filtering-accuracy
- Stack Overflow, *How to avoid integer overflow of fixed point in rasterization* —
  https://stackoverflow.com/questions/76444945/how-to-avoid-integer-overflow-of-fixed-point-in-rasterization

---

# 2. ARM NEON (AArch64) texture sampling without gather

## 2.1 There is no gather

AArch64 Advanced SIMD has **no per-lane indexed memory load** (no x86 `gather`). The two
things people mistake for gather:

- **`TBL`/`TBX`** — *byte-level table lookup inside 1–4 vector registers* (≤ 64 bytes).
  They cannot touch memory. `TBL` writes `0` for out-of-range indices; `TBX` leaves the
  destination byte unchanged. (ARM ARM C7.2.397; corsix whirlwind tour.)
- **`LD1/…/LD4` with a single base** — contiguous/structured loads only; the address is
  not per-lane.

Consequently a software renderer fetches texels **scalar `LDR` + lane insert**, and uses
`TBL`/`TBX` for *in-register* table lookup (palettes, channel shuffles, 4×4 block
decode), not for arbitrary texture addressing.

## 2.2 Fetching 8 texels: scalar load + lane pack

RGBA8 texel = 32-bit word. To build a vector of 8 texels:

```asm
// x_t is the texel base; x_off[k] are byte offsets for 8 pixels (8 separate LDRs)
ldr   w10, [x_t, x_off0]          // texel 0 (RGBA8)
ldr   w11, [x_t, x_off1]
...
ins   v20.s[0], w10               // lane insert from general register
ins   v20.s[1], w11
...
ins   v20.s[7], w17
```

`INS Vd.S[lane], Wn` is the element-insert. There is no way around the 8 scalar loads for
a genuinely scattered gather; the SIMD win is in the *coordinate math and the filter
math*, not the fetch.

If the 8 addresses are **contiguous** (a horizontal run), replace 8 `LDR` with
`LD1 {v20.4s}, [x]` / `LD1 {v21.4s}, [x,#16]` — this is the common case for a
screen-aligned textured quad and for texture-atlas blits.

**Where `TBL` genuinely helps:** 8-bit *indexed* textures (palettised, or 4bpp/8bpp),
SDF channel selection, or unpacking `R5G6B5`/`RGBA4` texels into lanes. Example: load 16
texels' worth of bytes into `v0..v3` (64-byte table) and select per-lane bytes with
`TBL v0.16b, {v4.16b,v5.16b,v6.16b,v7.16b}, v8.16b`.

```asm
// palette lookup: vIdx holds 16 palette indices (0..15) for a 16-entry RGBA palette
// stored in v0..v3 (16 bytes each = 64 bytes = 16 RGBA texels)
tbl   v9.16b, {v0.16b,v1.16b,v2.16b,v3.16b}, vIdx.16b   // out-of-range ⇒ 0
```

## 2.3 Vectorizing the coordinate math (keep the fetch scalar)

The pipeline per 4-pixel block:

1. Integer 16.16 `u,v` → float: `SCVTF`.
2. Multiply by texel dimensions, floor, get integer texel + fraction.
3. Fetch texels (scalar `LDR`).
4. Filter (SIMD `MUL`/`MLA`/`SHRN`, §1.4).
5. Blend (SIMD, §1.6).

```asm
// v0.4s = u (16.16 int), v1.4s = v
scvtf   v2.4s, v0.4s              // I2F
scvtf   v3.4s, v1.4s
fmul    v2.4s, v2.4s, v_texw      // * tex_w  (v_texw = broadcast float)
frintm  v2.4s, v2.4s              // floor toward -inf (matches REPEAT semantics)
fcvtzs  v4.4s, v2.4s              // F2I: integer texel iu (4 lanes)
fsub    v5.4s, v2.4s, v4.4s       // fu = floor(u) - u  (0..1)
frintm  v3.4s, v3.4s
fcvtzs  v6.4s, v3.4s              // iv
fsub    v7.4s, v3.4s, v6.4s       // fv
// f2i weights, then scalar texel fetch using v4/v6 lanes moved to GPRs
umov    w_i0, v4.s[0]
umov    w_j0, v6.s[0]
// ... ldr + ins for the 4 pixels
```

**Reciprocal `1/W`.** `FDIV Vd.4S` is exact but ~10–20 cycles. `FRECPE` gives an 8-bit
estimate; one Newton step (`FRECPS` + `FMUL`) gives ~16 bits — enough for 16.16 texture
coordinates:

```asm
frecpe  v1.4s, v0.4s              // est ≈ 1/W
frecps  v2.4s, v1.4s, v0.4s       // 2 - W*est
fmul    v1.4s, v1.4s, v2.4s       // refined 1/W (≈16-bit accurate)
```

Use `FDIV` only where full precision matters (the `numU/den` integer divide is already
exact scalar `SDIV`, so prefer the integer path).

**Integer alternative (no FP at all).** Keep everything in 16.16 as in §1: `iw_i` in
16.16, `numU = w0*U0 + w1*U1 + w2*U2`, `u = (numU<<16)/den` with scalar `SDIV`. This
avoids the FP↔int round-trips and matches the existing exact Z path. The NEON win is the
**coverage + depth + blend**, while the perspective divide stays scalar — exactly the
structure of `scripts/raster_span.s:107-128`.

## 2.4 Register pressure strategy

AArch64 gives 32 × 128-bit registers, but the ABI reserves `v8..v15` (low 64 bits) as
callee-saved, and the HolyC JIT / trap frame saves all 32 Q registers
(`Sched.HC:52`, 784-byte frame). In a hand-written span kernel you own all 32.

Observed pressure in `raster_span.s`: it uses `v0..v7` (edge lane constants + edges),
`v15` (color), `v16..v21` (edge deltas/vertices), `v22..v27` (per-block edge increments),
`v28` (Z lanes), `v29` (Z buffer), `v30/v31` (mask). That is ~20 live registers for the
**flat-color** path. Texture adds `u,v` (2), `1/W` (2), `iu,iv,fu,fv` (4), texel taps
(4), accumulators (4) = ~16 more. Strategies:

1. **Reload from the descriptor.** The `CRasterSpan` struct is a flat, cache-hot block
   (`RasterTile.HC:98-120`). Load the per-triangle fields once into `x` registers and
   keep *per-pixel* quantities in vector registers; reload anything cold with a single
   `LDR` from `x9` (the descriptor base) rather than holding it live.
2. **Process 4 pixels, not 8**, for the textured path. 8-pixel spans force 8-lane
   temporaries for `u,v,iu,iv,fu,fv` and blow the budget; 4-pixel blocks keep the whole
   coordinate+filter set in ~16 registers and still amortize the loop overhead.
3. **Spill to the stack** for the rare path (CLAMP, blend) and keep the hot REPEAT/opaque
   path in registers. The `stp/ldp` prologue already exists (`raster_span.s:19-22`); add
   slots for `u,v` vertex constants if needed.
4. **Keep `1/W` in a single register set** and recompute `u,v` from it; don't keep both
   `u/W` and `u` live.

## 2.5 Pitfalls (Topic 2)

1. Assuming `TBL` can index memory — it cannot; it is a 64-byte register file lookup.
2. Using `TBL` where `TBX` is needed (merging into an existing destination) — `TBL`
   zeroes out-of-range lanes.
3. `FRECPE` alone is only 8-bit accurate; two Newton steps needed for ~32 bits.
4. `FCVTZS` truncates toward zero; pair with `FRINTM` for floor semantics on REPEAT.
5. Mixing `F64` (D registers) and `F32` (S registers) lane counts — the current span
   uses `.4s`/`.4h`; keep texture math `.4s` to match.
6. Clobbering callee-saved `v8..v15` without saving them if the kernel is called from
   C/JIT code that expects them preserved (the scheduler frame saves them, but hand-asm
   helpers must too if used outside that path).
7. Non-temporal stores (`STNP`) used by the blitter are *not* appropriate for texture
   fetch; use normal `LDR`/`LD1`.

## 2.6 References (Topic 2)

- ARM, *TBL* (A64 Advanced SIMD) — https://support.arm.com/documentation/ddi0487/mc/-Part-C-The-AArch64-Instruction-Set/-Chapter-C7-A64-Advanced-SIMD-and-Floating-point-Instruction-Descriptions/-C7-2-Alphabetical-list-of-A64-Advanced-SIMD-and-floating-point-instructions/-C7-2-397-TBL
- ARM, *TBX* — https://developer.arm.com/documentation/100069/0610/A64-SIMD-Vector-Instructions/TBX--vector-
- corsix, *A whirlwind tour of AArch64 vector instructions (NEON)* —
  https://www.corsix.org/content/whirlwind-tour-aarch64-vector-instructions
- ARM, *Permutation — Neon instructions* —
  https://support.arm.com/documentation/102159/0400/Permutation---Neon-instructions
- ARM, *Neon* — https://developer.arm.com/Architectures/Neon
- Biesheuvel, *AES S-Box via TBL/TBX* (constant-time table lookup) —
  https://eprint.iacr.org/2022/1154.pdf

---

# 3. ARM64 lock-free MPMC ring buffer (no libatomic)

## 3.1 Current state and why it is only SPSC

`Smp.HC` implements one job slot per core (`SmpGetJob`, `Smp.HC:30-32`) with a
`pending`/`completed` handshake and `__dmb_ish()` fences (`Smp.HC:57-85`). That is a
**lockless SPSC mailbox**: exactly one producer (BSP) and one consumer (worker) per slot.
A general run-queue needs MPMC (any core can push/pull work).

## 3.2 Exclusives: LDXR/STXR vs LDAXR/STLXR

- `LDXR`/`STXR` = load-linked / store-conditional **without** ordering; pair with explicit
  `DMB`.
- `LDAXR`/`STLXR` = the same but with **acquire / release** semantics built in — no extra
  `DMB` needed for the CAS itself. Linux uses `LDAXR`/`STLXR` for its AArch64 spinlocks.
- `LDXP`/`STXP` are the 128-bit pair forms.
- Armv8.1+ LSE adds single-instruction atomics (`CAS`, `CASAL`, `LDADD`, `SWP`) that avoid
  the retry loop; check `ID_AA64ISAR0_EL1.Atomics` before relying on them. Cortex-A72 is
  Armv8.0 → **use the LL/SC path** as the baseline.

CAS (compare-and-swap) loop, portable:

```asm
// w0 = expected, w2 = new, x1 = &var; returns old in w0, success flag in w3
.retry:
    ldaxr   w3, [x1]            // load-acquire + claim
    cmp     w3, w0
    b.ne    .fail
    stlxr   w4, w2, [x1]        // store-release + commit
    cbnz    w4, .retry          // exclusive lost ⇒ retry
    mov     w3, #1
    b       .done
.fail:
    mov     w3, #0
.done:
    // w3 = 1 on success, w0/w3 holds the observed value
```

`atomic_fetch_add` (returns old, adds new), self-contained (no libatomic):

```c
static inline U64 atomic_fetch_add_acq_rel(U64 *p, U64 v) {
    U64 old, tmp; U32 st;
    __asm__ volatile(
        "1: ldaxr %0, [%3]\n"
        "   add   %1, %0, %4\n"
        "   stlxr %w2, %1, [%3]\n"
        "   cbnz  %w2, 1b\n"
        : "=&r"(old), "=&r"(tmp), "=&w"(st)
        : "r"(p), "r"(v) : "memory");
    return old;
}
```

`__atomic_*` builtins from GCC/Clang lower to exactly this for 32/64-bit lock-free types
**without** libatomic; only non-lock-free (128-bit) types pull libatomic in. Since the
runtime (`boot/`) is compiled C, prefer `__atomic_load_n(p, __ATOMIC_ACQUIRE)` /
`__atomic_store_n(p, v, __ATOMIC_RELEASE)` / `__atomic_compare_exchange_n(...)`; the HolyC
JIT side needs its own `__ldaxr/__stlxr` intrinsics added (a small addition to
`Compiler.HC` / `jit_arm64.c`).

## 3.3 The ABA problem, and how to avoid it without hazard pointers

ABA bites **pointer/ownership-based** structures (a freelist head is popped, pushed back,
and the CAS succeeds on a stale-but-equal value). Two robust escapes that need no
hazard pointers or RCU:

1. **Monotonic 64-bit indices, never reused.** Producers/consumers CAS a *counter*, not a
   pointer. A 64-bit counter wrapping at 2^64 events is unreachable. The current code
   already uses `g_sched_next_id` monotonic ids (`Sched.HC:132,175`).
2. **Dmitry Vyukov's bounded MPMC queue.** Each cell carries a *sequence number* that
   encodes whose turn it is; ABA cannot occur because a cell is only reused after its
   sequence has advanced past the consumer's reservation. This is the recommended design
   for NeoOS per-core run-queues.

### Vyukov bounded MPMC queue (per-cell sequence)

```c
typedef struct { U64 seq; void *data; } cell_t;

typedef struct {
    U64 mask;            // capacity - 1 (capacity is a power of two)
    cell_t *cells;       // capacity entries
    U64 enqueue;         // producer cursor
    U64 dequeue;         // consumer cursor
} mpmc_t;

void mpmc_init(mpmc_t *q, U64 capacity) {
    q->mask  = capacity - 1;
    q->cells = kzalloc(capacity * sizeof(cell_t));
    for (U64 i = 0; i < capacity; i++) q->cells[i].seq = i;
    q->enqueue = q->dequeue = 0;
}

int mpmc_push(mpmc_t *q, void *data) {
    U64 pos = atomic_fetch_add_acq_rel(&q->enqueue, 1);   // reserve a slot
    cell_t *c = &q->cells[pos & q->mask];
    for (;;) {
        U64 seq = atomic_load_acquire(&c->seq);           // LDAR
        I64 dif = (I64)seq - (I64)pos;
        if (dif == 0) break;                              // our turn
        if (dif < 0)  return 0;                           // full
        spin_pause();                                     // dif > 0: producer ahead
    }
    c->data = data;
    atomic_store_release(&c->seq, pos + 1);               // STLR: publish
    return 1;
}

void *mpmc_pop(mpmc_t *q) {
    U64 pos = atomic_fetch_add_acq_rel(&q->dequeue, 1);
    cell_t *c = &q->cells[pos & q->mask];
    for (;;) {
        U64 seq = atomic_load_acquire(&c->seq);
        I64 dif = (I64)seq - (I64)(pos + 1);
        if (dif == 0) break;                              // our turn
        if (dif < 0)  return NULL;                        // empty
        spin_pause();
    }
    void *d = c->data;
    atomic_store_release(&c->seq, pos + q->mask + 1);     // free the cell
    return d;
}
```

Notes:
- `atomic_fetch_add_acq_rel` is the LDAXR/STLXR loop above; `atomic_load_acquire` is a
  plain `LDAR`; `atomic_store_release` is `STLR`.
- The `dif < 0` / `dif > 0` comparisons must be **signed** — cast the `U64` difference to
  `I64` so the wrap at 2^64 is handled by the modular arithmetic.
- Capacity must be a power of two so `& mask` replaces `%`.
- ABA-free by construction: `seq` is never equal to a stale reservation.

## 3.4 Memory ordering: where the barriers go

| Purpose | Instruction | Linux macro |
|---|---|---|
| Full barrier | `DMB ISH` | `smp_mb()` |
| Load-load / load-store ordering | `DMB ISHLD` | `smp_rmb()` |
| Store-store ordering | `DMB ISHST` | `smp_wmb()` |
| Acquire (no later op moves up) | `LDAR` / `LDAXR` | `smp_load_acquire` |
| Release (no earlier op moves down) | `STLR` / `STLXR` | `smp_store_release` |

The **producer→consumer handoff** must be: write payload → `DMB ISHST` (or the payload
store itself is `STLR`) → `STLR` the sequence/ready flag. The consumer: `LDAR` the flag →
`DMB ISHLD` (or rely on the `LDAR`) → read payload. The existing mailbox does the
`DMB ISH` *before* `pending=1` (`Smp.HC:181-183`) which is correct but stronger than
needed; replacing the `pending` store with `STLR` and the load with `LDAR` removes two
full barriers per dispatch.

`WFE`/`SEV`: after publishing, `SEV`; the consumer loops `while (!ready) WFE;` and
re-checks (WFE can return spuriously). `Smp.HC:62-65` and `Smp.HC:184` already do this.

## 3.5 Per-core run-queues for a ring-0 SASOS

Two topologies, in increasing complexity:

1. **MPSC inbox per core** (simplest, matches the existing per-core slot idea). Each core
   owns a ring; any core may enqueue (multi-producer), only the owner dequeues
   (single-consumer). Enqueue needs a CAS on `tail` (or the Vyukov push); dequeue is a
   plain `LDAR` of `tail` + read. This is enough for "dispatch a job to core N" and keeps
   the owner's dequeue branch-free.
2. **Per-core work-stealing deques** (Chase–Lev). Owner pushes/pops one end; thieves CAS
   the other end. This gives load balancing for the tile rasterizer. Chase–Lev uses a
   CAS on the *top* index and a plain store on the *bottom*, with a `DMB ISH` between.

Given the 4-core Cortex-A72 target (`Smp.HC:4`, `SMP_MAX_CORES 4`), an array of 4 MPSC
inboxes plus an MPMC "global" queue is the pragmatic choice: enqueue to the least-loaded
owner, steal from the global queue when idle.

**SASOS structure:**
- The queues live in the single flat address space; no serialization/deserialization,
  pass raw `U64` pointers (as `SmpDispatch` already passes `fn`/`arg` as `U64`,
  `Smp.HC:169-201`).
- Never dereference a queue node after `pop` returns it to the free pool — with the Vyukov
  scheme there is no separate node free pool, cells are fixed, so this class of UAF is
  structurally impossible.
- Since all cores share the address space, a stolen job may touch any global; that is by
  design, but it means the memory ordering around the *data* must be the `STLR`/`LDAR`
  above, not just around the queue metadata.

## 3.6 Pitfalls (Topic 3)

1. Using `LDXR`/`STXR` **without** a `DMB` and expecting acquire/release — use
   `LDAXR`/`STLXR`.
2. Forgetting the release barrier before the "ready" flag ⇒ consumer reads torn payload.
3. ABA when reusing indices/pointers; use sequence counters or monotonic ids.
4. The exclusive monitor is **lost** by an interrupt/`ERET`, by an unrelated exclusive
   access, or by cache eviction. Always retry, and bound retries with a fallback (yield)
   to avoid livelock.
5. `%` on a non-power-of-two capacity in the inner loop — require PoT and `& mask`.
6. Signed/unsigned confusion in the `seq - pos` comparison — cast to `I64`.
7. Assuming LSE `CAS` exists on Armv8.0 hardware; probe `ID_AA64ISAR0_EL1`.
8. `WFE` without a re-check loop; `WFE` may wake with the condition still false.
9. Touching a popped node after it is recycled (not an issue with fixed-cell Vyukov).

## 3.7 References (Topic 3)

- ARM, *Implementation Software Synchronization Primitives in A64* —
  https://documentation-service.arm.com/static/68c223238a337a2bc6645c0a
- ARM, *Acquire and Release semantics* —
  https://support.arm.com/documentation/111493/100/2--Synchronization/2-3--Acquire-and-Release-semantics
- Linux Kernel Internals, *ARM64 Memory Model* —
  https://kernel-internals.org/arch/arm64/memory-model/
- Rust Atomics and Locks, *Chapter 7. Understanding the Processor* (ARM64 mapping) —
  https://mara.nl/atomics/hardware.html
- Stack Overflow, *ARM64: LDXR/STXR vs LDAXR/STLXR* —
  https://stackoverflow.com/questions/21535058/arm64-ldxr-stxr-vs-ldaxr-stlxr
- K. McKenzie, *A Simple Lock-free Ring Buffer* (sequence-number reasoning) —
  https://kmdreko.github.io/posts/20191003/a-simple-lock-free-ring-buffer

---

# 4. CRC32C (Castagnoli) and block-integrity commit patterns

## 4.1 256-entry table algorithm

Reflected (LSB-first) CRC-32C. Polynomial `0x1EDC6F41` (normal) = `0x82F63B78` (reflected),
`init = 0xFFFFFFFF`, `refin = refout = true`, `xorout = 0xFFFFFFFF`.

```c
static U32 crc32c_table[256];

static void crc32c_init_table(void) {
    for (U32 i = 0; i < 256; i++) {
        U32 c = i;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? (0x82F63B78u ^ (c >> 1)) : (c >> 1);
        crc32c_table[i] = c;
    }
}

U32 crc32c(U32 crc, const U8 *p, U64 n) {
    crc = ~crc;                                   // init / xorout = ~0
    while (n--) crc = crc32c_table[(crc ^ *p++) & 0xFF] ^ (crc >> 8);
    return ~crc;
}
```

**Self-test vector:** `crc32c(0, "123456789", 9) == 0xE3069283`. Bake this into a boot
self-test (mirror the style of `RasterBootCheck`, `RasterTile.HC:272`).

**Hardware path (optional, Armv8 CRC32 extension):** `CRC32CB`/`CRC32CH`/`CRC32CW`/
`CRC32CX` implement the Castagnoli polynomial in hardware:

```asm
crc32cb w0, w0, w1     // w0 = crc, w1 = byte   (CRC-32C, byte)
crc32ch w0, w0, w1     // halfword
crc32cw w0, w0, w1     // word
crc32cx w0, w0, x1     // doubleword
```

The instructions do **not** apply the init/final XOR; wrap them with `~crc` at the ends
and validate against the test vector (the exact bit-order convention of the running value
is easy to get wrong — the self-test is the arbiter). Probe `ID_AA64ISAR0_EL1.CRC32`.
(Armv8.0 also has the non-C `CRC32B` using the IEEE polynomial — do not confuse them.)

**Combining CRCs (useful for block trees):**
- `crc32c_xor(size, a, b) = a ^ b ^ crc32c_add_zeros(0, size)`
- `crc32c_append(a, size_b, b) = mul_mod_p(a, x^{size_b}) ^ b`
These need `crc32c_mul_mod_p` (carry-less multiply; `PMULL`/`CLMUL` if available, else
software). For a simple FS you can skip them and re-CRC whole blocks.

## 4.2 Block-integrity commit patterns

### littlefs (log-structured metadata, power-loss safe)

From the littlefs SPEC: each **metadata block** starts with a 32-bit revision count,
followed by a sequence of **commits**; each commit is a variable-length run of metadata
entries terminated by a **32-bit CRC tag**. The CRC covers *all metadata since the
previous CRC tag, including the CRC tag itself*; the tag's chunk field carries flags.
Entries are not word-aligned, so a commit may be padded to the **program alignment** of
the flash. On mount, the highest revision whose last commit's CRC validates wins; the
metadata **pair** (two blocks) lets you fall back if the newest block is torn.

CRC here is IEEE `0x04c11db7`, init `0xffffffff` — note it is **not** Castagnoli; pick one
and document it (Castagnoli is preferable on Arm because of the CRC32C instructions).

### ZFS uberblock (copy-on-write, atomic commit point)

ZFS groups all writes into a **transaction group (TXG)**; every modified block is written
**copy-on-write** (never overwritten in place), forming a Merkle tree. The root —
the **uberblock** — is updated **atomically**, which makes the on-disk image always
consistent. The uberblock ring holds several slots; the one with the highest
**monotonically increasing `ub_txg`** whose checksum validates is the live root. Because
the txg number only ever increases, it doubles as a global version.

### Minimal NeoOS FS commit protocol

```c
class CBlock {                     // 4 KiB block header
  U64 magic;      U64 txg;         // transaction group (monotonic)
  U64 type;       U64 flags;       // data / inode / dir / uberblock
  U64 data_crc;                    // CRC32C over the block payload
  U64 self_crc;                    // CRC32C over this header (with self_crc=0)
};

class CUberblock {                 // one of N slots, e.g. 4
  U64 magic;      U64 txg;
  U64 root_block;                  // physical block id of the tree root
  U64 ub_crc;                      // CRC32C over the uberblock fields
};

// commit:
// 1. write all new data/metadata blocks COW (fresh block ids)
// 2. flush each block: DC CVAC over the range; DSB SY   (durability)
// 3. write new uberblock into slot (txg & (N-1)): fields, then ub_crc
// 4. DC CVAC the uberblock slot; DSB SY                  (commit point)
// 5. increment txg
```

Mount: scan all `N` uberblock slots, validate `ub_crc`, pick the highest valid `txg`;
then walk `root_block` verifying `self_crc` on every node (ZFS-style end-to-end
integrity). A torn write to a data block is detected by `data_crc`; a torn uberblock is
detected by `ub_crc` and simply ignored in favour of the previous slot.

**Bare-metal ordering (critical).** On AArch64, a normal store is not durable until it
reaches the PoC: `DC CVAC addr; DSB SY`. For a virtio-blk device, the device's completion
interrupt is the durability signal for its writes; order the uberblock write *after* all
data-block completions. Never mark an uberblock committed before its payload blocks are
durable.

## 4.3 Pitfalls (Topic 4)

1. Wrong polynomial orientation: `0x82F63B78` is the **reflected** Castagnoli; using
   `0x1EDC6F41` in the reflected loop yields garbage. Pick reflected+reflected.
2. Forgetting the `~` at both ends (init/xorout) — the check value will not match
   `0xE3069283`.
3. Mixing IEEE `0xEDB88320` and Castagnoli in one FS. Choose Castagnoli for Arm.
4. Computing the CRC over a header that includes its own CRC field without zeroing it
   first — define the convention (littlefs covers the tag itself; pick one and be
   consistent).
5. Not padding commits to flash program alignment before writing (littlefs pitfall) —
   partial-program corruption.
6. Marking the commit durable before `DC CVAC`+`DSB` — a power loss leaves a "valid"
   uberblock pointing at non-durable data.
7. Non-monotonic txg numbers (reuse after wrap) breaks "highest txg wins"; use `U64`.

## 4.4 References (Topic 4)

- mazzo.li, *CRC-32C tips and tricks* (polynomial math, `0x82F63B78`, combine ops) —
  https://mazzo.li/posts/crc-tips.html
- OSDev Wiki, *CRC32* (polynomials) — https://wiki.osdev.org/CRC32
- littlefs, *SPEC.md* (metadata pair, CRC tag, program alignment) —
  https://github.com/littlefs-project/littlefs/blob/master/SPEC.md
- littlefs technical specification (MCUXpresso mirror) —
  https://mcuxpresso.nxp.com/mcuxsdk/latest/middleware/littlefs/SPEC.html
- littlefs, *DESIGN.md* (CRC chain diagram) —
  https://github.com/littlefs-project/littlefs/blob/master/DESIGN.md
- *End-to-end Data Integrity for File Systems: A ZFS Case Study* —
  https://research.cs.wisc.edu/wind/Publications/zfs-corruption-fast10.pdf
- ZFS internals (uberblock / TXG) — https://internals-for-interns.com/posts/zfs-filesystem
- CRC-32C reference implementations (machinezoo) — https://crc32c.machinezoo.com

---

# 5. stb_truetype outline rasterization + SDF generation

The current font stack (`FontVector.HC`) draws **stroked** quadratic Béziers
(`BezierEval1D`, `FontVector.HC:16-22`; 12-segment tessellation at
`FontVector.HC:28-42`). It cannot fill a closed glyph outline with holes, and it has no
distance field. This section gives the two missing pieces.

## 5.1 TrueType outline → edges

TrueType `glyf` contours are sequences of on-curve and off-curve (control) points;
consecutive off-curve points imply an on-curve midpoint. `stbtt_GetGlyphShape` produces a
vertex list where each vertex is `move / line / quadratic-curve / cubic-curve`
(`stbtt_vertex`, see `stb_truetype.h`). Flatten each curve into line segments at a
flatness tolerance (stb uses `flatness_in_pixels`); a quadratic can be recursively
subdivided, or adaptively sampled by the deviation `|P0 - 2P1 + P2|/4`.

**Directed edges** are `(x0,y0) → (x1,y1)` with a direction sign (+1 for one winding,
−1 for the other) so the nonzero fill rule works with holes.

## 5.2 stb_truetype v2 signed-area rasterizer (exact AA coverage)

This is the algorithm described by Sean Barrett ("How the stb_truetype Anti-Aliased
Software Rasterizer v2 Works", https://nothings.org/gamedev/rasterize/). It computes, per
pixel, the signed area of the polygon clipped to the pixel, using right-extending
trapezoids and an **inverse cumulative-sum** trick, in one linear pass.

Algorithm:

```
1. Gather directed edges, sort by topmost vertex.
2. For each 1-pixel-tall scanline y:
   a. Add edges whose topmost vertex is in this scanline to the active list
      (store their x at this scanline).
   b. Remove edges whose bottom vertex is above this scanline.
   c. Compute per-pixel signed-area coverage for the scanline:
        - For each active edge, add the rightward-trapezoid area into A[i]
          and the "height" contribution into the difference array X[i]
          (so that X is the inverse of the cumulative sum S).
   d. s = 0
      for i in 0..n:
          s = s + X[i]
          a = A[i] + s
          pixel[i] = 255 * a         // coverage, clamp 0..255
3. Advance each active edge to the next scanline (x += dx/dy).
```

The per-edge "Case 2" code (edges spanning ≥2 pixels) from stb_truetype, reproduced from
Barrett's write-up:

```c
{
   int x, x1, x2;
   float y_crossing, step, sign, area;
   // covers 2+ pixels
   if (x_top > x_bottom) {
      float t;
      y0 = y_bottom - (y0 - y_top);
      y1 = y_bottom - (y1 - y_top);
      t = y0, y0 = y1, y1 = t;
      t = x_bottom, x_bottom = x_top, x_top = t;
      dx = -dx; dy = -dy;
      t = x0, x0 = xb, xb = t;
   }
   x1 = (int) x_top;
   x2 = (int) x_bottom;
   y_crossing = (x1 + 1 - x0) * dy + y_top;
   sign = e->direction;
   area = sign * (y_crossing - y0);
   scanline[x1] += area * (1 - ((x_top - x1) + (x1 + 1 - x1)) / 2);
   step = sign * dy;
   for (x = x1 + 1; x < x2; ++x) {
      scanline[x] += area + step / 2;
      area += step;
   }
   y_crossing += dy * (x2 - (x1 + 1));
   scanline[x2] += area + sign * (1 - ((x2 - x2) + (x_bottom - x2)) / 2) * (y1 - y_crossing);
   scanline_fill[x2] += sign * (y1 - y0);
}
```

Then the finite-difference pass:

```c
int s = 0;
for (i = 0; i < n; i++) {
    s += scanline_fill[i];        // X[]
    float a = scanline[i] + s;    // A[] + S
    if (a < 0) a = 0; else if (a > 1) a = 1;
    bitmap[i] = (unsigned char)(a * 255);
}
```

**Legacy v1 (oversampled scanline):** active edge list + 1-D horizontal AA, with 5× or
15× vertical oversampling (chosen because 5 and 15 divide 255 evenly). Simpler to
implement but ~15% slower and less accurate. For NeoOS, implement v2.

## 5.3 SDF generation (stb `stbtt_GetGlyphSDF`)

stb's SDF is a **brute-force** signed distance field: for every pixel centre, find the
minimum distance to every outline edge (analytic closest point on a line or quadratic),
and sign it by the winding number. From `stb_truetype.h` (`GetGlyphSDF`):

```
1. Get the glyph shape verts (scaled to pixel space; y is negated for y-down bitmaps).
2. For each edge, precompute 1/len (line) or 1/len2 (quadratic) for fast distance.
3. For each pixel (x,y) in the padded bbox:
     sx = x + 0.5;  sy = y + 0.5;            // pixel centre
     winding = crossings_x(sx/scale, sy/scale, verts);   // nonzero ⇒ inside
     min_dist = +INF
     for each edge:
        if line:   closest point on the segment (project t, clamp to [0,1]);
                   dist = |cross| * 1/len, else endpoint distance
        if quad:   solve the cubic for the closest point on the quadratic;
                   evaluate at up to 3 roots in [0,1]; take min distance
        min_dist = min(min_dist, dist)
     if (winding == 0) min_dist = -min_dist;   // outside ⇒ negative
     val = onedge_value + pixel_dist_scale * min_dist;
     val = clamp(val, 0, 255);
     data[(y-iy0)*w + (x-ix0)] = (unsigned char)val;
```

Encoding/reconstruction:
- `onedge_value` (e.g. 128) is the value on the outline isocontour.
- `pixel_dist_scale` is how many byte-units one pixel of distance adds; for a 5-pixel
  spread with `onedge_value = 128`, `pixel_dist_scale = 128/5 = 25.6`.
- Reconstruct alpha with a smoothstep across ±0.5 texel:
  `alpha = clamp((sample - onedge)/pixel_dist_scale * 1.0 + 0.5, 0, 1)` (equivalently
  `smoothstep`), then blend with §1.6.

Line-distance core (from the source, `stbtt.h:4650-4673`):

```
dist2 = (x0-sx)^2 + (y0-sy)^2                       // endpoint distance
dist  = |(x1-x0)*(y0-sy) - (y1-y0)*(x0-sx)| / len   // perpendicular distance
t     = -((x0-sx)*(x1-x0) + (y0-sy)*(y1-y0)) / len2 // projection
if (0 <= t <= 1) min_dist = dist
```

Quadratic distance solves a cubic in `t` (stb `stbtt__solve_cubic`) after the standard
substitution; see `stbtt.h:4674-4742`.

**Cheaper alternative for NeoOS:** generate a high-res coverage bitmap with the v2
rasterizer (§5.2), threshold at 50%, then run a 2-pass **Felzenszwalb exact Euclidean
distance transform** (O(w·h) per axis) to get an unsigned field, and take the sign from
the threshold bitmap. This trades exact edge distance for speed and is what most runtime
SDF bakers use.

## 5.4 Structure for NeoOS (ring-0 SASOS, no deps)

- Keep it single-file, no libc: replace `malloc/free/sqrt/fabs` with the kernel's
  `kmalloc/kfree`, `MathSqrt` (`Math3D.HC:64-74`), and a local `fabs`. stb_truetype is
  explicitly parameterizable (`STBTT_malloc`, `STBTT_sqrt`, …) so this is mechanical.
- **Bake at boot, cache forever.** SDF generation is O(w·h·edges); bake each glyph once
  into a shared atlas (the single address space means the atlas pointer is valid
  everywhere, no copying). Store the atlas in the kernel heap (`kheap.c`).
- Because there is no MMU protection, treat font data as trusted or add the range checks
  stb explicitly omits ("NO SECURITY GUARANTEE" in `stb_truetype.h`) — a corrupt font can
  read arbitrary memory. For a personal OS loading only bundled fonts this is acceptable;
  document it.
- Composite the SDF glyph as a textured quad through HolyGL (the atlas is just a texture),
  reusing §1.2–§1.6. This unifies text with the 3D pipeline instead of the current
  stroke-by-stroke `gfx_draw_line` path.

## 5.5 Pitfalls (Topic 5)

1. Nonzero vs even-odd winding for glyphs with holes (counters of `o`, `B`) — use the
   nonzero rule and consistent edge direction.
2. Overlapping/self-intersecting contours double-count in the signed-area rasterizer
   (stb bug #1524 and the "Limitations" section of Barrett's write-up) — clamp coverage.
3. Off-curve midpoint handling: skipping the implied on-curve points distorts curves.
4. SDF padding must be ≥ the spread, or the field clips at the bitmap border.
5. `pixel_dist_scale` sign and `onedge_value` must match the reconstruction shader, or
   text renders inverted/aliased.
6. 8-bit SDF precision limits the usable spread; for larger spreads use 16-bit (stb
   supports it via the scale factor, but you must widen the atlas).
7. Flattening tolerance too coarse ⇒ faceted glyphs; too fine ⇒ slow bake.
8. No bounds checking on untrusted font tables (stb's documented caveat).

## 5.6 References (Topic 5)

- Sean Barrett, *How the stb_truetype Anti-Aliased Software Rasterizer v2 Works* —
  https://nothings.org/gamedev/rasterize/
- stb_truetype source (`stbtt_GetGlyphSDF`, rasterizer) —
  https://github.com/nothings/stb/blob/master/stb_truetype.h
- DeepWiki, *TrueType Font Processing (stb_truetype)* — SDF section —
  https://deepwiki.com/nothings/stb/3.1-truetype-font-processing-(stb_truetype)
- Red Blob Games, *Signed Distance Field Fonts* —
  https://www.redblobgames.com/x/2403-distance-field-fonts
- Raph Levien, *Inside the fastest font renderer in the world* —
  https://medium.com/@raphlinus/inside-the-fastest-font-renderer-in-the-world-75ae5270c445

---

# 6. Chibicc / SubC single-pass compiler techniques

## 6.1 Token and lexer arenas

The current C lexer (`boot/seed/lexer.c`) returns a **by-value** `token_t` with a fixed
`str_value` buffer (`tok.h`), and `#define` handling `kmalloc`s a `int64_t` per macro
(`lexer.c:214-217`) — one allocation per definition, and identifiers are copied into a
fixed-size array per token. For a self-hosting HolyC compiler you want:

- **Bump arena** for tokens: allocate 64 KiB chunks; `arena_alloc(n)` returns a bump
  pointer; reset the whole arena between compilation units. No per-token `free`.
- **Interned identifier strings**: a single string arena + a hash set; a token stores a
  `char*` into the arena, so identifier comparison is pointer comparison. This also lets
  the symbol table key on the interned pointer.
- **Token linked list** (chibicc's model): `struct Token { Token *next; ... }` allocated
  from the arena; the preprocessor splices lists cheaply.

```c
typedef struct ArenaChunk { struct ArenaChunk *next; U64 used, cap; U8 data[]; } ArenaChunk;
typedef struct { ArenaChunk *head; } Arena;

void *arena_alloc(Arena *a, U64 n) {
    n = (n + 15) & ~15ULL;                       // 16-byte align
    if (!a->head || a->head->used + n > a->head->cap) {
        U64 cap = n > 65536 ? n : 65536;
        ArenaChunk *c = kmalloc(sizeof(ArenaChunk) + cap);
        c->next = a->head; c->used = 0; c->cap = cap;
        a->head = c;
    }
    void *p = a->head->data + a->head->used;
    a->head->used += n;
    return p;
}
```

## 6.2 FNV-1a hashing

Parameters (IETF draft-eastlake-fnv):

| Width | Offset basis | Prime |
|---|---|---|
| 32-bit | `0x811c9dc5` | `0x01000193` |
| 64-bit | `0xcbf29ce484222325` | `0x00000100000001B3` |

Canonical FNV-1a = **XOR first, then multiply**:

```c
U64 fnv1a(const U8 *s, int len) {
    U64 h = 0xcbf29ce484222325ULL;
    for (int i = 0; i < len; i++) { h ^= s[i]; h *= 0x100000001b3ULL; }
    return h;
}
```

**chibicc's actual `hashmap.c` does the multiply *before* the XOR** (`hash *= prime;
hash ^= byte;`), which is FNV-1 ordering under an FNV-1a name — a harmless but real
discrepancy worth knowing if you interop with it. Pick one order and be consistent.

**Open-addressing hashmap** (chibicc's design): `INIT_SIZE` buckets, linear probing
`(hash + i) % capacity`, `TOMBSTONE` for deletes, rehash when usage ≥ **70%**, growing
2× and keeping usage < 50%. Robin Hood or linear probing both fine; linear is simpler and
matches chibicc.

```c
typedef struct { char *key; int keylen; int val; } HashEntry;
typedef struct { HashEntry *buckets; int capacity; int used; } HashMap;

void hashmap_put(HashMap *m, char *key, int keylen, int val) {
    if (!m->buckets) { m->buckets = kzalloc(INIT_SIZE * sizeof(HashEntry));
                       m->capacity = INIT_SIZE; }
    else if ((m->used * 100) / m->capacity >= 70) rehash(m);
    U64 h = fnv1a((U8*)key, keylen);
    for (int i = 0; i < m->capacity; i++) {
        HashEntry *e = &m->buckets[(h + i) % m->capacity];
        if (!e->key) { e->key = key; e->keylen = keylen; e->val = val; m->used++; return; }
        if (e->key == key && e->keylen == keylen) { e->val = val; return; }  // interned ptr
    }
}
```

(With interned identifiers, `e->key == key` suffices; keep `keylen` for safety.)

## 6.3 Symbol tables

Two workable models:

- **chibicc-style scopes:** a stack of `Scope { HashMap vars; Scope *parent; }`. `find_var`
  walks inner → outer. Each `Var` records `offset` (assigned as encountered), `ty`, and
  `is_local`. This is used by the recursive-descent parser + AST codegen.
- **SubC-style single pass:** one global hash table for globals/functions, plus a scope
  stack of *markers* for locals; locals get frame offsets on first sight and are removed
  when the scope closes. No AST — code is emitted as statements are parsed.

For a single-pass HolyC JIT (`apps/Compiler.HC` already backpatches forward branches per
the README), the SubC model fits: emit directly, keep a **fixup list** for forward
references (function calls, forward jumps, global addresses) and patch them at the end of
the unit.

```c
typedef struct Sym {
    char *name;              // interned
    I64   kind;              // VAR / FUNC / CONST / LABEL
    I64   type;
    I64   offset;            // frame offset or global address
    struct Sym *next;        // hash chain or scope list
} Sym;
```

## 6.4 Direct code emission and backpatching

`boot/seed/jit_arm64.c` / `apps/Compiler.HC` already emit raw ARM64 words. For
single-pass emission you need forward-branch fixups:

```c
// emit a placeholder conditional branch, remember where to patch
I64 fix = code_emit_bcond(cond, 0 /*placeholder offset*/);
...
// later, when the target is known:
code_patch_branch(fix, here);
```

For conditional branches with a **far** target, emit the two-instruction sequence
`B.cond +8 ; B target` (invert the condition and use an unconditional `B` with its 26-bit
range) because `B.cond` has only a 19-bit offset. This is the standard pattern for
compilers targeting A64; the existing CBZ/CBNZ placeholders (README, "Branch
backpatching") are the same idea.

Register allocation for a first-cut JIT: the current design uses a fixed set of scratch
registers (`x0..x7`) and stack temporaries, which is fine for an expression tree emitted
depth-first. chibicc's backend is a stack machine (push/pop), which is the simplest
correct thing; optimize later.

## 6.5 Pitfalls (Topic 6)

1. Per-token `malloc`/`free` and fixed-size string copies — slow and truncating. Use an
   arena + interned strings.
2. FNV-1 vs FNV-1a ordering confusion (see chibicc) — document which you implement.
3. Hash collision handling that probes forever on a full table — rehash at 70%, and keep
   tombstones distinct from empty.
4. Integer overflow in the FNV multiply — use `U64` and rely on modular wraparound
   (defined for unsigned).
5. Forward references in a single-pass compiler — always keep a fixup/backpatch list.
6. `B.cond` range (19-bit) — use the inverted-branch trampoline for far targets.
7. Scope lifetime: locals must be popped on scope exit, or the symbol table grows without
   bound during long REPL sessions.
8. Token numbering drift between the C lexer and the HolyC compiler — the tree already
   guards this with `boot/seed/tok.h` + `scripts/check-token-parity.py`; keep the X-macro
   as the single source of truth and extend it for new tokens.

## 6.6 References (Topic 6)

- rui314/chibicc — https://github.com/rui314/chibicc
- chibicc `hashmap.c` (FNV + open addressing) —
  https://github.com/rui314/chibicc/blob/main/hashmap.c
- Nils M. Holm, *SubC* — https://github.com/jezze/subc
- IETF, *The FNV Non-Cryptographic Hash Algorithm* —
  https://www.ietf.org/archive/id/draft-eastlake-fnv-22.html
- Ben Hoyt, *How to implement a hash table (in C)* —
  https://benhoyt.com/writings/hash-table-in-c/
- Keleshev, *One-pass Compiler Primer* — https://keleshev.com/one-pass-compiler-primer

---

# 7. Suggested build order (tie-back to the roadmap)

1. **§1 + §2 (P4.3 textures):** extend `CRasterSpan` (`RasterTile.HC:107`) with the
   texture descriptor; add `RasterTriangleZTex`; wire `glBindTexture`/`glTexImage2D` state
   into `HolyGLSubmitTriangle` (`HolyGL.HC:258`). Land perspective-correct `u/W,v/W,1/W`
   first with nearest sampling (no filter) to validate interpolation against a checker
   (the exact regression harness already exists in `RasterBootCheck`).
2. **§1.4–1.6:** bilinear + wrap + blend as separate, testable steps.
3. **§3 (P3.x):** replace the SPSC mailbox (`Smp.HC:57-85`) with MPSC per-core inboxes
   (Vyukov), then add a global MPMC queue for the tile rasterizer's job dispatch.
4. **§4 (P2.x FS):** CRC32C table + self-test, then the uberblock-ring commit protocol on
   top of the existing virtio-blk driver (`VirtioBlk.HC`).
5. **§5 (P4.x SDF):** port stb's v2 rasterizer + `GetGlyphSDF` into a single HolyC/C file,
   bake an atlas at boot, composite as textured quads.
6. **§6 (compiler):** arena + intern + FNV hashmap in the seed lexer; move `Compiler.HC`
   symbol table to the same scheme; keep `tok.h` as the parity source of truth.

---

*End of brief.*
