// NeoOS Sovereign Pure HolyC Task Scheduler & Round-Robin Executive
// Ring 0 Thread State Machine with Priority Queuing, Deferred Zombie Reaping & SMP Affinity

#define TASK_READY    0
#define TASK_RUNNING  1
#define TASK_SLEEPING 2
#define TASK_BLOCKED  3
#define TASK_DEAD     4

#define PRIO_IDLE        0
#define PRIO_BACKGROUND  1
#define PRIO_INTERACTIVE 2
#define PRIO_REALTIME    3

class CTask {
  U64    id;
  U8     name[32];
  I64    state;
  I64    priority;
  U64    entry_fn;
  U64    arg;
  U8    *stack_base;
  U64    stack_size;
  U64    sp;
  I64    quantum_ticks;
  I64    quantum_remaining;
  U32    affinity_mask;
  CTask *next;
  CTask *prev;
  // CAMADA 2 (IDEA-1): dono e ultimo core. running_on_core impede que DOIS cores
  // peguem a MESMA task (-1 = livre, c = rodando no core c); last_ran_core
  // registra onde ela rodou por ultimo (prova do Watchdog no core 1).
  I64    running_on_core;
  I64    last_ran_core;
  // CAMADA 2: run-queue DONA da task (-1 = orfa, qualquer core pode pegar).
  // Derivada da afinidade quando o mask e' de um unico core (ex.: Watchdog 0x02 ->
  // owner 1); senao o core criador. E' o que impede o core 0 de roubar o Watchdog.
  I64    owner_rq;
};

CTask *g_sched_current;
CTask *g_sched_head;
U64    g_sched_next_id;
CTask *g_sched_zombie;
U64    g_sched_switch_count;

// P3.5: set by TaskYield()/TaskExit() (a switch is wanted) and by the timer IRQ
// (quantum expiry). SchedOnTick() performs the actual switch in IRQ context.
I64    g_sched_need_resched = 0;
I64    g_sched_ticks_seen = 0;
I64    g_sched_preempt_off = 0; // >0 defers preemption (kernel critical section)
I64    g_sched_ready = 0;       // set by SchedInit; gates SchedOnTick from the IRQ

// ============================================================================
// CAMADA 2 (IDEA-1) — RUN-QUEUES POR CORE (MQMS). 64 bytes EXATOS por core (uma
// linha L1D), arena alinhada por &~63 em SchedInit — mesmo idioma do CProdCount
// (Camada 0.2) e do CGicCoreStats (Camada 1.1). Zero kmalloc, zero CENSUS.
// ============================================================================
#define SCHED_MAX_CORES 4
class CSmpRunQueue {
  U32    lock;            // reservado: a secao critica usa g_sched_lock (a lista
  U32    pad_u32;         // de tasks e' GLOBAL); mantido por layout/explicitude.
  CTask *curr_task;       // task atual deste core (0 = thread nativa do core)
  U64    idle_frame_sp;   // CTrapFrame* da thread nativa (SmpWorkerLoop nos cores 1..3)
  I64    sched_ticks;     // ticks que ESTE core passou pelo escalonador
  I64    context_switches;// trocas de contexto REAIS neste core
  CTask *last_task;       // ultima task executada neste core
  I64    need_resched;    // CAMADA 2: yield pedido POR ESTE core (era pad0)
  I64    pad1;
};   // 4+4+8*7 = 64 bytes EXATOS = 1 linha L1D
U8            g_sched_rq_arena[SCHED_MAX_CORES * 64 + 64];
CSmpRunQueue *g_sched_rq;
U32           g_sched_lock = 0;          // protege a lista de tasks + os slots de rq

// P3.5 guardrail 2: trap-frame layout written by vectors.S SAVE_ALL (784 bytes):
//   [0..223]   x0..x29 (8 bytes each)
//   [240]      x30 (LR)
//   [248]      ELR_EL1
//   [256]      SPSR_EL1
//   [264]      SP_EL0
//   [272..783] Q0..Q31
#define SCHED_FRAME_SIZE 784

// B5 (ONDA 2) — canario de pilha. Valor LITERAL PURO ("STKCANAR" em ASCII):
// o Compiler.HC documenta que "a PRODUCT of two macros is the one form it does
// not fold reliably", entao nada de produto de macros aqui.
#define STACK_CANARY 0x53544B43414E4152
// Contador observavel: cada violacao vista no ponto de troca.
U64 g_stack_canary_violations = 0;

