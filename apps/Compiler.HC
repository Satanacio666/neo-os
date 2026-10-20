// ==============================================================================
// Compiler.HC - Sovereign Pure HolyC Stage-2 Self-Hosting JIT Compiler & Runtime
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 Machine Code Generation
// Self-Hosting: Compiles HolyC Source into Executable AArch64 Machine Instructions
// ==============================================================================

// Unified Token IDs (shared 1:1 with Lexer.HC)
#define TOK_EOF          0
#define TOK_NUMBER       1
#define TOK_FLOAT        2
#define TOK_IDENT        3
#define TOK_STRING       4

#define TOK_RETURN       5
#define TOK_IF           6
#define TOK_ELSE         7
#define TOK_WHILE        8
#define TOK_FOR          9
#define TOK_BREAK        10
#define TOK_CONTINUE     11
#define TOK_SWITCH       12
#define TOK_CASE         13
#define TOK_DEFAULT      14
#define TOK_DO           15
#define TOK_TYPE_I64     16
#define TOK_TYPE_U0      17
#define TOK_TYPE_F64     18
#define TOK_TYPE_U8      19
#define TOK_TYPE_U16     20
#define TOK_TYPE_U32     21

#define TOK_PLUS         22
#define TOK_MINUS        23
#define TOK_STAR         24
#define TOK_SLASH        25
#define TOK_PERCENT      26
#define TOK_EQUAL        27

#define TOK_AMPERSAND    28
#define TOK_ANDAND       29
#define TOK_PIPE         30
#define TOK_PIPEPIPE     31
#define TOK_CARET        32
#define TOK_TILDE        33
#define TOK_EXCLAM       34

#define TOK_EQEQ         35
#define TOK_NEQ          36
#define TOK_LT           37
#define TOK_LTE          38
#define TOK_GT           39
#define TOK_GTE          40

#define TOK_LPAREN       41
#define TOK_RPAREN       42
#define TOK_LBRACE       43
#define TOK_RBRACE       44
#define TOK_LBRACKET     45
#define TOK_RBRACKET     46
#define TOK_SEMICOLON    47
#define TOK_COMMA        48
#define TOK_DOT          49
#define TOK_ARROW        50
#define TOK_COLON        51
#define TOK_QUESTION     52
#define TOK_SHL          53
#define TOK_SHR          54
#define TOK_PLUSPLUS     55
#define TOK_MINUSMINUS   56
#define TOK_PLUSEQ       57
#define TOK_MINUSEQ      58
#define TOK_STAREQ       59
#define TOK_SLASHEQ      60
#define TOK_PERCENTEQ    61
#define TOK_ANDEQ        62
#define TOK_PIPEEQ       63
#define TOK_CARETEQ      64
#define TOK_SHLEQ        65
#define TOK_SHREQ        66
#define TOK_CLASS        67
#define TOK_STRUCT       68
#define TOK_AUTO         69
#define TOK_SIZEOF       70

// Stage-1 alias macros mapped to unified IDs
#define TOK_NUM          1
#define TOK_STR          4
#define TOK_TYPE         16
#define TOK_ASSIGN       27
#define TOK_AND          28
#define TOK_LOGAND       29
#define TOK_OR           30
#define TOK_LOGOR        31
#define TOK_XOR          32
#define TOK_NOT          34
#define TOK_EQ           35
#define TOK_NE           36
#define TOK_LE           38
#define TOK_GE           40
#define TOK_SEMI         47

#define HC_CODE_CAPACITY 1048576
#define HC_MAX_LOCALS    64
#define HC_MAX_FUNCS     128

// Compiler Source & Lexer State
U8   *g_hc_src;
I64   g_hc_pos;
I64   g_hc_len;

I64   g_hc_tok;
I64   g_hc_tok_val;
U8    g_hc_tok_str[256];

// Persistent Monotonic Executable Code Pool
U32  *g_hc_code;
I64   g_hc_code_len;
I64   g_hc_pool_offset;
U64   g_hc_unit_main;

// Function Prologue/Epilogue Dynamic Frame Patching
I64   g_hc_pro_sub_idx;
I64   g_hc_epi_patches[64];
I64   g_hc_epi_count;

// Local Variables Table (per function)
U8    g_hc_local_names[2048];   // 64 * 32
I64   g_hc_local_offsets[64];
I64   g_hc_local_scales[64];    // 1, 2, 4, 8, or struct size
I64   g_hc_local_is_ptr[64];    // 0=scalar, 1=ptr, 2=stack array, 3=stack struct
I64   g_hc_local_is_float[64];  // 1 if this local is an F64
I64   g_hc_local_st_idx[64];    // struct index or -1
I64   g_hc_local_count;
I64   g_hc_decl_float;          // transient: current declaration is F64
I64   g_hc_frame_offset;

// Persistent Compiled Function Table
U8    g_hc_func_names[4096];    // 128 * 32
U64   g_hc_func_addrs[128];
I64   g_hc_func_count;
I64   g_hc_func_ret_float[128];  // 1 if the function returns F64 (result in D0)
I64   g_hc_fn_ret_float;         // transient: current function return type is F64
I64   g_hc_arg_float[32];        // transient: which call args are F64

// Preprocessor #define Table in Compiler.HC
U8    g_hc_def_names[4096];     // 64 * 64
I64   g_hc_def_vals[64];
I64   g_hc_def_count;

// Struct / Class Registry (up to 32 structs, 16 members each = 512 member slots)
U8    g_hc_structs[1024];       // 32 * 32 struct names
I64   g_hc_struct_sizes[32];
I64   g_hc_struct_mcount[32];
U8    g_hc_member_names[16384]; // 512 * 32 member names
I64   g_hc_member_offsets[512];
I64   g_hc_member_sizes[512];   // 1, 2, 4, 8 (element/field load width)
I64   g_hc_member_is_arr[512];  // 1 if inline array member
I64   g_hc_member_is_ptr[512];  // 1 if pointer member
I64   g_hc_member_st_idx[512];  // nested struct index or -1
I64   g_hc_struct_count;

// Loop & Switch Break/Continue Patching Stacks (16 levels, 32 patches per level)
I64   g_hc_brk_stack[512];
I64   g_hc_brk_count[16];
I64   g_hc_cont_stack[512];
I64   g_hc_cont_count[16];
I64   g_hc_loop_is_switch[16];
I64   g_hc_loop_depth;

// Indirect parser & expression stacks
U64   g_hc_exec_fn;
U64   g_fn_parse_expr;
U64   g_fn_parse_stmt;
U64   g_hc_call_targets[32];
I64   g_hc_call_depth;
#define HC_OP_STACK 4096
I64   g_hc_op_stack[HC_OP_STACK];
I64   g_hc_op_sp;
I64   g_hc_expr_float;   // 1 if the current expression result is in D0 (F64)
I64   g_hc_error;        // set on any compiler internal error (stack overflow, cap, etc.)

U0 HcCallParseExpr() {
    g_fn_parse_expr();
}

U0 HcCallParseStmt() {
    g_fn_parse_stmt();
}

U0 HcOpPush(I64 val) {
    if (g_hc_op_sp < 0 || g_hc_op_sp >= HC_OP_STACK) { g_hc_error = 1; return; }
    g_hc_op_stack[g_hc_op_sp] = val;
    g_hc_op_sp++;
}

I64 HcOpPop() {
    if (g_hc_op_sp <= 0) { g_hc_error = 1; return 0; }
    g_hc_op_sp--;
    return g_hc_op_stack[g_hc_op_sp];
}

// Bounded string copy (never overruns dst; always NUL-terminates).
U0 HcSafeCopy(U8 *dst, U8 *src, I64 cap) {
    I64 i = 0;
    if (cap <= 0) return;
    while (i < cap - 1 && src[i]) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}

U0 HcStrCat(U8 *dest, U8 *src) {
    I64 d_len = strlen(dest);
    I64 s_len = strlen(src);
    I64 hsc_i = 0;
    for (hsc_i = 0; hsc_i < s_len; hsc_i++) {
        dest[d_len + hsc_i] = src[hsc_i];
    }
    dest[d_len + s_len] = 0;
}

// ------------------------------------------------------------------------------
// Character & Type Classification Helpers
// ------------------------------------------------------------------------------
I64 HcIsAlpha(U8 c) {
    I64 ch = c & 0xFF;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_')
        return 1;
    return 0;
}

I64 HcIsDigit(U8 c) {
    I64 ch = c & 0xFF;
    if (ch >= '0' && ch <= '9')
        return 1;
    return 0;
}

I64 HcIsAlNum(U8 c) {
    I64 ch = c & 0xFF;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_')
        return 1;
    return 0;
}

I64 HcIsSpace(U8 c) {
    I64 ch = c & 0xFF;
    if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n')
        return 1;
    return 0;
}

I64 HcIsTypeToken(I64 tok) {
    if (tok == TOK_TYPE_I64 || tok == TOK_TYPE_U0 || tok == TOK_TYPE_F64 ||
        tok == TOK_TYPE_U8  || tok == TOK_TYPE_U16 || tok == TOK_TYPE_U32) {
        return 1;
    }
    return 0;
}

I64 HcTypeTokenScale(I64 tok) {
    if (tok == TOK_TYPE_U8)  return 1;
    if (tok == TOK_TYPE_U16) return 2;
    if (tok == TOK_TYPE_U32) return 4;
    return 8;
}

// ------------------------------------------------------------------------------
// Compiler Initialization, Cache Coherency & Reset
// ------------------------------------------------------------------------------
U0 HcInit() {
    if (!g_hc_code) {
        g_hc_code = kmalloc(HC_CODE_CAPACITY * 4);
        g_hc_pool_offset = 0;
        g_hc_func_count = 0;
        g_hc_struct_count = 0;
        g_hc_def_count = 0;
    }
}

U0 HcReset() {
    if (g_hc_pool_offset > 1000000) {
        g_hc_pool_offset = 0;
    }
    g_hc_code_len = g_hc_pool_offset;
    g_hc_local_count = 0;
    g_hc_frame_offset = 16;
    g_hc_call_depth = 0;
    g_hc_op_sp = 0;
    g_hc_loop_depth = 0;
    g_hc_epi_count = 0;
    g_hc_unit_main = 0;
    g_hc_error = 0;
    // Reset per-module tables so counts don't accumulate across compilations.
    g_hc_func_count = 0;
    g_hc_struct_count = 0;
    g_hc_def_count = 0;
}

U0 HcFlushCache(U64 addr, U64 size) {
    if (!addr || size == 0) return;
    U64 f_p = addr & (~63);
    U64 f_end = addr + size + 64;
    while (f_p < f_end) {
        __dc_civac(f_p);
        __ic_ivau(f_p);
        f_p += 64;
    }
    __dsb_sy();
    __isb();
    HalFlushCache(addr, size);
}

// ------------------------------------------------------------------------------
// Preprocessor #define Table, Struct Table, Locals & Functions
// ------------------------------------------------------------------------------
U0 HcAddDefine(U8 *name, I64 val) {
    if (!name || !name[0]) return;
    I64 had_i = 0;
    for (had_i = 0; had_i < g_hc_def_count; had_i++) {
        if (strcmp(&g_hc_def_names[had_i * 64], name) == 0) {
            g_hc_def_vals[had_i] = val;
            return;
        }
    }
    if (g_hc_def_count < 64) {
        HcSafeCopy(&g_hc_def_names[g_hc_def_count * 64], name, 64);
        g_hc_def_vals[g_hc_def_count] = val;
        g_hc_def_count++;
    } else {
        g_hc_error = 1;
    }
}

I64 HcFindDefine(U8 *name, I64 *out_val) {
    I64 hfd_i = 0;
    for (hfd_i = 0; hfd_i < g_hc_def_count; hfd_i++) {
        if (strcmp(&g_hc_def_names[hfd_i * 64], name) == 0) {
            *out_val = g_hc_def_vals[hfd_i];
            return 1;
        }
    }
    return 0;
}

I64 HcFindStruct(U8 *name) {
    if (!name || !name[0]) return -1;
    I64 hfs_i = 0;
    for (hfs_i = 0; hfs_i < g_hc_struct_count; hfs_i++) {
        if (strcmp(&g_hc_structs[hfs_i * 32], name) == 0) {
            return hfs_i;
        }
    }
    return -1;
}

I64 HcAddStruct(U8 *name) {
    I64 ex_idx = HcFindStruct(name);
    if (ex_idx >= 0) {
        g_hc_struct_mcount[ex_idx] = 0;
        g_hc_struct_sizes[ex_idx] = 0;
        return ex_idx;
    }
    if (g_hc_struct_count >= 32) { g_hc_error = 1; return 0; }
    I64 ns_idx = g_hc_struct_count;
    HcSafeCopy(&g_hc_structs[ns_idx * 32], name, 32);
    g_hc_struct_sizes[ns_idx] = 0;
    g_hc_struct_mcount[ns_idx] = 0;
    g_hc_struct_count++;
    return ns_idx;
}

