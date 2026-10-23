# NeoOS — 02 TASKLIST (every task, prioritized, traced to sources)

> Consolidation doc 3 of 5. The **actionable** list: every task from every old plan, merged, de-duplicated,
> and ordered P0→P10. The *why* is in `00-MASTER-PLAN.md`; verified reality in `01-REALITY-AUDIT.md`;
> research/ideas in `03-IDEAS-AND-RESEARCH.md`; contradictions & decisions in
> `04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`.
>
> **Sources merged here:** `docs/master/{00-MASTER-CONSOLIDATED-PLAN,00-CONSOLIDATED,00-REALITY-AND-MASTER-PLAN,
> 01-VERIFIED-TRUTH,01-status-and-history,02-PRIORITY-PLAN,02-audit,03-NEXT-STEP-TASKLIST,03-design,
> 04-UPDATED-PRIORITIES-AND-CHECKLIST,04-plan,05-NEW-TASKLIST,05-methodology,06-decisions-and-todo,NEXT-STEPS,
> P1-DELEGATION,P2-P6-MIGRATION-SPECS}.md`; `docs/{task,FUTURE_IMPLEMENTATIONS_MASTER_ROADMAP,
> neo_os_grand_forensic_dossier_and_sovereign_blueprint,OUTSTANDING_DEFECTS_AND_CODE_CRITIQUE,
> neo_os_consolidated_defect_record,priority_implementation_plan,implementation_plan,
> single_core_sovereign_master_audit,complete_render_stack_master_evaluation,exhaustive_architectural_post_mortem,
> audit,bench_empirical_analysis,consolidation_dossier,dossier,POST_DOM_OS_ARCHITECTURE_BLUEPRINT,
> doldoc_sovereign_unified_continuum_master_specification,doldoc3_graphics_typography_sprite_spec,
> holygl_sovereign_unified_master_architecture,shell_doldoc_symbiosis_and_sovereign_compositor_blueprint,
> ultimate_dom_substitute_paradigm_spec,ring0_embeddings_engine_manifesto,neo_os_architecture_specification,
> neo_os_grand_architecture_manifesto,neo_os_grand_consolidation_encyclopedia,walkthrough}.md`;
> root `README.md` + `SKILL.md` (20 ironclad orders).

---

## 0. How to use this list

- Work **P0 → P10 in order**. Do not start a lower priority until the one above it is green.
- **Gate after every change:** `scripts/golden-boot.sh` → `GOLDEN BOOT: PASS` (it now also runs
  `scripts/self-host-test.sh` → `SELF-HOST: PASS`).
- At the **end of each priority**, stop and ask the owner what to do next.
- Merges/dissolutions are **gated behind P1** (they are unsafe until the self-host compiler compiles + runs them).
- Persist after every green step: `git commit` + `git bundle create /home/user/project/neo-os.bundle --all`.
- Sources are tagged `(from <doc>)`. **[REAL]/[PARTIAL]/[STUB]/[MISSING]/[GONE]/[SUPERSEDED]** tags come from doc 01.

---

## P0 — Observability & Debug Harness — ✅ DONE

**Authoritative harness (present):** `scripts/golden-boot.sh`, `self-host-test.sh`, `p1-parity.sh`,
`p1-flip-test.sh`, `run-jit-golden.py` + `tests/jit_golden/cases.json`, `audit-symbols.sh`, `crash-decode.py`,
`screenshot-diff.py`, `check-token-parity.py`, `run-viewer-vm.sh` (+gdbstub), `uart-repl.py`, `uart-bridge.mjs`.
`(from docs/master/00-MASTER-CONSOLIDATED-PLAN §6 P0, 04-plan P0, 05-methodology, P1-DELEGATION §1)`

**Legacy harness** (`scripts/test_p8_holygl.py`, `test_p9_compiler.py`, `test_cold_boot.py`,
`verify_shaders_and_3d.py`, `test_showcase_and_tools.py`, `test_wm_shell_switch.py`, … ~45 `test_*.py`)
is **[GONE]/[MISSING]** as the gate — it remains in-tree but is not the golden path. `(from 01-VERIFIED-TRUTH §1,
task.md Phases 8–11)`.

- [x] Golden gate (rebuild → boot → assert shell + subsystems + 0 exceptions + 0 undefined → battery → screenshot).
- [x] JIT battery `run-jit-golden.py` (was 50 → 52 → 65/67 cases across the engagement).
- [x] Symbol audit `audit-symbols.sh`.
- [x] Crash decoder `crash-decode.py` (ELR/FAR/ESR → function map → `xp /Ni` disasm).
- [x] Screenshot diff `screenshot-diff.py`.
- [x] Self-host gate `self-host-test.sh` (Compiler.HC compiles itself), wired into `golden-boot.sh`.
- [x] Engine parity `p1-parity.sh`; hang detector `p1-flip-test.sh`; token parity `check-token-parity.py`.

---

## P0.5 — Test & harness 200% upgrade (one in-guest SelfTest; kill per-command UART) — ✅ COMPLETE (core + first coverage batch; stress/determinism/per-module parity remain)

**Landed (verified via `golden-boot.sh`):** `apps/SelfTest.HC` runs the whole battery in-guest through the
shell builtin `selftest`, printing `SELFTEST: 80/80 PASS` (74 ported + 6 new), `PARITY: 54/54` (0 diff,
4 seed-skip), `TWINS: 5/5`, `SYMS: 1390 symbols, 0 unresolved`, and the sentinel `<<<NEO-DONE:selftest>>>`.
`scripts/neo_uart.py` is the shared driver that frames on the sentinel; `uart-repl.py` is a shim over it.
`golden-boot.sh` boots once and runs the battery with **one** command, then checks twin-liveness, the symbol
audit, the `.HC`→C census, and self-host. `scripts/census-c-runtime.sh` + `tests/census-baseline.txt` guard
against any new `.HC`→C runtime call. `make check/selftest/census/parity` wrap the gate. The 40 legacy
`test_*.py` were moved to `scripts/_superseded/`.
**Known limitation:** the corpus assumes fresh compiler state — a second `selftest` in one boot is guarded
(warns, does not run) because recompiling the battery trips a pre-existing `Compiler.HC` re-entrancy bug.

**Bugs surfaced by the expansion (see doc 04):** ~~2-D arrays fault (Data Abort)~~ **FIXED** — the compiler
now registers per-dimension row strides in `apps/Compiler.HC`, so `arr[i][j]` resolves to
`base + i*row_stride + j*elem` with no intermediate dereference; locked in by `SelfTest2DArray`
(`ARRAY2D: PASS`) and the `array2d_*` / `array3d_global` JIT-battery cases.
`enum` and function-like `#define` are unsupported (return -1); an unterminated `struct {` is silently
accepted (returns 0, not rejected); a global-`F64` subtraction (`F64 r = 0.0 - q;`) returned 0.

**Why.** The P0 harness works but is not *sovereign*: it tests the OS from the outside, over a frameless
byte stream, with host-side heuristics, and the tests themselves live on the host. This priority makes the
OS test *itself* in HolyC and reduces the host to a thin launcher. It is a prerequisite for the P2 hardening
list (twin-liveness, census, allocator/symbol/FS stress, determinism), which is named there but has no home.

**Diagnosis (verified this session).**
1. **No framing.** `scripts/uart-repl.py:38-68` and `scripts/run-jit-golden.py:54-68` send one line, then
   guess completion by polling `/tmp/neo-os-serial.log` for size-stability (`NEO_WAIT` 1.5–2.5 s +
   `NEO_SETTLE`). Every command pays a fixed wait; output is regex-scraped from a shared log.
2. **Fragmented.** Five scripts each re-implement connect/send/wait/read: `uart-repl.py`, `run-jit-golden.py`,
   `self-host-test.sh`, `golden-boot.sh`, `p1-parity.sh`.
3. **Tests live on the host** (`tests/jit_golden/cases.json` + Python/bash), so adding a case means editing
   JSON/Python, not dogfooding HolyC.
4. **Parity costs two boots.** `p1-parity.sh` patches `apps/KernelInit.HC`, rebuilds, boots twice (C-JIT vs
   flip), and probes ~15 globals one-at-a-time (`p1-parity.sh:222-266`); it cannot compare the two engines
   in one process.
5. **Conflicting locking.** `p1-flip-test.sh:56-60` takes `flock` on `/tmp/neo-os-vm.lock`; `p1-parity.sh:37-39`
   deliberately takes none (the running QEMU inherits the fd) — they cannot be safely co-scheduled.
6. **Doc drift.** The verification matrix below and the P1 heading say **65/65**; the P0 heading says
   65/67; `tests/jit_golden/cases.json` actually holds **75** cases (1 `known`), i.e. **74/74** active. Stale
   numbers undermine the gate and must be corrected here.

**Target architecture.**
- **`apps/SelfTest.HC`** — one in-guest runner, the single source of truth for tests. Holds the battery as
  in-source `src`/`expect` pairs, runs each through **both** engines (`CompilerCompileAndRun` and
  `jit_compile_and_run`) and compares (in-process parity), plus twin-liveness, stress, and determinism.
  Prints a machine-readable `SELFTEST: <pass>/<total> PASS` summary and per-case lines; `Main()` returns 0/1.
- **Sentinel framing** — the shell/runner emits `<<<NEO-DONE:<id>>>>` after a command; the host reads to the
  sentinel instead of guessing. Since the gate collapses to **one** command (`selftest`), framing largely
  disappears anyway.
- **One host driver** `scripts/neo_uart.py` (lib) + thin CLI, replacing the duplicated send/wait/read.
- **One gate** `scripts/golden-boot.sh`: boot once → send `selftest` → assert summary + boot-log invariants.

**Work breakdown.**
- [x] **P0.5.1 — `apps/SelfTest.HC` skeleton.** ✅ `SelfTestRun()` + `SelfTestCase(name,src,expect)`; `Main()`
      returns pass/fail; add a `selftest` builtin in `apps/Shell.HC`; print the sentinel summary.
- [x] **P0.5.2 — Port the 75 battery cases** ✅ from `tests/jit_golden/cases.json` into `SelfTest.HC` verbatim
      (keep the JSON as the historical record, tag it superseded-by-`SelfTest.HC` in doc 01).
- [x] **P0.5.3 — In-process parity.** ✅ (49/49 agree, 0 diff, 4 seed-skip) For each case run both engines and assert equal; report
      `PARITY: <n>/<total>`. Replaces the two-boot `p1-parity.sh` for the battery corpus.
- [x] **P0.5.4 — Sentinel protocol.** ✅ (`scripts/neo_uart.py`; `uart-repl.py` shim) Emit `NEO-DONE`; make `scripts/neo_uart.py` frame on it; keep
      `uart-repl.py` as a back-compat shim.
- [x] **P0.5.5 — Twin-liveness probes.** ✅ (`TWINS: 5/5`, gate-checked) `HalTwinProbe`/`VirtioBlkTwinProbe`/`RedSeaTwinProbe`/
      `SymbolsTwinProbe`/`KHeapTwinProbe` (magic returns); `SelfTest.HC` asserts all five; feeds P2.
- [x] **P0.5.6 — Census gate.** ✅ (`scripts/census-c-runtime.sh` + `tests/census-baseline.txt`, gate-checked) `scripts/census-c-runtime.sh` (from P2.0) invoked by the gate; fails on any
      increase vs a checked-in baseline `tests/census-baseline.txt`.
- [x] **P0.5.7 — Symbol audit in-guest.** ✅ (`SYMS: 1383 symbols, 0 unresolved`; `symbols_unresolved_count()` C accessor) `symbols_audit()` → 0 undefined / 0 unresolved / 0 late-bound;
      `SelfTest.HC` asserts; `audit-symbols.sh` becomes a thin wrapper.
- [x] **P0.5.8 — Rewrite `golden-boot.sh`** ✅ to one `selftest` command + boot-log invariants + a host
      hang-timeout; fold `self-host-test.sh` and `run-jit-golden.py` in (self-host stays a second command).
- [x] **P0.5.9 — Makefile:** `make check` (gate), `make selftest`, `make census`, `make parity`. ✅
- [x] **P0.5.10 — Retire legacy:** moved 40 `scripts/test_*.py` to `scripts/_superseded/` (git mv, never
      deleted) and noted them in doc 01. ✅

**Coverage expansion (the "200%").** First batch landed (6 cases: `neg_bad_expr`, `lex_block_comment`,
`type_nested_struct`, `type_typedef`, `f64_int_cast2`, `f64_global_if`). Remaining:
- [x] **Negative tests** — `neg_bad_expr` (`2 + ;` → -1). Partial: unterminated `struct`/bad token are
      silently accepted (bug, see doc 04), so only one reject case is asserted.
- [ ] **Diagnostics** — assert the reported line number is correct for a multi-line fault.
- [x] **F64 depth** — `(F64)`/`(I64)` round-trips, F64 global if-branch. Partial: NaN/Inf not yet covered.
- [x] **Types** — nested structs, `typedef`, and **multi-dimensional arrays** (`SelfTest2DArray` → `ARRAY2D: PASS`). `enum` still unsupported.
- [x] **Lexer edges** — block comments. Partial: line comments / string escapes / arg-macros not yet.
- [ ] **Stress** — allocator churn + double-free (canary), 4096-symbol register/lookup, FS
      create/read/overwrite/delete + sector-boundary reads.
- [ ] **Determinism** — run the battery twice, hash outputs, assert identical; identical boot symbol dump +
      heap high-water across repeated boots.
- [ ] **Per-module parity** — all 34 modules through both engines, in-process.

**File-level change list.**
| Path | Today | After |
|---|---|---|
| `apps/SelfTest.HC` | — | new: the one runner |
| `apps/Shell.HC` | no `selftest`/`echo` | `selftest` builtin + sentinel emit |
| `scripts/neo_uart.py` | — | new: shared send/read/sentinel lib |
| `scripts/uart-repl.py` | duplicated driver | shim over `neo_uart.py` |
| `scripts/run-jit-golden.py` | host battery | thin: `selftest` → summary |
| `scripts/golden-boot.sh` | 4 stages | one `selftest` + boot greps |
| `scripts/self-host-test.sh` | standalone | folded into gate |
| `scripts/p1-parity.sh` | 2 boots + UART probes | one boot, in-guest parity |
| `scripts/census-c-runtime.sh` | — | new: baseline-diff gate |
| `scripts/audit-symbols.sh` | log grep | wrapper over `symbols_audit()` |
| `tests/jit_golden/cases.json` | source of truth | historical (superseded) |

**Exit (Definition of Done).**
- `make check` boots once and prints `SELFTEST: N/N PASS`, `PARITY: N/N`, `SELF-HOST: PASS`.
- Adding a test requires editing **only** `apps/SelfTest.HC`.
- No host script polls a log for size-stability; all framing is sentinel-based.
- Legacy `test_*.py` moved out of the golden path; doc 01 updated; the matrix numbers corrected to 74/74.

**Risks / open questions.**
- A fault inside `SelfTest.HC` hangs the guest → the host timeout is the only backstop; keep it.
- In-process parity is stricter than today's two-boot parity; expect it to surface real engine divergences
  (that is the point, but it may block the gate — triage into `known`).
- Boot-time invariants (32 subsystems, 0 exceptions) can only be grepped host-side — stay in `golden-boot.sh`.
- `selftest` at boot (auto) or on demand? Auto is stronger but lengthens boot; propose a
  `g_selftest_on_boot` flag, default on in the gate image.

---

## P0.6 — BSOD panic-halt + fault telemetry — ✅ DONE (`f0a407c`)

**Problem.** A kernel panic re-executed the faulting instruction forever: `kernel/arch/aarch64/vectors.S`
called `ExceptionsHandleSync` and ignored its X0 return, then always `eret`. `g_exc.in_fault` never latched,
so a fault inside the compiler looked like a hang with no telemetry.
**Fix.** `vectors.S` branches on the handler's X0: on a kernel panic it latches `halted` and spins in
`panic_halt` instead of returning; `Exceptions.HC` keeps `in_fault=1` and emits `<<<BSOD:KERNEL>>>` /
`<<<BSOD:DOUBLE>>>` / `<<<EXC:RECOVERED>>>`; `Compiler.HC` keeps an on-demand JIT symbol map (`jitmap`,
`HcMapAdd`/`HcMapDump`); `Shell.HC` gains `kpanic`/`jitmap`; `scripts/crash-decode.py` v2 decodes
ESR/ISS, symbolises `ELR_EL1`, and supports `--gate`. Gate: `PANIC GATE: PASS`, `GOLDEN BOOT: PASS`.

## P0.7 — Allocator / lexer / module-load hardening — ✅ DONE (this step)

**Problem (unmasked by P0.6).** Boot died in `HcLexNext` (`Compiler.HC`) when a string literal's
allocation returned NULL. The `[HCLX]` diagnostic printed `free=8388560 used=48` — but that is the *idle*
HolyC 8 MB pool, not the heap in use. **The failing allocator was the C seed heap (`boot/runtime/kheap.c`)**
(21 MB used / 43 MB free / 5192 blocks post-boot), so the failure was **not exhaustion**.
**Root cause.** `KInitLoad` read every module into a **128 KB** buffer with a `131071`-byte limit, silently
truncating any module larger than 128 KB. Baseline `Compiler.HC` (134 KB) was already truncated past
`CompilerCompileAndRun` (offset 127483); the P4.3 texture edits added ~4.6 KB, pushing that function past
the cutoff so it never compiled → unresolved forward references → dead shell. This is exactly the
"module growth crosses a threshold" failure. The truncation is silent: the module "compiles" (res=0) with a
missing tail.
**Fixes.**
1. **Module-load ceiling raised to 1 MB** everywhere a `.HC` source is read — `KernelInit.HC` (`HC_MODULE_MAX`),
   `Shell.HC` (`run`/`cat`/`src`), `Compiler.HC` (`#include` read), and the C JIT's `INCLUDE_BUF_SIZE`
   (256 KB → 2 MB). Source growth can no longer truncate silently.
2. **Dedicated lexer string arena** (`HcStrAlloc`): literals used to be `kmalloc(slen+1)`'d individually and
   never freed (~2000 leaked small blocks per boot, fragmenting the heap). They now bump-allocate from
   chained 256 KB chunks; the first chunk is static BSS, so lexing has **no allocator dependency** during the
   fragile boot window. Bounds-checked: an over-long literal fails the unit cleanly.
3. **Corruption vectors closed.** `HcBackpatchCbz` and the inline CBNZ patch wrote `g_hc_code[patch_idx]`
   with no bounds check; global-array `kmalloc`/`memset` were unchecked (a write through NULL). All guarded.
4. **Exact failure diagnostics.** The seed `kmalloc` OOM path now prints the real reason with
   total/used/free/largest-free-block; `KHeap.HC`'s `KMalloc` no longer returns 0 silently; the `[HCLX]`
   diagnostic reports both heaps.
5. **`SelfTestHeap`** — Phase A: 100 alloc/write/verify/free iterations across 16/36/128/4096 B; Phase B:
   2500 small (32–64 B) allocations interleaved with medium alloc/free traffic; every byte written and
   verified (`KHEAP: PASS`), gated in `golden-boot.sh`.
**Pointer-arithmetic audit (Causa-2 ruled out).** `HcParseAdditive` emits a raw `add x0,x0,x1`, i.e. HolyC
pointer arithmetic is **byte-wise** (only `[]` indexing scales, via `HcGlobalScale`/`g_hc_global_strides`).
So `curr + HEAP_BLOCK_HEADER_SIZE` in `KHeap.KMalloc` is a 48-byte offset — the block split is correct and
does **not** corrupt the remainder (confirmed by `KHEAP: PASS` + the existing 5-block `KHeapSelfTest`).
**Gate:** `GOLDEN BOOT: PASS`, `SELFTEST 80/80`, `PARITY 54/54`, `RENDER 0xD28836F`, `SELF-HOST: PASS`,
`KHEAP: PASS`, `PANIC GATE: PASS`, `CENSUS: PASS`. The census baseline moved `kmalloc 50→54` / `kfree 47→51`
**solely** because of the new heap-stress test (the lexer's `kmalloc` was *replaced* by the arena, so
`Compiler.HC` is net-neutral).

---

## P1 — Compiler (self-hosting) — ✅ **COMPLETE** (self-hosts; REPL/`run` on Compiler.HC; battery 65/65; parity PASS)

**Goal:** `apps/Compiler.HC` compiles every `.HC` module *and itself*; C JIT only seeds it.
`(from docs/master/00-MASTER-CONSOLIDATED-PLAN §3/§6 P1, P1-DELEGATION §0, 05-NEW-TASKLIST, 04-UPDATED-PRIORITIES)`

