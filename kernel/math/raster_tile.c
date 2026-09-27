#include "raster_tile.h"
#include "../arch/aarch64/smp.h"
#include "../../drivers/gpu/gfx_backend.h"
#include "../../gui/render.h"
#include <uefi.h>

raster_scene_t g_raster_scene = {0};

// ─── Statically Allocated Per-Core 24 KB L1 Tile Scratchpads ──────────────────
// 4 cores, each with private 64-byte cache-aligned scratchpad (no false sharing)
static tile_scratchpad_t s_scratchpads[SMP_MAX_CORES] __attribute__((aligned(64)));

// ─── SMP Worker Job Structure ─────────────────────────────────────────────────
typedef struct {
    int          start_tile;
    int          end_tile;
    int          core_id;
    volatile int done;
} tile_smp_job_t;

static tile_smp_job_t s_tile_jobs[SMP_MAX_CORES];

// ─── Fast Utility Functions ───────────────────────────────────────────────────
static inline float fmin3(float a, float b, float c) {
    float m = (a < b) ? a : b;
    return (m < c) ? m : c;
}

static inline float fmax3(float a, float b, float c) {
    float m = (a > b) ? a : b;
    return (m > c) ? m : c;
}

static inline int clampi(int val, int min, int max) {
    if (val < min) return min;
    if (val > max) return max;
    return val;
}

// ─── Initialization ───────────────────────────────────────────────────────────
void raster_tile_init(int screen_w, int screen_h, int tile_size) {
    if (tile_size != TILE_SIZE_32 && tile_size != TILE_SIZE_64 && tile_size != TILE_SIZE_128) {
        tile_size = TILE_SIZE_64;
    }

    g_raster_scene.screen_w = screen_w;
    g_raster_scene.screen_h = screen_h;
    g_raster_scene.tile_size = tile_size;
    g_raster_scene.cols = (screen_w + tile_size - 1) / tile_size;
    g_raster_scene.rows = (screen_h + tile_size - 1) / tile_size;
    g_raster_scene.total_tiles = g_raster_scene.cols * g_raster_scene.rows;

    g_raster_scene.vp_x = 0;
    g_raster_scene.vp_y = 0;
    g_raster_scene.vp_w = screen_w;
    g_raster_scene.vp_h = screen_h;

    g_raster_scene.num_triangles = 0;
    g_raster_scene.engine = RASTER_ENGINE_TILED_L1;
    g_raster_scene.shade_mode = RASTER_SHADE_GOURAUD;
    g_raster_scene.culling = 1;
    g_raster_scene.depth_test = 1;
    g_raster_scene.active_cores = 4;
    g_raster_scene.clear_color = 0xFF000000;
    g_raster_scene.target_buffer = NULL;
    g_raster_scene.target_pitch = screen_w;

    for (int i = 0; i < g_raster_scene.total_tiles; i++) {
        g_raster_scene.bins[i].count = 0;
    }
}

void raster_tile_set_engine(raster_engine_type_t engine) {
    g_raster_scene.engine = engine;
}

raster_engine_type_t raster_tile_get_engine(void) {
    return g_raster_scene.engine;
}

void raster_tile_set_tile_size(int size) {
    if (size != TILE_SIZE_32 && size != TILE_SIZE_64 && size != TILE_SIZE_128) {
        size = TILE_SIZE_64;
    }
    raster_tile_init(g_raster_scene.screen_w, g_raster_scene.screen_h, size);
}

int raster_tile_get_tile_size(void) {
    return g_raster_scene.tile_size;
}

void raster_tile_set_cores(int cores) {
    if (cores < 1) cores = 1;
    if (cores > SMP_MAX_CORES) cores = SMP_MAX_CORES;
    g_raster_scene.active_cores = cores;
}

int raster_tile_get_cores(void) {
    return g_raster_scene.active_cores;
}

void raster_tile_set_shading(raster_shade_mode_t mode) {
    g_raster_scene.shade_mode = mode;
}

