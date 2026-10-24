# NeoOS Forensic Audit — Compiler / Bootstrap (P0–P2, P7.0)

Auditor: read-only forensic pass. Repo: `/home/user/neo-os` @ `HEAD 61b5546` (P7.0).
Method: line-by-line static read of the scoped files + live QEMU/UART reproduction of the
D29/D30 compiler defects against the running guest (no repo file was modified; only
`/tmp/neo-audit/01-compiler-bootstrap.md` was written). The guest REPL state accumulated
across probes (persistent struct/global registries), so D30 was first reproduced from an
early, near-clean state and the callee/`if` correlation was established with back-to-back
controlled pairs.

Scoped files read: `apps/Compiler.HC`, `boot/seed/jit_arm64.c`, `boot/seed/lexer.c`,
`boot/seed/table.c`, `boot/main.c`, `kernel/arch/aarch64/vectors.S`, `apps/Exceptions.HC`,
`scripts/{golden-boot.sh,crash-decode.py,p1-parity.sh,census-c-runtime.sh,self-host-test.sh}`,
`tests/jit_golden/cases.json`, `tests/census-baseline.txt`, `apps/{Symbols,RedSea,SelfTest,Shell,DolDoc,KernelInit}.HC`,
`docs/04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`, `docs/02-TASKLIST.md`.

---

## 1. Workarounds / disabled tests / comments hiding bugs

| # | Location | Finding | Workaround vs root-fix | Sev |
|---|---|---|---|---|
|1.1|`apps/SelfTest.HC:13-14`, `:994`; `tests/jit_golden/cases.json:676-677`|The struct-fnptr-dispatch case is **absent** from the in-guest battery; only `known_over8_args` is `known`-tagged. This is the D30 exclusion. `SelfTestCheck3` covers a *plain local* fnptr (`fnptr_indirect_call` `:974`, `fnptr_addr_of_fn` `:926`) — never a `(*fn)(...)` **struct member**.|**Caller workaround** (D30 root fix pending) | HIGH |
|1.2|`apps/Shell.HC:35,73-84,312,890`|`CShellCmd.fn_addr` is a plain `U64`; dispatch does `h = g_shell_cmds[ci].fn_addr;` then calls through a **typed local**, explicitly to avoid the struct fnptr member (documented in D30).|**Caller workaround** | HIGH |
|1.3|`apps/DolDoc.HC:293,322`|`U64 g_doc_pump_cb` + `DolDocSetPump(U64 fn)` — the Shell pump is smuggled through a `U64`, again avoiding a `(*fn)` member.|**Caller workaround** | MED |
|1.4|`boot/seed/jit_arm64.c:1341`|`if (l->pos != pf_start_pos + 2 && lexer_peek(l).type != TOK_EOF && 0) {}` — a dead `&& 0` guard with an empty body in the post-inc/dec path. Disabled logic left in the tree.|**Disabled code hiding a bug** | MED |
|1.5|`boot/main.c:159`|`printf("[DEBUG BASE] main is at 0x%016llX\n", …)` — debug print shipped on every boot.|Hygiene | LOW |
|1.6|`boot/seed/jit_arm64.c:3763-3771`|`[DEBUG-JIT] cb.count = … before/after peephole`, `Calling fn() at …`, `fn() returned …` — verbose debug prints; **observed live** on every `jit_compile_and_run` call.|Hygiene (log noise; `golden-boot.sh:29` only fails on `[JIT] Error`, so these pass the gate)| LOW |
|1.7|`apps/Compiler.HC:1256-1257`|`#define` expression folding **deliberately excludes `/`** “so a trailing `// comment` is never parsed as division”. This is a workaround for the lexer not tracking line/comment boundaries; it is also a seed divergence (§7).|**Workaround**, partial root fix | MED |
|1.8|`apps/RasterTile.HC:193`|Comment: the typed-local workaround `U32 *td = g_rtex.data; td[...]` is “no longer needed” (D7 root-fixed). Confirms a removed workaround — no action.|Informational | — |
|1.9|`apps/KHeap.HC:188,491`|`KFree` deliberately **no-ops** on a “pinned seed block (below the pool)” and a comment says it “no-ops instead of tripping a false HEAP_CANARY panic”. A guard that suppresses a canary check.|Deliberate, but masks heap-integrity signal | MED |
|1.10|`scripts/census-c-runtime.sh:23-27`|`hal_flush_cache`/`redsea_*`/`virtio_*` are deliberately excluded from the census. Documented rationale, but it means the gate cannot see `.HC`→C regressions in those subsystems.|Documented exclusion | LOW |
|1.11|`apps/SelfTest.HC:13` vs `golden-boot.sh:60` vs `docs/04:727`|Header says “74 active cases”; `golden-boot.sh` only requires `a >= 74`; D27/P7.0 claims `SELFTEST 96/96`. The pass threshold was **not** raised to the real count, so 74/74 passes even if 22 cases silently disappear.|Gate weakness (hides test loss) | MED |
|1.12|`boot/seed/jit_arm64.c:469-487`|`emit_b_cond_placeholder` / `patch_b_cond` are marked `__attribute__((unused))` — dead functions.|Dead code | LOW |
|1.13|`apps/Exceptions.HC:251-253`|`ExceptionsPrintDolDoc` uses `%d` for `I64` counters (the known `%d`×~40 typing sweep).|Known typing defect (doc 04 Part E)| LOW |

