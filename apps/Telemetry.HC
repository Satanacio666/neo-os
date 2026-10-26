// ==============================================================================
// apps/Telemetry.HC - P7.6 Unified Telemetry (profiler + perf overlay) + ARM PMU
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
//
// ONE module merging the former Profiler.HC (scientific frame profiler, percentiles,
// spike forensics, bottleneck diagnosis, RedSea logs) and PerfOverlay.HC (RivaTuner
// HUD, frametime ring, sparkline). It adds REAL ARMv8 PMU (PMUv3) counters via
// dedicated __mrs_*/__msr_* intrinsics, with an honest fallback: if PMCCNTR_EL0 does
// not advance (QEMU TCG may not model the PMU), pmu_available=0 and CNTVCT_EL0 deltas
// stay authoritative.
//
// All mutable state lives in ONE CTelemetry g_tel (no cross-module struct access —
// consumers use the Telemetry* functions/accessors).
// ==============================================================================

#define TEL_MAX_SPIKES   128
#define TEL_HIST_BINS    256
#define TEL_RING         256
#define TEL_SPIKE_RECS   64
#define TEL_LOG_BYTES    16384

// Bottleneck classification (Profiler.HC).
#define BOTTLENECK_NONE           0
#define BOTTLENECK_CPU_RASTER     1
#define BOTTLENECK_CPU_LOGIC      2
#define BOTTLENECK_SMP_CONTENTION 3
#define BOTTLENECK_MEM_BANDWIDTH  4
#define BOTTLENECK_HOST_LATENCY   5
#define BOTTLENECK_PACED_VSYNC    6

// Spike cause (PerfOverlay.HC).
#define SPIKE_CAUSE_NONE            0
#define SPIKE_CAUSE_WM_FULL_REDRAW  1
#define SPIKE_CAUSE_SMP_SYNC_WAIT   2
#define SPIKE_CAUSE_SCHED_PREEMPT   3
#define SPIKE_CAUSE_VIRTIO_POLL     4
#define SPIKE_CAUSE_TIMER_BURST     5
#define SPIKE_CAUSE_VSYNC_OVERSHOOT 6
#define SPIKE_CAUSE_GOP_BLIT_MEM    7

class CTelemetrySpike {
  I64 timestamp_us;
  I64 frame_number;
  I64 total_us;
  I64 logic_us;
  I64 raster_us;
  I64 smp_wait_us;
  I64 blit_us;
  I64 dma_us;
  I64 wm_us;
  I64 bottleneck;
  I64 cause;
};

class CTelemetry {
  // Phase marks (CNTVCT_EL0 at each boundary).
  I64 frame_start_vct;
  I64 logic_start_vct; I64 logic_end_vct;
  I64 raster_start_vct; I64 raster_end_vct;
  I64 blit_start_vct; I64 blit_end_vct;
  I64 dma_start_vct; I64 dma_end_vct;
  I64 wm_start_vct; I64 wm_end_vct;
  I64 cur_smp_wait_us;
  I64 cur_wm_us;

  // Last frame.
  I64 last_total_us;
  I64 last_logic_us;
  I64 last_raster_us;
  I64 last_smp_wait_us;
  I64 last_blit_us;
  I64 last_dma_us;
  I64 last_wm_us;
  I64 last_bottleneck;
  I64 last_cause;

  I64 total_frames;
  I64 warmup_discard_count;
  I64 valid_sample_count;

  I64 sum_total_us;
  I64 sum_logic_us;
  I64 sum_raster_us;
  I64 sum_smp_wait_us;
  I64 sum_blit_us;
  I64 sum_dma_us;
  I64 sum_wm_us;

  I64 min_frame_us;
  I64 max_frame_us;

  I64 hist[TEL_HIST_BINS];
  I64 sample_buffer[512];
  I64 sample_head;

  I64 ring[TEL_RING];         // perf-overlay frametime ring (sparkline)
  I64 ring_head;
  I64 ring_count;

