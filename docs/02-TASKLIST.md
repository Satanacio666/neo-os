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

**Bugs surfaced by the expansion (documented, not yet fixed — see doc 04):** 2-D arrays fault (Data Abort);
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
- [x] **Types** — nested structs, `typedef`. Partial: 2-D arrays **fault** (bug), `enum` unsupported.
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

## P2 — Minimal bootstrap (make everything but the irreducible seed HolyC) — 🟡 IN PROGRESS (P2.0 done; **P2.1 NEXT**)

**Objective.** Shrink the C substrate to the *irreducible bootstrap* and make every `.HC` twin the single
source of truth for its subsystem, so "everything above the seed is HolyC".

**Current truth [PARTIAL]** (verified `c78bbdd`): project C = **9** files
`boot/main.c`; `boot/seed/{lexer,table,jit_arm64}.c`; `boot/runtime/{kheap,symbols,hal_platform,virtio_blk,redsea}.c`
(+ vendored `boot/uefi/*.c` ×9, + `boot/uefi/reloc.S`; asm = 5). Live-call census from `apps/*.HC`:
`kmalloc` 52, `kfree` 45, `symbols_register` 29, `symbols_lookup` 23, `hal_flush_cache` 22,
`redsea_read_file` 11, `redsea_write_file` 7, `redsea_list_dir` 2, `symbols_is_defined`/`symbols_var_cell`/
`symbols_sic_cell`/`symbols_count`/`symbols_unresolved_count` 1 each, `jit_compile_and_run` 5 (the seed — stays).
`(from 00-MASTER-CONSOLIDATED-PLAN §6 P2, P2-P6-MIGRATION-SPECS §7.1, 01-REALITY-AUDIT §A)`

**⚠ Correction (verified `68cc2dc`, this session) — the old P2.1 finding was wrong:**
- The 22 `hal_flush_cache` sites in `apps/*.HC` **already bind to the `.HC` implementation**:
  `symbols_lookup("hal_flush_cache")` → `0x77745A40` (JIT pool, next to `HalFlushCache` `0x777457C0`), while
  `symbols_lookup("hal_platform_init")` → `0x78EF0D70` (C binary). The C `hal_flush_cache` registered at
  `boot/main.c:270` is **overwritten** when `HalPlatform.HC` loads (C-JIT `symbols_register` updates the
  address). **No C file calls it** — it is dead code.
- The C `g_hal_*` globals are **NOT** unused by C: `boot/runtime/virtio_blk.c:42-44` uses
  `hal_get_virtio_slots()` / `hal_get_virtio_base(slot)`, which read the C `g_hal_virtio_base/slots/stride`.
  C `virtio_blk` runs at early boot (to read the first `.HC` file) **before** `HalPlatform.HC` loads, so a
  minimal C stub must stay until **P2.2** retires C `virtio_blk`.

**Irreducible C (the target floor):**
1. `boot/main.c` — UEFI entry, GOP, `GetMemoryMap`, jump into `.HC`.
2. `boot/seed/*` — the JIT that compiles `Compiler.HC` (retired only at P8, Option C).
3. `boot/uefi/*` — freestanding libc/syscalls (vendored, not "our" C).
4. The smallest allocator + symbol table + block/FS reader that `Compiler.HC` needs *before* any `.HC`
   module can run — to be shrunk as far as self-hosting allows.

**Circularity rule:** a subsystem's C is retired only after its `.HC` twin is load-bearing; twins are
retired in **reverse dependency order** so nothing depends on a not-yet-live twin.

### P2.0 — Baseline & harness — ✅ DONE (delivered by P0.5)
- [x] Freeze baseline: `golden-boot.sh` PASS, `SELFTEST: 80/80`, `SELF-HOST: PASS`, `p1-parity` PASS. ✅
- [x] **C-call census gate** `scripts/census-c-runtime.sh` + `tests/census-baseline.txt` (fails on any
      increase; wired into `golden-boot.sh`). ✅
