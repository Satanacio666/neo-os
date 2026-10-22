// ==============================================================================
// apps/Mesh.HC - P4.7 Mesh ingestion: streaming Wavefront OBJ parser + renderer
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
//
// A streaming OBJ parser (`v`/`vn`/`vt`/`f`), handling:
//   * negative (relative) face indices  (f -5//6 -1//6 ...),
//   * `v/vt/vn`, `v//vn`, `v/vt`, `v` corner forms,
//   * n-gon fan triangulation (quads -> 2 tris, ...),
//   * `#`, `o`, `g`, `s`, `mtllib`, `usemtl`, `l`, `p` ignored.
// Faces without normals get a computed face normal so the mesh is always lit.
//
// Rendering goes through the ONE pipeline: HolyGL immediate mode ->
// HolyGLSubmitTriangle -> RasterTriangleZ (P4.5 per-fragment Blinn-Phong when
// GL_LIGHTING is on). No separate rasterizer path.
//
// Memory is fixed-capacity globals (no kmalloc sites) to keep the .HC->C census
// neutral. The default mesh is the embedded unit cube so `$SP,type="mesh"`
// works with no file; `obj <file>` loads one from RedSea.
// ==============================================================================

#define MESH_MAX_V  2048
#define MESH_MAX_N  2048
#define MESH_MAX_UV 2048
#define MESH_MAX_T  4096
#define MESH_MAX_CORNERS 32

class CMesh {
    I64 vcount;
    F64 vx[MESH_MAX_V];
    F64 vy[MESH_MAX_V];
    F64 vz[MESH_MAX_V];
    I64 ncount;
    F64 nx[MESH_MAX_N];
    F64 ny[MESH_MAX_N];
    F64 nz[MESH_MAX_N];
    I64 uvcount;
    F64 uu[MESH_MAX_UV];
    F64 uv[MESH_MAX_UV];
    I64 fcount;                     // triangle count
    I64 fv[MESH_MAX_T * 3];         // position index per corner
    I64 fni[MESH_MAX_T * 3];        // normal index per corner (-1 = none)
    I64 ft[MESH_MAX_T * 3];         // texcoord index per corner (-1 = none)
};
CMesh g_mesh;

// Embedded unit cube (6 quads -> 12 triangles). The top face uses NEGATIVE
// (relative) indices so the parser's relative-index path is exercised.
U8 *g_mesh_cube_obj = "v -1 -1 -1\nv 1 -1 -1\nv 1 1 -1\nv -1 1 -1\nv -1 -1 1\nv 1 -1 1\nv 1 1 1\nv -1 1 1\nvn 0 0 -1\nvn 0 0 1\nvn -1 0 0\nvn 1 0 0\nvn 0 -1 0\nvn 0 1 0\nf 1//1 4//1 3//1 2//1\nf 5//2 6//2 7//2 8//2\nf 1//3 5//3 8//3 4//3\nf 2//4 3//4 7//4 6//4\nf 1//5 2//5 6//5 5//5\nf -5//6 -1//6 -2//6 -6//6\n";

// ==============================================================================
// Token / number helpers (no strtod/atof in the runtime).
// ==============================================================================
I64 MeshIsWS(U8 c) {
    if (c == ' ' || c == 9 || c == 13) return 1;
    return 0;
}

I64 MeshAtoiTok(U8 *s) {
    I64 i = 0;
    I64 sign = 1;
    if (s[0] == '-') { sign = -1; i = 1; }
    else if (s[0] == '+') { i = 1; }
    I64 v = 0;
    while (s[i] >= '0' && s[i] <= '9') { v = v * 10 + (s[i] - '0'); i = i + 1; }
    return sign * v;
}

F64 MeshAtofTok(U8 *s) {
    I64 i = 0;
    I64 neg = 0;
    if (s[0] == '-') { neg = 1; i = 1; }
    else if (s[0] == '+') { i = 1; }
    F64 ip = 0.0;
    while (s[i] >= '0' && s[i] <= '9') { ip = ip * 10.0 + (F64)(s[i] - '0'); i = i + 1; }
    F64 fp = 0.0;
    F64 scale = 0.1;
    if (s[i] == '.') {
        i = i + 1;
        while (s[i] >= '0' && s[i] <= '9') { fp = fp + (F64)(s[i] - '0') * scale; scale = scale * 0.1; i = i + 1; }
    }
    F64 val = ip + fp;
    if (s[i] == 'e' || s[i] == 'E') {
        i = i + 1;
        I64 esign = 1;
        if (s[i] == '-') { esign = -1; i = i + 1; }
        else if (s[i] == '+') { i = i + 1; }
        I64 e = 0;
        while (s[i] >= '0' && s[i] <= '9') { e = e * 10 + (s[i] - '0'); i = i + 1; }
        I64 k = 0;
        while (k < e) {
            if (esign > 0) val = val * 10.0; else val = val / 10.0;
            k = k + 1;
        }
    }
    if (neg != 0) val = 0.0 - val;
    return val;
}

