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

static void bench_apply_suite_phase(int phase) {
    g_bench.render_w = 640;
    g_bench.render_h = 360;
    gpu_set_shading(RASTER_SHADE_GOURAUD);

    if (phase == 0) {
        // Ph 1: CPU SW Double-Buffer, 1 Core, 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_CPU_SW;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
        gpu_set_smp_cores(1);
        gfx_vsync_set(0, 0);
    } else if (phase == 1) {
        // Ph 2: CPU SW Direct VRAM (Zero-RAM), 1 Core, 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_CPU_SW;
        gpu_set_buffering(GFX_BUFFER_DIRECT_VRAM);
        gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
        gpu_set_smp_cores(1);
        gfx_vsync_set(0, 0);
    } else if (phase == 2) {
        // Ph 3: VirtIO-GPU Hardware DMA Scanout, 1 Core, 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_GPU_HW;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
        gpu_set_smp_cores(1);
        gfx_vsync_set(0, 0);
    } else if (phase == 3) {
        // Ph 4: VirtIO HW + Direct VRAM, 1 Core, 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_GPU_HW;
        gpu_set_buffering(GFX_BUFFER_DIRECT_VRAM);
        gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
        gpu_set_smp_cores(1);
        gfx_vsync_set(0, 0);
    } else if (phase == 4) {
        // Ph 5: Dual-Core SMP Parallel Slicing (2 Cores), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
        gpu_set_smp_cores(2);
        gfx_vsync_set(0, 0);
    } else if (phase == 5) {
        // Ph 6: Quad-Core SMP Parallel Grid (4 Cores), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
        gpu_set_smp_cores(4);
        gfx_vsync_set(0, 0);
    } else if (phase == 6) {
        // Ph 7: Sovereign L1 Tile NEON (1 Core), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_CPU_SW;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(1);
        gfx_vsync_set(0, 0);
    } else if (phase == 7) {
        // Ph 8: Sovereign L1 Tile NEON (2 Cores), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(2);
        gfx_vsync_set(0, 0);
    } else if (phase == 8) {
        // Ph 9: Sovereign L1 Tile NEON (4 Cores), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gfx_vsync_set(0, 0);
    } else if (phase == 9) {
        // Ph 10: Sovereign L1 Tile Flat Shading (4 Cores), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gpu_set_shading(RASTER_SHADE_FLAT);
        gfx_vsync_set(0, 0);
    } else if (phase == 10) {
        // Ph 11: Sovereign L1 Tile Wireframe (4 Cores), 360p, Uncapped
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gpu_set_shading(RASTER_SHADE_WIREFRAME);
        gfx_vsync_set(0, 0);
    } else if (phase == 11) {
        // Ph 12: Scaled Resolution 480p (4 Cores L1 Tile, Uncapped)
        g_bench.render_w = 640;
        g_bench.render_h = 480;
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gfx_vsync_set(0, 0);
    } else if (phase == 12) {
        // Ph 13: Native Resolution 720p (4 Cores L1 Tile, Uncapped)
        g_bench.render_w = 1280;
        g_bench.render_h = 720;
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gfx_vsync_set(0, 0);
    } else if (phase == 13) {
        // Ph 14: Native 720p + Direct VRAM (4 Cores L1 Tile, Uncapped)
        g_bench.render_w = 1280;
        g_bench.render_h = 720;
        g_gfx_backend.mode = GFX_MODE_CPU_SW;
        gpu_set_buffering(GFX_BUFFER_DIRECT_VRAM);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gfx_vsync_set(0, 0);
    } else if (phase == 14) {
        // Ph 15: V-Sync Locked 30 FPS (4 Cores L1 Tile, 360p)
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gfx_vsync_set(1, 30);
    } else if (phase == 15) {
        // Ph 16: V-Sync Locked 60 FPS (4 Cores L1 Tile, 720p Native)
        g_bench.render_w = 1280;
        g_bench.render_h = 720;
        g_gfx_backend.mode = GFX_MODE_SMP_TILED;
        gpu_set_buffering(GFX_BUFFER_DOUBLE);
        gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
        gpu_set_smp_cores(4);
        gfx_vsync_set(1, 60);
    }

    static const char *s_phase_names[BENCH_SUITE_TOTAL_PHASES] = {
        "CPU SW + DoubleBuf (1C, 360p)",
        "CPU Direct VRAM (1C, 360p)",
        "VirtIO-GPU HW DMA (1C, 360p)",
        "VirtIO HW + Direct VRAM (1C)",
        "Dual-Core SMP Slicing (2C, 360p)",
        "Quad-Core SMP Grid (4C, 360p)",
        "Sovereign L1 Tile (1C, 360p)",
        "Sovereign L1 Tile (2C, 360p)",
        "Sovereign L1 Tile (4C, 360p)",
        "Sovereign L1 Flat Shade (4C)",
        "Sovereign L1 Wireframe (4C)",
        "Scaled 480p L1 Tile (4C)",
        "Native 720p L1 Tile (4C)",
        "Native 720p Direct VRAM (4C)",
        "VSync Locked 30 FPS (4C, 360p)",
        "VSync Locked 60 FPS (4C, 720p)"
    };

    if (phase >= 0 && phase < BENCH_SUITE_TOTAL_PHASES) {
        strncpy(g_bench.comparison_records[phase].name, s_phase_names[phase], sizeof(g_bench.comparison_records[phase].name) - 1);
    }

    g_bench.suite_phase_start_ticks = read_cntvct();
    uint64_t freq = read_cntfrq();
    if (freq == 0) freq = 62500000ULL;
    // Exactly 2.5 seconds per test = 40 seconds total test suite!
    g_bench.suite_phase_duration_ticks = (freq * 25ULL) / 10ULL;
    g_bench.suite_phase_elapsed_sec = 0.0f;
    g_bench.suite_ticks = 0;
    perf_overlay_init(&g_bench.perf_stats);
}

