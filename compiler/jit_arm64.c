#include "jit_arm64.h"
#include "lexer.h"
#include "table.h"
#include "../kernel/mem/kheap.h"
#include "../kernel/symbols/symbols.h"
extern void doldoc_print(const char *str);
extern void doldoc_printf(const char *fmt, ...);
#include <uefi.h>

typedef struct {
    uint32_t *code;
    size_t   capacity;
    size_t   count;
    int      has_error;
    char     error_msg[128];
} code_buffer_t;


static void arm64_flush_cache(void *addr, size_t size) {
    if (!addr || size == 0) return;
    uintptr_t start = (uintptr_t)addr;
    uintptr_t end = start + size;
    for (uintptr_t p = start & ~63ULL; p < end; p += 64) {
        asm volatile("dc cvau, %0" :: "r"(p) : "memory");
    }
    asm volatile("dsb ish" ::: "memory");
    for (uintptr_t p = start & ~63ULL; p < end; p += 64) {
        asm volatile("ic ivau, %0" :: "r"(p) : "memory");
    }
    asm volatile("dsb ish; isb" ::: "memory");
}

static uint8_t  *s_jit_pool_start = NULL;
static size_t    s_jit_pool_offset = 0;
static size_t    s_jit_pool_size = 0;
static uint32_t *s_jit_scratch_code = NULL;
static const size_t JIT_SCRATCH_BYTES = 64 * 1024;
static const size_t JIT_SCRATCH_INSTRS = 16384;

void jit_init_code_pool(void *pool_start, size_t pool_size) {
    if (!pool_start || pool_size <= JIT_SCRATCH_BYTES) {
        s_jit_pool_start = (uint8_t*)pool_start;
        s_jit_pool_size = pool_size;
        s_jit_pool_offset = 0;
        s_jit_scratch_code = NULL;
        return;
    }
    s_jit_scratch_code = (uint32_t*)pool_start;
    s_jit_pool_start = (uint8_t*)pool_start + JIT_SCRATCH_BYTES;
    s_jit_pool_size = pool_size - JIT_SCRATCH_BYTES;
    s_jit_pool_offset = 0;
    printf("[NEOC JIT] Dedicated Executable Code Pool: Scratch 64KB @ 0x%016llX | Persistent Pool %llu KB @ 0x%016llX\n",
           (unsigned long long)s_jit_scratch_code,
           (unsigned long long)(s_jit_pool_size / 1024),
           (unsigned long long)s_jit_pool_start);
}

static inline int is_in_jit_pool(const void *ptr) {
    if (!ptr) return 0;
    if (s_jit_scratch_code && (const uint32_t*)ptr == s_jit_scratch_code) return 1;
    if (s_jit_pool_start && 
        (const uint8_t*)ptr >= s_jit_pool_start && 
        (const uint8_t*)ptr < (s_jit_pool_start + s_jit_pool_size)) {
        return 1;
    }
    return 0;
}

int jit_is_in_code_pool(const void *ptr) {
    return is_in_jit_pool(ptr);
}

static int s_jit_scratch_in_use = 0;

static void cb_release(code_buffer_t *cb) {
    if (!cb || !cb->code) return;
    if (cb->code == s_jit_scratch_code) {
        s_jit_scratch_in_use = 0;
    } else if (!is_in_jit_pool(cb->code)) {
        kfree(cb->code);
    }
    cb->code = NULL;
    cb->count = 0;
    cb->capacity = 0;
}

static void cb_init_scratch(code_buffer_t *cb, size_t max_instructions) {
    cb->capacity = max_instructions;
    cb->count = 0;
    cb->has_error = 0;
    cb->error_msg[0] = '\0';
    if (!s_jit_scratch_in_use && s_jit_scratch_code && max_instructions <= JIT_SCRATCH_INSTRS) {
        s_jit_scratch_in_use = 1;
        cb->code = s_jit_scratch_code;
        cb->capacity = JIT_SCRATCH_INSTRS;
    } else {
        size_t bytes = max_instructions * sizeof(uint32_t);
        if (s_jit_pool_start && (s_jit_pool_offset + bytes <= s_jit_pool_size)) {
            cb->code = (uint32_t*)(s_jit_pool_start + s_jit_pool_offset);
            s_jit_pool_offset += (bytes + 63) & ~63ULL;
        } else {
            cb->code = (uint32_t*)kmalloc(bytes);
            if (!cb->code) {
                cb->has_error = 1;
                snprintf(cb->error_msg, sizeof(cb->error_msg), "Out of memory allocating scratch buffer");
            }
        }
    }
}

static void cb_init_persistent(code_buffer_t *cb, size_t max_instructions) {
    cb->capacity = max_instructions;
    cb->count = 0;
    cb->has_error = 0;
    cb->error_msg[0] = '\0';
    size_t bytes = max_instructions * sizeof(uint32_t);
    if (s_jit_pool_start && (s_jit_pool_offset + bytes <= s_jit_pool_size)) {
        cb->code = (uint32_t*)(s_jit_pool_start + s_jit_pool_offset);
    } else {
        cb->code = (uint32_t*)kmalloc(bytes);
        if (!cb->code) {
            cb->has_error = 1;
            snprintf(cb->error_msg, sizeof(cb->error_msg), "Out of memory allocating persistent code buffer");
        }
    }
}

static void cb_commit_persistent(code_buffer_t *cb) {
    if (!cb || cb->has_error || !cb->code) return;
    if (is_in_jit_pool(cb->code) && cb->code != s_jit_scratch_code) {
        size_t actual_bytes = (cb->count * sizeof(uint32_t) + 63) & ~63ULL;
        s_jit_pool_offset += actual_bytes;
    }
}

static void jit_syntax_error(lexer_t *l, code_buffer_t *cb, const char *fmt, ...) {
    char buf[256];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    if (cb) cb->has_error = 1;
    int line = l ? l->current.line : 0;
    int col = l ? l->current.col : 0;
    if (cb) snprintf(cb->error_msg, sizeof(cb->error_msg), "[Line %d, Col %d] %s", line, col, buf);

    // 1. Direct hardware UART output (always visible on serial/fifo)
    printf("\n[JIT SYNTAX ERROR] [Line %d, Col %d] %s\n", line, col, buf);

    // Find and print source snippet
    if (l && l->src) {
        int cur_line = 1;
        const char *p = l->src;
        const char *line_start = p;
        while (*p && cur_line < line) {
            if (*p == '\n') {
                cur_line++;
                line_start = p + 1;
            }
            p++;
        }
        const char *line_end = line_start;
        while (*line_end && *line_end != '\n' && *line_end != '\r') line_end++;

        char line_snippet[128];
        size_t slen = (size_t)(line_end - line_start);
        if (slen > sizeof(line_snippet) - 1) slen = sizeof(line_snippet) - 1;
        memcpy(line_snippet, line_start, slen);
        line_snippet[slen] = '\0';

        printf("  %4d | %s\n", line, line_snippet);
        printf("       | ");
        for (int c = 1; c < col && c < 60; c++) printf(" ");
        printf("^\n");

        // 2. DolDoc GUI console output (visible in terminal window)
        doldoc_printf("$FG,RED$[JIT SYNTAX ERROR]$FG$ [Line %d, Col %d] %s\n", line, col, buf);
        doldoc_printf("$FG,YELLOW$  %4d |$FG$ %s\n", line, line_snippet);
    }
}

static void emit_u32(code_buffer_t *cb, uint32_t instruction) {
    if (cb->has_error) return;
    if (cb->code && cb->count < cb->capacity) {
        cb->code[cb->count++] = instruction;
    } else {
        cb->has_error = 1;
        snprintf(cb->error_msg, sizeof(cb->error_msg), "Code buffer capacity exceeded (%d instructions)", (int)cb->capacity);
        printf("[JIT] Error: %s\n", cb->error_msg);
    }
}

// Emits 64-bit constant load into register Xd (0-30) using MOVZ and MOVK
static void emit_mov_imm64(code_buffer_t *cb, uint32_t rd, uint64_t val) {
    uint16_t imm0 = (val >> 0)  & 0xFFFF;
    uint16_t imm1 = (val >> 16) & 0xFFFF;
    uint16_t imm2 = (val >> 32) & 0xFFFF;
    uint16_t imm3 = (val >> 48) & 0xFFFF;

    // MOVZ Xd, #imm0, LSL #0
    emit_u32(cb, 0xD2800000 | (0 << 21) | ((uint32_t)imm0 << 5) | rd);

    if (imm1) {
        // MOVK Xd, #imm1, LSL #16
        emit_u32(cb, 0xF2800000 | (1 << 21) | ((uint32_t)imm1 << 5) | rd);
    }
    if (imm2) {
        // MOVK Xd, #imm2, LSL #32
        emit_u32(cb, 0xF2800000 | (2 << 21) | ((uint32_t)imm2 << 5) | rd);
    }
    if (imm3) {
        // MOVK Xd, #imm3, LSL #48
        emit_u32(cb, 0xF2800000 | (3 << 21) | ((uint32_t)imm3 << 5) | rd);
    }
}

// Basic AArch64 Opcodes
static void emit_mov_reg(code_buffer_t *cb, uint32_t rd, uint32_t rm) {
    // ORR Xd, XZR, Xm (MOV Xd, Xm)
    emit_u32(cb, 0xAA0003E0 | (rm << 16) | rd);
}

static void emit_add(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x8B000000 | (rm << 16) | (rn << 5) | rd);
}

static void emit_sub(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0xCB000000 | (rm << 16) | (rn << 5) | rd);
}

static void emit_mul(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x9B007C00 | (rm << 16) | (rn << 5) | rd);
}

static void emit_sdiv(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x9AC00C00 | (rm << 16) | (rn << 5) | rd);
}

// Remainder: Xd = Xn % Xm (via SDIV X2, Xn, Xm; MSUB Xd, X2, Xm, Xn)
static void emit_srem(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_sdiv(cb, 2, rn, rm); // X2 = Xn / Xm
    emit_u32(cb, 0x9B008000 | (rm << 16) | (rn << 10) | (2 << 5) | rd);
}

static void emit_cmp(code_buffer_t *cb, uint32_t rn, uint32_t rm) {
    // SUBS XZR, Xn, Xm
    emit_u32(cb, 0xEB00001F | (rm << 16) | (rn << 5));
}

// CSET Xd, cond: CSINC Xd, XZR, XZR, inv_cond
static void emit_cset(code_buffer_t *cb, uint32_t rd, uint32_t inv_cond) {
    emit_u32(cb, 0x9A9F07E0 | (inv_cond << 12) | rd);
}

static void emit_ldr_ptr(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // LDR Xd, [Xn]
    emit_u32(cb, 0xF9400000 | (rn << 5) | rd);
}

static void emit_str_ptr(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // STR Xd, [Xn]
    emit_u32(cb, 0xF9000000 | (rn << 5) | rd);
}

static inline void emit_ldr64(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_ldr_ptr(cb, rd, rn);
}

static inline void emit_str64(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_str_ptr(cb, rd, rn);
}

static void emit_ldrb(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // LDRB Wd, [Xn]
    emit_u32(cb, 0x39400000 | (rn << 5) | rd);
}

static void emit_strb(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // STRB Wd, [Xn]
    emit_u32(cb, 0x39000000 | (rn << 5) | rd);
}

static void emit_ldrh(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // LDRH Wd, [Xn]
    emit_u32(cb, 0x79400000 | (rn << 5) | rd);
}

static void emit_strh(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // STRH Wd, [Xn]
    emit_u32(cb, 0x79000000 | (rn << 5) | rd);
}

static void emit_ldr32(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // LDR Wd, [Xn] (zero-extending 32-bit load into Xd)
    emit_u32(cb, 0xB9400000 | (rn << 5) | rd);
}

static void emit_str32(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // STR Wd, [Xn]
    emit_u32(cb, 0xB9000000 | (rn << 5) | rd);
}

// Bitwise Logic & Shifts
static void emit_and(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x8A000000 | (rm << 16) | (rn << 5) | rd);
}

static void emit_orr(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0xAA000000 | (rm << 16) | (rn << 5) | rd);
}

static void emit_eor(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0xCA000000 | (rm << 16) | (rn << 5) | rd);
}

static void emit_lsl(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x9AC02000 | (rm << 16) | (rn << 5) | rd);
}

static void emit_lsr(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x9AC02400 | (rm << 16) | (rn << 5) | rd);
}

static void emit_asr(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x9AC02800 | (rm << 16) | (rn << 5) | rd);
}

static void emit_neg(code_buffer_t *cb, uint32_t rd, uint32_t rm) {
    // SUB Xd, XZR, Xm
    emit_u32(cb, 0xCB0003E0 | (rm << 16) | rd);
}

static void emit_mvn(code_buffer_t *cb, uint32_t rd, uint32_t rm) {
    // ORN Xd, XZR, Xm
    emit_u32(cb, 0xAA2003E0 | (rm << 16) | rd);
}

static inline int is_compound_assign_tok(token_type_t t) {
    return (t == TOK_PLUSEQ || t == TOK_MINUSEQ || t == TOK_STAREQ ||
            t == TOK_SLASHEQ || t == TOK_PERCENTEQ || t == TOK_ANDEQ ||
            t == TOK_PIPEEQ || t == TOK_CARETEQ || t == TOK_SHLEQ || t == TOK_SHREQ);
}

static void emit_compound_op(code_buffer_t *cb, token_type_t op_type) {
    if (op_type == TOK_PLUSEQ)        emit_add(cb, 0, 1, 0);
    else if (op_type == TOK_MINUSEQ)   emit_sub(cb, 0, 1, 0);
    else if (op_type == TOK_STAREQ)    emit_mul(cb, 0, 1, 0);
    else if (op_type == TOK_SLASHEQ)   emit_sdiv(cb, 0, 1, 0);
    else if (op_type == TOK_PERCENTEQ) emit_srem(cb, 0, 1, 0);
    else if (op_type == TOK_ANDEQ)     emit_and(cb, 0, 1, 0);
    else if (op_type == TOK_PIPEEQ)    emit_orr(cb, 0, 1, 0);
    else if (op_type == TOK_CARETEQ)   emit_eor(cb, 0, 1, 0);
    else if (op_type == TOK_SHLEQ)     emit_lsl(cb, 0, 1, 0);
    else if (op_type == TOK_SHREQ)     emit_asr(cb, 0, 1, 0);
}

// Float NEON / VFP (Double Precision D0-D31)
static void emit_fadd(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x1E602800 | (rm << 16) | (rn << 5) | rd);
}

static void emit_fsub(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x1E603800 | (rm << 16) | (rn << 5) | rd);
}

static void emit_fmul(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x1E600800 | (rm << 16) | (rn << 5) | rd);
}

static void emit_fdiv(code_buffer_t *cb, uint32_t rd, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x1E601800 | (rm << 16) | (rn << 5) | rd);
}

static void emit_fcmp(code_buffer_t *cb, uint32_t rn, uint32_t rm) {
    emit_u32(cb, 0x1E602000 | (rm << 16) | (rn << 5));
}

static void emit_fneg(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_u32(cb, 0x1E614000 | (rn << 5) | rd);
}

static void emit_scvtf(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_u32(cb, 0x9E620000 | (rn << 5) | rd);
}

static void emit_fcvtzs(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_u32(cb, 0x9E780000 | (rn << 5) | rd);
}

static void emit_fmov_d_x(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_u32(cb, 0x9E670000 | (rn << 5) | rd);
}

static void emit_fcvt_s_d(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    // FCVT Sd, Dn: converts 64-bit double in Dn to 32-bit single-precision float in Sd
    emit_u32(cb, 0x1E624000 | (rn << 5) | rd);
}

static void emit_fmov_x_d(code_buffer_t *cb, uint32_t rd, uint32_t rn) {
    emit_u32(cb, 0x9E660000 | (rn << 5) | rd);
}

static void emit_push_x(code_buffer_t *cb, uint32_t rn) {
    // STR Xn, [SP, #-16]!
    emit_u32(cb, 0xF81F0FE0 | rn);
}

static void emit_pop_x(code_buffer_t *cb, uint32_t rd) {
    // LDR Xd, [SP], #16
    emit_u32(cb, 0xF84107E0 | rd);
}

static void emit_blr(code_buffer_t *cb, uint32_t rn) {
    emit_u32(cb, 0xD63F0000 | (rn << 5));
}

static void emit_ret(code_buffer_t *cb) {
    emit_u32(cb, 0xD65F03C0); // RET
}

static void emit_push_lr(code_buffer_t *cb) {
    // STP X29, X30, [SP, #-16]!
    emit_u32(cb, 0xA9BF7BFD);
    // MOV X29, SP  (establish frame pointer: locals live at [X29 - off])
    emit_u32(cb, 0x910003FD);
}

static void emit_pop_lr(code_buffer_t *cb) {
    // MOV SP, X29  (discard locals and any pending temporaries)
    emit_u32(cb, 0x910003BF);
    // LDP X29, X30, [SP], #16
    emit_u32(cb, 0xA8C17BFD);
}

// X(reg) = X29 - off   (address of a stack-frame local)
static void emit_frame_addr(code_buffer_t *cb, uint32_t reg, uint32_t off) {
    if (off < 4096) {
        emit_u32(cb, 0xD1000000 | (off << 10) | (29u << 5) | reg); // SUB Xreg, X29, #off
    } else {
        emit_mov_imm64(cb, 17, off);
        emit_sub(cb, reg, 29, 17);                                  // SUB Xreg, X29, X17
    }
}

// Conditional & Unconditional Branch Placeholders
static size_t emit_cbz_placeholder(code_buffer_t *cb, uint32_t rt) {
    size_t idx = cb->count;
    emit_u32(cb, 0xB4000000 | rt); // CBZ Xt, #0
    return idx;
}

static size_t emit_b_placeholder(code_buffer_t *cb) {
    size_t idx = cb->count;
    emit_u32(cb, 0x14000000); // B #0
    return idx;
}

static void patch_cbz(code_buffer_t *cb, size_t branch_idx, size_t target_idx) {
    int32_t offset = (int32_t)(target_idx - branch_idx);
    cb->code[branch_idx] |= ((offset & 0x7FFFF) << 5);
}

static void patch_b(code_buffer_t *cb, size_t branch_idx, size_t target_idx) {
    int32_t offset = (int32_t)(target_idx - branch_idx);
    cb->code[branch_idx] |= (offset & 0x03FFFFFF);
}

static void emit_b_cond(code_buffer_t *cb, uint32_t cond, size_t target_idx) {
    int32_t offset = (int32_t)(target_idx - cb->count);
    emit_u32(cb, 0x54000000 | ((offset & 0x7FFFF) << 5) | (cond & 0xF));
}

__attribute__((unused))
static size_t emit_b_cond_placeholder(code_buffer_t *cb, uint32_t cond) {
    size_t idx = cb->count;
    emit_u32(cb, 0x54000000 | (cond & 0xF));
    return idx;
}

__attribute__((unused))
static void patch_b_cond(code_buffer_t *cb, size_t branch_idx, size_t target_idx) {
    int32_t offset = (int32_t)(target_idx - branch_idx);
    cb->code[branch_idx] |= ((offset & 0x7FFFF) << 5);
}

static void emit_cbnz(code_buffer_t *cb, uint32_t rt, size_t target_idx) {
    int32_t offset = (int32_t)(target_idx - cb->count);
    emit_u32(cb, 0xB5000000 | ((offset & 0x7FFFF) << 5) | rt);
}

// Loop and Switch context stack for break/continue control flow
#define MAX_LOOP_DEPTH 16
#define MAX_BREAKS_PER_LOOP 64
#define MAX_CONTINUES_PER_LOOP 64