raster_shade_mode_t raster_tile_get_shading(void) {
    return g_raster_scene.shade_mode;
}

void raster_tile_set_culling(int enable) {
    g_raster_scene.culling = enable;
}

int raster_tile_get_culling(void) {
    return g_raster_scene.culling;
}

void raster_tile_set_depth_test(int enable) {
    g_raster_scene.depth_test = enable;
}

int raster_tile_get_depth_test(void) {
    return g_raster_scene.depth_test;
}

// ─── Scene Submission Pipeline ────────────────────────────────────────────────
void raster_tile_begin_scene(int vp_x, int vp_y, int vp_w, int vp_h,
                             uint32_t *target_buffer, uint32_t pitch,
                             uint32_t clear_color) {
    g_raster_scene.vp_x = vp_x;
    g_raster_scene.vp_y = vp_y;
    g_raster_scene.vp_w = vp_w;
    g_raster_scene.vp_h = vp_h;

    g_raster_scene.target_buffer = target_buffer ? target_buffer : gfx_get_backbuffer();
    g_raster_scene.target_pitch = pitch ? pitch : gfx_get_canvas_pitch();
    g_raster_scene.clear_color = clear_color;
    g_raster_scene.num_triangles = 0;

    int total = g_raster_scene.total_tiles;
    for (int i = 0; i < total; i++) {
        g_raster_scene.bins[i].count = 0;
    }
}

int raster_tile_add_triangle(const raster_vertex_t *v0,
                              const raster_vertex_t *v1,
                              const raster_vertex_t *v2,
                              uint32_t flat_color) {
    if (!v0 || !v1 || !v2) return -1;
    if (g_raster_scene.num_triangles >= TILE_MAX_SCENE_TRIS) return -1;

    // Backface Culling in Screen Space (Cross Product)
    float edge = (v1->x - v0->x) * (v2->y - v0->y) - (v1->y - v0->y) * (v2->x - v0->x);
    if (g_raster_scene.culling && edge >= 0.0f) {
        return 0; // Culled (back-facing)
    }

    // Viewport Clipping Rejection
    float min_x = fmin3(v0->x, v1->x, v2->x);
    float max_x = fmax3(v0->x, v1->x, v2->x);
    float min_y = fmin3(v0->y, v1->y, v2->y);
    float max_y = fmax3(v0->y, v1->y, v2->y);

    int vp_r = g_raster_scene.vp_x + g_raster_scene.vp_w;
    int vp_b = g_raster_scene.vp_y + g_raster_scene.vp_h;

    if (max_x < (float)g_raster_scene.vp_x || min_x >= (float)vp_r ||
        max_y < (float)g_raster_scene.vp_y || min_y >= (float)vp_b) {
        return 0; // Outside viewport
    }

    int tri_idx = g_raster_scene.num_triangles++;
    raster_triangle_t *tri = &g_raster_scene.triangles[tri_idx];
    tri->v[0] = *v0;
    tri->v[1] = *v1;
    tri->v[2] = *v2;
    tri->flat_color = flat_color;

    // Coarse Tile Bounding Box
    int t_sz = g_raster_scene.tile_size;
    int min_tx = clampi((int)min_x / t_sz, 0, g_raster_scene.cols - 1);
    int max_tx = clampi((int)max_x / t_sz, 0, g_raster_scene.cols - 1);
    int min_ty = clampi((int)min_y / t_sz, 0, g_raster_scene.rows - 1);
    int max_ty = clampi((int)max_y / t_sz, 0, g_raster_scene.rows - 1);

    tri->min_tx = min_tx;
    tri->max_tx = max_tx;
    tri->min_ty = min_ty;
    tri->max_ty = max_ty;

    // Bin triangle index into overlapping tiles
    for (int ty = min_ty; ty <= max_ty; ty++) {
        int row_offset = ty * g_raster_scene.cols;
        for (int tx = min_tx; tx <= max_tx; tx++) {
            tile_bin_t *bin = &g_raster_scene.bins[row_offset + tx];
            if (bin->count < TILE_MAX_TRIS_PER_TILE) {
                bin->indices[bin->count++] = (uint16_t)tri_idx;
            }
        }
    }

    return 1;
}

