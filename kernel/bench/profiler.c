#include "profiler.h"
#include "../../fs/redsea.h"
#include <uefi.h>

profiler_t g_profiler = {0};

static inline uint64_t profiler_read_vct(void) {
    uint64_t val;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(val));
    return val;
}

static inline uint64_t profiler_read_frq(void) {
    uint64_t val;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(val));
    if (val == 0) val = 62500000ULL;
    return val;
}

static inline uint32_t profiler_ticks_to_us(uint64_t ticks, uint64_t frq) {
    if (frq == 0) return 0;
    return (uint32_t)((ticks * 1000000ULL) / frq);
}

void profiler_init(void) {
    memset(&g_profiler, 0, sizeof(g_profiler));
    g_profiler.min_frame_us = 0xFFFFFFFF;
    g_profiler.max_frame_us = 0;
    g_profiler.warmup_discard_count = 25;
}

void profiler_phase_reset(uint32_t warmup_discard_frames) {
    g_profiler.warmup_discard_count = warmup_discard_frames;
    g_profiler.total_frames = 0;
    g_profiler.valid_sample_count = 0;

    g_profiler.sum_total_us = 0;
    g_profiler.sum_logic_us = 0;
    g_profiler.sum_raster_us = 0;
    g_profiler.sum_smp_wait_us = 0;
    g_profiler.sum_blit_us = 0;
    g_profiler.sum_dma_us = 0;
    g_profiler.sum_wm_us = 0;

    g_profiler.min_frame_us = 0xFFFFFFFF;
    g_profiler.max_frame_us = 0;
    memset(g_profiler.hist, 0, sizeof(g_profiler.hist));
    g_profiler.sample_head = 0;

    g_profiler.fps_avg = 0.0f;
    g_profiler.fps_1pct_low = 0.0f;
    g_profiler.fps_01pct_low = 0.0f;
    g_profiler.frame_time_avg_ms = 0.0f;
    g_profiler.frame_time_stddev_ms = 0.0f;
}

void profiler_begin_frame(void) {
    g_profiler.frame_start_vct = profiler_read_vct();
    g_profiler.cur_smp_wait_us = 0;
    g_profiler.logic_start_vct = 0;
    g_profiler.logic_end_vct = 0;
    g_profiler.raster_start_vct = 0;
    g_profiler.raster_end_vct = 0;
    g_profiler.blit_start_vct = 0;
    g_profiler.blit_end_vct = 0;
    g_profiler.dma_start_vct = 0;
    g_profiler.dma_end_vct = 0;
    g_profiler.wm_start_vct = 0;
    g_profiler.wm_end_vct = 0;
}

void profiler_mark_logic_start(void) {
    g_profiler.logic_start_vct = profiler_read_vct();
}

void profiler_mark_logic_end(void) {
    g_profiler.logic_end_vct = profiler_read_vct();
}

void profiler_mark_raster_start(void) {
    g_profiler.raster_start_vct = profiler_read_vct();
}

void profiler_mark_raster_end(void) {
    g_profiler.raster_end_vct = profiler_read_vct();
}

void profiler_record_smp_wait(uint64_t wait_us) {
    g_profiler.cur_smp_wait_us += wait_us;
}

void profiler_mark_blit_start(void) {
    g_profiler.blit_start_vct = profiler_read_vct();
}

void profiler_mark_blit_end(void) {
    g_profiler.blit_end_vct = profiler_read_vct();
}

void profiler_mark_dma_start(void) {
    g_profiler.dma_start_vct = profiler_read_vct();
}

void profiler_mark_dma_end(void) {
    g_profiler.dma_end_vct = profiler_read_vct();
}

void profiler_mark_wm_start(void) {
    g_profiler.wm_start_vct = profiler_read_vct();
}

void profiler_mark_wm_end(void) {
    g_profiler.wm_end_vct = profiler_read_vct();
}

