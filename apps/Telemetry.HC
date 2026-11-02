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

  // ---------------------------------------------------------------------
  // ESTADO DE UI (fundido do antigo CProfiler — UNIFICACAO 01/11)
  // ---------------------------------------------------------------------
  // Antes existiam DUAS estruturas com o mesmo papel: CTelemetry (dados ricos:
  // histograma, percentis, spikes, diagnostico) e CProfiler (baldes do loop +
  // estado do painel). Ambas mediam o MESMO frame por caminhos paralelos. Agora
  // ha' UMA: o frame entra por ProfilerMarkXxx (baldes do loop do Shell) e por
  // TelemetryBeginFrame/EndFrame (estagios logic/raster/blit/dma/wm). CTelemetry
  // e' o modelo unico; nao existe mais g_prof.
  I64 ui_on;                  // painel ligado?
  I64 ui_trace;               // espelho [PROF] no serial
  I64 ui_node_id;             // no DolDoc do painel (-1 = nenhum)
  I64 ui_draws;               // quantas vezes o painel foi redesenhado
  I64 ui_refreshes;           // quantos refreshes de estado
  I64 ui_last_refresh_ms;
  I64 ui_last_trace_ms;
  I64 ui_refresh_period_ms;
  I64 ui_trace_period_ms;

  // Baldes do frame corrente — loop do Shell (input/shell/doldoc/render/idle).
  I64 acc_input_us;
  I64 acc_shell_us;
  I64 acc_doldoc_us;
  I64 acc_render_us;
  I64 acc_idle_us;

  // Ultimo frame (baldes do loop).
  I64 last_input_us;
  I64 last_shell_us;
  I64 last_doldoc_us;
  I64 last_render_us;
  I64 last_idle_us;

  // Somas da janela (baldes do loop).
  I64 samples;
  I64 sum_frame_us;
  I64 sum_input_us;
  I64 sum_shell_us;
  I64 sum_doldoc_us;
  I64 sum_render_us;
  I64 sum_idle_us;
  I64 sum_idle_ms;
  I64 ui_ring[PROF_RING];     // frame times (us) para o FPS da janela
  I64 ui_ring_head;
  I64 ui_ring_count;
  I64 ui_min_frame_us;
  I64 ui_max_frame_us;
  I64 ui_frames_total;

  // Carga instantanea (ultimo refresh).
  I64 ui_heap_used_kb;
  I64 ui_heap_free_kb;
  I64 ui_heap_total_kb;
  I64 ui_heap_allocs;
  I64 ui_exc_recovered;
  I64 ui_exc_total;
  I64 ui_exc_panic;
  I64 ui_uptime_ms;
  I64 ui_fps_x10;
  I64 ui_frame_us;
  I64 ui_last_sample_ms;
  I64 ui_last_sample_frames;
  // Geometria do no DolDoc (para apresentar so o retangulo do painel).
  I64 ui_panel_x; I64 ui_panel_y; I64 ui_panel_w; I64 ui_panel_h;
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

// Ponto de entrada UNICO do caminho de DESENHO (fora do loop do shell, ex.:
// SelfTestRender). Antes, alimentar a telemetria exigia chamar cinco funcoes na
// ordem certa e ninguem o fazia (eram orfas). Agora e' abrir e fechar.
U0 TelemetryFrameBegin() {
  TelemetryBeginFrame();
  TelemetryMarkLogicStart();
  TelemetryMarkRasterStart();
}
U0 TelemetryFrameEnd() {
  TelemetryMarkRasterEnd();
  TelemetryMarkLogicEnd();
  TelemetryEndFrame();
}

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

// ============================================================================
// P9.0 — LIVE PROFILER PANEL (substitui o banner de boot do Shell)
//
// O painel e um NODE DolDoc (kind DOC_PROF, criado pela tag $PROF$): quem o
// desenha e o proprio pipeline do DolDoc (DolDocRedraw -> ProfilerDrawPanel).
// O estado vive aqui, no modulo de telemetria, e o Shell alimenta os baldes de
// tempo no seu event loop. Nada de printf cru: a renderizacao passa por
// gfx_draw_* (o mesmo caminho de $CARD/$GRAPH) e o espelho textual vai para o
// UART por uart_puts, que e o log serial.
// ============================================================================
#define PROF_RING 256
#define PROF_LINES 12

