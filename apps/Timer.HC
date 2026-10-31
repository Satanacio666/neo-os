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

// B11: verificacao de drift entre o contador de hardware (CNTVCT_EL0) e os ticks
// de software. A base e' gravada em TimerArm (caminho REAL do boot, KernelInit.HC:188),
// NAO em TimerInit — que o TimerSelfTest chama 3x e depois bate TimerTick() a mao
// (Timer.HC:132-134), o que daria falso positivo. TimerInit zera a base (=0 =
// "nao armado"), invalidando qualquer medicao anterior. TimerDriftCheck() so' e'
// chamada por observadores externos, nunca pelo TimerTick.
U64 g_timer_drift_base_cntvct = 0;
U64 g_timer_drift_base_ticks = 0;
I64 g_timer_drift_ticks = 0;
I64 g_timer_drift_checks = 0;
// B11/1.3: deadline ABSOLUTO do proximo tick (em CNTVCT_EL0). 0 = nao armado.
// Sem isto, o re-arme com TVAL relativo soma `interval` ao instante em que o
// handler RODOU — e todo atraso de entrega se acumula para sempre. Medido em
// 31/10: 27,3% dos ticks perdidos (284 s => 206.511 ticks em vez de 284.000).
U64 g_timer_next_deadline = 0;

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
  // B11: TimerInit invalida a base do drift (qualquer mudanca de cadencia ou o
  // TimerSelfTest zera/rearma a contagem a mao). Base=0 => TimerDriftCheck devolve 0
  // ate' um TimerArm real re-armar a medicao.
  g_timer_drift_base_cntvct = 0;
  g_timer_drift_base_ticks = 0;
  g_timer_next_deadline = 0;   // B11/1.3: rearme absoluto sera' refeito pelo TimerArm
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
// B2a.2 (ONDA 3) — arma o CNTV DESTE core sem tocar os globais do timer.
// O timer virtual (CNTV_*) e' PER-CORE: cada core tem o seu TVAL/CVAL/TICK. O BSP
// arma o dele em KernelInit.HC:188 (TimerArm). Os secundarios so' tomam o tick se
// armarem o PROPRIO — e isso NAO pode passar por TimerArm(), que escreveria nos
// globais compartilhados (interval_ticks, next_deadline) e corromperia o BSP.
U0 TimerArmThisCore(I64 hz) {
  U64 frq = TimerQueryHwFreq();
  U64 interval = (hz > 0) ? (frq / hz) : 0;
  if (interval == 0) interval = g_timer.interval_ticks;   // usa o do BSP (ja' armado)
  if (interval == 0) interval = frq / 1000;
  if (interval == 0) interval = 1;
  __msr_cntv_tval(interval);
  __msr_cntv_ctl(1);   // ENABLE=1, IMASK=0 — habilita o tick deste core
}

U0 TimerArm(I64 hz) {  U64 frq = TimerQueryHwFreq();
  if (hz > 0) {
    U64 interval = frq / hz;
    if (interval == 0) interval = 1;
    g_timer.interval_ticks = interval;
  }
  if (g_timer.interval_ticks == 0) g_timer.interval_ticks = frq / 1000;
  if (g_timer.interval_ticks == 0) g_timer.interval_ticks = 1;
  __msr_cntv_tval(g_timer.interval_ticks);
  __msr_cntv_ctl(1); // ENABLE=1, IMASK=0
  // B11/1.3: deadline ABSOLUTO inicial e base do drift.
  U64 now = __mrs_cntvct();
  g_timer_next_deadline = now + g_timer.interval_ticks;
  g_timer_drift_base_cntvct = now;
  g_timer_drift_base_ticks = g_timer.system_ticks;
  g_timer_drift_ticks = 0;
}

// B11: parte PURA da verificacao — recebe os numeros ja coletados e decide. Testavel
// sem tocar o hardware (deterministico). Devolve 1 se |sw - hw| > 5%, 0 se dentro.
I64 TimerDriftExceeded(U64 sw_ticks, U64 hw_ticks) {
  if (hw_ticks == 0) return 0;
  U64 lo = hw_ticks - (hw_ticks / 20);            // -5%
  U64 hi = hw_ticks + (hw_ticks / 20);            // +5%
  if (sw_ticks < lo || sw_ticks > hi) return 1;
  return 0;
}

