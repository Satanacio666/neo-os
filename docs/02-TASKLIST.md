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