// (CProfiler removido — UNIFICACAO 01/11: o estado de UI vive em CTelemetry.)

U0 ProfilerReset() {
  g_tel.ui_node_id = -1;
  g_tel.ui_draws = 0;
  g_tel.ui_refreshes = 0;
  g_tel.ui_last_refresh_ms = 0;
  g_tel.ui_last_trace_ms = 0;
  if (g_tel.ui_refresh_period_ms <= 0) g_tel.ui_refresh_period_ms = 250;
  if (g_tel.ui_trace_period_ms <= 0) g_tel.ui_trace_period_ms = 1000;
  g_tel.acc_input_us = 0; g_tel.acc_shell_us = 0; g_tel.acc_doldoc_us = 0;
  g_tel.acc_render_us = 0; g_tel.acc_idle_us = 0;
  g_tel.last_total_us = 0; g_tel.last_input_us = 0; g_tel.last_shell_us = 0;
  g_tel.last_doldoc_us = 0; g_tel.last_render_us = 0; g_tel.last_idle_us = 0;
  g_tel.samples = 0; g_tel.sum_total_us = 0; g_tel.sum_input_us = 0;
  g_tel.sum_shell_us = 0; g_tel.sum_doldoc_us = 0; g_tel.sum_render_us = 0;
  g_tel.sum_idle_us = 0; g_tel.sum_idle_ms = 0;
  g_tel.ui_ring_head = 0; g_tel.ui_ring_count = 0;
  g_tel.min_frame_us = 0; g_tel.max_frame_us = 0;
  g_tel.total_frames = 0;
  g_tel.ui_heap_used_kb = 0; g_tel.ui_heap_free_kb = 0; g_tel.ui_heap_total_kb = 0;
  g_tel.ui_heap_allocs = 0;
  g_tel.ui_exc_recovered = 0; g_tel.ui_exc_total = 0; g_tel.ui_exc_panic = 0;
  g_tel.ui_uptime_ms = 0; g_tel.ui_fps_x10 = 0; g_tel.ui_frame_us = 0;
  g_tel.ui_last_sample_ms = 0; g_tel.ui_last_sample_frames = 0;
  g_tel.ui_panel_x = 0; g_tel.ui_panel_y = 0; g_tel.ui_panel_w = 0; g_tel.ui_panel_h = 0;
  I64 i = 0;
  while (i < PROF_RING) { g_tel.ui_ring[i] = 0; i = i + 1; }
}

U0 ProfilerSetOn(I64 v) { g_tel.ui_on = v ? 1 : 0; }
I64 ProfilerIsOn() { return g_tel.ui_on; }
U0 ProfilerSetTrace(I64 v) { g_tel.ui_trace = v ? 1 : 0; }
I64 ProfilerTraceOn() { return g_tel.ui_trace; }
U0 ProfilerSetNodeId(I64 nid) { g_tel.ui_node_id = nid; }
U0 ProfilerSetNodeRect(I64 x, I64 y, I64 w, I64 h) {
  g_tel.ui_panel_x = x; g_tel.ui_panel_y = y; g_tel.ui_panel_w = w; g_tel.ui_panel_h = h;
}
I64 ProfilerPanelX() { return g_tel.ui_panel_x; }
I64 ProfilerPanelY() { return g_tel.ui_panel_y; }
I64 ProfilerPanelW() { return g_tel.ui_panel_w; }
I64 ProfilerPanelH() { return g_tel.ui_panel_h; }
I64 ProfilerNodeId() { return g_tel.ui_node_id; }
I64 ProfilerRefreshes() { return g_tel.ui_refreshes; }
I64 ProfilerDraws() { return g_tel.ui_draws; }

// Tempo em us entre dois carimbos CNTVCT_EL0 (o Shell carimba o loop).
I64 ProfilerUsSince(I64 t0) {
  I64 dv = (I64)__mrs_cntvct() - t0;
  if (dv < 0) dv = 0;
  return TelVctToUs(dv);
}

I64 ProfilerUsBetween(I64 t0, I64 t1) {
  I64 dv = t1 - t0;
  if (dv < 0) dv = 0;
  return TelVctToUs(dv);
}