void profiler_end_frame(void) {
    if (g_profiler.frame_start_vct == 0) return;
    uint64_t end_vct = profiler_read_vct();
    uint64_t frq = profiler_read_frq();

    uint32_t total_us = profiler_ticks_to_us(end_vct - g_profiler.frame_start_vct, frq);
    g_profiler.frame_start_vct = 0;
    if (total_us == 0) total_us = 1;

    uint32_t logic_us = (g_profiler.logic_end_vct > g_profiler.logic_start_vct) ?
        profiler_ticks_to_us(g_profiler.logic_end_vct - g_profiler.logic_start_vct, frq) : 0;

    uint32_t raster_us = (g_profiler.raster_end_vct > g_profiler.raster_start_vct) ?
        profiler_ticks_to_us(g_profiler.raster_end_vct - g_profiler.raster_start_vct, frq) : 0;

    uint32_t blit_us = (g_profiler.blit_end_vct > g_profiler.blit_start_vct) ?
        profiler_ticks_to_us(g_profiler.blit_end_vct - g_profiler.blit_start_vct, frq) : 0;

    uint32_t dma_us = (g_profiler.dma_end_vct > g_profiler.dma_start_vct) ?
        profiler_ticks_to_us(g_profiler.dma_end_vct - g_profiler.dma_start_vct, frq) : 0;

    uint32_t wm_us = (g_profiler.wm_end_vct > g_profiler.wm_start_vct) ?
        profiler_ticks_to_us(g_profiler.wm_end_vct - g_profiler.wm_start_vct, frq) : 0;

    uint32_t smp_wait_us = (uint32_t)g_profiler.cur_smp_wait_us;

    // Bottleneck Diagnosis
    profiler_bottleneck_t b = BOTTLENECK_NONE;
    if (total_us >= 15500 && total_us <= 17800) {
        b = BOTTLENECK_PACED_VSYNC;
    } else if (raster_us * 100 > total_us * 55) {
        b = BOTTLENECK_CPU_RASTER;
    } else if ((blit_us + dma_us) * 100 > total_us * 45) {
        b = (dma_us > blit_us) ? BOTTLENECK_HOST_LATENCY : BOTTLENECK_MEM_BANDWIDTH;
    } else if (smp_wait_us * 100 > total_us * 25) {
        b = BOTTLENECK_SMP_CONTENTION;
    } else if (logic_us * 100 > total_us * 30) {
        b = BOTTLENECK_CPU_LOGIC;
    } else {
        b = BOTTLENECK_CPU_RASTER;
    }

    g_profiler.last_total_us = total_us;
    g_profiler.last_logic_us = logic_us;
    g_profiler.last_raster_us = raster_us;
    g_profiler.last_smp_wait_us = smp_wait_us;
    g_profiler.last_blit_us = blit_us;
    g_profiler.last_dma_us = dma_us;
    g_profiler.last_wm_us = wm_us;
    g_profiler.last_bottleneck = b;

    g_profiler.total_frames++;

    // Track spikes in RAM ring buffer (no synchronous UART calls!)
    if (total_us > 33333) {
        g_profiler.spikes_33ms++;
        if (total_us > 50000)  g_profiler.spikes_50ms++;
        if (total_us > 100000) g_profiler.spikes_100ms++;

        int s_idx = g_profiler.spike_head;
        g_profiler.spikes[s_idx].timestamp_us = (end_vct * 1000000ULL) / frq;
        g_profiler.spikes[s_idx].frame_number = g_profiler.total_frames;
        g_profiler.spikes[s_idx].total_us = total_us;
        g_profiler.spikes[s_idx].logic_us = logic_us;
        g_profiler.spikes[s_idx].raster_us = raster_us;
        g_profiler.spikes[s_idx].smp_wait_us = smp_wait_us;
        g_profiler.spikes[s_idx].blit_us = blit_us;
        g_profiler.spikes[s_idx].dma_us = dma_us;
        g_profiler.spikes[s_idx].wm_us = wm_us;
        g_profiler.spikes[s_idx].bottleneck = b;

        g_profiler.spike_head = (s_idx + 1) % PROFILER_MAX_SPIKES;
        if (g_profiler.spike_count < PROFILER_MAX_SPIKES) {
            g_profiler.spike_count++;
        }
    }

    // Discard initial warm-up frames from steady-state statistics
    if (g_profiler.total_frames <= g_profiler.warmup_discard_count) {
        return;
    }

    g_profiler.valid_sample_count++;
    g_profiler.sum_total_us += total_us;
    g_profiler.sum_logic_us += logic_us;
    g_profiler.sum_raster_us += raster_us;
    g_profiler.sum_smp_wait_us += smp_wait_us;
    g_profiler.sum_blit_us += blit_us;
    g_profiler.sum_dma_us += dma_us;
    g_profiler.sum_wm_us += wm_us;

    if (total_us < g_profiler.min_frame_us) g_profiler.min_frame_us = total_us;
    if (total_us > g_profiler.max_frame_us) g_profiler.max_frame_us = total_us;

    // Histogram bucketing: 500us resolution
    uint32_t bin = total_us / 500;
    if (bin >= PROFILER_HIST_BINS) bin = PROFILER_HIST_BINS - 1;
    g_profiler.hist[bin]++;

    // Store in sample circular buffer for variance computation
    int s_buf_idx = g_profiler.sample_head % 512;
    g_profiler.sample_buffer[s_buf_idx] = total_us;
    g_profiler.sample_head++;

    // Refresh telemetry metrics every 10 frames
    if ((g_profiler.valid_sample_count % 10) == 0) {
        profiler_compute_metrics();
    }
}

