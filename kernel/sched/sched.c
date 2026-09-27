#include "sched.h"
#include "../mem/kheap.h"
#include "../../gui/render.h"
#include "../arch/aarch64/smp.h"
#include "../arch/aarch64/timer.h"
#include <uefi.h>

static task_t *current_task = NULL;
static task_t *task_head = NULL;
static uint64_t next_task_id = 1;
static task_t *s_zombie_task = NULL;

static void task_entry_wrapper(void) {
    if (current_task && current_task->entry) {
        current_task->entry(current_task->arg);
    }
    task_exit();
}

void sched_init(void) {
    // Create the Main / Kernel task representing the current execution thread
    task_t *main_task = (task_t*)kmalloc(sizeof(task_t));
    if (!main_task) {
        printf("[SCHED] FATAL: Failed to allocate main task!\n");
        return;
    }

    memset(main_task, 0, sizeof(task_t));
    main_task->id = next_task_id++;
    strncpy(main_task->name, "KernelMain", sizeof(main_task->name) - 1);
    main_task->state = TASK_RUNNING;
    main_task->priority = PRIO_REALTIME;
    main_task->stack_base = NULL; // Uses UEFI/current stack
    main_task->stack_size = 0;
    main_task->quantum_ticks = 5;
    main_task->quantum_remaining = 5;
    main_task->affinity_mask = 0x0F;
    main_task->next = main_task;
    main_task->prev = main_task;

    current_task = main_task;
    task_head = main_task;

    printf("[SCHED] Round-Robin Scheduler initialized (Main Task ID #%llu)\n", (unsigned long long)main_task->id);
}

task_t* task_create(const char *name, task_entry_t entry, void *arg, size_t stack_size) {
    if (!entry) return NULL;
    if (stack_size < 65536) stack_size = 65536; // 64KB stack for full C runtime & printf safety

    task_t *task = (task_t*)kmalloc(sizeof(task_t));
    if (!task) return NULL;

    uint8_t *stack = (uint8_t*)kmalloc(stack_size);
    if (!stack) {
        kfree(task);
        return NULL;
    }

    memset(task, 0, sizeof(task_t));
    task->id = next_task_id++;
    strncpy(task->name, name ? name : "task", sizeof(task->name) - 1);
    task->state = TASK_READY;
    task->priority = PRIO_INTERACTIVE;
    task->entry = entry;
    task->arg = arg;
    task->stack_base = stack;
    task->stack_size = stack_size;
    task->quantum_ticks = 5;
    task->quantum_remaining = 5;
    task->affinity_mask = 0x0F;

    // Align stack pointer to 16 bytes at the top of stack (stacks grow downwards in AArch64)
    uintptr_t sp_top = ((uintptr_t)stack + stack_size - 16) & ~15;
    task->context.sp = sp_top;
    task->context.x29 = sp_top; // Frame pointer
    task->context.x30 = (uint64_t)task_entry_wrapper; // Return address for cpu_switch_context

    // Add to circular doubly-linked task queue
    task->next = task_head;
    task->prev = task_head->prev;
    task_head->prev->next = task;
    task_head->prev = task;

    printf("[SCHED] Task created: ID #%llu '%s' (Entry: 0x%016llX, SP: 0x%016llX)\n",
           (unsigned long long)task->id, task->name, (unsigned long long)entry, (unsigned long long)sp_top);

    return task;
}

void task_yield(void) {
    if (!current_task || !current_task->next) return;

    // Clean up any previously exited zombie task now that execution is on a valid stack
    if (s_zombie_task) {
        if (s_zombie_task->stack_base) {
            kfree(s_zombie_task->stack_base);
            s_zombie_task->stack_base = NULL;
        }
        kfree(s_zombie_task);
        s_zombie_task = NULL;
    }

    task_t *prev = current_task;
    task_t *best = NULL;
    uint32_t best_prio = 0;

    // Priority-aware task selection: pick highest-priority TASK_READY task
    task_t *curr = current_task->next;
    while (curr != current_task) {
        if (curr->state == TASK_READY) {
            if (!best || curr->priority > best_prio) {
                best = curr;
                best_prio = curr->priority;
            }
        }
        curr = curr->next;
    }

    if (!best || best->state != TASK_READY) {
        return; // No other ready task to switch to
    }

    task_t *next = best;
    if (prev->state == TASK_RUNNING) {
        prev->state = TASK_READY;
    }
    next->state = TASK_RUNNING;
    current_task = next;

    // Reset quantum for freshly scheduled task
    current_task->quantum_remaining = current_task->quantum_ticks ? current_task->quantum_ticks : 5;

    // Fast assembly context switch (20 nanoseconds!)
    cpu_switch_context(&prev->context, &next->context);
}

void task_exit(void) {
    if (!current_task) return;

    printf("[SCHED] Task ID #%llu '%s' finished.\n",
           (unsigned long long)current_task->id, current_task->name);

    task_t *dying_task = current_task;
    dying_task->state = TASK_DEAD;

    // Remove from linked list if not only task
    if (dying_task->next != dying_task) {
        dying_task->prev->next = dying_task->next;
        dying_task->next->prev = dying_task->prev;
        if (task_head == dying_task) {
            task_head = dying_task->next;
        }
    }

    s_zombie_task = dying_task;

    // Yield to next ready task
    task_yield();

    // If we reach here, no other tasks exist
    while (1) {
        asm volatile("wfi"); // Wait For Interrupt
    }
}

task_t* sched_get_current(void) {
    return current_task;
}

