#ifndef NEO_JIT_ARM64_H
#define NEO_JIT_ARM64_H

#include <uefi.h>

typedef int64_t (*jit_func_t)(void);

void    jit_init(void);
void    jit_init_code_pool(void *pool_start, size_t pool_size);
int64_t jit_eval(const char *expr_source);
int64_t jit_compile_and_run(const char *source);
// ENXUTO (31/10): jit_execute_statement, jit_run_self_tests, jit_is_in_code_pool
// removidos — dead code (0 chamadores, so a definicao). O seed so' compila o
// Compiler.HC; nada disso era necessario.

#endif // NEO_JIT_ARM64_H