// Read the next whitespace-delimited token of src[le] starting at *pp into out.
U0 MeshNextTok(U8 *src, I64 le, I64 *pp, U8 *out, I64 maxlen) {
    I64 q = *pp;
    while (q < le && MeshIsWS(src[q])) q = q + 1;
    I64 i = 0;
    while (q < le && !MeshIsWS(src[q])) {
        if (i < maxlen - 1) { out[i] = src[q]; i = i + 1; }
        q = q + 1;
    }
    out[i] = 0;
    *pp = q;
}

I64 MeshAddNormal(CMesh *m, F64 x, F64 y, F64 z) {
    if (m->ncount >= MESH_MAX_N) return 0;
    m->nx[m->ncount] = x;
    m->ny[m->ncount] = y;
    m->nz[m->ncount] = z;
    m->ncount = m->ncount + 1;
    return m->ncount - 1;
}

// Resolve a 1-based (positive) or relative (negative) OBJ index to 0-based.
I64 MeshResolveIdx(U8 *tok, I64 count) {
    if (tok[0] == 0) return -1;
    I64 v = MeshAtoiTok(tok);
    if (v < 0) return count + v;
    if (v == 0) return -1;
    return v - 1;
}

// Parse one face corner "v", "v/t", "v//n" or "v/t/n" -> 0-based indices.
U0 MeshParseCorner(U8 *tok, I64 vc, I64 nc, I64 tc, I64 *ov, I64 *on, I64 *ot) {
    U8 parts[48];
    I64 np = 0;
    I64 i = 0;
    while (np < 3) {
        I64 j = 0;
        while (tok[i] != 0 && tok[i] != '/') {
            if (j < 15) { parts[np * 16 + j] = tok[i]; j = j + 1; }
            i = i + 1;
        }
        parts[np * 16 + j] = 0;
        np = np + 1;
        if (tok[i] == '/') i = i + 1;
        else break;
    }
    // Field order is v/t/n: parts[0]=v, parts[1]=t, parts[2]=n. For "v//n" the
    // texcoord field is empty and the normal is field 2.
    *ov = MeshResolveIdx(parts, vc);
    *ot = (np > 1) ? MeshResolveIdx(parts + 16, tc) : -1;
    *on = (np > 2) ? MeshResolveIdx(parts + 32, nc) : -1;
}

