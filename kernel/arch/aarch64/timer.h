#ifndef NEO_TIMER_H
#define NEO_TIMER_H

#include <uefi.h>

void     timer_init(uint32_t frequency_hz);
uint64_t timer_get_ticks(void);
uint64_t timer_get_frequency(void);
uint64_t timer_get_uptime_us(void);
uint64_t timer_get_uptime_sec(void);
void     timer_sleep_ms(uint64_t ms);

#endif // NEO_TIMER_H
