// ==============================================================================
// apps/ShaderVM.HC - P4.6 Fragment-Shader VM (2x2 NEON quad)
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
//
// A small register-based bytecode VM evaluated per 2x2 fragment quad:
//   * 16 shader registers, each holding FOUR lanes (SoA 2x2 quad).
//   * Fixed op set; the arithmetic core runs in 128-bit NEON (ShaderOp4,
//     hand-encoded in scripts/shader_quad.s) so one instruction = 4 px.
//   * dFdx/dFdy via lane permutation of the quad; execution masking for
//     branches (if/else/endif) so lanes can diverge without cost.
//   * A built-in library first: value/Perlin noise, multi-octave fBm,
//     Mandelbulb distance estimator, SDF primitives; generic bytecode for
//     custom shaders (ShaderVMAssemble text assembler).
//
// This module owns the $SHADER$ procedural viewports whose type is one of
// "vm", "sdf", "noise", "mandel", "bulb" (see ShaderTypeId). DolDoc.HC routes
// those to ShaderVMRenderNode via symbols_lookup; the legacy 2D approximations
// stay in DolDoc.HC for the other type strings.
// ==============================================================================

// ---- ISA opcodes (the range SV_ADD..SV_FRACT maps to NEON ops SV_ADD-3..) ----
#define SV_END        0
#define SV_MOVI       1
#define SV_MOV        2
#define SV_ADD        3
#define SV_SUB        4
#define SV_MUL        5
#define SV_DIV        6
#define SV_MIN        7
#define SV_MAX        8
#define SV_SQRT       9
#define SV_RSQ       10
#define SV_ABS       11
#define SV_NEG       12
#define SV_FLOOR     13
#define SV_FRACT     14
#define SV_SIN       15
#define SV_COS       16
#define SV_LEN2      17
#define SV_LEN3      18
#define SV_DOT2      19
#define SV_MIX       20
#define SV_CLAMP     21
#define SV_SMOOTH    22
#define SV_FRAGX     23
#define SV_FRAGY     24
#define SV_TIME      25
#define SV_DFDX      26
#define SV_DFDY      27
#define SV_IF        28
#define SV_ELSE      29
#define SV_ENDIF     30
#define SV_JMP       31
#define SV_JNZ       32
#define SV_JZ        33
#define SV_PERLIN    34
#define SV_FBM       35
#define SV_MANDEL    36
#define SV_SDFSPHERE 37
#define SV_SDFBOX    38
#define SV_SDFTORUS  39
#define SV_OUT       40

#define SV_MAX_REGS   16
#define SV_MAX_PROG   4096
#define SV_MAX_CONST  512
#define SV_MAX_STEPS  8192
#define SV_MAX_LABELS 64

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
// epilogue, so this block must NOT contain `ret`.
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
// State
// ==============================================================================
I64 g_sv_prog[SV_MAX_PROG];
I64 g_sv_prog_len;
F64 g_sv_const[SV_MAX_CONST];
I64 g_sv_const_count;

F64 g_sv_regs[SV_MAX_REGS * 4];
I64 g_sv_mask;
I64 g_sv_cond;
I64 g_sv_mask_stack[8];
I64 g_sv_mask_sp;
F64 g_sv_qx;
F64 g_sv_qy;
F64 g_sv_sx;
F64 g_sv_sy;
F64 g_sv_time;
U32 g_sv_out[4];

I64 g_sv_cur_type = -99;

// Render context (globals to respect the 8-argument call cap).
U32 *g_sv_fb;
I64 g_sv_pit;
I64 g_sv_cw;
I64 g_sv_ch;
I64 g_sv_present_band = 0;   // demo: present each 16-row band as it is rendered

// Assembler tables.
U8  g_sv_lbl_names[SV_MAX_LABELS * 16];
I64 g_sv_lbl_pos[SV_MAX_LABELS];
I64 g_sv_lbl_count;
U8  g_sv_ref_names[SV_MAX_LABELS * 16];
I64 g_sv_ref_word[SV_MAX_LABELS];
I64 g_sv_ref_count;
I64 g_sv_asm_err;

// ==============================================================================
// Emitter API (used by the built-in library and available to custom shaders).
// ==============================================================================
U0 ShaderAsmReset() {
    g_sv_prog_len = 0;
    g_sv_const_count = 0;
    g_sv_lbl_count = 0;
    g_sv_ref_count = 0;
    g_sv_asm_err = 0;
}

I64 ShaderAddConst(F64 v) {
    if (g_sv_const_count >= SV_MAX_CONST) return 0;
    g_sv_const[g_sv_const_count] = v;
    g_sv_const_count = g_sv_const_count + 1;
    return g_sv_const_count - 1;
}

U0 ShaderAsm(I64 op, I64 a, I64 b, I64 c) {
    if (g_sv_prog_len + 4 > SV_MAX_PROG) { g_sv_asm_err = 1; return; }
    g_sv_prog[g_sv_prog_len]     = op;
    g_sv_prog[g_sv_prog_len + 1] = a;
    g_sv_prog[g_sv_prog_len + 2] = b;
    g_sv_prog[g_sv_prog_len + 3] = c;
    g_sv_prog_len = g_sv_prog_len + 4;
}

U0 ShaderAsmMovi(I64 a, F64 v) {
    ShaderAsm(SV_MOVI, a, ShaderAddConst(v), 0);
}