No `TODO`/`FIXME`/`HACK`/`XXX` markers exist in `apps/`, `boot/seed/`, `kernel/` (the only
hits are `boot/uefi/uefi.h:618` `2XXX` in a comment and `scripts/elf2efi.py:278`). There are
**no commented-out tests** in the `.HC` tree; the only disabled construct is 1.4.

---

## 2. D29 — array-dimension constant expressions

**There is no shared helper.** The dimension parser is **duplicated three times in
`Compiler.HC` and twice in the seed**; each folds only `*` and `+`.

### 2.1 `Compiler.HC` — struct member (`HcParseStructDef`), lines 2585-2610
```c
if (g_hc_tok == TOK_LBRACKET) {                       // 2585
    HcLexNext();
    I64 acnt = 1;
    if (g_hc_tok == TOK_NUMBER) { acnt = g_hc_tok_val; HcLexNext(); }
    while (g_hc_tok == TOK_STAR || g_hc_tok == TOK_PLUS) {   // 2600
        I64 m_dim_op = g_hc_tok; HcLexNext();
        I64 m_dim_f = 1;
        if (g_hc_tok == TOK_NUMBER) { m_dim_f = g_hc_tok_val; HcLexNext(); }
        if (m_dim_op == TOK_STAR) acnt = acnt * m_dim_f;
        else                      acnt = acnt + m_dim_f;
    }
    ...
}
```
Evaluates **`*` and `+` only**. `-`, `/`, `<<`, `>>` are not consumed.

### 2.2 `Compiler.HC` — local declaration (`HcParseStatement`), lines 2805-2824
```c
while (g_hc_tok == TOK_LBRACKET) {                    // 2809
    HcLexNext();
    I64 dim = 1;
    if (g_hc_tok == TOK_NUMBER) { dim = g_hc_tok_val; HcLexNext(); }
    while (g_hc_tok == TOK_STAR || g_hc_tok == TOK_PLUS) {   // 2813
        ... if (dim_op == TOK_STAR) dim = dim * dim_f; else dim = dim + dim_f;
    }
    ...
}
```
Same: **`*` / `+` only**.

### 2.3 `Compiler.HC` — global declaration (`HcParseProgram`), lines 3455-3475
```c
while (g_hc_tok == TOK_LBRACKET) {                    // 3459
    HcLexNext();
    I64 dim = 1;
    if (g_hc_tok == TOK_NUMBER) { dim = g_hc_tok_val; HcLexNext(); }
    while (g_hc_tok == TOK_STAR || g_hc_tok == TOK_PLUS) {   // 3464
        ... if (dim_op == TOK_STAR) dim = dim * dim_f; else dim = dim + dim_f;
    }
    ...
}
```
Same: **`*` / `+` only**.

### 2.4 `boot/seed/jit_arm64.c` — struct member, lines 2010-2054
`while (lexer_peek(l).type == TOK_STAR || lexer_peek(l).type == TOK_PLUS)` (2031) — **`*` / `+` only**.

### 2.5 `boot/seed/jit_arm64.c` — global/local, lines 2711-2743
`while (lexer_peek(l).type == TOK_STAR || lexer_peek(l).type == TOK_PLUS)` (2726) — **`*` / `+` only**.

