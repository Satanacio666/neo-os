#ifndef NEO_BENCH3D_H
#define NEO_BENCH3D_H

#include <uefi.h>
#include "../../gui/wm.h"
#include "../math/math3d.h"

typedef struct {
    uint32_t       core_id;             // SMP Core (1 or 2)
    mesh3d_cube_t  cube;
    float          angle_x;
    float          angle_y;
    float          angle_z;
    float          speed_x;
    float          speed_y;
    float          speed_z;
    uint32_t       theme_primary;       // Wire or solid color
    uint32_t       theme_accent;        // Vertex or secondary color
    int            is_solid;            // 0 = wireframe, 1 = solid shaded
    
    // Telemetry & Benchmark Metrics
    uint64_t       frame_count;
    uint64_t       last_ticks;
    uint32_t       fps;
    uint32_t       fps_counter;
    uint64_t       fps_timer_ticks;
    uint64_t       frame_time_us;
    uint64_t       throughput_metric;   // Ops/sec or MB/s
    uint64_t       ops_accumulator;     // Raw empirical work counter from SMP worker
    
    // Multi-core dispatch flag
    volatile int   compute_ready;
    mat4_t         mvp;
    zbuffer_t      zbuffer;
} bench3d_instance_t;

void bench3d_init(void);
int  bench3d_start(void);
void bench3d_stop(void);
int  bench3d_is_active(void);

void bench3d_update_instance(bench3d_instance_t *inst);
void bench3d_render_instance(window_t *win, void *user_data);

#endif // NEO_BENCH3D_H