// Pick the highest-priority READY task other than `cur` (round-robin within a
// band). Walks from g_sched_head so a removed (dead) `cur` cannot loop forever.
// B2b (ONDA 3) — afinidade SUAVE. DECISAO PURA (testavel sem hardware, licao do
// B11): uma task e' ELEGIVEL no core atual se o bit do core esta' no seu
// affinity_mask. mask==0 significa "sem restricao" (qualquer core).
// Recebe a MASK (nao o CTask*) porque SelfTest.HC compila ANTES de Sched.HC e
// nao enxerga o tipo CTask (mesma razao do B5 usar endereco cru).
I64 SchedAffinityAllowsMask(U32 mask, U32 core_id) {
  if (mask == 0) return 1;
  return ((mask >> core_id) & 1) != 0;
}
I64 SchedAffinityAllows(CTask *t, U32 core_id) {
  if (!t) return 0;
  return SchedAffinityAllowsMask(t->affinity_mask, core_id);
}

// B2b: escolhe a proxima task. Em DUAS passadas:
//   1. passada ESTRITA: so' tasks cujo affinity_mask contem o core atual;
//   2. passada de RELAXAMENTO: se a estrita nao achou nada, aceita qualquer
//      READY (senao uma task presa a um core que ela nao roda ficaria STARVADA —
//      ex.: o Watchdog tem mask=0x02, e se o core 1 nao escalar ninguem, ele
//      sumiria em silencio). Cada relaxamento e' CONTADO em
//      g_sched_affinity_relaxed, para o sintoma ser visivel.
I64 g_sched_affinity_relaxed = 0;
// B2b: troca forcada porque a task ATUAL nao pertencia a este core (afinidade).
I64 g_sched_affinity_moves = 0;
CTask* SchedPickNext(CTask *cur) {
  U32 me = (U32)(__mrs_mpidr() & 3);
  // Passada 1: estrita (respeita afinidade).
  CTask *best = 0;
  I64 best_prio = -1;
  CTask *c = g_sched_head;
  I64 guard = 0;
  while (c && guard < 4096) {
    if (c != cur && c->state == TASK_READY && SchedAffinityAllows(c, me)
        && (c->running_on_core == -1 || c->running_on_core == (I64)me)) {
      if (!best || c->priority > best_prio) {
        best = c;
        best_prio = c->priority;
      }
    }
    c = c->next;
    guard++;
    if (c == g_sched_head) break;
  }
  if (best) return best;
  // Passada 2: relaxamento (contado) — nenhuma task afinizada neste core.
  c = g_sched_head;
  guard = 0;
  while (c && guard < 4096) {
    if (c != cur && c->state == TASK_READY
        && (c->running_on_core == -1 || c->running_on_core == (I64)me)) {
      if (!best || c->priority > best_prio) {
        best = c;
        best_prio = c->priority;
      }
    }
    c = c->next;
    guard++;
    if (c == g_sched_head) break;
  }
  if (best) g_sched_affinity_relaxed = g_sched_affinity_relaxed + 1;
  return best;
}

U0 SchedStrCpy(U8 *dst_buf, U8 *src_buf) {
  if (!dst_buf || !src_buf) return;
  I64 ssc_idx = 0;
  while (src_buf[ssc_idx] != 0 && ssc_idx < 31) {
    dst_buf[ssc_idx] = src_buf[ssc_idx];
    ssc_idx++;
  }
  dst_buf[ssc_idx] = 0;
}

I64 SchedStrCmp(U8 *s1, U8 *s2) {
  if (!s1 || !s2) return -1;
  I64 scmp_pos = 0;
  while (s1[scmp_pos] != 0 && s2[scmp_pos] != 0) {
    if (s1[scmp_pos] != s2[scmp_pos]) return s1[scmp_pos] - s2[scmp_pos];
    scmp_pos++;
  }
  return s1[scmp_pos] - s2[scmp_pos];
}

// B5 (ONDA 2): verificacao do canario de UMA task. Recebe o endereco cru (o
// SelfTest.HC e' compilado ANTES de Sched.HC e nao enxerga CTask). Devolve:
//   1 = intacto OU fora do escopo (stack_base == 0: a task KernelMain do boot)
//   0 = CORROMPIDO (grita)
// Nao incrementa contador algum: quem decide "nunca trocar" e' SchedOnTick.
I64 SchedCanaryOk(U64 task_addr) {
  if (task_addr == 0) return 1;
  CTask *t = (CTask *)task_addr;
  if (t->stack_base == 0) return 1;   // KernelMain: sem pilha propria (boot)
  if (*(U64 *)t->stack_base == (U64)STACK_CANARY) return 1;
  return 0;
}