### 2.6 The `HC_CODE_CAPACITY / 8` case — CONFIRMED DROPPED
The fix landed as a **literal**: `U8 g_hc_target_bits[131072];` (`Compiler.HC:155`), i.e.
`HC_CODE_CAPACITY/8`. With the dimension parser above, `HC_CODE_CAPACITY / 8` is not folded:
`HC_CODE_CAPACITY` is macro-substituted to `1048576`; the parser reads `1048576`, then stops
at `/`, and the trailing `/ 8]` is left unconsumed. The comment at 2592-2599 states the same
for the D15 member fix (“recorded only `MESH_MAX_T` elements and left `* 3]`”). D29
(`docs/04:711-716`) states the `/8` was dropped and a **1 MB** array was allocated, exhausting
memory.

**Live confirmation (current tree):** in the guest,
`U8 gt1[64 / 8]; …` → `[COMPILER.HC] internal error … --> -1`
`U8 gt2[64 - 1]; …` → `internal error … --> -1`
while `U8 gt3[64 * 2];` → `1` and `U8 gt4[64 + 8];` → `1`.
So today `/` and `-` are a **hard compile error** (not a silent 1 MB alloc — the parser state
at D29 discovery differed), and `*`/`+` fold.

- **Severity: HIGH.** D29 is unresolved; the workaround (write literals everywhere) is fragile and already caused one boot-breaking bug.
- **Root fix:** add a single shared `HcParseArrayDim()` (and a `parse_array_dim()` in the seed) that folds `* / + - << >>` with left-to-right evaluation and an overflow guard, then call it from all five sites. Do **not** rely on macro substitution alone.

---

## 3. D30 — indirect call through a struct function-pointer member

### 3.1 What the parser emits for `s.fn(args)` / `p->fn(args)`
- `HcParsePrimary` (`Compiler.HC:1972`) reads the leading identifier. The **direct-call** path is taken only when `g_hc_tok == TOK_LPAREN` *immediately* after the identifier and the name is neither a local nor a variable (`1981`). For `p->fn(...)` the next token is `->`, so this path is **not** taken.
- `HcResolveLValue` (`1718-1920`) consumes the whole `.`/`->`/`[]` chain. Member resolution is at `1813-1852`; a fnptr member is registered with `is_ptr=1, size=8` (`2553-2566`). The function returns the **address** in `x0` with `out_addr_only=0` for a pointer member.
- `HcParsePrimary:2051-2058` then emits the member load (`HcEmitLoadSized(0,0,8)` → `ldr x0,[x0]`).
- **The `TOK_LPAREN` *is* handled as an indirect call** at `Compiler.HC:2060-2084`:
```c
if (g_hc_tok == TOK_LPAREN) {                    // 2061
    HcEmitPush(0);                               // 2062 push fn ptr
    HcLexNext();                                 // eat '('
    ... parse args, HcEmitPush(0) each ...
    if (ind_argc > 8) g_hc_error = 1;            // 2077
    for (ia_reg = ind_argc-1; ia_reg >= 0; ia_reg--) HcEmitPop(ia_reg);
    HcEmitPop(16);                               // 2082 fn ptr -> x16
    HcEmit(0xD63F0200);                          // 2083 blr x16
}
```
- The statement parser's identifier fast-path (`3234-3268`) resolves the lvalue, and if the following token is not an assignment it **restores state and re-parses via `HcParseExpr()`** (`3260-3266`), so the call is compiled exactly once.

**Conclusion:** the doc's D30 framing (“`TOK_LPAREN` after a `.member` is *not* handled”) is
**inaccurate** — the indirect path exists and is structurally identical to the seed's
(`boot/seed/jit_arm64.c:1297-1330`). The seed additionally loads the member value before the
call (`jit_arm64.c:1254-1257`) and then takes the same `TOK_LPAREN` path.

### 3.2 The `ldr x16,[x16]; blr x16` null fault
That exact sequence is the **direct-call SIC** sequence, not the indirect path:
`Compiler.HC:2025-2028` → `HcEmitImm64(16, target); HcEmitLoadSized(16,16,8)` (`ldr x16,[x16]`); `blr x16`. It faults at `FAR=0` when `symbols_sic_cell(name)` returned 0 (no cell) or the cell held 0. The indirect path emits only `ldr x16,[sp],#16; blr x16` (2082-2083), which faults at the *loaded* pointer, not 0.

