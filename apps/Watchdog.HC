// ==============================================================================
// apps/Watchdog.HC - CAMADA 1 + 2 + 3: vigia contínuo no core ocioso, que
// também REPARA com segurança (auto-cura).
//
// CAMADA 1 (ec5d945/b13399d): watcher em background (CPU #1, affinity 0x02,
// PRIO_BACKGROUND) a cada 250 ms:
//   1. SymScanUnresolvedQuiet()   - varre os 1024 baldes simbolicos
//   2. Contadores de orcamento    - uso vs teto das tabelas criticas
//   3. Canario do heap (KHeap)    - g_heap_head->canary_head
// Em cada falha: g_watchdog_faults++  + print no serial.
//
// CAMADA 2 (e4e6e2c): o vigia REGISTRA cada anomalia num livro-razao de saude
// consultavel em runtime — o HealthLog circular de 1 MB (ver git log e backup
// apps/Watchdog.HC no commit e4e6e2c para o racional completo do HealthLog).
//
// CAMADA 3 (ESTA): o vigia REPARA. Decisoes de desenho documentadas:
//
//   * SYM (simbolo unresolved): se o simbolo pertence ao NAMESPACE DE TESTE
//     (`_tp_` = "test payload" — prefixo que a Camada 2 ja usou para injetar
//     `_tp_frobnicate_missing`), o vigia RE-REGISTRA o simbolo in-place para
//     SymNoop (noop pura, registrada por este proprio modulo) — o mesmo
//     mecanismo que a Camada 2 provou manualmente no REPL:
//         SymRegister("_tp_healmiss_xyz", <doldoc_print addr do seed>, 1) -> 1
//     (medido NESTA sessao: o flood [WATCHDOG] SYMBOL FAULT de ~4/s cessou no
//     tick seguinte apos o re-registro — log cru no artefato fase23).
//     POR QUE isso e reparo REAL e nao mascaramento:
//       - o CSymbol EXISTENTE e re-registrado (address passa de
//         &SymUnresolvedTrap para &SymNoop) — o MESMO caminho SymRegister
//         in-place que o compilador usa para resolver um forward reference
//         (Compiler.HC HcPublishFunc/HcAddFunc);
//       - chamar `_tp_*()` passa a retornar 0 em vez de cair no trap
//         (SymUnresolvedTrap tambem retorna 0, MAS incrementa g_sym_trap_hits
//         e grita no serial — o trap e o sintoma de contrato quebrado; SymNoop
//         e um no-op documentado);
//       - a tabela soberana fica SEM unresolved (SymScanUnresolvedQuiet()
//         retorna 0), logo o HealthLog, o boot self-check e o gate veem o
//         sistema limpo.
//       - RESTRICAO de seguranca: so nomes com prefixo `_tp_` sao tocados.
//         Unresolved FORA do namespace de teste NAO e reparado: nao ha destino
//         seguro conhecido (e possivelmente bug real de forward reference —
//         mascarar seria covardia). O vigia registra HEALTH_SYM action=NOREP
//         e o serial mostra "(NAO reparado)".
//     Efeito colateral aceito: re-executar o mesmo texto no REPL faz
//     SymSicCell -> SymRegister(name, &SymUnresolvedTrap) de novo (o teste
//     volta a ficar unresolved e o vigia repara de novo) — comportamento
//     correto para payload de teste (reparo repetivel, audivivel no log).
//
//   * CANARY (g_heap_head->canary_head != HEAP_CANARY): restaurar o campo
//     canario para HEAP_CANARY e SEGURO somente quando a PREMISSA abaixo vale;
//     o vigia VALIDA a premissa antes de tocar em qualquer coisa:
//       PREMISSA (ajustada apos medicao): o head pode estar livre OU alocado
//       (is_free ∈ {0,1} — o head vira alocado quando o KMalloc faz split).
//       O vigia valida o que CONSEGUE conferir: size plausivel (multiplo de
//       16, >0), is_free booleano, next (se houver) dentro do pool com canario
//       intacto. Se esses campos estao plausiveis, so o CAMPO canario foi
//       corrompido — restaurar o detector nao esconde estrago estrutural.
//     Se a premissa falha, o vigia registra HEALTH_CANARY action=NOREP e NAO
//     toca em nada — a corrupcao pode ser estrutural e exigir decisao humana
//     (KHeap.HC ja grita "FATAL: Memory corruption" e recusa o KMalloc sem
//     abortar). Nota: canario INTERIOR corrompido tambem fica NOREP
//     (reconstruir a lista e fora do escopo de "reparo seguro"); o HEAPINT
//     (KHeapCheckAll) do selftest continua detectando.
//
//   * BUDGET: NAO reparado (decisao documentada). NAO ha acao segura: subir o
//     teto mascara a pressao real de capacidade, e o SelfTestOverflowInjection
//     POE os contadores no teto DE PROPOSITO. O vigia continua so DETECTANDO e
//     registrando (como na Camada 2) — BUDGET FAULT e alarme de capacidade que
//     pede decisao humana, nao clique de reparo.
//
//   * BACKOFF / DEDUPLICACAO: a observacao da Camada 2 — 1 simbolo unresolved
//     gerou ~4 entradas/s (1 a cada 250 ms; 143 em ~40 s). A Camada 3
//     deduplica por (tipo, chave de estado): a MESMA falha continua NAO gera
//     entrada nova ate mudar de estado (contagem mudou / simbolo reparado /
//     valor do canario mudou) OU ate passarem REPAIR_MIN_MS (5 s) — um
//     "heartbeat de persistencia" com action=PERSIST que nao vira flood.
//     A DETECCAO (g_watchdog_faults++ e counters) continua por tick, como a
//     Camada 2 — so o REGISTRO no HealthLog e deduplicado. Estado do dedup e
//     POR TIPO (array indexado pelo tipo), para um BUDGET nao resetar o timer
//     do SYM (bug de desenho: estado compartilhado entre tipos).
//
// Custo: em regime normal a passada ganha ~2 comparacoes por tick (<0,1% do
// intervalo); o scan/repair extra so roda em falha. Medido na Camada 3 (sonda
// REPL, mesmo metodo da Camada 1): pct < 1% (ver artefato fase23).
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

