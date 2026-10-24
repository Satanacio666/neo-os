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
// NOTE: there is no HC_MAX_LOCALS macro. The per-function local table is sized 256
// (see g_hc_local_* below) and HcAddLocalTyped hard-errors (g_hc_error = 1) rather
// than silently dropping a local if that ceiling is ever reached.
#define HC_MAX_FUNCS     512
// Max `return` statements per function (epilogue back-patches). A large
// two-letter tag dispatcher legitimately needs well over the old 64.
#define HC_MAX_EPILOGUES 512
// P0.7: source / include-expansion ceilings. A module larger than the load
// buffer used to be silently truncated (see KernelInit.HC HC_MODULE_MAX); these
// match that 1 MB source cap, with a 2 MB expansion buffer for #include splicing.
#define HC_SRC_MAX       1048576
#define HC_EXPAND_MAX    2097152

// P3.5 guardrail 1: non-zero while a compilation is in progress. The scheduler
// (SchedOnTick) defers preemption while this is set, because the compiler uses
// global (non-reentrant) state. The C heap masks IRQs internally.
I64   g_hc_compiling = 0;

// Compiler Source & Lexer State
U8   *g_hc_src;
I64   g_hc_pos;
I64   g_hc_len;

I64   g_hc_tok;
I64   g_hc_tok_val;
I64   g_hc_tok_pos;   // source position where the current token starts
U8    g_hc_tok_str[256];

// P0.7: dedicated lexer string arena. Every string literal used to be kmalloc'd
// (slen+1) individually and never freed, leaking thousands of 32-64 byte blocks
// into the general heap (the C seed heap during boot, KHeap.HC after handover)
// and fragmenting it. String literals must persist (emitted code holds pointers
// to them), so instead we bump-allocate them from chained fixed-size chunks. The
// first chunk is a static BSS array, so lexing has NO allocator dependency during
// the fragile boot window; further chunks come from kmalloc only once a session
// compiles enough literals to fill one. Bounds-checked: an over-long literal
// fails the compile cleanly (g_hc_error) instead of corrupting memory.
#define HC_STR_CHUNK      262144
#define HC_STR_MAX_CHUNKS 64
U8    g_hc_str_arena0[HC_STR_CHUNK];
U8   *g_hc_str_chunks[HC_STR_MAX_CHUNKS];
I64   g_hc_str_nchunks;
I64   g_hc_str_off;
I64   g_hc_str_bytes;   // total bytes handed out (telemetry)

// Persistent Monotonic Executable Code Pool
U32  *g_hc_code;
I64   g_hc_code_len;
I64   g_hc_pool_offset;
U64   g_hc_unit_main;

// P7.0: branch-target bitmap for the peephole optimizer (1 bit per instruction).
// D29 ROOT-FIXED: this dimension is now a constant EXPRESSION (HC_CODE_CAPACITY/8),
// folded by HcParseArrayDim — no more literal workaround.
U8    g_hc_target_bits[HC_CODE_CAPACITY / 8];

// Function Prologue/Epilogue Dynamic Frame Patching
I64   g_hc_pro_sub_idx;
I64   g_hc_epi_patches[HC_MAX_EPILOGUES];
I64   g_hc_epi_count;

// Local Variables Table (per function)
U8    g_hc_local_names[8192];   // 256 * 32
I64   g_hc_local_offsets[256];
I64   g_hc_local_scales[256];    // 1, 2, 4, 8, or struct size
I64   g_hc_local_is_ptr[256];    // 0=scalar, 1=ptr, 2=stack array, 3=stack struct
I64   g_hc_local_is_float[256];  // 1 if this local is an F64
I64   g_hc_local_elem_float[256]; // 1 if this local's ELEMENT/POINTEE is F64 (arrays, F64*)
I64   g_hc_local_st_idx[256];    // struct index or -1
I64   g_hc_local_strides[256 * 4]; // per-dim byte strides for local arrays (0 = none)
I64   g_hc_local_count;
I64   g_hc_decl_float;          // transient: current declaration is F64
I64   g_hc_decl_elem_float;     // transient: current decl's element/pointee is F64
I64   g_hc_frame_offset;

// Persistent Compiled Function Table
U8    g_hc_func_names[HC_MAX_FUNCS * 32];
U64   g_hc_func_addrs[HC_MAX_FUNCS];
I64   g_hc_func_count;
I64   g_hc_func_ret_float[HC_MAX_FUNCS];  // 1 if the function returns F64 (result in D0)
I64   g_hc_fn_ret_float;         // transient: current function return type is F64
I64   g_hc_arg_float[32];        // transient: which call args are F64

// P4.5 ROOT FIX: function return-floatness must PERSIST across compilation units.
// HcReset() clears the per-unit g_hc_func_* table at the start of every unit, so a
// call to an F64-returning function defined in an EARLIER unit (Gears3D.HC calling
// MathCos from Math3D.HC) was treated as returning an INTEGER: HcFuncIsFloat
// returned 0, HcEmitPromoteFloat then emitted `scvtf d0, x0` on the double's raw
// bit pattern, and `r * MathCos(a)` produced garbage — the gears mesh collapsed.
// This table records name -> returns-F64 and is NEVER reset; HcFuncIsFloat consults
// it when the per-unit table has no entry. It is also filled by HcPrescanFuncs so
// intra-unit forward references resolve too.
#define HC_FNF_MAX 2048
U8    g_hc_fnf_names[HC_FNF_MAX * 24];
I64   g_hc_fnf_flags[HC_FNF_MAX];
I64   g_hc_fnf_count;

// Global variable struct-type registry (scoped member lookup for globals).
#define HC_MAX_GLOBALS 512
U8    g_hc_global_names[HC_MAX_GLOBALS * 32];
I64   g_hc_global_st_idx[HC_MAX_GLOBALS];
I64   g_hc_global_is_arr[HC_MAX_GLOBALS];
I64   g_hc_global_is_ptr[HC_MAX_GLOBALS]; // 1 if the global is a pointer (e.g. FBox *p)
I64   g_hc_global_is_float[HC_MAX_GLOBALS];
I64   g_hc_global_elem_scale[HC_MAX_GLOBALS]; // element byte width for indexing
I64   g_hc_global_strides[HC_MAX_GLOBALS * 4]; // per-dim byte strides for arrays (0 = none)
I64   g_hc_global_count;

// Preprocessor #define Table in Compiler.HC
#define HC_MAX_DEFINES 1024
U8    g_hc_def_names[HC_MAX_DEFINES * 64];
I64   g_hc_def_vals[HC_MAX_DEFINES];
I64   g_hc_def_count;

// Deferred top-level initializers. A global declared with a NON-literal initializer
// (e.g. `I64 *p = &x;`, `I64 b = a + 4;`) gets its storage allocated statically but
// its value is computed at runtime inside the top-level wrapper function, exactly as
// the C JIT does. Each entry records the global's storage cell and the source
// position of the initializer expression, re-lexed and emitted in the wrapper.
#define HC_MAX_DEFERRED 64
I64   g_hc_init_slot[HC_MAX_DEFERRED];
I64   g_hc_init_pos[HC_MAX_DEFERRED];
I64   g_hc_init_count;

// Struct / Class Registry (up to 128 structs, 64 members each = 8192 member slots)
// Persists across modules (matching the C JIT) so cross-module struct types
// (e.g. Math3D's CMat4 used by HolyGL) resolve correctly.
U8    g_hc_structs[4096];        // 128 * 32 struct names
I64   g_hc_struct_sizes[128];
I64   g_hc_struct_mcount[128];
U8    g_hc_member_names[262144]; // 8192 * 32 member names
I64   g_hc_member_offsets[8192];
I64   g_hc_member_sizes[8192];   // 1, 2, 4, 8 (element/field load width)
I64   g_hc_member_is_arr[8192];  // 1 if inline array member
I64   g_hc_member_is_ptr[8192];  // 1 if pointer member
I64   g_hc_member_st_idx[8192];  // nested struct index or -1
I64   g_hc_member_is_float[8192];// 1 if this member is an F64 scalar/element
// D7 root fix: the element/pointee byte width used to INDEX a member. For a
// scalar pointer member `U32 *data` this is 4 (NOT the 8-byte pointer field
// width); for an inline array it is the element width; for a nested struct it is
// the struct size. Mirrors struct_member_t.elem_size in boot/seed/jit_arm64.c.
I64   g_hc_member_elem_bytes[8192];
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