### 3.3 Live reproduction (the real symptom)
Compiling `class C { I64 id; I64 value; I64 (*calc)(C *item, I64 m); } I64 Mul(C *item, I64 m) { if (!item) return 0; return item->value * m; } I64 Main() { C item; item.value=10; C *p=&item; p->calc=&Mul; return p->calc(p,3); }`
through `Compiler.HC` returned **garbage, not 30** (e.g. `0x777386D0`, `0x7879E800`), and
**not a clean crash**. Disassembly of the failing `Main` (`0x7842B7C0`) shows the entire call
sequence is **absent**: after `p->calc = &CY2Mul` the code is
`movz x0,#0xe800; movk x0,#0x7879,lsl#16; ldr d0,[x0]; ret` — i.e. an **F64 global load**, not
a `blr`. The callee itself (`0x7842B73C`) is correct.
- Removing the callee's `if` (CY1) → correct `30`. Adding a conditional (CY2/CY3) → garbage.
- Calling the same callee **directly** (CY4) or via a **local** fnptr (FF) → correct.
- The failure is data-dependent on the callee's control flow / code placement, not on the
  member name (TN2/TP2 pass; CY2 fails). This points at shared compiler **state corruption**
  (op-stack / single-pass emitter state) rather than a missing call path.
- **Parity:** the C seed also miscompiles the equivalent source (live
  `jit_compile_and_run("class … I64 Main(){… p->calc(p,3);}")` returned the code address and
  emitted an **empty `Main`**, `[DEBUG-JIT] cb.count = 5 instrs`). So D30 is a **shared
  codegen defect**, not a Compiler.HC-only or seed-only divergence.

- **Severity: BLOCKER.** Struct fnptr dispatch is unusable; the current workarounds (Shell/DolDoc) are load-bearing.
- **Root fix:** isolate whether the callee's `if` leaves `g_hc_op_sp` / emitter state unbalanced across `HcParseFunction` boundaries (compare pre-/post-peephole code by building a copy of the tree with `HcOptimizePeephole` disabled — do **not** patch the live tree), fix at the root, then **re-add the fnptr-dispatch case to `SelfTest.HC`** (currently excluded, `:13-14`). Also fix the doc 04 D30 text (the missing-`TOK_LPAREN` explanation is wrong).

---

## 4. P1.3 open items

- **Symbol lookup hash vs linear:** `apps/Symbols.HC` is **already hash-based** — DJB2, 1024 buckets (`SYM_HASH_BUCKETS 1024`, `:8`), `SymHashString` `:135-143`, `SymLookupEntry` `:192-203`. Exact lookup is O(1). **However** `SymLookupCanonical` (`:274-307`) falls back to a **full 1024-bucket linear scan** (`while (slc_b < SYM_HASH_BUCKETS) { … SymCanonicalMatch … }`, `:282-292`) because no normalized key is stored. **P1.3 not done** (`docs/02-TASKLIST.md:1036-1039`). Also DJB2 is not FNV-1a.
  - Sev MED. Root fix: store a normalized (case/underscore-folded) key + its hash and look it up in O(1).
- **`CBZ`/`CBNZ` range guard:** **absent.** `HcBackpatchCbz`/`HcBackpatchCbnz` (`Compiler.HC:1082-1095`) do `(diff & 0x7FFFF) << 5` with **no** range check; a distance beyond ±2^18 instructions silently wraps to a wrong target. `HcBackpatchB` masks to 26 bits similarly (`1097-1101`). The seed has the same omission (`boot/seed/jit_arm64.c:459-466`). No range-extension thunks exist.
  - Sev HIGH (silent miscompile). Root fix: check the displacement and emit a `b`-trampoline/thunk when out of range, or hard-error.
- **Silent failure paths:** several errors are swallowed without `g_hc_error`:
  - Unknown **member**: `HcResolveLValue:1833` `if (HcFindMember(...)) { … }` with **no else** — `s.no_such_member` silently compiles as the base address (offset 0). Sev MED.
  - `HcParseStructDef:2504` `if (g_hc_tok != TOK_IDENT) return;` and `:2510` `if (g_hc_tok != TOK_LBRACE) return;` — malformed struct silently accepted. Sev MED.
  - `HcParseProgram:3425-3430` an IDENT type that is not a known struct is silently treated as an `I64` global (`g_bytes` stays 8). Sev MED.
  - `HcParseFunction:3349-3352` publishes the function **before** parsing the body (`HcAddFunc` then `HcParseStatement`), and never requires `{`; a mid-body error leaves a dangling published symbol (the known D4 hazard). Sev MED.