I64 HcFindMember(I64 st_idx, U8 *mname, I64 *out_off, I64 *out_sz, I64 *out_is_arr, I64 *out_is_ptr, I64 *out_sub_st) {
    I64 s_start = 0;
    I64 s_end = g_hc_struct_count;
    if (st_idx >= 0 && st_idx < g_hc_struct_count) {
        s_start = st_idx;
        s_end = st_idx + 1;
    }
    I64 s_i = 0;
    I64 m_i = 0;
    for (s_i = s_start; s_i < s_end; s_i++) {
        I64 mcnt = g_hc_struct_mcount[s_i];
        for (m_i = 0; m_i < mcnt; m_i++) {
            I64 slot = s_i * 16 + m_i;
            if (strcmp(&g_hc_member_names[slot * 32], mname) == 0) {
                *out_off = g_hc_member_offsets[slot];
                *out_sz = g_hc_member_sizes[slot];
                *out_is_arr = g_hc_member_is_arr[slot];
                *out_is_ptr = g_hc_member_is_ptr[slot];
                *out_sub_st = g_hc_member_st_idx[slot];
                return 1;
            }
        }
    }
    // Fallback search across all structs if st_idx was unknown
    if (st_idx >= 0) {
        for (s_i = 0; s_i < g_hc_struct_count; s_i++) {
            I64 mcnt2 = g_hc_struct_mcount[s_i];
            for (m_i = 0; m_i < mcnt2; m_i++) {
                I64 slot2 = s_i * 16 + m_i;
                if (strcmp(&g_hc_member_names[slot2 * 32], mname) == 0) {
                    *out_off = g_hc_member_offsets[slot2];
                    *out_sz = g_hc_member_sizes[slot2];
                    *out_is_arr = g_hc_member_is_arr[slot2];
                    *out_is_ptr = g_hc_member_is_ptr[slot2];
                    *out_sub_st = g_hc_member_st_idx[slot2];
                    return 1;
                }
            }
        }
    }
    return 0;
}

I64 HcFindLocalIdx(U8 *name) {
    I64 fl_i = 0;
    for (fl_i = 0; fl_i < g_hc_local_count; fl_i++) {
        if (strcmp(&g_hc_local_names[fl_i * 32], name) == 0) {
            return fl_i;
        }
    }
    return -1;
}

I64 HcFindLocal(U8 *name) {
    I64 idx = HcFindLocalIdx(name);
    if (idx >= 0) return g_hc_local_offsets[idx];
    return -1;
}

I64 HcAddLocalTyped(U8 *name, I64 scale, I64 is_ptr, I64 st_idx, I64 count) {
    I64 ex = HcFindLocalIdx(name);
    if (ex >= 0) {
        return g_hc_local_offsets[ex];
    }
    I64 offset = g_hc_frame_offset;
    I64 alloc_bytes = 16;
    if (is_ptr == 2) {
        // Inline stack array
        I64 raw_arr = count * scale;
        alloc_bytes = (raw_arr + 15) & (~15);
        if (alloc_bytes < 16) alloc_bytes = 16;
    } else if (is_ptr == 3 && st_idx >= 0) {
        // Inline stack struct
        I64 raw_st = g_hc_struct_sizes[st_idx];
        alloc_bytes = (raw_st + 15) & (~15);
        if (alloc_bytes < 16) alloc_bytes = 16;
    }
    g_hc_frame_offset += alloc_bytes;
    if (g_hc_local_count < 64) {
        HcSafeCopy(&g_hc_local_names[g_hc_local_count * 32], name, 32);
        g_hc_local_offsets[g_hc_local_count] = offset;
        g_hc_local_scales[g_hc_local_count] = scale;
        g_hc_local_is_ptr[g_hc_local_count] = is_ptr;
        g_hc_local_is_float[g_hc_local_count] = g_hc_decl_float;
        g_hc_local_st_idx[g_hc_local_count] = st_idx;
        g_hc_local_count++;
    } else {
        g_hc_error = 1;
    }
    return offset;
}

I64 HcAddLocal(U8 *name) {
    return HcAddLocalTyped(name, 8, 0, -1, 1);
}

U64 HcFindFunc(U8 *name) {
    I64 ff_i = 0;
    for (ff_i = 0; ff_i < g_hc_func_count; ff_i++) {
        if (strcmp(&g_hc_func_names[ff_i * 32], name) == 0) {
            return g_hc_func_addrs[ff_i];
        }
    }
    return symbols_lookup(name);
}

U0 HcAddFunc(U8 *name, U64 addr) {
    I64 af_i = 0;
    for (af_i = 0; af_i < g_hc_func_count; af_i++) {
        if (strcmp(&g_hc_func_names[af_i * 32], name) == 0) {
            g_hc_func_addrs[af_i] = addr;
            symbols_register(name, addr, 1);
            return;
        }
    }
    if (g_hc_func_count < 128) {
        HcSafeCopy(&g_hc_func_names[g_hc_func_count * 32], name, 32);
        g_hc_func_addrs[g_hc_func_count] = addr;
        g_hc_func_ret_float[g_hc_func_count] = g_hc_fn_ret_float;
        g_hc_func_count++;
    } else {
        g_hc_error = 1;
    }
    symbols_register(name, addr, 1);
}

I64 HcFuncIsFloat(U8 *name) {
    for (I64 i = 0; i < g_hc_func_count; i++) {
        if (strcmp(&g_hc_func_names[i * 32], name) == 0) return g_hc_func_ret_float[i];
    }
    return 0;
}

// ------------------------------------------------------------------------------
// AArch64 Machine Code Emitter
// ------------------------------------------------------------------------------
U0 HcEmit(U32 insn) {
    if (g_hc_code_len >= HC_CODE_CAPACITY) { g_hc_error = 1; return; } // bounds guard: never overrun
    g_hc_code[g_hc_code_len++] = insn;
}

U0 HcEmitImm64(I64 reg, I64 val) {
    U64 v = val;
    HcEmit(0xD2800000 | ((v & 0xFFFF) << 5) | reg);
    if ((v >> 16) & 0xFFFF) {
        HcEmit(0xF2A00000 | (((v >> 16) & 0xFFFF) << 5) | reg);
    }
    if ((v >> 32) & 0xFFFF) {
        HcEmit(0xF2C00000 | (((v >> 32) & 0xFFFF) << 5) | reg);
    }
    if ((v >> 48) & 0xFFFF) {
        HcEmit(0xF2E00000 | (((v >> 48) & 0xFFFF) << 5) | reg);
    }
}

U0 HcEmitPush(I64 reg) {
    // str x(reg), [sp, #-16]!
    HcEmit(0xF81F0FE0 | reg);
}

U0 HcEmitPop(I64 reg) {
    // ldr x(reg), [sp], #16
    HcEmit(0xF84107E0 | reg);
}

U0 HcEmitAddrLocal(I64 reg, I64 offset) {
    // add x(reg), x29, #offset
    HcEmit(0x910003A0 | ((offset & 0xFFF) << 10) | reg);
}

U0 HcEmitLoadLocal(I64 reg, I64 offset) {
    // ldr x(reg), [x29, #offset]
    HcEmit(0xF94003A0 | ((offset >> 3) << 10) | reg);
}

U0 HcEmitStoreLocal(I64 reg, I64 offset) {
    // str x(reg), [x29, #offset]
    HcEmit(0xF90003A0 | ((offset >> 3) << 10) | reg);
}

U0 HcEmitLoadSized(I64 rd, I64 rn, I64 sz) {
    if (sz == 1) {
        // ldrb w(rd), [x(rn)]
        HcEmit(0x39400000 | (rn << 5) | rd);
    } else if (sz == 2) {
        // ldrh w(rd), [x(rn)]
        HcEmit(0x79400000 | (rn << 5) | rd);
    } else if (sz == 4) {
        // ldr w(rd), [x(rn)]
        HcEmit(0xB9400000 | (rn << 5) | rd);
    } else {
        // ldr x(rd), [x(rn)]
        HcEmit(0xF9400000 | (rn << 5) | rd);
    }
}

U0 HcEmitStoreSized(I64 rt, I64 rn, I64 sz) {
    if (sz == 1) {
        // strb w(rt), [x(rn)]
        HcEmit(0x39000000 | (rn << 5) | rt);
    } else if (sz == 2) {
        // strh w(rt), [x(rn)]
        HcEmit(0x79000000 | (rn << 5) | rt);
    } else if (sz == 4) {
        // str w(rt), [x(rn)]
        HcEmit(0xB9000000 | (rn << 5) | rt);
    } else {
        // str x(rt), [x(rn)]
        HcEmit(0xF9000000 | (rn << 5) | rt);
    }
}

U0 HcEmitPrologue() {
    // stp x29, x30, [sp, #-16]!
    HcEmit(0xA9BF7BFD);
    // sub sp, sp, #frame_sz (backpatched at end of function)
    g_hc_pro_sub_idx = g_hc_code_len;
    HcEmit(0xD10403FF); // default 256 until patched
    // mov x29, sp
    HcEmit(0x910003FD);
}

U0 HcEmitEpilogue() {
    // mov sp, x29
    HcEmit(0x910003BF);
    // add sp, sp, #frame_sz (backpatched at end of function)
    if (g_hc_epi_count < 64) {
        g_hc_epi_patches[g_hc_epi_count] = g_hc_code_len;
        g_hc_epi_count++;
    } else {
        g_hc_error = 1;
    }
    HcEmit(0x910403FF); // default 256 until patched
    // ldp x29, x30, [sp], #16
    HcEmit(0xA8C17BFD);
    // ret
    HcEmit(0xD65F03C0);
}

U0 HcFinalizeFrame() {
    I64 frame_sz = (g_hc_frame_offset + 15) & (~15);
    if (frame_sz < 64) frame_sz = 64;
    if (frame_sz > 4080) { frame_sz = 4080; g_hc_error = 1; }
    g_hc_code[g_hc_pro_sub_idx] = 0xD10003FF | ((frame_sz & 0xFFF) << 10);
    I64 ep_i = 0;
    for (ep_i = 0; ep_i < g_hc_epi_count; ep_i++) {
        I64 p_idx = g_hc_epi_patches[ep_i];
        g_hc_code[p_idx] = 0x910003FF | ((frame_sz & 0xFFF) << 10);
    }
}

U0 HcBackpatchCbz(I64 patch_idx, I64 target_idx) {
    I64 diff = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0xB4000000 | ((diff & 0x7FFFF) << 5);
}

U0 HcBackpatchCbnz(I64 patch_idx, I64 target_idx) {
    I64 rel = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0xB5000000 | ((rel & 0x7FFFF) << 5) | 0;
}

U0 HcBackpatchB(I64 patch_idx, I64 target_idx) {
    I64 diff = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0x14000000 | (diff & 0x03FFFFFF);
}

// ------------------------------------------------------------------------------
// Loop / Switch Break & Continue Context Helpers
// ------------------------------------------------------------------------------
I64 HcPushLoopCtx(I64 is_switch) {
    I64 lvl = g_hc_loop_depth;
    if (lvl < 16) {
        g_hc_brk_count[lvl] = 0;
        g_hc_cont_count[lvl] = 0;
        g_hc_loop_is_switch[lvl] = is_switch;
        g_hc_loop_depth++;
    } else {
        g_hc_error = 1;
        lvl = 15;   // clamp so callers never index out of bounds
    }
    return lvl;
}

U0 HcPopLoopCtx() {
    if (g_hc_loop_depth > 0) {
        g_hc_loop_depth--;
    }
}

U0 HcRecordBreak() {
    if (g_hc_loop_depth <= 0) return;
    I64 lvl = g_hc_loop_depth - 1;
    I64 cnt = g_hc_brk_count[lvl];
    if (cnt < 32) {
        g_hc_brk_stack[lvl * 32 + cnt] = g_hc_code_len;
        g_hc_brk_count[lvl] = cnt + 1;
    }
    HcEmit(0x14000000); // b break_target
}

U0 HcRecordContinue() {
    I64 lvl = g_hc_loop_depth - 1;
    while (lvl >= 0 && g_hc_loop_is_switch[lvl] != 0) {
        lvl--;
    }
    if (lvl < 0) return;
    I64 cnt = g_hc_cont_count[lvl];
    if (cnt < 32) {
        g_hc_cont_stack[lvl * 32 + cnt] = g_hc_code_len;
        g_hc_cont_count[lvl] = cnt + 1;
    }
    HcEmit(0x14000000); // b continue_target
}

U0 HcPatchBreaks(I64 lvl, I64 target_idx) {
    I64 cnt = g_hc_brk_count[lvl];
    I64 pb_i = 0;
    for (pb_i = 0; pb_i < cnt; pb_i++) {
        HcBackpatchB(g_hc_brk_stack[lvl * 32 + pb_i], target_idx);
    }
}

U0 HcPatchContinues(I64 lvl, I64 target_idx) {
    I64 cnt = g_hc_cont_count[lvl];
    I64 pc_i = 0;
    for (pc_i = 0; pc_i < cnt; pc_i++) {
        HcBackpatchB(g_hc_cont_stack[lvl * 32 + pc_i], target_idx);
    }
}

