// ==============================================================================
// apps/Watchdog.HC - CAMADA 1 + CAMADA 2: vigia contínuo no core ocioso
//
// CAMADA 1 (ec5d945/b13399d): watcher em background (CPU #1, affinity 0x02,
// PRIO_BACKGROUND) a cada 250 ms:
//   1. SymScanUnresolvedQuiet()   - varre os 1024 baldes simbolicos
//   2. Contadores de orcamento    - uso vs teto das tabelas criticas
//   3. Canario do heap (KHeap)    - g_heap_head->canary_head
// Em cada falha: g_watchdog_faults++  + print no serial.
//
// CAMADA 2 (ESTA): o vigia REGISTRA cada anomalia num livro-razao de saude
// consultavel em runtime — o HealthLog circular de 1 MB. Decisao de desenho:
//   * Por que NAO o omnitape do DolDoc? O omnitape registra CDocNodes
//     (comandos de documento de 64 B + payload de texto) e RETORNA -1 quando
//     o buffer 1 MB enche — um auditorio congelado. Um livro-razao de saude
//     precisa NUNCA parar de gravar (diagnostico proativo: "as ultimas N
//     falhas"), entao o HealthLog e circular (wrap-around com overwrite do
//     mais antigo). O omnitape tambem e acoplado ao layout do documento vivo
//     (relayout do DolDoc), irrelevante para eventos de kernel.
//   * Estrutura: HEALTHLOG_SIZE (1 MB) bytes, entradas de 64 B (header fixo
//     + payload compacto), fixas — wrap-around por indice, O(1) por evento.
//   * Alocacao: KMalloc (KHeap nativo) no WatchdogStart(). Nao usamos
//     kmalloc porque o gate CENSUS (census-c-runtime.sh) conta chamadas
//     'kmalloc(' nas apps e NAO pode aumentar (baseline 55).
//   * Consulta: comando de shell 'health' (registrado de forma IDEMPOTENTE
//     no WatchdogTick — Shell.HC carrega ANTES do Watchdog.HC, logo um
//     ShellCmd_health em Shell.HC seria uma forward reference E16; e o
//     ShellInit() roda DEPOIS do WatchdogStart e zera a tabela, entao o
//     registro e refeito a cada tick enquanto faltar; manter Shell.HC e o
//     SHELL self-test intocados).
//   * Leitura: globais auto-publicadas (mesmo mecanismo da Camada 1, que
//     le g_watchdog_cost_cycles via sonda REPL) — sem symbols_register
//     (tambem contado pelo CENSUS).
//   * Escrita: split writer no proprio task do vigia — o reader de um
//     comando 'health' so le entradas comecando na cabeca, entao nunca ve
//     entrada parcial.
//
// Custo: o registro e O(1), SOMENTE em falha; em operacao normal a passada
// do vigia ganha uma comparacao/escrita por tick (<0,1% do intervalo).
// ==============================================================================

I64 g_watchdog_runs = 0;
I64 g_watchdog_faults = 0;
// Metricas de custo (Camada 1, criterio <1%): ciclos gastos nas PASSADAS do
// vigia (scan + budget + canario) vs ciclos totais decorridos, acumulados.
// Lidas via sonda no REPL (doldoc_printf <=7 args). O custo-alvo e <1%.
U64 g_watchdog_cost_cycles = 0;
U64 g_watchdog_wall_cycles = 0;

