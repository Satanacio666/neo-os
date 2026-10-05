// ==============================================================================
// WasmJit.HC - Pure HolyC WebAssembly AArch64 JIT Compiler & Runtime
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Zero External Dependencies: Emits raw 32-bit ARM64 machine instructions
// ==============================================================================

#define WASM_MAGIC   0x6D736100 // "\0asm"
#define WASM_VERSION 0x00000001

#define WASM_SEC_TYPE     1
#define WASM_SEC_IMPORT   2
#define WASM_SEC_FUNCTION 3
#define WASM_SEC_TABLE    4
#define WASM_SEC_MEMORY   5
#define WASM_SEC_GLOBAL   6
#define WASM_SEC_EXPORT   7
#define WASM_SEC_START    8
#define WASM_SEC_ELEMENT  9
#define WASM_SEC_CODE     10
#define WASM_SEC_DATA     11

class WasmJitContext {
    U8  *wasm_bytes;
    I64  wasm_size;
    I64  pc;
    
    U32 *code_buf;
    I64  code_idx;
    
    U8  *linear_mem;
    I64  mem_pages;
};

WasmJitContext g_wasmjit;

U0 WasmEmitA64(WasmJitContext *ctx, U32 insn) {
    ctx->code_buf[ctx->code_idx++] = insn;
}