// Store one scalar into a compile-time array buffer at element index idx with the
// given element byte width. Kept as a small top-level helper (rather than an inline
// nested-block pointer store) because the C JIT miscompiles typed stores through a
// pointer local declared in a deeply nested block of a large function.
U0 HcStoreElem(U64 base, I64 idx, I64 val, I64 scale) {
    U64 addr = base + (U64)(idx * scale);
    if (scale == 1) *(U8*)addr = val;
    else if (scale == 2) *(U16*)addr = val;
    else if (scale == 4) *(U32*)addr = val;
    else *(I64*)addr = val;
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
    // `auto` is accepted as a declaration type (TempleOS/HolyC storage class);
    // it behaves as a signed 64-bit integer here.
    if (tok == TOK_TYPE_I64 || tok == TOK_TYPE_U0 || tok == TOK_TYPE_F64 ||
        tok == TOK_TYPE_U8  || tok == TOK_TYPE_U16 || tok == TOK_TYPE_U32 ||
        tok == TOK_AUTO) {
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
// P0.7: reset the string arena. Called only on cold init (never per compile):
// strings must persist across compilation units because emitted code stores raw
// pointers to them.
U0 HcStrReset() {
    g_hc_str_nchunks = 0;
    g_hc_str_off = 0;
    g_hc_str_bytes = 0;
    g_hc_str_chunks[0] = g_hc_str_arena0;
    g_hc_str_nchunks = 1;
}

// Bump-allocate n bytes (8-byte aligned) from the lexer string arena. Always
// returns a writable pointer on success; returns 0 only on genuine exhaustion
// (all chunks full, or a chunk allocation failed), in which case g_hc_error is
// set so the caller aborts the unit instead of writing through NULL.
U8* HcStrAlloc(I64 n) {
    if (n <= 0) n = 1;
    n = (n + 7) & ~7;
    if (n > HC_STR_CHUNK) { g_hc_error = 1; return 0; }   // one literal must fit a chunk
    if (g_hc_str_nchunks <= 0) HcStrReset();
    if (g_hc_str_off + n > HC_STR_CHUNK) {
        if (g_hc_str_nchunks >= HC_STR_MAX_CHUNKS) {
            doldoc_printf("[HCLX] STRING ARENA FULL (%lld chunks, %lld bytes); literal too large\n",
                          g_hc_str_nchunks, g_hc_str_bytes);
            g_hc_error = 1;
            return 0;
        }
        U8 *chunk = kmalloc(HC_STR_CHUNK);
        if (!chunk) {
            doldoc_printf("[HCLX] STRING ARENA chunk alloc failed (chunks=%lld bytes=%lld)\n",
                          g_hc_str_nchunks, g_hc_str_bytes);
            g_hc_error = 1;
            return 0;
        }
        g_hc_str_chunks[g_hc_str_nchunks] = chunk;
        g_hc_str_nchunks = g_hc_str_nchunks + 1;
        g_hc_str_off = 0;
    }
    U8 *p = g_hc_str_chunks[g_hc_str_nchunks - 1] + g_hc_str_off;
    g_hc_str_off = g_hc_str_off + n;
    g_hc_str_bytes = g_hc_str_bytes + n;
    return p;
}

I64 HcStrBytes() { return g_hc_str_bytes; }
I64 HcStrChunks() { return g_hc_str_nchunks; }

U0 HcInit() {
    if (!g_hc_code) {
        g_hc_code = kmalloc(HC_CODE_CAPACITY * 4);
        g_hc_pool_offset = 0;
        g_hc_func_count = 0;
        g_hc_struct_count = 0;
        g_hc_def_count = 0;
        g_hc_fnf_count = 0;   // P4.5: persistent cross-unit function-float table
        HcStrReset();
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
    // NOTE: the struct table is intentionally NOT reset — struct definitions must
    // persist across modules (matching the C JIT) so cross-module struct types
    // used by later modules resolve correctly.
    g_hc_func_count = 0;
    // NOTE: the #define table (g_hc_def_count) is intentionally NOT reset: macros must
    // persist across compilation units, exactly as the C JIT's #defines do (it
    // registers them as SYM_VAR). This is what lets a macro defined in one REPL
    // command be used by the next.
    g_hc_init_count = 0;
}

// Cache maintenance for freshly JIT-emitted code. Deliberately self-contained so
// Compiler.HC has NO dependency on any other .HC module: the C JIT bootstraps
// ONLY Compiler.HC (P2.7), which then compiles everything else, including
// HalPlatform.HC (whose HalFlushCache is the runtime implementation).
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
    if (g_hc_def_count < HC_MAX_DEFINES) {
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
    if (g_hc_struct_count >= 128) { g_hc_error = 1; return 0; }
    I64 ns_idx = g_hc_struct_count;
    HcSafeCopy(&g_hc_structs[ns_idx * 32], name, 32);
    g_hc_struct_sizes[ns_idx] = 0;
    g_hc_struct_mcount[ns_idx] = 0;
    g_hc_struct_count++;
    return ns_idx;
}

// D7 root fix: element/pointee width of the most recently matched member, set by
// HcFindMember. Exposed as a global because the C JIT (which compiles this file)
// caps function calls at 8 arguments — HcFindMember already takes 8 out-params.
I64 g_hc_found_member_elem = 8;
I64 HcFindMember(I64 st_idx, U8 *mname, I64 *out_off, I64 *out_sz, I64 *out_is_arr, I64 *out_is_ptr, I64 *out_sub_st, I64 *out_is_float) {
    g_hc_found_member_elem = 8;
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
            I64 slot = s_i * 64 + m_i;
            if (strcmp(&g_hc_member_names[slot * 32], mname) == 0) {
                *out_off = g_hc_member_offsets[slot];
                *out_sz = g_hc_member_sizes[slot];
                *out_is_arr = g_hc_member_is_arr[slot];
                *out_is_ptr = g_hc_member_is_ptr[slot];
                *out_sub_st = g_hc_member_st_idx[slot];
                *out_is_float = g_hc_member_is_float[slot];
                g_hc_found_member_elem = g_hc_member_elem_bytes[slot];
                if (g_hc_found_member_elem <= 0) g_hc_found_member_elem = *out_sz;
                return 1;
            }
        }
    }
    // Fallback search across all structs if st_idx was unknown
    if (st_idx >= 0) {
        for (s_i = 0; s_i < g_hc_struct_count; s_i++) {
            I64 mcnt2 = g_hc_struct_mcount[s_i];
            for (m_i = 0; m_i < mcnt2; m_i++) {
                I64 slot2 = s_i * 64 + m_i;
                if (strcmp(&g_hc_member_names[slot2 * 32], mname) == 0) {
                    *out_off = g_hc_member_offsets[slot2];
                    *out_sz = g_hc_member_sizes[slot2];
                    *out_is_arr = g_hc_member_is_arr[slot2];
                    *out_is_ptr = g_hc_member_is_ptr[slot2];
                    *out_sub_st = g_hc_member_st_idx[slot2];
                    *out_is_float = g_hc_member_is_float[slot2];
                    g_hc_found_member_elem = g_hc_member_elem_bytes[slot2];
                    if (g_hc_found_member_elem <= 0) g_hc_found_member_elem = *out_sz;
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
        // D14 ROOT FIX: redeclaring an existing local name must UPDATE its type
        // metadata. The compiler is single-pass and reads these flags at each point
        // of use, so code already emitted for earlier uses keeps the old type while
        // every later use sees the new one. Previously the FIRST declaration's type
        // stuck forever: MeshParseOBJ declares `F64 b` in the `vn`/`v` branches and
        // later `I64 b` in the fan/fill loops, so `b` stayed F64. Using a float-typed
        // local as an array index emits `ldr d0, [x0]` (which leaves x0 = &b) and the
        // index code then does `mul x0, x0, #elem` -> &b * elem, a wild ~18 GB read
        // (Data Abort, ESR 0x96000005). Sharing the slot is correct: the branches are
        // mutually exclusive at run time, so one 8-byte cell serves both.
        g_hc_local_scales[ex]     = scale;
        g_hc_local_is_ptr[ex]     = is_ptr;
        g_hc_local_is_float[ex]   = g_hc_decl_float;
        g_hc_local_elem_float[ex] = g_hc_decl_elem_float;
        g_hc_local_st_idx[ex]     = st_idx;
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
    if (g_hc_local_count < 256) {
        HcSafeCopy(&g_hc_local_names[g_hc_local_count * 32], name, 32);
        g_hc_local_offsets[g_hc_local_count] = offset;
        g_hc_local_scales[g_hc_local_count] = scale;
        g_hc_local_is_ptr[g_hc_local_count] = is_ptr;
        g_hc_local_is_float[g_hc_local_count] = g_hc_decl_float;
        g_hc_local_elem_float[g_hc_local_count] = g_hc_decl_elem_float;
        g_hc_local_st_idx[g_hc_local_count] = st_idx;
        g_hc_local_strides[g_hc_local_count * 4 + 0] = 0;
        g_hc_local_strides[g_hc_local_count * 4 + 1] = 0;
        g_hc_local_strides[g_hc_local_count * 4 + 2] = 0;
        g_hc_local_strides[g_hc_local_count * 4 + 3] = 0;
        g_hc_local_count++;
    } else {
        g_hc_error = 1;
    }
    return offset;
}

I64 HcAddLocal(U8 *name) {
    return HcAddLocalTyped(name, 8, 0, -1, 1);
}

// Per-dimension byte strides for a local array (parallel to the local table).
U0 HcSetLocalStrides(U8 *name, I64 s0, I64 s1, I64 s2, I64 s3) {
    I64 idx = HcFindLocalIdx(name);
    if (idx < 0) return;
    g_hc_local_strides[idx * 4 + 0] = s0;
    g_hc_local_strides[idx * 4 + 1] = s1;
    g_hc_local_strides[idx * 4 + 2] = s2;
    g_hc_local_strides[idx * 4 + 3] = s3;
}

I64 HcLocalStride(I64 loc, I64 k) {
    if (loc < 0 || k < 0 || k > 3) return 0;
    return g_hc_local_strides[loc * 4 + k];
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

// Publish a compiled function into the global symbol table, but NEVER clobber a
// symbol that already has a real address. When Compiler.HC compiles a module that
// redefines a function the running compiler itself provides (i.e. compiling
// itself), overwriting that symbol would redirect the compiler's own late-bound
// calls into not-yet-emitted code. Forward references (still pointing at the
// unresolved trap) are resolved normally.
// P0.6: cumulative JIT symbol map (name -> addr). Stored, not printed, so the
// boot log is not flooded; dumped on demand by the `jitmap` shell command so
// scripts/crash-decode.py can symbolicate a faulting ELR_EL1 to function+offset.
#define HC_MAP_MAX 1024
U8  g_hc_map_names[HC_MAP_MAX * 24];
U64 g_hc_map_addrs[HC_MAP_MAX];
I64 g_hc_map_count = 0;

U0 HcMapAdd(U8 *name, U64 addr) {
    if (g_hc_map_count >= HC_MAP_MAX) return;
    HcSafeCopy(&g_hc_map_names[g_hc_map_count * 24], name, 24);
    g_hc_map_addrs[g_hc_map_count] = addr;
    g_hc_map_count = g_hc_map_count + 1;
}

U0 HcMapDump() {
    I64 i = 0;
    while (i < g_hc_map_count) {
        doldoc_printf("[HCF] %s 0x%016llX\n", &g_hc_map_names[i * 24], g_hc_map_addrs[i]);
        i = i + 1;
    }
    doldoc_print("<<<NEO-DONE:jitmap>>>\n");
}

U0 HcPublishFunc(U8 *name, U64 addr) {
    if (!symbols_is_defined(name) || !symbols_is_func(name)) {
        symbols_register(name, addr, 1);
    }
}

// P4.5: persist a function's return-floatness (see g_hc_fnf_* above).
U0 HcFnFloatSet(U8 *name, I64 isf) {
    I64 i = 0;
    while (i < g_hc_fnf_count) {
        if (strcmp(&g_hc_fnf_names[i * 24], name) == 0) { g_hc_fnf_flags[i] = isf; return; }
        i++;
    }
    if (g_hc_fnf_count < HC_FNF_MAX) {
        HcSafeCopy(&g_hc_fnf_names[g_hc_fnf_count * 24], name, 24);
        g_hc_fnf_flags[g_hc_fnf_count] = isf;
        g_hc_fnf_count++;
    } else {
        g_hc_error = 1;
    }
}

I64 HcFnFloatGet(U8 *name) {
    I64 i = 0;
    while (i < g_hc_fnf_count) {
        if (strcmp(&g_hc_fnf_names[i * 24], name) == 0) return g_hc_fnf_flags[i];
        i++;
    }
    return -1; // unknown
}

U0 HcAddFunc(U8 *name, U64 addr) {
    HcFnFloatSet(name, g_hc_fn_ret_float); // P4.5: persist across units
    I64 af_i = 0;
    for (af_i = 0; af_i < g_hc_func_count; af_i++) {
        if (strcmp(&g_hc_func_names[af_i * 32], name) == 0) {
            g_hc_func_addrs[af_i] = addr;
            HcPublishFunc(name, addr);
            return;
        }
    }
    if (g_hc_func_count < HC_MAX_FUNCS) {
        HcSafeCopy(&g_hc_func_names[g_hc_func_count * 32], name, 32);
        g_hc_func_addrs[g_hc_func_count] = addr;
        g_hc_func_ret_float[g_hc_func_count] = g_hc_fn_ret_float;
        g_hc_func_count++;
        // P0.6: record the symbol map (dumped on demand via the `jitmap`
        // command) so scripts/crash-decode.py can turn a faulting ELR_EL1 into
        // "function + offset". Stored, not printed, to avoid flooding DolDoc.
        HcMapAdd(name, addr);
    } else {
        g_hc_error = 1;
    }
    HcPublishFunc(name, addr);
}

I64 HcFuncIsFloat(U8 *name) {
    for (I64 i = 0; i < g_hc_func_count; i++) {
        if (strcmp(&g_hc_func_names[i * 32], name) == 0) return g_hc_func_ret_float[i];
    }
    // P4.5: the per-unit table only holds THIS unit's functions. Fall back to the
    // persistent cross-unit table so a call to an F64 function defined earlier
    // (e.g. MathCos) is not mis-promoted from integer.
    I64 pf = HcFnFloatGet(name);
    if (pf >= 0) return pf;
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

// ------------------------------------------------------------------------------
// P7.0: Peephole optimizer (ported from boot/seed/jit_arm64.c:800).
//
// NOP-BASED: it NEVER deletes or inserts instructions, so the index-based branch
// backpatching in HcBackpatchCbz/Cbnz/B and the break/continue stacks (which
// record g_hc_code_len at emit time) stays exactly valid. Deleting emitted
// instructions after the fact would shift every jump crossing the deletion.
//
//   Pass 1  STR X0,[SP,#-16]! ... LDR X0,[SP],#16  -> NOP / NOP (X0 round-trip)
//           STR X0,[SP,#-16]! ... LDR X1,[SP],#16  -> MOV X1,X0 / NOP (retarget)
//   Pass 2  MOV Xd, Xd                              -> NOP (dead move)
//   Pass 3  ADD Xd, Xd, #0                          -> NOP (redundant zero add)
// ------------------------------------------------------------------------------
I64 g_hc_opt_roundtrips = 0;
I64 g_hc_opt_deadmoves = 0;
I64 g_hc_opt_deadadds = 0;
I64 g_hc_opt_runs = 0;

// True if `insn` reads or writes general register `reg`, or touches SP. Deliberate
// over-approximation: a false positive only rejects a collapse (safe).
I64 HcInsnTouches(U32 insn, I64 reg) {
    if (insn == 0xD503201F) return 0; // NOP is harmless
    // MOVZ / MOVK: immediate in [20:5], only Rd in [4:0] is a register.
    if ((insn & 0x7F800000) == 0x52800000 || (insn & 0x7F800000) == 0x72800000) {
        U32 rd = insn & 0x1F;
        if (rd == reg) return 1;
        if (rd == 31) return 1; // SP
        return 0;
    }
    // MOV reg (ORR Xd, XZR, Xm).
    if ((insn & 0xFFE0FFE0) == 0xAA0003E0) {
        U32 rd = insn & 0x1F;
        U32 rm = (insn >> 16) & 0x1F;
        if (rd == reg || rm == reg) return 1;
        if (rd == 31 || rm == 31) return 1;
        return 0;
    }
    // Single-register load/store.
    if ((insn & 0x0A000000) == 0x08000000 || (insn & 0x38000000) == 0x38000000) {
        U32 rt = insn & 0x1F;
        U32 rn = (insn >> 5) & 0x1F;
        if (rt == reg || rn == reg) return 1;
        if (rn == 31) return 1; // SP base
        return 0;
    }
    // Standard 3-register data processing.
    U32 rd2 = insn & 0x1F;
    U32 rn2 = (insn >> 5) & 0x1F;
    U32 rm2 = (insn >> 16) & 0x1F;
    if (rd2 == reg || rn2 == reg || rm2 == reg) return 1;
    if (rn2 == 31) return 1; // SP
    return 0;
}

// May the push at `p` and the pop at `q` be collapsed? The intervening window
// must contain no branch/call/SVC/RET, must not touch `reg` or SP, and no branch
// may target (p, q].
I64 HcCanCollapse(I64 p, I64 q, I64 reg) {
    if (q <= p || (q - p) > 40) return 0;
    I64 k = p + 1;
    while (k < q) {
        U32 insn = g_hc_code[k];
        if (insn == 0xD503201F) { k = k + 1; continue; }
        if ((insn & 0xFFFFFC1F) == 0xD63F0000) return 0; // BLR
        if ((insn & 0xFC000000) == 0x94000000) return 0; // BL
        if ((insn & 0xFFE0001F) == 0xD4000001) return 0; // SVC
        if (insn == 0xD65F03C0) return 0;                // RET
        if ((insn & 0xFC000000) == 0x14000000) return 0; // B
        if ((insn & 0xFF000010) == 0x54000000) return 0; // B.cond
        if ((insn & 0x7E000000) == 0x34000000) return 0; // CBZ / CBNZ
        if (HcInsnTouches(insn, reg)) return 0;
        k = k + 1;
    }
    k = p + 1;
    while (k <= q) {
        if (g_hc_target_bits[k >> 3] & (1 << (k & 7))) return 0;
        k = k + 1;
    }
    return 1;
}

U0 HcOptimizePeephole(I64 start, I64 end) {
    if (g_hc_error) return;
    if (end - start < 2) return;
    g_hc_opt_runs = g_hc_opt_runs + 1;

    I64 z = 0;
    while (z < 131072) { g_hc_target_bits[z] = 0; z = z + 1; }

    // Build the branch-target bitmap for [start, end).
    I64 b = start;
    while (b < end) {
        U32 insn = g_hc_code[b];
        I64 tgt = -1;
        if ((insn & 0xFC000000) == 0x14000000) {          // B
            I64 imm = insn & 0x03FFFFFF;
            if (imm & 0x02000000) imm = imm - 0x04000000;
            tgt = b + imm;
        } else if ((insn & 0xFF000010) == 0x54000000) {   // B.cond
            I64 imm = (insn >> 5) & 0x7FFFF;
            if (imm & 0x40000) imm = imm - 0x80000;
            tgt = b + imm;
        } else if ((insn & 0x7E000000) == 0x34000000) {   // CBZ / CBNZ
            I64 imm = (insn >> 5) & 0x7FFFF;
            if (imm & 0x40000) imm = imm - 0x80000;
            tgt = b + imm;
        }
        if (tgt >= 0 && tgt < 131072 * 8) {
            g_hc_target_bits[tgt >> 3] = g_hc_target_bits[tgt >> 3] | (1 << (tgt & 7));
        }
        b = b + 1;
    }

    I64 pass = 0;
    while (pass < 4) {
        I64 changed = 0;

        // Pass 1: stack round-trip collapse.
        I64 p = start;
        while (p < end) {
            if (g_hc_code[p] == 0xF81F0FE0) { // STR X0, [SP, #-16]!
                I64 q = p + 1;
                while (q < end && (q - p) <= 40) {
                    U32 qi = g_hc_code[q];
                    if (qi == 0xF84107E0) { // LDR X0, [SP], #16
                        if (HcCanCollapse(p, q, 0)) {
                            g_hc_code[p] = 0xD503201F;
                            g_hc_code[q] = 0xD503201F;
                            g_hc_opt_roundtrips = g_hc_opt_roundtrips + 1;
                            changed = 1; p = q; break;
                        }
                    } else if (qi == 0xF84107E1) { // LDR X1, [SP], #16
                        if (HcCanCollapse(p, q, 1)) {
                            g_hc_code[p] = 0xAA0003E1; // MOV X1, X0 (X0 still holds the pushed value here)
                            g_hc_code[q] = 0xD503201F;
                            g_hc_opt_roundtrips = g_hc_opt_roundtrips + 1;
                            changed = 1; p = q; break;
                        }
                    }
                    q = q + 1;
                }
            }
            p = p + 1;
        }

        // Pass 2: dead moves (MOV Xd, Xd -> NOP).
        I64 k = start;
        while (k < end) {
            U32 insn = g_hc_code[k];
            if ((insn & 0xFFE0FFFF) == 0xAA0003E0) {
                U32 rm = (insn >> 16) & 0x1F;
                U32 rd = insn & 0x1F;
                if (rm == rd) {
                    g_hc_code[k] = 0xD503201F;
                    g_hc_opt_deadmoves = g_hc_opt_deadmoves + 1;
                    changed = 1;
                }
            }
            k = k + 1;
        }

        // Pass 3: redundant zero adds (ADD Xd, Xd, #0 -> NOP).
        k = start;
        while (k < end) {
            U32 insn = g_hc_code[k];
            if ((insn & 0xFFC00000) == 0x91000000) {
                I64 imm12 = (insn >> 10) & 0xFFF;
                U32 rn = (insn >> 5) & 0x1F;
                U32 rd = insn & 0x1F;
                if (imm12 == 0 && rn == rd) {
                    g_hc_code[k] = 0xD503201F;
                    g_hc_opt_deadadds = g_hc_opt_deadadds + 1;
                    changed = 1;
                }
            }
            k = k + 1;
        }

        if (!changed) break;
        pass = pass + 1;
    }
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
    if (g_hc_epi_count < HC_MAX_EPILOGUES) {
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
    if (g_hc_pro_sub_idx >= 0 && g_hc_pro_sub_idx < HC_CODE_CAPACITY)
        g_hc_code[g_hc_pro_sub_idx] = 0xD10003FF | ((frame_sz & 0xFFF) << 10);
    else g_hc_error = 1;
    I64 ep_i = 0;
    for (ep_i = 0; ep_i < g_hc_epi_count; ep_i++) {
        I64 p_idx = g_hc_epi_patches[ep_i];
        if (p_idx >= 0 && p_idx < HC_CODE_CAPACITY)
            g_hc_code[p_idx] = 0x910003FF | ((frame_sz & 0xFFF) << 10);
        else g_hc_error = 1;
    }
}

U0 HcBackpatchCbz(I64 patch_idx, I64 target_idx) {
    // P0.7: bounds-check. An out-of-range patch index here used to write past the
    // code pool into adjacent heap memory, corrupting a block header (a latent
    // heap-corruption vector). Fail the unit cleanly instead.
    if (patch_idx < 0 || patch_idx >= HC_CODE_CAPACITY) { g_hc_error = 1; return; }
    I64 diff = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0xB4000000 | ((diff & 0x7FFFF) << 5);
}

U0 HcBackpatchCbnz(I64 patch_idx, I64 target_idx) {
    if (patch_idx < 0 || patch_idx >= HC_CODE_CAPACITY) { g_hc_error = 1; return; }
    I64 rel = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0xB5000000 | ((rel & 0x7FFFF) << 5) | 0;
}

U0 HcBackpatchB(I64 patch_idx, I64 target_idx) {
    if (patch_idx < 0 || patch_idx >= HC_CODE_CAPACITY) { g_hc_error = 1; return; }
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
                // Constant-expression continuation: `#define X 6 * 7`, `#define Y N + 1`.
                // The C JIT evaluates these, so macros must too. (`/` is deliberately
                // excluded so a trailing `// comment` is never parsed as division.)
                while (g_hc_pos < g_hc_len) {
                    while (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == ' ' || g_hc_src[g_hc_pos] == '\t')) g_hc_pos++;
                    U8 dop = g_hc_src[g_hc_pos];
                    if (dop != '*' && dop != '+' && dop != '-') break;
                    g_hc_pos++;
                    while (g_hc_pos < g_hc_len && (g_hc_src[g_hc_pos] == ' ' || g_hc_src[g_hc_pos] == '\t')) g_hc_pos++;
                    I64 rhs = 0;
                    if (g_hc_pos < g_hc_len && HcIsDigit(g_hc_src[g_hc_pos])) {
                        while (g_hc_pos < g_hc_len && HcIsDigit(g_hc_src[g_hc_pos])) { rhs = rhs * 10 + (g_hc_src[g_hc_pos] - '0'); g_hc_pos++; }
                    } else if (g_hc_pos < g_hc_len && HcIsAlpha(g_hc_src[g_hc_pos])) {
                        U8 rn2[64];
                        I64 r2 = 0;
                        while (g_hc_pos < g_hc_len && HcIsAlNum(g_hc_src[g_hc_pos]) && r2 < 63) rn2[r2++] = g_hc_src[g_hc_pos++];
                        rn2[r2] = 0;
                        HcFindDefine(rn2, &rhs);
                    }
                    if (dop == '*') d_val = d_val * rhs;
                    else if (dop == '+') d_val = d_val + rhs;
                    else if (dop == '-') d_val = d_val - rhs;
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
    g_hc_tok_pos = g_hc_pos;   // remember where this token begins (for re-lexing)

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
        // P0.7: strings come from the dedicated arena, not the general heap. This
        // removes ~2000 small leaked kmalloc blocks per full boot (and their
        // fragmentation) and makes lexing independent of the general allocator.
        U8 *buf = HcStrAlloc(slen + 1);
        if (!buf) {
            // NOTE: the C JIT (which compiles Compiler.HC itself) supports at most
            // 8 arguments per call, so keep this diagnostic within that budget.
            U64 sd_tot = 0; U64 sd_used = 0; U64 sd_free = 0; U64 sd_cnt = 0;
            kheap_get_stats(&sd_tot, &sd_used, &sd_free, &sd_cnt);
            doldoc_printf("[HCLX] STRING ARENA FAILED slen=%lld pos=%lld len=%lld arena=%lld/%lld seed_free=%lld\n",
                          slen, g_hc_pos, g_hc_len, HcStrBytes(), HcStrChunks(), sd_free);
            g_hc_error = 1;
            g_hc_tok = TOK_EOF;
            return;
        }
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
U0 HcRegisterGlobalStruct(U8 *name, I64 st_idx) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) { g_hc_global_st_idx[i] = st_idx; return; }
    }
    if (g_hc_global_count < HC_MAX_GLOBALS) {
        HcSafeCopy(&g_hc_global_names[g_hc_global_count * 32], name, 32);
        g_hc_global_st_idx[g_hc_global_count] = st_idx;
        g_hc_global_count++;
    }
}

U0 HcRegisterGlobalArray(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) { g_hc_global_is_arr[i] = 1; return; }
    }
    if (g_hc_global_count < HC_MAX_GLOBALS) {
        HcSafeCopy(&g_hc_global_names[g_hc_global_count * 32], name, 32);
        g_hc_global_st_idx[g_hc_global_count] = -1;
        g_hc_global_is_arr[g_hc_global_count] = 1;
        g_hc_global_count++;
    }
}

I64 HcGlobalIsArray(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) return g_hc_global_is_arr[i];
    }
    return 0;
}

// Mark a global as a pointer (Type *name). Needed so `name->member` dereferences
// the pointer cell before applying the member offset (a struct *value* global
// instead treats the symbol itself as the struct storage).
U0 HcRegisterGlobalPtr(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) { g_hc_global_is_ptr[i] = 1; return; }
    }
    if (g_hc_global_count < HC_MAX_GLOBALS) {
        HcSafeCopy(&g_hc_global_names[g_hc_global_count * 32], name, 32);
        g_hc_global_st_idx[g_hc_global_count] = -1;
        g_hc_global_is_ptr[g_hc_global_count] = 1;
        g_hc_global_count++;
    }
}

