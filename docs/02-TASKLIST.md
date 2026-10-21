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

## P1 — Compiler (self-hosting) — ✅ **self-hosting**; script-mode gaps remain

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

### P1.1 — Close the script-mode gaps (the remaining P1 work)
Routing the shell REPL/`run` through `CompilerCompileAndRun` currently yields **61/65** battery cases.
`Shell.HC:732,762` still uses the C JIT for the runtime REPL. Missing capabilities: `(from docs/01-REALITY-AUDIT §B,
docs/master/NEXT-STEPS, P1-DELEGATION §7)`
- [ ] Function-pointer **calls** in script mode.
- [ ] **F64 struct expressions** (`a.x * b.y - …` over F64 members).
- [ ] **Forward structs** in script mode.
- [ ] **Cross-unit interference** (state leaking between successive compiles).
- [ ] Then route `Shell.HC` REPL/`run` through `CompilerCompileAndRun`; retire the C JIT as runtime REPL.

### P1.2 — Remaining compiler capability (only if a module needs it)
`(from 00-MASTER-CONSOLIDATED-PLAN §6 P1.3, 04-UPDATED-PRIORITIES §B, P1-DELEGATION §7)`
- [ ] `#include` **inside `Compiler.HC`** (mirror the C JIT's `expand_includes`).
- [ ] Diagnostics (`file:line`, type errors).
- [ ] `auto` — support or hard-error (currently tokenizes, not consumed → hang risk).
- [ ] Table literals `{…}`; expression/string global initializers (if a module needs them).
- [ ] Global forward cell via `symbols_lookup_or_reserve`.
- [ ] >8-arg calls: currently a **hard error** (`0738474`); optionally spill to stack.

### P1.3 — Retire the C seed (per the no-blob decision)
- [x] Seed decision = **Option A** (C seed confined to `boot/seed/`, commit `708c92a`). **No blob.** `(from 00-MASTER-CONSOLIDATED-PLAN §4/§8)`
- [ ] Later (P2/P8): minimize the seed (Option B) or true self-host-from-source (Option C).

**P1 exit:** script-mode parity (65/65) + REPL on `CompilerCompileAndRun` + golden gate PASS.

---

## P2 — Minimal bootstrap (make everything but the irreducible seed HolyC)

**Truth [PARTIAL]:** C is *physically confined* to `boot/` but *functionally live*. The build has 9 project `.c`
(`boot/main.c`; `boot/seed/{lexer,table,jit_arm64}.c`; `boot/runtime/{kheap,symbols,hal_platform,virtio_blk,redsea}.c`)
plus the vendored `boot/uefi/*.c` (9) and 5 `.S`. `.HC` modules still call **C** for alloc/symbols/block I/O/FS.
`(from docs/master/00-MASTER-CONSOLIDATED-PLAN §6 P2, 02-PRIORITY-PLAN P2, P2-P6-MIGRATION-SPECS §7.1)`

**Irreducible C (the true minimal bootstrap):** UEFI entry+GOP+memmap; a compiler to compile `.HC` (seed);
allocator+symbol table; block driver+FS (to *read* `.HC`). Everything above is already `.HC`.

**Work — retire the C runtime by making the `.HC` twins live, least-circular first:**
- [x] `GetMemoryMap`-derived heap/JIT pool (`7199c3e`).
- [x] C physically confined to `boot/seed` + `boot/runtime` (`708c92a`, `P2b.1`).
- [ ] `HalPlatform.HC` live — **finding:** only load-bearing C HAL function is `hal_flush_cache`; the C `g_hal_*`
      are unused by C. Reduce C HAL to a cache-flush helper.
- [ ] `VirtioBlk.HC` live (own the virtqueue; stop delegating to C).
- [ ] `RedSea.HC` live (own the FS; retire `redsea.c`).
- [ ] `Symbols.HC` live (retire `symbols.c`).
- [ ] `KHeap.HC` live (retire `kheap.c`) — last, most circular.
- [ ] Delete each C file once its `.HC` replacement is load-bearing.
- [ ] **Exit:** C = `boot/main.c` + `boot/uefi/*` + the compiler seed + minimal allocator/symbols/loader.

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
| Golden gate | `scripts/golden-boot.sh` | `GOLDEN BOOT: PASS` |
| Self-host | `scripts/self-host-test.sh` | `SELF-HOST: PASS` |
| Self-test | UART `CompilerSelfTest();` | `All 7 / 7 tests passed` |
| Engine parity | `scripts/p1-parity.sh` | `RESULT: PASS — engines agree` |
| Undefined syms | `scripts/audit-symbols.sh` | 0 undefined, 0 unresolved |
| JIT battery | `scripts/run-jit-golden.py` | 65/65 (script-mode target) |
| Token parity | `scripts/check-token-parity.py` | 71 tokens identical |
| Visual | `scripts/screenshot-diff.py` | no unexpected diff |
| Cycles | `rg "shell_run_command" apps/DolDoc.HC apps/WM.HC` | empty |

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