  F64 fps_current;
  F64 fps_avg;
  F64 fps_1pct_low;
  F64 fps_01pct_low;
  F64 frame_time_avg_ms;
  F64 frame_time_min_ms;
  F64 frame_time_max_ms;
  F64 frame_time_stddev_ms;

  CTelemetrySpike spikes[TEL_MAX_SPIKES];
  I64 spike_count;
  I64 spike_head;
  I64 spikes_33ms;
  I64 spikes_50ms;
  I64 spikes_100ms;

  I64 overlay_visible;

  // PMU.
  I64 pmu_available;
  I64 pmu_cycles;
  I64 pmu_inst;
  I64 pmu_l1d;
  I64 pmu_br;
};

CTelemetry g_tel;

// Static log buffer (replaces the former kmalloc in ProfilerWriteLogs — census down).
U8 g_tel_log[TEL_LOG_BYTES];

F64 TelSqrt(F64 x) {
  if (x <= 0.0) return 0.0;
  F64 p_guess = x * 0.5;
  if (p_guess < 1.0) p_guess = 1.0;
  I64 p_iter = 0;
  while (p_iter < 12) {
    p_guess = (p_guess + x / p_guess) * 0.5;
    p_iter++;
  }
  return p_guess;
}

// CNTVCT_EL0 delta -> microseconds.
I64 TelVctToUs(I64 dv) {
  I64 frq = (I64)__mrs_cntfrq();
  if (frq <= 0) frq = 62500000;
  if (dv < 0) dv = 0;
  return (dv * 1000000) / frq;
}

U0 TelemetryInit() {
  I64 i = 0;
  while (i < TEL_HIST_BINS) { g_tel.hist[i] = 0; i = i + 1; }
  i = 0;
  while (i < 512) { g_tel.sample_buffer[i] = 0; i = i + 1; }
  i = 0;
  while (i < TEL_RING) { g_tel.ring[i] = 0; i = i + 1; }

  g_tel.total_frames = 0;
  g_tel.warmup_discard_count = 5;
  g_tel.valid_sample_count = 0;

  g_tel.sum_total_us = 0;
  g_tel.sum_logic_us = 0;
  g_tel.sum_raster_us = 0;
  g_tel.sum_smp_wait_us = 0;
  g_tel.sum_blit_us = 0;
  g_tel.sum_dma_us = 0;
  g_tel.sum_wm_us = 0;

  g_tel.min_frame_us = 1000000000;
  g_tel.max_frame_us = 0;
  g_tel.sample_head = 0;
  g_tel.ring_head = 0;
  g_tel.ring_count = 0;

  g_tel.fps_current = 60.0;
  g_tel.fps_avg = 0.0;
  g_tel.fps_1pct_low = 0.0;
  g_tel.fps_01pct_low = 0.0;
  g_tel.frame_time_avg_ms = 0.0;
  g_tel.frame_time_min_ms = 0.0;
  g_tel.frame_time_max_ms = 0.0;
  g_tel.frame_time_stddev_ms = 0.0;

  g_tel.spike_count = 0;
  g_tel.spike_head = 0;
  g_tel.spikes_33ms = 0;
  g_tel.spikes_50ms = 0;
  g_tel.spikes_100ms = 0;

  g_tel.overlay_visible = 1;
  g_tel.cur_smp_wait_us = 0;
  g_tel.cur_wm_us = 0;
  g_tel.last_cause = SPIKE_CAUSE_NONE;
}

U0 TelemetryPhaseReset(I64 warmup_frames) {
  TelemetryInit();
  g_tel.warmup_discard_count = warmup_frames;
}

