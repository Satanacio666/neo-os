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
    if (c != cur && c->state == TASK_READY && SchedAffinityAllows(c, me)) {
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
    if (c != cur && c->state == TASK_READY) {
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

  g_sched_current = main_task;
  g_sched_head = main_task;
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
  g_sched_need_resched = 1;
  __sev();
}

U0 TaskExit() {
  if (!g_sched_current) return;
  if (g_sched_zombie) SchedReapZombie();

  CTask *dying = g_sched_current;
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

// Called from the timer IRQ with `sp` = the interrupted task's saved trap frame.
// Returns the SP to resume (same frame, or the next task's frame).
U64 SchedOnTick(U64 sp) {
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