// B5 (ONDA 2): sonda do CAMINHO DE FALHA. Prova o ciclo completo numa task real
// (canario GRAVADO -> corrupcao DETECTADA -> restaurado). Devolve 1 so' se as 3
// etapas baterem; sem o fix (canario nunca gravado) a etapa 1 falha e devolve 0.
I64 SchedTestCanaryCycle(U64 task_addr) {
  if (task_addr == 0) return 0;
  CTask *t = (CTask *)task_addr;
  if (t->stack_base == 0) return 0;             // sem pilha: fora do escopo
  if (SchedCanaryOk(task_addr) != 1) return 0;  // 1. o canario FOI gravado
  *(U64 *)t->stack_base = 0xDEADDEADDEADDEAD;   // 2. forca a violacao
  I64 detected = 0;
  if (SchedCanaryOk(task_addr) == 0) detected = 1;
  *(U64 *)t->stack_base = (U64)STACK_CANARY;    // 3. restaura
  if (SchedCanaryOk(task_addr) != 1) return 0;  //    e confirma o retorno
  return detected;
}

U0 SchedReapZombie() {
  if (!g_sched_zombie) return;
  CTask *z = g_sched_zombie;
  g_sched_zombie = 0;
  if (z->stack_base) {
    kfree(z->stack_base);
    z->stack_base = 0;
  }
  kfree(z);
}

U0 SchedCleanupAll() {
  SchedReapZombie();
  if (!g_sched_head) {
    g_sched_current = 0;
    return;
  }
  // Break circular list and free all nodes
  CTask *tail = g_sched_head->prev;
  if (tail) tail->next = 0;

  CTask *curr = g_sched_head;
  while (curr) {
    CTask *nxt = curr->next;
    if (curr->stack_base) {
      kfree(curr->stack_base);
      curr->stack_base = 0;
    }
    kfree(curr);
    curr = nxt;
  }
  g_sched_head = 0;
  g_sched_current = 0;
}

U0 SchedInit() {
  SchedCleanupAll();
  g_sched_next_id = 1;
  g_sched_zombie = 0;
  g_sched_switch_count = 0;
  g_sched_need_resched = 0;
  g_sched_ticks_seen = 0;

  CTask *main_task = kmalloc(sizeof(CTask));
  if (!main_task) return;

  main_task->id = g_sched_next_id;
  g_sched_next_id = g_sched_next_id + 1;
  SchedStrCpy(main_task->name, "KernelMain");
  main_task->state = TASK_RUNNING;
  main_task->priority = PRIO_INTERACTIVE;
  main_task->entry_fn = 0;
  main_task->arg = 0;
  main_task->stack_base = 0;
  main_task->stack_size = 0;
  main_task->sp = 0;
  main_task->quantum_ticks = 5;
  main_task->quantum_remaining = 5;
  main_task->affinity_mask = 0x0F;
  main_task->next = main_task;
  main_task->prev = main_task;
  main_task->running_on_core = 0;   // KernelMain roda no BSP
  main_task->last_ran_core = 0;
  main_task->owner_rq = 0;          // CAMADA 2: pertence a run-queue do core 0

  g_sched_current = main_task;
  g_sched_head = main_task;

  // CAMADA 2: arena alinhada das run-queues + asserts de layout (falha ALTA).
  g_sched_rq = (CSmpRunQueue*)(((U64)g_sched_rq_arena + 63) & (~63));
  if (sizeof(CSmpRunQueue) != 64 || ((U64)g_sched_rq & 63) != 0) {
    doldoc_printf("[SCHED] FATAL: CSmpRunQueue layout != 64B (sizeof=%lld align=%lld)\n",
                  (I64)sizeof(CSmpRunQueue), (U64)g_sched_rq & 63);
  }
  I64 rqi = 0;
  while (rqi < SCHED_MAX_CORES) {
    g_sched_rq[rqi].lock = 0;
    g_sched_rq[rqi].curr_task = (rqi == 0) ? main_task : 0;  // core 0 = KernelMain;
    g_sched_rq[rqi].idle_frame_sp = 0;                       // cores 1..3 = nativa
    g_sched_rq[rqi].sched_ticks = 0;
    g_sched_rq[rqi].context_switches = 0;
    g_sched_rq[rqi].last_task = 0;
    rqi = rqi + 1;
  }
  g_sched_ready = 1; // scheduler is now live; IRQ may hand frames to SchedOnTick
}