- [x] **Twin-liveness probes** (`<X>TwinProbe()`, asserted as `TWINS: 5/5` in the gate). ✅
- [ ] Snapshot `symbols_dump` + heap high-water mark before/after each step for parity. (open)

### P2.1 — HAL: `HalPlatform.HC` owns the platform — ⬜ **NEXT**

**Corrected goal.** `.HC` is the single owner of cache maintenance and the platform-profile table; the C HAL
shrinks to the minimal early-boot stub that C `virtio_blk.c` needs; the dead C cache function is deleted.
Full C-HAL deletion is **deferred to P2.2** (blocked on retiring C `virtio_blk`).

#### P2.1.0 — Baseline & binding proof (do first)
- [ ] Freeze: `golden-boot.sh` PASS (`SELFTEST: 80/80`, parity 54/54, `TWINS: 5/5`, `SYMS: … 0 unresolved`,
      `CENSUS: PASS`, `SELF-HOST: PASS`).
- [ ] Record the binding proof (must show the C cache fn is dead):
      `symbols_lookup("hal_flush_cache")` → JIT pool (`0x77…`); `symbols_lookup("hal_platform_init")` → C (`0x78…`).
- [ ] Confirm C callers: `rg -n 'hal_flush_cache' boot --glob '!boot/uefi/**'` → def + registration only;
      `rg -n 'hal_' boot/runtime/virtio_blk.c` → only `hal_get_virtio_slots`/`hal_get_virtio_base`.

#### P2.1.1 — Delete the dead C cache function
- [ ] Remove `hal_flush_cache` from `boot/runtime/hal_platform.c` (the function) and its declaration from
      `boot/runtime/hal_platform.h`.
- [ ] Remove `symbols_register("hal_flush_cache", …)` from `boot/main.c:270`.
- [ ] Verify: build; boot; `symbols_lookup("hal_flush_cache")` still resolves in the JIT pool (`.HC` owns it);
      gate green.

#### P2.1.2 — Reduce the C HAL to the minimal early-boot stub
- [ ] `boot/runtime/hal_platform.c`: keep only `g_hal_virtio_base/slots/stride`, `hal_platform_init()`
      (hardcode QEMU virt: base `0x0A000000`, slots `32`, stride `0x200`), and the two virtio accessors.
      Drop the uart/gicd/gicc globals + getters, the RPi4/RPi5 profiles, `hal_get_platform`/`hal_set_platform`/
      `hal_platform_select`, and `hal_flush_cache`.
- [ ] `boot/runtime/hal_platform.h`: shrink to what `virtio_blk.c` needs
      (`hal_platform_init`, `hal_get_virtio_base`, `hal_get_virtio_slots`); drop the rest.
- [ ] Verify: build (no missing symbols); boot reaches shell; `virtio_blk` still finds the block device and
      RedSea loads all modules; gate green.

#### P2.1.3 — `.HC` fully owns the path; de-duplicate `HcFlushCache`
- [ ] Confirm `apps/HalPlatform.HC` owns cache maintenance (`HalFlushCache`: `dc civac`+`ic ivau`+`dsb`+`isb`),
      the five platform profiles, `g_hal_*`, and `HalSystemReset`.
- [ ] Simplify `apps/Compiler.HC:HcFlushCache` to delegate to `HalFlushCache(addr, size)` (drop the duplicated
      inline flush) so there is exactly one cache-maintenance implementation.
- [ ] Verify: `SELF-HOST: PASS`; battery `80/80` (JIT-emitted code still flushes and executes).

#### P2.1.4 — Census reclassification
- [ ] Remove `hal_flush_cache` from `SYMBOLS` in `scripts/census-c-runtime.sh` (it is a `.HC` symbol now);
      re-baseline `tests/census-baseline.txt` via `--write`.
- [ ] Verify: `CENSUS: PASS` with `hal_flush_cache` no longer listed.

#### P2.1.5 — Hardening
- [ ] Add a direct cache-coherency check to `apps/SelfTest.HC` (allocate a buffer, write, `HalFlushCache`,
      read back, assert) — `HalTwinProbe` already covers liveness.