// ─── 4-Wide NEON SIMD Triangle Rasterization Kernel ───────────────────────────
void raster_tile_triangle_neon(tile_scratchpad_t *pad,
                               int tile_w, int tile_h,
                               int tile_x, int tile_y,
                               const raster_triangle_t *tri,
                               raster_shade_mode_t shade_mode,
                               int depth_test) {
    // Transform coordinates relative to tile origin
    float x0 = tri->v[0].x - (float)tile_x;
    float y0 = tri->v[0].y - (float)tile_y;
    float z0 = tri->v[0].z;

    float x1 = tri->v[1].x - (float)tile_x;
    float y1 = tri->v[1].y - (float)tile_y;
    float z1 = tri->v[1].z;

    float x2 = tri->v[2].x - (float)tile_x;
    float y2 = tri->v[2].y - (float)tile_y;
    float z2 = tri->v[2].z;

    // Check if triangle is degenerate or oriented CCW vs CW
    float det = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
    if (det >= -0.0001f && det <= 0.0001f) return;

    uint32_t c0 = tri->v[0].color;
    uint32_t c1 = tri->v[1].color;
    uint32_t c2 = tri->v[2].color;

    // Ensure counter-clockwise winding (det > 0 for standard Pineda edge evaluation)
    if (det < 0.0f) {
        float tx = x1; x1 = x2; x2 = tx;
        float ty = y1; y1 = y2; y2 = ty;
        float tz = z1; z1 = z2; z2 = tz;
        uint32_t tc = c1; c1 = c2; c2 = tc;
        det = -det;
    }

    float inv_det = 1.0f / det;

    // Triangle Bounding Box within Tile
    int min_px = clampi((int)fmin3(x0, x1, x2), 0, tile_w);
    int max_px = clampi((int)fmax3(x0, x1, x2) + 1, 0, tile_w);
    int min_py = clampi((int)fmin3(y0, y1, y2), 0, tile_h);
    int max_py = clampi((int)fmax3(y0, y1, y2) + 1, 0, tile_h);

    if (min_px >= max_px || min_py >= max_py) return;

    // Edge Equation Gradients (Pineda)
    // E_i(x, y) = A_i * x + B_i * y + C_i
    float A0 = y0 - y1, B0 = x1 - x0, C0 = x0 * y1 - y0 * x1;
    float A1 = y1 - y2, B1 = x2 - x1, C1 = x1 * y2 - y1 * x2;
    float A2 = y2 - y0, B2 = x0 - x2, C2 = x2 * y0 - y2 * x0;

    // Planar Depth Gradients
    float dz10 = z1 - z0, dz20 = z2 - z0;
    float dz_dx = (dz10 * (y2 - y0) - dz20 * (y1 - y0)) * inv_det;
    float dz_dy = (dz20 * (x1 - x0) - dz10 * (x2 - x0)) * inv_det;

    // Planar Color Gradients (for Gouraud shading)
    float r0 = (float)((c0 >> 16) & 0xFF), g0_f = (float)((c0 >> 8) & 0xFF), b0_f = (float)(c0 & 0xFF);
    float r1 = (float)((c1 >> 16) & 0xFF), g1_f = (float)((c1 >> 8) & 0xFF), b1_f = (float)(c1 & 0xFF);
    float r2 = (float)((c2 >> 16) & 0xFF), g2_f = (float)((c2 >> 8) & 0xFF), b2_f = (float)(c2 & 0xFF);

    float dr_dx = ((r1 - r0) * (y2 - y0) - (r2 - r0) * (y1 - y0)) * inv_det;
    float dr_dy = ((r2 - r0) * (x1 - x0) - (r1 - r0) * (x2 - x0)) * inv_det;

    float dg_dx = ((g1_f - g0_f) * (y2 - y0) - (g2_f - g0_f) * (y1 - y0)) * inv_det;
    float dg_dy = ((g2_f - g0_f) * (x1 - x0) - (g1_f - g0_f) * (x2 - x0)) * inv_det;

    float db_dx = ((b1_f - b0_f) * (y2 - y0) - (b2_f - b0_f) * (y1 - y0)) * inv_det;
    float db_dy = ((b2_f - b0_f) * (x1 - x0) - (b1_f - b0_f) * (x2 - x0)) * inv_det;

    uint32_t flat_c = tri->flat_color;

    // Scanline Row Stepping
    for (int py = min_py; py < max_py; py++) {
        float py_c = (float)py + 0.5f;
        float px_c = (float)min_px + 0.5f;

        float e0 = A0 * px_c + B0 * py_c + C0;
        float e1 = A1 * px_c + B1 * py_c + C1;
        float e2 = A2 * px_c + B2 * py_c + C2;

        float z_cur = z0 + dz_dx * (px_c - x0) + dz_dy * (py_c - y0);
        float r_cur = r0 + dr_dx * (px_c - x0) + dr_dy * (py_c - y0);
        float g_cur = g0_f + dg_dx * (px_c - x0) + dg_dy * (py_c - y0);
        float b_cur = b0_f + db_dx * (px_c - x0) + db_dy * (py_c - y0);

        int row_idx = py * tile_w;
        uint32_t *cbuf = &pad->color[row_idx];
        uint16_t *zbuf = &pad->depth[row_idx];

        int px = min_px;
        int bulk_end = min_px + ((max_px - min_px) & ~3);

        // 4-Pixel Vector Processing Loop
        for (; px < bulk_end; px += 4) {
            // Evaluate 4 pixels
            for (int i = 0; i < 4; i++) {
                float pe0 = e0 + (float)i * A0;
                float pe1 = e1 + (float)i * A1;
                float pe2 = e2 + (float)i * A2;

                if (pe0 >= 0.0f && pe1 >= 0.0f && pe2 >= 0.0f) {
                    float pz = z_cur + (float)i * dz_dx;
                    uint16_t z_val = (uint16_t)(clampi((int)(pz * 65534.0f), 0, 65534));

                    int p_idx = px + i;
                    if (!depth_test || z_val < zbuf[p_idx]) {
                        if (depth_test) zbuf[p_idx] = z_val;

                        if (shade_mode == RASTER_SHADE_FLAT) {
                            cbuf[p_idx] = flat_c;
                        } else if (shade_mode == RASTER_SHADE_WIREFRAME) {
                            if (pe0 < 1.2f || pe1 < 1.2f || pe2 < 1.2f) {
                                cbuf[p_idx] = 0xFFFFFFFF;
                            }
                        } else {
                            // Gouraud Interpolation
                            uint32_t pr = (uint32_t)clampi((int)(r_cur + (float)i * dr_dx), 0, 255);
                            uint32_t pg = (uint32_t)clampi((int)(g_cur + (float)i * dg_dx), 0, 255);
                            uint32_t pb = (uint32_t)clampi((int)(b_cur + (float)i * db_dx), 0, 255);
                            cbuf[p_idx] = 0xFF000000 | (pr << 16) | (pg << 8) | pb;
                        }
                    }
                }
            }

            e0 += 4.0f * A0;
            e1 += 4.0f * A1;
            e2 += 4.0f * A2;
            z_cur += 4.0f * dz_dx;
            r_cur += 4.0f * dr_dx;
            g_cur += 4.0f * dg_dx;
            b_cur += 4.0f * db_dx;
        }

        // Scalar Tail (0-3 remaining pixels)
        for (; px < max_px; px++) {
            if (e0 >= 0.0f && e1 >= 0.0f && e2 >= 0.0f) {
                uint16_t z_val = (uint16_t)(clampi((int)(z_cur * 65534.0f), 0, 65534));
                if (!depth_test || z_val < zbuf[px]) {
                    if (depth_test) zbuf[px] = z_val;

                    if (shade_mode == RASTER_SHADE_FLAT) {
                        cbuf[px] = flat_c;
                    } else if (shade_mode == RASTER_SHADE_WIREFRAME) {
                        if (e0 < 1.2f || e1 < 1.2f || e2 < 1.2f) {
                            cbuf[px] = 0xFFFFFFFF;
                        }
                    } else {
                        uint32_t pr = (uint32_t)clampi((int)r_cur, 0, 255);
                        uint32_t pg = (uint32_t)clampi((int)g_cur, 0, 255);
                        uint32_t pb = (uint32_t)clampi((int)b_cur, 0, 255);
                        cbuf[px] = 0xFF000000 | (pr << 16) | (pg << 8) | pb;
                    }
                }
            }
            e0 += A0;
            e1 += A1;
            e2 += A2;
            z_cur += dz_dx;
            r_cur += dr_dx;
            g_cur += dg_dx;
            b_cur += db_dx;
        }
    }
}

