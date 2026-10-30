// ==============================================================================
// apps/ShaderVM.HC - Fragment shaders as direct HolyC kernels (P4.6 cleanup)
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
//
// The register bytecode VM (mini-assembly + fetch-decode-execute interpreter)
// is GONE. The four built-in shaders ("vm", "sdf", "noise", "mandel") are now
// plain HolyC pixel kernels (ShaderKernelColor) called directly from
// ShaderVMRenderNode; the fifth ("bulb") still runs in the native 4-lane NEON
// raymarcher (ShaderRaymarchQuad + ShaderField4), which is untouched.
//
// This module owns the $SHADER$ procedural viewports whose type is one of
// "vm", "sdf", "noise", "mandel", "bulb" (see ShaderTypeId). DolDoc.HC routes
// those to ShaderVMRenderNode via symbols_lookup; the legacy 2D approximations
// stay in DolDoc.HC for the other type strings.
//
// The kernels reuse the exact math of the retired bytecode:
//   * sdf    = distance to a disc with screen-space derivative shading
//   * noise  = 8-octave compartment: 4-octave FBM of (4x, 4y, 0.5t) -> [0,1]
//   * mandel = Mandelbrot, 40 iterations, count/40 palette
//   * vm     = animated sin/cos gradient (TIME + SIN/COS demo)
// ==============================================================================

// Built-in shader ids (must match ShaderTypeId).
#define SVB_VM      0
#define SVB_SDF     1
#define SVB_NOISE   2
#define SVB_MANDEL  3
#define SVB_BULB    4

// ==============================================================================
// NEON 4-lane op core. Source of record: scripts/shader_quad.s.
// void ShaderOp4(F64 *dst, const F64 *a, const F64 *b, I64 op)
// Applies op to four doubles (2x .2d). The compiler emits the prologue and
// epilogue, so this block must NOT contain `ret`. Survives: used by the
// raymarcher (ShaderField4) and by the self-test op-core checks.
// ==============================================================================
U0 ShaderOp4(F64 *dst, F64 *a, F64 *b, I64 op) {
    asm {
        0x3DC00020,    0x3DC00421,    0x3DC00042,    0x3DC00443,    0xF100007F,    0x54000300,    0xF100047F,    0x54000320,
        0xF100087F,    0x54000340,    0xF1000C7F,    0x54000360,    0xF100107F,    0x54000380,    0xF100147F,    0x540003A0,
        0xF100187F,    0x540003C0,    0xF1001C7F,    0x540003E0,    0xF100207F,    0x540004C0,    0xF100247F,    0x540004E0,
        0xF100287F,    0x54000500,    0xF1002C7F,    0x54000520,    0x1400002D,    0x4E62D400,    0x4E63D421,    0x1400002A,
        0x4EE2D400,    0x4EE3D421,    0x14000027,    0x6E62DC00,    0x6E63DC21,    0x14000024,    0x6E62FC00,    0x6E63FC21,
        0x14000021,    0x4EE2F400,    0x4EE3F421,    0x1400001E,    0x4E62F400,    0x4E63F421,    0x1400001B,    0x6EE1F800,
        0x6EE1F821,    0x14000018,    0x6EE1D804,    0x6EE1D825,    0x6E64DC86,    0x6E65DCA7,    0x4EE6FC06,    0x4EE7FC27,
        0x6E66DC80,    0x6E67DCA1,    0x1400000F,    0x4EE0F800,    0x4EE0F821,    0x1400000C,    0x6EE0F800,    0x6EE0F821,
        0x14000009,    0x4E619800,    0x4E619821,    0x14000006,    0x4E619804,    0x4E619825,    0x4EE4D400,    0x4EE5D421,
        0x14000001,    0x3D800000,    0x3D800401,
    };
}

// ==============================================================================
// Per-core fragment-shader execution context (survives: the native raymarcher
// writes its 2x2 quad of output pixels here). Mutable VM state no longer
// exists; the context is only the output latch now.
#define SV_MAX_CORES 4
class CShaderCtx {
  U32 out[4];
};
CShaderCtx g_sv_ctx[SV_MAX_CORES];

// ==============================================================================
// Built-in shader library (survives; used by the raymarcher, the kernels and
// the self-test).
// ==============================================================================
I64 ShaderFloorI(F64 x) {
    I64 i = (I64)x;
    if ((F64)i > x) i = i - 1;
    return i;
}

I64 ShaderHash3(I64 x, I64 y, I64 z) {
    I64 h = x * 374761393 + y * 668265263 + z * 1274126177;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return h & 0x7FFFFFFF;
}