- [ ] Keep `HalSelfTest()` reachable (`HalPlatformSelfTest()`), and (optional) assert it from the in-guest suite.

#### P2.1.6 — Docs + gate + commit + bundle
- [ ] Update `01-REALITY-AUDIT` (C HAL inventory + the correction), `00-MASTER-PLAN` (P2 row), `04` if needed.
- [ ] `golden-boot.sh` PASS; `git commit`; `git bundle create /home/user/project/neo-os.bundle --all`.

**P2.1 exit (Definition of Done):** `hal_flush_cache` has **no C implementation**; `boot/runtime/hal_platform.c`
is a ~30-line early-boot stub (only the VirtIO MMIO constants C `virtio_blk.c` needs); `.HC` owns cache +
platform; the census no longer lists `hal_flush_cache`; gate green. **Risk: low.**
**Rollback:** `git checkout --` the touched files (no committed state depends on the change).
**Deferred to P2.2:** deleting the C HAL stub entirely (blocked on retiring C `virtio_blk.c`).

### P2.2 — VirtioBlk: `VirtioBlk.HC` owns the virtqueue
- [ ] Port virtqueue setup/notify/poll + read/write from `boot/runtime/virtio_blk.c` into `VirtioBlk.HC`
      (exists, 13.6 KB, currently delegating); own the descriptor/avail/used rings.
- [ ] Verify: `redsea_read_file` of a known file returns identical bytes; parity PASS. **Risk:** medium.

### P2.3 — RedSea: `RedSea.HC` owns the filesystem
- [ ] Port the RedSea directory/sector logic from `boot/runtime/redsea.c` into `RedSea.HC`; retire
      `redsea_read_file`/`redsea_write_file`/`redsea_list_dir` C-calls from `.HC` (11/6/2 sites).
- [ ] Verify: `save`/`run`/`cat`/`hcrun` round-trip; self-host PASS. **Risk:** medium.

### P2.4 — Symbols: `Symbols.HC` owns the table
- [ ] Port `symbols_register`/`lookup`/`lookup_entry`/`lookup_or_reserve`/`is_defined`/`is_func`/`is_var`/
      `var_cell`/`sic_cell` into `Symbols.HC` (unify the 256 vs 1024 bucket split).
- [ ] Verify: 0 undefined / 0 unresolved at boot; parity PASS; self-host PASS.
- **Risk:** high — the compiler uses the table. Keep `symbols.c` until the `.HC` table passes parity.

### P2.5 — KHeap: `KHeap.HC` owns the allocator (last, most circular)
- [ ] Port `kmalloc`/`kfree` (+ `HEAP_CANARY`/`CHeapBlock`) into `KHeap.HC` (52/45 call sites).
- [ ] Bootstrap: keep a tiny C bump allocator as the seed arena; switch to `KHeap.HC` once it can allocate.
- [ ] Verify: no double-free/canary faults under stress. **Risk:** highest (rollback: flag-gated flip).

### P2.6 — Seed minimization & C deletion
- [ ] Delete each `boot/runtime/*.c` once its twin is live and its census is 0.
- [ ] Reduce `boot/seed/` to the minimum that still compiles `Compiler.HC` (Option B); Option C deferred to P8.
- [ ] Update `Makefile` `SRCS_C`; keep `boot/uefi/*` (vendored).
- [ ] **Exit:** `SRCS_C` = `boot/main.c` + `boot/seed/*` + `boot/uefi/*`; 0 `.HC`→C runtime calls.

### P2 — 200% hardening (make it bullet-proof)
- [ ] **C-call census = 0** for every retired subsystem, enforced by `scripts/census-c-runtime.sh`.
- [ ] **Twin-liveness tests** for all five twins, run inside `golden-boot.sh`.
- [ ] **Allocator stress:** malloc/free churn, fragmentation, exhaustion, double-free (canary) detection.
- [ ] **Symbol stress:** register/lookup 4096+ names, collisions, redefinition, forward refs.
- [ ] **FS stress:** create/read/overwrite/delete many files; large files; sector-boundary reads.
- [ ] **Determinism:** identical boot symbol dump + heap high-water mark across repeated boots.
- [ ] **Per-module parity:** `p1-parity --per-module` PASS for all 34 modules.
- [ ] **Docs:** update `01-REALITY-AUDIT`/`00-MASTER-PLAN` to the new C inventory; keep the census gate.