typedef struct {
    int is_switch; // 1 if switch, 0 if loop (while, for, do)
    size_t break_patches[MAX_BREAKS_PER_LOOP];
    int break_count;
    size_t continue_patches[MAX_CONTINUES_PER_LOOP];
    int continue_count;
} loop_ctx_t;

static loop_ctx_t loop_stack[MAX_LOOP_DEPTH];
static int loop_depth = 0;

// Switch/Case compilation context
#define MAX_CASES 64

typedef struct {
    int64_t value;
    size_t code_target;
} switch_case_entry_t;

typedef struct {
    uint64_t val_ref;   // variable reference (frame slot or global cell)
    int64_t *val_storage;
    switch_case_entry_t cases[MAX_CASES];
    int case_count;
    size_t default_target;
    int has_default;
} switch_ctx_t;

static switch_ctx_t *current_switch_ctx = NULL;

// Struct and Type Registry
typedef struct {
    char name[32];
    int offset;
    int size;
    int is_array;
    int is_ptr;
    int is_float;
    int elem_size;
    char type_name[32];
} struct_member_t;


#define MAX_STRUCT_DEFS 256
#define MAX_STRUCT_MEMBERS 64
#define MAX_VAR_TYPES 4096

typedef struct {
    char name[32];
    int total_size;
    int member_count;
    struct_member_t members[MAX_STRUCT_MEMBERS];
} struct_def_t;

static struct_def_t struct_defs[MAX_STRUCT_DEFS];
static int struct_def_count = 0;

static struct_def_t* find_struct_def(const char *name) {
    if (!name || !*name) return NULL;
    for (int i = 0; i < struct_def_count; i++) {
        if (strcmp(struct_defs[i].name, name) == 0) return &struct_defs[i];
    }
    return NULL;
}

typedef struct {
    char name[32];
    int scale;            // 1 (U8), 2 (U16), 4 (U32), 8 (I64 / pointer / default)
    int is_ptr;           // 1 if pointer, 0 if direct struct/value
    int is_float;         // 1 if floating point (F64, double, float)
    int is_array;         // 1 if an array (its name evaluates to its base address)
    char struct_type[32]; // Bound struct type if applicable
} var_type_t;

static var_type_t var_types[MAX_VAR_TYPES];
static int var_type_count = 0;
static int s_expr_is_float = 0;

// ─── Per-Function Stack Frames (re-entrant, SMP-safe locals) ────────────────
// Inside a function body every parameter and local lives in the hardware stack
// frame at [X29 - off]. A variable reference (var ref) is either an absolute
// global cell address or JIT_LOCAL_TAG | off. Kernel addresses are identity
// mapped below 4 GB, so the tag can never collide with a real address.
#define JIT_LOCAL_TAG   0xF0CA000000000000ULL
#define JIT_LOCAL_MASK  0xFFFF000000000000ULL
#define MAX_FN_LOCALS   512

typedef struct {
    char       name[64];
    uint32_t   off;      // slot address = X29 - off
    uint32_t   size;     // slot size in bytes (16-byte aligned)
    var_type_t vt;
} local_var_t;

typedef struct {
    local_var_t vars[MAX_FN_LOCALS];
    int         count;
    uint32_t    frame_size;
} fn_frame_t;

static fn_frame_t *s_frame = NULL;   // NULL at top level (globals)

static inline int ref_is_local(uint64_t ref) { return (ref & JIT_LOCAL_MASK) == JIT_LOCAL_TAG; }

static local_var_t *frame_find(const char *name) {
    if (!s_frame) return NULL;
    for (int i = s_frame->count - 1; i >= 0; i--) {
        if (strcmp(s_frame->vars[i].name, name) == 0) return &s_frame->vars[i];
    }
    return NULL;
}

// Allocates (or reuses, if big enough) a frame slot. Returns NULL when not in a function.
static local_var_t *frame_alloc(const char *name, uint32_t bytes) {
    if (!s_frame) return NULL;
    uint32_t sz = (bytes + 15u) & ~15u;
    if (sz < 16) sz = 16;
    if (name && name[0]) {
        local_var_t *ex = frame_find(name);
        if (ex && ex->size >= sz) return ex;
    }
    if (s_frame->count >= MAX_FN_LOCALS) {
        printf("[JIT] Error: too many locals in function (max %d)\n", MAX_FN_LOCALS);
        return NULL;
    }
    s_frame->frame_size += sz;
    local_var_t *lv = &s_frame->vars[s_frame->count++];
    memset(lv, 0, sizeof(*lv));
    if (name) strncpy(lv->name, name, sizeof(lv->name) - 1);
    strncpy(lv->vt.name, lv->name, sizeof(lv->vt.name) - 1);
    lv->vt.scale = 8;
    lv->off = s_frame->frame_size;
    lv->size = sz;
    return lv;
}

static inline uint64_t local_ref(local_var_t *lv) { return JIT_LOCAL_TAG | lv->off; }

static void register_var_type(const char *name, int scale, int is_ptr, int is_float, const char *st_name) {
    if (scale != 1 && scale != 2 && scale != 4 && scale != 8) {
        scale = 8; // Enforce natural alignment scale
    }
    local_var_t *lv = frame_find(name);
    if (lv) {
        lv->vt.scale = scale;
        lv->vt.is_ptr = is_ptr;
        lv->vt.is_float = is_float;
        if (st_name) strncpy(lv->vt.struct_type, st_name, 31);
        else lv->vt.struct_type[0] = '\0';
        return;
    }
    for (int i = 0; i < var_type_count; i++) {
        if (strcmp(var_types[i].name, name) == 0) {
            var_types[i].scale = scale;
            var_types[i].is_ptr = is_ptr;
            var_types[i].is_float = is_float;
            if (st_name) strncpy(var_types[i].struct_type, st_name, 31);
            else var_types[i].struct_type[0] = '\0';
            return;
        }
    }
    if (var_type_count < MAX_VAR_TYPES) {
        strncpy(var_types[var_type_count].name, name, 31);
        var_types[var_type_count].scale = scale;
        var_types[var_type_count].is_ptr = is_ptr;
        var_types[var_type_count].is_float = is_float;
        if (st_name) strncpy(var_types[var_type_count].struct_type, st_name, 31);
        else var_types[var_type_count].struct_type[0] = '\0';
        var_type_count++;
    } else {
        printf("[JIT] Warning: MAX_VAR_TYPES (%d) exceeded! Cannot register '%s'\n", MAX_VAR_TYPES, name);
    }
}

static var_type_t* lookup_var_type(const char *name) {
    local_var_t *lv = frame_find(name);
    if (lv) return &lv->vt;
    for (int i = 0; i < var_type_count; i++) {
        if (strcmp(var_types[i].name, name) == 0) return &var_types[i];
    }
    return NULL;
}

// Resolves a variable name: frame local first, then global SYM_VAR cell. 0 = not a variable.
static uint64_t lookup_var_ref(const char *name) {
    local_var_t *lv = frame_find(name);
    if (lv) return local_ref(lv);
    symbol_t *sym = symbols_lookup_entry(name);
    if (sym && sym->type == SYM_VAR && sym->address) return (uint64_t)sym->address;
    return 0;
}

// X(reg) = address of the variable's storage
static void emit_ref_addr(code_buffer_t *cb, uint32_t reg, uint64_t ref) {
    if (ref_is_local(ref)) emit_frame_addr(cb, reg, (uint32_t)(ref & 0xFFFFFFFFu));
    else emit_mov_imm64(cb, reg, ref);
}

// Zero `bytes` (multiple of 16) of a frame slot at runtime. Clobbers X16, X17.
static void emit_zero_slot(code_buffer_t *cb, local_var_t *lv) {
    emit_frame_addr(cb, 16, lv->off);
    if (lv->size == 16) {
        emit_u32(cb, 0xA9007E1F);                        // STP XZR, XZR, [X16]
        return;
    }
    emit_mov_imm64(cb, 17, lv->size / 16);
    size_t loop = cb->count;
    emit_u32(cb, 0xA8817E1F);                            // STP XZR, XZR, [X16], #16
    emit_u32(cb, 0xF1000631);                            // SUBS X17, X17, #1
    emit_b_cond(cb, 1, loop);                            // B.NE loop
}

// ─── AArch64 JIT Self-Optimization (Peephole Pass) ───────────────────────────
static int s_jit_total_opt_roundtrips = 0;
static int s_jit_total_opt_deadmoves   = 0;
static int s_jit_total_opt_deadadds    = 0;

static int insn_touches_reg_or_sp(uint32_t insn, uint32_t target_reg) {
    if (insn == 0xD503201F) return 0; // NOP is harmless

    // MOVZ / MOVK: immediate in [20:5], only Rd in [4:0] is a register
    if ((insn & 0x7F800000) == 0x52800000 || (insn & 0x7F800000) == 0x72800000) {
        uint32_t rd = insn & 0x1F;
        if (rd == target_reg) return 1;
        if (rd == 31) return 1; // Touches SP
        return 0;
    }

    // MOV reg (ORR Xd, XZR, Xm)
    if ((insn & 0xFFE0FFE0) == 0xAA0003E0) {
        uint32_t rd = insn & 0x1F;
        uint32_t rm = (insn >> 16) & 0x1F;
        if (rd == target_reg || rm == target_reg) return 1;
        if (rd == 31 || rm == 31) return 1;
        return 0;
    }

    // Single register load/store: [Xn]
    if ((insn & 0x0A000000) == 0x08000000 || (insn & 0x38000000) == 0x38000000) {
        uint32_t rt = insn & 0x1F;
        uint32_t rn = (insn >> 5) & 0x1F;
        if (rt == target_reg || rn == target_reg) return 1;
        if (rn == 31) return 1; // Base is SP
        return 0;
    }

    // Standard 3-register data processing
    uint32_t rd = insn & 0x1F;
    uint32_t rn = (insn >> 5) & 0x1F;
    uint32_t rm = (insn >> 16) & 0x1F;
    if (rd == target_reg || rn == target_reg || rm == target_reg) return 1;
    if (rn == 31) return 1;

    return 0;
}