// ==============================================================================
// Built-in shader library (native fast paths + VM opcodes).
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
// VM interpreter: evaluate g_sv_prog over a 2x2 quad.
// lane layout: 0=(x,y) 1=(x+sx,y) 2=(x,y+sy) 3=(x+sx,y+sy)
// ==============================================================================
U0 ShaderVMQuad(F64 qx, F64 qy, F64 sx, F64 sy, F64 t) {
    I64 i = 0;
    while (i < SV_MAX_REGS * 4) { g_sv_regs[i] = 0.0; i = i + 1; }
    g_sv_qx = qx;
    g_sv_qy = qy;
    g_sv_sx = sx;
    g_sv_sy = sy;
    g_sv_time = t;
    g_sv_mask = 15;
    g_sv_cond = 15;
    g_sv_mask_sp = 0;
    g_sv_out[0] = 0xFF000000;
    g_sv_out[1] = 0xFF000000;
    g_sv_out[2] = 0xFF000000;
    g_sv_out[3] = 0xFF000000;

    I64 pc = 0;
    I64 steps = 0;
    I64 halted = 0;
    F64 tmp[4];

    while (halted == 0 && steps < SV_MAX_STEPS) {
        I64 op = g_sv_prog[pc];
        I64 a  = g_sv_prog[pc + 1];
        I64 b  = g_sv_prog[pc + 2];
        I64 c  = g_sv_prog[pc + 3];
        pc = pc + 4;
        steps = steps + 1;

        if (op == SV_END) {
            halted = 1;
        } else if (op >= SV_ADD && op <= SV_FRACT) {
            // NEON 4-lane arithmetic core.
            ShaderOp4(&tmp[0], &g_sv_regs[b * 4], &g_sv_regs[c * 4], op - SV_ADD);
            I64 l = 0;
            while (l < 4) { if ((g_sv_mask & (1 << l)) != 0) g_sv_regs[a * 4 + l] = tmp[l]; l = l + 1; }
        } else if (op == SV_MOV) {
            I64 l = 0;
            while (l < 4) { if ((g_sv_mask & (1 << l)) != 0) g_sv_regs[a * 4 + l] = g_sv_regs[b * 4 + l]; l = l + 1; }
        } else if (op == SV_MOVI) {
            F64 v = g_sv_const[b];
            I64 l = 0;
            while (l < 4) { if ((g_sv_mask & (1 << l)) != 0) g_sv_regs[a * 4 + l] = v; l = l + 1; }
        } else if (op == SV_SIN || op == SV_COS) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    F64 x = g_sv_regs[b * 4 + l];
                    if (op == SV_SIN) g_sv_regs[a * 4 + l] = MathSinRad(x);
                    else g_sv_regs[a * 4 + l] = MathCosRad(x);
                }
                l = l + 1;
            }
        } else if (op == SV_LEN2 || op == SV_LEN3) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    F64 x = g_sv_regs[b * 4 + l];
                    F64 y = g_sv_regs[(b + 1) * 4 + l];
                    F64 s = x * x + y * y;
                    if (op == SV_LEN3) { F64 z = g_sv_regs[(b + 2) * 4 + l]; s = s + z * z; }
                    g_sv_regs[a * 4 + l] = MathSqrt(s);
                }
                l = l + 1;
            }
        } else if (op == SV_DOT2) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    F64 ax = g_sv_regs[b * 4 + l];
                    F64 ay = g_sv_regs[(b + 1) * 4 + l];
                    F64 bx = g_sv_regs[c * 4 + l];
                    F64 by = g_sv_regs[(c + 1) * 4 + l];
                    g_sv_regs[a * 4 + l] = ax * bx + ay * by;
                }
                l = l + 1;
            }
        } else if (op == SV_MIX) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    F64 t0 = g_sv_regs[c * 4 + l];
                    F64 p0 = g_sv_regs[a * 4 + l];
                    F64 p1 = g_sv_regs[b * 4 + l];
                    g_sv_regs[a * 4 + l] = p0 + (p1 - p0) * t0;
                }
                l = l + 1;
            }
        } else if (op == SV_CLAMP) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    F64 v = g_sv_regs[a * 4 + l];
                    F64 lo = g_sv_regs[b * 4 + l];
                    F64 hi = g_sv_regs[c * 4 + l];
                    if (v < lo) v = lo;
                    if (v > hi) v = hi;
                    g_sv_regs[a * 4 + l] = v;
                }
                l = l + 1;
            }
        } else if (op == SV_SMOOTH) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    F64 x = g_sv_regs[a * 4 + l];
                    F64 e0 = g_sv_regs[b * 4 + l];
                    F64 e1 = g_sv_regs[c * 4 + l];
                    g_sv_regs[a * 4 + l] = Smoothstep(e0, e1, x);
                }
                l = l + 1;
            }
        } else if (op == SV_FRAGX || op == SV_FRAGY || op == SV_TIME) {
            I64 l = 0;
            while (l < 4) {
                F64 v = g_sv_time;
                if (op == SV_FRAGX) v = g_sv_qx + g_sv_sx * (F64)(l & 1);
                else if (op == SV_FRAGY) v = g_sv_qy + g_sv_sy * (F64)(l >> 1);
                if ((g_sv_mask & (1 << l)) != 0) g_sv_regs[a * 4 + l] = v;
                l = l + 1;
            }
        } else if (op == SV_DFDX || op == SV_DFDY) {
            F64 v0 = g_sv_regs[b * 4 + 0];
            F64 v1 = g_sv_regs[b * 4 + 1];
            F64 v2 = g_sv_regs[b * 4 + 2];
            F64 v3 = g_sv_regs[b * 4 + 3];
            F64 d0 = 0.0;
            F64 d1 = 0.0;
            F64 d2 = 0.0;
            F64 d3 = 0.0;
            if (op == SV_DFDX) { d0 = v1 - v0; d1 = v1 - v0; d2 = v3 - v2; d3 = v3 - v2; }
            else               { d0 = v2 - v0; d1 = v3 - v1; d2 = v2 - v0; d3 = v3 - v1; }
            I64 l = 0;
            while (l < 4) {
                F64 d = d0;
                if (l == 1) d = d1;
                else if (l == 2) d = d2;
                else if (l == 3) d = d3;
                if ((g_sv_mask & (1 << l)) != 0) g_sv_regs[a * 4 + l] = d;
                l = l + 1;
            }
        } else if (op == SV_IF) {
            I64 cond = 0;
            I64 l = 0;
            while (l < 4) { if (g_sv_regs[a * 4 + l] > 0.0) cond = cond | (1 << l); l = l + 1; }
            if (g_sv_mask_sp < 7) {
                g_sv_mask_stack[g_sv_mask_sp] = g_sv_mask;
                g_sv_mask_sp = g_sv_mask_sp + 1;
            }
            g_sv_cond = cond;
            g_sv_mask = g_sv_mask & cond;
        } else if (op == SV_ELSE) {
            I64 saved = 15;
            if (g_sv_mask_sp > 0) saved = g_sv_mask_stack[g_sv_mask_sp - 1];
            g_sv_mask = saved & (~g_sv_cond) & 15;
        } else if (op == SV_ENDIF) {
            if (g_sv_mask_sp > 0) {
                g_sv_mask_sp = g_sv_mask_sp - 1;
                g_sv_mask = g_sv_mask_stack[g_sv_mask_sp];
            } else {
                g_sv_mask = 15;
            }
        } else if (op == SV_JMP) {
            pc = a * 4;
        } else if (op == SV_JNZ || op == SV_JZ) {
            I64 nz = 0;
            I64 l = 0;
            while (l < 4) { if (g_sv_regs[a * 4 + l] != 0.0) nz = 1; l = l + 1; }
            if ((op == SV_JNZ && nz != 0) || (op == SV_JZ && nz == 0)) pc = b * 4;
        } else if (op == SV_PERLIN) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    g_sv_regs[a * 4 + l] = ShaderPerlin3(g_sv_regs[b * 4 + l], g_sv_regs[(b + 1) * 4 + l], g_sv_regs[(b + 2) * 4 + l]);
                }
                l = l + 1;
            }
        } else if (op == SV_FBM) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    I64 oct = (I64)g_sv_regs[c * 4 + l];
                    g_sv_regs[a * 4 + l] = ShaderFbm3(g_sv_regs[b * 4 + l], g_sv_regs[(b + 1) * 4 + l], g_sv_regs[(b + 2) * 4 + l], oct);
                }
                l = l + 1;
            }
        } else if (op == SV_MANDEL) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    g_sv_regs[a * 4 + l] = ShaderMandelbulbDE(g_sv_regs[b * 4 + l], g_sv_regs[(b + 1) * 4 + l], g_sv_regs[(b + 2) * 4 + l]);
                }
                l = l + 1;
            }
        } else if (op == SV_SDFSPHERE) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    g_sv_regs[a * 4 + l] = SdfSphere(g_sv_regs[b * 4 + l], g_sv_regs[(b + 1) * 4 + l], g_sv_regs[(b + 2) * 4 + l], g_sv_regs[c * 4 + l]);
                }
                l = l + 1;
            }
        } else if (op == SV_SDFBOX) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    g_sv_regs[a * 4 + l] = SdfBox2D(g_sv_regs[b * 4 + l], g_sv_regs[(b + 1) * 4 + l], g_sv_regs[c * 4 + l], g_sv_regs[(c + 1) * 4 + l]);
                }
                l = l + 1;
            }
        } else if (op == SV_SDFTORUS) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    g_sv_regs[a * 4 + l] = ShaderSdfTorus(g_sv_regs[b * 4 + l], g_sv_regs[(b + 1) * 4 + l], g_sv_regs[(b + 2) * 4 + l], g_sv_regs[c * 4 + l], g_sv_regs[(c + 1) * 4 + l]);
                }
                l = l + 1;
            }
        } else if (op == SV_OUT) {
            I64 l = 0;
            while (l < 4) {
                if ((g_sv_mask & (1 << l)) != 0) {
                    I64 r = (I64)(g_sv_regs[a * 4 + l] * 255.0 + 0.5);
                    I64 g = (I64)(g_sv_regs[b * 4 + l] * 255.0 + 0.5);
                    I64 bl = (I64)(g_sv_regs[c * 4 + l] * 255.0 + 0.5);
                    if (r < 0) r = 0; if (r > 255) r = 255;
                    if (g < 0) g = 0; if (g > 255) g = 255;
                    if (bl < 0) bl = 0; if (bl > 255) bl = 255;
                    g_sv_out[l] = 0xFF000000 | (r << 16) | (g << 8) | bl;
                }
                l = l + 1;
            }
        }
    }
}