I64 HcGlobalIsPtr(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) return g_hc_global_is_ptr[i];
    }
    return 0;
}

U0 HcRegisterGlobalFloat(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) { g_hc_global_is_float[i] = 1; return; }
    }
    if (g_hc_global_count < HC_MAX_GLOBALS) {
        HcSafeCopy(&g_hc_global_names[g_hc_global_count * 32], name, 32);
        g_hc_global_st_idx[g_hc_global_count] = -1;
        g_hc_global_is_float[g_hc_global_count] = 1;
        g_hc_global_count++;
    }
}

I64 HcGlobalIsFloat(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) return g_hc_global_is_float[i];
    }
    return 0;
}

// Register the element byte width used to index a global array. Registered for
// every parsed global array regardless of whether its storage was allocated here
// or by the C JIT (which sizes arrays at their true element width).
U0 HcRegisterGlobalScale(U8 *name, I64 scale) {
    if (scale <= 0) return;
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) { g_hc_global_elem_scale[i] = scale; return; }
    }
    if (g_hc_global_count < HC_MAX_GLOBALS) {
        HcSafeCopy(&g_hc_global_names[g_hc_global_count * 32], name, 32);
        g_hc_global_st_idx[g_hc_global_count] = -1;
        g_hc_global_elem_scale[g_hc_global_count] = scale;
        g_hc_global_count++;
    }
}