static int can_collapse_stack_roundtrip(code_buffer_t *cb, size_t p, size_t q, uint32_t m_reg) {
    if (q <= p || (q - p) > 40) return 0;

    for (size_t k = p + 1; k < q; k++) {
        uint32_t insn = cb->code[k];
        if (insn == 0xD503201F) continue; // NOP is safe

        // Function calls, SVC, RET
        if ((insn & 0xFFFFFC1F) == 0xD63F0000) return 0; // BLR
        if ((insn & 0xFC000000) == 0x94000000) return 0; // BL
        if ((insn & 0xFFE0001F) == 0xD4000001) return 0; // SVC
        if (insn == 0xD65F03C0) return 0;                 // RET

        // Branches
        if ((insn & 0xFC000000) == 0x14000000) return 0; // B
        if ((insn & 0xFF000010) == 0x54000000) return 0; // B.cond
        if ((insn & 0x7E000000) == 0x34000000) return 0; // CBZ / CBNZ

        // Register or SP modification
        if (insn_touches_reg_or_sp(insn, m_reg)) return 0;
    }

    // Verify no branch jumps into (p, q]
    for (size_t b = 0; b < cb->count; b++) {
        uint32_t binsn = cb->code[b];
        int32_t target = -1;
        if ((binsn & 0xFC000000) == 0x14000000) { // B
            int32_t imm26 = binsn & 0x03FFFFFF;
            if (imm26 & 0x02000000) imm26 |= (int32_t)0xFC000000;
            target = (int32_t)b + imm26;
        } else if ((binsn & 0xFF000010) == 0x54000000) { // B.cond
            int32_t imm19 = (binsn >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= (int32_t)0xFFF80000;
            target = (int32_t)b + imm19;
        } else if ((binsn & 0x7E000000) == 0x34000000) { // CBZ/CBNZ
            int32_t imm19 = (binsn >> 5) & 0x7FFFF;
            if (imm19 & 0x40000) imm19 |= (int32_t)0xFFF80000;
            target = (int32_t)b + imm19;
        }
        if (target > (int32_t)p && target <= (int32_t)q) {
            return 0;
        }
    }

    return 1;
}

static void jit_optimize_peephole(code_buffer_t *cb) {
    if (!cb || cb->has_error || !cb->code || cb->count < 2) return;

    int roundtrips_in_pass = 0;
    int deadmoves_in_pass = 0;
    int deadadds_in_pass = 0;

    int changed = 1;
    int pass_iter = 0;
    while (changed && pass_iter < 4) {
        changed = 0;
        pass_iter++;

        // Pass 1: Collapse STR X0, [SP, #-16]! ... LDR X1, [SP], #16 into MOV X1, X0 ... NOP
        for (size_t p = 0; p < cb->count; p++) {
            if (cb->code[p] == 0xF81F0FE0) { // STR X0, [SP, #-16]!
                for (size_t q = p + 1; q < cb->count && (q - p) <= 40; q++) {
                    if (cb->code[q] == 0xF84107E1) { // LDR X1, [SP], #16
                        if (can_collapse_stack_roundtrip(cb, p, q, 1)) {
                            cb->code[p] = 0xAA0003E1; // MOV X1, X0
                            cb->code[q] = 0xD503201F; // NOP
                            roundtrips_in_pass++;
                            changed = 1;
                            p = q;
                            break;
                        }
                    } else if (cb->code[q] == 0xF84107E0) { // LDR X0, [SP], #16
                        if (can_collapse_stack_roundtrip(cb, p, q, 0)) {
                            cb->code[p] = 0xD503201F; // NOP
                            cb->code[q] = 0xD503201F; // NOP
                            roundtrips_in_pass++;
                            changed = 1;
                            p = q;
                            break;
                        }
                    }
                }
            }
        }

        // Pass 2: Dead Move Elimination (MOV Xn, Xn -> NOP)
        for (size_t k = 0; k < cb->count; k++) {
            uint32_t insn = cb->code[k];
            if ((insn & 0xFFE0FFFF) == 0xAA0003E0) {
                uint32_t rm = (insn >> 16) & 0x1F;
                uint32_t rd = insn & 0x1F;
                if (rm == rd) {
                    cb->code[k] = 0xD503201F; // NOP
                    deadmoves_in_pass++;
                    changed = 1;
                }
            }
        }

        // Pass 3: Redundant Zero Additions (ADD Xd, Xd, #0 -> NOP)
        for (size_t k = 0; k < cb->count; k++) {
            uint32_t insn = cb->code[k];
            if ((insn & 0xFFC00000) == 0x91000000) {
                uint32_t imm12 = (insn >> 10) & 0xFFF;
                uint32_t rn = (insn >> 5) & 0x1F;
                uint32_t rd = insn & 0x1F;
                if (imm12 == 0 && rn == rd) {
                    cb->code[k] = 0xD503201F; // NOP
                    deadadds_in_pass++;
                    changed = 1;
                }
            }
        }
    }

    s_jit_total_opt_roundtrips += roundtrips_in_pass;
    s_jit_total_opt_deadmoves   += deadmoves_in_pass;
    s_jit_total_opt_deadadds    += deadadds_in_pass;

    if (roundtrips_in_pass > 0 || deadmoves_in_pass > 0 || deadadds_in_pass > 0) {
        printf("[JIT OPT] Peephole Pass: collapsed %d stack round-trip(s), %d dead move(s), %d dead add(s)\n",
               roundtrips_in_pass, deadmoves_in_pass, deadadds_in_pass);
    }
}

// Forward Declarations for Recursive Descent Parser
static void parse_expr(lexer_t *l, code_buffer_t *cb);
static void parse_statement(lexer_t *l, code_buffer_t *cb);
static void parse_block(lexer_t *l, code_buffer_t *cb);
static void parse_unary(lexer_t *l, code_buffer_t *cb);

// Function compilation state for preserving recursion stack frames
static int64_t *current_fn_param_storages[8];
static int current_fn_param_count = 0;

// Primary Expression (Numbers, Floats, Identifiers, Function Calls, Strings, Tables, Array Indexing, Dereferencing, Parentheses)
static void parse_primary(lexer_t *l, code_buffer_t *cb) {
    token_t tok = lexer_peek(l);

    if (tok.type == TOK_NUMBER) {
        emit_mov_imm64(cb, 0, (uint64_t)tok.int_value); // X0 = number
        lexer_next(l);
    } else if (tok.type == TOK_FLOAT) {
        // Load IEEE-754 double precision bit pattern into X0
        uint64_t raw = 0;
        memcpy(&raw, &tok.float_value, sizeof(double));
        emit_mov_imm64(cb, 0, raw);
        s_expr_is_float = 1;
        lexer_next(l);
    } else if (tok.type == TOK_STRING) {
        // Allocate persistent copy in kernel heap
        size_t slen = strlen(tok.str_value) + 1;
        char *s_copy = (char*)kmalloc(slen);
        if (s_copy) memcpy(s_copy, tok.str_value, slen);
        emit_mov_imm64(cb, 0, (uint64_t)s_copy); // X0 = &string
        lexer_next(l);
    } else if (tok.type == TOK_LBRACE) {
        // Dynamic Table Literal: { key = val, key2 = val2, ... }
        lexer_next(l); // eat '{'
        emit_mov_imm64(cb, 16, (uint64_t)table_create);
        emit_blr(cb, 16); // X0 = table_create()
        emit_push_x(cb, 0); // Save table pointer on stack

        while (lexer_peek(l).type != TOK_RBRACE && lexer_peek(l).type != TOK_EOF) {
            token_t k = lexer_peek(l);
            if (k.type == TOK_IDENT || k.type == TOK_STRING) {
                char key[32];
                strncpy(key, k.str_value, 31);
                key[31] = '\0';
                lexer_next(l);

                if (lexer_peek(l).type == TOK_EQUAL || lexer_peek(l).type == TOK_COLON) {
                    lexer_next(l); // eat '=' or ':'
                }

                parse_expr(l, cb); // val in X0
                emit_mov_reg(cb, 2, 0); // val in X2
                emit_pop_x(cb, 0);      // tbl in X0
                emit_push_x(cb, 0);     // keep tbl on stack

                char *k_copy = (char*)kmalloc(strlen(key) + 1);
                if (k_copy) strcpy(k_copy, key);
                emit_mov_imm64(cb, 1, (uint64_t)k_copy); // key in X1

                emit_mov_imm64(cb, 16, (uint64_t)table_set);
                emit_blr(cb, 16);

                if (lexer_peek(l).type == TOK_COMMA) lexer_next(l);
            } else {
                lexer_next(l);
            }
        }
        if (lexer_peek(l).type == TOK_RBRACE) lexer_next(l); // eat '}'
        emit_pop_x(cb, 0); // Return table pointer in X0
    } else if (tok.type == TOK_IDENT) {
        char ident_name[64];
        strncpy(ident_name, tok.str_value, sizeof(ident_name) - 1);
        ident_name[sizeof(ident_name) - 1] = '\0';
        lexer_next(l);

        if (lexer_peek(l).type == TOK_LPAREN) {
            // Function Call or Hardware Intrinsic: ident(arg0, arg1, ...)
            lexer_next(l); // eat '('

            int arg_count = 0;
            if (lexer_peek(l).type != TOK_RPAREN) {
                while (1) {
                    parse_expr(l, cb); // Arg result in X0
                    emit_push_x(cb, 0); // Push arg to stack
                    arg_count++;

                    if (lexer_peek(l).type == TOK_COMMA) {
                        lexer_next(l);
                    } else {
                        break;
                    }
                }
            }

            if (lexer_peek(l).type == TOK_RPAREN) {
                lexer_next(l); // eat ')'
            }

            if (arg_count > 8) {
                printf("[JIT] Error: Function '%s' called with %d arguments (max 8 supported)\n", ident_name, arg_count);
                cb->has_error = 1;
                return;
            }

            // Restore arguments into registers X0-X7 in forward order
            for (int i = arg_count - 1; i >= 0; i--) {
                emit_pop_x(cb, i); // Pop into Xi
            }

            // 1. Check Native AArch64 Hardware & System Register Intrinsics (Zero Call Overhead)
            if (strcmp(ident_name, "__wfe") == 0) {
                emit_u32(cb, 0xD503205F); // WFE
                return;
            } else if (strcmp(ident_name, "__sev") == 0) {
                emit_u32(cb, 0xD503209F); // SEV
                return;
            } else if (strcmp(ident_name, "__dmb_ish") == 0) {
                emit_u32(cb, 0xD5033BBF); // DMB ISH
                return;
            } else if (strcmp(ident_name, "__dsb_sy") == 0) {
                emit_u32(cb, 0xD5033F9F); // DSB SY
                return;
            } else if (strcmp(ident_name, "__isb") == 0) {
                emit_u32(cb, 0xD5033FDF); // ISB
                return;
            } else if (strcmp(ident_name, "__mrs_cntvct") == 0) {
                emit_u32(cb, 0xD53BE040); // MRS X0, CNTVCT_EL0
                return;
            } else if (strcmp(ident_name, "__mrs_cntfrq") == 0) {
                emit_u32(cb, 0xD53BE000); // MRS X0, CNTFRQ_EL0
                return;
            } else if (strcmp(ident_name, "__mrs_mpidr") == 0) {
                emit_u32(cb, 0xD53800A0); // MRS X0, MPIDR_EL1
                emit_u32(cb, 0x92400400); // AND X0, X0, #3
                return;
            } else if (strcmp(ident_name, "__mrs_esr") == 0) {
                emit_u32(cb, 0xD5385200); // MRS X0, ESR_EL1
                return;
            } else if (strcmp(ident_name, "__mrs_far") == 0) {
                emit_u32(cb, 0xD5386000); // MRS X0, FAR_EL1
                return;
            } else if (strcmp(ident_name, "__dc_civac") == 0) {
                emit_u32(cb, 0xD50B7E20); // DC CIVAC, X0
                return;
            } else if (strcmp(ident_name, "__ic_ivau") == 0) {
                emit_u32(cb, 0xD50B7520); // IC IVAU, X0
                return;
            } else if (strcmp(ident_name, "__mmio_r32") == 0) {
                emit_u32(cb, 0xB9400000); // LDR W0, [X0]
                return;
            } else if (strcmp(ident_name, "__mmio_w32") == 0) {
                emit_u32(cb, 0xB9000001); // STR W1, [X0]
                return;
            }

            // 2. Late-Bound Symbol Indirect Cell (SIC) Resolution (Zero Forward Declarations!)
            local_var_t *call_lv = frame_find(ident_name);
            symbol_t *sym = call_lv ? NULL : symbols_lookup_or_reserve(ident_name, SYM_FUNC);
            if (!call_lv && !sym) {
                cb->has_error = 1;
                return;
            }

            // AAPCS compliance: Mirror arguments into float registers D0-D7 / S0-S7
            // HolyGL functions take IEEE-754 32-bit single-precision float parameters in S0-S7,
            // while math and HolyC functions take 64-bit doubles in D0-D7.
            int is_holygl_float_func = (
                strcmp(ident_name, "glVertex3f") == 0 ||
                strcmp(ident_name, "glVertex2f") == 0 ||
                strcmp(ident_name, "glColor3f") == 0 ||
                strcmp(ident_name, "glColor4f") == 0 ||
                strcmp(ident_name, "glNormal3f") == 0 ||
                strcmp(ident_name, "glTexCoord2f") == 0 ||
                strcmp(ident_name, "glTranslatef") == 0 ||
                strcmp(ident_name, "glRotatef") == 0 ||
                strcmp(ident_name, "glScalef") == 0 ||
                strcmp(ident_name, "gluPerspective") == 0 ||
                strcmp(ident_name, "glClearColor") == 0
            );

            if (is_holygl_float_func) {
                for (int i = 0; i < arg_count; i++) {
                    emit_fmov_d_x(cb, i, i);
                    emit_fcvt_s_d(cb, i, i);
                }
            }

            // Call function via Symbol Indirect Cell (SIC) or Function Pointer Variable
            if (call_lv) {
                emit_frame_addr(cb, 16, call_lv->off);
                emit_ldr_ptr(cb, 16, 16); // Load function pointer from frame slot
            } else if (sym->type == SYM_VAR) {
                emit_mov_imm64(cb, 16, (uint64_t)sym->address);
                emit_ldr_ptr(cb, 16, 16); // Dereference variable storage
            } else {
                emit_mov_imm64(cb, 16, (uint64_t)&sym->address);
                emit_ldr_ptr(cb, 16, 16); // Dereference SIC cell (&sym->address) dynamically!
            }
            emit_blr(cb, 16);
        } else if (lexer_peek(l).type == TOK_LBRACKET) {
            // Array Indexing: ident[index]
            lexer_next(l); // eat '['
            uint64_t arr_ref = lookup_var_ref(ident_name);
            var_type_t *vt = lookup_var_type(ident_name);
            if (arr_ref) {
                if (vt && !vt->is_ptr) {
                    emit_ref_addr(cb, 1, arr_ref); // frame-resident array: address IS base
                } else {
                    emit_ref_addr(cb, 16, arr_ref);
                    emit_ldr_ptr(cb, 1, 16); // X1 = base address
                }
            } else {
                emit_mov_imm64(cb, 1, 0);
            }
            emit_push_x(cb, 1);      // Save base

            parse_expr(l, cb);       // X0 = index
            emit_pop_x(cb, 1);       // X1 = base

            int scale = vt ? vt->scale : 1;

            if (scale == 8) {
                emit_mov_imm64(cb, 2, 8);
                emit_mul(cb, 0, 0, 2);
                emit_add(cb, 0, 1, 0);
                emit_ldr64(cb, 0, 0);
            } else if (scale == 4) {
                emit_mov_imm64(cb, 2, 4);
                emit_mul(cb, 0, 0, 2);
                emit_add(cb, 0, 1, 0);
                emit_ldr32(cb, 0, 0);
            } else if (scale == 2) {
                emit_mov_imm64(cb, 2, 2);
                emit_mul(cb, 0, 0, 2);
                emit_add(cb, 0, 1, 0);
                emit_ldrh(cb, 0, 0);
            } else {
                emit_add(cb, 0, 1, 0);   // X0 = base + index
                emit_ldrb(cb, 0, 0);     // X0 = *(uint8_t*)X0
            }

            if (lexer_peek(l).type == TOK_RBRACKET) {
                lexer_next(l); // eat ']'
            }

            // Chained multidimensional array indexing: ident[i][j]...
            while (lexer_peek(l).type == TOK_LBRACKET) {
                lexer_next(l); // eat '['
                emit_push_x(cb, 0); // push row pointer
                parse_expr(l, cb);  // X0 = col index
                emit_pop_x(cb, 1);  // X1 = row pointer
                emit_mov_imm64(cb, 2, 8); // 8-byte elements
                emit_mul(cb, 0, 0, 2);
                emit_add(cb, 0, 1, 0);
                emit_ldr64(cb, 0, 0); // X0 = row[col]
                if (lexer_peek(l).type == TOK_RBRACKET) {
                    lexer_next(l); // eat ']'
                }
            }
        } else {
            // Variable Read: frame local first, then Global Symbol Table (late-bound)
            uint64_t var_ref = lookup_var_ref(ident_name);
            symbol_t *sym = var_ref ? NULL : symbols_lookup_entry(ident_name);
            if (!var_ref && !sym) {
                // Forward reference: reserve a SIC cell so a later definition resolves
                // this read instead of silently baking in a constant 0.
                sym = symbols_lookup_or_reserve(ident_name, SYM_VAR);
                if (sym) {
                    printf("[JIT] line %d: forward reference '%s' late-bound via SIC\n",
                           l->line, ident_name);
                }
            }
            if (!var_ref && sym && sym->type == SYM_VAR && sym->address) {
                var_ref = (uint64_t)sym->address;
            }
            var_type_t *vt = lookup_var_type(ident_name);
            if (vt && vt->is_float && !vt->is_ptr) {
                s_expr_is_float = 1;
            }
            if (var_ref) {
                if (vt && (vt->is_array || (vt->struct_type[0] != '\0' && !vt->is_ptr))) {
                    emit_ref_addr(cb, 0, var_ref);      // array/struct value: X0 = base address
                } else {
                    emit_ref_addr(cb, 16, var_ref);
                    emit_ldr_ptr(cb, 0, 16); // X0 = *address
                }
            } else if (sym && sym->type == SYM_FUNC) {
                emit_mov_imm64(cb, 16, (uint64_t)&sym->address);
                emit_ldr_ptr(cb, 0, 16); // X0 = live function pointer from SIC cell
            } else {
                printf("[JIT] Warning: line %d: undefined identifier '%s'\n", l->line, ident_name);
                emit_mov_imm64(cb, 0, 0);
            }

            char cur_st_name[32] = {0};
            if (vt && vt->struct_type[0] != '\0') {
                strncpy(cur_st_name, vt->struct_type, 31);
            }
            int last_member_elem_sz = (vt && vt->scale > 0) ? vt->scale : 8;
            int last_member_is_float = 0;

            // Unified Postfix Expression Pipeline: arbitrary chained ident.f, ident->f, ident[i], ident(args)
            size_t pf_start_pos = l->pos;
            while (1) {
                token_type_t ptt = lexer_peek(l).type;
                if (ptt == TOK_DOT || ptt == TOK_ARROW) {
                    lexer_next(l); // eat '.' or '->'
                    token_t f_tok = lexer_peek(l);
                    if (f_tok.type == TOK_IDENT) {
                        char field[32];
                        strncpy(field, f_tok.str_value, 31);
                        field[31] = '\0';
                        lexer_next(l);

                        struct_def_t *st = NULL;
                        if (cur_st_name[0] != '\0') {
                            st = find_struct_def(cur_st_name);
                        }
                        if (!st) {
                            for (int s = 0; s < struct_def_count; s++) {
                                for (int m = 0; m < struct_defs[s].member_count; m++) {
                                    if (strcmp(struct_defs[s].members[m].name, field) == 0) {
                                        st = &struct_defs[s];
                                        break;
                                    }
                                }
                                if (st) break;
                            }
                        }
                        if (st) {
                            int found = 0;
                            int offset = 0;
                            int fsize = 8;
                            int is_arr = 0;
                            int is_nst = 0;
                            int is_flt = 0;
                            char sub_st[32] = {0};
                            for (int m = 0; m < st->member_count; m++) {
                                if (strcmp(st->members[m].name, field) == 0) {
                                    offset = st->members[m].offset;
                                    fsize = st->members[m].size;
                                    is_arr = st->members[m].is_array;
                                    is_flt = st->members[m].is_float;
                                    last_member_elem_sz = st->members[m].elem_size > 0 ? st->members[m].elem_size : 8;
                                    if (st->members[m].type_name[0]) {
                                        strncpy(sub_st, st->members[m].type_name, 31);
                                        if (find_struct_def(sub_st) && !st->members[m].is_ptr) is_nst = 1;
                                    }

                                    found = 1;
                                    break;
                                }
                            }
                            if (!found) {
                                cb->has_error = 1;
                                snprintf(cb->error_msg, sizeof(cb->error_msg),
                                         "Type error: struct '%s' has no member '%s'", st->name, field);
                                printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                                return;
                            }
                            emit_mov_imm64(cb, 1, (uint64_t)offset);
                            emit_add(cb, 0, 0, 1); // X0 = base + offset
                            if (is_arr || is_nst) {
                                if (sub_st[0]) strncpy(cur_st_name, sub_st, 31);
                                s_expr_is_float = 0;
                                last_member_is_float = is_flt;
                                continue;
                            }
                            if (fsize == 1) emit_ldrb(cb, 0, 0);
                            else if (fsize == 2) emit_ldrh(cb, 0, 0);
                            else if (fsize == 4) emit_ldr32(cb, 0, 0);
                            else emit_ldr64(cb, 0, 0);
                            if (sub_st[0]) strncpy(cur_st_name, sub_st, 31);
                            s_expr_is_float = is_flt;
                            last_member_is_float = is_flt;
                            continue;
                        }

                        // Dynamic table get: table_get(tbl, field)
                        char *f_copy = (char*)kmalloc(strlen(field) + 1);
                        if (f_copy) strcpy(f_copy, field);
                        emit_mov_imm64(cb, 1, (uint64_t)f_copy); // X1 = key
                        emit_mov_imm64(cb, 16, (uint64_t)table_get);
                        emit_blr(cb, 16); // X0 = value
                        continue;
                    }
                } else if (ptt == TOK_LBRACKET) {
                    lexer_next(l); // eat '['
                    emit_push_x(cb, 0); // push array base
                    parse_expr(l, cb);  // index in X0
                    emit_pop_x(cb, 1);  // base in X1
                    int esz = last_member_elem_sz > 0 ? last_member_elem_sz : 8;
                    emit_mov_imm64(cb, 2, (uint64_t)esz);
                    emit_mul(cb, 0, 0, 2);
                    emit_add(cb, 0, 1, 0); // X0 = elem_addr

                    if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'
                    token_type_t next_t = lexer_peek(l).type;
                    if (cur_st_name[0] && find_struct_def(cur_st_name) && (next_t == TOK_DOT || next_t == TOK_ARROW)) {
                        // Struct element in array, leave X0 as address for subsequent member lookup
                        continue;
                    }

                    if (esz == 1) emit_ldrb(cb, 0, 0);
                    else if (esz == 2) emit_ldrh(cb, 0, 0);
                    else if (esz == 4) emit_ldr32(cb, 0, 0);
                    else emit_ldr64(cb, 0, 0);
                    if (last_member_is_float) {
                        s_expr_is_float = 1;
                    }
                    continue;
                } else if (ptt == TOK_LPAREN) {
                    lexer_next(l); // eat '('
                    emit_push_x(cb, 0); // Save function pointer on stack

                    int arg_count = 0;
                    if (lexer_peek(l).type != TOK_RPAREN) {
                        while (1) {
                            parse_expr(l, cb); // Arg result in X0
                            emit_push_x(cb, 0); // Push arg to stack
                            arg_count++;

                            if (lexer_peek(l).type == TOK_COMMA) {
                                lexer_next(l);
                            } else {
                                break;
                            }
                        }
                    }

                    if (lexer_peek(l).type == TOK_RPAREN) {
                        lexer_next(l); // eat ')'
                    }

                    // Restore arguments into registers X0-X(arg_count-1)
                    for (int i = arg_count - 1; i >= 0; i--) {
                        emit_pop_x(cb, i);
                    }

                    // Pop the saved function pointer into X16
                    emit_pop_x(cb, 16);

                    // Call function via X16
                    emit_blr(cb, 16);
                    continue;
                } else {
                    break;
                }
            }


            // Post-increment / Post-decrement: ident++ / ident--
            if (lexer_peek(l).type == TOK_PLUSPLUS || lexer_peek(l).type == TOK_MINUSMINUS) {
                int is_inc = (lexer_peek(l).type == TOK_PLUSPLUS);
                lexer_next(l);
                if (l->pos != pf_start_pos + 2 && lexer_peek(l).type != TOK_EOF && 0) {}
                if (var_ref) {
                    emit_mov_reg(cb, 2, 0); // X2 = old value
                    emit_mov_imm64(cb, 3, 1);
                    if (is_inc) emit_add(cb, 1, 0, 3); else emit_sub(cb, 1, 0, 3);
                    emit_ref_addr(cb, 16, var_ref);
                    emit_str_ptr(cb, 1, 16); // *address = X1
                    emit_mov_reg(cb, 0, 2); // Return old value
                }
            }
        }
    } else if (tok.type == TOK_LPAREN) {
        lexer_t l_save = *l;
        lexer_next(&l_save); // advance past '(' in temporary copy
        token_t next_tok = lexer_peek(&l_save);
        if (next_tok.type == TOK_TYPE_F64) {
            *l = l_save;
            lexer_next(l); // eat 'F64'
            if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l); // eat ')'
            s_expr_is_float = 0;
            parse_unary(l, cb);
            if (!s_expr_is_float) {
                emit_scvtf(cb, 0, 0); // X0 int -> D0 double
                emit_fmov_x_d(cb, 0, 0); // D0 -> X0
            }
            s_expr_is_float = 1;
            return;
        } else if (next_tok.type == TOK_TYPE_I64 || next_tok.type == TOK_TYPE_U32 || next_tok.type == TOK_TYPE_U8 || next_tok.type == TOK_IDENT) {
            lexer_t l_chk = l_save;
            lexer_next(&l_chk); // eat type/ident
            int has_star = 0;
            while (lexer_peek(&l_chk).type == TOK_STAR) {
                has_star = 1;
                lexer_next(&l_chk);
            }
            if (has_star && lexer_peek(&l_chk).type == TOK_RPAREN) {
                // Pointer cast: (Type*) or (Ident*)
                *l = l_chk;
                lexer_next(l); // eat ')'
                s_expr_is_float = 0;
                parse_unary(l, cb);
                s_expr_is_float = 0;
                return;
            } else if (next_tok.type == TOK_TYPE_I64 || next_tok.type == TOK_TYPE_U32 || next_tok.type == TOK_TYPE_U8) {
                *l = l_save;
                lexer_next(l); // eat type
                if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l); // eat ')'
                s_expr_is_float = 0;
                parse_unary(l, cb);
                if (s_expr_is_float) {
                    emit_fmov_d_x(cb, 0, 0); // X0 -> D0
                    emit_fcvtzs(cb, 0, 0);  // D0 double -> X0 int
                }
                s_expr_is_float = 0;
                return;
            }
        }

        lexer_next(l); // eat '('
        parse_expr(l, cb);
        if (lexer_peek(l).type == TOK_RPAREN) {
            lexer_next(l); // eat ')'
        }
    } else {
        token_t unk = lexer_peek(l);
        if (unk.type != TOK_EOF && unk.type != TOK_SEMICOLON && unk.type != TOK_RPAREN && unk.type != TOK_RBRACE && unk.type != TOK_COMMA) {
            jit_syntax_error(l, cb, "Unexpected token '%s' (type %d) in expression",
                             unk.str_value[0] ? unk.str_value : "<symbol>",
                             (int)unk.type);
            lexer_next(l); // GUARANTEE forward progress
        }
    }
}