// ==============================================================================
// Text assembler: "mnemonic a, b, c" lines; "name:" labels; // comments.
// All operands are registers (rN) except movi's immediate and jump labels.
// ==============================================================================
U0 ShaderCopyTok(U8 *dst, U8 *src, I64 n) {
    I64 i = 0;
    while (i < n && i < 15) { dst[i] = src[i]; i = i + 1; }
    dst[i] = 0;
}

F64 ShaderAtof(U8 *s) {
    I64 i = 0;
    F64 sign = 1.0;
    if (s[0] == '-') { sign = -1.0; i = 1; }
    else if (s[0] == '+') { i = 1; }
    F64 ip = 0.0;
    while (s[i] >= '0' && s[i] <= '9') { ip = ip * 10.0 + (F64)(s[i] - '0'); i = i + 1; }
    F64 fp = 0.0;
    F64 scale = 0.1;
    if (s[i] == '.') {
        i = i + 1;
        while (s[i] >= '0' && s[i] <= '9') { fp = fp + (F64)(s[i] - '0') * scale; scale = scale * 0.1; i = i + 1; }
    }
    return sign * (ip + fp);
}

I64 ShaderMnemonic(U8 *s) {
    if (strcmp(s, "end") == 0) return SV_END;
    if (strcmp(s, "movi") == 0) return SV_MOVI;
    if (strcmp(s, "mov") == 0) return SV_MOV;
    if (strcmp(s, "add") == 0) return SV_ADD;
    if (strcmp(s, "sub") == 0) return SV_SUB;
    if (strcmp(s, "mul") == 0) return SV_MUL;
    if (strcmp(s, "div") == 0) return SV_DIV;
    if (strcmp(s, "min") == 0) return SV_MIN;
    if (strcmp(s, "max") == 0) return SV_MAX;
    if (strcmp(s, "sqrt") == 0) return SV_SQRT;
    if (strcmp(s, "rsq") == 0) return SV_RSQ;
    if (strcmp(s, "abs") == 0) return SV_ABS;
    if (strcmp(s, "neg") == 0) return SV_NEG;
    if (strcmp(s, "floor") == 0) return SV_FLOOR;
    if (strcmp(s, "fract") == 0) return SV_FRACT;
    if (strcmp(s, "sin") == 0) return SV_SIN;
    if (strcmp(s, "cos") == 0) return SV_COS;
    if (strcmp(s, "len2") == 0) return SV_LEN2;
    if (strcmp(s, "len3") == 0) return SV_LEN3;
    if (strcmp(s, "dot2") == 0) return SV_DOT2;
    if (strcmp(s, "mix") == 0) return SV_MIX;
    if (strcmp(s, "clamp") == 0) return SV_CLAMP;
    if (strcmp(s, "smooth") == 0) return SV_SMOOTH;
    if (strcmp(s, "fragx") == 0) return SV_FRAGX;
    if (strcmp(s, "fragy") == 0) return SV_FRAGY;
    if (strcmp(s, "time") == 0) return SV_TIME;
    if (strcmp(s, "dfdx") == 0) return SV_DFDX;
    if (strcmp(s, "dfdy") == 0) return SV_DFDY;
    if (strcmp(s, "if") == 0) return SV_IF;
    if (strcmp(s, "else") == 0) return SV_ELSE;
    if (strcmp(s, "endif") == 0) return SV_ENDIF;
    if (strcmp(s, "jmp") == 0) return SV_JMP;
    if (strcmp(s, "jnz") == 0) return SV_JNZ;
    if (strcmp(s, "jz") == 0) return SV_JZ;
    if (strcmp(s, "perlin") == 0) return SV_PERLIN;
    if (strcmp(s, "fbm") == 0) return SV_FBM;
    if (strcmp(s, "mandel") == 0) return SV_MANDEL;
    if (strcmp(s, "sdfsphere") == 0) return SV_SDFSPHERE;
    if (strcmp(s, "sdfbox") == 0) return SV_SDFBOX;
    if (strcmp(s, "sdftorus") == 0) return SV_SDFTORUS;
    if (strcmp(s, "out") == 0) return SV_OUT;
    return -1;
}