// ==============================================================================
// Streaming parser. Returns the triangle count, or -1 on failure.
// ==============================================================================
I64 MeshParseOBJ(U8 *src, I64 len, CMesh *m) {
    m->vcount = 0;
    m->ncount = 0;
    m->uvcount = 0;
    m->fcount = 0;

    I64 p = 0;
    while (p < len) {
        I64 ls = p;
        while (p < len && src[p] != 10) p = p + 1;
        I64 le = p;
        if (p < len) p = p + 1;

        I64 q = ls;
        while (q < le && MeshIsWS(src[q])) q = q + 1;
        if (q >= le) continue;
        U8 kw = src[q];
        if (kw == '#') continue;

        U8 tok[24];
        if (kw == 'v' && q + 1 < le && src[q + 1] == 'n') {
            q = q + 2;
            MeshNextTok(src, le, &q, tok, 24); F64 a = MeshAtofTok(tok);
            MeshNextTok(src, le, &q, tok, 24); F64 b = MeshAtofTok(tok);
            MeshNextTok(src, le, &q, tok, 24); F64 c = MeshAtofTok(tok);
            MeshAddNormal(m, a, b, c);
        } else if (kw == 'v' && q + 1 < le && src[q + 1] == 't') {
            q = q + 2;
            MeshNextTok(src, le, &q, tok, 24); F64 a = MeshAtofTok(tok);
            MeshNextTok(src, le, &q, tok, 24); F64 b = MeshAtofTok(tok);
            if (m->uvcount < MESH_MAX_UV) {
                m->uu[m->uvcount] = a;
                m->uv[m->uvcount] = b;
                m->uvcount = m->uvcount + 1;
            }
        } else if (kw == 'v') {
            q = q + 1;
            MeshNextTok(src, le, &q, tok, 24); F64 a = MeshAtofTok(tok);
            MeshNextTok(src, le, &q, tok, 24); F64 b = MeshAtofTok(tok);
            MeshNextTok(src, le, &q, tok, 24); F64 c = MeshAtofTok(tok);
            if (m->vcount < MESH_MAX_V) {
                m->vx[m->vcount] = a;
                m->vy[m->vcount] = b;
                m->vz[m->vcount] = c;
                m->vcount = m->vcount + 1;
            }
        } else if (kw == 'f') {
            q = q + 1;
            I64 cv[MESH_MAX_CORNERS];
            I64 cn[MESH_MAX_CORNERS];
            I64 ct[MESH_MAX_CORNERS];
            I64 ncorners = 0;
            while (ncorners < MESH_MAX_CORNERS) {
                MeshNextTok(src, le, &q, tok, 24);
                if (tok[0] == 0) break;
                I64 ov = 0; I64 on = 0; I64 ot = 0;
                MeshParseCorner(tok, m->vcount, m->ncount, m->uvcount, &ov, &on, &ot);
                cv[ncorners] = ov;
                cn[ncorners] = on;
                ct[ncorners] = ot;
                ncorners = ncorners + 1;
            }
            // Fan triangulation: (0, k, k+1).
            I64 k = 1;
            while (k + 1 < ncorners) {
                if (m->fcount < MESH_MAX_T) {
                    I64 b = m->fcount * 3;
                    m->fv[b + 0] = cv[0];       m->fni[b + 0] = cn[0];       m->ft[b + 0] = ct[0];
                    m->fv[b + 1] = cv[k];       m->fni[b + 1] = cn[k];       m->ft[b + 1] = ct[k];
                    m->fv[b + 2] = cv[k + 1];   m->fni[b + 2] = cn[k + 1];   m->ft[b + 2] = ct[k + 1];
                    m->fcount = m->fcount + 1;
                }
                k = k + 1;
            }
        }
        // else: o/g/s/usemtl/mtllib/l/p -> ignore
    }

    // Fill in missing normals with a computed face normal.
    I64 i = 0;
    while (i < m->fcount) {
        I64 b = i * 3;
        if (m->fni[b] < 0 || m->fni[b + 1] < 0 || m->fni[b + 2] < 0) {
            I64 i0 = m->fv[b + 0];
            I64 i1 = m->fv[b + 1];
            I64 i2 = m->fv[b + 2];
            F64 e1x = m->vx[i1] - m->vx[i0];
            F64 e1y = m->vy[i1] - m->vy[i0];
            F64 e1z = m->vz[i1] - m->vz[i0];
            F64 e2x = m->vx[i2] - m->vx[i0];
            F64 e2y = m->vy[i2] - m->vy[i0];
            F64 e2z = m->vz[i2] - m->vz[i0];
            F64 fnx = e1y * e2z - e1z * e2y;
            F64 fny = e1z * e2x - e1x * e2z;
            F64 fnz = e1x * e2y - e1y * e2x;
            F64 fl = MathSqrt(fnx * fnx + fny * fny + fnz * fnz);
            if (fl > 0.00001) { fnx = fnx / fl; fny = fny / fl; fnz = fnz / fl; }
            else { fnx = 0.0; fny = 0.0; fnz = 1.0; }
            I64 ni = MeshAddNormal(m, fnx, fny, fnz);
            m->fni[b + 0] = ni;
            m->fni[b + 1] = ni;
            m->fni[b + 2] = ni;
        }
        i = i + 1;
    }
    return m->fcount;
}

// ==============================================================================
// Accessors (sovereign rule: no cross-module struct-member access).
// ==============================================================================
I64 MeshGetVertexCount() { return g_mesh.vcount; }
I64 MeshGetTriCount()    { return g_mesh.fcount; }

// Parse the embedded cube into g_mesh if nothing is loaded yet.
U0 MeshEnsureLoaded() {
    if (g_mesh.fcount <= 0) {
        MeshParseOBJ(g_mesh_cube_obj, strlen(g_mesh_cube_obj), &g_mesh);
    }
}

// Load + parse an OBJ from RedSea. Returns the triangle count or -1.
U8 g_mesh_src[262144];
I64 MeshLoadFile(U8 *fname) {
    I64 sz = 0;
    if (redsea_read_file(fname, &g_mesh_src[0], 262143, &sz) != 0) return -1;
    if (sz <= 0) return -1;
    g_mesh_src[sz] = 0;
    return MeshParseOBJ(&g_mesh_src[0], sz, &g_mesh);
}

// ==============================================================================
// Render through the ONE pipeline (HolyGL -> RasterTriangleZ).
// ==============================================================================
U0 MeshRender(CMesh *m) {
    if (m->fcount <= 0) return;
    HolyGLBegin(GL_TRIANGLES);
    I64 i = 0;
    while (i < m->fcount) {
        I64 b = i * 3;
        I64 k = 0;
        while (k < 3) {
            I64 vi = m->fv[b + k];
            I64 ni = m->fni[b + k];
            if (ni >= 0) HolyGLNormal3f(m->nx[ni], m->ny[ni], m->nz[ni]);
            HolyGLColor3ub(176, 200, 232);
            HolyGLVertex3f(m->vx[vi], m->vy[vi], m->vz[vi]);
            k = k + 1;
        }
        i = i + 1;
    }
    HolyGLEnd();
}