void sched_tick(uint64_t ticks) {
    (void)ticks;
    if (!current_task) return;

    // Real-Time tasks (Render loop, compositor, physics) have preemption immunity mid-frame!
    // They yield cooperatively via task_yield() at frame/vsync boundaries.
    if (current_task->priority >= PRIO_REALTIME) {
        return;
    }

    if (current_task->quantum_remaining > 0) {
        current_task->quantum_remaining--;
    }

    if (current_task->quantum_remaining == 0) {
        current_task->quantum_remaining = current_task->quantum_ticks ? current_task->quantum_ticks : 5;
        // Check if another task is ready to run
        if (current_task->next && current_task->next != current_task) {
            task_t *t = current_task->next;
            while (t != current_task) {
                if (t->state == TASK_READY) {
                    task_yield();
                    break;
                }
                t = t->next;
            }
        }
    }
}

void sched_dump(void) {
    printf("\n--- SCHEDULER TASK LIST ---\n");
    if (!task_head) {
        printf(" No tasks running.\n");
        return;
    }

    task_t *curr = task_head;
    do {
        const char *state_str = (curr->state == TASK_RUNNING) ? "RUNNING" :
                                (curr->state == TASK_READY)   ? "READY  " :
                                (curr->state == TASK_SLEEPING)? "SLEEP  " : "DEAD   ";
        printf(" [ID #%llu] %s | %s | SP: 0x%016llX\n",
               (unsigned long long)curr->id, curr->name, state_str, (unsigned long long)curr->context.sp);
        curr = curr->next;
    } while (curr != task_head);
    printf("---------------------------\n\n");
}

void sched_print_doldoc(void) {
    doldoc_print("$FG,CYAN$--- ACTIVE SCHEDULER TASKS ---$FG$\n");
    if (!task_head) {
        doldoc_print(" No tasks running.\n");
        return;
    }

    task_t *curr = task_head;
    do {
        const char *state_str = (curr->state == TASK_RUNNING) ? "RUNNING" :
                                (curr->state == TASK_READY)   ? "READY  " :
                                (curr->state == TASK_SLEEPING)? "SLEEP  " : "DEAD   ";
        doldoc_printf(" [ID #%llu] $FG,YELLOW$%s$FG$ | %s | SP: 0x%016llX\n",
                      (unsigned long long)curr->id, curr->name, state_str, (unsigned long long)curr->context.sp);
        curr = curr->next;
    } while (curr != task_head);
    doldoc_print("$FG,CYAN$--------------------------------$FG$\n");
}

void top_print_doldoc(void) {
    heap_stats_t hstats;
    kheap_get_stats(&hstats);

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$ NeoOS Top 2.0 - SMP Multiprocessing & System Telemetry $FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    uint64_t heap_pct = (hstats.total_memory > 0) ? ((hstats.used_memory * 100ULL) / hstats.total_memory) : 0;
    doldoc_printf(" Topology: %u Cores (%u Online) | Ticks: %llu | RAM: %llu MB\n",
                  g_smp.num_cores, g_smp.online_cores,
                  (unsigned long long)timer_get_ticks(),
                  (unsigned long long)(hstats.total_memory / (1024 * 1024)));
    doldoc_printf(" Heap: %llu KB used / %llu MB total ($PB,VAL=%llu,MAX=100$ %llu%%)\n\n",
                  (unsigned long long)(hstats.used_memory / 1024),
                  (unsigned long long)(hstats.total_memory / (1024 * 1024)),
                  (unsigned long long)heap_pct, (unsigned long long)heap_pct);

    doldoc_print(" $FG,YELLOW$ARMv8 Cortex-A72 SMP Cores Status:$FG$\n");
    for (uint32_t i = 0; i < g_smp.num_cores && i < SMP_MAX_CORES; i++) {
        const char *state = g_smp.core_online[i] ? "$FG,GREEN$ONLINE$FG$" : "$FG,RED$OFFLINE$FG$";
        const char *role = (i == 0) ? "(BSP / Compositor)" : "(SMP Worker Core)";
        uint64_t hb = g_smp.core_heartbeat[i];
        doldoc_printf("  Core #%u %s: %s | Heartbeats: %llu\n",
                      i, role, state, (unsigned long long)hb);
    }

    doldoc_print("\n $FG,YELLOW$Active Ring 0 Scheduler Tasks & Core Affinity:$FG$\n");
    if (task_head) {
        task_t *curr = task_head;
        do {
            const char *st = (curr->state == TASK_RUNNING) ? "RUNNING" :
                             (curr->state == TASK_READY)   ? "READY" :
                             (curr->state == TASK_SLEEPING)? "SLEEP" : "DEAD";
            doldoc_printf("  [PID %llu] %-14s | %-7s | Aff: 0x%02X | $BT,\"C0\",LM=\"affinity %llu 0\"$ $BT,\"C1\",LM=\"affinity %llu 1\"$ $BT,\"SMP\",LM=\"affinity %llu -1\"$\n",
                          (unsigned long long)curr->id, curr->name, st, curr->affinity_mask,
                          (unsigned long long)curr->id, (unsigned long long)curr->id, (unsigned long long)curr->id);
            curr = curr->next;
        } while (curr != task_head);
    }
    doldoc_print("\n Actions: $BT,\"Refresh\",LM=\"top\"$ $BT,\"Tasks\",LM=\"tasks\"$ $BT,\"Mem\",LM=\"mem\"$ $BT,\"SMP\",LM=\"smp\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
}

int task_set_affinity(uint64_t task_id, uint32_t mask) {
    if (!task_head) return -1;
    task_t *curr = task_head;
    do {
        if (curr->id == task_id) {
            curr->affinity_mask = mask;
            printf("[SCHED] Task PID %llu '%s' affinity mask updated to 0x%02X\n",
                   (unsigned long long)task_id, curr->name, mask);
            return 0;
        }
        curr = curr->next;
    } while (curr != task_head);
    return -1;
}