I64 HcGlobalScale(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) return g_hc_global_elem_scale[i];
    }
    return 0;
}

// Register the per-dimension byte strides of a global array. strides[k] is the
// byte step applied to subscript k: for `I64 m[N][M]` that is [M*8, 8]. 0 marks
// "no such dimension". This is what lets `m[i][j]` resolve to base + i*M*8 + j*8
// with no intermediate dereference (the old code had no row stride at all).
U0 HcRegisterGlobalStrides(U8 *name, I64 s0, I64 s1, I64 s2, I64 s3) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) {
            g_hc_global_strides[i * 4 + 0] = s0;
            g_hc_global_strides[i * 4 + 1] = s1;
            g_hc_global_strides[i * 4 + 2] = s2;
            g_hc_global_strides[i * 4 + 3] = s3;
            return;
        }
    }
    if (g_hc_global_count < HC_MAX_GLOBALS) {
        HcSafeCopy(&g_hc_global_names[g_hc_global_count * 32], name, 32);
        g_hc_global_st_idx[g_hc_global_count] = -1;
        g_hc_global_strides[g_hc_global_count * 4 + 0] = s0;
        g_hc_global_strides[g_hc_global_count * 4 + 1] = s1;
        g_hc_global_strides[g_hc_global_count * 4 + 2] = s2;
        g_hc_global_strides[g_hc_global_count * 4 + 3] = s3;
        g_hc_global_count++;
    }
}

I64 HcGlobalStride(U8 *name, I64 k) {
    if (k < 0 || k > 3) return 0;
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) return g_hc_global_strides[i * 4 + k];
    }
    return 0;
}

I64 HcGlobalStructIdx(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) return g_hc_global_st_idx[i];
    }
    return -1;
}

// Clear a global's recorded type so a RE-declaration (e.g. a stateful REPL where a
// later unit declares `I64 x` after an earlier one declared `F64 x`) starts from a
// clean slate. Without this the stale float/array/struct flags make the new
// declaration compile with the old type.
U0 HcResetGlobalType(U8 *name) {
    for (I64 i = 0; i < g_hc_global_count; i++) {
        if (strcmp(&g_hc_global_names[i * 32], name) == 0) {
            g_hc_global_st_idx[i] = -1;
            g_hc_global_is_arr[i] = 0;
            g_hc_global_is_ptr[i] = 0;
            g_hc_global_is_float[i] = 0;
            g_hc_global_elem_scale[i] = 0;
            g_hc_global_strides[i * 4 + 0] = 0;
            g_hc_global_strides[i * 4 + 1] = 0;
            g_hc_global_strides[i * 4 + 2] = 0;
            g_hc_global_strides[i * 4 + 3] = 0;
            return;
        }
    }
}

