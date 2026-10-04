#include "bench_unified.h"
#include "../../gui/render.h"
#include "../../gui/wm.h"
#include "../../gui/menu.h"
#include "../arch/aarch64/smp.h"
#include "../arch/aarch64/timer.h"
#include "../math/raster_tile.h"
#include "../../drivers/gpu/gfx_backend.h"
#include "../../fs/redsea.h"
#include "../math/holygl.h"
#include <uefi.h>

extern void uart_puts(const char *s);
extern void doldoc_print(const char *str);
extern void doldoc_printf(const char *fmt, ...);
extern void compositor_set_vsync(uint32_t hz);
extern uint32_t compositor_get_vsync(void);

bench_unified_t g_bench = {0};

static inline uint64_t read_cntvct(void) {
    uint64_t val;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    return val;
}

static inline uint64_t read_cntfrq(void) {
    uint64_t val;
    asm volatile("mrs %0, cntfrq_el0" : "=r"(val));
    return val;
}

// ─── Genuine SMP Worker for Parallel 3D Geometry Rasterization ─────────────────

typedef struct {
    mesh3d_cube_t *cube;
    mat4_t         vp;
    int            vp_x, vp_y, vp_w, vp_h;
    uint32_t       color1, color2;
} smp_cube_wire_job_t;

static smp_cube_wire_job_t s_smp_cube_job;

static void worker_render_cube_wire(void *arg) {
    smp_cube_wire_job_t *job = (smp_cube_wire_job_t*)arg;
    if (!job || !job->cube) return;
    mesh3d_render_wireframe(job->cube, &job->vp, job->vp_x, job->vp_y, job->vp_w, job->vp_h, job->color1, job->color2);
}

void bench_unified_record_blit(uint64_t blit_us) {
    perf_overlay_record_blit(&g_bench.perf_stats, blit_us);
}

// ─── Suite Phase Configuration Applicator ─────────────────────────────────────

static const char *s_cat_names[5] = {
    "Gears", "Cubes", "Dynamics", "Sphere", "Fillrate"
};
static const char *s_var_names[8] = {
    "SW 1C Base", "SW NEON L1", "SW SMP 4C", "SW DirectVRAM",
    "HW VirtIO",  "HW DMA+SMP", "HW Wireframe", "HW VSync 60Hz"
};

static void bench_apply_suite_phase(int phase) {
    if (phase < 0 || phase >= BENCH_SUITE_TOTAL_PHASES) return;

    g_bench.render_w = 640;
    g_bench.render_h = 360;
    gpu_set_shading(RASTER_SHADE_GOURAUD);

    int cat = phase / 8; // 0=Gears, 1=Cubes, 2=Dynamics, 3=Sphere, 4=Fillrate
    int var = phase % 8; // 0..7

    if (cat == 2) {
        physics3d_world_init();
    }

    switch (var) {
        case 0: // V1: SW Baseline 1C
            g_gfx_backend.mode = GFX_MODE_CPU_SW;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
            gpu_set_smp_cores(1);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(0, 0);
            break;
        case 1: // V2: SW NEON SIMD L1-Tile
            g_gfx_backend.mode = GFX_MODE_CPU_SW;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(1);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(0, 0);
            break;
        case 2: // V3: SW SMP 4C
            g_gfx_backend.mode = GFX_MODE_SMP_TILED;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(4);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(0, 0);
            break;
        case 3: // V4: SW Zero-RAM Direct VRAM
            g_gfx_backend.mode = GFX_MODE_CPU_SW;
            gpu_set_buffering(GFX_BUFFER_DIRECT_VRAM);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(4);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(0, 0);
            break;
        case 4: // V5: HW VirtIO DMA (1C)
            g_gfx_backend.mode = GFX_MODE_GPU_HW;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(1);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(0, 0);
            break;
        case 5: // V6: HW VirtIO DMA + SMP 4C
            g_gfx_backend.mode = GFX_MODE_GPU_HW;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(4);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(0, 0);
            break;
        case 6: // V7: HW Wireframe
            g_gfx_backend.mode = GFX_MODE_GPU_HW;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(4);
            gpu_set_shading(RASTER_SHADE_WIREFRAME);
            gfx_vsync_set(0, 0);
            break;
        case 7: // V8: HW VSync Locked 60Hz
            g_gfx_backend.mode = GFX_MODE_GPU_HW;
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            gpu_set_smp_cores(4);
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            gfx_vsync_set(1, 60);
            break;
    }

    snprintf(g_bench.comparison_records[phase].name, sizeof(g_bench.comparison_records[phase].name),
             "%s: %s", s_cat_names[cat], s_var_names[var]);

    g_bench.suite_phase_start_ticks = read_cntvct();
    uint64_t freq = read_cntfrq();
    if (freq == 0) freq = 62500000ULL;
    // Robust 3.5 seconds per individual test (allowing steady-state statistical convergence)
    g_bench.suite_phase_duration_ticks = (freq * 7ULL) / 2ULL;
    g_bench.suite_phase_elapsed_sec = 0.0f;
    g_bench.suite_ticks = 0;
    profiler_phase_reset(5);
    perf_overlay_init(&g_bench.perf_stats);
}

// ─── Initialization ──────────────────────────────────────────────────────────

typedef struct {
    vec3_t  vertices[128];
    int     num_vertices;
    tri3d_t triangles[256];
    int     num_triangles;
} mesh3d_sphere_t;

static mesh3d_sphere_t s_sphere;
static float s_sphere_rot = 0.0f;

static void init_sphere_mesh(mesh3d_sphere_t *sph, float radius, int rings, int sectors) {
    if (rings > 8) rings = 8;
    if (sectors > 12) sectors = 12;
    sph->num_vertices = 0;
    sph->num_triangles = 0;
    float const R = 1.0f / (float)(rings - 1);
    float const S = 1.0f / (float)(sectors - 1);
    for (int r = 0; r < rings; ++r) {
        for (int s = 0; s < sectors; ++s) {
            float y = math3d_sin((float)r * 180.0f * R - 90.0f);
            float x = math3d_cos((float)s * 360.0f * S) * math3d_cos((float)r * 180.0f * R - 90.0f);
            float z = math3d_sin((float)s * 360.0f * S) * math3d_cos((float)r * 180.0f * R - 90.0f);
            if (sph->num_vertices < 128) {
                sph->vertices[sph->num_vertices].x = x * radius;
                sph->vertices[sph->num_vertices].y = y * radius;
                sph->vertices[sph->num_vertices].z = z * radius;
                sph->num_vertices++;
            }
        }
    }
    for (int r = 0; r < rings - 1; ++r) {
        for (int s = 0; s < sectors - 1; ++s) {
            int i0 = r * sectors + s;
            int i1 = r * sectors + (s + 1);
            int i2 = (r + 1) * sectors + (s + 1);
            int i3 = (r + 1) * sectors + s;
            if (sph->num_triangles < 254) {
                sph->triangles[sph->num_triangles].v[0] = i0;
                sph->triangles[sph->num_triangles].v[1] = i1;
                sph->triangles[sph->num_triangles].v[2] = i2;
                sph->triangles[sph->num_triangles].color = ((r + s) % 2) ? 0xFF3498DB : 0xFF2ECC71;
                sph->num_triangles++;
                sph->triangles[sph->num_triangles].v[0] = i0;
                sph->triangles[sph->num_triangles].v[1] = i2;
                sph->triangles[sph->num_triangles].v[2] = i3;
                sph->triangles[sph->num_triangles].color = ((r + s) % 2) ? 0xFFE74C3C : 0xFFF1C40F;
                sph->num_triangles++;
            }
        }
    }
}

static void render_sphere_mesh(const mesh3d_sphere_t *sph, const mat4_t *mvp, int vp_x, int vp_y, int vp_w, int vp_h, int wireframe) {
    if (!sph || !mvp) return;
    int sx[128], sy[128], valid[128];
    float half_w = (float)vp_w * 0.5f, half_h = (float)vp_h * 0.5f;
    float cx = (float)vp_x + half_w, cy = (float)vp_y + half_h;
    for (int i = 0; i < sph->num_vertices; i++) {
        vec4_t v = {sph->vertices[i].x, sph->vertices[i].y, sph->vertices[i].z, 1.0f};
        vec4_t p;
        mat4_mul_vec4(&p, mvp, &v);
        if (p.w > 0.05f) {
            float inv_w = 1.0f / p.w;
            sx[i] = (int)(cx + p.x * inv_w * half_w);
            sy[i] = (int)(cy - p.y * inv_w * half_h);
            valid[i] = 1;
        } else {
            valid[i] = 0;
        }
    }
    for (int i = 0; i < sph->num_triangles; i++) {
        int i0 = sph->triangles[i].v[0];
        int i1 = sph->triangles[i].v[1];
        int i2 = sph->triangles[i].v[2];
        if (valid[i0] && valid[i1] && valid[i2]) {
            if (wireframe) {
                gfx_draw_triangle_wire(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2], COLOR_ACCENT_CYAN);
            } else {
                gfx_draw_triangle_fill(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2], sph->triangles[i].color);
                gfx_draw_triangle_wire(sx[i0], sy[i0], sx[i1], sy[i1], sx[i2], sy[i2], 0xFF1B1E20);
            }
        }
    }
}