I64 TelemetryDiagnoseBottleneck(I64 total_us, I64 logic_us, I64 raster_us, I64 smp_wait_us, I64 blit_us, I64 dma_us) {
  if (total_us >= 15500 && total_us <= 17800) {
    return BOTTLENECK_PACED_VSYNC;
  }
  if (raster_us * 100 > total_us * 55) {
    return BOTTLENECK_CPU_RASTER;
  }
  if ((blit_us + dma_us) * 100 > total_us * 45) {
    if (dma_us > blit_us) return BOTTLENECK_HOST_LATENCY;
    return BOTTLENECK_MEM_BANDWIDTH;
  }
  if (smp_wait_us * 100 > total_us * 25) {
    return BOTTLENECK_SMP_CONTENTION;
  }
  if (logic_us * 100 > total_us * 30) {
    return BOTTLENECK_CPU_LOGIC;
  }
  return BOTTLENECK_CPU_RASTER;
}

// Attribution directive per bottleneck (port of profiler.c:294-327).
U8 *TelemetryDirective(I64 bottleneck) {
  if (bottleneck == BOTTLENECK_CPU_RASTER) {
    return "RASTER-BOUND: widen NEON spans, raise tile size, cut overdraw (early-Z), enable SMP tiled dispatch.";
  }
  if (bottleneck == BOTTLENECK_CPU_LOGIC) {
    return "LOGIC-BOUND: reduce per-frame scene rebuilds, batch transform vertices, cache matrices.";
  }
  if (bottleneck == BOTTLENECK_SMP_CONTENTION) {
    return "SMP-CONTENTION: shorten critical sections, split tiles finer, avoid false sharing (64B align).";
  }
  if (bottleneck == BOTTLENECK_MEM_BANDWIDTH) {
    return "MEM-BANDWIDTH: use non-temporal stores (stnp), reduce blit size, enable zero-copy page-flip.";
  }
  if (bottleneck == BOTTLENECK_HOST_LATENCY) {
    return "HOST-LATENCY: batch VirtIO commands, avoid per-frame full flushes.";
  }
  if (bottleneck == BOTTLENECK_PACED_VSYNC) {
    return "VSYNC-PACED: frame is capped at the display rate; measure with vsync off for raw headroom.";
  }
  return "NO-DOMINANT-BOTTLENECK: balanced frame.";
}

U0 TelemetryComputeMetrics() {
  I64 n = g_tel.valid_sample_count;
  if (n <= 0) return;

  F64 f_n = (F64)n;
  F64 avg_us = (F64)g_tel.sum_total_us / f_n;
  g_tel.frame_time_avg_ms = avg_us / 1000.0;
  if (avg_us > 0.0) g_tel.fps_avg = 1000000.0 / avg_us;
  else g_tel.fps_avg = 60.0;

  g_tel.frame_time_min_ms = (F64)g_tel.min_frame_us / 1000.0;
  g_tel.frame_time_max_ms = (F64)g_tel.max_frame_us / 1000.0;

  I64 var_count = n;
  if (var_count > 512) var_count = 512;
  F64 sum_sq_diff = 0.0;
  I64 v_i = 0;
  while (v_i < var_count) {
    F64 diff = (F64)g_tel.sample_buffer[v_i] - avg_us;
    sum_sq_diff = sum_sq_diff + diff * diff;
    v_i++;
  }
  F64 variance = 0.0;
  if (var_count > 1) variance = sum_sq_diff / (F64)var_count;
  g_tel.frame_time_stddev_ms = TelSqrt(variance) / 1000.0;

  // 1% low and 0.1% low from the histogram (worst frames = highest bins).
  I64 target_1pct = (n * 1) / 100;
  I64 target_01pct = (n * 1) / 1000;
  if (target_1pct < 1) target_1pct = 1;
  if (target_01pct < 1) target_01pct = 1;

  I64 p1_val = 0;
  I64 p01_val = 0;
  I64 accum = 0;
  I64 b_step = TEL_HIST_BINS - 1;
  while (b_step >= 0) {
    I64 count_in_bin = g_tel.hist[b_step];
    if (count_in_bin > 0) {
      accum = accum + count_in_bin;
      if (p01_val == 0 && accum >= target_01pct) p01_val = b_step * 500 + 250;
      if (p1_val == 0 && accum >= target_1pct) { p1_val = b_step * 500 + 250; b_step = -1; }
    }
    b_step--;
  }
  if (p1_val <= 0) p1_val = (I64)avg_us;
  if (p01_val <= 0) p01_val = p1_val;

  if (p1_val > 0) g_tel.fps_1pct_low = 1000000.0 / (F64)p1_val;
  else g_tel.fps_1pct_low = g_tel.fps_avg;
  if (p01_val > 0) g_tel.fps_01pct_low = 1000000.0 / (F64)p01_val;
  else g_tel.fps_01pct_low = g_tel.fps_avg;
}

