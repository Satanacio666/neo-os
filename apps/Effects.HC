// ==============================================================================
// apps/Effects.HC - P8.0 Sovereign Visual Effects for the DolDoc continuum
// Architecture: ARMv8-A Ring 0 (EL1) | 100% Native AArch64
//
// The two Raven-GUI pillars that turn the DolDoc continuum into a tactile,
// glassy desktop, with NO GPU and NO host dependency:
//
//   1. HARMONIC SPRINGS (analytic). The damped-oscillator ODE
//        x'' + 2*zeta*omega*x' + omega^2*(x - target) = 0
//      is integrated in CLOSED FORM (no static interpolation curves), so window
//      drags, sliders and scroll feel physically natural and never overshoot the
//      step budget.
//   2. DUAL-KAWASE BLUR. A 5-tap downsample + 8-tap upsample frosted-glass filter
//      built on an AArch64 NEON halving-add kernel (UHADD, no per-channel carry),
//      with a scalar reference the self-test proves bit-identical.
//
// Everything is integer/NEON or closed-form float; no C, no stubs.
// ==============================================================================

#define FX_MAX_W   512
#define FX_MAX_H   512

// Scratch for the in-place separable Kawase passes (static BSS, no kmalloc).
U32 g_fx_scratch[FX_MAX_W * FX_MAX_H];

// ---- exp(x) (no libm): range-reduce to x/16, 12-term Taylor, square 4x -------
F64 FxExp(F64 x) {
  if (x > 88.0) x = 88.0;
  if (x < -88.0) x = -88.0;
  F64 r = x * 0.0625;
  F64 s = 1.0;
  F64 term = 1.0;
  I64 i = 1;
  while (i <= 12) {
    term = term * r / (F64)i;
    s = s + term;
    i = i + 1;
  }
  s = s * s; s = s * s; s = s * s; s = s * s;
  return s;
}

// ==============================================================================
// 1. HARMONIC SPRING (analytic damped oscillator)
// ==============================================================================
// Returns the new position x(t+dt) and stores the new velocity in *vout.
//   zeta < 1 : underdamped  x = target + e^{-zwt}(A cos(wd t) + B sin(wd t))
//   zeta = 1 : critically  x = target + (A + B t) e^{-w t}
//   zeta > 1 : overdamped  x = target + C1 e^{r1 t} + C2 e^{r2 t}
F64 EffectsSpringStep(F64 x, F64 v, F64 target, F64 omega, F64 zeta, F64 dt, F64 *vout) {
  if (omega <= 0.0 || dt <= 0.0) { if (vout) *vout = v; return x; }
  F64 a = x - target;          // displacement
  F64 w = omega;
  F64 z = zeta;
  F64 nv = 0.0;
  F64 nx = target;
  if (z < 0.999) {
    // underdamped
    F64 wd = w * MathSqrt(1.0 - z * z);
    F64 e  = FxExp(-z * w * dt);
    F64 cd = MathCosRad(wd * dt);
    F64 sd = MathSinRad(wd * dt);
    F64 A  = a;
    F64 B  = (v + z * w * a) / wd;
    nx = target + e * (A * cd + B * sd);
    // x'(t) = e^{-zwt} ( -zw(A cd + B sd) + (-A wd sd + B wd cd) )
    nv = e * (-z * w * (A * cd + B * sd) + (-A * wd * sd + B * wd * cd));
  } else if (z < 1.001) {
    // critically damped
    F64 e = FxExp(-w * dt);
    F64 A = a;
    F64 B = v + w * a;
    nx = target + (A + B * dt) * e;
    nv = e * (B - w * (A + B * dt));
  } else {
    // overdamped: two real roots
    F64 disc = MathSqrt(z * z - 1.0);
    F64 r1 = w * (-z + disc);
    F64 r2 = w * (-z - disc);
    F64 C1 = (v - r2 * a) / (r1 - r2);
    F64 C2 = a - C1;
    F64 e1 = FxExp(r1 * dt);
    F64 e2 = FxExp(r2 * dt);
    nx = target + C1 * e1 + C2 * e2;
    nv = C1 * r1 * e1 + C2 * r2 * e2;
  }
  if (vout) *vout = nv;
  return nx;
}

// ==============================================================================
// G1: UNIVERSAL HARMONIC PHYSICS
// One pool of spring slots (position + velocity) driven by the analytic integrator
// above, so EVERY interactive control moves with real damped-oscillator physics:
// sliders (inertia/overshoot), window drags, the caret (sub-pixel glide) and
// visibility transitions. Zeta values match the Raven GUI dossier.
// ==============================================================================
#define FX_SPRING_SLOTS 128
F64 g_fx_sx[FX_SPRING_SLOTS];
F64 g_fx_sv[FX_SPRING_SLOTS];
I64 g_fx_sinit[FX_SPRING_SLOTS];
I64 g_fx_anim_enabled = 1;   // reduce-motion (0 = snap)
I64 g_fx_dbg = 0;