// ---- CAMADA 2: livro-razao de saude (HealthLog) ----
// NOTA: literais puros, NAO produtos de macros — o Compiler.HC documenta que
// "a PRODUCT of two macros is the one form it does not fold reliably"; medido
// na Camada 2: `(1 << 20) / 64` dobrou para 0 no modulo (o REPL avalia certo,
// o compilador de modulo nao). Com HEALTHLOG_MAX=0 o `% 0` vira udiv-por-zero
// (AArch64 retorna 0, sem trap), a cabeca cresce sem wrap e estoura o buffer.
#define HEALTHLOG_SIZE     1048576   // 1 MB circular (mesmo do omnitape)
#define HEALTHLOG_ENTRY    64        // bytes por entrada (fixa)
#define HEALTHLOG_MAX      16384     // HEALTHLOG_SIZE / HEALTHLOG_ENTRY
#define HEALTHLOG_MAGIC    0x4845414C54484C47 // "HEALTHLG"
U8  *g_healthlog_buf = 0;
I64  g_healthlog_head = 0;  // indice onde a PROXIMA entrada sera gravada
I64  g_healthlog_count = 0; // entradas vivas (0..HEALTHLOG_MAX)

// Tipos de evento de saude (espelham os 3 pontos de falha do vigia).
#define HEALTH_SYM    1   // simbolo(s) unresolved na tabela soberana
#define HEALTH_BUDGET 2   // teto de tabela estourado
#define HEALTH_CANARY 3   // canario do heap corrompido
#define HEALTH_HDRINV 4   // header invalido encontrado no dump (corrompido)

class CHlEntry {
    U64 magic;    // HEALTHLOG_MAGIC (permite reconhecer slot ocupado)
    U64 wd_tick;  // ciclo do __mrs_cntvct do MOMENTO do registro
    I64 ms;       // timer_get_uptime_ms() no momento do registro
    I64 type;     // HEALTH_SYM / HEALTH_BUDGET / HEALTH_CANARY
    I64 fault_no; // g_watchdog_faults (ticket global) da falha
    I64 payload;  // dado relevante (unresolved count / teto estourado / canario visto)
    I64 u2;       // reservado (0)
    I64 u3;       // reservado (0)
};

U0 HealthLogInit() {
    if (g_healthlog_buf) return; // ja inicializado
    g_healthlog_buf = KMalloc(HEALTHLOG_SIZE);
    if (!g_healthlog_buf) {
        doldoc_printf("$FG,RED$[HEALTHLOG] FAIL: KMalloc(%lld) indisponivel — HealthLog inativo$FG$\n",
                      (I64)HEALTHLOG_SIZE);
        return;
    }
    g_healthlog_head = 0;
    g_healthlog_count = 0;
    doldoc_printf("[HEALTHLOG] livro-razao de saude ativo: %lld slots x %lld B circulares\n",
                  (I64)HEALTHLOG_MAX, (I64)HEALTHLOG_ENTRY);
}

// Registra um evento de saude. O(1) por evento, wrap-around circular.
U0 HealthLogRecord(I64 h_type, I64 h_payload) {
    if (!g_healthlog_buf) return;
    if (g_healthlog_head < 0 || g_healthlog_head >= HEALTHLOG_MAX) g_healthlog_head = 0;
    I64 wet = g_healthlog_head; // slot; o writer e unico (task do vigia)
    CHlEntry *e = (CHlEntry *)(g_healthlog_buf + wet * HEALTHLOG_ENTRY);
    e->magic = HEALTHLOG_MAGIC;
    e->wd_tick = __mrs_cntvct();
    e->ms = (I64)timer_get_uptime_ms();
    e->type = h_type;
    e->fault_no = g_watchdog_faults;
    e->payload = h_payload;
    e->u2 = 0;
    e->u3 = 0;
    __dmb_ish(); // publica a entrada antes de mover a cabeca
    g_healthlog_head = (wet + 1) % HEALTHLOG_MAX;
    if (g_healthlog_count < HEALTHLOG_MAX) g_healthlog_count++;
}

