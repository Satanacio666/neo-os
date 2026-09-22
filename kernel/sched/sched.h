#ifndef NEO_SCHED_H
#define NEO_SCHED_H

#include "task.h"

typedef void (*task_entry_t)(void *arg);

void    sched_init(void);
task_t* task_create(const char *name, task_entry_t entry, void *arg, size_t stack_size);
void    task_yield(void);
void    task_exit(void);
void    sched_tick(uint64_t ticks);
task_t* sched_get_current(void);
void    sched_dump(void);
void    sched_print_doldoc(void);
void    top_print_doldoc(void);

#endif // NEO_SCHED_H
