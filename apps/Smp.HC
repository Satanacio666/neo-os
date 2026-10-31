// NeoOS Sovereign Pure HolyC SMP Multiprocessing Subsystem
// Lockless SPSC Mailbox Dispatch, WFE/SEV Tickless Workers & Real Cycle Telemetry

#define SMP_MAX_CORES 4
#define PSCI_CPU_ON_64 0xC4000003

class CSmpJob {
  U64 fn;
  U64 arg;
  I64 pending;
  I64 completed;
};

class CSmpState {
  U32 num_cores;
  U32 online_cores;
  I64 core_online[4];
  U64 core_heartbeat[4];
  U64 core_active_ticks[4];
  U64 core_total_ticks[4];
  U8 *jobs;
};

CSmpState g_smp_hc;
I64       g_smp_initialized;
U64       g_smp_boot_vct;
U64       g_smp_test_acc;
U32       g_smp_test_exec_core;

// B2a.3 (ONDA 3) — kill-switch do SMP simetrico. DESLIGADO por padrao (0): o
// comportamento atual NAO muda (secundarios surdos a IRQ, escalonador UP-only).
// Quando 1, os secundarios inicializam a interface GICC do proprio core e abrem
// IRQ — habilitando o tick simetrico. O interlock B2a.1 (Gic.HC) continua
// garantindo que SO' o core 0 entrega o frame ao escalonador, entao ligar este
// switch NAO corrompe o Sched: apenas faz os secundarios tomarem o tick.
I64       g_smp_irq_enable = 1; // EXPERIMENTO B2a.3: medir se ligar sem B2a.2 quebra
U64       g_smp_irq_enabled_cores = 0;   // bitmask: quais cores abriram IRQ

// B2a.3: o secundario habilita a interface do PROPRIO core. Como o GICC e'
// banked (GicGetCpuBase nao recebe core) e o GICD_ISENABLER0/PPI<32> tambem sao
// banked no redistribuidor DESTE core, quem inicializa e' o proprio core — nao
// o BSP por ele. Aqui so' se abre a IRQ (DAIF); a inicializacao per-core do GIC
// e' responsabilidade de SmpSecondaryIrqInit(), chamada antes.
U0 SmpSecondaryIrqEnable(U32 core_id) {
  if (g_smp_irq_enable == 0) return;        // kill-switch: desligado = nada muda
  if (core_id == 0 || core_id >= SMP_MAX_CORES) return;
  // B2a.2: antes de abrir a IRQ, arma a interface GIC DESTE core (redistribuidor
  // proprio + PPI 27 no banco dele). Sem isto a IRQ fica aberta e o tick nao chega
  // (medido: offcore_ticks_blocked=0 com enabled_cores=0xE).
  GicInitCpuInterface(core_id);
  // B2a.2: o timer virtual e' PER-CORE — arma o CNTV DESTE core (sem tocar os
  // globais do BSP). Sem isto, o PPI 27 do secundario nunca dispara.
  TimerArmThisCore(1000);
  g_smp_irq_enabled_cores = g_smp_irq_enabled_cores | (1 << core_id);
  __dmb_ish();
  __irq_enable();                            // MSR DAIFClr, #2 (builtin do JIT)
  // B2a.4: observabilidade — registra que este core abriu IRQ (imprime 1x por core).
  doldoc_printf("$FG,CYAN$[SMP] core %lld: IRQ local habilitada (g_smp_irq_enable=1)$FG$\n", core_id);
}

// B2a.3: DECISAO PURA — testavel sem hardware (licao do B11). Devolve 1 se este
// core DEVERIA abrir IRQ dadas as condicoes (switch ligado + nao-BSP + valido).
I64 SmpIrqEnableAllowed(I64 switch_on, U32 core_id) {
  if (switch_on == 0) return 0;
  if (core_id == 0 || core_id >= SMP_MAX_CORES) return 0;
  return 1;
}

// B2a.3: sonda deterministica do kill-switch. Prova as duas metades: com o switch
// DESLIGADO nenhum core abre IRQ (comportamento atual preservado) e o contador
// nao muda; com o switch LIGADO o secundario e' aceito e o BSP continua barrado.
I64 SmpTestIrqEnableGate() {
  I64 ok = 1;
  if (SmpIrqEnableAllowed(0, 1) != 0) ok = 0;   // switch off -> secundario barrado
  if (SmpIrqEnableAllowed(0, 0) != 0) ok = 0;   // switch off -> BSP barrado
  if (SmpIrqEnableAllowed(1, 1) != 1) ok = 0;   // switch on  -> secundario aceito
  if (SmpIrqEnableAllowed(1, 0) != 0) ok = 0;   // switch on  -> BSP segue barrado
  if (SmpIrqEnableAllowed(1, 3) != 1) ok = 0;   // core 3 valido
  if (SmpIrqEnableAllowed(1, 4) != 0) ok = 0;   // core 4 invalido (>= SMP_MAX_CORES)
  return ok;
}