// ------------------------------------------------------------------------------
// Lexical Analyzer (Tokenizer with #define Preprocessor Support)
// ------------------------------------------------------------------------------
U0 HcSkipWhitespaceAndComments() {
    while (g_hc_pos < g_hc_len) {
        U8 c = g_hc_src[g_hc_pos];
        if (HcIsSpace(c)) {
            g_hc_pos++;
            continue;
        }
        // Single-line comment //
        if (c == '/' && g_hc_pos + 1 < g_hc_len && g_hc_src[g_hc_pos + 1] == '/') {
            g_hc_pos += 2;
            while (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] != '\n') {
                g_hc_pos++;
            }
            continue;
        }
        // Multi-line block comment
        if (c == '/' && g_hc_pos + 1 < g_hc_len && g_hc_src[g_hc_pos + 1] == '*') {
            g_hc_pos += 2;
            while (g_hc_pos + 1 < g_hc_len) {
                if (g_hc_src[g_hc_pos] == '*' && g_hc_src[g_hc_pos + 1] == '/') {
                    g_hc_pos += 2;
                    break;
                }
                g_hc_pos++;
            }
            continue;
        }
        // Preprocessor #define directive
        if (c == '#') {
            g_hc_pos++;
            while (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == ' ' || g_hc_src[g_hc_pos] == '\t')) {
                g_hc_pos++;
            }
            U8 dir_w[32];
            I64 dw_i = 0;
            while (g_hc_pos < g_hc_len && HcIsAlpha(g_hc_src[g_hc_pos]) && dw_i < 31) {
                dir_w[dw_i++] = g_hc_src[g_hc_pos++];
            }
            dir_w[dw_i] = 0;
            if (strcmp(dir_w, "define") == 0) {
                while (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == ' ' || g_hc_src[g_hc_pos] == '\t')) {
                    g_hc_pos++;
                }
                U8 def_n[64];
                I64 dn_i = 0;
                while (g_hc_pos < g_hc_len && HcIsAlNum(g_hc_src[g_hc_pos]) && dn_i < 63) {
                    def_n[dn_i++] = g_hc_src[g_hc_pos++];
                }
                def_n[dn_i] = 0;
                while (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == ' ' || g_hc_src[g_hc_pos] == '\t')) {
                    g_hc_pos++;
                }
                I64 d_neg = 0;
                if (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] == '-') {
                    d_neg = 1;
                    g_hc_pos++;
                    while (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == ' ' || g_hc_src[g_hc_pos] == '\t')) {
                        g_hc_pos++;
                    }
                }
                I64 d_val = 0;
                if (g_hc_pos + 1 < g_hc_len && g_hc_src[g_hc_pos] == '0' &&
                    (g_hc_src[g_hc_pos + 1] == 'x' || g_hc_src[g_hc_pos + 1] == 'X')) {
                    g_hc_pos += 2;
                    while (g_hc_pos < g_hc_len) {
                        U8 hc = g_hc_src[g_hc_pos];
                        if (hc >= '0' && hc <= '9') { d_val = (d_val << 4) | (hc - '0'); g_hc_pos++; }
                        else if (hc >= 'a' && hc <= 'f') { d_val = (d_val << 4) | (hc - 'a' + 10); g_hc_pos++; }
                        else if (hc >= 'A' && hc <= 'F') { d_val = (d_val << 4) | (hc - 'A' + 10); g_hc_pos++; }
                        else break;
                    }
                } else if (g_hc_pos < g_hc_len && HcIsDigit(g_hc_src[g_hc_pos])) {
                    while (g_hc_pos < g_hc_len && HcIsDigit(g_hc_src[g_hc_pos])) {
                        d_val = d_val * 10 + (g_hc_src[g_hc_pos] - '0');
                        g_hc_pos++;
                    }
                } else if (g_hc_pos < g_hc_len && HcIsAlpha(g_hc_src[g_hc_pos])) {
                    U8 ref_n[64];
                    I64 rn_i = 0;
                    while (g_hc_pos < g_hc_len && HcIsAlNum(g_hc_src[g_hc_pos]) && rn_i < 63) {
                        ref_n[rn_i++] = g_hc_src[g_hc_pos++];
                    }
                    ref_n[rn_i] = 0;
                    HcFindDefine(ref_n, &d_val);
                }
                if (d_neg) d_val = -d_val;
                if (def_n[0]) {
                    HcAddDefine(def_n, d_val);
                }
            }
            while (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] != '\n') {
                g_hc_pos++;
            }
            continue;
        }
        break;
    }
}

U0 HcLexNext() {
    HcSkipWhitespaceAndComments();
    if (g_hc_pos >= g_hc_len) {
        g_hc_tok = TOK_EOF;
        return;
    }

    U8 c = g_hc_src[g_hc_pos];

    // Numbers: Hex (0x...) or Decimal
    if (HcIsDigit(c)) {
        I64 val = 0;
        if (c == '0' && g_hc_pos + 1 < g_hc_len && (g_hc_src[g_hc_pos + 1] == 'x' || g_hc_src[g_hc_pos + 1] == 'X')) {
            g_hc_pos += 2;
            while (g_hc_pos < g_hc_len) {
                U8 h = g_hc_src[g_hc_pos];
                if (h >= '0' && h <= '9') {
                    val = (val << 4) | (h - '0');
                    g_hc_pos++;
                } else if (h >= 'a' && h <= 'f') {
                    val = (val << 4) | (h - 'a' + 10);
                    g_hc_pos++;
                } else if (h >= 'A' && h <= 'F') {
                    val = (val << 4) | (h - 'A' + 10);
                    g_hc_pos++;
                } else {
                    break;
                }
            }
        } else {
            while (g_hc_pos < g_hc_len) {
                I64 d = g_hc_src[g_hc_pos] & 0xFF;
                if (d >= '0' && d <= '9') {
                    val = val * 10 + (d - '0');
                    g_hc_pos++;
                } else {
                    break;
                }
            }
            // Float literal: digits '.' digits [ (e|E) [+|-] digits ]
            if (g_hc_pos < g_hc_len &&
                (g_hc_src[g_hc_pos] == '.' || g_hc_src[g_hc_pos] == 'e' || g_hc_src[g_hc_pos] == 'E')) {
                F64 fv = (F64)val;
                if (g_hc_src[g_hc_pos] == '.') {
                    g_hc_pos++;
                    F64 scale = 10.0;
                    while (g_hc_pos < g_hc_len && HcIsDigit(g_hc_src[g_hc_pos])) {
                        fv = fv + (F64)(g_hc_src[g_hc_pos] - '0') / scale;
                        scale = scale * 10.0;
                        g_hc_pos++;
                    }
                }
                if (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == 'e' || g_hc_src[g_hc_pos] == 'E')) {
                    g_hc_pos++;
                    I64 esign = 1;
                    if (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] == '+') g_hc_pos++;
                    else if (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] == '-') { esign = -1; g_hc_pos++; }
                    I64 exp = 0;
                    while (g_hc_pos < g_hc_len && HcIsDigit(g_hc_src[g_hc_pos])) {
                        exp = exp * 10 + (g_hc_src[g_hc_pos] - '0');
                        g_hc_pos++;
                    }
                    for (I64 ei = 0; ei < exp; ei++) { if (esign > 0) fv = fv * 10.0; else fv = fv / 10.0; }
                }
                g_hc_tok_val = *(I64*)&fv;   // IEEE-754 bits
                g_hc_tok = TOK_FLOAT;
                return;
            }
        }
        g_hc_tok_val = val;
        g_hc_tok = TOK_NUMBER;
        return;
    }

    // String Literals: "..."
    if (c == '\"') {
        g_hc_pos++;
        I64 start = g_hc_pos;
        while (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] != '\"') {
            if (g_hc_src[g_hc_pos] == '\\' && g_hc_pos + 1 < g_hc_len) {
                g_hc_pos++;
            }
            g_hc_pos++;
        }
        I64 slen = g_hc_pos - start;
        U8 *buf = kmalloc(slen + 1);
        I64 dst_i = 0;
        I64 src_i = start;
        while (src_i < g_hc_pos) {
            U8 sc = g_hc_src[src_i++];
            if (sc == '\\' && src_i < g_hc_pos) {
                U8 esc = g_hc_src[src_i++];
                if (esc == 'n') sc = 10;
                else if (esc == 'r') sc = 13;
                else if (esc == 't') sc = 9;
                else if (esc == '0') sc = 0;
                else sc = esc;
            }
            buf[dst_i++] = sc;
        }
        buf[dst_i] = 0;
        if (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] == '\"') {
            g_hc_pos++;
        }
        g_hc_tok_val = buf;
        g_hc_tok = TOK_STRING;
        return;
    }

    // Character Literals: '...'
    if (c == '\'') {
        g_hc_pos++;
        U8 ch = g_hc_src[g_hc_pos++];
        if (ch == '\\' && g_hc_pos < g_hc_len) {
            U8 esc = g_hc_src[g_hc_pos++];
            if (esc == 'n') ch = 10;
            else if (esc == 'r') ch = 13;
            else if (esc == 't') ch = 9;
            else if (esc == '0') ch = 0;
            else ch = esc;
        }
        if (g_hc_pos < g_hc_len && g_hc_src[g_hc_pos] == '\'') {
            g_hc_pos++;
        }
        g_hc_tok_val = ch;
        g_hc_tok = TOK_NUMBER;
        return;
    }

    // Identifiers, Keywords & #define Constants
    if (HcIsAlpha(c)) {
        I64 idx = 0;
        while (g_hc_pos < g_hc_len && idx < 255) {
            I64 id_ch = g_hc_src[g_hc_pos] & 0xFF;
            if ((id_ch >= 'a' && id_ch <= 'z') || (id_ch >= 'A' && id_ch <= 'Z') ||
                (id_ch >= '0' && id_ch <= '9') || id_ch == '_') {
                g_hc_tok_str[idx++] = id_ch;
                g_hc_pos++;
            } else {
                break;
            }
        }
        g_hc_tok_str[idx] = 0;

        if (strcmp(g_hc_tok_str, "if") == 0) g_hc_tok = TOK_IF;
        else if (strcmp(g_hc_tok_str, "else") == 0) g_hc_tok = TOK_ELSE;
        else if (strcmp(g_hc_tok_str, "while") == 0) g_hc_tok = TOK_WHILE;
        else if (strcmp(g_hc_tok_str, "for") == 0) g_hc_tok = TOK_FOR;
        else if (strcmp(g_hc_tok_str, "do") == 0) g_hc_tok = TOK_DO;
        else if (strcmp(g_hc_tok_str, "switch") == 0) g_hc_tok = TOK_SWITCH;
        else if (strcmp(g_hc_tok_str, "case") == 0) g_hc_tok = TOK_CASE;
        else if (strcmp(g_hc_tok_str, "default") == 0) g_hc_tok = TOK_DEFAULT;
        else if (strcmp(g_hc_tok_str, "break") == 0) g_hc_tok = TOK_BREAK;
        else if (strcmp(g_hc_tok_str, "continue") == 0) g_hc_tok = TOK_CONTINUE;
        else if (strcmp(g_hc_tok_str, "return") == 0) g_hc_tok = TOK_RETURN;
        else if (strcmp(g_hc_tok_str, "class") == 0) g_hc_tok = TOK_CLASS;
        else if (strcmp(g_hc_tok_str, "struct") == 0) g_hc_tok = TOK_STRUCT;
        else if (strcmp(g_hc_tok_str, "sizeof") == 0) g_hc_tok = TOK_SIZEOF;
        else if (strcmp(g_hc_tok_str, "auto") == 0) g_hc_tok = TOK_AUTO;
        else if (strcmp(g_hc_tok_str, "I64") == 0 || strcmp(g_hc_tok_str, "U64") == 0 ||
                 strcmp(g_hc_tok_str, "int") == 0 || strcmp(g_hc_tok_str, "long") == 0) {
            g_hc_tok = TOK_TYPE_I64;
        } else if (strcmp(g_hc_tok_str, "U0") == 0 || strcmp(g_hc_tok_str, "void") == 0) {
            g_hc_tok = TOK_TYPE_U0;
        } else if (strcmp(g_hc_tok_str, "F64") == 0 || strcmp(g_hc_tok_str, "double") == 0) {
            g_hc_tok = TOK_TYPE_F64;
        } else if (strcmp(g_hc_tok_str, "U8") == 0 || strcmp(g_hc_tok_str, "I8") == 0 ||
                   strcmp(g_hc_tok_str, "char") == 0) {
            g_hc_tok = TOK_TYPE_U8;
        } else if (strcmp(g_hc_tok_str, "U16") == 0 || strcmp(g_hc_tok_str, "I16") == 0 ||
                   strcmp(g_hc_tok_str, "short") == 0) {
            g_hc_tok = TOK_TYPE_U16;
        } else if (strcmp(g_hc_tok_str, "U32") == 0 || strcmp(g_hc_tok_str, "I32") == 0) {
            g_hc_tok = TOK_TYPE_U32;
        } else {
            I64 def_val = 0;
            if (HcFindDefine(g_hc_tok_str, &def_val)) {
                g_hc_tok_val = def_val;
                g_hc_tok = TOK_NUMBER;
            } else {
                g_hc_tok = TOK_IDENT;
            }
        }
        return;
    }

    // Three-character operators
    if (g_hc_pos + 2 < g_hc_len) {
        U8 n1 = g_hc_src[g_hc_pos + 1];
        U8 n2 = g_hc_src[g_hc_pos + 2];
        if (c == '<' && n1 == '<' && n2 == '=') { g_hc_pos += 3; g_hc_tok = TOK_SHLEQ; return; }
        if (c == '>' && n1 == '>' && n2 == '=') { g_hc_pos += 3; g_hc_tok = TOK_SHREQ; return; }
    }

    // Two-character operators
    if (g_hc_pos + 1 < g_hc_len) {
        U8 next = g_hc_src[g_hc_pos + 1];
        if (c == '=' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_EQEQ; return; }
        if (c == '!' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_NEQ; return; }
        if (c == '<' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_LTE; return; }
        if (c == '>' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_GTE; return; }
        if (c == '+' && next == '+') { g_hc_pos += 2; g_hc_tok = TOK_PLUSPLUS; return; }
        if (c == '-' && next == '-') { g_hc_pos += 2; g_hc_tok = TOK_MINUSMINUS; return; }
        if (c == '+' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_PLUSEQ; return; }
        if (c == '-' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_MINUSEQ; return; }
        if (c == '*' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_STAREQ; return; }
        if (c == '/' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_SLASHEQ; return; }
        if (c == '%' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_PERCENTEQ; return; }
        if (c == '&' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_ANDEQ; return; }
        if (c == '|' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_PIPEEQ; return; }
        if (c == '^' && next == '=') { g_hc_pos += 2; g_hc_tok = TOK_CARETEQ; return; }
        if (c == '&' && next == '&') { g_hc_pos += 2; g_hc_tok = TOK_ANDAND; return; }
        if (c == '|' && next == '|') { g_hc_pos += 2; g_hc_tok = TOK_PIPEPIPE; return; }
        if (c == '<' && next == '<') { g_hc_pos += 2; g_hc_tok = TOK_SHL; return; }
        if (c == '>' && next == '>') { g_hc_pos += 2; g_hc_tok = TOK_SHR; return; }
        if (c == '-' && next == '>') { g_hc_pos += 2; g_hc_tok = TOK_ARROW; return; }
    }

    // Single-character tokens
    g_hc_pos++;
    if (c == '+') g_hc_tok = TOK_PLUS;
    else if (c == '-') g_hc_tok = TOK_MINUS;
    else if (c == '*') g_hc_tok = TOK_STAR;
    else if (c == '/') g_hc_tok = TOK_SLASH;
    else if (c == '%') g_hc_tok = TOK_PERCENT;
    else if (c == '=') g_hc_tok = TOK_EQUAL;
    else if (c == '<') g_hc_tok = TOK_LT;
    else if (c == '>') g_hc_tok = TOK_GT;
    else if (c == '(') g_hc_tok = TOK_LPAREN;
    else if (c == ')') g_hc_tok = TOK_RPAREN;
    else if (c == '{') g_hc_tok = TOK_LBRACE;
    else if (c == '}') g_hc_tok = TOK_RBRACE;
    else if (c == '[') g_hc_tok = TOK_LBRACKET;
    else if (c == ']') g_hc_tok = TOK_RBRACKET;
    else if (c == ';') g_hc_tok = TOK_SEMICOLON;
    else if (c == ',') g_hc_tok = TOK_COMMA;
    else if (c == '.') g_hc_tok = TOK_DOT;
    else if (c == ':') g_hc_tok = TOK_COLON;
    else if (c == '?') g_hc_tok = TOK_QUESTION;
    else if (c == '&') g_hc_tok = TOK_AMPERSAND;
    else if (c == '|') g_hc_tok = TOK_PIPE;
    else if (c == '^') g_hc_tok = TOK_CARET;
    else if (c == '~') g_hc_tok = TOK_TILDE;
    else if (c == '!') g_hc_tok = TOK_EXCLAM;
    else g_hc_tok = TOK_EOF;
}