void bench_unified_init(void) {
    memset(&g_bench, 0, sizeof(g_bench));
    g_bench.current_mode = BENCH_MODE_GEARS;
    g_bench.wireframe = 0;
    g_bench.smp_mode = 1;
    g_bench.vsync_preset = compositor_get_vsync();
    g_bench.res_preset = BENCH_RES_360P;
    g_bench.render_w = 640;
    g_bench.render_h = 360;

    math3d_init();
    init_sphere_mesh(&s_sphere, 2.8f, 8, 12);

    // 1. Gears Setup
    zbuffer_init(&g_bench.zbuffer, 640, 360);
    gear_generate(&g_bench.gear1, 1.0f, 4.0f, 1.0f, 20, 0.7f, 0xFFE74C3C); // Red (20t)
    g_bench.gear1.pos = (vec3_t){-3.0f, -2.0f, 0.0f};
    gear_generate(&g_bench.gear2, 0.5f, 2.0f, 2.0f, 10, 0.7f, 0xFF2ECC71); // Green (10t)
    g_bench.gear2.pos = (vec3_t){3.1f, -2.0f, 0.0f};
    gear_generate(&g_bench.gear3, 1.3f, 2.0f, 0.5f, 10, 0.7f, 0xFF3498DB); // Blue (10t)
    g_bench.gear3.pos = (vec3_t){-3.1f, 4.2f, 0.0f};
    g_bench.view_rotx = 20.0f;
    g_bench.view_roty = 30.0f;
    g_bench.gear_angle = 0.0f;

    // 2. Dual Cubes Setup
    mesh3d_init_cube(&g_bench.cube_left, 2.0f);
    mesh3d_init_cube(&g_bench.cube_right, 2.0f);
    g_bench.cube_rotx_l = 25.0f; g_bench.cube_roty_l = 35.0f; g_bench.cube_rotz_l = 10.0f;
    g_bench.cube_rotx_r = 15.0f; g_bench.cube_roty_r = 45.0f; g_bench.cube_rotz_r = 30.0f;

    // 3. Suite Setup (6 Phases)
    mesh3d_init_cube(&g_bench.suite_cube, 2.0f);
    physics3d_world_init();
    texture_generate_procedural(g_bench.suite_tex_neon, 64, 64, 0);
    texture_generate_procedural(g_bench.suite_tex_check, 64, 64, 1);
    g_bench.suite_phase = PHASE_IDLE;
    g_bench.suite_cycle = 0;
    g_bench.suite_finished = 0;

    for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
        int cat = p / 8;
        int var = p % 8;
        snprintf(g_bench.comparison_records[p].name, sizeof(g_bench.comparison_records[p].name),
                 "%s: %s", s_cat_names[cat], s_var_names[var]);
    }

    perf_overlay_init(&g_bench.perf_stats);
}

// ─── Window Management Integration ───────────────────────────────────────────

int bench_unified_start(bench_mode_t initial_mode) {
    if (g_bench.active && g_bench.win_id != 0) {
        window_t *w = wm_get_window_by_id(g_bench.win_id);
        if (w) {
            w->is_minimized = 0;
            w->is_active = 1;
            wm_bring_to_front_by_id(g_bench.win_id);
            bench_unified_set_mode(initial_mode);
            wm_set_dirty();
            return 0;
        }
    }

    window_t *win = wm_create_window("NeoBench Extreme: Unified Sovereign Graphics Suite", 270, 45, 740, 560);
    if (!win) return -1;

    g_bench.win_id = win->id;
    g_bench.active = 1;
    win->custom_render = bench_unified_render;
    win->custom_click = bench_unified_click;
    win->user_data = &g_bench;

    wm_bring_to_front_by_id(win->id);
    bench_unified_set_mode(initial_mode);
    return 0;
}

void bench_unified_stop(void) {
    if (g_bench.active && g_bench.win_id != 0) {
        wm_destroy_window(g_bench.win_id);
        g_bench.win_id = 0;
        g_bench.active = 0;
    }
}

int bench_unified_is_active(void) {
    return g_bench.active;
}

void bench_unified_set_resolution(uint32_t w, uint32_t h) {
    if (w < 160) w = 160;
    if (h < 120) h = 120;
    if (w > 1920) w = 1920;
    if (h > 1080) h = 1080;

    g_bench.render_w = w;
    g_bench.render_h = h;
    g_bench.res_preset = BENCH_RES_CUSTOM;
    zbuffer_resize(&g_bench.zbuffer, (int)w, (int)h);
    wm_set_dirty();
}

void bench_unified_set_resolution_preset(uint32_t preset) {
    g_bench.res_preset = preset;
    if (preset == BENCH_RES_360P) {
        bench_unified_set_resolution(640, 360);
    } else if (preset == BENCH_RES_480P) {
        bench_unified_set_resolution(640, 480);
    } else if (preset == BENCH_RES_720P) {
        bench_unified_set_resolution(1280, 720);
    }
}

void bench_unified_set_mode(bench_mode_t mode) {
    g_bench.current_mode = mode;
    if (mode == BENCH_MODE_DYNAMICS) {
        physics3d_world_init();
    } else if (mode == BENCH_MODE_SUITE) {
        g_bench.suite_phase = PHASE_CPU_SW;
        g_bench.suite_cycle = 0;
        g_bench.suite_ticks = 0;
        g_bench.suite_finished = 0;
        bench_apply_suite_phase(0);
    }
    wm_set_dirty();
}

// ─── Export Benchmark Logs & Comparison Matrix to RedSea Filesystem ───────────