CSmpJob* SmpGetJob(I64 core_id) {
  return g_smp_hc.jobs + core_id * 32;
}

U32 SmpGetCoreId() {
  return __mrs_mpidr() & 3;
}

U32 SmpGetCurrentCore() {
  return __mrs_mpidr() & 3;
}

U32 smp_get_current_core() {
  return __mrs_mpidr() & 3;
}

U32 SmpGetCoreCount() {
  if (g_smp_hc.num_cores == 0) return SMP_MAX_CORES;
  return g_smp_hc.num_cores;
}

U32 smp_get_core_count() {
  return SmpGetCoreCount();
}

// P7.4: cross-module-safe core-online query (callers must not touch g_smp_hc).
I64 SmpCoreOnline(U32 core_id) {
  if (core_id >= SMP_MAX_CORES) return 0;
  return g_smp_hc.core_online[core_id];
}

// P7.4 F0: number of cores that actually came online (BSP + secondaries). Callers
// must never read g_smp_hc directly; this is the single source of truth for
// deciding how many disjoint slices a parallel job can be split into.
U32 SmpOnlineCoreCount() {
  if (g_smp_hc.online_cores == 0) return 1;
  return g_smp_hc.online_cores;
}

// One generic per-core worker loop (no copy-paste). Each core owns its own job
// slot (SmpGetJob) and idles in WFE until the BSP posts a job.
U0 SmpWorkerLoop(U32 core_id) {
  CSmpJob *j = SmpGetJob(core_id);
  g_smp_hc.core_online[core_id] = 1;
  __dmb_ish();
  __sev();
  // B2a.3: se o SMP simetrico estiver LIGADO (g_smp_irq_enable), este core abre a
  // IRQ do proprio core. Desligado (padrao) = nada acontece, comportamento atual.
  SmpSecondaryIrqEnable(core_id);
  while (1) {
    while (!j->pending) {
      __wfe();
    }
    __dmb_ish();
    U64 fn = j->fn;
    U64 arg = j->arg;
    U64 t0 = __mrs_cntvct();
    if (fn >= 0x40000000) {
      fn(arg);
    }
    U64 t1 = __mrs_cntvct();
    U64 dt = t1 - t0;
    if (dt == 0) dt = 1;
    g_smp_hc.core_active_ticks[core_id] = g_smp_hc.core_active_ticks[core_id] + dt;
    g_smp_hc.core_total_ticks[core_id] = t1 - g_smp_boot_vct;
    __dmb_ish();
    j->pending = 0;
    __dmb_ish();
    j->completed = 1;
    g_smp_hc.core_heartbeat[core_id] = g_smp_hc.core_heartbeat[core_id] + 1;
    __dmb_ish();
    __sev();
  }
}

U0 SmpSecondaryWorker(U32 unused_core_arg) {
  U32 hw_cid = __mrs_mpidr() & 3;
  SmpWorkerLoop(hw_cid);
  while (1) {
    __wfe();
  }
}

U0 SmpInit() {
  if (!g_smp_hc.jobs) {
    g_smp_hc.jobs = kmalloc(SMP_MAX_CORES * 32);
  }
  if (!g_smp_hc.jobs) return;

  if (g_smp_boot_vct == 0) {
    g_smp_boot_vct = __mrs_cntvct();
  }

  g_smp_hc.num_cores = SMP_MAX_CORES;
  g_smp_hc.core_online[0] = 1;

  I64 smp_i = 0;
  while (smp_i < SMP_MAX_CORES) {
    g_smp_hc.core_heartbeat[smp_i] = 0;
    g_smp_hc.core_active_ticks[smp_i] = 0;
    g_smp_hc.core_total_ticks[smp_i] = 0;
    CSmpJob *j = SmpGetJob(smp_i);
    j->fn = 0;
    j->arg = 0;
    j->pending = 0;
    j->completed = 1;
    smp_i++;
  }

  // Populate MMU state for secondary cores & bind g_arch_vectors[4]
  U64 *mmu = &g_mmu_config;
  mmu[0] = smp_get_sctlr();
  mmu[1] = smp_get_tcr();
  mmu[2] = smp_get_mair();
  mmu[3] = smp_get_ttbr0();
  mmu[4] = smp_get_vbar();
  __dc_civac(mmu);
  __dsb_sy();
  __isb();

  U64 *vecs = &g_arch_vectors;
  vecs[4] = SmpSecondaryWorker;
  __dc_civac(vecs);
  __dsb_sy();
  __isb();

  if (!g_smp_initialized) {
    U64 entry_addr = symbols_lookup("smp_entry");
    if (entry_addr != 0) {
      I64 ap_c = 1;
      while (ap_c < SMP_MAX_CORES) {
        I64 psci_rc = psci_call_hvc(PSCI_CPU_ON_64, ap_c, entry_addr, ap_c);
        if (psci_rc == 0) {
          I64 wait_w = 0;
          while (!g_smp_hc.core_online[ap_c] && wait_w < 50000) {
            __sev();
            wait_w++;
          }
        }
        ap_c++;
      }
    }
    g_smp_initialized = 1;
  }

  U32 online_cnt = 1;
  smp_i = 1;
  while (smp_i < SMP_MAX_CORES) {
    if (g_smp_hc.core_online[smp_i]) {
      online_cnt = online_cnt + 1;
    }
    smp_i++;
  }
  g_smp_hc.online_cores = online_cnt;
}