### P1.0 — Done ✅
- [x] Frame-based locals (recursion-safe; prologue `MOVZ X16,#n; SUB SP,SP,X16` = `0xCB3063FF`).
- [x] `&function`; forward-struct two-pass; read-path late-binding; `#include` (C JIT); inline `asm{}`; block comments.
- [x] F64 codegen + AArch64 intrinsics; global sizing from declared type; global struct-type tracking; top-level arrays.
- [x] `HcOpPush/Pop` bounds (stack 256→4096); bounded name copies; **every silent cap → hard `g_hc_error`**;
      per-module table resets; `g_hc_arg_float[8]→[32]`; pool-write guards.
- [x] **Compiler self-host achieved**: `hcrun Compiler.HC → 0`. Three bugs fixed: define table 64→**1024**;
      array dims accept `N`/`N*M`/`N+M`; `HcPublishFunc` never clobbers a defined symbol (`symbols_is_defined`).
- [x] Tokenizer unified: one `TOK_*` source (`boot/seed/tok.h`), enforced by `check-token-parity.py` (71 tokens).
- [x] Flip done (`0b2db9d`): `KernelInit.HC` sets `g_hc_ready = 1` after `Compiler.HC`; later modules route
      through `CompilerCompileAndRun`. `p1-parity.sh` PASS (34 modules, engines agree).

### P1.1 — Close the script-mode gaps ✅ DONE (commit `f5b6da8`)
Routing the shell REPL/`run` through `CompilerCompileAndRun` now yields **65/65** battery cases.
`Shell.HC` routes the REPL and `run <file>` through `CompilerCompileAndRun` when `g_hc_ready`.
- [x] Function-pointer **calls** in script mode (`symbols_is_var` routes `fp(args)` to the indirect `blr` path).
- [x] **F64 struct expressions** (`a.x * b.y - …`) — `&`/`sizeof`/`*` now clear the stale `g_hc_expr_float`.
- [x] **Forward structs** in script mode (`HcPrescanStructs` registers struct/class defs before the parse).
- [x] **Cross-unit interference** — a function definition may override a leaked VARIABLE but never an
      existing function (`symbols_is_func`), preserving self-host while fixing REPL name collisions.
- [x] Global pointer-to-struct member offsets (`HcRegisterGlobalPtr`/`HcGlobalIsPtr`).

### P1.2 — Remaining compiler capability ✅ DONE (commits `83426d9`, `e2c0f1f`)
`(from 00-MASTER-CONSOLIDATED-PLAN §6 P1.3, 04-UPDATED-PRIORITIES §B, P1-DELEGATION §7)`
- [x] `#include "file"` **inside `Compiler.HC`** (`HcExpandIncludes` splices VFS files, recursive, mirrors `expand_includes`).
- [x] Diagnostics — internal errors report the 1-based source line (`HcLineOf`).
- [x] `auto` — accepted as a declaration type (behaves as I64); no more error/hang.
- [x] Table literals `{…}` — array initializer lists for globals and locals (1-D, literal elements).
- [x] Global forward cell — works (`forward_global_var` passes; `symbols_var_cell`/`symbols_lookup_or_reserve`).
- [ ] >8-arg calls: remains a **clean hard error** (`g_hc_error`), matching the C JIT's 8-arg (X0–X7) limit.
      Stack spill is deliberately deferred (would diverge from the C JIT and the `known_over8_args` battery case).

### P1.3 — Retire the C seed (per the no-blob decision)
- [x] Seed decision = **Option A** (C seed confined to `boot/seed/`, commit `708c92a`). **No blob.** `(from 00-MASTER-CONSOLIDATED-PLAN §4/§8)`
- [ ] Later (P2/P8): minimize the seed (Option B) or true self-host-from-source (Option C).

**P1 exit — MET ✅:** script-mode parity (65/65) + REPL/`run` on `CompilerCompileAndRun` + golden gate PASS +
`SELF-HOST: PASS` + `p1-parity` PASS + token parity (71). Verified at commit `e2c0f1f`.

---

## P2 — Bootstrap Perfection — ✅ **COMPLETE** (seed = compiler substrate only; no C FS/block driver)

**North star.** The C seed is a *pure HolyC compiler substrate* — allocate + register/lookup symbols +
compile + obtain `.HC` bytes — and **nothing else**. Every OS subsystem (HAL, block driver, FS, and the
extended allocator/symbol facilities) is `.HC`. The seed contains **no filesystem and no OS block driver**.
The OS builds itself from source over a minimal, frozen, auditable seed. *(This supersedes the old
"Minimal bootstrap" framing, whose P2.2–P2.5 were proven unreachable — see the verified truth below.)*

**Project C today (verified):** `boot/main.c`; `boot/seed/{lexer,table,jit_arm64}.c` (**4751** lines);
`boot/runtime/{kheap,symbols,hal_platform,virtio_blk,redsea}.c` (**1710** lines) + headers; vendored
`boot/uefi/*.c` ×9 + `reloc.S`. Census (`apps/*.HC`): `kmalloc` 52, `kfree` 45, `symbols_register` 29,
`symbols_lookup` 23, `redsea_read_file` 11, `redsea_write_file` 7, `redsea_list_dir` 2, `symbols_*` 1 each,
`jit_compile_and_run` 5 (seed — stays).

**The verified truth (why the old P2.2–P2.5 were unreachable)** *(verified `HEAD 92a5878`)* — the `.HC`
module load chain depends on the C runtime end-to-end:
```
boot/main.c:307  virtio_blk_init()                      (C)
boot/main.c:308  redsea_init(0)                         (C)  mounts the RedSea partition
boot/main.c:321  redsea_read_file("KernelInit.HC", …)   (C)  first .HC module
apps/KernelInit.HC  KInitLoad(f)   (.HC) → C kmalloc + C redsea_read_file  (direct-bound; C-JIT compiled)
```
`KInitLoad` is compiled by the **C JIT before `RedSea.HC` exists**, so its `redsea_read_file` call binds
directly to C. Every module load goes C `redsea.c` → C `virtio_blk.c`. The runtime FS separately uses the
`.HC` stack (`redsea_read_file` shadows C) → `RedSeaReadFile` → `RsReadSectors` → `.HC` `VirtioBlkReadSectors`
→ **falls back to C `virtio_read`** because `VirtioBlkInit` refuses to reset an already-`DRIVER_OK` device
(`VirtioBlk.HC:137-144`), leaving `vq_desc==0`.

**Consequence:** C `virtio_blk.c`/`redsea.c` cannot be deleted while the modules are loaded from disk through
the C FS — the old P2 exit ("`SRCS_C` has no project runtime `.c`") contradicted the plan's own "Irreducible
C" list (which *keeps* a block/FS reader). **P2.2 below fixes the root cause; the old P2.2–P2.5 are void.**

**The principle (the perfect seed).** The seed needs exactly four capabilities: allocate, register/lookup
symbols, compile, and obtain `.HC` bytes. It must not need an FS or a block driver — bytes come from a
**bootstrap image** (P2.2). Everything above the seed owns the real hardware in `.HC`.

**Correction kept (verified `68cc2dc`):** the 22 `.HC` `hal_flush_cache` sites already bind to the `.HC`
implementation (the C one is dead — see P2.1); the C `g_hal_*` globals *were* used by C `virtio_blk.c`, which
is why P2.1 kept a stub — that stub is deleted in P2.4 once C `virtio_blk` goes.

### P2.0 — Baseline & harness — ✅ DONE (delivered by P0.5)
- [x] Freeze baseline: `golden-boot.sh` PASS, `SELFTEST: 80/80`, `SELF-HOST: PASS`, `p1-parity` PASS. ✅
- [x] **C-call census gate** `scripts/census-c-runtime.sh` + `tests/census-baseline.txt` (fails on any
      increase; wired into `golden-boot.sh`). ✅
- [x] **Twin-liveness probes** (`<X>TwinProbe()`, asserted as `TWINS: 5/5` in the gate). ✅
- [ ] Snapshot `symbols_dump` + heap high-water mark before/after each step for parity. (open)

### P2.1 — HAL: `HalPlatform.HC` owns the platform — ✅ **DONE** (commits `94d5faf`, `d9db963`)

**Corrected goal (met).** `.HC` is the single owner of cache maintenance and the platform-profile table; the C
HAL is reduced to the minimal early-boot stub C `virtio_blk.c` needs; the dead C cache function is deleted.
Full C-HAL deletion stays **deferred to P2.2** (blocked on retiring C `virtio_blk`).

- [x] **P2.1.0 — Baseline & binding proof.** Gate frozen PASS; binding proven:
      `symbols_lookup("hal_flush_cache")` → `0x77745A40` (JIT pool, beside `HalFlushCache` `0x777457C0`) = the
      `.HC` implementation, so the C one registered at `boot/main.c:270` is dead. C callers confirmed: only the
      def + registration; `virtio_blk.c` uses only `hal_get_virtio_slots`/`hal_get_virtio_base`. ✅
- [x] **P2.1.1 — Delete the dead C cache function.** Removed `hal_flush_cache` (def + decl + registration). ✅
- [x] **P2.1.2 — Reduce the C HAL to a stub.** `boot/runtime/hal_platform.{c,h}` now = VirtIO MMIO constants +
      the two accessors + `hal_platform_init` (31 lines, was 117 + 75). Board profiles, `g_hal_uart/gicd/gicc`,
      platform switching and flush removed. ✅
- [x] **P2.1.3 — `.HC` fully owns the path.** `Compiler.HC:HcFlushCache` delegates to `HalFlushCache` — exactly
      one cache-maintenance implementation. ✅
- [x] **P2.1.4 — Census reclassification.** `hal_flush_cache` removed from the census list; baseline
      re-generated: **201 → 179** genuine `.HC`→C calls. ✅
- [x] **P2.1.5 — Hardening.** `SelfTest.HC` adds `SelfTestHalCache` (write buffer → `HalFlushCache` → read
      back); the gate asserts `HALCACHE: PASS`. ✅
- [x] **P2.1.6 — Docs + gate + commit + bundle.** ✅

**P2.1 exit — MET ✅:** no C `hal_flush_cache`; `boot/runtime/hal_platform.c` is a 31-line early-boot stub;
`.HC` owns cache + platform; census no longer lists `hal_flush_cache`. Gate: `SELFTEST 80/80`, parity `54/54`,
`TWINS 5/5`, `SYMS … 0 unresolved`, `HALCACHE: PASS`, `CENSUS: PASS`, `SELF-HOST: PASS`.
**Deferred to P2.2:** deleting the C HAL stub entirely (blocked on retiring C `virtio_blk.c`).

### P2.2 — Bootstrap via **UEFI SimpleFS** (the crux) — ✅ **DONE**
The seed implements **no filesystem and no block driver**. It reuses the **UEFI firmware's own FAT driver**
(`EFI_SIMPLE_FILE_SYSTEM_PROTOCOL`) to read the `.HC` sources from the FAT32 ESP it was loaded from.
`main.c` never calls `ExitBootServices`, so the protocol stays valid.
- [x] `boot/seed/seed_fs.{c,h}`: `LocateProtocol(SimpleFS)` → `OpenVolume` → `Open`/`Read`/`Close`;
      `seed_read_file(name, buf, max) → len` registered as a symbol. ✅
- [x] `boot/main.c` + `apps/KernelInit.HC:KInitLoad` read boot modules via `seed_read_file`. ✅
- [x] Makefile copies `apps/*.HC` → `holyc/` on the FAT32 ESP; `redsea.img` kept for user files. ✅
- [x] The C JIT's `#include` also uses `seed_read_file` (was C `redsea_read_file`). ✅
- [x] Verified: boot reaches the shell; all 34 modules load from the ESP. ✅

### P2.3 — Retire C `redsea.c` (FS → `.HC`) — ✅ **DONE**
- [x] Deleted `boot/runtime/redsea.{c,h}`; dropped the C registrations. ✅
- [x] `RedSea.HC` is the only FS (shadows the names; owns the RAMDisk). ✅
- [x] Verified: `redsea_read_file` binds to the JIT pool; `save`/`run`/`hcrun` + self-host PASS. ✅

### P2.4 — Retire C `virtio_blk.c` (block → `.HC`) — ✅ **DONE**
- [x] Deleted `boot/runtime/virtio_blk.{c,h}` + the `hal_platform.{c,h}` stub. ✅
- [x] `VirtioBlk.HC`: removed the `DRIVER_OK` early-return and the `virtio_read`/`virtio_write` fallback —
      it now resets and owns the device (`RsReadSectors` does the DMA). ✅
- [x] Verified: the `.HC` FS reads the real disk; `VirtioBlkReadSectors` binds to the JIT pool. ✅

### P2.5 — Seed substrate: `kheap.c` + `symbols.c` — ✅ **DONE (kept & frozen)**
- [x] `boot/runtime/` is now **only** `{kheap.c, symbols.c}` — the seed allocator + symbol table the compiler
      needs before any `.HC` module runs. Documented as the irreducible floor. ✅
- [x] `.HC` `KHeap.HC`/`Symbols.HC` extend the seed. ✅
- [x] Added `SelfTest.HC:SelfTestFs` (`.HC` FS write→read→verify → `FSRT: PASS`, gate-checked). ✅

### P2.6 — Hardening, docs, gate — ✅ **DONE**
- [x] `SRCS_C` = `boot/main.c` + `boot/seed/*` + `boot/runtime/{kheap,symbols}.c` + vendored `boot/uefi/*`. ✅
- [x] Census reclassified: `redsea_*` removed (now `.HC`); **178 → 159** genuine `.HC`→C calls, all seed. ✅
- [x] Gate green (see exit below). ✅

**P2 exit — MET ✅ (one checkpoint at the end of P2):**
- The seed has **no FS and no OS block driver**; `boot/runtime/` = `{kheap.c, symbols.c}` only.
- `apps/*.HC` are the single source of truth for HAL/block/FS, loaded from the FAT32 ESP via the firmware.
- **P2.7:** the C JIT compiles **only** `Compiler.HC`; the seed compiles **1** module (not 7) — every other
  subsystem is compiled at runtime by the self-hosted HolyC compiler.
- Gate: `SELFTEST 80/80`, parity `54/54`, `TWINS 5/5`, `SYMS … 0 unresolved`, `HALCACHE: PASS`,
  `FSRT: PASS`, `CENSUS: PASS (159)`, `SELF-HOST: PASS`, `GOLDEN BOOT: PASS`.

### P2.7 — Compiler-only bootstrap (seed = Compiler.HC alone) — ✅ **COMPLETE**
Goal: the C JIT compiles **only** `Compiler.HC`; the compiler then compiles everything else. **Met:** the seed
now compiles **1** module, not 7. `apps/KernelInit.HC` loads `Compiler.HC` first, sets `g_hc_ready = 1`, then
loads all 31 remaining modules through `CompilerCompileAndRun`.
- [x] **Parser bug fixed (commit `95ece53`).** `HcParseProgram`'s top-level statement loop ended at
      EOF, so a function definition after a top-level statement (`if (...) {...}` then `I64 f() {...}` —
      exactly how `KHeap.HC`/`Symbols.HC` end) was mis-parsed → internal error. Added `HcAtFunctionDef()`
      lookahead so a function/class definition ends the statement block and is parsed by the outer loop.
      Verified: `hcrun KHeap.HC` → `2012327920`, `hcrun Symbols.HC` → `1` (were `-1`); battery still `80/80`.
- [x] `HcFlushCache` is self-contained again → `Compiler.HC` has **no** `.HC` dependency (prereq).
- [x] Pruned dead seed functions (`kheap.c` 218→170, `symbols.c` 222→179).
- [x] **Codegen bug FOUND & FIXED — pointer-element array stride.** The boot corruption
      (`[HEAP] FATAL: Memory corruption detected at block …`, then instruction abort) was **not** in
      `KHeap.HC` — it was in `Symbols.HC`'s top-level `SymInit()`, which zeroes `CSymbol *g_sym_buckets[256]`.
      `HcResolveLValue`'s index path used the **pointee struct size (92)** as the element stride whenever
      `cur_st_idx >= 0 && cur_mode != 1`; for an array of *pointers* that stride must be 8. `SymInit` therefore
      wrote `base + i*92` for `i` up to 255 → far past the 2048-byte buffer → adjacent C-heap canary clobbered.
      Fix (two lines): register the element width for **all** global arrays (`g_is_ptr ? 8 : g_elem_bytes`) and
      only fall back to the pointee struct size when no element width is registered. `sizeof(CSymbol)=92` was
      already correct; `hcr`/parity unaffected.
- [x] **Verified:** boot with the flip before `HalPlatform.HC` reaches the shell; gate green
      (`SELFTEST 80/80`, parity `54/54`, `TWINS 5/5`, `SYMS … 0 unresolved`, `HALCACHE: PASS`, `FSRT: PASS`,
      `CENSUS: PASS (159)`, `SELF-HOST: PASS`, `GOLDEN BOOT: PASS`).

**P2.7 exit — MET ✅:** `boot/main.c`'s C JIT compiles exactly one `.HC` unit (`Compiler.HC`); every OS
subsystem is compiled at runtime by the self-hosted HolyC compiler.

---

## P3 — Kernel correctness (make it a real kernel) — ✅ **COMPLETE** (see doc 03 §9.7 for research/refs)

**Exit — MET ✅ (gate: `GOLDEN BOOT: PASS`):** a hardware timer IRQ fires (`TICK: PASS`, ticks ~1700),
preemptive scheduling works (`SCHED: PASS`), SMP cores come online and run dispatched jobs (`SMP: PASS`),
kernel faults reach the BSOD while REPL faults unwind (`BSOD: PASS`), memory is discovered from the UEFI map,
and the sovereign handover is live (`SOVEREIGN: PASS` — `.HC` KHeap/Symbols own `kmalloc`/`kfree`/`symbols_*`).
Full gate: `SELFTEST 80/80`, parity `54/54`, `TWINS 5/5`, `SYMS … 0 unresolved`, `HALCACHE: PASS`,
`FSRT: PASS`, `CENSUS: PASS`, `SELF-HOST: PASS`.