int bench_unified_export_comparison(void) {
    static char buf[8192];
    int len = 0;
    len += snprintf(buf + len, sizeof(buf) - len,
        "========================================================================================================================\n"
        "                               NeoOS HolyBenchmark 2.0: 40-Phase Symmetrical Telemetry Matrix                           \n"
        "                                       Target: AArch64 Ring 0 SASOS (4x Cortex-A72)                                     \n"
        "========================================================================================================================\n"
        "Ph | Category | Variation    | Avg FPS | 1%% Low | Avg FT (ms) | Render (ms) | Blit (ms) | Jitter | Primary Bottleneck\n"
        "---+----------+--------------+---------+--------+-------------+-------------+-----------+--------+----------------------\n"
    );

    int winner_idx = 0;
    float max_fps = -1.0f;
    for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
        if (g_bench.comparison_records[p].fps_avg > max_fps) {
            max_fps = g_bench.comparison_records[p].fps_avg;
            winner_idx = p;
        }
    }

    for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
        bench_comparison_record_t *r = &g_bench.comparison_records[p];
        int cat = p / 8;
        int var = p % 8;

        uint64_t fps_i = (uint64_t)r->fps_avg;
        uint64_t fps_f = (uint64_t)((r->fps_avg - (float)fps_i) * 10.0f);
        uint64_t l1_i = (uint64_t)r->fps_1pct_low;
        uint64_t l1_f = (uint64_t)((r->fps_1pct_low - (float)l1_i) * 10.0f);
        uint64_t ft_i = (uint64_t)r->frametime_avg_ms;
        uint64_t ft_f = (uint64_t)((r->frametime_avg_ms - (float)ft_i) * 10.0f);
        uint64_t rn_i = (uint64_t)r->render_time_ms;
        uint64_t rn_f = (uint64_t)((r->render_time_ms - (float)rn_i) * 10.0f);
        uint64_t bl_i = (uint64_t)r->blit_time_ms;
        uint64_t bl_f = (uint64_t)((r->blit_time_ms - (float)bl_i) * 10.0f);
        uint64_t jt_i = (uint64_t)r->jitter_ms;
        uint64_t jt_f = (uint64_t)((r->jitter_ms - (float)jt_i) * 10.0f);

        len += snprintf(buf + len, sizeof(buf) - len,
            "%2llu | %-8s | %-12s | %4llu.%llu  | %4llu.%llu |   %4llu.%llu    |   %4llu.%llu    |  %3llu.%llu    | %3llu.%llu| %s %s\n",
            (unsigned long long)(p + 1), s_cat_names[cat], s_var_names[var],
            (unsigned long long)fps_i, (unsigned long long)fps_f,
            (unsigned long long)l1_i, (unsigned long long)l1_f,
            (unsigned long long)ft_i, (unsigned long long)ft_f,
            (unsigned long long)rn_i, (unsigned long long)rn_f,
            (unsigned long long)bl_i, (unsigned long long)bl_f,
            (unsigned long long)jt_i, (unsigned long long)jt_f,
            r->bottleneck ? r->bottleneck : "BALANCED",
            (p == winner_idx) ? "[WINNER]" : ""
        );

        if ((p % 8) == 7 && p < BENCH_SUITE_TOTAL_PHASES - 1) {
            len += snprintf(buf + len, sizeof(buf) - len,
                "---+----------+--------------+---------+--------+-------------+-------------+-----------+--------+----------------------\n"
            );
        }
    }

    // 8x5 Comparative Matrix Summary
    len += snprintf(buf + len, sizeof(buf) - len,
        "========================================================================================================================\n"
        "                                  Symmetrical 8x5 Comparative Matrix (FPS by Engine)\n"
        "========================================================================================================================\n"
        "Variation       | GLXGears 3D  | Dual Cubes   | 3D Dynamics  | Sphere Mesh  | Fillrate     | Variance Mean\n"
        "----------------+--------------+--------------+--------------+--------------+--------------+---------------\n"
    );

    for (int v = 0; v < 8; v++) {
        float f0 = g_bench.comparison_records[0 * 8 + v].fps_avg;
        float f1 = g_bench.comparison_records[1 * 8 + v].fps_avg;
        float f2 = g_bench.comparison_records[2 * 8 + v].fps_avg;
        float f3 = g_bench.comparison_records[3 * 8 + v].fps_avg;
        float f4 = g_bench.comparison_records[4 * 8 + v].fps_avg;
        float f_mean = (f0 + f1 + f2 + f3 + f4) / 5.0f;

        uint64_t ui_f0 = (uint64_t)f0, ud_f0 = (uint64_t)((f0 - (float)ui_f0) * 10.0f);
        uint64_t ui_f1 = (uint64_t)f1, ud_f1 = (uint64_t)((f1 - (float)ui_f1) * 10.0f);
        uint64_t ui_f2 = (uint64_t)f2, ud_f2 = (uint64_t)((f2 - (float)ui_f2) * 10.0f);
        uint64_t ui_f3 = (uint64_t)f3, ud_f3 = (uint64_t)((f3 - (float)ui_f3) * 10.0f);
        uint64_t ui_f4 = (uint64_t)f4, ud_f4 = (uint64_t)((f4 - (float)ui_f4) * 10.0f);
        uint64_t ui_fm = (uint64_t)f_mean, ud_fm = (uint64_t)((f_mean - (float)ui_fm) * 10.0f);

        len += snprintf(buf + len, sizeof(buf) - len,
            "%-15s | %5llu.%llu FPS  | %5llu.%llu FPS  | %5llu.%llu FPS  | %5llu.%llu FPS  | %5llu.%llu FPS  | %5llu.%llu FPS\n",
            s_var_names[v],
            (unsigned long long)ui_f0, (unsigned long long)ud_f0,
            (unsigned long long)ui_f1, (unsigned long long)ud_f1,
            (unsigned long long)ui_f2, (unsigned long long)ud_f2,
            (unsigned long long)ui_f3, (unsigned long long)ud_f3,
            (unsigned long long)ui_f4, (unsigned long long)ud_f4,
            (unsigned long long)ui_fm, (unsigned long long)ud_fm
        );
    }
    extern const char* profiler_get_optimization_directive(profiler_bottleneck_t b);
    const char *opt_dir = profiler_get_optimization_directive(g_profiler.last_bottleneck);

    len += snprintf(buf + len, sizeof(buf) - len,
        "========================================================================================================================\n"
        "Architectural Telemetry Conclusion & Optimization Directives:\n"
        "Empirical Winner: Phase %u (%s) at %u.%u FPS.\n"
        "Primary System Bottleneck: %s\n"
        "Code-Level Optimization Directives:\n%s\n"
        "========================================================================================================================\n",
        (unsigned int)(winner_idx + 1), g_bench.comparison_records[winner_idx].name,
        (unsigned int)(uint32_t)g_bench.comparison_records[winner_idx].fps_avg,
        (unsigned int)((g_bench.comparison_records[winner_idx].fps_avg - (float)(uint32_t)g_bench.comparison_records[winner_idx].fps_avg) * 10.0f),
        profiler_bottleneck_str(g_profiler.last_bottleneck),
        opt_dir
    );

    redsea_write_file("BENCH_COMPARISON.TXT", buf, (size_t)len);
    uart_puts("[NEOBENCH] Exported 40-Phase Symmetrical Matrix to /BENCH_COMPARISON.TXT\r\n");
    return 0;
}