**P2 exit (Definition of Done):**
- `SRCS_C` has no project runtime `.c` (only `boot/main.c` + `boot/seed/*` + vendored `boot/uefi/*`).
- Every `.HC` twin is load-bearing; the C-call census is 0 for alloc/symbols/FS/HAL.
- `golden-boot.sh` PASS (with twin-liveness), battery 74/74, `SELF-HOST: PASS`, `p1-parity` PASS. Commit + bundle.

**Open questions (decide at the P2 boundary):** seed Option B (minimize) vs Option C (true HolyC source
bootstrap); keep `boot/uefi` as vendored libc vs port it; the allocator's bootstrap-arena design.

---

## P3 — Kernel correctness (make it a real kernel)

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P3, 02-PRIORITY-PLAN P3, P2-P6-MIGRATION-SPECS §7, 01-VERIFIED-TRUTH §2.2)`
- [ ] **Allocator:** one allocator (C `kheap.c` live; `KHeap.HC` `KMalloc/KFree` dead). Remove `HEAP_CANARY`/`CHeapBlock` dup.
- [ ] **Symbols:** one table (C `symbols.c`, 1024 buckets, live; `Symbols.HC` 256, fallback). Port `SymCanonicalMatch`/Pascal↔snake helpers in.
- [ ] **HAL:** one set of `g_hal_*` globals; add missing platforms + `g_hal_timer_freq`.
- [ ] **Timer:** arm `CNTP_TVAL_EL0`/`CNTV_TVAL_EL0`; register timer IRQ (`GicRegisterHandler(27, TimerTick)`).
- [ ] **GIC:** dedupe `g_hal_gicd/gicc_base`; register the timer handler at boot.
- [ ] **Scheduler:** wire `cpu_switch_context` (assembled+registered, **zero callers**); real run queue; `task_yield` from the tick; make it preemptive.
- [ ] **SMP:** per-core run queues; drop the silent local-execution fallback; delete `SmpWorkerLoop1/2/3` copy-paste; idle secondaries `wfe`/`sev`.
- [ ] **Exceptions:** fix `vectors.S` hardcoded `x3=1` (kernel faults must reach the BSOD); kill the `while(1)__wfe()` re-entrancy hang; clean ESR/FAR/ELR dump.
- [ ] **Globals:** dedupe `g_kernel_booting` (**redeclared in 14 files** — start here), `g_hal_*`, `top_print_doldoc`.
- [ ] **Exit:** a timer IRQ fires; preemptive scheduling works; memory is discovered, not hardcoded.

---

## P4 — Rendering unification (one pipeline)

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P4, 02-PRIORITY-PLAN P4, P2-P6-MIGRATION-SPECS §1–§3, 01-VERIFIED-TRUTH §2.3)`
- [ ] **Merge → `GfxDevice.HC`:** `Render` + `GfxBackend` + `VirtioGpu` + Compositor damage/present. One target resolver, one damage, one present.
- [ ] **Fix `VirtioGpu` truncated commands:** `RESOURCE_CREATE_2D` 40→32 (`VirtioGpu.HC:345`), `TRANSFER_TO_HOST_2D` 56→48 (`:417`); real `ATTACH_BACKING`.
- [ ] **One tiled NEON rasterizer:** promote `RasterTile.RasterTriangleZ` (real per-pixel Z); wire `HolyGLSubmitTriangle` to it; delete `HolyGLDrawTriangleZ` (`z_avg`), `gfx_draw_triangle_fill`, dead `TileRasterTri`/`TileClear`; one Z-buffer.
- [ ] **Real features:** per-pixel Z, perspective-correct **textures** (sample stored UVs), **SDF**, small **fragment-shader VM**; **NEON** (4 px/op); **SMP tiles** actually dispatched.
- [ ] **Merge → `Fonts.HC`:** `FontMono` + `FontVector` + Render's `gfx_draw_char`; drop the mock SFNT.
- [ ] **Themes:** keep `g_theme`; move its owner out of Compositor; delete Compositor damage/present.
- [ ] Delete ~60 dead fns + write-only state (`raster_engine`, `tile_size`, `zprecision`, `culling`, tile map). Determinism test (1 core vs N).
- [ ] **Exit:** a triangle, textured quad, SDF glyph, and shaded mesh all render through one path with real Z.

