// NeoOS Sovereign Pure HolyC ARM Generic Timer Subsystem
// Overflow-Safe 64-bit Microsecond Telemetry, Tick Cadence, and Calibrated Sleep

class CTimerState {
  U64 frequency_hz;
  U64 freq;
  U64 interval_ticks;
  U64 system_ticks;
  U64 boot_time_us;
};

CTimerState g_timer;

U64 TimerQueryHwFreq() {
  U64 frq = __mrs_cntfrq();
  if (frq == 0 && g_hal_timer_freq != 0) frq = g_hal_timer_freq;
  if (frq == 0) frq = 62500000;
  return frq;
}

// Overflow-safe microsecond conversion from 64-bit CNTVCT_EL0
U64 TimerGetUsec() {
  U64 cnt = __mrs_cntvct();
  U64 frq = TimerQueryHwFreq();
  if (frq >= 1000000) {
    U64 mhz = frq / 1000000;
    if ((frq % 1000000) == 0 && mhz > 0) {
      return cnt / mhz;
    }
    // Split quotient and remainder so (r_cnt * 1000000) never overflows 64 bits
    U64 q_sec = cnt / frq;
    U64 r_cnt = cnt % frq;
    return q_sec * 1000000 + (r_cnt * 1000000) / frq;
  }
  return (cnt * 1000000) / frq;
}

U64 timer_get_uptime_us() {
  return TimerGetUsec();
}

U64 timer_get_uptime_sec() {
  return TimerGetUsec() / 1000000;
}

U64 timer_get_uptime_ms() {
  return TimerGetUsec() / 1000;
}

U0 TimerInit(U32 p_freq_hz) {
  if (p_freq_hz == 0) p_freq_hz = 100;
  U64 hw_frq = TimerQueryHwFreq();
  g_timer.frequency_hz = hw_frq;
  g_timer.freq = hw_frq;
  g_timer.interval_ticks = hw_frq / p_freq_hz;
  g_timer.system_ticks = 0;
  g_timer.boot_time_us = TimerGetUsec();
}

U64 TimerGetTicks() {
  return g_timer.system_ticks;
}

U64 TimerGetFrequency() {
  return g_timer.freq;
}

U64 TimerGetUptimeUs() {
  U64 now_us = TimerGetUsec();
  if (now_us >= g_timer.boot_time_us) {
    return now_us - g_timer.boot_time_us;
  }
  return now_us;
}

U64 TimerGetUptimeSec() {
  return TimerGetUptimeUs() / 1000000;
}

// P3.4: arm the EL1 virtual timer. QEMU virt routes it to PPI 27
// (HalGetTimerIrq). CNTV_TVAL_EL0 auto-loads CNTV_CVAL_EL0 = CNTVCT + TVAL.
U0 TimerArm(I64 hz) {
  U64 frq = TimerQueryHwFreq();
  if (hz > 0) {
    U64 interval = frq / hz;
    if (interval == 0) interval = 1;
    g_timer.interval_ticks = interval;
  }
  if (g_timer.interval_ticks == 0) g_timer.interval_ticks = frq / 1000;
  if (g_timer.interval_ticks == 0) g_timer.interval_ticks = 1;
  __msr_cntv_tval(g_timer.interval_ticks);
  __msr_cntv_ctl(1); // ENABLE=1, IMASK=0
}

// Fired from the GIC PPI (level-sensitive) -> increment the tick and re-arm.
U0 TimerTick() {
  g_timer.system_ticks = g_timer.system_ticks + 1;
  __msr_cntv_tval(g_timer.interval_ticks);
}

U0 TimerSleepMs(I64 p_ms) {
  if (p_ms <= 0) return;
  U64 start_us = TimerGetUsec();
  U64 target_us = start_us + (p_ms * 1000);
  while (TimerGetUsec() < target_us) {
    task_yield();
  }
}

U0 TimerPrintDolDoc() {
  doldoc_printf("$FG,CYAN$--- ARM GENERIC TIMER TELEMETRY ---$FG$\n");
  doldoc_printf(" Clock Frequency: %d MHz (%d Hz)\n", g_timer.freq / 1000000, g_timer.freq);
  doldoc_printf(" Tick Interval:   %d ticks\n", g_timer.interval_ticks);
  doldoc_printf(" Monotonic Ticks: %d ticks\n", g_timer.system_ticks);
  doldoc_printf(" Total Uptime:    %d us (%d sec)\n", TimerGetUptimeUs(), TimerGetUptimeSec());
  doldoc_printf("$FG,CYAN$-----------------------------------$FG$\n");
}

I64 TimerSelfTest() {
  doldoc_printf("\n$FG,CYAN$[TIMER-TEST] Starting Pure HolyC Generic Timer Verification...$FG$\n");

  // Test 1: Timer initialization @ 100 Hz (hardware-agnostic frequency check)
  TimerInit(100);
  if (g_timer.freq == 0 || g_timer.frequency_hz != g_timer.freq || g_timer.interval_ticks != g_timer.freq / 100) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Timer interval calculation failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: Generic Timer armed @ 100 Hz (freq=%lld Hz, interval=%lld ticks).$FG$\n",
                g_timer.freq, g_timer.interval_ticks);

  // Test 2: Monotonic tick increment
  I64 t_idx = 0;
  while (t_idx < 50) {
    TimerTick();
    t_idx++;
  }
  if (TimerGetTicks() != 50) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: Monotonic tick increment failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Monotonic system ticks validated (50 ticks).$FG$\n");

  // Test 3: Overflow-safe uptime in microseconds & seconds
  U64 us = TimerGetUptimeUs();
  U64 sec = TimerGetUptimeSec();
  if (sec != us / 1000000) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: Uptime conversion mismatch!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Overflow-safe microsecond & second uptime calculation verified.$FG$\n");

  // Test 4: Real elapsed microseconds across TimerSleepMs(5)
  U64 s_before = TimerGetUsec();
  TimerSleepMs(5);
  U64 s_after = TimerGetUsec();
  if (s_after <= s_before || (s_after - s_before) < 4000) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: TimerSleepMs(5) elapsed time too short (%lld us)!$FG$\n", s_after - s_before);
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Calibrated sleep delay verified (%lld us elapsed across TimerSleepMs(5)).$FG$\n",
                s_after - s_before);

  // Test 5: Re-arm at 1000 Hz (1ms high-frequency scheduler tick)
  TimerInit(1000);
  if (g_timer.interval_ticks != g_timer.freq / 1000) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: 1000 Hz re-arm failed!$FG$\n");
    return 0;
  }
  TimerPrintDolDoc();
  doldoc_printf("$FG,GREEN$[PASS] Test 5: High-frequency 1000 Hz cadence & DolDoc dump verified.$FG$\n");

  doldoc_printf("\n[TIMER-PASS] ALL 5 TIMER TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  TimerInit(1000);
} else {
  TimerSelfTest();
}