- **>8-arg calls:** still a **hard error** — `Compiler.HC:2004-2009` (`cur_argc > 8 → g_hc_error=1`) and `:2077` (`ind_argc > 8`). Intentional and documented (`docs/02-TASKLIST.md:261`), matches the C JIT’s X0–X7 limit. No stack spill. Sev LOW (by design), but it is a documented open P1.3 item.

---

## 5. P2.8 — RedSea integrity & atomic commit

**Real state: a plain contiguous FAT-like FS + a volatile RAMDisk. No CRC, no uberblock, no
txg, no atomic commit, no durability barrier.**

- No occurrence of `CRC`, `crc32`, `0x82F63B78`, `0xE3069283`, `uber`, `txg` anywhere in `apps/RedSea.HC`.
- `CRedSeaFs` (`:27-36`) is `root_lba/root_sectors/total_sectors/current_dir_lba/next_alloc_lba/current_pwd/initialized` — no superblock/checksum/transaction fields.
- Write path `RedSeaWriteFile` (`:292-366`) is **in-place**: allocate `next_alloc_lba` contiguously, `RsWriteSectors` payload, then `RsWriteSectors` the directory sector — **no ordering barrier, no journal, no fsync**; an interrupted write leaves an inconsistent entry.
- `RedSeaDeleteFile` (`:400-419`) does best-effort `next_alloc_lba` rewind only when the deleted cluster is the tail (`:413-415`).
- Durability: no `DC CVAC`/`DSB SY` in the write path (P2.8 explicitly calls for them).

Docs agree it is open (`docs/04:351`, `docs/02-TASKLIST.md:1040-1042` mark P2.8 unchecked). So
the docs do **not** over-claim; the finding is that the feature is simply unimplemented.

- **Severity: MED** (data-integrity gap; not a build blocker). Root fix: CRC32C table + per-block CRC, an uberblock ring with monotonic `txg`, and `DC CVAC`+`DSB SY` before the directory commit, per `docs/02-TASKLIST.md:1040-1042`.

---

## 6. Repo hygiene

- **Tracked binary build artifacts: 11** — `git ls-files | grep -E '\.(o|a)$'` →
  `boot/uefi/{crt_aarch64.o, dirent.o, qsort.o, reloc.o, stat.o, stdio.o, stdlib.o, string.o, time.o, unistd.o, libuefi.a}`.
  The `.gitignore` ignores `*.o`/`*.a` but re-includes **only** `!boot/uefi/crt_aarch64.o` (`:.gitignore:3-5`), so the other 10 are tracked despite being ignored — inconsistent and stale. **Sev LOW.**
- **Root-level stray images/log: 18 PNGs + `GEARS_BENCHMARK.LOG`** (tracked): `all_enhancements_live.png`, `apps_suite_live.png`, `bench3d_fixed.png`, `bench_dual_live.png`, `bench_results_live.png`, `bench_single_live.png`, `dual_cubes_benchmarks_live.png`, `filer_app_live.png`, `glxgears_dual_live.png`, `glxgears_fast_dual.png`, `glxgears_fast_live.png`, `glxgears_fixed.png`, `glxgears_single_live.png`, `interactive_shell.png`, `menu_live.png`, `phase1_live.png`, `screenshot.png`, `top_real_live.png`; plus `GEARS_BENCHMARK.LOG`. **Sev LOW.**
- **`docs/images/` (~90 PNGs) and `screenshots/` (~50 PNGs) are tracked** — large binary clutter. **Sev LOW.**
- **Orphan branches: none.** `git branch -a` = `main` only (P7.0 deleted `p4.3-wip`). **Good.**
- **`build/` is not tracked** (gitignored); `boot/build/` also untracked. `apps/cube.obj`/`sphere.obj` are tracked data files (acceptable). No `__pycache__`/`.pyc` tracked. **Good.**
- **`.gitignore` state:** covers `build/`, `*.o`, `*.a`, `*.ppm`, `.DS_Store`, `*.swp/swo`, `__pycache__/`, `*.pyc`. It does **not** ignore root `*.png`, `*.LOG`, or the vendored `boot/uefi/*.o|a` (only crt is re-included). **Sev LOW.**
- **Stale gate scripts:**
  - `scripts/p1-parity.sh:116-124` probes `g_wm.count`, `g_wm.screen_w`, `g_comp.tiles_x` and maps them to `WM.HC`/`Compositor.HC` — **both modules were deleted in P5** (`ls apps/WM.HC`/`Compositor.HC` → not found). Those probes can only yield `N/A`/divergence. **Sev MED.**
  - `scripts/p1-parity.sh:214` still greps `ALL 32 HOLYC SUBSYSTEMS`; `KernelInit.HC:111` prints `ALL 34`. Stale boot marker (the `DolDocShell active` fallback saves it). **Sev LOW.**
  - `scripts/p1-parity.sh:171-176` depends on exact anchors `"    g_hc_ready = 1;"` and the `if (g_hc_ready) {…}` call site — both still present in `KernelInit.HC:36,57`, so it runs, but it is brittle.
  - `scripts/crash-decode.py:114` parses the C seed’s `[JIT] Compiled function '…' to RAM at …` line; the seed now also prints `[DEBUG-JIT]`, and the self-host map is `[HCF]` (`:116`). Mostly fine, but the C-seed line format is a moving target. **Sev LOW.**