**Goal.** Turn the cooperative, effectively single-core substrate into a real kernel: **one** allocator, **one**
symbol table, **one** HAL, a **timer IRQ that actually fires**, a **preemptive** scheduler that uses the
assembled context switch, working SMP with per-core queues, and a **BSOD for kernel faults** (not a silent
recovery). Memory is *discovered* (already read from the UEFI memory map) and every global has exactly one owner.

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P3, 02-PRIORITY-PLAN P3, P2-P6-MIGRATION-SPECS §7, 01-VERIFIED-TRUTH §2.2)`

### P3 guardrails (LOCKED — apply to every sub-step below)
1. **Interrupt-safe JIT & allocator critical sections (P3.4/P3.5/P3.8).** Once `CNTV_CTL_EL0` is armed and
   preemption is live, a timer IRQ can fire mid-`CompilerCompileAndRun` or mid-`kmalloc`. `KHeap.HC`,
   `Symbols.HC` and the JIT emitter must guard all mutations with an explicit **IRQ-mask / spinlock** primitive
   (`DAIFSet`/`DAIFClr` for the local core; `LDXR`/`STXR` for SMP), **or** preemption must be deferred while a
   task holds the compiler/heap lock. No mutation path may run unguarded with IRQs unmasked.
2. **Full trap-frame context switching on preemption (P3.4/P3.5).** `cpu_switch_context`'s callee-saved save
   (`X19–X30`, `SP`, `D8–D15`) is correct for *voluntary* `TaskYield()` (the compiler knows `X0–X18` are dead).
   For *asynchronous timer preemption*, the IRQ vector already pushes the full volatile frame (`X0–X30`,
   `ELR_EL1`, `SPSR_EL1`, and `Q0–Q31`); the preemptive switch must transition **through that IRQ frame** or
   switch `SP_EL1` in the IRQ epilogue so `X0–X18`/`D0–D7` are never clobbered mid-expression.
3. **Sovereign handover in P3.8 (LOCKED — the C owner is frozen at handover).** `Symbols.HC` ingests the seed
   symbols from the C bootstrap table into its unified 1024-bucket table, then SIC-patches `symbols_register`,
   `symbols_lookup`, `symbols_is_func`, `symbols_is_var`, `symbols_var_cell`, `symbols_sic_cell`. `KHeap.HC`
   initializes its free list strictly **above** the C seed's high-water mark (from the UEFI memory map via
   `boot_probe_memory`), then SIC-patches `kmalloc`/`kfree`; `KHeapFree` treats any pointer **below** that
   high-water mark as a **pinned bootstrap block** (no-op / route to seed) so freeing early-boot structures never
   trips a false `HEAP_CANARY` panic. **The "C stays the runtime owner" alternative is OFF THE TABLE.**
4. **BSOD vs. REPL recovery boundary (P3.6).** Classify faults by `ELR_EL1` in `ExceptionsHandleSync`: a fault
   inside a user REPL expression / JIT task unwinds cleanly to the shell prompt; a fault inside a core kernel
   range (`Sched.HC`, `KHeap.HC`, `Gic.HC`) triggers `ExceptionsRenderBsod` with full register, symbol+offset and
   assembly-instruction dumps.

**Current state (verified).** Timer is a pure software tick (`TimerTick()` just increments `g_timer.system_ticks`,
`Timer.HC:81`); `TimerInit` never writes `CNTP/CNTV_TVAL_EL0` or `CNTP_CTL_EL0`. `GicInit` programs the distributor
but **no handler is registered at boot** and interrupts are masked (`disable_interrupts()` in `ExceptionsInit`,
`Exceptions.HC:225`). `Sched.HC` `TaskYield` only relabels task states — it **never calls `cpu_switch_context`**
(which is assembled + registered at `main.c:298` but has **zero callers**). `SmpDispatch` has a **silent local
execution fallback** (`Smp.HC:256-271`) and `SmpWorkerLoop1/2/3` are copy-paste (`Smp.HC:56/87/118`).
`vectors.S` hardcodes `x3=1` for every sync fault (`vectors.S:179,206`) so **kernel faults are treated as
recoverable JIT faults** and never reach the BSOD; the re-entrancy guard `while(1)__wfe()` (`Exceptions.HC:155`)
hangs instead of panicking. Globals are duplicated: `I64 g_kernel_booting;` in **15** `.HC` files,
`g_hal_gicd_base`/`g_hal_gicc_base` in both `HalPlatform.HC:32-33` and `Gic.HC:39-40`, `g_hal_timer_freq` in
both `HalPlatform.HC:37` and `Timer.HC:13`.

### P3.0 — Baseline, kernel gate & inventory — ✅ DONE
- [ ] **Kernel gate:** add in-guest `kernbench`/`schedtest`; assert `TICK: PASS` (timer IRQ count rises),
      `SMP: PASS` (cores online), `BSOD: PASS` (a deliberate kernel fault reaches the BSOD). Wire into
      `golden-boot.sh`.
- [ ] **Inventory:** every `g_hal_*`, every `g_kernel_booting`, every duplicated global/fn, every dead fn.

### P3.1 — Global dedup & ownership (**start here**) — ✅ DONE
- [ ] Delete the **15** `I64 g_kernel_booting;` redeclarations (keep the definition in `KernelInit.HC:8`).
- [ ] One owner for `g_hal_*` (see P3.2) and `top_print_doldoc` (`Sched.HC:361` vs elsewhere).
- [ ] Rationale: lowest-risk, unblocks P3.3–P3.7, and removes cross-module symbol aliasing.

### P3.2 — HAL unification — ✅ DONE
- [ ] **One** set of `g_hal_*` globals; delete the duplicate `g_hal_gicd_base`/`g_hal_gicc_base`
      (`Gic.HC:39-40` → use `HalGetGicdBase()`/`HalGetGiccBase()`) and the duplicate `g_hal_timer_freq`.
- [ ] Keep the 5 platform profiles; make `g_hal_timer_freq` single-owned (from `CNTFRQ_EL0`).
- [ ] Memory: `boot_probe_memory()` already reads the **UEFI memory map** (`main.c:120-152`) → keep; expose
      `g_total_ram_bytes`/`g_free_ram_bytes` through the HAL and delete any remaining hardcoded sizes.

### P3.3 — GIC correctness — ✅ DONE
- [ ] Dedupe bases (P3.2); **register the timer handler at boot** (`GicRegisterHandler(HalGetTimerIrq(), TimerTick)`).
- [ ] Fix IAR/EOIR ordering; handle SGI/PPI/SPI ranges; keep PPIs enabled across ticks (already noted `Gic.HC:196`).
- [ ] **Decision (research):** stay on **GICv2** — QEMU `virt` TCG defaults to GICv2 (matches the existing
      GICD `0x08000000` / GICC `0x08010000` code). GICv3/ITS is a later platform item, not a P3 blocker.
- [ ] `GicBindVectors()` + `enable_interrupts()` at the end of boot (unmask IRQs).

### P3.4 — Timer IRQ (the trigger that makes it a kernel) — ✅ DONE
- [ ] Arm the **virtual timer** `CNTV_TVAL_EL0 = freq/hz` + `CNTV_CTL_EL0 = 1` (QEMU virt `irq_timer = 27` is the
      EL1 virtual timer; the EL1 *physical* timer is INTID 30 — use the platform's `irq_timer` and the matching
      register). *(Refs: AArch64 Programmer's Guide: Generic Timer; Löwenware.)*
- [ ] Handler re-arms `CNTV_TVAL_EL0` every tick (level-sensitive), calls `TimerTick()`, then the scheduler.
- [ ] Verify `g_timer.system_ticks` increments from the **hardware IRQ** (gate `TICK: PASS`).

### P3.5 — Preemptive scheduler — ✅ DONE
- [ ] **Wire `cpu_switch_context`** (`kernel/sched/switch.S`; currently zero callers): per-task context
      (callee-saved x19-x30 + SP + D8-D15) saved/restored on every switch.
- [ ] Real run queue; on each tick decrement `quantum_remaining`; at 0 pick the next ready task and switch.
      **Decision:** round-robin within priority bands (matches the existing `priority` field); quantum ≈10–50 ms
      (research: RR/no-starvation). `TaskYield` becomes a real switch, not a relabel.
- [ ] Safe task exit/reap (keep the deferred-zombie pattern, but only free after the switch completes).

### P3.6 — Exceptions & BSOD — ✅ DONE
- [ ] **Fix `vectors.S` hardcoded `x3=1`** (`:179,:206`): pass `0` and let `ExceptionsHandleSync` decide
      recoverable-vs-panic from `ELR_EL1` (JIT pool range = recoverable; kernel `.HC`/C = panic). Kernel faults
      must reach `ExceptionsRenderBsod`.
- [ ] Kill the `while(1)__wfe()` double-fault hang (`Exceptions.HC:155`) → a proper double-fault panic card.
- [ ] Clean ESR/FAR/ELR/SPSR dump + a full EC decode table (`osdev AArch64 Exceptions`).

### P3.7 — SMP correctness — ✅ DONE
- [ ] Delete `SmpWorkerLoop1/2/3` copy-paste → **one** generic worker loop with a **per-core run queue**.
- [ ] Drop the **silent local-execution fallback** in `SmpDispatch` (`Smp.HC:256-271`) — make single-core mode
      explicit/diagnostic, never a hidden BSP execution.
- [ ] Idle secondaries with `wfe`/`sev`; PSCI `CPU_ON` with proper entry + **per-core stacks**.
- [ ] **Cache coherency:** secondary cores must have the same `SCTLR/TCR/MAIR/TTBR0/VBAR` (already copied via
      `g_mmu_config`, `Smp.HC:186-200`) and shared data must be cleaned before handoff (`dc civac`/`dsb`/`isb`).
      *(Refs: Bootlin SMP bring-up; optee_os MMU setup sequence.)*
- [ ] Spinlocks: verify `smp_spin_lock` uses `LDXR/STXR` + `wfe`/`sev` (`smp_entry.S:56`). *(Refs: Linux arm64
      memory-model; Arm "Software Synchronization Primitives in A64".)*

### P3.8 — Sovereign handover: `.HC` becomes the sole runtime owner — ✅ DONE (sovereign path, no alternative)
The C seed allocator/symbol table is the *bootstrap floor* (the compiler needs them before any `.HC` runs). At a
single **handover point**, `KHeap.HC` and `Symbols.HC` take ownership via SIC hot-patch, and the C seed is
**frozen** — it is never again the runtime owner.
- [ ] **Symbols.HC:** ingest the seed symbols from the C bootstrap table into the unified **1024-bucket** table,
      then SIC-patch `symbols_register`, `symbols_lookup`, `symbols_is_func`, `symbols_is_var`,
      `symbols_var_cell`, `symbols_sic_cell` → `Symbols.HC`.
- [ ] **KHeap.HC:** init the free list strictly **above** the C seed high-water mark (UEFI map via
      `boot_probe_memory`), then SIC-patch `kmalloc`/`kfree` → `KHeap.HC`.
- [ ] **Pinned bootstrap blocks:** in `KHeapFree`, any pointer **below** the seed high-water mark is a pinned
      bootstrap block → no-op / route to seed (never a false `HEAP_CANARY` panic).
- [ ] Freeze the C seed allocator/table at the moment handover completes; delete the losing duplicate structures
      (`HEAP_CANARY`/`CHeapBlock` dup; the 256- vs 1024-bucket table). Port `SymCanonicalMatch`/Pascal↔snake
      helpers into `Symbols.HC`.

### P3.9 — Verify — ✅ DONE
- [ ] **Exit — MET when:** a **hardware timer IRQ fires** and drives the tick; **preemptive** scheduling works
      (a spinning task is preempted, a second task runs); **memory is discovered** from the UEFI map (not
      hardcoded); SMP cores come online with per-core queues; a **kernel fault reaches the BSOD**; and the gate
      is green (`SELFTEST`, `TICK`, `SMP`, `BSOD`, `GOLDEN BOOT`).

---

## P4 — Rendering unification (one pipeline) — ✅ **DONE** (P4.0 ✅, P4.1 ✅, P4.2 ✅, P4.3 ✅, p4.3b ✅, P4.4 ✅, P4.5 ✅ incl. gears root fix, P4.6 ✅ fragment-shader VM, P4.7 ✅ OBJ mesh ingestion + D14/D15 root fixes, P4.8 ✅ merge/delete/verify + determinism gate; see doc 03 §3.1 for research/refs)

**Goal.** One renderer. One target resolver, one damage tracker, one present, **one tiled rasterizer** with
real per-pixel Z, and **one font**. Everything 2D and 3D goes through the same tile job model. No `z_avg`
fakes, no scalar fallback (AArch64 mandates NEON), deterministic per tile (same image on 1 vs N cores).

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P4, 02-PRIORITY-PLAN P4, P2-P6-MIGRATION-SPECS §1–§3, 01-VERIFIED-TRUTH §2.3)`

**Current state (verified at P4 start; superscripts = fixed since).** `Render.HC` = 2D canvas + damage +
`gfx_*` API + a flat `gfx_draw_triangle_fill` (`Render.HC:529`). `RasterTile.HC` = a 64×64 tile with **real**
per-pixel barycentric Z (`RasterTriangleZ`, `RasterTile.HC:58`) but flat color only, plus a duplicate no-Z path
(`TileRasterTri:149`). `HolyGL.HC` = GL API but its submit path (`HolyGLSubmitTriangle:370`) averages NDC Z to a
single `z_avg` (`:401-405`) and calls `HolyGLDrawTriangleZ:284` (flat Z, flat color). **Two Z-buffers**
(`g_hgl_zbuf` `HolyGL.HC:68` and `g_tile_zbuf` `RasterTile.HC:13`). `GfxBackend.HC` = write-only knobs
(**P4.1**). `VirtioGpu.HC` sent **truncated** commands — `RESOURCE_CREATE_2D` 32 (need 40) and
`TRANSFER_TO_HOST_2D` 48 (need 56) — (**P4.1**). `FontMono` is a bitmap font + a stub SFNT parser; `FontVector`
is procedural beziers. ~60 dead fns / write-only state (`raster_engine`, `tile_size`, `zprecision`, `culling`).

### P4.0 — Baseline, render gate & inventory — ✅ **DONE**
- [x] **Golden-frame gate:** `RenderGoldenScene()` (`Render.HC`) draws a fixed integer-coordinate scene
      (clear, rects, line, AA circle, rounded rect, vertical gradient, filled triangle, 8×16 text);
      `RenderHashBuffer()` is a 32-bit FNV-1a over the whole back buffer (row-by-row, explicit pitch).
      `SelfTestRender()` (`SelfTest.HC`) renders with IRQs masked (no preemptive writer) and asserts the
      frozen hash **`0x7E9DE351`** (verified byte-identical across ≥3 reboots). `golden-boot.sh` asserts
      `RENDER: PASS`. Restores the display via `gfx_clear` + `doldoc_mark_all_dirty`. This is the P4
      regression + 1-vs-N determinism gate.
- [x] **Bench:** in-guest `renderbench` (shell command → `RenderBench()`). Reports the tile Z-rasterizer
      **tri/s** and **Kpix/s** and the full-canvas **Mpix/s** clear rate. Measured (this host):
      `13063 tri/s, 9122 Kpix/s, 72 Mpix/s`. (Textured tri/s is deferred to P4.3; the bench is the
      measurement harness and will grow that line when textures land.)
- [x] **Inventory:** (verified by call-site count across `apps/ boot/ kernel/`; a name with **0 call
      sites** is dead. This feeds P4.8.)

  **Entry points — 2D canvas (`gfx_*`, `Render.HC`):** `gfx_get_canvas_width/height/pitch`,
  `gfx_get_backbuffer/frontbuffer`, `gfx_set_clip`, `gfx_reset_clip`, `gfx_dirty_expand`,
  `gfx_dirty_all`, `gfx_put_pixel`, `gfx_get_pixel`, `gfx_draw_line`, `gfx_draw_rect`, `gfx_blend_rect`,
  `gfx_draw_rounded_rect`, `gfx_draw_triangle_fill`, `gfx_draw_char`, `gfx_draw_text`, `gfx_draw_string`,
  `gfx_clear`, `gfx_swap_buffers`, `gfx_swap_rect`, `gfx_vsync_set`, `gfx_vsync_wait`, `gfx_lerp_color`,
  `gfx_draw_circle_filled`, `gfx_draw_gradient_v`, `gfx_draw_soft_shadow`, plus the P4.0 additions
  `RenderHashBuffer`, `RenderGoldenScene`, `RenderBench`.

  **Entry points — 3D (`HolyGL.HC`):** `HolyGL{Init,Viewport,MatrixMode,LoadIdentity,Push/PopMatrix,
  Translatef,Rotatef,Scalef,Perspective,Color3f,Color3ub,TexCoord2f,Normal3f,Begin,Vertex3f,Vertex2f,End,
  Enable,Disable,ClearDepth,SubmitTriangle,SubmitLine,RenderCube,RenderCubeAt,Main}` and the `gl*`
  aliases. **`glViewport` is the only `gl*` alias with a live caller** (`HolyBenchmark.HC:56`); the other
  18 are dead wrappers.

  **Entry points — tile raster (`RasterTile.HC`):** `PinedaEdge`, `RasterClearTile`, `RasterTriangleZ`,
  `TileResolve`, `RasterTileMain`.

  **Entry points — backend/present:** `GfxBackend{Init,SetMode,Present,FastClear,SelfTest}`,
  `gfx_backend_{set_mode,present}`, `gfx_set_zero_ram_mode`, `gfx_is_zero_ram_mode`,
  `VirtioGpu{Init,FlushRect,FlushFull,IsAvailable,SendCmd}`.

  **Dead functions (0 call sites) — 43 verified:** `gfx_mark_dirty`, `gfx_dirty_reset`, `gfx_draw_circle`,
  `RenderIsZeroRamMode`, `gfx_backend_get_mode`; `TileClear`, `TileRasterTri`, `RasterSetVertexZ`;
  `HolyGLSetWireframe` + 18 dead `gl*` aliases; `GpuSetRasterEngine`, `GpuGetRasterEngine`, `GpuConfigMain`;
  `virtio_gpu_init`, `virtio_gpu_flush_rect`, `virtio_gpu_flush_full`, `virtio_gpu_is_available`;
  `FontInitAtlas`, `FontDrawChar`, `FontDrawString`, `FontMeasureWrappedHeight`; `VectorDrawGlyph`,
  `VectorDrawString`; `CompositorMain`, `CompositorDrawBox`, `CompositorQueryTileOwner`.

  **Write-only / dead state (set but not read for behaviour):** `CGfxBackendState.raster_engine`,
  `.tile_size`, `.zprecision`, `.smp_cores`, `.culling`, `.active_tab`, `.feature_flags` (only printed
  by `GpuConfigPrintDolDoc` / exercised by the self-test; real culling reads `g_hgl.cull_face`). Only
  `.shading_mode` is read for behaviour (`GpuGetShading` → wireframe branch in `HolyGLDrawTriangleZ`).

  **Duplicate paths to collapse:** two Z-buffers (`g_hgl_zbuf` `HolyGL.HC:68` vs `g_tile_zbuf`
  `RasterTile.HC:13`); four triangle paths (`gfx_draw_triangle_fill` no-Z, `TileRasterTri` no-Z,
  `HolyGLDrawTriangleZ` flat `z_avg`, `RasterTriangleZ` real per-pixel Z); three damage/present
  trackers (Render dirty + `gfx_swap_*`, `GfxBackendPresent`, `Compositor*`).