U0 HcResolveLValue(U8 *ident_name, I64 *out_scale, I64 *out_addr_only, I64 *out_is_float) {
    *out_scale = 8;
    *out_addr_only = 0;
    *out_is_float = 0;

    I64 loc_idx = HcFindLocalIdx(ident_name);
    I64 cur_scale = 8;
    I64 cur_st_idx = -1;
    I64 cur_mode = 0; // 0=scalar, 1=ptr, 2=inline_arr, 3=inline_struct
    I64 cur_is_float = 0;
    I64 arr_sym = 0;  // 1 while indexing the base array symbol's own subscripts
    I64 sub_k = 0;    // current subscript depth (0 = first dimension)

    if (loc_idx >= 0) {
        I64 rlv_off = g_hc_local_offsets[loc_idx];
        cur_scale = g_hc_local_scales[loc_idx];
        cur_st_idx = g_hc_local_st_idx[loc_idx];
        cur_mode = g_hc_local_is_ptr[loc_idx];
        cur_is_float = g_hc_local_is_float[loc_idx];
        if (cur_mode == 2) arr_sym = 1;

        if (cur_mode == 2 || cur_mode == 3) {
            HcEmitAddrLocal(0, rlv_off);
        } else if (cur_mode == 1 && (g_hc_tok == TOK_ARROW || g_hc_tok == TOK_LBRACKET || g_hc_tok == TOK_DOT)) {
            HcEmitLoadLocal(0, rlv_off);
            cur_mode = 0;
            // P4.6 root fix: indexing a POINTER local (e.g. `F64 *px; px[i]`) must
            // use the POINTEE floatness, not the pointer's own (which is always 0).
            if (g_hc_tok == TOK_LBRACKET) cur_is_float = g_hc_local_elem_float[loc_idx];
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
            cur_st_idx = HcGlobalStructIdx(ident_name);
            cur_is_float = HcGlobalIsFloat(ident_name);
            I64 gscale = HcGlobalScale(ident_name);
            if (gscale > 0) cur_scale = gscale;
            // Global arrays are stored behind an 8-byte cell holding the base
            // address (the C JIT allocates them that way, and HcParseProgram now
            // matches). Dereference the cell so indexed *and* unindexed uses both
            // see the true base address instead of the cell's low bytes.
            if (HcGlobalIsArray(ident_name)) {
                HcEmit(0xF9400000); // ldr x0, [x0] : array cell -> base address
                cur_mode = 2;
                arr_sym = 1;
            } else if (HcGlobalIsPtr(ident_name)) {
                // Global pointer (possibly to a struct). Dereference the cell once
                // before indexing / -> member access; leave cur_mode = 0 so the
                // member/index loops below do NOT dereference a second time.
                if (g_hc_tok == TOK_LBRACKET || g_hc_tok == TOK_ARROW) {
                    HcEmit(0xF9400000); // ldr x0, [x0]
                }
                // A BARE pointer use must load the 8-byte pointer value; only an
                // indexed use (`p[i]`) uses the registered pointee width (cur_scale
                // set above from HcGlobalScale). Without this, `U32 *fb = ...` style
                // bare reads would load only sizeof(pointee) bytes.
                if (g_hc_tok != TOK_LBRACKET) cur_scale = 8;
            } else if (cur_st_idx >= 0) {
                cur_mode = 3; // global struct value: the symbol IS its storage
            } else if (g_hc_tok == TOK_LBRACKET || g_hc_tok == TOK_ARROW) {
                HcEmit(0xF9400000); // ldr x0, [x0] (deref pointer before indexing)
            }
        } else {
            // Forward reference: reserve a global cell so it resolves when defined.
            U64 vcell = (U64)symbols_var_cell(ident_name);
            HcEmitImm64(0, vcell);
            cur_st_idx = HcGlobalStructIdx(ident_name);
        }
    }

    if (g_hc_tok != TOK_DOT && g_hc_tok != TOK_ARROW && g_hc_tok != TOK_LBRACKET) {
        *out_scale = cur_scale;
        *out_is_float = cur_is_float;
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
            arr_sym = 0; // member access ends the base array's subscript chain
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
                I64 m_flt = 0;
                I64 m_elem = 8;
                if (HcFindMember(cur_st_idx, mname, &m_off, &m_sz, &m_arr, &m_ptr, &m_sub, &m_flt)) {
                    m_elem = g_hc_found_member_elem;
                    if (m_off != 0) {
                        HcEmitImm64(1, m_off);
                        HcEmit(0x8B010000); // add x0, x0, x1
                    }
                    cur_scale = m_sz;
                    cur_st_idx = m_sub;
                    cur_is_float = m_flt;
                    if (m_arr) cur_mode = 2;
                    else if (m_ptr) cur_mode = 1;
                    else if (m_sub >= 0) cur_mode = 3;
                    else cur_mode = 0;
                    // D7 ROOT FIX: indexing a pointer (or inline array) member must
                    // stride by the pointee/element width, not the 8-byte pointer
                    // field width. `s.data[k]` (U32 *) strides by 4 and loads LDR W.
                    // The C JIT already did this via struct_member_t.elem_size; the
                    // self-hosted compiler lost it, forcing a typed-local workaround.
                    if ((m_ptr || m_arr) && g_hc_tok == TOK_LBRACKET) cur_scale = m_elem;
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

            // Element stride for THIS subscript. For a registered array symbol
            // (global or local) use its per-dimension byte stride: the row stride
            // for [i], the element width for [j]. This is what makes arr[i][j]
            // resolve to base + i*row_stride + j*elem with NO intermediate
            // dereference. Otherwise fall back to the element width, or the
            // pointee struct size for an array of inline struct values.
            I64 elem_sz = cur_scale;
            I64 stride_k = 0;
            if (arr_sym) {
                if (loc_idx >= 0) stride_k = HcLocalStride(loc_idx, sub_k);
                else stride_k = HcGlobalStride(ident_name, sub_k);
            }
            if (stride_k > 0) {
                elem_sz = stride_k;
            } else if (cur_st_idx >= 0 && cur_mode != 1 && HcGlobalScale(ident_name) <= 0) {
                elem_sz = g_hc_struct_sizes[cur_st_idx];
            }
            if (elem_sz > 1) {
                HcEmitImm64(2, elem_sz);
                HcEmit(0x9B027C00); // mul x0, x0, x2
            }
            HcEmit(0x8B000020); // add x0, x1, x0
            sub_k = sub_k + 1;

            if (g_hc_tok == TOK_LBRACKET) {
                // Chained multidimensional array indexing (e.g. matrix[i][j]).
                // X0 now holds the sub-array base address, so do NOT dereference
                // it (the old cur_mode=1 here emitted an LDR that loaded element
                // [i] as a pointer -> Data Abort). Advance to the next stride.
                cur_mode = 0;
                I64 nk = 0;
                if (arr_sym) {
                    if (loc_idx >= 0) nk = HcLocalStride(loc_idx, sub_k);
                    else nk = HcGlobalStride(ident_name, sub_k);
                }
                if (nk > 0) cur_scale = nk;
                cur_is_float = (loc_idx >= 0) ? g_hc_local_is_float[loc_idx] : HcGlobalIsFloat(ident_name);
            } else {
                cur_mode = 0;
            }
        }
    }

    *out_scale = cur_scale;
    *out_is_float = cur_is_float;
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
            HcParseUnary(); // cast binds tighter than binary ops: (F64)k * 6.0 == ((F64)k) * 6.0
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

        // Direct Function Call: ident(arg1, arg2, ...). If ident names a VARIABLE
        // (e.g. a global function pointer `I64 fp = &inc;`), fall through to the
        // indirect-call path below so we load the pointer's value and blr it,
        // instead of treating the variable's storage cell as the call target.
        if (g_hc_tok == TOK_LPAREN && HcFindLocalIdx(ident_name) < 0 && !symbols_is_var(ident_name)) {
            I64 is_intr = HcIsIntrinsic(ident_name);
            U64 sic = is_intr ? 0 : (U64)symbols_sic_cell(ident_name);
            HcOpPush(sic);

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

            if (cur_argc > 8) {
                // AArch64 passes the first 8 integer/FP arguments in X0-X7. More
                // requires stack spilling, which is not implemented; hard-error
                // instead of silently clobbering registers past X7 (matches the C JIT).
                g_hc_error = 1;
            }

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
            HcEmitLoadSized(16, 16, 8); // ldr x16, [x16] : SIC cell -> live entry
            HcEmit(0xD63F0200); // blr x16
            g_hc_expr_float = HcFuncIsFloat(ident_name);
            return;
        }

        // LValue resolution for variables, arrays, and struct fields
        I64 lv_scale = 8;
        I64 lv_addr_only = 0;
        I64 lv_is_float = 0;
        HcResolveLValue(ident_name, &lv_scale, &lv_addr_only, &lv_is_float);

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
            if (lv_is_float) {
                HcEmit(0xFD400000); // ldr d0, [x0]  (F64 scalar/array element)
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
            if (ind_argc > 8) g_hc_error = 1; // >8 args needs stack spill (see direct-call note)
            I64 ia_reg = 0;
            for (ia_reg = ind_argc - 1; ia_reg >= 0; ia_reg--) {
                HcEmitPop(ia_reg);
            }
            HcEmitPop(16); // Pop function pointer into x16
            HcEmit(0xD63F0200); // blr x16
        }
        return;
    }

    // Any other token (a binary operator, ';', ')', '}', EOF, ...) cannot begin a
    // primary expression. Flag a hard error instead of silently emitting nothing,
    // which would let malformed input like `2 + ;` miscompile.
    g_hc_error = 1;
}

U0 HcParseUnary() {
    if (g_hc_tok == TOK_MINUS) {
        HcLexNext();
        HcParseUnary();
        if (g_hc_expr_float) HcEmit(0x1E614000); // fneg d0, d0
        else HcEmit(0xCB0003E0);                 // neg x0, x0
        return;
    }
    if (g_hc_tok == TOK_EXCLAM) {
        HcLexNext();
        HcParseUnary();
        if (g_hc_expr_float) {
            HcEmit(0x1E602008); // fcmp d0, #0.0
            g_hc_expr_float = 0;
        } else {
            HcEmit(0xF100001F); // cmp x0, #0
        }
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
            I64 amp_scale = 8;
            I64 amp_ao = 0;
            I64 amp_flt = 0;
            HcResolveLValue(amp_name, &amp_scale, &amp_ao, &amp_flt);
            g_hc_expr_float = 0; // address-of yields an integer pointer
            return;
        }
        HcParseUnary();
        g_hc_expr_float = 0;
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
        g_hc_expr_float = 0; // sizeof yields an integer
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
        g_hc_expr_float = 0; // integer-sized dereference load
        return;
    }
    HcParsePrimary();
}

// P4.3 ROOT FIX: when a binary op has one F64 and one integer operand, the
// integer must be converted to F64 (SCVTF) before the float op. Previously the
// float path blindly did `fmov d0,x0`/`fmov d1,x1`, reinterpreting the integer
// bit pattern as a double — e.g. `g_hgl.vp_w * 0.5` produced a denormal ~0, so
// every HolyGL triangle collapsed to (0,0). Left bits/int are on the stack top;
// the right result is in d0 (rf) or x0 (integer).
U0 HcEmitPromoteFloat(I64 lf, I64 rf) {
    if (rf) {
        HcEmit(0x9E660001);   // fmov x1, d0   (right is F64 bits)
    } else {
        HcEmit(0x9E620000);   // scvtf d0, x0  (right int -> double)
        HcEmit(0x9E660001);   // fmov x1, d0
    }
    HcEmitPop(0);             // x0 = left
    if (lf) {
        HcEmit(0x9E670000);   // fmov d0, x0   (left is F64 bits)
    } else {
        HcEmit(0x9E620000);   // scvtf d0, x0  (left int -> double)
    }
    HcEmit(0x9E670021);       // fmov d1, x1   (right -> d1)
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
            HcEmitPromoteFloat(lf, rf);
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
            HcEmitPromoteFloat(lf, rf);
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
            HcEmitPromoteFloat(lf, rf);
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
            HcEmitPromoteFloat(lf, rf);
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
        if (patch_idx < 0 || patch_idx >= HC_CODE_CAPACITY) { g_hc_error = 1; return; } // P0.7: bounds guard
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
            strcmp(name, "__mmio_r32") == 0 || strcmp(name, "__mmio_w32") == 0 ||
            strcmp(name, "__msr_cntv_tval") == 0 || strcmp(name, "__msr_cntv_ctl") == 0 ||
            strcmp(name, "__irq_disable") == 0 || strcmp(name, "__irq_enable") == 0 ||
            strcmp(name, "__mrs_daif") == 0 || strcmp(name, "__msr_daif") == 0);
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
    else if (strcmp(name, "__msr_cntv_tval") == 0) HcEmit(0xD51BE300); // MSR CNTV_TVAL_EL0, X0
    else if (strcmp(name, "__msr_cntv_ctl") == 0) HcEmit(0xD51BE320);  // MSR CNTV_CTL_EL0, X0
    else if (strcmp(name, "__irq_disable") == 0) HcEmit(0xD50342DF);   // MSR DAIFSet, #2
    else if (strcmp(name, "__irq_enable") == 0) HcEmit(0xD50342FF);    // MSR DAIFClr, #2
    else if (strcmp(name, "__mrs_daif") == 0) HcEmit(0xD53B4220);      // MRS X0, DAIF
    else if (strcmp(name, "__msr_daif") == 0) HcEmit(0xD51B4220);      // MSR DAIF, X0
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
// P7.0 / D29 ROOT FIX: array-dimension constant-expression parser.
//
// Every array dimension (`Type name[N]`, `Type name[N*M]`, struct-member arrays)
// must fold constant expressions. Before this, three separate inline parsers in
// this file (and two in the C seed) folded only `*` and `+`, so `[HC_CODE_CAPACITY/8]`
// dropped the `/8` (silently allocating 8x the intended bytes) and `-`/`<<`/`>>`
// were left unconsumed. This single helper folds `* / % + - << >>` with C
// precedence, unary `+/-`, and parentheses. `#define` macros are already
// substituted to TOK_NUMBER by the lexer. Call it with the `[` already consumed;
// it stops at (but does not consume) the closing `]`.
// ------------------------------------------------------------------------------
I64 HcDimPrec(I64 tok) {
    if (tok == TOK_STAR || tok == TOK_SLASH || tok == TOK_PERCENT) return 5;
    if (tok == TOK_PLUS || tok == TOK_MINUS) return 4;
    if (tok == TOK_SHL || tok == TOK_SHR) return 3;
    return -1;
}