// Unsigned LEB128 Reader
I64 WasmReadULEB128(WasmJitContext *ctx) {
    I64 result = 0;
    I64 shift = 0;
    while (ctx->pc < ctx->wasm_size) {
        U8 byte = ctx->wasm_bytes[ctx->pc++];
        result = result | ((byte & 0x7F) << shift);
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

// Signed LEB128 Reader
I64 WasmReadSLEB128(WasmJitContext *ctx) {
    I64 result = 0;
    I64 shift = 0;
    U8 byte;
    while (ctx->pc < ctx->wasm_size) {
        byte = ctx->wasm_bytes[ctx->pc++];
        result = result | ((byte & 0x7F) << shift);
        shift += 7;
        if ((byte & 0x80) == 0) break;
    }
    if ((shift < 32) && (byte & 0x40)) {
        result = result | (~0 << shift);
    }
    return result;
}

// ------------------------------------------------------------------------------
// Single-Pass AArch64 Machine Code Generator
// ------------------------------------------------------------------------------
U0 WasmCompileFunctionBody(WasmJitContext *ctx, I64 body_len) {
    I64 end_pc = ctx->pc + body_len;

    // Standard AArch64 Function Prologue: stp x29, x30, [sp, #-16]! ; mov x29, sp
    WasmEmitA64(ctx, 0xA9BF7BFD);
    WasmEmitA64(ctx, 0x910003FD);

    while (ctx->pc < end_pc && ctx->pc < ctx->wasm_size) {
        U8 opcode = ctx->wasm_bytes[ctx->pc++];
        switch (opcode) {
            case 0x01: // nop
                WasmEmitA64(ctx, 0xD503201F);
                break;

            case 0x41: // i32.const <imm>
                {
                    I64 imm = WasmReadSLEB128(ctx);
                    // movz w0, #imm16
                    WasmEmitA64(ctx, 0x52800000 | ((imm & 0xFFFF) << 5));
                    // str w0, [sp, #-16]! (push onto evaluation stack)
                    WasmEmitA64(ctx, 0xB81F0FE0);
                }
                break;

            case 0x20: // local.get <idx>
                {
                    I64 idx = WasmReadULEB128(ctx);
                    // ldr x0, [sp, #(idx * 16)]
                    WasmEmitA64(ctx, 0xF94003E0 | ((idx * 2) << 10));
                    // str x0, [sp, #-16]!
                    WasmEmitA64(ctx, 0xF81F0FE0);
                }
                break;

            case 0x6A: // i32.add
                // ldr w1, [sp], #16 (pop rhs)
                WasmEmitA64(ctx, 0xB84107E1);
                // ldr w0, [sp]      (peek lhs)
                WasmEmitA64(ctx, 0xB94003E0);
                // add w0, w0, w1
                WasmEmitA64(ctx, 0x0B010000);
                // str w0, [sp]      (write back result)
                WasmEmitA64(ctx, 0xB90003E0);
                break;

            case 0x6B: // i32.sub
                WasmEmitA64(ctx, 0xB84107E1);
                WasmEmitA64(ctx, 0xB94003E0);
                // sub w0, w0, w1
                WasmEmitA64(ctx, 0x4B010000);
                WasmEmitA64(ctx, 0xB90003E0);
                break;

            case 0x6C: // i32.mul
                WasmEmitA64(ctx, 0xB84107E1);
                WasmEmitA64(ctx, 0xB94003E0);
                // mul w0, w0, w1
                WasmEmitA64(ctx, 0x1B017C00);
                WasmEmitA64(ctx, 0xB90003E0);
                break;

            case 0x0B: // end
                // ldr x0, [sp], #16 (pop return value into X0)
                WasmEmitA64(ctx, 0xF84107E0);
                // Epilogue: ldp x29, x30, [sp], #16 ; ret
                WasmEmitA64(ctx, 0xA8C17BFD);
                WasmEmitA64(ctx, 0xD65F03C0);
                break;
        }
    }
}

// ------------------------------------------------------------------------------
// Top-Level WebAssembly JIT Compiler Entry Point
// ------------------------------------------------------------------------------
I64 WasmJitRunBytes(U8 *bytes, I64 len) {
    if (!bytes || len < 8) return -1;

    g_wasmjit.wasm_bytes = bytes;
    g_wasmjit.wasm_size  = len;
    g_wasmjit.pc         = 8; // Skip magic & version
    g_wasmjit.code_buf   = kmalloc(65536);
    g_wasmjit.code_idx   = 0;

    doldoc_printf("$FG,CYAN$[WASM-JIT] Compiling WebAssembly module (%lld bytes)...$FG$\n", len);

    while (g_wasmjit.pc < g_wasmjit.wasm_size) {
        U8 sec_id = g_wasmjit.wasm_bytes[g_wasmjit.pc++];
        I64 sec_len = WasmReadULEB128(&g_wasmjit);
        I64 sec_end = g_wasmjit.pc + sec_len;

        if (sec_id == WASM_SEC_CODE) {
            I64 func_count = WasmReadULEB128(&g_wasmjit);
            I64 f;
            for (f = 0; f < func_count; f++) {
                I64 body_len = WasmReadULEB128(&g_wasmjit);
                I64 local_decls = WasmReadULEB128(&g_wasmjit);
                WasmCompileFunctionBody(&g_wasmjit, body_len);
            }
        } else {
            // Skip non-code sections for baseline runner
            g_wasmjit.pc = sec_end;
        }
    }

    doldoc_printf("$FG,GREEN$[WASM-JIT] JIT Compilation complete: %lld ARM64 instructions emitted at %p$FG$\n",
                  g_wasmjit.code_idx, g_wasmjit.code_buf);

    // Call compiled AArch64 machine code directly as a Ring 0 function pointer!
    I64 (*fn)() = g_wasmjit.code_buf;
    I64 ret_val = (*fn)();

    doldoc_printf("$FG,YELLOW$[WASM-JIT] Execution result: %lld$FG$\n", ret_val);
    return ret_val;
}

// Self-Test WebAssembly Binary: Calculates (42 * 2) = 84
U0 WasmSelfTest() {
    U8 test_wasm[32];
    I64 idx = 0;

    // Magic & Version
    test_wasm[idx++] = 0x00; test_wasm[idx++] = 0x61; test_wasm[idx++] = 0x73; test_wasm[idx++] = 0x6D;
    test_wasm[idx++] = 0x01; test_wasm[idx++] = 0x00; test_wasm[idx++] = 0x00; test_wasm[idx++] = 0x00;

    // Section 10: Code Section
    test_wasm[idx++] = 10;   // Section ID
    test_wasm[idx++] = 11;   // Section Length
    test_wasm[idx++] = 1;    // 1 Function
    test_wasm[idx++] = 9;    // Function body size
    test_wasm[idx++] = 0;    // 0 locals

    // Bytecodes: i32.const 42 ; i32.const 2 ; i32.mul ; end
    test_wasm[idx++] = 0x41; test_wasm[idx++] = 42;
    test_wasm[idx++] = 0x41; test_wasm[idx++] = 2;
    test_wasm[idx++] = 0x6C; // i32.mul
    test_wasm[idx++] = 0x0B; // end

    WasmJitRunBytes(test_wasm, idx);
}

WasmSelfTest();
