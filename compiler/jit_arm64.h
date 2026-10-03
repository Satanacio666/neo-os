#ifndef NEO_JIT_ARM64_H
#define NEO_JIT_ARM64_H

#include <uefi.h>

typedef int64_t (*jit_func_t)(void);

void    jit_init(void);
int64_t jit_eval(const char *expr_source);
int64_t jit_execute_statement(const char *code);
int64_t jit_compile_and_run(const char *source);
int     jit_run_self_tests(void);
int     jit_is_in_code_pool(const void *ptr);

#endif // NEO_JIT_ARM64_H