U0 HcNextToken() {
    HcLexNext();
}

// ------------------------------------------------------------------------------
// Unified LValue Address Resolver (Locals, Globals, Arrays, Struct . and ->)
// Emits address of lvalue into X0; writes element byte width (1/2/4/8) to *out_scale
// and sets *out_addr_only = 1 if expression is an unindexed array/struct base
// ------------------------------------------------------------------------------
U0 HcResolveLValue(U8 *ident_name, I64 *out_scale, I64 *out_addr_only) {
    *out_scale = 8;
    *out_addr_only = 0;

    I64 loc_idx = HcFindLocalIdx(ident_name);
    I64 cur_scale = 8;
    I64 cur_st_idx = -1;
    I64 cur_mode = 0; // 0=scalar, 1=ptr, 2=inline_arr, 3=inline_struct

    if (loc_idx >= 0) {
        I64 rlv_off = g_hc_local_offsets[loc_idx];
        cur_scale = g_hc_local_scales[loc_idx];
        cur_st_idx = g_hc_local_st_idx[loc_idx];
        cur_mode = g_hc_local_is_ptr[loc_idx];

        if (cur_mode == 2 || cur_mode == 3) {
            HcEmitAddrLocal(0, rlv_off);
        } else if (cur_mode == 1 && (g_hc_tok == TOK_ARROW || g_hc_tok == TOK_LBRACKET || g_hc_tok == TOK_DOT)) {
            HcEmitLoadLocal(0, rlv_off);
            cur_mode = 0;
        } else {
            HcEmitAddrLocal(0, rlv_off);
            if (cur_mode == 1) {
                cur_scale = 8;
            }
        }
    } else {
        I64 kf_i = 0;
        for (kf_i = 0; kf_i < g_hc_func_count; kf_i++) {
            if (strcmp(&g_hc_func_names[kf_i * 32], ident_name) == 0) {
                HcEmitImm64(0, g_hc_func_addrs[kf_i]);
                *out_addr_only = 1;
                return;
            }
        }
        U64 gaddr = symbols_lookup(ident_name);
        if (gaddr) {
            HcEmitImm64(0, gaddr);
            if (g_hc_tok == TOK_LBRACKET || g_hc_tok == TOK_ARROW) {
                HcEmit(0xF9400000); // ldr x0, [x0]
            }
        } else {
            doldoc_printf("$FG,RED$[COMPILER.HC ERROR] Unknown symbol: %s$FG$\n", ident_name);
            HcEmitImm64(0, 0);
        }
    }

    if (g_hc_tok != TOK_DOT && g_hc_tok != TOK_ARROW && g_hc_tok != TOK_LBRACKET) {
        *out_scale = cur_scale;
        if (cur_mode == 2 || cur_mode == 3) {
            *out_addr_only = 1;
        } else {
            *out_addr_only = 0;
        }
        return;
    }

    while (g_hc_tok == TOK_DOT || g_hc_tok == TOK_ARROW || g_hc_tok == TOK_LBRACKET) {
        if (g_hc_tok == TOK_DOT || g_hc_tok == TOK_ARROW) {
            I64 is_arrow = (g_hc_tok == TOK_ARROW);
            if (is_arrow && cur_mode == 1) {
                HcEmit(0xF9400000); // ldr x0, [x0]
            }
            HcLexNext(); // eat '.' or '->'
            if (g_hc_tok == TOK_IDENT) {
                U8 mname[64];
                HcSafeCopy(mname, g_hc_tok_str, 64);
                HcLexNext();

                I64 m_off = 0;
                I64 m_sz = 8;
                I64 m_arr = 0;
                I64 m_ptr = 0;
                I64 m_sub = -1;
                if (HcFindMember(cur_st_idx, mname, &m_off, &m_sz, &m_arr, &m_ptr, &m_sub)) {
                    if (m_off != 0) {
                        HcEmitImm64(1, m_off);
                        HcEmit(0x8B010000); // add x0, x0, x1
                    }
                    cur_scale = m_sz;
                    cur_st_idx = m_sub;
                    if (m_arr) cur_mode = 2;
                    else if (m_ptr) cur_mode = 1;
                    else if (m_sub >= 0) cur_mode = 3;
                    else cur_mode = 0;
                }
            }
        } else if (g_hc_tok == TOK_LBRACKET) {
            if (cur_mode == 1) {
                HcEmit(0xF9400000); // ldr x0, [x0] (dereference pointer before indexing)
            }
            HcLexNext(); // eat '['
            HcEmitPush(0); // save base address
            HcOpPush(cur_scale);
            HcOpPush(cur_st_idx);
            HcOpPush(cur_mode);
            HcCallParseExpr(); // index in x0
            cur_mode = HcOpPop();
            cur_st_idx = HcOpPop();
            cur_scale = HcOpPop();
            if (g_hc_tok == TOK_RBRACKET) HcLexNext(); // eat ']'
            HcEmitPop(1); // base address in x1

            I64 elem_sz = cur_scale;
            if (cur_st_idx >= 0 && cur_mode != 1) {
                elem_sz = g_hc_struct_sizes[cur_st_idx];
            }
            if (elem_sz > 1) {
                HcEmitImm64(2, elem_sz);
                HcEmit(0x9B027C00); // mul x0, x0, x2
            }
            HcEmit(0x8B000020); // add x0, x1, x0

            if (g_hc_tok == TOK_LBRACKET) {
                // Chained multidimensional array indexing (e.g. matrix[i][j])
                cur_mode = 1;
                cur_scale = 8;
            } else {
                cur_mode = 0;
            }
        }
    }

    *out_scale = cur_scale;
    if (cur_mode == 2 || cur_mode == 3) {
        *out_addr_only = 1;
    } else {
        *out_addr_only = 0;
    }
}

// ------------------------------------------------------------------------------
// Recursive-Descent Expression Parser
// ------------------------------------------------------------------------------
U0 HcParsePrimary() {
    g_hc_expr_float = 0;
    if (g_hc_tok == TOK_FLOAT) {
        I64 bits = g_hc_tok_val;
        HcLexNext();
        HcEmitImm64(16, bits);   // x16 = IEEE-754 double bits
        HcEmit(0x9E670200);      // fmov d0, x16
        g_hc_expr_float = 1;
        return;
    }
    if (g_hc_tok == TOK_NUMBER) {
        I64 val = g_hc_tok_val;
        HcLexNext();
        HcEmitImm64(0, val);
        return;
    }
    if (g_hc_tok == TOK_STRING) {
        I64 str_ptr = g_hc_tok_val;
        HcLexNext();
        HcEmitImm64(0, str_ptr);
        return;
    }
    if (g_hc_tok == TOK_LPAREN) {
        HcLexNext();
        // Check for C-style typecast: (I64), (U8*), (U32*), etc.
        if (HcIsTypeToken(g_hc_tok) || (g_hc_tok == TOK_IDENT && HcFindStruct(g_hc_tok_str) >= 0)) {
            I64 cast_tok = g_hc_tok;
            HcLexNext();
            I64 cast_is_ptr = 0;
            while (g_hc_tok == TOK_STAR) { cast_is_ptr = 1; HcLexNext(); }
            if (g_hc_tok == TOK_RPAREN) HcLexNext();
            HcCallParseExpr();
            // Numeric conversions (skip pointer casts).
            if (!cast_is_ptr) {
                if (cast_tok == TOK_TYPE_F64) {
                    if (!g_hc_expr_float) { HcEmit(0x9E620000); g_hc_expr_float = 1; } // scvtf d0, x0
                } else if (cast_tok == TOK_TYPE_I64 || cast_tok == TOK_TYPE_U8 ||
                           cast_tok == TOK_TYPE_U16 || cast_tok == TOK_TYPE_U32) {
                    if (g_hc_expr_float) { HcEmit(0x9E780000); g_hc_expr_float = 0; } // fcvtzs x0, d0
                }
            }
            return;
        }
        HcCallParseExpr();
        if (g_hc_tok == TOK_RPAREN) HcLexNext();
        return;
    }
    if (g_hc_tok == TOK_IDENT) {
        U8 ident_name[64];
        HcSafeCopy(ident_name, g_hc_tok_str, 64);
        HcLexNext();

        // Direct Function Call: ident(arg1, arg2, ...)
        if (g_hc_tok == TOK_LPAREN && HcFindLocalIdx(ident_name) < 0) {
            I64 is_intr = HcIsIntrinsic(ident_name);
            U64 fn_target = is_intr ? 0 : HcFindFunc(ident_name);
            if (!fn_target && !is_intr) {
                doldoc_printf("$FG,RED$[COMPILER.HC ERROR] Unknown function: %s$FG$\n", ident_name);
            }
            HcOpPush(fn_target);

            HcLexNext(); // eat '('
            I64 cur_argc = 0;
            if (g_hc_tok != TOK_RPAREN) {
                while (1) {
                    HcOpPush(cur_argc);
                    HcCallParseExpr();
                    cur_argc = HcOpPop();
                    if (cur_argc >= 0 && cur_argc < 32) g_hc_arg_float[cur_argc] = g_hc_expr_float;
                    else g_hc_error = 1;
                    if (g_hc_expr_float) HcEmit(0x9E660000); // fmov x0, d0 (save bits)
                    HcEmitPush(0);
                    cur_argc++;
                    if (g_hc_tok == TOK_COMMA) HcLexNext();
                    else break;
                }
            }
            if (g_hc_tok == TOK_RPAREN) HcLexNext(); // eat ')'

            I64 a_reg = 0;
            for (a_reg = cur_argc - 1; a_reg >= 0; a_reg--) {
                HcEmitPop(a_reg);
                if (g_hc_arg_float[a_reg]) {
                    HcEmit(0x9E670000 | (a_reg << 5) | a_reg); // fmov d{a_reg}, x{a_reg}
                }
            }

            if (is_intr) {
                HcOpPop(); // discard placeholder target
                HcEmitIntrinsic(ident_name);
                return;
            }

            U64 target = HcOpPop();
            HcEmitImm64(16, target);
            HcEmit(0xD63F0200); // blr x16
            g_hc_expr_float = HcFuncIsFloat(ident_name);
            return;
        }

        // LValue resolution for variables, arrays, and struct fields
        I64 lv_scale = 8;
        I64 lv_addr_only = 0;
        HcResolveLValue(ident_name, &lv_scale, &lv_addr_only);

        // Post-increment / Post-decrement inside expression: x++ or x--
        if (g_hc_tok == TOK_PLUSPLUS || g_hc_tok == TOK_MINUSMINUS) {
            I64 is_pinc = (g_hc_tok == TOK_PLUSPLUS);
            HcLexNext();
            HcEmit(0xAA0003E1); // mov x1, x0 (address in x1)
            HcEmitLoadSized(0, 1, lv_scale); // x0 = old value
            if (is_pinc) HcEmit(0x91000402); // add x2, x0, #1
            else HcEmit(0xD1000402);         // sub x2, x0, #1
            HcEmitStoreSized(2, 1, lv_scale);
            return;
        }

        if (!lv_addr_only) {
            I64 ridx = HcFindLocalIdx(ident_name);
            if (ridx >= 0 && g_hc_local_is_float[ridx]) {
                HcEmit(0xFD400000); // ldr d0, [x0]  (F64 local)
                g_hc_expr_float = 1;
            } else {
                HcEmitLoadSized(0, 0, lv_scale);
            }
        }

        // Indirect Function Pointer or Struct Method Call: obj->fn(arg1, ...)
        if (g_hc_tok == TOK_LPAREN) {
            HcEmitPush(0); // Save function pointer on stack
            HcLexNext(); // eat '('
            I64 ind_argc = 0;
            if (g_hc_tok != TOK_RPAREN) {
                while (1) {
                    HcOpPush(ind_argc);
                    HcCallParseExpr();
                    ind_argc = HcOpPop();
                    HcEmitPush(0);
                    ind_argc++;
                    if (g_hc_tok == TOK_COMMA) HcLexNext();
                    else break;
                }
            }
            if (g_hc_tok == TOK_RPAREN) HcLexNext(); // eat ')'
            I64 ia_reg = 0;
            for (ia_reg = ind_argc - 1; ia_reg >= 0; ia_reg--) {
                HcEmitPop(ia_reg);
            }
            HcEmitPop(16); // Pop function pointer into x16
            HcEmit(0xD63F0200); // blr x16
        }
        return;
    }
}