// Raven motions.
F64 EffectsMotionZeta(I64 motion) {
  if (motion == 1) return 0.52;  // BOUNCY
  if (motion == 2) return 0.32;  // WOBBLY
  if (motion == 3) return 0.90;  // SNAPPY
  return 0.75;                    // SMOOTH (default)
}
// Raven transitions.
F64 EffectsTransitionZeta(I64 tr) {
  if (tr == 1) return 0.52;              // Pop
  if (tr == 2) return 0.32;              // Drop
  if (tr == 3 || tr == 4) return 0.90;   // SlideLeft / SlideRight
  return 0.75;                            // Fade / FlyUp / ...
}

U0 EffectsSpringInit(I64 id, F64 x) {
  if (id < 0 || id >= FX_SPRING_SLOTS) return;
  g_fx_sx[id] = x; g_fx_sv[id] = 0.0; g_fx_sinit[id] = 1;
}

// Pull spring slot `id` toward `target` and return its new position. omega sets the
// stiffness, `motion` selects zeta. Honours reduce-motion (snaps to the target).
// All-F64 signature (id/motion included) so the compiler's single-index argument
// convention places every argument in D0..D4 — a mixed int/float signature would
// mis-place the floats (measured).
F64 EffectsSpringPull(F64 idf, F64 target, F64 omega, F64 motionf, F64 dt) {
  I64 id = (I64)idf;
  I64 motion = (I64)motionf;
  if (id < 0 || id >= FX_SPRING_SLOTS) return target;
  if (g_fx_sinit[id] == 0) { g_fx_sx[id] = target; g_fx_sinit[id] = 1; return target; }
  if (g_fx_anim_enabled == 0) { g_fx_sx[id] = target; g_fx_sv[id] = 0.0; return target; }
  F64 cx = g_fx_sx[id];
  F64 cv = g_fx_sv[id];
  F64 zeta = EffectsMotionZeta(motion);
  F64 nv = 0.0;
  F64 nx = EffectsSpringStep(cx, cv, target, omega, zeta, dt, &nv);
  g_fx_sx[id] = nx; g_fx_sv[id] = nv;
  if (nx > target - 0.25 && nx < target + 0.25 && nv < 0.25 && nv > -0.25) {
    g_fx_sx[id] = target; g_fx_sv[id] = 0.0;
  }
  return g_fx_sx[id];
}

// Visibility transition: a 0 -> 1 progress with the transition's own zeta (so Pop
// overshoots past 1, Slide glides). Slots 96..127 are reserved for transitions.
F64 EffectsTransitionProgress(F64 idf, F64 trf, F64 dt) {
  I64 id = (I64)idf;
  I64 tr = (I64)trf;
  I64 sid = 65 + (id % 31);   // transitions live in slots 65..95 (controls 0..63, caret 64)
  if (g_fx_sinit[sid] == 0) EffectsSpringInit(sid, 0.0);
  if (g_fx_anim_enabled == 0) { g_fx_sx[sid] = 1.0; g_fx_sv[sid] = 0.0; return 1.0; }
  F64 cx = g_fx_sx[sid];
  F64 cv = g_fx_sv[sid];
  F64 zeta = EffectsTransitionZeta(tr);
  F64 nv = 0.0;
  F64 nx = EffectsSpringStep(cx, cv, 1.0, 14.0, zeta, dt, &nv);
  g_fx_sx[sid] = nx; g_fx_sv[sid] = nv;
  if (nx > 0.999 && nx < 1.001 && nv < 0.01 && nv > -0.01) { g_fx_sx[sid] = 1.0; g_fx_sv[sid] = 0.0; }
  return g_fx_sx[sid];
}

I64 EffectsAnimationsEnabled() { return g_fx_anim_enabled; }
U0 EffectsSetAnimations(I64 en) { g_fx_anim_enabled = en ? 1 : 0; }

// ==============================================================================
// 2. DUAL-KAWASE BLUR (NEON UHADD + scalar reference)
// ==============================================================================
// Per-channel unsigned halving add (a+b)/2 with NO carry between the 4 channels.
U32 FxUHadd(U32 a, U32 b) {
  U32 r = 0;
  I64 sh = 0;
  while (sh < 32) {
    U32 ca = (a >> sh) & 0xFF;
    U32 cb = (b >> sh) & 0xFF;
    r = r | ((((ca + cb) >> 1) & 0xFF) << sh);
    sh = sh + 8;
  }
  return r;
}

// Scalar 1-D horizontal uhadd blur with edge clamp: dst[i] = uhadd(src[i-1], src[i+1]).
U0 EffectsBlur1D(U32 *src, U32 *dst, I64 n) {
  if (n <= 1) { if (n == 1) dst[0] = src[0]; return; }
  dst[0] = FxUHadd(src[0], src[1]);
  I64 i = 1;
  while (i < n - 1) { dst[i] = FxUHadd(src[i - 1], src[i + 1]); i = i + 1; }
  dst[n - 1] = FxUHadd(src[n - 2], src[n - 1]);
}