int bench_unified_export_log(void) {
    if (g_bench.perf_stats.total_frames < 2) return -1;

    perf_overlay_update_metrics(&g_bench.perf_stats);
    perf_stats_t *s = &g_bench.perf_stats;

    uint32_t fps_i = (uint32_t)s->fps_avg;
    uint32_t fps_f = (uint32_t)((s->fps_avg - (float)fps_i) * 10.0f);
    uint32_t sfps_i = (uint32_t)s->steady_fps_avg;
    uint32_t sfps_f = (uint32_t)((s->steady_fps_avg - (float)sfps_i) * 10.0f);
    uint32_t l1_i = (uint32_t)s->fps_1pct_low;
    uint32_t l1_f = (uint32_t)((s->fps_1pct_low - (float)l1_i) * 10.0f);
    uint32_t l01_i = (uint32_t)s->fps_01pct_low;
    uint32_t l01_f = (uint32_t)((s->fps_01pct_low - (float)l01_i) * 10.0f);
    uint32_t ft_i = (uint32_t)s->frame_time_avg_ms;
    uint32_t ft_f = (uint32_t)((s->frame_time_avg_ms - (float)ft_i) * 10.0f);
    uint32_t sft_i = (uint32_t)s->steady_frame_time_avg_ms;
    uint32_t sft_f = (uint32_t)((s->steady_frame_time_avg_ms - (float)sft_i) * 10.0f);
    uint32_t min_i = (uint32_t)s->frame_time_min_ms;
    uint32_t min_f = (uint32_t)((s->frame_time_min_ms - (float)min_i) * 10.0f);
    uint32_t max_i = (uint32_t)s->frame_time_max_ms;
    uint32_t max_f = (uint32_t)((s->frame_time_max_ms - (float)max_i) * 10.0f);
    uint32_t spk_i = (uint32_t)s->recent_spike_ms;
    uint32_t spk_f = (uint32_t)((s->recent_spike_ms - (float)spk_i) * 10.0f);
    uint32_t sd_i = (uint32_t)s->frame_time_stddev_ms;
    uint32_t sd_f = (uint32_t)((s->frame_time_stddev_ms - (float)sd_i) * 10.0f);
    uint32_t ssd_i = (uint32_t)s->steady_stddev_ms;
    uint32_t ssd_f = (uint32_t)((s->steady_stddev_ms - (float)ssd_i) * 10.0f);
    uint32_t rn_i = (uint32_t)s->render_avg_ms;
    uint32_t rn_f = (uint32_t)((s->render_avg_ms - (float)rn_i) * 10.0f);
    uint32_t bl_i = (uint32_t)s->blit_avg_ms;
    uint32_t bl_f = (uint32_t)((s->blit_avg_ms - (float)bl_i) * 10.0f);
    uint32_t wu_ms = (uint32_t)(s->warmup_spike_us / 1000);
    uint32_t wu_f  = (uint32_t)((s->warmup_spike_us % 1000) / 10);

    const char *mode_str = g_bench.current_mode == BENCH_MODE_GEARS ? "Authentic 3D GLXGears" :
        g_bench.current_mode == BENCH_MODE_CUBES_SMP ? "Dual Cubes SMP" :
        g_bench.current_mode == BENCH_MODE_DYNAMICS ? "3D Multi-Body Rigid Dynamics" : "Automated 10-Phase Comparison Suite";

    char buf[2048];
    int len = 0;
    len += snprintf(buf + len, sizeof(buf) - len,
        "======================================================================\n"
        "             NeoBench Extreme Unified Benchmark Telemetry Report      \n"
        "                  NeoOS AArch64 Ring 0 SASOS Kernel                   \n"
        "======================================================================\n"
    );
    len += snprintf(buf + len, sizeof(buf) - len, "Current Mode:         %s\n", mode_str);
    len += snprintf(buf + len, sizeof(buf) - len, "Total Frames:         %llu\n", (uint64_t)s->total_frames);
    len += snprintf(buf + len, sizeof(buf) - len, "Average FPS:          %llu.%llu\n", (uint64_t)fps_i, (uint64_t)fps_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Steady-State FPS:     %llu.%llu\n", (uint64_t)sfps_i, (uint64_t)sfps_f);
    len += snprintf(buf + len, sizeof(buf) - len, "1%% Low FPS:           %llu.%llu\n", (uint64_t)l1_i, (uint64_t)l1_f);
    len += snprintf(buf + len, sizeof(buf) - len, "0.1%% Low FPS:         %llu.%llu\n", (uint64_t)l01_i, (uint64_t)l01_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Avg Frame Time:       %llu.%llu ms (Steady: %llu.%llu ms)\n", (uint64_t)ft_i, (uint64_t)ft_f, (uint64_t)sft_i, (uint64_t)sft_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Min Frame Time:       %llu.%llu ms\n", (uint64_t)min_i, (uint64_t)min_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Max Frame Time:       %llu.%llu ms\n", (uint64_t)max_i, (uint64_t)max_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Recent 60f Worst:     %llu.%llu ms\n", (uint64_t)spk_i, (uint64_t)spk_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Frame Time StdDev:    %llu.%llu ms (Steady: %llu.%llu ms)\n", (uint64_t)sd_i, (uint64_t)sd_f, (uint64_t)ssd_i, (uint64_t)ssd_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Avg Render Time:      %llu.%llu ms\n", (uint64_t)rn_i, (uint64_t)rn_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Avg Blit Time:        %llu.%llu ms\n", (uint64_t)bl_i, (uint64_t)bl_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Cold Start Spike:     %llu.%llu ms\n", (uint64_t)wu_ms, (uint64_t)wu_f);
    len += snprintf(buf + len, sizeof(buf) - len, "Spikes (>50ms):       %llu\n", (uint64_t)s->spike_count_50ms);
    len += snprintf(buf + len, sizeof(buf) - len, "Spikes (>100ms):      %llu\n", (uint64_t)s->spike_count_100ms);
    len += snprintf(buf + len, sizeof(buf) - len, "Spikes (>500ms):      %llu\n", (uint64_t)s->spike_count_500ms);
    len += snprintf(buf + len, sizeof(buf) - len, "Active V-Sync Target: %llu Hz\n", (uint64_t)compositor_get_vsync());
    len += snprintf(buf + len, sizeof(buf) - len, "SMP Cores Stressed:   %s\n", g_bench.smp_mode ? "YES (Core 1 SIMD + Core 2 RAM)" : "NO (Single Core 0)");
    len += snprintf(buf + len, sizeof(buf) - len, "Wireframe Mode:       %s\n", g_bench.wireframe ? "ON" : "OFF");
    len += snprintf(buf + len, sizeof(buf) - len, "======================================================================\n");

    redsea_write_file("BENCH_REPORT.TXT", buf, (size_t)len);
    redsea_write_file("GEARS_BENCHMARK.LOG", buf, (size_t)len);
    uart_puts("[NEOBENCH] Exported BENCH_REPORT.TXT and GEARS_BENCHMARK.LOG to RedSea disk.\r\n");
    return 0;
}

// ─── Rendering Pipeline ───────────────────────────────────────────────────────

void bench_unified_render(window_t *win, void *user_data) {
    (void)user_data;
    if (!win || !g_bench.active) return;

    perf_overlay_begin_frame(&g_bench.perf_stats);
    uint64_t start_vct = read_cntvct();
    uint64_t freq = read_cntfrq();

    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;
    int ch = win->height - 38;

    int is_suite = (g_bench.current_mode == BENCH_MODE_SUITE);
    int top_offset = 0;

    if (!is_suite) {
        // 1. Draw Top Tab Bar (Mode Selector)
        int tab_w = cw / 4;
        const char *tab_names[4] = {
            "1. GLXGears 3D",
            "2. Cubes SMP",
            "3. Dynamics 64b",
            "4. 40-Phase Suite"
        };

        for (int t = 0; t < 4; t++) {
            int tx = cx + t * tab_w;
            int active = (t == (int)g_bench.current_mode);
            uint32_t t_bg = active ? 0xFF2C3E50 : 0xFF1A1D20;
            uint32_t t_fg = active ? COLOR_ACCENT_CYAN : COLOR_TEXT_MUTED;
            gfx_draw_rect(tx, cy, tab_w, 24, t_bg);
            if (active) {
                gfx_draw_rect(tx, cy + 22, tab_w, 2, COLOR_ACCENT_CYAN);
            }
            gfx_draw_string(tx + 8, cy + 5, tab_names[t], t_fg, 0);
        }

        // 2. Control Toolbar
        int bar_y = cy + 26;
        gfx_draw_rect(cx, bar_y, cw, 26, 0xFF212529);

        // Button: Wireframe
        gfx_draw_rounded_rect(cx + 8, bar_y + 3, 92, 20, 3, g_bench.wireframe ? 0xFF27AE60 : 0xFF34495E);
        gfx_draw_string(cx + 14, bar_y + 6, g_bench.wireframe ? "[X] Wireframe" : "[ ] Wireframe", COLOR_TEXT_WHITE, 0);

        // Button: SMP Mode
        gfx_draw_rounded_rect(cx + 106, bar_y + 3, 100, 20, 3, g_bench.smp_mode ? 0xFF2980B9 : 0xFF34495E);
        gfx_draw_string(cx + 112, bar_y + 6, g_bench.smp_mode ? "[X] SMP 4-Core" : "[ ] Single Core", COLOR_TEXT_WHITE, 0);

        // Button: V-Sync Cycle
        uint32_t cur_vsync = compositor_get_vsync();
        const char *vs_label = (cur_vsync == 0) ? "VSync: OFF" : (cur_vsync == 30) ? "VSync: 30" : "VSync: 60";
        gfx_draw_rounded_rect(cx + 212, bar_y + 3, 95, 20, 3, (cur_vsync > 0) ? 0xFF16A085 : 0xFF34495E);
        gfx_draw_string(cx + 218, bar_y + 6, vs_label, COLOR_TEXT_WHITE, 0);

        // Button: Export Log
        gfx_draw_rounded_rect(cx + 313, bar_y + 3, 114, 20, 3, 0xFF8E44AD);
        gfx_draw_string(cx + 320, bar_y + 6, "Export Matrix", COLOR_TEXT_WHITE, 0);

        // Button: Impulse (in Dynamics Mode)
        if (g_bench.current_mode == BENCH_MODE_DYNAMICS) {
            gfx_draw_rounded_rect(cx + 433, bar_y + 3, 85, 20, 3, 0xFFE67E22);
            gfx_draw_string(cx + 439, bar_y + 6, "Explode!", COLOR_TEXT_WHITE, 0);
        }
        top_offset = 54;
    }

    // 3. Centered Fixed-Resolution Viewport 3D Canvas
    int avail_w = cw;
    int avail_h = ch - top_offset;
    int target_w = (g_bench.render_w > 0) ? (int)g_bench.render_w : 640;
    int target_h = (g_bench.render_h > 0) ? (int)g_bench.render_h : 360;

    int vp_w = (target_w <= avail_w) ? target_w : avail_w;
    int vp_h = (target_h <= avail_h) ? target_h : avail_h;
    int vp_x = cx + (avail_w - vp_w) / 2;
    int vp_y = cy + top_offset + (avail_h - vp_h) / 2;

    // Outer framing / letterbox area
    gfx_draw_rect(cx, cy + top_offset, avail_w, avail_h, 0xFF0D1117);
    // Fixed Viewport Canvas
    gfx_draw_rect(vp_x, vp_y, vp_w, vp_h, 0xFF14171A);

    // ─── Mode Specific 3D Rendering ──────────────────────────────────────────

    if (g_bench.current_mode == BENCH_MODE_GEARS) {
        // Mode 1: Authentic 3D GLXGears
        zbuffer_clear(&g_bench.zbuffer);

        // Mouse Drag Camera Interaction
        mouse_state_t ms = mouse_get_state();
        if (ms.x >= vp_x && ms.x < vp_x + vp_w && ms.y >= vp_y && ms.y < vp_y + vp_h) {
            if (ms.left_button) {
                if (!g_bench.dragging) {
                    g_bench.dragging = 1;
                    g_bench.last_mouse_x = ms.x;
                    g_bench.last_mouse_y = ms.y;
                } else {
                    int dx = ms.x - g_bench.last_mouse_x;
                    int dy = ms.y - g_bench.last_mouse_y;
                    g_bench.view_roty += (float)dx * 0.6f;
                    g_bench.view_rotx += (float)dy * 0.6f;
                    g_bench.last_mouse_x = ms.x;
                    g_bench.last_mouse_y = ms.y;
                }
            } else {
                g_bench.dragging = 0;
            }
        } else {
            g_bench.dragging = 0;
        }

        // Advance Gear Angles
        g_bench.gear_angle += 2.0f;
        if (g_bench.gear_angle >= 360.0f) g_bench.gear_angle -= 360.0f;
        g_bench.gear1.angle = g_bench.gear_angle;
        g_bench.gear2.angle = -2.0f * g_bench.gear_angle - 9.0f;
        g_bench.gear3.angle = -2.0f * g_bench.gear_angle - 25.0f;

        // View-Projection Matrix (Camera at Z=-32.0f centers all 3 gears with zero clipping)
        mat4_t proj, view, rx, ry, rz, rot_tmp, vp;
        mat4_perspective(&proj, 42.0f, (float)vp_w / (float)vp_h, 1.0f, 100.0f);
        mat4_translate(&view, 0.0f, 0.0f, -32.0f);
        mat4_rotate_x(&rx, g_bench.view_rotx);
        mat4_rotate_y(&ry, g_bench.view_roty);
        mat4_rotate_z(&rz, 0.0f);
        mat4_mul(&rot_tmp, &rx, &ry);
        mat4_mul(&view, &view, &rot_tmp);
        mat4_mul(&vp, &proj, &view);

        // Render 3 Authentic Interlocking Gears (Red, Green, Blue)
        raster_tile_begin_scene(vp_x, vp_y, vp_w, vp_h, gfx_get_backbuffer(), gfx_get_canvas_pitch(), 0xFF14171A);
        gear_render(&g_bench.gear1, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, g_bench.wireframe);
        gear_render(&g_bench.gear2, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, g_bench.wireframe);
        gear_render(&g_bench.gear3, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, g_bench.wireframe);
        raster_tile_end_scene();

    } else if (g_bench.current_mode == BENCH_MODE_CUBES_SMP) {
        // Mode 2: Dual Cubes SMP (Core 1 Parallel Wireframe left, Core 0 Solid Shaded right)
        int half_w = vp_w / 2;

        // Divider
        gfx_draw_rect(vp_x + half_w, vp_y, 2, vp_h, 0xFF34495E);

        // Left Viewport (Cube 1: Parallel Wireframe on Core 1)
        g_bench.cube_rotx_l += 2.0f;
        g_bench.cube_roty_l += 3.0f;

        mat4_t proj_l, view_l, rx_l, ry_l, vp_l;
        mat4_perspective(&proj_l, 45.0f, (float)half_w / (float)vp_h, 1.0f, 50.0f);
        mat4_translate(&view_l, 0.0f, 0.0f, -6.0f);
        mat4_rotate_x(&rx_l, g_bench.cube_rotx_l);
        mat4_rotate_y(&ry_l, g_bench.cube_roty_l);
        mat4_mul(&view_l, &view_l, &rx_l);
        mat4_mul(&view_l, &view_l, &ry_l);
        mat4_mul(&vp_l, &proj_l, &view_l);

        int smp_active = (g_bench.smp_mode && smp_get_core_count() > 1);
        if (smp_active) {
            s_smp_cube_job.cube = &g_bench.cube_left;
            s_smp_cube_job.vp = vp_l;
            s_smp_cube_job.vp_x = vp_x;
            s_smp_cube_job.vp_y = vp_y;
            s_smp_cube_job.vp_w = half_w;
            s_smp_cube_job.vp_h = vp_h;
            s_smp_cube_job.color1 = COLOR_ACCENT_CYAN;
            s_smp_cube_job.color2 = COLOR_EMERALD_GREEN;
            smp_dispatch(1, worker_render_cube_wire, &s_smp_cube_job);
            g_bench.core1_ops += 12;
        } else {
            mesh3d_render_wireframe(&g_bench.cube_left, &vp_l, vp_x, vp_y, half_w, vp_h, COLOR_ACCENT_CYAN, COLOR_EMERALD_GREEN);
        }

        // Right Viewport (Cube 2: Solid Shaded on Core 0)
        g_bench.cube_rotx_r += 3.0f;
        g_bench.cube_roty_r += 2.0f;

        mat4_t proj_r, view_r, rx_r, ry_r, vp_r;
        mat4_perspective(&proj_r, 45.0f, (float)half_w / (float)vp_h, 1.0f, 50.0f);
        mat4_translate(&view_r, 0.0f, 0.0f, -6.0f);
        mat4_rotate_x(&rx_r, g_bench.cube_rotx_r);
        mat4_rotate_y(&ry_r, g_bench.cube_roty_r);
        mat4_mul(&view_r, &view_r, &rx_r);
        mat4_mul(&view_r, &view_r, &ry_r);
        mat4_mul(&vp_r, &proj_r, &view_r);

        vec3_t light = {0.577f, 0.577f, 0.577f};
        mesh3d_render_solid(&g_bench.cube_right, &vp_r, vp_x + half_w, vp_y, half_w, vp_h, 0xFFE67E22, light);
        g_bench.core2_ops += 12;

        // Synchronize Core 1 via low-power WFE (releases host TCG slice)
        if (smp_active) {
            uint64_t w_start = read_cntvct();
            while (!smp_is_job_done(1)) {
                __asm__ volatile("wfe");
            }
            uint64_t w_end = read_cntvct();
            uint64_t wait_us = (w_end > w_start && freq > 0) ? (((w_end - w_start) * 1000000ULL) / freq) : 0;
            bench_unified_record_smp_wait(wait_us);
        }

        // Core Status Cards
        gfx_blend_rect(vp_x + 10, vp_y + 10, 220, 48, 0xDD181C20);
        gfx_draw_rect_outline(vp_x + 10, vp_y + 10, 220, 48, COLOR_ACCENT_CYAN);
        gfx_draw_string(vp_x + 18, vp_y + 16, smp_active ? "Core 1: Parallel Wireframe" : "Core 0: Wireframe (Single)", COLOR_ACCENT_CYAN, 0);
        char c1_str[48];
        snprintf(c1_str, sizeof(c1_str), "Edges Rendered: %llu", (unsigned long long)g_bench.core1_ops);
        gfx_draw_string(vp_x + 18, vp_y + 32, c1_str, COLOR_TEXT_WHITE, 0);

        gfx_blend_rect(vp_x + half_w + 10, vp_y + 10, 220, 48, 0xDD181C20);
        gfx_draw_rect_outline(vp_x + half_w + 10, vp_y + 10, 220, 48, 0xFFE67E22);
        gfx_draw_string(vp_x + half_w + 18, vp_y + 16, "Core 0: Shaded Painter Engine", 0xFFE67E22, 0);
        char c2_str[48];
        snprintf(c2_str, sizeof(c2_str), "Triangles Drawn: %llu", (unsigned long long)g_bench.core2_ops);
        gfx_draw_string(vp_x + half_w + 18, vp_y + 32, c2_str, COLOR_TEXT_WHITE, 0);

    } else if (g_bench.current_mode == BENCH_MODE_DYNAMICS) {
        // Mode 3: 3D Multi-Body Rigid Dynamics
        physics3d_world_step(0.016f);

        mat4_t proj, view, vp;
        mat4_perspective(&proj, 45.0f, (float)vp_w / (float)vp_h, 1.0f, 100.0f);
        mat4_translate(&view, 0.0f, 0.0f, -8.0f);

        mat4_t rx, ry;
        mat4_rotate_x(&rx, g_bench.view_rotx);
        mat4_rotate_y(&ry, g_bench.view_roty);
        mat4_mul(&view, &view, &rx);
        mat4_mul(&view, &view, &ry);

        // Draw Arena Floor Wireframe Grid
        for (int gx = -4; gx <= 4; gx++) {
            vec4_t p0 = {(float)gx * 0.6f, -1.6f, -2.4f, 1.0f};
            vec4_t p1 = {(float)gx * 0.6f, -1.6f,  2.4f, 1.0f};
            vec4_t tp0, tp1;
            mat4_mul(&vp, &proj, &view);
            mat4_mul_vec4(&tp0, &vp, &p0);
            mat4_mul_vec4(&tp1, &vp, &p1);
            if (tp0.w > 0.1f && tp1.w > 0.1f) {
                float half_w_f = (float)vp_w * 0.5f, half_h_f = (float)vp_h * 0.5f;
                int sx0 = (int)((tp0.x / tp0.w + 1.0f) * half_w_f) + vp_x;
                int sy0 = (int)((-tp0.y / tp0.w + 1.0f) * half_h_f) + vp_y;
                int sx1 = (int)((tp1.x / tp1.w + 1.0f) * half_w_f) + vp_x;
                int sy1 = (int)((-tp1.y / tp1.w + 1.0f) * half_h_f) + vp_y;
                gfx_draw_line(sx0, sy0, sx1, sy1, 0xFF34495E);
            }
        }

        // Render each 3D rigid body cube
        for (int i = 0; i < g_physics_world.num_bodies; i++) {
            rigid_body_t *b = &g_physics_world.bodies[i];
            mat4_t model, mv, mvp;
            physics3d_get_transform(b, &model);
            mat4_mul(&mv, &view, &model);
            mat4_mul(&mvp, &proj, &mv);

            if (g_bench.wireframe) {
                mesh3d_render_wireframe(&g_bench.suite_cube, &mvp, vp_x, vp_y, vp_w, vp_h, b->color, 0xFFFFFFFF);
            } else {
                vec3_t light = {0.577f, 0.577f, 0.577f};
                mesh3d_render_solid(&g_bench.suite_cube, &mvp, vp_x, vp_y, vp_w, vp_h, b->color, light);
            }
        }

        // Physics Telemetry Card
        gfx_blend_rect(vp_x + 14, vp_y + 12, 380, 56, 0xDD181C20);
        gfx_draw_rect_outline(vp_x + 14, vp_y + 12, 380, 56, COLOR_ACCENT_CYAN);
        gfx_draw_string(vp_x + 22, vp_y + 18, "64-bit Rigid Body Dynamics Engine", COLOR_ACCENT_CYAN, 0);

        char dyn_str1[64], dyn_str2[64];
        uint32_t e_int = (uint32_t)g_physics_world.total_energy;
        uint32_t e_dec = (uint32_t)((g_physics_world.total_energy - (double)e_int) * 10.0);
        snprintf(dyn_str1, sizeof(dyn_str1), "Energy: %u.%u J | Collisions: %llu",
                 e_int, e_dec, (unsigned long long)g_physics_world.total_collisions);
        gfx_draw_string(vp_x + 22, vp_y + 32, dyn_str1, COLOR_GOLD_ACCENT, 0);

        snprintf(dyn_str2, sizeof(dyn_str2), "Bodies: 4 Active | Click window or [Explode!] to kick");
        gfx_draw_string(vp_x + 22, vp_y + 46, dyn_str2, COLOR_TEXT_MUTED, 0);

    } else if (g_bench.current_mode == BENCH_MODE_SUITE) {
        // Mode 4: Automated 40-Phase Symmetrical Scientific Suite (5 Engines x 8 Architectures)
        if (g_bench.suite_finished) {
            // ─── Render Final 8x5 Symmetrical Scorecard Matrix ───
            gfx_blend_rect(vp_x + 8, vp_y + 6, vp_w - 16, vp_h - 12, 0xF214171A);
            gfx_draw_rect_outline(vp_x + 8, vp_y + 6, vp_w - 16, vp_h - 12, COLOR_ACCENT_CYAN);

            gfx_draw_string(vp_x + 18, vp_y + 12, "✦ HolyBenchmark 2.0: 40-Phase Symmetrical Performance Matrix ✦", COLOR_GOLD_ACCENT, 0);
            gfx_draw_string(vp_x + 18, vp_y + 26, "Target Architecture: AArch64 Ring 0 SASOS (4x Cortex-A72) | 5 Engines x 8 Variations", COLOR_TEXT_MUTED, 0);

            int winner_idx = 0;
            float max_fps = -1.0f;
            for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
                if (g_bench.comparison_records[p].fps_avg > max_fps) {
                    max_fps = g_bench.comparison_records[p].fps_avg;
                    winner_idx = p;
                }
            }

            int row_y = vp_y + 44;
            gfx_draw_rect(vp_x + 14, row_y, vp_w - 28, 18, 0xFF2C3E50);
            gfx_draw_string(vp_x + 18,  row_y + 2, "Architecture", COLOR_TEXT_WHITE, 0);
            gfx_draw_string(vp_x + 148, row_y + 2, "GLXGears",     COLOR_ACCENT_CYAN, 0);
            gfx_draw_string(vp_x + 236, row_y + 2, "DualCubes",    COLOR_ACCENT_CYAN, 0);
            gfx_draw_string(vp_x + 328, row_y + 2, "Dynamics",     COLOR_ACCENT_CYAN, 0);
            gfx_draw_string(vp_x + 418, row_y + 2, "Sphere",       COLOR_ACCENT_CYAN, 0);
            gfx_draw_string(vp_x + 498, row_y + 2, "Fillrate",     COLOR_ACCENT_CYAN, 0);
            gfx_draw_string(vp_x + 578, row_y + 2, "Mean FPS",     COLOR_GOLD_ACCENT, 0);
            row_y += 20;

            for (int v = 0; v < 8; v++) {
                uint32_t row_bg = (v % 2 == 0) ? 0xFF1E242B : 0xFF171B20;
                gfx_draw_rect(vp_x + 14, row_y, vp_w - 28, 18, row_bg);

                gfx_draw_string(vp_x + 18, row_y + 2, s_var_names[v], COLOR_TEXT_WHITE, 0);

                float f0 = g_bench.comparison_records[0 * 8 + v].fps_avg;
                float f1 = g_bench.comparison_records[1 * 8 + v].fps_avg;
                float f2 = g_bench.comparison_records[2 * 8 + v].fps_avg;
                float f3 = g_bench.comparison_records[3 * 8 + v].fps_avg;
                float f4 = g_bench.comparison_records[4 * 8 + v].fps_avg;
                float f_mean = (f0 + f1 + f2 + f3 + f4) / 5.0f;

                char c0[16], c1[16], c2[16], c3[16], c4[16], cm[16];
                snprintf(c0, sizeof(c0), "%4u.%u", (uint32_t)f0, (uint32_t)((f0 - (float)(uint32_t)f0) * 10.0f));
                snprintf(c1, sizeof(c1), "%4u.%u", (uint32_t)f1, (uint32_t)((f1 - (float)(uint32_t)f1) * 10.0f));
                snprintf(c2, sizeof(c2), "%4u.%u", (uint32_t)f2, (uint32_t)((f2 - (float)(uint32_t)f2) * 10.0f));
                snprintf(c3, sizeof(c3), "%4u.%u", (uint32_t)f3, (uint32_t)((f3 - (float)(uint32_t)f3) * 10.0f));
                snprintf(c4, sizeof(c4), "%4u.%u", (uint32_t)f4, (uint32_t)((f4 - (float)(uint32_t)f4) * 10.0f));
                snprintf(cm, sizeof(cm), "%4u.%u", (uint32_t)f_mean, (uint32_t)((f_mean - (float)(uint32_t)f_mean) * 10.0f));

                gfx_draw_string(vp_x + 150, row_y + 2, c0, COLOR_TEXT_WHITE, 0);
                gfx_draw_string(vp_x + 238, row_y + 2, c1, COLOR_TEXT_WHITE, 0);
                gfx_draw_string(vp_x + 330, row_y + 2, c2, COLOR_TEXT_WHITE, 0);
                gfx_draw_string(vp_x + 420, row_y + 2, c3, COLOR_TEXT_WHITE, 0);
                gfx_draw_string(vp_x + 500, row_y + 2, c4, COLOR_TEXT_WHITE, 0);
                gfx_draw_string(vp_x + 580, row_y + 2, cm, COLOR_EMERALD_GREEN, 0);

                row_y += 19;
            }

            row_y += 6;
            gfx_blend_rect(vp_x + 14, row_y, vp_w - 28, 44, 0xFF1C2833);
            gfx_draw_rect(vp_x + 14, row_y, vp_w - 28, 1, COLOR_EMERALD_GREEN);

            char win_str1[96], win_str2[96];
            uint32_t w_fps_i = (uint32_t)g_bench.comparison_records[winner_idx].fps_avg;
            uint32_t w_fps_d = (uint32_t)((g_bench.comparison_records[winner_idx].fps_avg - (float)w_fps_i) * 10.0f);
            snprintf(win_str1, sizeof(win_str1), "Empirical Peak Winner: Phase %u (%s)",
                     winner_idx + 1, g_bench.comparison_records[winner_idx].name);
            snprintf(win_str2, sizeof(win_str2), "Peak Throughput: %u.%u FPS | Telemetry saved to /BENCH_COMPARISON.TXT",
                     w_fps_i, w_fps_d);
            gfx_draw_string(vp_x + 20, row_y + 6, win_str1, COLOR_GOLD_ACCENT, 0);
            gfx_draw_string(vp_x + 20, row_y + 24, win_str2, COLOR_TEXT_MUTED, 0);

            // Re-run Button
            row_y += 50;
            gfx_draw_rounded_rect(vp_x + (vp_w / 2) - 110, row_y, 220, 24, 4, 0xFF27AE60);
            gfx_draw_string(vp_x + (vp_w / 2) - 90, row_y + 5, "[ Click to Re-Run Suite ]", COLOR_TEXT_WHITE, 0);

        } else {
            // ─── Render Active Symmetrical Phase (cat = cycle / 8, var = cycle % 8) ───
            int cat = g_bench.suite_cycle / 8; // 0=Gears, 1=Cubes, 2=Dynamics, 3=Sphere, 4=Fillrate
            int var = g_bench.suite_cycle % 8; // 0..7

            profiler_begin_frame();

            if (cat == 0) {
                // Category 0: 3D GLXGears
                profiler_mark_logic_start();
                g_bench.gear_angle += 2.0f;
                if (g_bench.gear_angle >= 360.0f) g_bench.gear_angle -= 360.0f;
                g_bench.gear1.angle = g_bench.gear_angle;
                g_bench.gear2.angle = -2.0f * g_bench.gear_angle - 9.0f;
                g_bench.gear3.angle = -2.0f * g_bench.gear_angle - 25.0f;

                mat4_t proj, view, rx, ry, rot_tmp, vp;
                mat4_perspective(&proj, 42.0f, (float)vp_w / (float)vp_h, 1.0f, 100.0f);
                mat4_translate(&view, 0.0f, 0.0f, -32.0f);
                mat4_rotate_x(&rx, 20.0f);
                mat4_rotate_y(&ry, 30.0f);
                mat4_mul(&rot_tmp, &rx, &ry);
                mat4_mul(&view, &view, &rot_tmp);
                mat4_mul(&vp, &proj, &view);
                profiler_mark_logic_end();

                profiler_mark_raster_start();
                raster_tile_begin_scene(vp_x, vp_y, vp_w, vp_h, gfx_get_backbuffer(), gfx_get_canvas_pitch(), 0xFF14171A);
                if (var == 6) {
                    raster_tile_set_shading(RASTER_SHADE_WIREFRAME);
                } else {
                    raster_tile_set_shading(RASTER_SHADE_GOURAUD);
                }
                gear_render(&g_bench.gear1, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, (var == 6));
                gear_render(&g_bench.gear2, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, (var == 6));
                gear_render(&g_bench.gear3, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, (var == 6));
                raster_tile_end_scene();
                profiler_mark_raster_end();

            } else if (cat == 1) {
                // Category 1: Dual Cubes
                profiler_mark_logic_start();
                int half_w = vp_w / 2;
                g_bench.cube_rotx_l += 2.0f;
                g_bench.cube_roty_l += 3.0f;
                mat4_t proj_l, view_l, rx_l, ry_l, vp_l;
                mat4_perspective(&proj_l, 45.0f, (float)half_w / (float)vp_h, 1.0f, 50.0f);
                mat4_translate(&view_l, 0.0f, 0.0f, -6.0f);
                mat4_rotate_x(&rx_l, g_bench.cube_rotx_l);
                mat4_rotate_y(&ry_l, g_bench.cube_roty_l);
                mat4_mul(&view_l, &view_l, &rx_l);
                mat4_mul(&view_l, &view_l, &ry_l);
                mat4_mul(&vp_l, &proj_l, &view_l);

                g_bench.cube_rotx_r += 3.0f;
                g_bench.cube_roty_r += 2.0f;
                mat4_t proj_r, view_r, rx_r, ry_r, vp_r;
                mat4_perspective(&proj_r, 45.0f, (float)half_w / (float)vp_h, 1.0f, 50.0f);
                mat4_translate(&view_r, 0.0f, 0.0f, -6.0f);
                mat4_rotate_x(&rx_r, g_bench.cube_rotx_r);
                mat4_rotate_y(&ry_r, g_bench.cube_roty_r);
                mat4_mul(&view_r, &view_r, &rx_r);
                mat4_mul(&view_r, &view_r, &ry_r);
                mat4_mul(&vp_r, &proj_r, &view_r);
                profiler_mark_logic_end();

                profiler_mark_raster_start();
                gfx_draw_rect(vp_x + half_w, vp_y, 2, vp_h, 0xFF34495E);

                int smp_active = ((var == 2 || var == 5) && smp_get_core_count() > 1);
                if (smp_active) {
                    s_smp_cube_job.cube = &g_bench.cube_left;
                    s_smp_cube_job.vp = vp_l;
                    s_smp_cube_job.vp_x = vp_x;
                    s_smp_cube_job.vp_y = vp_y;
                    s_smp_cube_job.vp_w = half_w;
                    s_smp_cube_job.vp_h = vp_h;
                    s_smp_cube_job.color1 = COLOR_ACCENT_CYAN;
                    s_smp_cube_job.color2 = COLOR_EMERALD_GREEN;
                    smp_dispatch(1, worker_render_cube_wire, &s_smp_cube_job);
                } else {
                    if (var == 6) {
                        mesh3d_render_wireframe(&g_bench.cube_left, &vp_l, vp_x, vp_y, half_w, vp_h, COLOR_ACCENT_CYAN, COLOR_EMERALD_GREEN);
                    } else {
                        vec3_t light = {0.577f, 0.577f, 0.577f};
                        mesh3d_render_solid(&g_bench.cube_left, &vp_l, vp_x, vp_y, half_w, vp_h, COLOR_ACCENT_CYAN, light);
                    }
                }

                if (var == 6) {
                    mesh3d_render_wireframe(&g_bench.cube_right, &vp_r, vp_x + half_w, vp_y, half_w, vp_h, 0xFFE67E22, 0xFFF39C12);
                } else {
                    vec3_t light = {0.577f, 0.577f, 0.577f};
                    mesh3d_render_solid(&g_bench.cube_right, &vp_r, vp_x + half_w, vp_y, half_w, vp_h, 0xFFE67E22, light);
                }

                if (smp_active) {
                    uint64_t w0 = read_cntvct();
                    while (!smp_is_job_done(1)) {
                        __asm__ volatile("wfe");
                    }
                    uint64_t w1 = read_cntvct();
                    uint64_t w_us = (w1 > w0 && freq > 0) ? (((w1 - w0) * 1000000ULL) / freq) : 0;
                    profiler_record_smp_wait(w_us);
                }
                profiler_mark_raster_end();

            } else if (cat == 2) {
                // Category 2: 3D Rigid Body Dynamics
                profiler_mark_logic_start();
                physics3d_world_step(0.016f);
                mat4_t proj, view, vp;
                mat4_perspective(&proj, 45.0f, (float)vp_w / (float)vp_h, 1.0f, 100.0f);
                mat4_translate(&view, 0.0f, 0.0f, -8.0f);
                mat4_t rx, ry;
                mat4_rotate_x(&rx, g_bench.view_rotx);
                mat4_rotate_y(&ry, g_bench.view_roty);
                mat4_mul(&view, &view, &rx);
                mat4_mul(&view, &view, &ry);
                profiler_mark_logic_end();

                profiler_mark_raster_start();
                // Arena Floor Wireframe Grid
                for (int gx = -4; gx <= 4; gx++) {
                    vec4_t p0 = {(float)gx * 0.6f, -1.6f, -2.4f, 1.0f};
                    vec4_t p1 = {(float)gx * 0.6f, -1.6f,  2.4f, 1.0f};
                    vec4_t tp0, tp1;
                    mat4_mul(&vp, &proj, &view);
                    mat4_mul_vec4(&tp0, &vp, &p0);
                    mat4_mul_vec4(&tp1, &vp, &p1);
                    if (tp0.w > 0.1f && tp1.w > 0.1f) {
                        float half_w_f = (float)vp_w * 0.5f, half_h_f = (float)vp_h * 0.5f;
                        int sx0 = (int)((tp0.x / tp0.w + 1.0f) * half_w_f) + vp_x;
                        int sy0 = (int)((-tp0.y / tp0.w + 1.0f) * half_h_f) + vp_y;
                        int sx1 = (int)((tp1.x / tp1.w + 1.0f) * half_w_f) + vp_x;
                        int sy1 = (int)((-tp1.y / tp1.w + 1.0f) * half_h_f) + vp_y;
                        gfx_draw_line(sx0, sy0, sx1, sy1, 0xFF34495E);
                    }
                }

                // Render rigid bodies
                for (int i = 0; i < g_physics_world.num_bodies; i++) {
                    rigid_body_t *b = &g_physics_world.bodies[i];
                    mat4_t model, mv, mvp;
                    physics3d_get_transform(b, &model);
                    mat4_mul(&mv, &view, &model);
                    mat4_mul(&mvp, &proj, &mv);
                    if (var == 6) {
                        mesh3d_render_wireframe(&g_bench.suite_cube, &mvp, vp_x, vp_y, vp_w, vp_h, b->color, 0xFFFFFFFF);
                    } else {
                        vec3_t light = {0.577f, 0.577f, 0.577f};
                        mesh3d_render_solid(&g_bench.suite_cube, &mvp, vp_x, vp_y, vp_w, vp_h, b->color, light);
                    }
                }
                profiler_mark_raster_end();

            } else if (cat == 3) {
                // Category 3: High-Poly Sphere Mesh
                profiler_mark_logic_start();
                s_sphere_rot += 3.0f;
                if (s_sphere_rot >= 360.0f) s_sphere_rot -= 360.0f;
                mat4_t proj, view, rx, ry, rot_tmp, mvp;
                mat4_perspective(&proj, 45.0f, (float)vp_w / (float)vp_h, 1.0f, 50.0f);
                mat4_translate(&view, 0.0f, 0.0f, -8.0f);
                mat4_rotate_x(&rx, 25.0f);
                mat4_rotate_y(&ry, s_sphere_rot);
                mat4_mul(&rot_tmp, &rx, &ry);
                mat4_mul(&view, &view, &rot_tmp);
                mat4_mul(&mvp, &proj, &view);
                profiler_mark_logic_end();

                profiler_mark_raster_start();
                render_sphere_mesh(&s_sphere, &mvp, vp_x, vp_y, vp_w, vp_h, (var == 6));
                profiler_mark_raster_end();

            } else if (cat == 4) {
                // Category 4: Fillrate & Alpha Blending
                profiler_mark_raster_start();
                int num_quads = (var == 6) ? 70 : 35;
                for (int i = 0; i < num_quads; i++) {
                    int qx = vp_x + 15 + (i * 23) % (vp_w - 120);
                    int qy = vp_y + 15 + (i * 19) % (vp_h - 100);
                    uint32_t col = 0x50000000 | (((i * 59) & 0xFF) << 16) | (((i * 97) & 0xFF) << 8) | ((i * 149) & 0xFF);
                    if (var == 0) {
                        gfx_blend_rect_scalar(qx, qy, 110, 85, col);
                    } else {
                        gfx_blend_rect(qx, qy, 110, 85, col);
                    }
                }
                profiler_mark_raster_end();
            }

            // Phase Completion Check (2.5s duration)
            uint64_t now_vct = read_cntvct();
            uint64_t elapsed_ticks = (now_vct >= g_bench.suite_phase_start_ticks) ?
                                     (now_vct - g_bench.suite_phase_start_ticks) : 0;
            float elapsed_sec = (freq > 0) ? ((float)elapsed_ticks / (float)freq) : ((float)g_bench.suite_ticks / 30.0f);
            g_bench.suite_phase_elapsed_sec = elapsed_sec;

            if (elapsed_ticks >= g_bench.suite_phase_duration_ticks && g_profiler.valid_sample_count >= 15) {
                profiler_compute_metrics();
                bench_comparison_record_t *rec = &g_bench.comparison_records[g_bench.suite_cycle];
                rec->fps_avg = g_profiler.fps_avg;
                rec->fps_1pct_low = g_profiler.fps_1pct_low;
                rec->frametime_avg_ms = g_profiler.frame_time_avg_ms;
                rec->render_time_ms = g_profiler.raster_avg_ms;
                rec->blit_time_ms = g_profiler.blit_avg_ms;
                rec->jitter_ms = g_profiler.frame_time_stddev_ms;
                rec->spike_count = g_profiler.spikes_50ms;
                rec->bottleneck = profiler_bottleneck_str(g_profiler.last_bottleneck);

                char dbg[64];
                snprintf(dbg, sizeof(dbg), "[PHASE-TRANSITION] Completed Phase %u/40\r\n", g_bench.suite_cycle + 1);
                uart_puts(dbg);

                g_bench.suite_scores[g_bench.suite_cycle] = (uint32_t)g_profiler.fps_avg;
                g_bench.suite_cycle++;

                if (g_bench.suite_cycle >= BENCH_SUITE_TOTAL_PHASES) {
                    uart_puts("[PHASE-TRANSITION] All 40 phases finished! Resetting VSync...\r\n");
                    gfx_vsync_set(0, 0);
                    g_bench.suite_finished = 1;
                    uart_puts("[PHASE-TRANSITION] Calling bench_unified_export_comparison...\r\n");
                    bench_unified_export_comparison();
                    uart_puts("[PHASE-TRANSITION] Calling bench_unified_export_log...\r\n");
                    bench_unified_export_log();
                    uart_puts("[PHASE-TRANSITION] Calling profiler_export_log...\r\n");
                    profiler_export_log("BENCH_PROFILER.LOG");
                    uart_puts("[PHASE-TRANSITION] Calling profiler_export_spikes...\r\n");
                    profiler_export_spikes("BENCH_SPIKES.LOG");
                    uart_puts("[PHASE-TRANSITION] ALL 40-PHASE EXPORTS COMPLETED SUCCESSFULLY!\r\n");
                } else {
                    bench_apply_suite_phase(g_bench.suite_cycle);
                }
            }

            // Suite Progress Banner & Scorecard
            gfx_blend_rect(vp_x + 16, vp_y + 10, vp_w - 32, 60, 0xDD181C20);
            gfx_draw_rect_outline(vp_x + 16, vp_y + 10, vp_w - 32, 60, COLOR_ACCENT_CYAN);

            int cur_c = (g_bench.suite_cycle < BENCH_SUITE_TOTAL_PHASES) ? g_bench.suite_cycle : (BENCH_SUITE_TOTAL_PHASES - 1);
            char cur_title[64];
            snprintf(cur_title, sizeof(cur_title), "Phase %2u/40: %s", cur_c + 1, g_bench.comparison_records[cur_c].name);
            gfx_draw_string(vp_x + 24, vp_y + 14, cur_title, COLOR_TEXT_WHITE, 0);

            char banner_telemetry[128];
            uint32_t el_i = (uint32_t)g_bench.suite_phase_elapsed_sec;
            uint32_t el_d = (uint32_t)((g_bench.suite_phase_elapsed_sec - (float)el_i) * 10.0f);
            if (el_i >= 3 && el_d >= 5) { el_i = 3; el_d = 5; }
            float cur_fps = (g_profiler.fps_avg > 0.0f) ? g_profiler.fps_avg : g_bench.perf_stats.fps_current;
            float cur_l1  = (g_profiler.fps_1pct_low > 0.0f) ? g_profiler.fps_1pct_low : cur_fps;
            uint32_t f_i = (uint32_t)cur_fps;
            uint32_t f_d = (uint32_t)((cur_fps - (float)f_i) * 10.0f);
            uint32_t l_i = (uint32_t)cur_l1;
            uint32_t l_d = (uint32_t)((cur_l1 - (float)l_i) * 10.0f);
            snprintf(banner_telemetry, sizeof(banner_telemetry),
                     "Time: %u.%us / 3.5s (Frames: %u)  |  Live: %u.%u FPS  |  1%% Low: %u.%u FPS",
                     el_i, el_d, (unsigned int)g_profiler.total_frames,
                     f_i, f_d, l_i, l_d);
            gfx_draw_string(vp_x + 24, vp_y + 28, banner_telemetry, COLOR_GOLD_ACCENT, 0);

            // Progress Bar
            int pb_w = vp_w - 48;
            uint64_t dur = g_bench.suite_phase_duration_ticks;
            if (dur == 0) dur = 1;
            int pb_val = (int)((elapsed_ticks * (uint64_t)pb_w) / dur);
            if (pb_val > pb_w) pb_val = pb_w;
            gfx_draw_rect(vp_x + 24, vp_y + 44, pb_w, 14, 0xFF2A2E33);
            gfx_draw_rect(vp_x + 24, vp_y + 44, pb_val, 14, COLOR_EMERALD_GREEN);
        }
    }

    // 4. Calculate Render & Blit Time Telemetry
    uint64_t render_end_vct = read_cntvct();
    uint64_t render_us = (render_end_vct > start_vct) ? (((render_end_vct - start_vct) * 1000000ULL) / freq) : 2500;
    g_bench.perf_stats.last_render_us = render_us;
    perf_overlay_end_frame(&g_bench.perf_stats);

    // 5. Draw RivaTuner Style Telemetry HUD Overlay
    if (!g_bench.suite_finished) {
        perf_overlay_draw(&g_bench.perf_stats, vp_x + 12, vp_y + vp_h - 176);
    }

    // 6. Presentation is performed once by the window compositor (wm_draw_animating_windows)
    // to eliminate duplicate VRAM transfer penalties.
}

