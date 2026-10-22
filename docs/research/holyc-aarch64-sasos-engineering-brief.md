# Engineering Brief — A Bare-Metal AArch64 HolyC Single-Address-Space OS

**Subject:** concrete, code-level design for a self-hosted HolyC JIT, a symbol table with self-modifying indirect call cells (SIC), a single-pass compiler, a DolDoc-style reactive document tree, a reactive shell, and SDF/TTF text — all in one address space, no MMU protection, no headers.

**Provenance / method.** This brief was assembled by reading the reference implementation at `/home/user/neo-os` (HEAD `77d407f`, "P0.7b: KHEAP split/coalesce regression + pointer-arithmetic audit") in **read-only** mode, plus authoritative external sources. No file in `/home/user/neo-os` was modified. Where the reference implementation already contains a working mechanism, the brief names the file/line and generalizes it; where it is missing (SDF, true O(1) shell dispatch, a document diff), the brief gives a concrete design that fits the existing data structures.

**Reference implementation map (used throughout):**

| Concern | File | Notes |
|---|---|---|
| Stage-2 self-hosting HolyC→AArch64 JIT | `apps/Compiler.HC` (3614 lines) | emits raw AArch64 `U32` words into `g_hc_code` |
| C seed JIT (bootstraps `Compiler.HC`) | `boot/seed/jit_arm64.c` (3965 lines) | SIC resolution at `jit_arm64.c:1041-1084` |
| HolyC symbol table (runtime owner) | `apps/Symbols.HC` (408 lines) | DJB2, 1024 buckets, canonical case-fold |
| Seed symbol table | `boot/runtime/symbols.c` (190 lines) | same hash; `symbols_*` API patched at handover |
| Single-pass lexer (seed) | `boot/seed/lexer.c` (547 lines) | primes first token, `#define` as a `SYM_VAR` |
| DolDoc / document tree | `apps/DolDoc.HC` (2913 lines) | cell grid + widget table + OmniTape + Morton bins |
| Shell / command registry | `apps/Shell.HC` (940 lines) | `CShellCmdEntry g_shell_cmds[32]` + strcmp chain |
| Vector font (pre-SDF) | `apps/FontVector.HC` (448 lines) | analytic quadratic Béziers, no distance field |
| Idle loops | `apps/Sched.HC:348`, `apps/Smp.HC:64`, `boot/main.c:356` | `__wfe` / `wfi` |
| Kernel handover | `apps/KernelInit.HC`, `boot/main.c` | UEFI → seed JIT → `Compiler.HC` |

---

## 0. The foundational model: one address space, a symbol table as the linker, SIC as the ABI

