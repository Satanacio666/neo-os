// ==============================================================================
// GrMath.HC - Authentic 3D Transformation Math & Hardware Vector Intrinsics
// Adapted from TempleOS Adam/Gr/GrMath.HC & AthenaEnv Math Intrinsics
// Architecture: ARMv8-A Ring 0 | Pure HolyC Native Execution
// ==============================================================================

#define PI 3.14159265358979323846

// 4x4 Transformation Matrix in Row-Major Order
class Mat4x4 {
    F64 m[16];
};

// 3D Vector
class Vec3 {
    F64 x, y, z;
};

// 4D Homogeneous Vector
class Vec4 {
    F64 x, y, z, w;
};

// Identity Matrix Initialization
U0 Mat4x4Identity(Mat4x4 *out) {
    I64 i;
    for (i = 0; i < 16; i++) {
        out->m[i] = (i % 5 == 0) ? 1.0 : 0.0;
    }
}

// Copy 4x4 Matrix: dst = src
U0 Mat4x4Copy(Mat4x4 *dst, Mat4x4 *src) {
    I64 i;
    for (i = 0; i < 16; i++) {
        dst->m[i] = src->m[i];
    }
}

// 4x4 Matrix Multiplication: out = a * b
U0 Mat4x4Mul(Mat4x4 *out, Mat4x4 *a, Mat4x4 *b) {
    Mat4x4 temp;
    I64 r, c, k;
    for (r = 0; r < 4; r++) {
        for (c = 0; c < 4; c++) {
            F64 sum = 0.0;
            for (k = 0; k < 4; k++) {
                sum = sum + a->m[r * 4 + k] * b->m[k * 4 + c];
            }
            temp.m[r * 4 + c] = sum;
        }
    }
    for (r = 0; r < 16; r++) {
        out->m[r] = temp.m[r];
    }
}

// Translation Matrix: out = Translate(tx, ty, tz) * out
U0 Mat4x4Translate(Mat4x4 *out, F64 tx, F64 ty, F64 tz) {
    Mat4x4 tr;
    Mat4x4Identity(&tr);
    tr.m[3]  = tx;
    tr.m[7]  = ty;
    tr.m[11] = tz;
    Mat4x4Mul(out, &tr, out);
}

// Scale Matrix: out = Scale(sx, sy, sz) * out
U0 Mat4x4Scale(Mat4x4 *out, F64 sx, F64 sy, F64 sz) {
    Mat4x4 sc;
    Mat4x4Identity(&sc);
    sc.m[0]  = sx;
    sc.m[5]  = sy;
    sc.m[10] = sz;
    Mat4x4Mul(out, &sc, out);
}

// Rotation Matrix about X-axis (angle in degrees)
U0 Mat4x4RotateX(Mat4x4 *out, F64 angle_deg) {
    Mat4x4 rot;
    Mat4x4Identity(&rot);
    F64 c = math3d_cos(angle_deg);
    F64 s = math3d_sin(angle_deg);
    rot.m[5]  = c;
    rot.m[6]  = -s;
    rot.m[9]  = s;
    rot.m[10] = c;
    Mat4x4Mul(out, &rot, out);
}

// Rotation Matrix about Y-axis (angle in degrees)
U0 Mat4x4RotateY(Mat4x4 *out, F64 angle_deg) {
    Mat4x4 rot;
    Mat4x4Identity(&rot);
    F64 c = math3d_cos(angle_deg);
    F64 s = math3d_sin(angle_deg);
    rot.m[0]  = c;
    rot.m[2]  = s;
    rot.m[8]  = -s;
    rot.m[10] = c;
    Mat4x4Mul(out, &rot, out);
}

// Rotation Matrix about Z-axis (angle in degrees)
U0 Mat4x4RotateZ(Mat4x4 *out, F64 angle_deg) {
    Mat4x4 rot;
    Mat4x4Identity(&rot);
    F64 c = math3d_cos(angle_deg);
    F64 s = math3d_sin(angle_deg);
    rot.m[0] = c;
    rot.m[1] = -s;
    rot.m[4] = s;
    rot.m[5] = c;
    Mat4x4Mul(out, &rot, out);
}

// Perspective Projection Matrix (fov_y in degrees)
U0 Mat4x4Perspective(Mat4x4 *out, F64 fov_y_deg, F64 aspect, F64 z_near, F64 z_far) {
    Mat4x4Identity(out);
    F64 half_fov = fov_y_deg * 0.5;
    F64 s = math3d_sin(half_fov);
    F64 c = math3d_cos(half_fov);
    F64 tan_half = 1.0;
    if (s > 0.0001) {
        tan_half = s / c;
    }
    F64 f = 1.0 / tan_half;

    out->m[0]  = f / aspect;
    out->m[5]  = f;
    out->m[10] = -(z_far + z_near) / (z_far - z_near);
    out->m[11] = -(2.0 * z_far * z_near) / (z_far - z_near);
    out->m[14] = -1.0;
    out->m[15] = 0.0;
}

// Orthographic Projection Matrix
U0 Mat4x4Ortho(Mat4x4 *out, F64 left, F64 right, F64 bottom, F64 top, F64 near, F64 far) {
    Mat4x4Identity(out);
    out->m[0]  = 2.0 / (right - left);
    out->m[3]  = -(right + left) / (right - left);
    out->m[5]  = 2.0 / (top - bottom);
    out->m[7]  = -(top + bottom) / (top - bottom);
    out->m[10] = -2.0 / (far - near);
    out->m[11] = -(far + near) / (far - near);
    out->m[15] = 1.0;
}

// Vector Transformation: out = mat * (x, y, z, w)
U0 Mat4x4Transform(Mat4x4 *mat, F64 x, F64 y, F64 z, F64 w, F64 *out_vec) {
    out_vec[0] = mat->m[0] * x + mat->m[1] * y + mat->m[2] * z  + mat->m[3] * w;
    out_vec[1] = mat->m[4] * x + mat->m[5] * y + mat->m[6] * z  + mat->m[7] * w;
    out_vec[2] = mat->m[8] * x + mat->m[9] * y + mat->m[10] * z + mat->m[11] * w;
    out_vec[3] = mat->m[12]* x + mat->m[13]* y + mat->m[14]* z + mat->m[15]* w;
}

// ------------------------------------------------------------------------------
// AthenaEnv-Inspired Math Intrinsics
// ------------------------------------------------------------------------------
F64 Clamp(F64 v, F64 min_val, F64 max_val) {
    if (v < min_val) return min_val;
    if (v > max_val) return max_val;
    return v;
}

F64 Lerp(F64 a, F64 b, F64 t) {
    return a + (b - a) * t;
}

F64 Saturate(F64 v) {
    return Clamp(v, 0.0, 1.0);
}

F64 Smoothstep(F64 edge0, F64 edge1, F64 x) {
    F64 t = Saturate((x - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}