---

## P5 — DolDoc (real TempleOS model + dissolution)

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P5, 02-PRIORITY-PLAN P5, P2-P6-MIGRATION-SPECS §5, 03-design §3.2–3.4)`
- [ ] **Rewrite `DolDoc.HC` → CDoc/CTree** of entries + **per-char attributes**; delete `g_doc_chars/fg/bg`, `g_doc_link_idx`, `g_hist_chars`.
- [ ] **Full two-letter tag set:** `TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI` — incl. `$MA` macros, `$DA` forms, `$AN` anchors, `$ID` trees, typed `$LK` links, word-wrap.
- [ ] **Windows are documents:** `$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`; **dissolve `WM.HC`**; **dissolve `Compositor.HC`**.
- [ ] **Reactive cells** (generalize `DolDocPatchTarget`); RedSea document persistence; the DolDoc reference is a DolDoc (dogfood).
- [ ] Fix `g_doc_dirty_mask` (`((U64)1 << r)`).
- [ ] **Exit:** a doc with text/link/button/slider/form/tree/3D-scene/shader renders + responds; no char grid.

---

## P6 — Shell (action executor over a CDoc)

`(from 00-MASTER-CONSOLIDATED-PLAN §6 P6, P2-P6-MIGRATION-SPECS §6)`
- [ ] **Action protocol:** documents emit `Action{Run,Open,Set,Clone,Focus}`; the shell executes.
- [ ] **Command registry:** fill the dead `shell_register_cmd` (`Shell.HC:42`, zero callers); replace the if/else ladder (`Shell.HC:467-751`).
- [ ] **Break all cycles** (`DolDoc→Shell`, `WM→Shell`, `WM↔Compositor`).
- [ ] **Shell buffer is a CDoc**; keep the input/event loop.
- [ ] Fold `top`/`edit`/`filer` into shell-backed docs.
- [ ] **Exit:** no cycles; shell output *is* a CDoc.

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
| In-guest battery | inside the gate: `selftest` (one command) | `SELFTEST: 80/80 PASS` |
| In-guest parity | inside the gate: `selftest` | `PARITY: 54/54`, `0 diff` |
| Twin-liveness | inside the gate: `selftest` | `TWINS: 5/5` |
| Symbol audit | inside the gate: `selftest` | `SYMS: <n> symbols, 0 unresolved` |
| C-runtime census | `scripts/census-c-runtime.sh` | `CENSUS: PASS` |
| Self-host | `scripts/self-host-test.sh` | `SELF-HOST: PASS` |
| Module parity | `scripts/p1-parity.sh` | `RESULT: PASS — engines agree` |
| Undefined syms | `scripts/audit-symbols.sh` | 0 undefined, 0 unresolved |
| Legacy battery | `scripts/run-jit-golden.py` | 74/74 (superseded by `selftest`) |
| Token parity | `scripts/check-token-parity.py` | 71 tokens identical |
| Visual | `scripts/screenshot-diff.py` | no unexpected diff |
| Cycles | `rg "shell_run_command" apps/DolDoc.HC apps/WM.HC` | empty |

> `tests/jit_golden/cases.json` holds **75 cases** (1 `known`), i.e. **74 active**; the in-guest suite is
> those 74 plus **6 new** coverage cases = **80 checks**. The earlier "65/65" figures in P0/P1 were stale.

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