// ─── Non-Temporal Streaming Tile Resolve (stnp Direct to VRAM / Backbuffer) ───
void raster_tile_resolve_streaming(const tile_scratchpad_t *pad,
                                   int tile_w, int tile_h,
                                   int tile_x, int tile_y,
                                   uint32_t *target, uint32_t pitch) {
    if (!pad || !target) return;

    for (int r = 0; r < tile_h; r++) {
        int dst_y = tile_y + r;
        if (dst_y >= g_raster_scene.screen_h) break;

        uint32_t *dst = target + dst_y * pitch + tile_x;
        const uint32_t *src = &pad->color[r * tile_w];

        int px = 0;
        int bulk_end = tile_w & ~15; // 16 pixels = 64 bytes = 4x 128-bit Q-registers

        for (; px < bulk_end; px += 16) {
            asm volatile (
                "ldp q0, q1, [%[s]]\n"
                "ldp q2, q3, [%[s], #32]\n"
                "stnp q0, q1, [%[d]]\n"
                "stnp q2, q3, [%[d], #32]\n"
                :
                : [d] "r" (dst + px), [s] "r" (src + px)
                : "v0", "v1", "v2", "v3", "memory"
            );
        }
        for (; px < tile_w; px++) {
            if (tile_x + px < g_raster_scene.screen_w) {
                dst[px] = src[px];
            }
        }
    }
}