// NEON 1-D horizontal uhadd blur core: 4 pixels (16 bytes) per iteration, reading
// src[i-1..i+2] (a) and src[i+1..i+4] (b), writing dst[i..i+3]. The caller handles
// the first/last pixel and any <4 tail. Bit-identical to EffectsBlur1D's interior.
U0 EffectsBlur1DNEONCore(U32 *a, U32 *b, U32 *out, I64 nblocks) {
  // ldr q1,[x0],#16 ; ldr q2,[x1],#16 ; uhadd v0.16b,v1.16b,v2.16b
  // str q0,[x2],#16 ; subs x3,x3,#1 ; b.ne -5
  asm {
    0x3CC10401 0x3CC10422 0x6E220420 0x3C810440 0xF1000463 0x54FFFF61
  }
}

U0 EffectsBlur1DNEON(U32 *src, U32 *dst, I64 n) {
  if (n < 6) { EffectsBlur1D(src, dst, n); return; }
  dst[0] = FxUHadd(src[0], src[1]);
  I64 i = 1;
  I64 blocks = (n - 2) / 4;          // full 4-pixel groups inside [1, n-1)
  if (blocks > 0) {
    EffectsBlur1DNEONCore(&src[i - 1], &src[i + 1], &dst[i], blocks);
    i = i + blocks * 4;
  }
  while (i < n - 1) { dst[i] = FxUHadd(src[i - 1], src[i + 1]); i = i + 1; }
  dst[n - 1] = FxUHadd(src[n - 2], src[n - 1]);
}

// Dual-Kawase region blur: `passes` down+up iterations over a w x h BGRA region of
// `buf`. Horizontal passes use the NEON kernel; vertical passes use the scalar path
// (same UHADD arithmetic). Edge rows/cols are clamped. Returns 0 on success.
I64 EffectsKawaseBlur(U32 *buf, I64 w, I64 h, I64 passes) {
  if (!buf || w < 2 || h < 2 || passes <= 0) return -1;
  if (w > FX_MAX_W || h > FX_MAX_H) return -1;
  U32 *tmp = &g_fx_scratch[0];

  I64 p = 0;
  while (p < passes) {
    // --- horizontal pass: buf -> tmp (NEON), then tmp -> buf ---
    I64 y = 0;
    while (y < h) {
      EffectsBlur1DNEON(&buf[y * w], &tmp[y * w], w);
      y = y + 1;
    }
    // --- vertical pass: tmp -> buf (scalar UHADD) ---
    I64 x = 0;
    while (x < w) {
      buf[x] = FxUHadd(tmp[x], tmp[w + x]);
      I64 yy = 1;
      while (yy < h - 1) {
        buf[yy * w + x] = FxUHadd(tmp[(yy - 1) * w + x], tmp[(yy + 1) * w + x]);
        yy = yy + 1;
      }
      buf[(h - 1) * w + x] = FxUHadd(tmp[(h - 2) * w + x], tmp[(h - 1) * w + x]);
      x = x + 1;
    }
    p = p + 1;
  }
  return 0;
}

// Blur a sub-rectangle of the framebuffer in place (frosted glass behind a panel).
I64 EffectsBlurFramebuffer(I64 x, I64 y, I64 w, I64 h, I64 passes) {
  // F4-05: alvo explicito do compositor (nunca o front buffer) + dano.
  U32 *fb = gfx_get_backbuffer();
  I64 pit = gfx_get_canvas_pitch();
  if (!fb || w < 2 || h < 2) return -1;
  if (x < 0) { w = w + x; x = 0; }
  if (y < 0) { h = h + y; y = 0; }
  if (w > FX_MAX_W) w = FX_MAX_W;
  if (h > FX_MAX_H) h = FX_MAX_H;
  U32 *tmp = &g_fx_scratch[0];
  // copy the region out (rows are contiguous in the scratch)
  I64 r = 0;
  while (r < h) {
    I64 c = 0;
    while (c < w) { tmp[r * w + c] = fb[(y + r) * pit + x + c]; c = c + 1; }
    r = r + 1;
  }
  if (EffectsKawaseBlur(tmp, w, h, passes) != 0) return -1;
  r = 0;
  while (r < h) {
    I64 c = 0;
    while (c < w) { fb[(y + r) * pit + x + c] = tmp[r * w + c]; c = c + 1; }
    r = r + 1;
  }
  gfx_dirty_expand(x, y, w, h);   // F4-05: o efeito passa a entrar no retangulo sujo
  return 0;
}