// Unary Operators: -, ~, !, *, &, sizeof
static void parse_unary(lexer_t *l, code_buffer_t *cb) {
    token_t tok = lexer_peek(l);

    if (tok.type == TOK_MINUS) {
        lexer_next(l);
        parse_unary(l, cb);
        if (s_expr_is_float) {
            emit_fmov_d_x(cb, 0, 0);
            emit_fneg(cb, 0, 0);
            emit_fmov_x_d(cb, 0, 0);
        } else {
            emit_neg(cb, 0, 0);
        }
    } else if (tok.type == TOK_TILDE) {
        lexer_next(l);
        parse_unary(l, cb);
        emit_mvn(cb, 0, 0);
    } else if (tok.type == TOK_EXCLAM) {
        lexer_next(l);
        parse_unary(l, cb);
        emit_cmp(cb, 0, 31); // CMP X0, XZR
        emit_cset(cb, 0, 1); // X0 = (X0 == 0)
    } else if (tok.type == TOK_STAR) {
        lexer_next(l); // eat '*'
        int deref_scale = 8;
        if (lexer_peek(l).type == TOK_LPAREN) {
            lexer_t l_chk = *l;
            lexer_next(&l_chk); // eat '('
            token_t t_type = lexer_peek(&l_chk);
            if (t_type.type == TOK_TYPE_U8 || t_type.type == TOK_TYPE_U16 ||
                t_type.type == TOK_TYPE_U32 || t_type.type == TOK_TYPE_I64 ||
                t_type.type == TOK_TYPE_F64) {
                lexer_next(&l_chk); // eat type
                if (lexer_peek(&l_chk).type == TOK_STAR) {
                    lexer_next(&l_chk); // eat '*'
                    if (lexer_peek(&l_chk).type == TOK_RPAREN) {
                        lexer_next(&l_chk); // eat ')'
                        *l = l_chk; // commit cast
                        if (t_type.type == TOK_TYPE_U8) deref_scale = 1;
                        else if (t_type.type == TOK_TYPE_U16) deref_scale = 2;
                        else if (t_type.type == TOK_TYPE_U32) deref_scale = 4;
                        else deref_scale = 8;
                    }
                }
            }
        }
        if (deref_scale == 8) {
            token_t next_tok = lexer_peek(l);
            if (next_tok.type == TOK_IDENT) {
                var_type_t *vt = lookup_var_type(next_tok.str_value);
                if (vt && vt->is_ptr && vt->scale > 0) {
                    deref_scale = vt->scale;
                }
            } else if (next_tok.type == TOK_LPAREN) {
                lexer_t l_chk = *l;
                lexer_next(&l_chk); // eat '('
                token_t inner_tok = lexer_peek(&l_chk);
                if (inner_tok.type == TOK_IDENT) {
                    var_type_t *vt = lookup_var_type(inner_tok.str_value);
                    if (vt && vt->is_ptr && vt->scale > 0) {
                        deref_scale = vt->scale;
                    }
                }
            }
        }
        parse_unary(l, cb);
        if (deref_scale == 1) {
            emit_ldrb(cb, 0, 0);
        } else if (deref_scale == 2) {
            emit_ldrh(cb, 0, 0);
        } else if (deref_scale == 4) {
            emit_ldr32(cb, 0, 0);
        } else {
            emit_ldr64(cb, 0, 0);
        }
    } else if (tok.type == TOK_AMPERSAND) {
        lexer_next(l); // eat '&'
        token_t id = lexer_peek(l);
        if (id.type == TOK_IDENT) {
            char base_name[64];
            strncpy(base_name, id.str_value, 63);
            base_name[63] = '\0';
            lexer_next(l); // eat ident

            uint64_t amp_ref = lookup_var_ref(base_name);
            var_type_t *vt = lookup_var_type(base_name);
            if (amp_ref) {
                if (vt && vt->is_ptr) {
                    emit_ref_addr(cb, 16, amp_ref);
                    emit_ldr_ptr(cb, 0, 16); // X0 = pointer value
                } else {
                    emit_ref_addr(cb, 0, amp_ref); // X0 = &variable
                }
            } else {
                // &function: resolve the live entry through the SIC cell so forward
                // definitions (and later redefinitions) are observed at call time.
                symbol_t *fsym = symbols_lookup_or_reserve(base_name, SYM_FUNC);
                if (fsym) {
                    emit_mov_imm64(cb, 16, (uint64_t)&fsym->address);
                    emit_ldr_ptr(cb, 0, 16); // X0 = function entry
                } else {
                    printf("[JIT] line %d: address-of undefined symbol '%s'\n", l->line, base_name);
                    emit_mov_imm64(cb, 0, 0);
                }
            }

            char cur_st[32] = {0};
            int cur_elem_sz = 8;
            if (vt && vt->struct_type[0]) {
                strncpy(cur_st, vt->struct_type, 31);
            }

            while (lexer_peek(l).type == TOK_DOT || lexer_peek(l).type == TOK_ARROW || lexer_peek(l).type == TOK_LBRACKET) {
                if (lexer_peek(l).type == TOK_DOT || lexer_peek(l).type == TOK_ARROW) {
                    lexer_next(l); // eat '.' or '->'
                    token_t f_tok = lexer_peek(l);
                    if (f_tok.type == TOK_IDENT) {
                        char field[32];
                        strncpy(field, f_tok.str_value, 31);
                        field[31] = '\0';
                        lexer_next(l);

                        struct_def_t *st = find_struct_def(cur_st);
                        if (!st) {
                            for (int s = 0; s < struct_def_count; s++) {
                                for (int m = 0; m < struct_defs[s].member_count; m++) {
                                    if (strcmp(struct_defs[s].members[m].name, field) == 0) {
                                        st = &struct_defs[s];
                                        break;
                                    }
                                }
                                if (st) break;
                            }
                        }
                        if (st) {
                            for (int m = 0; m < st->member_count; m++) {
                                if (strcmp(st->members[m].name, field) == 0) {
                                    emit_mov_imm64(cb, 1, (uint64_t)st->members[m].offset);
                                    emit_add(cb, 0, 0, 1); // X0 = base + offset
                                    if (st->members[m].type_name[0]) {
                                        strncpy(cur_st, st->members[m].type_name, 31);
                                    }
                                    cur_elem_sz = st->members[m].elem_size > 0 ? st->members[m].elem_size : 8;
                                    break;
                                }
                            }
                        }
                    }
                } else if (lexer_peek(l).type == TOK_LBRACKET) {
                    lexer_next(l); // eat '['
                    emit_push_x(cb, 0); // save base address
                    parse_expr(l, cb);  // index in X0
                    if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'
                    emit_pop_x(cb, 1);  // X1 = base address

                    int elem_sz = 8;
                    struct_def_t *st = find_struct_def(cur_st);
                    if (st && st->total_size > 0) {
                        elem_sz = st->total_size;
                    } else if (cur_elem_sz > 0) {
                        elem_sz = cur_elem_sz;
                    }
                    emit_mov_imm64(cb, 2, (uint64_t)elem_sz);
                    emit_mul(cb, 0, 0, 2); // X0 = index * elem_sz
                    emit_add(cb, 0, 1, 0); // X0 = base + index * elem_sz
                }
            }
        }
    } else if (tok.type == TOK_SIZEOF) {
        lexer_next(l);
        if (lexer_peek(l).type == TOK_LPAREN) lexer_next(l);
        token_t t = lexer_peek(l);
        int sz = 8;
        if (t.type == TOK_TYPE_I64 || t.type == TOK_TYPE_F64) sz = 8;
        else if (t.type == TOK_TYPE_U32) sz = 4;
        else if (t.type == TOK_TYPE_U16) sz = 2;
        else if (t.type == TOK_TYPE_U8) sz = 1;
        else if (t.type == TOK_IDENT) {
            struct_def_t *st = find_struct_def(t.str_value);
            if (st) sz = st->total_size;
        }
        lexer_next(l);
        if (lexer_peek(l).type == TOK_STAR) {
            sz = 8;
            lexer_next(l);
        }
        if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l);
        emit_mov_imm64(cb, 0, (uint64_t)sz);
    } else {
        parse_primary(l, cb);
    }
}

// Multiplicative: *, /, %
static void parse_term(lexer_t *l, code_buffer_t *cb) {
    parse_unary(l, cb);
    int lhs_is_float = s_expr_is_float;

    while (lexer_peek(l).type == TOK_STAR ||
           lexer_peek(l).type == TOK_SLASH ||
           lexer_peek(l).type == TOK_PERCENT) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0); // Save LHS
        s_expr_is_float = 0;
        parse_unary(l, cb); // RHS in X0
        int rhs_is_float = s_expr_is_float;
        emit_pop_x(cb, 1);  // LHS in X1

        if (lhs_is_float || rhs_is_float) {
            if (!lhs_is_float) {
                emit_scvtf(cb, 1, 1);
                emit_fmov_x_d(cb, 1, 1);
            }
            if (!rhs_is_float) {
                emit_scvtf(cb, 0, 0);
                emit_fmov_x_d(cb, 0, 0);
            }
            emit_fmov_d_x(cb, 1, 1); // D1 = X1
            emit_fmov_d_x(cb, 0, 0); // D0 = X0
            if (op == TOK_STAR) {
                emit_fmul(cb, 0, 1, 0); // D0 = D1 * D0
            } else if (op == TOK_SLASH) {
                emit_fdiv(cb, 0, 1, 0); // D0 = D1 / D0
            } else {
                emit_fdiv(cb, 2, 1, 0);
                emit_fcvtzs(cb, 2, 2);
                emit_scvtf(cb, 2, 2);
                emit_fmul(cb, 2, 2, 0);
                emit_fsub(cb, 0, 1, 2);
            }
            emit_fmov_x_d(cb, 0, 0); // X0 = D0
            s_expr_is_float = 1;
            lhs_is_float = 1;
        } else {
            if (op == TOK_STAR) {
                emit_mul(cb, 0, 1, 0); // X0 = X1 * X0
            } else if (op == TOK_SLASH) {
                emit_sdiv(cb, 0, 1, 0); // X0 = X1 / X0
            } else if (op == TOK_PERCENT) {
                emit_srem(cb, 0, 1, 0); // X0 = X1 % X0
            }
        }
    }
}

// Additive: +, -
static void parse_additive(lexer_t *l, code_buffer_t *cb) {
    parse_term(l, cb);
    int lhs_is_float = s_expr_is_float;

    while (lexer_peek(l).type == TOK_PLUS || lexer_peek(l).type == TOK_MINUS) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0); // Save LHS
        s_expr_is_float = 0;
        parse_term(l, cb);  // RHS in X0
        int rhs_is_float = s_expr_is_float;
        emit_pop_x(cb, 1);  // LHS in X1

        if (lhs_is_float || rhs_is_float) {
            if (!lhs_is_float) {
                emit_scvtf(cb, 1, 1);
                emit_fmov_x_d(cb, 1, 1);
            }
            if (!rhs_is_float) {
                emit_scvtf(cb, 0, 0);
                emit_fmov_x_d(cb, 0, 0);
            }
            emit_fmov_d_x(cb, 1, 1);
            emit_fmov_d_x(cb, 0, 0);
            if (op == TOK_PLUS) {
                emit_fadd(cb, 0, 1, 0);
            } else {
                emit_fsub(cb, 0, 1, 0);
            }
            emit_fmov_x_d(cb, 0, 0);
            s_expr_is_float = 1;
            lhs_is_float = 1;
        } else {
            if (op == TOK_PLUS) {
                emit_add(cb, 0, 1, 0);
            } else {
                emit_sub(cb, 0, 1, 0);
            }
        }
    }
}

// Shifts: <<, >>
static void parse_shift(lexer_t *l, code_buffer_t *cb) {
    parse_additive(l, cb);

    while (lexer_peek(l).type == TOK_SHL || lexer_peek(l).type == TOK_SHR) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0); // Save LHS
        parse_additive(l, cb); // RHS in X0
        emit_pop_x(cb, 1);  // LHS in X1

        if (op == TOK_SHL) {
            emit_lsl(cb, 0, 1, 0); // X0 = X1 << X0
        } else {
            emit_asr(cb, 0, 1, 0); // X0 = X1 >> X0 (Arithmetic Shift for signed integers)
        }
    }
}

// Bitwise operations: &, |, ^
static void parse_bitwise(lexer_t *l, code_buffer_t *cb) {
    parse_shift(l, cb);

    while (lexer_peek(l).type == TOK_AMPERSAND ||
           lexer_peek(l).type == TOK_PIPE ||
           lexer_peek(l).type == TOK_CARET) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0);
        parse_shift(l, cb);
        emit_pop_x(cb, 1);

        if (op == TOK_AMPERSAND) {
            emit_and(cb, 0, 1, 0); // X0 = X1 & X0
        } else if (op == TOK_PIPE) {
            emit_orr(cb, 0, 1, 0); // X0 = X1 | X0
        } else if (op == TOK_CARET) {
            emit_eor(cb, 0, 1, 0); // X0 = X1 ^ X0
        }
    }
}

// Relational: <, <=, >, >=
static void parse_relational(lexer_t *l, code_buffer_t *cb) {
    parse_bitwise(l, cb);
    int lhs_is_float = s_expr_is_float;

    while (lexer_peek(l).type == TOK_LT || lexer_peek(l).type == TOK_LTE ||
           lexer_peek(l).type == TOK_GT || lexer_peek(l).type == TOK_GTE) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0);
        s_expr_is_float = 0;
        parse_bitwise(l, cb);
        int rhs_is_float = s_expr_is_float;
        emit_pop_x(cb, 1);

        if (lhs_is_float || rhs_is_float) {
            if (!lhs_is_float) {
                emit_scvtf(cb, 1, 1);
                emit_fmov_x_d(cb, 1, 1);
            }
            if (!rhs_is_float) {
                emit_scvtf(cb, 0, 0);
                emit_fmov_x_d(cb, 0, 0);
            }
            emit_fmov_d_x(cb, 1, 1);
            emit_fmov_d_x(cb, 0, 0);
            emit_fcmp(cb, 1, 0); // FCMP D1, D0
        } else {
            emit_cmp(cb, 1, 0); // CMP X1, X0
        }
        if (op == TOK_LT) {
            emit_cset(cb, 0, 10); // LT -> inv GE (10)
        } else if (op == TOK_LTE) {
            emit_cset(cb, 0, 12); // LE -> inv GT (12)
        } else if (op == TOK_GT) {
            emit_cset(cb, 0, 13); // GT -> inv LE (13)
        } else if (op == TOK_GTE) {
            emit_cset(cb, 0, 11); // GE -> inv LT (11)
        }
        s_expr_is_float = 0;
    }
}

// Equality: ==, !=
static void parse_equality(lexer_t *l, code_buffer_t *cb) {
    parse_relational(l, cb);
    int lhs_is_float = s_expr_is_float;

    while (lexer_peek(l).type == TOK_EQEQ || lexer_peek(l).type == TOK_NEQ) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0);
        s_expr_is_float = 0;
        parse_relational(l, cb);
        int rhs_is_float = s_expr_is_float;
        emit_pop_x(cb, 1);

        if (lhs_is_float || rhs_is_float) {
            if (!lhs_is_float) {
                emit_scvtf(cb, 1, 1);
                emit_fmov_x_d(cb, 1, 1);
            }
            if (!rhs_is_float) {
                emit_scvtf(cb, 0, 0);
                emit_fmov_x_d(cb, 0, 0);
            }
            emit_fmov_d_x(cb, 1, 1);
            emit_fmov_d_x(cb, 0, 0);
            emit_fcmp(cb, 1, 0);
        } else {
            emit_cmp(cb, 1, 0);
        }
        if (op == TOK_EQEQ) {
            emit_cset(cb, 0, 1); // EQ -> inv NE (1)
        } else {
            emit_cset(cb, 0, 0); // NE -> inv EQ (0)
        }
        s_expr_is_float = 0;
    }
}

// Logical AND / OR: &&, ||
static void parse_logical(lexer_t *l, code_buffer_t *cb) {
    parse_equality(l, cb);

    while (lexer_peek(l).type == TOK_ANDAND || lexer_peek(l).type == TOK_PIPEPIPE) {
        token_type_t op = lexer_peek(l).type;
        lexer_next(l);

        emit_push_x(cb, 0);
        parse_equality(l, cb);
        emit_pop_x(cb, 1);
        emit_cmp(cb, 1, 31); // CMP X1, XZR
        emit_cset(cb, 1, 0);  // X1 = (X1 != 0)
        emit_cmp(cb, 0, 31); // CMP X0, XZR
        emit_cset(cb, 0, 0);  // X0 = (X0 != 0)

        if (op == TOK_ANDAND) {
            emit_and(cb, 0, 1, 0);
        } else {
            emit_orr(cb, 0, 1, 0);
        }
    }
}

// Ternary Operator: cond ? expr1 : expr2
static void parse_expr(lexer_t *l, code_buffer_t *cb) {
    parse_logical(l, cb);

    if (lexer_peek(l).type == TOK_QUESTION) {
        lexer_next(l); // eat '?'
        size_t cbz_idx = emit_cbz_placeholder(cb, 0); // Jump to false branch if X0 == 0
        parse_expr(l, cb); // True branch expression (leaves result in X0)
        size_t b_exit = emit_b_placeholder(cb); // Jump over false branch
        patch_cbz(cb, cbz_idx, cb->count);

        if (lexer_peek(l).type == TOK_COLON) {
            lexer_next(l); // eat ':'
        }

        parse_expr(l, cb); // False branch expression (leaves result in X0)
        patch_b(cb, b_exit, cb->count);
    }
}

// Block: { statement* }
static void parse_block(lexer_t *l, code_buffer_t *cb) {
    if (lexer_peek(l).type == TOK_LBRACE) {
        lexer_next(l); // eat '{'
        while (lexer_peek(l).type != TOK_RBRACE && lexer_peek(l).type != TOK_EOF) {
            size_t prev_pos = l->pos;
            parse_statement(l, cb);
            if (cb->has_error) break;
            if (l->pos <= prev_pos && lexer_peek(l).type != TOK_RBRACE && lexer_peek(l).type != TOK_EOF) {
                jit_syntax_error(l, cb, "Unparsed token '%s' (type %d) inside block",
                                 l->current.str_value[0] ? l->current.str_value : "<symbol>",
                                 (int)l->current.type);
                lexer_next(l); // GUARANTEE forward progress: never hang!
            }
        }
        if (lexer_peek(l).type == TOK_RBRACE) {
            lexer_next(l); // eat '}'
        }
    } else {
        parse_statement(l, cb);
    }
}