U0 HcParseUnary() {
    if (g_hc_tok == TOK_MINUS) {
        HcLexNext();
        HcParseUnary();
        HcEmit(0xCB0003E0); // neg x0, x0
        return;
    }
    if (g_hc_tok == TOK_EXCLAM) {
        HcLexNext();
        HcParseUnary();
        HcEmit(0xF100001F); // cmp x0, #0
        HcEmit(0x9A9F17E0); // cset x0, eq
        return;
    }
    if (g_hc_tok == TOK_TILDE) {
        HcLexNext();
        HcParseUnary();
        HcEmit(0xAA2003E0); // mvn x0, x0
        return;
    }
    if (g_hc_tok == TOK_AMPERSAND) {
        HcLexNext();
        if (g_hc_tok == TOK_IDENT) {
            U8 amp_name[64];
            HcSafeCopy(amp_name, g_hc_tok_str, 64);
            HcLexNext();
            if (HcFindLocalIdx(amp_name) < 0) {
                U64 fn_a = HcFindFunc(amp_name);
                if (fn_a) {
                    HcEmitImm64(0, fn_a);
                    return;
                }
            }
            I64 amp_scale = 8;
            I64 amp_ao = 0;
            HcResolveLValue(amp_name, &amp_scale, &amp_ao);
            return;
        }
        HcParseUnary();
        return;
    }
    if (g_hc_tok == TOK_SIZEOF) {
        HcLexNext();
        if (g_hc_tok == TOK_LPAREN) HcLexNext();
        I64 sz_val = 8;
        if (HcIsTypeToken(g_hc_tok)) {
            sz_val = HcTypeTokenScale(g_hc_tok);
            HcLexNext();
        } else if (g_hc_tok == TOK_IDENT) {
            I64 st_i = HcFindStruct(g_hc_tok_str);
            if (st_i >= 0) {
                sz_val = g_hc_struct_sizes[st_i];
            } else {
                I64 loc_i = HcFindLocalIdx(g_hc_tok_str);
                if (loc_i >= 0) sz_val = g_hc_local_scales[loc_i];
            }
            HcLexNext();
        }
        while (g_hc_tok == TOK_STAR) {
            sz_val = 8;
            HcLexNext();
        }
        if (g_hc_tok == TOK_RPAREN) HcLexNext();
        HcEmitImm64(0, sz_val);
        return;
    }
    if (g_hc_tok == TOK_STAR) {
        HcLexNext();
        I64 deref_sz = -1;
        // Check for *(U8*) / *(U16*) / *(U32*) / *(I64*) cast
        if (g_hc_tok == TOK_LPAREN) {
            I64 sv_p = g_hc_pos;
            I64 sv_t = g_hc_tok;
            I64 sv_v = g_hc_tok_val;
            U8  sv_s[256];
            HcSafeCopy(sv_s, g_hc_tok_str, 256);
            HcLexNext(); // eat '('
            if (HcIsTypeToken(g_hc_tok)) {
                I64 c_sz = HcTypeTokenScale(g_hc_tok);
                HcLexNext();
                if (g_hc_tok == TOK_STAR) {
                    HcLexNext();
                    if (g_hc_tok == TOK_RPAREN) {
                        HcLexNext();
                        deref_sz = c_sz;
                    }
                }
            }
            if (deref_sz < 0) {
                g_hc_pos = sv_p;
                g_hc_tok = sv_t;
                g_hc_tok_val = sv_v;
                HcSafeCopy(g_hc_tok_str, sv_s, 256);
            }
        }
        if (deref_sz < 0 && g_hc_tok == TOK_IDENT) {
            I64 ptr_loc = HcFindLocalIdx(g_hc_tok_str);
            if (ptr_loc >= 0 && g_hc_local_is_ptr[ptr_loc] == 1) {
                deref_sz = g_hc_local_scales[ptr_loc];
            }
        }
        if (deref_sz < 0) deref_sz = 8;
        HcOpPush(deref_sz);
        HcParseUnary();
        deref_sz = HcOpPop();
        HcEmitLoadSized(0, 0, deref_sz);
        return;
    }
    HcParsePrimary();
}

U0 HcParseMultiplicative() {
    HcParseUnary();
    I64 lf = g_hc_expr_float;
    while (g_hc_tok == TOK_STAR || g_hc_tok == TOK_SLASH || g_hc_tok == TOK_PERCENT) {
        HcOpPush(g_hc_tok);
        HcLexNext();
        if (lf) HcEmit(0x9E660000); // fmov x0, d0 (save left bits)
        HcEmitPush(0);
        HcParseUnary();
        I64 rf = g_hc_expr_float;
        I64 isf = (lf || rf);
        if (isf) {
            HcEmit(0x9E660001); // fmov x1, d0 (right)
            HcEmitPop(0);
            HcEmit(0x9E670000); // fmov d0, x0 (left)
            HcEmit(0x9E670021); // fmov d1, x1 (right)
            I64 op = HcOpPop();
            if (op == TOK_SLASH) HcEmit(0x1E611800); // fdiv d0,d0,d1
            else HcEmit(0x1E610800);                 // fmul d0,d0,d1
        } else {
            HcEmit(0xAA0003E1); // mov x1, x0
            HcEmitPop(0);
            I64 cur_mul_op = HcOpPop();
            if (cur_mul_op == TOK_STAR) {
                HcEmit(0x9B017C00); // mul x0, x0, x1
            } else if (cur_mul_op == TOK_SLASH) {
                HcEmit(0x9AC10C00); // sdiv x0, x0, x1
            } else if (cur_mul_op == TOK_PERCENT) {
                HcEmit(0x9AC10C02); // sdiv x2, x0, x1
                HcEmit(0x9B018040); // msub x0, x2, x1, x0
            }
        }
        lf = isf;
    }
    g_hc_expr_float = lf;
}

U0 HcParseAdditive() {
    HcParseMultiplicative();
    I64 lf = g_hc_expr_float;
    while (g_hc_tok == TOK_PLUS || g_hc_tok == TOK_MINUS) {
        HcOpPush(g_hc_tok);
        HcLexNext();
        if (lf) HcEmit(0x9E660000); // fmov x0, d0
        HcEmitPush(0);
        HcParseMultiplicative();
        I64 rf = g_hc_expr_float;
        I64 isf = (lf || rf);
        if (isf) {
            HcEmit(0x9E660001); // fmov x1, d0 (right)
            HcEmitPop(0);
            HcEmit(0x9E670000); // fmov d0, x0 (left)
            HcEmit(0x9E670021); // fmov d1, x1 (right)
            I64 op = HcOpPop();
            if (op == TOK_MINUS) HcEmit(0x1E613800); // fsub d0,d0,d1
            else HcEmit(0x1E612800);                 // fadd d0,d0,d1
        } else {
            HcEmit(0xAA0003E1); // mov x1, x0
            HcEmitPop(0);
            I64 cur_add_op = HcOpPop();
            if (cur_add_op == TOK_PLUS) {
                HcEmit(0x8B010000); // add x0, x0, x1
            } else {
                HcEmit(0xCB010000); // sub x0, x0, x1
            }
        }
        lf = isf;
    }
    g_hc_expr_float = lf;
}

U0 HcParseShift() {
    HcParseAdditive();
    while (g_hc_tok == TOK_SHL || g_hc_tok == TOK_SHR) {
        HcOpPush(g_hc_tok);
        HcLexNext();
        HcEmitPush(0);
        HcParseAdditive();
        HcEmit(0xAA0003E1); // mov x1, x0
        HcEmitPop(0);

        I64 cur_shift_op = HcOpPop();
        if (cur_shift_op == TOK_SHL) {
            HcEmit(0x9AC12000); // lsl x0, x0, x1
        } else {
            HcEmit(0x9AC12800); // asr x0, x0, x1
        }
    }
}

U0 HcParseRelational() {
    HcParseShift();
    I64 lf = g_hc_expr_float;
    while (g_hc_tok == TOK_LT || g_hc_tok == TOK_LTE || g_hc_tok == TOK_GT || g_hc_tok == TOK_GTE) {
        HcOpPush(g_hc_tok);
        HcLexNext();
        if (lf) HcEmit(0x9E660000); // fmov x0, d0
        HcEmitPush(0);
        HcParseShift();
        I64 rf = g_hc_expr_float;
        I64 isf = (lf || rf);
        if (isf) {
            HcEmit(0x9E660001); // fmov x1, d0 (right)
            HcEmitPop(0);
            HcEmit(0x9E670000); // fmov d0, x0 (left)
            HcEmit(0x9E670021); // fmov d1, x1 (right)
            HcEmit(0x1E612000); // fcmp d0, d1
        } else {
            HcEmit(0xAA0003E1); // mov x1, x0
            HcEmitPop(0);
            HcEmit(0xEB01001F); // cmp x0, x1
        }
        I64 cur_rel_op = HcOpPop();
        if (cur_rel_op == TOK_LT) HcEmit(0x9A9FA7E0);       // cset x0, lt
        else if (cur_rel_op == TOK_LTE) HcEmit(0x9A9FC7E0); // cset x0, le
        else if (cur_rel_op == TOK_GT) HcEmit(0x9A9FD7E0);  // cset x0, gt
        else if (cur_rel_op == TOK_GTE) HcEmit(0x9A9FB7E0); // cset x0, ge
        lf = 0;
    }
    g_hc_expr_float = lf;
}

U0 HcParseEquality() {
    HcParseRelational();
    I64 lf = g_hc_expr_float;
    while (g_hc_tok == TOK_EQEQ || g_hc_tok == TOK_NEQ) {
        HcOpPush(g_hc_tok);
        HcLexNext();
        if (lf) HcEmit(0x9E660000); // fmov x0, d0
        HcEmitPush(0);
        HcParseRelational();
        I64 rf = g_hc_expr_float;
        I64 isf = (lf || rf);
        if (isf) {
            HcEmit(0x9E660001); // fmov x1, d0
            HcEmitPop(0);
            HcEmit(0x9E670000); // fmov d0, x0
            HcEmit(0x9E670021); // fmov d1, x1
            HcEmit(0x1E612000); // fcmp d0, d1
        } else {
            HcEmit(0xAA0003E1); // mov x1, x0
            HcEmitPop(0);
            HcEmit(0xEB01001F); // cmp x0, x1
        }
        I64 cur_eq_op = HcOpPop();
        if (cur_eq_op == TOK_EQEQ) HcEmit(0x9A9F17E0); // cset x0, eq
        else HcEmit(0x9A9F07E0);                       // cset x0, ne
        lf = 0;
    }
    g_hc_expr_float = lf;
}

U0 HcParseBitAnd() {
    HcParseEquality();
    while (g_hc_tok == TOK_AMPERSAND) {
        HcLexNext();
        HcEmitPush(0);
        HcParseEquality();
        HcEmit(0xAA0003E1); // mov x1, x0
        HcEmitPop(0);
        HcEmit(0x8A010000); // and x0, x0, x1
    }
}

U0 HcParseBitXor() {
    HcParseBitAnd();
    while (g_hc_tok == TOK_CARET) {
        HcLexNext();
        HcEmitPush(0);
        HcParseBitAnd();
        HcEmit(0xAA0003E1); // mov x1, x0
        HcEmitPop(0);
        HcEmit(0xCA010000); // eor x0, x0, x1
    }
}

U0 HcParseBitOr() {
    HcParseBitXor();
    while (g_hc_tok == TOK_PIPE) {
        HcLexNext();
        HcEmitPush(0);
        HcParseBitXor();
        HcEmit(0xAA0003E1); // mov x1, x0
        HcEmitPop(0);
        HcEmit(0xAA010000); // orr x0, x0, x1
    }
}

U0 HcParseLogAnd() {
    HcParseBitOr();
    while (g_hc_tok == TOK_ANDAND) {
        HcLexNext();
        HcOpPush(g_hc_code_len);
        HcEmit(0xB4000000); // cbz x0, 0
        HcParseBitOr();
        HcEmit(0xF100001F); // cmp x0, #0
        HcEmit(0x9A9F07E0); // cset x0, ne
        HcOpPush(g_hc_code_len);
        HcEmit(0x14000000); // b end
        I64 p_b = HcOpPop();
        I64 p_cbz = HcOpPop();
        HcBackpatchCbz(p_cbz, g_hc_code_len);
        HcEmit(0xD2800000); // movz x0, #0
        HcBackpatchB(p_b, g_hc_code_len);
    }
}