// Tipos de evento de saude (espelham os pontos de falha do vigia).
#define HEALTH_SYM      1   // simbolo(s) unresolved na tabela soberana
#define HEALTH_BUDGET   2   // teto de tabela estourado
#define HEALTH_CANARY   3   // canario do heap corrompido
#define HEALTH_HDRINV   4   // header invalido encontrado no dump (corrompido)

// ---- CAMADA 3: acoes de reparo por evento ----
// A acao vive nos bits altos do payload: `payload & 0xFFFFFFFF` e o dado
// numerico da Camada 2 (count de unresolved / valor do canario / budget id),
// e `(payload >> 32) & 0xFF` e a ACTION. Gates do tipo `payload != 0`
// (Camada 2) seguem corretos para contagens positivas (action 1<<32 nao zera
// o low). u2 carrega contadores auxiliares (ex.: quantos simbolos foram
// reparados numa passada SYM).
#define HEALTH_ACTION_NONE   0   // so deteccao (ex.: unresolved fora do ns _tp_)
#define HEALTH_ACTION_REPAIR 1   // reparo executado (SymNoop / canario restaurado)
#define HEALTH_ACTION_DEDUP  2   // falha persistente — heartbeat de 5 s
#define HEALTH_ACTION_NOREP  3   // nao reparado: premissa de seguranca violada