// Statements (Function Decls, Variable Decls, Assignments, If, While, For, Expressions, Classes, Format Strings)
// Class / Struct Definition (also reused by the type pre-pass)
static void parse_struct_def(lexer_t *l, code_buffer_t *cb) {
    lexer_next(l); // eat class / struct
    token_t st_id = lexer_peek(l);
    if (st_id.type == TOK_IDENT) {
        char st_name[32];
        strncpy(st_name, st_id.str_value, 31);
        st_name[31] = '\0';
        lexer_next(l); // eat ident

        struct_def_t *st = find_struct_def(st_name);
        if (!st) {
            if (struct_def_count >= MAX_STRUCT_DEFS) {
                printf("[JIT] Error: Maximum struct definitions (%d) exceeded\n", MAX_STRUCT_DEFS);
                cb->has_error = 1;
                return;
            }
            st = &struct_defs[struct_def_count++];
        }

        memset(st, 0, sizeof(struct_def_t));
        strncpy(st->name, st_name, 31);

        if (lexer_peek(l).type == TOK_LBRACE) {
            lexer_next(l); // eat '{'
            int cur_offset = 0;
            while (lexer_peek(l).type != TOK_RBRACE && lexer_peek(l).type != TOK_EOF) {
                token_type_t m_type = lexer_peek(l).type;
                int is_mem_float = (m_type == TOK_TYPE_F64);
                char m_type_str[32] = {0};
                if (m_type == TOK_IDENT) {
                    strncpy(m_type_str, lexer_peek(l).str_value, 31);
                }
                int m_size = 8;
                if (m_type == TOK_TYPE_U8) m_size = 1;
                else if (m_type == TOK_TYPE_U16) m_size = 2;
                else if (m_type == TOK_TYPE_U32) m_size = 4;
                else if (m_type == TOK_IDENT) {
                    struct_def_t *nested_st = find_struct_def(lexer_peek(l).str_value);
                    if (nested_st && nested_st->total_size > 0) m_size = nested_st->total_size;
                    else m_size = 8;
                }
                else m_size = 8;
                lexer_next(l); // eat type

                if (lexer_peek(l).type == TOK_LPAREN) {
                    // Function pointer member: ReturnType (*fn_name)(params...);
                    lexer_next(l); // eat '('
                    if (lexer_peek(l).type == TOK_STAR) lexer_next(l); // eat '*'
                    token_t fn_id = lexer_peek(l);
                    if (fn_id.type == TOK_IDENT) {
                        if (st->member_count < MAX_STRUCT_MEMBERS) {
                            struct_member_t *mem = &st->members[st->member_count++];
                            memset(mem, 0, sizeof(struct_member_t));
                            strncpy(mem->name, fn_id.str_value, 31);
                            mem->name[31] = '\0';
                            mem->offset = cur_offset;
                            mem->size = 8; // 64-bit function pointer
                            mem->elem_size = 8;
                            mem->is_ptr = 1;
                            cur_offset += 8;
                        }
                        lexer_next(l); // eat ident
                    }
                    if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l); // eat ')'
                    // Skip argument list: (params...)
                    if (lexer_peek(l).type == TOK_LPAREN) {
                        int p_depth = 1;
                        lexer_next(l);
                        while (p_depth > 0 && lexer_peek(l).type != TOK_EOF && lexer_peek(l).type != TOK_SEMICOLON) {
                            token_t pt = lexer_next(l);
                            if (pt.type == TOK_LPAREN) p_depth++;
                            else if (pt.type == TOK_RPAREN) p_depth--;
                        }
                    }
                } else {
                    int orig_elem_sz = m_size;
                    int is_mem_ptr = 0;
                    if (lexer_peek(l).type == TOK_STAR) {
                        is_mem_ptr = 1;
                        m_size = 8;
                        lexer_next(l);
                    }

                    token_t m_id = lexer_peek(l);
                    if (m_id.type == TOK_IDENT) {
                        if (st->member_count >= MAX_STRUCT_MEMBERS) {
                            printf("[JIT] Error: Struct '%s' exceeded max members (%d)\n", st_name, MAX_STRUCT_MEMBERS);
                            cb->has_error = 1;
                            return;
                        }
                        struct_member_t *mem = &st->members[st->member_count++];
                        memset(mem, 0, sizeof(struct_member_t));
                        strncpy(mem->name, m_id.str_value, 31);
                        mem->name[31] = '\0';
                        mem->offset = cur_offset;
                        mem->size = m_size;
                        mem->elem_size = is_mem_ptr ? orig_elem_sz : m_size;
                        mem->is_array = 0;
                        mem->is_ptr = is_mem_ptr;
                        mem->is_float = is_mem_ptr ? 0 : is_mem_float;
                        if (m_type_str[0]) strncpy(mem->type_name, m_type_str, 31);
                        cur_offset += m_size;
                        lexer_next(l);

                        // Check for array member: ident[size]
                        if (lexer_peek(l).type == TOK_LBRACKET) {
                            lexer_next(l); // eat '['
                            int arr_count = 1;
                            token_t num_tok = lexer_peek(l);
                            if (num_tok.type == TOK_NUMBER) {
                                arr_count = (int)num_tok.int_value;
                                lexer_next(l);
                            } else if (num_tok.type == TOK_IDENT) {
                                symbol_t *c_sym = symbols_lookup_entry(num_tok.str_value);
                                if (c_sym && c_sym->type == SYM_VAR && c_sym->address) {
                                    arr_count = *(int*)c_sym->address;
                                } else if (strcmp(num_tok.str_value, "MAX_WINDOWS") == 0) {
                                    arr_count = 16;
                                }
                                lexer_next(l);
                            }
                            if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'
                            if (arr_count > 1) {
                                cur_offset -= m_size;
                                mem->size = m_size * arr_count;
                                mem->elem_size = m_size;
                                mem->is_array = 1;
                                cur_offset += mem->size;
                            }
                        }
                    }
                }
                if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
            }
            st->total_size = cur_offset;
            if (lexer_peek(l).type == TOK_RBRACE) lexer_next(l);
            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
        }
        return;
    }
}