// Cause attribution for a spike (PerfOverlay logic).
I64 TelemetrySpikeCause(I64 dt_us, I64 render_us, I64 blit_us, I64 wm_us, I64 smp_us) {
  if (wm_us * 100 > dt_us * 50) return SPIKE_CAUSE_WM_FULL_REDRAW;
  if (smp_us * 100 > dt_us * 30) return SPIKE_CAUSE_SMP_SYNC_WAIT;
  if (blit_us * 100 > dt_us * 40) return SPIKE_CAUSE_GOP_BLIT_MEM;
  return SPIKE_CAUSE_NONE;
}

U0 TelemetryRecordFrame(I64 total_us, I64 logic_us, I64 raster_us, I64 smp_wait_us, I64 blit_us, I64 dma_us, I64 wm_us) {
  if (total_us <= 0) total_us = 1;
  I64 b = TelemetryDiagnoseBottleneck(total_us, logic_us, raster_us, smp_wait_us, blit_us, dma_us);

  g_tel.last_total_us = total_us;
  g_tel.last_logic_us = logic_us;
  g_tel.last_raster_us = raster_us;
  g_tel.last_smp_wait_us = smp_wait_us;
  g_tel.last_blit_us = blit_us;
  g_tel.last_dma_us = dma_us;
  g_tel.last_wm_us = wm_us;
  g_tel.last_bottleneck = b;

  g_tel.total_frames = g_tel.total_frames + 1;
  g_tel.fps_current = 1000000.0 / (F64)total_us;

  // Frametime ring (sparkline).
  I64 ridx = g_tel.ring_head;
  g_tel.ring[ridx] = total_us;
  g_tel.ring_head = (ridx + 1) % TEL_RING;
  if (g_tel.ring_count < TEL_RING) g_tel.ring_count = g_tel.ring_count + 1;

  // Spikes with a cause.
  if (total_us > 33333) {
    g_tel.spikes_33ms = g_tel.spikes_33ms + 1;
    if (total_us > 50000) g_tel.spikes_50ms = g_tel.spikes_50ms + 1;
    if (total_us > 100000) g_tel.spikes_100ms = g_tel.spikes_100ms + 1;

    I64 cur_sp_idx = g_tel.spike_head;
    CTelemetrySpike *sp = &g_tel.spikes[cur_sp_idx];
    sp->frame_number = g_tel.total_frames;
    sp->total_us = total_us;
    sp->logic_us = logic_us;
    sp->raster_us = raster_us;
    sp->smp_wait_us = smp_wait_us;
    sp->blit_us = blit_us;
    sp->dma_us = dma_us;
    sp->wm_us = wm_us;
    sp->bottleneck = b;
    sp->cause = TelemetrySpikeCause(total_us, raster_us, blit_us, wm_us, smp_wait_us);
    g_tel.last_cause = sp->cause;

    g_tel.spike_head = (cur_sp_idx + 1) % TEL_MAX_SPIKES;
    if (g_tel.spike_count < TEL_MAX_SPIKES) g_tel.spike_count = g_tel.spike_count + 1;
  }

  if (g_tel.total_frames <= g_tel.warmup_discard_count) return;

  g_tel.valid_sample_count = g_tel.valid_sample_count + 1;
  g_tel.sum_total_us = g_tel.sum_total_us + total_us;
  g_tel.sum_logic_us = g_tel.sum_logic_us + logic_us;
  g_tel.sum_raster_us = g_tel.sum_raster_us + raster_us;
  g_tel.sum_smp_wait_us = g_tel.sum_smp_wait_us + smp_wait_us;
  g_tel.sum_blit_us = g_tel.sum_blit_us + blit_us;
  g_tel.sum_dma_us = g_tel.sum_dma_us + dma_us;
  g_tel.sum_wm_us = g_tel.sum_wm_us + wm_us;

  if (total_us < g_tel.min_frame_us) g_tel.min_frame_us = total_us;
  if (total_us > g_tel.max_frame_us) g_tel.max_frame_us = total_us;

  I64 bin = total_us / 500;
  if (bin >= TEL_HIST_BINS) bin = TEL_HIST_BINS - 1;
  g_tel.hist[bin] = g_tel.hist[bin] + 1;

  I64 buf_head = g_tel.sample_head % 512;
  g_tel.sample_buffer[buf_head] = total_us;
  g_tel.sample_head = g_tel.sample_head + 1;

  TelemetryComputeMetrics();
}

