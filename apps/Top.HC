// ==============================================================================
// Top.HC - Sovereign Pure HolyC Live System Monitor & Telemetry Dashboard
// Architecture: ARMv8-A Ring 0 (EL1) Single Address Space OS (SASOS)
// Displays: Live SMP Core Heartbeats, Ring-0 Task Table, Heap Telemetry & Uptime
// ==============================================================================

U0 TopMain() {
  doldoc_clear();
  U64 up_us = timer_get_uptime_us();
  U64 up_sec = up_us / 1000000;
  U64 up_ms = (up_us / 1000) % 1000;
  U64 up_hrs = up_sec / 3600;
  U64 up_min = (up_sec / 60) % 60;
  U64 up_s = up_sec % 60;

  U64 raw_cnt = __mrs_cntvct();
  U64 raw_frq = __mrs_cntfrq();
  if (raw_frq == 0) raw_frq = 62500000;
  U64 frq_mhz = raw_frq / 1000000;

  U32 bsp_core = smp_get_current_core() & 3;
  I64 task_cnt = SchedCountTasks();

  doldoc_print("\n$FG,CYAN$==============================================================================$FG$\n");
  doldoc_print("$FG,WHITE$        ✦ NeoOS Sovereign Ring-0 System Monitor & Telemetry (Top.HC) ✦$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================================$FG$\n");

  // 1. Hardware Platform & Uptime Banner
  U8 *plat_name = "QEMU ARM64 Virt (ARMv8-A EL1)";
  if (g_current_platform) {
    plat_name = g_current_platform->name;
  }
  doldoc_printf(" Platform : $FG,YELLOW$%s$FG$ | Executing on Core #%d (Ring 0 SASOS)\n", plat_name, bsp_core);
  doldoc_printf(" Uptime   : $FG,GREEN$%02lld:%02lld:%02lld.%03lld$FG$ (%lld us) | Timer: %lld MHz | CNTVCT: $FG,CYAN$0x%012llX$FG$\n",
                up_hrs, up_min, up_s, up_ms, up_us, frq_mhz, raw_cnt);
  doldoc_printf(" Scheduler: $FG,YELLOW$%lld Active Tasks$FG$ | Context Switches: $FG,GREEN$%lld$FG$ | System Ticks: %lld\n",
                task_cnt, g_sched_switch_count, TimerGetTicks());
  doldoc_print("$FG,CYAN$------------------------------------------------------------------------------$FG$\n");

  // 2. Live SMP Multi-Core Heartbeats & Load Telemetry
  I64 n_cores = g_smp_hc.num_cores;
  if (n_cores <= 0 || n_cores > 4) n_cores = 4;
  doldoc_printf(" $FG,WHITE$[1] SMP MULTI-CORE TELEMETRY (%lld / %lld Cores Online)$FG$\n",
                g_smp_hc.online_cores, n_cores);

  I64 tp_c = 0;
  while (tp_c < n_cores) {
    I64 is_on = g_smp_hc.core_online[tp_c];
    U64 hb = g_smp_hc.core_heartbeat[tp_c];
    I64 load_pct = SmpGetCoreLoadPct(tp_c);
    if (load_pct < 0) load_pct = 0;
    if (load_pct > 100) load_pct = 100;

    U8 *role_str = "Worker";
    if (tp_c == 0) role_str = "BSP   ";

    if (is_on) {
      doldoc_printf("   Core #%lld (%s): $FG,GREEN$ONLINE $FG$ | Heartbeat: $FG,YELLOW$%6lld$FG$ | Load: $FG,CYAN$%3lld%%$FG$  $PB,VAL=%lld,MAX=100$\n",
                    tp_c, role_str, hb, load_pct, load_pct);
    } else {
      doldoc_printf("   Core #%lld (%s): $FG,RED$OFFLINE$FG$ | Heartbeat: %6lld | Load:   0%%  $PB,VAL=0,MAX=100$\n",
                    tp_c, role_str, hb);
    }
    tp_c++;
  }
  doldoc_print("$FG,CYAN$------------------------------------------------------------------------------$FG$\n");

  // 3. Active Ring-0 Task Table
  doldoc_printf(" $FG,WHITE$[2] RING-0 COOPERATIVE / PREEMPTIVE TASK TABLE (%lld Tasks)$FG$\n", task_cnt);
  doldoc_print("   PID  NAME              STATE      PRIORITY    QUANTUM  AFFINITY  STACK\n");

  if (g_sched_head) {
    CTask *tp_curr = g_sched_head;
    I64 tp_guard = 0;
    while (tp_curr && tp_guard < 32) {
      U8 *st_str = "READY   ";
      if (tp_curr->state == 1) st_str = "RUNNING ";
      else if (tp_curr->state == 2) st_str = "SLEEPING";
      else if (tp_curr->state == 3) st_str = "DEAD    ";
      else if (tp_curr->state == 4) st_str = "BLOCKED ";

      U8 *pr_str = "NORMAL  ";
      if (tp_curr->priority == 0) pr_str = "IDLE    ";
      else if (tp_curr->priority == 1) pr_str = "BG      ";
      else if (tp_curr->priority == 2) pr_str = "INTERACT";
      else if (tp_curr->priority == 3) pr_str = "REALTIME";

      I64 stk_kb = tp_curr->stack_size / 1024;
      if (tp_curr->state == 1) {
        doldoc_printf("   $FG,GREEN$%-4lld %-17s %-10s %-11s$FG$ ",
                      tp_curr->id, tp_curr->name, st_str, pr_str);
        doldoc_printf("$FG,GREEN$%2lld/%-4lld  0x%02X      %4lld KB$FG$\n",
                      tp_curr->quantum_remaining, tp_curr->quantum_ticks,
                      tp_curr->affinity_mask, stk_kb);
      } else {
        doldoc_printf("   %-4lld %-17s $FG,YELLOW$%-10s$FG$ %-11s ",
                      tp_curr->id, tp_curr->name, st_str, pr_str);
        doldoc_printf("%2lld/%-4lld  0x%02X      %4lld KB\n",
                      tp_curr->quantum_remaining, tp_curr->quantum_ticks,
                      tp_curr->affinity_mask, stk_kb);
      }

      tp_guard++;
      tp_curr = tp_curr->next;
      if (tp_curr == g_sched_head) break;
    }
  }
  doldoc_print("$FG,CYAN$------------------------------------------------------------------------------$FG$\n");

  // 4. Sovereign Kernel Heap Memory Telemetry
  U64 h_tot = g_heap_stats.total_memory;
  U64 h_used = g_heap_stats.used_memory;
  U64 h_free = g_heap_stats.free_memory;
  U64 h_peak = g_heap_stats.peak_used;
  if (h_peak < h_used) h_peak = h_used;
  I64 h_pct = 1;
  if (h_tot > 0) {
    h_pct = (h_used * 100) / h_tot;
    if (h_pct < 1 && h_used > 0) h_pct = 1;
  }

  doldoc_print(" $FG,WHITE$[3] KERNEL HEAP MEMORY TELEMETRY (16-Byte Aligned Canary Freelist)$FG$\n");
  doldoc_printf("   Range    : $FG,CYAN$0x%016llX$FG$ .. $FG,CYAN$0x%016llX$FG$ (%lld KB Total)\n",
                g_heap_start, g_heap_end, h_tot / 1024);
  doldoc_printf("   Allocated: $FG,YELLOW$%lld B$FG$ (%lld KB) | Free: $FG,GREEN$%lld KB$FG$ | Peak Used: $FG,CYAN$%lld B$FG$\n",
                h_used, h_used / 1024, h_free / 1024, h_peak);
  doldoc_printf("   Counters : %lld Allocs | %lld Frees | Utilization: $PB,VAL=%lld,MAX=100$ (%lld%%)\n",
                g_heap_stats.allocation_count, g_heap_stats.free_count, h_pct, h_pct);
  doldoc_print("$FG,CYAN$------------------------------------------------------------------------------$FG$\n");
  doldoc_print(" Actions: $BT,\"Refresh Top\",LM=\"run Top.HC\"$  $BT,\"SMP Stress\",LM=\"smp\"$  $BT,\"Heap Dump\",LM=\"mem\"$  $BT,\"CPU Bench\",LM=\"run BenchCpu.HC\"$  $BT,\"Filer\",LM=\"filer\"$\n");
  doldoc_print("$FG,CYAN$==============================================================================$FG$\n\n");
}

U0 top_print_doldoc() {
  TopMain();
}

I64 g_kernel_booting;
if (!g_kernel_booting) {
  TopMain();
}