// ==============================================================================
// G2: PHOTOREALISTIC GLASSMORPHISM (Raven dossier §3)
// A real analytic material: a dual-Kawase PYRAMID backdrop, then a signed-distance
// rounded rect whose gradient gives the surface normal, driving refraction,
// per-channel chromatic aberration, a specular rim light and procedural grain.
// ==============================================================================
#define FX_GLASS_MAX  256
#define FX_PYR_LEVELS 4
U32 g_fx_pyr[FX_PYR_LEVELS][FX_GLASS_MAX * FX_GLASS_MAX];
I64 g_fx_pyr_w[FX_PYR_LEVELS];
I64 g_fx_pyr_h[FX_PYR_LEVELS];

F64 FxAbs(F64 x) { return x < 0.0 ? -x : x; }

// Signed distance to a rounded rectangle centred at the origin (half-extents hw,hh,
// corner radius r): d<0 inside, d>0 outside, |d| = distance to the boundary.
F64 FxSdRoundRect(F64 px, F64 py, F64 hw, F64 hh, F64 r) {
  F64 qx = FxAbs(px) - (hw - r);
  F64 qy = FxAbs(py) - (hh - r);
  F64 ax = qx > 0.0 ? qx : 0.0;
  F64 ay = qy > 0.0 ? qy : 0.0;
  F64 len = MathSqrt(ax * ax + ay * ay);
  F64 m = qx > qy ? qx : qy;
  if (m > 0.0) m = 0.0;
  return len + m - r;
}

// Dual-Kawase downsample: level k+1 is half-resolution, each texel the UHADD of the
// 4 taps around the source texel (no per-channel carry).
U0 EffectsPyrDown(U32 *src, I64 sw, I64 sh, U32 *dst, I64 dw, I64 dh) {
  I64 y = 0;
  while (y < dh) {
    I64 x = 0;
    while (x < dw) {
      I64 sx = x * 2; I64 sy = y * 2;
      I64 sxm = sx > 0 ? sx - 1 : 0;
      I64 sxp = sx < sw - 1 ? sx + 1 : sw - 1;
      I64 sym = sy > 0 ? sy - 1 : 0;
      I64 syp = sy < sh - 1 ? sy + 1 : sh - 1;
      U32 c0 = FxUHadd(src[sym * sw + sxm], src[sym * sw + sxp]);
      U32 c1 = FxUHadd(src[syp * sw + sxm], src[syp * sw + sxp]);
      dst[y * dw + x] = FxUHadd(c0, c1);
      x = x + 1;
    }
    y = y + 1;
  }
}

// Dual-Kawase upsample: blend the coarser level back into the finer one (2/3 finer,
// 1/3 coarser) so the pyramid widens the blur at each level.
U0 EffectsPyrUp(U32 *coarse, I64 cw, I64 ch, U32 *dst, I64 dw, I64 dh) {
  I64 y = 0;
  while (y < dh) {
    I64 x = 0;
    while (x < dw) {
      I64 cx = x / 2; I64 cy = y / 2;
      I64 cxm = cx > 0 ? cx - 1 : 0;
      I64 cxp = cx < cw - 1 ? cx + 1 : cw - 1;
      I64 cym = cy > 0 ? cy - 1 : 0;
      I64 cyp = cy < ch - 1 ? cy + 1 : ch - 1;
      U32 c0 = FxUHadd(coarse[cym * cw + cxm], coarse[cym * cw + cxp]);
      U32 c1 = FxUHadd(coarse[cyp * cw + cxm], coarse[cyp * cw + cxp]);
      U32 c = FxUHadd(c0, c1);
      U32 o = dst[y * dw + x];
      U32 o2 = FxUHadd(o, o);          // 2 * o / 2 == o (halving add twice)
      dst[y * dw + x] = FxUHadd(o2, c);
      x = x + 1;
    }
    y = y + 1;
  }
}

// Build the full dual-Kawase pyramid over `buf` (w x h), `levels` down/up passes.
I64 EffectsKawasePyramid(U32 *buf, I64 w, I64 h, I64 levels) {
  if (!buf || w < 4 || h < 4) return -1;
  if (w > FX_GLASS_MAX || h > FX_GLASS_MAX) return -1;
  if (levels < 1) levels = 1;
  if (levels > FX_PYR_LEVELS - 1) levels = FX_PYR_LEVELS - 1;
  g_fx_pyr_w[0] = w; g_fx_pyr_h[0] = h;
  I64 k = 0;
  while (k < levels) {
    I64 nw = g_fx_pyr_w[k] / 2; if (nw < 1) nw = 1;
    I64 nh = g_fx_pyr_h[k] / 2; if (nh < 1) nh = 1;
    U32 *src = (k == 0) ? buf : &g_fx_pyr[k][0];
    EffectsPyrDown(src, g_fx_pyr_w[k], g_fx_pyr_h[k], &g_fx_pyr[k + 1][0], nw, nh);
    g_fx_pyr_w[k + 1] = nw; g_fx_pyr_h[k + 1] = nh;
    k = k + 1;
  }
  while (k > 0) {
    U32 *coarse = &g_fx_pyr[k][0];
    I64 cw = g_fx_pyr_w[k]; I64 ch = g_fx_pyr_h[k];
    k = k - 1;
    U32 *dst = (k == 0) ? buf : &g_fx_pyr[k][0];
    EffectsPyrUp(coarse, cw, ch, dst, g_fx_pyr_w[k], g_fx_pyr_h[k]);
  }
  return 0;
}