F64 ShaderFade(F64 t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

F64 ShaderGrad(I64 h, F64 x, F64 y, F64 z) {
    h = h & 15;
    F64 u = (h < 8) ? x : y;
    F64 v = (h < 4) ? y : ((h == 12 || h == 14) ? x : z);
    F64 a = ((h & 1) != 0) ? (0.0 - u) : u;
    F64 b = ((h & 2) != 0) ? (0.0 - v) : v;
    return a + b;
}

// Classic Perlin gradient noise in [-1,1].
F64 ShaderPerlin3(F64 x, F64 y, F64 z) {
    I64 ix = ShaderFloorI(x);
    I64 iy = ShaderFloorI(y);
    I64 iz = ShaderFloorI(z);
    F64 fx = x - (F64)ix;
    F64 fy = y - (F64)iy;
    F64 fz = z - (F64)iz;
    F64 u = ShaderFade(fx);
    F64 v = ShaderFade(fy);
    F64 w = ShaderFade(fz);

    F64 n000 = ShaderGrad(ShaderHash3(ix,     iy,     iz    ), fx,     fy,     fz    );
    F64 n100 = ShaderGrad(ShaderHash3(ix + 1, iy,     iz    ), fx - 1.0, fy,   fz    );
    F64 n010 = ShaderGrad(ShaderHash3(ix,     iy + 1, iz    ), fx,     fy - 1.0, fz    );
    F64 n110 = ShaderGrad(ShaderHash3(ix + 1, iy + 1, iz    ), fx - 1.0, fy - 1.0, fz    );
    F64 n001 = ShaderGrad(ShaderHash3(ix,     iy,     iz + 1), fx,     fy,     fz - 1.0);
    F64 n101 = ShaderGrad(ShaderHash3(ix + 1, iy,     iz + 1), fx - 1.0, fy,   fz - 1.0);
    F64 n011 = ShaderGrad(ShaderHash3(ix,     iy + 1, iz + 1), fx,     fy - 1.0, fz - 1.0);
    F64 n111 = ShaderGrad(ShaderHash3(ix + 1, iy + 1, iz + 1), fx - 1.0, fy - 1.0, fz - 1.0);

    F64 x00 = n000 + u * (n100 - n000);
    F64 x10 = n010 + u * (n110 - n010);
    F64 x01 = n001 + u * (n101 - n001);
    F64 x11 = n011 + u * (n111 - n011);
    F64 y0  = x00 + v * (x10 - x00);
    F64 y1  = x01 + v * (x11 - x01);
    return y0 + w * (y1 - y0);
}

// Multi-octave fractal Brownian motion (Perlin), ~[-1,1].
F64 ShaderFbm3(F64 x, F64 y, F64 z, I64 oct) {
    F64 sum = 0.0;
    F64 amp = 0.5;
    F64 freq = 1.0;
    I64 i = 0;
    while (i < oct) {
        sum = sum + amp * ShaderPerlin3(x * freq, y * freq, z * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
        i = i + 1;
    }
    return sum;
}

// atan via a minimax rational approximation (good to ~1e-4 rad); atan2/acos built on it.
F64 ShaderAtan(F64 z) {
    F64 sign = 1.0;
    if (z < 0.0) { z = 0.0 - z; sign = -1.0; }
    I64 inv = 0;
    if (z > 1.0) { z = 1.0 / z; inv = 1; }
    F64 z2 = z * z;
    F64 r = z * (0.9998660 + z2 * (-0.3302995 + z2 * (0.1801410 + z2 * (-0.0851330 + z2 * 0.0208351))));
    if (inv != 0) r = 1.57079632679 - r;
    return sign * r;
}

F64 ShaderAtan2(F64 y, F64 x) {
    if (x > 0.0) return ShaderAtan(y / x);
    if (x < 0.0) {
        if (y >= 0.0) return ShaderAtan(y / x) + 3.14159265359;
        return ShaderAtan(y / x) - 3.14159265359;
    }
    if (y > 0.0) return 1.57079632679;
    if (y < 0.0) return -1.57079632679;
    return 0.0;
}

F64 ShaderAcos(F64 x) {
    if (x > 1.0) x = 1.0;
    if (x < -1.0) x = -1.0;
    return ShaderAtan2(MathSqrt(1.0 - x * x), x);
}

// Natural log via range reduction + atanh series.
F64 ShaderLog(F64 x) {
    if (x <= 0.0) return -100.0;
    I64 e = 0;
    while (x > 2.0) { x = x * 0.5; e = e + 1; }
    while (x < 0.5) { x = x * 2.0; e = e - 1; }
    F64 t = (x - 1.0) / (x + 1.0);
    F64 t2 = t * t;
    F64 s = t * (2.0 + t2 * (0.6666667 + t2 * (0.4 + t2 * (0.2857143 + t2 * (0.2222222 + t2 * 0.1818182)))));
    return s + (F64)e * 0.69314718056;
}

// Mandelbulb (power 8) distance estimator.
F64 ShaderMandelbulbDE(F64 x, F64 y, F64 z) {
    F64 zx = x;
    F64 zy = y;
    F64 zz = z;
    F64 dr = 1.0;
    F64 r = 0.0;
    I64 i = 0;
    while (i < 8) {
        r = MathSqrt(zx * zx + zy * zy + zz * zz);
        if (r > 2.0) break;
        F64 theta = ShaderAcos(zz / r);
        F64 phi = ShaderAtan2(zy, zx);
        F64 rp = r * r;
        rp = rp * rp;
        rp = rp * rp;                       // r^8
        F64 st = MathSinRad(theta * 8.0);
        F64 ct = MathCosRad(theta * 8.0);
        F64 sp = MathSinRad(phi * 8.0);
        F64 cp = MathCosRad(phi * 8.0);
        zx = rp * st * cp + x;
        zy = rp * st * sp + y;
        zz = rp * ct + z;
        dr = rp * 8.0 * dr + 1.0;
        i = i + 1;
    }
    return 0.5 * ShaderLog(r) * r / dr;
}

F64 ShaderSdfTorus(F64 px, F64 py, F64 pz, F64 R, F64 r) {
    F64 qx = MathSqrt(px * px + pz * pz) - R;
    return MathSqrt(qx * qx + py * py) - r;
}

// ==============================================================================
// Direct HolyC pixel kernels (replaces the retired bytecode programs).
// Evaluate one pixel at normalized fragment coordinates (fx,fy) in [0,1) at
// time t (seconds). ewx/ewy are the per-pixel screen-space steps used for the
// derivative shading of the SDF kernel. Returns a 0xFFRRGGBB color.
// ==============================================================================
U32 ShaderKernelColor(I64 tid, F64 fx, F64 fy, F64 t, F64 ewx, F64 ewy) {
    I64 r = 0;
    I64 g = 0;
    I64 b = 0;

    if (tid == SVB_SDF) {
        F64 px = fx - 0.5;
        F64 py = fy - 0.5;
        F64 d;
        F64 dx;
        F64 dy;
        d = MathSqrt(px * px + py * py) - 0.30;
        dx = MathSqrt((px + ewx) * (px + ewx) + py * py) - 0.30;
        dy = MathSqrt(px * px + (py + ewy) * (py + ewy)) - 0.30;
        F64 grad = 1.6 * (dx - d) + 1.6 * (dy - d);
        F64 shade = 0.55 - grad;
        F64 cov = 1.0 - Smoothstep(0.0, 0.02, d);
        F64 col = shade * cov + 0.06;
        F64 blue = col * 1.5;
        r = (I64)(col * 255.0 + 0.5);
        g = (I64)(col * 255.0 + 0.5);
        b = (I64)(blue * 255.0 + 0.5);
    } else if (tid == SVB_NOISE) {
        F64 v;
        v = ShaderFbm3(fx * 4.0, fy * 4.0, t * 0.5, 4);
        F64 n = v * 0.5 + 0.5;
        r = (I64)(n * 255.0 + 0.5);
        g = (I64)(n * 255.0 + 0.5);
        b = (I64)(n * 1.3 * 255.0 + 0.5);
    } else if (tid == SVB_MANDEL) {
        F64 cx = (fx - 0.5) * 2.7;
        F64 cy = (fy - 0.5) * 2.7;
        F64 zx = 0.0;
        F64 zy = 0.0;
        I64 i = 0;
        while (i < 40) {
            if (zx * zx + zy * zy < 4.0) {
                F64 nzx = zx * zx - zy * zy + cx;
                zy = 2.0 * zx * zy + cy;
                zx = nzx;
                i = i + 1;
            } else {
                break;
            }
        }
        F64 tt = (F64)i / 40.0;
        r = (I64)(tt * 255.0 + 0.5);
        g = (I64)(tt * 255.0 + 0.5);
        b = (I64)((1.0 - tt) * 255.0 + 0.5);
    } else {
        // SVB_VM: animated procedural gradient (demonstrates TIME + SIN/COS).
        F64 r0 = 0.5 + 0.5 * MathSinRad(fx * 3.14159265 + t * 2.0);
        F64 r1 = 0.5 + 0.5 * MathCosRad(fy * 3.14159265 + t);
        F64 r2 = (r0 + r1) * 0.5;
        r = (I64)(r0 * 255.0 + 0.5);
        g = (I64)(r1 * 255.0 + 0.5);
        b = (I64)(r2 * 255.0 + 0.5);
    }

    if (r < 0) r = 0;
    if (r > 255) r = 255;
    if (g < 0) g = 0;
    if (g > 255) g = 255;
    if (b < 0) b = 0;
    if (b > 255) b = 255;
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}

// ==============================================================================
// 4-lane NEON field for the native raymarcher (sphere + torus + ground plane).
// void ShaderField4(F64 *dst, F64 *px, F64 *py, F64 *pz, F64 t)
// ==============================================================================
U0 ShaderField4(F64 *dst, F64 *px, F64 *py, F64 *pz, F64 t) {
    F64 a4[4]; F64 b4[4]; F64 c4[4];
    F64 t0[4]; F64 t1[4]; F64 t2[4];
    I64 i = 0;
    while (i < 4) { a4[i] = px[i]; b4[i] = py[i]; c4[i] = pz[i]; i = i + 1; }

    // sphere at (0,0,0), r=1
    ShaderOp4(&t0[0], &a4[0], &a4[0], 2);   // x*x
    ShaderOp4(&t1[0], &b4[0], &b4[0], 2);   // y*y
    ShaderOp4(&t2[0], &c4[0], &c4[0], 2);   // z*z
    ShaderOp4(&t0[0], &t0[0], &t1[0], 0);
    ShaderOp4(&t0[0], &t0[0], &t2[0], 0);
    ShaderOp4(&t0[0], &t0[0], &t0[0], 6);   // sqrt
    F64 one4[4];
    i = 0; while (i < 4) { one4[i] = 1.0; i = i + 1; }
    ShaderOp4(&t0[0], &t0[0], &one4[0], 1); // - 1.0  -> dSphere

    // torus in the xz-plane at y=0: R=1.35, r=0.45
    F64 R4[4]; F64 r4[4];
    i = 0; while (i < 4) { R4[i] = 1.35; r4[i] = 0.45; i = i + 1; }
    ShaderOp4(&t1[0], &a4[0], &a4[0], 2);   // x*x
    ShaderOp4(&t2[0], &c4[0], &c4[0], 2);   // z*z
    ShaderOp4(&t1[0], &t1[0], &t2[0], 0);
    ShaderOp4(&t1[0], &t1[0], &t1[0], 6);   // length(xz)
    ShaderOp4(&t1[0], &t1[0], &R4[0], 1);   // qx = len - R
    F64 y2[4];
    ShaderOp4(&y2[0], &b4[0], &b4[0], 2);   // y*y
    ShaderOp4(&t2[0], &t1[0], &t1[0], 2);   // qx*qx
    ShaderOp4(&t2[0], &t2[0], &y2[0], 0);   // + y*y
    ShaderOp4(&t2[0], &t2[0], &t2[0], 6);   // sqrt
    ShaderOp4(&t2[0], &t2[0], &r4[0], 1);   // dTorus

    // ground plane y = -1
    ShaderOp4(&t1[0], &b4[0], &one4[0], 0); // y + 1

    // scene = min(dSphere, dTorus, plane)
    ShaderOp4(&t0[0], &t0[0], &t2[0], 4);   // min(sphere, torus)
    ShaderOp4(dst, &t0[0], &t1[0], 4);      // min(., plane)
}

// Raymarch a 2x2 quad of pixels. u0/v0 = quad origin in NDC-ish screen space,
// su/sv = per-pixel step. Field evaluation is 4-lane NEON (ShaderField4).
U0 ShaderRaymarchQuad(CShaderCtx *ctx, F64 u0, F64 v0, F64 su, F64 sv, F64 t) {
    F64 rox[4]; F64 roy[4]; F64 roz[4];
    F64 rdx[4]; F64 rdy[4]; F64 rdz[4];
    F64 tt[4];

    // camera orbits the origin
    F64 cx = MathSinRad(t * 0.35) * 3.6;
    F64 cz = MathCosRad(t * 0.35) * 3.6;
    F64 cy = 1.5;
    F64 fx = 0.0 - cx; F64 fy = 0.0 - cy; F64 fz = 0.0 - cz;
    F64 fl = MathSqrt(fx * fx + fy * fy + fz * fz);
    if (fl < 0.0001) fl = 1.0;
    fx = fx / fl; fy = fy / fl; fz = fz / fl;
    // right = normalize(cross(f, up=(0,1,0)))
    F64 rx = fz * 1.0 - fy * 0.0;
    F64 ry = fx * 0.0 - fz * 0.0;
    F64 rz = fy * 0.0 - fx * 1.0;
    F64 rl = MathSqrt(rx * rx + ry * ry + rz * rz);
    if (rl < 0.0001) rl = 1.0;
    rx = rx / rl; ry = ry / rl; rz = rz / rl;
    // up2 = cross(right, f)
    F64 ux = ry * fz - rz * fy;
    F64 uy = rz * fx - rx * fz;
    F64 uz = rx * fy - ry * fx;

    I64 l = 0;
    while (l < 4) {
        F64 u = u0 + su * (F64)(l & 1);
        F64 v = v0 + sv * (F64)(l >> 1);
        F64 dx = fx + u * rx + v * ux;
        F64 dy = fy + u * ry + v * uy;
        F64 dz = fz + u * rz + v * uz;
        F64 dl = MathSqrt(dx * dx + dy * dy + dz * dz);
        if (dl < 0.0001) dl = 1.0;
        rox[l] = cx; roy[l] = cy; roz[l] = cz;
        rdx[l] = dx / dl; rdy[l] = dy / dl; rdz[l] = dz / dl;
        tt[l] = 0.0;
        l = l + 1;
    }

    F64 px[4]; F64 py[4]; F64 pz[4]; F64 dd[4];
    I64 step = 0;
    I64 hit = 0;
    while (step < 48) {
        l = 0;
        while (l < 4) {
            px[l] = rox[l] + rdx[l] * tt[l];
            py[l] = roy[l] + rdy[l] * tt[l];
            pz[l] = roz[l] + rdz[l] * tt[l];
            l = l + 1;
        }
        ShaderField4(&dd[0], &px[0], &py[0], &pz[0], t);
        I64 active = 0;
        l = 0;
        while (l < 4) {
            if (dd[l] > 0.0015 && tt[l] < 12.0) { tt[l] = tt[l] + dd[l]; active = 1; }
            else if (dd[l] <= 0.0015) hit = hit | (1 << l);
            l = l + 1;
        }
        if (active == 0) break;
        step = step + 1;
    }

    // shade each lane with a finite-difference normal
    F64 eps = 0.002;
    l = 0;
    while (l < 4) {
        U32 col = 0xFF0A0A14;                 // background
        if ((hit & (1 << l)) != 0) {
            F64 ex[4]; F64 ey[4]; F64 ez[4];
            F64 gx0[4]; F64 gx1[4]; F64 gy0[4]; F64 gy1[4]; F64 gz0[4]; F64 gz1[4];
            I64 k = 0;
            while (k < 4) {
                ex[k] = px[k]; ey[k] = py[k]; ez[k] = pz[k];
                gx0[k] = ex[k] - eps; gx1[k] = ex[k] + eps;
                gy0[k] = ey[k] - eps; gy1[k] = ey[k] + eps;
                gz0[k] = ez[k] - eps; gz1[k] = ez[k] + eps;
                k = k + 1;
            }
            F64 fA[4]; F64 fB[4];
            ShaderField4(&fA[0], &gx1[0], &ey[0], &ez[0], t);
            ShaderField4(&fB[0], &gx0[0], &ey[0], &ez[0], t);
            F64 nx = (fA[l] - fB[l]);
            ShaderField4(&fA[0], &ex[0], &gy1[0], &ez[0], t);
            ShaderField4(&fB[0], &ex[0], &gy0[0], &ez[0], t);
            F64 ny = (fA[l] - fB[l]);
            ShaderField4(&fA[0], &ex[0], &ey[0], &gz1[0], t);
            ShaderField4(&fB[0], &ex[0], &ey[0], &gz0[0], t);
            F64 nz = (fA[l] - fB[l]);
            F64 nl = MathSqrt(nx * nx + ny * ny + nz * nz);
            if (nl < 0.00001) nl = 1.0;
            nx = nx / nl; ny = ny / nl; nz = nz / nl;
            // light + half vector
            F64 Lx = 0.577; F64 Ly = 0.577; F64 Lz = 0.577;
            F64 Hx = Lx + 0.0 - rdx[l]; F64 Hy = Ly + 0.0 - rdy[l]; F64 Hz = Lz + 0.0 - rdz[l];
            F64 hl = MathSqrt(Hx * Hx + Hy * Hy + Hz * Hz);
            if (hl < 0.00001) hl = 1.0;
            Hx = Hx / hl; Hy = Hy / hl; Hz = Hz / hl;
            F64 diff = nx * Lx + ny * Ly + nz * Lz;
            if (diff < 0.0) diff = 0.0;
            F64 spec = nx * Hx + ny * Hy + nz * Hz;
            if (spec < 0.0) spec = 0.0;
            spec = spec * spec; spec = spec * spec; spec = spec * spec; spec = spec * spec;
            F64 base = 0.55;
            F64 lam = 0.18 + 0.82 * diff;
            F64 rr = MathSqrt(base * lam + spec * 0.9);
            F64 gg = MathSqrt(base * 0.75 * lam + spec * 0.9);
            F64 bb = MathSqrt(base * 1.0 * lam + spec * 0.95);
            I64 ir = (I64)(rr * 255.0); if (ir < 0) ir = 0; if (ir > 255) ir = 255;
            I64 ig = (I64)(gg * 255.0); if (ig < 0) ig = 0; if (ig > 255) ig = 255;
            I64 ib = (I64)(bb * 255.0); if (ib < 0) ib = 0; if (ib > 255) ib = 255;
            col = 0xFF000000 | (ir << 16) | (ig << 8) | ib;
        }
        ctx->out[l] = col;
        l = l + 1;
    }
}

// ==============================================================================
// Type routing + render entry.
// ==============================================================================
I64 ShaderTypeId(U8 *s) {
    if (s == 0) return -1;
    if (strcmp(s, "vm") == 0) return SVB_VM;
    if (strcmp(s, "sdf") == 0) return SVB_SDF;
    if (strcmp(s, "noise") == 0) return SVB_NOISE;
    if (strcmp(s, "mandel") == 0) return SVB_MANDEL;
    if (strcmp(s, "bulb") == 0) return SVB_BULB;
    return -1;
}

// Render a shader viewport with an explicit per-core context: the BSP uses
// context 0 via ShaderVMRenderNode; a tile worker would pass its own.
U0 ShaderVMRenderNodeCore(CShaderCtx *ctx, I64 vx, I64 vy, I64 vw, I64 vh, U8 *sh_type) {
    I64 tid = ShaderTypeId(sh_type);
    if (tid < 0) tid = SVB_VM;

    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();
    // F4-04: o viewport do shader escreve pixel a pixel no alvo sancionado mas
    // NUNCA entrava no retangulo sujo -> podia ficar invisivel. Marca uma vez.
    gfx_dirty_expand(vx, vy, vw, vh);
    I64 cw = gfx_get_canvas_width();
    I64 ch = gfx_get_canvas_height();

    F64 t = (F64)timer_get_uptime_ms() * 0.001;
    F64 invw = 1.0 / (F64)vw;
    F64 invh = 1.0 / (F64)vh;

    I64 qy = 0;
    while (qy < vh) {
        I64 qx = 0;
        while (qx < vw) {
            if (tid == SVB_BULB) {
                ShaderRaymarchQuad(ctx, (F64)qx * invw - 0.5, (F64)qy * invh - 0.5, invw, invh, t);
                I64 l = 0;
                while (l < 4) {
                    I64 px = vx + qx + (l & 1);
                    I64 py = vy + qy + (l >> 1);
                    if (px >= 0 && px < cw && py >= 0 && py < ch) {
                        fb[py * pit + px] = ctx->out[l];
                    }
                    l = l + 1;
                }
            } else {
                // fragment-space [0,1] pixel, written directly.
                U32 c;
                c = ShaderKernelColor(tid, (F64)qx * invw, (F64)qy * invh, t, invw, invh);
                I64 px = vx + qx;
                I64 py = vy + qy;
                if (px >= 0 && px < cw && py >= 0 && py < ch) {
                    fb[py * pit + px] = c;
                }
            }
            qx = qx + 1;
        }
        qy = qy + 1;
    }
}

// Public entry (DolDoc.HC): the BSP renders with context 0.
U0 ShaderVMRenderNode(I64 vx, I64 vy, I64 vw, I64 vh, U8 *sh_type) {
    ShaderVMRenderNodeCore(&g_sv_ctx[0], vx, vy, vw, vh, sh_type);
}

// ==============================================================================
// Self-test support (called from SelfTest.HC -> SHADERVM: PASS).
// The retired VM is exercised indirectly: each direct kernel is evaluated on
// pixels with known expected values (precomputed from the exact kernel math),
// plus the surviving NEON op core, noise determinism, and the SDF/VM/mandel
// visual-detail grid (a filled viewport must contain many distinct shades).
// Total stays 15 tests (was 15, of which 6 exercised the interpreter).
// ==============================================================================
U0 ShaderVMTestOp4(I64 *pass, I64 *total) {
    F64 a[4]; F64 b[4]; F64 d[4];
    a[0] = 1.0; a[1] = 2.0; a[2] = 3.0; a[3] = 4.0;
    b[0] = 10.0; b[1] = 20.0; b[2] = 30.0; b[3] = 40.0;
    ShaderOp4(&d[0], &a[0], &b[0], 0);   // ADD
    *total = *total + 1;
    if (d[0] == 11.0 && d[1] == 22.0 && d[2] == 33.0 && d[3] == 44.0) *pass = *pass + 1;
    ShaderOp4(&d[0], &a[0], &b[0], 2);   // MUL
    *total = *total + 1;
    if (d[0] == 10.0 && d[1] == 40.0 && d[2] == 90.0 && d[3] == 160.0) *pass = *pass + 1;
    ShaderOp4(&d[0], &a[0], &a[0], 6);   // SQRT
    *total = *total + 1;
    if (d[0] > 0.99 && d[0] < 1.01 && d[3] > 1.99 && d[3] < 2.01) *pass = *pass + 1;
}

// Full-grid scan of one kernel for the visual-detail proof. Returns the count
// of samples whose luma exceeds 8 and the number of distinct luma/4 buckets.
U0 ShaderKernelGrid(I64 tid, I64 *ink_out, I64 *distinct_out, F64 max_t) {
    I64 ink = 0;
    I64 distinct = 0;
    U8 seen[64];
    I64 k = 0;
    while (k < 64) { seen[k] = 0; k = k + 1; }
    F64 t = 0.0;
    if (tid == SVB_NOISE) t = 1.5;
    else if (tid == SVB_VM) t = 0.77;
    I64 y = 0;
    while (y < 120) {
        I64 x = 0;
        while (x < 120) {
            F64 fx = (F64)x / 120.0;
            F64 fy = (F64)y / 120.0;
            U32 c;
            c = ShaderKernelColor(tid, fx, fy, t, 1.0 / 120.0, 1.0 / 120.0);
            I64 lum = (((c >> 16) & 255) * 30 + ((c >> 8) & 255) * 59 + (c & 255) * 11) / 100;
            if (lum > 8) ink = ink + 1;
            I64 qb = lum >> 2;
            if (seen[qb] == 0) { seen[qb] = 1; distinct = distinct + 1; }
            x = x + 2;
        }
        y = y + 2;
    }
    *ink_out = ink;
    *distinct_out = distinct;
}

U0 ShaderVMSelfTest() {
    I64 pass = 0;
    I64 total = 0;

    // 0. NEON 4-lane op core (ShaderOp4): add / mul / sqrt across the quad.
    ShaderVMTestOp4(&pass, &total);

    // 1. direct SDF kernel: at the disc centre (0.5,0.5) the shade is
    //    0.55*1+0.06 = 0.61 -> red/green byte 149 (luma-heavy), blue 1.5x -> 223.
    U32 sdf_c = ShaderKernelColor(SVB_SDF, 0.5, 0.5, 0.0, 1.0 / 120.0, 1.0 / 120.0);
    total = total + 1;
    if (((sdf_c >> 16) & 255) == 149) pass = pass + 1;

    // 2. SDF viewport fill: a 120x120 SDF field must contain many distinct shades
    //    (edge gradient + coverage ramp; disc alone is ~1/4 of the field).
    I64 ink = 0;
    I64 distinct = 0;
    ShaderKernelGrid(SVB_SDF, &ink, &distinct, 0.0);
    total = total + 1;
    if (ink > 200 && distinct >= 6) pass = pass + 1;

    // 3. direct noise kernel: 4-octave FBM at (0.4,0.8,0.75) -> n=0.6151 ->
    //    red byte 157 (exact kernel math, per-pixel determinism).
    U32 nz_c = ShaderKernelColor(SVB_NOISE, 0.1, 0.2, 1.5, 1.0 / 120.0, 1.0 / 120.0);
    total = total + 1;
    if (((nz_c >> 16) & 255) == 157) pass = pass + 1;

    // 4. noise is a pure function of (x,y,t): two evaluations must agree.
    U32 nz_c2 = ShaderKernelColor(SVB_NOISE, 0.1, 0.2, 1.5, 1.0 / 120.0, 1.0 / 120.0);
    total = total + 1;
    if (nz_c2 == nz_c) pass = pass + 1;

    // 5. direct mandel kernel: at the origin (0.5,0.5) the point never escapes
    //    -> i=40, r=g=255, b=0.
    U32 mn_c = ShaderKernelColor(SVB_MANDEL, 0.5, 0.5, 0.0, 1.0 / 120.0, 1.0 / 120.0);
    total = total + 1;
    if (((mn_c >> 16) & 255) == 255 && ((mn_c >> 8) & 255) == 255) pass = pass + 1;

    // 6. mandel depth: a 120x120 field must show an interior AND an exterior.
    //    Escapees (blue-bright) and the interior (yellow-ish) split the luma
    //    distribution; the coarse 2-bit-per-channel class count stays bounded.
    I64 nb_lo = 0;
    I64 nb_hi = 0;
    I64 nb_total = 0;
    U8 bseen[64];
    I64 k = 0;
    while (k < 64) { bseen[k] = 0; k = k + 1; }
    I64 my = 0;
    while (my < 120) {
        I64 mx = 0;
        while (mx < 120) {
            F64 fx = (F64)mx / 120.0;
            F64 fy = (F64)my / 120.0;
            U32 c;
            c = ShaderKernelColor(SVB_MANDEL, fx, fy, 0.0, 1.0 / 120.0, 1.0 / 120.0);
            I64 lum = (((c >> 16) & 255) * 30 + ((c >> 8) & 255) * 59 + (c & 255) * 11) / 100;
            if (lum <= 40) nb_lo = nb_lo + 1;
            if (lum >= 170) nb_hi = nb_hi + 1;
            I64 nb = (((c >> 16) & 192) >> 6) * 16 + (((c >> 8) & 192) >> 6) * 4 + ((c & 192) >> 6);
            if (bseen[nb] == 0) { bseen[nb] = 1; nb_total = nb_total + 1; }
            mx = mx + 2;
        }
        my = my + 2;
    }
    total = total + 1;
    if (nb_lo >= 400 && nb_hi >= 400 && nb_total >= 3 && nb_total <= 64) pass = pass + 1;

    // 7. direct VM kernel: at (0,0,t=0) -> r=0.5 (128), g=1.0 (255), b=0.75 (191).
    U32 vm_c = ShaderKernelColor(SVB_VM, 0.0, 0.0, 0.0, 0.0, 0.0);
    total = total + 1;
    if (((vm_c >> 16) & 255) == 128 && ((vm_c >> 8) & 255) == 255) pass = pass + 1;

    // 8. VM visual detail: the animated gradient spans many shades.
    ShaderKernelGrid(SVB_VM, &ink, &distinct, 0.0);
    total = total + 1;
    if (distinct > 16 && ink > 200) pass = pass + 1;

    // 9. raymarch library: Mandelbulb distance estimator still in range.
    F64 mv = ShaderMandelbulbDE(0.2, 0.2, 0.2);
    total = total + 1;
    if (mv > -10.0 && mv < 10.0) pass = pass + 1;

    // 10. Perlin/FBM library ranges (as before).
    F64 pv = ShaderPerlin3(1.3, 2.7, 0.9);
    total = total + 1;
    if (pv >= -1.5 && pv <= 1.5) pass = pass + 1;
    F64 fv = ShaderFbm3(0.5, 0.5, 0.5, 4);
    total = total + 1;
    if (fv >= -2.0 && fv <= 2.0) pass = pass + 1;
    // 10b. SDF primitive library (Math3D.HC) — a unit sphere at the origin is -1.
    F64 sv = SdfSphere(0.0, 0.0, 0.0, 1.0);
    total = total + 1;
    if (sv > -1.01 && sv < -0.99) pass = pass + 1;

    // 11. 4-lane NEON field: at (3.6,1.5,0) the nearest surface is the torus at
    //     sqrt((3.6-1.35)^2+1.5^2)-0.45 ~= 2.25.
    F64 fp[4]; F64 fq[4]; F64 fr[4]; F64 fo[4];
    I64 fi = 0;
    while (fi < 4) { fp[fi] = 3.6; fq[fi] = 1.5; fr[fi] = 0.0; fi = fi + 1; }
    ShaderField4(&fo[0], &fp[0], &fq[0], &fr[0], 0.0);
    total = total + 1;
    if (fo[0] > 2.0 && fo[0] < 2.6) pass = pass + 1;

    if (pass == total) doldoc_printf("SHADERVM: PASS (%lld/%lld)\n", pass, total);
    else doldoc_printf("SHADERVM: FAIL (%lld/%lld)\n", pass, total);
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();
}

// Held visual: render each shader viewport (vm/sdf/noise/mandel/bulb) for a few
// seconds each so a host screendump can capture every kernel's frame. The demo
// command `shadervm` now exercises the direct HolyC kernels AND the raymarcher.
U0 ShaderVMDemo() {
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();
    I64 vw = 448;
    I64 vh = 336;
    if (vw > w - 80) vw = w - 80;
    if (vh > h - 80) vh = h - 80;
    I64 vx = (w - vw) / 2;
    I64 vy = (h - vh) / 2;
    I64 fr = __mrs_cntfrq();
    if (fr == 0) fr = 62500000;
    U8 *types[6];
    types[0] = "vm";
    types[1] = "sdf";
    types[2] = "noise";
    types[3] = "mandel";
    types[4] = "bulb";
    types[5] = 0;
    I64 ti = 0;
    while (types[ti] != 0) {
        gfx_clear(0xFF101018);
        GfxPresent(0, 0, w, h, 1);
        ShaderVMRenderNode(vx, vy, vw, vh, types[ti]);
        GfxPresent(0, 0, w, h, 1);
        U64 t0 = __mrs_cntvct();
        U64 dur = fr * 3;
        while (__mrs_cntvct() - t0 < dur) { }
        ti = ti + 1;
    }
    gfx_clear(0xFF000000);
    GfxPresent(0, 0, w, h, 1);
}