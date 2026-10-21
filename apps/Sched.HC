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

  U64 sp_top = (stk + p_stack_sz - 16) & ~15;
  t->sp = sp_top;
  t->quantum_ticks = 5;
  t->quantum_remaining = 5;
  t->affinity_mask = 0x0F;

  // Insert into circular doubly linked list
  t->next = g_sched_head;
  t->prev = g_sched_head->prev;
  CTask *h_prev = g_sched_head->prev;
  h_prev->next = t;
  g_sched_head->prev = t;

  return t;
}

U0 TaskYield() {
  // Reap deferred zombie task on safe stack transition
  if (g_sched_zombie) {
    SchedReapZombie();
  }

  if (!g_sched_current) return;
  if (!g_sched_current->next) return;

  CTask *prev = g_sched_current;
  CTask *best = 0;
  I64 best_prio = -1;

  CTask *curr = g_sched_current->next;
  while (curr != g_sched_current) {
    if (!curr) break;
    if (curr->state == TASK_READY) {
      if (!best) {
        best = curr;
        best_prio = curr->priority;
      } else if (curr->priority > best_prio) {
        best = curr;
        best_prio = curr->priority;
      }
    }
    curr = curr->next;
  }

  if (!best) {
    return;
  }
  if (best->state != TASK_READY) {
    return;
  }

  if (prev->state == TASK_RUNNING) {
    prev->state = TASK_READY;
  }
  best->state = TASK_RUNNING;
  best->quantum_remaining = best->quantum_ticks;
  g_sched_current = best;
  g_sched_switch_count = g_sched_switch_count + 1;
}

U0 TaskExit() {
  if (!g_sched_current) return;

  // Reap any previously queued zombie before staging the current dying task
  if (g_sched_zombie) {
    SchedReapZombie();
  }

  CTask *dying = g_sched_current;
  dying->state = TASK_DEAD;

  if (dying->next != dying) {
    CTask *d_prev = dying->prev;
    CTask *d_next = dying->next;
    d_prev->next = d_next;
    d_next->prev = d_prev;
    if (g_sched_head == dying) {
      g_sched_head = d_next;
    }
    g_sched_current = d_next;
    g_sched_current->state = TASK_RUNNING;
  }

  // Defer stack & TCB deallocation to the next TaskYield() so we NEVER free
  // the active stack while executing on it!
  g_sched_zombie = dying;
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

I64 SchedSelfTest() {
  doldoc_printf("\n$FG,CYAN$[SCHED-TEST] Starting Pure HolyC Scheduler & Task Executive Verification...$FG$\n");

  // Test 1: SchedInit
  SchedInit();
  if (!g_sched_current || !g_sched_head || g_sched_current->id != 1 ||
      g_sched_current->state != TASK_RUNNING || SchedStrCmp(g_sched_current->name, "KernelMain") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: SchedInit failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: SchedInit established KernelMain task ID #1.$FG$\n");

  // Test 2: TaskCreate
  CTask *t2 = TaskCreate("WorkerA", 0x75001000, 0, 8192);
  CTask *t3 = TaskCreate("WorkerB", 0x75002000, 0, 8192);
  if (!t2 || !t3 || t2->id != 2 || t3->id != 3 || SchedCountTasks() != 3) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: TaskCreate failed to add tasks!$FG$\n");
    return 0;
  }
  if (t2->state != TASK_READY || t3->state != TASK_READY || (t2->sp & 15) != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2: Task state or stack alignment failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Circular doubly-linked task queue with 3 tasks created.$FG$\n");

  // Test 3: Priority selection and cooperative yield
  t3->priority = PRIO_REALTIME; // Make WorkerB higher priority than WorkerA
  TaskYield();
  if (g_sched_current->id != 3 || g_sched_current->state != TASK_RUNNING) {
    doldoc_printf("$FG,RED$[FAIL] Test 3: Priority task switch to WorkerB failed!$FG$\n");
    return 0;
  }
  // WorkerB yields back to ready tasks
  t3->priority = PRIO_BACKGROUND;
  TaskYield();
  if (g_sched_current->id != 1) {
    doldoc_printf("$FG,RED$[FAIL] Test 3A: Yield round-robin to KernelMain failed!$FG$\n");
    return 0;
  }
  TaskYield();
  if (g_sched_current->id != 2) {
    doldoc_printf("$FG,RED$[FAIL] Test 3B: Yield round-robin to WorkerA failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Priority-aware task selection & round-robin verified.$FG$\n");

  // Test 4: Affinity configuration
  if (TaskSetAffinity(2, 0x01) != 0 || t2->affinity_mask != 0x01) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: TaskSetAffinity failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Core affinity mask assignment verified.$FG$\n");

  // Test 5: Deferred zombie staging in TaskExit() & reaping on next TaskYield()
  TaskExit(); // Exit current task (WorkerA) -> staged in g_sched_zombie
  if (SchedCountTasks() != 2 || g_sched_zombie == 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5A: TaskExit failed to stage g_sched_zombie!$FG$\n");
    return 0;
  }
  TaskYield(); // Reaps g_sched_zombie safely!
  if (g_sched_zombie != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 5B: TaskYield failed to reap g_sched_zombie!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Deferred zombie staging (TaskExit) & reaping (TaskYield) validated.$FG$\n");

  SchedPrintDolDoc();
  doldoc_printf("\n[SCHED-PASS] ALL 5 SCHEDULER TESTS PASSED\n\n");
  SchedInit();
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