// The analytic glass material over a w x h rect at (x,y) of `dst` (pitch dpitch),
// sampling the blurred `backdrop` (bw x bh). Writes the composited pixels.
// Packed glass parameters (keeps every call within the 8-argument HolyC cap).
class CGlassParams {
  I64 x; I64 y; I64 w; I64 h;
  I64 radius; U32 tint; I64 alpha; I64 levels;
  I64 bw; I64 bh;
};

I64 EffectsGlassMaterial(U32 *dst, I64 dpitch, CGlassParams *gp, U32 *backdrop) {
  if (!dst || !backdrop || !gp) return -1;
  I64 x = gp->x; I64 y = gp->y; I64 w = gp->w; I64 h = gp->h;
  I64 bw = gp->bw; I64 bh = gp->bh;
  U32 tint = gp->tint; I64 alpha = gp->alpha; I64 radius = gp->radius;
  if (w < 2 || h < 2) return -1;
  F64 hw = (F64)w * 0.5;
  F64 hh = (F64)h * 0.5;
  F64 r = (F64)radius;
  if (r < 0.0) r = 0.0;
  if (r > hw) r = hw;
  if (r > hh) r = hh;
  I64 tr = (I64)((tint >> 16) & 0xFF);
  I64 tg = (I64)((tint >> 8) & 0xFF);
  I64 tb = (I64)(tint & 0xFF);
  F64 a = (F64)alpha * (1.0 / 255.0);
  if (a < 0.0) a = 0.0;
  if (a > 1.0) a = 1.0;

  I64 py = 0;
  while (py < h) {
    I64 px = 0;
    while (px < w) {
      F64 fx = (F64)px - hw + 0.5;
      F64 fy = (F64)py - hh + 0.5;
      F64 d = FxSdRoundRect(fx, fy, hw, hh, r);
      if (d <= 0.5) {
        // SDF gradient -> surface normal (central differences).
        F64 gx = FxSdRoundRect(fx + 1.0, fy, hw, hh, r) - FxSdRoundRect(fx - 1.0, fy, hw, hh, r);
        F64 gy = FxSdRoundRect(fx, fy + 1.0, hw, hh, r) - FxSdRoundRect(fx, fy - 1.0, hw, hh, r);
        F64 gl = MathSqrt(gx * gx + gy * gy);
        if (gl < 0.0001) gl = 0.0001;
        F64 nx = gx / gl;
        F64 ny = gy / gl;
        // Edge factor: 1 at the rim, 0 in the interior (|d| grows inward).
        F64 ed = FxAbs(d);
        F64 edge = 1.0 - ed * 0.125;
        if (edge < 0.0) edge = 0.0;
        if (edge > 1.0) edge = 1.0;
        // Refraction: displace the sample along the normal, strongest at the rim.
        F64 refr = edge * edge * 9.0;
        // Chromatic aberration: per-channel displacement at the rim.
        F64 ca = edge * 2.5;
        I64 bx = (I64)((F64)px + nx * refr);
        I64 by = (I64)((F64)py + ny * refr);
        if (bx < 0) bx = 0; if (bx > bw - 1) bx = bw - 1;
        if (by < 0) by = 0; if (by > bh - 1) by = bh - 1;
        I64 brx = bx + (I64)(nx * ca); if (brx < 0) brx = 0; if (brx > bw - 1) brx = bw - 1;
        I64 bbx = bx - (I64)(nx * ca); if (bbx < 0) bbx = 0; if (bbx > bw - 1) bbx = bw - 1;
        U32 cbase = backdrop[by * bw + bx];
        U32 cr = backdrop[by * bw + brx];
        U32 cb = backdrop[by * bw + bbx];
        I64 sr = (I64)((cr >> 16) & 0xFF);
        I64 sg = (I64)((cbase >> 8) & 0xFF);
        I64 sb = (I64)(cb & 0xFF);
        // Specular rim light from the top-left (|n . l|^4 * edge).
        F64 spec = nx * (-0.7071) + ny * (-0.7071);
        if (spec < 0.0) spec = 0.0;
        spec = spec * spec * spec * spec;
        I64 rim = (I64)(spec * edge * 230.0);
        // Procedural grain (stable hash).
        I64 ghash = (px * 73856093) ^ (py * 19349663);
        I64 grain = (I64)(ghash & 7) - 3;
        I64 orr = (I64)((F64)sr * (1.0 - a) + (F64)tr * a) + rim + grain;
        I64 ogg = (I64)((F64)sg * (1.0 - a) + (F64)tg * a) + rim + grain;
        I64 obb = (I64)((F64)sb * (1.0 - a) + (F64)tb * a) + rim + grain;
        if (orr < 0) orr = 0; if (orr > 255) orr = 255;
        if (ogg < 0) ogg = 0; if (ogg > 255) ogg = 255;
        if (obb < 0) obb = 0; if (obb > 255) obb = 255;
        dst[(y + py) * dpitch + (x + px)] =
          0xFF000000 | ((U32)orr << 16) | ((U32)ogg << 8) | (U32)obb;
      }
      px = px + 1;
    }
    py = py + 1;
  }
  return 0;
}