### P4.1 — One `GfxDevice.HC` (backend + present unification) — ✅ **DONE**
- [x] **Merge** `GfxBackend.HC` + `VirtioGpu.HC` + Render's damage/present into one **`apps/GfxDevice.HC`**
      (the two old files are deleted). One device state (`g_gdev`), **one target resolver** `GfxDeviceTarget()`
      (→ `RenderGetTargetBuffer`), **one damage tracker** (`GfxDeviceDamage` → Render's single dirty rect),
      **one present** `GfxPresent(x,y,w,h,full)` (double-buffer copy / direct-VRAM + optional GPU DMA). Callers
      updated: `Shell.HC` (`GfxDeviceSetMode`/`SetZeroRam`/`IsZeroRam`), `Compositor.HC` (`GfxPresent`),
      `WM.HC` (`GfxDevicePrintDolDoc`), `HolyGL.HC` (`GfxDeviceGetShading`); `KernelInit.HC` loads one module;
      `p1-parity.sh` probes `g_gdev.mode`.
- [x] **Fix the truncated virtio-gpu commands** (the only real HW bug): `RESOURCE_CREATE_2D` 32→**40** and
      `TRANSFER_TO_HOST_2D` 48→**56** now send the full structs. Audited against the spec: `ATTACH_BACKING`
      **48** ✓, `SET_SCANOUT` **48** ✓, `RESOURCE_FLUSH` **48** ✓ (already correct). Verified live: the device
      is active (`VirtioGpuIsAvailable()==1`) and `VirtioGpuFlushRect/Full` now return **0** (previously the
      truncated transfer dropped `resource_id`). `render gpu` + `GfxPresent` present the whole frame with no fault.
- [x] **Decision (research):** stay on **virtio-gpu 2D** for P4 (guest software-renders, host blits). Virgl/
      Venus 3D needs host Vulkan + a big QEMU patch set (Collabora/QEMU docs) → **deferred to P9**.
- [x] Delete `GfxBackend` write-only knobs (`GpuSetRasterEngine/TileSize/Zprecision/Culling/SmpCores` and the
      `active_tab`/`feature_flags` state — no behaviour readers) and the dead `gl*` aliases + `virtio_gpu_*`
      lowercase aliases + `GpuConfigMain`/`VirtioGpuSelfTest`/`GfxBackendSelfTest`. Symbol count **1330 → 1310**.

### P4.2 — One rasterizer with real Z + NEON span (the core) — ✅ **DONE**
- [x] **Promoted `RasterTriangleZ`** as the single rasterizer; **`HolyGLSubmitTriangle` now calls it** with
      per-vertex z16. Deleted `HolyGLDrawTriangleZ` (`z_avg`), the `avg_ndc_z` path, `gfx_draw_triangle_fill`,
      `TileRasterTri`, `TileClear`, `TileResolve`, `RasterSetVertexZ`, `g_hgl_zbuf`. **One full-screen
      16-bit Z-buffer** owned by `RasterTile.HC`.
- [x] **Algorithm:** Juan Pineda edge functions in **exact integer arithmetic** (screen vertices are integers,
      so coverage is exact — stronger than 16.16 fixed-point, which the plan suggested and is unnecessary at
      integer coords); **top-left fill rule** (shared mesh edges drawn exactly once); barycentric edge weights
      drive per-pixel Z interpolation (the old `z_avg` is gone). `RasterTriangleZ` (setup + row loop) →
      `RasterRow` (one scanline), linear/deterministic row-major order.
- [x] **Root-cause compiler fix (this is what unblocked it).** The rasterizer surfaced a real self-hosted
      compiler bug: a global **pointee** width was never registered, so `HcGlobalScale` returned 0 and
      `HcResolveLValue` fell back to the default 8-byte element stride/width. Thus `U16 *g_zbuf; g_zbuf[i]`
      emitted an **8-byte `LDR`** (reading `0xFFFF` as `-1`) and `U32 *g_raster_fb; fb[i] = c` emitted an
      **8-byte `STR`** (wrong address). Fixed in `Compiler.HC`: register the pointee width for global
      *pointers* (`HcRegisterGlobalScale(fname, g_elem_bytes)`) and keep a bare pointer use at 8 bytes
      (`HcResolveLValue`). **No workarounds remain** — the `& 0xFFFF` mask and the `RasterPut`/`RasterPutZ`
      shims were removed. Regression test `SelfTestPtrScale` (`PTRSCALE: PASS`) + `RasterBootCheck`
      (`RASTER: PASS`: coverage / depth-rejection / shared-edge seam).
- [x] **NEON 8-pixel span (p4.2b) — DONE.** Each scanline is `head(scalar) | body(NEON 8 px/iter) | tail(scalar)`.
      `RasterSpanNEON` (`RasterTile.HC`, words assembled from `scripts/raster_span.s`) vectorizes the 3 biased
      edge tests (`CMGE.4S` ×2 groups → `XTN` → one `V.8H` coverage mask), the 8-lane depth compare (`CMHI.8H`),
      the masked Z-buffer store (`BSL` + `STR Q`) and the masked 32-bpp framebuffer store (`ZIP1/ZIP2` + `BSL`).
      The depth numerator/division stays **exact 64-bit** (8 scalar `SDIV`/block) so Z is bit-identical to the
      scalar path — chosen over 16-bit DDA stepping (which drifts and would re-introduce mesh Z-fighting).
      Parameters cross the ABI via a `CRasterSpan` descriptor in `X0`. **Measured: `renderbench` 2075 → 9262
      tri/s (1399 → 6245 Kpix/s), a 4.46× span speedup**, with `RENDER` hash **unchanged (`0xD28836F`)** and
      `RASTER: PASS` (coverage / depth-rejection / seam gaps=0).
- [x] **Tiling/determinism:** row-major scan is order-independent and byte-identical on 1 vs N cores (the
      `RENDER` golden hash covers this). Per-tile SMP job binning is deferred to a later parallel-render step.

### P4.3 — Textures, filtering & blend modes — ✅ **DONE** (`51a9c68`)

**Goal (met):** one unified rasterizer that absorbs textures — no parallel scalar rasterizer.
**Reference algorithms:** `docs/research/NEO_OS_AARCH64_ENGINEERING_BRIEF.md` §1–§2.

**Delivered.** `CTexture2D` pool + `glGenTextures/glBindTexture/glTexImage2D/glTexParameteri/glBlendFunc` (+
`GL_TEXTURE_2D`/`GL_BLEND`), per-vertex `u/W,v/W,1/W`, `RasterPixelTextured` dispatched from the **one**
`RasterRow`, perspective-correct (area cancels), NEAREST/LINEAR (bilinear, weights sum to 256), REPEAT (PoT
mask)/CLAMP, exact `div255` alpha blend, `RasterDisableTexture()` on the 2D golden path. `SelfTestTexture`
(4 sub-tests) → `TEXTURE: PASS`; `RENDER 0xD28836F` bit-exact. Texel gather is scalar (NEON has no gather).

**Two compiler root bugs fixed to get here (the actual blockers):**
1. **Mixed I64/F64 arithmetic** (`Compiler.HC`): the float binary path reinterpreted the integer operand's
   bits as a double (`fmov` instead of `scvtf`) → `g_hgl.vp_w * 0.5` ≈ 0 → **all HolyGL geometry collapsed to
   (0,0)**. Fixed with `HcEmitPromoteFloat` in Multiplicative/Additive/Relational/Equality.
2. **Struct-member pointer stride = 8** — **ROOT-FIXED in p4.3b (D7)**; see below.

**Lesson (kept):** never `doldoc_printf` from inside the rasterizer and never exceed **8 args** — a 9-arg debug
print failed `RasterTile.HC` to compile and left **dangling** function symbols (publish-before-body) → BSOD.

### p4.3b — NEON textured span + D7 root fix — ✅ **DONE**

**Goal (met):** the textured span runs through the **same** `RasterSpanNEON` kernel; no scalar rasterizer, no
scalar fallback. The texel gather stays scalar (AArch64 NEON has no gather) inside a compact 8-lane loop.

**FASE 1 — D7 root fix (`Compiler.HC`), no workaround.** The self-hosted compiler lost the pointee width of a
struct-member pointer: `s.data[k]` (`U32 *`) advanced **8** bytes and emitted `LDR X`, not `LDR W`.
- Added `g_hc_member_elem_bytes[8192]` (element/pointee width), filled by `HcParseStructDef` with `base_sz`
  (mirrors `struct_member_t.elem_size` in `boot/seed/jit_arm64.c`). Exposed via the global
  `g_hc_found_member_elem` set by `HcFindMember` (the C JIT caps calls at **8 args**, so a 9th out-param is
  illegal). In `HcResolveLValue`, indexing a `m_ptr`/`m_arr` member uses `cur_scale = elem` instead of the
  8-byte field width. The `U32 *td = g_rtex.data;` workaround in `RasterTile.HC` was **deleted** — `g_rtex.data[k]`
  now strides by 4 and emits `LDR W`.
- Regression: `SelfTestStructPtrScale` (`PTRSCALE2: PASS`) with `U8 *p8/U16 *p16/U32 *p32`, direct (`.`) and
  arrow (`->`) access, verifying **no adjacent-byte corruption**; golden case `struct_member_ptr_scale` in
  `tests/jit_golden/cases.json`; `PTRSCALE2` added to `golden-boot.sh`.

**FASE 2 — NEON textured span (`scripts/raster_span.s` → `RasterSpanNEON`).** `CRasterSpan` gained `tex_ptr`
(0x90) + the 9 per-vertex 16.16 attributes + 3 per-pixel deltas; when `tex_ptr != 0` the kernel branches to the
textured path (otherwise the **byte-identical** solid path runs → `0xD28836F` untouched):
- Coverage + 8-lane depth (`CMHI.8H`) → active mask `V31`, exactly as the solid path.
- Compact 8-lane loop (mask-skip via `TST`): perspective-correct `u,v` with **exact 64-bit `SDIV`**
  (`u = (numU<<16)/den`; `numU = Σ wₖ·uowₖ` recomputed per block from the block's `w0,w1,w2`), scalar gather,
  **NEON bilinear** (`UXTL`/`UMULL`/`UMLAL`/`SHRN`, weights `(ifx·ify)>>24`), packed to a 32-byte stack buffer.
- NEON **modulate** (`UMULL`+`(P+(P>>8)+1)>>8` = exact `/255`, alpha forced 255) and **alpha blend**
  (`UMULL`/`UMLAL` with `+127` then `/255`) across 8 pixels; masked `BSL` store. `REPEAT` (PoT mask) / `CLAMP`
  wrap via `TBNZ` bit-15 test; `NEAREST`/`LINEAR` branch per lane.
- Bug found & fixed during bring-up: `w19` (colour) was clobbered by the per-lane loop's `x19` temp, so the
  modulate colour vector was rebuilt from garbage → dimmed texels. Fixed by building `v8`/`v9` **once** in the
  prologue. (Also fixed: overlapping 8-byte stack slots for `fx/fy`, `tx0/tx1`, `ty0/ty1` → 4-byte slots.)

**FASE 3 — parity + benchmark.** All 4 `SelfTestTexture` sub-tests pass through the NEON span
(`NEAREST` quadrants, `LINEAR` centre `0x7F7F7F`, perspective row, alpha `0xFF800000`). `renderbench` gained a
`Textured` line (measured ~3493 tri/s, ~277 Kpix/s on QEMU TCG — the NEON path with per-lane `SDIV` + gather).

- [x] Remove ALL `doldoc_printf` from the rasterizer; diagnostics are globals read after the draw.
- [x] Perspective-correct interpolation (area-free).
- [x] NEAREST → LINEAR (256-sum weights) → REPEAT/CLAMP → alpha blend (exact `div255`).
- [x] **NEON textured span** — one kernel, mask-skip, exact-integer perspective, NEON bilerp/modulate/blend.
- [x] **D7 root fix** — struct-member pointer indexing strides by the pointee width (no typed-local workaround).
- [x] **`RasterDisableTexture()`** is called by the 2D path (`RenderGoldenScene`) so the golden hash stays
      bit-exact; `glDisable(GL_TEXTURE_2D)` unbinds.
- [x] **`SelfTestTexture`** (gate `TEXTURE: PASS`): (1) NEAREST quadrants; (2) LINEAR centre; (3) perspective
      row boundary at `v=3t/(1+2t)`; (4) alpha 50% blend. `TEXTURE: PASS` + `PTRSCALE2` in `golden-boot.sh`.
- [ ] **Decision (color space) — DEFERRED to P4.4+:** shade in linear light / present sRGB / premultiplied
      alpha (current path is straight alpha + sRGB-ish 0xAARRGGBB).
- [ ] Blend modes additive/multiply — DEFERRED (opaque + src-alpha landed).
- [x] **Exit — MET:** `SELFTEST 81/81`, `PARITY 54/54 (0 diff)`, `RASTER: PASS`, `RENDER: PASS (0xD28836F)`,
      `TEXTURE: PASS`, `PTRSCALE2: PASS`, `KHEAP: PASS`, `SELF-HOST: PASS`, `CENSUS: PASS`, `GOLDEN BOOT: PASS`.

**Cross-module accessors (sovereign rule):** `HolyGLGetTrisRendered()`, `HolyGLGetViewportW/H()`,
`HolyGLGetBound()`, `RasterTextureActive()` — never read `g_hgl.*`/`g_rtex.*` from another module. (Existing
violations to fix: `Gears3D.HC`, `Physics3D.HC` write `g_hgl.v_curr.color` directly.)

### P4.4 — `Fonts.HC` (merge + AA atlas) — ✅ **DONE**
**Goal (met):** one font module; crisp bitmap for small text, smooth AA scalable text, real metrics.
- [x] **Merged** `FontMono` + `FontVector` into one `apps/Fonts.HC`; **deleted** `FontMono.HC` / `FontVector.HC`;
      `KernelInit` now loads only `Fonts.HC` (Stage 2). The **mock SFNT** parser (`FontParseTableDirectory`),
      the redundant `g_mono_glyphs` copy, and the dead `VectorDrawGlyph`/`VectorDrawString` shims are gone.
- [x] **Bitmap font** kept for crisp small text (`FontsDrawBitmapChar/Text` → Render's `gfx_draw_char`,
      unchanged so the golden hash is preserved).
- [x] **Boot-baked AA atlas:** each glyph's analytical quadratic-Bézier outlines are rasterised at **4×**
      supersample into a 96×96 buffer, box-downsampled to a **24×24 coverage** cell (17 alpha levels), and packed
      into one **256×256** power-of-two ARGB atlas (alpha = coverage, RGB = white). 95 glyphs, 10×10 cells.
- [x] **AA composite:** each glyph is sampled from the atlas with a **bilinear coverage read** and
      alpha-composited straight into the framebuffer (clip-safe). *(`smoothstep` is baked into the coverage at
      bake time — a fixed-function composite cannot evaluate an SDF per fragment; the per-fragment SDF variant
      lands with the P4.6 fragment VM.)* The earlier rasterizer-quad composite was abandoned: the packed
      atlas's sub-texel UV is fragile at the 16.16 precision of the NEON span.
- [x] **Real metrics:** `g_font_metrics` (8×16 bitmap, UPM 1000) + `FontVectorCharAdvance/MeasureString` from
      the vector grid; `FontsDrawText(x,y,str,px_height,color)` pixel-height convenience.
- [x] **`FontsSelfTest`** (gate **`FONTS: PASS`**): (1) atlas baked ('A' coverage); (2) metrics; (3) a real
      80-px AA composite through the framebuffer (ink + intermediate coverage + peak). Added to `golden-boot.sh`.
- [x] **Exit — MET:** `SELFTEST 81/81`, `PARITY 54/54 (0 diff)`, `RENDER: PASS (0xD28836F)`, `TEXTURE: PASS`,
      `FONTS: PASS`, `PTRSCALE2: PASS`, `KHEAP: PASS`, `SELF-HOST: PASS`, `CENSUS: PASS`, `GOLDEN BOOT: PASS`.

### P4.5 — Lighting & shading — ✅ **DONE** (P4.5a gears root fix + P4.5b shading)
**Goal (met):** per-fragment Blinn-Phong + Gouraud, inside the ONE NEON rasterizer, with the golden solid
path byte-identical; plus the gears-geometry root fix that was blocking all 3D.

**P4.5a — Gears geometry ROOT FIX (`Compiler.HC`) — DONE.** The gears rendered 366 tris / 644 px (collapsed)
while `z = w*0.5` stayed correct. Root cause: `HcReset()` clears the per-unit function table every unit, so a
call to an **F64-returning function defined in an earlier unit** (`Gears3D` → `MathCos` from `Math3D`) was
treated as returning an **integer**; `HcEmitPromoteFloat` then emitted `scvtf d0, x0` on the double's raw
bits, and `r * MathCos(a)` produced garbage. Fix: a **persistent** `name → returns-F64` table
(`g_hc_fnf_*`, never reset) that `HcFuncIsFloat` falls back to, plus `HcPrescanFuncs` (a brace-depth-0
pre-scan registering top-level function floatness so intra-unit forward refs resolve too). Gears now render
**800 tris / 71410 px** (`3D-GEARS: PASS`); regressions `f64_lhs_mul_fn_call`, `f64_struct_arr_member_assign`,
`f64_seven_arg_mixed` added to `SelfTest.HC` + `cases.json`.

**P4.5b — Smooth shading in the ONE kernel (`scripts/raster_span.s`) — DONE.** `CRasterSpan` gained `gmode`
(0xF8) + the shading state (0x100..0x1B8: affine colour/normal at `x_start`, per-pixel deltas, L/H, base²,
amb/diff/spec). After the shared coverage/depth stage the kernel dispatches:
- **gmode 0 — flat:** the *byte-identical* solid path → `RENDER 0xD28836F` untouched.
- **gmode 1 — Gouraud:** per-vertex lit colours are carried as affine `f32` accumulators, advanced `8*delta`
  per block, fanned over 8 lanes with `FMLA v.4s, v.4s, [0..7]`, `FCVTZS`, clamped, packed ARGB and masked
  `BSL`-stored.
- **gmode 2 — per-fragment Blinn-Phong:** per-vertex view-space normals are interpolated per pixel
  (`PHONG_HALF` macro, 4 lanes ×2), **normalized with `FRSQRTE` + one `FRSQRTS` Newton step**, then
  `N·L` (diffuse), `N·H` (Blinn half-vector), `(N·H)^16` (four `FMUL` squarings), `amb + diff·N·L`, and a
  **gamma-corrected** `sqrt(base²·lambert + spec)` → sRGB. All NEON; no scalar fallback in the span body.
- Head/tail (<8 px/row) use a scalar mirror (`RasterPixelShaded`/`RasterShadeColorAt`) exactly as p4.2b.

**Integration (`HolyGL.HC`):** `HolyGLSubmitTriangle` now rotates each vertex normal into view space
(`HolyGLViewNormal`) and calls `RasterSetNormal(0/1/2, …)` + `RasterSetLight` + `RasterSetShading` +
`RasterEnablePhong()` when `GL_LIGHTING` is on, else `RasterDisableGouraud()`. `RenderGoldenScene` /
`RenderBench` force `RasterDisableGouraud()` so 2D stays on the flat golden path.

- [x] Per-fragment (not per-vertex) lighting; normals interpolated + normalized per pixel (`FRSQRTE`/`FRSQRTS`).
- [x] Blinn-Phong specular (`N·H`, exponent 16) + ambient + diffuse; gamma-corrected output.
- [x] Gouraud (affine per-vertex colour) mode in the same kernel.
- [x] `SHADING: PASS` gate (`SelfTestShading`): a normal-swept quad yields ≥8 distinct per-fragment shades
      with a specular peak (measured `phong=30 lum_max=182`), and a 3-colour Gouraud triangle yields a
      gradient (`gouraud=218`). Visual: smooth quad gradient + specular highlight captured via screendump.
- [x] **Golden invariant:** gmode 0 + tex 0 executes the unchanged solid path → `RENDER: PASS (0xD28836F)`.
- [x] **Exit — MET:** `SELFTEST 84/84`, `PARITY 54/54 (0 diff)`, `RENDER: PASS (0xD28836F)`, `3D: PASS`,
      `3D-GEARS: PASS`, `SHADING: PASS`, `TEXTURE: PASS`, `FONTS: PASS`, `SELF-HOST: PASS`, `CENSUS: PASS`,
      `GOLDEN BOOT: PASS`.

### P4.6 — Fragment-shader VM — ✅ **DONE**
**Goal (met):** a small bytecode VM evaluated per 2×2 quad, with `dFdx`/`dFdy` via lane permutation and
execution masking; a built-in shader library first (SDF/noise/Mandelbulb) and a generic VM for custom shaders;
4 px/iteration in NEON lanes.

- [x] **`apps/ShaderVM.HC`** — a register bytecode machine: 16 shader registers × **4 lanes** (SoA 2×2 quad),
      instruction = 4×I64 `[op,a,b,c]`. ISA: `mov/movi add/sub/mul/div/min/max sqrt/rsq/abs/neg/floor/fract
      sin/cos len2/len3/dot2 mix/clamp/smooth fragx/fragy/time dfdx/dfdy if/else/endif jmp/jnz/jz
      perlin/fbm/mandel/sdfsphere/sdfbox/sdftorus out`.
- [x] **NEON op core** `ShaderOp4` (`scripts/shader_quad.s`, 75 words): add/sub/mul/div/min/max/sqrt/rsq/abs/
      neg/floor/fract applied to all four lanes with 2× `.2d` (`frsqrte`+`frsqrts` for `rsq`). One instruction
      = 4 px. The interpreter does only the per-lane masked blend.
- [x] **`dFdx`/`dFdy` via lane permutation** (quad layout 0=(x,y) 1=(x+sx,y) 2=(x,y+sy) 3=(x+sx,y+sy)).
- [x] **Execution masking:** `if r[a]` → 4-bit predicate ∩ current mask, mask stack for `else`/`endif`; ops
      write only active lanes.
- [x] **Built-in library first:** Perlin gradient noise (`ShaderPerlin3`), multi-octave fBm (`ShaderFbm3`),
      Mandelbulb DE (`ShaderMandelbulbDE`, with `atan2`/`acos`/`log`), SDF primitives; plus a **text assembler**
      (`ShaderVMAssemble`, mnemonics + labels) for custom shaders. Built-in programs: animated gradient,
      shaded 2-D SDF disc (uses `dfdx`/`dfdy`), Perlin fBm, and a **masked Mandelbrot** (real divergence loop).
- [x] **Native 4-lane raymarcher** (`ShaderRaymarchQuad`): marches 4 px/iteration against a sphere+torus+plane
      whose field (`ShaderField4`) is evaluated **4 lanes at a time through `ShaderOp4`**, finite-difference
      normal + Blinn-Phong + gamma. Exposed as the `shadervm` shell command.
- [x] **Integration:** DolDoc routes `$SHADER$` types `vm`/`sdf`/`noise`/`mandel`/`bulb` to
      `ShaderVMRenderNode` (direct call — Stage 5 loads before DolDoc, no `symbols_lookup`, census unchanged);
      `ShaderEditor` preset 9 shows the live VM gallery; `KernelInit` Stage 5 loads `ShaderVM.HC` (34 subsystems).
- [x] **Root fixes it required (`Compiler.HC`):** local-array element floatness was inherited from the
      *previous* declaration (`F64 a[3]; a[0]=1.0;` → raw integer bits), and indexing a **pointer local**
      (`F64 *p; p[i]`) used the pointer's own floatness instead of the pointee. Fixed via `g_hc_decl_float` /
      `g_hc_decl_elem_float` / `g_hc_local_elem_float`; regression `f64_local_array_assign`.
- [x] **`SHADERVM: PASS (14/14)`** gate (`SelfTestShaderVM`): op-core add/mul/sqrt, VM arithmetic, derivatives,
      masking (both branches), library ranges, a text-assembled countdown loop, the 4-lane field value
      (`2.25` at the torus) and an SDF viewport fill. Visual: the raymarched sphere/torus/plane and the live
      `shader 9` gallery captured by screendump.
- [x] **Golden invariant:** the VM is a separate path → `RENDER: PASS (0xD28836F)` untouched (bit-exact).
- [x] **Exit — MET:** `SELFTEST 85/85`, `PARITY 54/54 (0 diff)`, `RENDER: PASS (0xD28836F)`, `3D: PASS`,
      `3D-GEARS: PASS`, `SHADING: PASS`, `SHADERVM: PASS (14/14)`, `TEXTURE: PASS`, `FONTS: PASS`,
      `CENSUS: PASS (181)`, `SELF-HOST: PASS`, `GOLDEN BOOT: PASS`.

### P4.7 — Mesh ingestion — ✅ **DONE**
**Goal (met):** a streaming Wavefront OBJ parser in HolyC + a renderer that goes through the ONE pipeline
(HolyGL immediate mode → `HolyGLSubmitTriangle` → `RasterTriangleZ`), with the two compiler root bugs it
surfaced (D14, D15) fixed at the root.

- [x] **`apps/Mesh.HC`** — streaming OBJ parser: `v/vn/vt/f`, negative (relative) indices, `v/vt/vn`, `v//vn`,
      `v/vt`, `v` corner forms, n-gon fan triangulation (quad → 2 tris), `#/o/g/s/mtllib/usemtl/l/p` ignored;
      faces without normals get a computed face normal so the mesh is always lit.
- [x] **No new allocator sites:** fixed-capacity `CMesh g_mesh` globals → the `.HC`→C census is unchanged
      (181). Embedded unit cube (top face uses negative indices) so `$SP,type="mesh"` works with no file;
      `obj <file>` loads one from RedSea (`redsea_read_file`, auto-packed from `apps/`).
- [x] **Render through the ONE path** (`MeshRender` → `HolyGL*`), `MeshRenderViewport` (perspective + modelview),
      `MeshDemo` (`mesh` command), DolDoc `$SP,type="mesh"` route (direct call, census-neutral).
- [x] **Root fix D14 (`Compiler.HC`):** a local **redeclared with a different type** kept the FIRST type, so
      `F64 b` (in the `vn`/`v` branches) made the later `I64 b` index load as a double → `&b × elem` → wild
      ~18 GB read. `HcAddLocalTyped` now updates the local's type flags on redeclaration. Regression
      `redecl_float_int_index`.
- [x] **Root fix D15 (`Compiler.HC` + `boot/seed/jit_arm64.c`):** the struct-member array parser accepted only a
      single number, so `I64 fv[MESH_MAX_T * 3]` recorded 512 elements and corrupted every following offset
      (`fni`/`ft`) and `sizeof(CMesh)`. Both engines now fold `N*M` / `N+M` like the local/global array parsers.
      Regression `member_arr_compound_dim`.
- [x] **`MESH: PASS (v=8 tris=12 nrm=6 ink=28177)`** gate (`MeshSelfTest`): parse the embedded cube (8 v, 6 vn,
      12 tris incl. a negative-index face), submit through HolyGL, count rendered pixels. Visual: `mesh` demo
      screendump (`screenshots/mesh_cube_live.png`).
- [x] **Exit — MET:** `SELFTEST 87/87`, `PARITY 56/56 (0 diff)`, `RENDER: PASS (0xD28836F)`, `SHADERVM: PASS`,
      `3D`/`3D-GEARS`/`SHADING`/`TEXTURE`/`FONTS: PASS`, `MESH: PASS`, `CENSUS: PASS (181)`, `SELF-HOST: PASS`,
      `GOLDEN BOOT: PASS`.

### P4.8 — Merge, delete, verify — ✅ **DONE**
**Goal (met):** one damage tracker, one present, one theme owner, and a determinism gate proving the ONE
renderer is byte-identical on 1 vs N cores.

- [x] **Duplicate damage/present collapsed.** `Compositor.HC` no longer keeps a second bounding box
      (`g_comp.dmg_*`) or the write-only KolibriOS tile maps (`tile_dirty_map`/`win_tile_map`).
      `CompositorDamage{All,Rect,Window}` now forward to the ONE tracker (`GfxDeviceDamage` → Render's
      `g_canv.dirty`; `gfx_dirty_all`) and `CompositorPresent` reads that same rect via new
      `RenderDirtyActive()`/`RenderDirtyBounds()`. WM's redraw predicate now uses `RenderDirtyActive()`.
      Two Z-buffers were already retired in P4.2 (one `g_zbuf` in `RasterTile.HC`); verified.
- [x] **Theme ownership moved out of Compositor.** New `apps/Theme.HC` owns `CThemePalette g_theme` +
      `ThemeApply`/`ThemeSetByName` + the `THEME_*` ids; loaded in Stage 6 before Compositor (36 subsystems).
      Verified live: `theme latte` recolours the desktop.
- [x] **Dead-code purge.** Deleted `CompositorMain`, `CompositorDrawBox` + `CBoxStyle`,
      `CompositorQueryTileOwner`, `CompositorStampWindowTiles`, `CompositorClearDamage`; Render's
      `RenderIsZeroRamMode`, `gfx_mark_dirty`, `gfx_draw_circle`; HolyGL's `HolyGLApplyLighting` + 7 dead
      getters + 6 dead `gl*` aliases; Raster's `RasterGetDepthTest`/`RasterShadeMode`/`RasterTextureActive`.
      All verified 0 call sites (symbol count drops; census stays 181 — no allocator sites touched).
- [x] **Determinism gate.** New `scripts/determinism-gate.sh`: boots the OS on 1 core and on N cores
      (`run-viewer-vm.sh` now honours `NEO_SMP`), runs the battery, and asserts the golden-frame hash matches.
      Wired into `golden-boot.sh`. Result: **`DETERMINISM: PASS (1 vs 4 cores identical: 0xD28836F)`**.
- [x] **Exit — MET:** `SELFTEST 87/87`, `PARITY 56/56 (0 diff)`, `RENDER: PASS (0xD28836F)` **bit-exact on 1
      and 4 cores**, `3D`/`3D-GEARS`/`SHADING`/`TEXTURE`/`FONTS`/`SHADERVM`/`MESH: PASS`, `CENSUS: PASS (181)`,
      `SELF-HOST: PASS`, `GOLDEN BOOT: PASS`. A flat triangle, a textured quad, an SDF glyph and a lit
      Gouraud mesh all render through the one NEON path with real per-pixel Z.

---

## P5 — DolDoc (real TempleOS model + dissolution)  ✅ **DONE**

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P5, 02-PRIORITY-PLAN P5, P2-P6-MIGRATION-SPECS §5, 03-design §3.2–3.4)`
- [x] **Rewrite `DolDoc.HC` → CDoc/CTree** of entries + **per-char attributes**; delete `g_doc_chars/fg/bg`, `g_doc_link_idx`, `g_hist_chars`. — flat `CDocNode` tree + `g_doc_attr[fg|bg]` arena; grid gone.
- [x] **Full two-letter tag set:** `TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI` — incl. `$MA` macros, `$DA` forms, `$AN` anchors, `$ID` trees, typed `$LK` links, word-wrap.
- [x] **Windows are documents:** `$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`; **dissolve `WM.HC`**; **dissolve `Compositor.HC`** — both files DELETED; desktop/window/damage/present/effects absorbed.
- [x] **Reactive cells** (generalize `DolDocPatchTarget` via `DolDocCellWrite`/`$SL`/`$DA` `target=`); RedSea document persistence (`$FI` include); the DolDoc reference is a DolDoc (dogfood: `DolDocSelfTest`).
- [x] Fix `g_doc_dirty_mask` (`((U64)1 << r)`).
- [x] **Exit:** a doc with text/link/button/slider/form/tree/3D-scene/shader renders + responds; no char grid. Gate: `DOLDOC: PASS`; screenshots `p5_desktop_live.png`, `p5_shader_editor_live.png`, `p5_doc_widgets_live.png`.
- Compiler root fixes this priority: **D17** (no function forward declarations), **D18** (no comma-separated initialized declarations), **D19** (`HC_MAX_FUNCS` 128→512, epilogue-patch cap 64→512), **D20** (declare globals before use). See doc 4.

---

## P6 — Shell (action executor over a CDoc)  ✅ **DONE**

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P6, P2-P6-MIGRATION-SPECS §6)`
- [x] **Action protocol:** documents emit `Action{Run,Open,Set,Clone,Focus}` (`DOC_ACT_*` in `DolDoc.HC`); the shell executes (`ShellDrainActions`/`ShellExecuteAction`).
- [x] **Command registry:** `shell_register_cmd` is live (FNV-1a `CShellCmd` hash table + `ShellFindCmd`); the if/else ladder is gone.
- [x] **Break all cycles** (`DolDoc→Shell`, `WM→Shell`, `WM↔Compositor`) — `DolDoc.HC` has 0 Shell references.
- [x] **Shell buffer is a CDoc**; the input/event loop is kept (with `WFE` idle).
- [x] Fold `top`/`edit`/`filer` into shell-backed docs (interactive CDoc: buttons, `$PB` bars, line-numbered text).
- [x] **Exit:** no cycles; shell output *is* a CDoc. Gate: `SHELL: PASS`; screenshots `p6_top_live.png`, `p6_filer_live.png`, `p6_edit_live.png`.
- Root fix this priority: **D21** (FNV-1a `% 128` is signed-negative → OOB bucket read). See doc 4.

---

## P7 — Benchmark (one HolyGL-max suite)

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P7, 02-PRIORITY-PLAN P7, P2-P6-MIGRATION-SPECS §4)`
- [ ] Merge `HolyBenchmark` + `BenchCpu` + `BenchReport` → one suite; merge `Profiler` + `PerfOverlay` → one telemetry engine.
- [ ] **Real 40 phases** (or relabel): per-pixel Z, textures, Gouraud (interpolated), SDF, real NEON; remove write-only `g_bench_mode`; fix `BenchCpuMathNeon` (currently an integer LCG loop — BEN-01).
- [ ] Remove synthetic constants `blit_us=1200`/`dma_us=400`/`wm_us=300` (BEN-02).
- [ ] Write `/BENCH_REPORT.TXT` (+ `/BENCH_COMPARISON.TXT`, `BENCH_PROFILER.LOG`, `BENCH_SPIKES.LOG`).

---

## P8 — Self-hosting everything

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P8, 03-design §3.9)`
- [ ] Boot as a document; only `boot/main.c` + `boot/uefi` in C; finish the self-host loop.
- [ ] The compiler is a document (source buffer + Run + output/errors); the DolDoc reference is a DolDoc.