I64 HcParseArrayDimExpr(I64 min_prec) {
    I64 v = 0;
    if (g_hc_tok == TOK_MINUS) { HcLexNext(); v = 0 - HcParseArrayDimExpr(6); }
    else if (g_hc_tok == TOK_PLUS) { HcLexNext(); v = HcParseArrayDimExpr(6); }
    else if (g_hc_tok == TOK_LPAREN) { HcLexNext(); v = HcParseArrayDimExpr(0); if (g_hc_tok == TOK_RPAREN) HcLexNext(); }
    else if (g_hc_tok == TOK_NUMBER) { v = g_hc_tok_val; HcLexNext(); }
    while (1) {
        I64 prec = HcDimPrec(g_hc_tok);
        if (prec < min_prec) break;
        I64 op = g_hc_tok;
        HcLexNext();
        I64 r = HcParseArrayDimExpr(prec + 1);
        if (op == TOK_STAR) v = v * r;
        else if (op == TOK_SLASH) { if (r != 0) v = v / r; else g_hc_error = 1; }
        else if (op == TOK_PERCENT) { if (r != 0) v = v % r; else g_hc_error = 1; }
        else if (op == TOK_PLUS) v = v + r;
        else if (op == TOK_MINUS) v = v - r;
        else if (op == TOK_SHL) v = v << r;
        else if (op == TOK_SHR) v = v >> r;
    }
    return v;
}

