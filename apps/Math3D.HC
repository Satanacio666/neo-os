// NeoOS Sovereign Pure HolyC 3D Math, Matrix & Shader Intrinsic Subsystem (Math3D.HC)
// Vectors, 4x4 Homogeneous Matrices, Perspective Projections, O(1) Trig, and SDF Helpers

F64 PI = 3.14159265358979323846;
F64 TWO_PI = 6.28318530717958647692;
F64 HALF_PI = 1.57079632679489661923;
F64 DEG2RAD = 0.01745329251994329577;
F64 RAD2DEG = 57.2957795130823208768;

class CVec3 {
  F64 x;
  F64 y;
  F64 z;
};

class CVec4 {
  F64 x;
  F64 y;
  F64 z;
  F64 w;
};

class CMat4 {
  F64 m[16];
};

U0 Vec3Set(CVec3 *v, F64 px, F64 py, F64 pz) {
  v->x = px;
  v->y = py;
  v->z = pz;
}

U0 Vec3Add(CVec3 *out, CVec3 *a, CVec3 *b) {
  out->x = a->x + b->x;
  out->y = a->y + b->y;
  out->z = a->z + b->z;
}

U0 Vec3Sub(CVec3 *out, CVec3 *a, CVec3 *b) {
  out->x = a->x - b->x;
  out->y = a->y - b->y;
  out->z = a->z - b->z;
}

U0 Vec3Scale(CVec3 *out, CVec3 *v, F64 s) {
  out->x = v->x * s;
  out->y = v->y * s;
  out->z = v->z * s;
}

F64 Vec3Dot(CVec3 *a, CVec3 *b) {
  return a->x * b->x + a->y * b->y + a->z * b->z;
}

U0 Vec3Cross(CVec3 *out, CVec3 *a, CVec3 *b) {
  F64 rx = a->y * b->z - a->z * b->y;
  F64 ry = a->z * b->x - a->x * b->z;
  F64 rz = a->x * b->y - a->y * b->x;
  out->x = rx;
  out->y = ry;
  out->z = rz;
}

F64 MathSqrt(F64 x) {
  if (x <= 0.0) return 0.0;
  F64 guess = x * 0.5;
  if (guess < 1.0) guess = 1.0;
  I64 ms_iter = 0;
  while (ms_iter < 16) {
    guess = (guess + x / guess) * 0.5;
    ms_iter++;
  }
  return guess;
}

F64 Vec3Length(CVec3 *v) {
  F64 sq = v->x * v->x + v->y * v->y + v->z * v->z;
  return MathSqrt(sq);
}

U0 Vec3Normalize(CVec3 *out, CVec3 *v) {
  F64 len = Vec3Length(v);
  if (len < 0.0000001) {
    out->x = 0.0;
    out->y = 0.0;
    out->z = 0.0;
    return;
  }
  F64 inv = 1.0 / len;
  out->x = v->x * inv;
  out->y = v->y * inv;
  out->z = v->z * inv;
}

// O(1) modular range reduction in radians: x in (-inf, +inf) -> [-1.0, 1.0]
F64 MathSinRad(F64 x) {
  I64 k = (I64)(x / 6.283185307179586);
  x = x - (F64)k * 6.283185307179586;
  if (x < 0.0) x = x + 6.283185307179586;

  F64 sign = 1.0;
  if (x > 3.14159265358979323846) {
    x = x - 3.14159265358979323846;
    sign = -1.0;
  }
  if (x > 1.57079632679489661923) {
    x = 3.14159265358979323846 - x;
  }
  F64 r2 = x * x;
  F64 s = x - (x * r2) / 6.0
            + (x * r2 * r2) / 120.0
            - (x * r2 * r2 * r2) / 5040.0
            + (x * r2 * r2 * r2 * r2) / 362880.0;
  return sign * s;
}

F64 MathCosRad(F64 x) {
  return MathSinRad(x + 1.57079632679489661923);
}

// O(1) modular range reduction for degree-based callers
F64 MathSin(F64 deg) {
  F64 x = deg * 0.01745329251994329577;
  I64 k = (I64)(x / 6.283185307179586);
  x = x - (F64)k * 6.283185307179586;
  if (x < 0.0) x = x + 6.283185307179586;

  F64 sign = 1.0;
  if (x > 3.14159265358979323846) {
    x = x - 3.14159265358979323846;
    sign = -1.0;
  }
  if (x > 1.57079632679489661923) {
    x = 3.14159265358979323846 - x;
  }
  F64 r2 = x * x;
  F64 s = x - (x * r2) / 6.0
            + (x * r2 * r2) / 120.0
            - (x * r2 * r2 * r2) / 5040.0
            + (x * r2 * r2 * r2 * r2) / 362880.0;
  return sign * s;
}