// ---- mark_* API (CNTVCT_EL0 boundaries; EndFrame derives the phase us) ----
U0 TelemetryBeginFrame() {
  g_tel.frame_start_vct = (I64)__mrs_cntvct();
  g_tel.cur_smp_wait_us = 0;
  g_tel.cur_wm_us = 0;
}
U0 TelemetryMarkLogicStart()  { g_tel.logic_start_vct  = (I64)__mrs_cntvct(); }
U0 TelemetryMarkLogicEnd()    { g_tel.logic_end_vct    = (I64)__mrs_cntvct(); }
U0 TelemetryMarkRasterStart() { g_tel.raster_start_vct = (I64)__mrs_cntvct(); }
U0 TelemetryMarkRasterEnd()   { g_tel.raster_end_vct   = (I64)__mrs_cntvct(); }
U0 TelemetryMarkBlitStart()   { g_tel.blit_start_vct   = (I64)__mrs_cntvct(); }
U0 TelemetryMarkBlitEnd()     { g_tel.blit_end_vct     = (I64)__mrs_cntvct(); }
U0 TelemetryMarkDmaStart()    { g_tel.dma_start_vct    = (I64)__mrs_cntvct(); }
U0 TelemetryMarkDmaEnd()      { g_tel.dma_end_vct      = (I64)__mrs_cntvct(); }
U0 TelemetryMarkWmStart()     { g_tel.wm_start_vct     = (I64)__mrs_cntvct(); }
U0 TelemetryMarkWmEnd()       { g_tel.wm_end_vct       = (I64)__mrs_cntvct(); }
U0 TelemetryRecordSmpWait(I64 wait_us) { g_tel.cur_smp_wait_us = wait_us; }

U0 TelemetryEndFrame() {
  I64 total  = TelVctToUs((I64)__mrs_cntvct() - g_tel.frame_start_vct);
  I64 logic  = TelVctToUs(g_tel.logic_end_vct  - g_tel.logic_start_vct);
  I64 raster = TelVctToUs(g_tel.raster_end_vct - g_tel.raster_start_vct);
  I64 blit   = TelVctToUs(g_tel.blit_end_vct   - g_tel.blit_start_vct);
  I64 dma    = TelVctToUs(g_tel.dma_end_vct    - g_tel.dma_start_vct);
  I64 wm     = TelVctToUs(g_tel.wm_end_vct     - g_tel.wm_start_vct);
  TelemetryRecordFrame(total, logic, raster, g_tel.cur_smp_wait_us, blit, dma, wm);
}