U0 MeshRenderViewport(I64 vx, I64 vy, I64 vw, I64 vh, F64 angle) {
    MeshEnsureLoaded();
    gfx_draw_rect(vx, vy, vw, vh, 0xFF11111B);
    HolyGLViewport(vx, vy, vw, vh);
    HolyGLSetWireframe(0);
    HolyGLEnable(GL_DEPTH_TEST);
    HolyGLEnable(GL_LIGHTING);
    HolyGLDisable(GL_CULL_FACE);
    HolyGLDisable(GL_TEXTURE_2D);
    HolyGLMatrixMode(GL_PROJECTION); HolyGLLoadIdentity();
    HolyGLPerspective(40.0, (F64)vw / (F64)vh, 0.5, 100.0);
    HolyGLMatrixMode(GL_MODELVIEW); HolyGLLoadIdentity();
    HolyGLTranslatef(0.0, 0.0, -4.0);
    HolyGLRotatef(angle, 0.0, 1.0, 0.0);
    HolyGLRotatef(22.0, 1.0, 0.0, 0.0);
    MeshRender(&g_mesh);
    HolyGLDisable(GL_LIGHTING);
}

// Held visual for a host screendump (~8 s).
U0 MeshDemo() {
    I64 w = gfx_get_canvas_width();
    I64 h = gfx_get_canvas_height();
    I64 vw = 440;
    I64 vh = 440;
    if (vw > w - 80) vw = w - 80;
    if (vh > h - 80) vh = h - 80;
    I64 vx = (w - vw) / 2;
    I64 vy = (h - vh) / 2;
    MeshRenderViewport(vx, vy, vw, vh, 32.0);
    GfxPresent(0, 0, w, h, 1);
    U64 t0 = __mrs_cntvct();
    U64 fr = __mrs_cntfrq();
    if (fr == 0) fr = 62500000;
    U64 dur = fr * 8;
    while (__mrs_cntvct() - t0 < dur) { }
    gfx_clear(0xFF000000);
    GfxPresent(0, 0, w, h, 1);
}

// ==============================================================================
// Self-test support (called from SelfTest.HC -> MESH: PASS).
// ==============================================================================
U0 MeshSelfTest() {
    I64 slen = strlen(g_mesh_cube_obj);
    MeshParseOBJ(g_mesh_cube_obj, slen, &g_mesh);
    I64 vok = (g_mesh.vcount == 8);
    I64 fok = (g_mesh.fcount == 12);   // 6 quads -> 12 triangles
    I64 nok = (g_mesh.ncount == 6);

    HolyGLSetWireframe(0);
    GfxDeviceSetShading(0);
    HolyGLEnable(GL_LIGHTING);
    HolyGLEnable(GL_DEPTH_TEST);
    HolyGLDisable(GL_TEXTURE_2D);
    HolyGLDisable(GL_CULL_FACE);
    gfx_clear(0xFF202020);
    RasterClearZ();
    HolyGLViewport(60, 60, 380, 380);
    HolyGLMatrixMode(GL_PROJECTION); HolyGLLoadIdentity();
    HolyGLPerspective(40.0, 1.0, 0.5, 100.0);
    HolyGLMatrixMode(GL_MODELVIEW); HolyGLLoadIdentity();
    HolyGLTranslatef(0.0, 0.0, -4.0);
    HolyGLRotatef(28.0, 1.0, 0.0, 0.0);
    HolyGLRotatef(36.0, 0.0, 1.0, 0.0);

    I64 t0 = HolyGLGetTrisRendered();
    MeshRender(&g_mesh);
    I64 t1 = HolyGLGetTrisRendered();

    U32 *fb = RenderGetTargetBuffer();
    I64 pit = gfx_get_canvas_pitch();
    I64 ink = 0;
    I64 y = 60;
    while (y < 440) {
        I64 x = 60;
        while (x < 440) {
            if ((fb[y * pit + x] & 0xFFFFFF) != 0x202020) ink = ink + 1;
            x = x + 2;
        }
        y = y + 2;
    }
    HolyGLDisable(GL_LIGHTING);
    gfx_clear(0xFF202020);
    RasterClearZ();

    if (vok && fok && nok && (t1 - t0) == 12 && ink > 800) {
        doldoc_printf("MESH: PASS (v=%lld tris=%lld nrm=%lld ink=%lld)\n", g_mesh.vcount, t1 - t0, g_mesh.ncount, ink);
    } else {
        doldoc_printf("MESH: FAIL (v=%lld f=%lld nrm=%lld tris=%lld ink=%lld)\n",
                      g_mesh.vcount, g_mesh.fcount, g_mesh.ncount, t1 - t0, ink);
    }
    gfx_clear(0xFF000000);
    doldoc_mark_all_dirty();
}