void profiler_compute_metrics(void) {
    uint32_t n = g_profiler.valid_sample_count;
    if (n == 0) return;

    float avg_us = (float)g_profiler.sum_total_us / (float)n;
    g_profiler.frame_time_avg_ms = avg_us / 1000.0f;
    g_profiler.fps_avg = (avg_us > 0.0f) ? (1000000.0f / avg_us) : 60.0f;

    g_profiler.logic_avg_ms = (float)g_profiler.sum_logic_us / ((float)n * 1000.0f);
    g_profiler.raster_avg_ms = (float)g_profiler.sum_raster_us / ((float)n * 1000.0f);
    g_profiler.smp_wait_avg_ms = (float)g_profiler.sum_smp_wait_us / ((float)n * 1000.0f);
    g_profiler.blit_avg_ms = (float)g_profiler.sum_blit_us / ((float)n * 1000.0f);
    g_profiler.dma_avg_ms = (float)g_profiler.sum_dma_us / ((float)n * 1000.0f);
    g_profiler.wm_avg_ms = (float)g_profiler.sum_wm_us / ((float)n * 1000.0f);

    g_profiler.frame_time_min_ms = (float)g_profiler.min_frame_us / 1000.0f;
    g_profiler.frame_time_max_ms = (float)g_profiler.max_frame_us / 1000.0f;

    // Variance & Jitter (StdDev) over recent samples
    uint32_t var_count = (n > 512) ? 512 : n;
    float sum_sq_diff = 0.0f;
    for (uint32_t i = 0; i < var_count; i++) {
        float diff = (float)g_profiler.sample_buffer[i] - avg_us;
        sum_sq_diff += diff * diff;
    }
    float variance = (var_count > 1) ? (sum_sq_diff / (float)var_count) : 0.0f;
    float stddev_us = 0.0f;
    __asm__ volatile("fsqrt %s0, %s1" : "=w"(stddev_us) : "w"(variance));
    g_profiler.frame_time_stddev_ms = stddev_us / 1000.0f;

    // Compute 1% Low and 0.1% Low from histogram
    int target_1pct = (int)((n * 1) / 100);
    int target_01pct = (int)((n * 1) / 1000);
    if (target_1pct < 1) target_1pct = 1;
    if (target_01pct < 1) target_01pct = 1;

    uint32_t p1_val = 0, p01_val = 0;
    int accum = 0;
    for (int b = PROFILER_HIST_BINS - 1; b >= 0; b--) {
        if (g_profiler.hist[b] == 0) continue;
        accum += g_profiler.hist[b];
        if (!p01_val && accum >= target_01pct) {
            p01_val = (b == PROFILER_HIST_BINS - 1 && g_profiler.max_frame_us > 127500) ?
                g_profiler.max_frame_us : ((uint32_t)b * 500 + 250);
        }
        if (!p1_val && accum >= target_1pct) {
            p1_val = (b == PROFILER_HIST_BINS - 1 && g_profiler.max_frame_us > 127500) ?
                g_profiler.max_frame_us : ((uint32_t)b * 500 + 250);
            break;
        }
    }
    if (p1_val == 0) p1_val = (uint32_t)avg_us;
    if (p01_val == 0) p01_val = p1_val;

    g_profiler.fps_1pct_low = (p1_val > 0) ? (1000000.0f / (float)p1_val) : g_profiler.fps_avg;
    g_profiler.fps_01pct_low = (p01_val > 0) ? (1000000.0f / (float)p01_val) : g_profiler.fps_avg;
}