// Parse one dimension between `[` and `]` (the `[` already consumed). An empty
// `[]` yields 1. Consumes the closing `]`.
I64 HcParseArrayDim() {
    I64 dim = 1;
    if (g_hc_tok != TOK_RBRACKET) dim = HcParseArrayDimExpr(0);
    if (g_hc_tok == TOK_RBRACKET) HcLexNext();
    return dim;
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
        I64 base_flt = 0;
        if (HcIsTypeToken(g_hc_tok)) {
            base_flt = (g_hc_tok == TOK_TYPE_F64);
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
            if (fp_name[0] && m_cnt < 64) {
                I64 fp_slot = st_idx * 64 + m_cnt;
                HcSafeCopy(&g_hc_member_names[fp_slot * 32], fp_name, 32);
                g_hc_member_offsets[fp_slot] = cur_off;
                g_hc_member_sizes[fp_slot] = 8;
                g_hc_member_is_arr[fp_slot] = 0;
                g_hc_member_is_ptr[fp_slot] = 1;
                g_hc_member_st_idx[fp_slot] = -1;
                g_hc_member_is_float[fp_slot] = 0;
                g_hc_member_elem_bytes[fp_slot] = 8;
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
                    // D29 ROOT FIX: a member array dimension may be any constant
                    // expression (N, N*M, N/M, N+M, N-M, N<<M, N>>M, parentheses),
                    // exactly like the local-array and global-array parsers.
                    I64 acnt = HcParseArrayDim();
                    field_bytes = elem_sz * acnt;
                    is_a = 1;
                }

                // Packed layout (no inter-member padding), matching the C JIT exactly.
                if (m_cnt < 64) {
                    I64 m_slot = st_idx * 64 + m_cnt;
                    HcSafeCopy(&g_hc_member_names[m_slot * 32], mem_n, 32);
                    g_hc_member_offsets[m_slot] = cur_off;
                    g_hc_member_sizes[m_slot] = (is_p || elem_sz > 8) ? 8 : elem_sz;
                    g_hc_member_is_arr[m_slot] = is_a;
                    g_hc_member_is_ptr[m_slot] = is_p;
                    g_hc_member_st_idx[m_slot] = sub_st;
                    g_hc_member_is_float[m_slot] = (base_flt && !is_p && sub_st < 0) ? 1 : 0;
                    // Element/pointee width for indexing: base_sz is the declared
                    // base type width (or nested struct size), independent of the
                    // 8-byte pointer field width. This is what D7 was losing.
                    g_hc_member_elem_bytes[m_slot] = base_sz;
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

    // Packed total size (no trailing padding), matching the C JIT's total_size.
    I64 struct_tot = cur_off;
    if (struct_tot <= 0) struct_tot = 8;
    g_hc_struct_sizes[st_idx] = struct_tot;
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

U0 HcFinishMemoryAssign(I64 mem_scale, I64 is_float) {
    if (g_hc_tok == TOK_EQUAL) {
        HcLexNext(); // eat '='
        HcEmitPush(0); // save target address
        HcParseExpr(); // RHS in x0 (or d0 if float)
        if (is_float) {
            if (!g_hc_expr_float) HcEmit(0x9E620000); // scvtf d0, x0
            HcEmitPop(1);        // target address in x1
            HcEmit(0xFD000020);  // str d0, [x1]
            g_hc_expr_float = 0;
            return;
        }
        HcEmitPop(1);  // target address in x1
        HcEmitStoreSized(0, 1, mem_scale);
        return;
    }
    if (is_float) {
        // Float compound assignment / inc-dec is not supported: hard error, never miscompile.
        g_hc_error = 1;
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
            g_hc_decl_float = 0;   // P4.6: function pointers are never F64
            g_hc_decl_elem_float = 0;
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
                    I64 l_dims[4];
                    I64 l_ndim = 0;
                    I64 arr_cnt = 1;
                    while (g_hc_tok == TOK_LBRACKET) {
                        HcLexNext();
                        // D29 ROOT FIX: any constant expression as the dimension.
                        I64 dim = HcParseArrayDim();
                        arr_cnt = arr_cnt * dim;
                        if (l_ndim < 4) l_dims[l_ndim] = dim;
                        l_ndim = l_ndim + 1;
                    }
                    I64 arr_elem_sz = (is_p > 0) ? 8 : base_scale;
                    // P4.6 root fix: HcAddLocalTyped records the element floatness
                    // from g_hc_decl_float, but the local-array path never set it,
                    // so an F64 array inherited the PREVIOUS declaration's type and
                    // its elements were read/written as integers. Set it explicitly.
                    g_hc_decl_float = (is_p > 0) ? 0 : base_is_float;
                    g_hc_decl_elem_float = base_is_float;
                    I64 arr_off = HcAddLocalTyped(vname, arr_elem_sz, 2, (is_p > 0) ? -1 : st_idx, arr_cnt);
                    g_hc_decl_elem_float = 0;
                    // Per-dimension strides: stride[last] = elem width,
                    // stride[d] = dims[d+1]*stride[d+1]  (row stride for [i]).
                    I64 l_acc = arr_elem_sz;
                    I64 l_nd = l_ndim; if (l_nd > 4) l_nd = 4;
                    I64 l_s0 = 0; I64 l_s1 = 0; I64 l_s2 = 0; I64 l_s3 = 0;
                    for (I64 ld = l_nd - 1; ld >= 0; ld--) {
                        if (ld == 0) l_s0 = l_acc;
                        else if (ld == 1) l_s1 = l_acc;
                        else if (ld == 2) l_s2 = l_acc;
                        else l_s3 = l_acc;
                        if (ld > 0) l_acc = l_acc * l_dims[ld];
                    }
                    HcSetLocalStrides(vname, l_s0, l_s1, l_s2, l_s3);
                    // Local array initializer list: Type a[N] = { e0, e1, ... };
                    if (g_hc_tok == TOK_EQUAL) {
                        HcLexNext(); // eat '='
                        if (g_hc_tok == TOK_LBRACE) {
                            HcLexNext(); // eat '{'
                            I64 ai = 0;
                            while (g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF && ai < arr_cnt) {
                                I64 aev = 0;
                                I64 aflt = 0;
                                I64 aneg = 0;
                                if (g_hc_tok == TOK_MINUS) { aneg = 1; HcLexNext(); }
                                if (g_hc_tok == TOK_FLOAT) { aev = g_hc_tok_val; aflt = 1; HcLexNext(); }
                                else if (g_hc_tok == TOK_NUMBER) { aev = g_hc_tok_val; HcLexNext(); }
                                else if (g_hc_tok == TOK_STRING) { aev = g_hc_tok_val; HcLexNext(); }
                                else break;
                                if (aneg) { if (aflt) aev = aev ^ (1 << 63); else aev = -aev; }
                                I64 aeoff = arr_off + ai * arr_elem_sz;
                                HcEmitImm64(0, aev);
                                HcEmitStoreLocal(0, aeoff);
                                ai++;
                                if (g_hc_tok == TOK_COMMA) HcLexNext();
                                else break;
                            }
                            if (g_hc_tok == TOK_RBRACE) HcLexNext();
                        } else {
                            g_hc_error = 1; // only literal initializer lists are supported
                        }
                    }
                } else if (st_idx >= 0 && is_p == 0) {
                    g_hc_decl_float = 0;   // P4.6: struct-value locals are never F64
                    g_hc_decl_elem_float = 0;
                    HcAddLocalTyped(vname, base_scale, 3, st_idx, 1);
                } else {
                    I64 var_scale = (is_p > 0) ? base_scale : 8;
                    I64 ptr_mode = (is_p > 0) ? 1 : 0;
                    I64 decl_is_f = (is_p == 0 && base_is_float);
                    g_hc_decl_float = decl_is_f;
                    g_hc_decl_elem_float = base_is_float;   // F64* local: pointee is F64
                    I64 decl_off = HcAddLocalTyped(vname, var_scale, ptr_mode, st_idx, 1);
                    g_hc_decl_float = 0;
                    g_hc_decl_elem_float = 0;
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
            I64 blk_pp = g_hc_pos;
            HcCallParseStmt();
            if (g_hc_pos <= blk_pp && g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF) {
                // Invariant: a statement parser must consume >= 1 token. If it did
                // not, raise a hard error and skip a token so the compiler can never
                // hang on a non-advancing token.
                g_hc_error = 1;
                HcLexNext();
            }
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
        I64 mem_assigned = (g_hc_tok == TOK_EQUAL || g_hc_tok == TOK_PLUSPLUS ||
                            g_hc_tok == TOK_MINUSMINUS || HcIsAssignOp(g_hc_tok));
        HcFinishMemoryAssign(st_sz, 0);
        // A bare `*ptr;` is a dereference READ: load the pointed-to value so the
        // statement's value is the contents, not the address (matches the C JIT).
        if (!mem_assigned) HcEmitLoadSized(0, 0, st_sz);
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
            I64 lv_flt = 0;
            HcResolveLValue(iname, &lv_sz, &lv_ao, &lv_flt);
            if (HcIsAssignOp(g_hc_tok)) {
                HcFinishMemoryAssign(lv_sz, lv_flt);
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
                g_hc_decl_elem_float = p_is_float;   // F64* param: pointee is F64
                I64 fn_arg_off = HcAddLocalTyped(pname, v_scale, p_is_ptr, p_st_idx, 1);
                g_hc_decl_float = 0;
                g_hc_decl_elem_float = 0;
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

    // D17 root fix: a forward prototype `Type name(args);` must NOT publish a body.
    // An empty body emitted at this address would win the SIC cell over the real
    // definition (HcPublishFunc never updates an already-defined symbol). Record
    // only the return-floatness; the real definition publishes the address.
    if (g_hc_tok == TOK_SEMICOLON) {
        HcFnFloatSet(func_name, g_hc_fn_ret_float);
        HcLexNext();
        return;
    }

    HcAddFunc(func_name, fn_entry);
    HcParseStatement();
    HcEmitEpilogue();
    HcFinalizeFrame();
}

// Emit runtime initialization for top-level globals whose initializer was not a
// literal (`I64 *p = &x;`, `I64 b = a + 4;`, ...). Each initializer is re-lexed from
// its recorded source position, evaluated, and stored into the global's storage cell.
// The lexer state is saved/restored so the caller's parse position is preserved.
U0 HcEmitDeferredInits() {
    if (g_hc_init_count <= 0) return;
    I64 sp = g_hc_pos;
    I64 st = g_hc_tok;
    I64 sv = g_hc_tok_val;
    I64 stp = g_hc_tok_pos;
    U8  ss[256];
    HcSafeCopy(ss, g_hc_tok_str, 256);

    I64 di = 0;
    for (di = 0; di < g_hc_init_count; di++) {
        g_hc_pos = g_hc_init_pos[di];
        HcLexNext();          // re-prime the lexer at the initializer expression
        HcParseExpr();        // result in x0 (or d0 if float)
        HcEmitImm64(16, g_hc_init_slot[di]);
        if (g_hc_expr_float) HcEmit(0xFD000200); // str d0, [x16]
        else                 HcEmit(0xF9000200); // str x0, [x16]
    }

    g_hc_pos = sp;
    g_hc_tok = st;
    g_hc_tok_val = sv;
    g_hc_tok_pos = stp;
    HcSafeCopy(g_hc_tok_str, ss, 256);
}

// Lookahead: does the current token begin a function definition (`Type [*]* name (`)
// or a class/struct definition? Used to end a top-level statement block when a
// declaration follows it. Restores the lexer state either way.
I64 HcAtFunctionDef() {
    if (g_hc_tok == TOK_CLASS || g_hc_tok == TOK_STRUCT) return 1;
    if (!HcIsTypeToken(g_hc_tok) && !(g_hc_tok == TOK_IDENT && HcFindStruct(g_hc_tok_str) >= 0)) return 0;
    I64 sp = g_hc_pos;
    I64 st = g_hc_tok;
    I64 sv = g_hc_tok_val;
    I64 stp = g_hc_tok_pos;
    U8  ss[256];
    HcSafeCopy(ss, g_hc_tok_str, 256);
    HcLexNext();
    while (g_hc_tok == TOK_STAR) HcLexNext();
    I64 is_fn = 0;
    if (g_hc_tok == TOK_IDENT) {
        HcLexNext();
        is_fn = (g_hc_tok == TOK_LPAREN);
    }
    g_hc_pos = sp; g_hc_tok = st; g_hc_tok_val = sv; g_hc_tok_pos = stp;
    HcSafeCopy(g_hc_tok_str, ss, 256);
    return is_fn;
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

            // Size the global from its declared type (struct -> total_size).
            I64 g_st_idx = -1;
            I64 g_bytes = 8;
            if (save_t == TOK_IDENT) {
                g_st_idx = HcFindStruct(save_s);
                if (g_st_idx >= 0) g_bytes = g_hc_struct_sizes[g_st_idx];
            } else {
                g_bytes = HcTypeTokenScale(save_t);
            }
            I64 g_elem_bytes = g_bytes; // true element width, for array indexing
            if (g_bytes < 8) g_bytes = 8;

            HcLexNext(); // eat Type
            I64 g_is_ptr = 0;
            while (g_hc_tok == TOK_STAR) { g_is_ptr = 1; HcLexNext(); }
            I64 g_decl = 0;
            I64 g_was_fn = 0;
            while (g_hc_tok == TOK_IDENT) {
                g_decl = 1;
                U8 fname[64];
                HcSafeCopy(fname, g_hc_tok_str, 64);
                HcLexNext(); // eat ident
                if (g_hc_tok == TOK_LPAREN) {
                    HcLexNext(); // eat '('
                    g_hc_fn_ret_float = (save_t == TOK_TYPE_F64);
                    HcParseFunction(fname);
                    g_hc_fn_ret_float = 0;
                    g_was_fn = 1;
                    break;
                }
                // Top-level array dimensions: Type g_arr[N][M]...  A dimension may be
                // a constant expression of the form N, N*M or N+M (macros are already
                // substituted by the lexer), e.g. `[HC_MAX_GLOBALS * 32]`.
                I64 g_count = 1;
                I64 g_has_bracket = 0;
                I64 g_dims[4];
                I64 g_ndim = 0;
                while (g_hc_tok == TOK_LBRACKET) {
                    g_has_bracket = 1;
                    HcLexNext();
                    // D29 ROOT FIX: any constant expression as the dimension.
                    I64 dim = HcParseArrayDim();
                    g_count *= dim;
                    if (g_ndim < 4) g_dims[g_ndim] = dim;
                    g_ndim = g_ndim + 1;
                }
                // Top-level global variable declaration: Type g_var [= val];
                U64 g_slot = symbols_lookup(fname);
                I64 g_is_arr = g_has_bracket;
                if (!g_slot) {
                    I64 g_elem_sz = g_is_ptr ? 8 : g_elem_bytes;
                    I64 g_alloc = g_is_arr ? (g_count * g_elem_sz) : (g_is_ptr ? 8 : g_bytes);
                    g_alloc = (g_alloc + 15) & (~15);
                    if (g_alloc < 16) g_alloc = 16;
                    if (g_is_arr) {
                        // Arrays live behind an 8-byte cell holding the base address,
                        // exactly as the C JIT registers them.
                        U64 g_arr_buf = kmalloc(g_alloc);
                        U64 g_arr_cell = kmalloc(8);
                        if (!g_arr_buf || !g_arr_cell) {
                            // P0.7: never memset through NULL (that was a write to
                            // address 0). Fail the unit cleanly instead.
                            doldoc_printf("[HCLX] GLOBAL ARRAY ALLOC FAILED %s bytes=%lld\n", fname, g_alloc);
                            g_hc_error = 1;
                            g_hc_tok = TOK_EOF;
                            return;
                        }
                        memset((U8*)g_arr_buf, 0, g_alloc);
                        *(U64*)g_arr_cell = g_arr_buf;
                        g_slot = g_arr_cell;
                    } else {
                        g_slot = kmalloc(g_alloc);
                        if (!g_slot) {
                            doldoc_printf("[HCLX] GLOBAL ALLOC FAILED %s bytes=%lld\n", fname, g_alloc);
                            g_hc_error = 1;
                            g_hc_tok = TOK_EOF;
                            return;
                        }
                        memset((U8*)g_slot, 0, g_alloc);
                    }
                    symbols_register(fname, g_slot, 2);
                }
                // Record the array/struct/float nature of the global even when its
                // storage already exists (allocated by the C JIT at boot): the JIT's
                // global name table does not record array-ness, and without this the
                // self-host compiler indexes and dereferences global arrays wrongly.
                HcResetGlobalType(fname);
                if (g_is_arr) HcRegisterGlobalArray(fname);
                if (g_is_ptr) HcRegisterGlobalPtr(fname);
                // Record the struct type for BOTH a struct value global and a
                // pointer-to-struct global, so `g.field` and `p->field` resolve
                // member offsets (HcGlobalIsPtr distinguishes the two at use site).
                if (g_st_idx >= 0) HcRegisterGlobalStruct(fname, g_st_idx);
                if (save_t == TOK_TYPE_F64 && !g_is_ptr) HcRegisterGlobalFloat(fname);
                // Register the array element width for indexing even when the storage
                // was already allocated by the C JIT (symbols_lookup found it): the
                // JIT sizes global arrays at their true element width, so indexing
                // them at the default 8-byte scale would run out of bounds.
                // Element stride for indexing. A pointer-element array (e.g.
                // `CSymbol *g_sym_buckets[256]`) strides by 8, NOT by the pointee
                // struct size — register 8 so the index path below does not fall
                // back to the struct size. Value arrays stride by element width.
                if (g_is_arr) HcRegisterGlobalScale(fname, g_is_ptr ? 8 : g_elem_bytes);
                // Register per-dimension strides so arr[i][j] indexes correctly:
                // stride[last] = element width, stride[d] = dims[d+1]*stride[d+1].
                if (g_is_arr) {
                    I64 g_acc = g_is_ptr ? 8 : g_elem_bytes;
                    I64 g_nd = g_ndim; if (g_nd > 4) g_nd = 4;
                    I64 g_s0 = 0; I64 g_s1 = 0; I64 g_s2 = 0; I64 g_s3 = 0;
                    for (I64 gd = g_nd - 1; gd >= 0; gd--) {
                        if (gd == 0) g_s0 = g_acc;
                        else if (gd == 1) g_s1 = g_acc;
                        else if (gd == 2) g_s2 = g_acc;
                        else g_s3 = g_acc;
                        if (gd > 0) g_acc = g_acc * g_dims[gd];
                    }
                    HcRegisterGlobalStrides(fname, g_s0, g_s1, g_s2, g_s3);
                }
                // A global POINTER also needs its pointee width registered so that
                // `p[i]` strides by sizeof(pointee) and loads/stores the pointee
                // width (e.g. `U16 *zb; zb[i]` must be a 2-byte LDRH, not an 8-byte
                // LDR). Without this, HcGlobalScale returns 0 and indexing falls
                // back to the default 8-byte stride/width — the P4.2 rasterizer bug.
                else if (g_is_ptr) HcRegisterGlobalScale(fname, g_elem_bytes);
                if (g_hc_tok == TOK_EQUAL) {
                    HcLexNext();
                    I64 g_init_pos = g_hc_tok_pos; // start of the initializer expression
                    if (g_is_arr && !g_is_ptr && g_hc_tok == TOK_LBRACE) {
                        // Array initializer list: Type name[N] = { e0, e1, ... };
                        HcLexNext(); // eat '{'
                        U64 g_base = *(U64*)g_slot; // array cell -> element base
                        I64 gi = 0;
                        while (g_hc_tok != TOK_RBRACE && g_hc_tok != TOK_EOF && gi < g_count) {
                            I64 gev = 0;
                            I64 gflt = 0;
                            I64 gneg = 0;
                            if (g_hc_tok == TOK_MINUS) { gneg = 1; HcLexNext(); }
                            if (g_hc_tok == TOK_FLOAT) { gev = g_hc_tok_val; gflt = 1; HcLexNext(); }
                            else if (g_hc_tok == TOK_NUMBER) { gev = g_hc_tok_val; HcLexNext(); }
                            else if (g_hc_tok == TOK_STRING) { gev = g_hc_tok_val; HcLexNext(); }
                            else break;
                            if (gneg) { if (gflt) gev = gev ^ (1 << 63); else gev = -gev; }
                            HcStoreElem(g_base, gi, gev, g_elem_bytes);
                            gi++;
                            if (g_hc_tok == TOK_COMMA) HcLexNext();
                            else break;
                        }
                        if (g_hc_tok == TOK_RBRACE) HcLexNext();
                    } else {
                    I64 g_neg = 0;
                    if (g_hc_tok == TOK_MINUS) {
                        g_neg = 1;
                        HcLexNext();
                    }
                    if (g_hc_tok == TOK_FLOAT) {
                        // F64 global: store IEEE-754 bits (flip sign bit for a leading '-').
                        I64 gbits = g_hc_tok_val;
                        if (g_neg) gbits = gbits ^ (1 << 63);
                        *(I64*)g_slot = gbits;
                        HcLexNext();
                    } else if (g_hc_tok == TOK_NUMBER) {
                        I64 gv = g_hc_tok_val;
                        if (g_neg) gv = -gv;
                        *(I64*)g_slot = gv;
                        HcLexNext();
                    } else {
                        // Non-literal initializer: defer it to the top-level wrapper,
                        // which evaluates it at runtime and stores into g_slot (matching
                        // the C JIT). Consume the expression to keep the parser in sync.
                        if (g_hc_init_count < HC_MAX_DEFERRED) {
                            g_hc_init_slot[g_hc_init_count] = g_slot;
                            g_hc_init_pos[g_hc_init_count] = g_init_pos;
                            g_hc_init_count++;
                        } else {
                            g_hc_error = 1;
                        }
                        I64 g_skip = 0;
                        while (g_hc_tok != TOK_SEMICOLON && g_hc_tok != TOK_EOF && g_skip < 8192) {
                            HcLexNext();
                            g_skip++;
                        }
                    }
                    } // end non-array initializer
                }
                // D18 root fix: multiple initialized globals in one declaration
                // (`I64 g1 = 5, g2 = 6;`). Preserve the base type across declarators.
                if (g_hc_tok == TOK_COMMA) {
                    HcLexNext();
                    g_is_ptr = 0;
                    while (g_hc_tok == TOK_STAR) { g_is_ptr = 1; HcLexNext(); }
                    continue;
                }
                break;
            }
            if (g_was_fn) continue;
            if (g_decl) { if (g_hc_tok == TOK_SEMICOLON) HcLexNext(); continue; }

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
        HcEmitDeferredInits();
        while (g_hc_tok != TOK_EOF) {
            // A function (or class/struct) definition may follow top-level statements
            // — e.g. boot modules end with `if (g_kernel_booting) {...}` followed by a
            // function. Break so the outer loop parses it as a declaration instead of
            // mis-parsing it as a statement. Global variable declarations are left to
            // HcParseStatement (local semantics) to preserve prior behaviour.
            if (HcAtFunctionDef()) break;
            I64 repl_pp = g_hc_pos;
            HcParseStatement();
            if (g_hc_pos <= repl_pp && g_hc_tok != TOK_EOF) {
                // Same non-advancing-token invariant as block statements: hard error,
                // never an infinite loop.
                g_hc_error = 1;
                HcLexNext();
            }
        }
        // REPL result: the last top-level expression's value must be returned in X0.
        // An F64 result lives in D0, so move its bits across (matches the C JIT).
        if (g_hc_expr_float) HcEmit(0x9E660000); // fmov x0, d0
        HcEmitEpilogue();
        HcFinalizeFrame();
    }

    // If the unit was ONLY declarations with runtime (non-literal) initializers and no
    // trailing statements, the wrapper above was never created. Emit one now so those
    // deferred initializers actually run (matches the C JIT's one-shot unit model).
    if (g_hc_init_count > 0 && g_hc_unit_main == 0) {
        U64 dinit_entry = g_hc_code + g_hc_code_len * 4;
        g_hc_unit_main = dinit_entry;
        g_hc_local_count = 0;
        g_hc_frame_offset = 16;
        g_hc_epi_count = 0;
        HcEmitPrologue();
        HcEmitDeferredInits();
        HcEmitEpilogue();
        HcFinalizeFrame();
    }
}

// ------------------------------------------------------------------------------
// Forward-struct pre-scan. Walks the whole unit once and registers every
// `struct`/`class` definition (names, member offsets, sizes) BEFORE the real parse,
// so a type used before its definition resolves (e.g. `I64 getfx(F *p) {...}`
// preceding `struct F { I64 x; }`). Mirrors the C JIT's prescan_struct_defs.
// The lexer state is saved/restored so the caller's parse position is preserved.
// ------------------------------------------------------------------------------
U0 HcPrescanStructs() {
    I64 sp = g_hc_pos;
    I64 st = g_hc_tok;
    I64 sv = g_hc_tok_val;
    I64 stp = g_hc_tok_pos;
    U8  ss[256];
    HcSafeCopy(ss, g_hc_tok_str, 256);

    g_hc_pos = 0;
    HcLexNext();
    while (g_hc_tok != TOK_EOF) {
        if (g_hc_tok == TOK_STRUCT || g_hc_tok == TOK_CLASS) {
            HcParseStructDef();
        } else {
            HcLexNext();
        }
    }

    g_hc_pos = sp;
    g_hc_tok = st;
    g_hc_tok_val = sv;
    g_hc_tok_pos = stp;
    HcSafeCopy(g_hc_tok_str, ss, 256);
}

// P4.5: pre-register every top-level function's return-floatness BEFORE parsing, so
// a call that appears before its definition in the same unit (and every later unit)
// knows whether the result is an F64 in D0. Scans only at brace-depth 0 so member
// declarations inside class/struct bodies and statements inside function bodies are
// ignored. Lexer state is saved/restored, mirroring HcPrescanStructs.
U0 HcPrescanFuncs() {
    I64 sp = g_hc_pos;
    I64 st = g_hc_tok;
    I64 sv = g_hc_tok_val;
    I64 stp = g_hc_tok_pos;
    U8  ss[256];
    HcSafeCopy(ss, g_hc_tok_str, 256);

    g_hc_pos = 0;
    HcLexNext();
    I64 depth = 0;
    while (g_hc_tok != TOK_EOF) {
        if (g_hc_tok == TOK_LBRACE) { depth++; HcLexNext(); continue; }
        if (g_hc_tok == TOK_RBRACE) { if (depth > 0) depth--; HcLexNext(); continue; }
        if (depth == 0 && HcIsTypeToken(g_hc_tok)) {
            I64 rt_float = (g_hc_tok == TOK_TYPE_F64);
            HcLexNext();
            while (g_hc_tok == TOK_STAR) HcLexNext();
            if (g_hc_tok == TOK_IDENT) {
                U8 pfn[64];
                HcSafeCopy(pfn, g_hc_tok_str, 64);
                HcLexNext();
                if (g_hc_tok == TOK_LPAREN) HcFnFloatSet(pfn, rt_float);
            }
            continue;
        }
        HcLexNext();
    }

    g_hc_pos = sp;
    g_hc_tok = st;
    g_hc_tok_val = sv;
    g_hc_tok_pos = stp;
    HcSafeCopy(g_hc_tok_str, ss, 256);
}

// #include preprocessor expansion. Recursively splices `#include "file"` targets
// (read from the RedSea VFS) into one flat source buffer before lexing, matching
// the C JIT's expand_includes. Returns the expanded length.
I64 HcExpandIncludes(U8 *src, U8 *out, I64 cap, I64 depth) {
    if (depth > 8) return 0;
    I64 si = 0;
    I64 oi = 0;
    while (src[si] != 0 && oi < cap - 1) {
        // A '#' starts a directive ONLY as the first non-whitespace char on its
        // line. This prevents a '#include' that appears inside a string literal
        // (e.g. Compiler.HC's own `strstr(src, "#include")`) from being expanded.
        I64 dir_ok = 0;
        if (src[si] == 35) {
            I64 ls = si;
            while (ls > 0 && src[ls - 1] != 10) ls--;
            dir_ok = 1;
            I64 q = ls;
            while (q < si) {
                if (src[q] != 32 && src[q] != 9) { dir_ok = 0; break; }
                q++;
            }
        }
        if (src[si] == 35 && dir_ok) {
            I64 after = si + 1;
            while (src[after] == 32 || src[after] == 9) after++;
            if (strncmp(src + after, "include", 7) == 0) {
                after = after + 7;
                while (src[after] == 32 || src[after] == 9) after++;
                if (src[after] == 34) {
                    after++;
                    U8 ifn[128];
                    I64 fi = 0;
                    while (src[after] != 0 && src[after] != 34 && fi < 127) {
                        ifn[fi] = src[after];
                        fi++;
                        after++;
                    }
                    ifn[fi] = 0;
                    if (src[after] == 34) after++;
                    U8 *ibuf = kmalloc(HC_SRC_MAX);
                    if (ibuf) {
                        I64 isz = 0;
                        if (redsea_read_file(ifn, ibuf, HC_SRC_MAX - 1, &isz) == 0) {
                            ibuf[isz] = 0;
                            oi = oi + HcExpandIncludes(ibuf, out + oi, cap - oi, depth + 1);
                            // Separate the spliced content from whatever follows on the
                            // same line so tokens never glue together.
                            if (oi < cap - 1) { out[oi] = 10; oi++; }
                        }
                        kfree(ibuf);
                    }
                    // Resume immediately after the closing quote (do NOT skip the rest
                    // of the line) so `#include "f" code;` keeps `code;`.
                    si = after;
                    continue;
                }
            }
        }
        out[oi] = src[si];
        oi++;
        si++;
    }
    out[oi] = 0;
    return oi;
}

// 1-based line number of a source position (for diagnostics).
I64 HcLineOf(I64 pos) {
    I64 ln = 1;
    I64 i = 0;
    while (i < pos && i < g_hc_len) {
        if (g_hc_src[i] == 10) ln++;
        i++;
    }
    return ln;
}

// ------------------------------------------------------------------------------
// Compiler Compile & Run Driver (Persistent Monotonic Code Pool)
// ------------------------------------------------------------------------------
I64 CompilerCompileAndRun(U8 *src) {
    g_fn_parse_expr = &HcParseExpr;
    g_fn_parse_stmt = &HcParseStatement;
    HcInit();
    HcReset();
    g_hc_compiling = 1; // guardrail 1: defer preemption during compilation

    I64 start_idx = g_hc_pool_offset;
    U64 start_addr = g_hc_code + start_idx * 4;

    U8 *use_src = src;
    U8 *exp_buf = 0;
    if (strstr(src, "#include") != 0) {
        exp_buf = kmalloc(HC_EXPAND_MAX);
        if (exp_buf) {
            HcExpandIncludes(src, exp_buf, HC_EXPAND_MAX - 1, 0);
            use_src = exp_buf;
        }
    }

    g_hc_src = use_src;
    g_hc_pos = 0;
    g_hc_len = strlen(use_src);
    HcLexNext(); // Prime lexer

    HcPrescanStructs(); // register forward struct/class definitions first
    HcPrescanFuncs();   // P4.5: register function return-floatness before parsing

    HcParseProgram();

    if (g_hc_error) {
        doldoc_printf("$FG,RED$[COMPILER.HC] internal error at line %lld (pos=%lld locals=%lld funcs=%lld structs=%lld globals=%lld code=%lld)$FG$\n",
                      HcLineOf(g_hc_pos), g_hc_pos, g_hc_local_count, g_hc_func_count, g_hc_struct_count,
                      g_hc_global_count, g_hc_code_len);
        g_hc_pool_offset = start_idx;
        g_hc_compiling = 0;
        if (exp_buf) kfree(exp_buf);
        return -1;
    }

    // P7.0: peephole-optimize the freshly emitted module (NOP-based, index-safe).
    HcOptimizePeephole(start_idx, g_hc_code_len);

    I64 emitted_insns = g_hc_code_len - start_idx;
    g_hc_pool_offset = g_hc_code_len;

    if (emitted_insns > 0) {
        HcFlushCache(start_addr, emitted_insns * 4);
    }

    if (exp_buf) kfree(exp_buf);

    g_hc_compiling = 0; // compile done: preemption may resume for the unit body

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