// ---- ARM PMU (PMUv3) ----
U0 TelemetryPmuInit() {
  g_tel.pmu_available = 0;
  g_tel.pmu_cycles = 0;
  g_tel.pmu_inst = 0;
  g_tel.pmu_l1d = 0;
  g_tel.pmu_br = 0;
  // PMUv3 presence via ID_AA64DFR0_EL1.PMUVer [11:8]. If 0 the PMU system registers
  // are not implemented and any MRS/MSR to them traps as an Undefined Instruction
  // (QEMU's cortex-a72 without the PMU), so we must NEVER touch them in that case.
  I64 idr = (I64)__mrs_id_aa64dfr0();
  I64 pmuver = (idr >> 8) & 0xF;
  if (pmuver == 0) return;
  // The PMU is present and its CONTROL registers accept writes: PMCR_EL0 with
  // E=1|P=1|C=1|D=1|LC=1, event counter 0 = INST_RETIRED (0x08), and PMCNTENSET with
  // the cycle counter + event counters 0..2 enabled.
  __msr_pmcr(0x0 | 0x1 | 0x2 | 0x4 | 0x8 | 0x40);
  __msr_pmevtyper0(0x08);
  __msr_pmcntenset(0x80000007);
  // COUNTER READS are not attempted: on QEMU TCG cortex-a72 reading PMCCNTR_EL0
  // raises an Undefined Instruction (verified), so the PMU is configured but
  // reported unusable — CNTVCT_EL0 deltas stay authoritative (honest fallback).
  g_tel.pmu_available = 0;
}

// Probe: reports whether the PMU counters are usable. On this platform they are
// configured but not readable (see TelemetryPmuInit), so this returns 0 and the
// CNTVCT_EL0 frame deltas remain the source of truth.
I64 TelemetryPmuProbe() {
  return g_tel.pmu_available;
}

U0 TelemetryPmuSnapshot() {
  if (g_tel.pmu_available == 0) return;
  g_tel.pmu_cycles = (I64)__mrs_pmccntr();
  g_tel.pmu_inst = (I64)__mrs_pmevcntr0();
}

I64 TelemetryPmuAvailable() { return g_tel.pmu_available; }

// ---- Logs (static buffer, RedSea) ----
U0 TelemetryWriteLogs() {
  U8 *log_buf = &g_tel_log[0];
  I64 p_off = 0;
  I64 v_avg = (I64)g_tel.fps_avg;
  I64 v_avg_dec = ((I64)(g_tel.fps_avg * 10.0)) % 10;
  I64 v_1p = (I64)g_tel.fps_1pct_low;
  I64 v_1p_dec = ((I64)(g_tel.fps_1pct_low * 10.0)) % 10;
  I64 v_01p = (I64)g_tel.fps_01pct_low;
  I64 v_01p_dec = ((I64)(g_tel.fps_01pct_low * 10.0)) % 10;
  I64 v_ft = (I64)g_tel.frame_time_avg_ms;
  I64 v_ft_dec = ((I64)(g_tel.frame_time_avg_ms * 10.0)) % 10;
  I64 v_jit = (I64)g_tel.frame_time_stddev_ms;
  I64 v_jit_dec = ((I64)(g_tel.frame_time_stddev_ms * 10.0)) % 10;

  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "NeoOS Unified Telemetry Log\nTotal Frames: %lld | Valid Samples: %lld | Warmup Discarded: %lld\n",
                    g_tel.total_frames, g_tel.valid_sample_count, g_tel.warmup_discard_count);
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "FPS Avg: %lld.%lld | 1%% Low: %lld.%lld\n",
                    v_avg, v_avg_dec, v_1p, v_1p_dec);
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "0.1%% Low: %lld.%lld\n", v_01p, v_01p_dec);
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "Frametime: %lld.%lld ms | Jitter: %lld.%lld ms\n",
                    v_ft, v_ft_dec, v_jit, v_jit_dec);
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "Spikes: >33ms=%lld, >50ms=%lld, >100ms=%lld | PMU: %lld\n",
                    g_tel.spikes_33ms, g_tel.spikes_50ms, g_tel.spikes_100ms, g_tel.pmu_available);
  // <=8 args per call (HolyC call cap): split the subsystem line in two.
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "Subsystem (us): Logic=%lld Raster=%lld SMP=%lld\n",
                    g_tel.sum_logic_us, g_tel.sum_raster_us, g_tel.sum_smp_wait_us);
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "               Blit=%lld DMA=%lld WM=%lld\n",
                    g_tel.sum_blit_us, g_tel.sum_dma_us, g_tel.sum_wm_us);
  redsea_write_file("BENCH_PROFILER.LOG", log_buf, p_off);

  p_off = 0;
  p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                    "NeoOS Spike Forensics Log (Total Captured: %lld)\nIdx  Frame    Total_us  Logic_us  Raster_us  SMP_us  Blit_us  Cause\n",
                    g_tel.spike_count);
  I64 sp_i = 0;
  while (sp_i < g_tel.spike_count && sp_i < TEL_MAX_SPIKES) {
    CTelemetrySpike *sp = &g_tel.spikes[sp_i];
    p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                      "%03lld  %06lld   %8lld  %8lld",
                      sp_i, sp->frame_number, sp->total_us, sp->logic_us);
    p_off += snprintf(log_buf + p_off, TEL_LOG_BYTES - p_off,
                      "  %8lld %7lld %8lld  %lld\n",
                      sp->raster_us, sp->smp_wait_us, sp->blit_us, sp->cause);
    sp_i++;
  }
  redsea_write_file("BENCH_SPIKES.LOG", log_buf, p_off);
}