// Register operand "rN" -> N, else -1.
I64 ShaderRegTok(U8 *s) {
    if (s[0] != 'r') return -1;
    I64 v = 0;
    I64 i = 1;
    if (s[i] < '0' || s[i] > '9') return -1;
    while (s[i] >= '0' && s[i] <= '9') { v = v * 10 + (s[i] - '0'); i = i + 1; }
    if (s[i] != 0) return -1;
    if (v >= SV_MAX_REGS) return -1;
    return v;
}

I64 ShaderFindLabel(U8 *name) {
    I64 i = 0;
    while (i < g_sv_lbl_count) {
        if (strcmp(g_sv_lbl_names + i * 16, name) == 0) return g_sv_lbl_pos[i];
        i = i + 1;
    }
    return -1;
}

// Assemble into g_sv_prog. Returns word count or -1.
I64 ShaderVMAssemble(U8 *src) {
    ShaderAsmReset();
    I64 p = 0;
    while (src[p] != 0) {
        // one line
        I64 ls = p;
        while (src[p] != 0 && src[p] != 10) p = p + 1;
        I64 le = p;
        if (src[p] == 10) p = p + 1;

        // strip // comment
        I64 q = ls;
        I64 ce = le;
        while (q + 1 < le) {
            if (src[q] == '/' && src[q + 1] == '/') { ce = q; break; }
            q = q + 1;
        }

        // skip leading spaces
        while (ls < ce && (src[ls] == ' ' || src[ls] == 9 || src[ls] == 13)) ls = ls + 1;
        if (ls >= ce) continue;

        // label? "name:" at line start
        I64 k = ls;
        while (k < ce && src[k] != ' ' && src[k] != 9 && src[k] != ',') k = k + 1;
        if (k > ls && src[k - 1] == ':') {
            if (g_sv_lbl_count < SV_MAX_LABELS) {
                ShaderCopyTok(g_sv_lbl_names + g_sv_lbl_count * 16, src + ls, k - ls - 1);
                g_sv_lbl_pos[g_sv_lbl_count] = g_sv_prog_len / 4;
                g_sv_lbl_count = g_sv_lbl_count + 1;
            }
            continue;
        }

        // mnemonic
        U8 mtok[16];
        ShaderCopyTok(mtok, src + ls, k - ls);
        I64 op = ShaderMnemonic(mtok);
        if (op < 0) { g_sv_asm_err = 1; return -1; }

        // operands: up to 3, into a flat 3x16 token buffer
        U8  otok[48];
        I64 nops = 0;
        I64 r = k;
        while (nops < 3) {
            while (r < ce && (src[r] == ' ' || src[r] == 9 || src[r] == ',')) r = r + 1;
            if (r >= ce) break;
            I64 os = r;
            while (r < ce && src[r] != ' ' && src[r] != 9 && src[r] != ',') r = r + 1;
            ShaderCopyTok(otok + nops * 16, src + os, r - os);
            nops = nops + 1;
        }

        I64 ia = (nops > 0) ? ShaderRegTok(otok) : 0;
        I64 ib = (nops > 1) ? ShaderRegTok(otok + 16) : 0;
        I64 ic = (nops > 2) ? ShaderRegTok(otok + 32) : 0;

        if (op == SV_MOVI) {
            if (ia < 0) { g_sv_asm_err = 1; return -1; }
            ShaderAsm(SV_MOVI, ia, ShaderAddConst(ShaderAtof(otok + 16)), 0);
        } else if (op == SV_JMP) {
            if (g_sv_ref_count < SV_MAX_LABELS) {
                ShaderCopyTok(g_sv_ref_names + g_sv_ref_count * 16, otok, 15);
                g_sv_ref_word[g_sv_ref_count] = g_sv_prog_len + 1;   // operand a
                g_sv_ref_count = g_sv_ref_count + 1;
            }
            ShaderAsm(SV_JMP, 0, 0, 0);
        } else if (op == SV_JNZ || op == SV_JZ) {
            if (ia < 0) { g_sv_asm_err = 1; return -1; }
            if (g_sv_ref_count < SV_MAX_LABELS) {
                ShaderCopyTok(g_sv_ref_names + g_sv_ref_count * 16, otok + 16, 15);
                g_sv_ref_word[g_sv_ref_count] = g_sv_prog_len + 2;   // operand b
                g_sv_ref_count = g_sv_ref_count + 1;
            }
            ShaderAsm(op, ia, 0, 0);
        } else if (op == SV_IF || op == SV_ELSE || op == SV_ENDIF) {
            ShaderAsm(op, ia, 0, 0);
        } else if (op == SV_FRAGX || op == SV_FRAGY || op == SV_TIME || op == SV_OUT) {
            ShaderAsm(op, ia, ib, ic);
        } else {
            // default: registers a,b,c (unary ops leave b/c as 0)
            ShaderAsm(op, ia, ib, ic);
        }
    }

    // resolve label references
    I64 j = 0;
    while (j < g_sv_ref_count) {
        I64 tgt = ShaderFindLabel(g_sv_ref_names + j * 16);
        if (tgt < 0) { g_sv_asm_err = 1; return -1; }
        g_sv_prog[g_sv_ref_word[j]] = tgt;
        j = j + 1;
    }
    return g_sv_prog_len / 4;
}