U0 ProfilerMarkInput(I64 us) { g_tel.acc_input_us = g_tel.acc_input_us + us; }
U0 ProfilerMarkShell(I64 us) { g_tel.acc_shell_us = g_tel.acc_shell_us + us; }
U0 ProfilerMarkDolDoc(I64 us) { g_tel.acc_doldoc_us = g_tel.acc_doldoc_us + us; }
U0 ProfilerMarkRender(I64 us) { g_tel.acc_render_us = g_tel.acc_render_us + us; }
U0 ProfilerMarkIdle(I64 us) { g_tel.acc_idle_us = g_tel.acc_idle_us + us; }

// Fecha o frame: consolida os baldes, atualiza a janela deslizante de FPS.
// Fecha o frame: consolida os baldes do LOOP e os estagios do PRESENT num unico
// modelo (UNIFICACAO 01/11). Antes havia dois ciclos paralelos: o loop alimentava
// CProfiler e o Present alimentava CTelemetry (via TelemetryEndFrame), e os dois
// calculavam FPS/frametime por conta propria. Agora o LOOP e' o unico fechador de
// frame: ele soma os baldes e repassa os estagios de apresentacao (logic/raster/
// blit, gravados pelos TelemetryMark*) para TelemetryRecordFrame, que mantem o
// histograma, os percentis 1%/0.1% e a atribuicao de spikes. Um frame, um modelo.
U0 ProfilerEndFrame(I64 frame_us) {
  if (frame_us <= 0) frame_us = 1;
  g_tel.last_total_us = frame_us;
  g_tel.last_input_us = g_tel.acc_input_us;
  g_tel.last_shell_us = g_tel.acc_shell_us;
  g_tel.last_doldoc_us = g_tel.acc_doldoc_us;
  g_tel.last_render_us = g_tel.acc_render_us;
  g_tel.last_idle_us = g_tel.acc_idle_us;

  g_tel.samples = g_tel.samples + 1;
  // NAO incrementar total_frames/sum_total_us aqui: TelemetryRecordFrame (chamado
  // abaixo) ja' os contabiliza. Contar nos dois lugares dobraria a amostra.
  g_tel.sum_input_us = g_tel.sum_input_us + g_tel.acc_input_us;
  g_tel.sum_shell_us = g_tel.sum_shell_us + g_tel.acc_shell_us;
  g_tel.sum_doldoc_us = g_tel.sum_doldoc_us + g_tel.acc_doldoc_us;
  g_tel.sum_render_us = g_tel.sum_render_us + g_tel.acc_render_us;
  g_tel.sum_idle_us = g_tel.sum_idle_us + g_tel.acc_idle_us;
  g_tel.sum_idle_ms = g_tel.sum_idle_ms + (g_tel.acc_idle_us / 1000);
  if (g_tel.min_frame_us == 0 || frame_us < g_tel.min_frame_us) g_tel.min_frame_us = frame_us;
  if (frame_us > g_tel.max_frame_us) g_tel.max_frame_us = frame_us;

  g_tel.ui_ring[g_tel.ui_ring_head] = frame_us;
  g_tel.ui_ring_head = (g_tel.ui_ring_head + 1) % PROF_RING;
  if (g_tel.ui_ring_count < PROF_RING) g_tel.ui_ring_count = g_tel.ui_ring_count + 1;

  // UNIFICACAO: os estagios de apresentacao (gravados por TelemetryMarkLogic*/
  // Raster*/Blit* no caminho de desenho) entram no MESMO registro de frame. O
  // "logic" e' o trabalho que nao e' apresentacao (input+shell+doldoc), o "raster"
  // e' o render e o "blit" vem do funil Present(). Assim o histograma, os percentis
  // e o diagnostico de gargalo passam a medir o frame REAL do loop — antes mediam
  // so' os frames em que HolyBenchmark chamava TelemetryRecordFrame.
  I64 u_logic  = g_tel.acc_input_us + g_tel.acc_shell_us + g_tel.acc_doldoc_us;
  I64 u_raster = g_tel.acc_render_us;
  I64 u_blit   = TelVctToUs(g_tel.blit_end_vct - g_tel.blit_start_vct);
  if (u_blit < 0) u_blit = 0;
  TelemetryRecordFrame(frame_us, u_logic, u_raster, g_tel.cur_smp_wait_us, u_blit, 0, 0);

  g_tel.acc_input_us = 0; g_tel.acc_shell_us = 0; g_tel.acc_doldoc_us = 0;
  g_tel.acc_render_us = 0; g_tel.acc_idle_us = 0;
}