static void parse_statement(lexer_t *l, code_buffer_t *cb) {
    s_expr_is_float = 0;
    token_t tok = lexer_peek(l);

    // Format String Statement: "Format %d\n", arg1, ...;
    if (tok.type == TOK_STRING) {
        char fmt[2048];
        strncpy(fmt, tok.str_value, 2047);
        fmt[2047] = '\0';
        lexer_next(l);

        int arg_count = 0;
        if (lexer_peek(l).type == TOK_COMMA) {
            while (lexer_peek(l).type == TOK_COMMA) {
                lexer_next(l); // eat ','
                parse_expr(l, cb); // arg in X0
                emit_push_x(cb, 0);
                arg_count++;
            }
        }

        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);

        // Validate % specifiers against argument count
        int spec_count = 0;
        for (const char *p = fmt; *p; p++) {
            if (*p == '%') {
                if (*(p + 1) == '%') p++; // Skip escaped %%
                else spec_count++;
            }
        }
        if (arg_count > 7) {
            printf("[JIT] Error: Print statement with %d arguments exceeds max 7 registers\n", arg_count);
            cb->has_error = 1;
            return;
        }
        if (spec_count > arg_count) {
            printf("[JIT] Warning: Format string '%s' expects %d arguments, but got %d\n", fmt, spec_count, arg_count);
        }

        // Pop args into X1..X7 in reverse
        for (int i = arg_count; i >= 1; i--) {
            if (i < 8) emit_pop_x(cb, i);
            else emit_pop_x(cb, 7);
        }

        char *fmt_copy = (char*)kmalloc(strlen(fmt) + 1);
        if (fmt_copy) strcpy(fmt_copy, fmt);
        emit_mov_imm64(cb, 0, (uint64_t)fmt_copy); // X0 = fmt

        emit_mov_imm64(cb, 16, (uint64_t)doldoc_printf);
        emit_blr(cb, 16);
        return;
    }

    // Class / Struct Definition: class Name { ... };
    if (tok.type == TOK_CLASS || tok.type == TOK_STRUCT) {
        parse_struct_def(l, cb);
        return;
    }

    // If Statement: if (cond) block [else if (cond) block]* [else block]
    if (tok.type == TOK_IF) {
        size_t end_branches[64];
        int end_branch_count = 0;

        while (1) {
            lexer_next(l); // eat 'if'
            if (lexer_peek(l).type == TOK_LPAREN) lexer_next(l);
            parse_expr(l, cb); // Condition in X0
            if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l);
            size_t cbz_idx = emit_cbz_placeholder(cb, 0); // Jump to next branch if false
            parse_block(l, cb);

            if (lexer_peek(l).type == TOK_ELSE) {
                lexer_next(l); // eat 'else'
                if (end_branch_count < 64) {
                    end_branches[end_branch_count++] = emit_b_placeholder(cb); // Jump over remaining blocks
                }
                patch_cbz(cb, cbz_idx, cb->count);
                if (lexer_peek(l).type == TOK_IF) {
                    // Iteratively parse the 'else if' without stack recursion!
                    continue;
                } else {
                    // Final trailing 'else' block
                    parse_block(l, cb);
                    break;
                }
            } else {
                patch_cbz(cb, cbz_idx, cb->count);
                break;
            }
        }

        // Patch all end jumps to after the entire if-else chain
        for (int i = 0; i < end_branch_count; i++) {
            patch_b(cb, end_branches[i], cb->count);
        }
        return;
    }

    // Break Statement: break;
    if (tok.type == TOK_BREAK) {
        lexer_next(l); // eat 'break'
        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
        if (loop_depth > 0) {
            loop_ctx_t *lctx = &loop_stack[loop_depth - 1];
            if (lctx->break_count < MAX_BREAKS_PER_LOOP) {
                lctx->break_patches[lctx->break_count++] = emit_b_placeholder(cb);
            } else {
                printf("[JIT] Error: Maximum breaks per loop (%d) exceeded\n", MAX_BREAKS_PER_LOOP);
                cb->has_error = 1;
            }
        }
        return;
    }

    // Continue Statement: continue;
    if (tok.type == TOK_CONTINUE) {
        lexer_next(l); // eat 'continue'
        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
        // Find nearest enclosing loop (skipping switch)
        for (int d = loop_depth - 1; d >= 0; d--) {
            if (!loop_stack[d].is_switch) {
                if (loop_stack[d].continue_count < MAX_CONTINUES_PER_LOOP) {
                    loop_stack[d].continue_patches[loop_stack[d].continue_count++] = emit_b_placeholder(cb);
                } else {
                    printf("[JIT] Error: Maximum continues per loop (%d) exceeded\n", MAX_CONTINUES_PER_LOOP);
                    cb->has_error = 1;
                }
                break;
            }
        }
        return;
    }

    // While Loop: while (cond) block
    if (tok.type == TOK_WHILE) {
        lexer_next(l); // eat 'while'
        if (loop_depth >= MAX_LOOP_DEPTH) {
            printf("[JIT] Error: Maximum loop nesting depth (%d) exceeded\n", MAX_LOOP_DEPTH);
            cb->has_error = 1;
            return;
        }
        loop_ctx_t *lctx = &loop_stack[loop_depth++];
        memset(lctx, 0, sizeof(loop_ctx_t));
        lctx->is_switch = 0;

        size_t loop_start = cb->count;
        if (lexer_peek(l).type == TOK_LPAREN) lexer_next(l);
        parse_expr(l, cb); // Condition in X0
        if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l);

        size_t exit_branch = emit_cbz_placeholder(cb, 0); // Exit if false
        parse_block(l, cb);

        // Patch continues to jump to loop_start (condition check)
        for (int i = 0; i < lctx->continue_count; i++) {
            patch_b(cb, lctx->continue_patches[i], loop_start);
        }

        size_t loop_back = emit_b_placeholder(cb);
        patch_b(cb, loop_back, loop_start);
        patch_cbz(cb, exit_branch, cb->count);

        // Patch breaks to jump to loop exit
        for (int i = 0; i < lctx->break_count; i++) {
            patch_b(cb, lctx->break_patches[i], cb->count);
        }
        loop_depth--;
        return;
    }

    // Do-While Loop: do block while (cond);
    if (tok.type == TOK_DO) {
        lexer_next(l); // eat 'do'
        if (loop_depth >= MAX_LOOP_DEPTH) {
            printf("[JIT] Error: Maximum loop nesting depth (%d) exceeded\n", MAX_LOOP_DEPTH);
            cb->has_error = 1;
            return;
        }
        loop_ctx_t *lctx = &loop_stack[loop_depth++];
        memset(lctx, 0, sizeof(loop_ctx_t));
        lctx->is_switch = 0;

        size_t loop_start = cb->count;
        parse_block(l, cb);

        // Continue target in do..while is the condition evaluation
        size_t cond_target = cb->count;
        for (int i = 0; i < lctx->continue_count; i++) {
            patch_b(cb, lctx->continue_patches[i], cond_target);
        }

        if (lexer_peek(l).type == TOK_WHILE) lexer_next(l);
        if (lexer_peek(l).type == TOK_LPAREN) lexer_next(l);
        parse_expr(l, cb); // Cond in X0
        if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l);
        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);

        // If cond != 0, branch back to loop_start
        emit_cbnz(cb, 0, loop_start);

        // Patch breaks to jump to loop exit
        for (int i = 0; i < lctx->break_count; i++) {
            patch_b(cb, lctx->break_patches[i], cb->count);
        }
        loop_depth--;
        return;
    }

    // For Loop: for (init; cond; step) block
    if (tok.type == TOK_FOR) {
        lexer_next(l); // eat 'for'
        if (lexer_peek(l).type == TOK_LPAREN) lexer_next(l);

        // 1. Initializer
        if (lexer_peek(l).type != TOK_SEMICOLON) {
            parse_statement(l, cb);
        } else {
            lexer_next(l);
        }

        if (loop_depth >= MAX_LOOP_DEPTH) {
            printf("[JIT] Error: Maximum loop nesting depth (%d) exceeded\n", MAX_LOOP_DEPTH);
            cb->has_error = 1;
            return;
        }
        loop_ctx_t *lctx = &loop_stack[loop_depth++];
        memset(lctx, 0, sizeof(loop_ctx_t));
        lctx->is_switch = 0;

        // 2. Condition
        size_t loop_start = cb->count;
        size_t exit_branch = 0;
        int has_cond = 0;
        if (lexer_peek(l).type != TOK_SEMICOLON) {
            parse_expr(l, cb); // Cond in X0
            exit_branch = emit_cbz_placeholder(cb, 0);
            has_cond = 1;
        }
        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);

        // 3. Step statement: record token position
        lexer_t step_lexer = *l;
        int paren_depth = 1;
        while (lexer_peek(l).type != TOK_EOF) {
            if (lexer_peek(l).type == TOK_LPAREN) paren_depth++;
            else if (lexer_peek(l).type == TOK_RPAREN) {
                paren_depth--;
                if (paren_depth == 0) break;
            }
            lexer_next(l);
        }
        if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l); // eat ')'

        // 4. Body
        parse_block(l, cb);

        // Target for continues in 'for' loop is the step statement
        size_t step_target = cb->count;
        for (int i = 0; i < lctx->continue_count; i++) {
            patch_b(cb, lctx->continue_patches[i], step_target);
        }

        // 5. Execute Step using recorded step_lexer
        lexer_t after_body_lexer = *l;
        *l = step_lexer;
        if (lexer_peek(l).type != TOK_RPAREN) {
            parse_statement(l, cb);
        }

        // Loop back to condition
        size_t loop_back = emit_b_placeholder(cb);
        patch_b(cb, loop_back, loop_start);

        if (has_cond) {
            patch_cbz(cb, exit_branch, cb->count);
        }

        // Patch breaks to jump to loop exit
        for (int i = 0; i < lctx->break_count; i++) {
            patch_b(cb, lctx->break_patches[i], cb->count);
        }
        loop_depth--;

        *l = after_body_lexer;
        return;
    }

    // Switch Statement: switch (expr) { case ...: ... break; default: ... }
    if (tok.type == TOK_SWITCH) {
        lexer_next(l); // eat 'switch'
        if (lexer_peek(l).type == TOK_LPAREN) lexer_next(l);
        parse_expr(l, cb); // Switch expression in X0
        if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l);

        int64_t *sw_slot = (int64_t*)kmalloc(sizeof(int64_t));
        *sw_slot = 0;
        emit_mov_imm64(cb, 16, (uint64_t)sw_slot);
        emit_str_ptr(cb, 0, 16); // *sw_slot = switch value

        if (loop_depth >= MAX_LOOP_DEPTH) {
            printf("[JIT] Error: Maximum switch nesting depth (%d) exceeded\n", MAX_LOOP_DEPTH);
            cb->has_error = 1;
            kfree(sw_slot);
            return;
        }
        loop_ctx_t *lctx = &loop_stack[loop_depth++];
        memset(lctx, 0, sizeof(loop_ctx_t));
        lctx->is_switch = 1;

        switch_ctx_t sw_ctx;
        memset(&sw_ctx, 0, sizeof(switch_ctx_t));
        sw_ctx.val_storage = sw_slot;
        switch_ctx_t *prev_switch_ctx = current_switch_ctx;
        current_switch_ctx = &sw_ctx;

        // Jump over case bodies to dispatch comparison block
        size_t jump_to_dispatch = emit_b_placeholder(cb);

        // Parse switch body
        if (lexer_peek(l).type == TOK_LBRACE) {
            lexer_next(l); // eat '{'
            while (lexer_peek(l).type != TOK_RBRACE && lexer_peek(l).type != TOK_EOF) {
                size_t prev_pos = l->pos;
                parse_statement(l, cb);
                if (cb->has_error) break;
                if (l->pos <= prev_pos && lexer_peek(l).type != TOK_RBRACE && lexer_peek(l).type != TOK_EOF) {
                    jit_syntax_error(l, cb, "Unparsed token '%s' (type %d) inside switch",
                                     l->current.str_value[0] ? l->current.str_value : "<symbol>",
                                     (int)l->current.type);
                    lexer_next(l);
                }
            }
            if (lexer_peek(l).type == TOK_RBRACE) lexer_next(l);
        } else {
            parse_statement(l, cb);
        }

        // Jump over dispatch block to exit
        size_t jump_over_dispatch = emit_b_placeholder(cb);

        // Emit dispatch comparisons
        patch_b(cb, jump_to_dispatch, cb->count);
        emit_mov_imm64(cb, 16, (uint64_t)sw_ctx.val_storage);
        emit_ldr_ptr(cb, 1, 16); // X1 = switch value
        for (int i = 0; i < sw_ctx.case_count; i++) {
            emit_mov_imm64(cb, 0, (uint64_t)sw_ctx.cases[i].value);
            emit_cmp(cb, 1, 0);
            emit_b_cond(cb, 0, sw_ctx.cases[i].code_target); // B.EQ to case body
        }

        if (sw_ctx.has_default) {
            size_t def_b = emit_b_placeholder(cb);
            patch_b(cb, def_b, sw_ctx.default_target);
        }

        // Current count is switch exit
        patch_b(cb, jump_over_dispatch, cb->count);

        // Patch all breaks to switch exit
        for (int i = 0; i < lctx->break_count; i++) {
            patch_b(cb, lctx->break_patches[i], cb->count);
        }
        loop_depth--;
        current_switch_ctx = prev_switch_ctx;
        return;
    }

    // Case Label: case <const>:
    if (tok.type == TOK_CASE) {
        lexer_next(l); // eat 'case'
        int64_t case_val = 0;
        int is_neg = 0;
        if (lexer_peek(l).type == TOK_MINUS) {
            is_neg = 1;
            lexer_next(l);
        }
        token_t val_tok = lexer_peek(l);
        if (val_tok.type == TOK_NUMBER) {
            case_val = is_neg ? -val_tok.int_value : val_tok.int_value;
            lexer_next(l);
        } else if (val_tok.type == TOK_IDENT) {
            symbol_t *csym = symbols_lookup_entry(val_tok.str_value);
            if (csym && csym->type == SYM_VAR && csym->address) {
                case_val = is_neg ? -(*(int64_t*)csym->address) : (*(int64_t*)csym->address);
            } else {
                jit_syntax_error(l, cb, "Undefined constant in case label: '%s'", val_tok.str_value);
            }
            lexer_next(l);
        }
        if (lexer_peek(l).type == TOK_COLON) {
            lexer_next(l); // eat ':'
        }
        if (current_switch_ctx && current_switch_ctx->case_count < MAX_CASES) {
            current_switch_ctx->cases[current_switch_ctx->case_count].value = case_val;
            current_switch_ctx->cases[current_switch_ctx->case_count].code_target = cb->count;
            current_switch_ctx->case_count++;
        } else if (current_switch_ctx) {
            printf("[JIT] Error: Maximum switch cases (%d) exceeded\n", MAX_CASES);
            cb->has_error = 1;
        }
        return;
    }

    // Default Label: default:
    if (tok.type == TOK_DEFAULT) {
        lexer_next(l); // eat 'default'
        if (lexer_peek(l).type == TOK_COLON) {
            lexer_next(l); // eat ':'
        }
        if (current_switch_ctx) {
            current_switch_ctx->default_target = cb->count;
            current_switch_ctx->has_default = 1;
        }
        return;
    }

    // Return statement
    if (tok.type == TOK_RETURN) {
        lexer_next(l);
        if (lexer_peek(l).type != TOK_SEMICOLON) {
            parse_expr(l, cb); // Return value in X0
        }
        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);

        if (current_fn_param_count > 0) {
            emit_mov_reg(cb, 2, 0); // Save return value in scratch register X2
            for (int i = current_fn_param_count - 1; i >= 0; i--) {
                emit_pop_x(cb, 17);
                emit_mov_imm64(cb, 16, (uint64_t)current_fn_param_storages[i]);
                emit_str_ptr(cb, 17, 16);
            }
            emit_mov_reg(cb, 0, 2); // Restore return value into X0
        }

        emit_pop_lr(cb);
        emit_ret(cb);
        return;
    }

    // Type definition, Struct variable, Auto or Function Definition:
    struct_def_t *known_st = find_struct_def(tok.str_value);
    if (tok.type == TOK_TYPE_I64 || tok.type == TOK_TYPE_U0 ||
        tok.type == TOK_TYPE_F64 || tok.type == TOK_TYPE_U8 ||
        tok.type == TOK_TYPE_U16 || tok.type == TOK_TYPE_U32 ||
        tok.type == TOK_AUTO || known_st != NULL) {

        token_type_t base_type = tok.type;
        char st_type_name[32] = {0};
        if (known_st) strncpy(st_type_name, known_st->name, 31);
        int scale = 8;
        if (base_type == TOK_TYPE_U8) scale = 1;
        else if (base_type == TOK_TYPE_U16) scale = 2;
        else if (base_type == TOK_TYPE_U32) scale = 4;
        else scale = 8;

        lexer_next(l); // eat type

        int is_ptr = 0;
        int ptr_depth = 0;
        while (lexer_peek(l).type == TOK_STAR) {
            is_ptr = 1;
            ptr_depth++;
            lexer_next(l); // eat '*'
        }
        if (ptr_depth > 1) {
            scale = 8; // pointer to pointer points to 8-byte pointer
        }

        token_t id_tok = lexer_peek(l);
        if (id_tok.type == TOK_IDENT) {
            char name[64];
            strncpy(name, id_tok.str_value, sizeof(name) - 1);
            name[sizeof(name) - 1] = '\0';
            lexer_next(l); // eat ident

            // Check if this is a Function Definition: Type Ident ( args ) { body }
            if (lexer_peek(l).type == TOK_LPAREN) {
                lexer_next(l); // eat '('

                code_buffer_t fn_cb;
                cb_init_persistent(&fn_cb, 8192);

                symbols_register(name, (void*)fn_cb.code, SYM_FUNC);

                int parent_param_count = current_fn_param_count;
                int64_t *parent_param_storages[8];
                for (int i = 0; i < 8; i++) {
                    parent_param_storages[i] = current_fn_param_storages[i];
                }

                current_fn_param_count = 0;
                while (lexer_peek(l).type != TOK_RPAREN && lexer_peek(l).type != TOK_EOF) {
                    char param_st_name[64] = {0};
                    int is_param_ptr = 0;
                    token_t type_tok = lexer_peek(l);
                    int p_scale = 8;
                    if (type_tok.type == TOK_TYPE_U8) p_scale = 1;
                    else if (type_tok.type == TOK_TYPE_U16) p_scale = 2;
                    else if (type_tok.type == TOK_TYPE_U32) p_scale = 4;
                    else if (find_struct_def(type_tok.str_value)) {
                        struct_def_t *pst = find_struct_def(type_tok.str_value);
                        p_scale = pst->total_size > 0 ? pst->total_size : 8;
                    }
                    else p_scale = 8;

                    if (find_struct_def(type_tok.str_value)) {
                        strncpy(param_st_name, type_tok.str_value, sizeof(param_st_name) - 1);
                        lexer_next(l);
                    } else if ((type_tok.type >= TOK_TYPE_I64 && type_tok.type <= TOK_TYPE_U32) ||
                               type_tok.type == TOK_AUTO) {
                        lexer_next(l);
                    }
                    int p_ptr_depth = 0;
                    while (lexer_peek(l).type == TOK_STAR) {
                        is_param_ptr = 1;
                        p_ptr_depth++;
                        lexer_next(l);
                    }
                    if (p_ptr_depth > 1) {
                        p_scale = 8;
                    }
                    token_t p_tok = lexer_peek(l);
                    if (p_tok.type == TOK_IDENT) {
                        symbol_t *var_sym = symbols_lookup_entry(p_tok.str_value);
                        int64_t *storage = NULL;
                        if (var_sym && var_sym->type == SYM_VAR) {
                            storage = (int64_t*)var_sym->address;
                        } else {
                            storage = (int64_t*)kmalloc(sizeof(int64_t));
                            *storage = 0;
                            symbols_register(p_tok.str_value, storage, SYM_VAR);
                        }

                        register_var_type(p_tok.str_value, p_scale, is_param_ptr, (type_tok.type == TOK_TYPE_F64 && !is_param_ptr) ? 1 : 0, param_st_name[0] ? param_st_name : NULL);

                        if (current_fn_param_count < 8) {
                            current_fn_param_storages[current_fn_param_count++] = storage;
                        }
                        lexer_next(l);
                    }
                    if (lexer_peek(l).type == TOK_COMMA) lexer_next(l);
                }
                if (lexer_peek(l).type == TOK_RPAREN) lexer_next(l); // eat ')'

                fn_frame_t fn_frame;
                memset(&fn_frame, 0, sizeof(fn_frame));
                fn_frame_t *parent_frame = s_frame;
                s_frame = &fn_frame;

                emit_push_lr(&fn_cb);

                // Reserve the function's local-variable stack frame. Its size is only
                // known once the body has been parsed, so patch the MOVZ immediate below.
                size_t frame_sub_patch = fn_cb.count;
                emit_u32(&fn_cb, 0xD2800010); // MOVZ X16, #0
                emit_u32(&fn_cb, 0xCB3063FF); // SUB SP, SP, X16 (extended register)

                // Preserve previous parameter values on stack and assign argument registers
                for (int i = 0; i < current_fn_param_count; i++) {
                    emit_mov_imm64(&fn_cb, 16, (uint64_t)current_fn_param_storages[i]);
                    emit_ldr_ptr(&fn_cb, 17, 16); // X17 = old value of *storage
                    emit_push_x(&fn_cb, 17);      // Save to stack
                    emit_str_ptr(&fn_cb, i, 16);  // *storage = argument register Xi
                }

                parse_block(l, &fn_cb);

                // Finalize the local frame: patch MOVZ X16 with the 16-byte aligned size.
                uint32_t frame_bytes = (fn_frame.frame_size + 15u) & ~15u;
                if (frame_bytes > 0xFFFFu) {
                    printf("[JIT] Error: function stack frame too large (%u bytes)\n",
                           (unsigned int)frame_bytes);
                    cb->has_error = 1;
                    fn_cb.has_error = 1;
                } else {
                    fn_cb.code[frame_sub_patch] = 0xD2800000u | ((frame_bytes & 0xFFFFu) << 5) | 16u;
                }

                // Epilogue: restore previous parameter values from stack
                for (int i = current_fn_param_count - 1; i >= 0; i--) {
                    emit_pop_x(&fn_cb, 17);
                    emit_mov_imm64(&fn_cb, 16, (uint64_t)current_fn_param_storages[i]);
                    emit_str_ptr(&fn_cb, 17, 16);
                }

                emit_pop_lr(&fn_cb);
                emit_ret(&fn_cb);

                s_frame = parent_frame;
                current_fn_param_count = parent_param_count;
                for (int i = 0; i < 8; i++) {
                    current_fn_param_storages[i] = parent_param_storages[i];
                }

                if (fn_cb.has_error) {
                    symbol_t *s = symbols_lookup_entry(name);
                    if (s && s->address == fn_cb.code) s->address = NULL;
                    cb->has_error = 1;
                    cb_release(&fn_cb);
                    printf("[JIT] Error: Function '%s' compilation failed\n", name);
                    return;
                }

                jit_optimize_peephole(&fn_cb);
                cb_commit_persistent(&fn_cb);
                arm64_flush_cache(fn_cb.code, fn_cb.count * sizeof(uint32_t));
                printf("[JIT] Compiled function '%s' to RAM at 0x%p (%u instrs, %zu bytes)\n",
                       name, fn_cb.code, (unsigned int)fn_cb.count, (size_t)(fn_cb.count * sizeof(uint32_t)));
                doldoc_printf("$FG,GREEN$[JIT]$FG$ Function '%s' compiled to RAM (0x%p)\n", name, fn_cb.code);
                return;
            }

            // Check for array declaration: Type name[count]; or Type *name[count];
            int arr_decl_count = 0;
            if (lexer_peek(l).type == TOK_LBRACKET) {
                lexer_next(l); // eat '['
                token_t sz_tok = lexer_peek(l);
                if (sz_tok.type == TOK_NUMBER) {
                    arr_decl_count = (int)sz_tok.int_value;
                    lexer_next(l);
                } else if (sz_tok.type == TOK_IDENT) {
                    symbol_t *c_sym = symbols_lookup_entry(sz_tok.str_value);
                    if (c_sym && c_sym->type == SYM_VAR && c_sym->address) {
                        arr_decl_count = *(int*)c_sym->address;
                    } else if (strcmp(sz_tok.str_value, "MAX_WINDOWS") == 0) {
                        arr_decl_count = 16;
                    }
                    lexer_next(l);
                }
                while (lexer_peek(l).type == TOK_STAR || lexer_peek(l).type == TOK_PLUS) {
                    token_type_t op = lexer_peek(l).type;
                    lexer_next(l);
                    int factor = 1;
                    token_t f_tok = lexer_peek(l);
                    if (f_tok.type == TOK_NUMBER) {
                        factor = (int)f_tok.int_value;
                        lexer_next(l);
                    } else if (f_tok.type == TOK_IDENT) {
                        symbol_t *c_sym = symbols_lookup_entry(f_tok.str_value);
                        if (c_sym && c_sym->type == SYM_VAR && c_sym->address) factor = *(int*)c_sym->address;
                        lexer_next(l);
                    }
                    if (op == TOK_STAR) arr_decl_count *= factor;
                    else arr_decl_count += factor;
                }
                if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'
            }

            if (arr_decl_count > 0) {
                int elem_sz = is_ptr ? 8 : ((known_st && known_st->total_size > 0) ? known_st->total_size : (scale > 0 ? scale : 8));
                size_t total_buf_sz = (size_t)arr_decl_count * elem_sz;

                if (s_frame) {
                    // Function-local array: live in the stack frame so recursion and
                    // re-entrancy are safe (is_ptr = 0 => address IS the base).
                    local_var_t *alv = frame_alloc(name, (uint32_t)total_buf_sz);
                    if (alv) {
                        register_var_type(name, elem_sz, 0, (base_type == TOK_TYPE_F64 && !is_ptr) ? 1 : 0, st_type_name[0] ? st_type_name : NULL);
                        alv->vt.is_array = 1;
                        emit_zero_slot(cb, alv);
                        if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                        return;
                    }
                }

                void *arr_buf = kmalloc(total_buf_sz);
                if (arr_buf) memset(arr_buf, 0, total_buf_sz);

                int64_t *storage = (int64_t*)kmalloc(sizeof(int64_t));
                *storage = (int64_t)arr_buf;
                symbols_register(name, storage, SYM_VAR);
                register_var_type(name, elem_sz, 1, (base_type == TOK_TYPE_F64 && !is_ptr) ? 1 : 0, st_type_name[0] ? st_type_name : NULL);

                if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                return;
            }

            // Normal Variable Declaration: Type [ * ] name = expr;
            size_t alloc_sz = sizeof(int64_t);
            if (known_st && !is_ptr) {
                alloc_sz = known_st->total_size > 8 ? known_st->total_size : 8;
            }
            local_var_t *frame_lv = s_frame ? frame_alloc(name, (uint32_t)alloc_sz) : NULL;
            if (frame_lv) {
                register_var_type(name, scale, is_ptr, (base_type == TOK_TYPE_F64 && !is_ptr) ? 1 : 0, st_type_name[0] ? st_type_name : NULL);
                emit_zero_slot(cb, frame_lv);
                if (lexer_peek(l).type == TOK_EQUAL) {
                    lexer_next(l); // eat '='
                    parse_expr(l, cb); // Result in X0
                    emit_ref_addr(cb, 16, local_ref(frame_lv));
                    emit_str_ptr(cb, 0, 16); // local = X0
                }
            } else {
            symbol_t *existing_sym = symbols_lookup_entry(name);
            int64_t *storage = NULL;
            if (existing_sym && existing_sym->type == SYM_VAR && existing_sym->address && alloc_sz <= sizeof(int64_t)) {
                storage = (int64_t*)existing_sym->address;
            } else {
                storage = (int64_t*)kmalloc(alloc_sz);
                memset(storage, 0, alloc_sz);
                symbols_register(name, storage, SYM_VAR);
            }
            register_var_type(name, scale, is_ptr, (base_type == TOK_TYPE_F64 && !is_ptr) ? 1 : 0, st_type_name[0] ? st_type_name : NULL);

            if (lexer_peek(l).type == TOK_EQUAL) {
                lexer_next(l); // eat '='
                parse_expr(l, cb); // Result in X0
                emit_mov_imm64(cb, 16, (uint64_t)storage);
                emit_str_ptr(cb, 0, 16); // *storage = X0
            }
            }

            while (lexer_peek(l).type == TOK_COMMA) {
                lexer_next(l); // eat ','
                int next_is_ptr = 0;
                while (lexer_peek(l).type == TOK_STAR) {
                    next_is_ptr = 1;
                    lexer_next(l); // eat '*'
                }
                token_t next_id = lexer_peek(l);
                if (next_id.type == TOK_IDENT) {
                    char next_name[64];
                    strncpy(next_name, next_id.str_value, sizeof(next_name) - 1);
                    next_name[sizeof(next_name) - 1] = '\0';
                    lexer_next(l); // eat ident

                    size_t next_alloc_sz = sizeof(int64_t);
                    if (known_st && !next_is_ptr) {
                        next_alloc_sz = known_st->total_size > 8 ? known_st->total_size : 8;
                    }
                    local_var_t *next_lv = s_frame ? frame_alloc(next_name, (uint32_t)next_alloc_sz) : NULL;
                    if (next_lv) {
                        register_var_type(next_name, scale, next_is_ptr, (base_type == TOK_TYPE_F64 && !next_is_ptr) ? 1 : 0, st_type_name[0] ? st_type_name : NULL);
                        emit_zero_slot(cb, next_lv);
                        if (lexer_peek(l).type == TOK_EQUAL) {
                            lexer_next(l); // eat '='
                            parse_expr(l, cb);
                            emit_ref_addr(cb, 16, local_ref(next_lv));
                            emit_str_ptr(cb, 0, 16);
                        }
                    } else {
                    symbol_t *ex_sym = symbols_lookup_entry(next_name);
                    int64_t *next_storage = NULL;
                    if (ex_sym && ex_sym->type == SYM_VAR && ex_sym->address && next_alloc_sz <= sizeof(int64_t)) {
                        next_storage = (int64_t*)ex_sym->address;
                    } else {
                        next_storage = (int64_t*)kmalloc(next_alloc_sz);
                        memset(next_storage, 0, next_alloc_sz);
                        symbols_register(next_name, next_storage, SYM_VAR);
                    }
                    register_var_type(next_name, scale, next_is_ptr, (base_type == TOK_TYPE_F64 && !next_is_ptr) ? 1 : 0, st_type_name[0] ? st_type_name : NULL);

                    if (lexer_peek(l).type == TOK_EQUAL) {
                        lexer_next(l); // eat '='
                        parse_expr(l, cb);
                        emit_mov_imm64(cb, 16, (uint64_t)next_storage);
                        emit_str_ptr(cb, 0, 16);
                    }
                    }
                }
            }

            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
            return;
        }
    }

    // Dereference Assignment: *ptr = expr; or *(U32*)addr = expr;
    if (tok.type == TOK_STAR) {
        // If there is no top-level '=' before the ';', this is a dereference *read*
        // (e.g. "*q;" or "*q + 1;") and must be evaluated as an expression.
        lexer_t star_la = *l;
        int sdepth = 0, star_is_assign = 0;
        while (star_la.current.type != TOK_EOF && star_la.current.type != TOK_SEMICOLON) {
            token_type_t tt = star_la.current.type;
            if (tt == TOK_LPAREN || tt == TOK_LBRACKET) sdepth++;
            else if (tt == TOK_RPAREN || tt == TOK_RBRACKET) { if (sdepth > 0) sdepth--; }
            else if (sdepth == 0 && (tt == TOK_EQUAL || is_compound_assign_tok(tt))) { star_is_assign = 1; break; }
            lexer_next(&star_la);
        }
        if (!star_is_assign) {
            parse_expr(l, cb);
            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
            return;
        }

        lexer_next(l); // eat '*'
        int store_scale = 8;
        if (lexer_peek(l).type == TOK_LPAREN) {
            lexer_t l_chk = *l;
            lexer_next(&l_chk); // eat '('
            token_t t_type = lexer_peek(&l_chk);
            if (t_type.type == TOK_TYPE_U8 || t_type.type == TOK_TYPE_U16 ||
                t_type.type == TOK_TYPE_U32 || t_type.type == TOK_TYPE_I64 ||
                t_type.type == TOK_TYPE_F64) {
                lexer_next(&l_chk); // eat type
                if (lexer_peek(&l_chk).type == TOK_STAR) {
                    lexer_next(&l_chk); // eat '*'
                    if (lexer_peek(&l_chk).type == TOK_RPAREN) {
                        lexer_next(&l_chk); // eat ')'
                        *l = l_chk; // commit cast
                        if (t_type.type == TOK_TYPE_U8) store_scale = 1;
                        else if (t_type.type == TOK_TYPE_U16) store_scale = 2;
                        else if (t_type.type == TOK_TYPE_U32) store_scale = 4;
                        else store_scale = 8;
                    }
                }
            }
        }

        token_t id_tok = lexer_peek(l);
        if (id_tok.type == TOK_IDENT) {
            char ptr_name[64];
            strncpy(ptr_name, id_tok.str_value, 63);
            ptr_name[63] = '\0';
            lexer_next(l); // eat ident

            if (store_scale == 8) {
                var_type_t *vt = lookup_var_type(ptr_name);
                if (vt && vt->is_ptr && vt->scale > 0) {
                    store_scale = vt->scale;
                }
            }

            if (lexer_peek(l).type == TOK_EQUAL) {
                lexer_next(l); // eat '='
                parse_expr(l, cb); // RHS in X0
                emit_push_x(cb, 0); // Save RHS

                uint64_t ptr_ref = lookup_var_ref(ptr_name);
                emit_ref_addr(cb, 16, ptr_ref);
                emit_ldr_ptr(cb, 1, 16); // X1 = target address stored in ptr
                emit_pop_x(cb, 0);       // X0 = RHS value
                if (store_scale == 1) {
                    emit_strb(cb, 0, 1);
                } else if (store_scale == 2) {
                    emit_strh(cb, 0, 1);
                } else if (store_scale == 4) {
                    emit_str32(cb, 0, 1);
                } else {
                    emit_str_ptr(cb, 0, 1);  // *X1 = X0
                }

                if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                return;
            }
        } else {
            // General Address Expression (e.g. *(U32*)(0x0A003E70) = val)
            parse_unary(l, cb); // target address in X0
            emit_push_x(cb, 0); // Save target address

            if (lexer_peek(l).type == TOK_EQUAL) {
                lexer_next(l); // eat '='
                parse_expr(l, cb); // RHS in X0
                emit_pop_x(cb, 1); // X1 = target address
                if (store_scale == 1) {
                    emit_strb(cb, 0, 1);
                } else if (store_scale == 2) {
                    emit_strh(cb, 0, 1);
                } else if (store_scale == 4) {
                    emit_str32(cb, 0, 1);
                } else {
                    emit_str_ptr(cb, 0, 1);
                }

                if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                return;
            } else {
                emit_pop_x(cb, 0);
            }
        }
    }

    // Identifier Statements: ident = expr, ident[i] = expr, ident.field = expr, ident++, ident--
    if (tok.type == TOK_IDENT) {
        lexer_t lookahead = *l;
        lexer_next(&lookahead);

        if (lookahead.current.type == TOK_LBRACKET) {
            // Array Assignment: ident[index] = expr; or ident[i][j] = expr; or compound op
            char arr_name[64];
            strncpy(arr_name, tok.str_value, 63);
            arr_name[63] = '\0';
            lexer_next(l); // eat ident
            lexer_next(l); // eat '['
            parse_expr(l, cb); // index in X0
            if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'

            uint64_t arr_ref = lookup_var_ref(arr_name);
            var_type_t *vt = lookup_var_type(arr_name);
            int scale = vt ? vt->scale : 1;

            if (vt && !vt->is_ptr) {
                emit_ref_addr(cb, 2, arr_ref); // X2 = base (frame-resident array)
            } else {
                emit_ref_addr(cb, 16, arr_ref);
                emit_ldr_ptr(cb, 2, 16); // X2 = base pointer
            }

            emit_mov_imm64(cb, 3, (uint64_t)(scale > 0 ? scale : 1));
            emit_mul(cb, 0, 0, 3);
            emit_add(cb, 2, 2, 0); // X2 = base + index * scale

            // Chained dimensions: [j]...
            while (lexer_peek(l).type == TOK_LBRACKET) {
                emit_ldr64(cb, 2, 2); // X2 = *X2 (dereference row pointer)
                lexer_next(l); // eat '['
                emit_push_x(cb, 2); // save row pointer
                parse_expr(l, cb); // col index in X0
                emit_pop_x(cb, 2); // X2 = row pointer
                emit_mov_imm64(cb, 3, 8); // 8-byte elements
                emit_mul(cb, 0, 0, 3);
                emit_add(cb, 2, 2, 0); // X2 = row + col * 8
                if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'
            }

            // Member access on array element: ident[i].field = expr;
            if (lexer_peek(l).type == TOK_DOT || lexer_peek(l).type == TOK_ARROW) {
                lexer_next(l); // eat '.' or '->'
                token_t f_tok = lexer_peek(l);
                if (f_tok.type == TOK_IDENT) {
                    char field_name[32];
                    strncpy(field_name, f_tok.str_value, 31);
                    field_name[31] = '\0';
                    lexer_next(l);

                    struct_def_t *st = NULL;
                    if (vt && vt->struct_type[0]) st = find_struct_def(vt->struct_type);
                    if (!st) {
                        for (int s = 0; s < struct_def_count; s++) {
                            for (int m = 0; m < struct_defs[s].member_count; m++) {
                                if (strcmp(struct_defs[s].members[m].name, field_name) == 0) {
                                    st = &struct_defs[s];
                                    break;
                                }
                            }
                            if (st) break;
                        }
                    }
                    if (st) {
                        for (int m = 0; m < st->member_count; m++) {
                            if (strcmp(st->members[m].name, field_name) == 0) {
                                emit_mov_imm64(cb, 3, (uint64_t)st->members[m].offset);
                                emit_add(cb, 2, 2, 3); // X2 = elem_addr + offset
                                scale = st->members[m].size;
                                break;
                            }
                        }
                    }
                }
            }

            token_type_t op_type = lexer_peek(l).type;
            if (op_type == TOK_EQUAL || is_compound_assign_tok(op_type)) {
                lexer_next(l); // eat '=' or 'op='
                emit_push_x(cb, 2); // save target address X2
                parse_expr(l, cb); // RHS in X0

                if (is_compound_assign_tok(op_type)) {
                    emit_pop_x(cb, 2); // X2 = target address
                    emit_push_x(cb, 2); // save again
                    if (scale == 1) emit_ldrb(cb, 1, 2);
                    else if (scale == 2) emit_ldrh(cb, 1, 2);
                    else if (scale == 4) emit_ldr32(cb, 1, 2);
                    else emit_ldr64(cb, 1, 2); // X1 = old val
                    emit_compound_op(cb, op_type); // X0 = X1 (op) X0
                }
                emit_pop_x(cb, 2); // X2 = target address
                if (scale == 1) emit_strb(cb, 0, 2);
                else if (scale == 2) emit_strh(cb, 0, 2);
                else if (scale == 4) emit_str32(cb, 0, 2);
                else emit_str64(cb, 0, 2);

                if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                return;
            }
        } else if (lookahead.current.type == TOK_DOT || lookahead.current.type == TOK_ARROW) {
            lexer_t dot_la = *l;
            lexer_next(&dot_la); // past ident
            int is_member_assign = 0;
            int is_member_arr_assign = 0;
            int is_member_inc = 0;
            while (dot_la.current.type == TOK_DOT || dot_la.current.type == TOK_ARROW) {
                lexer_next(&dot_la); // past '.' or '->'
                if (dot_la.current.type != TOK_IDENT) break;
                lexer_next(&dot_la); // past field ident
            }
            if (dot_la.current.type == TOK_EQUAL || is_compound_assign_tok(dot_la.current.type)) {
                is_member_assign = 1;
            } else if (dot_la.current.type == TOK_PLUSPLUS || dot_la.current.type == TOK_MINUSMINUS) {
                is_member_inc = 1;
            } else if (dot_la.current.type == TOK_LBRACKET) {
                int bracket_depth = 1;
                lexer_next(&dot_la); // past '['
                while (dot_la.current.type != TOK_EOF && bracket_depth > 0) {
                    if (dot_la.current.type == TOK_LBRACKET) bracket_depth++;
                    else if (dot_la.current.type == TOK_RBRACKET) bracket_depth--;
                    lexer_next(&dot_la);
                }
                if (bracket_depth == 0 && (dot_la.current.type == TOK_EQUAL || is_compound_assign_tok(dot_la.current.type))) {
                    is_member_arr_assign = 1;
                }
            }

            if (is_member_arr_assign) {
                // Member Array Assignment: ident.f1...fN[index] = expr; or ident->f1...fN[index] = expr;
                char var_name[64];
                strncpy(var_name, tok.str_value, 63);
                var_name[63] = '\0';
                lexer_next(l); // eat ident

                char field_chain[16][32];
                int chain_len = 0;
                while ((lexer_peek(l).type == TOK_DOT || lexer_peek(l).type == TOK_ARROW) && chain_len < 16) {
                    lexer_next(l); // eat '.' or '->'
                    token_t f_tok = lexer_peek(l);
                    if (f_tok.type == TOK_IDENT) {
                        strncpy(field_chain[chain_len], f_tok.str_value, 31);
                        field_chain[chain_len][31] = '\0';
                        chain_len++;
                        lexer_next(l); // eat field ident
                    } else {
                        break;
                    }
                }

                if (lexer_peek(l).type == TOK_LBRACKET) {
                    lexer_next(l); // eat '['
                    parse_expr(l, cb); // index in X0
                    emit_push_x(cb, 0); // save index
                    if (lexer_peek(l).type == TOK_RBRACKET) lexer_next(l); // eat ']'
                }

                token_type_t op_type = lexer_peek(l).type;
                if (op_type == TOK_EQUAL || is_compound_assign_tok(op_type)) {
                    lexer_next(l); // eat '=' or op=
                    parse_expr(l, cb); // RHS in X0
                    emit_push_x(cb, 0); // save RHS

                    uint64_t var_ref = lookup_var_ref(var_name);

                    var_type_t *vt = lookup_var_type(var_name);
                    char cur_st_name[32] = {0};
                    if (vt && vt->struct_type[0] != '\0') {
                        strncpy(cur_st_name, vt->struct_type, 31);
                    }

                    if (vt && vt->is_ptr) {
                        emit_ref_addr(cb, 16, var_ref);
                        emit_ldr_ptr(cb, 1, 16); // X1 = *storage (pointer to struct)
                    } else {
                        emit_ref_addr(cb, 1, var_ref); // X1 = storage (direct base)
                    }

                    int elem_sz = 8;
                    for (int k = 0; k < chain_len; k++) {
                        struct_def_t *st = NULL;
                        if (cur_st_name[0] != '\0') {
                            st = find_struct_def(cur_st_name);
                        }
                        if (!st) {
                            for (int s = 0; s < struct_def_count; s++) {
                                for (int m = 0; m < struct_defs[s].member_count; m++) {
                                    if (strcmp(struct_defs[s].members[m].name, field_chain[k]) == 0) {
                                        st = &struct_defs[s];
                                        break;
                                    }
                                }
                                if (st) break;
                            }
                        }
                        if (!st) {
                            cb->has_error = 1;
                            snprintf(cb->error_msg, sizeof(cb->error_msg),
                                     "Type error: unknown struct for member '%s'", field_chain[k]);
                            printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                            return;
                        }

                        int found = 0;
                        int offset = 0;
                        int is_arr = 0;
                        int is_ptr = 0;
                        char sub_st[32] = {0};
                        for (int m = 0; m < st->member_count; m++) {
                            if (strcmp(st->members[m].name, field_chain[k]) == 0) {
                                offset = st->members[m].offset;
                                is_arr = st->members[m].is_array;
                                is_ptr = st->members[m].is_ptr;
                                if (st->members[m].elem_size > 0) elem_sz = st->members[m].elem_size;
                                if (st->members[m].type_name[0]) {
                                    strncpy(sub_st, st->members[m].type_name, 31);
                                }
                                found = 1;
                                break;
                            }
                        }
                        if (!found) {
                            cb->has_error = 1;
                            snprintf(cb->error_msg, sizeof(cb->error_msg),
                                     "Type error: struct '%s' has no member '%s'", st->name, field_chain[k]);
                            printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                            return;
                        }

                        emit_mov_imm64(cb, 2, (uint64_t)offset);
                        emit_add(cb, 1, 1, 2); // X1 = &current->field

                        if (k < chain_len - 1) {
                            if (sub_st[0]) {
                                strncpy(cur_st_name, sub_st, 31);
                            }
                            if (is_ptr) {
                                emit_ldr64(cb, 1, 1);
                            }
                        } else {
                            if (!is_arr) {
                                emit_ldr64(cb, 1, 1); // pointer to array
                            }
                        }
                    }

                    emit_pop_x(cb, 0); // X0 = RHS value
                    emit_pop_x(cb, 2); // X2 = index
                    emit_mov_imm64(cb, 3, (uint64_t)elem_sz);
                    emit_mul(cb, 2, 2, 3);
                    emit_add(cb, 1, 1, 2); // X1 = base + index * elem_sz

                    if (is_compound_assign_tok(op_type)) {
                        emit_mov_reg(cb, 2, 1); // X2 = target address
                        if (elem_sz == 1) emit_ldrb(cb, 1, 2);
                        else if (elem_sz == 2) emit_ldrh(cb, 1, 2);
                        else if (elem_sz == 4) emit_ldr32(cb, 1, 2);
                        else emit_ldr64(cb, 1, 2); // X1 = old val
                        emit_compound_op(cb, op_type); // X0 = X1 (op) X0
                        emit_mov_reg(cb, 1, 2); // X1 = target address
                    }

                    if (elem_sz == 1) emit_strb(cb, 0, 1);
                    else if (elem_sz == 2) emit_strh(cb, 0, 1);
                    else if (elem_sz == 4) emit_str32(cb, 0, 1);
                    else emit_str64(cb, 0, 1);

                    if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                    return;
                }
            }

            if (is_member_inc) {
                // Member Increment / Decrement: ident.f1...fN++; or --;
                char var_name[64];
                strncpy(var_name, tok.str_value, 63);
                var_name[63] = '\0';
                lexer_next(l); // eat ident

                char field_chain[16][32];
                int chain_len = 0;
                while ((lexer_peek(l).type == TOK_DOT || lexer_peek(l).type == TOK_ARROW) && chain_len < 16) {
                    lexer_next(l); // eat '.' or '->'
                    token_t f_tok = lexer_peek(l);
                    if (f_tok.type == TOK_IDENT) {
                        strncpy(field_chain[chain_len], f_tok.str_value, 31);
                        field_chain[chain_len][31] = '\0';
                        chain_len++;
                        lexer_next(l);
                    } else {
                        break;
                    }
                }

                token_type_t inc_type = lexer_peek(l).type;
                lexer_next(l); // eat '++' or '--'

                uint64_t var_ref = lookup_var_ref(var_name);

                var_type_t *vt = lookup_var_type(var_name);
                char cur_st_name[32] = {0};
                if (vt && vt->struct_type[0] != '\0') {
                    strncpy(cur_st_name, vt->struct_type, 31);
                }

                if (vt && vt->is_ptr) {
                    emit_ref_addr(cb, 16, var_ref);
                    emit_ldr_ptr(cb, 1, 16); // X1 = *storage (pointer to struct)
                } else {
                    emit_ref_addr(cb, 1, var_ref); // X1 = storage (direct base)
                }

                int fsize = 8;
                for (int k = 0; k < chain_len; k++) {
                    struct_def_t *st = NULL;
                    if (cur_st_name[0] != '\0') {
                        st = find_struct_def(cur_st_name);
                    }
                    if (!st) {
                        for (int s = 0; s < struct_def_count; s++) {
                            for (int m = 0; m < struct_defs[s].member_count; m++) {
                                if (strcmp(struct_defs[s].members[m].name, field_chain[k]) == 0) {
                                    st = &struct_defs[s];
                                    break;
                                }
                            }
                            if (st) break;
                        }
                    }
                    if (!st) {
                        cb->has_error = 1;
                        snprintf(cb->error_msg, sizeof(cb->error_msg),
                                 "Type error: unknown struct for member '%s'", field_chain[k]);
                        printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                        return;
                    }

                    int found = 0;
                    int offset = 0;
                    int is_ptr = 0;
                    char sub_st[32] = {0};
                    for (int m = 0; m < st->member_count; m++) {
                        if (strcmp(st->members[m].name, field_chain[k]) == 0) {
                            offset = st->members[m].offset;
                            fsize = st->members[m].size;
                            is_ptr = st->members[m].is_ptr;
                            if (st->members[m].type_name[0]) {
                                strncpy(sub_st, st->members[m].type_name, 31);
                            }
                            found = 1;
                            break;
                        }
                    }
                    if (!found) {
                        cb->has_error = 1;
                        snprintf(cb->error_msg, sizeof(cb->error_msg),
                                 "Type error: struct '%s' has no member '%s'", st->name, field_chain[k]);
                        printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                        return;
                    }

                    emit_mov_imm64(cb, 2, (uint64_t)offset);
                    emit_add(cb, 1, 1, 2); // X1 = base + offset

                    if (k < chain_len - 1) {
                        if (sub_st[0]) {
                            strncpy(cur_st_name, sub_st, 31);
                        }
                        if (is_ptr) {
                            emit_ldr64(cb, 1, 1);
                        }
                    }
                }

                if (fsize == 1) emit_ldrb(cb, 0, 1);
                else if (fsize == 2) emit_ldrh(cb, 0, 1);
                else if (fsize == 4) emit_ldr32(cb, 0, 1);
                else emit_ldr64(cb, 0, 1);

                emit_mov_imm64(cb, 2, 1);
                if (inc_type == TOK_PLUSPLUS) {
                    emit_add(cb, 0, 0, 2);
                } else {
                    emit_sub(cb, 0, 0, 2);
                }

                if (fsize == 1) emit_strb(cb, 0, 1);
                else if (fsize == 2) emit_strh(cb, 0, 1);
                else if (fsize == 4) emit_str32(cb, 0, 1);
                else emit_str64(cb, 0, 1);

                if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                return;
            }

            if (is_member_assign) {
                // Member Assignment: ident.field1...fieldN = expr; or op= expr;
                char var_name[64];
                strncpy(var_name, tok.str_value, 63);
                var_name[63] = '\0';
                lexer_next(l); // eat ident

                char field_chain[16][32];
                int chain_len = 0;
                while ((lexer_peek(l).type == TOK_DOT || lexer_peek(l).type == TOK_ARROW) && chain_len < 16) {
                    lexer_next(l); // eat '.' or '->'
                    token_t f_tok = lexer_peek(l);
                    if (f_tok.type == TOK_IDENT) {
                        strncpy(field_chain[chain_len], f_tok.str_value, 31);
                        field_chain[chain_len][31] = '\0';
                        chain_len++;
                        lexer_next(l);
                    } else {
                        break;
                    }
                }

                token_type_t op_type = lexer_peek(l).type;
                if (op_type == TOK_EQUAL || is_compound_assign_tok(op_type)) {
                    lexer_next(l); // eat '=' or 'op='
                    parse_expr(l, cb); // RHS in X0
                    emit_push_x(cb, 0); // save RHS

                    uint64_t var_ref = lookup_var_ref(var_name);

                    var_type_t *vt = lookup_var_type(var_name);
                    char cur_st_name[32] = {0};
                    if (vt && vt->struct_type[0] != '\0') {
                        strncpy(cur_st_name, vt->struct_type, 31);
                    }

                    if (chain_len == 1 && (!vt || vt->struct_type[0] == '\0')) {
                        int is_st = 0;
                        for (int s = 0; s < struct_def_count; s++) {
                            for (int m = 0; m < struct_defs[s].member_count; m++) {
                                if (strcmp(struct_defs[s].members[m].name, field_chain[0]) == 0) {
                                    is_st = 1;
                                    break;
                                }
                            }
                            if (is_st) break;
                        }
                        if (!is_st) {
                            // Dynamic Table set: table_set(tbl, field, val)
                            emit_pop_x(cb, 2); // RHS in X2
                            emit_ref_addr(cb, 16, var_ref);
                            emit_ldr_ptr(cb, 0, 16); // X0 = tbl

                            char *f_copy = (char*)kmalloc(strlen(field_chain[0]) + 1);
                            if (f_copy) strcpy(f_copy, field_chain[0]);
                            emit_mov_imm64(cb, 1, (uint64_t)f_copy); // X1 = key

                            emit_mov_imm64(cb, 16, (uint64_t)table_set);
                            emit_blr(cb, 16);

                            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                            return;
                        }
                    }

                    if (vt && vt->is_ptr) {
                        emit_ref_addr(cb, 16, var_ref);
                        emit_ldr_ptr(cb, 1, 16); // X1 = *storage (pointer to struct)
                    } else {
                        emit_ref_addr(cb, 1, var_ref); // X1 = storage (direct base)
                    }

                    int fsize = 8;
                    for (int k = 0; k < chain_len; k++) {
                        struct_def_t *st = NULL;
                        if (cur_st_name[0] != '\0') {
                            st = find_struct_def(cur_st_name);
                        }
                        if (!st) {
                            for (int s = 0; s < struct_def_count; s++) {
                                for (int m = 0; m < struct_defs[s].member_count; m++) {
                                    if (strcmp(struct_defs[s].members[m].name, field_chain[k]) == 0) {
                                        st = &struct_defs[s];
                                        break;
                                    }
                                }
                                if (st) break;
                            }
                        }
                        if (!st) {
                            cb->has_error = 1;
                            snprintf(cb->error_msg, sizeof(cb->error_msg),
                                     "Type error: unknown struct for member '%s'", field_chain[k]);
                            printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                            return;
                        }

                        int found = 0;
                        int offset = 0;
                        int is_ptr = 0;
                        char sub_st[32] = {0};
                        for (int m = 0; m < st->member_count; m++) {
                            if (strcmp(st->members[m].name, field_chain[k]) == 0) {
                                offset = st->members[m].offset;
                                fsize = st->members[m].size;
                                is_ptr = st->members[m].is_ptr;
                                if (st->members[m].type_name[0]) {
                                    strncpy(sub_st, st->members[m].type_name, 31);
                                }
                                found = 1;
                                break;
                            }
                        }
                        if (!found) {
                            cb->has_error = 1;
                            snprintf(cb->error_msg, sizeof(cb->error_msg),
                                     "Type error: struct '%s' has no member '%s'", st->name, field_chain[k]);
                            printf("[JIT TYPE-CHECK] %s\n", cb->error_msg);
                            return;
                        }

                        emit_mov_imm64(cb, 2, (uint64_t)offset);
                        emit_add(cb, 1, 1, 2); // X1 = base + offset

                        if (k < chain_len - 1) {
                            if (sub_st[0]) {
                                strncpy(cur_st_name, sub_st, 31);
                            }
                            if (is_ptr) {
                                emit_ldr64(cb, 1, 1);
                            }
                        }
                    }

                    if (is_compound_assign_tok(op_type)) {
                        emit_mov_reg(cb, 2, 1); // X2 = target address
                        if (fsize == 1) emit_ldrb(cb, 1, 2);
                        else if (fsize == 2) emit_ldrh(cb, 1, 2);
                        else if (fsize == 4) emit_ldr32(cb, 1, 2);
                        else emit_ldr64(cb, 1, 2); // X1 = old val
                        emit_pop_x(cb, 0); // X0 = RHS
                        emit_compound_op(cb, op_type); // X0 = X1 (op) X0
                        emit_mov_reg(cb, 1, 2); // X1 = target address
                    } else {
                        emit_pop_x(cb, 0); // X0 = RHS
                    }

                    if (fsize == 1) emit_strb(cb, 0, 1);
                    else if (fsize == 2) emit_strh(cb, 0, 1);
                    else if (fsize == 4) emit_str32(cb, 0, 1);
                    else emit_str64(cb, 0, 1);

                    if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
                    return;
                }
            }
        } else if (lookahead.current.type == TOK_PLUSPLUS || lookahead.current.type == TOK_MINUSMINUS) {
            // Standalone Increment / Decrement: ident++; or ident--;
            char var_name[64];
            strncpy(var_name, tok.str_value, 63);
            lexer_next(l); // eat ident
            token_type_t inc_type = lexer_peek(l).type;
            lexer_next(l); // eat '++' or '--'

            uint64_t var_ref = lookup_var_ref(var_name);
            if (var_ref) {
                emit_ref_addr(cb, 16, var_ref);
                emit_ldr_ptr(cb, 0, 16); // X0 = old val
                emit_mov_imm64(cb, 1, 1);
                if (inc_type == TOK_PLUSPLUS) {
                    emit_add(cb, 0, 0, 1);
                } else {
                    emit_sub(cb, 0, 0, 1);
                }
                emit_str_ptr(cb, 0, 16); // *storage = new val
            }

            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
            return;
        } else if (is_compound_assign_tok(lookahead.current.type)) {
            // Compound Assignment: ident op= expr;
            char var_name[64];
            strncpy(var_name, tok.str_value, 63);
            var_name[63] = '\0';
            lexer_next(l); // eat ident
            token_type_t op_type = lexer_peek(l).type;
            lexer_next(l); // eat 'op='

            parse_expr(l, cb); // RHS in X0
            uint64_t var_ref = lookup_var_ref(var_name);
            if (var_ref) {
                emit_ref_addr(cb, 16, var_ref);
                emit_ldr_ptr(cb, 1, 16); // X1 = old val
                emit_compound_op(cb, op_type); // X0 = X1 (op) X0
                emit_str_ptr(cb, 0, 16);
            }

            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
            return;
        } else if (lookahead.current.type == TOK_EQUAL) {
            char var_name[64];
            strncpy(var_name, tok.str_value, sizeof(var_name) - 1);
            var_name[sizeof(var_name) - 1] = '\0';
            lexer_next(l); // eat ident
            lexer_next(l); // eat '='

            uint64_t var_ref = lookup_var_ref(var_name);
            if (!var_ref) {
                int64_t *storage = (int64_t*)kmalloc(sizeof(int64_t));
                *storage = 0;
                symbols_register(var_name, storage, SYM_VAR);
                var_ref = (uint64_t)storage;
            }

            parse_expr(l, cb); // Result in X0
            emit_ref_addr(cb, 16, var_ref);
            emit_str_ptr(cb, 0, 16); // *storage = X0

            if (lexer_peek(l).type == TOK_SEMICOLON) lexer_next(l);
            return;
        }
    }

    // Default: Expression statement
    parse_expr(l, cb);
    if (lexer_peek(l).type == TOK_SEMICOLON) {
        lexer_next(l);
    }
}