// ---- CAMADA 3: deduplicador de registros (backoff por (tipo,chave)) ----
// Mesma falha (mesmo tipo + mesma chave de estado) nao gera entrada nova antes
// de REPAIR_MIN_MS (5 s) ou de MUDAR de estado. Chaves:
//   SYM    -> total de unresolved restantes (mudou = simbolo entrou/saiu)
//   BUDGET -> wd_budget_id (qual tabela estourou)
//   CANARY -> valor do canario visto (mudou = corrupcao diferente/restaurado)
// Com 1 simbolo persistente a taxa cai de ~4/s para <=1/5 s (heartbeat),
// e o log fica com 1 entrada representativa por estado — o objetivo da
// Camada 3. Estado POR TIPO (array indexado pelo tipo): eventos de tipos
// diferentes nao interferem entre si.
#define REPAIR_MIN_MS       5000
I64 g_heal_key[8];   // chave de estado da ultima entrada, por tipo (1..4)
U64 g_heal_ms[8];    // uptime ms da ultima entrada registrada, por tipo

// Valores espelhados de Symbols.HC (NAO cruzar #define entre modulos — a
// Camada 2 espelhou SEM_* no mesmo padrao).
#define WD_SYM_FUNC          1   // Symbols.HC: SYM_FUNC = 1
// Valores espelhados de KHeap.HC: HEAP_CANARY puro (regra: literal, nunca
// produto de macros).
#define HEAL_CANARY          0xDEADBEEFCAFECAFE

class CHlEntry {
    U64 magic;    // HEALTHLOG_MAGIC (permite reconhecer slot ocupado)
    U64 wd_tick;  // ciclo do __mrs_cntvct do MOMENTO do registro
    I64 ms;       // timer_get_uptime_ms() no momento do registro
    I64 type;     // HEALTH_SYM / HEALTH_BUDGET / HEALTH_CANARY
    I64 fault_no; // g_watchdog_faults (ticket global) da falha
    I64 payload;  // low 32 = dado (count/canario/budget id), high = action
    I64 u2;       // contador auxiliar (ex.: simbolos reparados) — 0 se vazio
    I64 u3;       // reservado (0)
};

// Alvo de reparo SYM: no-op puro (retorna 0 — chamada barata e inofensiva).
// Re-registrar um simbolo `_tp_*` unresolved PARA SymNoop remove o unresolved
// da tabela soberana (mesmo efeito que a resolucao real do compilador) sem
// inventar semantica de negocio para o nome de teste.
I64 SymNoop() { return 0; }

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

// Verifica se (h_type, h_key) ja foi registrado ha menos de REPAIR_MIN_MS
// (estado inalterado) — backoff da Camada 3. O timestamp do estado SO e
// renovado quando NAO ha duplicata (primeira vez OU heartbeat expirado): se
// renovassemos a cada chamada, o backoff nunca expiraria e o heartbeat de
// 5 s (action=PERSIST) nunca aconteceria. Retorna 1 se duplicata (o chamador
// NAO registra nem imprime), 0 se pode registrar.
I64 HealthLogBackoff(I64 h_type, I64 h_key) {
    I64 h_idx = h_type & 7;
    if (h_idx == 0) h_idx = 1;
    U64 now_ms = (U64)timer_get_uptime_ms();
    I64 is_dup = 0;
    if (g_heal_key[h_idx] == h_key && g_heal_ms[h_idx] != 0) {
        if (now_ms - g_heal_ms[h_idx] < (U64)REPAIR_MIN_MS) {
            is_dup = 1;              // estado inalterado e backoff ativo
        } else {
            g_heal_ms[h_idx] = now_ms;  // heartbeat: expirou, renova
        }
    } else {
        g_heal_key[h_idx] = h_key;  // estado novo (ou primeiro registro)
        g_heal_ms[h_idx] = now_ms;
    }
    return is_dup;
}

// Registra um evento de saude. O(1) por evento, wrap-around circular.
U0 HealthLogRecord(I64 h_type, I64 h_payload, I64 h_u2) {
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
    e->u2 = h_u2;
    e->u3 = 0;
    __dmb_ish(); // publica a entrada antes de mover a cabeca
    g_healthlog_head = (wet + 1) % HEALTHLOG_MAX;
    if (g_healthlog_count < HEALTHLOG_MAX) g_healthlog_count++;
}