CTask* TaskCreate(U8 *p_name, U64 p_entry, U64 p_arg, I64 p_stack_sz) {
  if (!g_sched_head) SchedInit();
  if (p_stack_sz < 4096) p_stack_sz = 4096;

  CTask *t = kmalloc(sizeof(CTask));
  if (!t) return 0;

  U8 *stk = kmalloc(p_stack_sz);
  if (!stk) {
    kfree(t);
    return 0;
  }

  t->id = g_sched_next_id;
  g_sched_next_id = g_sched_next_id + 1;
  SchedStrCpy(t->name, p_name);
  t->state = TASK_READY;
  t->priority = PRIO_INTERACTIVE;
  t->entry_fn = p_entry;
  t->arg = p_arg;
  t->stack_base = stk;
  t->stack_size = p_stack_sz;

  // B5 (ONDA 2): grava o canario no FUNDO da pilha (base). A pilha cresce para
  // baixo e o trap frame vai em top-784 (SCHED_FRAME_SIZE), bem longe do base —
  // logo o canario so' e' tocado se a task ESTOURAR a pilha (o caso que importa).
  *(U64 *)stk = (U64)STACK_CANARY;

  // P3.5: build a full initial trap frame so the first preemptive switch can
  // RESTORE_ALL + eret straight into entry_fn(arg).
  SchedBuildFrame(t);
  t->quantum_ticks = 5;
  t->quantum_remaining = 5;
  t->affinity_mask = 0x0F;
  t->running_on_core = -1;   // CAMADA 2: livre (nenhum core a executa ainda)
  t->last_ran_core = -1;
  // owner_rq: se a afinidade aponta UM core, a task pertence a ele; senao ao
  // criador. (O Watchdog ajusta depois de setar affinity 0x02 — ver TaskSetOwner.)
  U32 cm = t->affinity_mask;
  if (cm != 0 && (cm & (cm - 1)) == 0) {
    I64 oc = 0; while (((cm >> oc) & 1) == 0) oc = oc + 1;
    t->owner_rq = oc;
  } else {
    t->owner_rq = (I64)(__mrs_mpidr() & 3);
  }

  // Insert into circular doubly linked list (IRQs masked: SchedOnTick walks it).
  __irq_disable();
  t->next = g_sched_head;
  t->prev = g_sched_head->prev;
  CTask *h_prev = g_sched_head->prev;
  h_prev->next = t;
  g_sched_head->prev = t;
  __irq_enable();

  g_sched_need_resched = 1; // let the next tick run the new task promptly
  __sev();
  return t;
}

// P3.5: voluntary yield is now a *request*; the actual switch happens in IRQ
// context (SchedOnTick) so there is exactly ONE switch mechanism (the trap
// frame) — correct for both voluntary and asynchronous switches (guardrail 2).
U0 TaskYield() {
  // CAMADA 2: pedido de yield POR CORE (cada core le' o proprio no seu tick);
  // o global segue setado para o caminho do core 0.
  I64 mycore = (I64)(__mrs_mpidr() & 3);
  if (g_sched_rq && mycore >= 0 && mycore < SCHED_MAX_CORES) {
    g_sched_rq[mycore].need_resched = 1;
  }
  g_sched_need_resched = 1;
  __sev();
}

U0 TaskExit() {
  // CAMADA 2: a task que morre e' a do CORE ATUAL, nao o global g_sched_current.
  // (Bug medido: um worker no core 1 marcava a KernelMain do core 0 como DEAD e a
  // desligava da lista -> double fault.)
  I64 mycore = (I64)(__mrs_mpidr() & 3);
  CTask *dying;
  if (mycore == 0) {
    dying = g_sched_current;
  } else {
    dying = (g_sched_rq ? g_sched_rq[mycore].curr_task : 0);
  }
  if (!dying) return;
  if (g_sched_zombie && g_sched_zombie != dying) SchedReapZombie();
  dying->state = TASK_DEAD;

  // Unlink from the circular list. g_sched_current stays = dying so SchedOnTick
  // saves its (discarded) frame; SchedPickNext skips it (removed from list).
  __irq_disable();
  if (dying->next != dying) {
    CTask *d_prev = dying->prev;
    CTask *d_next = dying->next;
    d_prev->next = d_next;
    d_next->prev = d_prev;
    if (g_sched_head == dying) g_sched_head = d_next;
  }
  g_sched_zombie = dying;
  g_sched_need_resched = 1;
  __irq_enable();
  __sev();

  // Never return to the dying stack; the next tick switches away, then the
  // zombie stack is reaped from the new task's stack.
  while (1) {
    __wfe();
  }
}