void jit_init(void) {
    symbols_register("table_create", (void*)table_create, SYM_FUNC);
    symbols_register("table_set", (void*)table_set, SYM_FUNC);
    symbols_register("table_get", (void*)table_get, SYM_FUNC);
    symbols_register("table_has", (void*)table_has, SYM_FUNC);
    printf("[JIT] HolyC 2.0 AArch64 Machine Code Compiler ready (TempleOS SASOS Mode)\n");
}

int64_t jit_eval(const char *expr_source) {
    if (!expr_source || !*expr_source) return 0;

    lexer_t l;
    code_buffer_t cb;
    cb_init_scratch(&cb, 2048);

    lexer_init(&l, expr_source);
    emit_push_lr(&cb);

    if (lexer_peek(&l).type == TOK_RETURN) {
        lexer_next(&l);
    }

    parse_expr(&l, &cb);

    emit_pop_lr(&cb);
    emit_ret(&cb);

    if (cb.has_error) {
        printf("[JIT] Evaluation aborted due to compilation error.\n");
        cb_release(&cb);
        return 0;
    }

    jit_optimize_peephole(&cb);
    arm64_flush_cache(cb.code, cb.count * sizeof(uint32_t));

    jit_func_t fn = (jit_func_t)cb.code;
    int64_t result = fn();

    cb_release(&cb);
    return result;
}