// Imprime as ultimas N entradas (padrao: 10). Consulta em runtime.
// OBS.: doldoc_printf com NO MAXIMO 6 args apos o formato (regra medida:
// mais que 7 args NÃO executa).
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
            U8 *hact = "?";
            if (e->type == HEALTH_SYM) hname = "SYM";
            else if (e->type == HEALTH_BUDGET) hname = "BUDGET";
            else if (e->type == HEALTH_CANARY) hname = "CANARY";
            I64 h_action = (e->payload >> 32) & 0xFF;
            I64 h_data = e->payload & 0xFFFFFFFF;
            if (h_action == HEALTH_ACTION_NONE) hact = "DETECT";
            else if (h_action == HEALTH_ACTION_REPAIR) hact = "REPAIR";
            else if (h_action == HEALTH_ACTION_DEDUP) hact = "PERSIST";
            else if (h_action == HEALTH_ACTION_NOREP) hact = "NOREP";
            doldoc_printf("[HEALTH] #%lld %s/%s @t=%lldms fault=%lld payload=%lld\n",
                          hi + 1, hname, hact, e->ms, e->fault_no, h_data);
            if (e->type == HEALTH_SYM && e->u2 != 0) {
                doldoc_printf("[HEALTH]   reparados nesta passada: %lld\n", e->u2);
            }
        }
        slot = (slot + 1) % HEALTHLOG_MAX;
        hi++;
    }
}

// ---- CAMADA 3: core de reparo SYM ----
// Varre a tabela soberana (mesmos criterios do SymScanUnresolvedQuiet) e, para
// cada unresolved COM PREFIXO `_tp_` (namespace de teste), re-registra
// in-place para SymNoop. Retorna o NUMERO de entradas RESTANTES unresolved
// apos o reparo (o count que o vigia usa como chave de dedup e payload).
// Zero KMalloc / zero symbols_register (CENSUS): so le a lista e re-registra
// CSymbol existente via SymRegister (caminho nativo da resolucao).
I64 SymRepairTestPayload() {
    I64 remaining = 0;
    I64 sr_b = 0;
    while (sr_b < 1024) {
        CSymbol *sr_c = g_sym_buckets[sr_b];
        while (sr_c) {
            if (sr_c->address == (U64)&SymUnresolvedTrap &&
                strcmp(sr_c->name, "SymUnresolvedTrap") != 0) {
                if (strncmp(sr_c->name, "_tp_", 4) == 0) {
                    // Reparo real: re-registra o MESMO CSymbol para SymNoop
                    // (in-place, idempotente, mesmo caminho do compilador).
                    SymRegister(sr_c->name, (U64)&SymNoop, WD_SYM_FUNC);
                } else {
                    remaining++;   // fora do namespace de teste -> NAO tocar
                }
            }
            sr_c = sr_c->next;
        }
        sr_b++;
    }
    return remaining;
}

