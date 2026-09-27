#ifndef NEO_PERF_OVERLAY_H
#define NEO_PERF_OVERLAY_H

#include <uefi.h>

#define PERF_RING_SIZE 512
#define MAX_SPIKE_RECORDS 128

typedef enum {
    SPIKE_CAUSE_NONE            = 0,
    SPIKE_CAUSE_WM_FULL_REDRAW  = 1, // Full desktop invalidation (wm_draw_all)
    SPIKE_CAUSE_SMP_SYNC_WAIT   = 2, // Secondary core join starvation in TCG
    SPIKE_CAUSE_SCHED_PREEMPT   = 3, // Scheduler preempted render thread
    SPIKE_CAUSE_VIRTIO_POLL     = 4, // Host GPU hypervisor fence synchronous wait
    SPIKE_CAUSE_TIMER_BURST     = 5, // Interrupt service routine storm
    SPIKE_CAUSE_VSYNC_OVERSHOOT = 6, // VSync sleep passed deadline
    SPIKE_CAUSE_GOP_BLIT_MEM    = 7  // Memory bus blit overhead
} spike_cause_t;

typedef struct {
    uint64_t      timestamp_us;
    uint64_t      frame_number;
    uint32_t      total_frametime_us;
    uint32_t      render_time_us;
    uint32_t      blit_time_us;
    uint32_t      wm_overhead_us;
    uint32_t      smp_wait_us;
    spike_cause_t primary_cause;
    uint8_t       core_id;
    char          preempting_task[16];
} spike_record_t;

typedef struct {
    // Ring buffer of frame times (microseconds)
    uint64_t frame_times_us[PERF_RING_SIZE];
    uint64_t render_times_us[PERF_RING_SIZE];
    uint64_t blit_times_us[PERF_RING_SIZE];
    int      ring_head;
    int      ring_count;

    // Segment timing per frame (filled by caller)
    uint64_t frame_start_cycles;   // hardware counter at begin_frame
    uint64_t last_frame_end_cycles;// hardware counter at previous frame end
    uint64_t frame_start_us;       // frame start timestamp
    uint64_t last_render_us;       // time spent in render (draw calls)
    uint64_t last_blit_us;         // time spent in blit (swap_buffers)
    uint64_t last_logic_us;        // time spent in logic/physics

    // Warmup vs Steady-state tracking
    uint64_t warmup_frames;    // Number of initial warmup frames (typically 1)
    uint64_t warmup_spike_us;  // Duration of frame 0 warmup spike

    // Computed metrics (All frames including warmup)
    float    fps_current;
    float    fps_avg;
    float    fps_1pct_low;
    float    fps_01pct_low;
    float    frame_time_avg_ms;
    float    frame_time_min_ms;
    float    frame_time_max_ms;
    float    frame_time_stddev_ms;
    float    blit_avg_ms;
    float    render_avg_ms;

    // Steady-state metrics (Excluding frame 0 warmup spike for pure hardware performance)
    float    steady_fps_avg;
    float    steady_1pct_low;
    float    steady_01pct_low;
    float    steady_frame_time_avg_ms;
    float    steady_stddev_ms;
    float    steady_blit_avg_ms;
    float    steady_render_avg_ms;
    float    recent_spike_ms;

    // Spike diagnostics
    uint32_t spike_count_50ms;  // Frames > 50ms (drops below 20 FPS)
    uint32_t spike_count_100ms; // Frames > 100ms (drops below 10 FPS)
    uint32_t spike_count_500ms; // Severe stalls > 500ms (TCG translation / allocation)

    // Detailed Spike Forensics Ring Buffer
    spike_record_t spike_records[MAX_SPIKE_RECORDS];
    int            spike_record_count;
    int            spike_record_head;
    uint64_t       last_smp_wait_us;
    uint64_t       last_wm_overhead_us;

    uint64_t total_frames;
    int      overlay_visible;
} perf_stats_t;

void perf_overlay_init(perf_stats_t *s);
void perf_overlay_begin_frame(perf_stats_t *s);   // record frame start tick
void perf_overlay_end_frame(perf_stats_t *s);     // record frame end, update ring buffer
void perf_overlay_record_blit(perf_stats_t *s, uint64_t blit_us); // record blit duration
void perf_overlay_record_smp_wait(perf_stats_t *s, uint64_t wait_us);
void perf_overlay_record_wm_overhead(perf_stats_t *s, uint64_t wm_us);
void perf_overlay_update_metrics(perf_stats_t *s);// recompute 1%low etc (call every N frames)
void perf_overlay_draw(perf_stats_t *s, int x, int y); // draw HUD overlay at position
int  perf_export_log(perf_stats_t *s, const char *benchmark_name, const char *redsea_path, const char *ramdisk_path);
int  perf_export_spike_log(perf_stats_t *s, const char *path);

// Helper: read AArch64 virtual counter in microseconds
uint64_t perf_now_us(void);

#endif // NEO_PERF_OVERLAY_H