---

## P9 — GPU provider

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P9, 03-design §3.5)`
- [ ] virtio-gpu 3D (virgl/Venus) + native GPU drivers, behind the HolyGL provider seam.

---

## P10 — Run anything + MCU cluster

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P10, 03-design §3.10/§3.11)`
- [ ] `HolyPort` platform layer + C→HolyC / LLVM→HolyC toolchain (run decompiled games).
- [ ] `Surface` + `remote` provider → **MCU cluster** (RISC-V backend + distributed runtime).

---

## Cross-cutting sweeps (fold into the relevant priority)

`(from 00-MASTER-CONSOLIDATED-PLAN §6 "Cross-cutting", 00-CONSOLIDATED §3.2/§8, 06-decisions-and-todo "Hygiene")`
- [ ] **Typing sweep:** `%d`→`%lld`/`%llX` (~40 sites); fnptr fields typed `U64`; colors as `I64`; `int` truncation in the compiler; duplicate globals; `g_doc_dirty_mask` shift.
- [ ] **Docs:** rewrite README/docs to verified truth (this 5-doc set does that).
- [ ] **Remove demos:** `calc`, `fact`, `SmpDemo`, `Showcase`, `Menu`, `Editor`, `Filer`, `Top`.
- [ ] **Naming:** one convention (kill PascalCase+snake aliases); single source of truth per module.
- [ ] **Dead code purge:** `Table.HC`, `StdLib.HC` (dup/unused), `Bench.HC`, `HolyBenchmark3D.HC`, `HolyGLTest.HC`, write-only state.
- [ ] **Files to delete (cumulative, planned):** `FontMono.HC`, `FontVector.HC`, `GfxBackend.HC`, `VirtioGpu.HC`,
      `RasterTile.HC`, `PerfOverlay.HC`, `BenchCpu.HC`, `BenchReport.HC`, `WM.HC`, `Compositor.HC`.

---

## Verification matrix (run after every change)

`(from 00-MASTER-CONSOLIDATED-PLAN §7, P2-P6-MIGRATION-SPECS §7.5)`

| Check | Command | Expected |
|---|---|---|
| Golden gate (one boot) | `scripts/golden-boot.sh` | `GOLDEN BOOT: PASS` |
| In-guest battery | inside the gate: `selftest` (one command) | `SELFTEST: 87/87 PASS` |
| In-guest parity | inside the gate: `selftest` | `PARITY: 56/56`, `0 diff` |
| Twin-liveness | inside the gate: `selftest` | `TWINS: 5/5` |
| Symbol audit | inside the gate: `selftest` | `SYMS: <n> symbols, 0 unresolved` |
| Shading (P4.5) | inside the gate: `selftest` | `SHADING: PASS` |
| Fragment-shader VM (P4.6) | inside the gate: `selftest` | `SHADERVM: PASS (14/14)` |
| DolDoc 3.0 (P5) | inside the gate: `selftest` | `DOLDOC: PASS` |
| Shell action executor (P6) | inside the gate: `selftest` | `SHELL: PASS` |
| C-runtime census | `scripts/census-c-runtime.sh` | `CENSUS: PASS` |
| Self-host | `scripts/self-host-test.sh` | `SELF-HOST: PASS` |
| Module parity | `scripts/p1-parity.sh` | `RESULT: PASS — engines agree` |
| Undefined syms | `scripts/audit-symbols.sh` | 0 undefined, 0 unresolved |
| Legacy battery | `scripts/run-jit-golden.py` | 86/86 (superseded by `selftest`) |
| Token parity | `scripts/check-token-parity.py` | 71 tokens identical |
| Visual | `scripts/screenshot-diff.py` | no unexpected diff |
| Cycles | `rg "shell_run_command" apps/DolDoc.HC` | button/link click only (P6) |

> `tests/jit_golden/cases.json` holds **86 cases** (1 `known`), i.e. **85 active**; the in-guest suite is
> those 85 plus coverage/subsystem gates = **87 counted checks** (`SELFTEST 87/87`).

---

## Reconciliation of every old numbering scheme (nothing dropped)

`(from 00-MASTER-CONSOLIDATED-PLAN §3, 05-NEW-TASKLIST, 06-decisions-and-todo, task.md, FUTURE…ROADMAP,
neo_os_grand_forensic_dossier… §6, POST_DOM… §7, priority_implementation_plan §8, implementation_plan §5,
single_core…_audit §4, complete_render_stack… §6, neo_os_consolidated_defect_record §11)`

| Old scheme | Where | Maps to |
|---|---|---|
| **Levels L0–L8** | `00-REALITY-AND-MASTER-PLAN`, `NEO_OS_MASTER_PLAN.md` | L0=P0, L1=P1, L2=P2/P3, L3=P4, L4=P5, L5=P6, L6=P7, L7=docs, L8=P9/P10 |
| **Phases 0–17** | `task.md` | Phase 0–8 = historical (done); 9=P1; 10–11 = history; 12 = hygiene; 13=P5; 14=P4; 15=shader engine; 16=P1 seed (**blob part superseded**); 17=PMU (P7) |
| **Phases 1.0–6.0** | forensic dossier §6 / FUTURE roadmap | 1.0 = hygiene; 2.0=P5; 3.0=P4; 4.0=shader engine (P4); 5.0=P1; 6.0=PMU (P7) |
| **Phases 1–7** | POST_DOM §7 | 1=storage zero-copy (P2/P3); 2=P5; 3=P4; 4=SIC live-patch (P1/P5); 5=P3 SMP |
| **Phases 1–7** | priority_implementation_plan §8 | 1=Lua excision ✅; 2=JIT pool ✅; 3=P3; 4=P5; 5=P4; 6=P8; 7=stack collapse (P4/P7) |
| **Phases 1–6** | implementation_plan §5 | timekeeping ✅; VirtIO decouple ✅; UDS (P5); HolyGL tile (P4); 16-phase bench (P7); HolyC 2.0 (P1) |
| **Steps 1–5** | single_core_sovereign_master_audit §4 | single-core baseline ✅; VSync ✅; NEON rasterizer (P4); 6-config suite (P7); verify |
| **Steps 1–4** | complete_render_stack_master_evaluation §6 | SMP idle ✅; VSync ✅; VirtIO barrier ✅; time-limited bench (P7) |
| **Phases A–D** | 03-NEXT-STEP-TASKLIST | compiler corruption bisect → **superseded** (fixed; P1) |
| **Agent split A/B** | P1-DELEGATION | Agent A compiler (P1), Agent B harness/specs (P0/docs) |
| **20 Orders** | root `SKILL.md` | Orders 1–2=P1/P2; 3=HAL (P3); 4=KHeap (P3); 5=Symbols (P3); 6=Lexer (P1 ✅); 7=Compiler (P1); 8=Exceptions (P3); 9=GIC/Timer/Sched (P3); 10=SMP (P3); 11=VirtIO/RedSea (P2/P3); 12=Render (P4); 13=Themes (P5); 14=Fonts (P4); 15=DolDoc (P5); 16=dissolution (P5/P6); 17=Shaders (P4/P5); 18=3D/bench (P4/P7); 19=Showcase (P5); 20=QEMU verification (P0 ✅) |

**Superseded tasks (kept, tagged, NOT to be done):** the **Stage-2 binary blob** (`task.md` Phase 16,
`FUTURE…ROADMAP` Task 5.4, `P1-DELEGATION` §0 item 6) — removed by master plan §4; the `scripts/compile-parity.sh`
name (does not exist; the real tool is `scripts/p1-parity.sh`); the 6-config/16-phase benchmark matrices
(superseded by one 40-phase suite). See doc 04.

---

## Cross-cutting sovereign upgrades (2026-10) — external best-in-class → subsystem

Folded into their owning priorities. Code-level detail + citations in `docs/research/*.md`. Each is a **root
upgrade**, gated by the existing harness, and must not increase the `.HC`→C census except where noted.

- [ ] **P1.3 — Symbol resolution O(1) & FNV-1a** (`apps/Symbols.HC`, `apps/Compiler.HC`). Upgrade the symbol
      hash DJB2→**FNV-1a 64-bit**; store a **normalized key** so the canonical (case/underscore-insensitive)
      lookup is O(1) instead of a 1024-bucket linear scan; add **>8-arg stack spill** (today it hard-errors);
      add range-extension thunks for far `CBZ/CBNZ`. Gate: `SYMS 0 unresolved`, `SELF-HOST PASS`, census flat.
- [ ] **P2.8 — RedSea integrity & atomic commit** (`apps/RedSea.HC`, `apps/KHeap.HC`). **CRC32C** table
      (`0x82F63B78`), self-test vector `0xE3069283`, per-block CRC; **uberblock ring** + monotonic `txg`
      (highest valid wins); durability `DC CVAC`+`DSB SY`. Gate: `FSRT: PASS` + a new `CRC32C: PASS`.
- [ ] **P3.9 — Lock-free MPMC & MPSC run-queues** (`apps/Sched.HC`, `apps/Smp.HC`, `kernel/`). Replace the
      SPSC mailbox with **Vyukov bounded MPMC** (per-cell sequence, ABA-free) + per-core MPSC inboxes;
      `LDAXR/STLXR`/`LDAR/STLR`; `WFE/SEV` idle with re-check. Gate: `SMP: PASS`, `SCHED: PASS`, 1-vs-N parity.
- [ ] **P4.4 — `Fonts.HC` merge + SDF** (`apps/Fonts.HC`, `apps/DolDoc.HC`). Merge `FontMono`+`FontVector`+
      `gfx_draw_char`; add the **stb_truetype v2 signed-area AA rasterizer** + `GetGlyphSDF` (or
      rasterize-then-EDT); bake an **SDF atlas** at boot; composite as textured quads through the one rasterizer.
      Gate: `FONTS: PASS` (AA glyph hash) + `RENDER` unchanged.
- [x] **P5.0 — DolDoc 3.0** (`apps/DolDoc.HC`). Flat index-based `CDocNode` tree; reactive-cell bindings
      (`$DA`/`$SL` `target=` via `DolDocCellWrite`); document = window/shell/editor; windows are `$WIN$` docs;
      draw through the one rasterizer. Gate: `DOLDOC: PASS` + golden hash unchanged (`0xD28836F`). *React O(n)
      keyed reconciliation and Morton dirty tiles were superseded by the tree walk + single dirty rect.*
- [ ] **P6.0 — Reactive shell** (`apps/Shell.HC`, `apps/Symbols.HC`). Symbol-table O(1) dispatch; command
      output as a mounted `CDoc` subtree; `WFE` idle with a lost-wakeup-safe re-check. Gate: all builtins
      dispatch + `WFE` idle verified.
- [ ] **Sweep — cross-module accessor rule.** Purge direct `g_hgl.*` writes (`Gears3D.HC`, `Physics3D.HC`) and
      any other cross-module struct-member access; route through exported accessors. Add a static check.


---

## P7 — Execution blueprint (one-shot runbook)

> **STATUS (2026-10):** **P7.0 ✅ DONE** — docs consolidated to exactly 5 files; peephole optimizer live in
> `Compiler.HC` (`[PEEPHOLE] runs=33 roundtrips=5600`); cross-module `g_hgl.*` writes purged
> (`HolyGLColorPacked`); orphan `apps/TestJitP0.HC` removed (6 useful cases folded into `SelfTest.HC`); stale
> `p4.3-wip` branch deleted. Gate: `SELFTEST 96/96`, `PARITY 64/64 (0 diff)`, `CENSUS 181`, `SELF-HOST: PASS`,
> `DETERMINISM: PASS`, `GOLDEN BOOT: PASS`. **Next: P7.1 (HolyGL GL 1.3 surface + conformance).**
>
> Merged from the former `docs/07-P7-EXECUTION-BLUEPRINT.md` (P7.0 doc consolidation). The ladder overview is in `00-MASTER-PLAN.md` §11.