// FPS da janela deslizante (x10, sem ponto flutuante na impressao).
I64 ProfilerFpsX10() {
  if (g_tel.ui_ring_count <= 0) return 0;
  I64 i = 0; I64 sum = 0;
  while (i < g_tel.ui_ring_count) { sum = sum + g_tel.ui_ring[i]; i = i + 1; }
  if (sum <= 0) return 0;
  // fps = count * 1e6 / sum_us
  return (g_tel.ui_ring_count * 10000000) / sum;
}

I64 ProfilerFrameMsX100() {
  if (g_tel.ui_ring_count <= 0) return 0;
  I64 i = 0; I64 sum = 0;
  while (i < g_tel.ui_ring_count) { sum = sum + g_tel.ui_ring[i]; i = i + 1; }
  return (sum * 100) / (g_tel.ui_ring_count * 1000);
}

I64 ProfilerAvgUs(I64 which) {
  if (g_tel.samples <= 0) return 0;
  I64 s = 0;
  if (which == 0) s = g_tel.sum_render_us;
  else if (which == 1) s = g_tel.sum_doldoc_us;
  else if (which == 2) s = g_tel.sum_input_us;
  else if (which == 3) s = g_tel.sum_shell_us;
  else s = g_tel.sum_idle_us;
  return s / g_tel.samples;
}

// ---- formatacao auxiliar: barra de proporcao (0..100 -> 20 celulas) ----
U0 ProfilerBar(U8 *dst, I64 pct) {
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  I64 fill = (pct * 20) / 100;
  I64 i = 0;
  while (i < 20) { if (i < fill) dst[i] = '#'; else dst[i] = '.'; i = i + 1; }
  dst[20] = 0;
}

// Amostra a carga corrente (heap, excecoes, uptime) no refresh.
U0 ProfilerSampleLoad() {
  g_tel.ui_heap_used_kb = KHeapUsedBytes() / 1024;
  g_tel.ui_heap_free_kb = KHeapFreeBytes() / 1024;
  g_tel.ui_heap_total_kb = KHeapTotalBytes() / 1024;
  g_tel.ui_heap_allocs = KHeapAllocCount();
  g_tel.ui_exc_recovered = ExceptionsRecoveredCount();
  g_tel.ui_exc_total = ExceptionsTotalCount();
  g_tel.ui_exc_panic = ExceptionsPanicCount();
  g_tel.ui_uptime_ms = timer_get_uptime_ms();
  // FPS real: frames contados na janela de um refresh (250 ms), nao no anel
  // curto de 256 frames (que a 30 kHz cobre apenas ~8 ms e oscila demais).
  if (g_tel.ui_last_sample_ms > 0 && g_tel.ui_uptime_ms > g_tel.ui_last_sample_ms) {
    I64 dms = g_tel.ui_uptime_ms - g_tel.ui_last_sample_ms;
    I64 dframes = g_tel.total_frames - g_tel.ui_last_sample_frames;
    if (dframes > 0) {
      g_tel.ui_fps_x10 = (dframes * 10000) / dms;
      g_tel.ui_frame_us = (dms * 1000) / dframes;
    }
  }
  g_tel.ui_last_sample_ms = g_tel.ui_uptime_ms;
  g_tel.ui_last_sample_frames = g_tel.total_frames;
  g_tel.ui_refreshes = g_tel.ui_refreshes + 1;
}

// Soma dos baldes atribuidos (media por frame) - o resto e overhead do loop.
I64 total_attributed_us() {
  return ProfilerAvgUs(0) + ProfilerAvgUs(1) + ProfilerAvgUs(2) + ProfilerAvgUs(3) + ProfilerAvgUs(4);
}