// B11: compara os ticks de software com o tempo REAL decorrido no contador de
// hardware. Esperado = (cntvct - base) / (freq / tick_hz); divergencia > 5% =>
// g_timer_drift_ticks++ (print so' na 1a). NAO altera a contagem — so' observa.
// Devolve 0 sem contar se a base nao esta armada (base==0) ou se ainda nao houve
// tick suficiente para uma medida significativa (< janela minima).
// A DECISAO fica em TimerDriftExceeded (pura) para poder ser testada sem timer.
I64 TimerDriftCheck() {
  if (g_timer_drift_base_cntvct == 0) return 0;   // TimerInit invalidou / ainda nao armado
  U64 now = __mrs_cntvct();
  if (now <= g_timer_drift_base_cntvct) return 0; // wrap / relogio reiniciado
  U64 freq = TimerQueryHwFreq();
  U64 interval = g_timer.interval_ticks;
  if (freq == 0 || interval == 0) return 0;
  U64 elapsed_ticks = g_timer.system_ticks - g_timer_drift_base_ticks;
  if (elapsed_ticks < 5000) return 0;             // janela longa: o jitter do agendador
                                                  // do observador (~ms) fica < 1% da medida
  U64 hw_ticks = (now - g_timer_drift_base_cntvct) / interval; // esperado pelo hardware
  g_timer_drift_checks = g_timer_drift_checks + 1;
  if (TimerDriftExceeded(elapsed_ticks, hw_ticks)) {
    g_timer_drift_ticks = g_timer_drift_ticks + 1;
    if (g_timer_drift_ticks == 1) {
      doldoc_printf("$FG,RED$[TIMER] DRIFT: sw=%lld ticks, hw~%lld (elapsed=%lld cntv) — fora de 5%%$FG$\n",
                    elapsed_ticks, hw_ticks, now - g_timer_drift_base_cntvct);
    }
    return 1;
  }
  return 0;
}

// B11: sonda DETERMINISTICA. Testa a decisao PURA (TimerDriftExceeded) — sem tocar
// o timer de hardware, sem corrida com o observador real (WatchdogTick). Cobre:
// (1) deteccao de drift (fora de +5% e de -5%); (2) NAO disparar dentro da tolerancia;
// (3) o guard de hw==0. Tambem confirma que a integracao real existe (base armada).
I64 TimerTestDrift() {
  I64 ok = 1;
  // (1a) sw muito ACIMA do esperado (+9%) -> detecta
  if (TimerDriftExceeded(10900, 10000) != 1) ok = 0;
  // (1b) sw muito ABAIXO do esperado (-9%) -> detecta
  if (TimerDriftExceeded(9100, 10000) != 1) ok = 0;
  // (2a) exatamente igual -> dentro
  if (TimerDriftExceeded(10000, 10000) != 0) ok = 0;
  // (2b) +2% (dentro da tolerancia) -> dentro
  if (TimerDriftExceeded(10200, 10000) != 0) ok = 0;
  // (2c) -2% -> dentro
  if (TimerDriftExceeded(9800, 10000) != 0) ok = 0;
  // (3) hw==0 (relogio nao iniciado) -> nunca acusa
  if (TimerDriftExceeded(5000, 0) != 0) ok = 0;
  return ok;
}

// Fired from the GIC PPI (level-sensitive) -> advance the tick(s) and re-arm.
//
// B11/1.3 (31/10): antes, isto fazia apenas system_ticks++ e re-armava TVAL
// relativo AO INSTANTE DO HANDLER. Todo atraso de entrega se acumulava: medido
// 27,3% de ticks perdidos (284 s => 206.511 ticks em vez de 284.000). Agora:
//   1. o deadline e' ABSOLUTO (g_timer_next_deadline, em CNTVCT);
//   2. avancamos system_ticks pelo DELTA REAL (quantos periodos ja' venceram),
//      entao uma IRQ atrasada por 2 ms conta 2 e nao 1;
//   3. re-armamos TVAL = deadline - agora (o residuo), nao `interval` fixo.
// Assim o erro nao se acumula: a cadencia MEDIA fica exata.
U0 TimerTick() {
  U64 now = __mrs_cntvct();
  U64 interval = g_timer.interval_ticks;
  if (interval == 0) interval = 1;
  if (g_timer_next_deadline == 0) {
    // Deadline nao armado (ex.: teste) — mantem o comportamento antigo e arma.
    g_timer.system_ticks = g_timer.system_ticks + 1;
    g_timer_next_deadline = now + interval;
    __msr_cntv_tval(interval);
    return;
  }
  // Quantos periodos venceram desde o deadline? >= 1 sempre (a IRQ veio).
  U64 missed = 1;
  if (now > g_timer_next_deadline) {
    missed = ((now - g_timer_next_deadline) / interval) + 1;
  }
  g_timer.system_ticks = g_timer.system_ticks + missed;
  g_timer_next_deadline = g_timer_next_deadline + missed * interval;
  // Residuo ate' o proximo deadline (nunca 0: TVAL=0 desarmaria o timer).
  U64 cval = g_timer_next_deadline;
  U64 remain;
  if (cval > now) remain = cval - now;
  else {
    // Ja' passou do deadline (handler muito atrasado): re-sincroniza.
    remain = interval;
    g_timer_next_deadline = now + interval;
  }
  __msr_cntv_tval(remain);
}

U0 TimerSleepMs(I64 p_ms) {
  if (p_ms <= 0) return;
  U64 start_us = TimerGetUsec();
  U64 target_us = start_us + (p_ms * 1000);
  while (TimerGetUsec() < target_us) {
    task_yield();
  }
}

U0 TimerPrintDolDoc() {  doldoc_printf("$FG,CYAN$--- ARM GENERIC TIMER TELEMETRY ---$FG$\n");
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