> **Scope.** This is the *execution* blueprint for the single next priority, **P7**. It is deliberately
> prescriptive: an engineer who follows it top-to-bottom should land P7 in one clean pass with no open
> design questions. Every anchor was verified against `/home/user/neo-os` @ `HEAD d657e70` (P0–P6 done)
> and upstream `/tmp/neo-upstream` @ `36ca4b0`.
>
> Sibling docs written in parallel: `docs/05-UPSTREAM-SALVAGE-AUDIT.md`, `docs/06-PERFECTED-PRIORITY-PLAN.md`.
> This file depends only on `docs/00-MASTER-PLAN.md` §3/§5/§6.5/§9.4, `docs/02-TASKLIST.md` §P7, and the tree.
>
> **Hard constraints honoured by every step:** no new `.c` files; no stubs/placeholders/mock data; no
> forward declarations; one render pipeline only (no scalar fallback); golden 2D hash `0xD28836F`
> bit-exact; C-runtime census never increases; 8-argument call cap; no cross-module struct-member access
> (use exported accessors); all verification in QEMU via screendump.

---

## 1. Objective

Make the NeoOS graphics + measurement stack **sovereign and real**:

1. **HolyGL** becomes a complete GL 1.3-class immediate-mode state machine (projection stack depth 4 +
   modelview depth 16 + the full `gl*` binding surface + `glClear/glClearColor/glColor4f/glFlush`) with a
   near-plane Sutherland–Hodgman clipper, feeding the **one** NEON rasterizer.
2. The **one** rasterizer gains real **L1 tile binning** with per-core scratchpads and a **`stnp` streaming
   resolve**, dispatched across **SMP cores** (`wfe`/`sev`/`dmb ish`), making `GFX_MODE_SMP_TILED` real.
3. The GPU config plane becomes real (5 knobs, each with a real reader); VirtIO-GPU gains **batch2/batch3**
   and a **page-flip ping-pong**; optional 32-bit-Z tile kernel.
4. **Telemetry** merges `Profiler.HC` + `PerfOverlay.HC` into one `apps/Telemetry.HC`: a `mark_*` stage API,
   histogram percentiles (1 %/0.1 % low), steady-state, a spike ring with causes, optimization directives,
   and **real ARM PMU counters** (`PMCR_EL0`/`PMCCNTR_EL0`/`PMEVCNTR*`).
5. `HolyBenchmark.HC` becomes a **real 40-phase suite** (5 categories × 8 variations, 3.5 s `cntvct_el0`
   limiter, per-phase metrics, real export files), absorbing `BenchCpu.HC` + `BenchReport.HC`, with the
   integer-LCG `BenchCpuMathNeon` replaced by real NEON and all synthetic constants purged.
6. `apps/SelfTest.HC` stays the single source of truth: it grows `GL`, `TILE`, `TELEMETRY`, `BENCH` gates,
   wired into `scripts/golden-boot.sh`.

---

## 2. Exit gate (exact strings)

After the final step, **all** of the following must hold on a normal boot. Strings are exact and greppable.

| Gate | Exact expected string | Produced by |
|---|---|---|
| Golden boot | `GOLDEN BOOT: PASS` | `scripts/golden-boot.sh` |
| Battery | `SELFTEST: <a>/<b> PASS` with `a == b` and `a >= 74` | `apps/SelfTest.HC:SelfTestRun` |
| Engine parity | `engine parity: <n>/<n> agree, 0 diff` | `apps/SelfTest.HC` |
| Twins | `TWINS: 5/5` | `apps/SelfTest.HC` |
| Symbols | `SYMS: <n> symbols, 0 unresolved` | `apps/SelfTest.HC` |
| Golden frame | `RENDER: PASS (golden=0xD28836F)` | `apps/SelfTest.HC:SelfTestRender` |
| Census | `CENSUS: PASS` | `scripts/census-c-runtime.sh` |
| Self-host | `SELF-HOST: PASS` | `scripts/self-host-test.sh` |
| Determinism | `DETERMINISM: PASS` | `scripts/determinism-gate.sh` |
| **New** GL conformance | `GL: PASS` | `apps/SelfTest.HC:SelfTestGL` |
| **New** tile raster | `TILE: PASS` | `apps/SelfTest.HC:SelfTestTile` |
| **New** telemetry | `TELEMETRY: PASS` | `apps/SelfTest.HC:SelfTestTelemetry` |
| **New** benchmark | `BENCH: PASS` | `apps/SelfTest.HC:SelfTestBench` |

Unchanged subsystem gates that must stay green: `RASTER: PASS`, `KHEAP: PASS`, `TEXTURE: PASS`,
`FONTS: PASS`, `3D: PASS`, `3D-GEARS: PASS`, `SHADING: PASS`, `SHADERVM: PASS`, `MESH: PASS`,
`DOLDOC: PASS`, `SHELL: PASS`, `TICK/SCHED/BSOD/SMP/SOVEREIGN: PASS`, `HALCACHE: PASS`, `FSRT: PASS`.

---

## 3. Preconditions (before touching anything)

1. `git status` clean at `d657e70`; `git bundle create /home/user/project/neo-os.bundle --all` (P7 baseline).
2. `scripts/golden-boot.sh` prints `GOLDEN BOOT: PASS` **before** any edit. Record the baseline:
   `RENDER: PASS (golden=0xD28836F)`, `SELFTEST: 87/87 PASS`, `PARITY: 56/56`, `TWINS: 5/5`,
   `SYMS: … 0 unresolved`, `CENSUS: PASS`. Freeze `tests/census-baseline.txt` (do **not** run `--write`).
   Capture the current UART `renderbench` output (`apps/Render.HC:743`) as the P7.0 perf baseline.
3. Confirm `tests/census-baseline.txt` is exactly: `kmalloc 55`, `kfree 52`, `symbols_register 38`,
   `symbols_lookup 26`, `symbols_is_defined 1`, `symbols_var_cell 1`, `symbols_sic_cell 1`,
   `symbols_count 1`, `symbols_unresolved_count 1`, `jit_compile_and_run 5` (**total 181**).
4. Snapshot (read-only): `git rev-parse HEAD`; the `KERNEL-INIT` module list (`apps/KernelInit.HC:56-108`);
   the count literal `ALL 34 HOLYC SUBSYSTEMS` (`apps/KernelInit.HC:111`, gated at `scripts/golden-boot.sh:25`).
5. Tooling: `aarch64-linux-gnu-as` + `aarch64-linux-gnu-objdump` (regenerate `.s` words; command at
   `scripts/raster_span.s:7-9`); QEMU + the `/api/neo-os/stream` screendump endpoint live.
6. **Do not** start the dev server or run the build unless a step explicitly needs a gate; the gate rebuilds.

---

## 4. Global laws, made operational

| Law | Operational rule for P7 |
|---|---|
| No new `.c` | All new code is `.HC` + `.s`. Edit an existing `boot/seed/*.c` only if an intrinsic parity edit is required; never create a `.c`. |
| No stubs/mocks/placeholders | Every knob has a real reader; every counter reads real hardware; unsupported values are *rejected with a diagnostic*, never silently ignored. |
| No forward declarations | Never write `Type name(args);` (D17). HolyC resolves forward *references* via the symbol table. |
| One pipeline | 3D and tile rendering both funnel through `RasterTriangleZCore → RasterRow → RasterSpanNEON`. The 2D golden path uses the **solid** branch (`tex_ptr==0 && gmode==0`). |
| Golden hash | `g_render_golden = 0x0D28836F` (`apps/SelfTest.HC:327`). The scene (`apps/Render.HC:718`) is drawn **only** through the immediate `RasterTriangleZ` path. See §7. |
| Census | Never add a `kmalloc(`/`kfree(`/`symbols_*(`/`jit_compile_and_run(` call site in `apps/*.HC`. Use static BSS buffers and existing accessors. See §7. |
| 8-arg cap | Every new function has ≤ 8 parameters. Cross a boundary with a descriptor struct passed by pointer, or with globals. |
| Cross-module access | Never read/write another module's struct members. Add an exported accessor. Existing violations to fix: `apps/Gears3D.HC:217`, `apps/Physics3D.HC:338,389,412,421` (write `g_hgl.v_curr.color`). |
| Compiler quirks | Follow §8 (D17–D21 + arithmetic/declaration rules). |

---

## 5. Step-by-step sequence P7.0 → P7.9

Each step lists **files touched**, **exact anchors**, **port source**, **assembly**, **golden-hash risk**,
**census risk**, **verify**. Do the steps in order; commit + bundle after each green step.

---

### P7.0 — Recon / baseline freeze

- **Goal.** Freeze the P7 baseline so every later step is a diff against a known-good tree.
- **Files touched.** None (record in the PR/commit body).
- **Actions.** Run `scripts/golden-boot.sh`; capture `/tmp/golden-boot.png`. Run UART `renderbench` and
  record the three lines (Z-raster tri/s + Kpix/s, Textured tri/s + Kpix/s, Canvas Mpix/s). Record
  `SELFTEST/PARITY/TWINS/SYMS/CENSUS/DETERMINISM` exactly. Bundle.
- **Golden-hash risk.** None. **Census risk.** None.
- **Verify.** `GOLDEN BOOT: PASS` reproduced twice (rules out flake).

---

### P7.1 — HolyGL GL 1.3 surface completion + GL conformance

**Goal.** Complete the GL state machine; add a conformance gate; keep per-fragment Blinn-Phong.

- **Files touched.** `apps/HolyGL.HC`; `apps/SelfTest.HC` (new `SelfTestGL`); `apps/Shell.HC` (optional
  `glconform` command).
- **Exact anchors (`apps/HolyGL.HC`).** `class GLVertex` :23-34; `class HolyGLContext` :36-65 (`CMat4
  projection` :38, `CMat4 modelview_stack[8]` :40, `I64 modelview_sp` :41); `g_hgl` :67; `HolyGLInit`
  :117-158; `HolyGLUpdateMVP` :160-162; matrix ops `HolyGLMatrixMode` :187, `HolyGLLoadIdentity` :191,
  `HolyGLPushMatrix` :200, `HolyGLPopMatrix` :207, `HolyGLTranslatef` :215, `HolyGLRotatef` :224,
  `HolyGLScalef` :234, `HolyGLPerspective` :239; bindings :451-463; accessor :539.
- **Edits.**
  1. **Struct.** Replace `CMat4 projection;` with `CMat4 projection_stack[4];` + `I64 projection_sp;`.
     Widen `CMat4 modelview_stack[8]` → `[16]`. Add `F64 clear_r; F64 clear_g; F64 clear_b; F64 clear_a;`
     (one initialized var per declaration).
  2. **Current-matrix helper** (port `holygl.c:60-65`):
     `CMat4* HolyGLCurrentMatrix() { if (g_hgl.matrix_mode == GL_PROJECTION) return &g_hgl.projection_stack[g_hgl.projection_sp]; return &g_hgl.modelview_stack[g_hgl.modelview_sp]; }`
  3. **Push/Pop** (port `holygl.c:73-99`): projection depth 4, modelview depth 16, operating on the current
     mode; keep `HolyGLUpdateMVP()` after each mutation.
  4. **LoadIdentity / Translatef / Scalef / Perspective** operate on `HolyGLCurrentMatrix()`
     (port `holygl.c:67-138`). `Mat4Mul(out,out,&x)` is alias-safe (temp, `apps/Math3D.HC:287-309`).
  5. **Rotatef.** Keep the existing per-axis dispatch (:224-232) but apply it to the current matrix
     (`Mat4RotateX/Y/Z(current, …)`). This preserves exact `3D-GEARS` geometry (unit-axis callers).
  6. **Add bindings** (thin forwarders): `glPushMatrix`, `glPopMatrix`, `glRotatef`, `glScalef`,
     `glColor3f`, `glColor4f`, `glClear`, `glClearColor`, `glFlush`, `glVertex2f`.
  7. **`glClear(mask)`** (port `holygl.c:149-162`): `#define GL_COLOR_BUFFER_BIT 0x4000` and
     `#define GL_DEPTH_BUFFER_BIT 0x0100` at the top; colour bit → `gfx_clear(colour from clear_rgba)`,
     depth bit → `RasterClearZ()`.
  8. **`glClearColor(r,g,b,a)`** stores the F64s; **`glColor4f`** sets `g_hgl.v_curr.color` exactly like
     `holygl.c:180-186`; `glColor3f` forwards with alpha 1.
  9. **`glFlush()`** → `gfx_dirty_expand(vp_x,vp_y,vp_w,vp_h)` (same as `HolyGLEnd` :437-440).
  10. Leave `HolyGLSubmitTriangle`'s `w <= 0.05` reject (:292) for now; P7.2 replaces it.
- **Port source.** `kernel/math/holygl.c:60-186`, `:381`.
- **Assembly.** None.
- **Golden-hash risk.** **None** — the 2D golden scene never touches HolyGL. Risk is to `3D`/`3D-GEARS`;
  keep Rotatef axis semantics and re-verify.