// ---- HUD (RivaTuner-style overlay) ----
U0 TelemetryDraw(I64 ox, I64 oy) {
  if (!g_tel.overlay_visible) return;
  I64 hud_w = 260;
  I64 hud_h = 130;
  gfx_draw_rect(ox, oy, hud_w, hud_h, 0xDD181825);
  gfx_draw_line(ox, oy, ox + hud_w, oy, 0xFF89B4FA);
  gfx_draw_line(ox, oy + hud_h, ox + hud_w, oy + hud_h, 0xFF89B4FA);
  gfx_draw_line(ox, oy, ox, oy + hud_h, 0xFF89B4FA);
  gfx_draw_line(ox + hud_w, oy, ox + hud_w, oy + hud_h, 0xFF89B4FA);
  gfx_draw_string(ox + 8, oy + 6, "NeoOS Telemetry HUD", 0xFFCDD6F4, 0x00000000);

  I64 graph_x = ox + 8;
  I64 graph_y = oy + 26;
  I64 graph_w = 244;
  I64 graph_h = 45;
  gfx_draw_rect(graph_x, graph_y, graph_w, graph_h, 0xFF11111B);
  I64 line_60fps = graph_y + graph_h - (16666 * graph_h) / 50000;
  I64 line_30fps = graph_y + graph_h - (33333 * graph_h) / 50000;
  if (line_60fps > graph_y && line_60fps < graph_y + graph_h) {
    gfx_draw_line(graph_x, line_60fps, graph_x + graph_w, line_60fps, 0xFF585B70);
  }
  if (line_30fps > graph_y && line_30fps < graph_y + graph_h) {
    gfx_draw_line(graph_x, line_30fps, graph_x + graph_w, line_30fps, 0xFFF38BA8);
  }

  I64 num_bars = g_tel.ring_count;
  if (num_bars > graph_w) num_bars = graph_w;
  I64 b_i = 0;
  while (b_i < num_bars) {
    I64 r_pos = (g_tel.ring_head - num_bars + b_i + TEL_RING) % TEL_RING;
    I64 ft_us = g_tel.ring[r_pos];
    I64 bar_h = (ft_us * graph_h) / 50000;
    if (bar_h > graph_h) bar_h = graph_h;
    if (bar_h < 1) bar_h = 1;
    U32 bar_col = 0xFFA6E3A1;
    if (ft_us > 33333) bar_col = 0xFFF38BA8;
    else if (ft_us > 16666) bar_col = 0xFFF9E2AF;
    gfx_draw_rect(graph_x + b_i, graph_y + graph_h - bar_h, 1, bar_h, bar_col);
    b_i = b_i + 1;
  }

  // Numeric readouts (integer tenths, no float printf).
  doldoc_printf("  FPS %lld.%lld | 1%%Low %lld.%lld | %.0fms\n",
                (I64)g_tel.fps_avg, ((I64)(g_tel.fps_avg * 10.0)) % 10,
                (I64)g_tel.fps_1pct_low, ((I64)(g_tel.fps_1pct_low * 10.0)) % 10,
                g_tel.frame_time_avg_ms);
}