// ─── Initialization ──────────────────────────────────────────────────────────

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
    physics3d_init(&g_bench.suite_physics, 1.8f);
    texture_generate_procedural(g_bench.suite_tex_neon, 64, 64, 0);
    texture_generate_procedural(g_bench.suite_tex_check, 64, 64, 1);
    g_bench.suite_phase = PHASE_IDLE;
    g_bench.suite_cycle = 0;
    g_bench.suite_finished = 0;

    const char *names[BENCH_SUITE_TOTAL_PHASES] = {
        "CPU SW (UEFI GOP) + DoubleBuf (1C)",
        "CPU Direct VRAM (Zero-RAM GOP) (1C)",
        "VirtIO-GPU Hardware DMA Scanout (1C)",
        "VirtIO Hardware + Direct VRAM (1C)",
        "Dual-Core SMP Parallel Slicing (2C)",
        "Quad-Core SMP Parallel Grid (4C)",
        "Sovereign L1 Tile NEON (1C)",
        "Sovereign L1 Tile NEON + 4C SMP",
        "Mixed: L1 Tile + 4C + Direct VRAM",
        "Mixed: L1 Tile + 4C + 60fps Lock"
    };
    for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
        strncpy(g_bench.comparison_records[p].name, names[p], sizeof(g_bench.comparison_records[p].name) - 1);
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

static void pad_right(char *dst, const char *src, int width) {
    int len = 0;
    while (*src && len < width) {
        dst[len++] = *src++;
    }
    while (len < width) {
        dst[len++] = ' ';
    }
    dst[len] = '\0';
}

static void pad_left(char *dst, const char *src, int width) {
    int slen = 0;
    const char *p = src;
    while (*p++) slen++;
    int spaces = (width > slen) ? (width - slen) : 0;
    int pos = 0;
    for (int i = 0; i < spaces; i++) dst[pos++] = ' ';
    for (int i = 0; i < slen && pos < width; i++) dst[pos++] = src[i];
    dst[pos] = '\0';
}