- **Census gate healthy:** `scripts/census-c-runtime.sh` → `CENSUS: PASS (181 total, none increased)`, matching `tests/census-baseline.txt` (55+52+38+26+1+1+1+1+1+5 = 181). **Good.**

---

## 7. Compiler vs C-seed divergence + peephole port

### 7.1 Feature divergences (beyond D17/D18/D19)
1. **`#define` expression evaluator.** Seed (`lexer.c:101-134`) folds **`* / + -`** and **parentheses** (`parse_define_factor:49-53`), registering the value as a `SYM_VAR`. `Compiler.HC` (`1256-1277`) folds only **`* + -`**, explicitly **excludes `/`**, and has **no parenthesis handling** — `#define X (6*7)` evaluates to `0` in `Compiler.HC` but `42` in the seed. Latent (no current `apps/*.HC` uses parens or `/` in a `#define`; grep found none), but a real semantic split. **Sev MED.**
2. **Array-dimension IDENT resolution.** Seed resolves a non-numeric dimension by looking up a **runtime symbol’s value** and special-cases `MAX_WINDOWS`→16 (`jit_arm64.c:2017-2024`, `2717-2724`); `Compiler.HC` relies **solely** on lexer macro substitution (`3462-3463`). A dimension written as a non-macro global const would diverge. **Sev LOW.**
3. **Unknown-member handling.** Seed falls back to a runtime `table_get(tbl, field)` (`jit_arm64.c:1264-1270`); `Compiler.HC` silently ignores the member (offset 0, §4). **Sev MED.**
4. **Peephole application granularity.** Seed calls `jit_optimize_peephole` **per function** (`jit_arm64.c:2700`) and for the top-level wrapper (`3631`); `Compiler.HC` calls it **once per module** (`3875`, `HcOptimizePeephole(start_idx, g_hc_code_len)`). Functionally equivalent (NOP-based, index-preserving); the Compiler’s target bitmap covers `[start,end)` (whole module) vs the seed scanning the whole function buffer, so the Compiler is marginally **more conservative**. No correctness divergence. **Sev INFO.**
5. **Seed `jit_compile_and_run` unit model.** Live: feeding a `class + function + Main` unit to the seed produced an **empty `Main`** (5 instrs), while `Compiler.HC` compiled it (miscompiled, D30). The seed’s one-shot REPL entry differs from the module-load path; parity for multi-definition units is **not** established by the existing gates. **Sev MED.**
6. **Diagnostics.** Seed prints `[JIT]`/`[DEBUG-JIT]`; Compiler prints `[HCF]`/`[COMPILER.HC]`. Cosmetic.