const char* profiler_bottleneck_str(profiler_bottleneck_t b) {
    switch (b) {
        case BOTTLENECK_CPU_RASTER:     return "CPU_RASTER (Triangle/ZBuf)";
        case BOTTLENECK_CPU_LOGIC:      return "CPU_LOGIC (Math/Physics)";
        case BOTTLENECK_SMP_CONTENTION: return "SMP_CONTENTION (Lock/Join)";
        case BOTTLENECK_MEM_BANDWIDTH:  return "MEM_BANDWIDTH (VRAM Blit)";
        case BOTTLENECK_HOST_LATENCY:   return "HOST_GPU (VirtIO Fence)";
        case BOTTLENECK_PACED_VSYNC:    return "FLUID_VSYNC (Paced 60Hz)";
        default:                        return "BALANCED";
    }
}

int profiler_export_log(const char *path) {
    static char buf[4096];
    int len = 0;

    len += snprintf(buf + len, sizeof(buf) - len,
        "======================================================================\n"
        "                  NeoOS Sovereign Hardware Profiler Report            \n"
        "                     Target: AArch64 Ring 0 SASOS                     \n"
        "======================================================================\n"
        "Total Frames Captured:  %u (Warmup Discarded: %u)\n"
        "Average FPS:            %u.%u FPS\n"
        "1%% Low FPS:             %u.%u FPS\n"
        "0.1%% Low FPS:           %u.%u FPS\n"
        "Average Frame Time:     %u.%u ms\n"
        "Min Frame Time:         %u.%u ms\n"
        "Max Frame Time:         %u.%u ms\n"
        "Frame Jitter (StdDev):  %u.%u ms\n"
        "----------------------------------------------------------------------\n"
        "Sub-Millisecond Decomposed Telemetry Averages:\n"
        "  - Logic / Math:       %u.%u ms\n"
        "  - Rasterizer / Fill:  %u.%u ms\n"
        "  - SMP Sync Wait:      %u.%u ms\n"
        "  - Framebuffer Blit:   %u.%u ms\n"
        "  - VirtIO GPU DMA:     %u.%u ms\n"
        "  - Compositor Window:  %u.%u ms\n"
        "----------------------------------------------------------------------\n"
        "Spike Telemetry:\n"
        "  - Drops below 30 FPS (>33.3ms): %u\n"
        "  - Drops below 20 FPS (>50.0ms): %u\n"
        "  - Severe Spikes (>100.0ms):     %u\n"
        "Primary Bottleneck:     %s\n"
        "======================================================================\n",
        (unsigned int)g_profiler.total_frames, (unsigned int)g_profiler.warmup_discard_count,
        (unsigned int)g_profiler.fps_avg, (unsigned int)((g_profiler.fps_avg - (float)(unsigned int)g_profiler.fps_avg) * 10.0f),
        (unsigned int)g_profiler.fps_1pct_low, (unsigned int)((g_profiler.fps_1pct_low - (float)(unsigned int)g_profiler.fps_1pct_low) * 10.0f),
        (unsigned int)g_profiler.fps_01pct_low, (unsigned int)((g_profiler.fps_01pct_low - (float)(unsigned int)g_profiler.fps_01pct_low) * 10.0f),
        (unsigned int)g_profiler.frame_time_avg_ms, (unsigned int)((g_profiler.frame_time_avg_ms - (float)(unsigned int)g_profiler.frame_time_avg_ms) * 10.0f),
        (unsigned int)g_profiler.frame_time_min_ms, (unsigned int)((g_profiler.frame_time_min_ms - (float)(unsigned int)g_profiler.frame_time_min_ms) * 10.0f),
        (unsigned int)g_profiler.frame_time_max_ms, (unsigned int)((g_profiler.frame_time_max_ms - (float)(unsigned int)g_profiler.frame_time_max_ms) * 10.0f),
        (unsigned int)g_profiler.frame_time_stddev_ms, (unsigned int)((g_profiler.frame_time_stddev_ms - (float)(unsigned int)g_profiler.frame_time_stddev_ms) * 10.0f),
        (unsigned int)g_profiler.logic_avg_ms, (unsigned int)((g_profiler.logic_avg_ms - (float)(unsigned int)g_profiler.logic_avg_ms) * 10.0f),
        (unsigned int)g_profiler.raster_avg_ms, (unsigned int)((g_profiler.raster_avg_ms - (float)(unsigned int)g_profiler.raster_avg_ms) * 10.0f),
        (unsigned int)g_profiler.smp_wait_avg_ms, (unsigned int)((g_profiler.smp_wait_avg_ms - (float)(unsigned int)g_profiler.smp_wait_avg_ms) * 10.0f),
        (unsigned int)g_profiler.blit_avg_ms, (unsigned int)((g_profiler.blit_avg_ms - (float)(unsigned int)g_profiler.blit_avg_ms) * 10.0f),
        (unsigned int)g_profiler.dma_avg_ms, (unsigned int)((g_profiler.dma_avg_ms - (float)(unsigned int)g_profiler.dma_avg_ms) * 10.0f),
        (unsigned int)g_profiler.wm_avg_ms, (unsigned int)((g_profiler.wm_avg_ms - (float)(unsigned int)g_profiler.wm_avg_ms) * 10.0f),
        (unsigned int)g_profiler.spikes_33ms, (unsigned int)g_profiler.spikes_50ms, (unsigned int)g_profiler.spikes_100ms,
        profiler_bottleneck_str(g_profiler.last_bottleneck)
    );

    return redsea_write_file(path, buf, (size_t)len);
}