// Build the initial 784-byte trap frame for a brand-new task (guardrail 2).
U0 SchedBuildFrame(CTask *t) {
  if (!t || !t->stack_base) return;
  U64 top = ((U64)t->stack_base + t->stack_size) & ~15;
  U64 frame = top - SCHED_FRAME_SIZE;
  U8 *fp = (U8*)frame;
  I64 i = 0;
  while (i < SCHED_FRAME_SIZE) { fp[i] = 0; i++; }
  *(U64*)(frame + 0)   = t->arg;          // x0 = arg
  *(U64*)(frame + 240) = (U64)&TaskExit;  // x30 = return trampoline
  *(U64*)(frame + 248) = t->entry_fn;     // ELR_EL1
  *(U64*)(frame + 256) = 0x5;             // SPSR_EL1 = EL1h, DAIF clear
  *(U64*)(frame + 264) = 0;               // SP_EL0
  t->sp = frame;
}

// CORPO COMPROVADO (inalterado): o nucleo do escalonamento. Roda com g_sched_lock
// preso (ver o wrapper SchedOnTick abaixo). Nao mexer na logica — o gate de
// determinismo depende dela.
U64 SchedOnTickLocked(U64 sp) {
  // Never free a zombie whose stack we are currently executing on: a dying task
  // that is preempted has its frame on its own stack. Reap only a *previous*
  // zombie (different stack) — the current one is freed on the next tick.
  if (g_sched_zombie && g_sched_zombie != g_sched_current) SchedReapZombie();
  g_sched_ticks_seen = g_sched_ticks_seen + 1;
  if (!g_sched_current) return sp;

  CTask *cur = g_sched_current;
  cur->sp = sp;

  I64 need = g_sched_need_resched;
  g_sched_need_resched = 0;
  if (cur->quantum_remaining > 0) cur->quantum_remaining = cur->quantum_remaining - 1;
  if (cur->quantum_remaining > 0 && !need) return sp;

  // Guardrail 1: defer the switch inside a kernel critical section (compiler
  // lock / scheduler self-test).
  if (g_hc_compiling || g_sched_preempt_off) {
    cur->quantum_remaining = 1;
    return sp;
  }

  // B5 (ONDA 2) — guarda de pilha no ponto de troca. O canario vive no FUNDO
  // da pilha da task que esta' SAINDO (cur). Se ele sumiu, a task estourou a
  // pilha para baixo: o frame dela ja' e' suspeito. DECISAO (documentada):
  // NAO trocar — continuar em cur com quantum reiniciado. Trocar salvaria o
  // frame sobre uma pilha ja' corrompida (agravaria) e esconderia a evidencia.
  // KernelMain tem stack_base == 0 e e' PULADA (sem pilha propria no boot).
  if (cur->stack_base != 0 && *(U64 *)cur->stack_base != (U64)STACK_CANARY) {
    g_stack_canary_violations++;
    if (g_stack_canary_violations == 1) {
      doldoc_printf("$FG,RED$[SCHED] STACK CANARY VIOLATION: task '%s' (id=%lld base=0x%016llX) — canario corrompido; troca BLOQUEADA$FG$\n",
                    cur->name, cur->id, (U64)cur->stack_base);
    }
    cur->quantum_remaining = cur->quantum_ticks;
    return sp;
  }

  // B2b (ONDA 3) — afinidade: se a task ATUAL nao pode rodar neste core (o
  // affinity_mask dela nao inclui este core), ela nao deve continuar aqui. Marca
  // READY e deixa o SchedPickNext escolher outra (a passada estrita vai preferir
  // uma task feita para este core). Sem isto, uma task rodaria no core errado.
  U32 me_now = (U32)(__mrs_mpidr() & 3);
  if (!SchedAffinityAllows(cur, me_now)) {
    cur->state = TASK_READY;
    cur->quantum_remaining = 0;
    g_sched_affinity_moves = g_sched_affinity_moves + 1;
  }

  CTask *best = SchedPickNext(cur);
  if (!best) { cur->quantum_remaining = cur->quantum_ticks; return sp; }

  if (cur->state == TASK_RUNNING) cur->state = TASK_READY;
  best->state = TASK_RUNNING;
  best->quantum_remaining = best->quantum_ticks;
  g_sched_current = best;
  g_sched_switch_count = g_sched_switch_count + 1;
  return best->sp;
}

// CAMADA 2 (IDEA-1) — wrappers de core. O caminho do Core 0 e' o de sempre, agora
// sob g_sched_lock (a lista de tasks passa a ser compartilhada entre cores).
U64 SchedOnTick(U64 sp) {
  U64 sched_daif = SmpLockIrqSave(&g_sched_lock);
  U64 r = SchedOnTickLocked(sp);
  SmpUnlockIrqRestore(&g_sched_lock, sched_daif);
  return r;
}