// ---- CAMADA 3: core de reparo CANARY (head) ----
// Valida a PREMISSA de seguranca e restaura o canario do HEAD para
// HEAP_CANARY. Devolve: 1 = reparado, 0 = NAO reparado (premissa violada ou
// head nulo).
// PREMISSA (medida nesta sessao): o g_heap_head em regime normal pode estar
// livre OU alocado (is_free ∈ {0,1} — o head da lista vira bloco alocado
// quando o KMalloc faz split; o free continua em next). O que o vigia
// CONSEGUE validar sem conhecer a semantica do alocador:
//   1. size e plausivel: > 0 e multiplo de 16 (contrato de alinhamento);
//   2. is_free e booleano (0 ou 1);
//   3. next (se houver) esta DENTRO do pool e com canario intacto (a cadeia
//      de blocos nao foi estruturalmente corrompida).
// Se esses campos estao plausiveis, a corrupcao atingiu SOMENTE o campo
// canario — restaurar o detector nao esconde estrago estrutural (nao ha
// estrago estrutural comprovavel nesses campos). Se a premissa falha, o
// vigia NAO toca em nada (registra NOREP) e deixa o KHeap gritar "FATAL:
// Memory corruption" no proximo KMalloc, sem abortar.
I64 CanaryRepairHead() {
    if (g_heap_head == 0) return 0;
    CHeapBlock *hd = g_heap_head;
    if (hd->size <= 0 || (hd->size & 15) != 0) return 0;   // premissa 1: size
    if (hd->is_free != 0 && hd->is_free != 1) return 0;    // premissa 2: booleano
    CHeapBlock *nx = hd->next;
    if (nx != 0) {
        U64 nx_a = (U64)nx;
        if (nx_a < g_heap_start || nx_a >= g_heap_end) return 0; // premissa 3a
        if (nx->canary_head != HEAL_CANARY) return 0;      // premissa 3b: cadeia
    }
    hd->canary_head = HEAL_CANARY;
    __dmb_ish(); // publica a restauracao
    return 1;
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
        //    para nao inundar o serial a cada 250 ms (gate). A Camada 3
        //    REPARA primeiro os payloads de teste (_tp_*); o count restante
        //    decide se ha falha real (unresolved fora do namespace).
        I64 wd_u = SymScanUnresolvedQuiet();
        I64 wd_rem = wd_u;
        I64 wd_fixed = 0;
        if (wd_u != 0) {
            wd_rem = SymRepairTestPayload();  // restantes APOS reparo
            wd_fixed = wd_u - wd_rem;         // quantos foram reparados agora
        }
        if (wd_rem != 0) {
            // Ainda ha unresolved NAO reparados (fora do ns _tp_ ou premissa
            // invalida). Detecta + dedup; se algum _tp_ foi reparado na mesma
            // passada, registra o evento mesmo sendo "duplicata" (estado
            // relevante mudou — wd_fixed > 0) e carrega wd_fixed em u2.
            // O PRINT no serial tambem respeita o backoff: 1x por estado +
            // heartbeat de 5 s (nao inundar o gate com 4 prints/s).
            g_watchdog_faults++;
            I64 wd_act = HEALTH_ACTION_NONE;
            if (wd_fixed > 0) wd_act = HEALTH_ACTION_NOREP;
            I64 wd_is_dup = HealthLogBackoff(HEALTH_SYM, wd_rem);
            if (wd_is_dup && wd_fixed == 0) {
                // Estado inalterado dentro do backoff: nem registra nem imprime
                // (a deteccao faults++ ja aconteceu acima). O registro so
                // acontece na 1a passada do estado e a cada heartbeat (5 s).
            } else {
                if (wd_fixed > 0) wd_act = HEALTH_ACTION_NOREP;
                I64 wd_payload = (I64)((U64)wd_act << 32) | wd_rem;
                HealthLogRecord(HEALTH_SYM, wd_payload, wd_fixed);
                doldoc_printf("$FG,RED$[WATCHDOG] SYMBOL FAULT: %lld unresolved restantes (reparados=%lld, NAO-reparados=%lld)$FG$\n",
                              wd_rem, wd_fixed, wd_rem);
            }
        } else if (wd_fixed > 0) {
            // Reparo completo: o scan voltou a 0 e a passada reparou algo.
            // Registra o evento de REPAIR (payload = total reparado).
            I64 wd_rep_payload = (I64)((U64)HEALTH_ACTION_REPAIR << 32) | wd_fixed;
            HealthLogRecord(HEALTH_SYM, wd_rep_payload, 0);
            doldoc_printf("$FG,GREEN$[WATCHDOG] SYM REPAIR: %lld unresolved(s) de teste re-registrados para SymNoop — tabela limpa$FG$\n",
                          wd_fixed);
        }

        // 2. Tabelas de orcamento (P0.2): grita se QUALQUER teto critico
        //    estourar. PULA durante o selftest: o SelfTestOverflowInjection
        //    leva os contadores ao teto DE PROPOSITO — seria falso positivo.
        //    NAO ha reparo (decisao documentada no cabecalho): subir teto
        //    mascara a pressao real; alarme pede decisao humana.
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
            I64 wd_bdup = HealthLogBackoff(HEALTH_BUDGET, wd_budget_id);
            if (wd_bdup == 0) {
                HealthLogRecord(HEALTH_BUDGET, wd_budget_id, 0);
                doldoc_printf("$FG,RED$[WATCHDOG] BUDGET FAULT: funcs=%lld/%lld globals=%lld/%lld$FG$\n",
                              g_hc_func_count, HC_MAX_FUNCS, g_hc_global_count, HC_MAX_GLOBALS);
                doldoc_printf("$FG,RED$[WATCHDOG] BUDGET FAULT: map=%lld/%lld fnf=%lld/%lld$FG$\n",
                              g_hc_map_count, HC_MAP_MAX, g_hc_fnf_count, HC_FNF_MAX);
            }
        }

        // 3. Canario do heap: o head deve ter o canario intacto. A Camada 3
        //    RESTAURA so o canario do HEAD, depois de validar a PREMISSA de
        //    seguranca (head livre + proximo intacto) em CanaryRepairHead.
        //    Canario interior corrompido continua NOREP (requer reconstruir a
        //    lista — fora do escopo) e o KHeap o detecta via KHeapCheckAll.
        if (g_heap_head != 0 && g_heap_head->canary_head != HEAP_CANARY) {
            g_watchdog_faults++;
            U64 wd_canary_seen = g_heap_head->canary_head;  // valor corrompido (capturado ANTES do reparo)
            I64 wd_canary_low = (I64)(wd_canary_seen & 0xFFFFFFFF);
            I64 wd_canary_act = HEALTH_ACTION_NONE;
            if (CanaryRepairHead() == 1) {
                wd_canary_act = HEALTH_ACTION_REPAIR;
            } else {
                wd_canary_act = HEALTH_ACTION_NOREP;
            }
            I64 wd_cdup = HealthLogBackoff(HEALTH_CANARY, wd_canary_low);
            // CANARY REPAIR (acao mudou) sempre registra/imprime — e a acao
            // de auto-cura que o gate precisa ver. Violacao NAO reparada segue
            // o backoff (1x por estado + heartbeat de 5 s).
            if (wd_canary_act == HEALTH_ACTION_REPAIR) {
                HealthLogRecord(HEALTH_CANARY, (I64)((U64)HEALTH_ACTION_REPAIR << 32) | wd_canary_low, 0);
                doldoc_printf("$FG,GREEN$[WATCHDOG] CANARY REPAIR: head 0x%016llX canary 0x%016llX -> 0x%016llX$FG$\n",
                              (U64)g_heap_head, wd_canary_seen, HEAL_CANARY);
            } else if (wd_cdup == 0) {
                HealthLogRecord(HEALTH_CANARY, (I64)((U64)HEALTH_ACTION_NOREP << 32) | wd_canary_low, 0);
                doldoc_printf("$FG,RED$[WATCHDOG] HEAP CANARY VIOLATION (head=0x%016llX canary=0x%016llX, NAO reparado: premissa invalida)$FG$\n",
                              (U64)g_heap_head, wd_canary_seen);
            }
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
    // Registra SymNoop na tabela soberana UMA vez (destino de reparo dos
    // payloads de teste). Sem symbols_register (contado pelo CENSUS): SymRegister
    // e o caminho .HC nativo e idempotente.
    SymRegister("SymNoop", (U64)&SymNoop, WD_SYM_FUNC);
    HealthLogInit();
    // Zera o estado do dedup da Camada 3 (globais comecam zerados pelo loader,
    // mas o WatchdogStart pode rodar apos reboot quente sem recarregar o
    // modulo — redundante e barato).
    g_heal_key[1] = 0; g_heal_key[2] = 0; g_heal_key[3] = 0; g_heal_key[4] = 0;
    g_heal_ms[1] = 0; g_heal_ms[2] = 0; g_heal_ms[3] = 0; g_heal_ms[4] = 0;
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