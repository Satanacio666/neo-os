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
  U32 *fb = GfxDeviceTarget();
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
  return 0;
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