- **Census risk.** None.
- **Verify.** Add `SelfTestGL()` (expand `HolyGLTest.HC`'s 4 assertions): (1) modelview push/translate/pop
  isolation (`HolyGLTest.HC:8-24`); (2) projection stack depth 4 (push/translate/pop, `projection_sp`
  returns to 0, top translation intact); (3) modelview depth 16 (17th push is a no-op, no OOB); (4)
  `gluPerspective` `m[14]≈-1`, `m[5]>0` (`HolyGLTest.HC:26-35`); (5) `glColor4f(1,0,0,0.5)` →
  `0x80FF0000`; (6) `glClear` colour/depth effects; (7) a lit triangle increments `HolyGLGetTrisRendered()`
  (`HolyGLTest.HC:50-76`). Print `GL: PASS`. Call from `SelfTestRun`.
  Gates: `GL: PASS`, `3D-GEARS: PASS`, `3D: PASS`, `SHADING: PASS`, `RENDER: PASS (0xD28836F)`.

---

### P7.2 — Near-plane Sutherland–Hodgman clipper + NEON memory kernels

**Goal.** Clip triangles against `w >= near` (1–2 output triangles) instead of rejecting; add NEON
blit/blend/clear in `Render.HC`.

- **Files touched.** `apps/HolyGL.HC` (clipper + integration); `apps/Render.HC` (NEON kernels + use);
  new `scripts/render_neon.s`; `apps/GfxDevice.HC` (route `GfxDeviceFastClear`).
- **Exact anchors.** `HolyGLSubmitTriangle` :290-365 (reject :292); `HolyGLVertex3f` triangle emission
  :414-430; `RenderDrawRect` :308-343 (scalar row fill :333-342); `gfx_blend_rect` :484-530;
  `gfx_swap_buffers` :587-595; `gfx_swap_rect` :596-618; `GfxDeviceFastClear` :562-579.
- **Edits.**
  1. **Clipper** (port `kernel/math/math3d.c:775-866`): add `HolyGLLerpVertex(GLVertex *out, GLVertex *a,
     GLVertex *b, F64 t)` and `I64 HolyGLClipNear(GLVertex in[3], F64 near_w, GLVertex out[2][3])`.
     `out` is a local array in `HolyGLVertex3f` (2×3×sizeof(GLVertex) = 480 B — within the 4080 B frame).
  2. **Integrate.** In `HolyGLVertex3f`, when a triangle's 3-vertex buffer fills, clip then submit each
     output triangle via `HolyGLSubmitTriangle`. **Remove** the early reject at :292 (the clipper guarantees
     `w >= 0.05`). Keep the `cross <= 0` cull (:309).
  3. **NEON memory kernels.** Write `scripts/render_neon.s` (source-of-truth) and embed its words via
     `asm { … }` in `apps/Render.HC` (pattern `apps/RasterTile.HC:374-503`):
     - `RenderNeonFill(U32 *dst, I64 count, U32 color)` — 8 px/iter (`dup v0.4s,w2; stp q0,q0,[x0],#32`),
       scalar tail. Replaces the row loop :333-342 and backs `GfxDeviceFastClear`.
     - `RenderNeonBlit(U32 *dst, U32 *src, I64 bytes)` — port `gui/render.c:15-35` (8×`ldp`/`stnp`, 128 B/iter),
       used by `gfx_swap_buffers`/`gfx_swap_rect`.
     - `RenderNeonBlendRect(U32 *dst, I64 n, U32 premul, U32 inv_a)` — 8-lane SRC_ALPHA/ONE_MINUS_SRC_ALPHA
       with the exact `+128 >>8` math, must equal `apps/Render.HC:511-529`.
  4. **Expose** `RenderNeonFill`; `GfxDeviceFastClear` calls it (removes the 8× scalar unroll at
     `apps/GfxDevice.HC:562-579`).
- **Port source.** `kernel/math/math3d.c:775-866`; `gui/render.c:15-35,209,418-530`.
- **Assembly.** `scripts/render_neon.s` (new).
- **Golden-hash risk.** `gfx_clear` is in the golden scene; the NEON fill stores the same `U32` per pixel →
  byte-identical result, hash unchanged. `gfx_blend_rect` is **not** in the golden scene but must stay
  bit-exact. `gfx_swap_*` is not part of `RenderHashBuffer`. The clipper touches 3D submission only.
- **Census risk.** None.
- **Verify.** `GL: PASS` (add: a triangle with one vertex at `w=0.02` yields 2 clipped triangles and
  non-zero coverage), `3D: PASS`, `3D-GEARS: PASS`, `RENDER: PASS (0xD28836F)`, `CENSUS: PASS`.

---

### P7.3 — L1 tile binning + per-core scratchpad + `stnp` streaming resolve

**Goal.** Add a real tiled scene API that reuses the **one** kernel, with per-core L1 scratchpads and a
non-temporal resolve. The immediate `RasterTriangleZ` path stays byte-identical.

- **Files touched.** `apps/RasterTile.HC`; new `scripts/tile_resolve.s`; `apps/SelfTest.HC` (`SelfTestTile`).
- **Exact anchors.** `I64 TILE_W = 64; I64 TILE_H = 64;` :22-23 (**currently unused** — the hook);
  `g_zbuf` globals :25-28; `g_raster_fb/pitch/cw` :36-38; `RasterTriangleZ` :711-766; `RasterRow` :670-708;
  `RasterSpanBlocks` :529-601; `RasterInit` :285-301; `RasterClearZ` :303-307.
- **Edits.**
  1. **Bit-exact hoist.** Extract the body of `RasterTriangleZ` :711-766 into
     `I64 RasterTriangleZCore(I64 x0,I64 y0,I64 x1,I64 y1,I64 x2,I64 y2, U32 color)` (7 args) using the
     globals `g_raster_fb`, `g_raster_pitch`, `g_zbuf`, `g_zbuf_w`, `g_zbuf_h` — **no** `RasterInit()`,
     **no** `GfxDeviceTarget()`. `RasterTriangleZ` becomes: `RasterInit(); if(!g_zbuf) return 0;
     g_raster_fb = GfxDeviceTarget(); if(!g_raster_fb) return 0; g_raster_pitch = gfx_get_canvas_pitch();
     return RasterTriangleZCore(…);`
  2. **Static scene storage** (BSS, census-neutral):
     `#define RASTER_MAX_SCENE_TRIS 4096`, `#define RASTER_MAX_TRIS_PER_TILE 256`,
     `#define RASTER_MAX_TILES (48*32)`; `class CRasterTri { F64 x[3]; F64 y[3]; I64 z[3]; U32 color;
     I64 min_tx; I64 max_tx; I64 min_ty; I64 max_ty; }`; `class CRasterBin { U16 idx[RASTER_MAX_TRIS_PER_TILE];
     I64 count; }`; `CRasterTri g_rs_tris[RASTER_MAX_SCENE_TRIS]; CRasterBin g_rs_bins[RASTER_MAX_TILES];`
     plus scalar globals `g_rs_tri_count/g_rs_cols/g_rs_rows/g_rs_tile_size/g_rs_target/g_rs_pitch/g_rs_clear`;
     `U32 g_tile_color[4][64*64];` and `U16 g_tile_depth[4][64*64];`. All global — never local.
  3. **API** (≤ 8 args each): `RasterSceneBegin(I64 vx,I64 vy,I64 vw,I64 vh, U32 clear)`;
     `RasterSceneAddTriangle(CRasterVertex *v, U32 color)` (2 args; cull port `raster_tile.c:159-162`,
     bbox port `:185-195`, bin port `:197-206`); `RasterSceneEnd()`.
  4. **`RasterRenderTile(t)`**: clear `g_tile_color[core]` (NEON fill) and `g_tile_depth[core]` to `0xFFFF`;
     save `g_raster_fb/pitch/cw` + `g_zbuf/g_zbuf_w/g_zbuf_h`, point them at the scratchpad with `cw=ch=64`;
     call `RasterTriangleZCore(local coords)` per binned tri (local = world − tile origin); restore.
  5. **`RasterTileResolve`**: copy tile rows to `g_rs_target` with `stnp` from `scripts/tile_resolve.s`
     (port `raster_tile.c:411-444`), clipped to screen/viewport and to the partial last tile. The
     *rasterization* is still `RasterSpanNEON`; only the tile→target copy is a new kernel.
- **Port source.** `kernel/math/raster_tile.c:46-209`, `:411-444`.
- **Assembly.** `scripts/tile_resolve.s` (new).
- **Golden-hash risk.** **None iff** `RenderGoldenScene` never calls `RasterScene*` (it does not — it calls
  `RasterTriangleZ`, `apps/Render.HC:736`). Prove the hoist with `RENDER: PASS (0xD28836F)` + `RASTER: PASS`
  **before** adding tiling.
- **Census risk.** None (BSS only).
- **Verify.** `SelfTestTile()`: (1) a fixed triangle through the tiled path vs the immediate path must be
  pixel- and Z-identical; (2) a triangle straddling 4 tiles resolves with `gaps == 0` (mirror
  `apps/RasterTile.HC:787-803`); (3) an off-screen triangle writes no guard word past the scratchpad.
  Print `TILE: PASS`. Call from `SelfTestRun`. Gates: `TILE: PASS`, `RENDER: PASS (0xD28836F)`,
  `RASTER: PASS`, `CENSUS: PASS`.

### P7.4 — SMP tile dispatch + SMP parallel vertex transform; make `GFX_MODE_SMP_TILED` real

**Goal.** Split tiles across online cores (each into its own scratchpad), then resolve; add a parallel vertex
transform; make `GfxDeviceSetMode(GFX_MODE_SMP_TILED)` actually change the render path.

- **Files touched.** `apps/Smp.HC` (async dispatch); `apps/RasterTile.HC` (SMP end); `apps/Math3D.HC`
  (parallel transform); `apps/Mesh.HC` (use it); `apps/GfxDevice.HC` (mode read).
- **Exact anchors.** `apps/Smp.HC` `SmpDispatch` :169-201 (blocking), `SmpIsJobDone` :203, `SmpWaitJob`
  :209, `smp_dispatch` :260; `apps/GfxDevice.HC` `GFX_MODE_SMP_TILED` :15, `GfxDeviceSetMode` :497-507,
  `GfxDeviceGetMode` :509; `apps/Math3D.HC` `Mat4MulVec4` :366-375; `apps/Mesh.HC` `MeshRender`.
- **Edits.**
  1. **`apps/Smp.HC`:** add `I64 SmpDispatchAsync(U32 core_id, U64 fn, U64 arg)` — identical to `SmpDispatch`
     :169 but **without** the completion spin (sets `j->pending=1`, `__sev()`, returns 0/-1). `SmpWaitJob`
     remains the join. Reuses `CSmpJob`; no new allocation.
  2. **`apps/RasterTile.HC`:** add `class CTileJob { I64 start; I64 end; I64 core; };`,
     `CTileJob g_tile_jobs[4];`, `U0 RasterTileWorker(U64 arg)` (renders its tile range into
     `g_tile_color[core]`/`g_tile_depth[core]`, then `__dmb_ish()` and marks `core = -core - 1`), and
     `U0 RasterSceneEndSmp()`: read cores from the config plane; if `<= 1` render all tiles on core 0; else
     compute `per = (total + cores - 1) / cores`, `SmpDispatchAsync` cores 1..n-1, render slice 0 on core 0,
     then `while (g_tile_jobs[c].core >= 0) __wfe();` and a final `__dmb_ish()`. Tiles are disjoint →
     deterministic regardless of core count.
  3. **`RasterSceneEnd`** selects: `if (GfxDeviceGetMode()==GFX_MODE_SMP_TILED) RasterSceneEndSmp(); else`
     single-core. Honour `RASTER_ENGINE_SCANLINE` (P7.5) by falling back to the immediate per-triangle path.
  4. **`apps/Math3D.HC`:** port `math3d.c:1189-1232` as `U0 Math3DTransformParallel(CVec3 *in, CVec4 *out,
     I64 count, CMat4 *mvp)` — split at `count/2`, dispatch the second half to core 1 via `SmpDispatch`,
     transform the first half locally. Guard `count < 8` or core offline → scalar loop.
  5. **`apps/Mesh.HC`:** in `MeshRender`, batch-transform into a static `CVec4 g_mesh_xform[MESH_MAX_V]`
     via `Math3DTransformParallel`, then feed the transformed vertices through the same submit path.
  6. **Fix cross-module violations:** replace `g_hgl.v_curr.color = …` at `apps/Gears3D.HC:217` and
     `apps/Physics3D.HC:338,389,412,421` with `HolyGLColor3ub(...)` / a new exported
     `HolyGLSetCurrentColor(U32)`.
- **Port source.** `kernel/math/raster_tile.c:447-556`; `kernel/math/math3d.c:1189-1232`.
- **Assembly.** None new (`__dmb_ish`/`__sev`/`__wfe` already exist, `apps/Compiler.HC:2273-2276`).
- **Golden-hash risk.** None (golden path is immediate + IRQ-masked). **Determinism risk is real:** the SMP
  tile test must equal the single-core result byte-for-byte; `DETERMINISM: PASS` must hold.
- **Census risk.** None.
- **Verify.** Extend `SelfTestTile` with an SMP sub-test (1 vs 4 cores, byte-compare) → `TILE: PASS`.
  `SMP: PASS`, `DETERMINISM: PASS`, `RENDER: PASS (0xD28836F)`. Manual: UART `render smp` then `renderbench`.

---

### P7.5 — GPU config plane + VirtIO batch2/batch3 + page-flip ping-pong (+ optional 32-bit Z)

**Goal.** Real GPU knobs, batched VirtIO submission, dual-resource page-flip.

- **Files touched.** `apps/GfxDevice.HC` (config plane, batch2/3, page-flip); `apps/RasterTile.HC` (knob
  readers); `apps/HolyGL.HC` (culling reader); `apps/Shell.HC` (`gpuconfig` command).
- **Exact anchors.** `apps/GfxDevice.HC` `CGfxDeviceState` :24-31, `g_gdev` :33, `VirtioGpuSendCmd` :191-238,
  `VirtioGpuInit` :240-425, `VirtioGpuFlushRect` :427-473, `GfxDeviceSetMode` :497; `apps/HolyGL.HC`
  `g_hgl.cull_face` :46, `HolyGLEnable/Disable` :164/172.
- **Edits.**
  1. **Config plane** (port `drivers/gpu/gfx_backend.c:98-163`): `class CGpuConfig { I64 zprecision; I64
     raster_engine; I64 tile_size; I64 smp_cores; I64 culling; };` + `CGpuConfig g_gpu_cfg;` +
     `gpu_set_zprecision/get`, `gpu_set_raster_engine/get`, `gpu_set_tile_size/get`, `gpu_set_smp_cores/get`,
     `gpu_set_culling/get`. Every setter has a **real reader**: `RasterSceneBegin/End` reads `raster_engine`,
     `tile_size`, `smp_cores`; `RasterSceneAddTri` reads `culling`. `gpu_set_zprecision` accepts 16; for 32 it
     **returns an error and leaves the value at 16** unless P7.5c landed (honest rejection, never a silent
     stub); `GpuConfigPrintDolDoc` shows `32-bit Z: unsupported` in that case.
  2. **Batch2/Batch3** (port `virtio_gpu.c:84-200`): batch3 has 12 params → exceeds the 8-arg cap. Add
     `class CVirtioBatch { U64 cmd[3]; U32 cmd_sz[3]; U64 resp[3]; U32 resp_sz[3]; };` and
     `I64 VirtioGpuSendBatchN(CVirtioBatch *b, I64 n)` (2 args), with `VirtioGpuSendBatch2/3` wrappers.
     `VirtioGpuFlushRect` :452-471 becomes one batch2 (transfer + flush). Descriptors 0..5, two avail entries.
  3. **Page-flip ping-pong** (port `virtio_gpu.c:368-387`, `:409-451`): in `VirtioGpuInit`, create resource 2
     for `gfx_get_frontbuffer()` and attach backing (mirrors resource 1). Add `I64 VirtioGpuPageFlip(I64
     resource_id)` issuing batch3 (transfer→scanout→flush) and flipping `g_s_active_scanout`. `GfxPresent`
     :541 calls it in GPU mode when not zero-RAM.
  4. **Shell:** register `gpuconfig` (`apps/Shell.HC:1010-1058`) → `GpuConfigPrintDolDoc()` rendering the 5
     knobs + current values as a `$CARD$`.
- **Port source.** `drivers/gpu/gfx_backend.c:98-163,679-697`; `drivers/gpu/virtio_gpu.c:84-200,368-451`.
- **Assembly.** None.
- **Golden-hash risk.** None (config affects the tile/3D/bench path only). **Census risk.** None.
- **Verify.** `GfxDeviceSelfTest` passes; `SelfTestTile` toggles `gpu_set_tile_size(32)` and re-runs the tile
  equality check (proves the knob is read); `SelfTestBench` asserts `gpu_set_smp_cores(1)` vs `(4)` yields
  identical tile output. Manual: `render gpu` screenshot with no fault; `VirtioGpuIsAvailable()==1`.

#### P7.5c — Optional 32-bit Z tile kernel (start only after P7.0–P7.9 are green)

- Derive `scripts/raster_span32.s` mechanically from `scripts/raster_span.s`: `ZLANE` emits
  `ins v28.s[k], w0` (8×.4s) instead of `ins v28.h[k], w0`; the depth compare becomes two `cmhi v30.4s` +
  an AND; `zb_ptr` advances 32 B/block; the Z clear writes `0xFFFFFFFF`. Embed as `RasterSpanNEON32` in
  `apps/RasterTile.HC`; `RasterRenderTile` selects it when `gpu_get_zprecision()==32` and uses
  `U32 g_tile_depth32[4][64*64]`. The immediate/golden path stays 16-bit and never selects it.
  Gate: `TILE: PASS` at zprecision 16 **and** 32.

---

### P7.6 — Merge `Profiler.HC` + `PerfOverlay.HC` → `apps/Telemetry.HC` + real ARM PMU

**Goal.** One telemetry engine with a `mark_*` API, percentiles, spike ring + causes, optimization
directives, and PMU counters. Delete the two old modules.

- **Files touched.** New `apps/Telemetry.HC`; delete `apps/Profiler.HC`, `apps/PerfOverlay.HC`;
  `apps/KernelInit.HC` (Stage 6); `apps/Compiler.HC` (PMU intrinsics); `apps/SelfTest.HC`
  (`SelfTestTelemetry`); `apps/HolyBenchmark.HC` (call sites); `apps/Gears3D.HC`/`apps/Physics3D.HC`
  (accessor fix); `scripts/golden-boot.sh` (module count, P7.8).
- **Exact anchors.** `apps/Profiler.HC` `CProfilerSpike` :16-27, `CProfiler` :29-86, `g_prof` :88,
  `ProfilerInit` :102, `ProfilerPhaseReset` :143, `ProfilerDiagnoseBottleneck` :148, `ProfilerComputeMetrics`
  :168 (percentiles :201-239), `ProfilerRecordFrame` :242, `ProfilerWriteLogs` :309 (kmalloc :310).
  `apps/PerfOverlay.HC` `CSpikeRecord` :17-26, `CPerfOverlay` :28-66, `g_perf` :68, `PerfOverlayInit` :82,
  `PerfOverlayRecordBlit/SmpWait/WmOverhead` :125/129/133, `PerfOverlayRecordFrame` :137, `PerfOverlayDraw`
  :219. `apps/KernelInit.HC:97-108` (Stage 6), count literal :111. `apps/Compiler.HC` `HcIsIntrinsic`
  :2261-2270, `HcEmitIntrinsic` :2272-2293.
- **Edits.**
  1. **`apps/Telemetry.HC`** — one module:
     - `CTelemetry` (merge of `CProfiler` + `CPerfOverlay`: 256-bin histogram, 128-spike ring, 64-record
       cause ring). Global `CTelemetry g_tel;`.
     - **`mark_*` API** (port `profiler.c:57-116`): `TelemetryBeginFrame`, `TelemetryMarkLogicStart/End`,
       `TelemetryMarkRasterStart/End`, `TelemetryMarkBlitStart/End`, `TelemetryMarkDmaStart/End`,
       `TelemetryMarkWmStart/End`, `TelemetryRecordSmpWait(I64)`, `TelemetryEndFrame`.
     - **Percentiles** (port `profiler.c:224` + `Profiler.HC:201-239`): compute FPS avg, **1 % low**,
       **0.1 % low** (currently never computed in `PerfOverlay.HC`), min/max/stddev once, in
       `TelemetryComputeMetrics`.
     - **Spike ring with causes** (merge `CProfilerSpike` + `CSpikeRecord`; cause enum `PerfOverlay.HC:8-15`
       + `BOTTLENECK_*` `Profiler.HC:8-14`).
     - **Optimization directive** (port `profiler.c:294-327`): `U8* TelemetryDirective(I64 bottleneck)`.
     - **Logs with static buffers:** `U8 g_tel_log[16384];` (removes the `kmalloc` at `Profiler.HC:310` and
       `kfree` at :372). `TelemetryWriteLogs()` writes `BENCH_PROFILER.LOG` + `BENCH_SPIKES.LOG` via
       `redsea_write_file`.
     - **HUD:** `TelemetryDraw(I64 ox, I64 oy)` (port `PerfOverlay.HC:219-296`) with a real 1 %-low readout.
  2. **PMU** (real hardware). Add intrinsics to `apps/Compiler.HC` (`HcIsIntrinsic` :2261 + `HcEmitIntrinsic`
     :2272). Encoding: `MRS X0,<sysreg> = 0xD5300000 | op0<<19 | op1<<16 | CRn<<12 | CRm<<8 | op2<<5`;
     `MSR = 0xD5100000 | …`. Verify each word with `aarch64-linux-gnu-as` before embedding (pattern
     `scripts/raster_span.s:7-9`).

     | name | MRS word | MSR word |
     |---|---|---|
     | `__mrs_pmcr` / `__msr_pmcr` (PMCR_EL0) | `0xD54B9C00` | `0xD51B9C00` |
     | `__mrs_pmccntr` / `__msr_pmccntr` (PMCCNTR_EL0) | `0xD54B9D00` | `0xD51B9D00` |
     | `__mrs_pmevcntr0` / `__msr_pmevcntr0` (PMEVCNTR0_EL0) | `0xD54BE800` | `0xD51BE800` |
     | `__mrs_pmevtyper0` / `__msr_pmevtyper0` (PMEVTYPER0_EL0) | `0xD54BEC00` | `0xD51BEC00` |
     | `__msr_pmcntenset` (PMCNTENSET_EL0) | — | `0xD51B9C20` |
     | `__msr_pmcntenclr` (PMCNTENCLR_EL0) | — | `0xD51B9C40` |

     `TelemetryPmuInit()`: `__msr_pmcr` with `E=1|P=1|C=1|D=1|LC=1`; program `PMEVTYPER0=0x08`
     (`INST_RETIRED`), `PMEVTYPER1=0x03` (`L1D_CACHE_REFILL`), `PMEVTYPER2=0x10` (`BR_MIS_PRED`);
     `__msr_pmcntenset` with `0x80000007`. `TelemetryPmuProbe()`: read `PMCCNTR_EL0`, run a fixed loop, read
     again; if it did not advance, set `g_tel.pmu_available = 0` and keep `CNTVCT_EL0` deltas authoritative
     (honest fallback — QEMU TCG may not implement PMU counters). `TelemetryPmuSnapshot()` fills
     `cycles/inst/l1d/br`.
     **Seed parity:** the C seed (`boot/seed/jit_arm64.c:1005+`) compiles **only** `Compiler.HC` (P2.7), which
     does not call PMU intrinsics → a seed edit is **not required**. Add them to the seed only if the parity
     corpus later gains a PMU case (existing-file edit, allowed).
  3. **`apps/KernelInit.HC` Stage 6** (:97-108): replace `Profiler.HC` + `PerfOverlay.HC` with `Telemetry.HC`.
     Update the count literal :111 from `34` to `31` (34 − 1 telemetry − 2 bench merges).
  4. **Call-site updates.** Replace `ProfilerInit`/`PerfOverlayInit`/`ProfilerRecordFrame`/
     `PerfOverlayRecordFrame`/`PerfOverlayDraw`/`ProfilerWriteLogs`/`g_prof.fps_avg` in `apps/HolyBenchmark.HC`
     (rewritten in P7.7) with `Telemetry*`. `rg -n 'g_prof|g_perf|Profiler|PerfOverlay' apps/` → zero outside
     `Telemetry.HC`.
  5. **Cross-module fix** (as P7.4 item 6).
- **Port source.** `kernel/bench/profiler.c:57-116,224,294-327,329,386`;
  `kernel/bench/perf_overlay.c:189-195,238-249`.
- **Assembly.** None new (PMU is `__mrs_*`/`__msr_*`).
- **Golden-hash risk.** None.
- **Census risk.** **Decreases** kmalloc/kfree by 1 each (static log buffer) → gate prints `[DOWN]`, still
  `CENSUS: PASS`. Do **not** re-baseline yet.
- **Verify.** `SelfTestTelemetry()`: (1) `mark_*` records 100 frames → `valid_sample_count==95` (warmup 5);
  (2) `fps_1pct_low > 0` and `fps_01pct_low > 0`; (3) a forced 65 ms frame lands in the spike ring with a
  cause; (4) `TelemetryDirective(BOTTLENECK_CPU_RASTER)` is non-empty; (5) `TelemetryPmuInit()` +
  `TelemetryPmuProbe()` reports without faulting; (6) `TelemetryWriteLogs()` writes both files. Print
  `TELEMETRY: PASS`. Call from `SelfTestRun`. Gates: `TELEMETRY: PASS`, `CENSUS: PASS`, `SELF-HOST: PASS`.

---

### P7.7 — Real 40-phase suite in `HolyBenchmark.HC` (absorb `BenchCpu` + `BenchReport`)

**Goal.** A real 40-phase suite with a 3.5 s limiter, per-phase metric capture, real export files; real NEON
CPU bench; purge synthetic constants and write-only state.

- **Files touched.** `apps/HolyBenchmark.HC` (rewrite); delete `apps/BenchCpu.HC`, `apps/BenchReport.HC`;
  new `scripts/bench_neon.s`; `apps/SelfTest.HC` (`SelfTestBench`); `apps/Shell.HC` (`benchreport`).
- **Exact anchors.** `apps/HolyBenchmark.HC` `g_bench_*` :4-9, `bench_unified_tick_and_draw` :33-90 (the
  `phase%8` bug: `eng = (g_bench_phase / 8) % 5` :59 ignores the variation), fake scorecard :112-119.
  `apps/BenchCpu.HC` `BenchCpuSieve` :4, `BenchCpuMatrixMul` :32, `BenchCpuPointerChasing` :68,
  `BenchCpuMathNeon` :94 (**integer LCG — BEN-01**), `BenchCpuMemBandwidth` :105, `BenchCpuRunAll` :126.
  `apps/BenchReport.HC` `BenchReportMain` :4.
- **Edits.**
  1. **Static records** (BSS): `class CBenchRec { U8 name[48]; F64 fps_avg; F64 fps_1pct; F64 ft_ms;
     F64 render_ms; F64 blit_ms; F64 jitter_ms; I64 bottleneck; };` + `CBenchRec g_bench_records[40];` +
     phase-state globals. **Remove** `g_bench_mode` (write-only). `U8 g_bench_buf[8192];` static.
  2. **Names** (port `bench_unified.c:56-62`): categories `Gears, Cubes, Dynamics, Sphere, Fillrate`;
     variations `SW 1C Base, SW NEON L1, SW SMP 4C, SW DirectVRAM, HW VirtIO, HW DMA+SMP, HW Wireframe,
     HW VSync 60Hz`.
  3. **Applicator** `BenchApplyPhase(I64 phase)` (port `bench_unified.c:64-157`): `cat=phase/8`, `var=phase%8`;
     set the config plane (`gpu_set_raster_engine`, `gpu_set_tile_size(64)`, `gpu_set_smp_cores`,
     `gpu_set_culling`, `GfxDeviceSetMode`, `GfxDeviceSetBuffering`, `GfxDeviceSetShading`, `gfx_vsync_set`).
     `TelemetryPhaseReset(5)`. 3.5 s limiter: `g_bench_dur = (__mrs_cntfrq()*7)/2`, `g_bench_t0 = __mrs_cntvct()`.
  4. **`BenchTickAndDraw()`** (fix :33-90): honour `var = g_bench_phase % 8` (var 6 → wireframe, var 7 → vsync,
     var 3 → zero-RAM, var 5 → GPU+SMP). Render the category scene (`Gears3DRenderViewport`, cubes,
     `Physics3DRenderViewport`, sphere via `HolyGLRenderCubeAt`/`MeshRender`, `DolDocRenderShaderNode(…,"plasma")`)
     through the tile/GPU path, bracketing stages with `TelemetryMark*`. Replace synthetic
     `PerfOverlayRecordFrame(dt, r, 1200)` / `ProfilerRecordFrame(…,1200,400,300)` with **real** measured
     `blit_us` (around `GfxPresent`) and `dma_us` (around `VirtioGpuPageFlip`). **Delete** `1200/400/300` (BEN-02).
  5. **Phase loop:** when `__mrs_cntvct() - g_bench_t0 >= g_bench_dur`, capture the record from `g_tel`,
     advance phase, re-apply. After phase 39, export.
  6. **CPU bench** (fold `BenchCpu.HC` in): keep `BenchCpuSieve`/`MatrixMul`/`PointerChasing`/`MemBandwidth`
     verbatim; **replace `BenchCpuMathNeon` :94** with `BenchMathNeon(U32 *src, I64 n, F64 *out)` whose words
     come from `scripts/bench_neon.s` (2×`.2d` `fmla` dot-product over a static `F64 g_bench_v[4096]`), plus a
     scalar cross-check matching to `1e-9`. No allocation.
  7. **Exports** (static `g_bench_buf`): `BENCH_COMPARISON.TXT` (40 rows: `Ph | Category | Variation | Avg FPS
     | 1% Low | Avg FT | Render | Blit | Jitter | Bottleneck [WINNER]` + 8×5 FPS matrix + winner; port
     `bench_unified.c:377-491`); `BENCH_REPORT.TXT` (port `:493-564`); `BENCH_PROFILER.LOG` + `BENCH_SPIKES.LOG`
     (from `TelemetryWriteLogs`). All via `redsea_write_file`.
  8. **`BenchReportMain`** (fold `BenchReport.HC:4` in) reads the four files into static
     `U8 g_bench_view[32768]` (removes the kmalloc at `BenchReport.HC:9`).
  9. **Shell:** `benchreport` → `BenchReportMain()`.
- **Port source.** `kernel/bench/bench_unified.c:56-157,377-564`.
- **Assembly.** `scripts/bench_neon.s` (new).
- **Golden-hash risk.** None (separate path). **Note:** the full suite takes 40×3.5 s = 140 s → the golden
  gate must **not** run it; `SelfTestBench` runs a short 2-phase smoke version.
- **Census risk.** Decreases kmalloc/kfree (static buffers). Never add a `kmalloc` in the suite.
- **Verify.** `SelfTestBench()`: `BenchApplyPhase(0)` and `(2)` produce different records (variation honoured);
  `BenchMathNeon` matches the scalar cross-check; the four files exist and are non-empty. Print `BENCH: PASS`.
  Manual full run: UART `bench` → screenshots (P7.9). Gates: `BENCH: PASS`, `CENSUS: PASS`.

---

### P7.8 — Rebuild the tests: `SelfTest.HC` is the source of truth; wire the new gates

**Goal.** All new gates live in `apps/SelfTest.HC`; `scripts/golden-boot.sh` asserts them.

- **Files touched.** `apps/SelfTest.HC`; `scripts/golden-boot.sh`; `tests/jit_golden/cases.json` (mark
  historical); `docs/02-TASKLIST.md` (matrix numbers only).
- **Exact anchors.** `apps/SelfTest.HC` gate calls :986-1009, summary :1011-1018; `scripts/golden-boot.sh`
  `check()` :14, selftest block :40-232, module-count check :25, census :234, self-host :237, determinism :240.
- **Edits.**
  1. `SelfTestRun` (`apps/SelfTest.HC:851`): after `SelfTestStructPtrScale()` (:999) insert `SelfTestTile();`;
     after `SelfTestRender()` (:1007) insert `SelfTestGL(); SelfTestTelemetry(); SelfTestBench();`. Keep them
     in the fresh-compiler-state window (all before the sentinel).
  2. `scripts/golden-boot.sh`: after the `SHELL: PASS` block (:225-231) add four grep blocks for `GL: `,
     `TILE: `, `TELEMETRY: `, `BENCH: ` (same pattern as the others, checking `PASS`). Update line 25:
     `check "all 34 subsystems" 1 "$(count 'ALL 34 HOLYC SUBSYSTEMS')"` →
     `check "all 31 subsystems" 1 "$(count 'ALL 31 HOLYC SUBSYSTEMS')"`.
  3. `tests/jit_golden/cases.json`: mark **historical / superseded by `apps/SelfTest.HC`** (top-of-file note
     or rename the directory). Ensure `scripts/golden-boot.sh` does **not** invoke `run-jit-golden.py` (it
     already does not — keep it that way).
  4. At the very end (after all decreases are in) run `scripts/census-c-runtime.sh --write` once to re-baseline
     the (lower) counts, then re-run the gate. Optional; the gate passes without it.
- **Golden-hash risk.** None. **Census risk.** Re-baselining must be **last** and only to a **lower** total.
- **Verify.** `GOLDEN BOOT: PASS` with all four new gate lines `[PASS]`, plus the unchanged gates.

---

### P7.9 — Visual proof (screendumps only, never host desktop)

- **Goal.** Screenshots for each benchmark category, the GPU config window, the GL conformance scene, and the
  telemetry HUD.
- **Files touched.** New `scripts/p7-screenshots.sh` (allowed; not `.c`); output to `docs/images/p7-*.png`.
- **Actions.** Boot via `scripts/run-viewer-vm.sh`; for each of `bench` phase categories, `gpuconfig`,
  `glconform`, `perf`, capture via the existing `/api/neo-os/stream` endpoint (mechanism as
  `scripts/golden-boot.sh:251-258`). Save `p7-bench-gears.png`, `p7-bench-cubes.png`, `p7-bench-dynamics.png`,
  `p7-bench-sphere.png`, `p7-bench-fillrate.png`, `p7-gpuconfig.png`, `p7-glconform.png`,
  `p7-telemetry-hud.png`.
- **Golden-hash risk.** None. **Census risk.** None.
- **Verify.** Each PNG is non-empty and shows the expected scene; the final gate run is still `GOLDEN BOOT: PASS`.

---

## 6. Assembly plan (every NEON kernel to add)

All `.s` files are **source-of-truth, not built** (pattern: `scripts/raster_span.s:1-13`). Regenerate the
instruction words with:

```
aarch64-linux-gnu-as -o /tmp/x.o scripts/<file>.s
aarch64-linux-gnu-objdump -d /tmp/x.o | awk '/^[ ]*[0-9a-f]+:/{print "0x"$2}' | tr a-f A-F
```

then embed them in the `.HC` function as `asm { … }` (pattern: `apps/RasterTile.HC:374-503`,
`apps/ShaderVM.HC` `ShaderOp4`). The block must **not** contain `ret` (the compiler emits the prologue/epilogue)
and must preserve the ABI registers it uses (`x19`–`x28`, `v8`–`v31` as needed) exactly like `RasterSpanNEON`.

| Kernel | Source-of-truth `.s` | Embedded in | Purpose | Correctness test |
|---|---|---|---|---|
| `RasterSpanNEON` (existing: solid/textured/shaded) | `scripts/raster_span.s` | `apps/RasterTile.HC:374` | THE one span kernel | `RENDER: PASS`, `RASTER: PASS`, `TEXTURE/SHADING: PASS` |
| `RenderNeonFill` | `scripts/render_neon.s` (new) | `apps/Render.HC` (`RenderDrawRect` fill, `GfxDeviceFastClear`) | 8-px/iter colour fill | golden hash + `GfxDeviceSelfTest` Test 4 |
| `RenderNeonBlit` | `scripts/render_neon.s` (new) | `apps/Render.HC` (`gfx_swap_buffers`/`gfx_swap_rect`) | 128 B/iter `ldp`/`stnp` copy | byte-compare copied region vs `memcpy` |
| `RenderNeonBlendRect` | `scripts/render_neon.s` (new) | `apps/Render.HC` (`gfx_blend_rect`) | 8-lane SRC_ALPHA blend | compare vs scalar `:511-529` byte-for-byte |
| `RasterTileResolve` | `scripts/tile_resolve.s` (new) | `apps/RasterTile.HC` | `stnp` tile→target streaming | `TILE: PASS` pixel equality |
| `RasterSpanNEON32` (optional P7.5c) | `scripts/raster_span32.s` (new) | `apps/RasterTile.HC` | 32-bit-Z tile span | `TILE: PASS` at zprecision 16 & 32 |
| `BenchMathNeon` | `scripts/bench_neon.s` (new) | `apps/HolyBenchmark.HC` | real NEON FMA compute (BEN-01 fix) | `BENCH: PASS` vs scalar cross-check |

**SMP primitives** use existing intrinsics, no new asm: `__wfe` (`Compiler.HC:2273`), `__sev` (:2274),
`__dmb_ish` (:2275), `__dsb_sy` (:2276), `__isb` (:2277). **PMU** uses the new `__mrs_*`/`__msr_*`
intrinsics added in P7.6. **No kernel is ever duplicated** — the tile path reuses `RasterSpanNEON`; only the
tile→target copy, the memory ops, and the optional 32-bit-Z variant are new.

---

## 7. Golden-hash protection protocol (2D path stays bit-exact)

1. **Single owner.** `g_render_golden = 0x0D28836F` lives at `apps/SelfTest.HC:327`; only `SelfTestRender`
   (`apps/SelfTest.HC:585`) hashes and asserts it. Never change the constant.
2. **Forced solid branch.** `RenderGoldenScene` (`apps/Render.HC:718`) calls `RasterDisableTexture()` +
   `RasterDisableGouraud()` (:721-722) before drawing. In `RasterSpanNEON` the solid path runs **only** when
   `tex_ptr==0` (`scripts/raster_span.s:447-459`) **and** `gmode==0`; the byte-identical store is
   `zip1/zip2 + bsl` over `v31`. No P7 change may alter this branch.
3. **Immediate path only.** The golden scene's triangle uses `RasterTriangleZ` directly
   (`apps/Render.HC:736`). It never enters `HolyGLVertex3f`, the clipper, or `RasterScene*`. Therefore
   P7.1–P7.5 cannot touch it.
4. **The P7.3 hoist is behaviour-preserving.** `RasterTriangleZ` → `RasterTriangleZCore` only moves
   `RasterInit()`/target resolution into the wrapper; the core body (Pineda edges, top-left rule, exact
   64-bit Z `SDIV`, `CMHI.8H`, `BSL`) is unchanged. **Prove it** with `RENDER: PASS (0xD28836F)` and
   `RASTER: PASS` immediately after the hoist, *before* adding any tiling.
5. **NEON memory kernels must be byte-identical.** `gfx_clear`/`RenderDrawRect` fill stores the same `U32`
   per pixel (result identical). `gfx_blend_rect` keeps the exact `+128 >>8` math. `gfx_swap_*` is not part
   of `RenderHashBuffer` (which reads the target before any swap).
6. **IRQ mask.** `SelfTestRender` masks `DAIF` around the render + hash (`apps/SelfTest.HC:586-593`), so a
   preemptive writer cannot perturb the golden frame. Do not remove that mask.
7. **New tiling/SMP only on 3D/benchmark.** The `RasterScene*` API is called only from the 3D viewports and
   the benchmark; never from `RenderGoldenScene`, `RenderBench`, or any 2D `gfx_*` primitive.
8. **Determinism.** The golden hash must be byte-identical on 1 vs 4 cores (`DETERMINISM: PASS`). Tile
   rendering is deterministic because tiles write disjoint pixels in row-major tile order, and each core
   has a private scratchpad.

---

## 8. Census-neutrality protocol

The census (`scripts/census-c-runtime.sh`) counts **call sites** of `kmalloc`, `kfree`, `symbols_register`,
`symbols_lookup`, `symbols_is_defined`, `symbols_var_cell`, `symbols_sic_cell`, `symbols_count`,
`symbols_unresolved_count`, `jit_compile_and_run` across `apps/*.HC` and fails if any count **increases** vs
`tests/census-baseline.txt` (181). Rules for P7:

1. **Static BSS, never heap, for new state.** Tile scratchpads (`g_tile_color/g_tile_depth`), scene
   triangle/bin arrays, telemetry log buffers (`g_tel_log[16384]`), bench records (`g_bench_records[40]`),
   the bench report view (`g_bench_view[32768]`), and mesh transform buffers are all file-scope globals.
2. **Reuse existing accessors, do not add allocations.** The texture path already reuses the `CTexture2D`
   pool; the tile path reuses `RasterSpanNEON`; the benchmark reuses `redsea_write_file` (not a census
   symbol) for exports.
3. **Merges reduce counts, never increase.** `Telemetry.HC` replaces the `kmalloc`/`kfree` in
   `ProfilerWriteLogs` (`Profiler.HC:310/372`) with a static buffer; the merged benchmark replaces
   `BenchReport.HC:9`'s `kmalloc` with a static buffer. These produce `[DOWN]` lines — accepted.
4. **Never introduce `symbols_*` or `jit_compile_and_run` call sites.** Cross-module calls go through
   exported functions resolved at load time, not through `symbols_lookup`.
5. **Check after every step.** Run `scripts/census-c-runtime.sh` (or the gate) after each step; any
   `[FAIL] … (increased)` is a hard stop.
6. **Re-baseline once, last.** Only at the end of P7.8, and only to a **lower** total, run
   `scripts/census-c-runtime.sh --write`. If in doubt, leave the baseline at 181 (the gate accepts
   decreases).

---

## 9. Compiler-workaround checklist (do not re-introduce parser/codegen bugs)

| # | Rule | Why |
|---|---|---|
| D17 | **Never write a function prototype** `Type name(args);`. Define the function; HolyC resolves forward *references* via the symbol table. | A prototype is parsed as an empty definition and silently breaks the real one. |
| D18 | **One initialized variable per declaration.** `U8 a = 1; U8 b = 2;` — never `U8 a = 1, b = 2;`. | Comma-separated *initialized* declarations bind only the first declarator. |
| D19 | Compiler caps are `HC_MAX_FUNCS 512`, `HC_MAX_EPILOGUES 512`. A module with >512 functions/returns must be split. | Larger ceilings are the root fix; do not shrink them. |
| D20 | **Declare a global before the first function that touches it.** Put all new `class`/global declarations at the top of the module. | A global used before its declaration is implicitly sized to 8 bytes and corrupts memory. |
| D21 | **Mask a power-of-two hash; never signed-`%` a `U64`.** Use `& (BUCKETS - 1)`. | `U64 % 128` cast to `I64` is negative → OOB bucket read. |
| A1 | **8-argument hard cap.** A function with >8 parameters is a compile error. Cross boundaries with a descriptor struct pointer or globals. | X0–X7 only; no stack spill. |
| A2 | **No `F64` compound assign / `++`.** Write `x = x + 1.0;`. | Float compound-assign and increment hard-error. |
| A3 | **No `F64 *p` deref.** Use `p[i]`. | `*p` on an F64 pointer is unsupported. |
| A4 | **Local frame ≤ 4080 B.** Large arrays (scratchpads, records, transform buffers) must be globals. | The prologue `SUB SP,SP,#n` is bounded. |
| A5 | **No `strtod`/`atof`.** Parse numbers with integer/`F64` arithmetic. | Not implemented. |
| A6 | **One pipeline / no scalar fallback.** New rendering code goes through `RasterTriangleZCore → RasterRow → RasterSpanNEON`. | Project law. |
| A7 | **No cross-module struct-member access.** Add an exported accessor (e.g. `HolyGLSetCurrentColor`, `RasterGetCores`). | Project law; prevents layout coupling. |
| A8 | **Never `doldoc_printf` from inside the rasterizer.** Diagnostics are globals read after the draw. | A 9-arg print previously failed the module to compile and left dangling symbols → BSOD. |

**Per-module compile sanity.** After each step, the boot log must show `[KERNEL-INIT] <module> compiled, res = 0`
and zero `undefined identifier` / `COMPILER.HC] internal error` / `unresolved reference` lines (the gate already
asserts these at `scripts/golden-boot.sh:26-30`).

---

## 10. Definition of done (mapped to `scripts/golden-boot.sh`)

Run `scripts/golden-boot.sh`; it must print `GOLDEN BOOT: PASS`. The checklist below maps each required
outcome to the exact gate line the script already checks (or the new one P7.8 adds).

- [ ] `check "shell active"` → `DolDocShell active` appears once.
- [ ] `check "all 31 subsystems"` → `ALL 31 HOLYC SUBSYSTEMS` (updated from 34 in P7.8).
- [ ] `check "exceptions"` → 0 `Synchronous Exception`.
- [ ] `check "undefined identifiers"` → 0 `undefined identifier`.
- [ ] `check "compiler internal errors"` → 0 `COMPILER.HC] internal error`.
- [ ] `check "C JIT errors"` → 0 `[JIT] Error`.
- [ ] `check "unresolved forward refs"` → 0 `unresolved reference`.
- [ ] Boot-log `RASTER: PASS` (single rasterizer boot check, `apps/RasterTile.HC:768`).
- [ ] `SELFTEST: <a>/<b> PASS` with `a == b` and `a >= 74`.
- [ ] `engine parity: <n>/<n> agree, 0 diff` and `PARITY: <n>/<n>`.
- [ ] `TWINS: 5/5`.
- [ ] `SYMS: <n> symbols, 0 unresolved`.
- [ ] `HALCACHE: PASS`, `FSRT: PASS`, `KERNEL:`, `TICK: PASS`, `SCHED: PASS`, `BSOD: PASS`, `SMP: PASS`,
      `SOVEREIGN: PASS`.
- [ ] `RENDER: PASS (golden=0xD28836F)`.
- [ ] `PTRSCALE: PASS`, `ARRAY2D: PASS`, `PTRSCALE2: PASS`, `KHEAP: PASS`, `TEXTURE: PASS`, `FONTS: PASS`,
      `3D: PASS`, `3D-GEARS: PASS`, `SHADING: PASS`, `SHADERVM: PASS`, `MESH: PASS`, `DOLDOC: PASS`,
      `SHELL: PASS`.
- [ ] **New** `GL: PASS`, `TILE: PASS`, `TELEMETRY: PASS`, `BENCH: PASS` (added in P7.8).
- [ ] `CENSUS: PASS` (no count increased; decreases allowed).
- [ ] `SELF-HOST: PASS`.
- [ ] `DETERMINISM: PASS` (golden hash byte-identical on 1 vs 4 cores).
- [ ] Screenshot saved (non-empty PNG).
- [ ] `git bundle create /home/user/project/neo-os.bundle --all` after the final green commit.

---

## 11. Risk register (watch-list)

| Risk | Where | Mitigation |
|---|---|---|
| Golden hash drifts | `RasterTriangleZCore` hoist, NEON fill | Prove the hoist with `RENDER: PASS` before adding tiling; keep NEON fills byte-exact. |
| `3D-GEARS` geometry changes | P7.1 Rotatef / matrix stacks | Keep the per-axis dispatch; re-verify `3D-GEARS: PASS`. |
| SMP tile nondeterminism | P7.4 | Disjoint per-tile scratchpads; SMP test compares to single-core; `DETERMINISM: PASS`. |
| PMU absent under QEMU TCG | P7.6 | `TelemetryPmuProbe()` falls back to `CNTVCT_EL0`; no gate depends on nonzero PMU counts. |
| Census increase | P7.3/P7.6/P7.7 | Static BSS only; run the census after every step. |
| Module count mismatch | P7.6/P7.8 | Update `KernelInit.HC:111` literal **and** `golden-boot.sh:25` together. |
| `bench` blocks the gate | P7.7 | Gate runs `SelfTestBench` (2-phase smoke), never the full 140 s suite. |
| 8-arg cap on batch3/clipper | P7.2/P7.5 | Descriptor structs (`CVirtioBatch`, `CRasterVertex`) passed by pointer. |
| Stale `g_prof`/`g_perf` refs | P7.6 | `rg -n 'g_prof|g_perf|Profiler|PerfOverlay' apps/` must be empty outside `Telemetry.HC`. |
| `tests/jit_golden` re-enters the gate | P7.8 | Keep `golden-boot.sh` free of `run-jit-golden.py`; mark the JSON historical. |

---

*End of P7 execution blueprint. One priority, one clean pass. Land each step green, commit, bundle; never
leave the tree red.*