int profiler_export_spikes(const char *path) {
    static char buf[8192];
    int len = 0;

    len += snprintf(buf + len, sizeof(buf) - len,
        "=========================================================================================\n"
        "                  NeoOS Profiler High-Resolution Spike Forensic Log                       \n"
        "=========================================================================================\n"
        "Frame # | Total (ms) | Logic | Raster | SMP Wait | Blit | VirtIO DMA | WM | Cause\n"
        "--------+------------+-------+--------+----------+------+------------+----+---------------\n"
    );

    uint32_t count = g_profiler.spike_count;
    if (count > PROFILER_MAX_SPIKES) count = PROFILER_MAX_SPIKES;

    int base = (g_profiler.spike_head - count + PROFILER_MAX_SPIKES) % PROFILER_MAX_SPIKES;
    for (uint32_t i = 0; i < count; i++) {
        int idx = (base + i) % PROFILER_MAX_SPIKES;
        profiler_spike_t *s = &g_profiler.spikes[idx];

        len += snprintf(buf + len, sizeof(buf) - len,
            " %6u |  %4u.%u ms | %3u.%u | %4u.%u |  %4u.%u  | %3u.%u|   %4u.%u   |%2u.%u| %s\n",
            (unsigned int)s->frame_number,
            (unsigned int)(s->total_us / 1000), (unsigned int)((s->total_us % 1000) / 100),
            (unsigned int)(s->logic_us / 1000), (unsigned int)((s->logic_us % 1000) / 100),
            (unsigned int)(s->raster_us / 1000), (unsigned int)((s->raster_us % 1000) / 100),
            (unsigned int)(s->smp_wait_us / 1000), (unsigned int)((s->smp_wait_us % 1000) / 100),
            (unsigned int)(s->blit_us / 1000), (unsigned int)((s->blit_us % 1000) / 100),
            (unsigned int)(s->dma_us / 1000), (unsigned int)((s->dma_us % 1000) / 100),
            (unsigned int)(s->wm_us / 1000), (unsigned int)((s->wm_us % 1000) / 100),
            profiler_bottleneck_str(s->bottleneck)
        );

        if (len >= (int)sizeof(buf) - 256) break;
    }

    len += snprintf(buf + len, sizeof(buf) - len,
        "=========================================================================================\n"
    );

    return redsea_write_file(path, buf, (size_t)len);
}
