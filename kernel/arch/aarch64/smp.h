#ifndef NEO_SMP_H
#define NEO_SMP_H

#include <uefi.h>

#define SMP_MAX_CORES 4

typedef struct {
    volatile uint32_t lock;
} spinlock_t;

typedef void (*smp_task_fn)(void *arg);

typedef struct {
    smp_task_fn  fn;
    void        *arg;
    volatile int pending;
    volatile int completed;
} smp_core_job_t;

typedef struct {
    uint32_t        num_cores;
    uint32_t        online_cores;
    volatile uint32_t core_online[SMP_MAX_CORES];
    volatile uint64_t core_heartbeat[SMP_MAX_CORES];
    smp_core_job_t  jobs[SMP_MAX_CORES];
    spinlock_t      lock;
} smp_state_t;

typedef struct {
    uint64_t sctlr;
    uint64_t tcr;
    uint64_t mair;
    uint64_t ttbr0;
    uint64_t vbar;
} mmu_config_t;

extern mmu_config_t g_mmu_config;
extern smp_state_t  g_smp;

void smp_init(void);
uint32_t smp_get_core_count(void);
uint32_t smp_get_current_core(void);
int  smp_dispatch(uint32_t core_id, smp_task_fn fn, void *arg);
int  smp_is_job_done(uint32_t core_id);
void smp_spin_lock(spinlock_t *l);
void smp_spin_unlock(spinlock_t *l);
void smp_print_doldoc(void);

#endif // NEO_SMP_H