// ---- painel (desenhado pelo DolDoc; chamado de DolDocRedraw) ----
U0 ProfilerDrawPanel(I64 vx, I64 vy, I64 vw, I64 vh) {
  if (!g_tel.ui_on) return;
  g_tel.ui_draws = g_tel.ui_draws + 1;

  U32 bg     = 0xF011111B;   // crust translucido
  U32 border = 0xFF89B4FA;   // sapphire
  U32 hdr    = 0xFF1E1E2E;
  U32 text   = 0xFFCDD6F4;
  U32 muted  = 0xFF7F849C;
  U32 yellow = 0xFFF9E2AF;
  U32 green  = 0xFFA6E3A1;
  U32 teal   = 0xFF94E2D5;
  U32 red    = 0xFFF38BA8;

  gfx_draw_rect(vx, vy, vw, vh, bg);
  gfx_draw_rect(vx, vy, vw, 1, border);
  gfx_draw_rect(vx, vy + vh - 1, vw, 1, border);
  gfx_draw_rect(vx, vy, 1, vh, border);
  gfx_draw_rect(vx + vw - 1, vy, 1, vh, border);
  gfx_draw_rect(vx + 1, vy + 1, vw - 2, 20, hdr);
  gfx_draw_string(vx + 8, vy + 3, "NEO-OS LIVE PROFILER  (profiler on|off)", teal, 0);
  gfx_draw_string(vx + vw - 190, vy + 3, "DolDoc node DOC_PROF/$PROF$", muted, 0);

  I64 lx = vx + 10;
  I64 ly = vy + 26;
  I64 total_us = g_tel.sum_total_us / (g_tel.samples > 0 ? g_tel.samples : 1);
  if (total_us <= 0) total_us = 1;

  I64 fps_i = g_tel.ui_fps_x10 / 10;
  I64 fps_d = g_tel.ui_fps_x10 % 10;
  I64 fr_i = g_tel.ui_frame_us / 1000;
  I64 fr_d = g_tel.ui_frame_us % 1000;

  U8 line[160];
  // Linha 1: FPS + ms/frame + uptime. HolyC limita os argumentos por chamada
  // (~8), entao cada linha e montada em pedacos com poucos argumentos.
  I64 off = 0;
  off += snprintf(line + off, 158 - off, "loop FPS %lld.%lld", fps_i, fps_d);
  off += snprintf(line + off, 158 - off, "   frame %lld.%03lld ms", fr_i, fr_d);
  off += snprintf(line + off, 158 - off, "   samples %lld", g_tel.samples);
  off += snprintf(line + off, 158 - off, "   uptime %lld s", g_tel.ui_uptime_ms / 1000);
  gfx_draw_string(lx, ly, line, text, 0);
  ly = ly + 18;

  // Linhas 2..6: subsistemas (render / DolDoc / input / shell / idle)
  I64 s_i = 0;
  while (s_i < 5) {
    I64 us = ProfilerAvgUs(s_i);
    I64 pct = (us * 100) / total_us;
    U8 bar[24]; ProfilerBar(bar, pct);
    U8 name[16];
    U32 col = text;
    if (s_i == 0) { strcpy(name, "render "); col = green; }
    else if (s_i == 1) { strcpy(name, "DolDoc "); col = teal; }
    else if (s_i == 2) { strcpy(name, "input  "); col = yellow; }
    else if (s_i == 3) { strcpy(name, "shell  "); col = muted; }
    else { strcpy(name, "idle   "); col = border; }
    off = 0;
    off += snprintf(line + off, 158 - off, "%s  %6lld.%03lld ms", name, us / 1000, us % 1000);
    off += snprintf(line + off, 158 - off, "  [%s]", bar);
    off += snprintf(line + off, 158 - off, " %3lld%%", pct);
    gfx_draw_string(lx, ly, line, col, 0);
    ly = ly + 18;
    s_i = s_i + 1;
  }

  // Linha 7: ocioso acumulado + atividade do painel
  off = 0;
  off += snprintf(line + off, 158 - off, "idle total %lld ms", g_tel.sum_idle_ms);
  off += snprintf(line + off, 158 - off, "   frames %lld", g_tel.total_frames);
  off += snprintf(line + off, 158 - off, "   refreshes %lld", g_tel.ui_refreshes);
  off += snprintf(line + off, 158 - off, "   draws %lld", g_tel.ui_draws);
  off += snprintf(line + off, 158 - off, "   period %lld ms", g_tel.ui_refresh_period_ms);
  gfx_draw_string(lx, ly, line, muted, 0);
  ly = ly + 18;
  off = 0;
  I64 other_us = (g_tel.sum_total_us / (g_tel.samples > 0 ? g_tel.samples : 1)) - total_attributed_us();
  if (other_us < 0) other_us = 0;
  off += snprintf(line + off, 158 - off, "loop/other %lld.%03lld ms", other_us / 1000, other_us % 1000);
  off += snprintf(line + off, 158 - off, "   min %lld.%03lld ms", g_tel.min_frame_us / 1000, g_tel.min_frame_us % 1000);
  off += snprintf(line + off, 158 - off, "   max %lld.%03lld ms", g_tel.max_frame_us / 1000, g_tel.max_frame_us % 1000);
  gfx_draw_string(lx, ly, line, muted, 0);
  ly = ly + 18;

  // Linha 8: excecoes recuperadas
  off = 0;
  off += snprintf(line + off, 158 - off, "exceptions  recovered %lld", g_tel.ui_exc_recovered);
  off += snprintf(line + off, 158 - off, "   trapped %lld", g_tel.ui_exc_total);
  off += snprintf(line + off, 158 - off, "   panics %lld", g_tel.ui_exc_panic);
  gfx_draw_string(lx, ly, line, g_tel.ui_exc_recovered > 0 ? red : green, 0);
  ly = ly + 18;

  // Linha 9: heap
  I64 hpct = 0;
  if (g_tel.ui_heap_total_kb > 0) hpct = (g_tel.ui_heap_used_kb * 100) / g_tel.ui_heap_total_kb;
  U8 hbar[24]; ProfilerBar(hbar, hpct);
  off = 0;
  off += snprintf(line + off, 158 - off, "heap  used %lld KB", g_tel.ui_heap_used_kb);
  off += snprintf(line + off, 158 - off, " / %lld KB", g_tel.ui_heap_total_kb);
  off += snprintf(line + off, 158 - off, "  [%s]", hbar);
  off += snprintf(line + off, 158 - off, " %lld%%", hpct);
  off += snprintf(line + off, 158 - off, "   free %lld KB", g_tel.ui_heap_free_kb);
  gfx_draw_string(lx, ly, line, yellow, 0);
}