F64 MathCos(F64 deg) {
  return MathSin(deg + 90.0);
}

F64 math3d_sin(F64 deg) {
  return MathSin(deg);
}

F64 math3d_cos(F64 deg) {
  return MathCos(deg);
}

// Fast Fixed-Point (256-scale) & Integer Shader Helpers
// FastSin256: angle256 period = 256 (0..255), output in [-256..256]
I64 FastSin256(I64 angle256) {
  I64 a = angle256 & 255;
  I64 sign = 1;
  if (a >= 128) {
    a = a - 128;
    sign = -1;
  }
  // Parabolic Bhaskara/CORDIC-style curve on [0..128], peak 256 at a=64
  I64 parabola = (a * (128 - a)) >> 4;
  return sign * parabola;
}

I64 FastCos256(I64 angle256) {
  return FastSin256(angle256 + 64);
}

I64 FastSqrtInt(I64 val) {
  if (val <= 0) return 0;
  if (val == 1) return 1;
  I64 x0 = val >> 1;
  if (x0 > 65536) x0 = 65536;
  I64 x1 = (x0 + val / x0) >> 1;
  I64 fsi_iter = 0;
  while (x1 < x0 && fsi_iter < 20) {
    x0 = x1;
    x1 = (x0 + val / x0) >> 1;
    fsi_iter++;
  }
  return x0;
}

I64 SdfCircle256(I64 x, I64 y, I64 r) {
  return FastSqrtInt(x * x + y * y) - r;
}

I64 SdfBox256(I64 x, I64 y, I64 bx, I64 by) {
  I64 ax = (x < 0) ? -x : x;
  I64 ay = (y < 0) ? -y : y;
  I64 dx = ax - bx;
  I64 dy = ay - by;
  I64 ox = (dx > 0) ? dx : 0;
  I64 oy = (dy > 0) ? dy : 0;
  I64 outside = FastSqrtInt(ox * ox + oy * oy);
  I64 max_d = (dx > dy) ? dx : dy;
  I64 inside = (max_d < 0) ? max_d : 0;
  return outside + inside;
}

// Floating-point Shadertoy helpers
F64 FastSinRad(F64 rad) {
  return MathSinRad(rad);
}

F64 FastCosRad(F64 rad) {
  return MathCosRad(rad);
}

F64 Lerp(F64 a, F64 b, F64 t) {
  return a + (b - a) * t;
}

F64 Clamp(F64 val, F64 min_v, F64 max_v) {
  if (val < min_v) return min_v;
  if (val > max_v) return max_v;
  return val;
}

F64 Saturate(F64 val) {
  return Clamp(val, 0.0, 1.0);
}