// ==============================================================================
// Built-in shader programs (emitted bytecode).
// ==============================================================================
U0 ShaderVMBuildProgram(I64 tid) {
    ShaderAsmReset();

    if (tid == SVB_SDF) {
        // 2D signed-distance disc, shaded with screen-space derivatives.
        ShaderAsm(SV_FRAGX, 0, 0, 0);
        ShaderAsm(SV_FRAGY, 1, 0, 0);
        ShaderAsmMovi(2, 0.5);
        ShaderAsm(SV_SUB, 0, 0, 2);
        ShaderAsm(SV_SUB, 1, 1, 2);
        ShaderAsm(SV_MOV, 3, 0, 0);
        ShaderAsm(SV_MOV, 4, 1, 0);
        ShaderAsm(SV_LEN2, 5, 3, 0);
        ShaderAsmMovi(6, 0.30);
        ShaderAsm(SV_SUB, 5, 5, 6);            // d = length(p) - R
        ShaderAsm(SV_DFDX, 7, 5, 0);           // ddx
        ShaderAsm(SV_DFDY, 8, 5, 0);           // ddy
        ShaderAsmMovi(9, 1.6);
        ShaderAsm(SV_MUL, 7, 7, 9);
        ShaderAsm(SV_MUL, 8, 8, 9);
        ShaderAsm(SV_ADD, 7, 7, 8);
        ShaderAsmMovi(9, 0.55);
        ShaderAsm(SV_SUB, 7, 9, 7);            // shade = 0.55 - grad
        ShaderAsm(SV_MOV, 10, 5, 0);
        ShaderAsmMovi(11, 0.0);
        ShaderAsmMovi(12, 0.02);
        ShaderAsm(SV_SMOOTH, 10, 11, 12);      // smoothstep(0, 0.02, d)
        ShaderAsmMovi(13, 1.0);
        ShaderAsm(SV_SUB, 10, 13, 10);         // coverage = 1 - that
        ShaderAsm(SV_MUL, 7, 7, 10);           // shade * coverage
        ShaderAsmMovi(13, 0.06);
        ShaderAsm(SV_ADD, 7, 7, 13);           // + ambient
        ShaderAsm(SV_MOV, 14, 7, 0);
        ShaderAsmMovi(15, 1.5);
        ShaderAsm(SV_MUL, 14, 14, 15);         // blue-tinted
        ShaderAsm(SV_OUT, 7, 7, 14);
    } else if (tid == SVB_NOISE) {
        ShaderAsm(SV_FRAGX, 0, 0, 0);
        ShaderAsm(SV_FRAGY, 1, 0, 0);
        ShaderAsm(SV_TIME, 2, 0, 0);
        ShaderAsmMovi(3, 4.0);
        ShaderAsm(SV_MUL, 0, 0, 3);
        ShaderAsm(SV_MUL, 1, 1, 3);
        ShaderAsmMovi(4, 0.5);
        ShaderAsm(SV_MUL, 2, 2, 4);
        ShaderAsmMovi(5, 4.0);
        ShaderAsm(SV_FBM, 6, 0, 5);
        ShaderAsmMovi(7, 0.5);
        ShaderAsm(SV_MUL, 6, 6, 7);
        ShaderAsm(SV_ADD, 6, 6, 7);            // [0,1]
        ShaderAsm(SV_MOV, 8, 6, 0);
        ShaderAsmMovi(9, 1.3);
        ShaderAsm(SV_MUL, 8, 8, 9);
        ShaderAsm(SV_OUT, 6, 6, 8);
    } else if (tid == SVB_MANDEL) {
        // 2D Mandelbrot with an execution-masked loop (lanes escape independently).
        ShaderAsm(SV_FRAGX, 0, 0, 0);
        ShaderAsm(SV_FRAGY, 1, 0, 0);
        ShaderAsmMovi(2, 0.5);
        ShaderAsm(SV_SUB, 0, 0, 2);
        ShaderAsm(SV_SUB, 1, 1, 2);
        ShaderAsmMovi(2, 2.7);
        ShaderAsm(SV_MUL, 0, 0, 2);            // cx
        ShaderAsm(SV_MUL, 1, 1, 2);            // cy
        ShaderAsmMovi(3, 0.0);                 // zx
        ShaderAsmMovi(4, 0.0);                 // zy
        ShaderAsmMovi(5, 0.0);                 // i
        ShaderAsmMovi(7, 40.0);                // countdown
        I64 head = g_sv_prog_len / 4;          // loop head word index
        ShaderAsm(SV_MOV, 8, 3, 0);
        ShaderAsm(SV_MUL, 8, 8, 8);
        ShaderAsm(SV_MOV, 9, 4, 0);
        ShaderAsm(SV_MUL, 9, 9, 9);
        ShaderAsm(SV_ADD, 8, 8, 9);            // |z|^2
        ShaderAsmMovi(10, 4.0);
        ShaderAsm(SV_SUB, 8, 10, 8);           // 4 - |z|^2  (>0 while inside)
        ShaderAsm(SV_IF, 8, 0, 0);
        ShaderAsm(SV_MOV, 11, 3, 0);
        ShaderAsm(SV_MUL, 11, 11, 3);          // zx*zx
        ShaderAsm(SV_MOV, 12, 4, 0);
        ShaderAsm(SV_MUL, 12, 12, 4);          // zy*zy
        ShaderAsm(SV_SUB, 13, 11, 12);
        ShaderAsm(SV_ADD, 13, 13, 0);          // nzx
        ShaderAsm(SV_MUL, 14, 3, 4);           // zx*zy
        ShaderAsmMovi(15, 2.0);
        ShaderAsm(SV_MUL, 14, 14, 15);
        ShaderAsm(SV_ADD, 14, 14, 1);          // nzy
        ShaderAsm(SV_MOV, 3, 13, 0);
        ShaderAsm(SV_MOV, 4, 14, 0);
        ShaderAsmMovi(15, 1.0);
        ShaderAsm(SV_ADD, 5, 5, 15);           // i++
        ShaderAsm(SV_ENDIF, 0, 0, 0);
        ShaderAsmMovi(15, 1.0);
        ShaderAsm(SV_SUB, 7, 7, 15);
        ShaderAsm(SV_JNZ, 7, head, 0);         // back-edge to the loop head
        ShaderAsmMovi(15, 40.0);
        ShaderAsm(SV_DIV, 5, 5, 15);           // t = i/40
        ShaderAsmMovi(15, 1.0);
        ShaderAsm(SV_SUB, 15, 15, 5);          // 1-t
        ShaderAsm(SV_OUT, 5, 5, 15);
    } else {
        // SVB_VM: animated procedural gradient (demonstrates TIME + SIN/COS).
        ShaderAsm(SV_FRAGX, 0, 0, 0);
        ShaderAsmMovi(1, 3.14159265);
        ShaderAsm(SV_MUL, 0, 0, 1);
        ShaderAsm(SV_TIME, 2, 0, 0);
        ShaderAsmMovi(3, 2.0);
        ShaderAsm(SV_MUL, 2, 2, 3);
        ShaderAsm(SV_ADD, 0, 0, 2);
        ShaderAsm(SV_SIN, 0, 0, 0);
        ShaderAsm(SV_FRAGY, 1, 0, 0);
        ShaderAsmMovi(4, 3.14159265);
        ShaderAsm(SV_MUL, 1, 1, 4);
        ShaderAsm(SV_TIME, 2, 0, 0);
        ShaderAsm(SV_ADD, 1, 1, 2);
        ShaderAsm(SV_COS, 1, 1, 0);
        ShaderAsmMovi(5, 0.5);
        ShaderAsm(SV_MUL, 0, 0, 5);
        ShaderAsm(SV_ADD, 0, 0, 5);
        ShaderAsm(SV_MUL, 1, 1, 5);
        ShaderAsm(SV_ADD, 1, 1, 5);
        ShaderAsm(SV_MOV, 2, 0, 0);
        ShaderAsm(SV_ADD, 2, 2, 1);
        ShaderAsm(SV_MUL, 2, 2, 5);
        ShaderAsm(SV_OUT, 0, 1, 2);
    }

    ShaderAsm(SV_END, 0, 0, 0);
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
U0 ShaderRaymarchQuad(F64 u0, F64 v0, F64 su, F64 sv, F64 t) {
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
        g_sv_out[l] = col;
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

U0 ShaderVMRenderNode(I64 vx, I64 vy, I64 vw, I64 vh, U8 *sh_type) {
    I64 tid = ShaderTypeId(sh_type);
    if (tid < 0) tid = SVB_VM;
    if (tid != g_sv_cur_type) {
        ShaderVMBuildProgram(tid);
        g_sv_cur_type = tid;
    }

    g_sv_fb = RenderGetTargetBuffer();
    g_sv_pit = gfx_get_canvas_pitch();
    g_sv_cw = gfx_get_canvas_width();
    g_sv_ch = gfx_get_canvas_height();

    F64 t = (F64)timer_get_uptime_ms() * 0.001;
    F64 invw = 1.0 / (F64)vw;
    F64 invh = 1.0 / (F64)vh;

    I64 qy = 0;
    while (qy < vh - 1) {
        if (g_sv_present_band != 0 && (qy & 15) == 0) {
            GfxPresent(vx, vy + qy, vw, 16, 0);
        }
        I64 qx = 0;
        while (qx < vw - 1) {
            F64 u0 = (F64)qx * invw - 0.5;
            F64 v0 = (F64)qy * invh - 0.5;
            if (tid == SVB_BULB) {
                ShaderRaymarchQuad(u0, v0, invw, invh, t);
            } else {
                // fragment-space [0,1] quad
                F64 fx = (F64)qx * invw;
                F64 fy = (F64)qy * invh;
                ShaderVMQuad(fx, fy, invw, invh, t);
            }
            I64 l = 0;
            while (l < 4) {
                I64 px = vx + qx + (l & 1);
                I64 py = vy + qy + (l >> 1);
                if (px >= 0 && px < g_sv_cw && py >= 0 && py < g_sv_ch) {
                    g_sv_fb[py * g_sv_pit + px] = g_sv_out[l];
                }
                l = l + 1;
            }
            qx = qx + 2;
        }
        qy = qy + 2;
    }
}

// ==============================================================================
// Self-test support (called from SelfTest.HC -> SHADERVM: PASS).
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

// Evaluate a one-pixel program and return lane 0's red channel.
I64 ShaderVMEvalR(U8 *src, F64 qx, F64 qy, F64 sx, F64 sy) {
    I64 n = ShaderVMAssemble(src);
    if (n <= 0) return -1;
    ShaderVMQuad(qx, qy, sx, sy, 0.0);
    return (I64)((g_sv_out[0] >> 16) & 255);
}

U0 ShaderVMSelfTest() {
    I64 pass = 0;
    I64 total = 0;

    // 0. NEON 4-lane op core (ShaderOp4): add / mul / sqrt across the quad.
    ShaderVMTestOp4(&pass, &total);

    // 1. arithmetic through the VM: r = (x + y) * 0.0625 at (2,4) -> red 96.
    I64 r1 = ShaderVMEvalR("fragx r0\nfragy r1\nadd r0, r0, r1\nmovi r1, 0.0625\nmul r0, r0, r1\nout r0, r0, r0\nend\n", 2.0, 4.0, 0.0, 0.0);
    total = total + 1;
    if (r1 == 96) pass = pass + 1;

    // 2. screen-space derivatives: dFdx(fragx) is the per-pixel step. With step
    //    0.5, dFdx = 0.5 -> red byte 128.
    I64 r2 = ShaderVMEvalR("fragx r0\ndfdx r1, r0\nout r1, r1, r1\nend\n", 0.0, 0.0, 0.5, 0.5);
    total = total + 1;
    if (r2 == 128) pass = pass + 1;

    // 3. execution masking: if (fragx > 0.5) red else blue; lane 0 at x=0 is
    //    masked out of the "then" branch (blue), at x=1 it takes it (red).
    I64 r3 = ShaderVMEvalR("fragx r0\nmovi r1, 0.5\nsub r0, r0, r1\nmovi r2, 0.0\nmovi r3, 1.0\nif r0\nout r3, r2, r2\nelse\nout r2, r2, r3\nendif\nend\n", 0.0, 0.0, 1.0, 1.0);
    total = total + 1;
    if (r3 == 0) pass = pass + 1;
    I64 r3b = ShaderVMEvalR("fragx r0\nmovi r1, 0.5\nsub r0, r0, r1\nmovi r2, 0.0\nmovi r3, 1.0\nif r0\nout r3, r2, r2\nelse\nout r2, r2, r3\nendif\nend\n", 1.0, 0.0, 1.0, 1.0);
    total = total + 1;
    if (r3b == 255) pass = pass + 1;

    // 4. built-in library ranges.
    F64 pv = ShaderPerlin3(1.3, 2.7, 0.9);
    total = total + 1;
    if (pv >= -1.5 && pv <= 1.5) pass = pass + 1;
    F64 fv = ShaderFbm3(0.5, 0.5, 0.5, 4);
    total = total + 1;
    if (fv >= -2.0 && fv <= 2.0) pass = pass + 1;
    F64 mv = ShaderMandelbulbDE(0.2, 0.2, 0.2);
    total = total + 1;
    if (mv > -10.0 && mv < 10.0) pass = pass + 1;
    F64 sv = SdfSphere(0.0, 0.0, 0.0, 1.0);
    total = total + 1;
    if (sv > -1.01 && sv < -0.99) pass = pass + 1;

    // 5. assembler: a loop counts down and outputs a constant.
    I64 r5 = ShaderVMEvalR("movi r0, 1.0\nmovi r1, 8.0\nloop:\nsub r1, r1, r0\njnz r1, loop\nout r0, r0, r0\nend\n", 0.0, 0.0, 1.0, 1.0);
    total = total + 1;
    if (r5 == 255) pass = pass + 1;

    // 5b. 4-lane NEON field: at (3.6,1.5,0) the nearest surface is the torus at
    //     sqrt((3.6-1.35)^2+1.5^2)-0.45 ~= 2.25.
    F64 fp[4]; F64 fq[4]; F64 fr[4]; F64 fo[4];
    I64 fi = 0;
    while (fi < 4) { fp[fi] = 3.6; fq[fi] = 1.5; fr[fi] = 0.0; fi = fi + 1; }
    ShaderField4(&fo[0], &fp[0], &fq[0], &fr[0], 0.0);
    total = total + 1;
    if (fo[0] > 2.0 && fo[0] < 2.6) pass = pass + 1;

    // 6. real render: an SDF viewport must fill with many distinct shades.
    g_sv_cur_type = -99;
    ShaderVMBuildProgram(SVB_SDF);
    I64 ink = 0;
    I64 distinct = 0;
    U8 seen[64];
    I64 k = 0;
    while (k < 64) { seen[k] = 0; k = k + 1; }
    I64 y = 0;
    while (y < 120) {
        I64 x = 0;
        while (x < 120) {
            F64 fx = (F64)x / 120.0;
            F64 fy = (F64)y / 120.0;
            ShaderVMQuad(fx, fy, 1.0 / 120.0, 1.0 / 120.0, 0.0);
            U32 c0 = g_sv_out[0];
            I64 lum = (((c0 >> 16) & 255) * 30 + ((c0 >> 8) & 255) * 59 + (c0 & 255) * 11) / 100;
            if (lum > 8) ink = ink + 1;
            I64 qb = lum >> 2;
            if (seen[qb] == 0) { seen[qb] = 1; distinct = distinct + 1; }
            x = x + 2;
        }
        y = y + 2;
    }
    total = total + 1;
    if (ink > 200 && distinct >= 6) pass = pass + 1;

    g_sv_cur_type = -99;
    if (pass == total) doldoc_printf("SHADERVM: PASS (%lld/%lld)\n", pass, total);
    else doldoc_printf("SHADERVM: FAIL (%lld/%lld)\n", pass, total);
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();
}

// Held visual: render the raymarched SDF showcase for ~8 s for a host screendump.
I64 g_shadervm_demo_keep = 0;

U0 ShaderVMDemo() {
    g_shadervm_demo_keep = 1;
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();
    I64 vw = 448;
    I64 vh = 336;
    if (vw > w - 80) vw = w - 80;
    if (vh > h - 80) vh = h - 80;
    I64 vx = (w - vw) / 2;
    I64 vy = (h - vh) / 2;
    gfx_clear(0xFF101018);
    GfxPresent(0, 0, w, h, 1);
    // Render the raymarched SDF scene, presenting each band as it completes so
    // the frame appears progressively (the field eval is 4-lane NEON but the
    // per-lane ray march is the bottleneck).
    g_sv_present_band = 1;
    ShaderVMRenderNode(vx, vy, vw, vh, "bulb");
    g_sv_present_band = 0;
    GfxPresent(0, 0, w, h, 1);
    U64 t0 = __mrs_cntvct();
    U64 fr = __mrs_cntfrq();
    if (fr == 0) fr = 62500000;
    U64 dur = fr * 8;
    while (__mrs_cntvct() - t0 < dur) { }
    g_shadervm_demo_keep = 0;
    gfx_clear(0xFF000000);
    GfxPresent(0, 0, w, h, 1);
}