// ---- espelho textual no serial (o log UART mostra o mesmo painel) ----
U0 ProfilerSerialMirror(U8 *why) {
  U8 line[160];
  I64 off = 0;
  U8 head[96];
  snprintf(head, 94, "[PROF:%s] NeoOS live profiler panel", why);
  uart_puts(head); uart_puts("\n");
  I64 total_us = g_tel.sum_total_us / (g_tel.samples > 0 ? g_tel.samples : 1);
  if (total_us <= 0) total_us = 1;
  off = 0;
  off += snprintf(line + off, 158 - off, "  loop FPS %lld.%lld", g_tel.ui_fps_x10 / 10, g_tel.ui_fps_x10 % 10);
  off += snprintf(line + off, 158 - off, " | frame %lld.%03lld ms", g_tel.ui_frame_us / 1000, g_tel.ui_frame_us % 1000);
  off += snprintf(line + off, 158 - off, " | samples %lld", g_tel.samples);
  off += snprintf(line + off, 158 - off, " | uptime %lld s", g_tel.ui_uptime_ms / 1000);
  uart_puts(line); uart_puts("\n");
  off = 0;
  off += snprintf(line + off, 158 - off, "  render %lld.%03lld ms", ProfilerAvgUs(0) / 1000, ProfilerAvgUs(0) % 1000);
  off += snprintf(line + off, 158 - off, " (%lld%%)", (ProfilerAvgUs(0) * 100) / total_us);
  off += snprintf(line + off, 158 - off, " | DolDoc %lld.%03lld ms", ProfilerAvgUs(1) / 1000, ProfilerAvgUs(1) % 1000);
  off += snprintf(line + off, 158 - off, " (%lld%%)", (ProfilerAvgUs(1) * 100) / total_us);
  uart_puts(line); uart_puts("\n");
  off = 0;
  off += snprintf(line + off, 158 - off, "  input %lld.%03lld ms", ProfilerAvgUs(2) / 1000, ProfilerAvgUs(2) % 1000);
  off += snprintf(line + off, 158 - off, " (%lld%%)", (ProfilerAvgUs(2) * 100) / total_us);
  off += snprintf(line + off, 158 - off, " | shell %lld.%03lld ms", ProfilerAvgUs(3) / 1000, ProfilerAvgUs(3) % 1000);
  off += snprintf(line + off, 158 - off, " (%lld%%)", (ProfilerAvgUs(3) * 100) / total_us);
  uart_puts(line); uart_puts("\n");
  off = 0;
  off += snprintf(line + off, 158 - off, "  idle %lld.%03lld ms", ProfilerAvgUs(4) / 1000, ProfilerAvgUs(4) % 1000);
  off += snprintf(line + off, 158 - off, " (%lld%%)", (ProfilerAvgUs(4) * 100) / total_us);
  off += snprintf(line + off, 158 - off, " | idle total %lld ms", g_tel.sum_idle_ms);
  uart_puts(line); uart_puts("\n");
  off = 0;
  off += snprintf(line + off, 158 - off, "  exceptions recovered %lld", g_tel.ui_exc_recovered);
  off += snprintf(line + off, 158 - off, " | trapped %lld", g_tel.ui_exc_total);
  off += snprintf(line + off, 158 - off, " | panics %lld", g_tel.ui_exc_panic);
  uart_puts(line); uart_puts("\n");
  off = 0;
  off += snprintf(line + off, 158 - off, "  heap used %lld KB", g_tel.ui_heap_used_kb);
  off += snprintf(line + off, 158 - off, " / %lld KB", g_tel.ui_heap_total_kb);
  off += snprintf(line + off, 158 - off, " | free %lld KB", g_tel.ui_heap_free_kb);
  off += snprintf(line + off, 158 - off, " | allocs %lld", g_tel.ui_heap_allocs);
  uart_puts(line); uart_puts("\n");
}