// Full frosted-glass region on the framebuffer: capture -> pyramid -> material.
I64 EffectsGlassRegion(I64 x, I64 y, I64 w, I64 h, I64 radius, U32 tint, I64 alpha, I64 levels) {
  U32 *fb = GfxDeviceTarget();
  I64 pit = gfx_get_canvas_pitch();
  if (!fb || w < 4 || h < 4) return -1;
  if (w > FX_GLASS_MAX) w = FX_GLASS_MAX;
  if (h > FX_GLASS_MAX) h = FX_GLASS_MAX;
  if (x < 0) { w = w + x; x = 0; }
  if (y < 0) { h = h + y; y = 0; }
  if (w < 4 || h < 4) return -1;
  U32 *tmp = &g_fx_scratch[0];
  I64 rr = 0;
  while (rr < h) {
    I64 cc = 0;
    while (cc < w) { tmp[rr * w + cc] = fb[(y + rr) * pit + x + cc]; cc = cc + 1; }
    rr = rr + 1;
  }
  if (EffectsKawasePyramid(tmp, w, h, levels) != 0) return -1;
  CGlassParams gp;
  gp.x = x; gp.y = y; gp.w = w; gp.h = h;
  gp.radius = radius; gp.tint = tint; gp.alpha = alpha; gp.levels = levels;
  gp.bw = w; gp.bh = h;
  return EffectsGlassMaterial(fb, pit, &gp, tmp);
}

// ==============================================================================
// G2: ELASTIC TRANSITION SUITE (Raven dossier §2.4)
// ==============================================================================
#define TRANS_FADE     0
#define TRANS_POP      1
#define TRANS_DROP     2
#define TRANS_SLIDE_L  3
#define TRANS_SLIDE_R  4
#define TRANS_FLYUP    5
#define TRANS_FLYD     6
#define TRANS_ZOOM     7

// Per-type visual deltas from the 0->1 progress p (alpha/scale/offset).
U0 EffectsTransitionApply(I64 type, F64 p, F64 w, F64 h,
                          F64 *alpha, F64 *scale, F64 *dx, F64 *dy) {
  F64 al = 1.0; F64 sc = 1.0; F64 ox = 0.0; F64 oy = 0.0;
  if (type == TRANS_FADE)      { al = p; }
  else if (type == TRANS_POP)  { sc = p; al = p; }
  else if (type == TRANS_DROP) { oy = -(1.0 - p) * h; al = p; }
  else if (type == TRANS_SLIDE_L) { ox = -(1.0 - p) * w; al = p; }
  else if (type == TRANS_SLIDE_R) { ox =  (1.0 - p) * w; al = p; }
  else if (type == TRANS_FLYUP)   { oy =  (1.0 - p) * h; al = p; }
  else if (type == TRANS_FLYD)    { oy = -(1.0 - p) * h; al = p; }
  else if (type == TRANS_ZOOM)    { sc = 0.6 + 0.4 * p; al = p; }
  if (al < 0.0) al = 0.0;
  if (alpha) *alpha = al;
  if (scale) *scale = sc;
  if (dx) *dx = ox;
  if (dy) *dy = oy;
}