### 7.2 Peephole optimizer — is the `Compiler.HC` port equivalent, and is NOP substitution safe?
`Compiler.HC:810-990` is a faithful port of `jit_arm64.c:709-878`:
- Pass 1 stack round-trip collapse (`STR X0,[SP,#-16]! … LDR X0/X1,[SP],#16` → NOP/NOP or MOV/NOP); Pass 2 dead `MOV Xd,Xd`; Pass 3 redundant `ADD Xd,Xd,#0`; 4 passes max.
- The only differences are cosmetic: Pass-1 check order (`X0` first vs `X1` first — encodings are disjoint, so no effect) and the target scan (bitmap over `[start,end)` vs whole-buffer scan).
- **Index preservation:** substitutions are NOP/MOV only — no insert/delete — so `HcBackpatchCbz/Cbnz/B`, the break/continue stacks, and the epilogue patch indices remain valid. Verified.
- **NZCV:** `MOV` (`0xAA0003Ex` ORR) and `ADD (immediate) #0` (`0x91000000`, the **non-flag-setting** variant) do not touch NZCV; `NOP` does not. **No flag effect.**
- **Branch targets:** `HcCanCollapse` (`866-888`) rejects any window containing B/B.cond/CBZ/CBNZ/BL/BLR/SVC/RET and any window with a branch target in `(p,q]`. Shared theoretical edge case: a branch targeting **`p`** itself (the `STR`) is not rejected by either engine, but the collapse preserves net SP and the pushed value is delivered via `MOV`, so this is benign in the emitter’s usage.
- **Conclusion:** semantically equivalent; no flag/target hazard introduced. The peephole is **not** the cause of the D30 miscompile (it cannot remove a `blr`, and the failing caller’s call sequence is absent from the emitted code, not NOP’d). **Sev INFO.**

---

## Prioritized root-fix list

1. **BLOCKER — D30 fnptr-member dispatch.** Root-cause the shared (Compiler.HC **and** seed) miscompile of `p->fn(args)` when the callee contains a conditional (live: garbage return; call sequence absent / F64-load emitted). Diagnose by building a copy of the tree with `HcOptimizePeephole` disabled and diffing pre/post code; fix at the root; **re-add the fnptr-dispatch case to `SelfTest.HC`** (currently excluded). Fix doc 04 D30’s incorrect “missing `TOK_LPAREN`” explanation. Remove the Shell/DolDoc `U64 fn_addr` workarounds once fixed.
2. **HIGH — D29 array dimensions.** Add a shared `HcParseArrayDim()` (Compiler.HC) + `parse_array_dim()` (seed) folding `* / + - << >>` with overflow checks; replace all five inline parsers (`Compiler.HC:2585,2805,3459`; `jit_arm64.c:2010,2711`). Stop relying on literals.
3. **HIGH — Branch-range guards (P1.3).** Add ±1 MiB checks to `HcBackpatchCbz/Cbnz` (`Compiler.HC:1082-1095`) and the seed’s `patch_cbz`/`patch_b` (`jit_arm64.c:459-466`); emit thunks or hard-error on overflow.
4. **HIGH — P1.3 symbol resolution.** Store a normalized key so `SymLookupCanonical` (`Symbols.HC:274-307`) is O(1) instead of a 1024-bucket linear scan; migrate DJB2→FNV-1a. Keep census flat.
5. **MED — Silent compiler failures.** Emit `g_hc_error` for unknown members (`Compiler.HC:1833`), malformed struct defs (`2504,2510`), unknown IDENT types (`3425`), and functions without a `{` body (`3349-3352`); publish the function **after** its body parse to avoid dangling symbols.
6. **MED — P2.8 RedSea integrity.** CRC32C table (`0x82F63B78`, vector `0xE3069283`), per-block CRC, uberblock ring + monotonic `txg`, `DC CVAC`+`DSB SY` before commit (`RedSea.HC:292-366`).
7. **MED — Seed `#define` divergence.** Make `Compiler.HC`’s `#define` evaluator fold `/` (with comment-boundary awareness) and parentheses, or document and lint the restriction.
8. **MED — Gate/script hygiene.** Fix `p1-parity.sh` stale globals/modules (`:87-124`, deleted WM/Compositor) and the `ALL 32` marker (`:214`); raise `golden-boot.sh`’s SELFTEST floor (`:60`) to the real case count so tests cannot silently vanish.
9. **LOW — Repo hygiene.** Untrack `boot/uefi/*.o|a` (keep `crt_aarch64.o` or all via LFS), root `*.png`/`GEARS_BENCHMARK.LOG`, `docs/images/`, `screenshots/`; extend `.gitignore`; remove dead `&& 0` (`jit_arm64.c:1341`) and `__attribute__((unused))` stubs (`jit_arm64.c:469-487`); gate the `[DEBUG BASE]`/`[DEBUG-JIT]` prints behind a build flag.
10. **LOW — Typing sweep.** Replace `%d` with `%lld` for `I64` (e.g. `Exceptions.HC:251-253`).