U0 HcParseLogOr() {
    HcParseLogAnd();
    while (g_hc_tok == TOK_PIPEPIPE) {
        HcLexNext();
        HcOpPush(g_hc_code_len);
        HcEmit(0xB5000000); // cbnz x0, 0
        HcParseLogAnd();
        HcEmit(0xF100001F); // cmp x0, #0
        HcEmit(0x9A9F07E0); // cset x0, ne
        HcOpPush(g_hc_code_len);
        HcEmit(0x14000000); // b end
        I64 p_b = HcOpPop();
        I64 patch_idx = HcOpPop();
        I64 rel = (g_hc_code_len - patch_idx) & 0x7FFFF;
        g_hc_code[patch_idx] = 0xB5000000 | (rel << 5) | 0; // Preserve CBNZ!
        HcEmit(0xD2800020); // movz x0, #1
        HcBackpatchB(p_b, g_hc_code_len);
    }
}

I64 HcIsIntrinsic(U8 *name) {
    return (strcmp(name, "__wfe") == 0 || strcmp(name, "__sev") == 0 || strcmp(name, "__dmb_ish") == 0 ||
            strcmp(name, "__dsb_sy") == 0 || strcmp(name, "__isb") == 0 || strcmp(name, "__mrs_cntvct") == 0 ||
            strcmp(name, "__mrs_cntfrq") == 0 || strcmp(name, "__mrs_mpidr") == 0 || strcmp(name, "__mrs_esr") == 0 ||
            strcmp(name, "__mrs_far") == 0 || strcmp(name, "__dc_civac") == 0 || strcmp(name, "__ic_ivau") == 0 ||
            strcmp(name, "__mmio_r32") == 0 || strcmp(name, "__mmio_w32") == 0);
}

U0 HcEmitIntrinsic(U8 *name) {
    if (strcmp(name, "__wfe") == 0) HcEmit(0xD503205F);
    else if (strcmp(name, "__sev") == 0) HcEmit(0xD503209F);
    else if (strcmp(name, "__dmb_ish") == 0) HcEmit(0xD5033BBF);
    else if (strcmp(name, "__dsb_sy") == 0) HcEmit(0xD5033F9F);
    else if (strcmp(name, "__isb") == 0) HcEmit(0xD5033FDF);
    else if (strcmp(name, "__mrs_cntvct") == 0) HcEmit(0xD53BE040);
    else if (strcmp(name, "__mrs_cntfrq") == 0) HcEmit(0xD53BE000);
    else if (strcmp(name, "__mrs_mpidr") == 0) { HcEmit(0xD53800A0); HcEmit(0x92400400); }
    else if (strcmp(name, "__mrs_esr") == 0) HcEmit(0xD5385200);
    else if (strcmp(name, "__mrs_far") == 0) HcEmit(0xD5386000);
    else if (strcmp(name, "__dc_civac") == 0) HcEmit(0xD50B7E20);
    else if (strcmp(name, "__ic_ivau") == 0) HcEmit(0xD50B7520);
    else if (strcmp(name, "__mmio_r32") == 0) HcEmit(0xB9400000);
    else if (strcmp(name, "__mmio_w32") == 0) HcEmit(0xB9000001);
}

U0 HcParseExpr() {
    HcParseLogOr();
    if (g_hc_tok == TOK_QUESTION) {
        HcLexNext(); // eat '?'
        HcOpPush(g_hc_code_len);
        HcEmit(0xB4000000); // cbz x0, false_branch
        HcCallParseExpr();  // true_branch in x0
        if (g_hc_tok == TOK_COLON) HcLexNext(); // eat ':'
        HcOpPush(g_hc_code_len);
        HcEmit(0x14000000); // b end_ternary
        I64 p_end = HcOpPop();
        I64 p_false = HcOpPop();
        HcBackpatchCbz(p_false, g_hc_code_len);
        HcCallParseExpr();  // false_branch in x0
        HcBackpatchB(p_end, g_hc_code_len);
    }
}

// ------------------------------------------------------------------------------
// Struct / Class Definition Parser & Assignment Helper
// ------------------------------------------------------------------------------
U0 HcParseStructDef() {
    HcLexNext(); // eat 'class' or 'struct'
    if (g_hc_tok != TOK_IDENT) return;
    U8 st_name[64];
    HcSafeCopy(st_name, g_hc_tok_str, 64);
    HcLexNext();

    I64 st_idx = HcAddStruct(st_name);
    if (g_hc_tok != TOK_LBRACE) return;
    HcLexNext(); // eat '{'

    I64 cur_off = 0;
    I64 m_cnt = 0;

    while (g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF) {
        I64 base_sz = 8;
        I64 sub_st = -1;
        if (HcIsTypeToken(g_hc_tok)) {
            base_sz = HcTypeTokenScale(g_hc_tok);
            HcLexNext();
        } else if (g_hc_tok == TOK_IDENT) {
            sub_st = HcFindStruct(g_hc_tok_str);
            if (sub_st >= 0) base_sz = g_hc_struct_sizes[sub_st];
            HcLexNext();
        } else {
            HcLexNext();
            continue;
        }

        // Check for function pointer member: Type (*name)(params...);
        if (g_hc_tok == TOK_LPAREN) {
            HcLexNext(); // eat '('
            if (g_hc_tok == TOK_STAR) HcLexNext();
            U8 fp_name[64];
            fp_name[0] = 0;
            if (g_hc_tok == TOK_IDENT) {
                HcSafeCopy(fp_name, g_hc_tok_str, 64);
                HcLexNext();
            }
            if (g_hc_tok == TOK_RPAREN) HcLexNext();
            if (g_hc_tok == TOK_LPAREN) {
                I64 p_depth = 1;
                HcLexNext();
                while (p_depth > 0 && g_hc_tok != TOK_EOF) {
                    if (g_hc_tok == TOK_LPAREN) p_depth++;
                    else if (g_hc_tok == TOK_RPAREN) p_depth--;
                    HcLexNext();
                }
            }
            cur_off = (cur_off + 7) & (~7);
            if (fp_name[0] && m_cnt < 16) {
                I64 fp_slot = st_idx * 16 + m_cnt;
                HcSafeCopy(&g_hc_member_names[fp_slot * 32], fp_name, 32);
                g_hc_member_offsets[fp_slot] = cur_off;
                g_hc_member_sizes[fp_slot] = 8;
                g_hc_member_is_arr[fp_slot] = 0;
                g_hc_member_is_ptr[fp_slot] = 1;
                g_hc_member_st_idx[fp_slot] = -1;
                m_cnt++;
            }
            cur_off += 8;
            if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
            continue;
        }

        while (1) {
            I64 is_p = 0;
            while (g_hc_tok == TOK_STAR) {
                is_p = 1;
                HcLexNext();
            }
            if (g_hc_tok == TOK_IDENT) {
                U8 mem_n[64];
                HcSafeCopy(mem_n, g_hc_tok_str, 64);
                HcLexNext();

                I64 elem_sz = is_p ? 8 : base_sz;
                I64 field_bytes = elem_sz;
                I64 is_a = 0;
                if (g_hc_tok == TOK_LBRACKET) {
                    HcLexNext();
                    I64 acnt = 1;
                    if (g_hc_tok == TOK_NUMBER) {
                        acnt = g_hc_tok_val;
                        HcLexNext();
                    }
                    if (g_hc_tok == TOK_RBRACKET) HcLexNext();
                    field_bytes = elem_sz * acnt;
                    is_a = 1;
                }

                if (elem_sz >= 8) cur_off = (cur_off + 7) & (~7);
                else if (elem_sz == 4) cur_off = (cur_off + 3) & (~3);
                else if (elem_sz == 2) cur_off = (cur_off + 1) & (~1);

                if (m_cnt < 16) {
                    I64 m_slot = st_idx * 16 + m_cnt;
                    HcSafeCopy(&g_hc_member_names[m_slot * 32], mem_n, 32);
                    g_hc_member_offsets[m_slot] = cur_off;
                    g_hc_member_sizes[m_slot] = (is_p || elem_sz > 8) ? 8 : elem_sz;
                    g_hc_member_is_arr[m_slot] = is_a;
                    g_hc_member_is_ptr[m_slot] = is_p;
                    g_hc_member_st_idx[m_slot] = sub_st;
                    m_cnt++;
                }
                cur_off += field_bytes;
            }
            if (g_hc_tok == TOK_COMMA) HcLexNext();
            else break;
        }
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
    }

    if (g_hc_tok == TOK_RBRACE) HcLexNext();
    if (g_hc_tok == TOK_SEMICOLON) HcLexNext();

    I64 aligned_tot = (cur_off + 7) & (~7);
    if (aligned_tot <= 0) aligned_tot = 8;
    g_hc_struct_sizes[st_idx] = aligned_tot;
    g_hc_struct_mcount[st_idx] = m_cnt;
}

I64 HcIsAssignOp(I64 tok) {
    if (tok == TOK_EQUAL || tok == TOK_PLUSEQ || tok == TOK_MINUSEQ ||
        tok == TOK_STAREQ || tok == TOK_SLASHEQ || tok == TOK_PERCENTEQ ||
        tok == TOK_ANDEQ || tok == TOK_PIPEEQ || tok == TOK_CARETEQ ||
        tok == TOK_SHLEQ || tok == TOK_SHREQ ||
        tok == TOK_PLUSPLUS || tok == TOK_MINUSMINUS) {
        return 1;
    }
    return 0;
}

U0 HcFinishMemoryAssign(I64 mem_scale) {
    if (g_hc_tok == TOK_EQUAL) {
        HcLexNext(); // eat '='
        HcEmitPush(0); // save target address
        HcParseExpr(); // RHS in x0
        HcEmitPop(1);  // target address in x1
        HcEmitStoreSized(0, 1, mem_scale);
        return;
    }
    if (g_hc_tok == TOK_PLUSPLUS || g_hc_tok == TOK_MINUSMINUS) {
        I64 is_inc = (g_hc_tok == TOK_PLUSPLUS);
        HcLexNext();
        HcEmit(0xAA0003E1); // mov x1, x0
        HcEmitLoadSized(0, 1, mem_scale);
        if (is_inc) HcEmit(0x91000400); // add x0, x0, #1
        else HcEmit(0xD1000400);        // sub x0, x0, #1
        HcEmitStoreSized(0, 1, mem_scale);
        return;
    }
    if (HcIsAssignOp(g_hc_tok)) {
        I64 cop = g_hc_tok;
        HcLexNext();
        HcEmitPush(0); // save target address
        HcParseExpr(); // RHS in x0
        HcEmit(0xAA0003E2); // mov x2, x0 (RHS in x2)
        HcEmitPop(1);       // target address in x1
        HcEmitLoadSized(0, 1, mem_scale); // LHS in x0

        if (cop == TOK_PLUSEQ) HcEmit(0x8B020000);       // add x0, x0, x2
        else if (cop == TOK_MINUSEQ) HcEmit(0xCB020000); // sub x0, x0, x2
        else if (cop == TOK_STAREQ) HcEmit(0x9B027C00);  // mul x0, x0, x2
        else if (cop == TOK_SLASHEQ) HcEmit(0x9AC20C00); // sdiv x0, x0, x2
        else if (cop == TOK_PERCENTEQ) {
            HcEmit(0x9AC20C03); // sdiv x3, x0, x2
            HcEmit(0x9B028060); // msub x0, x3, x2, x0
        }
        else if (cop == TOK_ANDEQ) HcEmit(0x8A020000);   // and x0, x0, x2
        else if (cop == TOK_PIPEEQ) HcEmit(0xAA020000);  // orr x0, x0, x2
        else if (cop == TOK_CARETEQ) HcEmit(0xCA020000); // eor x0, x0, x2
        else if (cop == TOK_SHLEQ) HcEmit(0x9AC22000);   // lsl x0, x0, x2
        else if (cop == TOK_SHREQ) HcEmit(0x9AC22800);   // asr x0, x0, x2

        HcEmitStoreSized(0, 1, mem_scale);
    }
}