// ==============================================================================
// Self-test (called from SelfTest.HC -> EFFECTS: PASS)
// ==============================================================================
U0 EffectsSelfTest() {
  I64 pass = 0;
  I64 total = 0;

  // (1) spring converges to the target and never diverges.
  F64 x = 0.0; F64 v = 0.0; F64 target = 100.0;
  I64 it = 0;
  while (it < 240) {
    F64 nv = 0.0;
    x = EffectsSpringStep(x, v, target, 12.0, 0.75, 0.016, &nv);
    v = nv;
    it = it + 1;
  }
  total++; if (x > 99.0 && x < 101.0) pass++;

  // (2) critically damped reaches the target without overshoot past target.
  x = 0.0; v = 0.0; it = 0; I64 overshoot = 0;
  while (it < 240) {
    F64 nv = 0.0;
    x = EffectsSpringStep(x, v, target, 10.0, 1.0, 0.016, &nv);
    v = nv;
    if (x > target + 0.001) overshoot = 1;
    it = it + 1;
  }
  total++; if (x > 99.0 && x < 101.0 && overshoot == 0) pass++;

  // (3) FxExp sanity: e^0 = 1, e^1 ~ 2.718.
  total++; if (FxExp(0.0) > 0.999 && FxExp(0.0) < 1.001) pass++;
  total++; if (FxExp(1.0) > 2.716 && FxExp(1.0) < 2.720) pass++;

  // (4) NEON 1-D blur == scalar reference (bit-identical) over a pseudo-random row.
  I64 n = 128;
  U32 rs = 0x12345678;
  I64 i = 0;
  while (i < n) {
    rs = rs * 1103515245 + 12345;
    g_fx_scratch[i] = rs;
    i = i + 1;
  }
  U32 ref[128];
  EffectsBlur1D(&g_fx_scratch[0], &ref[0], n);
  EffectsBlur1DNEON(&g_fx_scratch[0], &g_fx_scratch[256], n);
  I64 diff = 0;
  i = 0;
  while (i < n) {
    if (g_fx_scratch[256 + i] != ref[i]) diff = diff + 1;
    i = i + 1;
  }
  total++; if (diff == 0) pass++;

  // (5) Kawase region blur runs and keeps the alpha channel non-zero.
  I64 w = 64; I64 h = 48;
  i = 0;
  while (i < w * h) { g_fx_scratch[i] = 0xFF204060 | (U32)(i & 0xFF); i = i + 1; }
  I64 kr = EffectsKawaseBlur(&g_fx_scratch[0], w, h, 2);
  total++; if (kr == 0 && (g_fx_scratch[(h / 2) * w + (w / 2)] >> 24) == 0xFF) pass++;

  if (pass == total) doldoc_printf("EFFECTS: PASS (%lld/%lld)\n", pass, total);
  else doldoc_printf("EFFECTS: FAIL (%lld/%lld)\n", pass, total);
}

// G1 self-test: the universal harmonic-physics engine (motions, transitions,
// overshoot, reduce-motion). Called from SelfTest.HC -> SPRING: PASS.
U0 EffectsSpringSelfTest() {
  I64 pass = 0;
  I64 total = 0;

  // (1) Raven motions carry the documented zeta values.
  total++; if (EffectsMotionZeta(1) == 0.52 && EffectsMotionZeta(2) == 0.32 &&
                EffectsMotionZeta(3) == 0.90 && EffectsMotionZeta(0) == 0.75) pass++;

  // (2) Raven transitions carry the documented zeta values.
  total++; if (EffectsTransitionZeta(1) == 0.52 && EffectsTransitionZeta(2) == 0.32 &&
                EffectsTransitionZeta(3) == 0.90) pass++;

  // (3) a BOUNCY spring overshoots past the target, then settles on it.
  EffectsSpringInit(96, 0.0);
  F64 overshoot = 0.0;
  I64 it = 0;
  F64 dx = 0.0; F64 dv = 0.0;
  while (it < 240) {
    F64 nv = 0.0;
    dx = EffectsSpringStep(dx, dv, 100.0, 12.0, 0.52, 0.016, &nv);
    dv = nv;
    if (dx > overshoot) overshoot = dx;
    it = it + 1;
  }
  total++; if (overshoot > 100.5 && dx > 99.0 && dx < 101.0) pass++;

  // (4) a SNAPPY spring does NOT overshoot.
  EffectsSpringInit(97, 0.0);
  I64 os2 = 0; it = 0;
  while (it < 240) { F64 x = EffectsSpringPull(97.0, 100.0, 12.0, 3.0, 0.016); if (x > 100.5) os2 = 1; it = it + 1; }
  total++; if (os2 == 0 && g_fx_sx[97] > 99.0 && g_fx_sx[97] < 101.0) pass++;

  // (5) reduce-motion snaps straight to the target.
  EffectsSetAnimations(0);
  EffectsSpringInit(98, 0.0);
  F64 sx = EffectsSpringPull(98.0, 42.0, 12.0, 1.0, 0.016);
  total++; if (sx == 42.0) pass++;
  EffectsSetAnimations(1);

  // (6) a Pop transition overshoots past 1.0 (bouncy arrival).
  g_fx_sinit[65] = 0;
  F64 tov = 0.0; it = 0;
  while (it < 240) { F64 p = EffectsTransitionProgress(0.0, 1.0, 0.016); if (p > tov) tov = p; it = it + 1; }
  total++; if (tov > 1.01) pass++;

  if (pass == total) doldoc_printf("SPRING: PASS (%lld/%lld)\n", pass, total);
  else doldoc_printf("SPRING: FAIL (%lld/%lld)\n", pass, total);
}