// Imprime as ultimas N entradas (padrao: 10). Consulta em runtime.
U0 HealthLogDump(I64 n_want) {
    if (!g_healthlog_buf) {
        doldoc_printf("$FG,YELLOW$[HEALTH] HealthLog inativo (KMalloc falhou no boot)$FG$\n");
        return;
    }
    if (n_want < 1) n_want = 1;
    if (n_want > HEALTHLOG_MAX) n_want = HEALTHLOG_MAX;
    I64 n_viv = g_healthlog_count;
    if (n_viv > n_want) n_viv = n_want;
    doldoc_printf("$FG,CYAN$[HEALTH] livro-razao: %lld entradas vivas, %lld slots, dump das ultimas %lld$FG$\n",
                  g_healthlog_count, (I64)HEALTHLOG_MAX, n_viv);
    if (n_viv == 0) {
        doldoc_print("$FG,GREEN$[HEALTH] NENHUMA anomalia registrada (kernel saudavel)$FG$\n");
        return;
    }
    I64 slot = (g_healthlog_head - n_viv + HEALTHLOG_MAX) % HEALTHLOG_MAX;
    I64 hi = 0;
    while (hi < n_viv) {
        CHlEntry *e = (CHlEntry *)(g_healthlog_buf + slot * HEALTHLOG_ENTRY);
        if (e->magic != HEALTHLOG_MAGIC) {
            // Slot sem magic: ou entrada corrompida ou cauda nao inicializada
            // (retorno do wrap). Sinaliza, nao inventa dado.
            doldoc_printf("[HEALTH] slot %lld: header invalido (magic=0x%016llX)\n", slot, e->magic);
        } else {
            U8 *hname = "?";
            if (e->type == HEALTH_SYM) hname = "SYM";
            else if (e->type == HEALTH_BUDGET) hname = "BUDGET";
            else if (e->type == HEALTH_CANARY) hname = "CANARY";
            doldoc_printf("[HEALTH] #%lld %s @t=%lldms tick=%lld fault=%lld payload=%lld\n",
                          hi + 1, hname, e->ms, e->wd_tick, e->fault_no, e->payload);
        }
        slot = (slot + 1) % HEALTHLOG_MAX;
        hi++;
    }
}

// Comando de shell: 'health'  |  'health <N>'  (N = quantas entradas; padrao 10)
U0 ShellCmd_health(U8 *a, U8 *r) {
    I64 h_n = 10;
    while (*a == ' ' || *a == '\t') a++;
    if (*a) {
        I64 h_acc = 0;
        while (*a >= '0' && *a <= '9') { h_acc = h_acc * 10 + (*a - '0'); a++; }
        if (h_acc > 0) h_n = h_acc;
    }
    HealthLogDump(h_n);
}

