#ifndef NEO_BENCH_UNIFIED_H
#define NEO_BENCH_UNIFIED_H

#include <uefi.h>
#include "../../gui/wm.h"
#include "../math/gears3d.h"
#include "../math/math3d.h"
#include "../physics/physics3d.h"
#include "perf_overlay.h"

typedef enum {
    PHASE_IDLE = 0,
    PHASE_CPU_SW = 1,
    PHASE_ZERO_RAM = 2,
    PHASE_VIRTIO_HW = 3,
    PHASE_SMP_4C = 4,
    PHASE_L1_TILE = 5,
    PHASE_LUAGL_PHYSICS = 6
} bench_phase_t;

typedef enum {
    BENCH_MODE_GEARS = 0,     // Mode 1: Authentic 3D GLXGears with Z-Buffer & Lighting
    BENCH_MODE_CUBES_SMP = 1, // Mode 2: Dual Cubes SMP (Core 1 SIMD stress, Core 2 Mem stress)
    BENCH_MODE_DYNAMICS = 2,  // Mode 3: 3D Multi-Body Rigid Dynamics & Collisions
    BENCH_MODE_SUITE = 3      // Mode 4: Automated 10-Phase Scientific Comparison Suite
} bench_mode_t;

typedef enum {
    BENCH_RES_360P = 0,   // 640x360 (16:9 widescreen baseline)
    BENCH_RES_480P = 1,   // 640x480 (4:3)
    BENCH_RES_720P = 2,   // 1280x720 (Native 720p 16:9)
    BENCH_RES_CUSTOM = 3
} bench_res_preset_t;

typedef struct {
    char     name[40];
    float    fps_avg;
    float    fps_1pct_low;
    float    frametime_avg_ms;
    float    render_time_ms;
    float    blit_time_ms;
    float    jitter_ms;
    uint32_t spike_count;
} bench_comparison_record_t;

typedef struct {
    int          active;
    uint32_t     win_id;
    bench_mode_t current_mode;
    int          wireframe;
    int          smp_mode;
    uint32_t     vsync_preset; // 0=Uncapped, 30, 60, 120

    // Mode 0: Authentic 3D GLXGears
    gear_mesh_t  gear1; // Red (20 teeth)
    gear_mesh_t  gear2; // Green (10 teeth)
    gear_mesh_t  gear3; // Blue (10 teeth)
    float        view_rotx;
    float        view_roty;
    float        gear_angle;
    int          dragging;
    int          last_mouse_x;
    int          last_mouse_y;
    zbuffer_t    zbuffer;

    // Mode 1: Dual Cubes SMP
    mesh3d_cube_t cube_left;   // Wireframe, Core 1
    mesh3d_cube_t cube_right;  // Solid, Core 2
    float         cube_rotx_l, cube_roty_l, cube_rotz_l;
    float         cube_rotx_r, cube_roty_r, cube_rotz_r;
    uint64_t      core1_ops;
    uint64_t      core2_ops;
    int           core1_ready;
    int           core2_ready;

#define BENCH_SUITE_TOTAL_PHASES 16

    // Mode 3: Automated Multi-Phase Scientific Comparison Suite
    bench_phase_t suite_phase;
    uint32_t      suite_cycle;
    uint32_t      suite_ticks;
    uint64_t      suite_phase_start_ticks;
    uint64_t      suite_phase_duration_ticks;
    float         suite_phase_elapsed_sec;
    mesh3d_cube_t suite_cube;
    rigid_body_t  suite_physics;
    uint32_t      suite_tex_neon[64 * 64];
    uint32_t      suite_tex_check[64 * 64];
    uint32_t      suite_scores[BENCH_SUITE_TOTAL_PHASES];
    int           suite_finished;
    bench_comparison_record_t comparison_records[BENCH_SUITE_TOTAL_PHASES];

    // Viewport & Fixed Resolution Configuration (Decoupled from window size)
    uint32_t      res_preset; // 0=360p (640x360), 1=480p (640x480), 2=720p (1280x720), 3=Custom
    uint32_t      render_w;
    uint32_t      render_h;

    // RTSS-style Performance Telemetry (O(N) deterministic histogram bucketing)
    perf_stats_t perf_stats;
} bench_unified_t;

extern bench_unified_t g_bench;

void bench_unified_init(void);
int  bench_unified_start(bench_mode_t initial_mode);
void bench_unified_stop(void);
int  bench_unified_is_active(void);
void bench_unified_set_mode(bench_mode_t mode);
void bench_unified_set_resolution(uint32_t w, uint32_t h);
void bench_unified_set_resolution_preset(uint32_t preset);
void bench_unified_render(window_t *win, void *user_data);
int  bench_unified_click(window_t *win, int mouse_x, int mouse_y);
int  bench_unified_export_log(void);
int  bench_unified_export_comparison(void);
float bench_unified_get_fps(void);
float bench_unified_get_frame_time(void);
void  bench_unified_set_gear_angle(float angle);
perf_stats_t* bench_unified_get_stats(void);
void  bench_unified_trigger_impulse(void);
void  bench_unified_record_blit(uint64_t blit_us);
void  bench_unified_record_smp_wait(uint64_t wait_us);
void  bench_unified_record_wm_overhead(uint64_t wm_us);

#endif // NEO_BENCH_UNIFIED_H
