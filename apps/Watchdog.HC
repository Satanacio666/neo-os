// ==============================================================================
// apps/Watchdog.HC - CAMADA 1: vigia contínuo no core ocioso (sistema imunológico)
//
// Prova de viabilidade: um watcher em background (CPU #1, affinity 0x02) que
// executa a cada 250 ms:
//   1. SymScanUnresolved()      (P0.3) - varre os 1024 baldes da tabela soberana
//   2. Contadores de orçamento  (P0.2) - compara uso vs teto das tabelas críticas
//   3. Canário do heap (KHeap)  (P0.2) - KHeapIsValidPtr no head
//
// Critério de sucesso (falsificável):
//   - Custo de CPU < 1% (profiler/Telemetry)
//   - RENDER golden hash 0xD28836F INTACTO (1 vs 4 cores) - sem race conditions
//
// O arquivo é carregado DEPOIS de todos os estágios (fim do KernelInit), então
// pode referenciar qualquer símbolo sem forward-ref (evita o E16).
// ==============================================================================

I64 g_watchdog_runs = 0;
I64 g_watchdog_faults = 0;

// Espelho das constantes de teto (as #define de Compiler.HC/KHeap.HC são
// por-unidade e NÃO persistem entre arquivos — mesmo padrão do [BUDGET]).
#define HC_MAX_FUNCS     2048
#define HC_MAX_GLOBALS   768
#define HC_MAP_MAX       2048
#define HC_FNF_MAX       4096
#define HEAP_CANARY      0xDEADBEEFCAFECAFE
#define PRIO_BACKGROUND  1

U0 WatchdogTick(U64 arg) {
  while (1) {
    // 1. Scan soberano de símbolos não-resolvidos (P0.3). Variante SILENCIOSA
    //    (SymScanUnresolvedQuiet) — o vigia imprime só em FALHA, para não
    //    inundar o serial a cada 250 ms e corromper o parsing do gate.
    I64 wd_u;
    wd_u = SymScanUnresolvedQuiet();
    if (wd_u != 0) {
      g_watchdog_faults++;
      doldoc_printf("$FG,RED$[WATCHDOG] SYMBOL FAULT: %lld unresolved na tabela soberana$FG$\n", wd_u);
    }

    // 2. Tabelas de orçamento (P0.2): grita se QUALQUER teto crítico estourar.
    //    PULA durante o selftest: o SelfTestOverflowInjection leva os contadores
    //    ao teto DE PROPÓSITO (prova ativa das guardas) — seria falso positivo.
    if (g_selftest_total == 0 &&
        (g_hc_func_count >= HC_MAX_FUNCS ||
         g_hc_global_count >= HC_MAX_GLOBALS ||
         g_hc_map_count >= HC_MAP_MAX ||
         g_hc_fnf_count >= HC_FNF_MAX)) {
      g_watchdog_faults++;
      doldoc_printf("$FG,RED$[WATCHDOG] BUDGET FAULT: funcs=%lld/%lld globals=%lld/%lld$FG$\n",
                    g_hc_func_count, HC_MAX_FUNCS, g_hc_global_count, HC_MAX_GLOBALS);
      doldoc_printf("$FG,RED$[WATCHDOG] BUDGET FAULT: map=%lld/%lld fnf=%lld/%lld$FG$\n",
                    g_hc_map_count, HC_MAP_MAX, g_hc_fnf_count, HC_FNF_MAX);
    }

    // 3. Canário do heap: o head deve ter o canário intacto.
    if (g_heap_head != 0 && g_heap_head->canary_head != HEAP_CANARY) {
      g_watchdog_faults++;
      doldoc_printf("$FG,RED$[WATCHDOG] HEAP CANARY VIOLATION (head=0x%016llX canary=0x%016llX)$FG$\n",
                    (U64)g_heap_head, g_heap_head->canary_head);
    }

    g_watchdog_runs++;
    TimerSleepMs(250);
  }
}

// Ponto de entrada: cria a task do vigia com afinidade no core 1 (0x02).
U0 WatchdogStart() {
  if (g_watchdog_runs > 0) return; // já rodando
  U64 t;
  t = TaskCreate("Watchdog", (U64)&WatchdogTick, 0, 8192);
  if (t == 0) {
    doldoc_printf("$FG,RED$[WATCHDOG] FAIL: TaskCreate$FG$\n");
    return;
  }
  // Força afinidade core 1 (bit 1 = 0x02) e prioridade BACKGROUND (1):
  // abaixo do INTERACTIVE (2) das tasks de teste — o vigia não rouba o scheduler
  // dos testes (o SCHED falhava com o vigia na mesma prioridade do probe).
  CTask *wd = (CTask *)t;
  wd->affinity_mask = 0x02;
  wd->priority = PRIO_BACKGROUND;
  doldoc_printf("[WATCHDOG] vigia ativo no core 1 (affinity_mask=0x%02X prio=%lld)\n",
                wd->affinity_mask, wd->priority);
}