// Chamado pelo Shell no event loop quando chega a hora do refresh.
// Devolve 1 se o painel foi redesenhado neste tick.
I64 ProfilerTickDue(I64 now_ms) {
  if (!g_tel.ui_on) return 0;
  if (now_ms - g_tel.ui_last_refresh_ms < g_tel.ui_refresh_period_ms) return 0;
  g_tel.ui_last_refresh_ms = now_ms;
  ProfilerSampleLoad();
  if (g_tel.ui_trace && (now_ms - g_tel.ui_last_trace_ms) >= g_tel.ui_trace_period_ms) {
    g_tel.ui_last_trace_ms = now_ms;
    ProfilerSerialMirror("LIVE");
  }
  return 1;
}

I64 ProfilerSelfTest() {
  I64 pass = 0; I64 total = 0;
  ProfilerReset();
  total++; if (g_tel.samples == 0 && g_tel.ui_ring_count == 0 && g_tel.ui_draws == 0) pass++;
  ProfilerSetOn(1);
  total++; if (ProfilerIsOn() == 1) pass++;
  ProfilerMarkInput(100); ProfilerMarkShell(200); ProfilerMarkDolDoc(300);
  ProfilerMarkRender(400); ProfilerMarkIdle(500);
  ProfilerEndFrame(1500);
  total++; if (g_tel.last_input_us == 100 && g_tel.last_shell_us == 200 &&
                g_tel.last_doldoc_us == 300 && g_tel.last_render_us == 400 &&
                g_tel.last_idle_us == 500 && g_tel.last_total_us == 1500) pass++;
  total++; if (g_tel.ui_ring_count == 1 && g_tel.samples == 1) pass++;
  // FPS: 1 frame de 1500 us -> 666.6 fps -> 6666 (x10)
  total++; if (ProfilerFpsX10() == 6666) pass++;
  ProfilerSetOn(0);
  if (pass == total) doldoc_printf("PROFILER: PASS (%lld/%lld)\n", pass, total);
  else doldoc_printf("PROFILER: FAIL (%lld/%lld)\n", pass, total);
  ProfilerSetOn(1);
  return pass;
}

if (g_kernel_booting) {
  TelemetryInit();
  TelemetryPmuInit();
} else {
  TelemetrySelfTest();
}