// CAMADA 2 — escalonamento do core `core`. Core 0 delega ao caminho comprovado.
// Cores 1..3: cada um mantem a PROPRIA thread nativa (SmpWorkerLoop, representada
// por rq->curr_task == 0) e alterna com as tasks cujo affinity_mask contem o bit
// do core — protegia por g_sched_lock e por running_on_core (impede que dois cores
// peguem a mesma task). Preserva a pilha nativa em rq->idle_frame_sp.
U64 SchedOnTickCore(I64 core, U64 frame_sp) {
  if (core < 0 || core >= SCHED_MAX_CORES || !g_sched_rq) return frame_sp;
  CSmpRunQueue *rq = &g_sched_rq[core];
  rq->sched_ticks = rq->sched_ticks + 1;
  if (g_sched_dbg != 0 && rq->sched_ticks <= 3) SchedDbgEvent(core, 1, (I64)frame_sp);
  if (core == 0) return SchedOnTick(frame_sp);   // caminho comprovado (com lock)
  if (g_sched_preempt_off) return frame_sp;      // secao critica: nao preemptar

  U64 sched_daif = SmpLockIrqSave(&g_sched_lock);
  // Reaping do zumbi: NUNCA o que esta' na pilha que estamos executando agora.
  if (g_sched_zombie && g_sched_zombie != g_sched_rq[core].curr_task) SchedReapZombie();
  CTask *cur = rq->curr_task;                    // 0 = thread nativa (SmpWorkerLoop)
  if (cur) { cur->sp = frame_sp; cur->last_ran_core = core; }
  else { rq->idle_frame_sp = frame_sp; }

  I64 need = rq->need_resched;                   // CAMADA 2: por core
  rq->need_resched = 0;
  if (cur) {
    if (cur->quantum_remaining > 0) cur->quantum_remaining = cur->quantum_remaining - 1;
    if (cur->quantum_remaining > 0 && !need) {
      SmpUnlockIrqRestore(&g_sched_lock, sched_daif);
      return frame_sp;                           // quantum do core ainda nao expirou
    }
  }
  // Canario de pilha da task que esta' SAINDO (mesma regra do B5).
  if (cur && cur->stack_base != 0 && *(U64 *)cur->stack_base != (U64)STACK_CANARY) {
    g_stack_canary_violations = g_stack_canary_violations + 1;
    cur->quantum_remaining = cur->quantum_ticks;
    SmpUnlockIrqRestore(&g_sched_lock, sched_daif);
    return frame_sp;
  }
  // Escolhe a proxima task ELEGIVEL neste core (afinidade + running_on_core).
  CTask *best = 0;
  I64 best_prio = -1;
  CTask *c = g_sched_head;
  I64 guard = 0;
  while (c && guard < 4096) {
    // CAMADA 2: pertence a ESTE core (owner_rq) e nao esta' presa em outro.
    if (c != cur && c->state == TASK_READY
        && (c->owner_rq == -1 || c->owner_rq == core)
        && (c->running_on_core == -1 || c->running_on_core == core)) {
      if (!best || c->priority > best_prio) { best = c; best_prio = c->priority; }
    }
    c = c->next; guard++;
    if (c == g_sched_head) break;
  }
  U64 ret = frame_sp;
  if (best) {
    if (cur && cur->state == TASK_RUNNING) cur->state = TASK_READY;
    if (cur && cur->running_on_core == core) cur->running_on_core = -1;
    best->state = TASK_RUNNING;
    best->running_on_core = core;
    best->last_ran_core = core;
    best->quantum_remaining = best->quantum_ticks;
    rq->last_task = cur;
    rq->curr_task = best;
    rq->context_switches = rq->context_switches + 1;
    ret = best->sp;
  } else if (cur) {
    // Nenhuma task elegivel: devolve o core a' sua thread nativa (SmpWorkerLoop),
    // que continua atendendo Math3DPar/RasterTile. Se a nativa nunca rodou
    // (idle_frame_sp == 0: impossivel em operacao — ela roda antes das tasks), o
    // frame atual e' devolvido e nada quebra.
    cur->running_on_core = -1;
    if (cur->state == TASK_RUNNING) cur->state = TASK_READY;
    rq->curr_task = 0;
    if (rq->idle_frame_sp != 0) {
      rq->context_switches = rq->context_switches + 1;
      ret = rq->idle_frame_sp;
    }
  }
  SmpUnlockIrqRestore(&g_sched_lock, sched_daif);
  return ret;
}