// ─── Interactive Mouse Click Handler ──────────────────────────────────────────

int bench_unified_click(window_t *win, int mouse_x, int mouse_y) {
    if (!win) return 0;
    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;
    int ch = win->height - 38;
    (void)ch;

    // Check Tab Header Clicks
    int tab_w = cw / 4;
    if (mouse_y >= cy && mouse_y <= cy + 24) {
        int clicked_tab = (mouse_x - cx) / tab_w;
        if (clicked_tab >= 0 && clicked_tab < 4) {
            bench_unified_set_mode((bench_mode_t)clicked_tab);
            return 1;
        }
    }

    // Check Toolbar Clicks
    int bar_y = cy + 26;
    if (mouse_y >= bar_y + 3 && mouse_y <= bar_y + 23) {
        // Wireframe toggle
        if (mouse_x >= cx + 8 && mouse_x < cx + 100) {
            g_bench.wireframe = !g_bench.wireframe;
            wm_set_dirty();
            return 1;
        }
        // SMP toggle
        if (mouse_x >= cx + 106 && mouse_x < cx + 206) {
            g_bench.smp_mode = !g_bench.smp_mode;
            wm_set_dirty();
            return 1;
        }
        // V-Sync toggle (0 -> 30 -> 60 -> 0)
        if (mouse_x >= cx + 212 && mouse_x < cx + 307) {
            uint32_t hz = compositor_get_vsync();
            uint32_t next_hz = (hz == 0) ? 30 : (hz == 30) ? 60 : 0;
            compositor_set_vsync(next_hz);
            wm_set_dirty();
            return 1;
        }
        // Export Log & Matrix
        if (mouse_x >= cx + 313 && mouse_x < cx + 427) {
            bench_unified_export_comparison();
            bench_unified_export_log();
            wm_set_dirty();
            return 1;
        }
        // Explode / Impulse in Dynamics Mode
        if (g_bench.current_mode == BENCH_MODE_DYNAMICS && mouse_x >= cx + 433 && mouse_x < cx + 518) {
            physics3d_world_explode();
            wm_set_dirty();
            return 1;
        }
    }

    // Check Re-run Button Click in Suite Finished Scorecard
    if (g_bench.current_mode == BENCH_MODE_SUITE && g_bench.suite_finished) {
        int vp_w = cw;
        int vp_y = cy;
        int btn_y = vp_y + 44 + 20 + (8 * 19) + 6 + 44 + 50;
        if (mouse_x >= cx + (vp_w / 2) - 120 && mouse_x <= cx + (vp_w / 2) + 120 &&
            mouse_y >= btn_y - 10 && mouse_y <= btn_y + 35) {
            bench_unified_set_mode(BENCH_MODE_SUITE);
            return 1;
        }
    }

    // Viewport Click (Trigger impulse in Dynamics mode)
    if (g_bench.current_mode == BENCH_MODE_DYNAMICS && mouse_y > bar_y + 26) {
        physics3d_world_explode();
        wm_set_dirty();
        return 1;
    }

    return 0;
}

// ─── Unified Benchmark Engine Public APIs ─────────────────────────────────────

perf_stats_t* bench_unified_get_stats(void) {
    return &g_bench.perf_stats;
}

void bench_unified_trigger_impulse(void) {
    physics3d_world_explode();
    wm_set_dirty();
}

float bench_unified_get_fps(void) {
    return g_bench.perf_stats.fps_avg;
}

float bench_unified_get_frame_time(void) {
    return g_bench.perf_stats.frame_time_avg_ms;
}

void bench_unified_set_gear_angle(float angle) {
    g_bench.gear_angle = angle;
}

void bench_unified_record_smp_wait(uint64_t wait_us) {
    perf_overlay_record_smp_wait(&g_bench.perf_stats, wait_us);
}

void bench_unified_record_wm_overhead(uint64_t wm_us) {
    perf_overlay_record_wm_overhead(&g_bench.perf_stats, wm_us);
}