F64 Smoothstep(F64 e0, F64 e1, F64 x) {
  F64 denom = e1 - e0;
  if (denom > -0.000001 && denom < 0.000001) return 0.0;
  F64 t = Clamp((x - e0) / denom, 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

F64 ShaderFract(F64 x) {
  I64 ix = (I64)x;
  F64 f = x - (F64)ix;
  if (f < 0.0) f = f + 1.0;
  return f;
}

F64 ShaderMix(F64 a, F64 b, F64 t) {
  return a + (b - a) * t;
}

F64 ShaderSmoothstep(F64 e0, F64 e1, F64 x) {
  return Smoothstep(e0, e1, x);
}

F64 SdfSphere(F64 px, F64 py, F64 pz, F64 r) {
  return MathSqrt(px * px + py * py + pz * pz) - r;
}

F64 SdfBox2D(F64 px, F64 py, F64 bx, F64 by) {
  F64 ax = (px < 0.0) ? -px : px;
  F64 ay = (py < 0.0) ? -py : py;
  F64 dx = ax - bx;
  F64 dy = ay - by;
  F64 ox = (dx > 0.0) ? dx : 0.0;
  F64 oy = (dy > 0.0) ? dy : 0.0;
  F64 md = (dx > dy) ? dx : dy;
  F64 inside = (md < 0.0) ? md : 0.0;
  return MathSqrt(ox * ox + oy * oy) + inside;
}

U0 Mat4Identity(CMat4 *out) {
  I64 mi = 0;
  while (mi < 16) {
    out->m[mi] = 0.0;
    mi++;
  }
  out->m[0]  = 1.0;
  out->m[5]  = 1.0;
  out->m[10] = 1.0;
  out->m[15] = 1.0;
}

U0 Mat4Copy(CMat4 *dst, CMat4 *src) {
  I64 mc_i = 0;
  while (mc_i < 16) {
    dst->m[mc_i] = src->m[mc_i];
    mc_i++;
  }
}

U0 Mat4Mul(CMat4 *out, CMat4 *a, CMat4 *b) {
  CMat4 mm_tmp;
  I64 mm_r = 0;
  while (mm_r < 4) {
    I64 mm_c = 0;
    while (mm_c < 4) {
      F64 sum = 0.0;
      I64 mm_k = 0;
      while (mm_k < 4) {
        sum = sum + a->m[mm_r * 4 + mm_k] * b->m[mm_k * 4 + mm_c];
        mm_k++;
      }
      mm_tmp.m[mm_r * 4 + mm_c] = sum;
      mm_c++;
    }
    mm_r++;
  }
  I64 mm_idx = 0;
  while (mm_idx < 16) {
    out->m[mm_idx] = mm_tmp.m[mm_idx];
    mm_idx++;
  }
}

U0 Mat4Translate(CMat4 *out, F64 tx, F64 ty, F64 tz) {
  CMat4 mt_tr;
  Mat4Identity(&mt_tr);
  mt_tr.m[3]  = tx;
  mt_tr.m[7]  = ty;
  mt_tr.m[11] = tz;
  Mat4Mul(out, out, &mt_tr);
}

U0 Mat4Scale(CMat4 *out, F64 sx, F64 sy, F64 sz) {
  CMat4 ms_sc;
  Mat4Identity(&ms_sc);
  ms_sc.m[0]  = sx;
  ms_sc.m[5]  = sy;
  ms_sc.m[10] = sz;
  Mat4Mul(out, out, &ms_sc);
}

U0 Mat4RotateX(CMat4 *out, F64 deg) {
  CMat4 mrx_rot;
  Mat4Identity(&mrx_rot);
  F64 c = MathCos(deg);
  F64 s = MathSin(deg);
  mrx_rot.m[5]  = c;
  mrx_rot.m[6]  = -s;
  mrx_rot.m[9]  = s;
  mrx_rot.m[10] = c;
  Mat4Mul(out, out, &mrx_rot);
}

U0 Mat4RotateY(CMat4 *out, F64 deg) {
  CMat4 mry_rot;
  Mat4Identity(&mry_rot);
  F64 c = MathCos(deg);
  F64 s = MathSin(deg);
  mry_rot.m[0]  = c;
  mry_rot.m[2]  = s;
  mry_rot.m[8]  = -s;
  mry_rot.m[10] = c;
  Mat4Mul(out, out, &mry_rot);
}

U0 Mat4RotateZ(CMat4 *out, F64 deg) {
  CMat4 mrz_rot;
  Mat4Identity(&mrz_rot);
  F64 c = MathCos(deg);
  F64 s = MathSin(deg);
  mrz_rot.m[0] = c;
  mrz_rot.m[1] = -s;
  mrz_rot.m[4] = s;
  mrz_rot.m[5] = c;
  Mat4Mul(out, out, &mrz_rot);
}

// Aliasing-safe 4x4 matrix * Vec4 multiplication using temporaries tx, ty, tz, tw
U0 Mat4MulVec4(CVec4 *out, CMat4 *m, CVec4 *v) {
  F64 tx = m->m[0]  * v->x + m->m[1]  * v->y + m->m[2]  * v->z + m->m[3]  * v->w;
  F64 ty = m->m[4]  * v->x + m->m[5]  * v->y + m->m[6]  * v->z + m->m[7]  * v->w;
  F64 tz = m->m[8]  * v->x + m->m[9]  * v->y + m->m[10] * v->z + m->m[11] * v->w;
  F64 tw = m->m[12] * v->x + m->m[13] * v->y + m->m[14] * v->z + m->m[15] * v->w;
  out->x = tx;
  out->y = ty;
  out->z = tz;
  out->w = tw;
}

U0 Mat4Perspective(CMat4 *out, F64 fov_y_deg, F64 aspect, F64 z_near, F64 z_far) {
  Mat4Identity(out);
  if (aspect > -0.0001 && aspect < 0.0001) aspect = 1.333333;
  F64 dz = z_far - z_near;
  if (dz > -0.0001 && dz < 0.0001) dz = 99.9;
  F64 half_fov = fov_y_deg * 0.5;
  F64 s = MathSin(half_fov);
  F64 c = MathCos(half_fov);
  if (s > -0.0001 && s < 0.0001) s = 0.0001;
  F64 f = c / s;

  out->m[0]  = f / aspect;
  out->m[5]  = f;
  out->m[10] = -(z_far + z_near) / dz;
  out->m[11] = -(2.0 * z_far * z_near) / dz;
  out->m[14] = -1.0;
  out->m[15] = 0.0;
}

U0 Mat4Ortho(CMat4 *out, F64 left, F64 right, F64 bottom, F64 top, F64 near_z, F64 far_z) {
  Mat4Identity(out);
  F64 rl = right - left;
  F64 tb = top - bottom;
  F64 fn = far_z - near_z;
  if (rl == 0.0) rl = 1.0;
  if (tb == 0.0) tb = 1.0;
  if (fn == 0.0) fn = 1.0;
  out->m[0]  = 2.0 / rl;
  out->m[3]  = -(right + left) / rl;
  out->m[5]  = 2.0 / tb;
  out->m[7]  = -(top + bottom) / tb;
  out->m[10] = -2.0 / fn;
  out->m[11] = -(far_z + near_z) / fn;
  out->m[15] = 1.0;
}

I64 Math3DSelfTest() {
  doldoc_printf("\n$FG,CYAN$[MATH3D-TEST] Starting Pure HolyC 3D Math Verification...$FG$\n");

  // Test 1: Vector arithmetic & cross product
  CVec3 m3_v1, m3_v2, m3_cross;
  Vec3Set(&m3_v1, 1.0, 0.0, 0.0);
  Vec3Set(&m3_v2, 0.0, 1.0, 0.0);
  Vec3Cross(&m3_cross, &m3_v1, &m3_v2);
  if (m3_cross.x < -0.001 || m3_cross.x > 0.001 ||
      m3_cross.y < -0.001 || m3_cross.y > 0.001 ||
      m3_cross.z < 0.999  || m3_cross.z > 1.001) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Vector cross product failed!$FG$\n");
    return 0;
  }
  F64 m3_len = Vec3Length(&m3_cross);
  if (m3_len < 0.999 || m3_len > 1.001) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Vector length calculation failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: Vector arithmetic, cross product, and norm verified.$FG$\n");

  // Test 2: Matrix identity, translation & in-place aliasing safety
  CMat4 m_trans;
  Mat4Identity(&m_trans);
  Mat4Translate(&m_trans, 10.0, 20.0, 30.0);

  CVec4 p_in;
  p_in.x = 1.0; p_in.y = 2.0; p_in.z = 3.0; p_in.w = 1.0;
  Mat4MulVec4(&p_in, &m_trans, &p_in);
  if (p_in.x < 10.999 || p_in.x > 11.001 ||
      p_in.y < 21.999 || p_in.y > 22.001 ||
      p_in.z < 32.999 || p_in.z > 33.001 ||
      p_in.w < 0.999  || p_in.w > 1.001) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: In-place Mat4MulVec4 translation failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: 4x4 Homogeneous transformation & in-place aliasing verified.$FG$\n");

  // Test 3: O(1) modular angle reduction & rotation
  CMat4 m_rot;
  Mat4Identity(&m_rot);
  Mat4RotateY(&m_rot, 36090.0); // 100 full turns + 90 deg: X -> -Z
  CVec4 p_out;
  p_in.x = 1.0; p_in.y = 0.0; p_in.z = 0.0; p_in.w = 1.0;
  Mat4MulVec4(&p_out, &m_rot, &p_in);
  if (p_out.x > 0.02 || p_out.x < -0.02 || p_out.z > -0.98 || p_out.z < -1.02) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: RotateY O(1) large-angle transform failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: O(1) modular trigonometric reduction & rotation verified.$FG$\n");

  // Test 4: Perspective projection matrix
  CMat4 m_proj;
  Mat4Perspective(&m_proj, 60.0, 1.333333, 0.1, 100.0);
  if (m_proj.m[14] < -1.001 || m_proj.m[14] > -0.999 || m_proj.m[0] <= 0.0 || m_proj.m[5] <= 0.0) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: Perspective projection matrix failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: 3D Perspective frustum projection matrix verified.$FG$\n");

  // Test 5: Sqrt, Lerp, Smoothstep, FastSin256, FastSqrtInt & SDF helpers
  F64 sqrt_val = MathSqrt(144.0);
  F64 lerp_val = Lerp(10.0, 20.0, 0.5);
  F64 sm_val   = Smoothstep(0.0, 1.0, 0.5);
  I64 fsin_pk  = FastSin256(64);
  I64 isqrt_v  = FastSqrtInt(10000);
  I64 sdf_c    = SdfCircle256(30, 40, 20);
  if (sqrt_val < 11.999 || sqrt_val > 12.001 ||
      lerp_val < 14.999 || lerp_val > 15.001 ||
      sm_val < 0.499   || sm_val > 0.501 ||
      fsin_pk != 256 || isqrt_v != 100 || sdf_c != 30) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Math/SDF utility functions failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: MathSqrt, FastSin256, FastSqrtInt, and SDF primitives verified.$FG$\n");

  doldoc_printf("\n[MATH3D-PASS] ALL 5 MATH3D TESTS PASSED\n\n");
  return 1;
}

if (!g_kernel_booting) {
  Math3DSelfTest();
}