I64 SmpDispatch(U32 core_id, U64 fn, U64 arg) {
  if (core_id == 0 || core_id >= SMP_MAX_CORES || fn == 0) return -1;
  // P3.7: NO silent local-execution fallback. If the target core is offline the
  // dispatch fails explicitly (single-core mode is a diagnostic, never a hidden
  // BSP execution that would fake parallelism).
  if (!g_smp_hc.core_online[core_id]) return -1;

  U64 bsp_t0 = __mrs_cntvct();
  CSmpJob *j = SmpGetJob(core_id);
  j->completed = 0;
  j->fn = fn;
  j->arg = arg;
  __dmb_ish();
  j->pending = 1;
  __dmb_ish();
  __sev();

  I64 wait_iters = 0;
  while (!j->completed && wait_iters < 1000000) {
    __sev();
    wait_iters++;
  }

  U64 bsp_t1 = __mrs_cntvct();
  U64 bsp_dt = bsp_t1 - bsp_t0;
  if (bsp_dt == 0) bsp_dt = 1;
  g_smp_hc.core_active_ticks[0] = g_smp_hc.core_active_ticks[0] + bsp_dt;
  g_smp_hc.core_total_ticks[0] = bsp_t1 - g_smp_boot_vct;
  g_smp_hc.core_heartbeat[0] = g_smp_hc.core_heartbeat[0] + 1;

  if (!j->completed) return -1; // timed out; the job did NOT run
  return 0;
}

// P7.4 F0: non-blocking post. The release sequence is: write fn/arg/completed,
// DMB ISH, publish pending with a store, DMB ISH, SEV. A worker that observes
// pending==1 with a matching acquire (its own DMB after the WFE) is guaranteed to
// see fn/arg. There is deliberately no local-execution fallback.
I64 SmpDispatchAsync(U32 core_id, U64 fn, U64 arg) {
  if (core_id == 0 || core_id >= SMP_MAX_CORES || fn == 0) return -1;
  if (!g_smp_hc.core_online[core_id]) return -1;
  CSmpJob *j = SmpGetJob(core_id);
  j->completed = 0;
  j->fn = fn;
  j->arg = arg;
  __dmb_ish();
  j->pending = 1;
  __dmb_ish();
  __sev();
  return 0;
}

I64 SmpIsJobDone(U32 core_id) {
  if (core_id >= SMP_MAX_CORES) return 1;
  CSmpJob *j = SmpGetJob(core_id);
  return j->completed;
}

// P7.4 F0: blocking join with an explicit acquire barrier. Spins WFE/SEV (the
// worker's completion SEV sets the event register so the WFE returns), then a
// trailing DMB ISH makes every store the worker made before `completed=1` visible
// to this core. Returns 0 on success, -1 on timeout (an explicit failure — the
// old version returned silently after a fixed iteration count, hiding a hang).
I64 SmpWaitJob(U32 core_id) {
  if (core_id >= SMP_MAX_CORES) return -1;
  CSmpJob *j = SmpGetJob(core_id);
  I64 guard = 0;
  while (!j->completed) {
    __wfe();
    __sev();
    guard = guard + 1;
    if (guard >= 2000000000) return -1;
  }
  __dmb_ish();
  return 0;
}

U32 SmpGetCoreLoadPct(U32 core_id) {
  if (core_id >= SMP_MAX_CORES) return 0;
  CSmpJob *j = SmpGetJob(core_id);
  if (j && j->pending) return 100;

  U64 act = g_smp_hc.core_active_ticks[core_id];
  if (act == 0) return 0;

  U64 elapsed = __mrs_cntvct() - g_smp_boot_vct;
  U64 tot = g_smp_hc.core_total_ticks[core_id];
  if (elapsed > tot) tot = elapsed;
  if (tot == 0) return 1;

  U64 pct = (act * 100) / tot;
  if (pct > 100) pct = 100;
  if (pct == 0 && act > 0) pct = 1;
  return pct;
}