// CAMADA 2 (IDEA-1) — registra a thread NATIVA de um core secundario (o
// SmpWorkerLoop). Ela e' representada por rq->curr_task == 0 ("sem CTask"): o
// escalonador preserva sua pilha em idle_frame_sp e devolve o core a ela quando
// nao ha task elegivel. Chamada por Smp.HC (Stage 3, compilado DEPOIS de Sched.HC).
U64 g_sched_native_cores = 0;
U0 SmpRegisterNativeThread(U32 core, U64 entry) {
  if (core == 0 || core >= SCHED_MAX_CORES || !g_sched_rq) return;
  g_sched_rq[core].curr_task = 0;
  g_sched_rq[core].idle_frame_sp = 0;   // capturado no 1o tick deste core
  g_sched_native_cores = g_sched_native_cores | (1 << core);
  __dmb_ish();
}

// CAMADA 2 (IDEA-1) — provas puras das run-queues (SelfTest.HC e' Stage 1 e NAO
// enxerga CSmpRunQueue; estas funcoes em Sched.HC devolvem numeros crus).
// CAMADA 2 — DEBUG gated (desligado por padrao; o gate nao polui). Ligue com o
// comando 'scheddbg 1' (ou setando g_sched_dbg). Rastreia as trocas por core.
I64 g_sched_dbg = 0;
I64 g_sched_dbg_events[8];

U0 SchedDbgEvent(I64 core, I64 tag, I64 val) {
  if (g_sched_dbg == 0 || !g_sched_dbg_events) return;
  if (core < 0 || core >= SCHED_MAX_CORES) return;
  if (g_sched_dbg_events[core] >= 12) return;   // limita o ruido
  g_sched_dbg_events[core] = g_sched_dbg_events[core] + 1;
  doldoc_printf("[SCHEDDBG] core=%lld ev=%lld tag=%lld val=%lld cur=%lld rqticks=%lld\n",
                core, g_sched_dbg_events[core], tag, val,
                g_sched_rq[core].curr_task ? g_sched_rq[core].curr_task->id : -1,
                g_sched_rq[core].sched_ticks);
}

// Alias: hash simples para confirmar que nada foi esquecido (debug).
U64 SchedRqHash() {
  if (!g_sched_rq) return 0;
  U64 h = 0x811C9DC5;
  I64 i = 0;
  while (i < SCHED_MAX_CORES) {
    h = (h ^ (U64)g_sched_rq[i].sched_ticks) * 16777619;
    h = (h ^ (U64)g_sched_rq[i].context_switches) * 16777619;
    i = i + 1;
  }
  return h;
}

I64 SchedRqSizesOk() {
  if (sizeof(CSmpRunQueue) != 64) return 0;
  if (!g_sched_rq) return 0;
  if (((U64)g_sched_rq & 63) != 0) return 0;
  return 1;
}
// Soma de sched_ticks nos cores 1..3 (prova de que o escalonador rodou neles).
I64 SchedRqSecondaryTicks() {
  if (!g_sched_rq) return 0;
  I64 t = 0, i = 1;
  while (i < SCHED_MAX_CORES) { t = t + g_sched_rq[i].sched_ticks; i = i + 1; }
  return t;
}
// Trocas de contexto reais no core 1 (prova fisica de scheduling no secundario).
I64 SchedRqCore1Switches() {
  if (!g_sched_rq) return 0;
  return g_sched_rq[1].context_switches;
}
// Cores que registraram sua thread nativa (SmpWorkerLoop) — bitmask.
U64 SchedNativeCores() { return g_sched_native_cores; }

// CAMADA 2: recomputa owner_rq a partir da afinidade (idempotente). Chamar depois
// de setar affinity_mask a mao (ex.: WatchdogStart).
U0 TaskSetOwner(CTask *t) {
  if (!t) return;
  U32 cm = t->affinity_mask;
  if (cm != 0 && (cm & (cm - 1)) == 0) {
    I64 oc = 0; while (((cm >> oc) & 1) == 0) oc = oc + 1;
    t->owner_rq = oc;
  }
}

I64 TaskSetAffinity(U64 p_task_id, U32 p_mask) {
  if (!g_sched_head) return -1;
  CTask *curr = g_sched_head;
  while (curr) {
    if (curr->id == p_task_id) {
      curr->affinity_mask = p_mask;
      return 0;
    }
    curr = curr->next;
    if (curr == g_sched_head) break;
  }
  return -1;
}

I64 SchedCountTasks() {
  if (!g_sched_head) return 0;
  I64 count = 0;
  CTask *curr = g_sched_head;
  while (curr) {
    count++;
    curr = curr->next;
    if (curr == g_sched_head) break;
  }
  return count;
}