// ------------------------------------------------------------------------------
// Statement & Program Parser
// ------------------------------------------------------------------------------
U0 HcParseStatement() {
    // Inline assembly: asm { 0xWORD, 0xWORD, ... }  (raw AArch64 instruction words)
    if (g_hc_tok == TOK_IDENT && strcmp(g_hc_tok_str, "asm") == 0) {
        HcLexNext(); // eat 'asm'
        if (g_hc_tok == TOK_LBRACE) {
            HcLexNext(); // eat '{'
            while (g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF) {
                if (g_hc_tok == TOK_NUMBER) {
                    HcEmit((U32)g_hc_tok_val);
                    HcLexNext();
                } else if (g_hc_tok == TOK_COMMA || g_hc_tok == TOK_SEMICOLON) {
                    HcLexNext();
                } else {
                    break;
                }
            }
            if (g_hc_tok == TOK_RBRACE) HcLexNext();
            if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
            return;
        }
    }

    // Struct / Class Declaration
    if (g_hc_tok == TOK_CLASS || g_hc_tok == TOK_STRUCT) {
        HcParseStructDef();
        return;
    }

    // Variable Declaration: Type [*] ident [= expr], ...;
    if (HcIsTypeToken(g_hc_tok) || (g_hc_tok == TOK_IDENT && HcFindStruct(g_hc_tok_str) >= 0)) {
        I64 base_scale = 8;
        I64 st_idx = -1;
        I64 base_is_float = (g_hc_tok == TOK_TYPE_F64);
        if (HcIsTypeToken(g_hc_tok)) {
            base_scale = HcTypeTokenScale(g_hc_tok);
        } else {
            st_idx = HcFindStruct(g_hc_tok_str);
            base_scale = g_hc_struct_sizes[st_idx];
        }
        HcLexNext(); // eat Type

        // Check for local function pointer: Type (*fn)(...) = expr;
        if (g_hc_tok == TOK_LPAREN) {
            HcLexNext();
            if (g_hc_tok == TOK_STAR) HcLexNext();
            U8 fn_vname[64];
            fn_vname[0] = 0;
            if (g_hc_tok == TOK_IDENT) {
                HcSafeCopy(fn_vname, g_hc_tok_str, 64);
                HcLexNext();
            }
            if (g_hc_tok == TOK_RPAREN) HcLexNext();
            if (g_hc_tok == TOK_LPAREN) {
                I64 fp_d = 1;
                HcLexNext();
                while (fp_d > 0 && g_hc_tok != TOK_EOF) {
                    if (g_hc_tok == TOK_LPAREN) fp_d++;
                    else if (g_hc_tok == TOK_RPAREN) fp_d--;
                    HcLexNext();
                }
            }
            I64 fp_off = HcAddLocalTyped(fn_vname, 8, 1, -1, 1);
            if (g_hc_tok == TOK_EQUAL) {
                HcLexNext();
                HcParseExpr();
            } else {
                HcEmitImm64(0, 0);
            }
            HcEmitStoreLocal(0, fp_off);
            if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
            return;
        }

        while (1) {
            I64 is_p = 0;
            while (g_hc_tok == TOK_STAR) {
                is_p++;
                HcLexNext();
            }
            if (g_hc_tok == TOK_IDENT) {
                U8 vname[64];
                HcSafeCopy(vname, g_hc_tok_str, 64);
                HcLexNext();

                if (g_hc_tok == TOK_LBRACKET) {
                    HcLexNext();
                    I64 arr_cnt = 1;
                    if (g_hc_tok == TOK_NUMBER) {
                        arr_cnt = g_hc_tok_val;
                        HcLexNext();
                    }
                    if (g_hc_tok == TOK_RBRACKET) HcLexNext();
                    I64 arr_elem_sz = (is_p > 0) ? 8 : base_scale;
                    HcAddLocalTyped(vname, arr_elem_sz, 2, (is_p > 0) ? -1 : st_idx, arr_cnt);
                } else if (st_idx >= 0 && is_p == 0) {
                    HcAddLocalTyped(vname, base_scale, 3, st_idx, 1);
                } else {
                    I64 var_scale = (is_p > 0) ? base_scale : 8;
                    I64 ptr_mode = (is_p > 0) ? 1 : 0;
                    I64 decl_is_f = (is_p == 0 && base_is_float);
                    g_hc_decl_float = decl_is_f;
                    I64 decl_off = HcAddLocalTyped(vname, var_scale, ptr_mode, st_idx, 1);
                    g_hc_decl_float = 0;
                    if (g_hc_tok == TOK_EQUAL) {
                        HcLexNext(); // eat '='
                        HcParseExpr(); // result in x0 (or d0 if float)
                    } else {
                        HcEmitImm64(0, 0);
                    }
                    if (decl_is_f) {
                        HcEmit(0xFD0003A0 | ((decl_off >> 3) << 10)); // str d0, [x29, #off]
                        g_hc_expr_float = 0;
                    } else {
                        HcEmitStoreLocal(0, decl_off);
                    }
                }
            }
            if (g_hc_tok == TOK_COMMA) HcLexNext();
            else break;
        }
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
        return;
    }

    // Return Statement: return [expr];
    if (g_hc_tok == TOK_RETURN) {
        HcLexNext();
        if (g_hc_tok != TOK_SEMICOLON) {
            HcParseExpr();
        } else {
            HcEmitImm64(0, 0);
        }
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
        HcEmitEpilogue();
        return;
    }

    // Break Statement: break;
    if (g_hc_tok == TOK_BREAK) {
        HcLexNext();
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
        HcRecordBreak();
        return;
    }

    // Continue Statement: continue;
    if (g_hc_tok == TOK_CONTINUE) {
        HcLexNext();
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
        HcRecordContinue();
        return;
    }

    // Conditional: if (cond) stmt [else stmt]
    if (g_hc_tok == TOK_IF) {
        HcLexNext();
        if (g_hc_tok == TOK_LPAREN) HcLexNext();
        HcParseExpr();
        if (g_hc_tok == TOK_RPAREN) HcLexNext();

        HcOpPush(g_hc_code_len);
        HcEmit(0xB4000000); // cbz x0, 0
        HcCallParseStmt();

        I64 p_cbz = HcOpPop();
        if (g_hc_tok == TOK_ELSE) {
            HcLexNext();
            HcOpPush(g_hc_code_len);
            HcEmit(0x14000000); // b 0
            HcBackpatchCbz(p_cbz, g_hc_code_len);
            HcCallParseStmt();
            I64 p_b = HcOpPop();
            HcBackpatchB(p_b, g_hc_code_len);
        } else {
            HcBackpatchCbz(p_cbz, g_hc_code_len);
        }
        return;
    }

    // Loop: while (cond) stmt
    if (g_hc_tok == TOK_WHILE) {
        HcLexNext();
        I64 w_lvl = HcPushLoopCtx(0);
        I64 loop_start = g_hc_code_len;
        if (g_hc_tok == TOK_LPAREN) HcLexNext();
        HcParseExpr();
        if (g_hc_tok == TOK_RPAREN) HcLexNext();

        HcOpPush(w_lvl);
        HcOpPush(loop_start);
        HcOpPush(g_hc_code_len);
        HcEmit(0xB4000000); // cbz x0, 0
        HcCallParseStmt();

        I64 patch_exit = HcOpPop();
        I64 l_start = HcOpPop();
        I64 pop_lvl = HcOpPop();
        HcPatchContinues(pop_lvl, l_start);
        I64 diff = l_start - g_hc_code_len;
        HcEmit(0x14000000 | (diff & 0x03FFFFFF)); // b loop_start
        HcBackpatchCbz(patch_exit, g_hc_code_len);
        HcPatchBreaks(pop_lvl, g_hc_code_len);
        HcPopLoopCtx();
        return;
    }

    // Loop: do stmt while (cond);
    if (g_hc_tok == TOK_DO) {
        HcLexNext();
        I64 d_lvl = HcPushLoopCtx(0);
        I64 do_start = g_hc_code_len;
        HcOpPush(d_lvl);
        HcOpPush(do_start);

        HcCallParseStmt();

        I64 pop_do_start = HcOpPop();
        I64 pop_d_lvl = HcOpPop();
        I64 cond_idx = g_hc_code_len;
        HcPatchContinues(pop_d_lvl, cond_idx);

        if (g_hc_tok == TOK_WHILE) HcLexNext();
        if (g_hc_tok == TOK_LPAREN) HcLexNext();
        HcParseExpr();
        if (g_hc_tok == TOK_RPAREN) HcLexNext();
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();

        I64 do_rel = (pop_do_start - g_hc_code_len) & 0x7FFFF;
        HcEmit(0xB5000000 | (do_rel << 5) | 0); // cbnz x0, do_start
        HcPatchBreaks(pop_d_lvl, g_hc_code_len);
        HcPopLoopCtx();
        return;
    }

    // Loop: for (init; cond; step) stmt
    if (g_hc_tok == TOK_FOR) {
        HcLexNext();
        if (g_hc_tok == TOK_LPAREN) HcLexNext();

        // 1. Parse init
        if (g_hc_tok != TOK_SEMICOLON) {
            HcCallParseStmt();
        } else {
            HcLexNext(); // eat ';'
        }

        // 2. Parse cond
        I64 f_cond_idx = g_hc_code_len;
        if (g_hc_tok != TOK_SEMICOLON) {
            HcParseExpr();
        } else {
            HcEmitImm64(0, 1);
        }
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext(); // eat ';'

        I64 f_patch_exit = g_hc_code_len;
        HcEmit(0xB4000000); // cbz x0, exit
        I64 f_patch_body = g_hc_code_len;
        HcEmit(0x14000000); // b body

        // 3. Parse step
        I64 f_step_idx = g_hc_code_len;
        if (g_hc_tok != TOK_RPAREN) {
            HcCallParseStmt();
        }
        if (g_hc_tok == TOK_RPAREN) HcLexNext(); // eat ')'

        I64 back_to_cond = f_cond_idx - g_hc_code_len;
        HcEmit(0x14000000 | (back_to_cond & 0x03FFFFFF)); // b f_cond_idx

        // 4. Parse body
        HcBackpatchB(f_patch_body, g_hc_code_len);
        I64 f_lvl = HcPushLoopCtx(0);
        HcOpPush(f_lvl);
        HcOpPush(f_step_idx);
        HcOpPush(f_patch_exit);

        HcCallParseStmt();

        I64 pop_f_exit = HcOpPop();
        I64 pop_f_step = HcOpPop();
        I64 pop_f_lvl = HcOpPop();

        HcPatchContinues(pop_f_lvl, pop_f_step);
        I64 back_to_step = pop_f_step - g_hc_code_len;
        HcEmit(0x14000000 | (back_to_step & 0x03FFFFFF)); // b f_step_idx

        HcBackpatchCbz(pop_f_exit, g_hc_code_len);
        HcPatchBreaks(pop_f_lvl, g_hc_code_len);
        HcPopLoopCtx();
        return;
    }

    // Switch: switch (expr) { case N: ... break; default: ... }
    if (g_hc_tok == TOK_SWITCH) {
        HcLexNext();
        if (g_hc_tok == TOK_LPAREN) HcLexNext();
        HcParseExpr();
        if (g_hc_tok == TOK_RPAREN) HcLexNext();

        // Store switch selector value in a dedicated stack slot
        I64 sw_off = g_hc_frame_offset;
        g_hc_frame_offset += 16;
        HcEmitStoreLocal(0, sw_off);

        I64 sw_lvl = HcPushLoopCtx(1);
        if (g_hc_tok == TOK_LBRACE) HcLexNext();

        I64 prev_miss_patch = -1;
        I64 prev_fall_patch = -1;
        I64 in_case = 0;

        while (g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF) {
            if (g_hc_tok == TOK_CASE) {
                HcLexNext();
                if (in_case) {
                    prev_fall_patch = g_hc_code_len;
                    HcEmit(0x14000000); // fallthrough branch over next case check
                }
                if (prev_miss_patch >= 0) {
                    HcBackpatchCbz(prev_miss_patch, g_hc_code_len);
                    prev_miss_patch = -1;
                }
                HcOpPush(sw_off);
                HcOpPush(sw_lvl);
                HcOpPush(prev_fall_patch);
                HcParseExpr(); // case constant in x0
                prev_fall_patch = HcOpPop();
                sw_lvl = HcOpPop();
                sw_off = HcOpPop();

                if (g_hc_tok == TOK_COLON) HcLexNext();

                HcEmit(0xAA0003E1); // mov x1, x0
                HcEmitLoadLocal(0, sw_off); // x0 = switch value
                HcEmit(0xEB01001F); // cmp x0, x1
                HcEmit(0x9A9F17E0); // cset x0, eq
                prev_miss_patch = g_hc_code_len;
                HcEmit(0xB4000000); // cbz x0, next_case

                if (prev_fall_patch >= 0) {
                    HcBackpatchB(prev_fall_patch, g_hc_code_len);
                    prev_fall_patch = -1;
                }
                in_case = 1;
            } else if (g_hc_tok == TOK_DEFAULT) {
                HcLexNext();
                if (g_hc_tok == TOK_COLON) HcLexNext();
                if (prev_fall_patch >= 0) {
                    HcBackpatchB(prev_fall_patch, g_hc_code_len);
                    prev_fall_patch = -1;
                }
                if (prev_miss_patch >= 0) {
                    HcBackpatchCbz(prev_miss_patch, g_hc_code_len);
                    prev_miss_patch = -1;
                }
                in_case = 1;
            } else {
                HcOpPush(sw_off);
                HcOpPush(sw_lvl);
                HcOpPush(prev_miss_patch);
                HcOpPush(prev_fall_patch);
                HcOpPush(in_case);
                HcCallParseStmt();
                in_case = HcOpPop();
                prev_fall_patch = HcOpPop();
                prev_miss_patch = HcOpPop();
                sw_lvl = HcOpPop();
                sw_off = HcOpPop();
            }
        }

        if (g_hc_tok == TOK_RBRACE) HcLexNext();
        if (prev_miss_patch >= 0) {
            HcBackpatchCbz(prev_miss_patch, g_hc_code_len);
        }
        if (prev_fall_patch >= 0) {
            HcBackpatchB(prev_fall_patch, g_hc_code_len);
        }
        HcPatchBreaks(sw_lvl, g_hc_code_len);
        HcPopLoopCtx();
        return;
    }

    // Block: { stmt; ... }
    if (g_hc_tok == TOK_LBRACE) {
        HcLexNext();
        while (g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF) {
            HcCallParseStmt();
        }
        if (g_hc_tok == TOK_RBRACE) HcLexNext();
        return;
    }

    // Pointer dereference assignment: *ptr = expr; or *(U8*)ptr = expr;
    if (g_hc_tok == TOK_STAR) {
        HcLexNext();
        I64 st_sz = -1;
        if (g_hc_tok == TOK_LPAREN) {
            I64 sp_p = g_hc_pos;
            I64 sp_t = g_hc_tok;
            I64 sp_v = g_hc_tok_val;
            U8  sp_s[256];
            HcSafeCopy(sp_s, g_hc_tok_str, 256);
            HcLexNext();
            if (HcIsTypeToken(g_hc_tok)) {
                I64 c_sz = HcTypeTokenScale(g_hc_tok);
                HcLexNext();
                if (g_hc_tok == TOK_STAR) {
                    HcLexNext();
                    if (g_hc_tok == TOK_RPAREN) {
                        HcLexNext();
                        st_sz = c_sz;
                    }
                }
            }
            if (st_sz < 0) {
                g_hc_pos = sp_p;
                g_hc_tok = sp_t;
                g_hc_tok_val = sp_v;
                HcSafeCopy(g_hc_tok_str, sp_s, 256);
            }
        }
        if (st_sz < 0 && g_hc_tok == TOK_IDENT) {
            I64 p_loc = HcFindLocalIdx(g_hc_tok_str);
            if (p_loc >= 0 && g_hc_local_is_ptr[p_loc] == 1) {
                st_sz = g_hc_local_scales[p_loc];
            }
        }
        if (st_sz < 0) st_sz = 8;
        HcParseUnary(); // target address in x0
        HcFinishMemoryAssign(st_sz);
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
        return;
    }

    // Identifier statements: assignments, compound ops, increments, or calls
    if (g_hc_tok == TOK_IDENT) {
        I64 save_p = g_hc_pos;
        I64 save_t = g_hc_tok;
        I64 save_v = g_hc_tok_val;
        I64 save_code = g_hc_code_len;
        U8  save_s[256];
        HcSafeCopy(save_s, g_hc_tok_str, 256);

        U8 iname[64];
        HcSafeCopy(iname, g_hc_tok_str, 64);
        HcLexNext();

        if (g_hc_tok != TOK_LPAREN) {
            I64 lv_sz = 8;
            I64 lv_ao = 0;
            HcResolveLValue(iname, &lv_sz, &lv_ao);
            if (HcIsAssignOp(g_hc_tok)) {
                HcFinishMemoryAssign(lv_sz);
                if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
                return;
            }
        }

        // Restore state and parse as general expression statement
        g_hc_pos = save_p;
        g_hc_tok = save_t;
        g_hc_tok_val = save_v;
        g_hc_code_len = save_code;
        HcSafeCopy(g_hc_tok_str, save_s, 256);

        HcParseExpr();
        if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
        return;
    }

    // Null statement: ;
    if (g_hc_tok == TOK_SEMICOLON) {
        HcLexNext();
        return;
    }

    // Expression statement fallback
    HcParseExpr();
    if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
}