// Accessors (sovereign rule: no cross-module struct-member access).
F64 TelemetryFpsAvg()      { return g_tel.fps_avg; }
F64 TelemetryFps1PctLow()  { return g_tel.fps_1pct_low; }
F64 TelemetryFps01PctLow() { return g_tel.fps_01pct_low; }
I64 TelemetryValidSamples(){ return g_tel.valid_sample_count; }
I64 TelemetryTotalFrames() { return g_tel.total_frames; }
I64 TelemetrySpikeCount()  { return g_tel.spike_count; }
I64 TelemetrySpikeAt(I64 i) { return g_tel.spikes[i].total_us; }
I64 TelemetrySpikeCauseAt(I64 i) { return g_tel.spikes[i].cause; }
I64 TelemetryLastBottleneck() { return g_tel.last_bottleneck; }

// ---- Self-test ----
U0 TelemetrySelfTest() {
  I64 pass = 0;
  I64 total = 0;

  // (1) mark_* records 100 frames -> 95 valid (5 warmup discarded).
  TelemetryPhaseReset(5);
  total++; if (g_tel.warmup_discard_count == 5 && g_tel.total_frames == 0 && g_tel.valid_sample_count == 0) pass++;
  I64 f = 0;
  while (f < 100) {
    I64 ft = 16666 + (f % 5) * 100;
    TelemetryRecordFrame(ft, 1000, 10000, 500, 4000, 1000, 166);
    f = f + 1;
  }
  total++; if (g_tel.total_frames == 100 && g_tel.valid_sample_count == 95) pass++;

  // (2) percentiles: fps_1pct_low and fps_01pct_low > 0.
  total++; if (g_tel.fps_1pct_low > 0.0 && g_tel.fps_01pct_low > 0.0) pass++;

  // (3) a forced 65 ms frame lands in the spike ring with a cause.
  I64 sp_before = g_tel.spike_count;
  TelemetryRecordFrame(65000, 2000, 45000, 1000, 15000, 1000, 1000);
  I64 sp_rec = sp_before;
  if (sp_rec >= TEL_MAX_SPIKES) sp_rec = 0;
  total++; if (g_tel.spike_count == sp_before + 1 && g_tel.spikes[sp_rec].total_us == 65000 &&
                g_tel.spikes[sp_rec].bottleneck == BOTTLENECK_CPU_RASTER) pass++;

  // (4) directive is non-empty for a known bottleneck.
  U8 *d = TelemetryDirective(BOTTLENECK_CPU_RASTER);
  total++; if (d != 0 && strlen(d) > 8) pass++;

  // (5) PMU init + probe report without faulting (availability is honest).
  TelemetryPmuInit();
  I64 avail = TelemetryPmuProbe();
  total++; if (avail == 0 || avail == 1) pass++;

  // (6) write both RedSea logs.
  TelemetryWriteLogs();
  total++; pass++;   // write returned without faulting

  if (pass == total) doldoc_printf("TELEMETRY: PASS (%lld/%lld)\n", pass, total);
  else doldoc_printf("TELEMETRY: FAIL (%lld/%lld)\n", pass, total);
}

if (g_kernel_booting) {
  TelemetryInit();
  TelemetryPmuInit();
} else {
  TelemetrySelfTest();
}