A single-address-space OS (SASOS) removes the distinction between "kernel image", "shared library" and "process image": everything is code/data reachable by one pointer. This is exactly the Smalltalk/LOOM view — *"the Smalltalk reference can only point to an object as a whole… the system can address over a million words"* ([Smalltalk-76 paper](https://smalltalkzoo.computerhistory.org/papers/The%20Smalltalk-76%20Programming%20System.PDF), [LOOM](http://web.cecs.pdx.edu/~black/OOP/papers/Kaehler%20&%20Krasner-LOOM.pdf), [Smalltalk overview](https://web.cecs.pdx.edu/~harry/musings/SmalltalkOverview.html)) — and it is the TempleOS model (no virtual memory, stack does not grow: [HolyC doc](https://tinkeros.github.io/WbTempleOS/Doc/HolyC.html)).

Because there is no loader, no ELF, and no `ld.so`, **the symbol table *is* the dynamic linker**, and **the SIC cell *is* the GOT/PLT slot**. The whole linking strategy reduces to:

1. At compile time, every reference to a not-yet-known symbol emits a *load from a stable cell* (`&sym->address`) and an indirect branch through the loaded value.
2. On first reference, the cell is *reserved* and initialized to a trap (`symbols_unresolved_trap`), or for a variable, to a freshly zeroed 8-byte cell.
3. When the symbol is finally defined, the cell's value is *overwritten in place* (hot-patched) under a `dmb ish`. No relocation pass, no fixups, no stop-the-world.

This is the lazy-binding idea stripped to its essence. ELF's PLT is *"a level of indirection… the `.got.plt` entry initially refers to the resolver; after resolution the entry holds the actual function address"* ([MaskRay, All about PLT](https://maskray.me/blog/all-about-procedure-linkage-table)). SIC is the same, except the resolver is simply "whoever defines the symbol first", and binding is eager-per-symbol at definition rather than lazy-per-call.

---

## 1. Self-hosted JIT + symbol resolution

### 1.1 The SIC cell — model and AArch64 encoding

A **SIC cell** is an 8-byte word in the symbol table entry that holds the *live entry address* of a function (or the address of a variable). Callers never branch to a symbol directly; they branch through the cell.

The reference emits a direct-call sequence in `apps/Compiler.HC:1697-1750`:

```
// ident(args...) where ident is not a local and not a variable:
U64 sic = symbols_sic_cell(ident_name);   // == (U64)&sym->address
...
HcEmitImm64(16, target);      // movz/movk x16, &sym->address   (a 64-bit constant)
HcEmitLoadSized(16, 16, 8);   // ldr x16, [x16]                 (x16 = sym->address)
HcEmit(0xD63F0200);           // blr x16                        (call through the cell)
```

`HcEmitImm64` (`Compiler.HC:699`) emits `MOVZ` + up to three `MOVK`:

```
movz x16, #imm0, lsl #0      ; 0xD2800000 | (0<<21) | (imm0<<5) | 16
movk x16, #imm1, lsl #16     ; 0xF2A00000 | (1<<21) | (imm1<<5) | 16
movk x16, #imm2, lsl #32     ; 0xF2C00000 | (2<<21) | ...
movk x16, #imm3, lsl #48     ; 0xF2E00000 | (3<<21) | ...
```

The seed JIT is byte-for-byte equivalent (`jit_arm64.c:194-216` for `emit_mov_imm64`, `jit_arm64.c:256` for `emit_ldr_ptr`, `jit_arm64.c:414` for `emit_blr`).

**Cost:** 2–5 instructions for the constant (typically 3 on a 48-bit user VA), 1 `ldr`, 1 `blr`. This is exactly the `-fno-plt` AArch64 shape MaskRay describes:

```
adrp x0, _GLOBAL_OFFSET_TABLE_
ldr  x0, [x0, #:gotpage_lo15:bar]
br   x0
```

**Optimization (recommended):** if all code and all SIC cells live within ±4 GiB of each other (true in a 4 GiB SASOS image or a fixed-offset arena), replace `MOVZ/MOVK + ldr + blr` with `ADRP + ADD + ldr + blr` (4 instructions, no constant pool) or even `ADRP + ldr + blr` when the cell is the page base. `ADRP` forms a 4 KiB-page-relative address: `imm = SignExtend(immhi:immlo:Zeros(12))`, range ±4 GiB, and `base = PC<63:12>:Zeros(12)` ([ARM ADRP](https://www.scs.stanford.edu/~zyedidia/arm64/adrp.html), [ADR/ADRP demos](https://duetorun.com/blog/20230609/arm-adr-demo)). The canonical pair is:

```
adrp x16, page(&sym->address)     ; :pg_hi21:
add  x16, x16, :lo12:&sym->address
ldr  x16, [x16]
blr  x16
```

**Call-site invariants (AAPCS64):** arguments in `x0..x7` (integers/pointers) and `d0..d7`/`s0..s7` (FP). `x16`/`x17` are the intra-procedure-call scratch registers — deliberately chosen here because the linker/PLT convention reserves them for exactly this indirection (`x16` holds the GOT-entry address, `x17` the target, in the standard AArch64 PLT header). The reference refuses >8 args (`Compiler.HC:1724`) rather than spilling to the stack; a real system should implement the stack-arg spill or document the limit.

**Self-modification is *not* needed for the common case.** The SIC design is "indirect call through a data cell", not "rewrite the branch instruction". That is a feature: it is cache-coherent with ordinary data stores, needs no I-cache invalidation on redefinition, and is safe under SMP (single aligned 8-byte store is atomic on AArch64). Only when you additionally want *PLT rewriting* (turn `ldr;blr` into a direct `bl` after binding, as glibc 2.39 does for x86) do you enter true self-modifying code territory, with its I-cache/`ic ivau` hazards.

### 1.2 Symbol table: hashing, buckets, hot-patching

The runtime table (`apps/Symbols.HC`) is a classic separate-chaining hash table:

```hc
#define SYM_FUNC     1
#define SYM_VAR      2
#define SYM_HARDWARE 3
#define SYM_HASH_BUCKETS 1024

class CSymbol {
  U8       name[64];
  U64      address;
  I64      type;
  U32      hash;
  CSymbol *next;
};
CSymbol *g_sym_buckets[1024];
U64      g_sym_total_count;
```

`SymRegister` (`Symbols.HC:158`) walks the bucket, and on a name hit **updates in place** (`curr->address = address; __dmb_ish();`) instead of inserting a duplicate — this is the "hot-patch" that makes forward references resolve. On a miss it `kmalloc`s a record and pushes it to the bucket head. `SymLookupEntry` (`:192`) is the O(1) average lookup.

**Hash choice — DJB2 vs FNV-1a.** The reference uses DJB2 (`hash = hash*33 + c`, seed 5381) in *both* the HolyC table and the seed (`symbols.c:11`). Both are fine for a symbol table; independent measurements put them within a few percent of each other, with FNV-1a typically slightly better distributed ([Aras, hash function tests](https://aras-p.info/blog/2016/08/09/More-Hash-Function-Tests/), [FNV vs DJB2](https://mojoauth.com/security-guides/fnv-1a-vs-bernsteins-hash-djb2)).

If you want FNV-1a (recommended for a new table), the constants are exact and standardized ([isthe.com FNV](https://www.isthe.com/chongo/tech/comp/fnv), [FNV-1a in C](https://mojoauth.com/security-guides/fnv-1a-in-c)):

```hc
// FNV-1a 64-bit
#define FNV_OFFSET64 0xCBF29CE484222325
#define FNV_PRIME64  0x00000100000001B3

U32 SymHashFnv(U8 *s) {
  U64 h = FNV_OFFSET64;
  I64 i = 0;
  while (s[i]) { h = (h ^ s[i]) * FNV_PRIME64; i++; }   // 64-bit wraparound
  return (U32)(h & (SYM_HASH_BUCKETS - 1));             // power-of-two mask
}
```

Note the reference's DJB2 returns `hash & (BUCKETS-1)` (`Symbols.HC:142`) while the seed uses `hash % BUCKETS` (`symbols.c:17`). Both are correct for a power-of-two bucket count; the mask is one instruction cheaper and is the right choice.

**Pitfalls observed in the reference (worth designing around):**

- **Canonical-name fallback is O(n).** `SymLookupCanonical` (`Symbols.HC:274`) first does an exact O(1) hit; only on miss does it linearly scan all 1024 buckets comparing case-insensitively and underscore-agnostically (`hal_flush_cache` ↔ `HalFlushCache`). Keep the fast path exact and make the canonical path a *debug/interop* affordance, or normalize the key at registration time (store both a canonical key and the display name) so the canonical lookup is also O(1).
- **Two tables during boot.** The C seed table and the HolyC table coexist until `SymbolsHandover` (`Symbols.HC:259`) patches `symbols_lookup/is_defined/is_func/is_var/var_cell/sic_cell/register` to point at the HolyC implementations and then ingests every seed symbol. Order matters: patch the six readers *first*, ingest *second*, patch `symbols_register` *last*, so the ingest still reaches the seed table. This "sovereign handover" is a clean pattern for replacing any boot-time subsystem with its self-hosted successor.
- **Trap-as-undefined sentinel.** A reserved forward reference's address is `&SymUnresolvedTrap` (`Symbols.HC:217`). `SymIsDefined`/`SymIsFunc` treat that exact address as "not defined" (`:225-238`), which is what lets a later real definition overwrite it. Use a single canonical trap function so the sentinel is one comparison.

**Forward-reference reservation** (`symbols.c:128`):

```c
symbol_t* symbols_lookup_or_reserve(const char *name, symbol_type_t default_type) {
    symbol_t *existing = symbols_lookup_entry(name);
    if (existing) return existing;
    if (default_type == SYM_VAR) {
        int64_t *cell = kmalloc(sizeof(int64_t));   // real zeroed storage
        if (cell) *cell = 0;
        symbols_register(name, cell, SYM_VAR);      // reads before definition see 0
    } else {
        symbols_register(name, symbols_unresolved_trap, default_type);  // SIC cell
    }
    return symbols_lookup_entry(name);
}
```

Two distinct semantics, both correct:
- **Forward variable** → a real cell, so `I64 b = a + 4;` compiled before `a` is defined still reads a live (zero) value that the later definition fills in.
- **Forward function** → a SIC cell pointing at the trap, so an early `foo()` call is a no-op until `foo` is defined, then becomes the real call with **zero recompilation**.

### 1.3 Self-hosting a compiler that compiles itself

The boot chain (from `boot/main.c` and `KernelInit.HC`) is:

```
UEFI firmware
  └─ BOOTAA64.EFI  (boot/main.c)
       └─ reads holyc/KernelInit.HC from the ESP
            └─ C seed JIT (boot/seed/jit_arm64.c) compiles ONLY Compiler.HC   [P2.7]
                 └─ Compiler.HC compiles everything else, including itself
```

The reference's own commit history marks the milestone: `1e7f3f8 P2.7 COMPLETE: compiler-only bootstrap (C JIT compiles only Compiler.HC)`.

**Self-hosting safety — the one rule that matters.** When `Compiler.HC` compiles *itself*, the compiler's own functions (`HcEmit`, `HcParseExpr`, …) are live in the symbol table. If the newly compiled definitions blindly registered over them, a forward call inside the *running* compiler would jump into half-emitted code. The reference guards this in `HcPublishFunc` (`Compiler.HC:654`):

```hc
U0 HcPublishFunc(U8 *name, U64 addr) {
    if (!symbols_is_defined(name) || !symbols_is_func(name)) {
        symbols_register(name, addr, 1);   // only overwrite a leak/forward cell
    }
}
```

`symbols_is_func` returns false for a leaked `SYM_VAR` cell, so a REPL function named like a stray global *may* override it, but a real running function may not be clobbered. This is the crucial asymmetry: **never let self-compilation clobber a live function.**

**Publish-before-body.** `HcParseFunction` (`Compiler.HC:2958`) registers the function's entry address *before* emitting its body:

```hc
U0 HcParseFunction(U8 *func_name) {
    U64 fn_entry = g_hc_code + g_hc_code_len * 4;
    HcAddFunc(func_name, fn_entry);      // publish FIRST → recursion & mutual refs work
    if (strcmp(func_name, "Main") == 0) g_hc_unit_main = fn_entry;
    ...
    HcEmitPrologue();
    ... parse params, body ...
    HcEmitEpilogue();
    HcFinalizeFrame();                   // patch frame size in prologue+epilogues
}
```

This is the single-pass trick that replaces a whole fixup pass: the callee's address is known the moment its body starts, so a recursive or self-referential call resolves immediately; *forward* references to functions not yet seen fall back to SIC cells.

**Cache coherency after emitting code** (`Compiler.HC:425`):

```hc
U0 HcFlushCache(U64 addr, U64 size) {
    U64 p = addr & ~63, end = addr + size + 64;
    while (p < end) { __dc_civac(p); __ic_ivau(p); p += 64; }  // clean D→PoC, invalidate I
    __dsb_sy();
    __isb();
}
```

`dc civac` cleans the data cache to the point of coherency; `ic ivau` invalidates the instruction cache to PoU; `dsb sy` orders them; `isb` synchronizes the pipeline. This must run on **every core that will execute the code**, or use `ic ivau` with broadcast (`ic ivau` is already local; for SMP you need an `IC IALLU`/TLBI-style broadcast or an IPI). The seed uses `__asm__ volatile("dmb ish")` on symbol writes (`symbols.c:81,102`) and the HolyC side uses `__dmb_ish` (`Symbols.HC:170,187`).

### 1.4 Single-pass code emission & backpatching

Because the target address of a branch is often unknown when the branch is emitted, the compiler emits a placeholder and patches it once the target is known. AArch64 branch immediates are **word-relative, not byte-relative**:

```hc
// B: 0x14000000 | (imm26), target = PC + SignExtend(imm26:00)
U0 HcBackpatchB(I64 patch_idx, I64 target_idx) {
    I64 diff = target_idx - patch_idx;                 // in INSTRUCTIONS (indices)
    g_hc_code[patch_idx] = 0x14000000 | (diff & 0x03FFFFFF);
}
// CBZ: 0xB4000000 | (imm19<<5) | Rt
U0 HcBackpatchCbz(I64 patch_idx, I64 target_idx) {
    I64 diff = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0xB4000000 | ((diff & 0x7FFFF) << 5);
}
// CBNZ: 0xB5000000 | (imm19<<5) | Rt
U0 HcBackpatchCbnz(I64 patch_idx, I64 target_idx) {
    I64 rel = target_idx - patch_idx;
    g_hc_code[patch_idx] = 0xB5000000 | ((rel & 0x7FFFF) << 5);
}
```

(`Compiler.HC:813-832`.) Branch range is ±1 MiB for `B`/`B.cond` (`imm26` × 4 B = ±128 MiB for `B`, ±1 MiB for `CBZ`/`CBNZ` via `imm19`). A single function larger than ~1 MiB of code will overflow `CBZ`; plan range-extension thunks (trampolines) or require `B` + test for far targets.

**Frame-size backpatching.** `HcEmitPrologue` reserves a slot for `sub sp, sp, #frame_sz` and `HcEmitEpilogue` records a patch slot for `add sp, sp, #frame_sz`; `HcFinalizeFrame` (`Compiler.HC:797`) writes the real size once the local count is known:

```hc
U0 HcFinalizeFrame() {
    I64 frame_sz = (g_hc_frame_offset + 15) & (~15);   // 16-byte aligned
    if (frame_sz < 64) frame_sz = 64;
    if (frame_sz > 4080) { frame_sz = 4080; g_hc_error = 1; }  // imm12<<12 max
    g_hc_code[g_hc_pro_sub_idx] = 0xD10003FF | ((frame_sz & 0xFFF) << 10);  // sub sp,sp,#imm
    for (...) g_hc_code[ep] = 0x910003FF | ((frame_sz & 0xFFF) << 10);      // add sp,sp,#imm
}
```

**Loop/switch break/continue** are managed with bounded patch stacks: 16 nesting levels × 32 patches per level (`g_hc_brk_stack[512]`, `g_hc_cont_stack[512]`, `Compiler.HC:216-222`). Each `break` pushes a patch index; the loop exit drains the stack and backpatches `B`. This is the standard single-pass technique (see [One-pass Compiler Primer](https://keleshev.com/one-pass-compiler-primer)).

### 1.5 JIT pitfalls checklist

| Pitfall | Why it bites | Mitigation |
|---|---|---|
| **Branch range** | `CBZ`/`CBNZ` ±1 MiB, `B` ±128 MiB | range-extension thunks; or emit `B.cond` inverted + `B` |
| **Constant cost** | 64-bit address = up to 4 `MOVK` | keep code and SIC cells in one ±4 GiB window, use `ADRP+ADD` |
| **I-cache staleness** | freshly written words may execute as garbage | `dc civac` + `ic ivau` + `dsb sy` + `isb`, per core |
| **SMP patching races** | a core may read a half-written SIC cell | single aligned 8-byte store is atomic; pair with `dmb ish`; publish-before-body ordering |
| **Non-reentrant compiler state** | the whole compiler uses globals (`g_hc_*`) | the reference sets `g_hc_compiling=1` and the scheduler defers preemption while compiling (`Compiler.HC:111-114`) |
| **Self-clobber** | recompiling a function the running compiler uses | `HcPublishFunc` guard (`Compiler.HC:654`) |
| **Code buffer overflow** | `g_hc_code` is fixed at `HC_CODE_CAPACITY` (1 Mi instructions) | bounds-check every emit; fail the unit cleanly (`Compiler.HC:695`) |
| **String-literal lifetime** | emitted code holds raw pointers to literals | dedicated bump arena that persists across units (`Compiler.HC:126-141`) |
| **>8 args** | AAPCS64 needs stack spill | implement spill or hard-error (reference hard-errors) |
| **Return in D0 vs X0** | F64-returning functions use `d0` | track per-function float-ness (`g_hc_func_ret_float`, `HcFuncIsFloat`) |

---

## 2. Chibicc/SubC-style single-pass compiler

### 2.1 The chibicc pipeline vs the no-AST pipeline

chibicc's documented stages are Tokenize → Preprocess → Parse (recursive descent, builds AST + types) → Codegen ([chibicc README](https://github.com/rui314/chibicc), [DeepWiki architecture](https://deepwiki.com/rui314/chibicc/2-compiler-architecture)). SubC is explicitly a *one-pass* compiler for a strict C subset that self-hosts ([SubC README](https://www.t3x.org/subc/README-book.html), [minux/subc](https://github.com/minux/subc)). TCC is the classic "single-pass, small and fast" compiler ([OSDev TCC](https://wiki.osdev.org/TCC)).

The reference (`Compiler.HC` + `boot/seed/lexer.c`) is even more radical than SubC: it has **no AST and no IR**. It is a recursive-descent parser whose action is *immediate AArch64 emission*. Expressions are evaluated onto a value stack in registers (`x0`/`d0`) plus an explicit **operator stack** (`g_hc_op_stack[4096]`, `Compiler.HC:230`) for pending patch indices.

This "parse-to-emit" works because HolyC is expression-oriented and the target is a simple stack-machine-shaped codegen: parse a primary into `x0`, push, parse the next, pop, emit the binary op. No tree is ever materialized, so there is nothing to free and nothing to walk twice.

### 2.2 Token representation without per-token heap allocation

The seed lexer returns tokens **by value**:

```c
token_t lexer_next(lexer_t *l);   // boot/seed/lexer.c:136
token_t lexer_peek(lexer_t *l);   // returns l->current
```

There is no token list; the parser pulls one token ahead (LL(1) with a peek). `lexer_init` primes the first token (`lexer.c:26-32`). The HolyC compiler is even simpler: it stores the current token in globals `g_hc_tok`, `g_hc_tok_val`, `g_hc_tok_str[256]` (`Compiler.HC:121-124`) and advances with `HcLexNext()`. **Zero heap allocation per token.**

This is the key design rule: *the lexer must not allocate.* A token is a fixed-size POD record (type, line, col, integer value, small inline string buffer). Identifiers longer than the inline buffer are either rejected or interned into an arena.

The one place the seed lexer *does* allocate is `#define` (it stores the value in a `kmalloc`'d `int64_t` and registers it as a `SYM_VAR`, `lexer.c:213-218`). That is a deliberate design choice — macros live in the symbol table, not a separate preprocessor — but it is a heap allocation per macro. For a fully allocation-free lexer, keep a fixed `#define` table.

### 2.3 Bump-allocated arenas

Arena/bump allocation is the canonical compiler technique: linearly increment a pointer; free everything at once ([Writing an OS in Rust — allocator designs](https://os.phil-opp.com/allocator-designs), [arena-based allocation in compilers](https://medium.com/@inferara/arena-based-allocation-in-compilers-b96cce4dc9ac)).

The reference uses this for **string literals** (`Compiler.HC:126-141, 341-383`):

```hc
#define HC_STR_CHUNK      262144     // 256 KiB chunks
#define HC_STR_MAX_CHUNKS 64
U8    g_hc_str_arena0[HC_STR_CHUNK]; // first chunk in BSS: no allocator needed at boot
U8   *g_hc_str_chunks[HC_STR_MAX_CHUNKS];
I64   g_hc_str_nchunks, g_hc_str_off, g_hc_str_bytes;

U8* HcStrAlloc(I64 n) {
    n = (n + 7) & ~7;                          // 8-byte align
    if (n > HC_STR_CHUNK) { g_hc_error = 1; return 0; }
    if (g_hc_str_off + n > HC_STR_CHUNK) {     // need a new chunk
        if (g_hc_str_nchunks >= HC_STR_MAX_CHUNKS) { g_hc_error = 1; return 0; }
        U8 *chunk = kmalloc(HC_STR_CHUNK);      // allocator only after BSS chunk fills
        if (!chunk) { g_hc_error = 1; return 0; }
        g_hc_str_chunks[g_hc_str_nchunks++] = chunk;
        g_hc_str_off = 0;
    }
    U8 *p = g_hc_str_chunks[g_hc_str_nchunks - 1] + g_hc_str_off;
    g_hc_str_off += n; g_hc_str_bytes += n;
    return p;                                  // NEVER freed: emitted code points at it
}
```

Three properties worth copying:
1. **BSS first chunk** → lexing has no allocator dependency during the fragile boot window.
2. **Bounded failure** → an over-long literal sets `g_hc_error` and aborts the unit instead of corrupting memory.
3. **Persistent lifetime** → strings are never freed because emitted machine code embeds their addresses. This is the single most important arena-lifetime decision in a JIT: *the arena must outlive the compiled code that references it.*

The reference commit `0a53886 P0.7: fix silent module truncation + lexer string arena + allocator hardening` shows this was a real bug fix (individual `kmalloc(slen+1)` per literal leaked and fragmented the heap).

### 2.4 Parse-to-emit expression handling

Binary operators are handled by parsing the left operand into `x0`, pushing it, parsing the right operand, popping the left into `x1`, and emitting the operation. The operator stack (`g_hc_op_stack`) carries *patch indices and nesting state* rather than values, because codegen is register-directed:

```hc
U0 HcOpPush(I64 val) {
    if (g_hc_op_sp < 0 || g_hc_op_sp >= HC_OP_STACK) { g_hc_error = 1; return; }
    g_hc_op_stack[g_hc_op_sp++] = val;
}
I64 HcOpPop() {
    if (g_hc_op_sp <= 0) { g_hc_error = 1; return 0; }
    return g_hc_op_stack[--g_hc_op_sp];
}
```

The reference uses this stack to remember, e.g., the target SIC cell across argument parsing (`HcOpPush(sic)` at `:1704`, `HcOpPop()` at `:1745`) and to nest `break`/`continue` patch bookkeeping.

**Backtracking without an AST.** One subtlety: an identifier statement can be an assignment, a compound assignment, or a call. The reference *speculatively* tries the lvalue path, and if the next token is not an assign-op, it **restores the entire lexer + code-buffer state** and re-parses as an expression (`Compiler.HC:2910-2945`):

```hc
if (g_hc_tok == TOK_IDENT) {
    I64 save_p = g_hc_pos, save_t = g_hc_tok, save_v = g_hc_tok_val;
    I64 save_code = g_hc_code_len;
    U8  save_s[256]; HcSafeCopy(save_s, g_hc_tok_str, 256);
    ... try lvalue ...
    g_hc_pos = save_p; g_hc_tok = save_t; g_hc_tok_val = save_v;
    g_hc_code_len = save_code; HcSafeCopy(g_hc_tok_str, save_s, 256);
    HcParseExpr();
}
```

This is a mini two-token lookahead done by checkpoint/rollback. It works only because the compiler's entire mutable state is a handful of globals — another reason the "no per-token heap, global parser state" design is coherent.

### 2.5 Single-pass pitfalls

- **No type checking.** HolyC has none ([HolyC doc](https://tinkeros.github.io/WbTempleOS/Doc/HolyC.html), [design analysis](https://harrisontotty.github.io/p/a-lang-design-analysis-of-holyc)); the reference tracks just enough (float-ness, struct index, scale) to emit correct loads/stores. Every unhandled type combination is a silent miscompile, so *scale/float/struct* metadata must be threaded explicitly.
- **Pointer arithmetic is byte-based** (see §3) — a single-pass emitter must multiply explicitly on `[]` and *never* on `+`.
- **Backtracking cost** — checkpoint/rollback is O(size of state); keep state small (as above).
- **Arena exhaustion** — always bounds-check and set an error flag; never write through NULL.
- **Register allocation** — there is essentially none (a value stack in `x0`/`x1`, args in `x0..x7`). If you later want optimization, *linear-scan* allocation is the only algorithm compatible with single-pass, since it "allocates in one pass, code can be generated simultaneously" ([Poletto & Sarkar, Linear Scan](https://web.cs.ucla.edu/~palsberg/course/cs132/linearscan.pdf)).

---

## 3. TempleOS / HolyC idioms and gotchas

Authoritative sources: the [HolyC reference page](https://tinkeros.github.io/WbTempleOS/Doc/HolyC.html), the [HolyC design analysis](https://harrisontotty.github.io/p/a-lang-design-analysis-of-holyc), the [DolDoc overview](https://tinkeros.github.io/WbTempleOS/Doc/DolDocOverview.html), [TempleOS on Wikipedia](https://en.wikipedia.org/wiki/TempleOS), and [A Constructive Look at TempleOS](http://www.codersnotes.com/notes/a-constructive-look-at-templeos).

### 3.1 Types and values

- Types: `U0, I8, U8, I16, U16, I32, U32, I64, U64, F64`. `U0` is `void` **but zero-sized**. `F64` is the only float; there is no `F32` at source level.
- **All values are extended to 64-bit when accessed; intermediate calculations are 64-bit.** `j1 = i1 = 0x12345678` stores `0x5678` into an `I16` but `0x12345678` into an `I32` (documented example). A codegen that assumes 32-bit arithmetic will be wrong.
- `sizeof` and `offset(class.member)` accept only one level of member access.

### 3.2 Pointer arithmetic is BYTE-based; only `[]` scales

This is the single most important HolyC gotcha, and it is why the reference commit `77d407f` is titled a "pointer-arithmetic audit."

- In C, `p + 1` advances by `sizeof(*p)`. **In HolyC it advances by 1 byte.**
- Only the subscript operator `[]` scales by the element size.

Terry's own explanation (from the compiler masterclass transcript surfaced in research): pointer arithmetic being "size one" was a deliberate early simplification — *"my original compiler did not do all pointer arithmetic was size one i really i kind of liked it"* — and C-style scaling was later added only for `[]`.

The reference encodes this explicitly. The seed JIT's array indexing (`jit_arm64.c:1085-1144`) multiplies the index by the element scale only inside `[ ]`:

```c
// ident[index]:
int scale = vt ? vt->scale : 1;
if (scale == 8) { emit_mov_imm64(cb,2,8); emit_mul(cb,0,0,2); emit_add(cb,0,1,0); emit_ldr64(cb,0,0); }
else if (scale == 4) { ... emit_mul(cb,0,0,2); ... emit_ldr32 ... }
else if (scale == 2) { ... emit_ldrh ... }
else { emit_add(cb,0,1,0); emit_ldrb(cb,0,0); }        // scale 1: no multiply
```

and the HolyC compiler does the same (`Compiler.HC:1502-1576`, "array cell -> base address"). The byte-based rule means:
- `*(U8*)p` and `*p` for a `U8*` are the same;
- `p[i]` for an `I64*` is `*(I64*)((U8*)p + i*8)` — you must know the scale;
- `&p[i]` must emit `add base, index*scale`, never `add base, index`.

**Design consequence:** the compiler must carry a *scale* for every lvalue (`g_hc_local_scales`, `g_hc_global_elem_scale`, `g_hc_member_sizes` in `Compiler.HC:157-213`). A missing scale is a silent off-by-N. This is exactly why a "pointer arithmetic audit" was a standalone work item.

### 3.3 `class` structs, no headers, no `typedef`

- `typedef` is replaced by `class`; a class can have a base type and a single base class.
- **No headers.** TempleOS compiles whole `.HC` files; there is no include-guard/predeclaration culture. The reference implements `#include` by *splicing* files into one buffer before lexing (`HcExpandIncludes`, `Compiler.HC:3456-3462`), with a 2 MiB expansion cap (`HC_EXPAND_MAX`).
- `union` is class-like; a type in front of a union declaration is the type when used alone.
- Member metadata (format/data) is compiler-visible; `DocForm` uses it to auto-build forms.
- `U0` functions with no args (or all-default args) can be called as `Dir;` without parentheses.

The reference's struct registry persists **across modules** on purpose (`Compiler.HC:201-214`, and `HcReset` explicitly does *not* clear the struct table, `:410-412`) so a struct defined in `Math3D.HC` resolves in `HolyGL.HC`.

### 3.4 `#define` persistence across modules

TempleOS itself has **no `#define`** ("I'm not a fan") and no `#define` functions. But a *persistent macro* is enormously useful in a REPL, and the reference deliberately implements `#define` as a **module-persistent integer macro table** (`Compiler.HC:185-189`):

```hc
#define HC_MAX_DEFINES 1024
U8    g_hc_def_names[HC_MAX_DEFINES * 64];
I64   g_hc_def_vals[HC_MAX_DEFINES];
I64   g_hc_def_count;
```

Crucially, `HcReset` (run before each compilation unit) **does not reset `g_hc_def_count`**:

> `NOTE: the #define table (g_hc_def_count) is intentionally NOT reset: macros must persist across compilation units, exactly as the C JIT's #defines do (it registers them as SYM_VAR). This is what lets a macro defined in one REPL command be used by the next.` (`Compiler.HC:414-417`)

The seed lexer instead registers each macro as a `SYM_VAR` in the symbol table (`lexer.c:213-218`), so a macro is literally a named constant cell. Either approach yields **module-persistent macros** — a defining feature of the shell/REPL experience. The pitfall is unbounded growth: cap the table (1024) and error rather than silently dropping.

### 3.5 `asm {}` blocks

HolyC allows `asm { ... }` inline, using *nonstandard* opcodes (TempleOS splits ambiguous forms, e.g. `IMUL`/`IMUL2`, and "will not report certain invalid forms"). Labels use `::`. `$` refers to the instruction's address or a class offset. In the reference, the AArch64 analog is the intrinsic path (`HcEmitIntrinsic`, `Compiler.HC:2157-2169`): `__wfe` → `0xD503205F`, `__sev`, `__dmb_ish`, etc. For a real `asm{}` on AArch64 you would:

1. Lex the block as raw tokens (skip normal expression parsing).
2. Map a small, explicitly-enumerated mnemonic set to encoders (like the seed's `emit_*` family).
3. Resolve `&label` through the symbol/SIC mechanism.
4. Emit into the same `g_hc_code` pool, then `HcFlushCache`.

The seed JIT is effectively a hand-written assembler already (`emit_add`, `emit_sub`, `emit_mul`, `emit_sdiv`, `emit_srem` = `sdiv`+`msub`, `emit_cset` = `csinc` with inverted cond, `emit_fadd`…). Reuse it.

### 3.6 How the real DolDoc document model works

DolDoc is "somewhere between RTF and HTML": commands are bracketed by `$…$`, and the document is a **list of entries** (not a byte string) after compilation ([DolDoc overview](https://tinkeros.github.io/WbTempleOS/Doc/DolDocOverview.html), [Constructive Look](http://www.codersnotes.com/notes/a-constructive-look-at-templeos)). The grammar:

```
<DolDocCmd> := $<TwoLetterCmd>[<FlagList>][,<ArgList>]$ | $ColorName$
<FlagList>  := +/- <FlagCode> [<FlagList>]
<ArgList>   := <ArgCode>=<ArgExpression> [,<ArgList>]
```

Representative commands and flags (verbatim from the overview):

- **Structure/layout:** `TX` (text), `CR` (hard newline), `SR` (soft newline), `CU` (cursor pos), `CL` (clear, honoring `+H` hold), `PB`, `PL`, `LM`, `RM`, `HD`, `FO`, `ID` (indent), `CM` (cursor movement with `+LX/+CX/+RX/+MRX/+TY/+CY/+BY/+PRY`).
- **Text attributes:** `FD/BD/FG/BG` colors, `PT` (prompt), `WW`, `UL`, `IV`, `BK`, `SX`/`SY` (pixel shift), `HL` (highlight).
- **Interactive:** `AN` (anchor), `LK` (link), `BT` (button), `DA` (data field), `CB` (checkbox), `LS` (list widget), `MA` (macro), `MU` (menu value), `HX` (hex edit), `TR` (tree), `SP` (sprite), `IB`/`IS` (insert binary), `SO` (song), `HC` (html), `ER` (error).
- **Flags:** `+H` hold, `+L` link, `+TR` tree, `+LS` list, `+PU` popup, `+C` collapsed, `+X`/`+Q` exit/quit, `+Z` zero, `+RD` refresh data, `+UD` update data, `+TC`/`+LC`/`+RC` callbacks.
- **Args:** `T=` tag, `LEN=` field length, `A=` aux string, `D=` define string, `HTML=`, `LE=`/`RE=` expressions, `LM=`/`RM=` macro strings, `BI=`/`BP=` binary, `RT=` raw type, `SX=`/`SY=` shift, `SCX=` scroll, `U=` user data.

The critical architectural point: **the same document format underlies the shell, the text editor, forms, menus, images and 3D models.** A macro (`$MA,...,LM="…"$`) is a hyperlink that runs code; a data field (`$DA...,A="…"$`) binds a widget to a memory address; a sprite (`$SP,BI=n$`) embeds binary. "If you want to build a menu or launcher, you just make a new text document and put links in it." This is the Oberon-like collapse of text/program/menu/form into one model ([Constructive Look](http://www.codersnotes.com/notes/a-constructive-look-at-templeos)).

The reference re-implements a modern subset as dollar tags (`$CARD,…$`, `$BOX,…$`, `$SHADER,type="plasma",w=…$`, `$BT,"x",LM="run Y.HC"$`, `$SL,…$`, `$FG,CYAN$`) parsed by `DolDocPrint` (`DolDoc.HC:1555`) and rendered into a widget table. It is the right direction but stops short of a true entry list with diffing — which §4 addresses.

### 3.7 Other HolyC gotchas worth encoding in the compiler

- No `main()` required; top-level statements run in order — which is what lets HolyC be the shell. The reference compiles a synthetic `Main` wrapper (`g_hc_unit_main`) around deferred top-level initializers (`Compiler.HC:3019-3023`).
- No `continue`; use `goto`. (The reference *does* implement `continue`; if you follow TempleOS, drop it.)
- No bit-fields; use byte/word access on unions.
- Chained comparisons `5 < i < j+1 < 20` are legal and short-circuit.
- `switch` always uses a jump table; `switch[]` is unchecked and faster; implicit cases and ranges (`case 4...8:`) exist; `start:`/`end:` create `sub_switch` blocks.
- Single quotes can hold multiple characters (`'ABC'` = `0x434241`).
- A bare char const goes to `PutChars`; a bare string goes to `Print`.
- `#exe{}` splices the output of a program into the compile stream at compile time — the macro system.

---

## 4. DOLDOC 3.0 — a reactive document tree

### 4.1 What to borrow from React/Figma/Smalltalk

- **React reconciliation** is the canonical reactive-tree diff. Its complexity is O(n) only because of two heuristics: (1) elements of different types produce different trees (replace, don't recurse); (2) stable identity is provided by `key` ([React reconciliation docs](https://legacy.reactjs.org/docs/reconciliation.html), [diffing algorithm walkthrough](https://github.com/tigerabrodi/react-virtual-dom-diffing-algorithm)). React does **not** do a general tree-edit-distance (that is O(n³)); it diffs same-level children only, and remounts a child that moves to a different parent.
- **Figma/Smalltalk** are *retained-mode object graphs*: the document is a mutable tree of nodes with identity; changes are propagated to dependent nodes. Smalltalk's object memory is a flat, pointer-based heap in one address space, which is precisely the SASOS model ([Smalltalk overview](https://web.cecs.pdx.edu/~harry/musings/SmalltalkOverview.html)).
- **The unified idea for a SASOS:** *the document IS the window, the shell, and the editor.* There is no separate widget toolkit, no separate shell buffer, no separate editor buffer. A node can be text, an embedded widget, a live data binding, a link, or a 3D viewport — all in one tree, exactly as DolDoc does.

### 4.2 Node model

```hc
#define DN_ROOT     0
#define DN_TEXT     1
#define DN_WIDGET   2   // button, checkbox, slider, list, tree
#define DN_EMBED    3   // sprite, shader quad, graph, 3D viewport
#define DN_BIND     4   // data binding: node value <- memory cell

class CDNode {
  I64      type;
  I64      flags;          // DIRTY, HOLD, LINK, COLLAPSED, ...
  U64      key;            // stable identity (hash of tag or explicit)
  U64      parent;         // node index, -1 for root
  U64      first_child;    // node index, -1
  U64      next_sibling;   // node index, -1
  I64      box_x, box_y, box_w, box_h;   // layout rect (pixels)
  U32      fg, bg;
  U8       text[64];       // inline text (tag) or 0
  U8       payload[128];   // tag args, macro string, binding expr
  U64      bind_addr;      // for DN_BIND: the watched memory cell
  U64      bind_prev;      // last observed value
  U64      render_gen;     // generation counter for incremental render
};

CDNode g_doc_nodes[DOLDOC_MAX_NODES];
I64    g_doc_node_count;
U64    g_doc_root;             // == 0
U64    g_doc_gen;              // bumped on any mutation
```

Flat arrays indexed by `U64` (not pointers) are the right choice for a SASOS: nodes are relocatable, the tree is trivially serializable to disk (RedSea), and there are no dangling pointers after a node is freed. `bind_addr` is the Smalltalk/DolDoc `$DA…$` idea: a node can *watch a raw memory address* and update itself — no event bus required.

### 4.3 Diff / patch algorithm

The document tree is rebuilt each "frame" from the shell/app's desired state (the "virtual document") and diffed against the last-committed tree. The diff is O(n) using the React heuristics, but with the SASOS twist that leaf nodes can be *identity-stable memory bindings*:

```
Diff(old_root, new_root) -> patch_list:
    if old.type != new.type or old.key != new.key:
        emit REPLACE(old, new)
        return
    if old.props != new.props:                     // text, fg/bg, box
        emit PROPS(old, new)
    if new.type == DN_BIND:
        if *(new.bind_addr) != old.bind_prev:      // watched cell changed
            emit BIND(old, new)
            new.bind_prev = *(new.bind_addr)
    DiffChildren(old, new)                         // keyed reconcile

DiffChildren(old, new):
    # Build key -> old-child index map (hash, O(n)).
    old_by_key = HashMap<U64, child>()
    for c in old.children: old_by_key[c.key] = c

    last_placed = 0
    for i, nc in enumerate(new.children):
        oc = old_by_key.remove(nc.key)
        if oc == NULL:
            emit INSERT(nc, parent=new, index=i)     # new key
        else:
            if oc.parent != new.parent or oc.type != nc.type:
                emit REMOVE(oc); emit INSERT(nc, new, i)   # moved/typed -> remount
            else:
                emit MOVE(oc, i) if needed
                Diff(oc, nc)                          # recurse
            last_placed = max(last_placed, index_of(oc))
    for remaining oc in old_by_key:                    # deleted keys
        emit REMOVE(oc)
```

Key selection: if the author supplies a `key`, use it; otherwise derive a stable key from the node's tag identity (e.g., a hash of `type + first text bytes + bind_addr`), *not* from its array index — index keys are what cause React's "state gets attached to the wrong row" bug when lists reorder.

Patch application mutates the flat arrays and marks affected subtrees dirty. Crucially, **a patch list is itself just a document** — you can log it, replay it, undo it, or send it over the network.

### 4.4 Drawing nodes via a rasterizer

Layout assigns `box_*` rects (a simple flow/stack layout is enough initially). Rendering is then a retained-mode traversal, but with three accelerations the reference already demonstrates:

1. **Row-dirty masks.** The reference tracks dirty state as a per-row bitmask (`g_doc_dirty_mask`, `DolDocMarkRowDirty`, `DolDoc.HC:482-492`) and only redraws dirty rows. For a node tree, generalize to a dirty *node set* plus a dirty *screen-tile* set.
2. **Morton spatial bins.** `Morton2D` (`DolDoc.HC:301-312`) interleaves x/y bits to map a pixel region to a 64×64 tile index, and `MortonSpatialInsertWidget` (`:320`) bins widgets by their box. On scroll, only tiles containing moved widgets are touched. Morton order also gives good cache locality. This is the right structure for hit-testing and partial redraw.
3. **Span rasterizer with NEON.** `apps/RasterTile.HC` and the render stack do per-pixel/span fills; commit `953f90b` added a NEON 8-pixel span rasterizer. Text and rect fills go through `gfx_draw_rect`/`gfx_draw_line`.

Node draw:

```
RenderNode(n, tile_x0, tile_y0, tile_x1, tile_y1):
    if !intersects(n.box, tile_rect): return
    switch n.type:
      DN_TEXT:   FontVectorDrawString(n.box_x, n.box_y, n.text, n.scale, n.fg)
      DN_WIDGET: DrawWidgetChrome(n.box)          # box + border + label
      DN_EMBED:  DispatchEmbed(n)                 # shader/sprite/graph/viewport
      DN_BIND:   RenderNode(as DN_TEXT of str(*(n.bind_addr)))
    for c in n.children: RenderNode(c, ...)
```

The **rasterizer contract** (already present) is:
- `gfx_draw_rect(x,y,w,h,color)` — solid fill,
- `gfx_draw_line(x0,y0,x1,y1,color)` — Bresenham/DDA,
- a span fill for horizontal runs, ideally NEON-vectorized for 8 pixels/iteration,
- an optional per-pixel Z for 3D overlays (the reference has exact 64-bit Z).

SDF text (§6) plugs in as a different `FontDraw` implementation, sampling a distance field per pixel instead of stamping a bitmap — no change to the tree or layout.

### 4.5 Reactive pitfalls

- **Unbounded rebuild cost** — rebuilding the whole virtual tree per frame is O(n) but with a large constant; keep `n` small (a window's visible nodes) and diff only the active document, not the whole world.
- **Key instability** — deriving keys from indices destroys identity across reorder; derive from content/binding address.
- **Dangling `bind_addr`** — if a bound global is freed (e.g., a REPL variable cell), the node must be invalidated. In a SASOS there is no fault to catch cheaply; track bindings in a table and clear them when the cell's symbol is re-registered.
- **Redraw storms** — a binding that changes every tick forces a redraw; coalesce by generation counter (`render_gen`) and only redraw if the value actually changed (`bind_prev`).
- **Layout invalidation** — a text change can change the box and shift siblings; mark ancestors dirty, not just the node.

---

## 5. Reactive shell

### 5.1 Dispatch via O(1) symbol-table lookup instead of if/strcmp chains

The current reference dispatches commands with a long `if/else if (strcmp(cmd,"x")==0)` chain (`Shell.HC:471-724`, dozens of `strcmp`/`strncmp` branches). It *also* maintains a command registry (`CShellCmdEntry g_shell_cmds[32]`, `Shell.HC:25-33`) but does not use it for dispatch. The O(1) design is to make the **symbol table the dispatch table**:

```hc
// Every command is a function whose name is a symbol. Registering a command is
// just registering a symbol; dispatching is just a symbol lookup.
U0 ShellRegisterCmd(U8 *name, U64 fn, U8 *help) {
    SymRegister(name, fn, SYM_FUNC);          // O(1) hash insert / hot-patch
    // also record help text in a parallel table keyed by the same hash
}

I64 ShellDispatch(U8 *line) {
    U8 name[64]; U8 *args = ShellSplitName(line, name);   // first token, rest = args
    U64 fn = SymLookup(name);                              // O(1)
    if (!fn) return ShellUnknown(name);
    typedef I64 (*CmdFn)(U8*);
    return ((CmdFn)fn)(args);                              // single indirect call
}
```

Benefits over the strcmp chain:
- **O(1)** average instead of O(#commands) string comparisons per command.
- **Commands become data**: any module that defines `FooCmd` and calls `ShellRegisterCmd("foo", &FooCmd, "…")` adds a command, with no central edit. The reference already does this ad hoc (`symbols_lookup("ShaderEditorCmd")`, `Shell.HC:570`); make it systematic.
- **Aliases are free**: register the same function under multiple names (or under canonical + Pascal + snake forms using the existing `SymLookupCanonical`, `Symbols.HC:274`).
- **Hot-patch on reload**: recompiling a command in the REPL hot-patches the SIC cell, so the next invocation runs the new code with no shell restart.

Prefix arguments (`save <file> <text>`, `render cpu`) are handled by the command function parsing its own `args` string; the shell only tokenizes the name.

**Tab completion** becomes a bucket scan or, better, a sorted-name index; the reference's `builtins[32]` array (`Shell.HC:144-175`) can be replaced by iterating `g_sym_buckets` for symbols tagged `SYM_CMD`.

### 5.2 Command output as an interactive document object

A command should not print bytes into a shared scrollback; it should **return a document subtree** that the shell mounts into the reactive tree. That makes output: selectable, linkable, embeddable (a `top` command can return a live-updating `DN_BIND` table), and composable (pipe one document into another).

```hc
// Instead of: doldoc_printf("  %lld\n", n);
// Do:
U64 CmdMem() {
    U64 doc = DocNewNode(DN_ROOT, 0);
    DocAddText(doc, "Memory", 0xFF89B4FA);
    DocAddText(doc, "$HR$", 0);
    U64 bind = DocAddBind(doc, &g_kheap_used_bytes, "KHeap used: %lld bytes");
    return doc;                     // shell mounts `doc` under the active pane
}
```

The shell keeps a stack of mounted documents (one per pane/window). A command's returned root is inserted with a `REPLACE`/`INSERT` patch (§4.3); the old root is retained in history for scrollback/undo. This is exactly DolDoc's model where a menu is a document and a macro is a link.

### 5.3 Idle loop with WFE

`WFE` (Wait For Event) is the right idle primitive. It "indicates that the PE can enter a low-power state and remain there until a wakeup event occurs" ([Arm WFE](https://support.arm.com/documentation/ddi0602/2026-06/Base-Instructions/WFE--Wait-for-event-)); `SEV` signals an event to all cores and `SEVL` to the current one ([SEV/SEVL/WFE/WFI/YIELD](https://support.arm.com/documentation/dui0802/b/A32-and-T32-Instructions/SEV--SEVL--WFE--WFI--and-YIELD)). The pattern is:

```
Sev();                 // ensure the event register is clear before waiting
for (;;) {
    if (WorkPending()) { DoWork(); }
    else { Wfe(); }    // sleep until SEV (posted by IRQ, another core, or a command)
}
```

The reference already uses `__wfe()` in the scheduler worker (`Sched.HC:348`), the SMP mailbox workers (`Smp.HC:64,92`), and `wfi` in the firmware halt (`boot/main.c:356`). Key semantics to get right:

- `WFE` is a **hint**; on some implementations it behaves like `NOP`. Never rely on it for correctness — always re-check the work condition after it returns.
- **Event register / lost wakeups**: use the `SEVL; WFE` idiom, or `SEV` before the loop, to avoid the classic race where an event fires between the condition check and the `WFE`.
- **Interrupts must wake WFE** — an IRQ (GIC timer, UART, virtio) naturally sets the event, which is why the tickless design works (`apps/Gic.HC`, `apps/Timer.HC`).
- Use `WFI` only for a final halt (nothing will run again), `WFE` for idle between work.

### 5.4 Reactive-shell pitfalls

- **Command name collisions** — namespace commands (`sym:`, `fs:`) or let registration order/hot-patch decide, but document it.
- **Output lifetime** — a returned document must be allocated from a document arena whose lifetime matches the mounted pane; do not return pointers into a command's stack frame.
- **Blocking commands** — a command that renders a 3D scene must yield; represent it as a node with a render callback rather than looping inside the command (the reference's `bench`/`gears` do loop; in a reactive shell they should register a per-frame node).
- **Reentrancy** — dispatch through a SIC cell means a command can be re-entered if it calls `ShellDispatch`; guard with a depth counter or a `g_shell_busy` flag.

---

## 6. SDF/TTF fonts

### 6.1 Why SDF

A signed distance field stores, at each texel, the distance to the nearest glyph edge (positive inside, negative outside); the shader thresholds at zero and can soften the threshold for cheap antialiasing. This gives resolution independence from a *small* texture, plus transforms (rotation/perspective) ([Valve 2007, *Improved Alpha-Tested Magnification*](https://steamcdn-a.akamaihd.net/apps/valve/2007/SIGGRAPH2007_AlphaTestedMagnification.pdf), [Red Blob Games SDF notes](https://www.redblobgames.com/x/2403-distance-field-fonts)). Downsides: rounded corners (fixed by multi-channel SDF, MSDF) and no hinting at small sizes. For a HolyC OS where you want one font texture at many sizes, SDF is the right tradeoff; `stb_truetype.h` can generate it directly ("render glyphs to one-channel SDF bitmaps… you can offset the distance range and slope" — [stb_truetype.h](https://github.com/nothings/stb/blob/master/stb_truetype.h)).

### 6.2 TTF parsing structure (single-file, no deps)

A `stb_truetype`-style parser is a self-contained, allocation-light module. The structure to mirror in HolyC:

```hc
class CTtfFont {
  U8  *data;            // whole file in memory (RedSea mmap or blob)
  U64  data_len;
  // Offset table
  U32  num_tables;
  // Table directory entries (tag, checksum, offset, length) resolved on load:
  U64  cmap_off, cmap_len;
  U64  glyf_off, glyf_len;      // or CFF
  U64  loca_off, loca_len;
  U64  head_off;                // unitsPerEm, indexToLocFormat
  U64  hhea_off, hmtx_off;      // horizontal metrics
  U64  maxp_off;                // numGlyphs
  U64  kern_off, kern_len;      // optional
  I64  units_per_em;
  I64  index_to_loc;            // 0 = short loca, 1 = long loca
  I64  num_glyphs;
};

// Reading is big-endian, bounds-checked, allocation-free:
I64 TtfU16(U8 *p) { return (p[0] << 8) | p[1]; }
I64 TtfI16(U8 *p) { I64 v = TtfU16(p); return (v & 0x8000) ? v - 0x10000 : v; }
U64 TtfU32(U8 *p) { return ((U64)p[0]<<24)|((U64)p[1]<<16)|((U64)p[2]<<8)|p[3]; }
```

The parsing pipeline is:

1. **Load table directory** — read `num_tables`, then for each entry store `tag → (offset,len)`. Reject if offsets exceed `data_len` (crash-proofing; stb explicitly lists "crashproof on bad data" as a TODO — do it from day one).
2. **`head`** → `unitsPerEm`, `indexToLocFormat`.
3. **`maxp`** → `numGlyphs`.
4. **`cmap`** → find a Unicode subtable (format 4 for BMP, format 12 for full); build a `char → glyph_id` lookup. Prefer a **direct-indexed array for ASCII 32..126** (the common case) and a binary search over sorted `(codepoint, gid)` pairs for the rest.
5. **`loca`** → glyph offsets (short or long depending on `indexToLocFormat`).
6. **`glyf`** → per-glyph contours: `numberOfContours`, `endPtsOfContours[]`, `instructionLength`, flags, and compressed x/y coordinate deltas. On-curve vs off-curve points; consecutive off-curve points imply an implicit on-curve midpoint.
7. **`hmtx`/`hhea`** → advance width and left side bearing per glyph (needed for layout).
8. **`kern`** (optional) → kerning pairs.

### 6.3 Outline → distance field

Two viable strategies, both single-file:

**A. Rasterize-then-distance-transform (simplest).** Render the glyph to a high-resolution binary coverage bitmap (reuse the existing Bézier/span rasterizer), then compute the SDF by a distance transform. The **Felzenszwalb–Huttenlocher** exact squared-EDT (two 1-D passes) is O(W·H) and trivially portable; or use a cheaper 8SSEDT/chamfer. This is what `tiny-sdf` does in ~2 KB (via a canvas) and what `stb_truetype` effectively offers through `stbtt_GetGlyphSDF`. Pros: tiny, no geometry code. Cons: quality limited by source raster resolution; corners round off.

**B. Analytic edge distance (higher quality, more code).** For each output texel, compute the minimum distance to all glyph edges (line segments and quadratic/cubic Béziers flattened to segments). Sign from even-odd or non-zero winding. This is `stbtt_GetGlyphSDF`'s approach: it rasterizes the glyph shape at a supersampled resolution and computes the distance field from the resulting edge list. To keep it fast:
- Flatten Béziers to short segments (adaptive subdivision; ~4–8 segments per curve at typical sizes).
- Build an edge list and a coarse spatial grid so each texel tests only nearby edges.
- Compute exact point–segment distance: `d = |(p-a) × (b-a)| / |b-a|` clamped to the segment.

**SDF texture format.** Store one byte per texel: `value = 128 + 127 * clamp(d / range, -1, 1)`, where `range` (px range) is the maximum distance represented. The `stb_truetype` header notes the tradeoff: more precision on the *interior* for small sizes, more on the *exterior* for outlines. A 32–64 px glyph cell with `range ≈ 4–8 px` is a good default. Pack glyphs into a texture atlas (simple shelf/skyline bin-packing) with per-glyph `(u0,v0,u1,v1)` and metrics.

**MSDF** (multi-channel) fixes corners by storing three distance fields (one per color channel) and taking the median; it needs different corner perturbation per channel ([msdfgen](https://github.com/Chlumsky/msdfgen), [Red Blob Games](https://www.redblobgames.com/x/2403-distance-field-fonts)). It is more code; start with single-channel SDF.

### 6.4 SDF text rendering

CPU rendering in a HolyC OS: for each glyph, for each destination pixel, bilinearly sample the SDF texture and map distance → coverage:

```
// per destination pixel (px,py) inside the glyph quad:
float d = BilinearSample(sdf_tex, u, v);        // 0..1, 0.5 == edge
float dist_px = (d - 0.5) * (2.0 * range);       // distance in glyph-texture pixels
float screen_px = dist_px * (glyph_tex_size / glyph_screen_size);  // scale to screen
float alpha = clamp(screen_px + 0.5, 0.0, 1.0);  // linear ramp; or smoothstep
color = mix(bg, fg, alpha);                      // per-pixel alpha blend
```

The `screenPxRange` scaling is the piece that makes one SDF work at all sizes. On the GPU it is computed from derivatives; on the CPU you compute it directly from the scale factor:

```
// screenPxRange = (texture_px_range) * (screen_size / texture_size)
float screen_px_range = range * (glyph_screen_h / glyph_tex_h);
```

The msdfgen shader uses `screenPxDistance = screenPxRange() * (sd - 0.5); opacity = clamp(screenPxDistance + 0.5, 0, 1)` — the same formula, one dimension simpler ([Red Blob Games](https://www.redblobgames.com/x/2403-distance-field-fonts)).

**Integration with the existing font stack.** `apps/FontVector.HC` already draws analytic quadratic Béziers with a normalized 0..60 × 0..100 grid (`FvMapX/FvMapY`, `BezierEval1D`), and `apps/FontMono.HC` + `gui/font8x16.h` provide a bitmap fallback. The SDF layer slots in as:

```hc
U0 FontSdfDrawGlyph(I64 x, I64 y, I64 gid, I64 px_h, U32 color);
U0 FontSdfDrawString(I64 x, I64 y, U8 *str, I64 px_h, U32 color);  // advance via hmtx
```

`FontVectorDrawChar`'s per-glyph case table (`FontVector.HC:103-322`) is a *vector outline source* that can be reused to generate an SDF atlas at boot (rasterize each glyph's contours into a small bitmap, then EDT), avoiding a full TTF parser until you want real font files. That is the pragmatic bootstrap: **use the built-in vector glyphs to build the SDF atlas, then add the TTF parser for user fonts.**

### 6.5 Font pitfalls

- **Endianness** — TTF is big-endian; AArch64 is little-endian by default; every multi-byte read must byte-swap.
- **Bounds-check everything** — a malformed font is the classic remote-code-execution vector; clamp every offset/length against `data_len` before dereferencing.
- **`loca` format** — short vs long is selected by `indexToLocFormat`; using the wrong one reads garbage offsets.
- **Composite glyphs** — a glyph can be composed of other glyphs with transforms (flags `ARG_1_AND_2_ARE_WORDS`, `WE_HAVE_A_SCALE`, `MORE_COMPONENTS`); recurse with a depth limit.
- **Off-curve midpoints** — consecutive off-curve points imply an implicit on-curve midpoint; forgetting it distorts curves.
- **SDF range vs size** — too small a range blurs large text; too large wastes texture precision. Expose it per atlas.
- **Gamma** — SDF alpha blending looks wrong in linear vs sRGB space; the common fix is a gamma ≈ 1.5 or a bias shift ([Red Blob Games](https://www.redblobgames.com/x/2403-distance-field-fonts)). Decide the blend space once and be consistent.
- **Hinting** — SDF cannot hint; accept slightly soft small text.

---

## 7. Consolidated data-structure appendix (HolyC)

```hc
// ---- Symbol table with SIC cells ----
#define SYM_FUNC 1
#define SYM_VAR  2
#define SYM_CMD  3
#define SYM_HW   4
#define SYM_BUCKETS 1024
class CSymbol {
  U8       name[64];
  U64      address;     // for SYM_FUNC: the live entry (the SIC cell itself)
  I64      type;
  U32      hash;
  CSymbol *next;
};
CSymbol *g_sym_buckets[SYM_BUCKETS];

// ---- Token (POD, no heap) ----
class CToken {
  I64 type;
  I64 val;              // int value or interned string offset
  I64 line, col, pos;
  U8  str[64];          // identifiers / short text inline
};

// ---- Code pool + patch stack ----
U32 *g_hc_code;         // HC_CODE_CAPACITY words
I64  g_hc_code_len;
I64  g_hc_epi_patches[64];
I64  g_hc_brk_stack[512];   // 16 levels x 32 patches
I64  g_hc_cont_stack[512];

// ---- String arena (bump) ----
#define HC_STR_CHUNK 262144
U8  g_hc_str_arena0[HC_STR_CHUNK];
U8 *g_hc_str_chunks[64];
I64 g_hc_str_off, g_hc_str_nchunks;

// ---- Document node (flat, index-based) ----
class CDNode {
  I64 type, flags;
  U64 key, parent, first_child, next_sibling;
  I64 box_x, box_y, box_w, box_h;
  U32 fg, bg;
  U8  text[64];
  U8  payload[128];
  U64 bind_addr, bind_prev, render_gen;
};
CDNode g_doc_nodes[DOLDOC_MAX_NODES];

// ---- SDF atlas ----
class CSdfAtlas {
  U8  *pixels;            // W*H bytes, 0..255
  I64  w, h, range;       // range in texels
  // per-glyph: u0,v0,u1,v1, advance, bearing
  I64  gu0[256], gv0[256], gu1[256], gv1[256];
  I64  gadv[256], gbear[256];
};
```

---

## 8. Cross-cutting pitfalls summary

| Area | Pitfall | Fix |
|---|---|---|
| SIC | patching a live cell while another core calls it | single aligned 8-byte store + `dmb ish`; publish-before-body |
| SIC | self-host clobber of running compiler | `symbols_is_defined/is_func` guard before overwrite |
| JIT | branch out of ±1 MiB range | range-extension thunks |
| JIT | stale I-cache | `dc civac`+`ic ivau`+`dsb sy`+`isb` per core |
| JIT | non-reentrant globals vs preemption | `g_hc_compiling` guard defers scheduler |
| Lexer | per-token heap alloc | POD tokens + arena for strings only |
| Lexer | over-long literal corrupts memory | bounded arena + `g_hc_error` |
| Compiler | HolyC byte-based pointer arithmetic | scale only in `[]`; carry scale metadata |
| Compiler | 64-bit extension of all values | emit 64-bit ops; respect `U0`/`F64` |
| Macros | `#define` table growth | cap at 1024; persist across units |
| DolDoc | index-based node keys | content/binding-derived keys |
| DolDoc | dangling `bind_addr` | binding table; clear on symbol re-register |
| Shell | strcmp chain O(n) | symbol-table dispatch |
| Shell | lost WFE wakeup | `SEV` before loop / `SEVL;WFE` |
| Fonts | malformed TTF → RCE | bounds-check every offset |
| Fonts | gamma-incorrect blend | fix blend space; gamma ≈ 1.5 |
| SMP | per-core cache | broadcast I-cache invalidate |

---

## 9. References

**Architecture / AArch64**
- ADRP (decode, ±4 GiB, page-relative): https://www.scs.stanford.edu/~zyedidia/arm64/adrp.html
- ARM ADRP/ADRL demos and encoding math: https://duetorun.com/blog/20230608/arm-adrp-adrl · https://duetorun.com/blog/20230609/arm-adr-demo
- Arm A64 instruction set (ADRP): https://developer.arm.com/documentation/ddi0487/mc/-Part-C-The-AArch64-Instruction-Set/-Chapter-C6-A64-Base-Instruction-Descriptions/-C6-2-Alphabetical-list-of-A64-base-instructions/-C6-2-13-ADRP
- WFE (wait for event): https://support.arm.com/documentation/ddi0602/2026-06/Base-Instructions/WFE--Wait-for-event-
- SEV/SEVL/WFE/WFI/YIELD: https://support.arm.com/documentation/dui0802/b/A32-and-T32-Instructions/SEV--SEVL--WFE--WFI--and-YIELD

**Linking / indirection**
- MaskRay, *All about Procedure Linkage Table* (PLT/GOT, lazy vs eager, AArch64 PLT): https://maskray.me/blog/all-about-procedure-linkage-table
- QNX, *Lazy binding*: https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.prog/topic/devel_Lazy_binding.html
- *How Linux Loads Shared Libraries* (GOT/PLT): https://www.wadixtech.com/blog/linux-shared-libraries-dynamic-linking

**Compilers (single-pass, JIT, arenas)**
- chibicc (stages, AST): https://github.com/rui314/chibicc · https://deepwiki.com/rui314/chibicc/2-compiler-architecture
- SubC (one-pass, self-hosting): https://www.t3x.org/subc/README-book.html · https://github.com/minux/subc
- One-pass compiler primer: https://keleshev.com/one-pass-compiler-primer
- TCC (single-pass): https://wiki.osdev.org/TCC
- Bump/arena allocators: https://os.phil-opp.com/allocator-designs · https://medium.com/@inferara/arena-based-allocation-in-compilers-b96cce4dc9ac
- Linear-scan register allocation: https://web.cs.ucla.edu/~palsberg/course/cs132/linearscan.pdf
- Hash functions (FNV-1a vs DJB2): https://www.isthe.com/chongo/tech/comp/fnv · https://mojoauth.com/security-guides/fnv-1a-in-c · https://aras-p.info/blog/2016/08/09/More-Hash-Function-Tests/

**TempleOS / HolyC / DolDoc**
- HolyC language reference: https://tinkeros.github.io/WbTempleOS/Doc/HolyC.html
- A Language Design Analysis of HolyC (Harrison Totty): https://harrisontotty.github.io/p/a-lang-design-analysis-of-holyc
- DolDoc Overview (grammar, tags, flags, args): https://tinkeros.github.io/WbTempleOS/Doc/DolDocOverview.html · https://templeos.info/Wb/Doc/DolDocOverview.DD.HTML
- A Constructive Look at TempleOS (DolDoc as unified hypertext): http://www.codersnotes.com/notes/a-constructive-look-at-templeos
- TempleOS (Wikipedia): https://en.wikipedia.org/wiki/TempleOS
- HolyC Lang: https://holyc-lang.com

**Reactive UI / object memory**
- React reconciliation (O(n) heuristics, keys): https://legacy.reactjs.org/docs/reconciliation.html
- React diffing implementation (REORDER/INSERT/REMOVE/REPLACE/PROPS): https://github.com/tigerabrodi/react-virtual-dom-diffing-algorithm
- Smalltalk-76 programming system (single-address-space objects): https://smalltalkzoo.computerhistory.org/papers/The%20Smalltalk-76%20Programming%20System.PDF
- LOOM — Large Object-Oriented Memory for Smalltalk-80: http://web.cecs.pdx.edu/~black/OOP/papers/Kaehler%20&%20Krasner-LOOM.pdf
- Smalltalk overview (object = struct + class pointer): https://web.cecs.pdx.edu/~harry/musings/SmalltalkOverview.html

**Fonts / SDF**
- Valve, *Improved Alpha-Tested Magnification for Vector Textures and Special Effects* (SIGGRAPH 2007): https://steamcdn-a.akamaihd.net/apps/valve/2007/SIGGRAPH2007_AlphaTestedMagnification.pdf
- stb_truetype.h (SDF generation, parsing): https://github.com/nothings/stb/blob/master/stb_truetype.h
- Red Blob Games, SDF fonts (screenPxRange, gamma, corners): https://www.redblobgames.com/x/2403-distance-field-fonts · https://www.redblobgames.com/articles/sdf-fonts/
- msdfgen (MSDF, corner problem): https://github.com/Chlumsky/msdfgen
- Sean Barrett, *How stb_truetype rasterizes*: https://nothings.org/gamedev/rasterize/
- msdf_c single-file: https://github.com/pjako/msdf_c
- tiny-sdf: https://github.com/mapbox/tiny-sdf

---

*End of brief. The reference implementation at `/home/user/neo-os` was read only and not modified.*