U0 HcParseFunction(U8 *func_name) {
    U64 fn_entry = g_hc_code + g_hc_code_len * 4;
    HcAddFunc(func_name, fn_entry);
    if (strcmp(func_name, "Main") == 0) {
        g_hc_unit_main = fn_entry;
    }

    g_hc_local_count = 0;
    g_hc_frame_offset = 16;
    g_hc_epi_count = 0;

    HcEmitPrologue();

    // Parse parameters: (Type [*] name, ...)
    I64 param_count = 0;
    if (g_hc_tok != TOK_RPAREN) {
        while (1) {
            I64 p_scale = 8;
            I64 p_st_idx = -1;
            I64 p_is_float = 0;
            if (HcIsTypeToken(g_hc_tok)) {
                p_is_float = (g_hc_tok == TOK_TYPE_F64);
                p_scale = HcTypeTokenScale(g_hc_tok);
                HcLexNext();
            } else if (g_hc_tok == TOK_IDENT && HcFindStruct(g_hc_tok_str) >= 0) {
                p_st_idx = HcFindStruct(g_hc_tok_str);
                p_scale = g_hc_struct_sizes[p_st_idx];
                HcLexNext();
            }
            I64 p_is_ptr = 0;
            while (g_hc_tok == TOK_STAR) {
                p_is_ptr = 1;
                HcLexNext();
            }
            if (g_hc_tok == TOK_IDENT) {
                U8 pname[64];
                HcSafeCopy(pname, g_hc_tok_str, 64);
                HcLexNext();

                I64 v_scale = p_is_ptr ? p_scale : 8;
                g_hc_decl_float = (p_is_float && !p_is_ptr) ? 1 : 0;
                I64 fn_arg_off = HcAddLocalTyped(pname, v_scale, p_is_ptr, p_st_idx, 1);
                g_hc_decl_float = 0;
                if (p_is_float && !p_is_ptr) {
                    HcEmit(0xFD0003A0 | ((fn_arg_off >> 3) << 10) | param_count); // str d{pc}, [x29,#off]
                } else {
                    HcEmitStoreLocal(param_count, fn_arg_off);
                }
                param_count++;
            }
            if (g_hc_tok == TOK_COMMA) HcLexNext();
            else break;
        }
    }
    if (g_hc_tok == TOK_RPAREN) HcLexNext(); // eat ')'

    HcParseStatement();
    HcEmitEpilogue();
    HcFinalizeFrame();
}

U0 HcParseProgram() {
    while (g_hc_tok != TOK_EOF) {
        if (g_hc_tok == TOK_CLASS || g_hc_tok == TOK_STRUCT) {
            HcParseStructDef();
            continue;
        }
        if (HcIsTypeToken(g_hc_tok) || (g_hc_tok == TOK_IDENT && HcFindStruct(g_hc_tok_str) >= 0)) {
            I64 save_p = g_hc_pos;
            I64 save_t = g_hc_tok;
            I64 save_v = g_hc_tok_val;
            U8  save_s[256];
            HcSafeCopy(save_s, g_hc_tok_str, 256);

            HcLexNext(); // eat Type
            while (g_hc_tok == TOK_STAR) HcLexNext();
            if (g_hc_tok == TOK_IDENT) {
                U8 fname[64];
                HcSafeCopy(fname, g_hc_tok_str, 64);
                HcLexNext(); // eat ident
                if (g_hc_tok == TOK_LPAREN) {
                    HcLexNext(); // eat '('
                    g_hc_fn_ret_float = (save_t == TOK_TYPE_F64);
                    HcParseFunction(fname);
                    g_hc_fn_ret_float = 0;
                    continue;
                }
                // Top-level global variable declaration: Type g_var [= val];
                U64 g_slot = symbols_lookup(fname);
                if (!g_slot) {
                    g_slot = kmalloc(16);
                    *(I64*)g_slot = 0;
                    symbols_register(fname, g_slot, 2);
                }
                if (g_hc_tok == TOK_EQUAL) {
                    HcLexNext();
                    I64 g_neg = 0;
                    if (g_hc_tok == TOK_MINUS) {
                        g_neg = 1;
                        HcLexNext();
                    }
                    if (g_hc_tok == TOK_NUMBER) {
                        I64 gv = g_hc_tok_val;
                        if (g_neg) gv = -gv;
                        *(I64*)g_slot = gv;
                        HcLexNext();
                    }
                }
                if (g_hc_tok == TOK_SEMICOLON) HcLexNext();
                continue;
            }

            // Restore state and parse as top-level statement block
            g_hc_pos = save_p;
            g_hc_tok = save_t;
            g_hc_tok_val = save_v;
            HcSafeCopy(g_hc_tok_str, save_s, 256);
        }

        // Top-level REPL statements outside a function
        U64 repl_entry = g_hc_code + g_hc_code_len * 4;
        g_hc_unit_main = repl_entry;
        g_hc_local_count = 0;
        g_hc_frame_offset = 16;
        g_hc_epi_count = 0;
        HcEmitPrologue();
        while (g_hc_tok != TOK_EOF) {
            HcParseStatement();
        }
        HcEmitEpilogue();
        HcFinalizeFrame();
    }
}

// ------------------------------------------------------------------------------
// Compiler Compile & Run Driver (Persistent Monotonic Code Pool)
// ------------------------------------------------------------------------------
I64 CompilerCompileAndRun(U8 *src) {
    g_fn_parse_expr = &HcParseExpr;
    g_fn_parse_stmt = &HcParseStatement;
    HcInit();
    HcReset();

    I64 start_idx = g_hc_pool_offset;
    U64 start_addr = g_hc_code + start_idx * 4;

    g_hc_src = src;
    g_hc_pos = 0;
    g_hc_len = strlen(src);
    HcLexNext(); // Prime lexer

    HcParseProgram();

    if (g_hc_error) {
        doldoc_printf("$FG,RED$[COMPILER.HC] internal error during compilation (op-stack/cap/overflow)$FG$\n");
        g_hc_pool_offset = start_idx;
        return -1;
    }

    I64 emitted_insns = g_hc_code_len - start_idx;
    g_hc_pool_offset = g_hc_code_len;

    if (emitted_insns > 0) {
        HcFlushCache(start_addr, emitted_insns * 4);
    }

    if (g_hc_unit_main) {
        g_hc_exec_fn = g_hc_unit_main;
        return g_hc_exec_fn();
    }
    return 0;
}

// ------------------------------------------------------------------------------
// Comprehensive Stage-2 Self-Hosting Self-Test Suite
// ------------------------------------------------------------------------------
U0 CompilerSelfTest() {
    doldoc_clear();
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$  [STAGE-2 COMPILER.HC] Pure HolyC Self-Hosting JIT Scorecard $FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    I64 passed = 0;
    I64 total = 0;

    // Test 1: Arithmetic & Operator Precedence
    total++;
    U8 *test1_src = "I64 Main() { return (10 + 20) * 3 - 50 / 2; }";
    I64 res1 = CompilerCompileAndRun(test1_src);
    if (res1 == 65) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 1: Arithmetic Precedence: (10+20)*3 - 50/2 = %lld\n", res1);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 1: Expected 65, got %lld\n", res1);
    }

    // Test 2: #define Preprocessor Constants & Compound Operations
    total++;
    U8 test2_buf[256];
    strcpy(test2_buf, "#define BASE_VAL 40\n#define STEP_VAL 2\n");
    HcStrCat(test2_buf, "I64 Main() { I64 a = BASE_VAL; a += STEP_VAL; return a; }");
    I64 res2 = CompilerCompileAndRun(test2_buf);
    if (res2 == 42) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 2: #define Constants & Compound Ops: 40 + 2 = %lld\n", res2);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 2: Expected 42, got %lld\n", res2);
    }

    // Test 3: Short-Circuit Logical OR (|| CBNZ) & Logical AND (&& CBZ)
    total++;
    U8 test3_buf[256];
    strcpy(test3_buf, "I64 Main() { I64 a = (1 || 0); I64 b = (0 || 5); I64 c = (0 || 0); ");
    HcStrCat(test3_buf, "I64 d = (1 && 1); I64 e = (1 && 0); return a*100 + b*10 + c + d*1000 + e; }");
    I64 res3 = CompilerCompileAndRun(test3_buf);
    if (res3 == 1110) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 3: Logical || (CBNZ) & && (CBZ) Short-Circuit = %lld\n", res3);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 3: Expected 1110, got %lld\n", res3);
    }

    // Test 4: For Loops, Break & Continue
    total++;
    U8 test4_buf[256];
    strcpy(test4_buf, "I64 Main() { I64 sum = 0; I64 i; ");
    HcStrCat(test4_buf, "for (i = 1; i <= 10; i++) { if (i == 5) continue; if (i == 9) break; sum += i; } return sum; }");
    I64 res4 = CompilerCompileAndRun(test4_buf);
    if (res4 == 31) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 4: For Loop + Continue + Break = %lld\n", res4);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 4: Expected 31, got %lld\n", res4);
    }

    // Test 5: Switch / Case / Default Control Flow
    total++;
    U8 test5_buf[256];
    strcpy(test5_buf, "I64 MapVal(I64 x) { switch (x) { case 1: return 10; case 2: return 20; default: return 70; } } ");
    HcStrCat(test5_buf, "I64 Main() { return MapVal(1) + MapVal(2) + MapVal(99); }");
    I64 res5 = CompilerCompileAndRun(test5_buf);
    if (res5 == 100) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 5: Switch/Case/Default Dispatch = %lld\n", res5);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 5: Expected 100, got %lld\n", res5);
    }

    // Test 6: Class/Struct Member Access (. and ->) & sizeof()
    total++;
    U8 test6_buf[256];
    strcpy(test6_buf, "class CBox { I64 w; I64 h; }; ");
    HcStrCat(test6_buf, "I64 Main() { CBox b; CBox *p = &b; b.w = 12; p->h = 5; return (b.w * p->h) + sizeof(CBox); }");
    I64 res6 = CompilerCompileAndRun(test6_buf);
    if (res6 == 76) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 6: Struct (. and ->) & sizeof(CBox): 12*5 + 16 = %lld\n", res6);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 6: Expected 76, got %lld\n", res6);
    }

    // Test 7: Persistent Multi-Function Pool (Monotonic g_hc_pool_offset)
    total++;
    CompilerCompileAndRun("I64 HcPersistFn1(I64 x) { return x * 3; }");
    CompilerCompileAndRun("I64 HcPersistFn2(I64 y) { return HcPersistFn1(y) + 7; }");
    I64 res7 = CompilerCompileAndRun("I64 Main() { return HcPersistFn1(10) + HcPersistFn2(10); }");
    if (res7 == 67) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 7: Persistent Multi-Function JIT Pool: 30 + 37 = %lld\n", res7);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 7: Expected 67, got %lld\n", res7);
    }

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    if (passed == total) {
        doldoc_printf("$FG,GREEN$  All %lld / %lld tests passed (100%% precision) - Stage-2 Sovereign!$FG$\n", passed, total);
    } else {
        doldoc_printf("$FG,RED$  %lld / %lld tests passed.$FG$\n", passed, total);
    }
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
}

if (g_kernel_booting) {
    HcInit();
} else {
    CompilerSelfTest();
}
