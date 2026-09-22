#ifndef NEO_TASK_H
#define NEO_TASK_H

#include <uefi.h>

typedef enum {
    TASK_READY = 0,
    TASK_RUNNING,
    TASK_SLEEPING,
    TASK_DEAD
} task_state_t;

typedef struct {
    uint64_t x19;
    uint64_t x20;
    uint64_t x21;
    uint64_t x22;
    uint64_t x23;
    uint64_t x24;
    uint64_t x25;
    uint64_t x26;
    uint64_t x27;
    uint64_t x28;
    uint64_t x29; // Frame Pointer
    uint64_t x30; // Link Register (Return PC)
    uint64_t sp;  // Stack Pointer

    // Callee-saved NEON/FP registers (D8-D15)
    uint64_t d8;
    uint64_t d9;
    uint64_t d10;
    uint64_t d11;
    uint64_t d12;
    uint64_t d13;
    uint64_t d14;
    uint64_t d15;
} __attribute__((aligned(16))) cpu_context_t;

typedef struct task {
    uint64_t      id;
    char          name[32];
    task_state_t  state;
    uint32_t      priority;
    uint64_t      wake_tick;
    void          (*entry)(void *arg);
    void          *arg;
    uint8_t       *stack_base;
    uint64_t      stack_size;
    cpu_context_t context;
    struct task   *next;
    struct task   *prev;
} task_t;

// Context switch in pure assembly:
extern void cpu_switch_context(cpu_context_t *prev, cpu_context_t *next);

#endif // NEO_TASK_H