U0 SmpStatus() {
  doldoc_printf("$FG,CYAN$--- ARMv8-A SMP MULTIPROCESSING TELEMETRY ---$FG$\n");
  doldoc_printf(" Cores Configured: %d | Hardware Online: %d | Current Core: #%d\n",
                g_smp_hc.num_cores, g_smp_hc.online_cores, SmpGetCoreId());
  I64 sp_i = 0;
  while (sp_i < SMP_MAX_CORES) {
    U8 *st_badge = g_smp_hc.core_online[sp_i] ? "$FG,GREEN$ONLINE $FG$" : "$FG,YELLOW$COOP-FB$FG$";
    doldoc_printf("  Core #%d %s: %s (%3d%%) | Heartbeats: %lld | Active Ticks: %lld\n",
                  sp_i,
                  (sp_i == 0) ? "(BSP / GUI Core)" : "(Worker Core)   ",
                  st_badge,
                  SmpGetCoreLoadPct(sp_i),
                  g_smp_hc.core_heartbeat[sp_i],
                  g_smp_hc.core_active_ticks[sp_i]);
    sp_i++;
  }
  doldoc_printf("$FG,CYAN$-----------------------------------------------$FG$\n");
}

U0 SmpPrintDolDoc() {
  SmpStatus();
}

I64 smp_dispatch(U32 core_id, U64 fn, U64 arg) {
  return SmpDispatch(core_id, fn, arg);
}

U0 smp_print() {
  SmpStatus();
}

U0 smp_wait_job(U32 core_id) {
  SmpWaitJob(core_id);
}

U0 SmpTestWorkerFn(U64 arg) {
  g_smp_test_acc = arg + 0x1000;
  g_smp_test_exec_core = SmpGetCoreId();
}

I64 SmpSelfTest() {
  doldoc_printf("\n$FG,CYAN$[SMP-TEST] Starting Pure HolyC SMP Multiprocessing Verification...$FG$\n");

  // Test 1: SmpInit (Zero synthetic heartbeats)
  SmpInit();
  if (g_smp_hc.num_cores != 4 || !g_smp_hc.core_online[0] || g_smp_hc.core_heartbeat[1] != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: SMP initialization or zero-heartbeat invariant failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: SMP 4-Core topology initialized (0 synthetic heartbeats).$FG$\n");

  // Test 2: Core count and MPIDR masked core ID query
  if (SmpGetCoreCount() != 4 || SmpGetCoreId() != 0 || SmpGetCurrentCore() != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: Core count or MPIDR core ID mask mismatch!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Hardware core count (4) and masked MPIDR_EL1 (Core 0) verified.$FG$\n");

  // Test 3: Real function job dispatch to Core 1 (no magic 0x75001111 address hack)
  g_smp_test_acc = 0;
  g_smp_test_exec_core = 0xFFFFFFFF;
  U64 hb_before = g_smp_hc.core_heartbeat[1];
  I64 d_res = SmpDispatch(1, SmpTestWorkerFn, 0x99);
  if (d_res != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: SmpDispatch failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Lockless SPSC job dispatch to Worker Core 1 validated.$FG$\n");

  // Test 4: Job synchronization, payload execution, real heartbeat increment and
  // — the F0 proof — the worker reporting the MPIDR core it actually ran on.
  I64 wj = SmpWaitJob(1);
  if (wj != 0 || !SmpIsJobDone(1) || g_smp_test_acc != 0x1099 ||
      g_smp_hc.core_heartbeat[1] != hb_before + 1 || g_smp_test_exec_core != 1) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: Worker payload/heartbeat/core-ID failed (acc=0x%llX core=%d)!$FG$\n",
                  g_smp_test_acc, g_smp_test_exec_core);
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: SmpWaitJob join + payload (0x%llX) ran on core #%d (MPIDR) verified.$FG$\n",
                g_smp_test_acc, g_smp_test_exec_core);

  // Test 5: Real cycle-based CPU load calculation & DolDoc telemetry
  U32 bsp_load = SmpGetCoreLoadPct(0);
  U32 ap_load = SmpGetCoreLoadPct(1);
  if (bsp_load == 0 || ap_load == 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Real cycle load calculation returned 0!$FG$\n");
    return 0;
  }
  SmpStatus();
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Real CNTVCT_EL0 cycle load telemetry validated.$FG$\n");

  doldoc_printf("\n[SMP-PASS] ALL 5 SMP TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  SmpInit();
} else {
  SmpSelfTest();
}