U0 SchedPrintDolDoc() {
  I64 t_count = SchedCountTasks();
  doldoc_print("\n$CARD,title=\"Sovereign Task Executive & Core Scheduler\",w=96,h=6,bg=0xFF1E1E2E,border=0xFF89B4FA$\n");
  doldoc_printf("  $FG,SAPPHIRE$Active Tasks:$FG$ %lld   $FG,SAPPHIRE$Context Switches:$FG$ %lld   $FG,SAPPHIRE$Model:$FG$ Ring-0 SASOS Executive\n",
                t_count, g_sched_switch_count);
  doldoc_print("$HR$\n");
  if (!g_sched_head) {
    doldoc_print("  $FG,MUTED$(No tasks registered)$FG$\n\n");
    return;
  }
  CTask *curr = g_sched_head;
  while (curr) {
    U8 *st_str = "READY  ";
    if (curr->state == TASK_RUNNING) st_str = "RUNNING";
    else if (curr->state == TASK_SLEEPING) st_str = "SLEEP  ";
    else if (curr->state == TASK_BLOCKED) st_str = "BLOCKED";
    else if (curr->state == TASK_DEAD) st_str = "DEAD   ";

    doldoc_printf("  $FG,CYAN$#%02lld$FG$  $FG,WHITE$%-16s$FG$  $FG,GREEN$%s$FG$  Prio: %lld  Aff: 0x%02X\n",
                  curr->id, curr->name, st_str, curr->priority, curr->affinity_mask);
    curr = curr->next;
    if (curr == g_sched_head) break;
  }
  doldoc_print("$HR$\n\n");
}

U0 SchedTestWorker(U64 arg) {
  while (1) { __wfe(); }
}

I64 SchedSelfTest() {
  doldoc_printf("\n$FG,CYAN$[SCHED-TEST] Starting Pure HolyC Scheduler & Task Executive Verification...$FG$\n");

  // Defer preemption for the test so the assertions are deterministic.
  g_sched_preempt_off = 1;

  // Test 1: SchedInit
  SchedInit();
  if (!g_sched_current || !g_sched_head || g_sched_current->id != 1 ||
      g_sched_current->state != TASK_RUNNING || SchedStrCmp(g_sched_current->name, "KernelMain") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: SchedInit failed!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: SchedInit established KernelMain task ID #1.$FG$\n");

  // Test 2: TaskCreate with REAL entry fns + trap-frame construction
  CTask *t2 = TaskCreate("WorkerA", (U64)&SchedTestWorker, 0, 8192);
  CTask *t3 = TaskCreate("WorkerB", (U64)&SchedTestWorker, 0, 8192);
  if (!t2 || !t3 || t2->id != 2 || t3->id != 3 || SchedCountTasks() != 3) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: TaskCreate failed to add tasks!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  if (t2->state != TASK_READY || t3->state != TASK_READY || (t2->sp & 15) != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: Task state or stack alignment failed!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Circular task queue with 3 tasks created.$FG$\n");

  // Test 3: priority selection (pure SchedPickNext)
  t3->priority = PRIO_REALTIME;
  t2->priority = PRIO_BACKGROUND;
  if (SchedPickNext(g_sched_current) != t3) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: Priority selection failed!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  t3->priority = PRIO_BACKGROUND;
  t2->priority = PRIO_REALTIME;
  if (SchedPickNext(g_sched_current) != t2) {
    doldoc_printf("$FG,RED$[FAIL] Test 3B: Priority selection failed!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Priority-aware task selection verified.$FG$\n");

  // Test 4: Affinity configuration
  if (TaskSetAffinity(2, 0x01) != 0 || t2->affinity_mask != 0x01) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: TaskSetAffinity failed!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Core affinity mask assignment verified.$FG$\n");

  // Test 5: trap-frame contents (guardrail 2)
  if (*(U64*)(t2->sp + 248) != (U64)&SchedTestWorker || *(U64*)(t2->sp + 256) != 0x5) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: trap frame (ELR/SPSR) malformed!$FG$\n");
    g_sched_preempt_off = 0; return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Full trap-frame context (ELR_EL1/SPSR_EL1) verified.$FG$\n");

  SchedPrintDolDoc();
  g_sched_preempt_off = 0;
  SchedInit(); // frees the test tasks, restores KernelMain
  doldoc_printf("\n[SCHED-PASS] ALL 5 SCHEDULER TESTS PASSED\n\n");
  return 1;
}

U0 task_yield() {
  TaskYield();
}

U0 top_print_doldoc() {
  SchedPrintDolDoc();
  SmpPrintDolDoc();
}

if (g_kernel_booting) {
  SchedInit();
} else {
  SchedSelfTest();
}