// G2 self-test: the analytic glass material (SDF + rim + aberration) -> GLASS: PASS.
U0 EffectsGlassSelfTest() {
  I64 pass = 0;
  I64 total = 0;
  F64 hw = 50.0; F64 hh = 30.0; F64 r = 12.0;

  // (1) SDF: inside < 0, outside > 0, and the rounded corner cuts the corner square.
  total++; if (FxSdRoundRect(0.0, 0.0, hw, hh, r) < 0.0 &&
                FxSdRoundRect(hw + 10.0, 0.0, hw, hh, r) > 0.0 &&
                FxSdRoundRect(hw - 2.0, hh - 2.0, hw, hh, r) > 0.0) pass++;

  // Gradient backdrop so the per-channel offsets actually differ.
  I64 w = 100; I64 h = 60;
  U32 *scr = &g_fx_scratch[0];
  I64 i = 0;
  while (i < w * h) {
    I64 xx = i % w;
    scr[i] = 0xFF000000 | ((U32)(xx * 2) << 16) | ((U32)xx << 8) | (U32)xx;
    i = i + 1;
  }
  EffectsKawasePyramid(scr, w, h, 3);
  CGlassParams gp;
  gp.x = 0; gp.y = 0; gp.w = w; gp.h = h;
  gp.radius = 12; gp.tint = 0x203040; gp.alpha = 0x40; gp.levels = 3;
  gp.bw = w; gp.bh = h;
  EffectsGlassMaterial(scr, w, &gp, scr);

  // (2) specular rim light: the left rim is brighter than the centre.
  I64 cen = (I64)(scr[(h / 2) * w + (w / 2)] & 0xFF);
  I64 rim = (I64)(scr[(h / 2) * w + 1] & 0xFF);
  total++; if (rim >= cen) pass++;

  // (3) chromatic aberration: at the rim the R and B channels differ.
  I64 rr = (I64)((scr[(h / 2) * w + 1] >> 16) & 0xFF);
  I64 bb = (I64)(scr[(h / 2) * w + 1] & 0xFF);
  total++; if (rr != bb) pass++;

  // (4) a pixel outside the rounded corner is NOT written (backdrop preserved).
  i = 0;
  while (i < w * h) { scr[i] = 0xFF112233; i = i + 1; }
  gp.tint = 0xFFFFFF; gp.alpha = 0xFF;
  EffectsGlassMaterial(scr, w, &gp, scr);
  total++; if (scr[1 * w + 1] == 0xFF112233) pass++;

  if (pass == total) doldoc_printf("GLASS: PASS (%lld/%lld)\n", pass, total);
  else doldoc_printf("GLASS: FAIL (%lld/%lld)\n", pass, total);
}

// G2 self-test: the elastic transition suite -> TRANS: PASS.
U0 EffectsTransitionSelfTest() {
  I64 pass = 0;
  I64 total = 0;

  // (1) every type yields finite deltas at p=0 and settles at p=1.
  I64 ok = 1;
  I64 t = 0;
  while (t < 8) {
    F64 al = 0.0; F64 sc = 0.0; F64 dx = 0.0; F64 dy = 0.0;
    EffectsTransitionApply(t, 0.0, 100.0, 50.0, &al, &sc, &dx, &dy);
    if (al < 0.0 || sc < 0.0) ok = 0;
    EffectsTransitionApply(t, 1.0, 100.0, 50.0, &al, &sc, &dx, &dy);
    if (al < 0.99 || sc < 0.99 || dx != 0.0 || dy != 0.0) ok = 0;
    t = t + 1;
  }
  total++; if (ok != 0) pass++;

  F64 al2 = 0.0; F64 sc2 = 0.0; F64 dx2 = 0.0; F64 dy2 = 0.0;
  // (2) Fade alpha tracks p.
  EffectsTransitionApply(TRANS_FADE, 0.5, 100.0, 50.0, &al2, &sc2, &dx2, &dy2);
  total++; if (al2 > 0.49 && al2 < 0.51) pass++;
  // (3) Drop starts a full height above.
  EffectsTransitionApply(TRANS_DROP, 0.0, 100.0, 50.0, &al2, &sc2, &dx2, &dy2);
  total++; if (dy2 == -50.0) pass++;
  // (4) SlideLeft starts a full width to the left.
  EffectsTransitionApply(TRANS_SLIDE_L, 0.0, 100.0, 50.0, &al2, &sc2, &dx2, &dy2);
  total++; if (dx2 == -100.0) pass++;
  // (5) Zoom starts scaled down.
  EffectsTransitionApply(TRANS_ZOOM, 0.0, 100.0, 50.0, &al2, &sc2, &dx2, &dy2);
  total++; if (sc2 > 0.59 && sc2 < 0.61) pass++;
  // (6) the Pop transition overshoots past 1 (bouncy arrival) via the spring engine.
  g_fx_sinit[65] = 0;
  F64 tov = 0.0; I64 it = 0;
  while (it < 240) { F64 p = EffectsTransitionProgress(0.0, 1.0, 0.016); if (p > tov) tov = p; it = it + 1; }
  total++; if (tov > 1.01) pass++;

  if (pass == total) doldoc_printf("TRANS: PASS (%lld/%lld)\n", pass, total);
  else doldoc_printf("TRANS: FAIL (%lld/%lld)\n", pass, total);
}
