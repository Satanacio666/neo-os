#ifndef NEO_BENCH_SUITE_H
#define NEO_BENCH_SUITE_H

#include <uefi.h>
#include "../../gui/wm.h"
#include "../math/math3d.h"
#include "../physics/physics3d.h"
#include "../../drivers/gpu/gfx_backend.h"

// 6 Test Cycles
typedef enum {
    CYCLE_WIREFRAME_GEOM = 0,
    CYCLE_POLYGON_FILL   = 1,
    CYCLE_UV_TEXTURES    = 2,
    CYCLE_GOURAUD_PHONG  = 3,
    CYCLE_CLIPPING_STRESS= 4,
    CYCLE_RIGID_PHYSICS  = 5,
    CYCLE_COUNT          = 6
} bench_cycle_t;

// Benchmark Execution Phases
typedef enum {
    PHASE_IDLE           = -1,
    PHASE_SINGLE_1T      = 0, // Single Window, Single Core (Core 1)
    PHASE_SINGLE_3T      = 1, // Single Window, Multi-Threaded (Cores 1, 2, 3)
    PHASE_DUAL_SMP       = 2, // Dual Windows (Core 1 & Core 2)
    PHASE_HW_ACCEL       = 3, // Hardware Accelerated Backend
    PHASE_COMPLETE       = 4  // Report & Visual Charts
} bench_phase_t;

typedef struct {
    uint32_t fps;
    uint64_t frame_time_us;
    uint64_t throughput;
} cycle_stat_t;

typedef struct {
    cycle_stat_t stats[CYCLE_COUNT];
    uint32_t     avg_fps;
    uint64_t     total_frames;
} phase_record_t;

typedef struct {
    int            active;
    bench_phase_t  current_phase;
    bench_cycle_t  current_cycle;
    uint64_t       cycle_start_tick;
    uint32_t       ticks_per_cycle;
    uint64_t       cycle_frame_count;
    uint64_t       total_suite_frames;
    
    // Geometry & Physics instances
    mesh3d_cube_t  cube;
    rigid_body_t   physics_body;
    float          cube_rot_x;
    float          cube_rot_y;
    float          cube_rot_z;
    float          cube_scale;
    float          clip_offset_x;
    float          clip_offset_y;
    
    // Procedural textures
    uint32_t       texture_neon[64 * 64];
    uint32_t       texture_check[64 * 64];
    
    // Performance Records for comparison
    phase_record_t record_single_1t;
    phase_record_t record_single_3t;
    phase_record_t record_dual_smp;
    phase_record_t record_hw_accel;
    
    // Window handles
    uint32_t       win_main_id;
    uint32_t       win_sec_id;
} bench_suite_t;

extern bench_suite_t g_bench_suite;

void bench_suite_init(void);
int  bench_suite_start(void);
void bench_suite_stop(void);
int  bench_suite_is_active(void);
void bench_suite_update(void);
void bench_suite_render_viewport(window_t *win, void *user_data);

#endif // NEO_BENCH_SUITE_H