U0 WatchdogTick(U64 arg) {
    while (1) {
        U64 wd_t0 = __mrs_cntvct();
        // Registra o comando 'health' de forma IDEMPOTENTE: o ShellInit()
        // (rodado em DolDocShellEventLoop, DEPOIS do WatchdogStart) zera
        // g_shell_cmd_count e reconstroi a tabela — registrar uma vez so
        // seria apagado. Re-registrar sempre que faltar e auto-curativo:
        // depois do ShellInit, o proximo tick (250 ms) o restaura e ele
        // permanece (shell_register_cmd e O(1) e atualiza in-place).
        if (ShellFindCmd("health") < 0) {
            shell_register_cmd("health", ShellCmd_health, "health ledger dump");
        }
        // 1. Scan soberano de simbolos nao-resolvidos (P0.3). Variante
        //    SILENCIOSA (SymScanUnresolvedQuiet) — o vigia imprime so em FALHA,
        //    para nao inundar o serial a cada 250 ms (gate).
        I64 wd_u;
        wd_u = SymScanUnresolvedQuiet();
        if (wd_u != 0) {
            g_watchdog_faults++;
            doldoc_printf("$FG,RED$[WATCHDOG] SYMBOL FAULT: %lld unresolved na tabela soberana$FG$\n", wd_u);
            HealthLogRecord(HEALTH_SYM, wd_u);
        }

        // 2. Tabelas de orcamento (P0.2): grita se QUALQUER teto critico estourar.
        //    PULA durante o selftest: o SelfTestOverflowInjection leva os contadores
        //    ao teto DE PROPOSITO — seria falso positivo.
        if (g_selftest_total == 0 &&
            (g_hc_func_count >= HC_MAX_FUNCS ||
             g_hc_global_count >= HC_MAX_GLOBALS ||
             g_hc_map_count >= HC_MAP_MAX ||
             g_hc_fnf_count >= HC_FNF_MAX)) {
            g_watchdog_faults++;
            I64 wd_budget_id = 0;
            if (g_hc_func_count >= HC_MAX_FUNCS) wd_budget_id = 1;
            else if (g_hc_global_count >= HC_MAX_GLOBALS) wd_budget_id = 2;
            else if (g_hc_map_count >= HC_MAP_MAX) wd_budget_id = 3;
            else if (g_hc_fnf_count >= HC_FNF_MAX) wd_budget_id = 4;
            HealthLogRecord(HEALTH_BUDGET, wd_budget_id);
            doldoc_printf("$FG,RED$[WATCHDOG] BUDGET FAULT: funcs=%lld/%lld globals=%lld/%lld$FG$\n",
                          g_hc_func_count, HC_MAX_FUNCS, g_hc_global_count, HC_MAX_GLOBALS);
            doldoc_printf("$FG,RED$[WATCHDOG] BUDGET FAULT: map=%lld/%lld fnf=%lld/%lld$FG$\n",
                          g_hc_map_count, HC_MAP_MAX, g_hc_fnf_count, HC_FNF_MAX);
        }

        // 3. Canario do heap: o head deve ter o canario intacto.
        if (g_heap_head != 0 && g_heap_head->canary_head != HEAP_CANARY) {
            g_watchdog_faults++;
            HealthLogRecord(HEALTH_CANARY, (I64)g_heap_head->canary_head);
            doldoc_printf("$FG,RED$[WATCHDOG] HEAP CANARY VIOLATION (head=0x%016llX canary=0x%016llX)$FG$\n",
                          (U64)g_heap_head, g_heap_head->canary_head);
        }

        // Custo da passada (ciclos) e do intervalo total (250 ms), acumulados.
        g_watchdog_cost_cycles += __mrs_cntvct() - wd_t0;
        g_watchdog_runs++;
        g_watchdog_wall_cycles += TimerQueryHwFreq() / 4; // 250 ms em ciclos
        TimerSleepMs(250);
    }
}

// Ponto de entrada: cria a task do vigia com afinidade no core 1 (0x02),
// inicializa o HealthLog e registra o comando de consulta 'health'.
U0 WatchdogStart() {
    if (g_watchdog_runs > 0) return; // ja rodando
    HealthLogInit();
    // NOTA: o comando 'health' e registrado no PRIMEIRO tick (WatchdogTick),
    // NAO aqui — o ShellInit() roda DEPOIS (DolDocShellEventLoop) e zera a
    // tabela de comandos; registrar aqui seria apagado.
    U64 t;
    t = TaskCreate("Watchdog", (U64)&WatchdogTick, 0, 8192);
    if (t == 0) {
        doldoc_printf("$FG,RED$[WATCHDOG] FAIL: TaskCreate$FG$\n");
        return;
    }
    // Forca afinidade core 1 (bit 1 = 0x02) e prioridade BACKGROUND (1):
    // abaixo do INTERACTIVE (2) das tasks de teste — o vigia nao rouba o
    // scheduler dos testes (o SCHED falhava com o vigia na mesma prioridade).
    CTask *wd = (CTask *)t;
    wd->affinity_mask = 0x02;
    wd->priority = PRIO_BACKGROUND;
    doldoc_printf("[WATCHDOG] vigia ativo no core 1 (affinity_mask=0x%02X prio=%lld)\n",
                  wd->affinity_mask, wd->priority);
}