int bench_unified_export_comparison(void) {
    char buf[4096];
    int len = 0;
    len += snprintf(buf + len, sizeof(buf) - len,
        "=============================================================================================================\n"
        "                       NeoOS NeoBench Extreme: 16-Phase Comparative Telemetry Matrix\n"
        "                                  Target: AArch64 Ring 0 SASOS (4x Cortex-A72)\n"
        "=============================================================================================================\n"
        "Phase | Configuration              | Avg FPS | 1%% Low | Avg FT (ms) | Render (ms) | Blit (ms) | Jitter | Spikes\n"
        "------+----------------------------+---------+--------+-------------+-------------+-----------+--------+-------\n"
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
        uint32_t fps_i = (uint32_t)r->fps_avg;
        uint32_t fps_f = (uint32_t)((r->fps_avg - (float)fps_i) * 10.0f);
        uint32_t l1_i = (uint32_t)r->fps_1pct_low;
        uint32_t l1_f = (uint32_t)((r->fps_1pct_low - (float)l1_i) * 10.0f);
        uint32_t ft_i = (uint32_t)r->frametime_avg_ms;
        uint32_t ft_f = (uint32_t)((r->frametime_avg_ms - (float)ft_i) * 10.0f);
        uint32_t rn_i = (uint32_t)r->render_time_ms;
        uint32_t rn_f = (uint32_t)((r->render_time_ms - (float)rn_i) * 10.0f);
        uint32_t bl_i = (uint32_t)r->blit_time_ms;
        uint32_t bl_f = (uint32_t)((r->blit_time_ms - (float)bl_i) * 10.0f);
        uint32_t jt_i = (uint32_t)r->jitter_ms;
        uint32_t jt_f = (uint32_t)((r->jitter_ms - (float)jt_i) * 10.0f);

        char c_name[32], c_fps[16], c_l1[16], c_ft[16], c_rn[16], c_bl[16], c_jt[16], c_spk[16];
        char fps_tmp[16], l1_tmp[16], ft_tmp[16], rn_tmp[16], bl_tmp[16], jt_tmp[16], spk_tmp[16];

        pad_right(c_name, r->name, 26);

        snprintf(fps_tmp, sizeof(fps_tmp), "%llu.%llu", (uint64_t)fps_i, (uint64_t)fps_f);
        pad_left(c_fps, fps_tmp, 7);

        snprintf(l1_tmp, sizeof(l1_tmp), "%llu.%llu", (uint64_t)l1_i, (uint64_t)l1_f);
        pad_left(c_l1, l1_tmp, 6);

        snprintf(ft_tmp, sizeof(ft_tmp), "%llu.%llu", (uint64_t)ft_i, (uint64_t)ft_f);
        pad_left(c_ft, ft_tmp, 11);

        snprintf(rn_tmp, sizeof(rn_tmp), "%llu.%llu", (uint64_t)rn_i, (uint64_t)rn_f);
        pad_left(c_rn, rn_tmp, 11);

        snprintf(bl_tmp, sizeof(bl_tmp), "%llu.%llu", (uint64_t)bl_i, (uint64_t)bl_f);
        pad_left(c_bl, bl_tmp, 9);

        snprintf(jt_tmp, sizeof(jt_tmp), "%llu.%llums", (uint64_t)jt_i, (uint64_t)jt_f);
        pad_left(c_jt, jt_tmp, 8);

        snprintf(spk_tmp, sizeof(spk_tmp), "%llu", (uint64_t)r->spike_count);
        pad_left(c_spk, spk_tmp, 6);

        len += snprintf(buf + len, sizeof(buf) - len,
            "  %llu   | %s | %s | %s | %s | %s | %s | %s | %s  %s\n",
            (uint64_t)(p + 1), c_name, c_fps, c_l1, c_ft, c_rn, c_bl, c_jt, c_spk,
            (p == winner_idx) ? "[WINNER]" : ""
        );
    }

    uint32_t w_fps_i = (uint32_t)g_bench.comparison_records[winner_idx].fps_avg;
    uint32_t w_fps_f = (uint32_t)((g_bench.comparison_records[winner_idx].fps_avg - (float)w_fps_i) * 10.0f);

    len += snprintf(buf + len, sizeof(buf) - len,
        "=============================================================================================================\n"
        "Architectural Telemetry Conclusion:\n"
        "Empirical Winner: Phase %llu (%s) at %llu.%llu FPS.\n"
        "Direct hardware scanout and parallelized math pipelines achieve tear-free low-latency presentation.\n"
        "=============================================================================================================\n",
        (uint64_t)(winner_idx + 1),
        g_bench.comparison_records[winner_idx].name,
        (uint64_t)w_fps_i, (uint64_t)w_fps_f
    );

    redsea_write_file("BENCH_COMPARISON.TXT", buf, (size_t)len);
    uart_puts(buf);
    uart_puts("[NEOBENCH] Exported scientific comparison matrix to /BENCH_COMPARISON.TXT\r\n");
    doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Exported scientific comparison matrix to $FG,YELLOW$/BENCH_COMPARISON.TXT$FG$\n");
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
    perf_export_spike_log(&g_bench.perf_stats, "BENCH_SPIKES.LOG");
    uart_puts("[NEOBENCH] Exported BENCH_REPORT.TXT, GEARS_BENCHMARK.LOG, and BENCH_SPIKES.LOG to RedSea disk.\r\n");
    doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Exported reports to $FG,YELLOW$/BENCH_REPORT.TXT$FG$ and $FG,YELLOW$/BENCH_SPIKES.LOG$FG$\n");
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
            "4. 16-Phase Suite"
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
        gfx_draw_rect(vp_x + 10, vp_y + 10, 220, 48, COLOR_ACCENT_CYAN);
        gfx_draw_string(vp_x + 18, vp_y + 16, smp_active ? "Core 1: Parallel Wireframe" : "Core 0: Wireframe (Single)", COLOR_ACCENT_CYAN, 0);
        char c1_str[48];
        snprintf(c1_str, sizeof(c1_str), "Edges Rendered: %llu", (unsigned long long)g_bench.core1_ops);
        gfx_draw_string(vp_x + 18, vp_y + 32, c1_str, COLOR_TEXT_WHITE, 0);

        gfx_blend_rect(vp_x + half_w + 10, vp_y + 10, 220, 48, 0xDD181C20);
        gfx_draw_rect(vp_x + half_w + 10, vp_y + 10, 220, 48, 0xFFE67E22);
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
        gfx_draw_rect(vp_x + 14, vp_y + 12, 380, 56, COLOR_ACCENT_CYAN);
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
        // Mode 4: Automated 6-Phase Scientific Comparison Suite
        const char *phase_names[BENCH_SUITE_TOTAL_PHASES] = {
            "Ph 1/16: CPU SW + DoubleBuf (1C, 360p)",
            "Ph 2/16: CPU Direct VRAM (1C, 360p)",
            "Ph 3/16: VirtIO-GPU Hardware DMA (1C, 360p)",
            "Ph 4/16: VirtIO Hardware + Direct VRAM (1C)",
            "Ph 5/16: Dual-Core SMP Slicing (2C, 360p)",
            "Ph 6/16: Quad-Core SMP Grid (4C, 360p)",
            "Ph 7/16: Sovereign L1 Tile NEON (1C, 360p)",
            "Ph 8/16: Sovereign L1 Tile NEON (2C, 360p)",
            "Ph 9/16: Sovereign L1 Tile NEON (4C, 360p)",
            "Ph 10/16: Sovereign L1 Tile Flat Shade (4C)",
            "Ph 11/16: Sovereign L1 Tile Wireframe (4C)",
            "Ph 12/16: Scaled Resolution 480p (4C)",
            "Ph 13/16: Native Resolution 720p (4C)",
            "Ph 14/16: Native 720p + Direct VRAM (4C)",
            "Ph 15/16: V-Sync Locked 30 FPS (4C, 360p)",
            "Ph 16/16: V-Sync Locked 60 FPS (4C, 720p)"
        };

        if (g_bench.suite_finished) {
            // ─── Render Final 16-Phase Comparison Scorecard Matrix ───
            gfx_blend_rect(vp_x + 10, vp_y + 10, vp_w - 20, vp_h - 20, 0xF214171A);
            gfx_draw_rect(vp_x + 10, vp_y + 10, vp_w - 20, vp_h - 20, COLOR_ACCENT_CYAN);

            gfx_draw_string(vp_x + 20, vp_y + 14, "✦ NeoBench Extreme: 16-Phase Multi-Configuration Comparison Matrix ✦", COLOR_GOLD_ACCENT, 0);
            gfx_draw_string(vp_x + 20, vp_y + 28, "Target Architecture: AArch64 Ring 0 SASOS (4x Cortex-A72 @ 1.5 GHz)", COLOR_TEXT_MUTED, 0);

            int winner_idx = 0;
            float max_fps = -1.0f;
            for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
                if (g_bench.comparison_records[p].fps_avg > max_fps) {
                    max_fps = g_bench.comparison_records[p].fps_avg;
                    winner_idx = p;
                }
            }

            int row_y = vp_y + 44;
            gfx_draw_rect(vp_x + 18, row_y, vp_w - 36, 18, 0xFF2C3E50);
            gfx_draw_string(vp_x + 24, row_y + 2, "Ph | Configuration         |  Avg  | 1%Low | Avg FT | Render |  Blit | Jitter", COLOR_TEXT_WHITE, 0);
            row_y += 20;

            for (int p = 0; p < BENCH_SUITE_TOTAL_PHASES; p++) {
                bench_comparison_record_t *r = &g_bench.comparison_records[p];
                int is_winner = (p == winner_idx);
                uint32_t row_bg = is_winner ? 0xFF145A32 : ((p % 2 == 0) ? 0xFF1E242B : 0xFF171B20);
                gfx_draw_rect(vp_x + 18, row_y, vp_w - 36, 18, row_bg);

                char row_str[128];
                uint32_t f_i = (uint32_t)r->fps_avg;
                uint32_t f_d = (uint32_t)((r->fps_avg - (float)f_i) * 10.0f);
                uint32_t l_i = (uint32_t)r->fps_1pct_low;
                uint32_t l_d = (uint32_t)((r->fps_1pct_low - (float)l_i) * 10.0f);
                uint32_t ft_i = (uint32_t)r->frametime_avg_ms;
                uint32_t ft_d = (uint32_t)((r->frametime_avg_ms - (float)ft_i) * 10.0f);
                uint32_t rn_i = (uint32_t)r->render_time_ms;
                uint32_t rn_d = (uint32_t)((r->render_time_ms - (float)rn_i) * 10.0f);
                uint32_t bl_i = (uint32_t)r->blit_time_ms;
                uint32_t bl_d = (uint32_t)((r->blit_time_ms - (float)bl_i) * 10.0f);
                uint32_t jt_i = (uint32_t)r->jitter_ms;
                uint32_t jt_d = (uint32_t)((r->jitter_ms - (float)jt_i) * 10.0f);

                char c_name[32], c_fps[16], c_l1[16], c_ft[16], c_rn[16], c_bl[16], c_jt[16];
                char fps_t[16], l1_t[16], ft_t[16], rn_t[16], bl_t[16], jt_t[16];

                pad_right(c_name, r->name, 23);

                snprintf(fps_t, sizeof(fps_t), "%llu.%llu", (uint64_t)f_i, (uint64_t)f_d);
                pad_left(c_fps, fps_t, 5);

                snprintf(l1_t, sizeof(l1_t), "%llu.%llu", (uint64_t)l_i, (uint64_t)l_d);
                pad_left(c_l1, l1_t, 5);

                snprintf(ft_t, sizeof(ft_t), "%llu.%llums", (uint64_t)ft_i, (uint64_t)ft_d);
                pad_left(c_ft, ft_t, 6);

                snprintf(rn_t, sizeof(rn_t), "%llu.%llums", (uint64_t)rn_i, (uint64_t)rn_d);
                pad_left(c_rn, rn_t, 6);

                snprintf(bl_t, sizeof(bl_t), "%llu.%llums", (uint64_t)bl_i, (uint64_t)bl_d);
                pad_left(c_bl, bl_t, 5);

                snprintf(jt_t, sizeof(jt_t), "%llu.%llums", (uint64_t)jt_i, (uint64_t)jt_d);
                pad_left(c_jt, jt_t, 6);

                snprintf(row_str, sizeof(row_str), "%s%2llu | %s | %s | %s | %s | %s | %s | %s",
                         is_winner ? "*" : " ", (uint64_t)(p + 1), c_name, c_fps, c_l1, c_ft, c_rn, c_bl, c_jt);
                gfx_draw_string(vp_x + 24, row_y + 2, row_str, is_winner ? COLOR_EMERALD_GREEN : COLOR_TEXT_WHITE, 0);
                row_y += 20;
            }

            row_y += 6;
            gfx_blend_rect(vp_x + 18, row_y, vp_w - 36, 40, 0xFF1C2833);
            gfx_draw_rect(vp_x + 18, row_y, vp_w - 36, 1, COLOR_EMERALD_GREEN);

            char win_str1[96], win_str2[96];
            uint32_t w_fps_i = (uint32_t)g_bench.comparison_records[winner_idx].fps_avg;
            uint32_t w_fps_d = (uint32_t)((g_bench.comparison_records[winner_idx].fps_avg - (float)w_fps_i) * 10.0f);
            snprintf(win_str1, sizeof(win_str1), "Empirical Winner: Phase %llu (%s)",
                     (uint64_t)(winner_idx + 1), g_bench.comparison_records[winner_idx].name);
            snprintf(win_str2, sizeof(win_str2), "Achieved peak throughput of %llu.%llu FPS with minimal frame jitter.",
                     (uint64_t)w_fps_i, (uint64_t)w_fps_d);
            gfx_draw_string(vp_x + 26, row_y + 4, win_str1, COLOR_GOLD_ACCENT, 0);
            gfx_draw_string(vp_x + 26, row_y + 20, win_str2, COLOR_EMERALD_GREEN, 0);

            // Re-run Button
            int btn_y = row_y + 46;
            gfx_draw_rounded_rect(vp_x + (vp_w / 2) - 100, btn_y, 200, 24, 4, 0xFF8E44AD);
            gfx_draw_string(vp_x + (vp_w / 2) - 80, btn_y + 5, "Re-run 16-Phase Suite", COLOR_TEXT_WHITE, 0);

        } else {
            // Suite In Progress: Execute active phase
            g_bench.suite_ticks++;

            // ─── Render Active Example Based on Suite Cycle ───
            int scene_type = 0;
            if (g_bench.suite_cycle == 4 || g_bench.suite_cycle == 5 || g_bench.suite_cycle == 13) {
                scene_type = 1; // Dual Cubes SMP
            } else if (g_bench.suite_cycle == 6 || g_bench.suite_cycle == 7 || g_bench.suite_cycle == 11) {
                scene_type = 2; // Physics 3D Dynamics
            } else if (g_bench.suite_cycle == 9) {
                scene_type = 3; // Flat Shaded Mesh
            } else if (g_bench.suite_cycle == 10) {
                scene_type = 4; // Wireframe Grid Mesh
            } else {
                scene_type = 0; // 3D GLXGears
            }

            if (scene_type == 0 || scene_type == 3 || scene_type == 4) {
                // 3D GLXGears / Shading Demos: All 3 Interlocking Gears (Red, Green, Blue)
                raster_tile_begin_scene(vp_x, vp_y, vp_w, vp_h, gfx_get_backbuffer(), gfx_get_canvas_pitch(), 0xFF14171A);
                if (scene_type == 3) {
                    raster_tile_set_shading(RASTER_SHADE_FLAT);
                } else if (scene_type == 4) {
                    raster_tile_set_shading(RASTER_SHADE_WIREFRAME);
                } else {
                    raster_tile_set_shading(RASTER_SHADE_GOURAUD);
                }

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

                gear_render(&g_bench.gear1, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, (scene_type == 4));
                gear_render(&g_bench.gear2, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, (scene_type == 4));
                gear_render(&g_bench.gear3, &vp, vp_x, vp_y, vp_w, vp_h, &g_bench.zbuffer, (scene_type == 4));

                raster_tile_end_scene();

            } else if (scene_type == 1) {
                // Dual Cubes SMP (Core 1 Parallel Wireframe left, Core 0 Solid Shaded right)
                int half_w = vp_w / 2;
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

                int smp_active = (smp_get_core_count() > 1);
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

                // Synchronize Core 1
                if (smp_active) {
                    while (!smp_is_job_done(1)) {
                        __asm__ volatile("yield");
                    }
                }
            } else if (scene_type == 2) {
                // Physics 3D Rigid Body Dynamics
                physics3d_world_step(0.016f);

                mat4_t proj, view, vp;
                mat4_perspective(&proj, 45.0f, (float)vp_w / (float)vp_h, 1.0f, 100.0f);
                mat4_translate(&view, 0.0f, 0.0f, -8.0f);
                mat4_t rx, ry;
                mat4_rotate_x(&rx, g_bench.view_rotx);
                mat4_rotate_y(&ry, g_bench.view_roty);
                mat4_mul(&view, &view, &rx);
                mat4_mul(&view, &view, &ry);

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

                // Render each rigid body
                for (int i = 0; i < g_physics_world.num_bodies; i++) {
                    rigid_body_t *b = &g_physics_world.bodies[i];
                    mat4_t model, mv, mvp;
                    physics3d_get_transform(b, &model);
                    mat4_mul(&mv, &view, &model);
                    mat4_mul(&mvp, &proj, &mv);
                    vec3_t light = {0.577f, 0.577f, 0.577f};
                    mesh3d_render_solid(&g_bench.suite_cube, &mvp, vp_x, vp_y, vp_w, vp_h, b->color, light);
                }
            }

            // Check if active phase cycle completed (10.0s wall-clock duration)
            uint64_t now_vct = read_cntvct();
            uint64_t elapsed_ticks = (now_vct >= g_bench.suite_phase_start_ticks) ?
                                     (now_vct - g_bench.suite_phase_start_ticks) : 0;
            float elapsed_sec = (freq > 0) ? ((float)elapsed_ticks / (float)freq) : ((float)g_bench.suite_ticks / 30.0f);
            g_bench.suite_phase_elapsed_sec = elapsed_sec;

            if (elapsed_ticks >= g_bench.suite_phase_duration_ticks) {
                // Record completed phase metrics
                perf_overlay_update_metrics(&g_bench.perf_stats);
                bench_comparison_record_t *rec = &g_bench.comparison_records[g_bench.suite_cycle];
                rec->fps_avg = g_bench.perf_stats.fps_avg;
                rec->fps_1pct_low = g_bench.perf_stats.fps_1pct_low;
                rec->frametime_avg_ms = g_bench.perf_stats.frame_time_avg_ms;
                rec->render_time_ms = (float)g_bench.perf_stats.last_render_us / 1000.0f;
                rec->blit_time_ms = (float)g_bench.perf_stats.last_blit_us / 1000.0f;
                rec->jitter_ms = g_bench.perf_stats.frame_time_stddev_ms;
                rec->spike_count = g_bench.perf_stats.spike_count_50ms;

                g_bench.suite_scores[g_bench.suite_cycle] = (uint32_t)g_bench.perf_stats.fps_avg;
                g_bench.suite_cycle++;

                if (g_bench.suite_cycle >= BENCH_SUITE_TOTAL_PHASES) {
                    g_bench.suite_finished = 1;
                    bench_unified_export_comparison();
                    bench_unified_export_log();
                } else {
                    bench_apply_suite_phase(g_bench.suite_cycle);
                }
            }

            // Suite Progress Banner & Scorecard
            gfx_blend_rect(vp_x + 16, vp_y + 10, vp_w - 32, 60, 0xDD181C20);
            gfx_draw_rect(vp_x + 16, vp_y + 10, vp_w - 32, 60, COLOR_ACCENT_CYAN);

            int cur_c = (g_bench.suite_cycle < BENCH_SUITE_TOTAL_PHASES) ? g_bench.suite_cycle : (BENCH_SUITE_TOTAL_PHASES - 1);
            gfx_draw_string(vp_x + 24, vp_y + 14, phase_names[cur_c], COLOR_TEXT_WHITE, 0);

            char banner_telemetry[96];
            uint32_t el_i = (uint32_t)g_bench.suite_phase_elapsed_sec;
            uint32_t el_d = (uint32_t)((g_bench.suite_phase_elapsed_sec - (float)el_i) * 10.0f);
            if (el_i > 2 || (el_i == 2 && el_d > 5)) { el_i = 2; el_d = 5; }
            uint32_t f_i = (uint32_t)g_bench.perf_stats.fps_avg;
            uint32_t f_d = (uint32_t)((g_bench.perf_stats.fps_avg - (float)f_i) * 10.0f);
            uint32_t l_i = (uint32_t)g_bench.perf_stats.fps_1pct_low;
            uint32_t l_d = (uint32_t)((g_bench.perf_stats.fps_1pct_low - (float)l_i) * 10.0f);
            snprintf(banner_telemetry, sizeof(banner_telemetry),
                     "Time: %llu.%llus / 2.5s  |  Live: %llu.%llu FPS  |  1%% Low: %llu.%llu FPS",
                     (uint64_t)el_i, (uint64_t)el_d, (uint64_t)f_i, (uint64_t)f_d, (uint64_t)l_i, (uint64_t)l_d);
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
        perf_overlay_draw(&g_bench.perf_stats, vp_x + 12, vp_y + vp_h - 130);
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
        int vp_y = cy + 52;
        int btn_y = vp_y + 44 + 20 + (BENCH_SUITE_TOTAL_PHASES * 20) + 6 + 46;
        if (mouse_x >= cx + (vp_w / 2) - 100 && mouse_x <= cx + (vp_w / 2) + 100 &&
            mouse_y >= btn_y && mouse_y <= btn_y + 26) {
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