int64_t jit_execute_statement(const char *code) {
    return jit_compile_and_run(code);
}

// Type pre-pass: parse every struct/class definition first so that forward
// references (pointers to types defined later in the same unit, member access)
// resolve correctly during the real compile pass. Definitions are re-parsed in
// the main pass (idempotent: the entry is memset and refilled).
static void prescan_struct_defs(const char *source) {
    lexer_t scan;
    lexer_init(&scan, source);
    code_buffer_t dummy;
    cb_init_scratch(&dummy, 16);
    while (1) {
        token_t t = lexer_peek(&scan);
        if (t.type == TOK_EOF) break;
        if (t.type == TOK_STRUCT || t.type == TOK_CLASS) {
            parse_struct_def(&scan, &dummy);
        } else {
            lexer_next(&scan);
        }
    }
    cb_release(&dummy);
}

// RedSea file reader (registered as a JIT symbol; declared here for the preprocessor).
extern int redsea_read_file(const char *filename, void *buffer, size_t max_bytes, size_t *out_size);

#define INCLUDE_MAX_DEPTH 8
#define INCLUDE_BUF_SIZE  (256 * 1024)

// Expand `#include "file"` directives recursively by splicing file contents
// (read from RedSea). Returns the number of bytes written to `out`.
static size_t expand_includes(const char *src, char *out, size_t cap, int depth) {
    if (depth > INCLUDE_MAX_DEPTH) return 0;
    size_t o = 0;
    const char *p = src;
    while (*p) {
        if ((p == src || p[-1] == '\n') && p[0] == '#') {
            const char *q = p + 1;
            while (*q == ' ' || *q == '\t') q++;
            if (strncmp(q, "include", 7) == 0) {
                q += 7;
                while (*q == ' ' || *q == '\t') q++;
                if (*q == '"') {
                    q++;
                    char name[64];
                    int n = 0;
                    while (*q && *q != '"' && *q != '\n' && n < 63) name[n++] = *q++;
                    name[n] = '\0';
                    if (*q == '"') q++;
                    char *fb = (char*)kmalloc(INCLUDE_BUF_SIZE);
                    if (fb) {
                        size_t len = 0;
                        if (redsea_read_file(name, fb, INCLUDE_BUF_SIZE - 1, &len) == 0) {
                            fb[len] = '\0';
                            o += expand_includes(fb, out + o, cap - o, depth + 1);
                        } else {
                            printf("[JIT] #include: cannot read '%s'\n", name);
                        }
                        kfree(fb);
                    }
                    while (*q && *q != '\n') q++;
                    p = q;
                    continue;
                }
            }
        }
        if (o + 1 < cap) out[o++] = *p;
        p++;
    }
    if (o < cap) out[o] = '\0';
    return o;
}

int64_t jit_compile_and_run(const char *source) {
    if (!source || !*source) return 0;

    lexer_t l;
    code_buffer_t cb;
    cb_init_scratch(&cb, 8192);

    // Expand #include directives (only if present) before parsing.
    char *expanded = NULL;
    const char *src = source;
    if (strstr(source, "#include")) {
        expanded = (char*)kmalloc(INCLUDE_BUF_SIZE);
        if (expanded) {
            expand_includes(source, expanded, INCLUDE_BUF_SIZE, 0);
            src = expanded;
        }
    }

    lexer_init(&l, src);
    prescan_struct_defs(src);
    emit_push_lr(&cb);

    while (lexer_peek(&l).type != TOK_EOF) {
        size_t prev_pos = l.pos;
        parse_statement(&l, &cb);
        if (cb.has_error) break;
        if (l.pos <= prev_pos && lexer_peek(&l).type != TOK_EOF) {
            jit_syntax_error(&l, &cb, "Unparsed token '%s' (type %d) at top level",
                             l.current.str_value[0] ? l.current.str_value : "<symbol>",
                             (int)l.current.type);
            lexer_next(&l); // GUARANTEE forward progress: never hang!
        }
    }

    if (expanded) kfree(expanded);
    emit_pop_lr(&cb);
    emit_ret(&cb);

    if (cb.has_error) {
        printf("[JIT] Execution aborted due to compilation error.\n");
        cb_release(&cb);
        return -1;
    }

    printf("[DEBUG-JIT] cb.count = %u instrs before peephole\n", (unsigned int)cb.count);
    jit_optimize_peephole(&cb);
    printf("[DEBUG-JIT] cb.count = %u instrs after peephole\n", (unsigned int)cb.count);
    arm64_flush_cache(cb.code, cb.count * sizeof(uint32_t));
    printf("[DEBUG-JIT] Calling fn() at %p...\n", cb.code);

    jit_func_t fn = (jit_func_t)cb.code;
    int64_t result = fn();
    printf("[DEBUG-JIT] fn() returned %lld\n", (long long)result);

    cb_release(&cb);
    return result;
}

int jit_run_self_tests(void) {
    int passed = 0;
    int total = 12;

    doldoc_print("$FG,CYAN$=======================================================$FG$\n");
    doldoc_print("$FG,WHITE$ NeoOS HolyC 2.0 JIT Advanced Feature Self-Tests$FG$\n");
    doldoc_print("$FG,CYAN$=======================================================$FG$\n");

    // 1. Ternary Operator
    int64_t t1 = jit_eval("(10 > 5) ? 42 : 99");
    int64_t t2 = jit_eval("(3 > 8) ? 42 : 99");
    if (t1 == 42 && t2 == 99) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 1. Ternary (? :): (10>5)?42:99=%lld, (3>8)?42:99=%lld\n", (long long)t1, (long long)t2);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 1. Ternary: got t1=%lld, t2=%lld\n", (long long)t1, (long long)t2);
    }

    // 2. Do-While Loop
    jit_compile_and_run("I64 d_test = 0; do { d_test = d_test + 1; } while (d_test < 5);");
    symbol_t *s_d = symbols_lookup_entry("d_test");
    int64_t v_d = s_d ? *(int64_t*)s_d->address : 0;
    if (v_d == 5) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 2. Do-While Loop: counter reached %lld\n", (long long)v_d);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 2. Do-While Loop: expected 5, got %lld\n", (long long)v_d);
    }

    // 3. While Loop with Break & Continue
    jit_compile_and_run(
        "I64 w_ctr = 0;\n"
        "I64 w_sum = 0;\n"
        "while (w_ctr < 10) {\n"
        "    w_ctr = w_ctr + 1;\n"
        "    if (w_ctr == 3) continue;\n"
        "    if (w_ctr == 7) break;\n"
        "    w_sum = w_sum + w_ctr;\n"
        "}\n"
    );
    symbol_t *s_wsum = symbols_lookup_entry("w_sum");
    int64_t v_wsum = s_wsum ? *(int64_t*)s_wsum->address : 0;
    symbol_t *s_wctr = symbols_lookup_entry("w_ctr");
    int64_t v_wctr = s_wctr ? *(int64_t*)s_wctr->address : 0;
    if (v_wsum == 18 && v_wctr == 7) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 3. While (Break & Continue): sum=%lld, ctr=%lld\n", (long long)v_wsum, (long long)v_wctr);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 3. While Loop: expected sum=18 ctr=7, got sum=%lld ctr=%lld\n", (long long)v_wsum, (long long)v_wctr);
    }

    // 4. For Loop with Break & Continue
    jit_compile_and_run(
        "I64 f_sum = 0;\n"
        "for (I64 fi = 0; fi < 10; fi++) {\n"
        "    if (fi == 2) continue;\n"
        "    if (fi == 6) break;\n"
        "    f_sum = f_sum + fi;\n"
        "}\n"
    );
    symbol_t *s_fsum = symbols_lookup_entry("f_sum");
    int64_t v_fsum = s_fsum ? *(int64_t*)s_fsum->address : 0;
    if (v_fsum == 13) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 4. For (Break & Continue): f_sum=%lld\n", (long long)v_fsum);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 4. For Loop: expected f_sum=13, got %lld\n", (long long)v_fsum);
    }

    // 5. Switch-Case with Break
    jit_compile_and_run(
        "I64 sw_in = 2;\n"
        "I64 sw_out = 0;\n"
        "switch (sw_in) {\n"
        "    case 1: sw_out = 100; break;\n"
        "    case 2: sw_out = 200; break;\n"
        "    case 3: sw_out = 300; break;\n"
        "    default: sw_out = 999; break;\n"
        "}\n"
    );
    symbol_t *s_swout = symbols_lookup_entry("sw_out");
    int64_t v_swout = s_swout ? *(int64_t*)s_swout->address : 0;
    if (v_swout == 200) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 5. Switch-Case Dispatch with Break: matched case 2 -> %lld\n", (long long)v_swout);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 5. Switch-Case: expected 200, got %lld\n", (long long)v_swout);
    }

    // 6. Switch-Case Fallthrough
    jit_compile_and_run(
        "I64 ft_in = 1;\n"
        "I64 ft_out = 10;\n"
        "switch (ft_in) {\n"
        "    case 1: ft_out += 20;\n"
        "    case 2: ft_out += 30; break;\n"
        "    default: ft_out = 999; break;\n"
        "}\n"
    );
    symbol_t *s_ftout = symbols_lookup_entry("ft_out");
    int64_t v_ftout = s_ftout ? *(int64_t*)s_ftout->address : 0;
    if (v_ftout == 60) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 6. Switch-Case Fallthrough: 10 + 20 + 30 = %lld\n", (long long)v_ftout);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 6. Switch Fallthrough: expected 60, got %lld\n", (long long)v_ftout);
    }

    // 7. Switch Default Handler
    jit_compile_and_run(
        "I64 def_in = 77;\n"
        "I64 def_out = 0;\n"
        "switch (def_in) {\n"
        "    case 1: def_out = 10; break;\n"
        "    case 2: def_out = 20; break;\n"
        "    default: def_out = 888; break;\n"
        "}\n"
    );
    symbol_t *s_defout = symbols_lookup_entry("def_out");
    int64_t v_defout = s_defout ? *(int64_t*)s_defout->address : 0;
    if (v_defout == 888) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 7. Switch Default Handler: input 77 matched default -> %lld\n", (long long)v_defout);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 7. Switch Default: expected 888, got %lld\n", (long long)v_defout);
    }

    // 8. Class / Struct Declaration & Member Access
    jit_compile_and_run(
        "class Vec2D { I64 x; I64 y; };\n"
        "Vec2D v;\n"
        "v.x = 25;\n"
        "v.y = 75;\n"
        "I64 v_sum = v.x + v.y;\n"
    );
    symbol_t *s_vsum = symbols_lookup_entry("v_sum");
    int64_t v_val = s_vsum ? *(int64_t*)s_vsum->address : 0;
    if (v_val == 100) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 8. Class / Struct Member Access: v.x(25) + v.y(75) = %lld\n", (long long)v_val);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 8. Class / Struct: expected 100, got %lld\n", (long long)v_val);
    }

    // 9. Pointer Dereference & Write
    jit_compile_and_run(
        "I64 target_val = 42;\n"
        "I64 *p_val = &target_val;\n"
        "*p_val = 999;\n"
    );
    symbol_t *s_tval = symbols_lookup_entry("target_val");
    int64_t v_tval = s_tval ? *(int64_t*)s_tval->address : 0;
    if (v_tval == 999) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 9. Pointer Dereference & Indirection: *p_val = %lld\n", (long long)v_tval);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 9. Pointer Dereference: expected 999, got %lld\n", (long long)v_tval);
    }

    // 10. Floating-Point Expressions & Casts (J10)
    int64_t fp_res = jit_eval("(I64)(10.5 * 2.0 + 3.0)");
    if (fp_res == 24) {
        doldoc_printf(" $FG,GREEN$[PASS]$FG$ 10. Floating-Point Expressions (F64 & Casts): (10.5 * 2.0 + 3.0) = %lld\n", (long long)fp_res);
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 10. Floating-Point: expected 24, got %lld\n", (long long)fp_res);
    }

    // 11. Static Type-Checking: Compile-Time Struct Member Verification
    int64_t err_res = jit_compile_and_run(
        "class TypeTestClass { I64 valid_field; };\n"
        "TypeTestClass tt;\n"
        "tt.invalid_field = 123;\n"
    );
    if (err_res == -1) {
        doldoc_print(" $FG,GREEN$[PASS]$FG$ 11. Type-Checking (Member Verification): invalid struct access halted compile-time\n");
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 11. Type-Checking: expected compile abort (-1), got %lld\n", (long long)err_res);
    }

    // 12. Static Pointer Scaling & Element Access (U8* vs U32* vs I64*)
    jit_compile_and_run(
        "U8 *raw_buf = kmalloc(32);\n"
        "raw_buf[0] = 11;\n"
        "raw_buf[1] = 22;\n"
        "raw_buf[2] = 33;\n"
        "raw_buf[3] = 44;\n"
        "U32 *p32 = raw_buf;\n"
        "U32 val32 = p32[0];\n"
        "I64 scale_ok = (raw_buf[0] == 11 && raw_buf[1] == 22 && val32 != 0);\n"
        "kfree(raw_buf);\n"
    );
    symbol_t *s_scale = symbols_lookup_entry("scale_ok");
    int64_t v_scale = s_scale ? *(int64_t*)s_scale->address : 0;
    if (v_scale == 1) {
        doldoc_print(" $FG,GREEN$[PASS]$FG$ 12. Pointer Scaling & Multi-Type Indirection: U8/U32 verified byte-precise\n");
        passed++;
    } else {
        doldoc_printf(" $FG,RED$[FAIL]$FG$ 12. Pointer Scaling: expected 1, got %lld\n", (long long)v_scale);
    }

    if (passed == total) {
        doldoc_printf("$FG,CYAN$=======================================================$FG$\n");
        doldoc_printf("$FG,GREEN$ ALL %d JIT ADVANCED CONSTRUCTS VERIFIED 100%% OPERATIONAL!$FG$\n", total);
        doldoc_printf("$FG,CYAN$=======================================================$FG$\n");
    }
    return (passed == total);
}

