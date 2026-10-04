#ifndef NEO_PROFILER_H
#define NEO_PROFILER_H

#include <uefi.h>

#define PROFILER_MAX_SPIKES 128
#define PROFILER_HIST_BINS  256

typedef enum {
    BOTTLENECK_NONE = 0,
    BOTTLENECK_CPU_RASTER,      // Triangle fill, rasterization, Z-buffer
    BOTTLENECK_CPU_LOGIC,       // Physics step, matrix multiplication
    BOTTLENECK_SMP_CONTENTION,  // Cores waiting on spinlocks/join
    BOTTLENECK_MEM_BANDWIDTH,   // Blit / VRAM copy
    BOTTLENECK_HOST_LATENCY,    // VirtIO queue submission & fence wait
    BOTTLENECK_PACED_VSYNC      // Smooth 60 FPS presentation
} profiler_bottleneck_t;

typedef struct {
    uint64_t timestamp_us;
    uint32_t frame_number;
    uint32_t total_us;
    uint32_t logic_us;
    uint32_t raster_us;
    uint32_t smp_wait_us;
    uint32_t blit_us;
    uint32_t dma_us;
    uint32_t wm_us;
    profiler_bottleneck_t bottleneck;
} profiler_spike_t;

typedef struct {
    // Current frame microsecond counters (hardware cntvct_el0)
    uint64_t frame_start_vct;
    uint64_t logic_start_vct;
    uint64_t logic_end_vct;
    uint64_t raster_start_vct;
    uint64_t raster_end_vct;
    uint64_t blit_start_vct;
    uint64_t blit_end_vct;
    uint64_t dma_start_vct;
    uint64_t dma_end_vct;
    uint64_t wm_start_vct;
    uint64_t wm_end_vct;

    // Frame segment accumulators
    uint64_t cur_smp_wait_us;

    // Last completed frame metrics (microseconds)
    uint32_t last_total_us;
    uint32_t last_logic_us;
    uint32_t last_raster_us;
    uint32_t last_smp_wait_us;
    uint32_t last_blit_us;
    uint32_t last_dma_us;
    uint32_t last_wm_us;
    profiler_bottleneck_t last_bottleneck;

    // Phase statistical accumulation (O(N) ring + histogram)
    uint32_t total_frames;
    uint32_t warmup_discard_count;
    uint32_t valid_sample_count;

    uint64_t sum_total_us;
    uint64_t sum_logic_us;
    uint64_t sum_raster_us;
    uint64_t sum_smp_wait_us;
    uint64_t sum_blit_us;
    uint64_t sum_dma_us;
    uint64_t sum_wm_us;

    uint32_t min_frame_us;
    uint32_t max_frame_us;

    // Percentile histogram (500us bins, 0 to 128ms)
    uint16_t hist[PROFILER_HIST_BINS];

    // Variance scratchpad
    uint32_t sample_buffer[512];
    uint32_t sample_head;

    // Computed scientific metrics
    float    fps_avg;
    float    fps_1pct_low;
    float    fps_01pct_low;
    float    frame_time_avg_ms;
    float    frame_time_min_ms;
    float    frame_time_max_ms;
    float    frame_time_stddev_ms; // Jitter
    float    logic_avg_ms;
    float    raster_avg_ms;
    float    smp_wait_avg_ms;
    float    blit_avg_ms;
    float    dma_avg_ms;
    float    wm_avg_ms;

    // Spike forensics ring in RAM
    profiler_spike_t spikes[PROFILER_MAX_SPIKES];
    uint32_t spike_count;
    uint32_t spike_head;
    uint32_t spikes_33ms;
    uint32_t spikes_50ms;
    uint32_t spikes_100ms;
} profiler_t;

extern profiler_t g_profiler;

void profiler_init(void);
void profiler_phase_reset(uint32_t warmup_discard_frames);

void profiler_begin_frame(void);
void profiler_mark_logic_start(void);
void profiler_mark_logic_end(void);
void profiler_mark_raster_start(void);
void profiler_mark_raster_end(void);
void profiler_record_smp_wait(uint64_t wait_us);
void profiler_mark_blit_start(void);
void profiler_mark_blit_end(void);
void profiler_mark_dma_start(void);
void profiler_mark_dma_end(void);
void profiler_mark_wm_start(void);
void profiler_mark_wm_end(void);
void profiler_end_frame(void);

void profiler_compute_metrics(void);
const char* profiler_bottleneck_str(profiler_bottleneck_t b);
const char* profiler_get_optimization_directive(profiler_bottleneck_t b);

int profiler_export_log(const char *path);
int profiler_export_spikes(const char *path);

#endif // NEO_PROFILER_H