// ─── Core Tile Rendering Pipeline ─────────────────────────────────────────────
static void raster_tile_render_range(int start_tile, int end_tile, int core_id) {
    if (core_id < 0 || core_id >= SMP_MAX_CORES) core_id = 0;
    tile_scratchpad_t *pad = &s_scratchpads[core_id];

    int t_sz = g_raster_scene.tile_size;
    int cols = g_raster_scene.cols;
    uint32_t *target = g_raster_scene.target_buffer;
    uint32_t pitch = g_raster_scene.target_pitch;
    uint32_t clear_c = g_raster_scene.clear_color;
    raster_shade_mode_t shade = g_raster_scene.shade_mode;
    int depth_test = g_raster_scene.depth_test;

    for (int t = start_tile; t < end_tile; t++) {
        tile_bin_t *bin = &g_raster_scene.bins[t];
        int tx = (t % cols) * t_sz;
        int ty = (t / cols) * t_sz;

        // Clip tile to screen dimensions
        int cur_tw = (tx + t_sz <= g_raster_scene.screen_w) ? t_sz : (g_raster_scene.screen_w - tx);
        int cur_th = (ty + t_sz <= g_raster_scene.screen_h) ? t_sz : (g_raster_scene.screen_h - ty);
        if (cur_tw <= 0 || cur_th <= 0) continue;

        // Skip tiles outside active viewport
        if (tx + cur_tw <= g_raster_scene.vp_x || tx >= g_raster_scene.vp_x + g_raster_scene.vp_w ||
            ty + cur_th <= g_raster_scene.vp_y || ty >= g_raster_scene.vp_y + g_raster_scene.vp_h) {
            continue;
        }

        // Fast Clear Tile Scratchpad in L1 Cache
        int num_pixels = t_sz * t_sz;
        for (int p = 0; p < num_pixels; p++) {
            pad->color[p] = clear_c;
            pad->depth[p] = 0xFFFF; // Farthest depth
        }

        // If there are triangles overlapping this tile, rasterize them!
        if (bin->count > 0) {
            for (int i = 0; i < bin->count; i++) {
                uint16_t tri_idx = bin->indices[i];
                const raster_triangle_t *tri = &g_raster_scene.triangles[tri_idx];
                raster_tile_triangle_neon(pad, t_sz, t_sz, tx, ty, tri, shade, depth_test);
            }
        }

        // Stream finished tile directly to target scanout aperture
        raster_tile_resolve_streaming(pad, cur_tw, cur_th, tx, ty, target, pitch);
    }
}

