#include "timer.h"
#include "gic.h"
#include "../../sched/sched.h"

static uint64_t timer_frequency = 0;
static uint64_t timer_interval = 0;
static volatile uint64_t system_ticks = 0;

static void timer_irq_handler(uint32_t irq, void *data) {
    (void)irq;
    (void)data;

    // 1. Reload the countdown register for the next periodic tick
    asm volatile("msr cntv_tval_el0, %0" : : "r"(timer_interval));

    // 2. Increment monotonically increasing system ticks
    system_ticks++;

    // 3. Notify the preemptive scheduler
    sched_tick(system_ticks);
}

void timer_init(uint32_t frequency_hz) {
    if (frequency_hz == 0) frequency_hz = 100; // Default 100 Hz (10ms tick)

    // 1. Read the constant hardware clock frequency from CPU
    asm volatile("mrs %0, cntfrq_el0" : "=r"(timer_frequency));

    timer_interval = timer_frequency / frequency_hz;
    system_ticks = 0;

    // 2. Register handler on GIC for Virtual Timer (IRQ #27)
    gic_register_handler(IRQ_VIRT_TIMER, timer_irq_handler, NULL);
    gic_set_priority(IRQ_VIRT_TIMER, 0x10); // High priority for timer

    // 3. Arm the Virtual Timer countdown
    asm volatile("msr cntv_tval_el0, %0" : : "r"(timer_interval));

    // 4. Enable the timer (bit 0 = 1: enable, bit 1 = 0: unmask interrupt)
    asm volatile("msr cntv_ctl_el0, %0" : : "r"(1ULL));

    printf("[TIMER] ARM Generic Timer armed @ %u Hz (Freq: %llu MHz, Interval: %llu ticks)\n",
           frequency_hz,
           (unsigned long long)(timer_frequency / 1000000),
           (unsigned long long)timer_interval);
}

uint64_t timer_get_ticks(void) {
    return system_ticks;
}

uint64_t timer_get_frequency(void) {
    return timer_frequency;
}

uint64_t timer_get_uptime_us(void) {
    uint64_t val = 0;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    uint64_t freq = timer_frequency;
    if (freq == 0) {
        asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));
        if (freq == 0) freq = 62500000ULL;
    }
    return (val / freq) * 1000000ULL + ((val % freq) * 1000000ULL) / freq;
}

uint64_t timer_get_uptime_sec(void) {
    uint64_t val = 0;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    uint64_t freq = timer_frequency;
    if (freq == 0) {
        asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));
        if (freq == 0) freq = 62500000ULL;
    }
    return val / freq;
}

void timer_sleep_ms(uint64_t ms) {
    uint64_t freq = timer_frequency;
    if (freq == 0) {
        asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));
        if (freq == 0) freq = 62500000ULL;
    }
    uint64_t start = 0;
    asm volatile("mrs %0, cntvct_el0" : "=r"(start));
    uint64_t target = start + (ms * freq) / 1000ULL;
    while (1) {
        uint64_t cur = 0;
        asm volatile("mrs %0, cntvct_el0" : "=r"(cur));
        if (cur >= target) break;
        task_yield();
    }
}