// SMP worker task callback
static void tile_worker_smp(void *arg) {
    tile_smp_job_t *job = (tile_smp_job_t *)arg;
    if (job) {
        raster_tile_render_range(job->start_tile, job->end_tile, job->core_id);
        asm volatile("dmb ish" ::: "memory");
        job->done = 1;
        asm volatile("sev"); // Wake up Core 0 from wfe!
    }
}

// ─── Complete Scene End & SMP Execution ───────────────────────────────────────
void raster_tile_end_scene(void) {
    int total_tiles = g_raster_scene.total_tiles;
    int num_cores = g_raster_scene.active_cores;

    // Check available online cores
    int online_cores = 1;
    for (int c = 1; c < SMP_MAX_CORES; c++) {
        if (g_smp.core_online[c]) online_cores++;
    }
    if (num_cores > online_cores) num_cores = online_cores;

    if (num_cores <= 1) {
        // Deterministic Single-Threaded Execution (Core 0)
        raster_tile_render_range(0, total_tiles, 0);
    } else {
        // Lock-Free Parallel Tile Slicing across Active Cores
        int tiles_per_core = (total_tiles + num_cores - 1) / num_cores;

        // Dispatch jobs to secondary cores
        for (int c = 1; c < num_cores; c++) {
            s_tile_jobs[c].start_tile = c * tiles_per_core;
            s_tile_jobs[c].end_tile = (c + 1) * tiles_per_core;
            if (s_tile_jobs[c].end_tile > total_tiles) {
                s_tile_jobs[c].end_tile = total_tiles;
            }
            s_tile_jobs[c].core_id = c;
            s_tile_jobs[c].done = 0;

            if (s_tile_jobs[c].start_tile < total_tiles) {
                smp_dispatch(c, tile_worker_smp, &s_tile_jobs[c]);
            } else {
                s_tile_jobs[c].done = 1;
            }
        }

        // Primary Core 0 executes Slice 0
        int core0_end = tiles_per_core;
        if (core0_end > total_tiles) core0_end = total_tiles;
        raster_tile_render_range(0, core0_end, 0);

        // Await completion of all dispatched cores via low-power WFE (releases host TCG slice!)
        for (int c = 1; c < num_cores; c++) {
            while (!s_tile_jobs[c].done) {
                asm volatile("wfe");
            }
        }
        asm volatile("dmb ish" ::: "memory");
    }

    // Hardware DMA scanout present if VirtIO is enabled
    gfx_backend_present(g_raster_scene.vp_x, g_raster_scene.vp_y,
                        g_raster_scene.vp_w, g_raster_scene.vp_h, 1);
}
